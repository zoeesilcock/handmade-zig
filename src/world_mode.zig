const shared = @import("shared.zig");
const math = @import("math.zig");
const world = @import("world.zig");
const sim = @import("sim.zig");
const asset = @import("asset.zig");
const audio = @import("audio.zig");
const rendergroup = @import("rendergroup.zig");
const random = @import("random.zig");
const intrinsics = @import("intrinsics.zig");
const file_formats = @import("file_formats");
const handmade = @import("handmade.zig");
const cutscene = @import("cutscene.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

const PARTICLE_CEL_DIM = 32;
pub const GROUND_BUFFER_WIDTH: u32 = 256;
pub const GROUND_BUFFER_HEIGHT: u32 = 256;

var global_config = &@import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Rectangle2i = math.Rectangle2i;
const Color = math.Color;
const State = shared.State;
const WorldPosition = world.WorldPosition;
const LoadedBitmap = asset.LoadedBitmap;
const PlayingSound = audio.PlayingSound;
const BitmapId = file_formats.BitmapId;
const RenderGroup = rendergroup.RenderGroup;
const ObjectTransform = rendergroup.ObjectTransform;
const TransientState = shared.TransientState;
const DebugInterface = debug_interface.DebugInterface;
const AssetTagId = file_formats.AssetTagId;
const TimedBlock = debug_interface.TimedBlock;
const ArenaPushParams = shared.ArenaPushParams;
const SimEntityTraversablePoint = sim.SimEntityTraversablePoint;
const SimEntityCollisionVolumeGroup = sim.SimEntityCollisionVolumeGroup;

pub const GameModeWorld = struct {
    world: *world.World = undefined,
    typical_floor_height: f32 = 0,

    camera_following_entity_index: u32 = 0,
    camera_position: WorldPosition,

    low_entity_count: u32 = 0,
    low_entities: [90000]LowEntity = [1]LowEntity{undefined} ** 90000,

    collision_rule_hash: [256]?*PairwiseCollisionRule = [1]?*PairwiseCollisionRule{null} ** 256,
    first_free_collision_rule: ?*PairwiseCollisionRule = null,

    null_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    floor_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    wall_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    stair_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
    hero_body_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    hero_head_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    sword_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
    familiar_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
    monster_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,

    time: f32 = 0,

    t_sine: f32 = 0,

    effects_entropy: random.Series,

    next_particle: u32 = 0,
    particles: [256]Particle = [1]Particle{Particle{}} ** 256,
    particle_cels: [PARTICLE_CEL_DIM][PARTICLE_CEL_DIM]ParticleCel = undefined,

    pub fn getLowEntity(self: *GameModeWorld, index: u32) ?*LowEntity {
        var entity: ?*LowEntity = null;

        if (index > 0 and index < self.low_entity_count) {
            entity = &self.low_entities[index];
        }

        return entity;
    }

    pub fn addPlayer(self: *GameModeWorld) AddLowEntityResult {
        const body = addGroundedEntity(self, .HeroBody, self.camera_position, self.hero_body_collision);
        body.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

        const head = addGroundedEntity(self, .HeroHead, self.camera_position, self.hero_head_collision);
        head.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

        initHitPoints(&body.low.sim, 3);

        const sword = addSword(self);
        head.low.sim.sword = sim.EntityReference{ .index = sword.low_index };
        head.low.sim.head = sim.EntityReference{ .index = body.low_index };
        body.low.sim.head = sim.EntityReference{ .index = head.low_index };

        if (self.camera_following_entity_index == 0) {
            self.camera_following_entity_index = body.low_index;
        }

        return head;
    }

    pub fn deleteLowEntity(self: *GameModeWorld, entity_index: u32) void {
        _ = self;
        _ = entity_index;
        // TODO: Implement this.
    }

    pub fn addCollisionRule(self: *GameModeWorld, in_storage_index_a: u32, in_storage_index_b: u32, can_collide: bool) void {
        var storage_index_a = in_storage_index_a;
        var storage_index_b = in_storage_index_b;

        // Sort entities based on storage index.
        if (storage_index_a > storage_index_b) {
            const temp = storage_index_a;
            storage_index_a = storage_index_b;
            storage_index_b = temp;
        }

        // Look for an existing rule in the hash.
        const hash_bucket = storage_index_a & ((self.collision_rule_hash.len) - 1);
        var found_rule: ?*PairwiseCollisionRule = null;
        var opt_rule: ?*PairwiseCollisionRule = self.collision_rule_hash[hash_bucket];
        while (opt_rule) |rule| : (opt_rule = rule.next_in_hash) {
            if (rule.storage_index_a == storage_index_a and rule.storage_index_b == storage_index_b) {
                found_rule = rule;
                break;
            }
        }

        // Create a new rule if it didn't exist.
        if (found_rule == null) {
            found_rule = self.first_free_collision_rule;

            if (found_rule) |rule| {
                self.first_free_collision_rule = rule.next_in_hash;
            } else {
                found_rule = self.world.arena.pushStruct(PairwiseCollisionRule, null);
            }

            found_rule.?.next_in_hash = self.collision_rule_hash[hash_bucket];
            self.collision_rule_hash[hash_bucket] = found_rule.?;
        }

        // Apply the rule settings.
        if (found_rule) |found| {
            found.storage_index_a = storage_index_a;
            found.storage_index_b = storage_index_b;
            found.can_collide = can_collide;
        }
    }
};

pub const LowEntity = struct {
    sim: sim.SimEntity,
    position: WorldPosition = undefined,
};

pub const AddLowEntityResult = struct {
    low: *LowEntity,
    low_index: u32,
};

pub const ParticleCel = struct {
    density: f32 = 0,
    velocity_times_density: Vector3 = Vector3.zero(),
};

pub const Particle = struct {
    position: Vector3 = Vector3.zero(),
    velocity: Vector3 = Vector3.zero(),
    acceleration: Vector3 = Vector3.zero(),
    color: Color = Color.white(),
    color_velocity: Color = Color.zero(),
    bitmap_id: BitmapId = undefined,
};

pub const PairwiseCollisionRuleFlag = enum(u8) {
    CanCollide = 0x1,
    Temporary = 0x2a,
};

pub const PairwiseCollisionRule = extern struct {
    can_collide: bool,
    storage_index_a: u32,
    storage_index_b: u32,

    next_in_hash: ?*PairwiseCollisionRule,
};

pub fn playWorld(state: *State, transient_state: *TransientState) void {
    state.setGameMode(transient_state, .World);

    var world_mode: *GameModeWorld = state.mode_arena.pushStruct(
        GameModeWorld,
        ArenaPushParams.aligned(@alignOf(GameModeWorld), true),
    );
    world_mode.typical_floor_height = 3;

    // TODO: Replace this with a value received from the renderer.
    const pixels_to_meters = 1.0 / 42.0;
    const chunk_dimension_in_meters = Vector3.new(
        pixels_to_meters * @as(f32, @floatFromInt(GROUND_BUFFER_WIDTH)),
        pixels_to_meters * @as(f32, @floatFromInt(GROUND_BUFFER_HEIGHT)),
        world_mode.typical_floor_height,
    );

    world_mode.world = world.createWorld(chunk_dimension_in_meters, &state.mode_arena);

    _ = addLowEntity(world_mode, .Null, WorldPosition.nullPosition());

    const tile_side_in_meters: f32 = 1.4;
    const tiles_per_width: u32 = 17;
    const tiles_per_height: u32 = 9;
    const tile_depth_in_meters = world_mode.typical_floor_height;
    world_mode.null_collision = makeNullCollision(world_mode);
    world_mode.floor_collision = makeSimpleFloorCollision(
        world_mode,
        tile_side_in_meters,
        tile_side_in_meters,
        tile_depth_in_meters,
    );
    world_mode.wall_collision = makeSimpleGroundedCollision(
        world_mode,
        tile_side_in_meters,
        tile_side_in_meters,
        tile_depth_in_meters - 0.1,
        0,
    );
    world_mode.stair_collsion = makeSimpleGroundedCollision(
        world_mode,
        tile_side_in_meters,
        tile_side_in_meters * 2.0,
        tile_depth_in_meters * 1.1,
        0,
    );
    world_mode.hero_body_collision = makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.5, 0);
    world_mode.hero_head_collision = makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.6, 0.7);
    world_mode.sword_collsion = makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.1, 0);
    world_mode.monster_collsion = makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.5, 0);
    world_mode.familiar_collsion = makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.5, 0);

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

    for (0..1) |_| {
        // const door_direction = 3;
        const door_direction = series.randomChoice(if (door_up or door_down) 2 else 4);
        // const door_direction = series.randomChoice(2);

        var created_z_door = false;
        if (door_direction == 3) {
            created_z_door = true;
            door_down = true;
        } else if (door_direction == 2) {
            created_z_door = true;
            door_up = true;
        } else if (door_direction == 1) {
            door_right = true;
        } else {
            door_top = true;
        }

        _ = addStandardRoom(
            world_mode,
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
                    _ = addWall(world_mode, abs_tile_x, abs_tile_y, abs_tile_z);
                } else if (created_z_door) {
                    if ((@mod(abs_tile_z, 2) == 1 and (tile_x == 10 and tile_y == 5)) or
                        ((@mod(abs_tile_z, 2) == 0 and (tile_x == 4 and tile_y == 5))))
                    {
                        _ = addStairs(world_mode, abs_tile_x, abs_tile_y, if (door_down) abs_tile_z - 1 else abs_tile_z);
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

        if (door_direction == 3) {
            abs_tile_z -= 1;
        } else if (door_direction == 2) {
            abs_tile_z += 1;
        } else if (door_direction == 1) {
            screen_x += 1;
        } else {
            screen_y += 1;
        }
    }

    if (false) {
        // Fill the low entity storage with walls.
        while (world_mode.low_entity_count < (world_mode.low_entities.len - 16)) {
            const coordinate: i32 = @intCast(1024 + world_mode.low_entity_count);
            _ = addWall(world_mode, coordinate, coordinate, 0);
        }
    }

    const camera_tile_x = screen_base_x * tiles_per_width + (17 / 2);
    const camera_tile_y = screen_base_y * tiles_per_height + (9 / 2);
    const camera_tile_z = screen_base_z;
    world_mode.camera_position = chunkPositionFromTilePosition(
        world_mode.world,
        camera_tile_x,
        camera_tile_y,
        camera_tile_z,
        null,
    );

    _ = addMonster(world_mode, camera_tile_x - 3, camera_tile_y + 2, camera_tile_z);

    for (0..1) |_| {
        const familiar_offset_x: i32 = series.randomIntBetween(-7, 7);
        const familiar_offset_y: i32 = series.randomIntBetween(-3, -1);

        _ = addFamiliar(world_mode, camera_tile_x + familiar_offset_x, camera_tile_y + familiar_offset_y, camera_tile_z);
    }

    state.mode = .{ .world = world_mode };
}

pub fn updateAndRenderWorld(
    state: *shared.State,
    world_mode: *GameModeWorld,
    transient_state: *TransientState,
    input: *shared.GameInput,
    render_group: *RenderGroup,
    draw_buffer: *asset.LoadedBitmap,
) bool {
    TimedBlock.beginBlock(@src(), .UpdateAndRenderWorld);
    defer TimedBlock.endBlock(@src(), .UpdateAndRenderWorld);

    const result = false;
    var heroes_exist = false;
    var quit_requested = false;

    const width_of_monitor_in_meters = 0.635;
    const meters_to_pixels: f32 = @as(f32, @floatFromInt(draw_buffer.width)) * width_of_monitor_in_meters;
    const focal_length: f32 = 0.6;
    const distance_above_ground: f32 = 9;
    const mouse_position: Vector2 = Vector2.new(input.mouse_x, input.mouse_y);

    render_group.perspectiveMode(
        draw_buffer.width,
        draw_buffer.height,
        meters_to_pixels,
        focal_length,
        distance_above_ground,
    );

    // Clear background.
    render_group.pushClear(Color.new(0.25, 0.25, 0.25, 0));

    const screen_bounds = render_group.getCameraRectangleAtTarget();
    var camera_bounds_in_meters = math.Rectangle3.fromMinMax(
        screen_bounds.min.toVector3(0),
        screen_bounds.max.toVector3(0),
    );
    _ = camera_bounds_in_meters.min.setZ(-3.0 * world_mode.typical_floor_height);
    _ = camera_bounds_in_meters.max.setZ(1.0 * world_mode.typical_floor_height);
    const fade_top_end_z: f32 = 0.75 * world_mode.typical_floor_height;
    const fade_top_start_z: f32 = 0.5 * world_mode.typical_floor_height;
    const fade_bottom_start_z: f32 = -2 * world_mode.typical_floor_height;
    const fade_bottom_end_z: f32 = -2.25 * world_mode.typical_floor_height;

    for (&input.controllers, 0..) |*controller, controller_index| {
        const controlled_hero = &state.controlled_heroes[controller_index];
        controlled_hero.movement_direction = Vector2.zero();
        controlled_hero.vertical_direction = 0;
        controlled_hero.sword_direction = Vector2.zero();

        if (controlled_hero.entity_index == 0) {
            if (controller.back_button.wasPressed()) {
                quit_requested = true;
            } else if (controller.start_button.wasPressed()) {
                controlled_hero.* = shared.ControlledHero{};
                controlled_hero.entity_index = state.mode.world.addPlayer().low_index;
            }
        }

        if (controlled_hero.entity_index != 0) {
            heroes_exist = true;

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

            if (controller.action_up.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(0, 1));
                state.audio_state.changeVolume(state.music, 10, Vector2.one());
            }
            if (controller.action_down.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(0, -1));
                state.audio_state.changeVolume(state.music, 10, Vector2.zero());
            }
            if (controller.action_left.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(-1, 0));
                state.audio_state.changeVolume(state.music, 5, Vector2.new(1, 0));
            }
            if (controller.action_right.ended_down) {
                controlled_hero.sword_direction = controlled_hero.sword_direction.plus(Vector2.new(1, 0));
                state.audio_state.changeVolume(state.music, 5, Vector2.new(0, 1));
            }

            if (controller.back_button.wasPressed()) {
                state.mode.world.deleteLowEntity(controlled_hero.entity_index);
                controlled_hero.entity_index = 0;
            }
        }
    }

    const sim_bounds_expansion = Vector3.new(15, 15, 0);
    const sim_bounds = camera_bounds_in_meters.addRadius(sim_bounds_expansion);
    const sim_memory = transient_state.arena.beginTemporaryMemory();
    const sim_center_position = world_mode.camera_position;
    const screen_sim_region = sim.beginSimulation(
        world_mode,
        &transient_state.arena,
        world_mode.world,
        sim_center_position,
        sim_bounds,
        input.frame_delta_time,
    );

    render_group.pushRectangleOutline(
        ObjectTransform.defaultFlat(),
        screen_bounds.getDimension(),
        Vector3.zero(),
        Color.new(1, 1, 0, 1),
        0.1,
    );
    // render_group.pushRectangleOutline(
    //     ObjectTransform.defaultFlat(),
    //     camera_bounds_in_meters.getDimension().xy(),
    //     Vector3.zero(),
    //     Color.new(1, 1, 1, 1),
    // );
    render_group.pushRectangleOutline(
        ObjectTransform.defaultFlat(),
        sim_bounds.getDimension().xy(),
        Vector3.zero(),
        Color.new(0, 1, 1, 1),
        0.1,
    );
    render_group.pushRectangleOutline(
        ObjectTransform.defaultFlat(),
        screen_sim_region.bounds.getDimension().xy(),
        Vector3.zero(),
        Color.new(1, 0, 1, 1),
        0.1,
    );

    const camera_position = world.subtractPositions(world_mode.world, &world_mode.camera_position, &sim_center_position);

    TimedBlock.beginBlock(@src(), .EntityRender);
    var hot_entity_count: u32 = 0;
    var entity_index: u32 = 0;
    while (entity_index < screen_sim_region.entity_count) : (entity_index += 1) {
        const entity = &screen_sim_region.entities[entity_index];
        entity.x_axis = .new(1, 0);
        entity.y_axis = .new(0, 1);
        const entity_debug_id = debug_interface.DebugId.fromPointer(&world_mode.low_entities[entity.storage_index]);
        if (debug_interface.requested(entity_debug_id)) {
            DebugInterface.debugBeginDataBlock(@src(), "Simulation/Entity");
        }

        if (entity.updatable) {
            const delta_time = input.frame_delta_time;
            const shadow_color = Color.new(1, 1, 1, math.clampf01(1 - 0.5 * entity.position.z()));
            var move_spec = sim.MoveSpec{};
            var acceleration = Vector3.zero();

            const camera_relative_ground_position = entity.getGroundPoint().minus(camera_position);
            render_group.global_alpha = 1;

            if (camera_relative_ground_position.z() > fade_top_start_z) {
                render_group.global_alpha = math.clamp01MapToRange(
                    fade_top_end_z,
                    fade_top_start_z,
                    camera_relative_ground_position.z(),
                );
            } else if (camera_relative_ground_position.z() < fade_bottom_start_z) {
                render_group.global_alpha = math.clamp01MapToRange(
                    fade_bottom_end_z,
                    fade_bottom_start_z,
                    camera_relative_ground_position.z(),
                );
            }

            // Pre-physics entity work.
            switch (entity.type) {
                .HeroHead => {
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
                                .speed = 30,
                                .drag = 8,
                                .unit_max_acceleration = true,
                            };
                            acceleration = controlled_hero.movement_direction.toVector3(0);

                            if (controlled_hero.sword_direction.x() == 0 and controlled_hero.sword_direction.y() == 0) {
                                // Keep existing facing direction when velocity is zero.
                            } else {
                                entity.facing_direction =
                                    intrinsics.atan2(controlled_hero.sword_direction.y(), controlled_hero.sword_direction.x());
                            }

                            var closest_position: Vector3 = entity.position;
                            if (getClosestTraversable(screen_sim_region, entity.position, &closest_position)) {
                                const any_push: bool = acceleration.lengthSquared() < 0.1;
                                const spring_coefficient: f32 = if (any_push) 300 else 50;
                                var acceleration2: Vector3 = Vector3.new(0, 0, 0);
                                for (0..2) |e| {
                                    // if (math.square(acceleration.values[e]) < 0.1) {
                                    if (any_push) {
                                        acceleration2.values[e] =
                                            spring_coefficient * (closest_position.values[e] - entity.position.values[e]) -
                                            30 * entity.velocity.values[e];
                                    }
                                }

                                entity.velocity = entity.velocity.plus(acceleration2.scaledTo(delta_time));
                            }

                            if (false) {
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
                                        world_mode.addCollisionRule(sword.storage_index, entity.storage_index, false);
                                        // _ = world_mode.audio_state.playSound(
                                        //     transient_state.assets.getRandomSound(.Bloop, &world_mode.effects_entropy),
                                        // );
                                    }
                                }
                            }
                            }
                        }
                    }
                },
                .HeroBody => {
                    if (entity.head.ptr) |head| {
                        var closest_position: Vector3 = entity.position;
                        _ = getClosestTraversable(screen_sim_region, head.position, &closest_position);
                        const body_delta: Vector3 = closest_position.minus(entity.position);
                        const body_distance: f32 = body_delta.lengthSquared();

                        entity.facing_direction = head.facing_direction;
                        var bob_acceleration: f32 = 0;

                        entity.velocity = Vector3.zero();

                        const head_delta: Vector3 = head.position.minus(entity.position);
                        const head_distance: f32 = head_delta.length();
                        const max_head_distance: f32 = 0.5;
                        const t_head_distance: f32 = math.clamp01MapToRange(0, max_head_distance, head_distance);

                        switch (entity.movement_mode) {
                            .Planted => {
                                if (body_distance > math.square(0.01)) {
                                    entity.movement_time = 0;
                                    entity.movement_from = entity.position;
                                    entity.movement_to = closest_position;
                                    entity.movement_mode = .Hopping;
                                }

                                bob_acceleration = -20 * t_head_distance;
                            },
                            .Hopping => {
                                const t_jump: f32 = 0.1;
                                const t_thrust: f32 = 0.2;
                                const t_land: f32 = 0.9;

                                if (entity.movement_time < t_thrust) {
                                    bob_acceleration = 30;
                                }

                                if (entity.movement_time < t_land) {
                                    const t: f32 = math.clamp01MapToRange(t_jump, t_land, entity.movement_time);
                                    const a: Vector3 = Vector3.new(0, -2, 0);
                                    const b: Vector3 = entity.movement_to.minus(entity.movement_from).minus(a);
                                    entity.position = a.scaledTo(t * t).plus(b.scaledTo(t)).plus(entity.movement_from);
                                }

                                if (entity.movement_time >= 1) {
                                    entity.movement_mode = .Planted;
                                    entity.position = entity.movement_to;
                                    entity.bob_delta_time = -2;
                                }

                                entity.movement_time += 4 * delta_time;
                                if (entity.movement_time > 1) {
                                    entity.movement_time = 1;
                                }
                            },
                        }

                        const position_coefficient = 100;
                        const velocity_coefficient = 10;
                        bob_acceleration +=
                            position_coefficient * (0 - entity.bob_time) +
                            velocity_coefficient * (0 - entity.bob_delta_time);
                        entity.bob_time +=
                            bob_acceleration * delta_time * delta_time +
                            entity.bob_delta_time * delta_time;
                        entity.bob_delta_time += bob_acceleration * delta_time;

                        entity.y_axis = Vector2.new(0, 1).plus(head_delta.xy().scaledTo(1));
                    }
                },
                .Sword => {
                    move_spec = sim.MoveSpec{
                        .speed = 0,
                        .drag = 0,
                        .unit_max_acceleration = false,
                    };

                    if (entity.distance_limit == 0) {
                        entity.makeNonSpatial();
                        clearCollisionRulesFor(world_mode, entity.storage_index);
                        continue;
                    }
                },
                .Familiar => {
                    var closest_hero: ?*sim.SimEntity = null;
                    var closest_hero_squared: f32 = math.square(10.0);

                    var hero_entity_index: u32 = 0;
                    while (hero_entity_index < screen_sim_region.entity_count) : (hero_entity_index += 1) {
                        var test_entity = &screen_sim_region.entities[hero_entity_index];
                        if (test_entity.type == .HeroBody) {
                            const distance = test_entity.position.minus(entity.position).lengthSquared();

                            if (distance < closest_hero_squared) {
                                closest_hero = test_entity;
                                closest_hero_squared = distance;
                            }
                        }
                    }

                    if (global_config.AI_Familiar_FollowsHero) {
                        if (closest_hero) |hero| {
                            if (closest_hero_squared > math.square(3.0)) {
                                const speed: f32 = 1.0;
                                const one_over_length = speed / @sqrt(closest_hero_squared);
                                acceleration = hero.position.minus(entity.position).scaledTo(one_over_length);
                            }
                        }
                    }

                    move_spec = sim.MoveSpec{
                        .speed = 25,
                        .drag = 8,
                        .unit_max_acceleration = true,
                    };
                },
                .Wall => {},
                .Stairwell => {},
                .Monster => {},
                .Floor => {},
                else => {
                    unreachable;
                },
            }

            if (!entity.isSet(sim.SimEntityFlags.Nonspatial.toInt()) and
                entity.isSet(sim.SimEntityFlags.Movable.toInt()))
            {
                sim.moveEntity(
                    world_mode,
                    screen_sim_region,
                    entity,
                    delta_time,
                    acceleration,
                    &move_spec,
                );
            }

            var entity_transform = ObjectTransform.defaultUpright();
            entity_transform.offset_position = entity.getGroundPoint();

            var match_vector = asset.AssetVector{};
            match_vector.e[AssetTagId.FacingDirection.toInt()] = entity.facing_direction;
            var weight_vector = asset.AssetVector{};
            weight_vector.e[AssetTagId.FacingDirection.toInt()] = 1;

            const hero_bitmaps = shared.HeroBitmapIds{
                .head = transient_state.assets.getBestMatchBitmap(.Head, &match_vector, &weight_vector),
                .cape = transient_state.assets.getBestMatchBitmap(.Cape, &match_vector, &weight_vector),
                .torso = transient_state.assets.getBestMatchBitmap(.Torso, &match_vector, &weight_vector),
            };

            // Post-physics entity work.
            switch (entity.type) {
                .HeroBody => {
                    const hero_scale = 2.5;
                    const color: Color = .white();
                    const x_axis: Vector2 = entity.x_axis;
                    const y_axis: Vector2 = entity.y_axis;
                    render_group.pushBitmapId(
                        entity_transform,
                        transient_state.assets.getFirstBitmap(.Shadow),
                        hero_scale * 1.0,
                        Vector3.zero(),
                        shadow_color,
                        null,
                        null,
                        null,
                    );
                    render_group.pushBitmapId(
                        entity_transform,
                        hero_bitmaps.cape,
                        hero_scale * 1.2,
                        Vector3.new(0, entity.bob_time, 1),
                        color,
                        null,
                        x_axis,
                        y_axis,
                    );
                    render_group.pushBitmapId(
                        entity_transform,
                        hero_bitmaps.torso,
                        hero_scale * 1.2,
                        Vector3.zero(),
                        color,
                        null,
                        x_axis,
                        y_axis,
                    );

                    drawHitPoints(entity, render_group, entity_transform);
                },
                .HeroHead => {
                    const hero_scale = 2.5;
                    render_group.pushBitmapId(
                        entity_transform,
                        hero_bitmaps.head,
                        hero_scale * 1.2,
                        Vector3.zero(),
                        Color.white(),
                        null,
                        null,
                        null,
                    );
                },
                .Sword => {
                    render_group.pushBitmapId(
                        entity_transform,
                        transient_state.assets.getFirstBitmap(.Shadow),
                        0.25,
                        Vector3.zero(),
                        shadow_color,
                        null,
                        null,
                        null,
                    );
                    render_group.pushBitmapId(
                        entity_transform,
                        transient_state.assets.getFirstBitmap(.Sword),
                        0.5,
                        Vector3.zero(),
                        Color.white(),
                        null,
                        null,
                        null,
                    );
                },
                .Wall => {
                    var opt_bitmap_id = transient_state.assets.getFirstBitmap(.Tree);
                    if (opt_bitmap_id) |bitmap_id| {
                        if (debug_interface.requested(entity_debug_id)) {
                            DebugInterface.debugNamedValue(@src(), &opt_bitmap_id.?, "bitmap_id");
                        }
                        render_group.pushBitmapId(
                            entity_transform,
                            bitmap_id,
                            2.5,
                            Vector3.zero(),
                            Color.white(),
                            null,
                        null,
                        null,
                        );
                    }
                },
                .Stairwell => {
                    const stairwell_color1 = Color.new(1, 0.5, 0, 1);
                    const stairwell_color2 = Color.new(1, 1, 0, 1);
                    render_group.pushRectangle(
                        entity_transform,
                        entity.walkable_dimension,
                        Vector3.zero(),
                        stairwell_color1,
                    );
                    render_group.pushRectangle(
                        entity_transform,
                        entity.walkable_dimension,
                        Vector3.new(0, 0, entity.walkable_height),
                        stairwell_color2,
                    );
                },
                .Monster => {
                    render_group.pushBitmapId(
                        entity_transform,
                        transient_state.assets.getFirstBitmap(.Shadow),
                        4.5,
                        Vector3.zero(),
                        shadow_color,
                        null,
                        null,
                        null,
                    );
                    render_group.pushBitmapId(
                        entity_transform,
                        hero_bitmaps.torso,
                        4.5,
                        Vector3.zero(),
                        Color.white(),
                        null,
                        null,
                        null,
                    );

                    drawHitPoints(entity, render_group, entity_transform);
                },
                .Familiar => {
                    // Update head bob.
                    entity.bob_time += delta_time * 2;
                    if (entity.bob_time > shared.TAU32) {
                        entity.bob_time = -shared.TAU32;
                    }

                    const head_bob_sine = @sin(2 * entity.bob_time);
                    const head_z = 0.25 * head_bob_sine;
                    const head_shadow_color = Color.new(1, 1, 1, (0.5 * shadow_color.a()) + (0.2 * head_bob_sine));

                    var bitmap_id = hero_bitmaps.head;
                    if (debug_interface.requested(entity_debug_id)) {
                        DebugInterface.debugNamedValue(@src(), &bitmap_id.?, "bitmap_id");
                    }

                    render_group.pushBitmapId(
                        entity_transform,
                        transient_state.assets.getFirstBitmap(.Shadow),
                        2.5,
                        Vector3.zero(),
                        head_shadow_color,
                        null,
                        null,
                        null,
                    );
                    render_group.pushBitmapId(
                        entity_transform,
                        bitmap_id,
                        2.5,
                        Vector3.new(0, 0, head_z),
                        Color.white(),
                        null,
                        null,
                        null,
                    );
                },
                .Floor => {
                    var volume_index: u32 = 0;
                    while (volume_index < entity.collision.volume_count) : (volume_index += 1) {
                        const volume = entity.collision.volumes[volume_index];
                        render_group.pushRectangleOutline(
                            entity_transform,
                            volume.dimension.xy(),
                            volume.offset_position.minus(Vector3.new(0, 0, 0.5 * volume.dimension.z())),
                            Color.new(0, 0.5, 1, 1),
                            0.1,
                        );
                    }

                    var traversable_index: u32 = 0;
                    while (traversable_index < entity.collision.traversable_count) : (traversable_index += 1) {
                        const traversable = entity.collision.traversables[traversable_index];
                        render_group.pushRectangle(
                            entity_transform,
                            Vector2.new(0.1, 0.1),
                            traversable.position,
                            Color.new(1, 0.5, 0, 1),
                        );
                    }
                },
                else => {
                    unreachable;
                },
            }

            if (debug_interface.DEBUG_UI_ENABLED) {
                var volume_index: u32 = 0;
                while (volume_index < entity.collision.volume_count) : (volume_index += 1) {
                    const volume = entity.collision.volumes[volume_index];
                    const local_mouse_position = render_group.unproject(
                        entity_transform,
                        mouse_position,
                    );

                    if (local_mouse_position.x() > -0.5 * volume.dimension.x() and
                        local_mouse_position.x() < 0.5 * volume.dimension.x() and
                        local_mouse_position.y() > -0.5 * volume.dimension.y() and
                        local_mouse_position.y() < 0.5 * volume.dimension.y())
                    {
                        debug_interface.hit(entity_debug_id, local_mouse_position.z());
                    }

                    var outline_color: Color = undefined;
                    if (debug_interface.highlighted(entity_debug_id, &outline_color)) {
                        render_group.pushRectangleOutline(
                            entity_transform,
                            volume.dimension.xy(),
                            volume.offset_position.minus(Vector3.new(0, 0, 0.5 * volume.dimension.z())),
                            outline_color,
                            0.05,
                        );
                    }
                }
            }
        }

        if (debug_interface.DEBUG_UI_ENABLED) {
            if (debug_interface.requested(entity_debug_id)) {
                DebugInterface.debugStruct(@src(), entity);
                // DebugInterface.debugBeginArray(entity.hit_points);
                // var hit_point_index: u32 = 0;
                // while (hit_point_index < entity.hit_points.len) : (hit_point_index += 1) {
                //     DebugInterface.debugValue(@src(), entity.hit_points[hit_point_index]);
                // }
                // DebugInterface.debugEndArray();
                hot_entity_count += 1;
                DebugInterface.debugEndDataBlock(@src());
            }
        }
    }
    TimedBlock.endBlock(@src(), .EntityRender);

    render_group.global_alpha = 1;

    if (false) {
        const map_colors: [3]Color = .{
            Color.new(1, 0, 0, 1),
            Color.new(0, 1, 0, 1),
            Color.new(0, 0, 1, 1),
        };

        const checker_width = 16;
        const checker_height = 16;
        const checker_dimension = Vector2.new(checker_width, checker_height);
        for (&transient_state.env_maps, 0..) |*map, map_index| {
            const lod: *LoadedBitmap = &map.lod[0];
            const clip_rect: Rectangle2i = Rectangle2i.new(0, 0, lod.width, lod.height);

            var row_checker_on = false;
            var y: u32 = 0;
            while (y < lod.height) : (y += checker_height) {
                var checker_on = row_checker_on;
                var x: u32 = 0;
                while (x < lod.width) : (x += checker_width) {
                    const min_position = Vector2.newU(x, y);
                    const max_position = min_position.plus(checker_dimension);
                    const color = if (checker_on) map_colors[map_index] else Color.new(0, 0, 0, 1);
                    rendergroup.drawRectangle(lod, min_position, max_position, color, clip_rect, true);
                    rendergroup.drawRectangle(lod, min_position, max_position, color, clip_rect, false);
                    checker_on = !checker_on;
                }

                row_checker_on = !row_checker_on;
            }
        }
        transient_state.env_maps[0].z_position = -1.5;
        transient_state.env_maps[1].z_position = 0;
        transient_state.env_maps[2].z_position = 1.5;

        world_mode.time += input.frame_delta_time;
        const angle = 0.1 * world_mode.time;
        // const angle: f32 = 0;

        const screen_center = Vector2.new(
            0.5 * @as(f32, @floatFromInt(draw_buffer.width)),
            0.5 * @as(f32, @floatFromInt(draw_buffer.height)),
        );
        const origin = screen_center;
        const scale = 100.0;

        var x_axis = Vector2.zero();
        var y_axis = Vector2.zero();

        // const displacement = Vector2.zero();
        const displacement = Vector2.new(
            100.0 * intrinsics.cos(5.0 * angle),
            100.0 * intrinsics.sin(3.0 * angle),
        );

        if (true) {
            x_axis = Vector2.new(intrinsics.cos(10 * angle), intrinsics.sin(10 * angle)).scaledTo(scale);
            y_axis = x_axis.perp();
        } else if (false) {
            x_axis = Vector2.new(intrinsics.cos(angle), intrinsics.sin(angle)).scaledTo(scale);
            y_axis = Vector2.new(intrinsics.cos(angle + 1.0), intrinsics.sin(angle + 1.0)).scaledTo(50.0 + 50.0 * intrinsics.cos(angle));
        } else {
            x_axis = Vector2.new(scale, 0);
            y_axis = Vector2.new(0, scale);
        }

        const color = Color.new(1, 1, 1, 1);
        // const color_angle = 5.0 * angle;
        // const color =
        //     Color.new(
        //     0.5 + 0.5 * intrinsics.sin(color_angle),
        //     0.5 + 0.5 * intrinsics.sin(2.9 * color_angle),
        //     0.5 + 0.5 * intrinsics.sin(9.9 * color_angle),
        //     0.5 + 0.5 * intrinsics.sin(10 * color_angle),
        // );

        _ = render_group.pushCoordinateSystem(
            origin.minus(x_axis.scaledTo(0.5)).minus(y_axis.scaledTo(0.5)).plus(displacement),
            x_axis,
            y_axis,
            color,
            &world_mode.test_diffuse,
            &world_mode.test_normal,
            &transient_state.env_maps[2],
            &transient_state.env_maps[1],
            &transient_state.env_maps[0],
        );

        var map_position = Vector2.zero();
        for (&transient_state.env_maps) |*map| {
            const lod: *LoadedBitmap = &map.lod[0];

            x_axis = Vector2.newI(lod.width, 0).scaledTo(0.5);
            y_axis = Vector2.newI(0, lod.height).scaledTo(0.5);

            _ = render_group.pushCoordinateSystem(
                map_position,
                x_axis,
                y_axis,
                Color.new(1, 1, 1, 1),
                lod,
                null,
                undefined,
                undefined,
                undefined,
            );

            map_position = map_position.plus(y_axis.plus(Vector2.new(0, 6)));
        }

        if (false) {
            render_group.pushSaturation(0.5 + 0.5 * intrinsics.sin(10.0 * world_mode.time));
        }
    }

    render_group.orthographicMode(draw_buffer.width, draw_buffer.height, 1);
    render_group.pushRectangleOutline(
        ObjectTransform.defaultFlat(),
        Vector2.new(5, 5),
        mouse_position.toVector3(0),
        Color.new(1, 1, 1, 1),
        0.2,
    );

    // render_group.renderToOutput(transient_state.high_priority_queue, draw_buffer);
    //
    // render_group.endRender();

    sim.endSimulation(world_mode, screen_sim_region);
    transient_state.arena.endTemporaryMemory(sim_memory);

    if (!heroes_exist) {
        cutscene.playTitleScreen(state, transient_state);
    }

    return result;
}

fn addLowEntity(world_mode: *GameModeWorld, entity_type: sim.EntityType, world_position: WorldPosition) AddLowEntityResult {
    std.debug.assert(world_mode.low_entity_count < world_mode.low_entities.len);

    const low_entity_index = world_mode.low_entity_count;
    world_mode.low_entity_count += 1;

    var low_entity = &world_mode.low_entities[low_entity_index];
    low_entity.sim.collision = world_mode.null_collision;
    low_entity.sim.type = entity_type;

    low_entity.position = WorldPosition.nullPosition();
    world.changeEntityLocation(
        &world_mode.world.arena,
        world_mode.world,
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
    world_mode: *GameModeWorld,
    entity_type: sim.EntityType,
    world_position: WorldPosition,
    collision: *sim.SimEntityCollisionVolumeGroup,
) AddLowEntityResult {
    const entity = addLowEntity(world_mode, entity_type, world_position);
    entity.low.sim.collision = collision;
    return entity;
}

fn addStandardRoom(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) void {
    var offset_x: i32 = -8;
    while (offset_x <= 8) : (offset_x += 1) {
        var offset_y: i32 = -4;
        while (offset_y <= 4) : (offset_y += 1) {
            const world_position = chunkPositionFromTilePosition(
                world_mode.world,
                abs_tile_x + offset_x,
                abs_tile_y + offset_y,
                abs_tile_z,
                null,
            );
            _ = addGroundedEntity(world_mode, .Floor, world_position, world_mode.floor_collision);
        }
    }
}

fn addWall(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(world_mode, .Wall, world_position, world_mode.wall_collision);

    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt());

    return entity;
}

fn addStairs(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(world_mode, .Stairwell, world_position, world_mode.stair_collsion);

    entity.low.sim.walkable_dimension = entity.low.sim.collision.total_volume.dimension.xy();
    entity.low.sim.walkable_height = world_mode.typical_floor_height;
    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt());

    return entity;
}

fn addSword(world_mode: *GameModeWorld) AddLowEntityResult {
    const entity = addLowEntity(world_mode, .Sword, WorldPosition.nullPosition());

    entity.low.sim.collision = world_mode.sword_collsion;
    entity.low.sim.addFlags(sim.SimEntityFlags.Movable.toInt());

    return entity;
}

fn addMonster(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(world_mode, .Monster, world_position, world_mode.monster_collsion);

    entity.low.sim.collision = world_mode.monster_collsion;
    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

    initHitPoints(&entity.low.sim, 3);

    return entity;
}

fn addFamiliar(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const world_position = chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = addGroundedEntity(world_mode, .Familiar, world_position, world_mode.familiar_collsion);

    entity.low.sim.addFlags(sim.SimEntityFlags.Collides.toInt() | sim.SimEntityFlags.Movable.toInt());

    return entity;
}

pub fn clearCollisionRulesFor(world_mode: *GameModeWorld, storage_index: u32) void {
    var hash_bucket: u32 = 0;
    while (hash_bucket < world_mode.collision_rule_hash.len) : (hash_bucket += 1) {
        var opt_rule = &world_mode.collision_rule_hash[hash_bucket];
        while (opt_rule.*) |rule| {
            if (rule.storage_index_a == storage_index or rule.storage_index_b == storage_index) {
                const removed_rule = rule;

                opt_rule.* = rule.next_in_hash;

                removed_rule.next_in_hash = world_mode.first_free_collision_rule;
                world_mode.first_free_collision_rule = removed_rule;
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

fn drawHitPoints(entity: *sim.SimEntity, render_group: *RenderGroup, object_transform: ObjectTransform) void {
    if (entity.hit_point_max >= 1) {
        const hit_point_dimension = Vector2.new(0.2, 0.2);
        const hit_point_spacing_x = hit_point_dimension.x() * 2;

        var hit_position =
            Vector2.new(-0.5 * @as(f32, @floatFromInt(entity.hit_point_max - 1)) * hit_point_spacing_x, -0.25);
        const hit_position_delta = Vector2.new(hit_point_spacing_x, 0);
        for (0..@intCast(entity.hit_point_max)) |hit_point_index| {
            const hit_point = entity.hit_points[hit_point_index];
            var hit_point_color = Color.new(1, 0, 0, 1);

            if (hit_point.filled_amount == 0) {
                hit_point_color = Color.new(0.2, 0.2, 0.2, 1);
            }

            render_group.pushRectangle(
                object_transform,
                hit_point_dimension,
                hit_position.toVector3(0),
                hit_point_color,
            );
            hit_position = hit_position.plus(hit_position_delta);
        }
    }
}
fn makeSimpleGroundedCollision(
    world_mode: *GameModeWorld,
    x_dimension: f32,
    y_dimension: f32,
    z_dimension: f32,
    opt_z_offset: ?f32,
) *sim.SimEntityCollisionVolumeGroup {
    const z_offset: f32 = opt_z_offset orelse 0;
    const group = world_mode.world.arena.pushStruct(sim.SimEntityCollisionVolumeGroup, null);

    group.volume_count = 1;
    group.volumes = world_mode.world.arena.pushArray(group.volume_count, sim.SimEntityCollisionVolume, null);
    group.total_volume.offset_position = Vector3.new(0, 0, 0.5 * z_dimension + z_offset);
    group.total_volume.dimension = Vector3.new(x_dimension, y_dimension, z_dimension);
    group.volumes[0] = group.total_volume;

    return group;
}

fn makeSimpleFloorCollision(
    world_mode: *GameModeWorld,
    x_dimension: f32,
    y_dimension: f32,
    z_dimension: f32,
) *sim.SimEntityCollisionVolumeGroup {
    const group = world_mode.world.arena.pushStruct(sim.SimEntityCollisionVolumeGroup, null);

    group.volume_count = 0;
    group.traversable_count = 1;
    group.traversables = world_mode.world.arena.pushArray(group.traversable_count, sim.SimEntityTraversablePoint, null);
    group.traversables[0].position = Vector3.zero();
    group.total_volume.offset_position = Vector3.new(0, 0, 0);
    group.total_volume.dimension = Vector3.new(x_dimension, y_dimension, z_dimension);

    if (false) {
        group.volume_count = 1;
        group.volumes = world_mode.world.arena.pushArray(group.volume_count, sim.SimEntityCollisionVolume, null);
        group.total_volume.offset_position = Vector3.new(0, 0, 0.5 * z_dimension);
        group.total_volume.dimension = Vector3.new(x_dimension, y_dimension, z_dimension);
        group.volumes[0] = group.total_volume;
    }

    return group;
}

fn makeNullCollision(world_mode: *GameModeWorld) *sim.SimEntityCollisionVolumeGroup {
    const group = world_mode.world.arena.pushStruct(sim.SimEntityCollisionVolumeGroup, null);

    group.volume_count = 0;
    group.volumes = undefined;
    group.total_volume.offset_position = Vector3.zero();
    group.total_volume.dimension = Vector3.zero();

    return group;
}


fn getClosestTraversable(sim_region: *sim.SimRegion, from_position: Vector3, result: *Vector3) bool {
    var found: bool = false;
    var closest_distance_squared: f32 = math.square(1000);
    var hero_entity_index: u32 = 0;
    while (hero_entity_index < sim_region.entity_count) : (hero_entity_index += 1) {
        const test_entity = &sim_region.entities[hero_entity_index];
        const volume_group: *sim.SimEntityCollisionVolumeGroup = test_entity.collision;
        var point_index: u32 = 0;
        while (point_index < volume_group.traversable_count) : (point_index += 1) {
            const point: SimEntityTraversablePoint = test_entity.getTraversable(point_index);
            const head_to_point: Vector3 = point.position.minus(from_position);

            const test_distance_squared = head_to_point.lengthSquared();
            if (closest_distance_squared > test_distance_squared) {
                result.* = point.position;
                closest_distance_squared = test_distance_squared;
                found = true;
            }
        }
    }

    return found;
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

fn particleTest(
    world_mode: *GameModeWorld,
    input: *shared.GameInput,
    transient_state: *TransientState,
    render_group: *RenderGroup,
    entity_transform: ObjectTransform,
) void {
    if (global_config.Particles_Test) {
        // Particle system test.
        var particle_spawn_index: u32 = 0;
        while (particle_spawn_index < 3) : (particle_spawn_index += 1) {
            const particle: *Particle = &world_mode.particles[world_mode.next_particle];

            world_mode.next_particle += 1;
            if (world_mode.next_particle >= world_mode.particles.len) {
                world_mode.next_particle = 0;
            }

            particle.position = Vector3.new(
                world_mode.effects_entropy.randomFloatBetween(-0.05, 0.05),
                0,
                0,
            );
            particle.velocity = Vector3.new(
                world_mode.effects_entropy.randomFloatBetween(-0.01, 0.01),
                7 * world_mode.effects_entropy.randomFloatBetween(0.7, 1),
                0,
            );
            particle.acceleration = Vector3.new(0, -9.8, 0);
            particle.color = Color.new(
                world_mode.effects_entropy.randomFloatBetween(0.75, 1),
                world_mode.effects_entropy.randomFloatBetween(0.75, 1),
                world_mode.effects_entropy.randomFloatBetween(0.75, 1),
                1,
            );
            particle.color_velocity = Color.new(0, 0, 0, -0.5);

            const nothings = "NOTHINGS";
            var particle_match_vector = asset.AssetVector{};
            var particle_weight_vector = asset.AssetVector{};
            particle_match_vector.e[@intFromEnum(AssetTagId.UnicodeCodepoint)] =
                @floatFromInt(nothings[world_mode.effects_entropy.randomChoice(nothings.len)]);
            particle_weight_vector.e[@intFromEnum(AssetTagId.UnicodeCodepoint)] = 1;
            particle.bitmap_id = transient_state.assets.getBestMatchBitmap(
                .Font,
                &particle_match_vector,
                &particle_weight_vector,
            ).?;

            particle.bitmap_id = transient_state.assets.getRandomBitmap(
                .Head,
                &world_mode.effects_entropy,
            ).?;
        }

        const grid_scale: f32 = 0.25;
        const inv_grid_scale: f32 = 1 / grid_scale;
        const grid_origin = Vector3.new(-0.5 * grid_scale * PARTICLE_CEL_DIM, 0, 0);

        {
            // Zero the paricle cels.
            {
                var y: u32 = 0;
                while (y < PARTICLE_CEL_DIM) : (y += 1) {
                    var x: u32 = 0;
                    while (x < PARTICLE_CEL_DIM) : (x += 1) {
                        world_mode.particle_cels[y][x] = ParticleCel{};
                    }
                }
            }

            var particle_index: u32 = 0;
            while (particle_index < world_mode.particles.len) : (particle_index += 1) {
                const particle: *Particle = &world_mode.particles[particle_index];
                const position = particle.position.minus(grid_origin).scaledTo(inv_grid_scale);
                const ix: i32 = intrinsics.floorReal32ToInt32(position.x());
                const iy: i32 = intrinsics.floorReal32ToInt32(position.y());
                var x: u32 = if (ix > 0) 0 +% @as(u32, @intCast(ix)) else 0 -% @abs(ix);
                var y: u32 = if (iy > 0) 0 +% @as(u32, @intCast(iy)) else 0 -% @abs(iy);

                if (x < 0) {
                    x = 0;
                }
                if (x > (PARTICLE_CEL_DIM - 1)) {
                    x = (PARTICLE_CEL_DIM - 1);
                }
                if (y < 0) {
                    y = 0;
                }
                if (y > (PARTICLE_CEL_DIM - 1)) {
                    y = (PARTICLE_CEL_DIM - 1);
                }

                const cel = &world_mode.particle_cels[y][x];
                const density: f32 = particle.color.a();
                cel.density += density;
                cel.velocity_times_density =
                    cel.velocity_times_density.plus(particle.velocity.scaledTo(density));
            }
        }

        if (global_config.Particles_ShowGrid) {
            var y: u32 = 0;
            while (y < PARTICLE_CEL_DIM) : (y += 1) {
                var x: u32 = 0;
                while (x < PARTICLE_CEL_DIM) : (x += 1) {
                    const cel = &world_mode.particle_cels[y][x];
                    const alpha: f32 = math.clampf01(0.1 * cel.density);
                    render_group.pushRectangle(
                        entity_transform,
                        Vector2.one().scaledTo(grid_scale),
                        Vector3.new(
                            @floatFromInt(x),
                            @floatFromInt(y),
                            0,
                        ).scaledTo(grid_scale).plus(grid_origin),
                        Color.new(alpha, alpha, alpha, 0),
                    );
                }
            }
        }

        var particle_index: u32 = 0;
        while (particle_index < world_mode.particles.len) : (particle_index += 1) {
            const particle: *Particle = &world_mode.particles[particle_index];
            const position = particle.position.minus(grid_origin).scaledTo(inv_grid_scale);
            const ix: i32 = intrinsics.floorReal32ToInt32(position.x());
            const iy: i32 = intrinsics.floorReal32ToInt32(position.y());
            var x: u32 = if (ix > 0) 0 +% @as(u32, @intCast(ix)) else 0 -% @abs(ix);
            var y: u32 = if (iy > 0) 0 +% @as(u32, @intCast(iy)) else 0 -% @abs(iy);

            if (x < 1) {
                x = 1;
            }
            if (x > (PARTICLE_CEL_DIM - 2)) {
                x = (PARTICLE_CEL_DIM - 2);
            }
            if (y < 1) {
                y = 1;
            }
            if (y > (PARTICLE_CEL_DIM - 2)) {
                y = (PARTICLE_CEL_DIM - 2);
            }

            const cel_center = &world_mode.particle_cels[y][x];
            const cel_left = &world_mode.particle_cels[y][x - 1];
            const cel_right = &world_mode.particle_cels[y][x + 1];
            const cel_down = &world_mode.particle_cels[y - 1][x];
            const cel_up = &world_mode.particle_cels[y + 1][x];

            var dispersion = Vector3.zero();
            const dispersion_coefficient: f32 = 1;
            dispersion = dispersion.plus(Vector3.new(-1, 0, 0)
                .scaledTo(dispersion_coefficient * (cel_center.density - cel_left.density)));
            dispersion = dispersion.plus(Vector3.new(1, 0, 0)
                .scaledTo(dispersion_coefficient * (cel_center.density - cel_right.density)));
            dispersion = dispersion.plus(Vector3.new(0, -1, 0)
                .scaledTo(dispersion_coefficient * (cel_center.density - cel_down.density)));
            dispersion = dispersion.plus(Vector3.new(0, 1, 0)
                .scaledTo(dispersion_coefficient * (cel_center.density - cel_up.density)));

            // Simulate particle.
            const particle_acceleration = particle.acceleration.plus(dispersion);
            particle.position = particle.position.plus(
                particle_acceleration.scaledTo(0.5 * math.square(input.frame_delta_time) * input.frame_delta_time),
            ).plus(
                particle.velocity.scaledTo(input.frame_delta_time),
            );
            particle.velocity = particle.velocity.plus(particle_acceleration.scaledTo(input.frame_delta_time));
            particle.color = particle.color.plus(particle.color_velocity.scaledTo(input.frame_delta_time));

            if (particle.position.y() < 0) {
                const coefficient_of_restitution = 0.3;
                const coefficient_of_friction = 0.7;
                _ = particle.position.setY(-particle.position.y());
                _ = particle.velocity.setY(-coefficient_of_restitution * particle.velocity.y());
                _ = particle.velocity.setX(coefficient_of_friction * particle.velocity.x());
            }

            var color = particle.color.clamp01();
            if (particle.color.a() > 0.9) {
                _ = color.setA(0.9 * math.clamp01MapToRange(1, 0.9, color.a()));
            }

            // Render particle.
            render_group.pushBitmapId(
                entity_transform,
                particle.bitmap_id,
                1,
                particle.position,
                color,
                null,
                null,
                null,
            );
        }
    }
}
