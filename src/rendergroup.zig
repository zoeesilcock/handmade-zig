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
const LoadedBitmap = asset.LoadedBitmap;
const LoadedFont = asset.LoadedFont;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const RenderCommands = shared.RenderCommands;
const ArenaPushParams = shared.ArenaPushParams;
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
    RenderEntryClipRect,
    RenderEntryBitmap,
    RenderEntryRectangle,
    RenderEntrySaturation,
    RenderEntryBlendRenderTarget,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
    clip_rect_index: u16,
    debug_tag: u32,
};

pub const RenderEntryClipRect = extern struct {
    next: ?*RenderEntryClipRect,
    rect: Rectangle2i,
    render_target_index: u32,
    focal_length: f32,
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

pub const RenderEntryBitmap = extern struct {
    bitmap: ?*LoadedBitmap,
    premultiplied_color: Color,
    position: Vector3,
    // These are already scaled by the half dimension.
    x_axis: Vector2,
    y_axis: Vector2,
};

pub const RenderEntryRectangle = extern struct {
    premultiplied_color: Color,
    position: Vector3,
    dimension: Vector2 = Vector2.zero(),
};

pub const RenderEntryBlendRenderTarget = extern struct {
    source_target_index: u32,
    alpha: f32,
};

pub const ObjectTransform = extern struct {
    upright: bool,
    offset_position: Vector3,
    scale: f32,
    floor_z: f32 = 0,
    chunk_z: i32 = 0,
    manual_sort: ManualSortKey = .{},
    color_time: Color = .zero(),
    color: Color = .zero(),

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

const CameraTransform = extern struct {
    orthographic: bool,
    focal_length: f32,
    camera_position: Vector3,
};

const PushBufferResult = extern struct {
    header: ?*RenderEntryHeader = null,
};

fn getRenderEntityBasisPosition(
    camera_transform: CameraTransform,
    object_transform: *const ObjectTransform,
    original_position: Vector3,
) Vector3 {
    var result: Vector3 = .zero();
    var position: Vector3 = original_position.xy().toVector3(0).plus(object_transform.offset_position);

    _ = position.setXY(position.xy().minus(camera_transform.camera_position.xy()));

    if (camera_transform.orthographic) {
        result = position;
    } else {
        var distance_above_target = camera_transform.camera_position.z();

        if (global_config.Renderer_Camera_UseDebug) {
            distance_above_target += global_config.Renderer_Camera_DebugDistance;
        }

        const floor_z: f32 = object_transform.floor_z;
        const distance_to_position_z: f32 = distance_above_target - floor_z;

        const height_of_floor: f32 = position.z() - floor_z;

        var raw_xy = position.xy().toVector3(1);
        const ortho_y_from_z: f32 = 1;
        _ = raw_xy.setY(raw_xy.y() + ortho_y_from_z * height_of_floor);

        result = .new(raw_xy.x(), raw_xy.y(), distance_to_position_z);
    }

    return result;
}

pub const RenderGroup = extern struct {
    assets: *asset.Assets,

    screen_dimensions: Vector2,
    debug_tag: u32,

    camera_transform: CameraTransform,

    missing_resource_count: u32,
    renders_in_background: bool,

    generation_id: u32,
    commands: *RenderCommands,

    current_clip_rect_index: u32,

    pub fn begin(
        assets: *asset.Assets,
        commands: *RenderCommands,
        generation_id: u32,
        renders_in_background: bool,
        pixel_width: i32,
        pixel_height: i32,
    ) RenderGroup {
        var result: RenderGroup = .{
            .assets = assets,
            .renders_in_background = renders_in_background,
            .missing_resource_count = 0,
            .generation_id = generation_id,
            .commands = commands,
            .screen_dimensions = .newI(pixel_width, pixel_height),
            .debug_tag = undefined,
            .camera_transform = undefined,
            .current_clip_rect_index = 0,
        };

        result.current_clip_rect_index = result.pushClipRect(
            0,
            0,
            @intCast(pixel_width),
            @intCast(pixel_height),
            0,
            1,
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

    pub fn setCameraTransform(
        self: *RenderGroup,
        focal_length: f32,
        camera_position: Vector3,
        ortho: bool,
    ) void {
        const pixel_width: f32 = self.screen_dimensions.x();
        const pixel_height: f32 = self.screen_dimensions.y();

        self.camera_transform.focal_length = focal_length;
        self.camera_transform.camera_position = camera_position;
        self.camera_transform.orthographic = ortho;
        self.current_clip_rect_index = self.pushClipRect(
            0,
            0,
            @intFromFloat(pixel_width),
            @intFromFloat(pixel_height),
            0,
            focal_length,
        );
    }

    pub fn perspectiveMode(
        self: *RenderGroup,
        focal_length: f32,
        camera_position: Vector3,
    ) void {
        self.setCameraTransform(focal_length, camera_position, false);
    }

    pub fn orthographicMode(
        self: *RenderGroup,
    ) void {
        self.setCameraTransform(1, .new(0, 0, 1), true);
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

        return result;
    }

    // Renderer API.
    pub fn unproject(self: *RenderGroup, object_transform: *const ObjectTransform, pixels_xy: Vector2) Vector3 {
        const camera_transform = self.camera_transform;
        const screen_center: Vector2 = self.screen_dimensions.scaledTo(0.5);

        var unprojected_xy: Vector2 = pixels_xy.minus(screen_center);
        const aspect: f32 = self.screen_dimensions.x() / self.screen_dimensions.y();
        _ = unprojected_xy.setX(unprojected_xy.x() * 0.5 / self.screen_dimensions.x());
        _ = unprojected_xy.setY(unprojected_xy.y() * 0.5 / (self.screen_dimensions.y() * aspect));

        if (!camera_transform.orthographic) {
            unprojected_xy =
                unprojected_xy.scaledTo(
                    (camera_transform.camera_position.z() - object_transform.offset_position.z()) /
                        camera_transform.focal_length,
                );
        }

        var result: Vector3 =
            unprojected_xy.plus(camera_transform.camera_position.xy()).toVector3(object_transform.offset_position.z());
        result = result.minus(object_transform.offset_position);

        return result;
    }

    pub fn getCameraRectangleAtDistance(self: *RenderGroup, distance_from_camera: f32) Rectangle3 {
        var transform: ObjectTransform = .defaultFlat();
        _ = transform.offset_position.setZ(-distance_from_camera);

        const min_corner = self.unproject(&transform, .zero());
        const max_corner = self.unproject(&transform, self.screen_dimensions);

        return Rectangle3.fromMinMax(min_corner, max_corner);
    }

    pub fn getCameraRectangleAtTarget(self: *RenderGroup) Rectangle3 {
        return self.getCameraRectangleAtDistance(self.camera_transform.camera_position.z());
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
        const x_axis: Vector2 = opt_x_axis orelse Vector2.new(1, 0);
        const y_axis: Vector2 = opt_y_axis orelse Vector2.new(0, 1);
        var dim = UsedBitmapDim{};

        dim.size = Vector2.new(height * bitmap.width_over_height, height);
        dim.alignment = bitmap.alignment_percentage.hadamardProduct(dim.size).scaledTo(align_coefficient);
        _ = dim.position.setZ(offset.z());
        _ = dim.position.setXY(
            offset.xy().minus(x_axis.scaledTo(dim.alignment.x())).minus(y_axis.scaledTo(dim.alignment.y())),
        );
        dim.basis_position = getRenderEntityBasisPosition(self.camera_transform, object_transform, dim.position);

        return dim;
    }

    fn storeColor(transform: *const ObjectTransform, source: Color) Color {
        var dest: Color = undefined;
        const time: Color = transform.color_time;
        const color: Color = transform.color;

        _ = dest.setA(math.lerpf(source.a(), color.a(), time.a()));
        _ = dest.setR(dest.a() * math.lerpf(source.r(), color.r(), time.r()));
        _ = dest.setG(dest.a() * math.lerpf(source.g(), color.g(), time.g()));
        _ = dest.setB(dest.a() * math.lerpf(source.b(), color.b(), time.b()));

        return dest;
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
        const x_axis: Vector2 = opt_x_axis orelse Vector2.new(1, 0);
        const y_axis: Vector2 = opt_y_axis orelse Vector2.new(0, 1);
        const dim = self.getBitmapDim(object_transform, bitmap, height, offset, align_coefficient, x_axis, y_axis);

        const size: Vector2 = dim.size;
        if (self.pushRenderElement(RenderEntryBitmap)) |entry| {
            entry.bitmap = bitmap;
            entry.position = dim.basis_position;
            entry.premultiplied_color = storeColor(object_transform, color);
            entry.x_axis = size.times(x_axis);
            entry.y_axis = size.times(y_axis);
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
            var opt_bitmap = self.assets.getBitmap(id, self.generation_id);

            if (self.renders_in_background and opt_bitmap == null) {
                self.assets.loadBitmap(id, true);
                opt_bitmap = self.assets.getBitmap(id, self.generation_id);
            }

            if (opt_bitmap) |bitmap| {
                self.pushBitmap(object_transform, bitmap, height, offset, color, align_coefficient, opt_x_axis, opt_y_axis);
            } else {
                std.debug.assert(!self.renders_in_background);

                self.assets.loadBitmap(id, false);
                self.missing_resource_count += 1;
            }
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
                std.debug.assert(!self.renders_in_background);

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

        const basis_position = getRenderEntityBasisPosition(self.camera_transform, object_transform, position);
        if (self.pushRenderElement(RenderEntryRectangle)) |entry| {
            entry.position = basis_position;
            entry.dimension = dimension;
            entry.premultiplied_color = storeColor(object_transform, color);
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

    pub fn pushClipRectByTransform(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        dimension: Vector2,
        offset: Vector3,
        render_target_index: u32,
    ) u32 {
        var result: u32 = 0;
        const modified_position = offset.minus(dimension.scaledTo(0.5).toVector3(0));

        const position = getRenderEntityBasisPosition(self.camera_transform, object_transform, modified_position);
        const basis_dimension: Vector2 = dimension;
        result = self.pushClipRect(
            intrinsics.roundReal32ToInt32(position.x()),
            intrinsics.roundReal32ToInt32(position.y()),
            intrinsics.roundReal32ToInt32(basis_dimension.x()),
            intrinsics.roundReal32ToInt32(basis_dimension.y()),
            render_target_index,
            self.camera_transform.focal_length,
        );

        return result;
    }

    pub fn pushClipRectByRectangle(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        rectangle: Rectangle2,
        z: f32,
        render_target_index: u32,
    ) u32 {
        return self.pushClipRectByTransform(
            object_transform,
            rectangle.getDimension(),
            rectangle.getCenter().toVector3(z),
            render_target_index,
        );
    }

    pub fn pushClipRect(
        self: *RenderGroup,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        render_target_index: u32,
        focal_length: f32,
    ) u32 {
        var result: u32 = 0;

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
            rect.focal_length = focal_length;

            rect.render_target_index = render_target_index;
            if (self.commands.max_render_target_index < render_target_index) {
                self.commands.max_render_target_index = render_target_index;
            }
        }

        return result;
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
