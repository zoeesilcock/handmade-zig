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

pub const SNAPSHOT_COUNT = 120;
const COUNTER_COUNT = 512;

pub const DebugCounterSnapshot = struct {
    hit_count: u32 = 0,
    cycle_count: u64 = 0,
};

pub const DebugCounterState = struct {
    file_name: ?[*:0]const u8 = null,
    block_name: ?[*:0]const u8 = null,
    line_number: u32 = undefined,

    snapshots: [SNAPSHOT_COUNT]DebugCounterSnapshot = [1]DebugCounterSnapshot{DebugCounterSnapshot{}} ** SNAPSHOT_COUNT,
};

pub const DebugState = struct {
    snapshot_index: u32 = 0,
    counter_count: u32 = 0,
    counter_states: [COUNTER_COUNT]DebugCounterState = [1]DebugCounterState{DebugCounterState{}} ** COUNTER_COUNT,

    pub fn collateDebugRecords(self: *DebugState, event_count: u32, events: *[shared.MAX_DEBUG_EVENT_COUNT]DebugEvent) void {
        self.counter_count = shared.MAX_DEBUG_RECORD_COUNT;

        var counter_index: u32 = 0;
        while (counter_index < self.counter_count) : (counter_index += 1) {
            var dest: *DebugCounterState = &self.counter_states[counter_index];
            dest.snapshots[self.snapshot_index].hit_count = 0;
            dest.snapshots[self.snapshot_index].cycle_count = 0;
        }

        var event_index: u32 = 0;
        while (event_index < event_count) : (event_index += 1) {
            const event: *const DebugEvent = &events[event_index];

            // These two lookups are simpler because we have all our code in the same compilation.
            // If we split our compilation into optimized and non-optimized like Casey does we need to
            // implement the same type of lookup here.
            const dest: *DebugCounterState = &self.counter_states[event.debug_record_index];
            const source: *DebugRecord = &global_debug_table.records[shared.TRANSLATION_UNIT_INDEX][event.debug_record_index];

            dest.file_name = source.file_name;
            dest.block_name = source.block_name;
            dest.line_number = source.line_number;

            if (event.event_type == .BeginBlock) {
                dest.snapshots[self.snapshot_index].hit_count += 1;
                dest.snapshots[self.snapshot_index].cycle_count -%= event.clock;
            } else if (event.event_type == .EndBlock) {
                dest.snapshots[self.snapshot_index].cycle_count +%= event.clock;
            }
        }
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

    const next_event_array_index: u64 = global_debug_table.current_event_array_index << 32;
    const event_array_index_event_index: u64 =
        @atomicRmw(u64, &global_debug_table.event_array_index_event_index, .Xchg, next_event_array_index, .seq_cst);

    const event_array_index: u32 = @intCast(event_array_index_event_index >> 32);
    const event_count: u32 = @intCast(event_array_index_event_index & 0xffffffff);

    if (memory.debug_storage) |debug_storage| {
        var debug_state: *DebugState = @ptrCast(@alignCast(debug_storage));
        debug_state.counter_count = 0;

        debug_state.collateDebugRecords(event_count, &global_debug_table.events[event_array_index]);

        debug_state.snapshot_index += 1;
        if (debug_state.snapshot_index >= SNAPSHOT_COUNT) {
            debug_state.snapshot_index = 0;
        }
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

                const bar_width: f32 = 8;
                const bar_spacing: f32 = 10;
                const chart_left: f32 = left_edge + 10;
                const chart_height: f32 = 300;
                const chart_width: f32 = bar_spacing * @as(f32, @floatFromInt(SNAPSHOT_COUNT));
                const chart_min_y: f32 = at_y - (chart_height + 80);
                const scale: f32 = 1.0 / 0.03333;

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

                if (false) {
                var snapshot_index: u32 = 0;
                while (snapshot_index < SNAPSHOT_COUNT) : (snapshot_index += 1) {
                    const info: *shared.DebugFrameEndInfo = &debug_state.frame_end_infos[snapshot_index];

                    var stack_y: f32 = chart_min_y;
                    var prev_timestamp_seconds: f32 = 0;
                    var timestamp_index: u32 = 0;
                    while (timestamp_index < info.timestamp_count) : (timestamp_index += 1) {
                        const timestamp: *const shared.DebugFrameTimestamp = &info.timestamps[timestamp_index];
                        const this_seconds_elapsed: f32 = timestamp.seconds - prev_timestamp_seconds;
                        prev_timestamp_seconds = timestamp.seconds;

                        const color = colors[timestamp_index % colors.len];
                        const this_proportion: f32 = scale * this_seconds_elapsed;
                        const this_height: f32 = chart_height * this_proportion;
                        group.pushRectangle(
                            Vector2.new(bar_width, this_height),
                            Vector3.new(
                                chart_left + bar_spacing * @as(f32, (@floatFromInt(snapshot_index))) + 0.5 * bar_width,
                                stack_y + 0.5 * this_height,
                                0,
                            ),
                            color.toColor(1),
                        );

                        stack_y += this_height;
                    }
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
