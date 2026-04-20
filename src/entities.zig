const shared = @import("shared.zig");
const types = @import("types.zig");
const world = @import("world.zig");
const brains = @import("brains.zig");
const asset = @import("asset.zig");
const asset_rendering = @import("asset_rendering.zig");
const sim = @import("sim.zig");
const math = @import("math.zig");
const particles = @import("particles.zig");
const renderer = @import("renderer.zig");
const lighting = @import("lighting.zig");
const file_formats = shared.file_formats;
const debug_interface = @import("debug_interface.zig");
const in_game_editor = @import("in_game_editor.zig");
const std = @import("std");

// Types.
const Color = math.Color;
const Color3 = math.Color3;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const Matrix4x4 = math.Matrix4x4;
const BrainId = brains.BrainId;
const BrainType = brains.BrainType;
const BrainSlot = brains.BrainSlot;
const Assets = asset.Assets;
const AssetTypeId = asset.AssetTypeId;
const TransientState = shared.TransientState;
const SimRegion = sim.SimRegion;
const WorldPosition = world.WorldPosition;
const ManualSortKey = renderer.ManualSortKey;
const ParticleCache = particles.ParticleCache;
const RenderGroup = renderer.RenderGroup;
const TransientClipRect = renderer.TransientClipRect;
const RenderTransform = renderer.RenderTransform;
const AssetTagId = file_formats.AssetTagId;
const AssetBasicCategory = file_formats.AssetBasicCategory;
const BitmapId = file_formats.BitmapId;
const HHAAlignPoint = file_formats.HHAAlignPoint;
const DebugInterface = debug_interface.DebugInterface;
const TimedBlock = debug_interface.TimedBlock;
const LightingPoint = lighting.LightingPoint;
const LightingPointState = renderer.LightingPointState;
const EditableHitTest = in_game_editor.EditableHitTest;
const LIGHT_POINTS_PER_CHUNK = renderer.LIGHT_POINTS_PER_CHUNK;

const ENTITY_MAX_PIECE_COUNT = 4;
const MAX_CONTROLLER_COUNT = shared.MAX_CONTROLLER_COUNT;
pub const INTERNAL = @import("build_options").internal;
var global_config = &@import("config.zig").global_config;

pub const EntityId = packed struct {
    value: u32 = 0,

    pub fn equals(self: EntityId, other: EntityId) bool {
        return self.value == other.value;
    }

    pub fn clear(self: *EntityId) void {
        self.value = 0;
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

pub const BitmapPiece = extern struct {
    // Parents must ALWAYS come before children.
    parent_piece: u8,
    parent_align_type: u8, // file_formats.HHAAlignPointType,
    child_align_type: u8, // file_formats.HHAAlignPointType,
    reserved: u8,
};

pub const EntityVisiblePieceFlag = enum(u32) {
    AxesDeform = 0x1,
    BobOffset = 0x2,
    Cube = 0x4,
    Light = 0x8,
};

pub const EntityVisiblePiece = extern struct {
    color: Color,
    offset: Vector3,
    dimension: Vector3,

    flags: u32,
    category: AssetBasicCategory,

    extra: extern union {
        bitmap: BitmapPiece,
        cube_uv_layout: renderer.CubeUVLayout,
    },

    pub fn isBitmap(self: *EntityVisiblePiece) bool {
        return (self.flags &
            (@intFromEnum(EntityVisiblePieceFlag.Cube) | @intFromEnum(EntityVisiblePieceFlag.Light))) == 0;
    }
};

pub const CameraBehavior = enum(u32) {
    Inspect = 0x1,
    Offset = 0x2,
    ViewPlayer = 0x4,
    GeneralVelocityConstraint = 0x8,
    DirectionalVelocityConstraint = 0x10,
};

pub const Entity = extern struct {
    id: EntityId = .{},

    brain_slot: BrainSlot = .{},
    brain_id: BrainId = .{},

    camera_behavior: u32,
    camera_min_velocity: f32,
    camera_max_velocity: f32,
    camera_min_time: f32,
    camera_offset: Vector3,
    camera_velocity_direction: Vector3,

    //
    // This lighting data will get "cleaned" whenever a chunk isn't used for one frame.
    //
    lighting: [ENTITY_MAX_PIECE_COUNT][LIGHT_POINTS_PER_CHUNK]LightingPointState,

    //
    // Everything below here is not worked out yet.
    //
    tag_count: u32 = 0,
    tags: [8]AssetTagId = [1]AssetTagId{.None} ** 8,
    tag_values: [8]f32 = [1]f32{0} ** 8,
    flags: u32 = 0,

    position: Vector3 = Vector3.zero(),
    velocity: Vector3 = Vector3.zero(),
    acceleration: Vector3 = Vector3.zero(), // Do not pack this.

    distance_limit: f32 = 0,

    collision_volume: Rectangle3,

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
    pieces: [ENTITY_MAX_PIECE_COUNT]EntityVisiblePiece,

    auto_boost_to: TraversableReference,

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

    pub fn addTag(self: *Entity, tag_id: AssetTagId, value: f32) void {
        std.debug.assert(self.tag_count < self.tags.len);

        const tag_index: u32 = self.tag_count;
        self.tag_count += 1;

        self.tags[tag_index] = tag_id;
        self.tag_values[tag_index] = value;
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

pub const EntityTraversablePoint = extern struct {
    position: Vector3,
    occupier: ?*Entity,
};

pub fn updateAndRenderEntities(
    sim_region: *SimRegion,
    delta_time: f32,
    // Optional...
    opt_render_group: ?*RenderGroup,
    particle_cache: ?*ParticleCache,
    opt_assets: ?*Assets,
    hit_test: *EditableHitTest,
) void {
    TimedBlock.beginFunction(@src(), .UpdateAndRenderEntities);
    defer TimedBlock.endFunction(@src(), .UpdateAndRenderEntities);

    var picking_origin: Vector3 = .zero();
    var picking_ray: Vector3 = .zero();
    if (hit_test.shouldHitTest()) {
        if (opt_render_group) |render_group| {
            const transform: *RenderTransform = &render_group.debug_transform;
            const cursor_in_world: Vector3 = render_group.unproject(
                transform,
                hit_test.clip_space_mouse_position,
                1,
            );
            picking_origin = transform.position;
            picking_ray = cursor_in_world.minus(picking_origin).normalizeOrZero();
        }
    }

    var entity_index: u32 = 0;
    while (entity_index < sim_region.entity_count) : (entity_index += 1) {
        const entity = &sim_region.entities[entity_index];

        if (entity.hasFlag(EntityFlags.Active.toInt())) {
            TimedBlock.beginBlock(@src(), .EntityBoost);

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

            TimedBlock.endBlock(@src(), .EntityBoost);

            TimedBlock.beginBlock(@src(), .EntityPhysics);

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

                        particles.spawnFire(particle_cache, entity.position);
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
                sim.moveEntity(sim_region, entity, delta_time, entity.acceleration);
            }

            TimedBlock.endBlock(@src(), .EntityPhysics);

            TimedBlock.beginBlock(@src(), .EntityRender);
            if (opt_render_group) |render_group| {
                const entity_ground_point: Vector3 = entity.getGroundPoint();

                var match_vector = asset.AssetVector{};
                match_vector.e[AssetTagId.FacingDirection.toInt()] = entity.facing_direction;
                var weight_vector = asset.AssetVector{};
                weight_vector.e[AssetTagId.FacingDirection.toInt()] = 1;

                var match_index: u32 = 0;
                while (match_index < entity.tag_count) : (match_index += 1) {
                    const id: AssetTagId = entity.tags[match_index];
                    match_vector.e[id.toInt()] = entity.tag_values[match_index];
                    weight_vector.e[id.toInt()] = 1;
                }

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

                TimedBlock.beginBlock(@src(), .EntityRenderPieces);

                // var piece_transforms: [ENTITY_MAX_PIECE_COUNT]Matrix4x4 = undefined;

                var piece_index: u32 = 0;
                while (piece_index < entity.piece_count) : (piece_index += 1) {
                    const piece: *EntityVisiblePiece = &entity.pieces[piece_index];
                    var bitmap_id: ?BitmapId = null;
                    if (opt_assets) |assets| {
                        bitmap_id = assets.getBestMatchBitmap(piece.category, &match_vector, &weight_vector);
                    }

                    var world_radius: Vector3 = piece.dimension;

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

                    var color: Color = piece.color;
                    _ = color.setA(color.a() * (1.0 - 0.5 * match_vector.e[@intFromEnum(AssetTagId.Ghost)]));

                    const dev_id: types.DevId = .fromU32s(entity.id.value, piece_index, @src());
                    const highlighted: bool = dev_id.equals(hit_test.highlight_id);

                    if (piece.flags & @intFromEnum(EntityVisiblePieceFlag.Light) != 0) {
                        asset_rendering.pushCubeLight(
                            render_group,
                            entity_ground_point.plus(piece.offset),
                            piece.dimension,
                            color.rgb(),
                            color.a(),
                            @ptrCast(&entity.lighting[piece_index]),
                        );
                    } else if (piece.flags & @intFromEnum(EntityVisiblePieceFlag.Cube) != 0) {
                        asset_rendering.pushCubeBitmapId(
                            render_group,
                            bitmap_id,
                            entity_ground_point.plus(piece.offset),
                            piece.dimension,
                            color,
                            piece.extra.cube_uv_layout,
                            null,
                            @ptrCast(&entity.lighting[piece_index]),
                        );
                    } else {
                        _ = world_radius.setX(world_radius.y());
                        _ = world_radius.setZ(0.1);

                        if (opt_assets) |assets| {
                            if (bitmap_id) |id| {
                                const bitmap_info: *file_formats.HHABitmap = assets.getBitmapInfo(id);
                                if (assets.getBitmap(id)) |bitmap| {
                                    const align_percentage: Vector2 = bitmap_info.getFirstAlign();

                                    var bitmap_dim = asset_rendering.getBitmapDim(
                                        bitmap,
                                        piece.dimension.y(),
                                        entity_ground_point.plus(piece.offset.plus(offset)),
                                        align_percentage,
                                        x_axis,
                                        y_axis,
                                    );

                                    asset_rendering.pushBitmapWithDim(
                                        render_group,
                                        true,
                                        &bitmap_dim,
                                        bitmap,
                                        piece.dimension.y(),
                                        entity_ground_point.plus(piece.offset.plus(offset)),
                                        color,
                                        align_percentage,
                                        x_axis,
                                        y_axis,
                                    );

                                    if (highlighted) {
                                        var ap_index: u32 = 0;
                                        while (ap_index < bitmap_info.align_points.len) : (ap_index += 1) {
                                            const ap: HHAAlignPoint = bitmap_info.align_points[ap_index];

                                            if (hit_test.shouldDrawAlignPoint(ap_index) and ap.getType() != .None) {
                                                const temp_dim = asset_rendering.getBitmapDim(
                                                    bitmap,
                                                    piece.dimension.y(),
                                                    bitmap_dim.position,
                                                    ap.getPositionPercent().negated(),
                                                    x_axis,
                                                    y_axis,
                                                );

                                                render_group.pushCube(
                                                    render_group.white_texture,
                                                    temp_dim.position,
                                                    .splat(0.04),
                                                    shared.getDebugColor4(ap_index, null),
                                                    null,
                                                    null,
                                                    null,
                                                    3,
                                                );
                                            }
                                        }
                                    }
                                } else {
                                    assets.loadBitmap(id, false);
                                    render_group.missing_resource_count += 1;
                                }
                            }
                        }
                    }

                    if (bitmap_id != null) {
                        if (hit_test.shouldHitTest()) {
                            const world_position: Vector3 = entity_ground_point.plus(piece.offset);

                            const t_hit = picking_origin.rayIntersectsBox(picking_ray, world_position, world_radius);
                            if (t_hit < std.math.floatMax(f32)) {
                                hit_test.addHit(dev_id, bitmap_id.?.value, t_hit);
                            }
                        }

                        if (highlighted) {
                            render_group.pushVolumeOutline(
                                .fromCenterHalfDimension(entity_ground_point.plus(piece.offset), world_radius),
                                hit_test.highlight_color,
                                0.1,
                            );
                        }
                    }
                }
                TimedBlock.endBlock(@src(), .EntityRenderPieces);

                TimedBlock.beginBlock(@src(), .EntityRenderHitpoints);
                drawHitPoints(entity, render_group, entity_ground_point);
                TimedBlock.endBlock(@src(), .EntityRenderHitpoints);

                TimedBlock.beginBlock(@src(), .EntityRenderVolume);
                {
                    if (global_config.Simulation_VisualizeCollisionVolumes) {
                        if (entity.collision_volume.hasArea()) {
                            var color: Color = .new(0, 0.5, 1, 1);

                            if (entity.hasFlag(EntityFlags.Collides.toInt())) {
                                color = .new(1, 0, 1, 1);
                            }

                            render_group.pushVolumeOutline(entity.collision_volume, color, 0.01);
                        }
                    }

                    if (false) {
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
                                traversable.position,
                                Vector2.new(1.4, 1.4),
                                color,
                            );

                            // render_group.pushRectangleOutline(
                            //     Vector2.new(1.2, 1.2),
                            //     traversable.position,
                            //     Color.new(0, 0, 0, 1),
                            //     0.1,
                            // );
                        }
                    }
                }
                TimedBlock.endBlock(@src(), .EntityRenderVolume);
                TimedBlock.endBlock(@src(), .EntityRender);
            }
        }
    }
}

fn drawHitPoints(entity: *Entity, render_group: *RenderGroup, ground_point: Vector3) void {
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
                ground_point.plus(hit_position.toVector3(0.1)),
                hit_point_dimension,
                hit_point_color,
            );
            hit_position = hit_position.plus(hit_position_delta);
        }
    }
}
