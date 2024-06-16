const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

fn getTileChunk(world: *shared.World, tile_map_x: i32, tile_map_y: i32) ?*shared.TileChunk {
    var tile_chunk: ?*shared.TileChunk = null;

    if ((tile_map_x >= 0) and (tile_map_x < world.tile_chunk_count_x) and
        (tile_map_y >= 0) and (tile_map_y < world.tile_chunk_count_y))
    {
        tile_chunk = &world.tile_chunks[@intCast(tile_map_y * world.tile_chunk_count_x + tile_map_x)];
    }

    return tile_chunk;
}

fn getTileValueUnchecked(world: *shared.World, tile_chunk: *shared.TileChunk, tile_x: u32, tile_y: u32) u32 {
    std.debug.assert((tile_x >= 0) and (tile_x < world.chunk_dim) and
        (tile_y >= 0) and (tile_y < world.chunk_dim));

    return tile_chunk.tiles[@intCast(tile_y * world.chunk_dim + tile_x)];
}

fn getTileValue(world: *shared.World, opt_tile_chunk: ?*shared.TileChunk, test_x: u32, test_y: u32) u32 {
    var value: u32 = 0;

    if (opt_tile_chunk) |tile_chunk| {
        value = getTileValueUnchecked(world, tile_chunk, test_x, test_y);
    }

    return value;
}

inline fn recannonicalizeCoordinate(world: *shared.World, tile: *u32, tile_rel: *f32) void {
    // Calculate new tile position pased on the tile relative position.
    // TODO: This can end up rounding back on the tile we just came from.
    // TODO: Add bounds checking to prevent wrapping.
    const offset = intrinsics.floorReal32ToInt32(tile_rel.* / world.tile_side_in_meters);
    if (offset >= 0) {
        tile.* +%= @as(u32, @intCast(offset));
    } else {
        tile.* -%= @as(u32, @intCast(@abs(offset)));
    }
    tile_rel.* -= @as(f32, @floatFromInt(offset)) * world.tile_side_in_meters;

    // Check that the new relative position is within the tile size.
    std.debug.assert(tile_rel.* >= 0);
    std.debug.assert(tile_rel.* < world.tile_side_in_meters);
}

fn recanonicalizePosition(world: *shared.World, position: shared.WorldPosition) shared.WorldPosition {
    var result = position;

    recannonicalizeCoordinate(world, &result.abs_tile_x, &result.tile_rel_x);
    recannonicalizeCoordinate(world, &result.abs_tile_y, &result.tile_rel_y);

    return result;
}

inline fn getChunkPositionFor(world: *shared.World, abs_tile_x: u32, abs_tile_y: u32) shared.TileChunkPosition {
    return shared.TileChunkPosition{
        .tile_chunk_x = abs_tile_x >> @as(u5, @intCast(world.chunk_shift)),
        .tile_chunk_y = abs_tile_y >> @as(u5, @intCast(world.chunk_shift)),
        .rel_tile_x = abs_tile_x & world.chunk_mask,
        .rel_tile_y = abs_tile_y &  world.chunk_mask,
    };
}

fn getChunkTileValue(world: *shared.World, abs_tile_x: u32, abs_tile_y: u32) u32 {
    var value: u32 = 0;

    const chunk_position = getChunkPositionFor(world, abs_tile_x, abs_tile_y);
    const opt_tile_chunk = getTileChunk(world, @intCast(chunk_position.tile_chunk_x), @intCast(chunk_position.tile_chunk_y));
    value = getTileValue(world, opt_tile_chunk, chunk_position.rel_tile_x, chunk_position.rel_tile_y);

    return value;
}

fn isWorldPointEmpty(world: *shared.World, test_position: shared.WorldPosition) bool {
    var is_empty = false;

    const tile_chunk_value = getChunkTileValue(world, test_position.abs_tile_x, test_position.abs_tile_y);
    is_empty = (tile_chunk_value == 0);

    return is_empty;
}

pub export fn updateAndRender(
    thread: *shared.ThreadContext,
    platform: shared.Platform,
    memory: *shared.Memory,
    input: shared.GameInput,
    buffer: *shared.OffscreenBuffer,
) void {
    _ = thread;
    _ = platform;

    std.debug.assert(@sizeOf(shared.State) <= memory.permanent_storage_size);

    const state: *shared.State = @ptrCast(@alignCast(memory.permanent_storage));

    if (!memory.is_initialized) {
        state.* = shared.State{ .player_position = shared.WorldPosition{
            .tile_map_x = 0,
            .tile_map_y = 0,
            .abs_tile_x = 3,
            .abs_tile_y = 3,
            .tile_rel_x = 5.0,
            .tile_rel_y = 5.0,
        } };
        memory.is_initialized = true;
    }

    // Create an empty chunk.
    var temp_tiles: [256][256]u32 = .{[1]u32{0} ** 256} ** 256;

    // Build our example section.
    const tile_map_count_x = 34;
    const tile_map_count_y = 18;
    const map = [tile_map_count_y][tile_map_count_x]u32{
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    };

    // Transfer our example section into the chunk.
    for (map, 0..) |row, row_index| {
        for (row, 0..) |col, col_index| {
            temp_tiles[row_index][col_index] = col;
        }
    }

    var tile_chunk1 = shared.TileChunk{
        .tiles = @ptrCast(&temp_tiles),
    };
    var world = shared.World{
        // 256x256 tile chunks.
        .chunk_shift = 8,
        .chunk_mask = 0xFF,
        .chunk_dim = 256,

        .tile_side_in_meters = 1.4,
        .tile_side_in_pixels = 60,
        .meters_to_pixels = 0,

        .tile_chunk_count_x = 1,
        .tile_chunk_count_y = 1,
        .tile_chunks = @ptrCast(&tile_chunk1),
    };
    world.meters_to_pixels = @as(f32, @floatFromInt(world.tile_side_in_pixels)) / world.tile_side_in_meters;

    const opt_tile_chunk = getTileChunk(&world, state.player_position.tile_map_x, state.player_position.tile_map_y);
    std.debug.assert(opt_tile_chunk != null);

    const player_movement_speed: f32 = 2;
    const player_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 0.0 };
    const player_height: f32 = 1.4;
    const player_width: f32 = 0.75 * player_height;

    for (&input.controllers) |controller| {
        if (controller.is_analog) {} else {
            var player_x_delta: f32 = 0;
            var player_y_delta: f32 = 0;

            if (controller.move_up.ended_down) {
                player_y_delta = 1;
            }
            if (controller.move_down.ended_down) {
                player_y_delta = -1;
            }
            if (controller.move_left.ended_down) {
                player_x_delta = -1;
            }
            if (controller.move_right.ended_down) {
                player_x_delta = 1;
            }

            var new_player_position = state.player_position;
            new_player_position.tile_rel_x += player_movement_speed * player_x_delta * input.frame_delta_time;
            new_player_position.tile_rel_y += player_movement_speed * player_y_delta * input.frame_delta_time;
            new_player_position = recanonicalizePosition(&world, new_player_position);

            var player_position_left = new_player_position;
            player_position_left.tile_rel_x -= 0.5 * player_width;
            player_position_left = recanonicalizePosition(&world, player_position_left);

            var player_position_right = new_player_position;
            player_position_right.tile_rel_x += 0.5 * player_width;
            player_position_right = recanonicalizePosition(&world, player_position_right);

            if (isWorldPointEmpty(&world, player_position_left) and
                isWorldPointEmpty(&world, player_position_right) and
                isWorldPointEmpty(&world, new_player_position))
            {
                state.player_position = new_player_position;
            }
        }
    }

    // Clear background.
    const clear_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 1.0 };
    drawRectangle(buffer, 0.0, 0.0, @floatFromInt(buffer.width), @floatFromInt(buffer.height), clear_color);

    // Draw tile map.
    const wall_color = shared.Color{ .r = 1.0, .g = 1.0, .b = 1.0 };
    const background_color = shared.Color{ .r = 0.5, .g = 0.5, .b = 0.5 };

    var player_tile_color = background_color;
    if (shared.DEBUG) {
        player_tile_color = shared.Color{ .r = 0.25, .g = 0.25, .b = 0.25 };
    }

    const center_x: f32 = 0.5 * @as(f32, @floatFromInt(buffer.width));
    const center_y: f32 = 0.5 * @as(f32, @floatFromInt(buffer.height));

    var rel_row: i32 = -10;
    var rel_col: i32 = 0;

    while (rel_row < 10) : (rel_row += 1) {
        rel_col = -20;

        while (rel_col < 20) : (rel_col += 1) {
            var col: u32 = state.player_position.abs_tile_x;
            var row: u32 = state.player_position.abs_tile_y;
            if (rel_col >= 0) col +%= @intCast(rel_col) else col -%= @abs(rel_col);
            if (rel_row >= 0) row +%= @intCast(rel_row) else row -%= @abs(rel_row);

            const tile = getChunkTileValue(&world, col, row);
            const is_player_tile = (col == state.player_position.abs_tile_x and row == state.player_position.abs_tile_y);
            const tile_color = if (is_player_tile) player_tile_color else if (tile == 1) wall_color else background_color;

            const min_x = center_x + @as(f32, @floatFromInt(rel_col)) * @as(f32, @floatFromInt(world.tile_side_in_pixels));
            const min_y = center_y - @as(f32, @floatFromInt(rel_row)) * @as(f32, @floatFromInt(world.tile_side_in_pixels));
            const max_x = min_x + @as(f32, @floatFromInt(world.tile_side_in_pixels));
            const max_y = min_y - @as(f32, @floatFromInt(world.tile_side_in_pixels));

            drawRectangle(buffer, min_x, max_y, max_x, min_y, tile_color);
        }
    }

    // Draw player.
    const player_left: f32 = center_x +
        world.meters_to_pixels * state.player_position.tile_rel_x - (0.5 * world.meters_to_pixels * player_width);
    const player_top: f32 = center_y -
        world.meters_to_pixels * state.player_position.tile_rel_y - world.meters_to_pixels * player_height;
    drawRectangle(
        buffer,
        player_left,
        player_top,
        player_left + world.meters_to_pixels * player_width,
        player_top + world.meters_to_pixels * player_height,
        player_color,
    );
}

pub export fn getSoundSamples(
    thread: *shared.ThreadContext,
    memory: *shared.Memory,
    sound_buffer: *shared.SoundOutputBuffer,
) void {
    _ = thread;

    const state: *shared.State = @ptrCast(@alignCast(memory.permanent_storage));
    outputSound(sound_buffer, shared.MIDDLE_C, state);
}

fn drawRectangle(
    buffer: *shared.OffscreenBuffer,
    real_min_x: f32,
    real_min_y: f32,
    real_max_x: f32,
    real_max_y: f32,
    color: shared.Color,
) void {
    // Round input values.
    var min_x = intrinsics.roundReal32ToInt32(real_min_x);
    var min_y = intrinsics.roundReal32ToInt32(real_min_y);
    var max_x = intrinsics.roundReal32ToInt32(real_max_x);
    var max_y = intrinsics.roundReal32ToInt32(real_max_y);

    // Clip input values to buffer.
    if (min_x < 0) {
        min_x = 0;
    }
    if (min_y < 0) {
        min_y = 0;
    }
    if (max_x > buffer.width) {
        max_x = buffer.width;
    }
    if (max_y > buffer.height) {
        max_y = buffer.height;
    }

    // Set the pointer to the top left corner of the rectangle.
    var row: [*]u8 = @ptrCast(buffer.memory);
    row += @as(u32, @intCast((min_x * buffer.bytes_per_pixel) + (min_y * @as(i32, @intCast(buffer.pitch)))));

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            pixel[0] = color.toInt();
            pixel += 1;
        }

        row += buffer.pitch;
    }
}

fn renderWeirdGradient(buffer: *shared.OffscreenBuffer, x_offset: i32, y_offset: i32) void {
    var row: [*]u8 = @ptrCast(buffer.memory);
    var y: u32 = 0;
    var wrapped_x_offset: u32 = 0;
    var wrapped_y_offset: u32 = 0;

    // Wrap the x offset.
    if (x_offset < 0) {
        wrapped_x_offset -%= @as(u32, @intCast(@abs(x_offset)));
    } else {
        wrapped_x_offset +%= @as(u32, @intCast(x_offset));
    }

    // Wrap the y offset.
    if (y_offset < 0) {
        wrapped_y_offset -%= @as(u32, @intCast(@abs(y_offset)));
    } else {
        wrapped_y_offset +%= @as(u32, @intCast(y_offset));
    }

    while (y < buffer.height) {
        var x: u32 = 0;
        var pixel: [*]u32 = @ptrCast(@alignCast(row));

        while (x < buffer.width) {
            const blue: u32 = @as(u8, @truncate(x +% wrapped_x_offset));
            const green: u32 = @as(u8, @truncate(y +% wrapped_y_offset));

            pixel[0] = (green << 8) | blue;

            pixel += 1;
            x += 1;
        }

        row += buffer.pitch;
        y += 1;
    }
}

fn outputSound(sound_buffer: *shared.SoundOutputBuffer, tone_hz: u32, state: *shared.State) void {
    _ = sound_buffer;
    _ = tone_hz;
    _ = state;

    // const tone_volume = 3000;
    // const wave_period = @divFloor(sound_buffer.samples_per_second, tone_hz);
    //
    // var sample_out: [*]i16 = sound_buffer.samples;
    // var sample_index: u32 = 0;
    // while (sample_index < sound_buffer.sample_count) {
    //     var sample_value: i16 = 0;
    //
    //     if (!shared.DEBUG) {
    //         const sine_value: f32 = @sin(t_sine.*);
    //         sample_value = @intFromFloat(sine_value * @as(f32, @floatFromInt(tone_volume)));
    //     }
    //
    //     sample_out += 1;
    //     sample_out[0] = sample_value;
    //     sample_out += 1;
    //     sample_out[0] = sample_value;
    //
    //     sample_index += 1;
    //     t_sine.* += shared.TAU32 / @as(f32, @floatFromInt(wave_period));
    //     if (t_sine.* > shared.TAU32) {
    //         t_sine.* -= shared.TAU32;
    //     }
    // }
}
