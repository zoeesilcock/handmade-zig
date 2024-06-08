pub const PI32: f32 = 3.1415926535897932384626433;
pub const TAU32: f32 = PI32 * 2.0;
pub const MIDDLE_C: u32 = 261;
pub const TREBLE_C: u32 = 523;

const std = @import("std");

// Build options.
pub const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;

pub const MAX_CONTROLLER_COUNT: u8 = 5;

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

pub inline fn safeTruncateI64(value: i64) u32 {
    std.debug.assert(value <= 0xFFFFFFFF);
    return @as(u32, @intCast(value));
}

pub const Platform = extern struct {
    debugFreeFileMemory: *const fn (memory: *anyopaque) callconv(.C) void = undefined,
    debugWriteEntireFile: *const fn (file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) callconv(.C) bool = undefined,
    debugReadEntireFile: *const fn (file_name: [*:0]const u8) callconv(.C) DebugReadFileResult = undefined,
};

pub const DebugReadFileResult = extern struct {
    contents: *anyopaque = undefined,
    content_size: u32 = 0,
};

pub const OffscreenBuffer = extern struct {
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
    bytes_per_pixel: i32 = 0,
};

pub const SoundOutputBuffer = extern struct {
    samples: [*]i16,
    samples_per_second: u32,
    sample_count: u32,
};

pub const ControllerInputs = extern struct {
    controllers: [MAX_CONTROLLER_COUNT]ControllerInput = [1]ControllerInput{undefined} ** MAX_CONTROLLER_COUNT,
};

pub const ControllerButtonState = extern struct {
    ended_down: bool = false,
    half_transitions: u8 = 0,
};

pub const ControllerInput = extern struct {
    is_analog: bool = false,
    is_connected: bool = false,

    stick_average_x: f32 = 0,
    stick_average_y: f32 = 0,

    move_up: ControllerButtonState,
    move_down: ControllerButtonState,
    move_left: ControllerButtonState,
    move_right: ControllerButtonState,

    action_up: ControllerButtonState,
    action_down: ControllerButtonState,
    action_left: ControllerButtonState,
    action_right: ControllerButtonState,

    left_shoulder: ControllerButtonState,
    right_shoulder: ControllerButtonState,

    start_button: ControllerButtonState,
    back_button: ControllerButtonState,
};

pub const Memory = extern struct {
    is_initialized: bool,
    permanent_storage_size: u64,
    permanent_storage: *anyopaque,
    transient_storage_size: u64,
    transient_storage: *anyopaque,
};

pub const State = struct {
    x_offset: i32 = 0,
    y_offset: i32 = 0,
    t_sine: f32 = 0.0,
    tone_hz: u32 = MIDDLE_C,
};

pub fn updateAndRenderStub(_: Platform, _: *Memory, _: ControllerInputs, _: *OffscreenBuffer) callconv(.C) void {
    return;
}
pub fn getSoundSamplesStub(_: *Memory, _: *SoundOutputBuffer) callconv(.C) void {
    return;
}
