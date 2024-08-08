//! Software renderer.
//!
//! 1: Everywhere outside the renderer, Y always goeas upward, X to the right.
//!
//! 2: All bitmaps including the render target are assumed to be bottom-up (meaning that the first row pointer points
//! to the bottom-most row when viewed on the screen).
//!
//! 3: It is mandatory that all inputs to the renderer are in world coordinates (meters), not pixels. If for some
//! reason something absolutely has to be specified in pixels, that will be explicitly marked in the API, but
//! this should occur exceedingly sparingly.
//!
//! 4: Z is a special coordinate because it is broken up into discrete slices, and the renderer actually understands
//! these slices. Z slices are what control the scaling of things, whereas Z offsets inside a slice are what control
//! Y offsetting.
//!
//! 5: All color values specified to the renderer using the Color and Color3 types are in non-premultiplied alpha.
//!

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
const Rectangle2 = math.Rectangle2;

pub const LoadedBitmap = extern struct {
    alignment_percentage: Vector2 = Vector2.zero(),
    width_over_height: f32 = 0,

    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
    memory: ?[*]void,
};

pub const EnvironmentMap = extern struct {
    lod: [4]LoadedBitmap,
    z_position: f32,
};

const BilinearSample = struct {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
};

pub const RenderBasis = extern struct {
    position: Vector3,
};

pub const RenderEntityBasis = extern struct {
    basis: *RenderBasis,
    offset: Vector3,
};

pub const RenderEntityBasisResult = extern struct {
    position: Vector2 = Vector2.zero(),
    scale: f32 = 0,
    valid: bool = false,
};

pub const RenderEntryType = enum(u8) {
    RenderEntryClear,
    RenderEntryBitmap,
    RenderEntryRectangle,
    RenderEntryCoordinateSystem,
    RenderEntrySaturation,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
};

pub const RenderEntryClear = extern struct {
    color: Color,
};

pub const RenderEntrySaturation = extern struct {
    level: f32,
};

pub const RenderEntryBitmap = extern struct {
    entity_basis: RenderEntityBasis,
    bitmap: ?*const LoadedBitmap,
    size: Vector2,
    color: Color,
};

pub const RenderEntryRectangle = extern struct {
    entity_basis: RenderEntityBasis,
    dimension: Vector2 = Vector2.zero(),
    color: Color,
};

/// This is only for testing.
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

const RenderGroupCamera = extern struct {
    focal_length: f32,
    distance_above_target: f32,
};

pub const RenderGroup = extern struct {
    game_camera: RenderGroupCamera,
    render_camera: RenderGroupCamera,
    meters_to_pixels: f32,
    monitor_half_dim_in_meters: Vector2,

    global_alpha: f32,

    default_basis: *RenderBasis,

    max_push_buffer_size: u32,
    push_buffer_size: u32,
    push_buffer_base: [*]u8,

    pub fn allocate(
        arena: *shared.MemoryArena,
        max_push_buffer_size: u32,
        resolution_pixels_x: i32,
        resolution_pixels_y: i32,
    ) *RenderGroup {
        var result = arena.pushStruct(RenderGroup);

        result.max_push_buffer_size = max_push_buffer_size;
        result.push_buffer_size = 0;
        result.push_buffer_base = @ptrCast(arena.pushSize(result.max_push_buffer_size, @alignOf(u8)));
        result.default_basis = arena.pushStruct(RenderBasis);
        result.default_basis.position = Vector3.zero();

        const width_of_monitor_in_meters = 0.635;
        result.game_camera.focal_length = 0.6;
        result.game_camera.distance_above_target = 9.0;

        result.render_camera = result.game_camera;
        result.render_camera.distance_above_target = 30.0;

        result.meters_to_pixels = @as(f32, @floatFromInt(resolution_pixels_x)) * width_of_monitor_in_meters;

        const pixels_to_meters = 1.0 / result.meters_to_pixels;
        result.monitor_half_dim_in_meters = Vector2.new(
            0.5 * @as(f32, @floatFromInt(resolution_pixels_x)) * pixels_to_meters,
            0.5 * @as(f32, @floatFromInt(resolution_pixels_y)) * pixels_to_meters,
        );

        result.global_alpha = 1;

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

    fn getRenderEntityBasisPosition(
        self: *RenderGroup,
        entity_basis: *RenderEntityBasis,
        screen_dimension: Vector2,
    ) RenderEntityBasisResult {
        var result = RenderEntityBasisResult{};

        const screen_center = screen_dimension.scaledTo(0.5);
        const entity_base_position = entity_basis.basis.position;

        const distance_to_position_z = self.render_camera.distance_above_target - entity_base_position.z();
        const near_clip_plane = 0.2;

        const raw_xy = entity_base_position.xy().plus(entity_basis.offset.xy()).toVector3(1);

        if (distance_to_position_z > near_clip_plane) {
            const projected_xy = raw_xy.scaledTo((1.0 / distance_to_position_z) * self.render_camera.focal_length);
            result.position = screen_center.plus(projected_xy.xy().scaledTo(self.meters_to_pixels));
            result.scale = projected_xy.z() * self.meters_to_pixels;
            result.valid = true;
        }

        return result;
    }

    // Renderer API.
    pub fn unproject(self: *RenderGroup, projected_xy: Vector2, distance_from_camera: f32) Vector2 {
        return projected_xy.scaledTo(distance_from_camera / self.game_camera.focal_length);
    }

    pub fn getCameraRectangleAtDistance(self: *RenderGroup, distance_from_camera: f32) Rectangle2 {
        const raw_xy = self.unproject(self.monitor_half_dim_in_meters, distance_from_camera);
        return Rectangle2.fromCenterHalfDimension(Vector2.zero(), raw_xy);
    }

    pub fn getCameraRectangleAtTarget(self: *RenderGroup) Rectangle2 {
        return self.getCameraRectangleAtDistance(self.game_camera.distance_above_target);
    }

    pub fn pushClear(self: *RenderGroup, color: Color) void {
        if (self.pushRenderElement(RenderEntryClear)) |entry| {
            entry.color = color;
        }
    }

    pub fn pushSaturation(self: *RenderGroup, level: f32) void {
        if (self.pushRenderElement(RenderEntrySaturation)) |entry| {
            entry.level = level;
        }
    }

    pub fn pushBitmap(
        self: *RenderGroup,
        bitmap: *const LoadedBitmap,
        height: f32,
        offset: Vector3,
        color: Color,
    ) void {
        if (self.pushRenderElement(RenderEntryBitmap)) |entry| {
            entry.bitmap = bitmap;
            entry.entity_basis.basis = self.default_basis;
            entry.size = Vector2.new(height * bitmap.width_over_height, height);
            const alignment = bitmap.alignment_percentage.hadamardProduct(entry.size);
            entry.entity_basis.offset = offset.minus(alignment.toVector3(0));
            entry.color = color.scaledTo(self.global_alpha);
        }
    }

    pub fn pushRectangle(
        self: *RenderGroup,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
    ) void {
        if (self.pushRenderElement(RenderEntryRectangle)) |entry| {
            entry.entity_basis.basis = self.default_basis;
            entry.entity_basis.offset = offset.minus(dimension.scaledTo(0.5).toVector3(0));
            entry.color = color;
            entry.dimension = dimension;
        }
    }

    pub fn pushRectangleOutline(
        self: *RenderGroup,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
    ) void {
        const thickness: f32 = 0.15;
        self.pushRectangle(
            Vector2.new(dimension.x() + thickness, thickness),
            offset.minus(Vector3.new(0, dimension.y() / 2, 0)),
            color,
        );
        self.pushRectangle(
            Vector2.new(dimension.x() + thickness, thickness),
            offset.plus(Vector3.new(0, dimension.y() / 2, 0)),
            color,
        );

        self.pushRectangle(
            Vector2.new(thickness, dimension.y() + thickness),
            offset.minus(Vector3.new(dimension.x() / 2, 0, 0)),
            color,
        );
        self.pushRectangle(
            Vector2.new(thickness, dimension.y() + thickness),
            offset.plus(Vector3.new(dimension.x() / 2, 0, 0)),
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

    pub fn renderTo(self: *RenderGroup, output_target: *LoadedBitmap) void {
        const screen_dimension = Vector2.new(
            @as(f32, @floatFromInt(output_target.width)),
            @as(f32, @floatFromInt(output_target.height)),
        );
        const pixels_to_meters: f32 = 1.0 / self.meters_to_pixels;

        var base_address: u32 = 0;
        while (base_address < self.push_buffer_size) {
            const header: *RenderEntryHeader = @ptrCast(self.push_buffer_base + base_address);
            const alignment: usize = switch (header.type) {
                .RenderEntryClear => @alignOf(RenderEntryClear),
                .RenderEntryBitmap => @alignOf(RenderEntryBitmap),
                .RenderEntryRectangle => @alignOf(RenderEntryRectangle),
                .RenderEntryCoordinateSystem => @alignOf(RenderEntryCoordinateSystem),
                .RenderEntrySaturation => @alignOf(RenderEntrySaturation),
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
                .RenderEntrySaturation => {
                    const entry: *RenderEntrySaturation = @ptrCast(@alignCast(data));

                    changeSaturation(output_target, entry.level);

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryBitmap => {
                    const entry: *RenderEntryBitmap = @ptrCast(@alignCast(data));
                    if (entry.bitmap) |bitmap| {
                        const basis = self.getRenderEntityBasisPosition(&entry.entity_basis, screen_dimension);

                        if (basis.valid) {
                            if (false) {
                                drawBitmap(output_target, bitmap, basis.position.x(), basis.position.y(), entry.color.a());
                            } else {
                                drawRectangleSlowly(
                                    output_target,
                                    basis.position,
                                    Vector2.new(entry.size.x(), 0).scaledTo(basis.scale),
                                    Vector2.new(0, entry.size.y()).scaledTo(basis.scale),
                                    entry.color,
                                    @constCast(bitmap),
                                    null,
                                    undefined,
                                    undefined,
                                    undefined,
                                    pixels_to_meters,
                                );
                            }
                        }
                    }

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryRectangle => {
                    const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));
                    const basis = self.getRenderEntityBasisPosition(&entry.entity_basis, screen_dimension);

                    if (basis.valid) {
                        drawRectangle(
                            output_target,
                            basis.position,
                            basis.position.plus(entry.dimension.scaledTo(basis.scale)),
                            entry.color,
                        );
                    }

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
                        pixels_to_meters,
                    );

                    const color = Color.new(1, 1, 0, 1);
                    const dimension = Vector2.new(2, 2);
                    var position = entry.origin;
                    drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);

                    position = entry.origin.plus(entry.x_axis);
                    drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);

                    position = entry.origin.plus(entry.y_axis);
                    drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);

                    position = max;
                    drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);

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

fn changeSaturation(draw_buffer: *LoadedBitmap, level: f32) void {
    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);

    var y: u32 = 0;
    while (y < draw_buffer.height) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));

        var x: u32 = 0;
        while (x < draw_buffer.width) : (x += 1) {
            const d = Color.unpackColor(dest[0]);
            const average: f32 = (1.0 / 3.0) * (d.r() + d.g() + d.b());
            const delta = Color3.new(d.r() - average, d.g() - average, d.b() - average);
            var result = Color3.splat(average).plus(delta.scaledTo(level)).toColor(d.a());

            dest[0] = result.packColor1();

            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
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
    pixels_to_meters: f32,
) void {
    var color = color_in;
    _ = color.setRGB(color.rgb().scaledTo(color.a()));

    const y_axis_length = y_axis.length();
    const x_axis_length = x_axis.length();
    const normal_x_axis = x_axis.scaledTo(y_axis_length / x_axis_length);
    const normal_y_axis = y_axis.scaledTo(x_axis_length / y_axis_length);
    const normal_z_scale = 0.5 * (x_axis_length + y_axis_length);

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

    const origin_z: f32 = 0.0;
    const origin_y: f32 = (origin.plus(x_axis.scaledTo(0.5).plus(y_axis.scaledTo(0.5)))).y();
    const fixed_cast_y = inv_height_max * origin_y;

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
                // For items that are standing up.
                var screen_space_uv = Vector2.new(
                    inv_width_max * @as(f32, @floatFromInt(x)),
                    fixed_cast_y,
                );
                var z_diff: f32 = pixels_to_meters * (@as(f32, @floatFromInt(y)) - origin_y);

                if (false) {
                    // For items that are lying down on the ground.
                    screen_space_uv = Vector2.new(
                        inv_width_max * @as(f32, @floatFromInt(x)),
                        inv_height_max * @as(f32, @floatFromInt(y)),
                    );
                    z_diff = 0;
                }

                const u = d.dotProduct(x_axis) * inv_x_axis_length_squared;
                const v = d.dotProduct(y_axis) * inv_y_axis_length_squared;

                // std.debug.assert(u >= 0 and u <= 1.0);
                // std.debug.assert(v >= 0 and v <= 1.0);

                const texel_x: f32 = 1 + (u * @as(f32, @floatFromInt(texture.width - 2)));
                const texel_y: f32 = 1 + (v * @as(f32, @floatFromInt(texture.height - 2)));

                const texel_rounded_x: i32 = @intFromFloat(texel_x);
                const texel_rounded_y: i32 = @intFromFloat(texel_y);

                const texel_fraction_x: f32 = texel_x - @as(f32, @floatFromInt(texel_rounded_x));
                const texel_fraction_y: f32 = texel_y - @as(f32, @floatFromInt(texel_rounded_y));

                std.debug.assert(texel_rounded_x >= 0 and texel_rounded_x <= texture.width);
                std.debug.assert(texel_rounded_y >= 0 and texel_rounded_y <= texture.height);

                const texel_sample = bilinearSample(texture, texel_rounded_x, texel_rounded_y);
                var texel = sRGBBilinearBlend(texel_sample, texel_fraction_x, texel_fraction_y);

                if (opt_normal_map) |normal_map| {
                    const normal_sample = bilinearSample(normal_map, texel_rounded_x, texel_rounded_y);
                    const normal_a = Color.unpackColor(normal_sample.a);
                    const normal_b = Color.unpackColor(normal_sample.b);
                    const normal_c = Color.unpackColor(normal_sample.c);
                    const normal_d = Color.unpackColor(normal_sample.d);
                    var normal = normal_a.lerp(normal_b, texel_fraction_x).lerp(
                        normal_c.lerp(normal_d, texel_fraction_x),
                        texel_fraction_y,
                    ).toVector4();

                    normal = unscaleAndBiasNormal(normal);

                    _ = normal.setXY(normal_x_axis.scaledTo(normal.x()).plus(normal_y_axis.scaledTo(normal.y())));
                    _ = normal.setZ(normal.z() * normal_z_scale);
                    _ = normal.setXYZ(normal.xyz().normalized());

                    // The eye vector is always asumed to be 0, 0, 1.
                    var bounce_direction = normal.xyz().scaledTo(2.0 * normal.z());
                    _ = bounce_direction.setZ(bounce_direction.z() - 1.0);
                    _ = bounce_direction.setZ(-bounce_direction.z());

                    const z_position = origin_z + z_diff;
                    var opt_far_map: ?*EnvironmentMap = null;
                    const env_map_blend: f32 = bounce_direction.y();
                    var far_map_blend: f32 = 0;
                    if (env_map_blend < -0.5) {
                        opt_far_map = bottom;
                        far_map_blend = -1.0 - 2.0 * env_map_blend;
                    } else if (env_map_blend > 0.5) {
                        opt_far_map = top;
                        far_map_blend = 2.0 * (env_map_blend - 0.5);
                    }

                    far_map_blend *= far_map_blend;
                    far_map_blend *= far_map_blend;

                    var light_color = Color3.zero();
                    _ = middle;

                    if (opt_far_map) |far_map| {
                        const distance_from_map_in_z = far_map.z_position - z_position;
                        const far_map_color = sampleEnvironmentMap(
                            far_map,
                            screen_space_uv,
                            bounce_direction,
                            normal.w(),
                            distance_from_map_in_z,
                        );
                        light_color = light_color.lerp(far_map_color, far_map_blend);
                    }

                    _ = texel.setRGB(texel.rgb().plus(light_color.scaledTo(texel.a())));

                    if (false) {
                        // Draw bounce direction.
                        _ = texel.setRGB(bounce_direction.scaledTo(0.5).plus(Vector3.splat(0.5)).toColor3());
                        _ = texel.setRGB(texel.rgb().scaledTo(texel.a()));
                    }

                    // texel = Color.new(
                    //     normal.x() * 0.5 + 0.5,
                    //     normal.y() * 0.5 + 0.5,
                    //     normal.z() * 0.5 + 0.5,
                    //     1.0,
                    // );
                }

                texel = texel.hadamardProduct(color);
                _ = texel.setRGB(texel.rgb().clamp01());

                var dest = Color.unpackColor(pixel[0]);
                dest = sRGB255ToLinear1(dest);

                const blended = dest.scaledTo(1.0 - texel.a()).plus(texel);
                const blended255 = linear1ToSRGB255(blended);

                pixel[0] = blended255.packColor1();
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

            dest[0] = result.packColor1();

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
            const color = Color.new(
                inv_rsa * da,
                inv_rsa * dr,
                inv_rsa * dg,
                inv_rsa * db,
            );

            dest[0] = color.packColor1();

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
        source_row = shared.incrementPointer(source_row, bitmap.pitch);
    }
}

pub inline fn sRGB255ToLinear1(color: Color) Color {
    const inverse_255: f32 = 1.0 / 255.0;

    return Color.new(
        math.square(inverse_255 * color.r()),
        math.square(inverse_255 * color.g()),
        math.square(inverse_255 * color.b()),
        inverse_255 * color.a(),
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

inline fn sRGBBilinearBlend(texel_sample: BilinearSample, x: f32, y: f32) Color {
    var texel_a = Color.unpackColor(texel_sample.a);
    var texel_b = Color.unpackColor(texel_sample.b);
    var texel_c = Color.unpackColor(texel_sample.c);
    var texel_d = Color.unpackColor(texel_sample.d);

    texel_a = sRGB255ToLinear1(texel_a);
    texel_b = sRGB255ToLinear1(texel_b);
    texel_c = sRGB255ToLinear1(texel_c);
    texel_d = sRGB255ToLinear1(texel_d);

    return texel_a.lerp(texel_b, x).lerp(
        texel_c.lerp(texel_d, x),
        y,
    );
}

inline fn unscaleAndBiasNormal(normal: Vector4) Vector4 {
    const inv_255: f32 = 1.0 / 255.0;

    return Vector4.new(
        -1.0 + 2.0 * (inv_255 * normal.x()),
        -1.0 + 2.0 * (inv_255 * normal.y()),
        -1.0 + 2.0 * (inv_255 * normal.z()),
        inv_255 * normal.w(),
    );
}

/// Sample from environment map, used when calculating light impact on a normal map.
///
/// * screen_space_uv tells us where the ray is being cast from in normalized screen coordinates.
/// * sample_direction tells us what direction the cast is going.
/// * roughness says which LODs of the map we sample from.
/// * distance_from_map_in_z says how far the map is from the sample point in Z, given in meters.
inline fn sampleEnvironmentMap(
    map: *EnvironmentMap,
    screen_space_uv: Vector2,
    sample_direction: Vector3,
    roughness: f32,
    distance_from_map_in_z: f32,
) Color3 {
    // Pick which LOD to sample from.
    const lod_index: u32 = @intFromFloat(roughness * @as(f32, @floatFromInt(map.lod.len - 1)) + 0.5);
    std.debug.assert(lod_index < map.lod.len);
    var lod = map.lod[lod_index];

    // Calculate the distance to the map and the scaling factor for meters to UVs.
    const uvs_per_meter = 0.1;
    const coefficient = (uvs_per_meter * distance_from_map_in_z) / sample_direction.y();
    const offset = Vector2.new(sample_direction.x(), sample_direction.z()).scaledTo(coefficient);

    // Find the intersection point and clamp it to a valid range.
    var uv = screen_space_uv.plus(offset).clamp01();

    // Bilinear sample.
    const map_x: f32 = (uv.x() * @as(f32, @floatFromInt(lod.width - 2)));
    const map_y: f32 = (uv.y() * @as(f32, @floatFromInt(lod.height - 2)));

    const rounded_x: i32 = @intFromFloat(map_x);
    const rounded_y: i32 = @intFromFloat(map_y);

    const fraction_x: f32 = map_x - @as(f32, @floatFromInt(rounded_x));
    const fraction_y: f32 = map_y - @as(f32, @floatFromInt(rounded_y));

    std.debug.assert(rounded_x >= 0 and rounded_x < lod.width);
    std.debug.assert(rounded_y >= 0 and rounded_y < lod.height);

    if (false) {
        // Debug where we are sampling from on the environment map.
        const test_offset: i32 = @intCast((rounded_x * @sizeOf(u32)) + (rounded_y * lod.pitch));
        const texture_base = shared.incrementPointer(lod.memory.?, test_offset);
        const texel_pointer: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base));
        texel_pointer[0] = Color.new(255, 255, 255, 255).packColor();
    }

    const sample = bilinearSample(&lod, rounded_x, rounded_y);
    const result = sRGBBilinearBlend(sample, fraction_x, fraction_y).rgb();

    return result;
}

inline fn bilinearSample(texture: *LoadedBitmap, x: i32, y: i32) BilinearSample {
    const offset: i32 = @intCast((x * @sizeOf(u32)) + (y * texture.pitch));
    const texture_base = shared.incrementPointer(texture.memory.?, offset);
    const texel_pointer_a: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base));
    const texel_pointer_b: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(
        shared.incrementPointer(texture_base, @sizeOf(u32)),
    ));
    const texel_pointer_c: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(
        shared.incrementPointer(texture_base, texture.pitch),
    ));
    const texel_pointer_d: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(
        shared.incrementPointer(texture_base, @sizeOf(u32) + texture.pitch),
    ));

    return BilinearSample{
        .a = texel_pointer_a[0],
        .b = texel_pointer_b[0],
        .c = texel_pointer_c[0],
        .d = texel_pointer_d[0],
    };
}
