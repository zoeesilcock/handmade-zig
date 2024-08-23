const shared = @import("shared.zig");
const math = @import("math.zig");
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
    Backdrop,
    Shadow,
    Tree,
    Sword,
    Stairwell,
    Rock,

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
    alignment_percentage: Vector2 = Vector2.zero(),
    width_over_height: f32 = 0,
    width: i32 = 0,
    height: i32 = 0,
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

    sound_count: u32,
    sounds: [*]AssetSlot,

    asset_count: u32,
    assets: [*]Asset,

    tag_count: u32,
    tags: [*]AssetTag,

    asset_types: [ASSET_TYPE_ID_COUNT]AssetType = [1]AssetType{AssetType{}} ** ASSET_TYPE_ID_COUNT,

    // Array assets.
    grass: [2]LoadedBitmap,
    stone: [4]LoadedBitmap,
    tuft: [3]LoadedBitmap,

    // Structured assets.
    hero_bitmaps: [4]HeroBitmaps,

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
        result.bitmap_count = ASSET_TYPE_ID_COUNT;
        result.bitmaps = result.arena.pushArray(result.bitmap_count, AssetSlot);

        result.sound_count = 1;
        result.sounds = result.arena.pushArray(result.sound_count, AssetSlot);

        result.tag_count = 0;
        result.tags = result.arena.pushArray(result.tag_count, AssetTag);

        result.asset_count = result.bitmap_count;
        result.assets = result.arena.pushArray(result.asset_count, Asset);

        var asset_id: u32 = 0;
        while (asset_id < ASSET_TYPE_ID_COUNT) : (asset_id += 1) {
            const asset_type: *AssetType = &result.asset_types[asset_id];
            asset_type.first_asset_index = asset_id;
            asset_type.one_past_last_asset_index = asset_id + 1;

            const asset: *Asset = &result.assets[asset_type.first_asset_index];
            asset.first_tag_index = 0;
            asset.one_past_last_index = 0;
            asset.slot_id = asset_type.first_asset_index;
        }

        result.hero_bitmaps = .{
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_right_head.bmp"),
                .torso = debugLoadBMP("test/test_hero_right_torso.bmp"),
                .cape = debugLoadBMP("test/test_hero_right_cape.bmp"),
            },
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_back_head.bmp"),
                .torso = debugLoadBMP("test/test_hero_back_torso.bmp"),
                .cape = debugLoadBMP("test/test_hero_back_cape.bmp"),
            },
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_left_head.bmp"),
                .torso = debugLoadBMP("test/test_hero_left_torso.bmp"),
                .cape = debugLoadBMP("test/test_hero_left_cape.bmp"),
            },
            HeroBitmaps{
                .head = debugLoadBMP("test/test_hero_front_head.bmp"),
                .torso = debugLoadBMP("test/test_hero_front_torso.bmp"),
                .cape = debugLoadBMP("test/test_hero_front_cape.bmp"),
            },
        };
        result.grass = .{
            debugLoadBMP("test2/grass00.bmp"),
            debugLoadBMP("test2/grass01.bmp"),
        };
        result.stone = .{
            debugLoadBMP("test2/ground00.bmp"),
            debugLoadBMP("test2/ground01.bmp"),
            debugLoadBMP("test2/ground02.bmp"),
            debugLoadBMP("test2/ground03.bmp"),
        };
        result.tuft = .{
            debugLoadBMP("test2/tuft00.bmp"),
            debugLoadBMP("test2/tuft01.bmp"),
            debugLoadBMP("test2/tuft02.bmp"),
        };

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
};

const LoadBitmapWork = struct {
    assets: *Assets,
    id: BitmapId,
    file_name: [*:0]const u8,
    task: *shared.TaskWithMemory,
    bitmap: *LoadedBitmap,

    has_alignment: bool,
    align_x: i32,
    top_down_align_y: i32,

    final_state: AssetState,
};

fn doLoadAssetWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    const work: *LoadBitmapWork = @ptrCast(@alignCast(data));

    if (work.has_alignment) {
        work.bitmap.* = debugLoadBMPAligned(
            work.file_name,
            work.align_x,
            work.top_down_align_y,
        );
    } else {
        work.bitmap.* = debugLoadBMP(work.file_name);
    }

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
            work.has_alignment = false;
            work.final_state = .Loaded;

            switch (@as(AssetTypeId, @enumFromInt(id.value))) {
                .None => {},
                .Backdrop => {
                    work.file_name = "test/test_background.bmp";
                },
                .Shadow => {
                    work.file_name = "test/test_hero_shadow.bmp";
                    work.has_alignment = true;
                    work.align_x = 72;
                    work.top_down_align_y = 182;
                },
                .Tree => {
                    work.file_name = "test2/tree00.bmp";
                    work.has_alignment = true;
                    work.align_x = 40;
                    work.top_down_align_y = 80;
                },
                .Sword => {
                    work.file_name = "test2/rock03.bmp";
                    work.has_alignment = true;
                    work.align_x = 29;
                    work.top_down_align_y = 10;
                },
                .Stairwell => {
                    work.file_name = "test2/rock02.bmp";
                },
                .Rock => {},
            }

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
) LoadedBitmap {
    var result = debugLoadBMPAligned(file_name, 0, 0);
    result.alignment_percentage = Vector2.new(0.5, 0.5);
    return result;
}

fn debugLoadBMPAligned(
    file_name: [*:0]const u8,
    align_x: i32,
    top_down_align_y: i32,
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
        result.alignment_percentage = topDownAligned(&result, Vector2.newI(align_x, top_down_align_y));
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

