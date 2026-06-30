const std = @import("std");
const shared = @import("shared.zig");
const math = shared.math;
const types = shared.types;
const intrinsics = shared.intrinsics;

pub const HHA_MAGIC_VALUE = hhaCode('h', 'h', 'a', 'f');
pub const HHA_VERSION = 2;
pub const ASSET_MAX_SPRITE_DIM = 512;
pub const ASSET_MAX_PLATE_DIM = 2048;
pub const ASSET_TAG_COUNT = @typeInfo(AssetTagId).@"enum".fields.len;
pub const ASSET_CATEGORY_COUNT = @typeInfo(AssetBasicCategory).@"enum".fields.len;

// Types.
const String = types.String;
const Vector2 = math.Vector2;

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
    Dodge,
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

    Orphan,

    Baby,
    Hero,
    Brahm,
    Carla,
    Cassidy,
    Drew,
    Dylan,
    Giles,
    Kline,
    Laird,
    Lambert,
    Rhoda,
    Slade,
    Sunny,
    Viva,

    Cook,
    Earth,
    Fall,
    Health,
    Fauna,
    Speed,
    Spring,
    Strength,
    Summer,
    Tailor,
    Tank,
    Winter,

    IntroCutscene,
    TitleScreen,

    Bloop,
    Crack,
    Drop,
    Glide,
    Puhp,

    Variant,
    ChannelIndex,

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
    Audio,

    pub fn toString(self: AssetBasicCategory) String {
        return .fromSlice(@tagName(self));
    }
};

pub const HHAHeader = extern struct {
    magic_value: u32 align(1) = HHA_MAGIC_VALUE,
    version: u32 align(1) = HHA_VERSION,

    tag_count: u32 align(1) = 0,
    asset_count: u32 align(1) = 0,

    reserved32: [12]u32 align(1) = @splat(0),

    tags: u64 align(1) = undefined, // [tag_count]HHATag
    assets: u64 align(1) = undefined, // [asset_count]HHAAsset
    annotations: u64 align(1) = undefined, // [asset_count]HHAAnnotation

    reserved64: [5]u64 align(1) = @splat(0),
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

    pub fn equals(self: HHATag, other: HHATag) bool {
        return self.id == other.id and self.value == other.value;
    }
};
comptime {
    std.debug.assert(@sizeOf(HHATag) == (2 * 4));
}

pub const HHAAnnotation = extern struct {
    // TODO: Should we start also storing machine-specific source_file_date out-of-band so that we don't have to
    // update HHAs when dates change but checksums don't?
    source_file_date: u64 align(1) = 0,
    source_file_checksum: u64 align(1) = 0,
    source_file_base_name_offset: u64 align(1) = 0,
    asset_name_offset: u64 align(1) = 0,
    asset_description_offset: u64 align(1) = 0,
    author_offset: u64 align(1) = 0,
    error_stream_offset: u64 align(1) = 0,
    hht_block_checksum: u64 align(1) = 0,
    reserved: [3]u64 align(1) = @splat(0),

    error_stream_count: u32 align(1) = 0,
    reserved32: u32 align(1) = 0,
    source_file_base_name_count: u32 align(1) = 0,
    asset_name_count: u32 align(1) = 0,
    asset_description_count: u32 align(1) = 0,
    author_count: u32 align(1) = 0,

    sprite_sheet_x: u32 align(1) = 0,
    sprite_sheet_y: u32 align(1) = 0,
    reserved32_2: [2]u32 align(1) = @splat(0),
};
comptime {
    std.debug.assert(@sizeOf(HHAAnnotation) == (16 * 8));
}

pub const LoadedHHAAnnotation = struct {
    source_file_date: u64 align(1) = 0,
    source_file_checksum: u64 align(1) = 0,
    hht_block_checksum: u64 align(1) = 0,
    sprite_sheet_x: u32 align(1) = 0,
    sprite_sheet_y: u32 align(1) = 0,

    source_file_base_name: String = .empty,
    asset_name: String = .empty,
    asset_description: String = .empty,
    author: String = .empty,
    error_stream: String = .empty,
};

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
    } align(1) = undefined,
};
comptime {
    std.debug.assert(@sizeOf(HHAAsset) == (16 * 8));
}

// Note: The decrement by 1 here is to avoid ToParent being counted. Adjust this if you add more non-sequential entries.
pub const HHA_ALIGN_POINT_TYPE_COUNT: u32 = @typeInfo(HHAAlignPointType).@"enum".fields.len - 1;
pub const HHAAlignPointType = enum(u16) {
    None,

    Default,

    TopOfHead,
    BaseOfNeck,

    ToParent = 0x8000,
};

pub const HHAAlignPoint = extern struct {
    position_percent: [2]u16 align(1) = @splat(0),
    size: u16 align(1) = 0,
    align_type: u16 align(1) = 0,

    pub fn set(
        self: *align(1) HHAAlignPoint,
        align_point_type: HHAAlignPointType,
        to_parent: bool,
        size: f32,
        position_percent: Vector2,
    ) void {
        self.position_percent[0] = @intCast(
            intrinsics.roundReal32ToUInt32(
                math.clamp01MapToRange(
                    -2,
                    2,
                    position_percent.x(),
                ) * @as(f32, @floatFromInt(std.math.maxInt(u16) - 1)),
            ),
        );
        self.position_percent[1] = @intCast(
            intrinsics.roundReal32ToUInt32(
                math.clamp01MapToRange(
                    -2,
                    2,
                    position_percent.y(),
                ) * @as(f32, @floatFromInt(std.math.maxInt(u16) - 1)),
            ),
        );
        self.size = @intCast(
            intrinsics.roundReal32ToUInt32((size * @as(f32, @floatFromInt(std.math.maxInt(u16)))) / 85.0),
        );
        self.align_type =
            @intFromEnum(align_point_type) | if (to_parent) @intFromEnum(HHAAlignPointType.ToParent) else 0;
    }

    pub fn isToParent(self: HHAAlignPoint) bool {
        return (self.align_type & @intFromEnum(HHAAlignPointType.ToParent)) != 0;
    }

    pub fn getType(self: HHAAlignPoint) HHAAlignPointType {
        return @enumFromInt(self.align_type & ~@intFromEnum(HHAAlignPointType.ToParent));
    }

    pub fn getPositionPercent(self: HHAAlignPoint) Vector2 {
        return .new(
            -2 + 4 * (@as(f32, @floatFromInt(self.position_percent[0])) /
                @as(f32, @floatFromInt(std.math.maxInt(u16) - 1))),
            -2 + 4 * (@as(f32, @floatFromInt(self.position_percent[1])) /
                @as(f32, @floatFromInt(std.math.maxInt(u16) - 1))),
        );
    }

    pub fn getSize(self: HHAAlignPoint) f32 {
        return (85.0 * @as(f32, @floatFromInt(self.size))) / @as(f32, @floatFromInt(std.math.maxInt(u16)));
    }
};

pub const HHA_BITMAP_ALIGN_POINT_COUNT = 12;
pub const HHABitmap = extern struct {
    // These are imported from txt file augmentation of the PNG.
    align_points: [HHA_BITMAP_ALIGN_POINT_COUNT]HHAAlignPoint align(1) = @splat(.{}),

    dim: [2]u16 align(1) = @splat(0),
    orig_dim: [2]u16 align(1) = @splat(0),

    // Data looks like this:
    //
    // pixels: [dim[1]][dim[0]]u16,

    pub fn getFirstAlign(self: *HHABitmap) Vector2 {
        var result: Vector2 = .new(0.5, 0.5);

        if (self.align_points[0].align_type != 0) {
            result = self.align_points[0].getPositionPercent();
        }

        return result;
    }

    pub fn findAlign(self: *HHABitmap, complete_type: u32) HHAAlignPoint {
        var result: HHAAlignPoint = .{};

        var point_index: u32 = 0;
        while (point_index < self.align_points.len) : (point_index += 1) {
            if (self.align_points[point_index].align_type == complete_type) {
                result = self.align_points[point_index];
                break;
            }
        }

        if (complete_type == (@intFromEnum(HHAAlignPointType.Default) | @intFromEnum(HHAAlignPointType.ToParent)) and
            result.align_type == 0)
        {
            result.set(.Default, true, 1.0, .new(0.5, 0.5));
        }

        return result;
    }
};

pub const HHASoundChain = enum(u32) {
    None,
    Loop,
    Advance,
};

pub const HHA_MAX_SOUND_SAMPLE_COUNT = 24000;
pub const HHASound = extern struct {
    // The sample_count and channel_count are the total samples and channels for the sound, even though it is broken
    // up into chunks and split across assets, one per channel per chunk.
    sample_count: u32 align(1) = 0,
    channel_count: u32 align(1) = 0,
    chain: HHASoundChain align(1) = .None,

    // Data looks like this:
    //
    // channels: [sample_count]i16,
};

pub const HHAFontGlyph = extern struct {
    unicode_code_point: u32,
    bitmap: BitmapId,
};

pub const HHAFont = extern struct {
    one_past_highest_code_point: u32 align(1),
    glyph_count: u32 align(1),
    ascender_height: f32 align(1),
    descender_height: f32 align(1),
    external_leading: f32 align(1),

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
    .{ .name = .fromSlice("None"), .id = .None },
    .{ .name = .fromSlice("Flatness"), .id = .Flatness },
    .{ .name = .fromSlice("FacingDirection"), .id = .FacingDirection },
    .{ .name = .fromSlice("UnicodeCodepoint"), .id = .UnicodeCodepoint },
    .{ .name = .fromSlice("FontType"), .id = .FontType },
    .{ .name = .fromSlice("ShotIndex"), .id = .ShotIndex },
    .{ .name = .fromSlice("LayerIndex"), .id = .LayerIndex },
    .{ .name = .fromSlice("Primacy"), .id = .Primacy },
    .{ .name = .fromSlice("BasicCategory"), .id = .BasicCategory },
    .{ .name = .fromSlice("Bones"), .id = .Bones },
    .{ .name = .fromSlice("Dark"), .id = .DarkEnergy },
    .{ .name = .fromSlice("Darkenergy"), .id = .DarkEnergy },
    .{ .name = .fromSlice("Glove"), .id = .Glove },
    .{ .name = .fromSlice("Fingers"), .id = .Fingers },
    .{ .name = .fromSlice("Wood"), .id = .Wood },
    .{ .name = .fromSlice("Stone"), .id = .Stone },
    .{ .name = .fromSlice("Drywall"), .id = .Drywall },
    .{ .name = .fromSlice("Manmade"), .id = .Manmade },
    .{ .name = .fromSlice("Wall"), .id = .Wall },
    .{ .name = .fromSlice("Floor"), .id = .Floor },
    .{ .name = .fromSlice("Grass"), .id = .Grass },
    .{ .name = .fromSlice("Idle"), .id = .Idle },
    .{ .name = .fromSlice("Dodge"), .id = .Dodge },
    .{ .name = .fromSlice("Move"), .id = .Move },
    .{ .name = .fromSlice("Hit"), .id = .Hit },
    .{ .name = .fromSlice("Attack1"), .id = .Attack1 },
    .{ .name = .fromSlice("Attack2"), .id = .Attack2 },
    .{ .name = .fromSlice("Surprise"), .id = .Surprise },
    .{ .name = .fromSlice("Anger"), .id = .Anger },
    .{ .name = .fromSlice("Cat"), .id = .Cat },
    .{ .name = .fromSlice("Birman"), .id = .Birman },
    .{ .name = .fromSlice("Ghost"), .id = .Ghost },
    .{ .name = .fromSlice("Tabby"), .id = .Tabby },
    .{ .name = .fromSlice("Brown"), .id = .Brown },
    .{ .name = .fromSlice("Gray"), .id = .Gray },
    .{ .name = .fromSlice("Krampus"), .id = .Krampus },
    .{ .name = .fromSlice("Undead"), .id = .Undead },
    .{ .name = .fromSlice("Broken"), .id = .Broken },
    .{ .name = .fromSlice("Wrapped"), .id = .Wrapped },

    .{ .name = .fromSlice("Orphan"), .id = .Orphan },

    .{ .name = .fromSlice("Baby"), .id = .Baby },
    .{ .name = .fromSlice("Hero"), .id = .Hero },
    .{ .name = .fromSlice("Brahm"), .id = .Brahm },
    .{ .name = .fromSlice("Carla"), .id = .Carla },
    .{ .name = .fromSlice("Cassidy"), .id = .Cassidy },
    .{ .name = .fromSlice("Drew"), .id = .Drew },
    .{ .name = .fromSlice("Dylan"), .id = .Dylan },
    .{ .name = .fromSlice("Giles"), .id = .Giles },
    .{ .name = .fromSlice("Kline"), .id = .Kline },
    .{ .name = .fromSlice("Laird"), .id = .Laird },
    .{ .name = .fromSlice("Lambert"), .id = .Lambert },
    .{ .name = .fromSlice("Rhoda"), .id = .Rhoda },
    .{ .name = .fromSlice("Slade"), .id = .Slade },
    .{ .name = .fromSlice("Sunny"), .id = .Sunny },
    .{ .name = .fromSlice("Viva"), .id = .Viva },

    .{ .name = .fromSlice("Cook"), .id = .Cook },
    .{ .name = .fromSlice("Earth"), .id = .Earth },
    .{ .name = .fromSlice("Fall"), .id = .Fall },
    .{ .name = .fromSlice("Health"), .id = .Health },
    .{ .name = .fromSlice("Fauna"), .id = .Fauna },
    .{ .name = .fromSlice("Speed"), .id = .Speed },
    .{ .name = .fromSlice("Spring"), .id = .Spring },
    .{ .name = .fromSlice("Strength"), .id = .Strength },
    .{ .name = .fromSlice("Summer"), .id = .Summer },
    .{ .name = .fromSlice("Tailor"), .id = .Tailor },
    .{ .name = .fromSlice("Tank"), .id = .Tank },
    .{ .name = .fromSlice("Winter"), .id = .Winter },

    .{ .name = .fromSlice("IntroCutscene"), .id = .IntroCutscene },
    .{ .name = .fromSlice("TitleScreen"), .id = .TitleScreen },

    .{ .name = .fromSlice("Bloop"), .id = .Bloop },
    .{ .name = .fromSlice("Crack"), .id = .Crack },
    .{ .name = .fromSlice("Drop"), .id = .Drop },
    .{ .name = .fromSlice("Glide"), .id = .Glide },
    .{ .name = .fromSlice("Puhp"), .id = .Puhp },

    .{ .name = .fromSlice("Variant"), .id = .Variant },
    .{ .name = .fromSlice("ChannelIndex"), .id = .ChannelIndex },
};

pub fn tagNameFromID(tag_id: AssetTagId) String {
    return .fromSlice(@tagName(tag_id));
}

pub fn tagIdFromName(name: String) AssetTagId {
    var result: AssetTagId = .None;
    var name_index: u32 = 0;
    // TODO: Refactor this to use comptime instead of the `name_tags` array.
    while (name_index < name_tags.len) : (name_index += 1) {
        if (shared.stringBuffersEqualLowercase(name, name_tags[name_index].name)) {
            result = name_tags[name_index].id;
            break;
        }
    }
    return result;
}

pub fn alignPointNameFromType(align_type: HHAAlignPointType) String {
    return .fromSlice(@tagName(align_type));
}

pub fn alignPointTypeFromName(name: String) HHAAlignPointType {
    var result: HHAAlignPointType = .None;
    var type_index: u32 = 0;
    const type_count: u32 = @typeInfo(HHAAlignPointType).@"enum".fields.len - 1;
    while (type_index < type_count) : (type_index += 1) {
        const align_type: HHAAlignPointType = @enumFromInt(type_index);
        if (shared.stringBuffersEqualLowercase(name, alignPointNameFromType(align_type))) {
            result = align_type;
            break;
        }
    }
    return result;
}

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
