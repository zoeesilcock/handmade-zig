const shared = @import("shared.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const world = @import("world.zig");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Rectangle2 = math.Rectangle2;
const State = shared.State;
const World = world.World;

pub const INVALID_POSITION = Vector2.new(100000, 100000);

pub const SimRegion = struct {
    world: *World,

    origin: world.WorldPosition,
    bounds: Rectangle2,
    updatable_bounds: Rectangle2,

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

    position: Vector2 = Vector2.zero(),
    velocity: Vector2 = Vector2.zero(),

    z: f32 = 0,
    z_velocity: f32 = 0,

    distance_limit: f32 = 0,

    chunk_z: i32 = 0,

    width: f32 = 0,
    height: f32 = 0,

    facing_direction: u32 = undefined,
    head_bob_time: f32 = 0,

    abs_tile_z_delta: i32 = 0,

    hit_point_max: u32,
    hit_points: [16]HitPoint,

    sword: EntityReference = null,

    pub fn isSet(self: *const SimEntity, flag: u32) bool {
        return (self.flags & flag) != 0;
    }

    pub fn addFlag(self: *SimEntity, flag: u32) void {
        self.flags = self.flags | flag;
    }

    pub fn clearFlag(self: *SimEntity, flag: u32) void {
        self.flags = self.flags & ~flag;
    }

    pub fn makeNonSpatial(self: *SimEntity) void {
        self.addFlag(SimEntityFlags.Nonspatial.toInt());
        self.position = INVALID_POSITION;
    }

    pub fn makeSpatial(self: *SimEntity, position: Vector2, velocity: Vector2) void {
        self.clearFlag(SimEntityFlags.Nonspatial.toInt());
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

            std.debug.assert(entry.index == 0 or entry.index == storage_index);
            entry.index = storage_index;
            entry.ptr = entity.?;

            if (opt_source) |source| {
                entity.?.* = source.sim;
                loadEntityReference(state, sim_region, &entity.?.sword);

                std.debug.assert(!source.sim.isSet(SimEntityFlags.Simming.toInt()));
                source.sim.addFlag(SimEntityFlags.Simming.toInt());
            }

            entity.?.storage_index = storage_index;
            entity.?.updatable = false;
        } else {
            unreachable;
        }
    }

    return entity;
}

fn getSimSpacePosition(sim_region: *SimRegion, low_entity: *shared.LowEntity) Vector2 {
    var result = INVALID_POSITION;

    if (!low_entity.sim.isSet(SimEntityFlags.Nonspatial.toInt())) {
        const diff = world.subtractPositions(sim_region.world, &low_entity.position, &sim_region.origin);
        result = diff.xy;
    }

    return result;
}

pub fn addEntity(
    state: *State,
    sim_region: *SimRegion,
    storage_index: u32,
    source: *shared.LowEntity,
    opt_sim_position: ?*Vector2,
) ?*SimEntity {
    const opt_entity = addEntityRaw(state, sim_region, storage_index, source);

    if (opt_entity) |sim_entity| {
        if (opt_sim_position) |sim_position| {
            sim_entity.position = sim_position.*;
            sim_entity.updatable = sim_entity.position.isInRectangle(sim_region.updatable_bounds);
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
    bounds: Rectangle2,
) *SimRegion {
    var sim_region: *SimRegion = shared.pushStruct(sim_arena, SimRegion);
    shared.zeroStruct([4096]SimEntityHash, &sim_region.sim_entity_hash);

    const update_safety_margin: f32 = 1;

    sim_region.world = game_world;
    sim_region.origin = origin;
    sim_region.updatable_bounds = bounds;
    sim_region.bounds = bounds.addRadius(update_safety_margin, update_safety_margin);
    sim_region.max_entity_count = 4096;
    sim_region.entity_count = 0;
    sim_region.entities = shared.pushArray(sim_arena, sim_region.max_entity_count, SimEntity);

    const min_chunk_position = world.mapIntoChunkSpace(sim_region.world, sim_region.origin, sim_region.bounds.getMinCorner());
    const max_chunk_position = world.mapIntoChunkSpace(sim_region.world, sim_region.origin, sim_region.bounds.getMaxCorner());

    var chunk_y = min_chunk_position.chunk_y;
    while (chunk_y <= max_chunk_position.chunk_y) : (chunk_y += 1) {
        var chunk_x = min_chunk_position.chunk_x;
        while (chunk_x <= max_chunk_position.chunk_x) : (chunk_x += 1) {
            const opt_chunk = world.getWorldChunk(sim_region.world, chunk_x, chunk_y, sim_region.origin.chunk_z, null);

            if (opt_chunk) |chunk| {
                var opt_block: ?*world.WorldEntityBlock = &chunk.first_block;
                while (opt_block) |block| : (opt_block = block.next) {
                    var block_entity_index: u32 = 0;
                    while (block_entity_index < block.entity_count) : (block_entity_index += 1) {
                        const low_entity_index = block.low_entity_indices[block_entity_index];
                        var low_entity = &state.low_entities[low_entity_index];

                        if (!low_entity.sim.isSet(SimEntityFlags.Nonspatial.toInt())) {
                            var sim_space_position = getSimSpacePosition(sim_region, low_entity);

                            if (sim_space_position.isInRectangle(sim_region.bounds)) {
                                _ = addEntity(state, sim_region, low_entity_index, low_entity, &sim_space_position);
                            }
                        }
                    }
                }
            }
        }
    }

    return sim_region;
}

pub fn moveEntity(
    sim_region: *SimRegion,
    entity: *SimEntity,
    delta_time: f32,
    acceleration_in: Vector2,
    move_spec: *const MoveSpec,
) void {
    std.debug.assert(!entity.isSet(SimEntityFlags.Nonspatial.toInt()));

    var acceleration = acceleration_in;

    // Correct speed when multiple axes are contributing to the direction.
    if (move_spec.unit_max_acceleration) {
        const direction_length = acceleration.lengthSquared();
        if (direction_length > 1.0) {
            acceleration = acceleration.scaledTo(1.0 / intrinsics.squareRoot(direction_length));
        }
    }

    // Calculate acceleration.
    acceleration = acceleration.scaledTo(move_spec.speed);

    // Apply drag.
    acceleration = acceleration.plus(entity.velocity.scaledTo(move_spec.drag).negated());
    // acceleration = acceleration.minus(entity.velocity.scaledTo(move_spec.drag));

    // Calculate movement delta.
    var entity_delta = acceleration.scaledTo(0.5 * math.square(delta_time))
        .plus(entity.velocity.scaledTo(delta_time));
    entity.velocity = acceleration.scaledTo(delta_time).plus(entity.velocity);

    // Jump.
    const z_acceleration = -9.8;
    entity.z = (0.5 * z_acceleration * math.square(delta_time)) +
        entity.z_velocity * delta_time + entity.z;
    entity.z_velocity = z_acceleration * delta_time + entity.z_velocity;
    if (entity.z < 0) {
        entity.z = 0;
    }

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

            var wall_normal = Vector2.zero();
            var opt_hit_entity: ?*SimEntity = null;

            const desired_position = entity.position.plus(entity_delta);

            const stops_on_collision = entity.isSet(SimEntityFlags.Collides.toInt());

            if (!entity.isSet(SimEntityFlags.Nonspatial.toInt())) {
                var test_entity_index: u32 = 0;
                while (test_entity_index < sim_region.entity_count) : (test_entity_index += 1) {
                    const test_entity = &sim_region.entities[test_entity_index];

                    if (entity != test_entity) {
                        if (test_entity.isSet(SimEntityFlags.Collides.toInt()) and
                            !test_entity.isSet(SimEntityFlags.Nonspatial.toInt()))
                        {
                            const collision_diameter = Vector2.new(
                                test_entity.width + entity.width,
                                test_entity.height + entity.height,
                            );
                            const min_corner = collision_diameter.scaledTo(-0.5);
                            const max_corner = collision_diameter.scaledTo(0.5);
                            const relative = entity.position.minus(test_entity.position);

                            if (testWall(
                                min_corner.x(),
                                relative.x(),
                                relative.y(),
                                entity_delta.x(),
                                entity_delta.y(),
                                min_corner.y(),
                                max_corner.y(),
                                &min_time,
                            )) {
                                wall_normal = Vector2.new(-1, 0);
                                opt_hit_entity = test_entity;
                            }

                            if (testWall(
                                max_corner.x(),
                                relative.x(),
                                relative.y(),
                                entity_delta.x(),
                                entity_delta.y(),
                                min_corner.y(),
                                max_corner.y(),
                                &min_time,
                            )) {
                                wall_normal = Vector2.new(1, 0);
                                opt_hit_entity = test_entity;
                            }

                            if (testWall(
                                min_corner.y(),
                                relative.y(),
                                relative.x(),
                                entity_delta.y(),
                                entity_delta.x(),
                                min_corner.x(),
                                max_corner.x(),
                                &min_time,
                            )) {
                                wall_normal = Vector2.new(0, -1);
                                opt_hit_entity = test_entity;
                            }

                            if (testWall(
                                max_corner.y(),
                                relative.y(),
                                relative.x(),
                                entity_delta.y(),
                                entity_delta.x(),
                                min_corner.x(),
                                max_corner.x(),
                                &min_time,
                            )) {
                                wall_normal = Vector2.new(0, 1);
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

                if (stops_on_collision) {
                    // Remove velocity that is facing into the wall.
                    entity_delta = entity_delta.minus(wall_normal.scaledTo(entity_delta.dotProduct(wall_normal)));
                    entity.velocity = entity.velocity.minus(wall_normal.scaledTo(entity.velocity.dotProduct(wall_normal)));
                }

                var a = entity;
                var b = hit_entity;

                if (@intFromEnum(a.type) > @intFromEnum(b.type)) {
                    const temp = a;
                    a = b;
                    b = temp;
                }

                handleCollision(a, b);

                // Update player Z when hitting a ladder.
                // entity.chunk_z += hit_low_entity.abs_tile_z_delta;
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

pub fn handleCollision(a: *SimEntity, b: *SimEntity) void {
    if (a.type == .Monster and b.type == .Sword) {
        a.hit_point_max -= 1;
        b.makeNonSpatial();
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
            if (false) {
                new_camera_position.chunk_z = stored.position.chunk_z;

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
                new_camera_position = stored.position;
            }

            state.camera_position = new_camera_position;
        }
    }
}
