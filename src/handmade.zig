const shared = @import("shared.zig");
const tile = @import("tile.zig");
const intrinsics = @import("intrinsics.zig");
const random = @import("random.zig");
const std = @import("std");

pub export fn updateAndRender(
    thread: *shared.ThreadContext,
    platform: shared.Platform,
    memory: *shared.Memory,
    input: shared.GameInput,
    buffer: *shared.OffscreenBuffer,
) void {
    std.debug.assert(@sizeOf(shared.State) <= memory.permanent_storage_size);

    const state: *shared.State = @ptrCast(@alignCast(memory.permanent_storage));

    if (!memory.is_initialized) {
        state.* = shared.State{
            .camera_position = tile.TileMapPosition{
                .abs_tile_x = 17 / 2,
                .abs_tile_y = 9 / 2,
                .abs_tile_z = 0,
                .offset_x = 0.0,
                .offset_y = 0.0,
            },
            .player_position = tile.TileMapPosition{
                .abs_tile_x = 1,
                .abs_tile_y = 3,
                .abs_tile_z = 0,
                .offset_x = 5.0,
                .offset_y = 5.0,
            },
            .player_facing_direction = 3,
            .backdrop = debugLoadBMP(thread, platform, "test/test_background.bmp"),
            .hero_bitmaps = .{
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_right_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_right_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_right_cape.bmp"),
                },
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_back_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_back_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_back_cape.bmp"),
                },
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_left_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_left_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_left_cape.bmp"),
                },
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_front_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_front_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_front_cape.bmp"),
                },
            },
        };

        shared.initializeArena(
            &state.world_arena,
            memory.permanent_storage_size - @sizeOf(shared.State),
            @as([*]u8, @ptrCast(memory.permanent_storage.?)) + @sizeOf(shared.State),
        );

        state.world = shared.pushStruct(&state.world_arena, shared.World);
        const world = state.world;
        world.tile_map = shared.pushStruct(&state.world_arena, tile.TileMap);
        var tile_map = world.tile_map;

        tile_map.tile_side_in_meters = 1.4;

        tile_map.chunk_shift = 4;
        tile_map.chunk_dim = (@as(u32, 1) << @as(u5, @intCast(tile_map.chunk_shift)));
        tile_map.chunk_mask = (@as(u32, 1) << @as(u5, @intCast(tile_map.chunk_shift))) - 1;

        tile_map.tile_chunk_count_x = 128;
        tile_map.tile_chunk_count_y = 128;
        tile_map.tile_chunk_count_z = 2;
        tile_map.tile_chunks = shared.pushArray(
            &state.world_arena,
            tile_map.tile_chunk_count_x * tile_map.tile_chunk_count_y * tile_map.tile_chunk_count_z,
            tile.TileChunk,
        );

        const tiles_per_width: u32 = 17;
        const tiles_per_height: u32 = 9;

        var random_number_index: u32 = 0;
        var screen_x: u32 = 0;
        var screen_y: u32 = 0;
        var abs_tile_z: u32 = 0;
        var door_left = false;
        var door_right = false;
        var door_top = false;
        var door_bottom = false;
        var door_up = false;
        var door_down = false;

        for (0..100) |_| {
            std.debug.assert(random_number_index < random.RANDOM_NUMBERS.len);
            var random_choice: u32 = 0;
            if (door_up or door_down) {
                random_choice = random.RANDOM_NUMBERS[random_number_index] % 2;
            } else {
                random_choice = random.RANDOM_NUMBERS[random_number_index] % 3;
            }

            random_number_index += 1;

            var created_z_door = false;
            if (random_choice == 2) {
                created_z_door = true;

                if (abs_tile_z == 0) {
                    door_up = true;
                } else {
                    door_down = true;
                }
            } else if (random_choice == 1) {
                door_right = true;
            } else {
                door_top = true;
            }

            for (0..tiles_per_height) |tile_y| {
                for (0..tiles_per_width) |tile_x| {
                    const abs_tile_x: u32 = @as(u32, @intCast(screen_x)) * tiles_per_width + @as(u32, @intCast(tile_x));
                    const abs_tile_y: u32 = @as(u32, @intCast(screen_y)) * tiles_per_height + @as(u32, @intCast(tile_y));
                    var tile_value: u32 = 1;

                    // Generate doors.
                    if ((tile_x == 0) and (!door_left or (tile_y != (tiles_per_height / 2)))) {
                        tile_value = 2;
                    }
                    if ((tile_x == (tiles_per_width - 1)) and (!door_right or (tile_y != (tiles_per_height / 2)))) {
                        tile_value = 2;
                    }
                    if ((tile_y == 0) and (!door_bottom or (tile_x != (tiles_per_width / 2)))) {
                        tile_value = 2;
                    }
                    if ((tile_y == (tiles_per_height - 1)) and (!door_top or (tile_x != (tiles_per_width / 2)))) {
                        tile_value = 2;
                    }

                    if (tile_x == 10 and tile_y == 6) {
                        if (door_up) {
                            tile_value = 3;
                        } else if (door_down) {
                            tile_value = 4;
                        }
                    }

                    tile.setTileValue(&state.world_arena, world.tile_map, abs_tile_x, abs_tile_y, abs_tile_z, tile_value);
                }
            }

            door_left = door_right;
            door_bottom = door_top;

            if (created_z_door) {
                door_up = !door_up;
                door_down = !door_down;
            } else {
                door_up = false;
                door_down = false;
            }

            door_right = false;
            door_top = false;

            if (random_choice == 2) {
                if (abs_tile_z == 0) {
                    abs_tile_z = 1;
                } else {
                    abs_tile_z = 0;
                }
            } else if (random_choice == 1) {
                screen_x += 1;
            } else {
                screen_y += 1;
            }
        }
        memory.is_initialized = true;
    }

    const world = state.world;
    const tile_map = world.tile_map;

    const tile_side_in_pixels = 60;
    const meters_to_pixels = @as(f32, @floatFromInt(tile_side_in_pixels)) / tile_map.tile_side_in_meters;

    var player_movement_speed: f32 = 2.0;
    const player_height: f32 = 1.4;
    const player_width: f32 = 0.75 * player_height;

    for (&input.controllers) |controller| {
        if (controller.is_analog) {} else {
            var player_x_delta: f32 = 0;
            var player_y_delta: f32 = 0;

            if (controller.move_up.ended_down) {
                player_y_delta = 1;
                state.player_facing_direction = 1;
            }
            if (controller.move_down.ended_down) {
                player_y_delta = -1;
                state.player_facing_direction = 3;
            }
            if (controller.move_left.ended_down) {
                player_x_delta = -1;
                state.player_facing_direction = 2;
            }
            if (controller.move_right.ended_down) {
                player_x_delta = 1;
                state.player_facing_direction = 0;
            }

            if (controller.action_up.ended_down) {
                player_movement_speed *= 5.0;
            }

            var new_player_position = state.player_position;
            new_player_position.offset_x += player_movement_speed * player_x_delta * input.frame_delta_time;
            new_player_position.offset_y += player_movement_speed * player_y_delta * input.frame_delta_time;
            new_player_position = tile.recanonicalizePosition(tile_map, new_player_position);

            var player_position_left = new_player_position;
            player_position_left.offset_x -= 0.5 * player_width;
            player_position_left = tile.recanonicalizePosition(tile_map, player_position_left);

            var player_position_right = new_player_position;
            player_position_right.offset_x += 0.5 * player_width;
            player_position_right = tile.recanonicalizePosition(tile_map, player_position_right);

            if (tile.isTileMapPointEmpty(tile_map, player_position_left) and
                tile.isTileMapPointEmpty(tile_map, player_position_right) and
                tile.isTileMapPointEmpty(tile_map, new_player_position))
            {
                if (!tile.areOnSameTile(&state.player_position, &new_player_position)) {
                    const new_tile_value = tile.getTileValueFromPosition(tile_map, new_player_position);

                    if (new_tile_value == 3) {
                        new_player_position.abs_tile_z += 1;
                    } else if (new_tile_value == 4) {
                        new_player_position.abs_tile_z -= 1;
                    }
                }

                state.player_position = new_player_position;
            }

            state.camera_position.abs_tile_z = state.player_position.abs_tile_z;

            // Move camera when player leaves the current screen.
            if (!state.camera_transitioning) {
                const diff = tile.subtractPositions(tile_map, state.player_position, state.camera_position);
                if (diff.x > 9.0 * tile_map.tile_side_in_meters) {
                    state.camera_target_position = state.camera_position;
                    state.camera_target_position.abs_tile_x += 17;
                    state.camera_transitioning = true;
                } else if (diff.x < -9.0 * tile_map.tile_side_in_meters) {
                    state.camera_target_position = state.camera_position;
                    state.camera_target_position.abs_tile_x -= 17;
                    state.camera_transitioning = true;
                }
                if (diff.y > 5.0 * tile_map.tile_side_in_meters) {
                    state.camera_target_position = state.camera_position;
                    state.camera_target_position.abs_tile_y += 9;
                    state.camera_transitioning = true;
                } else if (diff.y < -5.0 * tile_map.tile_side_in_meters) {
                    state.camera_target_position = state.camera_position;
                    state.camera_target_position.abs_tile_y -= 9;
                    state.camera_transitioning = true;
                }
            }
        }
    }

    if (state.camera_transitioning) {
        var transition_complete = true;

        if (state.camera_target_position.abs_tile_x < state.camera_position.abs_tile_x) {
            state.camera_position.abs_tile_x -= 1;
            transition_complete = false;
        } else if (state.camera_target_position.abs_tile_x > state.camera_position.abs_tile_x) {
            state.camera_position.abs_tile_x += 1;
            transition_complete = false;
        }

        if (state.camera_target_position.abs_tile_y < state.camera_position.abs_tile_y) {
            state.camera_position.abs_tile_y -= 1;
            transition_complete = false;
        } else if (state.camera_target_position.abs_tile_y > state.camera_position.abs_tile_y) {
            state.camera_position.abs_tile_y += 1;
            transition_complete = false;
        }

        if (transition_complete) {
            state.camera_transitioning = false;
        }
    }

    drawBitmap(buffer, 0, 0, state.backdrop, 0, 0);

    // Clear background.
    // const clear_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 0.0 };
    // drawRectangle(buffer, 0.0, 0.0, @floatFromInt(buffer.width), @floatFromInt(buffer.height), clear_color);

    // Draw tile map.
    const wall_color = shared.Color{ .r = 1.0, .g = 1.0, .b = 1.0 };
    const background_color = shared.Color{ .r = 0.5, .g = 0.5, .b = 0.5 };
    const vertical_door_color = shared.Color{ .r = 0.5, .g = 0.25, .b = 0 };

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
            var col: u32 = state.camera_position.abs_tile_x;
            var row: u32 = state.camera_position.abs_tile_y;
            const depth: u32 = state.camera_position.abs_tile_z;
            if (rel_col >= 0) col +%= @intCast(rel_col) else col -%= @abs(rel_col);
            if (rel_row >= 0) row +%= @intCast(rel_row) else row -%= @abs(rel_row);
            const tile_value = tile.getTileValue(tile_map, col, row, depth);

            if (tile_value > 1) {
                const is_player_tile = (col == state.camera_position.abs_tile_x and row == state.camera_position.abs_tile_y);
                var tile_color = background_color;

                if (is_player_tile) {
                    tile_color = player_tile_color;
                } else if (tile_value > 2) {
                    tile_color = vertical_door_color;
                } else if (tile_value == 2) {
                    tile_color = wall_color;
                } else {
                    tile_color = background_color;
                }

                const center_x = screen_center_x -
                    meters_to_pixels * state.camera_position.offset_x +
                    @as(f32, @floatFromInt(rel_col)) * @as(f32, @floatFromInt(tile_side_in_pixels));
                const center_y = screen_center_y +
                    meters_to_pixels * state.camera_position.offset_y -
                    @as(f32, @floatFromInt(rel_row)) * @as(f32, @floatFromInt(tile_side_in_pixels));
                const min_x = center_x - 0.5 * @as(f32, @floatFromInt(tile_side_in_pixels));
                const min_y = center_y - 0.5 * @as(f32, @floatFromInt(tile_side_in_pixels));
                const max_x = center_x + 0.5 * @as(f32, @floatFromInt(tile_side_in_pixels));
                const max_y = center_y + 0.5 * @as(f32, @floatFromInt(tile_side_in_pixels));

                drawRectangle(buffer, min_x, min_y, max_x, max_y, tile_color);
            }
        }
    }

    // Draw player.
    const diff = tile.subtractPositions(tile_map, state.player_position, state.camera_position);
    const player_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 0.0 };
    const player_ground_point_x = screen_center_x + meters_to_pixels * diff.x;
    const player_ground_point_y = screen_center_y - meters_to_pixels * diff.y;
    const player_left: f32 = player_ground_point_x - (0.5 * meters_to_pixels * player_width);
    const player_top: f32 = player_ground_point_y - meters_to_pixels * player_height;
    drawRectangle(
        buffer,
        player_left,
        player_top,
        player_left + meters_to_pixels * player_width,
        player_top + meters_to_pixels * player_height,
        player_color,
    );
    const hero_bitmaps = state.hero_bitmaps[state.player_facing_direction];
    drawBitmap(buffer, player_ground_point_x, player_ground_point_y, hero_bitmaps.torso, hero_bitmaps.align_x, hero_bitmaps.align_y);
    drawBitmap(buffer, player_ground_point_x, player_ground_point_y, hero_bitmaps.cape, hero_bitmaps.align_x, hero_bitmaps.align_y);
    drawBitmap(buffer, player_ground_point_x, player_ground_point_y, hero_bitmaps.head, hero_bitmaps.align_x, hero_bitmaps.align_y);
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

fn drawBitmap(
    buffer: *shared.OffscreenBuffer,
    real_x: f32,
    real_y: f32,
    bitmap: shared.LoadedBitmap,
    align_x: i32,
    align_y: i32,
) void {
    // Consider alignment.
    const x = real_x - @as(f32, @floatFromInt(align_x));
    const y = real_y - @as(f32, @floatFromInt(align_y));

    // Calculate extents.
    var min_x = intrinsics.roundReal32ToInt32(x);
    var min_y = intrinsics.roundReal32ToInt32(y);
    var max_x = intrinsics.roundReal32ToInt32(x + @as(f32, @floatFromInt(bitmap.width)));
    var max_y = intrinsics.roundReal32ToInt32(y + @as(f32, @floatFromInt(bitmap.height)));

    // Clip input values to buffer.
    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = -min_x;
        min_x = 0;
    }
    var source_offset_y: i32 = 0;
    if (min_y < 0) {
        source_offset_y = -min_y;
        min_y = 0;
    }
    if (max_x > buffer.width) {
        max_x = buffer.width;
    }
    if (max_y > buffer.height) {
        max_y = buffer.height;
    }

    const clipping_offset = (-source_offset_y * bitmap.width) + source_offset_x;
    var source_row = bitmap.data.per_pixel + @as(u32, @intCast(bitmap.width * (bitmap.height - 1) + clipping_offset));
    var dest_row: [*]u8 = @ptrCast(buffer.memory);
    dest_row += @as(u32, @intCast((min_x * buffer.bytes_per_pixel) + (min_y * @as(i32, @intCast(buffer.pitch)))));
    for (@intCast(min_y)..@intCast(max_y)) |_| {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source = source_row;

        for (@intCast(min_x)..@intCast(max_x)) |_| {
            const a: f32 = @as(f32, @floatFromInt((source[0] >> 24) & 0xFF)) / 255.0;
            const sr: f32 = @floatFromInt((source[0] >> 16) & 0xFF);
            const sg: f32 = @floatFromInt((source[0] >> 8) & 0xFF);
            const sb: f32 = @floatFromInt((source[0] >> 0) & 0xFF);

            const dr: f32 = @floatFromInt((dest[0] >> 16) & 0xFF);
            const dg: f32 = @floatFromInt((dest[0] >> 8) & 0xFF);
            const db: f32 = @floatFromInt((dest[0] >> 0) & 0xFF);

            const r = (1.0 - a) * dr + a * sr;
            const g = (1.0 - a) * dg + a * sg;
            const b = (1.0 - a) * db + a * sb;

            dest[0] = ((@as(u32, @intFromFloat(r + 0.5)) << 16) |
                (@as(u32, @intFromFloat(g + 0.5)) << 8) |
                (@as(u32, @intFromFloat(b + 0.5)) << 0));

            source += 1;
            dest += 1;
        }

        dest_row += buffer.pitch;
        source_row -= @as(usize, @intCast(bitmap.width));
    }
}

fn debugLoadBMP(
    thread: *shared.ThreadContext,
    platform: shared.Platform,
    file_name: [*:0]const u8,
) shared.LoadedBitmap {
    var result: shared.LoadedBitmap = undefined;
    const read_result = platform.debugReadEntireFile(thread, file_name);

    if (read_result.content_size > 0) {
        const header = @as(*shared.BitmapHeader, @ptrCast(@alignCast(read_result.contents)));

        std.debug.assert(header.compression == 3);

        result.data.per_pixel_channel = @as([*]u8, @ptrCast(read_result.contents)) + header.bitmap_offset;
        result.width = header.width;
        result.height = header.height;

        const alpha_mask = ~(header.red_mask | header.green_mask | header.blue_mask);
        const red_shift = intrinsics.findLeastSignificantSetBit(header.red_mask);
        const green_shift = intrinsics.findLeastSignificantSetBit(header.green_mask);
        const blue_shift = intrinsics.findLeastSignificantSetBit(header.blue_mask);
        const alpha_shift = intrinsics.findLeastSignificantSetBit(alpha_mask);

        std.debug.assert(red_shift.found);
        std.debug.assert(green_shift.found);
        std.debug.assert(blue_shift.found);
        std.debug.assert(alpha_shift.found);

        var source_dest = result.data.per_pixel;
        for (0..@intCast(header.width)) |_| {
            for (0..@intCast(header.height)) |_| {
                const color = source_dest[0];
                source_dest[0] = ((((color >> @intCast(alpha_shift.index)) & 0xFF) << 24) |
                    (((color >> @intCast(red_shift.index)) & 0xFF) << 16) |
                    (((color >> @intCast(green_shift.index)) & 0xFF) << 8) |
                    (((color >> @intCast(blue_shift.index)) & 0xFF) << 0));
                source_dest += 1;
            }
        }
    }

    return result;
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
