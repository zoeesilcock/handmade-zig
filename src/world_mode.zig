const shared = @import("shared.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const world = @import("world.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
const asset = @import("asset.zig");
const audio = @import("audio.zig");
const render = @import("render.zig");
const rendergroup = @import("rendergroup.zig");
const particles = @import("particles.zig");
const random = @import("random.zig");
const intrinsics = @import("intrinsics.zig");
const file_formats = @import("file_formats");
const handmade = @import("handmade.zig");
const cutscene = @import("cutscene.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

var global_config = &@import("config.zig").global_config;
const tile_side_in_meters: f32 = 1.4;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Rectangle2 = math.Rectangle2;
const Rectangle2i = math.Rectangle2i;
const Matrix4x4 = math.Matrix4x4;
const Color = math.Color;
const State = shared.State;
const ControlledHero = shared.ControlledHero;
const GameInputMouseButton = shared.GameInputMouseButton;
const TransientState = shared.TransientState;
const WorldPosition = world.WorldPosition;
const LoadedBitmap = asset.LoadedBitmap;
const PlayingSound = audio.PlayingSound;
const BitmapId = file_formats.BitmapId;
const RenderGroup = rendergroup.RenderGroup;
const ObjectTransform = rendergroup.ObjectTransform;
const TransientClipRect = rendergroup.TransientClipRect;
const CameraParams = render.CameraParams;
const ParticleCache = particles.ParticleCache;
const DebugInterface = debug_interface.DebugInterface;
const AssetTagId = file_formats.AssetTagId;
const TimedBlock = debug_interface.TimedBlock;
const MemoryArena = memory.MemoryArena;
const ArenaPushParams = memory.ArenaPushParams;
const TemporaryMemory = memory.TemporaryMemory;
const Entity = entities.Entity;
const EntityId = entities.EntityId;
const EntityReference = entities.EntityReference;
const TraversableReference = entities.TraversableReference;
const EntityFlags = entities.EntityFlags;
const EntityTraversablePoint = entities.EntityTraversablePoint;
const EntityVisiblePiece = entities.EntityVisiblePiece;
const EntityVisiblePieceFlag = entities.EntityVisiblePieceFlag;
const CameraBehavior = entities.CameraBehavior;
const Brain = brains.Brain;
const BrainId = brains.BrainId;
const BrainSlot = brains.BrainSlot;
const BrainHero = brains.BrainHero;
const BrainSnake = brains.BrainSnake;
const BrainMonster = brains.BrainMonster;
const BrainFamiliar = brains.BrainFamiliar;
const ReservedBrainId = brains.ReservedBrainId;
const SimRegion = sim.SimRegion;

pub const GameCamera = struct {
    following_entity_index: EntityId = .{},
    position: WorldPosition,
    simulation_center: WorldPosition,
    offset_z: f32,

    target_position: WorldPosition,
    target_offset_z: f32,

    in_special: EntityId,
    time_in_special: f32,
};

pub const GameModeWorld = struct {
    world: *world.World = undefined,
    camera: GameCamera,

    standard_room_dimension: Vector3 = .zero(),
    typical_floor_height: f32 = 0,

    effects_entropy: random.Series,

    next_particle: u32 = 0,
    particles: [256]Particle = [1]Particle{Particle{}} ** 256,
    particle_cels: [particles.PARTICLE_CEL_DIM][particles.PARTICLE_CEL_DIM]ParticleCel = undefined,
    particle_cache: *ParticleCache,

    creation_region: ?*SimRegion,
    last_used_entity_storage_index: u32,

    last_mouse_position: Vector2,
    use_debug_camera: bool,
    debug_camera_pitch: f32,
    debug_camera_orbit: f32,
    debug_camera_dolly: f32,
    debug_light_position: Vector3,

    camera_pitch: f32,
    camera_orbit: f32,
    camera_dolly: f32,
};

const WorldSim = struct {
    sim_region: *SimRegion = undefined,
    sim_memory: TemporaryMemory = undefined,
};

const WorldSimWork = struct {
    sim_center_position: WorldPosition,
    sim_bounds: Rectangle3,
    world_mode: *GameModeWorld,
    delta_time: f32,
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

    world_mode.particle_cache =
        state.mode_arena.pushStruct(ParticleCache, ArenaPushParams.aligned(@alignOf(ParticleCache), false));
    particles.initParticleCache(world_mode.particle_cache, transient_state.assets);

    world_mode.last_used_entity_storage_index = @intFromEnum(ReservedBrainId.FirstFree);
    world_mode.effects_entropy = .seed(1234);
    world_mode.typical_floor_height = 5;

    // TODO: Replace this with a value received from the renderer.
    // const pixels_to_meters = 1.0 / 42.0;
    const chunk_dimension_in_meters = Vector3.new(17 * 1.4, 9 * 1.4, world_mode.typical_floor_height);

    world_mode.world = world.createWorld(chunk_dimension_in_meters, &state.mode_arena);
    world_mode.standard_room_dimension = Vector3.new(17 * 1.4, 9 * 1.4, world_mode.typical_floor_height);

    const sim_memory = transient_state.arena.beginTemporaryMemory();
    const null_origin: WorldPosition = .zero();
    const null_rect: Rectangle3 = .{ .min = .zero(), .max = .zero() };
    world_mode.creation_region = sim.beginWorldChange(
        &transient_state.arena,
        world_mode.world,
        null_origin,
        null_rect,
        0,
    );

    var series = world_mode.world.game_entropy;
    const screen_base_z: i32 = 0;
    var door_direction: u32 = 0;
    var room_center_tile_x: i32 = 0;
    var room_center_tile_y: i32 = 0;
    var abs_tile_z: i32 = screen_base_z;

    var last_screen_z: i32 = abs_tile_z;

    var door_left = false;
    var door_right = false;
    var door_top = false;
    var door_bottom = false;
    var door_up = false;
    var door_down = false;
    var prev_room: StandardRoom = .{};

    for (0..1) |screen_index| {
        last_screen_z = abs_tile_z;

        // const room_radius_x: i32 = 8 + @as(i32, @intCast(series.randomChoice(4)));
        // const room_radius_y: i32 = 4 + @as(i32, @intCast(series.randomChoice(4)));
        _ = series.randomChoice(4);
        const room_radius_x: i32 = 4;
        const room_radius_y: i32 = 4;
        if (door_direction == 1) {
            room_center_tile_x += room_radius_x;
        } else if (door_direction == 0) {
            room_center_tile_y += room_radius_y;
        }

        // const door_direction = 1;
        // _ = series.randomChoice(2);
        door_direction = 2;
        // const door_direction = series.randomChoice(if (door_up or door_down) 2 else 4);
        // door_direction = series.randomChoice(2);

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

        var left_hole: bool = @mod(screen_index, 2) != 0;
        var right_hole: bool = !left_hole;
        if (screen_index == 0) {
            left_hole = false;
            right_hole = false;
        }

        const room_width: i32 = 2 * room_radius_x + 1;
        const room_height: i32 = 2 * room_radius_y + 1;
        const room: StandardRoom = addStandardRoom(
            world_mode,
            room_center_tile_x,
            room_center_tile_y,
            abs_tile_z,
            left_hole,
            right_hole,
            room_radius_x,
            room_radius_y,
        );

        if (false) {
            _ = addMonster(world_mode, room.position[3][6], room.ground[3][6]);
            _ = addFamiliar(world_mode, room.position[4][3], room.ground[4][3]);

            const snake_brain_id = addBrain(world_mode);
            var segment_index: u32 = 0;
            while (segment_index < 5) : (segment_index += 1) {
                const x: u32 = 2 + segment_index;
                _ = addSnakeSegment(world_mode, room.position[x][2], room.ground[x][2], snake_brain_id, segment_index);
            }
        }

        for (0..@intCast(room_height)) |tile_y| {
            for (0..@intCast(room_width)) |tile_x| {
                const position: WorldPosition = room.position[tile_x][tile_y];
                const ground: TraversableReference = room.ground[tile_x][tile_y];

                var should_be_door = true;
                if ((tile_x == 0) and (!door_left or (tile_y != @divFloor(room_height, 2)))) {
                    should_be_door = false;
                }
                if ((tile_x == (room_width - 1)) and (!door_right or (tile_y != @divFloor(room_height, 2)))) {
                    should_be_door = false;
                }
                if ((tile_y == 0) and (!door_bottom or (tile_x != @divFloor(room_width, 2)))) {
                    should_be_door = false;
                }
                if ((tile_y == (room_height - 1)) and (!door_top or (tile_x != @divFloor(room_width, 2)))) {
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
            room_center_tile_x += room_radius_x + 1;
        } else {
            room_center_tile_y += room_radius_y + 1;
        }

        prev_room = room;
    }

    if (false) {
        // Fill the low entity storage with walls.
        while (world_mode.entity_count < (world_mode.low_entities.len - 16)) {
            const coordinate: i32 = @intCast(1024 + world_mode.entity_count);
            _ = addWall(world_mode, coordinate, coordinate, 0);
        }
    }

    const camera_tile_x = room_center_tile_x;
    const camera_tile_y = room_center_tile_y;
    const camera_tile_z = last_screen_z;
    const new_camera_position: WorldPosition = chunkPositionFromTilePosition(
        world_mode.world,
        camera_tile_x,
        camera_tile_y,
        camera_tile_z,
        null,
    );
    world_mode.camera.position = new_camera_position;
    world_mode.camera.simulation_center = new_camera_position;

    sim.endWorldChange(world_mode.world, world_mode.creation_region.?);
    world_mode.creation_region = null;
    transient_state.arena.endTemporaryMemory(sim_memory);

    state.mode = .{ .world = world_mode };
}

fn checkForJoiningPlayers(
    opt_state: ?*shared.State,
    opt_input: ?*shared.GameInput,
    sim_region: *SimRegion,
) void {
    if (opt_input) |input| {
        if (opt_state) |state| {
            for (&input.controllers, 0..) |*controller, controller_index| {
                const controlled_hero = &state.controlled_heroes[controller_index];
                if (controlled_hero.brain_id.value == 0) {
                    if (controller.start_button.wasPressed()) {
                        controlled_hero.* = shared.ControlledHero{};

                        var traversable: TraversableReference = undefined;
                        if (sim.getClosestTraversable(sim_region, .zero(), &traversable, 0)) {
                            controlled_hero.brain_id = .{ .value = @as(u32, @intCast(controller_index)) + @intFromEnum(ReservedBrainId.FirstHero) };
                            addPlayer(state.mode.world, sim_region, traversable, controlled_hero.brain_id);
                        }
                    }
                }
            }
        }
    }
}

fn beginSim(
    temp_arena: *MemoryArena,
    world_ptr: *world.World,
    sim_center_position: WorldPosition,
    sim_bounds: Rectangle3,
    delta_time: f32,
) WorldSim {
    var result: WorldSim = .{};
    const sim_memory: TemporaryMemory = temp_arena.beginTemporaryMemory();

    const sim_region = sim.beginWorldChange(
        temp_arena,
        world_ptr,
        sim_center_position,
        sim_bounds,
        delta_time,
    );

    result.sim_region = sim_region;
    result.sim_memory = sim_memory;

    return result;
}

fn simulate(
    world_sim: *WorldSim,
    game_entropy: *random.Series,
    delta_time: f32,
    // Optional...
    assets: ?*asset.Assets,
    opt_state: ?*shared.State,
    opt_input: ?*shared.GameInput,
    opt_render_group: ?*RenderGroup,
    particle_cache: ?*ParticleCache,
) void {
    const sim_region: *SimRegion = world_sim.sim_region;

    // Run all brains.
    TimedBlock.beginBlock(@src(), .ExecuteBrains);
    var brain_index: u32 = 0;
    while (brain_index < sim_region.brain_count) : (brain_index += 1) {
        const brain: *Brain = &sim_region.brains[brain_index];
        brains.markBrainActive(brain);
    }

    brain_index = 0;
    while (brain_index < sim_region.brain_count) : (brain_index += 1) {
        const brain: *Brain = &sim_region.brains[brain_index];
        brains.executeBrain(opt_state, game_entropy, sim_region, opt_input, brain, delta_time);
    }
    TimedBlock.endBlock(@src(), .ExecuteBrains);

    entities.updateAndRenderEntities(
        sim_region,
        delta_time,
        opt_render_group,
        particle_cache,
        assets,
    );
}

fn endSim(
    arena: *MemoryArena,
    world_sim: *WorldSim,
    world_ptr: *world.World,
) void {
    sim.endWorldChange(world_ptr, world_sim.sim_region);
    arena.endTemporaryMemory(world_sim.sim_memory);
}

pub fn doWorldSim(queue: shared.PlatformWorkQueuePtr, data: *anyopaque) callconv(.c) void {
    _ = queue;

    TimedBlock.beginFunction(@src(), .DoWorldSim);
    defer TimedBlock.endFunction(@src(), .DoWorldSim);

    // TODO: It is inneficient to reallocate every time - this should be something that is passsed as a property
    // of the worker thread.
    var arena: MemoryArena = .{};

    const work: *WorldSimWork = @ptrCast(@alignCast(data));

    var world_sim: WorldSim = beginSim(
        &arena,
        work.world_mode.world,
        work.sim_center_position,
        work.sim_bounds,
        work.delta_time,
    );
    simulate(
        &world_sim,
        &work.world_mode.world.game_entropy,
        work.delta_time,
        null,
        null,
        null,
        null,
        null,
    );
    endSim(&arena, &world_sim, work.world_mode.world);

    arena.clear();
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

    var camera_offset: Vector3 = .new(0, 0, world_mode.camera.offset_z);
    const camera: CameraParams = .get(draw_buffer.width, 0.6);
    const mouse_position: Vector2 = Vector2.new(input.mouse_x, input.mouse_y);
    const d_mouse_p: Vector2 = mouse_position.minus(world_mode.last_mouse_position);
    if (input.alt_down and input.mouse_buttons[GameInputMouseButton.Left.toInt()].isDown()) {
        const rotation_speed: f32 = 0.001 * math.PI32;
        world_mode.debug_camera_orbit -= rotation_speed * d_mouse_p.x();
        world_mode.debug_camera_pitch += rotation_speed * d_mouse_p.y();
    } else if (input.alt_down and input.mouse_buttons[GameInputMouseButton.Middle.toInt()].isDown()) {
        const zoom_speed: f32 = (camera_offset.z() + world_mode.debug_camera_dolly) * 0.005;
        world_mode.debug_camera_dolly -= zoom_speed * d_mouse_p.y();
    }

    if (input.mouse_buttons[GameInputMouseButton.Right.toInt()].wasPressed()) {
        world_mode.use_debug_camera = !world_mode.use_debug_camera;
    }

    world_mode.last_mouse_position = mouse_position;
    DebugInterface.debugSetMousePosition(mouse_position);

    world_mode.camera_pitch = 0.05 * math.PI32;
    world_mode.camera_orbit = 0;
    world_mode.camera_dolly = 0;

    render_group.beginDepthPeel();

    // Clear background.
    const background_color: Color = .new(0.15, 0.15, 0.15, 0);
    render_group.pushClear(background_color);

    const near_clip_plane: f32 = 3;
    const far_clip_plane: f32 = 100;
    const debug_light_position: Vector3 = world_mode.debug_light_position;

    var camera_o: Matrix4x4 =
        Matrix4x4.zRotation(world_mode.camera_orbit).times(.xRotation(world_mode.camera_pitch));
    const delta_from_sim: Vector3 = world.subtractPositions(
        world_mode.world,
        &world_mode.camera.position,
        &world_mode.camera.simulation_center,
    );
    var camera_ot: Vector3 =
        camera_o.timesV(camera_offset.plus(delta_from_sim).plus(.new(0, 0, world_mode.camera_dolly)));
    render_group.setCameraTransform(
        camera.focal_length,
        camera_o.getColumn(0),
        camera_o.getColumn(1),
        camera_o.getColumn(2),
        camera_ot,
        0,
        near_clip_plane,
        far_clip_plane,
        true,
        debug_light_position,
    );

    if (world_mode.use_debug_camera) {
        camera_o =
            Matrix4x4.zRotation(world_mode.debug_camera_orbit).times(.xRotation(world_mode.debug_camera_pitch));
        camera_ot = camera_o.timesV(camera_offset.plus(.new(0, 0, world_mode.debug_camera_dolly)));
        render_group.setCameraTransform(
            camera.focal_length,
            camera_o.getColumn(0),
            camera_o.getColumn(1),
            camera_o.getColumn(2),
            camera_ot,
            @intFromEnum(rendergroup.CameraTransformFlag.IsDebug),
            near_clip_plane,
            far_clip_plane,
            false,
            debug_light_position,
        );
    }

    const world_camera_rect: Rectangle3 = render_group.getCameraRectangleAtTarget();
    const screen_bounds: Rectangle2 = .fromCenterDimension(.zero(), .new(
        world_camera_rect.max.x() - world_camera_rect.min.x(),
        world_camera_rect.max.y() - world_camera_rect.min.y(),
    ));
    var camera_bounds_in_meters = math.Rectangle3.fromMinMax(
        screen_bounds.min.toVector3(0),
        screen_bounds.max.toVector3(0),
    );
    _ = camera_bounds_in_meters.min.setZ(-3.0 * world_mode.typical_floor_height);
    _ = camera_bounds_in_meters.max.setZ(1.0 * world_mode.typical_floor_height);

    const sim_bounds: Rectangle3 = .fromCenterDimension(
        .zero(),
        world_mode.standard_room_dimension.scaledTo(3),
    );

    if (false) {
        var sim_work: [16]WorldSimWork = undefined;
        var sim_index: u32 = 0;
        for (0..4) |sim_y| {
            for (0..4) |sim_x| {
                var work: *WorldSimWork = &sim_work[sim_index];
                sim_index += 1;

                var center_position: WorldPosition = world_mode.camera.position;
                center_position.chunk_x += @intCast(-70 * (sim_x + 1));
                center_position.chunk_y += @intCast(-70 * (sim_y + 1));

                work.sim_center_position = center_position;
                work.sim_bounds = sim_bounds;
                work.world_mode = world_mode;
                work.delta_time = input.frame_delta_time;

                if (true) {
                    shared.platform.addQueueEntry(transient_state.high_priority_queue, &doWorldSim, work);
                } else {
                    doWorldSim(transient_state.high_priority_queue, work);
                }
            }
        }

        shared.platform.completeAllQueuedWork(transient_state.high_priority_queue);
    }

    var world_sim: WorldSim = beginSim(
        &transient_state.arena,
        world_mode.world,
        world_mode.camera.simulation_center,
        sim_bounds,
        input.frame_delta_time,
    );
    {
        checkForJoiningPlayers(state, input, world_sim.sim_region);

        simulate(
            &world_sim,
            &world_mode.world.game_entropy,
            input.frame_delta_time,
            transient_state.assets,
            state,
            input,
            render_group,
            world_mode.particle_cache,
        );

        // Can we merge the camera update down into the simulation so that we correctly update the camera for the current frame?

        const last_camera_position: WorldPosition = world_mode.camera.position;
        if (sim.getEntityByStorageIndex(
            world_sim.sim_region,
            world_mode.camera.following_entity_index,
        )) |camera_following_entity| {
            sim.updateCameraForEntityMovement(
                world_mode.world,
                world_sim.sim_region,
                &world_mode.camera,
                camera_following_entity,
                input.frame_delta_time,
            );
            world_mode.debug_light_position = camera_following_entity.position.plus(.new(0, 0, 2));
        }

        render_group.pushCubeLight(world_mode.debug_light_position, 0.1, .new(1, 1, 1), 1);

        // TODO: Re-enable particles.
        if (false) {
            const frame_to_frame_camera_delta_position: Vector3 =
                world.subtractPositions(world_mode.world, &world_mode.camera.position, &last_camera_position);
            particles.updateAndRenderParticleSystem(
                world_mode.particle_cache,
                input.frame_delta_time,
                render_group,
                frame_to_frame_camera_delta_position.negated(),
            );
        }

        var world_transform = ObjectTransform.defaultUpright();

        // render_group.pushVolumeOutline(
        //     &world_transform,
        //     .fromMinMax(.new(-1, -1, -1), .new(1, 1, 1)),
        //     .new(1, 1, 0, 1),
        //     0.01,
        // );

        if (true) {
            render_group.pushRectangleOutline(
                &world_transform,
                screen_bounds.getDimension(),
                Vector3.new(0, 0, 0.005),
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
                &world_transform,
                sim_bounds.getDimension().xy(),
                Vector3.new(0, 0, 0.005),
                Color.new(0, 1, 1, 1),
                0.1,
            );
            render_group.pushRectangleOutline(
                &world_transform,
                world_sim.sim_region.bounds.getDimension().xy(),
                Vector3.new(0, 0, 0.005),
                Color.new(1, 0, 1, 1),
                0.1,
            );
        }
    }
    endSim(&transient_state.arena, &world_sim, world_mode.world);

    render_group.lightingTest();
    render_group.endDepthPeel();

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

fn allocateEntityId(world_mode: *GameModeWorld) EntityId {
    world_mode.last_used_entity_storage_index += 1;
    const result: EntityId = .{ .value = world_mode.last_used_entity_storage_index };
    return result;
}

fn beginEntity(world_mode: *GameModeWorld) *Entity {
    const entity: *Entity = sim.createEntity(world_mode.creation_region.?, allocateEntityId(world_mode));

    entity.x_axis = .new(1, 0);
    entity.y_axis = .new(0, 1);

    return entity;
}

fn endEntity(world_mode: *GameModeWorld, entity: *Entity, chunk_position: WorldPosition) void {
    entity.position = world.subtractPositions(world_mode.world, &chunk_position, &world_mode.creation_region.?.origin);
}

fn beginGroundedEntity(
    world_mode: *GameModeWorld,
) *Entity {
    const entity = beginEntity(world_mode);
    return entity;
}

const StandardRoom = struct {
    position: [64][64]WorldPosition = undefined,
    ground: [64][64]TraversableReference = undefined,
};

fn addStandardRoom(
    world_mode: *GameModeWorld,
    abs_tile_x: i32,
    abs_tile_y: i32,
    abs_tile_z: i32,
    left_hole: bool,
    right_hole: bool,
    radius_x: i32,
    radius_y: i32,
) StandardRoom {
    var result: StandardRoom = .{};
    var offset_y: i32 = -radius_y;

    // const has_left_hole = left_hole;
    // const has_right_hole = right_hole;
    _ = left_hole;
    _ = right_hole;
    const has_left_hole = true;
    const has_right_hole = true;

    while (offset_y <= radius_y) : (offset_y += 1) {
        var offset_x: i32 = -radius_x;
        while (offset_x <= radius_x) : (offset_x += 1) {
            var standing_on: TraversableReference = .{};
            var world_position = chunkPositionFromTilePosition(
                world_mode.world,
                abs_tile_x + offset_x,
                abs_tile_y + offset_y,
                abs_tile_z,
                null,
            );

            if (has_left_hole and offset_x >= -5 and offset_x <= -3 and offset_y >= 0 and offset_y <= 1) {
                // Hole down to the floor below.
            } else if (has_right_hole and offset_x >= 3 and offset_x <= 4 and offset_y >= -1 and offset_y <= 2) {
                // Hole down to the floor below.
            } else {
                var wall_height: f32 = 0.5;
                if (offset_x >= -2 and offset_x <= 1 and offset_y == 2) {
                    wall_height = 3;
                }

                _ = world_position.offset.setX(world_position.offset.x() + 0 * world_mode.world.game_entropy.randomBilateral());
                _ = world_position.offset.setY(world_position.offset.y() + 0 * world_mode.world.game_entropy.randomBilateral());
                _ = world_position.offset.setZ(world_position.offset.z() + wall_height + 0.5 * world_mode.world.game_entropy.randomUnilateral());

                const entity: *Entity = beginGroundedEntity(world_mode);
                standing_on.entity.ptr = entity;
                standing_on.entity.index = entity.id;
                entity.traversable_count = 1;
                entity.traversables[0].position = Vector3.zero();
                entity.traversables[0].occupier = null;
                entity.addPieceV2(
                    .Grass,
                    .new(0.7, wall_height),
                    .zero(),
                    .newFromSRGB(0.31, 0.49, 0.32, 1),
                    @intFromEnum(EntityVisiblePieceFlag.Cube),
                );
                endEntity(world_mode, entity, world_position);
            }

            const array_x: usize = @intCast(offset_x + radius_x);
            const array_y: usize = @intCast(offset_y + radius_y);
            result.position[array_x][array_y] = world_position;
            result.ground[array_x][array_y] = standing_on;
        }
    }

    var stair_positions: [4]WorldPosition = [1]WorldPosition{undefined} ** 4;
    offset_y = -1;
    while (offset_y <= 2) : (offset_y += 1) {
        const offset_x: i32 = 3;
        var standing_on: TraversableReference = .{};
        var world_position = chunkPositionFromTilePosition(
            world_mode.world,
            abs_tile_x + offset_x,
            abs_tile_y + offset_y,
            abs_tile_z,
            .new(0.5 * tile_side_in_meters, 0, 0),
        );
        stair_positions[@intCast(offset_y + 1)] = world_position;

        _ = world_position.offset.setZ(
            world_position.offset.z() + 0.3 - (@as(f32, @floatFromInt(offset_y + 2)) * 0.8),
        );

        const entity: *Entity = beginGroundedEntity(world_mode);
        standing_on.entity.ptr = entity;
        standing_on.entity.index = entity.id;
        entity.traversable_count = 1;
        entity.traversables[0].position = Vector3.zero();
        entity.traversables[0].occupier = null;
        entity.addPieceV2(
            .Grass,
            .new(0.7, 0.5),
            .zero(),
            .newFromSRGB(0.31, 0.49, 0.32, 1),
            @intFromEnum(EntityVisiblePieceFlag.Cube),
        );
        endEntity(world_mode, entity, world_position);

        const array_x: usize = @intCast(offset_x + radius_x);
        const array_y: usize = @intCast(offset_y + radius_y);
        result.position[array_x][array_y] = world_position;
        result.ground[array_x][array_y] = standing_on;
    }

    {
        // Hole camera.
        const entity: *Entity = beginGroundedEntity(world_mode);
        entity.camera_behavior =
            @intFromEnum(CameraBehavior.Inspect) |
            @intFromEnum(CameraBehavior.Offset) |
            @intFromEnum(CameraBehavior.GeneralVelocityConstraint);
        entity.camera_offset = .new(0, 2, 3);
        entity.camera_min_time = 1;
        entity.camera_min_velocity = 0;
        entity.camera_max_velocity = 0.1;
        const x_dim: f32 = 1.5 * tile_side_in_meters;
        const y_dim: f32 = 0.5 * tile_side_in_meters;
        entity.collision_volume = .fromMinMax(
            .new(-x_dim, -y_dim, 0),
            .new(x_dim, y_dim, 0.5 * world_mode.typical_floor_height),
        );
        endEntity(world_mode, entity, result.position[@intCast(-4 + radius_x)][@intCast(-1 + radius_y)]);
    }

    {
        // Stairs camera, on stairs.
        var entity: *Entity = beginGroundedEntity(world_mode);
        entity.camera_behavior = @intFromEnum(CameraBehavior.ViewPlayer);
        var x_dim: f32 = 0.5 * tile_side_in_meters;
        var y_dim: f32 = 1.5 * tile_side_in_meters;
        entity.collision_volume = .fromMinMax(
            .new(-x_dim, -y_dim, -0.5 * world_mode.typical_floor_height),
            .new(x_dim, y_dim, 0.3 * world_mode.typical_floor_height),
        );
        endEntity(world_mode, entity, stair_positions[2]);

        // Stairs camera, at top of stairs.
        entity = beginGroundedEntity(world_mode);
        entity.camera_behavior =
            @intFromEnum(CameraBehavior.ViewPlayer) |
            @intFromEnum(CameraBehavior.DirectionalVelocityConstraint);
        entity.camera_velocity_direction = .new(0, 1, 0);
        entity.camera_min_velocity = 0.2;
        entity.camera_max_velocity = std.math.floatMax(f32);
        x_dim = 1 * tile_side_in_meters;
        y_dim = 1.5 * tile_side_in_meters;
        entity.collision_volume = .fromMinMax(
            .new(-x_dim, -y_dim, -0.2 * world_mode.typical_floor_height),
            .new(x_dim, y_dim, 0.5 * world_mode.typical_floor_height),
        );
        endEntity(world_mode, entity, stair_positions[0]);
    }

    const room_position = chunkPositionFromTilePosition(
        world_mode.world,
        abs_tile_x,
        abs_tile_y,
        abs_tile_z,
        null,
    );

    const room: *Entity = beginGroundedEntity(world_mode);
    room.collision_volume = makeSimpleGroundedCollision(
        @as(f32, @floatFromInt((2 * radius_x + 1))) * tile_side_in_meters,
        @as(f32, @floatFromInt((2 * radius_y + 1))) * tile_side_in_meters,
        world_mode.typical_floor_height,
        0,
    );

    room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
    endEntity(world_mode, room, room_position);

    return result;
}

fn addBrain(world_mode: *GameModeWorld) BrainId {
    world_mode.last_used_entity_storage_index += 1;
    const brain_id: BrainId = .{ .value = world_mode.last_used_entity_storage_index };
    return brain_id;
}

pub fn addPlayer(
    world_mode: *GameModeWorld,
    sim_region: *SimRegion,
    standing_on: TraversableReference,
    brain_id: BrainId,
) void {
    world_mode.creation_region = sim_region;
    defer world_mode.creation_region = null;

    const position: WorldPosition = world.mapIntoChunkSpace(
        sim_region.world,
        sim_region.origin,
        standing_on.getSimSpaceTraversable().position,
    );
    var body = beginGroundedEntity(world_mode);
    const head = beginGroundedEntity(world_mode);
    head.collision_volume = makeSimpleGroundedCollision(1, 0.5, 0.6, 0.7);
    head.addFlags(EntityFlags.Collides.toInt());

    const glove = beginGroundedEntity(world_mode);
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

    if (world_mode.camera.following_entity_index.value == 0) {
        world_mode.camera.following_entity_index = head.id;
    }

    const hero_scale = 3;
    const shadow_alpha = 0.5;
    const color: Color = .white();
    body.addPiece(.Shadow, hero_scale * 1.0, .zero(), .new(1, 1, 1, shadow_alpha), null);
    body.addPiece(
        .Torso,
        hero_scale * 1.2,
        .new(0, 0, 0),
        color,
        @intFromEnum(EntityVisiblePieceFlag.AxesDeform),
    );
    body.addPiece(
        .Cape,
        hero_scale * 1.2,
        .new(0, -0.1, 0),
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
    const entity = beginGroundedEntity(world_mode);

    entity.collision_volume = makeSimpleGroundedCollision(
        tile_side_in_meters,
        tile_side_in_meters,
        world_mode.typical_floor_height - 0.1,
        0,
    );

    entity.addFlags(EntityFlags.Collides.toInt());
    entity.occupying = standing_on;
    entity.addPiece(.Tree, 2.5, .zero(), .white(), null);

    endEntity(world_mode, entity, world_position);
}

fn addStairs(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) void {
    const world_position = chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = beginGroundedEntity(world_mode);

    entity.collision_volume = makeSimpleGroundedCollision(
        tile_side_in_meters,
        tile_side_in_meters * 2.0,
        world_mode.typical_floor_height * 1.1,
        0,
    );
    entity.walkable_dimension = entity.collision_volume.getDimension().xy();
    entity.walkable_height = world_mode.typical_floor_height;
    entity.addFlags(EntityFlags.Collides.toInt());

    endEntity(world_mode, entity, world_position);
}

fn addMonster(world_mode: *GameModeWorld, world_position: WorldPosition, standing_on: TraversableReference) void {
    var entity = beginGroundedEntity(world_mode);

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
    var entity = beginGroundedEntity(world_mode);

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
    const entity = beginGroundedEntity(world_mode);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainFamiliar, "head");
    entity.brain_id = addBrain(world_mode);
    entity.occupying = standing_on;

    const shadow_alpha = 0.5;
    entity.addPiece(.Shadow, 2.5, .zero(), .new(1, 1, 1, shadow_alpha), null);
    entity.addPiece(.Head, 2.5, .zero(), .white(), @intFromEnum(EntityVisiblePieceFlag.BobOffset));

    endEntity(world_mode, entity, world_position);
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
    x_dimension: f32,
    y_dimension: f32,
    z_dimension: f32,
    opt_z_offset: ?f32,
) Rectangle3 {
    const z_offset: f32 = opt_z_offset orelse 0;
    const result: Rectangle3 = .fromCenterDimension(
        Vector3.new(0, 0, 0.5 * z_dimension + z_offset),
        Vector3.new(x_dimension, y_dimension, z_dimension),
    );

    return result;
}

pub fn chunkPositionFromTilePosition(
    game_world: *world.World,
    abs_tile_x: i32,
    abs_tile_y: i32,
    abs_tile_z: i32,
    opt_additional_offset: ?Vector3,
) WorldPosition {
    const tile_depth_in_meters = game_world.chunk_dimension_in_meters.z();

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
    _ = offset.setZ(offset.z() - 0.4 * tile_depth_in_meters);

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
