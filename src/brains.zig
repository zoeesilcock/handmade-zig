const std = @import("std");
const shared = @import("shared.zig");
const entities = @import("entities.zig");
const sim = @import("sim.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const debug_interface = @import("debug_interface.zig");

var global_config = &@import("config.zig").global_config;

const GameWorldMode = @import("world_mode.zig").GameModeWorld;
const Entity = entities.Entity;
const TraversableReference = entities.TraversableReference;
const SimRegion = sim.SimRegion;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const DebugInterface = debug_interface.DebugInterface;

//
// Brain types
//
pub const BrainHero = extern struct {
    head: ?*Entity,
    body: ?*Entity,
};

pub const BrainMonster = extern struct {
    body: ?*Entity,
};

pub const BrainFamiliar = extern struct {
    head: ?*Entity,
};

pub const BrainSnake = extern struct {
    segments: [16]?*Entity,
};

//
// Brain
//
pub const Brain = extern struct {
    id: BrainId,
    type: BrainType,
    parts: extern union {
        array: [*]Entity,
        hero: BrainHero,
        monster: BrainMonster,
        familiar: BrainFamiliar,
        snake: BrainSnake,
    },
};

pub const BrainId = extern struct {
    value: u32 = 0,

    pub const no_brain: BrainId = .{};
};

pub const BrainType = enum(u16) {
    BrainHero,

    // Test brains.
    BrainSnake,
    BrainFamiliar,
    BrainFloatyThing,
    BrainMonster,
};

pub const ReservedBrainId = enum(u32) {
    FirstHero = 1,
    LastHero = 1 + shared.MAX_CONTROLLER_COUNT - 1,
    FirstFree,
};

pub const BrainSlot = extern struct {
    type: u16 = 0,
    index: u16 = 0,

    pub fn forField(comptime slot_type: type, comptime field_name: []const u8) BrainSlot {
        const full_brain_type_name = @typeName(slot_type);

        comptime var last_dot: usize = 0;
        comptime for (full_brain_type_name, 0..) |c, i| {
            if (c == '.') {
                last_dot = i + 1;
            }
        };

        const brain_type_name: []const u8 = full_brain_type_name[last_dot..];
        const brain_type: u16 = @intFromEnum(@field(BrainType, brain_type_name));
        const pack_value: u16 = @offsetOf(slot_type, field_name) / @sizeOf(*Entity);
        return BrainSlot{ .type = brain_type, .index = pack_value };
    }

    pub fn forIndexedField(comptime slot_type: type, comptime field_name: []const u8, index: u32) BrainSlot {
        var slot: BrainSlot = BrainSlot.forField(slot_type, field_name);
        slot.index += @as(u16, @intCast(index));
        return slot;
    }

    pub fn isType(self: BrainSlot, brain_type: BrainType) bool {
        return self.index != 0 and self.type == @intFromEnum(brain_type);
    }
};

pub fn executeBrain(
    state: *shared.State,
    world_mode: *GameWorldMode,
    sim_region: *SimRegion,
    input: *shared.GameInput,
    brain: *Brain,
    delta_time: f32,
) void {
    switch (brain.type) {
        .BrainHero => {
            const parts: *BrainHero = &brain.parts.hero;
            const opt_head: ?*Entity = parts.head;
            const opt_body: ?*Entity = parts.body;

            var sword_direction: Vector2 = Vector2.zero();
            var exited: bool = false;

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

            if (controller.start_button.wasPressed()) {
                if (opt_head) |head| {
                    var opt_closest_hero: ?*Entity = null;
                    var closest_hero_squared: f32 = math.square(10.0);

                    var hero_entity_index: u32 = 0;
                    while (hero_entity_index < sim_region.entity_count) : (hero_entity_index += 1) {
                        var test_entity = &sim_region.entities[hero_entity_index];
                        if (test_entity.brain_id.value != 0 and test_entity.brain_id.value != brain.id.value) {
                            const distance = test_entity.position.minus(head.position).lengthSquared();

                            if (distance < closest_hero_squared) {
                                opt_closest_hero = test_entity;
                                closest_hero_squared = distance;
                            }
                        }
                    }

                    if (opt_closest_hero) |closest_hero| {
                        const old_brain_id = head.brain_id;
                        const old_brain_slot = head.brain_slot;
                        head.brain_id = closest_hero.brain_id;
                        head.brain_slot = closest_hero.brain_slot;
                        closest_hero.brain_id = old_brain_id;
                        closest_hero.brain_slot = old_brain_slot;
                    }
                }
            }

            if (controller.action_up.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(0, 1));
            }
            if (controller.action_down.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(0, -1));
            }
            if (controller.action_left.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(-1, 0));
            }
            if (controller.action_right.ended_down) {
                sword_direction = sword_direction.plus(Vector2.new(1, 0));
            }

            if (controller.back_button.wasPressed()) {
                exited = true;
            }

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

                    const controller_direction = controlled_hero.controller_direction.toVector3(0);
                    var acceleration: Vector3 = controller_direction;

                    // Limit the input to unit length.
                    const direction_length = acceleration.lengthSquared();
                    if (direction_length > 1.0) {
                        acceleration = acceleration.scaledTo(1.0 / intrinsics.squareRoot(direction_length));
                    }

                    // Apply movement speed.
                    const movement_speed: f32 = 30;
                    const drag: f32 = 8;
                    acceleration = acceleration.scaledTo(movement_speed);

                    // Recenter.
                    const timer_is_up: bool = controlled_hero.recenter_timer == 0;
                    const no_push: bool = controlled_hero.controller_direction.lengthSquared() < 0.1;
                    const spring_coefficient: f32 = if (no_push) 300 else 25;
                    for (0..3) |e| {
                        if (no_push or (timer_is_up and math.square(acceleration.values[e]) < 0.1)) {
                            acceleration.values[e] =
                                spring_coefficient * (closest_position.values[e] - head.position.values[e]) -
                                30 * head.velocity.values[e];
                        } else {
                            acceleration.values[e] += -drag * head.velocity.values[e];
                        }
                    }
                    controlled_hero.recenter_timer = math.clampAboveZero(controlled_hero.recenter_timer - delta_time);

                    // Apply the calculated acceleration to entity.
                    head.acceleration = acceleration;
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
        .BrainFamiliar => {
            const parts: *BrainFamiliar = &brain.parts.familiar;
            const opt_head: ?*Entity = parts.head;

            if (opt_head) |head| {
                var closest_hero: ?*Entity = null;
                var closest_hero_squared: f32 = math.square(10.0);

                var hero_entity_index: u32 = 0;
                while (hero_entity_index < sim_region.entity_count) : (hero_entity_index += 1) {
                    var test_entity = &sim_region.entities[hero_entity_index];
                    if (test_entity.brain_slot.isType(.BrainHero)) {
                        const distance = test_entity.position.minus(head.position).lengthSquared();

                        if (distance < closest_hero_squared) {
                            closest_hero = test_entity;
                            closest_hero_squared = distance;
                        }
                    }
                }

                if (global_config.AI_Familiar_FollowsHero) {
                    if (closest_hero) |hero| {
                        if (closest_hero_squared > math.square(3.0)) {
                            const acceleration: f32 = 1;
                            const one_over_length = acceleration / @sqrt(closest_hero_squared);
                            head.acceleration = hero.position.minus(head.position).scaledTo(one_over_length);
                        }
                    }
                }
            }
        },
        .BrainFloatyThing => {
            // _ = entity.position.setZ(entity.position.z() + 0.05 * intrinsics.cos(entity.bob_time));
            // entity.bob_time += delta_time;
        },
        .BrainMonster => {
            const parts: *BrainMonster = &brain.parts.monster;
            const opt_body: ?*Entity = parts.body;

            if (opt_body) |body| {
                const delta: Vector3 = .new(
                    world_mode.game_entropy.randomBilateral(),
                    world_mode.game_entropy.randomBilateral(),
                    0,
                );
                var traversable: TraversableReference = undefined;
                if (sim.getClosestTraversable(sim_region, body.position.plus(delta), &traversable, 0)) {
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
            }
        },
        .BrainSnake => {
            const parts: *BrainSnake = &brain.parts.snake;
            const opt_head: ?*Entity = parts.segments[0];

            if (opt_head) |head| {
                const delta: Vector3 = .new(
                    world_mode.game_entropy.randomBilateral(),
                    world_mode.game_entropy.randomBilateral(),
                    0,
                );
                var traversable: TraversableReference = undefined;
                if (sim.getClosestTraversable(sim_region, head.position.plus(delta), &traversable, 0)) {
                    if (head.movement_mode == .Planted) {
                        if (!traversable.equals(head.occupying)) {
                            var last_occupying: TraversableReference = head.occupying;
                            head.came_from = head.occupying;
                            if (sim.transactionalOccupy(head, &head.occupying, traversable)) {
                                head.movement_time = 0;
                                head.movement_mode = .Hopping;

                                var segment_index: u32 = 1;
                                while (segment_index < parts.segments.len) : (segment_index += 1) {
                                    if (parts.segments[segment_index]) |segment| {
                                        segment.came_from = segment.occupying;
                                        _ = sim.transactionalOccupy(segment, &segment.occupying, last_occupying);
                                        last_occupying = segment.came_from;

                                        segment.movement_time = 0;
                                        segment.movement_mode = .Hopping;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
    }
}
