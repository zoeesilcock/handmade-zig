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
const Color3 = math.Color3;
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
const GenApron = world_gen.GenApron;
const GenApronSpec = world_gen.GenApronSpec;
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

pub fn getCameraOffsetZForCloseup() f32 {
    return 6;
}

fn getCameraOffsetZForDimension(dimension: GenVector3, camera_behaviour: *u32) f32 {
    var x_distance: f32 = 13;
    if (dimension[X] == 12) {
        x_distance = 14;
    } else if (dimension[X] == 13) {
        x_distance = 15;
    } else if (dimension[X] == 14) {
        x_distance = 16;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerX);
    } else if (dimension[X] >= 15) {
        x_distance = 17;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerX);
    }

    var y_distance: f32 = 13;
    if (dimension[Y] == 10) {
        y_distance = 15;
    } else if (dimension[Y] == 11) {
        y_distance = 17;
    } else if (dimension[Y] == 12) {
        y_distance = 19;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerY);
    } else if (dimension[Y] >= 13) {
        y_distance = 21;
        camera_behaviour.* |= @intFromEnum(CameraBehavior.ViewPlayerY);
    }

    const result: f32 = @max(x_distance, y_distance);

    return result;
}

pub fn generateRoom(gen: *WorldGenerator, world: *World, room: *GenRoom) void {
    const spec: *GenRoomSpec = room.spec;
    const tile_count: GenVector3 = room.volume.getDimension();
    const min_tile: GenVector3 = room.volume.min;

    const floor_tile_z: i32 = min_tile[Z];
    const tile_dimension: Vector3 = gen.tile_dimension;

    const change_base_position: WorldPosition = chunkPositionFromTilePositionV3(gen, min_tile, null);

    const room_dimensions: Vector3 = .new(
        @as(f32, @floatFromInt(tile_count[X])) * tile_dimension.x(),
        @as(f32, @floatFromInt(tile_count[Y])) * tile_dimension.y(),
        @as(f32, @floatFromInt(tile_count[Z])) * tile_dimension.z(),
    );
    const min_room_position: Vector3 = Vector3.new(tile_dimension.x(), tile_dimension.y(), 0).scaledTo(-0.5);
    const max_room_position: Vector3 = min_room_position.plus(room_dimensions);

    var series = &world.game_entropy;

    const change_rect: Rectangle3 =
        Rectangle3.fromMinMax(min_room_position, max_room_position).addRadius(tile_dimension);

    const change_memory = gen.temp_memory.beginTemporaryMemory();
    defer gen.temp_memory.endTemporaryMemory(change_memory);

    var grid: *GenRoomGrid = gen.temp_memory.pushStruct(GenRoomGrid, null);
    grid.dimension = tile_count;
    grid.tiles = gen.temp_memory.pushArray(@intCast(gen_math.getTotalVolume(tile_count)), GenRoomTile, null);

    const region: *SimRegion = sim.beginWorldChange(&gen.temp_memory, world, change_base_position, change_rect, 0);

    var y_index: i32 = 0;
    while (y_index < tile_count[Y]) : (y_index += 1) {
        var x_index: i32 = 0;
        while (x_index < tile_count[X]) : (x_index += 1) {
            var position: Vector3 = .new(
                tile_dimension.x() * @as(f32, @floatFromInt(x_index)),
                tile_dimension.y() * @as(f32, @floatFromInt(y_index)),
                0,
            );

            const z_index: i32 = 0;
            var tile: *GenRoomTile = grid.getTile(x_index, y_index, z_index).?;

            const tile_x: i32 = min_tile[X] + x_index;
            const tile_y: i32 = min_tile[Y] + y_index;
            // const tile_z: i32 = floor_tile_z;

            const on_edge: bool =
                x_index == 0 or
                x_index == (tile_count[X] - 1) or
                y_index == 0 or
                y_index == (tile_count[Y] - 1);
            var on_boundary = on_edge;

            var t_stair: f32 = 0;
            var on_connection: bool = false;
            var stairwell: bool = false;
            if (spec.outdoors) {
                on_boundary = false;
            }

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

            const entity: *Entity = entity_gen.addEntity(region);

            var color: Color = .newFromSRGB(0.31, 0.49, 0.32, 1);
            var wall_height: f32 = 0.5;

            if (on_connection) {
                color = .newFromSRGB(0.21, 0.29, 0.42, 1);
            }

            const place_tree: bool = spec.outdoors and !on_connection and on_edge;
            const on_lamp: bool = !spec.outdoors and (x_index == tile_count[X] - 2 and y_index == 1);
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

                entity.traversable_count = 1;
                entity.traversables[0].position = Vector3.zero();
                entity.traversables[0].occupier = null;
            }

            if (!spec.outdoors) {
                entity.addTag(.Manmade, 1);
            }

            _ = position.setX(position.x() + 0);
            _ = position.setY(position.y() + 0);
            _ = position.setZ(position.z() + wall_height + 0.5 * series.randomUnilateral());

            if (stairwell) {
                _ = position.setZ(position.z() - (t_stair * tile_dimension.z()));
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

            entity.position = position;
            tile.structural = entity;
            tile.open = (!stairwell and !on_connection and entity.traversable_count == 1);

            if (tile.open) {
                var ref: TraversableReference = .init;
                var ground_position: Vector3 = .zero();
                ref.entity.ptr = tile.structural;
                ref.entity.index = tile.structural.?.id;
                ground_position = ref.getSimSpaceTraversable().position;

                if (place_tree) {
                    const placed_entity: *Entity = entity_gen.addObstacle(region, ground_position, ref);
                    // placed_entity.addTag(.Tree, 1);
                    placed_entity.addTag(.Variant, series.randomUnilateral());
                    placed_entity.addTag(.DarkEnergy, series.randomUnilateral());
                    placed_entity.addTag(.Winter, series.randomUnilateral());
                    placed_entity.addTag(.Fall, series.randomUnilateral());
                    placed_entity.addTag(.Damaged, series.randomUnilateral());
                } else if (on_lamp) {
                    const placed_entity: *Entity = entity_gen.addObstacle(region, ground_position, ref);
                    placed_entity.addTag(.Lamp, 1);

                    const lamp_light: Color3 = .new(
                        series.randomFloatBetween(0.4, 0.7),
                        series.randomFloatBetween(0.4, 0.7),
                        0.5,
                    );
                    entity_gen.addLamp(region, position, lamp_light);
                }
            }
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

    const camera_room: *Entity = entity_gen.addEntity(region);
    camera_room.collision_volume = .fromMinMax(min_room_position, max_room_position);

    camera_room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
    _ = camera_room.camera_offset.setZ(getCameraOffsetZForDimension(tile_count, &camera_room.camera_behavior));
    camera_room.position = .new(0, 0, 0);

    const world_room: *world_mod.WorldRoom =
        world_mod.addWorldRoom(
            world,
            world_mod.mapIntoChunkSpace(world, change_base_position, min_room_position),
            world_mod.mapIntoChunkSpace(world, change_base_position, max_room_position),
        );
    _ = world_room;

    sim.endWorldChange(region);

    if (spec.apron) |apron_spec| {
        const apron: *GenApron = world_gen.genApron(gen, apron_spec);
        apron.volume = room.volume.addRadius(.{ 8, 8, 0 });
    }
}

pub fn generateApron(gen: *WorldGenerator, world: *World, apron: *GenApron) void {
    // const spec: *GenApronSpec = apron.spec;
    const dimension: GenVector3 = apron.volume.getDimension();
    const min_tile_x: i32 = apron.volume.min[X];
    const x_count: i32 = dimension[X];
    const min_tile_y: i32 = apron.volume.min[Y];
    const y_count: i32 = dimension[Y];
    const min_tile_z: i32 = apron.volume.min[Z];
    const z_count: i32 = dimension[Z];
    const floor_tile_z: i32 = min_tile_z;
    const tile_dimension: Vector3 = gen.tile_dimension;

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

    // var series = &world.game_entropy;

    var y_index: i32 = 0;
    while (y_index < y_count) : (y_index += 1) {
        var x_index: i32 = 0;
        while (x_index < x_count) : (x_index += 1) {
            const tile_x: i32 = min_tile_x + x_index;
            const tile_y: i32 = min_tile_y + y_index;
            // const tile_z: i32 = floor_tile_z;

            const wall_height: f32 = 0.5;
            const cube_position: Vector3 = .new(0, 0, -0.5 * wall_height);
            const cube_half_dimension: Vector3 = .new(0.7, 0.7, 0.5 * wall_height);
            const collision_region: Rectangle3 = .fromCenterHalfDimension(cube_position, cube_half_dimension);
            const query_region: Rectangle3 =
                .fromCenterHalfDimension(cube_position, cube_half_dimension.plus(.new(-0.1, -0.1, 0)));

            var world_position: WorldPosition = chunkPositionFromTilePosition(
                gen,
                tile_x,
                tile_y,
                floor_tile_z,
                null,
            );
            _ = world_position.offset.setZ(world_position.offset.z() + 0.5 * wall_height);
            const position: Vector3 = world_mod.subtractPositions(region.world, &world_position, &region.origin);

            if (!sim.overlappingEntitiesExist(region, query_region.offsetBy(position))) {
                var entity: *Entity = entity_gen.addEntity(region);
                entity.collision_volume = collision_region;
                const color: Color = .newFromSRGB(0.5, 0.5, 0.5, 1);
                const piece: *EntityVisiblePiece = entity_gen.addPieceV3(
                    entity,
                    .Block,
                    cube_half_dimension,
                    cube_position,
                    color,
                    @intFromEnum(EntityVisiblePieceFlag.Cube),
                );
                _ = piece;

                entity.addTag(.Floor, 1);
                entity.addTag(.Grass, 1);

                entity.position = position;
            }
        }
    }

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

pub fn chunkPositionFromTilePositionV3(
    gen: *WorldGenerator,
    abs_tile: GenVector3,
    opt_additional_offset: ?Vector3,
) WorldPosition {
    return chunkPositionFromTilePosition(gen, abs_tile[X], abs_tile[Y], abs_tile[Z], opt_additional_offset);
}
