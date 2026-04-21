const renderer = @import("renderer.zig");
const math = @import("math.zig");

// Types.
const RenderGroup = renderer.RenderGroup;
const TexturedVertex = renderer.TexturedVertex;
const RendererTexture = renderer.RendererTexture;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;

pub const GeometryOutput = struct {
    vertices: [*]TexturedVertex,
    indices: [*]u16,
    base_index: u16,
};

pub const SpriteValues = struct {
    min_position: Vector3,
    scaled_x_axis: Vector3,
    scaled_y_axis: Vector3,
    z_bias: f32,

    pub fn forUpright(
        render_group: *RenderGroup,
        base_position: Vector3,
        world_dim: Vector2,
        align_percentage: Vector2,
        opt_x_axis: ?Vector2,
        opt_y_axis: ?Vector2,
        opt_t_camera_up: ?f32,
    ) SpriteValues {
        const x_axis2: Vector2 = opt_x_axis orelse Vector2.new(1, 0);
        const y_axis2: Vector2 = opt_y_axis orelse Vector2.new(0, 1);
        const t_camera_up: f32 = opt_t_camera_up orelse 0.5;

        const world_up: Vector3 = render_group.world_up;
        const camera_up: Vector3 = render_group.game_transform.y;
        const x_axis_hybrid: Vector3 = render_group.game_transform.x;
        const y_axis_hybrid: Vector3 = world_up.lerp(camera_up, t_camera_up).normalizeOrZero();

        const x_axis =
            x_axis_hybrid.scaledTo(x_axis2.x()).plus(y_axis_hybrid.scaledTo(x_axis2.y())).scaledTo(world_dim.x());
        const y_axis =
            x_axis_hybrid.scaledTo(y_axis2.x()).plus(y_axis_hybrid.scaledTo(y_axis2.y())).scaledTo(world_dim.y());

        const min_position: Vector3 = base_position.minus(
            x_axis.scaledTo(align_percentage.x()),
        ).minus(
            y_axis.scaledTo(align_percentage.y()),
        );

        return .{
            .min_position = min_position,
            .scaled_x_axis = x_axis,
            .scaled_y_axis = y_axis,
            // TODO: This is totally wrong because the sprite may be rotated, we're going to have to have a more
            // consistent way of computing ZBias per vertex.
            .z_bias = t_camera_up * render_group.world_up.dotProduct(camera_up) * world_dim.y(),
        };
    }
    pub fn worldPositionFromAlignPosition(self: *const SpriteValues, align_percentage: Vector2) Vector3 {
        const result: Vector3 = self.min_position.plus(
            self.scaled_x_axis.scaledTo(align_percentage.x()),
        ).plus(
            self.scaled_y_axis.scaledTo(align_percentage.y()),
        );

        return result;
    }
};

pub fn worldDimFromWorldHeight(texture: RendererTexture, height: f32) Vector2 {
    var width_over_height: f32 = 1;
    if (texture.height != 0) {
        width_over_height =
            @as(f32, @floatFromInt(texture.width)) / @as(f32, @floatFromInt(texture.height));
    }

    const result: Vector2 = .new(
        height * width_over_height,
        height,
    );

    return result;
}

pub fn writeQuad(
    out: *GeometryOutput,
    p0: Vector4,
    n0: Vector3,
    uv0: Vector2,
    c0: u32,
    p1: Vector4,
    n1: Vector3,
    uv1: Vector2,
    c1: u32,
    p2: Vector4,
    n2: Vector3,
    uv2: Vector2,
    c2: u32,
    p3: Vector4,
    n3: Vector3,
    uv3: Vector2,
    c3: u32,
    light_index: u16,
    texture_index: u16,
) void {
    const vert: [*]TexturedVertex = out.vertices;
    const index: [*]u16 = out.indices;

    vert[0].position = p3;
    vert[0].normal = n3;
    vert[0].uv = uv3;
    vert[0].color = c3;
    vert[0].light_index = light_index;
    vert[0].texture_index = texture_index;

    vert[1].position = p0;
    vert[1].normal = n0;
    vert[1].uv = uv0;
    vert[1].color = c0;
    vert[1].light_index = light_index;
    vert[1].texture_index = texture_index;

    vert[2].position = p2;
    vert[2].normal = n2;
    vert[2].uv = uv2;
    vert[2].color = c2;
    vert[2].light_index = light_index;
    vert[2].texture_index = texture_index;

    vert[3].position = p1;
    vert[3].normal = n1;
    vert[3].uv = uv1;
    vert[3].color = c1;
    vert[3].light_index = light_index;
    vert[3].texture_index = texture_index;

    const vi: u16 = out.base_index;
    index[0] = vi + 0;
    index[1] = vi + 1;
    index[2] = vi + 2;
    index[3] = vi + 1;
    index[4] = vi + 3;
    index[5] = vi + 2;

    out.vertices += 4;
    out.indices += 6;
    out.base_index += 4;
}
