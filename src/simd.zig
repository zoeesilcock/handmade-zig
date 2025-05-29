const math = @import("math.zig");

const Vector3 = math.Vector3;

pub const Vec4f = @Vector(4, f32);
pub const Vec4u = @Vector(4, u32);
pub const Vec4i = @Vector(4, i32);

pub const V3_4x = extern struct {
    x: Vec4f,
    y: Vec4f,
    z: Vec4f,

    pub fn fromVector3(in: Vector3) V3_4x {
        return .{
            .x = @splat(in.x()),
            .y = @splat(in.y()),
            .z = @splat(in.z()),
        };
    }

    pub fn plus(self: V3_4x, other: V3_4x) V3_4x {
        var result = self;
        result.x += other.x;
        result.y += other.y;
        result.z += other.z;
        return result;
    }

    pub fn scaledTo(self: V3_4x, scalar: f32) V3_4x {
        var result = self;
        result.x *= @splat(scalar);
        result.y *= @splat(scalar);
        result.z *= @splat(scalar);
        return result;
    }
};

pub const V4_4x = extern struct {
    r: Vec4f,
    g: Vec4f,
    b: Vec4f,
    a: Vec4f,

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

pub fn mmSetExpr(comptime method: anytype, args: anytype) Vec4f {
    return [_]f32{
        @call(.auto, method, args),
        @call(.auto, method, args),
        @call(.auto, method, args),
        @call(.auto, method, args),
    };
}
