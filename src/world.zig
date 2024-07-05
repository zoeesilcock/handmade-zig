const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const std = @import("std");

const Vector2 = math.Vector2;

const TILE_CHUNK_SAFE_MARGIN = std.math.maxInt(i32) / 64;
const TILE_CHUNK_UNINITIALIZED = std.math.maxInt(i32);
const TILES_PER_CHUNK = 16;

pub const World = struct {
    tile_side_in_meters: f32,
    chunk_side_in_meters: f32,

    first_free: ?*WorldEntityBlock,

    chunk_hash: [4096]WorldChunk,
};

pub const WorldChunk = struct {
    x: i32,
    y: i32,
    z: i32,

    first_block: WorldEntityBlock,

    next_in_hash: ?*WorldChunk = null,
};

pub const WorldEntityBlock = struct {
    entity_count: u32,
    low_entity_indices: [TILES_PER_CHUNK]u32,
    next: ?*WorldEntityBlock,
};

pub const WorldDifference = struct {
    xy: Vector2 = Vector2.zero(),
    z: f32 = 0,
};

pub const WorldPosition = struct {
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,

    // Position relative to the center of the chunk.
    offset: Vector2,

    pub fn zero() WorldPosition {
        return WorldPosition{
            .chunk_x = 0,
            .chunk_y = 0,
            .chunk_z = 0,
            .offset = Vector2.zero(),
        };
    }

    pub fn nullPosition() WorldPosition {
        return WorldPosition{
            .chunk_x = TILE_CHUNK_UNINITIALIZED,
            .chunk_y = 0,
            .chunk_z = 0,
            .offset = Vector2.zero(),
        };
    }

    pub fn isValid(self: *WorldPosition) bool {
        return self.chunk_x != TILE_CHUNK_UNINITIALIZED;
    }
};

pub fn initializeWorld(world: *World, tile_side_in_meters: f32) void {
    world.tile_side_in_meters = tile_side_in_meters;
    world.chunk_side_in_meters = TILES_PER_CHUNK * tile_side_in_meters;
    world.first_free = null;

    for (&world.chunk_hash) |*chunk| {
        chunk.x = TILE_CHUNK_UNINITIALIZED;
        chunk.y = TILE_CHUNK_UNINITIALIZED;
        chunk.z = TILE_CHUNK_UNINITIALIZED;
        chunk.first_block.entity_count = 0;
    }
}

inline fn isCanonical(world: *World, relative: f32) bool {
    return ((relative >= -0.5 * world.chunk_side_in_meters) and
        (relative <= 0.5 * world.chunk_side_in_meters));
}

inline fn isVector2Canonical(world: *World, offset: Vector2) bool {
    return (isCanonical(world, offset.x()) and isCanonical(world, offset.y()));
}

pub fn areInSameChunk(world: *World, a: *WorldPosition, b: *WorldPosition) bool {
    std.debug.assert(isVector2Canonical(world, a.offset));
    std.debug.assert(isVector2Canonical(world, b.offset));

    return a.chunk_x == b.chunk_x and
        a.chunk_y == b.chunk_y and
        a.chunk_z == b.chunk_z;
}

pub fn getWorldChunk(
    world: *World,
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,
    opt_memory_arena: ?*shared.MemoryArena,
) ?*WorldChunk {
    std.debug.assert(chunk_x > -TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_x > -TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_y > -TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_x < TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_y < TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_z < TILE_CHUNK_SAFE_MARGIN);

    const hash_value: u32 = @bitCast(19 *% chunk_x +% 7 *% chunk_y +% 3 *% chunk_z);
    const hash_slot = @as(usize, @intCast(hash_value)) & (world.chunk_hash.len - 1);
    std.debug.assert(hash_slot < world.chunk_hash.len);

    var tile_chunk: ?*WorldChunk = &world.chunk_hash[hash_slot];
    while (tile_chunk) |chunk| {
        if ((chunk_x == chunk.x) and
            (chunk_y == chunk.y) and
            (chunk_z == chunk.z))
        {
            break;
        }

        if (opt_memory_arena) |memory_arena| {
            if (chunk.x != TILE_CHUNK_UNINITIALIZED and chunk.next_in_hash == null) {
                chunk.next_in_hash = shared.pushStruct(memory_arena, WorldChunk);
                tile_chunk = chunk.next_in_hash;
                tile_chunk.?.x = TILE_CHUNK_UNINITIALIZED;

                continue;
            }
        }

        if (opt_memory_arena) |_| {
            if (chunk.x == TILE_CHUNK_UNINITIALIZED) {
                chunk.x = chunk_x;
                chunk.y = chunk_y;
                chunk.z = chunk_z;

                chunk.next_in_hash = null;

                break;
            }
        }

        tile_chunk = chunk.next_in_hash;
    }

    return tile_chunk;
}
pub fn changeEntityLocation(
    memory_arena: *shared.MemoryArena,
    world: *World,
    low_entity: *shared.LowEntity,
    low_entity_index: u32,
    opt_old_position: ?*WorldPosition,
    new_position: *WorldPosition,
) void {
    changeEntityLocationRaw(
        memory_arena,
        world,
        low_entity_index,
        opt_old_position,
        new_position,
    );

    low_entity.position = new_position.*;
}

pub fn changeEntityLocationRaw(
    memory_arena: *shared.MemoryArena,
    world: *World,
    low_entity_index: u32,
    opt_old_position: ?*WorldPosition,
    new_position: *WorldPosition,
) void {
    std.debug.assert(opt_old_position == null or opt_old_position.?.isValid());
    std.debug.assert(new_position.isValid());

    if (opt_old_position) |old_position| {
        if (!areInSameChunk(world, old_position, new_position)) {
            // Pull the entity out of it's current block.
            const opt_chunk = getWorldChunk(
                world,
                old_position.chunk_x,
                old_position.chunk_y,
                old_position.chunk_z,
                memory_arena,
            );

            std.debug.assert(opt_chunk != null);

            if (opt_chunk) |old_chunk| {
                const first_block = &old_chunk.first_block;

                // Look through all the blocks.
                var opt_block: ?*WorldEntityBlock = &old_chunk.first_block;
                outer: while (opt_block) |block| : (opt_block = block.next) {
                    // Look through the entity indices in the block.
                    for (block.low_entity_indices, 0..) |_, index| {
                        if (low_entity_index == index) {
                            std.debug.assert(first_block.entity_count > 0);

                            // Remove the entity from the block.
                            block.entity_count -= 1;
                            block.low_entity_indices[index] =
                                first_block.low_entity_indices[first_block.entity_count];

                            if (first_block.entity_count == 0) {
                                // Last entity in the block, remove this block.
                                if (first_block.next) |next_block| {
                                    // Overwrite the empty block with the next block.
                                    first_block.* = next_block.*;

                                    // Free the empty block.
                                    next_block.next = world.first_free;
                                    world.first_free = next_block;
                                }
                            }

                            break :outer;
                        }
                    }
                }
            }
        }
    }

    // Insert the entity into it's new entity block.
    const opt_chunk = getWorldChunk(
        world,
        new_position.chunk_x,
        new_position.chunk_y,
        new_position.chunk_z,
        memory_arena,
    );
    if (opt_chunk) |new_chunk| {
        const block = &new_chunk.first_block;

        if (block.entity_count == block.low_entity_indices.len) {
            // Out of space, get a new block.
            var old_block: ?*WorldEntityBlock = null;
            const opt_free_block = world.first_free;

            if (opt_free_block) |free_block| {
                // Use the free block.
                world.first_free = free_block.next;
                old_block = free_block;
            } else {
                // No free blocks, create a new block.
                old_block = shared.pushStruct(memory_arena, WorldEntityBlock);
            }

            // Copy the existing block into the old block position.
            old_block.?.* = block.*;
            block.next = old_block;
            block.entity_count = 0;
        }

        // Add the entity to the block.
        std.debug.assert(block.entity_count < block.low_entity_indices.len);
        block.low_entity_indices[block.entity_count] = low_entity_index;
        block.entity_count += 1;
    }
}

pub inline fn recannonicalizeCoordinate(world: *World, tile_abs: *i32, tile_rel: *const f32) f32 {
    const offset = intrinsics.roundReal32ToInt32(tile_rel.* / world.chunk_side_in_meters);

    tile_abs.* +%= offset;
    const result = tile_rel.* - @as(f32, @floatFromInt(offset)) * world.chunk_side_in_meters;

    std.debug.assert(isCanonical(world, result));

    return result;
}

pub fn mapIntoChunkSpace(world: *World, base_position: WorldPosition, offset: Vector2) WorldPosition {
    var result = base_position;

    result.offset = result.offset.plus(offset);
    result.offset = Vector2.new(
        recannonicalizeCoordinate(world, &result.chunk_x, &result.offset.x()),
        recannonicalizeCoordinate(world, &result.chunk_y, &result.offset.y()),
    );

    return result;
}

pub inline fn chunkPositionFromTilePosition(
    world: *World,
    abs_tile_x: i32,
    abs_tile_y: i32,
    abs_tile_z: i32,
) WorldPosition {
    var result = WorldPosition.zero();

    result.chunk_x = @divFloor(abs_tile_x, TILES_PER_CHUNK);
    result.chunk_y = @divFloor(abs_tile_y, TILES_PER_CHUNK);
    result.chunk_z = @divFloor(abs_tile_z, TILES_PER_CHUNK);

    result.offset = Vector2.new(
        @as(f32, @floatFromInt((abs_tile_x - TILES_PER_CHUNK / 2) -
                (result.chunk_x * TILES_PER_CHUNK))) * world.tile_side_in_meters,
        @as(f32, @floatFromInt((abs_tile_y - TILES_PER_CHUNK / 2) -
                (result.chunk_y * TILES_PER_CHUNK))) * world.tile_side_in_meters,
    );

    std.debug.assert(isVector2Canonical(world, result.offset));

    return result;
}

pub fn subtractPositions(world: *World, a: *WorldPosition, b: *WorldPosition) WorldDifference {
    var result = WorldDifference{};

    var tile_diff_xy = Vector2.new(
        @as(f32, @floatFromInt(a.chunk_x)) - @as(f32, @floatFromInt(b.chunk_x)),
        @as(f32, @floatFromInt(a.chunk_y)) - @as(f32, @floatFromInt(b.chunk_y)),
    );
    const tile_diff_z = @as(f32, @floatFromInt(a.chunk_z)) - @as(f32, @floatFromInt(b.chunk_z));

    result.xy = tile_diff_xy.scaledTo(world.chunk_side_in_meters).plus(a.offset.minus(b.offset));
    result.z = world.chunk_side_in_meters * tile_diff_z;

    return result;
}

pub fn centeredChunkPoint(chunk_x: i32, chunk_y: i32, chunk_z: i32) WorldPosition {
    return WorldPosition{
        .chunk_x = chunk_x,
        .chunk_y = chunk_y,
        .chunk_z = chunk_z,
        .offset = Vector2.zero(),
    };
}
