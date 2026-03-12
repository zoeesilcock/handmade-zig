const win32 = @import("win32").everything;
const renderer = @import("renderer.zig");

pub const LOAD_RENDERER_ENTRY = "win32LoadRenderer";

pub const win32LoadRendererType = ?*const fn (
    opt_window_dc: ?win32.HDC,
    max_quad_count_per_frame: u32,
    max_texture_count: u32,
) callconv(.c) ?*renderer.PlatformRenderer;

pub fn loadRendererDLL(file_name: [*:0]const u8) win32LoadRendererType {
    var win32LoadRenderer: win32LoadRendererType = null;
    if (win32.LoadLibraryA(file_name)) |renderer_dll| {
        if (win32.GetProcAddress(renderer_dll, LOAD_RENDERER_ENTRY)) |procedure| {
            win32LoadRenderer = @as(@TypeOf(win32LoadRenderer), @ptrCast(procedure));
        }
    }
    return win32LoadRenderer;
}

pub fn initDefaultRenderer(
    window: win32.HWND,
    max_quad_count_per_frame: u32,
    max_texture_count: u32,
) *renderer.PlatformRenderer {
    // Load the renderer DLL and get the address of the init function.
    const win32LoadRenderer: win32LoadRendererType = loadRendererDLL("win32-handmade-opengl.dll");

    if (win32LoadRenderer == null) {
        _ = win32.MessageBoxA(
            window,
            "Please make sure win32_handmade_opengl.dll is present in the same directory as the exe.",
            "Unable to load win32_handmade_opengl.dll",
            win32.MB_ICONERROR,
        );
        win32.ExitProcess(0);
    }

    // Initialize OpenGL so that we can render to our window. The win32 OpenGL startup code is contained within
    // `win32_handmade_opengl.dll`, so we get the DC for our window and pass that to its `win32LoadRenderer`
    // function so it can do all the startup for us.
    const platform_renderer: *renderer.PlatformRenderer = win32LoadRenderer.?(
        win32.GetDC(window),
        max_quad_count_per_frame,
        max_texture_count,
    ).?;

    return platform_renderer;
}
