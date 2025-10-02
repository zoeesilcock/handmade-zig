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
const random = @import("random.zig");
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
    RenderEntryDepthClear,
    RenderEntryBeginPeels,
    RenderEntryEndPeels,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
    debug_tag: u32,
};

pub const RenderEntryTexturedQuads = extern struct {
    setup: RenderSetup,
    quad_count: u32,
    vertex_array_offset: u32, // Uses 4 vertices per quad.
};

pub const RenderSetup = extern struct {
    clip_rect: Rectangle2i = .zero(),
    render_target_index: u32 = 0,
    projection: Matrix4x4 = .identity(),
    camera_position: Vector3 = .zero(),
    fog_direction: Vector3 = .zero(),
    fog_color: Color3 = .white(),
    fog_start_distance: f32 = 0,
    fog_end_distance: f32 = 0,
    clip_alpha_start_distance: f32 = 0,
    clip_alpha_end_distance: f32 = 0,
    debug_light_position: Vector3 = .zero(),
};

pub const TransientClipRect = extern struct {
    render_group: *RenderGroup,
    old_clip_rect: Rectangle2i,

    pub fn init(render_group: *RenderGroup) TransientClipRect {
        const result: TransientClipRect = .{
            .render_group = render_group,
            .old_clip_rect = render_group.last_setup.clip_rect,
        };
        return result;
    }

    pub fn initWith(render_group: *RenderGroup, new_clip_rect: Rectangle2i) TransientClipRect {
        const result: TransientClipRect = .{
            .render_group = render_group,
            .old_clip_rect = render_group.last_setup.clip_rect,
        };
        var new_setup: RenderSetup = render_group.last_setup;
        new_setup.clip_rect = new_clip_rect;
        render_group.pushSetup(&new_setup);
        return result;
    }

    pub fn restore(self: *const TransientClipRect) void {
        var new_setup: RenderSetup = self.render_group.last_setup;
        new_setup.clip_rect = self.old_clip_rect;
        self.render_group.pushSetup(&new_setup);
    }
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

const RenderTransform = extern struct {
    position: Vector3 = .zero(),
    x: Vector3 = .zero(),
    y: Vector3 = .zero(),
    z: Vector3 = .zero(),
    projection: MatrixInverse4x4 = .{},
};

pub const RenderGroup = extern struct {
    assets: *asset.Assets,

    screen_dimensions: Vector2,
    debug_tag: u32,

    missing_resource_count: u32,

    last_setup: RenderSetup = .{},
    game_transform: RenderTransform = .{},
    debug_transform: RenderTransform = .{},

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
            .generation_id = generation_id,
            .commands = commands,
            .current_quads = undefined,
        };

        var initial_setup: RenderSetup = .{
            .fog_start_distance = 0,
            .fog_end_distance = 1,
            .clip_alpha_start_distance = 0,
            .clip_alpha_end_distance = 1,
            .fog_color = .new(math.square(0.15), math.square(0.15), math.square(0.15)),
            .clip_rect = .fromMinDimension(.zero(), .new(pixel_width, pixel_height)),
        };
        result.pushSetup(&initial_setup);

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
        render_transform: *RenderTransform,
        pixels_xy: Vector2,
        world_distance_from_camera_z: f32,
    ) Vector3 {
        var probe_z: Vector4 =
            render_transform.position.minus(render_transform.z.scaledTo(world_distance_from_camera_z)).toVector4(1);
        probe_z = render_transform.projection.forward.timesV4(probe_z);
        const clip_z: f32 = probe_z.z() / probe_z.w();

        const screen_center: Vector2 = self.screen_dimensions.scaledTo(0.5);

        var clip_space_xy: Vector2 = pixels_xy.minus(screen_center);
        _ = clip_space_xy.setX(clip_space_xy.x() * 2 / self.screen_dimensions.x());
        _ = clip_space_xy.setY(clip_space_xy.y() * 2 / self.screen_dimensions.y());

        const clip: Vector3 = clip_space_xy.toVector3(clip_z);
        const world_position: Vector3 = render_transform.projection.inverse.timesV(clip);

        return world_position;
    }

    // const object_position: Vector3 = world_position.minus(object_transform.offset_position);

    pub fn getCameraRectangleAtDistance(self: *RenderGroup, distance_from_camera: f32) Rectangle3 {
        var transform: ObjectTransform = .defaultFlat();
        _ = transform.offset_position.setZ(-distance_from_camera);

        const min_corner = self.unproject(&self.game_transform, .zero(), distance_from_camera);
        const max_corner = self.unproject(&self.game_transform, self.screen_dimensions, distance_from_camera);

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

    pub fn beginDepthPeel(self: *RenderGroup) void {
        _ = self.pushRenderElement_(
            0,
            .RenderEntryBeginPeels,
            @alignOf(u32),
        );
    }

    pub fn endDepthPeel(self: *RenderGroup) void {
        _ = self.pushRenderElement_(
            0,
            .RenderEntryEndPeels,
            @alignOf(u32),
        );
    }

    pub fn pushDepthClear(self: *RenderGroup) void {
        _ = self.pushRenderElement_(
            0,
            .RenderEntryDepthClear,
            @alignOf(u32),
        );
    }

    pub fn pushClear(self: *RenderGroup, color: Color) void {
        if (true) {
            self.commands.clear_color = .new(
                math.square(color.r()),
                math.square(color.g()),
                math.square(color.b()),
                color.a(),
            );
            self.last_setup.fog_color = .new(math.square(color.r()), math.square(color.g()), math.square(color.b()));
        } else {
            self.commands.clear_color = color;
            self.last_setup.fog_color = .new(color.r(), color.g(), color.b());
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

        if (false) {
            dim.size = Vector2.new(height * bitmap.width_over_height, height);
            dim.alignment = bitmap.alignment_percentage.hadamardProduct(dim.size).scaledTo(align_coefficient);
            _ = dim.position.setZ(offset.z());
            _ = dim.position.setXY(
                offset.xy().minus(x_axis.scaledTo(dim.alignment.x())).minus(y_axis.scaledTo(dim.alignment.y())),
            );
            dim.basis_position = getRenderEntityBasisPosition(object_transform, dim.position);
        } else {
            dim.size = .new(
                height * bitmap.width_over_height,
                height,
            );
            dim.alignment = .new(
                align_coefficient * bitmap.alignment_percentage.x() * dim.size.x(),
                align_coefficient * bitmap.alignment_percentage.y() * dim.size.y(),
            );
            dim.position = .new(
                offset.x() - dim.alignment.x() * x_axis.x() - dim.alignment.y() * y_axis.x(),
                offset.y() - dim.alignment.y() * x_axis.y() - dim.alignment.y() * y_axis.y(),
                offset.z(),
            );
            dim.basis_position = .new(
                object_transform.offset_position.x() + dim.position.x(),
                object_transform.offset_position.y() + dim.position.y(),
                object_transform.offset_position.z() + dim.position.z(),
            );
        }

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
            self.current_quads.?.setup = self.last_setup;
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
        opt_emission: ?f32,
    ) void {
        const emission = opt_emission orelse 0;
        const entry: ?*RenderEntryTexturedQuads = self.current_quads;
        std.debug.assert(entry != null);

        entry.?.quad_count += 1;

        self.commands.quad_bitmaps[self.commands.vertex_count >> 2] = bitmap;
        var vert: [*]TexturedVertex = self.commands.vertex_array + self.commands.vertex_count;
        self.commands.vertex_count += 4;

        var e10 = p1.minus(p0);
        _ = e10.setZ(e10.z() + e10.w());
        var e20 = p2.minus(p0);
        _ = e20.setZ(e20.z() + e20.w());

        const normal_direction: Vector3 = e10.xyz().crossProduct(e20.xyz());
        const normal = normal_direction.normalizeOrZero();
        const n0: Vector3 = normal;
        const n1: Vector3 = normal;
        const n2: Vector3 = normal;
        const n3: Vector3 = normal;

        vert[0].position = p3;
        vert[0].normal = n3;
        vert[0].uv = uv3;
        vert[0].color = c3;
        vert[0].emission = emission;

        vert[1].position = p0;
        vert[1].normal = n0;
        vert[1].uv = uv0;
        vert[1].color = c0;
        vert[1].emission = emission;

        vert[2].position = p2;
        vert[2].normal = n2;
        vert[2].uv = uv2;
        vert[2].color = c2;
        vert[2].emission = emission;

        vert[3].position = p1;
        vert[3].normal = n1;
        vert[3].uv = uv1;
        vert[3].color = c1;
        vert[3].emission = emission;
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
        opt_emission: ?f32,
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
            opt_emission,
        );
    }

    pub fn pushLineSegment(
        self: *RenderGroup,
        bitmap: ?*LoadedBitmap,
        from_position: Vector3,
        from_color: Color,
        to_position: Vector3,
        to_color: Color,
        thickness: f32,
    ) void {
        const from_color_packed: u32 = from_color.scaledTo(255).packColorRGBA();
        const to_color_packed: u32 = to_color.scaledTo(255).packColorRGBA();

        var line: Vector3 = to_position.minus(from_position);
        const camera_z: Vector3 = self.debug_transform.z;
        line = line.minus(camera_z.scaledTo(camera_z.dotProduct(line)));
        var line_perp: Vector3 = camera_z.crossProduct(line);
        const line_perp_length: f32 = line_perp.length();

        // if (line_perp_length < thickness) {
        //     line_perp = self.debug_transform.y;
        // } else {
        //     line_perp = line_perp.dividedByF(line_perp_length);
        // }

        line_perp = line_perp.dividedByF(line_perp_length);
        line_perp = line_perp.scaledTo(thickness);

        const z_bias: f32 = 0.01;
        const p0: Vector4 = from_position.minus(line_perp).toVector4(z_bias);
        const uv0: Vector2 = .new(0, 0);
        const c0: u32 = from_color_packed;
        const p1: Vector4 = to_position.minus(line_perp).toVector4(z_bias);
        const uv1: Vector2 = .new(1, 0);
        const c1: u32 = to_color_packed;
        const p2: Vector4 = to_position.plus(line_perp).toVector4(z_bias);
        const uv2: Vector2 = .new(1, 1);
        const c2: u32 = to_color_packed;
        const p3: Vector4 = from_position.plus(line_perp).toVector4(z_bias);
        const uv3: Vector2 = .new(0, 1);
        const c3: u32 = from_color_packed;

        self.pushQuad(
            bitmap,
            p0,
            uv0,
            c0,
            p1,
            uv1,
            c1,
            p2,
            uv2,
            c2,
            p3,
            uv3,
            c3,
            null,
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
                var z_bias: f32 = 0;
                const premultiplied_color: Color = storeColor(color);
                var x_axis: Vector3 = x_axis2.toVector3(0).scaledTo(size.x());
                var y_axis: Vector3 = y_axis2.toVector3(0).scaledTo(size.y());

                if (object_transform.upright) {
                    z_bias = 0.25 * height;
                    // const x_axis0 = Vector3.new(x_axis2.x(), 0, x_axis2.y()).scaledTo(size.x());
                    const y_axis0 = Vector3.new(y_axis2.x(), 0, y_axis2.y()).scaledTo(size.y());
                    const x_axis1 =
                        self.game_transform.x.scaledTo(x_axis2.x())
                            .plus(self.game_transform.y.scaledTo(x_axis2.y())).scaledTo(size.x());
                    const y_axis1 =
                        self.game_transform.x.scaledTo(y_axis2.x())
                            .plus(self.game_transform.y.scaledTo(y_axis2.y())).scaledTo(size.y());

                    // x_axis = x_axis0.lerp(x_axis1, 0.8);
                    // y_axis = y_axis0.lerp(y_axis1, 0.8);

                    x_axis = x_axis1;
                    y_axis = y_axis1;
                    _ = y_axis.setZ(math.lerpf(y_axis0.z(), y_axis1.z(), 0.8));
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
                    null,
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

    pub fn pushCubeLight(
        self: *RenderGroup,
        position: Vector3,
        radius: f32,
        color: Color3,
        emission: f32,
    ) void {
        self.pushCube(
            self.commands.white_bitmap,
            position.plus(.new(0, 0, 0.5 * radius)),
            radius,
            radius,
            color.toColor(1),
            emission,
        );
    }

    pub fn pushCube(
        self: *RenderGroup,
        bitmap: ?*LoadedBitmap,
        position: Vector3,
        radius: f32,
        height: f32,
        color: Color,
        opt_emission: ?f32,
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

            // const top_color: Color = storeColor(color);
            // const bottom_color: Color = .new(0, 0, 0, top_color.a());
            // const ct: Color = top_color.rgb().scaledTo(0.75).toColor(top_color.a());
            // const cb: Color = top_color.rgb().scaledTo(0.25).toColor(top_color.a());

            const top_color = storeColor(color);
            const bottom_color = top_color;
            const ct = top_color;
            const cb = top_color;

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
                opt_emission,
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
                opt_emission,
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
                opt_emission,
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
                opt_emission,
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
                opt_emission,
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
                opt_emission,
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
                null,
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

    pub fn pushVolumeOutline(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        rectangle: Rectangle3,
        color: Color,
        thickness: f32,
    ) void {
        if (self.getCurrentQuads(6) != null) {
            const bitmap: ?*LoadedBitmap = self.commands.white_bitmap;
            const offset_position: Vector3 = object_transform.offset_position;

            const nx: f32 = offset_position.x() + rectangle.min.x();
            const px: f32 = offset_position.x() + rectangle.max.x();
            const ny: f32 = offset_position.y() + rectangle.min.y();
            const py: f32 = offset_position.y() + rectangle.max.y();
            const nz: f32 = offset_position.z() + rectangle.min.z();
            const pz: f32 = offset_position.z() + rectangle.max.z();

            const p0: Vector3 = .new(nx, ny, pz);
            const p1: Vector3 = .new(px, ny, pz);
            const p2: Vector3 = .new(px, py, pz);
            const p3: Vector3 = .new(nx, py, pz);
            const p4: Vector3 = .new(nx, ny, nz);
            const p5: Vector3 = .new(px, ny, nz);
            const p6: Vector3 = .new(px, py, nz);
            const p7: Vector3 = .new(nx, py, nz);

            const line_color: Color = storeColor(color);

            self.pushLineSegment(bitmap, p0, line_color, p1, line_color, thickness);
            self.pushLineSegment(bitmap, p0, line_color, p3, line_color, thickness);
            self.pushLineSegment(bitmap, p0, line_color, p4, line_color, thickness);

            self.pushLineSegment(bitmap, p2, line_color, p1, line_color, thickness);
            self.pushLineSegment(bitmap, p2, line_color, p3, line_color, thickness);
            self.pushLineSegment(bitmap, p2, line_color, p6, line_color, thickness);

            self.pushLineSegment(bitmap, p5, line_color, p1, line_color, thickness);
            self.pushLineSegment(bitmap, p5, line_color, p4, line_color, thickness);
            self.pushLineSegment(bitmap, p5, line_color, p6, line_color, thickness);

            self.pushLineSegment(bitmap, p7, line_color, p3, line_color, thickness);
            self.pushLineSegment(bitmap, p7, line_color, p4, line_color, thickness);
            self.pushLineSegment(bitmap, p7, line_color, p6, line_color, thickness);
        }
    }

    pub fn pushSetup(
        self: *RenderGroup,
        new_setup: *RenderSetup,
    ) void {
        self.last_setup = new_setup.*;
        self.current_quads = null;
    }

    fn getScreenPoint(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        world_position: Vector3,
    ) Vector2 {
        var position: Vector4 =
            self.last_setup.projection.timesV(world_position.plus(object_transform.offset_position)).toVector4(1);
        _ = position.setXYZ(position.xyz().dividedByF(position.w()));

        _ = position.setX(self.screen_dimensions.x() * 0.5 * (position.x() + 1));
        _ = position.setY(self.screen_dimensions.y() * 0.5 * (position.y() + 1));

        return position.xy();
    }

    pub fn getClipRectByTransform(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        offset: Vector3,
        dimension: Vector2,
    ) Rectangle2i {
        const min_corner: Vector2 = self.getScreenPoint(object_transform, offset);
        const max_corner: Vector2 = self.getScreenPoint(object_transform, offset.plus(dimension.toVector3(0)));

        return .fromMinMax(
            .new(
                intrinsics.roundReal32ToInt32(min_corner.x()),
                intrinsics.roundReal32ToInt32(min_corner.y()),
            ),
            .new(
                intrinsics.roundReal32ToInt32(max_corner.x()),
                intrinsics.roundReal32ToInt32(max_corner.y()),
            ),
        );
    }

    pub fn getClipRectByRectangle(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        rectangle: Rectangle2,
        z: f32,
    ) Rectangle2i {
        return self.getClipRectByTransform(
            object_transform,
            rectangle.min.toVector3(z),
            rectangle.getDimension(),
        );
    }

    pub fn pushRenderTarget(self: *RenderGroup, render_target_index: u32) u32 {
        var new_setup: RenderSetup = self.last_setup;
        new_setup.render_target_index = render_target_index;
        self.pushSetup(&new_setup);
        return 0;
    }

    pub fn setCameraTransformToIdentity(
        self: *RenderGroup,
        focal_length: f32,
        flags: u32,
    ) void {
        self.setCameraTransform(
            focal_length,
            .new(1, 0, 0),
            .new(0, 1, 0),
            .new(0, 0, 1),
            .zero(),
            flags,
            null,
            null,
            null,
            null,
        );
    }

    pub fn setCameraTransform(
        self: *RenderGroup,
        focal_length: f32,
        camera_x: Vector3,
        camera_y: Vector3,
        camera_z: Vector3,
        camera_position: Vector3,
        flags: u32,
        opt_near_clip_plane: ?f32,
        opt_far_clip_plane: ?f32,
        opt_fog: ?bool,
        opt_debug_light_position: ?Vector3,
    ) void {
        const debug_light_position: Vector3 = opt_debug_light_position orelse .zero();
        const fog: bool = opt_fog orelse false;
        const near_clip_plane: f32 = opt_near_clip_plane orelse 0.1;
        const far_clip_plane: f32 = opt_far_clip_plane orelse 100;
        const is_ortho: bool = (flags & @intFromEnum(CameraTransformFlag.IsOrthographic)) != 0;
        const is_debug: bool = (flags & @intFromEnum(CameraTransformFlag.IsDebug)) != 0;
        const b: f32 = math.safeRatio1(
            @as(f32, @floatFromInt(self.commands.settings.width)),
            @as(f32, @floatFromInt(self.commands.settings.height)),
        );

        var new_setup: RenderSetup = self.last_setup;
        var render_transform: *RenderTransform = if (is_debug) &self.debug_transform else &self.game_transform;
        var proj: MatrixInverse4x4 = .{};
        if (is_ortho) {
            proj = .orthographicProjection(b, near_clip_plane, far_clip_plane);
        } else {
            proj = .perspectiveProjection(b, focal_length, near_clip_plane, far_clip_plane);
        }

        if (fog) {
            new_setup.fog_direction = camera_z.negated();
            new_setup.fog_start_distance = 8;
            new_setup.fog_end_distance = 20;
            new_setup.clip_alpha_start_distance = near_clip_plane + 2;
            new_setup.clip_alpha_end_distance = near_clip_plane + 2.25;
        } else {
            new_setup.fog_direction = .zero();
            new_setup.clip_alpha_start_distance = near_clip_plane - 100;
            new_setup.clip_alpha_end_distance = near_clip_plane - 99;
        }

        render_transform.x = camera_x;
        render_transform.y = camera_y;
        render_transform.z = camera_z;
        render_transform.position = camera_position;

        new_setup.camera_position = camera_position;
        new_setup.debug_light_position = debug_light_position;

        const camera_c: MatrixInverse4x4 = .cameraTransform(camera_x, camera_y, camera_z, camera_position);
        render_transform.projection.forward = proj.forward.times(camera_c.forward);
        render_transform.projection.inverse = camera_c.inverse.times(proj.inverse);

        if (SLOW) {
            const identity: Matrix4x4 = render_transform.projection.inverse.times(render_transform.projection.forward);
            _ = identity;
        }

        new_setup.projection = render_transform.projection.forward;
        self.pushSetup(&new_setup);

        if (!is_debug) {
            self.debug_transform = self.game_transform;
        }
    }

    const LightingElement = struct {
        // Static information.
        position: Vector3,
        normal: Vector3,
        transparency: f32,
        radius: f32,
        reflection_color: Color3,

        // Ambient occlusion.
        visibility: f32,
        shadow: f32, // Transient.

        // Lighting.
        front_emission_color: Color3,
        back_emission_color: Color3,
        accumulated_color: Color3, // Transient.
    };

    pub fn lightingTest(self: *RenderGroup) void {
        var elements: [6144]LightingElement = [1]LightingElement{undefined} ** 6144;

        const camera_position: Vector3 = self.last_setup.camera_position;

        const commands: *RenderCommands = self.commands;
        std.debug.assert(self.current_quads != null);
        const quads: *RenderEntryTexturedQuads = self.current_quads.?;

        const reflector_pick: Vector3 = .new(0, 4.5, 1.5);
        var close_pick_index: u32 = 0;
        const max_emission: f32 = 10;

        // Copy ligthing in.
        {
            var verts: [*]TexturedVertex = commands.vertex_array + quads.vertex_array_offset;
            var close_pick_distance_squared: f32 = std.math.floatMax(f32);

            var quad_index: u32 = 0;
            while (quad_index < quads.quad_count) : (quad_index += 1) {
                var element: *LightingElement = &elements[quad_index];
                var vert0: *TexturedVertex = @ptrCast(verts + 0);
                var vert1: *TexturedVertex = @ptrCast(verts + 1);
                var vert2: *TexturedVertex = @ptrCast(verts + 3);
                var vert3: *TexturedVertex = @ptrCast(verts + 2);

                var vert0_position: Vector3 = vert0.position.xyz();
                _ = vert0_position.setZ(vert0_position.z() + vert0.position.w());

                var vert1_position: Vector3 = vert1.position.xyz();
                _ = vert1_position.setZ(vert1_position.z() + vert1.position.w());

                var vert2_position: Vector3 = vert2.position.xyz();
                _ = vert2_position.setZ(vert2_position.z() + vert2.position.w());

                var vert3_position: Vector3 = vert3.position.xyz();
                _ = vert3_position.setZ(vert3_position.z() + vert3.position.w());

                const span30: Vector3 = vert3_position.minus(vert0_position);
                const span20: Vector3 = vert2_position.minus(vert0_position);
                const span10: Vector3 = vert1_position.minus(vert0_position);

                element.position = vert0_position.plus(span20.scaledTo(0.5));
                element.radius = 0.75 * @min(span30.length(), span10.length());

                // TODO: Remove the premultiplied alpha here?
                const color: Color = Color.unpackColorRGBA(vert0.color).scaledTo(1.0 / 255.0);

                element.normal = vert0.normal;
                element.front_emission_color = .zero();
                element.back_emission_color = .zero();
                element.accumulated_color = .zero();
                element.reflection_color = color.rgb().scaledTo(0.95);
                element.transparency = color.a();
                element.front_emission_color = color.rgb().scaledTo(vert0.emission * max_emission);
                element.visibility = 1;
                element.shadow = 0;

                const this_pick_distance_squared = element.position.minus(reflector_pick).lengthSquared();
                if (close_pick_distance_squared > this_pick_distance_squared) {
                    close_pick_distance_squared = this_pick_distance_squared;
                    close_pick_index = quad_index;
                }

                verts += 4;
            }
        }

        // Compute lighting.
        var series: random.Series = .seed(1234);
        var offsets: [16]Vector3 = undefined;
        for (&offsets) |*offset| {
            offset.* = Vector3.new(
                series.randomBilateral(),
                series.randomBilateral(),
                series.randomBilateral(),
            );
        }
        for (0..global_config.Renderer_Lighting_IterationCount) |_| {
            var dest_index: u32 = 0;
            while (dest_index < quads.quad_count) : (dest_index += 1) {
                var dest: *LightingElement = &elements[dest_index];

                var rays: [16]Vector3 = undefined;
                for (&rays, 0..) |*ray, i| {
                    ray.* = dest.normal.plus(offsets[i]).normalizeOrZero();
                }

                var closest_hit: [rays.len]f32 = [1]f32{std.math.floatMax(f32)} ** rays.len;
                const to_camera: Vector3 = camera_position.minus(dest.position).normalizeOrZero();
                var accumulated_color: Vector3 = .zero();

                var source_index: u32 = 0;
                while (source_index < quads.quad_count) : (source_index += 1) {
                    var source: *LightingElement = &elements[source_index];

                    const light_color: Vector3 = source.front_emission_color.toVector3();
                    var to_light: Vector3 = source.position.minus(dest.position);
                    const light_distance: f32 = to_light.length();
                    if (light_distance > 0) {
                        to_light = to_light.scaledTo(1.0 / light_distance);

                        const reflection_normal: Vector3 = dest.normal;
                        const diffuse_coefficient: f32 = 1;
                        const specular_coefficent: f32 = 1 - diffuse_coefficient;
                        // const specular_power = 1.0 + (15.0);
                        const distance_falloff: f32 = 1.0 / (1.0 + math.square(light_distance));

                        const diffuse_dot: f32 = math.clampf01(to_light.dotProduct(reflection_normal));
                        const diffuse_contrib: f32 = distance_falloff * diffuse_coefficient * diffuse_dot;
                        const diffuse_contrib3: Vector3 = .splat(diffuse_contrib);
                        const diffuse_light: Vector3 = diffuse_contrib3.hadamardProduct(light_color);

                        const reflection_vector: Vector3 =
                            to_camera.negated().plus(reflection_normal.scaledTo(2 * reflection_normal.dotProduct(to_camera)));
                        const specular_dot: f32 = math.clampf01(to_light.dotProduct(reflection_vector));
                        // specular_dot = pow(specular_dot, specular_power);
                        const specular_contrib: f32 = specular_coefficent * specular_dot;
                        const specular_contrib3: Vector3 = .splat(specular_contrib);
                        const specular_light: Vector3 = specular_contrib3.hadamardProduct(light_color);

                        const total_light: Vector3 = diffuse_light.plus(specular_light);
                        const result: Vector3 = dest.reflection_color.toVector3().hadamardProduct(total_light);

                        if (true) {
                            var ray_index: u32 = 0;
                            while (ray_index < rays.len) : (ray_index += 1) {
                                const ray: Vector3 = rays[ray_index];
                                const ray_source_normal = ray.dotProduct(source.normal);
                                if (ray_source_normal < -0.001) {
                                    const relative_source_position: Vector3 = source.position.minus(dest.position);
                                    const d: f32 = -source.normal.dotProduct(relative_source_position);
                                    const t_ray: f32 = -d / ray_source_normal;

                                    if (t_ray > 0 and t_ray < closest_hit[ray_index]) {
                                        const ray_position: Vector3 = ray.scaledTo(t_ray);
                                        const cone_radius: f32 = 0.25 * t_ray;
                                        const distance_squared: f32 =
                                            ray_position.minus(relative_source_position).lengthSquared();
                                        if (distance_squared < math.square(source.radius + cone_radius)) {
                                            closest_hit[ray_index] = t_ray;
                                            accumulated_color = result;
                                        }
                                    }
                                }
                            }
                        } else {
                            accumulated_color = accumulated_color.plus(result);
                        }
                    }
                }

                dest.accumulated_color = accumulated_color.toColor3().scaledTo(dest.visibility);
            }

            var quad_index: u32 = 0;
            while (quad_index < quads.quad_count) : (quad_index += 1) {
                var dest: *LightingElement = &elements[quad_index];
                const iteration_count: f32 = @as(f32, @floatFromInt(global_config.Renderer_Lighting_IterationCount));
                dest.front_emission_color =
                    dest.front_emission_color.plus(dest.accumulated_color.scaledTo(1.0 / iteration_count));
            }
        }

        // Calculate ambient occlusion.
        for (0..global_config.Renderer_Lighting_OcclusionIterationCount) |i| {
            var dest_index: u32 = 0;
            while (dest_index < quads.quad_count) : (dest_index += 1) {
                var dest: *LightingElement = &elements[dest_index];
                var shadow: f32 = 0;

                var source_index: u32 = 0;
                while (source_index < quads.quad_count) : (source_index += 1) {
                    var source: *LightingElement = &elements[source_index];

                    std.debug.assert(source.visibility >= 0);
                    std.debug.assert(source.visibility <= 1);

                    var v: Vector3 = source.position.minus(dest.position);
                    const vsq = v.lengthSquared();
                    const v_len = @sqrt(vsq);

                    if (v_len > 0.0001) {
                        std.debug.assert(dest_index != source_index);

                        v = v.scaledTo(1.0 / v_len);

                        const apparent_source_amount: f32 = intrinsics.absoluteValue(source.normal.dotProduct(v));
                        const apparent_dest_amount: f32 = math.clampf01(4 * dest.normal.dotProduct(v));
                        const apparent_source_area: f32 = (math.PI32 * math.square(source.radius)) / vsq;

                        const s: f32 = (1 - intrinsics.reciprocalSquareRoot(apparent_source_area + 1.0)) *
                            apparent_source_amount * apparent_dest_amount;

                        std.debug.assert(s >= 0);
                        std.debug.assert(s <= 1);

                        shadow += source.visibility * s;
                    }
                }

                shadow = math.clampf01(shadow);

                if (i == 1) {
                    std.debug.assert(shadow <= dest.shadow);
                }

                dest.shadow = shadow;
            }

            var quad_index: u32 = 0;
            while (quad_index < quads.quad_count) : (quad_index += 1) {
                var dest: *LightingElement = &elements[quad_index];
                dest.visibility = 1.0 - dest.shadow;
            }
        }

        // Copy ligthing out.
        {
            var bitmap: [*]?*LoadedBitmap = @ptrCast(&commands.quad_bitmaps[quads.vertex_array_offset >> 2]);
            var verts: [*]TexturedVertex = commands.vertex_array + quads.vertex_array_offset;

            var quad_index: u32 = 0;
            while (quad_index < quads.quad_count) : (quad_index += 1) {
                var element: *LightingElement = &elements[quad_index];

                var vert0: *TexturedVertex = @ptrCast(verts + 0);
                var vert1: *TexturedVertex = @ptrCast(verts + 1);
                var vert2: *TexturedVertex = @ptrCast(verts + 2);
                var vert3: *TexturedVertex = @ptrCast(verts + 3);

                var front_emission_color: Color = element.front_emission_color.clamp01().toColor(1);
                if (global_config.Renderer_Lighting_ShowVisibility) {
                    front_emission_color = Color3.white().scaledTo(element.visibility).toColor(1);
                }

                if (false) {
                    if (quad_index == close_pick_index) {
                        front_emission_color = Color3.new(1, 1, 0).scaledTo(element.visibility).toColor(1);
                    }
                }

                if (global_config.Renderer_Lighting_ShowReflectors) {
                    bitmap[0] = commands.white_bitmap;

                    var base: Vector3 = .zero();
                    {
                        var normal = vert0.normal;
                        _ = normal.setX(@abs(normal.x()));
                        _ = normal.setY(@abs(normal.y()));
                        _ = normal.setZ(@abs(normal.z()));

                        var min_el: u32 = 0;
                        if (normal.x() < normal.y()) {
                            if (normal.z() < normal.y()) {
                                min_el = 2;
                            } else {
                                min_el = 0;
                            }
                        } else {
                            if (normal.z() < normal.y()) {
                                min_el = 2;
                            } else {
                                min_el = 1;
                            }
                        }
                        base.values[min_el] = 1;
                    }

                    var x: Vector3 = base.crossProduct(vert0.normal);
                    var y: Vector3 = x.crossProduct(vert0.normal).negated();

                    x = x.normalizeOrZero().scaledTo(element.radius);
                    y = y.normalizeOrZero().scaledTo(element.radius);

                    _ = vert0.position.setXYZ(element.position.minus(y));
                    _ = vert1.position.setXYZ(element.position.plus(x));
                    _ = vert2.position.setXYZ(element.position.minus(x));
                    _ = vert3.position.setXYZ(element.position.plus(y));

                    _ = vert0.position.setW(0);
                    _ = vert1.position.setW(0);
                    _ = vert2.position.setW(0);
                    _ = vert3.position.setW(0);

                    vert0.normal = element.normal;
                    vert1.normal = element.normal;
                    vert2.normal = element.normal;
                    vert3.normal = element.normal;

                    const front_emission_color32 =
                        front_emission_color.rgb().toColor(element.transparency).scaledTo(255.0).packColorRGBA();
                    vert0.color = front_emission_color32;
                    vert1.color = front_emission_color32;
                    vert2.color = front_emission_color32;
                    vert3.color = front_emission_color32;
                } else {
                    vert0.color =
                        front_emission_color.hadamardProduct(Color.unpackColorRGBA(vert0.color)).packColorRGBA();
                    vert1.color =
                        front_emission_color.hadamardProduct(Color.unpackColorRGBA(vert1.color)).packColorRGBA();
                    vert2.color =
                        front_emission_color.hadamardProduct(Color.unpackColorRGBA(vert2.color)).packColorRGBA();
                    vert3.color =
                        front_emission_color.hadamardProduct(Color.unpackColorRGBA(vert3.color)).packColorRGBA();
                }

                bitmap += 1;
                verts += 4;
            }
        }
    }
};
