pub const Vector2 = struct {
    // TODO: Casey uses a union here, but in Zig this requires an extra level. What would be the use case
    // for having an array accessor for this and is it worth extra typing on every single usage?
    //
    // pub const Vector2 = struct {
    //     map: extern struct {
    //         x: f32 = 0,
    //         y: f32 = 0,
    //     },
    //     arr: [2]f32,
    // ...
    // }
    //
    // Another alternative may be to use @Vector, but it appears that they have drawbacks also:
    // * https://github.com/ziglang/zig/issues/4961#issuecomment-610050227
    //
    // Other examples of vector implementation in Zig:
    // * https://github.com/ryupold/raylib.zig/blob/bd561b3689bc4e703f46bf1908633abb09680b4b/raylib.zig#L251
    // * https://github.com/godot-zig/godot-zig/blob/70e156b429610dcd2dfc0b5837e2feccdea0a0ad/src/api/Vector.zig#L91

    x: f32 = 0,
    y: f32 = 0,

    pub fn zero() Vector2 {
        return Vector2{};
    }

    pub fn add(self: Vector2, b: Vector2) Vector2 {
        return Vector2{
            .x = self.x + b.x,
            .y = self.y + b.y,
        };
    }

    pub fn addSet(self: *Vector2, b: Vector2) *Vector2 {
        self.x += b.x;
        self.y += b.y;
        return self;
    }

    pub fn subtract(self: Vector2, b: Vector2) Vector2 {
        return Vector2{
            .x = self.x - b.x,
            .y = self.y - b.y,
        };
    }

    pub fn subtractSet(self: *Vector2, b: Vector2) *Vector2 {
        self.x -= b.x;
        self.y -= b.y;
        return self;
    }

    pub fn multiply(self: Vector2, b: Vector2) Vector2 {
        return Vector2{
            .x = self.x * b.x,
            .y = self.y * b.y,
        };
    }

    pub fn multiplySet(self: *Vector2, b: Vector2) *Vector2 {
        self.x *= b.x;
        self.y *= b.y;
        return self;
    }

    pub fn divide(self: Vector2, b: Vector2) Vector2 {
        return Vector2{
            .x = self.x / b.x,
            .y = self.y / b.y,
        };
    }

    pub fn divideSet(self: *Vector2, b: Vector2) *Vector2 {
        self.x /= b.x;
        self.y /= b.y;
        return self;
    }

    pub fn negate(self: Vector2) Vector2 {
        return Vector2{
            .x = -self.x,
            .y = -self.y,
        };
    }

    pub fn scale(self: Vector2, b: f32) Vector2 {
        return Vector2{
            .x = b * self.x,
            .y = b * self.y
        };
    }

    pub fn scaleSet(self: *Vector2, b: f32) *Vector2 {
        self.x = b * self.x;
        self.y = b * self.y;
        return self;
    }

    pub fn dot(self: Vector2, b: Vector2) f32 {
        return (self.x * b.x) + (self.y * b.y);
    }

    pub fn lengthSquared(self: Vector2) f32 {
        return self.dot(self);
    }

    pub fn isInRectangle(self: Vector2, rectangle: Rectangle2) bool {
        const result = ((self.x >= rectangle.min.x) and
             (self.y >= rectangle.min.y) and
             (self.x < rectangle.max.x) and
             (self.y < rectangle.max.y));

        return result;
    }
};

pub const Rectangle2 = struct {
    min: Vector2 = Vector2{},
    max: Vector2 = Vector2{},

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
            .min = center.subtract(half_dimension),
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

