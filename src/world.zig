const shared = @import("shared.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const brains = @import("brains.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const file_formats = shared.file_formats;
const asset = @import("asset.zig");
const audio = @import("audio.zig");
const random = @import("random.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const MemoryArena = memory.MemoryArena;
const ArenaPushParams = memory.ArenaPushParams;
const BitmapId = file_formats.BitmapId;
const PlayingSound = audio.PlayingSound;
const Entity = entities.Entity;
const EntityFlags = entities.EntityFlags;
const EntityReference = entities.EntityReference;
const TraversableReference = entities.TraversableReference;
const SimRegion = sim.SimRegion;
const TicketMutex = types.TicketMutex;
const BrainId = brains.BrainId;
const ReservedBrainId = brains.ReservedBrainId;
const EntityId = entities.EntityId;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;

const TILE_CHUNK_SAFE_MARGIN = std.math.maxInt(i32) / 64;
const TILE_CHUNK_UNINITIALIZED = std.math.maxInt(i32);
const TILES_PER_CHUNK = 16;
pub const MAX_SIM_REGION_ENTITY_COUNT = 4 * 8192;
const WORLD_BLOCK_SIZE = 1 << 16;

pub const World = extern struct {
    change_ticket: TicketMutex,

    chunk_dimension_in_meters: Vector3,
    game_entropy: random.Series,

    last_used_entity_storage_index: u32,

    first_free: ?*WorldEntityBlock,

    chunk_hash: [4096]?*WorldChunk,

    // Temporary - eventually these will be spatially partitioned, probably?
    room_count: u32,
    rooms: [65536]WorldRoom,

    arena: *MemoryArena,

    first_free_chunk: ?*WorldChunk,
    first_free_block: ?*WorldEntityBlock,

    unpack_is_open: bool,
    unpack_origin: WorldPosition,
    max_unpacked_entity_count: u32,
    unpacked_entity_count: u32 = 0,
    unpacked_entities: [*]Entity,

    total_entity_packs_minus_unpacks: i32,

    null_entity: *Entity,
};

pub const WorldChunk = extern struct {
    next_in_hash: ?*WorldChunk = null,
    first_block: ?*WorldEntityBlock,

    x: i32,
    y: i32,
    z: i32,
    // unpacked: bool,
};

pub const WorldRoom = extern struct {
    min_pos: WorldPosition,
    max_pos: WorldPosition,
};

pub const WorldEntityBlock = extern struct {
    next: ?*WorldEntityBlock,
    entity_count: u32,
    entity_data_size: u32,
    entity_data: [WORLD_BLOCK_SIZE - 16]u8,

    pub fn clear(self: *WorldEntityBlock) void {
        self.entity_count = 0;
        self.next = null;
        self.entity_data_size = 0;
    }

    pub fn hasRoomFor(self: *WorldEntityBlock, size: u32) bool {
        return (self.entity_data_size + size) <= self.entity_data.len;
    }
};

pub const WorldPosition = extern struct {
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,

    // Position relative to the center of the chunk.
    offset: Vector3,

    pub fn zero() WorldPosition {
        return WorldPosition{
            .chunk_x = 0,
            .chunk_y = 0,
            .chunk_z = 0,
            .offset = Vector3.zero(),
        };
    }

    pub fn nullPosition() WorldPosition {
        return WorldPosition{
            .chunk_x = TILE_CHUNK_UNINITIALIZED,
            .chunk_y = 0,
            .chunk_z = 0,
            .offset = Vector3.zero(),
        };
    }

    pub fn isValid(self: *const WorldPosition) bool {
        return self.chunk_x != TILE_CHUNK_UNINITIALIZED;
    }
};

pub fn createWorld(chunk_dimension_in_meters: Vector3, parent_arena: *MemoryArena) *World {
    var world: *World = parent_arena.pushStruct(World, null, @src());

    world.chunk_dimension_in_meters = chunk_dimension_in_meters;
    world.first_free = null;
    world.arena = parent_arena;
    world.game_entropy = .seed(1233, null, null, null);
    world.last_used_entity_storage_index = @intFromEnum(ReservedBrainId.FirstFree);

    world.max_unpacked_entity_count = MAX_SIM_REGION_ENTITY_COUNT;
    world.unpacked_entity_count = 0;
    world.unpacked_entities = world.arena.pushArray(world.max_unpacked_entity_count, Entity, null, @src());

    world.null_entity = world.arena.pushStruct(Entity, null, @src());

    return world;
}

pub fn allocateEntityId(world: *World) EntityId {
    world.last_used_entity_storage_index += 1;
    const result: EntityId = .{ .value = world.last_used_entity_storage_index };
    return result;
}

pub fn addBrain(world: *World) BrainId {
    world.last_used_entity_storage_index += 1;
    const brain_id: BrainId = .{ .value = world.last_used_entity_storage_index };
    return brain_id;
}

fn isCanonical(chunk_dimension: f32, relative: f32) bool {
    const epsilon = 0.01;
    return ((relative >= -(0.5 * chunk_dimension + epsilon)) and
        (relative <= (0.5 * chunk_dimension + epsilon)));
}

pub fn isVector3Canonical(world: *World, offset: Vector3) bool {
    return (isCanonical(world.chunk_dimension_in_meters.x(), offset.x()) and
        isCanonical(world.chunk_dimension_in_meters.y(), offset.y()) and
        isCanonical(world.chunk_dimension_in_meters.z(), offset.z()));
}

pub fn areInSameChunk(world: *World, a: *const WorldPosition, b: *const WorldPosition) bool {
    std.debug.assert(isVector3Canonical(world, a.offset));
    std.debug.assert(isVector3Canonical(world, b.offset));

    return a.chunk_x == b.chunk_x and
        a.chunk_y == b.chunk_y and
        a.chunk_z == b.chunk_z;
}

fn useChunkSpace(
    world: *World,
    size: u32,
    chunk: *WorldChunk,
) *anyopaque {
    if (chunk.first_block == null or !chunk.first_block.?.hasRoomFor(size)) {
        if (world.first_free_block == null) {
            world.first_free_block = world.arena.pushStruct(WorldEntityBlock, null, @src());
            world.first_free_block.?.next = null;
        }

        const new_block: ?*WorldEntityBlock = world.first_free_block;
        world.first_free_block = new_block.?.next;

        new_block.?.clear();

        new_block.?.next = chunk.first_block;
        chunk.first_block = new_block;
    }

    const block: *WorldEntityBlock = chunk.first_block.?;

    std.debug.assert(block.hasRoomFor(@intCast(size)));

    const dest_address = @intFromPtr(&block.entity_data) + block.entity_data_size;
    block.entity_data_size += @intCast(size);
    block.entity_count += 1;

    return @ptrFromInt(dest_address);
}

pub fn useChunkSpaceAt(
    world: *World,
    size: u32,
    at: WorldPosition,
) *anyopaque {
    world.change_ticket.begin();

    const chunk: ?*WorldChunk = getWorldChunk(world, at.chunk_x, at.chunk_y, at.chunk_z, world.arena);
    std.debug.assert(chunk != null);
    const result = useChunkSpace(world, size, chunk.?);

    world.change_ticket.end();

    return result;
}

pub fn addToFreeList(
    world: *World,
    old: *WorldChunk,
    first_block: ?*WorldEntityBlock,
    last_block: ?*WorldEntityBlock,
) void {
    world.change_ticket.begin();

    old.next_in_hash = world.first_free_chunk;
    world.first_free_chunk = old;

    if (first_block) |first| {
        if (last_block) |last| {
            last.next = world.first_free_block;
            world.first_free_block = first;
        }
    }

    world.change_ticket.end();
}

pub fn addBlockToFreeList(
    world: *World,
    old: *WorldEntityBlock,
) void {
    old.next = world.first_free_block;
    world.first_free_block = old;
}

pub fn removeWorldChunk(
    world: *World,
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,
) ?*WorldChunk {
    world.change_ticket.begin();

    const chunk_ptr: *?*WorldChunk = getWorldChunkInternal(world, chunk_x, chunk_y, chunk_z);
    const result: ?*WorldChunk = chunk_ptr.*;

    if (result != null) {
        chunk_ptr.* = result.?.next_in_hash;
    }

    world.change_ticket.end();

    return result;
}

fn getWorldChunk(
    world: *World,
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,
    opt_memory_arena: ?*MemoryArena,
) ?*WorldChunk {
    const chunk_ptr: *?*WorldChunk = getWorldChunkInternal(world, chunk_x, chunk_y, chunk_z);
    var result: ?*WorldChunk = chunk_ptr.*;

    if (result == null) {
        if (opt_memory_arena) |memory_arena| {
            if (world.first_free_chunk == null) {
                const chunk_count_per_block: u32 = WORLD_BLOCK_SIZE / @sizeOf(WorldChunk);
                const chunk_array: [*]WorldChunk =
                    memory_arena.pushArray(chunk_count_per_block, WorldChunk, .noClear(), @src());

                var chunk_index: u32 = 0;
                while (chunk_index < chunk_count_per_block) : (chunk_index += 1) {
                    const new_chunk: *WorldChunk = &chunk_array[chunk_index];
                    new_chunk.next_in_hash = world.first_free_chunk;
                    world.first_free_chunk = new_chunk;
                }
            }

            result = world.first_free_chunk;
            world.first_free_chunk = result.?.next_in_hash;

            result.?.first_block = null;
            result.?.x = chunk_x;
            result.?.y = chunk_y;
            result.?.z = chunk_z;

            result.?.next_in_hash = chunk_ptr.*;
            chunk_ptr.* = result;
        }
    }

    return result;
}

pub fn getWorldChunkBounds(
    world: *World,
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,
) Rectangle3 {
    const chunk_center: Vector3 = Vector3.newI(chunk_x, chunk_y, chunk_z).hadamardProduct(world.chunk_dimension_in_meters);
    const result: Rectangle3 = .fromCenterDimension(chunk_center, world.chunk_dimension_in_meters);
    return result;
}

pub fn getWorldChunkInternal(
    world: *World,
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,
) *?*WorldChunk {
    std.debug.assert(chunk_x > -TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_x > -TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_y > -TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_x < TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_y < TILE_CHUNK_SAFE_MARGIN);
    std.debug.assert(chunk_z < TILE_CHUNK_SAFE_MARGIN);

    const hash_value: u32 = @bitCast(19 *% chunk_x +% 7 *% chunk_y +% 3 *% chunk_z);
    const hash_slot = @as(usize, @intCast(hash_value)) & (world.chunk_hash.len - 1);
    std.debug.assert(hash_slot < world.chunk_hash.len);

    var opt_chunk: *?*WorldChunk = &world.chunk_hash[hash_slot];
    while (opt_chunk.* != null and
        !((chunk_x == opt_chunk.*.?.x) and
            (chunk_y == opt_chunk.*.?.y) and
            (chunk_z == opt_chunk.*.?.z)))
    {
        opt_chunk = &opt_chunk.*.?.next_in_hash;
    }

    return opt_chunk;
}

pub fn addWorldRoom(
    world: *World,
    min_pos: WorldPosition,
    max_pos: WorldPosition,
) *WorldRoom {
    std.debug.assert(world.room_count < world.rooms.len);
    var room: *WorldRoom = &world.rooms[world.room_count];
    world.room_count += 1;

    room.min_pos = min_pos;
    room.max_pos = max_pos;

    return room;
}

pub fn recannonicalizeCoordinate(chunk_dimension: f32, tile_abs: *i32, tile_rel: *f32) void {
    const epsilon = 0.0001;
    const offset = intrinsics.roundReal32ToInt32((tile_rel.* + epsilon) / chunk_dimension);

    tile_abs.* +%= offset;
    tile_rel.* -= @as(f32, @floatFromInt(offset)) * chunk_dimension;

    std.debug.assert(isCanonical(chunk_dimension, tile_rel.*));
}

pub fn mapIntoChunkSpace(world: *World, base_position: WorldPosition, offset: Vector3) WorldPosition {
    var result = base_position;

    result.offset = result.offset.plus(offset);
    recannonicalizeCoordinate(world.chunk_dimension_in_meters.x(), &result.chunk_x, &result.offset.values[0]);
    recannonicalizeCoordinate(world.chunk_dimension_in_meters.y(), &result.chunk_y, &result.offset.values[1]);
    recannonicalizeCoordinate(world.chunk_dimension_in_meters.z(), &result.chunk_z, &result.offset.values[2]);

    return result;
}

pub fn subtractPositions(world: *World, a: *const WorldPosition, b: *const WorldPosition) Vector3 {
    var tile_diff = Vector3.new(
        @as(f32, @floatFromInt(a.chunk_x)) - @as(f32, @floatFromInt(b.chunk_x)),
        @as(f32, @floatFromInt(a.chunk_y)) - @as(f32, @floatFromInt(b.chunk_y)),
        @as(f32, @floatFromInt(a.chunk_z)) - @as(f32, @floatFromInt(b.chunk_z)),
    );

    return tile_diff.hadamardProduct(world.chunk_dimension_in_meters).plus(a.offset.minus(b.offset));
}

pub fn createEntity(world: *World) *Entity {
    var result: *Entity = world.null_entity;

    if (world.unpacked_entity_count < world.max_unpacked_entity_count) {
        result = &world.unpacked_entities[world.unpacked_entity_count];
        world.unpacked_entity_count += 1;
    } else {
        unreachable;
    }

    memory.zeroStruct(Entity, result);

    return result;
}

pub fn ensureRegionIsUnpacked(
    world: *World,
    min_chunk_position: WorldPosition,
    max_chunk_position: WorldPosition,
    sim_region: *SimRegion,
) void {
    TimedBlock.beginFunction(@src(), .EnsureRegionIsUnpacked);
    defer TimedBlock.endFunction(@src(), .EnsureRegionIsUnpacked);

    std.debug.assert(!world.unpack_is_open);
    world.unpack_is_open = true;

    const unpack_origin_delta: Vector3 =
        subtractPositions(world, &sim_region.origin, &world.unpack_origin);
    world.unpack_origin = sim_region.origin;

    // TODO: Since we're making this pass here, it does seem like we would want to just keep an updateable hash table,
    // perhaps, and not have to do so many passes over all the entities?
    {
        var entity_index: u32 = 0;
        while (entity_index < world.unpacked_entity_count) : (entity_index += 1) {
            const entity: *Entity = &world.unpacked_entities[entity_index];
            entity.position = entity.position.plus(unpack_origin_delta);
            sim.registerEntity(sim_region, entity);
        }
    }

    var chunk_z = min_chunk_position.chunk_z;
    while (chunk_z <= max_chunk_position.chunk_z) : (chunk_z += 1) {
        var chunk_y = min_chunk_position.chunk_y;
        while (chunk_y <= max_chunk_position.chunk_y) : (chunk_y += 1) {
            var chunk_x = min_chunk_position.chunk_x;
            while (chunk_x <= max_chunk_position.chunk_x) : (chunk_x += 1) {
                const opt_chunk = removeWorldChunk(sim_region.world, chunk_x, chunk_y, chunk_z);

                if (opt_chunk) |chunk| {
                    std.debug.assert(chunk.x == chunk_x);
                    std.debug.assert(chunk.y == chunk_y);
                    std.debug.assert(chunk.z == chunk_z);
                    const chunk_position: WorldPosition = .{
                        .chunk_x = chunk_x,
                        .chunk_y = chunk_y,
                        .chunk_z = chunk_z,
                        .offset = .zero(),
                    };
                    const chunk_delta: Vector3 =
                        subtractPositions(world, &chunk_position, &world.unpack_origin);
                    const first_block: ?*WorldEntityBlock = chunk.first_block;
                    var last_block: ?*WorldEntityBlock = first_block;
                    var opt_block: ?*WorldEntityBlock = first_block;
                    while (opt_block) |block| : (opt_block = block.next) {
                        last_block = block;

                        var entity_index: u32 = 0;
                        while (entity_index < block.entity_count) : (entity_index += 1) {
                            if (world.unpacked_entity_count < world.max_unpacked_entity_count) {
                                const entities_ptr: [*]align(1) Entity = @ptrCast(&block.entity_data);
                                const source: ?[*]align(1) Entity = entities_ptr + entity_index;
                                const id: EntityId = source.?[0].id;
                                const dest: *Entity =
                                    @ptrCast(world.unpacked_entities + world.unpacked_entity_count);
                                world.unpacked_entity_count += 1;

                                std.debug.assert(source != null);

                                dest.* = source.?[0];
                                dest.position = dest.position.plus(chunk_delta);
                                dest.id = id;

                                sim.registerEntity(sim_region, dest);

                                world.total_entity_packs_minus_unpacks -= 1;
                            } else {
                                unreachable;
                            }
                        }
                    }

                    addToFreeList(sim_region.world, chunk, first_block, last_block);
                }
            }
        }
    }

    DebugInterface.debugValue(@src(), &world.unpacked_entity_count, "UnpackedEntityCount");
}

pub fn repackEntitiesAsNecessary(
    world: *World,
    sim_region: *SimRegion,
) void {
    TimedBlock.beginFunction(@src(), .RepackEntitiesAsNecessary);
    defer TimedBlock.endFunction(@src(), .RepackEntitiesAsNecessary);

    std.debug.assert(world.unpack_is_open);

    var entity_index: u32 = 0;
    var entity: [*]Entity = world.unpacked_entities;
    while (entity_index < world.unpacked_entity_count) : (entity_index += 1) {
        if (!entity[0].hasFlag(EntityFlags.Deleted.toInt())) {
            const entity_position: WorldPosition =
                mapIntoChunkSpace(world, world.unpack_origin, entity[0].position);
            var chunk_position: WorldPosition = entity_position;
            chunk_position.offset = .zero();

            const chunk_delta: Vector3 = entity_position.offset.minus(entity[0].position);

            entity[0].position = entity[0].position.plus(chunk_delta);
            var dest_e: *align(1) Entity =
                @ptrCast(useChunkSpaceAt(sim_region.world, @sizeOf(Entity), chunk_position));

            dest_e.* = entity[0];
            sim.packTraversableReference(sim_region, &dest_e.occupying);
            sim.packTraversableReference(sim_region, &dest_e.came_from);
            sim.packTraversableReference(sim_region, &dest_e.auto_boost_to);

            dest_e.acceleration = .zero();
            dest_e.bob_acceleration = 0;

            world.total_entity_packs_minus_unpacks += 1;
        }

        entity += 1;
    }

    world.unpacked_entity_count = 0;
    world.unpack_is_open = false;
}
