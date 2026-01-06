const math = @import("math.zig");
const shared = @import("shared.zig");
const world_module = @import("world.zig");
const world_mode_module = @import("world_mode.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
const memory = @import("memory.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const TransientState = shared.TransientState;
const WorldPosition = world_module.WorldPosition;
const WorldRoom = world_module.WorldRoom;
const GameModeWorld = world_mode_module.GameModeWorld;
const Entity = entities.Entity;
const EntityFlags = entities.EntityFlags;
const EntityVisiblePiece = entities.EntityVisiblePiece;
const EntityVisiblePieceFlag = entities.EntityVisiblePieceFlag;
const TraversableReference = entities.TraversableReference;
const CameraBehavior = entities.CameraBehavior;
const BrainSlot = brains.BrainSlot;

const tile_side_in_meters = world_mode_module.tile_side_in_meters;

const WorldGenerator = struct {
    memory: memory.MemoryArena,
};
const GenRoomSpec = struct {};
const GenRoom = struct {};
const GenConnection = struct {};
const GenOrphanage = struct {
    hero_bedroom: *GenRoom,
    forest_entrance: *GenRoom,
};

fn genSpec(gen: *WorldGenerator) *GenRoomSpec {
    const spec: *GenRoomSpec = gen.memory.pushStruct(GenRoomSpec, null);
    return spec;
}

fn genRoom(gen: *WorldGenerator, spec: *GenRoomSpec) *GenRoom {
    _ = spec;
    const room: *GenRoom = gen.memory.pushStruct(GenRoom, null);
    return room;
}

fn connect(gen: *WorldGenerator, a: *GenRoom, b: *GenRoom) *GenConnection {
    _ = a;
    _ = b;
    const connection: *GenConnection = gen.memory.pushStruct(GenConnection, null);
    return connection;
}

fn beginWorldGen() *WorldGenerator {
    const gen: *WorldGenerator = memory.bootstrapPushStruct(WorldGenerator, "memory", null, null);
    return gen;
}

fn layout(gen: *WorldGenerator) void {
    _ = gen;
}

fn generateWorld(gen: *WorldGenerator, world: *world_module.World) void {
    _ = gen;
    _ = world;
}

fn endWorldGen(gen: *WorldGenerator) void {
    gen.memory.clear();
}

fn createOrphanage(gen: *WorldGenerator) GenOrphanage {
    var result: GenOrphanage = .{
        .hero_bedroom = undefined,
        .forest_entrance = undefined,
    };

    const bedroom_spec: *GenRoomSpec = genSpec(gen);
    const main_room_spec: *GenRoomSpec = genSpec(gen);
    const tailor_spec: *GenRoomSpec = genSpec(gen);
    const kitchen_spec: *GenRoomSpec = genSpec(gen);
    const garden_spec: *GenRoomSpec = genSpec(gen);
    const basic_forest_spec: *GenRoomSpec = genSpec(gen);

    const hero_bedroom: *GenRoom = genRoom(gen, bedroom_spec);
    const bedroom_a: *GenRoom = genRoom(gen, bedroom_spec);
    const bedroom_b: *GenRoom = genRoom(gen, bedroom_spec);
    const bedroom_c: *GenRoom = genRoom(gen, bedroom_spec);
    const bedroom_d: *GenRoom = genRoom(gen, bedroom_spec);
    const main_room: *GenRoom = genRoom(gen, main_room_spec);
    const tailor_room: *GenRoom = genRoom(gen, tailor_spec);
    const kitchen: *GenRoom = genRoom(gen, kitchen_spec);
    const forest_path: *GenRoom = genRoom(gen, basic_forest_spec);
    const garden: *GenRoom = genRoom(gen, garden_spec);
    const forest_entrance: *GenRoom = genRoom(gen, basic_forest_spec);
    const back_door_path: *GenRoom = genRoom(gen, basic_forest_spec);
    const side_alley: *GenRoom = genRoom(gen, basic_forest_spec);

    _ = connect(gen, main_room, hero_bedroom);
    _ = connect(gen, main_room, bedroom_a);
    _ = connect(gen, main_room, bedroom_b);
    _ = connect(gen, main_room, bedroom_c);
    _ = connect(gen, main_room, bedroom_d);
    _ = connect(gen, main_room, tailor_room);
    _ = connect(gen, main_room, kitchen);

    _ = connect(gen, main_room, forest_path);
    _ = connect(gen, main_room, back_door_path);

    _ = connect(gen, forest_path, garden);
    _ = connect(gen, forest_path, forest_entrance);

    _ = connect(gen, back_door_path, side_alley);
    _ = connect(gen, side_alley, forest_entrance);

    result.hero_bedroom = hero_bedroom;
    result.forest_entrance = forest_entrance;

    return result;
}

pub fn createWorldNew(world: *world_module.World) void {
    const gen: *WorldGenerator = beginWorldGen();
    const orphanage: GenOrphanage = createOrphanage(gen);
    _ = orphanage;
    layout(gen);
    generateWorld(gen, world);
    endWorldGen(gen);
}

pub fn createWorld(world_mode: *world_mode_module.GameModeWorld, transient_state: *TransientState) void {
    createWorldNew(world_mode.world);

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

    var series = &world_mode.world.game_entropy;
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

    for (0..8) |screen_index| {
        last_screen_z = abs_tile_z;

        // const room_radius_x: i32 = 8 + @as(i32, @intCast(series.randomChoice(4)));
        // const room_radius_y: i32 = 4 + @as(i32, @intCast(series.randomChoice(4)));
        _ = series.randomChoice(4);
        const room_radius_x: i32 = 8;
        const room_radius_y: i32 = 8;
        if (door_direction == 1) {
            room_center_tile_x += room_radius_x;
        } else if (door_direction == 0) {
            room_center_tile_y += room_radius_y;
        }

        // const door_direction = 1;
        // _ = series.randomChoice(2);
        // door_direction = 3;
        door_direction = series.randomChoice(if (door_up or door_down) 2 else 4);
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

        if (true) {
            // _ = addMonster(world_mode, room.position[3][6], room.ground[3][6]);
            // _ = addFamiliar(world_mode, room.position[4][3], room.ground[4][3]);

            const snake_brain_id = world_mode_module.addBrain(world_mode);
            var segment_index: u32 = 0;
            while (segment_index < 3) : (segment_index += 1) {
                const x: u32 = 2 + segment_index;
                _ = world_mode_module.addSnakeSegment(world_mode, room.position[x][1], room.ground[x][1], snake_brain_id, segment_index);
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
    const new_camera_position: WorldPosition = world_mode_module.chunkPositionFromTilePosition(
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
            var color: Color = .newFromSRGB(0.31, 0.49, 0.32, 1);
            color = .newFromSRGB(1, 1, 1, 1);

            var standing_on: TraversableReference = .{};
            var world_position = world_mode_module.chunkPositionFromTilePosition(
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
                if (offset_x >= -2 and offset_x <= 1 and (offset_y == 2 or offset_y == -2)) {
                    color = if (offset_y == -2) .newFromSRGB(1, 0, 0, 1) else .newFromSRGB(0, 0, 1, 1);
                    wall_height = 3;
                }

                _ = world_position.offset.setX(world_position.offset.x() + 0 * world_mode.world.game_entropy.randomBilateral());
                _ = world_position.offset.setY(world_position.offset.y() + 0 * world_mode.world.game_entropy.randomBilateral());
                _ = world_position.offset.setZ(world_position.offset.z() + wall_height + 0.5 * world_mode.world.game_entropy.randomUnilateral());

                const entity: *Entity = world_mode_module.beginGroundedEntity(world_mode);
                standing_on.entity.ptr = entity;
                standing_on.entity.index = entity.id;
                entity.traversable_count = 1;
                entity.traversables[0].position = Vector3.zero();
                entity.traversables[0].occupier = null;
                entity.addPieceV2(
                    .Grass,
                    .new(0.7, wall_height),
                    .zero(),
                    color,
                    @intFromEnum(EntityVisiblePieceFlag.Cube),
                );
                world_mode_module.endEntity(world_mode, entity, world_position);
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
        var world_position = world_mode_module.chunkPositionFromTilePosition(
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

        const entity: *Entity = world_mode_module.beginGroundedEntity(world_mode);
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
        world_mode_module.endEntity(world_mode, entity, world_position);

        const array_x: usize = @intCast(offset_x + radius_x);
        const array_y: usize = @intCast(offset_y + radius_y);
        result.position[array_x][array_y] = world_position;
        result.ground[array_x][array_y] = standing_on;
    }

    {
        // Hole camera.
        const entity: *Entity = world_mode_module.beginGroundedEntity(world_mode);
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
        world_mode_module.endEntity(world_mode, entity, result.position[@intCast(-4 + radius_x)][@intCast(-1 + radius_y)]);
    }

    {
        // Stairs camera, on stairs.
        var entity: *Entity = world_mode_module.beginGroundedEntity(world_mode);
        entity.camera_behavior = @intFromEnum(CameraBehavior.ViewPlayer);
        var x_dim: f32 = 0.5 * tile_side_in_meters;
        var y_dim: f32 = 1.5 * tile_side_in_meters;
        entity.collision_volume = .fromMinMax(
            .new(-x_dim, -y_dim, -0.5 * world_mode.typical_floor_height),
            .new(x_dim, y_dim, 0.3 * world_mode.typical_floor_height),
        );
        world_mode_module.endEntity(world_mode, entity, stair_positions[2]);

        // Stairs camera, at top of stairs.
        entity = world_mode_module.beginGroundedEntity(world_mode);
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
        world_mode_module.endEntity(world_mode, entity, stair_positions[0]);
    }

    const room_position = world_mode_module.chunkPositionFromTilePosition(
        world_mode.world,
        abs_tile_x,
        abs_tile_y,
        abs_tile_z,
        null,
    );

    const room: *Entity = world_mode_module.beginGroundedEntity(world_mode);
    room.collision_volume = world_mode_module.makeSimpleGroundedCollision(
        @as(f32, @floatFromInt((2 * radius_x + 1))) * tile_side_in_meters,
        @as(f32, @floatFromInt((2 * radius_y + 1))) * tile_side_in_meters,
        world_mode.typical_floor_height,
        0,
    );

    room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
    world_mode_module.endEntity(world_mode, room, room_position);

    const world_room: *WorldRoom = world_module.addWorldRoom(
        world_mode.world,
        world_mode_module.chunkPositionFromTilePosition(
            world_mode.world,
            abs_tile_x - radius_x,
            abs_tile_y - radius_y,
            abs_tile_z,
            null,
        ),
        world_mode_module.chunkPositionFromTilePosition(
            world_mode.world,
            abs_tile_x + radius_x,
            abs_tile_y + radius_y,
            abs_tile_z + 1,
            null,
        ),
        .FocusOnRoom,
    );
    _ = world_room;

    return result;
}

fn addWall(world_mode: *GameModeWorld, world_position: WorldPosition, standing_on: TraversableReference) void {
    const entity = world_mode_module.beginGroundedEntity(world_mode);

    entity.collision_volume = world_mode_module.makeSimpleGroundedCollision(
        tile_side_in_meters,
        tile_side_in_meters,
        world_mode.typical_floor_height - 0.1,
        0,
    );

    entity.addFlags(EntityFlags.Collides.toInt());
    entity.occupying = standing_on;
    entity.addPiece(.Tree, 2.5, .zero(), .white(), null);

    world_mode_module.endEntity(world_mode, entity, world_position);
}

fn addStairs(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) void {
    const world_position = world_mode_module.chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
    const entity = world_mode_module.beginGroundedEntity(world_mode);

    entity.collision_volume = world_mode_module.makeSimpleGroundedCollision(
        tile_side_in_meters,
        tile_side_in_meters * 2.0,
        world_mode.typical_floor_height * 1.1,
        0,
    );
    entity.walkable_dimension = entity.collision_volume.getDimension().xy();
    entity.walkable_height = world_mode.typical_floor_height;
    entity.addFlags(EntityFlags.Collides.toInt());

    world_mode_module.endEntity(world_mode, entity, world_position);
}
