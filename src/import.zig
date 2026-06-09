const std = @import("std");
const shared = @import("shared.zig");
const math = @import("math.zig");
const types = @import("types.zig");
const asset_mod = @import("asset.zig");
const stream = @import("stream.zig");
const memory = @import("memory.zig");
const file_formats = shared.file_formats;
const png = @import("png.zig");
const tokenizer_mod = @import("tokenizer.zig");

// Build options.
const INTERNAL = shared.INTERNAL;

// Types.
const PlatformFileHandle = shared.PlatformFileHandle;
const PlatformFileInfo = shared.PlatformFileInfo;
const PlatformFileGroup = shared.PlatformFileGroup;
const Vector2 = math.Vector2;
const Vector2u = math.Vector2u;
const Vector3 = math.Vector3;
const Color = math.Color;
const Assets = asset_mod.Assets;
const Asset = asset_mod.Asset;
const AssetFile = asset_mod.AssetFile;
const SourceFile = asset_mod.SourceFile;
const Stream = stream.Stream;
const Buffer = types.Buffer;
const String = types.String;
const MemoryArena = memory.MemoryArena;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAsset = file_formats.HHAAsset;
const HHAAnnotation = file_formats.HHAAnnotation;
const AssetBasicCategory = file_formats.AssetBasicCategory;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const FontId = file_formats.FontId;
const AssetTagId = file_formats.AssetTagId;
const HHAAlignPoint = file_formats.HHAAlignPoint;
const HHAAlignPointType = file_formats.HHAAlignPointType;
const ImageU32 = png.ImageU32;
const Token = tokenizer_mod.Token;
const Tokenizer = tokenizer_mod.Tokenizer;

pub const ASSET_IMPORT_GRID_MAX = 8;
const ASSET_MAX_SPRITE_DIM = file_formats.ASSET_MAX_SPRITE_DIM;
const ASSET_MAX_PLATE_DIM = file_formats.ASSET_MAX_PLATE_DIM;
const HHA_ALIGN_POINT_TYPE_COUNT = file_formats.HHA_ALIGN_POINT_TYPE_COUNT;

const ImportType = enum(u32) {
    None,
    Plate,
    SingleTile,
    MultiTile,
};

const ImportTagArray = struct {
    first_tag_index: u32 = 0,
    one_past_last_tag_index: u32 = 0,

    pub fn getCount(self: ImportTagArray) u32 {
        return self.one_past_last_tag_index - self.first_tag_index;
    }
};

const ImportGridTag = struct {
    type_id: AssetBasicCategory = .None,
    tags: ImportTagArray = .{},
};

const ImportGridTags = struct {
    tags: [ASSET_IMPORT_GRID_MAX][ASSET_IMPORT_GRID_MAX]ImportGridTag = @splat(@splat(.{})),
};

const TagBuilder = struct {
    assets: *Assets = undefined,
    first_tag_index: u32 = 0,
    has_error: bool = false,
};

const HHTContext = struct {
    assets: *Assets,
    default_fields: HHTFields = .{},
    file_group: PlatformFileGroup,
    temp_arena: *MemoryArena,
    hha_stem: String = .empty,
    hha_index: u32 = 0,
    include_depth: u32 = 0,
    hht_write: bool = false, // If true, we are writing a new HHT from the existing one, not importing its values.
};

const HHTFields = struct {
    name: String = .empty,
    author: String = .empty,
    description: String = .empty,
};

pub fn reserveTag(assets: *Assets, tag_count: u32) u32 {
    var result: u32 = 0;

    if ((assets.tag_count + tag_count) < assets.max_tag_count) {
        result = assets.tag_count;
        assets.tag_count += tag_count;
    }

    return result;
}

pub fn reserveAsset(assets: *Assets) u32 {
    var result: u32 = 0;

    if (assets.asset_count < assets.max_asset_count) {
        result = assets.asset_count;
        assets.asset_count += 1;
    }

    return result;
}

pub fn reserveData(assets: *Assets, file: *AssetFile, data_size: u32) u64 {
    _ = assets;
    const result: u64 = file.high_water_mark;
    file.modified = true;
    file.high_water_mark += data_size;
    return result;
}

fn writeAssetStream(file: *AssetFile, data_offset_in: u64, data: *const Stream) void {
    var data_offset: u64 = data_offset_in;
    var opt_chunk: ?*stream.Chunk = data.first;
    while (opt_chunk) |chunk| : (opt_chunk = chunk.next) {
        writeAssetData(
            file,
            data_offset,
            @intCast(chunk.contents.count),
            @ptrCast(@alignCast(chunk.contents.data)),
        );
        data_offset += chunk.contents.count;
    }
}

fn writeAssetData(file: *AssetFile, data_offset: u64, data_size: u32, data: [*]align(1) u32) void {
    file.modified = true;
    shared.platform.writeDataToFile(&file.handle, data_offset, data_size, data);
}

pub fn updateAssetString(
    assets: *Assets,
    file: *AssetFile,
    source: String,
    count: *align(1) u32,
    offset: *align(1) u64,
) void {
    // TODO: Don't write this if the string is already the same in the file.
    if (source.count > count.*) {
        offset.* = reserveData(assets, file, @intCast(source.count));
    }

    count.* = @intCast(source.count);
    writeAssetData(file, offset.*, count.*, @ptrCast(@alignCast(source.data)));
}

pub fn writeModificationsToHHA(assets: *Assets, file_index: u32, temp_arena: *MemoryArena) void {
    const file: *AssetFile = &assets.files[file_index];

    file.modified = false;

    var asset_count: u32 = 1; // First asset entry is skipped as the null asset!
    var tag_count: u32 = 1; // First tag entry is skipped as the null tag!
    var asset_index: u32 = 0;
    while (asset_index < assets.asset_count) : (asset_index += 1) {
        const asset: *Asset = &assets.assets[asset_index];
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
    const hha_assets: [*]HHAAsset = temp_arena.pushArray(asset_count, HHAAsset, null);
    const annotations: [*]HHAAnnotation = temp_arena.pushArray(asset_count, HHAAnnotation, null);

    var tag_index_in_file: u32 = 1;
    var asset_index_in_file: u32 = 1;

    var global_asset_index: u32 = 1;
    while (global_asset_index < assets.asset_count) : (global_asset_index += 1) {
        const source: *Asset = &assets.assets[global_asset_index];
        if (source.file_index == file_index) {
            const dest: *HHAAsset = &hha_assets[asset_index_in_file];
            const dest_annotation: *HHAAnnotation = &annotations[asset_index_in_file];
            source.asset_index_in_file = asset_index_in_file;

            dest_annotation.* = source.annotation;

            dest.* = source.hha;
            dest.first_tag_index = tag_index_in_file;
            var tag_index: u32 = source.hha.first_tag_index;
            while (tag_index < source.hha.one_past_last_tag_index) : (tag_index += 1) {
                tags[tag_index_in_file] = assets.tags[tag_index];
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
    shared.platform.writeDataToFile(&file.handle, file.header.assets, assets_array_size, hha_assets);
    shared.platform.writeDataToFile(&file.handle, file.header.annotations, annotation_array_size, annotations);
}

pub fn setAssetType(assets: *Assets, asset_index: u32, type_id: AssetBasicCategory) void {
    // TODO: We don't really want to be doing this anymore, we just want a tag-matcing acceleration structure that
    // we can rebuild during imports, because we ant it to be easy to do things like change the types of assets.
    if (asset_index != 0 and @intFromEnum(type_id) < @typeInfo(AssetBasicCategory).@"enum".fields.len) {
        var asset: *Asset = &assets.assets[asset_index];
        std.debug.assert(asset.next_of_type == 0);
        std.debug.assert(asset.asset_type == 0);
        asset.asset_type = @intFromEnum(type_id);
        asset.next_of_type = assets.first_asset_of_type[@intFromEnum(type_id)];
        assets.first_asset_of_type[@intFromEnum(type_id)] = asset_index;
    }
}

fn getDownsampleCountForFit(source: ImageU32, max_width: u32, max_height: u32) u32 {
    var result: u32 = 0;
    var width: u32 = source.width;
    var height: u32 = source.height;
    while (width > max_width or height > max_height) {
        width /= 2;
        height /= 2;
        result += 1;
    }
    return result;
}

fn downsample(source: ImageU32, downsample_count: u32) ImageU32 {
    var result: ImageU32 = source;
    var downsample_index: u32 = 0;
    while (downsample_index < downsample_count) : (downsample_index += 1) {
        const width: u32 = result.width / 2;
        const height: u32 = result.height / 2;

        var dest_pixel: [*]u32 = @ptrCast(result.pixels);
        var source_row: [*]u32 = @ptrCast(result.pixels);

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var source_pixel0: [*]u32 = source_row;
            var source_pixel1: [*]u32 = source_row + result.width;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
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

            source_row += result.width * 2;
        }

        result.width = width;
        result.height = height;
    }

    return result;
}

fn writeImageToHHA(
    assets: *Assets,
    file: *SourceFile,
    orig_dim: Vector2u,
    source_image: ImageU32,
    temp_arena: *MemoryArena,
    tile_x_index: u32,
    tile_y_index: u32,
) void {
    _ = temp_arena;

    var hha_asset: HHAAsset = .{
        .info = .{
            .bitmap = .{},
        },
    };
    hha_asset.info.bitmap.align_points[0].set(.Default, true, 1.0, .new(0.5, 0.5));
    var asset_index: u32 = file.asset_indices[tile_y_index][tile_x_index];
    if (asset_index != 0) {
        const asset: *Asset = &assets.assets[asset_index];
        hha_asset = asset.hha;
    } else {
        asset_index = reserveAsset(assets);
    }

    if (asset_index != 0) {
        const asset_data_size: u32 = source_image.getTotalImageSize();
        var asset: *Asset = &assets.assets[asset_index];

        const bitmap_id: BitmapId = .{ .value = asset_index };
        assets.unloadBitmap(bitmap_id);

        asset.file_index = file.dest_file_index;
        std.debug.assert(asset.file_index != 0);

        const asset_file: *AssetFile = &assets.files[asset.file_index];
        if (hha_asset.data_offset == 0 or hha_asset.data_size < asset_data_size) {
            hha_asset.data_offset = reserveData(assets, asset_file, asset_data_size);
        }
        hha_asset.data_size = asset_data_size;

        hha_asset.info.bitmap.dim[0] = @intCast(source_image.width);
        hha_asset.info.bitmap.dim[1] = @intCast(source_image.height);
        hha_asset.info.bitmap.orig_dim[0] = @intCast(orig_dim.width());
        hha_asset.info.bitmap.orig_dim[1] = @intCast(orig_dim.height());
        hha_asset.type = .Bitmap;

        asset.hha = hha_asset;
        asset.annotation.source_file_date = file.file_date;
        asset.annotation.source_file_checksum = file.file_checksum;
        asset.annotation.sprite_sheet_x = tile_x_index;
        asset.annotation.sprite_sheet_y = tile_y_index;

        file.asset_indices[tile_y_index][tile_x_index] = asset_index;

        writeAssetData(asset_file, hha_asset.data_offset, asset_data_size, @ptrCast(source_image.pixels));
    } else {
        _ = stream.outputWithSrc(&file.errors, @src(), "Out of asset memory - please restart Handmade Hero!\n", .{});
    }
}

fn extractImage(
    source_image: ImageU32,
    min_x: u32,
    min_y: u32,
    one_past_max_x: u32,
    one_past_max_y: u32,
    temp_arena: *MemoryArena,
) ImageU32 {
    const result: ImageU32 = .pushImage(temp_arena, one_past_max_x - min_x, one_past_max_y - min_y);
    var dest_pixel: [*]u32 = @ptrCast(result.pixels);
    var source_row: [*]u32 = source_image.pixels.ptr + ((one_past_max_y - 1) * source_image.width + min_x);

    var y: u32 = 0;
    while (y < result.height) : (y += 1) {
        var source_pixel: [*]u32 = source_row;

        var x: u32 = 0;
        while (x < result.width) : (x += 1) {
            const source_color: u32 = source_pixel[0];
            source_pixel += 1;
            var color: Color = .unpackColorRGBA(source_color);
            color = math.sRGB255ToLinear1(color);
            _ = color.setRGB(color.rgb().scaledTo(color.a()));
            color = math.linear1ToSRGB255(color);
            dest_pixel[0] = Color.packColorBGRA(color);
            dest_pixel += 1;
        }

        source_row -= source_image.width;
    }

    return result;
}

fn processPlateImport(
    assets: *Assets,
    file: *SourceFile,
    source_image: ImageU32,
    temp_arena: *MemoryArena,
) void {
    const orig_dim: Vector2u = .new(source_image.width, source_image.height);
    const donwsample_count: u32 = getDownsampleCountForFit(source_image, ASSET_MAX_PLATE_DIM, ASSET_MAX_PLATE_DIM);
    const prepared_image: ImageU32 = extractImage(
        source_image,
        0,
        0,
        source_image.width,
        source_image.height,
        temp_arena,
    );
    const dest_image: ImageU32 = downsample(prepared_image, donwsample_count);
    writeImageToHHA(assets, file, orig_dim, dest_image, temp_arena, 0, 0);
}

fn processSingleTileImport(
    assets: *Assets,
    file: *SourceFile,
    source_image: ImageU32,
    temp_arena: *MemoryArena,
) void {
    const orig_dim: Vector2u = .new(source_image.width, source_image.height);
    const donwsample_count: u32 = getDownsampleCountForFit(source_image, ASSET_MAX_SPRITE_DIM, ASSET_MAX_SPRITE_DIM);
    const prepared_image: ImageU32 = extractImage(
        source_image,
        0,
        0,
        source_image.width,
        source_image.height,
        temp_arena,
    );
    const dest_image: ImageU32 = downsample(prepared_image, donwsample_count);
    writeImageToHHA(assets, file, orig_dim, dest_image, temp_arena, 0, 0);
}

fn processMultiTileImport(
    assets: *Assets,
    file: *SourceFile,
    image: ImageU32,
    temp_arena: *MemoryArena,
) void {
    const border_dimension: u32 = 8;
    const tile_dimension: u32 = 1024;

    const x_count_max: u32 = file.asset_indices[0].len;
    const y_count_max: u32 = file.asset_indices.len;

    var x_count: u32 = image.width / tile_dimension;
    if (x_count > x_count_max) {
        _ = stream.outputWithSrc(&file.errors, @src(), "Tile column count of %u exceeds maximum of %u columns.\n", .{
            x_count,
            x_count_max,
        });
        x_count = x_count_max;
    }
    var y_count: u32 = image.height / tile_dimension;
    if (y_count > y_count_max) {
        _ = stream.outputWithSrc(&file.errors, @src(), "Tile row count of %u exceeds maximum of %u rows.\n", .{
            y_count,
            y_count_max,
        });
        y_count = y_count_max;
    }

    var y_index: u32 = 0;
    while (y_index < y_count) : (y_index += 1) {
        var x_index: u32 = 0;
        while (x_index < x_count) : (x_index += 1) {
            var min_x: u32 = std.math.maxInt(u32);
            var max_x: u32 = std.math.minInt(u32);
            var min_y: u32 = std.math.maxInt(u32);
            var max_y: u32 = std.math.minInt(u32);

            // Calculate bounds of image contents.
            {
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
                    }

                    source_row += image.width;
                }
            }

            if (min_x <= max_x) {
                // There was something in this tile.
                if (min_x >= border_dimension) {
                    min_x -= border_dimension;
                } else {
                    min_x = 0;
                    _ = stream.outputWithSrc(&file.errors, @src(), "Tile %u, %u extends into left %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (max_x < (tile_dimension - border_dimension)) {
                    max_x += border_dimension;
                } else {
                    max_x = tile_dimension - 1;
                    _ = stream.outputWithSrc(&file.errors, @src(), "Tile %u, %u extends into right %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (min_y >= border_dimension) {
                    min_y -= border_dimension;
                } else {
                    min_y = 0;
                    _ = stream.outputWithSrc(&file.errors, @src(), "Tile %u, %u extends into top %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (max_y < (tile_dimension - border_dimension)) {
                    max_y += border_dimension;
                } else {
                    max_y = tile_dimension - 1;
                    _ = stream.outputWithSrc(&file.errors, @src(), "Tile %u, %u extends into bottom %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                const tile_image: ImageU32 = extractImage(
                    image,
                    x_index * tile_dimension + min_x,
                    y_index * tile_dimension + min_y,
                    x_index * tile_dimension + max_x + 1,
                    y_index * tile_dimension + max_y + 1,
                    temp_arena,
                );

                const downsample_count: u32 = getDownsampleCountForFit(
                    tile_image,
                    ASSET_MAX_SPRITE_DIM,
                    ASSET_MAX_SPRITE_DIM,
                );
                const orig_dim: Vector2u = .new(tile_image.width, tile_image.height);
                const dest_image: ImageU32 = downsample(tile_image, downsample_count);
                writeImageToHHA(assets, file, orig_dim, dest_image, temp_arena, x_index, y_index);
            }
        }
    }
}

fn popToken(source: *String) Token {
    var result: Token = .{
        .text = source.*,
        .f32 = 1,
    };

    var skip: u32 = 0;
    var index: u32 = 0;
    while (index < source.count) : (index += 1) {
        if (source.data[index] == '_') {
            result.text.count = index;
            result.text.data = source.data;
            skip = 1;
            break;
        }
    }

    if (source.count > 0) {
        source.count -= (result.text.count + skip);
        source.data += (result.text.count + skip);
    }

    return result;
}

fn beginTags(assets: *Assets) TagBuilder {
    const builder: TagBuilder = .{
        .assets = assets,
        .first_tag_index = assets.tag_count,
    };
    return builder;
}

fn addTag(builder: *TagBuilder, tag_id: AssetTagId, value: f32) void {
    if (builder.assets.tag_count < builder.assets.max_tag_count) {
        var tag: *HHATag = @ptrCast(builder.assets.tags + builder.assets.tag_count);
        builder.assets.tag_count += 1;

        tag.id = tag_id;
        tag.value = value;
    } else {
        builder.has_error = true;
    }
}

fn endTags(
    builder: *TagBuilder,
    tokenizer: *Tokenizer,
    category: AssetBasicCategory,
) ImportGridTag {
    var result: ImportGridTag = .{};

    // TODO: Make it explicit, instead of auto-ading the category?
    if (category != .None) {
        addTag(builder, .BasicCategory, @floatFromInt(@as(u32, @intFromEnum(category))));
    }

    result.type_id = category;
    result.tags.first_tag_index = builder.first_tag_index;
    result.tags.one_past_last_tag_index = builder.assets.tag_count;

    if (builder.has_error) {
        tokenizer.encounteredError(null, "Out of tag space.", .{});
    }

    return result;
}

fn importHead(
    assets: *Assets,
    tokenizer: *Tokenizer,
    x_index: u32,
    y_index: u32,
) ImportGridTag {
    var result: ImportGridTag = .{};

    if (x_index <= 2) {
        var builder: TagBuilder = beginTags(assets);
        addTag(
            &builder,
            .FacingDirection,
            @as(f32, @floatFromInt(@mod(y_index, 4))) * math.TAU32 / 4.0,
        );

        switch (x_index) {
            0 => addTag(&builder, .Idle, 1),
            1 => addTag(&builder, .Surprise, 1),
            2 => addTag(&builder, .Anger, 1),
            else => unreachable,
        }

        result = endTags(&builder, tokenizer, .Head);
    }

    return result;
}

fn importBody(
    assets: *Assets,
    tokenizer: *Tokenizer,
    x_index: u32,
    y_index: u32,
) ImportGridTag {
    var result: ImportGridTag = .{};

    if (x_index <= 6) {
        var builder: TagBuilder = beginTags(assets);
        addTag(
            &builder,
            .FacingDirection,
            @as(f32, @floatFromInt(@mod(y_index, 4))) * math.TAU32 / 4.0,
        );

        switch (x_index) {
            0 => addTag(&builder, .Idle, 1),
            1 => addTag(&builder, .DodgeLeft, 1),
            2 => addTag(&builder, .DodgeRight, 1),
            3 => addTag(&builder, .Move, 1),
            4 => addTag(&builder, .Hit, 1),
            5 => addTag(&builder, .Attack1, 1),
            6 => addTag(&builder, .Attack2, 1),
            else => unreachable,
        }

        result = endTags(&builder, tokenizer, .Body);
    }

    return result;
}

fn parsePieces(
    assets: *Assets,
    tokenizer: *Tokenizer,
    type_token: Token,
    tags: *ImportGridTags,
) ImportType {
    var result: ImportType = .None;

    if (type_token.equals("block")) {
        const tag: *ImportGridTag = &tags.tags[0][0];
        var builder: TagBuilder = beginTags(assets);
        tag.* = endTags(&builder, tokenizer, .Block);
        result = .SingleTile;
    } else if (type_token.equals("head")) {
        var y_index: u32 = 0;
        while (y_index < ASSET_IMPORT_GRID_MAX) : (y_index += 1) {
            var x_index: u32 = 0;
            while (x_index < ASSET_IMPORT_GRID_MAX) : (x_index += 1) {
                tags.tags[y_index][x_index] = importHead(assets, tokenizer, x_index, y_index);
            }
        }

        result = .MultiTile;
    } else if (type_token.equals("body")) {
        var y_index: u32 = 0;
        while (y_index < ASSET_IMPORT_GRID_MAX) : (y_index += 1) {
            var x_index: u32 = 0;
            while (x_index < ASSET_IMPORT_GRID_MAX) : (x_index += 1) {
                tags.tags[y_index][x_index] = importBody(assets, tokenizer, x_index, y_index);
            }
        }

        result = .MultiTile;
    } else if (type_token.equals("character")) {
        var y_index: u32 = 0;
        while (y_index < ASSET_IMPORT_GRID_MAX) : (y_index += 1) {
            var x_index: u32 = 0;
            const tag: *ImportGridTag = &tags.tags[y_index][x_index];

            while (x_index < ASSET_IMPORT_GRID_MAX) : (x_index += 1) {
                if (y_index <= 3) {
                    tag.* = importBody(assets, tokenizer, x_index, y_index);
                } else {
                    tag.* = importHead(assets, tokenizer, x_index, y_index - 4);
                }
            }
        }

        result = .MultiTile;
    } else if (type_token.equals("cover")) {
        // TODO: Item tags.
        result = .MultiTile;
    } else if (type_token.equals("hand")) {
        var y_index: u32 = 0;
        while (y_index < ASSET_IMPORT_GRID_MAX) : (y_index += 1) {
            var x_index: u32 = 0;
            while (x_index < ASSET_IMPORT_GRID_MAX) : (x_index += 1) {
                const tag: *ImportGridTag = &tags.tags[y_index][x_index];
                if (x_index == 0 and y_index < 4) {
                    var builder: TagBuilder = beginTags(assets);
                    addTag(&builder, .FacingDirection, @as(f32, @floatFromInt(y_index)) * math.TAU32 / 4.0);
                    tag.* = endTags(&builder, tokenizer, .Hand);
                }
            }
        }

        result = .MultiTile;
    } else if (type_token.equals("item")) {
        // TODO: Item tags.
        result = .MultiTile;
    } else if (type_token.equals("obstacles")) {
        // TODO: Item tags.
        result = .MultiTile;
    } else if (type_token.equals("plate")) {
        const tag: *ImportGridTag = &tags.tags[0][0];
        var builder: TagBuilder = beginTags(assets);
        tag.* = endTags(&builder, tokenizer, .Plate);

        result = .Plate;
    } else {
        // stream.output(errors, @src(), "Unrecognized type of import artwork.\n", .{});
        tokenizer.encounteredError(null, "Unrecognized type of import artwork.", .{});
    }

    return result;
}

pub fn writeAllHHAModifications(assets: *Assets) void {
    var file_index: u32 = 1;
    while (file_index < assets.file_count) : (file_index += 1) {
        const file: *AssetFile = @ptrCast(assets.files + file_index);
        if (file.modified) {
            var temp_arena: MemoryArena = .{};
            defer temp_arena.clear();

            writeModificationsToHHA(assets, file_index, &temp_arena);
        }
    }
}

pub fn readAssetString(
    file: *AssetFile,
    arena: *MemoryArena,
    count: u32,
    offset: u64,
) String {
    const result: String = .{
        .count = count,
        .data = arena.pushSize(count, null),
    };
    shared.platform.readDataFromFile(&file.handle, offset, result.count, result.data);
    return result;
}

pub fn parseHHT(
    context: *HHTContext,
    file_info: *PlatformFileInfo,
) void {
    var handle: PlatformFileHandle = shared.platform.openFile(
        &context.file_group,
        @constCast(file_info),
        @intFromEnum(shared.OpenFileModeFlags.Read),
    );
    var file_buffer: Buffer = .{
        .count = file_info.file_size,
    };
    file_buffer.data = context.temp_arena.pushSize(file_buffer.count, null);
    shared.platform.readDataFromFile(&handle, 0, file_buffer.count, file_buffer.data);
    shared.platform.closeFile(&handle);

    var tokenizer: Tokenizer = .init(file_buffer, .wrapZ(file_info.base_name));

    while (tokenizer.parsing()) {
        const token: Token = tokenizer.getToken();

        // Needed for the simple-preprocessor example.
        // if (token.token_type == .Comment) {
        //     continue;
        // }

        if (token.token_type == .Pound) {
            const directive = tokenizer.getToken();
            if (directive.equals("include")) {
                context.include_depth += 1;
                if (context.include_depth > 16) {
                    const file_name: Token = tokenizer.requireToken(.String);

                    var buf: [4096]u8 = undefined;
                    const length = shared.formatString(buf.len, &buf, "tags/%S", .{file_name.text});
                    const path = buf[0..length];

                    if (shared.platform.getFileByPath(
                        &context.file_group,
                        @ptrCast(path),
                        @intFromEnum(shared.OpenFileModeFlags.Read),
                    )) |included_file_info| {
                        parseHHT(context, included_file_info);
                        //
                    } else {
                        tokenizer.encounteredError(file_name, "Unable to include file.", .{});
                    }
                } else {
                    tokenizer.encounteredError(directive, "Maximum include depth exceeded.", .{});
                }
            } else if (directive.equals("hha")) {
                const hha_stem: Token = tokenizer.requireToken(.String);
                const hha_index: u32 = getOrCreateHHAByStem(context.assets, hha_stem.text, true);
                if (hha_index != 0) {
                    context.hha_stem = hha_stem.text;
                    context.hha_index = hha_index;
                } else {
                    tokenizer.encounteredError(null, "Couldn't open HHA %S for writing.", .{hha_stem.text});
                }
            } else {
                tokenizer.encounteredError(directive, "Unrecongnized directive.", .{});
            }
        } else if (token.token_type == .Identifier) {
            if (context.hha_index != 0) {
                parseTopLevelBlock(&tokenizer, context, token);
            } else {
                tokenizer.encounteredError(token, "Import blocks are not allowed to appear before at least one hha directive.", .{});
            }
        } else if (token.token_type == .EndOfStream) {
            break;
        } else {
            tokenizer.encounteredError(token, "Unexpected top-level token.", .{});
        }
    }
}

fn getOrCreateHHAByStem(assets: *Assets, stem: String, create_if_not_found: bool) u32 {
    var result: u32 = 0;

    var hha_index: u32 = 1;
    while (hha_index < assets.file_count) : (hha_index += 1) {
        const file: *AssetFile = @ptrCast(assets.files + hha_index);
        if (file.stem.equals(stem)) {
            result = hha_index;
            break;
        }
    }

    if (create_if_not_found and result == 0) {
        var file_group = shared.platform.getAllFilesOfTypeBegin(.AssetFile);
        defer shared.platform.getAllFilesOfTypeEnd(&file_group);

        var buf: [4096]u8 = undefined;
        const length = shared.formatString(buf.len, &buf, "data/%S.hha", .{stem});
        const path = buf[0..length];

        var file_info: ?*PlatformFileInfo = shared.platform.getFileByPath(
            &file_group,
            @ptrCast(path),
            @intFromEnum(shared.OpenFileModeFlags.Read) | @intFromEnum(shared.OpenFileModeFlags.Write),
        );
        if (file_info != null) {
            var handle: PlatformFileHandle = shared.platform.openFile(
                &file_group,
                @constCast(file_info.?),
                @intFromEnum(shared.OpenFileModeFlags.Write),
            );

            if (shared.platform.noFileErrors(&handle)) {
                var header: HHAHeader = .{};
                shared.platform.writeDataToFile(&handle, 0, @sizeOf(HHAHeader), &header);
            }
            shared.platform.closeFile(&handle);

            if (shared.platform.noFileErrors(&handle)) {
                // TODO: It would be much nicer if we had a way to refresh the FileInfo here.
                file_info = shared.platform.getFileByPath(
                    &file_group,
                    @ptrCast(path),
                    @intFromEnum(shared.OpenFileModeFlags.Read) | @intFromEnum(shared.OpenFileModeFlags.Write),
                );
                result = assets.initSourceHHA(&file_group, file_info.?);
            }
        }
    }

    return result;
}

fn copyAllInputUpToAndIncluding(context: *HHTContext, open_brace: Token) void {
    _ = context;
    _ = open_brace;
}

fn updateAssetMetadata(
    tokenizer: *Tokenizer,
    assets: *Assets,
    file: *SourceFile,
    fields: *HHTFields,
    grid: *ImportGridTags,
    append_tags: ImportTagArray,
) void {
    if (assets.getFile(file.dest_file_index)) |asset_file| {
        const x_count: u32 = file.asset_indices[0].len;
        const y_count: u32 = file.asset_indices.len;

        var y_index: u32 = 0;
        while (y_index < y_count) : (y_index += 1) {
            var x_index: u32 = 0;
            while (x_index < x_count) : (x_index += 1) {
                const asset_index: u32 = file.asset_indices[y_index][x_index];
                if (asset_index != 0) {
                    const tags: ImportGridTag = grid.tags[y_index][x_index];

                    const asset: *Asset = &assets.assets[asset_index];
                    if (tags.type_id != .None) {
                        if (asset.asset_type == 0) {
                            setAssetType(assets, asset_index, tags.type_id);
                        }
                    } else {
                        _ = stream.outputWithSrc(&file.errors, @src(), "Sprite found in what is required to be a blank tile.\n", .{});
                    }

                    var tags_differ: bool = false;
                    const total_tag_count: u32 = tags.tags.getCount() + append_tags.getCount();

                    if (total_tag_count == (asset.hha.one_past_last_tag_index - asset.hha.first_tag_index)) {
                        var test_tag_index: u32 = asset.hha.first_tag_index;
                        var tag_index: u32 = tags.tags.first_tag_index;
                        while (tag_index < tags.tags.one_past_last_tag_index) : (tag_index += 1) {
                            const source_tag: *HHATag = @ptrCast(assets.tags + tag_index);
                            if (!assets.tags[test_tag_index].equals(source_tag.*)) {
                                tags_differ = true;
                            }
                            test_tag_index += 1;
                        }
                        tag_index = append_tags.first_tag_index;
                        while (tag_index < append_tags.one_past_last_tag_index) : (tag_index += 1) {
                            const source_tag: *HHATag = @ptrCast(assets.tags + tag_index);
                            if (!assets.tags[test_tag_index].equals(source_tag.*)) {
                                tags_differ = true;
                            }
                            test_tag_index += 1;
                        }
                    } else {
                        tags_differ = true;
                    }

                    if (tags_differ) {
                        var builder: TagBuilder = beginTags(assets);
                        var tag_index: u32 = tags.tags.first_tag_index;
                        while (tag_index < tags.tags.one_past_last_tag_index) : (tag_index += 1) {
                            const source_tag: *HHATag = @ptrCast(assets.tags + tag_index);
                            addTag(&builder, source_tag.id, source_tag.value);
                        }
                        tag_index = append_tags.first_tag_index;
                        while (tag_index < append_tags.one_past_last_tag_index) : (tag_index += 1) {
                            const source_tag: *HHATag = @ptrCast(assets.tags + tag_index);
                            addTag(&builder, source_tag.id, source_tag.value);
                        }
                        const combined_tags: ImportGridTag = endTags(&builder, tokenizer, .None);

                        asset.hha.first_tag_index = combined_tags.tags.first_tag_index;
                        asset.hha.one_past_last_tag_index = combined_tags.tags.one_past_last_tag_index;
                        asset_file.modified = true;
                    }

                    updateAssetString(
                        assets,
                        asset_file,
                        fields.name,
                        &asset.annotation.asset_name_count,
                        &asset.annotation.asset_name_offset,
                    );
                    updateAssetString(
                        assets,
                        asset_file,
                        fields.description,
                        &asset.annotation.asset_description_count,
                        &asset.annotation.asset_description_offset,
                    );
                    updateAssetString(
                        assets,
                        asset_file,
                        fields.author,
                        &asset.annotation.author_count,
                        &asset.annotation.author_offset,
                    );
                    updateAssetString(
                        assets,
                        asset_file,
                        file.base_name,
                        &asset.annotation.source_file_base_name_count,
                        &asset.annotation.source_file_base_name_offset,
                    );

                    const asset_errors: Stream = .{};
                    const file_error_stream_size: u32 = @intCast(file.errors.getTotalSize());
                    const asset_error_stream_size: u32 = @intCast(asset_errors.getTotalSize());
                    asset.annotation.error_stream_count = file_error_stream_size + asset_error_stream_size;
                    asset.annotation.error_stream_offset = reserveData(
                        assets,
                        asset_file,
                        asset.annotation.error_stream_count,
                    );
                    writeAssetStream(asset_file, asset.annotation.error_stream_offset, &file.errors);
                    writeAssetStream(
                        asset_file,
                        asset.annotation.error_stream_offset + file_error_stream_size,
                        &asset_errors,
                    );
                }
            }
        }
    }
}

fn parseTopLevelBlock(
    tokenizer: *Tokenizer,
    context: *HHTContext,
    block_token: Token,
) void {
    const temp_arena: *MemoryArena = context.temp_arena;
    const temp_marker: memory.TemporaryMemory = temp_arena.beginTemporaryMemory();
    defer temp_arena.endTemporaryMemory(temp_marker);

    var fields: HHTFields = context.default_fields;
    const is_default: bool = block_token.equals("default");

    var needs_full_rebuild: bool = false;

    var tags: ImportGridTags = .{};
    var import_type: ImportType = .None;
    var match: ?*SourceFile = null;
    var file_info: ?*PlatformFileInfo = null;

    if (!is_default) {
        const file_name: Token = tokenizer.requireToken(.String);

        var buf: [4096]u8 = undefined;
        const sub_dir: []const u8 = "art";
        const length =
            shared.formatString(buf.len, &buf, "sources/%S/%s/%S", .{ context.hha_stem, sub_dir, file_name.text });
        const path = buf[0..length];

        file_info = shared.platform.getFileByPath(
            &context.file_group,
            @ptrCast(path),
            @intFromEnum(shared.OpenFileModeFlags.Read),
        );
        if (file_info != null) {
            match = .getOrCreateFromHashValue(context.assets, @ptrCast(path));

            import_type = parsePieces(context.assets, tokenizer, block_token, &tags);

            if (import_type != .None) {
                if (match.?.file_date != file_info.?.file_date) {
                    needs_full_rebuild = true;
                }
            } else {
                tokenizer.encounteredError(block_token, "Unexpected block type.", .{});
            }
        } else {
            tokenizer.encounteredError(file_name, "File not found (looked in %s)", .{path});
        }
    }

    const open_brace: Token = tokenizer.requireToken(.OpenBrace);
    copyAllInputUpToAndIncluding(context, open_brace);

    var append_tags: ImportTagArray = .{};
    const align_point_written: [ASSET_IMPORT_GRID_MAX][ASSET_IMPORT_GRID_MAX][HHA_ALIGN_POINT_TYPE_COUNT]bool =
        @splat(@splat(@splat(false)));
    _ = align_point_written;
    var align_points: [ASSET_IMPORT_GRID_MAX][ASSET_IMPORT_GRID_MAX][HHA_ALIGN_POINT_TYPE_COUNT]HHAAlignPoint =
        @splat(@splat(@splat(.{})));

    while (tokenizer.parsing()) {
        const token: Token = tokenizer.getToken();
        if (token.token_type == .CloseBrace) {
            if (context.hht_write) {
                // Output the alignment points.
            }
            break;
        } else if (token.equals("Name")) {
            _ = tokenizer.requireToken(.Equals);
            fields.name = tokenizer.requireToken(.String).text;
        } else if (token.equals("Author")) {
            _ = tokenizer.requireToken(.Equals);
            fields.author = tokenizer.requireToken(.String).text;
        } else if (token.equals("Description")) {
            _ = tokenizer.requireToken(.Equals);
            fields.description = tokenizer.requireToken(.String).text;
        } else if (token.equals("Tags")) {
            _ = tokenizer.requireToken(.Equals);
            append_tags = parseTagList(context.assets, tokenizer);
        } else if (token.equals("Align")) {
            _ = tokenizer.requireToken(.OpenBracket);
            const grid_x: i32 = tokenizer.requireIntegerRange(0, ASSET_IMPORT_GRID_MAX - 1).i32;
            _ = tokenizer.requireToken(.Comma);
            const grid_y: i32 = tokenizer.requireIntegerRange(0, ASSET_IMPORT_GRID_MAX - 1).i32;
            const index: i32 = tokenizer.requireIntegerRange(0, HHA_ALIGN_POINT_TYPE_COUNT - 1).i32;
            _ = tokenizer.requireToken(.CloseBracket);
            _ = tokenizer.requireToken(.Equals);

            const position_percent0: i32 = tokenizer.requireIntegerRange(0, std.math.maxInt(u16)).i32;
            _ = tokenizer.requireToken(.Comma);
            const position_percent1: i32 = tokenizer.requireIntegerRange(0, std.math.maxInt(u16)).i32;
            _ = tokenizer.requireToken(.Comma);
            const size: i32 = tokenizer.requireIntegerRange(0, std.math.maxInt(u16)).i32;
            _ = tokenizer.requireToken(.Comma);
            const type0: Token = tokenizer.requireToken(.Identifier);
            var align_type: u16 = @intFromEnum(file_formats.alignPointTypeFromName(type0.text));
            if (align_type != @intFromEnum(HHAAlignPointType.None)) {
                var type1: Token = .{};
                if (tokenizer.optionalToken(.Or)) {
                    type1 = tokenizer.requireToken(.Identifier);
                    if (type1.equals("ToParent")) {
                        align_type |= @intFromEnum(HHAAlignPointType.ToParent);
                    } else {
                        tokenizer.encounteredError(type0, "Expected \"ToParent\".", .{});
                    }
                }

                if (tokenizer.parsing()) {
                    var point: *HHAAlignPoint = &align_points[@intCast(grid_y)][@intCast(grid_x)][@intCast(index)];
                    point.position_percent[0] = @intCast(position_percent0);
                    point.position_percent[1] = @intCast(position_percent1);
                    point.size = @intCast(size);
                    point.align_type = align_type;
                }
            } else {
                tokenizer.encounteredError(type0, "Urecognized alignment point type.", .{});
            }
        } else {
            tokenizer.encounteredError(token, "Expected field name.", .{});
        }

        _ = tokenizer.requireToken(.SemiColon);
        copyAllInputUpToAndIncluding(context, open_brace);
    }

    _ = tokenizer.requireToken(.SemiColon);

    if (tokenizer.parsing()) {
        if (is_default) {
            context.default_fields = fields;
        } else if (match != null) {
            if (match.?.dest_file_index != context.hha_index) {
                match.?.dest_file_index = context.hha_index;
                needs_full_rebuild = true;
            }

            if (needs_full_rebuild) {
                var handle: PlatformFileHandle = shared.platform.openFile(
                    &context.file_group,
                    @constCast(file_info.?),
                    @intFromEnum(shared.OpenFileModeFlags.Read),
                );
                var file_buffer: Buffer = .{
                    .count = file_info.?.file_size,
                };

                file_buffer.data = temp_arena.pushSize(file_buffer.count, null);

                shared.platform.readDataFromFile(&handle, 0, file_buffer.count, file_buffer.data);
                shared.platform.closeFile(&handle);

                // We update this first, because assets that get packed from here on out need to be able to
                // stamp themselves with the right data.
                match.?.file_date = file_info.?.file_date;
                match.?.file_checksum = shared.checksumOf(file_buffer, null);

                const content_stream: Stream = .makeReadStream(file_buffer, &match.?.errors);
                const image = png.parsePNG(temp_arena, content_stream, null);

                switch (import_type) {
                    .Plate => {
                        processPlateImport(context.assets, match.?, image, temp_arena);
                    },
                    .SingleTile => {
                        processSingleTileImport(context.assets, match.?, image, temp_arena);
                    },
                    .MultiTile => {
                        processMultiTileImport(context.assets, match.?, image, temp_arena);
                    },
                    else => unreachable,
                }
            }

            updateAssetMetadata(tokenizer, context.assets, match.?, &fields, &tags, append_tags);
        }
    }
}

fn parseTagList(assets: *Assets, tokenizer: *Tokenizer) ImportTagArray {
    var builder: TagBuilder = beginTags(assets);

    while (tokenizer.parsing()) {
        var token: Token = tokenizer.peekToken();
        if (token.token_type == .SemiColon) {
            break;
        } else if (token.token_type == .Identifier) {
            token = tokenizer.getToken();
            var tag_value: f32 = 1;

            var check: Token = tokenizer.peekToken();
            if (check.token_type == .OpenParen) {
                _ = tokenizer.requireToken(.OpenParen);
                const value: Token = tokenizer.requireToken(.Number);
                tag_value = value.f32;
                _ = tokenizer.requireToken(.CloseParen);
                check = tokenizer.peekToken();
            }

            const tag_id: AssetTagId = file_formats.tagIdFromName(token.text);
            if (tag_id != .None) {
                addTag(&builder, tag_id, tag_value);
            } else {
                tokenizer.encounteredError(
                    token,
                    "Unrecognized tag name: %S.\n",
                    .{token.text.data},
                );
            }

            if (check.token_type == .SemiColon) {
                break;
            } else if (check.token_type == .Comma) {
                _ = tokenizer.requireToken(.Comma);
            } else {
                tokenizer.encounteredError(token, "Expected comma or semicolon.", .{});
            }
        } else if (token.token_type == .Comma) {} else {
            tokenizer.encounteredError(token, "Expected a tag name.", .{});
        }
    }

    const result: ImportTagArray = endTags(&builder, tokenizer, .None).tags;
    return result;
}

fn writeModificationsToAllHHAs(assets: *Assets) void {
    var temp_arena: MemoryArena = .{};
    defer temp_arena.clear();

    var file_index: u32 = 1;
    while (file_index < assets.file_count) : (file_index += 1) {
        const file: *AssetFile = &assets.files[file_index];
        if (file.modified) {
            writeModificationsToHHA(assets, file_index, &temp_arena);
        }
    }
}

pub fn importChangedAssets(assets: *Assets) void {
    if (INTERNAL) {
        var temp_arena: MemoryArena = .{};
        defer temp_arena.clear();

        var context: HHTContext = .{
            .file_group = shared.platform.getAllFilesOfTypeBegin(.HHT),
            .assets = assets,
            .temp_arena = &temp_arena,
        };
        defer shared.platform.getAllFilesOfTypeEnd(&context.file_group);

        var opt_file_info: ?*PlatformFileInfo = context.file_group.first_file_info;
        while (opt_file_info) |file_info| : (opt_file_info = file_info.next) {
            parseHHT(&context, file_info);
        }

        writeModificationsToAllHHAs(assets);
    }
}
