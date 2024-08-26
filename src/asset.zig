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

    Head,
    Cape,
    Torso,

    pub fn toInt(self: AssetTypeId) u32 {
        return @intFromEnum(self);
    }
};

const ASSET_TYPE_ID_COUNT = @typeInfo(AssetTypeId).Enum.fields.len;

const AssetType = struct {
    first_asset_index: u32,
    one_past_last_asset_index: u32,
};

pub const AssetTagId = enum(u32) {
    Smoothness,
    Flatness,
    FacingDirection, // Angles in radians off of due right.

    pub fn toInt(self: AssetTagId) u32 {
        return @intFromEnum(self);
    }
};

const AssetTag = struct {
    id: u32,
    value: f32,
};

const Asset = struct {
    first_tag_index: u32,
    one_past_last_tag_index: u32,
    slot_id: u32,
};

pub const AssetVector = struct {
    e: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{0} ** ASSET_TYPE_ID_COUNT,
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

const AssetSlotType = enum {
    bitmap,
    sound,
};

const AssetSlot = struct {
    state: AssetState = .Unloaded,
    data: union(AssetSlotType) {
        bitmap: ?*LoadedBitmap,
        sound: ?*LoadedSound,
    }
};

pub const BitmapId = struct {
    value: u32,
};

const AssetBitmapInfo = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: Vector2 = Vector2.zero(),
};

pub const SoundId = struct {
    value: u32,
};

const AssetSoundInfo = struct {
    file_name: [*:0]const u8 = undefined,
};

pub const Assets = struct {
    transient_state: *TransientState,
    arena: MemoryArena,

    bitmap_count: u32,
    bitmaps: [*]AssetSlot,
    bitmap_infos: [*]AssetBitmapInfo,

    sound_count: u32,
    sounds: [*]AssetSlot,
    sound_infos: [*]AssetSoundInfo,

    asset_count: u32,
    assets: [*]Asset,

    tag_count: u32,
    tags: [*]AssetTag,
    tag_range: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{1000000} ** ASSET_TYPE_ID_COUNT,

    debug_used_bitmap_count: u32,
    debug_used_asset_count: u32,
    debug_used_tag_count: u32,
    debug_asset_type: ?*AssetType,
    debug_asset: ?*Asset,

    asset_types: [ASSET_TYPE_ID_COUNT]AssetType = [1]AssetType{AssetType{}} ** ASSET_TYPE_ID_COUNT,

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

        self.debug_asset_type = &self.asset_types[type_id.toInt()];
        self.debug_asset_type.?.first_asset_index = self.debug_used_asset_count;
        self.debug_asset_type.?.one_past_last_asset_index = self.debug_asset_type.?.first_asset_index;
    }

    fn addBitmapAsset(self: *Assets, file_name: [*:0]const u8, alignment_percentage: ?Vector2) void {
        std.debug.assert(self.debug_asset_type != null);

        if (self.debug_asset_type) |asset_type| {
            std.debug.assert(asset_type.one_past_last_asset_index < ASSET_TYPE_ID_COUNT);

            const asset: *Asset = &self.assets[asset_type.one_past_last_asset_index];
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            asset.first_tag_index = self.debug_used_tag_count;
            asset.one_past_last_tag_index = self.debug_used_tag_count;
            asset.slot_id = self.debugAddBitmapInfo(file_name, alignment_percentage orelse Vector2.splat(0.5)).value;

            self.debug_asset = asset;
        }
    }

    fn addTag(self: *Assets, tag_id: AssetTagId, value: f32) void {
        if (self.debug_asset) |asset| {
            asset.one_past_last_tag_index += 1;
            const tag: *AssetTag = &self.tags[self.debug_used_tag_count];
            self.debug_used_tag_count += 1;

            tag.id = tag_id.toInt();
            tag.value = value;
        }
    }

    fn endAssetType(self: *Assets) void {
        if (self.debug_asset_type) |asset_type| {
            self.debug_used_asset_count = asset_type.one_past_last_asset_index;
            self.debug_asset_type = null;
            self.debug_asset = null;
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

        result.tag_count = 1024 * ASSET_TYPE_ID_COUNT;
        result.tags = result.arena.pushArray(result.tag_count, AssetTag);

        result.asset_count = result.bitmap_count + result.sound_count;
        result.assets = result.arena.pushArray(result.asset_count, Asset);
        result.tag_range[AssetTagId.FacingDirection.toInt()] = shared.TAU32;

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

        const angle_right: f32 = 0;
        const angle_back: f32 = 0.25 * shared.TAU32;
        const angle_left: f32 = 0.5 * shared.TAU32;
        const angle_front: f32 = 0.75 * shared.TAU32;
        const hero_align = Vector2.new(0.5, 0.156682029);

        result.beginAssetType(.Head);
        result.addBitmapAsset("test/test_hero_right_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_right);
        result.addBitmapAsset("test/test_hero_back_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_back);
        result.addBitmapAsset("test/test_hero_left_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_left);
        result.addBitmapAsset("test/test_hero_front_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_front);
        result.endAssetType();

        result.beginAssetType(.Cape);
        result.addBitmapAsset("test/test_hero_right_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_right);
        result.addBitmapAsset("test/test_hero_back_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_back);
        result.addBitmapAsset("test/test_hero_left_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_left);
        result.addBitmapAsset("test/test_hero_front_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_front);
        result.endAssetType();

        result.beginAssetType(.Torso);
        result.addBitmapAsset("test/test_hero_right_torso.bmp", hero_align);
        result.addTag(.FacingDirection, angle_right);
        result.addBitmapAsset("test/test_hero_back_torso.bmp", hero_align);
        result.addTag(.FacingDirection, angle_back);
        result.addBitmapAsset("test/test_hero_left_torso.bmp", hero_align);
        result.addTag(.FacingDirection, angle_left);
        result.addBitmapAsset("test/test_hero_front_torso.bmp", hero_align);
        result.addTag(.FacingDirection, angle_front);
        result.endAssetType();

        return result;
    }

    pub fn getBitmap(self: *Assets, id: BitmapId) ?*LoadedBitmap {
        var result: ?*LoadedBitmap = null;

        if (self.bitmaps[id.value].data.bitmap) |bitmap| {
            result = bitmap;
        }

        return result;
    }

    pub fn getFirstBitmapId(self: *Assets, type_id: AssetTypeId) ?BitmapId {
        var result: ?BitmapId = null;
        const asset_type: *AssetType = &self.asset_types[type_id.toInt()];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            const asset = self.assets[asset_type.first_asset_index];
            result = BitmapId{ .value = asset.slot_id };
        }

        return result;
    }

    pub fn getRandomAsset(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?BitmapId {
        var result: ?BitmapId = null;
        const asset_type: *AssetType = &self.asset_types[type_id.toInt()];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            const count: u32 = asset_type.one_past_last_asset_index - asset_type.first_asset_index;
            const choice = series.randomChoice(count);
            const asset = self.assets[asset_type.first_asset_index + choice];
            result = BitmapId{ .value = asset.slot_id };
        }

        return result;
    }

    pub fn getBestMatchAsset(
        self: *Assets,
        type_id: AssetTypeId,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?BitmapId {
        var result: ?BitmapId = null;
        var best_diff: f32 = std.math.floatMax(f32);
        const asset_type: *AssetType = &self.asset_types[type_id.toInt()];

        var asset_index: u32 = asset_type.first_asset_index;
        while (asset_index < asset_type.one_past_last_asset_index) : (asset_index += 1) {
            const asset = self.assets[asset_index];

            var total_weighted_diff: f32 = 0;
            var tag_index: u32 = asset.first_tag_index;
            while (tag_index < asset.one_past_last_tag_index) : (tag_index += 1) {
                const tag: *AssetTag = &self.tags[tag_index];

                const a: f32 = match_vector.e[tag.id];
                const b: f32 = tag.value;
                const d0 = intrinsics.absoluteValue(a - b);
                const d1 = intrinsics.absoluteValue((a - (self.tag_range[tag.id] * intrinsics.signOfF32(a))) - b);
                const difference = @min(d0, d1);

                const weighted = weight_vector.e[tag.id] * intrinsics.absoluteValue(difference);
                total_weighted_diff += weighted;
            }

            if (best_diff > total_weighted_diff) {
                best_diff = total_weighted_diff;
                result = BitmapId{ .value = asset.slot_id };
            }
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

fn doLoadBitmapWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    const work: *LoadBitmapWork = @ptrCast(@alignCast(data));
    const info = work.assets.bitmap_infos[work.id.value];

    work.bitmap.* = debugLoadBMP(info.file_name, info.alignment_percentage);
    work.assets.bitmaps[work.id.value].data.bitmap = work.bitmap;
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

            shared.addQueueEntry(assets.transient_state.low_priority_queue, doLoadBitmapWork, work);
        } else {
            @atomicStore(AssetState, &assets.bitmaps[id.value].state, .Unloaded, .release);
        }
    }
}

pub const LoadedSound = extern struct {
    sample_count: i32,
    memory: ?[*]void,
};

const LoadSoundWork = struct {
    assets: *Assets,
    id: BitmapId,
    task: *shared.TaskWithMemory,
    sound: *LoadedSound,

    final_state: AssetState,
};

fn doLoadSoundWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    const work: *LoadSoundWork = @ptrCast(@alignCast(data));
    const info = work.assets.sound_infos[work.id.value];

    work.sound.* = debugLoadWAV(info.file_name);
    work.assets.sounds[work.id.value].data.sound = work.sound;
    work.assets.sounds[work.id.value].state = work.final_state;

    handmade.endTaskWithMemory(work.task);
}
pub fn loadSound(
    assets: *Assets,
    id: SoundId,
) void {
    if (id.value != 0 and @cmpxchgStrong(
        AssetState,
        &assets.sounds[id.value].state,
        .Unloaded,
        .Queued,
        .seq_cst,
        .seq_cst,
    ) == null) {
        if (handmade.beginTaskWithMemory(assets.transient_state)) |task| {
            var work: *LoadSoundWork = task.arena.pushStruct(LoadSoundWork);

            work.assets = assets;
            work.id = id;
            work.task = task;
            work.sound = assets.arena.pushStruct(LoadedSound);
            work.final_state = .Loaded;

            shared.addQueueEntry(assets.transient_state.low_priority_queue, doLoadSoundWork, work);
        } else {
            @atomicStore(AssetState, &assets.bitmaps[id.value].state, .Unloaded, .release);
        }
    }
}

const BitmapHeader = packed struct {
    file_type: u16,
    file_size: u32,
    reserved1: u16,
    reserved2: u16,
    bitmap_offset: u32,
    size: u32,
    width: i32,
    height: i32,
    planes: u16,
    bits_per_pxel: u16,
    compression: u32,
    size_of_bitmap: u32,
    horz_resolution: i32,
    vert_resolution: i32,
    colors_used: u32,
    colors_important: u32,
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
};

fn debugLoadBMP(
    file_name: [*:0]const u8,
    alignment_percentage: ?Vector2,
) LoadedBitmap {
    var result: LoadedBitmap = undefined;
    const read_result = shared.debugReadEntireFile(file_name);

    if (read_result.content_size > 0) {
        const header = @as(*BitmapHeader, @ptrCast(@alignCast(read_result.contents)));

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

const WaveHeader = packed struct {
    riff_id: u32,
    size: u32,
    wave_id: u32,
};

fn riffCode(a: u8, b: u8, c: u8, d: u8) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, c << 16) | @as(u32, d << 24);
}

const WaveChunkIds = enum(u32) {
    ChunkID_fmt = riffCode('f', 'm', 't', ' '),
    ChunkID_RIFF = riffCode('R', 'I', 'F', 'F'),
    ChunkID_WAVE = riffCode('W', 'A', 'V', 'E'),
};

const WaveChunk = packed struct {
    id: u32,
    size: u32,
};

const WaveFmt = packed struct {
    w_format_tag: u16,
    channels: u16,
    n_samples_per_second: u32,
    n_avg_bytes_per_second: u32,
    n_block_align: u32,
    bits_per_sample: u16,
    cb_size: u16,
    w_valid_width_per_sample: u16,
    dw_channel_mask: u32,
    sub_format: [16]u8,
};

fn debugLoadWAV(file_name: [*:0]const u8) LoadedSound {
    var result: LoadedSound = undefined;
    const read_result = shared.debugReadEntireFile(file_name);

    if (read_result.content_size > 0) {
        const header = @as(*WaveHeader, @ptrCast(@alignCast(read_result.contents)));

        std.debug.assert(header.riff_id == WaveChunkIds.ChunkID_RIFF);
        std.debug.assert(header.wave_id == WaveChunkIds.ChunkID_WAVE);

        result.memory = undefined;
    }

    return result;
}
