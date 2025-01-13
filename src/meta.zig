pub const FieldTypes = enum {
    u32,
    i32,
    f32,
    bool,
    SimEntity,
    SimEntityHash,
    SimRegion,
    EntityType,
    Vector2,
    Vector3,
    WorldPosition,
    SimEntityCollisionVolume,
    SimEntityCollisionVolumeGroup,
    HitPoint,
    EntityReference,
    World,
    Rectangle2,
    Rectangle3,
};

pub const MemberDefinitionFlag = enum(u32) {
    None = 0,
    IsPointer = 0x1,
};

pub const MemberDefinition = struct {
    flags: MemberDefinitionFlag,
    field_type: FieldTypes,
    field_name: []const u8,
    field_offset: u32,
};
