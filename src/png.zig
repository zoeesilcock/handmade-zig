const std = @import("std");
const shared = @import("shared.zig");

const Signature: [8]u8 = .{ 137, 80, 78, 71, 13, 10, 26, 10 };
const Header = extern struct {
    signature: [8]u8,
};

const ChunkHeader = extern struct {
    length: u32 align(1),
    chunk_type: [4]u8 align(1),

    pub fn chunkTypeU32(self: *ChunkHeader) u32 {
        return @bitCast(self.chunk_type);
    }
};

const IHeader = extern struct {
    width: u32,
    height: u32,
    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,
};

const IDataHeader = extern struct {
    zlib_method_flags: u8,
    additional_flags: u8,
};

const IDataFooter = extern struct {
    crc: u32,
};

const ChunkFooter = extern struct {
    crc: u32 align(1),
};

const EntireFile = struct {
    content_size: u32 = 0,
    contents: [:0]align(1) u8 = undefined,

    pub fn consumeType(self: *EntireFile, T: type) ?*T {
        return @ptrCast(@alignCast(self.consumeSize(@sizeOf(T))));
    }

    pub fn consumeSize(self: *EntireFile, size: u32) ?[*]u8 {
        var result: ?[*]u8 = null;

        if (self.content_size >= size) {
            result = self.contents.ptr;
            self.contents.ptr += size;
            self.content_size -= size;
        } else {
            self.content_size = 0;
            std.log.err("File underflow", .{});
        }

        return result;
    }
};

fn readEntireFile(file_name: [:0]const u8, allocator: std.mem.Allocator) !EntireFile {
    var result = EntireFile{};

    if (std.fs.cwd().openFile(file_name, .{})) |file| {
        defer file.close();

        _ = try file.seekFromEnd(0);
        result.content_size = @as(u32, @intCast(file.getPos() catch 0));
        _ = try file.seekTo(0);

        const buffer = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, .@"32", 0);
        result.contents = buffer;
    } else |err| {
        std.log.err("Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}

fn endianSwap(value: *align(1) u32) void {
    if (false) {
        const v: u32 = value.*;
        value.* =
            (v << 24) |
            ((v & 0xff00) << 8) |
            ((v >> 8) & 0xff00) |
            (v >> 24);
    } else {
        value.* = @byteSwap(value.*);
    }
}

test "endianSwap" {
    var value: u32 = 0x44332211;
    endianSwap(&value);
    try std.testing.expectEqual(0x11223344, value);
}

fn fourcc(string: []const u8) u32 {
    // return @as(*const u32, @ptrCast(@alignCast(string.ptr))).*;

    return string[0] |
        @as(u32, @intCast(string[1])) << 8 |
        @as(u32, @intCast(string[2])) << 16 |
        @as(u32, @intCast(string[3])) << 24;
}

fn allocatePixels(allocator: std.mem.Allocator, width: u32, height: u32, bytes_per_pixel: u32) []u8 {
    return allocator.alloc(u8, width * height * bytes_per_pixel) catch unreachable;
}

/// This is not meant to be fault tolerant. It only loads specifically what we expect, and is happy to crash otherwise.
fn parsePNG(file: EntireFile, allocator: std.mem.Allocator) void {
    var supported: bool = false;
    var at: EntireFile = file;
    var decompressed_pixels: ?[]u8 = null;

    if (at.consumeType(Header)) |header| {
        _ = header;

        while (at.content_size > 0) {
            if (at.consumeType(ChunkHeader)) |chunk_header| {
                endianSwap(&chunk_header.length);

                const chunk_data: ?[*c]u8 = at.consumeSize(chunk_header.length);

                if (at.consumeType(ChunkFooter)) |chunk_footer| {
                    endianSwap(&chunk_footer.crc);

                    if (chunk_header.chunkTypeU32() == fourcc("IHDR")) {
                        std.log.info("IHDR", .{});

                        const ihdr: *IHeader = @ptrCast(@alignCast(chunk_data));
                        endianSwap(&ihdr.width);
                        endianSwap(&ihdr.height);

                        std.log.info("    width: {d}", .{ihdr.width});
                        std.log.info("    height: {d}", .{ihdr.height});
                        std.log.info("    bit_depth: {d}", .{ihdr.bit_depth});
                        std.log.info("    color_type: {d}", .{ihdr.color_type});
                        std.log.info("    compression_method: {d}", .{ihdr.compression_method});
                        std.log.info("    filter_method: {d}", .{ihdr.filter_method});
                        std.log.info("    interlace_method: {d}", .{ihdr.interlace_method});

                        if (ihdr.bit_depth == 8 and
                            ihdr.color_type == 6 and
                            ihdr.compression_method == 0 and
                            ihdr.filter_method == 0 and
                            ihdr.interlace_method == 0)
                        {
                            decompressed_pixels = allocatePixels(allocator, ihdr.width, ihdr.height, 4);
                            supported = true;
                        }
                    } else if (chunk_header.chunkTypeU32() == fourcc("IDAT")) {
                        std.log.info("IDAT", .{});

                        if (supported) {
                            const idat_header: *IDataHeader = @ptrCast(chunk_data);
                            const cm: u8 = idat_header.zlib_method_flags & 0xf;
                            const cinfo: u8 = idat_header.zlib_method_flags >> 4;
                            const fcheck: u8 = idat_header.additional_flags & 0x1f;
                            const fdict: u8 = (idat_header.additional_flags >> 5) & 0x1;
                            const flevel: u8 = idat_header.additional_flags >> 6;

                            std.log.info("    cm: {d}", .{cm});
                            std.log.info("    cinfo: {d}", .{cinfo});
                            std.log.info("    fcheck: {d}", .{fcheck});
                            std.log.info("    fdict: {d}", .{fdict});
                            std.log.info("    flevel: {d}", .{flevel});
                        }
                    }
                }
            }
        }
    }

    std.log.info("Supported: {s}", .{if (supported) "true" else "false"});

    if (decompressed_pixels) |pixels| {
        allocator.free(pixels);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2) {
        const file_name: [:0]const u8 = args[1];
        std.log.info("Loading PNG {s}...", .{file_name});

        const file: EntireFile = try readEntireFile(file_name, allocator);
        defer allocator.free(file.contents);

        parsePNG(file, allocator);
    } else {
        std.log.info("Usage: {s} (png file to load)", .{args[0]});
    }
}
