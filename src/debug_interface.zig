const shared = @import("shared.zig");
const math = @import("math.zig");
const asset = @import("asset.zig");
const debug = @import("debug.zig");
const file_formats = @import("file_formats");
const config = @import("config.zig");
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

pub const hit = if (INTERNAL) debug.hit else debug.hitStub;
pub const highlighted = if (INTERNAL) debug.highlighted else debug.highlightedStub;
pub const requested = if (INTERNAL) debug.requested else debug.requestedStub;

// Build options.
pub const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;
pub const INTERNAL = @import("build_options").internal;

pub const MAX_DEBUG_REGIONS_PER_FRAME = 2 * 4096;
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
    RenderToOutputOpenGL,
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

    events: [2][16 * 65536]DebugEvent = [1][16 * 65536]DebugEvent{
        [1]DebugEvent{DebugEvent{}} ** (16 * 65536),
    } ** 2,
};

pub const DebugId = extern struct {
    value: [2]*anyopaque,

    pub fn fromLink(tree: *debug.DebugTree, link: *debug.DebugVariableLink) DebugId {
        return DebugId{ .value = .{ @ptrCast(tree), @ptrCast(link) } };
    }

    pub fn fromGuid(tree: *debug.DebugTree, guid: [*:0]const u8) DebugId {
        return DebugId{ .value = .{ @ptrCast(tree), @ptrCast(@constCast(guid)) } };
    }

    pub fn fromPointer(pointer: *anyopaque) DebugId {
        return DebugId{ .value = .{ @ptrCast(pointer), undefined } };
    }

    pub fn equals(self: DebugId, other: DebugId) bool {
        return @intFromPtr(self.value[0]) == @intFromPtr(other.value[0]) and
            @intFromPtr(self.value[1]) == @intFromPtr(other.value[1]);
    }
};

pub const DebugType = if (INTERNAL) enum(u8) {
    Unknown,

    FrameMarker,
    BeginBlock,
    EndBlock,

    OpenDataBlock,
    CloseDataBlock,

    MarkDebugValue,

    bool,
    f32,
    u32,
    i32,
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
} else enum(u8) {};

pub const DebugEvent = if (INTERNAL) extern struct {
    clock: u64 = 0,
    guid: [*:0]const u8 = undefined,
    block_name: [*:0]const u8 = undefined,
    thread_id: u16 = undefined,
    core_index: u16 = undefined,
    event_type: DebugType = undefined,
    data: extern union {
        value_debug_event: *DebugEvent,
        debug_id: DebugId,
        bool: bool,
        i32: i32,
        u32: u32,
        f32: f32,
        Vector2: Vector2,
        Vector3: Vector3,
        Vector4: Vector4,
        Rectangle2: Rectangle2,
        Rectangle3: Rectangle3,
        BitmapId: BitmapId,
        SoudnId: SoundId,
        FontId: FontId,
    } = undefined,

    fn uniqueFileCounterString(comptime file_name: []const u8, comptime line_number: u32, comptime counter: DebugType) [*:0]const u8 {
        return file_name ++ "(" ++ std.fmt.comptimePrint("{d}", .{line_number}) ++ ")." ++ @tagName(counter);
    }

    pub fn record(comptime source: std.builtin.SourceLocation, comptime event_type: DebugType, block: [*:0]const u8) *DebugEvent {
        const event_array_index_event_index = @atomicRmw(u64, &shared.global_debug_table.event_array_index_event_index, .Add, 1, .seq_cst);
        const array_index = event_array_index_event_index >> 32;
        const event_index = event_array_index_event_index & 0xffffffff;
        std.debug.assert(event_index < shared.global_debug_table.events[0].len);

        var event: *DebugEvent = &shared.global_debug_table.events[array_index][event_index];
        event.clock = shared.rdtsc();
        event.event_type = event_type;
        event.core_index = 0;
        event.thread_id = @truncate(shared.getThreadId());
        event.guid = DebugEvent.uniqueFileCounterString(source.file, source.line, event_type);
        event.block_name = block;

        return event;
    }

    pub fn setValue(self: *DebugEvent, value: anytype) void {
        switch (@TypeOf(value)) {
            *DebugEvent => {
                self.event_type = .MarkDebugValue;
                self.data = .{ .value_debug_event = value };
            },
            u32 => {
                self.event_type = .u32;
                self.data = .{ .u32 = value };
            },
            i32 => {
                self.event_type = .i32;
                self.data = .{ .i32 = value };
            },
            f32 => {
                self.event_type = .f32;
                self.data = .{ .f32 = value };
            },
            Vector2 => {
                self.event_type = .Vector2;
                self.data = .{ .Vector2 = value };
            },
            Vector3 => {
                self.event_type = .Vector3;
                self.data = .{ .Vector3 = value };
            },
            Vector4 => {
                self.event_type = .Vector4;
                self.data = .{ .Vector4 = value };
            },
            Rectangle2 => {
                self.event_type = .Rectangle2;
                self.data = .{ .Rectangle2 = value };
            },
            Rectangle3 => {
                self.event_type = .Rectangle3;
                self.data = .{ .Rectangle3 = value };
            },
            BitmapId => {
                self.event_type = .BitmapId;
                self.data = .{ .BitmapId = value };
            },
            SoundId => {
                self.event_type = .SoundId;
                self.data = .{ .SoundId = value };
            },
            FontId => {
                self.event_type = .FontId;
                self.data = .{ .FontId = value };
            },
            else => {},
        }
    }

    pub fn matches(a: *DebugEvent, b: *DebugEvent) bool {
        return (a.thread_id == b.thread_id);
    }

    pub fn typeString(self: *DebugEvent) []const u8 {
        return @tagName(self.event_type);
    }

    pub fn prefixString(self: *DebugEvent) []const u8 {
        return switch (self.event_type) {
            .OpenDataBlock => "// ",
            else => "pub const DEBUGUI_",
        };
    }
} else struct {
    pub fn record(source: std.builtin.SourceLocation, event_type: DebugType, block: [*:0]const u8) *DebugEvent {
        _ = source;
        _ = event_type;
        _ = block;
        return undefined;
    }
};

pub const TimedBlock = if (INTERNAL) struct {
    counter: DebugCycleCounters = undefined,

    pub fn beginBlock(comptime source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        return begin_(source, counter, true);
    }

    pub fn beginFunction(comptime source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        return begin_(source, counter, false);
    }

    fn begin_(comptime source: std.builtin.SourceLocation, counter: DebugCycleCounters, is_block: bool) TimedBlock {
        const result = TimedBlock{ .counter = counter };

        _ = DebugEvent.record(source, .BeginBlock, if (is_block) @tagName(counter) else source.fn_name);

        return result;
    }

    pub fn frameMarker(comptime source: std.builtin.SourceLocation, counter: DebugCycleCounters, seconds_elapsed: f32) TimedBlock {
        const result = TimedBlock{ .counter = counter };

        var event = DebugEvent.record(source, .FrameMarker, "Frame Marker");
        event.data = .{ .f32 = seconds_elapsed };

        return result;
    }

    pub fn beginWithCount(comptime source: std.builtin.SourceLocation, counter: DebugCycleCounters, hit_count: u32) TimedBlock {
        const result = TimedBlock.beginBlock(source, counter);
        // result.hit_count = hit_count;
        _ = hit_count;
        return result;
    }

    pub fn end(self: TimedBlock) void {
        _ = self;
        _ = DebugEvent.record(@src(), .EndBlock, "End block");
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

pub const DebugInterface = if (INTERNAL) struct {
    pub fn debugBeginDataBlock(
        comptime source: std.builtin.SourceLocation,
        name: [*:0]const u8,
        id: DebugId,
    ) void {
        var event = DebugEvent.record(source, .OpenDataBlock, name);
        event.data = .{ .debug_id = id };
    }

    fn formatFieldName(comptime name: []const u8) []const u8 {
        var buf: [128]u8 = undefined;
        _ = std.mem.replace(u8, name, "_", "-", &buf);
        // return &buf[0..name.len];
        const final = buf[0..name.len].*;
        return &final;
    }

    pub fn debugStruct(comptime source: std.builtin.SourceLocation, parent: anytype) void {
        const fields = std.meta.fields(@TypeOf(parent.*));
        inline for (fields) |field| {
            debugValue(source, parent, field.name);
        }
    }

    pub fn debugValue(
        comptime source: std.builtin.SourceLocation,
        parent: anytype,
        comptime field_name: []const u8,
    ) void {
        const display_name = comptime DebugInterface.formatFieldName(field_name);
        const value = @field(parent, field_name);
        const type_info = @typeInfo(@TypeOf(value));
        var event = DebugEvent.record(source, .Unknown, @ptrCast(@typeName(@TypeOf(parent)) ++ "." ++ display_name));
        switch (type_info) {
            .Optional => {
                if (value) |v| {
                    event.setValue(v);
                }
            },
            else => {
                event.setValue(value);
            },
        }
    }

    pub fn debugBeginArray(array: anytype) void {
        _ = array;
    }

    pub fn debugEndArray() void {}

    pub fn debugEndDataBlock(comptime source: std.builtin.SourceLocation) void {
        _ = DebugEvent.record(source, .CloseDataBlock, "End Data Block");
    }

    fn LocalStorageType() type {
        const storage_fields = comptime blk: {
            var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
            for (std.meta.fields(config.GlobalConstants)) |field| {
                fields = fields ++ &[1]std.builtin.Type.StructField{std.builtin.Type.StructField{
                    .name = field.name,
                    .type = ?DebugEvent,
                    .default_value = @ptrCast(&@as(?DebugEvent, null)),
                    .is_comptime = false,
                    .alignment = 0,
                }};
            }
            break :blk fields;
        };

        return @Type(.{
            .Struct = .{
                .layout = std.builtin.Type.ContainerLayout.auto,
                .fields = storage_fields,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });
    }

    pub fn debugVariable(comptime source: std.builtin.SourceLocation, comptime T: type, comptime path: []const u8) T {
        const LocalStorage = LocalStorageType();
        const local_persist = struct {
            var storage: LocalStorage = LocalStorage{};
        };

        const event: *?DebugEvent = &@field(local_persist.storage, path);
        if (event.* == null) {
            const default_value = @field(config.global_constants, path);
            event.* = DebugEvent{};
            event.* = debug.initializeDebugValue(
                source,
                .bool,
                &event.*.?,
                DebugEvent.uniqueFileCounterString(source.file, source.line, @field(DebugType, @typeName(T))),
                path,
            );
            event.*.?.setValue(default_value);
        }

        return @field(event.*.?.data, @typeName(T));
    }

    pub fn debugIf(comptime source: std.builtin.SourceLocation, comptime path: []const u8) bool {
        const LocalStorage = LocalStorageType();
        const local_persist = struct {
            var storage: LocalStorage = LocalStorage{};
        };

        const event: *?DebugEvent = &@field(local_persist.storage, path);
        if (event.* == null) {
            const default_value = @field(config.global_constants, path);
            event.* = DebugEvent{};
            event.* = debug.initializeDebugValue(
                source,
                .bool,
                &event.*.?,
                DebugEvent.uniqueFileCounterString(source.file, source.line, .bool),
                path,
            );
            event.*.?.setValue(default_value);
        }

        return event.*.?.data.bool;
    }
} else struct {
    pub fn debugBeginDataBlock(
        source: std.builtin.SourceLocation,
        name: [*:0]const u8,
        id: DebugId,
    ) void {
        _ = source;
        _ = name;
        _ = id;
    }

    pub fn debugStruct(source: std.builtin.SourceLocation, parent: anytype) void {
        _ = source;
        _ = parent;
    }

    pub fn debugValue(source: std.builtin.SourceLocation, parent: anytype, comptime field_name: []const u8) void {
        _ = source;
        _ = parent;
        _ = field_name;
    }

    pub fn debugBeginArray(array: anytype) void {
        _ = array;
    }

    pub fn debugEndArray() void {}

    pub fn debugEndDataBlock(source: std.builtin.SourceLocation) void {
        _ = source;
    }
    pub fn debugVariable(source: std.builtin.SourceLocation, comptime T: type, comptime path: []const u8) T {
        _ = source;
        return @field(config.global_constants, path);
    }

    pub fn debugIf(source: std.builtin.SourceLocation, comptime path: []const u8) bool {
        _ = source;
        return @field(config.global_constants, path);
    }
};
