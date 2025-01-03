// Constants.
pub const PI32: f32 = 3.14159265359;
pub const TAU32: f32 = 6.28318530717958647692;
pub const MIDDLE_C: u32 = 261;
pub const TREBLE_C: u32 = 523;
pub const MAX_CONTROLLER_COUNT: u8 = 5;
pub const HIT_POINT_SUB_COUNT = 4;
pub const BITMAP_BYTES_PER_PIXEL = 4;
pub const DEFAULT_MEMORY_ALIGNMENT = 4;

pub const intrinsics = @import("intrinsics.zig");
pub const math = @import("math.zig");
const world = @import("world.zig");
const sim = @import("sim.zig");
const render = @import("render.zig");
const file_formats = @import("file_formats");
const asset = @import("asset.zig");
const audio = @import("audio.zig");
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
const LoadedBitmap = asset.LoadedBitmap;
const LoadedSound = asset.LoadedSound;
const Assets = asset.Assets;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const FontId = file_formats.FontId;
const PlayingSound = audio.PlayingSound;
const DebugTable = debug_interface.DebugTable;

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

pub inline fn stringsAreEqual(a: []const u8, b: []const u8) bool {
    var result: bool = true;

    if (a.len != b.len) {
        result = false;
    } else {
        for (a, 0..) |a_char, i| {
            if (a_char != b[i]) {
                result = false;
                break;
            }
        }
    }

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

test "stringsAreEqual" {
    try std.testing.expectEqual(true, stringsAreEqual("abc", "abc"));
    try std.testing.expectEqual(true, stringsAreEqual("", ""));

    try std.testing.expectEqual(false, stringsAreEqual("cba", "abc"));
    try std.testing.expectEqual(false, stringsAreEqual("abc", "abcd"));
    try std.testing.expectEqual(false, stringsAreEqual("abcd", "abc"));
}

pub fn introspect(input: []const u8) void {
    _ = input;
}

// Platform.
pub const DebugReadFileResult = extern struct {
    contents: *anyopaque = undefined,
    content_size: u32 = 0,
};

pub const PlatformWorkQueueCallback = *const fn (queue: *PlatformWorkQueue, data: *anyopaque) callconv(.C) void;

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
pub fn updateAndRenderStub(_: Platform, _: *Memory, _: GameInput, _: *OffscreenBuffer) callconv(.C) void {
    return;
}

pub fn getSoundSamplesStub(_: *Memory, _: *SoundOutputBuffer) callconv(.C) void {
    return;
}

pub fn debugFrameEndStub(_: *Memory, _: GameInput, _: *OffscreenBuffer) callconv(.C) *DebugTable {
    return undefined;
}

pub var global_debug_table: *DebugTable = if (INTERNAL) &@import("debug.zig").global_debug_table else undefined;
pub var debug_global_memory: ?*Memory = null;
pub var debugFrameEnd: *const @TypeOf(debugFrameEndStub) = if (INTERNAL) @import("debug.zig").frameEnd else debugFrameEndStub;

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

pub const MOUSE_BUTTON_COUNT = @typeInfo(GameInputMouseButton).Enum.fields.len;
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

    // For debugging only.
    mouse_buttons: [MOUSE_BUTTON_COUNT]ControllerButtonState = [1]ControllerButtonState{ControllerButtonState{}} ** MOUSE_BUTTON_COUNT,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_z: f32 = 0,
    shift_down: bool = false,
    alt_down: bool = false,
    control_down: bool = false,
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
};

pub const ControllerButtonState = extern struct {
    ended_down: bool = false,
    half_transitions: u8 = 0,

    pub fn wasPressed(self: ControllerButtonState) bool {
        return self.half_transitions > 1 or (self.half_transitions == 1 and self.ended_down);
    }
};

// Memory.
pub const MemoryIndex = usize;

pub const Memory = GameMemory();
fn GameMemory() type {
    return extern struct {
        permanent_storage_size: u64,
        permanent_storage: ?[*]void,

        transient_storage_size: u64,
        transient_storage: ?[*]void,

        debug_storage_size: u64,
        debug_storage: ?[*]void,

        high_priority_queue: *PlatformWorkQueue,
        low_priority_queue: *PlatformWorkQueue,

        executable_reloaded: bool = false,

        const Self = @This();
    };
}

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

    fn getAlignmentOffset(self: *MemoryArena, alignment: MemoryIndex) MemoryIndex {
        var alignment_offset: MemoryIndex = 0;
        const result_pointer: MemoryIndex = @intFromPtr(self.base + self.used);
        const alignment_mask: MemoryIndex = alignment - 1;

        if (result_pointer & alignment_mask != 0) {
            alignment_offset = alignment - (result_pointer & alignment_mask);
        }

        return alignment_offset;
    }

    pub fn getRemainingSize(self: *MemoryArena, alignent: ?MemoryIndex) MemoryIndex {
        return self.size - (self.used + self.getAlignmentOffset(alignent orelse DEFAULT_MEMORY_ALIGNMENT));
    }

    pub fn makeSubArena(self: *MemoryArena, arena: *MemoryArena, size: MemoryIndex, alignment: ?MemoryIndex) void {
        arena.size = size;
        arena.base = self.pushSize(size, alignment orelse 16);
        arena.used = 0;
        arena.temp_count = 0;
    }

    pub fn getEffectiveSizeFor(self: *MemoryArena, size: MemoryIndex, alignment: MemoryIndex) MemoryIndex {
        const alignment_offset = self.getAlignmentOffset(alignment);
        const aligned_size = size + alignment_offset;
        return aligned_size;
    }

    pub fn hasRoomFor(self: *MemoryArena, size: MemoryIndex, alignment: ?MemoryIndex) bool {
        const effective_size = self.getEffectiveSizeFor(size, alignment orelse DEFAULT_MEMORY_ALIGNMENT);
        return (self.used + effective_size) <= self.size;
    }

    pub fn pushSize(self: *MemoryArena, size: MemoryIndex, alignment: ?MemoryIndex) [*]u8 {
        const aligned_size = self.getEffectiveSizeFor(size, alignment orelse DEFAULT_MEMORY_ALIGNMENT);

        std.debug.assert((self.used + aligned_size) <= self.size);

        const alignment_offset = self.getAlignmentOffset(alignment orelse DEFAULT_MEMORY_ALIGNMENT);
        const result: [*]u8 = @ptrCast(self.base + self.used + alignment_offset);
        self.used += aligned_size;

        return result;
    }

    pub fn pushStruct(self: *MemoryArena, comptime T: type) *T {
        return @as(*T, @ptrCast(@alignCast(pushSize(self, @sizeOf(T), @alignOf(T)))));
    }

    pub fn pushArray(self: *MemoryArena, count: MemoryIndex, comptime T: type) [*]T {
        return @as([*]T, @ptrCast(@alignCast(pushSize(self, @sizeOf(T) * count, @alignOf(T)))));
    }

    pub fn pushArrayAligned(self: *MemoryArena, count: MemoryIndex, comptime T: type, alignment: MemoryIndex) [*]T {
        return @as([*]T, @ptrCast(@alignCast(pushSize(self, @sizeOf(T) * count, alignment))));
    }

    pub fn pushString(self: *MemoryArena, source: [*:0]const u8) [*:0]const u8 {
        var size: u32 = 0;

        var char_index: u32 = 0;
        while (source[char_index] != 0) : (char_index += 1) {
            size += 1;
        }

        // Include the sentinel.
        size += 1;

        var dest = self.pushSize(size, null);

        char_index = 0;
        while (char_index < size) : (char_index += 1) {
            dest[char_index] = source[char_index];
        }

        return @ptrCast(dest);
    }

    pub fn pushCopy(self: *MemoryArena, size: MemoryIndex, source: *void) *void {
        return copy(size, source, @ptrCast(self.pushSize(size, null)));
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

pub fn zeroArray(count: u32, ptr: *anyopaque) void {
    zeroSize(@sizeOf(ptr) * count, ptr);
}

pub fn copy(size: MemoryIndex, source_init: *void, dest_init: *void) *void {
    var source: [*]u8 = @ptrCast(source_init);
    var dest: [*]u8 = @ptrCast(dest_init);

    var index: MemoryIndex = size;
    while (index > 0) : (index -= 1) {
        dest[0] = source[0];

        source += 1;
        dest += 1;
    }

    return dest_init;
}

// Game state.
pub const State = struct {
    is_initialized: bool = false,
    world_arena: MemoryArena = undefined,
    meta_arena: MemoryArena = undefined,
    world: *world.World = undefined,

    typical_floor_height: f32 = 0,

    camera_following_entity_index: u32 = 0,
    camera_position: world.WorldPosition,

    controlled_heroes: [MAX_CONTROLLER_COUNT]ControlledHero = [1]ControlledHero{undefined} ** MAX_CONTROLLER_COUNT,

    low_entity_count: u32 = 0,
    low_entities: [90000]LowEntity = [1]LowEntity{undefined} ** 90000,

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

    time: f32 = 0,

    test_diffuse: LoadedBitmap,
    test_normal: LoadedBitmap,

    t_sine: f32 = 0,

    audio_state: audio.AudioState = undefined,
    music: *PlayingSound = undefined,

    effects_entropy: random.Series,

    next_particle: u32 = 0,
    particles: [256]Particle = [1]Particle{Particle{}} ** 256,
    particle_cels: [PARTICLE_CEL_DIM][PARTICLE_CEL_DIM]ParticleCel = undefined,
};

pub const PARTICLE_CEL_DIM = 32;

pub const HeroBitmapIds = struct {
    head: ?BitmapId,
    torso: ?BitmapId,
    cape: ?BitmapId,
};

pub const ParticleCel = struct {
    density: f32 = 0,
    velocity_times_density: Vector3 = Vector3.zero(),
};

pub const Particle = struct {
    position: Vector3 = Vector3.zero(),
    velocity: Vector3 = Vector3.zero(),
    acceleration: Vector3 = Vector3.zero(),
    color: Color = Color.white(),
    color_velocity: Color = Color.zero(),
    bitmap_id: BitmapId = undefined,
};

pub const TaskWithMemory = struct {
    being_used: bool,
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

    ground_buffer_count: u32 = 0,
    ground_buffers: [*]GroundBuffer = undefined,

    env_map_width: i32,
    env_map_height: i32,
    env_maps: [3]render.EnvironmentMap = [1]render.EnvironmentMap{undefined} ** 3,
};

pub const GroundBuffer = extern struct {
    position: world.WorldPosition = undefined,
    bitmap: LoadedBitmap,
};

pub const PairwiseCollisionRuleFlag = enum(u8) {
    CanCollide = 0x1,
    Temporary = 0x2a,
};

pub const PairwiseCollisionRule = extern struct {
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
