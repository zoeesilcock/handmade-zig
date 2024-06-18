const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

const TileChunkPosition = struct {
    tile_chunk_x: u32,
    tile_chunk_y: u32,
    rel_tile_x: u32,
    rel_tile_y: u32,
};

pub const TileChunk = struct {
    tiles: [*]u32 = undefined,
};

pub const TileMap = struct {
    chunk_shift: u32,
    chunk_mask: u32,
    chunk_dim: u32,

    tile_side_in_meters: f32,
    tile_side_in_pixels: i32,
    meters_to_pixels: f32,

    tile_chunk_count_x: u32,
    tile_chunk_count_y: u32,
    tile_chunks: [*]TileChunk = undefined,
};

pub const TileMapPosition = struct {
    // Fixed point tile locations.
    // The high bits are the tile chunk index.
    // The low bits are the tile index in the chunk.
    abs_tile_x: u32,
    abs_tile_y: u32,

    // Position relative to the center of the current tile.
    tile_rel_y: f32,
    tile_rel_x: f32,
};

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

pub fn recanonicalizePosition(tile_map: *TileMap, position: TileMapPosition) TileMapPosition {
    var result = position;

    recannonicalizeCoordinate(tile_map, &result.abs_tile_x, &result.tile_rel_x);
    recannonicalizeCoordinate(tile_map, &result.abs_tile_y, &result.tile_rel_y);

    return result;
}

inline fn getTileChunk(tile_map: *TileMap, tile_map_x: u32, tile_map_y: u32) ?*TileChunk {
    var tile_chunk: ?*TileChunk = null;

    if ((tile_map_x >= 0) and (tile_map_x < tile_map.tile_chunk_count_x) and
        (tile_map_y >= 0) and (tile_map_y < tile_map.tile_chunk_count_y))
    {
        tile_chunk = &tile_map.tile_chunks[@intCast(tile_map_y * tile_map.tile_chunk_count_x + tile_map_x)];
    }

    return tile_chunk;
}

inline fn getTileValueUnchecked(tile_map: *TileMap, tile_chunk: *TileChunk, tile_x: u32, tile_y: u32) u32 {
    std.debug.assert((tile_x >= 0) and (tile_x < tile_map.chunk_dim) and
        (tile_y >= 0) and (tile_y < tile_map.chunk_dim));

    return tile_chunk.tiles[@intCast(tile_y * tile_map.chunk_dim + tile_x)];
}

inline fn setTileValueUnchecked(tile_map: *TileMap, tile_chunk: *TileChunk, tile_x: u32, tile_y: u32, value: u32) void {
    std.debug.assert((tile_x >= 0) and (tile_x < tile_map.chunk_dim) and
        (tile_y >= 0) and (tile_y < tile_map.chunk_dim));

    tile_chunk.tiles[@intCast(tile_y * tile_map.chunk_dim + tile_x)] = value;
}

fn getTileValue(tile_map: *TileMap, opt_tile_chunk: ?*TileChunk, test_x: u32, test_y: u32) u32 {
    var value: u32 = 0;

    if (opt_tile_chunk) |tile_chunk| {
        value = getTileValueUnchecked(tile_map, tile_chunk, test_x, test_y);
    }

    return value;
}

fn setTileValue(tile_map: *TileMap, opt_tile_chunk: ?*TileChunk, test_x: u32, test_y: u32, value: u32) void {
    if (opt_tile_chunk) |tile_chunk| {
        setTileValueUnchecked(tile_map, tile_chunk, test_x, test_y, value);
    }
}

inline fn getChunkPositionFor(tile_map: *TileMap, abs_tile_x: u32, abs_tile_y: u32) TileChunkPosition {
    return TileChunkPosition{
        .tile_chunk_x = abs_tile_x >> @as(u5, @intCast(tile_map.chunk_shift)),
        .tile_chunk_y = abs_tile_y >> @as(u5, @intCast(tile_map.chunk_shift)),
        .rel_tile_x = abs_tile_x & tile_map.chunk_mask,
        .rel_tile_y = abs_tile_y & tile_map.chunk_mask,
    };
}

pub fn getTileValueFromPosition(tile_map: *TileMap, abs_tile_x: u32, abs_tile_y: u32) u32 {
    var value: u32 = 0;

    const chunk_position = getChunkPositionFor(tile_map, abs_tile_x, abs_tile_y);
    const opt_tile_chunk = getTileChunk(
        tile_map,
        @intCast(chunk_position.tile_chunk_x),
        @intCast(chunk_position.tile_chunk_y),
    );
    value = getTileValue(tile_map, opt_tile_chunk, chunk_position.rel_tile_x, chunk_position.rel_tile_y);

    return value;
}

pub fn setTileValueByPosition(
    world_arena: *shared.MemoryArena,
    tile_map: *TileMap,
    abs_tile_x: u32,
    abs_tile_y: u32,
    value: u32,
) void {
    _ = world_arena;

    const chunk_position = getChunkPositionFor(tile_map, abs_tile_x, abs_tile_y);
    const opt_tile_chunk = getTileChunk(
        tile_map,
        @intCast(chunk_position.tile_chunk_x),
        @intCast(chunk_position.tile_chunk_y),
    );

    std.debug.assert(opt_tile_chunk != null);

    setTileValue(tile_map, opt_tile_chunk, chunk_position.rel_tile_x, chunk_position.rel_tile_y, value);
}

pub fn isTileMapPointEmpty(tile_map: *TileMap, test_position: TileMapPosition) bool {
    var is_empty = false;

    const tile_chunk_value = getTileValueFromPosition(tile_map, test_position.abs_tile_x, test_position.abs_tile_y);
    is_empty = (tile_chunk_value == 1);

    return is_empty;
}
