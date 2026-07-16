const std = @import("std");
const math = @import("math");
const ray = @import("ray.zig");
const win32 = @import("win32").everything;

// Note: This doesn't work with the current build setup.
fn lockedAddAndReturnPreviousValue(value: *u64, addend: u64) u64 {
    return @intCast(win32.InterlockedExchangeAdd64(@ptrCast(value), @intCast(addend)));
}

fn workerThread(lp_parameter: *anyopaque) callconv(.winapi) std.os.windows.DWORD {
    const queue: *ray.WorkQueue = @ptrCast(@alignCast(lp_parameter));
    while (ray.renderTile(queue)) {}
    return 0;
}

pub fn createWorkThread(parameter: *anyopaque) void {
    var thread_id: std.os.windows.DWORD = undefined;
    const thread_handle: ?std.os.windows.HANDLE = win32.CreateThread(
        null,
        0,
        @ptrCast(&workerThread),
        parameter,
        .{},
        &thread_id,
    );
    _ = win32.CloseHandle(thread_handle);
}

pub fn getCPUCoreCount() u32 {
    var info: win32.SYSTEM_INFO = undefined;
    win32.GetSystemInfo(&info);
    return info.dwNumberOfProcessors;
}
