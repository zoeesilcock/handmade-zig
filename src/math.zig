const intrinsics = @import("intrinsics.zig");
const shared = @import("shared.zig");
const std = @import("std");

pub const PI32: f32 = 3.14159265359;
pub const TAU32: f32 = 6.28318530717958647692;
pub const SLOW = shared.SLOW;

pub const Vector2 = Vector2Type(f32);
pub const Vector2i = Vector2Type(i32);
pub const Vector3 = Vector3Type(f32);
pub const Vector4 = Vector4Type(f32);
pub const Color3 = Color3Type(f32);
pub const Color = Color4Type(f32);

pub const Rectangle2 = Rectangle2Type(f32);
pub const Rectangle2i = Rectangle2Type(i32);
pub const Rectangle3 = Rectangle3Type(f32);

pub const Matrix2x2 = MatrixType(2, 2);
pub const Matrix3x3 = MatrixType(3, 3);
pub const Matrix4x4 = MatrixType(4, 4);
pub const MatrixInverse4x4 = MatrixInverseType(Matrix4x4);

fn Vector2Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(2, ScalarType),

        pub fn new(x_value: ScalarType, y_value: ScalarType) Self {
            return Self{ .values = .{ x_value, y_value } };
        }

        pub fn newI(x_value: i32, y_value: i32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
            } };
        }

        pub fn newU(x_value: u32, y_value: u32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
            } };
        }

        pub fn perp(self: *const Self) Self {
            return Self{ .values = .{ -self.values[1], self.values[0] } };
        }

        pub fn x(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub fn y(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub fn setX(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub fn setY(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub fn toVector3(self: Self, in_z: ScalarType) Vector3 {
            return Vector3.new(self.x(), self.y(), in_z);
        }

        pub fn isInRectangle(self: *const Self, rectangle: Rectangle2) bool {
            const result = ((self.x() >= rectangle.min.x()) and
                (self.y() >= rectangle.min.y()) and
                (self.x() < rectangle.max.x()) and
                (self.y() < rectangle.max.y()));

            return result;
        }

        pub fn arm2(angle: f32) Self {
            return Self.new(intrinsics.cos(angle), intrinsics.sin(angle));
        }

        pub fn rayIntersection(pa: Self, ra: Self, pb: Self, rb: Self) Self {
            var result: Self = .zero();

            // Equation:
            // Pa.x + ta * ra.x = Pb.x + tb * rb.x
            // Pa.y + ta * ra.y = Pb.y + tb * rb.y

            const d: f32 = (rb.x() * ra.y() - rb.y() * ra.x());
            if (d != 0) {
                const ta: f32 = ((pa.x() - pb.x()) * rb.y() + (pb.y() - pa.y()) * rb.x()) / d;
                const tb: f32 = ((pa.x() - pb.x()) * ra.y() + (pb.y() - pa.y()) * ra.x()) / d;

                result = .new(ta, tb);
            }

            return result;
        }

        const Shared = VectorShared(2, ScalarType, Self);
        pub const zero = Shared.zero;
        pub const one = Shared.one;
        pub const splat = Shared.splat;
        pub const plus = Shared.plus;
        pub const minus = Shared.minus;
        pub const times = Shared.times;
        pub const dividedBy = Shared.dividedBy;
        pub const dividedByF = Shared.dividedByF;
        pub const scaledTo = Shared.scaledTo;
        pub const clamp01 = Shared.clamp01;
        pub const negated = Shared.negated;
        pub const dotProduct = Shared.dotProduct;
        pub const hadamardProduct = Shared.hadamardProduct;
        pub const lengthSquared = Shared.lengthSquared;
        pub const length = Shared.length;
        pub const invalidPosition = Shared.invalidPosition;
        pub const lerp = Shared.lerp;
        pub const normalized = Shared.normalized;
        pub const normalizeOrZero = Shared.normalizeOrZero;
        pub const min = Shared.min;
        pub const max = Shared.max;
        pub const toGL = Shared.toGL;
    };
}

fn Vector3Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(3, ScalarType),

        pub fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType) Self {
            return Self{ .values = .{ x_value, y_value, z_value } };
        }

        pub fn newI(x_value: i32, y_value: i32, z_value: i32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
            } };
        }

        pub fn newU(x_value: u32, y_value: u32, z_value: u32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
            } };
        }

        pub fn x(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub fn y(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub fn z(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub fn xy(self: *const Self) Vector2 {
            return Vector2.new(self.x(), self.y());
        }

        pub fn yz(self: *const Self) Vector2 {
            return Vector2.new(self.y(), self.z());
        }

        pub fn setX(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub fn setY(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub fn setZ(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub fn setXY(self: *Self, value: Vector2) *Self {
            self.values[0] = value.values[0];
            self.values[1] = value.values[1];
            return self;
        }

        pub fn setYZ(self: *Self, value: Vector2) *Self {
            self.values[1] = value.values[0];
            self.values[2] = value.values[1];
            return self;
        }

        pub fn toVector4(vector3: Vector3, in_w: ScalarType) Vector4 {
            return Vector4.new(vector3.values[0], vector3.values[1], vector3.values[2], in_w);
        }

        pub fn toColor3(self: Self) Color3 {
            return Color3.new(self.x(), self.y(), self.z());
        }

        pub fn isInRectangle(self: *const Self, rectangle: Rectangle3) bool {
            const result = ((self.x() >= rectangle.min.x()) and
                (self.y() >= rectangle.min.y()) and
                (self.z() >= rectangle.min.z()) and
                (self.x() < rectangle.max.x()) and
                (self.y() < rectangle.max.y()) and
                (self.z() < rectangle.max.z()));

            return result;
        }

        pub fn crossProduct(self: Self, b: Self) Self {
            return .new(
                self.y() * b.z() - self.z() * b.y(),
                self.z() * b.x() - self.x() * b.z(),
                self.x() * b.y() - self.y() * b.x(),
            );
        }

        pub fn rayIntersectsBox(ray_origin: Self, ray_direction: Self, box_position: Self, box_radius: Self) f32 {
            const box_min: Vector3 = box_position.minus(box_radius);
            const box_max: Vector3 = box_position.plus(box_radius);

            const inverse_ray_direction: Vector3 = ray_direction.divideFByMe(1);
            const t_box_min: Vector3 = box_min.minus(ray_origin).hadamardProduct(inverse_ray_direction);
            const t_box_max: Vector3 = box_max.minus(ray_origin).hadamardProduct(inverse_ray_direction);

            const t_min3: Vector3 = t_box_min.min(t_box_max);
            const t_max3: Vector3 = t_box_min.max(t_box_max);

            const t_min: f32 = @max(t_min3.x(), @max(t_min3.y(), t_min3.z()));
            const t_max: f32 = @min(t_max3.x(), @min(t_max3.y(), t_max3.z()));

            var result: f32 = std.math.floatMax(f32);
            if ((t_min > 0) and (t_min < t_max)) {
                result = t_min;
            }

            return result;
        }

        const Shared = VectorShared(3, ScalarType, Self);
        pub const zero = Shared.zero;
        pub const one = Shared.one;
        pub const splat = Shared.splat;
        pub const plus = Shared.plus;
        pub const minus = Shared.minus;
        pub const times = Shared.times;
        pub const dividedBy = Shared.dividedBy;
        pub const dividedByF = Shared.dividedByF;
        pub const divideFByMe = Shared.divideFByMe;
        pub const scaledTo = Shared.scaledTo;
        pub const clamp01 = Shared.clamp01;
        pub const negated = Shared.negated;
        pub const dotProduct = Shared.dotProduct;
        pub const hadamardProduct = Shared.hadamardProduct;
        pub const lengthSquared = Shared.lengthSquared;
        pub const length = Shared.length;
        pub const invalidPosition = Shared.invalidPosition;
        pub const lerp = Shared.lerp;
        pub const normalized = Shared.normalized;
        pub const normalizeOrZero = Shared.normalizeOrZero;
        pub const min = Shared.min;
        pub const max = Shared.max;
        pub const toGL = Shared.toGL;
    };
}

pub fn isInRectangleCenterHalfDim(position: Vector3, radius: Vector3, test_point: Vector3) bool {
    const relative: Vector3 = test_point.minus(position);
    const result = ((@abs(relative.x()) <= radius.x()) and
        (@abs(relative.y()) <= radius.y()) and
        (@abs(relative.z()) <= radius.z()));

    return result;
}

fn Vector4Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(4, ScalarType),

        pub fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType, w_value: ScalarType) Self {
            return Self{ .values = .{ x_value, y_value, z_value, w_value } };
        }

        pub fn newI(x_value: i32, y_value: i32, z_value: i32, w_value: i32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
                @floatFromInt(w_value),
            } };
        }

        pub fn newU(x_value: u32, y_value: u32, z_value: u32, w_value: u32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
                @floatFromInt(w_value),
            } };
        }

        pub fn x(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub fn y(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub fn z(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub fn w(self: *const Self) ScalarType {
            return self.values[3];
        }

        pub fn xy(self: *const Self) Vector2 {
            return Vector2.new(self.x(), self.y());
        }

        pub fn yz(self: *const Self) Vector2 {
            return Vector2.new(self.y(), self.z());
        }

        pub fn xyz(self: *const Self) Vector3 {
            return Vector3.new(self.x(), self.y(), self.z());
        }

        pub fn setX(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub fn setY(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub fn setZ(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub fn setW(self: *Self, value: ScalarType) *Self {
            self.values[3] = value;
            return self;
        }

        pub fn setXYZ(self: *Self, value: Vector3) *Self {
            self.values[0] = value.values[0];
            self.values[1] = value.values[1];
            self.values[2] = value.values[2];
            return self;
        }

        pub fn setXY(self: *Self, value: Vector2) *Self {
            self.values[0] = value.values[0];
            self.values[1] = value.values[1];
            return self;
        }

        pub fn toColor(self: Self) Color {
            return Color.new(self.x(), self.y(), self.z(), self.w());
        }

        const Shared = VectorShared(4, ScalarType, Self);
        pub const zero = Shared.zero;
        pub const one = Shared.one;
        pub const splat = Shared.splat;
        pub const plus = Shared.plus;
        pub const minus = Shared.minus;
        pub const times = Shared.times;
        pub const dividedBy = Shared.dividedBy;
        pub const dividedByF = Shared.dividedByF;
        pub const scaledTo = Shared.scaledTo;
        pub const clamp01 = Shared.clamp01;
        pub const negated = Shared.negated;
        pub const dotProduct = Shared.dotProduct;
        pub const hadamardProduct = Shared.hadamardProduct;
        pub const lengthSquared = Shared.lengthSquared;
        pub const length = Shared.length;
        pub const invalidPosition = Shared.invalidPosition;
        pub const lerp = Shared.lerp;
        pub const normalized = Shared.normalized;
        pub const normalizeOrZero = Shared.normalizeOrZero;
        pub const min = Shared.min;
        pub const max = Shared.max;
        pub const packColorBGRA255 = Shared.packColorBGRA255;
        pub const packColorBGRA = Shared.packColorBGRA;
        pub const unpackColorBGRA = Shared.unpackColorBGRA;
        pub const packColorRGBA = Shared.packColorRGBA;
        pub const unpackColorRGBA = Shared.unpackColorRGBA;
        pub const toGL = Shared.toGL;
    };
}

fn Color3Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(3, ScalarType),

        pub fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType) Self {
            return Self{ .values = .{ x_value, y_value, z_value } };
        }

        pub fn newI(x_value: i32, y_value: i32, z_value: i32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
            } };
        }

        pub fn newU(x_value: u32, y_value: u32, z_value: u32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
            } };
        }

        pub fn r(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub fn g(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub fn b(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub fn setR(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub fn setG(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub fn setB(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub fn toColor(self: Self, in_a: ScalarType) Color {
            return Color.new(self.r(), self.g(), self.b(), in_a);
        }

        pub fn toVector3(self: Self) Vector3 {
            return Vector3.new(self.r(), self.g(), self.b());
        }

        const Shared = VectorShared(3, ScalarType, Self);
        pub const zero = Shared.zero;
        pub const one = Shared.one;
        pub const white = Shared.white;
        pub const black = Shared.black;
        pub const splat = Shared.splat;
        pub const plus = Shared.plus;
        pub const minus = Shared.minus;
        pub const times = Shared.times;
        pub const dividedBy = Shared.dividedBy;
        pub const dividedByF = Shared.dividedByF;
        pub const scaledTo = Shared.scaledTo;
        pub const clamp01 = Shared.clamp01;
        pub const negated = Shared.negated;
        pub const dotProduct = Shared.dotProduct;
        pub const hadamardProduct = Shared.hadamardProduct;
        pub const lengthSquared = Shared.lengthSquared;
        pub const length = Shared.length;
        pub const invalidPosition = Shared.invalidPosition;
        pub const lerp = Shared.lerp;
        pub const normalized = Shared.normalized;
        pub const normalizeOrZero = Shared.normalizeOrZero;
        pub const min = Shared.min;
        pub const max = Shared.max;
        pub const toGL = Shared.toGL;
    };
}

fn Color4Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(4, ScalarType),

        pub fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType, w_value: ScalarType) Self {
            return Self{ .values = .{ x_value, y_value, z_value, w_value } };
        }

        pub fn newI(x_value: i32, y_value: i32, z_value: i32, w_value: i32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
                @floatFromInt(w_value),
            } };
        }

        pub fn newU(x_value: u32, y_value: u32, z_value: u32, w_value: u32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
                @floatFromInt(w_value),
            } };
        }

        pub inline fn newFromSRGB(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType, w_value: ScalarType) Self {
            return Self.new(
                square(x_value),
                square(y_value),
                square(z_value),
                w_value,
            );
        }

        pub fn r(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub fn g(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub fn b(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub fn a(self: *const Self) ScalarType {
            return self.values[3];
        }

        pub fn rgb(self: *const Self) Color3 {
            return Color3.new(self.r(), self.g(), self.b());
        }

        pub fn setR(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub fn setG(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub fn setB(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub fn setA(self: *Self, value: ScalarType) *Self {
            self.values[3] = value;
            return self;
        }

        pub fn setRGB(self: *Self, value: Color3) *Self {
            self.values[0] = value.values[0];
            self.values[1] = value.values[1];
            self.values[2] = value.values[2];
            return self;
        }

        pub fn toVector4(self: Self) Vector4 {
            return Vector4.new(self.r(), self.g(), self.b(), self.a());
        }

        const Shared = VectorShared(4, ScalarType, Self);
        pub const zero = Shared.zero;
        pub const one = Shared.one;
        pub const white = Shared.white;
        pub const black = Shared.black;
        pub const splat = Shared.splat;
        pub const plus = Shared.plus;
        pub const minus = Shared.minus;
        pub const times = Shared.times;
        pub const dividedBy = Shared.dividedBy;
        pub const dividedByF = Shared.dividedByF;
        pub const scaledTo = Shared.scaledTo;
        pub const clamp01 = Shared.clamp01;
        pub const negated = Shared.negated;
        pub const dotProduct = Shared.dotProduct;
        pub const hadamardProduct = Shared.hadamardProduct;
        pub const lengthSquared = Shared.lengthSquared;
        pub const length = Shared.length;
        pub const invalidPosition = Shared.invalidPosition;
        pub const lerp = Shared.lerp;
        pub const normalized = Shared.normalized;
        pub const min = Shared.min;
        pub const max = Shared.max;
        pub const normalizeOrZero = Shared.normalizeOrZero;
        pub const packColorBGRA255 = Shared.packColorBGRA255;
        pub const packColorBGRA = Shared.packColorBGRA;
        pub const unpackColorBGRA = Shared.unpackColorBGRA;
        pub const packColorRGBA = Shared.packColorRGBA;
        pub const unpackColorRGBA = Shared.unpackColorRGBA;
        pub const toGL = Shared.toGL;
    };
}

fn VectorShared(comptime dimension_count: comptime_int, comptime ScalarType: type, comptime Self: type) type {
    return struct {
        pub fn zero() Self {
            return Self{ .values = @splat(0) };
        }

        pub fn one() Self {
            return Self{ .values = @splat(1) };
        }

        pub fn white() Self {
            return Self.one();
        }

        pub fn black() Self {
            var result: Self = .{ .values = @splat(0) };
            if (dimension_count == 4) {
                result.values[3] = 1;
            }
            return result;
        }

        pub fn splat(value: ScalarType) Self {
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

        pub fn dividedByF(self: *const Self, scalar: ScalarType) Self {
            return self.scaledTo(1 / scalar);
        }

        pub fn divideFByMe(self: Self, divisor: f32) Self {
            return Self.splat(divisor).dividedBy(self);
        }

        pub fn scaledTo(self: *const Self, scalar: ScalarType) Self {
            return Self{ .values = self.values * @as(@TypeOf(self.values), @splat(scalar)) };
        }

        pub fn clamp01(self: *const Self) Self {
            var result = Self.zero();

            for (0..dimension_count) |axis_index| {
                result.values[axis_index] = clampf01(self.values[axis_index]);
            }

            return result;
        }

        pub fn negated(self: *const Self) Self {
            return Self{ .values = -self.values };
        }

        pub fn dotProduct(self: *const Self, b: Self) ScalarType {
            return @reduce(.Add, self.values * b.values);
        }

        pub fn hadamardProduct(self: *const Self, b: Self) Self {
            return Self{ .values = self.values * b.values };
        }

        pub fn lengthSquared(self: *const Self) ScalarType {
            return self.dotProduct(self.*);
        }

        pub fn length(self: *const Self) ScalarType {
            return @sqrt(self.lengthSquared());
        }

        pub fn invalidPosition() Self {
            return Self{ .values = @splat(100000) };
        }

        pub fn lerp(from: Self, to: Self, time: ScalarType) Self {
            return Self{ .values = from.values + @as(@TypeOf(from.values), @splat(time)) * (to.values - from.values) };
        }

        pub fn normalized(self: Self) Self {
            return self.scaledTo(1.0 / self.length());
        }

        pub fn normalizeOrZero(self: Self) Self {
            var result: Self = Self.zero();
            const length_squared: f32 = self.lengthSquared();
            if (length_squared > square(0.0001)) {
                result = self.scaledTo(1 / @sqrt(length_squared));
            }
            return result;
        }

        pub fn min(self: Self, b: Self) Self {
            var result = Self.zero();

            for (0..dimension_count) |axis_index| {
                result.values[axis_index] = @min(self.values[axis_index], b.values[axis_index]);
            }

            return result;
        }

        pub fn max(self: Self, b: Self) Self {
            var result = Self.zero();

            for (0..dimension_count) |axis_index| {
                result.values[axis_index] = @max(self.values[axis_index], b.values[axis_index]);
            }

            return result;
        }

        pub inline fn packColorBGRA255(self: Self) u32 {
            return ((intrinsics.roundReal32ToUInt32(self.a() * 255.0) << 24) |
                (intrinsics.roundReal32ToUInt32(self.r() * 255.0) << 16) |
                (intrinsics.roundReal32ToUInt32(self.g() * 255.0) << 8) |
                (intrinsics.roundReal32ToUInt32(self.b() * 255.0) << 0));
        }

        pub inline fn packColorBGRA(self: Self) u32 {
            return ((intrinsics.roundReal32ToUInt32(self.a()) << 24) |
                (intrinsics.roundReal32ToUInt32(self.r()) << 16) |
                (intrinsics.roundReal32ToUInt32(self.g()) << 8) |
                (intrinsics.roundReal32ToUInt32(self.b()) << 0));
        }

        pub inline fn unpackColorBGRA(value: u32) Self {
            return Self.newU(
                (value >> 16) & 0xFF,
                (value >> 8) & 0xFF,
                (value >> 0) & 0xFF,
                (value >> 24) & 0xFF,
            );
        }

        pub fn packColorRGBA(self: Self) u32 {
            return ((intrinsics.roundReal32ToUInt32(self.a()) << 24) |
                (intrinsics.roundReal32ToUInt32(self.b()) << 16) |
                (intrinsics.roundReal32ToUInt32(self.g()) << 8) |
                (intrinsics.roundReal32ToUInt32(self.r()) << 0));
        }

        pub inline fn unpackColorRGBA(value: u32) Self {
            return Self.newU(
                (value >> 0) & 0xFF,
                (value >> 8) & 0xFF,
                (value >> 16) & 0xFF,
                (value >> 24) & 0xFF,
            );
        }

        pub inline fn toGL(self: Self) *const f32 {
            return @ptrCast(&self.values);
        }
    };
}

fn Rectangle2Type(comptime ScalarType: type) type {
    return extern struct {
        const VectorType = Vector2Type(ScalarType);
        const Self = @This();

        min: VectorType,
        max: VectorType,

        pub fn new(min_x: ScalarType, min_y: ScalarType, max_x: ScalarType, max_y: ScalarType) Self {
            return Self{
                .min = VectorType.new(min_x, min_y),
                .max = VectorType.new(max_x, max_y),
            };
        }

        pub fn toRectangle3(self: Self, min_z: ScalarType, max_z: ScalarType) Rectangle3 {
            return Rectangle3{
                .min = self.min.toVector3(min_z),
                .max = self.max.toVector3(max_z),
            };
        }

        pub fn getIntersectionWith(self: *const Self, b: Self) Self {
            return Self{
                .min = VectorType.new(
                    @max(self.min.x(), b.min.x()),
                    @max(self.min.y(), b.min.y()),
                ),
                .max = VectorType.new(
                    @min(self.max.x(), b.max.x()),
                    @min(self.max.y(), b.max.y()),
                ),
            };
        }

        pub fn getUnionWith(self: *const Self, b: *Self) Self {
            return Self{
                .min = VectorType.new(
                    @min(self.min.x(), b.min.x()),
                    @min(self.min.y(), b.min.y()),
                ),
                .max = VectorType.new(
                    @max(self.max.x(), b.max.x()),
                    @max(self.max.y(), b.max.y()),
                ),
            };
        }

        pub fn getClampedArea(self: *const Self) ScalarType {
            const width = (self.max.x() - self.min.x());
            const height = (self.max.y() - self.min.y());
            var result: ScalarType = 0;

            if (width > 0 and height > 0) {
                result = width * height;
            }

            return result;
        }

        const Shared = RectangleShared(2, VectorType, ScalarType, Self);
        pub const invertedInfinity = if (ScalarType == f32) Shared.invertedInfinityFloat else Shared.invertedInfinityInt;
        pub const zero = Shared.zero;
        pub const fromMinMax = Shared.fromMinMax;
        pub const fromMinDimension = Shared.fromMinDimension;
        pub const fromCenterHalfDimension = Shared.fromCenterHalfDimension;
        pub const fromCenterDimension = Shared.fromCenterDimension;
        pub const getMinCorner = Shared.getMinCorner;
        pub const getMaxCorner = Shared.getMaxCorner;
        pub const getCenter = Shared.getCenter;
        pub const getDimension = Shared.getDimension;
        pub const getRadius = Shared.getRadius;
        pub const getWidth = Shared.getWidth;
        pub const getHeight = Shared.getHeight;
        pub const getBarycentricPosition = Shared.getBarycentricPosition;
        pub const addRadius = Shared.addRadius;
        pub const offsetBy = Shared.offsetBy;
        pub const intersects = Shared.intersects;
        pub const getArea = Shared.getArea;
        pub const hasArea = Shared.hasArea;
    };
}

fn Rectangle3Type(comptime ScalarType: type) type {
    return extern struct {
        const VectorType = Vector3Type(ScalarType);
        const Self = @This();

        min: VectorType,
        max: VectorType,

        pub fn new(
            min_x: ScalarType,
            min_y: ScalarType,
            min_z: ScalarType,
            max_x: ScalarType,
            max_y: ScalarType,
            max_z: ScalarType,
        ) Self {
            return Self{
                .min = VectorType.new(min_x, min_y, min_z),
                .max = VectorType.new(max_x, max_y, max_z),
            };
        }
        pub fn toRectangle2(self: Self) Rectangle2 {
            return Rectangle2{
                .min = self.min.xy(),
                .max = self.max.xy(),
            };
        }

        pub fn getUnionWith(self: *const Self, b: *Self) Self {
            return Self{
                .min = VectorType.new(
                    @min(self.min.x(), b.min.x()),
                    @min(self.min.y(), b.min.y()),
                    @min(self.min.z(), b.min.z()),
                ),
                .max = VectorType.new(
                    @max(self.max.x(), b.max.x()),
                    @max(self.max.y(), b.max.y()),
                    @max(self.max.z(), b.max.z()),
                ),
            };
        }

        const Shared = RectangleShared(3, VectorType, ScalarType, Self);
        pub const invertedInfinity = if (ScalarType == f32) Shared.invertedInfinityFloat else Shared.invertedInfinityInt;
        pub const zero = Shared.zero;
        pub const fromMinMax = Shared.fromMinMax;
        pub const fromMinDimension = Shared.fromMinDimension;
        pub const fromCenterHalfDimension = Shared.fromCenterHalfDimension;
        pub const fromCenterDimension = Shared.fromCenterDimension;
        pub const getMinCorner = Shared.getMinCorner;
        pub const getMaxCorner = Shared.getMaxCorner;
        pub const getCenter = Shared.getCenter;
        pub const getDimension = Shared.getDimension;
        pub const getRadius = Shared.getRadius;
        pub const getWidth = Shared.getWidth;
        pub const getHeight = Shared.getHeight;
        pub const getBarycentricPosition = Shared.getBarycentricPosition;
        pub const addRadius = Shared.addRadius;
        pub const offsetBy = Shared.offsetBy;
        pub const intersects = Shared.intersects;
        pub const getArea = Shared.getArea;
        pub const hasArea = Shared.hasArea;
    };
}

fn RectangleShared(
    comptime dimension_count: comptime_int,
    comptime VectorType: type,
    comptime ScalarType: type,
    comptime Self: type,
) type {
    return struct {
        pub fn invertedInfinityInt() Self {
            const scalar_max = std.math.maxInt(ScalarType);
            return Self.fromMinMax(.splat(scalar_max), .splat(-scalar_max));
        }

        pub fn invertedInfinityFloat() Self {
            const scalar_max = std.math.floatMax(ScalarType);
            return Self.fromMinMax(.splat(scalar_max), .splat(-scalar_max));
        }

        pub fn zero() Self {
            return Self{
                .min = VectorType.splat(0),
                .max = VectorType.splat(0),
            };
        }

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
            return self.min.plus(self.max).scaledTo(0.5);
        }

        pub fn getDimension(self: *const Self) VectorType {
            return self.max.minus(self.min);
        }

        pub fn getRadius(self: *const Self) VectorType {
            return self.getDimension().scaledTo(0.5);
        }

        pub fn getWidth(self: *const Self) ScalarType {
            return self.max.x() - self.min.x();
        }

        pub fn getHeight(self: *const Self) ScalarType {
            return self.max.y() - self.min.y();
        }

        pub fn getBarycentricPosition(self: *const Self, position: VectorType) VectorType {
            var result = VectorType.zero();

            for (0..dimension_count) |axis_index| {
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

        pub fn offsetBy(self: *const Self, offset: VectorType) Self {
            return Self{
                .min = self.min.plus(offset),
                .max = self.max.plus(offset),
            };
        }

        pub fn intersects(self: *const Self, b: *const Self) bool {
            var result = true;

            for (0..dimension_count) |axis_index| {
                if ((b.max.values[axis_index] <= self.min.values[axis_index]) or
                    (b.min.values[axis_index] >= self.max.values[axis_index]))
                {
                    result = false;
                    break;
                }
            }

            return result;
        }

        pub fn getArea(self: *const Self) ScalarType {
            const dimension: VectorType = self.getDimension();
            return dimension.x() * dimension.y();
        }

        pub fn hasArea(self: *const Self) bool {
            return (self.min.x() < self.max.x() and self.min.y() < self.max.y());
        }
    };
}

fn MatrixInverseType(comptime InnerType: type) type {
    return extern struct {
        const Self = @This();

        forward: InnerType = .{},
        inverse: InnerType = .{},

        pub fn identity() Self {
            return .{
                .forward = .identity(),
                .inverse = .identity(),
            };
        }

        pub fn cameraTransform(x: Vector3, y: Vector3, z: Vector3, p: Vector3) Self {
            var result: Self = .{};

            var a: Matrix4x4 = .rows3x3(x, y, z);
            const ap: Vector3 = a.timesV(p).negated();
            a = a.translate(ap);
            result.forward = a;

            const ix: Vector3 = x.dividedByF(x.lengthSquared());
            const iy: Vector3 = y.dividedByF(y.lengthSquared());
            const iz: Vector3 = z.dividedByF(z.lengthSquared());
            const ip: Vector3 = .new(
                ap.x() * ix.x() + ap.y() * iy.x() + ap.z() * iz.x(),
                ap.x() * ix.y() + ap.y() * iy.y() + ap.z() * iz.y(),
                ap.x() * ix.z() + ap.y() * iy.z() + ap.z() * iz.z(),
            );

            var b: Matrix4x4 = .columns3x3(ix, iy, iz);
            b = b.translate(ip.negated());
            result.inverse = b;

            if (SLOW) {
                const ident: Matrix4x4 = result.inverse.times(result.forward);
                _ = ident;
            }

            return result;
        }

        pub fn perspectiveProjection(
            aspect_width_over_height: f32,
            focal_length: f32,
            near_clip_plane: f32,
            far_clip_plane: f32,
        ) Self {
            const a: f32 = 1;
            const b: f32 = aspect_width_over_height;
            const c: f32 = focal_length;

            const n: f32 = near_clip_plane; // Near clip plane distance.
            const f: f32 = far_clip_plane; // Far clip plane distance.

            // These are perspective corrected terms, for when you divide by -z.
            const d: f32 = (n + f) / (n - f);
            const e: f32 = (2 * f * n) / (n - f);

            const result: Self = .{
                .forward = .{
                    .values = .{
                        .new(a * c, 0, 0, 0),
                        .new(0, b * c, 0, 0),
                        .new(0, 0, d, e),
                        .new(0, 0, -1, 0),
                    },
                },
                .inverse = .{
                    .values = .{
                        .new(1 / a * c, 0, 0, 0),
                        .new(0, 1 / b * c, 0, 0),
                        .new(0, 0, 0, -1),
                        .new(0, 0, 1 / e, d / e),
                    },
                },
            };

            if (SLOW) {
                const ident: Matrix4x4 = result.inverse.times(result.forward);
                _ = ident;

                var test0: Vector4 = result.forward.timesV4(.new(0, 0, -n, 1));
                var test1: Vector4 = result.forward.timesV4(.new(0, 0, -f, 1));
                _ = test0.setXYZ(test0.xyz().dividedByF(test0.w()));
                _ = test1.setXYZ(test1.xyz().dividedByF(test1.w()));
                // std.log.info("Near: {d}, far: {d}", .{ test0.z(), test1.z() });
            }

            return result;
        }

        pub fn orthographicProjection(
            aspect_width_over_height: f32,
            near_clip_plane: f32,
            far_clip_plane: f32,
        ) Self {
            const a: f32 = 1;
            const b: f32 = aspect_width_over_height;

            const n: f32 = near_clip_plane; // Near clip plane distance.
            const f: f32 = far_clip_plane; // Far clip plane distance.

            // These are non-perspective corrected terms, for orthographic.
            const d: f32 = 2 / (n - f);
            const e: f32 = (n + f) / (n - f);

            const result: Self = .{
                .forward = .{
                    .values = .{
                        .new(a, 0, 0, 0),
                        .new(0, b, 0, 0),
                        .new(0, 0, d, e),
                        .new(0, 0, 0, 1),
                    },
                },
                .inverse = .{
                    .values = .{
                        .new(1 / a, 0, 0, 0),
                        .new(0, 1 / b, 0, 0),
                        .new(0, 0, 1 / d, e / d),
                        .new(0, 0, 0, 1),
                    },
                },
            };

            if (SLOW) {
                const ident: Matrix4x4 = result.inverse.times(result.forward);
                const test0: Vector3 = result.forward.timesV(.new(0, 0, -n));
                const test1: Vector3 = result.forward.timesV(.new(0, 0, -f));
                _ = ident;
                _ = test0;
                _ = test1;
            }

            return result;
        }
    };
}

fn MatrixType(comptime row_count: comptime_int, comptime col_count: comptime_int) type {
    return extern struct {
        const VectorType =
            if (row_count != col_count) unreachable else if (row_count == 2) Vector2Type(f32) else if (row_count == 3) Vector3Type(f32) else if (row_count == 4) Vector4Type(f32);

        // Row major storage.
        values: [row_count]VectorType = [1]VectorType{.zero()} ** row_count,

        const Self = @This();

        pub fn columns3x3(x: Vector3, y: Vector3, z: Vector3) Matrix4x4 {
            return .{
                .values = .{
                    .new(x.x(), y.x(), z.x(), 0),
                    .new(x.y(), y.y(), z.y(), 0),
                    .new(x.z(), y.z(), z.z(), 0),
                    .new(0, 0, 0, 1),
                },
            };
        }

        pub fn rows3x3(x: Vector3, y: Vector3, z: Vector3) Matrix4x4 {
            return .{
                .values = .{
                    .new(x.x(), x.y(), x.z(), 0),
                    .new(y.x(), y.y(), y.z(), 0),
                    .new(z.x(), z.y(), z.z(), 0),
                    .new(0, 0, 0, 1),
                },
            };
        }

        pub fn plus(self: Self, b: Self) Self {
            var result = self;

            for (0..row_count) |row| {
                result.values[row] = result.values[row].plus(b.values[row]);
            }

            return result;
        }

        pub fn times(self: Self, b: Self) Self {
            var result = Self{};

            for (0..row_count) |r| { // Rows of self.
                for (0..col_count) |c| { // Columns of b.
                    for (0..col_count) |i| { // Columns of self, and rows of b.
                        result.values[r].values[c] += self.values[r].values[i] * b.values[i].values[c];
                    }
                }
            }

            return result;
        }

        pub fn timesV(self: Matrix4x4, p: Vector3) Vector3 {
            return self.timesV4(p.toVector4(1)).xyz();
        }

        pub fn timesV4(self: Matrix4x4, p: Vector4) Vector4 {
            var r: Vector4 = .zero();

            _ = r.setX(p.x() * self.values[0].values[0] +
                p.y() * self.values[0].values[1] +
                p.z() * self.values[0].values[2] +
                p.w() * self.values[0].values[3]);
            _ = r.setY(p.x() * self.values[1].values[0] +
                p.y() * self.values[1].values[1] +
                p.z() * self.values[1].values[2] +
                p.w() * self.values[1].values[3]);
            _ = r.setZ(p.x() * self.values[2].values[0] +
                p.y() * self.values[2].values[1] +
                p.z() * self.values[2].values[2] +
                p.w() * self.values[2].values[3]);
            _ = r.setW(p.x() * self.values[2].values[0] +
                p.y() * self.values[3].values[1] +
                p.z() * self.values[3].values[2] +
                p.w() * self.values[3].values[3]);

            return r;
        }

        pub fn identity() Self {
            var result: Self = .{};

            for (0..row_count) |r| {
                result.values[r].values[r] = 1;
            }

            return result;
        }

        pub fn xRotation(angle: f32) Matrix4x4 {
            const c = @cos(angle);
            const s = @sin(angle);
            return .{
                .values = .{
                    .new(1, 0, 0, 0),
                    .new(0, c, -s, 0),
                    .new(0, s, c, 0),
                    .new(0, 0, 0, 1),
                },
            };
        }

        pub fn yRotation(angle: f32) Matrix4x4 {
            const c = @cos(angle);
            const s = @sin(angle);
            return .{
                .values = .{
                    .new(c, 0, s, 0),
                    .new(0, 1, 0, 0),
                    .new(-s, 0, c, 0),
                    .new(0, 0, 0, 1),
                },
            };
        }

        pub fn zRotation(angle: f32) Matrix4x4 {
            const c = @cos(angle);
            const s = @sin(angle);
            return .{
                .values = .{
                    .new(c, -s, 0, 0),
                    .new(s, c, 0, 0),
                    .new(0, 0, 1, 0),
                    .new(0, 0, 0, 1),
                },
            };
        }

        pub fn translation(t: Vector3) Matrix4x4 {
            return .{
                .values = .{
                    .new(1, 0, 0, t.x()),
                    .new(0, 1, 0, t.y()),
                    .new(0, 0, 1, t.z()),
                    .new(0, 0, 0, 1),
                },
            };
        }

        pub fn transpose(self: Self) Self {
            var result: Self = .{};

            for (0..row_count) |j| {
                for (0..col_count) |i| {
                    result.values[j].values[i] = self.values[i].values[j];
                }
            }

            return result;
        }

        pub fn translate(self: Matrix4x4, t: Vector3) Matrix4x4 {
            var result = self;

            result.values[0].values[3] += t.x();
            result.values[1].values[3] += t.y();
            result.values[2].values[3] += t.z();

            return result;
        }

        pub fn getColumn(self: Matrix4x4, column: usize) Vector3 {
            var result: Vector3 = .zero();

            for (0..row_count - 1) |r| {
                result.values[r] = self.values[r].values[column];
            }

            return result;
        }

        pub fn getRow(self: Self, row: usize) VectorType {
            return self.values[row];
        }

        pub inline fn toGL(self: Self) *const f32 {
            return @ptrCast(&self.values);
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

pub fn square(a: f32) f32 {
    return a * a;
}

pub fn squareV4(vector: @Vector(4, f32)) @Vector(4, f32) {
    return vector * vector;
}

pub fn lerpf(min: f32, max: f32, time: f32) f32 {
    return (1.0 - time) * min + time * max;
}

pub fn lerpI32Binormal(a: i32, b: i32, time_binormal: f32) i32 {
    const time: f32 = 0.5 + 0.5 * time_binormal;
    const result: f32 = lerpf(@floatFromInt(a), @floatFromInt(b), time);
    return @intFromFloat(result);
}

pub fn sin01(time: f32) f32 {
    return @sin(PI32 * time);
}

pub fn triangle01(time: f32) f32 {
    var result: f32 = 2 * time;
    if (result > 1) {
        result = 2 - result;
    }
    return result;
}

pub fn clampi32(min: i32, value: i32, max: i32) i32 {
    var result = value;

    if (result < min) {
        result = min;
    }

    if (result > max) {
        result = max;
    }

    return result;
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

pub fn clamp01MapToRange(min: f32, max: f32, value: f32) f32 {
    var result: f32 = 0;
    const range = max - min;

    if (range != 0) {
        result = clampf01((value - min) / range);
    }

    return result;
}

pub fn clampBinormalMapToRange(min: f32, max: f32, value: f32) f32 {
    return -1.0 + 2.0 * clamp01MapToRange(min, max, value);
}

pub fn clampAboveZero(value: f32) f32 {
    return if (value < 0) 0 else value;
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

pub fn safeRatioNf64(numerator: f64, divisor: f64, fallback: f64) f64 {
    var result: f64 = fallback;

    if (divisor != 0) {
        result = numerator / divisor;
    }

    return result;
}

pub fn safeRatio0f64(numerator: f64, divisor: f64) f64 {
    return safeRatioNf64(numerator, divisor, 0);
}

pub fn safeRatio1f64(numerator: f64, divisor: f64) f64 {
    return safeRatioNf64(numerator, divisor, 1);
}

pub inline fn sRGB255ToLinear1(color: Color) Color {
    const inverse_255: f32 = 1.0 / 255.0;

    return Color.new(
        square(inverse_255 * color.r()),
        square(inverse_255 * color.g()),
        square(inverse_255 * color.b()),
        inverse_255 * color.a(),
    );
}

pub inline fn linearToSRGB(color: Color) Color {
    return Color.new(
        square(color.r()),
        square(color.g()),
        square(color.b()),
        color.a(),
    );
}

pub inline fn linear1ToSRGB255(color: Color) Color {
    return Color.new(
        255.0 * @sqrt(color.r()),
        255.0 * @sqrt(color.g()),
        255.0 * @sqrt(color.b()),
        255.0 * color.a(),
    );
}

pub fn swapRedAndBlue(color: u32) u32 {
    const result: u32 = ((color & 0xff00ff00) |
        ((color >> 16) & 0xff) |
        ((color & 0xff) << 16));

    return result;
}

pub fn isInRange(min: f32, value: f32, max: f32) bool {
    return min <= value and value <= max;
}

pub fn aspectRatioFit(render_width: u32, render_height: u32, window_width: u32, window_height: u32) Rectangle2i {
    var result: Rectangle2i = .fromMinMax(.zero(), .zero());

    if (render_width > 0 and render_height > 0 and window_width > 0 and window_height > 0) {
        const optimal_window_width: f32 =
            @as(f32, @floatFromInt(window_height)) *
            (@as(f32, @floatFromInt(render_width)) / @as(f32, @floatFromInt(render_height)));
        const optimal_window_height: f32 =
            @as(f32, @floatFromInt(window_width)) *
            (@as(f32, @floatFromInt(render_height)) / @as(f32, @floatFromInt(render_width)));

        if (optimal_window_width > @as(f32, @floatFromInt(window_width))) {
            // Width-constrained display, top and bottom black bars.
            _ = result.min.setX(0);
            _ = result.max.setX(@intCast(window_width));

            const empty: f32 = @as(f32, @floatFromInt(window_height)) - optimal_window_height;
            const half_empty: i32 = intrinsics.roundReal32ToInt32(0.5 * empty);
            const use_height: i32 = intrinsics.roundReal32ToInt32(optimal_window_height);

            _ = result.min.setY(half_empty);
            _ = result.max.setY(result.min.y() + use_height);
        } else {
            // Height-constrained display, left and right black bars.
            _ = result.min.setY(0);
            _ = result.max.setY(@intCast(window_height));

            const empty: f32 = @as(f32, @floatFromInt(window_width)) - optimal_window_width;
            const half_empty: i32 = intrinsics.roundReal32ToInt32(0.5 * empty);
            const use_width: i32 = intrinsics.roundReal32ToInt32(optimal_window_width);

            _ = result.min.setX(half_empty);
            _ = result.max.setX(result.min.x() + use_width);
        }
    }

    return result;
}

pub fn fitCameraDistanceToHalfDistance(
    focal_length: f32,
    monitor_half_dim_in_meters: f32,
    half_dim_in_meters: f32,
) f32 {
    const result: f32 = (focal_length * half_dim_in_meters) / monitor_half_dim_in_meters;
    return result;
}

pub fn fitCameraDistanceToHalfDimensionV2(
    focal_length: f32,
    monitor_half_dim_in_meters: f32,
    half_dim_in_meters: Vector2,
) Vector2 {
    const result: Vector2 = .new(
        fitCameraDistanceToHalfDistance(focal_length, monitor_half_dim_in_meters, half_dim_in_meters.x()),
        fitCameraDistanceToHalfDistance(focal_length, monitor_half_dim_in_meters, half_dim_in_meters.y()),
    );
    return result;
}
