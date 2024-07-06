const shared = @import("shared.zig");
const math = @import("math.zig");
const world = @import("world.zig");

// Types.
const Vector2 = math.Vector2;
const Rectangle2 = math.Rectangle2;
const State = shared.State;
const World = world.World;

pub const SimEntity = struct {
    storage_index: u32 = 0,

    position: Vector2 = Vector2.zero(),
    chunk_z: i32 = 0,

    z: f32 = 0,
    z_velocity: f32 = 0,
};

pub const SimRegion = struct {
    world: *World,

    origin: world.WorldPosition,
    bounds: Rectangle2,

    max_entity_count: u32,
    entity_count: u32 = 0,
    entities: [*]SimEntity,
};

fn getSimSpacePosition(sim_region: *SimRegion, low_entity: *shared.LowEntity) Vector2 {
    const diff = world.subtractPositions(sim_region.world, &low_entity.position, &sim_region.origin);
    return diff.xy;
}

pub fn createEntity(sim_region: *SimRegion) ?*SimEntity {
    var result: ?*SimEntity = null;

    if (sim_region.entity_count < sim_region.max_entity_count) {
        sim_region.entity_count += 1;
        result = sim_region.entities[sim_region.entity_count];
        result.* = .{};
    } else {
        unreachable;
    }

    return result;
}

pub fn addEntity(sim_region: *SimRegion, low_entity: shared.LowEntity, opt_sim_position: ?*Vector2) ?*SimEntity {
    var opt_entity = createEntity(sim_region);

    if (opt_entity) |*sim_entity| {
        if (opt_sim_position) |sim_position| {
            sim_entity.position = sim_position.*;
        } else {
            sim_entity.position = getSimSpacePosition(sim_region, &low_entity);
        }
    }

    return opt_entity;
}

pub fn beginSimulation(state: *State, sim_arena: *shared.MemoryArena, game_world: *World, origin: world.WorldPosition, bounds: Rectangle2) *SimRegion {
    const sim_region: SimRegion = shared.pushStruct(sim_arena, SimRegion);
    sim_region.world = game_world;
    sim_region.origin = origin;
    sim_region.bounds = bounds;
    sim_region.max_entity_count = 4096;
    sim_region.entity_count = 0;
    sim_region.entities = shared.pushArray(sim_arena, sim_region.max_entity_count, SimEntity);

    const min_chunk_position = world.mapIntoChunkSpace(sim_region.world, sim_region.origin, sim_region.bounds.getMinCorner());
    const max_chunk_position = world.mapIntoChunkSpace(sim_region.world, sim_region.origin, sim_region.bounds.getMaxCorner());

    var chunk_y = min_chunk_position.chunk_y;
    while (chunk_y <= max_chunk_position.chunk_y) : (chunk_y += 1) {
        var chunk_x = min_chunk_position.chunk_x;
        while (chunk_x <= max_chunk_position.chunk_x) : (chunk_x += 1) {
            const opt_chunk = world.getWorldChunk(sim_region, chunk_x, chunk_y, sim_region.origin.chunk_z, null);

            if (opt_chunk) |chunk| {
                var opt_block: ?*world.WorldEntityBlock = &chunk.first_block;
                while (opt_block) |block| : (opt_block = block.next) {
                    var block_entity_index: u32 = 0;
                    while (block_entity_index < block.entity_count) : (block_entity_index += 1) {
                        const low_entity_index = block.low_entity_indices[block_entity_index];
                        var low_entity = state.low_entities[low_entity_index];
                        const sim_space_position = getSimSpacePosition(sim_region, &low_entity);

                        if (sim_space_position.isInRectangle(sim_region.bounds)) {
                            addEntity(sim_region, low_entity, sim_space_position);
                        }
                    }
                }
            }
        }
    }
}

pub fn endSimulation(state: *State, sim_region: *SimRegion) void {
    var sim_entity_index = 0;
    while (sim_entity_index < sim_region.entity_count) : (sim_entity_index += 1) {
        const sim_entity = sim_region.entities[sim_entity_index];
        const low_entity = &state.low_entities[sim_entity.storage_index];

        var new_position = world.mapIntoChunkSpace(state.world, sim_region.origin, sim_entity.position);
        world.changeEntityLocation(&state.world_arena, state.world, low_entity, sim_entity.storage_index, &low_entity.position, &new_position,);

        // Update camera position.
        if (forceEntityIntoHigh(state, state.camera_following_entity_index)) |camera_following_entity| {
            if (camera_following_entity.high) |high_entity| {
                var new_camera_position = state.camera_position;
                new_camera_position.chunk_z = camera_following_entity.low.position.chunk_z;

                // Move camera when player leaves the current screen.
                if (high_entity.position.x() > 9.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_x += 17;
                } else if (high_entity.position.x() < -9.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_x -= 17;
                }
                if (high_entity.position.y() > 5.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_y += 9;
                } else if (high_entity.position.y() < -5.0 * state.world.tile_side_in_meters) {
                    new_camera_position.chunk_y -= 9;
                }

                if (false) {
                    setCameraPosition(state, new_camera_position);
                } else {
                    // Follow player position.
                    setCameraPosition(state, camera_following_entity.low.position);
                }
            }
        }
    }
}
