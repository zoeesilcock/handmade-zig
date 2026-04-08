const shared = @import("shared.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const asset = @import("asset.zig");
const asset_rendering = @import("asset_rendering.zig");
const renderer = @import("renderer.zig");
const math = @import("math.zig");
const config = @import("config.zig");
const sim = @import("sim.zig");
const sort = @import("sort.zig");
const file_formats = shared.file_formats;
const debug_interface = @import("debug_interface.zig");
const dev_ui = @import("dev_ui.zig");
const std = @import("std");

// Types.
const DevId = types.DevId;
const Assets = asset.Assets;
const TimedBlock = debug_interface.TimedBlock;
const DebugType = debug_interface.DebugType;
const DebugEvent = debug_interface.DebugEvent;
const DevUI = dev_ui.DevUI;
const TooltipBuffer = dev_ui.TooltipBuffer;
const DebugPlatformMemoryStats = shared.DebugPlatformMemoryStats;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Matrix4x4 = math.Matrix4x4;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const MemoryArena = memory.MemoryArena;
const MemoryIndex = memory.MemoryIndex;
const ArenaPushParams = memory.ArenaPushParams;
const SortEntry = sort.SortEntry;
const ObjectTransform = renderer.ObjectTransform;
const RenderGroup = renderer.RenderGroup;
const RenderGroupFlags = renderer.RenderGroupFlags;
const TransientClipRect = renderer.TransientClipRect;

const debug_color_table = shared.debug_color_table;

const MAX_FRAME_COUNT = 256;
pub const MAX_VARIABLE_STACK_DEPTH = 64;

fn devIdFromLink(tree: *DebugTree, link: *DebugVariableLink) DevId {
    return DevId{ .value = .{ @ptrCast(tree), @ptrCast(link) } };
}

fn devIdFromGuid(tree: *DebugTree, guid: [*:0]const u8) DevId {
    return DevId{ .value = .{ @ptrCast(tree), @ptrCast(@constCast(guid)) } };
}

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

    frame_bar_scale: f32,

    frame_index: u32,

    stored_event_count: u32,
    profile_block_count: u32,
    data_block_count: u32,

    root_profile_node: ?*DebugStoredEvent,
};

const OpenDebugBlock = struct {
    parent: ?*OpenDebugBlock,
    next_free: ?*OpenDebugBlock,

    staring_frame_index: u32,
    begin_clock: u64,
    element: ?*DebugElement,

    node: ?*DebugStoredEvent,

    group: ?*DebugVariableLink,
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
    sum: f64,
    average: f64,
    count: u32,

    pub fn begin() DebugStatistic {
        return DebugStatistic{
            .min = std.math.floatMax(f64),
            .max = -std.math.floatMax(f64),
            .sum = 0,
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

        self.sum += value;
    }

    pub fn end(self: *DebugStatistic) void {
        if (self.count != 0) {
            self.average = self.sum / @as(f32, @floatFromInt(self.count));
        } else {
            self.min = 0;
            self.max = 0;
            self.average = 0;
        }
    }
};

const ElementAddOp = enum(u32) {
    AddToGroup = 0x1,
    CreateHierarchy = 0x2,
};

pub const DebugState = struct {
    debug_arena: MemoryArena,
    per_frame_arena: MemoryArena,

    element_hash: [1024]?*DebugElement = [1]?*DebugElement{null} ** 1024,
    view_hash: [4096]*DebugView = [1]*DebugView{undefined} ** 4096,
    root_group: *DebugVariableLink,
    function_group: *DebugVariableLink,
    profile_group: *DebugVariableLink,
    tree_sentinel: DebugTree,

    paused: bool,

    total_frame_count: u32,
    viewing_frame_ordinal: u32,
    most_recent_frame_ordinal: u32,
    collation_frame_ordinal: u32,
    oldest_frame_ordinal: u32,
    frames: [MAX_FRAME_COUNT]DebugFrame = [1]DebugFrame{undefined} ** MAX_FRAME_COUNT,
    collation_frame: DebugFrame,

    root_profile_element: ?*DebugElement,

    frame_bar_lane_count: u32,
    first_thread: ?*DebugThread,
    first_free_thread: ?*DebugThread,
    first_free_block: ?*OpenDebugBlock,

    // Per-frame storage management.
    first_free_stored_event: ?*DebugStoredEvent,

    root_info_size: u32,
    root_info: [*:0]u8,

    function_info_size: u32,
    function_info: [*:0]u8,

    //
    //
    //

    dev_ui: DevUI,

    menu_position: Vector2,
    menu_active: bool,

    selected_id_count: u32,
    selected_id: [64]DevId = [1]DevId{undefined} ** 64,

    left_edge: f32 = 0,
    right_edge: f32 = 0,
    font_scale: f32 = 0,
    font_id: file_formats.FontId = undefined,

    pub fn get() ?*DebugState {
        var result: ?*DebugState = null;

        if (shared.debug_global_memory) |debug_memory| {
            result = @ptrCast(@alignCast(debug_memory.debug_state));
        }

        return result;
    }

    fn initFrame(self: *DebugState, begin_clock: u64, result: *DebugFrame) void {
        result.frame_index = self.total_frame_count;
        self.total_frame_count += 1;
        result.frame_bar_scale = 1;
        result.begin_clock = begin_clock;
    }

    fn freeFrame(self: *DebugState, frame_ordinal: u32) void {
        std.debug.assert(frame_ordinal < MAX_FRAME_COUNT);

        var freed_event_count: u32 = 0;

        var element_hash_index: u32 = 0;
        while (element_hash_index < self.element_hash.len) : (element_hash_index += 1) {
            var opt_element = self.element_hash[element_hash_index];
            while (opt_element) |element| : (opt_element = element.next_in_hash) {
                const element_frame: *DebugElementFrame = &element.frames[frame_ordinal];
                while (element_frame.oldest_event) |oldest_event| {
                    const free_event: *DebugStoredEvent = oldest_event;
                    element_frame.oldest_event = free_event.next;
                    free_event.next = self.first_free_stored_event;
                    self.first_free_stored_event = free_event;
                    freed_event_count += 1;
                }
                memory.zeroStruct(DebugElementFrame, element_frame);
            }
        }

        const frame: *DebugFrame = &self.frames[frame_ordinal];
        std.debug.assert(frame.stored_event_count == freed_event_count);

        memory.zeroStruct(DebugFrame, frame);
    }

    fn incrementFrameOrdinal(ordinal: *u32) void {
        ordinal.* = (ordinal.* + 1) % MAX_FRAME_COUNT;
    }

    fn freeOldestFrame(self: *DebugState) void {
        self.freeFrame(self.oldest_frame_ordinal);

        if (self.oldest_frame_ordinal == self.most_recent_frame_ordinal) {
            incrementFrameOrdinal(&self.most_recent_frame_ordinal);
        }
        incrementFrameOrdinal(&self.oldest_frame_ordinal);
    }

    fn getCollationFrame(self: *DebugState) *DebugFrame {
        return &self.frames[self.collation_frame_ordinal];
    }

    fn storeEvent(self: *DebugState, element: *DebugElement, event: *DebugEvent) *DebugStoredEvent {
        var result: ?*DebugStoredEvent = null;

        while (result == null) {
            result = self.first_free_stored_event;
            if (result != null) {
                self.first_free_stored_event = result.?.next;
            } else {
                result = self.per_frame_arena.pushStruct(
                    DebugStoredEvent,
                    ArenaPushParams.aligned(@alignOf(DebugStoredEvent), true),
                );
            }
        }

        const collation_frame: *DebugFrame = self.getCollationFrame();

        result.?.next = null;
        result.?.data = .{ .event = event.* };

        collation_frame.stored_event_count += 1;

        var frame: *DebugElementFrame = &element.frames[self.collation_frame_ordinal];
        if (frame.most_recent_event != null) {
            frame.most_recent_event.?.next = result;
            frame.most_recent_event = result;
        } else {
            frame.oldest_event = result;
            frame.most_recent_event = result;
        }

        return result.?;
    }

    fn allocateOpenDebugBlock(
        self: *DebugState,
        element: ?*DebugElement,
        frame_index: u32,
        event: *DebugEvent,
        first_open_block: *?*OpenDebugBlock,
    ) *OpenDebugBlock {
        var result: ?*OpenDebugBlock = self.first_free_block;
        if (result) |block| {
            self.first_free_block = block.next_free;
        } else {
            result = self.debug_arena.pushStruct(
                OpenDebugBlock,
                ArenaPushParams.aligned(@alignOf(OpenDebugBlock), true),
            );
        }

        result.?.staring_frame_index = frame_index;
        result.?.element = element;
        result.?.begin_clock = event.clock;
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

    fn getOrCreateGroupWithName(
        self: *DebugState,
        parent: *DebugVariableLink,
        name_length: u32,
        name: [*:0]const u8,
    ) ?*DebugVariableLink {
        var result: ?*DebugVariableLink = null;
        var link: *DebugVariableLink = parent.first_child;
        while (link != parent.getSentinel()) : (link = link.next) {
            if (shared.stringsWithOneLengthAreEqual(name, name_length, link.name)) {
                result = link;
            }
        }

        if (result == null) {
            result = self.createVariableLink(name_length, name);
            _ = addLinkToGroup(parent, result.?);
        }

        return result;
    }

    fn getGroupForHierarchicalName(
        self: *DebugState,
        parent: *DebugVariableLink,
        name: [*:0]const u8,
        create_terminal: bool,
    ) ?*DebugVariableLink {
        var result: ?*DebugVariableLink = parent;
        var first_separator: ?[*]const u8 = null;
        var opt_scan: ?[*]const u8 = @ptrCast(name);
        while (opt_scan) |scan| : (opt_scan = scan + 1) {
            if (scan[0] == 0) {
                break;
            }

            if (scan[0] == '/') {
                first_separator = scan;
                break;
            }
        }

        if (first_separator != null or create_terminal) {
            var name_length: u32 = 0;
            if (first_separator != null) {
                name_length = @intCast(@intFromPtr(first_separator.?) - @intFromPtr(name));
            } else {
                name_length = @intCast(@intFromPtr(opt_scan.?) - @intFromPtr(name));
            }

            const sub_name_length: u32 = name_length;
            if (self.getOrCreateGroupWithName(parent, sub_name_length, name)) |sub_group| {
                result = sub_group;

                if (first_separator != null) {
                    const sub_name: [*:0]const u8 = @ptrCast(first_separator.? + 1);
                    result = self.getGroupForHierarchicalName(sub_group, sub_name, create_terminal);
                }
            }
        }

        return result;
    }

    fn freeVariableGroup(self: *DebugState, group: ?*DebugVariableLink) void {
        _ = self;
        _ = group;

        // Not defined.
        unreachable;
    }

    fn createVariableLink(
        self: *DebugState,
        opt_name_length: ?u32,
        opt_name: ?[*:0]const u8,
    ) *DebugVariableLink {
        var link: *DebugVariableLink = self.debug_arena.pushStruct(
            DebugVariableLink,
            ArenaPushParams.aligned(@alignOf(DebugVariableLink), true),
        );
        link.getSentinel().next = link.getSentinel();
        link.getSentinel().prev = link.getSentinel();
        link.next = undefined;
        link.prev = undefined;
        link.element = null;

        if (opt_name_length) |name_length| {
            if (opt_name) |name| {
                link.name = self.debug_arena.pushAndNullTerminateString(name_length, name);
            }
        }

        return link;
    }

    pub fn addElementToGroup(
        self: *DebugState,
        opt_parent: ?*DebugVariableLink,
        element: ?*DebugElement,
    ) *DebugVariableLink {
        const link: *DebugVariableLink = self.createVariableLink(null, null);

        if (opt_parent) |parent| {
            link.next = parent.getSentinel();
            link.prev = parent.getSentinel().prev;
            link.next.prev = link;
            link.prev.next = link;

            link.first_child = link.getSentinel();
            link.last_child = link.getSentinel();
            link.element = element;
        }

        return link;
    }

    pub fn addLinkToGroup(
        parent: *DebugVariableLink,
        link: *DebugVariableLink,
    ) void {
        link.next = parent.getSentinel();
        link.prev = parent.getSentinel().prev;
        link.next.prev = link;
        link.prev.next = link;
    }

    fn cloneVariableLink(self: *DebugState, source: *DebugVariableLink) *DebugVariableLink {
        return self.cloneVariableLinkInto(null, source);
    }

    fn cloneVariableLinkInto(
        self: *DebugState,
        dest_group: ?*DebugVariableLink,
        source: *DebugVariableLink,
    ) *DebugVariableLink {
        const dest: *DebugVariableLink = self.addElementToGroup(dest_group, source.element);
        dest.name = source.name;

        if (source.canHaveChildren()) {
            var child: *DebugVariableLink = source.first_child;
            while (child != source.getSentinel()) : (child = child.next) {
                _ = self.cloneVariableLinkInto(dest, child);
            }
        }
        return dest;
    }

    fn parseName(guid: [*:0]const u8, proper_name: ?[*:0]const u8) DebugParsedName {
        var result = DebugParsedName{};
        var pipe_count: u32 = 0;
        var scan = guid;
        while (scan[0] != 0) : (scan += 1) {
            if (scan[0] == '|') {
                if (pipe_count == 0) {
                    result.file_name_count = @intCast(@intFromPtr(scan) - @intFromPtr(guid));
                    result.line_number = @intCast(shared.i32FromZ(scan + 1));
                } else if (pipe_count == 2) {
                    result.name_starts_at = @intCast(@intFromPtr(scan) - @intFromPtr(guid) + 1);
                }
                pipe_count += 1;
            }

            shared.updateStringHash(&result.hash_value, scan[0]);
        }
        if (false) {
            result.name_length = @intCast((@intFromPtr(scan) - @intFromPtr(guid)) - result.name_starts_at);
            result.name = guid + result.name_starts_at;
        } else {
            result.name_length = types.stringLength(proper_name);
            result.name = proper_name;
        }
        return result;
    }

    fn getElementFromGuid(self: *DebugState, opt_guid: ?[*:0]const u8) ?*DebugElement {
        var result: ?*DebugElement = null;
        if (opt_guid) |guid| {
            const parsed_name: DebugParsedName = parseName(guid, null);
            const index: u32 = @mod(parsed_name.hash_value, @as(u32, @intCast(self.element_hash.len)));
            result = self.getElementFromGuidHash(index, guid);
        }
        return result;
    }

    fn getElementFromGuidHash(self: *DebugState, index: u32, guid: [*:0]const u8) ?*DebugElement {
        var result: ?*DebugElement = null;
        var opt_chain: ?*DebugElement = self.element_hash[index];
        while (opt_chain) |chain| : (opt_chain = chain.next_in_hash) {
            if (shared.stringsAreEqual(chain.guid, guid)) {
                result = chain;
                break;
            }
        }
        return result;
    }

    fn getElementFromEvent(
        self: *DebugState,
        event: *DebugEvent,
        parent: ?*DebugVariableLink,
        op: u32,
    ) ?*DebugElement {
        var result: ?*DebugElement = null;
        const parsed_name: DebugParsedName = parseName(event.guid, event.name);
        const index: u32 = @mod(parsed_name.hash_value, @as(u32, @intCast(self.element_hash.len)));
        result = self.getElementFromGuidHash(index, event.guid);

        if (result == null) {
            result = self.debug_arena.pushStruct(
                DebugElement,
                ArenaPushParams.aligned(@alignOf(DebugElement), true),
            );

            result.?.guid = event.guid;
            result.?.guid = self.debug_arena.pushStringZ(event.guid);
            result.?.file_name_count = parsed_name.file_name_count;
            result.?.line_number = parsed_name.line_number;
            result.?.next_in_hash = self.element_hash[index];
            result.?.name = self.debug_arena.pushStringZ(event.name);
            result.?.type = event.event_type;
            self.element_hash[index] = result;

            var opt_parent_group = parent;
            if (op & @intFromEnum(ElementAddOp.CreateHierarchy) != 0) {
                if (self.getGroupForHierarchicalName(
                    parent orelse self.root_group,
                    result.?.getName(),
                    false,
                )) |hierarchy_parent_group| {
                    opt_parent_group = hierarchy_parent_group;
                }
            }

            if (op & @intFromEnum(ElementAddOp.AddToGroup) != 0) {
                if (opt_parent_group) |parent_group| {
                    _ = self.addElementToGroup(parent_group, result.?);
                }
            }
        }

        return result;
    }

    pub fn collateDebugRecords(self: *DebugState, event_count: u32, event_array: [*]DebugEvent) void {
        var event_index: u32 = 0;
        while (event_index < event_count) : (event_index += 1) {
            const event: *DebugEvent = &event_array[event_index];
            if (event.event_type == .FrameMarker) {
                var collation_frame: *DebugFrame = self.getCollationFrame();

                collation_frame.end_clock = event.clock;
                collation_frame.wall_seconds_elapsed = event.data.f32;

                if (collation_frame.root_profile_node) |root_profile_node| {
                    root_profile_node.data.profile_node.duration =
                        collation_frame.end_clock -% collation_frame.begin_clock;
                }

                self.total_frame_count += 1;

                if (self.paused) {
                    self.freeFrame(self.collation_frame_ordinal);
                } else {
                    self.most_recent_frame_ordinal = self.collation_frame_ordinal;
                    incrementFrameOrdinal(&self.collation_frame_ordinal);
                    if (self.collation_frame_ordinal == self.oldest_frame_ordinal) {
                        self.freeOldestFrame();
                    }
                    collation_frame = self.getCollationFrame();
                }

                self.initFrame(event.clock, collation_frame);
            } else {
                var collation_frame: *DebugFrame = self.getCollationFrame();

                const frame_index: u32 = self.total_frame_count -% 1;
                const thread: *DebugThread = self.getDebugThread(event.thread_id);

                var default_parent_group: *DebugVariableLink = self.root_group;
                if (thread.first_open_data_block) |first_open_data_block| {
                    if (first_open_data_block.group) |group| {
                        default_parent_group = group;
                    }
                }

                switch (event.event_type) {
                    .BeginBlock => {
                        collation_frame.profile_block_count += 1;

                        if (self.getElementFromEvent(
                            event,
                            self.profile_group,
                            @intFromEnum(ElementAddOp.AddToGroup),
                        )) |element| {
                            var stored_event: *DebugStoredEvent = self.storeEvent(element, event);
                            stored_event.data = .{ .profile_node = .{} };
                            var node = &stored_event.data.profile_node;

                            var parent_event: ?*DebugStoredEvent = collation_frame.root_profile_node;
                            var clock_basis: u64 = collation_frame.begin_clock;
                            if (thread.first_open_code_block) |first_open_code_block| {
                                parent_event = first_open_code_block.node;
                                clock_basis = first_open_code_block.begin_clock;
                            } else if (parent_event == null) {
                                var null_event: DebugEvent = .{};
                                parent_event = self.storeEvent(self.root_profile_element.?, &null_event);
                                parent_event.?.data = .{
                                    .profile_node = .{
                                        .element = null,
                                        .first_child = null,
                                        .next_same_parent = null,
                                        .parent_relative_clock = 0,
                                        .duration = 0,
                                        .duration_of_children = 0,
                                        .thread_ordinal = 0,
                                        .core_index = 0,
                                    },
                                };
                                clock_basis = collation_frame.begin_clock;
                                collation_frame.root_profile_node = parent_event;
                            }

                            node.element = element;
                            node.first_child = null;
                            node.next_same_parent = null;
                            node.parent_relative_clock = event.clock -% clock_basis;
                            node.duration = 0;
                            node.duration_of_children = 0;
                            node.thread_ordinal = @intCast(thread.lane_index);
                            node.core_index = event.core_index;

                            node.next_same_parent = parent_event.?.data.profile_node.first_child;
                            parent_event.?.data.profile_node.first_child = stored_event;

                            var debug_block: *OpenDebugBlock = self.allocateOpenDebugBlock(
                                element,
                                frame_index,
                                event,
                                &thread.first_open_code_block,
                            );
                            debug_block.node = stored_event;
                        }
                    },
                    .EndBlock => {
                        if (thread.first_open_code_block) |matching_block| {
                            std.debug.assert(thread.id == event.thread_id);

                            var node: *DebugProfileNode = &matching_block.node.?.data.profile_node;
                            node.duration = event.clock -% matching_block.begin_clock;

                            self.deallocateOpenDebugBlock(&thread.first_open_code_block);

                            if (thread.first_open_code_block) |parent_block| {
                                if (parent_block.node) |parent_node| {
                                    parent_node.data.profile_node.duration_of_children += node.duration;
                                }
                            }
                        }
                    },
                    .OpenDataBlock => {
                        collation_frame.data_block_count += 1;

                        var debug_block: *OpenDebugBlock =
                            self.allocateOpenDebugBlock(null, frame_index, event, &thread.first_open_data_block);

                        const parsed_name: DebugParsedName = parseName(event.guid, event.name);
                        debug_block.group =
                            self.getGroupForHierarchicalName(default_parent_group, parsed_name.name orelse "", true);
                    },
                    .CloseDataBlock => {
                        std.debug.assert(thread.id == event.thread_id);

                        self.deallocateOpenDebugBlock(&thread.first_open_data_block);
                    },
                    else => {
                        if (self.getElementFromEvent(
                            event,
                            default_parent_group,
                            @intFromEnum(ElementAddOp.AddToGroup) | @intFromEnum(ElementAddOp.CreateHierarchy),
                        )) |element| {
                            element.original_guid = event.guid;
                            _ = self.storeEvent(element, event);
                        }
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
            result = self.first_free_thread;
            if (result != null) {
                self.first_free_thread = result.?.next;
            } else {
                result = self.debug_arena.pushStruct(DebugThread, ArenaPushParams.aligned(@alignOf(DebugThread), true));
            }

            result.?.id = thread_id;
            result.?.lane_index = self.frame_bar_lane_count;
            self.frame_bar_lane_count += 1;
            result.?.first_open_code_block = null;
            result.?.first_open_data_block = null;
            result.?.next = self.first_thread;
            self.first_thread = result.?;
        }

        return result.?;
    }

    fn addTree(self: *DebugState, group: ?*DebugVariableLink, position: Vector2) *DebugTree {
        var tree: *DebugTree = self.debug_arena.pushStruct(DebugTree, ArenaPushParams.aligned(@alignOf(DebugTree), true));
        tree.group = group;
        tree.ui_position = position;

        tree.next = self.tree_sentinel.next;
        tree.prev = &self.tree_sentinel;
        tree.next.?.prev = tree;
        tree.prev.?.next = tree;

        return tree;
    }

    pub fn isSelected(self: *DebugState, id: DevId) bool {
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

    pub fn addToSelection(self: *DebugState, id: DevId) void {
        if (self.selected_id_count < self.selected_id.len and !self.isSelected(id)) {
            self.selected_id[self.selected_id_count] = id;
            self.selected_id_count += 1;
        }
    }

    fn getOrCreateDebugView(self: *DebugState, id: DevId) *DebugView {
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
            result = self.debug_arena.pushStruct(DebugView, ArenaPushParams.aligned(@alignOf(DebugView), true));
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
    ShowEntireGUID = 0x80,
    Value = 0x100,

    pub fn toInt(self: DebugVariableToTextFlag) u32 {
        return @intFromEnum(self);
    }

    pub fn declarationFlags() u32 {
        return DebugVariableToTextFlag.Declaration.toInt() |
            DebugVariableToTextFlag.Name.toInt() |
            DebugVariableToTextFlag.Value.toInt() |
            DebugVariableToTextFlag.Type.toInt() |
            DebugVariableToTextFlag.SemiColonEnd.toInt() |
            DebugVariableToTextFlag.LineFeedEnd.toInt();
    }

    pub fn displayFlags() u32 {
        return DebugVariableToTextFlag.Name.toInt() |
            DebugVariableToTextFlag.NullTerminator.toInt() |
            DebugVariableToTextFlag.Value.toInt() |
            DebugVariableToTextFlag.Colon.toInt();
    }

    pub fn blockTitleFlags() u32 {
        return DebugVariableToTextFlag.Name.toInt() |
            DebugVariableToTextFlag.NullTerminator.toInt() |
            DebugVariableToTextFlag.Colon.toInt();
    }
};

pub const DebugTree = struct {
    ui_position: Vector2,
    group: ?*DebugVariableLink,

    prev: ?*DebugTree,
    next: ?*DebugTree,
};

const DebugViewType = enum(u32) {
    Unknown,
    Basic,
    InlineBlock,
    Collapsible,
    ProfileGraph,
    ArenaGraph,
};

const DebugViewDataType = enum(u32) {
    inline_block,
    collapsible,
    profile_graph,
    arena_graph,
};

const DebugView = struct {
    id: DevId,
    next_in_hash: *DebugView = undefined,

    view_type: DebugViewType,
    data: union(DebugViewDataType) {
        inline_block: DebugViewInlineBlock,
        collapsible: DebugViewCollapsible,
        profile_graph: DebugViewProfileGraph,
        arena_graph: DebugViewArenaGraph,
    },
};

const DebugViewInlineBlock = struct {
    dimension: Vector2,
};

const DebugViewCollapsible = struct {
    expanded_always: bool,
    expanded_alt_view: bool,
};

const DebugViewProfileGraph = struct {
    block: DebugViewInlineBlock,
    guid: ?[*:0]const u8,
};

const DebugViewArenaGraph = struct {
    block: DebugViewInlineBlock,
};

const DebugProfileNode = extern struct {
    element: ?*DebugElement = null,
    first_child: ?*DebugStoredEvent = null,
    next_same_parent: ?*DebugStoredEvent = null,
    duration: u64 = 0,
    duration_of_children: u64 = 0,
    reserved: u32 = 0,
    parent_relative_clock: u64 = 0,
    thread_ordinal: u16 = 0,
    core_index: u16 = 0,
};

pub const DebugStoredEvent = struct {
    next: ?*DebugStoredEvent,
    data: union {
        event: DebugEvent,
        profile_node: DebugProfileNode,
    },
};

const DebugElementFrame = struct {
    oldest_event: ?*DebugStoredEvent,
    most_recent_event: ?*DebugStoredEvent,
};

pub const DebugElement = struct {
    original_guid: [*:0]const u8, // Can't be printed, it is only used for checking pointer equality.
    guid: [*:0]const u8,
    file_name_count: u32,
    line_number: u32,
    name: [*:0]const u8,

    type: DebugType,

    value_was_edited: bool,

    frames: [MAX_FRAME_COUNT]DebugElementFrame = [1]DebugElementFrame{undefined} ** MAX_FRAME_COUNT,

    next_in_hash: ?*DebugElement,

    pub fn getName(self: *DebugElement) [*:0]const u8 {
        return self.name;
    }
};

pub const DebugParsedName = struct {
    hash_value: u32 = 0,
    file_name_count: u32 = 0,
    name_starts_at: u32 = 0,
    line_number: u32 = 0,

    name_length: u32 = 0,
    name: ?[*:0]const u8 = null,
};

pub const DebugVariableLink = struct {
    next: *DebugVariableLink,
    prev: *DebugVariableLink,

    first_child: *DebugVariableLink,
    last_child: *DebugVariableLink,

    name: [*:0]const u8,
    element: ?*DebugElement,

    pub fn getSentinel(self: *DebugVariableLink) *DebugVariableLink {
        const result: *DebugVariableLink = @ptrCast(&self.first_child);
        return result;
    }

    pub fn canHaveChildren(self: *DebugVariableLink) bool {
        return self.element == null; //self.first_child != self.getSentinel();
    }
};

fn debugEventToText(buffer: [*]u8, end: [*]u8, element: *DebugElement, event: *DebugEvent, flags: u32) usize {
    var at: [*]u8 = buffer;

    if (flags & DebugVariableToTextFlag.Declaration.toInt() != 0) {
        at += shared.formatString(end - at, at, "%s", .{event.prefixString()});
    }

    if (flags & DebugVariableToTextFlag.Name.toInt() != 0) {
        var name = element.guid;

        if (flags & DebugVariableToTextFlag.ShowEntireGUID.toInt() == 0) {
            var scan = name;
            while (scan[0] != 0) : (scan += 1) {
                if (scan[0] == '|' and scan[1] != 0) {
                    name = scan + 1;
                }
            }
        }

        at += shared.formatString(end - at, at, "%s", .{name});
    }

    if (flags & DebugVariableToTextFlag.Colon.toInt() != 0) {
        at += shared.formatString(end - at, at, ": ", .{});
    }

    if (event.event_type != .OpenDataBlock and flags & DebugVariableToTextFlag.Type.toInt() != 0) {
        at += shared.formatString(end - at, at, ": %s = ", .{event.typeString()});
    }

    if (flags & DebugVariableToTextFlag.Declaration.toInt() != 0) {
        switch (event.event_type) {
            .Vector2, .Vector3, .Vector4 => {
                at += shared.formatString(end - at, at, "%s.new", .{event.typeString()});
            },
            else => {},
        }
    }

    if (flags & DebugVariableToTextFlag.Value.toInt() != 0) {
        switch (event.event_type) {
            .StringPointer => {
                at += shared.formatString(end - at, at, "%s", .{@as([*:0]const u8, @ptrCast(event.data.string_pointer))});
            },
            .bool => {
                at += shared.formatString(end - at, at, "%s", .{
                    @as([*:0]const u8, @ptrCast(if (event.data.bool) "true" else "false")),
                });
            },
            .u8 => {
                at += shared.formatString(end - at, at, "%u", .{event.data.u8});
            },
            .u16 => {
                at += shared.formatString(end - at, at, "%u", .{event.data.u16});
            },
            .u32 => {
                at += shared.formatString(end - at, at, "%u", .{event.data.u32});
            },
            .i32 => {
                at += shared.formatString(end - at, at, "%i", .{event.data.i32});
            },
            .f32 => {
                at += shared.formatString(end - at, at, "%f", .{event.data.f32});
            },
            .Vector2 => {
                at += shared.formatString(end - at, at, "(%f, %f)", .{ event.data.Vector2.x(), event.data.Vector2.y() });
            },
            .Vector3 => {
                at += shared.formatString(end - at, at, "(%f, %f, %f)", .{
                    event.data.Vector3.x(),
                    event.data.Vector3.y(),
                    event.data.Vector3.z(),
                });
            },
            .Vector4 => {
                at += shared.formatString(end - at, at, "(%f, %f, %f, %f)", .{
                    event.data.Vector4.x(),
                    event.data.Vector4.y(),
                    event.data.Vector4.z(),
                    event.data.Vector4.w(),
                });
            },
            .Rectangle2 => {
                at += shared.formatString(end - at, at, "(%f, %f, %f, %f)", .{
                    event.data.Rectangle2.min.x(),
                    event.data.Rectangle2.min.y(),
                    event.data.Rectangle2.max.x(),
                    event.data.Rectangle2.max.y(),
                });
            },
            .Rectangle3 => {
                at += shared.formatString(end - at, at, "(%f, %f, %f, %f, %f, %f)", .{
                    event.data.Rectangle3.min.x(),
                    event.data.Rectangle3.min.y(),
                    event.data.Rectangle3.min.z(),
                    event.data.Rectangle3.max.x(),
                    event.data.Rectangle3.max.y(),
                    event.data.Rectangle3.max.z(),
                });
            },
            .BitmapId => {},
            .Enum => {
                at += shared.formatString(end - at, at, "%u", .{event.data.Enum});
            },
            else => {
                at += shared.formatString(end - at, at, "UNHANDLED: %s", .{event.guid});
            },
        }
    }

    if (event.event_type != .OpenDataBlock and flags & DebugVariableToTextFlag.SemiColonEnd.toInt() != 0) {
        at += shared.formatString(end - at, at, ";", .{});
    }

    if (flags & DebugVariableToTextFlag.LineFeedEnd.toInt() != 0) {
        at += shared.formatString(end - at, at, "\n", .{});
    }

    if (flags & DebugVariableToTextFlag.NullTerminator.toInt() != 0) {
        at[0] = 0;
    }

    return at - buffer;
}

fn getTotalClocks(frame: *DebugElementFrame) u64 {
    var result: u64 = 0;
    var opt_event = frame.oldest_event;
    while (opt_event) |event| : (opt_event = event.next) {
        result += event.data.profile_node.duration;
    }
    return result;
}

fn drawFrameSlider(
    debug_state: *DebugState,
    slider_id: DevId,
    total_rect: Rectangle2,
    mouse_position: Vector2,
    root_element: *DebugElement,
) void {
    const ui: *DevUI = &debug_state.dev_ui;
    const render_group: *RenderGroup = &ui.render_group;
    const frame_count: u32 = root_element.frames.len;
    if (frame_count > 0) {
        render_group.pushRectangle2(
            &ui.backing_transform,
            total_rect,
            0,
            Color.new(0, 0, 0, 0.25),
        );

        const bar_width: f32 = total_rect.getDimension().x() / @as(f32, @floatFromInt(frame_count));
        var at_x: f32 = total_rect.min.x();
        const this_min_y: f32 = total_rect.min.y();
        const this_max_y: f32 = total_rect.max.y();

        var frame_index: u32 = 0;
        while (frame_index < frame_count) : (frame_index += 1) {
            const color = Color.new(0.5, 0.5, 0.5, 1);
            var highlight_color = Color.new(1, 1, 1, 1);
            const region_rect = math.Rectangle2.new(at_x, this_min_y, at_x + bar_width, this_max_y);

            var highlight: bool = false;
            if (frame_index == debug_state.viewing_frame_ordinal) {
                highlight = true;
                highlight_color = Color.new(1, 1, 0, 1);
            }
            if (frame_index == debug_state.most_recent_frame_ordinal) {
                highlight = true;
                highlight_color = Color.new(0, 1, 0, 1);
            }
            if (frame_index == debug_state.collation_frame_ordinal) {
                highlight = true;
                highlight_color = Color.new(1, 0, 0, 1);
            }
            if (frame_index == debug_state.oldest_frame_ordinal) {
                highlight = true;
                highlight_color = Color.new(0, 0.5, 0, 1);
            }

            if (highlight) {
                render_group.pushRectangle2(&ui.ui_transform, region_rect, 0, highlight_color);
            }

            render_group.pushRectangle2Outline(&ui.ui_transform, region_rect, 1, color, 2);

            if (mouse_position.isInRectangle(region_rect)) {
                const text_buffer: TooltipBuffer = dev_ui.addLine(&ui.tooltips);
                _ = shared.formatString(text_buffer.size, text_buffer.data, "%u", .{frame_index});

                ui.next_hot_interaction = dev_ui.Interaction.setUInt32(
                    slider_id,
                    &debug_state.viewing_frame_ordinal,
                    frame_index,
                );
            }

            at_x += bar_width;
        }
    }
}

fn drawProfileIn(
    debug_state: *DebugState,
    graph_id: DevId,
    profile_rect: Rectangle2,
    mouse_position: Vector2,
    root_element: *DebugElement,
) void {
    const lane_count: u32 = debug_state.frame_bar_lane_count;
    var lane_height: f32 = 0;
    if (lane_count > 0) {
        lane_height = profile_rect.getDimension().y() / @as(f32, @floatFromInt(lane_count));
    }

    const root_frame: *DebugElementFrame = &root_element.frames[debug_state.viewing_frame_ordinal];
    const total_clock: u64 = getTotalClocks(root_frame);
    var next_x: f32 = profile_rect.min.x();
    var relative_clock: u64 = 0;

    var opt_event: ?*DebugStoredEvent = root_frame.oldest_event;
    while (opt_event) |event| : (opt_event = event.next) {
        const node: *DebugProfileNode = &event.data.profile_node;

        var event_rect: Rectangle2 = profile_rect;
        relative_clock += node.duration;
        const t: f32 = @floatCast(@as(f64, @floatFromInt(relative_clock)) / @as(f64, @floatFromInt(total_clock)));

        _ = event_rect.min.setX(next_x);

        _ = event_rect.max.setX((1 - t) * profile_rect.min.x() + t * profile_rect.max.x());
        next_x = event_rect.max.x();

        drawProfileBars(
            debug_state,
            graph_id,
            event_rect,
            mouse_position,
            node,
            lane_height,
            lane_height,
            1,
        );
    }
}

fn drawProfileBars(
    debug_state: *DebugState,
    graph_id: DevId,
    profile_rect: Rectangle2,
    mouse_position: Vector2,
    root_node: *DebugProfileNode,
    lane_stride: f32,
    lane_height: f32,
    depth_remaining: u32,
) void {
    const ui: *DevUI = &debug_state.dev_ui;
    const render_group: *RenderGroup = &ui.render_group;
    const frame_span: f32 = @floatFromInt(root_node.duration);
    const pixel_span: f32 = profile_rect.getDimension().x();
    const base_z: f32 = 100 - 10 * @as(f32, @floatFromInt(depth_remaining));
    var scale: f32 = 0;
    if (frame_span > 0) {
        scale = pixel_span / frame_span;
    }

    var opt_stored_event: ?*DebugStoredEvent = root_node.first_child;
    while (opt_stored_event) |stored_event| : (opt_stored_event = stored_event.data.profile_node.next_same_parent) {
        const node: *DebugProfileNode = &stored_event.data.profile_node;
        std.debug.assert(node.element != null);
        const element: *DebugElement = node.element.?;

        const color = debug_color_table[@intFromPtr(element.guid) % debug_color_table.len];
        const this_min_x: f32 =
            profile_rect.min.x() + scale * @as(f32, @floatFromInt(node.parent_relative_clock));
        const this_max_x: f32 =
            this_min_x + scale * @as(f32, @floatFromInt(node.duration));

        const lane_index: u32 = node.thread_ordinal;
        const lane: f32 = @as(f32, @floatFromInt(lane_index));
        const lane_y: f32 = profile_rect.max.y() - lane_stride * lane;

        const region_rect = math.Rectangle2.new(this_min_x, lane_y - lane_height, this_max_x, lane_y);
        render_group.pushRectangle2(&ui.ui_transform, region_rect, base_z, color.toColor(1));
        render_group.pushRectangle2Outline(&ui.ui_transform, region_rect, base_z + 1, Color.black(), 2);

        if (mouse_position.isInRectangle(region_rect)) {
            const text_buffer: TooltipBuffer = dev_ui.addLine(&ui.tooltips);
            _ = shared.formatString(text_buffer.size, text_buffer.data, "%s: %10ucy", .{
                element.guid,
                node.duration,
            });

            const view: *DebugView = debug_state.getOrCreateDebugView(graph_id);
            ui.next_hot_interaction = dev_ui.Interaction.setPointer(
                graph_id,
                @ptrCast(&view.data.profile_graph.guid),
                @ptrCast(element.guid),
            );
        }

        if (depth_remaining > 0) {
            drawProfileBars(
                debug_state,
                graph_id,
                region_rect,
                mouse_position,
                node,
                0,
                lane_height / 2,
                depth_remaining - 1,
            );
        }
    }
}

fn drawFrameBars(
    debug_state: *DebugState,
    graph_id: DevId,
    profile_rect: Rectangle2,
    mouse_position: Vector2,
    root_element: *DebugElement,
) void {
    const ui: *DevUI = &debug_state.dev_ui;
    const render_group: *RenderGroup = &ui.render_group;
    const frame_count: u32 = root_element.frames.len;
    const bar_width: f32 = profile_rect.getDimension().x() / @as(f32, @floatFromInt(frame_count));
    var at_x: f32 = profile_rect.min.x();

    var frame_index: u32 = 0;
    while (frame_index < frame_count) : (frame_index += 1) {
        if (root_element.frames[frame_index].most_recent_event) |root_event| {
            const root_node: *DebugProfileNode = &root_event.data.profile_node;
            const frame_span: f32 = @floatFromInt(root_node.duration);
            const pixel_span: f32 = profile_rect.getDimension().y();
            const highlight: bool = frame_index == debug_state.viewing_frame_ordinal;
            const highlight_dim: f32 = if (highlight) 1 else 0.5;
            var scale: f32 = 0;
            if (frame_span > 0) {
                scale = pixel_span / frame_span;
            }

            var opt_stored_event: ?*DebugStoredEvent = root_node.first_child;
            while (opt_stored_event) |stored_event| : (opt_stored_event = stored_event.data.profile_node.next_same_parent) {
                const node: *DebugProfileNode = &stored_event.data.profile_node;
                std.debug.assert(node.element != null);
                const element: *DebugElement = node.element.?;

                const color = debug_color_table[@intFromPtr(element.guid) % debug_color_table.len];
                const this_min_y: f32 =
                    profile_rect.min.y() + scale * @as(f32, @floatFromInt(node.parent_relative_clock));
                const this_max_y: f32 =
                    this_min_y + scale * @as(f32, @floatFromInt(node.duration));

                const region_rect = math.Rectangle2.new(at_x, this_min_y, at_x + bar_width, this_max_y);
                render_group.pushRectangle2(
                    &ui.ui_transform,
                    region_rect,
                    0,
                    color.toColor(1).scaledTo(highlight_dim),
                );
                render_group.pushRectangle2Outline(
                    &ui.ui_transform,
                    region_rect,
                    0,
                    Color.black(),
                    2,
                );

                if (mouse_position.isInRectangle(region_rect)) {
                    const text_buffer: TooltipBuffer = dev_ui.addLine(&ui.tooltips);
                    _ = shared.formatString(text_buffer.size, text_buffer.data, "%s: %10ucy", .{
                        element.guid,
                        node.duration,
                    });

                    const view: *DebugView = debug_state.getOrCreateDebugView(graph_id);
                    ui.next_hot_interaction = dev_ui.Interaction.setPointer(
                        graph_id,
                        @ptrCast(&view.data.profile_graph.guid),
                        @ptrCast(element.guid),
                    );
                }
            }
        }

        at_x += bar_width;
    }
}

fn drawArenaOccupancy(
    debug_state: *DebugState,
    graph_id: DevId,
    frame_rect: Rectangle2,
    mouse_position: Vector2,
    root_element: *DebugElement,
) void {
    _ = debug_state;
    _ = graph_id;
    _ = frame_rect;
    _ = mouse_position;
    _ = root_element;

    // const ui: *DevUI = &debug_state.dev_ui;
    // const render_group: *RenderGroup = &debug_state.dev_ui.render_group;
    // const root_frame: *DebugElementFrame = &root_element.frames[debug_state.viewing_frame_ordinal];
    // if (root_frame.oldest_event) |event| {
    //     const arena: *MemoryArena = event.data.event.data.MemoryArena;
    //     const split_point: f32 = math.lerpf(
    //         frame_rect.min.x(),
    //         frame_rect.max.x(),
    //         @floatCast(@as(f64, @floatFromInt(arena.used)) / @as(f64, @floatFromInt(arena.size))),
    //     );
    //     const used_rect = math.Rectangle2.new(
    //         frame_rect.min.x(),
    //         frame_rect.min.y(),
    //         split_point,
    //         frame_rect.max.y(),
    //     );
    //     const unused_rect = math.Rectangle2.new(
    //         split_point,
    //         frame_rect.min.y(),
    //         frame_rect.max.x(),
    //         frame_rect.max.y(),
    //     );
    //     render_group.pushRectangle2(&ui.ui_transform, used_rect, 0, Color.new(1, 0.5, 0, 1));
    //     render_group.pushRectangle2Outline(&ui.ui_transform, used_rect, 0, Color.black(), 2);
    //
    //     render_group.pushRectangle2(&ui.ui_transform, unused_rect, 0, Color.new(0, 1, 0, 1));
    //     render_group.pushRectangle2Outline(&ui.ui_transform, unused_rect, 0, Color.black(), 2);
    // }
}

const ClockEntry = struct {
    element: *DebugElement,
    stats: DebugStatistic,
};

fn drawTopClocksList(
    debug_state: *DebugState,
    graph_id: DevId,
    profile_rect: Rectangle2,
    mouse_position: Vector2,
    root_element: *DebugElement,
) void {
    _ = graph_id;
    _ = root_element;

    const ui: *DevUI = &debug_state.dev_ui;
    const temp = debug_state.debug_arena.beginTemporaryMemory();
    defer debug_state.debug_arena.endTemporaryMemory(temp);

    var link_count: u32 = 0;
    var total_time: f64 = 0;
    var link: *DebugVariableLink = debug_state.profile_group.getSentinel().next;
    while (link != debug_state.profile_group.getSentinel()) : (link = link.next) {
        link_count += 1;
    }

    const entries: [*]ClockEntry = debug_state.debug_arena.pushArray(link_count, ClockEntry, ArenaPushParams.noClear());
    const sort_a: [*]SortEntry = debug_state.debug_arena.pushArray(link_count, SortEntry, ArenaPushParams.noClear());
    const sort_b: [*]SortEntry = debug_state.debug_arena.pushArray(link_count, SortEntry, ArenaPushParams.noClear());

    link = debug_state.profile_group.getSentinel().next;
    var index: u32 = 0;
    while (link != debug_state.profile_group.getSentinel()) : (link = link.next) {
        defer index += 1;

        std.debug.assert(link.first_child == link.getSentinel());

        var entry: *ClockEntry = &entries[index];
        var sort_entry: *SortEntry = &sort_a[index];

        if (link.element) |element| {
            entry.element = element;
            entry.stats = DebugStatistic.begin();

            var opt_event: ?*DebugStoredEvent = element.frames[debug_state.viewing_frame_ordinal].oldest_event;
            while (opt_event) |event| : (opt_event = event.next) {
                const clocks_with_children: u64 = event.data.profile_node.duration;
                const clocks_without_children: u64 = clocks_with_children - event.data.profile_node.duration_of_children;
                entry.stats.accumulate(@floatFromInt(clocks_without_children));
            }

            entry.stats.end();
            total_time += entry.stats.sum;

            sort_entry.sort_key = @floatCast(-entry.stats.sum);
            sort_entry.index = index;
        }
    }

    sort.radixSort(link_count, sort_a, sort_b);

    var percent_coefficient: f64 = 0;
    if (total_time > 0) {
        percent_coefficient = 100 / total_time;
    }

    var running_sum: f64 = 0;

    var at: Vector2 = Vector2.new(profile_rect.min.x(), profile_rect.max.y() - ui.getBaseline());
    index = 0;
    while (index < link_count) : (index += 1) {
        const entry: *ClockEntry = &entries[sort_a[index].index];
        const stats: *DebugStatistic = &entry.stats;
        const element: *DebugElement = entry.element;

        running_sum += stats.sum;

        var buffer: [256]u8 = undefined;
        _ = shared.formatString(buffer.len, &buffer, "%10ucy %05.02f%% %4d %s", .{
            @as(u32, @intFromFloat(stats.sum)),
            percent_coefficient * stats.sum,
            stats.count,
            element.getName(),
        });
        dev_ui.textOutAt(
            ui,
            @ptrCast(&buffer),
            at,
            Color.white(),
            null,
        );

        const text_rect: Rectangle2 = dev_ui.getTextSizeAt(ui, @ptrCast(&buffer), at);
        if (mouse_position.isInRectangle(text_rect)) {
            const tooltip_buffer: TooltipBuffer = dev_ui.addLine(&ui.tooltips);
            _ = shared.formatString(
                tooltip_buffer.size,
                tooltip_buffer.data,
                "  %05.02fcy each; cumulative to this point: %05.02f%%",
                .{
                    math.safeRatio0f64(stats.sum, @as(f64, @floatFromInt(stats.count))),
                    percent_coefficient * running_sum,
                },
            );
        }

        if (at.y() < profile_rect.min.y()) {
            break;
        } else {
            _ = at.setY(at.y() - ui.getLineAdvance());
        }
    }
}

pub fn hit(id: DevId, z_value: f32) void {
    _ = z_value;
    if (DebugState.get()) |debug_state| {
        debug_state.dev_ui.next_hot_interaction = dev_ui.Interaction.fromId(id, .Select);
    }
}

pub fn hitStub(id: DevId, z_value: f32) void {
    _ = id;
    _ = z_value;
}

pub fn highlighted(id: DevId, outline_color: *Color) bool {
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

pub fn highlightedStub(id: DevId, outline_color: *Color) bool {
    _ = id;
    _ = outline_color;
    return false;
}

pub fn requested(id: DevId) bool {
    var result = false;

    if (DebugState.get()) |debug_state| {
        result = debug_state.isSelected(id) or id.equals(debug_state.dev_ui.hot_interaction.id);
    }

    return result;
}

pub fn requestedStub(id: DevId) bool {
    _ = id;
    return false;
}

fn drawDebugElement(
    debug_state: *DebugState,
    layout: *dev_ui.Layout,
    tree: *DebugTree,
    element: *DebugElement,
    debug_id: DevId,
    frame_ordinal: u32,
) void {
    _ = tree;

    const ui: *DevUI = &debug_state.dev_ui;
    var render_group: *RenderGroup = &ui.render_group;
    const no_transform = ui.backing_transform;
    _ = frame_ordinal;
    // const opt_stored_event: ?*DebugStoredEvent = element.frames[frame_ordinal].most_recent_event;

    // const event = &stored_event.data.event;
    var item_interaction: dev_ui.Interaction =
        dev_ui.Interaction.elementInteraction(ui, debug_id, element, .AutoModifyVariable);
    const is_hot: bool = ui.interactionIsHot(&item_interaction);
    const item_color: Color = if (is_hot) Color.new(1, 1, 0, 1) else Color.white();
    const view: *DebugView = debug_state.getOrCreateDebugView(debug_id);

    const opt_oldest_event: ?*DebugStoredEvent = element.frames[debug_state.viewing_frame_ordinal].oldest_event;

    switch (element.type) {
        .BitmapId => {
            var opt_bitmap: ?*asset.LoadedBitmap = null;
            const bitmap_scale = view.data.inline_block.dimension.y();

            const opt_event: ?*DebugEvent = if (opt_oldest_event) |oldest_event| &oldest_event.data.event else null;
            if (opt_event) |event| {
                if (render_group.assets.getBitmap(event.data.BitmapId)) |bitmap| {
                    var dim = asset_rendering.getBitmapDim(
                        &no_transform,
                        bitmap,
                        bitmap_scale,
                        Vector3.zero(),
                        0,
                        null,
                        null,
                    );
                    _ = view.data.inline_block.dimension.setX(dim.size.x());
                    opt_bitmap = bitmap;
                }
            }

            var layout_element: dev_ui.LayoutElement = layout.beginElementRectangle(&view.data.inline_block.dimension);
            layout_element.makeSizable();
            layout_element.defaultInteraction(item_interaction);
            layout_element.end();

            render_group.pushRectangle2(
                &ui.backing_transform,
                layout_element.bounds,
                0,
                Color.black(),
            );

            if (opt_bitmap) |bitmap| {
                asset_rendering.pushBitmap(
                    render_group,
                    &ui.backing_transform,
                    bitmap,
                    bitmap_scale,
                    layout_element.bounds.min.toVector3(1),
                    Color.white(),
                    0,
                    null,
                    null,
                );
            }
        },
        .MemoryArena, .ArenaOccupancy => {
            if (view.view_type != .ArenaGraph) {
                view.view_type = .ArenaGraph;
                const inline_block = view.data.inline_block;
                view.data = .{ .arena_graph = .{ .block = inline_block } };
            }

            const graph: *DebugViewArenaGraph = &view.data.arena_graph;
            if (graph.block.dimension.x() == 0 and graph.block.dimension.y() == 0) {
                graph.block.dimension = Vector2.new(1400, 100);
            }

            layout.beginRow();
            layout.label(std.mem.span(element.getName()));
            layout.booleanButton(
                "Occupancy",
                element.type == .ArenaOccupancy,
                dev_ui.Interaction.setUInt32(debug_id, &element.type, @intFromEnum(DebugType.ArenaOccupancy)),
            );
            layout.endRow();

            var layout_element: dev_ui.LayoutElement = layout.beginElementRectangle(&graph.block.dimension);
            layout_element.makeSizable();
            layout_element.end();

            render_group.pushRectangle2(
                &ui.backing_transform,
                layout_element.bounds,
                0,
                Color.new(0, 0, 0, 0.75),
            );

            const transient_clip_rect: TransientClipRect = .initWith(
                render_group,
                render_group.getClipRectByRectangle(
                    &ui.backing_transform,
                    layout_element.bounds,
                    0,
                ),
            );
            defer transient_clip_rect.restore();

            switch (element.type) {
                .ArenaOccupancy => {
                    drawArenaOccupancy(
                        debug_state,
                        debug_id,
                        layout_element.bounds,
                        layout.mouse_position,
                        element,
                    );
                },
                else => {},
            }
        },
        .ThreadIntervalGraph, .FrameBarGraph, .TopClocksList => {
            if (view.view_type != .ProfileGraph) {
                view.view_type = .ProfileGraph;
                const inline_block = view.data.inline_block;
                view.data = .{ .profile_graph = .{ .guid = null, .block = inline_block } };
            }

            const graph: *DebugViewProfileGraph = &view.data.profile_graph;
            if (graph.block.dimension.x() == 0 and graph.block.dimension.y() == 0) {
                graph.block.dimension = Vector2.new(1400, 280);
            }

            layout.beginRow();
            layout.actionButton("Root", dev_ui.Interaction.setPointer(debug_id, @ptrCast(&graph.guid), null));
            layout.booleanButton(
                "Threads",
                element.type == .ThreadIntervalGraph,
                dev_ui.Interaction.setUInt32(debug_id, &element.type, @intFromEnum(DebugType.ThreadIntervalGraph)),
            );
            layout.booleanButton(
                "Frames",
                element.type == .FrameBarGraph,
                dev_ui.Interaction.setUInt32(debug_id, &element.type, @intFromEnum(DebugType.FrameBarGraph)),
            );
            layout.booleanButton(
                "Clocks",
                element.type == .TopClocksList,
                dev_ui.Interaction.setUInt32(debug_id, &element.type, @intFromEnum(DebugType.TopClocksList)),
            );
            layout.endRow();

            var layout_element: dev_ui.LayoutElement = layout.beginElementRectangle(&graph.block.dimension);
            layout_element.makeSizable();
            layout_element.end();

            render_group.pushRectangle2(
                &ui.backing_transform,
                layout_element.bounds,
                0,
                Color.new(0, 0, 0, 0.75),
            );

            const transient_clip_rect: TransientClipRect = .initWith(
                render_group,
                render_group.getClipRectByRectangle(
                    &ui.backing_transform,
                    layout_element.bounds,
                    0,
                ),
            );
            defer transient_clip_rect.restore();

            var opt_viewing_element: ?*DebugElement =
                debug_state.getElementFromGuid(view.data.profile_graph.guid);

            if (opt_viewing_element == null) {
                opt_viewing_element = debug_state.root_profile_element;
            }

            if (opt_viewing_element) |viewing_element| {
                switch (element.type) {
                    .ThreadIntervalGraph => {
                        drawProfileIn(
                            debug_state,
                            debug_id,
                            layout_element.bounds,
                            layout.mouse_position,
                            viewing_element,
                        );
                    },
                    .FrameBarGraph => {
                        drawFrameBars(
                            debug_state,
                            debug_id,
                            layout_element.bounds,
                            layout.mouse_position,
                            viewing_element,
                        );
                    },
                    .TopClocksList => {
                        drawTopClocksList(
                            debug_state,
                            debug_id,
                            layout_element.bounds,
                            layout.mouse_position,
                            viewing_element,
                        );
                    },
                    else => {},
                }
            }
        },
        .FrameSlider => {
            var dimension: *Vector2 = &view.data.inline_block.dimension;
            if (dimension.x() == 0 and dimension.y() == 0) {
                _ = dimension.setX(1400);
                _ = dimension.setY(32);
            }

            var layout_element: dev_ui.LayoutElement = layout.beginElementRectangle(dimension);
            layout_element.makeSizable();
            layout_element.end();

            layout.beginRow();
            layout.booleanButton(
                "Pause",
                debug_state.paused,
                dev_ui.Interaction.setBool(debug_id, &debug_state.paused, !debug_state.paused),
            );
            layout.actionButton(
                "Oldest",
                dev_ui.Interaction.setUInt32(
                    debug_id,
                    &debug_state.viewing_frame_ordinal,
                    debug_state.oldest_frame_ordinal,
                ),
            );
            layout.actionButton(
                "Most Recent",
                dev_ui.Interaction.setUInt32(
                    debug_id,
                    &debug_state.viewing_frame_ordinal,
                    debug_state.most_recent_frame_ordinal,
                ),
            );
            layout.endRow();

            drawFrameSlider(
                debug_state,
                debug_id,
                layout_element.bounds,
                layout.mouse_position,
                element,
            );
        },
        .LastFrameInfo => {
            const most_recent_frame: *DebugFrame = &debug_state.frames[debug_state.viewing_frame_ordinal];
            var text: [128:0]u8 = undefined;
            _ = shared.formatString(text.len, &text, "Viewing frame time: %.02fms %de %dp %dd", .{
                most_recent_frame.wall_seconds_elapsed * 1000,
                most_recent_frame.stored_event_count,
                most_recent_frame.profile_block_count,
                most_recent_frame.data_block_count,
            });
            _ = dev_ui.basicTextElement(&text, layout, item_interaction, null, null, null, null);
        },
        .DebugMemoryInfo => {
            // var text: [128:0]u8 = undefined;
            // _ = shared.formatString(text.len, &text, "Per-frame arena space remaining: %ukb", .{
            //     debug_state.per_frame_arena.getRemainingSize(ArenaPushParams.alignedNoClear(1)) / 1024,
            // });
            // _ = dev_ui.basicTextElement(&text, layout, item_interaction, null, null, null, null);
        },
        else => {
            var null_event: DebugEvent = .{
                .guid = element.guid,
                .event_type = element.type,
            };
            const event: *DebugEvent = if (opt_oldest_event) |oldest_event| &oldest_event.data.event else &null_event;
            var text: [256:0]u8 = undefined;
            _ = debugEventToText(&text, @ptrFromInt(@intFromPtr(&text) + text.len), element, event, DebugVariableToTextFlag.displayFlags());
            _ = dev_ui.basicTextElement(&text, layout, item_interaction, item_color, null, null, null);
        },
    }
}

fn drawTreeLink(debug_state: *DebugState, layout: *dev_ui.Layout, tree: *DebugTree, link: *DebugVariableLink) void {
    const ui: *DevUI = &debug_state.dev_ui;
    const frame_ordinal: u32 = debug_state.most_recent_frame_ordinal;

    if (link.canHaveChildren()) {
        const id: DevId = devIdFromLink(tree, link);
        const debug_id: DevId = devIdFromLink(tree, link);
        const view: *DebugView = debug_state.getOrCreateDebugView(debug_id);
        var item_interaction: dev_ui.Interaction = dev_ui.Interaction.fromId(id, .ToggleExpansion);

        if (ui.alt_ui) {
            item_interaction = dev_ui.Interaction.fromLink(link, .TearValue);
        }

        const text = std.mem.span(link.name);
        const text_bounds = dev_ui.getTextSize(ui, text);
        var dim: Vector2 = Vector2.new(text_bounds.getDimension().x(), layout.line_advance);

        var element: dev_ui.LayoutElement = layout.beginElementRectangle(&dim);
        element.defaultInteraction(item_interaction);
        element.end();

        const is_hot: bool = ui.interactionIsHot(&item_interaction);
        const item_color: Color = if (is_hot) Color.new(1, 1, 0, 1) else Color.white();

        const text_position: Vector2 = Vector2.new(
            element.bounds.min.x(),
            element.bounds.max.y() - ui.getBaseline(),
        );
        dev_ui.textOutAt(ui, text, text_position, item_color, null);

        if (view.data == .collapsible and view.data.collapsible.expanded_always) {
            layout.depth += 1;

            var sublink: *DebugVariableLink = link.first_child;
            while (sublink != link.getSentinel()) : (sublink = sublink.next) {
                drawTreeLink(debug_state, layout, tree, sublink);
            }

            layout.depth -= 1;
        }
    } else {
        const debug_id = devIdFromLink(tree, link);
        drawDebugElement(debug_state, layout, tree, link.element.?, debug_id, frame_ordinal);
    }
}

fn drawTrees(debug_state: *DebugState, mouse_position: Vector2) void {
    const ui: *DevUI = &debug_state.dev_ui;
    const render_group: *RenderGroup = &ui.render_group;
    var opt_tree: ?*DebugTree = debug_state.tree_sentinel.next;

    while (opt_tree) |tree| : (opt_tree = tree.next) {
        if (tree == &debug_state.tree_sentinel) {
            break;
        }

        var layout: dev_ui.Layout = dev_ui.Layout.begin(ui, tree.ui_position);

        if (tree.group) |tree_group| {
            drawTreeLink(debug_state, &layout, tree, tree_group);
        }

        const move_interaction: dev_ui.Interaction = dev_ui.Interaction{
            .interaction_type = .Move,
            .data = .{ .position = &tree.ui_position },
        };
        const move_box_color: Color =
            if (ui.interactionIsHot(&move_interaction)) Color.new(1, 1, 0, 1) else Color.white();
        const move_box: Rectangle2 = Rectangle2.fromCenterHalfDimension(
            tree.ui_position.minus(Vector2.new(4, 4)),
            Vector2.new(4, 4),
        );
        render_group.pushRectangle2(&ObjectTransform.defaultFlat(), move_box, 0, move_box_color);

        if (mouse_position.isInRectangle(move_box)) {
            ui.next_hot_interaction = move_interaction;
        }

        layout.end();
    }

    // var new_hot_menu_index: u32 = debug_variable_list.len;
    // var best_distance_sq: f32 = std.math.floatMax(f32);
    //
    // const menu_radius: f32 = 400;
    // const angle_step: f32 = math.TAU32 / @as(f32, @floatFromInt(debug_variable_list.len));
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
    //     const text_bounds: Rectangle2 = dev_ui.getTextSize(debug_state, text);
    //     dev_ui.textOutAt(text, text_position.minus(text_bounds.getDimension().scaledTo(0.5)), item_color);
    // }
    //
    // if (mouse_position.minus(debug_state.menu_position).lengthSquared() > math.square(menu_radius)) {
    //     debug_state.hot_menu_index = new_hot_menu_index;
    // } else {
    //     debug_state.hot_menu_index = debug_variable_list.len;
    // }
}

fn beginInteract(debug_state: *DebugState, input: *const shared.GameInput, mouse_position: Vector2) void {
    const ui: *DevUI = &debug_state.dev_ui;
    const frame_ordinal: u32 = debug_state.most_recent_frame_ordinal;
    if (ui.hot_interaction.interaction_type != .None) {
        if (ui.hot_interaction.interaction_type == .AutoModifyVariable) {
            switch (ui.hot_interaction.data.element.?.frames[frame_ordinal]
                .most_recent_event.?.data.event.event_type) {
                .bool, .Enum => {
                    ui.hot_interaction.interaction_type = .ToggleValue;
                },
                .f32 => {
                    ui.hot_interaction.interaction_type = .DragValue;
                },
                .OpenDataBlock => {
                    ui.hot_interaction.interaction_type = .ToggleValue;
                },
                else => {},
            }
        }

        switch (ui.hot_interaction.interaction_type) {
            .TearValue => {
                const root_group: *DebugVariableLink =
                    debug_state.cloneVariableLink(ui.hot_interaction.data.link.?);
                const tree: *DebugTree = debug_state.addTree(root_group, mouse_position);
                ui.hot_interaction.interaction_type = .Move;
                ui.hot_interaction.data = .{ .position = &tree.ui_position };
            },
            .Select => {
                if (!input.shift_down) {
                    debug_state.clearSelection();
                }

                debug_state.addToSelection(ui.hot_interaction.id);
            },
            else => {},
        }

        ui.interaction = ui.hot_interaction;
    } else {
        ui.interaction.interaction_type = .NoOp;
    }
}

fn interact(
    debug_state: *DebugState,
    input: *const shared.GameInput,
    mouse_position: Vector2,
    delta_mouse_position: Vector2,
) void {
    const ui: *DevUI = &debug_state.dev_ui;

    if (ui.interaction.interaction_type != .None) {
        // Mouse move interaction.
        const frame_ordinal: u32 = debug_state.most_recent_frame_ordinal;
        switch (ui.interaction.interaction_type) {
            .DragValue => {
                if (ui.interaction.data.element) |element| {
                    if (element.frames[frame_ordinal].most_recent_event) |stored_event| {
                        const event = &stored_event.data.event;
                        switch (event.event_type) {
                            .f32 => {
                                event.data.f32 += 0.1 * delta_mouse_position.y();
                            },
                            else => {},
                        }
                        markEditedEvent(debug_state, event);
                    }
                }
            },
            .Resize => {
                var position = ui.interaction.data.position;
                const flipped_delta: Vector2 = Vector2.new(delta_mouse_position.x(), -delta_mouse_position.y());
                position.* = position.plus(flipped_delta);
                _ = position.setX(@max(position.x(), 10));
                _ = position.setY(@max(position.y(), 10));
            },
            .Move => {
                var position = ui.interaction.data.position;
                position.* = position.plus(delta_mouse_position);
            },
            else => {},
        }

        // Click interaction.
        var transition_index: u32 = input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].half_transitions;
        while (transition_index > 1) : (transition_index -= 1) {
            endInteract(debug_state, input, mouse_position);
            beginInteract(debug_state, input, mouse_position);
        }

        if (!input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].ended_down) {
            endInteract(debug_state, input, mouse_position);
        }
    } else {
        ui.hot_interaction = ui.next_hot_interaction;

        var transition_index: u32 = input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].half_transitions;
        while (transition_index > 1) : (transition_index -= 1) {
            beginInteract(debug_state, input, mouse_position);
            endInteract(debug_state, input, mouse_position);
        }

        if (input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].ended_down) {
            beginInteract(debug_state, input, mouse_position);
        }
    }
}

fn markEditedEvent(debug_state: *DebugState, opt_event: ?*DebugEvent) void {
    if (opt_event) |event| {
        shared.global_debug_table.edit_event = event.*;
        if (debug_state.getElementFromEvent(
            event,
            null,
            @intFromEnum(ElementAddOp.AddToGroup) | @intFromEnum(ElementAddOp.CreateHierarchy),
        )) |element| {
            shared.global_debug_table.edit_event.guid = element.original_guid;
        }
    }
}

fn endInteract(debug_state: *DebugState, input: *const shared.GameInput, mouse_position: Vector2) void {
    _ = input;
    _ = mouse_position;

    const ui: *DevUI = &debug_state.dev_ui;
    const frame_ordinal: u32 = debug_state.most_recent_frame_ordinal;
    switch (ui.interaction.interaction_type) {
        .ToggleExpansion => {
            const view: *DebugView = debug_state.getOrCreateDebugView(ui.interaction.id);

            view.view_type = .Collapsible;
            if (view.data != .collapsible) {
                view.data = .{
                    .collapsible = .{ .expanded_always = false, .expanded_alt_view = false },
                };
            }

            view.data.collapsible.expanded_always = !view.data.collapsible.expanded_always;
        },
        .SetUInt32 => {
            if (ui.interaction.target) |target| {
                const u32_target = @as(*u32, @ptrCast(@alignCast(target)));
                u32_target.* = ui.interaction.data.uint32;
            }
        },
        .SetBool => {
            if (ui.interaction.target) |target| {
                const bool_target = @as(*bool, @ptrCast(@alignCast(target)));
                bool_target.* = ui.interaction.data.bool;
            }
        },
        .SetPointer => {
            if (ui.interaction.pointer_target) |target| {
                target.* = ui.interaction.data.pointer;
            }
        },
        .ToggleValue => {
            if (ui.interaction.data.element) |interaction_element| {
                if (interaction_element.frames[frame_ordinal].most_recent_event) |stored_event| {
                    const event = &stored_event.data.event;
                    switch (event.event_type) {
                        .bool => {
                            event.data.bool = !event.data.bool;
                        },
                        .Enum => {
                            event.data.Enum = event.data.Enum + 1;
                        },
                        else => {},
                    }
                    markEditedEvent(debug_state, event);
                }
            }
        },
        else => {},
    }

    ui.interaction.interaction_type = .None;
}

fn debugInit(
    assets: *Assets,
    width: i32,
    height: i32,
) *DebugState {
    var debug_state: *DebugState = memory.bootstrapPushStruct(
        DebugState,
        "debug_arena",
        null,
        ArenaPushParams.aligned(@alignOf(DebugState), true),
    );

    debug_state.collation_frame_ordinal = 1;

    debug_state.tree_sentinel.next = &debug_state.tree_sentinel;
    debug_state.tree_sentinel.prev = &debug_state.tree_sentinel;

    memory.zeroStruct(MemoryArena, &debug_state.per_frame_arena);

    debug_state.root_group = debug_state.createVariableLink(4, "Root");
    debug_state.root_info_size = 256;
    debug_state.root_info = @ptrCast(debug_state.debug_arena.pushSize(debug_state.root_info_size, null));
    debug_state.root_group.name = debug_state.root_info;

    debug_state.function_group = debug_state.createVariableLink(9, "Functions");
    debug_state.function_info_size = 256;
    debug_state.function_info = @ptrCast(debug_state.debug_arena.pushSize(debug_state.function_info_size, null));
    debug_state.function_group.name = debug_state.function_info;

    debug_state.profile_group = debug_state.createVariableLink(7, "Profile");

    var root_profile_event: DebugEvent = .{
        .guid = DebugEvent.debugName(@src(), .RootProfile, "RootProfile"),
        .name = "RootProfile",
    };
    debug_state.root_profile_element = debug_state.getElementFromEvent(&root_profile_event, null, 0);

    _ = debug_state.addTree(
        debug_state.root_group,
        Vector2.new(-0.5 * @as(f32, @floatFromInt(width)), 0.5 * @as(f32, @floatFromInt(height))),
    );
    _ = debug_state.addTree(
        debug_state.function_group,
        Vector2.new(0.0 * @as(f32, @floatFromInt(width)), 0.5 * @as(f32, @floatFromInt(height))),
    );

    debug_state.dev_ui.init(assets);

    return debug_state;
}

fn debugStart(
    debug_state: *DebugState,
    commands: *renderer.RenderCommands,
    assets: *asset.Assets,
    input: *const shared.GameInput,
) void {
    TimedBlock.beginFunction(@src(), .DebugStart);
    defer TimedBlock.endFunction(@src(), .DebugStart);

    if (!debug_state.paused) {
        debug_state.viewing_frame_ordinal = debug_state.most_recent_frame_ordinal;
    }

    debug_state.dev_ui.beginFrame(assets, commands, input);
}

fn debugEnd(debug_state: *DebugState, input: *const shared.GameInput) void {
    TimedBlock.beginFunction(@src(), .DebugEnd);
    defer TimedBlock.endFunction(@src(), .DebugEnd);

    const ui: *DevUI = &debug_state.dev_ui;
    const mem_stats: DebugPlatformMemoryStats = shared.platform.debugGetMemoryStats();

    // Set the text shown in the root node of the debug menu.
    const most_recent_frame: *DebugFrame = &debug_state.frames[debug_state.viewing_frame_ordinal];
    _ = shared.formatString(
        debug_state.root_info_size,
        debug_state.root_info,
        "%.02fms %de %dp %dd - Mem: %lu blocks, %lu used",
        .{
            most_recent_frame.wall_seconds_elapsed * 1000,
            most_recent_frame.stored_event_count,
            most_recent_frame.profile_block_count,
            most_recent_frame.data_block_count,
            mem_stats.block_count,
            mem_stats.total_used,
        },
    );

    if (debug_state.getElementFromGuid(shared.global_debug_table.hud_function)) |hud_element| {
        var min_duration: u64 = std.math.maxInt(u64);
        var max_duration: u64 = 0;
        var cur_duration: u64 = 0;
        var total_duration: u64 = 0;
        var total_count: u32 = 0;

        var frame_index: u32 = 0;
        while (frame_index < MAX_FRAME_COUNT) : (frame_index += 1) {
            const frame: *DebugElementFrame = &hud_element.frames[frame_index];
            var duration: u64 = 0;

            if (frame.oldest_event != null) {
                var opt_event: ?*DebugStoredEvent = frame.oldest_event;
                while (opt_event) |event| : (opt_event = event.next) {
                    const node: *DebugProfileNode = &event.data.profile_node;
                    duration += node.duration;
                }

                if (min_duration > duration) {
                    min_duration = duration;
                }
                if (max_duration < duration) {
                    max_duration = duration;
                }
                if (frame_index == debug_state.viewing_frame_ordinal) {
                    cur_duration = duration;
                }

                total_duration += duration;
                total_count += 1;
            }
        }

        if (max_duration > 0) {
            const cur_kilocycles: u32 = @intCast(cur_duration / 1000);
            const min_kilocycles: u32 = @intCast(min_duration / 1000);
            const max_kilocycles: u32 = @intCast(max_duration / 1000);
            const avg_kilocycles: u32 =
                @intFromFloat(math.safeRatio0(@floatFromInt(total_duration), @floatFromInt((1000 * total_count))));

            _ = shared.formatString(
                debug_state.function_info_size,
                debug_state.function_info,
                "%s: %dkcy cur | %dkcy min | %dkcy avg | %dkcy max",
                .{ hud_element.name, cur_kilocycles, min_kilocycles, avg_kilocycles, max_kilocycles },
            );
        }
    }

    drawTrees(debug_state, ui.mouse_position);
    interact(debug_state, input, ui.mouse_position, ui.delta_mouse_position);
    debug_state.dev_ui.endFrame();
}

fn getGameAssets(game_memory: *shared.Memory) ?*asset.Assets {
    var assets: ?*asset.Assets = null;

    if (game_memory.game_state) |state| {
        assets = state.assets;
    }

    return assets;
}

pub fn frameEnd(
    game_memory: *shared.Memory,
    input: *shared.GameInput,
    commands: *renderer.RenderCommands,
) callconv(.c) void {
    memory.zeroStruct(DebugEvent, &shared.global_debug_table.edit_event);

    shared.global_debug_table.current_event_array_index = if (shared.global_debug_table.current_event_array_index == 0) 1 else 0;

    const next_event_array_index: u64 = @as(u64, @intCast(shared.global_debug_table.current_event_array_index)) << 32;
    const event_array_index_event_index: u64 =
        @atomicRmw(u64, &shared.global_debug_table.event_array_index_event_index, .Xchg, next_event_array_index, .seq_cst);
    const event_array_index: u32 = @intCast(event_array_index_event_index >> 32);

    std.debug.assert(event_array_index <= 1);

    const event_count: u32 = @intCast(event_array_index_event_index & 0xffffffff);

    if (game_memory.debug_state == null) {
        if (getGameAssets(game_memory)) |assets| {
            game_memory.debug_state = debugInit(
                assets,
                @intCast(commands.settings.width),
                @intCast(commands.settings.height),
            );
        }
    }

    if (game_memory.debug_state) |debug_state| {
        if (getGameAssets(game_memory)) |assets| {
            debugStart(
                debug_state,
                commands,
                assets,
                input,
            );
            debug_state.collateDebugRecords(event_count, &shared.global_debug_table.events[event_array_index]);
            debugEnd(debug_state, input);
        }
    }
}
