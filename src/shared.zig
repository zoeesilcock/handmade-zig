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

// Build options.
pub const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;
pub const INTERNAL = @import("build_options").internal;

// Helper functions.
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
        const ticket = @atomicRmw(u64, &self.ticket, .Add, 1, .seq_cst);
        while (ticket != self.serving) {}
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

pub inline fn stringLength(string: [*:0]const u8) u32 {
    var count: u32 = 0;
    var scan = string;
    while (scan[0] != 0) : (scan += 1) {
        count += 1;
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
                    result = @intCast(@field(args, field.name));
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

                switch (at[0]) {
                    'd', 'i' => {
                        const value: i64 = readVarArgSignedInteger(args, &arg_index);
                        _ = value;
                    },
                    'u' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        _ = value;
                    },
                    'o' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        _ = value;
                    },
                    'x' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        _ = value;
                    },
                    'X' => {
                        const value: u64 = readVarArgUnsignedInteger(args, &arg_index);
                        _ = value;
                    },
                    'f' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'F' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'e' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'E' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'g' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'G' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'a' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'A' => {
                        const value: f64 = readVarArgFloat(args, &arg_index);
                        _ = value;
                    },
                    'c' => {
                        if (fields_info.len > arg_index) {
                            var value: u8 = 0;
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == u8) {
                                    value = @field(args, field.name);
                                }
                            }
                            arg_index += 1;
                        }
                    },
                    's' => {
                        if (fields_info.len > arg_index) {
                            var value: [*]const u8 = "";
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == [*:0]const u8) {
                                    value = @field(args, field.name);
                                }
                            }
                            while (value[0] != 0) : (value += 1) {
                                outChar(&dest, value[0]);
                            }
                            arg_index += 1;
                        }
                    },
                    'p' => {
                        if (fields_info.len > arg_index) {
                            var value: usize = 0;
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == @TypeOf(value)) {
                                    value = @field(args, field.name);
                                }
                            }
                            arg_index += 1;
                        }
                    },
                    'n' => {
                        if (fields_info.len > arg_index) {
                            var value: *i32 = undefined;
                            inline for (fields_info, 0..) |field, i| {
                                if (i == arg_index and field.type == @TypeOf(value)) {
                                    value = @field(args, field.name);
                                }
                            }
                            arg_index += 1;
                        }
                    },
                    '%' => {
                        outChar(&dest, '%');
                    },
                    else => {
                        @panic("Unrecognized format specifier");
                    },
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
pub const PlatformWorkQueueCallback = *const fn (queue: PlatformWorkQueuePtr, data: *anyopaque) callconv(.C) void;

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

pub const DebugExecutingProcess = extern struct {
    os_handle: u64 = 0,
};

pub const DebugExecutingProcessState = extern struct {
    started_successfully: bool = false,
    is_running: bool = false,
    return_code: u32 = 0,
};

const addQueueEntryType: type = fn (queue: *PlatformWorkQueue, callback: PlatformWorkQueueCallback, data: *anyopaque) callconv(.C) void;
const completeAllQueuedWorkType: type = fn (queue: *PlatformWorkQueue) callconv(.C) void;

const getAllFilesOfTypeBeginType: type = fn (file_type: PlatformFileTypes) callconv(.C) PlatformFileGroup;
const getAllFilesOfTypeEndType: type = fn (file_group: *PlatformFileGroup) callconv(.C) void;
const openNextFileType: type = fn (file_group: *PlatformFileGroup) callconv(.C) PlatformFileHandle;
const readDataFromFileType: type = fn (source: *PlatformFileHandle, offset: u64, size: u64, dest: *anyopaque) callconv(.C) void;
const noFileErrorsType: type = fn (file_handle: *PlatformFileHandle) callconv(.C) bool;
const fileErrorType: type = fn (file_handle: *PlatformFileHandle, message: [*:0]const u8) callconv(.C) void;

const allocateMemoryType: type = fn (size: MemoryIndex) callconv(.C) ?*anyopaque;
const deallocateMemoryType: type = fn (memory: ?*anyopaque) callconv(.C) void;

const debugFreeFileMemoryType = fn (memory: *anyopaque) callconv(.C) void;
const debugWriteEntireFileType = fn (file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) callconv(.C) bool;
const debugReadEntireFileType: type = fn (file_name: [*:0]const u8) callconv(.C) DebugReadFileResult;
const debugExecuteSystemCommandType: type = fn (path: [*:0]const u8, command: [*:0]const u8, command_line: [*:0]const u8) callconv(.C) DebugExecutingProcess;
const debugGetProcessStateType: type = fn (process: DebugExecutingProcess) callconv(.C) DebugExecutingProcessState;

pub fn defaultNoFileErrors(file_handle: *PlatformFileHandle) callconv(.C) bool {
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
pub fn updateAndRenderStub(_: Platform, _: *Memory, _: *GameInput, _: *RenderCommands) callconv(.C) void {
    return;
}

pub fn getSoundSamplesStub(_: *Memory, _: *SoundOutputBuffer) callconv(.C) void {
    return;
}

pub fn debugFrameEndStub(_: *Memory, _: GameInput, _: *RenderCommands) callconv(.C) void {
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

pub const RenderCommands = extern struct {
    width: u32 = 0,
    height: u32 = 0,

    max_push_buffer_size: u32,
    sort_entry_count: u32,
    push_buffer_base: [*]u8,
    push_buffer_data_at: [*]u8,

    clear_color: Color,

    last_used_manual_sort_key: u32 = 0,
    max_render_target_index: u32 = 0,

    clip_rect_count: u32 = 0,
    first_clip_rect: ?*rendergroup.RenderEntryClipRect = null,
    last_clip_rect: ?*rendergroup.RenderEntryClipRect = null,
};

pub const GameRenderPrep = extern struct {
    clip_rects: [*]rendergroup.RenderEntryClipRect = undefined,
    sorted_index_count: u32 = 0,
    sorted_indices: [*]u32 = undefined,
};

pub fn initializeRenderCommands(
    max_push_buffer_size: u32,
    push_buffer: *anyopaque,
    width: u32,
    height: u32,
) RenderCommands {
    return RenderCommands{
        .width = width,
        .height = height,

        .max_push_buffer_size = max_push_buffer_size,
        .sort_entry_count = 0,
        .push_buffer_base = @ptrCast(push_buffer),
        .push_buffer_data_at = @ptrFromInt(@intFromPtr(push_buffer) + max_push_buffer_size),

        .clear_color = .black(),
    };
}

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
    permanent_storage_size: u64,
    permanent_storage: ?[*]u8,

    transient_storage_size: u64,
    transient_storage: ?[*]u8,

    debug_storage_size: u64,
    debug_storage: ?[*]u8,
    debug_table: *DebugTable,

    high_priority_queue: *PlatformWorkQueue,
    low_priority_queue: *PlatformWorkQueue,
    texture_op_queue: PlatformTextureOpQueue = .{},

    executable_reloaded: bool = false,
};

pub const State = struct {
    is_initialized: bool = false,
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
