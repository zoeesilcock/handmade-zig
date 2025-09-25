const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
const rendergroup = @import("rendergroup.zig");
const render = @import("render.zig");
const asset = @import("asset.zig");
const math = @import("math.zig");
const sort = @import("sort.zig");
const debug_interface = @import("debug_interface.zig");
const platform = @import("win32_handmade.zig");
const std = @import("std");

pub const GL_NUM_EXTENSIONS = 0x821D;

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
pub const GL_STREAM_DRAW = 0x88E0;
pub const GL_STREAM_READ = 0x88E1;
pub const GL_STREAM_COPY = 0x88E2;
pub const GL_STATIC_DRAW = 0x88E4;
pub const GL_STATIC_READ = 0x88E5;
pub const GL_STATIC_COPY = 0x88E6;
pub const GL_DYNAMIC_DRAW = 0x88E8;
pub const GL_DYNAMIC_READ = 0x88E9;
pub const GL_DYNAMIC_COPY = 0x88EA;

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

// Windows specific.
pub const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
pub const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
pub const WGL_CONTEXT_LAYER_PLANE_ARB = 0x2093;
pub const WGL_CONTEXT_FLAGS_ARB = 0x2094;
pub const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;

pub const WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001;
pub const WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;

pub const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
pub const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;

pub const ERROR_INVALID_VERSION_ARB = 0x2095;
pub const ERROR_INVALID_PROFILE_ARB = 0x2096;

pub const WGL_DRAW_TO_WINDOW_ARB = 0x2001;
pub const WGL_ACCELERATION_ARB = 0x2003;
pub const WGL_FULL_ACCELERATION_ARB = 0x2027;
pub const WGL_SUPPORT_OPENGL_ARB = 0x2010;
pub const WGL_DOUBLE_BUFFER_ARB = 0x2011;
pub const WGL_PIXEL_TYPE_ARB = 0x2013;
pub const WGL_TYPE_RGBA_ARB = 0x202B;
pub const WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB = 0x20A9;

pub const WGL_RED_BITS_ARB = 0x2015;
pub const WGL_GREEN_BITS_ARB = 0x2017;
pub const WGL_BLUE_BITS_ARB = 0x2019;
pub const WGL_ALPHA_BITS_ARB = 0x201B;
pub const WGL_ACCUM_BITS_ARB = 0x201D;
pub const WGL_DEPTH_BITS_ARB = 0x2022;

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

const RenderCommands = shared.RenderCommands;
const RenderSettings = shared.RenderSettings;
const TexturedVertex = shared.TexturedVertex;
const RenderGroup = rendergroup.RenderGroup;
const RenderSetup = rendergroup.RenderSetup;
const RenderEntryHeader = rendergroup.RenderEntryHeader;
const RenderEntryTexturedQuads = rendergroup.RenderEntryTexturedQuads;
const RenderEntryClear = rendergroup.RenderEntryClear;
const RenderEntryBitmap = rendergroup.RenderEntryBitmap;
const RenderEntryCube = rendergroup.RenderEntryCube;
const RenderEntryRectangle = rendergroup.RenderEntryRectangle;
const RenderEntrySaturation = rendergroup.RenderEntrySaturation;
const LoadedBitmap = asset.LoadedBitmap;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Rectangle2 = math.Rectangle2;
const Rectangle2i = math.Rectangle2i;
const Matrix4x4 = math.Matrix4x4;
const TimedBlock = debug_interface.TimedBlock;
const TextureOp = render.TextureOp;
const SpriteFlag = render.SpriteFlag;
const SpriteEdge = render.SpriteEdge;
const zeroStruct = @import("memory.zig").zeroStruct;

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
        // std.log.info("GLDebugMessage: {s}", .{ message[0..@intCast(length)] });
    }
}

// TODO: How do we import OpenGL on other platforms here?
pub const gl = @import("win32").graphics.open_gl;

const OpenGLProgramCommon = struct {
    program_handle: u32 = 0,

    vert_position_id: i32 = 0,
    vert_normal_id: i32 = 0,
    vert_uv_id: i32 = 0,
    vert_color_id: i32 = 0,

    sampler_count: u32,
    samplers: [16]i32 = [1]i32{0} ** 16,
};

const ZBiasProgram = struct {
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

    debug_light_position_id: i32 = 0,
};

const ResolveMultisampleProgram = struct {
    common: OpenGLProgramCommon,

    sample_count_id: i32 = 0,
};

const FakeSeedLightingProgram = struct {
    common: OpenGLProgramCommon,

    debug_light_position_id: i32 = 0,
};

const MultiGridLightDownProgram = struct {
    common: OpenGLProgramCommon,

    source_uv_step: i32 = 0,
};

const ColorHandleType = enum(u32) {
    SurfaceReflection, // Reflection RGB, coverage A.
    Emission, // Emission RGB, spread A.
    NormalPositionLight, // Nx, Ny. TODO: Lp0, Lp1.
};

const COLOR_HANDLE_COUNT = @typeInfo(ColorHandleType).@"enum".fields.len;

const Framebuffer = struct {
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

const LightBuffer = struct {
    width: i32,
    height: i32,

    write_all_framebuffer: u32 = 0,
    write_emission_framebuffer: u32 = 0,

    // These are all 3-element textures.
    front_emission_texture: u32 = 0,
    back_emission_texture: u32 = 0,
    surface_color_texture: u32 = 0,
    normal_position_texture: u32 = 0, // This is Normal.x, Normal.z, Depth.
};

const OpenGL = struct {
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

    reserved_blit_texture: u32 = 0,

    white_bitmap: LoadedBitmap = undefined,
    white: [4][4]u32 = undefined,

    multisampling: bool = false,
    depth_peel_count: u32 = 0,

    // Dynamic resources that get recreated when settings change.
    resolve_frame_buffer: Framebuffer = .{},
    depth_peel_buffers: [16]Framebuffer = [1]Framebuffer{.{}} ** 16,
    depth_peel_resolve_buffers: [16]Framebuffer = [1]Framebuffer{.{}} ** 16,
    z_bias_no_depth_peel: ZBiasProgram = undefined, // Pass 0.
    z_bias_depth_peel: ZBiasProgram = undefined, // Passes 1 through n.
    peel_composite: OpenGLProgramCommon = undefined, // Composite all passes.
    final_stretch: OpenGLProgramCommon = undefined,
    resolve_multisample: ResolveMultisampleProgram = undefined,
    fake_seed_lighting: FakeSeedLightingProgram = undefined,
    depth_peel_to_lighting: OpenGLProgramCommon = undefined,
    multi_grid_light_up: OpenGLProgramCommon = undefined,
    multi_grid_light_down: MultiGridLightDownProgram = undefined,

    light_buffer_count: u32 = 0,
    light_buffers: [12]LightBuffer = undefined,

    debug_light_buffer_index: i32 = 0,
    debug_light_buffer_texture_index: i32 = 0,
};

pub var open_gl: OpenGL = .{};

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

pub fn init(info: Info, framebuffer_supports_sRGB: bool) void {
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
            // if (platform.optGLTextImage2DMultiSample) |glTexImage2DMultisample| {
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
    platform.optGLBindBuffer.?(GL_ARRAY_BUFFER, open_gl.vertex_buffer);

    open_gl.white = [1][4]u32{
        [1]u32{0xffffffff} ** 4,
    } ** 4;
    open_gl.white_bitmap = .{
        .memory = @ptrCast(&open_gl.white),
        .alignment_percentage = .new(0.5, 0.5),
        .width_over_height = 1,
        .width = 4,
        .height = 4,
        .pitch = 16,
        .texture_handle = allocateTexture(1, 1, &open_gl.white),
    };
}

const shader_header_code =
    \\// Header code
    \\#define MaxLightIntensity 10
    \\
    \\float clamp01MapToRange(float min, float max, float value) {
    \\  float range = max - min;
    \\  float result = clamp((value - min) / range, 0, 1);
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
    \\  Result.x = -1f + 2.0f * Normal.x;
    \\  Result.y = -1f + 2.0f * Normal.y;
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

fn compileZBiasProgram(program: *ZBiasProgram, depth_peel: bool) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 130
        \\#extension GL_ARB_explicit_attrib_location : enable
        \\#define ShaderSimTexReadSRGB %d
        \\#define ShaderSimTexWriteSRGB %d
        \\#define DepthPeel %d
    ,
        .{
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_read_srgb))),
            @as(i32, @intCast(@intFromBool(open_gl.shader_sim_tex_write_srgb))),
            @as(i32, @intCast(@intFromBool(depth_peel))),
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
        \\smooth out vec2 FragUV;
        \\smooth out vec4 FragColor;
        \\smooth out float FogDistance;
        \\smooth out vec3 WorldPosition;
        \\smooth out vec3 WorldNormal;
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
        \\}
    ;
    const fragment_code =
        \\// Fragment code
        \\uniform sampler2D TextureSampler;
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
        \\uniform vec3 LightPosition;
        \\
        \\smooth in vec2 FragUV;
        \\smooth in vec4 FragColor;
        \\smooth in float FogDistance;
        \\smooth in vec3 WorldPosition;
        \\smooth in vec3 WorldNormal;
        \\
        \\layout(location = 0) out vec4 BlendUnitColor[3];
        \\
        \\void main(void)
        \\{
        \\#if DepthPeel
        \\  float ClipDepth = texelFetch(DepthSampler, ivec2(gl_FragCoord.xy), 0).r;
        \\  if (gl_FragCoord.z <= ClipDepth)
        \\  {
        \\    discard;
        \\  }
        \\#endif
        \\
        \\  vec4 TexSample = texture(TextureSampler, FragUV);
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
        \\    // TODO: Some way of specifying light params.
        \\    float Lp0 = 0;
        \\    float Lp1 = 0;
        \\    float EmissionSpread = 1.0f;
        \\
        \\    vec3 Emission = vec3(0, 0, 0);
        \\    if (length(LightPosition - WorldPosition) < 2.0f)
        \\    {
        \\      Emission = vec3(1, 1, 1);
        \\    }
        \\
        \\    vec2 Normal = PackNormal2(WorldNormal.xy);
        \\
        \\    BlendUnitColor[0] = SurfaceReflection;
        \\    BlendUnitColor[1] = vec4(Emission.r, Emission.g, Emission.b, EmissionSpread);
        \\    BlendUnitColor[2] = vec4(Normal.x, Normal.y, Lp0, Lp1);
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
    linkSamplers(&program.common, &.{ "TextureSampler", "DepthSampler" });

    program.transform_id = platform.optGLGetUniformLocation.?(program_handle, "Transform");

    program.camera_position_id = platform.optGLGetUniformLocation.?(program_handle, "CameraPosition");
    program.fog_direction_id = platform.optGLGetUniformLocation.?(program_handle, "FogDirection");
    program.fog_color_id = platform.optGLGetUniformLocation.?(program_handle, "FogColor");
    program.fog_start_distance_id = platform.optGLGetUniformLocation.?(program_handle, "FogStartDistance");
    program.fog_end_distance_id = platform.optGLGetUniformLocation.?(program_handle, "FogEndDistance");
    program.clip_alpha_start_distance_id = platform.optGLGetUniformLocation.?(program_handle, "ClipAlphaStartDistance");
    program.clip_alpha_end_distance_id = platform.optGLGetUniformLocation.?(program_handle, "ClipAlphaEndDistance");
    program.alpha_threshold_id = platform.optGLGetUniformLocation.?(program_handle, "AlphaThreshold");

    program.debug_light_position_id = platform.optGLGetUniformLocation.?(program_handle, "LightPosition");
}

fn compilePeelCompositeProgram(program: *OpenGLProgramCommon) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 130
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
        \\uniform sampler2D NormalPosition0Sampler;
        \\uniform sampler2D Peel1Sampler;
        \\uniform sampler2D NormalPosition1Sampler;
        \\uniform sampler2D Peel2Sampler;
        \\uniform sampler2D NormalPosition2Sampler;
        \\uniform sampler2D Peel3Sampler;
        \\uniform sampler2D NormalPosition3Sampler;
        \\
        \\uniform sampler2D LightEmissionSampler;
        \\uniform sampler2D LightNormalPositionSampler;
        \\
        \\smooth in vec2 FragUV;
        \\smooth in vec4 FragColor;
        \\
        \\out vec4 BlendUnitColor;
        \\
        \\vec3 LightPeel(vec3 Peel, vec4 NormalPosition, vec3 LightNormal, vec3 LightColor, vec3 ToCamera)
        \\{
        \\  LightNormal = vec3(0, 0, -1);
        \\
        \\  vec3 ToLight = -LightNormal;
        \\  vec3 ReflectionNormal = UnpackNormal3(NormalPosition.xy);
        \\  float DiffuseCoefficient = NormalPosition.z;
        \\  float SpecularCoefficient = 1.0f - DiffuseCoefficient; // TODO: How should this really be encoded?
        \\  float SpecularPower = 1.0f + (15.0f * NormalPosition.w);
        \\
        \\  float DiffuseDot = clamp(dot(ToLight, ReflectionNormal), 0, 1);
        \\  vec3 CosAngle = vec3(DiffuseDot, DiffuseDot, DiffuseDot);
        \\  vec3 DiffuseLight = DiffuseCoefficient * CosAngle * LightColor;
        \\
        \\  vec3 ReflectionVector = -ToCamera + 2 * dot(ReflectionNormal, ToCamera) * ReflectionNormal;
        \\  float SpecularDot = clamp(dot(ToLight, ReflectionVector), 0, 1);
        \\  SpecularDot = pow(SpecularDot, SpecularPower);
        \\  vec3 CosReflectedAngle = vec3(SpecularDot, SpecularDot, SpecularDot);
        \\  vec3 SpecularLight = SpecularCoefficient * CosReflectedAngle * LightColor;
        \\
        \\  vec3 TotalLight = DiffuseLight + SpecularLight;
        \\
        \\  vec3 Result = Peel * TotalLight;
        \\
        \\  return Result;
        \\}
        \\
        \\void main(void)
        \\{
        \\  vec4 Peel0 = texture(Peel0Sampler, FragUV);
        \\  vec4 NormalPosition0 = texture(NormalPosition0Sampler, FragUV);
        \\  vec4 Peel1 = texture(Peel1Sampler, FragUV);
        \\  vec4 NormalPosition1 = texture(NormalPosition1Sampler, FragUV);
        \\  vec4 Peel2 = texture(Peel2Sampler, FragUV);
        \\  vec4 NormalPosition2 = texture(NormalPosition2Sampler, FragUV);
        \\  vec4 Peel3 = texture(Peel3Sampler, FragUV);
        \\  vec4 NormalPosition3 = texture(NormalPosition3Sampler, FragUV);
        \\
        \\  vec3 LightColor = texture(LightEmissionSampler, FragUV).rgb;
        \\  vec3 LightNormalPosition = texture(LightNormalPositionSampler, FragUV).rgb;
        \\  vec3 LightNormal = ExtendNormalZ(LightNormalPosition.xy);
        \\
        \\  vec3 ToCamera = vec3(0, 0, 1); // TODO: Actually compute this!
        \\
        \\  LightColor = clamp(LightColor / MaxLightIntensity, 0, 1);
        \\  LightColor = sqrt(sqrt(LightColor));
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
        \\#if 0
        \\  Peel0.rgb = LightPeel(Peel0.rgb, NormalPosition0, LightNormal, LightColor, ToCamera);
        \\  Peel1.rgb = LightPeel(Peel1.rgb, NormalPosition1, LightNormal, LightColor, ToCamera);
        \\  Peel2.rgb = LightPeel(Peel2.rgb, NormalPosition2, LightNormal, LightColor, ToCamera);
        \\  Peel3.rgb = LightPeel(Peel3.rgb, NormalPosition3, LightNormal, LightColor, ToCamera);
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
        "NormalPosition0Sampler",
        "Peel1Sampler",
        "NormalPosition1Sampler",
        "Peel2Sampler",
        "NormalPosition2Sampler",
        "Peel3Sampler",
        "NormalPosition3Sampler",
        "LightEmissionSampler",
        "LightNormalPositionSampler",
    });
}

fn compileResolveMultisampleProgram(program: *ResolveMultisampleProgram) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 150
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
        \\uniform sampler2DMS EmissionSampler;
        \\uniform sampler2DMS NormalPositionSampler;
        \\uniform int SampleCount;
        \\
        \\layout(location = 0) out vec4 BlendUnitColor[3];
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
        \\  vec4 CombinedColor = vec4(0, 0, 0, 0);
        \\  vec4 CombinedEmission = vec4(0, 0, 0, 0);
        \\  vec4 CombinedNormalPosition = vec4(0, 0, 0, 0);
        \\  for (int SampleIndex = 0;
        \\       SampleIndex < SampleCount;
        \\       ++SampleIndex)
        \\  {
        \\    float Depth = texelFetch(DepthSampler, ivec2(gl_FragCoord.xy), SampleIndex).r;
        \\    vec4 Color = texelFetch(ColorSampler, ivec2(gl_FragCoord.xy), SampleIndex);
        \\    vec4 Emission = texelFetch(EmissionSampler, ivec2(gl_FragCoord.xy), SampleIndex);
        \\    vec4 NormalPosition = texelFetch(NormalPositionSampler, ivec2(gl_FragCoord.xy), SampleIndex);
        \\#if ShaderSimTexReadSRGB
        \\    Color.rgb *= Color.rgb;
        \\#endif
        \\    CombinedColor += Color;
        \\    CombinedEmission += Emission;
        \\    CombinedNormalPosition += NormalPosition;
        \\  }
        \\
        \\  float InvSampleCount = 1.0 / float(SampleCount);
        \\  vec4 SurfaceReflect = InvSampleCount * CombinedColor;
        \\
        \\#if ShaderSimTexWriteSRGB
        \\  SurfaceReflect.rgb = sqrt(SurfaceReflect.rgb);
        \\#endif
        \\
        \\  BlendUnitColor[0] = SurfaceReflect;
        \\  BlendUnitColor[1] = InvSampleCount * CombinedEmission;
        \\  BlendUnitColor[2] = InvSampleCount * CombinedNormalPosition;
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
        \\    BlendUnitColor.rgb = vec3(0, 0, 0);
        \\  }
        \\  if (UniqueCount == 2) {
        \\    BlendUnitColor.rgb = vec3(0, 1, 0);
        \\  }
        \\  if (UniqueCount == 3) {
        \\    BlendUnitColor.rgb = vec3(1, 1, 0);
        \\  }
        \\  if (UniqueCount >= 4) {
        \\    BlendUnitColor.rgb = vec3(1, 0, 0);
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

fn compileFinalStretchProgram(program: *OpenGLProgramCommon) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 130
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

fn compileFakeSeedLightingProgram(program: *FakeSeedLightingProgram) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(defines.len, &defines,
        \\#version 150
        \\#extension GL_ARB_explicit_attrib_location : enable
    , .{});
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
        \\uniform vec3 LightPosition;
        \\
        \\layout(location = 0) out vec4 BlendUnitColor[4];
        \\
        \\vec3 FrontEmission = vec3(0, 0, 0);
        \\vec3 BackEmission = vec3(0, 0, 0);
        \\vec3 SurfaceColor = vec3(0.7f, 0.7f, 0.7f);
        \\vec3 NormalPosition = vec3(0, 1, -10);
        \\
        \\void Light(vec2 LightPosition,
        \\           float LightRadius,
        \\           vec3 LightFrontEmission,
        \\           vec3 LightBackEmission,
        \\           vec3 LightNormalPosition
        \\)
        \\{
        \\  vec2 ThisPosition = gl_FragCoord.xy;
        \\  vec2 LP = LightPosition * 0.025f * vec2(1920.0f, 1080.0f) + 0.25f * vec2(1920.0f, 1080.0f);
        \\
        \\  vec2 DeltaToLight = ThisPosition - LP;
        \\  float DistanceToLight = length(DeltaToLight);
        \\  if (DistanceToLight < LightRadius)
        \\  {
        \\     FrontEmission = LightFrontEmission;
        \\     BackEmission = LightBackEmission;
        \\     SurfaceColor = vec3(0, 0, 0);
        \\     NormalPosition = LightNormalPosition;
        \\  }
        \\}
        \\
        \\void main(void)
        \\{
        \\  Light(LightPosition.xy,                 10.0f, vec3(100, 0, 0),  vec3(0, 100, 0),  vec3(1, 0, 0));
        \\  Light(LightPosition.xy + vec2(0.5f, 0), 10.0f, vec3(0, 10, 0),  vec3(0, 0, 10),  vec3(0, 1, 1));
        \\
        \\  BlendUnitColor[0].rgb = FrontEmission;
        \\  BlendUnitColor[1].rgb = BackEmission;
        \\  BlendUnitColor[2].rgb = SurfaceColor;
        \\  BlendUnitColor[3].rgb = NormalPosition;
        \\}
    ;

    const program_handle = createProgram(
        @ptrCast(defines[0..defines_length]),
        shader_header_code,
        vertex_code,
        fragment_code,
        &program.common,
    );
    program.debug_light_position_id = platform.optGLGetUniformLocation.?(program_handle, "LightPosition");
}

fn compileDepthPeelToLightingProgram(program: *OpenGLProgramCommon) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 130
        \\#extension GL_ARB_explicit_attrib_location : enable
    ,
        .{},
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
        \\uniform sampler2D DepthSampler;
        \\uniform sampler2D SurfaceReflectionSampler;
        \\uniform sampler2D EmissionSampler;
        \\uniform sampler2D NormalPositionSampler;
        \\
        \\smooth in vec2 FragUV;
        \\
        \\layout(location = 0) out vec4 BlendUnitColor[4];
        \\
        \\void main(void)
        \\{
        \\  ivec2 TexelXY = ivec2(gl_FragCoord.xy);
        \\#if 0
        \\  float Depth = texelFetch(DepthSampler, TexelXY, 0).r;
        \\  vec4 SurfaceReflection = texelFetch(SurfaceReflectionSampler, TexelXY, 0);
        \\  vec4 Emission = texelFetch(EmissionSampler, TexelXY, 0);
        \\  vec4 NormalPositionLight = texelFetch(NormalPositionSampler, TexelXY, 0);
        \\#else
        \\  float Depth = texture(DepthSampler, FragUV).r;
        \\  vec4 SurfaceReflection = texture(SurfaceReflectionSampler, FragUV);
        \\  vec4 Emission = texture(EmissionSampler, FragUV);
        \\  vec4 NormalPositionLight = texture(NormalPositionSampler, FragUV);
        \\#endif
        \\
        \\  vec3 SurfaceReflectionRGB = SurfaceReflection.rgb;
        \\  float Coverage = SurfaceReflection.a;
        \\
        \\  vec3 EmissionRGB = Emission.rgb;
        \\  float EmitSpreat = Emission.a; // TODO: Use this to seed back emitters?
        \\
        \\  vec2 Normal = UnpackNormal2(NormalPositionLight.xy);
        \\  float Lp0 = NormalPositionLight.z;
        \\  float Lp1 = NormalPositionLight.w;
        \\
        \\  vec3 FrontEmission = MaxLightIntensity * EmissionRGB;
        \\  vec3 BackEmission = vec3(0, 0, 0);
        \\  vec3 SurfaceColor = SurfaceReflectionRGB;
        \\  vec3 NormalPosition = vec3(Normal.x, Normal.y, Depth);
        \\
        \\  BlendUnitColor[0].rgb = FrontEmission;
        \\  BlendUnitColor[1].rgb = BackEmission;
        \\  BlendUnitColor[2].rgb = SurfaceColor;
        \\  BlendUnitColor[3].rgb = NormalPosition;
        \\}
    ;

    _ = createProgram(
        @ptrCast(defines[0..defines_length]),
        shader_header_code,
        vertex_code,
        fragment_code,
        program,
    );
    linkSamplers(program, &.{ "DepthSampler", "SurfaceReflectionSampler", "EmissionSampler", "NormalPositionSampler" });
}

fn compileMultiGridLightUpProgram(program: *OpenGLProgramCommon) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 150
        \\#extension GL_ARB_explicit_attrib_location : enable
    ,
        .{},
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
        \\uniform sampler2D SourceFrontEmissionTexture;
        \\uniform sampler2D SourceBackEmissionTexture;
        \\uniform sampler2D SourceSurfaceColorTexture;
        \\uniform sampler2D SourceNormalPositionTexture;
        \\
        \\smooth in vec2 FragUV;
        \\
        \\layout(location = 0) out vec4 BlendUnitColor[4];
        \\
        \\vec3 ManualSample(sampler2D Sampler)
        \\{
        \\  vec3 Result = texture(Sampler, FragUV).rgb;
        \\  return Result;
        \\}
        \\
        \\void main(void)
        \\{
        \\  vec3 SourceFrontEmission = ManualSample(SourceFrontEmissionTexture).rgb;
        \\  vec3 SourceBackEmission = ManualSample(SourceBackEmissionTexture).rgb;
        \\  vec3 SourceSurfaceColor = ManualSample(SourceSurfaceColorTexture).rgb;
        \\  vec3 SourceNormalPosition = ManualSample(SourceNormalPositionTexture).rgb;
        \\
        \\  vec3 FrontEmission = SourceFrontEmission;
        \\  vec3 BackEmission = SourceBackEmission;
        \\  vec3 SurfaceColor = SourceSurfaceColor;
        \\  vec3 NormalPosition = SourceNormalPosition;
        \\
        \\  BlendUnitColor[0].rgb = FrontEmission;
        \\  BlendUnitColor[1].rgb = BackEmission;
        \\  BlendUnitColor[2].rgb = SurfaceColor;
        \\  BlendUnitColor[3].rgb = NormalPosition;
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
        "SourceFrontEmissionTexture",
        "SourceBackEmissionTexture",
        "SourceSurfaceColorTexture",
        "SourceNormalPositionTexture",
    });
}

fn compileMultiGridLightDownProgram(program: *MultiGridLightDownProgram) void {
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#version 150
        \\#extension GL_ARB_explicit_attrib_location : enable
    ,
        .{},
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
        \\
        \\uniform sampler2D ParentFrontEmissionTexture;
        \\uniform sampler2D ParentBackEmissionTexture;
        \\uniform sampler2D ParentNormalPositionTexture;
        \\
        \\uniform sampler2D OurSurfaceColorTexture;
        \\uniform sampler2D OurNormalPositionTexture;
        \\
        \\uniform vec2 SourceUVStep;
        \\
        \\smooth in vec2 FragUV;
        \\
        \\layout(location = 0) out vec4 BlendUnitColor[2];
        \\
        \\struct light_value
        \\{
        \\  vec3 FrontEmission;
        \\  vec3 BackEmission;
        \\  vec3 Position;
        \\  vec3 Normal;
        \\};
        \\
        \\vec3 ReconstructPosition(vec3 NormalPosition, vec2 UV)
        \\{
        \\  vec3 Result = vec3(UV.x, UV.y, NormalPosition.z); // TODO: Compute the X and Y from the fragment coordinate.
        \\  return Result;
        \\}
        \\
        \\vec3 ReconstructNormal(vec3 NormalPosition)
        \\{
        \\  vec3 Result = ExtendNormalZ(NormalPosition.xy);
        \\  return Result;
        \\}
        \\
        \\light_value ParentSample(vec2 UV)
        \\{
        \\  light_value Result;
        \\  Result.FrontEmission = texture(ParentFrontEmissionTexture, UV).rgb;
        \\  Result.BackEmission = texture(ParentBackEmissionTexture, UV).rgb;
        \\  vec3 NormalPosition = texture(ParentNormalPositionTexture, UV).rgb;
        \\  Result.Position = ReconstructPosition(NormalPosition, UV);
        \\  Result.Normal = ReconstructNormal(NormalPosition);
        \\  return Result;
        \\}
        \\
        \\vec3 TransferLight(vec3 LightPosition,
        \\                   vec3 LightNormal,
        \\                   vec3 LightEmission,
        \\                   vec3 ReflectorPosition,
        \\                   vec3 ReflectorNormal,
        \\                   vec3 ReflectorColor)
        \\{
        \\  float Facing = 1.0f; // clamp(-dot(LightNormal, ReflectorNormal), 0, 1);
        \\  vec3 Distance = LightPosition - ReflectorPosition;
        \\  float DistanceSq = dot(Distance, Distance);
        \\  float Falloff = 1.0f / (1.0f + 100.0f * DistanceSq);
        \\  vec3 Result = Facing * Falloff * ReflectorColor * LightEmission;
        \\  return Result;
        \\}
        \\
        \\void main(void)
        \\{
        \\  light_value Left = ParentSample(FragUV + vec2(-SourceUVStep.x, 0));
        \\  light_value Right = ParentSample(FragUV + vec2(SourceUVStep.x, 0));
        \\  light_value Up = ParentSample(FragUV + vec2(0, -SourceUVStep.y));
        \\  light_value Down = ParentSample(FragUV + vec2(0, SourceUVStep.y));
        \\
        \\  vec3 RefC = texture(OurSurfaceColorTexture, FragUV).rgb;
        \\  vec3 OurNormalPosition = texture(OurNormalPositionTexture, FragUV).rgb;
        \\  vec3 RefP = ReconstructPosition(OurNormalPosition, FragUV);
        \\  vec3 RefN = ReconstructNormal(OurNormalPosition);
        \\
        \\  vec3 DestFrontEmission = (
        \\      TransferLight(Left.Position, Left.Normal, Left.FrontEmission, RefP, RefN, RefC) +
        \\      TransferLight(Right.Position, Right.Normal, Right.FrontEmission, RefP, RefN, RefC) +
        \\      TransferLight(Up.Position, Up.Normal, Up.FrontEmission, RefP, RefN, RefC) +
        \\      TransferLight(Down.Position, Down.Normal, Down.FrontEmission, RefP, RefN, RefC)
        \\  );
        \\  vec3 DestBackEmission = (
        \\      TransferLight(Left.Position, Left.Normal, Left.BackEmission, RefP, RefN, RefC) +
        \\      TransferLight(Right.Position, Right.Normal, Right.BackEmission, RefP, RefN, RefC) +
        \\      TransferLight(Up.Position, Up.Normal, Up.BackEmission, RefP, RefN, RefC) +
        \\      TransferLight(Down.Position, Down.Normal, Down.BackEmission, RefP, RefN, RefC)
        \\  );
        \\
        \\  BlendUnitColor[0].rgb = DestFrontEmission;
        \\  BlendUnitColor[1].rgb = vec3(-dot(RefN, Left.Normal)); //DestBackEmission;
        \\}
    ;

    const program_handle = createProgram(
        @ptrCast(defines[0..defines_length]),
        shader_header_code,
        vertex_code,
        fragment_code,
        &program.common,
    );
    linkSamplers(&program.common, &.{
        "ParentFrontEmissionTexture",
        "ParentBackEmissionTexture",
        "ParentNormalPositionTexture",
        "OurSurfaceColorTexture",
        "OurNormalPositionTexture",
    });

    program.source_uv_step =
        platform.optGLGetUniformLocation.?(program_handle, "SourceUVStep");
}

fn useZBiasProgramBegin(program: *ZBiasProgram, setup: *RenderSetup, alpha_threshold: f32) void {
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

    platform.optGLUniform3fv.?(program.debug_light_position_id, 1, setup.debug_light_position.toGL());
}

fn useResolveMultisampleProgramBegin(program: *ResolveMultisampleProgram) void {
    useProgramBegin(&program.common);

    platform.optGLUniform1i.?(program.sample_count_id, open_gl.max_multi_sample_count);
}

fn useFakeSeedLightingProgramBegin(program: *FakeSeedLightingProgram, setup: *RenderSetup) void {
    useProgramBegin(&program.common);

    platform.optGLUniform3fv.?(program.debug_light_position_id, 1, setup.debug_light_position.toGL());
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
}

fn framebufferTexImage(slot: u32, format: i32, filter_type: i32, width: i32, height: i32) u32 {
    var result: u32 = 0;
    gl.glGenTextures(1, @ptrCast(&result));
    gl.glBindTexture(slot, result);

    if (slot == GL_TEXTURE_2D_MULTISAMPLE) {
        _ = platform.optGLTextImage2DMultiSample.?(
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

fn createFrameBuffer(width: i32, height: i32, flags: u32, color_buffer_count: u32) Framebuffer {
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
        result.depth_handle = framebufferTexImage(slot, DEPTH_COMPONENT_TYPE, filter_type, width, height);
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

fn getDepthPeelReadBuffer(index: u32) *Framebuffer {
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

fn changeToSettings(settings: *RenderSettings) void {
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
        zeroStruct(LightBuffer, light_buffer);
    }
    freeProgram(&open_gl.z_bias_no_depth_peel.common);
    freeProgram(&open_gl.z_bias_depth_peel.common);
    freeProgram(&open_gl.peel_composite);
    freeProgram(&open_gl.final_stretch);
    freeProgram(&open_gl.resolve_multisample.common);
    freeProgram(&open_gl.fake_seed_lighting.common);
    freeProgram(&open_gl.depth_peel_to_lighting);
    freeProgram(&open_gl.multi_grid_light_up);
    freeProgram(&open_gl.multi_grid_light_down.common);

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

    compileZBiasProgram(&open_gl.z_bias_no_depth_peel, false);
    compileZBiasProgram(&open_gl.z_bias_depth_peel, true);
    compilePeelCompositeProgram(&open_gl.peel_composite);
    compileFinalStretchProgram(&open_gl.final_stretch);
    compileResolveMultisampleProgram(&open_gl.resolve_multisample);
    compileFakeSeedLightingProgram(&open_gl.fake_seed_lighting);
    compileDepthPeelToLightingProgram(&open_gl.depth_peel_to_lighting);
    compileMultiGridLightUpProgram(&open_gl.multi_grid_light_up);
    compileMultiGridLightDownProgram(&open_gl.multi_grid_light_down);

    open_gl.resolve_frame_buffer = createFrameBuffer(render_width, render_height, resolve_flags, 1);

    depth_peel_index = 0;
    while (depth_peel_index < open_gl.depth_peel_count) : (depth_peel_index += 1) {
        open_gl.depth_peel_buffers[depth_peel_index] = createFrameBuffer(
            render_width,
            render_height,
            depth_peel_flags,
            COLOR_HANDLE_COUNT,
        );

        if (open_gl.multisampling) {
            open_gl.depth_peel_resolve_buffers[depth_peel_index] = createFrameBuffer(
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
            gl.GL_TEXTURE_2D,
            GL_RGB32F,
            filter_type,
            texture_width,
            texture_height,
        );
        light_buffer.back_emission_texture = framebufferTexImage(
            gl.GL_TEXTURE_2D,
            GL_RGB32F,
            filter_type,
            texture_width,
            texture_height,
        );
        light_buffer.surface_color_texture = framebufferTexImage(
            gl.GL_TEXTURE_2D,
            GL_RGB32F,
            filter_type,
            texture_width,
            texture_height,
        );
        light_buffer.normal_position_texture = framebufferTexImage(
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
}

fn beginScreenFill(framebuffer_handle: u32, width: i32, height: i32) void {
    platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, framebuffer_handle);
    gl.glViewport(0, 0, width, height);
    gl.glScissor(0, 0, width, height);
    gl.glDepthFunc(gl.GL_ALWAYS);

    var vertices: [4]TexturedVertex = [_]TexturedVertex{
        .{ .position = .new(-1, 1, 0, 1), .normal = .zero(), .uv = .new(0, 1), .color = 0xffffffff },
        .{ .position = .new(-1, -1, 0, 1), .normal = .zero(), .uv = .new(0, 0), .color = 0xffffffff },
        .{ .position = .new(1, 1, 0, 1), .normal = .zero(), .uv = .new(1, 1), .color = 0xffffffff },
        .{ .position = .new(1, -1, 0, 1), .normal = .zero(), .uv = .new(1, 0), .color = 0xffffffff },
    };
    platform.optGLBufferData.?(
        GL_ARRAY_BUFFER,
        vertices.len * @sizeOf(TexturedVertex),
        &vertices,
        GL_STREAM_DRAW,
    );
}

fn endScreenFill() void {
    platform.optGLBindFramebufferEXT.?(GL_FRAMEBUFFER, 0);
    gl.glDepthFunc(gl.GL_LEQUAL);
}

fn resolveMultisample(from: *Framebuffer, to: *Framebuffer, width: i32, height: i32) void {
    beginScreenFill(to.framebuffer_handle, width, height);

    useResolveMultisampleProgramBegin(&open_gl.resolve_multisample);

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

fn fakeSeedLighting(setup: *RenderSetup) void {
    const light_buffer: *LightBuffer = &open_gl.light_buffers[0];
    beginScreenFill(light_buffer.write_all_framebuffer, light_buffer.width, light_buffer.height);

    useFakeSeedLightingProgramBegin(&open_gl.fake_seed_lighting, setup);
    platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);
    useProgramEnd(&open_gl.fake_seed_lighting.common);

    endScreenFill();
}

fn computeLightTransport() void {
    // Import depth peel results.
    {
        const source: *Framebuffer = &open_gl.depth_peel_resolve_buffers[0];
        const dest: *LightBuffer = &open_gl.light_buffers[0];
        beginScreenFill(dest.write_all_framebuffer, dest.width, dest.height);

        useProgramBegin(&open_gl.depth_peel_to_lighting);
        bindTexture(GL_TEXTURE0, gl.GL_TEXTURE_2D, source.depth_handle);
        bindTexture(GL_TEXTURE1, gl.GL_TEXTURE_2D, source.color_handle[@intFromEnum(ColorHandleType.SurfaceReflection)]);
        bindTexture(GL_TEXTURE2, gl.GL_TEXTURE_2D, source.color_handle[@intFromEnum(ColorHandleType.Emission)]);
        bindTexture(GL_TEXTURE3, gl.GL_TEXTURE_2D, source.color_handle[@intFromEnum(ColorHandleType.NormalPositionLight)]);

        platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);
        useProgramEnd(&open_gl.depth_peel_to_lighting);

        endScreenFill();
    }

    // Upward phase - build succesively less detailed light buffers.
    {
        var dest_light_buffer_index: u32 = 1;
        while (dest_light_buffer_index < open_gl.light_buffer_count) : (dest_light_buffer_index += 1) {
            const source_light_buffer_index: u32 = dest_light_buffer_index - 1;

            const source: *LightBuffer = &open_gl.light_buffers[source_light_buffer_index];
            const dest: *LightBuffer = &open_gl.light_buffers[dest_light_buffer_index];

            beginScreenFill(dest.write_all_framebuffer, dest.width, dest.height);

            useProgramBegin(&open_gl.multi_grid_light_up);
            bindTexture(GL_TEXTURE0, gl.GL_TEXTURE_2D, source.front_emission_texture);
            bindTexture(GL_TEXTURE1, gl.GL_TEXTURE_2D, source.back_emission_texture);
            bindTexture(GL_TEXTURE2, gl.GL_TEXTURE_2D, source.surface_color_texture);
            bindTexture(GL_TEXTURE3, gl.GL_TEXTURE_2D, source.normal_position_texture);

            platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);
            useProgramEnd(&open_gl.multi_grid_light_up);

            endScreenFill();
        }
        platform.optGLActiveTexture.?(GL_TEXTURE0);
    }

    // Downward phase - transfer light from less-detailed light buffers to higher-detailed ones.
    {
        var source_light_buffer_index: u32 = open_gl.light_buffer_count - 1;
        while (source_light_buffer_index > 0) : (source_light_buffer_index -= 1) {
            const dest_light_buffer_index: u32 = source_light_buffer_index - 1;

            const source: *LightBuffer = &open_gl.light_buffers[source_light_buffer_index];
            const dest: *LightBuffer = &open_gl.light_buffers[dest_light_buffer_index];

            const source_uv_step = Vector2.newI(@divFloor(1, source.width), @divFloor(1, source.height));

            beginScreenFill(dest.write_emission_framebuffer, dest.width, dest.height);

            gl.glEnable(gl.GL_BLEND);
            gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE);

            useMultiGridLightDownProgramBegin(&open_gl.multi_grid_light_down, source_uv_step);
            bindTexture(GL_TEXTURE0, gl.GL_TEXTURE_2D, source.front_emission_texture);
            bindTexture(GL_TEXTURE1, gl.GL_TEXTURE_2D, source.back_emission_texture);
            bindTexture(GL_TEXTURE2, gl.GL_TEXTURE_2D, source.normal_position_texture);
            bindTexture(GL_TEXTURE3, gl.GL_TEXTURE_2D, dest.surface_color_texture);
            bindTexture(GL_TEXTURE4, gl.GL_TEXTURE_2D, dest.normal_position_texture);

            platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, 0, 4);
            useProgramEnd(&open_gl.multi_grid_light_down.common);

            endScreenFill();

            gl.glDisable(gl.GL_BLEND);
        }
        platform.optGLActiveTexture.?(GL_TEXTURE0);
    }
}

fn settingsHaveChanged(a: *RenderSettings, b: *RenderSettings) bool {
    _ = a;
    _ = b;
    return true;
}

pub fn renderCommands(
    commands: *RenderCommands,
    draw_region: Rectangle2i,
    window_width: i32,
    window_height: i32,
) callconv(.c) void {
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

    const settings: *RenderSettings = &commands.settings;
    if (!settings.equals(&open_gl.current_settings)) {
        changeToSettings(settings);
    }

    const use_render_targets: bool = platform.optGLBindFramebufferEXT != null;
    std.debug.assert(use_render_targets);

    const render_width: i32 = @intCast(settings.width);
    const render_height: i32 = @intCast(settings.height);

    std.debug.assert(open_gl.depth_peel_count > 0);
    const max_render_target_index: u32 = open_gl.depth_peel_count - 1;

    var target_index: u32 = 0;
    while (target_index <= open_gl.depth_peel_count) : (target_index += 1) {
        bindFrameBuffer(&open_gl.depth_peel_buffers[target_index], render_width, render_height);

        gl.glScissor(0, 0, render_width, render_height);
        gl.glClearDepth(1);
        if (target_index == max_render_target_index) {
            gl.glClearColor(
                commands.clear_color.r(),
                commands.clear_color.g(),
                commands.clear_color.b(),
                1,
            );
        } else {
            gl.glClearColor(0, 0, 0, 0);
        }
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
    }
    bindFrameBuffer(null, render_width, render_height);

    bindFrameBuffer(&open_gl.depth_peel_buffers[0], render_width, render_height);

    var debug_setup: ?*RenderSetup = null;
    var peeling: bool = false;
    var on_peel_index: u32 = 0;
    var peel_header_restore: [*]u8 = undefined;
    var header_at: [*]u8 = commands.push_buffer_base;
    while (@intFromPtr(header_at) < @intFromPtr(commands.push_buffer_data_at)) : (header_at += @sizeOf(RenderEntryHeader)) {
        const header: *RenderEntryHeader = @ptrCast(@alignCast(header_at));
        const alignment: usize = switch (header.type) {
            .RenderEntryTexturedQuads => @alignOf(RenderEntryTexturedQuads),
            .RenderEntryDepthClear, .RenderEntryBeginPeels, .RenderEntryEndPeels => @alignOf(u32),
        };

        const header_address = @intFromPtr(header);
        const data_address = header_address + @sizeOf(RenderEntryHeader);
        const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        const data: *anyopaque = @ptrFromInt(aligned_address);

        header_at += aligned_address - data_address;

        switch (header.type) {
            .RenderEntryBeginPeels => {
                peel_header_restore = header_at;
            },
            .RenderEntryEndPeels => {
                if (open_gl.multisampling) {
                    const from: *Framebuffer = &open_gl.depth_peel_buffers[on_peel_index];
                    const to: *Framebuffer = &open_gl.depth_peel_resolve_buffers[on_peel_index];

                    if (true) {
                        resolveMultisample(from, to, render_width, render_height);
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
                    peeling = on_peel_index > 0;
                } else {
                    std.debug.assert(on_peel_index == max_render_target_index);

                    const peel_buffer: *Framebuffer = getDepthPeelReadBuffer(0);
                    bindFrameBuffer(peel_buffer, render_width, render_height);
                    peeling = false;
                    on_peel_index = 0;
                }
            },
            .RenderEntryDepthClear => {
                gl.glClear(gl.GL_DEPTH_BUFFER_BIT);
            },
            .RenderEntryTexturedQuads => {
                const entry: *RenderEntryTexturedQuads = @ptrCast(@alignCast(data));
                header_at += @sizeOf(RenderEntryTexturedQuads);

                const setup: *RenderSetup = &entry.setup;

                if (debug_setup == null) {
                    // TODO: Remove this eventually.
                    debug_setup = setup;
                }

                var clip_rect: Rectangle2i = setup.clip_rect;
                gl.glScissor(
                    clip_rect.min.x(),
                    clip_rect.min.y(),
                    clip_rect.max.x() - clip_rect.min.x(),
                    clip_rect.max.y() - clip_rect.min.y(),
                );

                platform.optGLBufferData.?(
                    GL_ARRAY_BUFFER,
                    commands.vertex_count * @sizeOf(TexturedVertex),
                    commands.vertex_array,
                    GL_STREAM_DRAW,
                );

                var program: *ZBiasProgram = &open_gl.z_bias_no_depth_peel;
                var alpha_threshold: f32 = 0.01;
                if (peeling) {
                    const peel_buffer: *Framebuffer = getDepthPeelReadBuffer(on_peel_index - 1);

                    program = &open_gl.z_bias_depth_peel;
                    platform.optGLActiveTexture.?(GL_TEXTURE1);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, peel_buffer.depth_handle);
                    platform.optGLActiveTexture.?(GL_TEXTURE0);

                    if (on_peel_index == max_render_target_index) {
                        alpha_threshold = 0.9;
                    }
                }

                useZBiasProgramBegin(program, setup, alpha_threshold);

                var vertex_index: u32 = entry.vertex_array_offset;
                while (vertex_index < (entry.vertex_array_offset + 4 * entry.quad_count)) : (vertex_index += 4) {
                    const opt_bitmap: ?*LoadedBitmap = commands.quad_bitmaps[vertex_index >> 2];

                    // TODO: This assertion shouldn't fire, but it does. The issue originates in debug_ui.textOp.
                    // std.debug.assert(opt_bitmap != null);

                    if (opt_bitmap) |bitmap| {
                        gl.glBindTexture(gl.GL_TEXTURE_2D, bitmap.texture_handle);
                    }

                    platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, @intCast(vertex_index), 4);
                }
                gl.glBindTexture(gl.GL_TEXTURE_2D, 0);

                useProgramEnd(&program.common);
                if (peeling) {
                    platform.optGLActiveTexture.?(GL_TEXTURE1);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
                    platform.optGLActiveTexture.?(GL_TEXTURE0);
                }
            },
        }
    }

    gl.glDisable(gl.GL_DEPTH_TEST);
    gl.glDisable(gl.GL_BLEND);

    computeLightTransport();

    platform.optGLBindFramebufferEXT.?(GL_DRAW_FRAMEBUFFER, open_gl.resolve_frame_buffer.framebuffer_handle);
    gl.glViewport(0, 0, render_width, render_height);
    gl.glScissor(0, 0, render_width, render_height);

    var vertices: [4]TexturedVertex = [_]TexturedVertex{
        .{ .position = .new(-1, 1, 0, 1), .normal = .zero(), .uv = .new(0, 1), .color = 0xffffffff },
        .{ .position = .new(-1, -1, 0, 1), .normal = .zero(), .uv = .new(0, 0), .color = 0xffffffff },
        .{ .position = .new(1, 1, 0, 1), .normal = .zero(), .uv = .new(1, 1), .color = 0xffffffff },
        .{ .position = .new(1, -1, 0, 1), .normal = .zero(), .uv = .new(1, 0), .color = 0xffffffff },
    };
    platform.optGLBufferData.?(
        GL_ARRAY_BUFFER,
        vertices.len * @sizeOf(TexturedVertex),
        &vertices,
        GL_STREAM_DRAW,
    );

    useProgramBegin(&open_gl.peel_composite);
    var texture_bind_index: u32 = GL_TEXTURE0;
    var peel_index: u32 = 0;
    while (peel_index <= max_render_target_index) : (peel_index += 1) {
        const peel_buffer: *Framebuffer = getDepthPeelReadBuffer(peel_index);
        platform.optGLActiveTexture.?(texture_bind_index);
        texture_bind_index += 1;
        gl.glBindTexture(gl.GL_TEXTURE_2D, peel_buffer.color_handle[@intFromEnum(ColorHandleType.SurfaceReflection)]);
        platform.optGLActiveTexture.?(texture_bind_index);
        texture_bind_index += 1;
        gl.glBindTexture(gl.GL_TEXTURE_2D, peel_buffer.color_handle[@intFromEnum(ColorHandleType.NormalPositionLight)]);
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

pub fn manageTextures(first_op: ?*TextureOp) void {
    var opt_op: ?*render.TextureOp = first_op;
    while (opt_op) |op| : (opt_op = op.next) {
        if (op.is_allocate) {
            op.op.allocate.result_handle.* = allocateTexture(
                op.op.allocate.width,
                op.op.allocate.height,
                op.op.allocate.data,
            );
        } else {
            gl.glDeleteTextures(1, &op.op.deallocate.handle);
        }
    }
}

fn allocateTexture(width: i32, height: i32, data: ?*anyopaque) callconv(.c) u32 {
    var handle: u32 = 0;

    gl.glGenTextures(1, &handle);
    gl.glBindTexture(gl.GL_TEXTURE_2D, handle);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        open_gl.default_sprite_texture_format,
        width,
        height,
        0,
        gl.GL_BGRA_EXT,
        gl.GL_UNSIGNED_BYTE,
        data,
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);

    return handle;
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

    shared.notImplemented();

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
