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
///     * Logging.
///     * Diagramming.
///     * Switches, sliders etc.
///     * Draw tile chunks so we can verify things are aligned / in the chunks we want them to be in etc.
///
/// * Audio.
///     * Sound effect triggers.
///     * Ambient sounds.
///     * Music.
/// * Asset streaming.
///
/// * Metagame/save game?
///     * How do you enter a save slot? Multiple profiles and potential "menu world".
///     * Persistent unlocks, etc.
///     * De we allo save games? Probably yes, just for "pausing".
///     * Continuous save for crash recovery?
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
const Color = math.Color;
const State = shared.State;
const WorldPosition = world.WorldPosition;
const AddLowEntityResult = shared.AddLowEntityResult;

pub export fn updateAndRender(
    thread: *shared.ThreadContext,
    platform: shared.Platform,
    memory: *shared.Memory,
    input: shared.GameInput,
    buffer: *shared.OffscreenBuffer,
) void {
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
        };

        shared.initializeArena(
            &state.world_arena,
            memory.permanent_storage_size - @sizeOf(State),
            memory.permanent_storage.? + @sizeOf(State),
        );

        _ = addLowEntity(state, .Null, WorldPosition.nullPosition());

        state.world = shared.pushStruct(&state.world_arena, world.World);
        world.initializeWorld(state.world, 1.4, 3.0);

        const tile_side_in_pixels = 60;
        state.meters_to_pixels = @as(f32, @floatFromInt(tile_side_in_pixels)) / state.world.tile_side_in_meters;

        const tiles_per_width: u32 = 17;
        const tiles_per_height: u32 = 9;

        state.null_collision = makeNullCollision(state);
        state.wall_collision = makeSimpleGroundedCollision(
            state,
            state.world.tile_side_in_meters,
            state.world.tile_side_in_meters,
            state.world.tile_depth_in_meters,
        );
        state.stair_collsion = makeSimpleGroundedCollision(
            state,
            state.world.tile_side_in_meters,
            state.world.tile_side_in_meters * 2.0,
            state.world.tile_depth_in_meters * 1.1,
        );
        state.player_collsion = makeSimpleGroundedCollision(state, 0.5, 1, 1.2);
        state.sword_collsion = makeSimpleGroundedCollision(state, 1, 0.5, 0.1);
        state.monster_collsion = makeSimpleGroundedCollision(state, 1, 1, 0.5);
        state.familiar_collsion = makeSimpleGroundedCollision(state, 1, 0.5, 0.5);

        var random_number_index: u32 = 3;
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

                if (abs_tile_z == screen_base_z) {
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

            if (random_choice == 2) {
                if (abs_tile_z == screen_base_z) {
                    abs_tile_z = screen_base_z + 1;
                } else {
                    abs_tile_z = screen_base_z;
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
        state.camera_position = world.chunkPositionFromTilePosition(
            state.world,
            camera_tile_x,
            camera_tile_y,
            camera_tile_z,
            null,
        );

        _ = addMonster(state, camera_tile_x - 3, camera_tile_y + 2, camera_tile_z);

        for (0..1) |_| {
            const familiar_offset_x: i32 = @mod(@as(i32, @intCast(random.RANDOM_NUMBERS[random_number_index])), 10) - 7;
            random_number_index += 1;
            const familiar_offset_y: i32 = @mod(@as(i32, @intCast(random.RANDOM_NUMBERS[random_number_index])), 6) - 3;
            random_number_index += 1;

            _ = addFamiliar(state, camera_tile_x + familiar_offset_x, camera_tile_y + familiar_offset_y, camera_tile_z);
        }

        memory.is_initialized = true;
    }

    const meters_to_pixels = state.meters_to_pixels;

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

    // Calculate the camera bounds.
    const tile_span_x = 17 * 3;
    const tile_span_y = 9 * 3;
    const tile_span_z = 1;
    const bounds_in_tiles = Vector3.new(tile_span_x, tile_span_y, tile_span_z);
    const camera_bounds = math.Rectangle3.fromCenterDimension(
        Vector3.zero(),
        bounds_in_tiles.scaledTo(state.world.tile_side_in_meters),
    );

    var sim_arena: shared.MemoryArena = undefined;
    shared.initializeArena(&sim_arena, memory.transient_storage_size, memory.transient_storage.?);
    const screen_sim_region = sim.beginSimulation(
        state,
        &sim_arena,
        state.world,
        state.camera_position,
        camera_bounds,
        input.frame_delta_time,
    );

    // Clear background.
    const clear_color = Color.new(0.5, 0.5, 0.5, 1);
    drawRectangle(
        buffer,
        Vector2.zero(),
        Vector2.new(@floatFromInt(buffer.width), @floatFromInt(buffer.height)),
        clear_color,
    );
    // drawBitmap(buffer, state.backdrop, 0, 0, 0, 0, 1);

    const screen_center_x: f32 = 0.5 * @as(f32, @floatFromInt(buffer.width));
    const screen_center_y: f32 = 0.5 * @as(f32, @floatFromInt(buffer.height));

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
                const entity_ground_point_x = screen_center_x + meters_to_pixels * z_fudge * entity_base_position.x();
                const entity_ground_point_y = screen_center_y - meters_to_pixels * z_fudge * entity_base_position.y();
                const entity_z = -meters_to_pixels * entity_base_position.z();

                const center = Vector2.new(
                    piece.offset.x() + entity_ground_point_x,
                    piece.offset.y() + entity_ground_point_y + (entity_z * piece.entity_z_amount),
                );

                if (piece.bitmap) |bitmap| {
                    drawBitmap(buffer, bitmap, center.x(), center.y(), piece.color.a());
                } else {
                    const dimension = piece.dimension.scaledTo(meters_to_pixels);
                    drawRectangle(
                        buffer,
                        center.minus(dimension.scaledTo(0.5)),
                        center.plus(dimension.scaledTo(0.5)),
                        piece.color,
                    );
                }
            }
        }
    }

    sim.endSimulation(state, screen_sim_region);
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

fn addWall(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = world.chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Wall, world_position, state.wall_collision);

    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt());

    return entity;
}

fn addStairs(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = world.chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Stairwell, world_position, state.stair_collsion);

    entity.low.sim.walkable_dimension = entity.low.sim.collision.total_volume.dimension.xy();
    entity.low.sim.walkable_height = state.world.tile_depth_in_meters;
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
    const world_position = world.chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(state, .Monster, world_position, state.monster_collsion);

    entity.low.sim.collision = state.monster_collsion;
    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

    initHitPoints(&entity.low.sim, 3);

    return entity;
}

fn addFamiliar(state: *State, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = world.chunkPositionFromTilePosition(state.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
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
    const group = shared.pushStruct(&state.world_arena, sim.SimEntityCollisionVolumeGroup);

    group.volume_count = 1;
    group.volumes = shared.pushArray(&state.world_arena, group.volume_count, sim.SimEntityCollisionVolume);
    group.total_volume.offset_position = Vector3.new(0, 0, 0.5 * z_dimension);
    group.total_volume.dimension = Vector3.new(x_dimension, y_dimension, z_dimension);
    group.volumes[0] = group.total_volume;

    return group;
}

fn makeNullCollision(state: *State) *sim.SimEntityCollisionVolumeGroup {
    const group = shared.pushStruct(&state.world_arena, sim.SimEntityCollisionVolumeGroup);

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
            found_rule = shared.pushStruct(&state.world_arena, shared.PairwiseCollisionRule);
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

fn drawRectangle(
    buffer: *shared.OffscreenBuffer,
    vector_min: Vector2,
    vector_max: Vector2,
    color: Color,
) void {
    // Round input values.
    var min_x = intrinsics.roundReal32ToInt32(vector_min.x());
    var min_y = intrinsics.roundReal32ToInt32(vector_min.y());
    var max_x = intrinsics.roundReal32ToInt32(vector_max.x());
    var max_y = intrinsics.roundReal32ToInt32(vector_max.y());

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
            pixel[0] = shared.colorToInt(color);
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
    in_alpha: f32,
) void {
    // TODO: Should we really clamp here?
    const alpha = math.clampf01(in_alpha);

    // The pixel color calculation below doesn't handle sizes outside the range of 0 - 1.
    std.debug.assert(alpha >= 0 and alpha <= 1);

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
