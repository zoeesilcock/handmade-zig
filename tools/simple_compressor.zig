const std = @import("std");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 4) {
        var final_output_size: usize = 0;
        var final_output_buffer: [*]u8 = undefined;

        var out_buffer: []u8 = undefined;
        defer allocator.free(out_buffer);

        const command = args[1];
        const in_filename = args[2];
        const out_filename = args[3];

        const in_file = try readEntireFileIntoMemory(in_filename, allocator);
        defer allocator.free(in_file.contents);

        if (std.mem.eql(u8, command, "compress")) {
            const out_buffer_size: usize = getMaxCompressedOutputSize(in_file.file_size);
            out_buffer = try allocator.alloc(u8, out_buffer_size);
            const compressed_size: usize =
                compress(@intCast(in_file.file_size), in_file.contents.ptr, out_buffer_size, out_buffer.ptr + 4);

            var out: [*]u32 = @ptrCast(@alignCast(out_buffer));
            out[0] = @intCast(in_file.file_size);

            final_output_size = compressed_size + 4;
            final_output_buffer = out_buffer.ptr;
        } else if (std.mem.eql(u8, command, "decompress")) {
            if (in_file.file_size >= 4) {
                const in: [*]const u32 = @ptrCast(@alignCast(in_file.contents));
                const out_buffer_size: u32 = in[0];
                out_buffer = try allocator.alloc(u8, out_buffer_size);
                decompress(in_file.file_size - 4, in_file.contents.ptr + 4, out_buffer_size, out_buffer.ptr);

                final_output_size = out_buffer_size;
                final_output_buffer = out_buffer.ptr;
            } else {
                std.log.err("Invalid input file", .{});
            }
        } else {
            std.log.err("Unrecognized command: {s}", .{command});
        }

        if (final_output_size > 0) {
            if (std.fs.cwd().createFile(out_filename, .{})) |file| {
                defer file.close();

                try file.writeAll(final_output_buffer[0..final_output_size]);
            } else |err| {
                std.log.err("Cannot open output file '{s}': {s}", .{ out_filename, @errorName(err) });
            }
        }
    } else {
        std.log.err("Usage: {s} compress [raw filename] [compressed filename]", .{args[0]});
        std.log.err("       {s} decompress [raw filename] [compressed filename]", .{args[0]});
    }
}

fn getMaxCompressedOutputSize(in_size: usize) usize {
    return 256 + 2 * in_size;
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

fn rleCompress(in_size: usize, in_in: [*]const u8, max_out_size: usize, out_in: [*]u8) usize {
    const MAX_LITERAL_COUNT = 255;
    const MAX_RUN_COUNT = 255;
    var literal_count: u32 = 0;
    var literals: [MAX_LITERAL_COUNT]u8 = [1]u8{0} ** MAX_LITERAL_COUNT;

    var in: [*]const u8 = in_in;
    var out: [*]u8 = out_in;
    const in_end = in + in_size;
    while (@intFromPtr(in) < @intFromPtr(in_end)) {
        const starting_value: u8 = in[0];
        var run: usize = 1;
        while (run < (in_end - in) and run < MAX_RUN_COUNT and in[run] == starting_value) {
            run += 1;
        }

        if (run > 1 or literal_count == MAX_LITERAL_COUNT) {
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
        } else {
            // Buffer literals.
            literals[literal_count] = starting_value;
            literal_count += 1;

            in += 1;
        }
    }

    std.debug.assert(in == in_end);

    const out_size = out - out_in;
    std.debug.assert(out_size <= max_out_size);

    return out_size;
}

fn rleDecompress(in_size: usize, in_in: [*]const u8, out_size: usize, out_in: [*]u8) void {
    _ = out_size;

    var in: [*]const u8 = in_in;
    var out: [*]u8 = out_in;
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

fn compress(in_size: usize, in: [*]const u8, max_out_size: usize, out: [*]u8) usize {
    return rleCompress(in_size, in, max_out_size, out);
}

fn decompress(in_size: usize, in: [*]const u8, out_size: usize, out: [*]u8) void {
    return rleDecompress(in_size, in, out_size, out);
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

        const buffer = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, @alignOf(u32), 0);
        result.contents = buffer;
    } else |err| {
        std.log.err("Cannot open input file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}
