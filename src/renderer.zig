const std = @import("std");
const shared = @import("shared.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const simd = @import("simd.zig");
const asset = @import("asset.zig");
const types = @import("types.zig");
const intrinsics = @import("intrinsics.zig");
const sort = @import("sort.zig");
const lighting = @import("lighting.zig");
const config = @import("config.zig");
const file_formats = shared.file_formats;
const debug_interface = @import("debug_interface.zig");

var show_lighting_samples: bool = false;

const INTERNAL = shared.INTERNAL;
const SLOW = shared.SLOW;
pub const ENTITY_VISIBLE_PIECE_COUNT = 4096;
var global_config = &@import("config.zig").global_config;

// Types.
const MemoryArena = memory.MemoryArena;
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
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const TicketMutex = types.TicketMutex;
const ArenaPushParams = shared.ArenaPushParams;
const LIGHT_DATA_WIDTH = lighting.LIGHT_DATA_WIDTH;
const LIGHT_LOOKUP_X = shared.LIGHT_LOOKUP_X;
const LIGHT_LOOKUP_Y = shared.LIGHT_LOOKUP_Y;
const LIGHT_LOOKUP_Z = shared.LIGHT_LOOKUP_Z;
const MAX_LIGHT_POWER = shared.MAX_LIGHT_POWER;

pub const LIGHT_POINTS_PER_CHUNK = 24;

const processTextureQueueType = fn (
    platform_renderer: *PlatformRenderer,
    texture_queue: *TextureQueue,
) callconv(.c) void;
const beginFrameType = fn (
    platform_renderer: *PlatformRenderer,
    window_width: i32,
    window_height: i32,
    draw_region: Rectangle2i,
) callconv(.c) ?*RenderCommands;
const endFrameType = fn (platform_renderer: *PlatformRenderer, frame: *RenderCommands) callconv(.c) void;

pub const PlatformRenderer = extern struct {
    processTextureQueue: *const processTextureQueueType = undefined,
    beginFrame: *const beginFrameType = undefined,
    endFrame: *const endFrameType = undefined,
};

pub const TexturedVertex = extern struct {
    position: Vector4,
    light_uv: Vector2,
    uv: Vector2, // TODO: Convert this down to 8-bit?
    color: u32, // Packed RGBA in memory order (ABGR in little endian).

    // TODO: Doesn't need to be per-vertex - move this into its own per-primitive buffer.
    normal: Vector3,
    light_index: u16 = 0,
};

const TextureGroup = struct {
    max_vertex_count: u32,
    texture_count: u32,
    dimension: [2]u32,
};

const MemoryLayout = struct {
    max_push_buffer_size: u32,
    texture_group_count: u32,
    texture_groups: [*]TextureGroup,
};

pub const RenderSettings = extern struct {
    width: u32 = 0,
    height: u32 = 0,
    depth_peel_count_hint: u32 = 0,
    multisampling_hint: bool = false,
    pixelation_hint: bool = false,
    multisample_debug: bool = false,
    lighting_disabled: bool = false,
    request_vsync: bool = true,

    pub fn equals(self: *RenderSettings, b: *RenderSettings) bool {
        const type_info = @typeInfo(@TypeOf(self.*));
        inline for (type_info.@"struct".fields) |struct_field| {
            if (@field(self, struct_field.name) != @field(b, struct_field.name)) {
                return false;
            }
        }
        return true;

        // return self.width == b.width and
        //     self.height == b.height and
        //     self.depth_peel_count_hint == b.depth_peel_count_hint and
        //     self.multisampling_hint == b.multisampling_hint and
        //     self.pixelation_hint == b.pixelation_hint;
    }
};

pub const RendererTexture = extern struct {
    handle: u64,

    pub const empty: RendererTexture = .{ .handle = 0 };
};

pub const LightingBox = extern struct {
    storage: [*]LightingPointState,
    position: Vector3,
    radius: Vector3,
    reflection_color: Color3,
    transparency: f32,
    emission: f32,
    light_index: [7]u16 = [1]u16{0} ** 7,
    child_count: u16 = 0,
    first_child_index: u16,
};

pub const LightingPointState = extern struct {
    last_pps: Color3,
    last_direction: Vector3,
};

pub const TextureOpList = extern struct {
    first: ?*TextureOp = null,
    last: ?*TextureOp = null,
};

pub const TextureOp = struct {
    next: ?*TextureOp = null,
    is_allocate: bool,

    op: union {
        allocate: TextureOpAllocate,
        deallocate: TextureOpDeallocate,
    },
};

pub const TextureQueue = extern struct {
    mutex: TicketMutex = undefined,

    pending: TextureOpList = .{},
    first_free: ?*TextureOp = null,
};

pub const RenderCommands = extern struct {
    settings: RenderSettings = .{},

    window_width: i32,
    window_height: i32,
    draw_region: Rectangle2i,

    max_push_buffer_size: u32 = 0,
    push_buffer_base: [*]u8 = undefined,
    push_buffer_data_at: [*]u8 = undefined,

    max_vertex_count: u32 = 0,
    vertex_count: u32 = 0,
    vertex_array: [*]TexturedVertex = undefined,
    quad_bitmaps: [*]RendererTexture = undefined,
    white_bitmap: RendererTexture = undefined,

    pub fn reset(self: *RenderCommands) void {
        self.push_buffer_data_at = self.push_buffer_base;
        self.vertex_count = 0;
    }
};

const TextureOpAllocate = struct {
    width: i32,
    height: i32,
    data: *anyopaque,
    result_texture: *RendererTexture,
};

const TextureOpDeallocate = struct {
    texture: RendererTexture,
};

pub const ManualSortKey = extern struct {
    always_in_front_of: u32 = 0,
    always_behind: u32 = 0,
};

pub const RenderEntryType = enum(u16) {
    RenderEntryTexturedQuads,
    RenderEntryFullClear,
    RenderEntryDepthClear,
    RenderEntryBeginPeels,
    RenderEntryEndPeels,
    RenderEntryLightingTransfer,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
    debug_tag: u32,
};

pub const RenderEntryFullClear = extern struct {
    clear_color: Color, // This color is NOT in linear space, it is in sRGB space directly.
};

pub const RenderEntryBeginPeels = extern struct {
    clear_color: Color, // This color is NOT in linear space, it is in sRGB space directly.
};

pub const RenderEntryTexturedQuads = extern struct {
    setup: RenderSetup,
    quad_count: u32,
    vertex_array_offset: u32, // Uses 4 vertices per quad.
};

pub const RenderEntryLightingTransfer = extern struct {
    light_data0: [*]Vector4,
    light_data1: [*]Vector4,
};

pub const RenderSetup = extern struct {
    clip_rect: Rectangle2 = .zero(),
    render_target_index: u32 = 0,
    projection: Matrix4x4 = .identity(),
    camera_position: Vector3 = .zero(),
    fog_direction: Vector3 = .zero(),
    fog_color: Color3 = .white(),
    fog_start_distance: f32 = 0,
    fog_end_distance: f32 = 0,
    clip_alpha_start_distance: f32 = 0,
    clip_alpha_end_distance: f32 = 0,
};

pub const FogParams = struct {
    direction: Vector3 = .zero(),
    start_distance: f32 = 0,
    end_distance: f32 = 0,

    pub const default: FogParams = .{};
};

pub const AlphaClipParams = struct {
    delta_start_distance: f32,
    delta_end_distance: f32,

    pub const default: AlphaClipParams = .{
        .delta_start_distance = -100,
        .delta_end_distance = -99,
    };
};

pub const TransientClipRect = extern struct {
    render_group: *RenderGroup,
    old_clip_rect: Rectangle2,

    pub fn init(render_group: *RenderGroup) TransientClipRect {
        const result: TransientClipRect = .{
            .render_group = render_group,
            .old_clip_rect = render_group.last_setup.clip_rect,
        };
        return result;
    }

    pub fn initWith(render_group: *RenderGroup, new_clip_rect: Rectangle2) TransientClipRect {
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
    UsesAlphaClip = 0x4,
    UsesFog = 0x8,
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
    pub fn getRenderEntityBasisPosition(
        object_transform: *const ObjectTransform,
        original_position: Vector3,
    ) Vector3 {
        const position: Vector3 = original_position.xy().toVector3(0).plus(object_transform.offset_position);
        return position;
    }
};

const PushBufferResult = extern struct {
    header: ?*RenderEntryHeader = null,
};

pub const CubeUVLayout = struct {
    bot_t0: Vector2,
    bot_t1: Vector2,
    bot_t2: Vector2,
    bot_t3: Vector2,

    // Order: +X, +Y, -X, -Y.
    mid_t0: [4]Vector2,
    mid_t1: [4]Vector2,
    mid_t2: [4]Vector2,
    mid_t3: [4]Vector2,

    top_t0: Vector2,
    top_t1: Vector2,
    top_t2: Vector2,
    top_t3: Vector2,

    pub const default: CubeUVLayout = .{
        .bot_t0 = .new(0, 0),
        .bot_t1 = .new(0.25, 0),
        .bot_t2 = .new(0.25, 0.25),
        .bot_t3 = .new(0, 0.25),

        .mid_t0 = [1]Vector2{.new(0, 0.25)} ** 4,
        .mid_t1 = [1]Vector2{.new(0.25, 0.25)} ** 4,
        .mid_t2 = [1]Vector2{.new(0.25, 0.75)} ** 4,
        .mid_t3 = [1]Vector2{.new(0, 0.75)} ** 4,

        .top_t0 = .new(0, 0.75),
        .top_t1 = .new(0.25, 0.75),
        .top_t2 = .new(0.25, 1),
        .top_t3 = .new(0, 1),
    };
};

const RenderTransform = extern struct {
    position: Vector3 = .zero(),
    x: Vector3 = .zero(),
    y: Vector3 = .zero(),
    z: Vector3 = .zero(),

    // This is both the world camera transform and the projection matrix combined.
    projection: MatrixInverse4x4 = .{},
};

pub const RenderGroupFlags = enum(u32) {
    ClearColor = 0x1,
    ClearDepth = 0x2,
    HandleTransparency = 0x4,

    pub const default: u32 =
        @intFromEnum(RenderGroupFlags.ClearColor) |
        @intFromEnum(RenderGroupFlags.ClearDepth) |
        @intFromEnum(RenderGroupFlags.HandleTransparency);
};

pub const RenderGroup = extern struct {
    assets: *asset.Assets,

    lighting_enabled: bool,
    light_bounds: Rectangle3,
    light_box_count: u32,
    light_boxes: [*]LightingBox,
    light_point_index: u16,

    debug_tag: u32,

    flags: u32,
    missing_resource_count: u32,

    world_up: Vector3,
    last_setup: RenderSetup = .{},
    game_transform: RenderTransform = .{},
    debug_transform: RenderTransform = .{},

    commands: *RenderCommands,

    current_quads: ?*RenderEntryTexturedQuads,

    pub fn beginDepthPeel_(self: *RenderGroup, color: Color) void {
        if (self.pushRenderElement(RenderEntryBeginPeels)) |entry| {
            // For sRGB mode, this color needs to be squared.
            entry.clear_color = color;
            self.last_setup.fog_color = .new(math.square(color.r()), math.square(color.g()), math.square(color.b()));
        }
    }

    pub fn endDepthPeel_(self: *RenderGroup) void {
        _ = self.pushRenderElement_(0, .RenderEntryEndPeels, @alignOf(u32));
    }

    pub fn pushDepthClear_(self: *RenderGroup) void {
        _ = self.pushRenderElement_(
            0,
            .RenderEntryDepthClear,
            @alignOf(u32),
        );
    }

    pub fn pushFullClear_(self: *RenderGroup, color: Color) void {
        if (self.pushRenderElement(RenderEntryFullClear)) |entry| {
            // For sRGB mode, this color needs to be squared.
            entry.clear_color = color;
            self.last_setup.fog_color = .new(math.square(color.r()), math.square(color.g()), math.square(color.b()));
        }
    }

    pub fn begin(
        assets: *asset.Assets,
        commands: *RenderCommands,
        opt_flags: ?u32,
        opt_clear_color: ?Color,
    ) RenderGroup {
        const flags: u32 = opt_flags orelse RenderGroupFlags.default;
        const clear_color: Color = opt_clear_color orelse .zero();

        var self: RenderGroup = .{
            .assets = assets,
            .debug_tag = undefined,
            .flags = flags,
            .missing_resource_count = 0,
            .commands = commands,
            .world_up = .new(0, 0, 1),
            .current_quads = undefined,
            .lighting_enabled = false,
            .light_bounds = .zero(),
            .light_box_count = 0,
            .light_boxes = undefined,
            .light_point_index = 0,
        };

        var initial_setup: RenderSetup = .{
            .fog_start_distance = 0,
            .fog_end_distance = 1,
            .clip_alpha_start_distance = 0,
            .clip_alpha_end_distance = 1,
            .fog_color = .new(math.square(0.15), math.square(0.15), math.square(0.15)),
            .clip_rect = .fromMinMax(.new(-1, -1), .new(1, 1)),
        };
        self.pushSetup(&initial_setup);

        if ((flags & @intFromEnum(RenderGroupFlags.HandleTransparency)) != 0) {
            std.debug.assert((flags & @intFromEnum(RenderGroupFlags.ClearColor)) != 0);
            std.debug.assert((flags & @intFromEnum(RenderGroupFlags.ClearDepth)) != 0);
            self.beginDepthPeel_(clear_color);
        } else {
            if ((flags & @intFromEnum(RenderGroupFlags.ClearColor)) != 0) {
                std.debug.assert((flags & @intFromEnum(RenderGroupFlags.ClearDepth)) != 0);

                self.pushFullClear_(clear_color);
            } else if ((flags & @intFromEnum(RenderGroupFlags.ClearDepth)) != 0) {
                self.pushDepthClear_();
            }
        }

        return self;
    }

    pub fn end(self: *RenderGroup) void {
        if ((self.flags & @intFromEnum(RenderGroupFlags.HandleTransparency)) != 0) {
            self.endDepthPeel_();
        }

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

    pub fn pushRenderElement(self: *RenderGroup, comptime T: type) ?*T {
        // TimedBlock.beginFunction(@src(), .PushRenderElement);
        // defer TimedBlock.endFunction(@src(), .PushRenderElement);

        // This depends on the name of this file, if the file name changes the magic number may need to be adjusted.
        const entry_type: RenderEntryType = @field(RenderEntryType, @typeName(T)[9..]);
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

    pub fn clipSpaceFromPixelSpace(pixel_dimension_x: f32, pixel_dimension_y: f32, screen_space_xy: Vector2) Vector2 {
        const pixel_dimensions: Vector2 = .new(pixel_dimension_x, pixel_dimension_y);
        const center: Vector2 = pixel_dimensions.scaledTo(0.5);

        var clip_space_xy: Vector2 = screen_space_xy.minus(center);
        _ = clip_space_xy.setX(clip_space_xy.x() * 2 / pixel_dimensions.x());
        _ = clip_space_xy.setY(clip_space_xy.y() * 2 / pixel_dimensions.y());

        return clip_space_xy;
    }

    // Renderer API.
    pub fn unproject(
        self: *RenderGroup,
        render_transform: *RenderTransform,
        clip_space_xy_in: Vector2,
        world_distance_from_camera_z: f32,
    ) Vector3 {
        _ = self;

        var probe_z: Vector4 =
            render_transform.position.minus(render_transform.z.scaledTo(world_distance_from_camera_z)).toVector4(1);
        probe_z = render_transform.projection.forward.timesV4(probe_z);

        var clip_space_xy: Vector2 = clip_space_xy_in;
        _ = clip_space_xy.setX(clip_space_xy.x() * probe_z.w());
        _ = clip_space_xy.setY(clip_space_xy.y() * probe_z.w());

        const clip: Vector4 = .new(clip_space_xy.x(), clip_space_xy.y(), probe_z.z(), probe_z.w());
        const world_position: Vector4 = render_transform.projection.inverse.timesV4(clip);

        return world_position.xyz();
    }

    pub fn getCameraRectangleAtDistance(self: *RenderGroup, distance_from_camera: f32) Rectangle3 {
        var transform: ObjectTransform = .defaultFlat();
        _ = transform.offset_position.setZ(-distance_from_camera);

        const min_corner = self.unproject(&self.game_transform, .new(-1, -1), distance_from_camera);
        const max_corner = self.unproject(&self.game_transform, .new(1, 1), distance_from_camera);

        return Rectangle3.fromMinMax(min_corner, max_corner);
    }

    pub fn getCameraRectangleAtTarget(self: *RenderGroup, z: f32) Rectangle3 {
        return self.getCameraRectangleAtDistance(z);
    }

    pub fn getCurrentQuads(self: *RenderGroup, quad_count: u32) ?*RenderEntryTexturedQuads {
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

        std.debug.assert(result != null);

        return result;
    }

    pub fn pushQuad(
        self: *RenderGroup,
        texture: RendererTexture,
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
        opt_light_count: ?u16,
        opt_light_index: ?u16,
    ) void {
        _ = opt_light_count;

        const emission = opt_emission orelse 0;
        std.debug.assert(emission >= 0);
        std.debug.assert(emission <= 1);

        const light_index = opt_light_index orelse 0;
        const commands: *RenderCommands = self.commands;
        const entry: ?*RenderEntryTexturedQuads = self.current_quads;
        std.debug.assert(entry != null);

        entry.?.quad_count += 1;

        const vertex_index: u32 = commands.vertex_count;
        commands.vertex_count += 4;
        std.debug.assert(vertex_index <= commands.max_vertex_count);

        commands.quad_bitmaps[vertex_index >> 2] = texture;
        var vert: [*]TexturedVertex = commands.vertex_array + vertex_index;

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
        vert[0].light_index = light_index;

        vert[1].position = p0;
        vert[1].normal = n0;
        vert[1].uv = uv0;
        vert[1].color = c0;
        vert[1].light_index = light_index;

        vert[2].position = p2;
        vert[2].normal = n2;
        vert[2].uv = uv2;
        vert[2].color = c2;
        vert[2].light_index = light_index;

        vert[3].position = p1;
        vert[3].normal = n1;
        vert[3].uv = uv1;
        vert[3].color = c1;
        vert[3].light_index = light_index;
    }

    fn pushQuadUnpackedColors(
        self: *RenderGroup,
        texture: RendererTexture,
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
        opt_light_count: ?u16,
        opt_light_index: ?u16,
    ) void {
        self.pushQuad(
            texture,
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
            opt_light_count,
            opt_light_index,
        );
    }

    pub fn pushLineSegment(
        self: *RenderGroup,
        texture: RendererTexture,
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
            texture,
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
            null,
            null,
        );
    }

    pub fn pushCubeBitmapId(
        self: *RenderGroup,
        opt_id: ?file_formats.BitmapId,
        position: Vector3,
        radius: Vector3,
        color: Color,
    ) void {
        if (opt_id) |id| {
            if (self.assets.getBitmap(id)) |bitmap| {
                self.pushCube(
                    bitmap.texture_handle,
                    position,
                    radius,
                    color,
                    null,
                    null,
                    null,
                );
            } else {
                self.assets.loadBitmap(id, false);
                self.missing_resource_count += 1;
            }
        }
    }

    pub fn pushCube(
        self: *RenderGroup,
        texture: RendererTexture,
        position: Vector3,
        radius: Vector3,
        color: Color,
        opt_uv_layout: ?*const CubeUVLayout,
        opt_emission: ?f32,
        opt_light_store_in: ?*LightingPointState,
    ) void {
        const uv_layout: *const CubeUVLayout = opt_uv_layout orelse &.default;
        const emission = opt_emission orelse 0;
        var opt_light_store: ?*LightingPointState = opt_light_store_in;

        std.debug.assert(emission >= 0);
        std.debug.assert(emission <= 1);

        if (self.getCurrentQuads(6) != null) {
            if (!self.lighting_enabled) {
                opt_light_store = null;
            }

            const nx: f32 = position.x() - radius.x();
            const px: f32 = position.x() + radius.x();
            const ny: f32 = position.y() - radius.y();
            const py: f32 = position.y() + radius.y();
            const nz: f32 = position.z() - radius.z();
            const pz: f32 = position.z() + radius.z();

            const p0: Vector4 = .new(nx, ny, pz, 0);
            const p1: Vector4 = .new(px, ny, pz, 0);
            const p2: Vector4 = .new(px, py, pz, 0);
            const p3: Vector4 = .new(nx, py, pz, 0);
            const p4: Vector4 = .new(nx, ny, nz, 0);
            const p5: Vector4 = .new(px, ny, nz, 0);
            const p6: Vector4 = .new(px, py, nz, 0);
            const p7: Vector4 = .new(nx, py, nz, 0);

            // const top_color: Color = storeColor(color);
            // const bottom_color: Color = .new(0, 0, 0, top_color.a());
            // const ct: Color = top_color.rgb().scaledTo(0.75).toColor(top_color.a());
            // const cb: Color = top_color.rgb().scaledTo(0.25).toColor(top_color.a());

            const top_color = storeColor(color);
            const bottom_color = top_color;
            const ct = top_color;
            const cb = top_color;

            var light_count: u16 = 0;
            var light_index: u16 = 0;
            if (opt_light_store) |light_store| {
                const min_corner: Vector3 = .new(nx, ny, nz);
                const max_corner: Vector3 = .new(px, py, pz);
                const cube_bounds: Rectangle3 = .fromMinMax(min_corner, max_corner);

                if (cube_bounds.intersects(&self.light_bounds)) {
                    light_count = LIGHT_POINTS_PER_CHUNK / 6;
                    light_index = self.light_point_index;
                    std.debug.assert(light_index != 0);
                    self.light_point_index += LIGHT_POINTS_PER_CHUNK;

                    std.debug.assert(self.light_point_index <= LIGHT_DATA_WIDTH);

                    var light_box: [*]LightingBox = self.light_boxes + self.light_box_count;
                    self.light_box_count += 1;
                    std.debug.assert(self.light_box_count <= LIGHT_DATA_WIDTH);

                    light_box[0].position = max_corner.plus(min_corner).scaledTo(0.5);
                    light_box[0].radius = max_corner.minus(min_corner).scaledTo(0.5);
                    light_box[0].transparency = 0;
                    light_box[0].emission = emission;
                    light_box[0].reflection_color = color.rgb();
                    light_box[0].storage = @ptrCast(light_store);
                    light_box[0].light_index[0] = light_index;
                    light_box[0].light_index[1] = light_index + 4;
                    light_box[0].light_index[2] = light_index + 8;
                    light_box[0].light_index[3] = light_index + 12;
                    light_box[0].light_index[4] = light_index + 16;
                    light_box[0].light_index[5] = light_index + 20;
                    light_box[0].light_index[6] = light_index + 24;
                    light_box[0].child_count = 0;
                }
            }

            // Negative X.
            self.pushQuadUnpackedColors(
                texture,
                p7,
                uv_layout.mid_t0[2],
                cb,
                p4,
                uv_layout.mid_t1[2],
                cb,
                p0, //
                uv_layout.mid_t2[2],
                ct,
                p3, //
                uv_layout.mid_t3[2],
                ct,
                opt_emission,
                light_count,
                light_index,
            );
            light_index += light_count;

            // Positive X.
            self.pushQuadUnpackedColors(
                texture,
                p1, //
                uv_layout.mid_t3[0],
                ct,
                p5,
                uv_layout.mid_t0[0],
                cb,
                p6,
                uv_layout.mid_t1[0],
                cb,
                p2, //
                uv_layout.mid_t2[0],
                ct,
                opt_emission,
                light_count,
                light_index,
            );
            light_index += light_count;

            // Negative Y.
            self.pushQuadUnpackedColors(
                texture,
                p4,
                uv_layout.mid_t0[3],
                cb,
                p5,
                uv_layout.mid_t1[3],
                cb,
                p1, //
                uv_layout.mid_t2[3],
                ct,
                p0, //
                uv_layout.mid_t3[3],
                ct,
                opt_emission,
                light_count,
                light_index,
            );
            light_index += light_count;

            // Positive Y.
            self.pushQuadUnpackedColors(
                texture,
                p2, //
                uv_layout.mid_t3[1],
                ct,
                p6,
                uv_layout.mid_t0[1],
                cb,
                p7,
                uv_layout.mid_t1[1],
                cb,
                p3, //
                uv_layout.mid_t2[1],
                ct,
                opt_emission,
                light_count,
                light_index,
            );
            light_index += light_count;

            // Negative Z.
            self.pushQuadUnpackedColors(
                texture,
                p7,
                uv_layout.bot_t0,
                bottom_color,
                p6,
                uv_layout.bot_t1,
                bottom_color,
                p5,
                uv_layout.bot_t2,
                bottom_color,
                p4,
                uv_layout.bot_t3,
                bottom_color,
                opt_emission,
                light_count,
                light_index,
            );
            light_index += light_count;

            // Positive Z.
            self.pushQuadUnpackedColors(
                texture,
                p0,
                uv_layout.top_t0,
                top_color,
                p1,
                uv_layout.top_t1,
                top_color,
                p2,
                uv_layout.top_t2,
                top_color,
                p3,
                uv_layout.top_t3,
                top_color,
                opt_emission,
                light_count,
                light_index,
            );
            light_index += light_count;
        }
    }

    pub fn pushRectangle(
        self: *RenderGroup,
        object_transform: *const ObjectTransform,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
    ) void {
        const position = offset.minus(dimension.scaledTo(0.5).toVector3(0));
        const basis_position = object_transform.getRenderEntityBasisPosition(position);

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
                null,
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
            const texture: RendererTexture = self.commands.white_bitmap;
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

            self.pushLineSegment(texture, p0, line_color, p1, line_color, thickness);
            self.pushLineSegment(texture, p0, line_color, p3, line_color, thickness);
            self.pushLineSegment(texture, p0, line_color, p4, line_color, thickness);

            self.pushLineSegment(texture, p2, line_color, p1, line_color, thickness);
            self.pushLineSegment(texture, p2, line_color, p3, line_color, thickness);
            self.pushLineSegment(texture, p2, line_color, p6, line_color, thickness);

            self.pushLineSegment(texture, p5, line_color, p1, line_color, thickness);
            self.pushLineSegment(texture, p5, line_color, p4, line_color, thickness);
            self.pushLineSegment(texture, p5, line_color, p6, line_color, thickness);

            self.pushLineSegment(texture, p7, line_color, p3, line_color, thickness);
            self.pushLineSegment(texture, p7, line_color, p4, line_color, thickness);
            self.pushLineSegment(texture, p7, line_color, p6, line_color, thickness);
        }
    }

    pub fn pushUpright(
        self: *RenderGroup,
        texture: RendererTexture,
        ground_position: Vector3,
        size: Vector2,
        opt_color: ?Color,
        opt_x_axis: ?Vector2,
        opt_y_axis: ?Vector2,
        opt_min_uv: ?Vector2,
        opt_max_uv: ?Vector2,
        opt_t_camera_up: ?f32,
    ) void {
        if (self.getCurrentQuads(1)) |_| {
            const color: Color = opt_color orelse .white();
            const x_axis2: Vector2 = opt_x_axis orelse Vector2.new(1, 0);
            const y_axis2: Vector2 = opt_y_axis orelse Vector2.new(0, 1);
            const min_uv: Vector2 = opt_min_uv orelse .new(0, 0);
            const max_uv: Vector2 = opt_max_uv orelse .new(1, 1);
            const t_camera_up: f32 = opt_t_camera_up orelse 0.5;

            const camera_up: Vector3 = self.game_transform.y;
            const x_axis_hybrid: Vector3 = self.game_transform.x;
            const y_axis_hybrid: Vector3 = self.world_up.lerp(camera_up, t_camera_up).normalizeOrZero();
            const z_bias: f32 = t_camera_up * self.world_up.dotProduct(camera_up) * size.y();

            const x_axis =
                x_axis_hybrid.scaledTo(x_axis2.x()).plus(y_axis_hybrid.scaledTo(x_axis2.y())).scaledTo(size.x());
            const y_axis =
                x_axis_hybrid.scaledTo(y_axis2.x()).plus(y_axis_hybrid.scaledTo(y_axis2.y())).scaledTo(size.y());

            const premultiplied_color: Color = storeColor(color);
            const vertex_color: u32 = premultiplied_color.scaledTo(255).packColorRGBA();

            const min_position: Vector3 = ground_position.minus(x_axis.scaledTo(0.5));
            const min_x_min_y: Vector4 = min_position.toVector4(0);
            const min_x_max_y: Vector4 = min_position.plus(y_axis).toVector4(z_bias);
            const max_x_min_y: Vector4 = min_position.plus(x_axis).toVector4(0);
            const max_x_max_y: Vector4 = min_position.plus(x_axis).plus(y_axis).toVector4(z_bias);

            self.pushQuad(
                texture,
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

    pub fn pushSprite(
        self: *RenderGroup,
        texture: RendererTexture,
        center_position: Vector3,
        size: Vector2,
        opt_color: ?Color,
        opt_x_axis: ?Vector3,
        opt_y_axis: ?Vector3,
        opt_min_uv: ?Vector2,
        opt_max_uv: ?Vector2,
    ) void {
        if (self.getCurrentQuads(1)) |_| {
            const color: Color = opt_color orelse .white();
            const x_axis: Vector3 = (opt_x_axis orelse Vector3.new(1, 0, 0)).scaledTo(size.x());
            const y_axis: Vector3 = (opt_y_axis orelse Vector3.new(0, 1, 0)).scaledTo(size.y());
            const min_uv: Vector2 = opt_min_uv orelse .new(0, 0);
            const max_uv: Vector2 = opt_max_uv orelse .new(1, 1);

            const premultiplied_color: Color = storeColor(color);
            const vertex_color: u32 = premultiplied_color.scaledTo(255).packColorRGBA();

            const min_position: Vector3 = center_position.minus(x_axis.scaledTo(0.5)).minus(y_axis.scaledTo(0.5));
            const min_x_min_y: Vector4 = min_position.toVector4(0);
            const min_x_max_y: Vector4 = min_position.plus(y_axis).toVector4(0);
            const max_x_min_y: Vector4 = min_position.plus(x_axis).toVector4(0);
            const max_x_max_y: Vector4 = min_position.plus(x_axis).plus(y_axis).toVector4(0);

            self.pushQuad(
                texture,
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

    pub fn pushSetup(
        self: *RenderGroup,
        new_setup: *RenderSetup,
    ) void {
        self.last_setup = new_setup.*;
        self.current_quads = null;
    }

    fn getClipSpacePoint(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        world_position: Vector3,
    ) Vector2 {
        var position: Vector4 =
            self.last_setup.projection.timesV(world_position.plus(object_transform.offset_position)).toVector4(1);
        _ = position.setXYZ(position.xyz().dividedByF(position.w()));

        return position.xy();
    }

    pub fn getClipRectByTransform(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        offset: Vector3,
        dimension: Vector2,
    ) Rectangle2 {
        const min_corner: Vector2 = self.getClipSpacePoint(object_transform, offset);
        const max_corner: Vector2 = self.getClipSpacePoint(object_transform, offset.plus(dimension.toVector3(0)));

        return .fromMinMax(min_corner, max_corner);
    }

    pub fn getClipRectByRectangle(
        self: *RenderGroup,
        object_transform: *ObjectTransform,
        rectangle: Rectangle2,
        z: f32,
    ) Rectangle2 {
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
        opt_fog_params: ?*FogParams,
        opt_alpha_clip_params: ?*AlphaClipParams,
    ) void {
        const near_clip_plane: f32 = opt_near_clip_plane orelse 0.1;
        const far_clip_plane: f32 = opt_far_clip_plane orelse 100;
        const fog_params: *const FogParams = opt_fog_params orelse &.default;
        const alpha_clip_params: *const AlphaClipParams = opt_alpha_clip_params orelse &.default;
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

        new_setup.fog_direction = fog_params.direction;
        new_setup.fog_start_distance = fog_params.start_distance;
        new_setup.fog_end_distance = fog_params.end_distance;
        new_setup.clip_alpha_start_distance = near_clip_plane + alpha_clip_params.delta_start_distance;
        new_setup.clip_alpha_end_distance = near_clip_plane + alpha_clip_params.delta_end_distance;

        render_transform.x = camera_x;
        render_transform.y = camera_y;
        render_transform.z = camera_z;
        render_transform.position = camera_position;

        new_setup.camera_position = camera_position;

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
};

pub fn storeColor(source: Color) Color {
    var dest: Color = .white();

    _ = dest.setA(source.a());
    _ = dest.setR(dest.a() * source.r());
    _ = dest.setG(dest.a() * source.g());
    _ = dest.setB(dest.a() * source.b());

    return dest;
}

fn unscaleAndBiasNormal(normal: Vector4) Vector4 {
    const inv_255: f32 = 1.0 / 255.0;

    return Vector4.new(
        -1.0 + 2.0 * (inv_255 * normal.x()),
        -1.0 + 2.0 * (inv_255 * normal.y()),
        -1.0 + 2.0 * (inv_255 * normal.z()),
        inv_255 * normal.w(),
    );
}

pub fn dequeuePending(queue: *TextureQueue) TextureOpList {
    queue.mutex.begin();
    const result: TextureOpList = queue.pending;
    queue.pending.first = null;
    queue.pending.last = null;
    queue.mutex.end();
    return result;
}

pub fn enqueueFree(queue: *TextureQueue, list: TextureOpList) void {
    if (list.last != null) {
        queue.mutex.begin();
        list.last.?.next = queue.first_free;
        queue.first_free = list.first;
        queue.mutex.end();
    }
}

pub fn addOp(queue: *TextureQueue, source: *const TextureOp) void {
    queue.mutex.begin();

    std.debug.assert(queue.first_free != null);

    const dest: *TextureOp = queue.first_free.?;
    queue.first_free = dest.next;

    dest.* = source.*;

    std.debug.assert(dest.next == null);

    if (queue.pending.last != null) {
        queue.pending.last.?.next = dest;
        queue.pending.last = dest;
    } else {
        queue.pending.first = dest;
        queue.pending.last = dest;
    }

    queue.mutex.end();
}

pub fn initTextureQueue(queue: *TextureQueue, memory_size: usize, texture_ops_memory: *anyopaque) void {
    const texture_op_count: usize = memory_size / @sizeOf(TextureOp);
    queue.first_free = @ptrCast(@alignCast(texture_ops_memory));

    var texture_op_index: usize = 0;
    while (texture_op_index < (texture_op_count - 1)) : (texture_op_index += 1) {
        const first_free: [*]TextureOp = @ptrCast(queue.first_free.?);
        var op: [*]TextureOp = first_free + texture_op_index;
        op[0].next = @ptrCast(first_free + texture_op_index + 1);
    }
}
