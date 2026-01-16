const math = @import("math.zig");
const shared = @import("shared.zig");
const sim = @import("sim.zig");
const gen_math = @import("gen_math.zig");
const world_gen = @import("world_gen.zig");
const entities = @import("entities.zig");
const asset = @import("asset.zig");
const brains = @import("brains.zig");
const world_mod = @import("world.zig");
const world_mode_mod = @import("world_mode.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Vector2 = math.Vector2;
const Color = math.Color;
const Color3 = math.Color3;
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

pub const shadow_alpha = 0.5;
const X = 0;
const Y = 1;
const Z = 2;

pub fn addPiece(
    entity: *Entity,
    asset_type: asset.AssetTypeId,
    height: f32,
    offset: Vector3,
    color: Color,
    opt_movement_flags: ?u32,
) void {
    addPieceV2(entity, asset_type, .new(0, height), offset, color, opt_movement_flags);
}

fn addPieceLight(
    entity: *Entity,
    radius: f32,
    offset: Vector3,
    emission: f32,
    color: Color3,
) void {
    addPieceV2(
        entity,
        .None,
        .new(radius, radius),
        offset,
        color.toColor(emission),
        @intFromEnum(EntityVisiblePieceFlag.Light),
    );
}

fn addPieceV2(
    entity: *Entity,
    asset_type: asset.AssetTypeId,
    dimension: Vector2,
    offset: Vector3,
    color: Color,
    opt_movement_flags: ?u32,
) void {
    std.debug.assert(entity.piece_count < entity.pieces.len);

    var piece: *EntityVisiblePiece = &entity.pieces[entity.piece_count];
    entity.piece_count += 1;

    piece.asset_type = asset_type;
    piece.dimension = dimension;
    piece.offset = offset;
    piece.color = color;
    piece.flags = opt_movement_flags orelse 0;
}

fn getCameraOffsetZForDimension(x_count: i32, y_count: i32) f32 {
    var x_distance: f32 = 10;
    if (x_count == 14) {
        x_distance = 11;
    } else if (x_count == 15) {
        x_distance = 12;
    } else if (x_count == 16) {
        x_distance = 13;
    } else if (x_count >= 17) {
        x_distance = 14;
    }

    var y_distance: f32 = 10;
    if (y_count == 10) {
        y_distance = 11;
    } else if (y_count == 11) {
        y_distance = 12;
    } else if (y_count == 12) {
        y_distance = 13;
    } else if (y_count >= 13) {
        y_distance = 14;
    }

    const result: f32 = @max(x_distance, y_distance);

    return result;
}

pub fn generateRoom(gen: *WorldGenerator, world: *World, room: *GenRoom) void {
    const dimension: GenVector3 = room.volume.getDimension();
    const min_tile_x: i32 = room.volume.min[X];
    const x_count: i32 = dimension[X];
    const min_tile_y: i32 = room.volume.min[Y];
    const y_count: i32 = dimension[Y];
    const min_tile_z: i32 = room.volume.min[Z];
    const z_count: i32 = dimension[Z];

    const floor_tile_z: i32 = min_tile_z;
    const tile_dimension: Vector3 = gen.tile_dimension;

    var series = &world.game_entropy;

    const change_center: WorldPosition =
        chunkPositionFromTilePosition(
            gen,
            min_tile_x + @divFloor(x_count, 2),
            min_tile_y + @divFloor(y_count, 2),
            min_tile_z + @divFloor(z_count, 2),
            null,
        );
    const change_rectangle: Rectangle3 = .fromCenterDimension(
        .zero(),
        .new(
            tile_dimension.x() * @as(f32, @floatFromInt(x_count + 8)),
            tile_dimension.y() * @as(f32, @floatFromInt(y_count + 8)),
            tile_dimension.z() * @as(f32, @floatFromInt(z_count + 4)),
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
                gen,
                tile_x,
                tile_y,
                floor_tile_z,
                null,
            );

            const entity: *Entity = addEntity(region);

            var color: Color = .newFromSRGB(0.31, 0.49, 0.32, 1);
            var wall_height: f32 = 0.5;

            const on_lamp: bool =
                (x_index == 1 and y_index == 1) or
                (x_index == 1 and y_index == y_count - 2) or
                (x_index == x_count - 2 and y_index == 1) or
                (x_index == x_count - 2 and y_index == y_count - 2);

            if (on_lamp) {
                addLamp(
                    region,
                    position,
                    .new(
                        series.randomFloatBetween(0.4, 0.7),
                        series.randomFloatBetween(0.4, 0.7),
                        0.5,
                    ),
                );
            }

            if (on_connection) {
                color = .newFromSRGB(0.21, 0.29, 0.42, 1);
            }

            if (on_boundary and !on_connection) {
                wall_height = 2;
                color = .newFromSRGB(0.5, 0.2, 0.2, 1);
            } else if (!on_lamp) {
                entity.traversable_count = 1;
                entity.traversables[0].position = Vector3.zero();
                entity.traversables[0].occupier = null;
            }

            _ = position.offset.setX(position.offset.x() + 0);
            _ = position.offset.setY(position.offset.y() + 0);
            _ = position.offset.setZ(position.offset.z() + wall_height + 0.5 * series.randomUnilateral());

            addPieceV2(
                entity,
                .Grass,
                .new(0.7, 0.5 * wall_height),
                .new(0, 0, -0.5 * wall_height),
                color,
                @intFromEnum(EntityVisiblePieceFlag.Cube),
            );

            placeEntity(region, entity, position);
        }
    }

    var half_tile_dimension: Vector3 = tile_dimension.scaledTo(0.5);
    _ = half_tile_dimension.setZ(0);
    const min_room_world_position: WorldPosition = chunkPositionFromTilePosition(
        gen,
        min_tile_x,
        min_tile_y,
        min_tile_z,
        half_tile_dimension.negated(),
    );
    const max_room_world_position: WorldPosition = chunkPositionFromTilePosition(
        gen,
        min_tile_x + x_count,
        min_tile_y + y_count,
        min_tile_z + z_count,
        half_tile_dimension.negated(),
    );

    const min_room_position: Vector3 = sim.mapIntoSimSpace(
        region,
        min_room_world_position,
    );
    const max_room_position: Vector3 = sim.mapIntoSimSpace(
        region,
        max_room_world_position,
    );

    const camera_room: *Entity = addEntity(region);
    camera_room.collision_volume = .fromMinMax(min_room_position, max_room_position);

    camera_room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
    _ = camera_room.camera_offset.setZ(getCameraOffsetZForDimension(x_count, y_count));
    placeEntity(region, camera_room, change_center);

    const world_room: *world_mod.WorldRoom =
        world_mod.addWorldRoom(world, min_room_world_position, max_room_world_position);
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

    addPiece(entity, .Shadow, 4.5, .zero(), .new(1, 1, 1, 0.5), null);
    addPiece(entity, .Torso, 4.5, .zero(), .white(), null);

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

    addPiece(entity, .Shadow, 1.5, .zero(), .new(1, 1, 1, 0.5), null);
    addPiece(entity, if (segment_index != 0) .Torso else .Head, 1.5, .zero(), .white(), null);
    addPieceLight(entity, 0.1, .new(0, 0, 0.5), 1.0, .new(1, 1, 0));

    placeEntity(region, entity, world_position);
}

fn addLamp(
    region: *SimRegion,
    world_position: WorldPosition,
    color: Color3,
) void {
    const entity = addEntity(region);

    addPieceLight(entity, 0.5, .new(0, 0, 2.5), 1.0, color);

    placeEntity(region, entity, world_position);
}

fn addFamiliar(region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) void {
    const entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainFamiliar, "head");
    entity.brain_id = sim.addBrain(region);
    entity.occupying = standing_on;

    addPiece(entity, .Shadow, 2.5, .zero(), .new(1, 1, 1, shadow_alpha), null);
    addPiece(entity, .Head, 2.5, .zero(), .white(), @intFromEnum(EntityVisiblePieceFlag.BobOffset));

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
    gen: *WorldGenerator,
    abs_tile_x: i32,
    abs_tile_y: i32,
    abs_tile_z: i32,
    opt_additional_offset: ?Vector3,
) WorldPosition {
    const additional_offset: Vector3 = opt_additional_offset orelse .zero();
    const base_position = WorldPosition.zero();
    const tile_dimension: Vector3 = gen.tile_dimension;
    var offset = Vector3.new(
        @floatFromInt(abs_tile_x),
        @floatFromInt(abs_tile_y),
        @floatFromInt(abs_tile_z),
    ).hadamardProduct(tile_dimension);
    const result = world_mod.mapIntoChunkSpace(gen.world, base_position, offset.plus(additional_offset));

    std.debug.assert(world_mod.isVector3Canonical(gen.world, result.offset));

    return result;
}
