const std = @import("std");
const win32 = @import("win32").everything;
const shared = @import("shared.zig");
const opengl = @import("renderer_opengl.zig");

const gl = @cImport({
    @cInclude("GL/glcorearb.h");
});

var open_gl = &opengl.open_gl;

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
    hdc: win32.HDC,
    share_context: ?win32.HGLRC,
    attrib_list: ?[*:0]const c_int,
) callconv(.winapi) ?win32.HGLRC;
var optWglCreateContextAttribsARB: ?*const WglCreateContextAttribsARB = null;

const WglChoosePixelFormatARB: type = fn (
    hdc: win32.HDC,
    piAttribIList: [*:0]const c_int,
    pfAttribFList: ?[*:0]const f32,
    nMaxFormats: c_uint,
    piFormats: *c_int,
    nNumFormats: *c_uint,
) callconv(.winapi) win32.BOOL;
var optWglChoosePixelFormatARB: ?*const WglChoosePixelFormatARB = null;

const WglGetExtensionsStringEXT: type = fn (hdc: win32.HDC) callconv(.winapi) ?*u8;
pub var optWglGetExtensionsStringEXT: ?*const WglGetExtensionsStringEXT = null;
const GLBindFramebufferEXT: type = fn (target: u32, framebuffer: u32) callconv(.winapi) void;
pub var optGLBindFramebufferEXT: ?*const GLBindFramebufferEXT = null;
const GLGenFramebuffersEXT: type = fn (n: u32, framebuffer: [*]u32) callconv(.winapi) void;
pub var optGLGenFramebuffersEXT: ?*const GLGenFramebuffersEXT = null;
const GLDeleteFramebuffersEXT: type = fn (n: u32, framebuffer: [*]u32) callconv(.winapi) void;
pub var optGLDeleteFramebuffersEXT: ?*const GLDeleteFramebuffersEXT = null;
const GLFrameBufferTexture2DEXT: type = fn (target: u32, attachment: u32, textarget: u32, texture: u32, level: i32) callconv(.winapi) void;
pub var optGLFrameBufferTexture2DEXT: ?*const GLFrameBufferTexture2DEXT = null;
const GLCheckFramebufferStatusEXT: type = fn (target: u32) callconv(.winapi) u32;
pub var optGLCheckFramebufferStatusEXT: ?*const GLCheckFramebufferStatusEXT = null;
const GLTexImage2DMultiSample: type = fn (target: u32, samples: i32, internal_format: i32, width: i32, height: i32, fixed_sample_locations: bool) callconv(.winapi) u32;
pub var optGLTexImage2DMultiSample: ?*const GLTexImage2DMultiSample = null;
const GLBlitFrameBuffer: type = fn (src_x0: i32, src_y0: i32, src_x1: i32, src_y1: i32, dst_x0: i32, dst_y0: i32, dst_x1: i32, dst_y1: i32, mask: u32, filter: u32) callconv(.winapi) void;
pub var optGLBlitFrameBuffer: ?*const GLBlitFrameBuffer = null;
const GLCreateShader: type = fn (shader_type: u32) callconv(.winapi) u32;
pub var optGLCreateShader: ?*const GLCreateShader = null;
const GLDeleteShader: type = fn (shader: u32) callconv(.winapi) void;
pub var optGLDeleteShader: ?*const GLDeleteShader = null;
const GLShaderSource: type = fn (shader: u32, count: i32, string: [*]const [*:0]const u8, length: ?*i32) callconv(.winapi) void;
pub var optGLShaderSource: ?*const GLShaderSource = null;
const GLCompileShader: type = fn (shader: u32) callconv(.winapi) void;
pub var optGLCompileShader: ?*const GLCompileShader = null;
const GLCreateProgram: type = fn () callconv(.winapi) u32;
pub var optGLCreateProgram: ?*const GLCreateProgram = null;
const GLDeleteProgram: type = fn (program: u32) callconv(.winapi) void;
pub var optGLDeleteProgram: ?*const GLDeleteProgram = null;
const GLLinkProgram: type = fn (shader: u32) callconv(.winapi) void;
pub var optGLLinkProgram: ?*const GLLinkProgram = null;
const GLAttachShader: type = fn (program: u32, shader: u32) callconv(.winapi) void;
pub var optGLAttachShader: ?*const GLAttachShader = null;
const GLValidateProgram: type = fn (program: u32) callconv(.winapi) void;
pub var optGLValidateProgram: ?*const GLValidateProgram = null;
const GLGetProgramiv: type = fn (program: u32, pname: u32, params: *i32) callconv(.winapi) void;
pub var optGLGetProgramiv: ?*const GLGetProgramiv = null;
const GLGetShaderInfoLog: type = fn (shader: u32, bufSize: i32, length: *i32, infoLog: [*]u8) callconv(.winapi) void;
pub var optGLGetShaderInfoLog: ?*const GLGetShaderInfoLog = null;
const GLGetProgramInfoLog: type = fn (program: u32, bufSize: i32, length: *i32, infoLog: [*]u8) callconv(.winapi) void;
pub var optGLGetProgramInfoLog: ?*const GLGetProgramInfoLog = null;
const GLUseProgram: type = fn (program: u32) callconv(.winapi) void;
pub var optGLUseProgram: ?*const GLUseProgram = null;
const GLUniformMatrix4fv: type = fn (location: i32, count: i32, transpose: bool, value: *const f32) callconv(.winapi) void;
pub var optGLUniformMatrix4fv: ?*const GLUniformMatrix4fv = null;
const GLUniform1f: type = fn (location: i32, value: f32) callconv(.winapi) void;
pub var optGLUniform1f: ?*const GLUniform1f = null;
const GLUniform2fv: type = fn (location: i32, count: i32, value: *const f32) callconv(.winapi) void;
pub var optGLUniform2fv: ?*const GLUniform2fv = null;
const GLUniform3fv: type = fn (location: i32, count: i32, value: *const f32) callconv(.winapi) void;
pub var optGLUniform3fv: ?*const GLUniform3fv = null;
const GLUniform4fv: type = fn (location: i32, count: i32, value: *const f32) callconv(.winapi) void;
pub var optGLUniform4fv: ?*const GLUniform4fv = null;
const GLUniform1i: type = fn (location: i32, value: i32) callconv(.winapi) void;
pub var optGLUniform1i: ?*const GLUniform1i = null;
const GLGetUniformLocation: type = fn (program: u32, [*]const u8) callconv(.winapi) i32;
pub var optGLGetUniformLocation: ?*const GLGetUniformLocation = null;
const GLGetAttribLocation: type = fn (program: u32, name: [*]const u8) callconv(.winapi) i32;
pub var optGLGetAttribLocation: ?*const GLGetAttribLocation = null;
const GLEnableVertexAttribArray: type = fn (index: u32) callconv(.winapi) void;
pub var optGLEnableVertexAttribArray: ?*const GLEnableVertexAttribArray = null;
const GLDisableVertexAttribArray: type = fn (index: u32) callconv(.winapi) void;
pub var optGLDisableVertexAttribArray: ?*const GLDisableVertexAttribArray = null;
const GLVertexAttribPointer: type = fn (index: u32, size: i32, data_type: u32, normalized: bool, stride: isize, pointer: ?*anyopaque) callconv(.winapi) void;
pub var optGLVertexAttribPointer: ?*const GLVertexAttribPointer = null;
const GLVertexAttribIPointer: type = fn (index: u32, size: i32, data_type: u32, stride: isize, pointer: ?*anyopaque) callconv(.winapi) void;
pub var optGLVertexAttribIPointer: ?*const GLVertexAttribIPointer = null;
const GLGenVertexArrays: type = fn (size: i32, arrays: ?*u32) callconv(.winapi) void;
pub var optGLGenVertexArrays: ?*const GLGenVertexArrays = null;
const GLBindVertexArray: type = fn (array: u32) callconv(.winapi) void;
pub var optGLBindVertexArray: ?*const GLBindVertexArray = null;
const GLDrawArrays: type = fn (mode: u32, first: i32, count: i32) callconv(.winapi) void;
pub var optGLDrawArrays: ?*const GLDrawArrays = null;
const GLDebugProcArb = ?*const fn (source: u32, message_type: u32, id: u32, severity: u32, length: i32, message: [*]const u8, user_param: ?*const anyopaque) callconv(.winapi) void;
const GLDebugMessageCallbackARB: type = fn (callback: GLDebugProcArb, user_param: ?*const anyopaque) callconv(.winapi) void;
pub var optGLDebugMessageCallbackARB: ?*const GLDebugMessageCallbackARB = null;
const GLDebugMessageControlARB: type = fn (source: u32, message_type: u32, severity: u32, count: i32, ids: [*]const i32, enabled: bool) callconv(.winapi) void;
pub var optGLDebugMessageControlARB: ?*const GLDebugMessageControlARB = null;
const GLGetStringi: type = fn (name: u32, index: u32) callconv(.winapi) ?*u8;
pub var optGLGetStringi: ?*const GLGetStringi = null;
const GLGenBuffers: type = fn (count: i32, buffers: *u32) callconv(.winapi) void;
pub var optGLGenBuffers: ?*const GLGenBuffers = null;
const GLBindBuffer: type = fn (target: u32, buffer: u32) callconv(.winapi) void;
pub var optGLBindBuffer: ?*const GLBindBuffer = null;
const GLBufferData: type = fn (target: u32, size: isize, data: *anyopaque, usage: u32) callconv(.winapi) void;
pub var optGLBufferData: ?*const GLBufferData = null;
const GLActiveTexture: type = fn (texture: u32) callconv(.winapi) void;
pub var optGLActiveTexture: ?*const GLActiveTexture = null;
const GLDrawBuffers: type = fn (n: u32, buffers: [*]const u32) callconv(.winapi) void;
pub var optGLDrawBuffers: ?*const GLDrawBuffers = null;
const GLBindFragDataLocation: type = fn (program: u32, color: u32, name: [*]const u8) callconv(.winapi) void;
pub var optGLBindFragDataLocation: ?*const GLBindFragDataLocation = null;
const GLTexImage3D: type = fn (target: u32, level: i32, internalformat: i32, width: isize, height: isize, depth: isize, border: i32, format: u32, type: u32, pixels: ?*const anyopaque) callconv(.winapi) void;
pub var optGLTexImage3D: ?*const GLTexImage3D = null;
const GLTexSubImage3D: type = fn (target: u32, level: i32, xoffset: i32, yoffset: i32, zoffset: i32, width: isize, height: isize, depth: isize, format: u32, type: u32, pixels: ?*const anyopaque) callconv(.winapi) void;
pub var optGLTexSubImage3D: ?*const GLTexSubImage3D = null;

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

fn setPixelFormat(window_dc: win32.HDC) void {
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

fn loadWglExtensions() void {
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
                setPixelFormat(dummy_window_dc);

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

pub fn initOpenGL(opt_window_dc: ?win32.HDC) ?win32.HGLRC {
    var opengl_rc: ?win32.HGLRC = null;

    loadWglExtensions();

    if (opt_window_dc) |window_dc| {
        setPixelFormat(window_dc);

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
            optGLGetStringi = @ptrCast(win32.wglGetProcAddress("glGetStringi"));
            std.debug.assert(optGLGetStringi != null);

            const info = opengl.Info.get(is_modern_context);

            if (info.gl_arb_framebuffer_object) {
                optGLBindFramebufferEXT = @ptrCast(win32.wglGetProcAddress("glBindFramebufferEXT"));
                optGLGenFramebuffersEXT = @ptrCast(win32.wglGetProcAddress("glGenFramebuffersEXT"));
                optGLDeleteFramebuffersEXT = @ptrCast(win32.wglGetProcAddress("glDeleteFramebuffersEXT"));
                optGLFrameBufferTexture2DEXT = @ptrCast(win32.wglGetProcAddress("glFramebufferTexture2D"));
                optGLCheckFramebufferStatusEXT = @ptrCast(win32.wglGetProcAddress("glCheckFramebufferStatusEXT"));

                std.debug.assert(optGLBindFramebufferEXT != null);
                std.debug.assert(optGLGenFramebuffersEXT != null);
                std.debug.assert(optGLDeleteFramebuffersEXT != null);
                std.debug.assert(optGLFrameBufferTexture2DEXT != null);
                std.debug.assert(optGLCheckFramebufferStatusEXT != null);
            }

            optGLTexImage2DMultiSample = @ptrCast(win32.wglGetProcAddress("glTexImage2DMultisample"));
            optGLBlitFrameBuffer = @ptrCast(win32.wglGetProcAddress("glBlitFramebuffer"));
            optGLCreateShader = @ptrCast(win32.wglGetProcAddress("glCreateShader"));
            optGLDeleteShader = @ptrCast(win32.wglGetProcAddress("glDeleteShader"));
            optGLShaderSource = @ptrCast(win32.wglGetProcAddress("glShaderSource"));
            optGLCompileShader = @ptrCast(win32.wglGetProcAddress("glCompileShader"));
            optGLCreateProgram = @ptrCast(win32.wglGetProcAddress("glCreateProgram"));
            optGLDeleteProgram = @ptrCast(win32.wglGetProcAddress("glDeleteProgram"));
            optGLLinkProgram = @ptrCast(win32.wglGetProcAddress("glLinkProgram"));
            optGLAttachShader = @ptrCast(win32.wglGetProcAddress("glAttachShader"));
            optGLValidateProgram = @ptrCast(win32.wglGetProcAddress("glValidateProgram"));
            optGLGetProgramiv = @ptrCast(win32.wglGetProcAddress("glGetProgramiv"));
            optGLGetShaderInfoLog = @ptrCast(win32.wglGetProcAddress("glGetShaderInfoLog"));
            optGLGetProgramInfoLog = @ptrCast(win32.wglGetProcAddress("glGetProgramInfoLog"));
            optGLUseProgram = @ptrCast(win32.wglGetProcAddress("glUseProgram"));
            optGLUniformMatrix4fv = @ptrCast(win32.wglGetProcAddress("glUniformMatrix4fv"));
            optGLUniform1f = @ptrCast(win32.wglGetProcAddress("glUniform1f"));
            optGLUniform2fv = @ptrCast(win32.wglGetProcAddress("glUniform2fv"));
            optGLUniform3fv = @ptrCast(win32.wglGetProcAddress("glUniform3fv"));
            optGLUniform4fv = @ptrCast(win32.wglGetProcAddress("glUniform4fv"));
            optGLUniform1i = @ptrCast(win32.wglGetProcAddress("glUniform1i"));
            optGLGetUniformLocation = @ptrCast(win32.wglGetProcAddress("glGetUniformLocation"));
            optGLGetAttribLocation = @ptrCast(win32.wglGetProcAddress("glGetAttribLocation"));
            optGLEnableVertexAttribArray = @ptrCast(win32.wglGetProcAddress("glEnableVertexAttribArray"));
            optGLDisableVertexAttribArray = @ptrCast(win32.wglGetProcAddress("glDisableVertexAttribArray"));
            optGLVertexAttribPointer = @ptrCast(win32.wglGetProcAddress("glVertexAttribPointer"));
            optGLVertexAttribIPointer = @ptrCast(win32.wglGetProcAddress("glVertexAttribIPointer"));
            optGLGenVertexArrays = @ptrCast(win32.wglGetProcAddress("glGenVertexArrays"));
            optGLBindVertexArray = @ptrCast(win32.wglGetProcAddress("glBindVertexArray"));
            optGLDrawArrays = @ptrCast(win32.wglGetProcAddress("glDrawArrays"));
            optGLDebugMessageCallbackARB = @ptrCast(win32.wglGetProcAddress("glDebugMessageCallbackARB"));
            optGLDebugMessageControlARB = @ptrCast(win32.wglGetProcAddress("glDebugMessageControlARB"));
            optGLGenBuffers = @ptrCast(win32.wglGetProcAddress("glGenBuffers"));
            optGLBindBuffer = @ptrCast(win32.wglGetProcAddress("glBindBuffer"));
            optGLBufferData = @ptrCast(win32.wglGetProcAddress("glBufferData"));
            optGLActiveTexture = @ptrCast(win32.wglGetProcAddress("glActiveTexture"));
            optGLDrawBuffers = @ptrCast(win32.wglGetProcAddress("glDrawBuffers"));
            optGLBindFragDataLocation = @ptrCast(win32.wglGetProcAddress("glBindFragDataLocation"));
            optGLTexImage3D = @ptrCast(win32.wglGetProcAddress("glTexImage3D"));
            optGLTexSubImage3D = @ptrCast(win32.wglGetProcAddress("glTexSubImage3D"));

            if (optGLDrawArrays == null) {
                const opengl32 = win32.LoadLibraryA("opengl32.dll");
                optGLDrawArrays = @ptrCast(win32.GetProcAddress(opengl32, "glDrawArrays"));
            }

            std.debug.assert(optGLTexImage2DMultiSample != null);
            std.debug.assert(optGLBlitFrameBuffer != null);
            std.debug.assert(optGLCreateShader != null);
            std.debug.assert(optGLDeleteShader != null);
            std.debug.assert(optGLShaderSource != null);
            std.debug.assert(optGLCompileShader != null);
            std.debug.assert(optGLCreateProgram != null);
            std.debug.assert(optGLDeleteProgram != null);
            std.debug.assert(optGLLinkProgram != null);
            std.debug.assert(optGLAttachShader != null);
            std.debug.assert(optGLValidateProgram != null);
            std.debug.assert(optGLGetProgramiv != null);
            std.debug.assert(optGLGetShaderInfoLog != null);
            std.debug.assert(optGLGetProgramInfoLog != null);
            std.debug.assert(optGLUseProgram != null);
            std.debug.assert(optGLUniformMatrix4fv != null);
            std.debug.assert(optGLUniform1f != null);
            std.debug.assert(optGLUniform2fv != null);
            std.debug.assert(optGLUniform3fv != null);
            std.debug.assert(optGLUniform4fv != null);
            std.debug.assert(optGLUniform1i != null);
            std.debug.assert(optGLGetUniformLocation != null);
            std.debug.assert(optGLGetAttribLocation != null);
            std.debug.assert(optGLEnableVertexAttribArray != null);
            std.debug.assert(optGLDisableVertexAttribArray != null);
            std.debug.assert(optGLVertexAttribPointer != null);
            std.debug.assert(optGLVertexAttribIPointer != null);
            std.debug.assert(optGLGenVertexArrays != null);
            std.debug.assert(optGLBindVertexArray != null);
            std.debug.assert(optGLDrawArrays != null);
            std.debug.assert(optGLDebugMessageCallbackARB != null);
            std.debug.assert(optGLDebugMessageControlARB != null);
            std.debug.assert(optGLGenBuffers != null);
            std.debug.assert(optGLBindBuffer != null);
            std.debug.assert(optGLBufferData != null);
            std.debug.assert(optGLActiveTexture != null);
            std.debug.assert(optGLDrawBuffers != null);
            std.debug.assert(optGLBindFragDataLocation != null);
            std.debug.assert(optGLTexImage3D != null);
            std.debug.assert(optGLTexSubImage3D != null);

            optWglSwapIntervalEXT = @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT"));
            if (optWglSwapIntervalEXT) |wglSwapIntervalEXT| {
                _ = wglSwapIntervalEXT(0);
            }

            opengl.init(info, open_gl.supports_srgb_frame_buffer);
        } else {
            outputLastGLError("Failed to make modern context current");
        }
    }

    return opengl_rc;
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
        std.debug.print("{s}: {d}\n", .{ title, @intFromEnum(last_error) });
    } else {
        var buffer: [128]u8 = undefined;
        const length = shared.formatString(buffer.len, &buffer, "%s: %d\n", .{
            title,
            @intFromEnum(last_error),
        });
        win32.OutputDebugStringA(@ptrCast(buffer[0..length]));
    }
}
