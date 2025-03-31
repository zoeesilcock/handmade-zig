const shared = @import("shared.zig");
const world = @import("world.zig");
const brains = @import("brains.zig");
const assets = @import("asset.zig");
const sim = @import("sim.zig");
const math = @import("math.zig");
const std = @import("std");

// Types.
const Color = math.Color;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const MoveSpec = sim.MoveSpec;
const BrainId = brains.BrainId;
const BrainType = brains.BrainType;
const BrainSlot = brains.BrainSlot;
const AssetTypeId = assets.AssetTypeId;

const MAX_CONTROLLER_COUNT = shared.MAX_CONTROLLER_COUNT;

pub const EntityId = packed struct {
    value: u32 = 0,
};

pub const EntityFlags = enum(u32) {
    Collides = (1 << 0),
    Movable = (1 << 1),
    Deleted = (1 << 2),

    pub fn toInt(self: EntityFlags) u32 {
        return @intFromEnum(self);
    }
};

pub const EntityMovementMode = enum(u32) {
    Planted,
    Hopping,
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

    //
    // Everything below here is not worked out yet.
    //

    updatable: bool = false,
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
    move_spec: MoveSpec, // Do not pack this.
    movement_time: f32,
    occupying: TraversableReference,
    came_from: TraversableReference,

    x_axis: Vector2,
    y_axis: Vector2,

    floor_displace: Vector2,

    traversable_count: u32,
    traversables: [16]EntityTraversablePoint,

    piece_count: u32,
    pieces: [4]EntityVisiblePiece,

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
        return self.isSet(EntityFlags.Deleted.toInt());
    }

    pub fn isSet(self: *const Entity, flag: u32) bool {
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
    entity: EntityReference,
    index: u32,

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
