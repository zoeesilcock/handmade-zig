const shared = @import("shared.zig");
const world = @import("world.zig");
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
            .camera_position = world.WorldPosition.zero(),
            .backdrop = debugLoadBMP(thread, platform, "test/test_background.bmp"),
            .hero_bitmaps = .{
                shared.HeroBitmaps{
                    .alignment = math.Vector2{ .x = 72, .y = 182 },
                    .head = debugLoadBMP(thread, platform, "test/test_hero_right_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_right_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_right_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .alignment = math.Vector2{ .x = 72, .y = 182 },
                    .head = debugLoadBMP(thread, platform, "test/test_hero_back_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_back_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_back_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .alignment = math.Vector2{ .x = 72, .y = 182 },
                    .head = debugLoadBMP(thread, platform, "test/test_hero_left_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_left_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_left_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .alignment = math.Vector2{ .x = 72, .y = 182 },
                    .head = debugLoadBMP(thread, platform, "test/test_hero_front_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_front_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_front_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
            },
            .tree = debugLoadBMP(thread, platform, "test2/tree00.bmp"),
        };

        shared.initializeArena(
            &state.world_arena,
            memory.permanent_storage_size - @sizeOf(shared.State),
            @as([*]u8, @ptrCast(memory.permanent_storage.?)) + @sizeOf(shared.State),
        );

        _ = addLowEntity(state, .Null, null);
        state.high_entity_count = 1;

        state.world = shared.pushStruct(&state.world_arena, world.World);
        world.initializeWorld(state.world, 1.4);

        const tiles_per_width: u32 = 17;
        const tiles_per_height: u32 = 9;

        var random_number_index: u32 = 0;
        const screen_base_x: i32 = 0;
        const screen_base_y: i32 = 0;
        const screen_base_z: i32 = 0;
        var screen_x = screen_base_x;
        var screen_y = screen_base_y;
        var chunk_z: i32 = screen_base_z;
        var door_left = false;
        var door_right = false;
        var door_top = false;
        var door_bottom = false;
        var door_up = false;
        var door_down = false;

        for (0..200) |_| {
            std.debug.assert(random_number_index < random.RANDOM_NUMBERS.len);
            var random_choice: u32 = 0;
            // if (door_up or door_down) {
            random_choice = random.RANDOM_NUMBERS[random_number_index] % 2;
            // } else {
            //     random_choice = random.RANDOM_NUMBERS[random_number_index] % 3;
            // }

            random_number_index += 1;

            var created_z_door = false;
            if (random_choice == 2) {
                created_z_door = true;

                if (chunk_z == screen_base_z) {
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
                    const abs_tile_x: i32 = screen_x * tiles_per_width + @as(i32, @intCast(tile_x));
                    const abs_tile_y: i32 = screen_y * tiles_per_height + @as(i32, @intCast(tile_y));
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

                    if (tile_value == 2) {
                        _ = addWall(state, abs_tile_x, abs_tile_y, chunk_z);
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
                if (chunk_z == screen_base_z) {
                    chunk_z = screen_base_z + 1;
                } else {
                    chunk_z = screen_base_z;
                }
            } else if (random_choice == 1) {
                screen_x += 1;
            } else {
                screen_y += 1;
            }
        }

        if (false) {
            // Fill the low entity storage with walls.
            while (state.low_entity_count < (state.low_entities.len - 16)) {
                const coordinate: i32 = @intCast(1024 + state.low_entity_count);
                _ = addWall(state, coordinate, coordinate, 0);
            }
        }

        const camera_tile_x = screen_base_x * tiles_per_width + (17 / 2);
        const camera_tile_y = screen_base_y * tiles_per_height + (9 / 2);
        const camera_tile_z = screen_base_z;

        _ = addMonster(state, camera_tile_x + 2, camera_tile_y + 2, camera_tile_z);
        _ = addFamiliar(state, camera_tile_x - 2, camera_tile_y + 2, camera_tile_z);

        setCameraPosition(state, world.chunkPositionFromTilePosition(
            state.world,
            camera_tile_x,
            camera_tile_y,
            camera_tile_z,
        ));

        memory.is_initialized = true;
    }

    const tile_side_in_pixels = 60;
    const meters_to_pixels = @as(f32, @floatFromInt(tile_side_in_pixels)) / state.world.tile_side_in_meters;

    // Handle input.
    for (&input.controllers, 0..) |controller, controller_index| {
        const low_index = state.player_index_for_controller[controller_index];

        if (low_index == 0) {
            if (controller.start_button.ended_down) {
                const entity = addPlayer(state);
                state.player_index_for_controller[controller_index] = entity.low_index;
            }
        } else {
            if (forceEntityIntoHigh(state, low_index)) |controlling_entity| {
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

                if (controlling_entity.high) |high_entity| {
                    if (controller.action_down.ended_down) {
                        high_entity.z_velocity = 3;
                    }
                }

                moveEntity(
                    state,
                    controlling_entity,
                    input.frame_delta_time,
                    input_direction,
                    if (controller.action_up.ended_down) 200.0 else 50.0,
                );
            }
        }
    }
    if (forceEntityIntoHigh(state, state.camera_following_entity_index)) |camera_following_entity| {
        if (camera_following_entity.high) |high_entity| {
            var new_camera_position = state.camera_position;
            new_camera_position.chunk_z = camera_following_entity.low.position.chunk_z;

            // Move camera when player leaves the current screen.
            if (high_entity.position.x > 9.0 * state.world.tile_side_in_meters) {
                new_camera_position.chunk_x += 17;
            } else if (high_entity.position.x < -9.0 * state.world.tile_side_in_meters) {
                new_camera_position.chunk_x -= 17;
            }
            if (high_entity.position.y > 5.0 * state.world.tile_side_in_meters) {
                new_camera_position.chunk_y += 9;
            } else if (high_entity.position.y < -5.0 * state.world.tile_side_in_meters) {
                new_camera_position.chunk_y -= 9;
            }

            if (false) {
                setCameraPosition(state, new_camera_position);
            } else {
                // Follow player position.
                setCameraPosition(state, camera_following_entity.low.position);
            }
        }
    }

    // Clear background.
    const clear_color = shared.Color{ .r = 0.5, .g = 0.5, .b = 0.5 };
    drawRectangle(
        buffer,
        math.Vector2{ .x = 0.0, .y = 0.0 },
        math.Vector2{ .x = @floatFromInt(buffer.width), .y = @floatFromInt(buffer.height) },
        clear_color,
    );
    // drawBitmap(buffer, state.backdrop, 0, 0, 0, 0, 1);

    const screen_center_x: f32 = 0.5 * @as(f32, @floatFromInt(buffer.width));
    const screen_center_y: f32 = 0.5 * @as(f32, @floatFromInt(buffer.height));

    var piece_group = shared.EntityVisiblePieceGroup{};
    var high_entity_index: u32 = 1;
    while (high_entity_index < state.high_entity_count) : (high_entity_index += 1) {
        piece_group.piece_count = 0;

        var high_entity = &state.high_entities[high_entity_index];
        const low_entity = &state.low_entities[high_entity.low_entity_index];
        const entity = shared.Entity{
            .low_index = high_entity.low_entity_index,
            .low = low_entity,
            .high = high_entity,
        };

        const delta_time = input.frame_delta_time;
        var shadow_alpha: f32 = 1 - high_entity.z;
        if (shadow_alpha < 0) {
            shadow_alpha = 0;
        }

        switch (low_entity.type) {
            .Hero => {
                var hero_bitmaps = state.hero_bitmaps[high_entity.facing_direction];
                piece_group.pushPiece(&hero_bitmaps.shadow, math.Vector2.zero(), 0, hero_bitmaps.alignment, shadow_alpha);
                piece_group.pushPiece(&hero_bitmaps.torso, math.Vector2.zero(), 0, hero_bitmaps.alignment, 1);
                piece_group.pushPiece(&hero_bitmaps.cape, math.Vector2.zero(), 0, hero_bitmaps.alignment, 1);
                piece_group.pushPiece(&hero_bitmaps.head, math.Vector2.zero(), 0, hero_bitmaps.alignment, 1);
            },
            .Wall => {
                piece_group.pushPiece(&state.tree, math.Vector2.zero(), 0, math.Vector2{ .x = 40, .y = 80 }, 1);
            },
            .Monster => {
                updateMonster(state, entity, delta_time);

                var hero_bitmaps = state.hero_bitmaps[high_entity.facing_direction];
                piece_group.pushPiece(&hero_bitmaps.shadow, math.Vector2.zero(), 0, hero_bitmaps.alignment, shadow_alpha);
                piece_group.pushPiece(&hero_bitmaps.torso, math.Vector2.zero(), 0, hero_bitmaps.alignment, 1);
            },
            .Familiar => {
                updateFamiliar(state, entity, delta_time);

                // Update head bob.
                high_entity.head_bob_time += (delta_time * 8);
                if (high_entity.head_bob_time > shared.TAU32) {
                    high_entity.head_bob_time = -shared.TAU32;
                }

                const head_z = 10 * @sin(high_entity.head_bob_time);
                var hero_bitmaps = state.hero_bitmaps[high_entity.facing_direction];
                piece_group.pushPiece(&hero_bitmaps.shadow, math.Vector2.zero(), 0, hero_bitmaps.alignment, shadow_alpha);
                piece_group.pushPiece(&hero_bitmaps.head, math.Vector2.zero(), head_z, hero_bitmaps.alignment, 1);
            },
            else => {
                unreachable;
            }
        }

        // Jump.
        const z_acceleration = -9.8;
        high_entity.z = (0.5 * z_acceleration * math.square(delta_time)) +
            high_entity.z_velocity * delta_time + high_entity.z;
        high_entity.z_velocity = z_acceleration * delta_time + high_entity.z_velocity;
        if (high_entity.z < 0) {
            high_entity.z = 0;
        }

        const entity_ground_point_x = screen_center_x + meters_to_pixels * high_entity.position.x;
        const entity_ground_point_y = screen_center_y - meters_to_pixels * high_entity.position.y;
        const entity_z = -meters_to_pixels * high_entity.z;

        if (false) {
            const tile_color = shared.Color{ .r = 1.0, .g = 1.0, .b = 0.0 };
            const entity_left_top = math.Vector2{
                .x = entity_ground_point_x - (0.5 * meters_to_pixels * low_entity.width),
                .y = entity_ground_point_y - (0.5 * meters_to_pixels * low_entity.height),
            };
            const entity_width_height = math.Vector2{
                .x = low_entity.width,
                .y = low_entity.height,
            };

            drawRectangle(
                buffer,
                entity_left_top,
                entity_left_top.add(entity_width_height.scale(meters_to_pixels).scale(0.9)),
                tile_color,
            );
        }

        var piece_group_index: u32 = 0;
        while (piece_group_index < piece_group.piece_count) : (piece_group_index += 1) {
            const piece = piece_group.pieces[piece_group_index];

            drawBitmap(
                buffer,
                piece.bitmap,
                piece.offset.x + entity_ground_point_x,
                piece.offset.y + piece.offset_z + entity_ground_point_y + entity_z,
                piece.alpha,
            );
        }
    }
}

fn setCameraPosition(state: *shared.State, new_camera_position: world.WorldPosition) void {
    std.debug.assert(validateEntityPairs(state));

    const camera_delta = world.subtractPositions(state.world, @constCast(&new_camera_position), &state.camera_position);
    state.camera_position = new_camera_position;

    const tile_span_x = 17 * 3;
    const tile_span_y = 9 * 3;
    const bounds_in_tiles = math.Vector2{ .x = tile_span_x, .y = tile_span_y };
    const camera_bounds = math.Rectangle2.fromCenterDimension(
        math.Vector2.zero(),
        bounds_in_tiles.scale(state.world.tile_side_in_meters),
    );
    const entity_offset_for_frame = camera_delta.xy.negate();
    offsetAndCheckFrequencyByArea(state, entity_offset_for_frame, camera_bounds);

    std.debug.assert(validateEntityPairs(state));

    const min_chunk_position = world.mapIntoChunkSpace(state.world, new_camera_position, camera_bounds.getMinCorner());
    const max_chunk_position = world.mapIntoChunkSpace(state.world, new_camera_position, camera_bounds.getMaxCorner());

    var chunk_y = min_chunk_position.chunk_y;
    while (chunk_y <= max_chunk_position.chunk_y) : (chunk_y += 1) {
        var chunk_x = min_chunk_position.chunk_x;
        while (chunk_x <= max_chunk_position.chunk_x) : (chunk_x += 1) {
            const opt_chunk = world.getWorldChunk(state.world, chunk_x, chunk_y, new_camera_position.chunk_z, null);

            if (opt_chunk) |chunk| {
                var opt_block: ?*world.WorldEntityBlock = &chunk.first_block;
                while (opt_block) |block| : (opt_block = block.next) {
                    var block_entity_index: u32 = 0;
                    while (block_entity_index < block.entity_count) : (block_entity_index += 1) {
                        const low_entity_index = block.low_entity_indices[block_entity_index];
                        var low_entity = state.low_entities[low_entity_index];

                        if (low_entity.high_entity_index == 0) {
                            const camera_space_position = getCameraSpacePosition(state, &low_entity);

                            if (camera_space_position.isInRectangle(camera_bounds)) {
                                _ = makeEntityHighFrequency(state, low_entity_index, camera_space_position);
                            }
                        }
                    }
                }
            }
        }
    }

    std.debug.assert(validateEntityPairs(state));
}

fn addLowEntity(state: *shared.State, entity_type: shared.EntityType, opt_world_position: ?world.WorldPosition) shared.Entity {
    std.debug.assert(state.low_entity_count < state.low_entities.len);

    const entity_index = state.low_entity_count;
    state.low_entity_count += 1;

    var low_entity = &state.low_entities[entity_index];
    low_entity.type = entity_type;

    if (opt_world_position) |world_position| {
        low_entity.position = world_position;
        world.changeEntityLocation(state.world, &state.world_arena, entity_index, null, @constCast(@ptrCast(&opt_world_position)));
    }

    return shared.Entity{
        .low_index = entity_index,
        .low = low_entity,
        .high = null,
    };
}

fn getLowEntity(state: *shared.State, index: u32) ?*shared.LowEntity {
    var entity: ?*shared.LowEntity = null;

    if (index > 0 and index < state.low_entity_count) {
        entity = &state.low_entities[index];
    }

    return entity;
}

fn forceEntityIntoHigh(state: *shared.State, low_index: u32) ?shared.Entity {
    var result: ?shared.Entity = null;

    if (low_index > 0 and low_index < state.low_entity_count) {
        result = shared.Entity{
            .low_index = low_index,
            .low = &state.low_entities[low_index],
            .high = makeEntityHighFrequency(state, low_index, null),
        };
    }

    return result;
}

fn getEntityFromHighIndex(state: *shared.State, high_entity_index: u32) ?shared.Entity {
    var result: ?shared.Entity = null;

    if (high_entity_index > 0) {
        const high_entity = &state.high_entities[high_entity_index];
        const low_entity = &state.low_entities[high_entity.low_entity_index];
        result = shared.Entity{
            .low_index = high_entity.low_entity_index,
            .low = low_entity,
            .high = high_entity,
        };
    }

    return result;
}

inline fn validateEntityPairs(state: *shared.State) bool {
    var valid = true;

    var high_entity_index: u32 = 1;
    while (high_entity_index < state.high_entity_count) : (high_entity_index += 1) {
        const high_entity = &state.high_entities[high_entity_index];
        valid = valid and (state.low_entities[high_entity.low_entity_index].high_entity_index == high_entity_index);
    }

    return valid;
}

inline fn offsetAndCheckFrequencyByArea(state: *shared.State, offset: math.Vector2, camera_bounds: math.Rectangle2) void {
    var high_entity_index: u32 = 1;
    while (high_entity_index < state.high_entity_count) {
        const high_entity = &state.high_entities[high_entity_index];

        _ = high_entity.position.addSet(offset);

        if (high_entity.position.isInRectangle(camera_bounds)) {
            high_entity_index += 1;
        } else {
            std.debug.assert(state.low_entities[high_entity.low_entity_index].high_entity_index == high_entity_index);
            _ = makeEntityLowFrequency(state, high_entity.low_entity_index);
        }
    }
}

inline fn getCameraSpacePosition(state: *shared.State, low_entity: *shared.LowEntity) math.Vector2 {
    const diff = world.subtractPositions(state.world, &low_entity.position, &state.camera_position);
    return diff.xy;
}

fn makeEntityHighFrequency(
    state: *shared.State,
    low_index: u32,
    camera_space_position: ?math.Vector2,
) ?*shared.HighEntity {
    var result: ?*shared.HighEntity = null;
    var low_entity = &state.low_entities[low_index];

    if (low_entity.high_entity_index != 0) {
        result = &state.high_entities[low_entity.high_entity_index];
    } else {
        if (state.high_entity_count < state.high_entities.len) {
            const high_index = state.high_entity_count;
            state.high_entity_count += 1;
            var high_entity = &state.high_entities[high_index];

            if (camera_space_position) |position| {
                high_entity.position = position;
            } else {
                high_entity.position = getCameraSpacePosition(state, low_entity);
            }

            high_entity.chunk_z = low_entity.position.chunk_z;
            high_entity.velocity = math.Vector2.zero();
            high_entity.facing_direction = 0;
            high_entity.low_entity_index = low_index;

            low_entity.high_entity_index = high_index;
            result = high_entity;
        } else {
            unreachable;
        }
    }

    return result;
}

inline fn makeEntityLowFrequency(state: *shared.State, low_index: u32) void {
    const low_entity = &state.low_entities[low_index];
    const high_index = low_entity.high_entity_index;

    if (high_index != 0) {
        const last_high_index = state.high_entity_count - 1;
        if (high_index != last_high_index) {
            const last_entity = state.high_entities[last_high_index];
            state.high_entities[high_index] = last_entity;
            state.low_entities[last_entity.low_entity_index].high_entity_index = high_index;
        }

        state.high_entity_count -= 1;
        low_entity.high_entity_index = 0;
    }
}

fn addWall(state: *shared.State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) shared.Entity {
    const world_position = world.chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addLowEntity(state, .Wall, world_position);

    entity.low.height = state.world.tile_side_in_meters;
    entity.low.width = state.world.tile_side_in_meters;
    entity.low.collides = true;

    return entity;
}

fn addMonster(state: *shared.State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) shared.Entity {
    const world_position = world.chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addLowEntity(state, .Monster, world_position);

    entity.low.height = 0.5;
    entity.low.width = 1.0;
    entity.low.collides = true;

    return entity;
}

fn updateMonster(state: *shared.State, entity: shared.Entity, delta_time: f32) void {
    _ = state;
    _ = entity;
    _ = delta_time;
}

fn addFamiliar(state: *shared.State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) shared.Entity {
    const world_position = world.chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addLowEntity(state, .Familiar, world_position);

    entity.low.height = 0.5;
    entity.low.width = 1.0;
    entity.low.collides = false;

    return entity;
}

fn updateFamiliar(state: *shared.State, entity: shared.Entity, delta_time: f32) void {
    var closest_hero: ?shared.Entity = null;
    var closest_hero_squared: f32 = math.square(10.0);

    var high_entity_index: u32 = 1;
    while (high_entity_index < state.high_entity_count) : (high_entity_index += 1) {
        const opt_test_entity = getEntityFromHighIndex(state, high_entity_index);

        if (opt_test_entity) |test_entity| {
            if (test_entity.low.type == .Hero) {
                const distance = test_entity.high.?.position.subtract(entity.high.?.position).lengthSquared();

                if (distance < closest_hero_squared) {
                    closest_hero = test_entity;
                    closest_hero_squared = distance;
                }
            }
        }
    }

    if (closest_hero) |hero| {
        const movement_speed = 25;
        const acceleration: f32 = 1.0;
        const one_over_length = acceleration / @sqrt(closest_hero_squared);
        const direction = hero.high.?.position.subtract(entity.high.?.position).scale(one_over_length);

        moveEntity(state, entity, delta_time, direction, movement_speed);
    }
}

fn addPlayer(state: *shared.State) shared.Entity {
    const entity = addLowEntity(state, .Hero, state.camera_position);

    entity.low.height = 0.5; // 1.4;
    entity.low.width = 1.0;
    entity.low.collides = true;

    if (state.camera_following_entity_index == 0) {
        state.camera_following_entity_index = entity.low_index;
    }

    return entity;
}

fn moveEntity(
    state: *shared.State,
    entity: shared.Entity,
    delta_time: f32,
    direction: math.Vector2,
    movement_speed: f32,
) void {
    if (entity.high) |high_entity| {
        var acceleration = direction;

        // Correct speed when multiple axes are contributing to the direction.
        const direction_length = direction.lengthSquared();
        if (direction_length > 1.0) {
            _ = acceleration.scaleSet(1.0 / intrinsics.squareRoot(direction_length));
        }

        // Calculate acceleration.
        _ = acceleration.scaleSet(movement_speed);
        _ = acceleration.addSet(high_entity.velocity.scale(8.0).negate());

        // Calculate player delta.
        var player_delta = acceleration.scale(0.5 * math.square(delta_time))
            .add(high_entity.velocity.scale(delta_time));
        high_entity.velocity = acceleration.scale(delta_time).add(high_entity.velocity);

        var iterations: u32 = 0;
        while (iterations < 4) : (iterations += 1) {
            var min_time: f32 = 1.0;
            var wall_normal = math.Vector2.zero();
            var hit_high_entity_index: u32 = 0;

            const desired_position = high_entity.position.add(player_delta);

            var test_high_entity_index: u32 = 0;
            while (test_high_entity_index < state.high_entity_count) : (test_high_entity_index += 1) {
                if (test_high_entity_index != entity.low.high_entity_index) {
                    var test_entity = shared.Entity{
                        .high = &state.high_entities[test_high_entity_index],
                        .low = undefined,
                        .low_index = 0,
                    };
                    if (test_entity.high) |test_high_entity| {
                        test_entity.low_index = test_high_entity.low_entity_index;
                        test_entity.low = &state.low_entities[test_high_entity.low_entity_index];

                        if (test_entity.low.collides) {
                            const collision_diameter = math.Vector2{
                                .x = test_entity.low.width + entity.low.width,
                                .y = test_entity.low.height + entity.low.height,
                            };
                            const min_corner = collision_diameter.scale(-0.5);
                            const max_corner = collision_diameter.scale(0.5);
                            const relative = high_entity.position.subtract(test_high_entity.position);

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
                                hit_high_entity_index = test_high_entity_index;
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
                                hit_high_entity_index = test_high_entity_index;
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
                                hit_high_entity_index = test_high_entity_index;
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
                                hit_high_entity_index = test_high_entity_index;
                            }
                        }
                    }
                }
            }

            // Apply the amount of delta allowed by collision detection.
            _ = high_entity.position.addSet(player_delta.scale(min_time));

            if (hit_high_entity_index > 0) {
                // Remove velocity that is facing into the wall.
                _ = high_entity.velocity.subtractSet(wall_normal.scale(high_entity.velocity.dot(wall_normal)));

                // Remove the applied delta.
                player_delta = desired_position.subtract(high_entity.position);
                _ = player_delta.subtractSet(wall_normal.scale(player_delta.dot(wall_normal)));

                // Update player Z when hitting a ladder.
                const hit_high_entity = &state.high_entities[hit_high_entity_index];
                const hit_low_entity = &state.low_entities[hit_high_entity.low_entity_index];
                high_entity.chunk_z += hit_low_entity.abs_tile_z_delta;
            } else {
                break;
            }
        }

        // Update facing direction based on velocity.
        if (high_entity.velocity.x == 0 and high_entity.velocity.y == 0) {
            // Keep existing facing direction when velocity is zero.
        } else if (intrinsics.absoluteValue(high_entity.velocity.x) > intrinsics.absoluteValue(high_entity.velocity.y)) {
            if (high_entity.velocity.x > 0) {
                high_entity.facing_direction = 0;
            } else {
                high_entity.facing_direction = 2;
            }
        } else if (intrinsics.absoluteValue(high_entity.velocity.x) < intrinsics.absoluteValue(high_entity.velocity.y)) {
            if (high_entity.velocity.y > 0) {
                high_entity.facing_direction = 1;
            } else {
                high_entity.facing_direction = 3;
            }
        }

        var new_position = world.mapIntoChunkSpace(state.world, state.camera_position, high_entity.position);
        world.changeEntityLocation(state.world, &state.world_arena, entity.low_index, &entity.low.position, &new_position);
        entity.low.position = new_position;
    }
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
        const epsilon_time = 0.001;
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
            pixel[0] = color.to_int();
            pixel += 1;
        }

        row += buffer.pitch;
    }
}

fn drawBitmap(
    buffer: *shared.OffscreenBuffer,
    bitmap: *shared.LoadedBitmap,
    real_x: f32,
    real_y: f32,
    alpha: f32,
) void {
    // Calculate extents.
    var min_x = intrinsics.roundReal32ToInt32(real_x);
    var min_y = intrinsics.roundReal32ToInt32(real_y);
    var max_x: i32 = @intFromFloat(real_x + @as(f32, @floatFromInt(bitmap.width)));
    var max_y: i32 = @intFromFloat(real_y + @as(f32, @floatFromInt(bitmap.height)));

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

    // Calculate offset in data.
    const clipping_offset: i32 = -source_offset_y * bitmap.width + source_offset_x;
    const offset: i32 = bitmap.width * (bitmap.height - 1) + clipping_offset;

    // Move to the correct spot in the data.
    var source_row = bitmap.data.per_pixel;
    if (offset >= 0) {
        source_row += @as(u32, @intCast(offset));
    } else {
        source_row += @abs(offset);
    }

    // Move to the correct spot in the destination.
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
