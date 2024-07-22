const shared = @import("shared.zig");
const math = @import("math.zig");
const std = @import("std");

pub const ENTITY_VISIBLE_PIECE_COUNT = 4096;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const LoadedBitmap = shared.LoadedBitmap;

pub const RenderBasis = struct {
    position: Vector3,

    pub fn zero() RenderBasis {
        return RenderBasis{ .position = Vector3.zero() };
    }
};

pub const EntityVisiblePiece = struct {
    basis: *RenderBasis,
    bitmap: ?*const LoadedBitmap,
    offset: Vector2,
    offset_z: f32,
    entity_z_amount: f32,

    color: Color,
    dimension: Vector2 = Vector2.zero(),
};

pub const RenderGroup = struct {
    default_basis: *RenderBasis,
    meters_to_pixels: f32,

    max_push_buffer_size: u32,
    push_buffer_size: u32,
    push_buffer_base: [*]u8,

    pub fn allocate(arena: *shared.MemoryArena, max_push_buffer_size: u32, meters_to_pixels: f32) *RenderGroup {
        var result = arena.pushStruct(RenderGroup);

        result.max_push_buffer_size = max_push_buffer_size;
        result.push_buffer_size = 0;
        result.push_buffer_base = @ptrCast(arena.pushSize(@alignOf(u8), result.max_push_buffer_size));
        result.default_basis = arena.pushStruct(RenderBasis);
        result.default_basis.position = Vector3.zero();
        result.meters_to_pixels = meters_to_pixels;

        return result;
    }

    fn pushRenderElement(self: *RenderGroup, size: u32) ?[*]u8 {
        var result: ?[*]u8 = null;

        if ((self.push_buffer_size + size) < self.max_push_buffer_size) {
            result = self.push_buffer_base + self.push_buffer_size;
            self.push_buffer_size += size;
        } else {
            unreachable;
        }

        return result;
    }

    fn pushPiece(
        self: *RenderGroup,
        bitmap: ?*const LoadedBitmap,
        offset: Vector2,
        offset_z: f32,
        entity_z_amount: f32,
        alignment: Vector2,
        color: Color,
        dimension: Vector2,
    ) void {
        if (self.pushRenderElement(@sizeOf(EntityVisiblePiece))) |piece_pointer| {
            var piece: *EntityVisiblePiece = @ptrCast(@alignCast(piece_pointer));

            piece.basis = self.default_basis;
            piece.bitmap = bitmap;
            piece.offset = Vector2.new(offset.x(), -offset.y()).scaledTo(self.meters_to_pixels).minus(alignment);
            piece.offset_z = offset_z;
            piece.entity_z_amount = entity_z_amount;

            piece.color = color;
            piece.dimension = dimension;
        }
    }

    pub fn pushBitmap(
        self: *RenderGroup,
        bitmap: *const LoadedBitmap,
        offset: Vector2,
        offset_z: f32,
        alignment: Vector2,
        alpha: f32,
        entity_z_amount: f32,
    ) void {
        const color = Color.new(0, 0, 0, alpha);
        self.pushPiece(bitmap, offset, offset_z, entity_z_amount, alignment, color, Vector2.zero());
    }

    pub fn pushRectangle(
        self: *RenderGroup,
        dimension: Vector2,
        offset: Vector2,
        offset_z: f32,
        color: Color,
        entity_z_amount: f32,
    ) void {
        self.pushPiece(null, offset, offset_z, entity_z_amount, Vector2.zero(), color, dimension);
    }
    pub fn pushRectangleOutline(
        self: *RenderGroup,
        dimension: Vector2,
        offset: Vector2,
        offset_z: f32,
        color: Color,
        entity_z_amount: f32,
    ) void {
        const thickness: f32 = 0.1;
        self.pushPiece(
            null,
            offset.minus(Vector2.new(0, dimension.y() / 2)),
            offset_z,
            entity_z_amount,
            Vector2.zero(),
            color,
            Vector2.new(dimension.x(), thickness),
        );
        self.pushPiece(
            null,
            offset.plus(Vector2.new(0, dimension.y() / 2)),
            offset_z,
            entity_z_amount,
            Vector2.zero(),
            color,
            Vector2.new(dimension.x(), thickness),
        );

        self.pushPiece(
            null,
            offset.minus(Vector2.new(dimension.x() / 2, 0)),
            offset_z,
            entity_z_amount,
            Vector2.zero(),
            color,
            Vector2.new(thickness, dimension.y()),
        );
        self.pushPiece(
            null,
            offset.plus(Vector2.new(dimension.x() / 2, 0)),
            offset_z,
            entity_z_amount,
            Vector2.zero(),
            color,
            Vector2.new(thickness, dimension.y()),
        );
    }
};
