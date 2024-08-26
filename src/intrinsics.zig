const std = @import("std");

pub inline fn signOf(value: i32) i32 {
    return if (value >= 0) 1 else -1;
}

pub inline fn squareRoot(value: f32) f32 {
    return @sqrt(value);
}

pub inline fn absoluteValue(value: f32) f32 {
    return @abs(value);
}

pub inline fn rotateLeft(value: u32, amount: i32) u32 {
    return std.math.rotl(u32, value, amount);
}

pub inline fn rotateRight(value: u32, amount: i32) u32 {
    return std.math.rotr(u32, value, amount);
}

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

pub inline fn ceilReal32ToInt32(value: f32) i32 {
    return @intFromFloat(@ceil(value));
}

pub inline fn ceilReal32ToUInt32(value: f32) u32 {
    return @intFromFloat(@ceil(value));
}

pub inline fn sin(angle: f32) f32 {
    return @sin(angle);
}

pub inline fn cos(angle: f32) f32 {
    return @cos(angle);
}

pub inline fn atan2(y: f32, x: f32) f32 {
    return std.math.atan2(y, x);
}

pub const BitScanResult = struct {
    found: bool = false,
    index: u32 = undefined,
};

pub fn findLeastSignificantSetBit(value: u32) BitScanResult {
    var result = BitScanResult{};

    // for (0..32) |shift_index| {
    //     if ((value & (@as(u64, @intCast(1)) << @as(u6, @intCast(shift_index)))) != 0) {
    //         result.index = @intCast(shift_index);
    //         result.found = true;
    //         break;
    //     }
    // }

    result.index = asm (
        \\bsf %[value], %[index]
        : [index] "={eax}" (-> u32),
        : [value] "{eax}" (value),
    );
    result.found = true;

    return result;
}
