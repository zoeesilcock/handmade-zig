const std = @import("std");
const box = @import("box.zig");
const math = @import("math.zig");

pub const Vector3i = math.Vector3i;

pub fn getDirection(direction: box.BoxSurfaceIndex) Vector3i {
    var result: Vector3i = .zero();
    const params: box.BoxSurfaceParams = box.getBoxSurfaceParams(@intFromEnum(direction));
    result.setValueAt(params.axis_index, if (params.positive > 0) 1 else -1);
    return result;
}

pub fn getTotalVolume(dimension: Vector3i) i32 {
    return dimension.x() * dimension.y() * dimension.z();
}

pub fn isInArrayBounds(bounds: Vector3i, position: Vector3i) bool {
    const result: bool =
        (position.x() >= 0 and position.x() < bounds.x()) and
        (position.y() >= 0 and position.y() < bounds.y()) and
        (position.z() >= 0 and position.z() < bounds.z());
    return result;
}

/// Volumes include their min and their max. They are inclusive on both ends of the interval.
pub const GenVolume = struct {
    min: Vector3i,
    max: Vector3i,

    pub fn zero() GenVolume {
        return .{
            .min = .zero(),
            .max = .zero(),
        };
    }

    pub fn infinityVolume() GenVolume {
        return .{
            .min = .new(
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
            ),
            .max = .new(
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
            ),
        };
    }

    pub fn invalidInfinityVolume() GenVolume {
        return .{
            .min = .new(
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
                std.math.maxInt(i32) / 4,
            ),
            .max = .new(
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
                std.math.minInt(i32) / 4,
            ),
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

    pub fn getDimension(self: GenVolume) Vector3i {
        return .new(
            self.max.x() - self.min.x() + 1,
            self.max.y() - self.min.y() + 1,
            self.max.z() - self.min.z() + 1,
        );
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
            result.min.setValueAt(dimension, @max(self.min.valueAt(dimension), other.min.valueAt(dimension)));
            result.max.setValueAt(dimension, @min(self.max.valueAt(dimension), other.max.valueAt(dimension)));
        }

        return result;
    }

    pub fn isMinimumDimensionsForRoom(self: GenVolume) bool {
        const dimension: Vector3i = self.getDimension();

        const result =
            dimension.x() >= 4 and
            dimension.y() >= 4 and
            dimension.z() >= 1;

        return result;
    }

    pub fn hasVolume(self: GenVolume) bool {
        const dimension: Vector3i = self.getDimension();

        const result =
            dimension.x() > 0 and
            dimension.y() > 0 and
            dimension.z() > 0;

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
            (x >= self.min.x() and x <= self.max.x()) and
            (y >= self.min.y() and y <= self.max.y()) and
            (z >= self.min.z() and z <= self.max.z());

        return result;
    }

    pub fn isInVolumeV3(self: *GenVolume, position: Vector3i) bool {
        return self.isInVolume(position.x(), position.y(), position.z());
    }

    pub fn addRadius(self: *GenVolume, radius: Vector3i) GenVolume {
        var result = self.*;

        _ = result.min.setX(result.min.x() - radius.x());
        _ = result.min.setY(result.min.y() - radius.y());
        _ = result.min.setZ(result.min.z() - radius.z());

        _ = result.max.setX(result.max.x() + radius.x());
        _ = result.max.setY(result.max.y() + radius.y());
        _ = result.max.setZ(result.max.z() + radius.z());

        return result;
    }
};
