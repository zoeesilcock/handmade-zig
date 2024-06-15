const std = @import("std");

pub inline fn roundReal32ToInt32(value: f32) i32 {
    return @intFromFloat(@round(value));
}

pub inline fn roundReal32ToUInt32(value: f32) u32 {
    return @intFromFloat(@round(value));
}

pub inline fn floorReal32ToInt32(value: f32) i32 {
    return @intFromFloat(@floor(value));
}

pub inline fn floorReal32ToUInt32(value: f32) u32 {
    return @intFromFloat(@floor(value));
}

pub inline fn sin(angle: f32) f32 {
    return @sin(angle);
}

pub inline fn cos(angle: f32) f32 {
    return @cos(angle);
}

pub inline fn atan2(y: f32, x: f32) f32 {
    // TODO: Implement this.
    _ = y;
    _ = x;

    return 0.0;
}
