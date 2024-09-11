const std = @import("std");
const shared = @import("shared");
const file_formats = @import("file_formats");

// Types.
const AssetTypeId = shared.AssetTypeId;
const AssetTagId = shared.AssetTagId;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAssetType = file_formats.HHAAssetType;
const HHAAsset = file_formats.HHAAsset;
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;

const ASSET_TYPE_ID_COUNT = shared.ASSET_TYPE_ID_COUNT;

var opt_out: ?std.fs.File = null;

const Asset = struct {
    data_offset: u64,
    first_tag_index: u32,
    one_past_last_tag_index: u32,
    info: union {
        bitmap: AssetBitmapInfo,
        sound: AssetSoundInfo,
    }
};

const BitmapAsset = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

pub const BitmapId = struct {
    value: u32,

    pub fn isValid(self: *const BitmapId) bool {
        return self.value != 0;
    }
};

const AssetBitmapInfo = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

pub const SoundId = struct {
    value: u32,

    pub fn isValid(self: *const SoundId) bool {
        return self.value != 0;
    }
};

const AssetSoundInfo = struct {
    file_name: [*:0]const u8,
    first_sample_index: u32,
    sample_count: u32,
    next_id_to_play: ?SoundId,
};

const VERY_LARGE_NUMBER = 4096;

pub const Assets = struct {
    tag_count: u32 = 0,
    tags: [VERY_LARGE_NUMBER]HHATag = [1]HHATag{undefined} ** VERY_LARGE_NUMBER,

    asset_count: u32 = 0,
    assets: [VERY_LARGE_NUMBER]Asset = [1]Asset{undefined} ** VERY_LARGE_NUMBER,

    asset_type_count: u32 = 0,
    asset_types: [ASSET_TYPE_ID_COUNT]HHAAssetType = [1]HHAAssetType{HHAAssetType{}} ** ASSET_TYPE_ID_COUNT,

    debug_asset_type: ?*HHAAssetType = null,
    debug_asset: ?*Asset = null,

    fn beginAssetType(self: *Assets, type_id: AssetTypeId) void {
        std.debug.assert(self.debug_asset_type == null);

        self.debug_asset_type = &self.asset_types[type_id.toInt()];
        self.debug_asset_type.?.type_id = @intFromEnum(type_id);
        self.debug_asset_type.?.first_asset_index = self.asset_count;
        self.debug_asset_type.?.one_past_last_asset_index = self.debug_asset_type.?.first_asset_index;
    }

    fn addBitmapAsset(self: *Assets, file_name: [*:0]const u8, alignment_percentage_x: ?f32, alignment_percentage_y: ?f32) ?BitmapId {
        std.debug.assert(self.debug_asset_type != null);

        var result: ?BitmapId = null;

        if (self.debug_asset_type) |asset_type| {
            std.debug.assert(asset_type.one_past_last_asset_index < self.assets.len);

            result = BitmapId{ .value = asset_type.one_past_last_asset_index };
            const asset: *Asset = &self.assets[result.?.value];
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            asset.first_tag_index = self.tag_count;
            asset.one_past_last_tag_index = self.tag_count;

            asset.info = .{
                .bitmap = AssetBitmapInfo{
                    .alignment_percentage = .{
                        alignment_percentage_x orelse 0.5,
                        alignment_percentage_y orelse 0.5,
                    },
                    .file_name = file_name,
                },
            };

            self.debug_asset = asset;
        }

        return result;
    }

    fn addSoundAsset(self: *Assets, file_name: [*:0]const u8) ?SoundId {
        return self.addSoundSectionAsset(file_name, 0, 0);
    }

    fn addSoundSectionAsset(self: *Assets, file_name: [*:0]const u8, first_sample_index: u32, sample_count: u32) ?SoundId {
        std.debug.assert(self.debug_asset_type != null);

        var result: ?SoundId = null;

        if (self.debug_asset_type) |asset_type| {
            std.debug.assert(asset_type.one_past_last_asset_index < self.assets.len);

            result = SoundId { .value = asset_type.one_past_last_asset_index };
            const asset: *Asset = &self.assets[result.?.value];
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            asset.first_tag_index = self.tag_count;
            asset.one_past_last_tag_index = self.tag_count;

            asset.info = .{
                .sound = AssetSoundInfo{
                    .file_name = file_name,
                    .first_sample_index = first_sample_index,
                    .sample_count = sample_count,
                    .next_id_to_play = null,
                },
            };

            self.debug_asset = asset;
        }

        return result;
    }

    fn addTag(self: *Assets, tag_id: AssetTagId, value: f32) void {
        if (self.debug_asset) |asset| {
            asset.one_past_last_tag_index += 1;
            const tag: *HHATag = &self.tags[self.tag_count];
            self.tag_count += 1;

            tag.id = tag_id.toInt();
            tag.value = value;
        }
    }

    fn endAssetType(self: *Assets) void {
        if (self.debug_asset_type) |_| {
            self.debug_asset_type = null;
            self.debug_asset = null;
        }
    }
};

pub fn main() anyerror!void {
    var assets = Assets{
        .asset_count = 1,
        .tag_count = 1,
        .debug_asset_type = null,
        .debug_asset = null,
    };
    var result = &assets;

    result.beginAssetType(.Shadow);
    _ = result.addBitmapAsset("test/test_hero_shadow.bmp", 0.5, 0.15668203);
    result.endAssetType();

    result.beginAssetType(.Tree);
    _ = result.addBitmapAsset("test2/tree00.bmp", 0.49382716, 0.29565218);
    result.endAssetType();

    result.beginAssetType(.Sword);
    _ = result.addBitmapAsset("test2/rock03.bmp", 0.5, 0.65625);
    result.endAssetType();

    result.beginAssetType(.Grass);
    _ = result.addBitmapAsset("test2/grass00.bmp", null, null);
    _ = result.addBitmapAsset("test2/grass01.bmp", null, null);
    result.endAssetType();

    result.beginAssetType(.Stone);
    _ = result.addBitmapAsset("test2/ground00.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground01.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground02.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground03.bmp", null, null);
    result.endAssetType();

    result.beginAssetType(.Tuft);
    _ = result.addBitmapAsset("test2/tuft00.bmp", null, null);
    _ = result.addBitmapAsset("test2/tuft01.bmp", null, null);
    _ = result.addBitmapAsset("test2/tuft02.bmp", null, null);
    result.endAssetType();

    const angle_right: f32 = 0;
    const angle_back: f32 = 0.25 * shared.TAU32;
    const angle_left: f32 = 0.5 * shared.TAU32;
    const angle_front: f32 = 0.75 * shared.TAU32;
    const hero_align_x = 0.5;
    const hero_align_y = 0.156682029;

    result.beginAssetType(.Head);
    _ = result.addBitmapAsset("test/test_hero_right_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Cape);
    _ = result.addBitmapAsset("test/test_hero_right_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Torso);
    _ = result.addBitmapAsset("test/test_hero_right_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Bloop);
    _ = result.addSoundAsset("test3/bloop_00.wav");
    _ = result.addSoundAsset("test3/bloop_01.wav");
    _ = result.addSoundAsset("test3/bloop_02.wav");
    _ = result.addSoundAsset("test3/bloop_03.wav");
    result.endAssetType();

    result.beginAssetType(.Crack);
    _ = result.addSoundAsset("test3/crack_00.wav");
    result.endAssetType();

    result.beginAssetType(.Drop);
    _ = result.addSoundAsset("test3/drop_00.wav");
    result.endAssetType();

    result.beginAssetType(.Glide);
    _ = result.addSoundAsset("test3/glide_00.wav");
    result.endAssetType();

    result.beginAssetType(.Music);
    const one_music_chunk = 2 * 48000;
    const total_music_sample_count = 7468095;
    var first_sample_index: u32 = 0;
    var last_music: ?SoundId = null;
    while (first_sample_index < total_music_sample_count) : (first_sample_index += one_music_chunk) {
        var sample_count = total_music_sample_count - first_sample_index;
        if (sample_count > one_music_chunk) {
            sample_count = one_music_chunk;
        }

        const this_music = result.addSoundSectionAsset("test3/music_test.wav", first_sample_index, sample_count);
        if (last_music) |last| {
            if (this_music) |this| {
                result.assets[last.value].info.sound.next_id_to_play = this;
            }
        }

        last_music = this_music;
    }
    result.endAssetType();

    result.beginAssetType(.Glide);
    _ = result.addSoundAsset("test3/puhp_00.wav");
    _ = result.addSoundAsset("test3/puhp_01.wav");
    result.endAssetType();

    const file_path = "test.hha";
    if (std.fs.cwd().openFile(file_path, .{ .mode = .write_only })) |file| {
        opt_out = file;
    } else |err| {
        std.debug.print("unable to open '{s}': {s}", .{ file_path, @errorName(err) });

        opt_out = std.fs.cwd().createFile(file_path, .{}) catch |create_err| {
            std.debug.print("unable to create '{s}': {s}", .{ file_path, @errorName(create_err) });
            std.process.exit(1);
        };
    }

    if (opt_out) |out| {
        defer out.close();

        var header = HHAHeader{
            .tag_count = result.tag_count,
            .asset_type_count = result.asset_count,
            .asset_count = result.asset_count,
        };

        const tag_array_size: u32 = header.tag_count * @sizeOf(HHATag);
        const asset_type_array_size: u32 = header.asset_type_count * @sizeOf(HHAAssetType);
        // const asset_array_size: u32 = header.asset_count * @sizeOf(HHAAsset);

        header.tags = @sizeOf(HHAHeader);
        header.asset_types = header.tags + tag_array_size;
        header.assets = header.asset_types + asset_type_array_size;

        var bytes_written: usize = 0;
        bytes_written += try out.write(std.mem.asBytes(&header));
        bytes_written += try out.write(std.mem.asBytes(&result.tags));
        bytes_written += try out.write(std.mem.asBytes(&result.asset_types));
        // bytes_written += try out.write(std.mem.asBytes(&result.assets));

        std.debug.print("Bytes written: {d}", .{ bytes_written });
    }
}
