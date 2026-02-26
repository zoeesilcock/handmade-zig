const std = @import("std");
const win32 = @import("win32").everything;
const math = @import("math.zig");
const types = @import("types.zig");
const renderer = @import("renderer.zig");
const opengl = @import("renderer_opengl.zig");
const wgl = @import("win32_opengl.zig");

// Build options.
pub const INTERNAL = @import("build_options").internal;

// Types.
const Rectangle2i = math.Rectangle2i;
const RenderCommands = renderer.RenderCommands;
const RenderGroup = renderer.RenderGroup;
const TexturedVertex = renderer.TexturedVertex;
const LoadedBitmap = renderer.LoadedBitmap;

// Globals.
var running: bool = false;
var open_gl = &opengl.open_gl;

fn windowProcedure(
    window: win32.HWND,
    message: u32,
    w_param: win32.WPARAM,
    l_param: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_QUIT, win32.WM_CLOSE, win32.WM_DESTROY => {
            running = false;
        },
        win32.WM_SIZE => {},
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const opt_device_context: ?win32.HDC = win32.BeginPaint(window, &paint);
            _ = opt_device_context;
            _ = win32.EndPaint(window, &paint);
        },
        else => {
            result = win32.DefWindowProcW(window, message, w_param, l_param);
        },
    }

    return result;
}

fn processPendingMessages() void {
    var message: win32.MSG = undefined;
    while (true) {
        const skip_messages = [_]u32{
            // win32.WM_PAINT,
            // Ignoring WM_MOUSEMOVE lead to performance issues.
            // win32.WM_MOUSEMOVE,
            // Guard against an unknown message which spammed the game on Casey's machine.
            0x738,
            0xffffffff,
        };

        var got_message: bool = false;
        var last_message: u32 = 0;
        for (skip_messages) |skip| {
            got_message = win32.PeekMessageW(
                &message,
                null,
                last_message,
                skip - 1,
                win32.PM_REMOVE,
            ) != 0;

            if (got_message) {
                break;
            }

            last_message = skip +% 1;
        }

        if (!got_message) {
            break;
        }

        switch (message.message) {
            win32.WM_QUIT => running = false,
            else => {
                _ = win32.TranslateMessage(&message);
                _ = win32.DispatchMessageW(&message);
            },
        }
    }
}

fn allocateMemory(size: usize) ?*anyopaque {
    const result = win32.VirtualAlloc(
        null,
        size,
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    );

    return result;
}

/// This is needed for it to work when lib_c is linked.
pub export fn wWinMain(
    instance: win32.HINSTANCE,
    prev_instance: ?win32.HINSTANCE,
    cmd_line: ?win32.PWSTR,
    cmd_show: c_int,
) callconv(.winapi) c_int {
    return WinMain(instance, prev_instance, cmd_line, cmd_show);
}

pub export fn WinMain(
    instance: ?win32.HINSTANCE,
    prev_instance: ?win32.HINSTANCE,
    cmd_line: ?win32.PWSTR,
    cmd_show: c_int,
) c_int {
    _ = prev_instance;
    _ = cmd_line;
    _ = cmd_show;

    var perf_count_frequency: i64 = 0;
    var performance_frequency: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&performance_frequency);
    perf_count_frequency = performance_frequency.QuadPart;

    const window_class: win32.WNDCLASSW = .{
        .style = .{ .HREDRAW = 1, .VREDRAW = 1, .OWNDC = 1 },
        .lpfnWndProc = windowProcedure,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .hbrBackground = win32.GetStockObject(win32.BLACK_BRUSH),
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeZigRendererTestWindowClass"),
    };

    var last_counter: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceCounter(&last_counter);

    if (win32.RegisterClassW(&window_class) != 0) {
        const opt_window_handle: ?win32.HWND = win32.CreateWindowExW(
            .{},
            window_class.lpszClassName,
            win32.L("Handmade Zig Renderer Test"),
            win32.WINDOW_STYLE{
                .VISIBLE = 1,
                .TABSTOP = 1,
                .GROUP = 1,
                .THICKFRAME = 1,
                .SYSMENU = 1,
                .DLGFRAME = 1,
                .BORDER = 1,
            },
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        );

        if (opt_window_handle) |window_handle| {
            const window_dc = win32.GetDC(window_handle);
            _ = wgl.initOpenGL(window_dc);
            running = true;

            const push_buffer_size: u32 = types.megabytes(64);
            const push_buffer: [*]u8 = @ptrCast(allocateMemory(push_buffer_size));

            const max_vertex_count: u32 = 65536;
            const vertex_array: [*]TexturedVertex =
                @ptrCast(@alignCast(allocateMemory(max_vertex_count * @sizeOf(TexturedVertex))));
            const bitmap_array: [*]?*LoadedBitmap =
                @ptrCast(@alignCast(allocateMemory(max_vertex_count * @sizeOf(LoadedBitmap))));

            while (running) {
                processPendingMessages();

                var client_rect: win32.RECT = undefined;
                _ = win32.GetClientRect(window_handle, &client_rect);
                const window_width: i32 = client_rect.right - client_rect.left;
                const window_height: i32 = client_rect.bottom - client_rect.top;

                const draw_region: Rectangle2i =
                    math.aspectRatioFit(16, 9, @intCast(window_width), @intCast(window_height));

                var render_commands: RenderCommands = RenderCommands.default(
                    push_buffer_size,
                    push_buffer,
                    @intCast(draw_region.getWidth()),
                    @intCast(draw_region.getHeight()),
                    max_vertex_count,
                    vertex_array,
                    bitmap_array,
                    &open_gl.white_bitmap,
                );

                var group: RenderGroup = .begin(
                    undefined,
                    &render_commands,
                    1,
                    draw_region.getWidth(),
                    draw_region.getHeight(),
                );
                defer group.end();

                opengl.renderCommands(&render_commands, draw_region, window_width, window_height);
                _ = win32.SwapBuffers(window_dc);

                var end_counter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&end_counter);
                const seconds_elapsed: f32 =
                    @as(f32, @floatFromInt(end_counter.QuadPart - last_counter.QuadPart)) /
                    @as(f32, @floatFromInt(perf_count_frequency));
                _ = seconds_elapsed;
                last_counter = end_counter;
            }
        }
    }

    win32.ExitProcess(0);

    return 0;
}
