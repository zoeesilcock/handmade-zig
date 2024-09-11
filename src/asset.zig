const shared = @import("shared.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const render = @import("render.zig");
const handmade = @import("handmade.zig");
const intrinsics = @import("intrinsics.zig");
const asset_type_id = @import("asset_type_id.zig");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const TransientState = shared.TransientState;
const MemoryArena = shared.MemoryArena;
const Platform = shared.Platform;
const AssetTypeId = asset_type_id.AssetTypeId;

const ASSET_TYPE_ID_COUNT = asset_type_id.COUNT;

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
    info: union {
        bitmap: AssetBitmapInfo,
        sound: AssetSoundInfo,
    }
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
    },
};

pub const BitmapId = struct {
    value: u32,

    pub fn isValid(self: *const BitmapId) bool {
        return self.value != 0;
    }
};

const AssetBitmapInfo = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: Vector2 = Vector2.zero(),
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

pub const Assets = struct {
    transient_state: *TransientState,
    arena: MemoryArena,

    asset_count: u32,
    assets: [*]Asset,
    asset_types: [ASSET_TYPE_ID_COUNT]AssetType = [1]AssetType{AssetType{}} ** ASSET_TYPE_ID_COUNT,

    slots: [*]AssetSlot,

    tag_count: u32,
    tags: [*]AssetTag,
    tag_range: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{1000000} ** ASSET_TYPE_ID_COUNT,

    debug_used_bitmap_count: u32,
    debug_used_sound_count: u32,
    debug_used_asset_count: u32,
    debug_used_tag_count: u32,
    debug_asset_type: ?*AssetType,
    debug_asset: ?*Asset,

    fn beginAssetType(self: *Assets, type_id: AssetTypeId) void {
        std.debug.assert(self.debug_asset_type == null);

        self.debug_asset_type = &self.asset_types[type_id.toInt()];
        self.debug_asset_type.?.first_asset_index = self.debug_used_asset_count;
        self.debug_asset_type.?.one_past_last_asset_index = self.debug_asset_type.?.first_asset_index;
    }

    fn addBitmapAsset(self: *Assets, file_name: [*:0]const u8, alignment_percentage: ?Vector2) ?BitmapId {
        std.debug.assert(self.debug_asset_type != null);

        var result: ?BitmapId = null;

        if (self.debug_asset_type) |asset_type| {
            std.debug.assert(asset_type.one_past_last_asset_index < self.asset_count);

            result = BitmapId{ .value = asset_type.one_past_last_asset_index };
            const asset: *Asset = &self.assets[result.?.value];
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            asset.first_tag_index = self.debug_used_tag_count;
            asset.one_past_last_tag_index = self.debug_used_tag_count;

            asset.info = .{
                .bitmap = AssetBitmapInfo{
                    .alignment_percentage = alignment_percentage orelse Vector2.splat(0.5),
                    .file_name = self.arena.pushString(file_name),
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
            std.debug.assert(asset_type.one_past_last_asset_index < self.asset_count);

            result = SoundId { .value = asset_type.one_past_last_asset_index };
            const asset: *Asset = &self.assets[result.?.value];
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            asset.first_tag_index = self.debug_used_tag_count;
            asset.one_past_last_tag_index = self.debug_used_tag_count;

            asset.info = .{
                .sound = AssetSoundInfo{
                    .file_name = self.arena.pushString(file_name),
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

        result.tag_count = 1024 * ASSET_TYPE_ID_COUNT;
        result.tags = arena.pushArray(result.tag_count, AssetTag);
        result.tag_range[AssetTagId.FacingDirection.toInt()] = shared.TAU32;

        result.asset_count = 2 * 256 * ASSET_TYPE_ID_COUNT;
        result.assets = arena.pushArray(result.asset_count, Asset);
        result.slots = arena.pushArray(result.asset_count, AssetSlot);

        result.debug_used_bitmap_count = 1;
        result.debug_used_sound_count = 1;
        result.debug_used_asset_count = 1;

        result.beginAssetType(.Shadow);
        _ = result.addBitmapAsset("test/test_hero_shadow.bmp", Vector2.new(0.5, 0.15668203));
        result.endAssetType();

        result.beginAssetType(.Tree);
        _ = result.addBitmapAsset("test2/tree00.bmp", Vector2.new(0.49382716, 0.29565218));
        result.endAssetType();

        result.beginAssetType(.Sword);
        _ = result.addBitmapAsset("test2/rock03.bmp", Vector2.new(0.5, 0.65625));
        result.endAssetType();

        result.beginAssetType(.Grass);
        _ = result.addBitmapAsset("test2/grass00.bmp", null);
        _ = result.addBitmapAsset("test2/grass01.bmp", null);
        result.endAssetType();

        result.beginAssetType(.Stone);
        _ = result.addBitmapAsset("test2/ground00.bmp", null);
        _ = result.addBitmapAsset("test2/ground01.bmp", null);
        _ = result.addBitmapAsset("test2/ground02.bmp", null);
        _ = result.addBitmapAsset("test2/ground03.bmp", null);
        result.endAssetType();

        result.beginAssetType(.Tuft);
        _ = result.addBitmapAsset("test2/tuft00.bmp", null);
        _ = result.addBitmapAsset("test2/tuft01.bmp", null);
        _ = result.addBitmapAsset("test2/tuft02.bmp", null);
        result.endAssetType();

        const angle_right: f32 = 0;
        const angle_back: f32 = 0.25 * shared.TAU32;
        const angle_left: f32 = 0.5 * shared.TAU32;
        const angle_front: f32 = 0.75 * shared.TAU32;
        const hero_align = Vector2.new(0.5, 0.156682029);

        result.beginAssetType(.Head);
        _ = result.addBitmapAsset("test/test_hero_right_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_right);
        _ = result.addBitmapAsset("test/test_hero_back_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_back);
        _ = result.addBitmapAsset("test/test_hero_left_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_left);
        _ = result.addBitmapAsset("test/test_hero_front_head.bmp", hero_align);
        result.addTag(.FacingDirection, angle_front);
        result.endAssetType();

        result.beginAssetType(.Cape);
        _ = result.addBitmapAsset("test/test_hero_right_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_right);
        _ = result.addBitmapAsset("test/test_hero_back_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_back);
        _ = result.addBitmapAsset("test/test_hero_left_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_left);
        _ = result.addBitmapAsset("test/test_hero_front_cape.bmp", hero_align);
        result.addTag(.FacingDirection, angle_front);
        result.endAssetType();

        result.beginAssetType(.Torso);
        _ = result.addBitmapAsset("test/test_hero_right_torso.bmp", hero_align);
        result.addTag(.FacingDirection, angle_right);
        _ = result.addBitmapAsset("test/test_hero_back_torso.bmp", hero_align);
        result.addTag(.FacingDirection, angle_back);
        _ = result.addBitmapAsset("test/test_hero_left_torso.bmp", hero_align);
        result.addTag(.FacingDirection, angle_left);
        _ = result.addBitmapAsset("test/test_hero_front_torso.bmp", hero_align);
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

        return result;
    }

    pub fn getFirstSlot(self: *Assets, type_id: AssetTypeId) ?u32 {
        var result: ?u32 = null;
        const asset_type: *AssetType = &self.asset_types[type_id.toInt()];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            result = asset_type.first_asset_index;
        }

        return result;
    }

    pub fn getRandomSlot(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?u32 {
        var result: ?u32 = null;
        const asset_type: *AssetType = &self.asset_types[type_id.toInt()];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            const count: u32 = asset_type.one_past_last_asset_index - asset_type.first_asset_index;
            const choice = series.randomChoice(count);
            result = asset_type.first_asset_index + choice;
        }

        return result;
    }

    pub fn getBestMatchSlot(
        self: *Assets,
        type_id: AssetTypeId,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?u32 {
        var result: ?u32 = null;
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
                result = asset_index;
            }
        }

        return result;
    }

    pub fn getBitamapInfo(self: *Assets, id: BitmapId) *AssetBitmapInfo {
        std.debug.assert(id.value <= self.asset_count);
        return &self.assets[id.value].info.bitmap;
    }

    pub fn prefetchBitmap(
        self: *Assets,
        opt_id: ?BitmapId,
    ) void {
        self.loadBitmap(opt_id);
    }

    pub fn loadBitmap(
        self: *Assets,
        opt_id: ?BitmapId,
    ) void {
        if (opt_id) |id| {
            if (id.isValid() and @cmpxchgStrong(
                AssetState,
                &self.slots[id.value].state,
                .Unloaded,
                .Queued,
                .seq_cst,
                .seq_cst,
            ) == null) {
                if (handmade.beginTaskWithMemory(self.transient_state)) |task| {
                    var work: *LoadBitmapWork = task.arena.pushStruct(LoadBitmapWork);

                    work.assets = self;
                    work.id = id;
                    work.task = task;
                    work.bitmap = self.arena.pushStruct(LoadedBitmap);
                    work.final_state = .Loaded;

                    shared.addQueueEntry(self.transient_state.low_priority_queue, doLoadBitmapWork, work);
                } else {
                    @atomicStore(AssetState, &self.slots[id.value].state, .Unloaded, .release);
                }
            }
        }
    }

    pub fn getBitmap(self: *Assets, id: BitmapId) ?*LoadedBitmap {
        var result: ?*LoadedBitmap = null;

        if (self.slots[id.value].data.bitmap) |bitmap| {
            result = bitmap;
        }

        return result;
    }

    pub fn getFirstBitmap(self: *Assets, type_id: AssetTypeId) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.getFirstSlot(type_id)) |slot_id| {
            result = BitmapId{ .value = slot_id };
        }

        return result;
    }

    pub fn getRandomBitmap(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.getRandomSlot(type_id, series)) |slot_id| {
            result = BitmapId{ .value = slot_id };
        }

        return result;
    }

    pub fn getBestMatchBitmap(
        self: *Assets,
        type_id: AssetTypeId,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.getBestMatchSlot(type_id, match_vector, weight_vector)) |slot_id| {
            result = BitmapId{ .value = slot_id };
        }

        return result;
    }

    pub fn getSoundInfo(self: *Assets, id: SoundId) *AssetSoundInfo {
        std.debug.assert(id.value <= self.asset_count);
        return &self.assets[id.value].info.sound;
    }

    pub fn prefetchSound(
        self: *Assets,
        opt_id: ?SoundId,
    ) void {
        self.loadSound(opt_id);
    }

    pub fn loadSound(
        self: *Assets,
        opt_id: ?SoundId,
    ) void {
        if (opt_id) |id| {
            if (id.isValid() and @cmpxchgStrong(
                    AssetState,
                    &self.slots[id.value].state,
                    .Unloaded,
                    .Queued,
                    .seq_cst,
                    .seq_cst,
            ) == null) {
                if (handmade.beginTaskWithMemory(self.transient_state)) |task| {
                    var work: *LoadSoundWork = task.arena.pushStruct(LoadSoundWork);

                    work.assets = self;
                    work.id = id;
                    work.task = task;
                    work.sound = self.arena.pushStruct(LoadedSound);
                    work.final_state = .Loaded;

                    shared.addQueueEntry(self.transient_state.low_priority_queue, doLoadSoundWork, work);
                } else {
                    @atomicStore(AssetState, &self.slots[id.value].state, .Unloaded, .release);
                }
            }
        }
    }

    pub fn getSound(self: *Assets, id: SoundId) ?*LoadedSound {
        var result: ?*LoadedSound = null;

        if (self.slots[id.value].state == .Loaded) {
            if (self.slots[id.value].data.sound) |sound| {
                result = sound;
            }
        }

        return result;
    }

    pub fn getFirstSound(self: *Assets, type_id: AssetTypeId) ?SoundId {
        var result: ?SoundId = null;

        if (self.getFirstSlot(type_id)) |slot_id| {
            result = SoundId{ .value = slot_id };
        }

        return result;
    }

    pub fn getRandomSound(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?SoundId {
        var result: ?SoundId = null;

        if (self.getRandomSlot(type_id, series)) |slot_id| {
            result = SoundId{ .value = slot_id };
        }

        return result;
    }

    pub fn getBestMatchSound(
        self: *Assets,
        type_id: AssetTypeId,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?SoundId {
        var result: ?SoundId = null;

        if (self.getBestMatchSlot(type_id, match_vector, weight_vector)) |slot_id| {
            result = SoundId{ .value = slot_id };
        }

        return result;
    }
};

pub const LoadedBitmap = extern struct {
    alignment_percentage: Vector2 = Vector2.zero(),
    width_over_height: f32 = 0,

    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
    memory: ?[*]void,
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
    const info = work.assets.assets[work.id.value].info.bitmap;

    work.bitmap.* = debugLoadBMP(info.file_name, info.alignment_percentage);
    work.assets.slots[work.id.value] = AssetSlot{
        .data = .{ .bitmap = work.bitmap },
        .state = work.final_state,
    };

    handmade.endTaskWithMemory(work.task);
}

pub const LoadedSound = struct {
    sample_count: u32,
    channel_count: u32,
    samples: [2]?[*]i16,
};

const LoadSoundWork = struct {
    assets: *Assets,
    id: SoundId,
    task: *shared.TaskWithMemory,
    sound: *LoadedSound,

    final_state: AssetState,
};

fn doLoadSoundWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    const work: *LoadSoundWork = @ptrCast(@alignCast(data));
    const info = work.assets.assets[work.id.value].info.sound;

    work.sound.* = debugLoadWAV(info.file_name, info.first_sample_index, info.sample_count);
    work.assets.slots[work.id.value] = AssetSlot{
        .data = .{ .sound = work.sound },
        .state = work.final_state,
    };

    handmade.endTaskWithMemory(work.task);
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

const WaveHeader = extern struct {
    riff_id: u32,
    size: u32,
    wave_id: u32,
};

const WaveChunk = extern struct {
    id: u32,
    size: u32,
};

const WaveFmt = extern struct {
    w_format_tag: u16,
    channels: u16,
    n_samples_per_second: u32,
    n_avg_bytes_per_second: u32,
    n_block_align: u16,
    bits_per_sample: u16,
    cb_size: u16,
    w_valid_width_per_sample: u16,
    dw_channel_mask: u32,
    sub_format: [16]u8,
};

fn riffCode(a: u32, b: u32, c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, c << 16) | @as(u32, d << 24);
}

const WaveChunkId = enum(u32) {
    ChunkID_fmt = riffCode('f', 'm', 't', ' '),
    ChunkID_data = riffCode('d', 'a', 't', 'a'),
    ChunkID_RIFF = riffCode('R', 'I', 'F', 'F'),
    ChunkID_WAVE = riffCode('W', 'A', 'V', 'E'),
    _,
};

const RiffIterator = struct {
    at: [*]u8,
    stop: [*]u8,

    fn nextChunk(self: RiffIterator) RiffIterator {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        const size = (chunk.size + 1) & ~@as(u32, @intCast(1));
        return RiffIterator{ .at = self.at + @sizeOf(WaveChunk) + size, .stop = self.stop };
    }

    fn isValid(self: RiffIterator) bool {
        return @intFromPtr(self.at) < @intFromPtr(self.stop);
    }

    fn getType(self: RiffIterator) ?WaveChunkId {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        return std.meta.intToEnum(WaveChunkId, chunk.id) catch null;
    }

    fn getChunkData(self: RiffIterator) *void {
        return @ptrCast(self.at + @sizeOf(WaveChunk));
    }

    fn getChunkDataSize(self: RiffIterator) u32 {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        return chunk.size;
    }
};

fn parseWaveChunkAt(at: *void, stop: *void) RiffIterator {
    return RiffIterator{ .at = @ptrCast(at), .stop = @ptrCast(stop) };
}

pub fn debugLoadWAV(file_name: [*:0]const u8, section_first_sample_index: u32, section_sample_count: u32) LoadedSound {
    var result: LoadedSound = undefined;
    const read_result = shared.debugReadEntireFile(file_name);

    if (read_result.content_size > 0) {
        const header = @as(*WaveHeader, @ptrCast(@alignCast(read_result.contents)));

        std.debug.assert(header.riff_id == @intFromEnum(WaveChunkId.ChunkID_RIFF));
        std.debug.assert(header.wave_id == @intFromEnum(WaveChunkId.ChunkID_WAVE));

        var channel_count: ?u16 = null;
        var sample_data: ?[*]i16 = null;
        var sample_data_size: ?u32 = null;

        const chunk_address = @intFromPtr(header) + @sizeOf(WaveHeader);
        var iterator = parseWaveChunkAt(@ptrFromInt(chunk_address), @ptrFromInt(chunk_address + header.size - 4));
        while (iterator.isValid()) : (iterator = iterator.nextChunk()) {
            if (iterator.getType()) |chunk_type| {
                switch (chunk_type) {
                    .ChunkID_fmt => {
                        const fmt: *WaveFmt = @ptrCast(@alignCast(iterator.getChunkData()));

                        std.debug.assert(fmt.w_format_tag == 1);
                        std.debug.assert(fmt.n_samples_per_second == 48000);
                        std.debug.assert(fmt.bits_per_sample == 16);
                        std.debug.assert(fmt.n_block_align == (@sizeOf(i16) * fmt.channels));

                        channel_count = fmt.channels;
                    },
                    .ChunkID_data => {
                        sample_data = @ptrCast(@alignCast(iterator.getChunkData()));
                        sample_data_size = iterator.getChunkDataSize();
                    },
                    else => {},
                }
            }
        }

        std.debug.assert(channel_count != null and sample_data != null and sample_data_size != null);

        result.channel_count = channel_count.?;
        var sample_count = sample_data_size.? / (channel_count.? * @sizeOf(i16));

        if (sample_data) |data| {
            if (channel_count == 1) {
                result.samples[0] = @ptrCast(data);
                result.samples[1] = null;
            } else if (channel_count == 2) {
                result.samples[0] = @ptrCast(data);
                result.samples[1] = @ptrCast(data + sample_count);

                if (false) {
                    var i: i16 = 0;
                    while (i < sample_count) : (i += 1) {
                        data[2 * @as(usize, @intCast(i)) + 0] = i;
                        data[2 * @as(usize, @intCast(i)) + 1] = i;
                    }
                }

                var sample_index: u32 = 0;
                while (sample_index < sample_count) : (sample_index += 1) {
                    const source = data[2 * sample_index];
                    data[2 * sample_index] = data[sample_index];
                    data[sample_index] = source;
                }
            } else {
                // Invalid channel count in WAV file.
                unreachable;
            }
        }

        // TODO: Load right channels.
        result.channel_count = 1;

        var at_end = true;
        if (section_sample_count != 0) {
            std.debug.assert((section_first_sample_index + section_sample_count) <= sample_count);

            at_end = (section_first_sample_index + section_sample_count) == sample_count;
            sample_count = section_sample_count;

            var channel_index: u32 = 0;
            while (channel_index < result.channel_count) : (channel_index += 1) {
                result.samples[channel_index].? += section_first_sample_index;
            }
        }

        if (at_end) {
            var channel_index: u32 = 0;
            while (channel_index < result.channel_count) : (channel_index += 1) {
                var sample_index: u32 = sample_count;
                while (sample_index < (sample_count + 8)) : (sample_index += 1) {
                    result.samples[channel_index].?[sample_index] = 0;
                }
            }
        }

        result.sample_count = sample_count;
    }

    return result;
}
