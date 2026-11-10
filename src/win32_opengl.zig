const std = @import("std");
const win32 = @import("win32").everything;
const math = @import("math.zig");
const types = @import("types.zig");
const shared = @import("shared.zig");
const renderer = @import("renderer.zig");
const opengl = @import("renderer_opengl.zig");
const win32_opengl = @import("win32_opengl.zig");

const gl = @import("gl_c");

// Types.
const OpenGL = opengl.OpenGL;
const TextureQueue = renderer.TextureQueue;
const TexturedVertex = renderer.TexturedVertex;
const RendererTexture = renderer.RendererTexture;
const RenderCommands = renderer.RenderCommands;
const PlatformRenderer = renderer.PlatformRenderer;
const Rectangle2i = math.Rectangle2i;
const Vector2u = math.Vector2u;

const INTERNAL = shared.INTERNAL;

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

// Manual import of a function that is incorrectly defined in zigwin32.
// Remove once this is resloved: https://github.com/marlersoft/zigwin32/issues/33
pub extern "gdi32" fn DescribePixelFormat(
    hdc: ?win32.HDC,
    iPixelFormat: c_int, // The field that is wrong in zigwin32.
    nBytes: u32,
    ppfd: ?*win32.PIXELFORMATDESCRIPTOR,
) callconv(.winapi) i32;

const WglSwapIntervalEXT: type = fn (interval: i32) callconv(.winapi) bool;
var optWglSwapIntervalEXT: ?*const WglSwapIntervalEXT = null;

const WglCreateContextAttribsARB: type = fn (
    hdc: ?win32.HDC,
    share_context: ?win32.HGLRC,
    attrib_list: ?[*:0]const c_int,
) callconv(.winapi) ?win32.HGLRC;
var optWglCreateContextAttribsARB: ?*const WglCreateContextAttribsARB = null;

const WglChoosePixelFormatARB: type = fn (
    hdc: ?win32.HDC,
    piAttribIList: [*:0]const c_int,
    pfAttribFList: ?[*:0]const f32,
    nMaxFormats: c_uint,
    piFormats: *c_int,
    nNumFormats: *c_uint,
) callconv(.winapi) win32.BOOL;
var optWglChoosePixelFormatARB: ?*const WglChoosePixelFormatARB = null;

const WglGetExtensionsStringEXT: type = fn (hdc: win32.HDC) callconv(.winapi) ?*u8;
pub var optWglGetExtensionsStringEXT: ?*const WglGetExtensionsStringEXT = null;

const opengl_flags: c_int = if (INTERNAL)
    // 0 | opengl.WGL_CONTEXT_DEBUG_BIT_ARB
    WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB | WGL_CONTEXT_DEBUG_BIT_ARB
else
    WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB;
const opengl_attribs = [_:0]c_int{
    WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
    WGL_CONTEXT_MINOR_VERSION_ARB, 3,
    WGL_CONTEXT_FLAGS_ARB,         opengl_flags,
    // WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,
    WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
    0,
};

fn setPixelFormat(open_gl: *OpenGL, window_dc: ?win32.HDC) void {
    var suggested_pixel_format_index: c_int = 0;
    var extended_pick: c_uint = 0;

    if (optWglChoosePixelFormatARB) |wglChoosePixelFormatARB| {
        var int_attrib_list = [_:0]c_int{
            WGL_DRAW_TO_WINDOW_ARB,           win32.GL_TRUE,
            WGL_ACCELERATION_ARB,             WGL_FULL_ACCELERATION_ARB,
            WGL_SUPPORT_OPENGL_ARB,           win32.GL_TRUE,
            WGL_DOUBLE_BUFFER_ARB,            win32.GL_TRUE,
            WGL_PIXEL_TYPE_ARB,               WGL_TYPE_RGBA_ARB,
            WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB, win32.GL_TRUE,
            0,
        };

        if (!open_gl.supports_srgb_frame_buffer) {
            int_attrib_list[10] = 0;
        }

        if (wglChoosePixelFormatARB(
            window_dc,
            &int_attrib_list,
            null,
            1,
            &suggested_pixel_format_index,
            &extended_pick,
        ) == 0) {
            outputLastGLError("wglChoosePixelFormatARB failed");
        }
    }

    if (extended_pick == 0) {
        var desired_pixel_format: win32.PIXELFORMATDESCRIPTOR = .{
            .nSize = @sizeOf(win32.PIXELFORMATDESCRIPTOR),
            .nVersion = 1,
            .iPixelType = win32.PFD_TYPE_RGBA,
            .dwFlags = win32.PFD_FLAGS{
                .SUPPORT_OPENGL = 1,
                .DRAW_TO_WINDOW = 1,
                .DOUBLEBUFFER = 1,
            },
            .cColorBits = 32,
            .cAlphaBits = 8,
            .cDepthBits = 24,
            .iLayerType = win32.PFD_MAIN_PLANE,
            // Clear the rest to zero.
            .cRedBits = 0,
            .cRedShift = 0,
            .cGreenBits = 0,
            .cGreenShift = 0,
            .cBlueBits = 0,
            .cBlueShift = 0,
            .cAlphaShift = 0,
            .cAccumBits = 0,
            .cAccumRedBits = 0,
            .cAccumGreenBits = 0,
            .cAccumBlueBits = 0,
            .cAccumAlphaBits = 0,
            .cStencilBits = 0,
            .cAuxBuffers = 0,
            .bReserved = 0,
            .dwLayerMask = 0,
            .dwVisibleMask = 0,
            .dwDamageMask = 0,
        };

        suggested_pixel_format_index = win32.ChoosePixelFormat(window_dc, &desired_pixel_format);
        if (suggested_pixel_format_index == 0) {
            outputLastError("ChoosePixelFormat failed");
        }
    }

    var suggested_pixel_format: win32.PIXELFORMATDESCRIPTOR = undefined;
    const describe_result = DescribePixelFormat(
        window_dc,
        suggested_pixel_format_index,
        @sizeOf(win32.PIXELFORMATDESCRIPTOR),
        &suggested_pixel_format,
    );
    if (describe_result == 0) {
        outputLastError("DescribePixelFormat failed");
    }

    if (win32.SetPixelFormat(window_dc, suggested_pixel_format_index, &suggested_pixel_format) == 0) {
        outputLastError("SetPixelFormat failed");
    }
}

fn loadWglExtensions(open_gl: *OpenGL) void {
    const window_class: win32.WNDCLASSW = .{
        .style = .{ .HREDRAW = 1, .VREDRAW = 1 },
        .lpfnWndProc = win32.DefWindowProcW,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = win32.GetModuleHandleW(null),
        .hIcon = null,
        .hbrBackground = win32.GetStockObject(win32.BLACK_BRUSH),
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeZigWglLoaderWindowClass"),
    };

    if (win32.RegisterClassW(&window_class) != 0) {
        const opt_window = win32.CreateWindowExW(
            .{},
            window_class.lpszClassName,
            win32.L("Handmade Zig WglLoader"),
            win32.WINDOW_STYLE{},
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            window_class.hInstance,
            null,
        );

        if (opt_window) |dummy_window| {
            if (win32.GetDC(dummy_window)) |dummy_window_dc| {
                setPixelFormat(open_gl, dummy_window_dc);

                const opengl_rc = win32.wglCreateContext(dummy_window_dc);
                if (win32.wglMakeCurrent(dummy_window_dc, opengl_rc) != 0) {
                    optWglCreateContextAttribsARB = @ptrCast(win32.wglGetProcAddress("wglCreateContextAttribsARB"));
                    optWglChoosePixelFormatARB = @ptrCast(win32.wglGetProcAddress("wglChoosePixelFormatARB"));
                    optWglGetExtensionsStringEXT = @ptrCast(win32.wglGetProcAddress("wglGetExtensionsStringEXT"));

                    if (optWglGetExtensionsStringEXT) |wglGetExtensionsStringEXT| {
                        const extensions = wglGetExtensionsStringEXT(dummy_window_dc);

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

                            if (shared.stringsWithOneLengthAreEqual(at, count, "WGL_EXT_framebuffer_sRGB") or
                                shared.stringsWithOneLengthAreEqual(at, count, "WGL_ARB_framebuffer_sRGB"))
                            {
                                open_gl.supports_srgb_frame_buffer = true;
                            }

                            at = end;
                        }
                    }

                    _ = win32.wglMakeCurrent(null, null);
                }

                _ = win32.wglDeleteContext(opengl_rc);
                _ = win32.ReleaseDC(dummy_window, dummy_window_dc);
            }

            _ = win32.DestroyWindow(dummy_window);
        }
    }
}

pub fn initOpenGL(
    window_dc: ?win32.HDC,
    limits: *renderer.PlatformRendererLimits,
) *OpenGL {
    const open_gl: *OpenGL = @ptrCast(@alignCast(rendererAllocate(@sizeOf(OpenGL))));

    renderer.initTextureQueue(
        &open_gl.header.texture_queue,
        limits.texture_transfer_buffer_size,
        rendererAllocate(limits.texture_transfer_buffer_size).?,
    );

    loadWglExtensions(open_gl);
    setPixelFormat(open_gl, window_dc);

    const max_vertex_count: u32 = limits.max_quad_count_per_frame * 4;
    const max_index_count: u32 = limits.max_quad_count_per_frame * 6;
    open_gl.max_quad_texture_count = limits.max_quad_count_per_frame;
    open_gl.max_texture_count = limits.max_texture_count;
    open_gl.max_vertex_count = max_vertex_count;
    open_gl.max_index_count = max_index_count;
    open_gl.max_special_texture_count = limits.max_special_texture_count;

    open_gl.vertex_array = @ptrCast(@alignCast(rendererAllocate(max_vertex_count * @sizeOf(TexturedVertex))));
    open_gl.index_array = @ptrCast(@alignCast(rendererAllocate(max_index_count * @sizeOf(u16))));
    open_gl.bitmap_array = @ptrCast(@alignCast(rendererAllocate(open_gl.max_quad_texture_count * @sizeOf(RendererTexture))));
    if (limits.max_special_texture_count > 0) {
        open_gl.special_texture_handles = @ptrCast(@alignCast(rendererAllocate(limits.max_special_texture_count * @sizeOf(u32))));
    }

    var opengl_rc: ?win32.HGLRC = null;
    var is_modern_context: bool = true;

    if (optWglCreateContextAttribsARB) |wglCreateContextAttribsARB| {
        opengl_rc = wglCreateContextAttribsARB(window_dc, null, &opengl_attribs);

        if (opengl_rc == null) {
            outputLastGLError("Failed to create modern context");
        }
    }

    if (opengl_rc == null) {
        is_modern_context = false;
        opengl_rc = win32.wglCreateContext(window_dc);
    }

    if (win32.wglMakeCurrent(window_dc, opengl_rc) != 0) {
        open_gl.optGLGetStringi = @ptrCast(win32.wglGetProcAddress("glGetStringi"));
        std.debug.assert(open_gl.optGLGetStringi != null);

        const info = opengl.Info.get(open_gl, is_modern_context);

        if (info.gl_arb_framebuffer_object) {
            open_gl.optGLBindFramebufferEXT = @ptrCast(win32.wglGetProcAddress("glBindFramebufferEXT"));
            open_gl.optGLGenFramebuffersEXT = @ptrCast(win32.wglGetProcAddress("glGenFramebuffersEXT"));
            open_gl.optGLDeleteFramebuffersEXT = @ptrCast(win32.wglGetProcAddress("glDeleteFramebuffersEXT"));
            open_gl.optGLFrameBufferTexture2DEXT = @ptrCast(win32.wglGetProcAddress("glFramebufferTexture2D"));
            open_gl.optGLCheckFramebufferStatusEXT = @ptrCast(win32.wglGetProcAddress("glCheckFramebufferStatusEXT"));

            std.debug.assert(open_gl.optGLBindFramebufferEXT != null);
            std.debug.assert(open_gl.optGLGenFramebuffersEXT != null);
            std.debug.assert(open_gl.optGLDeleteFramebuffersEXT != null);
            std.debug.assert(open_gl.optGLFrameBufferTexture2DEXT != null);
            std.debug.assert(open_gl.optGLCheckFramebufferStatusEXT != null);
        }

        open_gl.optGLTexImage2DMultiSample = @ptrCast(win32.wglGetProcAddress("glTexImage2DMultisample"));
        open_gl.optGLBlitFrameBuffer = @ptrCast(win32.wglGetProcAddress("glBlitFramebuffer"));
        open_gl.optGLCreateShader = @ptrCast(win32.wglGetProcAddress("glCreateShader"));
        open_gl.optGLDeleteShader = @ptrCast(win32.wglGetProcAddress("glDeleteShader"));
        open_gl.optGLShaderSource = @ptrCast(win32.wglGetProcAddress("glShaderSource"));
        open_gl.optGLCompileShader = @ptrCast(win32.wglGetProcAddress("glCompileShader"));
        open_gl.optGLCreateProgram = @ptrCast(win32.wglGetProcAddress("glCreateProgram"));
        open_gl.optGLDeleteProgram = @ptrCast(win32.wglGetProcAddress("glDeleteProgram"));
        open_gl.optGLLinkProgram = @ptrCast(win32.wglGetProcAddress("glLinkProgram"));
        open_gl.optGLAttachShader = @ptrCast(win32.wglGetProcAddress("glAttachShader"));
        open_gl.optGLValidateProgram = @ptrCast(win32.wglGetProcAddress("glValidateProgram"));
        open_gl.optGLGetProgramiv = @ptrCast(win32.wglGetProcAddress("glGetProgramiv"));
        open_gl.optGLGetShaderInfoLog = @ptrCast(win32.wglGetProcAddress("glGetShaderInfoLog"));
        open_gl.optGLGetProgramInfoLog = @ptrCast(win32.wglGetProcAddress("glGetProgramInfoLog"));
        open_gl.optGLUseProgram = @ptrCast(win32.wglGetProcAddress("glUseProgram"));
        open_gl.optGLUniformMatrix4fv = @ptrCast(win32.wglGetProcAddress("glUniformMatrix4fv"));
        open_gl.optGLUniform1f = @ptrCast(win32.wglGetProcAddress("glUniform1f"));
        open_gl.optGLUniform2fv = @ptrCast(win32.wglGetProcAddress("glUniform2fv"));
        open_gl.optGLUniform3fv = @ptrCast(win32.wglGetProcAddress("glUniform3fv"));
        open_gl.optGLUniform4fv = @ptrCast(win32.wglGetProcAddress("glUniform4fv"));
        open_gl.optGLUniform1i = @ptrCast(win32.wglGetProcAddress("glUniform1i"));
        open_gl.optGLGetUniformLocation = @ptrCast(win32.wglGetProcAddress("glGetUniformLocation"));
        open_gl.optGLGetAttribLocation = @ptrCast(win32.wglGetProcAddress("glGetAttribLocation"));
        open_gl.optGLEnableVertexAttribArray = @ptrCast(win32.wglGetProcAddress("glEnableVertexAttribArray"));
        open_gl.optGLDisableVertexAttribArray = @ptrCast(win32.wglGetProcAddress("glDisableVertexAttribArray"));
        open_gl.optGLVertexAttribPointer = @ptrCast(win32.wglGetProcAddress("glVertexAttribPointer"));
        open_gl.optGLVertexAttribIPointer = @ptrCast(win32.wglGetProcAddress("glVertexAttribIPointer"));
        open_gl.optGLGenVertexArrays = @ptrCast(win32.wglGetProcAddress("glGenVertexArrays"));
        open_gl.optGLBindVertexArray = @ptrCast(win32.wglGetProcAddress("glBindVertexArray"));
        open_gl.optGLDrawArrays = @ptrCast(win32.wglGetProcAddress("glDrawArrays"));
        open_gl.optGLDrawElements = @ptrCast(win32.wglGetProcAddress("glDrawElements"));
        open_gl.optGLDrawElementsBaseVertex = @ptrCast(win32.wglGetProcAddress("glDrawElementsBaseVertex"));
        open_gl.optGLDebugMessageCallbackARB = @ptrCast(win32.wglGetProcAddress("glDebugMessageCallbackARB"));
        open_gl.optGLDebugMessageControlARB = @ptrCast(win32.wglGetProcAddress("glDebugMessageControlARB"));
        open_gl.optGLGenBuffers = @ptrCast(win32.wglGetProcAddress("glGenBuffers"));
        open_gl.optGLBindBuffer = @ptrCast(win32.wglGetProcAddress("glBindBuffer"));
        open_gl.optGLBufferData = @ptrCast(win32.wglGetProcAddress("glBufferData"));
        open_gl.optGLActiveTexture = @ptrCast(win32.wglGetProcAddress("glActiveTexture"));
        open_gl.optGLDrawBuffers = @ptrCast(win32.wglGetProcAddress("glDrawBuffers"));
        open_gl.optGLBindFragDataLocation = @ptrCast(win32.wglGetProcAddress("glBindFragDataLocation"));
        open_gl.optGLTexImage3D = @ptrCast(win32.wglGetProcAddress("glTexImage3D"));
        open_gl.optGLTexSubImage3D = @ptrCast(win32.wglGetProcAddress("glTexSubImage3D"));

        if (open_gl.optGLDrawArrays == null) {
            const opengl32 = win32.LoadLibraryA("opengl32.dll");
            open_gl.optGLDrawArrays = @ptrCast(win32.GetProcAddress(opengl32, "glDrawArrays"));
        }

        std.debug.assert(open_gl.optGLTexImage2DMultiSample != null);
        std.debug.assert(open_gl.optGLBlitFrameBuffer != null);
        std.debug.assert(open_gl.optGLCreateShader != null);
        std.debug.assert(open_gl.optGLDeleteShader != null);
        std.debug.assert(open_gl.optGLShaderSource != null);
        std.debug.assert(open_gl.optGLCompileShader != null);
        std.debug.assert(open_gl.optGLCreateProgram != null);
        std.debug.assert(open_gl.optGLDeleteProgram != null);
        std.debug.assert(open_gl.optGLLinkProgram != null);
        std.debug.assert(open_gl.optGLAttachShader != null);
        std.debug.assert(open_gl.optGLValidateProgram != null);
        std.debug.assert(open_gl.optGLGetProgramiv != null);
        std.debug.assert(open_gl.optGLGetShaderInfoLog != null);
        std.debug.assert(open_gl.optGLGetProgramInfoLog != null);
        std.debug.assert(open_gl.optGLUseProgram != null);
        std.debug.assert(open_gl.optGLUniformMatrix4fv != null);
        std.debug.assert(open_gl.optGLUniform1f != null);
        std.debug.assert(open_gl.optGLUniform2fv != null);
        std.debug.assert(open_gl.optGLUniform3fv != null);
        std.debug.assert(open_gl.optGLUniform4fv != null);
        std.debug.assert(open_gl.optGLUniform1i != null);
        std.debug.assert(open_gl.optGLGetUniformLocation != null);
        std.debug.assert(open_gl.optGLGetAttribLocation != null);
        std.debug.assert(open_gl.optGLEnableVertexAttribArray != null);
        std.debug.assert(open_gl.optGLDisableVertexAttribArray != null);
        std.debug.assert(open_gl.optGLVertexAttribPointer != null);
        std.debug.assert(open_gl.optGLVertexAttribIPointer != null);
        std.debug.assert(open_gl.optGLGenVertexArrays != null);
        std.debug.assert(open_gl.optGLBindVertexArray != null);
        std.debug.assert(open_gl.optGLDrawArrays != null);
        std.debug.assert(open_gl.optGLDrawElements != null);
        std.debug.assert(open_gl.optGLDrawElementsBaseVertex != null);
        std.debug.assert(open_gl.optGLDebugMessageCallbackARB != null);
        std.debug.assert(open_gl.optGLDebugMessageControlARB != null);
        std.debug.assert(open_gl.optGLGenBuffers != null);
        std.debug.assert(open_gl.optGLBindBuffer != null);
        std.debug.assert(open_gl.optGLBufferData != null);
        std.debug.assert(open_gl.optGLActiveTexture != null);
        std.debug.assert(open_gl.optGLDrawBuffers != null);
        std.debug.assert(open_gl.optGLBindFragDataLocation != null);
        std.debug.assert(open_gl.optGLTexImage3D != null);
        std.debug.assert(open_gl.optGLTexSubImage3D != null);

        win32_opengl.setVSync(open_gl, true);
        opengl.init(open_gl, info, open_gl.supports_srgb_frame_buffer);
    } else {
        outputLastGLError("Failed to make modern context current");
    }

    return open_gl;
}

pub export fn win32LoadRenderer(
    opt_window_dc: ?win32.HDC,
    limits: *renderer.PlatformRendererLimits,
) callconv(.c) ?*PlatformRenderer {
    const result: ?*PlatformRenderer = @ptrCast(initOpenGL(opt_window_dc, limits));
    return result;
}

fn processTextureQueue(platform_renderer: *PlatformRenderer, texture_queue: *TextureQueue) callconv(.c) void {
    opengl.manageTextures(@ptrCast(@alignCast(platform_renderer)), texture_queue);
}

pub export fn win32BeginFrame(
    platform_renderer: *PlatformRenderer,
    window_dim: Vector2u,
    render_dim: Vector2u,
    draw_region: Rectangle2i,
) callconv(.c) ?*RenderCommands {
    const result: ?*RenderCommands = opengl.beginFrame(
        @ptrCast(@alignCast(platform_renderer)),
        window_dim,
        render_dim,
        draw_region,
    );
    return result;
}

pub export fn win32EndFrame(platform_renderer: *PlatformRenderer, frame: *RenderCommands) callconv(.c) void {
    const open_gl: *OpenGL = @ptrCast(@alignCast(platform_renderer));
    opengl.endFrame(open_gl, frame);
    _ = win32.SwapBuffers(win32.wglGetCurrentDC());
}

pub fn setVSync(open_gl: *OpenGL, enabled: bool) void {
    _ = open_gl;

    if (optWglSwapIntervalEXT == null) {
        optWglSwapIntervalEXT = @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT"));
    }

    if (optWglSwapIntervalEXT) |wglSwapIntervalEXT| {
        _ = wglSwapIntervalEXT(if (enabled) 1 else 0);
    }
}

pub fn outputLastGLError(title: []const u8) void {
    const last_error = win32.glGetError();

    if (INTERNAL) {
        std.debug.print("{s}: {d}\n", .{ title, last_error });
    } else {
        var buffer: [128]u8 = undefined;
        const length = shared.formatString(buffer.len, &buffer, "{s}: {d}\n", .{ title, last_error });
        win32.OutputDebugStringA(@ptrCast(buffer[0..length]));
    }
}

fn outputLastError(title: []const u8) void {
    const last_error = win32.GetLastError();

    if (INTERNAL) {
        std.debug.print("{s}: {d}\n", .{ title, @backingInt(last_error) });
    } else {
        var buffer: [128]u8 = undefined;
        const length = shared.formatString(buffer.len, &buffer, "%s: %d\n", .{
            title,
            @backingInt(last_error),
        });
        win32.OutputDebugStringA(@ptrCast(buffer[0..length]));
    }
}

fn rendererAllocate(size: usize) ?*anyopaque {
    const result = win32.VirtualAlloc(
        null,
        size,
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    );

    return result;
}

// fn displayBufferInWindow(
//     render_queue: *shared.PlatformWorkQueue,
//     commands: *RenderCommands,
//     device_context: ?win32.HDC,
//     draw_region: Rectangle2i,
//     temp_arena: *MemoryArena,
//     window_width: i32,
//     window_height: i32,
// ) void {
//     var temporary_memory: memory.TemporaryMemory = undefined;
//     if (DEBUG) {
//         // TODO: Unclear why this has to be avoided in release mode.
//         temporary_memory = temp_arena.beginTemporaryMemory();
//     }
//
//     // TODO: Do we want to check for resources like before?
//     // if (render_group.allResourcesPresent()) {
//     //     render_group.renderToOutput(transient_state.high_priority_queue, draw_buffer, &transient_state.arena);
//     // }
//
//     if (software_rendering) {
//         var output_target: renderer_software.SoftwareTexture = .{
//             .memory = @ptrCast(back_buffer.memory.?),
//             .width = @intCast(back_buffer.width),
//             .height = @intCast(back_buffer.height),
//             .pitch = @intCast(back_buffer.pitch),
//         };
//         renderer_software.softwareRenderCommands(render_queue, commands, &output_target, temp_arena);
//
//         const clear_color: math.Color = .black();
//         opengl.displayBitmap(
//             back_buffer.width,
//             back_buffer.height,
//             draw_region,
//             output_target.pitch,
//             back_buffer.memory,
//             clear_color,
//             open_gl.reserved_blit_texture,
//         );
//     } else {
//         TimedBlock.beginBlock(@src(), .OpenGLRenderCommands);
//         opengl.renderCommands(commands, draw_region, window_width, window_height);
//         TimedBlock.endBlock(@src(), .OpenGLRenderCommands);
//     }
//
//     if (DEBUG) {
//         temp_arena.endTemporaryMemory(temporary_memory);
//     }
// }
