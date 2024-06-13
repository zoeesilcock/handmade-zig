const shared = @import("shared.zig");
const std = @import("std");

fn getTileMap(world: *shared.World, tile_map_x: u32, tile_map_y: u32) *shared.TileMap {
    var tile_map: *shared.TileMap = undefined;


    if ((tile_map_x >= 0) and (tile_map_x < world.count_x) and
        (tile_map_y >= 0) and (tile_map_y < world.count_y)) {
        tile_map = &world.tile_maps[tile_map_y * world.count_x + tile_map_y];
    }

    return tile_map;
}

fn getTileValueUnchecked(tile_map: *shared.TileMap, tile_x: u32, tile_y: u32) u32 {
    return tile_map.tiles[tile_y * tile_map.count_x + tile_x];
}

fn isTileMapPointEmpty(tile_map: *shared.TileMap, test_x: f32, test_y: f32) bool {
    var is_empty = false;

    const tile_x: u32 = shared.truncateReal32ToUInt32((test_x - tile_map.upper_left_x) / tile_map.tile_width);
    const tile_y: u32 = shared.truncateReal32ToUInt32((test_y - tile_map.upper_left_y) / tile_map.tile_height);

    if ((tile_x >= 0) and (tile_x < tile_map.count_x) and
        (tile_y >= 0) and (tile_y < tile_map.count_y)) {
        is_empty = (getTileValueUnchecked(tile_map, tile_x, tile_y) == 0);
    }

    return is_empty;
}

fn isWorldPointEmpty(world: *shared.World, tile_map_x: u32, tile_map_y: u32, test_x: f32, test_y: f32) bool {
    var is_empty = false;

    const tile_map = getTileMap(world, tile_map_x, tile_map_y);

    if (tile_map != undefined) {
        const tile_x: u32 = shared.truncateReal32ToUInt32((test_x - tile_map.upper_left_x) / tile_map.tile_width);
        const tile_y: u32 = shared.truncateReal32ToUInt32((test_y - tile_map.upper_left_y) / tile_map.tile_height);

        if ((tile_x >= 0) and (tile_x < tile_map.count_x) and
            (tile_y >= 0) and (tile_y < tile_map.count_y)) {
            is_empty = (getTileValueUnchecked(tile_map, tile_x, tile_y) == 0);
        }
    }

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
        state.* = shared.State{
            .player_x = 150,
            .player_y = 150,
        };
        memory.is_initialized = true;
    }

    const tile_map_count_x = 17;
    const tile_map_count_y = 9;
    var tiles00 = [tile_map_count_y][tile_map_count_x]u32{
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0 },
        [_]u32{ 1, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
    };
    var tiles01 = [tile_map_count_y][tile_map_count_x]u32{
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0 },
        [_]u32{ 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    };
    var tiles10 = [tile_map_count_y][tile_map_count_x]u32{
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1 },
        [_]u32{ 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    };
    var tiles11 = [tile_map_count_y][tile_map_count_x]u32{
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1 },
        [_]u32{ 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    };
    var tile_maps: [2][2]shared.TileMap = .{[1]shared.TileMap{
        shared.TileMap{
            .tile_height = 60,
            .tile_width = 60,
            .upper_left_x = -30,
            .upper_left_y = 0,
            .count_x = tile_map_count_x,
            .count_y = tile_map_count_y,
            .tiles = undefined,
        }
    } ** 2} ** 2;

    tile_maps[0][0].tiles = @ptrCast(&tiles00);
    tile_maps[0][1].tiles = @ptrCast(&tiles01);
    tile_maps[1][0].tiles = @ptrCast(&tiles10);
    tile_maps[1][1].tiles = @ptrCast(&tiles11);

    const tile_map = &tile_maps[0][0];

    const player_movement_speed: f32 = 128;
    const player_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 0.0 };
    const player_width: f32 = 0.75 * tile_map.tile_width;
    const player_height: f32 = tile_map.tile_height;

    for (&input.controllers) |controller| {
        if (controller.is_analog) {} else {
            var player_x_delta: f32 = 0;
            var player_y_delta: f32 = 0;

            if (controller.move_up.ended_down) {
                player_y_delta = -1;
            }
            if (controller.move_down.ended_down) {
                player_y_delta = 1;
            }
            if (controller.move_left.ended_down) {
                player_x_delta = -1;
            }
            if (controller.move_right.ended_down) {
                player_x_delta = 1;
            }

            const new_player_x = state.player_x + player_movement_speed * player_x_delta * input.frame_delta_time;
            const new_player_y = state.player_y + player_movement_speed * player_y_delta * input.frame_delta_time;

            if (isTileMapPointEmpty(tile_map, new_player_x - (0.5 * player_width), new_player_y) and
                isTileMapPointEmpty(tile_map, new_player_x + (0.5 * player_width), new_player_y) and
                isTileMapPointEmpty(tile_map, new_player_x, new_player_y)) {
                state.player_x = new_player_x;
                state.player_y = new_player_y;
            }
        }
    }

    // Clear background.
    const clear_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 1.0 };
    drawRectangle(buffer, 0.0, 0.0, @floatFromInt(buffer.width), @floatFromInt(buffer.height), clear_color);

    // Draw tile map.
    const color1 = shared.Color{ .r = 1.0, .g = 1.0, .b = 1.0 };
    const color2 = shared.Color{ .r = 0.5, .g = 0.5, .b = 0.5 };

    var row_index: u32 = 0;
    var column_index: u32 = 0;

    while (row_index < tile_map_count_y) : (row_index += 1) {
        column_index = 0;

        while (column_index < tile_map_count_x) : (column_index += 1) {
            const tile = getTileValueUnchecked(tile_map, column_index, row_index);
            const min_x = tile_map.upper_left_x + @as(f32, @floatFromInt(column_index)) * tile_map.tile_width;
            const min_y = tile_map.upper_left_y + @as(f32, @floatFromInt(row_index)) * tile_map.tile_height;
            const max_x = min_x + tile_map.tile_width;
            const max_y = min_y + tile_map.tile_height;

            drawRectangle(buffer, min_x, min_y, max_x, max_y, if (tile == 1) color1 else color2);
        }
    }

    // Draw player.
    const player_left: f32 = state.player_x - (0.5 * player_width);
    const player_top: f32 = state.player_y - player_height;
    drawRectangle(
        buffer,
        player_left,
        player_top,
        player_left + player_width,
        player_top + player_height,
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
    var min_x = shared.roundReal32ToInt32(real_min_x);
    var min_y = shared.roundReal32ToInt32(real_min_y);
    var max_x = shared.roundReal32ToInt32(real_max_x);
    var max_y = shared.roundReal32ToInt32(real_max_y);

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
