const shared = @import("shared.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const world = @import("world.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
const particles = @import("particles.zig");
const config = @import("config.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

var global_config = &@import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const MemoryArena = memory.MemoryArena;
const MemoryIndex = memory.MemoryIndex;
const ArenaPushParams = memory.ArenaPushParams;
const GameModeWorld = @import("world_mode.zig").GameModeWorld;
const PairwiseCollisionRule = @import("world_mode.zig").PairwiseCollisionRule;
const World = world.World;
const Entity = entities.Entity;
const EntityId = entities.EntityId;
const EntityReference = entities.EntityReference;
const TraversableReference = entities.TraversableReference;
const EntityCollisionVolume = entities.EntityCollisionVolume;
const EntityCollisionVolumeGroup = entities.EntityCollisionVolumeGroup;
const EntityTraversablePoint = entities.EntityTraversablePoint;
const EntityFlags = entities.EntityFlags;
const Brain = brains.Brain;
const BrainId = brains.BrainId;
const BrainType = brains.BrainType;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const ParticleSystem = particles.ParticleSystem;
const ParticleCache = particles.ParticleCache;

pub const SimRegion = extern struct {
    world: *World,

    origin: world.WorldPosition,
    bounds: Rectangle3,
    updatable_bounds: Rectangle3,

    max_entity_count: u32,
    entity_count: u32 = 0,
    entities: [*]Entity,

    max_brain_count: u32,
    brain_count: u32 = 0,
    brains: [*]Brain,

    entity_hash: [4096]EntityHash = [1]EntityHash{undefined} ** 4096,
    brain_hash: [256]BrainHash = [1]BrainHash{undefined} ** 256,

    entity_hash_occupancy: [4096 / 64]u64,
    brain_hash_occupancy: [256 / 64]u64,

    null_entity: Entity,
};

pub const EntityHash = extern struct {
    ptr: ?*Entity = null,
};

pub const BrainHash = extern struct {
    ptr: ?*Brain = null,
};

pub const MoveSpec = extern struct {
    speed: f32 = 1.0,
    drag: f32 = 0.0,
    unit_max_acceleration: bool = false,
};

const WallTestData = struct {
    x: f32,
    rel_x: f32,
    rel_y: f32,
    delta_y: f32,
    delta_x: f32,
    min_y: f32,
    max_y: f32,
    normal: Vector3,
};

fn shiftIndex(index: MemoryIndex) MemoryIndex {
    const shiftee: u64 = 1;
    const shift: u6 = @truncate(index);
    const mask: u64 = shiftee << shift;
    return mask;
}

fn markBit(array: [*]u64, index: MemoryIndex) void {
    const occ_index: MemoryIndex = index / 64;
    const bit_index: MemoryIndex = @mod(index, 64);
    array[occ_index] |= shiftIndex(bit_index);
}

fn isEmpty(array: [*]u64, index: MemoryIndex) bool {
    const occ_index: MemoryIndex = index / 64;
    const bit_index: MemoryIndex = @mod(index, 64);
    return (array[occ_index] & shiftIndex(bit_index)) == 0;
}

fn markEntityOccupied(sim_region: *SimRegion, entry: *EntityHash) void {
    const index: MemoryIndex = entry - &sim_region.entity_hash;
    markBit(&sim_region.entity_hash_occupancy, index);
}

fn markBrainOccupied(sim_region: *SimRegion, entry: *BrainHash) void {
    const index: MemoryIndex = entry - &sim_region.brain_hash;
    markBit(&sim_region.brain_hash_occupancy, index);
}

pub fn getEntityHashFromId(sim_region: *SimRegion, id: EntityId) ?*EntityHash {
    std.debug.assert(id.value != 0);

    var result: ?*EntityHash = null;

    const hash_value = id.value;
    var offset: u32 = 0;
    while (offset < sim_region.entity_hash.len) : (offset += 1) {
        const hash_mask = sim_region.entity_hash.len - 1;
        const hash_index = (hash_value + offset) & hash_mask;
        const entry: *EntityHash = &sim_region.entity_hash[hash_index];

        if (isEmpty(&sim_region.entity_hash_occupancy, hash_index)) {
            result = entry;
            result.?.ptr = null;
            break;
        } else if (entry.ptr != null and entry.ptr.?.id.value == id.value) {
            result = entry;
            break;
        }
    }

    std.debug.assert(result != null);

    return result;
}

pub fn getBrainHashFromId(sim_region: *SimRegion, id: BrainId) ?*BrainHash {
    std.debug.assert(id.value != 0);

    var result: ?*BrainHash = null;

    const hash_value = id.value;
    var offset: u32 = 0;

    while (offset < sim_region.brain_hash.len) : (offset += 1) {
        const hash_mask = sim_region.brain_hash.len - 1;
        const hash_index = (hash_value + offset) & hash_mask;
        const entry: *BrainHash = &sim_region.brain_hash[hash_index];

        if (isEmpty(&sim_region.brain_hash_occupancy, hash_index)) {
            result = entry;
            result.?.ptr = null;
            break;
        } else if (entry.ptr != null and entry.ptr.?.id.value == id.value) {
            result = entry;
            break;
        }
    }

    std.debug.assert(result != null);

    return result;
}

pub fn getEntityByStorageIndex(sim_region: *SimRegion, id: EntityId) ?*Entity {
    const entry = getEntityHashFromId(sim_region, id);
    const result: ?*Entity = if (entry != null) entry.?.ptr else null;
    return result;
}

pub fn loadEntityReference(sim_region: *SimRegion, reference: *EntityReference) void {
    if (reference.index.value != 0) {
        reference.* = EntityReference{
            .ptr = getEntityByStorageIndex(sim_region, reference.index),
        };

        // TODO: Why is this needed in our version, but not in Casey's?
        if (reference.ptr) |entity| {
            reference.index = entity.id;
        }
    }
}

pub fn loadTraversableReference(sim_region: *SimRegion, reference: *TraversableReference) void {
    loadEntityReference(sim_region, &reference.entity);
}

pub fn entityOverlapsRectangle(position: Vector3, volume: EntityCollisionVolume, rectangle: Rectangle3) bool {
    const grown = rectangle.addRadius(volume.dimension.scaledTo(0.5));
    return position.plus(volume.offset_position).isInRectangle(grown);
}

fn getOrAddBrain(sim_region: *SimRegion, brain_id: BrainId, brain_type: BrainType) *Brain {
    TimedBlock.beginFunction(@src(), .GetOrAddBrain);
    defer TimedBlock.endFunction(@src(), .GetOrAddBrain);

    var result: ?*Brain = null;

    const opt_hash: ?*BrainHash = getBrainHashFromId(sim_region, brain_id);
    result = opt_hash.?.ptr;

    if (result == null) {
        std.debug.assert(sim_region.brain_count < sim_region.max_brain_count);
        std.debug.assert(
            isEmpty(&sim_region.brain_hash_occupancy, opt_hash.? - &sim_region.brain_hash),
        );

        result = &sim_region.brains[sim_region.brain_count];
        sim_region.brain_count += 1;

        memory.zeroStruct(Brain, result.?);
        result.?.id = brain_id;
        result.?.type = brain_type;

        opt_hash.?.ptr = result.?;

        markBrainOccupied(sim_region, opt_hash.?);
        std.debug.assert(
            !isEmpty(&sim_region.brain_hash_occupancy, opt_hash.? - &sim_region.brain_hash),
        );
    }

    return result.?;
}

pub fn createEntity(sim_region: *SimRegion, id: EntityId) *Entity {
    var result: *Entity = &sim_region.null_entity;

    if (sim_region.entity_count < sim_region.max_entity_count) {
        result = &sim_region.entities[sim_region.entity_count];
        sim_region.entity_count += 1;
    } else {
        unreachable;
    }

    memory.zeroStruct(Entity, result);

    result.id = id;
    addEntityToHash(sim_region, result);

    return result;
}

pub fn deleteEntity(sim_region: *SimRegion, opt_entity: ?*Entity) void {
    _ = sim_region;
    if (opt_entity) |entity| {
        entity.addFlags(EntityFlags.Deleted.toInt());
    }
}

fn connectEntityPointers(sim_region: *SimRegion) void {
    var entity_index: u32 = 0;
    while (entity_index < sim_region.entity_count) : (entity_index += 1) {
        const entity: *Entity = &sim_region.entities[entity_index];

        loadTraversableReference(sim_region, &entity.occupying);
        if (entity.occupying.entity.ptr) |occupying_entity| {
            occupying_entity.traversables[entity.occupying.index].occupier = entity;
        }

        loadTraversableReference(sim_region, &entity.came_from);
        loadTraversableReference(sim_region, &entity.auto_boost_to);
    }
}

fn packEntityReference(opt_sim_region: ?*SimRegion, reference: *EntityReference) void {
    if (reference.ptr) |ptr| {
        if (ptr.isDeleted()) {
            reference.index.value = 0;
        } else {
            reference.index = ptr.id;
        }
    } else if (reference.index.value != 0) {
        if (opt_sim_region != null and getEntityHashFromId(opt_sim_region.?, reference.index) != null) {
            reference.index.value = 0;
        }
    }
}

fn packTraversableReference(opt_sim_region: ?*SimRegion, reference: *TraversableReference) void {
    packEntityReference(opt_sim_region, &reference.entity);
}

fn addEntityToHash(sim_region: *SimRegion, entity: *Entity) void {
    TimedBlock.beginFunction(@src(), .AddEntityToHash);
    defer TimedBlock.endFunction(@src(), .AddEntityToHash);

    const entry: *EntityHash = getEntityHashFromId(sim_region, entity.id).?;
    std.debug.assert(
        isEmpty(&sim_region.entity_hash_occupancy, entry - &sim_region.entity_hash),
    );
    entry.ptr = entity;

    markEntityOccupied(sim_region, entry);
}

pub fn beginWorldChange(
    sim_arena: *MemoryArena,
    game_world: *World,
    origin: world.WorldPosition,
    bounds: Rectangle3,
    delta_time: f32,
) *SimRegion {
    _ = delta_time;

    TimedBlock.beginFunction(@src(), .BeginWorldChange);
    defer TimedBlock.endFunction(@src(), .BeginWorldChange);

    TimedBlock.beginBlock(@src(), .SimArenaAlloc);
    var sim_region: *SimRegion = sim_arena.pushStruct(SimRegion, ArenaPushParams.aligned(16, false));
    TimedBlock.endBlock(@src(), .SimArenaAlloc);

    TimedBlock.beginBlock(@src(), .SimArenaClear);
    memory.zeroStruct(@TypeOf(sim_region.entity_hash), &sim_region.entity_hash);
    memory.zeroStruct(@TypeOf(sim_region.brain_hash), &sim_region.brain_hash);
    memory.zeroStruct(@TypeOf(sim_region.entity_hash_occupancy), &sim_region.entity_hash_occupancy);
    memory.zeroStruct(@TypeOf(sim_region.brain_hash_occupancy), &sim_region.brain_hash_occupancy);
    memory.zeroStruct(@TypeOf(sim_region.null_entity), &sim_region.null_entity);
    TimedBlock.endBlock(@src(), .SimArenaClear);

    sim_region.world = game_world;

    sim_region.origin = origin;
    sim_region.bounds = bounds;
    sim_region.updatable_bounds = sim_region.bounds;
    sim_region.max_entity_count = 4096;
    sim_region.entity_count = 0;
    sim_region.entities = sim_arena.pushArray(sim_region.max_entity_count, Entity, ArenaPushParams.noClear());

    sim_region.max_brain_count = 256;
    sim_region.brain_count = 0;
    sim_region.brains = sim_arena.pushArray(sim_region.max_brain_count, Brain, ArenaPushParams.noClear());

    const min_chunk_position = world.mapIntoChunkSpace(
        sim_region.world,
        sim_region.origin,
        sim_region.bounds.getMinCorner(),
    );
    const max_chunk_position = world.mapIntoChunkSpace(
        sim_region.world,
        sim_region.origin,
        sim_region.bounds.getMaxCorner(),
    );

    DebugInterface.debugBeginDataBlock(@src(), "Simulation/Origin");
    DebugInterface.debugStruct(@src(), &sim_region.origin);
    DebugInterface.debugEndDataBlock(@src());

    var chunk_z = min_chunk_position.chunk_z;
    while (chunk_z <= max_chunk_position.chunk_z) : (chunk_z += 1) {
        var chunk_y = min_chunk_position.chunk_y;
        while (chunk_y <= max_chunk_position.chunk_y) : (chunk_y += 1) {
            var chunk_x = min_chunk_position.chunk_x;
            while (chunk_x <= max_chunk_position.chunk_x) : (chunk_x += 1) {
                const opt_chunk = world.removeWorldChunk(sim_region.world, chunk_x, chunk_y, chunk_z);

                if (opt_chunk) |chunk| {
                    std.debug.assert(chunk.x == chunk_x);
                    std.debug.assert(chunk.y == chunk_y);
                    std.debug.assert(chunk.z == chunk_z);
                    const chunk_position: world.WorldPosition = .{
                        .chunk_x = chunk_x,
                        .chunk_y = chunk_y,
                        .chunk_z = chunk_z,
                        .offset = .zero(),
                    };
                    const chunk_delta: Vector3 =
                        world.subtractPositions(sim_region.world, &chunk_position, &sim_region.origin);
                    const first_block: ?*world.WorldEntityBlock = chunk.first_block;
                    var last_block: ?*world.WorldEntityBlock = first_block;
                    var opt_block: ?*world.WorldEntityBlock = first_block;
                    while (opt_block) |block| : (opt_block = block.next) {
                        last_block = block;

                        var entity_index: u32 = 0;
                        while (entity_index < block.entity_count) : (entity_index += 1) {
                            if (sim_region.entity_count < sim_region.max_entity_count) {
                                const source_address = @intFromPtr(&block.entity_data);
                                const source_address_aligned: usize = std.mem.alignForward(usize, source_address, @alignOf(Entity));
                                const entities_ptr: [*]Entity = @ptrFromInt(source_address_aligned);
                                const source = &entities_ptr[entity_index];
                                const id: EntityId = source.id;
                                const dest: *Entity = &sim_region.entities[sim_region.entity_count];
                                sim_region.entity_count += 1;

                                dest.* = source.*;

                                dest.id = id;
                                dest.z_layer = chunk_z;

                                dest.manual_sort = .{};

                                addEntityToHash(sim_region, dest);
                                dest.position = dest.position.plus(chunk_delta);

                                if (entityOverlapsRectangle(
                                    dest.position,
                                    dest.collision.total_volume,
                                    sim_region.updatable_bounds,
                                )) {
                                    dest.flags |= EntityFlags.Active.toInt();
                                }

                                if (dest.brain_id.value != 0) {
                                    const brain: *Brain = getOrAddBrain(
                                        sim_region,
                                        dest.brain_id,
                                        @enumFromInt(dest.brain_slot.type),
                                    );
                                    var ptr = @intFromPtr(&brain.parts.array);
                                    ptr += @sizeOf(*Entity) * dest.brain_slot.index;
                                    std.debug.assert(ptr <= @intFromPtr(brain) + @sizeOf(Brain) - @sizeOf(*Entity));
                                    @as(**Entity, @ptrFromInt(ptr)).* = dest;
                                }
                            } else {
                                unreachable;
                            }
                        }
                    }

                    world.addToFreeList(sim_region.world, chunk, first_block, last_block);
                }
            }
        }
    }

    connectEntityPointers(sim_region);

    DebugInterface.debugValue(@src(), &sim_region.entity_count, "EntityCount");

    return sim_region;
}

fn speculativeCollide(mover: *Entity, region: *Entity, test_position: Vector3) bool {
    const result = true;

    _ = mover;
    _ = region;
    _ = test_position;
    // if (region.type == .Stairwell) {
    //     const step_height = 0.1;
    //     const mover_ground_point = mover.getGroundPointFor(test_position);
    //     const ground = region.getStairGround(mover_ground_point);
    //     result = ((intrinsics.absoluteValue(mover_ground_point.z() - ground) > step_height));
    // }

    return result;
}

fn entitiesOverlap(entity: *Entity, test_entity: *Entity, epsilon: Vector3) bool {
    var overlapped = false;

    var entity_volume_index: u32 = 0;
    while (!overlapped and entity_volume_index < entity.collision.volume_count) : (entity_volume_index += 1) {
        const entity_volume = entity.collision.volumes[entity_volume_index];

        var test_volume_index: u32 = 0;
        while (!overlapped and test_volume_index < test_entity.collision.volume_count) : (test_volume_index += 1) {
            const test_volume = test_entity.collision.volumes[test_volume_index];

            const entity_rectangle = Rectangle3.fromCenterDimension(
                entity.position.plus(entity_volume.offset_position),
                entity_volume.dimension.plus(epsilon),
            );
            const test_entity_rectangle = Rectangle3.fromCenterDimension(
                test_entity.position.plus(test_volume.offset_position),
                test_volume.dimension,
            );

            overlapped = entity_rectangle.intersects(&test_entity_rectangle);
        }
    }

    return overlapped;
}

fn canCollide(entity: *Entity, hit_entity: *Entity) bool {
    var result = false;

    if (entity != hit_entity) {
        var a = entity;
        var b = hit_entity;

        // Sort entities based on storage index.
        if (a.id.value > b.id.value) {
            const temp = a;
            a = b;
            b = temp;
        }

        // Basic rules.
        if (a.hasFlag(EntityFlags.Collides.toInt()) and
            b.hasFlag(EntityFlags.Collides.toInt()))
        {
            result = true;
        }
    }

    return result;
}

pub fn handleCollision(entity: *Entity, hit_entity: *Entity) bool {
    const stops_on_collision = true;

    _ = entity;
    _ = hit_entity;
    // var a = entity;
    // var b = hit_entity;
    //
    // // Sort entities based on type.
    // if (@intFromEnum(a.type) > @intFromEnum(b.type)) {
    //     const temp = a;
    //     a = b;
    //     b = temp;
    // }

    return stops_on_collision;
}

pub fn transactionalOccupy(entity: *Entity, dest_ref: *TraversableReference, desired_ref: TraversableReference) bool {
    var result = false;

    if (desired_ref.getTraversable()) |desired| {
        if (desired.occupier == null) {
            if (dest_ref.getTraversable()) |dest| {
                dest.occupier = null;
            }
            dest_ref.* = desired_ref;
            desired.occupier = entity;
            result = true;
        }
    } else {
        std.log.warn("Failed to get the desired traversable.", .{});
    }

    return result;
}

pub fn moveEntity(
    sim_region: *SimRegion,
    entity: *Entity,
    delta_time: f32,
    acceleration: Vector3,
) void {
    // Calculate movement delta.
    var entity_delta = acceleration.scaledTo(0.5 * math.square(delta_time))
        .plus(entity.velocity.scaledTo(delta_time));
    entity.velocity = acceleration.scaledTo(delta_time).plus(entity.velocity);

    // std.debug.assert(entity.velocity.lengthSquared() <= math.square(sim_region.max_entity_velocity));

    var distance_remaining = entity.distance_limit;
    if (distance_remaining == 0) {
        distance_remaining = 10000;
    }

    const overlap_epsilon = Vector3.splat(0.001);
    const time_epsilon = 0.001;

    var iterations: u32 = 0;
    while (iterations < 4) : (iterations += 1) {
        var min_time: f32 = 1.0;
        const max_time: f32 = 1.0;
        const entity_delta_length = entity_delta.length();

        if (entity_delta_length > 0) {
            if (entity_delta_length > distance_remaining) {
                min_time = distance_remaining / entity_delta_length;
            }

            var wall_normal_min = Vector3.zero();
            const wall_normal_max = Vector3.zero();
            var opt_hit_entity_min: ?*Entity = null;
            const opt_hit_entity_max: ?*Entity = null;

            const desired_position = entity.position.plus(entity_delta);

            var test_entity_index: u32 = 0;
            while (test_entity_index < sim_region.entity_count) : (test_entity_index += 1) {
                const test_entity = &sim_region.entities[test_entity_index];

                if (entitiesOverlap(entity, test_entity, overlap_epsilon) or
                    canCollide(entity, test_entity))
                {
                    var entity_volume_index: u32 = 0;
                    while (entity_volume_index < entity.collision.volume_count) : (entity_volume_index += 1) {
                        const entity_volume = entity.collision.volumes[entity_volume_index];
                        var test_volume_index: u32 = 0;
                        while (test_volume_index < test_entity.collision.volume_count) : (test_volume_index += 1) {
                            const test_volume = test_entity.collision.volumes[test_volume_index];
                            const minkowski_diameter = Vector3.new(
                                test_volume.dimension.x() + entity_volume.dimension.x(),
                                test_volume.dimension.y() + entity_volume.dimension.y(),
                                test_volume.dimension.z() + entity_volume.dimension.z(),
                            );
                            const min_corner = minkowski_diameter.scaledTo(-0.5);
                            const max_corner = minkowski_diameter.scaledTo(0.5);
                            const relative = entity.position.plus(entity_volume.offset_position)
                                .minus(test_entity.position.plus(test_volume.offset_position));

                            if ((relative.z() >= min_corner.z()) and (relative.z() < max_corner.z())) {
                                const walls: [4]WallTestData = .{
                                    .{
                                        .x = min_corner.x(),
                                        .rel_x = relative.x(),
                                        .rel_y = relative.y(),
                                        .delta_x = entity_delta.x(),
                                        .delta_y = entity_delta.y(),
                                        .min_y = min_corner.y(),
                                        .max_y = max_corner.y(),
                                        .normal = Vector3.new(-1, 0, 0),
                                    },
                                    .{
                                        .x = max_corner.x(),
                                        .rel_x = relative.x(),
                                        .rel_y = relative.y(),
                                        .delta_x = entity_delta.x(),
                                        .delta_y = entity_delta.y(),
                                        .min_y = min_corner.y(),
                                        .max_y = max_corner.y(),
                                        .normal = Vector3.new(1, 0, 0),
                                    },
                                    .{
                                        .x = min_corner.y(),
                                        .rel_x = relative.y(),
                                        .rel_y = relative.x(),
                                        .delta_x = entity_delta.y(),
                                        .delta_y = entity_delta.x(),
                                        .min_y = min_corner.x(),
                                        .max_y = max_corner.x(),
                                        .normal = Vector3.new(0, -1, 0),
                                    },
                                    .{
                                        .x = max_corner.y(),
                                        .rel_x = relative.y(),
                                        .rel_y = relative.x(),
                                        .delta_x = entity_delta.y(),
                                        .delta_y = entity_delta.x(),
                                        .min_y = min_corner.x(),
                                        .max_y = max_corner.x(),
                                        .normal = Vector3.new(0, 1, 0),
                                    },
                                };

                                var test_min_time = min_time;
                                var hit_this = false;
                                var test_wall_normal = Vector3.zero();
                                var wall_index: u32 = 0;

                                while (wall_index < walls.len) : (wall_index += 1) {
                                    const wall = &walls[wall_index];

                                    if (wall.delta_x != 0.0) {
                                        const result_time = (wall.x - wall.rel_x) / wall.delta_x;
                                        const y = wall.rel_y + (result_time * wall.delta_y);
                                        if (result_time >= 0 and test_min_time > result_time) {
                                            if (y >= wall.min_y and y <= wall.max_y) {
                                                test_min_time = @max(0.0, result_time - time_epsilon);
                                                test_wall_normal = wall.normal;
                                                hit_this = true;
                                            }
                                        }
                                    }
                                }

                                if (hit_this) {
                                    const test_position = entity.position.plus(entity_delta.scaledTo(test_min_time));
                                    if (speculativeCollide(entity, test_entity, test_position)) {
                                        min_time = test_min_time;
                                        wall_normal_min = test_wall_normal;
                                        opt_hit_entity_min = test_entity;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            var wall_normal = Vector3.zero();
            var opt_hit_entity: ?*Entity = null;
            var stop_time: f32 = 0;

            if (min_time < max_time) {
                stop_time = min_time;
                opt_hit_entity = opt_hit_entity_min;
                wall_normal = wall_normal_min;
            } else {
                stop_time = max_time;
                opt_hit_entity = opt_hit_entity_max;
                wall_normal = wall_normal_max;
            }

            // Apply the amount of delta allowed by collision detection.
            entity.position = entity.position.plus(entity_delta.scaledTo(stop_time));
            distance_remaining -= stop_time * entity_delta_length;

            if (opt_hit_entity) |hit_entity| {
                // Remove the applied delta.
                entity_delta = desired_position.minus(entity.position);

                const stops_on_collision = handleCollision(entity, hit_entity);
                if (stops_on_collision) {
                    // Remove velocity that is facing into the wall.
                    entity_delta = entity_delta.minus(wall_normal.scaledTo(entity_delta.dotProduct(wall_normal)));
                    entity.velocity = entity.velocity.minus(wall_normal.scaledTo(entity.velocity.dotProduct(wall_normal)));
                }
            } else {
                break;
            }
        } else {
            break;
        }
    }

    if (entity.distance_limit != 0) {
        entity.distance_limit = distance_remaining;
    }
}

pub fn endWorldChange(world_mode: *GameModeWorld, world_ptr: *World, sim_region: *SimRegion) void {
    TimedBlock.beginFunction(@src(), .EndWorldChange);
    defer TimedBlock.endFunction(@src(), .EndWorldChange);

    var sim_entity_index: u32 = 0;
    while (sim_entity_index < sim_region.entity_count) : (sim_entity_index += 1) {
        const entity = &sim_region.entities[sim_entity_index];

        if (!entity.hasFlag(EntityFlags.Deleted.toInt())) {
            const entity_position: world.WorldPosition =
                world.mapIntoChunkSpace(world_ptr, sim_region.origin, entity.position);
            var chunk_position: world.WorldPosition = entity_position;
            chunk_position.offset = .zero();

            const chunk_delta: Vector3 = entity_position.offset.minus(entity.position);

            // Update camera position.
            if (entity.id.value == world_mode.camera_following_entity_index.value) {
                var new_camera_position = world_mode.camera_position;
                const room_delta: Vector3 = .new(24, 12.5, world_mode.typical_floor_height);
                const h_room_delta: Vector3 = room_delta.scaledTo(0.5);
                const apron_size: f32 = 0.7;
                const bounce_height: f32 = 0.5;
                const h_room_apron: Vector3 = .new(
                    h_room_delta.x() - apron_size,
                    h_room_delta.y() - apron_size,
                    h_room_delta.z() - apron_size,
                );

                if (global_config.Renderer_Camera_RoomBased) {
                    world_mode.camera_offset = .zero();

                    var applied_delta: Vector3 = .zero();
                    for (0..3) |e| {
                        if (entity.position.values[e] > h_room_delta.values[e]) {
                            applied_delta.values[e] = room_delta.values[e];
                            new_camera_position = world.mapIntoChunkSpace(
                                world_mode.world,
                                new_camera_position,
                                applied_delta,
                            );
                        }
                        if (entity.position.values[e] < -h_room_delta.values[e]) {
                            applied_delta.values[e] = -room_delta.values[e];
                            new_camera_position = world.mapIntoChunkSpace(
                                world_mode.world,
                                new_camera_position,
                                applied_delta,
                            );
                        }
                    }

                    const new_entity_position: Vector3 = entity.position.minus(applied_delta);
                    if (new_entity_position.x() > h_room_apron.x()) {
                        const t: f32 = math.clamp01MapToRange(h_room_apron.x(), h_room_delta.x(), new_entity_position.x());
                        world_mode.camera_offset = .new(t * h_room_delta.x(), 0, (-(t * t) + 2 * t) * bounce_height);
                    }
                    if (new_entity_position.x() < -h_room_apron.x()) {
                        const t: f32 = math.clamp01MapToRange(-h_room_apron.x(), -h_room_delta.x(), new_entity_position.x());
                        world_mode.camera_offset = .new(-t * h_room_delta.x(), 0, (-(t * t) + 2 * t) * bounce_height);
                    }
                    if (new_entity_position.y() > h_room_apron.y()) {
                        const t: f32 = math.clamp01MapToRange(h_room_apron.y(), h_room_delta.y(), new_entity_position.y());
                        world_mode.camera_offset = .new(0, t * h_room_delta.y(), (-(t * t) + 2 * t) * bounce_height);
                    }
                    if (new_entity_position.y() < -h_room_apron.y()) {
                        const t: f32 = math.clamp01MapToRange(-h_room_apron.y(), -h_room_delta.y(), new_entity_position.y());
                        world_mode.camera_offset = .new(0, -t * h_room_delta.y(), (-(t * t) + 2 * t) * bounce_height);
                    }
                    if (new_entity_position.z() > h_room_apron.z()) {
                        const t: f32 = math.clamp01MapToRange(h_room_apron.z(), h_room_delta.z(), new_entity_position.z());
                        world_mode.camera_offset = .new(0, 0, t * h_room_delta.z());
                    }
                    if (new_entity_position.z() < -h_room_apron.z()) {
                        const t: f32 = math.clamp01MapToRange(-h_room_apron.z(), -h_room_delta.z(), new_entity_position.z());
                        world_mode.camera_offset = .new(0, 0, -t * h_room_delta.z());
                    }
                } else {
                    new_camera_position = entity_position;
                }

                world_mode.camera_position = new_camera_position;
            }

            // const old_entity_position: Vector3 = entity.position;
            entity.position = entity.position.plus(chunk_delta);
            var dest_e: *Entity = world.useChunkSpaceAt(world_mode.world, @sizeOf(Entity), chunk_position);

            dest_e.* = entity.*;
            packTraversableReference(sim_region, &dest_e.occupying);
            packTraversableReference(sim_region, &dest_e.came_from);
            packTraversableReference(sim_region, &dest_e.auto_boost_to);

            dest_e.acceleration = .zero();
            dest_e.bob_acceleration = 0;

            // const reverse_chunk_delta: Vector3 =
            //     world.subtractPositions(sim_region.world, &chunk_position, &sim_region.origin);
            // const test_position: Vector3 = entity.position.plus(reverse_chunk_delta);
            // std.debug.assert(old_entity_position.z() == test_position.z());
        }
    }
}

pub const TraversableSearchFlag = enum(u8) {
    Unoccupied = 0x1,
};

pub fn getClosestTraversable(
    sim_region: *SimRegion,
    from_position: Vector3,
    result: *TraversableReference,
    flags: u32,
) bool {
    TimedBlock.beginFunction(@src(), .GetClosestTraversable);
    defer TimedBlock.endFunction(@src(), .GetClosestTraversable);

    var found: bool = false;
    var closest_distance_squared: f32 = math.square(1000);
    var hero_entity_index: u32 = 0;
    while (hero_entity_index < sim_region.entity_count) : (hero_entity_index += 1) {
        const test_entity = &sim_region.entities[hero_entity_index];
        var point_index: u32 = 0;
        while (point_index < test_entity.traversable_count) : (point_index += 1) {
            const point: EntityTraversablePoint = test_entity.getSimSpaceTraversable(point_index);

            if ((flags & @intFromEnum(TraversableSearchFlag.Unoccupied) == 0) or point.occupier == null) {
                var to_point: Vector3 = point.position.minus(from_position);

                // _ = to_point.setZ(math.clampAboveZero(intrinsics.absoluteValue(to_point.z() - 1.5)));

                const test_distance_squared = to_point.lengthSquared();
                if (closest_distance_squared > test_distance_squared) {
                    result.entity.ptr = test_entity;
                    result.entity.index = test_entity.id;
                    result.index = point_index;
                    closest_distance_squared = test_distance_squared;
                    found = true;
                }
            }
        }
    }

    if (!found) {
        result.* = .init;
    }

    return found;
}

pub fn getClosestTraversableAlongRay(
    sim_region: *SimRegion,
    from_position: Vector3,
    direction: Vector3,
    skip: TraversableReference,
    result: *TraversableReference,
    flags: u32,
) bool {
    TimedBlock.beginFunction(@src(), .GetClosestTraversableAlongRay);
    defer TimedBlock.endFunction(@src(), .GetClosestTraversableAlongRay);

    var found: bool = false;

    var probe_index: u32 = 0;
    while (probe_index < 5) : (probe_index += 1) {
        const sample_position: Vector3 =
            from_position.plus(direction.scaledTo(0.5 * @as(f32, @floatFromInt(probe_index))));

        if (getClosestTraversable(sim_region, sample_position, result, flags)) {
            if (!skip.equals(result.*)) {
                found = true;
                break;
            }
        }
    }

    return found;
}

pub const ClosestEntity = struct {
    entity: ?*Entity = null,
    delta: Vector3 = .zero(),
    distance_squared: f32 = 0,
};

pub fn getClosestEntityWithBrain(
    sim_region: *SimRegion,
    position: Vector3,
    brain_type: BrainType,
    opt_max_radius: ?f32,
) ClosestEntity {
    var result: ClosestEntity = .{};
    result.distance_squared = math.square(opt_max_radius orelse 20);

    var test_entity_index: u32 = 0;
    while (test_entity_index < sim_region.entity_count) : (test_entity_index += 1) {
        var test_entity = &sim_region.entities[test_entity_index];
        if (test_entity.brain_slot.isType(brain_type)) {
            const test_delta = test_entity.position.minus(position);
            const test_distance = test_delta.lengthSquared();

            if (result.distance_squared > test_distance) {
                result.entity = test_entity;
                result.distance_squared = test_distance;
                result.delta = test_delta;
            }
        }
    }

    return result;
}
