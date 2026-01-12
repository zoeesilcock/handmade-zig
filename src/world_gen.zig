const math = @import("math.zig");
const shared = @import("shared.zig");
const gen_math = @import("gen_math.zig");
const room_gen = @import("room_gen.zig");
const box_mod = @import("box.zig");
const world_mod = @import("world.zig");
const world_mode_mod = @import("world_mode.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
const memory = @import("memory.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const TransientState = shared.TransientState;
const World = world_mod.World;
const WorldPosition = world_mod.WorldPosition;
const GameModeWorld = world_mode_mod.GameModeWorld;
const Entity = entities.Entity;
const TraversableReference = entities.TraversableReference;
const CameraBehavior = entities.CameraBehavior;
const SimRegion = sim.SimRegion;
const BoxSurfaceMask = box_mod.BoxSurfaceMask;
const BoxSurfaceIndex = box_mod.BoxSurfaceIndex;
const GenVolume = gen_math.GenVolume;
const GenVector3 = gen_math.GenVector3;

const X = 0;
const Y = 1;
const Z = 2;
pub const INTERNAL = @import("build_options").internal;

pub const WorldGenerator = struct {
    memory: memory.MemoryArena,
    temp_memory: memory.MemoryArena,

    first_room: ?*GenRoom,
    first_connection: ?*GenConnection,

    creation_region: ?*SimRegion,
};

const GenRoomSpec = struct {};

pub const GenRoom = struct {
    first_connection: ?*GenRoomConnection,
    global_next: ?*GenRoom,

    spec: *GenRoomSpec,
    volume: GenVolume,
    generation_index: u32,

    required_dimension: GenVector3,

    debug_label: if (INTERNAL) []const u8 else void,
};

pub const GenRoomConnection = struct {
    connection: *GenConnection,
    next: ?*GenRoomConnection,

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

const GenOrphanage = struct {
    hero_bedroom: *GenRoom,
    forest_entrance: *GenRoom,
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
            self.first_free = self.memory.pushStruct(GenRoomStackEntry, null);
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

fn genSpec(gen: *WorldGenerator) *GenRoomSpec {
    const spec: *GenRoomSpec = gen.memory.pushStruct(GenRoomSpec, null);
    return spec;
}

fn genRoom(gen: *WorldGenerator, spec: *GenRoomSpec, label: []const u8) *GenRoom {
    var room: *GenRoom = gen.memory.pushStruct(GenRoom, null);
    room.spec = spec;

    if (INTERNAL) {
        room.debug_label = label;
    }

    room.global_next = gen.first_room;
    gen.first_room = room;

    return room;
}

fn addRoomConnection(gen: *WorldGenerator, room: *GenRoom, connection: *GenConnection) *GenRoomConnection {
    var room_connection: *GenRoomConnection = gen.memory.pushStruct(GenRoomConnection, null);

    room_connection.connection = connection;
    room_connection.next = room.first_connection;

    room.first_connection = room_connection;

    return room_connection;
}

fn connectByMask(gen: *WorldGenerator, a: *GenRoom, b: *GenRoom, opt_direction_mask: ?u32) *GenConnection {
    const direction_mask: u32 = opt_direction_mask orelse @intFromEnum(box_mod.BoxSurfaceMask.Planar);
    var connection: *GenConnection = gen.memory.pushStruct(GenConnection, null);

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

fn setSize(gen: *WorldGenerator, room: *GenRoom, dim_x: i32, dim_y: i32, opt_dim_z: ?i32) void {
    _ = gen;
    const dim_z: i32 = opt_dim_z orelse 1;

    room.required_dimension = .{ dim_x, dim_y, dim_z };
}

fn beginWorldGen() *WorldGenerator {
    const gen: *WorldGenerator = memory.bootstrapPushStruct(WorldGenerator, "memory", null, null);
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
            var max: i32 = min_volume.min[dimension];

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

fn placeRoomAlongEdge(gen: *WorldGenerator, base_room: *GenRoom, direction_mask: u32, generation_index: u32) void {
    _ = gen;
    const surface_index: BoxSurfaceIndex = box_mod.getSurfaceIndexFromDirectionMask(direction_mask);

    var axis_a: u32 = 0;
    var edge_axis: u32 = 0;
    var other_a_min: bool = false;
    switch (surface_index) {
        .West => {
            axis_a = 0;
            edge_axis = 1;
            other_a_min = true;
        },
        .East => {
            axis_a = 0;
            edge_axis = 1;
            other_a_min = false;
        },
        .South => {
            axis_a = 1;
            edge_axis = 0;
            other_a_min = true;
        },
        .North => {
            axis_a = 1;
            edge_axis = 0;
            other_a_min = false;
        },
        else => unreachable,
    }

    const min_edge_position: i32 = base_room.volume.min[edge_axis];
    const max_edge_position: i32 = base_room.volume.max[edge_axis];
    var at_edge_position: i32 = min_edge_position;

    var opt_room_connection: ?*GenRoomConnection = base_room.first_connection;
    while (opt_room_connection) |room_connection| : (opt_room_connection = room_connection.next) {
        const connection: *GenConnection = room_connection.connection;
        const room: *GenRoom = connection.getOtherRoom(base_room);

        if (connection.couldGoDirectionByMask(base_room, direction_mask) and
            room.generation_index != generation_index)
        {
            room.generation_index = generation_index;
            room.volume.min[edge_axis] = at_edge_position;
            at_edge_position = at_edge_position + room.required_dimension[edge_axis];
            room.volume.max[edge_axis] = at_edge_position - 1;

            if (other_a_min) {
                room.volume.max[axis_a] = base_room.volume.min[axis_a] - 1;
                room.volume.min[axis_a] = room.volume.max[axis_a] - room.required_dimension[axis_a] + 1;
            } else {
                room.volume.min[axis_a] = base_room.volume.max[axis_a] - 1;
                room.volume.max[axis_a] = room.volume.min[axis_a] + room.required_dimension[axis_a] + 1;
            }

            // if (other_b_min) {
            //     room.volume.max[axis_b] = base_room.volume.min[axis_b] - 1;
            //     room.volume.min[axis_b] = room.volume.max[axis_b] - room.required_dimension[axis_b] + 1;
            // } else {
            //     room.volume.min[axis_b] = base_room.volume.max[axis_b] - 1;
            //     room.volume.max[axis_b] = room.volume.min[axis_b] + room.required_dimension[axis_b] + 1;
            // }

            room.volume.min[2] = base_room.volume.min[2];
            room.volume.max[2] = base_room.volume.max[2];
        }
    }

    _ = max_edge_position;
}

fn layout(gen: *WorldGenerator, world: *World) void {
    // var series = &world.game_entropy;

    const change_memory = gen.temp_memory.beginTemporaryMemory();
    defer gen.temp_memory.endTemporaryMemory(change_memory);

    var stack: GenRoomStack = .{ .memory = &gen.temp_memory };
    const generation_index: u32 = 1;

    if (false) {
        // TODO: This will have to go eventually but for right now we want to control the initial room location.
        const first_room: *GenRoom = gen.first_room.?;
        const volume: GenVolume = .{
            .min = .{
                -4,
                -4,
                0,
            },
            .max = .{
                3,
                3,
                0,
            },
        };
        placeRoomInVolume(first_room, volume);
        first_room.generation_index = generation_index;
        stack.pushConnectedRooms(first_room, generation_index);

        stack.pushRoom(gen.first_room);
        while (stack.hasEntries()) {
            if (stack.popRoom()) |room| {
                if (room.generation_index != generation_index) {
                    room.generation_index = generation_index;
                    stack.pushConnectedRooms(room, generation_index);

                    var min_volume: GenVolume = .infinityVolume();
                    var max_volume: GenVolume = .infinityVolume();

                    const room_placed: bool = placeRoom(gen, world, room, &min_volume, &max_volume, room.first_connection);
                    _ = room_placed;
                    // std.debug.assert(room_placed);
                }
            }
        }
    } else {
        const first_room: *GenRoom = gen.first_room.?;
        var volume: GenVolume = .{
            .min = .{ 0, 0, 0 },
            .max = .{ 0, 0, 0 },
        };

        volume.max[X] = volume.min[X] + first_room.required_dimension[X];
        volume.max[Y] = volume.min[Y] + first_room.required_dimension[Y];
        volume.max[Z] = volume.min[Z] + first_room.required_dimension[Z];
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
                                const direction: u32 = connection.getDirectionMaskFromRoom(other_room);
                                placeRoomAlongEdge(gen, other_room, direction, generation_index);
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
}

fn generateWorld(gen: *WorldGenerator, world: *World) void {
    var opt_room: ?*GenRoom = gen.first_room;
    while (opt_room) |room| : (opt_room = room.global_next) {
        room_gen.generateRoom(gen, world, room);
    }
}

fn endWorldGen(gen: *WorldGenerator) void {
    gen.temp_memory.clear();
    gen.memory.clear();
}

fn createOrphanage(gen: *WorldGenerator) GenOrphanage {
    const bedroom_spec: *GenRoomSpec = genSpec(gen);
    const main_room_spec: *GenRoomSpec = genSpec(gen);
    const tailor_spec: *GenRoomSpec = genSpec(gen);
    const kitchen_spec: *GenRoomSpec = genSpec(gen);
    const garden_spec: *GenRoomSpec = genSpec(gen);
    const basic_forest_spec: *GenRoomSpec = genSpec(gen);
    const hallway_spec: *GenRoomSpec = genSpec(gen);

    const main_room: *GenRoom = genRoom(gen, main_room_spec, "Orphanage Main Room");
    const tailor_room: *GenRoom = genRoom(gen, tailor_spec, "Orphanage Tailor's Room");
    const kitchen: *GenRoom = genRoom(gen, kitchen_spec, "Orphanage Kitchen");
    const front_hall: *GenRoom = genRoom(gen, hallway_spec, "Orphanage Front Hallway");
    const bedroom_a: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom A");
    const bedroom_b: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom B");
    const bedroom_c: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom C");
    const bedroom_d: *GenRoom = genRoom(gen, bedroom_spec, "Orphanage Bedroom D");
    const back_hall: *GenRoom = genRoom(gen, hallway_spec, "Orphanage Back Hallway");
    const hero_save_slot_a: *GenRoom = genRoom(gen, bedroom_spec, "Save Slot A");
    const hero_save_slot_b: *GenRoom = genRoom(gen, bedroom_spec, "Save Slot B");
    const hero_save_slot_c: *GenRoom = genRoom(gen, bedroom_spec, "Save Slot C");
    const garden: *GenRoom = genRoom(gen, garden_spec, "Orphanage Garden");
    const forest_path: *GenRoom = genRoom(gen, basic_forest_spec, "Orphanage Forest Path");
    const forest_entrance: *GenRoom = genRoom(gen, basic_forest_spec, "Orphanage ForestEntrance");
    // const side_alley: *GenRoom = genRoom(gen, basic_forest_spec, "Orphanage Side Alley");

    setSize(gen, main_room, 16, 16, null);
    setSize(gen, tailor_room, 8, 6, null);
    setSize(gen, kitchen, 8, 6, null);
    setSize(gen, front_hall, 5, 16, null);
    setSize(gen, bedroom_a, 8, 6, null);
    setSize(gen, bedroom_b, 8, 6, null);
    setSize(gen, bedroom_c, 8, 6, null);
    setSize(gen, bedroom_d, 8, 6, null);
    setSize(gen, back_hall, 16, 5, null);
    setSize(gen, hero_save_slot_a, 5, 6, null);
    setSize(gen, hero_save_slot_b, 5, 6, null);
    setSize(gen, hero_save_slot_c, 5, 6, null);
    setSize(gen, garden, 16, 16, null);
    // setSize(gen, side_alley, 5, 16, null);
    setSize(gen, forest_path, 16, 16, null);
    setSize(gen, forest_entrance, 8, 8, null);

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

    const result: GenOrphanage = .{
        .hero_bedroom = hero_save_slot_a,
        .forest_entrance = forest_entrance,
    };

    return result;
}

pub fn createWorldNew(world: *World) GenResult {
    var result: GenResult = .{ .initial_camera_position = undefined };

    const gen: *WorldGenerator = beginWorldGen();
    const orphanage: GenOrphanage = createOrphanage(gen);
    _ = orphanage;
    layout(gen, world);
    generateWorld(gen, world);

    result.initial_camera_position = room_gen.chunkPositionFromTilePosition(world, 4, 4, 0, null);

    endWorldGen(gen);

    return result;
}

pub fn createWorld(world_mode: *world_mode_mod.GameModeWorld, transient_state: *TransientState) void {
    _ = transient_state;

    const generated: GenResult = createWorldNew(world_mode.world);

    world_mode.camera.position = generated.initial_camera_position;
    world_mode.camera.simulation_center = generated.initial_camera_position;
    world_mode.standard_room_dimension = Vector3.new(17 * 1.4, 9 * 1.4, world_mode.typical_floor_height);

    // const sim_memory = transient_state.arena.beginTemporaryMemory();
    // const null_origin: WorldPosition = .zero();
    // const null_rect: Rectangle3 = .{ .min = .zero(), .max = .zero() };
    // world_mode.creation_region = sim.beginWorldChange(
    //     &transient_state.arena,
    //     world_mode.world,
    //     null_origin,
    //     null_rect,
    //     0,
    // );
    //
    // var series = &world_mode.world.game_entropy;
    // const screen_base_z: i32 = 0;
    // var door_direction: u32 = 0;
    // var room_center_tile_x: i32 = 0;
    // var room_center_tile_y: i32 = 0;
    // var abs_tile_z: i32 = screen_base_z;
    //
    // var last_screen_z: i32 = abs_tile_z;
    //
    // var door_left = false;
    // var door_right = false;
    // var door_top = false;
    // var door_bottom = false;
    // var door_up = false;
    // var door_down = false;
    // var prev_room: StandardRoom = .{};
    //
    // for (0..8) |screen_index| {
    //     last_screen_z = abs_tile_z;
    //
    //     // const room_radius_x: i32 = 8 + @as(i32, @intCast(series.randomChoice(4)));
    //     // const room_radius_y: i32 = 4 + @as(i32, @intCast(series.randomChoice(4)));
    //     _ = series.randomChoice(4);
    //     const room_radius_x: i32 = 8;
    //     const room_radius_y: i32 = 8;
    //     if (door_direction == 1) {
    //         room_center_tile_x += room_radius_x;
    //     } else if (door_direction == 0) {
    //         room_center_tile_y += room_radius_y;
    //     }
    //
    //     // const door_direction = 1;
    //     // _ = series.randomChoice(2);
    //     // door_direction = 3;
    //     door_direction = series.randomChoice(if (door_up or door_down) 2 else 4);
    //     // door_direction = series.randomChoice(2);
    //
    //     var created_z_door = false;
    //     if (door_direction == 3) {
    //         created_z_door = true;
    //         door_down = true;
    //     } else if (door_direction == 2) {
    //         created_z_door = true;
    //         door_up = true;
    //     } else if (door_direction == 1) {
    //         door_right = true;
    //     } else {
    //         door_top = true;
    //     }
    //
    //     var left_hole: bool = @mod(screen_index, 2) != 0;
    //     var right_hole: bool = !left_hole;
    //     if (screen_index == 0) {
    //         left_hole = false;
    //         right_hole = false;
    //     }
    //
    //     const room_width: i32 = 2 * room_radius_x + 1;
    //     const room_height: i32 = 2 * room_radius_y + 1;
    //     const room: StandardRoom = addStandardRoom(
    //         world_mode,
    //         room_center_tile_x,
    //         room_center_tile_y,
    //         abs_tile_z,
    //         left_hole,
    //         right_hole,
    //         room_radius_x,
    //         room_radius_y,
    //     );
    //
    //     if (true) {
    //         // _ = addMonster(world_mode, room.position[3][6], room.ground[3][6]);
    //         // _ = addFamiliar(world_mode, room.position[4][3], room.ground[4][3]);
    //
    //         const snake_brain_id = world_mode_mod.addBrain(world_mode);
    //         var segment_index: u32 = 0;
    //         while (segment_index < 3) : (segment_index += 1) {
    //             const x: u32 = 2 + segment_index;
    //             _ = world_mode_mod.addSnakeSegment(world_mode, room.position[x][1], room.ground[x][1], snake_brain_id, segment_index);
    //         }
    //     }
    //
    //     for (0..@intCast(room_height)) |tile_y| {
    //         for (0..@intCast(room_width)) |tile_x| {
    //             const position: WorldPosition = room.position[tile_x][tile_y];
    //             const ground: TraversableReference = room.ground[tile_x][tile_y];
    //
    //             var should_be_door = true;
    //             if ((tile_x == 0) and (!door_left or (tile_y != @divFloor(room_height, 2)))) {
    //                 should_be_door = false;
    //             }
    //             if ((tile_x == (room_width - 1)) and (!door_right or (tile_y != @divFloor(room_height, 2)))) {
    //                 should_be_door = false;
    //             }
    //             if ((tile_y == 0) and (!door_bottom or (tile_x != @divFloor(room_width, 2)))) {
    //                 should_be_door = false;
    //             }
    //             if ((tile_y == (room_height - 1)) and (!door_top or (tile_x != @divFloor(room_width, 2)))) {
    //                 should_be_door = false;
    //             }
    //
    //             if (!should_be_door) {
    //                 _ = addWall(world_mode, position, ground);
    //             } else if (created_z_door) {
    //                 // if ((@mod(abs_tile_z, 2) == 1 and (tile_x == 10 and tile_y == 5)) or
    //                 //     ((@mod(abs_tile_z, 2) == 0 and (tile_x == 4 and tile_y == 5))))
    //                 // {
    //                 //     _ = addStairs(world_mode, abs_tile_x, abs_tile_y, if (door_down) abs_tile_z - 1 else abs_tile_z);
    //                 // }
    //             }
    //         }
    //     }
    //
    //     door_left = door_right;
    //     door_bottom = door_top;
    //
    //     if (created_z_door) {
    //         door_up = !door_up;
    //         door_down = !door_down;
    //     } else {
    //         door_up = false;
    //         door_down = false;
    //     }
    //
    //     door_right = false;
    //     door_top = false;
    //
    //     if (door_direction == 3) {
    //         abs_tile_z -= 1;
    //     } else if (door_direction == 2) {
    //         abs_tile_z += 1;
    //     } else if (door_direction == 1) {
    //         room_center_tile_x += room_radius_x + 1;
    //     } else {
    //         room_center_tile_y += room_radius_y + 1;
    //     }
    //
    //     prev_room = room;
    // }
    //
    // if (false) {
    //     // Fill the low entity storage with walls.
    //     while (world_mode.entity_count < (world_mode.low_entities.len - 16)) {
    //         const coordinate: i32 = @intCast(1024 + world_mode.entity_count);
    //         _ = addWall(world_mode, coordinate, coordinate, 0);
    //     }
    // }
    //
    // const camera_tile_x = room_center_tile_x;
    // const camera_tile_y = room_center_tile_y;
    // const camera_tile_z = last_screen_z;
    // const new_camera_position: WorldPosition = world_mode_mod.chunkPositionFromTilePosition(
    //     world_mode.world,
    //     camera_tile_x,
    //     camera_tile_y,
    //     camera_tile_z,
    //     null,
    // );
    // world_mode.camera.position = new_camera_position;
    // world_mode.camera.simulation_center = new_camera_position;
    //
    // sim.endWorldChange(world_mode.creation_region.?);
    // world_mode.creation_region = null;
    // transient_state.arena.endTemporaryMemory(sim_memory);
}

// const StandardRoom = struct {
//     position: [64][64]WorldPosition = undefined,
//     ground: [64][64]TraversableReference = undefined,
// };
//
// fn addStandardRoom(
//     world_mode: *GameModeWorld,
//     abs_tile_x: i32,
//     abs_tile_y: i32,
//     abs_tile_z: i32,
//     left_hole: bool,
//     right_hole: bool,
//     radius_x: i32,
//     radius_y: i32,
// ) StandardRoom {
//     var result: StandardRoom = .{};
//     var offset_y: i32 = -radius_y;
//
//     // const has_left_hole = left_hole;
//     // const has_right_hole = right_hole;
//     _ = left_hole;
//     _ = right_hole;
//     const has_left_hole = true;
//     const has_right_hole = true;
//
//     while (offset_y <= radius_y) : (offset_y += 1) {
//         var offset_x: i32 = -radius_x;
//         while (offset_x <= radius_x) : (offset_x += 1) {
//             var color: Color = .newFromSRGB(0.31, 0.49, 0.32, 1);
//             color = .newFromSRGB(1, 1, 1, 1);
//
//             var standing_on: TraversableReference = .{};
//             var world_position = world_mode_mod.chunkPositionFromTilePosition(
//                 world_mode.world,
//                 abs_tile_x + offset_x,
//                 abs_tile_y + offset_y,
//                 abs_tile_z,
//                 null,
//             );
//
//             if (has_left_hole and offset_x >= -5 and offset_x <= -3 and offset_y >= 0 and offset_y <= 1) {
//                 // Hole down to the floor below.
//             } else if (has_right_hole and offset_x >= 3 and offset_x <= 4 and offset_y >= -1 and offset_y <= 2) {
//                 // Hole down to the floor below.
//             } else {
//                 var wall_height: f32 = 0.5;
//                 if (offset_x >= -2 and offset_x <= 1 and (offset_y == 2 or offset_y == -2)) {
//                     color = if (offset_y == -2) .newFromSRGB(1, 0, 0, 1) else .newFromSRGB(0, 0, 1, 1);
//                     wall_height = 3;
//                 }
//
//                 _ = world_position.offset.setX(world_position.offset.x() + 0 * world_mode.world.game_entropy.randomBilateral());
//                 _ = world_position.offset.setY(world_position.offset.y() + 0 * world_mode.world.game_entropy.randomBilateral());
//                 _ = world_position.offset.setZ(world_position.offset.z() + wall_height + 0.5 * world_mode.world.game_entropy.randomUnilateral());
//
//                 const entity: *Entity = world_mode_mod.beginGroundedEntity(world_mode);
//                 standing_on.entity.ptr = entity;
//                 standing_on.entity.index = entity.id;
//                 entity.traversable_count = 1;
//                 entity.traversables[0].position = Vector3.zero();
//                 entity.traversables[0].occupier = null;
//                 entity.addPieceV2(
//                     .Grass,
//                     .new(0.7, wall_height),
//                     .zero(),
//                     color,
//                     @intFromEnum(EntityVisiblePieceFlag.Cube),
//                 );
//                 world_mode_mod.placeEntity(world_mode, entity, world_position);
//             }
//
//             const array_x: usize = @intCast(offset_x + radius_x);
//             const array_y: usize = @intCast(offset_y + radius_y);
//             result.position[array_x][array_y] = world_position;
//             result.ground[array_x][array_y] = standing_on;
//         }
//     }
//
//     var stair_positions: [4]WorldPosition = [1]WorldPosition{undefined} ** 4;
//     offset_y = -1;
//     while (offset_y <= 2) : (offset_y += 1) {
//         const offset_x: i32 = 3;
//         var standing_on: TraversableReference = .{};
//         var world_position = world_mode_mod.chunkPositionFromTilePosition(
//             world_mode.world,
//             abs_tile_x + offset_x,
//             abs_tile_y + offset_y,
//             abs_tile_z,
//             .new(0.5 * tile_side_in_meters, 0, 0),
//         );
//         stair_positions[@intCast(offset_y + 1)] = world_position;
//
//         _ = world_position.offset.setZ(
//             world_position.offset.z() + 0.3 - (@as(f32, @floatFromInt(offset_y + 2)) * 0.8),
//         );
//
//         const entity: *Entity = world_mode_mod.beginGroundedEntity(world_mode);
//         standing_on.entity.ptr = entity;
//         standing_on.entity.index = entity.id;
//         entity.traversable_count = 1;
//         entity.traversables[0].position = Vector3.zero();
//         entity.traversables[0].occupier = null;
//         entity.addPieceV2(
//             .Grass,
//             .new(0.7, 0.5),
//             .zero(),
//             .newFromSRGB(0.31, 0.49, 0.32, 1),
//             @intFromEnum(EntityVisiblePieceFlag.Cube),
//         );
//         world_mode_mod.placeEntity(world_mode, entity, world_position);
//
//         const array_x: usize = @intCast(offset_x + radius_x);
//         const array_y: usize = @intCast(offset_y + radius_y);
//         result.position[array_x][array_y] = world_position;
//         result.ground[array_x][array_y] = standing_on;
//     }
//
//     {
//         // Hole camera.
//         const entity: *Entity = world_mode_mod.beginGroundedEntity(world_mode);
//         entity.camera_behavior =
//             @intFromEnum(CameraBehavior.Inspect) |
//             @intFromEnum(CameraBehavior.Offset) |
//             @intFromEnum(CameraBehavior.GeneralVelocityConstraint);
//         entity.camera_offset = .new(0, 2, 3);
//         entity.camera_min_time = 1;
//         entity.camera_min_velocity = 0;
//         entity.camera_max_velocity = 0.1;
//         const x_dim: f32 = 1.5 * tile_side_in_meters;
//         const y_dim: f32 = 0.5 * tile_side_in_meters;
//         entity.collision_volume = .fromMinMax(
//             .new(-x_dim, -y_dim, 0),
//             .new(x_dim, y_dim, 0.5 * world_mode.typical_floor_height),
//         );
//         world_mode_mod.placeEntity(world_mode, entity, result.position[@intCast(-4 + radius_x)][@intCast(-1 + radius_y)]);
//     }
//
//     {
//         // Stairs camera, on stairs.
//         var entity: *Entity = world_mode_mod.beginGroundedEntity(world_mode);
//         entity.camera_behavior = @intFromEnum(CameraBehavior.ViewPlayer);
//         var x_dim: f32 = 0.5 * tile_side_in_meters;
//         var y_dim: f32 = 1.5 * tile_side_in_meters;
//         entity.collision_volume = .fromMinMax(
//             .new(-x_dim, -y_dim, -0.5 * world_mode.typical_floor_height),
//             .new(x_dim, y_dim, 0.3 * world_mode.typical_floor_height),
//         );
//         world_mode_mod.placeEntity(world_mode, entity, stair_positions[2]);
//
//         // Stairs camera, at top of stairs.
//         entity = world_mode_mod.beginGroundedEntity(world_mode);
//         entity.camera_behavior =
//             @intFromEnum(CameraBehavior.ViewPlayer) |
//             @intFromEnum(CameraBehavior.DirectionalVelocityConstraint);
//         entity.camera_velocity_direction = .new(0, 1, 0);
//         entity.camera_min_velocity = 0.2;
//         entity.camera_max_velocity = std.math.floatMax(f32);
//         x_dim = 1 * tile_side_in_meters;
//         y_dim = 1.5 * tile_side_in_meters;
//         entity.collision_volume = .fromMinMax(
//             .new(-x_dim, -y_dim, -0.2 * world_mode.typical_floor_height),
//             .new(x_dim, y_dim, 0.5 * world_mode.typical_floor_height),
//         );
//         world_mode_mod.placeEntity(world_mode, entity, stair_positions[0]);
//     }
//
//     const room_position = world_mode_mod.chunkPositionFromTilePosition(
//         world_mode.world,
//         abs_tile_x,
//         abs_tile_y,
//         abs_tile_z,
//         null,
//     );
//
//     const room: *Entity = world_mode_mod.beginGroundedEntity(world_mode);
//     room.collision_volume = world_mode_mod.makeSimpleGroundedCollision(
//         @as(f32, @floatFromInt((2 * radius_x + 1))) * tile_side_in_meters,
//         @as(f32, @floatFromInt((2 * radius_y + 1))) * tile_side_in_meters,
//         world_mode.typical_floor_height,
//         0,
//     );
//
//     room.brain_slot = BrainSlot.forSpecialBrain(.BrainRoom);
//     world_mode_mod.placeEntity(world_mode, room, room_position);
//
//     const world_room: *WorldRoom = world_mod.addWorldRoom(
//         world_mode.world,
//         world_mode_mod.chunkPositionFromTilePosition(
//             world_mode.world,
//             abs_tile_x - radius_x,
//             abs_tile_y - radius_y,
//             abs_tile_z,
//             null,
//         ),
//         world_mode_mod.chunkPositionFromTilePosition(
//             world_mode.world,
//             abs_tile_x + radius_x,
//             abs_tile_y + radius_y,
//             abs_tile_z + 1,
//             null,
//         ),
//         .FocusOnRoom,
//     );
//     _ = world_room;
//
//     return result;
// }
//
// fn addWall(world_mode: *GameModeWorld, world_position: WorldPosition, standing_on: TraversableReference) void {
//     const entity = world_mode_mod.beginGroundedEntity(world_mode);
//
//     entity.collision_volume = world_mode_mod.makeSimpleGroundedCollision(
//         tile_side_in_meters,
//         tile_side_in_meters,
//         world_mode.typical_floor_height - 0.1,
//         0,
//     );
//
//     entity.addFlags(EntityFlags.Collides.toInt());
//     entity.occupying = standing_on;
//     entity.addPiece(.Tree, 2.5, .zero(), .white(), null);
//
//     world_mode_mod.placeEntity(world_mode, entity, world_position);
// }
//
// fn addStairs(world_mode: *GameModeWorld, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) void {
//     const world_position = world_mode_mod.chunkPositionFromTilePosition(world_mode.world, abs_tile_x, abs_tile_y, abs_tile_z, null);
//     const entity = world_mode_mod.beginGroundedEntity(world_mode);
//
//     entity.collision_volume = world_mode_mod.makeSimpleGroundedCollision(
//         tile_side_in_meters,
//         tile_side_in_meters * 2.0,
//         world_mode.typical_floor_height * 1.1,
//         0,
//     );
//     entity.walkable_dimension = entity.collision_volume.getDimension().xy();
//     entity.walkable_height = world_mode.typical_floor_height;
//     entity.addFlags(EntityFlags.Collides.toInt());
//
//     world_mode_mod.placeEntity(world_mode, entity, world_position);
// }
