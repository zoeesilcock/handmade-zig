const shared = @import("shared.zig");
const asset = @import("asset.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const config = @import("config.zig");
const file_formats = @import("file_formats");
const debug_variables = @import("debug_variables.zig");
const std = @import("std");

// Types.
const DebugRecord = shared.DebugRecord;
const DebugEventType = shared.DebugEventType;
const DebugEvent = shared.DebugEvent;
const TimedBlock = shared.TimedBlock;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle2 = math.Rectangle2;

pub var global_debug_table: shared.DebugTable = shared.DebugTable{};

const COUNTER_COUNT = 512;

const DebugTextOp = enum {
    DrawText,
    SizeText,
};

pub const DebugCounterSnapshot = struct {
    hit_count: u32 = 0,
    cycle_count: u64 = 0,
};

pub const DebugCounterState = struct {
    file_name: ?[*:0]const u8 = null,
    block_name: ?[*:0]const u8 = null,
    line_number: u32 = undefined,
};

const DebugFrame = struct {
    begin_clock: u64,
    end_clock: u64,
    wall_seconds_elapsed: f32,
    region_count: u32,
    regions: [*]DebugFrameRegion,
};

const DebugFrameRegion = struct {
    record: *DebugRecord,
    cycle_count: u64,
    lane_index: u16,
    color_index: u16,
    min_t: f32,
    max_t: f32,
};

const OpenDebugBlock = struct {
    staring_frame_index: u32,
    source: *DebugRecord,
    opening_event: *DebugEvent,
    parent: ?*OpenDebugBlock,
    next_free: ?*OpenDebugBlock,
};

const DebugThread = struct {
    id: u32,
    lane_index: u32,
    first_open_block: ?*OpenDebugBlock,
    next: ?*DebugThread,
};

pub const DebugStatistic = struct {
    min: f64,
    max: f64,
    average: f64,
    count: u32,

    pub fn begin() DebugStatistic {
        return DebugStatistic{
            .min = std.math.floatMax(f64),
            .max = -std.math.floatMax(f64),
            .average = 0,
            .count = 0,
        };
    }

    pub fn accumulate(self: *DebugStatistic, value: f64) void {
        self.count += 1;

        if (self.min > value) {
            self.min = value;
        }

        if (self.max < value) {
            self.max = value;
        }

        self.average += value;
    }

    pub fn end(self: *DebugStatistic) void {
        if (self.count != 0) {
            self.average /= @as(f32, @floatFromInt(self.count));
        } else {
            self.min = 0;
            self.max = 0;
        }
    }
};

const DebugInteractionType = enum(u32) {
    None,
    NoOp,
    AutoModifyVariable,
    ToggleValue,
    DragValue,
    TearValue,
    Resize,
    Move
};

const DebugInteractionTargetType = enum(u32) {
    variable,
    tree,
    position,
};

const DebugInteraction = struct {
    interaction_type: DebugInteractionType,

    target: union(DebugInteractionTargetType) {
        variable: *DebugVariable,
        tree: ?*DebugTree,
        position: *Vector2,
    },

    pub fn equals(self: *const DebugInteraction, other: *const DebugInteraction) bool {
        return self.interaction_type == other.interaction_type and std.meta.eql(self.target, other.target);
    }
};

pub const DebugState = struct {
    initialized: bool,

    high_priority_queue: *shared.PlatformWorkQueue,
    debug_arena: shared.MemoryArena,

    render_group: ?*render.RenderGroup = null,
    debug_font: ?*asset.LoadedFont,
    debug_font_info: ?*file_formats.HHAFont,

    is_compiling: bool = false,
    compiler: shared.DebugExecutingProcess,

    menu_position: Vector2,
    menu_active: bool,

    root_group: ?*DebugVariable,
    view_hash: [4096]*DebugView = [1]*DebugView{undefined} ** 4096,
    tree_sentinel: DebugTree,

    last_mouse_position: Vector2,
    interaction: DebugInteraction,
    hot_interaction: DebugInteraction,
    next_hot_interaction: DebugInteraction,

    left_edge: f32 = 0,
    right_edge: f32 = 0,
    at_y: f32 = 0,
    font_scale: f32 = 0,
    font_id: file_formats.FontId = undefined,
    global_width: f32 = 0,
    global_height: f32 = 0,

    scope_to_record: ?*DebugRecord,

    collate_arena: shared.MemoryArena,
    collate_temp: shared.TemporaryMemory,

    collation_array_index: u32,
    collation_frame: ?*DebugFrame,
    frame_bar_lane_count: u32,
    frame_bar_scale: f32,
    frame_count: u32,
    paused: bool,

    frames: [*]DebugFrame,
    first_thread: ?*DebugThread,
    first_free_block: ?*OpenDebugBlock,

    pub fn get() ?*DebugState {
        var result: ?*DebugState = null;

        if (shared.debug_global_memory) |memory| {
            result = @ptrCast(@alignCast(memory.debug_storage));
        }

        return result;
    }

    fn restartCollation(self: *DebugState, invalid_event_array_index: u32) void {
        self.collate_arena.endTemporaryMemory(self.collate_temp);
        self.collate_temp = self.collate_arena.beginTemporaryMemory();

        self.first_thread = null;
        self.first_free_block = null;

        self.frames = self.collate_arena.pushArray(shared.MAX_DEBUG_EVENT_ARRAY_COUNT * 4, DebugFrame);
        self.frame_bar_lane_count = 0;
        self.frame_bar_scale = 1.0 / (60.0 * 1000000.0);
        self.frame_count = 0;

        self.collation_array_index = invalid_event_array_index + 1;
        self.collation_frame = null;
    }

    fn refreshCollation(self: *DebugState) void {
        self.restartCollation(global_debug_table.current_event_array_index);
        self.collateDebugRecords(global_debug_table.current_event_array_index);
    }

    pub fn collateDebugRecords(self: *DebugState, invalid_event_array_index: u32) void {
        while (true) : (self.collation_array_index += 1) {
            if (self.collation_array_index == shared.MAX_DEBUG_EVENT_ARRAY_COUNT) {
                self.collation_array_index = 0;
            }

            if (self.collation_array_index == invalid_event_array_index) {
                break;
            }

            var event_index: u32 = 0;
            while (event_index < global_debug_table.event_count[self.collation_array_index]) : (event_index += 1) {
                const event: *DebugEvent = &global_debug_table.events[self.collation_array_index][event_index];
                const source: *DebugRecord = &global_debug_table.records[shared.TRANSLATION_UNIT_INDEX][event.debug_record_index];

                if (event.event_type == .FrameMarker) {
                    if (self.collation_frame) |current_frame| {
                        current_frame.end_clock = event.clock;
                        current_frame.wall_seconds_elapsed = event.data.seconds_elapsed;
                        self.frame_count += 1;

                        if (false) {
                            const clock_range: f32 = @floatFromInt(current_frame.end_clock - current_frame.begin_clock);
                            if (clock_range > 0) {
                                const frame_bar_scale = 1.0 / clock_range;

                                if (self.frame_bar_scale > frame_bar_scale) {
                                    self.frame_bar_scale = frame_bar_scale;
                                }
                            }
                        }
                    }

                    self.collation_frame = &self.frames[self.frame_count];

                    if (self.collation_frame) |current_frame| {
                        current_frame.begin_clock = event.clock;
                        current_frame.end_clock = 0;
                        current_frame.region_count = 0;
                        current_frame.regions = self.collate_arena.pushArray(shared.MAX_DEBUG_REGIONS_PER_FRAME, DebugFrameRegion);
                        current_frame.wall_seconds_elapsed = 0;
                    }
                } else {
                    if (self.collation_frame) |current_frame| {
                        const frame_index: u32 = self.frame_count -% 1;
                        const thread: *DebugThread = self.getDebugThread(event.data.tc.thread_id);
                        const relative_clock: u64 = event.clock - current_frame.begin_clock;

                        _ = relative_clock;

                        switch (event.event_type) {
                            .BeginBlock => {
                                var debug_block: ?*OpenDebugBlock = self.first_free_block;

                                if (debug_block) |block| {
                                    self.first_free_block = block.next_free;
                                } else {
                                    debug_block = self.collate_arena.pushStruct(OpenDebugBlock);
                                }

                                if (debug_block) |block| {
                                    block.staring_frame_index = frame_index;
                                    block.opening_event = event;
                                    block.parent = thread.first_open_block;
                                    block.source = source;
                                    thread.first_open_block = block;
                                    block.next_free = null;
                                }
                            },
                            .EndBlock => {
                                if (thread.first_open_block) |matching_block| {
                                    const opening_event: *DebugEvent = matching_block.opening_event;

                                    if (opening_event.data.tc.thread_id == event.data.tc.thread_id and
                                        opening_event.debug_record_index == event.debug_record_index and
                                        opening_event.translation_unit == event.translation_unit)
                                    {
                                        if (matching_block.staring_frame_index == frame_index) {
                                            if (getRecordFrom(matching_block.parent) == self.scope_to_record) {
                                                const min_t: f32 = @floatFromInt(opening_event.clock - current_frame.begin_clock);
                                                const max_t: f32 = @floatFromInt(event.clock - current_frame.begin_clock);
                                                const threshold_t: f32 = 0.01;

                                                if ((max_t - min_t) > threshold_t) {
                                                    var region: *DebugFrameRegion = self.addRegion(current_frame);
                                                    region.record = source;
                                                    region.cycle_count = event.clock - opening_event.clock;
                                                    region.lane_index = @intCast(thread.lane_index);
                                                    region.min_t = min_t;
                                                    region.max_t = max_t;
                                                    region.color_index = opening_event.debug_record_index;
                                                }
                                            }
                                        } else {
                                            // Started on some previous frame.
                                        }

                                        matching_block.next_free = self.first_free_block;
                                        self.first_free_block = thread.first_open_block;
                                        thread.first_open_block = matching_block.parent;
                                    } else {
                                        // No begin block.
                                    }
                                }
                            },
                            else => unreachable,
                        }
                    }
                }
            }
        }
    }

    fn getDebugThread(self: *DebugState, thread_id: u32) *DebugThread {
        var result: ?*DebugThread = null;
        var opt_thread: ?*DebugThread = self.first_thread;

        while (opt_thread) |thread| : (opt_thread = thread.next) {
            if (thread.id == thread_id) {
                result = thread;
                break;
            }
        }

        if (result == null) {
            result = self.collate_arena.pushStruct(DebugThread);

            result.?.id = thread_id;
            result.?.first_open_block = null;

            result.?.lane_index = self.frame_bar_lane_count;
            self.frame_bar_lane_count += 1;

            result.?.next = self.first_thread;
            self.first_thread = result.?;
        }

        return result.?;
    }

    fn addRegion(self: *DebugState, current_frame: *DebugFrame) *DebugFrameRegion {
        _ = self;

        std.debug.assert(current_frame.region_count < shared.MAX_DEBUG_REGIONS_PER_FRAME);

        const result: *DebugFrameRegion = &current_frame.regions[current_frame.region_count];
        current_frame.region_count += 1;

        return result;
    }

    fn addTree(self: *DebugState, group: *DebugVariableReference, position: Vector2) *DebugTree {
        var tree: *DebugTree = self.debug_arena.pushStruct(DebugTree);
        tree.group = group;
        tree.ui_position = position;

        tree.next = self.hierarchy_sentinel.next;
        tree.prev = &self.hierarchy_sentinel;
        tree.next.?.prev = tree;
        tree.prev.?.next = tree;

        return tree;
    }

    fn interactionIsHot(self: *const DebugState, interaction: *const DebugInteraction) bool {
        return interaction.equals(&self.hot_interaction);
    }
};

const DebugVariableToTextFlag = enum(u32) {
    Declaration = 0x1,
    Name = 0x2,
    Type = 0x4,
    SemiColonEnd = 0x8,
    NullTerminator = 0x10,
    LineFeedEnd = 0x20,
    Colon = 0x40,

    pub fn toInt(self: DebugVariableToTextFlag) u32 {
        return @intFromEnum(self);
    }

    pub fn declarationFlags() u32 {
        return DebugVariableToTextFlag.Declaration.toInt() |
            DebugVariableToTextFlag.Name.toInt() |
            DebugVariableToTextFlag.Type.toInt() |
            DebugVariableToTextFlag.SemiColonEnd.toInt() |
            DebugVariableToTextFlag.LineFeedEnd.toInt();
    }

    pub fn displayFlags() u32 {
        return DebugVariableToTextFlag.Name.toInt() |
            DebugVariableToTextFlag.NullTerminator.toInt() |
            DebugVariableToTextFlag.Colon.toInt();
    }
};

pub const DebugTree = struct {
    ui_position: Vector2,
    group: ?*DebugVariable,

    prev: ?*DebugTree,
    next: ?*DebugTree,
};

const DebugViewType = enum(u32) {
    Basic,
    InlineBlock,
    Collapsible,
};

pub const DebugView = struct {
    tree: *DebugTree,
    variable: *DebugVariable = undefined,
    next_in_hash: *DebugView,

    view_type: DebugViewType,
    view: union {
        inline_block: DebugViewInlineBlock,
        collapsible: DebugViewCollapsible,
    },
};

pub const DebugViewCollapsible = struct {
    expanded_always: bool,
    expanded_alt_view: bool,
};

pub const DebugViewInlineBlock = struct {
    dimension: Vector2,
};

const DebugProfileSettings = struct {
    placeholder: u32,
};

const DebugBitmapDisplay = struct {
    id: file_formats.BitmapId,
};

pub const DebugVariableType = enum(u32) {
    Boolean,
    Int,
    UInt,
    Float,
    Vector2,
    Vector3,
    Vector4,
    VarArray,
    CounterThreadList,
    // CounterFunctionList,
    BitmapDisplay,
};

const DebugVariableArray = struct {
    count: u32,
    variables: [*]DebugVariable,
};

pub const DebugVariable = struct {
    variable_type: DebugVariableType = .Boolean,
    name: [*:0]const u8,

    data: union {
        bool_value: bool,
        int_value: i32,
        uint_value: u32,
        float_value: f32,
        vector2_value: Vector2,
        vector3_value: Vector3,
        vector4_value: Vector4,
        profile: DebugProfileSettings,
        bitmap_display: DebugBitmapDisplay,
        var_array: DebugVariableArray,
    },

    pub fn shouldBeWritten(self: *DebugVariable) bool {
        return self.variable_type != .CounterThreadList and self.variable_type != .BitmapDisplay;
    }

    pub fn typeString(self: *DebugVariable) []const u8 {
        return switch (self.variable_type) {
            .Boolean => "bool",
            .Int => "i32",
            .UInt => "u32",
            .Float => "f32",
            .Vector2 => "Vector2",
            .Vector3 => "Vector3",
            .Vector4 => "Vector4",
            else => "",
        };
    }

    pub fn prefixString(self: *DebugVariable) []const u8 {
        return switch (self.variable_type) {
            .Group => "// ",
            else => "pub const DEBUGUI_",
        };
    }
};

fn debugVariableToText(buffer: *[4096:0]u8, start_index: u32, variable: *DebugVariable, flags: u32) u32 {
    var len: u32 = start_index;

    if (flags & DebugVariableToTextFlag.Declaration.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], "{s}", .{variable.prefixString()}) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.Name.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(
            buffer[len..],
            "{s}",
            .{variable.name},
        ) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.Colon.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], ": ", .{}) catch "";
        len += @intCast(slice.len);
    }

    if (variable.variable_type != .Group and flags & DebugVariableToTextFlag.Type.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(
            buffer[len..],
            ": {s} = ",
            .{variable.typeString()},
        ) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.Declaration.toInt() != 0) {
        switch (variable.variable_type) {
            .Vector2, .Vector3, .Vector4 => {
                const slice = std.fmt.bufPrintZ(buffer[len..], "{s}.new", .{variable.typeString()}) catch "";
                len += @intCast(slice.len);
            },
            else => {},
        }
    }

    switch (variable.variable_type) {
        .Boolean => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "{s}",
                .{if (variable.data.bool_value) "true" else "false"},
            ) catch "";
            len += @intCast(slice.len);
        },
        .Int => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{d}", .{variable.data.int_value}) catch "";
            len += @intCast(slice.len);
        },
        .UInt => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{d}", .{variable.data.uint_value}) catch "";
            len += @intCast(slice.len);
        },
        .Float => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{d}", .{variable.data.float_value}) catch "";
            len += @intCast(slice.len);
        },
        .Vector2 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d})",
                .{ variable.data.vector2_value.x(), variable.data.vector2_value.y() },
            ) catch "";
            len += @intCast(slice.len);
        },
        .Vector3 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d}, {d})",
                .{ variable.data.vector3_value.x(), variable.data.vector3_value.y(), variable.data.vector3_value.z() },
            ) catch "";
            len += @intCast(slice.len);
        },
        .Vector4 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d}, {d}, {d})",
                .{
                    variable.data.vector4_value.x(),
                    variable.data.vector4_value.y(),
                    variable.data.vector4_value.z(),
                    variable.data.vector4_value.w(),
                },
            ) catch "";
            len += @intCast(slice.len);
        },
        .Group => {},
        .CounterThreadList => {},
        .BitmapDisplay => {},
    }

    if (variable.variable_type != .Group and flags & DebugVariableToTextFlag.SemiColonEnd.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], ";", .{}) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.LineFeedEnd.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], "\n", .{}) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.NullTerminator.toInt() != 0) {
        buffer[len] = 0;
        len += 1;
    }

    return len;
}

fn writeHandmadeConfig(debug_state: *DebugState) void {
    var buffer: [4096:0]u8 = undefined;
    var length: u32 = 0;
    var depth: u32 = 0;

    {
        const imports =
            \\const math = @import("math.zig");
            \\
            \\const Vector2 = math.Vector2;
            \\const Vector3 = math.Vector3;
            \\const Vector4 = math.Vector4;
            \\
            \\
        ;

        const slice = std.fmt.bufPrintZ(buffer[length..], "{s}", .{imports}) catch "";
        length += @intCast(slice.len);
    }

    if (debug_state.root_group) |root_group| {
        var opt_ref: ?*DebugTreeEntry = root_group.variable.data.group.first_child;

        while (opt_ref) |ref| {
            const variable: *DebugVariable = ref.variable;

            if (variable.shouldBeWritten()) {
                for (0..depth) |_| {
                    for (0..4) |_| {
                        buffer[length] = ' ';
                        length += 1;
                    }
                }

                length = debugVariableToText(&buffer, length, variable, DebugVariableToTextFlag.declarationFlags());
            }

            if (variable.variable_type == .Group) {
                opt_ref = variable.data.group.first_child;
                depth +%= 1;
            } else {
                while (opt_ref) |inner_ref| {
                    if (inner_ref.next != null) {
                        opt_ref = inner_ref.next;
                        break;
                    } else {
                        opt_ref = inner_ref.parent;
                        depth -%= 1;
                    }
                }
            }
        }

        _ = shared.platform.debugWriteEntireFile("../src/config.zig", length, &buffer);

        if (!debug_state.is_compiling) {
            debug_state.is_compiling = true;
            debug_state.compiler = shared.platform.debugExecuteSystemCommand(
                "../",
                "C:/Windows/System32/cmd.exe",
                "/C zig build -Dpackage=Library",
            );
        }
    }
}

fn drawProfileIn(debug_state: *DebugState, profile_rect: Rectangle2, mouse_position: Vector2) void {
    if (debug_state.render_group) |group| {
        group.pushRectangle2(profile_rect, 0, Color.new(0, 0, 0, 0.25));

        const bar_spacing: f32 = 4;
        var lane_height: f32 = 0;
        const lane_count: u32 = debug_state.frame_bar_lane_count;

        var max_frame: u32 = debug_state.frame_count;
        if (max_frame > 10) {
            max_frame = 10;
        }

        if (lane_count > 0 and max_frame > 0) {
            const pixels_per_frame: f32 = profile_rect.getDimension().y() / @as(f32, @floatFromInt(max_frame));
            lane_height = (pixels_per_frame - bar_spacing) / @as(f32, @floatFromInt(lane_count));
        }

        const bar_height: f32 = lane_height * @as(f32, @floatFromInt(lane_count));
        const bars_plus_spacing: f32 = bar_height + bar_spacing;
        const chart_left: f32 = profile_rect.min.x();
        // const chart_height: f32 = bars_plus_spacing * @as(f32, @floatFromInt(max_frame));
        const chart_width: f32 = profile_rect.getDimension().x();
        const chart_top: f32 = profile_rect.max.y();
        const scale: f32 = chart_width * debug_state.frame_bar_scale;

        const colors: [12]Color3 = .{
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
            Color3.new(0, 0.5, 1),
        };

        var frame_index: u32 = 0;
        while (frame_index < max_frame) : (frame_index += 1) {
            const frame: *DebugFrame = &debug_state.frames[debug_state.frame_count - (frame_index + 1)];

            const stack_x: f32 = chart_left;
            const stack_y: f32 = chart_top - bars_plus_spacing * @as(f32, (@floatFromInt(frame_index)));

            var region_index: u32 = 0;
            while (region_index < frame.region_count) : (region_index += 1) {
                const region: *const DebugFrameRegion = &frame.regions[region_index];

                const color = colors[region.color_index % colors.len];
                const this_min_x: f32 = stack_x + scale * region.min_t;
                const this_max_x: f32 = stack_x + scale * region.max_t;
                const lane: f32 = @as(f32, @floatFromInt(region.lane_index));

                const region_rect = math.Rectangle2.new(
                    this_min_x,
                    stack_y - lane_height * (lane + 1),
                    this_max_x,
                    stack_y - lane_height * lane,
                );

                group.pushRectangle2(region_rect, 0, color.toColor(1));

                if (mouse_position.isInRectangle(region_rect)) {
                    const record: *DebugRecord = region.record;

                    var buffer: [128]u8 = undefined;
                    const slice = std.fmt.bufPrintZ(&buffer, "{s}: {d:10}cy [{s}({d})]", .{
                        record.block_name,
                        region.cycle_count,
                        record.file_name,
                        record.line_number,
                    }) catch "";
                    textOutAt(slice, mouse_position.plus(Vector2.new(0, 10)), Color.white());

                    // hot_record = record;
                }
            }
        }

        // // 30 FPS line.
        // group.pushRectangle(
        //     Vector2.new(chart_width, 1),
        //     Vector3.new(chart_left + 0.5 * chart_width, chart_min_y + chart_height, 0),
        //     Color.white(),
        // );
        //
        // // 60 FPS line.
        // group.pushRectangle(
        //     Vector2.new(chart_width, 1),
        //     Vector3.new(chart_left + 0.5 * chart_width, chart_min_y + (chart_height * 0.5), 0),
        //     Color.new(0.5, 1, 0, 1),
        // );
    }
}

const Layout = struct {
    debug_state: *DebugState,
    mouse_position: Vector2,
    at: Vector2,
    depth: u32,
    line_advance: f32,
    spacing_y: f32,

    pub fn beginElementRectangle(self: *Layout, dimension: *Vector2) LayoutElement {
        const element: LayoutElement = .{
            .layout = self,
            .dimension = dimension,
        };
        return element;
    }
};

const LayoutElement = struct {
    layout: *Layout,
    dimension: *Vector2,
    size: ?*Vector2 = null,
    default_interaction: ?DebugInteraction = null,

    bounds: Rectangle2 = undefined,

    pub fn makeSizable(self: *LayoutElement) void {
        self.size = self.dimension;
    }

    pub fn defaultInteraction(self: *LayoutElement, interaction: DebugInteraction) void {
        self.default_interaction = interaction;
    }

    pub fn end(self: *LayoutElement) void {
        const debug_state: *DebugState = self.layout.debug_state;

        if (debug_state.render_group) |render_group| {
            const size_handle_pixels: f32 = 4;
            var frame: Vector2 = Vector2.new(0, 0);

            if (self.size != null) {
                frame = Vector2.splat(size_handle_pixels);
            }

            const total_dimension: Vector2 = self.dimension.plus(frame.scaledTo(2));

            const total_min_corner: Vector2 = Vector2.new(
                self.layout.at.x() + @as(f32, @floatFromInt(self.layout.depth)) * 2 * self.layout.line_advance,
                self.layout.at.y() - total_dimension.y(),
            );
            const total_max_corner: Vector2 = total_min_corner.plus(total_dimension);

            const interior_min_corner: Vector2 = total_min_corner.plus(frame);
            const interior_max_corner: Vector2 = interior_min_corner.plus(self.dimension.*);

            const total_bounds: Rectangle2 = Rectangle2.fromMinMax(total_min_corner, total_max_corner);
            self.bounds = Rectangle2.fromMinMax(interior_min_corner, interior_max_corner);

            if (self.default_interaction) |interaction| {
                if (interaction.interaction_type != .None and self.layout.mouse_position.isInRectangle(self.bounds)) {
                    debug_state.next_hot_interaction = interaction;
                }
            }

            if (self.size) |size| {
                render_group.pushRectangle2(
                    Rectangle2.fromMinMax(
                        Vector2.new(total_min_corner.x(), interior_min_corner.y()),
                        Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                    ), 0, Color.black(),
                );
                render_group.pushRectangle2(
                    Rectangle2.fromMinMax(
                        Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                        Vector2.new(total_max_corner.x(), total_max_corner.y()),
                    ), 0, Color.black(),
                );
                render_group.pushRectangle2(
                    Rectangle2.fromMinMax(
                        Vector2.new(interior_min_corner.x(), total_min_corner.y()),
                        Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                    ), 0, Color.black(),
                );
                render_group.pushRectangle2(
                    Rectangle2.fromMinMax(
                        Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                        Vector2.new(interior_max_corner.x(), total_max_corner.y()),
                    ), 0, Color.black(),
                );

                const size_interaction: DebugInteraction = DebugInteraction{
                    .interaction_type = .Resize,
                    .target = .{ .position = size },
                };

                const size_box: Rectangle2 = Rectangle2.fromMinMax(
                    Vector2.new(interior_max_corner.x(), total_min_corner.y()),
                    Vector2.new(total_max_corner.x(), interior_min_corner.y()),
                );
                const size_box_color: Color =
                    if (debug_state.interactionIsHot(&size_interaction)) Color.new(1, 1, 0, 1) else Color.white();
                render_group.pushRectangle2(size_box, 0, size_box_color);

                if (self.layout.mouse_position.isInRectangle(size_box)) {
                    debug_state.next_hot_interaction = size_interaction;
                }
            }

            const spacing_y: f32 = if (false) 0 else self.layout.spacing_y;
            _ = self.layout.at.setY(total_bounds.min.y() - spacing_y);
        }
    }
};


fn drawDebugMainMenu(debug_state: *DebugState, render_group: *render.RenderGroup, mouse_position: Vector2) void {
    var opt_tree: ?*DebugTree = debug_state.hierarchy_sentinel.next;

    if (debug_state.debug_font_info) |font_info| {
        while (opt_tree) |tree| : (opt_tree = tree.next) {
            if (tree == &debug_state.hierarchy_sentinel) {
                break;
            }

            var layout: Layout = .{
                .debug_state = debug_state,
                .mouse_position = mouse_position,
                .at = tree.ui_position,
                .depth = 0,
                .line_advance = font_info.getLineAdvance() * debug_state.font_scale,
                .spacing_y = 4,
            };

            if (tree.group) |hierarchy_group| {
                var opt_ref: ?*DebugTreeEntry = hierarchy_group.variable.data.group.first_child;

                while (opt_ref) |ref| {
                    const variable: *DebugVariable = ref.variable;
                    const item_interaction: DebugInteraction = DebugInteraction{
                        .interaction_type = .AutoModifyVariable,
                        .target = .{ .variable = variable },
                    };
                    const is_hot: bool = debug_state.interactionIsHot(&item_interaction);
                    const item_color: Color = if (is_hot) Color.new(1, 1, 0, 1) else Color.white();

                    switch (variable.variable_type) {
                        .CounterThreadList => {
                            var element: LayoutElement = layout.beginElementRectangle(&variable.data.profile.dimension);
                            element.makeSizable();
                            element.defaultInteraction(item_interaction);
                            element.end();

                            drawProfileIn(debug_state, element.bounds, mouse_position);
                        },
                        .BitmapDisplay => {
                            const bitmap_scale = variable.data.bitmap_display.dimension.y();
                            if (render_group.assets.getBitmap(variable.data.bitmap_display.id, render_group.generation_id)) |bitmap| {
                                var dim = render_group.getBitmapDim(bitmap, bitmap_scale, Vector3.zero(), 0);
                                _ = variable.data.bitmap_display.dimension.setX(dim.size.x());
                            }

                            const tear_interaction: DebugInteraction = .{
                                .interaction_type = .TearValue,
                                .target = .{ .variable = variable },
                            };

                            var element: LayoutElement = layout.beginElementRectangle(&variable.data.bitmap_display.dimension);
                            element.makeSizable();
                            element.defaultInteraction(tear_interaction);
                            element.end();

                            render_group.pushRectangle2(element.bounds, 0, Color.black());
                            render_group.pushBitmapId(
                                variable.data.bitmap_display.id,
                                bitmap_scale,
                                element.bounds.min.toVector3(0),
                                Color.white(),
                                0,
                            );
                        },
                        else => {
                            var text: [4096:0]u8 = undefined;
                            var len: u32 = 0;
                            len = debugVariableToText(&text, len, variable, DebugVariableToTextFlag.displayFlags());

                            const text_bounds = getTextSize(debug_state, &text);
                            var dim: Vector2 = Vector2.new(text_bounds.getDimension().x(), layout.line_advance);

                            var element: LayoutElement = layout.beginElementRectangle(&dim);
                            element.defaultInteraction(item_interaction);
                            element.end();

                            const text_position: Vector2 = Vector2.new(
                                element.bounds.min.x(),
                                element.bounds.max.y() - debug_state.font_scale * font_info.getStartingBaselineY(),
                            );
                            textOutAt(&text, text_position, item_color);
                        },
                    }

                    if (variable.variable_type == .Group and variable.data.group.expanded) {
                        opt_ref = variable.data.group.first_child;
                        layout.depth +%= 1;
                    } else {
                        while (opt_ref) |inner_variable| {
                            if (inner_variable.next != null) {
                                opt_ref = inner_variable.next;
                                break;
                            } else {
                                opt_ref = inner_variable.parent;
                                layout.depth -%= 1;
                            }
                        }
                    }
                }
            }

            debug_state.at_y = layout.at.y();

            if (true) {
                const move_interaction: DebugInteraction = DebugInteraction{
                    .interaction_type = .Move,
                    .target = .{ .position = &tree.ui_position },
                };
                const move_box_color: Color =
                    if (debug_state.interactionIsHot(&move_interaction)) Color.new(1, 1, 0, 1) else Color.white();
                const move_box: Rectangle2 = Rectangle2.fromCenterHalfDimension(
                    tree.ui_position.minus(Vector2.new(4, 4)),
                    Vector2.new(4, 4),
                );
                render_group.pushRectangle2(move_box, 0, move_box_color);

                if (mouse_position.isInRectangle(move_box)) {
                    debug_state.next_hot_interaction = move_interaction;
                }
            }
        }
    }

    // var new_hot_menu_index: u32 = debug_variable_list.len;
    // var best_distance_sq: f32 = std.math.floatMax(f32);
    //
    // const menu_radius: f32 = 400;
    // const angle_step: f32 = shared.TAU32 / @as(f32, @floatFromInt(debug_variable_list.len));
    // for (debug_variable_list, 0..) |variable, index| {
    //     const text = variable.name;
    //
    //     var item_color = if (variable.value) Color.white() else Color.new(0.5, 0.5, 0.5, 1);
    //     if (index == debug_state.hot_menu_index) {
    //         item_color = Color.new(1, 1, 0, 1);
    //     }
    //
    //     const angle: f32 = @as(f32, @floatFromInt(index)) * angle_step;
    //     const text_position: Vector2 = debug_state.menu_position.plus(Vector2.arm2(angle).scaledTo(menu_radius));
    //
    //     const this_distance_sq: f32 = text_position.minus(mouse_position).lengthSquared();
    //     if (best_distance_sq > this_distance_sq) {
    //         new_hot_menu_index = @intCast(index);
    //         best_distance_sq = this_distance_sq;
    //     }
    //
    //     const text_bounds: Rectangle2 = getTextSize(debug_state, text);
    //     textOutAt(text, text_position.minus(text_bounds.getDimension().scaledTo(0.5)), item_color);
    // }
    //
    // if (mouse_position.minus(debug_state.menu_position).lengthSquared() > math.square(menu_radius)) {
    //     debug_state.hot_menu_index = new_hot_menu_index;
    // } else {
    //     debug_state.hot_menu_index = debug_variable_list.len;
    // }
}

fn beginInteract(debug_state: *DebugState, input: *const shared.GameInput, mouse_position: Vector2, alt_ui: bool) void {
    _ = input;

    if (debug_state.hot_interaction.interaction_type != .None) {
        if (debug_state.hot_interaction.interaction_type == .AutoModifyVariable) {
            switch (debug_state.hot_interaction.target.variable.variable_type) {
                .Boolean => {
                    debug_state.hot_interaction.interaction_type = .ToggleValue;
                },
                .Float => {
                    debug_state.hot_interaction.interaction_type = .DragValue;
                },
                .Group => {
                    debug_state.hot_interaction.interaction_type = .ToggleValue;
                },
                else => {},
            }

            if (alt_ui) {
                debug_state.hot_interaction.interaction_type = .TearValue;
            }
        }

        switch (debug_state.hot_interaction.interaction_type) {
            .TearValue => {
                const root_group: *DebugTreeEntry = debug_variables.addRootGroup(debug_state, "NewUserGroup");
                _ = debug_variables.addVariableToGroup(debug_state, root_group, debug_state.hot_interaction.target.variable);
                const tree = debug_state.addTree(root_group, Vector2.zero());
                tree.ui_position = mouse_position;
                debug_state.hot_interaction.interaction_type = .Move;
                debug_state.hot_interaction.target = .{ .position = &tree.ui_position };
            },
            else => {},
        }

        debug_state.interaction = debug_state.hot_interaction;
    } else {
        debug_state.interaction.interaction_type = .NoOp;
    }
}

fn interact(debug_state: *DebugState, input: *const shared.GameInput, mouse_position: Vector2) void {
    const mouse_delta = mouse_position.minus(debug_state.last_mouse_position);
    // if (input.mouse_buttons[shared.GameInputMouseButton.Right.toInt()].ended_down) {
    //     if (input.mouse_buttons[shared.GameInputMouseButton.Right.toInt()].half_transitions > 0) {
    //         debug_state.menu_position = mouse_position;
    //     }
    //     drawDebugMainMenu(debug_state, group, mouse_position);
    // } else if (input.mouse_buttons[shared.GameInputMouseButton.Right.toInt()].half_transitions > 0) {
    //     drawDebugMainMenu(debug_state, group, mouse_position);
    //
    //     if (debug_state.hot_menu_index < debug_variable_list.len) {
    //         debug_variable_list[debug_state.hot_menu_index].value =
    //             !debug_variable_list[debug_state.hot_menu_index].value;
    //     }
    //     writeHandmadeConfig(debug_state);
    // }

    if (debug_state.interaction.interaction_type != .None) {

        // Mouse move interaction.
        switch (debug_state.interaction.interaction_type) {
            .DragValue => {
                const variable = debug_state.interaction.target.variable;
                switch (variable.variable_type) {
                    .Float => {
                        variable.data.float_value += 0.1 * mouse_delta.y();
                    },
                    else => {},
                }
            },
            .Resize => {
                var position = debug_state.interaction.target.position;
                const flipped_delta: Vector2 = Vector2.new(mouse_delta.x(), -mouse_delta.y());
                position.* = position.plus(flipped_delta);
                _ = position.setX(@max(position.x(), 10));
                _ = position.setY(@max(position.y(), 10));
            },
            .Move => {
                var position = debug_state.interaction.target.position;
                position.* = position.plus(mouse_delta);
            },
            else => {},
        }

        // Click interaction.
        const alt_ui: bool = input.mouse_buttons[shared.GameInputMouseButton.Right.toInt()].ended_down;
        var transition_index: u32 = input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].half_transitions;
        while (transition_index > 1) : (transition_index -= 1) {
            endInteract(debug_state, input, mouse_position);
            beginInteract(debug_state, input, mouse_position, alt_ui);
        }

        if (!input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].ended_down) {
            endInteract(debug_state, input, mouse_position);
        }
    } else {
        debug_state.hot_interaction = debug_state.next_hot_interaction;

        const alt_ui: bool = input.mouse_buttons[shared.GameInputMouseButton.Right.toInt()].ended_down;
        var transition_index: u32 = input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].half_transitions;
        while (transition_index > 1) : (transition_index -= 1) {
            beginInteract(debug_state, input, mouse_position, alt_ui);
            endInteract(debug_state, input, mouse_position);
        }

        if (input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].ended_down) {
            beginInteract(debug_state, input, mouse_position, alt_ui);
        }
    }

    debug_state.last_mouse_position = mouse_position;
}

fn endInteract(debug_state: *DebugState, input: *const shared.GameInput, mouse_position: Vector2) void {
    _ = input;
    _ = mouse_position;

    switch (debug_state.interaction.interaction_type) {
        .ToggleValue => {
            std.debug.assert(debug_state.interaction.target == .variable);

            const variable = debug_state.interaction.target.variable;
            switch (variable.variable_type) {
                .Boolean => {
                    variable.data.bool_value = !variable.data.bool_value;
                },
                .Group => {
                    variable.data.group.expanded = !variable.data.group.expanded;
                },
                else => {},
            }
        },
        else => {},
    }

    writeHandmadeConfig(debug_state);

    debug_state.interaction.interaction_type = .None;
    debug_state.interaction.target = .{ .tree = null };
}

pub fn textOutAt(text: [:0]const u8, position: Vector2, color: Color) void {
    if (DebugState.get()) |debug_state| {
        _ = textOp(debug_state, .DrawText, text, position, color);
    }
}

pub fn getTextSize(debug_state: *DebugState, text: [:0]const u8) Rectangle2 {
    return textOp(debug_state, .SizeText, text, Vector2.zero(), Color.white());
}

pub fn textOp(
    debug_state: *DebugState,
    op: DebugTextOp,
    text: [:0]const u8,
    position: Vector2,
    color_in: Color,
) Rectangle2 {
    var result: Rectangle2 = Rectangle2.invertedInfinity();
    var rect_found = false;
    var color = color_in;

    if (debug_state.render_group) |render_group| {
        if (debug_state.debug_font) |font| {
            if (debug_state.debug_font_info) |font_info| {
                var match_vector = asset.AssetVector{};
                var prev_code_point: u32 = 0;
                var char_scale = debug_state.font_scale;
                var x: f32 = position.x();

                var at: [*]const u8 = @ptrCast(text);
                while (at[0] != 0) {
                    if (at[0] == '\\' and
                        at[1] == '#' and
                        at[2] != 0 and
                        at[3] != 0 and
                        at[4] != 0)
                    {
                        const c_scale: f32 = 1.0 / 9.0;
                        color = Color.new(
                            math.clampf01(c_scale * @as(f32, @floatFromInt(at[2] - '0'))),
                            math.clampf01(c_scale * @as(f32, @floatFromInt(at[3] - '0'))),
                            math.clampf01(c_scale * @as(f32, @floatFromInt(at[4] - '0'))),
                            1,
                        );

                        at += 5;
                    } else if (at[0] == '\\' and
                        at[1] == '^' and
                        at[2] != 0)
                    {
                        const c_scale: f32 = 1.0 / 9.0;
                        char_scale = debug_state.font_scale * math.clampf01(c_scale * @as(f32, @floatFromInt(at[2] - '0')));
                        at += 3;
                    } else {
                        var code_point: u32 = at[0];

                        if (at[0] == '\\' and
                            (isHex(at[1])) and
                            (isHex(at[2])) and
                            (isHex(at[3])) and
                            (isHex(at[4])))
                        {
                            code_point = ((getHex(at[1]) << 12) |
                                (getHex(at[2]) << 8) |
                                (getHex(at[3]) << 4) |
                                (getHex(at[4]) << 0));

                            at += 4;
                        }

                        const advance_x: f32 = char_scale * font.getHorizontalAdvanceForPair(font_info, prev_code_point, code_point);
                        x += advance_x;

                        if (code_point != ' ') {
                            match_vector.e[@intFromEnum(asset.AssetTagId.UnicodeCodepoint)] = @floatFromInt(code_point);
                            if (font.getBitmapForGlyph(font_info, render_group.assets, code_point)) |bitmap_id| {
                                const info = render_group.assets.getBitmapInfo(bitmap_id);
                                const bitmap_scale = char_scale * @as(f32, @floatFromInt(info.dim[1]));
                                const bitamp_offset: Vector3 = Vector3.new(x, position.y(), 0);

                                if (op == .DrawText) {
                                    render_group.pushBitmapId(bitmap_id, bitmap_scale, bitamp_offset, color, null);
                                } else {
                                    std.debug.assert(op == .SizeText);

                                    if (render_group.assets.getBitmap(bitmap_id, render_group.generation_id)) |bitmap| {
                                        const dim = render_group.getBitmapDim(bitmap, bitmap_scale, bitamp_offset, 1);
                                        var glyph_dim: Rectangle2 = Rectangle2.fromMinDimension(dim.position.xy(), dim.size);
                                        result = result.getUnionWith(&glyph_dim);
                                        rect_found = true;
                                    }
                                }
                            }
                        }

                        prev_code_point = code_point;

                        at += 1;
                    }
                }
            }
        }
    }

    if (!rect_found) {
        result = Rectangle2.zero();
    }

    return result;
}

pub fn textLine(text: [:0]const u8) void {
    if (DebugState.get()) |debug_state| {
        if (debug_state.debug_font_info) |font_info| {
            const position = Vector2.new(
                debug_state.left_edge,
                debug_state.at_y - debug_state.font_scale * font_info.getStartingBaselineY(),
            );
            textOutAt(text, position, Color.white());
            debug_state.at_y -= font_info.getLineAdvance() * debug_state.font_scale;
        }
    }
}

fn isHex(char: u8) bool {
    return (char >= '0' and char <= '9') or (char >= 'A' and char <= 'F');
}

fn getHex(char: u8) u32 {
    var result: u32 = 0;

    if (char >= '0' and char <= '9') {
        result = char - '0';
    } else if (char >= 'A' and char <= 'F') {
        result = 0xA + (char - 'A');
    }

    return result;
}

fn getRecordFrom(opt_block: ?*OpenDebugBlock) ?*DebugRecord {
    var result: ?*DebugRecord = null;

    if (opt_block) |block| {
        result = block.source;
    }

    return result;
}

fn debugStart(debug_state: *DebugState, assets: *asset.Assets, width: i32, height: i32) void {
    var timed_block = TimedBlock.beginFunction(@src(), .DebugStart);
    defer timed_block.end();

    if (shared.debug_global_memory) |memory| {
        if (!debug_state.initialized) {
            debug_state.high_priority_queue = memory.high_priority_queue;

            debug_state.hierarchy_sentinel.next = &debug_state.hierarchy_sentinel;
            debug_state.hierarchy_sentinel.prev = &debug_state.hierarchy_sentinel;
            debug_state.hierarchy_sentinel.group = null;

            debug_state.debug_arena.initialize(
                memory.debug_storage_size - @sizeOf(DebugState),
                memory.debug_storage.? + @sizeOf(DebugState),
            );

            var context: debug_variables.DebugVariableDefinitionContext = .{
                .state = debug_state,
                .arena = &debug_state.debug_arena,
                .group = null,
            };
            context.group = debug_variables.beginVariableGroup(&context, "Root");

            _ = debug_variables.beginVariableGroup(&context, "Debugging");

            debug_variables.createDebugVariables(&context);

            _ = debug_variables.beginVariableGroup(&context, "Profile");
            {
                _ = debug_variables.beginVariableGroup(&context, "By Thread");
                var thread_list = debug_variables.addDebugVariable(&context, .CounterThreadList, "");
                thread_list.variable.data = .{ .profile = .{ .dimension = Vector2.new(1024, 100) } };
                debug_variables.endVariableGroup(&context);

                _ = debug_variables.beginVariableGroup(&context, "By Function");
                var function_list = debug_variables.addDebugVariable(&context, .CounterThreadList, "");
                function_list.variable.data = .{ .profile = .{ .dimension = Vector2.new(1024, 200) } };
                debug_variables.endVariableGroup(&context);
            }
            debug_variables.endVariableGroup(&context);

            var match_vector = asset.AssetVector{};
            match_vector.e[file_formats.AssetTagId.FacingDirection.toInt()] = 0;
            var weight_vector = asset.AssetVector{};
            weight_vector.e[file_formats.AssetTagId.FacingDirection.toInt()] = 1;
            if (assets.getBestMatchBitmap(.Head, &match_vector, &weight_vector)) |id| {
                _ = debug_variables.addDebugVariableBitmap(&context, "Test Bitmap", id);
            }

            debug_variables.endVariableGroup(&context);

            debug_state.root_group = context.group;

            debug_state.render_group =
                render.RenderGroup.allocate(assets, &debug_state.debug_arena, shared.megabytes(16), false);

            debug_state.paused = false;
            debug_state.scope_to_record = null;
            debug_state.initialized = true;

            debug_state.debug_arena.makeSubArena(&debug_state.collate_arena, shared.megabytes(32), 4);
            debug_state.collate_temp = debug_state.collate_arena.beginTemporaryMemory();

            debug_state.restartCollation(0);

            _ = debug_state.addTree(
                debug_state.root_group.?,
                Vector2.new(-0.5 * @as(f32, @floatFromInt(width)), 0.5 * @as(f32, @floatFromInt(height))),
            );
        }

        if (debug_state.render_group) |group| {
            group.beginRender();
            if (group.pushFont(debug_state.font_id)) |font| {
                debug_state.debug_font = font;
                debug_state.debug_font_info = group.assets.getFontInfo(debug_state.font_id);
            }
        }

        debug_state.global_width = @floatFromInt(width);
        debug_state.global_height = @floatFromInt(height);

        var match_vector = asset.AssetVector{};
        var weight_vector = asset.AssetVector{};
        match_vector.e[asset.AssetTagId.FontType.toInt()] = @intFromEnum(file_formats.AssetFontType.Debug);
        weight_vector.e[asset.AssetTagId.FontType.toInt()] = 1;
        if (assets.getBestMatchFont(.Font, &match_vector, &weight_vector)) |id| {
            debug_state.font_id = id;
        }

        debug_state.font_scale = 1;
        debug_state.at_y = 0.5 * @as(f32, @floatFromInt(height));
        debug_state.left_edge = -0.5 * @as(f32, @floatFromInt(width));
        debug_state.right_edge = 0.5 * @as(f32, @floatFromInt(width));

        if (debug_state.render_group) |group| {
            group.orthographicMode(width, height, 1);
        }
    }
}

fn debugEnd(debug_state: *DebugState, input: *const shared.GameInput, draw_buffer: *asset.LoadedBitmap) void {
    var overlay_timed_block = shared.TimedBlock.beginBlock(@src(), .DebugEnd);
    defer overlay_timed_block.end();

    if (debug_state.render_group) |group| {
        const mouse_position = Vector2.new(input.mouse_x, input.mouse_y);
        shared.zeroStruct(DebugInteraction, &debug_state.next_hot_interaction);

        drawDebugMainMenu(debug_state, group, mouse_position);
        interact(debug_state, input, mouse_position);

        if (debug_state.is_compiling) {
            const state = shared.platform.debugGetProcessState(debug_state.compiler);
            if (state.is_running) {
                textLine("COMPILING");
            } else {
                debug_state.is_compiling = false;
            }
        }

        if (false) {
            var counter_index: u32 = 0;
            while (counter_index < debug_state.counter_count) : (counter_index += 1) {
                const counter = debug_state.counter_states[counter_index];

                var hit_count = DebugStatistic.begin();
                var cycle_count = DebugStatistic.begin();
                var cycle_over_hit = DebugStatistic.begin();
                for (counter.snapshots) |snapshot| {
                    hit_count.accumulate(@floatFromInt(snapshot.hit_count));
                    cycle_count.accumulate(@floatFromInt(snapshot.cycle_count));

                    var coh: f64 = 0;
                    if (snapshot.hit_count > 0) {
                        coh = @as(f64, @floatFromInt(snapshot.cycle_count)) / @as(f64, @floatFromInt(snapshot.hit_count));
                    }
                    cycle_over_hit.accumulate(coh);
                }
                hit_count.end();
                cycle_count.end();
                cycle_over_hit.end();

                if (counter.block_name) |block_name| {
                    if (cycle_count.max > 0) {
                        const bar_width: f32 = 4;
                        const chart_left: f32 = 0;
                        const chart_min_y: f32 = debug_state.at_y;
                        const char_height: f32 = debug_state.debug_font_info.ascender_height * debug_state.font_scale;
                        const scale: f32 = 1 / @as(f32, @floatCast(cycle_count.max));
                        for (counter.snapshots, 0..) |snapshot, snapshot_index| {
                            const this_proportion: f32 = scale * @as(f32, @floatFromInt(snapshot.cycle_count));
                            const this_height: f32 = char_height * this_proportion;
                            group.pushRectangle(
                                Vector2.new(bar_width, this_height),
                                Vector3.new(
                                    chart_left + bar_width * @as(f32, (@floatFromInt(snapshot_index))) - 0.5 * bar_width,
                                    chart_min_y + 0.5 * this_height,
                                    0,
                                ),
                                Color.new(this_proportion, 1, 0, 1),
                            );
                        }
                    }

                    var buffer: [128]u8 = undefined;
                    const slice = std.fmt.bufPrintZ(&buffer, "{s:32}({d:4}): {d:10}cy, {d:8}h, {d:10}cy/h", .{
                        block_name,
                        counter.line_number,
                        @as(u64, @intFromFloat(cycle_count.average)),
                        @as(u64, @intFromFloat(hit_count.average)),
                        @as(u64, @intFromFloat(cycle_over_hit.average)),
                    }) catch "";
                    textLine(slice);
                }
            }
        }

        if (debug_state.frame_count > 0) {
            var buffer: [128]u8 = undefined;
            const slice = std.fmt.bufPrintZ(&buffer, "Last frame time: {d:0.2}ms", .{
                debug_state.frames[debug_state.frame_count - 1].wall_seconds_elapsed * 1000,
            }) catch "";
            textLine(slice);
        }

        // if (input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].wasPressed()) {
        //     if (hot_record) |record| {
        //         debug_state.scope_to_record = record;
        //     } else {
        //         debug_state.scope_to_record = null;
        //     }
        //
        //     debug_state.refreshCollation();
        // }

        group.tiledRenderTo(debug_state.high_priority_queue, draw_buffer);
        group.endRender();
    }
}

fn getGameAssets(memory: *shared.Memory) ?*asset.Assets {
    var assets: ?*asset.Assets = null;
    const transient_state: *shared.TransientState = @ptrCast(@alignCast(memory.transient_storage));

    if (transient_state.is_initialized) {
        assets = transient_state.assets;
    }

    return assets;
}

pub fn frameEnd(memory: *shared.Memory, input: shared.GameInput, buffer: *shared.OffscreenBuffer) callconv(.C) *shared.DebugTable {
    global_debug_table.current_event_array_index += 1;
    if (global_debug_table.current_event_array_index >= global_debug_table.events.len) {
        global_debug_table.current_event_array_index = 0;
    }

    const next_event_array_index: u64 = @as(u64, @intCast(global_debug_table.current_event_array_index)) << 32;
    const event_array_index_event_index: u64 =
        @atomicRmw(u64, &global_debug_table.event_array_index_event_index, .Xchg, next_event_array_index, .seq_cst);

    const event_array_index: u32 = @intCast(event_array_index_event_index >> 32);
    const event_count: u32 = @intCast(event_array_index_event_index & 0xffffffff);
    global_debug_table.event_count[event_array_index] = event_count;

    if (memory.debug_storage) |debug_storage| {
        const debug_state: *DebugState = @ptrCast(@alignCast(debug_storage));

        if (getGameAssets(memory)) |assets| {
            debugStart(debug_state, assets, buffer.width, buffer.height);

            if (memory.executable_reloaded) {
                debug_state.restartCollation(global_debug_table.current_event_array_index);
            }

            if (!debug_state.paused) {
                if (debug_state.frame_count >= shared.MAX_DEBUG_EVENT_ARRAY_COUNT * 4) {
                    debug_state.restartCollation(global_debug_table.current_event_array_index);
                }

                debug_state.collateDebugRecords(global_debug_table.current_event_array_index);
            }

            var draw_buffer_: asset.LoadedBitmap = .{
                .width = shared.safeTruncateToUInt16(buffer.width),
                .height = shared.safeTruncateToUInt16(buffer.height),
                .pitch = @intCast(buffer.pitch),
                .memory = @ptrCast(buffer.memory),
            };
            const draw_buffer = &draw_buffer_;
            debugEnd(debug_state, &input, draw_buffer);
        }
    }

    return &global_debug_table;
}
