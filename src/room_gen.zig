const math = @import("math.zig");
const shared = @import("shared.zig");
const sim = @import("sim.zig");
const gen_math = @import("gen_math.zig");
const world_gen = @import("world_gen.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
const world_mod = @import("world.zig");
const world_mode_mod = @import("world_mode.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Color = math.Color;
const Rectangle3 = math.Rectangle3;
const SimRegion = sim.SimRegion;
const Entity = entities.Entity;
const EntityId = entities.EntityId;
const EntityVisiblePiece = entities.EntityVisiblePiece;
const EntityVisiblePieceFlag = entities.EntityVisiblePieceFlag;
const EntityFlags = entities.EntityFlags;
const TraversableReference = entities.TraversableReference;
const World = world_mod.World;
const WorldPosition = world_mod.WorldPosition;
const WorldGenerator = world_gen.WorldGenerator;
const GenRoom = world_gen.GenRoom;
const GenVolume = gen_math.GenVolume;
const GenVector3 = gen_math.GenVector3;
const GenRoomConnection = world_gen.GenRoomConnection;
const GenConnection = world_gen.GenConnection;
const Brain = brains.Brain;
const BrainId = brains.BrainId;
const BrainSlot = brains.BrainSlot;
const BrainHero = brains.BrainHero;
const BrainSnake = brains.BrainSnake;
const BrainMonster = brains.BrainMonster;
const BrainFamiliar = brains.BrainFamiliar;

const tile_side_in_meters: f32 = 1.4;
pub const shadow_alpha = 0.5;
const X = 0;
const Y = 1;
const Z = 2;

pub fn generateRoom(gen: *WorldGenerator, world: *World, room: *GenRoom) void {
    const dimension: GenVector3 = room.volume.getDimension();
    const min_tile_x: i32 = room.volume.min[X];
    const x_count: i32 = dimension[X];
    const min_tile_y: i32 = room.volume.min[Y];
    const y_count: i32 = dimension[Y];
    const min_tile_z: i32 = room.volume.min[Z];
    const z_count: i32 = dimension[Z];
    const floor_tile_z: i32 = min_tile_z;

    const tile_depth_in_meters = world.chunk_dimension_in_meters.z();

    var series = &world.game_entropy;

    const change_center: WorldPosition =
        chunkPositionFromTilePosition(
            world,
            min_tile_x + @divFloor(x_count, 2),
            min_tile_y + @divFloor(y_count, 2),
            min_tile_z + @divFloor(z_count, 2),
            null,
        );
    const change_rectangle: Rectangle3 = .fromCenterDimension(
        .zero(),
        .new(
            tile_side_in_meters * @as(f32, @floatFromInt(x_count + 8)),
            tile_side_in_meters * @as(f32, @floatFromInt(y_count + 8)),
            tile_depth_in_meters * @as(f32, @floatFromInt(z_count + 4)),
        ),
    );

    const change_memory = gen.temp_memory.beginTemporaryMemory();
    defer gen.temp_memory.endTemporaryMemory(change_memory);

    const region: *SimRegion = sim.beginWorldChange(
        &gen.temp_memory,
        world,
        change_center,
        change_rectangle,
        0,
    );

    var y_index: i32 = 0;
    while (y_index < y_count) : (y_index += 1) {
        var x_index: i32 = 0;
        while (x_index < x_count) : (x_index += 1) {
            const tile_x: i32 = min_tile_x + x_index;
            const tile_y: i32 = min_tile_y + y_index;

            const on_boundary: bool =
                x_index == 0 or
                x_index == (x_count - 1) or
                y_index == 0 or
                y_index == (y_count - 1);
            var on_connection: bool = false;

            var opt_room_connection: ?*GenRoomConnection = room.first_connection;
            while (opt_room_connection) |room_connection| : (opt_room_connection = room_connection.next) {
                const connection: *GenConnection = room_connection.connection;
                if (connection.volume.isInVolume(tile_x, tile_y, floor_tile_z)) {
                    on_connection = true;
                }
            }

            var position: WorldPosition = chunkPositionFromTilePosition(
                world,
                tile_x,
                tile_y,
                floor_tile_z,
                null,
            );

            const entity: *Entity = addEntity(region);

            var color: Color = .newFromSRGB(0.31, 0.49, 0.32, 1);
            var wall_height: f32 = 0.5;

            if (on_connection) {
                color = .newFromSRGB(0.21, 0.29, 0.42, 1);
            }

            if (on_boundary and !on_connection) {
                wall_height = 2;
                color = .newFromSRGB(0.5, 0.2, 0.2, 1);
            } else {
                entity.traversable_count = 1;
                entity.traversables[0].position = Vector3.zero();
                entity.traversables[0].occupier = null;
            }

            _ = position.offset.setX(position.offset.x() + 0);
            _ = position.offset.setY(position.offset.y() + 0);
            _ = position.offset.setZ(position.offset.z() + wall_height + 0.5 * series.randomUnilateral());

            entity.addPieceV2(
                .Grass,
                .new(0.7, wall_height),
                .zero(),
                color,
                @intFromEnum(EntityVisiblePieceFlag.Cube),
            );

            placeEntity(region, entity, position);
        }
    }

    const camera_room: *Entity = addEntity(region);
    camera_room.collision_volume = makeSimpleGroundedCollision(
        @as(f32, @floatFromInt(x_count)) * tile_side_in_meters,
        @as(f32, @floatFromInt(y_count)) * tile_side_in_meters,
        @as(f32, @floatFromInt(z_count)) * tile_depth_in_meters,
        null,
    );

    camera_room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
    placeEntity(region, camera_room, change_center);

    const world_room: *world_mod.WorldRoom = world_mod.addWorldRoom(
        world,
        chunkPositionFromTilePosition(
            world,
            min_tile_x,
            min_tile_y,
            min_tile_z,
            null,
        ),
        chunkPositionFromTilePosition(
            world,
            min_tile_x + x_count,
            min_tile_y + y_count,
            min_tile_z + z_count,
            null,
        ),
        .FocusOnRoom,
    );
    _ = world_room;

    sim.endWorldChange(region);
}

pub fn addEntity(region: *SimRegion) *Entity {
    const entity: *Entity = sim.createEntity(region, sim.allocateEntityId(region));

    entity.x_axis = .new(1, 0);
    entity.y_axis = .new(0, 1);

    return entity;
}

pub fn placeEntity(region: *SimRegion, entity: *Entity, chunk_position: WorldPosition) void {
    entity.position = world_mod.subtractPositions(region.world, &chunk_position, &region.origin);
}

fn addMonster(region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) void {
    var entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainMonster, "body");
    entity.brain_id = sim.addBrain(region);
    entity.occupying = standing_on;

    initHitPoints(entity, 3);

    entity.addPiece(.Shadow, 4.5, .zero(), .new(1, 1, 1, 0.5), null);
    entity.addPiece(.Torso, 4.5, .zero(), .white(), null);

    placeEntity(region, entity, world_position);
}

fn addSnakeSegment(
    region: *SimRegion,
    world_position: WorldPosition,
    standing_on: TraversableReference,
    brain_id: BrainId,
    segment_index: u32,
) void {
    var entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forIndexedField(BrainSnake, "segments", segment_index);
    entity.brain_id = brain_id;
    entity.occupying = standing_on;

    initHitPoints(entity, 3);

    entity.addPiece(.Shadow, 1.5, .zero(), .new(1, 1, 1, 0.5), null);
    entity.addPiece(if (segment_index != 0) .Torso else .Head, 1.5, .zero(), .white(), null);
    entity.addPieceLight(0.1, .new(0, 0, 0.5), 1.0, .new(1, 1, 0));

    placeEntity(region, entity, world_position);
}

fn addFamiliar(region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) void {
    const entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainFamiliar, "head");
    entity.brain_id = sim.addBrain(region);
    entity.occupying = standing_on;

    entity.addPiece(.Shadow, 2.5, .zero(), .new(1, 1, 1, shadow_alpha), null);
    entity.addPiece(.Head, 2.5, .zero(), .white(), @intFromEnum(EntityVisiblePieceFlag.BobOffset));

    placeEntity(region, entity, world_position);
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

pub fn makeSimpleGroundedCollision(
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
    game_world: *World,
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

    const result = world_mod.mapIntoChunkSpace(game_world, base_position, offset);

    std.debug.assert(world_mod.isVector3Canonical(game_world, result.offset));

    return result;
}
