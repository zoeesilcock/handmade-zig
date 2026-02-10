const std = @import("std");
pub const shared = @import("shared.zig");
pub const memory = @import("memory.zig");
pub const stream = @import("stream.zig");

// Types.
const Stream = stream.Stream;
const StreamChunk = stream.Chunk;
const MemoryArena = memory.MemoryArena;

const PNG_HUFFMAN_MAX_BIT_COUNT = 16;
const Signature: [8]u8 = .{ 137, 80, 78, 71, 13, 10, 26, 10 };

pub const ImageU32 = struct {
    width: u32,
    height: u32,
    pixels: []u32,
};

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
    max_code_length_in_bits: u32 = 0,
    entry_count: u32 = 0,
    entries: []HuffmanEntry = undefined,

    fn compute(self: *Huffman, symbol_count: u32, symbol_code_length: [*]u32, opt_symbol_addend: ?u32) void {
        const symbol_addend = opt_symbol_addend orelse 0;

        var code_length_histogram: [PNG_HUFFMAN_MAX_BIT_COUNT]u32 = [1]u32{0} ** PNG_HUFFMAN_MAX_BIT_COUNT;
        var symbol_index: u32 = 0;
        while (symbol_index < symbol_count) : (symbol_index += 1) {
            const count: u32 = symbol_code_length[symbol_index];
            std.debug.assert(count <= code_length_histogram.len);
            code_length_histogram[count] += 1;
        }

        var next_unused_code: [PNG_HUFFMAN_MAX_BIT_COUNT]u32 = undefined;
        next_unused_code[0] = 0;
        code_length_histogram[0] = 0;
        var bit_index: u32 = 1;
        while (bit_index < next_unused_code.len) : (bit_index += 1) {
            next_unused_code[bit_index] =
                (next_unused_code[bit_index - 1] + code_length_histogram[bit_index - 1]) << 1;
        }

        symbol_index = 0;
        while (symbol_index < symbol_count) : (symbol_index += 1) {
            const code_length_in_bits: u32 = symbol_code_length[symbol_index];
            if (code_length_in_bits > 0) {
                std.debug.assert(code_length_in_bits < next_unused_code.len);
                const code: u32 = next_unused_code[code_length_in_bits];
                next_unused_code[code_length_in_bits] += 1;

                const arbitrary_bits: u32 = self.max_code_length_in_bits - code_length_in_bits;
                const entry_count: u32 = (@as(u32, 1) << @intCast(arbitrary_bits));

                var entry_index: u32 = 0;
                while (entry_index < entry_count) : (entry_index += 1) {
                    const base_index: u32 = (code << @as(u5, @intCast(arbitrary_bits))) | entry_index;
                    const index: u32 = reverseBits(base_index, self.max_code_length_in_bits);

                    var entry: *HuffmanEntry = &self.entries[index];

                    const symbol: u32 = symbol_index + symbol_addend;
                    entry.bits_used = @intCast(code_length_in_bits);
                    entry.symbol = @intCast(symbol);

                    std.debug.assert(entry.bits_used == code_length_in_bits);
                    std.debug.assert(entry.symbol == symbol);
                }
            }
        }
    }

    fn decode(self: *Huffman, input: *Stream) u32 {
        const entry_index: u32 = input.peekBits(self.max_code_length_in_bits);
        std.debug.assert(entry_index < self.entry_count);

        const entry: HuffmanEntry = self.entries[entry_index];

        const result: u32 = entry.symbol;
        input.discardBits(entry.bits_used);
        std.debug.assert(entry.bits_used != 0);

        return result;
    }
};

const HuffmanEntry = struct {
    symbol: u16,
    bits_used: u16,
};

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

fn endianSwapU16(value: *align(1) u16) void {
    if (false) {
        const v: u16 = value.*;
        value.* = ((v << 8) | (v >> 8));
    } else {
        value.* = @byteSwap(value.*);
    }
}

test "endianSwap" {
    var value: u32 = 0x44332211;
    endianSwap(&value);
    try std.testing.expectEqual(0x11223344, value);
}

fn reverseBits(value: u32, bit_count: u32) u32 {
    var result: u32 = 0;

    var bit_index: u32 = 0;
    while (bit_index <= (bit_count / 2)) : (bit_index += 1) {
        const inverse: u5 = @intCast(bit_count - (bit_index + 1));
        result |= ((value >> @as(u5, @intCast(bit_index))) & 0x1) << inverse;
        result |= ((value >> inverse) & 0x1) << @as(u5, @intCast(bit_index));
    }

    return result;
}

fn fourcc(string: []const u8) u32 {
    // return @as(*const u32, @ptrCast(@alignCast(string.ptr))).*;

    return string[0] |
        @as(u32, @intCast(string[1])) << 8 |
        @as(u32, @intCast(string[2])) << 16 |
        @as(u32, @intCast(string[3])) << 24;
}

fn allocatePixels(
    arena: *MemoryArena,
    width: u32,
    height: u32,
    bytes_per_pixel: u32,
    opt_extra_bytes: ?u32,
) []u8 {
    const extra_bytes: u32 = opt_extra_bytes orelse 0;
    const size: u32 = width * height * bytes_per_pixel + (extra_bytes * height);
    return arena.pushSize(size, null)[0..size];
}

fn allocateHuffman(arena: *MemoryArena, max_code_length_in_bits: u32) Huffman {
    std.debug.assert(max_code_length_in_bits <= PNG_HUFFMAN_MAX_BIT_COUNT);

    var result: Huffman = .{};
    result.max_code_length_in_bits = max_code_length_in_bits;
    result.entry_count = (@as(u32, 1) << @as(u5, @intCast(max_code_length_in_bits)));
    result.entries = arena.pushArray(result.entry_count, HuffmanEntry, null)[0..result.entry_count];
    return result;
}

const length_extra = [_]HuffmanEntry{
    .{ .symbol = 3, .bits_used = 0 }, // 257
    .{ .symbol = 4, .bits_used = 0 }, // 258
    .{ .symbol = 5, .bits_used = 0 }, // 259
    .{ .symbol = 6, .bits_used = 0 }, // 260
    .{ .symbol = 7, .bits_used = 0 }, // 261
    .{ .symbol = 8, .bits_used = 0 }, // 262
    .{ .symbol = 9, .bits_used = 0 }, // 263
    .{ .symbol = 10, .bits_used = 0 }, // 264
    .{ .symbol = 11, .bits_used = 1 }, // 265
    .{ .symbol = 13, .bits_used = 1 }, // 266
    .{ .symbol = 15, .bits_used = 1 }, // 267
    .{ .symbol = 17, .bits_used = 1 }, // 268
    .{ .symbol = 19, .bits_used = 2 }, // 269
    .{ .symbol = 23, .bits_used = 2 }, // 270
    .{ .symbol = 27, .bits_used = 2 }, // 271
    .{ .symbol = 31, .bits_used = 2 }, // 272
    .{ .symbol = 35, .bits_used = 3 }, // 273
    .{ .symbol = 43, .bits_used = 3 }, // 274
    .{ .symbol = 51, .bits_used = 3 }, // 275
    .{ .symbol = 59, .bits_used = 3 }, // 276
    .{ .symbol = 67, .bits_used = 4 }, // 277
    .{ .symbol = 83, .bits_used = 4 }, // 278
    .{ .symbol = 99, .bits_used = 4 }, // 279
    .{ .symbol = 115, .bits_used = 4 }, // 280
    .{ .symbol = 131, .bits_used = 5 }, // 281
    .{ .symbol = 163, .bits_used = 5 }, // 282
    .{ .symbol = 195, .bits_used = 5 }, // 283
    .{ .symbol = 227, .bits_used = 5 }, // 284
    .{ .symbol = 258, .bits_used = 0 }, // 285
};

const distance_extra = [_]HuffmanEntry{
    .{ .symbol = 1, .bits_used = 0 }, // 0
    .{ .symbol = 2, .bits_used = 0 }, // 1
    .{ .symbol = 3, .bits_used = 0 }, // 2
    .{ .symbol = 4, .bits_used = 0 }, // 3
    .{ .symbol = 5, .bits_used = 1 }, // 4
    .{ .symbol = 7, .bits_used = 1 }, // 5
    .{ .symbol = 9, .bits_used = 2 }, // 6
    .{ .symbol = 13, .bits_used = 2 }, // 7
    .{ .symbol = 17, .bits_used = 3 }, // 8
    .{ .symbol = 25, .bits_used = 3 }, // 9
    .{ .symbol = 33, .bits_used = 4 }, // 10
    .{ .symbol = 49, .bits_used = 4 }, // 11
    .{ .symbol = 65, .bits_used = 5 }, // 12
    .{ .symbol = 97, .bits_used = 5 }, // 13
    .{ .symbol = 129, .bits_used = 6 }, // 14
    .{ .symbol = 193, .bits_used = 6 }, // 15
    .{ .symbol = 257, .bits_used = 7 }, // 16
    .{ .symbol = 385, .bits_used = 7 }, // 17
    .{ .symbol = 513, .bits_used = 8 }, // 18
    .{ .symbol = 769, .bits_used = 8 }, // 19
    .{ .symbol = 1025, .bits_used = 9 }, // 20
    .{ .symbol = 1537, .bits_used = 9 }, // 21
    .{ .symbol = 2049, .bits_used = 10 }, // 22
    .{ .symbol = 3073, .bits_used = 10 }, // 23
    .{ .symbol = 4097, .bits_used = 11 }, // 24
    .{ .symbol = 6145, .bits_used = 11 }, // 25
    .{ .symbol = 8193, .bits_used = 12 }, // 26
    .{ .symbol = 12289, .bits_used = 12 }, // 27
    .{ .symbol = 16385, .bits_used = 13 }, // 28
    .{ .symbol = 24577, .bits_used = 13 }, // 29
};

fn filter1And2(x: []u8, a: []u8, channel: u32) u8 {
    return x[channel] +% a[channel];
}

fn filter3(x: []u8, a: []u8, b: []u8, channel: u32) u8 {
    const average: u32 = @divFloor(@as(u32, @intCast(a[channel])) + @as(u32, @intCast(b[channel])), 2);
    return x[channel] +% @as(u8, @intCast(average));
}

fn filter4(x: []u8, a_full: []u8, b_full: []u8, c_full: []u8, channel: u32) u8 {
    const a: i32 = @intCast(a_full[channel]);
    const b: i32 = @intCast(b_full[channel]);
    const c: i32 = @intCast(c_full[channel]);
    const p: i32 = a + b - c;

    var pa: i32 = p - a;
    if (pa < 0) pa = -pa;

    var pb: i32 = p - b;
    if (pb < 0) pb = -pb;

    var pc: i32 = p - c;
    if (pc < 0) pc = -pc;

    var paeth: i32 = 0;
    if (pa <= pb and pa <= pc) {
        paeth = a;
    } else if (pb <= pc) {
        paeth = b;
    } else {
        paeth = c;
    }

    return x[channel] +% @as(u8, @intCast(paeth));
}

fn filterReconstruct(height: u32, width: u32, decompressed_pixels: []u8, final_pixels: []u8, errors: ?*Stream) void {
    var zero: u32 = 0;
    var prior_row: []u8 = @ptrCast(&zero);
    var prior_row_advance: u32 = 0;
    var source: []u8 = decompressed_pixels;
    var dest: []u8 = final_pixels;

    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const filter: u8 = source[0];
        source.ptr += 1;
        const current_row: []u8 = dest;

        switch (filter) {
            0 => {
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    dest[0] = source[0];
                    dest[1] = source[1];
                    dest[2] = source[2];
                    dest[3] = source[3];

                    dest.ptr += 4;
                    source.ptr += 4;
                }
            },
            1 => {
                var a_pixel: u32 = 0;

                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    dest[0] = filter1And2(source, @as([]u8, @ptrCast(&a_pixel)), 0);
                    dest[1] = filter1And2(source, @as([]u8, @ptrCast(&a_pixel)), 1);
                    dest[2] = filter1And2(source, @as([]u8, @ptrCast(&a_pixel)), 2);
                    dest[3] = filter1And2(source, @as([]u8, @ptrCast(&a_pixel)), 3);

                    a_pixel = @as([]u32, @ptrCast(@alignCast(dest)))[0];

                    dest.ptr += 4;
                    source.ptr += 4;
                }
            },
            2 => {
                var b_pixel: []u8 = prior_row;
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    dest[0] = filter1And2(source, b_pixel, 0);
                    dest[1] = filter1And2(source, b_pixel, 1);
                    dest[2] = filter1And2(source, b_pixel, 2);
                    dest[3] = filter1And2(source, b_pixel, 3);

                    b_pixel.ptr += prior_row_advance;
                    dest.ptr += 4;
                    source.ptr += 4;
                }
            },
            3 => {
                var a_pixel: u32 = 0;

                var b_pixel: []u8 = prior_row;
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    dest[0] = filter3(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, 0);
                    dest[1] = filter3(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, 1);
                    dest[2] = filter3(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, 2);
                    dest[3] = filter3(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, 3);

                    a_pixel = @as([]u32, @ptrCast(@alignCast(dest)))[0];

                    b_pixel.ptr += prior_row_advance;
                    dest.ptr += 4;
                    source.ptr += 4;
                }
            },
            4 => {
                var a_pixel: u32 = 0;
                var b_pixel: []u8 = prior_row;
                var c_pixel: u32 = 0;

                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    dest[0] = filter4(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, @as([]u8, @ptrCast(&c_pixel)), 0);
                    dest[1] = filter4(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, @as([]u8, @ptrCast(&c_pixel)), 1);
                    dest[2] = filter4(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, @as([]u8, @ptrCast(&c_pixel)), 2);
                    dest[3] = filter4(source, @as([]u8, @ptrCast(&a_pixel)), b_pixel, @as([]u8, @ptrCast(&c_pixel)), 3);

                    c_pixel = @as([]u32, @ptrCast(@alignCast(b_pixel)))[0];
                    a_pixel = @as([]u32, @ptrCast(@alignCast(dest)))[0];

                    b_pixel.ptr += prior_row_advance;
                    dest.ptr += 4;
                    source.ptr += 4;
                }
            },
            else => {
                stream.output(errors, @src(), "Unrecognized row filter: %d.\n", .{filter});
            },
        }

        prior_row = current_row;
        prior_row_advance = 4;
    }
}

/// This is not meant to be fault tolerant. It only loads specifically what we expect, and is happy to crash otherwise.
pub fn parsePNG(arena: *MemoryArena, file: Stream, info: ?*Stream) ImageU32 {
    var at: Stream = file;

    var supported: bool = false;

    var final_pixels: ?[]u8 = null;
    var width: u32 = 0;
    var height: u32 = 0;

    if (at.consumeType(Header)) |header| {
        _ = header;

        var compressed_data: Stream = .onDemandMemoryStream(arena, file.errors);

        while (at.content_size > 0) {
            if (at.consumeType(ChunkHeader)) |chunk_header| {
                endianSwap(&chunk_header.length);

                const chunk_data: ?[*c]u8 = at.consumeSize(chunk_header.length);

                if (at.consumeType(ChunkFooter)) |chunk_footer| {
                    endianSwap(&chunk_footer.crc);

                    if (chunk_header.chunkTypeU32() == fourcc("IHDR")) {
                        stream.output(info, @src(), "IHDR\n", .{});

                        const ihdr: *IHeader = @ptrCast(@alignCast(chunk_data));
                        endianSwap(&ihdr.width);
                        endianSwap(&ihdr.height);

                        stream.output(info, @src(), "    width: %u\n", .{ihdr.width});
                        stream.output(info, @src(), "    height: %u\n", .{ihdr.height});
                        stream.output(info, @src(), "    bit_depth: %u\n", .{ihdr.bit_depth});
                        stream.output(info, @src(), "    color_type: %u\n", .{ihdr.color_type});
                        stream.output(info, @src(), "    compression_method: %u\n", .{ihdr.compression_method});
                        stream.output(info, @src(), "    filter_method: %u\n", .{ihdr.filter_method});
                        stream.output(info, @src(), "    interlace_method: %u\n", .{ihdr.interlace_method});

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
                        stream.output(info, @src(), "IDAT (%u)\n", .{chunk_header.length});

                        _ = compressed_data.appendChunk(
                            chunk_header.length,
                            @ptrCast(chunk_data.?[0..chunk_header.length]),
                        );
                    }
                }
            }
        }

        if (supported) {
            stream.output(info, @src(), "Examining ZLIB headers...\n", .{});

            if (compressed_data.consumeType(IDataHeader)) |idat_header| {
                const cm: u8 = idat_header.zlib_method_flags & 0xf;
                const cinfo: u8 = idat_header.zlib_method_flags >> 4;
                const fcheck: u8 = idat_header.additional_flags & 0x1f;
                const fdict: u8 = (idat_header.additional_flags >> 5) & 0x1;
                const flevel: u8 = idat_header.additional_flags >> 6;

                stream.output(info, @src(), "    cm: %u\n", .{cm});
                stream.output(info, @src(), "    cinfo: %u\n", .{cinfo});
                stream.output(info, @src(), "    fcheck: %u\n", .{fcheck});
                stream.output(info, @src(), "    fdict: %u\n", .{fdict});
                stream.output(info, @src(), "    flevel: %u\n", .{flevel});

                supported = (cm == 8 and fdict == 0);

                if (supported) {
                    stream.output(info, @src(), "Decompressing...\n", .{});

                    final_pixels = allocatePixels(arena, width, height, 4, null);
                    const decompressed_pixels: []u8 = allocatePixels(arena, width, height, 4, 1);
                    var decompressed_pixels_end: []u8 = decompressed_pixels;
                    decompressed_pixels_end.ptr += (height * ((width * 4) + 1));
                    var dest = decompressed_pixels;

                    var bfinal: u32 = 0;
                    while (bfinal == 0) {
                        std.debug.assert(@intFromPtr(dest.ptr) <= @intFromPtr(decompressed_pixels_end.ptr));

                        bfinal = compressed_data.consumeBits(1);
                        const btype: u32 = compressed_data.consumeBits(2);

                        if (btype == 0) {
                            compressed_data.flushByte();
                            var len: u16 = @intCast(compressed_data.consumeBits(16));
                            const nlen: u16 = @intCast(compressed_data.consumeBits(16));
                            if (len != ~nlen) {
                                stream.output(compressed_data.errors, @src(), "LEN/NLEN mismatch.\n", .{});
                            }

                            while (len > 0) {
                                compressed_data.refillIfNecessary();

                                var use_len: u16 = len;
                                if (use_len > compressed_data.content_size) {
                                    use_len = @intCast(compressed_data.content_size);
                                }

                                var source: ?[*]u8 = compressed_data.consumeSize(use_len);
                                if (source != null) {
                                    while (use_len > 0) : (use_len -= 1) {
                                        dest[0] = source.?[0];
                                        dest.ptr += 1;
                                        source.? += 1;
                                    }
                                }

                                len -= use_len;
                            }
                        } else if (btype == 3) {
                            stream.output(compressed_data.errors, @src(), "BTYPE of %u encountered.\n", .{btype});
                        } else {
                            var literal_length_distance_table: [512]u32 = undefined;
                            var literal_length_huffman: Huffman = allocateHuffman(arena, 15);
                            var distance_huffman: Huffman = allocateHuffman(arena, 15);
                            var hlit: u32 = 0;
                            var hdist: u32 = 0;

                            if (btype == 2) {
                                hlit = compressed_data.consumeBits(5);
                                hdist = compressed_data.consumeBits(5);
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

                                var dictionary_huffman: Huffman = allocateHuffman(arena, 7);
                                dictionary_huffman.compute(hclen_swizzle.len, &hclen_table, null);

                                var literal_length_count: u32 = 0;
                                const length_count: u32 = hlit + hdist;
                                std.debug.assert(length_count <= literal_length_distance_table.len);
                                while (literal_length_count < length_count) {
                                    var repeat_count: u32 = 1;
                                    var repeat_value: u32 = 0;
                                    const encoded_length: u32 = dictionary_huffman.decode(&compressed_data);

                                    if (encoded_length <= 15) {
                                        repeat_value = encoded_length;
                                    } else if (encoded_length == 16) {
                                        repeat_count = 3 + compressed_data.consumeBits(2);
                                        std.debug.assert(literal_length_count > 0);
                                        repeat_value = literal_length_distance_table[literal_length_count - 1];
                                    } else if (encoded_length == 17) {
                                        repeat_count = 3 + compressed_data.consumeBits(3);
                                    } else if (encoded_length == 18) {
                                        repeat_count = 11 + compressed_data.consumeBits(7);
                                    } else {
                                        stream.output(compressed_data.errors, @src(), "Encoded length of %u encountered.\n", .{encoded_length});
                                    }

                                    while (repeat_count > 0) : (repeat_count -= 1) {
                                        literal_length_distance_table[literal_length_count] = repeat_value;
                                        literal_length_count += 1;
                                    }
                                }

                                std.debug.assert(literal_length_count == length_count);
                            } else if (btype == 1) {
                                hlit = 288;
                                hdist = 32;
                                const bit_counts = [_][2]u32{
                                    .{ 143, 8 },
                                    .{ 255, 9 },
                                    .{ 279, 7 },
                                    .{ 287, 8 },
                                    .{ 319, 5 },
                                };

                                var bit_count_index: u32 = 0;
                                var range_index: u32 = 0;
                                while (range_index < bit_counts.len) : (range_index += 1) {
                                    const bit_count: u32 = bit_counts[range_index][1];
                                    const last_value: u32 = bit_counts[range_index][0];
                                    while (bit_count_index <= last_value) : (bit_count_index += 1) {
                                        literal_length_distance_table[bit_count_index] = bit_count;
                                    }
                                }
                            } else {
                                stream.output(compressed_data.errors, @src(), "BTYPE of %u encountered.\n", .{btype});
                            }

                            literal_length_huffman.compute(hlit, &literal_length_distance_table, null);
                            distance_huffman.compute(hdist, @ptrCast(&literal_length_distance_table[hlit]), null);

                            while (true) {
                                const literal_length: u32 = literal_length_huffman.decode(&compressed_data);
                                if (literal_length <= 255) {
                                    const out: u32 = literal_length & 0xff;
                                    dest[0] = @truncate(out);
                                    dest.ptr += 1;
                                } else if (literal_length >= 257) {
                                    const length_table_index: u32 = literal_length - 257;
                                    const length_table_entry: HuffmanEntry = length_extra[length_table_index];
                                    var length: u32 = length_table_entry.symbol;
                                    if (length_table_entry.bits_used > 0) {
                                        const extra_bits: u32 =
                                            compressed_data.consumeBits(length_table_entry.bits_used);
                                        length += extra_bits;
                                    }

                                    const distance_table_index: u32 = distance_huffman.decode(&compressed_data);
                                    const distance_table_entry: HuffmanEntry = distance_extra[distance_table_index];
                                    var distance: u32 = distance_table_entry.symbol;
                                    if (distance_table_entry.bits_used > 0) {
                                        const extra_bits: u32 =
                                            compressed_data.consumeBits(distance_table_entry.bits_used);
                                        distance += extra_bits;
                                    }

                                    var source: [*]u8 = @ptrFromInt(@intFromPtr(dest.ptr) - distance);
                                    std.debug.assert((@intFromPtr(source) + length) <= @intFromPtr(decompressed_pixels_end.ptr));
                                    std.debug.assert((@intFromPtr(dest.ptr) + length) <= @intFromPtr(decompressed_pixels_end.ptr));
                                    std.debug.assert(@intFromPtr(source) >= @intFromPtr(decompressed_pixels.ptr));

                                    while (length > 0) : (length -= 1) {
                                        dest[0] = source[0];
                                        dest.ptr += 1;
                                        source += 1;
                                    }
                                } else {
                                    break;
                                }
                            }
                        }
                    }

                    std.debug.assert(@intFromPtr(dest.ptr) == @intFromPtr(decompressed_pixels_end.ptr));
                    filterReconstruct(height, width, decompressed_pixels, final_pixels.?, compressed_data.errors);
                }
            }
        }
    }

    stream.output(info, @src(), "Supported: %s\n", .{if (supported) "true" else "false"});

    const result: ImageU32 = .{
        .width = width,
        .height = height,
        .pixels = @ptrCast(@alignCast(final_pixels)),
    };

    return result;
}
