const shared = @import("shared.zig");
const std = @import("std");

pub const DEBUG_CYCLE_COUNTERS_COUNT = @typeInfo(DebugCycleCounters).Enum.fields.len;

pub const DebugCycleCounters = enum(u8) {
    GameUpdateAndRender = 0,
    RenderGroupToOutput,
    DrawRectangle,
    DrawRectangleSlowly,
    DrawRectangleQuickly,
    ProcessPixel,
};

pub var debug_records = [1]DebugRecord{DebugRecord{}} ** DEBUG_CYCLE_COUNTERS_COUNT;

const DebugRecord = struct {
    cycle_count: u64 = undefined,

    file_name: [:0]const u8 = undefined,
    function_name: [:0]const u8 = undefined,

    line_number: u32 = undefined,
    hit_count: u32 = undefined,
};

pub const TimedBlock = struct {
    record: *DebugRecord,

    pub fn begin(source: std.builtin.SourceLocation, counter: DebugCycleCounters) TimedBlock {
        const result = TimedBlock{
            .record = &debug_records[@intFromEnum(counter)],
        };

        result.record.file_name = source.file;
        result.record.function_name = source.fn_name;
        result.record.line_number = source.line;
        result.record.cycle_count -%= shared.rdtsc();
        result.record.hit_count += 1;

        return result;
    }

    pub fn end(self: TimedBlock) void {
        self.record.cycle_count +%= shared.rdtsc();
    }

    pub fn endWithCount(self: TimedBlock, hit_count: u32) void {
        self.end();
        self.record.hit_count +%= hit_count;
    }
};

