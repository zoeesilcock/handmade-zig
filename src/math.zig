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

        pub inline fn new(x_value: ScalarType, y_value: ScalarType) Self {
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
            return Self{ .values = .{ -self.values[1], self.values[0] } };
        }

        pub inline fn x(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub inline fn y(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub inline fn setX(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub inline fn setY(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub inline fn toVector3(self: Self, in_z: ScalarType) Vector3 {
            return Vector3.new(self.x(), self.y(), in_z);
        }

        pub inline fn isInRectangle(self: *const Self, rectangle: Rectangle2) bool {
            const result = ((self.x() >= rectangle.min.x()) and
                (self.y() >= rectangle.min.y()) and
                (self.x() < rectangle.max.x()) and
                (self.y() < rectangle.max.y()));

            return result;
        }

        pub inline fn arm2(angle: f32) Self {
            return Self.new(intrinsics.cos(angle), intrinsics.sin(angle));
        }

        pub inline fn rayIntersection(pa: Self, ra: Self, pb: Self, rb: Self) Self {
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
        pub const toGL = Shared.toGL;
    };
}

fn Vector3Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(3, ScalarType),

        pub inline fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType) Self {
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

        pub inline fn x(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub inline fn y(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub inline fn z(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub inline fn xy(self: *const Self) Vector2 {
            return Vector2.new(self.x(), self.y());
        }

        pub inline fn yz(self: *const Self) Vector2 {
            return Vector2.new(self.y(), self.z());
        }

        pub inline fn setX(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub inline fn setY(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub inline fn setZ(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub inline fn setXY(self: *Self, value: Vector2) *Self {
            self.values[0] = value.values[0];
            self.values[1] = value.values[1];
            return self;
        }

        pub inline fn setYZ(self: *Self, value: Vector2) *Self {
            self.values[1] = value.values[0];
            self.values[2] = value.values[1];
            return self;
        }

        pub inline fn toVector4(vector3: Vector3, in_w: ScalarType) Vector4 {
            return Vector4.new(vector3.values[0], vector3.values[1], vector3.values[2], in_w);
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

        pub fn crossProduct(self: Self, b: Self) Self {
            return .new(
                self.y() * b.z() - self.z() * b.y(),
                self.z() * b.x() - self.x() * b.z(),
                self.x() * b.y() - self.y() * b.x(),
            );
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
        pub const toGL = Shared.toGL;
    };
}

fn Vector4Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(4, ScalarType),

        pub inline fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType, w_value: ScalarType) Self {
            return Self{ .values = .{ x_value, y_value, z_value, w_value } };
        }

        pub inline fn newI(x_value: i32, y_value: i32, z_value: i32, w_value: i32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
                @floatFromInt(w_value),
            } };
        }

        pub inline fn newU(x_value: u32, y_value: u32, z_value: u32, w_value: u32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
                @floatFromInt(w_value),
            } };
        }

        pub inline fn x(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub inline fn y(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub inline fn z(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub inline fn w(self: *const Self) ScalarType {
            return self.values[3];
        }

        pub inline fn xy(self: *const Self) Vector2 {
            return Vector2.new(self.x(), self.y());
        }

        pub inline fn yz(self: *const Self) Vector2 {
            return Vector2.new(self.y(), self.z());
        }

        pub inline fn xyz(self: *const Self) Vector3 {
            return Vector3.new(self.x(), self.y(), self.z());
        }

        pub inline fn setX(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub inline fn setY(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub inline fn setZ(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub inline fn setW(self: *Self, value: ScalarType) *Self {
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
        pub const packColorBGRA255 = Shared.packColorBGRA255;
        pub const packColorBGRA = Shared.packColorBGRA;
        pub const packColorRGBA = Shared.packColorRGBA;
        pub const unpackColorRGBA = Shared.unpackColorRGBA;
        pub const toGL = Shared.toGL;
    };
}

fn Color3Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(3, ScalarType),

        pub inline fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType) Self {
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

        pub inline fn r(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub inline fn g(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub inline fn b(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub inline fn setR(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub inline fn setG(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub inline fn setB(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub inline fn toColor(self: Self, in_a: ScalarType) Color {
            return Color.new(self.r(), self.g(), self.b(), in_a);
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
        pub const toGL = Shared.toGL;
    };
}

fn Color4Type(comptime ScalarType: type) type {
    return extern struct {
        const Self = @This();

        values: @Vector(4, ScalarType),

        pub inline fn new(x_value: ScalarType, y_value: ScalarType, z_value: ScalarType, w_value: ScalarType) Self {
            return Self{ .values = .{ x_value, y_value, z_value, w_value } };
        }

        pub inline fn newI(x_value: i32, y_value: i32, z_value: i32, w_value: i32) Self {
            return Self{ .values = .{
                @floatFromInt(x_value),
                @floatFromInt(y_value),
                @floatFromInt(z_value),
                @floatFromInt(w_value),
            } };
        }

        pub inline fn newU(x_value: u32, y_value: u32, z_value: u32, w_value: u32) Self {
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

        pub inline fn r(self: *const Self) ScalarType {
            return self.values[0];
        }

        pub inline fn g(self: *const Self) ScalarType {
            return self.values[1];
        }

        pub inline fn b(self: *const Self) ScalarType {
            return self.values[2];
        }

        pub inline fn a(self: *const Self) ScalarType {
            return self.values[3];
        }

        pub inline fn rgb(self: *const Self) Color3 {
            return Color3.new(self.r(), self.g(), self.b());
        }

        pub inline fn setR(self: *Self, value: ScalarType) *Self {
            self.values[0] = value;
            return self;
        }

        pub inline fn setG(self: *Self, value: ScalarType) *Self {
            self.values[1] = value;
            return self;
        }

        pub inline fn setB(self: *Self, value: ScalarType) *Self {
            self.values[2] = value;
            return self;
        }

        pub inline fn setA(self: *Self, value: ScalarType) *Self {
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
        pub const normalizeOrZero = Shared.normalizeOrZero;
        pub const packColorBGRA255 = Shared.packColorBGRA255;
        pub const packColorBGRA = Shared.packColorBGRA;
        pub const packColorRGBA = Shared.packColorRGBA;
        pub const unpackColorRGBA = Shared.unpackColorRGBA;
        pub const toGL = Shared.toGL;
    };
}

fn VectorShared(comptime dimension_count: comptime_int, comptime ScalarType: type, comptime Self: type) type {
    return struct {
        pub inline fn zero() Self {
            return Self{ .values = @splat(0) };
        }

        pub inline fn one() Self {
            return Self{ .values = @splat(1) };
        }

        pub inline fn white() Self {
            return Self.one();
        }

        pub inline fn black() Self {
            return Self.new(0, 0, 0, 1);
        }

        pub inline fn splat(value: ScalarType) Self {
            return Self{ .values = @splat(value) };
        }

        pub inline fn plus(self: *const Self, b: Self) Self {
            return Self{ .values = self.values + b.values };
        }

        pub inline fn minus(self: *const Self, b: Self) Self {
            return Self{ .values = self.values - b.values };
        }

        pub inline fn times(self: *const Self, b: Self) Self {
            return Self{ .values = self.values * b.values };
        }

        pub inline fn dividedBy(self: *const Self, b: Self) Self {
            return Self{ .values = self.values / b.values };
        }

        pub inline fn dividedByF(self: *const Self, scalar: ScalarType) Self {
            return self.scaledTo(1 / scalar);
        }

        pub inline fn scaledTo(self: *const Self, scalar: ScalarType) Self {
            return Self{ .values = self.values * @as(@TypeOf(self.values), @splat(scalar)) };
        }

        pub inline fn clamp01(self: *const Self) Self {
            var result = Self.zero();

            for (0..dimension_count) |axis_index| {
                result.values[axis_index] = clampf01(self.values[axis_index]);
            }

            return result;
        }

        pub inline fn negated(self: *const Self) Self {
            return Self{ .values = -self.values };
        }

        pub inline fn dotProduct(self: *const Self, b: Self) ScalarType {
            return @reduce(.Add, self.values * b.values);
        }

        pub inline fn hadamardProduct(self: *const Self, b: Self) Self {
            return Self{ .values = self.values * b.values };
        }

        pub inline fn lengthSquared(self: *const Self) ScalarType {
            return self.dotProduct(self.*);
        }

        pub inline fn length(self: *const Self) ScalarType {
            return @sqrt(self.lengthSquared());
        }

        pub inline fn invalidPosition() Self {
            return Self{ .values = @splat(100000) };
        }

        pub inline fn lerp(min: Self, max: Self, time: ScalarType) Self {
            return Self{ .values = min.values + @as(@TypeOf(min.values), @splat(time)) * (max.values - min.values) };
        }

        pub inline fn normalized(self: Self) Self {
            return self.scaledTo(1.0 / self.length());
        }

        pub inline fn normalizeOrZero(self: Self) Self {
            var result: Self = Self.zero();
            const length_squared: f32 = self.lengthSquared();
            if (length_squared > square(0.0001)) {
                result = self.scaledTo(1 / @sqrt(length_squared));
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
            return ((intrinsics.roundReal32ToUInt32(self.a() + 0.5) << 24) |
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

        pub inline fn packColorRGBA(self: Self) u32 {
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

        pub inline fn new(min_x: ScalarType, min_y: ScalarType, max_x: ScalarType, max_y: ScalarType) Self {
            return Self{
                .min = VectorType.new(min_x, min_y),
                .max = VectorType.new(max_x, max_y),
            };
        }

        pub inline fn toRectangle3(self: Self, min_z: ScalarType, max_z: ScalarType) Rectangle3 {
            return Rectangle3{
                .min = self.min.toVector3(min_z),
                .max = self.max.toVector3(max_z),
            };
        }

        pub inline fn getIntersectionWith(self: *const Self, b: Self) Self {
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

        pub inline fn getUnionWith(self: *const Self, b: *Self) Self {
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

        pub inline fn getClampedArea(self: *const Self) ScalarType {
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

        pub inline fn new(
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
        pub inline fn toRectangle2(self: Self) Rectangle2 {
            return Rectangle2{
                .min = self.min.xy(),
                .max = self.max.xy(),
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
        pub inline fn invertedInfinityInt() Self {
            const scalar_max = std.math.maxInt(ScalarType);
            return Self.new(scalar_max, scalar_max, -scalar_max, -scalar_max);
        }

        pub inline fn invertedInfinityFloat() Self {
            const scalar_max = std.math.floatMax(ScalarType);
            return Self.new(scalar_max, scalar_max, -scalar_max, -scalar_max);
        }

        pub inline fn zero() Self {
            return Self{
                .min = VectorType.splat(0),
                .max = VectorType.splat(0),
            };
        }

        pub inline fn fromMinMax(min: VectorType, max: VectorType) Self {
            return Self{
                .min = min,
                .max = max,
            };
        }

        pub inline fn fromMinDimension(min: VectorType, dimension: VectorType) Self {
            return Self{
                .min = min,
                .max = min.plus(dimension),
            };
        }

        pub inline fn fromCenterHalfDimension(center: VectorType, half_dimension: VectorType) Self {
            return Self{
                .min = center.minus(half_dimension),
                .max = center.plus(half_dimension),
            };
        }

        pub inline fn fromCenterDimension(center: VectorType, dimension: VectorType) Self {
            return fromCenterHalfDimension(center, dimension.scaledTo(0.5));
        }

        pub inline fn getMinCorner(self: *const Self) VectorType {
            return self.min;
        }

        pub inline fn getMaxCorner(self: *const Self) VectorType {
            return self.max;
        }

        pub inline fn getCenter(self: *const Self) VectorType {
            return self.min.plus(self.max).scaledTo(0.5);
        }

        pub inline fn getDimension(self: *const Self) VectorType {
            return self.max.minus(self.min);
        }

        pub inline fn getWidth(self: *const Self) ScalarType {
            return self.max.x() - self.min.x();
        }

        pub inline fn getHeight(self: *const Self) ScalarType {
            return self.max.y() - self.min.y();
        }

        pub inline fn getBarycentricPosition(self: *const Self, position: VectorType) VectorType {
            var result = VectorType.zero();

            for (0..dimension_count) |axis_index| {
                result.values[axis_index] = safeRatio0(
                    position.values[axis_index] - self.min.values[axis_index],
                    self.max.values[axis_index] - self.min.values[axis_index],
                );
            }

            return result;
        }

        pub inline fn addRadius(self: *const Self, radius: VectorType) Self {
            return Self{
                .min = self.min.minus(radius),
                .max = self.max.plus(radius),
            };
        }

        pub inline fn offsetBy(self: *const Self, offset: VectorType) Self {
            return Self{
                .min = self.min.plus(offset),
                .max = self.max.plus(offset),
            };
        }

        pub inline fn intersects(self: *const Self, b: *const Self) bool {
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

        pub inline fn getArea(self: *const Self) ScalarType {
            const dimension: VectorType = self.getDimension();
            return dimension.x() * dimension.y();
        }

        pub inline fn hasArea(self: *const Self) bool {
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

        pub inline fn plus(self: Self, b: Self) Self {
            var result = self;

            for (0..row_count) |row| {
                result.values[row] = result.values[row].plus(b.values[row]);
            }

            return result;
        }

        pub inline fn times(self: Self, b: Self) Self {
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

        pub inline fn timesV(self: Matrix4x4, p: Vector3) Vector3 {
            return self.timesV4(p.toVector4(1)).xyz();
        }

        pub inline fn timesV4(self: Matrix4x4, p: Vector4) Vector4 {
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

        pub inline fn identity() Self {
            var result: Self = .{};

            for (0..row_count) |r| {
                result.values[r].values[r] = 1;
            }

            return result;
        }

        pub inline fn xRotation(angle: f32) Matrix4x4 {
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

        pub inline fn yRotation(angle: f32) Matrix4x4 {
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

        pub inline fn zRotation(angle: f32) Matrix4x4 {
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

        pub inline fn transpose(self: Self) Self {
            var result: Self = .{};

            for (0..row_count) |j| {
                for (0..col_count) |i| {
                    result.values[j].values[i] = self.values[i].values[j];
                }
            }

            return result;
        }

        pub inline fn translate(self: Matrix4x4, t: Vector3) Matrix4x4 {
            var result = self;

            result.values[0].values[3] += t.x();
            result.values[1].values[3] += t.y();
            result.values[2].values[3] += t.z();

            return result;
        }

        pub inline fn getColumn(self: Matrix4x4, column: usize) Vector3 {
            var result: Vector3 = .zero();

            for (0..row_count - 1) |r| {
                result.values[r] = self.values[r].values[column];
            }

            return result;
        }

        pub inline fn getRow(self: Self, row: usize) VectorType {
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

pub inline fn square(a: f32) f32 {
    return a * a;
}

pub inline fn square_v4(vector: @Vector(4, f32)) @Vector(4, f32) {
    return vector * vector;
}

pub inline fn lerpf(min: f32, max: f32, time: f32) f32 {
    return (1.0 - time) * min + time * max;
}

pub inline fn sin01(time: f32) f32 {
    return @sin(PI32 * time);
}

pub inline fn triangle01(time: f32) f32 {
    var result: f32 = 2 * time;
    if (result > 1) {
        result = 2 - result;
    }
    return result;
}

pub inline fn clampf(min: f32, value: f32, max: f32) f32 {
    var result = value;

    if (result < min) {
        result = min;
    }

    if (result > max) {
        result = max;
    }

    return result;
}

pub inline fn clampf01(value: f32) f32 {
    return clampf(0, value, 1);
}

pub inline fn clamp01MapToRange(min: f32, max: f32, value: f32) f32 {
    var result: f32 = 0;
    const range = max - min;

    if (range != 0) {
        result = clampf01((value - min) / range);
    }

    return result;
}

pub inline fn clampAboveZero(value: f32) f32 {
    return if (value < 0) 0 else value;
}

pub inline fn safeRatioN(numerator: f32, divisor: f32, fallback: f32) f32 {
    var result: f32 = fallback;

    if (divisor != 0) {
        result = numerator / divisor;
    }

    return result;
}

pub inline fn safeRatio0(numerator: f32, divisor: f32) f32 {
    return safeRatioN(numerator, divisor, 0);
}

pub inline fn safeRatio1(numerator: f32, divisor: f32) f32 {
    return safeRatioN(numerator, divisor, 1);
}

pub inline fn safeRatioNf64(numerator: f64, divisor: f64, fallback: f64) f64 {
    var result: f64 = fallback;

    if (divisor != 0) {
        result = numerator / divisor;
    }

    return result;
}

pub inline fn safeRatio0f64(numerator: f64, divisor: f64) f64 {
    return safeRatioNf64(numerator, divisor, 0);
}

pub inline fn safeRatio1f64(numerator: f64, divisor: f64) f64 {
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

pub inline fn isInRange(min: f32, value: f32, max: f32) bool {
    return min <= value and value <= max;
}
