pub const AssetTagId = enum(u32) {
    Smoothness,
    Flatness,
    FacingDirection, // Angles in radians off of due right.

    pub fn toInt(self: AssetTagId) u32 {
        return @intFromEnum(self);
    }
};
pub const AssetTypeId = enum(u32) {
    None,

    // Bitmaps.
    Shadow,
    Tree,
    Sword,
    Rock,

    Grass,
    Tuft,
    Stone,

    Head,
    Cape,
    Torso,

    // Sounds.
    Bloop,
    Crack,
    Drop,
    Glide,
    Music,
    Puhp,

    pub fn toInt(self: AssetTypeId) u32 {
        return @intFromEnum(self);
    }
};

pub const COUNT = @typeInfo(AssetTypeId).Enum.fields.len;

