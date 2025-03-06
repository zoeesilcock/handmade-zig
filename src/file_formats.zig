pub const HHA_MAGIC_VALUE = hhaCode('h', 'h', 'a', 'f');
pub const HHA_VERSION = 0;

pub const AssetFontType = enum(u32) {
    Default = 0,
    Debug = 10,
};

pub const AssetTagId = enum(u32) {
    Smoothness,
    Flatness,
    FacingDirection, // Angles in radians off of due right.
    UnicodeCodepoint,
    FontType,

    ShotIndex,
    LayerIndex,

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

    Font,
    FontGlyph,

    // Sounds.
    Bloop,
    Crack,
    Drop,
    Glide,
    Music,
    Puhp,

    OpeningCutscene,

    pub fn toInt(self: AssetTypeId) u32 {
        return @intFromEnum(self);
    }
};

pub const ASSET_TYPE_ID_COUNT = @typeInfo(AssetTypeId).@"enum".fields.len;

pub const HHAHeader = extern struct {
    magic_value: u32 = HHA_MAGIC_VALUE,
    version: u32 = HHA_VERSION,

    tag_count: u32,
    asset_type_count: u32,
    asset_count: u32,

    tags: u64 = undefined, // [tag_count]HHATag
    asset_types: u64 = undefined, // [asset_type_count]HHAAssetType
    assets: u64 = undefined, // [asset_count]HHAAsset
};

fn hhaCode(a: u32, b: u32, c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, c << 16) | @as(u32, d << 24);
}

pub const HHATag = extern struct {
    id: u32,
    value: f32,
};

pub const HHAAssetType = extern struct {
    type_id: u32 = 0,
    first_asset_index: u32 = 0,
    one_past_last_asset_index: u32 = 0,
};

pub const HHAAsset = extern struct {
    data_offset: u64 align(1),
    first_tag_index: u32,
    one_past_last_tag_index: u32,
    info: extern union {
        bitmap: HHABitmap,
        sound: HHASound,
        font: HHAFont,
    },
};

pub const HHABitmap = extern struct {
    dim: [2]u32,
    alignment_percentage: [2]f32,

    // Data looks like this:
    //
    // pixels: [dim[1]][dim[0]]u32,
};

pub const HHASoundChain = enum(u32) {
    None,
    Loop,
    Advance,
};

pub const HHASound = extern struct {
    sample_count: u32,
    channel_count: u32,
    chain: HHASoundChain,

    // Data looks like this:
    //
    // channels: [channel_count][sample_count]i16,
};

pub const HHAFontGlyph = extern struct {
    unicode_code_point: u32,
    bitmap: BitmapId,
};

pub const HHAFont = extern struct {
    one_past_highest_code_point: u32,
    glyph_count: u32,
    ascender_height: f32,
    descender_height: f32,
    external_leading: f32,

    // Data looks like this:
    //
    // code_points: [glyph_count]HHAFontGlyph,
    // horizontal_advance: [glyph_count][glyph_count]f32,
    //
    // This could also be implemented using comptime.

    pub fn getLineAdvance(self: *HHAFont) f32 {
        return self.ascender_height + self.descender_height + self.external_leading;
    }

    pub fn getStartingBaselineY(self: *HHAFont) f32 {
        return self.ascender_height;
    }
};

pub const BitmapId = extern struct {
    value: u32,

    pub fn isValid(self: *const BitmapId) bool {
        return self.value != 0;
    }
};

pub const SoundId = extern struct {
    value: u32,

    pub fn isValid(self: *const SoundId) bool {
        return self.value != 0;
    }
};

pub const FontId = extern struct {
    value: u32,

    pub fn isValid(self: *const FontId) bool {
        return self.value != 0;
    }
};
