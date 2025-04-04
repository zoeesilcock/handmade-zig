const std = @import("std");
const shared = @import("shared");
const file_formats = @import("file_formats");
const math = shared.math;
const intrinsics = shared.intrinsics;

pub const UNICODE = true;
const USE_FONTS_FROM_WINDOWS = true;
const ASSET_TYPE_ID_COUNT = file_formats.ASSET_TYPE_ID_COUNT;

const ONE_PAST_MAX_FONT_CODE_POINT: u33 = 0x10FFFF + 1;
const MAX_FONT_WIDTH: u32 = 1024;
const MAX_FONT_HEIGHT: u32 = 1024;

var global_font_device_context: ?win32.CreatedHDC = null;
var opt_global_bits: ?*anyopaque = null;

const c = @cImport({
    @cInclude("stb_truetype.h");
});

const win32 = struct {
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").foundation;
};

// Types.
const AssetTypeId = file_formats.AssetTypeId;
const AssetFontType = file_formats.AssetFontType;
const AssetTagId = file_formats.AssetTagId;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAssetType = file_formats.HHAAssetType;
const HHAAsset = file_formats.HHAAsset;
const HHABitmap = file_formats.HHABitmap;
const HHASoundChain = file_formats.HHASoundChain;
const HHASound = file_formats.HHASound;
const HHAFont = file_formats.HHAFont;
const HHAFontGlyph = file_formats.HHAFontGlyph;
const BitmapId = file_formats.BitmapId;
const FontId = file_formats.FontId;
const SoundId = file_formats.SoundId;
const Color = math.Color;

// File formats.
const EntireFile = struct {
    content_size: u32 = 0,
    contents: []const u8 = undefined,
};

fn readEntireFile(file_name: []const u8, allocator: std.mem.Allocator) EntireFile {
    var result = EntireFile{};

    if (std.fs.cwd().openFile(file_name, .{ .mode = .read_only })) |file| {
        defer file.close();

        _ = file.seekFromEnd(0) catch undefined;
        result.content_size = @as(u32, @intCast(file.getPos() catch 0));
        _ = file.seekTo(0) catch undefined;

        const buffer = file.readToEndAlloc(allocator, std.math.maxInt(u32)) catch "";
        result.contents = buffer;
    } else |err| {
        std.debug.print("Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
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

const LoadedBitmap = struct {
    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
    memory: ?[*]void,
    free: []u8,
};

fn loadBMP(
    file_name: []const u8,
    allocator: std.mem.Allocator,
) ?LoadedBitmap {
    var result: ?LoadedBitmap = null;
    const read_result = readEntireFile(file_name, allocator);

    if (read_result.content_size > 0) {
        const header = @as(*BitmapHeader, @ptrCast(@alignCast(@constCast(read_result.contents))));

        std.debug.assert(header.height >= 0);
        std.debug.assert(header.compression == 3);

        result = LoadedBitmap{
            .free = @constCast(read_result.contents),
            .memory = @as([*]void, @ptrCast(@constCast(read_result.contents))) + header.bitmap_offset,
            .width = header.width,
            .height = header.height,
        };

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

        var source_dest: [*]align(@alignOf(u8)) u32 = @ptrCast(result.?.memory);
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
                texel = math.sRGB255ToLinear1(texel);

                _ = texel.setRGB(texel.rgb().scaledTo(texel.a()));

                texel = math.linear1ToSRGB255(texel);

                source_dest[0] = texel.packColor1();

                source_dest += 1;
            }
        }
    }

    result.?.pitch = result.?.width * shared.BITMAP_BYTES_PER_PIXEL;

    if (false) {
        result.?.pitch = -result.?.width * shared.BITMAP_BYTES_PER_PIXEL;
        const offset: usize = @intCast(-result.?.pitch * (result.?.height - 1));
        result.?.memory = @ptrCast(@as([*]u8, @ptrCast(result.?.memory)) + offset);
    }

    return result;
}

const LoadedFont = struct {
    win32_handle: win32.HFONT = undefined,
    text_metrics: win32.TEXTMETRICW = undefined,

    glyphs: []HHAFontGlyph,
    horizontal_advance: []f32,

    min_code_point: u32 = 0,
    max_code_point: u32 = 0,

    glyph_count: u32 = 0,
    max_glyph_count: u32 = 0,

    glyph_index_from_code_point: []u32,
    one_past_highest_code_point: u32 = 0,
};

fn initializeFontDC() void {
    global_font_device_context = win32.CreateCompatibleDC(win32.GetDC(null));

    const info = win32.BITMAPINFO{ .bmiHeader = .{
        .biSize = @sizeOf(win32.BITMAPINFOHEADER),
        .biWidth = MAX_FONT_WIDTH,
        .biHeight = MAX_FONT_HEIGHT,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
        .biSizeImage = 0,
        .biXPelsPerMeter = 0,
        .biYPelsPerMeter = 0,
        .biClrUsed = 0,
        .biClrImportant = 0,
    }, .bmiColors = .{
        win32.RGBQUAD{
            .rgbBlue = 0,
            .rgbGreen = 0,
            .rgbRed = 0,
            .rgbReserved = 0,
        },
    } };
    const bitmap = win32.CreateDIBSection(global_font_device_context, &info, win32.DIB_RGB_COLORS, &opt_global_bits, null, 0);

    // const bitmap = win32.CreateCompatibleBitmap(global_font_device_context, 1024, 1024);
    _ = win32.SelectObject(global_font_device_context, bitmap);
    _ = win32.SetBkColor(global_font_device_context, 0x000000);
}

fn loadFont(
    allocator: std.mem.Allocator,
    file_name: []const u8,
    font_name: []const u8,
    pixel_height: i32,
) *LoadedFont {
    var font: *LoadedFont = allocator.create(LoadedFont) catch unreachable;

    _ = win32.AddFontResourceExA(@ptrCast(file_name), .PRIVATE, null);
    font.win32_handle = win32.CreateFontA(
        pixel_height,
        0,
        0,
        0,
        win32.FW_NORMAL,
        0,
        0,
        0,
        win32.DEFAULT_CHARSET,
        .DEFAULT_PRECIS,
        win32.CLIP_DEFAULT_PRECIS,
        .ANTIALIASED_QUALITY,
        win32.FF_DONTCARE,
        @ptrCast(font_name),
    ).?;

    _ = win32.SelectObject(global_font_device_context, font.win32_handle);
    _ = win32.GetTextMetricsW(global_font_device_context, &font.text_metrics);

    font.min_code_point = std.math.maxInt(u32);
    font.max_code_point = 0;

    // 5k characters should be more than enough for anybody.
    font.max_glyph_count = 5000;
    font.glyph_count = 0;
    font.one_past_highest_code_point = 0;

    const glyph_index_from_code_point_size: u32 = ONE_PAST_MAX_FONT_CODE_POINT * @sizeOf(u32);
    font.glyph_index_from_code_point = allocator.alloc(u32, glyph_index_from_code_point_size) catch unreachable;
    @memset(font.glyph_index_from_code_point, 0);

    font.glyphs = (allocator.alloc(HHAFontGlyph, font.max_glyph_count) catch unreachable);
    font.horizontal_advance = (allocator.alloc(f32, font.max_glyph_count * font.max_glyph_count) catch unreachable);
    @memset(font.horizontal_advance, 0);

    // Reserve space for the null glyph.
    font.glyph_count = 1;
    font.glyphs[0].unicode_code_point = 0;
    font.glyphs[0].bitmap = undefined;

    return font;
}

fn finalizeFontKerning(allocator: std.mem.Allocator, font: *LoadedFont) void {
    _ = win32.SelectObject(global_font_device_context, font.win32_handle);

    const kerning_pair_count = win32.GetKerningPairsW(global_font_device_context, 0, null);
    const kerning_pairs = allocator.alloc(win32.KERNINGPAIR, kerning_pair_count) catch unreachable;
    defer allocator.free(kerning_pairs);
    _ = win32.GetKerningPairsW(global_font_device_context, kerning_pair_count, kerning_pairs.ptr);

    var kerning_pair_index: u32 = 0;
    while (kerning_pair_index < kerning_pair_count) : (kerning_pair_index += 1) {
        const pair = kerning_pairs[kerning_pair_index];

        if (pair.wFirst < ONE_PAST_MAX_FONT_CODE_POINT and pair.wSecond < ONE_PAST_MAX_FONT_CODE_POINT) {
            const first = font.glyph_index_from_code_point[pair.wFirst];
            const second = font.glyph_index_from_code_point[pair.wSecond];

            if (first != 0 and second != 0) {
                font.horizontal_advance[first * font.max_glyph_count + second] += @floatFromInt(pair.iKernAmount);
            }
        }
    }
}

fn freeFont(allocator: std.mem.Allocator, font: *LoadedFont) void {
    _ = win32.DeleteObject(font.win32_handle);
    allocator.free(font.glyphs);
    allocator.free(font.horizontal_advance);
    allocator.free(font.glyph_index_from_code_point);
    allocator.destroy(font);
}

fn loadGlyphBMP(
    font: *LoadedFont,
    code_point: u32,
    allocator: std.mem.Allocator,
    asset: *HHAAsset,
) ?LoadedBitmap {
    var result: ?LoadedBitmap = null;
    const glyph_index: u32 = font.glyph_index_from_code_point[code_point];

    if (USE_FONTS_FROM_WINDOWS) {
        _ = win32.SelectObject(global_font_device_context, font.win32_handle);

        if (opt_global_bits) |bits| {
            // Clear bits to black.
            const byte_count: usize = MAX_FONT_WIDTH * MAX_FONT_HEIGHT;
            @memset(@as([*]u32, @ptrCast(@alignCast(bits)))[0..byte_count], 0x00);
        }

        const cheese_point: []const u16 = &[_]u16{@intCast(code_point)};

        var size: win32.SIZE = undefined;
        _ = win32.GetTextExtentPoint32W(global_font_device_context, @ptrCast(cheese_point), 1, &size);

        const pre_step_x: i32 = 128;

        var bound_width: i32 = size.cx + 2 * pre_step_x;
        if (bound_width > MAX_FONT_WIDTH) {
            bound_width = MAX_FONT_WIDTH;
        }
        var bound_height: i32 = size.cy;
        if (bound_height > MAX_FONT_HEIGHT) {
            bound_height = MAX_FONT_HEIGHT;
        }

        // _ = win32.PatBlt(global_font_device_context, 0, 0, width, height, win32.BLACKNESS);
        // _ = win32.SetBkMode(global_font_device_context, .TRANSPARENT);
        _ = win32.SetTextColor(global_font_device_context, 0xffffff);
        _ = win32.TextOutW(global_font_device_context, pre_step_x, 0, @ptrCast(cheese_point), 1);

        var min_x: i32 = 10000;
        var min_y: i32 = 10000;
        var max_x: i32 = -10000;
        var max_y: i32 = -10000;

        if (opt_global_bits) |bits| {
            { // Calculate extents of glyph.
                var row: [*]u32 = @as([*]u32, @ptrCast(@alignCast(bits))) + (MAX_FONT_HEIGHT - 1) * MAX_FONT_WIDTH;
                var y: i32 = 0;
                while (y < bound_height) : (y += 1) {
                    var pixel = row;
                    var x: i32 = 0;
                    while (x < bound_width) : (x += 1) {
                        // const ref_pixel = win32.GetPixel(global_font_device_context, x, y);
                        // std.debug.assert(pixel[0] == ref_pixel);

                        if (pixel[0] != 0) {
                            if (min_x > x) {
                                min_x = x;
                            }
                            if (min_y > y) {
                                min_y = y;
                            }
                            if (max_x < x) {
                                max_x = x;
                            }
                            if (max_y < y) {
                                max_y = y;
                            }
                        }

                        pixel += 1;
                    }

                    row -= MAX_FONT_WIDTH;
                }
            }

            var kerning_change: f32 = 0;
            if (min_x <= max_x) {
                const width = (max_x - min_x) + 1;
                const height = (max_y - min_y) + 1;

                result = LoadedBitmap{
                    .free = undefined,
                    .memory = undefined,
                    .width = width + 2,
                    .height = height + 2,
                };
                result.?.pitch = result.?.width * shared.BITMAP_BYTES_PER_PIXEL;
                result.?.free = allocator.alloc(u8, @intCast(@as(i32, @intCast(result.?.height)) * result.?.pitch)) catch unreachable;
                @memset(result.?.free, 0);
                result.?.memory = @ptrCast(@constCast(result.?.free));

                var dest_row: [*]u8 = @as([*]u8, @ptrCast(result.?.memory.?)) + @as(usize, @intCast((result.?.height - 1 - 1) * result.?.pitch));
                var source_row: [*]u32 = @as([*]u32, @ptrCast(@alignCast(bits))) + (MAX_FONT_HEIGHT - 1 - @as(u32, @intCast(min_y))) * MAX_FONT_WIDTH;

                var y: i32 = min_y;
                while (y <= max_y) : (y += 1) {
                    var source: [*]u32 = source_row + @as(u32, @intCast(min_x));
                    var dest: [*]u32 = @as([*]u32, @ptrCast(@alignCast(dest_row))) + 1;

                    var x: i32 = min_x;
                    while (x <= max_x) : (x += 1) {
                        // const pixel = win32.GetPixel(global_font_device_context, @intCast(x), @intCast(y));
                        // std.debug.assert(pixel == source[0]);

                        const gray: f32 = @as(f32, @floatFromInt(source[0] & 0xff));
                        var texel = Color.new(255, 255, 255, gray);
                        texel = math.sRGB255ToLinear1(texel);
                        _ = texel.setRGB(texel.rgb().scaledTo(texel.a()));
                        texel = math.linear1ToSRGB255(texel);

                        dest[0] = texel.packColor1();

                        dest += 1;
                        source += 1;
                    }

                    dest_row -= @as(usize, @intCast(result.?.pitch));
                    source_row -= MAX_FONT_WIDTH;
                }

                asset.info.bitmap.alignment_percentage[0] =
                    (1.0) / @as(f32, @floatFromInt(result.?.width));
                asset.info.bitmap.alignment_percentage[1] =
                    (1.0 + @as(f32, @floatFromInt(max_y - (bound_height - font.text_metrics.tmDescent)))) / @as(f32, @floatFromInt(result.?.height));

                kerning_change = @as(f32, @floatFromInt(min_x - pre_step_x));
            }

            var char_advance: f32 = 0;
            if (false) {
                var this_abc: win32.ABC = undefined;
                _ = win32.GetCharABCWidthsW(global_font_device_context, code_point, code_point, &this_abc);
                char_advance = @floatFromInt(this_abc.abcA + @as(i32, @intCast(this_abc.abcB)) + this_abc.abcC);
            } else {
                var this_width: i32 = undefined;
                _ = win32.GetCharWidth32W(global_font_device_context, code_point, code_point, &this_width);
                char_advance = @floatFromInt(this_width);
            }

            var other_glyph_index: u32 = 0;
            while (other_glyph_index < font.max_glyph_count) : (other_glyph_index += 1) {
                font.horizontal_advance[glyph_index * font.max_glyph_count + other_glyph_index] += char_advance - kerning_change;

                if (other_glyph_index != 0) {
                    font.horizontal_advance[other_glyph_index * font.max_glyph_count + glyph_index] += kerning_change;
                }
            }
        } else {
            std.debug.print("Failed to generate glyph: {d}\n", .{code_point});
            return null;
        }
    } else {
        // const ttf_file = readEntireFile(file_name, allocator);
        // defer allocator.free(ttf_file.contents);
        //
        // if (ttf_file.content_size != 0) {
        //     const ttf_data: [*c]const u8 = @ptrCast(ttf_file.contents);
        //
        //     var font: c.stbtt_fontinfo = undefined;
        //     _ = c.stbtt_InitFont(&font, ttf_data, c.stbtt_GetFontOffsetForIndex(ttf_data, 0));
        //
        //     var width: c_int = undefined;
        //     var height: c_int = undefined;
        //     var x_offset: c_int = undefined;
        //     var y_offset: c_int = undefined;
        //     const mono_bitmap = c.stbtt_GetCodepointBitmap(
        //         &font,
        //         0,
        //         c.stbtt_ScaleForPixelHeight(&font, 128),
        //         @intCast(code_point),
        //         &width,
        //         &height,
        //         &x_offset,
        //         &y_offset,
        //     );
        //     defer c.stbtt_FreeBitmap(mono_bitmap, null);
        //
        //     result = LoadedBitmap{
        //         .free = undefined,
        //         .memory = undefined,
        //         .width = width,
        //         .height = height,
        //         .pitch = width * shared.BITMAP_BYTES_PER_PIXEL,
        //     };
        //     result.?.free = allocator.alloc(u8, @intCast(@as(i32, @intCast(height)) * result.?.pitch)) catch unreachable;
        //     result.?.memory = @ptrCast(@constCast(result.?.free));
        //
        //     var source: [*]u8 = mono_bitmap;
        //     var dest_row: [*]u8 = @as([*]u8, @ptrCast(result.?.memory.?)) + @as(usize, @intCast((height - 1) * result.?.pitch));
        //
        //     var y: u32 = 0;
        //     while (y < height) : (y += 1) {
        //         var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        //
        //         var x: u32 = 0;
        //         while (x < width) : (x += 1) {
        //             const alpha: u8 = 0xff;
        //             const gray = source;
        //             source += 1;
        //
        //             dest[0] = @truncate(
        //                 ((@as(u32, @intCast(alpha)) << 24) |
        //                     (@as(u32, @intCast(gray[0])) << 16) |
        //                     (@as(u32, @intCast(gray[0])) << 8) |
        //                     (@as(u32, @intCast(gray[0])) << 0)),
        //             );
        //             dest += 1;
        //         }
        //
        //         dest_row -= @as(usize, @intCast(result.?.pitch));
        //     }
        // }
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

const LoadedSound = struct {
    sample_count: u32,
    channel_count: u32,
    samples: [2]?[*]i16,
    free: []const u8,
};

fn riffCode(a: u32, b: u32, in_c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, in_c << 16) | @as(u32, d << 24);
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

    fn getChunkData(self: RiffIterator) *anyopaque {
        return @ptrCast(self.at + @sizeOf(WaveChunk));
    }

    fn getChunkDataSize(self: RiffIterator) u32 {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        return chunk.size;
    }
};

fn parseWaveChunkAt(at: *anyopaque, stop: *anyopaque) RiffIterator {
    return RiffIterator{ .at = @ptrCast(at), .stop = @ptrCast(stop) };
}

pub fn loadWAV(
    file_name: []const u8,
    section_first_sample_index: u32,
    section_sample_count: u32,
    allocator: std.mem.Allocator,
) LoadedSound {
    var result: LoadedSound = undefined;
    const read_result = readEntireFile(file_name, allocator);

    if (read_result.content_size > 0) {
        result.free = read_result.contents;

        const header = @as(*WaveHeader, @ptrCast(@alignCast(@constCast(read_result.contents))));

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

// Assets.
const AssetType = enum(u32) {
    Sound,
    Bitmap,
    Font,
    FontGlyph,
};

const AssetSourceFont = struct {
    font: *LoadedFont,
};

const AssetSourceFontGlyph = struct {
    font: *LoadedFont,
    code_point: u32,
};

const AssetSourceBitmap = struct {
    file_name: []const u8 = undefined,
};

const AssetSourceSound = struct {
    file_name: []const u8 = undefined,
    first_sample_index: u32,
};

const AssetSource = struct {
    asset_type: AssetType,
    data: union {
        bitmap: AssetSourceBitmap,
        sound: AssetSourceSound,
        font: AssetSourceFont,
        glyph: AssetSourceFontGlyph,
    },
};

const BitmapAsset = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

const AssetBitmapInfo = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

const AssetSoundInfo = struct {
    file_name: [*:0]const u8,
    first_sample_index: u32,
    sample_count: u32,
    next_id_to_play: ?SoundId,
};

const AddedAsset = struct {
    id: u32,
    hha: *HHAAsset,
    source: *AssetSource,
};

// TODO: Are there larger numbers than 4096? Do we have evidence in the natural world of things that can exist
// in quantities larger than 4096?
const VERY_LARGE_NUMBER = 4096; // 4096 should be enough for anybody.

pub const Assets = struct {
    tag_count: u32 = 0,
    tags: [VERY_LARGE_NUMBER]HHATag = [1]HHATag{undefined} ** VERY_LARGE_NUMBER,

    asset_count: u32 = 0,
    asset_sources: [VERY_LARGE_NUMBER]AssetSource = [1]AssetSource{undefined} ** VERY_LARGE_NUMBER,
    assets: [VERY_LARGE_NUMBER]HHAAsset = [1]HHAAsset{undefined} ** VERY_LARGE_NUMBER,

    asset_type_count: u32 = 0,
    asset_types: [ASSET_TYPE_ID_COUNT]HHAAssetType = [1]HHAAssetType{HHAAssetType{}} ** ASSET_TYPE_ID_COUNT,

    debug_asset_type: ?*HHAAssetType = null,
    asset_index: u32 = 0,

    fn init() Assets {
        return Assets{
            .asset_count = 1,
            .tag_count = 1,
            .asset_type_count = ASSET_TYPE_ID_COUNT,
            .debug_asset_type = null,
            .asset_index = 0,
        };
    }

    fn beginAssetType(self: *Assets, type_id: AssetTypeId) void {
        std.debug.assert(self.debug_asset_type == null);

        self.debug_asset_type = &self.asset_types[type_id.toInt()];
        self.debug_asset_type.?.type_id = @intFromEnum(type_id);
        self.debug_asset_type.?.first_asset_index = self.asset_count;
        self.debug_asset_type.?.one_past_last_asset_index = self.debug_asset_type.?.first_asset_index;
    }

    fn addAsset(self: *Assets) ?AddedAsset {
        std.debug.assert(self.debug_asset_type != null);

        var result: ?AddedAsset = null;

        if (self.debug_asset_type) |asset_type| {
            std.debug.assert(asset_type.one_past_last_asset_index < self.assets.len);

            const index = asset_type.one_past_last_asset_index;
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            const source: *AssetSource = &self.asset_sources[index];
            const hha: *HHAAsset = &self.assets[index];
            hha.first_tag_index = self.tag_count;
            hha.one_past_last_tag_index = self.tag_count;

            self.asset_index = index;

            result = AddedAsset{
                .id = index,
                .hha = hha,
                .source = source,
            };
        }

        return result;
    }

    fn addBitmapAsset(self: *Assets, file_name: []const u8, alignment_percentage_x: ?f32, alignment_percentage_y: ?f32) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.addAsset()) |asset| {
            result = BitmapId{ .value = asset.id };
            asset.hha.info = .{
                .bitmap = HHABitmap{
                    .dim = .{ 0, 0 },
                    .alignment_percentage = .{
                        alignment_percentage_x orelse 0.5,
                        alignment_percentage_y orelse 0.5,
                    },
                },
            };
            asset.source.asset_type = .Bitmap;
            asset.source.data = .{ .bitmap = .{ .file_name = file_name } };
        }

        return result;
    }

    fn addFontAsset(self: *Assets, font: *LoadedFont) ?FontId {
        var result: ?FontId = null;

        if (self.addAsset()) |asset| {
            result = FontId{ .value = asset.id };
            asset.hha.info = .{
                .font = HHAFont{
                    .one_past_highest_code_point = font.one_past_highest_code_point,
                    .glyph_count = font.glyph_count,
                    .ascender_height = @floatFromInt(font.text_metrics.tmAscent),
                    .descender_height = @floatFromInt(font.text_metrics.tmDescent),
                    .external_leading = @floatFromInt(font.text_metrics.tmExternalLeading),
                },
            };
            asset.source.asset_type = .Font;
            asset.source.data = .{
                .font = .{
                    .font = font,
                },
            };
        }

        return result;
    }

    fn addCharacterAsset(
        self: *Assets,
        font: *LoadedFont,
        code_point: u32,
    ) ?BitmapId {
        var result: ?BitmapId = null;

        if (self.addAsset()) |asset| {
            result = BitmapId{ .value = asset.id };
            asset.hha.info = .{
                .bitmap = HHABitmap{
                    .dim = .{ 0, 0 },
                    .alignment_percentage = .{ 0, 0 }, // This is set later by extraction.
                },
            };
            asset.source.asset_type = .FontGlyph;
            asset.source.data = .{
                .glyph = .{
                    .font = font,
                    .code_point = code_point,
                },
            };

            std.debug.assert(font.glyph_count < font.max_glyph_count);
            const glyph_index: u32 = font.glyph_count;
            font.glyph_count += 1;
            const glyph: *HHAFontGlyph = &font.glyphs[glyph_index];
            glyph.unicode_code_point = code_point;
            glyph.bitmap = result.?;
            font.glyph_index_from_code_point[code_point] = glyph_index;

            if (font.one_past_highest_code_point <= code_point) {
                font.one_past_highest_code_point = code_point + 1;
            }
        }

        return result;
    }

    fn addSoundAsset(self: *Assets, file_name: []const u8) ?SoundId {
        return self.addSoundSectionAsset(file_name, 0, 0);
    }

    fn addSoundSectionAsset(self: *Assets, file_name: []const u8, first_sample_index: u32, sample_count: u32) ?SoundId {
        var result: ?SoundId = null;

        if (self.addAsset()) |asset| {
            result = SoundId{ .value = asset.id };
            asset.hha.info = .{
                .sound = HHASound{
                    .channel_count = 0,
                    .sample_count = sample_count,
                    .chain = .None,
                    // .next_id_to_play = SoundId{ .value = 0 },
                },
            };

            asset.source.asset_type = .Sound;
            asset.source.data = .{
                .sound = .{
                    .file_name = file_name,
                    .first_sample_index = first_sample_index,
                },
            };
        }

        return result;
    }

    fn addTag(self: *Assets, tag_id: AssetTagId, value: f32) void {
        std.debug.assert(self.asset_index != 0);

        var hha = &self.assets[self.asset_index];
        hha.one_past_last_tag_index += 1;
        const tag: *HHATag = &self.tags[self.tag_count];
        self.tag_count += 1;

        tag.id = tag_id.toInt();
        tag.value = value;
    }

    fn endAssetType(self: *Assets) void {
        if (self.debug_asset_type) |asset_type| {
            self.asset_count = asset_type.one_past_last_asset_index;
            self.debug_asset_type = null;
            self.asset_index = 0;
        }
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    initializeFontDC();

    writeFonts(allocator);
    writeHero(allocator);
    writeNonHero(allocator);
    writeSounds(allocator);

    if (gpa.detectLeaks()) {
        std.log.debug("Memory leaks detected.\n", .{});
    }
}

inline fn addFont(
    allocator: std.mem.Allocator,
    assets: *Assets,
    font_file: []const u8,
    font_name: []const u8,
    font_type: AssetFontType,
) *LoadedFont {
    const font = loadFont(allocator, font_file, font_name);

    assets.beginAssetType(.FontGlyph);
    var character: u32 = ' ';
    while (character <= '~') : (character += 1) {
        _ = assets.addCharacterAsset(font, character);
    }

    // Kanji owl.
    _ = assets.addCharacterAsset(font, 0x5c0f);
    _ = assets.addCharacterAsset(font, 0x8033);
    _ = assets.addCharacterAsset(font, 0x6728);
    _ = assets.addCharacterAsset(font, 0x514e);

    assets.endAssetType();

    // This needs to happen after the glyphs for the font have been added.
    assets.beginAssetType(.Font);
    _ = assets.addFontAsset(font);
    assets.addTag(.FontType, @floatFromInt(@intFromEnum(font_type)));
    assets.endAssetType();

    return font;
}

fn writeFonts(allocator: std.mem.Allocator) void {
    var assets = Assets.init();

    const fonts: [2]*LoadedFont = .{
        loadFont(allocator, "C:/Windows/Fonts/arial.ttf", "Arial", 128),
        loadFont(allocator, "C:/Windows/Fonts/LiberationMono-Regular.ttf", "Liberation Mono", 20),
    };
    defer freeFont(allocator, fonts[0]);
    defer freeFont(allocator, fonts[1]);
    const font_types: [2]AssetFontType = .{
        .Default,
        .Debug,
    };

    assets.beginAssetType(.FontGlyph);
    for (fonts) |font| {
        var character: u32 = ' ';
        while (character <= '~') : (character += 1) {
            _ = assets.addCharacterAsset(font, character);
        }

        // Kanji owl.
        _ = assets.addCharacterAsset(font, 0x5c0f);
        _ = assets.addCharacterAsset(font, 0x8033);
        _ = assets.addCharacterAsset(font, 0x6728);
        _ = assets.addCharacterAsset(font, 0x514e);
    }
    assets.endAssetType();

    // This needs to happen after the glyphs for the font have been added.
    assets.beginAssetType(.Font);
    for (fonts, 0..) |font, index| {
        _ = assets.addFontAsset(font);
        assets.addTag(.FontType, @floatFromInt(@intFromEnum(font_types[index])));
    }
    assets.endAssetType();

    writeHHA("testfonts.hha", &assets, allocator) catch unreachable;
}

fn writeHero(allocator: std.mem.Allocator) void {
    var result = Assets.init();

    const angle_right: f32 = 0;
    const angle_back: f32 = 0.25 * math.TAU32;
    const angle_left: f32 = 0.5 * math.TAU32;
    const angle_front: f32 = 0.75 * math.TAU32;
    const hero_align_x = 0.5;
    const hero_align_y = 0.156682029;

    result.beginAssetType(.Head);
    _ = result.addBitmapAsset("test/test_hero_right_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Cape);
    _ = result.addBitmapAsset("test/test_hero_right_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Torso);
    _ = result.addBitmapAsset("test/test_hero_right_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    writeHHA("test1.hha", &result, allocator) catch unreachable;
}

fn writeNonHero(allocator: std.mem.Allocator) void {
    var result = Assets.init();

    result.beginAssetType(.Shadow);
    _ = result.addBitmapAsset("test/test_hero_shadow.bmp", 0.5, 0.15668203);
    result.endAssetType();

    result.beginAssetType(.Tree);
    _ = result.addBitmapAsset("test2/tree00.bmp", 0.49382716, 0.29565218);
    result.endAssetType();

    result.beginAssetType(.Sword);
    _ = result.addBitmapAsset("test2/rock03.bmp", 0.5, 0.65625);
    result.endAssetType();

    result.beginAssetType(.Grass);
    _ = result.addBitmapAsset("test2/grass00.bmp", null, null);
    _ = result.addBitmapAsset("test2/grass01.bmp", null, null);
    result.endAssetType();

    result.beginAssetType(.Stone);
    _ = result.addBitmapAsset("test2/ground00.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground01.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground02.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground03.bmp", null, null);
    result.endAssetType();

    result.beginAssetType(.Tuft);
    _ = result.addBitmapAsset("test2/tuft00.bmp", null, null);
    _ = result.addBitmapAsset("test2/tuft01.bmp", null, null);
    _ = result.addBitmapAsset("test2/tuft02.bmp", null, null);
    result.endAssetType();

    writeHHA("test2.hha", &result, allocator) catch unreachable;
}

fn writeSounds(allocator: std.mem.Allocator) void {
    var result = Assets.init();

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
    while (first_sample_index < total_music_sample_count) : (first_sample_index += one_music_chunk) {
        var sample_count = total_music_sample_count - first_sample_index;
        if (sample_count > one_music_chunk) {
            sample_count = one_music_chunk;
        }

        const this_music = result.addSoundSectionAsset("test3/music_test.wav", first_sample_index, sample_count);
        if (this_music) |this| {
            result.assets[this.value].info.sound.chain = .Advance;
        }
    }
    result.endAssetType();

    result.beginAssetType(.Puhp);
    _ = result.addSoundAsset("test3/puhp_00.wav");
    _ = result.addSoundAsset("test3/puhp_01.wav");
    result.endAssetType();

    writeHHA("test3.hha", &result, allocator) catch unreachable;
}

fn writeHHA(file_name: []const u8, result: *Assets, allocator: std.mem.Allocator) !void {
    // Open or create a file.
    var opt_out: ?std.fs.File = null;
    if (std.fs.cwd().openFile(file_name, .{ .mode = .write_only })) |file| {
        opt_out = file;
    } else |err| {
        std.debug.print("Unable to open '{s}': {s}", .{ file_name, @errorName(err) });

        opt_out = std.fs.cwd().createFile(file_name, .{}) catch |create_err| {
            std.debug.print("Unable to create '{s}': {s}", .{ file_name, @errorName(create_err) });
            std.process.exit(1);
        };
    }

    // Write the results out to the file.
    if (opt_out) |out| {
        defer out.close();

        var header = HHAHeader{
            .tag_count = result.tag_count,
            .asset_type_count = ASSET_TYPE_ID_COUNT,
            .asset_count = result.asset_count,
        };

        const tag_array_size: u32 = header.tag_count * @sizeOf(HHATag);
        const asset_type_array_size: u32 = header.asset_type_count * @sizeOf(HHAAssetType);
        const asset_array_size: u32 = header.asset_count * @sizeOf(HHAAsset);

        header.tags = @sizeOf(HHAHeader);
        header.asset_types = header.tags + tag_array_size;
        header.assets = header.asset_types + asset_type_array_size;
        header.assets = (header.assets + @alignOf(HHAAsset) - 1) & ~@as(u32, @alignOf(HHAAsset) - 1);

        var bytes_written: usize = 0;
        bytes_written += try out.write(std.mem.asBytes(&header));
        // std.debug.print("Bytes written after header: {d}\n", .{ bytes_written });
        // std.debug.print("Tags: Expected: {d}, actual: {d}\n", .{header.tags, bytes_written});
        bytes_written += try out.write(std.mem.asBytes(&result.tags)[0..tag_array_size]);
        // std.debug.print("Bytes written after tags: {d}\n", .{ bytes_written });
        // std.debug.print("Asset types: Expected: {d}, actual: {d}\n", .{header.asset_types, bytes_written});
        bytes_written += try out.write(std.mem.asBytes(&result.asset_types));
        // std.debug.print("Bytes written after asset types: {d}\n", .{ bytes_written });
        // std.debug.print("Assets: Expected: {d}, actual: {d}\n", .{header.assets, bytes_written});

        try out.seekBy(asset_array_size);
        var asset_index: u32 = 1;
        while (asset_index < header.asset_count) : (asset_index += 1) {
            const source: *AssetSource = &result.asset_sources[asset_index];
            var dest: *HHAAsset = &result.assets[asset_index];

            dest.data_offset = try out.getPos();

            switch (source.asset_type) {
                .Font => {
                    const font = source.data.font.font;

                    finalizeFontKerning(allocator, font);

                    const glyphs_size: u32 = font.glyph_count * @sizeOf(HHAFontGlyph);
                    var bytes: []const u8 = @as([*]const u8, @ptrCast(font.glyphs))[0..glyphs_size];
                    bytes_written += try out.write(bytes);

                    var horizontal_advance: [*]u8 = @ptrCast(@alignCast(font.horizontal_advance));
                    var glyph_index: u32 = 0;
                    while (glyph_index < font.glyph_count) : (glyph_index += 1) {
                        const horizontal_advance_slice_size: u32 = @sizeOf(f32) * font.glyph_count;
                        bytes = @as([*]const u8, @ptrCast(horizontal_advance))[0..horizontal_advance_slice_size];
                        bytes_written += try out.write(bytes);
                        horizontal_advance += @sizeOf(f32) * font.max_glyph_count;
                    }
                },
                .Bitmap, .FontGlyph => {
                    const opt_bmp = if (source.asset_type == .FontGlyph)
                        loadGlyphBMP(source.data.glyph.font, source.data.glyph.code_point, allocator, dest)
                    else
                        loadBMP(source.data.bitmap.file_name, allocator);

                    if (opt_bmp) |bmp| {
                        defer allocator.free(bmp.free);

                        dest.info.bitmap.dim[0] = @intCast(bmp.width);
                        dest.info.bitmap.dim[1] = @intCast(bmp.height);

                        std.debug.assert((bmp.width * 4) == bmp.pitch);
                        const size: usize = @as(usize, @intCast(bmp.width)) * @as(usize, @intCast(bmp.height * 4));
                        const bytes: []const u8 = @as([*]const u8, @ptrCast(bmp.memory.?))[0..size];
                        bytes_written += try out.write(bytes);
                        // std.debug.print("Expected size: {d}, size: {d}\n", .{ size, bytes.len });
                        // std.debug.print("Bytes written after bmp: {d}\n", .{ bytes_written });
                    }
                },
                .Sound => {
                    const wav = loadWAV(source.data.sound.file_name, source.data.sound.first_sample_index, dest.info.sound.sample_count, allocator);
                    defer allocator.free(wav.free);

                    dest.info.sound.sample_count = wav.sample_count;
                    dest.info.sound.channel_count = wav.channel_count;

                    var channel_index: u32 = 0;
                    while (channel_index < wav.channel_count) : (channel_index += 1) {
                        const size: usize = dest.info.sound.sample_count * @sizeOf(i16);
                        const bytes: []const u8 = @as([*]const u8, @ptrCast(wav.samples[channel_index].?))[0..size];
                        bytes_written += try out.write(bytes);
                        // std.debug.print("Expected size: {d}, size: {d}\n", .{ size, bytes.len });
                        // std.debug.print("Bytes written after wav: {d}\n", .{ bytes_written });
                    }
                },
            }
        }
        try out.seekTo(header.assets);
        bytes_written += try out.write(std.mem.asBytes(&result.assets)[0..asset_array_size]);

        std.debug.print("Bytes written: {s} {d}\n", .{ file_name, bytes_written });
    }
}
