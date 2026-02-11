const std = @import("std");

/// This is extremely rudimentary compression code tha tonly does the barest minimum of work.
///
/// Ways that this code could be improved.
///
/// * Figure out an efficient way to expand the LZ encoding to support > 255 size lookback and/or runs.
/// * Add an entropy backend like Huffman, Arithmetic, something from the ANS family.
/// * Add a hash lookup or other acceleration structure to the LZ encoder so that it isn't unusably slow.
/// * Add better heuristics to the LZ copressor to get closer to an optimal parse.
/// * Add precoditioners to test whether something better can be done for bitmaps (like differencing,
///   deinterleaving by 4, etc.)
/// * Add the concept of switchable compression mid-stream to allow different blocks to be encoded with different
///   methods.
pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 5) {
        var final_output_size: usize = 0;
        var final_output_buffer: [*]u8 = undefined;

        var out_buffer: []u8 = undefined;
        defer allocator.free(out_buffer);

        const codec_name = args[1];
        const command = args[2];
        const in_filename = args[3];
        const out_filename = args[4];

        var stats: StatGroup = .{};

        var opt_compressor: ?*const Compressor = null;
        var compressor_index: u32 = 0;
        while (compressor_index < compressors.len) : (compressor_index += 1) {
            const test_compressor: *const Compressor = &compressors[compressor_index];
            if (std.mem.eql(u8, codec_name, test_compressor.name)) {
                opt_compressor = test_compressor;
            }
        }

        if (opt_compressor) |compressor| {
            const in_file = try readEntireFileIntoMemory(in_filename, allocator);
            defer allocator.free(in_file.contents);

            if (std.mem.eql(u8, command, "compress")) {
                const out_buffer_size: usize = getMaxCompressedOutputSize(in_file.file_size);
                out_buffer = try allocator.alloc(u8, out_buffer_size);
                const compressed_size: usize =
                    compressor.compress(
                        &stats,
                        @intCast(in_file.file_size),
                        in_file.contents.ptr,
                        out_buffer_size,
                        out_buffer.ptr + 4,
                    );

                var out: [*]u32 = @ptrCast(@alignCast(out_buffer));
                out[0] = @intCast(in_file.file_size);

                final_output_size = compressed_size + 4;
                final_output_buffer = out_buffer.ptr;

                stats.uncompressed_bytes = in_file.file_size;
                stats.compressed_bytes = compressed_size;
            } else if (std.mem.eql(u8, command, "decompress")) {
                if (in_file.file_size >= 4) {
                    const in: [*]const u32 = @ptrCast(@alignCast(in_file.contents));
                    const out_buffer_size: u32 = in[0];
                    out_buffer = try allocator.alloc(u8, out_buffer_size);
                    compressor.decompress(
                        in_file.file_size - 4,
                        in_file.contents.ptr + 4,
                        out_buffer_size,
                        out_buffer.ptr,
                    );

                    final_output_size = out_buffer_size;
                    final_output_buffer = out_buffer.ptr;
                } else {
                    std.log.err("Invalid input file", .{});
                }
            } else if (std.mem.eql(u8, command, "test")) {
                const out_buffer_size: usize = getMaxCompressedOutputSize(in_file.file_size);
                out_buffer = try allocator.alloc(u8, out_buffer_size);
                const test_buffer: []u8 = try allocator.alloc(u8, in_file.file_size);
                defer allocator.free(test_buffer);
                const compressed_size: usize =
                    compressor.compress(
                        &stats,
                        @intCast(in_file.file_size),
                        in_file.contents.ptr,
                        out_buffer_size,
                        out_buffer.ptr,
                    );

                compressor.decompress(
                    compressed_size,
                    out_buffer.ptr,
                    in_file.file_size,
                    test_buffer.ptr,
                );

                if (std.mem.eql(u8, in_file.contents, test_buffer)) {
                    std.log.info("Success!", .{});
                } else {
                    std.log.warn("Failure", .{});
                }

                stats.uncompressed_bytes = in_file.file_size;
                stats.compressed_bytes = compressed_size;
            } else {
                std.log.err("Unrecognized command: {s}", .{command});
            }
        } else {
            std.log.err("Unrecognized compressor: {s}", .{codec_name});
        }

        if (final_output_size > 0) {
            if (std.fs.cwd().createFile(out_filename, .{})) |file| {
                defer file.close();

                try file.writeAll(final_output_buffer[0..final_output_size]);
            } else |err| {
                std.log.err("Cannot open output file '{s}': {s}", .{ out_filename, @errorName(err) });
            }
        }

        printStats(&stats);
    } else {
        std.log.err("Usage: {s} [algorithm] compress [raw filename] [compressed filename]", .{args[0]});
        std.log.err("       {s} [algorithm] decompress [raw filename] [compressed filename]", .{args[0]});
        std.log.err("       {s} [algorithm] test [raw filename] [compressed filename]", .{args[0]});

        var compressor_index: u32 = 0;
        while (compressor_index < compressors.len) : (compressor_index += 1) {
            const compressor: *const Compressor = &compressors[compressor_index];
            std.log.err("[algorithm] = {s}", .{compressor.name});
        }
    }
}

const COMPRESS_HANLDER = *const fn (stats: *StatGroup, in_size: usize, in_base: [*]const u8, max_out_size: usize, out_base: [*]u8) usize;
const DECOMPRESS_HANDLER = *const fn (in_size: usize, in_base: [*]const u8, out_size: usize, out_base: [*]u8) void;
const Compressor = struct {
    name: []const u8,
    compress: COMPRESS_HANLDER,
    decompress: DECOMPRESS_HANDLER,
};
const compressors = [_]Compressor{
    .{ .name = "rle", .compress = rleCompress, .decompress = rleDecompress },
    .{ .name = "lz", .compress = lzCompress, .decompress = lzDecompress },
};

fn getMaxCompressedOutputSize(in_size: usize) usize {
    return 256 + 8 * in_size;
}

fn copy(size_in: usize, source_in: [*]const u8, dest_in: [*]u8) void {
    var size: usize = size_in;
    var source: [*]const u8 = source_in;
    var dest: [*]u8 = dest_in;

    while (size > 0) : (size -= 1) {
        dest[0] = source[0];
        dest += 1;
        source += 1;
    }
}

fn rleCompress(stats: *StatGroup, in_size: usize, in_base: [*]const u8, max_out_size: usize, out_base: [*]u8) usize {
    const MAX_LITERAL_COUNT = 255;
    const MAX_RUN_COUNT = 255;
    var literal_count: u32 = 0;
    var literals: [MAX_LITERAL_COUNT]u8 = [1]u8{0} ** MAX_LITERAL_COUNT;

    var in: [*]const u8 = in_base;
    var out: [*]u8 = out_base;
    const in_end = in + in_size;
    while (@intFromPtr(in) <= @intFromPtr(in_end)) {
        const starting_value: u8 = if (@intFromPtr(in) == @intFromPtr(in_end)) 0 else in[0];
        var run: usize = 0;
        while (run < (in_end - in) and run < MAX_RUN_COUNT and in[run] == starting_value) {
            run += 1;
        }

        if (@intFromPtr(in) == @intFromPtr(in_end) or run > 1 or literal_count == MAX_LITERAL_COUNT) {
            increment(stats, .Literal, literal_count);
            increment(stats, .Repeat, run);

            // Output a literal/run pair.
            const literal_count8: u8 = @intCast(literal_count);
            out[0] = literal_count8;
            out += 1;
            var literal_index: usize = 0;
            while (literal_index < literal_count) : (literal_index += 1) {
                out[0] = literals[literal_index];
                out += 1;
            }
            literal_count = 0;

            const run8: u8 = @intCast(run);
            out[0] = run8;
            out += 1;

            out[0] = starting_value;
            out += 1;

            in += run;

            if (@intFromPtr(in) == @intFromPtr(in_end)) {
                break;
            }
        } else {
            // Buffer literals.
            literals[literal_count] = starting_value;
            literal_count += 1;

            in += 1;
        }
    }

    std.debug.assert(in == in_end);
    std.debug.assert(literal_count == 0);

    const out_size = out - out_base;
    std.debug.assert(out_size <= max_out_size);

    return out_size;
}

fn rleDecompress(in_size: usize, in_base: [*]const u8, out_size: usize, out_base: [*]u8) void {
    _ = out_size;

    var in: [*]const u8 = in_base;
    var out: [*]u8 = out_base;
    const in_end = in + in_size;
    while (@intFromPtr(in) < @intFromPtr(in_end)) {
        var literal_count: u8 = in[0];
        in += 1;

        while (literal_count > 0) : (literal_count -= 1) {
            out[0] = in[0];
            out += 1;
            in += 1;
        }

        var replication_count: u8 = in[0];
        in += 1;
        const replication_value: u8 = in[0];
        in += 1;

        while (replication_count > 0) : (replication_count -= 1) {
            out[0] = replication_value;
            out += 1;
        }
    }

    std.debug.assert(in == in_end);
}

fn lzCompress(stats: *StatGroup, in_size: usize, in_base: [*]const u8, max_out_size: usize, out_base: [*]u8) usize {
    const MAX_LITERAL_COUNT = 255;
    const MAX_RUN_COUNT = 255;
    const MAX_LOOKBACK_COUNT = 255;
    var literal_count: u32 = 0;
    var literals: [MAX_LITERAL_COUNT]u8 = [1]u8{0} ** MAX_LITERAL_COUNT;

    var in: [*]const u8 = in_base;
    var out: [*]u8 = out_base;
    const in_end = in + in_size;
    while (@intFromPtr(in) <= @intFromPtr(in_end)) {
        var max_lookback: usize = @intFromPtr(in) - @intFromPtr(in_base);
        if (max_lookback > MAX_LOOKBACK_COUNT) {
            max_lookback = MAX_LOOKBACK_COUNT;
        }

        var best_run: usize = 0;
        var best_distance: usize = 0;
        var window_start: [*]const u8 = in - max_lookback;
        while (@intFromPtr(window_start) < @intFromPtr(in)) : (window_start += 1) {
            var window_size: usize = @intFromPtr(in_end) - @intFromPtr(window_start);
            if (window_size > MAX_RUN_COUNT) {
                window_size = MAX_RUN_COUNT;
            }

            const window_end: [*]const u8 = window_start + window_size;
            var test_in: [*]const u8 = in;
            var window_in: [*]const u8 = window_start;
            var test_run: usize = 0;
            while (@intFromPtr(window_in) < @intFromPtr(window_end) and test_in[0] == window_in[0]) {
                test_in += 1;
                window_in += 1;
                test_run += 1;
            }

            if (best_run < test_run) {
                best_run = test_run;
                best_distance = in - window_start;
            }
        }

        var output_run: bool = false;
        if (literal_count > 0) {
            output_run = best_run > 4;
        } else {
            output_run = best_run > 2;
        }

        if (@intFromPtr(in) == @intFromPtr(in_end) or output_run or literal_count == MAX_LITERAL_COUNT) {
            // Flush.
            const literal_count8: u8 = @intCast(literal_count);
            if (literal_count8 > 0) {
                increment(stats, .Literal, literal_count);

                out[0] = literal_count8;
                out += 1;
                out[0] = 0;
                out += 1;

                var literal_index: usize = 0;
                while (literal_index < literal_count) : (literal_index += 1) {
                    out[0] = literals[literal_index];
                    out += 1;
                }
                literal_count = 0;
            }

            if (output_run) {
                increment(stats, if (best_distance >= best_run) .Copy else .Repeat, best_run);

                const run8: u8 = @intCast(best_run);
                out[0] = run8;
                out += 1;

                const distance8: u8 = @intCast(best_distance);
                out[0] = distance8;
                out += 1;

                in += best_run;
            }

            if (@intFromPtr(in) == @intFromPtr(in_end)) {
                break;
            }
        } else {
            // Buffer literals.
            literals[literal_count] = in[0];
            in += 1;
            literal_count += 1;
        }
    }

    if (in != in_end) {
        // Not sure why we end up going one step too far.
        in -= 1;
    }

    std.debug.assert(in == in_end);

    const out_size = out - out_base;
    std.debug.assert(out_size <= max_out_size);

    return out_size;
}

fn lzDecompress(in_size: usize, in_base: [*]const u8, out_size: usize, out_base: [*]u8) void {
    _ = out_size;

    var in: [*]const u8 = in_base;
    var out: [*]u8 = out_base;
    const in_end = in + in_size;
    while (@intFromPtr(in) < @intFromPtr(in_end)) {
        var count: u8 = in[0];
        in += 1;

        const copy_distance: u8 = in[0];
        in += 1;

        var source: [*]const u8 = out - copy_distance;
        if (copy_distance == 0) {
            source = in;
            in += count;
        }

        while (count > 0) : (count -= 1) {
            out[0] = source[0];
            out += 1;
            source += 1;
        }
    }

    std.debug.assert(in == in_end);
}

const FileContents = struct {
    file_size: u64 = 0,
    contents: [:0]const u8 = undefined,
};

fn readEntireFileIntoMemory(file_name: []const u8, allocator: std.mem.Allocator) !FileContents {
    var result = FileContents{};

    if (std.fs.cwd().openFile(file_name, .{ .mode = .read_only })) |file| {
        defer file.close();

        _ = try file.seekFromEnd(0);
        result.file_size = try file.getPos();
        _ = try file.seekTo(0);

        const buffer = try file.readToEndAllocOptions(
            allocator,
            std.math.maxInt(u32),
            null,
            .fromByteUnits(@alignOf(u32)),
            0,
        );
        result.contents = buffer;
    } else |err| {
        std.log.err("Cannot open input file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}

const STAT_COUNT = @typeInfo(StatType).@"enum".fields.len;
const StatType = enum {
    Literal,
    Repeat,
    Copy,
};

const Stat = struct {
    count: usize = 0,
    total: usize = 0,
};

const StatGroup = struct {
    uncompressed_bytes: usize = 0,
    compressed_bytes: usize = 0,
    stats: [STAT_COUNT]Stat = [1]Stat{.{}} ** STAT_COUNT,
};

fn getStatName(stat_type: StatType) []const u8 {
    return @tagName(stat_type);
}

fn percent(num: usize, den: usize) f64 {
    var result: f64 = 0;

    if (den != 0) {
        result = @as(f64, @floatFromInt(num)) / @as(f64, @floatFromInt(den));
    }

    return 100 * result;
}

fn printStats(stats: *StatGroup) void {
    if (stats.uncompressed_bytes > 0) {
        std.log.info(
            "Compression: {d} -> {d} ({d}%)",
            .{
                stats.uncompressed_bytes,
                stats.compressed_bytes,
                percent(stats.compressed_bytes, stats.uncompressed_bytes),
            },
        );

        var stat_index: u32 = 0;
        while (stat_index < STAT_COUNT) : (stat_index += 1) {
            const stat: *Stat = &stats.stats[stat_index];
            if (stat.count > 0) {
                std.log.info("{s}: {d} {d}", .{ getStatName(@enumFromInt(stat_index)), stat.count, stat.total });
            }
        }
    }
}

fn increment(stats: *StatGroup, stat_type: StatType, value: usize) void {
    stats.stats[@intFromEnum(stat_type)].count += 1;
    stats.stats[@intFromEnum(stat_type)].total += value;
}
