const math = @import("math.zig");
const gen_math = @import("gen_math.zig");
const entities = @import("entities.zig");
const sim = @import("sim.zig");
const random = @import("random.zig");
const memory = @import("memory.zig");
const world_mod = @import("world.zig");
const world_gen = @import("world_gen.zig");
const entity_gen = @import("entity_gen.zig");
const box = @import("box.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Vector3i = math.Vector3i;
const GenVolume = gen_math.GenVolume;
const Entity = entities.Entity;
const GenEntity = entity_gen.GenEntity;
const GenEntityGroup = entity_gen.GenEntityGroup;
const World = world_mod.World;
const WorldPosition = world_mod.WorldPosition;
const WorldGenerator = world_gen.WorldGenerator;
const SimRegion = sim.SimRegion;
const MemoryArena = memory.MemoryArena;
const TemporaryMemory = memory.TemporaryMemory;
const BoxSurfaceIndex = box.BoxSurfaceIndex;

const BOX_SURFACE_INDEX_COUNT = box.BOX_SURFACE_INDEX_COUNT;

pub const GenRoomTileQuery = struct {
    found: bool = false,
    volume: GenVolume = .zero(),
};

pub const EditTileContents = struct {
    open: bool,
    structural: ?*Entity,
};

pub const EditGrid = struct {
    temp_memory: TemporaryMemory,
    arena: *MemoryArena,

    tile_count: Vector3i,
    min_tile: Vector3i,
    tile_dimension: Vector3,
    base_position: WorldPosition,

    room_dim: Rectangle3,

    gen: *WorldGenerator,
    series: *random.Series,
    region: *SimRegion,
    tiles: [*]EditTileContents,

    pub fn beginGridEdit(gen: *WorldGenerator, volume: GenVolume) *EditGrid {
        const arena: *MemoryArena = &gen.temp_memory;
        const temp_memory: TemporaryMemory = arena.beginTemporaryMemory();

        var self: *EditGrid = arena.pushStruct(EditGrid, null, @src());

        self.gen = gen;
        self.arena = arena;
        self.temp_memory = temp_memory;
        self.tile_count = volume.getDimension();
        self.min_tile = volume.min;
        self.tile_dimension = gen.tile_dimension;
        self.series = &gen.world.game_entropy;

        const room_dimensions: Vector3 = .new(
            @as(f32, @floatFromInt(self.tile_count.x())) * self.tile_dimension.x(),
            @as(f32, @floatFromInt(self.tile_count.y())) * self.tile_dimension.y(),
            @as(f32, @floatFromInt(self.tile_count.z())) * self.tile_dimension.z(),
        );

        const min_room_position: Vector3 = .zero();
        const max_room_position: Vector3 = min_room_position.plus(room_dimensions);
        self.room_dim = .fromMinMax(min_room_position, max_room_position);

        self.base_position = chunkPositionFromTilePositionV3(gen, self.min_tile, null);

        const change_rect: Rectangle3 = self.room_dim.addRadius(self.tile_dimension.scaledTo(1));
        self.region = sim.beginWorldChange(arena, gen.world, gen.assets, self.base_position, change_rect, 0);

        self.tiles = arena.pushArray(
            @intCast(gen_math.getTotalVolume(self.tile_count)),
            EditTileContents,
            null,
            @src(),
        );

        return self;
    }

    pub fn endGridEdit(self: *EditGrid) void {
        sim.endWorldChange(self.region);
        self.arena.endTemporaryMemory(self.temp_memory);
    }

    pub fn iterateAsPlanarTiles(self: *EditGrid) EditTile {
        return .{
            .grid = self,
        };
    }

    pub fn findPlaceToPutEntityGroup(self: *EditGrid, entity_group: *GenEntityGroup) GenRoomTileQuery {
        var result: GenRoomTileQuery = .{};

        var z: i32 = 0;
        while (z < self.tile_count.z()) : (z += 1) {
            var y: i32 = 0;
            while (y < self.tile_count.y()) : (y += 1) {
                var x: i32 = 0;
                while (x < self.tile_count.x()) : (x += 1) {
                    const tile_position: Vector3i = .new(x, y, z);
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

    pub fn recursiveOpenTileSearch(
        self: *EditGrid,
        tile_position: Vector3i,
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
                            const next_tile_delta: Vector3i = gen_math.getDirection(direction_index);
                            if (self.recursiveOpenTileSearch(
                                tile_position.plus(next_tile_delta),
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

    pub fn getTileFromV3(self: *EditGrid, position: Vector3i) ?*EditTileContents {
        return self.getTile(position.x(), position.y(), position.z());
    }

    pub fn getTile(self: *EditGrid, x_index: i32, y_index: i32, z_index: i32) ?*EditTileContents {
        var result: ?*EditTileContents = null;
        const dimension: Vector3i = self.tile_count;

        if (x_index >= 0 and
            y_index >= 0 and
            z_index >= 0 and
            x_index < dimension.x() and
            y_index < dimension.y() and
            z_index < dimension.z())
        {
            result = @ptrCast(self.tiles +
                @as(usize, @intCast((dimension.x() * dimension.y() * z_index) + (dimension.x() * y_index) + x_index)));
        }

        return result;
    }

    pub fn getRoomVolume(self: *EditGrid) Rectangle3 {
        return self.room_dim;
    }

    pub fn getRoomMinPosition(self: *EditGrid) WorldPosition {
        return world_mod.mapIntoChunkSpace(self.gen.world, self.base_position, self.room_dim.min);
    }

    pub fn getRoomMaxPosition(self: *EditGrid) WorldPosition {
        return world_mod.mapIntoChunkSpace(self.gen.world, self.base_position, self.room_dim.max);
    }
};

pub const EditTile = struct {
    grid: *EditGrid,
    relative_index: Vector3i = .zero(),

    pub fn isValid(self: *EditTile) bool {
        return gen_math.isInArrayBounds(self.grid.tile_count, self.relative_index);
    }

    pub fn advance(self: *EditTile) void {
        _ = self.relative_index.setX(self.relative_index.x() + 1);
        if (self.relative_index.x() >= self.grid.tile_count.x()) {
            _ = self.relative_index.setX(0);
            _ = self.relative_index.setY(self.relative_index.y() + 1);
        }
    }

    pub fn getMinZCenterPosition(self: *EditTile) Vector3 {
        return self.getTotalVolume().getMinZCenterPosition();
    }

    pub fn getMaxZCenterPosition(self: *EditTile) Vector3 {
        return self.getTotalVolume().getMaxZCenterPosition();
    }

    pub fn getTotalVolume(self: *EditTile) Rectangle3 {
        var min_position: Vector3 = .new(
            @floatFromInt(self.relative_index.x()),
            @floatFromInt(self.relative_index.y()),
            @floatFromInt(self.relative_index.z()),
        );
        var max_position: Vector3 = min_position.plus(.new(1, 1, 1));

        min_position = self.grid.tile_dimension.hadamardProduct(min_position);
        max_position = self.grid.tile_dimension.hadamardProduct(max_position);

        return .fromMinMax(min_position, max_position);
    }

    pub fn getVolumeFromMinZ(self: *EditTile, height: f32) Rectangle3 {
        var result: Rectangle3 = self.getTotalVolume();
        _ = result.max.setZ(result.min.z() + height);
        return result;
    }

    pub fn getTile(self: *EditTile) ?*EditTileContents {
        return self.grid.getTileFromV3(self.relative_index);
    }

    pub fn getAbsoluteIndex(self: *EditTile) Vector3i {
        return self.grid.min_tile.plus(self.relative_index);
    }

    pub fn isOnEdge(self: *EditTile) bool {
        const position: Vector3i = self.relative_index;
        return position.x() == 0 or
            position.x() == (self.grid.tile_count.x() - 1) or
            position.y() == 0 or
            position.y() == (self.grid.tile_count.y() - 1);
    }
};

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
    abs_tile: Vector3i,
    opt_additional_offset: ?Vector3,
) WorldPosition {
    return chunkPositionFromTilePosition(gen, abs_tile.x(), abs_tile.y(), abs_tile.z(), opt_additional_offset);
}
