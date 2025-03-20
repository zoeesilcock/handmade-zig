const shared = @import("shared.zig");
const world = @import("world.zig");
const sim = @import("sim.zig");
const math = @import("math.zig");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const MoveSpec = sim.MoveSpec;

pub const EntityId = packed struct {
    value: u32 = 0,
};

pub const EntityType = enum(u8) {
    Null,

    HeroBody,
    HeroHead,
    Wall,
    Floor,
    FloatyThing,
    Familiar,
    Monster,
    Stairwell,
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

pub const Entity = extern struct {
    id: EntityId = .{},
    updatable: bool = false,

    type: EntityType = .Null,
    flags: u32 = 0,

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

    movement_mode: EntityMovementMode,
    movement_time: f32,
    standing_on: TraversableReference,
    moving_to: TraversableReference,

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

pub const EntityReference = packed union {
    ptr: ?*Entity,
    index: EntityId,
};

pub const TraversableReference = extern struct {
    entity: EntityReference,
    index: u32,

    pub const init: TraversableReference = .{
        .entity = .{ .ptr = null },
        .index = 0,
    };

    pub fn getTraversable(self: TraversableReference) EntityTraversablePoint {
        return self.entity.ptr.?.getTraversable(self.index);
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
