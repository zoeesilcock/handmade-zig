// Constants.
pub const PI32: f32 = 3.1415926535897932384626433;
pub const TAU32: f32 = PI32 * 2.0;
pub const MIDDLE_C: u32 = 261;
pub const TREBLE_C: u32 = 523;
pub const MAX_CONTROLLER_COUNT: u8 = 5;
pub const HIT_POINT_SUB_COUNT = 4;
pub const BITMAP_BYTES_PER_PIXEL = 4;

const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const world = @import("world.zig");
const sim = @import("sim.zig");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;

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

    executable_reloaded: bool = false,
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
    permanent_storage: ?[*]void,
    transient_storage_size: u64,
    transient_storage: ?[*]void,
};

pub const TemporaryMemory = struct {
    used: MemoryIndex,
};

pub const MemoryArena = struct {
    size: MemoryIndex,
    base: [*]u8,
    used: MemoryIndex,
    temp_count: i32,

    pub fn initialize(self: *MemoryArena, size: MemoryIndex, base: [*]void) void {
        self.size = size;
        self.base = @ptrCast(base);
        self.used = 0;
        self.temp_count = 0;
    }

    pub fn pushSize(self: *MemoryArena, comptime alignment: usize, size: MemoryIndex) [*]u8 {
        const base = @intFromPtr(self.base + self.used);
        const aligned_base = std.mem.alignForward(usize, base, alignment);
        const alignment_offset = aligned_base - base;
        const aligned_size = size + alignment_offset;

        std.debug.assert((self.used + aligned_size) <= self.size);

        const result: [*]align(alignment) u8 = @ptrFromInt(aligned_base);
        self.used += aligned_size;

        return result;
    }

    pub fn pushStruct(self: *MemoryArena, comptime T: type) *T {
        const size: MemoryIndex = @sizeOf(T);
        return @as(*T, @ptrCast(@alignCast(pushSize(self, @alignOf(T), size))));
    }

    pub fn pushArray(self: *MemoryArena, count: MemoryIndex, comptime T: type) [*]T {
        const size: MemoryIndex = @sizeOf(T) * count;
        return @as([*]T, @ptrCast(@alignCast(pushSize(self, @alignOf(T), size))));
    }

    pub fn beginTemporaryMemory(self: *MemoryArena) TemporaryMemory {
        const result = TemporaryMemory{
            .used = self.used,
        };

        self.temp_count += 1;

        return result;
    }

    pub fn endTemporaryMemory(self: *MemoryArena, temp_memory: TemporaryMemory) void {
        std.debug.assert(self.used >= temp_memory.used);

        self.used = temp_memory.used;

        std.debug.assert(self.temp_count > 0);
        self.temp_count -= 1;
    }

    pub fn checkArena(self: *MemoryArena) void {
        std.debug.assert(self.temp_count == 0);
    }
};

pub fn zeroSize(size: MemoryIndex, ptr: [*]void) void {
    var byte: [*]u8 = @ptrCast(ptr);
    var index = size;
    while (index > 0) : (index -= 1) {
        byte[0] = 0;
        byte += 1;
    }
}

pub fn zeroStruct(comptime T: type, ptr: *T) void {
    zeroSize(@sizeOf(T), @ptrCast(ptr));
}

// Game state.
pub const State = struct {
    world_arena: MemoryArena = undefined,
    world: *world.World = undefined,

    meters_to_pixels: f32 = 0,
    pixels_to_meters: f32 = 0,
    typical_floor_height: f32 = 0,

    camera_following_entity_index: u32 = 0,
    camera_position: world.WorldPosition,

    controlled_heroes: [MAX_CONTROLLER_COUNT]ControlledHero = [1]ControlledHero{undefined} ** MAX_CONTROLLER_COUNT,

    low_entity_count: u32 = 0,
    low_entities: [90000]LowEntity = [1]LowEntity{undefined} ** 90000,

    backdrop: LoadedBitmap,
    hero_bitmaps: [4]HeroBitmaps,
    tree: LoadedBitmap,
    sword: LoadedBitmap,
    stairwell: LoadedBitmap,
    grass: [2]LoadedBitmap,
    stone: [4]LoadedBitmap,
    tuft: [3]LoadedBitmap,

    collision_rule_hash: [256]?*PairwiseCollisionRule = [1]?*PairwiseCollisionRule{null} ** 256,
    first_free_collision_rule: ?*PairwiseCollisionRule = null,

    null_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    standard_room_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    wall_collision: *sim.SimEntityCollisionVolumeGroup = undefined,
    stair_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
    player_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
    sword_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
    familiar_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
    monster_collsion: *sim.SimEntityCollisionVolumeGroup = undefined,
};

pub const TransientState = struct {
    is_initialized: bool = false,
    arena: MemoryArena = undefined,
    ground_buffer_count: u32 = 0,
    ground_buffers: [*]GroundBuffer = undefined,
};

pub const GroundBuffer = struct {
    position: world.WorldPosition = undefined,
    bitmap: LoadedBitmap,
};

pub const PairwiseCollisionRuleFlag = enum(u8) {
    CanCollide = 0x1,
    Temporary = 0x2a,
};

pub const PairwiseCollisionRule = struct {
    can_collide: bool,
    storage_index_a: u32,
    storage_index_b: u32,

    next_in_hash: ?*PairwiseCollisionRule,
};

pub const ControlledHero = struct {
    entity_index: u32 = 0,
    movement_direction: Vector2 = Vector2.zero(),
    vertical_direction: f32 = 0,
    sword_direction: Vector2 = Vector2.zero(),
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

pub const LowEntity = struct {
    sim: sim.SimEntity,
    position: world.WorldPosition = undefined,
};

pub const AddLowEntityResult = struct {
    low: *LowEntity,
    low_index: u32,
};

pub const HeroBitmaps = struct {
    alignment: Vector2,

    head: LoadedBitmap,
    torso: LoadedBitmap,
    cape: LoadedBitmap,
    shadow: LoadedBitmap,
};

// Data structures.
pub const LoadedBitmap = struct {
    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
    memory: ?[*]void,
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

pub fn colorToInt(color: Color) u32 {
    return ((intrinsics.roundReal32ToUInt32(color.r() * 255.0) << 16) |
        (intrinsics.roundReal32ToUInt32(color.g() * 255.0) << 8) |
        (intrinsics.roundReal32ToUInt32(color.b() * 255.0) << 0));
}
