pub const HHA_MAGIC_VALUE = hhaCode('h', 'h', 'a', 'f');
pub const HHA_VERSION = 0;

pub const HHAHeader = extern struct {
    magic_value: u32 = HHA_MAGIC_VALUE,
    version: u32 = HHA_VERSION,

    tag_count: u32,
    asset_type_count: u32,
    asset_count: u32,

    tags: u64 = undefined,        // [tag_count]HHATag
    asset_types: u64 = undefined, // [asset_type_count]HHAAssetType
    assets: u64 = undefined,      // [asset_count]HHAAsset
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
    data_offset: u64,
    first_tag_index: u32,
    one_past_last_tag_index: u32,

    info: extern union {
        bitmap: HHABitmap,
        sound: HHASound,
    }
};

pub const HHABitmap = extern struct {
    dim: [2]u32,
    alignment_percentage: [2]f32,
};

pub const HHASound = extern struct {
    sample_count: u32,
    channel_count: u32,
    next_id_to_play: SoundId,
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
