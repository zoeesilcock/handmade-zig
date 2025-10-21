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
const memory = @import("memory.zig");
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
const LightingTextures = shared.LightingTextures;
const LightingTexel = shared.LightingTexel;
const LIGHT_DATA_WIDTH = shared.LIGHT_DATA_WIDTH;
const LIGHT_LOOKUP_X = shared.LIGHT_LOOKUP_X;
const LIGHT_LOOKUP_Y = shared.LIGHT_LOOKUP_Y;
const LIGHT_LOOKUP_Z = shared.LIGHT_LOOKUP_Z;
const MAX_LIGHT_POWER = shared.MAX_LIGHT_POWER;
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
    RenderEntryLightingTransfer,
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

pub const RenderEntryLightingTransfer = extern struct {
    voxel_min_corner: Vector3,
    voxel_inverse_cell_dimension: Vector3,

    position_next: [*]f32,
    color: [*]u32,
    direction: [*]f32,
    lookup: [*]u16,
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

const LightingElement = extern struct {
    // Static information.
    position: Vector3,
    normal: Vector3,
    transparency: f32,
    width: f32,
    height: f32,
    x_axis: Vector3,
    y_axis: Vector3,
    reflection_color: Color3,

    // Propagation.
    emission_color: Color3,
    next_emission_color: Color3,
    next_emission_weight: f32,

    // Gather.
    incident_light: Vector3,
    average_direction_to_light: Vector3,
};

pub const LightingSolution = extern struct {
    element_count: u32 = 0,
    elements: [LIGHT_DATA_WIDTH]LightingElement = [1]LightingElement{undefined} ** LIGHT_DATA_WIDTH,
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

    pub fn pushLighting(
        self: *RenderGroup,
        source: *LightingTextures,
        min_corner: Vector3,
        inverse_cell_dimension: Vector3,
    ) void {
        if (self.pushRenderElement(RenderEntryLightingTransfer)) |dest| {
            dest.position_next = @ptrCast(&source.position_next);
            dest.color = @ptrCast(&source.color);
            dest.direction = @ptrCast(&source.direction);
            dest.lookup = @ptrCast(&source.lookup);
            dest.voxel_min_corner = min_corner;
            dest.voxel_inverse_cell_dimension = inverse_cell_dimension;
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

    const max_emission: f32 = 10;

    fn extractReflectorsFromQuads(self: *RenderGroup, solution: *LightingSolution) void {
        const commands: *RenderCommands = self.commands;
        std.debug.assert(self.current_quads != null);
        const quads: *RenderEntryTexturedQuads = self.current_quads.?;

        const y_subdivision_count = 3;
        const x_subdivision_count = 3;
        solution.element_count = (y_subdivision_count * x_subdivision_count) * quads.quad_count;
        std.debug.assert(solution.element_count < solution.elements.len);

        var verts: [*]TexturedVertex = commands.vertex_array + quads.vertex_array_offset;
        var bitmaps: [*]?*LoadedBitmap = @ptrCast(&commands.quad_bitmaps[quads.vertex_array_offset >> 2]);

        var quad_index: u32 = 0;
        var element: [*]LightingElement = &solution.elements;
        while (quad_index < quads.quad_count) : (quad_index += 1) {
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
            const span10: Vector3 = vert1_position.minus(vert0_position);

            var x_axis: Vector3 = span10;
            var y_axis: Vector3 = span30;

            const width: f32 = x_axis.length();
            const height: f32 = y_axis.length();
            x_axis = x_axis.normalizeOrZero();
            y_axis = y_axis.normalizeOrZero();

            const sub_width: f32 = width / @as(f32, @floatFromInt(x_subdivision_count));
            const sub_height: f32 = height / @as(f32, @floatFromInt(y_subdivision_count));
            for (0..y_subdivision_count) |y_sub| {
                for (0..x_subdivision_count) |x_sub| {
                    element[0].width = sub_width;
                    element[0].height = sub_height;

                    element[0].position = vert0_position
                        .plus(x_axis.scaledTo((@as(f32, @floatFromInt(x_sub)) + 0.5) * sub_width))
                        .plus(y_axis.scaledTo((@as(f32, @floatFromInt(y_sub)) + 0.5) * sub_height));

                    // TODO: Remove the premultiplied alpha here?
                    const color: Color = Color.unpackColorRGBA(vert0.color).scaledTo(1.0 / 255.0);

                    element[0].x_axis = x_axis;
                    element[0].y_axis = y_axis;
                    element[0].normal = vert0.normal;
                    element[0].emission_color = .zero();
                    element[0].reflection_color = color.rgb().scaledTo(0.95);
                    element[0].transparency = color.a();
                    element[0].emission_color = Color3.new(1, 1, 1).scaledTo(vert0.emission * max_emission);
                    element[0].next_emission_color = .zero();
                    element[0].next_emission_weight = 0;

                    element += 1;
                }
            }

            verts += 4;
            bitmaps += 1;
        }
    }

    const RaycastResult = struct {
        color: Color3,
        index: u32,
    };

    fn raycast(
        solution: *LightingSolution,
        skip_index: u32,
        ray_origin: Vector3,
        ray_direction: Vector3,
    ) RaycastResult {
        var result: RaycastResult = .{
            .color = .zero(),
            .index = solution.element_count,
        };
        var closest_hit: f32 = std.math.floatMax(f32);

        var source_index: u32 = 0;
        while (source_index < solution.element_count) : (source_index += 1) {
            if (source_index != skip_index) {
                var source: *LightingElement = &solution.elements[source_index];
                const ray_source_normal = ray_direction.dotProduct(source.normal);
                if (ray_source_normal < -0.001) {
                    const relative_origin: Vector3 = ray_origin.minus(source.position);
                    const d: f32 = source.normal.dotProduct(relative_origin);
                    const t_ray: f32 = -d / ray_source_normal;

                    if (t_ray > 0 and t_ray < closest_hit) {
                        const ray_position: Vector3 = relative_origin.plus(ray_direction.scaledTo(t_ray));
                        const x_check: f32 = 2.0 * ray_position.dotProduct(source.x_axis);
                        const y_check: f32 = 2.0 * ray_position.dotProduct(source.y_axis);

                        if (x_check >= -source.width and x_check <= source.width and
                            y_check >= -source.height and y_check <= source.height)
                        {
                            closest_hit = t_ray;
                            result.color = source.emission_color;
                            result.index = source_index;
                        }
                    }
                }
            }
        }

        return result;
    }

    fn sampleHemisphere(series: *random.Series, normal: Vector3) Vector3 {
        const result: Vector3 = normal.plus(Vector3.new(
            series.randomBilateral(),
            series.randomBilateral(),
            series.randomBilateral(),
        ).scaledTo(0.5)).normalizeOrZero();

        // TODO: Why does this assertion fail for the gatherFinalLighting?
        // std.debug.assert(result.dotProduct(normal) > 0);

        return result;
    }

    fn computeLightPropagation(solution: *LightingSolution) void {
        const min_emission = 0.0;
        const ray_count = 8;
        var series: random.Series = .seed(1234);

        for (0..global_config.Renderer_Lighting_IterationCount) |_| {
            var emitter_index: u32 = 0;
            while (emitter_index < solution.element_count) : (emitter_index += 1) {
                var emitter: *LightingElement = &solution.elements[emitter_index];
                const sum: f32 = emitter.emission_color.r() + emitter.emission_color.g() + emitter.emission_color.b();
                if (sum > min_emission) {
                    var ray_index: u32 = 0;
                    while (ray_index < ray_count) : (ray_index += 1) {
                        const emission_direction: Vector3 = sampleHemisphere(&series, emitter.normal);

                        const hit_index: u32 = raycast(
                            solution,
                            emitter_index,
                            emitter.position,
                            emission_direction,
                        ).index;

                        if (hit_index < solution.element_count) {
                            const hit: *LightingElement = &solution.elements[hit_index];

                            const angular_attenuation: f32 = math.clampf01(-emission_direction.dotProduct(hit.normal));
                            const light_color: Color3 = emitter.emission_color.scaledTo(angular_attenuation);

                            hit.next_emission_color = hit.next_emission_color.plus(light_color);
                            hit.next_emission_weight += 1;
                        }
                    }
                }
            }

            var reflector_index: u32 = 0;
            while (reflector_index < solution.element_count) : (reflector_index += 1) {
                var reflector: *LightingElement = &solution.elements[reflector_index];
                if (reflector.next_emission_weight > 0) {
                    reflector.emission_color = reflector.reflection_color.hadamardProduct(reflector.next_emission_color)
                        .scaledTo(1.0 / reflector.next_emission_weight);
                }

                reflector.next_emission_color = .zero();
                reflector.next_emission_weight = 0;
            }
        }
    }

    fn gatherFinalLighting(solution: *LightingSolution) void {
        const ray_count = 16;
        var series: random.Series = .seed(1234);

        var dest_index: u32 = 0;
        while (dest_index < solution.element_count) : (dest_index += 1) {
            const dest: *LightingElement = &solution.elements[dest_index];

            var incident_accumulated: Vector3 = .zero();
            var incident_direction: Vector3 = .zero();
            var ray_index: u32 = 0;
            while (ray_index < ray_count) : (ray_index += 1) {
                const ray_direction: Vector3 = sampleHemisphere(&series, dest.normal);
                const incident_color: Color3 = raycast(solution, dest_index, dest.position, ray_direction).color;
                const weight: f32 = incident_color.length();

                incident_accumulated = incident_accumulated.plus(incident_color.toVector3());
                incident_direction = incident_direction.plus(ray_direction.scaledTo(weight));
            }

            dest.incident_light = incident_accumulated.scaledTo(1.0 / @as(f32, @floatFromInt(ray_count)));
            dest.average_direction_to_light = incident_direction.normalizeOrZero();
        }
    }

    pub fn lightingTest(self: *RenderGroup, solution: *LightingSolution) void {
        self.extractReflectorsFromQuads(solution);
        computeLightPropagation(solution);
        gatherFinalLighting(solution);
    }

    pub fn outputLighting(self: *RenderGroup, solution: *LightingSolution, opt_textures: ?*LightingTextures) void {
        if (false) {
            if (opt_textures) |textures| {
                self.outputTexturesDebug(solution, textures);
            }
        } else {
            self.outputLightingQuads(solution);
        }
    }

    fn decodePower(encoded_light: Color) Color {
        const result = encoded_light;
        result.setRGB(result.rgb().scaledTo(MAX_LIGHT_POWER * result.a()));
        result.setA(1);
        return result;
    }

    fn outputTexturesDebug(self: *RenderGroup, solution: *LightingSolution, textures: *LightingTextures) void {
        const commands: *RenderCommands = self.commands;
        _ = self.getCurrentQuads(solution.element_count);

        for (0..LIGHT_LOOKUP_Z) |z| {
            for (0..LIGHT_LOOKUP_Y) |y| {
                for (0..LIGHT_LOOKUP_X) |x| {
                    var index: u16 = textures.lookup[z][y][x];

                    if (false) {
                        while (index > 0) {
                            const position_next: *LightingTexel = &textures.position_next[index];

                            const position: Vector3 = position_next.position;
                            const color: Color = Color.unpackColorRGBA(textures.color[index]).scaledTo(1.0 / 255.0);

                            self.pushCube(commands.white_bitmap, position, 0.1, 0.1, color, null);

                            index = @intCast(position_next.next);
                        }
                    } else {
                        if (index > 0) {
                            var color_count: u32 = 0;
                            var color: Color = .new(0, 0, 0, 1);
                            while (index > 0) {
                                const position_next: *LightingTexel = &textures.position_next[index];
                                var unpack: Color = Color.unpackColorRGBA(textures.color[index]);
                                unpack = decodePower(unpack);

                                color = color.plus(unpack.scaledTo(1.0 / 255.0));
                                color_count += 1;
                                index = @intFromFloat(position_next.position.w());
                            }
                            _ = color.setRGB(color.rgb().scaledTo(1.0 / @as(f32, @floatFromInt(color_count))));

                            const position: Vector3 = textures.min_corner
                                .plus(textures.cell_dimension.scaledTo(0.5))
                                .plus(
                                textures.cell_dimension.hadamardProduct(
                                    .newU(@intCast(x), @intCast(y), @intCast(z)),
                                ),
                            );
                            self.pushCube(commands.white_bitmap, position, 0.1, 0.1, color, null);
                        }
                    }
                }
            }
        }
    }

    fn outputLightingQuads(self: *RenderGroup, solution: *LightingSolution) void {
        const commands: *RenderCommands = self.commands;
        _ = self.getCurrentQuads(solution.element_count);

        var element_index: u32 = 0;
        while (element_index < solution.element_count) : (element_index += 1) {
            var element: *LightingElement = &solution.elements[element_index];
            const bitmap: ?*LoadedBitmap = commands.white_bitmap;

            var emission_color: Color = element.emission_color.clamp01().toColor(1);

            var position0: Vector4 = .zero();
            var position1: Vector4 = .zero();
            var position2: Vector4 = .zero();
            var position3: Vector4 = .zero();

            var color0: u32 = 0;
            var color1: u32 = 0;
            var color2: u32 = 0;
            var color3: u32 = 0;

            const x: Vector3 = element.x_axis.scaledTo((0.5 * element.width) - 0.03);
            const y: Vector3 = element.y_axis.scaledTo((0.5 * element.height) - 0.03);

            _ = position0.setXYZ(element.position.minus(x).minus(y));
            _ = position1.setXYZ(element.position.plus(x).minus(y));
            _ = position2.setXYZ(element.position.plus(x).plus(y));
            _ = position3.setXYZ(element.position.minus(x).plus(y));

            _ = position0.setW(0);
            _ = position1.setW(0);
            _ = position2.setW(0);
            _ = position3.setW(0);

            const front_emission_color32 =
                emission_color.rgb().toColor(element.transparency).scaledTo(255.0).packColorRGBA();
            color0 = front_emission_color32;
            color1 = front_emission_color32;
            color2 = front_emission_color32;
            color3 = front_emission_color32;

            const uv: Vector2 = .zero();
            self.pushQuad(
                bitmap,
                position0,
                uv,
                color0,
                position1,
                uv,
                color1,
                position2,
                uv,
                color2,
                position3,
                uv,
                color3,
                null,
            );
        }
    }

    pub fn outputLightingTextures(self: *RenderGroup, solution: *LightingSolution, dest: *LightingTextures) void {
        dest.clearLookup();

        var min_corner: Vector3 = .splat(std.math.floatMax(f32));
        var max_corner: Vector3 = .splat(std.math.floatMin(f32));
        {
            var element_index: u32 = 0;
            while (element_index < solution.element_count) : (element_index += 1) {
                const element: *LightingElement = &solution.elements[element_index];

                for (0..3) |i| {
                    min_corner.values[i] = @min(element.position.values[i], min_corner.values[i]);
                    max_corner.values[i] = @max(element.position.values[i], max_corner.values[i]);
                }
            }
        }

        const epsilon: Vector3 = .splat(0.1);
        min_corner = min_corner.minus(epsilon);
        max_corner = max_corner.plus(epsilon);

        const dimension: Vector3 = max_corner.minus(min_corner);
        const cell_dimension: Vector3 = .new(
            dimension.x() / @as(f32, @floatFromInt(LIGHT_LOOKUP_X)),
            dimension.y() / @as(f32, @floatFromInt(LIGHT_LOOKUP_Y)),
            dimension.z() / @as(f32, @floatFromInt(LIGHT_LOOKUP_Z)),
        );
        const inverse_cell_dimension: Vector3 = .new(
            @as(f32, @floatFromInt(LIGHT_LOOKUP_X)) / dimension.x(),
            @as(f32, @floatFromInt(LIGHT_LOOKUP_Y)) / dimension.y(),
            @as(f32, @floatFromInt(LIGHT_LOOKUP_Z)) / dimension.z(),
        );

        var pack_index: u32 = 0;
        var element_index: u32 = 0;
        while (element_index < solution.element_count) : (element_index += 1) {
            const element: *LightingElement = &solution.elements[element_index];

            const voxel_position: Vector3 = inverse_cell_dimension.hadamardProduct(element.position.minus(min_corner));
            const voxel_x: u32 = @intFromFloat(voxel_position.x());
            const voxel_y: u32 = @intFromFloat(voxel_position.y());
            const voxel_z: u32 = @intFromFloat(voxel_position.z());
            const lookup_at: *u16 = &dest.lookup[voxel_z][voxel_y][voxel_x];

            const direction: Vector4 = element.average_direction_to_light.toVector4(0);
            const light_power: f32 = element.incident_light.length();
            var incident_light: Color = .zero();
            if (light_power > 0) {
                const light_color: Color3 = element.incident_light.dividedByF(light_power).toColor3();
                incident_light = light_color.clamp01().toColor(math.clampf01(light_power / MAX_LIGHT_POWER));
            }
            const color: u32 = incident_light.scaledTo(255).packColorRGBA();

            pack_index += 1;
            std.debug.assert(pack_index < dest.position_next.len);
            const position_next = &dest.position_next[pack_index];
            position_next.position = element.position.toVector4(@floatFromInt(lookup_at.*));
            // position_next.next = @floatFromInt(lookup_at.*);
            lookup_at.* = @intCast(pack_index);

            dest.color[pack_index] = color;
            dest.direction[pack_index] = direction;
        }

        for (0..LIGHT_LOOKUP_Z) |z| {
            for (0..LIGHT_LOOKUP_Y) |y| {
                for (0..LIGHT_LOOKUP_X) |x| {
                    if (dest.lookup[z][y][x] == 0) {
                        var neighbor: u16 = 0;

                        var dzi: i32 = if (z == 0) 0 else -1;
                        const dzm: i32 = if (z == (LIGHT_LOOKUP_Z - 1)) 0 else 1;
                        while (dzi <= dzm) : (dzi += 1) {
                            var dyi: i32 = if (y == 0) 0 else -1;
                            const dym: i32 = if (y == (LIGHT_LOOKUP_Y - 1)) 0 else 1;
                            while (dyi <= dym) : (dyi += 1) {
                                var dxi: i32 = if (x == 0) 0 else -1;
                                const dxm: i32 = if (x == (LIGHT_LOOKUP_X - 1)) 0 else 1;
                                while (dxi <= dxm) : (dxi += 1) {
                                    const dz: u32 = @intCast(@as(i32, @intCast(z)) + dzi);
                                    const dy: u32 = @intCast(@as(i32, @intCast(y)) + dyi);
                                    const dx: u32 = @intCast(@as(i32, @intCast(x)) + dxi);
                                    neighbor =
                                        if (neighbor > 0) neighbor else dest.lookup[dz][dy][dx];
                                }
                            }
                        }

                        dest.lookup[z][y][x] = neighbor;
                    }
                }
            }
        }

        dest.min_corner = min_corner;
        dest.max_corner = max_corner;
        dest.cell_dimension = cell_dimension;
        dest.inverse_cell_dimension = inverse_cell_dimension;

        self.pushLighting(dest, min_corner, inverse_cell_dimension);
    }
};
