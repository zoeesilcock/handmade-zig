const shared = @import("shared.zig");
const world = @import("world.zig");
const brains = @import("brains.zig");
const asset = @import("asset.zig");
const sim = @import("sim.zig");
const math = @import("math.zig");
const render = @import("render.zig");
const particles = @import("particles.zig");
const rendergroup = @import("rendergroup.zig");
const file_formats = @import("file_formats");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

// Types.
const Color = math.Color;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const BrainId = brains.BrainId;
const BrainType = brains.BrainType;
const BrainSlot = brains.BrainSlot;
const AssetTypeId = asset.AssetTypeId;
const TransientState = shared.TransientState;
const SimRegion = sim.SimRegion;
const WorldPosition = world.WorldPosition;
const ManualSortKey = render.ManualSortKey;
const ParticleCache = particles.ParticleCache;
const ParticleSpec = particles.ParticleSpec;
const RenderGroup = rendergroup.RenderGroup;
const TransientClipRect = rendergroup.TransientClipRect;
const ObjectTransform = rendergroup.ObjectTransform;
const ClipRectFX = rendergroup.ClipRectFX;
const AssetTagId = file_formats.AssetTagId;
const BitmapId = file_formats.BitmapId;
const DebugInterface = debug_interface.DebugInterface;
const TimedBlock = debug_interface.TimedBlock;
const GameModeWorld = @import("world_mode.zig").GameModeWorld;

const MAX_CONTROLLER_COUNT = shared.MAX_CONTROLLER_COUNT;
var global_config = &@import("config.zig").global_config;

pub const EntityId = packed struct {
    value: u32 = 0,

    pub fn equals(self: EntityId, other: EntityId) bool {
        return self.value == other.value;
    }
};

pub const EntityFlags = enum(u32) {
    Collides = (1 << 0),
    Deleted = (1 << 1),
    Active = (1 << 2),

    pub fn toInt(self: EntityFlags) u32 {
        return @intFromEnum(self);
    }
};

pub const EntityMovementMode = enum(u32) {
    Planted,
    Hopping,
    Floating,
    AngleOffset,
    AngleAttackSwipe,
};

pub const EntityVisiblePieceFlag = enum(u32) {
    AxesDeform = 0x1,
    BobOffset = 0x2,
};

pub const EntityVisiblePiece = extern struct {
    offset: Vector3,
    color: Color,
    asset_type: AssetTypeId,
    height: f32,
    flags: u32,
};

pub const Entity = extern struct {
    id: EntityId = .{},

    brain_type: BrainType,
    brain_slot: BrainSlot = .{},
    brain_id: BrainId = .{},

    z_layer: i32,

    //
    // Transient
    //
    //
    manual_sort: ManualSortKey,

    //
    // Everything below here is not worked out yet.
    //
    flags: u32 = 0,

    position: Vector3 = Vector3.zero(),
    velocity: Vector3 = Vector3.zero(),
    acceleration: Vector3 = Vector3.zero(), // Do not pack this.

    collision: *EntityCollisionVolumeGroup,

    distance_limit: f32 = 0,

    facing_direction: f32 = 0,
    bob_time: f32 = 0,
    bob_delta_time: f32 = 0,
    bob_acceleration: f32 = 0, // Do not pack this.

    abs_tile_z_delta: i32 = 0,

    hit_point_max: u32,
    hit_points: [16]HitPoint,

    walkable_dimension: Vector2,
    walkable_height: f32 = 0,

    movement_mode: EntityMovementMode,
    movement_time: f32,
    occupying: TraversableReference,
    came_from: TraversableReference,
    auto_boost_to: TraversableReference,

    angle_base: Vector3,
    angle_current: f32,
    angle_start: f32,
    angle_target: f32,
    angle_current_distance: f32,
    angle_base_distance: f32,
    angle_swipe_distance: f32,

    x_axis: Vector2,
    y_axis: Vector2,

    floor_displace: Vector2,

    traversable_count: u32,
    traversables: [16]EntityTraversablePoint,

    piece_count: u32,
    pieces: [4]EntityVisiblePiece, // 0 is the "on top" piece.

    has_particle_system: bool,
    particle_spec: ParticleSpec,

    pub fn addPiece(
        self: *Entity,
        asset_type: AssetTypeId,
        height: f32,
        offset: Vector3,
        color: Color,
        opt_movement_flags: ?u32,
    ) void {
        std.debug.assert(self.piece_count < self.pieces.len);

        var piece: *EntityVisiblePiece = &self.pieces[self.piece_count];
        self.piece_count += 1;

        piece.asset_type = asset_type;
        piece.height = height;
        piece.offset = offset;
        piece.color = color;
        piece.flags = opt_movement_flags orelse 0;
    }

    pub fn isDeleted(self: *const Entity) bool {
        return self.hasFlag(EntityFlags.Deleted.toInt());
    }

    pub fn hasFlag(self: *const Entity, flag: u32) bool {
        return (self.flags & flag) != 0;
    }

    pub fn addFlags(self: *Entity, flags: u32) void {
        self.flags = self.flags | flags;
    }

    pub fn clearFlags(self: *Entity, flags: u32) void {
        self.flags = self.flags & ~flags;
    }

    pub fn getGroundPoint(self: *const Entity) Vector3 {
        return self.position;
    }

    pub fn getGroundPointFor(self: *const Entity, position: Vector3) Vector3 {
        _ = self;
        return position;
    }

    pub fn getStairGround(self: *const Entity, at_ground_point: Vector3) f32 {
        const region_rectangle = Rectangle2.fromCenterDimension(self.position.xy(), self.walkable_dimension);
        const barycentric = region_rectangle.getBarycentricPosition(at_ground_point.xy()).clamp01();
        return self.position.z() + barycentric.y() * self.walkable_height;
    }

    pub fn getTraversable(opt_self: ?*const Entity, index: u32) ?*EntityTraversablePoint {
        var result: ?*EntityTraversablePoint = null;
        if (opt_self) |self| {
            std.debug.assert(index < self.traversable_count);
            result = @ptrFromInt(@intFromPtr(&self.traversables) + index);
        }
        return result;
    }

    pub fn getSimSpaceTraversable(self: *const Entity, index: u32) EntityTraversablePoint {
        var result: EntityTraversablePoint = .{
            .position = self.position,
            .occupier = null,
        };

        if (self.getTraversable(index)) |point| {
            result.position = result.position.plus(point.position);
            result.occupier = point.occupier;
        }

        return result;
    }
};

pub const EntityReference = extern struct {
    ptr: ?*Entity = null,
    index: EntityId = .{},

    pub fn equals(self: *const EntityReference, other: EntityReference) bool {
        return self.ptr == other.ptr and
            self.index.value == other.index.value;
    }
};

pub const TraversableReference = extern struct {
    entity: EntityReference = .{},
    index: u32 = 0,

    pub const init: TraversableReference = .{
        .entity = .{ .ptr = null },
        .index = 0,
    };

    pub fn getTraversable(self: TraversableReference) ?*EntityTraversablePoint {
        var result: ?*EntityTraversablePoint = null;
        if (self.entity.ptr) |entity_ptr| {
            result = entity_ptr.getTraversable(self.index);
        }
        return result;
    }

    pub fn getSimSpaceTraversable(self: TraversableReference) EntityTraversablePoint {
        var result: EntityTraversablePoint = .{
            .position = .zero(),
            .occupier = null,
        };

        if (self.entity.ptr) |entity_ptr| {
            result = entity_ptr.getSimSpaceTraversable(self.index);
        }

        return result;
    }

    pub fn equals(self: TraversableReference, other: TraversableReference) bool {
        return self.entity.equals(other.entity) and self.index == other.index;
    }

    pub fn isOccupied(self: TraversableReference) bool {
        var result: bool = true;

        if (self.getTraversable()) |traversable| {
            result = traversable.occupier != null;
        }

        return result;
    }
};

pub const HitPoint = extern struct {
    flags: u8,
    filled_amount: u8,
};

pub const EntityCollisionVolume = extern struct {
    offset_position: Vector3,
    dimension: Vector3,
};

pub const EntityTraversablePoint = extern struct {
    position: Vector3,
    occupier: ?*Entity,
};

pub const EntityCollisionVolumeGroup = extern struct {
    total_volume: EntityCollisionVolume,

    volume_count: u32,
    volumes: [*]EntityCollisionVolume,

    pub fn getSpaceVolume(self: *const EntityCollisionVolumeGroup, index: u32) EntityCollisionVolume {
        return self.volumes[index];
    }
};

pub fn updateAndRenderEntities(
    world_mode: *GameModeWorld,
    transient_state: *TransientState,
    render_group: *RenderGroup,
    sim_region: *SimRegion,
    camera_position: Vector3,
    draw_buffer: *asset.LoadedBitmap,
    background_color: Color,
    delta_time: f32,
    mouse_position: Vector2,
) void {
    TimedBlock.beginFunction(@src(), .UpdateAndRenderEntities);
    defer TimedBlock.endFunction(@src(), .UpdateAndRenderEntities);

    const minimum_level_index: i32 = -4;
    const maximum_level_index: i32 = 1;
    var fog_amount: [maximum_level_index - minimum_level_index + 1]f32 = undefined;
    var test_alpha: f32 = 0;

    const fade_top_end_z: f32 = 1 * world_mode.typical_floor_height;
    const fade_top_start_z: f32 = 0.5 * world_mode.typical_floor_height;
    const fade_bottom_start_z: f32 = -1 * world_mode.typical_floor_height;
    const fade_bottom_end_z: f32 = -4 * world_mode.typical_floor_height;
    var cam_rel_ground_z: [fog_amount.len]f32 = undefined;

    var level_index: u32 = 0;
    while (level_index < fog_amount.len) : (level_index += 1) {
        const relative_layer_index: i32 = minimum_level_index + @as(i32, @intCast(level_index));
        const camera_relative_ground_z: f32 =
            @as(f32, @floatFromInt(relative_layer_index)) * world_mode.typical_floor_height - world_mode.camera_offset.z();
        cam_rel_ground_z[level_index] = camera_relative_ground_z;

        test_alpha = math.clamp01MapToRange(
            fade_top_end_z,
            fade_top_start_z,
            camera_relative_ground_z,
        );
        fog_amount[level_index] = math.clamp01MapToRange(
            fade_bottom_start_z,
            fade_bottom_end_z,
            camera_relative_ground_z,
        );
    }

    var stop_level_index: u32 = maximum_level_index - 1;
    const alpha_floor_render_target: u32 = 1;
    const normal_floor_clip_rect: u32 = render_group.current_clip_rect_index;
    var alpha_floor_clip_rect: u32 = render_group.current_clip_rect_index;
    if (test_alpha > 0) {
        stop_level_index = maximum_level_index;
        alpha_floor_clip_rect =
            render_group.pushClipRect(0, 0, draw_buffer.width, draw_buffer.height, alpha_floor_render_target);
    }

    var current_absolute_z_layer: i32 = if (sim_region.entity_count > 0) sim_region.entities[0].z_layer else 0;

    var hot_entity_count: u32 = 0;
    var entity_index: u32 = 0;
    while (entity_index < sim_region.entity_count) : (entity_index += 1) {
        const entity = &sim_region.entities[entity_index];
        const entity_debug_id = debug_interface.DebugId.fromPointer(&entity.id.value);
        if (debug_interface.requested(entity_debug_id)) {
            DebugInterface.debugBeginDataBlock(@src(), "Simulation/Entity");
        }

        if (entity.hasFlag(EntityFlags.Active.toInt())) {
            if (entity.auto_boost_to.getTraversable() != null) {
                var traversable_index: u32 = 0;
                while (traversable_index < entity.traversable_count) : (traversable_index += 1) {
                    const traversable = entity.traversables[traversable_index];
                    if (traversable.occupier) |occupier| {
                        if (occupier.movement_mode == .Planted) {
                            occupier.came_from = occupier.occupying;
                            if (sim.transactionalOccupy(occupier, &occupier.occupying, entity.auto_boost_to)) {
                                occupier.movement_time = 0;
                                occupier.movement_mode = .Hopping;
                            }
                        }
                    }
                }
            }

            switch (entity.movement_mode) {
                .Planted => {},
                .Hopping => {
                    const movement_to: Vector3 = entity.occupying.getSimSpaceTraversable().position;
                    const movement_from: Vector3 = entity.came_from.getSimSpaceTraversable().position;
                    const t_jump: f32 = 0.1;
                    const t_thrust: f32 = 0.2;
                    const t_land: f32 = 0.9;

                    if (entity.movement_time < t_thrust) {
                        entity.bob_acceleration = 30;
                    }

                    if (entity.movement_time < t_land) {
                        const t: f32 = math.clamp01MapToRange(t_jump, t_land, entity.movement_time);
                        const a: Vector3 = Vector3.new(0, -2, 0);
                        const b: Vector3 = movement_to.minus(movement_from).minus(a);
                        entity.position = a.scaledTo(t * t).plus(b.scaledTo(t)).plus(movement_from);
                    }

                    if (entity.movement_time >= 1) {
                        entity.position = movement_to;
                        entity.came_from = entity.occupying;
                        entity.movement_mode = .Planted;
                        entity.bob_delta_time = -2;
                    }

                    entity.movement_time += 4 * delta_time;
                    if (entity.movement_time > 1) {
                        entity.movement_time = 1;
                    }
                },
                .AngleAttackSwipe => {
                    if (entity.movement_time < 1) {
                        entity.angle_current = math.lerpf(
                            entity.angle_start,
                            entity.angle_target,
                            entity.movement_time,
                        );

                        entity.angle_current_distance = math.lerpf(
                            entity.angle_base_distance,
                            entity.angle_swipe_distance,
                            math.triangle01(entity.movement_time),
                        );
                    } else {
                        entity.movement_mode = .AngleOffset;
                        entity.angle_current = entity.angle_target;
                        entity.angle_current_distance = entity.angle_base_distance;
                    }

                    entity.movement_time += 10 * delta_time;
                    if (entity.movement_time > 1) {
                        entity.movement_time = 1;
                    }
                },
                .AngleOffset => {},
                .Floating => {},
            }

            if (entity.movement_mode == .AngleAttackSwipe or entity.movement_mode == .AngleOffset) {
                const arm: Vector2 =
                    Vector2.arm2(entity.angle_current + entity.facing_direction)
                        .scaledTo(entity.angle_current_distance);
                entity.position = entity.angle_base.plus(.new(arm.x(), arm.y() + 0.5, 0));
            }

            const position_coefficient = 100;
            const velocity_coefficient = 10;
            entity.bob_acceleration +=
                position_coefficient * (0 - entity.bob_time) +
                velocity_coefficient * (0 - entity.bob_delta_time);
            entity.bob_time +=
                entity.bob_acceleration * delta_time * delta_time +
                entity.bob_delta_time * delta_time;
            entity.bob_delta_time += entity.bob_acceleration * delta_time;

            if (entity.velocity.lengthSquared() > 0 or entity.acceleration.lengthSquared() > 0) {
                sim.moveEntity(world_mode, sim_region, entity, delta_time, entity.acceleration);
            }

            var entity_transform = ObjectTransform.defaultUpright();
            entity_transform.offset_position = entity.getGroundPoint().minus(camera_position);

            const relative_layer: i32 = entity.z_layer - sim_region.origin.chunk_z;

            entity_transform.manual_sort = entity.manual_sort;
            entity_transform.chunk_z = entity.z_layer;

            if (relative_layer >= minimum_level_index and relative_layer <= stop_level_index) {
                if (current_absolute_z_layer != entity.z_layer) {
                    std.debug.assert(current_absolute_z_layer < entity.z_layer);
                    current_absolute_z_layer = entity.z_layer;
                    render_group.pushSortBarrier(false);
                }

                const layer_index: u32 = @intCast(relative_layer - minimum_level_index);
                if (relative_layer == maximum_level_index) {
                    render_group.current_clip_rect_index = alpha_floor_clip_rect;
                    entity_transform.color_time = .new(0, 0, 0, 0);
                } else {
                    render_group.current_clip_rect_index = normal_floor_clip_rect;
                    entity_transform.color = background_color;
                    entity_transform.color_time = Color.new(1, 1, 1, 0).scaledTo(fog_amount[layer_index]);
                }
                entity_transform.floor_z = cam_rel_ground_z[layer_index];

                var match_vector = asset.AssetVector{};
                match_vector.e[AssetTagId.FacingDirection.toInt()] = entity.facing_direction;
                var weight_vector = asset.AssetVector{};
                weight_vector.e[AssetTagId.FacingDirection.toInt()] = 1;

                // TODO:
                // * This is where articulated figures will be happening, so we need to have this code look correct in
                // terms if how we want rendering submitted.
                // * It should begin by creating a sort key for the entire armature, and then it should be able to
                // guarantee that each piece will be renndered in the order it was submitted after being sorted into
                // the scene at large by the key.
                //
                // * This should eliminate the need for RenderGroup-side sort bias as well, since now the user is in
                // control of setting the sort value specifically.
                //
                // * This also means we should be able to call a sort key transform routine that does the entity
                // basis transform and then reports the sort key to us.
                //
                // * And probably, we will want the sort keys to be u32's now, so we'll convert from float at this
                // time and that way we can use the low bits for maintaining order? Or maybe we just use a stable sort?

                if (entity.piece_count > 1) {
                    render_group.beginAggregateSortKey();
                }

                var piece_index: u32 = 0;
                while (piece_index < entity.piece_count) : (piece_index += 1) {
                    const piece: *EntityVisiblePiece = &entity.pieces[piece_index];
                    const bitmap_id: ?BitmapId =
                        transient_state.assets.getBestMatchBitmap(piece.asset_type, &match_vector, &weight_vector);

                    var x_axis: Vector2 = .new(1, 0);
                    var y_axis: Vector2 = .new(0, 1);
                    if (piece.flags & @intFromEnum(EntityVisiblePieceFlag.AxesDeform) != 0) {
                        x_axis = entity.x_axis;
                        y_axis = entity.y_axis;
                    }

                    var bob_time: f32 = 0;
                    var offset: Vector3 = .zero();
                    if (piece.flags & @intFromEnum(EntityVisiblePieceFlag.BobOffset) != 0) {
                        bob_time = entity.bob_time;
                        offset = entity.floor_displace.toVector3(0);
                        _ = offset.setY(offset.y() + bob_time);
                    }

                    render_group.pushBitmapId(
                        &entity_transform,
                        bitmap_id,
                        piece.height,
                        piece.offset.plus(offset),
                        piece.color,
                        null,
                        x_axis,
                        y_axis,
                    );
                }

                if (entity.piece_count > 1) {
                    render_group.endAggregateSortKey();
                }

                drawHitPoints(entity, render_group, &entity_transform);

                entity_transform.upright = false;
                {
                    // var volume_index: u32 = 0;
                    // while (volume_index < entity.collision.volume_count) : (volume_index += 1) {
                    //     const volume = entity.collision.volumes[volume_index];
                    //     render_group.pushRectangleOutline(
                    //         entity_transform,
                    //         volume.dimension.xy(),
                    //         volume.offset_position.minus(Vector3.new(0, 0, 0.5 * volume.dimension.z())),
                    //         Color.new(0, 0.5, 1, 1),
                    //         0.1,
                    //     );
                    // }

                    var traversable_index: u32 = 0;
                    while (traversable_index < entity.traversable_count) : (traversable_index += 1) {
                        const traversable = entity.traversables[traversable_index];
                        var color: Color = .new(0.05, 0.25, 0.05, 1);
                        if (entity.auto_boost_to.getTraversable() != null) {
                            color = .new(1, 0, 1, 1);
                        }
                        if (traversable.occupier != null) {
                            color = .new(1, 0.5, 0, 1);
                        }

                        render_group.pushRectangle(
                            &entity_transform,
                            Vector2.new(1.4, 1.4),
                            traversable.position,
                            color,
                        );

                        // render_group.pushRectangleOutline(
                        //     entity_transform,
                        //     Vector2.new(1.2, 1.2),
                        //     traversable.position,
                        //     Color.new(0, 0, 0, 1),
                        //     0.1,
                        // );
                    }
                }

                if (global_config.Simulation_VisualizeCollisionVolumes) {
                    var volume_index: u32 = 0;
                    while (volume_index < entity.collision.volume_count) : (volume_index += 1) {
                        const volume = entity.collision.volumes[volume_index];
                        const local_mouse_position = render_group.unproject(
                            &entity_transform,
                            mouse_position,
                        );

                        if (local_mouse_position.x() > -0.5 * volume.dimension.x() and
                            local_mouse_position.x() < 0.5 * volume.dimension.x() and
                            local_mouse_position.y() > -0.5 * volume.dimension.y() and
                            local_mouse_position.y() < 0.5 * volume.dimension.y())
                        {
                            debug_interface.hit(entity_debug_id, local_mouse_position.z());
                        }

                        var outline_color: Color = undefined;
                        if (debug_interface.highlighted(entity_debug_id, &outline_color)) {
                            render_group.pushRectangleOutline(
                                &entity_transform,
                                volume.dimension.xy(),
                                volume.offset_position.minus(Vector3.new(0, 0, 0.5 * volume.dimension.z())),
                                outline_color,
                                0.05,
                            );
                        }
                    }
                }
            }
        }

        if (global_config.Simulation_InspectSelectedEntity) {
            if (debug_interface.requested(entity_debug_id)) {
                DebugInterface.debugStruct(@src(), entity);
                // DebugInterface.debugBeginArray(entity.hit_points);
                // var hit_point_index: u32 = 0;
                // while (hit_point_index < entity.hit_points.len) : (hit_point_index += 1) {
                //     DebugInterface.debugValue(@src(), entity.hit_points[hit_point_index]);
                // }
                // DebugInterface.debugEndArray();
                hot_entity_count += 1;
                DebugInterface.debugEndDataBlock(@src());
            }
        }
    }

    render_group.current_clip_rect_index = normal_floor_clip_rect;
    if (test_alpha > 0) {
        render_group.pushBlendRenderTarget(test_alpha, alpha_floor_render_target);
    }
}

fn drawHitPoints(entity: *Entity, render_group: *RenderGroup, object_transform: *ObjectTransform) void {
    if (entity.hit_point_max >= 1) {
        const hit_point_dimension = Vector2.new(0.2, 0.2);
        const hit_point_spacing_x = hit_point_dimension.x() * 2;

        var hit_position =
            Vector2.new(-0.5 * @as(f32, @floatFromInt(entity.hit_point_max - 1)) * hit_point_spacing_x, -0.25);
        const hit_position_delta = Vector2.new(hit_point_spacing_x, 0);
        for (0..@intCast(entity.hit_point_max)) |hit_point_index| {
            const hit_point = entity.hit_points[hit_point_index];
            var hit_point_color = Color.new(1, 0, 0, 1);

            if (hit_point.filled_amount == 0) {
                hit_point_color = Color.new(0.2, 0.2, 0.2, 1);
            }

            render_group.pushRectangle(
                object_transform,
                hit_point_dimension,
                hit_position.toVector3(0),
                hit_point_color,
            );
            hit_position = hit_position.plus(hit_position_delta);
        }
    }
}
