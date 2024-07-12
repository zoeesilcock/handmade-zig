pub const Vector2 = Vector(2, .Position);
pub const Vector3 = Vector(3, .Position);
pub const Color = Vector(4, .Color);

const VectorAccessorStyle = enum {
    Position,
    Color,
};

fn Vector(comptime dimension_count: comptime_int, comptime accessor_style: VectorAccessorStyle) type {
    return struct {
        values: @Vector(dimension_count, f32),
        pub const dimensions = dimension_count;

        const Self = @This();

        pub usingnamespace switch (Self.dimensions) {
            inline 2 => struct {
                pub inline fn new(x_value: f32, y_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value } };
                }

                pub usingnamespace switch (accessor_style) {
                    inline .Position => struct {
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
                    else => {
                        unreachable;
                    }
                };
            },
            inline 3 => struct {
                pub inline fn new(x_value: f32, y_value: f32, z_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value, z_value } };
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
                        pub inline fn fromVector2(in_xy: Vector2, in_z: f32) Self {
                            return Self.new(in_xy.x(), in_xy.y(), in_z);
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
                    },
                };
            },
            inline 4 => struct {
                pub inline fn new(x_value: f32, y_value: f32, z_value: f32, w_value: f32) Self {
                    return Self{ .values = .{ x_value, y_value, z_value, w_value } };
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

            for (0..dimensions) |axis_index| {
                result.values[axis_index] *= scalar;
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
    };
}

pub const Rectangle2 = Rectangle(2);
pub const Rectangle3 = Rectangle(3);

fn Rectangle(comptime dimension_count: comptime_int) type {
    return struct {
        const VectorType = Vector(dimension_count, .Position);

        min: VectorType,
        max: VectorType,
        pub const dimensions = dimension_count;

        const Self = @This();

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

        pub fn addRadius(self: *const Self, radius: VectorType) Self {
            return Self{
                .min = self.min.minus(radius),
                .max = self.max.plus(radius),
            };
        }

        pub fn intersects(self: *const Self, b: *const Self) bool {
            return !(
                b.max.x() < self.min.x() or b.min.x() > self.max.x() or
                b.max.y() < self.min.y() or b.min.y() > self.max.y() or
                b.max.z() < self.min.z() or b.min.z() > self.max.z()
            );
        }
    };
}

pub fn square(a: f32) f32 {
    return a * a;
}

