const math = @import("math.zig");
const sim = @import("sim.zig");
const gen_math = @import("gen_math.zig");
const world_gen = @import("world_gen.zig");
const entities = @import("entities.zig");
const entity_gen = @import("entity_gen.zig");
const renderer = @import("renderer.zig");
const brains = @import("brains.zig");
const world_mod = @import("world.zig");
const edit_grid = @import("edit_grid.zig");
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
const EditGrid = edit_grid.EditGrid;
const EditTile = edit_grid.EditTile;
const EditTileContents = edit_grid.EditTileContents;
const GenRoomTileQuery = edit_grid.GenRoomTileQuery;

const X = 0;
const Y = 1;
const Z = 2;

const GenTileVolume = struct {
    base_position: WorldPosition,
    tile_coord: GenVector3,
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

fn addTreeTags(gen: *WorldGenerator, entity: *Entity) void {
    // entity.addTag(.Tree, 1);
    entity.addTag(.Variant, gen.entropy.randomUnilateral());
    entity.addTag(.DarkEnergy, 0); //gen.entropy.randomUnilateral());
    entity.addTag(.Winter, gen.entropy.randomUnilateral());
    entity.addTag(.Fall, 0); // gen.entropy.randomUnilateral());
    entity.addTag(.Damaged, 0); // gen.entropy.randomUnilateral());
}

pub fn generateRoom(gen: *WorldGenerator, room: *GenRoom) void {
    const spec: *GenRoomSpec = room.spec;

    const grid = EditGrid.beginGridEdit(gen, room.volume);

    var tile: EditTile = grid.iterateAsPlanarTiles();
    while (tile.isValid()) : (tile.advance()) {
        const abs_index: GenVector3 = tile.getAbsoluteIndex();
        var position: Vector3 = tile.getMinZCenterPosition();

        var contents: *EditTileContents = tile.getTile().?;

        const on_edge: bool = tile.isOnEdge();
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
            if (connection.volume.isInVolumeV3(abs_index)) {
                if (room_connection.placed_direction == .Up or
                    room_connection.placed_direction == .Down)
                {
                    stairwell = true;
                    t_stair =
                        @as(f32, @floatFromInt(abs_index[Y] - connection.volume.min[Y] + 1)) /
                        @as(f32, @floatFromInt(connection.volume.max[Y] - connection.volume.min[Y] + 2));
                }
                on_connection = true;
            }
        }

        const entity: *Entity = entity_gen.addEntity(grid.region);

        var color: Color = .newFromSRGB(0.31, 0.49, 0.32, 1);
        var wall_height: f32 = 0.5;

        if (on_connection) {
            color = .newFromSRGB(0.21, 0.29, 0.42, 1);
        }

        const place_tree: bool = spec.outdoors and !on_connection and on_edge;
        const on_lamp: bool = !spec.outdoors and
            (tile.relative_index[X] == grid.tile_count[X] - 2 and tile.relative_index[Y] == 1);
        var randomize_top: bool = false;
        var traversable: bool = false;
        const on_wall: bool = on_boundary and !on_connection;
        if (on_wall) {
            wall_height = 2;
            color = .newFromSRGB(0.5, 0.2, 0.2, 1);

            entity.addTag(.Wall, 1);
            entity.addTag(.Wood, 1);
        } else {
            entity.addTag(.Floor, 1);
            if (spec.outdoors) {
                entity.addTag(.Grass, 1);
                entity.ground_cover_specs[0].cover_type = .ThickGrass;
                entity.ground_cover_specs[0].density = 64;
            } else {
                entity.addTag(if (spec.stone_floor) .Stone else .Wood, 1);
            }
            randomize_top = true;
            traversable = true;
        }

        const volume: Rectangle3 = tile.getVolumeFromMinZ(wall_height).makeRelative(position);

        if (traversable) {
            entity.traversable_count = 1;
            entity.traversables[0].position = volume.getMaxZCenterPosition();
            entity.traversables[0].occupier = null;
        }

        if (!spec.outdoors) {
            entity.addTag(.Manmade, 1);
        }

        if (stairwell) {
            _ = position.setZ(position.z() - (t_stair * grid.tile_dimension.z()));
        }

        const basis_position: Vector3 = position;
        _ = position.setX(position.x() + 0);
        _ = position.setY(position.y() + 0);
        _ = position.setZ(position.z() + 0.5 * grid.series.randomUnilateral());

        color = .newFromSRGB(0.8, 0.8, 0.8, 1);
        var piece: *EntityVisiblePiece = entity_gen.addPieceV3(
            entity,
            .Block,
            volume.getRadius(),
            volume.getCenter(),
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
                grid.series.randomChoice(4),
                grid.series.randomChoice(4),
            );
        }

        entity.position = position;
        entity.collision_volume = volume;
        contents.structural = entity;
        contents.open = (!stairwell and !on_connection and entity.traversable_count == 1);

        if (contents.open) {
            var ref: TraversableReference = .init;
            ref.entity = contents.structural.?.id;
            // const ground_position = ref.getSimSpaceTraversable(grid.region).position;

            if (place_tree) {
                const placed_entity: *Entity =
                    entity_gen.genEntityAtTraversable(grid.region, &entity_gen.addObstacle, ref);
                addTreeTags(gen, placed_entity);
            } else if (on_lamp) {
                const placed_entity: *Entity =
                    entity_gen.genEntityAtTraversable(grid.region, &entity_gen.addObstacle, ref);
                placed_entity.addTag(.Lamp, 1);

                const lamp_light: Color3 = .new(
                    grid.series.randomFloatBetween(0.4, 0.7),
                    grid.series.randomFloatBetween(0.4, 0.7),
                    0.5,
                );
                entity_gen.addLamp(grid.region, position, lamp_light);
            }
        }

        if (!on_wall) {
            _ = entity_gen.addLightProbe(grid.region, basis_position.plus(.new(0, 0, 0.25 * grid.tile_dimension.z())));
            _ = entity_gen.addLightProbe(grid.region, basis_position.plus(.new(0, 0, 0.5 * grid.tile_dimension.z())));
        }
    }

    var opt_entity_group: ?*GenEntityGroup = room.first_entity_group;
    while (opt_entity_group) |entity_group| : (opt_entity_group = entity_group.next) {
        const query: GenRoomTileQuery = grid.findPlaceToPutEntityGroup(entity_group);
        std.debug.assert(query.found);

        var tile_position: GenVector3 = query.volume.min;

        var opt_pending_entity: ?*GenEntity = entity_group.first_entity;
        while (opt_pending_entity) |pending_entity| : (opt_pending_entity = pending_entity.next) {
            const contents: *EditTileContents = grid.getTileFromV3(tile_position).?;
            var ref: TraversableReference = .init;
            if (contents.structural) |structural| {
                ref.entity = structural.id;
            } else {
                unreachable;
            }

            const placed_entity: *Entity = entity_gen.genEntityAtTraversable(grid.region, pending_entity.creator, ref);
            var tag_index: u32 = 0;
            while (tag_index < pending_entity.tag_count) : (tag_index += 1) {
                const tag: *GenEntityTag = &pending_entity.tags[tag_index];
                placed_entity.addTag(tag.tag_id, tag.value);
            }

            tile_position = gen_math.plusV3(tile_position, gen_math.getDirection(pending_entity.next_direction_used));
        }
    }

    const camera_room: *Entity = entity_gen.addEntity(grid.region);
    camera_room.position = grid.getRoomVolume().getCenter();
    camera_room.collision_volume = grid.getRoomVolume().makeRelative(camera_room.position);

    camera_room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
    _ = camera_room.camera_offset.setZ(getCameraOffsetZForDimension(grid.tile_count, &camera_room.camera_behavior));

    const world_room: *world_mod.WorldRoom =
        world_mod.addWorldRoom(gen.world, grid.getRoomMinPosition(), grid.getRoomMaxPosition());
    _ = world_room;

    grid.endGridEdit();

    if (spec.apron) |apron_spec| {
        const apron: *GenApron = world_gen.genApron(gen, apron_spec);
        apron.volume = room.volume.addRadius(.{ 8, 8, 0 });
    }
}

pub fn generateApron(gen: *WorldGenerator, apron: *GenApron) void {
    const grid = EditGrid.beginGridEdit(gen, apron.volume);

    var tile: EditTile = grid.iterateAsPlanarTiles();
    while (tile.isValid()) : (tile.advance()) {
        const epsilon: f32 = 0.001;
        if (!sim.overlappingEntitiesExist(grid.region, tile.getTotalVolume().addRadius(.splat(-epsilon)))) {
            const position: Vector3 = tile.getMinZCenterPosition();
            const height: f32 = grid.series.randomFloatBetween(0.5, 1);
            const volume: Rectangle3 = tile.getVolumeFromMinZ(height).makeRelative(position);

            var entity: *Entity = entity_gen.addEntity(grid.region);
            entity.position = position;
            entity.collision_volume = volume;

            const color: Color = .newFromSRGB(0.5, 0.5, 0.5, 1);

            const piece: *EntityVisiblePiece = entity_gen.addPieceV3(
                entity,
                .Block,
                volume.getRadius(),
                volume.getCenter(),
                color,
                @intFromEnum(EntityVisiblePieceFlag.Cube),
            );
            _ = piece;

            entity.addTag(.Floor, 1);
            entity.addTag(.Grass, 1);

            entity.ground_cover_specs[0].cover_type = .ThickGrass;
            entity.ground_cover_specs[0].density = 64;

            const ground_position: Vector3 = position.plus(volume.getMaxZCenterPosition());
            if (grid.series.randomChoice(3) != 0) {
                const tree: *Entity =
                    entity_gen.genEntityAtPosition(grid.region, &entity_gen.addInanimate, ground_position);
                addTreeTags(gen, tree);
            }
        }
    }
    grid.endGridEdit();
}
