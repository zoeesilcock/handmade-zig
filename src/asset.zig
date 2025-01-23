const shared = @import("shared.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const render = @import("render.zig");
const handmade = @import("handmade.zig");
const intrinsics = @import("intrinsics.zig");
const file_formats = @import("file_formats");
const debug_interface = @import("debug_interface.zig");
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
const HHAFont = file_formats.HHAFont;
const HHAFontGlyph = file_formats.HHAFontGlyph;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const FontId = file_formats.FontId;
const PlatformFileHandle = shared.PlatformFileHandle;
const ArenaPushParams = shared.ArenaPushParams;
const TimedBlock = debug_interface.TimedBlock;

pub const AssetTypeId = file_formats.AssetTypeId;
pub const AssetTagId = file_formats.AssetTagId;
pub const ASSET_TYPE_ID_COUNT = file_formats.ASSET_TYPE_ID_COUNT;

const Asset = struct {
    state: u32 = 0,
    header: ?*AssetMemoryHeader,

    hha: HHAAsset,
    file_index: u32,
};

const AssetMemoryHeader = extern struct {
    next: ?*AssetMemoryHeader,
    previous: ?*AssetMemoryHeader,
    asset_index: u32,
    total_size: u32,
    generation_id: u32,
    data: extern union {
        bitmap: LoadedBitmap,
        sound: LoadedSound,
        font: LoadedFont,
    },
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

    pub fn toInt(self: AssetState) u32 {
        return @intFromEnum(self);
    }
};

const AssetGroup = struct {
    first_tag_index: u32,
    one_past_last_index: u32,
};

const AssetMemorySize = struct {
    total: u32 = 0,
    data: u32 = 0,
    section: u32 = 0,
};

const AssetFile = struct {
    handle: PlatformFileHandle,
    header: HHAHeader,
    asset_type_array: [*]HHAAssetType,
    tag_base: u32,
    asset_base: u32,
    font_bitmap_id_offset: u32,
};

const AssetMemoryBlockFlags = enum(u32) {
    Used = 0x1,
};

const AssetMemoryBlock = extern struct {
    previous: ?*AssetMemoryBlock,
    next: ?*AssetMemoryBlock,
    flags: u64,
    size: MemoryIndex,
};

pub const Assets = struct {
    next_generation_id: u32,

    transient_state: *TransientState,

    memory_sentinel: AssetMemoryBlock,

    loaded_asset_sentinel: AssetMemoryHeader,

    tag_range: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{1000000} ** ASSET_TYPE_ID_COUNT,

    file_count: u32,
    files: [*]AssetFile,

    tag_count: u32,
    tags: [*]HHATag,

    asset_count: u32,
    assets: [*]Asset,

    asset_types: [ASSET_TYPE_ID_COUNT]AssetType = [1]AssetType{AssetType{}} ** ASSET_TYPE_ID_COUNT,

    operation_lock: u32,

    in_flight_generation_count: u32,
    in_flight_generations: [16]u32,

    pub fn allocate(
        arena: *MemoryArena,
        memory_size: MemoryIndex,
        transient_state: *shared.TransientState,
    ) *Assets {
        var assets = arena.pushStruct(Assets, ArenaPushParams.aligned(@alignOf(Assets), true));

        assets.next_generation_id = 0;
        assets.in_flight_generation_count = 0;

        assets.transient_state = transient_state;
        assets.memory_sentinel = AssetMemoryBlock{
            .flags = 0,
            .size = 0,
            .previous = null,
            .next = null,
        };
        assets.memory_sentinel.previous = &assets.memory_sentinel;
        assets.memory_sentinel.next = &assets.memory_sentinel;

        _ = assets.insertBlock(
            &assets.memory_sentinel,
            memory_size,
            arena.pushSize(memory_size, ArenaPushParams.noClear()),
        );

        assets.loaded_asset_sentinel.next = &assets.loaded_asset_sentinel;
        assets.loaded_asset_sentinel.previous = &assets.loaded_asset_sentinel;

        assets.tag_range[@intFromEnum(AssetTagId.FacingDirection)] = shared.TAU32;

        assets.tag_count = 1;
        assets.asset_count = 1;

        // Load asset headers.
        {
            var file_group = shared.platform.getAllFilesOfTypeBegin(.AssetFile);
            defer shared.platform.getAllFilesOfTypeEnd(&file_group);

            assets.file_count = file_group.file_count;
            assets.files = arena.pushArray(assets.file_count, AssetFile, null);

            var file_index: u32 = 0;
            while (file_index < assets.file_count) : (file_index += 1) {
                const file: [*]AssetFile = assets.files + file_index;

                const file_handle = shared.platform.openNextFile(&file_group);
                file[0].font_bitmap_id_offset = 0;
                file[0].tag_base = assets.tag_count;
                file[0].asset_base = assets.asset_count;
                file[0].handle = file_handle;

                var offset: u32 = 0;
                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u32), &file[0].header.magic_value);
                offset += @sizeOf(u32);
                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u32), &file[0].header.version);
                offset += @sizeOf(u32);
                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u32), &file[0].header.tag_count);
                offset += @sizeOf(u32);
                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u32), &file[0].header.asset_type_count);
                offset += @sizeOf(u32);
                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u32), &file[0].header.asset_count);
                offset += @sizeOf(u32);

                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u64), &file[0].header.tags);
                offset += @sizeOf(u64);
                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u64), &file[0].header.asset_types);
                offset += @sizeOf(u64);
                shared.platform.readDataFromFile(&file[0].handle, offset, @sizeOf(u64), &file[0].header.assets);
                offset += @sizeOf(u64);

                const asset_type_array_size: u32 = file[0].header.asset_type_count * @sizeOf(HHAAssetType);
                file[0].asset_type_array = @ptrCast(@alignCast(arena.pushSize(asset_type_array_size, null)));
                shared.platform.readDataFromFile(
                    &file[0].handle,
                    file[0].header.asset_types,
                    asset_type_array_size,
                    file[0].asset_type_array,
                );

                if (file[0].header.magic_value != file_formats.HHA_MAGIC_VALUE) {
                    shared.platform.fileError(&file[0].handle, "HHA file has an invalid magic value.");
                }

                if (file[0].header.version > file_formats.HHA_VERSION) {
                    shared.platform.fileError(&file[0].handle, "HHA file is of a later version.");
                }

                if (shared.platform.noFileErrors(&file[0].handle)) {
                    // The first asset and tag slot in every HHA is a null,
                    // so we don't count it as something we will need space for.
                    assets.tag_count += (file[0].header.tag_count - 1);
                    assets.asset_count += (file[0].header.asset_count - 1);
                } else {
                    std.debug.assert(true);
                }
            }
        }

        assets.assets = arena.pushArray(assets.asset_count, Asset, ArenaPushParams.aligned(@alignOf(Asset), true));
        assets.tags = arena.pushArray(assets.tag_count, HHATag, null);

        shared.zeroStruct(HHATag, @ptrCast(assets.tags));

        // Load tags.
        {
            var file_index: u32 = 0;
            while (file_index < assets.file_count) : (file_index += 1) {
                const file: [*]AssetFile = assets.files + file_index;
                if (shared.platform.noFileErrors(&file[0].handle)) {
                    // Skip the first tag, since it is null.
                    const tag_array_size = @sizeOf(HHATag) * (file[0].header.tag_count - 1);
                    shared.platform.readDataFromFile(
                        &file[0].handle,
                        file[0].header.tags + @sizeOf(HHATag),
                        tag_array_size,
                        assets.tags + file[0].tag_base,
                    );
                }
            }
        }

        var asset_count: u32 = 0;
        shared.zeroStruct(Asset, @ptrCast(assets.assets + asset_count));
        asset_count += 1;

        // Load assets.
        var dest_type_id: u32 = 0;
        while (dest_type_id < ASSET_TYPE_ID_COUNT) : (dest_type_id += 1) {
            var dest_type = &assets.asset_types[dest_type_id];

            dest_type.first_asset_index = asset_count;

            var file_index: u32 = 0;
            while (file_index < assets.file_count) : (file_index += 1) {
                const file: [*]AssetFile = assets.files + file_index;

                if (shared.platform.noFileErrors(&file[0].handle)) {
                    var source_index: u32 = 0;
                    while (source_index < file[0].header.asset_type_count) : (source_index += 1) {
                        const source_type: [*]HHAAssetType = file[0].asset_type_array + source_index;
                        if (source_type[0].type_id == dest_type_id) {
                            if (source_type[0].type_id == AssetTypeId.FontGlyph.toInt()) {
                                file[0].font_bitmap_id_offset = asset_count - source_type[0].first_asset_index;
                            }

                            const asset_count_for_type =
                                source_type[0].one_past_last_asset_index - source_type[0].first_asset_index;

                            const temp_mem = transient_state.arena.beginTemporaryMemory();
                            defer transient_state.arena.endTemporaryMemory(temp_mem);
                            const hha_asset_array: [*]HHAAsset = transient_state.arena.pushArray(asset_count_for_type, HHAAsset, null);

                            shared.platform.readDataFromFile(
                                &file[0].handle,
                                file[0].header.assets + source_type[0].first_asset_index * @sizeOf(HHAAsset),
                                asset_count_for_type * @sizeOf(HHAAsset),
                                hha_asset_array,
                            );

                            // Rebase tag indexes.
                            var asset_index: u32 = 0;
                            while (asset_index < asset_count_for_type) : (asset_index += 1) {
                                const hha_asset = hha_asset_array + asset_index;

                                std.debug.assert(asset_count < assets.asset_count);
                                const asset = assets.assets + asset_count;
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

        std.debug.assert(asset_count == assets.asset_count);

        return assets;
    }

    pub fn beginGeneration(self: *Assets) u32 {
        self.beginAssetLock();
        defer self.endAssetLock();

        std.debug.assert(self.in_flight_generation_count < self.in_flight_generations.len);

        const result = self.next_generation_id;
        self.next_generation_id +%= 1;

        self.in_flight_generations[self.in_flight_generation_count] = result;
        self.in_flight_generation_count += 1;

        return result;
    }

    pub fn endGeneration(self: *Assets, generation_id: u32) void {
        self.beginAssetLock();
        defer self.endAssetLock();

        var index: u32 = 0;
        while (index < self.in_flight_generation_count) : (index += 1) {
            if (self.in_flight_generations[index] == generation_id) {
                self.in_flight_generation_count -= 1;
                self.in_flight_generations[index] = self.in_flight_generations[self.in_flight_generation_count];
            }
        }
    }

    fn generationHasCompleted(self: *Assets, check_id: u32) bool {
        var result = true;

        var index: u32 = 0;
        while (index < self.in_flight_generation_count) : (index += 1) {
            if (self.in_flight_generations[index] == check_id) {
                result = false;
                break;
            }
        }

        return result;
    }

    fn insertBlock(_: *Assets, previous: *AssetMemoryBlock, size: u64, memory: *anyopaque) *AssetMemoryBlock {
        std.debug.assert(size > @sizeOf(AssetMemoryBlock));
        var block: *AssetMemoryBlock = @ptrCast(@alignCast(memory));
        block.flags = 0;
        block.size = size - @sizeOf(AssetMemoryBlock);
        block.previous = previous;
        block.next = previous.next;
        block.previous.?.next = block;
        block.next.?.previous = block;
        return block;
    }

    fn findBlockForSize(self: *Assets, size: MemoryIndex) ?*AssetMemoryBlock {
        var result: ?*AssetMemoryBlock = null;
        var block = self.memory_sentinel.next;

        while (block != null and block != &self.memory_sentinel) : (block = block.?.next) {
            if ((block.?.flags & @intFromEnum(AssetMemoryBlockFlags.Used)) == 0) {
                if (block.?.size >= size) {
                    result = block;
                    break;
                }
            }
        }

        return result;
    }

    fn mergeIfPossible(self: *Assets, first: *AssetMemoryBlock, second: *AssetMemoryBlock) bool {
        var result = false;

        if (first != &self.memory_sentinel and second != &self.memory_sentinel) {
            if ((first.flags & @intFromEnum(AssetMemoryBlockFlags.Used)) == 0 and
                (second.flags & @intFromEnum(AssetMemoryBlockFlags.Used)) == 0)
            {
                const expected_second = @as([*]u8, @ptrCast(first)) + @sizeOf(AssetMemoryBlock) + first.size;
                if (@as([*]u8, @ptrCast(second)) == expected_second) {
                    second.next.?.previous = second.previous;
                    second.previous.?.next = second.next;

                    first.size += @sizeOf(AssetMemoryBlock) + second.size;

                    result = true;
                }
            }
        }

        return result;
    }

    fn beginAssetLock(self: *Assets) void {
        while (true) {
            if (@cmpxchgStrong(u32, &self.operation_lock, 0, 1, .seq_cst, .seq_cst) == null) {
                break;
            }
        }
    }

    fn endAssetLock(self: *Assets) void {
        self.operation_lock = 0;
    }

    fn acquireAssetMemory(self: *Assets, size: u32, asset_index: u32) ?*AssetMemoryHeader {
        var timed_block = TimedBlock.beginFunction(@src(), .AcquireAssetMemory);
        defer timed_block.end();

        var result: ?*AssetMemoryHeader = null;
        var opt_block = self.findBlockForSize(size);

        self.beginAssetLock();
        defer self.endAssetLock();

        while (true) {
            if (opt_block != null and size <= opt_block.?.size) {
                // Use the block found.
                const block = opt_block.?;

                block.flags |= @intFromEnum(AssetMemoryBlockFlags.Used);

                result = @ptrCast(@as([*]AssetMemoryBlock, @ptrCast(block)) + 1);

                const remaining_size = block.size - size;
                const block_split_threshold = 4096;

                if (remaining_size > block_split_threshold) {
                    block.size -= remaining_size;
                    _ = self.insertBlock(block, remaining_size, @as([*]u8, @ptrCast(result)) + size);
                }

                break;
            } else {
                // No block found, evict something to make space.
                var header: ?*AssetMemoryHeader = self.loaded_asset_sentinel.previous;
                while (header != null and header.? != &self.loaded_asset_sentinel) : (header = header.?.previous) {
                    var asset: *Asset = &self.assets[header.?.asset_index];
                    if (asset.state >= AssetState.Loaded.toInt() and
                        self.generationHasCompleted(asset.header.?.generation_id))
                    {
                        std.debug.assert(asset.state == AssetState.Loaded.toInt());

                        self.removeAssetHeaderFromList(header.?);

                        opt_block = @ptrCast(@as([*]AssetMemoryBlock, @ptrCast(@alignCast(asset.header))) - 1);
                        opt_block.?.flags &= ~@intFromEnum(AssetMemoryBlockFlags.Used);

                        if (self.mergeIfPossible(opt_block.?.previous.?, opt_block.?)) {
                            opt_block = opt_block.?.previous;
                        }

                        _ = self.mergeIfPossible(opt_block.?, opt_block.?.next.?);

                        asset.state = AssetState.Unloaded.toInt();
                        asset.header = null;

                        break;
                    }
                }
            }
        }

        if (result) |header| {
            header.asset_index = asset_index;
            header.total_size = size;
            self.insertAssetHeaderAtFront(header);
        }

        return result;
    }

    fn insertAssetHeaderAtFront(self: *Assets, header: *AssetMemoryHeader) void {
        const sentinel = &self.loaded_asset_sentinel;

        header.previous = sentinel;
        header.next = sentinel.next;

        header.next.?.previous = header;
        header.previous.?.next = header;
    }

    fn removeAssetHeaderFromList(self: *Assets, header: *AssetMemoryHeader) void {
        _ = self;
        header.previous.?.next = header.next;
        header.next.?.previous = header.previous;
        header.next = null;
        header.previous = null;
    }

    fn getFile(self: *Assets, file_index: u32) *AssetFile {
        std.debug.assert(file_index < self.file_count);
        return &self.files[file_index];
    }

    fn getFileHandleFor(self: *Assets, file_index: u32) *shared.PlatformFileHandle {
        return &self.getFile(file_index).handle;
    }

    pub fn getFirstAsset(self: *Assets, type_id: AssetTypeId) ?u32 {
        var timed_block = TimedBlock.beginFunction(@src(), .GetFirstAsset);
        defer timed_block.end();

        var result: ?u32 = null;
        const asset_type: *AssetType = &self.asset_types[type_id.toInt()];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            result = asset_type.first_asset_index;
        }

        return result;
    }

    pub fn getRandomAsset(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?u32 {
        var timed_block = TimedBlock.beginFunction(@src(), .GetRandomAsset);
        defer timed_block.end();

        var result: ?u32 = null;
        const asset_type: *AssetType = &self.asset_types[type_id.toInt()];

        if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
            const count: u32 = asset_type.one_past_last_asset_index - asset_type.first_asset_index;
            const choice = series.randomChoice(count);
            result = asset_type.first_asset_index + choice;
        }

        return result;
    }

    pub fn getBestMatchAsset(
        self: *Assets,
        type_id: AssetTypeId,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?u32 {
        var timed_block = TimedBlock.beginFunction(@src(), .GetBestMatchAsset);
        defer timed_block.end();

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
        self.loadBitmap(opt_id, false);
    }

    pub fn loadBitmap(
        self: *Assets,
        opt_id: ?BitmapId,
        immediate: bool,
    ) void {
        var timed_block = TimedBlock.beginFunction(@src(), .LoadBitmap);
        defer timed_block.end();

        if (opt_id) |id| {
            var asset = &self.assets[id.value];
            if (id.isValid()) {
                if (@cmpxchgStrong(
                    u32,
                    &asset.state,
                    AssetState.Unloaded.toInt(),
                    AssetState.Queued.toInt(),
                    .seq_cst,
                    .seq_cst,
                ) == null) {
                    var opt_task: ?*shared.TaskWithMemory = null;

                    if (!immediate) {
                        opt_task = handmade.beginTaskWithMemory(self.transient_state, false);
                    }

                    if (immediate or opt_task != null) {
                        const info = asset.hha.info.bitmap;

                        var size = AssetMemorySize{};
                        const width = shared.safeTruncateUInt32ToUInt16(info.dim[0]);
                        const height = shared.safeTruncateUInt32ToUInt16(info.dim[1]);
                        size.section = 4 * width;
                        size.data = size.section * height;
                        size.total = size.data + @sizeOf(AssetMemoryHeader);

                        asset.header = self.acquireAssetMemory(shared.align16(size.total), id.value);

                        var bitmap: *LoadedBitmap = @ptrCast(@alignCast(&asset.header.?.data.bitmap));

                        bitmap.alignment_percentage = Vector2.new(info.alignment_percentage[0], info.alignment_percentage[1]);
                        bitmap.width_over_height = @as(f32, @floatFromInt(info.dim[0])) / @as(f32, @floatFromInt(info.dim[1]));
                        bitmap.width = width;
                        bitmap.height = height;
                        bitmap.pitch = shared.safeTruncateUInt32ToUInt16(size.section);
                        bitmap.memory = @ptrCast(@as([*]AssetMemoryHeader, @ptrCast(asset.header)) + 1);
                        bitmap.handle = 0;

                        var work = LoadAssetWork{
                            .task = undefined,
                            .asset = asset,
                            .handle = self.getFileHandleFor(asset.file_index),
                            .offset = asset.hha.data_offset,
                            .size = size.data,
                            .destination = @ptrCast(bitmap.memory),
                            .finalize_operation = .None,
                            .final_state = AssetState.Loaded.toInt(),
                        };

                        if (opt_task) |task| {
                            work.task = task;

                            const task_work: *LoadAssetWork = task.arena.pushStruct(
                                LoadAssetWork,
                                ArenaPushParams.noClear(),
                            );
                            task_work.* = work;
                            shared.platform.addQueueEntry(
                                self.transient_state.low_priority_queue,
                                doLoadAssetWork,
                                task_work,
                            );
                        } else {
                            doLoadAssetWorkDirectly(&work);
                        }
                    } else {
                        @atomicStore(u32, &asset.state, AssetState.Unloaded.toInt(), .release);
                    }
                } else if (immediate) {
                    // The asset is already queued on another thread, wait until that asset loading is completed.
                    const state: *volatile u32 = &asset.state;
                    while (state.* == AssetState.Queued.toInt()) {}
                }
            }
        }
    }

    fn getAsset(self: *Assets, id: u32, generation_id: u32) ?*AssetMemoryHeader {
        std.debug.assert(id <= self.asset_count);
        const asset = &self.assets[id];

        var result: ?*AssetMemoryHeader = null;

        self.beginAssetLock();
        defer self.endAssetLock();

        if (asset.state == AssetState.Loaded.toInt()) {
            if (asset.header) |header| {
                result = header;
                self.removeAssetHeaderFromList(result.?);
                self.insertAssetHeaderAtFront(result.?);

                if (header.generation_id < generation_id) {
                    header.generation_id = generation_id;
                }
            }
        }

        return result;
    }

    pub fn getBitmap(self: *Assets, id: BitmapId, generation_id: u32) ?*LoadedBitmap {
        var result: ?*LoadedBitmap = null;

        if (self.getAsset(id.value, generation_id)) |header| {
            result = &header.data.bitmap;
        }

        return result;
    }

    pub fn getBitmapInfo(self: *Assets, id: BitmapId) *HHABitmap {
        std.debug.assert(id.value <= self.asset_count);
        return &self.assets[id.value].hha.info.bitmap;
    }

    pub fn getFirstBitmap(self: *Assets, type_id: AssetTypeId) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.getFirstAsset(type_id)) |slot_id| {
            result = BitmapId{ .value = slot_id };
        }

        return result;
    }

    pub fn getRandomBitmap(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.getRandomAsset(type_id, series)) |slot_id| {
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

        if (self.getBestMatchAsset(type_id, match_vector, weight_vector)) |slot_id| {
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
        var timed_block = TimedBlock.beginFunction(@src(), .LoadSound);
        defer timed_block.end();

        if (opt_id) |id| {
            var asset = &self.assets[id.value];

            if (id.isValid() and @cmpxchgStrong(
                u32,
                &asset.state,
                AssetState.Unloaded.toInt(),
                AssetState.Queued.toInt(),
                .seq_cst,
                .seq_cst,
            ) == null) {
                if (handmade.beginTaskWithMemory(self.transient_state, false)) |task| {
                    const info = asset.hha.info.sound;

                    var size = AssetMemorySize{};
                    size.section = info.sample_count * @sizeOf(i16);
                    size.data = info.channel_count * size.section;
                    size.total = size.data + @sizeOf(AssetMemoryHeader);

                    asset.header = @ptrCast(@alignCast(self.acquireAssetMemory(shared.align16(size.total), id.value)));
                    const sound = &asset.header.?.data.sound;

                    sound.sample_count = info.sample_count;
                    sound.channel_count = info.channel_count;
                    const channel_size = size.section;

                    const memory: *anyopaque = @ptrCast(@as([*]AssetMemoryHeader, @ptrCast(asset.header)) + 1);
                    var sound_at: [*]i16 = @ptrCast(@alignCast(memory));
                    var channel_index: u32 = 0;
                    while (channel_index < sound.channel_count) : (channel_index += 1) {
                        sound.samples[channel_index] = sound_at;
                        sound_at += channel_size;
                    }

                    var work: *LoadAssetWork = task.arena.pushStruct(LoadAssetWork, null);
                    work.task = task;
                    work.asset = asset;
                    work.handle = self.getFileHandleFor(asset.file_index);
                    work.offset = asset.hha.data_offset;
                    work.size = size.data;
                    work.destination = memory;
                    work.finalize_operation = .None;
                    work.final_state = AssetState.Loaded.toInt();

                    shared.platform.addQueueEntry(self.transient_state.low_priority_queue, doLoadAssetWork, work);
                } else {
                    @atomicStore(u32, &asset.state, AssetState.Unloaded.toInt(), .release);
                }
            }
        }
    }

    pub fn getSound(self: *Assets, id: SoundId, generation_id: u32) ?*LoadedSound {
        var result: ?*LoadedSound = null;

        if (self.getAsset(id.value, generation_id)) |header| {
            result = &header.data.sound;
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

        if (self.getFirstAsset(type_id)) |slot_id| {
            result = SoundId{ .value = slot_id };
        }

        return result;
    }

    pub fn getRandomSound(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?SoundId {
        var result: ?SoundId = null;

        if (self.getRandomAsset(type_id, series)) |slot_id| {
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

        if (self.getBestMatchAsset(type_id, match_vector, weight_vector)) |slot_id| {
            result = SoundId{ .value = slot_id };
        }

        return result;
    }

    pub fn loadFont(
        self: *Assets,
        opt_id: ?FontId,
        immediate: bool,
    ) void {
        var timed_block = TimedBlock.beginFunction(@src(), .LoadFont);
        defer timed_block.end();

        if (opt_id) |id| {
            var asset = &self.assets[id.value];
            if (id.isValid()) {
                if (@cmpxchgStrong(
                    u32,
                    &asset.state,
                    AssetState.Unloaded.toInt(),
                    AssetState.Queued.toInt(),
                    .seq_cst,
                    .seq_cst,
                ) == null) {
                    var opt_task: ?*shared.TaskWithMemory = null;

                    if (!immediate) {
                        opt_task = handmade.beginTaskWithMemory(self.transient_state, false);
                    }

                    if (immediate or opt_task != null) {
                        const info: HHAFont = asset.hha.info.font;

                        const horizontal_advance_size: u32 = @sizeOf(f32) * info.glyph_count * info.glyph_count;
                        const glyphs_size: u32 = info.glyph_count * @sizeOf(HHAFontGlyph);
                        const unicode_map_size: u32 = @sizeOf(u16) * info.one_past_highest_code_point;
                        const size_data: u32 = glyphs_size + horizontal_advance_size;
                        const size_total: u32 = size_data + @sizeOf(AssetMemoryHeader) + unicode_map_size;

                        asset.header = self.acquireAssetMemory(shared.align16(size_total), id.value);

                        var font: *LoadedFont = @ptrCast(@alignCast(&asset.header.?.data.font));
                        font.bitmap_id_offset = self.getFile(asset.file_index).font_bitmap_id_offset;
                        font.glyphs = @ptrCast(@as([*]AssetMemoryHeader, @ptrCast(asset.header)) + 1);
                        font.horizontal_advance =
                            @ptrCast(@alignCast(@as([*]u8, @ptrCast(font.glyphs)) + glyphs_size));
                        font.unicode_map =
                            @ptrCast(@alignCast(@as([*]u8, @ptrCast(font.horizontal_advance)) + horizontal_advance_size));

                        shared.zeroSize(unicode_map_size, @ptrCast(font.unicode_map));

                        var work = LoadAssetWork{
                            .task = undefined,
                            .asset = asset,
                            .handle = self.getFileHandleFor(asset.file_index),
                            .offset = asset.hha.data_offset,
                            .size = size_data,
                            .destination = @ptrCast(font.glyphs),
                            .finalize_operation = .Font,
                            .final_state = AssetState.Loaded.toInt(),
                        };

                        if (opt_task) |task| {
                            work.task = task;

                            const task_work: *LoadAssetWork = task.arena.pushStruct(
                                LoadAssetWork,
                                ArenaPushParams.noClear(),
                            );
                            task_work.* = work;
                            shared.platform.addQueueEntry(
                                self.transient_state.low_priority_queue,
                                doLoadAssetWork,
                                task_work,
                            );
                        } else {
                            doLoadAssetWorkDirectly(&work);
                        }
                    } else {
                        @atomicStore(u32, &asset.state, AssetState.Unloaded.toInt(), .release);
                    }
                } else if (immediate) {
                    // The asset is already queued on another thread, wait until that asset loading is completed.
                    const state: *volatile u32 = &asset.state;
                    while (state.* == AssetState.Queued.toInt()) {}
                }
            }
        }
    }

    pub fn prefetchFont(
        self: *Assets,
        opt_id: ?FontId,
    ) void {
        self.loadFont(opt_id);
    }

    pub fn getFont(self: *Assets, id: FontId, generation_id: u32) ?*LoadedFont {
        var result: ?*LoadedFont = null;

        if (self.getAsset(id.value, generation_id)) |header| {
            result = &header.data.font;
        }

        // var fake_font = LoadedFont{};
        // result = &fake_font;

        return result;
    }

    pub fn getFontInfo(self: *Assets, id: FontId) *HHAFont {
        std.debug.assert(id.value <= self.asset_count);
        return &self.assets[id.value].hha.info.font;
    }

    pub fn getBestMatchFont(
        self: *Assets,
        type_id: AssetTypeId,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?FontId {
        var result: ?FontId = null;

        if (self.getBestMatchAsset(type_id, match_vector, weight_vector)) |slot_id| {
            result = FontId{ .value = slot_id };
        }

        // result = FontId{ .value = 1 };

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
    handle: u32 = 0,

    pub fn getPitch(self: *LoadedSound) i16 {
        return self.width;
    }
};

pub const LoadedSound = extern struct {
    samples: [2]?[*]i16 = undefined,
    sample_count: u32 = undefined,
    channel_count: u32 = undefined,
};

pub const LoadedFont = extern struct {
    glyphs: [*]HHAFontGlyph,
    horizontal_advance: [*]f32,
    bitmap_id_offset: u32,
    unicode_map: [*]u16,

    pub fn getGlyphFromCodePoint(self: *LoadedFont, info: *HHAFont, code_point: u32) u32 {
        var result: u32 = 0;

        if (code_point < info.one_past_highest_code_point) {
            result = self.unicode_map[code_point];
            std.debug.assert(result < info.glyph_count);
        }

        return result;
    }

    pub fn getHorizontalAdvanceForPair(self: *LoadedFont, info: *HHAFont, desired_prev_code_point: u32, desired_code_point: u32) f32 {
        const prev_glyph = self.getGlyphFromCodePoint(info, desired_prev_code_point);
        const glyph = self.getGlyphFromCodePoint(info, desired_code_point);

        const result = self.horizontal_advance[prev_glyph * info.glyph_count + glyph];

        return result;
    }

    pub fn getBitmapForGlyph(self: *LoadedFont, info: *HHAFont, assets: *Assets, desired_code_point: u32) ?file_formats.BitmapId {
        _ = assets;

        const glyph = self.getGlyphFromCodePoint(info, desired_code_point);
        var result = self.glyphs[glyph].bitmap;
        result.value += self.bitmap_id_offset;

        return result;
    }
};

const FinalizeLoadAssetOperation = enum(u8) {
    None,
    Font,
};

const LoadAssetWork = struct {
    task: *shared.TaskWithMemory,
    asset: *Asset,

    handle: *PlatformFileHandle = undefined,
    offset: u64,
    size: u64,
    destination: *anyopaque,

    finalize_operation: FinalizeLoadAssetOperation,
    final_state: u32,
};

fn doLoadAssetWorkDirectly(
    work: *LoadAssetWork,
) callconv(.C) void {
    var timed_block = TimedBlock.beginFunction(@src(), .LoadAssetWorkDirectly);
    defer timed_block.end();

    shared.platform.readDataFromFile(work.handle, work.offset, work.size, work.destination);

    if (shared.platform.noFileErrors(work.handle)) {
        switch (work.finalize_operation) {
            .None => {
                // Nothing to do.
            },
            .Font => {
                const font: *LoadedFont = &work.asset.header.?.data.font;
                const info: *HHAFont = &work.asset.hha.info.font;

                var glyph_index: u32 = 1;
                while (glyph_index < info.glyph_count) : (glyph_index += 1) {
                    const glyph: *HHAFontGlyph = &font.glyphs[glyph_index];

                    std.debug.assert(glyph.unicode_code_point < info.one_past_highest_code_point);
                    std.debug.assert(@as(u16, @intCast(glyph_index)) == glyph_index);
                    font.unicode_map[glyph.unicode_code_point] = @intCast(glyph_index);
                }
            },
        }
    }

    if (!shared.platform.noFileErrors(work.handle)) {
        shared.zeroSize(work.size, @ptrCast(work.destination));
    }

    work.asset.state = work.final_state;
}

fn doLoadAssetWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    const work: *LoadAssetWork = @ptrCast(@alignCast(data));

    doLoadAssetWorkDirectly(work);

    handmade.endTaskWithMemory(work.task);
}
