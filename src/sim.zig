const shared = @import("shared.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const world = @import("world.zig");
const entities = @import("entities.zig");
const config = @import("config.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

var global_config = &@import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const GameModeWorld = @import("world_mode.zig").GameModeWorld;
const PairwiseCollisionRule = @import("world_mode.zig").PairwiseCollisionRule;
const World = world.World;
const Entity = entities.Entity;
const EntityId = entities.EntityId;
const EntityReference = entities.EntityReference;
const EntityCollisionVolume = entities.EntityCollisionVolume;
const EntityFlags = entities.EntityFlags;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const ArenaPushParams = shared.ArenaPushParams;

pub const SimRegion = extern struct {
    world: *World,
    max_entity_radius: f32,
    max_entity_velocity: f32,

    origin: world.WorldPosition,
    bounds: Rectangle3,
    updatable_bounds: Rectangle3,

    max_entity_count: u32,
    entity_count: u32 = 0,
    entities: [*]Entity,

    sim_entity_hash: [4096]EntityHash = [1]EntityHash{undefined} ** 4096,
};

pub const EntityHash = extern struct {
    ptr: ?*Entity = null,
    index: EntityId = .{},
};

pub const MoveSpec = struct {
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

pub fn getHashFromId(sim_region: *SimRegion, id: EntityId) ?*EntityHash {
    std.debug.assert(id.value != 0);

    var result: ?*EntityHash = null;

    const hash_value = id.value;
    var offset: u32 = 0;

    while (offset < sim_region.sim_entity_hash.len) : (offset += 1) {
        const hash_mask = sim_region.sim_entity_hash.len - 1;
        const hash_index = (hash_value + offset) & hash_mask;
        const entry = &sim_region.sim_entity_hash[hash_index];

        if (entry.index.value == 0 or entry.index.value == id.value) {
            result = entry;
            break;
        }
    }

    return result;
}

pub fn getEntityByStorageIndex(sim_region: *SimRegion, id: EntityId) ?*Entity {
    const entry = getHashFromId(sim_region, id);
    return entry.ptr;
}

pub fn loadEntityReference(sim_region: *SimRegion, reference: *EntityReference) void {
    if (reference.index.value != 0) {
        const entry = getHashFromId(sim_region, reference.index);
        reference.* = EntityReference{ .ptr = if (entry != null) entry.?.ptr else null };
    }
}

pub fn storeEntityReference(reference: *EntityReference) void {
    if (reference.ptr) |ptr| {
        reference.* = EntityReference{ .index = ptr.id };
    }
}

pub fn entityOverlapsRectangle(position: Vector3, volume: EntityCollisionVolume, rectangle: Rectangle3) bool {
    const grown = rectangle.addRadius(volume.dimension.scaledTo(0.5));
    return position.plus(volume.offset_position).isInRectangle(grown);
}

fn addEntity(
    sim_region: *SimRegion,
    opt_source: ?*Entity,
    chunk_delta: Vector3,
) void {
    const id: EntityId = opt_source.?.id;

    if (getHashFromId(sim_region, id)) |entry| {
        std.debug.assert(entry.ptr == null);

        if (sim_region.entity_count < sim_region.max_entity_count) {
            const dest: *Entity = &sim_region.entities[sim_region.entity_count];
            sim_region.entity_count += 1;

            entry.index = id;
            entry.ptr = dest;

            if (opt_source) |source| {
                dest.* = source.*;
            }

            dest.id = id;
            dest.position = dest.position.plus(chunk_delta);
            dest.movement_from = dest.movement_from.plus(chunk_delta);
            dest.movement_to = dest.movement_to.plus(chunk_delta);

            dest.updatable = entityOverlapsRectangle(
                dest.position,
                dest.collision.total_volume,
                sim_region.updatable_bounds,
            );
        } else {
            unreachable;
        }
    }
}

pub fn deleteEntity(sim_region: *SimRegion, entity: *Entity) void {
    _ = sim_region;
    entity.addFlags(EntityFlags.Deleted.toInt());
}

fn connectEntityPointers(sim_region: *SimRegion) void {
    var entity_index: u32 = 0;
    while (entity_index < sim_region.entity_count) : (entity_index += 1) {
        const entity: *Entity = &sim_region.entities[entity_index];
        loadEntityReference(sim_region, &entity.head);
    }
}

pub fn beginSimulation(
    sim_arena: *shared.MemoryArena,
    game_world: *World,
    origin: world.WorldPosition,
    bounds: Rectangle3,
    delta_time: f32,
) *SimRegion {
    TimedBlock.beginFunction(@src(), .BeginSimulation);
    defer TimedBlock.endFunction(@src(), .BeginSimulation);

    var sim_region: *SimRegion = sim_arena.pushStruct(SimRegion, ArenaPushParams.aligned(@alignOf(SimRegion), true));

    sim_region.max_entity_radius = 5;
    sim_region.max_entity_velocity = 30;
    const update_safety_margin = sim_region.max_entity_radius + sim_region.max_entity_velocity * delta_time;
    const update_safety_margin_z = 1;

    sim_region.world = game_world;
    sim_region.origin = origin;
    sim_region.updatable_bounds = bounds.addRadius(
        Vector3.new(sim_region.max_entity_radius, sim_region.max_entity_radius, 0),
    );
    sim_region.bounds = sim_region.updatable_bounds.addRadius(
        Vector3.new(update_safety_margin, update_safety_margin, update_safety_margin_z),
    );
    sim_region.max_entity_count = 4096;
    sim_region.entity_count = 0;
    sim_region.entities = sim_arena.pushArray(sim_region.max_entity_count, Entity, null);

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

    var chunk_z = min_chunk_position.chunk_z;
    while (chunk_z <= max_chunk_position.chunk_z) : (chunk_z += 1) {
        var chunk_y = min_chunk_position.chunk_y;
        while (chunk_y <= max_chunk_position.chunk_y) : (chunk_y += 1) {
            var chunk_x = min_chunk_position.chunk_x;
            while (chunk_x <= max_chunk_position.chunk_x) : (chunk_x += 1) {
                const opt_chunk = world.removeWorldChunk(sim_region.world, chunk_x, chunk_y, chunk_z);

                if (opt_chunk) |chunk| {
                    const chunk_position: world.WorldPosition = .{
                        .chunk_x = chunk_x,
                        .chunk_y = chunk_y,
                        .chunk_z = chunk_z,
                        .offset = .zero(),
                    };
                    const chunk_delta: Vector3 =
                        world.subtractPositions(sim_region.world, &chunk_position, &sim_region.origin);
                    var opt_block: ?*world.WorldEntityBlock = chunk.first_block;
                    while (opt_block) |block| {
                        var entity_index: u32 = 0;
                        while (entity_index < block.entity_count) : (entity_index += 1) {
                            const source_address = @intFromPtr(&block.entity_data);
                            const source: usize = std.mem.alignForward(usize, source_address, @alignOf(Entity));
                            const entities_ptr: [*]Entity = @ptrFromInt(source);
                            const entity = &entities_ptr[entity_index];
                            const sim_space_position = entity.position.plus(chunk_delta);

                            if (entityOverlapsRectangle(
                                sim_space_position,
                                entity.collision.total_volume,
                                sim_region.bounds,
                            )) {
                                _ = addEntity(
                                    sim_region,
                                    entity,
                                    chunk_delta,
                                );
                            }
                        }

                        const next_block: ?*world.WorldEntityBlock = block.next;
                        world.addBlockToFreeList(sim_region.world, block);
                        opt_block = next_block;
                    }

                    world.addChunkToFreeList(sim_region.world, chunk);
                }
            }
        }
    }

    connectEntityPointers(sim_region);

    return sim_region;
}

fn speculativeCollide(mover: *Entity, region: *Entity, test_position: Vector3) bool {
    TimedBlock.beginFunction(@src(), .SpeculativeCollide);
    defer TimedBlock.endFunction(@src(), .SpeculativeCollide);

    var result = true;

    if (region.type == .Stairwell) {
        const step_height = 0.1;
        const mover_ground_point = mover.getGroundPointFor(test_position);
        const ground = region.getStairGround(mover_ground_point);
        result = ((intrinsics.absoluteValue(mover_ground_point.z() - ground) > step_height));
    }

    return result;
}

fn entitiesOverlap(entity: *Entity, test_entity: *Entity, epsilon: Vector3) bool {
    TimedBlock.beginFunction(@src(), .EntitiesOverlap);
    defer TimedBlock.endFunction(@src(), .EntitiesOverlap);

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

fn canCollide(world_mode: *GameModeWorld, entity: *Entity, hit_entity: *Entity) bool {
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
        if (a.isSet(EntityFlags.Collides.toInt()) and
            b.isSet(EntityFlags.Collides.toInt()))
        {
            result = true;

            // Specific rules.
            const hash_bucket = a.id.value & ((world_mode.collision_rule_hash.len) - 1);
            var opt_rule: ?*PairwiseCollisionRule = world_mode.collision_rule_hash[hash_bucket];
            while (opt_rule) |rule| : (opt_rule = rule.next_in_hash) {
                if ((rule.id_a == a.id.value) and
                    (rule.id_b == b.id.value))
                {
                    result = rule.can_collide;
                    break;
                }
            }
        }
    }

    return result;
}

pub fn handleCollision(world_mode: *GameModeWorld, entity: *Entity, hit_entity: *Entity) bool {
    _ = world_mode;

    const stops_on_collision = true;
    var a = entity;
    var b = hit_entity;

    // Sort entities based on type.
    if (@intFromEnum(a.type) > @intFromEnum(b.type)) {
        const temp = a;
        a = b;
        b = temp;
    }

    return stops_on_collision;
}

pub fn moveEntity(
    world_mode: *GameModeWorld,
    sim_region: *SimRegion,
    entity: *Entity,
    delta_time: f32,
    in_acceleration: Vector3,
    move_spec: *const MoveSpec,
) void {
    TimedBlock.beginFunction(@src(), .MoveEntity);
    defer TimedBlock.endFunction(@src(), .MoveEntity);

    var acceleration = in_acceleration;

    // Correct speed when multiple axes are contributing to the direction.
    if (move_spec.unit_max_acceleration) {
        const direction_length = acceleration.lengthSquared();
        if (direction_length > 1.0) {
            acceleration = acceleration.scaledTo(1.0 / intrinsics.squareRoot(direction_length));
        }
    }

    // Calculate acceleration.
    acceleration = acceleration.scaledTo(move_spec.speed);

    // Add drag to acceleration.
    acceleration = acceleration.plus(entity.velocity.scaledTo(move_spec.drag).negated());
    _ = acceleration.setZ(0);

    // Calculate movement delta.
    var entity_delta = acceleration.scaledTo(0.5 * math.square(delta_time))
        .plus(entity.velocity.scaledTo(delta_time));
    entity.velocity = acceleration.scaledTo(delta_time).plus(entity.velocity);

    std.debug.assert(entity.velocity.lengthSquared() <= math.square(sim_region.max_entity_velocity));

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
                    canCollide(world_mode, entity, test_entity))
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

                const stops_on_collision = handleCollision(world_mode, entity, hit_entity);
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

pub fn endSimulation(world_mode: *GameModeWorld, sim_region: *SimRegion) void {
    TimedBlock.beginFunction(@src(), .EndSimulation);
    defer TimedBlock.endFunction(@src(), .EndSimulation);

    var sim_entity_index: u32 = 0;
    while (sim_entity_index < sim_region.entity_count) : (sim_entity_index += 1) {
        const entity = &sim_region.entities[sim_entity_index];

        if (!entity.isSet(EntityFlags.Deleted.toInt())) {
            const entity_position: world.WorldPosition =
                world.mapIntoChunkSpace(world_mode.world, sim_region.origin, entity.position);
            var chunk_position: world.WorldPosition = entity_position;
            chunk_position.offset = .zero();

            const chunk_delta: Vector3 =
                world.subtractPositions(sim_region.world, &chunk_position, &sim_region.origin).negated();

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

            entity.position = entity.position.plus(chunk_delta);
            entity.movement_from = entity.movement_from.plus(chunk_delta);
            entity.movement_to = entity.movement_to.plus(chunk_delta);
            storeEntityReference(&entity.head);
            world.packEntityIntoWorld(world_mode.world, entity, entity_position);
        }
    }
}
