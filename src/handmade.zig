const shared = @import("shared.zig");
const world = @import("world.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const std = @import("std");

/// TODO: An overview of upcoming tasks.
///
/// Architecture exploration:
///
/// * Z-axis.
///     * Need to make a solid concept of ground levels so thet camer can be freely placed in Z and have multiple
///     ground levels in one sim region.
///     * Concept of ground in the collision loop so it can handle collisions coming onto and off of stairwells.
///     * Make sure flying things can go over low walls.
///     * How it this rendered.
///     * Z fudge!
/// * Collision detection?
///     * Fix sword collisions!
///     * Clean up predicate proliferation! Can we make a nice clean set of flag rules so that it's easy to understnad
///     how things work in terms of special handling? This may involve making the iteration handle everything
///     instead of handling overlap outside and so on.
///     * Transient collusion rules. Clear based on flag.
///         * Allow non-transient rules to override transient ones.
///     * Entry/exit?
///     * Robustness/shape definition?
///     * Implement reprojection to handle interpenetration.
/// * Implement multiple sim regions per frame.
///     * Per-entity clocking.
///     * Sim region merging? For multiple players?
///
/// * Debug code.
///     * Fonts.
///     * Logging.
///     * Diagramming.
///     * Switches, sliders etc.
///     * Draw tile chunks so we can verify things are aligned / in the chunks we want them to be in etc.
///
/// * Asset streaming.
///
/// * Audio.
///     * Sound effect triggers.
///     * Ambient sounds.
///     * Music.
///
/// * Metagame/save game?
///     * How do you enter a save slot? Multiple profiles and potential "menu world".
///     * Persistent unlocks, etc.
///     * De we allo save games? Probably yes, just for "pausing".
///     * Continuous save for crash recovery?
///
/// * Rudimentary world generation to understand which elements will be needed.
///     * Placement of background things.
///     * Connectivity?
///     * None-overlapping?
///     * Map display.
/// * AI.
///     * Rudimentary monster behaviour example.
///     * Pathfinding.
///     * AI storage.
///
/// * Animation, should lead into rendering.
///     * Skeletal animation.
///     * Particle system.
///
/// Production:
///
/// * Rendering.
/// * Game.
///     * Entity system.
///     * World generation.
///

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const LoadedBitmap = shared.LoadedBitmap;
const State = shared.State;
const TransientState = shared.TransientState;
const WorldPosition = world.WorldPosition;
const AddLowEntityResult = shared.AddLowEntityResult;

pub export fn updateAndRender(
    thread: *shared.ThreadContext,
    platform: shared.Platform,
    memory: *shared.Memory,
    input: shared.GameInput,
    buffer: *shared.OffscreenBuffer,
) void {
    const ground_buffer_width: u32 = 256;
    const ground_buffer_height: u32 = 256;

    std.debug.assert(@sizeOf(State) <= memory.permanent_storage_size);
    const state: *State = @ptrCast(@alignCast(memory.permanent_storage));
    if (!memory.is_initialized) {
        state.* = State{
            .camera_position = WorldPosition.zero(),
            .backdrop = debugLoadBMP(thread, platform, "test/test_background.bmp"),
            .hero_bitmaps = .{
                shared.HeroBitmaps{
                    .alignment = Vector2.new(72, 182),
                    .head = debugLoadBMP(thread, platform, "test/test_hero_right_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_right_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_right_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .alignment = Vector2.new(72, 182),
                    .head = debugLoadBMP(thread, platform, "test/test_hero_back_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_back_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_back_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .alignment = Vector2.new(72, 182),
                    .head = debugLoadBMP(thread, platform, "test/test_hero_left_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_left_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_left_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
                shared.HeroBitmaps{
                    .alignment = Vector2.new(72, 182),
                    .head = debugLoadBMP(thread, platform, "test/test_hero_front_head.bmp"),
                    .torso = debugLoadBMP(thread, platform, "test/test_hero_front_torso.bmp"),
                    .cape = debugLoadBMP(thread, platform, "test/test_hero_front_cape.bmp"),
                    .shadow = debugLoadBMP(thread, platform, "test/test_hero_shadow.bmp"),
                },
            },
            .tree = debugLoadBMP(thread, platform, "test2/tree00.bmp"),
            .sword = debugLoadBMP(thread, platform, "test2/rock03.bmp"),
            .stairwell = debugLoadBMP(thread, platform, "test2/rock02.bmp"),
            .grass = .{
                debugLoadBMP(thread, platform, "test2/grass00.bmp"),
                debugLoadBMP(thread, platform, "test2/grass01.bmp"),
            },
            .stone = .{
                debugLoadBMP(thread, platform, "test2/ground00.bmp"),
                debugLoadBMP(thread, platform, "test2/ground01.bmp"),
                debugLoadBMP(thread, platform, "test2/ground02.bmp"),
                debugLoadBMP(thread, platform, "test2/ground03.bmp"),
            },
            .tuft = .{
                debugLoadBMP(thread, platform, "test2/tuft00.bmp"),
                debugLoadBMP(thread, platform, "test2/tuft01.bmp"),
                debugLoadBMP(thread, platform, "test2/tuft02.bmp"),
            },
        };

        state.world_arena.initialize(
            memory.permanent_storage_size - @sizeOf(State),
            memory.permanent_storage.? + @sizeOf(State),
        );

        _ = addLowEntity(state, .Null, WorldPosition.nullPosition());

        // Define pixel sizes.
        state.meters_to_pixels = 42;
        state.pixels_to_meters = 1.0 / state.meters_to_pixels;
        state.typical_floor_height = 3;
        const chunk_dimension_in_meters = Vector3.new(
            state.pixels_to_meters * @as(f32, @floatFromInt(ground_buffer_width)),
            state.pixels_to_meters * @as(f32, @floatFromInt(ground_buffer_height)),
            state.typical_floor_height,
        );

        state.world = state.world_arena.pushStruct(world.World);
        world.initializeWorld(state.world, chunk_dimension_in_meters);

        const tiles_per_width: u32 = 17;
        const tiles_per_height: u32 = 9;
        const tile_side_in_meters: f32 = 1.4;
        const tile_depth_in_meters = state.typical_floor_height;
        state.null_collision = makeNullCollision(state);
        state.standard_room_collision = makeSimpleGroundedCollision(
            state,
            tile_side_in_meters * tiles_per_width,
            tile_side_in_meters * tiles_per_height,
            tile_depth_in_meters,
        );
        state.wall_collision = makeSimpleGroundedCollision(
            state,
            tile_side_in_meters,
            tile_side_in_meters,
            tile_depth_in_meters,
        );
        state.stair_collsion = makeSimpleGroundedCollision(
            state,
            tile_side_in_meters,
            tile_side_in_meters * 2.0,
            tile_depth_in_meters * 1.1,
        );
        state.player_collsion = makeSimpleGroundedCollision(state, 0.5, 1, 1.2);
        state.sword_collsion = makeSimpleGroundedCollision(state, 1, 0.5, 0.1);
        state.monster_collsion = makeSimpleGroundedCollision(state, 1, 1, 0.5);
        state.familiar_collsion = makeSimpleGroundedCollision(state, 1, 0.5, 0.5);

        var series = random.Series.seed(3);
        const screen_base_x: i32 = 0;
        const screen_base_y: i32 = 0;
        const screen_base_z: i32 = 0;
        var screen_x = screen_base_x;
        var screen_y = screen_base_y;
        var abs_tile_z: i32 = screen_base_z;
        var door_left = false;
        var door_right = false;
        var door_top = false;
        var door_bottom = false;
        var door_up = false;
        var door_down = false;

        for (0..200) |_| {
            // const door_direction = series.randomChoice(if (door_up or door_down) 2 else 3);
            const door_direction = series.randomChoice(2);

            var created_z_door = false;
            if (door_direction == 2) {
                created_z_door = true;

                if (abs_tile_z == screen_base_z) {
                    door_up = true;
                } else {
                    door_down = true;
                }
            } else if (door_direction == 1) {
                door_right = true;
            } else {
                door_top = true;
            }

            _ = addStandardRoom(
                state,
                screen_x * tiles_per_width + (tiles_per_width / 2),
                screen_y * tiles_per_height + (tiles_per_height / 2),
                abs_tile_z,
            );

            for (0..tiles_per_height) |tile_y| {
                for (0..tiles_per_width) |tile_x| {
                    const abs_tile_x: i32 = screen_x * tiles_per_width + @as(i32, @intCast(tile_x));
                    const abs_tile_y: i32 = screen_y * tiles_per_height + @as(i32, @intCast(tile_y));
                    var should_be_door = true;

                    // Generate walls.
                    if ((tile_x == 0) and (!door_left or (tile_y != (tiles_per_height / 2)))) {
                        should_be_door = false;
                    }
                    if ((tile_x == (tiles_per_width - 1)) and (!door_right or (tile_y != (tiles_per_height / 2)))) {
                        should_be_door = false;
                    }
                    if ((tile_y == 0) and (!door_bottom or (tile_x != (tiles_per_width / 2)))) {
                        should_be_door = false;
                    }
                    if ((tile_y == (tiles_per_height - 1)) and (!door_top or (tile_x != (tiles_per_width / 2)))) {
                        should_be_door = false;
                    }

                    if (!should_be_door) {
                        _ = addWall(state, abs_tile_x, abs_tile_y, abs_tile_z);
                    } else if (created_z_door) {
                        if (tile_x == 10 and tile_y == 5) {
                            _ = addStairs(state, abs_tile_x, abs_tile_y, if (door_down) abs_tile_z - 1 else abs_tile_z);
                        }
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

            if (door_direction == 2) {
                if (abs_tile_z == screen_base_z) {
                    abs_tile_z = screen_base_z + 1;
                } else {
                    abs_tile_z = screen_base_z;
                }
            } else if (door_direction == 1) {
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
        state.camera_position = chunkPositionFromTilePosition(
            state.world,
            camera_tile_x,
            camera_tile_y,
            camera_tile_z,
            null,
        );

        _ = addMonster(state, camera_tile_x - 3, camera_tile_y + 2, camera_tile_z);

        for (0..1) |_| {
            const familiar_offset_x: i32 = series.randomIntBetween(-7, 7);
            const familiar_offset_y: i32 = series.randomIntBetween(-3, -1);

            _ = addFamiliar(state, camera_tile_x + familiar_offset_x, camera_tile_y + familiar_offset_y, camera_tile_z);
        }

        memory.is_initialized = true;
    }

    // Transient initialization.
    std.debug.assert(@sizeOf(TransientState) <= memory.transient_storage_size);
    var transient_state: *TransientState = @ptrCast(@alignCast(memory.transient_storage));
    if (!transient_state.is_initialized) {
        transient_state.arena.initialize(
            memory.transient_storage_size - @sizeOf(TransientState),
            memory.transient_storage.? + @sizeOf(TransientState),
        );

        transient_state.ground_buffer_count = 32;
        transient_state.ground_buffers = transient_state.arena.pushArray(
            transient_state.ground_buffer_count,
            shared.GroundBuffer,
        );

        for (0..transient_state.ground_buffer_count) |ground_buffer_index| {
            const ground_buffer = &transient_state.ground_buffers[ground_buffer_index];
            transient_state.ground_bitmap_template = makeEmptyBitmap(
                &transient_state.arena,
                ground_buffer_width,
                ground_buffer_height,
                false,
            );
            ground_buffer.memory = transient_state.ground_bitmap_template.memory;
            ground_buffer.position = WorldPosition.nullPosition();
        }

        transient_state.is_initialized = true;
    }

    if (input.executable_reloaded) {
        for (0..transient_state.ground_buffer_count) |ground_buffer_index| {
            const ground_buffer = &transient_state.ground_buffers[ground_buffer_index];
            ground_buffer.position = WorldPosition.nullPosition();
        }
    }

    const meters_to_pixels: f32 = state.meters_to_pixels;
    const pixels_to_meters: f32 = 1.0 / meters_to_pixels;

    // Handle input.
    for (&input.controllers, 0..) |controller, controller_index| {
        const controlled_hero = &state.controlled_heroes[controller_index];
        controlled_hero.movement_direction = Vector2.zero();
        controlled_hero.vertical_direction = 0;
        controlled_hero.sword_direction = Vector2.zero();

        if (controlled_hero.entity_index == 0) {
            if (controller.start_button.ended_down) {
                controlled_hero.* = shared.ControlledHero{};
                controlled_hero.entity_index = addPlayer(state).low_index;
            }
        } else {
            if (controller.is_analog) {
                controlled_hero.movement_direction = Vector2.new(controller.stick_average_x, controller.stick_average_y);
            } else {
                if (controller.move_up.ended_down) {
                    controlled_hero.movement_direction = controlled_hero.movement_direction.plus(Vector2.new(0, 1));
                }
                if (controller.move_down.ended_down) {
                    controlled_hero.movement_direction = controlled_hero.movement_direction.plus(Vector2.new(0, -1));
                }
                if (controller.move_left.ended_down) {
                    controlled_hero.movement_direction = controlled_hero.movement_direction.plus(Vector2.new(-1, 0));
                }
                if (controller.move_right.ended_down) {
                    controlled_hero.movement_direction = controlled_hero.movement_direction.plus(Vector2.new(1, 0));
                }
            }

            if (controller.start_button.ended_down) {
                controlled_hero.vertical_direction = 3;
            }

            if (controller.action_up.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(0, 1));
            }
            if (controller.action_down.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(0, -1));
            }
            if (controller.action_left.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(-1, 0));
            }
            if (controller.action_right.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(1, 0));
            }
        }
    }

    // Create draw buffer.
    var draw_buffer_ = LoadedBitmap{
        .width = buffer.width,
        .height = buffer.height,
        .pitch = @intCast(buffer.pitch),
        .memory = @ptrCast(buffer.memory),
    };
    const draw_buffer = &draw_buffer_;

    // Clear background.
    const clear_color = Color.new(0.5, 0.5, 0.5, 1);
    drawRectangle(
        draw_buffer,
        Vector2.zero(),
        Vector2.new(@floatFromInt(draw_buffer.width), @floatFromInt(draw_buffer.height)),
        clear_color,
    );

    const screen_center = Vector2.new(
        0.5 * @as(f32, @floatFromInt(draw_buffer.width)),
        0.5 * @as(f32, @floatFromInt(draw_buffer.height)),
    );
    const screen_size = Vector3.newI(buffer.width, buffer.height, 0).scaledTo(pixels_to_meters);
    const camera_bounds_in_meters = math.Rectangle3.fromCenterDimension(Vector3.zero(), screen_size);

    // Draw ground.
    {
        var ground_buffer_index: u32 = 0;
        while (ground_buffer_index < transient_state.ground_buffer_count) : (ground_buffer_index += 1) {
            const ground_buffer = transient_state.ground_buffers[ground_buffer_index];

            if (ground_buffer.position.isValid()) {
                var bitmap = transient_state.ground_bitmap_template;
                bitmap.memory = ground_buffer.memory;
                const delta = world.subtractPositions(
                    state.world,
                    &ground_buffer.position,
                    &state.camera_position,
                ).scaledTo(meters_to_pixels);
                const ground = Vector2.new(
                    screen_center.x() + delta.x() - 0.5 * @as(f32, @floatFromInt(bitmap.width)),
                    screen_center.y() - delta.y() - 0.5 * @as(f32, @floatFromInt(bitmap.height)),
                );
                drawBitmap(draw_buffer, &bitmap, ground.x(), ground.y(), 1);
            }
        }
    }

    // Populate ground chunks.
    {
        const min_chunk_position = world.mapIntoChunkSpace(
            state.world,
            state.camera_position,
            camera_bounds_in_meters.getMinCorner(),
        );
        const max_chunk_position = world.mapIntoChunkSpace(
            state.world,
            state.camera_position,
            camera_bounds_in_meters.getMaxCorner(),
        );

        var chunk_z = min_chunk_position.chunk_z;
        while (chunk_z <= max_chunk_position.chunk_z) : (chunk_z += 1) {
            var chunk_y = min_chunk_position.chunk_y;
            while (chunk_y <= max_chunk_position.chunk_y) : (chunk_y += 1) {
                var chunk_x = min_chunk_position.chunk_x;
                while (chunk_x <= max_chunk_position.chunk_x) : (chunk_x += 1) {
                    const chunk_center = world.centeredChunkPoint(chunk_x, chunk_y, chunk_z);
                    const relative_position = world.subtractPositions(
                        state.world,
                        &chunk_center,
                        &state.camera_position,
                    );

                    const screen_position = Vector2.new(
                        screen_center.x() + meters_to_pixels * relative_position.x(),
                        screen_center.y() - meters_to_pixels * relative_position.y(),
                    );
                    const screen_dimension = state.world.chunk_dimension_in_meters.xy().scaledTo(meters_to_pixels);

                    var opt_furthest_buffer: ?*shared.GroundBuffer = null;
                    var furthest_buffer_length_squared: f32 = 0;
                    var ground_buffer_index: u32 = 0;
                    while (ground_buffer_index < transient_state.ground_buffer_count) : (ground_buffer_index += 1) {
                        const ground_buffer = &transient_state.ground_buffers[ground_buffer_index];
                        if (world.areInSameChunk(state.world, &ground_buffer.position, &chunk_center)) {
                            // Buffer already exists.
                            opt_furthest_buffer = null;
                            break;
                        } else if (ground_buffer.position.isValid()) {
                            const buffer_relative_position = world.subtractPositions(
                                state.world,
                                &ground_buffer.position,
                                &state.camera_position,
                            );
                            const buffer_length_squared = buffer_relative_position.xy().lengthSquared();
                            if (buffer_length_squared > furthest_buffer_length_squared) {
                                opt_furthest_buffer = ground_buffer;
                                furthest_buffer_length_squared = buffer_length_squared;
                            }
                        } else {
                            furthest_buffer_length_squared = std.math.floatMax(f32);
                            opt_furthest_buffer = ground_buffer;
                        }
                    }

                    if (opt_furthest_buffer) |furthest_buffer| {
                        fillGroundChunk(transient_state, state, furthest_buffer, &chunk_center);
                    }

                    if (false) {
                        drawRectangleOutline(
                            draw_buffer,
                            screen_position.minus(screen_dimension.scaledTo(0.5)),
                            screen_position.plus(screen_dimension.scaledTo(0.5)),
                            Color.new(1, 1, 0, 1),
                            2,
                        );
                    }
                }
            }
        }
    }

    const simulation_bounds_expansion = Vector3.new(15, 15, 15);
    const simulation_bounds = camera_bounds_in_meters.addRadius(simulation_bounds_expansion);
    const sim_memory = transient_state.arena.beginTemporaryMemory();
    const screen_sim_region = sim.beginSimulation(
        state,
        &transient_state.arena,
        state.world,
        state.camera_position,
        simulation_bounds,
        input.frame_delta_time,
    );

    var piece_group = shared.EntityVisiblePieceGroup{
        .state = state,
    };
    var entity_index: u32 = 0;
    while (entity_index < screen_sim_region.entity_count) : (entity_index += 1) {
        const entity = &screen_sim_region.entities[entity_index];

        if (entity.updatable) {
            piece_group.piece_count = 0;

            const delta_time = input.frame_delta_time;
            const shadow_alpha: f32 = math.clampf01(1 - 0.5 * entity.position.z());
            var move_spec = sim.MoveSpec{};
            var acceleration = Vector3.zero();

            switch (entity.type) {
                .Hero => {
                    for (state.controlled_heroes) |controlled_hero| {
                        if (controlled_hero.entity_index == entity.storage_index) {
                            if (controlled_hero.vertical_direction != 0) {
                                entity.velocity = Vector3.new(
                                    entity.velocity.x(),
                                    entity.velocity.y(),
                                    controlled_hero.vertical_direction,
                                );
                            }

                            move_spec = sim.MoveSpec{
                                .speed = 50,
                                .drag = 8,
                                .unit_max_acceleration = true,
                            };
                            acceleration = controlled_hero.movement_direction.toVector3(0);

                            if (controlled_hero.sword_direction.x() != 0 or controlled_hero.sword_direction.y() != 0) {
                                if (entity.sword.ptr) |sword| {
                                    if (sword.isSet(sim.SimEntityFlags.Nonspatial.toInt())) {
                                        sword.distance_limit = 5.0;
                                        sword.makeSpatial(
                                            entity.position,
                                            entity.velocity.plus(
                                                controlled_hero.sword_direction.toVector3(0).scaledTo(5.0),
                                            ),
                                        );
                                        addCollisionRule(state, sword.storage_index, entity.storage_index, false);
                                    }
                                }
                            }
                        }
                    }

                    var hero_bitmaps = state.hero_bitmaps[entity.facing_direction];
                    piece_group.pushBitmap(&hero_bitmaps.shadow, Vector2.zero(), 0, hero_bitmaps.alignment, shadow_alpha, 0);
                    piece_group.pushBitmap(&hero_bitmaps.torso, Vector2.zero(), 0, hero_bitmaps.alignment, 1, 1);
                    piece_group.pushBitmap(&hero_bitmaps.cape, Vector2.zero(), 0, hero_bitmaps.alignment, 1, 1);
                    piece_group.pushBitmap(&hero_bitmaps.head, Vector2.zero(), 0, hero_bitmaps.alignment, 1, 1);

                    drawHitPoints(entity, &piece_group);
                },
                .Sword => {
                    move_spec = sim.MoveSpec{
                        .speed = 0,
                        .drag = 0,
                        .unit_max_acceleration = false,
                    };

                    if (entity.distance_limit == 0) {
                        entity.makeNonSpatial();
                        clearCollisionRulesFor(state, entity.storage_index);
                        continue;
                    }

                    var hero_bitmaps = state.hero_bitmaps[entity.facing_direction];
                    piece_group.pushBitmap(&hero_bitmaps.shadow, Vector2.zero(), 0, hero_bitmaps.alignment, shadow_alpha, 0);
                    piece_group.pushBitmap(&state.sword, Vector2.zero(), 0, Vector2.new(29, 10), 1, 1);
                },
                .Wall => {
                    piece_group.pushBitmap(&state.tree, Vector2.zero(), 0, Vector2.new(40, 80), 1, 1);
                },
                .Stairwell => {
                    const stairwell_color1 = Color.new(1, 0.5, 0, 1);
                    const stairwell_color2 = Color.new(1, 1, 0, 1);
                    piece_group.pushRectangle(entity.walkable_dimension, Vector2.zero(), 0, stairwell_color1, 0);
                    piece_group.pushRectangle(entity.walkable_dimension, Vector2.zero(), entity.walkable_height, stairwell_color2, 0);
                },
                .Monster => {
                    var hero_bitmaps = state.hero_bitmaps[entity.facing_direction];
                    piece_group.pushBitmap(&hero_bitmaps.shadow, Vector2.zero(), 0, hero_bitmaps.alignment, shadow_alpha, 1);
                    piece_group.pushBitmap(&hero_bitmaps.torso, Vector2.zero(), 0, hero_bitmaps.alignment, 1, 1);

                    drawHitPoints(entity, &piece_group);
                },
                .Familiar => {
                    var closest_hero: ?*sim.SimEntity = null;
                    var closest_hero_squared: f32 = math.square(10.0);

                    var hero_entity_index: u32 = 0;
                    while (hero_entity_index < screen_sim_region.entity_count) : (hero_entity_index += 1) {
                        var test_entity = &screen_sim_region.entities[hero_entity_index];
                        if (test_entity.type == .Hero) {
                            const distance = test_entity.position.minus(entity.position).lengthSquared();

                            if (distance < closest_hero_squared) {
                                closest_hero = test_entity;
                                closest_hero_squared = distance;
                            }
                        }
                    }

                    // if (closest_hero) |hero| {
                    //     if (closest_hero_squared > math.square(3.0)) {
                    //         const speed: f32 = 1.0;
                    //         const one_over_length = speed / @sqrt(closest_hero_squared);
                    //         acceleration = hero.position.minus(entity.position).scaledTo(one_over_length);
                    //     }
                    // }

                    move_spec = sim.MoveSpec{
                        .speed = 25,
                        .drag = 8,
                        .unit_max_acceleration = true,
                    };

                    // Update head bob.
                    entity.head_bob_time += delta_time * 2;
                    if (entity.head_bob_time > shared.TAU32) {
                        entity.head_bob_time = -shared.TAU32;
                    }

                    const head_bob_sine = @sin(2 * entity.head_bob_time);
                    const head_z = 0.25 * head_bob_sine;
                    const head_shadow_alpha = (0.5 * shadow_alpha) + (0.2 * head_bob_sine);

                    var hero_bitmaps = state.hero_bitmaps[entity.facing_direction];
                    piece_group.pushBitmap(&hero_bitmaps.shadow, Vector2.zero(), 0, hero_bitmaps.alignment, head_shadow_alpha, 0);
                    piece_group.pushBitmap(&hero_bitmaps.head, Vector2.zero(), head_z, hero_bitmaps.alignment, 1, 1);
                },
                .Space => {
                    const space_color = Color.new(0, 0.5, 1, 1);
                    var volume_index: u32 = 0;
                    while (volume_index < entity.collision.volume_count) : (volume_index += 1) {
                        const volume = entity.collision.volumes[volume_index];
                        piece_group.pushRectangleOutline(volume.dimension.xy(), volume.offset_position.xy(), 0, space_color, 0);
                    }
                },
                else => {
                    unreachable;
                },
            }

            if (!entity.isSet(sim.SimEntityFlags.Nonspatial.toInt()) and
                entity.isSet(sim.SimEntityFlags.Movable.toInt()))
            {
                sim.moveEntity(
                    state,
                    screen_sim_region,
                    entity,
                    delta_time,
                    acceleration,
                    &move_spec,
                );
            }

            var piece_group_index: u32 = 0;
            while (piece_group_index < piece_group.piece_count) : (piece_group_index += 1) {
                const piece = piece_group.pieces[piece_group_index];
                const entity_base_position = entity.getGroundPoint();
                const z_fudge = 1.0 + 0.1 * (entity_base_position.z() - piece.offset_z);
                const entity_ground_point_x = screen_center.x() + meters_to_pixels * z_fudge * entity_base_position.x();
                const entity_ground_point_y = screen_center.y() - meters_to_pixels * z_fudge * entity_base_position.y();
                const entity_z = -meters_to_pixels * entity_base_position.z();

                const center = Vector2.new(
                    piece.offset.x() + entity_ground_point_x,
                    piece.offset.y() + entity_ground_point_y + (entity_z * piece.entity_z_amount),
                );

                if (piece.bitmap) |bitmap| {
                    drawBitmap(draw_buffer, bitmap, center.x(), center.y(), piece.color.a());
                } else {
                    const dimension = piece.dimension.scaledTo(meters_to_pixels);
                    drawRectangle(
                        draw_buffer,
                        center.minus(dimension.scaledTo(0.5)),
                        center.plus(dimension.scaledTo(0.5)),
                        piece.color,
                    );
                }
            }
        }
    }

    sim.endSimulation(state, screen_sim_region);
    transient_state.arena.endTemporaryMemory(sim_memory);

    state.world_arena.checkArena();
    transient_state.arena.checkArena();
}

pub fn chunkPositionFromTilePosition(
    game_world: *world.World,
    abs_tile_x: i32,
    abs_tile_y: i32,
    abs_tile_z: i32,
    opt_additional_offset: ?Vector3,
) WorldPosition {
    const tile_side_in_meters = 1.4;
    const tile_depth_in_meters = 3.0;

    const base_position = WorldPosition.zero();
    const tile_dimension = Vector3.new(
        tile_side_in_meters,
        tile_side_in_meters,
        tile_depth_in_meters,
    );
    var offset = Vector3.new(
        @floatFromInt(abs_tile_x),
        @floatFromInt(abs_tile_y),
        @floatFromInt(abs_tile_z),
    ).hadamardProduct(tile_dimension);

    if (opt_additional_offset) |additional_offset| {
        offset = offset.plus(additional_offset);
    }

    const result = world.mapIntoChunkSpace(game_world, base_position, offset);

    std.debug.assert(world.isVector3Canonical(game_world, result.offset));

    return result;
}

fn addLowEntity(state: *State, entity_type: sim.EntityType, world_position: WorldPosition) AddLowEntityResult {
    std.debug.assert(state.low_entity_count < state.low_entities.len);

    const low_entity_index = state.low_entity_count;
    state.low_entity_count += 1;

    var low_entity = &state.low_entities[low_entity_index];
    low_entity.sim.collision = state.null_collision;
    low_entity.sim.type = entity_type;

    low_entity.position = WorldPosition.nullPosition();
    world.changeEntityLocation(
        &state.world_arena,
        state.world,
        low_entity,
        low_entity_index,
        world_position,
    );

    return AddLowEntityResult{
        .low_index = low_entity_index,
        .low = low_entity,
    };
}

fn addGroundedEntity(
    state: *State,
    entity_type: sim.EntityType,
    world_position: WorldPosition,
    collision: *sim.SimEntityCollisionVolumeGroup,
) AddLowEntityResult {
    const entity = addLowEntity(state, entity_type, world_position);
    entity.low.sim.collision = collision;
    return entity;
}

fn addStandardRoom(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Space, world_position, state.standard_room_collision);

    entity.low.sim.addFlags(sim.SimEntityFlags.Traversable.toInt());

    return entity;
}

fn addWall(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Wall, world_position, state.wall_collision);

    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt());

    return entity;
}

fn addStairs(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Stairwell, world_position, state.stair_collsion);

    entity.low.sim.walkable_dimension = entity.low.sim.collision.total_volume.dimension.xy();
    entity.low.sim.walkable_height = state.typical_floor_height;
    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt());

    return entity;
}

fn addPlayer(state: *State) AddLowEntityResult {
    const entity = addGroundedEntity(state, .Hero, state.camera_position, state.player_collsion);

    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

    initHitPoints(&entity.low.sim, 3);

    const sword = addSword(state);
    entity.low.sim.sword = sim.EntityReference{ .index = sword.low_index };

    if (state.camera_following_entity_index == 0) {
        state.camera_following_entity_index = entity.low_index;
    }

    return entity;
}

fn addSword(state: *State) AddLowEntityResult {
    const entity = addLowEntity(state, .Sword, WorldPosition.nullPosition());

    entity.low.sim.collision = state.sword_collsion;
    entity.low.sim.addFlags(sim.SimEntityFlags.Movable.toInt());

    return entity;
}

fn addMonster(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Monster, world_position, state.monster_collsion);

    entity.low.sim.collision = state.monster_collsion;
    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

    initHitPoints(&entity.low.sim, 3);

    return entity;
}

fn addFamiliar(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Familiar, world_position, state.familiar_collsion);

    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

    return entity;
}

fn makeSimpleGroundedCollision(
    state: *State,
    x_dimension: f32,
    y_dimension: f32,
    z_dimension: f32,
) *sim.SimEntityCollisionVolumeGroup {
    const group = state.world_arena.pushStruct(sim.SimEntityCollisionVolumeGroup);

    group.volume_count = 1;
    group.volumes = state.world_arena.pushArray(group.volume_count, sim.SimEntityCollisionVolume);
    group.total_volume.offset_position = Vector3.new(0, 0, 0.5 * z_dimension);
    group.total_volume.dimension = Vector3.new(x_dimension, y_dimension, z_dimension);
    group.volumes[0] = group.total_volume;

    return group;
}

fn makeNullCollision(state: *State) *sim.SimEntityCollisionVolumeGroup {
    const group = state.world_arena.pushStruct(sim.SimEntityCollisionVolumeGroup);

    group.volume_count = 0;
    group.volumes = undefined;
    group.total_volume.offset_position = Vector3.zero();
    group.total_volume.dimension = Vector3.zero();

    return group;
}

pub fn addCollisionRule(state: *State, in_storage_index_a: u32, in_storage_index_b: u32, can_collide: bool) void {
    var storage_index_a = in_storage_index_a;
    var storage_index_b = in_storage_index_b;

    // Sort entities based on storage index.
    if (storage_index_a > storage_index_b) {
        const temp = storage_index_a;
        storage_index_a = storage_index_b;
        storage_index_b = temp;
    }

    // Look for an existing rule in the hash.
    const hash_bucket = storage_index_a & ((state.collision_rule_hash.len) - 1);
    var found_rule: ?*shared.PairwiseCollisionRule = null;
    var opt_rule: ?*shared.PairwiseCollisionRule = state.collision_rule_hash[hash_bucket];
    while (opt_rule) |rule| : (opt_rule = rule.next_in_hash) {
        if (rule.storage_index_a == storage_index_a and rule.storage_index_b == storage_index_b) {
            found_rule = rule;
            break;
        }
    }

    // Create a new rule if it didn't exist.
    if (found_rule == null) {
        found_rule = state.first_free_collision_rule;

        if (found_rule) |rule| {
            state.first_free_collision_rule = rule.next_in_hash;
        } else {
            found_rule = state.world_arena.pushStruct(shared.PairwiseCollisionRule);
        }

        found_rule.?.next_in_hash = state.collision_rule_hash[hash_bucket];
        state.collision_rule_hash[hash_bucket] = found_rule.?;
    }

    // Apply the rule settings.
    if (found_rule) |found| {
        found.storage_index_a = storage_index_a;
        found.storage_index_b = storage_index_b;
        found.can_collide = can_collide;
    }
}

pub fn clearCollisionRulesFor(state: *State, storage_index: u32) void {
    var hash_bucket: u32 = 0;
    while (hash_bucket < state.collision_rule_hash.len) : (hash_bucket += 1) {
        var opt_rule = &state.collision_rule_hash[hash_bucket];
        while (opt_rule.*) |rule| {
            if (rule.storage_index_a == storage_index or rule.storage_index_b == storage_index) {
                const removed_rule = rule;

                opt_rule.* = rule.next_in_hash;

                removed_rule.next_in_hash = state.first_free_collision_rule;
                state.first_free_collision_rule = removed_rule;
            } else {
                opt_rule = &rule.next_in_hash;
            }
        }
    }
}

fn initHitPoints(entity: *sim.SimEntity, count: u32) void {
    std.debug.assert(count <= entity.hit_points.len);

    entity.hit_point_max = count;

    var hit_point_index: u32 = 0;
    while (hit_point_index < entity.hit_point_max) : (hit_point_index += 1) {
        const hit_point = &entity.hit_points[hit_point_index];

        hit_point.flags = 0;
        hit_point.filled_amount = shared.HIT_POINT_SUB_COUNT;
    }
}

fn drawHitPoints(entity: *sim.SimEntity, piece_group: *shared.EntityVisiblePieceGroup) void {
    if (entity.hit_point_max >= 1) {
        const hit_point_dimension = Vector2.new(0.2, 0.2);
        const hit_point_spacing_x = hit_point_dimension.x() * 2;

        var hit_position = Vector2.new(-0.5 * @as(f32, @floatFromInt(entity.hit_point_max - 1)) * hit_point_spacing_x, -0.25);
        const hit_position_delta = Vector2.new(hit_point_spacing_x, 0);
        for (0..@intCast(entity.hit_point_max)) |hit_point_index| {
            const hit_point = entity.hit_points[hit_point_index];
            var hit_point_color = Color.new(1, 0, 0, 1);

            if (hit_point.filled_amount == 0) {
                hit_point_color = Color.new(0.2, 0.2, 0.2, 1);
            }

            piece_group.pushRectangle(hit_point_dimension, hit_position, 0, hit_point_color, 0);
            hit_position = hit_position.plus(hit_position_delta);
        }
    }
}

pub export fn getSoundSamples(
    thread: *shared.ThreadContext,
    memory: *shared.Memory,
    sound_buffer: *shared.SoundOutputBuffer,
) void {
    _ = thread;

    const state: *State = @ptrCast(@alignCast(memory.permanent_storage));
    outputSound(sound_buffer, shared.MIDDLE_C, state);
}

fn fillGroundChunk(
    transient_state: *TransientState,
    state: *State,
    ground_buffer: *shared.GroundBuffer,
    chunk_position: *const world.WorldPosition,
) void {
    var buffer = transient_state.ground_bitmap_template;
    buffer.memory = ground_buffer.memory;

    ground_buffer.position = chunk_position.*;

    const width: f32 = @floatFromInt(buffer.width);
    const height: f32 = @floatFromInt(buffer.height);

    var chunk_offset_y: i32 = -1;
    while (chunk_offset_y <= 1) : (chunk_offset_y += 1) {
        var chunk_offset_x: i32 = -1;
        while (chunk_offset_x <= 1) : (chunk_offset_x += 1) {
            const chunk_x = chunk_position.chunk_x + chunk_offset_x;
            const chunk_y = chunk_position.chunk_y + chunk_offset_y;
            const chunk_z = chunk_position.chunk_z;
            const center = Vector2.new(
                @as(f32, @floatFromInt(chunk_offset_x)) * width,
                -@as(f32, @floatFromInt(chunk_offset_y)) * height,
            );

            const raw_seed: i32 = 139 * chunk_x + 593 * chunk_y + 329 * chunk_z;
            const seed: u32 = if (raw_seed >= 0) @intCast(raw_seed) else 0 -% @abs(raw_seed);
            var series = random.Series.seed(seed);

            var grass_index: u32 = 0;
            while (grass_index < 100) : (grass_index += 1) {
                var stamp: LoadedBitmap = undefined;

                if (series.randomChoice(2) == 1) {
                    stamp = state.grass[series.randomChoice(state.grass.len)];
                } else {
                    stamp = state.stone[series.randomChoice(state.stone.len)];
                }

                const bitmap_center = Vector2.newI(stamp.width, stamp.height).scaledTo(0.5);
                const offset = Vector2.new(width * series.randomUnilateral(), height * series.randomUnilateral());
                const position = center.plus(offset.minus(bitmap_center));

                drawBitmap(&buffer, &stamp, position.x(), position.y(), 1);
            }
        }
    }

    chunk_offset_y = -1;
    while (chunk_offset_y <= 1) : (chunk_offset_y += 1) {
        var chunk_offset_x: i32 = -1;
        while (chunk_offset_x <= 1) : (chunk_offset_x += 1) {
            const chunk_x = chunk_position.chunk_x + chunk_offset_x;
            const chunk_y = chunk_position.chunk_y + chunk_offset_y;
            const chunk_z = chunk_position.chunk_z;
            const center = Vector2.new(
                @as(f32, @floatFromInt(chunk_offset_x)) * width,
                -@as(f32, @floatFromInt(chunk_offset_y)) * height,
            );

            const raw_seed: i32 = 139 * chunk_x + 593 * chunk_y + 329 * chunk_z;
            const seed: u32 = if (raw_seed >= 0) @intCast(raw_seed) else 0 -% @abs(raw_seed);
            var series = random.Series.seed(seed);

            var grass_index: u32 = 0;
            while (grass_index < 50) : (grass_index += 1) {
                var stamp: LoadedBitmap = state.tuft[series.randomChoice(state.tuft.len)];

                const bitmap_center = Vector2.newI(stamp.width, stamp.height).scaledTo(0.5);
                const offset = Vector2.new(width * series.randomUnilateral(), height * series.randomUnilateral());
                const position = center.plus(offset.minus(bitmap_center));

                drawBitmap(&buffer, &stamp, position.x(), position.y(), 1);
            }
        }
    }
}

fn drawRectangle(
    draw_buffer: *LoadedBitmap,
    min: Vector2,
    max: Vector2,
    color: Color,
) void {
    // Round input values.
    var min_x = intrinsics.floorReal32ToInt32(min.x());
    var min_y = intrinsics.floorReal32ToInt32(min.y());
    var max_x = intrinsics.floorReal32ToInt32(max.x());
    var max_y = intrinsics.floorReal32ToInt32(max.y());

    // Clip input values to buffer.
    if (min_x < 0) {
        min_x = 0;
    }
    if (min_y < 0) {
        min_y = 0;
    }
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Set the pointer to the top left corner of the rectangle.
    var row: [*]u8 = @ptrCast(draw_buffer.memory);
    row += @as(u32, @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch)))));

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            pixel[0] = shared.colorToInt(color);
            pixel += 1;
        }

        row += @as(usize, @intCast(draw_buffer.pitch));
    }
}

pub fn drawRectangleOutline(
    draw_buffer: *LoadedBitmap,
    min: Vector2,
    max: Vector2,
    color: Color,
    radius: f32,
) void {
    // Top.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, min.y() - radius),
        Vector2.new(max.x() + radius, min.y() + radius),
        color,
    );

    // Bottom.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, max.y() - radius),
        Vector2.new(max.x() + radius, max.y() + radius),
        color,
    );

    // Left.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, min.y() - radius),
        Vector2.new(min.x() + radius, max.y() + radius),
        color,
    );

    // Right.
    drawRectangle(
        draw_buffer,
        Vector2.new(max.x() - radius, min.y() - radius),
        Vector2.new(max.x() + radius, max.y() + radius),
        color,
    );
}

fn drawBitmap(
    draw_buffer: *LoadedBitmap,
    bitmap: *LoadedBitmap,
    real_x: f32,
    real_y: f32,
    in_alpha: f32,
) void {
    // TODO: Should we really clamp here?
    const alpha = math.clampf01(in_alpha);

    // The pixel color calculation below doesn't handle sizes outside the range of 0 - 1.
    std.debug.assert(alpha >= 0 and alpha <= 1);

    // Calculate extents.
    var min_x = intrinsics.floorReal32ToInt32(real_x);
    var min_y = intrinsics.floorReal32ToInt32(real_y);
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
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Move to the correct spot in the data.
    const source_offset: i32 =
        @intCast(source_offset_y * @as(i32, @intCast(bitmap.pitch)) + shared.BITMAP_BYTES_PER_PIXEL * source_offset_x);
    var source_row: [*]u8 = @ptrCast(bitmap.memory);
    if (source_offset >= 0) {
        source_row += @as(usize, @intCast(source_offset));
    } else {
        source_row -= @as(usize, @intCast(-source_offset));
    }

    // Move to the correct spot in the destination.
    const dest_offset: usize = @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch))));
    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);
    dest_row += dest_offset;

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(source_row));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            const sa: f32 = @floatFromInt((source[0] >> 24) & 0xFF);
            const rsa: f32 = alpha * (sa / 255.0);
            const sr: f32 = alpha * @as(f32, @floatFromInt((source[0] >> 16) & 0xFF));
            const sg: f32 = alpha * @as(f32, @floatFromInt((source[0] >> 8) & 0xFF));
            const sb: f32 = alpha * @as(f32, @floatFromInt((source[0] >> 0) & 0xFF));

            const da: f32 = @floatFromInt((dest[0] >> 24) & 0xFF);
            const rda: f32 = (da / 255.0);
            const dr: f32 = @floatFromInt((dest[0] >> 16) & 0xFF);
            const dg: f32 = @floatFromInt((dest[0] >> 8) & 0xFF);
            const db: f32 = @floatFromInt((dest[0] >> 0) & 0xFF);

            const inv_rsa = (1.0 - rsa);
            const a = 255.0 * (rsa + rda - rsa * rda);
            const r = inv_rsa * dr + sr;
            const g = inv_rsa * dg + sg;
            const b = inv_rsa * db + sb;

            dest[0] = ((@as(u32, @intFromFloat(a + 0.5)) << 24) |
                (@as(u32, @intFromFloat(r + 0.5)) << 16) |
                (@as(u32, @intFromFloat(g + 0.5)) << 8) |
                (@as(u32, @intFromFloat(b + 0.5)) << 0));

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
        if (bitmap.pitch >= 0) {
            source_row += @as(usize, @intCast(bitmap.pitch));
        } else {
            source_row -= @as(usize, @intCast(-bitmap.pitch));
        }
    }
}

fn drawBitmapMatte(
    draw_buffer: *LoadedBitmap,
    bitmap: *LoadedBitmap,
    real_x: f32,
    real_y: f32,
    in_alpha: f32,
) void {
    // TODO: Should we really clamp here?
    const alpha = math.clampf01(in_alpha);

    // The pixel color calculation below doesn't handle sizes outside the range of 0 - 1.
    std.debug.assert(alpha >= 0 and alpha <= 1);

    // Calculate extents.
    var min_x = intrinsics.floorReal32ToInt32(real_x);
    var min_y = intrinsics.floorReal32ToInt32(real_y);
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
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Move to the correct spot in the data.
    const source_offset: i32 =
        @intCast(source_offset_y * @as(i32, @intCast(bitmap.pitch)) + shared.BITMAP_BYTES_PER_PIXEL * source_offset_x);
    var source_row: [*]u8 = @ptrCast(bitmap.memory);
    if (source_offset >= 0) {
        source_row += @as(usize, @intCast(source_offset));
    } else {
        source_row -= @as(usize, @intCast(-source_offset));
    }

    // Move to the correct spot in the destination.
    const dest_offset: usize = @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch))));
    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);
    dest_row += dest_offset;

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(source_row));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            const sa: f32 = @floatFromInt((source[0] >> 24) & 0xFF);
            const rsa: f32 = alpha * (sa / 255.0);

            const da: f32 = @floatFromInt((dest[0] >> 24) & 0xFF);
            const dr: f32 = @floatFromInt((dest[0] >> 16) & 0xFF);
            const dg: f32 = @floatFromInt((dest[0] >> 8) & 0xFF);
            const db: f32 = @floatFromInt((dest[0] >> 0) & 0xFF);

            const inv_rsa = (1.0 - rsa);
            const a = inv_rsa * da;
            const r = inv_rsa * dr;
            const g = inv_rsa * dg;
            const b = inv_rsa * db;

            dest[0] = ((@as(u32, @intFromFloat(a + 0.5)) << 24) |
                (@as(u32, @intFromFloat(r + 0.5)) << 16) |
                (@as(u32, @intFromFloat(g + 0.5)) << 8) |
                (@as(u32, @intFromFloat(b + 0.5)) << 0));

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
        if (bitmap.pitch >= 0) {
            source_row += @as(usize, @intCast(bitmap.pitch));
        } else {
            source_row -= @as(usize, @intCast(-bitmap.pitch));
        }
    }
}

fn clearBitmap(bitmap: *LoadedBitmap) void {
    if (bitmap.memory) |*memory| {
        const total_bitmap_size: u32 = @intCast(bitmap.*.width * bitmap.*.height * shared.BITMAP_BYTES_PER_PIXEL);
        shared.zeroSize(total_bitmap_size, memory.*);
    }
}

fn makeEmptyBitmap(arena: *shared.MemoryArena, width: i32, height: i32, clear_to_zero: bool) LoadedBitmap {
    const result = arena.pushStruct(LoadedBitmap);

    result.width = width;
    result.height = height;
    result.pitch = result.width * shared.BITMAP_BYTES_PER_PIXEL;

    const total_bitmap_size: u32 = @intCast(result.width * result.height * shared.BITMAP_BYTES_PER_PIXEL);
    result.memory = @ptrCast(arena.pushSize(@alignOf(u8), total_bitmap_size));

    if (clear_to_zero) {
        clearBitmap(result);
    }

    return result.*;
}

fn debugLoadBMP(
    thread: *shared.ThreadContext,
    platform: shared.Platform,
    file_name: [*:0]const u8,
) LoadedBitmap {
    var result: LoadedBitmap = undefined;
    const read_result = platform.debugReadEntireFile(thread, file_name);

    if (read_result.content_size > 0) {
        const header = @as(*shared.BitmapHeader, @ptrCast(@alignCast(read_result.contents)));

        std.debug.assert(header.compression == 3);

        result.memory = @as([*]void, @ptrCast(read_result.contents)) + header.bitmap_offset;
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

        const red_shift_down = @as(u5, @intCast(red_scan.index));
        const green_shift_down = @as(u5, @intCast(green_scan.index));
        const blue_shift_down = @as(u5, @intCast(blue_scan.index));
        const alpha_shift_down = @as(u5, @intCast(alpha_scan.index));

        var source_dest: [*]align(@alignOf(u8)) u32 = @ptrCast(result.memory);
        var x: u32 = 0;
        while (x < header.width) : (x += 1) {
            var y: u32 = 0;
            while (y < header.height) : (y += 1) {
                const color = source_dest[0];
                var r: f32 = @floatFromInt((color & header.red_mask) >> red_shift_down);
                var g: f32 = @floatFromInt((color & header.green_mask) >> green_shift_down);
                var b: f32 = @floatFromInt((color & header.blue_mask) >> blue_shift_down);
                const a: f32 = @floatFromInt((color & alpha_mask) >> alpha_shift_down);
                const an = (a / 255.0);

                // Pre-multiply alpha.
                r *= an;
                g *= an;
                b *= an;

                source_dest[0] = ((@as(u32, @intFromFloat(a + 0.5)) << 24) |
                    (@as(u32, @intFromFloat(r + 0.5)) << 16) |
                    (@as(u32, @intFromFloat(g + 0.5)) << 8) |
                    (@as(u32, @intFromFloat(b + 0.5)) << 0));

                source_dest += 1;
            }
        }
    }

    result.pitch = -result.width * shared.BITMAP_BYTES_PER_PIXEL;
    const offset: usize = @intCast(-result.pitch * (result.height - 1));
    result.memory = @ptrCast(@as([*]u8, @ptrCast(result.memory)) + offset);

    return result;
}

fn outputSound(sound_buffer: *shared.SoundOutputBuffer, tone_hz: u32, state: *State) void {
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
