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
const MemoryIndex = shared.MemoryIndex;
const Platform = shared.Platform;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAssetType = file_formats.HHAAssetType;
const HHAAsset = file_formats.HHAAsset;
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const PlatformFileHandle = shared.PlatformFileHandle;

pub const AssetTypeId = asset_type_id.AssetTypeId;
pub const AssetTagId = asset_type_id.AssetTagId;
pub const ASSET_TYPE_ID_COUNT = asset_type_id.COUNT;

const Asset = struct {
    hha: HHAAsset,
    file_index: u32,
};

const AssetType = struct {
    first_asset_index: u32,
    one_past_last_asset_index: u32,
};

pub const AssetVector = struct {
    e: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{0} ** ASSET_TYPE_ID_COUNT,
};

const AssetState = enum(u32) {
    Unloaded,
    Queued,
    Loaded,
    Locked,
    StateMask = 0xFFF,

    // All of this could be avoided by using the tagged union on AssetSlot to know which asset type it is.
    // But I have opted to use the same approach as Casey to avoid issues down the line.
    Sound = 0x1000,
    Bitmap = 0x2000,
    TypeMask = 0xF000,

    pub fn toInt(self: AssetState) u32 {
        return @intFromEnum(self);
    }
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
    state: u32 = 0,
    data: union(AssetSlotType) {
        bitmap: LoadedBitmap,
        sound: LoadedSound,
    },

    pub fn getState(self: *AssetSlot) AssetState {
        return @enumFromInt(self.state & @intFromEnum(AssetState.StateMask));
    }

    pub fn getType(self: *AssetSlot) AssetState {
        return @enumFromInt(self.state & @intFromEnum(AssetState.TypeMask));
    }
};

const AssetMemoryHeader = extern struct {
    next: *AssetMemoryHeader,
    previous: *AssetMemoryHeader,
    slot_index: u32,
    reserved: u32,
};

const AssetMemorySize = struct {
    total: u32 = 0,
    data: u32 = 0,
    section: u32 = 0,
};

const AssetFile = struct {
    handle: *PlatformFileHandle,
    header: HHAHeader,
    asset_type_array: [*]HHAAssetType,
    tag_base: u32,
    asset_base: u32,
};

pub const Assets = struct {
    transient_state: *TransientState,
    arena: MemoryArena,

    target_memory_used: u64,
    total_memory_used: u64,
    loaded_asset_sentinel: AssetMemoryHeader,

    asset_count: u32,
    assets: [*]Asset,
    asset_types: [ASSET_TYPE_ID_COUNT]AssetType = [1]AssetType{AssetType{}} ** ASSET_TYPE_ID_COUNT,

    slots: [*]AssetSlot,

    tag_count: u32,
    tags: [*]HHATag,
    tag_range: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{1000000} ** ASSET_TYPE_ID_COUNT,

    file_count: u32,
    files: [*]AssetFile,

    pub fn allocate(
        arena: *MemoryArena,
        memory_size: MemoryIndex,
        transient_state: *shared.TransientState,
    ) *Assets {
        var result = arena.pushStruct(Assets);

        result.transient_state = transient_state;
        result.arena = undefined;
        arena.makeSubArena(&result.arena, memory_size, null);

        result.total_memory_used = 0;
        result.target_memory_used = memory_size;

        result.loaded_asset_sentinel.next = &result.loaded_asset_sentinel;
        result.loaded_asset_sentinel.previous = &result.loaded_asset_sentinel;

        result.tag_range[@intFromEnum(AssetTagId.FacingDirection)] = shared.TAU32;

        result.tag_count = 1;
        result.asset_count = 1;

        // Load asset headers.
        {
            const file_group = shared.platform.getAllFilesOfTypeBegin("hha");
            defer shared.platform.getAllFilesOfTypeEnd(file_group);

            result.file_count = file_group.file_count;
            result.files = arena.pushArray(result.file_count, AssetFile);

            var file_index: u32 = 0;
            while (file_index < result.file_count) : (file_index += 1) {
                const file: [*]AssetFile = result.files + file_index;

                const file_handle = shared.platform.openNextFile(file_group);
                file[0].tag_base = result.tag_count;
                file[0].asset_base = result.asset_count;
                file[0].handle = file_handle;

                shared.platform.readDataFromFile(file[0].handle, 0, @sizeOf(HHAHeader), &file[0].header);

                const asset_type_array_size: u32 = file[0].header.asset_type_count * @sizeOf(HHAAssetType);
                file[0].asset_type_array = @ptrCast(@alignCast(arena.pushSize(asset_type_array_size, null)));
                shared.platform.readDataFromFile(
                    file[0].handle,
                    file[0].header.asset_types,
                    asset_type_array_size,
                    file[0].asset_type_array,
                );

                if (file[0].header.magic_value != file_formats.HHA_MAGIC_VALUE) {
                    shared.platform.fileError(file[0].handle, "HHA file has an invalid magic value.");
                }

                if (file[0].header.version > file_formats.HHA_VERSION) {
                    shared.platform.fileError(file[0].handle, "HHA file is of a later version.");
                }

                if (shared.platform.noFileErrors(file[0].handle)) {
                    // The first asset and tag slot in every HHA is a null,
                    // so we don't count it as something we will need space for.
                    result.tag_count += (file[0].header.tag_count - 1);
                    result.asset_count += (file[0].header.asset_count - 1);
                } else {
                    std.debug.assert(true);
                }
            }
        }

        result.assets = arena.pushArray(result.asset_count, Asset);
        result.slots = arena.pushArray(result.asset_count, AssetSlot);
        result.tags = arena.pushArray(result.tag_count, HHATag);

        shared.zeroStruct(HHATag, @ptrCast(result.tags));

        // Load tags.
        {
            var file_index: u32 = 0;
            while (file_index < result.file_count) : (file_index += 1) {
                const file: [*]AssetFile = result.files + file_index;
                if (shared.platform.noFileErrors(file[0].handle)) {
                    // Skip the first tag, since it is null.
                    const tag_array_size = @sizeOf(HHATag) * (file[0].header.tag_count - 1);
                    shared.platform.readDataFromFile(
                        file[0].handle,
                        file[0].header.tags + @sizeOf(HHATag),
                        tag_array_size,
                        result.tags + file[0].tag_base,
                    );
                }
            }
        }

        var asset_count: u32 = 0;
        shared.zeroStruct(Asset, @ptrCast(result.assets + asset_count));
        asset_count += 1;

        // Load assets.
        var dest_type_id: u32 = 0;
        while (dest_type_id < ASSET_TYPE_ID_COUNT) : (dest_type_id += 1) {
            var dest_type = &result.asset_types[dest_type_id];

            dest_type.first_asset_index = asset_count;

            var file_index: u32 = 0;
            while (file_index < result.file_count) : (file_index += 1) {
                const file: [*]AssetFile = result.files + file_index;

                if (shared.platform.noFileErrors(file[0].handle)) {
                    var source_index: u32 = 0;
                    while (source_index < file[0].header.asset_type_count) : (source_index += 1) {
                        const source_type: [*]HHAAssetType = file[0].asset_type_array + source_index;
                        if (source_type[0].type_id == dest_type_id) {
                            const asset_count_for_type =
                                source_type[0].one_past_last_asset_index - source_type[0].first_asset_index;

                            const temp_mem = transient_state.arena.beginTemporaryMemory();
                            defer transient_state.arena.endTemporaryMemory(temp_mem);
                            const hha_asset_array: [*]HHAAsset = transient_state.arena.pushArray(asset_count_for_type, HHAAsset);

                            shared.platform.readDataFromFile(
                                file[0].handle,
                                file[0].header.assets + source_type[0].first_asset_index * @sizeOf(HHAAsset),
                                asset_count_for_type * @sizeOf(HHAAsset),
                                hha_asset_array,
                            );

                            // Rebase tag indexes.
                            var asset_index: u32 = 0;
                            while (asset_index < asset_count_for_type) : (asset_index += 1) {
                                const hha_asset = hha_asset_array + asset_index;

                                std.debug.assert(asset_count < result.asset_count);
                                const asset = result.assets + asset_count;
                                asset_count += 1;

                                asset[0].file_index = file_index;
                                asset[0].hha = hha_asset[0];

                                if (asset[0].hha.first_tag_index == 0) {
                                    asset[0].hha.one_past_last_tag_index = 0;
                                } else {
                                    asset[0].hha.first_tag_index += (file[0].tag_base - 1);
                                    asset[0].hha.one_past_last_tag_index += (file[0].tag_base - 1);
                                }
                            }
                        }
                    }
                }
            }

            dest_type.one_past_last_asset_index = asset_count;
        }

        std.debug.assert(asset_count == result.asset_count);

        return result;
    }

    fn acquireAssetMemory(self: *Assets, size: MemoryIndex) ?*anyopaque {
        const result = shared.platform.allocateMemory(size);

        if (result != null) {
            self.total_memory_used += size;
        }

        return result;
    }

    fn releaseAssetMemory(self: *Assets, size: MemoryIndex, memory: ?*anyopaque) void {
        if (memory != null) {
            self.total_memory_used -= size;
        }

        shared.platform.deallocateMemory(memory);
    }

    pub fn evictAssetsAsNecessary(self: *Assets) void {
        while (self.total_memory_used > self.target_memory_used) {
            const opt_header: ?*AssetMemoryHeader = self.loaded_asset_sentinel.previous;

            if (opt_header) |header| {
                if (header != &self.loaded_asset_sentinel) {
                    self.evictAsset(header);
                }
            } else {
                unreachable;
            }
        }
    }

    fn evictAsset(self: *Assets, header: *AssetMemoryHeader) void {
        const slot_index = header.slot_index;
        const slot: *AssetSlot = &self.slots[slot_index];

        std.debug.assert(slot.state == AssetState.Loaded.toInt());

        const size = self.getSizeOfAsset(slot.getType(), slot_index);
        slot.state = AssetState.Unloaded.toInt();

        self.removeAssetHeaderFromList(header);

        switch (slot.getType()) {
            AssetState.Bitmap => {
                self.releaseAssetMemory(size.total, slot.data.bitmap.memory);
            },
            AssetState.Sound => {
                self.releaseAssetMemory(size.total, @ptrCast(slot.data.sound.samples[0]));
            },
            else => unreachable,
        }
    }

    fn getSizeOfAsset(self: *Assets, asset_type: AssetState, slot_index: u32) AssetMemorySize {
        var result = AssetMemorySize{};
        const asset = &self.assets[slot_index];

        switch (asset_type) {
            AssetState.Bitmap => {
                const info = asset.hha.info.bitmap;

                const width = shared.safeTruncateUInt32ToUInt16(info.dim[0]);
                const height = shared.safeTruncateUInt32ToUInt16(info.dim[1]);
                result.section = 4 * width;
                result.data = result.section * height;
            },
            AssetState.Sound => {
                const info = asset.hha.info.sound;

                result.section = info.sample_count * @sizeOf(i16);
                result.data = info.channel_count * result.section;
            },
            else => unreachable,
        }

        result.data = shared.align8(result.data);
        result.total = result.data + @sizeOf(AssetMemoryHeader);

        return result;
    }

    fn addAssetHeaderToList(self: *Assets, slot_index: u32, memory: *anyopaque, size: AssetMemorySize) void {
        const header: *AssetMemoryHeader = @ptrCast(@alignCast(@as([*]u8, @ptrCast(memory)) + size.data));
        const sentinel = &self.loaded_asset_sentinel;

        header.slot_index = slot_index;

        header.previous = sentinel;
        header.next = sentinel.next;

        header.next.previous = header;
        header.previous.next = header;
    }

    fn removeAssetHeaderFromList(self: *Assets, header: *AssetMemoryHeader) void {
        _ = self;
        header.previous.next = header.next;
        header.next.previous = header.previous;
    }

    fn getFileHandleFor(self: *Assets, file_index: u32) *shared.PlatformFileHandle {
        std.debug.assert(file_index < self.file_count);
        return self.files[file_index].handle;
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
            var tag_index: u32 = asset.hha.first_tag_index;
            while (tag_index < asset.hha.one_past_last_tag_index) : (tag_index += 1) {
                const tag: *HHATag = &self.tags[tag_index];

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

    pub fn getBitamapInfo(self: *Assets, id: BitmapId) *HHABitmap {
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
            var slot = &self.slots[id.value];

            if (id.isValid() and @cmpxchgStrong(
                u32,
                &slot.state,
                AssetState.Unloaded.toInt(),
                AssetState.Queued.toInt(),
                .seq_cst,
                .seq_cst,
            ) == null) {
                if (handmade.beginTaskWithMemory(self.transient_state)) |task| {
                    const asset = &self.assets[id.value];
                    const info = asset.hha.info.bitmap;
                    var bitmap: *LoadedBitmap = &slot.data.bitmap;

                    bitmap.alignment_percentage = Vector2.new(info.alignment_percentage[0], info.alignment_percentage[1]);
                    bitmap.width_over_height = @as(f32, @floatFromInt(info.dim[0])) / @as(f32, @floatFromInt(info.dim[1]));
                    bitmap.width = shared.safeTruncateUInt32ToUInt16(info.dim[0]);
                    bitmap.height = shared.safeTruncateUInt32ToUInt16(info.dim[1]);

                    const size: AssetMemorySize = self.getSizeOfAsset(.Bitmap, id.value);
                    bitmap.pitch = shared.safeTruncateUInt32ToUInt16(size.section);

                    if (self.acquireAssetMemory(size.total)) |memory| {
                        bitmap.memory = @ptrCast(memory);

                        var work: *LoadAssetWork = task.arena.pushStruct(LoadAssetWork);
                        work.task = task;
                        work.slot = slot;
                        work.handle = self.getFileHandleFor(asset.file_index);
                        work.offset = asset.hha.data_offset;
                        work.size = size.data;
                        work.destination = @ptrCast(bitmap.memory);
                        work.final_state = AssetState.Loaded.toInt() | AssetState.Bitmap.toInt();

                        self.addAssetHeaderToList(id.value, memory, size);

                        shared.platform.addQueueEntry(self.transient_state.low_priority_queue, doLoadAssetWork, work);
                    }
                } else {
                    @atomicStore(u32, &slot.state, AssetState.Unloaded.toInt(), .release);
                }
            }
        }
    }

    pub fn getBitmap(self: *Assets, id: BitmapId) ?*LoadedBitmap {
        var result: ?*LoadedBitmap = null;
        var slot = &self.slots[id.value];

        if (slot.state >= AssetState.Loaded.toInt()) {
            @fence(.acquire);
            result = &slot.data.bitmap;
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

    pub fn getSoundInfo(self: *Assets, id: SoundId) *HHASound {
        std.debug.assert(id.value <= self.asset_count);
        return &self.assets[id.value].hha.info.sound;
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
            var slot = &self.slots[id.value];

            if (id.isValid() and @cmpxchgStrong(
                    u32,
                    &slot.state,
                    AssetState.Unloaded.toInt(),
                    AssetState.Queued.toInt(),
                    .seq_cst,
                    .seq_cst,
            ) == null) {
                if (handmade.beginTaskWithMemory(self.transient_state)) |task| {
                    const asset = &self.assets[id.value];
                    const info = asset.hha.info.sound;
                    var sound: *LoadedSound = undefined;
                    switch (slot.data) {
                        AssetSlotType.sound => {
                            sound = &slot.data.sound;
                        },
                        AssetSlotType.bitmap => {
                            slot.data = .{ .sound = LoadedSound{} };
                            sound = &slot.data.sound;
                        },
                    }

                    sound.sample_count = info.sample_count;
                    sound.channel_count = info.channel_count;

                    const size = self.getSizeOfAsset(.Sound, id.value);
                    const channel_size = size.section;

                    if (self.acquireAssetMemory(size.total)) |memory| {
                        var sound_at: [*]i16 = @ptrCast(@alignCast(memory));
                        var channel_index: u32 = 0;
                        while (channel_index < sound.channel_count) : (channel_index += 1) {
                            sound.samples[channel_index] = sound_at;
                            sound_at += channel_size;
                        }

                        var work: *LoadAssetWork = task.arena.pushStruct(LoadAssetWork);
                        work.task = task;
                        work.slot = slot;
                        work.handle = self.getFileHandleFor(asset.file_index);
                        work.offset = asset.hha.data_offset;
                        work.size = size.data;
                        work.destination = memory;
                        work.final_state = AssetState.Loaded.toInt() | AssetState.Sound.toInt();

                        self.addAssetHeaderToList(id.value, memory, size);

                        shared.platform.addQueueEntry(self.transient_state.low_priority_queue, doLoadAssetWork, work);
                    }
                } else {
                    @atomicStore(u32, &slot.state, AssetState.Unloaded.toInt(), .release);
                }
            }
        }
    }

    pub fn getSound(self: *Assets, id: SoundId) ?*LoadedSound {
        var result: ?*LoadedSound = null;
        var slot = &self.slots[id.value];

        switch (slot.data) {
            AssetSlotType.sound => {
                if (slot.state >= AssetState.Loaded.toInt()) {
                    @fence(.acquire);
                    result = &slot.data.sound;
                }
            },
            AssetSlotType.bitmap => {},
        }

        return result;
    }

    pub fn getNextSoundInChain(self: *Assets, id: SoundId) ?SoundId {
        var result: ?SoundId = null;

        const info = self.getSoundInfo(id);
        switch (info.chain) {
            .None => {},
            .Advance => {
                result = SoundId{ .value = id.value + 1 };
            },
            .Loop => {
                result = id;
            },
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

pub const WritableBitmap = struct {
    pitch: i32 = 0,
};

pub const LoadedBitmap = extern struct {
    memory: ?[*]void,

    alignment_percentage: Vector2 = Vector2.zero(),
    width_over_height: f32 = 0,
    width: u16 = 0,
    height: u16 = 0,
    pitch: u16 = 0,

    pub fn getPitch(self: *LoadedSound) i16 {
        return self.width;
    }
};

pub const LoadedSound = struct {
    samples: [2]?[*]i16 = undefined,
    sample_count: u32 = undefined,
    channel_count: u32 = undefined,
};

const LoadAssetWork = struct {
    task: *shared.TaskWithMemory,
    slot: *AssetSlot,

    handle: *PlatformFileHandle = undefined,
    offset: u64,
    size: u64,
    destination: *anyopaque,

    final_state: u32,
};

fn doLoadAssetWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    const work: *LoadAssetWork = @ptrCast(@alignCast(data));

    shared.platform.readDataFromFile(work.handle, work.offset, work.size, work.destination);

    if (!shared.platform.noFileErrors(work.handle)) {
        shared.zeroSize(work.size, @ptrCast(work.destination));
    }

    work.slot.state = work.final_state;

    handmade.endTaskWithMemory(work.task);
}

