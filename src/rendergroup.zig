//! Software renderer.
//!
//! 1: Everywhere outside the renderer, Y always goes upward, X to the right.
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
const render = @import("render.zig");
const asset = @import("asset.zig");
const intrinsics = @import("intrinsics.zig");
const config = @import("config.zig");
const file_formats = @import("file_formats");
const sort = @import("sort.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

const INTERNAL = shared.INTERNAL;
const SLOW = shared.SLOW;
pub const ENTITY_VISIBLE_PIECE_COUNT = 4096;

var global_config = &@import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector2i = math.Vector2i;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const Rectangle2i = math.Rectangle2i;
const Matrix4x4 = math.Matrix4x4;
const MatrixInverse4x4 = math.MatrixInverse4x4;
const LoadedBitmap = asset.LoadedBitmap;
const LoadedFont = asset.LoadedFont;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const RenderCommands = shared.RenderCommands;
const ArenaPushParams = shared.ArenaPushParams;
const TexturedVertex = shared.TexturedVertex;
const ManualSortKey = render.ManualSortKey;
const SpriteFlag = render.SpriteFlag;

const Vec4f = math.Vec4f;
const Vec4u = math.Vec4u;
const Vec4i = math.Vec4i;

pub const UsedBitmapDim = struct {
    basis_position: Vector3 = undefined,
    size: Vector2 = undefined,
    alignment: Vector2 = undefined,
    position: Vector3 = undefined,
};

pub const EnvironmentMap = extern struct {
    lod: [4]LoadedBitmap,
    z_position: f32,
};

pub const RenderEntryType = enum(u16) {
    RenderEntryTexturedQuads,
    RenderEntryClipRect,
    RenderEntryBlendRenderTarget,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
    clip_rect_index: u16,
    debug_tag: u32,
};

pub const RenderEntryTexturedQuads = extern struct {
    quad_count: u32,
    vertex_array_offset: u32, // Uses 4 vertices per quad.
};

pub const RenderEntryClipRect = extern struct {
    next: ?*RenderEntryClipRect,
    rect: Rectangle2i,
    render_target_index: u32,
    proj: Matrix4x4,
};

pub const TransientClipRect = extern struct {
    render_group: *RenderGroup,
    old_clip_rect: u32,

    pub fn init(render_group: *RenderGroup) TransientClipRect {
        const result: TransientClipRect = .{
            .render_group = render_group,
            .old_clip_rect = render_group.current_clip_rect_index,
        };
        return result;
    }

    pub fn initWith(render_group: *RenderGroup, new_clip_rect_index: u32) TransientClipRect {
        const result: TransientClipRect = .{
            .render_group = render_group,
            .old_clip_rect = render_group.current_clip_rect_index,
        };
        result.render_group.current_clip_rect_index = new_clip_rect_index;
        return result;
    }

    pub fn restore(self: *const TransientClipRect) void {
        self.render_group.current_clip_rect_index = self.old_clip_rect;
    }
};

pub const RenderEntrySaturation = extern struct {
    level: f32,
};

pub const RenderEntryBlendRenderTarget = extern struct {
    source_target_index: u32,
    alpha: f32,
};

pub const CameraTransformFlag = enum(u32) {
    IsOrthographic = 0x1,
    IsDebug = 0x2,
};

pub const ObjectTransform = extern struct {
    upright: bool,
    offset_position: Vector3,
    scale: f32,

    pub fn defaultUpright() ObjectTransform {
        return ObjectTransform{
            .upright = true,
            .offset_position = Vector3.zero(),
            .scale = 1,
        };
    }

    pub fn defaultFlat() ObjectTransform {
        return ObjectTransform{
            .upright = false,
            .offset_position = Vector3.zero(),
            .scale = 1,
        };
    }
};

const PushBufferResult = extern struct {
    header: ?*RenderEntryHeader = null,
};

fn getRenderEntityBasisPosition(
    object_transform: *const ObjectTransform,
    original_position: Vector3,
) Vector3 {
    const position: Vector3 = original_position.xy().toVector3(0).plus(object_transform.offset_position);
    return position;
}

pub const RenderGroup = extern struct {
    assets: *asset.Assets,

    screen_dimensions: Vector2,
    debug_tag: u32,

    missing_resource_count: u32,

    last_clip_x: i32,
    last_clip_y: i32,
    last_clip_w: i32,
    last_clip_h: i32,
    current_clip_rect_index: u32,
    last_render_target: u32,

    camera_position: Vector3,
    camera_x: Vector3,
    camera_y: Vector3,
    camera_z: Vector3,
    last_proj: MatrixInverse4x4,

    generation_id: u32,
    commands: *RenderCommands,

    current_quads: ?*RenderEntryTexturedQuads,

    pub fn begin(
        assets: *asset.Assets,
        commands: *RenderCommands,
        generation_id: u32,
        pixel_width: i32,
        pixel_height: i32,
    ) RenderGroup {
        var result: RenderGroup = .{
            .assets = assets,
            .screen_dimensions = .newI(pixel_width, pixel_height),
            .debug_tag = undefined,
            .missing_resource_count = 0,
            .last_clip_x = 0,
            .last_clip_y = 0,
            .last_clip_w = 0,
            .last_clip_h = 0,
            .camera_position = .zero(),
            .camera_x = .zero(),
            .camera_y = .zero(),
            .camera_z = .zero(),
            .last_proj = .{},
            .last_render_target = 0,
            .current_clip_rect_index = 0,
            .generation_id = generation_id,
            .commands = commands,
            .current_quads = undefined,
        };

        var i: MatrixInverse4x4 = .identity();
        result.current_clip_rect_index = result.pushSetup(
            0,
            0,
            @intCast(pixel_width),
            @intCast(pixel_height),
            0,
            &i,
        );

        return result;
    }

    pub fn end(self: *RenderGroup) void {
        _ = self;

        // TODO:
        // self.commands.missing_resource_count += self.missing_resource_count
    }

    pub fn allResourcesPresent(self: *RenderGroup) bool {
        return self.missing_resource_count == 0;
    }

    fn pushBuffer(self: *RenderGroup, data_size: u32) PushBufferResult {
        var result: PushBufferResult = .{};
        const commands: *RenderCommands = self.commands;

        const push_buffer_end: [*]u8 = commands.push_buffer_base + commands.max_push_buffer_size;
        if ((@intFromPtr(commands.push_buffer_data_at) + data_size) <= @intFromPtr(push_buffer_end)) {
            result.header = @ptrCast(@alignCast(commands.push_buffer_data_at));
            commands.push_buffer_data_at += data_size;
        } else {
            unreachable;
        }

        return result;
    }

    pub fn pushSortBarrier(self: *RenderGroup, turn_off_sorting: bool) void {
        _ = self;
        _ = turn_off_sorting;

        // TODO: Do we want the sort barrier again?
    }

    fn pushRenderElement(self: *RenderGroup, comptime T: type) ?*T {
        // TimedBlock.beginFunction(@src(), .PushRenderElement);
        // defer TimedBlock.endFunction(@src(), .PushRenderElement);

        // This depends on the name of this file, if the file name changes the magic number may need to be adjusted.
        const entry_type: RenderEntryType = @field(RenderEntryType, @typeName(T)[12..]);
        return @ptrCast(@alignCast(self.pushRenderElement_(@sizeOf(T), entry_type, @alignOf(T))));
    }

    fn pushRenderElement_(
        self: *RenderGroup,
        in_size: u32,
        entry_type: RenderEntryType,
        comptime alignment: u32,
    ) ?*anyopaque {
        var result: ?*anyopaque = null;

        const size = in_size + @sizeOf(RenderEntryHeader);
        const data_address = @intFromPtr(self.commands.push_buffer_data_at) + @sizeOf(RenderEntryHeader);
        const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        const aligned_offset = aligned_address - data_address;
        const aligned_size: u32 = @intCast(size + aligned_offset);
        const push: PushBufferResult = self.pushBuffer(aligned_size);

        if (push.header) |header| {
            header.type = entry_type;
            header.clip_rect_index = shared.safeTruncateUInt32ToUInt16(self.current_clip_rect_index);
            result = @ptrFromInt(@intFromPtr(header) + @sizeOf(RenderEntryHeader) + aligned_offset);

            if (INTERNAL) {
                header.debug_tag = self.debug_tag;
            }
        } else {
            unreachable;
        }

        self.current_quads = null;

        return result;
    }

    // Renderer API.
    pub fn unproject(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        pixels_xy: Vector2,
        world_distance_from_camera_z: f32,
    ) Vector3 {
        var probe_z: Vector4 = .new(0, 0, world_distance_from_camera_z, 1);
        probe_z = self.last_proj.forward.timesV4(probe_z);
        const clip_z: f32 = probe_z.z() / probe_z.w();

        const screen_center: Vector2 = self.screen_dimensions.scaledTo(0.5);

        var clip_space_xy: Vector2 = pixels_xy.minus(screen_center);
        _ = clip_space_xy.setX(clip_space_xy.x() * 2 / self.screen_dimensions.x());
        _ = clip_space_xy.setY(clip_space_xy.y() * 2 / self.screen_dimensions.y());

        const clip: Vector3 = clip_space_xy.toVector3(clip_z);

        const world_position: Vector3 = self.last_proj.inverse.timesV(clip);
        const object_position: Vector3 = world_position.minus(object_transform.offset_position);

        return object_position;
    }

    pub fn getCameraRectangleAtDistance(self: *RenderGroup, distance_from_camera: f32) Rectangle3 {
        var transform: ObjectTransform = .defaultFlat();
        _ = transform.offset_position.setZ(-distance_from_camera);

        const min_corner = self.unproject(&transform, .zero(), distance_from_camera);
        const max_corner = self.unproject(&transform, self.screen_dimensions, distance_from_camera);

        return Rectangle3.fromMinMax(min_corner, max_corner);
    }

    pub fn getCameraRectangleAtTarget(self: *RenderGroup) Rectangle3 {
        const z: f32 = 8;
        return self.getCameraRectangleAtDistance(z);
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

    pub fn pushClear(self: *RenderGroup, color: Color) void {
        self.commands.clear_color = color;
    }

    pub fn pushSaturation(self: *RenderGroup, level: f32) void {
        if (self.pushRenderElement(RenderEntrySaturation)) |entry| {
            entry.level = level;
        }
    }

    pub fn getBitmapDim(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        bitmap: *const LoadedBitmap,
        height: f32,
        offset: Vector3,
        align_coefficient: f32,
        opt_x_axis: ?Vector2,
        opt_y_axis: ?Vector2,
    ) UsedBitmapDim {
        _ = self;

        const x_axis: Vector2 = opt_x_axis orelse Vector2.new(1, 0);
        const y_axis: Vector2 = opt_y_axis orelse Vector2.new(0, 1);
        var dim = UsedBitmapDim{};

        dim.size = Vector2.new(height * bitmap.width_over_height, height);
        dim.alignment = bitmap.alignment_percentage.hadamardProduct(dim.size).scaledTo(align_coefficient);
        _ = dim.position.setZ(offset.z());
        _ = dim.position.setXY(
            offset.xy().minus(x_axis.scaledTo(dim.alignment.x())).minus(y_axis.scaledTo(dim.alignment.y())),
        );
        dim.basis_position = getRenderEntityBasisPosition(object_transform, dim.position);

        return dim;
    }

    fn storeColor(source: Color) Color {
        var dest: Color = .white();

        _ = dest.setA(source.a());
        _ = dest.setR(dest.a() * source.r());
        _ = dest.setG(dest.a() * source.g());
        _ = dest.setB(dest.a() * source.b());

        return dest;
    }

    fn getCurrentQuads(self: *RenderGroup, quad_count: u32) ?*RenderEntryTexturedQuads {
        if (self.current_quads == null) {
            self.current_quads = @ptrCast(@alignCast(
                self.pushRenderElement_(
                    @sizeOf(RenderEntryTexturedQuads),
                    .RenderEntryTexturedQuads,
                    @alignOf(RenderEntryTexturedQuads),
                ),
            ));
            self.current_quads.?.quad_count = 0;
            self.current_quads.?.vertex_array_offset = self.commands.vertex_count;
        }

        var result = self.current_quads;
        if ((self.commands.vertex_count + 4 * quad_count) > self.commands.max_vertex_count) {
            result = null;
        }

        return result;
    }

    fn pushQuad(
        self: *RenderGroup,
        bitmap: ?*LoadedBitmap,
        p0: Vector4,
        uv0: Vector2,
        c0: u32,
        p1: Vector4,
        uv1: Vector2,
        c1: u32,
        p2: Vector4,
        uv2: Vector2,
        c2: u32,
        p3: Vector4,
        uv3: Vector2,
        c3: u32,
    ) void {
        const entry: ?*RenderEntryTexturedQuads = self.current_quads;
        std.debug.assert(self.current_quads != null);
        std.debug.assert(bitmap != null);

        entry.?.quad_count += 1;

        self.commands.quad_bitmaps[self.commands.vertex_count >> 2] = bitmap;
        var vert: [*]TexturedVertex = self.commands.vertex_array + self.commands.vertex_count;
        self.commands.vertex_count += 4;

        vert[0].position = p0;
        vert[0].uv = uv0;
        vert[0].color = c0;

        vert[1].position = p3;
        vert[1].uv = uv3;
        vert[1].color = c3;

        vert[2].position = p1;
        vert[2].uv = uv1;
        vert[2].color = c1;

        vert[3].position = p2;
        vert[3].uv = uv2;
        vert[3].color = c2;
    }

    fn pushQuadUnpackedColors(
        self: *RenderGroup,
        bitmap: ?*LoadedBitmap,
        p0: Vector4,
        uv0: Vector2,
        c0: Color,
        p1: Vector4,
        uv1: Vector2,
        c1: Color,
        p2: Vector4,
        uv2: Vector2,
        c2: Color,
        p3: Vector4,
        uv3: Vector2,
        c3: Color,
    ) void {
        self.pushQuad(
            bitmap,
            p0,
            uv0,
            c0.scaledTo(255).packColorRGBA(),
            p1,
            uv1,
            c1.scaledTo(255).packColorRGBA(),
            p2,
            uv2,
            c2.scaledTo(255).packColorRGBA(),
            p3,
            uv3,
            c3.scaledTo(255).packColorRGBA(),
        );
    }

    pub fn pushBitmap(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        bitmap: *LoadedBitmap,
        height: f32,
        offset: Vector3,
        color: Color,
        align_coefficient: f32,
        opt_x_axis: ?Vector2,
        opt_y_axis: ?Vector2,
    ) void {
        if (bitmap.width > 0 and bitmap.height > 0) {
            const x_axis2: Vector2 = opt_x_axis orelse Vector2.new(1, 0);
            const y_axis2: Vector2 = opt_y_axis orelse Vector2.new(0, 1);
            const dim = self.getBitmapDim(
                object_transform,
                bitmap,
                height,
                offset,
                align_coefficient,
                x_axis2,
                y_axis2,
            );

            const size: Vector2 = dim.size;
            if (self.getCurrentQuads(1)) |entry| {
                entry.quad_count += 1;

                const min_position: Vector3 = dim.basis_position;
                const z_bias: f32 = height;
                const premultiplied_color: Color = storeColor(color);
                var x_axis: Vector3 = x_axis2.toVector3(0).scaledTo(size.x());
                var y_axis: Vector3 = y_axis2.toVector3(0).scaledTo(size.y());

                if (object_transform.upright) {
                    x_axis =
                        self.camera_x.scaledTo(x_axis2.x()).plus(self.camera_y.scaledTo(x_axis2.y())).scaledTo(size.x());
                    y_axis =
                        self.camera_x.scaledTo(y_axis2.x()).plus(self.camera_y.scaledTo(y_axis2.y())).scaledTo(size.y());
                }

                const one_texel_u: f32 = 1 / @as(f32, @floatFromInt(bitmap.width));
                const one_texel_v: f32 = 1 / @as(f32, @floatFromInt(bitmap.height));
                const min_uv = Vector2.new(one_texel_u, one_texel_v);
                const max_uv = Vector2.new(1 - one_texel_u, 1 - one_texel_v);

                const vertex_color: u32 = premultiplied_color.scaledTo(255).packColorRGBA();

                const min_x_min_y: Vector4 = min_position.toVector4(0);
                const min_x_max_y: Vector4 = min_position.plus(y_axis).toVector4(z_bias);
                const max_x_min_y: Vector4 = min_position.plus(x_axis).toVector4(0);
                const max_x_max_y: Vector4 = min_position.plus(x_axis).plus(y_axis).toVector4(z_bias);

                self.pushQuad(
                    bitmap,
                    min_x_min_y,
                    .new(min_uv.x(), min_uv.y()),
                    vertex_color,
                    max_x_min_y,
                    .new(max_uv.x(), min_uv.y()),
                    vertex_color,
                    max_x_max_y,
                    .new(max_uv.x(), max_uv.y()),
                    vertex_color,
                    min_x_max_y,
                    .new(min_uv.x(), max_uv.y()),
                    vertex_color,
                );
            }
        }
    }

    pub fn pushBitmapId(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        opt_id: ?file_formats.BitmapId,
        height: f32,
        offset: Vector3,
        color: Color,
        opt_align_coefficient: ?f32,
        opt_x_axis: ?Vector2,
        opt_y_axis: ?Vector2,
    ) void {
        const align_coefficient: f32 = opt_align_coefficient orelse 1;
        if (opt_id) |id| {
            if (self.assets.getBitmap(id, self.generation_id)) |bitmap| {
                self.pushBitmap(object_transform, bitmap, height, offset, color, align_coefficient, opt_x_axis, opt_y_axis);
            } else {
                self.assets.loadBitmap(id, false);
                self.missing_resource_count += 1;
            }
        }
    }

    pub fn pushCubeBitmapId(
        self: *RenderGroup,
        opt_id: ?file_formats.BitmapId,
        position: Vector3,
        radius: f32,
        height: f32,
        color: Color,
    ) void {
        if (opt_id) |id| {
            if (self.assets.getBitmap(id, self.generation_id)) |bitmap| {
                self.pushCube(
                    bitmap,
                    position,
                    radius,
                    height,
                    color,
                );
            } else {
                self.assets.loadBitmap(id, false);
                self.missing_resource_count += 1;
            }
        }
    }

    pub fn pushCube(
        self: *RenderGroup,
        bitmap: ?*LoadedBitmap,
        position: Vector3,
        radius: f32,
        height: f32,
        color: Color,
    ) void {
        if (self.getCurrentQuads(6) != null) {
            const nx: f32 = position.x() - radius;
            const px: f32 = position.x() + radius;
            const ny: f32 = position.y() - radius;
            const py: f32 = position.y() + radius;
            const nz: f32 = position.z() - height;
            const pz: f32 = position.z();

            const p0: Vector4 = .new(nx, ny, pz, 0);
            const p1: Vector4 = .new(px, ny, pz, 0);
            const p2: Vector4 = .new(px, py, pz, 0);
            const p3: Vector4 = .new(nx, py, pz, 0);
            const p4: Vector4 = .new(nx, ny, nz, 0);
            const p5: Vector4 = .new(px, ny, nz, 0);
            const p6: Vector4 = .new(px, py, nz, 0);
            const p7: Vector4 = .new(nx, py, nz, 0);

            const t0: Vector2 = .new(0, 0);
            const t1: Vector2 = .new(1, 0);
            const t2: Vector2 = .new(1, 1);
            const t3: Vector2 = .new(0, 1);

            const top_color: Color = storeColor(color);
            const bottom_color: Color = .new(0, 0, 0, top_color.a());
            const ct: Color = top_color.rgb().scaledTo(0.75).toColor(top_color.a());
            const cb: Color = top_color.rgb().scaledTo(0.25).toColor(top_color.a());

            self.pushQuadUnpackedColors(
                bitmap,
                p0,
                t0,
                top_color,
                p1,
                t1,
                top_color,
                p2,
                t2,
                top_color,
                p3,
                t3,
                top_color,
            );
            self.pushQuadUnpackedColors(
                bitmap,
                p7,
                t0,
                bottom_color,
                p6,
                t1,
                bottom_color,
                p5,
                t2,
                bottom_color,
                p4,
                t3,
                bottom_color,
            );
            self.pushQuadUnpackedColors(
                bitmap,
                p4,
                t0,
                cb,
                p5,
                t1,
                cb,
                p1,
                t2,
                ct,
                p0,
                t3,
                ct,
            );
            self.pushQuadUnpackedColors(
                bitmap,
                p2,
                t0,
                ct,
                p6,
                t1,
                cb,
                p7,
                t2,
                cb,
                p3,
                t3,
                ct,
            );
            self.pushQuadUnpackedColors(
                bitmap,
                p1,
                t0,
                ct,
                p5,
                t1,
                cb,
                p6,
                t2,
                cb,
                p2,
                t3,
                ct,
            );
            self.pushQuadUnpackedColors(
                bitmap,
                p7,
                t0,
                cb,
                p4,
                t1,
                cb,
                p0,
                t2,
                ct,
                p3,
                t3,
                ct,
            );
        }
    }

    pub fn pushFont(
        self: *RenderGroup,
        opt_id: ?file_formats.FontId,
    ) ?*LoadedFont {
        var opt_font: ?*LoadedFont = null;

        if (opt_id) |id| {
            opt_font = self.assets.getFont(id, self.generation_id);

            if (opt_font == null) {
                self.assets.loadFont(id, false);
                self.missing_resource_count += 1;
            }
        }

        return opt_font;
    }

    pub fn pushRectangle(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
    ) void {
        const position = offset.minus(dimension.scaledTo(0.5).toVector3(0));
        const basis_position = getRenderEntityBasisPosition(object_transform, position);

        if (self.getCurrentQuads(6) != null) {
            const premultiplied_color: Color = storeColor(color);
            const packed_color: u32 = premultiplied_color.scaledTo(255).packColorRGBA();

            const min_position: Vector3 = basis_position;
            const max_position: Vector3 = basis_position.plus(dimension.toVector3(0));

            const z: f32 = min_position.z();
            const min_uv: Vector2 = .splat(0);
            const max_uv: Vector2 = .splat(1);

            self.pushQuad(
                self.commands.white_bitmap,
                .new(min_position.x(), min_position.y(), z, 0),
                .new(min_uv.x(), min_uv.y()),
                packed_color,
                .new(max_position.x(), min_position.y(), z, 0),
                .new(max_uv.x(), min_uv.y()),
                packed_color,
                .new(max_position.x(), max_position.y(), z, 0),
                .new(max_uv.x(), max_uv.y()),
                packed_color,
                .new(min_position.x(), max_position.y(), z, 0),
                .new(min_uv.x(), max_uv.y()),
                packed_color,
            );
        }
    }

    pub fn pushRectangle2(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        rectangle: Rectangle2,
        z: f32,
        color: Color,
    ) void {
        self.pushRectangle(
            object_transform,
            rectangle.getDimension(),
            rectangle.toRectangle3(z, z).getCenter(),
            color,
        );
    }

    pub fn pushRectangle2Outline(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        rectangle: Rectangle2,
        z: f32,
        color: Color,
        thickness: f32,
    ) void {
        self.pushRectangleOutline(
            object_transform,
            rectangle.getDimension(),
            rectangle.toRectangle3(z, z).getCenter(),
            color,
            thickness,
        );
    }

    pub fn pushRectangleOutline(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
        thickness: f32,
    ) void {
        self.pushRectangle(
            object_transform,
            Vector2.new(dimension.x() - thickness - 0.01, thickness),
            offset.minus(Vector3.new(0, 0.5 * dimension.y(), 0)),
            color,
        );
        self.pushRectangle(
            object_transform,
            Vector2.new(dimension.x() - thickness - 0.01, thickness),
            offset.plus(Vector3.new(0, 0.5 * dimension.y(), 0)),
            color,
        );

        self.pushRectangle(
            object_transform,
            Vector2.new(thickness, dimension.y() + thickness),
            offset.minus(Vector3.new(0.5 * dimension.x(), 0, 0)),
            color,
        );
        self.pushRectangle(
            object_transform,
            Vector2.new(thickness, dimension.y() + thickness),
            offset.plus(Vector3.new(0.5 * dimension.x(), 0, 0)),
            color,
        );
    }

    pub fn pushSetup(
        self: *RenderGroup,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        render_target_index: u32,
        proj: *MatrixInverse4x4,
    ) u32 {
        var result: u32 = 0;

        self.last_clip_x = x;
        self.last_clip_y = y;
        self.last_clip_w = w;
        self.last_clip_h = h;
        self.last_render_target = render_target_index;
        self.last_proj = proj.*;

        if (self.pushRenderElement(RenderEntryClipRect)) |rect| {
            result = self.commands.clip_rect_count;
            self.commands.clip_rect_count += 1;

            if (self.commands.last_clip_rect != null) {
                self.commands.last_clip_rect.?.next = rect;
                self.commands.last_clip_rect = rect;
            } else {
                self.commands.last_clip_rect = rect;
                self.commands.first_clip_rect = rect;
            }
            rect.next = null;

            rect.rect = Rectangle2i.new(x, y, x + w, y + h);
            rect.proj = proj.forward;

            rect.render_target_index = render_target_index;
            if (self.commands.max_render_target_index < render_target_index) {
                self.commands.max_render_target_index = render_target_index;
            }
        }

        return result;
    }

    pub fn pushClipRectByTransform(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        dimension: Vector2,
        offset: Vector3,
    ) u32 {
        var result: u32 = 0;
        const modified_position = offset.minus(dimension.scaledTo(0.5).toVector3(0));

        const position = getRenderEntityBasisPosition(object_transform, modified_position);
        const basis_dimension: Vector2 = dimension;
        result = self.pushSetup(
            intrinsics.roundReal32ToInt32(position.x()),
            intrinsics.roundReal32ToInt32(position.y()),
            intrinsics.roundReal32ToInt32(basis_dimension.x()),
            intrinsics.roundReal32ToInt32(basis_dimension.y()),
            self.last_render_target,
            &self.last_proj,
        );

        return result;
    }

    pub fn pushClipRectByRectangle(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        rectangle: Rectangle2,
        z: f32,
    ) u32 {
        return self.pushClipRectByTransform(
            object_transform,
            rectangle.getDimension(),
            rectangle.getCenter().toVector3(z),
        );
    }

    pub fn pushRenderTarget(self: *RenderGroup, render_target_index: u31) u32 {
        self.current_clip_rect_index = self.pushSetup(
            self.last_clip_x,
            self.last_clip_y,
            self.last_clip_w,
            self.last_clip_h,
            render_target_index,
            &self.last_proj,
        );
        return 0;
    }

    pub fn setCameraTransformToIdentity(
        self: *RenderGroup,
        focal_length: f32,
        flags: u32,
    ) void {
        self.setCameraTransform(focal_length, .new(1, 0, 0), .new(0, 1, 0), .new(0, 0, 1), .zero(), flags);
    }

    pub fn setCameraTransform(
        self: *RenderGroup,
        focal_length: f32,
        camera_x: Vector3,
        camera_y: Vector3,
        camera_z: Vector3,
        camera_position: Vector3,
        flags: u32,
    ) void {
        const is_ortho: bool = (flags & @intFromEnum(CameraTransformFlag.IsOrthographic)) != 0;
        const is_debug: bool = (flags & @intFromEnum(CameraTransformFlag.IsDebug)) != 0;
        const b: f32 = math.safeRatio1(
            @as(f32, @floatFromInt(self.commands.width)),
            @as(f32, @floatFromInt(self.commands.height)),
        );

        var proj: MatrixInverse4x4 = .{};
        if (is_ortho) {
            proj = .orthographicProjection(b);
        } else {
            proj = .perspectiveProjection(b, focal_length);
        }

        if (!is_debug) {
            self.camera_x = camera_x;
            self.camera_y = camera_y;
            self.camera_z = camera_z;
            self.camera_position = camera_position;
        }
        const camera_c: MatrixInverse4x4 = .cameraTransform(camera_x, camera_y, camera_z, camera_position);
        var composite: MatrixInverse4x4 = .{
            .forward = proj.forward.times(camera_c.forward),
            .inverse = camera_c.inverse.times(proj.inverse),
        };

        if (SLOW) {
            const identity: Matrix4x4 = composite.inverse.times(composite.forward);
            _ = identity;
        }

        self.current_clip_rect_index = self.pushSetup(
            self.last_clip_x,
            self.last_clip_y,
            self.last_clip_w,
            self.last_clip_h,
            self.last_render_target,
            &composite,
        );
    }

    pub fn pushBlendRenderTarget(self: *RenderGroup, alpha: f32, source_render_target_index: u32) void {
        self.pushSortBarrier(false);
        if (self.pushRenderElement(RenderEntryBlendRenderTarget)) |blend| {
            blend.alpha = alpha;
            blend.source_target_index = source_render_target_index;
        }
        self.pushSortBarrier(false);
    }
};
