const math = @import("math.zig");
const sim = @import("sim.zig");
const gen_math = @import("gen_math.zig");
const world_gen = @import("world_gen.zig");
const entities = @import("entities.zig");
const entity_gen = @import("entity_gen.zig");
const renderer = @import("renderer.zig");
const brains = @import("brains.zig");
const world_mod = @import("world.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Color = math.Color;
const Rectangle3 = math.Rectangle3;
const SimRegion = sim.SimRegion;
const Entity = entities.Entity;
const EntityVisiblePiece = entities.EntityVisiblePiece;
const EntityVisiblePieceFlag = entities.EntityVisiblePieceFlag;
const TraversableReference = entities.TraversableReference;
const World = world_mod.World;
const WorldPosition = world_mod.WorldPosition;
const WorldGenerator = world_gen.WorldGenerator;
const GenRoom = world_gen.GenRoom;
const GenRoomSpec = world_gen.GenRoomSpec;
const GenVector3 = gen_math.GenVector3;
const GenRoomConnection = world_gen.GenRoomConnection;
const GenConnection = world_gen.GenConnection;
const GenEntity = entity_gen.GenEntity;
const GenEntityTag = entity_gen.GenEntityTag;
const BrainSlot = brains.BrainSlot;

const X = 0;
const Y = 1;
const Z = 2;

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
    const spec: *GenRoomSpec = room.spec;
    var pending_entity: ?*GenEntity = room.first_entity;
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

            const entity: *Entity = entity_gen.addEntity(region);

            var color: Color = .newFromSRGB(0.31, 0.49, 0.32, 1);
            var wall_height: f32 = 0.5;

            const on_lamp: bool =
                (x_index == 1 and y_index == 1) or
                (x_index == 1 and y_index == y_count - 2) or
                (x_index == x_count - 2 and y_index == 1) or
                (x_index == x_count - 2 and y_index == y_count - 2);

            if (on_lamp) {
                entity_gen.addLamp(
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

            var randomize_top: bool = false;
            if (on_boundary and !on_connection) {
                wall_height = 2;
                color = .newFromSRGB(0.5, 0.2, 0.2, 1);

                entity.addTag(.Wall, 1);
                entity.addTag(.Wood, 1);
            } else {
                entity.addTag(.Floor, 1);
                entity.addTag(if (spec.stone_floor) .Stone else .Wood, 1);
                randomize_top = true;

                if (!on_lamp) {
                    entity.traversable_count = 1;
                    entity.traversables[0].position = Vector3.zero();
                    entity.traversables[0].occupier = null;

                    if (pending_entity != null) {
                        var ref: TraversableReference = .init;
                        ref.entity.ptr = entity;
                        ref.entity.index = entity.id;

                        const placed_entity: *Entity = pending_entity.?.creator(region, position, ref);
                        var tag_index: u32 = 0;
                        while (tag_index < pending_entity.?.tag_count) : (tag_index += 1) {
                            const tag: *GenEntityTag = &pending_entity.?.tags[tag_index];
                            placed_entity.addTag(tag.tag_id, tag.value);
                        }

                        pending_entity = pending_entity.?.next;
                    }
                }
            }

            entity.addTag(.Manmade, 1);

            _ = position.offset.setX(position.offset.x() + 0);
            _ = position.offset.setY(position.offset.y() + 0);
            _ = position.offset.setZ(position.offset.z() + wall_height + 0.5 * series.randomUnilateral());

            color = .newFromSRGB(0.8, 0.8, 0.8, 1);
            var piece: *EntityVisiblePiece = entity_gen.addPieceV3(
                entity,
                .Block,
                .new(0.7, 0.7, 0.5 * wall_height),
                .new(0, 0, -0.5 * wall_height),
                color,
                @intFromEnum(EntityVisiblePieceFlag.Cube),
            );

            if (randomize_top) {
                piece.extra.cube_uv_layout = renderer.encodeCubeUVLayout(
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    series.randomChoice(4),
                    series.randomChoice(4),
                );
            }

            entity_gen.placeEntity(region, entity, position);
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

    const camera_room: *Entity = entity_gen.addEntity(region);
    camera_room.collision_volume = .fromMinMax(min_room_position, max_room_position);

    camera_room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
    _ = camera_room.camera_offset.setZ(getCameraOffsetZForDimension(x_count, y_count));
    entity_gen.placeEntity(region, camera_room, change_center);

    const world_room: *world_mod.WorldRoom =
        world_mod.addWorldRoom(world, min_room_world_position, max_room_world_position);
    _ = world_room;

    sim.endWorldChange(region);
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
