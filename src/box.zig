const math = @import("math.zig");
const lighting = @import("lighting.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

// Types.
const Vector3 = math.Vector3;

///
/// A P     XAXIS       YAXIS
/// 0 0   0, -1,  0   0,  0,  1
/// 0 1   0,  1,  0   0,  0,  1
/// 1 0   1,  0,  0   0,  0,  1
/// 1 1  -1,  0,  0   0,  0,  1
/// 2 0  -1,  0,  0   0,  1,  0
/// 2 1   1,  0,  0   0,  1,  0
///
pub const BoxSurfaceIndex = enum(u32) {
    West,
    East,
    South,
    North,
    Down,
    Up,
};

const BoxMask_West: u32 = (1 << @intFromEnum(BoxSurfaceIndex.West));
const BoxMask_East: u32 = (1 << @intFromEnum(BoxSurfaceIndex.East));
const BoxMask_South: u32 = (1 << @intFromEnum(BoxSurfaceIndex.South));
const BoxMask_North: u32 = (1 << @intFromEnum(BoxSurfaceIndex.North));
const BoxMask_Down: u32 = (1 << @intFromEnum(BoxSurfaceIndex.Down));
const BoxMask_Up: u32 = (1 << @intFromEnum(BoxSurfaceIndex.Up));

pub const BoxSurfaceMask = enum(u32) {
    West = BoxMask_West,
    East = BoxMask_East,
    South = BoxMask_South,
    North = BoxMask_North,
    Down = BoxMask_Down,
    Up = BoxMask_Up,

    Planar = (BoxMask_West |
        BoxMask_East |
        BoxMask_South |
        BoxMask_North),

    Vertical = (BoxMask_Up |
        BoxMask_Down),

    pub fn getComplement(box_mask: u32) u32 {
        const bit_mask: u32 = ((1 << 0) | (1 << 2) | (1 << 4));
        const just_024: u32 = box_mask & bit_mask;
        const just_135: u32 = box_mask & (bit_mask << 1);

        const result: u32 = ((just_024 << 1) | (just_135 >> 1));

        return result;
    }
};

pub const BoxSurfaceParams = struct {
    axis_index: u32,
    positive: u32,
};

pub fn getBoxSurfaceParams(surface_index: u32) BoxSurfaceParams {
    return .{
        .axis_index = surface_index >> 1,
        .positive = surface_index & 0x1,
    };
}

pub fn getSurfaceIndex(axis_index: u32, positive: u32) u32 {
    std.debug.assert(positive <= 1);
    std.debug.assert(axis_index <= 2);

    return (axis_index << 1) | positive;
}

pub fn getSurfaceIndexFromDirectionMask(direction_mask: u32) BoxSurfaceIndex {
    const scan: intrinsics.BitScanResult = intrinsics.findLeastSignificantSetBit(direction_mask);
    std.debug.assert(scan.found);
    std.debug.assert(scan.index >= 0 and scan.index <= @intFromEnum(BoxSurfaceIndex.Up));

    const result: BoxSurfaceIndex = @enumFromInt(scan.index);
    std.debug.assert(getSurfaceMaskFromSurface(result) == direction_mask);

    return result;
}

pub fn getSurfaceMask(axis_index: u32, positive: u32) u32 {
    return @as(u8, 1) << @intCast(getSurfaceIndex(axis_index, positive));
}

pub fn getSurfaceMaskFromSurface(surface_index: BoxSurfaceIndex) u32 {
    return @as(u8, 1) << @intCast(@intFromEnum(surface_index));
}

pub const LightBoxSurface = struct {
    position: Vector3,
    normal: Vector3,
    x_axis: Vector3,
    y_axis: Vector3,
    half_width: f32,
    half_height: f32,
};

pub fn getBoxSurface(position_in: Vector3, radius: Vector3, surface_index: u32) LightBoxSurface {
    const params: BoxSurfaceParams = getBoxSurfaceParams(surface_index);
    const axis_index: u32 = params.axis_index;
    const positive: u32 = params.positive;

    var normal: Vector3 = .zero();
    var y_axis: Vector3 = if (axis_index == 2) .new(0, 1, 0) else .new(0, 0, 1);

    var position: Vector3 = position_in;
    if (positive == 1) {
        normal.values[axis_index] = 1;
        position.values[axis_index] += radius.values[axis_index];
    } else {
        normal.values[axis_index] = -1;
        position.values[axis_index] -= radius.values[axis_index];
    }

    var sign_x: f32 = if (positive == 1) 1 else -1;
    if (axis_index == 1) {
        sign_x *= -1;
    }
    var x_axis: Vector3 = if (axis_index == 0) .new(0, sign_x, 0) else .new(sign_x, 0, 0);

    const half_width: f32 = intrinsics.absoluteValue(x_axis.dotProduct(radius));
    const half_height: f32 = intrinsics.absoluteValue(y_axis.dotProduct(radius));

    const result: LightBoxSurface = .{
        .position = position,
        .normal = normal,
        .x_axis = x_axis,
        .y_axis = y_axis,
        .half_width = half_width,
        .half_height = half_height,
    };

    return result;
}
