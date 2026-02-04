const math = @import("math");

pub const LANE_WIDTH = 8;

// Types.
const Vector3 = math.Vector3;
const Color3 = math.Color3;
pub const Lane_f32 = @Vector(LANE_WIDTH, f32);
pub const Lane_u32 = @Vector(LANE_WIDTH, u32);
pub const Lane_bool = @Vector(LANE_WIDTH, bool);

pub const Lane_Vector3 = extern struct {
    x: Lane_f32,
    y: Lane_f32,
    z: Lane_f32,

    pub fn new(in_x: Lane_f32, in_y: Lane_f32, in_z: Lane_f32) Lane_Vector3 {
        return .{
            .x = in_x,
            .y = in_y,
            .z = in_z,
        };
    }

    pub fn splat(in: Vector3) Lane_Vector3 {
        return .{
            .x = @splat(in.x()),
            .y = @splat(in.y()),
            .z = @splat(in.z()),
        };
    }

    pub fn plus(self: Lane_Vector3, b: Lane_Vector3) Lane_Vector3 {
        return .{
            .x = self.x + b.x,
            .y = self.y + b.y,
            .z = self.z + b.z,
        };
    }

    pub fn minus(self: Lane_Vector3, b: Lane_Vector3) Lane_Vector3 {
        return .{
            .x = self.x - b.x,
            .y = self.y - b.y,
            .z = self.z - b.z,
        };
    }

    pub fn scaledTo(self: Lane_Vector3, scalar: Lane_f32) Lane_Vector3 {
        var result = self;
        result.x *= scalar;
        result.y *= scalar;
        result.z *= scalar;
        return result;
    }

    pub fn negated(self: Lane_Vector3) Lane_Vector3 {
        const zero: Lane_f32 = @splat(0);
        var result = self;
        result.x = zero - self.x;
        result.y = zero - self.y;
        result.z = zero - self.z;
        return result;
    }

    pub fn select(self: Lane_Vector3, mask: Lane_bool, b: Lane_Vector3) Lane_Vector3 {
        return .{
            .x = @select(f32, mask, b.x, self.z),
            .y = @select(f32, mask, b.y, self.y),
            .z = @select(f32, mask, b.z, self.z),
        };
    }

    pub fn extract0(self: Lane_Vector3) Vector3 {
        return .new(
            self.x[0],
            self.y[0],
            self.z[0],
        );
    }

    pub fn dotProduct(self: Lane_Vector3, other: Lane_Vector3) Lane_f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn crossProduct(self: Lane_Vector3, b: Lane_Vector3) Lane_Vector3 {
        return .new(
            self.y * b.z - self.z * b.y,
            self.z * b.x - self.x * b.z,
            self.x * b.y - self.y * b.x,
        );
    }

    pub fn lengthSquared(self: *const Lane_Vector3) Lane_f32 {
        return self.dotProduct(self.*);
    }

    pub fn length(self: *const Lane_Vector3) f32 {
        return @sqrt(self.lengthSquared());
    }

    fn approxInvSquareRoot(input: Lane_f32) Lane_f32 {
        return @as(Lane_f32, @splat(1)) / @sqrt(input);
    }

    pub fn normalized(self: Lane_Vector3) Lane_Vector3 {
        const length_squared: Lane_f32 = self.lengthSquared();
        return self.scaledTo(approxInvSquareRoot(length_squared));
    }

    pub fn normalizeOrZero(self: Lane_Vector3) Lane_Vector3 {
        var result: Lane_Vector3 = self;

        const length_squared: Lane_f32 = self.lengthSquared();
        const normalized_value: Lane_Vector3 = self.scaledTo(approxInvSquareRoot(length_squared));
        const limit: Lane_f32 = @splat(0.0001);
        const mask: Lane_bool = (length_squared > (limit * limit));

        result = result.select(mask, normalized_value);

        return result;
    }

    pub fn lerp(min: Lane_Vector3, max: Lane_Vector3, time: Lane_f32) Lane_Vector3 {
        const one: Lane_f32 = @splat(1);
        return min.scaledTo(one - time).plus(max.scaledTo(time));
    }
};

pub const Lane_Color3 = extern struct {
    r: Lane_f32,
    g: Lane_f32,
    b: Lane_f32,

    pub fn new(in_r: Lane_f32, in_g: Lane_f32, in_b: Lane_f32) Lane_Color3 {
        return .{
            .r = in_r,
            .g = in_g,
            .b = in_b,
        };
    }

    pub fn splat(in: Color3) Lane_Color3 {
        return .{
            .r = @splat(in.r()),
            .g = @splat(in.g()),
            .b = @splat(in.b()),
        };
    }

    pub fn plus(self: Lane_Color3, b: Lane_Color3) Lane_Color3 {
        return .{
            .r = self.r + b.r,
            .g = self.g + b.g,
            .b = self.b + b.b,
        };
    }

    pub fn scaledTo(self: Lane_Color3, scalar: Lane_f32) Lane_Color3 {
        var result = self;
        result.r *= scalar;
        result.g *= scalar;
        result.b *= scalar;
        return result;
    }

    pub fn hadamardProduct(self: *const Lane_Color3, b: Lane_Color3) Lane_Color3 {
        return Lane_Color3{
            .r = self.r * b.r,
            .g = self.g * b.g,
            .b = self.b * b.b,
        };
    }
};

fn gather(base_ptr: *anyopaque, stride: u32, indices: Lane_u32) Lane_f32 {
    var result: Lane_f32 = @splat(0);

    inline for (0..LANE_WIDTH) |i| {
        const offset = indices[i] * stride;
        const ptr: [*]u8 = @ptrCast(base_ptr);
        const value_ptr: *f32 = @ptrCast(@alignCast(&ptr[offset]));
        result[i] = value_ptr.*;
    }

    return result;
}

pub fn gatherF32(T: type, base: [*]T, indices: Lane_u32, comptime member: []const u8) Lane_f32 {
    const base_ptr = &@field(base[0], member);
    const stride: u32 = @sizeOf(@TypeOf(base[0]));

    return gather(base_ptr, stride, indices);
}

pub fn gatherColor3(T: type, base: [*]T, indices: Lane_u32, comptime member: []const u8) Lane_Color3 {
    const base_ptr: [*]f32 = @ptrCast(&@field(base[0], member));
    const stride: u32 = @sizeOf(@TypeOf(base[0]));

    var result: Lane_Color3 = .splat(.zero());

    result.r = gather(base_ptr + 0, stride, indices);
    result.g = gather(base_ptr + 1, stride, indices);
    result.b = gather(base_ptr + 2, stride, indices);

    return result;
}

pub fn andBoolWithColor3(a_in: Lane_bool, color: Lane_Color3) Lane_Color3 {
    const a: Lane_u32 = @select(u32, a_in, @as(Lane_u32, @splat(0xFFFFFFFF)), @as(Lane_u32, @splat(0)));
    const r: Lane_u32 = a & @as(*Lane_u32, @ptrCast(@constCast(&color.r))).*;
    const g: Lane_u32 = a & @as(*Lane_u32, @ptrCast(@constCast(&color.g))).*;
    const b: Lane_u32 = a & @as(*Lane_u32, @ptrCast(@constCast(&color.b))).*;

    return .new(
        @as(*Lane_f32, @ptrCast(@constCast(&r))).*,
        @as(*Lane_f32, @ptrCast(@constCast(&g))).*,
        @as(*Lane_f32, @ptrCast(@constCast(&b))).*,
    );
}

pub fn conditionalAssign(T: type, dest: *T, mask: Lane_bool, source: T) void {
    switch (T) {
        Lane_bool => {
            const full_mask = @select(bool, mask, @as(Lane_bool, @splat(0xFFFFFFFF)), @as(Lane_bool, @splat(0)));
            dest.* = ((~full_mask & dest.*) | (full_mask & source));
        },
        Lane_u32 => {
            const full_mask = @select(u32, mask, @as(Lane_u32, @splat(0xFFFFFFFF)), @as(Lane_u32, @splat(0)));
            dest.* = ((~full_mask & dest.*) | (full_mask & source));
        },
        Lane_f32 => {
            conditionalAssign(Lane_u32, @ptrCast(dest), mask, @as(*const Lane_u32, @ptrCast(@constCast(&source))).*);
        },
        Lane_Vector3 => {
            conditionalAssign(Lane_u32, @ptrCast(&dest.x), mask, @as(*const Lane_u32, @ptrCast(&source.x)).*);
            conditionalAssign(Lane_u32, @ptrCast(&dest.y), mask, @as(*const Lane_u32, @ptrCast(&source.y)).*);
            conditionalAssign(Lane_u32, @ptrCast(&dest.z), mask, @as(*const Lane_u32, @ptrCast(&source.z)).*);
        },
        Lane_Color3 => {
            conditionalAssign(Lane_u32, @ptrCast(&dest.r), mask, @as(*const Lane_u32, @ptrCast(&source.r)).*);
            conditionalAssign(Lane_u32, @ptrCast(&dest.g), mask, @as(*const Lane_u32, @ptrCast(&source.g)).*);
            conditionalAssign(Lane_u32, @ptrCast(&dest.b), mask, @as(*const Lane_u32, @ptrCast(&source.b)).*);
        },
        else => {},
    }
}

pub fn maskIsZeroed(lane_mask: Lane_bool) bool {
    return !@reduce(.Or, lane_mask);
}

pub fn horizontalAddU64(a: Lane_u32) u64 {
    var result: u64 = 0;
    inline for (0..LANE_WIDTH) |i| {
        result += a[i];
    }
    return result;
}

pub fn horizontalAddF32(a: Lane_f32) f32 {
    var result: f32 = 0;
    inline for (0..LANE_WIDTH) |i| {
        result += a[i];
    }
    return result;
}

pub fn horizontalAddColor3(a: Lane_Color3) Color3 {
    return .new(
        horizontalAddF32(a.r),
        horizontalAddF32(a.g),
        horizontalAddF32(a.b),
    );
}
