const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const sim = @import("sim.zig");
const std = @import("std");

const Vector3 = math.Vector3;

const TILE_CHUNK_SAFE_MARGIN = std.math.maxInt(i32) / 64;
const TILE_CHUNK_UNINITIALIZED = std.math.maxInt(i32);
const TILES_PER_CHUNK = 8;

pub const World = extern struct {
    chunk_dimension_in_meters: Vector3,

    first_free: ?*WorldEntityBlock,

    chunk_hash: [4096]WorldChunk,
};

pub const WorldChunk = extern struct {
    x: i32,
    y: i32,
    z: i32,

    first_block: WorldEntityBlock,

    next_in_hash: ?*WorldChunk = null,

    pub fn centeredPoint(self: *const WorldChunk) WorldPosition {
        return centeredChunkPoint(self.x, self.y, self.z);
    }
};

pub const WorldEntityBlock = extern struct {
    entity_count: u32,
    low_entity_indices: [TILES_PER_CHUNK]u32,
    next: ?*WorldEntityBlock,
};

pub const WorldPosition = extern struct {
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,

    // Position relative to the center of the chunk.
    offset: Vector3,

    pub fn zero() WorldPosition {
        return WorldPosition{
            .chunk_x = 0,
            .chunk_y = 0,
            .chunk_z = 0,
            .offset = Vector3.zero(),
        };
    }

    pub fn nullPosition() WorldPosition {
        return WorldPosition{
            .chunk_x = TILE_CHUNK_UNINITIALIZED,
            .chunk_y = 0,
            .chunk_z = 0,
            .offset = Vector3.zero(),
        };
    }

    pub fn isValid(self: *const WorldPosition) bool {
        return self.chunk_x != TILE_CHUNK_UNINITIALIZED;
    }
};

pub fn initializeWorld(world: *World, chunk_dimension_in_meters: Vector3) void {
    world.chunk_dimension_in_meters = chunk_dimension_in_meters;

    world.first_free = null;

    for (&world.chunk_hash) |*chunk| {
        chunk.x = TILE_CHUNK_UNINITIALIZED;
        chunk.y = TILE_CHUNK_UNINITIALIZED;
        chunk.z = TILE_CHUNK_UNINITIALIZED;
        chunk.first_block.entity_count = 0;
    }
}

fn isCanonical(chunk_dimension: f32, relative: f32) bool {
    const epsilon = 0.01;
    return ((relative >= -(0.5 * chunk_dimension + epsilon)) and
        (relative <= (0.5 * chunk_dimension + epsilon)));
}

pub fn isVector3Canonical(world: *World, offset: Vector3) bool {
    return (isCanonical(world.chunk_dimension_in_meters.x(), offset.x()) and
        isCanonical(world.chunk_dimension_in_meters.y(), offset.y()) and
        isCanonical(world.chunk_dimension_in_meters.z(), offset.z()));
}

pub fn areInSameChunk(world: *World, a: *const WorldPosition, b: *const WorldPosition) bool {
    std.debug.assert(isVector3Canonical(world, a.offset));
    std.debug.assert(isVector3Canonical(world, b.offset));

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
    var timed_block = shared.TimedBlock.beginFunction(@src(), .GetWorldChunk);
    defer timed_block.end();

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
                chunk.next_in_hash = memory_arena.pushStruct(WorldChunk);
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
    new_position: WorldPosition,
) void {
    var timed_block = shared.TimedBlock.beginFunction(@src(), .ChangeEntityLocation);
    defer timed_block.end();

    var opt_old_position: ?*WorldPosition = null;
    var opt_new_position: ?*WorldPosition = null;

    if (!low_entity.sim.isSet(sim.SimEntityFlags.Nonspatial.toInt()) and low_entity.position.isValid()) {
        opt_old_position = &low_entity.position;
    }

    if (new_position.isValid()) {
        opt_new_position = @constCast(&new_position);
    }

    changeEntityLocationRaw(
        memory_arena,
        world,
        low_entity_index,
        opt_old_position,
        opt_new_position,
    );

    if (new_position.isValid()) {
        low_entity.position = new_position;
        low_entity.sim.clearFlags(sim.SimEntityFlags.Nonspatial.toInt());
    } else {
        low_entity.position = WorldPosition.nullPosition();
        low_entity.sim.addFlags(sim.SimEntityFlags.Nonspatial.toInt());
    }
}

pub fn changeEntityLocationRaw(
    memory_arena: *shared.MemoryArena,
    world: *World,
    low_entity_index: u32,
    opt_old_position: ?*WorldPosition,
    opt_new_position: ?*WorldPosition,
) void {
    var timed_block = shared.TimedBlock.beginFunction(@src(), .ChangeEntityLocationRaw);
    defer timed_block.end();

    std.debug.assert(opt_old_position == null or opt_old_position.?.isValid());
    std.debug.assert(opt_new_position == null or opt_new_position.?.isValid());

    var in_same_chunk = false;
    if (opt_new_position) |new_position| {
        if (opt_old_position) |old_position| {
            in_same_chunk = areInSameChunk(world, old_position, new_position);
        }
    }

    if (!in_same_chunk) {
        if (opt_old_position) |old_position| {
            // Pull the entity out of it's current block.
            const opt_chunk = getWorldChunk(
                world,
                old_position.chunk_x,
                old_position.chunk_y,
                old_position.chunk_z,
                null,
            );

            std.debug.assert(opt_chunk != null);

            if (opt_chunk) |old_chunk| {
                const first_block = &old_chunk.first_block;

                // Look through all the blocks.
                var opt_block: ?*WorldEntityBlock = &old_chunk.first_block;
                outer: while (opt_block) |block| : (opt_block = block.next) {
                    // Look through the entity indices in the block.
                    var index: u32 = 0;
                    while (index < block.entity_count) : (index += 1) {
                        if (low_entity_index == block.low_entity_indices[index]) {
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

        if (opt_new_position) |new_position| {
            // Insert the entity into it's new entity block.
            const opt_chunk = getWorldChunk(
                world,
                new_position.chunk_x,
                new_position.chunk_y,
                new_position.chunk_z,
                memory_arena,
            );

            std.debug.assert(opt_chunk != null);

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
                        old_block = memory_arena.pushStruct(WorldEntityBlock);
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
    }
}

pub fn recannonicalizeCoordinate(chunk_dimension: f32, tile_abs: *i32, tile_rel: *const f32) f32 {
    const epsilon = 0.0001;
    const offset = intrinsics.roundReal32ToInt32((tile_rel.* + epsilon) / chunk_dimension);

    tile_abs.* +%= offset;
    const result = tile_rel.* - @as(f32, @floatFromInt(offset)) * chunk_dimension;

    std.debug.assert(isCanonical(chunk_dimension, result));

    return result;
}

pub fn mapIntoChunkSpace(world: *World, base_position: WorldPosition, offset: Vector3) WorldPosition {
    var result = base_position;

    result.offset = result.offset.plus(offset);
    result.offset = Vector3.new(
        recannonicalizeCoordinate(world.chunk_dimension_in_meters.x(), &result.chunk_x, &result.offset.x()),
        recannonicalizeCoordinate(world.chunk_dimension_in_meters.y(), &result.chunk_y, &result.offset.y()),
        recannonicalizeCoordinate(world.chunk_dimension_in_meters.z(), &result.chunk_z, &result.offset.z()),
    );

    return result;
}

pub fn subtractPositions(world: *World, a: *const WorldPosition, b: *const WorldPosition) Vector3 {
    var tile_diff = Vector3.new(
        @as(f32, @floatFromInt(a.chunk_x)) - @as(f32, @floatFromInt(b.chunk_x)),
        @as(f32, @floatFromInt(a.chunk_y)) - @as(f32, @floatFromInt(b.chunk_y)),
        @as(f32, @floatFromInt(a.chunk_z)) - @as(f32, @floatFromInt(b.chunk_z)),
    );

    return tile_diff.hadamardProduct(world.chunk_dimension_in_meters).plus(a.offset.minus(b.offset));
}

pub fn centeredChunkPoint(chunk_x: i32, chunk_y: i32, chunk_z: i32) WorldPosition {
    return WorldPosition{
        .chunk_x = chunk_x,
        .chunk_y = chunk_y,
        .chunk_z = chunk_z,
        .offset = Vector3.zero(),
    };
}
