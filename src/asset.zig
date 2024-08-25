const shared = @import("shared.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const render = @import("render.zig");
const handmade = @import("handmade.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const LoadedBitmap = render.LoadedBitmap;
const TransientState = shared.TransientState;
const MemoryArena = shared.MemoryArena;
const Platform = shared.Platform;

pub const AssetTypeId = enum(u32) {
    None,
    Shadow,
    Tree,
    Sword,
    Rock,

    Grass,
    Tuft,
    Stone,

    pub fn toInt(self: AssetTypeId) u32 {
        return @intFromEnum(self);
    }
};

const ASSET_TYPE_ID_COUNT = @typeInfo(AssetTypeId).Enum.fields.len;

const AssetType = struct {
    first_asset_index: u32,
    one_past_last_asset_index: u32,
};

const AssetTagId = enum(u8) {
    Smoothness,
    Flatness,
};

const AssetTag = struct {
    id: u32,
    value: f32,
};

const Asset = struct {
    first_tag_index: u32,
    one_past_last_index: u32,
    slot_id: u32,
};

const AssetState = enum(u8) {
    Unloaded,
    Queued,
    Loaded,
    Locked,
};

const AssetGroup = struct {
    first_tag_index: u32,
    one_past_last_index: u32,
};

const AssetSlot = struct {
    state: AssetState = .Unloaded,
    bitmap: ?*LoadedBitmap = null,
};

pub const BitmapId = struct {
    value: u32,
};

const AssetBitmapInfo = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: Vector2 = Vector2.zero(),
};

pub const HeroBitmaps = struct {
    head: LoadedBitmap,
    torso: LoadedBitmap,
    cape: LoadedBitmap,
};

pub const SoundId = struct {
    value: u32,
};

pub const Assets = struct {
    transient_state: *TransientState,
    arena: MemoryArena,

    bitmap_count: u32,
    bitmaps: [*]AssetSlot,
    bitmap_infos: [*]AssetBitmapInfo,

    sound_count: u32,
    sounds: [*]AssetSlot,

    asset_count: u32,
    assets: [*]Asset,

    tag_count: u32,
    tags: [*]AssetTag,

    debug_used_bitmap_count: u32,
    debug_used_asset_count: u32,
    debug_asset_type: ?*AssetType,

    asset_types: [ASSET_TYPE_ID_COUNT]AssetType = [1]AssetType{AssetType{}} ** ASSET_TYPE_ID_COUNT,

    // Structured assets.
    hero_bitmaps: [4]HeroBitmaps,

    fn debugAddBitmapInfo(self: *Assets, file_name: [*:0]const u8, alignment_percentage: Vector2) BitmapId {
        std.debug.assert(self.debug_used_bitmap_count < self.bitmap_count);

        const bitmap_id = BitmapId{ .value = self.debug_used_bitmap_count };
        self.debug_used_bitmap_count += 1;

        var info = &self.bitmap_infos[bitmap_id.value];
        info.alignment_percentage = alignment_percentage;
        info.file_name = file_name;

        return bitmap_id;
    }

    fn beginAssetType(self: *Assets, type_id: AssetTypeId) void {
        std.debug.assert(self.debug_asset_type == null);

        self.debug_asset_type = &self.asset_types[@intFromEnum(type_id)];
        self.debug_asset_type.?.first_asset_index = self.debug_used_asset_count;
        self.debug_asset_type.?.one_past_last_asset_index = self.debug_asset_type.?.first_asset_index;
    }

    fn addBitmapAsset(self: *Assets, file_name: [*:0]const u8, alignment_percentage: ?Vector2) void {
        std.debug.assert(self.debug_asset_type != null);

        if (self.debug_asset_type) |asset_type| {
            const asset: *Asset = &self.assets[asset_type.one_past_last_asset_index];
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            asset.first_tag_index = 0;
            asset.one_past_last_index = 0;
            asset.slot_id = self.debugAddBitmapInfo(file_name, alignment_percentage orelse Vector2.splat(0.5)).value;
        }
    }

    fn endAssetType(self: *Assets) void {
        if (self.debug_asset_type) |asset_type| {
            self.debug_used_asset_count = asset_type.one_past_last_asset_index;
            self.debug_asset_type = null;
        }
    }

    pub fn allocate(
        arena: *MemoryArena,
        memory_size: shared.MemoryIndex,
        transient_state: *shared.TransientState,
    ) *Assets {
        var result = arena.pushStruct(Assets);

        result.transient_state = transient_state;
        result.arena = undefined;

        arena.makeSubArena(&result.arena, memory_size, null);

        // Load game assets.
        result.bitmap_count = 256 * ASSET_TYPE_ID_COUNT;
        result.bitmaps = result.arena.pushArray(result.bitmap_count, AssetSlot);
        result.bitmap_infos = result.arena.pushArray(result.bitmap_count, AssetBitmapInfo);

        result.sound_count = 1;
        result.sounds = result.arena.pushArray(result.sound_count, AssetSlot);

        result.tag_count = 0;
        result.tags = result.arena.pushArray(result.tag_count, AssetTag);

        result.asset_count = result.bitmap_count + result.sound_count;
        result.assets = result.arena.pushArray(result.asset_count, Asset);

        result.debug_used_bitmap_count = 1;
        result.debug_used_asset_count = 1;

        result.beginAssetType(.Shadow);
        result.addBitmapAsset("test/test_hero_shadow.bmp", Vector2.new(0.5, 0.15668203));
        result.endAssetType();

        result.beginAssetType(.Tree);
        result.addBitmapAsset("test2/tree00.bmp", Vector2.new(0.49382716, 0.29565218));
        result.endAssetType();

        result.beginAssetType(.Sword);
        result.addBitmapAsset("test2/rock03.bmp", Vector2.new(0.5, 0.65625));
        result.endAssetType();

        result.hero_bitmaps = .{
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_right_head.bmp", null),
                .torso = debugLoadBMP("test/test_hero_right_torso.bmp", null),
                .cape = debugLoadBMP("test/test_hero_right_cape.bmp", null),
            },
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_back_head.bmp", null),
                .torso = debugLoadBMP("test/test_hero_back_torso.bmp", null),
                .cape = debugLoadBMP("test/test_hero_back_cape.bmp", null),
            },
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_left_head.bmp", null),
                .torso = debugLoadBMP("test/test_hero_left_torso.bmp", null),
                .cape = debugLoadBMP("test/test_hero_left_cape.bmp", null),
            },
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_front_head.bmp", null),
                .torso = debugLoadBMP("test/test_hero_front_torso.bmp", null),
                .cape = debugLoadBMP("test/test_hero_front_cape.bmp", null),
            },
        };

        result.beginAssetType(.Grass);
        result.addBitmapAsset("test2/grass00.bmp", null);
        result.addBitmapAsset("test2/grass01.bmp", null);
        result.endAssetType();

        result.beginAssetType(.Stone);
        result.addBitmapAsset("test2/ground00.bmp", null);
        result.addBitmapAsset("test2/ground01.bmp", null);
        result.addBitmapAsset("test2/ground02.bmp", null);
        result.addBitmapAsset("test2/ground03.bmp", null);
        result.endAssetType();

        result.beginAssetType(.Tuft);
        result.addBitmapAsset("test2/tuft00.bmp", null);
        result.addBitmapAsset("test2/tuft01.bmp", null);
        result.addBitmapAsset("test2/tuft02.bmp", null);
        result.endAssetType();

        for (&result.hero_bitmaps) |*bitmaps| {
            setTopDownAligned(bitmaps, Vector2.new(72, 182));
        }


        return result;
    }

    pub fn getBitmap(self: *Assets, id: BitmapId) ?*LoadedBitmap {
        return self.bitmaps[id.value].bitmap;
    }

    // TODO: This should probably return an optional.
    pub fn getFirstBitmapId(self: *Assets, type_id: AssetTypeId) ?BitmapId {
        var result: ?BitmapId = null;
        const asset_type: *AssetType = &self.asset_types[@intFromEnum(type_id)];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            const asset = self.assets[asset_type.first_asset_index];
            result = BitmapId{ .value = asset.slot_id };
        }

        return result;
    }

    pub fn getRandomAsset(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?BitmapId {
        var result: ?BitmapId = null;
        const asset_type: *AssetType = &self.asset_types[@intFromEnum(type_id)];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            const count: u32 = asset_type.one_past_last_asset_index - asset_type.first_asset_index;
            const choice = series.randomChoice(count);
            const asset = self.assets[asset_type.first_asset_index + choice];
            result = BitmapId{ .value = asset.slot_id };
        }

        return result;
    }
};

const LoadBitmapWork = struct {
    assets: *Assets,
    id: BitmapId,
    task: *shared.TaskWithMemory,
    bitmap: *LoadedBitmap,

    final_state: AssetState,
};

fn doLoadAssetWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    const work: *LoadBitmapWork = @ptrCast(@alignCast(data));
    const info = work.assets.bitmap_infos[work.id.value];

    work.bitmap.* = debugLoadBMP(info.file_name, info.alignment_percentage);
    work.assets.bitmaps[work.id.value].bitmap = work.bitmap;
    work.assets.bitmaps[work.id.value].state = work.final_state;

    handmade.endTaskWithMemory(work.task);
}

pub fn loadBitmap(
    assets: *Assets,
    id: BitmapId,
) void {
    if (id.value != 0 and @cmpxchgStrong(
        AssetState,
        &assets.bitmaps[id.value].state,
        .Unloaded,
        .Queued,
        .seq_cst,
        .seq_cst,
    ) == null) {
        if (handmade.beginTaskWithMemory(assets.transient_state)) |task| {
            var work: *LoadBitmapWork = task.arena.pushStruct(LoadBitmapWork);

            work.assets = assets;
            work.id = id;
            work.task = task;
            work.bitmap = assets.arena.pushStruct(LoadedBitmap);
            work.final_state = .Loaded;

            shared.addQueueEntry(assets.transient_state.low_priority_queue, doLoadAssetWork, work);
        } else {
            @atomicStore(AssetState, &assets.bitmaps[id.value].state, .Unloaded, .release);
        }
    }
}

pub fn loadSound(
    assets: *Assets,
    id: SoundId,
) void {
    _ = assets;
    _ = id;
}

fn topDownAligned(bitmap: *LoadedBitmap, alignment: Vector2) Vector2 {
    const flipped_y = @as(f32, @floatFromInt((bitmap.height - 1))) - alignment.y();
    return Vector2.new(
        math.safeRatio0(alignment.x(), @floatFromInt(bitmap.width)),
        math.safeRatio0(flipped_y, @floatFromInt(bitmap.height)),
    );
}

fn setTopDownAligned(bitmaps: *HeroBitmaps, in_alignment: Vector2) void {
    const alignment = topDownAligned(&bitmaps.head, in_alignment);

    bitmaps.head.alignment_percentage = alignment;
    bitmaps.cape.alignment_percentage = alignment;
    bitmaps.torso.alignment_percentage = alignment;
}

fn debugLoadBMP(
    file_name: [*:0]const u8,
    alignment_percentage: ?Vector2,
) LoadedBitmap {
    var result: LoadedBitmap = undefined;
    const read_result = shared.debugReadEntireFile(file_name);

    if (read_result.content_size > 0) {
        const header = @as(*shared.BitmapHeader, @ptrCast(@alignCast(read_result.contents)));

        std.debug.assert(header.height >= 0);
        std.debug.assert(header.compression == 3);

        result.memory = @as([*]void, @ptrCast(read_result.contents)) + header.bitmap_offset;
        result.width = header.width;
        result.height = header.height;
        result.alignment_percentage = alignment_percentage orelse Vector2.splat(0.5);
        result.width_over_height = math.safeRatio0(@floatFromInt(result.width), @floatFromInt(result.height));

        const alpha_mask = ~(header.red_mask | header.green_mask | header.blue_mask);
        const alpha_scan = intrinsics.findLeastSignificantSetBit(alpha_mask);
        const red_scan = intrinsics.findLeastSignificantSetBit(header.red_mask);
        const green_scan = intrinsics.findLeastSignificantSetBit(header.green_mask);
        const blue_scan = intrinsics.findLeastSignificantSetBit(header.blue_mask);

        std.debug.assert(alpha_scan.found);
        std.debug.assert(red_scan.found);
        std.debug.assert(green_scan.found);
        std.debug.assert(blue_scan.found);

        const red_shift_down = @as(u5, @intCast(red_scan.index));
        const green_shift_down = @as(u5, @intCast(green_scan.index));
        const blue_shift_down = @as(u5, @intCast(blue_scan.index));
        const alpha_shift_down = @as(u5, @intCast(alpha_scan.index));

        var source_dest: [*]align(@alignOf(u8)) u32 = @ptrCast(result.memory);
        var x: u32 = 0;
        while (x < header.width) : (x += 1) {
            var y: u32 = 0;
            while (y < header.height) : (y += 1) {
                const color = source_dest[0];
                var texel = Color.new(
                    @floatFromInt((color & header.red_mask) >> red_shift_down),
                    @floatFromInt((color & header.green_mask) >> green_shift_down),
                    @floatFromInt((color & header.blue_mask) >> blue_shift_down),
                    @floatFromInt((color & alpha_mask) >> alpha_shift_down),
                );
                texel = render.sRGB255ToLinear1(texel);

                _ = texel.setRGB(texel.rgb().scaledTo(texel.a()));

                texel = render.linear1ToSRGB255(texel);

                source_dest[0] = texel.packColor1();

                source_dest += 1;
            }
        }
    }

    result.pitch = result.width * shared.BITMAP_BYTES_PER_PIXEL;

    if (false) {
        result.pitch = -result.width * shared.BITMAP_BYTES_PER_PIXEL;
        const offset: usize = @intCast(-result.pitch * (result.height - 1));
        result.memory = @ptrCast(@as([*]u8, @ptrCast(result.memory)) + offset);
    }

    return result;
}

fn pickBestAsset(
    info_count: i32,
    infos: [*]AssetBitmapInfo,
    tags: [*]AssetTag,
    match_vector: [*]f32,
    weight_vector: [*]f32,
) i32 {
    var best_diff: f32 = std.math.maxFloat(f32);
    var best_index: i32 = 0;

    var info_index: u32 = 0;
    while (info_index < info_count) : (info_index += 1) {
        const info = infos + info_index;

        var total_weighted_diff: f32 = 0;
        var tag_index: u32 = info.first_tag_index;
        while (tag_index < info.one_past_last_tag_index) : (tag_index += 1) {
            const tag = tags + tag_index;
            const difference = match_vector[tag.id] - tag.value;
            const weighted = weight_vector[tag.id] * intrinsics.absoluteValue(difference);
            total_weighted_diff += weighted;
        }

        if (best_diff > total_weighted_diff) {
            best_diff = total_weighted_diff;
            best_index = info_index;
        }
    }

    return best_index;
}

