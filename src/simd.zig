const std = @import("std");
const math = @import("math.zig");

const Vector3 = math.Vector3;

pub const F32_4x = @Vector(4, f32);
pub const U32_4x = @Vector(4, u32);
pub const I32_4x = @Vector(4, i32);
pub const Bool_4x = @Vector(4, bool);

fn mmMovemaskPs(input: Bool_4x) u8 {
    var mask: u8 = 0;
    if (input[0]) mask |= 1;
    if (input[1]) mask |= 2;
    if (input[2]) mask |= 4;
    if (input[3]) mask |= 8;

    return mask;
}

test "mmMovemaskPs sanity" {
    const all_ones: I32_4x = @splat(1);
    const all_zeroes: I32_4x = @splat(0);
    const single_one: I32_4x = .{ 0, 0, 1, 0 };
    try std.testing.expect(mmMovemaskPs(all_ones == single_one) != 0);
    try std.testing.expectEqual(15, mmMovemaskPs(all_ones == all_ones));
    try std.testing.expectEqual(0, mmMovemaskPs(all_ones == all_zeroes));
}

pub fn anyTrue(comparison: Bool_4x) bool {
    return mmMovemaskPs(comparison) != 0;
}

pub fn allTrue(comparison: Bool_4x) bool {
    return mmMovemaskPs(comparison) == 15;
}

pub fn allFalse(comparison: Bool_4x) bool {
    return mmMovemaskPs(comparison) == 0;
}

fn approxInvSquareRoot(input: F32_4x) F32_4x {
    return @as(F32_4x, @splat(1)) / @sqrt(input);
}

pub const V3_4x = extern struct {
    x: F32_4x,
    y: F32_4x,
    z: F32_4x,

    pub fn new(in0: Vector3, in1: Vector3, in2: Vector3, in3: Vector3) V3_4x {
        return .{
            .x = .{ in0.x(), in1.x(), in2.x(), in3.x() },
            .y = .{ in0.y(), in1.y(), in2.y(), in3.y() },
            .z = .{ in0.z(), in1.z(), in2.z(), in3.z() },
        };
    }

    pub fn fromAxes(in_x: F32_4x, in_y: F32_4x, in_z: F32_4x) V3_4x {
        return .{ .x = in_x, .y = in_y, .z = in_z };
    }

    pub fn fromVector3(in: Vector3) V3_4x {
        return .{
            .x = @splat(in.x()),
            .y = @splat(in.y()),
            .z = @splat(in.z()),
        };
    }

    pub fn fromScalar(in0: f32, in1: f32, in2: f32, in3: f32) V3_4x {
        return .{
            .x = .{ in0, in1, in2, in3 },
            .y = .{ in0, in1, in2, in3 },
            .z = .{ in0, in1, in2, in3 },
        };
    }

    pub fn splat(in: F32_4x) V3_4x {
        return .{
            .x = in,
            .y = in,
            .z = in,
        };
    }

    pub fn getComponent(self: V3_4x, c_index: u32) Vector3 {
        return .new(self.x[c_index], self.y[c_index], self.z[c_index]);
    }

    pub fn min(self: V3_4x, b: V3_4x) V3_4x {
        return .{
            .x = @min(self.x, b.x),
            .y = @min(self.y, b.y),
            .z = @min(self.z, b.z),
        };
    }

    pub fn max(self: V3_4x, b: V3_4x) V3_4x {
        return .{
            .x = @max(self.x, b.x),
            .y = @max(self.y, b.y),
            .z = @max(self.z, b.z),
        };
    }

    pub fn select(self: V3_4x, mask: Bool_4x, b: V3_4x) V3_4x {
        return .{
            .x = @select(f32, mask, b.x, self.z),
            .y = @select(f32, mask, b.y, self.y),
            .z = @select(f32, mask, b.z, self.z),
        };
    }

    pub fn getLane(self: V3_4x, index: u32) F32_4x {
        return switch (index) {
            0 => self.x,
            1 => self.y,
            2 => self.z,
            else => unreachable,
        };
    }

    pub fn setLane(self: *V3_4x, index: u32, in: F32_4x) void {
        switch (index) {
            0 => self.x = in,
            1 => self.y = in,
            2 => self.z = in,
            else => unreachable,
        }
    }

    pub fn absoluteValue(self: V3_4x) V3_4x {
        const mask: U32_4x = @splat(~@as(u32, 1 << 31));

        const result: V3_4x = .{
            .x = @bitCast(@as(U32_4x, @bitCast(self.x)) & mask),
            .y = @bitCast(@as(U32_4x, @bitCast(self.y)) & mask),
            .z = @bitCast(@as(U32_4x, @bitCast(self.z)) & mask),
        };

        return result;

        // return .{
        //     .x = @abs(self.x),
        //     .y = @abs(self.y),
        //     .z = @abs(self.z),
        // };
    }

    pub fn lessThan(self: V3_4x, b: V3_4x) V3_4x {
        const result: V3_4x = .{
            .x = @floatFromInt(@intFromBool(self.x < b.x)),
            .y = @floatFromInt(@intFromBool(self.y < b.y)),
            .z = @floatFromInt(@intFromBool(self.z < b.z)),
        };
        return result;
    }

    pub fn lessThanOrEqualTo(self: V3_4x, b: V3_4x) V3_4x {
        const result: V3_4x = .{
            .x = @floatFromInt(@intFromBool(self.x <= b.x)),
            .y = @floatFromInt(@intFromBool(self.y <= b.y)),
            .z = @floatFromInt(@intFromBool(self.z <= b.z)),
        };
        return result;
    }

    pub fn any3TrueInAtLeastOneLane(self: V3_4x) bool {
        const result: bool = anyTrue(
            (@as(U32_4x, @bitCast(self.x)) | @as(U32_4x, @bitCast(self.y)) | @as(U32_4x, @bitCast(self.z))) ==
                @as(U32_4x, @splat(0xFFFFFFFF)),
        );
        return result;
    }

    pub fn all3TrueInAtLeastOneLane(self: V3_4x) bool {
        return anyTrue(
            (@as(U32_4x, @bitCast(self.x)) & @as(U32_4x, @bitCast(self.y)) & @as(U32_4x, @bitCast(self.z))) ==
                @as(U32_4x, @splat(0xFFFFFFFF)),
        );
    }

    pub fn plus(self: V3_4x, other: V3_4x) V3_4x {
        var result = self;
        result.x += other.x;
        result.y += other.y;
        result.z += other.z;
        return result;
    }

    pub fn minus(self: V3_4x, other: V3_4x) V3_4x {
        var result = self;
        result.x -= other.x;
        result.y -= other.y;
        result.z -= other.z;
        return result;
    }

    pub fn negated(self: V3_4x) V3_4x {
        const zero: F32_4x = @splat(0);
        var result = self;
        result.x = zero - self.x;
        result.y = zero - self.y;
        result.z = zero - self.z;
        return result;

        // var result = self;
        // result.x = -self.x;
        // result.y = -self.y;
        // result.z = -self.z;
        // return result;
    }

    pub fn scaledTo(self: V3_4x, scalar: f32) V3_4x {
        var result = self;
        result.x *= @splat(scalar);
        result.y *= @splat(scalar);
        result.z *= @splat(scalar);
        return result;
    }

    pub fn scaledToV(self: V3_4x, v: F32_4x) V3_4x {
        var result = self;
        result.x *= v;
        result.y *= v;
        result.z *= v;
        return result;
    }

    pub fn dividedBy(self: V3_4x, b: V3_4x) V3_4x {
        var result = self;
        result.x /= b.x;
        result.y /= b.y;
        result.z /= b.z;
        return result;
    }

    pub fn times(self: V3_4x, b: V3_4x) V3_4x {
        var result = self;
        result.x *= b.x;
        result.y *= b.y;
        result.z *= b.z;
        return result;
    }

    pub fn lengthSquared(self: *const V3_4x) F32_4x {
        return self.dotProduct(self.*);
    }

    pub fn approxNormalizeOrZero(self: V3_4x) V3_4x {
        var result: V3_4x = self;

        const length_squared: F32_4x = self.lengthSquared();
        const normalized: V3_4x = self.scaledToV(approxInvSquareRoot(length_squared));
        const limit: F32_4x = @splat(0.0001);
        const mask: Bool_4x = (length_squared > (limit * limit));

        result = result.select(mask, normalized);

        return result;
    }

    pub fn dotProduct(self: V3_4x, other: V3_4x) F32_4x {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
};

pub const V4_4x = extern struct {
    r: F32_4x,
    g: F32_4x,
    b: F32_4x,
    a: F32_4x,

    pub fn plus(self: V4_4x, other: V4_4x) V4_4x {
        var result = self;
        result.r += other.r;
        result.g += other.g;
        result.b += other.b;
        result.a += other.a;
        return result;
    }

    pub fn scaledTo(self: V4_4x, scalar: f32) V4_4x {
        var result = self;
        result.r *= @splat(scalar);
        result.g *= @splat(scalar);
        result.b *= @splat(scalar);
        result.a *= @splat(scalar);
        return result;
    }
};

pub fn mmSetExpr(comptime method: anytype, args: anytype) F32_4x {
    return [_]f32{
        @call(.auto, method, args),
        @call(.auto, method, args),
        @call(.auto, method, args),
        @call(.auto, method, args),
    };
}
