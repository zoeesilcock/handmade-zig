const shared = @import("shared.zig");
const std = @import("std");

pub const DEBUG_CYCLE_COUNTERS_COUNT = @typeInfo(DebugCycleCounters).Enum.fields.len;

pub const DebugCycleCounters = enum(u8) {
    GameUpdateAndRender = 0,
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
    EndSimulation,
    BeginSimulation,
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

pub var debug_records = [1]DebugRecord{DebugRecord{}} ** DEBUG_CYCLE_COUNTERS_COUNT;

pub const DebugRecord = extern struct {
    file_name: [*:0]const u8 = undefined,
    function_name: [*:0]const u8 = undefined,

    line_number: u32 = undefined,
    reserved: u32 = 0,

    hit_count_cycle_count: u64 = 0,
};

pub const TimedBlock = struct {
    record: *DebugRecord,
    start_cycles: u64 = 0,
    hit_count: u32 = 0,

    pub fn begin(source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        var result = TimedBlock{
            .record = &debug_records[@intFromEnum(counter)],
            .hit_count = 1,
        };

        result.record.file_name = source.file;
        result.record.function_name = source.fn_name;
        result.record.line_number = source.line;
        result.start_cycles = @intCast(shared.rdtsc());

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
    }
};

pub const SNAPSHOT_COUNT = 120;
const COUNTER_COUNT = 512;

pub const DebugCounterSnapshot = struct {
    hit_count: u32 = 0,
    cycle_count: u32 = 0,
};

pub const DebugCounterState = struct {
    file_name: [*:0]const u8 = undefined,
    function_name: [*:0]const u8 = undefined,
    line_number: u32 = undefined,

    snapshots: [SNAPSHOT_COUNT]DebugCounterSnapshot = [1]DebugCounterSnapshot{DebugCounterSnapshot{}} ** SNAPSHOT_COUNT,
};

pub const DebugState = struct {
    snapshot_index: u32,
    counter_count: u32,
    counter_states: [COUNTER_COUNT]DebugCounterState = [1]DebugCounterState{DebugCounterState{}} ** COUNTER_COUNT,
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
