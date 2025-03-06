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
const MemoryArena = shared.MemoryArena;
const LoadedBitmap = asset.LoadedBitmap;
const LoadedSound = asset.LoadedSound;
const Assets = asset.Assets;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const FontId = file_formats.FontId;

var global_config = &@import("config.zig").global_config;
pub const hit = if (INTERNAL) debug.hit else debug.hitStub;
pub const highlighted = if (INTERNAL) debug.highlighted else debug.highlightedStub;
pub const requested = if (INTERNAL) debug.requested else debug.requestedStub;

// Build options.
pub const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;
pub const INTERNAL = @import("build_options").internal;

pub const MAX_DEBUG_REGIONS_PER_FRAME = 2 * 4096;
pub const DEBUG_UI_ENABLED = true;

pub const DebugTable = extern struct {
    edit_event: DebugEvent = DebugEvent{},
    record_increment: u32 = 0,
    current_event_array_index: u32 = 0,
    event_array_index_event_index: u64 = 0,

    events: [2][16 * 65536]DebugEvent = [1][16 * 65536]DebugEvent{
        [1]DebugEvent{DebugEvent{}} ** (16 * 65536),
    } ** 2,

    pub fn setEventRecording(self: *DebugTable, enabled: bool) void {
        self.record_increment = if (enabled) 1 else 0;
    }
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

pub const DebugType = if (INTERNAL) enum(u32) {
    Unknown,

    FrameMarker,
    BeginBlock,
    EndBlock,

    OpenDataBlock,
    CloseDataBlock,

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
    Enum,
    MemoryArena,

    ThreadIntervalGraph,
    FrameBarGraph,
    LastFrameInfo,
    DebugMemoryInfo,
    FrameSlider,
    TopClocksList,
    ArenaOccupancy,
} else enum(u32) {};

pub const DebugEvent = if (INTERNAL) extern struct {
    clock: u64 = 0,
    guid: [*:0]const u8 = undefined,
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
        SoundId: SoundId,
        FontId: FontId,
        Enum: u32,
        MemoryArena: *shared.MemoryArena,
    } = undefined,

    pub fn debugName(
        comptime source: std.builtin.SourceLocation,
        comptime counter: ?@TypeOf(.EnumLiteral),
        comptime name: []const u8,
    ) [*:0]const u8 {
        const counter_name = if (counter != null) @tagName(counter.?) else "NOCOUNTER";
        const line_number = std.fmt.comptimePrint("{d}", .{source.line});
        return source.fn_name ++ "|" ++ line_number ++ "|" ++ counter_name ++ "|" ++ name;
    }

    pub fn record(
        comptime event_type: DebugType,
        guid: [*:0]const u8,
    ) *DebugEvent {
        const event_array_index_event_index =
            @atomicRmw(
            u64,
            &shared.global_debug_table.event_array_index_event_index,
            .Add,
            shared.global_debug_table.record_increment,
            .seq_cst,
        );
        const array_index = event_array_index_event_index >> 32;
        const event_index = event_array_index_event_index & 0xffffffff;
        std.debug.assert(event_index < shared.global_debug_table.events[0].len);

        var event: *DebugEvent = &shared.global_debug_table.events[array_index][event_index];
        event.clock = shared.rdtsc();
        event.event_type = event_type;
        event.core_index = 0;
        event.thread_id = @truncate(shared.getThreadId());
        event.guid = guid;

        return event;
    }

    pub fn setValue(self: *DebugEvent, source: anytype, dest: anytype) void {
        std.debug.assert(@typeInfo(@TypeOf(dest)) == .pointer);

        const guids_match = shared.global_debug_table.edit_event.guid == self.guid;
        // TODO: Could we use comptime to avoid duplicating this logic for each type?
        switch (@TypeOf(source)) {
            bool => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.bool;
                }
                self.event_type = .bool;
                self.data = .{ .bool = dest.* };
            },
            u32 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.u32;
                }
                self.event_type = .u32;
                self.data = .{ .u32 = dest.* };
            },
            i32 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.i32;
                }
                self.event_type = .i32;
                self.data = .{ .i32 = dest.* };
            },
            f32 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.f32;
                }
                self.event_type = .f32;
                self.data = .{ .f32 = dest.* };
            },
            Vector2 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.Vector2;
                }
                self.event_type = .Vector2;
                self.data = .{ .Vector2 = dest.* };
            },
            Vector3 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.Vector3;
                }
                self.event_type = .Vector3;
                self.data = .{ .Vector3 = dest.* };
            },
            Vector4 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.Vector4;
                }
                self.event_type = .Vector4;
                self.data = .{ .Vector4 = dest.* };
            },
            Rectangle2 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.Rectangle2;
                }
                self.event_type = .Rectangle2;
                self.data = .{ .Rectangle2 = dest.* };
            },
            Rectangle3 => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.Rectangle3;
                }
                self.event_type = .Rectangle3;
                self.data = .{ .Rectangle3 = dest.* };
            },
            BitmapId => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.BitmapId;
                }
                self.event_type = .BitmapId;
                self.data = .{ .BitmapId = dest.* };
            },
            SoundId => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.SoundId;
                }
                self.event_type = .SoundId;
                self.data = .{ .SoundId = dest.* };
            },
            FontId => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.FontId;
                }
                self.event_type = .FontId;
                self.data = .{ .FontId = dest.* };
            },
            MemoryArena => {
                if (guids_match) {
                    dest.* = shared.global_debug_table.edit_event.data.MemoryArena.*;
                }
                self.event_type = .MemoryArena;
                self.data = .{ .MemoryArena = dest };
            },
            else => {
                switch (@typeInfo(@TypeOf(source))) {
                    .@"enum" => |enum_info| {
                        if (guids_match) {
                            if (shared.global_debug_table.edit_event.data.Enum >= enum_info.fields.len) {
                                shared.global_debug_table.edit_event.data.Enum = 0;
                            }
                            dest.* = @enumFromInt(shared.global_debug_table.edit_event.data.Enum);
                        }

                        self.event_type = .Enum;
                        self.data = .{ .Enum = @intFromEnum(dest.*) };
                    },
                    else => {},
                }
            },
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
    pub fn record(event_type: DebugType, block: [*:0]const u8) *DebugEvent {
        _ = event_type;
        _ = block;
        return undefined;
    }
};

pub const TimedBlock = if (INTERNAL) struct {
    pub fn beginBlock(comptime source: std.builtin.SourceLocation, comptime counter: @TypeOf(.EnumLiteral)) void {
        begin(DebugEvent.debugName(source, counter, @tagName(counter)));
    }

    pub fn endBlock(comptime source: std.builtin.SourceLocation, comptime counter: @TypeOf(.EnumLiteral)) void {
        end(DebugEvent.debugName(source, counter, "END_BLOCK_"));
    }

    pub fn beginFunction(comptime source: std.builtin.SourceLocation, comptime counter: @TypeOf(.EnumLiteral)) void {
        begin(DebugEvent.debugName(source, counter, source.fn_name));
    }

    pub fn endFunction(comptime source: std.builtin.SourceLocation, comptime counter: @TypeOf(.EnumLiteral)) void {
        end(DebugEvent.debugName(source, counter, "END_BLOCK_"));
    }

    fn begin(guid: [*:0]const u8) void {
        _ = DebugEvent.record(.BeginBlock, guid);
    }

    fn end(guid: [*:0]const u8) void {
        _ = DebugEvent.record(.EndBlock, guid);
    }

    pub fn frameMarker(
        comptime source: std.builtin.SourceLocation,
        comptime counter: @TypeOf(.EnumLiteral),
        seconds_elapsed: f32,
    ) void {
        var event = DebugEvent.record(.FrameMarker, DebugEvent.debugName(source, counter, "Frame Marker"));
        event.data = .{ .f32 = seconds_elapsed };
    }

    pub fn beginWithCount(
        comptime source: std.builtin.SourceLocation,
        comptime counter: @TypeOf(.EnumLiteral),
        hit_count: u32,
    ) void {
        _ = hit_count;
        TimedBlock.beginBlock(source, counter);
    }
} else struct {
    pub fn beginBlock(source: std.builtin.SourceLocation, counter: @TypeOf(.EnumLiteral)) void {
        _ = source;
        _ = counter;
    }

    pub fn endBlock(comptime source: std.builtin.SourceLocation, comptime counter: @TypeOf(.EnumLiteral)) void {
        _ = source;
        _ = counter;
    }

    pub fn beginFunction(source: std.builtin.SourceLocation, counter: @TypeOf(.EnumLiteral)) void {
        _ = source;
        _ = counter;
    }

    pub fn endFunction(comptime source: std.builtin.SourceLocation, comptime counter: @TypeOf(.EnumLiteral)) void {
        _ = source;
        _ = counter;
    }

    pub fn frameMarker(source: std.builtin.SourceLocation, counter: @TypeOf(.EnumLiteral), seconds_elapsed: f32) void {
        _ = source;
        _ = counter;
        _ = seconds_elapsed;
    }

    pub fn beginWithCount(source: std.builtin.SourceLocation, counter: @TypeOf(.EnumLiteral), hit_count: u32) void {
        _ = source;
        _ = counter;
        _ = hit_count;
    }

    pub fn end(self: TimedBlock) void {
        _ = self;
    }
};

fn runtimeFieldPointer(ptr: anytype, comptime field_name: []const u8) *@TypeOf(@field(ptr.*, field_name)) {
    const field_offset = @offsetOf(@TypeOf(ptr.*), field_name);
    const base_ptr: [*]u8 = @ptrCast(ptr);
    return @ptrCast(@alignCast(&base_ptr[field_offset]));
}

pub const DebugInterface = if (INTERNAL) struct {
    pub fn debugBeginDataBlock(
        comptime source: std.builtin.SourceLocation,
        comptime name: []const u8,
    ) void {
        var event = DebugEvent.record(.OpenDataBlock, DebugEvent.debugName(source, null, name));
        event.data = .{ .debug_id = DebugId.fromPointer(@ptrCast(@constCast(name))) };
    }

    pub fn debugEndDataBlock(comptime source: std.builtin.SourceLocation) void {
        _ = DebugEvent.record(.CloseDataBlock, DebugEvent.debugName(source, null, "End Data Block"));
    }

    pub fn debugValue(
        comptime source: std.builtin.SourceLocation,
        value_ptr: anytype,
        comptime field_name: []const u8,
    ) void {
        const guid = DebugEvent.debugName(source, null, field_name);
        var event = DebugEvent.record(.Unknown, guid);
        event.setValue(value_ptr.*, value_ptr);
    }

    pub fn debugStruct(comptime source: std.builtin.SourceLocation, parent: anytype) void {
        const fields = std.meta.fields(@TypeOf(parent.*));
        inline for (fields) |field| {
            debugValue(source, runtimeFieldPointer(parent, field.name), field.name);
        }
    }

    pub fn debugNamedValue(
        comptime source: std.builtin.SourceLocation,
        value_ptr: anytype,
        comptime field_name: []const u8,
    ) void {
        var event = DebugEvent.record(.Unknown, source.fn_name ++ field_name);
        event.setValue(value_ptr.*, value_ptr);
    }

    pub fn debugUIElement(
        comptime source: std.builtin.SourceLocation,
        comptime element_type: DebugType,
        comptime name: []const u8,
    ) void {
        _ = source;
        _ = DebugEvent.record(element_type, @ptrCast(name));
    }

    pub fn debugBeginArray(array: anytype) void {
        _ = array;
    }

    pub fn debugEndArray() void {}

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
} else struct {
    pub fn debugBeginDataBlock(
        source: std.builtin.SourceLocation,
        name: [*:0]const u8,
    ) void {
        _ = source;
        _ = name;
    }

    pub fn debugEndDataBlock(source: std.builtin.SourceLocation) void {
        _ = source;
    }

    pub fn debugStruct(source: std.builtin.SourceLocation, parent: anytype) void {
        _ = source;
        _ = parent;
    }

    pub fn debugNamedValue(
        comptime source: std.builtin.SourceLocation,
        value_ptr: anytype,
        comptime field_name: []const u8,
    ) void {
        _ = source;
        _ = value_ptr;
        _ = field_name;
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
};
