const shared = @import("shared.zig");
const entities = @import("entities.zig");
const sim = @import("sim.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");

const Entity = entities.Entity;
const TraversableReference = entities.TraversableReference;
const SimRegion = sim.SimRegion;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;

pub const Brain = extern struct { id: BrainId, type: BrainType, parts: extern union {
    hero: BrainHeroParts,
    array: [16]?*Entity,
} };

pub const BrainId = extern struct {
    value: u32 = 0,
};

pub const BrainHeroParts = extern struct {
    head: ?*Entity,
    body: ?*Entity,
};

pub const BrainType = enum(u32) {
    Hero,

    // Test brains.
    Snake,
    Familiar,
    FloatyThing,
    Monster,
};

pub const ReservedBrainId = enum(u32) {
    FirstHero = 1,
    LastHero = 1 + shared.MAX_CONTROLLER_COUNT - 1,
    FirstFree,
};

pub const BrainSlot = extern struct {
    index: u32 = 0,

    pub fn forField(comptime slot_type: type, comptime field_name: []const u8) BrainSlot {
        const pack_value = @offsetOf(slot_type, field_name) / @sizeOf(*Entity);
        return BrainSlot{ .index = pack_value };
    }
};

pub fn executeBrain(
    state: *shared.State,
    sim_region: *SimRegion,
    input: *shared.GameInput,
    brain: *Brain,
    delta_time: f32,
) void {
    switch (brain.type) {
        .Hero => {
            const parts: *BrainHeroParts = &brain.parts.hero;
            const opt_head: ?*Entity = parts.head;
            const opt_body: ?*Entity = parts.body;

            var sword_direction: Vector2 = Vector2.zero();
            var exited: bool = false;
            var debug_spawn: bool = false;

            const controller_index: u32 = brain.id.value - @intFromEnum(ReservedBrainId.FirstHero);
            const controller: *shared.ControllerInput = input.getController(controller_index);
            const controlled_hero = &state.controlled_heroes[controller_index];
            if (controller.is_analog) {
                controlled_hero.controller_direction = Vector2.new(controller.stick_average_x, controller.stick_average_y);
            } else {
                const recenter: f32 = 0.5;
                if (controller.move_up.wasPressed()) {
                    _ = controlled_hero.controller_direction.setX(0);
                    _ = controlled_hero.controller_direction.setY(1);
                    controlled_hero.recenter_timer = recenter;
                }
                if (controller.move_down.wasPressed()) {
                    _ = controlled_hero.controller_direction.setX(0);
                    _ = controlled_hero.controller_direction.setY(-1);
                    controlled_hero.recenter_timer = recenter;
                }
                if (controller.move_left.wasPressed()) {
                    _ = controlled_hero.controller_direction.setX(-1);
                    _ = controlled_hero.controller_direction.setY(0);
                    controlled_hero.recenter_timer = recenter;
                }
                if (controller.move_right.wasPressed()) {
                    _ = controlled_hero.controller_direction.setX(1);
                    _ = controlled_hero.controller_direction.setY(0);
                    controlled_hero.recenter_timer = recenter;
                }

                if (!controller.move_left.isDown() and !controller.move_right.isDown()) {
                    _ = controlled_hero.controller_direction.setX(0);

                    if (controller.move_up.isDown()) {
                        _ = controlled_hero.controller_direction.setY(1);
                    } else if (controller.move_down.isDown()) {
                        _ = controlled_hero.controller_direction.setY(-1);
                    }
                }

                if (!controller.move_up.isDown() and !controller.move_down.isDown()) {
                    _ = controlled_hero.controller_direction.setY(0);

                    if (controller.move_left.isDown()) {
                        _ = controlled_hero.controller_direction.setX(-1);
                    } else if (controller.move_right.isDown()) {
                        _ = controlled_hero.controller_direction.setX(1);
                    }
                }
            }

            if (controller.action_up.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(0, 1));
                state.audio_state.changeVolume(state.music, 10, Vector2.one());
            }
            if (controller.action_down.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(0, -1));
                state.audio_state.changeVolume(state.music, 10, Vector2.zero());
            }
            if (controller.action_left.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(-1, 0));
                state.audio_state.changeVolume(state.music, 5, Vector2.new(1, 0));
            }
            if (controller.action_right.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(1, 0));
                state.audio_state.changeVolume(state.music, 5, Vector2.new(0, 1));
            }

            if (controller.start_button.wasPressed()) {
                debug_spawn = true;
            }

            if (controller.back_button.wasPressed()) {
                exited = true;
            }

            if (false) {
                if (opt_head) |head| {
                    if (debug_spawn) {
                        var traversable: TraversableReference = undefined;
                        if (sim.getClosestTraversable(
                            sim_region,
                            head.position,
                            &traversable,
                            @intFromEnum(sim.TraversableSearchFlag.Unoccupied),
                        )) {
                            _ = state.mode.world.addPlayer(sim_region, traversable);
                        }

                        debug_spawn = false;
                    }
                }
            }

            controlled_hero.recenter_timer =
                math.clampAboveZero(controlled_hero.recenter_timer - delta_time);

            if (opt_head) |head| {
                if (sword_direction.x() == 0 and sword_direction.y() == 0) {
                    // Keep existing facing direction when velocity is zero.
                } else {
                    head.facing_direction =
                        intrinsics.atan2(sword_direction.y(), sword_direction.x());
                }

                var traversable: TraversableReference = undefined;
                if (sim.getClosestTraversable(sim_region, head.position, &traversable, 0)) {
                    if (opt_body) |body| {
                        if (body.movement_mode == .Planted) {
                            if (!traversable.equals(body.occupying)) {
                                body.came_from = body.occupying;
                                if (sim.transactionalOccupy(body, &body.occupying, traversable)) {
                                    body.movement_time = 0;
                                    body.movement_mode = .Hopping;
                                }
                            }
                        }
                    }

                    const closest_position: Vector3 = traversable.getSimSpaceTraversable().position;
                    const timer_is_up: bool = controlled_hero.recenter_timer == 0;
                    const no_push: bool = controlled_hero.controller_direction.lengthSquared() < 0.1;
                    const spring_coefficient: f32 = if (no_push) 300 else 25;
                    const controller_direction = controlled_hero.controller_direction.toVector3(0);
                    var acceleration2: Vector3 = controller_direction;
                    for (0..3) |e| {
                        if (no_push or (timer_is_up and math.square(controller_direction.values[e]) < 0.1)) {
                            acceleration2.values[e] =
                                spring_coefficient * (closest_position.values[e] - head.position.values[e]) -
                                30 * head.velocity.values[e];
                        }
                    }

                    head.move_spec.speed = 30;
                    head.move_spec.drag = 8;
                    head.move_spec.unit_max_acceleration = true;
                    head.acceleration = acceleration2;
                }
            }

            if (opt_body) |body| {
                if (opt_head) |head| {
                    body.facing_direction = head.facing_direction;
                }

                body.velocity = Vector3.zero();

                if (body.movement_mode == .Planted) {
                    body.position = body.occupying.getSimSpaceTraversable().position;

                    if (opt_head) |head| {
                        const head_distance: f32 = head.position.minus(body.position).lengthSquared();

                        const max_head_distance: f32 = 0.5;
                        const t_head_distance: f32 = math.clamp01MapToRange(0, max_head_distance, head_distance);
                        body.bob_acceleration = -20 * t_head_distance;
                    }
                }

                var head_delta: Vector3 = .zero();
                if (opt_head) |head| {
                    head_delta = head.position.minus(body.position);
                }
                body.floor_displace = head_delta.xy().scaledTo(0.25);
                body.y_axis = Vector2.new(0, 1).plus(head_delta.xy().scaledTo(0.5));
            }

            if (exited) {
                sim.deleteEntity(sim_region, opt_head);
                sim.deleteEntity(sim_region, opt_body);
                controlled_hero.brain_id = .{};
            }
        },
        .Familiar => {
            // var closest_hero: ?*Entity = null;
            // var closest_hero_squared: f32 = math.square(10.0);
            //
            // var hero_entity_index: u32 = 0;
            // while (hero_entity_index < sim_region.entity_count) : (hero_entity_index += 1) {
            //     var test_entity = &sim_region.entities[hero_entity_index];
            //     if (test_entity.type == .HeroBody) {
            //         const distance = test_entity.position.minus(entity.position).lengthSquared();
            //
            //         if (distance < closest_hero_squared) {
            //             closest_hero = test_entity;
            //             closest_hero_squared = distance;
            //         }
            //     }
            // }
            //
            // if (global_config.AI_Familiar_FollowsHero) {
            //     if (closest_hero) |hero| {
            //         if (closest_hero_squared > math.square(3.0)) {
            //             const speed: f32 = 1.0;
            //             const one_over_length = speed / @sqrt(closest_hero_squared);
            //             entity.acceleration = hero.position.minus(entity.position).scaledTo(one_over_length);
            //         }
            //     }
            // }
            //
            // move_spec = sim.MoveSpec{
            //     .speed = 25,
            //     .drag = 8,
            //     .unit_max_acceleration = true,
            // };
        },
        .FloatyThing => {
            // _ = entity.position.setZ(entity.position.z() + 0.05 * intrinsics.cos(entity.bob_time));
            // entity.bob_time += delta_time;
        },
        .Monster => {},
        .Snake => {},
    }
}
