// Constants.
pub const PI32: f32 = 3.1415926535897932384626433;
pub const TAU32: f32 = PI32 * 2.0;
pub const MIDDLE_C: u32 = 261;
pub const TREBLE_C: u32 = 523;
pub const MAX_CONTROLLER_COUNT: u8 = 5;

const intrinsics = @import("intrinsics.zig");
const tile = @import("tile.zig");
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

// Memory.
pub const MemoryIndex = usize;

pub const Memory = extern struct {
    is_initialized: bool,
    permanent_storage_size: u64,
    permanent_storage: ?*anyopaque,
    transient_storage_size: u64,
    transient_storage: ?*anyopaque,
};

pub const MemoryArena = struct {
    size: MemoryIndex,
    base: [*]u8,
    used: MemoryIndex,
};

pub fn initializeArena(arena: *MemoryArena, size: MemoryIndex, base: [*]u8) void {
    arena.size = size;
    arena.base = base;
    arena.used = 0;
}

fn pushSize(arena: *MemoryArena, size: MemoryIndex) [*]u8 {
    std.debug.assert((arena.used + size) <= arena.size);

    const result = arena.base + arena.used;
    arena.used += size;
    return result;
}

pub fn pushStruct(arena: *MemoryArena, comptime T: type) *T {
    const size: MemoryIndex = @sizeOf(T);
    return @as(*T, @ptrCast(@alignCast(pushSize(arena, size))));
}

pub fn pushArray(arena: *MemoryArena, count: MemoryIndex, comptime T: type) [*]T {
    const size: MemoryIndex = @sizeOf(T) * count;
    return @as([*]T, @ptrCast(@alignCast(pushSize(arena, size))));
}

// Game state.
pub const State = struct {
    world_arena: MemoryArena = undefined,
    world: *World = undefined,

    camera_position: tile.TileMapPosition,

    player_position: tile.TileMapPosition,
    player_facing_direction: u32,

    backdrop: LoadedBitmap,
    hero_bitmaps: [4]HeroBitmaps,
};

pub const World = struct {
    tile_map: *tile.TileMap,
};

pub const HeroBitmaps = struct {
    align_x: i32,
    align_y: i32,

    head: LoadedBitmap,
    torso: LoadedBitmap,
    cape: LoadedBitmap,
};

// Data structures..
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    pub fn toInt(self: Color) u32 {
        return ((intrinsics.roundReal32ToUInt32(self.r * 255.0) << 16) |
            (intrinsics.roundReal32ToUInt32(self.g * 255.0) << 8) |
            (intrinsics.roundReal32ToUInt32(self.b * 255.0) << 0));
    }
};

pub const LoadedBitmap = struct {
    width: i32 = 0,
    height: i32 = 0,
    data: extern union {
        per_pixel_channel: [*]u8,
        per_pixel: [*]u32,
    },
};

pub const BitmapHeader = packed struct {
    file_type: u16,
    file_size: u32,
    reserved1: u16,
    reserved2: u16,
    bitmap_offset: u32,
    size: u32,
    width: i32,
    height: i32,
    planes: u16,
    bits_per_pxel: u16,
    compression: u32,
    size_of_bitmap: u32,
    horz_resolution: i32,
    vert_resolution: i32,
    colors_used: u32,
    colors_important: u32,
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
};
