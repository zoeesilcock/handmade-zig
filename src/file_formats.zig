const std = @import("std");
const shared = @import("shared.zig");
const types = shared.types;

pub const HHA_MAGIC_VALUE = hhaCode('h', 'h', 'a', 'f');
pub const HHA_VERSION = 1;
pub const ASSET_MAX_SPRITE_DIM = 512;
pub const ASSET_MAX_PLATE_DIM = 2048;
pub const ASSET_TAG_COUNT = @typeInfo(AssetTagId).@"enum".fields.len;
pub const ASSET_CATEGORY_COUNT = @typeInfo(AssetBasicCategory).@"enum".fields.len;

// Types.
const String = types.String;

pub const AssetFontType = enum(u32) {
    Default = 0,
    Debug = 10,
};

pub const AssetTagId = enum(u32) {
    None,
    Flatness,
    FacingDirection, // Angles in radians off of due right.
    UnicodeCodepoint,
    FontType,

    ShotIndex,
    LayerIndex,

    // 0 everywhere, except if you are trying to override an existing asset,
    // in which case you set it to it's Primacy + 1.
    Primacy,

    BasicCategory,

    Bones,
    DarkEnergy,
    Glove,
    Fingers,

    Wood,
    Stone,
    Drywall,
    Manmade,
    Wall,
    Floor,
    Grass,

    Idle,
    DodgeLeft,
    DodgeRight,
    Move,
    Hit,
    Attack1,
    Attack2,
    Surprise,
    Anger,

    Cat,
    Birman,
    Ghost,
    Tabby,
    Brown,
    Gray,
    Krampus,
    Undead,
    Broken,
    Wrapped,

    pub fn toInt(self: AssetTagId) u32 {
        return @intFromEnum(self);
    }
};

pub const HHAAssetType = enum(u32) {
    None,
    Bitmap,
    Sound,
    Font,
};

pub const AssetBasicCategory = enum(u32) {
    None,

    // Legacy categories.
    Shadow,
    Tree,
    Sword,
    Rock,
    Grass,
    Tuft,
    Stone,
    Head, // Still used.
    Cape,
    Body, // Still used.
    Font, // Still used.
    FontGlyph, // Still used.
    Bloop,
    Crack,
    Drop,
    Glide,
    Music,
    Puhp,
    OpeningCutscene, // Still used.
    Hand, // Still used.

    // New categories.
    Block,
    Cover,
    Item,
    Obstacle,
    Plate,
};

pub const HHAHeader = extern struct {
    magic_value: u32 align(1) = HHA_MAGIC_VALUE,
    version: u32 align(1) = HHA_VERSION,

    tag_count: u32 align(1) = 0,
    asset_count: u32 align(1) = 0,

    reserved32: [12]u32 align(1) = [1]u32{0} ** 12,

    tags: u64 align(1) = undefined, // [tag_count]HHATag
    assets: u64 align(1) = undefined, // [asset_count]HHAAsset
    annotations: u64 align(1) = undefined, // [asset_count]HHAAnnotation

    reserved64: [5]u64 align(1) = [1]u64{0} ** 5,
};
comptime {
    std.debug.assert(@sizeOf(HHAHeader) == (16 * 4 + 8 * 8));
}

pub fn hhaCode(a: u32, b: u32, c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, c << 16) | @as(u32, d << 24);
}

pub const HHATag = extern struct {
    id: AssetTagId align(1) = .None,
    value: f32 align(1) = 0,
};
comptime {
    std.debug.assert(@sizeOf(HHATag) == (2 * 4));
}

pub const HHAAnnotation = extern struct {
    source_file_date: u64 align(1) = 0,
    source_file_checksum: u64 align(1) = 0,
    source_file_base_name_offset: u64 align(1) = 0,
    asset_name_offset: u64 align(1) = 0,
    asset_description_offset: u64 align(1) = 0,
    author_offset: u64 align(1) = 0,
    reserved: [6]u64 align(1) = [1]u64{0} ** 6,

    source_file_base_name_count: u32 align(1) = 0,
    asset_name_count: u32 align(1) = 0,
    asset_description_count: u32 align(1) = 0,
    author_count: u32 align(1) = 0,

    sprite_sheet_x: u32 align(1) = 0,
    sprite_sheet_y: u32 align(1) = 0,
    reserved32: [2]u32 align(1) = [1]u32{0} ** 2,
};
comptime {
    std.debug.assert(@sizeOf(HHAAnnotation) == (16 * 8));
}

pub const HHAAsset = extern struct {
    data_offset: u64 align(1) = 0,
    data_size: u32 align(1) = 0,
    first_tag_index: u32 align(1) = 0,
    one_past_last_tag_index: u32 align(1) = 0,
    type: HHAAssetType align(1) = .None,

    info: extern union {
        bitmap: HHABitmap,
        sound: HHASound,
        font: HHAFont,
        max_union_size: [13]u64,
    } = undefined,
};
comptime {
    std.debug.assert(@sizeOf(HHAAsset) == (16 * 8));
}

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

const NameTag = struct {
    name: String,
    id: AssetTagId,
};

pub const name_tags = [_]NameTag{
    .{ .name = .fromSlice("none"), .id = .None },
    .{ .name = .fromSlice("Flatness"), .id = .Flatness },
    .{ .name = .fromSlice("FacingDirection"), .id = .FacingDirection },
    .{ .name = .fromSlice("UnicodeCodepoint"), .id = .UnicodeCodepoint },
    .{ .name = .fromSlice("FontType"), .id = .FontType },
    .{ .name = .fromSlice("ShotIndex"), .id = .ShotIndex },
    .{ .name = .fromSlice("LayerIndex"), .id = .LayerIndex },
    .{ .name = .fromSlice("Primacy"), .id = .Primacy },
    .{ .name = .fromSlice("BasicCategory"), .id = .BasicCategory },
    .{ .name = .fromSlice("bones"), .id = .Bones },
    .{ .name = .fromSlice("dark"), .id = .DarkEnergy },
    .{ .name = .fromSlice("darkenergy"), .id = .DarkEnergy },
    .{ .name = .fromSlice("glove"), .id = .Glove },
    .{ .name = .fromSlice("fingers"), .id = .Fingers },
    .{ .name = .fromSlice("wood"), .id = .Wood },
    .{ .name = .fromSlice("stone"), .id = .Stone },
    .{ .name = .fromSlice("drywall"), .id = .Drywall },
    .{ .name = .fromSlice("manmade"), .id = .Manmade },
    .{ .name = .fromSlice("wall"), .id = .Wall },
    .{ .name = .fromSlice("floor"), .id = .Floor },
    .{ .name = .fromSlice("grass"), .id = .Grass },
    .{ .name = .fromSlice("idle"), .id = .Idle },
    .{ .name = .fromSlice("dodgeleft"), .id = .DodgeLeft },
    .{ .name = .fromSlice("dodgeright"), .id = .DodgeRight },
    .{ .name = .fromSlice("move"), .id = .Move },
    .{ .name = .fromSlice("hit"), .id = .Hit },
    .{ .name = .fromSlice("attack1"), .id = .Attack1 },
    .{ .name = .fromSlice("attack2"), .id = .Attack2 },
    .{ .name = .fromSlice("surprise"), .id = .Surprise },
    .{ .name = .fromSlice("anger"), .id = .Anger },
    .{ .name = .fromSlice("cat"), .id = .Cat },
    .{ .name = .fromSlice("birman"), .id = .Birman },
    .{ .name = .fromSlice("ghost"), .id = .Ghost },
    .{ .name = .fromSlice("tabby"), .id = .Tabby },
    .{ .name = .fromSlice("brown"), .id = .Brown },
    .{ .name = .fromSlice("gray"), .id = .Gray },
    .{ .name = .fromSlice("krampus"), .id = .Krampus },
    .{ .name = .fromSlice("undead"), .id = .Undead },
    .{ .name = .fromSlice("broken"), .id = .Broken },
    .{ .name = .fromSlice("wrapped"), .id = .Wrapped },
};

const type_from_id = [_]struct { HHAAssetType, AssetBasicCategory }{
    .{ .None, .None },

    .{ .Bitmap, .Shadow },
    .{ .Bitmap, .Tree },
    .{ .Bitmap, .Sword },
    .{ .Bitmap, .Rock },

    .{ .Bitmap, .Grass },
    .{ .Bitmap, .Tuft },
    .{ .Bitmap, .Stone },

    .{ .Bitmap, .Head },
    .{ .Bitmap, .Cape },
    .{ .Bitmap, .Body },

    .{ .Font, .Font },
    .{ .Bitmap, .FontGlyph },

    .{ .Sound, .Bloop },
    .{ .Sound, .Crack },
    .{ .Sound, .Drop },
    .{ .Sound, .Glide },
    .{ .Sound, .Music },
    .{ .Sound, .Puhp },

    .{ .Bitmap, .OpeningCutscene },

    .{ .Bitmap, .Hand },
};

pub fn tagNameFromID(tag_id: AssetTagId) String {
    return .fromSlice(@tagName(tag_id));
}

pub fn tagIdFromName(name: String) AssetTagId {
    var result: AssetTagId = .None;
    var name_index: u32 = 0;
    while (name_index < name_tags.len) : (name_index += 1) {
        if (shared.stringBuffersEqual(name, name_tags[name_index].name)) {
            result = name_tags[name_index].id;
            break;
        }
    }
    return result;
}
