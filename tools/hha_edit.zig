const std = @import("std");
const shared = @import("shared");
const asset = shared.asset;
const file_formats = shared.file_formats;
const file_formats_v0 = shared.file_formats_v0;
const math = shared.math;
const intrinsics = shared.intrinsics;

// Types.
const String = shared.String;
const HHAHeaderV0 = file_formats_v0.HHAHeaderV0;
const HHAAssetTypeV0 = file_formats_v0.HHAAssetTypeV0;
const HHAAssetV0 = file_formats_v0.HHAAssetV0;
const AssetTypeIdV0 = file_formats_v0.AssetTypeIdV0;

const HHAHeader = file_formats.HHAHeader;
const HHAAssetType = file_formats.HHAAssetType;
const HHAAsset = file_formats.HHAAsset;
const HHATag = file_formats.HHATag;
const HHAAnnotation = file_formats.HHAAnnotation;
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;
const HHAFont = file_formats.HHAFont;
const HHAFontGlyph = file_formats.HHAFontGlyph;
const AssetMemoryHeader = asset.AssetMemoryHeader;

pub const std_options: std.Options = .{
    .logFn = myLogFn,
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    if (level == .err) {
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.fs.File.stderr().deprecatedWriter();
        nosuspend stderr.print(format ++ "\n", args) catch return;
    } else {
        var stdout_buf: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writerStreaming(&stdout_buf);
        var stdout = &stdout_writer.interface;
        stdout.print(format ++ "\n", args) catch return;
        stdout.flush() catch return;
    }
}

const LoadedHHAAnnotation = struct {
    source_file_date: u64 align(1) = 0,
    source_file_checksum: u64 align(1) = 0,
    sprite_sheet_x: u32 align(1) = 0,
    sprite_sheet_y: u32 align(1) = 0,

    source_file_base_name: String = .empty,
    asset_name: String = .empty,
    asset_description: String = .empty,
    author: String = .empty,
};

const LoadedHHA = struct {
    valid: bool = false,
    had_annotations: bool = false,
    source_file_name: []const u8 = "",

    magic_value: u32 = 0,
    source_version: u32 = 0,

    tag_count: u32 = 0,
    tags: [*]HHATag = undefined,

    asset_count: u32 = 0,
    assets: [*]HHAAsset = undefined,
    annotations: [*]LoadedHHAAnnotation = undefined,

    data_store: []const u8 = undefined,
};

fn readEntireFile(file: std.fs.File, allocator: std.mem.Allocator) ![]const u8 {
    var result: []const u8 = undefined;

    _ = try file.seekTo(0);

    result = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, .@"32", 0);

    return result;
}

const type_from_id = [_]struct { HHAAssetType, AssetTypeIdV0 }{
    .{ .None, .None },

    .{ .Bitmap, .Shadow },
    .{ .Bitmap, .Tree },
    .{ .Bitmap, .Sword },
    .{ .Bitmap, .Rock },

    .{ .Bitmap, .Grass },
    .{ .Bitmap, .Tuft },
    .{ .Bitmap, .Stone },

    .{ .Bitmap, .Head },
    .{ .Bitmap, .Cape },
    .{ .Bitmap, .Torso },

    .{ .Font, .Font },
    .{ .Bitmap, .FontGlyph },

    .{ .Sound, .Bloop },
    .{ .Sound, .Crack },
    .{ .Sound, .Drop },
    .{ .Sound, .Glide },
    .{ .Sound, .Music },
    .{ .Sound, .Puhp },

    .{ .Bitmap, .OpeningCutscene },

    .{ .Bitmap, .Hand },
};

fn removeExtension(file_name: *String) void {
    var new_count: usize = file_name.count;
    var index: usize = 0;
    while (index < file_name.count) : (index += 1) {
        if (file_name.data[index] == '.') {
            new_count = index;
        } else if (file_name.data[index] == '/' or file_name.data[index] == '\\') {
            new_count = file_name.count;
        }
    }
    file_name.count = new_count;
}

fn removePath(file_name: *String) void {
    var new_start: usize = 0;
    var index: usize = 0;
    while (index < file_name.count) : (index += 1) {
        if (file_name.data[index] == '/' or file_name.data[index] == '\\') {
            new_start = index + 1;
        }
    }
    file_name.data += new_start;
    file_name.count -= new_start;
}

fn readHHAV0(source_file: std.fs.File, hha: *LoadedHHA, allocator: std.mem.Allocator) void {
    _ = source_file;

    const header: *const HHAHeaderV0 = @ptrCast(hha.data_store);
    const source_tags: [*]HHATag = @ptrFromInt(@intFromPtr(hha.data_store.ptr) + header.tags);
    const source_asset_types: [*]HHAAssetTypeV0 = @ptrFromInt(@intFromPtr(hha.data_store.ptr) + header.asset_types);
    const source_assets: [*]HHAAssetV0 = @ptrFromInt(@intFromPtr(hha.data_store.ptr) + header.assets);

    hha.tag_count = header.tag_count + header.asset_count - 1;
    hha.tags = @ptrCast(allocator.alloc(HHATag, hha.tag_count) catch unreachable);

    hha.asset_count = header.asset_count;
    hha.assets = @ptrCast(allocator.alloc(HHAAsset, hha.asset_count) catch unreachable);
    hha.annotations = @ptrCast(allocator.alloc(LoadedHHAAnnotation, hha.asset_count) catch unreachable);

    var default_annotation: LoadedHHAAnnotation = .{
        .source_file_base_name = .fromSlice(hha.source_file_name),
        .asset_name = .fromSlice("UNKNOWN"),
        .asset_description = .fromSlice("imported by readHHAV0"),
        .author = .fromSlice("hha-edit.exe"),
    };
    removePath(&default_annotation.source_file_base_name);
    removeExtension(&default_annotation.source_file_base_name);

    hha.annotations[0] = .{};
    hha.assets[0] = .{};
    hha.tags[0] = .{};

    var dest_tag_index: u32 = 1;
    var asset_type_index: u32 = 0;
    while (asset_type_index < header.asset_type_count) : (asset_type_index += 1) {
        const asset_type: HHAAssetTypeV0 = source_asset_types[asset_type_index];
        var type_info = type_from_id[0];
        if (asset_type.type_id < type_from_id.len) {
            type_info = type_from_id[asset_type.type_id];
        }

        var asset_index: u32 = asset_type.first_asset_index;
        while (asset_index < asset_type.one_past_last_asset_index) : (asset_index += 1) {
            const source_asset: *HHAAssetV0 = &source_assets[asset_index];
            var dest_asset: *HHAAsset = &hha.assets[asset_index];
            dest_asset.* = .{};

            if (asset_index < hha.asset_count) {
                dest_asset.first_tag_index = dest_tag_index;
                var tag_index: u32 = source_asset.first_tag_index;
                while (tag_index < source_asset.one_past_last_tag_index) : (tag_index += 1) {
                    hha.tags[dest_tag_index] = source_tags[tag_index];
                    dest_tag_index += 1;
                }
                hha.tags[dest_tag_index].id = .BasicCategory;
                hha.tags[dest_tag_index].value = @floatFromInt(asset_type.type_id);
                dest_tag_index += 1;
                dest_asset.one_past_last_tag_index = dest_tag_index;

                dest_asset.data_offset = source_asset.data_offset;
                dest_asset.type = type_info[0];

                switch (dest_asset.type) {
                    .Bitmap => {
                        const bitmap: *HHABitmap = &source_asset.info.bitmap;
                        dest_asset.info.bitmap = bitmap.*;
                        dest_asset.data_size = 4 * bitmap.dim[0] * bitmap.dim[1];
                    },
                    .Sound => {
                        const sound: *HHASound = &source_asset.info.sound;
                        dest_asset.info.sound = sound.*;
                        dest_asset.data_size = sound.sample_count * sound.channel_count * @sizeOf(i16);
                    },
                    .Font => {
                        const font: *HHAFont = &source_asset.info.font;
                        dest_asset.info.font = font.*;
                        const horizontal_advance_size: u32 = @sizeOf(f32) * font.glyph_count * font.glyph_count;
                        const glyphs_size: u32 = font.glyph_count * @sizeOf(HHAFontGlyph);
                        const unicode_map_size: u32 = @sizeOf(u16) * font.one_past_highest_code_point;
                        const size_data: u32 = glyphs_size + horizontal_advance_size;
                        dest_asset.data_size = size_data + @sizeOf(AssetMemoryHeader) + unicode_map_size;
                    },
                    else => {
                        std.log.err("ERROR: Asset {d} has illegal type.", .{asset_index});
                    },
                }
            } else {
                std.log.err("ERROR: Asset index {d} out of range.", .{asset_index});
            }

            hha.annotations[asset_index] = default_annotation;
            hha.annotations[asset_index].asset_name = .fromSlice(@tagName(type_info[1]));
        }
    }
}

fn refString(d: [*]const u8, count: u32, offset: u64) String {
    return .{
        .count = count,
        .data = @constCast(d + offset),
    };
}

fn readHHAV1(source_file: std.fs.File, hha: *LoadedHHA, allocator: std.mem.Allocator) void {
    _ = source_file;

    const header: *const HHAHeader = @ptrCast(hha.data_store);
    const d: [*]const u8 = @ptrCast(hha.data_store.ptr);

    hha.tag_count = header.tag_count;
    hha.tags = @ptrCast(@constCast(d + header.tags));

    hha.asset_count = header.asset_count;
    hha.assets = @ptrCast(@alignCast(@constCast(d + header.assets)));

    if (header.annotations != 0) {
        hha.annotations = @ptrCast(allocator.alloc(LoadedHHAAnnotation, hha.asset_count) catch undefined);

        var annotation_index: u32 = 0;
        while (annotation_index < hha.asset_count) : (annotation_index += 1) {
            const source_annotation: [*]HHAAnnotation =
                @as([*]HHAAnnotation, @ptrCast(@constCast(d + header.annotations))) + annotation_index;
            const dest_annotation: [*]LoadedHHAAnnotation = hha.annotations + annotation_index;

            dest_annotation[0].source_file_date = source_annotation[0].source_file_date;
            dest_annotation[0].source_file_checksum = source_annotation[0].source_file_checksum;
            dest_annotation[0].sprite_sheet_x = source_annotation[0].sprite_sheet_x;
            dest_annotation[0].sprite_sheet_y = source_annotation[0].sprite_sheet_y;

            dest_annotation[0].source_file_base_name = refString(
                d,
                source_annotation[0].source_file_base_name_count,
                source_annotation[0].source_file_base_name_offset,
            );
            dest_annotation[0].asset_name = refString(
                d,
                source_annotation[0].asset_name_count,
                source_annotation[0].asset_name_offset,
            );
            dest_annotation[0].asset_description = refString(
                d,
                source_annotation[0].asset_description_count,
                source_annotation[0].asset_description_offset,
            );
            dest_annotation[0].author = refString(
                d,
                source_annotation[0].author_count,
                source_annotation[0].author_offset,
            );
        }

        hha.had_annotations = true;
    }
}

fn readHHA(source_file_name: []const u8, allocator: std.mem.Allocator) ?*LoadedHHA {
    const result: ?*LoadedHHA = allocator.create(LoadedHHA) catch null;
    const null_hha: LoadedHHA = .{};
    result.?.* = null_hha;
    result.?.source_file_name = source_file_name;

    if (std.fs.cwd().openFile(source_file_name, .{ .mode = .read_only })) |source_file| {
        defer source_file.close();

        result.?.data_store = readEntireFile(source_file, allocator) catch undefined;

        result.?.magic_value = @as([*]const u32, @ptrCast(@alignCast(result.?.data_store)))[0];
        result.?.source_version = @as([*]const u32, @ptrCast(@alignCast(result.?.data_store)))[1];

        if (result.?.magic_value == file_formats.HHA_MAGIC_VALUE) {
            if (result.?.source_version == 0) {
                readHHAV0(source_file, result.?, allocator);
                result.?.valid = true;
            } else if (result.?.source_version == 1) {
                readHHAV1(source_file, result.?, allocator);
                result.?.valid = true;
            } else {
                std.log.err("Unrecognized HHA version: {d}", .{result.?.source_version});
            }
        } else {
            std.log.err("Magic value is not HHAF.", .{});
        }
    } else |err| {
        std.log.err("Unable to open file {s} for reading. {s}", .{ source_file_name, @errorName(err) });
    }

    return result;
}

fn writeBlock(size: u32, source: *anyopaque, dest_file: *const std.fs.File) u64 {
    const result: u64 = dest_file.getPos() catch unreachable;

    const bytes: [*]const u8 = @ptrCast(source);
    dest_file.writeAll(bytes[0..size]) catch unreachable;

    return result;
}

fn writeString(string: String, count: *align(1) u32, dest_file: *const std.fs.File) u64 {
    count.* = @intCast(string.count);
    const result: u64 = writeBlock(@intCast(string.count), string.data, dest_file);
    return result;
}

fn writeHHAV1(
    source: *LoadedHHA,
    dest_file: *const std.fs.File,
    allocator: std.mem.Allocator,
    include_annotations: bool,
) void {
    var header: HHAHeader = .{};

    header.tag_count = source.tag_count;
    header.asset_count = source.asset_count;

    const dest_tags_size: u32 = source.tag_count * @sizeOf(HHATag);
    const dest_assets_size: u32 = source.asset_count * @sizeOf(HHAAsset);
    const dest_annotations_size: u32 = source.asset_count * @sizeOf(HHAAnnotation);

    const dest_tags: [*]HHATag = @ptrCast(allocator.alloc(HHATag, header.tag_count) catch undefined);
    const dest_assets: [*]HHAAsset = @ptrCast(allocator.alloc(HHAAsset, header.asset_count) catch undefined);
    const dest_annotations: [*]HHAAnnotation = @ptrCast(allocator.alloc(HHAAnnotation, header.asset_count) catch undefined);

    const header_size: u32 = @sizeOf(HHAHeader);
    dest_file.seekTo(header_size) catch unreachable;

    var tag_index: u32 = 0;
    while (tag_index < source.tag_count) : (tag_index += 1) {
        const source_tag: *HHATag = &source.tags[tag_index];
        const dest_tag: *HHATag = &dest_tags[tag_index];
        dest_tag.* = source_tag.*;
    }

    var asset_index: u32 = 0;
    while (asset_index < source.asset_count) : (asset_index += 1) {
        const source_asset: *HHAAsset = &source.assets[asset_index];
        const source_annotation: *LoadedHHAAnnotation = &source.annotations[asset_index];

        const dest_asset: *HHAAsset = &dest_assets[asset_index];
        const dest_annotation: *HHAAnnotation = &dest_annotations[asset_index];

        dest_asset.* = source_asset.*;
        dest_asset.data_offset = writeBlock(
            dest_asset.data_size,
            @ptrFromInt(@intFromPtr(source.data_store.ptr) + source_asset.data_offset),
            dest_file,
        );

        dest_annotation.* = .{
            .source_file_date = source_annotation.source_file_date,
            .source_file_checksum = source_annotation.source_file_checksum,
            .sprite_sheet_x = source_annotation.sprite_sheet_x,
            .sprite_sheet_y = source_annotation.sprite_sheet_y,
        };

        dest_annotation.source_file_base_name_offset = writeString(
            source_annotation.source_file_base_name,
            &dest_annotation.source_file_base_name_count,
            dest_file,
        );

        dest_annotation.asset_name_offset = writeString(
            source_annotation.asset_name,
            &dest_annotation.asset_name_count,
            dest_file,
        );

        dest_annotation.asset_description_offset = writeString(
            source_annotation.asset_description,
            &dest_annotation.asset_description_count,
            dest_file,
        );

        dest_annotation.author_offset = writeString(
            source_annotation.author,
            &dest_annotation.author_count,
            dest_file,
        );
    }

    header.tags = writeBlock(dest_tags_size, dest_tags, dest_file);
    header.assets = writeBlock(dest_assets_size, dest_assets, dest_file);
    if (include_annotations) {
        header.annotations = writeBlock(dest_annotations_size, dest_annotations, dest_file);
    }

    dest_file.seekTo(0) catch unreachable;
    const check_header_location: u64 = writeBlock(header_size, &header, dest_file);
    std.debug.assert(check_header_location == 0);
}

fn writeHHA(opt_source: ?*LoadedHHA, dest_file_name: []const u8, allocator: std.mem.Allocator) void {
    if (!fileExists(dest_file_name)) {
        if (opt_source) |source| {
            if (source.valid) {
                if (std.fs.cwd().createFile(dest_file_name, .{})) |dest_file| {
                    writeHHAV1(source, &dest_file, allocator, true);
                } else |err| {
                    std.log.err("Unable to open file {s} for writing. {s}", .{ dest_file_name, @errorName(err) });
                }
            } else {
                std.log.err("Source HHA was not valid, so not writing to {s}.", .{dest_file_name});
            }
        }
    } else {
        std.log.err("{s} must not exist.", .{dest_file_name});
    }
}

fn fileExists(file_name: []const u8) bool {
    var result: bool = false;

    const opt_file: ?std.fs.File = std.fs.cwd().openFile(file_name, .{ .mode = .read_only }) catch null;
    defer if (opt_file) |file| file.close();

    if (opt_file != null) {
        result = true;
    }

    return result;
}

fn printTag(hha: *LoadedHHA, tag_index: u32) void {
    if (tag_index < hha.tag_count) {
        const tag: *HHATag = &hha.tags[tag_index];
        std.log.info("                   {s} = {d}", .{ @tagName(tag.id), tag.value });
    } else {
        std.log.err("TAG INDEX OVERFLOW!", .{});
    }
}

fn printHeaderInfo(hha: *LoadedHHA) void {
    std.log.info("    Header:", .{});
    std.log.info("        Magic value: {s}", .{std.mem.toBytes(hha.magic_value)[0..4]});
    std.log.info("        Version: {d}", .{hha.source_version});
    std.log.info("        Assets: {d}", .{hha.asset_count});
    std.log.info("        Tag count: {d}", .{hha.tag_count});
    std.log.info("        Annotations: {s}", .{if (hha.had_annotations) "yes" else "no"});
}

fn printContents(hha: *LoadedHHA) void {
    std.log.info("    Assets:", .{});
    var asset_index: u32 = 1;
    while (asset_index < hha.asset_count) : (asset_index += 1) {
        const hha_asset: *HHAAsset = @ptrCast(hha.assets + asset_index);
        const an: *LoadedHHAAnnotation = @ptrCast(hha.annotations + asset_index);
        std.log.info("        [{d}] {s} {s} {d},{d}", .{
            asset_index,
            an.asset_name.toSlice(),
            an.source_file_base_name.toSlice(),
            an.sprite_sheet_x,
            an.sprite_sheet_y,
        });

        if (an.asset_description.count > 0) {
            std.log.info("            Description: {s}", .{an.asset_description.toSlice()});
        }
        if (an.author.count > 0) {
            std.log.info("            Author: {s}", .{an.author.toSlice()});
        }

        std.log.info("            From: {s} {s} {d},{d} (date: {d}, checksum: {d})", .{
            an.asset_name.toSlice(),
            an.source_file_base_name.toSlice(),
            an.sprite_sheet_x,
            an.sprite_sheet_y,
            an.source_file_date,
            an.source_file_checksum,
        });

        std.log.info("            Data: {d} bytes at {d}", .{ hha_asset.data_size, hha_asset.data_offset });

        if (hha.tag_count > 0) {
            std.log.info("            Tags: {d} at {d}", .{
                hha_asset.one_past_last_tag_index - hha_asset.first_tag_index,
                hha_asset.first_tag_index,
            });

            var tag_index: u32 = hha_asset.first_tag_index;
            while (tag_index < hha_asset.one_past_last_tag_index) : (tag_index += 1) {
                std.log.info("                [{d}]:", .{tag_index});
                printTag(hha, tag_index);
            }
        }

        switch (hha_asset.type) {
            .Bitmap => {
                const bitmap: *HHABitmap = &hha_asset.info.bitmap;
                std.log.info("            Type: {d}x{d} Bitmap: ({d})", .{
                    bitmap.dim[0],
                    bitmap.dim[1],
                    @intFromEnum(hha_asset.type),
                });
                std.log.info("                Alignment: {d},{d}", .{
                    bitmap.alignment_percentage[0],
                    bitmap.alignment_percentage[1],
                });
            },
            .Font => {
                const font: *HHAFont = &hha_asset.info.font;
                std.log.info("            Type: Font: ({d})", .{@intFromEnum(hha_asset.type)});
                std.log.info("                Glyphs: {d} (one past highest codepoint: {d}", .{
                    font.glyph_count,
                    font.one_past_highest_code_point,
                });
                std.log.info("                Ascender: {d}", .{font.ascender_height});
                std.log.info("                Descender: {d}", .{font.descender_height});
                std.log.info("                External leading: {d}", .{font.external_leading});
            },
            .Sound => {
                const sound: *HHASound = &hha_asset.info.sound;
                std.log.info("            Type: {d}x{d} {s} Sound: ({d})", .{
                    sound.sample_count,
                    sound.channel_count,
                    @tagName(sound.chain),
                    @intFromEnum(hha_asset.type),
                });
            },
            else => {
                std.log.info("            Type: UKNOWN: ({d})", .{@intFromEnum(hha_asset.type)});
            },
        }
    }

    std.log.info("    Tags:", .{});
    var tag_index: u32 = 1;
    while (tag_index < hha.tag_count) : (tag_index += 1) {
        std.log.info("        [{d}]:", .{tag_index});
        printTag(hha, tag_index);
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var print_usage: bool = false;

    if (args.len == 4) {
        if (std.mem.eql(u8, args[1], "-rewrite")) {
            const source_file_name: []const u8 = args[2];
            const dest_file_name: []const u8 = args[3];

            const hha: ?*LoadedHHA = readHHA(source_file_name, allocator);
            writeHHA(hha, dest_file_name, allocator);
        } else {
            print_usage = true;
        }
    } else if (args.len == 3) {
        if (std.mem.eql(u8, args[1], "-info")) {
            const file_name: []const u8 = args[2];

            if (readHHA(file_name, allocator)) |hha| {
                std.log.info("{s}", .{hha.source_file_name});
                printHeaderInfo(hha);
            }
        } else if (std.mem.eql(u8, args[1], "-dump")) {
            const file_name: []const u8 = args[2];

            if (readHHA(file_name, allocator)) |hha| {
                std.log.info("{s}", .{hha.source_file_name});
                printHeaderInfo(hha);
                printContents(hha);
            }
        } else if (std.mem.eql(u8, args[1], "-create")) {
            const file_name: []const u8 = args[2];

            if (!fileExists(file_name)) {
                const opt_dest: ?std.fs.File = std.fs.cwd().openFile(file_name, .{ .mode = .write_only }) catch null;
                defer if (opt_dest) |dest| dest.close();

                if (std.fs.cwd().createFile(file_name, .{})) |dest| {
                    const header: HHAHeader = .{
                        .tag_count = 0,
                        .asset_count = 0,
                    };

                    var buf: [1024]u8 = undefined;
                    var file_writer = dest.writer(&buf);
                    const writer = &file_writer.interface;

                    try writer.writeAll(std.mem.asBytes(&header)[0..@sizeOf(HHAHeader)]);
                    try writer.flush();
                } else |err| {
                    std.log.err("Unable to open file {s} for writing. {s}", .{ file_name, @errorName(err) });
                }
            } else {
                std.log.err("File {s} already exists.", .{file_name});
            }
        } else {
            print_usage = true;
        }
    } else {
        print_usage = true;
    }

    if (print_usage) {
        std.log.err("Usage: {s} -create (dest.hha)", .{args[0]});
        std.log.err("Usage: {s} -rewrite (source.hha) (dest.hha)", .{args[0]});
        std.log.err("Usage: {s} -info (source.hha)", .{args[0]});
        std.log.err("Usage: {s} -dump (source.hha)", .{args[0]});
    }
}
