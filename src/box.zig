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

pub const BoxSurfaceMask = enum(u32) {
    West = (1 << @intFromEnum(BoxSurfaceIndex.West)),
    East = (1 << @intFromEnum(BoxSurfaceIndex.East)),
    South = (1 << @intFromEnum(BoxSurfaceIndex.South)),
    North = (1 << @intFromEnum(BoxSurfaceIndex.North)),
    Down = (1 << @intFromEnum(BoxSurfaceIndex.Down)),
    Up = (1 << @intFromEnum(BoxSurfaceIndex.Up)),

    Planar = (@intFromEnum(BoxSurfaceIndex.West) |
        @intFromEnum(BoxSurfaceIndex.East) |
        @intFromEnum(BoxSurfaceIndex.South) |
        @intFromEnum(BoxSurfaceIndex.North)),
    Vertical = (@intFromEnum(BoxSurfaceIndex.Up) |
        @intFromEnum(BoxSurfaceIndex.Down)),

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

pub fn getSurfaceMask(axis_index: u32, positive: u32) u32 {
    return @as(u8, 1) << @intCast(getSurfaceIndex(axis_index, positive));
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
