const shared = @import("shared.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

pub const ENTITY_VISIBLE_PIECE_COUNT = 4096;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const LoadedBitmap = shared.LoadedBitmap;

pub const RenderBasis = extern struct {
    position: Vector3,
};

pub const RenderEntityBasis = extern struct {
    basis: *RenderBasis,
    offset: Vector2,
    offset_z: f32,
    entity_z_amount: f32,
};

pub const RenderEntryType = enum(u8) {
    RenderEntryClear,
    RenderEntryBitmap,
    RenderEntryRectangle,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
};

pub const RenderEntryClear = extern struct {
    header: RenderEntryHeader,
    color: Color,
};

pub const RenderEntryBitmap = extern struct {
    header: RenderEntryHeader,
    entity_basis: RenderEntityBasis,
    bitmap: ?*const LoadedBitmap,
    color: Color,
};

pub const RenderEntryRectangle = extern struct {
    header: RenderEntryHeader,
    entity_basis: RenderEntityBasis,
    dimension: Vector2 = Vector2.zero(),
    color: Color,
};

pub const RenderGroup = extern struct {
    default_basis: *RenderBasis,
    meters_to_pixels: f32,

    max_push_buffer_size: u32,
    push_buffer_size: u32,
    push_buffer_base: [*]u8,

    pub fn allocate(arena: *shared.MemoryArena, max_push_buffer_size: u32, meters_to_pixels: f32) *RenderGroup {
        var result = arena.pushStruct(RenderGroup);

        result.max_push_buffer_size = max_push_buffer_size;
        result.push_buffer_size = 0;
        result.push_buffer_base = @ptrCast(arena.pushSize(result.max_push_buffer_size));
        result.default_basis = arena.pushStruct(RenderBasis);
        result.default_basis.position = Vector3.zero();
        result.meters_to_pixels = meters_to_pixels;

        return result;
    }

    fn pushRenderElement(self: *RenderGroup, comptime T: type) ?*T {
        const entry_type: RenderEntryType = @field(RenderEntryType, @typeName(T)[7..]);
        return @ptrCast(@alignCast(self.pushRenderElement_(@sizeOf(T), entry_type, @alignOf(T))));
    }

    fn pushRenderElement_(
        self: *RenderGroup,
        size: u32,
        entry_type: RenderEntryType,
        alignment: usize,
    ) ?*RenderEntryHeader {
        _ = alignment;
        var result: ?*RenderEntryHeader = null;

        if ((self.push_buffer_size + size) < self.max_push_buffer_size) {
            result = @ptrCast(self.push_buffer_base + self.push_buffer_size);
            result.?.type = entry_type;
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
        _: Vector2,
    ) void {
        if (self.pushRenderElement(RenderEntryBitmap)) |entry| {
            entry.entity_basis.basis = self.default_basis;
            entry.entity_basis.offset = Vector2.new(offset.x(), -offset.y())
                .scaledTo(self.meters_to_pixels).minus(alignment);
            entry.entity_basis.offset_z = offset_z;
            entry.entity_basis.entity_z_amount = entity_z_amount;

            entry.bitmap = bitmap;

            entry.color = color;
        }
    }

    pub fn pushClear(self: *RenderGroup, color: Color) void {
        if (self.pushRenderElement(RenderEntryClear)) |entry| {
            entry.color = color;
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
        entity_z_amount: f32,
        color: Color,
    ) void {
        if (self.pushRenderElement(RenderEntryRectangle)) |entry| {
            const half_dimension = dimension.scaledTo(self.meters_to_pixels).scaledTo(0.5);

            entry.entity_basis.basis = self.default_basis;
            entry.entity_basis.offset = Vector2.new(offset.x(), -offset.y())
                .scaledTo(self.meters_to_pixels).minus(half_dimension);
            entry.entity_basis.offset_z = offset_z;
            entry.entity_basis.entity_z_amount = entity_z_amount;

            entry.color = color;
            entry.dimension = dimension.scaledTo(self.meters_to_pixels);
        }
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
        self.pushRectangle(
            Vector2.new(dimension.x(), thickness),
            offset.minus(Vector2.new(0, dimension.y() / 2)),
            offset_z,
            entity_z_amount,
            color,
        );
        self.pushRectangle(
            Vector2.new(dimension.x(), thickness),
            offset.plus(Vector2.new(0, dimension.y() / 2)),
            offset_z,
            entity_z_amount,
            color,
        );

        self.pushRectangle(
            Vector2.new(thickness, dimension.y()),
            offset.minus(Vector2.new(dimension.x() / 2, 0)),
            offset_z,
            entity_z_amount,
            color,
        );
        self.pushRectangle(
            Vector2.new(thickness, dimension.y()),
            offset.plus(Vector2.new(dimension.x() / 2, 0)),
            offset_z,
            entity_z_amount,
            color,
        );
    }

    pub fn getRenderEntityBasisPosition(
        self: *RenderGroup,
        entity_basis: *RenderEntityBasis,
        screen_center: Vector2,
    ) Vector2 {
        const entity_base_position = entity_basis.basis.position;
        const z_fudge = 1.0 + 0.1 * (entity_base_position.z() + entity_basis.offset_z);
        const entity_ground_point_x = screen_center.x() + self.meters_to_pixels * z_fudge * entity_base_position.x();
        const entity_ground_point_y = screen_center.y() - self.meters_to_pixels * z_fudge * entity_base_position.y();
        const entity_z = -self.meters_to_pixels * entity_base_position.z();

        const center = Vector2.new(
            entity_basis.offset.x() + entity_ground_point_x,
            entity_basis.offset.y() + entity_ground_point_y + (entity_z * entity_basis.entity_z_amount),
        );

        return center;
    }

    pub fn renderTo(self: *RenderGroup, output_target: *LoadedBitmap) void {
        const screen_center = Vector2.new(
            0.5 * @as(f32, @floatFromInt(output_target.width)),
            0.5 * @as(f32, @floatFromInt(output_target.height)),
        );

        var base_address: u32 = 0;
        while (base_address < self.push_buffer_size) {
            const header: *RenderEntryHeader = @ptrCast(@alignCast(self.push_buffer_base + base_address));

            switch (header.type) {
                .RenderEntryClear => {
                    const entry: *RenderEntryClear = @ptrCast(@alignCast(header));
                    base_address += @sizeOf(@TypeOf(entry.*));

                    const dimension = Vector2.newI(output_target.width, output_target.height);
                    drawRectangle(output_target, Vector2.zero(), dimension, entry.color);
                },
                .RenderEntryBitmap => {
                    const entry: *RenderEntryBitmap = @ptrCast(@alignCast(header));
                    base_address += @sizeOf(@TypeOf(entry.*));

                    if (entry.bitmap) |bitmap| {
                        const position = self.getRenderEntityBasisPosition(&entry.entity_basis, screen_center);
                        drawBitmap(output_target, bitmap, position.x(), position.y(), entry.color.a());
                    }
                },
                .RenderEntryRectangle => {
                    const entry: *RenderEntryRectangle = @ptrCast(@alignCast(header));
                    base_address += @sizeOf(@TypeOf(entry.*));

                    const position = self.getRenderEntityBasisPosition(&entry.entity_basis, screen_center);
                    drawRectangle(output_target, position, position.plus(entry.dimension), entry.color);
                },
            }
        }
    }
};

pub fn drawRectangle(
    draw_buffer: *LoadedBitmap,
    min: Vector2,
    max: Vector2,
    color: Color,
) void {
    // Round input values.
    var min_x = intrinsics.floorReal32ToInt32(min.x());
    var min_y = intrinsics.floorReal32ToInt32(min.y());
    var max_x = intrinsics.floorReal32ToInt32(max.x());
    var max_y = intrinsics.floorReal32ToInt32(max.y());

    // Clip input values to buffer.
    if (min_x < 0) {
        min_x = 0;
    }
    if (min_y < 0) {
        min_y = 0;
    }
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Set the pointer to the top left corner of the rectangle.
    var row: [*]u8 = @ptrCast(draw_buffer.memory);
    row += @as(u32, @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch)))));

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            pixel[0] = shared.colorToInt(color);
            pixel += 1;
        }

        row += @as(usize, @intCast(draw_buffer.pitch));
    }
}

pub fn drawRectangleOutline(
    draw_buffer: *LoadedBitmap,
    min: Vector2,
    max: Vector2,
    color: Color,
    radius: f32,
) void {
    // Top.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, min.y() - radius),
        Vector2.new(max.x() + radius, min.y() + radius),
        color,
    );

    // Bottom.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, max.y() - radius),
        Vector2.new(max.x() + radius, max.y() + radius),
        color,
    );

    // Left.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, min.y() - radius),
        Vector2.new(min.x() + radius, max.y() + radius),
        color,
    );

    // Right.
    drawRectangle(
        draw_buffer,
        Vector2.new(max.x() - radius, min.y() - radius),
        Vector2.new(max.x() + radius, max.y() + radius),
        color,
    );
}

pub fn drawBitmap(
    draw_buffer: *LoadedBitmap,
    bitmap: *const LoadedBitmap,
    real_x: f32,
    real_y: f32,
    in_alpha: f32,
) void {
    // TODO: Should we really clamp here?
    const alpha = math.clampf01(in_alpha);

    // The pixel color calculation below doesn't handle sizes outside the range of 0 - 1.
    std.debug.assert(alpha >= 0 and alpha <= 1);

    // Calculate extents.
    var min_x = intrinsics.floorReal32ToInt32(real_x);
    var min_y = intrinsics.floorReal32ToInt32(real_y);
    var max_x: i32 = @intFromFloat(real_x + @as(f32, @floatFromInt(bitmap.width)));
    var max_y: i32 = @intFromFloat(real_y + @as(f32, @floatFromInt(bitmap.height)));

    // Clip input values to buffer.
    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = -min_x;
        min_x = 0;
    }
    var source_offset_y: i32 = 0;
    if (min_y < 0) {
        source_offset_y = -min_y;
        min_y = 0;
    }
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Move to the correct spot in the data.
    const source_offset: i32 =
        @intCast(source_offset_y * @as(i32, @intCast(bitmap.pitch)) + shared.BITMAP_BYTES_PER_PIXEL * source_offset_x);
    var source_row: [*]u8 = @ptrCast(bitmap.memory);
    if (source_offset >= 0) {
        source_row += @as(usize, @intCast(source_offset));
    } else {
        source_row -= @as(usize, @intCast(-source_offset));
    }

    // Move to the correct spot in the destination.
    const dest_offset: usize =
        @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch))));
    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);
    dest_row += dest_offset;

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(source_row));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            const sa: f32 = @floatFromInt((source[0] >> 24) & 0xFF);
            const rsa: f32 = alpha * (sa / 255.0);
            const sr: f32 = alpha * @as(f32, @floatFromInt((source[0] >> 16) & 0xFF));
            const sg: f32 = alpha * @as(f32, @floatFromInt((source[0] >> 8) & 0xFF));
            const sb: f32 = alpha * @as(f32, @floatFromInt((source[0] >> 0) & 0xFF));

            const da: f32 = @floatFromInt((dest[0] >> 24) & 0xFF);
            const rda: f32 = (da / 255.0);
            const dr: f32 = @floatFromInt((dest[0] >> 16) & 0xFF);
            const dg: f32 = @floatFromInt((dest[0] >> 8) & 0xFF);
            const db: f32 = @floatFromInt((dest[0] >> 0) & 0xFF);

            const inv_rsa = (1.0 - rsa);
            const a = 255.0 * (rsa + rda - rsa * rda);
            const r = inv_rsa * dr + sr;
            const g = inv_rsa * dg + sg;
            const b = inv_rsa * db + sb;

            dest[0] = ((@as(u32, @intFromFloat(a + 0.5)) << 24) |
                (@as(u32, @intFromFloat(r + 0.5)) << 16) |
                (@as(u32, @intFromFloat(g + 0.5)) << 8) |
                (@as(u32, @intFromFloat(b + 0.5)) << 0));

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
        if (bitmap.pitch >= 0) {
            source_row += @as(usize, @intCast(bitmap.pitch));
        } else {
            source_row -= @as(usize, @intCast(-bitmap.pitch));
        }
    }
}

pub fn drawBitmapMatte(
    draw_buffer: *LoadedBitmap,
    bitmap: *LoadedBitmap,
    real_x: f32,
    real_y: f32,
    in_alpha: f32,
) void {
    // TODO: Should we really clamp here?
    const alpha = math.clampf01(in_alpha);

    // The pixel color calculation below doesn't handle sizes outside the range of 0 - 1.
    std.debug.assert(alpha >= 0 and alpha <= 1);

    // Calculate extents.
    var min_x = intrinsics.floorReal32ToInt32(real_x);
    var min_y = intrinsics.floorReal32ToInt32(real_y);
    var max_x: i32 = @intFromFloat(real_x + @as(f32, @floatFromInt(bitmap.width)));
    var max_y: i32 = @intFromFloat(real_y + @as(f32, @floatFromInt(bitmap.height)));

    // Clip input values to buffer.
    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = -min_x;
        min_x = 0;
    }
    var source_offset_y: i32 = 0;
    if (min_y < 0) {
        source_offset_y = -min_y;
        min_y = 0;
    }
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Move to the correct spot in the data.
    const source_offset: i32 =
        @intCast(source_offset_y * @as(i32, @intCast(bitmap.pitch)) + shared.BITMAP_BYTES_PER_PIXEL * source_offset_x);
    var source_row: [*]u8 = @ptrCast(bitmap.memory);
    if (source_offset >= 0) {
        source_row += @as(usize, @intCast(source_offset));
    } else {
        source_row -= @as(usize, @intCast(-source_offset));
    }

    // Move to the correct spot in the destination.
    const dest_offset: usize =
        @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch))));
    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);
    dest_row += dest_offset;

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(source_row));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            const sa: f32 = @floatFromInt((source[0] >> 24) & 0xFF);
            const rsa: f32 = alpha * (sa / 255.0);

            const da: f32 = @floatFromInt((dest[0] >> 24) & 0xFF);
            const dr: f32 = @floatFromInt((dest[0] >> 16) & 0xFF);
            const dg: f32 = @floatFromInt((dest[0] >> 8) & 0xFF);
            const db: f32 = @floatFromInt((dest[0] >> 0) & 0xFF);

            const inv_rsa = (1.0 - rsa);
            const a = inv_rsa * da;
            const r = inv_rsa * dr;
            const g = inv_rsa * dg;
            const b = inv_rsa * db;

            dest[0] = ((@as(u32, @intFromFloat(a + 0.5)) << 24) |
                (@as(u32, @intFromFloat(r + 0.5)) << 16) |
                (@as(u32, @intFromFloat(g + 0.5)) << 8) |
                (@as(u32, @intFromFloat(b + 0.5)) << 0));

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
        if (bitmap.pitch >= 0) {
            source_row += @as(usize, @intCast(bitmap.pitch));
        } else {
            source_row -= @as(usize, @intCast(-bitmap.pitch));
        }
    }
}
