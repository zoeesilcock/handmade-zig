const math = @import("math.zig");
const sim = @import("sim.zig");
const box = @import("box.zig");
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
const CameraBehavior = entities.CameraBehavior;
const World = world_mod.World;
const WorldPosition = world_mod.WorldPosition;
const WorldGenerator = world_gen.WorldGenerator;
const GenRoom = world_gen.GenRoom;
const GenRoomSpec = world_gen.GenRoomSpec;
const GenVector3 = gen_math.GenVector3;
const GenVolume = gen_math.GenVolume;
const GenRoomConnection = world_gen.GenRoomConnection;
const GenConnection = world_gen.GenConnection;
const GenEntity = entity_gen.GenEntity;
const GenEntityTag = entity_gen.GenEntityTag;
const GenEntityFlag = entity_gen.GenEntityFlag;
const GenEntityGroup = entity_gen.GenEntityGroup;
const BrainSlot = brains.BrainSlot;
const BoxSurfaceIndex = box.BoxSurfaceIndex;

const X = 0;
const Y = 1;
const Z = 2;
const BOX_SURFACE_INDEX_COUNT = box.BOX_SURFACE_INDEX_COUNT;

pub const GenRoomTileQuery = struct {
    found: bool = false,
    volume: GenVolume = .zero(),
};

const GenRoomTile = struct {
    open: bool,
    structural: ?*Entity,
};

const GenRoomGrid = struct {
    dimension: GenVector3,

    tiles: [*]GenRoomTile,

    pub fn findPlaceToPutEntityGroup(self: *GenRoomGrid, entity_group: *GenEntityGroup) GenRoomTileQuery {
        var result: GenRoomTileQuery = .{};

        var z: i32 = 0;
        while (z < self.dimension[2]) : (z += 1) {
            var y: i32 = 0;
            while (y < self.dimension[1]) : (y += 1) {
                var x: i32 = 0;
                while (x < self.dimension[0]) : (x += 1) {
                    const tile_position: GenVector3 = .{ x, y, z };
                    if (self.recursiveOpenTileSearch(tile_position, entity_group.first_entity.?)) {
                        result.found = true;
                        result.volume.min = tile_position;
                        result.volume.max = tile_position;

                        break;
                    }
                }
            }
        }

        return result;
    }

    fn recursiveOpenTileSearch(
        self: *GenRoomGrid,
        tile_position: GenVector3,
        entity: *GenEntity,
    ) bool {
        var result: bool = false;

        if (self.getTileFromV3(tile_position)) |tile| {
            if (tile.open) {
                std.debug.assert(tile.structural != null);
                tile.open = false;

                if (entity.next) |next_entity| {
                    var direction: u32 = 0;
                    while (direction < BOX_SURFACE_INDEX_COUNT) : (direction += 1) {
                        const direction_index: BoxSurfaceIndex = @enumFromInt(direction);
                        const mask: u32 = box.getSurfaceMaskFromSurface(direction_index);
                        if ((entity.allowed_directions_for_next & mask) != 0) {
                            const next_tile_delta: GenVector3 = gen_math.getDirection(direction_index);
                            if (self.recursiveOpenTileSearch(
                                gen_math.plusV3(tile_position, next_tile_delta),
                                next_entity,
                            )) {
                                entity.next_direction_used = direction_index;
                                result = true;
                                break;
                            }
                        }
                    }
                } else {
                    result = true;
                }

                if (!result) {
                    tile.open = true;
                }
            }
        }

        return result;
    }

    fn getTile(self: *GenRoomGrid, x_index: i32, y_index: i32, z_index: i32) ?*GenRoomTile {
        var result: ?*GenRoomTile = null;
        const dimension: GenVector3 = self.dimension;

        if (x_index >= 0 and
            y_index >= 0 and
            z_index >= 0 and
            x_index < dimension[0] and
            y_index < dimension[1] and
            z_index < dimension[2])
        {
            result = @ptrCast(self.tiles + @as(usize, @intCast(
                (dimension[0] * dimension[1] * z_index) +
                    (dimension[0] * y_index) +
                    x_index,
            )));
        }

        return result;
    }

    fn getTileFromV3(self: *GenRoomGrid, position: GenVector3) ?*GenRoomTile {
        return self.getTile(position[0], position[1], position[2]);
    }
};

fn getCameraOffsetZForDimension(x_count: i32, y_count: i32, camera_behaviour: *u32) f32 {
    var x_distance: f32 = 13;
    if (x_count == 12) {
        x_distance = 14;
    } else if (x_count == 13) {
        x_distance = 15;
    } else if (x_count == 14) {
        x_distance = 16;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerX);
    } else if (x_count >= 15) {
        x_distance = 17;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerX);
    }

    var y_distance: f32 = 13;
    if (y_count == 10) {
        y_distance = 15;
    } else if (y_count == 11) {
        y_distance = 17;
    } else if (y_count == 12) {
        y_distance = 19;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerY);
    } else if (y_count >= 13) {
        y_distance = 21;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerY);
    }

    const result: f32 = @max(x_distance, y_distance);

    return result;
}

pub fn generateRoom(gen: *WorldGenerator, world: *World, room: *GenRoom) void {
    const spec: *GenRoomSpec = room.spec;
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

    var grid: *GenRoomGrid = gen.temp_memory.pushStruct(GenRoomGrid, null);
    grid.dimension = dimension;
    grid.tiles = gen.temp_memory.pushArray(@intCast(dimension[0] * dimension[1] * dimension[2]), GenRoomTile, null);

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
            const z_index: i32 = 0;
            var tile: *GenRoomTile = grid.getTile(x_index, y_index, z_index).?;

            const tile_x: i32 = min_tile_x + x_index;
            const tile_y: i32 = min_tile_y + y_index;
            // const tile_z: i32 = floor_tile_z;

            var on_boundary: bool =
                x_index == 0 or
                x_index == (x_count - 1) or
                y_index == 0 or
                y_index == (y_count - 1);

            if (spec.outdoors) {
                on_boundary = false;
            }

            var t_stair: f32 = 0;
            var on_connection: bool = false;
            var stairwell: bool = false;

            var opt_room_connection: ?*GenRoomConnection = room.first_connection;
            while (opt_room_connection) |room_connection| : (opt_room_connection = room_connection.next) {
                const connection: *GenConnection = room_connection.connection;
                if (connection.volume.isInVolume(tile_x, tile_y, floor_tile_z)) {
                    if (room_connection.placed_direction == .Up or
                        room_connection.placed_direction == .Down)
                    {
                        stairwell = true;
                        t_stair =
                            @as(f32, @floatFromInt(tile_y - connection.volume.min[1] + 1)) /
                            @as(f32, @floatFromInt(connection.volume.max[1] - connection.volume.min[1] + 2));
                    }
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

            var on_lamp: bool =
                (x_index == 1 and y_index == 1) or
                (x_index == 1 and y_index == y_count - 2) or
                (x_index == x_count - 2 and y_index == 1) or
                (x_index == x_count - 2 and y_index == y_count - 2);

            on_lamp = false;

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
                if (spec.outdoors) {
                    entity.addTag(.Grass, 1);
                } else {
                    entity.addTag(if (spec.stone_floor) .Stone else .Wood, 1);
                }
                randomize_top = true;

                if (!on_lamp) {
                    entity.traversable_count = 1;
                    entity.traversables[0].position = Vector3.zero();
                    entity.traversables[0].occupier = null;
                }
            }

            entity.addTag(.Manmade, 1);

            _ = position.offset.setX(position.offset.x() + 0);
            _ = position.offset.setY(position.offset.y() + 0);
            _ = position.offset.setZ(position.offset.z() + wall_height + 0.5 * series.randomUnilateral());

            if (stairwell) {
                _ = position.offset.setZ(position.offset.z() - (t_stair * tile_dimension.z()));
            }

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
            tile.structural = entity;
            tile.open = (!stairwell and entity.traversable_count == 1);
        }
    }

    var opt_entity_group: ?*GenEntityGroup = room.first_entity_group;
    while (opt_entity_group) |entity_group| : (opt_entity_group = entity_group.next) {
        const query: GenRoomTileQuery = grid.findPlaceToPutEntityGroup(entity_group);
        std.debug.assert(query.found);

        var tile_position: GenVector3 = query.volume.min;

        var opt_pending_entity: ?*GenEntity = entity_group.first_entity;
        while (opt_pending_entity) |pending_entity| : (opt_pending_entity = pending_entity.next) {
            const tile: *GenRoomTile = grid.getTileFromV3(tile_position).?;
            var ref: TraversableReference = .init;
            var ground_position: Vector3 = .zero();
            if (tile.structural) |structural| {
                ref.entity.ptr = structural;
                ref.entity.index = structural.id;
                ground_position = ref.getSimSpaceTraversable().position;
            } else {
                unreachable;
            }

            const placed_entity: *Entity = pending_entity.creator(region, ground_position, ref);
            var tag_index: u32 = 0;
            while (tag_index < pending_entity.tag_count) : (tag_index += 1) {
                const tag: *GenEntityTag = &pending_entity.tags[tag_index];
                placed_entity.addTag(tag.tag_id, tag.value);
            }

            tile_position = gen_math.plusV3(tile_position, gen_math.getDirection(pending_entity.next_direction_used));
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
    _ = camera_room.camera_offset.setZ(getCameraOffsetZForDimension(x_count, y_count, &camera_room.camera_behavior));
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
