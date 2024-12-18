const shared = @import("shared.zig");
const math = @import("math.zig");
const asset = @import("asset.zig");
const debug = @import("debug.zig");
const file_formats = @import("file_formats");
const std = @import("std");

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

pub const hit = debug.hit;
pub const highlighted = debug.highlighted;
pub const requested = debug.requested;

// Build options.
pub const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;
pub const INTERNAL = @import("build_options").internal;

pub const MAX_DEBUG_THREAD_COUNT = 256;
pub const MAX_DEBUG_REGIONS_PER_FRAME = 4096;
pub const MAX_DEBUG_EVENT_ARRAY_COUNT = 8;
pub const MAX_DEBUG_EVENT_COUNT = 16 * 65536;
pub const DEBUG_UI_ENABLED = true;

pub const DebugCycleCounters = enum(u16) {
    TotalPlatformLoop,
    ExecutableRefresh,
    InputProcessing,
    GameUpdate,
    AudioUpdate,
    FrameRateWait,
    FrameDisplay,
    DebugCollation,

    GameUpdateAndRender,
    FillGroundChunk,
    DebugStart,
    DebugEnd,
    BeginRender,
    PushRenderElement,
    DrawRectangle,
    DrawBitmap,
    DrawRectangleSlowly,
    DrawRectangleQuickly,
    ProcessPixel,
    RenderToOutput,
    TiledRenderToOutput,
    SingleRenderToOutput,
    DoTiledRenderWork,
    EndRender,

    GetRenderEntityBasisPosition,
    ChangeSaturation,
    MoveEntity,
    EntitiesOverlap,
    SpeculativeCollide,
    BeginSimulation,
    EndSimulation,
    AddEntityRaw,

    ChangeEntityLocation,
    ChangeEntityLocationRaw,
    GetWorldChunk,

    PlaySound,
    OutputPlayingSounds,

    LoadAssetWorkDirectly,
    AcquireAssetMemory,
    LoadBitmap,
    LoadSound,
    LoadFont,
    GetBestMatchAsset,
    GetRandomAsset,
    GetFirstAsset,

    HotEntity,
    HotEntity1,
    HotEntity2,
    HotEntity3,
    HotEntity4,
    HotEntity5,
};

pub const DebugTable = extern struct {
    current_event_array_index: u32 = 0,
    event_array_index_event_index: u64 = 0,
    event_count: [MAX_DEBUG_EVENT_ARRAY_COUNT]u32 = [1]u32{0} ** MAX_DEBUG_EVENT_ARRAY_COUNT,
    events: [MAX_DEBUG_EVENT_ARRAY_COUNT][MAX_DEBUG_EVENT_COUNT]DebugEvent = [1][MAX_DEBUG_EVENT_COUNT]DebugEvent{
        [1]DebugEvent{DebugEvent{}} ** MAX_DEBUG_EVENT_COUNT,
    } ** MAX_DEBUG_EVENT_ARRAY_COUNT,
};

pub const DebugId = extern struct {
    value: [2]*void,

    pub fn fromLink(tree: *debug.DebugTree, link: *debug.DebugVariableLink) DebugId {
        return DebugId{ .value = .{ @ptrCast(tree), @ptrCast(link) } };
    }

    pub fn fromPointer(pointer: *anyopaque) DebugId {
        return DebugId{ .value = .{ @ptrCast(pointer), undefined } };
    }

    pub fn equals(self: DebugId, other: DebugId) bool {
        return @intFromPtr(self.value[0]) == @intFromPtr(other.value[0]) and
            @intFromPtr(self.value[0]) == @intFromPtr(other.value[0]);
    }
};

pub const DebugType = enum(u8) {
    FrameMarker,
    BeginBlock,
    EndBlock,

    OpenDataBlock,
    CloseDataBlock,
    Bool,
    F32,
    U32,
    I32,
    Vector2,
    Vector3,
    Vector4,
    Rectangle2,
    Rectangle3,
    BitmapId,
    SoundId,
    FontId,

    CounterThreadList,
    // CounterFunctionList,
};

pub const DebugEvent = extern struct {
    clock: u64 = 0,
    file_name: [*:0]const u8 = undefined,
    block_name: [*:0]const u8 = undefined,
    line_number: u32 = undefined,

    thread_id: u16 = undefined,
    core_index: u16 = undefined,
    event_type: DebugType = undefined,
    data: extern union {
        debug_id: DebugId,
        bool: bool,
        int: i32,
        uint: u32,
        float: f32,
        vector2: Vector2,
        vector3: Vector3,
        vector4: Vector4,
        rectangle2: Rectangle2,
        rectangle3: Rectangle3,
        bitmap_id: BitmapId,
        sound_id: SoundId,
        font_id: FontId,
    } = undefined,

    pub fn setValue(self: *DebugEvent, value: anytype) void {
        switch (@TypeOf(value)) {
            u32 => {
                self.event_type = .U32;
                self.data = .{ .uint = value };
            },
            i32 => {
                self.event_type = .I32;
                self.data = .{ .int = value };
            },
            f32 => {
                self.event_type = .F32;
                self.data = .{ .float = value };
            },
            Vector2 => {
                self.event_type = .Vector2;
                self.data = .{ .vector2 = value };
            },
            Vector3 => {
                self.event_type = .Vector3;
                self.data = .{ .vector3 = value };
            },
            Vector4 => {
                self.event_type = .Vector4;
                self.data = .{ .vector4 = value };
            },
            Rectangle2 => {
                self.event_type = .Rectangle2;
                self.data = .{ .rectangle2 = value };
            },
            Rectangle3 => {
                self.event_type = .Rectangle3;
                self.data = .{ .rectangle3 = value };
            },
            BitmapId => {
                self.event_type = .BitmapId;
                self.data = .{ .bitmap_id = value };
            },
            SoundId => {
                self.event_type = .SoundId;
                self.data = .{ .sound_id = value };
            },
            FontId => {
                self.event_type = .FontId;
                self.data = .{ .font_id = value };
            },
            else => {},
        }
    }

    pub fn matches(a: *DebugEvent, b: *DebugEvent) bool {
        return (a.thread_id == b.thread_id);
    }

    pub fn typeString(self: *DebugEvent) []const u8 {
        return switch (self.event_type) {
            .Bool => "bool",
            .I32 => "i32",
            .U32 => "u32",
            .F32 => "f32",
            .Vector2 => "Vector2",
            .Vector3 => "Vector3",
            .Vector4 => "Vector4",
            else => "",
        };
    }

    pub fn prefixString(self: *DebugEvent) []const u8 {
        return switch (self.event_type) {
            .OpenDataBlock => "// ",
            else => "pub const DEBUGUI_",
        };
    }
};

fn recordDebugEvent(source: std.builtin.SourceLocation, event_type: DebugType, block: [*:0]const u8) *DebugEvent {
    const event_array_index_event_index = @atomicRmw(u64, &shared.global_debug_table.event_array_index_event_index, .Add, 1, .seq_cst);
    const array_index = event_array_index_event_index >> 32;
    const event_index = event_array_index_event_index & 0xffffffff;
    std.debug.assert(event_index < MAX_DEBUG_EVENT_COUNT);

    var event: *DebugEvent = &shared.global_debug_table.events[array_index][event_index];
    event.clock = shared.rdtsc();
    event.event_type = event_type;
    event.thread_id = @truncate(shared.getThreadId());
    event.core_index = 0;
    event.file_name = source.file;
    event.block_name = block;
    event.line_number = source.line;

    return event;
}

pub const TimedBlock = if (INTERNAL) struct {
    counter: DebugCycleCounters = undefined,

    pub fn beginBlock(source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        return begin_(source, counter, true);
    }

    pub fn beginFunction(source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        return begin_(source, counter, false);
    }

    fn begin_(source: std.builtin.SourceLocation, counter: DebugCycleCounters, is_block: bool) TimedBlock {
        const result = TimedBlock{ .counter = counter };

        _ = recordDebugEvent(source, .BeginBlock, if (is_block) @tagName(counter) else source.fn_name);

        return result;
    }

    pub fn frameMarker(source: std.builtin.SourceLocation, counter: DebugCycleCounters, seconds_elapsed: f32) TimedBlock {
        const result = TimedBlock{ .counter = counter };

        var event = recordDebugEvent(source, .FrameMarker, "Frame Marker");
        event.data = .{ .float = seconds_elapsed };

        return result;
    }

    pub fn beginWithCount(source: std.builtin.SourceLocation, counter: DebugCycleCounters, hit_count: u32) TimedBlock {
        const result = TimedBlock.beginBlock(source, counter);
        // result.hit_count = hit_count;
        _ = hit_count;
        return result;
    }

    pub fn end(self: TimedBlock) void {
        _ = self;
        _ = recordDebugEvent(@src(), .EndBlock, "End block");
    }
} else struct {
    pub fn beginBlock(source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        _ = source;
        _ = counter;
        return undefined;
    }

    pub fn beginFunction(source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        _ = source;
        _ = counter;
        return undefined;
    }

    pub fn frameMarker(source: std.builtin.SourceLocation, counter: DebugCycleCounters, seconds_elapsed: f32) TimedBlock {
        _ = source;
        _ = counter;
        _ = seconds_elapsed;
        return undefined;
    }

    pub fn beginWithCount(source: std.builtin.SourceLocation, counter: DebugCycleCounters, hit_count: u32) TimedBlock {
        _ = source;
        _ = counter;
        _ = hit_count;
        return undefined;
    }

    pub fn end(self: TimedBlock) void {
        _ = self;
    }
};

pub fn debugBeginDataBlock(
    source: std.builtin.SourceLocation,
    name: [*:0]const u8,
    id: DebugId,
) void {
    var event = recordDebugEvent(source, .OpenDataBlock, name);
    event.data = .{ .debug_id = id };
}

pub fn debugValue(source: std.builtin.SourceLocation, value: anytype) void {
    var event = recordDebugEvent(source, .F32, "Value");
    event.setValue(value);
}

pub fn debugBeginArray(array: anytype) void {
    _ = array;
}

pub fn debugEndArray() void {
}

pub fn debugEndDataBlock(source: std.builtin.SourceLocation) void {
    _ = recordDebugEvent(source, .CloseDataBlock, "End Data Block");
}
