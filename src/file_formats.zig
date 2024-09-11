pub const HHAHeader = packed struct {
    magic_value: u32 = hhaCode('h', 'h', 'a', 'f'),
    version: u32 = 0,

    tag_count: u32,
    asset_type_count: u32,
    asset_count: u32,

    tags: u64 = undefined,        // [tag_count]HHATag
    asset_types: u64 = undefined, // [asset_type_count]HHAAssetType
    assets: u64 = undefined,      // [asset_count]HHAAsset
};

pub const HHATag = packed struct {
    id: u32,
    value: f32,
};

pub const HHAAssetType = packed struct {
    type_id: u32 = 0,
    first_asset_index: u32 = 0,
    one_past_last_asset_index: u32 = 0,
};

pub const HHAAsset = packed struct {
    data_offset: u64,
    first_tag_index: u32,
    one_past_last_tag_index: u32,

    info: packed union {
        bitmap: HHABitmap,
        sound: HHASound,
    }
};

pub const HHABitmap = packed struct {
    dim: [2]u32,
    alignment_percentage: [2]f32,
};

pub const HHASound = packed struct {
    first_sample_index: u32,
    sample_count: u32,
    next_id_to_play: ?u32,
};

fn hhaCode(a: u32, b: u32, c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, c << 16) | @as(u32, d << 24);
}
