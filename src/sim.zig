const shared = @import("shared.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const world = @import("world.zig");
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

pub const EntityReference = packed union {
    ptr: ?*Entity,
    index: EntityId,
};

pub const EntityHash = extern struct {
    ptr: ?*Entity = null,
    index: EntityId = .{},
};

pub const EntityFlags = enum(u32) {
    Collides = (1 << 0),
    Nonspatial = (1 << 1),
    Movable = (1 << 2),

    Simming = (1 << 30),

    pub fn toInt(self: EntityFlags) u32 {
        return @intFromEnum(self);
    }
};

pub const EntityCollisionVolume = extern struct {
    offset_position: Vector3,
    dimension: Vector3,
};

pub const EntityTraversablePoint = extern struct {
    position: Vector3,
};

pub const EntityCollisionVolumeGroup = extern struct {
    total_volume: EntityCollisionVolume,

    volume_count: u32,
    volumes: [*]EntityCollisionVolume,

    traversable_count: u32,
    traversables: [*]EntityTraversablePoint,

    pub fn getSpaceVolume(self: *const EntityCollisionVolumeGroup, index: u32) EntityCollisionVolume {
        return self.volumes[index];
    }
};

pub const MovementMode = enum(u32) {
    Planted,
    Hopping,
};

pub const EntityId = packed struct {
    value: u32 = 0,
};

pub const Entity = extern struct {
    storage_index: EntityId = .{},
    updatable: bool = false,

    type: EntityType = .Null,
    flags: u32 = 0,

    chunk_position: world.WorldPosition = undefined,
    position: Vector3 = Vector3.zero(),
    velocity: Vector3 = Vector3.zero(),

    collision: *EntityCollisionVolumeGroup,

    distance_limit: f32 = 0,

    facing_direction: f32 = 0,
    bob_time: f32 = 0,
    bob_delta_time: f32 = 0,

    abs_tile_z_delta: i32 = 0,

    hit_point_max: u32,
    hit_points: [16]HitPoint,

    head: EntityReference = undefined,

    walkable_dimension: Vector2,
    walkable_height: f32 = 0,

    movement_mode: MovementMode,
    movement_time: f32,
    movement_from: Vector3,
    movement_to: Vector3,

    x_axis: Vector2,
    y_axis: Vector2,

    floor_displace: Vector2,

    pub fn isSet(self: *const Entity, flag: u32) bool {
        return (self.flags & flag) != 0;
    }

    pub fn addFlags(self: *Entity, flags: u32) void {
        self.flags = self.flags | flags;
    }

    pub fn clearFlags(self: *Entity, flags: u32) void {
        self.flags = self.flags & ~flags;
    }

    pub fn makeNonSpatial(self: *Entity) void {
        self.addFlags(EntityFlags.Nonspatial.toInt());
        self.position = Vector3.invalidPosition();
    }

    pub fn makeSpatial(self: *Entity, position: Vector3, velocity: Vector3) void {
        self.clearFlags(EntityFlags.Nonspatial.toInt());
        self.position = position;
        self.velocity = velocity;
    }

    pub fn getGroundPoint(self: *const Entity) Vector3 {
        return self.position;
    }

    pub fn getGroundPointFor(self: *const Entity, position: Vector3) Vector3 {
        _ = self;
        return position;
    }

    pub fn getStairGround(self: *const Entity, at_ground_point: Vector3) f32 {
        std.debug.assert(self.type == .Stairwell);

        const region_rectangle = Rectangle2.fromCenterDimension(self.position.xy(), self.walkable_dimension);
        const barycentric = region_rectangle.getBarycentricPosition(at_ground_point.xy()).clamp01();
        return self.position.z() + barycentric.y() * self.walkable_height;
    }

    pub fn getTraversable(self: *const Entity, index: u32) EntityTraversablePoint {
        std.debug.assert(index < self.collision.traversable_count);

        var result = self.collision.traversables[index];
        result.position = result.position.plus(self.position);

        return result;
    }
};

pub const EntityType = enum(u8) {
    Null,

    HeroBody,
    HeroHead,
    Wall,
    Floor,
    Familiar,
    Monster,
    Sword,
    Stairwell,
};

pub const HitPoint = extern struct {
    flags: u8,
    filled_amount: u8,
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

pub fn getHashFromStorageIndex(sim_region: *SimRegion, storage_index: EntityId) ?*EntityHash {
    std.debug.assert(storage_index.value != 0);

    var result: ?*EntityHash = null;

    const hash_value = storage_index.value;
    var offset: u32 = 0;

    while (offset < sim_region.sim_entity_hash.len) : (offset += 1) {
        const hash_mask = sim_region.sim_entity_hash.len - 1;
        const hash_index = (hash_value + offset) & hash_mask;
        const entry = &sim_region.sim_entity_hash[hash_index];

        if (entry.index.value == 0 or entry.index.value == storage_index.value) {
            result = entry;
            break;
        }
    }

    return result;
}

pub fn getEntityByStorageIndex(sim_region: *SimRegion, storage_index: EntityId) ?*Entity {
    const entry = getHashFromStorageIndex(sim_region, storage_index);
    return entry.ptr;
}

pub fn loadEntityReference(world_mode: *GameModeWorld, sim_region: *SimRegion, reference: *EntityReference) void {
    _ = world_mode;

    if (reference.index.value != 0) {
        const entry = getHashFromStorageIndex(sim_region, reference.index);
        reference.* = EntityReference{ .ptr = if (entry != null) entry.?.ptr else null };
    }
}

pub fn storeEntityReference(reference: *EntityReference) void {
    if (reference.ptr) |ptr| {
        reference.* = EntityReference{ .index = ptr.storage_index };
    }
}

pub fn addEntityRaw(
    world_mode: *GameModeWorld,
    sim_region: *SimRegion,
    storage_index: EntityId,
    opt_source: ?*Entity,
) ?*Entity {
    TimedBlock.beginFunction(@src(), .AddEntityRaw);
    defer TimedBlock.endFunction(@src(), .AddEntityRaw);

    std.debug.assert(storage_index.value != 0);

    var entity: ?*Entity = null;

    if (getHashFromStorageIndex(sim_region, storage_index)) |entry| {
        if (entry.ptr == null) {
            if (sim_region.entity_count < sim_region.max_entity_count) {
                entity = &sim_region.entities[sim_region.entity_count];
                sim_region.entity_count += 1;

                entry.index = storage_index;
                entry.ptr = entity.?;

                if (opt_source) |source| {
                    entity.?.* = source.*;
                    loadEntityReference(world_mode, sim_region, &entity.?.head);

                    std.debug.assert(!source.isSet(EntityFlags.Simming.toInt()));
                    source.addFlags(EntityFlags.Simming.toInt());
                }

                entity.?.storage_index = storage_index;
                entity.?.updatable = false;
            } else {
                unreachable;
            }
        }
    }

    return entity;
}

fn getSimSpacePosition(sim_region: *SimRegion, entity: *Entity) Vector3 {
    var result = Vector3.invalidPosition();

    if (!entity.isSet(EntityFlags.Nonspatial.toInt())) {
        result = world.subtractPositions(sim_region.world, &entity.chunk_position, &sim_region.origin);
    }

    return result;
}

pub fn entityOverlapsRectangle(position: Vector3, volume: EntityCollisionVolume, rectangle: Rectangle3) bool {
    const grown = rectangle.addRadius(volume.dimension.scaledTo(0.5));
    return position.plus(volume.offset_position).isInRectangle(grown);
}

pub fn addEntity(
    world_mode: *GameModeWorld,
    sim_region: *SimRegion,
    storage_index: EntityId,
    source: *Entity,
    opt_sim_position: ?*Vector3,
) ?*Entity {
    const opt_entity = addEntityRaw(world_mode, sim_region, storage_index, source);

    if (opt_entity) |sim_entity| {
        if (opt_sim_position) |sim_position| {
            sim_entity.position = sim_position.*;
            sim_entity.updatable = entityOverlapsRectangle(
                sim_entity.position,
                sim_entity.collision.total_volume,
                sim_region.updatable_bounds,
            );
        } else {
            sim_entity.position = getSimSpacePosition(sim_region, source);
        }
    }

    return opt_entity;
}

pub fn beginSimulation(
    world_mode: *GameModeWorld,
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
                    var opt_block: ?*world.WorldEntityBlock = chunk.first_block;
                    while (opt_block) |block| {
                        var entity_index: u32 = 0;
                        while (entity_index < block.entity_count) : (entity_index += 1) {
                            const entities: [*]Entity = @ptrCast(@alignCast(&block.entity_data));
                            var entity = &entities[entity_index];

                            if (!entity.isSet(EntityFlags.Nonspatial.toInt())) {
                                var sim_space_position = getSimSpacePosition(sim_region, entity);

                                if (entityOverlapsRectangle(
                                    sim_space_position,
                                    entity.collision.total_volume,
                                    sim_region.bounds,
                                )) {
                                    _ = addEntity(
                                        world_mode,
                                        sim_region,
                                        entity.storage_index,
                                        entity,
                                        &sim_space_position,
                                    );
                                }
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
        if (a.storage_index.value > b.storage_index.value) {
            const temp = a;
            a = b;
            b = temp;
        }

        // Basic rules.
        if (a.isSet(EntityFlags.Collides.toInt()) and
            b.isSet(EntityFlags.Collides.toInt()))
        {
            if (!a.isSet(EntityFlags.Nonspatial.toInt()) and
                !b.isSet(EntityFlags.Nonspatial.toInt()))
            {
                result = true;
            }

            // Specific rules.
            const hash_bucket = a.storage_index.value & ((world_mode.collision_rule_hash.len) - 1);
            var opt_rule: ?*PairwiseCollisionRule = world_mode.collision_rule_hash[hash_bucket];
            while (opt_rule) |rule| : (opt_rule = rule.next_in_hash) {
                if ((rule.storage_index_a == a.storage_index.value) and
                    (rule.storage_index_b == b.storage_index.value)) {
                    result = rule.can_collide;
                    break;
                }
            }
        }
    }

    return result;
}

pub fn handleCollision(world_mode: *GameModeWorld, entity: *Entity, hit_entity: *Entity) bool {
    var stops_on_collision = false;

    if (entity.type == .Sword) {
        // Stop future collisons between these entities.
        world_mode.addCollisionRule(entity.storage_index.value, hit_entity.storage_index.value, false);

        stops_on_collision = false;
    } else {
        stops_on_collision = true;
    }

    var a = entity;
    var b = hit_entity;

    // Sort entities based on type.
    if (@intFromEnum(a.type) > @intFromEnum(b.type)) {
        const temp = a;
        a = b;
        b = temp;
    }

    if (a.type == .Monster and b.type == .Sword) {
        if (a.hit_point_max > 0) {
            a.hit_point_max -= 1;
        }
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

    std.debug.assert(!entity.isSet(EntityFlags.Nonspatial.toInt()));

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

            if (!entity.isSet(EntityFlags.Nonspatial.toInt())) {
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

        const chunk_position: world.WorldPosition =
            world.mapIntoChunkSpace(world_mode.world, sim_region.origin, entity.position);

        storeEntityReference(&entity.head);

        // Update camera position.
        if (entity.storage_index.value == world_mode.camera_following_entity_index.value) {
            var new_camera_position = world_mode.camera_position;
            new_camera_position.chunk_z = chunk_position.chunk_z;

            if (global_config.Renderer_Camera_RoomBased) {
                if (entity.position.x() > 9.0) {
                    new_camera_position = world.mapIntoChunkSpace(world_mode.world, new_camera_position, Vector3.new(18, 0, 0));
                } else if (entity.position.x() < -9.0) {
                    new_camera_position = world.mapIntoChunkSpace(world_mode.world, new_camera_position, Vector3.new(-18, 0, 0));
                }
                if (entity.position.y() > 5.0) {
                    new_camera_position = world.mapIntoChunkSpace(world_mode.world, new_camera_position, Vector3.new(0, 10, 0));
                } else if (entity.position.y() < -5.0) {
                    new_camera_position = world.mapIntoChunkSpace(world_mode.world, new_camera_position, Vector3.new(0, -10, 0));
                }
            } else {
                new_camera_position = chunk_position;
            }

            world_mode.camera_position = new_camera_position;
        }

        world.packEntityIntoWorld(world_mode.world, entity, chunk_position);
    }
}
