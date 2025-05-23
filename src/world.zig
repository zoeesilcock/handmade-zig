const shared = @import("shared.zig");
const memory = @import("memory.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const file_formats = @import("file_formats");
const asset = @import("asset.zig");
const audio = @import("audio.zig");
const random = @import("random.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Color = math.Color;
const MemoryArena = memory.MemoryArena;
const ArenaPushParams = memory.ArenaPushParams;
const TimedBlock = debug_interface.TimedBlock;
const LoadedBitmap = asset.LoadedBitmap;
const BitmapId = file_formats.BitmapId;
const PlayingSound = audio.PlayingSound;
const Entity = entities.Entity;
const EntityReference = entities.EntityReference;
const StoredEntityReference = entities.StoredEntityReference;
const TraversableReference = entities.TraversableReference;
const SimRegion = sim.SimRegion;

const TILE_CHUNK_SAFE_MARGIN = std.math.maxInt(i32) / 64;
const TILE_CHUNK_UNINITIALIZED = std.math.maxInt(i32);
const TILES_PER_CHUNK = 16;

pub const World = extern struct {
    chunk_dimension_in_meters: Vector3,

    first_free: ?*WorldEntityBlock,

    chunk_hash: [4096]?*WorldChunk,

    arena: MemoryArena,

    first_free_chunk: ?*WorldChunk,
    first_free_block: ?*WorldEntityBlock,
};

pub const WorldChunk = extern struct {
    x: i32,
    y: i32,
    z: i32,

    first_block: ?*WorldEntityBlock,

    next_in_hash: ?*WorldChunk = null,
};

pub const WorldEntityBlock = extern struct {
    entity_count: u32,
    low_entity_indices: [TILES_PER_CHUNK]u32,
    next: ?*WorldEntityBlock,

    entity_data_size: u32,
    entity_data: [1 << 16]u8,

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
    var world: *World = parent_arena.pushStruct(World, null);

    world.chunk_dimension_in_meters = chunk_dimension_in_meters;
    world.first_free = null;
    parent_arena.makeSubArena(&world.arena, parent_arena.getRemainingSize(null), ArenaPushParams.noClear());

    return world;
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

fn packEntityReference(opt_sim_region: ?*SimRegion, reference: *EntityReference) void {
    if (reference.ptr) |ptr| {
        if (ptr.isDeleted()) {
            reference.index.value = 0;
        } else {
            reference.index = ptr.id;
        }
    } else if (reference.index.value != 0) {
        if (opt_sim_region != null and sim.getEntityHashFromId(opt_sim_region.?, reference.index) != null) {
            reference.index.value = 0;
        }
    }
}

fn packTraversableReference(opt_sim_region: ?*SimRegion, reference: *TraversableReference) void {
    packEntityReference(opt_sim_region, &reference.entity);
}

fn packEntityIntoChunk(
    world: *World,
    opt_sim_region: ?*SimRegion,
    source: *Entity,
    chunk: *WorldChunk,
) void {
    const pack_size: u32 = @sizeOf(Entity);

    if (chunk.first_block == null or !chunk.first_block.?.hasRoomFor(pack_size)) {
        if (world.first_free_block == null) {
            world.first_free_block = world.arena.pushStruct(WorldEntityBlock, null);
            world.first_free_block.?.next = null;
        }

        const new_block: ?*WorldEntityBlock = world.first_free_block;
        world.first_free_block = new_block.?.next;

        new_block.?.clear();

        new_block.?.next = chunk.first_block;
        chunk.first_block = new_block;
    }

    const block: *WorldEntityBlock = chunk.first_block.?;

    const dest_address = @intFromPtr(&block.entity_data) + block.entity_data_size;
    const dest: usize = std.mem.alignForward(usize, dest_address, @alignOf(Entity));
    const aligned_offset = dest - dest_address;
    const aligned_size = pack_size + aligned_offset;

    // If we hit this assertion it means that there was space for the unaligned size, but not once it was aligned.
    std.debug.assert(block.hasRoomFor(@intCast(aligned_size)));

    block.entity_count += 1;
    block.entity_data_size += @intCast(aligned_size);

    var dest_e: *Entity = @ptrFromInt(dest);
    dest_e.* = source.*;
    packTraversableReference(opt_sim_region, &dest_e.occupying);
    packTraversableReference(opt_sim_region, &dest_e.came_from);
    packTraversableReference(opt_sim_region, &dest_e.auto_boost_to);

    dest_e.acceleration = .zero();
    dest_e.bob_acceleration = 0;
}

pub fn packEntityIntoWorld(
    world: *World,
    opt_sim_region: ?*SimRegion,
    source: *Entity,
    at: WorldPosition,
) void {
    const chunk: ?*WorldChunk = getWorldChunk(world, at.chunk_x, at.chunk_y, at.chunk_z, &world.arena);
    std.debug.assert(chunk != null);
    packEntityIntoChunk(world, opt_sim_region, source, chunk.?);
}

pub fn addChunkToFreeList(
    world: *World,
    old: *WorldChunk,
) void {
    old.next_in_hash = world.first_free_chunk;
    world.first_free_chunk = old;
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
    const chunk_ptr: *?*WorldChunk = getWorldChunkInternal(world, chunk_x, chunk_y, chunk_z);
    const result: ?*WorldChunk = chunk_ptr.*;

    if (result != null) {
        chunk_ptr.* = result.?.next_in_hash;
    }

    return result;
}

pub fn getWorldChunk(
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
                world.first_free_chunk = memory_arena.pushStruct(WorldChunk, ArenaPushParams.noClear());
                world.first_free_chunk.?.next_in_hash = null;
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

pub fn getWorldChunkInternal(
    world: *World,
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,
) *?*WorldChunk {
    TimedBlock.beginFunction(@src(), .GetWorldChunk);
    defer TimedBlock.endFunction(@src(), .GetWorldChunk);

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
    while (opt_chunk.*) |chunk| : (opt_chunk = &chunk.next_in_hash) {
        if ((chunk_x == chunk.x) and
            (chunk_y == chunk.y) and
            (chunk_z == chunk.z))
        {
            break;
        }
    }

    return opt_chunk;
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
