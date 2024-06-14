const shared = @import("shared.zig");
const std = @import("std");

fn getTileMap(world: *shared.World, tile_map_x: i32, tile_map_y: i32) ?*shared.TileMap {
    var tile_map: ?*shared.TileMap = null;

    if ((tile_map_x >= 0) and (tile_map_x < world.tile_map_count_x) and
        (tile_map_y >= 0) and (tile_map_y < world.tile_map_count_y))
    {
        tile_map = &world.tile_maps[@intCast(tile_map_y * world.tile_map_count_x + tile_map_x)];
    }

    return tile_map;
}

fn getTileValueUnchecked(world: *shared.World, tile_map: *shared.TileMap, tile_x: i32, tile_y: i32) u32 {
    std.debug.assert((tile_x >= 0) and (tile_x < world.tile_count_x) and
        (tile_y >= 0) and (tile_y < world.tile_count_y));

    return tile_map.tiles[@intCast(tile_y * world.tile_count_x + tile_x)];
}

fn isTileMapPointEmpty(world: *shared.World, tile_map: *shared.TileMap, test_x: i32, test_y: i32) bool {
    var is_empty = false;

    if ((test_x >= 0) and (test_x < world.tile_count_x) and
        (test_y >= 0) and (test_y < world.tile_count_y))
    {
        is_empty = (getTileValueUnchecked(world, tile_map, test_x, test_y) == 0);
    }

    return is_empty;
}

fn getCanonicalPosition(world: *shared.World, position: shared.RawPosition) shared.CanonicalPosition {
    const x: f32 = position.x - world.upper_left_x;
    const y: f32 = position.y - world.upper_left_y;
    const tile_x = shared.floorReal32ToInt32(x / world.tile_width);
    const tile_y = shared.floorReal32ToInt32(y / world.tile_height);

    var result = shared.CanonicalPosition{
        .tile_map_x = position.tile_map_x,
        .tile_map_y = position.tile_map_y,
        .tile_x = tile_x,
        .tile_y = tile_y,
        .tile_rel_x = x - (@as(f32, @floatFromInt(tile_x)) * world.tile_width),
        .tile_rel_y = y - (@as(f32, @floatFromInt(tile_y)) * world.tile_height),
    };

    // Check that the relative position is within the tile size.
    std.debug.assert(result.tile_rel_x >= 0);
    std.debug.assert(result.tile_rel_y >= 0);
    std.debug.assert(result.tile_rel_x < world.tile_width);
    std.debug.assert(result.tile_rel_y < world.tile_width);

    // Go to the adjescent tile map if the position is outside the current tile map.
    if (result.tile_x < 0) {
        result.tile_x = world.tile_count_x + result.tile_x;
        result.tile_map_x -= 1;
    }
    if (result.tile_x >= world.tile_count_x) {
        result.tile_x = result.tile_x - world.tile_count_x;
        result.tile_map_x += 1;
    }
    if (result.tile_y < 0) {
        result.tile_y = world.tile_count_y + result.tile_y;
        result.tile_map_y -= 1;
    }
    if (result.tile_y >= world.tile_count_y) {
        result.tile_y = result.tile_y - world.tile_count_y;
        result.tile_map_y += 1;
    }

    return result;
}

fn isWorldPointEmpty(world: *shared.World, test_position: shared.RawPosition) bool {
    var is_empty = false;

    const canonical_position = getCanonicalPosition(world, test_position);
    const opt_tile_map = getTileMap(world, canonical_position.tile_map_x, canonical_position.tile_map_y);
    if (opt_tile_map) |tile_map| {
        is_empty = isTileMapPointEmpty(world, tile_map, canonical_position.tile_x, canonical_position.tile_y);
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
            .player_tile_map_x = 0,
            .player_tile_map_y = 0,
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
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1 },
        [_]u32{ 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
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
    var tile_maps: [2][2]shared.TileMap = .{[1]shared.TileMap{shared.TileMap{
        .tiles = undefined,
    }} ** 2} ** 2;

    tile_maps[0][0].tiles = @ptrCast(&tiles00);
    tile_maps[0][1].tiles = @ptrCast(&tiles10);
    tile_maps[1][0].tiles = @ptrCast(&tiles01);
    tile_maps[1][1].tiles = @ptrCast(&tiles11);

    var world = shared.World{
        .tile_map_count_x = 2,
        .tile_map_count_y = 2,
        .upper_left_x = -30,
        .upper_left_y = 0,
        .tile_height = 60,
        .tile_width = 60,
        .tile_count_x = tile_map_count_x,
        .tile_count_y = tile_map_count_y,
        .tile_maps = @ptrCast(&tile_maps),
    };

    const opt_tile_map = getTileMap(&world, state.player_tile_map_x, state.player_tile_map_y);
    std.debug.assert(opt_tile_map != null);

    const player_movement_speed: f32 = 128;
    const player_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 0.0 };
    const player_width: f32 = 0.75 * world.tile_width;
    const player_height: f32 = world.tile_height;

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

            const player_position = shared.RawPosition{
                .x = new_player_x,
                .y = new_player_y,
                .tile_map_x = state.player_tile_map_x,
                .tile_map_y = state.player_tile_map_y,
            };
            var player_position_left = player_position;
            player_position_left.x -= 0.5 * player_width;
            var player_position_right = player_position;
            player_position_right.x += 0.5 * player_width;

            if (isWorldPointEmpty(&world, player_position_left) and
                isWorldPointEmpty(&world, player_position_right) and
                isWorldPointEmpty(&world, player_position))
            {
                const canonical_position = getCanonicalPosition(&world, player_position);
                state.player_tile_map_x = canonical_position.tile_map_x;
                state.player_tile_map_y = canonical_position.tile_map_y;

                state.player_x = world.upper_left_x +
                    world.tile_width * @as(f32, @floatFromInt(canonical_position.tile_x)) +
                    canonical_position.tile_rel_x;
                state.player_y = world.upper_left_y +
                    world.tile_height * @as(f32, @floatFromInt(canonical_position.tile_y)) +
                    canonical_position.tile_rel_y;
            }
        }
    }

    // Clear background.
    const clear_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 1.0 };
    drawRectangle(buffer, 0.0, 0.0, @floatFromInt(buffer.width), @floatFromInt(buffer.height), clear_color);

    // Draw tile map.
    const color1 = shared.Color{ .r = 1.0, .g = 1.0, .b = 1.0 };
    const color2 = shared.Color{ .r = 0.5, .g = 0.5, .b = 0.5 };

    if (opt_tile_map) |tile_map| {
        var row_index: i32 = 0;
        var column_index: i32 = 0;

        while (row_index < world.tile_count_y) : (row_index += 1) {
            column_index = 0;

            while (column_index < world.tile_count_x) : (column_index += 1) {
                const tile = getTileValueUnchecked(&world, tile_map, column_index, row_index);
                const min_x = world.upper_left_x + @as(f32, @floatFromInt(column_index)) * world.tile_width;
                const min_y = world.upper_left_y + @as(f32, @floatFromInt(row_index)) * world.tile_height;
                const max_x = min_x + world.tile_width;
                const max_y = min_y + world.tile_height;

                drawRectangle(buffer, min_x, min_y, max_x, max_y, if (tile == 1) color1 else color2);
            }
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
