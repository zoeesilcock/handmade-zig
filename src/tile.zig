const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const std = @import("std");

const TileChunkPosition = struct {
    tile_chunk_x: u32,
    tile_chunk_y: u32,
    tile_chunk_z: u32,
    rel_tile_x: u32,
    rel_tile_y: u32,
};

pub const TileChunk = struct {
    tiles: ?[*]u32 = null,
};

pub const TileMap = struct {
    chunk_shift: u32,
    chunk_mask: u32,
    chunk_dim: u32,

    tile_side_in_meters: f32,

    tile_chunk_count_x: u32,
    tile_chunk_count_y: u32,
    tile_chunk_count_z: u32,
    tile_chunks: [*]TileChunk = undefined,
};

pub const TileMapDifference = struct {
    xy: math.Vector2 = math.Vector2{},
    z: f32 = 0,
};

pub const TileMapPosition = struct {
    // Fixed point tile locations.
    // The high bits are the tile chunk index.
    // The low bits are the tile index in the chunk.
    abs_tile_x: u32,
    abs_tile_y: u32,
    abs_tile_z: u32,

    // Position relative to the center of the current tile.
    offset: math.Vector2,

    pub fn zero() TileMapPosition {
        return TileMapPosition{
            .abs_tile_x = 0,
            .abs_tile_y = 0,
            .abs_tile_z = 0,
            .offset = math.Vector2.zero(),
        };
    }
};

pub fn centeredTilePoint(abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32) TileMapPosition {
    return TileMapPosition{
        .abs_tile_x = abs_tile_x,
        .abs_tile_y = abs_tile_y,
        .abs_tile_z = abs_tile_z,
        .offset = math.Vector2{},
    };
}

pub fn subtractPositions(tile_map: *TileMap, a: *TileMapPosition, b: *TileMapPosition) TileMapDifference {
    var result = TileMapDifference{};

    var tile_diff_xy = math.Vector2{
        .x = @as(f32, @floatFromInt(a.abs_tile_x)) - @as(f32, @floatFromInt(b.abs_tile_x)),
        .y = @as(f32, @floatFromInt(a.abs_tile_y)) - @as(f32, @floatFromInt(b.abs_tile_y)),
    };
    const tile_diff_z = @as(f32, @floatFromInt(a.abs_tile_z)) - @as(f32, @floatFromInt(b.abs_tile_z));

    result.xy = tile_diff_xy.scale(tile_map.tile_side_in_meters).add(a.offset.subtract(b.offset));
    result.z = tile_map.tile_side_in_meters * tile_diff_z;

    return result;
}

pub inline fn recannonicalizeCoordinate(tile_map: *TileMap, tile_abs: *u32, tile_rel: *f32) void {
    // Calculate new tile position pased on the tile relative position.
    // TODO: This can end up rounding back on the tile we just came from.
    // TODO: Add bounds checking to prevent wrapping.
    const offset = intrinsics.roundReal32ToInt32(tile_rel.* / tile_map.tile_side_in_meters);
    if (offset >= 0) {
        tile_abs.* +%= @as(u32, @intCast(offset));
    } else {
        tile_abs.* -%= @as(u32, @intCast(@abs(offset)));
    }
    tile_rel.* -= @as(f32, @floatFromInt(offset)) * tile_map.tile_side_in_meters;

    // Check that the new relative position is within the tile size.
    std.debug.assert(tile_rel.* >= -0.5 * tile_map.tile_side_in_meters);
    std.debug.assert(tile_rel.* <= 0.5 * tile_map.tile_side_in_meters);
}

pub fn mapIntoTileSpace(tile_map: *TileMap, base_position: TileMapPosition, offset: math.Vector2) TileMapPosition {
    var result = base_position;

    _ = result.offset.addSet(offset);
    recannonicalizeCoordinate(tile_map, &result.abs_tile_x, &result.offset.x);
    recannonicalizeCoordinate(tile_map, &result.abs_tile_y, &result.offset.y);

    return result;
}

inline fn getTileChunk(tile_map: *TileMap, tile_map_x: u32, tile_map_y: u32, tile_map_z: u32) ?*TileChunk {
    var tile_chunk: ?*TileChunk = null;

    if ((tile_map_x >= 0) and (tile_map_x < tile_map.tile_chunk_count_x) and
        (tile_map_y >= 0) and (tile_map_y < tile_map.tile_chunk_count_y) and
        (tile_map_z >= 0) and (tile_map_z < tile_map.tile_chunk_count_z))
    {
        const index =
            tile_map_z * tile_map.tile_chunk_count_y * tile_map.tile_chunk_count_x +
            tile_map_y * tile_map.tile_chunk_count_x +
            tile_map_x;

        tile_chunk = &tile_map.tile_chunks[@intCast(index)];
    }

    return tile_chunk;
}

inline fn getTileValueUnchecked(tile_map: *TileMap, tile_chunk: *TileChunk, tile_x: u32, tile_y: u32) u32 {
    std.debug.assert((tile_x >= 0) and (tile_x < tile_map.chunk_dim) and
        (tile_y >= 0) and (tile_y < tile_map.chunk_dim));

    return tile_chunk.tiles.?[@intCast(tile_y * tile_map.chunk_dim + tile_x)];
}

inline fn setTileValueUnchecked(tile_map: *TileMap, tile_chunk: *TileChunk, tile_x: u32, tile_y: u32, value: u32) void {
    std.debug.assert((tile_x >= 0) and (tile_x < tile_map.chunk_dim) and
        (tile_y >= 0) and (tile_y < tile_map.chunk_dim));

    tile_chunk.tiles.?[@intCast(tile_y * tile_map.chunk_dim + tile_x)] = value;
}

inline fn getChunkPositionFor(tile_map: *TileMap, abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32) TileChunkPosition {
    return TileChunkPosition{
        .tile_chunk_x = abs_tile_x >> @as(u5, @intCast(tile_map.chunk_shift)),
        .tile_chunk_y = abs_tile_y >> @as(u5, @intCast(tile_map.chunk_shift)),
        .tile_chunk_z = abs_tile_z,
        .rel_tile_x = abs_tile_x & tile_map.chunk_mask,
        .rel_tile_y = abs_tile_y & tile_map.chunk_mask,
    };
}

pub fn getTileValue(tile_map: *TileMap, abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32) u32 {
    var value: u32 = 0;

    const chunk_position = getChunkPositionFor(tile_map, abs_tile_x, abs_tile_y, abs_tile_z);
    const opt_tile_chunk = getTileChunk(
        tile_map,
        @intCast(chunk_position.tile_chunk_x),
        @intCast(chunk_position.tile_chunk_y),
        @intCast(chunk_position.tile_chunk_z),
    );

    if (opt_tile_chunk) |tile_chunk| {
        if (tile_chunk.tiles != null) {
            value = getTileValueUnchecked(tile_map, tile_chunk, chunk_position.rel_tile_x, chunk_position.rel_tile_y);
        }
    }

    return value;
}

pub fn getTileValueFromPosition(tile_map: *TileMap, position: TileMapPosition) u32 {
    return getTileValue(tile_map, position.abs_tile_x, position.abs_tile_y, position.abs_tile_z);
}

pub fn setTileValue(
    world_arena: *shared.MemoryArena,
    tile_map: *TileMap,
    abs_tile_x: u32,
    abs_tile_y: u32,
    abs_tile_z: u32,
    value: u32,
) void {
    const chunk_position = getChunkPositionFor(tile_map, abs_tile_x, abs_tile_y, abs_tile_z);
    const opt_tile_chunk = getTileChunk(
        tile_map,
        @intCast(chunk_position.tile_chunk_x),
        @intCast(chunk_position.tile_chunk_y),
        @intCast(chunk_position.tile_chunk_z),
    );

    if (opt_tile_chunk) |tile_chunk| {
        // Initialize the chunk if it hasn't been initialized yet.
        if (tile_chunk.tiles == null) {
            const tile_count = tile_map.chunk_dim * tile_map.chunk_dim;
            tile_chunk.tiles = shared.pushArray(world_arena, tile_count, u32);

            for (0..tile_count) |tile_index| {
                tile_chunk.tiles.?[tile_index] = 1;
            }
        }

        setTileValueUnchecked(tile_map, tile_chunk, chunk_position.rel_tile_x, chunk_position.rel_tile_y, value);
    }
}

pub fn isTileValueEmpty(tile_value: u32) bool {
    return (tile_value == 1 or tile_value == 3 or tile_value == 4);
}

pub fn isTileMapPointEmpty(tile_map: *TileMap, test_position: TileMapPosition) bool {
    var is_empty = false;

    const tile_value = getTileValue(
        tile_map,
        test_position.abs_tile_x,
        test_position.abs_tile_y,
        test_position.abs_tile_z,
    );
    is_empty = isTileValueEmpty(tile_value);

    return is_empty;
}

pub fn areOnSameTile(a: *TileMapPosition, b: *TileMapPosition) bool {
    return a.abs_tile_x == b.abs_tile_x and
        a.abs_tile_y == b.abs_tile_y and
        a.abs_tile_z == b.abs_tile_z;
}
