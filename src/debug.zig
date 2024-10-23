const shared = @import("shared.zig");

pub var debug_global_memory: ?*shared.Memory = null;

const INTERNAL = shared.INTERNAL;
pub const DEBUG_CYCLE_COUNTERS_COUNT = @typeInfo(DebugCycleCounters).Enum.fields.len;
pub const DEBUG_CYCLE_COUNTER_NAMES: [DEBUG_CYCLE_COUNTERS_COUNT][:0]const u8 = buildDebugCycleCounterNames();

pub const DebugCycleCounters = enum(u8) {
    GameUpdateAndRender = 0,
    RenderGroupToOutput,
    DrawRectangle,
    DrawRectangleSlowly,
    DrawRectangleQuickly,
    ProcessPixel,
};

fn buildDebugCycleCounterNames() [DEBUG_CYCLE_COUNTERS_COUNT][:0]const u8 {
    var names: [DEBUG_CYCLE_COUNTERS_COUNT][:0]const u8 = undefined;
    for (0..DEBUG_CYCLE_COUNTERS_COUNT) |counter_index| {
        names[counter_index] = @typeInfo(DebugCycleCounters).Enum.fields[counter_index].name;
    }
    return names;
}

pub const DebugCycleCounter = extern struct {
    cycle_count: u64 = 0,
    last_cycle_start: u64 = 0,
    hit_count: u32 = 0,
};

pub const TimedBlock = struct {
    id: DebugCycleCounters,

    pub fn init(id: DebugCycleCounters) TimedBlock {
        var result = TimedBlock{ .id = id };
        result.beginTimedBlock();
        return result;
    }

    pub fn beginTimedBlock(self: *TimedBlock) void {
        if (INTERNAL) {
            if (debug_global_memory) |memory| {
                memory.getCycleCounter(self.id).last_cycle_start = shared.rdtsc();
            }
        }
    }
    pub fn endTimedBlock(self: *TimedBlock) void {
        if (INTERNAL) {
            if (debug_global_memory) |memory| {
                const counter = memory.getCycleCounter(self.id);
                counter.cycle_count +%= shared.rdtsc() -% counter.last_cycle_start;
                counter.hit_count +%= 1;
            }
        }
    }

    pub fn endTimedBlockCounted(self: *TimedBlock, hit_count: u32) void {
        if (INTERNAL) {
            if (debug_global_memory) |memory| {
                const counter = memory.getCycleCounter(self.id);
                counter.cycle_count +%= shared.rdtsc() -% counter.last_cycle_start;
                counter.hit_count +%= hit_count;
            }
        }
    }
};

