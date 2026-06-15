const types = @import("types.zig");
const shared = @import("shared.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const stream = @import("stream.zig");
const renderer = @import("renderer.zig");
const import = @import("import.zig");
const handmade = @import("handmade.zig");
const intrinsics = @import("intrinsics.zig");
const file_formats = shared.file_formats;
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

// Build options.
const INTERNAL = shared.INTERNAL;

// Types.
const Vector2u = math.Vector2u;
const String = types.String;
const Stream = stream.Stream;
const MemoryArena = memory.MemoryArena;
const MemoryIndex = memory.MemoryIndex;
const ArenaPushParams = memory.ArenaPushParams;
const ArenaBootstrapParams = memory.ArenaBootstrapParams;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAsset = file_formats.HHAAsset;
const HHAAnnotation = file_formats.HHAAnnotation;
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;
const HHAFont = file_formats.HHAFont;
const HHAFontGlyph = file_formats.HHAFontGlyph;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const FontId = file_formats.FontId;
const AssetBasicCategory = file_formats.AssetBasicCategory;
const PlatformFileHandle = shared.PlatformFileHandle;
const PlatformFileInfo = shared.PlatformFileInfo;
const PlatformFileGroup = shared.PlatformFileGroup;
const TimedBlock = debug_interface.TimedBlock;
const TextureOp = renderer.TextureOp;
const RendererTexture = renderer.RendererTexture;

pub const AssetTagId = file_formats.AssetTagId;
pub const ASSET_CATEGORY_COUNT = file_formats.ASSET_CATEGORY_COUNT;
pub const ASSET_TAG_COUNT = file_formats.ASSET_TAG_COUNT;
const name_tags = file_formats.name_tags;
const HHA_VERSION = file_formats.HHA_VERSION;
const HHA_MAGIC_VALUE = file_formats.HHA_MAGIC_VALUE;
const HHA_MAX_SOUND_SAMPLE_COUNT = file_formats.HHA_MAX_SOUND_SAMPLE_COUNT;
const ASSET_IMPORT_GRID_MAX = import.ASSET_IMPORT_GRID_MAX;
const ASSET_MAX_SPRITE_DIM = file_formats.ASSET_MAX_SPRITE_DIM;
const ASSET_MAX_PLATE_DIM = file_formats.ASSET_MAX_PLATE_DIM;
const TEXTURE_ARRAY_DIM = renderer.TEXTURE_ARRAY_DIM;
const HHA_ALIGN_POINT_TYPE_COUNT = file_formats.HHA_ALIGN_POINT_TYPE_COUNT;

const AssetLRULink = struct {
    prev: ?*AssetLRULink = null,
    next: ?*AssetLRULink = null,
};

pub const Asset = struct {
    lru: AssetLRULink,

    state: u32 = 0,
    handle: union(enum) {
        texture_handle: RendererTexture,
        loaded_at_sample_index: u64,
        font: LoadedFont,
    },

    hha: HHAAsset,
    annotation: HHAAnnotation,

    file_index: u32,
    asset_index_in_file: u32,

    asset_type: u32,
    next_of_type: u32,
};

pub const AssetVector = struct {
    e: [ASSET_TAG_COUNT]f32 = @splat(0),
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

pub const AssetFile = struct {
    handle: PlatformFileHandle,
    stem: String,
    header: HHAHeader,
    tag_base: u32,
    asset_base: u32,
    high_water_mark: u64,
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

pub const SourceFile = struct {
    next_in_hash: ?*SourceFile,
    base_name: String,
    file_date: u64,
    file_checksum: u64,
    dest_file_index: u32, // Index of the AssetFile to which this source file writes.

    // Note: [Y][X], asset index in the Assets.assets array.
    asset_indices: [ASSET_IMPORT_GRID_MAX][ASSET_IMPORT_GRID_MAX]u32 = @splat(@splat(0)),

    errors: Stream,

    pub fn getOrCreateFromHashValue(assets: *Assets, base_name: [*:0]const u8) *SourceFile {
        const hash_value: u32 = @mod(shared.stringHashOfZ(base_name), @as(u32, @intCast(assets.source_file_hash.len)));

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
            match.?.base_name = .wrapZ(@constCast(assets.non_restored_memory.pushAndNullTerminateString(
                types.stringLength(base_name),
                base_name,
            )));
            match.?.next_in_hash = assets.source_file_hash[hash_value];
            assets.source_file_hash[hash_value] = match;

            match.?.errors = .onDemandMemoryStream(&assets.non_restored_memory, null);
        }

        return match.?;
    }

    pub fn getOrCreateFromDate(assets: *Assets, base_name: [*:0]u8, file_date: u64, file_checksum: u64) *SourceFile {
        var result: *SourceFile = .getOrCreateFromHashValue(assets, base_name);
        if (result.file_date == 0 or result.file_date > file_date) {
            result.file_date = file_date;
            result.file_checksum = file_checksum;
        }
        return result;
    }
};

pub const Assets = struct {
    non_restored_memory: MemoryArena,
    texture_queue: *renderer.TextureQueue,

    game_state: *shared.State,

    tag_range: [ASSET_TAG_COUNT]f32 = @splat(1000000),

    // TODO: This could just be allocated on demaind now, there is no reasong for it to be an array,
    // nobody uses it that way.
    max_file_count: u32,
    file_count: u32,
    files: [*]AssetFile,

    max_tag_count: u32,
    tag_count: u32,
    tags: [*]HHATag,

    max_asset_count: u32,
    asset_count: u32,
    assets: [*]Asset,

    first_asset_of_type: [ASSET_CATEGORY_COUNT]u32,

    source_file_hash: [256]?*SourceFile = @splat(null),

    sample_count: u32,
    sample_buffer: [*]i16,
    sample_buffer_base_index: u64,
    sample_buffer_load_index: u32,

    normal_texture_handle_count: u32 = 0,
    special_texture_handle_count: u32 = 0,

    next_special_texture_handle: u32 = 0,
    next_free_texture_handle: u32,

    special_texture_lru_sentinel: AssetLRULink,
    regular_texture_lru_sentinel: AssetLRULink,

    pub fn allocate(
        memory_size: MemoryIndex,
        game_state: *shared.State,
        texture_queue: *renderer.TextureQueue,
    ) *Assets {
        _ = memory_size;

        TimedBlock.beginFunction(@src(), .AllocateGameAssets);
        defer TimedBlock.endFunction(@src(), .AllocateGameAssets);

        var assets = memory.bootstrapPushStruct(
            Assets,
            "non_restored_memory",
            ArenaBootstrapParams.nonRestored(),
            ArenaPushParams.aligned(@alignOf(Assets), true),
        );
        var arena: *MemoryArena = &assets.non_restored_memory;

        assets.game_state = game_state;
        assets.texture_queue = texture_queue;
        assets.normal_texture_handle_count = shared.NORMAL_TEXTURE_COUNT;
        assets.special_texture_handle_count = shared.SPECIAL_TEXTURE_COUNT;

        shared.dlistInit(&assets.special_texture_lru_sentinel);
        shared.dlistInit(&assets.regular_texture_lru_sentinel);

        const op = renderer.beginTextureOp(texture_queue, 1, 1);
        std.debug.assert(op != null);
        op.?.texture = renderer.referToTexture(0, 1, 1);
        @as(*u32, @ptrCast(@alignCast(op.?.data))).* = 0xffffffff;
        renderer.completeTextureOp(texture_queue, op.?);

        assets.next_free_texture_handle = 1;

        assets.tag_range[@intFromEnum(AssetTagId.FacingDirection)] = math.TAU32;

        assets.tag_count = 1;
        assets.asset_count = 1;
        assets.file_count = 1;

        // Load asset headers.
        {
            var file_group = shared.platform.getAllFilesOfTypeBegin(.AssetFile);
            defer shared.platform.getAllFilesOfTypeEnd(&file_group);

            assets.max_file_count = file_group.file_count;
            if (INTERNAL) {
                assets.max_file_count += 256;
            }

            assets.files = arena.pushArray(assets.max_file_count, AssetFile, null);

            var opt_file_info: ?*PlatformFileInfo = file_group.first_file_info;
            while (opt_file_info) |file_info| : (opt_file_info = file_info.next) {
                _ = initSourceHHA(assets, &file_group, file_info);
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

                    const temp_mem = game_state.frame_arena.beginTemporaryMemory();
                    defer game_state.frame_arena.endTemporaryMemory(temp_mem);
                    const hha_asset_array: [*]HHAAsset =
                        game_state.frame_arena.pushArray(file_asset_count, HHAAsset, null);
                    var hha_annotation_array: ?[*]HHAAnnotation =
                        game_state.frame_arena.pushArray(file_asset_count, HHAAnnotation, null);

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
                        asset.asset_type = 0;
                        asset.asset_index_in_file = global_asset_index - file.asset_base;
                        asset.hha = hha_asset[0];
                        asset.annotation = hha_annotation.*;

                        if (asset.hha.first_tag_index == 0) {
                            asset.hha.one_past_last_tag_index = 0;
                        } else {
                            asset.hha.first_tag_index += (file.tag_base - 1);
                            asset.hha.one_past_last_tag_index += (file.tag_base - 1);
                        }

                        if (INTERNAL) {
                            // TODO: This is very inefficent, and we could modify the file format to keep a separate
                            // array of file names (or we could has file names based on their location in the file as
                            // well, and only read them once). But at the moment we just read the source name directly,
                            // because we don't care how long it takes in the "editing" mode of the game anyway.

                            const source_file_name_count: u32 = hha_annotation.source_file_base_name_count;
                            const source_file_name: [*:0]u8 =
                                @ptrCast(game_state.frame_arena.pushArray(source_file_name_count + 1, u8, null));
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
                            source_file.dest_file_index = file_index;

                            const grid_asset_index: *u32 = &source_file.asset_indices[grid_y][grid_x];
                            if (grid_asset_index.* == 0) {
                                grid_asset_index.* = global_asset_index;
                            } else {
                                const conflict: *Asset = &assets.assets[grid_asset_index.*];
                                _ = stream.outputWithSrc(
                                    &source_file.errors,
                                    @src(),
                                    "{s}({d},{d}): Asset {d} and {d} occupy same slot in spritesheet and cannot be edited properly.\n",
                                    .{ source_file_name, grid_x, grid_y, asset.asset_index_in_file, conflict.asset_index_in_file },
                                );
                            }
                        }

                        var type_id: AssetBasicCategory = .None;
                        var asset_tag_index: u32 = asset.hha.first_tag_index;
                        while (asset_tag_index < asset.hha.one_past_last_tag_index) : (asset_tag_index += 1) {
                            if (assets.tags[asset_tag_index].id == .BasicCategory) {
                                type_id = @enumFromInt(@as(u32, @intFromFloat(assets.tags[asset_tag_index].value)));
                            }
                        }

                        import.setAssetType(assets, global_asset_index, type_id);
                    }
                }
            }
        }

        std.debug.assert(asset_count == assets.asset_count);

        if (INTERNAL) {
            import.synchronizeAssetFileChanges(assets, false);
        }

        return assets;
    }

    pub fn initSourceHHA(
        assets: *Assets,
        file_group: *PlatformFileGroup,
        file_info: *PlatformFileInfo,
    ) u32 {
        var file_index: u32 = 0;

        if (assets.file_count < assets.max_file_count) {
            file_index = assets.file_count;
            assets.file_count += 1;

            var arena: *MemoryArena = &assets.non_restored_memory;
            var open_flags: u32 = @intFromEnum(shared.OpenFileModeFlags.Read);
            if (INTERNAL) {
                open_flags |= @intFromEnum(shared.OpenFileModeFlags.Write);
            }

            const file: *AssetFile = &assets.files[file_index];

            const file_handle = shared.platform.openFile(file_group, file_info, open_flags);
            const stem: String = types.removePath(types.removeExtension(.wrapZ(file_info.base_name)));
            file.stem = arena.pushStringSized(stem);
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
        }

        return file_index;
    }

    pub fn getFile(self: *Assets, file_index: u32) ?*AssetFile {
        std.debug.assert(file_index < self.file_count);
        return &self.files[file_index];
    }

    fn getFileHandleFor(self: *Assets, file_index: u32) *shared.PlatformFileHandle {
        return &self.getFile(file_index).?.handle;
    }

    pub fn getAsset(self: *Assets, asset_index: u32) ?*Asset {
        std.debug.assert(asset_index <= self.asset_count);
        const asset = &self.assets[asset_index];
        return asset;
    }

    pub fn getFirstAsset(self: *Assets, type_id: AssetBasicCategory) ?u32 {
        TimedBlock.beginFunction(@src(), .GetFirstAsset);
        defer TimedBlock.endFunction(@src(), .GetFirstAsset);

        const result: ?u32 = self.first_asset_of_type[type_id.toInt()];

        return result;
    }

    // pub fn getRandomAsset(self: *Assets, type_id: AssetBasicCategory, series: *random.Series) ?u32 {
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
        type_id: AssetBasicCategory,
        match_vector: *AssetVector,
        weight_vector: *AssetVector,
    ) ?u32 {
        TimedBlock.beginFunction(@src(), .GetBestMatchAsset);
        defer TimedBlock.endFunction(@src(), .GetBestMatchAsset);

        var result: ?u32 = null;
        var best_match: f32 = 0;

        var asset_index: u32 = self.first_asset_of_type[@intFromEnum(type_id)];
        while (asset_index != 0) {
            const asset = self.assets[asset_index];

            var total_match: f32 = 0;
            var tag_index: u32 = asset.hha.first_tag_index;
            while (tag_index < asset.hha.one_past_last_tag_index) : (tag_index += 1) {
                const tag: *HHATag = &self.tags[tag_index];

                const a: f32 = match_vector.e[@intFromEnum(tag.id)];
                const b: f32 = tag.value;
                const d0 = intrinsics.absoluteValue(a - b);
                const d1 = intrinsics.absoluteValue((a - (self.tag_range[tag.id.toInt()] * intrinsics.signOfF32(a))) - b);
                const difference = 1.0 - @min(d0, d1);

                const weighted = weight_vector.e[tag.id.toInt()] * difference;
                total_match += weighted;
            }

            if (best_match < total_match) {
                best_match = total_match;
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
        self.loadBitmap(opt_id);
    }

    fn dimensionsRequireSpecialTexture(self: *Assets, width: u32, height: u32) bool {
        _ = self;
        return width >= TEXTURE_ARRAY_DIM or height >= TEXTURE_ARRAY_DIM;
    }

    pub fn unloadBitmap(self: *Assets, opt_id: ?BitmapId) void {
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
                ) != null) {
                    asset.handle.texture_handle = .empty;
                    asset.state = AssetState.Unloaded.toInt();
                }
            }
        }
    }

    fn acquireTextureHandle(self: *Assets, dimension: Vector2u) u32 {
        var opt_replace_sentinel: ?*AssetLRULink = null;
        var result: u32 = 0;
        if (self.dimensionsRequireSpecialTexture(@intCast(dimension.x()), @intCast(dimension.y()))) {
            if (self.next_special_texture_handle < self.special_texture_handle_count) {
                result = renderer.specialTextureIndexFrom(self.next_special_texture_handle);
                self.next_special_texture_handle += 1;
            } else {
                opt_replace_sentinel = &self.special_texture_lru_sentinel;
            }
        } else {
            if (self.next_free_texture_handle < self.normal_texture_handle_count) {
                result = self.next_free_texture_handle;
                self.next_free_texture_handle += 1;
            } else {
                opt_replace_sentinel = &self.regular_texture_lru_sentinel;
            }
        }

        if (opt_replace_sentinel) |replace_sentinel| {
            std.debug.assert(!shared.dlistIsEmpty(replace_sentinel));

            const first: *AssetLRULink = replace_sentinel.next.?;
            shared.dlistRemove(first);
            const replace_asset: *Asset = @ptrCast(first);
            replace_asset.state = AssetState.Unloaded.toInt();
            result = replace_asset.handle.texture_handle.values.index;

            replace_asset.handle = .{ .texture_handle = .empty };
        }

        return result;
    }

    pub fn loadBitmap(self: *Assets, opt_id: ?BitmapId) void {
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
                    const info = asset.hha.info.bitmap;
                    const width = types.safeTruncateUInt32ToUInt16(info.dim[0]);
                    const height = types.safeTruncateUInt32ToUInt16(info.dim[1]);

                    if (renderer.beginTextureOp(self.texture_queue, width, height)) |texture_op| {
                        const opt_task: ?*shared.TaskWithMemory = handmade.beginTaskWithMemory(self.game_state, false);

                        if (opt_task) |task| {
                            const bitmap_width: u32 = width;
                            const bitmap_height: u32 = height;

                            const texture_handle: u32 = self.acquireTextureHandle(.new(info.dim[0], info.dim[1]));
                            asset.handle = .{
                                .texture_handle = renderer.referToTexture(texture_handle, bitmap_width, bitmap_height),
                            };
                            texture_op.texture = asset.handle.texture_handle;

                            const work: *LoadAssetWork = task.arena.pushStruct(
                                LoadAssetWork,
                                ArenaPushParams.noClear(),
                            );
                            work.task = task;
                            work.asset = asset;
                            work.handle = self.getFileHandleFor(asset.file_index);
                            work.offset = asset.hha.data_offset;
                            work.size = bitmap_width * bitmap_height * 4;
                            work.destination = @ptrCast(texture_op.data);
                            work.final_state = AssetState.Loaded.toInt();
                            work.texture_op = texture_op;
                            work.texture_queue = self.texture_queue;

                            shared.platform.addQueueEntry(
                                self.game_state.low_priority_queue,
                                doLoadAssetWork,
                                work,
                            );
                        } else {
                            renderer.cancelTextureOp(self.texture_queue, texture_op);
                            asset.state = AssetState.Unloaded.toInt();
                        }
                    } else {
                        asset.state = AssetState.Unloaded.toInt();
                    }
                }
            }
        }
    }

    pub fn getBitmap(self: *Assets, id: BitmapId) RendererTexture {
        const asset: ?*Asset = self.getAsset(id.value);
        std.debug.assert(id.value == 0 or asset.?.hha.type == .Bitmap);

        const result: RendererTexture = asset.?.handle.texture_handle;

        if (result.isValid()) {
            const info = &asset.?.hha.info.bitmap;
            shared.dlistRemove(&asset.?.lru);
            if (self.dimensionsRequireSpecialTexture(@intCast(info.dim[0]), @intCast(info.dim[1]))) {
                shared.dlistInsertLast(&self.special_texture_lru_sentinel, &asset.?.lru);
            } else {
                shared.dlistInsertLast(&self.regular_texture_lru_sentinel, &asset.?.lru);
            }
        }

        return result;
    }

    pub fn getBitmapInfo(self: *Assets, id: BitmapId) *HHABitmap {
        const asset: ?*Asset = self.getAsset(id.value);
        std.debug.assert(id.value == 0 or asset.?.hha.type == .Bitmap);
        return &asset.?.hha.info.bitmap;
    }

    pub fn getFirstBitmap(self: *Assets, type_id: AssetBasicCategory) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.getFirstAsset(type_id)) |slot_id| {
            result = BitmapId{ .value = slot_id };
        }

        return result;
    }

    // pub fn getRandomBitmap(self: *Assets, type_id: AssetBasicCategory, series: *random.Series) ?BitmapId {
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
        type_id: AssetBasicCategory,
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
        const asset: ?*Asset = self.getAsset(id.value);
        std.debug.assert(asset.?.hha.type == .Sound);
        return &asset.?.hha.info.sound;
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

        _ = self;
        _ = opt_id;

        // if (opt_id) |id| {
        //     var asset = &self.assets[id.value];
        //
        //     if (id.isValid() and @cmpxchgStrong(
        //         u32,
        //         &asset.state,
        //         AssetState.Unloaded.toInt(),
        //         AssetState.Queued.toInt(),
        //         .seq_cst,
        //         .seq_cst,
        //     ) == null) {
        //         if (handmade.beginTaskWithMemory(self.game_state, false)) |task| {
        //             const info = asset.hha.info.sound;
        //
        //             var size = AssetMemorySize{};
        //             size.section = info.sample_count * @sizeOf(i16);
        //             size.data = info.channel_count * size.section;
        //             size.total = size.data;
        //
        //             asset.header = @ptrCast(@alignCast(self.acquireAssetMemory(types.align16(size.total), id.value, .Sound)));
        //             const sound = &asset.header.?.data.sound;
        //
        //             sound.sample_count = info.sample_count;
        //             sound.channel_count = info.channel_count;
        //             const channel_size = size.section;
        //
        //             const sound_memory: *anyopaque = @ptrCast(asset.header);
        //             var sound_at: [*]i16 = @ptrCast(@alignCast(sound_memory));
        //             var channel_index: u32 = 0;
        //             while (channel_index < sound.channel_count) : (channel_index += 1) {
        //                 sound.samples[channel_index] = sound_at;
        //                 sound_at += channel_size;
        //             }
        //
        //             var work: *LoadAssetWork = task.arena.pushStruct(LoadAssetWork, null);
        //             work.task = task;
        //             work.asset = asset;
        //             work.handle = self.getFileHandleFor(asset.file_index);
        //             work.offset = asset.hha.data_offset;
        //             work.size = size.data;
        //             work.destination = sound_memory;
        //             work.finalize_operation = .None;
        //             work.final_state = AssetState.Loaded.toInt();
        //             work.texture_queue = null;
        //
        //             shared.platform.addQueueEntry(self.game_state.low_priority_queue, doLoadAssetWork, work);
        //         } else {
        //             @atomicStore(u32, &asset.state, AssetState.Unloaded.toInt(), .release);
        //         }
        //     }
        // }
    }

    pub fn getSoundSamples(self: *Assets, id: SoundId) ?[*]u16 {
        const asset: ?*Asset = self.getAsset(id.value);
        std.debug.assert(id.value == 0 or asset.?.hha.type == .Sound);

        const result: ?[*]u16 = null;

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

    pub fn getFirstSound(self: *Assets, type_id: AssetBasicCategory) ?SoundId {
        var result: ?SoundId = null;

        if (self.getFirstAsset(type_id)) |slot_id| {
            result = SoundId{ .value = slot_id };
        }

        return result;
    }

    // pub fn getRandomSound(self: *Assets, type_id: AssetBasicCategory, series: *random.Series) ?SoundId {
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
        type_id: AssetBasicCategory,
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
        id: ?FontId,
    ) void {
        var asset = &self.assets[id.?.value];
        std.debug.assert(asset.state == @intFromEnum(AssetState.Unloaded));

        const info: HHAFont = asset.hha.info.font;

        const horizontal_advance_size: u32 = @sizeOf(f32) * info.glyph_count * info.glyph_count;
        const glyphs_size: u32 = info.glyph_count * @sizeOf(HHAFontGlyph);
        const unicode_map_size: u32 = @sizeOf(u16) * info.one_past_highest_code_point;
        const size_data: u32 = glyphs_size + horizontal_advance_size;
        const size_total: u32 = size_data + unicode_map_size;

        const memory_point = self.non_restored_memory.beginTemporaryMemory();

        const asset_memory: [*]u8 = self.non_restored_memory.pushSize(size_total, null);

        if (asset.handle != .font) {
            asset.handle = .{ .font = .{} };
        }
        var font: *LoadedFont = @ptrCast(@alignCast(&asset.handle.font));
        font.bitmap_id_offset = self.getFile(asset.file_index).?.asset_base;
        font.glyphs = @ptrCast(@alignCast(asset_memory));
        font.horizontal_advance =
            @ptrCast(@alignCast(@as([*]u8, @ptrCast(font.glyphs)) + glyphs_size));
        font.unicode_map =
            @ptrCast(@alignCast(@as([*]u8, @ptrCast(font.horizontal_advance)) + horizontal_advance_size));

        memory.zeroSize(unicode_map_size, @ptrCast(font.unicode_map));

        const file_handle: *PlatformFileHandle = self.getFileHandleFor(asset.file_index);
        shared.platform.readDataFromFile(
            file_handle,
            asset.hha.data_offset,
            size_data,
            @ptrCast(font.glyphs),
        );

        if (shared.platform.noFileErrors(file_handle)) {
            const hha: *HHAFont = &asset.hha.info.font;

            var glyph_index: u32 = 1;
            while (glyph_index < hha.glyph_count) : (glyph_index += 1) {
                const glyph: *HHAFontGlyph = &font.glyphs[glyph_index];

                std.debug.assert(glyph.unicode_code_point < hha.one_past_highest_code_point);
                std.debug.assert(@as(u16, @intCast(glyph_index)) == glyph_index);
                font.unicode_map[glyph.unicode_code_point] = @intCast(glyph_index);
            }

            asset.state = @intFromEnum(AssetState.Loaded);
            self.non_restored_memory.keepTemporaryMemory(memory_point);
        } else {
            self.non_restored_memory.endTemporaryMemory(memory_point);
        }
    }

    pub fn prefetchFont(
        self: *Assets,
        opt_id: ?FontId,
    ) void {
        self.loadFont(opt_id);
    }

    pub fn getFont(self: *Assets, id: FontId) ?*LoadedFont {
        const asset: ?*Asset = self.getAsset(id.value);
        std.debug.assert(id.value == 0 or asset.?.hha.type == .Font);

        var result: ?*LoadedFont = null;

        if (asset.?.state == @intFromEnum(AssetState.Loaded)) {
            if (asset.?.handle != .font) {
                asset.?.handle = .{ .font = .{} };
            }
            result = &asset.?.handle.font;
        }

        return result;
    }

    pub fn getFontInfo(self: *Assets, id: FontId) *HHAFont {
        const asset: ?*Asset = self.getAsset(id.value);
        std.debug.assert(asset.?.hha.type == .Font);
        return &asset.?.hha.info.font;
    }

    pub fn getBestMatchFont(
        self: *Assets,
        type_id: AssetBasicCategory,
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

pub const LoadedFont = extern struct {
    glyphs: [*]HHAFontGlyph = undefined,
    horizontal_advance: [*]f32 = undefined,
    bitmap_id_offset: u32 = 0,
    unicode_map: [*]u16 = undefined,

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

const LoadAssetWork = struct {
    task: *shared.TaskWithMemory,
    asset: *Asset,

    handle: *PlatformFileHandle = undefined,
    offset: u64,
    size: u64,
    destination: *anyopaque,

    final_state: u32,

    texture_op: ?*TextureOp,
    texture_queue: ?*renderer.TextureQueue,
};

fn doLoadAssetWork(queue: shared.PlatformWorkQueuePtr, data: *anyopaque) callconv(.c) void {
    _ = queue;

    TimedBlock.beginFunction(@src(), .DoLoadAssetWork);
    defer TimedBlock.endFunction(@src(), .DoLoadAssetWork);

    var resulting_state: AssetState = .Unloaded;
    const work: *LoadAssetWork = @ptrCast(@alignCast(data));

    shared.platform.readDataFromFile(work.handle, work.offset, work.size, work.destination);

    if (shared.platform.noFileErrors(work.handle)) {
        resulting_state = .Loaded;
    } else {
        memory.zeroSize(work.size, @ptrCast(work.destination));
    }

    if (work.texture_op) |texture_op| {
        renderer.completeTextureOp(work.texture_queue.?, texture_op);
    }

    work.asset.state = @intFromEnum(resulting_state);
    handmade.endTaskWithMemory(work.task);
}
