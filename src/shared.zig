// Constants.
pub const MIDDLE_C: u32 = 261;
pub const TREBLE_C: u32 = 523;
pub const MAX_CONTROLLER_COUNT: u8 = 5;
pub const HIT_POINT_SUB_COUNT = 4;
pub const BITMAP_BYTES_PER_PIXEL = 4;

pub const intrinsics = @import("intrinsics.zig");
pub const math = @import("math.zig");
const memory = @import("memory.zig");
const world = @import("world.zig");
const world_mode = @import("world_mode.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const brains = @import("brains.zig");
const rendergroup = @import("rendergroup.zig");
const render = @import("render.zig");
const file_formats = @import("file_formats");
const asset = @import("asset.zig");
const audio = @import("audio.zig");
const cutscene = @import("cutscene.zig");
const random = @import("random.zig");
const debug = @import("debug.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const Color3 = math.Color3;
const LoadedBitmap = asset.LoadedBitmap;
const LoadedSound = asset.LoadedSound;
const Assets = asset.Assets;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const FontId = file_formats.FontId;
const PlayingSound = audio.PlayingSound;
const DebugTable = debug_interface.DebugTable;
const EntityId = entities.EntityId;
const BrainId = brains.BrainId;
const MemoryArena = memory.MemoryArena;
const MemoryIndex = memory.MemoryIndex;
const TemporaryMemory = memory.TemporaryMemory;
const TimedBlock = debug_interface.TimedBlock;

// Build options.
pub const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;
pub const INTERNAL = @import("build_options").internal;
pub const SLOW = @import("build_options").slow;

// Helper functions.
pub fn notImplemented() void {
    if (INTERNAL) {
        std.debug.assert(true);
    } else {
        unreachable;
    }
}

pub inline fn kilobytes(value: u32) u64 {
    return value * 1024;
}

pub inline fn megabytes(value: u32) u64 {
    return kilobytes(value) * 1024;
}

pub inline fn gigabytes(value: u32) u64 {
    return megabytes(value) * 1024;
}

pub inline fn terabytes(value: u32) u64 {
    return gigabytes(value) * 1024;
}

pub inline fn incrementPointer(pointer: anytype, offset: i32) @TypeOf(pointer) {
    return if (offset >= 0)
        pointer + @as(usize, @intCast(offset))
    else
        pointer - @abs(offset);
}

pub fn rdtsc() u64 {
    var hi: u32 = 0;
    var low: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}

pub fn getThreadId() u32 {
    const thread_local_storage_ptr = asm (
        \\movq %%gs:0x30, %[ret]
        : [ret] "=ret" (-> *anyopaque),
    );
    const thread_id: *u32 = @ptrFromInt(@intFromPtr(thread_local_storage_ptr) + 0x48);

    return thread_id.*;
}

pub const TicketMutex = extern struct {
    ticket: u64,
    serving: u64,

    pub fn begin(self: *TicketMutex) void {
        TimedBlock.beginBlock(@src(), .BeginTicketMutex);
        defer TimedBlock.endBlock(@src(), .BeginTicketMutex);

        const ticket = @atomicRmw(u64, &self.ticket, .Add, 1, .seq_cst);
        while (ticket != self.serving) {
            // TODO: This isn't implemented in Zig yet:
            // mm_pause();
        }
    }

    pub fn end(self: *TicketMutex) void {
        _ = @atomicRmw(u64, &self.serving, .Add, 1, .seq_cst);
    }
};

pub const PlatformTextureOpQueue = extern struct {
    mutex: TicketMutex = undefined,

    first: ?*render.TextureOp = null,
    last: ?*render.TextureOp = null,
    first_free: ?*render.TextureOp = null,
};

pub inline fn alignPow2(value: u32, alignment: u32) u32 {
    return (value + (alignment - 1)) & ~@as(u32, alignment - 1);
}

pub inline fn align4(value: u32) u32 {
    return (value + 3) & ~@as(u32, 3);
}

pub inline fn align8(value: u32) u32 {
    return (value + 7) & ~@as(u32, 7);
}

pub inline fn align16(value: u32) u32 {
    return (value + 15) & ~@as(u32, 15);
}

pub inline fn safeTruncateI64(value: i64) u32 {
    std.debug.assert(value <= 0xFFFFFFFF);
    return @as(u32, @intCast(value));
}

pub inline fn safeTruncateUInt32ToUInt16(value: u32) u16 {
    std.debug.assert(value <= 65535);
    std.debug.assert(value >= 0);
    return @as(u16, @intCast(value));
}

pub inline fn safeTruncateToUInt16(value: i32) u16 {
    std.debug.assert(value <= 65535);
    std.debug.assert(value >= 0);
    return @as(u16, @intCast(value));
}

pub inline fn safeTruncateToInt16(value: i32) i16 {
    std.debug.assert(value <= 32767);
    std.debug.assert(value >= -32768);
    return @as(u16, @intCast(value));
}

pub inline fn stringLength(opt_string: ?[*:0]const u8) u32 {
    var count: u32 = 0;
    if (opt_string) |string| {
        var scan = string;
        while (scan[0] != 0) : (scan += 1) {
            count += 1;
        }
    }
    return count;
}

pub inline fn stringsAreEqual(a: [*:0]const u8, b: [*:0]const u8) bool {
    var result: bool = a == b;

    var a_scan = a;
    var b_scan = b;
    while (a_scan[0] != 0 and b_scan[0] != 0 and a_scan[0] == b_scan[0]) {
        a_scan += 1;
        b_scan += 1;
    }

    result = a_scan[0] == 0 and b_scan[0] == 0;

    return result;
}

pub inline fn stringsWithLengthAreEqual(a: [*:0]const u8, a_length: MemoryIndex, b: [*:0]const u8, b_length: MemoryIndex) bool {
    var result: bool = a_length == b_length;

    if (result) {
        for (0..a_length) |i| {
            if (a[i] != b[i]) {
                result = false;
                break;
            }
        }
    }

    return result;
}

pub inline fn stringsWithOneLengthAreEqual(a: [*]const u8, a_length: MemoryIndex, opt_b: ?[*:0]const u8) bool {
    var result: bool = false;

    if (opt_b) |b| {
        var at = b;

        for (0..a_length) |i| {
            if (a[i] == 0 or a[i] != at[0]) {
                return false;
            }
            at += 1;
        }

        result = at[0] == 0;
    } else {
        result = a_length == 0;
    }

    return result;
}

pub fn isEndOfLine(char: u32) bool {
    return char == '\n' or char == '\r';
}

pub fn isWhitespace(char: u32) bool {
    return char == ' ' or char == '\t' or isEndOfLine(char);
}

pub fn i32FromZInternal(at_init: *[*]const u8) i32 {
    var result: i32 = 0;

    var at: [*]const u8 = at_init.*;
    while (at[0] >= '0' and at[0] <= '9') : (at += 1) {
        result *= 10;
        result += at[0] - '0';
    }

    at_init.* = at;

    return result;
}

pub fn i32FromZ(at_init: [*]const u8) i32 {
    var at: [*]const u8 = at_init;
    return i32FromZInternal(&at);
}

const dec_chars: []const u8 = "0123456789";
const lower_hex_chars: []const u8 = "0123456789abcdef";
const upper_hex_chars: []const u8 = "0123456789ABCDEF";

pub fn u64ToASCII(dest: *FormatDest, value_in: u64, base: u32, digits: []const u8) void {
    std.debug.assert(base != 0);

    var start: [*]u8 = dest.at;
    var value: u64 = value_in;
    var first: bool = true;
    while (first or value != 0) {
        first = false;

        const digit_index: usize = @mod(value, base);
        const digit = digits[digit_index];
        outChar(dest, digit);

        value = @divFloor(value, base);
    }
    var end: [*]u8 = dest.at;
    while (@intFromPtr(start) < @intFromPtr(end)) {
        end -= 1;
        const temp: u8 = end[0];
        end[0] = start[0];
        start[0] = temp;
        start += 1;
    }
}

pub fn f64ToASCII(dest: *FormatDest, value_in: f64, precision: i32) void {
    var value: f64 = value_in;
    if (value < 0) {
        value = -value;
        outChar(dest, '-');
    }

    const integer_part: u64 = @intFromFloat(value);
    value -= @as(f64, @floatFromInt(integer_part));
    u64ToASCII(dest, integer_part, 10, dec_chars);

    outChar(dest, '.');

    var precision_index: u32 = 0;
    while (precision_index < precision) : (precision_index += 1) {
        value *= 10;
        const integer: u32 = @intFromFloat(value);
        value -= @as(f64, @floatFromInt(integer));
        outChar(dest, dec_chars[integer]);
    }
}

const FormatDest = struct {
    size: usize,
    at: [*]u8,
};

fn outChar(dest: *FormatDest, value: u8) void {
    if (dest.size > 0) {
        dest.at[0] = value;
        dest.size -= 1;
        dest.at += 1;
    }
}

fn outChars(dest: *FormatDest, value_in: [*]const u8) void {
    var value: [*]const u8 = value_in;
    while (value[0] != 0) {
        if (dest.size > 0) {
            dest.at[0] = value[0];
            value += 1;
            dest.size -= 1;
            dest.at += 1;
        }
    }
}

fn readVarArgUnsignedInteger(args: anytype, index: *u32) u64 {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    const fields_info = args_type_info.@"struct".fields;

    var result: u64 = 0;
    inline for (fields_info, 0..) |field, i| {
        if (i == index.*) {
            switch (field.type) {
                u8, u16, u32, u64, usize => {
                    index.* += 1;
                    result = @field(args, field.name);
                },
                i8, i16, i32 => {
                    index.* += 1;
                    const value = @field(args, field.name);
                    if (value >= 0) {
                        result = @intCast(value);
                    } else {
                        result = 0;
                    }
                },
                else => |t| {
                    @panic("Unexpected argument type, expected integer type. Got: " ++ @typeName(t));
                },
            }
            break;
        }
    }
    return result;
}

fn readVarArgSignedInteger(args: anytype, index: *u32) i64 {
    const temp = readVarArgUnsignedInteger(args, index);
    return @intCast(temp);
}

fn readVarArgFloat(args: anytype, index: *u32) f64 {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    const fields_info = args_type_info.@"struct".fields;

    var result: f64 = 0;
    inline for (fields_info, 0..) |field, i| {
        if (i == index.*) {
            switch (field.type) {
                f32, f64 => {
                    index.* += 1;
                    result = @field(args, field.name);
                },
                else => |t| {
                    @panic("Unexpected argument type, expected float type. Got: " ++ @typeName(t));
                },
            }
            break;
        }
    }
    return result;
}

pub fn formatString(dest_size: usize, dest_init: [*]u8, comptime format: [*]const u8, args: anytype) usize {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    const fields_info = args_type_info.@"struct".fields;
    var arg_index: u32 = 0;

    var dest: FormatDest = .{ .at = dest_init, .size = dest_size };

    if (dest.size > 0) {
        var at: [*]const u8 = format;
        while (at[0] != 0) {
            if (at[0] == '%') {
                at += 1;

                var force_sign: bool = false;
                var pad_with_zeros: bool = false;
                var left_justify: bool = false;
                var positive_sign_is_blank: bool = false;
                var annotate_if_not_zero: bool = false;

                // Handle flags.
                var parsing: bool = true;
                while (parsing) {
                    switch (at[0]) {
                        '+' => force_sign = true,
                        '0' => pad_with_zeros = true,
                        '-' => left_justify = true,
                        ' ' => positive_sign_is_blank = true,
                        '#' => annotate_if_not_zero = true,
                        else => parsing = false,
                    }

                    if (parsing) {
                        at += 1;
                    }
                }

                // Handle width.
                var width_specified: bool = false;
                var width: i32 = 0;
                if (at[0] == '*') {
                    if (fields_info.len > arg_index) {
                        inline for (fields_info, 0..) |field, i| {
                            if (i == arg_index and field.type == i32) {
                                width = @field(args, field.name);
                                width_specified = true;
                                arg_index += 1;
                            }
                        }
                    }
                    at += 1;
                } else if (at[0] >= '0' and at[0] <= '9') {
                    width = i32FromZInternal(&at);
                    width_specified = true;
                }

                // Handle precision.
                var precision_specified: bool = false;
                var precision: i32 = 0;
                if (at[0] == '.') {
                    at += 1;
                    if (at[0] == '*') {
                        if (fields_info.len > arg_index) {
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == i32) {
                                    precision = @field(args, field.name);
                                    precision_specified = true;
                                    arg_index += 1;
                                }
                            }
                        }
                        at += 1;
                    } else if (at[0] >= '0' and at[0] <= '9') {
                        precision = i32FromZInternal(&at);
                        precision_specified = true;
                    } else {
                        @panic("Malformed precision specifier");
                    }
                }

                // Righ now our routine doesn't allow non-specified precisons.
                if (!precision_specified) {
                    precision = 6;
                }

                // Handle length.
                if (at[0] == 'h' and at[1] == 'h') {
                    at += 2;
                } else if (at[0] == 'l' and at[1] == 'l') {
                    at += 2;
                } else if (at[0] == 'h') {
                    at += 1;
                } else if (at[0] == 'l') {
                    at += 1;
                } else if (at[0] == 'j') {
                    at += 1;
                } else if (at[0] == 'z') {
                    at += 1;
                } else if (at[0] == 't') {
                    at += 1;
                } else if (at[0] == 'L') {
                    at += 1;
                }

                var temp_buffer: [64]u8 = undefined;
                var temp: [*]u8 = &temp_buffer;
                var temp_dest: FormatDest = .{ .at = temp, .size = temp_buffer.len };
                var prefix: [*]const u8 = "";
                var is_float: bool = false;

                switch (at[0]) {
                    'd', 'i' => {
                        var value: i64 = readVarArgSignedInteger(args, &arg_index);
                        const was_negative: bool = value < 0;
                        if (was_negative) {
                            value = -value;
                        }

                        u64ToASCII(&temp_dest, @intCast(value), 10, dec_chars);
                        if (was_negative) {
                            prefix = "-";
                        } else if (force_sign) {
                            std.debug.assert(!positive_sign_is_blank);
                            prefix = "+";
                        } else if (positive_sign_is_blank) {
                            prefix = " ";
                        }
                    },
                    'u' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        u64ToASCII(&temp_dest, @intCast(value), 10, dec_chars);
                    },
                    'o' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        u64ToASCII(&temp_dest, @intCast(value), 8, dec_chars);

                        if (annotate_if_not_zero and value != 0) {
                            prefix = "0";
                        }
                    },
                    'x' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        u64ToASCII(&temp_dest, @intCast(value), 16, lower_hex_chars);

                        if (annotate_if_not_zero and value != 0) {
                            prefix = "0x";
                        }
                    },
                    'X' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        u64ToASCII(&temp_dest, @intCast(value), 16, upper_hex_chars);

                        if (annotate_if_not_zero and value != 0) {
                            prefix = "0X";
                        }
                    },
                    'f', 'F', 'e', 'E', 'g', 'G', 'a', 'A' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        f64ToASCII(&temp_dest, value, precision);
                        is_float = true;
                    },
                    'c' => {
                        if (fields_info.len > arg_index) {
                            var value: u8 = 0;
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == u8) {
                                    value = @field(args, field.name);
                                    outChar(&temp_dest, value);
                                    arg_index += 1;
                                }
                            }
                        }
                    },
                    's' => {
                        if (fields_info.len > arg_index) {
                            var value: [*]const u8 = "";
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == [*:0]const u8) {
                                    value = @field(args, field.name);
                                    temp = @constCast(value);

                                    if (precision_specified) {
                                        temp_dest.size = 0;
                                        var scan: [*]const u8 = value;
                                        while (scan[0] != 0 and temp_dest.size < precision) : (scan += 1) {
                                            temp_dest.size += 1;
                                        }
                                    } else {
                                        temp_dest.size = stringLength(@ptrCast(value));
                                    }

                                    temp_dest.at = @constCast(value + temp_dest.size);
                                    arg_index += 1;
                                }
                            }
                        }
                    },
                    'p' => {
                        if (fields_info.len > arg_index) {
                            var value: usize = 0;
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == @TypeOf(value)) {
                                    value = @field(args, field.name);
                                    u64ToASCII(&temp_dest, @intCast(value), 16, lower_hex_chars);
                                    arg_index += 1;
                                }
                            }
                        }
                    },
                    'n' => {
                        if (fields_info.len > arg_index) {
                            var value: *i32 = undefined;
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == @TypeOf(value)) {
                                    value = @field(args, field.name);
                                    value.* = dest.at - &dest_init;
                                    arg_index += 1;
                                }
                            }
                        }
                    },
                    '%' => {
                        outChar(&dest, '%');
                    },
                    else => {
                        @panic("Unrecognized format specifier");
                    },
                }

                if ((temp_dest.at - temp) > 0) {
                    const prefix_length: i32 = @as(i32, @intCast(stringLength(@ptrCast(prefix))));
                    var use_precision: i32 = precision;
                    if (is_float or !precision_specified) {
                        use_precision = @intCast(temp_dest.at - temp);
                    }

                    var use_width: i32 = width;
                    const computed_width: i32 = use_precision + prefix_length;
                    if (use_width < computed_width) {
                        use_width = computed_width;
                    }

                    if (!left_justify) {
                        while (use_width > (use_precision + prefix_length)) {
                            outChar(&dest, if (pad_with_zeros) '0' else ' ');
                            use_width -= 1;
                        }
                    }

                    var pre: [*]const u8 = prefix;
                    while (pre[0] != 0) : (pre += 1) {
                        outChar(&dest, pre[0]);
                        use_width -= 1;
                    }

                    if (use_precision > use_width) {
                        use_precision = use_width;
                    }

                    while (use_precision > (temp_dest.at - temp)) {
                        outChar(&dest, '0');
                        use_precision -= 1;
                        use_width -= 1;
                    }

                    while (use_precision > 0 and temp_dest.at != temp) {
                        outChar(&dest, temp[0]);
                        temp += 1;
                        use_precision -= 1;
                        use_width -= 1;
                    }

                    if (pad_with_zeros) {
                        std.debug.assert(!left_justify);
                        left_justify = false;
                    }

                    if (left_justify) {
                        while (use_width > 0) {
                            outChar(&dest, ' ');
                            use_width -= 1;
                        }
                    }
                }

                if (at[0] != 0) {
                    at += 1;
                }
            } else {
                outChar(&dest, at[0]);
                at += 1;
            }
        }

        if (dest.size > 0) {
            dest.at[0] = 0;
        } else {
            dest.at -= 1;
            dest.at[0] = 0;
            dest.at += 1;
        }
    }

    return dest.at - dest_init;
}

test "stringsAreEqual" {
    try std.testing.expectEqual(true, stringsAreEqual("abc", "abc"));
    try std.testing.expectEqual(true, stringsAreEqual("", ""));

    try std.testing.expectEqual(false, stringsAreEqual("cba", "abc"));
    try std.testing.expectEqual(false, stringsAreEqual("abc", "abcd"));
    try std.testing.expectEqual(false, stringsAreEqual("abcd", "abc"));
}

// Platform.
pub const DebugReadFileResult = extern struct {
    contents: *anyopaque = undefined,
    content_size: u32 = 0,
};

pub const PlatformWorkQueuePtr = *anyopaque;
pub const PlatformWorkQueueCallback = *const fn (queue: PlatformWorkQueuePtr, data: *anyopaque) callconv(.c) void;

pub const WorkQueueEntry = extern struct {
    callback: PlatformWorkQueueCallback = undefined,
    data: *anyopaque = undefined,
};

pub const PlatformWorkQueue = extern struct {
    completion_goal: u32 = 0,
    completion_count: u32 = 0,

    next_entry_to_write: u32 = 0,
    next_entry_to_read: u32 = 0,
    semaphore_handle: ?*anyopaque = null,

    entries: [256]WorkQueueEntry = [1]WorkQueueEntry{WorkQueueEntry{}} ** 256,
};

pub const PlatformFileHandle = extern struct {
    no_errors: bool = false,
    platform: *anyopaque = undefined,

    pub fn isValid(self: *PlatformFileHandle) bool {
        _ = self;
        return false;
    }
};

pub const PlatformFileGroup = extern struct {
    file_count: u32 = 0,
    platform: *anyopaque = undefined,
};

pub const PlatformFileTypes = enum(u32) {
    AssetFile,
    SaveGameFile,
};

pub const PlatformMemoryBlockFlags = enum(u64) {
    NotRestored = 0x1,
    OverflowCheck = 0x2,
    UnderflowCheck = 0x4,
};

pub const PlatformMemoryBlock = extern struct {
    flags: u64 = 0,
    size: u64 = 0,
    base: [*]u8 = undefined,
    used: MemoryIndex = 0,
    arena_prev: ?*PlatformMemoryBlock = null,
};

pub const DebugExecutingProcess = extern struct {
    os_handle: u64 = 0,
};

pub const DebugExecutingProcessState = extern struct {
    started_successfully: bool = false,
    is_running: bool = false,
    return_code: u32 = 0,
};

pub const DebugPlatformMemoryStats = extern struct {
    block_count: MemoryIndex = 0,
    total_size: MemoryIndex = 0, // This doesn't include the header.
    total_used: MemoryIndex = 0,
};

const addQueueEntryType: type = fn (queue: *PlatformWorkQueue, callback: PlatformWorkQueueCallback, data: *anyopaque) callconv(.c) void;
const completeAllQueuedWorkType: type = fn (queue: *PlatformWorkQueue) callconv(.c) void;

const getAllFilesOfTypeBeginType: type = fn (file_type: PlatformFileTypes) callconv(.c) PlatformFileGroup;
const getAllFilesOfTypeEndType: type = fn (file_group: *PlatformFileGroup) callconv(.c) void;
const openNextFileType: type = fn (file_group: *PlatformFileGroup) callconv(.c) PlatformFileHandle;
const readDataFromFileType: type = fn (source: *PlatformFileHandle, offset: u64, size: u64, dest: *anyopaque) callconv(.c) void;
const noFileErrorsType: type = fn (file_handle: *PlatformFileHandle) callconv(.c) bool;
const fileErrorType: type = fn (file_handle: *PlatformFileHandle, message: [*:0]const u8) callconv(.c) void;

const allocateMemoryType: type = fn (size: MemoryIndex, flags: u64) callconv(.c) ?*PlatformMemoryBlock;
const deallocateMemoryType: type = fn (memory: ?*PlatformMemoryBlock) callconv(.c) void;

const debugFreeFileMemoryType = fn (memory: *anyopaque) callconv(.c) void;
const debugWriteEntireFileType = fn (file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) callconv(.c) bool;
const debugReadEntireFileType: type = fn (file_name: [*:0]const u8) callconv(.c) DebugReadFileResult;
const debugExecuteSystemCommandType: type = fn (path: [*:0]const u8, command: [*:0]const u8, command_line: [*:0]const u8) callconv(.c) DebugExecutingProcess;
const debugGetProcessStateType: type = fn (process: DebugExecutingProcess) callconv(.c) DebugExecutingProcessState;
const debugGetMemoryStatsType = fn () callconv(.c) DebugPlatformMemoryStats;

pub fn defaultNoFileErrors(file_handle: *PlatformFileHandle) callconv(.c) bool {
    return file_handle.no_errors;
}

pub const Platform = if (INTERNAL) extern struct {
    addQueueEntry: *const addQueueEntryType = undefined,
    completeAllQueuedWork: *const completeAllQueuedWorkType = undefined,

    getAllFilesOfTypeBegin: *const getAllFilesOfTypeBeginType = undefined,
    getAllFilesOfTypeEnd: *const getAllFilesOfTypeEndType = undefined,
    openNextFile: *const openNextFileType = undefined,
    readDataFromFile: *const readDataFromFileType = undefined,
    noFileErrors: *const noFileErrorsType = defaultNoFileErrors,
    fileError: *const fileErrorType = undefined,

    allocateMemory: *const allocateMemoryType = undefined,
    deallocateMemory: *const deallocateMemoryType = undefined,

    debugFreeFileMemory: *const debugFreeFileMemoryType = undefined,
    debugWriteEntireFile: *const debugWriteEntireFileType = undefined,
    debugReadEntireFile: *const debugReadEntireFileType = undefined,
    debugExecuteSystemCommand: *const debugExecuteSystemCommandType = undefined,
    debugGetProcessState: *const debugGetProcessStateType = undefined,
    debugGetMemoryStats: *const debugGetMemoryStatsType = undefined,
} else extern struct {
    addQueueEntry: *const addQueueEntryType = undefined,
    completeAllQueuedWork: *const completeAllQueuedWorkType = undefined,

    getAllFilesOfTypeBegin: *const getAllFilesOfTypeBeginType = undefined,
    getAllFilesOfTypeEnd: *const getAllFilesOfTypeEndType = undefined,
    openNextFile: *const openNextFileType = undefined,
    readDataFromFile: *const readDataFromFileType = undefined,
    noFileErrors: *const noFileErrorsType = defaultNoFileErrors,
    fileError: *const fileErrorType = undefined,

    allocateMemory: *const allocateMemoryType = undefined,
    deallocateMemory: *const deallocateMemoryType = undefined,
};

pub var platform: Platform = undefined;

// Data from platform.
pub fn updateAndRenderStub(_: Platform, _: *Memory, _: *GameInput, _: *RenderCommands) callconv(.c) void {
    return;
}

pub fn getSoundSamplesStub(_: *Memory, _: *SoundOutputBuffer) callconv(.c) void {
    return;
}

pub fn debugFrameEndStub(_: *Memory, _: GameInput, _: *RenderCommands) callconv(.c) void {
    return undefined;
}

pub var global_debug_table: *DebugTable = undefined;
pub var debug_global_memory: ?*Memory = null;
pub var debugFrameEnd: *const @TypeOf(debugFrameEndStub) = if (INTERNAL) @import("debug.zig").frameEnd else debugFrameEndStub;
pub const debug_color_table: [11]Color3 = .{
    Color3.new(1, 0, 0),
    Color3.new(0, 1, 0),
    Color3.new(0, 0, 1),
    Color3.new(1, 1, 0),
    Color3.new(0, 1, 1),
    Color3.new(1, 0, 1),
    Color3.new(1, 0.5, 0),
    Color3.new(1, 0, 0.5),
    Color3.new(0.5, 1, 0),
    Color3.new(0, 1, 0.5),
    Color3.new(0.5, 0, 1),
};

pub const LIGHT_DATA_WIDTH = 8192;
pub const LIGHT_LOOKUP_X: u32 = 8;
pub const LIGHT_LOOKUP_Y: u32 = 8;
pub const LIGHT_LOOKUP_Z: u32 = 8;
pub const MAX_LIGHT_POWER: f32 = 10;

pub const LightingTextures = extern struct {
    position_next: [LIGHT_DATA_WIDTH]LightingTexel,
    color: [LIGHT_DATA_WIDTH]u32,
    direction: [LIGHT_DATA_WIDTH]Vector4,
    lookup: [LIGHT_LOOKUP_Z][LIGHT_LOOKUP_Y][LIGHT_LOOKUP_X]u16,

    min_corner: Vector3,
    max_corner: Vector3,
    cell_dimension: Vector3,
    inverse_cell_dimension: Vector3,

    pub fn clearLookup(self: *LightingTextures) void {
        self.lookup =
            [1][LIGHT_LOOKUP_Y][LIGHT_LOOKUP_X]u16{
                [1][LIGHT_LOOKUP_X]u16{
                    [1]u16{0} ** LIGHT_LOOKUP_X,
                } ** LIGHT_LOOKUP_Y,
            } ** LIGHT_LOOKUP_Z;
    }
};

pub const LightingTexel = extern struct {
    position: Vector4,
    // next: f32,
};

pub const TexturedVertex = extern struct {
    position: Vector4,
    normal: Vector3,
    uv: Vector2,
    color: u32, // Packed RGBA in memory order (ABGR in little endian).
    emission: f32 = 0,

    // TODO: Doesn't need to be per-vertex - move this into its own per-primitive buffer.
    light_index: u16 = 0,
    light_count: u16 = 0,
};

pub const RenderSettings = extern struct {
    width: u32 = 0,
    height: u32 = 0,
    depth_peel_count_hint: u32 = 0,
    multisampling_hint: bool = false,
    pixelation_hint: bool = false,
    multisample_debug: bool = false,
    lighting_disabled: bool = false,

    pub fn equals(self: *RenderSettings, b: *RenderSettings) bool {
        const type_info = @typeInfo(@TypeOf(self.*));
        inline for (type_info.@"struct".fields) |struct_field| {
            if (@field(self, struct_field.name) != @field(b, struct_field.name)) {
                return false;
            }
        }
        return true;

        // return self.width == b.width and
        //     self.height == b.height and
        //     self.depth_peel_count_hint == b.depth_peel_count_hint and
        //     self.multisampling_hint == b.multisampling_hint and
        //     self.pixelation_hint == b.pixelation_hint;
    }
};

pub const RenderCommands = extern struct {
    settings: RenderSettings = .{},

    max_push_buffer_size: u32,
    push_buffer_base: [*]u8,
    push_buffer_data_at: [*]u8,

    max_vertex_count: u32,
    vertex_count: u32,
    vertex_array: [*]TexturedVertex,
    quad_bitmaps: [*]?*LoadedBitmap,
    white_bitmap: ?*LoadedBitmap,

    clear_color: Color, // This color is NOT in linear space, it is in sRGB space directly.

    pub fn default(
        max_push_buffer_size: u32,
        push_buffer: *anyopaque,
        width: u32,
        height: u32,
        max_vertex_count: u32,
        vertex_array: [*]TexturedVertex,
        bitmap_array: [*]?*LoadedBitmap,
        white_bitmap: *LoadedBitmap,
    ) RenderCommands {
        return RenderCommands{
            .settings = .{
                .width = width,
                .height = height,
                .depth_peel_count_hint = 4,
                .multisampling_hint = true,
                .pixelation_hint = false,
            },

            .max_push_buffer_size = max_push_buffer_size,
            .push_buffer_base = @ptrCast(push_buffer),
            .push_buffer_data_at = @ptrFromInt(@intFromPtr(push_buffer)),

            .max_vertex_count = max_vertex_count,
            .vertex_count = 0,
            .vertex_array = vertex_array,
            .quad_bitmaps = bitmap_array,
            .white_bitmap = white_bitmap,

            .clear_color = .black(),
        };
    }

    pub fn reset(self: *RenderCommands) void {
        self.push_buffer_data_at = self.push_buffer_base;
        self.vertex_count = 0;
    }
};

pub const OffscreenBuffer = extern struct {
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
};

pub const SoundOutputBuffer = extern struct {
    // IMPORTANT: Samples must be padded to a multiple of 4 samples.
    samples: [*]i16,
    samples_per_second: u32,
    sample_count: u32,
};

pub const MOUSE_BUTTON_COUNT = @typeInfo(GameInputMouseButton).@"enum".fields.len;
pub const GameInputMouseButton = enum(u8) {
    Left,
    Middle,
    Right,
    Extended0,
    Extended1,

    pub fn toInt(self: GameInputMouseButton) u32 {
        return @intFromEnum(self);
    }
};

pub const GameInput = extern struct {
    frame_delta_time: f32 = 0,

    controllers: [MAX_CONTROLLER_COUNT]ControllerInput = [1]ControllerInput{ControllerInput{}} ** MAX_CONTROLLER_COUNT,

    quit_requested: bool = false,

    // For debugging only.
    mouse_buttons: [MOUSE_BUTTON_COUNT]ControllerButtonState = [1]ControllerButtonState{ControllerButtonState{}} ** MOUSE_BUTTON_COUNT,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_z: f32 = 0,
    shift_down: bool = false,
    alt_down: bool = false,
    control_down: bool = false,
    f_key_pressed: [13]bool = [1]bool{false} ** 13, // Index 1 is F1, etc. Index 0 is not used.

    pub fn getController(self: *GameInput, controller_index: u32) *ControllerInput {
        std.debug.assert(controller_index < self.controllers.len);
        return &self.controllers[controller_index];
    }
};

pub const ControllerInput = extern struct {
    is_analog: bool = false,
    is_connected: bool = false,

    stick_average_x: f32 = 0,
    stick_average_y: f32 = 0,

    move_up: ControllerButtonState = ControllerButtonState{},
    move_down: ControllerButtonState = ControllerButtonState{},
    move_left: ControllerButtonState = ControllerButtonState{},
    move_right: ControllerButtonState = ControllerButtonState{},

    action_up: ControllerButtonState = ControllerButtonState{},
    action_down: ControllerButtonState = ControllerButtonState{},
    action_left: ControllerButtonState = ControllerButtonState{},
    action_right: ControllerButtonState = ControllerButtonState{},

    left_shoulder: ControllerButtonState = ControllerButtonState{},
    right_shoulder: ControllerButtonState = ControllerButtonState{},

    start_button: ControllerButtonState = ControllerButtonState{},
    back_button: ControllerButtonState = ControllerButtonState{},

    pub fn copyButtonStatesTo(self: *ControllerInput, target: *ControllerInput) void {
        target.move_up.ended_down = self.move_up.ended_down;
        target.move_down.ended_down = self.move_down.ended_down;
        target.move_left.ended_down = self.move_left.ended_down;
        target.move_right.ended_down = self.move_right.ended_down;

        target.action_up.ended_down = self.action_up.ended_down;
        target.action_down.ended_down = self.action_down.ended_down;
        target.action_left.ended_down = self.action_left.ended_down;
        target.action_right.ended_down = self.action_right.ended_down;

        target.left_shoulder.ended_down = self.left_shoulder.ended_down;
        target.right_shoulder.ended_down = self.right_shoulder.ended_down;

        target.start_button.ended_down = self.start_button.ended_down;
        target.back_button.ended_down = self.back_button.ended_down;
    }

    pub fn resetButtonTransitionCounts(self: *ControllerInput) void {
        self.move_up.half_transitions = 0;
        self.move_down.half_transitions = 0;
        self.move_left.half_transitions = 0;
        self.move_right.half_transitions = 0;

        self.action_up.half_transitions = 0;
        self.action_down.half_transitions = 0;
        self.action_left.half_transitions = 0;
        self.action_right.half_transitions = 0;

        self.left_shoulder.half_transitions = 0;
        self.right_shoulder.half_transitions = 0;

        self.start_button.half_transitions = 0;
        self.back_button.half_transitions = 0;
    }
};

pub const ControllerButtonState = extern struct {
    ended_down: bool = false,
    half_transitions: u8 = 0,

    pub fn wasPressed(self: ControllerButtonState) bool {
        return self.half_transitions > 1 or (self.half_transitions == 1 and self.ended_down);
    }

    pub fn isDown(self: ControllerButtonState) bool {
        return self.ended_down;
    }
};

// Game state.
pub const Memory = struct {
    game_state: ?*State = null,
    transient_state: ?*TransientState = null,

    debug_table: *DebugTable,
    debug_state: ?*debug.DebugState = null,

    high_priority_queue: *PlatformWorkQueue,
    low_priority_queue: *PlatformWorkQueue,
    texture_op_queue: PlatformTextureOpQueue = .{},

    executable_reloaded: bool = false,
};

pub const State = struct {
    total_arena: MemoryArena = undefined,
    audio_arena: MemoryArena = undefined,
    mode_arena: MemoryArena = undefined,

    controlled_heroes: [MAX_CONTROLLER_COUNT]ControlledHero = [1]ControlledHero{undefined} ** MAX_CONTROLLER_COUNT,

    current_mode: GameMode = undefined,
    mode: union {
        title_screen: *cutscene.GameModeTitleScreen,
        cutscene: *cutscene.GameModeCutscene,
        world: *world_mode.GameModeWorld,
    } = undefined,

    audio_state: audio.AudioState = undefined,
    music: *PlayingSound = undefined,

    test_diffuse: LoadedBitmap,
    test_normal: LoadedBitmap,

    pub fn setGameMode(self: *State, transient_state: *TransientState, game_mode: GameMode) void {
        var need_to_wait: bool = false;
        var task_index: u32 = 0;
        while (task_index < transient_state.tasks.len) : (task_index += 1) {
            need_to_wait = need_to_wait or transient_state.tasks[task_index].depends_on_game_mode;
        }

        if (need_to_wait) {
            platform.completeAllQueuedWork(transient_state.low_priority_queue);
        }

        self.mode_arena.clear();
        self.current_mode = game_mode;
    }
};

pub const GameMode = enum {
    None,
    TitleScreen,
    Cutscene,
    World,
};

pub const HeroBitmapIds = struct {
    head: ?BitmapId,
    torso: ?BitmapId,
    cape: ?BitmapId,
};

pub const TaskWithMemory = struct {
    being_used: bool,
    depends_on_game_mode: bool,
    arena: MemoryArena,

    memory_flush: TemporaryMemory,
};

pub const TransientState = struct {
    is_initialized: bool = false,
    arena: MemoryArena = undefined,

    high_priority_queue: *PlatformWorkQueue,
    low_priority_queue: *PlatformWorkQueue,
    tasks: [4]TaskWithMemory = [1]TaskWithMemory{undefined} ** 4,

    assets: *Assets,
    main_generation_id: u32,

    env_map_width: i32,
    env_map_height: i32,
    env_maps: [3]rendergroup.EnvironmentMap = [1]rendergroup.EnvironmentMap{undefined} ** 3,

    // TODO: Potentially remove this, it is just for asset locking.
    next_generation_id: u32,
    operation_lock: u32,
    in_flight_generation_count: u32,
    in_flight_generations: [16]u32,
};

pub const GroundBuffer = extern struct {
    position: world.WorldPosition = undefined,
    bitmap: LoadedBitmap,
};

pub const ControlledHero = struct {
    brain_id: BrainId = undefined,
    recenter_timer: f32 = 0,
    controller_direction: Vector2 = .zero(),
};

pub const LowEntityChunkReference = struct {
    tile_chunk: world.TileChunk,
    entity_index_in_chunk: u32,
};

pub const EntityResidence = enum(u8) {
    NonExistent,
    Low,
    High,
};
