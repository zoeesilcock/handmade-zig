const shared = @import("shared.zig");
const asset = @import("asset.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const config = @import("config.zig");
const sim = @import("sim.zig");
const file_formats = @import("file_formats");
const debug_interface = @import("debug_interface.zig");
const meta = @import("meta.zig");
const generated = @import("generated.zig");
const std = @import("std");

// Types.
const TimedBlock = debug_interface.TimedBlock;
const DebugType = debug_interface.DebugType;
const DebugEvent = debug_interface.DebugEvent;
const DebugId = debug_interface.DebugId;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const ArenaPushParams = shared.ArenaPushParams;
const ObjectTransform = render.ObjectTransform;

pub var global_debug_table: debug_interface.DebugTable = debug_interface.DebugTable{};

const COUNTER_COUNT = 512;
pub const MAX_VARIABLE_STACK_DEPTH = 64;

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
    next: ?*DebugFrame,

    begin_clock: u64,
    end_clock: u64,
    wall_seconds_elapsed: f32,

    frame_bar_scale: f32,

    frame_index: u32,
};

const DebugFrameRegion = struct {
    event: *DebugEvent,
    cycle_count: u64,
    lane_index: u16,
    color_index: u16,
    min_t: f32,
    max_t: f32,
};

const OpenDebugBlock = struct {
    parent: ?*OpenDebugBlock,
    next_free: ?*OpenDebugBlock,

    staring_frame_index: u32,
    opening_event: *DebugEvent,
    element: ?*DebugElement,
    group: ?*DebugVariableGroup,
};

const DebugThread = struct {
    id: u32,
    lane_index: u32,
    first_open_code_block: ?*OpenDebugBlock,
    first_open_data_block: ?*OpenDebugBlock,
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
    Move,
    Select,
    ToggleExpansion,
};

const DebugInteractionTargetType = enum(u32) {
    event,
    tree,
    position,
};

const DebugInteraction = struct {
    id: DebugId = undefined,
    interaction_type: DebugInteractionType,

    target: union(DebugInteractionTargetType) {
        event: ?*DebugEvent,
        tree: ?*DebugTree,
        position: *Vector2,
    },

    pub fn equals(self: *const DebugInteraction, other: *const DebugInteraction) bool {
        return self.id.equals(other.id) and
            self.interaction_type == other.interaction_type and std.meta.eql(self.target, other.target);
    }

    pub fn eventInteraction(
        debug_state: *DebugState,
        debug_id: DebugId,
        event: *DebugEvent,
        interaction_type: DebugInteractionType,
    ) DebugInteraction {
        _ = debug_state;
        return DebugInteraction{
            .id = debug_id,
            .interaction_type = interaction_type,
            .target = .{
                .event = event,
            },
        };
    }

    pub fn fromId(id: DebugId, interaction_type: DebugInteractionType) DebugInteraction {
        return DebugInteraction{
            .id = id,
            .interaction_type = interaction_type,
            .target = undefined,
        };
    }
};

pub const DebugState = struct {
    initialized: bool,

    high_priority_queue: *shared.PlatformWorkQueue,
    debug_arena: shared.MemoryArena,
    per_frame_arena: shared.MemoryArena,

    render_group: ?*render.RenderGroup = null,
    debug_font: ?*asset.LoadedFont,
    debug_font_info: ?*file_formats.HHAFont,

    is_compiling: bool = false,
    compiler: shared.DebugExecutingProcess,

    menu_position: Vector2,
    menu_active: bool,

    selected_id_count: u32,
    selected_id: [64]DebugId = [1]DebugId{undefined} ** 64,

    element_hash: [1024]?*DebugElement = [1]?*DebugElement{null} ** 1024,
    view_hash: [4096]*DebugView = [1]*DebugView{undefined} ** 4096,
    root_group: *DebugVariableGroup,
    tree_sentinel: DebugTree,

    last_mouse_position: Vector2,
    interaction: DebugInteraction,
    hot_interaction: DebugInteraction,
    next_hot_interaction: DebugInteraction,
    paused: bool,

    left_edge: f32 = 0,
    right_edge: f32 = 0,
    at_y: f32 = 0,
    font_scale: f32 = 0,
    font_id: file_formats.FontId = undefined,
    global_width: f32 = 0,
    global_height: f32 = 0,

    scope_to_record: ?[*:0]const u8,

    total_frame_count: u32,
    frame_count: u32,
    oldest_frame: ?*DebugFrame,
    most_recent_frame: ?*DebugFrame,

    collation_frame: ?*DebugFrame,

    frame_bar_lane_count: u32,
    first_thread: ?*DebugThread,
    first_free_thread: ?*DebugThread,
    first_free_block: ?*OpenDebugBlock,

    // Per-frame storage management.
    first_free_stored_event: ?*DebugStoredEvent,
    first_free_frame: ?*DebugFrame,

    pub fn get() ?*DebugState {
        var result: ?*DebugState = null;

        if (shared.debug_global_memory) |memory| {
            result = @ptrCast(@alignCast(memory.debug_storage));

            if (!result.?.initialized) {
                result = null;
            }
        }

        return result;
    }

    fn newFrame(self: *DebugState, begin_clock: u64) *DebugFrame {
        var result: ?*DebugFrame = null;

        while (result == null) {
            result = self.first_free_frame;
            if (result != null) {
                self.first_free_frame = result.?.next;
            } else {
                if (self.per_frame_arena.hasRoomFor(@sizeOf(DebugFrame), null)) {
                    result = self.per_frame_arena.pushStruct(DebugFrame, null);
                } else {
                    std.debug.assert(self.oldest_frame != null);
                    self.freeOldestFrame();
                }
            }
        }

        shared.zeroStruct(DebugFrame, result.?);

        result.?.frame_index = self.total_frame_count;
        self.total_frame_count += 1;
        result.?.frame_bar_scale = 1;
        result.?.begin_clock = begin_clock;

        return result.?;
    }

    fn freeFrame(self: *DebugState, opt_frame: ?*DebugFrame) void {
        if (opt_frame) |frame| {
            var element_hash_index: u32 = 0;
            while (element_hash_index < self.element_hash.len) : (element_hash_index += 1) {
                var opt_element = self.element_hash[element_hash_index];
                while (opt_element) |element| : (opt_element = element.next_in_hash) {
                    while (element.oldest_event) |oldest_event| {
                        if (oldest_event.frame_index <= frame.frame_index) {
                            if (element.oldest_event) |free_event| {
                                element.oldest_event = free_event.next;

                                if (element.most_recent_event == free_event) {
                                    std.debug.assert(free_event.next == null);
                                    element.most_recent_event = null;
                                }

                                free_event.next = self.first_free_stored_event;
                                self.first_free_stored_event = free_event;
                            }
                        }
                    }
                }
            }

            frame.next = self.first_free_frame;
            self.first_free_frame = frame;
        }
    }

    fn freeOldestFrame(self: *DebugState) void {
        if (self.oldest_frame) |oldest_frame| {
            self.oldest_frame = oldest_frame.next;

            if (self.most_recent_frame == oldest_frame) {
                std.debug.assert(oldest_frame.next == null);
                self.most_recent_frame = null;
            }

            self.freeFrame(oldest_frame);
        }
    }

    fn storeEvent(self: *DebugState, element: *DebugElement, event: *DebugEvent) *DebugStoredEvent {
        var result: ?*DebugStoredEvent = null;

        while (result == null) {
            result = self.first_free_stored_event;
            if (result != null) {
                self.first_free_stored_event = result.?.next;
            } else {
                if (self.per_frame_arena.hasRoomFor(@sizeOf(DebugStoredEvent), null)) {
                    result = self.per_frame_arena.pushStruct(
                        DebugStoredEvent,
                        ArenaPushParams.aligned(@alignOf(DebugStoredEvent), true),
                    );
                } else {
                    std.debug.assert(self.oldest_frame != null);
                    self.freeOldestFrame();
                }
            }
        }

        result.?.next = null;
        result.?.frame_index = self.collation_frame.?.frame_index;
        result.?.event = event.*;

        if (element.most_recent_event != null) {
            element.most_recent_event.?.next = result;
            element.most_recent_event = result;
        } else {
            element.oldest_event = result;
            element.most_recent_event = result;
        }

        return result.?;
    }

    fn allocateOpenDebugBlock(
        self: *DebugState,
        element: *DebugElement,
        frame_index: u32,
        event: *DebugEvent,
        first_open_block: *?*OpenDebugBlock,
    ) *OpenDebugBlock {
        var result: ?*OpenDebugBlock = self.first_free_block;
        if (result) |block| {
            self.first_free_block = block.next_free;
        } else {
            result = self.debug_arena.pushStruct(OpenDebugBlock, null);
        }

        result.?.staring_frame_index = frame_index;
        result.?.opening_event = event;
        result.?.element = element;
        result.?.next_free = null;

        result.?.parent = first_open_block.*;
        first_open_block.* = result;

        return result.?;
    }

    fn deallocateOpenDebugBlock(self: *DebugState, first_open_block: *?*OpenDebugBlock) void {
        const free_block: ?*OpenDebugBlock = first_open_block.*;
        first_open_block.* = free_block.?.parent;

        free_block.?.next_free = self.first_free_block;
        self.first_free_block = free_block;
    }

    fn getOrCreateGroupWithName(self: *DebugState, parent: *DebugVariableGroup, name_length: u32, name: [*:0]const u8) ?*DebugVariableGroup {
        var result: ?*DebugVariableGroup = null;
        var link: *DebugVariableLink = parent.sentinel.next;
        while (link != &parent.sentinel) : (link = link.next) {
            if (link.children != null and shared.stringsWithLengthAreEqual(link.children.?.name, link.children.?.name_length, name, name_length)) {
                result = link.children;
            }
        }

        if (result == null) {
            result = self.createVariableGroup(name_length, name);
            _ = self.addGroupToGroup(parent, result.?);
        }

        return result;
    }

    fn getGroupForHierarchicalName(
        self: *DebugState,
        parent: *DebugVariableGroup,
        name: [*:0]const u8,
    ) ?*DebugVariableGroup {
        var result: ?*DebugVariableGroup = parent;
        var first_underscore: ?[*]const u8 = null;
        var opt_scan: ?[*]const u8 = @ptrCast(name);
        while (opt_scan) |scan| : (opt_scan = scan + 1) {
            if (scan[0] == 0) {
                break;
            }

            if (scan[0] == '_') {
                first_underscore = scan;
                break;
            }
        }

        if (first_underscore != null) {
            const sub_name_length: u32 = @intCast(@intFromPtr(first_underscore.?) - @intFromPtr(name));
            const sub_name: [*:0]const u8 = @ptrCast(first_underscore.? + 1);
            if (self.getOrCreateGroupWithName(parent, sub_name_length, name)) |sub_group| {
                result = self.getGroupForHierarchicalName(sub_group, sub_name);
            }
        }

        return result;
    }

    fn freeVariableGroup(self: *DebugState, group: ?*DebugVariableGroup) void {
        _ = self;
        _ = group;

        // Not defined.
        unreachable;
    }

    fn createVariableGroup(self: *DebugState, name_length: u32, name: [*:0]const u8) *DebugVariableGroup {
        var group: *DebugVariableGroup = self.debug_arena.pushStruct(DebugVariableGroup, null);
        group.sentinel.next = &group.sentinel;
        group.sentinel.prev = &group.sentinel;
        group.name = name;
        group.name_length = name_length;

        return group;
    }

    pub fn addElementToGroup(
        self: *DebugState,
        parent: *DebugVariableGroup,
        element: *DebugElement,
    ) *DebugVariableLink {
        const link: *DebugVariableLink = self.debug_arena.pushStruct(DebugVariableLink, null);

        link.next = parent.sentinel.next;
        link.prev = &parent.sentinel;
        link.next.prev = link;
        link.prev.next = link;

        link.children = null;
        link.element = element;

        return link;
    }

    pub fn addGroupToGroup(
        self: *DebugState,
        parent: *DebugVariableGroup,
        group: *DebugVariableGroup,
    ) *DebugVariableLink {
        const link: *DebugVariableLink = self.debug_arena.pushStruct(DebugVariableLink, null);

        link.next = parent.sentinel.next;
        link.prev = &parent.sentinel;
        link.next.prev = link;
        link.prev.next = link;

        link.children = group;
        link.element = null;

        return link;
    }

    fn getElementFromEvent(self: *DebugState, event: *DebugEvent) *DebugElement {
        var result: ?*DebugElement = null;
        const hash_value: u32 = @intCast(@intFromPtr(event.guid) >> 2);
        const index: u32 = @mod(hash_value, @as(u32, @intCast(self.element_hash.len)));

        var opt_chain: ?*DebugElement = self.element_hash[index];
        while (opt_chain) |chain| : (opt_chain = chain.next_in_hash) {
            if (@intFromPtr(chain.guid) == @intFromPtr(event.guid)) {
                result = chain;
                break;
            }
        }

        if (result == null) {
            result = self.debug_arena.pushStruct(DebugElement, null);

            result.?.guid = event.guid;
            result.?.next_in_hash = self.element_hash[index];
            self.element_hash[index] = result;

            result.?.oldest_event = null;
            result.?.most_recent_event = null;

            if (self.getGroupForHierarchicalName(self.root_group, event.block_name)) |parent_group| {
                _ = self.addElementToGroup(parent_group, result.?);
            }
        }

        return result.?;
    }

    pub fn collateDebugRecords(self: *DebugState, event_count: u32, event_array: [*]DebugEvent) void {
        var event_index: u32 = 0;
        while (event_index < event_count) : (event_index += 1) {
            const event: *DebugEvent = &event_array[event_index];
            const element: *DebugElement = self.getElementFromEvent(event);

            if (self.collation_frame == null) {
                self.collation_frame = self.newFrame(event.clock);
            }

            if (event.event_type == .MarkDebugValue) {
                _ = self.storeEvent(element, event);
            } else if (event.event_type == .FrameMarker) {
                std.debug.assert(self.collation_frame != null);

                if (self.collation_frame) |collation_frame| {
                    collation_frame.end_clock = event.clock;
                    collation_frame.wall_seconds_elapsed = event.data.f32;

                    if (false) {
                        const clock_range: f32 = @floatFromInt(collation_frame.end_clock - collation_frame.begin_clock);
                        if (clock_range > 0) {
                            const frame_bar_scale = 1.0 / clock_range;

                            if (self.frame_bar_scale > frame_bar_scale) {
                                self.frame_bar_scale = frame_bar_scale;
                            }
                        }
                    }

                    if (self.paused) {
                        self.freeFrame(self.collation_frame);
                    } else {
                        if (self.most_recent_frame != null) {
                            self.most_recent_frame = collation_frame;
                            self.most_recent_frame.?.next = collation_frame;
                        } else {
                            self.oldest_frame = collation_frame;
                            self.most_recent_frame = collation_frame;
                        }
                        self.frame_count += 1;
                    }
                }

                self.collation_frame = self.newFrame(event.clock);
            } else {
                std.debug.assert(self.collation_frame != null);

                // const collation_frame: *DebugFrame = self.collation_frame.?;
                const frame_index: u32 = self.frame_count -% 1;
                const thread: *DebugThread = self.getDebugThread(event.thread_id);
                // const relative_clock: u64 = event.clock - collation_frame.begin_clock;
                // _ = relative_clock;

                switch (event.event_type) {
                    .BeginBlock => {
                        // _ = self.allocateOpenDebugBlock(element, frame_index, event, &thread.first_open_code_block);
                    },
                    .EndBlock => {
                        if (thread.first_open_code_block) |matching_block| {
                            const opening_event: *DebugEvent = matching_block.opening_event;

                            if (opening_event.matches(event)) {
                                if (matching_block.staring_frame_index == frame_index) {
                                    var match_name: ?[*:0]const u8 = null;

                                    if (matching_block.parent) |parent| {
                                        match_name = parent.opening_event.block_name;
                                    }

                                    // if (match_name == self.scope_to_record) {
                                    //     const min_t: f32 = @floatFromInt(opening_event.clock - collation_frame.begin_clock);
                                    //     const max_t: f32 = @floatFromInt(event.clock - collation_frame.begin_clock);
                                    //     const threshold_t: f32 = 0.01;
                                    //
                                    //     if ((max_t - min_t) > threshold_t) {
                                    //         var region: *DebugFrameRegion = self.addRegion(collation_frame);
                                    //         region.event = opening_event;
                                    //         region.cycle_count = event.clock - opening_event.clock;
                                    //         region.lane_index = @intCast(thread.lane_index);
                                    //         region.min_t = min_t;
                                    //         region.max_t = max_t;
                                    //         region.color_index = @truncate(@intFromPtr(opening_event.block_name));
                                    //     }
                                    // }
                                } else {
                                    // Started on some previous frame.
                                }

                                self.deallocateOpenDebugBlock(&thread.first_open_code_block);
                            } else {
                                // No begin block.
                            }
                        }
                    },
                    .OpenDataBlock => {
                        _ = self.allocateOpenDebugBlock(element, frame_index, event, &thread.first_open_data_block);
                    },
                    .CloseDataBlock => {
                        if (thread.first_open_data_block) |matching_block| {
                            _ = self.storeEvent(element, event);

                            const opening_event: *DebugEvent = matching_block.opening_event;
                            if (opening_event.matches(event)) {
                                self.deallocateOpenDebugBlock(&thread.first_open_data_block);
                            }
                        }
                    },
                    else => {
                        var storage_element: *DebugElement = element;

                        if (thread.first_open_data_block) |first_open_data_block| {
                            storage_element = first_open_data_block.element.?;
                        }

                        _ = self.storeEvent(storage_element, event);
                    },
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
            result = self.first_thread;
            if (result != null) {
                self.first_thread = result.?.next;
            } else {
                result = self.debug_arena.pushStruct(DebugThread, null);
            }

            result.?.id = thread_id;
            result.?.first_open_code_block = null;
            result.?.first_open_data_block = null;

            result.?.lane_index = self.frame_bar_lane_count;
            self.frame_bar_lane_count += 1;

            result.?.next = self.first_thread;
            self.first_thread = result.?;
        }

        return result.?;
    }

    // fn addRegion(self: *DebugState, current_frame: *DebugFrame) *DebugFrameRegion {
    //     _ = self;
    //
    //     std.debug.assert(current_frame.region_count < debug_interface.MAX_DEBUG_REGIONS_PER_FRAME);
    //
    //     const result: *DebugFrameRegion = &current_frame.regions[current_frame.region_count];
    //     current_frame.region_count += 1;
    //
    //     return result;
    // }

    fn addTree(self: *DebugState, group: ?*DebugVariableGroup, position: Vector2) *DebugTree {
        var tree: *DebugTree = self.debug_arena.pushStruct(DebugTree, null);
        tree.group = group;
        tree.ui_position = position;

        tree.next = self.tree_sentinel.next;
        tree.prev = &self.tree_sentinel;
        tree.next.?.prev = tree;
        tree.prev.?.next = tree;

        return tree;
    }

    fn interactionIsHot(self: *const DebugState, interaction: *const DebugInteraction) bool {
        return interaction.equals(&self.hot_interaction);
    }

    pub fn isSelected(self: *DebugState, id: DebugId) bool {
        var result = false;

        var index: u32 = 0;
        while (index < self.selected_id_count) : (index += 1) {
            if (id.equals(self.selected_id[index])) {
                result = true;
                break;
            }
        }

        return result;
    }

    pub fn clearSelection(self: *DebugState) void {
        self.selected_id_count = 0;
    }

    pub fn addToSelection(self: *DebugState, id: DebugId) void {
        if (self.selected_id_count < self.selected_id.len and !self.isSelected(id)) {
            self.selected_id[self.selected_id_count] = id;
            self.selected_id_count += 1;
        }
    }

    fn getOrCreateDebugView(self: *DebugState, id: DebugId) *DebugView {
        const hash_index = @mod(((@intFromPtr(id.value[0]) >> 2) + (@intFromPtr(id.value[1]) >> 2)), self.view_hash.len);
        const hash_slot = &self.view_hash[hash_index];
        var result: ?*DebugView = null;

        var opt_search: ?*DebugView = hash_slot.*;
        while (opt_search) |search| : (opt_search = search.next_in_hash) {
            if (search.id.equals(id)) {
                result = search;
                break;
            }
        }

        if (result == null) {
            result = self.debug_arena.pushStruct(DebugView, null);
            result.?.id = id;
            result.?.view_type = .Unknown;
            result.?.next_in_hash = hash_slot.*;
            hash_slot.* = result.?;
        }

        return result.?;
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
    group: ?*DebugVariableGroup,

    prev: ?*DebugTree,
    next: ?*DebugTree,
};

const DebugViewType = enum(u32) {
    Unknown,
    Basic,
    InlineBlock,
    Collapsible,
};

const DebugViewDataType = enum(u32) {
    inline_block,
    collapsible,
};

pub const DebugView = struct {
    id: DebugId,
    next_in_hash: *DebugView = undefined,

    view_type: DebugViewType,
    data: union(DebugViewDataType) {
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

pub const DebugStoredEvent = struct {
    next: ?*DebugStoredEvent,
    frame_index: u32,
    event: DebugEvent,
};

pub const DebugElement = struct {
    guid: [*:0]const u8,
    next_in_hash: ?*DebugElement,

    oldest_event: ?*DebugStoredEvent,
    most_recent_event: ?*DebugStoredEvent,
};

pub const DebugVariableLink = struct {
    next: *DebugVariableLink,
    prev: *DebugVariableLink,

    children: ?*DebugVariableGroup,
    element: ?*DebugElement,
};

pub const DebugVariableGroup = struct {
    name_length: u32,
    name: [*:0]const u8,
    sentinel: DebugVariableLink,
};

fn debugEventToText(buffer: *[4096:0]u8, start_index: u32, event: *DebugEvent, flags: u32) u32 {
    var len: u32 = start_index;

    if (flags & DebugVariableToTextFlag.Declaration.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], "{s}", .{event.prefixString()}) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.Name.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], "{s}", .{event.block_name}) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.Colon.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], ": ", .{}) catch "";
        len += @intCast(slice.len);
    }

    if (event.event_type != .OpenDataBlock and flags & DebugVariableToTextFlag.Type.toInt() != 0) {
        const slice = std.fmt.bufPrintZ(buffer[len..], ": {s} = ", .{event.typeString()}) catch "";
        len += @intCast(slice.len);
    }

    if (flags & DebugVariableToTextFlag.Declaration.toInt() != 0) {
        switch (event.event_type) {
            .Vector2, .Vector3, .Vector4 => {
                const slice = std.fmt.bufPrintZ(buffer[len..], "{s}.new", .{event.typeString()}) catch "";
                len += @intCast(slice.len);
            },
            else => {},
        }
    }

    switch (event.event_type) {
        .bool => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{s}", .{if (event.data.bool) "true" else "false"}) catch "";
            len += @intCast(slice.len);
        },
        .i32 => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{d}", .{event.data.i32}) catch "";
            len += @intCast(slice.len);
        },
        .u32 => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{d}", .{event.data.u32}) catch "";
            len += @intCast(slice.len);
        },
        .f32 => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{d}", .{event.data.f32}) catch "";
            len += @intCast(slice.len);
        },
        .Vector2 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d})",
                .{ event.data.Vector2.x(), event.data.Vector2.y() },
            ) catch "";
            len += @intCast(slice.len);
        },
        .Vector3 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d}, {d})",
                .{
                    event.data.Vector3.x(),
                    event.data.Vector3.y(),
                    event.data.Vector3.z(),
                },
            ) catch "";
            len += @intCast(slice.len);
        },
        .Vector4 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d}, {d}, {d})",
                .{
                    event.data.Vector4.x(),
                    event.data.Vector4.y(),
                    event.data.Vector4.z(),
                    event.data.Vector4.w(),
                },
            ) catch "";
            len += @intCast(slice.len);
        },
        .Rectangle2 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d}, {d}, {d})",
                .{
                    event.data.Rectangle2.min.x(),
                    event.data.Rectangle2.min.y(),
                    event.data.Rectangle2.max.x(),
                    event.data.Rectangle2.max.y(),
                },
            ) catch "";
            len += @intCast(slice.len);
        },
        .Rectangle3 => {
            const slice = std.fmt.bufPrintZ(
                buffer[len..],
                "({d}, {d}, {d}, {d}, {d}, {d})",
                .{
                    event.data.Rectangle3.min.x(),
                    event.data.Rectangle3.min.y(),
                    event.data.Rectangle3.min.z(),
                    event.data.Rectangle3.max.x(),
                    event.data.Rectangle3.max.y(),
                    event.data.Rectangle3.max.z(),
                },
            ) catch "";
            len += @intCast(slice.len);
        },
        .OpenDataBlock => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "{s}", .{event.block_name}) catch "";
            len += @intCast(slice.len);
        },
        .CounterThreadList => {},
        .Unknown => {},
        else => {
            const slice = std.fmt.bufPrintZ(buffer[len..], "UNHANDLED: {s}", .{event.block_name}) catch "";
            len += @intCast(slice.len);
        },
    }

    if (event.event_type != .OpenDataBlock and flags & DebugVariableToTextFlag.SemiColonEnd.toInt() != 0) {
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

const DebugVariableIterator = struct {
    link: *DebugVariableLink = undefined,
    sentinel: *DebugVariableLink = undefined,
};

fn writeHandmadeConfig(debug_state: *DebugState) void {
    _ = debug_state;
    // var buffer: [4096:0]u8 = undefined;
    // var length: u32 = 0;
    // var depth: u32 = 0;
    // var stack: [MAX_VARIABLE_STACK_DEPTH]DebugVariableIterator = [1]DebugVariableIterator{DebugVariableIterator{}} ** MAX_VARIABLE_STACK_DEPTH;
    //
    // {
    //     const imports =
    //         \\const math = @import("math.zig");
    //         \\
    //         \\const Vector2 = math.Vector2;
    //         \\const Vector3 = math.Vector3;
    //         \\const Vector4 = math.Vector4;
    //         \\
    //         \\
    //     ;
    //
    //     const slice = std.fmt.bufPrintZ(buffer[length..], "{s}", .{imports}) catch "";
    //     length += @intCast(slice.len);
    // }
    //
    // if (debug_state.root_group) |root_group| {
    //     stack[depth].link = root_group.data.var_group.next;
    //     stack[depth].sentinel = &root_group.data.var_group;
    //     depth += 1;
    //
    //     while (depth > 0) {
    //         var iterator: *DebugVariableIterator = &stack[depth - 1];
    //
    //         if (iterator.link == iterator.sentinel) {
    //             depth -= 1;
    //         } else {
    //             const variable: *DebugVariable = iterator.link.variable;
    //             iterator.link = iterator.link.next;
    //
    //             if (variable.shouldBeWritten()) {
    //                 for (0..depth) |_| {
    //                     for (0..4) |_| {
    //                         buffer[length] = ' ';
    //                         length += 1;
    //                     }
    //                 }
    //
    //                 length = debugVariableToText(&buffer, length, variable, DebugVariableToTextFlag.declarationFlags());
    //             }
    //
    //             if (variable.variable_type == .VarGroup) {
    //                 iterator = &stack[depth];
    //                 iterator.link = variable.data.var_group.next;
    //                 iterator.sentinel = &variable.data.var_group;
    //                 depth += 1;
    //             }
    //         }
    //     }
    //
    //     _ = shared.platform.debugWriteEntireFile("../src/config.zig", length, &buffer);
    //
    //     if (!debug_state.is_compiling) {
    //         debug_state.is_compiling = true;
    //         debug_state.compiler = shared.platform.debugExecuteSystemCommand(
    //             "../",
    //             "C:/Windows/System32/cmd.exe",
    //             "/C zig build -Dpackage=Library",
    //         );
    //     }
    // }
}

fn drawProfileIn(debug_state: *DebugState, profile_rect: Rectangle2, mouse_position: Vector2) void {
    if (debug_state.render_group) |group| {
        group.pushRectangle2(ObjectTransform.defaultFlat(), profile_rect, 0, Color.new(0, 0, 0, 0.25));

        const bar_spacing: f32 = 4;
        var lane_height: f32 = 0;
        const lane_count: u32 = debug_state.frame_bar_lane_count;
        var frame_bar_scale: f32 = std.math.floatMax(f32);

        {
            var opt_frame: ?*DebugFrame = debug_state.oldest_frame;
            while (opt_frame) |frame| : (opt_frame = frame.next) {
                if (frame_bar_scale < frame.frame_bar_scale) {
                    frame_bar_scale = frame.frame_bar_scale;
                }
            }
        }

        var max_frame: u32 = debug_state.frame_count;
        if (max_frame > 10) {
            max_frame = 10;
        }

        if (lane_count > 0 and max_frame > 0) {
            const pixels_per_frame: f32 = profile_rect.getDimension().y() / @as(f32, @floatFromInt(max_frame));
            lane_height = (pixels_per_frame - bar_spacing) / @as(f32, @floatFromInt(lane_count));
        }

        _ = mouse_position;
        // const bar_height: f32 = lane_height * @as(f32, @floatFromInt(lane_count));
        // const bars_plus_spacing: f32 = bar_height + bar_spacing;
        // const chart_left: f32 = profile_rect.min.x();
        // // const chart_height: f32 = bars_plus_spacing * @as(f32, @floatFromInt(max_frame));
        // const chart_width: f32 = profile_rect.getDimension().x();
        // const chart_top: f32 = profile_rect.max.y();
        // const scale: f32 = chart_width * frame_bar_scale;
        //
        // const colors: [12]Color3 = .{
        //     Color3.new(1, 0, 0),
        //     Color3.new(0, 1, 0),
        //     Color3.new(0, 0, 1),
        //     Color3.new(1, 1, 0),
        //     Color3.new(0, 1, 1),
        //     Color3.new(1, 0, 1),
        //     Color3.new(1, 0.5, 0),
        //     Color3.new(1, 0, 0.5),
        //     Color3.new(0.5, 1, 0),
        //     Color3.new(0, 1, 0.5),
        //     Color3.new(0.5, 0, 1),
        //     Color3.new(0, 0.5, 1),
        // };

        // var frame_index: u32 = 0;
        // var opt_frame: ?*DebugFrame = debug_state.oldest_frame;
        // while (opt_frame) |frame| : (opt_frame = frame.next) {
        //     defer frame_index += 1;
        //     const stack_x: f32 = chart_left;
        //     const stack_y: f32 = chart_top - bars_plus_spacing * @as(f32, (@floatFromInt(frame_index)));
        //
        //     var region_index: u32 = 0;
        //     while (region_index < frame.region_count) : (region_index += 1) {
        //         const region: *const DebugFrameRegion = &frame.regions[region_index];
        //
        //         const color = colors[region.color_index % colors.len];
        //         const this_min_x: f32 = stack_x + scale * region.min_t;
        //         const this_max_x: f32 = stack_x + scale * region.max_t;
        //         const lane: f32 = @as(f32, @floatFromInt(region.lane_index));
        //
        //         const region_rect = math.Rectangle2.new(
        //             this_min_x,
        //             stack_y - lane_height * (lane + 1),
        //             this_max_x,
        //             stack_y - lane_height * lane,
        //         );
        //
        //         group.pushRectangle2(region_rect, 0, color.toColor(1));
        //
        //         if (mouse_position.isInRectangle(region_rect)) {
        //             const event: *DebugEvent = region.event;
        //
        //             var buffer: [128]u8 = undefined;
        //             const slice = std.fmt.bufPrintZ(&buffer, "{s}: {d:10}cy [{s}({d})]", .{
        //                 event.block_name,
        //                 region.cycle_count,
        //                 event.file_name,
        //                 event.line_number,
        //             }) catch "";
        //             textOutAt(slice, mouse_position.plus(Vector2.new(0, 10)), Color.white());
        //
        //             // hot_record = record;
        //         }
        //     }
        // }

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
        const no_transform = ObjectTransform.defaultFlat();
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
                    no_transform,
                    Rectangle2.fromMinMax(
                        Vector2.new(total_min_corner.x(), interior_min_corner.y()),
                        Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                    ),
                    0,
                    Color.black(),
                );
                render_group.pushRectangle2(
                    no_transform,
                    Rectangle2.fromMinMax(
                        Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                        Vector2.new(total_max_corner.x(), total_max_corner.y()),
                    ),
                    0,
                    Color.black(),
                );
                render_group.pushRectangle2(
                    no_transform,
                    Rectangle2.fromMinMax(
                        Vector2.new(interior_min_corner.x(), total_min_corner.y()),
                        Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                    ),
                    0,
                    Color.black(),
                );
                render_group.pushRectangle2(
                    no_transform,
                    Rectangle2.fromMinMax(
                        Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                        Vector2.new(interior_max_corner.x(), total_max_corner.y()),
                    ),
                    0,
                    Color.black(),
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
                render_group.pushRectangle2(no_transform, size_box, 0, size_box_color);

                if (self.layout.mouse_position.isInRectangle(size_box)) {
                    debug_state.next_hot_interaction = size_interaction;
                }
            }

            const spacing_y: f32 = if (false) 0 else self.layout.spacing_y;
            _ = self.layout.at.setY(total_bounds.min.y() - spacing_y);
        }
    }
};

pub fn hit(id: DebugId, z_value: f32) void {
    _ = z_value;
    if (DebugState.get()) |debug_state| {
        debug_state.next_hot_interaction = DebugInteraction.fromId(id, .Select);
    }
}

pub fn hitStub(id: DebugId, z_value: f32) void {
    _ = id;
    _ = z_value;
}

pub fn highlighted(id: DebugId, outline_color: *Color) bool {
    var result = false;

    if (DebugState.get()) |debug_state| {
        if (debug_state.isSelected(id)) {
            result = true;
            outline_color.* = Color.new(0, 1, 1, 1);
        }

        if (id.equals(debug_state.hot_interaction.id)) {
            result = true;
            outline_color.* = Color.new(1, 1, 0, 1);
        }
    }

    return result;
}

pub fn highlightedStub(id: DebugId, outline_color: *Color) bool {
    _ = id;
    _ = outline_color;
    return false;
}

pub fn requested(id: DebugId) bool {
    var result = false;

    if (DebugState.get()) |debug_state| {
        result = debug_state.isSelected(id) or id.equals(debug_state.hot_interaction.id);
    }

    return result;
}

pub fn requestedStub(id: DebugId) bool {
    _ = id;
    return false;
}

fn drawDebugEvent(layout: *Layout, opt_stored_event: ?*DebugStoredEvent, debug_id: DebugId) void {
    const no_transform = ObjectTransform.defaultFlat();
    const debug_state: *DebugState = layout.debug_state;

    if (opt_stored_event) |stored_event| {
        if (debug_state.debug_font_info) |font_info| {
            if (debug_state.render_group) |render_group| {
                const event = &stored_event.event;
                const item_interaction: DebugInteraction = DebugInteraction.eventInteraction(debug_state, debug_id, event, .AutoModifyVariable);
                const is_hot: bool = debug_state.interactionIsHot(&item_interaction);
                const item_color: Color = if (is_hot) Color.new(1, 1, 0, 1) else Color.white();
                const view: *DebugView = debug_state.getOrCreateDebugView(debug_id);

                switch (event.event_type) {
                    .BitmapId => {
                        const bitmap_scale = view.data.inline_block.dimension.y();
                        if (render_group.assets.getBitmap(event.data.BitmapId, render_group.generation_id)) |bitmap| {
                            var dim = render_group.getBitmapDim(no_transform, bitmap, bitmap_scale, Vector3.zero(), 0);
                            _ = view.data.inline_block.dimension.setX(dim.size.x());
                        }

                        const tear_interaction: DebugInteraction = DebugInteraction.eventInteraction(debug_state, debug_id, event, .TearValue);
                        var element: LayoutElement = layout.beginElementRectangle(&view.data.inline_block.dimension);
                        element.makeSizable();
                        element.defaultInteraction(tear_interaction);
                        element.end();

                        render_group.pushRectangle2(no_transform, element.bounds, 0, Color.black());
                        render_group.pushBitmapId(
                            no_transform,
                            event.data.BitmapId,
                            bitmap_scale,
                            element.bounds.min.toVector3(0),
                            Color.white(),
                            0,
                        );
                    },
                    else => {
                        var text: [4096:0]u8 = undefined;
                        var len: u32 = 0;
                        len = debugEventToText(&text, len, event, DebugVariableToTextFlag.displayFlags());

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
            }
        }
    }
}

fn drawDebugElement(layout: *Layout, tree: *DebugTree, element: *DebugElement, debug_id: DebugId) void {
    const debug_state: *DebugState = layout.debug_state;

    if (element.oldest_event) |oldest_event| {
        const view: *DebugView = debug_state.getOrCreateDebugView(debug_id);

        switch (oldest_event.event.event_type) {
            .CounterThreadList => {
                var layout_element: LayoutElement = layout.beginElementRectangle(&view.data.inline_block.dimension);
                layout_element.makeSizable();
                // layout_element.defaultInteraction(item_interaction);
                layout_element.end();

                drawProfileIn(debug_state, layout_element.bounds, layout.mouse_position);
            },
            .OpenDataBlock => {
                var last_open_block: *DebugStoredEvent = oldest_event;

                var opt_event: ?*DebugStoredEvent = element.oldest_event;
                while (opt_event) |event| : (opt_event = event.next) {
                    if (event.event.event_type == .OpenDataBlock) {
                        last_open_block = event;
                    }
                }

                opt_event = last_open_block;
                while (opt_event) |event| : (opt_event = event.next) {
                    const new_id: DebugId = DebugId.fromGuid(tree, event.event.guid);
                    drawDebugEvent(layout, event, new_id);
                }
            },
            else => {
                const opt_event: ?*DebugStoredEvent = element.most_recent_event;
                drawDebugEvent(layout, opt_event, debug_id);
            },
        }
    } else {}
}

fn drawDebugMainMenu(debug_state: *DebugState, render_group: *render.RenderGroup, mouse_position: Vector2) void {
    var opt_tree: ?*DebugTree = debug_state.tree_sentinel.next;

    if (debug_state.debug_font_info) |font_info| {
        while (opt_tree) |tree| : (opt_tree = tree.next) {
            if (tree == &debug_state.tree_sentinel) {
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

            if (tree.group) |tree_group| {
                var depth: u32 = 0;
                var stack: [MAX_VARIABLE_STACK_DEPTH]DebugVariableIterator = [1]DebugVariableIterator{DebugVariableIterator{}} ** MAX_VARIABLE_STACK_DEPTH;

                stack[depth].link = tree_group.sentinel.next;
                stack[depth].sentinel = &tree_group.sentinel;
                depth += 1;

                while (depth > 0) {
                    var iterator: *DebugVariableIterator = &stack[depth - 1];

                    if (iterator.link == iterator.sentinel) {
                        depth -= 1;
                    } else {
                        layout.depth = depth;

                        const link: *DebugVariableLink = iterator.link;
                        iterator.link = iterator.link.next;

                        if (link.children != null) {
                            const debug_id: DebugId = DebugId.fromLink(tree, link);
                            const view: *DebugView = debug_state.getOrCreateDebugView(debug_id);
                            const item_interaction: DebugInteraction = DebugInteraction.fromId(DebugId.fromLink(tree, link), .ToggleExpansion);

                            var text: [256:0]u8 = undefined;
                            std.debug.assert(link.children.?.name_length + 1 < text.len);
                            _ = shared.copy(link.children.?.name_length, @ptrCast(@constCast(link.children.?.name)), @ptrCast(&text));
                            text[link.children.?.name_length] = 0;

                            const text_bounds = getTextSize(debug_state, &text);
                            var dim: Vector2 = Vector2.new(text_bounds.getDimension().x(), layout.line_advance);

                            var element: LayoutElement = layout.beginElementRectangle(&dim);
                            element.defaultInteraction(item_interaction);
                            element.end();

                            const is_hot: bool = debug_state.interactionIsHot(&item_interaction);
                            const item_color: Color = if (is_hot) Color.new(1, 1, 0, 1) else Color.white();

                            const text_position: Vector2 = Vector2.new(
                                element.bounds.min.x(),
                                element.bounds.max.y() - debug_state.font_scale * font_info.getStartingBaselineY(),
                            );
                            textOutAt(&text, text_position, item_color);

                            if (view.data == .collapsible and view.data.collapsible.expanded_always) {
                                iterator = &stack[depth];
                                iterator.link = link.children.?.sentinel.next;
                                iterator.sentinel = &link.children.?.sentinel;
                                depth += 1;
                            }
                        } else {
                            const debug_id = DebugId.fromLink(tree, link);
                            drawDebugElement(&layout, tree, link.element.?, debug_id);
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
                render_group.pushRectangle2(ObjectTransform.defaultFlat(), move_box, 0, move_box_color);

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
    if (debug_state.hot_interaction.interaction_type != .None) {
        if (debug_state.hot_interaction.interaction_type == .AutoModifyVariable) {
            switch (debug_state.hot_interaction.target.event.?.event_type) {
                .bool => {
                    debug_state.hot_interaction.interaction_type = .ToggleValue;
                },
                .f32 => {
                    debug_state.hot_interaction.interaction_type = .DragValue;
                },
                .OpenDataBlock => {
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
                _ = mouse_position;
                // const root_group: *DebugVariable = debug_variables.addRootGroup(debug_state, "NewUserGroup");
                // _ = debug_variables.addDebugVariableToGroup(debug_state, root_group, debug_state.hot_interaction.target.variable);
                // const tree: *DebugTree = debug_state.addTree(root_group, Vector2.zero());
                // tree.ui_position = mouse_position;
                // debug_state.hot_interaction.interaction_type = .Move;
                // debug_state.hot_interaction.target = .{ .position = &tree.ui_position };
            },
            .Select => {
                if (!input.shift_down) {
                    debug_state.clearSelection();
                }

                debug_state.addToSelection(debug_state.hot_interaction.id);
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
                if (debug_state.interaction.target.event) |event| {
                    switch (event.event_type) {
                        .f32 => {
                            event.data.f32 += 0.1 * mouse_delta.y();
                        },
                        else => {},
                    }
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
        .ToggleExpansion => {
            const view: *DebugView = debug_state.getOrCreateDebugView(debug_state.interaction.id);

            if (view.data != .collapsible) {
                view.data = .{
                    .collapsible = .{ .expanded_always = false, .expanded_alt_view = false },
                };
            }

            view.data.collapsible.expanded_always = !view.data.collapsible.expanded_always;
        },
        .ToggleValue => {
            std.debug.assert(debug_state.interaction.target == .event);

            if (debug_state.interaction.target.event) |event| {
                switch (event.event_type) {
                    .bool => {
                        event.data.bool = !event.data.bool;
                    },
                    else => {},
                }
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

                        const advance_x: f32 = char_scale * font.getHorizontalAdvanceForPair(
                            font_info,
                            prev_code_point,
                            code_point,
                        );
                        x += advance_x;

                        if (code_point != ' ') {
                            match_vector.e[@intFromEnum(asset.AssetTagId.UnicodeCodepoint)] = @floatFromInt(code_point);
                            if (font.getBitmapForGlyph(font_info, render_group.assets, code_point)) |bitmap_id| {
                                const info = render_group.assets.getBitmapInfo(bitmap_id);
                                const bitmap_scale = char_scale * @as(f32, @floatFromInt(info.dim[1]));
                                const bitamp_offset: Vector3 = Vector3.new(x, position.y(), 0);

                                if (op == .DrawText) {
                                    render_group.pushBitmapId(
                                        ObjectTransform.defaultFlat(),
                                        bitmap_id,
                                        bitmap_scale,
                                        bitamp_offset,
                                        color,
                                        null,
                                    );
                                } else {
                                    std.debug.assert(op == .SizeText);

                                    if (render_group.assets.getBitmap(bitmap_id, render_group.generation_id)) |bitmap| {
                                        const dim = render_group.getBitmapDim(
                                            ObjectTransform.defaultFlat(),
                                            bitmap,
                                            bitmap_scale,
                                            bitamp_offset,
                                            1,
                                        );
                                        var glyph_dim: Rectangle2 = Rectangle2.fromMinDimension(
                                            dim.position.xy(),
                                            dim.size,
                                        );
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

fn debugStart(debug_state: *DebugState, assets: *asset.Assets, width: i32, height: i32) void {
    var timed_block = TimedBlock.beginFunction(@src(), .DebugStart);
    defer timed_block.end();

    if (shared.debug_global_memory) |memory| {
        if (!debug_state.initialized) {
            debug_state.frame_bar_lane_count = 0;
            debug_state.first_thread = null;
            debug_state.first_free_thread = null;
            debug_state.first_free_block = null;

            debug_state.frame_count = 0;

            debug_state.oldest_frame = null;
            debug_state.most_recent_frame = null;
            debug_state.first_free_frame = null;

            debug_state.collation_frame = null;

            debug_state.high_priority_queue = memory.high_priority_queue;

            debug_state.tree_sentinel.next = &debug_state.tree_sentinel;
            debug_state.tree_sentinel.prev = &debug_state.tree_sentinel;
            debug_state.tree_sentinel.group = null;

            const total_memory_size: shared.MemoryIndex = memory.debug_storage_size - @sizeOf(DebugState);
            debug_state.debug_arena.initialize(
                total_memory_size,
                memory.debug_storage.? + @sizeOf(DebugState),
            );
            debug_state.debug_arena.makeSubArena(
                &debug_state.per_frame_arena,
                total_memory_size / 2,
                // 128 * 1024,
                null,
            );

            debug_state.root_group = debug_state.createVariableGroup(4, "Root");

            // var context: debug_variables.DebugVariableDefinitionContext = .{
            //     .state = debug_state,
            //     .arena = &debug_state.debug_arena,
            // };
            // debug_state.root_group = debug_variables.beginVariableGroup(&context, "Root");
            // _ = debug_variables.beginVariableGroup(&context, "Debugging");
            //
            // debug_variables.createDebugVariables(&context);
            //
            // _ = debug_variables.beginVariableGroup(&context, "Profile");
            // {
            //     _ = debug_variables.beginVariableGroup(&context, "By Thread");
            //     _ = debug_variables.addDebugVariableToContext(&context, .CounterThreadList, "");
            //     debug_variables.endVariableGroup(&context);
            //
            //     _ = debug_variables.beginVariableGroup(&context, "By Function");
            //     _ = debug_variables.addDebugVariableToContext(&context, .CounterThreadList, "");
            //     debug_variables.endVariableGroup(&context);
            // }
            // debug_variables.endVariableGroup(&context);
            //
            // var match_vector = asset.AssetVector{};
            // match_vector.e[file_formats.AssetTagId.FacingDirection.toInt()] = 0;
            // var weight_vector = asset.AssetVector{};
            // weight_vector.e[file_formats.AssetTagId.FacingDirection.toInt()] = 1;
            // if (assets.getBestMatchBitmap(.Head, &match_vector, &weight_vector)) |id| {
            //     _ = debug_variables.addDebugVariableBitmap(&context, "Test Bitmap", id);
            // }
            //
            // debug_variables.endVariableGroup(&context);
            // debug_variables.endVariableGroup(&context);
            // std.debug.assert(context.group_depth == 0);

            debug_state.render_group =
                render.RenderGroup.allocate(assets, &debug_state.debug_arena, shared.megabytes(16), false);

            debug_state.paused = false;
            debug_state.scope_to_record = null;

            debug_state.initialized = true;

            _ = debug_state.addTree(
                debug_state.root_group,
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

pub fn debugDumpStruct(struct_ptr: *anyopaque, member_defs: [*]const meta.MemberDefinition, member_def_count: u32, indent_level: u32) void {
    var member_index: u32 = 0;
    while (member_index < member_def_count) : (member_index += 1) {
        const member: *const meta.MemberDefinition = @ptrCast(member_defs + member_index);
        var opt_member_ptr: ?*anyopaque = @ptrFromInt(@intFromPtr(struct_ptr) + member.field_offset);

        if (opt_member_ptr) |member_ptr| {
            if (member.flags == .IsPointer) {
                opt_member_ptr = @as(**anyopaque, @ptrCast(@alignCast(member_ptr))).*;
                // Pointers give an incorrect alignment panic, skip for now.
                continue;
            }
        }

        if (opt_member_ptr) |member_ptr| {
            var buffer: [256]u8 = undefined;
            var slice: ?[:0]const u8 = null;
            switch (member.field_type) {
                .u32 => {
                    const value: *u32 = @ptrCast(@alignCast(member_ptr));
                    slice = std.fmt.bufPrintZ(&buffer, "{s}: {d}", .{ member.field_name, value.* }) catch "";
                },
                .i32 => {
                    const value: *i32 = @ptrCast(@alignCast(member_ptr));
                    slice = std.fmt.bufPrintZ(&buffer, "{s}: {d}", .{ member.field_name, value.* }) catch "";
                },
                .f32 => {
                    const value: *f32 = @ptrCast(@alignCast(member_ptr));
                    slice = std.fmt.bufPrintZ(&buffer, "{s}: {d:0.4}", .{ member.field_name, value.* }) catch "";
                },
                .bool => {
                    const value: *bool = @ptrCast(@alignCast(member_ptr));
                    slice = std.fmt.bufPrintZ(&buffer, "{s}: {s}", .{ member.field_name, if (value.*) "true" else "false" }) catch "";
                },
                .Vector2 => {
                    const value: *Vector2 = @ptrCast(@alignCast(member_ptr));
                    slice = std.fmt.bufPrintZ(&buffer, "{s}: {{{d:0.4}, {d:0.4}}}", .{ member.field_name, value.x(), value.y() }) catch "";
                },
                .Vector3 => {
                    const value: *Vector3 = @ptrCast(@alignCast(member_ptr));
                    slice = std.fmt.bufPrintZ(&buffer, "{s}: {{{d:0.4}, {d:0.4}, {d:0.4}}}", .{ member.field_name, value.x(), value.y(), value.z() }) catch "";
                },
                else => {
                    generated.dumpKnownStruct(member_ptr, member, indent_level + 1);
                },
            }

            if (slice) |s| {
                var indent_buffer: [128]u8 = undefined;
                var indent_index: u32 = 0;
                while (indent_index < indent_level * 4) : (indent_index += 1) {
                    indent_buffer[indent_index] = ' ';
                }
                const indent: []const u8 = indent_buffer[0 .. indent_level * 4];

                var out_buffer: [256]u8 = undefined;
                textLine(std.fmt.bufPrintZ(&out_buffer, "{s}{s}", .{ indent, s }) catch "");
            }
        }
    }
}

fn debugEnd(debug_state: *DebugState, input: *const shared.GameInput, draw_buffer: *asset.LoadedBitmap) void {
    var overlay_timed_block = TimedBlock.beginBlock(@src(), .DebugEnd);
    defer overlay_timed_block.end();

    if (debug_state.render_group) |group| {
        const mouse_position: Vector2 = group.unproject(
            ObjectTransform.defaultFlat(),
            Vector2.new(input.mouse_x, input.mouse_y),
        ).xy();
        const hot_event: ?*DebugEvent = null;

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

        if (debug_state.most_recent_frame) |most_recent_frame| {
            var buffer: [128]u8 = undefined;
            const slice = std.fmt.bufPrintZ(&buffer, "Last frame time: {d:0.2}ms", .{
                most_recent_frame.wall_seconds_elapsed * 1000,
            }) catch "";
            textLine(slice);

            const slice2 = std.fmt.bufPrintZ(&buffer, "Per-frame arena space remaining: {d}kb", .{
                debug_state.debug_arena.getRemainingSize(ArenaPushParams.alignedNoClear(1)) / 1024,
            }) catch "";
            textLine(slice2);
        }

        if (input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].wasPressed()) {
            if (hot_event) |event| {
                debug_state.scope_to_record = event.block_name;
            } else {
                debug_state.scope_to_record = null;
            }
        }

        group.renderToOutput(debug_state.high_priority_queue, draw_buffer, &debug_state.debug_arena);
        group.endRender();

        shared.zeroStruct(DebugInteraction, &debug_state.next_hot_interaction);
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

pub fn initializeDebugValue(
    comptime source: std.builtin.SourceLocation,
    event_type: DebugType,
    sub_event: *DebugEvent,
    guid: [*:0]const u8,
    name: []const u8,
) DebugEvent {
    const mark_event = DebugEvent.record(source, .MarkDebugValue, "");
    mark_event.guid = guid;
    mark_event.block_name = @ptrCast(name);
    mark_event.data.value_debug_event = sub_event;

    sub_event.clock = 0;
    sub_event.guid = guid;
    sub_event.block_name = @ptrCast(name);
    sub_event.thread_id = 0;
    sub_event.core_index = 0;
    sub_event.event_type = event_type;

    return sub_event.*;
}

pub fn frameEnd(memory: *shared.Memory, input: shared.GameInput, buffer: *shared.OffscreenBuffer) callconv(.C) *debug_interface.DebugTable {
    global_debug_table.current_event_array_index = if (global_debug_table.current_event_array_index == 0) 1 else 0;

    const next_event_array_index: u64 = @as(u64, @intCast(global_debug_table.current_event_array_index)) << 32;
    const event_array_index_event_index: u64 =
        @atomicRmw(u64, &global_debug_table.event_array_index_event_index, .Xchg, next_event_array_index, .seq_cst);
    const event_array_index: u32 = @intCast(event_array_index_event_index >> 32);

    std.debug.assert(event_array_index <= 1);

    const event_count: u32 = @intCast(event_array_index_event_index & 0xffffffff);

    if (memory.debug_storage) |debug_storage| {
        const debug_state: *DebugState = @ptrCast(@alignCast(debug_storage));

        if (getGameAssets(memory)) |assets| {
            debugStart(debug_state, assets, buffer.width, buffer.height);
            debug_state.collateDebugRecords(event_count, &global_debug_table.events[event_array_index]);

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
