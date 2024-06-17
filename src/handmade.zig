const shared = @import("shared.zig");
const tile = @import("tile.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

fn initializeArena(arena: *shared.MemoryArena, size: shared.MemoryIndex, base: [*]u8) void {
    arena.size = size;
    arena.base = base;
    arena.used = 0;
}

fn pushSize(arena: *shared.MemoryArena, size: comptime_int) [*]u8 {
    std.debug.assert((arena.used + size) <= arena.size);

    const result = arena.base + arena.used;
    arena.used += size;
    return result;
}

fn pushStruct(arena: *shared.MemoryArena, comptime T: type) *T {
    const size: shared.MemoryIndex = @sizeOf(T);
    return @as(*T, @ptrCast(@alignCast(pushSize(arena, size))));
}

fn pushArray(arena: *shared.MemoryArena, comptime count: shared.MemoryIndex, comptime T: type) *[count]T {
    const size: shared.MemoryIndex = @sizeOf(T) * count;
    return @as(*[count]T, @ptrCast(@alignCast(pushSize(arena, size))));
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
        state.* = shared.State{ .player_position = tile.TileMapPosition{
            .abs_tile_x = 1,
            .abs_tile_y = 3,
            .tile_rel_x = 5.0,
            .tile_rel_y = 5.0,
        } };

        initializeArena(
            &state.world_arena,
            memory.permanent_storage_size - @sizeOf(shared.State),
            @as([*]u8, @ptrCast(memory.permanent_storage.?)) + @sizeOf(shared.State),
        );

        state.world = pushStruct(&state.world_arena, shared.World);
        const world = state.world;
        world.tile_map = pushStruct(&state.world_arena, tile.TileMap);
        var tile_map = world.tile_map;

        const chunk_shift = 4;
        const chunk_dim = (@as(u32, 1) << @as(u5, @intCast(chunk_shift)));
        const tile_chunk_count_x = 128;
        const tile_chunk_count_y = 128;

        tile_map.chunk_dim = chunk_dim;
        tile_map.chunk_shift = chunk_shift;
        tile_map.chunk_mask = (@as(u32, 1) << @as(u5, @intCast(tile_map.chunk_shift))) - 1;
        tile_map.tile_chunk_count_x = tile_chunk_count_x;
        tile_map.tile_chunk_count_y = tile_chunk_count_y;

        tile_map.tile_side_in_meters = 1.4;
        tile_map.tile_side_in_pixels = 60;
        tile_map.meters_to_pixels = @as(f32, @floatFromInt(tile_map.tile_side_in_pixels)) / tile_map.tile_side_in_meters;

        tile_map.tile_chunks = pushArray(&state.world_arena, tile_chunk_count_x * tile_chunk_count_y, tile.TileChunk);
        for (0..@intCast(tile_chunk_count_y)) |y| {
            for (0..@intCast(tile_chunk_count_x)) |x| {
                tile_map.tile_chunks[y * @as(usize, @intCast(tile_chunk_count_x)) + x].tiles =
                    pushArray(&state.world_arena, chunk_dim * chunk_dim, u32);
            }
        }

        const tiles_per_width: u32 = 17;
        const tiles_per_height: u32 = 9;
        for (0..33) |screen_y| {
            for (0..33) |screen_x| {
                for (0..tiles_per_height) |tile_y| {
                    for (0..tiles_per_width) |tile_x| {
                        const abs_tile_x: u32 = @as(u32, @intCast(screen_x)) * tiles_per_width + @as(u32, @intCast(tile_x));
                        const abs_tile_y: u32 = @as(u32, @intCast(screen_y)) * tiles_per_height + @as(u32, @intCast(tile_y));
                        tile.setTileValueByPosition(
                            &state.world_arena,
                            world.tile_map,
                            abs_tile_x,
                            abs_tile_y,
                            (if (tile_x == tile_y and (tile_y % 2) != 0) 1 else 0),
                        );
                    }
                }
            }
        }
        memory.is_initialized = true;
    }

    const world = state.world;
    const tile_map = world.tile_map;

    var player_movement_speed: f32 = 2.0;
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

            if (controller.action_up.ended_down) {
                player_movement_speed *= 5.0;
            }

            var new_player_position = state.player_position;
            new_player_position.tile_rel_x += player_movement_speed * player_x_delta * input.frame_delta_time;
            new_player_position.tile_rel_y += player_movement_speed * player_y_delta * input.frame_delta_time;
            new_player_position = tile.recanonicalizePosition(tile_map, new_player_position);

            var player_position_left = new_player_position;
            player_position_left.tile_rel_x -= 0.5 * player_width;
            player_position_left = tile.recanonicalizePosition(tile_map, player_position_left);

            var player_position_right = new_player_position;
            player_position_right.tile_rel_x += 0.5 * player_width;
            player_position_right = tile.recanonicalizePosition(tile_map, player_position_right);

            if (tile.isTileMapPointEmpty(tile_map, player_position_left) and
                tile.isTileMapPointEmpty(tile_map, player_position_right) and
                tile.isTileMapPointEmpty(tile_map, new_player_position))
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

    const screen_center_x: f32 = 0.5 * @as(f32, @floatFromInt(buffer.width));
    const screen_center_y: f32 = 0.5 * @as(f32, @floatFromInt(buffer.height));

    var rel_row: i32 = -10;
    var rel_col: i32 = 0;

    while (rel_row < 10) : (rel_row += 1) {
        rel_col = -20;

        while (rel_col < 20) : (rel_col += 1) {
            var col: u32 = state.player_position.abs_tile_x;
            var row: u32 = state.player_position.abs_tile_y;
            if (rel_col >= 0) col +%= @intCast(rel_col) else col -%= @abs(rel_col);
            if (rel_row >= 0) row +%= @intCast(rel_row) else row -%= @abs(rel_row);

            const tile_value = tile.getTileValueFromPosition(tile_map, col, row);
            const is_player_tile = (col == state.player_position.abs_tile_x and row == state.player_position.abs_tile_y);
            const tile_color = if (is_player_tile) player_tile_color else if (tile_value == 1) wall_color else background_color;

            const center_x = screen_center_x -
                tile_map.meters_to_pixels * state.player_position.tile_rel_x +
                @as(f32, @floatFromInt(rel_col)) * @as(f32, @floatFromInt(tile_map.tile_side_in_pixels));
            const center_y = screen_center_y +
                tile_map.meters_to_pixels * state.player_position.tile_rel_y -
                @as(f32, @floatFromInt(rel_row)) * @as(f32, @floatFromInt(tile_map.tile_side_in_pixels));
            const min_x = center_x - 0.5 * @as(f32, @floatFromInt(tile_map.tile_side_in_pixels));
            const min_y = center_y - 0.5 * @as(f32, @floatFromInt(tile_map.tile_side_in_pixels));
            const max_x = center_x + 0.5 * @as(f32, @floatFromInt(tile_map.tile_side_in_pixels));
            const max_y = center_y + 0.5 * @as(f32, @floatFromInt(tile_map.tile_side_in_pixels));

            drawRectangle(buffer, min_x, min_y, max_x, max_y, tile_color);
        }
    }

    // Draw player.
    const player_left: f32 = screen_center_x - (0.5 * tile_map.meters_to_pixels * player_width);
    const player_top: f32 = screen_center_y - tile_map.meters_to_pixels * player_height;
    drawRectangle(
        buffer,
        player_left,
        player_top,
        player_left + tile_map.meters_to_pixels * player_width,
        player_top + tile_map.meters_to_pixels * player_height,
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
