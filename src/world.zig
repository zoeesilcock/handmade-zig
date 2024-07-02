const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const std = @import("std");

const TILE_CHUNK_SAFE_MARGIN = std.math.maxInt(i32) / 64;
const TILE_CHUNK_UNINITIALIZED = std.math.maxInt(i32);

pub const World = struct {
    chunk_shift: i32,
    chunk_mask: i32,
    chunk_dim: i32,

    tile_side_in_meters: f32,

    chunk_hash: [4096]WorldChunk,
};

pub const WorldChunk = struct {
    x: i32,
    y: i32,
    z: i32,

    first_block: TileEntityBlock,

    next_in_hash: ?*WorldChunk = null,
};

pub const TileEntityBlock = struct {
    entity_count: u32,
    low_entity_indexes: [16]u32,
    next: ?*TileEntityBlock,
};

// const TileChunkPosition = struct {
//     tile_chunk_x: i32,
//     tile_chunk_y: i32,
//     tile_chunk_z: i32,
//
//     rel_tile_x: i32,
//     rel_tile_y: i32,
// };

pub const WorldDifference = struct {
    xy: math.Vector2 = math.Vector2{},
    z: f32 = 0,
};

pub const WorldPosition = struct {
    // Fixed point tile locations.
    // The high bits are the tile chunk index.
    // The low bits are the tile index in the chunk.
    abs_tile_x: i32,
    abs_tile_y: i32,
    abs_tile_z: i32,

    // Position relative to the center of the current tile.
    offset: math.Vector2,

    pub fn zero() WorldPosition {
        return WorldPosition{
            .abs_tile_x = 0,
            .abs_tile_y = 0,
            .abs_tile_z = 0,
            .offset = math.Vector2.zero(),
        };
    }
};

pub fn initializeWorld(world: *World, tile_side_in_meters: f32) void {
    world.chunk_shift = 4;
    world.chunk_dim = (@as(i32, 1) << @as(u5, @intCast(world.chunk_shift)));
    world.chunk_mask = (@as(i32, 1) << @as(u5, @intCast(world.chunk_shift))) - 1;
    world.tile_side_in_meters = tile_side_in_meters;

    for (&world.chunk_hash) |*chunk| {
        chunk.x = TILE_CHUNK_UNINITIALIZED;
    }
}

fn getTileChunk(
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

    const hash_value = 19 *% chunk_x +% 7 *% chunk_y +% 3 *% chunk_z;
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

// inline fn getChunkPositionFor(world: *World, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) TileChunkPosition {
//     return TileChunkPosition{
//         .chunk_x = abs_tile_x >> @as(u5, @intCast(world.chunk_shift)),
//         .chunk_y = abs_tile_y >> @as(u5, @intCast(world.chunk_shift)),
//         .chunk_z = abs_tile_z,
//         .rel_tile_x = abs_tile_x & world.chunk_mask,
//         .rel_tile_y = abs_tile_y & world.chunk_mask,
//     };
// }

pub inline fn recannonicalizeCoordinate(world: *World, tile_abs: *i32, tile_rel: *f32) void {
    // Calculate new tile position pased on the tile relative position.
    const offset = intrinsics.roundReal32ToInt32(tile_rel.* / world.tile_side_in_meters);
    tile_abs.* +%= offset;
    tile_rel.* -= @as(f32, @floatFromInt(offset)) * world.tile_side_in_meters;

    // Check that the new relative position is within the tile size.
    std.debug.assert(tile_rel.* >= -0.5 * world.tile_side_in_meters);
    std.debug.assert(tile_rel.* <= 0.5 * world.tile_side_in_meters);
}

pub fn mapIntoTileSpace(world: *World, base_position: WorldPosition, offset: math.Vector2) WorldPosition {
    var result = base_position;

    _ = result.offset.addSet(offset);
    recannonicalizeCoordinate(world, &result.abs_tile_x, &result.offset.x);
    recannonicalizeCoordinate(world, &result.abs_tile_y, &result.offset.y);

    return result;
}

pub fn areOnSameTile(a: *WorldPosition, b: *WorldPosition) bool {
    return a.abs_tile_x == b.abs_tile_x and
        a.abs_tile_y == b.abs_tile_y and
        a.abs_tile_z == b.abs_tile_z;
}

pub fn subtractPositions(world: *World, a: *WorldPosition, b: *WorldPosition) WorldDifference {
    var result = WorldDifference{};

    var tile_diff_xy = math.Vector2{
        .x = @as(f32, @floatFromInt(a.abs_tile_x)) - @as(f32, @floatFromInt(b.abs_tile_x)),
        .y = @as(f32, @floatFromInt(a.abs_tile_y)) - @as(f32, @floatFromInt(b.abs_tile_y)),
    };
    const tile_diff_z = @as(f32, @floatFromInt(a.abs_tile_z)) - @as(f32, @floatFromInt(b.abs_tile_z));

    result.xy = tile_diff_xy.scale(world.tile_side_in_meters).add(a.offset.subtract(b.offset));
    result.z = world.tile_side_in_meters * tile_diff_z;

    return result;
}

pub fn centeredTilePoint(abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) WorldPosition {
    return WorldPosition{
        .abs_tile_x = abs_tile_x,
        .abs_tile_y = abs_tile_y,
        .abs_tile_z = abs_tile_z,
        .offset = math.Vector2{},
    };
}
