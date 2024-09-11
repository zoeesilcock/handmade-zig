const std = @import("std");
const asset_type_id = @import("../src/asset_type_id.zig");

// Types.
const AssetTypeId = asset_type_id.AssetTypeId;

const ASSET_TYPE_ID_COUNT = asset_type_id.COUNT;

var opt_out: ?std.fs.File = null;

const Asset = struct {
    data_offset: u64,
    first_tag_index: u32,
    one_past_last_tag_index: u32,
};

const AssetTag = struct {
    id: u32,
    value: f32,
};

const AssetType = struct {
    first_asset_index: u32,
    one_past_last_asset_index: u32,
};

const BitmapAsset = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

const AssetBitmapInfo = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

const AssetSoundInfo = struct {
    file_name: [*:0]const u8,
    first_sample_index: u32,
    sample_count: u32,
    next_id_to_play: ?u32,
};

const VERY_LARGE_NUMBER = 4096;

var bitmap_count: u32 = 0;
var bitmap_infos: [VERY_LARGE_NUMBER]AssetBitmapInfo = undefined;

var sound_count: u32 = 0;
var sound_infos: [VERY_LARGE_NUMBER]AssetSoundInfo = undefined;

var asset_count: u32 = 0;
var assets: [VERY_LARGE_NUMBER]Asset = undefined;
var asset_types: [ASSET_TYPE_ID_COUNT]AssetType = [1]AssetType{AssetType{}} ** ASSET_TYPE_ID_COUNT;

var tag_count: u32 = 0;
var tags: [VERY_LARGE_NUMBER]AssetTag = undefined;
// var tag_range: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{1000000} ** ASSET_TYPE_ID_COUNT;

var debug_used_bitmap_count: u32 = 0;
var debug_used_sound_count: u32 = 0;
var debug_used_asset_count: u32 = 0;
var debug_used_tag_count: u32 = 0;
var debug_asset_type: ?*AssetType = null;
var debug_asset: ?*Asset = null;

fn beginAssetType(type_id: AssetTypeId) void {
    std.debug.assert(debug_asset_type == null);

    debug_asset_type = &asset_types[type_id.toInt()];
    debug_asset_type.?.first_asset_index = debug_used_asset_count;
    debug_asset_type.?.one_past_last_asset_index = debug_asset_type.?.first_asset_index;
}

fn addBitmapAsset(file_name: [*:0]const u8, alignment_percentage_x: ?f32, alignment_percentage_y: ?f32) void {
    std.debug.assert(debug_asset_type != null);

    if (debug_asset_type) |asset_type| {
        std.debug.assert(asset_type.one_past_last_asset_index < asset_count);

        const asset: *Asset = &assets[asset_type.one_past_last_asset_index];
        debug_asset_type.?.one_past_last_asset_index += 1;

        asset.first_tag_index = debug_used_tag_count;
        asset.one_past_last_tag_index = debug_used_tag_count;


        std.debug.assert(debug_used_bitmap_count < bitmap_count);

        const bitmap_id = debug_used_bitmap_count;
        debug_used_bitmap_count += 1;

        var info = &bitmap_infos[bitmap_id];
        info.alignment_percentage = .{
            alignment_percentage_x,
            alignment_percentage_y,
        };
        // info.file_name = arena.pushString(file_name);
        _ = file_name;


        asset.slot_id = bitmap_id.value;

        debug_asset = asset;
    }
}

fn addSoundAsset(file_name: [*:0]const u8) void {
    _ = addSoundSectionAsset(file_name, 0, 0);
}

fn addSoundSectionAsset(file_name: [*:0]const u8, first_sample_index: u32, sample_count: u32) ?*Asset {
    std.debug.assert(debug_asset_type != null);

    var result: ?*Asset = null;

    if (debug_asset_type) |asset_type| {
        std.debug.assert(asset_type.one_past_last_asset_index < asset_count);

        const asset: *Asset = &assets[asset_type.one_past_last_asset_index];
        debug_asset_type.?.one_past_last_asset_index += 1;

        asset.first_tag_index = debug_used_tag_count;
        asset.one_past_last_tag_index = debug_used_tag_count;


        std.debug.assert(debug_used_sound_count < sound_count);

        const sound_id = debug_used_sound_count;
        debug_used_sound_count += 1;

        var info = &sound_infos[sound_id];
        // info.file_name = arena.pushString(file_name);
        _ = file_name;
        info.first_sample_index = first_sample_index;
        info.sample_count = sample_count;
        info.next_id_to_play = null;


        asset.slot_id = sound_id.value;

        debug_asset = asset;
        result = asset;
    }

    return result;
}

pub fn main() anyerror!void {
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

        std.debug.print("Hello!", .{});
    }
}
