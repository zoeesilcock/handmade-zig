const std = @import("std");

pub const INTERNAL = @import("build_options").internal;

pub fn notImplemented() void {
    if (INTERNAL) {
        std.debug.assert(true);
    } else {
        unreachable;
    }
}

pub inline fn kilobytes(value: u32) u64 {
    return value * 1024;
}

pub inline fn megabytes(value: u32) u64 {
    return kilobytes(value) * 1024;
}

pub inline fn gigabytes(value: u32) u64 {
    return megabytes(value) * 1024;
}

pub inline fn terabytes(value: u32) u64 {
    return gigabytes(value) * 1024;
}

pub inline fn alignPow2(value: u32, alignment: u32) u32 {
    return (value + (alignment - 1)) & ~@as(u32, alignment - 1);
}

pub inline fn align4(value: u32) u32 {
    return (value + 3) & ~@as(u32, 3);
}

pub inline fn align8(value: u32) u32 {
    return (value + 7) & ~@as(u32, 7);
}

pub inline fn align16(value: u32) u32 {
    return (value + 15) & ~@as(u32, 15);
}

pub inline fn incrementPointer(pointer: anytype, offset: i32) @TypeOf(pointer) {
    return if (offset >= 0)
        pointer + @as(usize, @intCast(offset))
    else
        pointer - @abs(offset);
}

pub fn rdtsc() u64 {
    var hi: u32 = 0;
    var low: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}

pub fn getThreadId() u32 {
    const thread_local_storage_ptr = asm (
        \\movq %%gs:0x30, %[ret]
        : [ret] "=ret" (-> *anyopaque),
    );
    const thread_id: *u32 = @ptrFromInt(@intFromPtr(thread_local_storage_ptr) + 0x48);

    return thread_id.*;
}

pub const TicketMutex = extern struct {
    ticket: u64,
    serving: u64,

    pub fn begin(self: *TicketMutex) void {
        const ticket = @atomicRmw(u64, &self.ticket, .Add, 1, .seq_cst);
        while (ticket != self.serving) {
            // TODO: This isn't implemented in Zig yet:
            // mm_pause();
        }
    }

    pub fn end(self: *TicketMutex) void {
        _ = @atomicRmw(u64, &self.serving, .Add, 1, .seq_cst);
    }
};

pub inline fn safeTruncateI64(value: i64) u32 {
    std.debug.assert(value <= 0xFFFFFFFF);
    return @as(u32, @intCast(value));
}

pub inline fn safeTruncateUInt32ToUInt16(value: u32) u16 {
    std.debug.assert(value <= 65535);
    std.debug.assert(value >= 0);
    return @as(u16, @intCast(value));
}

pub inline fn safeTruncateToUInt16(value: i32) u16 {
    std.debug.assert(value <= 65535);
    std.debug.assert(value >= 0);
    return @as(u16, @intCast(value));
}

pub inline fn safeTruncateToInt16(value: i32) i16 {
    std.debug.assert(value <= 32767);
    std.debug.assert(value >= -32768);
    return @as(u16, @intCast(value));
}
