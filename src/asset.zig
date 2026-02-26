const shared = @import("shared.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const stream = @import("stream.zig");
const renderer = @import("renderer.zig");
const png = @import("png.zig");
const handmade = @import("handmade.zig");
const intrinsics = @import("intrinsics.zig");
const file_formats = shared.file_formats;
const file_formats_v0 = shared.file_formats_v0;
const debug_interface = @import("debug_interface.zig");
const std = @import("std");
const gl = @import("renderer_opengl.zig").gl;

// Build options.
const INTERNAL = shared.INTERNAL;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const TransientState = shared.TransientState;
const String = shared.String;
const Buffer = shared.Buffer;
const Stream = stream.Stream;
const MemoryArena = memory.MemoryArena;
const MemoryIndex = memory.MemoryIndex;
const ArenaPushParams = memory.ArenaPushParams;
const ArenaBootstrapParams = memory.ArenaBootstrapParams;
const Platform = shared.Platform;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAssetType = file_formats.HHAAssetType;
const HHAAsset = file_formats.HHAAsset;
const HHAAnnotation = file_formats.HHAAnnotation;
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;
const HHAFont = file_formats.HHAFont;
const HHAFontGlyph = file_formats.HHAFontGlyph;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const FontId = file_formats.FontId;
const PlatformFileHandle = shared.PlatformFileHandle;
const PlatformFileInfo = shared.PlatformFileInfo;
const PlatformMemoryBlock = shared.PlatformMemoryBlock;
const TimedBlock = debug_interface.TimedBlock;
const TextureOp = renderer.TextureOp;

pub const AssetTypeId = file_formats_v0.AssetTypeIdV0;
pub const AssetTagId = file_formats.AssetTagId;
pub const ASSET_TYPE_ID_COUNT = file_formats_v0.ASSET_TYPE_ID_COUNT;
const ASSET_IMPORT_GRID_MAX = 8;
const HHA_VERSION = file_formats.HHA_VERSION;
const HHA_MAGIC_VALUE = file_formats.HHA_MAGIC_VALUE;

const ImportGridTag = struct {
    type_id: AssetTypeId,
    first_tag_index: u32,
    one_past_last_tag_index: u32,
};

const ImportGridTags = struct {
    name: String = .empty,
    description: String = .empty,
    author: String = .empty,
    tags: [ASSET_IMPORT_GRID_MAX][ASSET_IMPORT_GRID_MAX]ImportGridTag,
};

const Asset = struct {
    state: u32 = 0,
    header: ?*AssetMemoryHeader,

    hha: HHAAsset,
    annotation: HHAAnnotation,

    file_index: u32,
    asset_index_in_file: u32,

    next_of_type: u32,
};

const AssetHeaderType = enum(u32) {
    None,
    Bitmap,
    Sound,
    Font,
};

// TODO. At some point we should move to fixed size blocks, perhaps one for cutscene plates and one for in-game
// artworks, like a 64x64, 1024x1024, and 2048x1024 grouping.
pub const AssetMemoryHeader = extern struct {
    next: ?*AssetMemoryHeader,
    previous: ?*AssetMemoryHeader,
    asset_type: AssetHeaderType,
    asset_index: u32,
    total_size: u32,
    generation_id: u32,
    data: extern union {
        bitmap: LoadedBitmap,
        sound: LoadedSound,
        font: LoadedFont,
    },
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
    tag_base: u32,
    asset_base: u32,
    high_water_mark: u64,
    allow_editing: bool,
    modified: bool,

    pub fn retractWaterMark(self: *AssetFile, count: u64, offset: u64, size: u64) bool {
        var result: bool = false;

        if (offset == self.high_water_mark - (count * size)) {
            self.high_water_mark = offset;
            result = true;
        }

        return result;
    }
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

const SourceFile = struct {
    next_in_hash: ?*SourceFile,
    base_name: String,
    file_date: u64,
    file_checksum: u64,

    // Note: [Y][X], asset index in the Assets.assets array.
    asset_indices: [ASSET_IMPORT_GRID_MAX][ASSET_IMPORT_GRID_MAX]u32 =
        [1][ASSET_IMPORT_GRID_MAX]u32{[1]u32{0} ** ASSET_IMPORT_GRID_MAX} ** ASSET_IMPORT_GRID_MAX,

    errors: Stream,

    pub fn getOrCreateFromHashValue(assets: *Assets, unmodded_hash_value: u32, base_name: [*:0]const u8) *SourceFile {
        const hash_value: u32 = @mod(unmodded_hash_value, @as(u32, @intCast(assets.source_file_hash.len)));

        var match: ?*SourceFile = null;
        var opt_source_file: ?*SourceFile = assets.source_file_hash[hash_value];
        while (opt_source_file) |source_file| : (opt_source_file = source_file.next_in_hash) {
            if (shared.stringsAreEqual(@ptrCast(source_file.base_name.data), base_name)) {
                match = source_file;
                break;
            }
        }

        if (match == null) {
            match = assets.non_restored_memory.pushStruct(SourceFile, .aligned(@alignOf(SourceFile), true));
            match.?.base_name = assets.non_restored_memory.pushString(base_name);
            match.?.next_in_hash = assets.source_file_hash[hash_value];
            assets.source_file_hash[hash_value] = match;

            match.?.errors = .onDemandMemoryStream(&assets.non_restored_memory, null);
        }

        return match.?;
    }

    pub fn getOrCreateFromDate(assets: *Assets, base_name: [*:0]u8, file_date: u64, file_checksum: u64) *SourceFile {
        var result: *SourceFile = .getOrCreateFromHashValue(assets, shared.stringHashOfZ(base_name), base_name);
        if (result.file_date == 0 or result.file_date > file_date) {
            result.file_date = file_date;
            result.file_checksum = file_checksum;
        }
        return result;
    }
};

pub const Assets = struct {
    non_restored_memory: MemoryArena,
    texture_op_queue: *shared.PlatformTextureOpQueue,

    transient_state: *TransientState,

    memory_sentinel: AssetMemoryBlock,

    loaded_asset_sentinel: AssetMemoryHeader,

    tag_range: [ASSET_TYPE_ID_COUNT]f32 = [1]f32{1000000} ** ASSET_TYPE_ID_COUNT,

    file_count: u32,
    files: [*]AssetFile,
    default_append_hha_index: u32,

    max_tag_count: u32,
    tag_count: u32,
    tags: [*]HHATag,

    max_asset_count: u32,
    asset_count: u32,
    assets: [*]Asset,

    first_asset_of_type: [ASSET_TYPE_ID_COUNT]u32,

    source_file_hash: [256]?*SourceFile = [1]?*SourceFile{null} ** 256,
    direction_tag: [4]u32,

    pub fn allocate(
        memory_size: MemoryIndex,
        transient_state: *shared.TransientState,
        texture_op_queue: *shared.PlatformTextureOpQueue,
    ) *Assets {
        TimedBlock.beginFunction(@src(), .AllocateGameAssets);
        defer TimedBlock.endFunction(@src(), .AllocateGameAssets);

        var assets = memory.bootstrapPushStruct(
            Assets,
            "non_restored_memory",
            ArenaBootstrapParams.nonRestored(),
            ArenaPushParams.aligned(@alignOf(Assets), true),
        );
        var arena: *MemoryArena = &assets.non_restored_memory;

        assets.texture_op_queue = texture_op_queue;
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

        assets.tag_range[@intFromEnum(AssetTagId.FacingDirection)] = math.TAU32;

        assets.tag_count = 1;
        assets.asset_count = 1;

        // Load asset headers.
        {
            var file_group = shared.platform.getAllFilesOfTypeBegin(.AssetFile);
            defer shared.platform.getAllFilesOfTypeEnd(&file_group);

            assets.file_count = file_group.file_count + 1;
            assets.files = arena.pushArray(assets.file_count, AssetFile, null);

            var open_flags: u32 = @intFromEnum(shared.OpenFileModeFlags.Read);
            if (INTERNAL) {
                open_flags |= @intFromEnum(shared.OpenFileModeFlags.Write);
            }

            var file_index: u32 = 1;
            var opt_file_info: ?*PlatformFileInfo = file_group.first_file_info;
            while (opt_file_info) |file_info| : (opt_file_info = file_info.next) {
                std.debug.assert(file_index < assets.file_count);
                const file: *AssetFile = &assets.files[file_index];
                defer file_index += 1;

                const file_handle = shared.platform.openFile(&file_group, file_info, open_flags);
                file.tag_base = assets.tag_count;
                file.asset_base = assets.asset_count - 1;
                file.handle = file_handle;

                shared.platform.readDataFromFile(&file.handle, 0, @sizeOf(HHAHeader), &file.header);

                if (file.header.magic_value != HHA_MAGIC_VALUE) {
                    shared.platform.fileError(&file.handle, "HHA file has an invalid magic value.");
                }

                if (file.header.version > HHA_VERSION) {
                    shared.platform.fileError(&file.handle, "HHA file is of a later version.");
                }

                if (shared.platform.noFileErrors(&file.handle)) {
                    // The first asset and tag slot in every HHA is a null,
                    // so we don't count it as something we will need space for.
                    if (file.header.tag_count > 0) {
                        assets.tag_count += (file.header.tag_count - 1);
                    }
                    if (file.header.asset_count > 0) {
                        assets.asset_count += (file.header.asset_count - 1);
                    }
                } else {
                    std.debug.assert(true);
                }

                file.high_water_mark = file_info.file_size;
                while (file.retractWaterMark(file.header.tag_count, file.header.tags, @sizeOf(HHATag)) or
                    file.retractWaterMark(file.header.asset_count, file.header.annotations, @sizeOf(HHAAnnotation)) or
                    file.retractWaterMark(file.header.asset_count, file.header.assets, @sizeOf(HHAAsset)))
                {
                    // Do nothing
                }

                if (INTERNAL) {
                    if (shared.stringsAreEqual(file_info.base_name, "local")) {
                        file.allow_editing = true;
                        assets.default_append_hha_index = file_index;
                    }
                }
            }
        }

        assets.max_asset_count = assets.asset_count;
        assets.max_tag_count = assets.tag_count;
        if (INTERNAL) {
            assets.max_asset_count += 65536;
            assets.max_tag_count += 65536;
        }
        assets.assets = arena.pushArray(assets.max_asset_count, Asset, ArenaPushParams.aligned(@alignOf(Asset), true));
        assets.tags = arena.pushArray(assets.max_tag_count, HHATag, null);

        memory.zeroStruct(HHATag, @ptrCast(assets.tags));

        var asset_count: u32 = 0;
        memory.zeroStruct(Asset, @ptrCast(assets.assets + asset_count));
        asset_count += 1;

        var null_annotation: HHAAnnotation = .{};

        // Load assets.
        var file_index: u32 = 1;
        while (file_index < assets.file_count) : (file_index += 1) {
            const file: *AssetFile = &assets.files[file_index];

            if (shared.platform.noFileErrors(&file.handle)) {
                if (file.header.tag_count > 0) {
                    const tag_array_size = @sizeOf(HHATag) * (file.header.tag_count - 1);
                    shared.platform.readDataFromFile(
                        &file.handle,
                        file.header.tags + @sizeOf(HHATag),
                        tag_array_size,
                        assets.tags + file.tag_base,
                    );
                }

                if (file.header.asset_count > 0) {
                    const file_asset_count: u32 = file.header.asset_count - 1;

                    const temp_mem = transient_state.arena.beginTemporaryMemory();
                    defer transient_state.arena.endTemporaryMemory(temp_mem);
                    const hha_asset_array: [*]HHAAsset =
                        transient_state.arena.pushArray(file_asset_count, HHAAsset, null);
                    var hha_annotation_array: ?[*]HHAAnnotation =
                        transient_state.arena.pushArray(file_asset_count, HHAAnnotation, null);

                    shared.platform.readDataFromFile(
                        &file.handle,
                        file.header.assets + @sizeOf(HHAAsset),
                        file_asset_count * @sizeOf(HHAAsset),
                        hha_asset_array,
                    );

                    if (file.header.annotations != 0) {
                        shared.platform.readDataFromFile(
                            &file.handle,
                            file.header.annotations + @sizeOf(HHAAnnotation),
                            file_asset_count * @sizeOf(HHAAnnotation),
                            hha_annotation_array.?,
                        );
                    } else {
                        hha_annotation_array = null;
                    }

                    // Rebase tag indexes.
                    var asset_index: u32 = 0;
                    while (asset_index < file_asset_count) : (asset_index += 1) {
                        const hha_asset: [*]HHAAsset = hha_asset_array + asset_index;
                        var hha_annotation: *HHAAnnotation = @ptrCast(&null_annotation);
                        if (hha_annotation_array) |annotations| {
                            hha_annotation = &annotations[asset_index];
                        }

                        std.debug.assert(asset_count < assets.asset_count);
                        const global_asset_index: u32 = asset_count;
                        asset_count += 1;
                        const asset: *Asset = &assets.assets[global_asset_index];

                        asset.file_index = file_index;
                        asset.asset_index_in_file = global_asset_index - file.asset_base;
                        asset.hha = hha_asset[0];
                        asset.annotation = hha_annotation.*;

                        if (asset.hha.first_tag_index == 0) {
                            asset.hha.one_past_last_tag_index = 0;
                        } else {
                            asset.hha.first_tag_index += (file.tag_base - 1);
                            asset.hha.one_past_last_tag_index += (file.tag_base - 1);
                        }

                        if (file.allow_editing) {
                            // TODO: This is very inefficent, and we could modify the file format to keep a separate
                            // array of file names (or we could has file names based on their location in the file as
                            // well, and only read them once). But at the moment we just read the source name directly,
                            // because we don't care how long it takes in the "editing" mode of the game anyway.

                            const source_file_name_count: u32 = hha_annotation.source_file_base_name_count;
                            const source_file_name: [*:0]u8 =
                                @ptrCast(transient_state.arena.pushArray(source_file_name_count + 1, u8, null));
                            shared.platform.readDataFromFile(
                                &file.handle,
                                hha_annotation.source_file_base_name_offset,
                                source_file_name_count,
                                source_file_name,
                            );
                            source_file_name[source_file_name_count] = 0;

                            const grid_x: u32 = hha_annotation.sprite_sheet_x;
                            const grid_y: u32 = hha_annotation.sprite_sheet_y;
                            const source_file: *SourceFile = .getOrCreateFromDate(
                                assets,
                                source_file_name,
                                hha_annotation.source_file_date,
                                hha_annotation.source_file_checksum,
                            );
                            const grid_asset_index: *u32 = &source_file.asset_indices[grid_y][grid_x];
                            if (grid_asset_index.* == 0) {
                                grid_asset_index.* = global_asset_index;
                            } else {
                                const conflict: *Asset = &assets.assets[grid_asset_index.*];
                                stream.output(
                                    &source_file.errors,
                                    @src(),
                                    "{s}({d},{d}): Asset {d} and {d} occupy same slot in spritesheet and cannot be edited properly.\n",
                                    .{ source_file_name, grid_x, grid_y, asset.asset_index_in_file, conflict.asset_index_in_file },
                                );
                            }
                        }

                        var type_id: AssetTypeId = .None;
                        var asset_tag_index: u32 = asset.hha.first_tag_index;
                        while (asset_tag_index < asset.hha.one_past_last_tag_index) : (asset_tag_index += 1) {
                            if (assets.tags[asset_tag_index].id == .BasicCategory) {
                                type_id = @enumFromInt(@as(u32, @intFromFloat(assets.tags[asset_tag_index].value)));
                            }
                        }

                        assets.setAssetType(global_asset_index, type_id);
                    }
                }
            }
        }

        std.debug.assert(asset_count == assets.asset_count);

        if (INTERNAL) {
            var direction_tag_index: u32 = 0;
            while (direction_tag_index < assets.direction_tag.len) : (direction_tag_index += 1) {
                assets.direction_tag[direction_tag_index] = assets.reserveTag(2);
                var tag: [*]HHATag = assets.tags + assets.direction_tag[direction_tag_index];
                tag[0].id = AssetTagId.FacingDirection;
                tag[0].value = math.TAU32 / @as(f32, @floatFromInt(assets.direction_tag.len));
                tag += 1;
                tag[0].id = AssetTagId.BasicCategory;
                tag[0].value = @floatFromInt(@as(u32, @intFromEnum(AssetTypeId.Hand)));
            }

            checkForArtChanges(assets);
        }

        return assets;
    }

    pub fn beginGeneration(self: *Assets) u32 {
        self.beginAssetLock();
        defer self.endAssetLock();

        std.debug.assert(self.transient_state.in_flight_generation_count < self.transient_state.in_flight_generations.len);

        const result = self.transient_state.next_generation_id;
        self.transient_state.next_generation_id +%= 1;

        self.transient_state.in_flight_generations[self.transient_state.in_flight_generation_count] = result;
        self.transient_state.in_flight_generation_count += 1;

        return result;
    }

    pub fn endGeneration(self: *Assets, generation_id: u32) void {
        self.beginAssetLock();
        defer self.endAssetLock();

        var index: u32 = 0;
        while (index < self.transient_state.in_flight_generation_count) : (index += 1) {
            if (self.transient_state.in_flight_generations[index] == generation_id) {
                self.transient_state.in_flight_generation_count -= 1;
                self.transient_state.in_flight_generations[index] = self.transient_state.in_flight_generations[self.transient_state.in_flight_generation_count];
            }
        }
    }

    fn generationHasCompleted(self: *Assets, check_id: u32) bool {
        var result = true;

        var index: u32 = 0;
        while (index < self.transient_state.in_flight_generation_count) : (index += 1) {
            if (self.transient_state.in_flight_generations[index] == check_id) {
                result = false;
                break;
            }
        }

        return result;
    }

    fn insertBlock(_: *Assets, previous: *AssetMemoryBlock, size: u64, block_memory: *anyopaque) *AssetMemoryBlock {
        std.debug.assert(size > @sizeOf(AssetMemoryBlock));
        var block: *AssetMemoryBlock = @ptrCast(@alignCast(block_memory));
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
            if (@cmpxchgStrong(u32, &self.transient_state.operation_lock, 0, 1, .seq_cst, .seq_cst) == null) {
                break;
            }
        }
    }

    fn endAssetLock(self: *Assets) void {
        self.transient_state.operation_lock = 0;
    }

    fn acquireAssetMemory(self: *Assets, size: u32, new_asset_index: u32, asset_type: AssetHeaderType) ?*AssetMemoryHeader {
        TimedBlock.beginFunction(@src(), .AcquireAssetMemory);
        defer TimedBlock.endFunction(@src(), .AcquireAssetMemory);

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

                        if (header.?.asset_type == .Bitmap) {
                            const op = TextureOp{
                                .is_allocate = false,
                                .op = .{
                                    .deallocate = .{
                                        .handle = header.?.data.bitmap.texture_handle,
                                    },
                                },
                            };
                            addOp(self.texture_op_queue, &op);
                        }

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
            header.asset_type = asset_type;
            header.asset_index = new_asset_index;
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
        TimedBlock.beginFunction(@src(), .GetFirstAsset);
        defer TimedBlock.endFunction(@src(), .GetFirstAsset);

        const result: ?u32 = self.first_asset_of_type[type_id.toInt()];

        return result;
    }

    // pub fn getRandomAsset(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?u32 {
    //     TimedBlock.beginFunction(@src(), .GetRandomAsset);
    //     defer TimedBlock.endFunction(@src(), .GetRandomAsset);
    //
    //     var result: ?u32 = null;
    //     const asset_type: *AssetType = &self.asset_types[type_id.toInt()];
    //
    //     if (asset_type.first_asset_index != asset_type.one_past_last_asset_index) {
    //         const count: u32 = asset_type.one_past_last_asset_index - asset_type.first_asset_index;
    //         const choice = series.randomChoice(count);
    //         result = asset_type.first_asset_index + choice;
    //     }
    //
    //     return result;
    // }

    pub fn getBestMatchAsset(
        self: *Assets,
        type_id: AssetTypeId,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?u32 {
        TimedBlock.beginFunction(@src(), .GetBestMatchAsset);
        defer TimedBlock.endFunction(@src(), .GetBestMatchAsset);

        var result: ?u32 = null;
        var best_diff: f32 = std.math.floatMax(f32);

        var asset_index: u32 = self.first_asset_of_type[type_id.toInt()];
        while (asset_index != 0) {
            const asset = self.assets[asset_index];

            var total_weighted_diff: f32 = 0;
            var tag_index: u32 = asset.hha.first_tag_index;
            while (tag_index < asset.hha.one_past_last_tag_index) : (tag_index += 1) {
                const tag: *HHATag = &self.tags[tag_index];

                const a: f32 = match_vector.e[tag.id.toInt()];
                const b: f32 = tag.value;
                const d0 = intrinsics.absoluteValue(a - b);
                const d1 = intrinsics.absoluteValue((a - (self.tag_range[tag.id.toInt()] * intrinsics.signOfF32(a))) - b);
                const difference = @min(d0, d1);

                const weighted = weight_vector.e[tag.id.toInt()] * intrinsics.absoluteValue(difference);
                total_weighted_diff += weighted;
            }

            if (best_diff > total_weighted_diff) {
                best_diff = total_weighted_diff;
                result = asset_index;
            }

            asset_index = asset.next_of_type;
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
        TimedBlock.beginFunction(@src(), .LoadBitmap);
        defer TimedBlock.endFunction(@src(), .LoadBitmap);

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
                        const width = types.safeTruncateUInt32ToUInt16(info.dim[0]);
                        const height = types.safeTruncateUInt32ToUInt16(info.dim[1]);
                        size.section = 4 * width;
                        size.data = size.section * height;
                        size.total = size.data + @sizeOf(AssetMemoryHeader);

                        asset.header = self.acquireAssetMemory(types.align16(size.total), id.value, .Bitmap);

                        var bitmap: *LoadedBitmap = @ptrCast(@alignCast(&asset.header.?.data.bitmap));

                        bitmap.alignment_percentage = Vector2.new(info.alignment_percentage[0], info.alignment_percentage[1]);
                        bitmap.width_over_height = @as(f32, @floatFromInt(info.dim[0])) / @as(f32, @floatFromInt(info.dim[1]));
                        bitmap.width = width;
                        bitmap.height = height;
                        bitmap.pitch = types.safeTruncateUInt32ToUInt16(size.section);
                        bitmap.memory = @ptrCast(@as([*]AssetMemoryHeader, @ptrCast(asset.header)) + 1);
                        bitmap.texture_handle = undefined;

                        var work = LoadAssetWork{
                            .task = undefined,
                            .asset = asset,
                            .handle = self.getFileHandleFor(asset.file_index),
                            .offset = asset.hha.data_offset,
                            .size = size.data,
                            .destination = @ptrCast(bitmap.memory),
                            .finalize_operation = .Bitmap,
                            .final_state = AssetState.Loaded.toInt(),
                            .texture_op_queue = self.texture_op_queue,
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

    // pub fn getRandomBitmap(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?BitmapId {
    //     var result: ?BitmapId = null;
    //
    //     if (self.getRandomAsset(type_id, series)) |slot_id| {
    //         result = BitmapId{ .value = slot_id };
    //     }
    //
    //     return result;
    // }

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
        TimedBlock.beginFunction(@src(), .LoadSound);
        defer TimedBlock.endFunction(@src(), .LoadSound);

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

                    asset.header = @ptrCast(@alignCast(self.acquireAssetMemory(types.align16(size.total), id.value, .Sound)));
                    const sound = &asset.header.?.data.sound;

                    sound.sample_count = info.sample_count;
                    sound.channel_count = info.channel_count;
                    const channel_size = size.section;

                    const sound_memory: *anyopaque = @ptrCast(@as([*]AssetMemoryHeader, @ptrCast(asset.header)) + 1);
                    var sound_at: [*]i16 = @ptrCast(@alignCast(sound_memory));
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
                    work.destination = sound_memory;
                    work.finalize_operation = .None;
                    work.final_state = AssetState.Loaded.toInt();
                    work.texture_op_queue = null;

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

    // pub fn getRandomSound(self: *Assets, type_id: AssetTypeId, series: *random.Series) ?SoundId {
    //     var result: ?SoundId = null;
    //
    //     if (self.getRandomAsset(type_id, series)) |slot_id| {
    //         result = SoundId{ .value = slot_id };
    //     }
    //
    //     return result;
    // }

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
        TimedBlock.beginFunction(@src(), .LoadFont);
        defer TimedBlock.endFunction(@src(), .LoadFont);

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

                        asset.header = self.acquireAssetMemory(types.align16(size_total), id.value, .Font);

                        var font: *LoadedFont = @ptrCast(@alignCast(&asset.header.?.data.font));
                        font.bitmap_id_offset = self.getFile(asset.file_index).asset_base;
                        font.glyphs = @ptrCast(@as([*]AssetMemoryHeader, @ptrCast(asset.header)) + 1);
                        font.horizontal_advance =
                            @ptrCast(@alignCast(@as([*]u8, @ptrCast(font.glyphs)) + glyphs_size));
                        font.unicode_map =
                            @ptrCast(@alignCast(@as([*]u8, @ptrCast(font.horizontal_advance)) + horizontal_advance_size));

                        memory.zeroSize(unicode_map_size, @ptrCast(font.unicode_map));

                        var work = LoadAssetWork{
                            .task = undefined,
                            .asset = asset,
                            .handle = self.getFileHandleFor(asset.file_index),
                            .offset = asset.hha.data_offset,
                            .size = size_data,
                            .destination = @ptrCast(font.glyphs),
                            .finalize_operation = .Font,
                            .final_state = AssetState.Loaded.toInt(),
                            .texture_op_queue = null,
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

    pub fn reserveTag(self: *Assets, tag_count: u32) u32 {
        var result: u32 = 0;

        if ((self.tag_count + tag_count) < self.max_tag_count) {
            result = self.tag_count;
            self.tag_count += tag_count;
        }

        return result;
    }

    pub fn reserveAsset(self: *Assets) u32 {
        var result: u32 = 0;

        if (self.asset_count < self.max_asset_count) {
            result = self.asset_count;
            self.asset_count += 1;
        }

        return result;
    }

    pub fn reserveData(self: *Assets, file: *AssetFile, data_size: u32) u64 {
        _ = self;
        const result: u64 = file.high_water_mark;
        file.modified = true;
        file.high_water_mark += data_size;
        return result;
    }

    fn writeAssetData(file: *AssetFile, data_offset: u64, data_size: u32, data: [*]u32) void {
        file.modified = true;
        shared.platform.writeDataToFile(&file.handle, data_offset, data_size, data);
    }

    pub fn writeAssetString(
        self: *Assets,
        file: *AssetFile,
        source: String,
        count: *align(1) u32,
        offset: *align(1) u64,
    ) void {
        if (source.count > count.*) {
            offset.* = self.reserveData(file, @intCast(source.count));
        }

        count.* = @intCast(source.count);
        writeAssetData(file, offset.*, count.*, @ptrCast(@alignCast(source.data)));
    }

    pub fn writeModificationsToHHA(self: *Assets, file_index: u32, temp_arena: *MemoryArena) void {
        const file: *AssetFile = &self.files[file_index];

        std.debug.assert(file.allow_editing);
        file.modified = false;

        var asset_count: u32 = 1; // First asset entry is skipped as the null asset!
        var tag_count: u32 = 1; // First tag entry is skipped as the null tag!
        var asset_index: u32 = 0;
        while (asset_index < self.asset_count) : (asset_index += 1) {
            const asset: *Asset = &self.assets[asset_index];
            if (asset.file_index == file_index) {
                asset_count += 1;
                tag_count += (asset.hha.one_past_last_tag_index - asset.hha.first_tag_index);
            }
        }

        const tag_array_size: u64 = tag_count * @sizeOf(HHATag);
        const assets_array_size: u64 = asset_count * @sizeOf(HHAAsset);
        const annotation_array_size: u64 = asset_count * @sizeOf(HHAAnnotation);

        file.header.tag_count = tag_count;
        file.header.asset_count = asset_count;

        file.header.tags = file.high_water_mark;
        file.header.assets = file.header.tags + tag_array_size;
        file.header.annotations = file.header.assets + assets_array_size;

        const tags: [*]HHATag = temp_arena.pushArray(tag_count, HHATag, null);
        const assets: [*]HHAAsset = temp_arena.pushArray(asset_count, HHAAsset, null);
        const annotations: [*]HHAAnnotation = temp_arena.pushArray(asset_count, HHAAnnotation, null);

        var tag_index_in_file: u32 = 1;
        var asset_index_in_file: u32 = 1;

        var global_asset_index: u32 = 1;
        while (global_asset_index < self.asset_count) : (global_asset_index += 1) {
            const source: *Asset = &self.assets[global_asset_index];
            if (source.file_index == file_index) {
                const dest: *HHAAsset = &assets[asset_index_in_file];
                const dest_annotation: *HHAAnnotation = &annotations[asset_index_in_file];
                source.asset_index_in_file = asset_index_in_file;

                dest_annotation.* = source.annotation;

                dest.* = source.hha;
                dest.first_tag_index = tag_index_in_file;
                var tag_index: u32 = source.hha.first_tag_index;
                while (tag_index < source.hha.one_past_last_tag_index) : (tag_index += 1) {
                    tags[tag_index_in_file] = self.tags[tag_index];
                    tag_index_in_file += 1;
                }
                dest.one_past_last_tag_index = tag_index_in_file;

                asset_index_in_file += 1;
            }
        }

        std.debug.assert(tag_index_in_file == tag_count);
        std.debug.assert(asset_index_in_file == asset_count);

        shared.platform.writeDataToFile(&file.handle, 0, @sizeOf(HHAHeader), &file.header);
        shared.platform.writeDataToFile(&file.handle, file.header.tags, tag_array_size, tags);
        shared.platform.writeDataToFile(&file.handle, file.header.assets, assets_array_size, assets);
        shared.platform.writeDataToFile(&file.handle, file.header.annotations, annotation_array_size, annotations);
    }

    pub fn setAssetType(self: *Assets, asset_index: u32, type_id: AssetTypeId) void {
        if (asset_index != 0 and @intFromEnum(type_id) < @typeInfo(AssetTypeId).@"enum".fields.len) {
            var asset: *Asset = &self.assets[asset_index];
            std.debug.assert(asset.next_of_type == 0);
            asset.next_of_type = self.first_asset_of_type[@intFromEnum(type_id)];
            self.first_asset_of_type[@intFromEnum(type_id)] = asset_index;
        }
    }
};

pub const WritableBitmap = struct {
    pitch: i32 = 0,
};

pub const LoadedBitmap = extern struct {
    memory: ?[*]u8,

    alignment_percentage: Vector2 = Vector2.zero(),
    width_over_height: f32 = 0,
    width: u16 = 0,
    height: u16 = 0,
    pitch: u16 = 0,
    texture_handle: u32 = undefined,

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
    Bitmap,
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

    texture_op_queue: ?*shared.PlatformTextureOpQueue,
};

fn addOp(queue: *shared.PlatformTextureOpQueue, source: *const TextureOp) void {
    queue.mutex.begin();

    std.debug.assert(queue.first_free != null);

    const dest: *TextureOp = queue.first_free.?;
    queue.first_free = dest.next;

    dest.* = source.*;

    std.debug.assert(dest.next == null);

    if (queue.last != null) {
        queue.last.?.next = dest;
        queue.last = dest;
    } else {
        queue.first = dest;
        queue.last = dest;
    }

    queue.mutex.end();
}

fn doLoadAssetWorkDirectly(
    work: *LoadAssetWork,
) callconv(.c) void {
    TimedBlock.beginFunction(@src(), .LoadAssetWorkDirectly);
    defer TimedBlock.endFunction(@src(), .LoadAssetWorkDirectly);

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
            .Bitmap => {
                const bitmap: *LoadedBitmap = &work.asset.header.?.data.bitmap;
                const op: TextureOp = .{
                    .is_allocate = true,
                    .op = .{
                        .allocate = .{
                            .width = bitmap.width,
                            .height = bitmap.height,
                            .data = @ptrCast(bitmap.memory),
                            .result_handle = &bitmap.texture_handle,
                        },
                    },
                };

                addOp(work.texture_op_queue.?, &op);
            },
        }
    }

    if (!shared.platform.noFileErrors(work.handle)) {
        memory.zeroSize(work.size, @ptrCast(work.destination));
    }

    work.asset.state = work.final_state;
}

fn doLoadAssetWork(queue: shared.PlatformWorkQueuePtr, data: *anyopaque) callconv(.c) void {
    _ = queue;

    const work: *LoadAssetWork = @ptrCast(@alignCast(data));

    doLoadAssetWorkDirectly(work);

    handmade.endTaskWithMemory(work.task);
}

fn processTiledImport(
    assets: *Assets,
    grid_tag_array: *ImportGridTags,
    file: *SourceFile,
    image: png.ImageU32,
    temp_arena: *MemoryArena,
) void {
    const border_dimension: u32 = 8;
    const tile_dimension: u32 = 1024;

    const pixel_buffer: [*]u32 = temp_arena.pushArray(tile_dimension * tile_dimension, u32, null);

    const x_count_max: u32 = file.asset_indices[0].len;
    const y_count_max: u32 = file.asset_indices.len;

    var x_count: u32 = image.width / tile_dimension;
    if (x_count > x_count_max) {
        stream.output(&file.errors, @src(), "Tile column count of %u exceeds maximum of %u columns.", .{
            x_count,
            x_count_max,
        });
        x_count = x_count_max;
    }
    var y_count: u32 = image.height / tile_dimension;
    if (y_count > y_count_max) {
        stream.output(&file.errors, @src(), "Tile row count of %u exceeds maximum of %u rows.", .{
            y_count,
            y_count_max,
        });
        y_count = y_count_max;
    }

    var y_index: u32 = 0;
    while (y_index < y_count) : (y_index += 1) {
        var x_index: u32 = 0;
        while (x_index < x_count) : (x_index += 1) {
            const grid_tags: ImportGridTag = grid_tag_array.tags[y_index][x_index];
            var min_x: u32 = std.math.maxInt(u32);
            var max_x: u32 = std.math.minInt(u32);
            var min_y: u32 = std.math.maxInt(u32);
            var max_y: u32 = std.math.minInt(u32);

            {
                var dest_pixel: [*]u32 = pixel_buffer;
                var source_row: [*]u32 = image.pixels.ptr +
                    (y_index * tile_dimension * image.width + x_index * tile_dimension);

                var y: u32 = 0;
                while (y < tile_dimension) : (y += 1) {
                    var source_pixel: [*]u32 = source_row;

                    var x: u32 = 0;
                    while (x < tile_dimension) : (x += 1) {
                        const source_color: u32 = source_pixel[0];
                        source_pixel += 1;

                        if (source_color & 0xff000000 != 0) {
                            min_x = @min(min_x, x);
                            max_x = @max(max_x, x);
                            min_y = @min(min_y, y);
                            max_y = @max(max_y, y);
                        }

                        var color: Color = .unpackColorBGRA(math.swapRedAndBlue(source_color));
                        color = math.sRGB255ToLinear1(color);
                        _ = color.setRGB(color.rgb().scaledTo(color.a()));
                        color = math.linear1ToSRGB255(color);
                        dest_pixel[0] = Color.packColorBGRA(color);
                        dest_pixel += 1;
                    }

                    source_row += image.width;
                }
            }

            if (min_x <= max_x) {
                // There was something in this tile.

                if (min_x < border_dimension) {
                    stream.output(&file.errors, @src(), "Tile %u, &u extends into left %u-pixel border.", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (max_x >= (tile_dimension - border_dimension)) {
                    stream.output(&file.errors, @src(), "Tile %u, &u extends into right %u-pixel border.", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (min_y < border_dimension) {
                    stream.output(&file.errors, @src(), "Tile %u, &u extends into top %u-pixel border.", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (max_y >= (tile_dimension - border_dimension)) {
                    stream.output(&file.errors, @src(), "Tile %u, &u extends into bottom %u-pixel border.", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                var sprite_dimension: u32 = tile_dimension;

                // Downsample by 2x.
                var downsample: u32 = 0;
                while (downsample < 1) : (downsample += 1) {
                    const previous_dimension: u32 = sprite_dimension;
                    sprite_dimension = sprite_dimension / 2;

                    var dest_pixel: [*]u32 = pixel_buffer;
                    var source_pixel0: [*]u32 = pixel_buffer;
                    var source_pixel1: [*]u32 = source_pixel0 + previous_dimension;

                    var y: u32 = 0;
                    while (y < sprite_dimension) : (y += 1) {
                        var x: u32 = 0;
                        while (x < sprite_dimension) : (x += 1) {
                            var pixel_00: Color = .unpackColorBGRA(source_pixel0[0]);
                            source_pixel0 += 1;
                            var pixel_10: Color = .unpackColorBGRA(source_pixel0[0]);
                            source_pixel0 += 1;
                            var pixel_01: Color = .unpackColorBGRA(source_pixel1[0]);
                            source_pixel1 += 1;
                            var pixel_11: Color = .unpackColorBGRA(source_pixel1[0]);
                            source_pixel1 += 1;

                            pixel_00 = math.sRGB255ToLinear1(pixel_00);
                            pixel_10 = math.sRGB255ToLinear1(pixel_10);
                            pixel_01 = math.sRGB255ToLinear1(pixel_01);
                            pixel_11 = math.sRGB255ToLinear1(pixel_11);

                            var color: Color = pixel_00.plus(pixel_10).plus(pixel_01).plus(pixel_11).scaledTo(0.25);

                            color = math.linear1ToSRGB255(color);

                            dest_pixel[0] = Color.packColorBGRA(color);
                            dest_pixel += 1;
                        }

                        source_pixel0 += previous_dimension;
                        source_pixel1 += previous_dimension;
                    }
                }

                if (grid_tags.type_id != .None) {
                    var hha_asset: HHAAsset = .{
                        .info = .{
                            .bitmap = .{
                                .alignment_percentage = .{ 0.5, 0.5 },
                            },
                        },
                    };
                    var asset_index: u32 = file.asset_indices[y_index][x_index];
                    if (asset_index != 0) {
                        const asset: *Asset = &assets.assets[asset_index];
                        hha_asset = asset.hha;
                    } else {
                        asset_index = assets.reserveAsset();
                        assets.setAssetType(asset_index, grid_tags.type_id);
                    }

                    if (asset_index != 0) {
                        const asset_data_size: u32 = 4 * sprite_dimension * sprite_dimension;
                        var asset: *Asset = &assets.assets[asset_index];
                        if (asset.file_index == 0) {
                            asset.file_index = assets.default_append_hha_index;
                        }

                        std.debug.assert(asset.file_index != 0);

                        const asset_file: *AssetFile = &assets.files[asset.file_index];
                        if (hha_asset.data_offset == 0 or hha_asset.data_size < asset_data_size) {
                            hha_asset.data_offset = assets.reserveData(asset_file, asset_data_size);
                        }
                        hha_asset.data_size = asset_data_size;

                        // TODO: Translate the tile index into tags based on the name of this file,
                        // probably using something passed into this routine.
                        // hha_asset.first_tag_index = 0;
                        // hha_asset.one_past_last_tag_index = 0;
                        hha_asset.info.bitmap.dim[0] = sprite_dimension;
                        hha_asset.info.bitmap.dim[1] = sprite_dimension;
                        hha_asset.first_tag_index = grid_tags.first_tag_index;
                        hha_asset.one_past_last_tag_index = grid_tags.one_past_last_tag_index;
                        hha_asset.type = .Bitmap;

                        asset.hha = hha_asset;
                        asset.annotation.source_file_date = file.file_date;
                        asset.annotation.source_file_checksum = file.file_checksum;
                        asset.annotation.sprite_sheet_x = x_index;
                        asset.annotation.sprite_sheet_y = y_index;

                        assets.writeAssetString(
                            asset_file,
                            grid_tag_array.name,
                            &asset.annotation.asset_name_count,
                            &asset.annotation.asset_name_offset,
                        );
                        assets.writeAssetString(
                            asset_file,
                            grid_tag_array.description,
                            &asset.annotation.asset_description_count,
                            &asset.annotation.asset_description_offset,
                        );
                        assets.writeAssetString(
                            asset_file,
                            grid_tag_array.author,
                            &asset.annotation.author_count,
                            &asset.annotation.author_offset,
                        );
                        assets.writeAssetString(
                            asset_file,
                            file.base_name,
                            &asset.annotation.source_file_base_name_count,
                            &asset.annotation.source_file_base_name_offset,
                        );

                        file.asset_indices[y_index][x_index] = asset_index;

                        Assets.writeAssetData(asset_file, hha_asset.data_offset, asset_data_size, pixel_buffer);
                    } else {
                        stream.output(&file.errors, @src(), "Out of asset memory - please restart Handmade Hero!", .{});
                    }
                } else {
                    stream.output(&file.errors, @src(), "Sprite found in what is required to be a blank tile.", .{});
                }
            }
        }
    }
}

fn updateAssetPackageFromPNG(
    assets: *Assets,
    grid_tag_array: *ImportGridTags,
    file: *SourceFile,
    contents: Buffer,
    temp_arena: *MemoryArena,
) bool {
    const content_stream: Stream = .makeReadStream(contents, &file.errors);
    const image = png.parsePNG(temp_arena, content_stream, null);

    // if () {
    processTiledImport(assets, grid_tag_array, file, image, temp_arena);
    // } else {
    //     processFlatImport();
    // }

    return false;
}

pub fn checkForArtChanges(assets: *Assets) void {
    if (assets.default_append_hha_index != 0) {
        var file_group = shared.platform.getAllFilesOfTypeBegin(.PNG);
        defer shared.platform.getAllFilesOfTypeEnd(&file_group);

        // TODO: Do a sweep mark to set all assets to "unseen", then mark each one we see so we can detect
        // when files have been deleted.

        var opt_file_info: ?*PlatformFileInfo = file_group.first_file_info;
        while (opt_file_info) |file_info| : (opt_file_info = file_info.next) {
            var piece_count: u32 = 0;
            var pieces: [3]String = [1]String{.empty} ** 3;

            var anchor: [*]u8 = file_info.base_name;
            var hash_value: u32 = 0;
            var scan: [*]u8 = file_info.base_name;
            while (true) : (scan += 1) {
                if (scan[0] == '_' or scan[0] == 0) {
                    if (piece_count < pieces.len) {
                        var string: *Buffer = &pieces[piece_count];
                        piece_count += 1;
                        string.count = scan - anchor;
                        string.data = anchor;
                    }

                    anchor = scan + 1;
                }

                if (scan[0] == 0) {
                    break;
                }

                shared.updateStringHash(&hash_value, scan[0]);
            }

            const match: *SourceFile = .getOrCreateFromHashValue(assets, hash_value, file_info.base_name);

            if (match.file_date != file_info.file_date) {
                if (shared.stringBufferEquals(pieces[0], "hand")) {
                    var temp_arena: MemoryArena = .{};
                    defer temp_arena.clear();

                    stream.output(&match.errors, @src(), "/**** REIMPORTED ****/\n", .{});

                    var handle: PlatformFileHandle = shared.platform.openFile(
                        &file_group,
                        @constCast(file_info),
                        @intFromEnum(shared.OpenFileModeFlags.Read),
                    );
                    var file_buffer: Buffer = .{
                        .count = file_info.file_size,
                    };

                    file_buffer.data = temp_arena.pushSize(file_buffer.count, null);

                    shared.platform.readDataFromFile(&handle, 0, file_buffer.count, file_buffer.data);
                    shared.platform.closeFile(&handle);

                    // We update this first, because assets that get packed from here on out need to be able to stamp
                    // themselves with the right data.
                    match.file_date = file_info.file_date;
                    match.file_checksum = shared.checksumOf(file_buffer, null);

                    var tags: ImportGridTags = .{ .tags = undefined };

                    var y_index: u32 = 0;
                    while (y_index < ASSET_IMPORT_GRID_MAX) : (y_index += 1) {
                        var x_index: u32 = 0;
                        while (x_index < ASSET_IMPORT_GRID_MAX) : (x_index += 1) {
                            var tag: *ImportGridTag = &tags.tags[y_index][x_index];
                            if (x_index == 0 and y_index < assets.direction_tag.len) {
                                tag.type_id = .Hand;
                                tag.first_tag_index = assets.direction_tag[y_index];
                                tag.one_past_last_tag_index = tag.first_tag_index + 2;
                            }
                        }
                    }

                    _ = updateAssetPackageFromPNG(assets, &tags, match, file_buffer, &temp_arena);
                }
            }
        }

        var file_index: u32 = 1;
        while (file_index < assets.file_count) : (file_index += 1) {
            const file: *AssetFile = @ptrCast(assets.files + file_index);
            if (file.modified) {
                var temp_arena: MemoryArena = .{};
                defer temp_arena.clear();

                assets.writeModificationsToHHA(file_index, &temp_arena);
            }
        }
    }
}
