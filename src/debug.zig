const shared = @import("shared.zig");
const asset = @import("asset.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const file_formats = @import("file_formats");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;
const Vector2 = math.Vector2;
const Color = math.Color;
const Color3 = math.Color3;

pub const DebugCycleCounters = enum(u16) {
    GameUpdateAndRender = 0,
    DebugOverlay,
    DebugTextReset,
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
    FillGroundChunk,
    LoadAssetWorkDirectly,
    AcquireAssetMemory,
    LoadBitmap,
    LoadSound,
    LoadFont,
    GetBestMatchAsset,
    GetRandomAsset,
    GetFirstAsset,
};

pub const DEBUG_CYCLE_COUNTERS_COUNT = @typeInfo(DebugCycleCounters).Enum.fields.len;
pub var debug_records = [1]DebugRecord{DebugRecord{}} ** DEBUG_CYCLE_COUNTERS_COUNT;

const DEBUG_EVENT_COUNT = 16 * 65536;
pub var debug_event_array = [2][DEBUG_EVENT_COUNT]DebugEvent{
    [1]DebugEvent{DebugEvent{}} ** DEBUG_EVENT_COUNT,
    [1]DebugEvent{DebugEvent{}} ** DEBUG_EVENT_COUNT,
};

pub var debug_array_index_event_index: u64 = 0;

pub const DebugRecord = extern struct {
    file_name: [*:0]const u8 = undefined,
    function_name: [*:0]const u8 = undefined,

    line_number: u32 = undefined,
    reserved: u32 = 0,

    hit_count_cycle_count: u64 = 0,
};

const DebugEventType = enum(u8) {
    BeginBlock,
    EndBlock,
};

const DebugEvent = extern struct {
    clock: u64 = 0,
    thread_index: u16 = 0,
    core_index: u16 = 0,
    debug_record_index: u16 = 0,
    debug_record_array_index: u8 = 0,
    event_type: DebugEventType = undefined,
};

fn recordDebugEvent(debug_record_index: u16, event_type: DebugEventType) void {
    const array_index_event_index = @atomicRmw(u64, &debug_array_index_event_index, .Add, 1, .seq_cst);
    const array_index = array_index_event_index >> 32;
    const event_index = array_index_event_index & 0xffffffff;
    std.debug.assert(event_index < DEBUG_EVENT_COUNT);

    var event: *DebugEvent = &debug_event_array[array_index][event_index];
    event.clock = shared.rdtsc();
    event.thread_index = 0;
    event.core_index = 0;
    event.debug_record_index = debug_record_index;
    event.debug_record_array_index = 0;
    event.event_type = event_type;
}

pub const TimedBlock = struct {
    record: *DebugRecord,
    start_cycles: u64 = 0,
    hit_count: u32 = 0,
    counter: DebugCycleCounters = undefined,

    pub fn begin(source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        var result = TimedBlock{
            .record = &debug_records[@intFromEnum(counter)],
            .hit_count = 1,
        };

        result.record.file_name = source.file;
        result.record.function_name = source.fn_name;
        result.record.line_number = source.line;
        result.start_cycles = @intCast(shared.rdtsc());
        result.counter = counter;

        recordDebugEvent(@intFromEnum(counter), .BeginBlock);

        return result;
    }

    pub fn beginWithCount(source: std.builtin.SourceLocation, counter: DebugCycleCounters, hit_count: u32) TimedBlock {
        var result = TimedBlock.begin(source, counter);
        result.hit_count = hit_count;
        return result;
    }

    pub fn end(self: TimedBlock) void {
        const delta: u64 = (shared.rdtsc() - self.start_cycles) | (@as(u64, @intCast(self.hit_count)) << 32);
        _ = @atomicRmw(u64, &self.record.hit_count_cycle_count, .Add, delta, .monotonic);

        recordDebugEvent(@intFromEnum(self.counter), .EndBlock);
    }
};

pub const SNAPSHOT_COUNT = 120;
const COUNTER_COUNT = 512;

pub const DebugCounterSnapshot = struct {
    hit_count: u32 = 0,
    cycle_count: u64 = 0,
};

pub const DebugCounterState = struct {
    file_name: ?[*:0]const u8 = null,
    function_name: ?[*:0]const u8 = null,
    line_number: u32 = undefined,

    snapshots: [SNAPSHOT_COUNT]DebugCounterSnapshot = [1]DebugCounterSnapshot{DebugCounterSnapshot{}} ** SNAPSHOT_COUNT,
};

pub const DebugState = struct {
    snapshot_index: u32 = 0,
    counter_count: u32 = 0,
    counter_states: [COUNTER_COUNT]DebugCounterState = [1]DebugCounterState{DebugCounterState{}} ** COUNTER_COUNT,
    frame_end_infos: [SNAPSHOT_COUNT]shared.DebugFrameEndInfo =
        [1]shared.DebugFrameEndInfo{shared.DebugFrameEndInfo{}} ** SNAPSHOT_COUNT,

    pub fn updateDebugRecords(self: *DebugState) void {
        for (&debug_records) |*source| {
            var dest: *DebugCounterState = &self.counter_states[self.counter_count];
            self.counter_count += 1;

            const hit_count_cycle_count = @atomicRmw(u64, @constCast(&source.hit_count_cycle_count), .Xchg, 0, .monotonic);

            dest.file_name = source.file_name;
            dest.function_name = source.function_name;
            dest.line_number = source.line_number;
            dest.snapshots[self.snapshot_index].hit_count = @intCast(hit_count_cycle_count >> 32);
            dest.snapshots[self.snapshot_index].cycle_count = @intCast(hit_count_cycle_count & 0xFFFFFFFF);
        }
    }

    pub fn collateDebugRecords(self: *DebugState, event_count: u32, events: *[DEBUG_EVENT_COUNT]DebugEvent) void {
        self.counter_count = DEBUG_CYCLE_COUNTERS_COUNT;

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
            const source: *DebugRecord = &debug_records[event.debug_record_index];

            dest.file_name = source.file_name;
            dest.function_name = source.function_name;
            dest.line_number = source.line_number;

            if (event.event_type == .BeginBlock) {
                dest.snapshots[self.snapshot_index].hit_count += 1;
                dest.snapshots[self.snapshot_index].cycle_count -%= event.clock;
            } else {
                std.debug.assert(event.event_type == .EndBlock);
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
var current_event_array_index: u64 = 0;

pub fn frameEnd(memory: *shared.Memory, info: *shared.DebugFrameEndInfo) void {
    current_event_array_index = if (current_event_array_index == 0) 1 else 0;
    const next_event_array_index: u64 = current_event_array_index << 32;
    const array_index_event_index: u64 =
        @atomicRmw(u64, &debug_array_index_event_index, .Xchg, next_event_array_index, .seq_cst);

    const event_array_index: u32 = @intCast(array_index_event_index >> 32);
    const event_count: u32 = @intCast(array_index_event_index & 0xffffffff);

    if (memory.debug_storage) |debug_storage| {
        var debug_state: *DebugState = @ptrCast(@alignCast(debug_storage));
        debug_state.counter_count = 0;

        if (false) {
            debug_state.updateDebugRecords();
        } else {
            debug_state.collateDebugRecords(event_count, &debug_event_array[event_array_index]);
        }

        debug_state.frame_end_infos[debug_state.snapshot_index] = info.*;

        debug_state.snapshot_index += 1;
        if (debug_state.snapshot_index >= SNAPSHOT_COUNT) {
            debug_state.snapshot_index = 0;
        }
    }
}

pub fn textReset(assets: *asset.Assets, width: i32, height: i32) void {
    var timed_block = TimedBlock.begin(@src(), .DebugTextReset);
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

                    if (counter.function_name) |function_name| {
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
                            function_name,
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
