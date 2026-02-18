pub const HHA_MAGIC_VALUE = hhaCode('h', 'h', 'a', 'f');
pub const HHA_VERSION = 1;

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

    // 0 everywhere, except if you are trying to override an existing asset,
    // in which case you set it to it's Primacy + 1.
    Primacy,

    DataType,

    pub fn toInt(self: AssetTagId) u32 {
        return @intFromEnum(self);
    }
};

pub const AssetDataTypeId = enum(u32) {
    None,

    Sprite,
    Font,
    FontGlyph,
    Sound,
};

pub const HHAHeader = extern struct {
    magic_value: u32 align(1) = HHA_MAGIC_VALUE,
    version: u32 align(1) = HHA_VERSION,

    tag_count: u32 align(1),
    asset_count: u32 align(1),

    reserved32: [12]u32 align(1) = [1]u32{0} ** 12,

    tags: u64 align(1) = undefined, // [tag_count]HHATag
    assets: u64 align(1) = undefined, // [asset_count]HHAAsset
    annotations: u64 align(1) = undefined, // [asset_count]HHAAnnotation

    reserved64: [5]u64 align(1) = [1]u64{0} ** 5,
};

pub fn hhaCode(a: u32, b: u32, c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, c << 16) | @as(u32, d << 24);
}

pub const HHATag = extern struct {
    id: u32 align(1) = 0,
    value: f32 align(1) = 0,
};

pub const HHAAnnotation = extern struct {
    source_file_date: u64 align(1) = 0,
    source_file_checksum: u64 align(1) = 0,
    source_file_base_name_offset: u64 align(1) = 0,
    asset_name_offset: u64 align(1) = 0,
    asset_description_offset: u64 align(1) = 0,
    author_offset: u64 align(1) = 0,
    reserved: [2]u64 align(1) = [1]u64{0} ** 2,

    source_file_base_name_count: u32 align(1) = 0,
    asset_name_count: u32 align(1) = 0,
    asset_description_count: u32 align(1) = 0,
    author_count: u32 align(1) = 0,

    sprite_sheet_x: u32 align(1) = 0,
    sprite_sheet_y: u32 align(1) = 0,
    reserved32: [2]u32 align(1) = [1]u32{0} ** 2,
};

pub const HHAAsset = extern struct {
    data_offset: u64 align(1) = 0,
    first_tag_index: u32 align(1) = 0,
    one_past_last_tag_index: u32 align(1) = 0,
    info: extern union {
        bitmap: HHABitmap,
        sound: HHASound,
        font: HHAFont,
    } = undefined,
};

pub const HHABitmap = extern struct {
    dim: [2]u32 = [1]u32{0} ** 2,
    alignment_percentage: [2]f32 = [1]f32{0} ** 2,

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
