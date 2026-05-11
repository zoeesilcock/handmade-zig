const std = @import("std");
const box = @import("box.zig");

const X = 0;
const Y = 1;
const Z = 2;

pub const GenVector3 = [3]i32;

pub fn plusV3(a: GenVector3, b: GenVector3) GenVector3 {
    const result: GenVector3 = .{
        a[0] + b[0],
        a[1] + b[1],
        a[2] + b[2],
    };
    return result;
}

pub fn getDirection(direction: box.BoxSurfaceIndex) GenVector3 {
    var result: GenVector3 = .{ 0, 0, 0 };
    const params: box.BoxSurfaceParams = box.getBoxSurfaceParams(@intFromEnum(direction));
    result[params.axis_index] = if (params.positive > 0) 1 else -1;
    return result;
}

/// Volumes include their min and their max. They are inclusive on both ends of the interval.
pub const GenVolume = struct {
    min: GenVector3,
    max: GenVector3,

    pub fn zero() GenVolume {
        return .{
            .min = .{ 0, 0, 0 },
            .max = .{ 0, 0, 0 },
        };
    }

    pub fn infinityVolume() GenVolume {
        return .{
            .min = .{
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
            },
            .max = .{
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
            },
        };
    }

    pub fn invalidInfinityVolume() GenVolume {
        return .{
            .min = .{
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
            },
            .max = .{
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
            },
        };
    }

    pub fn invertedInfinityVolume() GenVolume {
        return .{
            //
        };
    }

    pub fn unionWith(self: GenVolume, other: GenVolume) GenVolume {
        _ = self;
        _ = other;
        return .{
            //
        };
    }

    pub fn getDimension(self: GenVolume) GenVector3 {
        return .{
            self.max[X] - self.min[X] + 1,
            self.max[Y] - self.min[Y] + 1,
            self.max[Z] - self.min[Z] + 1,
        };
    }

    pub fn getMaxVolumeFor(min: GenVolume, max: GenVolume) GenVolume {
        return .{
            .min = min.min,
            .max = max.max,
        };
    }

    pub fn getUnionWith(self: *GenVolume, other: *GenVolume) GenVolume {
        var result: GenVolume = .zero();

        var dimension: u32 = 0;
        while (dimension < 3) : (dimension += 1) {
            result.min[dimension] = @min(self.min[dimension], other.min[dimension]);
            result.max[dimension] = @max(self.max[dimension], other.max[dimension]);
        }

        return result;
    }

    pub fn getIntersectionWith(self: *GenVolume, other: *GenVolume) GenVolume {
        var result: GenVolume = .zero();

        var dimension: u32 = 0;
        while (dimension < 3) : (dimension += 1) {
            result.min[dimension] = @max(self.min[dimension], other.min[dimension]);
            result.max[dimension] = @min(self.max[dimension], other.max[dimension]);
        }

        return result;
    }

    pub fn isMinimumDimensionsForRoom(self: GenVolume) bool {
        const dimension: GenVector3 = self.getDimension();

        const result =
            dimension[X] >= 4 and
            dimension[Y] >= 4 and
            dimension[Z] >= 1;

        return result;
    }

    pub fn hasVolume(self: GenVolume) bool {
        const dimension: GenVector3 = self.getDimension();

        const result =
            dimension[X] > 0 and
            dimension[Y] > 0 and
            dimension[Z] > 0;

        return result;
    }

    pub fn clipMin(self: *GenVolume, dimension: u32, value: i32) void {
        if (self.min[dimension] < value) {
            self.min[dimension] = value;
        }
    }

    pub fn clipMax(self: *GenVolume, dimension: u32, value: i32) void {
        if (self.max[dimension] > value) {
            self.max[dimension] = value;
        }
    }

    pub fn isInVolume(self: *GenVolume, x: i32, y: i32, z: i32) bool {
        const result: bool =
            (x >= self.min[X] and x <= self.max[X]) and
            (y >= self.min[Y] and y <= self.max[Y]) and
            (z >= self.min[Z] and z <= self.max[Z]);

        return result;
    }

    pub fn addRadius(self: *GenVolume, radius: GenVector3) void {
        self.min[0] -= radius[0];
        self.min[1] -= radius[1];
        self.min[2] -= radius[2];

        self.max[0] += radius[0];
        self.max[1] += radius[1];
        self.max[2] += radius[2];
    }
};
