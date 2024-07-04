// Constants.
pub const PI32: f32 = 3.1415926535897932384626433;
pub const TAU32: f32 = PI32 * 2.0;
pub const MIDDLE_C: u32 = 261;
pub const TREBLE_C: u32 = 523;
pub const MAX_CONTROLLER_COUNT: u8 = 5;

const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const world = @import("world.zig");
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
    world: *world.World = undefined,

    camera_following_entity_index: u32 = 0,
    camera_position: world.WorldPosition,

    player_index_for_controller: [MAX_CONTROLLER_COUNT]u32 = [1]u32{undefined} ** MAX_CONTROLLER_COUNT,

    low_entity_count: u32 = 0,
    low_entities: [100000]LowEntity = [1]LowEntity{undefined} ** 100000,

    high_entity_count: u32 = 0,
    high_entities: [256]HighEntity = [1]HighEntity{undefined} ** 256,

    backdrop: LoadedBitmap,
    hero_bitmaps: [4]HeroBitmaps,
    tree: LoadedBitmap,
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

pub const EntityType = enum(u8) {
    Null,
    Hero,
    Wall,
    Familiar,
    Monster,
};

pub const Entity = struct {
    low_index: u32,
    low: *LowEntity,

    high: ?*HighEntity,
};

pub const LowEntity = struct {
    type: EntityType = .Null,

    width: f32 = 0,
    height: f32 = 0,
    position: world.WorldPosition = undefined,

    collides: bool = false,
    abs_tile_z_delta: i32 = 0,

    high_entity_index: u32 = 0,
};

pub const HighEntity = struct {
    low_entity_index: u32 = 0,

    position: math.Vector2 = math.Vector2{},
    velocity: math.Vector2 = math.Vector2{},
    chunk_z: i32 = 0,
    facing_direction: u32 = undefined,

    z: f32 = 0,
    z_velocity: f32 = 0,

    head_bob_time: f32 = 0,
};

pub const EntityVisiblePieceGroup = struct {
    piece_count: u32 = 0,
    pieces: [8]EntityVisiblePiece = [1]EntityVisiblePiece{undefined} ** 8,

    pub fn pushPiece(
        self: *EntityVisiblePieceGroup,
        bitmap: *LoadedBitmap,
        offset: math.Vector2,
        offset_z: f32,
        alignment: math.Vector2,
        alpha: f32,
    ) void {
        std.debug.assert(self.piece_count < self.pieces.len);

        var piece = &self.pieces[self.piece_count];
        self.piece_count += 1;

        piece.bitmap = bitmap;
        piece.offset = offset.subtract(alignment);
        piece.offset_z = offset_z;
        piece.alpha = alpha;
    }
};

pub const EntityVisiblePiece = struct {
    bitmap: *LoadedBitmap,
    offset: math.Vector2,
    offset_z: f32,
    alpha: f32,
};

pub const HeroBitmaps = struct {
    alignment: math.Vector2,

    head: LoadedBitmap,
    torso: LoadedBitmap,
    cape: LoadedBitmap,
    shadow: LoadedBitmap,
};

// Data structures..
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    pub fn to_int(self: Color) u32 {
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
