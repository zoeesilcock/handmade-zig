const std = @import("std");
const png = @import("png");
const shared = png.shared;
const stream = png.stream;
const memory = png.memory;
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

// Types.
const Stream = stream.Stream;
const StreamChunk = stream.Chunk;
const ImageU32 = png.ImageU32;
const MemoryArena = memory.MemoryArena;
const PlatformMemoryBlock = shared.PlatformMemoryBlock;

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

fn readEntireFile(file_name: [:0]const u8, allocator: std.mem.Allocator, errors: *Stream) !Stream {
    var result = Stream{
        .errors = errors,
    };

    if (std.fs.cwd().openFile(file_name, .{})) |file| {
        defer file.close();

        _ = try file.seekFromEnd(0);
        result.content_size = @as(u32, @intCast(file.getPos() catch 0));
        _ = try file.seekTo(0);

        const buffer = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, .@"32", 0);
        result.contents = buffer;
    } else |err| {
        stream.output(result.errors, @src(), "Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}

const PixelOp = enum(u32) {
    SwapRedAndBlue = 0x1,
    ReplaceAlpha = 0x2,
    MultiplyAlpha = 0x4,
};

fn swapRedAndBlue(color: u32) u32 {
    const result: u32 = ((color & 0xff00ff00) |
        ((color >> 16) & 0xff) |
        ((color & 0xff) << 16));

    return result;
}

fn replaceAlpha(color: u32) u32 {
    const alpha = color >> 24;
    const result: u32 =
        (alpha << 24) |
        (alpha << 16) |
        (alpha << 8) |
        (alpha << 0);

    return result;
}

fn multiplyAlpha(color: u32) u32 {
    var color0: u32 = ((color >> 0) & 0xff);
    var color1: u32 = ((color >> 8) & 0xff);
    var color2: u32 = ((color >> 16) & 0xff);
    const alpha = color >> 24;

    // Quick and dirty lossy multiply, loses one bit.
    color0 = ((color0 * alpha) >> 8);
    color1 = ((color1 * alpha) >> 8);
    color2 = ((color2 * alpha) >> 8);

    const result: u32 =
        (alpha << 24) |
        (color2 << 16) |
        (color1 << 8) |
        (color0 << 0);

    return result;
}

fn writeBMPImageTopDownRGBA(
    width: u32,
    height: u32,
    pixels: []u32,
    output_file_name: []const u8,
    pixel_ops: u32,
    errors: *Stream,
) !void {
    const output_pixel_size: u32 = 4 * width * height;

    const replace_alpha: bool = (pixel_ops & @intFromEnum(PixelOp.ReplaceAlpha)) != 0;
    const swap_red_and_blue: bool = (pixel_ops & @intFromEnum(PixelOp.SwapRedAndBlue)) != 0;
    const multiply_alpha: bool = (pixel_ops & @intFromEnum(PixelOp.MultiplyAlpha)) != 0;

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
                color0 = swapRedAndBlue(color0);
                color1 = swapRedAndBlue(color1);
            }

            if (replace_alpha) {
                color0 = replaceAlpha(color0);
                color1 = replaceAlpha(color1);
            }

            if (multiply_alpha) {
                color0 = multiplyAlpha(color0);
                color1 = multiplyAlpha(color1);
            }

            pixel0[0] = color1;
            pixel1[0] = color0;
            pixel0 += 1;
            pixel1 += 1;
        }

        row0 += width;
        row1 -= width;
    }

    if (std.fs.cwd().createFile(output_file_name, .{})) |file| {
        defer file.close();

        var buf: [1024]u8 = undefined;
        var file_writer = file.writer(&buf);
        const writer = &file_writer.interface;

        try writer.writeAll(std.mem.asBytes(&header)[0..header_size]);
        try writer.writeAll(std.mem.sliceAsBytes(pixels));

        try writer.flush();
    } else |err| {
        stream.output(errors, @src(), "Unable to write output file '%s': %s\n", .{ output_file_name, @errorName(err) });
    }
}

fn dumpStreamToWriter(source: *Stream, dest: *std.Io.Writer) !void {
    var opt_chunk: ?*StreamChunk = source.first;
    while (opt_chunk) |chunk| : (opt_chunk = chunk.next) {
        try dest.print("{s} ({d}): ", .{ chunk.file_name, chunk.line });
        try dest.writeAll(chunk.contents);
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

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena_allocator.allocator();
    defer arena_allocator.deinit();

    shared.platform = shared.Platform{
        .allocateMemory = crtAllocateMemory,
        .deallocateMemory = crtDeallocateMemory,
    };

    var arena: MemoryArena = .{};

    var error_stream: Stream = .onDemandMemoryStream(&arena, null);
    var info_stream: Stream = .onDemandMemoryStream(&arena, &error_stream);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 4) {
        const in_file_name: [:0]const u8 = args[1];
        const out_file_name_rgb: [:0]const u8 = args[2];
        const out_file_name_alpha: [:0]const u8 = args[3];

        stream.output(&info_stream, @src(), "Loading PNG %s...\n", .{in_file_name});
        const file: Stream = try readEntireFile(in_file_name, allocator, &error_stream);
        const image: ImageU32 = png.parsePNG(&arena, file, &info_stream);

        stream.output(&info_stream, @src(), "Writing BMP %s...\n", .{out_file_name_rgb});
        try writeBMPImageTopDownRGBA(
            image.width,
            image.height,
            image.pixels,
            out_file_name_rgb,
            @intFromEnum(PixelOp.SwapRedAndBlue), // | @intFromEnum(PixelOp.MultiplyAlpha),
            &error_stream,
        );
        stream.output(&info_stream, @src(), "Writing BMP %s...\n", .{out_file_name_alpha});
        try writeBMPImageTopDownRGBA(
            image.width,
            image.height,
            image.pixels,
            out_file_name_alpha,
            @intFromEnum(PixelOp.ReplaceAlpha),
            &error_stream,
        );
    } else {
        stream.output(
            &error_stream,
            @src(),
            "Usage: %s (png file to load) (bmp file to write RGB to) (bmp file to write alpha to)\n",
            .{args[0]},
        );
    }

    var buf: [128]u8 = undefined;

    const stdout = std.fs.File.stdout().writer(&buf);
    var stdout_writer = stdout.interface;
    try stdout_writer.writeAll("Info:\n");
    try dumpStreamToWriter(&info_stream, &stdout_writer);
    try stdout_writer.flush();

    try stdout_writer.writeAll("Errors:\n");
    const stderr = std.fs.File.stderr().writer(&buf);
    var stderr_writer = stderr.interface;
    try dumpStreamToWriter(&error_stream, &stderr_writer);
    try stderr_writer.flush();
}
