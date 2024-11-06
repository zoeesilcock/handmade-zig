const shared = @import("shared.zig");
const asset = @import("asset.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const file_formats = @import("file_formats");
const std = @import("std");

// Types.
const DebugRecord = shared.DebugRecord;
const DebugEventType = shared.DebugEventType;
const DebugEvent = shared.DebugEvent;
const TimedBlock = shared.TimedBlock;
const Vector3 = math.Vector3;
const Vector2 = math.Vector2;
const Color = math.Color;
const Color3 = math.Color3;

pub var global_debug_table: shared.DebugTable = shared.DebugTable{};

const COUNTER_COUNT = 512;

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
    lane_index: u32,
    min_t: f32,
    max_t: f32,
};

const OpenDebugBlock = struct {
    staring_frame_index: u32,
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

pub const DebugState = struct {
    initialized: bool,

    collate_arena: shared.MemoryArena,
    collate_temp: shared.TemporaryMemory,

    frame_bar_lane_count: u32,
    frame_bar_scale: f32,
    frame_count: u32,

    frames: [*]DebugFrame,
    first_thread: ?*DebugThread,
    first_free_block: ?*OpenDebugBlock,

    pub fn collateDebugRecords(
        self: *DebugState,
        invalid_event_array_index: u32,
    ) void {
        self.frames = self.collate_arena.pushArray(shared.MAX_DEBUG_EVENT_ARRAY_COUNT * 4, DebugFrame);
        self.frame_bar_lane_count = 0;
        self.frame_bar_scale = 1.0 / (60.0 * 1000000.0);
        self.frame_count = 0;

        var opt_current_frame: ?*DebugFrame = null;

        var event_array_index: u32 = invalid_event_array_index + 1;
        while (true) : (event_array_index += 1) {
            if (event_array_index == shared.MAX_DEBUG_EVENT_ARRAY_COUNT) {
                event_array_index = 0;
            }

            if (event_array_index == invalid_event_array_index) {
                break;
            }

            var event_index: u32 = 0;
            while (event_index < global_debug_table.event_count[event_array_index]) : (event_index += 1) {
                const event: *DebugEvent = &global_debug_table.events[event_array_index][event_index];
                const source: *DebugRecord = &global_debug_table.records[shared.TRANSLATION_UNIT_INDEX][event.debug_record_index];

                _ = source;

                if (event.event_type == .FrameMarker) {
                    if (opt_current_frame) |current_frame| {
                        current_frame.end_clock = event.clock;
                        current_frame.wall_seconds_elapsed = event.data.seconds_elapsed;

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

                    opt_current_frame = &self.frames[self.frame_count];
                    self.frame_count += 1;

                    if (opt_current_frame) |current_frame| {
                        current_frame.begin_clock = event.clock;
                        current_frame.end_clock = 0;
                        current_frame.region_count = 0;
                        current_frame.regions = self.collate_arena.pushArray(shared.MAX_DEBUG_REGIONS_PER_FRAME, DebugFrameRegion);
                        current_frame.wall_seconds_elapsed = 0;
                    }
                } else {
                    if (opt_current_frame) |current_frame| {
                        const frame_index: u32 = self.frame_count - 1;
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
                                            if (thread.first_open_block != null and thread.first_open_block.?.parent == null) {
                                                const min_t: f32 = @floatFromInt(opening_event.clock - current_frame.begin_clock);
                                                const max_t: f32 = @floatFromInt(event.clock - current_frame.begin_clock);
                                                const threshold_t: f32 = 0.01;

                                                if ((max_t - min_t) > threshold_t) {
                                                    var region: *DebugFrameRegion = self.addRegion(current_frame);
                                                    region.lane_index = thread.lane_index;
                                                    region.min_t = min_t;
                                                    region.max_t = max_t;
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

        // if (false) {
        //     self.counter_count = shared.MAX_DEBUG_RECORD_COUNT;
        //
        //     var counter_index: u32 = 0;
        //     while (counter_index < self.counter_count) : (counter_index += 1) {
        //         var dest: *DebugCounterState = &self.counter_states[counter_index];
        //         dest.snapshots[self.snapshot_index].hit_count = 0;
        //         dest.snapshots[self.snapshot_index].cycle_count = 0;
        //     }
        //
        //     var event_index: u32 = 0;
        //     while (event_index < event_count) : (event_index += 1) {
        //         const event: *const DebugEvent = &events[event_index];
        //
        //         // These two lookups are simpler because we have all our code in the same compilation.
        //         // If we split our compilation into optimized and non-optimized like Casey does we need to
        //         // implement the same type of lookup here.
        //         const dest: *DebugCounterState = &self.counter_states[event.debug_record_index];
        //         const source: *DebugRecord = &global_debug_table.records[shared.TRANSLATION_UNIT_INDEX][event.debug_record_index];
        //
        //         dest.file_name = source.file_name;
        //         dest.block_name = source.block_name;
        //         dest.line_number = source.line_number;
        //
        //         if (event.event_type == .BeginBlock) {
        //             dest.snapshots[self.snapshot_index].hit_count += 1;
        //             dest.snapshots[self.snapshot_index].cycle_count -%= event.clock;
        //         } else if (event.event_type == .EndBlock) {
        //             dest.snapshots[self.snapshot_index].cycle_count +%= event.clock;
        //         }
        //     }
        // }
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

pub var render_group: ?*render.RenderGroup = null;
var left_edge: f32 = 0;
var at_y: f32 = 0;
var font_scale: f32 = 0;
var font_id: file_formats.FontId = undefined;

pub fn frameEnd(memory: *shared.Memory) *shared.DebugTable {
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
        var debug_state: *DebugState = @ptrCast(@alignCast(debug_storage));

        if (!debug_state.initialized) {
            debug_state.collate_arena.initialize(
                memory.debug_storage_size - @sizeOf(DebugState),
                memory.debug_storage.? + @sizeOf(DebugState),
            );

            debug_state.collate_temp = debug_state.collate_arena.beginTemporaryMemory();

            debug_state.initialized = true;
        }

        debug_state.collate_arena.endTemporaryMemory(debug_state.collate_temp);
        debug_state.collate_temp = debug_state.collate_arena.beginTemporaryMemory();

        debug_state.first_thread = null;
        debug_state.first_free_block = null;

        debug_state.collateDebugRecords(global_debug_table.current_event_array_index);
    }

    return &global_debug_table;
}

pub fn textReset(assets: *asset.Assets, width: i32, height: i32) void {
    var timed_block = TimedBlock.beginFunction(@src(), .DebugTextReset);
    defer timed_block.end();

    var match_vector = asset.AssetVector{};
    var weight_vector = asset.AssetVector{};

    font_scale = 1;
    at_y = 0;
    left_edge = -0.5 * @as(f32, @floatFromInt(width));

    if (render_group) |group| {
        group.orthographicMode(width, height, 1);
    }

    match_vector.e[asset.AssetTagId.FontType.toInt()] = @intFromEnum(file_formats.AssetFontType.Debug);
    weight_vector.e[asset.AssetTagId.FontType.toInt()] = 1;
    if (assets.getBestMatchFont(.Font, &match_vector, &weight_vector)) |id| {
        font_id = id;

        const font_info = assets.getFontInfo(font_id);
        at_y = 0.5 * @as(f32, @floatFromInt(height)) - font_scale * font_info.getStartingBaselineY();
    }
}

pub fn textLine(text: [:0]const u8) void {
    if (render_group) |group| {
        var match_vector = asset.AssetVector{};

        if (group.pushFont(font_id)) |font| {
            const font_info = group.assets.getFontInfo(font_id);
            var prev_code_point: u32 = 0;
            var char_scale = font_scale;
            var color = Color.white();
            var at_x: f32 = left_edge;

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
                    char_scale = font_scale * math.clampf01(c_scale * @as(f32, @floatFromInt(at[2] - '0')));
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
                    at_x += advance_x;

                    if (code_point != ' ') {
                        match_vector.e[@intFromEnum(asset.AssetTagId.UnicodeCodepoint)] = @floatFromInt(code_point);
                        if (font.getBitmapForGlyph(font_info, group.assets, code_point)) |bitmap_id| {
                            const info = group.assets.getBitmapInfo(bitmap_id);
                            const char_height = char_scale * @as(f32, @floatFromInt(info.dim[1]));
                            group.pushBitmapId(bitmap_id, char_height, Vector3.new(at_x, at_y, 0), color);
                        }
                    }

                    prev_code_point = code_point;

                    at += 1;
                }
            }

            at_y -= font_info.getLineAdvance() * font_scale;
        }
    }
}

pub fn overlay(memory: *shared.Memory) void {
    if (memory.debug_storage) |debug_storage| {
        if (render_group) |group| {
            const debug_state: *DebugState = @ptrCast(@alignCast(debug_storage));

            if (group.pushFont(font_id)) |_| {
                const font_info = group.assets.getFontInfo(font_id);

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
                                const chart_min_y: f32 = at_y;
                                const char_height: f32 = font_info.ascender_height * font_scale;
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

                at_y -= 300;

                const lane_width: f32 = 8;
                const lane_count: u32 = debug_state.frame_bar_lane_count;
                const bar_width: f32 = lane_width * @as(f32, @floatFromInt(lane_count));
                const bar_spacing: f32 = bar_width + 4;
                const chart_left: f32 = left_edge + 10;
                const chart_height: f32 = 300;
                const chart_width: f32 = bar_spacing * @as(f32, @floatFromInt(debug_state.frame_count));
                const chart_min_y: f32 = at_y - (chart_height + 80);
                const scale: f32 = chart_height * debug_state.frame_bar_scale;

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

                var max_frame: u32 = debug_state.frame_count;
                if (max_frame > 10) {
                    max_frame = 10;
                }

                var frame_index: u32 = 0;
                while (frame_index < max_frame) : (frame_index += 1) {
                    const frame: *DebugFrame = &debug_state.frames[debug_state.frame_count - (frame_index + 1)];

                    const stack_x: f32 = chart_left + bar_spacing * @as(f32, (@floatFromInt(frame_index)));
                    const stack_y: f32 = chart_min_y;

                    var region_index: u32 = 0;
                    while (region_index < frame.region_count) : (region_index += 1) {
                        const region: *const DebugFrameRegion = &frame.regions[region_index];

                        const color = colors[region_index % colors.len];
                        const this_min_y: f32 = stack_y + scale * region.min_t;
                        const this_max_y: f32 = stack_y + scale * region.max_t;
                        group.pushRectangle(
                            Vector2.new(lane_width, this_max_y - this_min_y),
                            Vector3.new(
                                stack_x + 0.5 * lane_width + lane_width * @as(f32, @floatFromInt(region.lane_index)),
                                0.5 * (this_min_y + this_max_y),
                                0,
                            ),
                            color.toColor(1),
                        );
                    }
                }

                // 30 FPS line.
                group.pushRectangle(
                    Vector2.new(chart_width, 1),
                    Vector3.new(chart_left + 0.5 * chart_width, chart_min_y + chart_height, 0),
                    Color.white(),
                );

                // 60 FPS line.
                group.pushRectangle(
                    Vector2.new(chart_width, 1),
                    Vector3.new(chart_left + 0.5 * chart_width, chart_min_y + (chart_height * 0.5), 0),
                    Color.new(0.5, 1, 0, 1),
                );

                // Kanji owl codepoints
                // 0x5c0f
                // 0x8033
                // 0x6728
                // 0x514e
                // debugTextLine("\\5C0F\\8033\\6728\\514E");
                //
                // debugTextLine("\\#900DEBUG \\#090CYCLE \\#990\\^5COUNTS:");
            }
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
