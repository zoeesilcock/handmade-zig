const shared = @import("shared.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

pub const ENTITY_VISIBLE_PIECE_COUNT = 4096;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const LoadedBitmap = shared.LoadedBitmap;

const EnvironmentMap = extern struct {
    width: i32,
    height: i32,
    lod: [4]*LoadedBitmap,
};

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
    RenderEntryCoordinateSystem,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
};

pub const RenderEntryClear = extern struct {
    color: Color,
};

pub const RenderEntryBitmap = extern struct {
    entity_basis: RenderEntityBasis,
    bitmap: ?*const LoadedBitmap,
    color: Color,
};

pub const RenderEntryRectangle = extern struct {
    entity_basis: RenderEntityBasis,
    dimension: Vector2 = Vector2.zero(),
    color: Color,
};

pub const RenderEntryCoordinateSystem = extern struct {
    origin: Vector2,
    x_axis: Vector2,
    y_axis: Vector2,
    color: Color,

    texture: *LoadedBitmap,
    normal_map: ?*LoadedBitmap,

    top: *EnvironmentMap,
    middle: *EnvironmentMap,
    bottom: *EnvironmentMap,
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
        result.push_buffer_base = @ptrCast(arena.pushSize(result.max_push_buffer_size, @alignOf(u8)));
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
        in_size: u32,
        entry_type: RenderEntryType,
        comptime alignment: u32,
    ) ?*void {
        var result: ?*void = null;
        const size = in_size + @sizeOf(RenderEntryHeader);

        if ((self.push_buffer_size + size) < self.max_push_buffer_size) {
            const header: *RenderEntryHeader = @ptrCast(self.push_buffer_base + self.push_buffer_size);
            header.type = entry_type;

            const data_address = @intFromPtr(header) + @sizeOf(RenderEntryHeader);
            const aligned_address = std.mem.alignForward(usize, data_address, alignment);
            const aligned_offset = aligned_address - data_address;
            const aligned_size = size + aligned_offset;

            result = @ptrFromInt(aligned_address);
            self.push_buffer_size += @intCast(aligned_size);
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

    pub fn pushCoordinateSystem(
        self: *RenderGroup,
        origin: Vector2,
        x_axis: Vector2,
        y_axis: Vector2,
        color: Color,
        texture: *LoadedBitmap,
        normal_map: ?*LoadedBitmap,
        top: *EnvironmentMap,
        middle: *EnvironmentMap,
        bottom: *EnvironmentMap,
    ) ?*RenderEntryCoordinateSystem {
        var result: ?*RenderEntryCoordinateSystem = null;

        if (self.pushRenderElement(RenderEntryCoordinateSystem)) |entry| {
            entry.origin = origin;
            entry.x_axis = x_axis;
            entry.y_axis = y_axis;
            entry.color = color;
            entry.texture = texture;
            entry.normal_map = normal_map;
            entry.top = top;
            entry.middle = middle;
            entry.bottom = bottom;

            result = @alignCast(entry);
        }

        return result;
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
            const header: *RenderEntryHeader = @ptrCast(self.push_buffer_base + base_address);
            const alignment: usize = switch (header.type) {
                .RenderEntryClear => @alignOf(RenderEntryClear),
                .RenderEntryBitmap => @alignOf(RenderEntryBitmap),
                .RenderEntryRectangle => @alignOf(RenderEntryRectangle),
                .RenderEntryCoordinateSystem => @alignOf(RenderEntryCoordinateSystem),
            };

            const header_address = @intFromPtr(header);
            const data_address = header_address + @sizeOf(RenderEntryHeader);
            const aligned_address = std.mem.alignForward(usize, data_address, alignment);
            const aligned_offset: u32 = @intCast(aligned_address - data_address);
            const data: *void = @ptrFromInt(aligned_address);

            base_address += @sizeOf(RenderEntryHeader) + aligned_offset;

            switch (header.type) {
                .RenderEntryClear => {
                    const entry: *RenderEntryClear = @ptrCast(@alignCast(data));
                    const dimension = Vector2.newI(output_target.width, output_target.height);
                    drawRectangle(output_target, Vector2.zero(), dimension, entry.color);

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryBitmap => {
                    const entry: *RenderEntryBitmap = @ptrCast(@alignCast(data));
                    // if (entry.bitmap) |bitmap| {
                    //     const position = self.getRenderEntityBasisPosition(&entry.entity_basis, screen_center);
                    //     drawBitmap(output_target, bitmap, position.x(), position.y(), entry.color.a());
                    // }

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryRectangle => {
                    const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));
                    const position = self.getRenderEntityBasisPosition(&entry.entity_basis, screen_center);
                    drawRectangle(output_target, position, position.plus(entry.dimension), entry.color);

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryCoordinateSystem => {
                    const entry: *RenderEntryCoordinateSystem = @ptrCast(@alignCast(data));

                    const max = entry.origin.plus(entry.x_axis).plus(entry.y_axis);
                    drawRectangleSlowly(
                        output_target,
                        entry.origin,
                        entry.x_axis,
                        entry.y_axis,
                        entry.color,
                        entry.texture,
                        entry.normal_map,
                        entry.top,
                        entry.middle,
                        entry.bottom,
                    );

                    const color = Color.new(1, 1, 0, 1);
                    const dimension = Vector2.new(6, 6);
                    var position = entry.origin;
                    drawRectangle(output_target, position, position.plus(dimension), color);

                    position = entry.origin.plus(entry.x_axis);
                    drawRectangle(output_target, position, position.plus(dimension), color);

                    position = entry.origin.plus(entry.y_axis);
                    drawRectangle(output_target, position, position.plus(dimension), color);

                    position = max;
                    drawRectangle(output_target, position, position.plus(dimension), color);

                    base_address += @sizeOf(@TypeOf(entry.*));
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
            pixel[0] = color.packColor();
            pixel += 1;
        }

        row += @as(usize, @intCast(draw_buffer.pitch));
    }
}

pub fn drawRectangleSlowly(
    draw_buffer: *LoadedBitmap,
    origin: Vector2,
    x_axis: Vector2,
    y_axis: Vector2,
    color_in: Color,
    texture: *LoadedBitmap,
    opt_normal_map: ?*LoadedBitmap,
    top: *EnvironmentMap,
    middle: *EnvironmentMap,
    bottom: *EnvironmentMap,
) void {
    var color = color_in;
    _ = color.setRGB(color.rgb().scaledTo(color.a()));

    const inv_x_axis_length_squared = 1.0 / x_axis.lengthSquared();
    const inv_y_axis_length_squared = 1.0 / y_axis.lengthSquared();
    const points: [4]Vector2 = .{
        origin,
        origin.plus(x_axis),
        origin.plus(x_axis).plus(y_axis),
        origin.plus(y_axis),
    };

    const width_max = draw_buffer.width - 1;
    const height_max = draw_buffer.height - 1;
    const inv_width_max: f32 = 1.0 / @as(f32, @floatFromInt(width_max));
    const inv_height_max: f32 = 1.0 / @as(f32, @floatFromInt(height_max));
    var y_min: i32 = height_max;
    var y_max: i32 = 0;
    var x_min: i32 = width_max;
    var x_max: i32 = 0;

    for (points) |point| {
        const floor_x = intrinsics.floorReal32ToInt32(point.x());
        const ceil_x = intrinsics.ceilReal32ToInt32(point.x());
        const floor_y = intrinsics.floorReal32ToInt32(point.y());
        const ceil_y = intrinsics.ceilReal32ToInt32(point.y());

        if (x_min > floor_x) {
            x_min = floor_x;
        }
        if (y_min > floor_y) {
            y_min = floor_y;
        }
        if (x_max < ceil_x) {
            x_max = ceil_x;
        }
        if (y_max < ceil_y) {
            y_max = ceil_y;
        }
    }

    if (x_min < 0) {
        x_min = 0;
    }
    if (y_min < 0) {
        y_min = 0;
    }
    if (x_max > width_max) {
        x_max = width_max;
    }
    if (y_max > height_max) {
        y_max = height_max;
    }

    var row: [*]u8 = @ptrCast(draw_buffer.memory);
    row += @as(u32, @intCast((x_min * shared.BITMAP_BYTES_PER_PIXEL) + (y_min * draw_buffer.pitch)));

    var y: i32 = y_min;
    while (y < y_max) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x: i32 = x_min;
        while (x < x_max) : (x += 1) {
            const pixel_position = Vector2.newI(x, y);
            const d = pixel_position.minus(origin);

            const edge0 = d.dotProduct(x_axis.perp().negated());
            const edge1 = d.minus(x_axis).dotProduct(y_axis.perp().negated());
            const edge2 = d.minus(x_axis).minus(y_axis).dotProduct(x_axis.perp());
            const edge3 = d.minus(y_axis).dotProduct(y_axis.perp());

            if (edge0 < 0 and edge1 < 0 and edge2 < 0 and edge3 < 0) {
                const screen_space_uv = Vector2.new(
                    inv_width_max * @as(f32, @floatFromInt(x)),
                    inv_height_max * @as(f32, @floatFromInt(y)),
                );
                const u = d.dotProduct(x_axis) * inv_x_axis_length_squared;
                const v = d.dotProduct(y_axis) * inv_y_axis_length_squared;

                // std.debug.assert(u >= 0 and u <= 1.0);
                // std.debug.assert(v >= 0 and v <= 1.0);

                const texel_x: f32 = 1 + (u * @as(f32, @floatFromInt(texture.width - 3)));
                const texel_y: f32 = 1 + (v * @as(f32, @floatFromInt(texture.height - 3)));

                const texel_rounded_x: i32 = @intFromFloat(texel_x);
                const texel_rounded_y: i32 = @intFromFloat(texel_y);

                const texel_fraction_x: f32 = texel_x - @as(f32, @floatFromInt(texel_rounded_x));
                const texel_fraction_y: f32 = texel_y - @as(f32, @floatFromInt(texel_rounded_y));

                std.debug.assert(texel_rounded_x >= 0 and texel_rounded_x <= texture.width);
                std.debug.assert(texel_rounded_y >= 0 and texel_rounded_y <= texture.height);

                if (texture.memory) |base| {
                    const offset: i32 =
                        @intCast((texel_rounded_x * shared.BITMAP_BYTES_PER_PIXEL) + (texel_rounded_y * texture.pitch));
                    const texture_base = base - @abs(offset);
                    const texel_pointer_a: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base));
                    const texel_pointer_b: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base + @sizeOf(u32)));
                    const texel_pointer_c: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base - @abs(texture.pitch)));
                    const texel_pointer_d: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base + @sizeOf(u32) - @abs(texture.pitch)));

                    var texel_a = Color.unpackColor(texel_pointer_a.*);
                    var texel_b = Color.unpackColor(texel_pointer_b.*);
                    var texel_c = Color.unpackColor(texel_pointer_c.*);
                    var texel_d = Color.unpackColor(texel_pointer_d.*);

                    texel_a = sRGB255ToLinear1(texel_a);
                    texel_b = sRGB255ToLinear1(texel_b);
                    texel_c = sRGB255ToLinear1(texel_c);
                    texel_d = sRGB255ToLinear1(texel_d);

                    var texel = texel_a.lerp(texel_b, texel_fraction_x).lerp(
                        texel_c.lerp(texel_d, texel_fraction_x),
                        texel_fraction_y,
                    );

                    if (opt_normal_map) |normal_map| {
                        if (normal_map.memory) |normal_texture| {
                            const normal_offset: i32 =
                                @intCast((texel_rounded_x * shared.BITMAP_BYTES_PER_PIXEL) + (texel_rounded_y * texture.pitch));
                            const normal_base = normal_texture - @abs(normal_offset);
                            const normal_pointer_a: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(normal_base));
                            const normal_pointer_b: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(normal_base + @sizeOf(u32)));
                            const normal_pointer_c: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(normal_base - @abs(texture.pitch)));
                            const normal_pointer_d: *align(@alignOf(u8)) u32 = @ptrCast(@alignCast(normal_base + @sizeOf(u32) - @abs(texture.pitch)));

                            const normal_a = Vector4.unpackColor(normal_pointer_a.*);
                            const normal_b = Vector4.unpackColor(normal_pointer_b.*);
                            const normal_c = Vector4.unpackColor(normal_pointer_c.*);
                            const normal_d = Vector4.unpackColor(normal_pointer_d.*);

                            const normal = normal_a.lerp(normal_b, texel_fraction_x).lerp(
                                normal_c.lerp(normal_d, texel_fraction_x),
                                texel_fraction_y,
                            );

                            var opt_far_map: ?*EnvironmentMap = null;
                            const env_map_blend: f32 = normal.z();
                            var far_map_blend: f32 = 0;
                            if (env_map_blend < 0.25) {
                                opt_far_map = bottom;
                                far_map_blend = 1.0 - (env_map_blend / 0.25);
                            } else if (env_map_blend > 0.75) {
                                opt_far_map = top;
                                far_map_blend = (1.0 - env_map_blend) / 0.25;
                            }

                            var light_color = sampleEnvironmentMap(middle, screen_space_uv, normal.xyz(), normal.w());
                            if (opt_far_map) |far_map| {
                                const far_map_color = sampleEnvironmentMap(far_map, screen_space_uv, normal.xyz(), normal.w());
                                light_color = light_color.lerp(far_map_color, far_map_blend);
                            }

                            _ = texel.setRGB(texel.rgb().hadamardProduct(light_color));
                        }
                    }

                    texel = texel.hadamardProduct(color);

                    var dest = Color.unpackColor(pixel[0]);
                    dest = sRGB255ToLinear1(dest);

                    const blended = dest.scaledTo(1.0 - texel.a()).plus(texel);
                    const blended255 = linear1ToSRGB255(blended);

                    pixel[0] = ((@as(u32, @intFromFloat(blended255.a() + 0.5)) << 24) |
                        (@as(u32, @intFromFloat(blended255.r() + 0.5)) << 16) |
                        (@as(u32, @intFromFloat(blended255.g() + 0.5)) << 8) |
                        (@as(u32, @intFromFloat(blended255.b() + 0.5)) << 0));
                }
            }

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
    const bitmap_pointer = @as([*]u8, @ptrCast(@alignCast(bitmap.memory.?)));
    var source_row: [*]u8 = shared.incrementPointer(bitmap_pointer, source_offset);

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

            var texel = Color.unpackColor(source[0]);

            texel = sRGB255ToLinear1(texel);
            texel = texel.scaledTo(alpha);

            var d = Color.unpackColor(dest[0]);

            d = sRGB255ToLinear1(d);

            var result = d.scaledTo(1.0 - texel.a()).plus(texel);
            result = linear1ToSRGB255(result);

            dest[0] = result.packColor();
            // dest[0] = ((@as(u32, @intFromFloat(result.a() + 0.5)) << 24) |
            //     (@as(u32, @intFromFloat(result.r() + 0.5)) << 16) |
            //     (@as(u32, @intFromFloat(result.g() + 0.5)) << 8) |
            //     (@as(u32, @intFromFloat(result.b() + 0.5)) << 0));

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));

        source_row = shared.incrementPointer(source_row, bitmap.pitch);
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
    const bitmap_pointer = @as([*]u8, @ptrCast(@alignCast(bitmap.memory.?)));
    var source_row: [*]u8 = shared.incrementPointer(bitmap_pointer, source_offset);

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
        source_row = shared.incrementPointer(source_row, bitmap.pitch);
    }
}

pub fn sRGB255ToLinear1(color: Color) Color {
    const inverse_255: f32 = 1.0 / 255.0;

    return Color.new(
        math.square(inverse_255 * color.r()),
        math.square(inverse_255 * color.g()),
        math.square(inverse_255 * color.b()),
        inverse_255 * color.a(),
    );
}

pub fn linear1ToSRGB255(color: Color) Color {
    return Color.new(
        255.0 * @sqrt(color.r()),
        255.0 * @sqrt(color.g()),
        255.0 * @sqrt(color.b()),
        255.0 * color.a(),
    );
}

fn sampleEnvironmentMap(map: *EnvironmentMap, screen_space_uv: Vector2, normal: Vector3, roughness: f32) Color3 {
    _ = map;
    _ = screen_space_uv;
    _ = roughness;

    return Color3.new(normal.x(), normal.y(), normal.z());
}

