const math = @import("math.zig");
const shared = @import("shared.zig");
const random = @import("random.zig");
const gen_math = @import("gen_math.zig");
const room_gen = @import("room_gen.zig");
const entity_gen = @import("entity_gen.zig");
const box_mod = @import("box.zig");
const world_mod = @import("world.zig");
const world_mode_mod = @import("world_mode.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
const memory = @import("memory.zig");
const asset = @import("asset.zig");
const edit_grid = @import("edit_grid.zig");
const file_formats = @import("file_formats.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const World = world_mod.World;
const WorldPosition = world_mod.WorldPosition;
const GameModeWorld = world_mode_mod.GameModeWorld;
const Entity = entities.Entity;
const GenEntity = entity_gen.GenEntity;
const GenEntityTag = entity_gen.GenEntityTag;
const GenEntityGroup = entity_gen.GenEntityGroup;
const TraversableReference = entities.TraversableReference;
const CameraBehavior = entities.CameraBehavior;
const SimRegion = sim.SimRegion;
const BoxSurfaceMask = box_mod.BoxSurfaceMask;
const BoxSurfaceIndex = box_mod.BoxSurfaceIndex;
const GenVolume = gen_math.GenVolume;
const Vector3i = math.Vector3i;
const AssetTagId = file_formats.AssetTagId;
const Assets = asset.Assets;

pub const INTERNAL = @import("build_options").internal;

pub const WorldGenerator = struct {
    memory: memory.MemoryArena,
    temp_memory: memory.MemoryArena,

    world: *World,
    tile_dimension: Vector3,

    first_apron: ?*GenApron,
    first_room: ?*GenRoom,
    first_connection: ?*GenConnection,

    option_arrays: [GEN_OPTION_TYPE_COUNT]GenOptionArray,

    entropy: *random.Series,
    assets: *Assets,
};

const GenOption = struct {
    room: ?*GenRoom,
};

const GenOptionIterator = struct {
    room: ?*GenRoom = null,

    pub fn iterateOptions(gen: *WorldGenerator, option_type: GenOptionType) GenOptionIterator {
        var result: GenOptionIterator = .{};
        const array: *GenOptionArray = &gen.option_arrays[@intFromEnum(option_type)];
        if (array.option_count > 0) {
            array.option_count -= 1;
            result.room = array.options[array.option_count].room;
        }
        return result;
    }

    pub fn isValid(self: *GenOptionIterator) bool {
        return self.room != null;
    }

    pub fn advance(self: *GenOptionIterator) void {
        self.room = null;
    }

    pub fn finish(self: *GenOptionIterator) void {
        self.room = null;
    }
};

const GenOptionArray = struct {
    options: [*]GenOption,

    max_option_count: u32,
    option_count: u32,
};

const GEN_OPTION_TYPE_COUNT = @typeInfo(GenOptionType).@"enum".fields.len;
const GenOptionType = enum(u32) {
    None,
    Cat,
    Orphan,
};

pub const GenRoomSpec = struct {
    required_dimension: Vector3i,
    stone_floor: bool,
    outdoors: bool,
    apron: ?*GenApronSpec,
};

pub const GenApronSpec = struct {
    trees: bool,
};

pub const GenApron = struct {
    global_next: ?*GenApron,
    spec: *GenApronSpec,
    volume: GenVolume,
};

pub const GenRoom = struct {
    first_connection: ?*GenRoomConnection,
    global_next: ?*GenRoom,

    spec: *GenRoomSpec,
    options_picked: u64,

    volume: GenVolume,
    generation_index: u32,

    first_entity_group: ?*GenEntityGroup,

    debug_label: if (INTERNAL) []const u8 else void,

    pub fn getRoomConnectionTo(self: *GenRoom, to_room: *GenRoom) ?*GenRoomConnection {
        var result: ?*GenRoomConnection = null;

        var test_connection = self.first_connection;
        while (test_connection) |connection| : (test_connection = connection.next) {
            if (connection.connection.getOtherRoom(self) == to_room) {
                result = connection;
            }
        }

        return result;
    }
};

pub const GenRoomConnection = struct {
    connection: *GenConnection,
    next: ?*GenRoomConnection,

    placed_direction: BoxSurfaceIndex,

    pub fn getOtherRoom(self: *const GenRoomConnection, from_room: *GenRoom) *GenRoom {
        return self.connection.getOtherRoom(from_room);
    }
};

const GenDirectionMask = enum(u32) {};

pub const GenConnection = struct {
    direction_from_a_mask: u32, // Masks the connection direction relative to room a.

    a: *GenRoom,
    b: *GenRoom,

    global_next: ?*GenConnection,

    volume: GenVolume,

    pub fn getOtherRoom(self: *const GenConnection, from_room: *GenRoom) *GenRoom {
        var result: *GenRoom = self.a;

        if (self.a == from_room) {
            std.debug.assert(self.b != from_room);
            result = self.b;
        } else {
            std.debug.assert(self.b == from_room);
        }

        return result;
    }

    pub fn getDirectionMaskFromRoom(self: *const GenConnection, from: *GenRoom) u32 {
        var direction_mask: u32 = self.direction_from_a_mask;

        if (self.b == from) {
            direction_mask = BoxSurfaceMask.getComplement(direction_mask);
        } else {
            std.debug.assert(self.a == from);
        }

        return direction_mask;
    }

    pub fn couldGoDirection(self: *GenConnection, from: *GenRoom, dimension: u32, side: u32) bool {
        return self.couldGoDirectionByMask(from, box_mod.getSurfaceMask(dimension, side));
    }

    pub fn couldGoDirectionByMask(self: *GenConnection, from: *GenRoom, test_mask: u32) bool {
        const direction_mask: u32 = self.getDirectionMaskFromRoom(from);
        return (direction_mask & test_mask) != 0;
    }
};

const GenDungeon = struct {
    entrance_room: ?*GenRoom = null,
    exit_room: ?*GenRoom = null,
};

const GenForest = struct {
    exits: [4]?*GenRoom = @splat(null),
};

const GenOrphanage = struct {
    hero_bedroom: ?*GenRoom = null,
    forest_entrance: ?*GenRoom = null,
};

const GenResult = struct {
    initial_camera_position: WorldPosition,
};

pub const GenRoomStack = struct {
    memory: *memory.MemoryArena,

    first_free: ?*GenRoomStackEntry = null,
    top: ?*GenRoomStackEntry = null,

    pub fn pushRoom(self: *GenRoomStack, room: ?*GenRoom) void {
        std.debug.assert(room != null);

        if (self.first_free == null) {
            self.first_free = self.memory.pushStruct(GenRoomStackEntry, null, @src());
        }

        var entry: *GenRoomStackEntry = self.first_free.?;
        self.first_free = entry.prev;

        entry.room = room;
        entry.prev = self.top;
        self.top = entry;
    }

    pub fn pushConnectedRooms(self: *GenRoomStack, room: *GenRoom, generation_index: u32) void {
        var opt_room_connection: ?*GenRoomConnection = room.first_connection;
        while (opt_room_connection) |room_connection| : (opt_room_connection = room_connection.next) {
            const connection: *GenConnection = room_connection.connection;
            const other_room: *GenRoom = connection.getOtherRoom(room);

            if (other_room.generation_index != generation_index) {
                self.pushRoom(other_room);
            }
        }
    }

    pub fn popRoom(self: *GenRoomStack) ?*GenRoom {
        var result: ?*GenRoom = null;

        if (self.top) |popped| {
            result = popped.room;
            std.debug.assert(result != null);

            self.top = popped.prev;

            popped.prev = self.first_free;
            self.first_free = popped;
            popped.room = null;
        }

        return result;
    }

    pub fn hasEntries(self: *GenRoomStack) bool {
        return self.top != null;
    }
};

pub const GenRoomStackEntry = struct {
    room: ?*GenRoom,
    prev: ?*GenRoomStackEntry,
};

fn genSpec(gen: *WorldGenerator, apron_spec: ?*GenApronSpec) *GenRoomSpec {
    var spec: *GenRoomSpec = gen.memory.pushStruct(GenRoomSpec, .aligned(@alignOf(GenRoomSpec), true), @src());
    spec.apron = apron_spec;
    return spec;
}

fn genRoom(gen: *WorldGenerator, spec: *GenRoomSpec, label: []const u8) *GenRoom {
    var room: *GenRoom = gen.memory.pushStruct(GenRoom, .aligned(@alignOf(GenRoom), true), @src());
    room.spec = spec;

    if (INTERNAL) {
        room.debug_label = label;
    }

    room.global_next = gen.first_room;
    gen.first_room = room;

    return room;
}

fn genApronSpec(gen: *WorldGenerator) *GenApronSpec {
    const spec: *GenApronSpec = gen.memory.pushStruct(GenApronSpec, .aligned(@alignOf(GenApronSpec), true), @src());
    return spec;
}

pub fn genApron(gen: *WorldGenerator, spec: *GenApronSpec) *GenApron {
    var apron: *GenApron = gen.memory.pushStruct(GenApron, .aligned(@alignOf(GenApron), true), @src());

    apron.spec = spec;
    apron.global_next = gen.first_apron;
    gen.first_apron = apron;

    return apron;
}

fn addRoomConnection(gen: *WorldGenerator, room: *GenRoom, connection: *GenConnection) *GenRoomConnection {
    var room_connection: *GenRoomConnection = gen.memory.pushStruct(GenRoomConnection, null, @src());

    room_connection.connection = connection;
    room_connection.next = room.first_connection;

    room.first_connection = room_connection;

    return room_connection;
}

fn connectByMask(gen: *WorldGenerator, a: *GenRoom, b: *GenRoom, opt_direction_mask: ?u32) *GenConnection {
    const direction_mask: u32 = opt_direction_mask orelse @intFromEnum(box_mod.BoxSurfaceMask.Planar);
    var connection: *GenConnection = gen.memory.pushStruct(GenConnection, null, @src());

    connection.direction_from_a_mask = direction_mask;
    connection.a = a;
    connection.b = b;

    connection.global_next = gen.first_connection;
    gen.first_connection = connection;

    _ = addRoomConnection(gen, a, connection);
    _ = addRoomConnection(gen, b, connection);

    return connection;
}

fn connect(gen: *WorldGenerator, a: *GenRoom, direction: BoxSurfaceIndex, b: *GenRoom) *GenConnection {
    return connectByMask(gen, a, b, box_mod.getSurfaceMaskFromSurface(direction));
}

fn setSize(gen: *WorldGenerator, spec: *GenRoomSpec, dim_x: i32, dim_y: i32, opt_dim_z: ?i32) void {
    _ = gen;
    const dim_z: i32 = opt_dim_z orelse 1;

    spec.required_dimension = .new(dim_x, dim_y, dim_z);
}

fn addOption(gen: *WorldGenerator, room: *GenRoom, option_type: GenOptionType) *GenOption {
    const array: *GenOptionArray = &gen.option_arrays[@intFromEnum(option_type)];

    std.debug.assert(array.option_count <= array.max_option_count);

    if (array.option_count == array.max_option_count) {
        array.max_option_count += 100;
        const new_options: [*]GenOption = gen.memory.pushArray(array.max_option_count, GenOption, null, @src());
        _ = shared.copyArray(array.option_count, GenOption, array.options, new_options);
        array.options = new_options;
    }

    const result: *GenOption = &array.options[array.option_count];
    array.option_count += 1;
    result.room = room;

    return result;
}

fn beginWorldGen(world: *World, assets: *Assets) *WorldGenerator {
    const gen: *WorldGenerator = memory.bootstrapPushStruct(WorldGenerator, "memory", null, null, @src());
    gen.world = world;
    gen.assets = assets;

    const tile_side_in_meters: f32 = 1.4;
    const tile_depth_in_meters = world.chunk_dimension_in_meters.z();
    gen.tile_dimension = .new(
        tile_side_in_meters,
        tile_side_in_meters,
        tile_depth_in_meters,
    );

    return gen;
}

fn placeRoomInVolume(room: *GenRoom, volume: GenVolume) void {
    room.volume = volume;
}

fn placeRoom(
    gen: *WorldGenerator,
    world: *World,
    room: *GenRoom,
    min_volume: *GenVolume,
    max_volume: *GenVolume,
    initial_room_connection: ?*GenRoomConnection,
) bool {
    var result: bool = false;

    var opt_room_connection: ?*GenRoomConnection = initial_room_connection;
    while (opt_room_connection) |room_connection| : (opt_room_connection = room_connection.next) {
        const connection: *GenConnection = room_connection.connection;
        const other_room: *GenRoom = connection.getOtherRoom(room);

        if (other_room.generation_index == room.generation_index) {
            break;
        }
    }

    if (opt_room_connection) |room_connection| {
        const connection: *GenConnection = room_connection.connection;
        const other_room: *GenRoom = connection.getOtherRoom(room);
        const other_room_connection = room.getRoomConnectionTo(other_room);

        var dimension: u32 = 0;
        while (!result and dimension < 3) : (dimension += 1) {
            var side: u32 = 0;
            while (!result and side < 2) : (side += 1) {
                if (connection.couldGoDirection(other_room, dimension, side)) {
                    var new_min_volume: GenVolume = min_volume.*;
                    var new_max_volume: GenVolume = max_volume.*;

                    if (side == 1) {
                        new_min_volume.clipMin(dimension, other_room.volume.max[dimension] + 1);
                        new_min_volume.clipMax(dimension, other_room.volume.max[dimension] + 1);

                        new_max_volume.clipMin(dimension, other_room.volume.max[dimension] + 1);
                    } else {
                        new_min_volume.clipMax(dimension, other_room.volume.min[dimension] - 1);

                        new_max_volume.clipMin(dimension, other_room.volume.min[dimension] - 1);
                        new_max_volume.clipMax(dimension, other_room.volume.min[dimension] - 1);
                    }

                    var other_dimension: u32 = 0;
                    while (other_dimension < 3) : (other_dimension += 1) {
                        if (other_dimension != dimension) {
                            const interior_apron: i32 = if (other_dimension == 2) 0 else 4;

                            new_min_volume.clipMax(
                                other_dimension,
                                other_room.volume.max[other_dimension] - interior_apron,
                            );
                            new_max_volume.clipMin(
                                other_dimension,
                                other_room.volume.min[other_dimension] + interior_apron,
                            );
                        }
                    }

                    const test_volume: GenVolume = GenVolume.getMaxVolumeFor(new_min_volume, new_max_volume);
                    if (test_volume.isMinimumDimensionsForRoom()) {
                        result = placeRoom(gen, world, room, &new_min_volume, &new_max_volume, room_connection.next);

                        if (result) {
                            var door: GenVolume = room.volume.getIntersectionWith(&other_room.volume);
                            const door_at: i32 =
                                if (side == 1) room.volume.min[dimension] else other_room.volume.min[dimension];

                            door.min[dimension] = door_at - 1;
                            door.max[dimension] = door_at;

                            connection.volume = door;

                            room_connection.placed_direction =
                                box_mod.getSurfaceIndex(dimension, box_mod.getOtherSide(side));
                            other_room_connection.placed_direction =
                                box_mod.getSurfaceIndex(dimension, side);
                        }
                    }
                }
            }
        }
    } else {
        const max_allowed_dimension: [3]i32 = .{
            16, // * 3,
            9, // * 3,
            1,
        };

        result = true;

        var final_volume: GenVolume = .zero();
        for (0..3) |dimension| {
            var min: i32 = min_volume.min[dimension];
            var max: i32 = max_volume.max[dimension];

            if (((max - min) + 1) > max_allowed_dimension[dimension]) {
                max = min + max_allowed_dimension[dimension] - 1;
            }

            if (max < max_volume.min[dimension]) {
                max = max_volume.min[dimension];
                min = max - max_allowed_dimension[dimension] + 1;
            }

            if (min > min_volume.max[dimension]) {
                result = false;
            }

            final_volume.min[dimension] = min;
            final_volume.max[dimension] = max;
        }

        if (result) {
            placeRoomInVolume(room, final_volume);
        }
    }

    return result;
}

fn getDeltaLongAxisForClearPlacement(
    gen: *WorldGenerator,
    test_volume: *GenVolume,
    edge_axis: u32,
    generation_index: u32,
) i32 {
    _ = edge_axis;

    var result: i32 = 0;

    var opt_room: ?*GenRoom = gen.first_room;
    while (opt_room) |room| : (opt_room = room.global_next) {
        if (room.generation_index == generation_index) {
            const intersection: GenVolume = room.volume.getIntersectionWith(test_volume);

            if (intersection.hasVolume()) {
                // TODO: Actually return the amount to move.
                result = 1;
                break;
            }
        }
    }

    return result;
}

fn placeRoomAlongEdge(
    gen: *WorldGenerator,
    base_room: *GenRoom,
    connection: *GenConnection,
    surface_index: BoxSurfaceIndex,
    generation_index: u32,
) bool {
    std.debug.assert(connection.couldGoDirectionByMask(base_room, box_mod.getSurfaceMaskFromSurface(surface_index)));

    var add_radius: Vector3i = .zero();
    var relative_x_axis: u32 = 0;
    var relative_y_axis: u32 = 0;
    var relative_z_axis: u32 = 0;
    var relative_z_axis_min: bool = false;
    switch (surface_index) {
        .West => {
            relative_x_axis = 1;
            relative_y_axis = 2;
            relative_z_axis = 0;
            relative_z_axis_min = true;
        },
        .East => {
            relative_x_axis = 1;
            relative_y_axis = 2;
            relative_z_axis = 0;
            relative_z_axis_min = false;
        },
        .South => {
            relative_x_axis = 0;
            relative_y_axis = 2;
            relative_z_axis = 1;
            relative_z_axis_min = true;
        },
        .North => {
            relative_x_axis = 0;
            relative_y_axis = 2;
            relative_z_axis = 1;
            relative_z_axis_min = false;
        },
        .Down => {
            relative_x_axis = 0;
            relative_y_axis = 1;
            relative_z_axis = 2;
            relative_z_axis_min = true;
            add_radius = .new(1, 1, 0);
        },
        .Up => {
            relative_x_axis = 0;
            relative_y_axis = 1;
            relative_z_axis = 2;
            relative_z_axis_min = false;
            add_radius = .new(1, 1, 0);
        },
    }

    const room: *GenRoom = connection.getOtherRoom(base_room);
    std.debug.assert(room.generation_index != generation_index);
    const spec: *GenRoomSpec = room.spec;

    var test_volume: GenVolume = .zero();

    if (relative_z_axis_min) {
        test_volume.max.setValueAt(relative_z_axis, base_room.volume.min.valueAt(relative_z_axis) - 1);
        test_volume.min.setValueAt(
            relative_z_axis,
            test_volume.max.valueAt(relative_z_axis) - spec.required_dimension.valueAt(relative_z_axis) + 1,
        );
    } else {
        test_volume.min.setValueAt(relative_z_axis, base_room.volume.max.valueAt(relative_z_axis) + 1);
        test_volume.max.setValueAt(
            relative_z_axis,
            test_volume.min.valueAt(relative_z_axis) + spec.required_dimension.valueAt(relative_z_axis) - 1,
        );
    }

    const min_relative_x: i32 = base_room.volume.min.valueAt(relative_x_axis);
    const max_relative_x: i32 = base_room.volume.max.valueAt(relative_x_axis);

    const min_relative_y: i32 = base_room.volume.min.valueAt(relative_y_axis);
    const max_relative_y: i32 = base_room.volume.max.valueAt(relative_y_axis);

    var relative_y: i32 = min_relative_y;
    while (room.generation_index != generation_index and relative_y <= max_relative_y) {
        test_volume.min.setValueAt(relative_y_axis, relative_y);
        test_volume.max.setValueAt(relative_y_axis, relative_y + spec.required_dimension.valueAt(relative_y_axis) - 1);

        var relative_x: i32 = min_relative_x;
        while (relative_x < max_relative_x) {
            test_volume.min.setValueAt(relative_x_axis, relative_x);
            test_volume.max.setValueAt(
                relative_x_axis,
                relative_x + spec.required_dimension.valueAt(relative_x_axis) - 1,
            );

            const delta_x: i32 = getDeltaLongAxisForClearPlacement(
                gen,
                &test_volume,
                relative_x_axis,
                generation_index,
            );

            if (delta_x == 0) {
                room.generation_index = generation_index;
                room.volume = test_volume;

                var door: GenVolume = base_room.volume.getIntersectionWith(&room.volume);
                const door_edge_x: i32 = @divFloor(
                    door.min.valueAt(relative_x_axis) + door.max.valueAt(relative_x_axis),
                    2,
                );
                door.min.setValueAt(relative_x_axis, door_edge_x);
                door.max.setValueAt(relative_x_axis, door_edge_x);

                const door_edge_y: i32 = @divFloor(
                    door.min.valueAt(relative_y_axis) + door.max.valueAt(relative_y_axis),
                    2,
                );
                door.min.setValueAt(relative_y_axis, door_edge_y);
                door.max.setValueAt(relative_y_axis, door_edge_y);

                const min_door: i32 = door.min.valueAt(relative_z_axis);
                const max_door: i32 = door.max.valueAt(relative_z_axis);
                door.min.setValueAt(relative_z_axis, max_door);
                door.max.setValueAt(relative_z_axis, min_door);

                door = door.addRadius(add_radius);

                connection.volume = door;

                const room_connection = room.getRoomConnectionTo(base_room).?;
                const other_room_connection = base_room.getRoomConnectionTo(room).?;
                room_connection.placed_direction =
                    box_mod.getSurfaceIndex(relative_z_axis, box_mod.getOtherSide(@intFromBool(relative_z_axis_min)));
                other_room_connection.placed_direction =
                    box_mod.getSurfaceIndex(relative_z_axis, @intFromBool(relative_z_axis_min));

                break;
            } else {
                relative_x += delta_x;
            }
        }

        relative_y += 1;
    }

    const result: bool = room.generation_index == generation_index;
    return result;
}

fn getRandomDirectionFromMask(gen: *WorldGenerator, direction_mask: u32) BoxSurfaceIndex {
    var direction_count: u32 = 0;
    var directions: [6]BoxSurfaceIndex = undefined;
    var direction_index: u32 = 0;
    while (direction_index < directions.len) : (direction_index += 1) {
        if (direction_mask & (box_mod.getSurfaceMaskFromSurface(@enumFromInt(direction_index))) != 0) {
            directions[direction_count] = @enumFromInt(direction_index);
            direction_count += 1;
        }
    }

    std.debug.assert(direction_count > 0);

    const result: BoxSurfaceIndex = directions[gen.entropy.randomChoice(direction_count)];

    return result;
}

fn layout(gen: *WorldGenerator, start_at_room: *GenRoom) void {
    const change_memory = gen.temp_memory.beginTemporaryMemory();
    defer gen.temp_memory.endTemporaryMemory(change_memory);

    var stack: GenRoomStack = .{ .memory = &gen.temp_memory };
    const generation_index: u32 = 1;

    const first_room: *GenRoom = start_at_room;
    var volume: GenVolume = .{
        .min = .new(0, 0, 0),
        .max = .new(0, 0, 0),
    };

    _ = volume.max.setX(volume.min.x() + first_room.spec.required_dimension.x() - 1);
    _ = volume.max.setY(volume.min.y() + first_room.spec.required_dimension.y() - 1);
    _ = volume.max.setZ(volume.min.z() + first_room.spec.required_dimension.z() - 1);
    placeRoomInVolume(first_room, volume);
    first_room.generation_index = generation_index;
    stack.pushConnectedRooms(first_room, generation_index);

    while (stack.hasEntries()) {
        if (stack.popRoom()) |room| {
            if (room.generation_index != generation_index) {
                var opt_room_connection: ?*GenRoomConnection = room.first_connection;
                while (opt_room_connection) |room_connection| : (opt_room_connection = room_connection.next) {
                    const connection: *GenConnection = room_connection.connection;
                    const other_room: *GenRoom = connection.getOtherRoom(room);

                    if (other_room.generation_index == generation_index) {
                        if (room.generation_index != generation_index) {
                            var direction_mask: u32 = connection.getDirectionMaskFromRoom(other_room);

                            while (direction_mask > 0) {
                                const direction: BoxSurfaceIndex = getRandomDirectionFromMask(gen, direction_mask);
                                if (placeRoomAlongEdge(gen, other_room, connection, direction, generation_index)) {
                                    break;
                                } else {
                                    direction_mask &= ~box_mod.getSurfaceMaskFromSurface(direction);
                                }
                            }

                            std.debug.assert(room.generation_index == generation_index);
                        }
                    } else {
                        stack.pushRoom(other_room);
                    }
                }
            }
        }
    }
}

fn generateWorld(gen: *WorldGenerator) void {
    var opt_room: ?*GenRoom = gen.first_room;
    while (opt_room) |room| : (opt_room = room.global_next) {
        room_gen.generateRoom(gen, room);
    }

    var opt_apron: ?*GenApron = gen.first_apron;
    while (opt_apron) |apron| : (opt_apron = apron.global_next) {
        room_gen.generateApron(gen, apron);
    }
}

fn endWorldGen(gen: *WorldGenerator) void {
    world_mod.clearUnpackedEntityCache(gen.world);
    gen.temp_memory.clear();
    gen.memory.clear();
}

fn createDungeon(gen: *WorldGenerator, floor_count: i32) GenDungeon {
    var result: GenDungeon = .{};

    const dungeon_spec: *GenRoomSpec = genSpec(gen, null);
    setSize(gen, dungeon_spec, 17, 9, 1);

    var opt_room_above: ?*GenRoom = null;
    var floor_index: i32 = 0;
    while (floor_index < floor_count) : (floor_index += 1) {
        const temp = gen.temp_memory.beginTemporaryMemory();
        defer gen.temp_memory.endTemporaryMemory(temp);

        const floor_entrance_room: *GenRoom = genRoom(gen, dungeon_spec, "Floor Entrance");

        if (opt_room_above) |room_above| {
            _ = connect(gen, room_above, .Down, floor_entrance_room);
        } else {
            result.entrance_room = floor_entrance_room;
        }

        var prev_room: *GenRoom = floor_entrance_room;
        const path_count: i32 = gen.entropy.randomIntBetween(4 + @divFloor(floor_index, 2), 6 + floor_index);

        var chain: [*]*GenRoom = temp.arena.pushArray(@intCast(path_count), *GenRoom, null, @src());

        var path_index: u32 = 0;
        while (path_index < path_count) : (path_index += 1) {
            const room: *GenRoom = genRoom(gen, dungeon_spec, "Dungeon Path");
            chain[path_index] = room;

            _ = connectByMask(gen, prev_room, room, @intFromEnum(BoxSurfaceMask.Planar));
            prev_room = room;

            _ = placeSnake(gen, room);
        }

        // TODO: Need a utility here that removes path rooms when they are chosen, to avoid over-connecting a room
        // with special rooms.
        const shop: *GenRoom = genRoom(gen, dungeon_spec, "Shop");
        _ = connectByMask(
            gen,
            chain[gen.entropy.randomChoice(@intCast(path_count))],
            shop,
            @intFromEnum(BoxSurfaceMask.Planar),
        );

        const item_room: *GenRoom = genRoom(gen, dungeon_spec, "Item Room");
        _ = connectByMask(
            gen,
            chain[gen.entropy.randomChoice(@intCast(path_count))],
            item_room,
            @intFromEnum(BoxSurfaceMask.Planar),
        );

        const floor_exit_room: *GenRoom = genRoom(gen, dungeon_spec, "Floor Exit");
        _ = connectByMask(gen, prev_room, floor_exit_room, @intFromEnum(BoxSurfaceMask.Planar));

        opt_room_above = floor_exit_room;
    }

    result.exit_room = opt_room_above;

    return result;
}

fn createOrphanage(gen: *WorldGenerator) GenOrphanage {
    var result: GenOrphanage = .{};

    const apron_spec: *GenApronSpec = genApronSpec(gen);
    var garden_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    garden_spec.outdoors = true;
    var basic_forest_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    basic_forest_spec.outdoors = true;

    var bedroom_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    bedroom_spec.stone_floor = true;

    const save_slot_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    const main_room_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    const tailor_room_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    const kitchen_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    const vertical_hallway_spec: *GenRoomSpec = genSpec(gen, apron_spec);
    const horizontal_hallway_spec: *GenRoomSpec = genSpec(gen, apron_spec);

    const main_room: *GenRoom = genRoom(gen, main_room_spec, "Orphanage Main Room");
    const tailor_room: *GenRoom = genRoom(gen, tailor_room_spec, "Orphanage Tailor's Room");
    const kitchen: *GenRoom = genRoom(gen, kitchen_spec, "Orphanage Kitchen");
    const front_hall: *GenRoom = genRoom(gen, vertical_hallway_spec, "Orphanage Front Hallway");
    const back_hall: *GenRoom = genRoom(gen, horizontal_hallway_spec, "Orphanage Back Hallway");
    const bedroom_a: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom A");
    const bedroom_b: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom B");
    const bedroom_c: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom C");
    const bedroom_d: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom D");
    const hero_save_slot_a: *GenRoom = genRoom(gen, save_slot_spec, "Save Slot A");
    const hero_save_slot_b: *GenRoom = genRoom(gen, save_slot_spec, "Save Slot B");
    const hero_save_slot_c: *GenRoom = genRoom(gen, save_slot_spec, "Save Slot C");
    const garden: *GenRoom = genRoom(gen, garden_spec, "Orphanage Garden");
    const forest_path: *GenRoom = genRoom(gen, basic_forest_spec, "Orphanage Forest Path");
    const forest_entrance: *GenRoom = genRoom(gen, basic_forest_spec, "Orphanage ForestEntrance");
    // const side_alley: *GenRoom = genRoom(gen, basic_forest_spec, "Orphanage Side Alley");

    if (true) {
        const scenery = addEntity(gen, &entity_gen.addObstacle);
        _ = addTag(gen, scenery, .Chair, 1);
        _ = addTag(gen, scenery, .FacingDirection, 0.0 * math.TAU32);
        placeEntity(gen, scenery, main_room);
    }

    _ = addOption(gen, main_room, .Cat);
    // _ = addOption(gen, main_room, .Orphan);
    _ = addOption(gen, bedroom_a, .Cat);
    _ = addOption(gen, bedroom_a, .Orphan);
    _ = addOption(gen, bedroom_b, .Cat);
    _ = addOption(gen, bedroom_b, .Orphan);
    _ = addOption(gen, bedroom_c, .Cat);
    _ = addOption(gen, bedroom_c, .Orphan);
    _ = addOption(gen, bedroom_d, .Cat);
    _ = addOption(gen, bedroom_d, .Orphan);
    _ = addOption(gen, tailor_room, .Cat);
    _ = addOption(gen, tailor_room, .Orphan);
    _ = addOption(gen, kitchen, .Cat);
    _ = addOption(gen, kitchen, .Orphan);
    _ = addOption(gen, garden, .Orphan);

    setSize(gen, main_room_spec, 13, 13, null);
    setSize(gen, tailor_room_spec, 8, 6, null);
    setSize(gen, kitchen_spec, 8, 6, null);
    setSize(gen, vertical_hallway_spec, 5, 13, null);
    setSize(gen, bedroom_spec, 8, 6, null);
    setSize(gen, horizontal_hallway_spec, 13, 5, null);
    setSize(gen, save_slot_spec, 5, 6, null);
    setSize(gen, garden_spec, 13, 13, null);
    // setSize(gen, side_alley, 5, 13, null);
    setSize(gen, basic_forest_spec, 13, 13, null);

    _ = connect(gen, main_room, .North, forest_path);
    _ = connect(gen, main_room, .West, tailor_room);
    _ = connect(gen, main_room, .West, kitchen);
    _ = connect(gen, main_room, .South, front_hall);

    _ = connect(gen, front_hall, .East, bedroom_d);
    _ = connect(gen, front_hall, .East, bedroom_b);
    _ = connect(gen, front_hall, .West, bedroom_c);
    _ = connect(gen, front_hall, .West, bedroom_a);
    _ = connect(gen, front_hall, .South, back_hall);

    _ = connect(gen, back_hall, .South, hero_save_slot_a);
    _ = connect(gen, back_hall, .South, hero_save_slot_b);
    _ = connect(gen, back_hall, .South, hero_save_slot_c);
    _ = connect(gen, back_hall, .East, garden);

    // _ = connect(gen, garden, .North, side_alley);
    // _ = connect(gen, side_alley, .North, forest_path);
    _ = connect(gen, forest_path, .North, forest_entrance);

    result.hero_bedroom = hero_save_slot_a;
    result.forest_entrance = forest_entrance;

    return result;
}

fn addEntity(gen: *WorldGenerator, creator: *const entity_gen.CreateEntityType) *GenEntity {
    var result: *GenEntity = gen.memory.pushStruct(GenEntity, null, @src());
    result.creator = creator;
    return result;
}

fn addEntityGroup(gen: *WorldGenerator, room: *GenRoom) *GenEntityGroup {
    var group: *GenEntityGroup = gen.memory.pushStruct(GenEntityGroup, null, @src());
    group.next = room.first_entity_group;
    room.first_entity_group = group;
    return group;
}

fn placeEntityInGroup(gen: *WorldGenerator, entity: *GenEntity, group: *GenEntityGroup) void {
    _ = gen;
    entity.next = group.first_entity;
    group.first_entity = entity;
}

fn placeEntity(gen: *WorldGenerator, entity: *GenEntity, room: *GenRoom) void {
    const group: *GenEntityGroup = addEntityGroup(gen, room);
    placeEntityInGroup(gen, entity, group);
}

fn appendEntity(gen: *WorldGenerator, parent: *GenEntity, direction_mask: u32, child: *GenEntity) void {
    _ = gen;
    std.debug.assert(child.next == null);

    child.next = parent.next;
    parent.next = child;
    parent.allowed_directions_for_next = direction_mask;
}

fn addTag(gen: *WorldGenerator, entity: *GenEntity, tag_id: AssetTagId, value: f32) *GenEntityTag {
    _ = gen;
    std.debug.assert(entity.tag_count < entity.tags.len);

    var tag: *GenEntityTag = &entity.tags[entity.tag_count];
    entity.tag_count += 1;

    tag.tag_id = tag_id;
    tag.value = value;

    return tag;
}

fn placeCat(gen: *WorldGenerator) ?*GenEntity {
    var result: ?*GenEntity = null;
    var iterator: GenOptionIterator = .iterateOptions(gen, .Cat);
    while (iterator.isValid()) : (iterator.advance()) {
        if (iterator.room) |room| {
            // TODO: Check this room to see if it meets our other criteria.
            if (true) {
                result = addEntity(gen, &entity_gen.addCat);
                _ = addTag(gen, result.?, .Cat, 1);
                placeEntity(gen, result.?, room);
                iterator.finish();
            }
        }
    }
    return result;
}

fn placeSnake(gen: *WorldGenerator, room: *GenRoom) ?*GenEntity {
    var result: ?*GenEntity = null;
    result = addEntity(gen, &entity_gen.addSnake);
    _ = addTag(gen, result.?, .Bones, 1);
    placeEntity(gen, result.?, room);
    return result;
}

fn placeOrphan(gen: *WorldGenerator, orphan_name_tag: AssetTagId) ?*GenEntity {
    var result: ?*GenEntity = null;
    var iterator: GenOptionIterator = .iterateOptions(gen, .Orphan);
    while (iterator.isValid()) : (iterator.advance()) {
        if (iterator.room) |room| {
            // TODO: Check this room to see if it meets our other criteria.
            if (true) {
                result = addEntity(gen, &entity_gen.addOrphan);
                _ = addTag(gen, result.?, .Orphan, 1);
                _ = addTag(gen, result.?, .FacingDirection, 0.75 * math.TAU32);
                placeEntity(gen, result.?, room);

                const child = addEntity(gen, &entity_gen.addConversation);
                appendEntity(gen, result.?, box_mod.BoxMask_South, child);

                iterator.finish();
            }
        }
    }
    if (result) |entity| {
        _ = addTag(gen, entity, orphan_name_tag, 1);
    }
    return result;
}

pub fn createWorldNew(world: *World, assets: *Assets) GenResult {
    var result: GenResult = .{ .initial_camera_position = undefined };

    var gen: *WorldGenerator = beginWorldGen(world, assets);
    gen.entropy = &world.game_entropy;

    const orphanage: GenOrphanage = createOrphanage(gen);
    const dungeon: GenDungeon = createDungeon(gen, 4);
    _ = connect(gen, orphanage.forest_entrance.?, .Down, dungeon.entrance_room.?);

    const start_room: *GenRoom = orphanage.hero_bedroom.?;

    const hannah: ?*GenEntity = placeCat(gen);
    _ = addTag(gen, hannah.?, .Ghost, 1);
    _ = addTag(gen, hannah.?, .Birman, 1);

    const fred: ?*GenEntity = placeCat(gen);
    _ = addTag(gen, fred.?, .Brown, 1);
    _ = addTag(gen, fred.?, .Tabby, 1);

    const molly: ?*GenEntity = placeCat(gen);
    _ = addTag(gen, molly.?, .Gray, 1);
    _ = addTag(gen, molly.?, .Tabby, 1);

    _ = placeOrphan(gen, .Baby);
    _ = placeOrphan(gen, .Brahm);
    _ = placeOrphan(gen, .Carla);
    _ = placeOrphan(gen, .Cassidy);
    _ = placeOrphan(gen, .Drew);
    _ = placeOrphan(gen, .Dylan);
    _ = placeOrphan(gen, .Giles);
    _ = placeOrphan(gen, .Kline);
    _ = placeOrphan(gen, .Laird);
    _ = placeOrphan(gen, .Lambert);
    _ = placeOrphan(gen, .Rhoda);
    _ = placeOrphan(gen, .Slade);
    _ = placeOrphan(gen, .Sunny);
    _ = placeOrphan(gen, .Viva);

    layout(gen, start_room);
    generateWorld(gen);

    const hero_room: GenVolume = orphanage.hero_bedroom.?.volume;
    // const hero_room: GenVolume = orphanage.forest_entrance.?.volume;

    result.initial_camera_position = edit_grid.chunkPositionFromTilePosition(
        gen,
        @divFloor(hero_room.min.x() + hero_room.max.x(), 2),
        @divFloor(hero_room.min.y() + hero_room.max.y(), 2) - 4,
        @divFloor(hero_room.min.z() + hero_room.max.z(), 2),
        null,
    );

    endWorldGen(gen);

    return result;
}

pub fn createWorld(world_mode: *world_mode_mod.GameModeWorld, assets: *Assets) void {
    const generated: GenResult = createWorldNew(world_mode.world, assets);

    world_mode.camera.position = generated.initial_camera_position;
    world_mode.camera.simulation_center = generated.initial_camera_position;
    world_mode.standard_room_dimension = Vector3.new(17 * 1.4, 9 * 1.4, world_mode.typical_floor_height);
}
