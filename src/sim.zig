const shared = @import("shared.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const world = @import("world.zig");
const std = @import("std");

const addCollisionRule = @import("handmade.zig").addCollisionRule;

// Types.
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const State = shared.State;
const World = world.World;

pub const SimRegion = struct {
    world: *World,
    max_entity_radius: f32,
    max_entity_velocity: f32,

    origin: world.WorldPosition,
    bounds: Rectangle3,
    updatable_bounds: Rectangle3,

    max_entity_count: u32,
    entity_count: u32 = 0,
    entities: [*]SimEntity,

    sim_entity_hash: [4096]SimEntityHash = [1]SimEntityHash{undefined} ** 4096,
};

const EntityReferenceTag = enum { ptr, index };
pub const EntityReference = union(EntityReferenceTag) {
    ptr: ?*SimEntity,
    index: u32,
};

pub const SimEntityHash = struct {
    ptr: ?*SimEntity = null,
    index: u32 = 0,
};

pub const SimEntityFlags = enum(u32) {
    Collides = (1 << 0),
    Nonspatial = (1 << 1),
    Movable = (1 << 2),
    ZSupported = (1 << 4),

    Simming = (1 << 30),

    pub fn toInt(self: SimEntityFlags) u32 {
        return @intFromEnum(self);
    }
};

pub const SimEntity = struct {
    storage_index: u32 = 0,
    updatable: bool = false,

    type: EntityType = .Null,
    flags: u32 = 0,

    position: Vector3 = Vector3.zero(),
    velocity: Vector3 = Vector3.zero(),
    dimension: Vector3 = Vector3.zero(),

    distance_limit: f32 = 0,

    facing_direction: u32 = undefined,
    head_bob_time: f32 = 0,

    abs_tile_z_delta: i32 = 0,

    hit_point_max: u32,
    hit_points: [16]HitPoint,

    sword: EntityReference = null,

    pub fn isSet(self: *const SimEntity, flag: u32) bool {
        return (self.flags & flag) != 0;
    }

    pub fn addFlags(self: *SimEntity, flags: u32) void {
        self.flags = self.flags | flags;
    }

    pub fn clearFlags(self: *SimEntity, flags: u32) void {
        self.flags = self.flags & ~flags;
    }

    pub fn makeNonSpatial(self: *SimEntity) void {
        self.addFlags(SimEntityFlags.Nonspatial.toInt());
        self.position = Vector3.invalidPosition();
    }

    pub fn makeSpatial(self: *SimEntity, position: Vector3, velocity: Vector3) void {
        self.clearFlags(SimEntityFlags.Nonspatial.toInt());
        self.position = position;
        self.velocity = velocity;
    }
};

pub const EntityType = enum(u8) {
    Null,
    Hero,
    Wall,
    Familiar,
    Monster,
    Sword,
    Stairwell,
};

pub const HitPoint = struct {
    flags: u8,
    filled_amount: u8,
};

pub const MoveSpec = struct {
    speed: f32 = 1.0,
    drag: f32 = 0.0,
    unit_max_acceleration: bool = false,
};

fn getLowEntity(state: *State, index: u32) ?*shared.LowEntity {
    var entity: ?*shared.LowEntity = null;

    if (index > 0 and index < state.low_entity_count) {
        entity = &state.low_entities[index];
    }

    return entity;
}

pub fn getHashFromStorageIndex(sim_region: *SimRegion, storage_index: u32) *SimEntityHash {
    std.debug.assert(storage_index != 0);

    var result: *SimEntityHash = undefined;

    const hash_value = storage_index;
    var offset: u32 = 0;

    while (offset < sim_region.sim_entity_hash.len) : (offset += 1) {
        const hash_mask = sim_region.sim_entity_hash.len - 1;
        const hash_index = (hash_value + offset) & hash_mask;
        const entry = &sim_region.sim_entity_hash[hash_index];

        if (entry.index == 0 or entry.index == storage_index) {
            result = entry;
            break;
        }
    }

    return result;
}

pub fn getEntityByStorageIndex(sim_region: *SimRegion, storage_index: u32) ?*SimEntity {
    const entry = getHashFromStorageIndex(sim_region, storage_index);
    return entry.ptr;
}

pub fn loadEntityReference(state: *State, sim_region: *SimRegion, reference: *EntityReference) void {
    switch (reference.*) {
        .index => |index| {
            if (index != 0) {
                const entry = getHashFromStorageIndex(sim_region, reference.index);

                if (entry.ptr == null) {
                    entry.index = reference.index;
                    if (getLowEntity(state, reference.index)) |low_entity| {
                        var position = getSimSpacePosition(sim_region, low_entity);
                        entry.ptr = addEntity(state, sim_region, reference.index, low_entity, &position);
                    }
                }

                reference.* = EntityReference{ .ptr = entry.ptr };
            }
        },
        else => {},
    }
}

pub fn storeEntityReference(reference: *EntityReference) void {
    switch (reference.*) {
        .ptr => |opt_ptr| {
            if (opt_ptr) |ptr| {
                reference.* = EntityReference{ .index = ptr.storage_index };
            }
        },
        else => {},
    }
}

pub fn addEntityRaw(
    state: *State,
    sim_region: *SimRegion,
    storage_index: u32,
    opt_source: ?*shared.LowEntity,
) ?*SimEntity {
    std.debug.assert(storage_index != 0);

    var entity: ?*SimEntity = null;

    const entry = getHashFromStorageIndex(sim_region, storage_index);
    if (entry.ptr == null) {
        if (sim_region.entity_count < sim_region.max_entity_count) {
            entity = &sim_region.entities[sim_region.entity_count];
            sim_region.entity_count += 1;

            entry.index = storage_index;
            entry.ptr = entity.?;

            if (opt_source) |source| {
                entity.?.* = source.sim;
                loadEntityReference(state, sim_region, &entity.?.sword);

                std.debug.assert(!source.sim.isSet(SimEntityFlags.Simming.toInt()));
                source.sim.addFlags(SimEntityFlags.Simming.toInt());
            }

            entity.?.storage_index = storage_index;
            entity.?.updatable = false;
        } else {
            unreachable;
        }
    }

    return entity;
}

fn getSimSpacePosition(sim_region: *SimRegion, low_entity: *shared.LowEntity) Vector3 {
    var result = Vector3.invalidPosition();

    if (!low_entity.sim.isSet(SimEntityFlags.Nonspatial.toInt())) {
        result = world.subtractPositions(sim_region.world, &low_entity.position, &sim_region.origin);
    }

    return result;
}

pub fn entityOverlapsRectangle(position: Vector3, dimension: Vector3, rectangle: Rectangle3) bool {
    const grown = rectangle.addRadius(dimension.scaledTo(0.5));
    return position.isInRectangle(grown);
}

pub fn addEntity(
    state: *State,
    sim_region: *SimRegion,
    storage_index: u32,
    source: *shared.LowEntity,
    opt_sim_position: ?*Vector3,
) ?*SimEntity {
    const opt_entity = addEntityRaw(state, sim_region, storage_index, source);

    if (opt_entity) |sim_entity| {
        if (opt_sim_position) |sim_position| {
            sim_entity.position = sim_position.*;
            sim_entity.updatable = entityOverlapsRectangle(
                sim_entity.position,
                sim_entity.dimension,
                sim_region.updatable_bounds,
            );
        } else {
            sim_entity.position = getSimSpacePosition(sim_region, source);
        }
    }

    return opt_entity;
}

pub fn beginSimulation(
    state: *State,
    sim_arena: *shared.MemoryArena,
    game_world: *World,
    origin: world.WorldPosition,
    bounds: Rectangle3,
    delta_time: f32,
) *SimRegion {
    var sim_region: *SimRegion = shared.pushStruct(sim_arena, SimRegion);
    shared.zeroStruct([4096]SimEntityHash, &sim_region.sim_entity_hash);

    sim_region.max_entity_radius = 5;
    sim_region.max_entity_velocity = 30;
    const update_safety_margin = sim_region.max_entity_radius + sim_region.max_entity_velocity * delta_time;
    const update_safety_margin_z = 1;

    sim_region.world = game_world;
    sim_region.origin = origin;
    sim_region.updatable_bounds = bounds.addRadius(Vector3.splat(sim_region.max_entity_radius));
    sim_region.bounds = sim_region.updatable_bounds.addRadius(
        Vector3.new(update_safety_margin, update_safety_margin, update_safety_margin_z),
    );
    sim_region.max_entity_count = 4096;
    sim_region.entity_count = 0;
    sim_region.entities = shared.pushArray(sim_arena, sim_region.max_entity_count, SimEntity);

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
                const opt_chunk = world.getWorldChunk(sim_region.world, chunk_x, chunk_y, chunk_z, null);

                if (opt_chunk) |chunk| {
                    var opt_block: ?*world.WorldEntityBlock = &chunk.first_block;
                    while (opt_block) |block| : (opt_block = block.next) {
                        var block_entity_index: u32 = 0;
                        while (block_entity_index < block.entity_count) : (block_entity_index += 1) {
                            const low_entity_index = block.low_entity_indices[block_entity_index];
                            var low_entity = &state.low_entities[low_entity_index];

                            if (!low_entity.sim.isSet(SimEntityFlags.Nonspatial.toInt())) {
                                var sim_space_position = getSimSpacePosition(sim_region, low_entity);

                                if (entityOverlapsRectangle(
                                    sim_space_position,
                                    low_entity.sim.dimension,
                                    sim_region.bounds,
                                )) {
                                    _ = addEntity(state, sim_region, low_entity_index, low_entity, &sim_space_position);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return sim_region;
}

fn canOverlap(state: *State, mover: *SimEntity, region: *SimEntity) bool {
    _ = state;

    var result = false;

    if (mover != region) {
        if (region.type == .Stairwell) {
            result = true;
        }
    }

    return result;
}

fn handleOverlap(state: *State, mover: *SimEntity, region: *SimEntity, delta_time: f32, ground: *f32) void {
    _ = state;
    _ = delta_time;

    if (region.type == .Stairwell) {
        const region_rectangle = Rectangle3.fromCenterDimension(region.position, region.dimension);
        const barycentric = region_rectangle.getBarycentricPosition(mover.position).clamp01();
        ground.* = math.lerp(region_rectangle.min.z(), barycentric.y(), region_rectangle.max.z());
    }
}

fn speculativeCollide(mover: *SimEntity, region: *SimEntity) bool {
    var result = true;

    if (region.type == .Stairwell) {
        const region_rectangle = Rectangle3.fromCenterDimension(region.position, region.dimension);
        const barycentric = region_rectangle.getBarycentricPosition(mover.position).clamp01();
        const ground = math.lerp(region_rectangle.min.z(), barycentric.y(), region_rectangle.max.z());
        const step_height = 0.1;

        result = ((@abs(mover.position.z() - ground) > step_height) or
            (barycentric.y() > 0.1 and barycentric.y() < 0.9));
    }

    return result;
}

fn canCollide(state: *State, entity: *SimEntity, hit_entity: *SimEntity) bool {
    var result = false;

    if (entity != hit_entity) {
        var a = entity;
        var b = hit_entity;

        // Sort entities based on storage index.
        if (a.storage_index > b.storage_index) {
            const temp = a;
            a = b;
            b = temp;
        }

        // Basic rules.
        if (!a.isSet(SimEntityFlags.Nonspatial.toInt()) and
            !b.isSet(SimEntityFlags.Nonspatial.toInt()))
        {
            result = true;
        }

        // Specific rules.
        const hash_bucket = a.storage_index & ((state.collision_rule_hash.len) - 1);
        var opt_rule: ?*shared.PairwiseCollisionRule = state.collision_rule_hash[hash_bucket];
        while (opt_rule) |rule| : (opt_rule = rule.next_in_hash) {
            if ((rule.storage_index_a == a.storage_index) and (rule.storage_index_b == b.storage_index)) {
                result = rule.can_collide;
                break;
            }
        }
    }

    return result;
}

pub fn handleCollision(state: *State, entity: *SimEntity, hit_entity: *SimEntity) bool {
    var stops_on_collision = false;

    if (entity.type == .Sword) {
        // Stop future collisons between these entities.
        addCollisionRule(state, entity.storage_index, hit_entity.storage_index, false);

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
    state: *State,
    sim_region: *SimRegion,
    entity: *SimEntity,
    delta_time: f32,
    in_acceleration: Vector3,
    move_spec: *const MoveSpec,
) void {
    std.debug.assert(!entity.isSet(SimEntityFlags.Nonspatial.toInt()));

    if (entity.type == .Hero) {
        const break_here = true;
        _ = break_here;
    }

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

    if (!entity.isSet(SimEntityFlags.ZSupported.toInt())) {
        // Add gravity to acceleration.
        acceleration = acceleration.plus(Vector3.new(0, 0, -9.8));
    }

    // Calculate movement delta.
    var entity_delta = acceleration.scaledTo(0.5 * math.square(delta_time))
        .plus(entity.velocity.scaledTo(delta_time));
    entity.velocity = acceleration.scaledTo(delta_time).plus(entity.velocity);

    std.debug.assert(entity.velocity.lengthSquared() <= math.square(sim_region.max_entity_velocity));

    var distance_remaining = entity.distance_limit;
    if (distance_remaining == 0) {
        distance_remaining = 10000;
    }

    var iterations: u32 = 0;
    while (iterations < 4) : (iterations += 1) {
        var min_time: f32 = 1.0;
        const entity_delta_length = entity_delta.length();

        if (entity_delta_length > 0) {
            if (entity_delta_length > distance_remaining) {
                min_time = distance_remaining / entity_delta_length;
            }

            var wall_normal = Vector3.zero();
            var opt_hit_entity: ?*SimEntity = null;

            const desired_position = entity.position.plus(entity_delta);

            if (!entity.isSet(SimEntityFlags.Nonspatial.toInt())) {
                var test_entity_index: u32 = 0;
                while (test_entity_index < sim_region.entity_count) : (test_entity_index += 1) {
                    const test_entity = &sim_region.entities[test_entity_index];

                    if (canCollide(state, entity, test_entity)) {
                        const minkowski_diameter = Vector3.new(
                            test_entity.dimension.x() + entity.dimension.x(),
                            test_entity.dimension.y() + entity.dimension.y(),
                            test_entity.dimension.z() + entity.dimension.z(),
                        );
                        const min_corner = minkowski_diameter.scaledTo(-0.5);
                        const max_corner = minkowski_diameter.scaledTo(0.5);
                        const relative = entity.position.minus(test_entity.position);

                        var test_min_time = min_time;
                        var test_wall_normal = Vector3.zero();
                        var hit_this = false;

                        if (testWall(
                            min_corner.x(),
                            relative.x(),
                            relative.y(),
                            entity_delta.x(),
                            entity_delta.y(),
                            min_corner.y(),
                            max_corner.y(),
                            &test_min_time,
                        )) {
                            test_wall_normal = Vector3.new(-1, 0, 0);
                            hit_this = true;
                        }

                        if (testWall(
                            max_corner.x(),
                            relative.x(),
                            relative.y(),
                            entity_delta.x(),
                            entity_delta.y(),
                            min_corner.y(),
                            max_corner.y(),
                            &test_min_time,
                        )) {
                            test_wall_normal = Vector3.new(1, 0, 0);
                            hit_this = true;
                        }

                        if (testWall(
                            min_corner.y(),
                            relative.y(),
                            relative.x(),
                            entity_delta.y(),
                            entity_delta.x(),
                            min_corner.x(),
                            max_corner.x(),
                            &test_min_time,
                        )) {
                            test_wall_normal = Vector3.new(0, -1, 0);
                            hit_this = true;
                        }

                        if (testWall(
                            max_corner.y(),
                            relative.y(),
                            relative.x(),
                            entity_delta.y(),
                            entity_delta.x(),
                            min_corner.x(),
                            max_corner.x(),
                            &test_min_time,
                        )) {
                            test_wall_normal = Vector3.new(0, 1, 0);
                            hit_this = true;
                        }

                        if (hit_this) {
                            // const test_position = entity.position.plus(entity_delta.scaledTo(test_min_time));
                            if (speculativeCollide(entity, test_entity)) {
                                min_time = test_min_time;
                                wall_normal = test_wall_normal;
                                opt_hit_entity = test_entity;
                            }
                        }
                    }
                }
            }

            // Apply the amount of delta allowed by collision detection.
            entity.position = entity.position.plus(entity_delta.scaledTo(min_time));
            distance_remaining -= min_time * entity_delta_length;

            if (opt_hit_entity) |hit_entity| {
                // Remove the applied delta.
                entity_delta = desired_position.minus(entity.position);

                const stops_on_collision = handleCollision(state, entity, hit_entity);
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

    var ground: f32 = 0;

    // Handle events based on area overlapping.
    var test_entity_index: u32 = 0;
    const entity_rectangle = Rectangle3.fromCenterDimension(entity.position, entity.dimension);
    while (test_entity_index < sim_region.entity_count) : (test_entity_index += 1) {
        const test_entity = &sim_region.entities[test_entity_index];

        if (canOverlap(state, entity, test_entity)) {
            const test_entity_rectangle = Rectangle3.fromCenterDimension(test_entity.position, test_entity.dimension);

            if (entity_rectangle.intersects(&test_entity_rectangle)) {
                handleOverlap(state, entity, test_entity, delta_time, &ground);
            }
        }
    }

    // Ground check.
    if (entity.position.z() <= ground or
        (entity.isSet(SimEntityFlags.ZSupported.toInt()) and entity.velocity.z() == 0.0))
    {
        entity.position = Vector3.new(entity.position.x(), entity.position.y(), ground);
        entity.velocity = Vector3.new(entity.velocity.x(), entity.velocity.y(), 0);
        entity.addFlags(SimEntityFlags.ZSupported.toInt());
    } else {
        entity.clearFlags(SimEntityFlags.ZSupported.toInt());
    }

    if (entity.distance_limit != 0) {
        entity.distance_limit = distance_remaining;
    }

    // Update facing direction based on velocity.
    if (entity.velocity.x() == 0 and entity.velocity.y() == 0) {
        // Keep existing facing direction when velocity is zero.
    } else if (intrinsics.absoluteValue(entity.velocity.x()) > intrinsics.absoluteValue(entity.velocity.y())) {
        if (entity.velocity.x() > 0) {
            entity.facing_direction = 0;
        } else {
            entity.facing_direction = 2;
        }
    } else if (intrinsics.absoluteValue(entity.velocity.x()) < intrinsics.absoluteValue(entity.velocity.y())) {
        if (entity.velocity.y() > 0) {
            entity.facing_direction = 1;
        } else {
            entity.facing_direction = 3;
        }
    }
}

pub fn testWall(
    wall_x: f32,
    relative_x: f32,
    relative_y: f32,
    delta_x: f32,
    delta_y: f32,
    min_y: f32,
    max_y: f32,
    min_time: *f32,
) bool {
    var hit = false;

    if (delta_x != 0.0) {
        const epsilon_time = 0.001;
        const result_time = (wall_x - relative_x) / delta_x;
        const y = relative_y + (result_time * delta_y);
        if (result_time >= 0 and min_time.* > result_time) {
            if (y >= min_y and y <= max_y) {
                min_time.* = @max(0.0, result_time - epsilon_time);
                hit = true;
            }
        }
    }

    return hit;
}

pub fn endSimulation(state: *State, sim_region: *SimRegion) void {
    var sim_entity_index: u32 = 0;
    while (sim_entity_index < sim_region.entity_count) : (sim_entity_index += 1) {
        const entity = &sim_region.entities[sim_entity_index];
        const stored = &state.low_entities[entity.storage_index];

        std.debug.assert(stored.sim.isSet(SimEntityFlags.Simming.toInt()));
        stored.sim = entity.*;
        std.debug.assert(!stored.sim.isSet(SimEntityFlags.Simming.toInt()));

        storeEntityReference(&stored.sim.sword);

        const new_position = if (stored.sim.isSet(SimEntityFlags.Nonspatial.toInt()))
            world.WorldPosition.nullPosition()
        else
            world.mapIntoChunkSpace(state.world, sim_region.origin, entity.position);
        world.changeEntityLocation(
            &state.world_arena,
            state.world,
            stored,
            entity.storage_index,
            new_position,
        );

        // Update camera position.
        if (entity.storage_index == state.camera_following_entity_index) {
            var new_camera_position = state.camera_position;
            new_camera_position.chunk_z = stored.position.chunk_z;

            if (false) {
                // Move camera when player leaves the current screen.
                if (entity.position.x() > 9.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_x += 17;
                } else if (entity.position.x() < -9.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_x -= 17;
                }
                if (entity.position.y() > 5.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_y += 9;
                } else if (entity.position.y() < -5.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_y -= 9;
                }
            } else {
                const camera_z_offset = new_camera_position.offset.z();
                new_camera_position = stored.position;
                new_camera_position.offset = Vector3.new(
                    new_camera_position.offset.x(),
                    new_camera_position.offset.y(),
                    camera_z_offset,
                );
            }

            state.camera_position = new_camera_position;
        }
    }
}
