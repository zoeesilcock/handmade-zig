pub const Vector2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn add(self: Vector2, b: Vector2) Vector2 {
        return Vector2{
            .x = self.x + b.x,
            .y = self.y + b.y,
        };
    }

    pub fn subtract(self: Vector2, b: Vector2) Vector2 {
        return Vector2{
            .x = self.x - b.x,
            .y = self.y - b.y,
        };
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
};

