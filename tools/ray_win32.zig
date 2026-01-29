const std = @import("std");
const math = @import("math");
const ray = @import("ray.zig");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("math.h");
    @cInclude("time.h");
    @cInclude("windows.h");
});

// Note: This doesn't work with the current build setup.
fn lockedAddAndReturnPreviousValue(value: *u64, addend: u64) u64 {
    return @intCast(c.InterlockedExchangeAdd64(@ptrCast(value), @intCast(addend)));
}

fn workerThread(lp_parameter: *anyopaque) callconv(.winapi) c.DWORD {
    const queue: *ray.WorkQueue = @ptrCast(@alignCast(lp_parameter));
    while (ray.renderTile(queue)) {}
    return 0;
}

pub fn createWorkThread(parameter: *anyopaque) void {
    var thread_id: c.DWORD = undefined;
    const thread_handle: c.HANDLE = c.CreateThread(null, 0, @ptrCast(&workerThread), parameter, 0, &thread_id);
    _ = c.CloseHandle(thread_handle);
}

pub fn getCPUCoreCount() u32 {
    var info: c.SYSTEM_INFO = undefined;
    c.GetSystemInfo(&info);
    return info.dwNumberOfProcessors;
}
