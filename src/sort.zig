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

const SpriteFlag = enum(u32) {
    Visited = 0x1,
    Drawn = 0x2,
};

pub const SortSpriteBound = struct {
    first_edge_with_me_as_front: ?*SpriteEdge,
    screen_area: Rectangle2,
    sort_key: SpriteBound,
    index: u32,
    flags: u32,
};

pub const SpriteBound = struct {
    y_min: f32,
    y_max: f32,
    z_max: f32,
};

const SpriteEdge = struct {
    next_edge_with_same_front: ?*SpriteEdge,
    front: u32,
    behind: u32,
};

pub fn getSortEntries(commands: *shared.RenderCommands) [*]SortSpriteBound {
    return @ptrFromInt(@intFromPtr(commands.push_buffer_base) + commands.sort_entry_at);
}

pub fn getSortTempMemorySize(commands: *shared.RenderCommands) u64 {
    return commands.push_buffer_element_count * @sizeOf(SortSpriteBound);
}

fn addEdge(a: SpriteEdge, b: SpriteEdge) void {
    _ = a;
    _ = b;
}

fn buildSpriteGraph(input_node_count: u32, input_nodes: [*]SortSpriteBound, arena: ?*MemoryArena) void {
    if (input_node_count > 0) {
        var node_index_a: u32 = 0;
        while (node_index_a < input_node_count - 1) : (node_index_a += 1) {
            const a: *SortSpriteBound = @ptrCast(input_nodes + node_index_a);
            std.debug.assert(a.flags == 0);

            var node_index_b: u32 = node_index_a;
            while (node_index_b < input_node_count) : (node_index_b += 1) {
                const b: *SortSpriteBound = @ptrCast(input_nodes + node_index_b);

                if (a.screen_area.intersects(b.screen_area)) {
                    var front_index: u32 = node_index_a;
                    var back_index: u32 = node_index_b;
                    if (isInFrontOf(b.sort_key, a.sort_key)) {
                        const temp: u32 = front_index;
                        front_index = back_index;
                        back_index = temp;
                    }

                    _ = arena;
                    var edge: ?*SpriteEdge = null; // arena.pushStruct(SpriteEdge);
                    const front: *SortSpriteBound = @ptrCast(input_nodes + front_index);
                    edge.front = front_index;
                    edge.behind = back_index;

                    edge.next_edge_with_same_front = front.first_edge_with_me_as_front;
                    front.first_edge_with_me_as_front = edge;
                }
            }
        }
    }
}

const SpriteGraphWalk = struct {
    input_nodes: [*]SortSpriteBound,
    out_index: [*]u32,
};

fn recursiveFrontToBack(walk: *SpriteGraphWalk, at_index: u32) void {
    const at: *SortSpriteBound = @ptrCast(walk.input_nodes + at_index);
    if ((at.flags & @intFromEnum(SpriteFlag.Visited)) == 0) {
        at.flags |= @intFromEnum(SpriteFlag.Visited);

        var opt_edge: ?*SpriteEdge = at[0].first_edge_with_me_as_front;
        while (opt_edge) |edge| : (opt_edge = edge.next_edge_with_same_front) {
            std.debug.assert(edge.front == at_index);
            recursiveFrontToBack(walk, edge.behind);
        }

        walk.*.out_index = at_index;
        walk.*.out_index += 1;
    }
}

fn walkSpriteGraph(input_node_count: u32, input_nodes: [*]SortSpriteBound, out_index_array: [*]u32) void {
    var walk: SpriteGraphWalk = .{
        .input_nodes = input_nodes,
        .out_index = out_index_array,
    };
    var node_index_a: u32 = 0;
    while (node_index_a < input_node_count - 1) : (node_index_a += 1) {
        recursiveFrontToBack(&walk, node_index_a);
    }
}

pub fn sortEntries(commands: *RenderCommands, temp_arena: *MemoryArena, out_index_array: [*]u32) void {
    TimedBlock.beginFunction(@src(), .SortEntries);
    defer TimedBlock.endFunction(@src(), .SortEntries);

    const count: u32 = commands.push_buffer_element_count;
    const entries: [*]SortSpriteBound = getSortEntries(commands);

    buildSpriteGraph(count, entries, temp_arena);
    walkSpriteGraph(count, entries, out_index_array);

    if (INTERNAL) {
        if (count > 0) {
            // Validate the sort result.
            var index: u32 = 0;
            while (index < @as(i32, @intCast(count)) - 1) : (index += 1) {
                var index_b: u32 = index + 1;
                // Partial ordering check, 0(n), only neighbors are verified.
                var count_b: u32 = 1;

                if (true) {
                    // Total ordering check, 0(n^2), all pairs verified.
                    count_b = count;
                }

                while (index_b < count_b) : (index_b += 1) {
                    const entry_a: [*]SortSpriteBound = entries + index;
                    const entry_b: [*]SortSpriteBound = entries + index_b;

                    if (isInFrontOf(entry_a[0].sort_key, entry_b[0].sort_key)) {
                        std.debug.assert(
                            entry_a[0].sort_key.y_min == entry_b[0].sort_key.y_min and
                            entry_a[0].sort_key.y_max == entry_b[0].sort_key.y_max and
                            entry_a[0].sort_key.z_max == entry_b[0].sort_key.z_max
                        );
                    }
                }
            }
        }
    }
}

pub fn isInFrontOf(a: SpriteBound, b: SpriteBound) bool {
    const both_z_sprites: bool = a.y_min != a.y_max and b.y_min != b.y_max;
    const a_includes_b: bool = b.y_min >= a.y_min and b.y_min < a.y_max;
    const b_includes_a: bool = a.y_min >= b.y_min and a.y_min < b.y_max;

    const sort_by_z: bool = both_z_sprites or a_includes_b or b_includes_a;

    const result: bool = if (sort_by_z)
        a.z_max > b.z_max
    else
        a.y_min < b.y_min;

    return result;
}

fn swapSpriteBound(a: [*]SortSpriteBound, b: [*]SortSpriteBound) void {
    const temp: SortSpriteBound = b[0];
    b[0] = a[0];
    a[0] = temp;
}

pub fn mergeSortSpriteBound(count: u32, first: [*]SortSpriteBound, temp: [*]SortSpriteBound) void {
    if (count <= 1) {
        // Nothing to do.
    } else if (count == 2) {
        const entry_a: [*]SortSpriteBound = first;
        const entry_b: [*]SortSpriteBound = first + 1;
        if (isInFrontOf(entry_a[0].sort_key, entry_b[0].sort_key)) {
            swapSpriteBound(entry_a, entry_b);
        }
    } else {
        const half0: u32 = @divFloor(count, 2);
        const half1: u32 = count - half0;

        std.debug.assert(half0 >= 1);
        std.debug.assert(half1 >= 1);

        const in_half0: [*]SortSpriteBound = first;
        const in_half1: [*]SortSpriteBound = first + half0;
        const end: [*]SortSpriteBound = first + count;

        mergeSortSpriteBound(half0, in_half0, temp);
        mergeSortSpriteBound(half1, in_half1, temp);

        var read_half0: [*]SortSpriteBound = in_half0;
        var read_half1: [*]SortSpriteBound = in_half1;

        var out: [*]SortSpriteBound = temp;
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
            } else if (isInFrontOf(read_half1[0].sort_key, read_half0[0].sort_key)) {
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

fn isZSprite(bound: SpriteBound) bool {
    return bound.y_min != bound.y_max;
}

fn verifyBuffer(count: u32, buffer: [*]SortSpriteBound, z_sprite: bool) void {
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        std.debug.assert(isZSprite(buffer[index].sort_key) == z_sprite);
        if (index > 0) {
            std.debug.assert(isInFrontOf(buffer[index].sort_key, buffer[index - 1].sort_key));
        }
    }
}

pub fn separatedSort(count: u32, first: [*]SortSpriteBound, temp: [*]SortSpriteBound) void {
    var y_count: u32 = 0;
    var z_count: u32 = 0;
    {
        var index: u32 = 0;
        while (index < count) : (index += 1) {
            const this: [*]SortSpriteBound = first + index;
            if (isZSprite(this[0].sort_key)) {
                temp[z_count] = this[0];
                z_count += 1;
            } else {
                first[y_count] = this[0];
                y_count += 1;
            }
        }
    }

    if (INTERNAL) {
        verifyBuffer(y_count, first, false);
        verifyBuffer(z_count, temp, true);
    }

    mergeSortSpriteBound(y_count, first, temp + z_count);
    mergeSortSpriteBound(z_count, temp, first + y_count);

    if (y_count == 1) {
        temp[z_count] = first[0];
    } else if (y_count == 2) {
        temp[y_count] = first[0];
        temp[y_count + 1] = first[1];
    }

    const in_half0: [*]SortSpriteBound = temp;
    const in_half1: [*]SortSpriteBound = temp + z_count;

    if (INTERNAL) {
        verifyBuffer(y_count, in_half1, false);
        verifyBuffer(z_count, in_half0, true);
    }

    const end: [*]SortSpriteBound = in_half1 + y_count;
    var read_half0: [*]SortSpriteBound = in_half0;
    var read_half1: [*]SortSpriteBound = in_half1;

    var out: [*]SortSpriteBound = first;
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
        // TODO: This merge comparison can be simpler now since we know which sprite is a Z sprite and which is a Y sprite.
        } else if (isInFrontOf(read_half1[0].sort_key, read_half0[0].sort_key)) {
            out[0] = read_half0[0];
            read_half0 += 1;
            out += 1;
        } else {
            out[0] = read_half1[0];
            read_half1 += 1;
            out += 1;
        }
    }

    std.debug.assert(out == (first + count));
    std.debug.assert(read_half0 == in_half1);
    std.debug.assert(read_half1 == end);
}
