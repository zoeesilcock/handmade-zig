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

    pub fn add(self: Vector2, b: Vector2) Vector2 {
        return Vector2{
            .x = self.x + b.x,
            .y = self.y + b.y,
        };
    }

    pub fn add_set(self: *Vector2, b: Vector2) *Vector2 {
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

    pub fn subtract_set(self: *Vector2, b: Vector2) *Vector2 {
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

    pub fn multiply_set(self: *Vector2, b: Vector2) *Vector2 {
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

    pub fn divide_set(self: *Vector2, b: Vector2) *Vector2 {
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

    pub fn scale_set(self: *Vector2, b: f32) *Vector2 {
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
};

pub fn square(a: f32) f32 {
    return a * a;
}

