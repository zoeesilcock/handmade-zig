const std = @import("std");
const shared = @import("shared.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const renderer = @import("renderer.zig");
const lighting = @import("lighting.zig");
const asset = @import("asset.zig");
const file_formats = shared.file_formats;

// Types.
const MemoryArena = memory.MemoryArena;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle3 = math.Rectangle3;
const RenderGroup = renderer.RenderGroup;
const ObjectTransform = renderer.ObjectTransform;
const RenderEntryLightingTransfer = renderer.RenderEntryLightingTransfer;
const LoadedFont = asset.LoadedFont;
const LoadedBitmap = asset.LoadedBitmap;
const LightingTextures = lighting.LightingTextures;
const LightingPointState = renderer.LightingPointState;
const LightingBox = renderer.LightingBox;
const LIGHT_DATA_WIDTH = lighting.LIGHT_DATA_WIDTH;

pub const UsedBitmapDim = struct {
    basis_position: Vector3 = undefined,
    size: Vector2 = undefined,
    alignment: Vector2 = undefined,
    position: Vector3 = undefined,
};

pub fn getBitmapDim(
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

    if (false) {
        dim.size = Vector2.new(height * bitmap.width_over_height, height);
        dim.alignment = bitmap.alignment_percentage.hadamardProduct(dim.size).scaledTo(align_coefficient);
        _ = dim.position.setZ(offset.z());
        _ = dim.position.setXY(
            offset.xy().minus(x_axis.scaledTo(dim.alignment.x())).minus(y_axis.scaledTo(dim.alignment.y())),
        );
        dim.basis_position = object_transform.getRenderEntityBasisPosition(dim.position);
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

pub fn pushBitmap(
    group: *RenderGroup,
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
        const dim = getBitmapDim(
            object_transform,
            bitmap,
            height,
            offset,
            align_coefficient,
            x_axis2,
            y_axis2,
        );

        const size: Vector2 = dim.size;
        if (group.getCurrentQuads(1, bitmap.texture_handle) != null) {
            const min_position: Vector3 = dim.basis_position;
            var z_bias: f32 = 0;
            const premultiplied_color: Color = renderer.storeColor(color);
            var x_axis: Vector3 = x_axis2.toVector3(0).scaledTo(size.x());
            var y_axis: Vector3 = y_axis2.toVector3(0).scaledTo(size.y());

            if (object_transform.upright) {
                z_bias = 0.25 * height;
                // const x_axis0 = Vector3.new(x_axis2.x(), 0, x_axis2.y()).scaledTo(size.x());
                const y_axis0 = Vector3.new(y_axis2.x(), 0, y_axis2.y()).scaledTo(size.y());
                const x_axis1 =
                    group.game_transform.x.scaledTo(x_axis2.x())
                        .plus(group.game_transform.y.scaledTo(x_axis2.y())).scaledTo(size.x());
                const y_axis1 =
                    group.game_transform.x.scaledTo(y_axis2.x())
                        .plus(group.game_transform.y.scaledTo(y_axis2.y())).scaledTo(size.y());

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

            group.pushQuad(
                bitmap.texture_handle,
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
                null,
                null,
            );
        }
    }
}

pub fn pushBitmapId(
    group: *RenderGroup,
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
        if (group.assets.getBitmap(id)) |bitmap| {
            pushBitmap(
                group,
                object_transform,
                bitmap,
                height,
                offset,
                color,
                align_coefficient,
                opt_x_axis,
                opt_y_axis,
            );
        } else {
            group.assets.loadBitmap(id, false);
            group.missing_resource_count += 1;
        }
    }
}

pub fn pushFont(
    group: *RenderGroup,
    opt_id: ?file_formats.FontId,
) ?*LoadedFont {
    var opt_font: ?*LoadedFont = null;

    if (opt_id) |id| {
        opt_font = group.assets.getFont(id);

        if (opt_font == null) {
            group.assets.loadFont(id, false);
            group.missing_resource_count += 1;
        }
    }

    return opt_font;
}

pub fn pushCubeBitmapId(
    group: *RenderGroup,
    opt_id: ?file_formats.BitmapId,
    position: Vector3,
    radius: Vector3,
    color: Color,
    opt_uv_layout: ?renderer.CubeUVLayout,
    opt_emission: ?f32,
    opt_light_store_in: ?*LightingPointState,
) void {
    if (opt_id) |id| {
        if (group.assets.getBitmap(id)) |bitmap| {
            group.pushCube(
                bitmap.texture_handle,
                position,
                radius,
                color,
                opt_uv_layout,
                opt_emission,
                opt_light_store_in,
            );
        } else {
            group.assets.loadBitmap(id, false);
            group.missing_resource_count += 1;
        }
    }
}

pub fn pushCubeLight(
    group: *RenderGroup,
    position: Vector3,
    radius: Vector3,
    color: Color3,
    emission: f32,
    opt_light_store: ?*LightingPointState,
) void {
    group.pushCube(
        group.white_texture,
        position,
        radius,
        color.toColor(1),
        null,
        emission,
        opt_light_store,
    );
}

pub fn pushLighting(
    group: *RenderGroup,
    temp_arena: *MemoryArena,
    lighting_bounds: Rectangle3,
) *LightingTextures {
    std.debug.assert(group.light_box_count == 0);

    var source: *LightingTextures = temp_arena.pushStruct(LightingTextures, null);

    group.lighting_enabled = true;
    group.light_bounds = lighting_bounds;
    group.light_boxes = temp_arena.pushArray(LIGHT_DATA_WIDTH, LightingBox, null);
    group.light_point_index = 1;

    if (group.pushRenderElement(RenderEntryLightingTransfer)) |dest| {
        dest.light_data0 = &source.light_data0;
        dest.light_data1 = &source.light_data1;
    }

    return source;
}
