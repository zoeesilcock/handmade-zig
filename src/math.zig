pub const Vector2 = Vector(2);
pub const Vector3 = Vector(3);
pub const Color = Vector(4);

fn Vector(comptime in_dimensions: comptime_int) type {
    return struct{
        data: @Vector(in_dimensions, f32),
        pub const dimensions = in_dimensions;

        const Self = @This();

        pub usingnamespace switch (Self.dimensions) {
            inline 2 => struct {
                pub inline fn new(x_value: f32, y_value: f32) Self {
                    return Self{ .data = .{ x_value, y_value } };
                }
                pub inline fn zero() Self {
                    return Self{ .data = .{ 0, 0 } };
                }

                pub inline fn x(self: *const Self) f32 {
                    return self.data[0];
                }
                pub inline fn y(self: *const Self) f32 {
                    return self.data[1];
                }
                pub inline fn isInRectangle(self: *const Self, rectangle: Rectangle2) bool {
                    const result = ((self.x() >= rectangle.min.x()) and
                        (self.y() >= rectangle.min.y()) and
                        (self.x() < rectangle.max.x()) and
                        (self.y() < rectangle.max.y()));

                    return result;
                }
            },
            inline 3 => struct {
                pub inline fn new(x_value: f32, y_value: f32, z_value: f32) Self {
                    return Self{ .data = .{ x_value, y_value, z_value } };
                }
                pub inline fn zero() Self {
                    return Self{ .data = .{ 0, 0, 0 } };
                }

                pub inline fn x(self: *const Self) f32 {
                    return self.data[0];
                }
                pub inline fn y(self: *const Self) f32 {
                    return self.data[1];
                }
                pub inline fn z(self: *const Self) f32 {
                    return self.data[2];
                }
            },
            inline 4 => struct {
                pub inline fn new(x_value: f32, y_value: f32, z_value: f32, w_value: f32) Self {
                    return Self{ .data = .{ x_value, y_value, z_value, w_value } };
                }
                pub inline fn zero() Self {
                    return Self{ .data = .{ 0, 0, 0, 0 } };
                }

                pub inline fn x(self: *const Self) f32 {
                    return self.data[0];
                }
                pub inline fn y(self: *const Self) f32 {
                    return self.data[1];
                }
                pub inline fn z(self: *const Self) f32 {
                    return self.data[2];
                }
                pub inline fn w(self: *const Self) f32 {
                    return self.data[3];
                }

                pub inline fn r(self: *const Self) f32 {
                    return self.data[0];
                }
                pub inline fn g(self: *const Self) f32 {
                    return self.data[1];
                }
                pub inline fn b(self: *const Self) f32 {
                    return self.data[2];
                }
                pub inline fn a(self: *const Self) f32 {
                    return self.data[3];
                }
            },
            else => {
                unreachable;
            },
        };

        pub fn add(self: *const Self, b: Self) Self {
            return Self{
                .data = self.data + b.data
            };
        }

        pub fn sub(self: *const Self, b: Self) Self {
            return Self{
                .data = self.data - b.data
            };
        }

        pub fn mul(self: *const Self, b: Self) Self {
            return Self{
                .data = self.data * b.data
            };
        }

        pub fn div(self: *const Self, b: Self) Self {
            return Self{
                .data = self.data / b.data
            };
        }

        pub fn scale(self: *const Self, scalar: f32) Self {
            var result = Self{
                .data = self.data
            };

            for (0..dimensions) |index| {
                result.data[index] *= scalar;
            }

            return result;
        }

        pub fn negate(self: *const Self) Self {
            return Self{
                .data = -self.data
            };
        }

        pub fn dot(self: *const Self, b: Self) f32 {
            var result: f32 = 0;

            for (0..dimensions) |index| {
                result += self.data[index] * b.data[index];
            }

            return result;
        }

        pub fn lengthSquared(self: *const Self) f32 {
            return self.dot(@constCast(self).*);
        }
    };
}

pub const Rectangle2 = struct {
    min: Vector2 = Vector2.zero(),
    max: Vector2 = Vector2.zero(),

    pub fn fromMinMax(min: Vector2, max: Vector2) Rectangle2 {
        return Rectangle2{
            .min = min,
            .max = max,
        };
    }

    pub fn fromMinDimension(min: Vector2, dimension: Vector2) Rectangle2 {
        return Rectangle2{
            .min = min,
            .max = min.add(dimension),
        };
    }

    pub fn fromCenterHalfDimension(center: Vector2, half_dimension: Vector2) Rectangle2 {
        return Rectangle2{
            .min = center.sub(half_dimension),
            .max = center.add(half_dimension),
        };
    }

    pub fn fromCenterDimension(center: Vector2, dimension: Vector2) Rectangle2 {
        return fromCenterHalfDimension(center, dimension.scale(0.5));
    }

    pub fn getMinCorner(self: Rectangle2) Vector2 {
        return self.min;
    }
    pub fn getMaxCorner(self: Rectangle2) Vector2 {
        return self.max;
    }
    pub fn getCenter(self: Rectangle2) Vector2 {
        return self.min.add(self.max).scale(0.5);
    }
};

pub fn square(a: f32) f32 {
    return a * a;
}

