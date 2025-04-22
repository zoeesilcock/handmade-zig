const shared = @import("shared.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const world = @import("world.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
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
const ControlledHero = shared.ControlledHero;
const WorldPosition = world.WorldPosition;
const LoadedBitmap = asset.LoadedBitmap;
const PlayingSound = audio.PlayingSound;
const BitmapId = file_formats.BitmapId;
const RenderGroup = rendergroup.RenderGroup;
const ObjectTransform = rendergroup.ObjectTransform;
const TransientClipRect = rendergroup.TransientClipRect;
const TransientState = shared.TransientState;
const DebugInterface = debug_interface.DebugInterface;
const AssetTagId = file_formats.AssetTagId;
const TimedBlock = debug_interface.TimedBlock;
const ArenaPushParams = memory.ArenaPushParams;
const Entity = entities.Entity;
const EntityId = entities.EntityId;
const EntityType = entities.EntityType;
const EntityReference = entities.EntityReference;
const TraversableReference = entities.TraversableReference;
const EntityFlags = entities.EntityFlags;
const EntityCollisionVolume = entities.EntityCollisionVolume;
const EntityCollisionVolumeGroup = entities.EntityCollisionVolumeGroup;
const EntityTraversablePoint = entities.EntityTraversablePoint;
const EntityVisiblePiece = entities.EntityVisiblePiece;
const EntityVisiblePieceFlag = entities.EntityVisiblePieceFlag;
const Brain = brains.Brain;
const BrainId = brains.BrainId;
const BrainSlot = brains.BrainSlot;
const BrainHero = brains.BrainHero;
const BrainSnake = brains.BrainSnake;
const BrainMonster = brains.BrainMonster;
const BrainFamiliar = brains.BrainFamiliar;
const ReservedBrainId = brains.ReservedBrainId;

pub const GameModeWorld = struct {
    world: *world.World = undefined,
    typical_floor_height: f32 = 0,

    camera_following_entity_index: EntityId = .{},
    camera_position: WorldPosition,
    camera_offset: Vector3,

    collision_rule_hash: [256]?*PairwiseCollisionRule = [1]?*PairwiseCollisionRule{null} ** 256,
    first_free_collision_rule: ?*PairwiseCollisionRule = null,

    null_collision: *EntityCollisionVolumeGroup = undefined,
    floor_collision: *EntityCollisionVolumeGroup = undefined,
    wall_collision: *EntityCollisionVolumeGroup = undefined,
    stair_collsion: *EntityCollisionVolumeGroup = undefined,
    hero_body_collision: *EntityCollisionVolumeGroup = undefined,
    hero_head_collision: *EntityCollisionVolumeGroup = undefined,
    hero_glove_collision: *EntityCollisionVolumeGroup = undefined,
    familiar_collsion: *EntityCollisionVolumeGroup = undefined,
    monster_collsion: *EntityCollisionVolumeGroup = undefined,

    time: f32 = 0,

    t_sine: f32 = 0,

    game_entropy: random.Series,
    effects_entropy: random.Series,

    next_particle: u32 = 0,
    particles: [256]Particle = [1]Particle{Particle{}} ** 256,
    particle_cels: [PARTICLE_CEL_DIM][PARTICLE_CEL_DIM]ParticleCel = undefined,

    creation_buffer_index: u32,
    creation_buffer: [4]Entity,
    last_used_entity_storage_index: u32,
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
    id_a: u32,
    id_b: u32,

    next_in_hash: ?*PairwiseCollisionRule,
};

pub fn playWorld(state: *State, transient_state: *TransientState) void {
    state.setGameMode(transient_state, .World);

    var world_mode: *GameModeWorld = state.mode_arena.pushStruct(
        GameModeWorld,
        ArenaPushParams.aligned(@alignOf(GameModeWorld), true),
    );
    world_mode.last_used_entity_storage_index = @intFromEnum(ReservedBrainId.FirstFree);
    world_mode.game_entropy = .seed(3);
    world_mode.effects_entropy = .seed(3);
    world_mode.typical_floor_height = 3;

    // TODO: Replace this with a value received from the renderer.
    const pixels_to_meters = 1.0 / 42.0;
    const chunk_dimension_in_meters = Vector3.new(
        pixels_to_meters * @as(f32, @floatFromInt(GROUND_BUFFER_WIDTH)),
        pixels_to_meters * @as(f32, @floatFromInt(GROUND_BUFFER_HEIGHT)),
        world_mode.typical_floor_height,
    );

    world_mode.world = world.createWorld(chunk_dimension_in_meters, &state.mode_arena);

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
    world_mode.hero_body_collision = makeNullCollision(world_mode); //makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.5, 0);
    world_mode.hero_head_collision = makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.6, 0.7);
    world_mode.hero_glove_collision = makeNullCollision(world_mode); //makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.6, 0.7);
    world_mode.monster_collsion = makeNullCollision(world_mode); //makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.5, 0);
    world_mode.familiar_collsion = makeNullCollision(world_mode); //makeSimpleGroundedCollision(world_mode, 1, 0.5, 0.5, 0);

    var series = world_mode.game_entropy;
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
        const door_direction = 2;
        _ = series.randomChoice(2);
        // const door_direction = 3;
        // const door_direction = series.randomChoice(if (door_up or door_down) 2 else 4);
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

        const room: StandardRoom = addStandardRoom(
            world_mode,
            screen_x * tiles_per_width + (tiles_per_width / 2),
            screen_y * tiles_per_height + (tiles_per_height / 2),
            abs_tile_z,
        );

        if (true) {
            _ = addMonster(world_mode, room.position[3][6], room.ground[3][6]);
            _ = addFamiliar(world_mode, room.position[4][3], room.ground[4][3]);

            const snake_brain_id = addBrain(world_mode);
            var segment_index: u32 = 0;
            while (segment_index < 5) : (segment_index += 1) {
                const x: u32 = 2 + segment_index;
                _ = addSnakeSegment(world_mode, room.position[x][2], room.ground[x][2], snake_brain_id, segment_index);
            }
        }

        for (0..room.position[0].len) |tile_y| {
            for (0..room.position.len) |tile_x| {
                const position: WorldPosition = room.position[tile_x][tile_y];
                const ground: TraversableReference = room.ground[tile_x][tile_y];

                var should_be_door = true;
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
                    _ = addWall(world_mode, position, ground);
                } else if (created_z_door) {
                    // if ((@mod(abs_tile_z, 2) == 1 and (tile_x == 10 and tile_y == 5)) or
                    //     ((@mod(abs_tile_z, 2) == 0 and (tile_x == 4 and tile_y == 5))))
                    // {
                    //     _ = addStairs(world_mode, abs_tile_x, abs_tile_y, if (door_down) abs_tile_z - 1 else abs_tile_z);
                    // }
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
        while (world_mode.entity_count < (world_mode.low_entities.len - 16)) {
            const coordinate: i32 = @intCast(1024 + world_mode.entity_count);
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

    const width_of_monitor_in_meters = 0.635;
    const meters_to_pixels: f32 = @as(f32, @floatFromInt(draw_buffer.width)) * width_of_monitor_in_meters;
    const focal_length: f32 = 0.6;
    const distance_above_ground: f32 = 9;
    const mouse_position: Vector2 = Vector2.new(input.mouse_x, input.mouse_y);

    render_group.perspectiveMode(
        meters_to_pixels,
        focal_length,
        distance_above_ground,
    );

    // Clear background.
    const background_color: Color = .new(0.15, 0.15, 0.15, 1);
    render_group.pushClear(background_color);

    const screen_bounds = render_group.getCameraRectangleAtTarget();
    var camera_bounds_in_meters = math.Rectangle3.fromMinMax(
        screen_bounds.min.toVector3(0),
        screen_bounds.max.toVector3(0),
    );
    _ = camera_bounds_in_meters.min.setZ(-3.0 * world_mode.typical_floor_height);
    _ = camera_bounds_in_meters.max.setZ(1.0 * world_mode.typical_floor_height);

    const sim_bounds_expansion = Vector3.new(15, 15, 15);
    const sim_bounds = camera_bounds_in_meters.addRadius(sim_bounds_expansion);
    const sim_memory = transient_state.arena.beginTemporaryMemory();
    const sim_center_position = world_mode.camera_position;
    const sim_region = sim.beginSimulation(
        &transient_state.arena,
        world_mode.world,
        sim_center_position,
        sim_bounds,
        input.frame_delta_time,
    );

    const camera_position: Vector3 =
        world.subtractPositions(world_mode.world, &world_mode.camera_position, &sim_center_position)
            .plus(world_mode.camera_offset);

    var world_transform = ObjectTransform.defaultUpright();
    world_transform.offset_position = world_transform.offset_position.minus(camera_position);

    render_group.pushRectangleOutline(
        world_transform,
        screen_bounds.getDimension(),
        Vector3.zero(),
        Color.new(1, 1, 0, 1),
        0.1,
    );
    // render_group.pushRectangleOutline(
    //     world_transform,
    //     camera_bounds_in_meters.getDimension().xy(),
    //     Vector3.zero(),
    //     Color.new(1, 1, 1, 1),
    // );
    render_group.pushRectangleOutline(
        world_transform,
        sim_bounds.getDimension().xy(),
        Vector3.zero(),
        Color.new(0, 1, 1, 1),
        0.1,
    );
    render_group.pushRectangleOutline(
        world_transform,
        sim_region.bounds.getDimension().xy(),
        Vector3.zero(),
        Color.new(1, 0, 1, 1),
        0.1,
    );

    const delta_time = input.frame_delta_time;

    // Check if any players are trying to join.
    for (&input.controllers, 0..) |*controller, controller_index| {
        const controlled_hero = &state.controlled_heroes[controller_index];
        if (controlled_hero.brain_id.value == 0) {
            if (controller.start_button.wasPressed()) {
                controlled_hero.* = shared.ControlledHero{};

                var traversable: TraversableReference = undefined;
                if (sim.getClosestTraversable(sim_region, camera_position, &traversable, 0)) {
                    controlled_hero.brain_id = .{ .value = @as(u32, @intCast(controller_index)) + @intFromEnum(ReservedBrainId.FirstHero) };
                    addPlayer(state.mode.world, sim_region, traversable, controlled_hero.brain_id);
                }
            }
        }
    }

    // Run all brains.
    TimedBlock.beginBlock(@src(), .ExecuteBrains);
    var brain_index: u32 = 0;
    while (brain_index < sim_region.brain_count) : (brain_index += 1) {
        const brain: *Brain = &sim_region.brains[brain_index];
        brains.executeBrain(state, world_mode, sim_region, input, brain, delta_time);
    }
    TimedBlock.endBlock(@src(), .ExecuteBrains);

    entities.updateAndRenderEntities(
        world_mode,
        transient_state,
        render_group,
        sim_region,
        camera_position,
        draw_buffer,
        background_color,
        delta_time,
        mouse_position,
    );

    render_group.global_color_time = .zero();
    render_group.orthographicMode(1);
    render_group.pushRectangleOutline(
        ObjectTransform.defaultFlat(),
        Vector2.new(5, 5),
        mouse_position.toVector3(0),
        Color.new(1, 1, 1, 1),
        0.2,
    );

    sim.endSimulation(world_mode, sim_region);
    transient_state.arena.endTemporaryMemory(sim_memory);

    var heores_exist: bool = false;
    var controlled_hero_index: u32 = 0;
    while (controlled_hero_index < state.controlled_heroes.len) : (controlled_hero_index += 1) {
        if (state.controlled_heroes[controlled_hero_index].brain_id.value != 0) {
            heores_exist = true;
            break;
        }
    }

    if (!heores_exist) {
        cutscene.playTitleScreen(state, transient_state);
    }

    return result;
}

fn beginEntity(world_mode: *GameModeWorld) *Entity {
    std.debug.assert(world_mode.creation_buffer_index < world_mode.creation_buffer.len);

    var entity: *Entity = &world_mode.creation_buffer[world_mode.creation_buffer_index];
    world_mode.creation_buffer_index += 1;

    memory.zeroStruct(Entity, entity);

    entity.x_axis = .new(1, 0);
    entity.y_axis = .new(0, 1);

    world_mode.last_used_entity_storage_index += 1;
    entity.id = .{ .value = world_mode.last_used_entity_storage_index };
    entity.collision = world_mode.null_collision;

    return entity;
}

fn endEntity(world_mode: *GameModeWorld, entity: *Entity, chunk_position: WorldPosition) void {
    world_mode.creation_buffer_index -= 1;

    std.debug.assert(@intFromPtr(entity) == @intFromPtr(&world_mode.creation_buffer[world_mode.creation_buffer_index]));

    entity.position = chunk_position.offset;
    world.packEntityIntoWorld(world_mode.world, null, entity, chunk_position);
}

fn beginGroundedEntity(
    world_mode: *GameModeWorld,
    collision: *EntityCollisionVolumeGroup,
) *Entity {
    const entity = beginEntity(world_mode);
    entity.collision = collision;
    return entity;
}

const StandardRoom = struct {
    position: [17][9]WorldPosition = undefined,
    ground: [17][9]TraversableReference = undefined,
};

fn addStandardRoom(
    world_mode: *GameModeWorld,
    abs_tile_x: i32,
    abs_tile_y: i32,
    abs_tile_z: i32,
) StandardRoom {
    var result: StandardRoom = .{};
    var offset_x: i32 = -8;
    while (offset_x <= 8) : (offset_x += 1) {
        var offset_y: i32 = -4;
        while (offset_y <= 4) : (offset_y += 1) {
            var standing_on: TraversableReference = .{};
            var world_position = chunkPositionFromTilePosition(
                world_mode.world,
                abs_tile_x + offset_x,
                abs_tile_y + offset_y,
                abs_tile_z,
                null,
            );

            if (false) {
                _ = world_position.offset.setX(world_position.offset.x() + 0.25 * world_mode.game_entropy.randomBilateral());
                _ = world_position.offset.setY(world_position.offset.y() + 0.25 * world_mode.game_entropy.randomBilateral());
            }

            if (offset_x >= -5 and offset_x <= -3 and offset_y >= 0 and offset_y <= 1) {
                // Hole down to the floor below.
            } else {
                if (offset_x == 3 and offset_y >= -2 and offset_y <= 2) {
                    _ = world_position.offset.setZ(world_position.offset.z() + 0.5 * @as(f32, @floatFromInt(offset_y + 2)));
                }

                // _ = world_position.offset.setZ(0.25 * @as(f32, @floatFromInt(offset_x + offset_y)));

                if (offset_x == 2 and offset_y == 2) {
                    const entity: *Entity = beginGroundedEntity(world_mode, world_mode.floor_collision);
                    standing_on.entity.index = entity.id;
                    entity.traversable_count = 1;
                    entity.traversables[0].position = Vector3.zero();
                    entity.traversables[0].occupier = null;
                    endEntity(world_mode, entity, world_position);
                } else {
                    const entity: *Entity = beginGroundedEntity(world_mode, world_mode.floor_collision);
                    standing_on.entity.index = entity.id;
                    entity.traversable_count = 1;
                    entity.traversables[0].position = Vector3.zero();
                    entity.traversables[0].occupier = null;
                    endEntity(world_mode, entity, world_position);
                }
            }

            result.position[@intCast(offset_x + 8)][@intCast(offset_y + 4)] = world_position;
            result.ground[@intCast(offset_x + 8)][@intCast(offset_y + 4)] = standing_on;
        }
    }

    return result;
}

fn addBrain(world_mode: *GameModeWorld) BrainId {
    world_mode.last_used_entity_storage_index += 1;
    const brain_id: BrainId = .{ .value = world_mode.last_used_entity_storage_index };
    return brain_id;
}

pub fn addPlayer(
    world_mode: *GameModeWorld,
    sim_region: *sim.SimRegion,
    standing_on: TraversableReference,
    brain_id: BrainId,
) void {
    const position: WorldPosition = world.mapIntoChunkSpace(
        sim_region.world,
        sim_region.origin,
        standing_on.getSimSpaceTraversable().position,
    );
    var body = beginGroundedEntity(world_mode, world_mode.hero_body_collision);
    body.addFlags(EntityFlags.Collides.toInt());

    const head = beginGroundedEntity(world_mode, world_mode.hero_head_collision);
    head.addFlags(EntityFlags.Collides.toInt());

    const glove = beginGroundedEntity(world_mode, world_mode.hero_glove_collision);
    glove.addFlags(EntityFlags.Collides.toInt());
    glove.movement_mode = .AngleOffset;
    glove.angle_current = -0.25 * math.TAU32;
    glove.angle_base_distance = 0.3;
    glove.angle_swipe_distance = 1;
    glove.angle_current_distance = 0.3;

    initHitPoints(body, 3);

    head.brain_slot = BrainSlot.forField(BrainHero, "head");
    head.brain_id = brain_id;

    body.brain_slot = BrainSlot.forField(BrainHero, "body");
    body.brain_id = brain_id;
    body.occupying = standing_on;

    glove.brain_slot = BrainSlot.forField(BrainHero, "glove");
    glove.brain_id = brain_id;

    if (world_mode.camera_following_entity_index.value == 0) {
        world_mode.camera_following_entity_index = head.id;
    }

    const hero_scale = 3;
    const shadow_alpha = 0.5;
    const color: Color = .white();
    body.addPiece(.Shadow, hero_scale * 1.0, .zero(), .new(1, 1, 1, shadow_alpha), null);
    body.addPiece(
        .Torso,
        hero_scale * 1.2,
        .new(0, 0, -0.002),
        color,
        @intFromEnum(EntityVisiblePieceFlag.AxesDeform),
    );
    body.addPiece(
        .Cape,
        hero_scale * 1.2,
        .new(0, -0.1, -0.001),
        color,
        @intFromEnum(EntityVisiblePieceFlag.AxesDeform) | @intFromEnum(EntityVisiblePieceFlag.BobOffset),
    );

    head.addPiece(.Head, hero_scale * 1.2, .new(0, -0.7, 0), color, null);

    glove.addPiece(.Sword, hero_scale * 0.25, .new(0, 0, 0), color, null);

    endEntity(world_mode, glove, position);
    endEntity(world_mode, head, position);
    endEntity(world_mode, body, position);
}

fn addWall(world_mode: *GameModeWorld, world_position: WorldPosition, standing_on: TraversableReference) void {
    const entity = beginGroundedEntity(world_mode, world_mode.wall_collision);

    entity.addFlags(EntityFlags.Collides.toInt());
    entity.occupying = standing_on;
    entity.addPiece(.Tree, 2.5, .zero(), .white(), null);

    endEntity(world_mode, entity, world_position);
}

fn addStairs(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) void {
    const world_position = chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = beginGroundedEntity(world_mode, world_mode.stair_collsion);

    entity.walkable_dimension = entity.collision.total_volume.dimension.xy();
    entity.walkable_height = world_mode.typical_floor_height;
    entity.addFlags(EntityFlags.Collides.toInt());

    endEntity(world_mode, entity, world_position);
}

fn addMonster(world_mode: *GameModeWorld, world_position: WorldPosition, standing_on: TraversableReference) void {
    var entity = beginGroundedEntity(world_mode, world_mode.monster_collsion);

    entity.collision = world_mode.monster_collsion;
    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainMonster, "body");
    entity.brain_id = addBrain(world_mode);
    entity.occupying = standing_on;

    initHitPoints(entity, 3);

    entity.addPiece(.Shadow, 4.5, .zero(), .new(1, 1, 1, 0.5), null);
    entity.addPiece(.Torso, 4.5, .zero(), .white(), null);

    endEntity(world_mode, entity, world_position);
}

fn addSnakeSegment(
    world_mode: *GameModeWorld,
    world_position: WorldPosition,
    standing_on: TraversableReference,
    brain_id: BrainId,
    segment_index: u32,
) void {
    var entity = beginGroundedEntity(world_mode, world_mode.monster_collsion);

    entity.collision = world_mode.monster_collsion;
    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forIndexedField(BrainSnake, "segments", segment_index);
    entity.brain_id = brain_id;
    entity.occupying = standing_on;

    initHitPoints(entity, 3);

    entity.addPiece(.Shadow, 1.5, .zero(), .new(1, 1, 1, 0.5), null);
    entity.addPiece(if (segment_index != 0) .Torso else .Head, 1.5, .zero(), .white(), null);

    endEntity(world_mode, entity, world_position);
}

fn addFamiliar(world_mode: *GameModeWorld, world_position: WorldPosition, standing_on: TraversableReference) void {
    const entity = beginGroundedEntity(world_mode, world_mode.familiar_collsion);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainFamiliar, "head");
    entity.brain_id = addBrain(world_mode);
    entity.occupying = standing_on;

    const shadow_alpha = 0.5;
    entity.addPiece(.Shadow, 2.5, .zero(), .new(1, 1, 1, shadow_alpha), null);
    entity.addPiece(.Head, 2.5, .zero(), .white(), @intFromEnum(EntityVisiblePieceFlag.BobOffset));

    endEntity(world_mode, entity, world_position);
}

pub fn addCollisionRule(world_mode: *GameModeWorld, in_id_a: u32, in_id_b: u32, can_collide: bool) void {
    var id_a = in_id_a;
    var id_b = in_id_b;

    // Sort entities based on storage index.
    if (id_a > id_b) {
        const temp = id_a;
        id_a = id_b;
        id_b = temp;
    }

    // Look for an existing rule in the hash.
    const hash_bucket = id_a & ((world_mode.collision_rule_hash.len) - 1);
    var found_rule: ?*PairwiseCollisionRule = null;
    var opt_rule: ?*PairwiseCollisionRule = world_mode.collision_rule_hash[hash_bucket];
    while (opt_rule) |rule| : (opt_rule = rule.next_in_hash) {
        if (rule.id_a == id_a and rule.id_b == id_b) {
            found_rule = rule;
            break;
        }
    }

    // Create a new rule if it didn't exist.
    if (found_rule == null) {
        found_rule = world_mode.first_free_collision_rule;

        if (found_rule) |rule| {
            world_mode.first_free_collision_rule = rule.next_in_hash;
        } else {
            found_rule = world_mode.world.arena.pushStruct(PairwiseCollisionRule, null);
        }

        found_rule.?.next_in_hash = world_mode.collision_rule_hash[hash_bucket];
        world_mode.collision_rule_hash[hash_bucket] = found_rule.?;
    }

    // Apply the rule settings.
    if (found_rule) |found| {
        found.id_a = id_a;
        found.id_b = id_b;
        found.can_collide = can_collide;
    }
}

pub fn clearCollisionRulesFor(world_mode: *GameModeWorld, id: u32) void {
    var hash_bucket: u32 = 0;
    while (hash_bucket < world_mode.collision_rule_hash.len) : (hash_bucket += 1) {
        var opt_rule = &world_mode.collision_rule_hash[hash_bucket];
        while (opt_rule.*) |rule| {
            if (rule.id_a == id or rule.id_b == id) {
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

fn initHitPoints(entity: *Entity, count: u32) void {
    std.debug.assert(count <= entity.hit_points.len);

    entity.hit_point_max = count;

    var hit_point_index: u32 = 0;
    while (hit_point_index < entity.hit_point_max) : (hit_point_index += 1) {
        const hit_point = &entity.hit_points[hit_point_index];

        hit_point.flags = 0;
        hit_point.filled_amount = shared.HIT_POINT_SUB_COUNT;
    }
}

fn makeSimpleGroundedCollision(
    world_mode: *GameModeWorld,
    x_dimension: f32,
    y_dimension: f32,
    z_dimension: f32,
    opt_z_offset: ?f32,
) *EntityCollisionVolumeGroup {
    const z_offset: f32 = opt_z_offset orelse 0;
    const group = world_mode.world.arena.pushStruct(EntityCollisionVolumeGroup, null);

    group.volume_count = 1;
    group.volumes = world_mode.world.arena.pushArray(group.volume_count, EntityCollisionVolume, null);
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
) *EntityCollisionVolumeGroup {
    const group = world_mode.world.arena.pushStruct(EntityCollisionVolumeGroup, null);

    group.volume_count = 0;
    group.total_volume.offset_position = Vector3.new(0, 0, 0);
    group.total_volume.dimension = Vector3.new(x_dimension, y_dimension, z_dimension);

    if (false) {
        group.volume_count = 1;
        group.volumes = world_mode.world.arena.pushArray(group.volume_count, EntityCollisionVolume, null);
        group.total_volume.offset_position = Vector3.new(0, 0, 0.5 * z_dimension);
        group.total_volume.dimension = Vector3.new(x_dimension, y_dimension, z_dimension);
        group.volumes[0] = group.total_volume;
    }

    return group;
}

fn makeNullCollision(world_mode: *GameModeWorld) *EntityCollisionVolumeGroup {
    const group = world_mode.world.arena.pushStruct(EntityCollisionVolumeGroup, null);

    group.volume_count = 0;
    group.volumes = undefined;
    group.total_volume.offset_position = Vector3.zero();
    group.total_volume.dimension = Vector3.zero();

    return group;
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

fn renderTest(
    world_mode: *GameModeWorld,
    transient_state: TransientState,
    input: *shared.GameInput,
    render_group: *RenderGroup,
    draw_buffer: *asset.LoadedBitmap,
) void {
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

    render_group.renderToOutput(transient_state.high_priority_queue, draw_buffer);
    render_group.endRender();
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
