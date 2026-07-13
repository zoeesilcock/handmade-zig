const std = @import("std");
const win32 = @import("win32");
const shared = @import("shared");
const math = shared.math;
const types = shared.types;
const png = shared.png;
const memory = png.memory;
const stream = shared.stream;
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

pub const UNICODE = true;

const MAX_FONT_WIDTH: u32 = 1024;
const MAX_FONT_HEIGHT: u32 = 1024;

// Types.
const Color = math.Color;
const Vector2 = math.Vector2;
const Vector2u = math.Vector2u;
const Stream = stream.Stream;
const StreamChunk = stream.Chunk;
const MemoryArena = memory.MemoryArena;
const PlatformMemoryBlock = shared.PlatformMemoryBlock;

// Logging.
pub const std_options: std.Options = .{
    .logFn = myLogFn,
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const io = std.Options.debug_io;

    if (level == .err) {
        const prev = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(prev);
        var buffer: [64]u8 = undefined;
        const stderr = std.debug.lockStderr(&buffer).terminal();
        defer std.debug.unlockStderr();
        return std.log.defaultLogFileTerminal(level, scope, format, args, stderr) catch {};
    } else {
        var stdout_buf: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
        var stdout = &stdout_writer.interface;
        stdout.print(format ++ "\n", args) catch return;
        stdout.flush() catch return;
    }
}

const PixelOp = enum(u32) {
    SwapRedAndBlue = 0x1,
    ReplaceAlpha = 0x2,
    MultiplyAlpha = 0x4,
    Invert = 0x8,
};

const FontGlyph = extern struct {
    unicode_code_point: u32,
    bitmap_id: u32,
};

const GlyphResult = extern struct {
    align_percentage: Vector2 = .zero(),
    kerning_change: f32 = 0,
    char_advance: f32 = 0,

    width: u32 = 0,
    height: u32 = 0,
    pixels: [*]u32 = undefined,
};

fn loadGlyphBMP(
    font_bits: ?*anyopaque,
    code_point: u32,
    max_glyph_dim: Vector2u,
    scale: u32,
    tm_descent: i32,
    device_context: win32.graphics.gdi.CreatedHDC,
    out_memory: []u8,
) GlyphResult {
    if (font_bits) |bits| {
        // Clear bits to black.
        const byte_count: usize = max_glyph_dim.x() * max_glyph_dim.y();
        @memset(@as([*]u32, @ptrCast(@alignCast(bits)))[0..byte_count], 0x00);
    }

    const cheese_point: []const u16 = &[_]u16{@intCast(code_point)};

    var size: win32.foundation.SIZE = undefined;
    _ = win32.graphics.gdi.GetTextExtentPoint32W(device_context, @ptrCast(cheese_point), 1, &size);

    const pre_step_x: u32 = 128;

    var bound_width: u32 = @as(u32, @intCast(size.cx)) + 2 * pre_step_x;
    if (bound_width > max_glyph_dim.x()) {
        bound_width = max_glyph_dim.x();
    }
    var bound_height: u32 = @intCast(size.cy);
    if (bound_height > max_glyph_dim.y()) {
        bound_height = max_glyph_dim.y();
    }

    _ = win32.graphics.gdi.TextOutW(device_context, pre_step_x, 0, @ptrCast(cheese_point), 1);

    if (scale > 1) {
        bound_height /= scale;
        bound_width /= scale;

        var row: [*]u32 = @as([*]u32, @ptrCast(@alignCast(font_bits.?))) + (max_glyph_dim.y() - 1) * max_glyph_dim.x();
        var sample_row: [*]u32 = @as([*]u32, @ptrCast(@alignCast(font_bits.?))) + (max_glyph_dim.y() - 1) * max_glyph_dim.x();
        var y: u32 = 0;
        while (y < bound_height) : (y += 1) {
            var pixel = row;
            var sample = sample_row;

            var x: u32 = 0;
            while (x < bound_width) : (x += 1) {
                var accumulator: u32 = 0;
                var sample_inner = sample;

                var y_offset: u32 = 0;
                while (y_offset < scale) : (y_offset += 1) {
                    var x_offset: u32 = 0;
                    while (x_offset < scale) : (x_offset += 1) {
                        accumulator += sample_inner[x_offset] & 0xff;
                    }
                    sample_inner -= max_glyph_dim.x();
                }

                accumulator /= (scale * scale);

                pixel[0] = accumulator;
                pixel += 1;

                sample += scale;
            }
            row -= max_glyph_dim.x();
            sample_row -= scale * max_glyph_dim.x();
        }
    }

    var min_x: u32 = std.math.maxInt(u32);
    var min_y: u32 = std.math.maxInt(u32);
    var max_x: u32 = 0;
    var max_y: u32 = 0;

    { // Calculate extents of glyph.
        var row: [*]u32 = @as([*]u32, @ptrCast(@alignCast(font_bits.?))) + (max_glyph_dim.y() - 1) * max_glyph_dim.x();
        var y: u32 = 0;
        while (y < bound_height) : (y += 1) {
            var pixel = row;
            var x: u32 = 0;
            while (x < bound_width) : (x += 1) {
                // const ref_pixel = win32.foundation.GetPixel(device_context, x, y);
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

            row -= max_glyph_dim.x();
        }
    }

    var result: GlyphResult = .{};

    var kerning_change: f32 = 0;
    var align_percentage: Vector2 = .new(0.5, 0.5);
    var char_advance: f32 = 0;
    if (min_x <= max_x) {
        const width: u32 = (max_x - min_x) + 1;
        const height: u32 = (max_y - min_y) + 1;

        const bytes_per_pixel: u32 = 4;

        const out_width: u32 = width + 2;
        const out_height: u32 = height + 2;
        const out_pitch: u32 = out_width * bytes_per_pixel;

        @memset(out_memory, 0);

        result.width = out_width;
        result.height = out_height;
        result.pixels = @ptrCast(@alignCast(out_memory));

        var dest_row: [*]u8 = @as([*]u8, @ptrCast(out_memory)) + out_pitch;
        var source_row: [*]u32 = @as([*]u32, @ptrCast(@alignCast(font_bits.?))) +
            (max_glyph_dim.y() - 1 - @as(u32, @intCast(min_y))) * max_glyph_dim.x();

        var y: u32 = min_y;
        while (y <= max_y) : (y += 1) {
            var source: [*]u32 = source_row + @as(u32, @intCast(min_x));
            var dest: [*]u32 = @as([*]u32, @ptrCast(@alignCast(dest_row))) + 1;

            var x: u32 = min_x;
            while (x <= max_x) : (x += 1) {
                // const pixel = win32.foundation.GetPixel(device_context, @intCast(x), @intCast(y));
                // std.debug.assert(pixel == source[0]);

                const gray: u32 = source[0] & 0xff;
                dest[0] = ((gray << 24) | 0x00ffffff);
                dest += 1;
                source += 1;
            }

            dest_row += @as(usize, @intCast(out_pitch));
            source_row -= max_glyph_dim.x();
        }

        align_percentage = .new(
            (1.0) / @as(f32, @floatFromInt(out_width)),
            (1.0 + @as(f32, @floatFromInt(@as(i32, @intCast(max_y)) - (@as(i32, @intCast(bound_height)) - tm_descent)))) /
                @as(f32, @floatFromInt(out_height)),
        );

        kerning_change = @as(f32, @floatFromInt(@as(i32, @intCast(min_x)) - @as(i32, @intCast(pre_step_x))));
    }

    if (false) {
        var this_abc: win32.foundation.ABC = undefined;
        _ = win32.graphics.gdi.GetCharABCWidthsW(device_context, code_point, code_point, &this_abc);
        char_advance = @floatFromInt(this_abc.abcA + @as(i32, @intCast(this_abc.abcB)) + this_abc.abcC);
    } else {
        var this_width: i32 = undefined;
        _ = win32.graphics.gdi.GetCharWidth32W(device_context, code_point, code_point, &this_width);
        char_advance = @floatFromInt(this_width);
    }

    result.align_percentage = align_percentage;
    result.kerning_change = kerning_change;
    result.char_advance = char_advance;

    return result;
}

fn sanitize(source_in: [*]const u8, dest_in: [*]u8) void {
    var source = source_in;
    var dest = dest_in;

    while (source[0] != 0) {
        const d = std.ascii.toLower(source[0]);

        if ((d >= 'a' and d <= 'z') or (d >= '0' and d <= '9')) {
            dest[0] = d;
        } else {
            dest[0] = '_';
        }

        dest += 1;
        source += 1;
    }

    dest[0] = 0;
}

fn dataStreamToWriter(source: *Stream, dest: *std.Io.Writer) !void {
    var opt_chunk: ?*StreamChunk = source.first;
    while (opt_chunk) |chunk| : (opt_chunk = chunk.next) {
        try dest.writeAll(chunk.contents.data[0..chunk.contents.count]);
        try dest.flush();
    }
}

fn crtAllocateMemory(size: memory.MemoryIndex, flags: u64) callconv(.c) ?*PlatformMemoryBlock {
    _ = flags;

    const total_size: usize = @sizeOf(PlatformMemoryBlock) + size;
    var block: [*]PlatformMemoryBlock = @ptrCast(@alignCast(c.malloc(total_size)));
    _ = c.memset(block, 0, total_size);

    block[0].size = size;
    block[0].base = @ptrCast(block + 1);

    return @ptrCast(block);
}

fn crtDeallocateMemory(opt_platform_block: ?*PlatformMemoryBlock) callconv(.c) void {
    if (opt_platform_block) |block| {
        c.free(block);
    }
}

fn extractFont(
    ttf_file_name: []const u8,
    font_name: []const u8,
    pixel_height: u32,
    mask: *CodePointMask,
    hht_out_writer: *std.Io.Writer,
    png_dest_dir: []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
) !void {
    const name_stem: [*:0]u8 = @ptrCast(try allocator.alloc(u8, font_name.len + 1));
    sanitize(@ptrCast(font_name), @ptrCast(name_stem));

    const png_out_name_buf: []u8 = try allocator.alloc(u8, types.stringLength(name_stem) + png_dest_dir.len + 128);
    const png_file_name_only: [*:0]const u8 = @ptrCast(png_out_name_buf[png_dest_dir.len + 1 ..]);

    const glyph_count: u32 = mask.glyph_count;
    const one_past_max_font_code_point: u32 = mask.one_past_max_code_point;
    const glyph_code_point: [*]u32 = mask.code_point_from_glyph.?;

    //
    // Load and select the requested font.
    //

    // Windows has some secret ideas about when it's going to antialias its fonts and when it won't. Sure, they have
    // a flag you pass that says whether you want it antialiased, but it just says that it may antialias, if the font
    // is "too large" it won't antialias it. The limit is unknown, but on both Casey's machine and mine the limit
    // for "LiberationMono-Regular.ttf" was 353, beyond that it refuses to antialias.
    const scale: u32 = if (pixel_height > 128) 4 else 1;

    const scale_ratio: f32 = 1.0 / @as(f32, @floatFromInt(scale));
    const sample_pixel_height: u32 = scale * pixel_height;
    var i_quality: win32.graphics.gdi.FONT_QUALITY = .ANTIALIASED_QUALITY;
    if (scale > 1) {
        i_quality = .DEFAULT_QUALITY;
    }

    const device_context: win32.graphics.gdi.CreatedHDC =
        win32.graphics.gdi.CreateCompatibleDC(win32.graphics.gdi.GetDC(null));

    _ = win32.graphics.gdi.AddFontResourceExA(@ptrCast(ttf_file_name), .PRIVATE, null);
    if (win32.graphics.gdi.CreateFontA(
        -@as(i32, @intCast(sample_pixel_height)),
        0,
        0,
        0,
        @intFromEnum(win32.graphics.gdi.FW_NORMAL),
        0,
        0,
        0,
        @intFromEnum(win32.graphics.gdi.DEFAULT_CHARSET),
        .DEFAULT_PRECIS,
        win32.graphics.gdi.CLIP_DEFAULT_PRECIS,
        i_quality,
        win32.graphics.gdi.FF_DONTCARE,
        @ptrCast(font_name),
    )) |win32_handle| {
        _ = win32.graphics.gdi.SelectObject(device_context, win32_handle);

        var text_metrics: win32.graphics.gdi.TEXTMETRICW = undefined;
        _ = win32.graphics.gdi.GetTextMetricsW(device_context, &text_metrics);

        // These are arbitrarily padded because we're not sure what kind of shenanigans Microsoft may pull when they
        // report sizes.
        const max_glyph_dim: Vector2u = .new(
            256 + 2 * @as(u32, @intCast(text_metrics.tmMaxCharWidth + text_metrics.tmOverhang)),
            256 + 2 * @as(u32, @intCast(text_metrics.tmHeight + text_metrics.tmOverhang)),
        );

        const out_memory: []u8 =
            allocator.alloc(u8, @intCast(max_glyph_dim.x() * max_glyph_dim.y() * @sizeOf(u32))) catch unreachable;
        defer allocator.free(out_memory);

        //
        // Setup our Windows rendering buffer.
        //

        var font_bits: ?*anyopaque = null;

        const info = win32.graphics.gdi.BITMAPINFO{
            .bmiHeader = .{
                .biSize = @sizeOf(win32.graphics.gdi.BITMAPINFOHEADER),
                .biWidth = @intCast(max_glyph_dim.x()),
                .biHeight = @intCast(max_glyph_dim.y()),
                .biPlanes = 1,
                .biBitCount = 32,
                .biCompression = win32.graphics.gdi.BI_RGB,
                .biSizeImage = 0,
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed = 0,
                .biClrImportant = 0,
            },
            .bmiColors = .{
                win32.graphics.gdi.RGBQUAD{
                    .rgbBlue = 0,
                    .rgbGreen = 0,
                    .rgbRed = 0,
                    .rgbReserved = 0,
                },
            },
        };

        const bitmap = win32.graphics.gdi.CreateDIBSection(
            device_context,
            &info,
            win32.graphics.gdi.DIB_RGB_COLORS,
            &font_bits,
            null,
            0,
        );
        _ = win32.graphics.gdi.SelectObject(device_context, bitmap);
        _ = win32.graphics.gdi.SetBkColor(device_context, 0x000000);
        _ = win32.graphics.gdi.SetTextColor(device_context, 0xffffff);

        // const min_code_point: u32 = std.math.maxInt(u32);
        // const max_code_point: u32 = 0;

        const glyph_index_from_code_point_size: u32 = one_past_max_font_code_point * @sizeOf(u32);

        const glyph_index_from_code_point: []u32 = try allocator.alloc(u32, glyph_index_from_code_point_size);
        @memset(glyph_index_from_code_point, 0);

        var glyphs: []FontGlyph = try allocator.alloc(FontGlyph, glyph_count);
        const horizontal_advance_count: u32 = glyph_count * glyph_count;
        var horizontal_advance: []f32 = try allocator.alloc(f32, horizontal_advance_count);
        @memset(horizontal_advance, 0);

        // Reserve space for the null glyph.
        glyphs[0].unicode_code_point = 0;
        glyphs[0].bitmap_id = 0;

        const ascender_height: f32 = @floatFromInt(text_metrics.tmAscent);
        const descender_height: f32 = @floatFromInt(text_metrics.tmDescent);
        const external_leading: f32 = @floatFromInt(text_metrics.tmExternalLeading);

        const kerning_pair_count = win32.graphics.gdi.GetKerningPairsW(device_context, 0, null);
        const kerning_pairs = allocator.alloc(win32.graphics.gdi.KERNINGPAIR, kerning_pair_count) catch unreachable;
        _ = win32.graphics.gdi.GetKerningPairsW(device_context, kerning_pair_count, kerning_pairs.ptr);

        var kerning_pair_index: u32 = 0;
        while (kerning_pair_index < kerning_pair_count) : (kerning_pair_index += 1) {
            const pair = kerning_pairs[kerning_pair_index];

            if (pair.wFirst < one_past_max_font_code_point and pair.wSecond < one_past_max_font_code_point) {
                const first = glyph_index_from_code_point[pair.wFirst];
                const second = glyph_index_from_code_point[pair.wSecond];

                if (first != 0 and second != 0) {
                    horizontal_advance[first * glyph_count + second] += @floatFromInt(pair.iKernAmount);
                }
            }
        }

        _ = ascender_height;
        _ = descender_height;
        _ = external_leading;

        try hht_out_writer.print("font \"{s}\" \n{{\n", .{name_stem});

        const tm_descent: i32 = text_metrics.tmDescent;
        var glyph_index: u32 = 1;
        while (glyph_index < glyph_count) : (glyph_index += 1) {
            const code_point: u32 = glyph_code_point[glyph_index];
            const glyph = loadGlyphBMP(
                font_bits,
                code_point,
                max_glyph_dim,
                scale,
                tm_descent,
                device_context,
                out_memory,
            );

            const png_out_name: [:0]const u8 = try std.fmt.bufPrintZ(
                png_out_name_buf,
                "{s}/{s}_{d:04}.png",
                .{ png_dest_dir, name_stem, code_point },
            );

            if (std.Io.Dir.cwd().createFile(io, png_out_name, .{})) |file| {
                defer file.close(io);

                var temp_arena: MemoryArena = .{};
                defer temp_arena.clear();

                var png_stream: Stream = .onDemandMemoryStream(&temp_arena, null);
                try png.writePNG(glyph.width, glyph.height, glyph.pixels, &png_stream);

                var buf: [1024]u8 = undefined;
                var file_writer = file.writer(io, &buf);
                const writer = &file_writer.interface;

                try dataStreamToWriter(&png_stream, writer);
            } else |err| {
                std.log.err("Unable to open file '{s}' for writing: {s}", .{ png_out_name, @errorName(err) });
            }

            try hht_out_writer.print(
                "    glyph[{d}] = \"{s}\", {{{d}, {d}}};\n",
                .{ glyph_index, png_file_name_only, glyph.align_percentage.x(), glyph.align_percentage.y() },
            );

            var other_glyph_index: u32 = 0;
            while (other_glyph_index < glyph_count) : (other_glyph_index += 1) {
                horizontal_advance[glyph_index * glyph_count + other_glyph_index] +=
                    glyph.char_advance - glyph.kerning_change;

                if (other_glyph_index != 0) {
                    horizontal_advance[other_glyph_index * glyph_count + glyph_index] += glyph.kerning_change;
                }
            }
        }

        try hht_out_writer.print("    HorizontalAdvance =\n        ", .{});
        var index: u32 = 0;
        while (index < horizontal_advance_count) : (index += 1) {
            if (index > 0) {
                if (@mod(index, 16) == 0) {
                    try hht_out_writer.print(",\n        ", .{});
                } else {
                    try hht_out_writer.print(", ", .{});
                }
            }

            try hht_out_writer.print("{d:3}", .{@as(u32, @intFromFloat(scale_ratio * horizontal_advance[index]))});
        }
        try hht_out_writer.print(";\n", .{});

        try hht_out_writer.print("}};\n", .{});
        try hht_out_writer.flush();
    } else {
        std.log.err("Unable to load font {s} from {s}.", .{ font_name, ttf_file_name });
    }
}

fn createTestCharSet(mask: *CodePointMask) void {
    mask.include(' ');
    mask.includeRange('!', '~');

    // Kanji owl.
    mask.include(.{ 0x5c0f, 0x8033, 0x6728, 0x514e });
}

const CodePointMask = extern struct {
    one_past_max_code_point: u32 = 0,
    glyph_count: u32 = 0,
    code_point_from_glyph: ?[*]u32 = null,

    pub fn include(self: *CodePointMask, param: anytype) void {
        const type_info = @typeInfo(@TypeOf(param));
        switch (type_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    inline for (param) |code_point| {
                        self.includeCodePoint(code_point);
                    }
                } else {
                    @compileError("Must be u32 or tuple of u32s.");
                }
            },
            .int => |int_info| {
                if (int_info.bits == 32 and int_info.signedness == .unsigned) {
                    self.includeCodePoint(param);
                } else {
                    @compileError("Must be u32 or tuple of u32s.");
                }
            },
            .comptime_int => {
                self.includeCodePoint(param);
            },
            else => {
                @compileError("Must be u32 or tuple of u32s.");
            },
        }
    }

    pub fn includeRange(self: *CodePointMask, min_code_point: u32, max_code_point: u32) void {
        var code_point: u32 = min_code_point;
        while (code_point <= max_code_point) : (code_point += 1) {
            self.include(code_point);
        }
    }

    fn includeCodePoint(self: *CodePointMask, code_point: u32) void {
        if (code_point > 0) {
            if (self.code_point_from_glyph != null) {
                self.code_point_from_glyph.?[self.glyph_count] = code_point;
            }

            if (self.one_past_max_code_point <= code_point) {
                self.one_past_max_code_point = code_point + 1;
            }

            self.glyph_count += 1;
        }
    }
};

const CharSetCreatorFnType = *const fn (*CodePointMask) void;
const CharSetCreator = struct {
    name: []const u8,
    description: []const u8,
    function: CharSetCreatorFnType,
};

const char_sets = [_]CharSetCreator{
    .{
        .name = "Test",
        .description = "Basic character set for testing font creation and display.",
        .function = &createTestCharSet,
    },
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    shared.platform = shared.Platform{
        .allocateMemory = crtAllocateMemory,
        .deallocateMemory = crtDeallocateMemory,
    };

    // "C:/Windows/Fonts/arial.ttf", "Arial", 128),
    // "C:/Windows/Fonts/LiberationMono-Regular.ttf", "Liberation Mono", 20),

    var print_usage: bool = true;

    if (args.len == 7) {
        const ttf_file_name: []const u8 = args[1];
        const font_name: []const u8 = args[2];
        const pixel_height: u32 = try std.fmt.parseInt(u32, args[3], 10);
        const char_set_name: []const u8 = args[4];
        const hht_file_name: []const u8 = args[5];
        const png_dir_name: []const u8 = args[6];

        var char_set_creator: ?*const CharSetCreator = null;

        for (&char_sets) |*char_set| {
            if (std.mem.eql(u8, char_set.name, char_set_name)) {
                char_set_creator = char_set;
                break;
            }
        }

        if (char_set_creator) |creator| {
            if (std.Io.Dir.cwd().createFile(io, hht_file_name, .{})) |hht_file| {
                defer hht_file.close(io);

                var buffer: [1024]u8 = undefined;
                var file_writer = hht_file.writerStreaming(io, &buffer);
                const writer = &file_writer.interface;
                try writer.print(
                    \\// File: {s}
                    \\// Date:
                    \\// Revision:
                    \\// Creator: {s}
                    \\// Notice: Extraction of font "{s}"
                    \\
                , .{ hht_file_name, args[0], font_name });

                var counter_mask: CodePointMask = .{
                    .glyph_count = 1,
                };
                creator.function(&counter_mask);

                var mask: CodePointMask = .{
                    .glyph_count = 1,
                    .code_point_from_glyph = @ptrCast(allocator.alloc(u32, counter_mask.glyph_count) catch @panic("OOM")),
                };
                @memset(mask.code_point_from_glyph.?[0..counter_mask.glyph_count], 0);
                creator.function(&mask);

                std.log.info("Extracting font {s} - {d} glyphs, codepoint range {d}", .{
                    font_name,
                    mask.glyph_count,
                    mask.one_past_max_code_point,
                });

                try extractFont(ttf_file_name, font_name, pixel_height, &mask, writer, png_dir_name, allocator, io);
                print_usage = false;

                std.log.info("Done!", .{});
            } else |err| {
                std.log.err(
                    "ERROR: Unable to open HHT file \"{s}\" for writing. Error: {s}.",
                    .{ hht_file_name, @errorName(err) },
                );
            }
        } else {
            std.log.err("ERROR: Unrecognized character set \"{s}\".", .{char_set_name});
        }
    }

    if (print_usage) {
        std.log.err("Usage:", .{});
        std.log.err("{s} <TTF file name> <font name> <pixel height> <charset> <dest hht> <dest dir>", .{args[0]});
        std.log.err("\nSuported <charset> values:", .{});
        for (char_sets) |char_set| {
            std.log.err("{s} - {s}", .{ char_set.name, char_set.description });
        }
    }
}
