const shared = @import("shared.zig");
const types = @import("types.zig");
const intrinsics = @import("intrinsics.zig");
const renderer = @import("renderer.zig");
const wgl = @import("win32_opengl.zig");
const lighting = @import("lighting.zig");
const asset = @import("asset.zig");
const math = @import("math.zig");
const sort = @import("sort.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

pub const GL_NUM_EXTENSIONS = 0x821D;

pub const GL_TEXTURE_3D = 0x806F;
pub const GL_TEXTURE0 = 0x84C0;
pub const GL_TEXTURE1 = 0x84C1;
pub const GL_TEXTURE2 = 0x84C2;
pub const GL_TEXTURE3 = 0x84C3;
pub const GL_TEXTURE4 = 0x84C4;
pub const GL_TEXTURE5 = 0x84C5;
pub const GL_TEXTURE6 = 0x84C6;
pub const GL_TEXTURE7 = 0x84C7;
pub const GL_TEXTURE8 = 0x84C8;
pub const GL_TEXTURE9 = 0x84C9;
pub const GL_TEXTURE10 = 0x84CA;
pub const GL_TEXTURE11 = 0x84CB;
pub const GL_TEXTURE12 = 0x84CC;
pub const GL_TEXTURE13 = 0x84CD;
pub const GL_TEXTURE14 = 0x84CE;
pub const GL_TEXTURE15 = 0x84CF;
pub const GL_TEXTURE16 = 0x84D0;
pub const GL_TEXTURE17 = 0x84D1;
pub const GL_TEXTURE18 = 0x84D2;
pub const GL_TEXTURE19 = 0x84D3;
pub const GL_TEXTURE20 = 0x84D4;
pub const GL_TEXTURE21 = 0x84D5;
pub const GL_TEXTURE22 = 0x84D6;
pub const GL_TEXTURE23 = 0x84D7;
pub const GL_TEXTURE24 = 0x84D8;
pub const GL_TEXTURE25 = 0x84D9;
pub const GL_TEXTURE26 = 0x84DA;
pub const GL_TEXTURE27 = 0x84DB;
pub const GL_TEXTURE28 = 0x84DC;
pub const GL_TEXTURE29 = 0x84DD;
pub const GL_TEXTURE30 = 0x84DE;
pub const GL_TEXTURE31 = 0x84DF;

pub const GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB = 0x8242;
pub const GL_DEBUG_LOGGED_MESSAGES = 0x9145;
pub const GL_DEBUG_SEVERITY_HIGH = 0x9146;
pub const GL_DEBUG_SEVERITY_MEDIUM = 0x9147;
pub const GL_DEBUG_SEVERITY_LOW = 0x9148;
pub const GL_DEBUG_TYPE_MARKER = 0x8268;
pub const GL_DEBUG_TYPE_PUSH_GROUP = 0x8269;
pub const GL_DEBUG_TYPE_POP_GROUP = 0x826A;
pub const GL_DEBUG_SEVERITY_NOTIFICATION = 0x826B;

pub const GL_ARRAY_BUFFER = 0x8892;
pub const GL_ELEMENT_ARRAY_BUFFER = 0x8893;
pub const GL_STREAM_DRAW = 0x88E0;
pub const GL_STREAM_READ = 0x88E1;
pub const GL_STREAM_COPY = 0x88E2;
pub const GL_STATIC_DRAW = 0x88E4;
pub const GL_STATIC_READ = 0x88E5;
pub const GL_STATIC_COPY = 0x88E6;
pub const GL_DYNAMIC_DRAW = 0x88E8;
pub const GL_DYNAMIC_READ = 0x88E9;
pub const GL_DYNAMIC_COPY = 0x88EA;
pub const GL_TEXTURE_2D_ARRAY = 0x8C1A;

pub const GL_FRAMEBUFFER_SRGB = 0x8DB9;
pub const GL_SRGB8_ALPHA8 = 0x8C43;
pub const GL_CLAMP_TO_EDGE = 0x812F;

pub const GL_SHADING_LANGUAGE_VERSION = 0x8B8C;
pub const GL_FRAGMENT_SHADER = 0x8B30;
pub const GL_VERTEX_SHADER = 0x8B31;
pub const GL_COMPILE_STATUS = 0x8B81;
pub const GL_LINK_STATUS = 0x8B82;
pub const GL_VALIDATE_STATUS = 0x8B83;

pub const GL_FRAMEBUFFER = 0x8D40;
pub const GL_READ_FRAMEBUFFER = 0x8CA8;
pub const GL_DRAW_FRAMEBUFFER = 0x8CA9;
pub const GL_COLOR_ATTACHMENT0 = 0x8CE0;
pub const GL_COLOR_ATTACHMENT1 = 0x8CE1;
pub const GL_COLOR_ATTACHMENT2 = 0x8CE2;
pub const GL_COLOR_ATTACHMENT3 = 0x8CE3;
pub const GL_COLOR_ATTACHMENT4 = 0x8CE4;
pub const GL_COLOR_ATTACHMENT5 = 0x8CE5;
pub const GL_COLOR_ATTACHMENT6 = 0x8CE6;
pub const GL_COLOR_ATTACHMENT7 = 0x8CE7;
pub const GL_COLOR_ATTACHMENT8 = 0x8CE8;
pub const GL_COLOR_ATTACHMENT9 = 0x8CE9;
pub const GL_COLOR_ATTACHMENT10 = 0x8CEA;
pub const GL_COLOR_ATTACHMENT11 = 0x8CEB;
pub const GL_COLOR_ATTACHMENT12 = 0x8CEC;
pub const GL_COLOR_ATTACHMENT13 = 0x8CED;
pub const GL_COLOR_ATTACHMENT14 = 0x8CEE;
pub const GL_COLOR_ATTACHMENT15 = 0x8CEF;
pub const GL_COLOR_ATTACHMENT16 = 0x8CF0;
pub const GL_COLOR_ATTACHMENT17 = 0x8CF1;
pub const GL_COLOR_ATTACHMENT18 = 0x8CF2;
pub const GL_COLOR_ATTACHMENT19 = 0x8CF3;
pub const GL_COLOR_ATTACHMENT20 = 0x8CF4;
pub const GL_COLOR_ATTACHMENT21 = 0x8CF5;
pub const GL_COLOR_ATTACHMENT22 = 0x8CF6;
pub const GL_COLOR_ATTACHMENT23 = 0x8CF7;
pub const GL_COLOR_ATTACHMENT24 = 0x8CF8;
pub const GL_COLOR_ATTACHMENT25 = 0x8CF9;
pub const GL_COLOR_ATTACHMENT26 = 0x8CFA;
pub const GL_COLOR_ATTACHMENT27 = 0x8CFB;
pub const GL_COLOR_ATTACHMENT28 = 0x8CFC;
pub const GL_COLOR_ATTACHMENT29 = 0x8CFD;
pub const GL_COLOR_ATTACHMENT30 = 0x8CFE;
pub const GL_COLOR_ATTACHMENT31 = 0x8CFF;
pub const GL_DEPTH_ATTACHMENT = 0x8D00;
pub const GL_FRAME_BUFFER_COMPLETE = 0x8CD5;

pub const GL_DEPTH_COMPONENT16 = 0x81A5;
pub const GL_DEPTH_COMPONENT24 = 0x81A6;
pub const GL_DEPTH_COMPONENT32 = 0x81A7;
pub const GL_DEPTH_COMPONENT32F = 0x8CAC;
pub const GL_RGBA32F = 0x8814;
pub const GL_RGB32F = 0x8815;
pub const GL_RGBA16F = 0x881A;
pub const GL_RGB16F = 0x881B;
pub const GL_R8 = 0x8229;
pub const GL_R16 = 0x822A;
pub const GL_RG8 = 0x822B;
pub const GL_RG16 = 0x822C;
pub const GL_R16F = 0x822D;
pub const GL_R32F = 0x822E;
pub const GL_RG16F = 0x822F;
pub const GL_RG32F = 0x8230;
pub const GL_R8I = 0x8231;
pub const GL_R8UI = 0x8232;
pub const GL_R16I = 0x8233;
pub const GL_R16UI = 0x8234;
pub const GL_R32I = 0x8235;
pub const GL_R32UI = 0x8236;
pub const GL_RG8I = 0x8237;
pub const GL_RG8UI = 0x8238;
pub const GL_RG16I = 0x8239;
pub const GL_RG16UI = 0x823A;
pub const GL_RG32I = 0x823B;
pub const GL_RED_INTEGER = 0x8D94;
pub const GL_GREEN_INTEGER = 0x8D95;
pub const GL_BLUE_INTEGER = 0x8D96;

pub const GL_MULTISAMPLE = 0x809D;
pub const GL_SAMPLE_ALPHA_TO_COVERAGE = 0x809E;
pub const GL_SAMPLE_ALPHA_TO_ONE = 0x809F;
pub const GL_SAMPLE_COVERAGE = 0x80A0;
pub const GL_SAMPLE_BUFFERS = 0x80A8;
pub const GL_SAMPLES = 0x80A9;
pub const GL_SAMPLE_COVERAGE_VALUE = 0x80AA;
pub const GL_SAMPLE_COVERAGE_INVERT = 0x80AB;
pub const GL_TEXTURE_2D_MULTISAMPLE = 0x9100;
pub const GL_MAX_SAMPLES = 0x8D57;
pub const GL_MAX_COLOR_TEXTURE_SAMPLES = 0x910E;
pub const GL_MAX_DEPTH_TEXTURE_SAMPLES = 0x910F;
pub const GL_MAX_COLOR_ATTACHMENTS = 0x8CDF;
pub const GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS = 0x8B4D;
pub const GL_TEXTURE_MIN_LOD = 0x813A;
pub const GL_TEXTURE_MAX_LOD = 0x813B;

const ALL_COLOR_ATTACHMENTS = [_]u32{
    GL_COLOR_ATTACHMENT0,
    GL_COLOR_ATTACHMENT1,
    GL_COLOR_ATTACHMENT2,
    GL_COLOR_ATTACHMENT3,
    GL_COLOR_ATTACHMENT4,
    GL_COLOR_ATTACHMENT5,
    GL_COLOR_ATTACHMENT6,
    GL_COLOR_ATTACHMENT7,
    GL_COLOR_ATTACHMENT8,
    GL_COLOR_ATTACHMENT9,
    GL_COLOR_ATTACHMENT10,
    GL_COLOR_ATTACHMENT11,
    GL_COLOR_ATTACHMENT12,
    GL_COLOR_ATTACHMENT13,
    GL_COLOR_ATTACHMENT14,
    GL_COLOR_ATTACHMENT15,
    GL_COLOR_ATTACHMENT16,
    GL_COLOR_ATTACHMENT17,
    GL_COLOR_ATTACHMENT18,
    GL_COLOR_ATTACHMENT19,
    GL_COLOR_ATTACHMENT20,
    GL_COLOR_ATTACHMENT21,
    GL_COLOR_ATTACHMENT22,
    GL_COLOR_ATTACHMENT23,
    GL_COLOR_ATTACHMENT24,
    GL_COLOR_ATTACHMENT25,
    GL_COLOR_ATTACHMENT26,
    GL_COLOR_ATTACHMENT27,
    GL_COLOR_ATTACHMENT28,
    GL_COLOR_ATTACHMENT29,
    GL_COLOR_ATTACHMENT30,
    GL_COLOR_ATTACHMENT31,
};

// Build options.
const INTERNAL = shared.INTERNAL;

const ALLOW_GPU_SRGB = false;
const DEPTH_COMPONENT_TYPE = GL_DEPTH_COMPONENT32F;

const PlatformRenderer = renderer.PlatformRenderer;
const RenderCommands = renderer.RenderCommands;
const RenderSettings = renderer.RenderSettings;
const TexturedVertex = renderer.TexturedVertex;
const RendererTexture = renderer.RendererTexture;
const RenderGroup = renderer.RenderGroup;
const RenderSetup = renderer.RenderSetup;
const TextureQueue = renderer.TextureQueue;
const TextureOpList = renderer.TextureOpList;
const RenderEntryHeader = renderer.RenderEntryHeader;
const RenderEntryTexturedQuads = renderer.RenderEntryTexturedQuads;
const RenderEntryLightingTransfer = renderer.RenderEntryLightingTransfer;
const RenderEntryBeginPeels = renderer.RenderEntryBeginPeels;
const RenderEntryFullClear = renderer.RenderEntryFullClear;
const RenderEntryBitmap = renderer.RenderEntryBitmap;
const RenderEntryCube = renderer.RenderEntryCube;
const RenderEntryRectangle = renderer.RenderEntryRectangle;
const RenderEntrySaturation = renderer.RenderEntrySaturation;
const LIGHT_DATA_WIDTH = lighting.LIGHT_DATA_WIDTH;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Rectangle2 = math.Rectangle2;
const Rectangle2i = math.Rectangle2i;
const Matrix4x4 = math.Matrix4x4;
const TimedBlock = debug_interface.TimedBlock;
const TextureOp = renderer.TextureOp;
const SpriteFlag = renderer.SpriteFlag;
const SpriteEdge = renderer.SpriteEdge;

const debug_color_table = shared.debug_color_table;
var global_config = &@import("config.zig").global_config;

// TODO: How do we avoid having this import here?
fn glDebugProc(
    source: u32,
    message_type: u32,
    id: u32,
    severity: u32,
    length: i32,
    message: [*]const u8,
    user_param: ?*const anyopaque,
) callconv(.winapi) void {
    _ = message_type;
    _ = id;
    _ = source;
    _ = user_param;

    if (severity == GL_DEBUG_SEVERITY_HIGH) {
        std.debug.panic("GLDebugMessage, severity: {d}, message: {s}", .{
            severity,
            message[0..@intCast(length)],
        });
    } else {
        // std.log.info("GLDebugMessage: {s}", .{message[0..@intCast(length)]});
    }
}

// TODO: How do we import OpenGL on other platforms here?
pub const gl = @import("win32").graphics.open_gl;
const platform = @import("win32_opengl.zig");

const OpenGLProgramCommon = extern struct {
    program_handle: u32 = 0,

    vert_position_id: i32 = 0,
    vert_normal_id: i32 = 0,
    vert_uv_id: i32 = 0,
    vert_color_id: i32 = 0,
    vert_light_index_id: i32 = 0,
    vert_texture_index_id: i32 = 0,

    sampler_count: u32,
    samplers: [16]i32 = [1]i32{0} ** 16,
};

const ZBiasProgram = extern struct {
    common: OpenGLProgramCommon,

    transform_id: i32 = 0,
    camera_position_id: i32 = 0,
    fog_direction_id: i32 = 0,
    fog_color_id: i32 = 0,
    fog_start_distance_id: i32 = 0,
    fog_end_distance_id: i32 = 0,
    clip_alpha_start_distance_id: i32 = 0,
    clip_alpha_end_distance_id: i32 = 0,
    alpha_threshold_id: i32 = 0,
};

const ResolveMultisampleProgram = extern struct {
    common: OpenGLProgramCommon,

    sample_count_id: i32 = 0,
};

const MultiGridLightDownProgram = extern struct {
    common: OpenGLProgramCommon,

    source_uv_step: i32 = 0,
};

const ColorHandleType = enum(u32) {
    SurfaceReflection, // Reflection RGB, coverage A.
    // Emission, // Emission RGB, spread A.
    // NormalPositionLight, // Nx, Ny. TODO: Lp0, Lp1.
};

const COLOR_HANDLE_COUNT = @typeInfo(ColorHandleType).@"enum".fields.len;

const Framebuffer = extern struct {
    framebuffer_handle: u32 = 0,
    color_handle: [COLOR_HANDLE_COUNT]u32 = undefined,
    depth_handle: u32 = 0,
};

const FramebufferFlags = enum(u32) {
    Multisampled = 0x1,
    Filtered = 0x2,
    Depth = 0x4,
    Float = 0x8,
};

const LightBuffer = extern struct {
    width: i32 = 0,
    height: i32 = 0,

    write_all_framebuffer: u32 = 0,
    write_emission_framebuffer: u32 = 0,

    // These are all 3-element textures.
    front_emission_texture: u32 = 0,
    back_emission_texture: u32 = 0,
    surface_color_texture: u32 = 0,
    normal_position_texture: u32 = 0, // This is Normal.x, Normal.z, Depth.
};

pub const OpenGL = extern struct {
    header: PlatformRenderer = .{},

    current_settings: RenderSettings = .{},

    max_color_attachments: i32 = 0,
    max_samplers_per_shader: i32 = 0,

    shader_sim_tex_read_srgb: bool = true,
    shader_sim_tex_write_srgb: bool = true,

    max_multi_sample_count: i32 = 0,
    supports_srgb_frame_buffer: bool = false,

    default_sprite_texture_format: i32 = 0,
    default_framebuffer_texture_format: i32 = 0,

    vertex_buffer: u32 = 0,
    index_buffer: u32 = 0,
    screen_fill_vertex_buffer: u32 = 0,

    reserved_blit_texture: u32 = 0,

    texture_array: u32 = 0,

    multisampling: bool = false,
    depth_peel_count: u32 = 0,

    push_buffer_memory: [65536]u8 = undefined,
    vertex_array: [*]TexturedVertex = undefined,
    index_array: [*]u16 = undefined,
    bitmap_array: [*]RendererTexture = undefined,

    max_quad_texture_count: u32,
    max_texture_count: u32,
    max_vertex_count: u32,
    max_index_count: u32,

    max_special_texture_count: u32,
    special_texture_handles: [*]u32 = undefined,

    // Dynamic resources that get recreated when settings change.
    resolve_frame_buffer: Framebuffer = .{},
    depth_peel_buffers: [16]Framebuffer = [1]Framebuffer{.{}} ** 16,
    depth_peel_resolve_buffers: [16]Framebuffer = [1]Framebuffer{.{}} ** 16,
    z_bias_no_depth_peel: ZBiasProgram = undefined, // Pass 0.
    z_bias_depth_peel: ZBiasProgram = undefined, // Passes 1 through n.
    peel_composite: OpenGLProgramCommon = undefined, // Composite all passes.
    final_stretch: OpenGLProgramCommon = undefined,
    resolve_multisample: ResolveMultisampleProgram = undefined,

    light_data0: u32 = 0,
    light_data1: u32 = 0,

    light_buffer_count: u32 = 0,
    light_buffers: [12]LightBuffer = undefined,

    debug_light_buffer_index: i32 = 0,
    debug_light_buffer_texture_index: i32 = 0,

    render_commands: RenderCommands,
};

pub const Info = struct {
    is_modern_context: bool,
    vendor: ?*const u8,
    renderer: ?*const u8,
    version: ?*const u8,
    shader_language_version: ?*const u8 = undefined,

    gl_ext_texture_srgb: bool = false,
    gl_ext_framebuffer_srgb: bool = false,
    gl_arb_framebuffer_object: bool = false,

    pub fn get(is_modern_context: bool) Info {
        var result: Info = .{
            .is_modern_context = is_modern_context,
            .vendor = gl.glGetString(gl.GL_VENDOR),
            .renderer = gl.glGetString(gl.GL_RENDERER),
            .version = gl.glGetString(gl.GL_VERSION),
        };

        if (is_modern_context) {
            result.shader_language_version = gl.glGetString(GL_SHADING_LANGUAGE_VERSION);
        } else {
            result.shader_language_version = @ptrCast("(none)");
        }

        var extension_count: i32 = 0;
        gl.glGetIntegerv(GL_NUM_EXTENSIONS, &extension_count);

        var extension_index: u32 = 0;
        while (extension_index < extension_count) : (extension_index += 1) {
            if (platform.optGLGetStringi.?(gl.GL_EXTENSIONS, extension_index)) |extension_name| {
                if (shared.stringsAreEqual(@ptrCast(extension_name), "GL_EXT_texture_sRGB")) {
                    result.gl_ext_texture_srgb = true;
                } else if (shared.stringsAreEqual(@ptrCast(extension_name), "GL_EXT_framebuffer_sRGB")) {
                    result.gl_ext_framebuffer_srgb = true;
                } else if (shared.stringsAreEqual(@ptrCast(extension_name), "GL_ARB_framebuffer_sRGB")) {
                    result.gl_ext_framebuffer_srgb = true;
                } else if (shared.stringsAreEqual(@ptrCast(extension_name), "GL_ARB_framebuffer_object")) {
                    result.gl_arb_framebuffer_object = true;
                }
            }
        }

        const opt_major_at: ?[*]const u8 = @ptrCast(result.version);
        var opt_minor_at: ?[*]const u8 = null;
        var at: [*]const u8 = @ptrCast(result.version);
        while (at[0] != 0) : (at += 1) {
            if (at[0] == '.') {
                opt_minor_at = at + 1;
                break;
            }
        }

        var major: i32 = 1;
        var minor: i32 = 0;
        if (opt_major_at) |major_at| {
            if (opt_minor_at) |minor_at| {
                major = shared.i32FromZ(major_at);
                minor = shared.i32FromZ(minor_at);
            }
        }

        if (major > 2 or (major == 2 and minor >= 1)) {
            result.gl_ext_texture_srgb = true;
        }

        return result;
    }
};

fn colorUB(color: u32) void {
    gl.glColor4ub(
        @intCast((color >> 0) & 0xFF),
        @intCast((color >> 8) & 0xFF),
        @intCast((color >> 16) & 0xFF),
        @intCast((color >> 24) & 0xFF),
    );
}

pub fn init(open_gl: *OpenGL, info: Info, framebuffer_supports_sRGB: bool) void {
    open_gl.current_settings.depth_peel_count_hint = 4;
    open_gl.current_settings.multisampling_hint = true;
    open_gl.current_settings.pixelation_hint = false;
    open_gl.current_settings.multisample_debug = false;

    open_gl.shader_sim_tex_read_srgb = true;
    open_gl.shader_sim_tex_write_srgb = true;

    gl.glGenTextures(1, &open_gl.reserved_blit_texture);

    gl.glGetIntegerv(GL_MAX_COLOR_ATTACHMENTS, &open_gl.max_color_attachments);
    gl.glGetIntegerv(GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS, &open_gl.max_samplers_per_shader);

    gl.glGetIntegerv(GL_MAX_COLOR_TEXTURE_SAMPLES, &open_gl.max_multi_sample_count);
    if (open_gl.max_multi_sample_count > 16) {
        open_gl.max_multi_sample_count = 16;
    }

    open_gl.default_sprite_texture_format = gl.GL_RGBA8;
    open_gl.default_framebuffer_texture_format = gl.GL_RGBA16;

    if (ALLOW_GPU_SRGB) {
        if (info.gl_ext_texture_srgb) {
            open_gl.default_sprite_texture_format = GL_SRGB8_ALPHA8;
            open_gl.shader_sim_tex_read_srgb = false;
        }

        if (framebuffer_supports_sRGB and info.gl_ext_framebuffer_srgb) {
            // if (platform.optGLTexImage2DMultiSample) |glTexImage2DMultisample| {
            // var test_texture: u32 = undefined;
            // gl.glGenTextures(1, &test_texture);
            // gl.glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, test_texture);
            //
            // _ = gl.glGetError();
            // _ = glTexImage2DMultisample(
            //     GL_TEXTURE_2D_MULTISAMPLE,
            //     open_gl.max_multi_sample_count,
            //     GL_SRGB8_ALPHA8,
            //     1920,
            //     1080,
            //     false,
            // );
            //
            // if (gl.glGetError() == gl.GL_NO_ERROR) {
            {
                open_gl.default_framebuffer_texture_format = GL_SRGB8_ALPHA8;
                gl.glEnable(GL_FRAMEBUFFER_SRGB);
                open_gl.shader_sim_tex_write_srgb = false;
            }

            // gl.glDeleteTextures(1, &test_texture);
            // gl.glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0);
            // }
        }
    }

    if (INTERNAL) {
        if (platform.optGLDebugMessageCallbackARB) |glDebugMessageCallbackARB| {
            gl.glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB);
            glDebugMessageCallbackARB(&glDebugProc, null);
        }
    }

    var dummy_vertex_array: u32 = 0;
    platform.optGLGenVertexArrays.?(1, &dummy_vertex_array);
    platform.optGLBindVertexArray.?(dummy_vertex_array);

    platform.optGLGenBuffers.?(1, &open_gl.vertex_buffer);
    platform.optGLGenBuffers.?(1, &open_gl.index_buffer);

    {
        platform.optGLGenBuffers.?(1, &open_gl.screen_fill_vertex_buffer);
        platform.optGLBindBuffer.?(GL_ARRAY_BUFFER, open_gl.screen_fill_vertex_buffer);
        var vertices: [4]TexturedVertex = [_]TexturedVertex{
            .{ .position = .new(-1, 1, 0, 1), .normal = .zero(), .uv = .new(0, 1), .light_uv = .zero(), .color = 0xffffffff },
            .{ .position = .new(-1, -1, 0, 1), .normal = .zero(), .uv = .new(0, 0), .light_uv = .zero(), .color = 0xffffffff },
            .{ .position = .new(1, 1, 0, 1), .normal = .zero(), .uv = .new(1, 1), .light_uv = .zero(), .color = 0xffffffff },
            .{ .position = .new(1, -1, 0, 1), .normal = .zero(), .uv = .new(1, 0), .light_uv = .zero(), .color = 0xffffffff },
        };
        platform.optGLBufferData.?(
            GL_ARRAY_BUFFER,
            vertices.len * @sizeOf(TexturedVertex),
            &vertices,
            GL_STATIC_DRAW,
        );
    }

    gl.glGenTextures(1, &open_gl.texture_array);
    gl.glBindTexture(GL_TEXTURE_2D_ARRAY, open_gl.texture_array);

    if (true) {
        platform.optGLTexStorage3D.?(
            GL_TEXTURE_2D_ARRAY,
            1,
            @intCast(open_gl.default_sprite_texture_format),
            renderer.TEXTURE_ARRAY_DIM,
            renderer.TEXTURE_ARRAY_DIM,
            open_gl.max_texture_count,
        );
        std.debug.assert(gl.glGetError() == gl.GL_NO_ERROR);
    } else {
        platform.optGLTexImage3D.?(
            GL_TEXTURE_2D_ARRAY,
            0,
            open_gl.default_sprite_texture_format,
            512,
            512,
            open_gl.max_texture_count,
            0,
            gl.GL_BGRA_EXT,
            gl.GL_UNSIGNED_BYTE,
            null,
        );
    }

    gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    gl.glGenTextures(@intCast(open_gl.max_special_texture_count), @ptrCast(open_gl.special_texture_handles));

    var handle_index: u32 = 0;
    while (handle_index < open_gl.max_special_texture_count) : (handle_index += 1) {
        const handle: u32 = open_gl.special_texture_handles[handle_index];
        gl.glBindTexture(GL_TEXTURE_2D_ARRAY, handle);

        gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
}

const shader_header_code =
    \\// Header code
    \\#define MaxLightIntensity 10
    \\#define LengthSq(a) dot(a, a)
    \\
    \\float clamp01MapToRange(float min, float max, float value) {
    \\  float range = max - min;
    \\  float result = clamp((value - min) / range, 0.0, 1.0);
    \\  return result;
    \\}
    \\
    \\vec2 PackNormal2(vec2 Normal)
    \\{
    \\  vec2 Result;
    \\  Result.x = 0.5f + 0.5f * Normal.x;
    \\  Result.y = 0.5f + 0.5f * Normal.y;
    \\  return Result;
    \\}
    \\
    \\vec2 UnpackNormal2(vec2 Normal)
    \\{
    \\  vec2 Result;
    \\  Result.x = -1.0f + 2.0f * Normal.x;
    \\  Result.y = -1.0f + 2.0f * Normal.y;
    \\  return Result;
    \\}
    \\
    \\vec3 ExtendNormalZ(vec2 Normal)
    \\{
    \\  vec3 Result = vec3(Normal, sqrt(1 - Normal.x * Normal.x - Normal.y * Normal.y));
    \\  return Result;
    \\}
    \\
    \\vec3 UnpackNormal3(vec2 Normal)
    \\{
    \\  vec3 Result = ExtendNormalZ(UnpackNormal2(Normal));
    \\  return Result;
    \\}
;

fn compileZBiasProgram(open_gl: *OpenGL, program: *ZBiasProgram, depth_peel: bool, lighting_disabled: bool) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 330
        \\#extension GL_ARB_explicit_attrib_location : enable
        \\#define ShaderSimTexReadSRGB %d
        \\#define ShaderSimTexWriteSRGB %d
        \\#define DepthPeel %d
        \\#define LIGHTING_DISABLED %d
    ,
        .{
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_read_srgb))),
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_write_srgb))),
            @as(i32, @intCast(@intFromBool(depth_peel))),
            @as(u32, @intCast(@intFromBool(lighting_disabled))),
        },
    );
    const vertex_code =
        \\// Vertex code
        \\uniform mat4x4 Transform;
        \\
        \\uniform vec3 CameraPosition;
        \\uniform vec3 FogDirection;
        \\
        \\in vec4 VertP;
        \\in vec3 VertN;
        \\in vec2 VertUV;
        \\in vec4 VertColor;
        \\
        \\in int VertLightIndex;
        \\in int VertTextureIndex;
        \\
        \\smooth out vec2 FragUV;
        \\smooth out vec4 FragColor;
        \\smooth out float FogDistance;
        \\smooth out vec3 WorldPosition;
        \\smooth out vec3 WorldNormal;
        \\
        \\flat out int FragLightIndex;
        \\flat out int FragTextureIndex;
        \\
        \\void main(void)
        \\{
        \\  vec4 InVertex = vec4(VertP.xyz, 1.0);
        \\  float ZBias = VertP.w;
        \\
        \\  vec4 ZVertex = InVertex;
        \\  ZVertex.z += ZBias;
        \\
        \\  vec4 ZMinTransform = Transform * InVertex;
        \\  vec4 ZMaxTransform = Transform * ZVertex;
        \\
        \\  float ModifiedZ = (ZMinTransform.w / ZMaxTransform.w) * ZMaxTransform.z;
        \\
        \\  gl_Position = vec4(ZMinTransform.x, ZMinTransform.y, ModifiedZ, ZMinTransform.w);
        \\
        \\  FragUV = VertUV.xy;
        \\  FragColor = VertColor;
        \\
        \\  FogDistance = dot(ZVertex.xyz - CameraPosition, FogDirection);
        \\  WorldPosition = ZVertex.xyz;
        \\  WorldNormal = VertN;
        \\
        \\  FragLightIndex = VertLightIndex;
        \\  FragTextureIndex = VertTextureIndex;
        \\}
    ;

    // TODO: Put this into the fragment shader.
    // const iteration_count: f32 = @floatFromInt(global_config.Renderer_Lighting_IterationCount);
    // const ray_count_f: f32 = @floatFromInt(ray_count);
    // dest.emission_color =
    //     dest.emission_color.plus(dest.next_emission_color.scaledTo(1.0 / (ray_count_f * iteration_count)));
    //
    // const light_color: Vector3 =
    //     source.reflection_color.hadamardProduct(source.emission_color).toVector3();
    //
    // const reflection_normal: Vector3 = dest.normal;
    // const diffuse_coefficient: f32 = 1;
    // const specular_coefficent: f32 = 1 - diffuse_coefficient;
    // // const specular_power = 1.0 + (15.0);
    // const distance_falloff: f32 = 1.0 / (1.0 + math.square(light_distance));
    //
    // const diffuse_dot: f32 = math.clampf01(to_light.dotProduct(reflection_normal));
    // const diffuse_contrib: f32 = distance_falloff * diffuse_coefficient * diffuse_dot;
    // const diffuse_contrib3: Vector3 = .splat(diffuse_contrib);
    // const diffuse_light: Vector3 = diffuse_contrib3.hadamardProduct(light_color);
    //
    // const reflection_vector: Vector3 =
    //     to_camera.negated().plus(reflection_normal.scaledTo(2 * reflection_normal.dotProduct(to_camera)));
    // const specular_dot: f32 = math.clampf01(to_light.dotProduct(reflection_vector));
    // // specular_dot = pow(specular_dot, specular_power);
    // const specular_contrib: f32 = specular_coefficent * specular_dot;
    // const specular_contrib3: Vector3 = .splat(specular_contrib);
    // const specular_light: Vector3 = specular_contrib3.hadamardProduct(light_color);
    //
    // const total_light: Vector3 = diffuse_light.plus(specular_light);
    // accumulated_color = accumulated_color.plus(total_light);

    const fragment_code =
        \\// Fragment code
        \\uniform sampler2DArray TextureSampler;
        \\#if DepthPeel
        \\uniform sampler2D DepthSampler;
        \\#endif
        \\uniform vec3 FogColor;
        \\uniform float AlphaThreshold;
        \\uniform float FogStartDistance;
        \\uniform float FogEndDistance;
        \\uniform float ClipAlphaStartDistance;
        \\uniform float ClipAlphaEndDistance;
        \\uniform vec3 CameraPosition;
        \\
        \\uniform sampler1D Light0Sampler;
        \\uniform sampler1D Light1Sampler;
        \\
        \\smooth in vec2 FragUV;
        \\smooth in vec4 FragColor;
        \\smooth in float FogDistance;
        \\smooth in vec3 WorldPosition;
        \\smooth in vec3 WorldNormal;
        \\
        \\flat in int FragLightIndex;
        \\flat in int FragTextureIndex;
        \\
        \\out vec4 BlendUnitColor;
        \\
        \\vec4 RunningSum;
        \\void FetchAndSum(int LightIndex)
        \\{
        \\  vec4 LightData0 = texelFetch(Light0Sampler, LightIndex, 0);
        \\  vec4 LightData1 = texelFetch(Light1Sampler, LightIndex, 0);
        \\
        \\  vec3 LightPosition = LightData0.xyz;
        \\  vec3 LightColor = LightData1.rgb;
        \\  vec3 LightDirection;
        \\  LightDirection.x = LightData0.a;
        \\  LightDirection.y = LightData1.a;
        \\  LightDirection.z =
        \\    sqrt(1.0f - (LightDirection.x * LightDirection.x + LightDirection.y * LightDirection.y));
        \\  if (LightColor.r < 0.0)
        \\  {
        \\    LightColor.r = -LightColor.r;
        \\    LightDirection.z = -LightDirection.z;
        \\  }
        \\
        \\  float Contribution = 1.0f / (1.0f + LengthSq(LightPosition - WorldPosition));
        \\  float DirectionalFalloff = clamp(dot(LightDirection.rgb, WorldNormal), 0.0, 1.0);
        \\
        \\  RunningSum.rgb += Contribution * DirectionalFalloff * LightColor.rgb;
        \\  RunningSum.a += Contribution;
        \\}
        \\
        \\vec3 SumLight()
        \\{
        \\  RunningSum = vec4(0.0, 0.0, 0.0, 0.0);
        \\
        \\  FetchAndSum(FragLightIndex + 0);
        \\  FetchAndSum(FragLightIndex + 1);
        \\  FetchAndSum(FragLightIndex + 2);
        \\  FetchAndSum(FragLightIndex + 3);
        \\
        \\  vec4 Result = RunningSum;
        \\
        \\  if (Result.a > 0.0f)
        \\  {
        \\    Result.rgb *= 1.0f / Result.a;
        \\  }
        \\
        \\  return(Result.rgb);
        \\}
        \\
        \\void main(void)
        \\{
        \\#if DepthPeel
        \\  float ClipDepth = texelFetch(DepthSampler, ivec2(gl_FragCoord.xy), 0).r;
        \\  if (gl_FragCoord.z < ClipDepth + 0.000001) // This epsilon was needed on an AMD GPU.
        \\  {
        \\    discard;
        \\  }
        \\#endif
        \\
        \\  vec3 ArrayUV = vec3(FragUV.x, FragUV.y, float(FragTextureIndex));
        \\  vec4 TexSample = texture(TextureSampler, ArrayUV);
        \\#if ShaderSimTexReadSRGB
        \\    TexSample.rgb *= TexSample.rgb;
        \\#endif
        \\
        \\  float FogAmount = clamp01MapToRange(FogStartDistance, FogEndDistance, FogDistance);
        \\  float AlphaAmount = clamp01MapToRange(ClipAlphaStartDistance, ClipAlphaEndDistance, FogDistance);
        \\  vec4 ModColor = AlphaAmount * FragColor * TexSample;
        \\
        \\  if (ModColor.a > AlphaThreshold)
        \\  {
        \\    vec4 SurfaceReflection;
        \\    SurfaceReflection.rgb = mix(ModColor.rgb, FogColor.rgb, FogAmount);
        \\    SurfaceReflection.a = ModColor.a;
        \\
        \\#if ShaderSimTexWriteSRGB
        \\    SurfaceReflection.rgb = sqrt(SurfaceReflection.rgb);
        \\#endif
        \\
        \\#if LIGHTING_DISABLED
        \\#else
        \\    if (FragLightIndex != 0)
        \\    {
        \\      vec3 L = SumLight();
        \\      SurfaceReflection.rgb *= L;
        \\    }
        \\#endif
        \\
        \\    SurfaceReflection.r = clamp(SurfaceReflection.r, 0.0, 1.0);
        \\    SurfaceReflection.g = clamp(SurfaceReflection.g, 0.0, 1.0);
        \\    SurfaceReflection.b = clamp(SurfaceReflection.b, 0.0, 1.0);
        \\
        \\    BlendUnitColor = SurfaceReflection;
        \\  }
        \\  else
        \\  {
        \\    discard;
        \\  }
        \\}
    ;

    const program_handle = createProgram(
        @ptrCast(defines[0..defines_length]),
        shader_header_code,
        vertex_code,
        fragment_code,
        &program.common,
    );
    linkSamplers(
        &program.common,
        &.{
            "TextureSampler",
            "DepthSampler",
            "Light0Sampler",
            "Light1Sampler",
        },
    );

    program.transform_id = platform.optGLGetUniformLocation.?(program_handle, "Transform");

    program.camera_position_id = platform.optGLGetUniformLocation.?(program_handle, "CameraPosition");
    program.fog_direction_id = platform.optGLGetUniformLocation.?(program_handle, "FogDirection");
    program.fog_color_id = platform.optGLGetUniformLocation.?(program_handle, "FogColor");
    program.fog_start_distance_id = platform.optGLGetUniformLocation.?(program_handle, "FogStartDistance");
    program.fog_end_distance_id = platform.optGLGetUniformLocation.?(program_handle, "FogEndDistance");
    program.clip_alpha_start_distance_id = platform.optGLGetUniformLocation.?(program_handle, "ClipAlphaStartDistance");
    program.clip_alpha_end_distance_id = platform.optGLGetUniformLocation.?(program_handle, "ClipAlphaEndDistance");
    program.alpha_threshold_id = platform.optGLGetUniformLocation.?(program_handle, "AlphaThreshold");
}

fn compilePeelCompositeProgram(open_gl: *OpenGL, program: *OpenGLProgramCommon) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 330
        \\#define ShaderSimTexReadSRGB %d
        \\#define ShaderSimTexWriteSRGB %d
        \\#define DepthPeel %d
    ,
        .{
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_read_srgb))),
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_write_srgb))),
            @as(i32, @intCast(@intFromBool(false))),
        },
    );
    const vertex_code =
        \\// Vertex code
        \\in vec4 VertP;
        \\in vec4 VertColor;
        \\in vec2 VertUV;
        \\
        \\smooth out vec2 FragUV;
        \\smooth out vec4 FragColor;
        \\
        \\void main(void)
        \\{
        \\  gl_Position = VertP;
        \\  FragUV = VertUV;
        \\  FragColor = VertColor;
        \\}
    ;
    const fragment_code =
        \\// Fragment code
        \\uniform sampler2D Peel0Sampler;
        \\uniform sampler2D Peel1Sampler;
        \\uniform sampler2D Peel2Sampler;
        \\uniform sampler2D Peel3Sampler;
        \\
        \\smooth in vec2 FragUV;
        \\smooth in vec4 FragColor;
        \\
        \\out vec4 BlendUnitColor;
        \\
        \\void main(void)
        \\{
        \\  vec4 Peel0 = texture(Peel0Sampler, FragUV);
        \\  vec4 Peel1 = texture(Peel1Sampler, FragUV);
        \\  vec4 Peel2 = texture(Peel2Sampler, FragUV);
        \\  vec4 Peel3 = texture(Peel3Sampler, FragUV);
        \\
        \\#if ShaderSimTexReadSRGB
        \\  Peel0.rgb *= Peel0.rgb;
        \\  Peel1.rgb *= Peel1.rgb;
        \\  Peel2.rgb *= Peel2.rgb;
        \\  Peel3.rgb *= Peel3.rgb;
        \\#endif
        \\
        \\#if 0
        \\  Peel3.rgb *= (1.0 / Peel3.a);
        \\#endif
        \\
        \\#if 0
        \\  Peel0.rgb = Peel0.a * vec3(0, 0, 1);
        \\  Peel1.rgb = Peel1.a * vec3(0, 1, 0);
        \\  Peel2.rgb = Peel2.a * vec3(1, 0, 0);
        \\  Peel3.rgb = Peel3.a * vec3(0, 0, 0);
        \\#endif
        \\
        \\  BlendUnitColor.rgb = Peel3.rgb;
        \\  BlendUnitColor.rgb = Peel2.rgb + (1 - Peel2.a) * BlendUnitColor.rgb;
        \\  BlendUnitColor.rgb = Peel1.rgb + (1 - Peel1.a) * BlendUnitColor.rgb;
        \\  BlendUnitColor.rgb = Peel0.rgb + (1 - Peel0.a) * BlendUnitColor.rgb;
        \\
        \\#if ShaderSimTexWriteSRGB
        \\  BlendUnitColor.rgb = sqrt(BlendUnitColor.rgb);
        \\#endif
        \\}
    ;

    _ = createProgram(
        @ptrCast(defines[0..defines_length]),
        shader_header_code,
        vertex_code,
        fragment_code,
        program,
    );
    linkSamplers(program, &.{
        "Peel0Sampler",
        "Peel1Sampler",
        "Peel2Sampler",
        "Peel3Sampler",
    });
}

fn compileResolveMultisampleProgram(open_gl: *OpenGL, program: *ResolveMultisampleProgram) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 330
        \\#extension GL_ARB_explicit_attrib_location : enable
        \\#define ShaderSimTexReadSRGB %d
        \\#define ShaderSimTexWriteSRGB %d
        \\#define DepthPeel %d
        \\#define MultisampleDebug %d
    ,
        .{
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_read_srgb))),
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_write_srgb))),
            @as(i32, @intCast(@intFromBool(false))),
            @as(i32, @intCast(@intFromBool(open_gl.current_settings.multisample_debug))),
        },
    );
    const vertex_code =
        \\// Vertex code
        \\in vec4 VertP;
        \\
        \\void main(void)
        \\{
        \\  gl_Position = VertP;
        \\}
    ;
    const fragment_code =
        \\// Fragment code
        \\#define DepthThreshold 0.001f
        \\uniform sampler2DMS DepthSampler;
        \\uniform sampler2DMS ColorSampler;
        \\uniform int SampleCount;
        \\
        \\out vec4 BlendUnitColor;
        \\
        \\void main(void)
        \\{
        \\#if !MultisampleDebug
        \\  float DepthMax = 0.0f;
        \\  float DepthMin = 1.0f;
        \\  for (int SampleIndex = 0;
        \\       SampleIndex < SampleCount;
        \\       ++SampleIndex)
        \\  {
        \\    float Depth = texelFetch(DepthSampler, ivec2(gl_FragCoord.xy), SampleIndex).r;
        \\    DepthMin = min(DepthMin, Depth);
        \\    DepthMax = max(DepthMax, Depth);
        \\  }
        \\
        \\  gl_FragDepth = 0.5 * (DepthMin + DepthMax);
        \\
        \\  vec4 CombinedColor = vec4(0.0, 0.0, 0.0, 0.0);
        \\  vec4 CombinedEmission = vec4(0.0, 0.0, 0.0, 0.0);
        \\  vec4 CombinedNormalPosition = vec4(0.0, 0.0, 0.0, 0.0);
        \\  for (int SampleIndex = 0;
        \\       SampleIndex < SampleCount;
        \\       ++SampleIndex)
        \\  {
        \\    float Depth = texelFetch(DepthSampler, ivec2(gl_FragCoord.xy), SampleIndex).r;
        \\    vec4 Color = texelFetch(ColorSampler, ivec2(gl_FragCoord.xy), SampleIndex);
        \\#if ShaderSimTexReadSRGB
        \\    Color.rgb *= Color.rgb;
        \\#endif
        \\    CombinedColor += Color;
        \\  }
        \\
        \\  float InvSampleCount = 1.0 / float(SampleCount);
        \\  vec4 SurfaceReflect = InvSampleCount * CombinedColor;
        \\
        \\#if ShaderSimTexWriteSRGB
        \\  SurfaceReflect.rgb = sqrt(SurfaceReflect.rgb);
        \\#endif
        \\
        \\  BlendUnitColor = SurfaceReflect;
        \\#else
        \\  int UniqueCount = 1;
        \\  for (int IndexA = 1;
        \\       IndexA < SampleCount;
        \\       ++IndexA)
        \\  {
        \\    int Unique = 1;
        \\    float DepthA = texelFetch(DepthSampler, ivec2(gl_FragCoord.xy), IndexA).r;
        \\    for (int IndexB = 0;
        \\         IndexB < IndexA;
        \\         ++IndexB)
        \\    {
        \\      float DepthB = texelFetch(DepthSampler, ivec2(gl_FragCoord.xy), IndexB).r;
        \\      if (DepthA == 1.0 || DepthB == 1.0 || DepthA == DepthB)
        \\      {
        \\        Unique = 0;
        \\        break;
        \\      }
        \\    }
        \\    if (Unique == 1) {
        \\      UniqueCount += 1;
        \\    }
        \\  }
        \\  BlendUnitColor.a = 1;
        \\  if (UniqueCount == 1) {
        \\    BlendUnitColor.rgb = vec3(0.0, 0.0, 0.0);
        \\  }
        \\  if (UniqueCount == 2) {
        \\    BlendUnitColor.rgb = vec3(0.0, 1.0, 0.0);
        \\  }
        \\  if (UniqueCount == 3) {
        \\    BlendUnitColor.rgb = vec3(1.0, 1.0, 0.0);
        \\  }
        \\  if (UniqueCount >= 4) {
        \\    BlendUnitColor.rgb = vec3(1.0, 0.0, 0.0);
        \\  }
        \\#endif
        \\}
    ;

    const program_handle = createProgram(
        @ptrCast(defines[0..defines_length]),
        shader_header_code,
        vertex_code,
        fragment_code,
        &program.common,
    );
    linkSamplers(&program.common, &.{ "DepthSampler", "ColorSampler", "EmissionSampler", "NormalPositionSampler" });
    program.sample_count_id = platform.optGLGetUniformLocation.?(program_handle, "SampleCount");
}

fn compileFinalStretchProgram(open_gl: *OpenGL, program: *OpenGLProgramCommon) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 330
        \\#define ShaderSimTexReadSRGB %d
        \\#define ShaderSimTexWriteSRGB %d
    ,
        .{
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_read_srgb))),
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_write_srgb))),
        },
    );
    const vertex_code =
        \\// Vertex code
        \\in vec4 VertP;
        \\in vec2 VertUV;
        \\
        \\smooth out vec2 FragUV;
        \\
        \\void main(void)
        \\{
        \\  gl_Position = VertP;
        \\  FragUV = VertUV;
        \\}
    ;
    const fragment_code =
        \\// Fragment code
        \\uniform sampler2D ImageSampler;
        \\
        \\smooth in vec2 FragUV;
        \\
        \\out vec4 BlendUnitColor;
        \\
        \\void main(void)
        \\{
        \\  BlendUnitColor = texture(ImageSampler, FragUV);
        \\}
    ;

    _ = createProgram(
        @ptrCast(defines[0..defines_length]),
        shader_header_code,
        vertex_code,
        fragment_code,
        program,
    );
    linkSamplers(program, &.{"ImageSampler"});
}

fn useZBiasProgramBegin(program: *ZBiasProgram, setup: *align(1) RenderSetup, alpha_threshold: f32) void {
    useProgramBegin(&program.common);

    platform.optGLUniformMatrix4fv.?(program.transform_id, 1, true, setup.projection.toGL());
    platform.optGLUniform3fv.?(program.camera_position_id, 1, setup.camera_position.toGL());
    platform.optGLUniform3fv.?(program.fog_direction_id, 1, setup.fog_direction.toGL());
    platform.optGLUniform3fv.?(program.fog_color_id, 1, setup.fog_color.toGL());
    platform.optGLUniform1f.?(program.fog_start_distance_id, setup.fog_start_distance);
    platform.optGLUniform1f.?(program.fog_end_distance_id, setup.fog_end_distance);
    platform.optGLUniform1f.?(program.clip_alpha_start_distance_id, setup.clip_alpha_start_distance);
    platform.optGLUniform1f.?(program.clip_alpha_end_distance_id, setup.clip_alpha_end_distance);
    platform.optGLUniform1f.?(program.alpha_threshold_id, alpha_threshold);
}

fn useResolveMultisampleProgramBegin(open_gl: *OpenGL, program: *ResolveMultisampleProgram) void {
    useProgramBegin(&program.common);

    platform.optGLUniform1i.?(program.sample_count_id, open_gl.max_multi_sample_count);
}

fn useMultiGridLightDownProgramBegin(program: *MultiGridLightDownProgram, source_uv_step: Vector2) void {
    useProgramBegin(&program.common);

    platform.optGLUniform2fv.?(program.source_uv_step, 1, source_uv_step.toGL());
}

fn isValidArray(index: i32) bool {
    return index != -1;
}

fn useProgramBegin(program: *OpenGLProgramCommon) void {
    platform.optGLUseProgram.?(program.program_handle);

    const position_array_index: i32 = program.vert_position_id;
    const normal_array_index: i32 = program.vert_normal_id;
    const uv_array_index: i32 = program.vert_uv_id;
    const color_array_index: i32 = program.vert_color_id;
    const light_index_index: i32 = program.vert_light_index_id;
    const texture_index_index: i32 = program.vert_texture_index_id;

    if (isValidArray(position_array_index)) {
        platform.optGLEnableVertexAttribArray.?(@intCast(position_array_index));
        platform.optGLVertexAttribPointer.?(
            @intCast(position_array_index),
            4,
            gl.GL_FLOAT,
            false,
            @sizeOf(TexturedVertex),
            @ptrFromInt(@offsetOf(TexturedVertex, "position")),
        );
    }
    if (isValidArray(normal_array_index)) {
        platform.optGLEnableVertexAttribArray.?(@intCast(normal_array_index));
        platform.optGLVertexAttribPointer.?(
            @intCast(normal_array_index),
            3,
            gl.GL_FLOAT,
            false,
            @sizeOf(TexturedVertex),
            @ptrFromInt(@offsetOf(TexturedVertex, "normal")),
        );
    }
    if (isValidArray(color_array_index)) {
        platform.optGLEnableVertexAttribArray.?(@intCast(color_array_index));
        platform.optGLVertexAttribPointer.?(
            @intCast(color_array_index),
            4,
            gl.GL_UNSIGNED_BYTE,
            true,
            @sizeOf(TexturedVertex),
            @ptrFromInt(@offsetOf(TexturedVertex, "color")),
        );
    }
    if (isValidArray(uv_array_index)) {
        platform.optGLEnableVertexAttribArray.?(@intCast(uv_array_index));
        platform.optGLVertexAttribPointer.?(
            @intCast(uv_array_index),
            2,
            gl.GL_FLOAT,
            false,
            @sizeOf(TexturedVertex),
            @ptrFromInt(@offsetOf(TexturedVertex, "uv")),
        );
    }
    // TODO: Can you send down a "vector of 2 unsigned shorts"?
    if (isValidArray(light_index_index)) {
        platform.optGLEnableVertexAttribArray.?(@intCast(light_index_index));
        platform.optGLVertexAttribIPointer.?(
            @intCast(light_index_index),
            1,
            gl.GL_UNSIGNED_SHORT,
            @sizeOf(TexturedVertex),
            @ptrFromInt(@offsetOf(TexturedVertex, "light_index")),
        );
    }
    if (isValidArray(texture_index_index)) {
        platform.optGLEnableVertexAttribArray.?(@intCast(texture_index_index));
        platform.optGLVertexAttribIPointer.?(
            @intCast(texture_index_index),
            1,
            gl.GL_UNSIGNED_SHORT,
            @sizeOf(TexturedVertex),
            @ptrFromInt(@offsetOf(TexturedVertex, "texture_index")),
        );
    }

    var sampler_index: u32 = 0;
    while (sampler_index < program.sampler_count) : (sampler_index += 1) {
        platform.optGLUniform1i.?(program.samplers[sampler_index], @intCast(sampler_index));
    }
}

fn useProgramEnd(program: *OpenGLProgramCommon) void {
    platform.optGLUseProgram.?(0);

    const position_array_index: i32 = program.vert_position_id;
    const normal_array_index: i32 = program.vert_normal_id;
    const color_array_index: i32 = program.vert_color_id;
    const uv_array_index: i32 = program.vert_uv_id;
    const light_index_index: i32 = program.vert_light_index_id;
    const texture_index_index: i32 = program.vert_texture_index_id;

    if (isValidArray(position_array_index)) {
        platform.optGLDisableVertexAttribArray.?(@intCast(position_array_index));
    }
    if (isValidArray(normal_array_index)) {
        platform.optGLDisableVertexAttribArray.?(@intCast(normal_array_index));
    }
    if (isValidArray(color_array_index)) {
        platform.optGLDisableVertexAttribArray.?(@intCast(color_array_index));
    }
    if (isValidArray(uv_array_index)) {
        platform.optGLDisableVertexAttribArray.?(@intCast(uv_array_index));
    }
    if (isValidArray(light_index_index)) {
        platform.optGLDisableVertexAttribArray.?(@intCast(light_index_index));
    }
    if (isValidArray(texture_index_index)) {
        platform.optGLDisableVertexAttribArray.?(@intCast(texture_index_index));
    }
}

fn framebufferTexImage(open_gl: *OpenGL, slot: u32, format: i32, filter_type: i32, width: i32, height: i32) u32 {
    var result: u32 = 0;
    gl.glGenTextures(1, @ptrCast(&result));
    gl.glBindTexture(slot, result);

    if (slot == GL_TEXTURE_2D_MULTISAMPLE) {
        _ = platform.optGLTexImage2DMultiSample.?(
            slot,
            open_gl.max_multi_sample_count,
            format,
            width,
            height,
            false,
        );
    } else {
        gl.glTexImage2D(
            slot,
            0,
            format,
            width,
            height,
            0,
            if (format == DEPTH_COMPONENT_TYPE) gl.GL_DEPTH_COMPONENT else gl.GL_BGRA_EXT,
            gl.GL_UNSIGNED_BYTE,
            null,
        );
    }

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, filter_type);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, filter_type);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    return result;
}

fn createFrameBuffer(open_gl: *OpenGL, width: i32, height: i32, flags: u32, color_buffer_count: u32) Framebuffer {
    var result: Framebuffer = .{};
    const multisampled: bool = (flags & @intFromEnum(FramebufferFlags.Multisampled)) != 0;
    const filtered: bool = (flags & @intFromEnum(FramebufferFlags.Filtered)) != 0;
    const has_depth: bool = (flags & @intFromEnum(FramebufferFlags.Depth)) != 0;
    // const is_float: bool = (flags & @intFromEnum(FramebufferFlags.Float)) != 0;

    platform.optGLGenFramebuffersEXT.?(1, @ptrCast(&result.framebuffer_handle));
    platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, result.framebuffer_handle);

    const slot = if (multisampled) GL_TEXTURE_2D_MULTISAMPLE else gl.GL_TEXTURE_2D;
    const filter_type: i32 = if (filtered) gl.GL_LINEAR else gl.GL_NEAREST;

    std.debug.assert(color_buffer_count <= ALL_COLOR_ATTACHMENTS.len);
    std.debug.assert(color_buffer_count <= result.color_handle.len);

    var color_index: u32 = 0;
    while (color_index < color_buffer_count) : (color_index += 1) {
        result.color_handle[color_index] = framebufferTexImage(
            open_gl,
            slot,
            if (color_index == 0) open_gl.default_framebuffer_texture_format else gl.GL_RGBA8,
            filter_type,
            width,
            height,
        );
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT0 + color_index,
            slot,
            result.color_handle[color_index],
            0,
        );
    }
    platform.optGLDrawBuffers.?(color_buffer_count, @ptrCast(&ALL_COLOR_ATTACHMENTS));
    std.debug.assert(gl.glGetError() == gl.GL_NO_ERROR);

    if (has_depth) {
        result.depth_handle = framebufferTexImage(open_gl, slot, DEPTH_COMPONENT_TYPE, filter_type, width, height);
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_DEPTH_ATTACHMENT,
            slot,
            result.depth_handle,
            0,
        );
    }
    std.debug.assert(gl.glGetError() == gl.GL_NO_ERROR);

    const status: u32 = platform.optGLCheckFramebufferStatusEXT.?(GL_FRAMEBUFFER);
    std.debug.assert(status == GL_FRAME_BUFFER_COMPLETE);

    platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, 0);
    gl.glBindTexture(slot, 0);

    return result;
}

fn bindFrameBuffer(framebuffer: ?*Framebuffer, render_width: i32, render_height: i32) void {
    if (platform.optGLBindFramebufferEXT) |glBindFramebuffer| {
        glBindFramebuffer(GL_FRAMEBUFFER, if (framebuffer) |f| f.framebuffer_handle else 0);
        gl.glViewport(0, 0, render_width, render_height);

        const status: u32 = platform.optGLCheckFramebufferStatusEXT.?(GL_FRAMEBUFFER);
        std.debug.assert(status == GL_FRAME_BUFFER_COMPLETE);
    }
}

fn getDepthPeelReadBuffer(open_gl: *OpenGL, index: u32) *Framebuffer {
    var peel_buffer: *Framebuffer = &open_gl.depth_peel_buffers[index];
    if (open_gl.multisampling) {
        peel_buffer = &open_gl.depth_peel_resolve_buffers[index];
    }
    return peel_buffer;
}

fn freeFramebuffer(framebuffer: *Framebuffer) void {
    if (framebuffer.framebuffer_handle != 0) {
        platform.optGLDeleteFramebuffersEXT.?(1, @ptrCast(&framebuffer.framebuffer_handle));
        framebuffer.framebuffer_handle = 0;
    }

    var color_index: u32 = 0;
    while (color_index < framebuffer.color_handle.len) : (color_index += 1) {
        if (framebuffer.color_handle[color_index] != 0) {
            gl.glDeleteTextures(1, &framebuffer.color_handle[color_index]);
            framebuffer.color_handle[color_index] = 0;
        }
    }

    if (framebuffer.depth_handle != 0) {
        gl.glDeleteTextures(1, &framebuffer.depth_handle);
        framebuffer.depth_handle = 0;
    }
}

fn freeProgram(program: *OpenGLProgramCommon) void {
    platform.optGLDeleteProgram.?(program.program_handle);
    program.program_handle = 0;
}

fn changeToSettings(open_gl: *OpenGL, settings: *RenderSettings) void {
    // Free all dynamic resources.
    freeFramebuffer(&open_gl.resolve_frame_buffer);
    var depth_peel_index: u32 = 0;
    while (depth_peel_index < open_gl.depth_peel_count) : (depth_peel_index += 1) {
        freeFramebuffer(&open_gl.depth_peel_buffers[depth_peel_index]);
        freeFramebuffer(&open_gl.depth_peel_resolve_buffers[depth_peel_index]);
    }
    var light_index: u32 = 0;
    while (light_index < open_gl.light_buffer_count) : (light_index += 1) {
        const light_buffer: *LightBuffer = &open_gl.light_buffers[light_index];
        platform.optGLDeleteFramebuffersEXT.?(1, @ptrCast(&light_buffer.write_all_framebuffer));
        platform.optGLDeleteFramebuffersEXT.?(1, @ptrCast(&light_buffer.write_emission_framebuffer));
        gl.glDeleteTextures(1, &light_buffer.front_emission_texture);
        gl.glDeleteTextures(1, &light_buffer.back_emission_texture);
        gl.glDeleteTextures(1, &light_buffer.surface_color_texture);
        gl.glDeleteTextures(1, &light_buffer.normal_position_texture);
        light_buffer.* = .{};
    }
    freeProgram(&open_gl.z_bias_no_depth_peel.common);
    freeProgram(&open_gl.z_bias_depth_peel.common);
    freeProgram(&open_gl.peel_composite);
    freeProgram(&open_gl.final_stretch);
    freeProgram(&open_gl.resolve_multisample.common);

    gl.glDeleteTextures(1, &open_gl.light_data0);
    gl.glDeleteTextures(1, &open_gl.light_data1);

    // Create new dynamic resources.
    open_gl.current_settings = settings.*;
    var resolve_flags: u32 = 0;
    if (!settings.pixelation_hint) {
        resolve_flags |= @intFromEnum(FramebufferFlags.Filtered);
    }

    open_gl.multisampling = settings.multisampling_hint;

    const render_width: i32 = @intCast(settings.width);
    const render_height: i32 = @intCast(settings.height);

    var depth_peel_flags: u32 = @intFromEnum(FramebufferFlags.Depth);
    const multisampled_resolve_flags = depth_peel_flags;
    if (open_gl.multisampling) {
        depth_peel_flags |= @intFromEnum(FramebufferFlags.Multisampled);
    }

    open_gl.depth_peel_count = settings.depth_peel_count_hint;
    if (open_gl.depth_peel_count > open_gl.depth_peel_buffers.len) {
        open_gl.depth_peel_count = open_gl.depth_peel_buffers.len;
    }

    compileZBiasProgram(open_gl, &open_gl.z_bias_no_depth_peel, false, open_gl.current_settings.lighting_disabled);
    compileZBiasProgram(open_gl, &open_gl.z_bias_depth_peel, true, open_gl.current_settings.lighting_disabled);
    compilePeelCompositeProgram(open_gl, &open_gl.peel_composite);
    compileFinalStretchProgram(open_gl, &open_gl.final_stretch);
    compileResolveMultisampleProgram(open_gl, &open_gl.resolve_multisample);

    open_gl.resolve_frame_buffer = createFrameBuffer(open_gl, render_width, render_height, resolve_flags, 1);

    depth_peel_index = 0;
    while (depth_peel_index < open_gl.depth_peel_count) : (depth_peel_index += 1) {
        open_gl.depth_peel_buffers[depth_peel_index] = createFrameBuffer(
            open_gl,
            render_width,
            render_height,
            depth_peel_flags,
            COLOR_HANDLE_COUNT,
        );

        if (open_gl.multisampling) {
            open_gl.depth_peel_resolve_buffers[depth_peel_index] = createFrameBuffer(
                open_gl,
                render_width,
                render_height,
                multisampled_resolve_flags,
                COLOR_HANDLE_COUNT,
            );
        }
    }

    var texture_width: i32 =
        (@as(i32, 1) << @as(u5, @intCast(intrinsics.findMostSignificantSetBit(@intCast(render_width)).index)));
    var texture_height: i32 =
        (@as(i32, 1) << @as(u5, @intCast(intrinsics.findMostSignificantSetBit(@intCast(render_height)).index)));

    open_gl.light_buffer_count = 0;
    light_index = 0;
    while (texture_width > 1 and texture_height > 1) : (light_index += 1) {
        const light_buffer: *LightBuffer = &open_gl.light_buffers[open_gl.light_buffer_count];
        open_gl.light_buffer_count += 1;
        const filter_type: i32 = gl.GL_LINEAR;

        light_buffer.width = texture_width;
        light_buffer.height = texture_height;

        light_buffer.front_emission_texture = framebufferTexImage(
            open_gl,
            gl.GL_TEXTURE_2D,
            GL_RGB32F,
            filter_type,
            texture_width,
            texture_height,
        );
        light_buffer.back_emission_texture = framebufferTexImage(
            open_gl,
            gl.GL_TEXTURE_2D,
            GL_RGB32F,
            filter_type,
            texture_width,
            texture_height,
        );
        light_buffer.surface_color_texture = framebufferTexImage(
            open_gl,
            gl.GL_TEXTURE_2D,
            GL_RGB32F,
            filter_type,
            texture_width,
            texture_height,
        );
        light_buffer.normal_position_texture = framebufferTexImage(
            open_gl,
            gl.GL_TEXTURE_2D,
            GL_RGB32F,
            filter_type,
            texture_width,
            texture_height,
        );

        // Up framebuffer.
        platform.optGLGenFramebuffersEXT.?(1, @ptrCast(&light_buffer.write_all_framebuffer));
        platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, light_buffer.write_all_framebuffer);
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT0,
            gl.GL_TEXTURE_2D,
            light_buffer.front_emission_texture,
            0,
        );
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT1,
            gl.GL_TEXTURE_2D,
            light_buffer.back_emission_texture,
            0,
        );
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT2,
            gl.GL_TEXTURE_2D,
            light_buffer.surface_color_texture,
            0,
        );
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT3,
            gl.GL_TEXTURE_2D,
            light_buffer.normal_position_texture,
            0,
        );
        platform.optGLDrawBuffers.?(4, @ptrCast(&ALL_COLOR_ATTACHMENTS));

        // Down framebuffer.
        platform.optGLGenFramebuffersEXT.?(1, @ptrCast(&light_buffer.write_emission_framebuffer));
        platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, light_buffer.write_emission_framebuffer);
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT0,
            gl.GL_TEXTURE_2D,
            light_buffer.front_emission_texture,
            0,
        );
        platform.optGLFrameBufferTexture2DEXT.?(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT1,
            gl.GL_TEXTURE_2D,
            light_buffer.back_emission_texture,
            0,
        );
        platform.optGLDrawBuffers.?(2, @ptrCast(&ALL_COLOR_ATTACHMENTS));

        texture_width = @divFloor(texture_width + 1, 2);
        texture_height = @divFloor(texture_height + 1, 2);

        if (texture_width < 1) {
            texture_width = 1;
        }
        if (texture_height < 1) {
            texture_height = 1;
        }
    }

    gl.glGenTextures(1, &open_gl.light_data0);
    gl.glBindTexture(gl.GL_TEXTURE_1D, open_gl.light_data0);
    gl.glTexImage1D(gl.GL_TEXTURE_1D, 0, GL_RGBA32F, LIGHT_DATA_WIDTH, 0, gl.GL_RGBA, gl.GL_FLOAT, null);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    gl.glGenTextures(1, &open_gl.light_data1);
    gl.glBindTexture(gl.GL_TEXTURE_1D, open_gl.light_data1);
    gl.glTexImage1D(gl.GL_TEXTURE_1D, 0, GL_RGBA32F, LIGHT_DATA_WIDTH, 0, gl.GL_RGBA, gl.GL_FLOAT, null);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    gl.glBindTexture(gl.GL_TEXTURE_1D, 0);
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
    gl.glBindTexture(GL_TEXTURE_3D, 0);

    wgl.setVSync(open_gl, open_gl.current_settings.request_vsync);
}

fn beginScreenFill(open_gl: *OpenGL, framebuffer_handle: u32, width: i32, height: i32) void {
    platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, framebuffer_handle);
    gl.glViewport(0, 0, width, height);
    gl.glScissor(0, 0, width, height);
    gl.glDepthFunc(gl.GL_ALWAYS);

    platform.optGLBindBuffer.?(GL_ARRAY_BUFFER, open_gl.screen_fill_vertex_buffer);
}

fn endScreenFill() void {
    platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, 0);
    gl.glDepthFunc(gl.GL_LEQUAL);
}

fn resolveMultisample(open_gl: *OpenGL, from: *Framebuffer, to: *Framebuffer, width: i32, height: i32) void {
    beginScreenFill(open_gl, to.framebuffer_handle, width, height);

    useResolveMultisampleProgramBegin(open_gl, &open_gl.resolve_multisample);

    platform.optGLActiveTexture.?(GL_TEXTURE0);
    gl.glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, from.depth_handle);

    var color_index: u32 = 0;
    while (color_index < COLOR_HANDLE_COUNT) : (color_index += 1) {
        platform.optGLActiveTexture.?(GL_TEXTURE1 + color_index);
        gl.glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, from.color_handle[color_index]);
    }

    platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);

    platform.optGLActiveTexture.?(GL_TEXTURE0);

    useProgramEnd(&open_gl.resolve_multisample.common);

    endScreenFill();
}

fn bindTexture(slot: u32, target: u32, handle: u32) void {
    platform.optGLActiveTexture.?(slot);
    gl.glBindTexture(target, handle);
}

pub fn manageTextures(open_gl: *OpenGL, queue: *TextureQueue) void {
    const pending: TextureOpList = renderer.dequeuePending(queue);

    var opt_op: ?*TextureOp = pending.first;
    while (opt_op) |op| : (opt_op = op.next) {
        allocateTexture(
            open_gl,
            op.update.texture,
            op.update.data,
        );
    }

    renderer.enqueueFree(queue, pending);
}

fn getSpecialTextureHandleFor(open_gl: *OpenGL, texture: RendererTexture) u32 {
    const index: u32 = renderer.textureIndexFrom(texture);
    std.debug.assert(index < open_gl.max_special_texture_count);

    const result: u32 = open_gl.special_texture_handles[index];
    return result;
}

pub fn beginFrame(
    open_gl: *OpenGL,
    window_width: i32,
    window_height: i32,
    draw_region: Rectangle2i,
) callconv(.c) *RenderCommands {
    var commands: *RenderCommands = &open_gl.render_commands;

    commands.settings = open_gl.current_settings;
    commands.settings.width = @intCast(draw_region.getWidth());
    commands.settings.height = @intCast(draw_region.getHeight());

    commands.window_width = window_width;
    commands.window_height = window_height;
    commands.draw_region = draw_region;

    commands.max_push_buffer_size = open_gl.push_buffer_memory.len * @sizeOf(u8);
    commands.push_buffer_base = &open_gl.push_buffer_memory;
    commands.push_buffer_data_at = &open_gl.push_buffer_memory;
    commands.max_vertex_count = open_gl.max_vertex_count;
    commands.vertex_count = 0;
    commands.max_index_count = open_gl.max_index_count;
    commands.index_count = 0;
    commands.vertex_array = open_gl.vertex_array;
    commands.index_array = open_gl.index_array;

    commands.max_quad_texture_count = open_gl.max_quad_texture_count;
    commands.quad_texture_count = 0;
    commands.quad_textures = open_gl.bitmap_array;

    return commands;
}

pub fn endFrame(open_gl: *OpenGL, commands: *RenderCommands) callconv(.c) void {
    const draw_region: Rectangle2i = commands.draw_region;
    const window_width: i32 = commands.window_width;
    const window_height: i32 = commands.window_height;

    gl.glDepthMask(gl.GL_TRUE);
    gl.glColorMask(gl.GL_TRUE, gl.GL_TRUE, gl.GL_TRUE, gl.GL_TRUE);
    gl.glDepthFunc(gl.GL_LEQUAL);
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_CULL_FACE);
    gl.glCullFace(gl.GL_BACK);
    gl.glFrontFace(gl.GL_CCW);
    // gl.glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE);
    // gl.glEnable(GL_SAMPLE_ALPHA_TO_ONE);
    gl.glEnable(GL_MULTISAMPLE);

    gl.glEnable(gl.GL_SCISSOR_TEST);
    gl.glDisable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

    platform.optGLBindBuffer.?(GL_ARRAY_BUFFER, open_gl.vertex_buffer);
    platform.optGLBufferData.?(
        GL_ARRAY_BUFFER,
        commands.vertex_count * @sizeOf(TexturedVertex),
        commands.vertex_array,
        GL_STREAM_DRAW,
    );

    platform.optGLBindBuffer.?(GL_ELEMENT_ARRAY_BUFFER, open_gl.index_buffer);
    platform.optGLBufferData.?(
        GL_ELEMENT_ARRAY_BUFFER,
        commands.index_count * @sizeOf(u16),
        commands.index_array,
        GL_STREAM_DRAW,
    );

    const settings: *RenderSettings = &commands.settings;
    if (!settings.equals(&open_gl.current_settings)) {
        changeToSettings(open_gl, settings);
    }

    const use_render_targets: bool = platform.optGLBindFramebufferEXT != null;
    std.debug.assert(use_render_targets);

    const render_width: i32 = @intCast(settings.width);
    const render_height: i32 = @intCast(settings.height);

    std.debug.assert(open_gl.depth_peel_count > 0);
    const max_render_target_index: u32 = open_gl.depth_peel_count - 1;

    gl.glClearDepth(1);

    var on_peel_index: u32 = 0;
    var peel_header_restore: [*]u8 = undefined;
    var header_at: [*]u8 = commands.push_buffer_base;
    while (@intFromPtr(header_at) < @intFromPtr(commands.push_buffer_data_at)) {
        const header: *align(1) RenderEntryHeader = @ptrCast(@alignCast(header_at));
        header_at += @sizeOf(RenderEntryHeader);
        const data: *anyopaque = @ptrFromInt(@intFromPtr(header) + @sizeOf(RenderEntryHeader));

        // const alignment: usize = 1;
        // //     switch (header.type) {
        // //     .RenderEntryFullClear => @alignOf(RenderEntryFullClear),
        // //     .RenderEntryBeginPeels => @alignOf(RenderEntryBeginPeels),
        // //     .RenderEntryTexturedQuads => @alignOf(RenderEntryTexturedQuads),
        // //     .RenderEntryLightingTransfer => @alignOf(RenderEntryLightingTransfer),
        // //     .RenderEntryDepthClear, .RenderEntryEndPeels => @alignOf(u32),
        // // };
        //
        // const header_address = @intFromPtr(header);
        // const data_address = header_address + @sizeOf(RenderEntryHeader);
        // const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        // const data: *anyopaque = @ptrFromInt(data_address);
        //
        // header_at += aligned_address - data_address;

        switch (header.type) {
            .RenderEntryFullClear => {
                const entry: *RenderEntryFullClear = @ptrCast(@alignCast(data));
                header_at += @sizeOf(RenderEntryFullClear);

                gl.glClearColor(
                    entry.clear_color.values[0],
                    entry.clear_color.values[1],
                    entry.clear_color.values[2],
                    1,
                );
                gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
            },
            .RenderEntryBeginPeels => {
                const entry: *RenderEntryBeginPeels = @ptrCast(@alignCast(data));
                header_at += @sizeOf(RenderEntryBeginPeels);

                peel_header_restore = @ptrCast(header);
                bindFrameBuffer(&open_gl.depth_peel_buffers[on_peel_index], render_width, render_height);

                gl.glScissor(0, 0, render_width, render_height);
                if (on_peel_index == max_render_target_index) {
                    gl.glClearColor(
                        entry.clear_color.values[0],
                        entry.clear_color.values[1],
                        entry.clear_color.values[2],
                        1,
                    );
                } else {
                    gl.glClearColor(0, 0, 0, 0);
                }
                gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
            },
            .RenderEntryEndPeels => {
                if (open_gl.multisampling) {
                    const from: *Framebuffer = &open_gl.depth_peel_buffers[on_peel_index];
                    const to: *Framebuffer = &open_gl.depth_peel_resolve_buffers[on_peel_index];

                    if (true) {
                        resolveMultisample(open_gl, from, to, render_width, render_height);
                    } else {
                        platform.optGLBindFramebufferEXT.?(GL_READ_FRAMEBUFFER, from.framebuffer_handle);
                        platform.optGLBindFramebufferEXT.?(GL_DRAW_FRAMEBUFFER, to.framebuffer_handle);
                        gl.glViewport(0, 0, window_width, window_height);
                        platform.optGLBlitFrameBuffer.?(
                            0,
                            0,
                            render_width,
                            render_height,
                            0,
                            0,
                            render_width,
                            render_height,
                            gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT,
                            gl.GL_NEAREST,
                        );
                    }
                }

                if (on_peel_index < max_render_target_index) {
                    header_at = peel_header_restore;
                    on_peel_index += 1;

                    bindFrameBuffer(&open_gl.depth_peel_buffers[on_peel_index], render_width, render_height);
                } else {
                    std.debug.assert(on_peel_index == max_render_target_index);

                    const peel_buffer: *Framebuffer = getDepthPeelReadBuffer(open_gl, 0);
                    bindFrameBuffer(peel_buffer, render_width, render_height);
                    on_peel_index = 0;
                    gl.glEnable(gl.GL_BLEND);
                }
            },
            .RenderEntryDepthClear => {
                gl.glClear(gl.GL_DEPTH_BUFFER_BIT);
            },
            .RenderEntryTexturedQuads => {
                platform.optGLBindBuffer.?(GL_ARRAY_BUFFER, open_gl.vertex_buffer);
                platform.optGLBindBuffer.?(GL_ELEMENT_ARRAY_BUFFER, open_gl.index_buffer);

                const entry: *RenderEntryTexturedQuads = @ptrCast(@alignCast(data));
                header_at += @sizeOf(RenderEntryTexturedQuads);

                const peeling: bool = on_peel_index > 0;
                const setup: *align(1) RenderSetup = &entry.setup;

                var clip_rect: Rectangle2 = setup.clip_rect;
                const clip_min_x: i32 = math.lerpI32Binormal(0, render_width, clip_rect.min.x());
                const clip_min_y: i32 = math.lerpI32Binormal(0, render_height, clip_rect.min.y());
                const clip_max_x: i32 = math.lerpI32Binormal(0, render_width, clip_rect.max.x());
                const clip_max_y: i32 = math.lerpI32Binormal(0, render_height, clip_rect.max.y());
                gl.glScissor(clip_min_x, clip_min_y, clip_max_x - clip_min_x, clip_max_y - clip_min_y);

                var program: *ZBiasProgram = &open_gl.z_bias_no_depth_peel;
                var alpha_threshold: f32 = 0.01;
                if (peeling) {
                    const peel_buffer: *Framebuffer = getDepthPeelReadBuffer(open_gl, on_peel_index - 1);

                    program = &open_gl.z_bias_depth_peel;
                    platform.optGLActiveTexture.?(GL_TEXTURE1);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, peel_buffer.depth_handle);
                    platform.optGLActiveTexture.?(GL_TEXTURE0);

                    if (on_peel_index == max_render_target_index) {
                        alpha_threshold = 0.9;
                    }
                }

                platform.optGLActiveTexture.?(GL_TEXTURE2);
                gl.glBindTexture(gl.GL_TEXTURE_1D, open_gl.light_data0);
                platform.optGLActiveTexture.?(GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_1D, open_gl.light_data1);
                platform.optGLActiveTexture.?(GL_TEXTURE0);

                useZBiasProgramBegin(program, setup, alpha_threshold);

                if (entry.quad_textures) |quad_textures| {
                    // Multiple dispatch, slow path, for arbitrary sized textures.
                    var index_index: u32 = entry.index_array_offset;
                    var quad_index: u32 = 0;
                    while (quad_index < entry.quad_count) : (quad_index += 1) {
                        const texture: RendererTexture = quad_textures[quad_index];
                        const texture_handle: u32 = getSpecialTextureHandleFor(open_gl, texture);
                        gl.glBindTexture(GL_TEXTURE_2D_ARRAY, texture_handle);
                        platform.optGLDrawElementsBaseVertex.?(
                            gl.GL_TRIANGLES,
                            6,
                            gl.GL_UNSIGNED_SHORT,
                            @ptrFromInt(index_index * @sizeOf(u16)),
                            @intCast(entry.vertex_array_offset),
                        );
                        index_index += 6;
                    }
                } else {
                    // Single dispatch, fast path, for same sized textures.
                    gl.glBindTexture(GL_TEXTURE_2D_ARRAY, open_gl.texture_array);
                    platform.optGLDrawElementsBaseVertex.?(
                        gl.GL_TRIANGLES,
                        @intCast(6 * entry.quad_count),
                        gl.GL_UNSIGNED_SHORT,
                        @ptrFromInt(entry.index_array_offset * @sizeOf(u16)),
                        @intCast(entry.vertex_array_offset),
                    );
                }

                gl.glBindTexture(GL_TEXTURE_2D_ARRAY, 0);

                useProgramEnd(&program.common);
                if (peeling) {
                    platform.optGLActiveTexture.?(GL_TEXTURE1);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
                    platform.optGLActiveTexture.?(GL_TEXTURE0);
                }
            },
            .RenderEntryLightingTransfer => {
                const entry: *RenderEntryLightingTransfer = @ptrCast(@alignCast(data));
                header_at += @sizeOf(RenderEntryLightingTransfer);

                gl.glBindTexture(gl.GL_TEXTURE_1D, open_gl.light_data0);
                gl.glTexSubImage1D(gl.GL_TEXTURE_1D, 0, 0, LIGHT_DATA_WIDTH, gl.GL_RGBA, gl.GL_FLOAT, entry.light_data0);
                gl.glBindTexture(gl.GL_TEXTURE_1D, open_gl.light_data1);
                gl.glTexSubImage1D(gl.GL_TEXTURE_1D, 0, 0, LIGHT_DATA_WIDTH, gl.GL_RGBA, gl.GL_FLOAT, entry.light_data1);
                gl.glBindTexture(gl.GL_TEXTURE_1D, 0);
            },
        }
    }

    gl.glDisable(gl.GL_DEPTH_TEST);
    gl.glDisable(gl.GL_BLEND);

    platform.optGLBindFramebufferEXT.?(GL_DRAW_FRAMEBUFFER, open_gl.resolve_frame_buffer.framebuffer_handle);
    gl.glViewport(0, 0, render_width, render_height);
    gl.glScissor(0, 0, render_width, render_height);
    platform.optGLBindBuffer.?(GL_ARRAY_BUFFER, open_gl.screen_fill_vertex_buffer);

    useProgramBegin(&open_gl.peel_composite);
    var texture_bind_index: u32 = GL_TEXTURE0;
    var peel_index: u32 = 0;
    while (peel_index <= max_render_target_index) : (peel_index += 1) {
        const peel_buffer: *Framebuffer = getDepthPeelReadBuffer(open_gl, peel_index);
        platform.optGLActiveTexture.?(texture_bind_index);
        texture_bind_index += 1;
        gl.glBindTexture(gl.GL_TEXTURE_2D, peel_buffer.color_handle[@intFromEnum(ColorHandleType.SurfaceReflection)]);
    }
    platform.optGLActiveTexture.?(texture_bind_index);
    texture_bind_index += 1;
    gl.glBindTexture(gl.GL_TEXTURE_2D, open_gl.light_buffers[0].front_emission_texture);
    platform.optGLActiveTexture.?(texture_bind_index);
    texture_bind_index += 1;
    gl.glBindTexture(gl.GL_TEXTURE_2D, open_gl.light_buffers[0].normal_position_texture);

    platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);
    platform.optGLActiveTexture.?(GL_TEXTURE0);
    useProgramEnd(&open_gl.peel_composite);

    platform.optGLBindFramebufferEXT.?(GL_DRAW_FRAMEBUFFER, 0);

    gl.glViewport(
        0,
        0,
        window_width,
        window_height,
    );
    gl.glScissor(
        0,
        0,
        window_width,
        window_height,
    );
    gl.glClearColor(0, 0, 0, 0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl.glViewport(
        draw_region.min.x(),
        draw_region.min.y(),
        draw_region.getWidth(),
        draw_region.getHeight(),
    );
    gl.glScissor(
        draw_region.min.x(),
        draw_region.min.y(),
        draw_region.getWidth(),
        draw_region.getHeight(),
    );

    useProgramBegin(&open_gl.final_stretch);
    gl.glBindTexture(gl.GL_TEXTURE_2D, open_gl.resolve_frame_buffer.color_handle[0]);
    platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
    platform.optGLActiveTexture.?(GL_TEXTURE0);
    useProgramEnd(&open_gl.final_stretch);

    open_gl.debug_light_buffer_index = math.clampi32(
        0,
        open_gl.debug_light_buffer_index,
        @intCast(open_gl.light_buffer_count - 1),
    );
    open_gl.debug_light_buffer_texture_index = math.clampi32(0, open_gl.debug_light_buffer_texture_index, 4);
    if (open_gl.debug_light_buffer_texture_index > 0) {
        const light_buffer: *LightBuffer = &open_gl.light_buffers[@intCast(open_gl.debug_light_buffer_index)];
        platform.optGLBindFramebufferEXT.?(
            GL_READ_FRAMEBUFFER,
            light_buffer.write_all_framebuffer,
        );
        platform.optGLBindFramebufferEXT.?(GL_DRAW_FRAMEBUFFER, 0);
        gl.glReadBuffer(GL_COLOR_ATTACHMENT0 + @as(u32, @intCast(open_gl.debug_light_buffer_texture_index - 1)));
        gl.glViewport(draw_region.min.x(), draw_region.min.y(), window_width, window_height);
        platform.optGLBlitFrameBuffer.?(
            0,
            0,
            light_buffer.width,
            light_buffer.height,
            draw_region.min.x(),
            draw_region.min.y(),
            draw_region.max.x(),
            draw_region.max.y(),
            gl.GL_COLOR_BUFFER_BIT,
            gl.GL_NEAREST,
        );
        gl.glReadBuffer(GL_COLOR_ATTACHMENT0);
    }
}

fn allocateTexture(open_gl: *OpenGL, texture: RendererTexture, data: *anyopaque) void {
    if (renderer.isSpecialTexture(texture)) {
        const handle: u32 = getSpecialTextureHandleFor(open_gl, texture);
        gl.glBindTexture(GL_TEXTURE_2D_ARRAY, handle);
        // gl.glTexImage2D(
        //     gl.GL_TEXTURE_2D,
        //     0,
        //     open_gl.default_sprite_texture_format,
        //     texture.width,
        //     texture.height,
        //     0,
        //     gl.GL_BGRA_EXT,
        //     gl.GL_UNSIGNED_BYTE,
        //     data,
        // );
        platform.optGLTexImage3D.?(
            GL_TEXTURE_2D_ARRAY,
            0,
            open_gl.default_sprite_texture_format,
            texture.width,
            texture.height,
            1,
            0,
            gl.GL_BGRA_EXT,
            gl.GL_UNSIGNED_BYTE,
            data,
        );
    } else {
        const texture_index: u32 = renderer.textureIndexFrom(texture);
        std.debug.assert(texture_index < open_gl.max_texture_count);

        gl.glBindTexture(GL_TEXTURE_2D_ARRAY, open_gl.texture_array);
        platform.optGLTexSubImage3D.?(
            GL_TEXTURE_2D_ARRAY,
            0,
            0,
            0,
            @intCast(texture_index),
            texture.width,
            texture.height,
            1,
            gl.GL_BGRA_EXT,
            gl.GL_UNSIGNED_BYTE,
            data,
        );
    }

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
}

fn drawLineVertices(
    min_position: Vector3,
    max_position: Vector3,
) void {
    const z: f32 = max_position.z();

    gl.glVertex3f(min_position.x(), min_position.y(), z);
    gl.glVertex3f(max_position.x(), min_position.y(), z);

    gl.glVertex3f(max_position.x(), min_position.y(), z);
    gl.glVertex3f(max_position.x(), max_position.y(), z);

    gl.glVertex3f(max_position.x(), max_position.y(), z);
    gl.glVertex3f(min_position.x(), max_position.y(), z);

    gl.glVertex3f(min_position.x(), max_position.y(), z);
    gl.glVertex3f(min_position.x(), min_position.y(), z);
}

fn drawQuad(
    p0: Vector3,
    t0: Vector2,
    c0: Color,
    p1: Vector3,
    t1: Vector2,
    c1: Color,
    p2: Vector3,
    t2: Vector2,
    c2: Color,
    p3: Vector3,
    t3: Vector2,
    c3: Color,
) void {
    // Lower triangle.
    gl.glColor4fv(c0.toGL());
    gl.glTexCoord2fv(t0.toGL());
    gl.glVertex3fv(p0.toGL());
    gl.glColor4fv(c1.toGL());
    gl.glTexCoord2fv(t1.toGL());
    gl.glVertex3fv(p1.toGL());
    gl.glColor4fv(c2.toGL());
    gl.glTexCoord2fv(t2.toGL());
    gl.glVertex3fv(p2.toGL());

    // Upper triangle
    gl.glColor4fv(c0.toGL());
    gl.glTexCoord2fv(t0.toGL());
    gl.glVertex3fv(p0.toGL());
    gl.glColor4fv(c2.toGL());
    gl.glTexCoord2fv(t2.toGL());
    gl.glVertex3fv(p2.toGL());
    gl.glColor4fv(c3.toGL());
    gl.glTexCoord2fv(t3.toGL());
    gl.glVertex3fv(p3.toGL());
}

fn drawRectangle(
    min_position: Vector3,
    max_position: Vector3,
    premultiplied_color: Color,
    opt_min_uv: ?Vector2,
    opt_max_uv: ?Vector2,
) void {
    const z: f32 = min_position.z();
    const min_uv = opt_min_uv orelse Vector2.splat(0);
    const max_uv = opt_max_uv orelse Vector2.splat(1);

    gl.glBegin(gl.GL_TRIANGLES);
    {
        // This value is not gamma corrected by OpenGL.
        gl.glColor4f(
            premultiplied_color.r(),
            premultiplied_color.g(),
            premultiplied_color.b(),
            premultiplied_color.a(),
        );

        // Lower triangle.
        gl.glTexCoord2f(min_uv.x(), min_uv.y());
        gl.glVertex3f(min_position.x(), min_position.y(), z);
        gl.glTexCoord2f(max_uv.x(), min_uv.y());
        gl.glVertex3f(max_position.x(), min_position.y(), z);
        gl.glTexCoord2f(max_uv.x(), max_uv.y());
        gl.glVertex3f(max_position.x(), max_position.y(), z);

        // Upper triangle
        gl.glTexCoord2f(min_uv.x(), min_uv.y());
        gl.glVertex3f(min_position.x(), min_position.y(), z);
        gl.glTexCoord2f(max_uv.x(), max_uv.y());
        gl.glVertex3f(max_position.x(), max_position.y(), z);
        gl.glTexCoord2f(min_uv.x(), max_uv.y());
        gl.glVertex3f(min_position.x(), max_position.y(), z);
    }
    gl.glEnd();
}

pub fn displayBitmap(
    width: i32,
    height: i32,
    draw_region: Rectangle2i,
    pitch: usize,
    memory: ?*const anyopaque,
    clear_color: Color,
    blit_texture: u32,
) void {
    std.debug.assert(pitch == width * 4);

    bindFrameBuffer(null, draw_region.getWidth(), draw_region.getHeight());

    gl.glDisable(gl.GL_SCISSOR_TEST);
    gl.glDisable(gl.GL_BLEND);

    gl.glBindTexture(gl.GL_TEXTURE_2D, blit_texture);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        GL_SRGB8_ALPHA8,
        width,
        height,
        0,
        gl.GL_BGRA_EXT,
        gl.GL_UNSIGNED_BYTE,
        memory,
    );

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP);

    gl.glEnable(gl.GL_TEXTURE_2D);

    gl.glClearColor(0, 0, 0, 0);
    gl.glClearColor(clear_color.r(), clear_color.g(), clear_color.b(), clear_color.a());
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    // Reset all transforms.
    gl.glMatrixMode(gl.GL_TEXTURE);
    gl.glLoadIdentity();

    gl.glMatrixMode(gl.GL_MODELVIEW);
    gl.glLoadIdentity();

    types.notImplemented();

    // TODO: This has to be worked out specifically for doing the full-screen draw.
    gl.glMatrixMode(gl.GL_PROJECTION);
    const a = math.safeRatio1(2, 1);
    const b = math.safeRatio1(2 * @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)));
    const projection: []const f32 = &.{
        a, 0, 0, 0,
        0, b, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
    gl.glLoadMatrixf(@ptrCast(projection));

    const min_position = math.Vector3.new(0, 0, 0);
    const max_position = math.Vector3.new(@floatFromInt(width), @floatFromInt(height), 0);
    const color = math.Color.new(1, 1, 1, 1);

    drawRectangle(min_position, max_position, color, null, null);

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
    gl.glEnable(gl.GL_BLEND);
}

fn createProgram(
    defines: [*:0]const u8,
    header: [*:0]const u8,
    vertex_code: [*:0]const u8,
    fragment_code: [*:0]const u8,
    program: *OpenGLProgramCommon,
) u32 {
    const glShaderSource = platform.optGLShaderSource.?;
    const glCreateShader = platform.optGLCreateShader.?;
    const glDeleteShader = platform.optGLDeleteShader.?;
    const glCompileShader = platform.optGLCompileShader.?;
    const glCreateProgram = platform.optGLCreateProgram.?;
    const glLinkProgram = platform.optGLLinkProgram.?;
    const glAttachShader = platform.optGLAttachShader.?;
    const glValidateProgram = platform.optGLValidateProgram.?;
    const glGetProgramiv = platform.optGLGetProgramiv.?;
    const glGetShaderInfoLog = platform.optGLGetShaderInfoLog.?;
    const glGetProgramInfoLog = platform.optGLGetProgramInfoLog.?;

    const vertex_shader_id: u32 = glCreateShader(GL_VERTEX_SHADER);
    var vertex_shader_code = [_][*:0]const u8{
        defines,
        header,
        vertex_code,
    };
    glShaderSource(vertex_shader_id, vertex_shader_code.len, &vertex_shader_code, null);
    glCompileShader(vertex_shader_id);

    const fragment_shader_id: u32 = glCreateShader(GL_FRAGMENT_SHADER);
    var fragment_shader_code = [_][*:0]const u8{
        defines,
        header,
        fragment_code,
    };
    glShaderSource(fragment_shader_id, fragment_shader_code.len, &fragment_shader_code, null);
    glCompileShader(fragment_shader_id);

    const program_id: u32 = glCreateProgram();
    glAttachShader(program_id, vertex_shader_id);
    glAttachShader(program_id, fragment_shader_id);
    glLinkProgram(program_id);

    glValidateProgram(program_id);
    var link_validated: i32 = 0;
    glGetProgramiv(program_id, GL_LINK_STATUS, &link_validated);
    if (link_validated == 0) {
        var vertex_errors: [4096:0]u8 = undefined;
        var fragment_errors: [4096:0]u8 = undefined;
        var program_errors: [4096:0]u8 = undefined;

        var vertex_length: i32 = 0;
        glGetShaderInfoLog(vertex_shader_id, vertex_errors.len, &vertex_length, &vertex_errors);
        var fragment_length: i32 = 0;
        glGetShaderInfoLog(fragment_shader_id, fragment_errors.len, &fragment_length, &fragment_errors);
        var program_length: i32 = 0;
        glGetProgramInfoLog(program_id, program_errors.len, &program_length, &program_errors);

        std.log.err("Vertex error log:\n{s}", .{vertex_errors[0..@intCast(vertex_length)]});
        std.log.err("Fragment error log:\n{s}", .{fragment_errors[0..@intCast(fragment_length)]});
        std.log.err("Program error log:\n{s}", .{program_errors[0..@intCast(program_length)]});

        @panic("Shader validation failed.");
    }

    glDeleteShader(vertex_shader_id);
    glDeleteShader(fragment_shader_id);

    program.program_handle = program_id;
    program.vert_position_id = platform.optGLGetAttribLocation.?(program_id, "VertP");
    program.vert_normal_id = platform.optGLGetAttribLocation.?(program_id, "VertN");
    program.vert_uv_id = platform.optGLGetAttribLocation.?(program_id, "VertUV");
    program.vert_color_id = platform.optGLGetAttribLocation.?(program_id, "VertColor");
    program.vert_light_index_id = platform.optGLGetAttribLocation.?(program_id, "VertLightIndex");
    program.vert_texture_index_id = platform.optGLGetAttribLocation.?(program_id, "VertTextureIndex");
    program.sampler_count = 0;

    return program_id;
}

fn linkSamplers(
    program: *OpenGLProgramCommon,
    samplers: []const ?[]const u8,
) void {
    for (samplers) |sampler| {
        if (sampler) |sampler_name| {
            const sampler_id: i32 = platform.optGLGetUniformLocation.?(program.program_handle, sampler_name.ptr);
            std.debug.assert(program.sampler_count < program.samplers.len);
            program.samplers[program.sampler_count] = sampler_id;
            program.sampler_count += 1;
        }
    }
}
