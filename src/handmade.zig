const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
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

inline fn recannonicalizeCoordinate(world: *shared.World, tile_count: i32, tile_map: *i32, tile: *i32, tile_rel: *f32) void {
    // Calculate new tile position pased on the tile relative position.
    // TODO: This can end up rounding back on the tile we just came from.
    // TODO: Add bounds checking to prevent wrapping.
    const offset = intrinsics.floorReal32ToInt32(tile_rel.* / world.tile_side_in_meters);
    tile.* += offset;
    tile_rel.* -= @as(f32, @floatFromInt(offset)) * world.tile_side_in_meters;

    // Check that the new relative position is within the tile size.
    std.debug.assert(tile_rel.* >= 0);
    std.debug.assert(tile_rel.* < world.tile_side_in_meters);

    // Go to the adjescent tile map if the position is outside the current tile map.
    if (tile.* < 0) {
        tile.* = tile_count + tile.*;
        tile_map.* -= 1;
    }
    if (tile.* >= tile_count) {
        tile.* = tile.* - tile_count;
        tile_map.* += 1;
    }
}

fn recanonicalizePosition(world: *shared.World, position: shared.WorldPosition) shared.WorldPosition {
    var result = position;

    recannonicalizeCoordinate(world, world.tile_count_x, &result.tile_map_x, &result.tile_x, &result.tile_rel_x);
    recannonicalizeCoordinate(world, world.tile_count_y, &result.tile_map_y, &result.tile_y, &result.tile_rel_y);

    return result;
}

fn isWorldPointEmpty(world: *shared.World, test_position: shared.WorldPosition) bool {
    var is_empty = false;

    const opt_tile_map = getTileMap(world, test_position.tile_map_x, test_position.tile_map_y);
    if (opt_tile_map) |tile_map| {
        is_empty = isTileMapPointEmpty(world, tile_map, test_position.tile_x, test_position.tile_y);
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
        state.* = shared.State{ .player_position = shared.WorldPosition{
            .tile_map_x = 0,
            .tile_map_y = 0,
            .tile_x = 3,
            .tile_y = 3,
            .tile_rel_x = 5.0,
            .tile_rel_y = 5.0,
        } };
        memory.is_initialized = true;
    }

    const tile_map_count_x = 17;
    const tile_map_count_y = 9;
    var tiles00 = [tile_map_count_y][tile_map_count_x]u32{
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
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
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
    };
    var tiles11 = [tile_map_count_y][tile_map_count_x]u32{
        [_]u32{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        [_]u32{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
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
        .tile_side_in_meters = 1.4,
        .tile_side_in_pixels = 60,
        .meters_to_pixels = 0,

        .tile_map_count_x = 2,
        .tile_map_count_y = 2,
        .lower_left_x = 0,
        .lower_left_y = @as(f32, @floatFromInt(buffer.height)),
        .tile_count_x = tile_map_count_x,
        .tile_count_y = tile_map_count_y,
        .tile_maps = @ptrCast(&tile_maps),
    };
    world.lower_left_x = -@as(f32, @floatFromInt(world.tile_side_in_pixels)) / 2.0;
    world.meters_to_pixels = @as(f32, @floatFromInt(world.tile_side_in_pixels)) / world.tile_side_in_meters;

    const opt_tile_map = getTileMap(&world, state.player_position.tile_map_x, state.player_position.tile_map_y);
    std.debug.assert(opt_tile_map != null);

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

    if (opt_tile_map) |tile_map| {
        var row_index: i32 = 0;
        var column_index: i32 = 0;

        while (row_index < world.tile_count_y) : (row_index += 1) {
            column_index = 0;

            while (column_index < world.tile_count_x) : (column_index += 1) {
                const tile = getTileValueUnchecked(&world, tile_map, column_index, row_index);
                const min_x = world.lower_left_x + @as(f32, @floatFromInt(column_index)) * @as(f32, @floatFromInt(world.tile_side_in_pixels));
                const min_y = world.lower_left_y - @as(f32, @floatFromInt(row_index)) * @as(f32, @floatFromInt(world.tile_side_in_pixels));
                const max_x = min_x + @as(f32, @floatFromInt(world.tile_side_in_pixels));
                const max_y = min_y - @as(f32, @floatFromInt(world.tile_side_in_pixels));
                const is_player_tile = (column_index == state.player_position.tile_x and row_index == state.player_position.tile_y);
                const tile_color = if (is_player_tile) player_tile_color else if (tile == 1) wall_color else background_color;

                drawRectangle(buffer, min_x, max_y, max_x, min_y, tile_color);
            }
        }
    }

    // Draw player.
    const player_left: f32 = world.lower_left_x +
        @as(f32, @floatFromInt(world.tile_side_in_pixels)) * @as(f32, @floatFromInt(state.player_position.tile_x)) +
        world.meters_to_pixels * state.player_position.tile_rel_x - (0.5 * world.meters_to_pixels * player_width);
    const player_top: f32 = world.lower_left_y -
        @as(f32, @floatFromInt(world.tile_side_in_pixels)) * @as(f32, @floatFromInt(state.player_position.tile_y)) -
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
