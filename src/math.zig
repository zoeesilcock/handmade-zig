pub const Vector2 = Vector(2);
pub const Vector3 = Vector(3);
pub const Color = Vector(4);

fn Vector(comptime dimension_count: comptime_int) type {
    return struct{
        values: @Vector(dimension_count, f32),
        pub const dimensions = dimension_count;

        const Self = @This();

        pub usingnamespace switch (Self.dimensions) {
            inline 2 => struct {
                pub inline fn new(x_value: f32, y_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value } };
                }
                pub inline fn zero() Self {
                    return Self{ .values = .{ 0, 0 } };
                }

                pub inline fn x(self: *const Self) f32 {
                    return self.values[0];
                }
                pub inline fn y(self: *const Self) f32 {
                    return self.values[1];
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
                    return Self{ .values = .{ x_value, y_value, z_value } };
                }
                pub inline fn zero() Self {
                    return Self{ .values = .{ 0, 0, 0 } };
                }

                pub inline fn x(self: *const Self) f32 {
                    return self.values[0];
                }
                pub inline fn y(self: *const Self) f32 {
                    return self.values[1];
                }
                pub inline fn z(self: *const Self) f32 {
                    return self.values[2];
                }
            },
            inline 4 => struct {
                pub inline fn new(x_value: f32, y_value: f32, z_value: f32, w_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value, z_value, w_value } };
                }
                pub inline fn zero() Self {
                    return Self{ .values = .{ 0, 0, 0, 0 } };
                }

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
            },
            else => {
                unreachable;
            },
        };

        pub fn plus(self: *const Self, b: Self) Self {
            return Self{
                .values = self.values + b.values
            };
        }

        pub fn minus(self: *const Self, b: Self) Self {
            return Self{
                .values = self.values - b.values
            };
        }

        pub fn times(self: *const Self, b: Self) Self {
            return Self{
                .values = self.values * b.values
            };
        }

        pub fn dividedBy(self: *const Self, b: Self) Self {
            return Self{
                .values = self.values / b.values
            };
        }

        pub fn scaledTo(self: *const Self, scalar: f32) Self {
            var result = Self{
                .values = self.values
            };

            for (0..dimensions) |index| {
                result.values[index] *= scalar;
            }

            return result;
        }

        pub fn negated(self: *const Self) Self {
            return Self{
                .values = -self.values
            };
        }

        pub fn dotProduct(self: *const Self, b: Self) f32 {
            var result: f32 = 0;

            for (0..dimensions) |index| {
                result += self.values[index] * b.values[index];
            }

            return result;
        }

        pub fn lengthSquared(self: *const Self) f32 {
            return self.dotProduct(@constCast(self).*);
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
            .max = min.plus(dimension),
        };
    }

    pub fn fromCenterHalfDimension(center: Vector2, half_dimension: Vector2) Rectangle2 {
        return Rectangle2{
            .min = center.minus(half_dimension),
            .max = center.plus(half_dimension),
        };
    }

    pub fn fromCenterDimension(center: Vector2, dimension: Vector2) Rectangle2 {
        return fromCenterHalfDimension(center, dimension.scaledTo(0.5));
    }

    pub fn getMinCorner(self: Rectangle2) Vector2 {
        return self.min;
    }
    pub fn getMaxCorner(self: Rectangle2) Vector2 {
        return self.max;
    }
    pub fn getCenter(self: Rectangle2) Vector2 {
        return self.min.plus(self.max).scale(0.5);
    }
};

pub fn square(a: f32) f32 {
    return a * a;
}

