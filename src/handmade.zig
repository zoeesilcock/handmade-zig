const shared = @import("shared.zig");
const tile = @import("tile.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
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
            .camera_position = tile.TileMapPosition.zero(),
            .backdrop = debugLoadBMP(thread, platform, "test/test_background.bmp"),
            .hero_bitmaps = .{
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_right_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_right_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_right_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_back_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_back_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_back_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_left_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_left_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_left_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .align_x = 72,
                    .align_y = 182,
                    .head = debugLoadBMP(thread, platform, "test/test_hero_front_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_front_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_front_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
            },
        };

        shared.initializeArena(
            &state.world_arena,
            memory.permanent_storage_size - @sizeOf(shared.State),
            @as([*]u8, @ptrCast(memory.permanent_storage.?)) + @sizeOf(shared.State),
        );

        const null_entity = addEntity(state, .Null);
        _ = null_entity;

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
        // TODO: Waiting for full sparseness.
        // var screen_x: u32 = std.math.maxInt(u32) / 2;
        // var screen_y: u32 = std.math.maxInt(u32) / 2;
        var screen_x: u32 = 0;
        var screen_y: u32 = 0;
        var abs_tile_z: u32 = 0;
        var door_left = false;
        var door_right = false;
        var door_top = false;
        var door_bottom = false;
        var door_up = false;
        var door_down = false;

        for (0..2) |_| {
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

                    if (tile_value == 2) {
                        _ = addWall(state, abs_tile_x, abs_tile_y, abs_tile_z);
                    }
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

        setCameraPosition(state, tile.TileMapPosition{
            .abs_tile_x = 17 / 2,
            .abs_tile_y = 9 / 2,
            .abs_tile_z = 0,
            .offset = math.Vector2{},
        });

        memory.is_initialized = true;
    }

    const world = state.world;
    const tile_map = world.tile_map;

    const tile_side_in_pixels = 60;
    const meters_to_pixels = @as(f32, @floatFromInt(tile_side_in_pixels)) / tile_map.tile_side_in_meters;

    // Handle input.
    for (&input.controllers, 0..) |controller, controller_index| {
        const controlling_entity_index = state.player_index_for_controller[controller_index];
        if (getEntity(state, .High, controlling_entity_index)) |controlling_entity| {
            if (controlling_entity.residence != .NonExistent) {
                var input_direction = math.Vector2{};

                if (controller.is_analog) {
                    input_direction = math.Vector2{
                        .x = controller.stick_average_x,
                        .y = controller.stick_average_y,
                    };
                } else {
                    if (controller.move_up.ended_down) {
                        input_direction.y = 1;
                    }
                    if (controller.move_down.ended_down) {
                        input_direction.y = -1;
                    }
                    if (controller.move_left.ended_down) {
                        input_direction.x = -1;
                    }
                    if (controller.move_right.ended_down) {
                        input_direction.x = 1;
                    }
                }

                if (controller.action_down.ended_down) {
                    controlling_entity.high.z_velocity = 3;
                }

                movePlayer(
                    state,
                    controlling_entity,
                    input.frame_delta_time,
                    input_direction,
                    controller.action_up.ended_down,
                );
            }
        } else {
            if (controller.start_button.ended_down) {
                const entity_index = addPlayer(state);
                state.player_index_for_controller[controller_index] = entity_index;
            }
        }
    }
    if (getEntity(state, .High, state.camera_following_entity_index)) |camera_following_entity| {
        if (camera_following_entity.residence != .NonExistent) {
            var new_camera_position = state.camera_position;
            new_camera_position.abs_tile_z = camera_following_entity.dormant.position.abs_tile_z;

            // Move camera when player leaves the current screen.
            if (camera_following_entity.high.position.x > 9.0 * tile_map.tile_side_in_meters) {
                new_camera_position.abs_tile_x += 17;
            } else if (camera_following_entity.high.position.x < -9.0 * tile_map.tile_side_in_meters) {
                new_camera_position.abs_tile_x -= 17;
            }
            if (camera_following_entity.high.position.y > 5.0 * tile_map.tile_side_in_meters) {
                new_camera_position.abs_tile_y += 9;
            } else if (camera_following_entity.high.position.y < -5.0 * tile_map.tile_side_in_meters) {
                new_camera_position.abs_tile_y -= 9;
            }

            setCameraPosition(state, new_camera_position);
        }
    }

    drawBitmap(buffer, 0, 0, state.backdrop, 0, 0, 1);

    // Clear background.
    // const clear_color = shared.Color{ .r = 1.0, .g = 0.0, .b = 0.0 };
    // drawRectangle(
    //     buffer,
    //     math.Vector2{ .x = 0.0, .y = 0.0 },
    //     math.Vector2{ .x = @floatFromInt(buffer.width), .y = @floatFromInt(buffer.height) },
    //     clear_color,
    // );

    // Draw tile map.
    // const wall_color = shared.Color{ .r = 1.0, .g = 1.0, .b = 1.0 };
    // const background_color = shared.Color{ .r = 0.5, .g = 0.5, .b = 0.5 };
    // const vertical_door_color = shared.Color{ .r = 0.5, .g = 0.25, .b = 0 };
    //
    // var player_tile_color = background_color;
    // if (shared.DEBUG) {
    //     player_tile_color = shared.Color{ .r = 0.25, .g = 0.25, .b = 0.25 };
    // }
    //
    const screen_center_x: f32 = 0.5 * @as(f32, @floatFromInt(buffer.width));
    const screen_center_y: f32 = 0.5 * @as(f32, @floatFromInt(buffer.height));
    //
    // var rel_row: i32 = -10;
    // var rel_col: i32 = 0;
    //
    // while (rel_row < 10) : (rel_row += 1) {
    //     rel_col = -20;
    //
    //     while (rel_col < 20) : (rel_col += 1) {
    //         var col: u32 = state.camera_position.abs_tile_x;
    //         var row: u32 = state.camera_position.abs_tile_y;
    //         const depth: u32 = state.camera_position.abs_tile_z;
    //         if (rel_col >= 0) col +%= @intCast(rel_col) else col -%= @abs(rel_col);
    //         if (rel_row >= 0) row +%= @intCast(rel_row) else row -%= @abs(rel_row);
    //         const tile_value = tile.getTileValue(tile_map, col, row, depth);
    //
    //         if (tile_value > 1) {
    //             const is_player_tile = (col == state.camera_position.abs_tile_x and row == state.camera_position.abs_tile_y);
    //             var tile_color = background_color;
    //
    //             if (is_player_tile) {
    //                 tile_color = player_tile_color;
    //             } else if (tile_value > 2) {
    //                 tile_color = vertical_door_color;
    //             } else if (tile_value == 2) {
    //                 tile_color = wall_color;
    //             } else {
    //                 tile_color = background_color;
    //             }
    //
    //             const center = math.Vector2{
    //                 .x = screen_center_x -
    //                     meters_to_pixels * state.camera_position.offset.x +
    //                     @as(f32, @floatFromInt(rel_col)) * @as(f32, @floatFromInt(tile_side_in_pixels)),
    //                 .y = screen_center_y +
    //                     meters_to_pixels * state.camera_position.offset.y -
    //                     @as(f32, @floatFromInt(rel_row)) * @as(f32, @floatFromInt(tile_side_in_pixels)),
    //             };
    //             const tile_side = math.Vector2{
    //                 .x = 0.5 * @as(f32, @floatFromInt(tile_side_in_pixels)),
    //                 .y = 0.5 * @as(f32, @floatFromInt(tile_side_in_pixels)),
    //             };
    //             const min = center.subtract(tile_side);
    //             const max = center.add(tile_side);
    //
    //             drawRectangle(buffer, min, max, tile_color);
    //         }
    //     }
    // }

    // Draw player.
    var entity_index: u32 = 1;
    while (entity_index < state.entity_count) : (entity_index += 1) {
        const residence = state.entity_residence[entity_index];
        if (residence == .High) {
            var high_entity = &state.high_entities[entity_index];
            const dormant_entity = &state.dormant_entities[entity_index];

            // Jump.
            const delta_time = input.frame_delta_time;
            const z_acceleration = -9.8;
            high_entity.z = (0.5 * z_acceleration * math.square(delta_time)) +
                high_entity.z_velocity * delta_time + high_entity.z;
            high_entity.z_velocity = z_acceleration * delta_time + high_entity.z_velocity;
            if (high_entity.z < 0) {
                high_entity.z = 0;
            }
            var shadow_alpha: f32 = 1 - high_entity.z;
            if (shadow_alpha < 0) {
                shadow_alpha = 0;
            }

            const entity_ground_point_x = screen_center_x + meters_to_pixels * high_entity.position.x;
            const entity_ground_point_y = screen_center_y - meters_to_pixels * high_entity.position.y;
            const z = -meters_to_pixels * high_entity.z;

            if (dormant_entity.type == .Hero) {
                const hero_bitmaps = state.hero_bitmaps[high_entity.facing_direction];
                drawBitmap(
                    buffer,
                    entity_ground_point_x,
                    entity_ground_point_y,
                    hero_bitmaps.shadow,
                    hero_bitmaps.align_x,
                    hero_bitmaps.align_y,
                    shadow_alpha,
                );
                drawBitmap(
                    buffer,
                    entity_ground_point_x,
                    entity_ground_point_y + z,
                    hero_bitmaps.torso,
                    hero_bitmaps.align_x,
                    hero_bitmaps.align_y,
                    1,
                );
                drawBitmap(
                    buffer,
                    entity_ground_point_x,
                    entity_ground_point_y + z,
                    hero_bitmaps.cape,
                    hero_bitmaps.align_x,
                    hero_bitmaps.align_y,
                    1,
                );
                drawBitmap(
                    buffer,
                    entity_ground_point_x,
                    entity_ground_point_y + z,
                    hero_bitmaps.head,
                    hero_bitmaps.align_x,
                    hero_bitmaps.align_y,
                    1,
                );
            } else {
                const tile_color = shared.Color{ .r = 1.0, .g = 1.0, .b = 1.0 };
                const entity_left_top = math.Vector2{
                    .x = entity_ground_point_x - (0.5 * meters_to_pixels * dormant_entity.width),
                    .y = entity_ground_point_y - (0.5 * meters_to_pixels * dormant_entity.height),
                };
                const entity_width_height = math.Vector2{
                    .x = dormant_entity.width,
                    .y = dormant_entity.height,
                };

                drawRectangle(
                    buffer,
                    entity_left_top,
                    entity_left_top.add(entity_width_height.scale(meters_to_pixels)),
                    tile_color,
                );
            }
        }
    }
}

fn setCameraPosition(state: *shared.State, new_camera_position: tile.TileMapPosition) void {
    const tile_map = state.world.tile_map;

    const camera_delta = tile.subtractPositions(tile_map, @constCast(&new_camera_position), &state.camera_position);
    state.camera_position = new_camera_position;

    const tile_span_x = 17 * 3;
    const tile_span_y = 9 * 3;
    const bounds_in_tiles = math.Vector2{ .x = tile_span_x, .y = tile_span_y };
    const camera_in_bounds = math.Rectangle2.fromCenterDimension(
        math.Vector2.zero(),
        bounds_in_tiles.scale(tile_map.tile_side_in_meters),
    );

    const entity_offset_for_frame = camera_delta.xy.negate();
    var entity_index: u32 = 1;
    while (entity_index < state.high_entities.len) : (entity_index += 1) {
        if (state.entity_residence[entity_index] == .High) {
            const high_entity = &state.high_entities[entity_index];
            _ = high_entity.position.addSet(entity_offset_for_frame);

            if (!high_entity.position.isInRectangle(camera_in_bounds)) {
                changeEntityResidence(state, entity_index, .Dormant);
            }
        }
    }

    entity_index = 1;
    while (entity_index < state.dormant_entities.len) : (entity_index += 1) {
        if (state.entity_residence[entity_index] == .Dormant) {
            const dormant_entity = &state.dormant_entities[entity_index];

            const min_tile_x: u32 = new_camera_position.abs_tile_x -% (tile_span_x / 2);
            const max_tile_x: u32 = new_camera_position.abs_tile_x +% (tile_span_x / 2);
            const min_tile_y: u32 = new_camera_position.abs_tile_y -% (tile_span_y / 2);
            const max_tile_y: u32 = new_camera_position.abs_tile_y +% (tile_span_y / 2);
            if ((dormant_entity.position.abs_tile_z == new_camera_position.abs_tile_z) and
                (dormant_entity.position.abs_tile_x >= min_tile_x) and
                (dormant_entity.position.abs_tile_x <= max_tile_x) and
                (dormant_entity.position.abs_tile_y >= min_tile_y) and
                (dormant_entity.position.abs_tile_y <= max_tile_y)) {
                changeEntityResidence(state, entity_index, .High);
            }
        }
    }
}

fn addEntity(state: *shared.State, entity_type: shared.EntityType) u32 {
    const entity_index = state.entity_count;
    state.entity_count += 1;

    std.debug.assert(state.entity_count < state.dormant_entities.len);
    std.debug.assert(state.entity_count < state.low_entities.len);
    std.debug.assert(state.entity_count < state.high_entities.len);

    state.entity_residence[entity_index] = .Dormant;
    state.dormant_entities[entity_index] = shared.DormantEntity{
        .type = entity_type,
    };
    state.low_entities[entity_index] = shared.LowEntity{};
    state.high_entities[entity_index] = shared.HighEntity{};

    return entity_index;
}

fn getEntity(state: *shared.State, residence: shared.EntityResidence, index: u32) ?shared.Entity {
    var entity: ?shared.Entity = null;

    if (index > 0 and index < state.entity_count) {
        if (@intFromEnum(state.entity_residence[index]) < @intFromEnum(residence)) {
            changeEntityResidence(state, index, residence);
            std.debug.assert(@intFromEnum(state.entity_residence[index]) >= @intFromEnum(residence));
        }

        entity = shared.Entity{
            .residence = residence,
            .dormant = &state.dormant_entities[index],
            .low = &state.low_entities[index],
            .high = &state.high_entities[index],
        };
    }

    return entity;
}

fn changeEntityResidence(state: *shared.State, entity_index: u32, residence: shared.EntityResidence) void {
    if (residence == .High) {
        if (state.entity_residence[entity_index] != .High) {
            var high_entity = &state.high_entities[entity_index];
            var dormant_entity = &state.dormant_entities[entity_index];

            const diff = tile.subtractPositions(state.world.tile_map, &dormant_entity.position, &state.camera_position);
            high_entity.position = diff.xy;
            high_entity.abs_tile_z = dormant_entity.position.abs_tile_z;
            high_entity.velocity = math.Vector2.zero();
            high_entity.facing_direction = 0;
        }
    }

    state.entity_residence[entity_index] = residence;
}

fn addPlayer(state: *shared.State) u32 {
    const entity_index = addEntity(state, .Hero);
    const opt_entity = getEntity(state, .Dormant, entity_index);

    if (opt_entity) |entity| {
        entity.high.facing_direction = 3;
        entity.dormant.position = tile.TileMapPosition{
            .abs_tile_x = 1,
            .abs_tile_y = 3,
            .abs_tile_z = 0,
            .offset = math.Vector2{ .x = 0, .y = 0 },
        };
        entity.dormant.height = 0.5; // 1.4;
        entity.dormant.width = 1.0;
        entity.dormant.collides = true;

        changeEntityResidence(state, entity_index, .High);

        const opt_camera_following_entity = getEntity(state, .Dormant, state.camera_following_entity_index);
        if (opt_camera_following_entity) |following_entity| {
            if (following_entity.residence == .NonExistent) {
                state.camera_following_entity_index = entity_index;
            }
        } else {
            state.camera_following_entity_index = entity_index;
        }
    }

    return entity_index;
}

fn addWall(state: *shared.State, abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32) u32 {
    const entity_index = addEntity(state, .Wall);
    const opt_entity = getEntity(state, .Dormant, entity_index);

    if (opt_entity) |entity| {
        entity.high.facing_direction = 3;
        entity.dormant.position = tile.TileMapPosition{
            .abs_tile_x = abs_tile_x,
            .abs_tile_y = abs_tile_y,
            .abs_tile_z = abs_tile_z,
            .offset = math.Vector2{ .x = 0, .y = 0 },
        };
        entity.dormant.height = state.world.tile_map.tile_side_in_meters;
        entity.dormant.width = state.world.tile_map.tile_side_in_meters;
        entity.dormant.collides = true;
    }

    return entity_index;
}

fn movePlayer(
    state: *shared.State,
    entity: shared.Entity,
    delta_time: f32,
    direction: math.Vector2,
    is_running: bool,
) void {
    const player_movement_speed: f32 = if (is_running) 200.0 else 50.0;
    var player_acceleration = direction;

    // Correct speed when multiple axes are contributing to the direction.
    const direction_length = direction.lengthSquared();
    if (direction_length > 1.0) {
        _ = player_acceleration.scaleSet(1.0 / intrinsics.squareRoot(direction_length));
    }

    // Calculate acceleration.
    _ = player_acceleration.scaleSet(player_movement_speed);
    _ = player_acceleration.addSet(entity.high.velocity.scale(8.0).negate());

    // Calculate player delta.
    var player_delta = player_acceleration.scale(0.5 * math.square(delta_time))
        .add(entity.high.velocity.scale(delta_time));
    entity.high.velocity = player_acceleration.scale(delta_time).add(entity.high.velocity);

    var remaining_time: f32 = 1.0;
    var iterations: u32 = 0;
    while (iterations < 4 and remaining_time > 0.0) : (iterations += 1) {
        var min_time: f32 = 1.0;
        var wall_normal = math.Vector2.zero();
        var hit_entity_index: u32 = 0;

        var entity_index: u32 = 0;
        while (entity_index < state.entity_count) : (entity_index += 1) {
            const opt_test_entity = getEntity(state, .High, entity_index);
            if (opt_test_entity) |test_entity| {
                if (entity.high != test_entity.high and test_entity.dormant.collides) {
                    const collision_diameter = math.Vector2{
                        .x = test_entity.dormant.width + entity.dormant.width,
                        .y = test_entity.dormant.height + entity.dormant.height,
                    };
                    const min_corner = collision_diameter.scale(-0.5);
                    const max_corner = collision_diameter.scale(0.5);
                    const relative = entity.high.position.subtract(test_entity.high.position);

                    if (testWall(
                        min_corner.x,
                        relative.x,
                        relative.y,
                        player_delta.x,
                        player_delta.y,
                        min_corner.y,
                        max_corner.y,
                        &min_time,
                    )) {
                        wall_normal = math.Vector2{ .x = -1, .y = 0 };
                        hit_entity_index = entity_index;
                    }

                    if (testWall(
                        max_corner.x,
                        relative.x,
                        relative.y,
                        player_delta.x,
                        player_delta.y,
                        min_corner.y,
                        max_corner.y,
                        &min_time,
                    )) {
                        wall_normal = math.Vector2{ .x = 1, .y = 0 };
                        hit_entity_index = entity_index;
                    }

                    if (testWall(
                        min_corner.y,
                        relative.y,
                        relative.x,
                        player_delta.y,
                        player_delta.x,
                        min_corner.x,
                        max_corner.x,
                        &min_time,
                    )) {
                        wall_normal = math.Vector2{ .x = 0, .y = -1 };
                        hit_entity_index = entity_index;
                    }

                    if (testWall(
                        max_corner.y,
                        relative.y,
                        relative.x,
                        player_delta.y,
                        player_delta.x,
                        min_corner.x,
                        max_corner.x,
                        &min_time,
                    )) {
                        wall_normal = math.Vector2{ .x = 0, .y = 1 };
                        hit_entity_index = entity_index;
                    }
                }
            }
        }

        // Apply the amount of delta allowed by collision detection.
        _ = entity.high.position.addSet(player_delta.scale(min_time));

        if (hit_entity_index > 0) {
            // Remove velocity that is facing into the wall.
            _ = entity.high.velocity.subtractSet(wall_normal.scale(entity.high.velocity.dot(wall_normal)));

            // Remove the applied delta.
            _ = player_delta.subtractSet(wall_normal.scale(player_delta.dot(wall_normal)));
            remaining_time -= min_time * remaining_time;

            if (getEntity(state, .Dormant, hit_entity_index)) |hit_entity| {
                // Update player Z when hitting a ladder.
                entity.high.abs_tile_z += hit_entity.dormant.abs_tile_z_delta;
            }
        } else {
            break;
        }
    }

    // Update facing direction based on velocity.
    if (entity.high.velocity.x == 0 and entity.high.velocity.y == 0) {
        // Keep existing facing direction when velocity is zero.
    } else if (intrinsics.absoluteValue(entity.high.velocity.x) > intrinsics.absoluteValue(entity.high.velocity.y)) {
        if (entity.high.velocity.x > 0) {
            entity.high.facing_direction = 0;
        } else {
            entity.high.facing_direction = 2;
        }
    } else if (intrinsics.absoluteValue(entity.high.velocity.x) < intrinsics.absoluteValue(entity.high.velocity.y)) {
        if (entity.high.velocity.y > 0) {
            entity.high.facing_direction = 1;
        } else {
            entity.high.facing_direction = 3;
        }
    }

    entity.dormant.position = tile.mapIntoTileSpace(state.world.tile_map, state.camera_position, entity.high.position);
}

pub fn testWall(
    wall_x: f32,
    relative_x: f32,
    relative_y: f32,
    delta_x: f32,
    delta_y: f32,
    min_y: f32,
    max_y: f32,
    min_time: *f32,
) bool {
    var hit = false;

    if (delta_x != 0.0) {
        const epsilon_time = 0.00001;
        const result_time = (wall_x - relative_x) / delta_x;
        const y = relative_y + (result_time * delta_y);
        if (result_time >= 0 and min_time.* > result_time) {
            if (y >= min_y and y <= max_y) {
                min_time.* = @max(0.0, result_time - epsilon_time);
                hit = true;
            }
        }
    }

    return hit;
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
    vector_min: math.Vector2,
    vector_max: math.Vector2,
    color: shared.Color,
) void {
    // Round input values.
    var min_x = intrinsics.roundReal32ToInt32(vector_min.x);
    var min_y = intrinsics.roundReal32ToInt32(vector_min.y);
    var max_x = intrinsics.roundReal32ToInt32(vector_max.x);
    var max_y = intrinsics.roundReal32ToInt32(vector_max.y);

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
    alpha: f32,
) void {
    // Consider alignment.
    const aligned_x = real_x - @as(f32, @floatFromInt(align_x));
    const aligned_y = real_y - @as(f32, @floatFromInt(align_y));

    // Calculate extents.
    var min_x = intrinsics.roundReal32ToInt32(aligned_x);
    var min_y = intrinsics.roundReal32ToInt32(aligned_y);
    var max_x: i32 = @intFromFloat(aligned_x + @as(f32, @floatFromInt(bitmap.width)));
    var max_y: i32 = @intFromFloat(aligned_y + @as(f32, @floatFromInt(bitmap.height)));

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

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source = source_row;

        var x = min_x;
        while (x < max_x) : (x += 1) {
            var a: f32 = @as(f32, @floatFromInt((source[0] >> 24) & 0xFF)) / 255.0;
            a *= alpha;

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
        const alpha_scan = intrinsics.findLeastSignificantSetBit(alpha_mask);
        const red_scan = intrinsics.findLeastSignificantSetBit(header.red_mask);
        const green_scan = intrinsics.findLeastSignificantSetBit(header.green_mask);
        const blue_scan = intrinsics.findLeastSignificantSetBit(header.blue_mask);

        std.debug.assert(alpha_scan.found);
        std.debug.assert(red_scan.found);
        std.debug.assert(green_scan.found);
        std.debug.assert(blue_scan.found);

        const alpha_shift = 24 - @as(i32, @intCast(alpha_scan.index));
        const red_shift = 16 - @as(i32, @intCast(red_scan.index));
        const green_shift = 8 - @as(i32, @intCast(green_scan.index));
        const blue_shift = 0 - @as(i32, @intCast(blue_scan.index));

        var source_dest = result.data.per_pixel;
        var x: u32 = 0;
        while (x < header.width) : (x += 1) {
            var y: u32 = 0;
            while (y < header.height) : (y += 1) {
                const color = source_dest[0];
                source_dest[0] = (intrinsics.rotateLeft(color & header.red_mask, red_shift) |
                    intrinsics.rotateLeft(color & header.green_mask, green_shift) |
                    intrinsics.rotateLeft(color & header.blue_mask, blue_shift) |
                    intrinsics.rotateLeft(color & alpha_mask, alpha_shift));
                source_dest += 1;
            }
        }
    }

    return result;
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
