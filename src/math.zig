const intrinsics = @import("intrinsics.zig");
const std = @import("std");

pub const Vector2 = Vector(2, .Position);
pub const Vector3 = Vector(3, .Position);
pub const Vector4 = Vector(4, .Position);
pub const Color3 = Vector(3, .Color);
pub const Color = Vector(4, .Color);

const VectorAccessorStyle = enum {
    Position,
    Color,
};

fn Vector(comptime dimension_count: comptime_int, comptime accessor_style: VectorAccessorStyle) type {
    return extern struct {
        values: @Vector(dimension_count, f32),
        pub const dimensions = dimension_count;

        const Self = @This();

        pub usingnamespace switch (Self.dimensions) {
            inline 2 => struct {
                pub inline fn new(x_value: f32, y_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value } };
                }
                pub inline fn newI(x_value: i32, y_value: i32) Self {
                    return Self{ .values = .{
                        @floatFromInt(x_value),
                        @floatFromInt(y_value),
                    } };
                }

                pub inline fn newU(x_value: u32, y_value: u32) Self {
                    return Self{ .values = .{
                        @floatFromInt(x_value),
                        @floatFromInt(y_value),
                    } };
                }

                pub inline fn perp(self: *const Self) Self {
                    return Self {
                        .values = .{ -self.values[1], self.values[0] }
                    };
                }

                pub usingnamespace switch (accessor_style) {
                    inline .Position => struct {
                        pub inline fn x(self: *const Self) f32 {
                            return self.values[0];
                        }
                        pub inline fn y(self: *const Self) f32 {
                            return self.values[1];
                        }
                        pub inline fn setX(self: *Self, value: f32) *Self {
                            self.values[0] = value;
                            return self;
                        }
                        pub inline fn setY(self: *Self, value: f32) *Self {
                            self.values[1] = value;
                            return self;
                        }
                        pub inline fn toVector3(self: Self, in_z: f32) Vector3 {
                            return Vector3.new(self.x(), self.y(), in_z);
                        }
                        pub inline fn isInRectangle(self: *const Self, rectangle: Rectangle2) bool {
                            const result = ((self.x() >= rectangle.min.x()) and
                                (self.y() >= rectangle.min.y()) and
                                (self.x() < rectangle.max.x()) and
                                (self.y() < rectangle.max.y()));

                            return result;
                        }
                    },
                    else => {
                        unreachable;
                    },
                };
            },
            inline 3 => struct {
                pub inline fn new(x_value: f32, y_value: f32, z_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value, z_value } };
                }

                pub inline fn newI(x_value: i32, y_value: i32, z_value: i32) Self {
                    return Self{ .values = .{
                        @floatFromInt(x_value),
                        @floatFromInt(y_value),
                        @floatFromInt(z_value),
                    } };
                }

                pub inline fn newU(x_value: u32, y_value: u32, z_value: u32) Self {
                    return Self{ .values = .{
                        @floatFromInt(x_value),
                        @floatFromInt(y_value),
                        @floatFromInt(z_value),
                    } };
                }

                pub usingnamespace switch (accessor_style) {
                    inline .Position => struct {
                        pub inline fn x(self: *const Self) f32 {
                            return self.values[0];
                        }
                        pub inline fn y(self: *const Self) f32 {
                            return self.values[1];
                        }
                        pub inline fn z(self: *const Self) f32 {
                            return self.values[2];
                        }
                        pub inline fn xy(self: *const Self) Vector2 {
                            return Vector2.new(self.x(), self.y());
                        }
                        pub inline fn setX(self: *Self, value: f32) *Self {
                            self.values[0] = value;
                            return self;
                        }
                        pub inline fn setY(self: *Self, value: f32) *Self {
                            self.values[1] = value;
                            return self;
                        }
                        pub inline fn setZ(self: *Self, value: f32) *Self {
                            self.values[2] = value;
                            return self;
                        }
                        pub inline fn setXY(self: *Self, value: Vector2) *Self {
                            self.values[0] = value.values[0];
                            self.values[1] = value.values[1];
                            return self;
                        }
                        pub inline fn toVector2(self: *const Self) Vector2 {
                            return Vector2.new(self.x(), self.y());
                        }
                        pub inline fn toVector4(vector3: Vector3, in_w: f32) Self {
                            return Self.new(vector3.values[0], vector3.values[1], vector3.values[2], in_w);
                        }
                        pub inline fn toColor3(self: Self) Color3 {
                            return Color3.new(self.x(), self.y(), self.z());
                        }
                        pub inline fn isInRectangle(self: *const Self, rectangle: Rectangle3) bool {
                            const result = ((self.x() >= rectangle.min.x()) and
                                (self.y() >= rectangle.min.y()) and
                                (self.z() >= rectangle.min.z()) and
                                (self.x() < rectangle.max.x()) and
                                (self.y() < rectangle.max.y()) and
                                (self.z() < rectangle.max.z()));

                            return result;
                        }
                    },
                    inline .Color => struct {
                        pub inline fn r(self: *const Self) f32 {
                            return self.values[0];
                        }
                        pub inline fn g(self: *const Self) f32 {
                            return self.values[1];
                        }
                        pub inline fn b(self: *const Self) f32 {
                            return self.values[2];
                        }
                        pub inline fn setR(self: *Self, value: f32) *Self {
                            self.values[0] = value;
                            return self;
                        }
                        pub inline fn setG(self: *Self, value: f32) *Self {
                            self.values[1] = value;
                            return self;
                        }
                        pub inline fn setB(self: *Self, value: f32) *Self {
                            self.values[2] = value;
                            return self;
                        }
                        pub inline fn toColor(self: Self, in_a: f32) Color {
                            return Color.new(self.r(), self.g(), self.b(), in_a);
                        }
                    },
                };
            },
            inline 4 => struct {
                pub inline fn new(x_value: f32, y_value: f32, z_value: f32, w_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value, z_value, w_value } };
                }

                pub inline fn packColor(self: Self) u32 {
                    return ((intrinsics.roundReal32ToUInt32(self.a() * 255.0) << 24) |
                        (intrinsics.roundReal32ToUInt32(self.r() * 255.0) << 16) |
                        (intrinsics.roundReal32ToUInt32(self.g() * 255.0) << 8) |
                        (intrinsics.roundReal32ToUInt32(self.b() * 255.0) << 0));
                }
                pub inline fn unpackColor(value: u32) Self {
                    return Self.new(
                        @as(f32, @floatFromInt((value >> 16) & 0xFF)),
                        @as(f32, @floatFromInt((value >> 8) & 0xFF)),
                        @as(f32, @floatFromInt((value >> 0) & 0xFF)),
                        @floatFromInt((value >> 24) & 0xFF),
                    );
                }

                pub usingnamespace switch (accessor_style) {
                    inline .Position => struct {
                        pub inline fn x(self: *const Self) f32 {
                            return self.values[0];
                        }
                        pub inline fn y(self: *const Self) f32 {
                            return self.values[1];
                        }
                        pub inline fn z(self: *const Self) f32 {
                            return self.values[2];
                        }
                        pub inline fn w(self: *const Self) f32 {
                            return self.values[3];
                        }
                        pub inline fn xyz(self: *const Self) Vector3 {
                            return Vector3.new(self.x(), self.y(), self.z());
                        }
                        pub inline fn setX(self: *Self, value: f32) *Self {
                            self.values[0] = value;
                            return self;
                        }
                        pub inline fn setY(self: *Self, value: f32) *Self {
                            self.values[1] = value;
                            return self;
                        }
                        pub inline fn setZ(self: *Self, value: f32) *Self {
                            self.values[2] = value;
                            return self;
                        }
                        pub inline fn setW(self: *Self, value: f32) *Self {
                            self.values[3] = value;
                            return self;
                        }
                        pub inline fn setXYZ(self: *Self, value: Vector3) *Self {
                            self.values[0] = value.values[0];
                            self.values[1] = value.values[1];
                            self.values[2] = value.values[2];
                            return self;
                        }
                        pub inline fn setXY(self: *Self, value: Vector2) *Self {
                            self.values[0] = value.values[0];
                            self.values[1] = value.values[1];
                            return self;
                        }
                        pub inline fn toColor(self: Self) Color {
                            return Color.new(self.x(), self.y(), self.z(), self.w());
                        }
                    },
                    inline .Color => struct {
                        pub inline fn r(self: *const Self) f32 {
                            return self.values[0];
                        }
                        pub inline fn g(self: *const Self) f32 {
                            return self.values[1];
                        }
                        pub inline fn b(self: *const Self) f32 {
                            return self.values[2];
                        }
                        pub inline fn a(self: *const Self) f32 {
                            return self.values[3];
                        }
                        pub inline fn rgb(self: *const Self) Color3 {
                            return Color3.new(self.r(), self.g(), self.b());
                        }
                        pub inline fn setR(self: *Self, value: f32) *Self {
                            self.values[0] = value;
                            return self;
                        }
                        pub inline fn setG(self: *Self, value: f32) *Self {
                            self.values[1] = value;
                            return self;
                        }
                        pub inline fn setB(self: *Self, value: f32) *Self {
                            self.values[2] = value;
                            return self;
                        }
                        pub inline fn setA(self: *Self, value: f32) *Self {
                            self.values[3] = value;
                            return self;
                        }
                        pub inline fn setRGB(self: *Self, value: Color3) *Self {
                            self.values[0] = value.values[0];
                            self.values[1] = value.values[1];
                            self.values[2] = value.values[2];
                            return self;
                        }
                        pub inline fn toVector4(self: Self) Vector4 {
                            return Vector4.new(self.r(), self.g(), self.b(), self.a());
                        }
                    },
                };
            },
            else => {
                unreachable;
            },
        };

        pub fn zero() Self {
            return Self{ .values = @splat(0) };
        }

        pub fn splat(value: f32) Self {
            return Self{ .values = @splat(value) };
        }

        pub fn plus(self: *const Self, b: Self) Self {
            return Self{ .values = self.values + b.values };
        }

        pub fn minus(self: *const Self, b: Self) Self {
            return Self{ .values = self.values - b.values };
        }

        pub fn times(self: *const Self, b: Self) Self {
            return Self{ .values = self.values * b.values };
        }

        pub fn dividedBy(self: *const Self, b: Self) Self {
            return Self{ .values = self.values / b.values };
        }

        pub fn scaledTo(self: *const Self, scalar: f32) Self {
            var result = Self{ .values = self.values };

            for (0..dimensions) |axis_index| {
                result.values[axis_index] *= scalar;
            }

            return result;
        }

        pub fn clamp01(self: *const Self) Self {
            var result = Self.zero();

            for (0..dimensions) |axis_index| {
                result.values[axis_index] = clampf01(self.values[axis_index]);
            }

            return result;
        }

        pub fn negated(self: *const Self) Self {
            return Self{ .values = -self.values };
        }

        pub fn dotProduct(self: *const Self, b: Self) f32 {
            var result: f32 = 0;

            for (0..dimensions) |axis_index| {
                result += self.values[axis_index] * b.values[axis_index];
            }

            return result;
        }

        pub fn hadamardProduct(self: *const Self, b: Self) Self {
            var result = Self.zero();

            for (0..dimensions) |axis_index| {
                result.values[axis_index] = self.values[axis_index] * b.values[axis_index];
            }

            return result;
        }

        pub fn lengthSquared(self: *const Self) f32 {
            return self.dotProduct(@constCast(self).*);
        }

        pub fn length(self: *const Self) f32 {
            return @sqrt(self.lengthSquared());
        }

        pub fn invalidPosition() Self {
            var result = Self.zero();

            for (0..dimensions) |axis_index| {
                result.values[axis_index] = 100000;
            }

            return result;
        }

        pub fn lerp(min: Self, max: Self, distance: f32) Self {
            var result = Self.zero();

            for (0..dimensions) |axis_index| {
                result.values[axis_index] = lerpf(min.values[axis_index], max.values[axis_index], distance);
            }

            return result;
        }

        pub fn normalized(self: Self) Self {
            return self.scaledTo(1.0 / self.length());
        }
    };
}

pub const Matrix2x2 = Matrix(2, 2);
pub const Matrix3x3 = Matrix(3, 3);

fn Matrix(comptime row_count: comptime_int, comptime col_count: comptime_int) type {
    return extern struct {
        const VectorType = Vector(col_count, .Position);

        values: [row_count]VectorType,

        const Self = @This();

        pub inline fn plus(self: Self, b: Self) Self {
            var result = self;

            for (0..row_count) |row| {
                result.values[row] = result.values[row].plus(b.values[row]);
            }

            return result;
        }
    };
}

test "add two matrices together" {
    const a = Matrix2x2{
        .values = .{
            Vector2.new(1, 0),
            Vector2.new(0, 1),
        },
    };
    const b = Matrix2x2{
        .values = .{
            Vector2.new(1, 1),
            Vector2.new(1, 1),
        },
    };
    const result = a.plus(b);

    try std.testing.expect(result.values[0].values[0] == 2);
    try std.testing.expect(result.values[0].values[1] == 1);
    try std.testing.expect(result.values[1].values[0] == 1);
    try std.testing.expect(result.values[1].values[1] == 2);
}

pub const Rectangle2 = Rectangle(2);
pub const Rectangle3 = Rectangle(3);

fn Rectangle(comptime dimension_count: comptime_int) type {
    return extern struct {
        const VectorType = Vector(dimension_count, .Position);

        min: VectorType,
        max: VectorType,
        pub const dimensions = dimension_count;

        const Self = @This();

        pub usingnamespace switch (Self.dimensions) {
            inline 2 => struct {
                pub fn toRectangle3(self: Self, min_z: f32, max_z: f32) Rectangle3 {
                    return Rectangle3{
                        .min = self.min.toVector3(min_z),
                        .max = self.max.toVector3(max_z),
                    };
                }
            },
            inline 3 => struct {
                pub fn toRectangle2(self: Self) Rectangle2 {
                    return Rectangle2{
                        .min = self.min.xy(),
                        .max = self.max.xy(),
                    };
                }
            },
            else => {
                unreachable;
            },
        };

        pub fn fromMinMax(min: VectorType, max: VectorType) Self {
            return Self{
                .min = min,
                .max = max,
            };
        }

        pub fn fromMinDimension(min: VectorType, dimension: VectorType) Self {
            return Self{
                .min = min,
                .max = min.plus(dimension),
            };
        }

        pub fn fromCenterHalfDimension(center: VectorType, half_dimension: VectorType) Self {
            return Self{
                .min = center.minus(half_dimension),
                .max = center.plus(half_dimension),
            };
        }

        pub fn fromCenterDimension(center: VectorType, dimension: VectorType) Self {
            return fromCenterHalfDimension(center, dimension.scaledTo(0.5));
        }

        pub fn getMinCorner(self: *const Self) VectorType {
            return self.min;
        }

        pub fn getMaxCorner(self: *const Self) VectorType {
            return self.max;
        }

        pub fn getCenter(self: *const Self) VectorType {
            return self.min.plus(self.max).scale(0.5);
        }

        pub fn getBarycentricPosition(self: *const Self, position: VectorType) VectorType {
            var result = VectorType.zero();

            for (0..dimensions) |axis_index| {
                result.values[axis_index] = safeRatio0(
                    position.values[axis_index] - self.min.values[axis_index],
                    self.max.values[axis_index] - self.min.values[axis_index],
                );
            }

            return result;
        }

        pub fn addRadius(self: *const Self, radius: VectorType) Self {
            return Self{
                .min = self.min.minus(radius),
                .max = self.max.plus(radius),
            };
        }

        pub fn offsetBy(self: *Self, offset: VectorType) Self {
            return Self {
                .min = self.min.add(offset),
                .max = self.max.add(offset),
            };
        }

        pub fn intersects(self: *const Self, b: *const Self) bool {
            var result = true;

            for (0..dimensions) |axis_index| {
                if ((b.max.values[axis_index] <= self.min.values[axis_index]) or
                    (b.min.values[axis_index] >= self.max.values[axis_index]))
                {
                    result = false;
                    break;
                }
            }

            return result;
        }
    };
}

pub fn square(a: f32) f32 {
    return a * a;
}

pub fn lerpf(min: f32, max: f32, distance: f32) f32 {
    return (1.0 - distance) * min + distance * max;
}

pub fn clampf(min: f32, value: f32, max: f32) f32 {
    var result = value;

    if (result < min) {
        result = min;
    }

    if (result > max) {
        result = max;
    }

    return result;
}

pub fn clampf01(value: f32) f32 {
    return clampf(0, value, 1);
}

pub fn safeRatioN(numerator: f32, divisor: f32, fallback: f32) f32 {
    var result: f32 = fallback;

    if (divisor != 0) {
        result = numerator / divisor;
    }

    return result;
}

pub fn safeRatio0(numerator: f32, divisor: f32) f32 {
    return safeRatioN(numerator, divisor, 0);
}

pub fn safeRatio1(numerator: f32, divisor: f32) f32 {
    return safeRatioN(numerator, divisor, 1);
}
