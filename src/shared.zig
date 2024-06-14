// Constants.
pub const PI32: f32 = 3.1415926535897932384626433;
pub const TAU32: f32 = PI32 * 2.0;
pub const MIDDLE_C: u32 = 261;
pub const TREBLE_C: u32 = 523;
pub const MAX_CONTROLLER_COUNT: u8 = 5;

const std = @import("std");

// Build options.
pub const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;

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

pub inline fn safeTruncateI64(value: i64) u32 {
    std.debug.assert(value <= 0xFFFFFFFF);
    return @as(u32, @intCast(value));
}

pub inline fn roundReal32ToInt32(value: f32) i32 {
    return @intFromFloat(@round(value));
}

pub inline fn roundReal32ToUInt32(value: f32) u32 {
    return @intFromFloat(@round(value));
}

pub inline fn floorReal32ToInt32(value: f32) i32 {
    return @intFromFloat(@floor(value));
}

pub inline fn floorReal32ToUInt32(value: f32) u32 {
    return @intFromFloat(@floor(value));
}

// Platform.
pub const Platform = extern struct {
    debugFreeFileMemory: *const fn (thread: *ThreadContext, memory: *anyopaque) callconv(.C) void = undefined,
    debugWriteEntireFile: *const fn (thread: *ThreadContext, file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) callconv(.C) bool = undefined,
    debugReadEntireFile: *const fn (thread: *ThreadContext, file_name: [*:0]const u8) callconv(.C) DebugReadFileResult = undefined,
};

pub const DebugReadFileResult = extern struct {
    contents: *anyopaque = undefined,
    content_size: u32 = 0,
};

// Data from platform.
pub fn updateAndRenderStub(_: *ThreadContext, _: Platform, _: *Memory, _: GameInput, _: *OffscreenBuffer) callconv(.C) void {
    return;
}
pub fn getSoundSamplesStub(_: *ThreadContext, _: *Memory, _: *SoundOutputBuffer) callconv(.C) void {
    return;
}

pub const ThreadContext = extern struct {
    placeholder: i32 = 0,
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

pub const GameInput = extern struct {
    mouse_buttons: [5]ControllerButtonState = [1]ControllerButtonState{ControllerButtonState{}} ** 5,
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,

    frame_delta_time: f32 = 0,

    controllers: [MAX_CONTROLLER_COUNT]ControllerInput = [1]ControllerInput{undefined} ** MAX_CONTROLLER_COUNT,
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

pub const ControllerButtonState = extern struct {
    ended_down: bool = false,
    half_transitions: u8 = 0,
};

pub const Memory = extern struct {
    is_initialized: bool,
    permanent_storage_size: u64,
    permanent_storage: *anyopaque,
    transient_storage_size: u64,
    transient_storage: *anyopaque,
};

// Game state.
pub const State = struct {
    player_x: f32,
    player_y: f32,
    player_tile_map_x: i32,
    player_tile_map_y: i32,
};

pub const World = struct {
    tile_map_count_x: i32,
    tile_map_count_y: i32,
    upper_left_x: f32,
    upper_left_y: f32,
    tile_width: f32,
    tile_height: f32,
    tile_count_x: i32,
    tile_count_y: i32,

    tile_maps: [*] TileMap,
};

pub const CanonicalPosition = struct {
    tile_map_x: i32,
    tile_map_y: i32,
    tile_x: i32,
    tile_y: i32,
    x: f32,
    y: f32,
};

pub const RawPosition = struct {
    tile_map_x: i32,
    tile_map_y: i32,
    x: f32,
    y: f32,
};

pub const TileMap = struct {
    tiles: [*]const u32,
};

// Data structures..
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    pub fn toInt(self: Color) u32 {
        return (
            (roundReal32ToUInt32(self.r * 255.0) << 16) |
            (roundReal32ToUInt32(self.g * 255.0) << 8) |
            (roundReal32ToUInt32(self.b * 255.0) << 0)
        );
    }
};
