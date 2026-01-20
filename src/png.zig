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

const Huffman = struct {
    fn compute(self: *Huffman, input_count: u32, input: [*]u32) void {
        _ = self;
        _ = input_count;
        _ = input;
    }

    fn decode(self: *Huffman, input: *StreamingBuffer) u32 {
        _ = self;
        _ = input;
        return 0;
    }
};

const StreamingChunk = struct {
    content_size: u32 = 0,
    contents: [:0]align(1) u8 = undefined,

    next: ?*StreamingChunk = null,
};

const StreamingBuffer = struct {
    content_size: u32 = 0,
    contents: [:0]align(1) u8 = undefined,

    bit_count: u32 = 0,
    bit_buf: u32 = 0,

    first: ?*StreamingChunk = null,
    last: ?*StreamingChunk = null,

    pub fn consumeType(self: *StreamingBuffer, T: type) ?*T {
        return @ptrCast(@alignCast(self.consumeSize(@sizeOf(T))));
    }

    pub fn consumeBits(self: *StreamingBuffer, bit_count: u32) u32 {
        std.debug.assert(bit_count <= 32);

        var result: u32 = 0;

        while (self.bit_count < bit_count and self.content_size > 0) {
            const byte: u32 = @intCast(self.consumeType(u8).?.*);
            self.bit_buf |= (byte << @as(u5, @intCast(self.bit_count)));
            self.bit_count += 8;
        }

        if (self.bit_count >= bit_count) {
            self.bit_count -= bit_count;

            result = self.bit_buf & ((@as(u32, 1) << @as(u5, @intCast(bit_count))) - 1);
            self.bit_buf >>= @as(u5, @intCast(bit_count));
        }

        return result;
    }

    pub fn flushByte(self: *StreamingBuffer) void {
        self.bit_count = 0;
        self.bit_buf = 0;
    }

    pub fn consumeSize(self: *StreamingBuffer, size: u32) ?[*]u8 {
        var result: ?[*]u8 = null;
        if (self.content_size == 0 and self.first != null) {
            const this: *StreamingChunk = self.first.?;
            self.content_size = this.content_size;
            self.contents = this.contents;
            self.first = this.next;
        }

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

fn readEntireFile(file_name: [:0]const u8, allocator: std.mem.Allocator) !StreamingBuffer {
    var result = StreamingBuffer{};

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

fn allocateChunk(allocator: std.mem.Allocator) *StreamingChunk {
    return @ptrCast(@alignCast(allocator.alloc(u8, @sizeOf(StreamingChunk)) catch unreachable));
}

/// This is not meant to be fault tolerant. It only loads specifically what we expect, and is happy to crash otherwise.
fn parsePNG(file: StreamingBuffer, allocator: std.mem.Allocator) void {
    var supported: bool = false;
    var at: StreamingBuffer = file;

    if (at.consumeType(Header)) |header| {
        _ = header;

        var compressed_data: StreamingBuffer = .{};
        var width: u32 = 0;
        var height: u32 = 0;

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
                            width = ihdr.width;
                            height = ihdr.height;
                            supported = true;
                        }
                    } else if (chunk_header.chunkTypeU32() == fourcc("IDAT")) {
                        std.log.info("IDAT {d}", .{chunk_header.length});

                        const chunk: *StreamingChunk = allocateChunk(allocator);
                        chunk.content_size = chunk_header.length;
                        chunk.contents = @ptrCast(chunk_data.?[0..chunk_header.length]);
                        chunk.next = null;

                        // Casey's "ridiculous" version.
                        // compressed_data.last =
                        //     ((if (compressed_data.last != null) compressed_data.last.?.next else compressed_data.first) = chunk);

                        if (compressed_data.last != null) {
                            compressed_data.last.?.next = chunk;
                        } else {
                            compressed_data.first = chunk;
                        }
                        compressed_data.last = chunk;
                    }
                }
            }
        }

        if (supported) {
            std.log.info("Examining ZLIB headers...", .{});

            if (compressed_data.consumeType(IDataHeader)) |idat_header| {
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

                supported = (cm == 8 and fdict == 0);

                if (supported) {
                    std.log.info("Decompressing...", .{});

                    const decompressed_pixels: []u8 = allocatePixels(allocator, width, height, 4);
                    _ = decompressed_pixels;

                    var bfinal: u32 = 0;
                    while (bfinal == 0) {
                        bfinal = compressed_data.consumeBits(1);
                        const btype: u32 = compressed_data.consumeBits(2);

                        if (btype == 0) {
                            compressed_data.flushByte();
                            const len: u32 = compressed_data.consumeBits(16);
                            const nlen: i32 = @bitCast(compressed_data.consumeBits(16));
                            if (len != -nlen) {
                                std.log.err("LEN/NLEN mismatch.", .{});
                            }
                        } else if (btype == 3) {
                            std.log.err("BTYPE of {d} encountered.", .{btype});
                        } else {
                            var literal_length_huffman: Huffman = .{};
                            var distance_huffman: Huffman = .{};

                            if (btype == 2) {
                                var hlit: u32 = compressed_data.consumeBits(5);
                                var hdist: u32 = compressed_data.consumeBits(5);
                                var hclen: u32 = compressed_data.consumeBits(4);

                                hlit += 257;
                                hdist += 1;
                                hclen += 4;

                                const hclen_swizzle =
                                    [_]u32{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
                                std.debug.assert(hclen <= hclen_swizzle.len);
                                var hclen_table: [hclen_swizzle.len]u32 = [1]u32{0} ** hclen_swizzle.len;

                                var index: u32 = 0;
                                while (index < hclen) : (index += 1) {
                                    hclen_table[hclen_swizzle[index]] = compressed_data.consumeBits(3);
                                }

                                var dictionary_huffman: Huffman = .{};
                                dictionary_huffman.compute(hclen, &hclen_table);

                                var literal_length_distance_table: [512]u32 = [1]u32{0} ** 512;
                                var literal_length_count: u32 = 0;
                                const length_count: u32 = hlit + hdist;
                                index = 0;
                                while (literal_length_count < length_count) {
                                    var repeat_count: u32 = 1;
                                    var repeat_value: u32 = 0;
                                    const encoded_length: u32 = dictionary_huffman.decode(&compressed_data);

                                    if (encoded_length <= 15) {
                                        literal_length_distance_table[literal_length_count] = encoded_length;
                                        literal_length_count += 1;
                                    } else if (encoded_length == 16) {
                                        repeat_count = 3 + compressed_data.consumeBits(2);
                                        std.debug.assert(literal_length_count > 0);
                                        repeat_value = literal_length_distance_table[literal_length_count - 1];
                                    } else if (encoded_length == 17) {
                                        repeat_count = 3 + compressed_data.consumeBits(2);
                                    } else if (encoded_length == 18) {
                                        repeat_count = 11 + compressed_data.consumeBits(7);
                                    } else {
                                        std.log.err("Encoded length of {d} encountered.", .{encoded_length});
                                    }

                                    while (repeat_count > 0) : (repeat_count -= 1) {
                                        literal_length_distance_table[literal_length_count] = repeat_value;
                                        literal_length_count += 1;
                                    }
                                }

                                std.debug.assert(literal_length_count == length_count);

                                literal_length_huffman.compute(hlit, &literal_length_distance_table);
                                distance_huffman.compute(hdist, @ptrCast(&literal_length_distance_table[hdist]));
                            } else {
                                std.log.err("BTYPE of {d} encountered.", .{btype});
                            }

                            while (true) {
                                const literal_length: u32 = literal_length_huffman.decode(&compressed_data);
                                if (literal_length < 256) {
                                    const out: u32 = literal_length;
                                    _ = out;
                                    // TODO: Write here.
                                } else if (literal_length > 256) {
                                    const length: u32 = literal_length - 256;
                                    const distance: u32 = distance_huffman.decode(&compressed_data);
                                    _ = distance;
                                    var index: u32 = 0;
                                    while (index < length) : (index += 1) {
                                        // TODO: Write here
                                    }
                                } else {
                                    break;
                                }
                            }

                            // TODO: REMOVE THIS!
                            bfinal = 1;
                            break;
                        }
                    }
                }
            }
        }
    }

    std.log.info("Supported: {s}", .{if (supported) "true" else "false"});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2) {
        const file_name: [:0]const u8 = args[1];
        std.log.info("Loading PNG {s}...", .{file_name});

        const file: StreamingBuffer = try readEntireFile(file_name, allocator);

        parsePNG(file, allocator);
    } else {
        std.log.info("Usage: {s} (png file to load)", .{args[0]});
    }
}
