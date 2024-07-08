const shared = @import("shared.zig");
const sim = @import("sim.zig");
const math = @import("math.zig");

// Types.
const Vector2 = math.Vector2;
const State = shared.State;
const SimEntity = sim.SimEntity;

pub fn updatePlayer(state: *State, sim_region: *sim.SimRegion, entity: *SimEntity, delta_time: f32) void {
    for (state.controlled_heroes) |controlled_hero| {
        if (controlled_hero.entity_index == entity.storage_index) {
            if (controlled_hero.vertical_direction != 0) {
                entity.z_velocity = controlled_hero.vertical_direction;
            }

            const move_spec = sim.MoveSpec{
                .speed = 50,
                .drag = 8,
                .unit_max_acceleration = true,
            };
            sim.moveEntity(
                sim_region,
                entity,
                delta_time,
                controlled_hero.movement_direction,
                &move_spec,
            );

            if (controlled_hero.sword_direction.x() != 0 or controlled_hero.sword_direction.y() != 0) {
                if (entity.sword.ptr) |sword| {
                    if (sword.isSet(sim.SimEntityFlags.Nonspatial.toInt())) {
                        sword.distance_remaining = 5.0;
                        sword.makeSpatial(entity.position, controlled_hero.sword_direction.scaledTo(5.0));
                    }
                }
            }
        }
    }
}

pub fn updateFamiliar(sim_region: *sim.SimRegion, entity: *SimEntity, delta_time: f32) void {
    var closest_hero: ?*SimEntity = null;
    var closest_hero_squared: f32 = math.square(10.0);

    var entity_index: u32 = 0;
    while (entity_index < sim_region.entity_count) : (entity_index += 1) {
        var test_entity = &sim_region.entities[entity_index];
        if (test_entity.type == .Hero) {
            const distance = test_entity.position.minus(entity.position).lengthSquared();

            if (distance < closest_hero_squared) {
                closest_hero = test_entity;
                closest_hero_squared = distance;
            }
        }
    }

    var direction = Vector2.zero();
    if (closest_hero) |hero| {
        if (closest_hero_squared > math.square(3.0)) {
            const acceleration: f32 = 1.0;
            const one_over_length = acceleration / @sqrt(closest_hero_squared);
            direction = hero.position.minus(entity.position).scaledTo(one_over_length);
        }
    }

    const move_spec = sim.MoveSpec{
        .speed = 25,
        .drag = 8,
        .unit_max_acceleration = true,
    };
    sim.moveEntity(sim_region, entity, delta_time, direction, &move_spec);
}

pub fn updateMonster(sim_region: *sim.SimRegion, entity: *SimEntity, delta_time: f32) void {
    _ = sim_region;
    _ = entity;
    _ = delta_time;
}

pub fn updateSword(sim_region: *sim.SimRegion, entity: *SimEntity, delta_time: f32) void {
    if (!entity.isSet(sim.SimEntityFlags.Nonspatial.toInt())) {
        const move_spec = sim.MoveSpec{};

        const old_position = entity.position;

        sim.moveEntity(sim_region, entity, delta_time, Vector2.zero(), &move_spec);

        const distance_traveled = entity.position.minus(old_position).length();
        entity.distance_remaining -= distance_traveled;

        if (entity.distance_remaining < 0) {
            entity.makeNonSpatial();
        }
    }
}
