const shared = @import("shared.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const render = @import("render.zig");
const handmade = @import("handmade.zig");
const intrinsics = @import("intrinsics.zig");
const asset_type_id = @import("asset_type_id.zig");
const file_formats = @import("file_formats");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const TransientState = shared.TransientState;
const MemoryArena = shared.MemoryArena;
const Platform = shared.Platform;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAssetType = file_formats.HHAAssetType;
const HHAAsset = file_formats.HHAAsset;
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;

pub const AssetTypeId = asset_type_id.AssetTypeId;
pub const AssetTagId = asset_type_id.AssetTagId;
pub const ASSET_TYPE_ID_COUNT = asset_type_id.COUNT;

const AssetType = struct {
    first_asset_index: u32,
    one_past_last_asset_index: u32,
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

    pub fn allocate(
        arena: *MemoryArena,
        memory_size: shared.MemoryIndex,
        transient_state: *shared.TransientState,
    ) *Assets {
        var result = arena.pushStruct(Assets);

        result.transient_state = transient_state;
        result.arena = undefined;

        arena.makeSubArena(&result.arena, memory_size, null);

        const read_result = shared.debugReadEntireFile("test.hha");
        if (read_result.content_size != 0) {
            const header: *HHAHeader = @ptrCast(@alignCast(read_result.contents));

            std.debug.assert(header.magic_value == file_formats.HHA_MAGIC_VALUE);
            std.debug.assert(header.version == file_formats.HHA_VERSION);

            result.tag_count = header.asset_count;
            result.tags = arena.pushArray(result.tag_count, AssetTag);
            result.tag_range[AssetTagId.FacingDirection.toInt()] = shared.TAU32;

            result.asset_count = header.asset_count;
            result.assets = arena.pushArray(result.asset_count, Asset);
            result.slots = arena.pushArray(result.asset_count, AssetSlot);

            const hha_tags: [*]HHATag = @ptrFromInt(@intFromPtr(read_result.contents) + header.tags);
            var tag_index: u32 = 0;
            while (tag_index < result.tag_count) : (tag_index += 1) {
                const source: [*]HHATag = hha_tags + tag_index;
                var dest = result.tags + tag_index;

                dest[0].id = source[0].id;
                dest[0].value = source[0].value;
            }
        }

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

fn debugLoadBMP(file_name: [*:0]const u8, alignment_percentage: ?Vector2) LoadedBitmap {
    _ = file_name;
    _ = alignment_percentage;

    std.debug.assert(true);

    return LoadedBitmap{ .memory = undefined };
}

pub fn debugLoadWAV(file_name: [*:0]const u8, section_first_sample_index: u32, section_sample_count: u32) LoadedSound {
    _ = file_name;
    _ = section_first_sample_index;
    _ = section_sample_count;

    std.debug.assert(true);

    return LoadedSound{ .sample_count = 0, .channel_count = 0, .samples = undefined };
}
