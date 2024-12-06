const meta = @import("meta.zig");
const std = @import("std");
const sim = @import("sim.zig");
const math = @import("math.zig");
const world = @import("world.zig");
const debug = @import("debug.zig");

const MemberDefinition = meta.MemberDefinition;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const SimEntity = sim.SimEntity;
const SimRegion = sim.SimRegion;
const SimEntityCollisionVolume = sim.SimEntityCollisionVolume;
const SimEntityCollisionVolumeGroup = sim.SimEntityCollisionVolumeGroup;
const WorldPosition = world.WorldPosition;

pub const SimRegionMembers = [_]MemberDefinition{
    .{ .field_type = .World, .field_name = "world", .field_offset = @offsetOf(SimRegion, "world"), .flags = .IsPointer },
    .{ .field_type = .f32, .field_name = "max_entity_radius", .field_offset = @offsetOf(SimRegion, "max_entity_radius"), .flags = .None },
    .{ .field_type = .f32, .field_name = "max_entity_velocity", .field_offset = @offsetOf(SimRegion, "max_entity_velocity"), .flags = .None },
    .{ .field_type = .WorldPosition, .field_name = "origin", .field_offset = @offsetOf(SimRegion, "origin"), .flags = .None },
    .{ .field_type = .Rectangle3, .field_name = "bounds", .field_offset = @offsetOf(SimRegion, "bounds"), .flags = .None },
    .{ .field_type = .Rectangle3, .field_name = "updatable_bounds", .field_offset = @offsetOf(SimRegion, "updatable_bounds"), .flags = .None },
    .{ .field_type = .u32, .field_name = "max_entity_count", .field_offset = @offsetOf(SimRegion, "max_entity_count"), .flags = .None },
    .{ .field_type = .u32, .field_name = "entity_count", .field_offset = @offsetOf(SimRegion, "entity_count"), .flags = .None },
    // .{ .field_type = .SimEntity, .field_name = "entities", .field_offset = @offsetOf(SimRegion, "entities"), .flags = .None },
    .{ .field_type = .SimEntityHash, .field_name = "sim_entity_hash", .field_offset = @offsetOf(SimRegion, "sim_entity_hash"), .flags = .IsPointer },
};
pub const SimEntityCollisionVolumeMembers = [_]MemberDefinition{
    .{ .field_type = .Vector3, .field_name = "offset_position", .field_offset = @offsetOf(SimEntityCollisionVolume, "offset_position"), .flags = .None },
    .{ .field_type = .Vector3, .field_name = "dimension", .field_offset = @offsetOf(SimEntityCollisionVolume, "dimension"), .flags = .None },
};
pub const SimEntityCollisionVolumeGroupMembers = [_]MemberDefinition{
    .{ .field_type = .SimEntityCollisionVolume, .field_name = "total_volume", .field_offset = @offsetOf(SimEntityCollisionVolumeGroup, "total_volume"), .flags = .None },
    .{ .field_type = .u32, .field_name = "volume_count", .field_offset = @offsetOf(SimEntityCollisionVolumeGroup, "volume_count"), .flags = .None },
    .{ .field_type = .SimEntityCollisionVolume, .field_name = "volumes", .field_offset = @offsetOf(SimEntityCollisionVolumeGroup, "volumes"), .flags = .None },
};
pub const SimEntityMembers = [_]MemberDefinition{
    .{ .field_type = .u32, .field_name = "storage_index", .field_offset = @offsetOf(SimEntity, "storage_index"), .flags = .None },
    .{ .field_type = .bool, .field_name = "updatable", .field_offset = @offsetOf(SimEntity, "updatable"), .flags = .None },
    .{ .field_type = .EntityType, .field_name = "type", .field_offset = @offsetOf(SimEntity, "type"), .flags = .None },
    .{ .field_type = .u32, .field_name = "flags", .field_offset = @offsetOf(SimEntity, "flags"), .flags = .None },
    .{ .field_type = .Vector3, .field_name = "position", .field_offset = @offsetOf(SimEntity, "position"), .flags = .None },
    .{ .field_type = .Vector3, .field_name = "velocity", .field_offset = @offsetOf(SimEntity, "velocity"), .flags = .None },
    .{ .field_type = .SimEntityCollisionVolumeGroup, .field_name = "collision", .field_offset = @offsetOf(SimEntity, "collision"), .flags = .IsPointer },
    .{ .field_type = .f32, .field_name = "distance_limit", .field_offset = @offsetOf(SimEntity, "distance_limit"), .flags = .None },
    .{ .field_type = .f32, .field_name = "facing_direction", .field_offset = @offsetOf(SimEntity, "facing_direction"), .flags = .None },
    .{ .field_type = .f32, .field_name = "head_bob_time", .field_offset = @offsetOf(SimEntity, "head_bob_time"), .flags = .None },
    .{ .field_type = .i32, .field_name = "abs_tile_z_delta", .field_offset = @offsetOf(SimEntity, "abs_tile_z_delta"), .flags = .None },
    .{ .field_type = .u32, .field_name = "hit_point_max", .field_offset = @offsetOf(SimEntity, "hit_point_max"), .flags = .None },
    .{ .field_type = .HitPoint, .field_name = "hit_points", .field_offset = @offsetOf(SimEntity, "hit_points"), .flags = .None },
    .{ .field_type = .EntityReference, .field_name = "sword", .field_offset = @offsetOf(SimEntity, "sword"), .flags = .None },
    .{ .field_type = .Vector2, .field_name = "walkable_dimension", .field_offset = @offsetOf(SimEntity, "walkable_dimension"), .flags = .None },
    .{ .field_type = .f32, .field_name = "walkable_height", .field_offset = @offsetOf(SimEntity, "walkable_height"), .flags = .None },
};
pub const WorldPositionMembers = [_]MemberDefinition{
    .{ .field_type = .i32, .field_name = "chunk_x", .field_offset = @offsetOf(WorldPosition, "chunk_x"), .flags = .None },
    .{ .field_type = .i32, .field_name = "chunk_y", .field_offset = @offsetOf(WorldPosition, "chunk_y"), .flags = .None },
    .{ .field_type = .i32, .field_name = "chunk_z", .field_offset = @offsetOf(WorldPosition, "chunk_z"), .flags = .None },
    .{ .field_type = .Vector3, .field_name = "offset", .field_offset = @offsetOf(WorldPosition, "offset"), .flags = .None },
};
pub const Rectangle2Members = [_]MemberDefinition{
    .{ .field_type = .Vector2, .field_name = "min", .field_offset = @offsetOf(Rectangle2, "min"), .flags = .None },
    .{ .field_type = .Vector2, .field_name = "max", .field_offset = @offsetOf(Rectangle2, "max"), .flags = .None },
};
pub const Rectangle3Members = [_]MemberDefinition{
    .{ .field_type = .Vector3, .field_name = "min", .field_offset = @offsetOf(Rectangle3, "min"), .flags = .None },
    .{ .field_type = .Vector3, .field_name = "max", .field_offset = @offsetOf(Rectangle3, "max"), .flags = .None },
};

pub fn dumpKnownStruct(member_ptr: *anyopaque, member: *const MemberDefinition, next_indent_level: u32) void {
    var buffer: [128]u8 = undefined;
    switch(member.field_type) {
        .SimEntity => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{ member.field_name }) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&SimEntityMembers), SimEntityMembers.len, next_indent_level);
        },
        .SimEntityCollisionVolumeGroup => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{ member.field_name }) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&SimEntityCollisionVolumeGroupMembers), SimEntityCollisionVolumeGroupMembers.len, next_indent_level);
        },
        .SimEntityCollisionVolume => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{ member.field_name }) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&SimEntityCollisionVolumeMembers), SimEntityCollisionVolumeMembers.len, next_indent_level);
        },
        .SimRegion => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{ member.field_name }) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&SimRegionMembers), SimRegionMembers.len, next_indent_level);
        },
        .WorldPosition => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{ member.field_name }) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&WorldPositionMembers), WorldPositionMembers.len, next_indent_level);
        },
        .Rectangle2 => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{ member.field_name }) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&Rectangle2Members), Rectangle2Members.len, next_indent_level);
        },
        .Rectangle3 => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{ member.field_name }) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&Rectangle3Members), Rectangle3Members.len, next_indent_level);
        },
        else => {},
    }
}
