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
pub const GL_DEPTH_ATTACHMENT = 0x8D00;
pub const GL_FRAME_BUFFER_COMPLETE = 0x8CD5;

pub const GL_DEPTH_COMPONENT16 = 0x81A5;
pub const GL_DEPTH_COMPONENT24 = 0x81A6;
pub const GL_DEPTH_COMPONENT32 = 0x81A7;
pub const GL_DEPTH_COMPONENT32F = 0x8CAC;

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

// Build options.
const INTERNAL = shared.INTERNAL;

const RenderCommands = shared.RenderCommands;
const GameRenderPrep = shared.GameRenderPrep;
const TexturedVertex = shared.TexturedVertex;
const RenderGroup = rendergroup.RenderGroup;
const RenderEntryHeader = rendergroup.RenderEntryHeader;
const RenderEntryTexturedQuads = rendergroup.RenderEntryTexturedQuads;
const RenderEntryClear = rendergroup.RenderEntryClear;
const RenderEntryClipRect = rendergroup.RenderEntryClipRect;
const RenderEntryBitmap = rendergroup.RenderEntryBitmap;
const RenderEntryCube = rendergroup.RenderEntryCube;
const RenderEntryRectangle = rendergroup.RenderEntryRectangle;
const RenderEntrySaturation = rendergroup.RenderEntrySaturation;
const RenderEntryBlendRenderTarget = rendergroup.RenderEntryBlendRenderTarget;
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
const SortSpriteBound = render.SortSpriteBound;
const SpriteFlag = render.SpriteFlag;
const SpriteEdge = render.SpriteEdge;

const debug_color_table = shared.debug_color_table;
var global_config = &@import("config.zig").global_config;

// TODO: How do we avoid having this import here?
const WINAPI = @import("std").os.windows.WINAPI;
fn glDebugProc(
    source: u32,
    message_type: u32,
    id: u32,
    severity: u32,
    length: i32,
    message: [*]const u8,
    user_param: ?*const anyopaque,
) callconv(WINAPI) void {
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

pub const gl = struct {
    // TODO: How do we import OpenGL on other platforms here?
    usingnamespace @import("win32").graphics.open_gl;
};

const OpenGL = struct {
    max_multi_sample_count: i32 = 0,
    supports_srgb_frame_buffer: bool = false,

    default_sprite_texture_format: i32 = 0,
    default_framebuffer_texture_format: i32 = 0,

    vertex_buffer: u32 = 0,

    reserved_blit_texture: u32 = 0,
    basic_z_bias_program: u32 = 0,

    transform_id: i32 = 0,
    texture_sampler_id: i32 = 0,

    white_bitmap: LoadedBitmap = undefined,
    white: [4][4]u32 = undefined,

    vert_position_id: i32 = 0,
    vert_uv_id: i32 = 0,
    vert_color_id: i32 = 0,
};

pub var open_gl: OpenGL = .{};

var frame_buffer_count: u32 = 0;
var frame_buffer_handles: [256]c_uint = [1]c_uint{0} ** 256;
var frame_buffer_textures: [256]c_uint = [1]c_uint{0} ** 256;

pub const Info = struct {
    is_modern_context: bool,
    vendor: ?*const u8,
    renderer: ?*const u8,
    version: ?*const u8,
    shader_language_version: ?*const u8 = undefined,
    extensions: ?*const u8,

    gl_ext_texture_srgb: bool = false,
    gl_ext_framebuffer_srgb: bool = false,
    gl_arb_framebuffer_object: bool = false,

    pub fn get(is_modern_context: bool) Info {
        var result: Info = .{
            .is_modern_context = is_modern_context,
            .vendor = gl.glGetString(gl.GL_VENDOR),
            .renderer = gl.glGetString(gl.GL_RENDERER),
            .version = gl.glGetString(gl.GL_VERSION),
            .extensions = gl.glGetString(gl.GL_EXTENSIONS),
        };

        if (is_modern_context) {
            result.shader_language_version = gl.glGetString(GL_SHADING_LANGUAGE_VERSION);
        } else {
            result.shader_language_version = @ptrCast("(none)");
        }

        if (result.extensions) |extensions| {
            var at: [*]const u8 = @ptrCast(extensions);
            while (at[0] != 0) {
                while (shared.isWhitespace(at[0])) {
                    at += 1;
                }
                var end = at;
                while (end[0] != 0 and !shared.isWhitespace(end[0])) {
                    end += 1;
                }

                const count = @intFromPtr(end) - @intFromPtr(at);

                if (shared.stringsWithOneLengthAreEqual(at, count, "GL_EXT_texture_sRGB")) {
                    result.gl_ext_texture_srgb = true;
                } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_EXT_framebuffer_sRGB")) {
                    result.gl_ext_framebuffer_srgb = true;
                } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_ARB_framebuffer_sRGB")) {
                    result.gl_ext_framebuffer_srgb = true;
                } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_ARB_framebuffer_object")) {
                    result.gl_arb_framebuffer_object = true;
                }

                at = end;
            }
        } else {
            _ = gl.glGetError();
            var index: u32 = 0;
            while (gl.glGetError() == gl.GL_NO_ERROR) : (index += 1) {
                if (platform.optGLGetStringi.?(gl.GL_EXTENSIONS, index)) |extension| {
                    const count = shared.stringLength(@ptrCast(extension));
                    const at: [*]const u8 = @ptrCast(extension);

                    if (shared.stringsWithOneLengthAreEqual(at, count, "GL_EXT_texture_sRGB")) {
                        result.gl_ext_texture_srgb = true;
                    } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_EXT_framebuffer_sRGB")) {
                        result.gl_ext_framebuffer_srgb = true;
                    } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_ARB_framebuffer_sRGB")) {
                        result.gl_ext_framebuffer_srgb = true;
                    } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_ARB_framebuffer_object")) {
                        result.gl_arb_framebuffer_object = true;
                    }
                } else {
                    break;
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
    var shader_sim_tex_read_srgb = true;
    var shader_sim_tex_write_srgb = true;

    gl.glGenTextures(1, &open_gl.reserved_blit_texture);

    gl.glGetIntegerv(GL_MAX_COLOR_TEXTURE_SAMPLES, &open_gl.max_multi_sample_count);
    if (open_gl.max_multi_sample_count > 16) {
        open_gl.max_multi_sample_count = 16;
    }

    open_gl.default_sprite_texture_format = gl.GL_RGBA8;
    open_gl.default_framebuffer_texture_format = gl.GL_RGBA8;

    if (info.gl_ext_texture_srgb) {
        open_gl.default_sprite_texture_format = GL_SRGB8_ALPHA8;
        shader_sim_tex_read_srgb = false;
    }

    if (framebuffer_supports_sRGB and info.gl_ext_framebuffer_srgb) {
        if (platform.optGLTextImage2DMultiSample) |glTexImage2DMultisample| {
            var test_texture: u32 = undefined;
            gl.glGenTextures(1, &test_texture);
            gl.glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, test_texture);

            _ = gl.glGetError();
            _ = glTexImage2DMultisample(
                GL_TEXTURE_2D_MULTISAMPLE,
                open_gl.max_multi_sample_count,
                GL_SRGB8_ALPHA8,
                1920,
                1080,
                false,
            );

            if (gl.glGetError() == gl.GL_NO_ERROR) {
                open_gl.default_framebuffer_texture_format = GL_SRGB8_ALPHA8;
                gl.glEnable(GL_FRAMEBUFFER_SRGB);
                shader_sim_tex_write_srgb = false;
            }

            gl.glDeleteTextures(1, &test_texture);
            gl.glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, test_texture);
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

    const header_code =
        \\#version 130
        \\// Header code
    ;
    var defines: [1024]u8 = undefined;
    const defines_length = shared.formatString(
        defines.len,
        &defines,
        \\#define ShaderSimTexReadSRGB %d
        \\#define ShaderSimTexWriteSRGB %d
    ,
        .{
            @as(i32, @intCast(@intFromBool(shader_sim_tex_read_srgb))),
            @as(i32, @intCast(@intFromBool(shader_sim_tex_write_srgb))),
        },
    );
    const vertex_code =
        \\// Vertex code
        \\uniform mat4x4 Transform;
        \\in vec4 VertP;
        \\in vec2 VertUV;
        \\in vec4 VertColor;
        \\
        \\smooth out vec2 FragUV;
        \\smooth out vec4 FragColor;
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
        \\  gl_Position = vec4(ZMinTransform.x, ZMinTransform.y, ZMaxTransform.z, ZMinTransform.w);
        \\
        \\  FragUV = VertUV.xy;
        \\  FragColor = VertColor;
        \\}
    ;
    const fragment_code =
        \\// Fragment code
        \\uniform sampler2D TextureSampler;
        \\out vec4 ResultColor;
        \\smooth in vec2 FragUV;
        \\smooth in vec4 FragColor;
        \\
        \\void main(void)
        \\{
        \\  //vec4 TexSample = vec4(1, 0, 0, 1);
        \\  vec4 TexSample = texture(TextureSampler, FragUV);
        \\
        \\  if (TexSample.a > 0) {
        \\#if ShaderSimTexReadSRGB
        \\    TexSample.rgb *= TexSample.rgb;
        \\#endif
        \\
        \\    ResultColor = FragColor * TexSample;
        \\
        \\#if ShaderSimTexWriteSRGB
        \\    ResultColor.rgb = sqrt(ResultColor.rgb);
        \\#endif
        \\  } else {
        \\    discard;
        \\  }
        \\}
    ;
    open_gl.basic_z_bias_program = createProgram(@ptrCast(defines[0..defines_length]), header_code, vertex_code, fragment_code);
    open_gl.transform_id = platform.optGLGetUniformLocation.?(open_gl.basic_z_bias_program, "Transform");
    open_gl.texture_sampler_id = platform.optGLGetUniformLocation.?(open_gl.basic_z_bias_program, "TextureSampler");
    open_gl.vert_position_id = platform.optGLGetAttribLocation.?(open_gl.basic_z_bias_program, "VertP");
    open_gl.vert_uv_id = platform.optGLGetAttribLocation.?(open_gl.basic_z_bias_program, "VertUV");
    open_gl.vert_color_id = platform.optGLGetAttribLocation.?(open_gl.basic_z_bias_program, "VertColor");

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

fn bindFrameBuffer(target_index: u32, draw_region: Rectangle2i) void {
    if (platform.optGlBindFramebufferEXT) |glBindFramebuffer| {
        const window_width: i32 = draw_region.getWidth();
        const window_height: i32 = draw_region.getHeight();

        glBindFramebuffer(GL_FRAMEBUFFER, frame_buffer_handles[target_index]);
        gl.glViewport(0, 0, window_width, window_height);
    }
}

pub fn renderCommands(
    commands: *RenderCommands,
    prep: *GameRenderPrep,
    draw_region: Rectangle2i,
    window_width: i32,
    window_height: i32,
) callconv(.C) void {
    gl.glDepthMask(gl.GL_TRUE);
    gl.glColorMask(gl.GL_TRUE, gl.GL_TRUE, gl.GL_TRUE, gl.GL_TRUE);
    gl.glDepthFunc(gl.GL_LEQUAL);
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE);
    gl.glEnable(GL_SAMPLE_ALPHA_TO_ONE);
    gl.glEnable(GL_MULTISAMPLE);

    gl.glEnable(gl.GL_SCISSOR_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

    std.debug.assert(commands.max_render_target_index < frame_buffer_handles.len);

    const use_render_targets: bool = platform.optGlBindFramebufferEXT != null;
    std.debug.assert(use_render_targets);

    const max_render_target_index: u32 = commands.max_render_target_index;
    if (max_render_target_index >= frame_buffer_count) {
        const new_frame_buffer_count: u32 = max_render_target_index + 1;
        std.debug.assert(new_frame_buffer_count < frame_buffer_handles.len);

        const new_count: u32 = new_frame_buffer_count - frame_buffer_count;
        if (platform.optGlGenFramebuffersEXT) |glGenFrameBuffers| {
            glGenFrameBuffers(new_count, @ptrCast(&frame_buffer_handles[frame_buffer_count]));
        }

        if (platform.optGlBindFramebufferEXT) |glBindFramebuffer| {
            if (platform.optGlFrameBufferTexture2DEXT) |glBindFrameBufferTexture2D| {
                if (platform.optGLTextImage2DMultiSample) |glTexImage2DMultisample| {
                    var target_index: u32 = frame_buffer_count;
                    while (target_index <= commands.max_render_target_index) : (target_index += 1) {
                        // std.debug.assert(gl.glGetError() == gl.GL_NO_ERROR);

                        const slot = GL_TEXTURE_2D_MULTISAMPLE;
                        var texture_handle: [2]u32 = undefined;
                        gl.glGenTextures(2, @ptrCast(&texture_handle));
                        gl.glBindTexture(slot, texture_handle[0]);

                        // std.debug.assert(gl.glGetError() == gl.GL_NO_ERROR);

                        if (slot == GL_TEXTURE_2D_MULTISAMPLE) {
                            _ = glTexImage2DMultisample(
                                slot,
                                open_gl.max_multi_sample_count,
                                open_gl.default_framebuffer_texture_format,
                                draw_region.getWidth(),
                                draw_region.getHeight(),
                                false,
                            );
                        } else {
                            gl.glTexImage2D(
                                slot,
                                0,
                                open_gl.default_framebuffer_texture_format,
                                draw_region.getWidth(),
                                draw_region.getHeight(),
                                0,
                                gl.GL_BGRA_EXT,
                                gl.GL_UNSIGNED_BYTE,
                                null,
                            );
                        }

                        // std.debug.assert(gl.glGetError() == gl.GL_NO_ERROR);

                        gl.glBindTexture(slot, texture_handle[1]);
                        _ = glTexImage2DMultisample(
                            slot,
                            open_gl.max_multi_sample_count,
                            // TODO: Check if going with a 16-bit depth buffer would be faster and still have enough
                            // quality (it should, wer don't have long draw distances).
                            GL_DEPTH_COMPONENT32,
                            draw_region.getWidth(),
                            draw_region.getHeight(),
                            false,
                        );

                        // std.debug.assert(gl.glGetError() == gl.GL_NO_ERROR);

                        gl.glBindTexture(slot, 0);

                        // const texture_handle: u32 = allocateTexture(draw_region.getWidth(), draw_region.getHeight(), null);
                        frame_buffer_textures[target_index] = texture_handle[0];

                        glBindFramebuffer(GL_FRAMEBUFFER, frame_buffer_handles[target_index]);
                        glBindFrameBufferTexture2D(
                            GL_FRAMEBUFFER,
                            GL_COLOR_ATTACHMENT0,
                            slot,
                            texture_handle[0],
                            0,
                        );
                        glBindFrameBufferTexture2D(
                            GL_FRAMEBUFFER,
                            GL_DEPTH_ATTACHMENT,
                            slot,
                            texture_handle[1],
                            0,
                        );

                        if (platform.optGlCheckFramebufferStatusEXT) |checkFramebufferStatus| {
                            const status: u32 = checkFramebufferStatus(GL_FRAMEBUFFER);
                            std.debug.assert(status == GL_FRAME_BUFFER_COMPLETE);
                        }
                    }
                }
            }
        }

        frame_buffer_count = new_frame_buffer_count;
    }

    var target_index: u32 = 0;
    while (target_index <= max_render_target_index) : (target_index += 1) {
        if (use_render_targets) {
            bindFrameBuffer(target_index, draw_region);
        }

        if (target_index == 0) {
            gl.glScissor(0, 0, window_width, window_height);
        } else {
            gl.glScissor(0, 0, draw_region.getWidth(), draw_region.getHeight());
        }

        gl.glClearDepth(1);
        gl.glClearColor(
            commands.clear_color.r(),
            commands.clear_color.g(),
            commands.clear_color.b(),
            commands.clear_color.a(),
        );
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
    }

    const clip_scale_x: f32 = math.safeRatio0(@floatFromInt(draw_region.getWidth()), @floatFromInt(commands.width));
    const clip_scale_y: f32 = math.safeRatio0(@floatFromInt(draw_region.getHeight()), @floatFromInt(commands.height));

    var clip_rect_index: u32 = 0xffffffff;
    var current_render_target_index: u32 = 0xffffffff;
    var header_at: [*]u8 = commands.push_buffer_base;
    var proj: Matrix4x4 = .identity();
    while (@intFromPtr(header_at) < @intFromPtr(commands.push_buffer_data_at)) : (header_at += @sizeOf(RenderEntryHeader)) {
        const header: *RenderEntryHeader = @ptrCast(@alignCast(header_at));
        const alignment: usize = switch (header.type) {
            .RenderEntryTexturedQuads => @alignOf(RenderEntryTexturedQuads),
            .RenderEntryBlendRenderTarget => @alignOf(RenderEntryBlendRenderTarget),
            .RenderEntryClipRect => @alignOf(RenderEntryClipRect),
        };

        const header_address = @intFromPtr(header);
        const data_address = header_address + @sizeOf(RenderEntryHeader);
        const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        const data: *anyopaque = @ptrFromInt(aligned_address);

        header_at += aligned_address - data_address;

        if (use_render_targets or
            prep.clip_rects[header.clip_rect_index].render_target_index <= max_render_target_index)
        {
            if (header.type != .RenderEntryClipRect and clip_rect_index != header.clip_rect_index) {
                clip_rect_index = header.clip_rect_index;

                std.debug.assert(clip_rect_index < commands.clip_rect_count);

                const clip: RenderEntryClipRect = prep.clip_rects[clip_rect_index];
                proj = clip.proj.transpose();
                var clip_rect: Rectangle2i = clip.rect;

                if (current_render_target_index != clip.render_target_index) {
                    current_render_target_index = clip.render_target_index;
                    std.debug.assert(current_render_target_index <= max_render_target_index);
                    if (use_render_targets) {
                        bindFrameBuffer(current_render_target_index, draw_region);
                    }
                }

                _ = clip_rect.min.setX(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.min.x())) * clip_scale_x),
                );
                _ = clip_rect.max.setX(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.max.x())) * clip_scale_x),
                );
                _ = clip_rect.min.setY(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.min.y())) * clip_scale_y),
                );
                _ = clip_rect.max.setY(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.max.y())) * clip_scale_y),
                );

                if (!use_render_targets or clip.render_target_index == 0) {
                    clip_rect = clip_rect.offsetBy(draw_region.min);
                }

                gl.glScissor(
                    clip_rect.min.x(),
                    clip_rect.min.y(),
                    clip_rect.max.x() - clip_rect.min.x(),
                    clip_rect.max.y() - clip_rect.min.y(),
                );
            }

            switch (header.type) {
                .RenderEntryTexturedQuads => {
                    const entry: *RenderEntryTexturedQuads = @ptrCast(@alignCast(data));
                    header_at += @sizeOf(RenderEntryTexturedQuads);

                    const uv_array_index: u32 = @intCast(open_gl.vert_uv_id);
                    const color_array_index: u32 = @intCast(open_gl.vert_color_id);
                    const position_array_index: u32 = @intCast(open_gl.vert_position_id);

                    platform.optGLBufferData.?(
                        GL_ARRAY_BUFFER,
                        commands.vertex_count * @sizeOf(TexturedVertex),
                        commands.vertex_array,
                        GL_STREAM_DRAW,
                    );

                    platform.optGLEnableVertexAttribArray.?(uv_array_index);
                    platform.optGLEnableVertexAttribArray.?(color_array_index);
                    platform.optGLEnableVertexAttribArray.?(position_array_index);

                    platform.optGLVertexAttribPointer.?(
                        uv_array_index,
                        2,
                        gl.GL_FLOAT,
                        false,
                        @sizeOf(TexturedVertex),
                        @ptrFromInt(@offsetOf(TexturedVertex, "uv")),
                    );
                    platform.optGLVertexAttribPointer.?(
                        color_array_index,
                        4,
                        gl.GL_UNSIGNED_BYTE,
                        true,
                        @sizeOf(TexturedVertex),
                        @ptrFromInt(@offsetOf(TexturedVertex, "color")),
                    );
                    platform.optGLVertexAttribPointer.?(
                        position_array_index,
                        4,
                        gl.GL_FLOAT,
                        false,
                        @sizeOf(TexturedVertex),
                        @ptrFromInt(@offsetOf(TexturedVertex, "position")),
                    );

                    platform.optGLUseProgram.?(open_gl.basic_z_bias_program);
                    platform.optGLUniformMatrix4fv.?(open_gl.transform_id, 1, false, proj.toGL());
                    platform.optGLUniform1i.?(open_gl.texture_sampler_id, 0);

                    var vertex_index: u32 = entry.vertex_array_offset;
                    while (vertex_index < (entry.vertex_array_offset + 4 * entry.quad_count)) : (vertex_index += 4) {
                        const opt_bitmap: ?*LoadedBitmap = commands.quad_bitmaps[vertex_index >> 2];

                        // TODO: This assertion shouldn't fire, but it does.
                        // std.debug.assert(opt_bitmap != null);

                        if (opt_bitmap) |bitmap| {
                            gl.glBindTexture(gl.GL_TEXTURE_2D, bitmap.texture_handle);
                        }

                        platform.optGLDrawArrays.?(gl.GL_TRIANGLE_STRIP, @intCast(vertex_index), 4);
                    }

                    platform.optGLUseProgram.?(0);

                    platform.optGLDisableVertexAttribArray.?(uv_array_index);
                    platform.optGLDisableVertexAttribArray.?(color_array_index);
                    platform.optGLDisableVertexAttribArray.?(position_array_index);
                },
                .RenderEntryBlendRenderTarget => {
                    header_at += @sizeOf(RenderEntryBlendRenderTarget);
                    const entry: *RenderEntryBlendRenderTarget = @ptrCast(@alignCast(data));
                    if (use_render_targets) {
                        gl.glBindTexture(gl.GL_TEXTURE_2D, frame_buffer_textures[entry.source_target_index]);
                        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
                        drawRectangle(
                            .zero(),
                            .new(@floatFromInt(commands.width), @floatFromInt(commands.height), 0),
                            .new(1, 1, 1, entry.alpha),
                            null,
                            null,
                        );
                        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
                    }
                },
                .RenderEntryClipRect => {
                    // These are being handled elsewhere currently.
                    header_at += @sizeOf(RenderEntryClipRect);
                },
            }
        }
    }

    if (platform.optGlBindFramebufferEXT) |glBindFramebuffer| {
        if (platform.optGLBlitFrameBuffer) |glBlitFramebuffer| {
            glBindFramebuffer(GL_READ_FRAMEBUFFER, frame_buffer_handles[0]);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
            gl.glViewport(draw_region.min.x(), draw_region.min.y(), window_width, window_height);
            glBlitFramebuffer(
                0,
                0,
                draw_region.getWidth(),
                draw_region.getHeight(),
                draw_region.min.x(),
                draw_region.min.y(),
                draw_region.max.x(),
                draw_region.max.y(),
                gl.GL_COLOR_BUFFER_BIT,
                gl.GL_LINEAR,
            );
        }
    }

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
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

fn allocateTexture(width: i32, height: i32, data: ?*anyopaque) callconv(.C) u32 {
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

    bindFrameBuffer(0, draw_region);

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
) u32 {
    const glShaderSource = platform.optGLShaderSource.?;
    const glCreateShader = platform.optGLCreateShader.?;
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
        header,
        defines,
        vertex_code,
    };
    glShaderSource(vertex_shader_id, vertex_shader_code.len, &vertex_shader_code, null);
    glCompileShader(vertex_shader_id);

    const fragment_shader_id: u32 = glCreateShader(GL_FRAGMENT_SHADER);
    var fragment_shader_code = [_][*:0]const u8{
        header,
        defines,
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

    return program_id;
}
