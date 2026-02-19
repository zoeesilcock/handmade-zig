const file_formats = @import("file_formats");

pub const HHA_MAGIC_VALUE = file_formats.hhaCode('h', 'h', 'a', 'f');
pub const HHA_VERSION = 0;
pub const ASSET_TYPE_ID_COUNT = @typeInfo(AssetTypeIdV0).@"enum".fields.len;

// Types.
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;
const HHAFont = file_formats.HHAFont;

pub const AssetTypeIdV0 = enum(u32) {
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

    Hand,

    pub fn toInt(self: AssetTypeIdV0) u32 {
        return @intFromEnum(self);
    }
};

pub const HHAAssetTypeV0 = extern struct {
    type_id: u32 align(1) = 0,
    first_asset_index: u32 align(1) = 0,
    one_past_last_asset_index: u32 align(1) = 0,
};

pub const HHAHeaderV0 = extern struct {
    magic_value: u32 align(1) = HHA_MAGIC_VALUE,
    version: u32 align(1) = HHA_VERSION,

    tag_count: u32 align(1),
    asset_type_count: u32 align(1),
    asset_count: u32 align(1),

    tags: u64 align(1) = undefined, // [tag_count]HHATag
    asset_types: u64 align(1) = undefined, // [asset_type_count]HHAAssetType
    assets: u64 align(1) = undefined, // [asset_count]HHAAsset

    // TODO: Right now we have a situation where we are no longer making contiguous asset type blocks - so it would be
    // better to switch to just having asset type IDs stored directly in the HHAAsset, because it's just burning space
    // and cycles to store it in the AssetTypes array.
};

pub const HHAAssetV0 = extern struct {
    data_offset: u64 align(1) = 0,
    first_tag_index: u32 align(1) = 0,
    one_past_last_tag_index: u32 align(1) = 0,
    info: extern union {
        bitmap: HHABitmap,
        sound: HHASound,
        font: HHAFont,
    } = undefined,
};
