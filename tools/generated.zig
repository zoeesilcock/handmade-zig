pub const SimRegionMembers = [_]MemberDefinition{
    .{ .field_type = .World, .field_name = "world", .field_offset = @offsetOf(SimRegion, "world"), .flags = .IsPointer },
    .{ .field_type = .WorldPosition, .field_name = "origin", .field_offset = @offsetOf(SimRegion, "origin"), .flags = .None },
    .{ .field_type = .Rectangle3, .field_name = "bounds", .field_offset = @offsetOf(SimRegion, "bounds"), .flags = .None },
    .{ .field_type = .Rectangle3, .field_name = "updatable_bounds", .field_offset = @offsetOf(SimRegion, "updatable_bounds"), .flags = .None },
    .{ .field_type = .u32, .field_name = "max_entity_count", .field_offset = @offsetOf(SimRegion, "max_entity_count"), .flags = .None },
    .{ .field_type = .u32, .field_name = "entity_count", .field_offset = @offsetOf(SimRegion, "entity_count"), .flags = .None },
    .{ .field_type = .Entity, .field_name = "entities", .field_offset = @offsetOf(SimRegion, "entities"), .flags = .None },
    .{ .field_type = .u32, .field_name = "max_brain_count", .field_offset = @offsetOf(SimRegion, "max_brain_count"), .flags = .None },
    .{ .field_type = .u32, .field_name = "brain_count", .field_offset = @offsetOf(SimRegion, "brain_count"), .flags = .None },
    .{ .field_type = .Brain, .field_name = "brains", .field_offset = @offsetOf(SimRegion, "brains"), .flags = .None },
    .{ .field_type = .EntityHash, .field_name = "entity_hash", .field_offset = @offsetOf(SimRegion, "entity_hash"), .flags = .IsPointer },
    .{ .field_type = .BrainHash, .field_name = "brain_hash", .field_offset = @offsetOf(SimRegion, "brain_hash"), .flags = .IsPointer },
    .{ .field_type = .u64, .field_name = "entity_hash_occupancy", .field_offset = @offsetOf(SimRegion, "entity_hash_occupancy"), .flags = .None },
    .{ .field_type = .u64, .field_name = "brain_hash_occupancy", .field_offset = @offsetOf(SimRegion, "brain_hash_occupancy"), .flags = .None },
    .{ .field_type = .Entity, .field_name = "null_entity", .field_offset = @offsetOf(SimRegion, "null_entity"), .flags = .None },
};
pub fn dumpKnownStruct(member_ptr: *anyopaque, member: *const MemberDefinition, next_indent_level: u32) void {
    var buffer: [128]u8 = undefined;
    switch (member.field_type) {
        .SimRegion => {
            debug.textLine(std.fmt.bufPrintZ(&buffer, "{s}", .{member.field_name}) catch "unknown");
            debug.debugDumpStruct(member_ptr, @ptrCast(&SimRegionMembers), SimRegionMembers.len, next_indent_level);
        },
        else => {},
    }
}
