const std = @import("std");
const png = @import("png");
const shared = png.shared;
const stream = png.stream;
const memory = png.memory;
const math = shared.math;
const types = shared.types;
const c = @cImport({
    @cInclude("stdlib.h");
});

// Types.
const Buffer = types.Buffer;
const Stream = stream.Stream;
const StreamChunk = stream.Chunk;
const ImageU32 = png.ImageU32;
const MemoryArena = memory.MemoryArena;
const PlatformMemoryBlock = shared.PlatformMemoryBlock;
const Rectangle2i = math.Rectangle2i;

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
};

fn readEntireFile(file_name: []const u8, allocator: std.mem.Allocator, errors: *Stream, io: std.Io) !Stream {
    var buffer: Buffer = .{};

    var open_error: ?std.Io.File.OpenError = null;
    if (std.Io.Dir.cwd().openFile(io, file_name, .{ .mode = .read_only })) |file| {
        defer file.close(io);

        var file_reader = file.reader(io, &.{});
        const file_contents = try file_reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(u32)));
        buffer.data = file_contents.ptr;
        buffer.count = file_contents.len;
    } else |err| {
        open_error = err;
    }

    const result: Stream = .makeReadStream(buffer, errors);
    if (open_error) |err| {
        _ = stream.outputWithSrc(result.errors, @src(), "Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}

const PixelOp = enum(u32) {
    SwapRedAndBlue = 0x1,
    ReplaceAlpha = 0x2,
    MultiplyAlpha = 0x4,
    Invert = 0x8,
    ThresholdAlpha = 0x10,
};

pub fn thresholdAlpha(color: u32) u32 {
    var alpha = color >> 24;

    if (alpha > 0) {
        alpha = 0xff;
    }

    const result: u32 = (alpha << 24) | color;

    return result;
}

fn writeBMPImageTopDownRGBA(
    width: u32,
    height: u32,
    pixels: []u32,
    output_file_name: []const u8,
    pixel_ops: u32,
    errors: *Stream,
    io: std.Io,
) !void {
    const output_pixel_size: u32 = 4 * width * height;

    const replace_alpha: bool = (pixel_ops & @intFromEnum(PixelOp.ReplaceAlpha)) != 0;
    const swap_red_and_blue: bool = (pixel_ops & @intFromEnum(PixelOp.SwapRedAndBlue)) != 0;
    const multiply_alpha: bool = (pixel_ops & @intFromEnum(PixelOp.MultiplyAlpha)) != 0;
    const invert: bool = (pixel_ops & @intFromEnum(PixelOp.Invert)) != 0;
    const threshold_alpha: bool = (pixel_ops & @intFromEnum(PixelOp.ThresholdAlpha)) != 0;

    const header_size: u32 = @sizeOf(BitmapHeader) - 10;
    const header: BitmapHeader = .{
        .file_type = 0x4d42,
        .file_size = header_size + @as(u32, @intCast(pixels.len)),
        .reserved1 = 0,
        .reserved2 = 0,
        .bitmap_offset = header_size,
        .size = header_size - 14,
        .width = @intCast(width),
        .height = @intCast(height),
        .planes = 1,
        .bits_per_pxel = 32,
        .compression = 0,
        .size_of_bitmap = output_pixel_size,
        .horz_resolution = 0,
        .vert_resolution = 0,
        .colors_used = 0,
        .colors_important = 0,
    };

    const mid_point_y: u32 = @divFloor(@as(u32, @intCast(header.height + 1)), 2);
    var row0: [*]u32 = pixels.ptr;
    var row1: [*]u32 = row0 + (height - 1) * width;
    var y: u32 = 0;
    while (y < mid_point_y) : (y += 1) {
        var pixel0: [*]u32 = row0;
        var pixel1: [*]u32 = row1;
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            var color0: u32 = pixel0[0];
            var color1: u32 = pixel1[0];

            if (swap_red_and_blue) {
                color0 = math.swapRedAndBlue(color0);
                color1 = math.swapRedAndBlue(color1);
            }

            if (threshold_alpha) {
                color0 = thresholdAlpha(color0);
                color1 = thresholdAlpha(color1);
            }

            if (replace_alpha) {
                color0 = math.replaceAlpha(color0);
                color1 = math.replaceAlpha(color1);
            }

            if (multiply_alpha) {
                color0 = math.multiplyAlpha(color0);
                color1 = math.multiplyAlpha(color1);
            }

            if (invert) {
                pixel0[0] = color1;
                pixel1[0] = color0;
            } else {
                pixel0[0] = color0;
                pixel1[0] = color1;
            }
            pixel0 += 1;
            pixel1 += 1;
        }

        row0 += width;
        row1 -= width;
    }

    if (std.Io.Dir.cwd().createFile(io, output_file_name, .{})) |file| {
        defer file.close(io);

        var buf: [1024]u8 = undefined;
        var file_writer = file.writer(io, &buf);
        const writer = &file_writer.interface;

        try writer.writeAll(std.mem.asBytes(&header)[0..header_size]);
        try writer.writeAll(std.mem.sliceAsBytes(pixels));

        try writer.flush();
    } else |err| {
        _ = stream.outputWithSrc(
            errors,
            @src(),
            "Unable to write output file '%s': %s\n",
            .{ output_file_name, @errorName(err) },
        );
    }
}

fn dumpStreamToWriter(source: *Stream, dest: *std.Io.Writer) !void {
    var opt_chunk: ?*StreamChunk = source.first;
    while (opt_chunk) |chunk| : (opt_chunk = chunk.next) {
        try dest.print("{s} ({d}): ", .{ chunk.file_name, chunk.line });
        try dest.writeAll(chunk.contents.data[0..chunk.contents.count]);
        try dest.flush();
    }
}

fn crtAllocateMemory(size: memory.MemoryIndex, flags: u64) callconv(.c) ?*PlatformMemoryBlock {
    _ = flags;

    const total_size: usize = @sizeOf(PlatformMemoryBlock) + size;
    var block: [*]PlatformMemoryBlock = @ptrCast(@alignCast(c.malloc(total_size)));
    @memset(@as([*]u8, @ptrCast(block))[0..total_size], 0);

    block[0].size = size;
    block[0].base = @ptrCast(block + 1);

    return @ptrCast(block);
}

fn crtDeallocateMemory(opt_platform_block: ?*PlatformMemoryBlock) callconv(.c) void {
    if (opt_platform_block) |block| {
        c.free(block);
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
    const one: u32 = if (one_past_max_y > 0) 1 else 0;
    var source_row: [*]u32 = source_image.pixels.ptr + ((one_past_max_y - one) * source_image.width + min_x);

    var y: u32 = 0;
    while (y < result.height) : (y += 1) {
        var source_pixel: [*]u32 = source_row;

        var x: u32 = 0;
        while (x < result.width) : (x += 1) {
            const source_color: u32 = source_pixel[0];
            source_pixel += 1;
            dest_pixel[0] = source_color;
            dest_pixel += 1;
        }

        source_row -= source_image.width;
    }

    return result;
}

fn testMultiTileImport(image: ImageU32, temp_arena: *MemoryArena, error_stream: *Stream, io: std.Io) !void {
    const border_dimension: u32 = 8;
    const tile_dimension: u32 = 1024;

    const x_count_max: u32 = 16;
    const y_count_max: u32 = 16;

    var x_count: u32 = image.width / tile_dimension;
    if (x_count > x_count_max) {
        _ = stream.outputWithSrc(error_stream, @src(), "Tile column count of %u exceeds maximum of %u columns.\n", .{
            x_count,
            x_count_max,
        });
        x_count = x_count_max;
    }
    var y_count: u32 = image.height / tile_dimension;
    if (y_count > y_count_max) {
        _ = stream.outputWithSrc(error_stream, @src(), "Tile row count of %u exceeds maximum of %u rows.\n", .{
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
                    _ = stream.outputWithSrc(error_stream, @src(), "Tile %u, %u extends into left %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (max_x < (tile_dimension - border_dimension)) {
                    max_x += border_dimension;
                } else {
                    max_x = tile_dimension - 1;
                    _ = stream.outputWithSrc(error_stream, @src(), "Tile %u, %u extends into right %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (min_y >= border_dimension) {
                    min_y -= border_dimension;
                } else {
                    min_y = 0;
                    _ = stream.outputWithSrc(error_stream, @src(), "Tile %u, %u extends into top %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                if (max_y < (tile_dimension - border_dimension)) {
                    max_y += border_dimension;
                } else {
                    max_y = tile_dimension - 1;
                    _ = stream.outputWithSrc(error_stream, @src(), "Tile %u, %u extends into bottom %u-pixel border.\n", .{
                        x_index,
                        y_index,
                        border_dimension,
                    });
                }

                const extract: Rectangle2i = .new(
                    @intCast(x_index * tile_dimension + min_x),
                    @intCast(y_index * tile_dimension + min_y),
                    @intCast(x_index * tile_dimension + max_x + 1),
                    @intCast(y_index * tile_dimension + max_y + 1),
                );

                const extracted: ImageU32 = extractImage(
                    image,
                    @intCast(extract.min.x()),
                    @intCast(extract.min.y()),
                    @intCast(extract.max.x()),
                    @intCast(extract.max.y()),
                    temp_arena,
                );

                _ = stream.outputWithSrc(error_stream, @src(), "EXTRACTION[%u, %u]: %u, %u -> %u, %u, (%u, %u)\n", .{
                    x_index,
                    y_index,
                    extract.min.x(),
                    extract.min.y(),
                    extract.max.x(),
                    extract.max.y(),
                    extracted.width,
                    extracted.height,
                });

                var out_rgb: [256]u8 = undefined;
                var out_alpha: [256]u8 = undefined;
                const out_rgb_name =
                    try std.fmt.bufPrint(&out_rgb, "C:/tmp/extract{d}{d}_rgb.bmp", .{ x_index, y_index });
                const out_alpha_name =
                    try std.fmt.bufPrint(&out_alpha, "C:/tmp/extract{d}{d}_alpha.bmp", .{ x_index, y_index });

                try writeBMPImageTopDownRGBA(
                    extracted.width,
                    extracted.height,
                    extracted.pixels,
                    out_rgb_name,
                    @intFromEnum(PixelOp.SwapRedAndBlue) | @intFromEnum(PixelOp.Invert), // | @intFromEnum(PixelOp.MultiplyAlpha),
                    error_stream,
                    io,
                );
                try writeBMPImageTopDownRGBA(
                    extracted.width,
                    extracted.height,
                    extracted.pixels,
                    out_alpha_name,
                    @intFromEnum(PixelOp.ReplaceAlpha) | @intFromEnum(PixelOp.ThresholdAlpha),
                    error_stream,
                    io,
                );
            }
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    shared.platform = shared.Platform{
        .allocateMemory = crtAllocateMemory,
        .deallocateMemory = crtDeallocateMemory,
    };

    var arena: MemoryArena = .{};

    var error_stream: Stream = .onDemandMemoryStream(&arena, null);
    var info_stream: Stream = .onDemandMemoryStream(&arena, &error_stream);

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len == 4) {
        const in_file_name: [:0]const u8 = args[1];
        const out_file_name_rgb: [:0]const u8 = args[2];
        const out_file_name_alpha: [:0]const u8 = args[3];

        _ = stream.outputWithSrc(&info_stream, @src(), "Loading PNG %s...\n", .{in_file_name});
        const file: Stream = try readEntireFile(in_file_name, allocator, &error_stream, init.io);
        const image: ImageU32 = png.parsePNG(&arena, file, &info_stream);

        if (false) {
            try testMultiTileImport(image, &arena, &info_stream, init.io);
        }

        _ = stream.outputWithSrc(&info_stream, @src(), "Writing BMP %s...\n", .{out_file_name_rgb});
        try writeBMPImageTopDownRGBA(
            image.width,
            image.height,
            image.pixels,
            out_file_name_rgb,
            @intFromEnum(PixelOp.SwapRedAndBlue) | @intFromEnum(PixelOp.Invert), // | @intFromEnum(PixelOp.MultiplyAlpha),
            &error_stream,
            init.io,
        );
        _ = stream.outputWithSrc(&info_stream, @src(), "Writing BMP %s...\n", .{out_file_name_alpha});
        try writeBMPImageTopDownRGBA(
            image.width,
            image.height,
            image.pixels,
            out_file_name_alpha,
            @intFromEnum(PixelOp.ReplaceAlpha), // | @intFromEnum(PixelOp.ThresholdAlpha),
            &error_stream,
            init.io,
        );
    } else {
        _ = stream.outputWithSrc(
            &error_stream,
            @src(),
            "Usage: %s (png file to load) (bmp file to write RGB to) (bmp file to write alpha to)\n",
            .{args[0]},
        );
    }

    var buf: [1024]u8 = undefined;

    var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("Info:\n");
    try dumpStreamToWriter(&info_stream, stdout);
    try stdout.flush();

    try stdout.writeAll("Errors:\n");
    var stderr_writer = std.Io.File.stderr().writer(init.io, &buf);
    const stderr = &stderr_writer.interface;
    try dumpStreamToWriter(&error_stream, stderr);
    try stderr.flush();
}
