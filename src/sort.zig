const std = @import("std");
const shared = @import("shared.zig");
const math = @import("math.zig");
const debug_interface = @import("debug_interface.zig");

const INTERNAL = shared.INTERNAL;

const Rectangle2 = math.Rectangle2;
const RenderCommands = shared.RenderCommands;
const TimedBlock = debug_interface.TimedBlock;
const MemoryArena = shared.MemoryArena;

pub const SortEntry = struct {
    sort_key: f32,
    index: u32,
};

fn swap(a: [*]SortEntry, b: [*]SortEntry) void {
    const store: SortEntry = b[0];
    b[0] = a[0];
    a[0] = store;
}

fn sortKeyToU32(sort_key: f32) u32 {
    var result: u32 = @bitCast(sort_key);

    if ((result & 0x80000000) != 0) {
        // Signed bit is set.
        result = ~result;
    } else {
        result |= 0x80000000;
    }

    return result;
}

pub fn bubbleSort(count: u32, first: [*]SortEntry, _: [*]SortEntry) void {
    var outer: u32 = 0;
    while (outer < count) : (outer += 1) {
        var list_is_sorted = true;
        var inner: u32 = 0;
        while (inner < count - 1) : (inner += 1) {
            const entry_a: [*]SortEntry = first + inner;
            const entry_b: [*]SortEntry = entry_a + 1;

            if (entry_a[0].sort_key > entry_b[0].sort_key) {
                swap(entry_a, entry_b);
                list_is_sorted = false;
            }
        }

        if (list_is_sorted) {
            break;
        }
    }
}

pub fn mergeSort(count: u32, first: [*]SortEntry, temp: [*]SortEntry) void {
    if (count <= 1) {
        // Nothing to do.
    } else if (count == 2) {
        const entry_a: [*]SortEntry = first;
        const entry_b: [*]SortEntry = entry_a + 1;
        if (entry_a[0].sort_key > entry_b[0].sort_key) {
            swap(entry_a, entry_b);
        }
    } else {
        const half0: u32 = @divFloor(count, 2);
        const half1: u32 = count - half0;

        std.debug.assert(half0 >= 1);
        std.debug.assert(half1 >= 1);

        const in_half0: [*]SortEntry = first;
        const in_half1: [*]SortEntry = first + half0;
        const end: [*]SortEntry = first + count;

        mergeSort(half0, in_half0, temp);
        mergeSort(half1, in_half1, temp);

        var read_half0: [*]SortEntry = in_half0;
        var read_half1: [*]SortEntry = in_half1;

        var out: [*]SortEntry = temp;
        var index: u32 = 0;
        while (index < count) : (index += 1) {
            if (read_half0 == in_half1) {
                out[0] = read_half1[0];
                read_half1 += 1;
                out += 1;
            } else if (read_half1 == end) {
                out[0] = read_half0[0];
                read_half0 += 1;
                out += 1;
            } else if (read_half0[0].sort_key < read_half1[0].sort_key) {
                out[0] = read_half0[0];
                read_half0 += 1;
                out += 1;
            } else {
                out[0] = read_half1[0];
                read_half1 += 1;
                out += 1;
            }
        }

        std.debug.assert(out == (temp + count));
        std.debug.assert(read_half0 == in_half1);
        std.debug.assert(read_half1 == end);

        index = 0;
        while (index < count) : (index += 1) {
            first[index] = temp[index];
        }
    }
}

pub fn radixSort(count: u32, first: [*]SortEntry, temp: [*]SortEntry) void {
    var source: [*]SortEntry = first;
    var dest: [*]SortEntry = temp;

    var byte_index: u32 = 0;
    while (byte_index < 32) : (byte_index += 8) {
        var sort_key_offsets: [256]u32 = [1]u32{0} ** 256;

        // First pass, count how many of each key.
        var index: u32 = 0;
        while (index < count) : (index += 1) {
            const radix_value: u32 = sortKeyToU32(source[index].sort_key);
            const radix_piece: u32 = (radix_value >> @as(u5, @intCast(byte_index))) & 0xff;
            sort_key_offsets[radix_piece] += 1;
        }

        // Change counts to offsets.
        var total: u32 = 0;
        var sort_key_index: u32 = 0;
        while (sort_key_index < sort_key_offsets.len) : (sort_key_index += 1) {
            const key_count: u32 = sort_key_offsets[sort_key_index];
            sort_key_offsets[sort_key_index] = total;
            total += key_count;
        }

        // Second pass, place elements into the right location.
        index = 0;
        while (index < count) : (index += 1) {
            const radix_value: u32 = sortKeyToU32(source[index].sort_key);
            const radix_piece: u32 = (radix_value >> @as(u5, @intCast(byte_index))) & 0xff;
            dest[sort_key_offsets[radix_piece]] = source[index];
            sort_key_offsets[radix_piece] += 1;
        }

        const swap_temp: [*]SortEntry = dest;
        dest = source;
        source = swap_temp;
    }
}
