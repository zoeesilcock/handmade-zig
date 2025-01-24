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
const asset = @import("asset.zig");
const intrinsics = @import("intrinsics.zig");
const config = @import("config.zig");
const file_formats = @import("file_formats");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

const INTERNAL = shared.INTERNAL;
pub const ENTITY_VISIBLE_PIECE_COUNT = 4096;

// Types.
const Vector2 = math.Vector2;
const Vector2i = math.Vector2i;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle2 = math.Rectangle2;
const Rectangle2i = math.Rectangle2i;
const LoadedBitmap = asset.LoadedBitmap;
const LoadedFont = asset.LoadedFont;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const RenderCommands = shared.RenderCommands;
const ArenaPushParams = shared.ArenaPushParams;

const Vec4f = math.Vec4f;
const Vec4u = math.Vec4u;
const Vec4i = math.Vec4i;

pub const UsedBitmapDim = struct {
    basis: RenderEntityBasisResult = undefined,
    size: Vector2 = undefined,
    alignment: Vector2 = undefined,
    position: Vector3 = undefined,
};

pub const EnvironmentMap = extern struct {
    lod: [4]LoadedBitmap,
    z_position: f32,
};

pub const RenderEntityBasisResult = extern struct {
    position: Vector2 = Vector2.zero(),
    scale: f32 = 0,
    valid: bool = false,
    sort_key: f32 = 0,
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
    bitmap: ?*LoadedBitmap,
    position: Vector2,
    size: Vector2,
    color: Color,
};

pub const RenderEntryRectangle = extern struct {
    position: Vector2,
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

    pixels_to_meters: f32,

    top: *EnvironmentMap,
    middle: *EnvironmentMap,
    bottom: *EnvironmentMap,
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

const CameraTransform = extern struct {
    orthographic: bool,

    meters_to_pixels: f32,
    screen_center: Vector2,

    focal_length: f32,
    distance_above_target: f32,
};

pub const TileSortEntry = struct {
    sort_key: f32,
    push_buffer_offset: u32,
};

fn getRenderEntityBasisPosition(
    camera_transform: CameraTransform,
    object_transform: ObjectTransform,
    original_position: Vector3,
) RenderEntityBasisResult {
    var timed_block = TimedBlock.beginFunction(@src(), .GetRenderEntityBasisPosition);
    defer timed_block.end();

    var result = RenderEntityBasisResult{};

    const position = original_position.xy().toVector3(0).plus(object_transform.offset_position);

    if (camera_transform.orthographic) {
        result.position = camera_transform.screen_center.plus(position.xy().scaledTo(camera_transform.meters_to_pixels));
        result.scale = camera_transform.meters_to_pixels;
        result.valid = true;
    } else {
        const offset_z: f32 = 0;
        var distance_above_target = camera_transform.distance_above_target;

        if (DebugInterface.debugIf(@src(), "Renderer_Camera_UseDebug")) {
            distance_above_target += DebugInterface.debugVariable(@src(), f32, "Renderer_Camera_DebugDistance");
        }

        const distance_to_position_z = distance_above_target - position.z();
        const near_clip_plane = 0.2;

        const raw_xy = position.xy().toVector3(1);

        if (distance_to_position_z > near_clip_plane) {
            const projected_xy = raw_xy.scaledTo((1.0 / distance_to_position_z) * camera_transform.focal_length);
            result.scale = projected_xy.z() * camera_transform.meters_to_pixels;
            result.position = camera_transform.screen_center.plus(projected_xy.xy().scaledTo(camera_transform.meters_to_pixels))
                .plus(Vector2.new(0, result.scale * offset_z));
            result.valid = true;
        }
    }

    result.sort_key =
        4096 * (2 * position.z() + 1 * @as(f32, @floatFromInt(@intFromBool(object_transform.upright)))) - position.y();

    return result;
}

pub const RenderGroup = extern struct {
    assets: *asset.Assets,
    global_alpha: f32,

    monitor_half_dim_in_meters: Vector2,

    camera_transform: CameraTransform,

    missing_resource_count: u32,
    renders_in_background: bool,

    generation_id: u32,
    commands: *RenderCommands,

    pub fn begin(
        assets: *asset.Assets,
        commands: *RenderCommands,
        generation_id: u32,
        renders_in_background: bool,
    ) RenderGroup {
        return .{
            .assets = assets,
            .renders_in_background = renders_in_background,
            .global_alpha = 1,
            .missing_resource_count = 0,
            .generation_id = generation_id,
            .commands = commands,
            .monitor_half_dim_in_meters = undefined,
            .camera_transform = undefined,
        };
    }

    pub fn end(self: *RenderGroup) void {
        _ = self;

        // TODO:
        // self.commands.missing_resource_count += self.missing_resource_count
    }

    pub fn allResourcesPresent(self: *RenderGroup) bool {
        return self.missing_resource_count == 0;
    }

    pub fn perspectiveMode(
        self: *RenderGroup,
        pixel_width: i32,
        pixel_height: i32,
        meters_to_pixels: f32,
        focal_length: f32,
        distance_above_target: f32,
    ) void {
        const pixels_to_meters: f32 = math.safeRatio1(1.0, meters_to_pixels);
        self.monitor_half_dim_in_meters = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)) * pixels_to_meters,
            0.5 * @as(f32, @floatFromInt(pixel_height)) * pixels_to_meters,
        );

        self.camera_transform.meters_to_pixels = meters_to_pixels;
        self.camera_transform.focal_length = focal_length;
        self.camera_transform.distance_above_target = distance_above_target;
        self.camera_transform.screen_center = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)),
            0.5 * @as(f32, @floatFromInt(pixel_height)),
        );
        self.camera_transform.orthographic = false;
    }

    pub fn orthographicMode(
        self: *RenderGroup,
        pixel_width: i32,
        pixel_height: i32,
        meters_to_pixels: f32,
    ) void {
        const pixels_to_meters: f32 = math.safeRatio1(1.0, meters_to_pixels);
        self.monitor_half_dim_in_meters = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)) * pixels_to_meters,
            0.5 * @as(f32, @floatFromInt(pixel_height)) * pixels_to_meters,
        );

        self.camera_transform.meters_to_pixels = meters_to_pixels;
        self.camera_transform.focal_length = 1;
        self.camera_transform.distance_above_target = 1;
        self.camera_transform.screen_center = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)),
            0.5 * @as(f32, @floatFromInt(pixel_height)),
        );
        self.camera_transform.orthographic = true;
    }

    fn pushRenderElement(self: *RenderGroup, comptime T: type, sort_key: f32) ?*T {
        var timed_block = TimedBlock.beginFunction(@src(), .PushRenderElement);
        defer timed_block.end();

        // This depends on the name of this file, if the file name changes the magic number may need to be adjusted.
        const entry_type: RenderEntryType = @field(RenderEntryType, @typeName(T)[12..]);
        return @ptrCast(@alignCast(self.pushRenderElement_(@sizeOf(T), entry_type, sort_key, @alignOf(T))));
    }

    fn pushRenderElement_(
        self: *RenderGroup,
        in_size: u32,
        entry_type: RenderEntryType,
        sort_key: f32,
        comptime alignment: u32,
    ) ?*anyopaque {
        var result: ?*anyopaque = null;
        const size = in_size + @sizeOf(RenderEntryHeader);
        const commands: *RenderCommands = self.commands;

        if ((commands.push_buffer_size + size) < commands.sort_entry_at - @sizeOf(TileSortEntry)) {
            const header: *RenderEntryHeader = @ptrCast(commands.push_buffer_base + commands.push_buffer_size);
            header.type = entry_type;

            const data_address = @intFromPtr(header) + @sizeOf(RenderEntryHeader);
            const aligned_address = std.mem.alignForward(usize, data_address, alignment);
            const aligned_offset = aligned_address - data_address;
            const aligned_size = size + aligned_offset;

            result = @ptrFromInt(aligned_address);

            commands.sort_entry_at -= @sizeOf(TileSortEntry);
            var sort_entry: *TileSortEntry = @ptrFromInt(@intFromPtr(commands.push_buffer_base) + commands.sort_entry_at);
            sort_entry.sort_key = sort_key;
            sort_entry.push_buffer_offset = commands.push_buffer_size;

            commands.push_buffer_size += @intCast(aligned_size);
            commands.push_buffer_element_count += 1;
        } else {
            unreachable;
        }

        return result;
    }

    // Renderer API.
    pub fn unproject(self: *RenderGroup, object_transform: ObjectTransform, pixels_xy: Vector2) Vector3 {
        var unprojected_xy: Vector2 = undefined;
        const camera_transform = self.camera_transform;

        if (camera_transform.orthographic) {
            unprojected_xy =
                pixels_xy.minus(camera_transform.screen_center).scaledTo(1.0 / camera_transform.meters_to_pixels);
        } else {
            const a: Vector2 =
                pixels_xy.minus(camera_transform.screen_center).scaledTo(1.0 / camera_transform.meters_to_pixels);
            unprojected_xy =
                a.scaledTo(
                (camera_transform.distance_above_target - object_transform.offset_position.z()) / camera_transform.focal_length,
            );
        }

        var result: Vector3 = unprojected_xy.toVector3(object_transform.offset_position.z());
        result = result.minus(object_transform.offset_position);

        return result;
    }

    pub fn unprojectOld(self: *RenderGroup, projected_xy: Vector2, distance_from_camera: f32) Vector2 {
        return projected_xy.scaledTo(distance_from_camera / self.camera_transform.focal_length);
    }

    pub fn getCameraRectangleAtDistance(self: *RenderGroup, distance_from_camera: f32) Rectangle2 {
        const raw_xy = self.unprojectOld(self.monitor_half_dim_in_meters, distance_from_camera);
        return Rectangle2.fromCenterHalfDimension(Vector2.zero(), raw_xy);
    }

    pub fn getCameraRectangleAtTarget(self: *RenderGroup) Rectangle2 {
        return self.getCameraRectangleAtDistance(self.camera_transform.distance_above_target);
    }

    pub fn pushClear(self: *RenderGroup, color: Color) void {
        if (self.pushRenderElement(RenderEntryClear, -std.math.floatMax(f32))) |entry| {
            entry.color = color;
        }
    }

    pub fn pushSaturation(self: *RenderGroup, level: f32) void {
        if (self.pushRenderElement(RenderEntrySaturation)) |entry| {
            entry.level = level;
        }
    }

    pub fn getBitmapDim(
        self: *RenderGroup,
        object_transform: ObjectTransform,
        bitmap: *const LoadedBitmap,
        height: f32,
        offset: Vector3,
        align_coefficient: f32,
    ) UsedBitmapDim {
        var dim = UsedBitmapDim{};

        dim.size = Vector2.new(height * bitmap.width_over_height, height);
        dim.alignment = bitmap.alignment_percentage.hadamardProduct(dim.size).scaledTo(align_coefficient);
        dim.position = offset.minus(dim.alignment.toVector3(0));
        dim.basis = getRenderEntityBasisPosition(self.camera_transform, object_transform, dim.position);

        return dim;
    }

    pub fn pushBitmap(
        self: *RenderGroup,
        object_transform: ObjectTransform,
        bitmap: *LoadedBitmap,
        height: f32,
        offset: Vector3,
        color: Color,
        align_coefficient: f32,
    ) void {
        const dim = self.getBitmapDim(object_transform, bitmap, height, offset, align_coefficient);

        if (dim.basis.valid) {
            if (self.pushRenderElement(RenderEntryBitmap, dim.basis.sort_key)) |entry| {
                entry.bitmap = bitmap;
                entry.position = dim.basis.position;
                entry.size = dim.size.scaledTo(dim.basis.scale);
                entry.color = color.scaledTo(self.global_alpha);
            }
        }
    }

    pub fn pushBitmapId(
        self: *RenderGroup,
        object_transform: ObjectTransform,
        opt_id: ?file_formats.BitmapId,
        height: f32,
        offset: Vector3,
        color: Color,
        opt_align_coefficient: ?f32,
    ) void {
        const align_coefficient: f32 = opt_align_coefficient orelse 1;
        if (opt_id) |id| {
            var opt_bitmap = self.assets.getBitmap(id, self.generation_id);

            if (self.renders_in_background and opt_bitmap == null) {
                self.assets.loadBitmap(id, true);
                opt_bitmap = self.assets.getBitmap(id, self.generation_id);
            }

            if (opt_bitmap) |bitmap| {
                self.pushBitmap(object_transform, bitmap, height, offset, color, align_coefficient);
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
        object_transform: ObjectTransform,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
    ) void {
        const position = offset.minus(dimension.scaledTo(0.5).toVector3(0));

        const basis = getRenderEntityBasisPosition(self.camera_transform, object_transform, position);
        if (basis.valid) {
            if (self.pushRenderElement(RenderEntryRectangle, basis.sort_key)) |entry| {
                entry.position = basis.position;
                entry.dimension = dimension.scaledTo(basis.scale);
                entry.color = color;
            }
        }
    }

    pub fn pushRectangle2(self: *RenderGroup, object_transform: ObjectTransform, rectangle: Rectangle2, z: f32, color: Color) void {
        self.pushRectangle(object_transform, rectangle.getDimension(), rectangle.toRectangle3(z, z).getCenter(), color);
    }

    pub fn pushRectangleOutline(
        self: *RenderGroup,
        object_transform: ObjectTransform,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
        thickness: f32,
    ) void {
        self.pushRectangle(
            object_transform,
            Vector2.new(dimension.x(), thickness),
            offset.minus(Vector3.new(0, 0.5 * dimension.y(), 0)),
            color,
        );
        self.pushRectangle(
            object_transform,
            Vector2.new(dimension.x(), thickness),
            offset.plus(Vector3.new(0, 0.5 * dimension.y(), 0)),
            color,
        );

        self.pushRectangle(
            object_transform,
            Vector2.new(thickness, dimension.y()),
            offset.minus(Vector3.new(0.5 * dimension.x(), 0, 0)),
            color,
        );
        self.pushRectangle(
            object_transform,
            Vector2.new(thickness, dimension.y()),
            offset.plus(Vector3.new(0.5 * dimension.x(), 0, 0)),
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
    ) void {
        _ = self;
        _ = origin;
        _ = x_axis;
        _ = y_axis;
        _ = color;
        _ = texture;
        _ = normal_map;
        _ = top;
        _ = middle;
        _ = bottom;
        // const basis = getRenderEntityBasisPosition(&entry.entity_basis, screen_dimension);
        //
        // if (basis.valid) {
        //     if (self.pushRenderElement(RenderEntryCoordinateSystem)) |entry| {
        //         entry.origin = origin;
        //         entry.x_axis = x_axis;
        //         entry.y_axis = y_axis;
        //         entry.color = color;
        //         entry.texture = texture;
        //         entry.normal_map = normal_map;
        //         entry.top = top;
        //         entry.middle = middle;
        //         entry.bottom = bottom;
        //     }
        // }
    }
};
