const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").graphics.gdi;
};

const OffscreenBuffer = struct {
    info: win32.BITMAPINFO = undefined,
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
    bytes_per_pixel: u8 = 4,
};

pub const UNICODE = true;
var running: bool = false;
var back_buffer: OffscreenBuffer = .{};

const WindowDimension = struct {
    width: i32,
    height: i32,
};

fn getWindowDimension(window: win32.HWND) WindowDimension {
    var client_rect: win32.RECT = undefined;
    _ = win32.GetClientRect(window, &client_rect);

    return WindowDimension{
        .width = client_rect.right - client_rect.left,
        .height = client_rect.bottom - client_rect.top,
    };
}

fn renderWeirdGradient(buffer: OffscreenBuffer, x_offset: u32, y_offset: u32) void {
    var row: [*]u8 = @ptrCast(buffer.memory);
    var y: u32 = 0;

    while (y < buffer.height) {
        var x: u32 = 0;
        var pixel: [*]align(4) u32 = @ptrCast(@alignCast(row));

        while (x < buffer.width) {
            const blue: u32 = @as(u8, @truncate(x + x_offset));
            const green: u32 = @as(u8, @truncate(y + y_offset));

            pixel[0] = (green << 8) | blue;

            pixel += 1;
            x += 1;
        }

        row += buffer.pitch;
        y += 1;
    }
}

fn resizeDBISection(buffer: *OffscreenBuffer, width: i32, height: i32) void {
    if (buffer.memory) |memory| {
        _ = win32.VirtualFree(memory, 0, win32.MEM_RELEASE);
    }

    buffer.width = width;
    buffer.height = height;
    buffer.bytes_per_pixel = 4;

    buffer.info = win32.BITMAPINFO{
        .bmiHeader = win32.BITMAPINFOHEADER{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = buffer.width,
            .biHeight = -buffer.height,
            .biPlanes = 1,
            .biBitCount = 32,
            .biCompression = win32.BI_RGB,
            .biSizeImage = 0,
            .biXPelsPerMeter = 0,
            .biYPelsPerMeter = 0,
            .biClrUsed = 0,
            .biClrImportant = 0,
        },
        .bmiColors = undefined,
    };

    const bitmap_memory_size: usize = @intCast((buffer.width * buffer.height) * buffer.bytes_per_pixel);
    buffer.memory = win32.VirtualAlloc(null, bitmap_memory_size, win32.MEM_COMMIT, win32.PAGE_READWRITE);
    buffer.pitch = @intCast(buffer.width * buffer.bytes_per_pixel);
}

fn displayBufferInWindow(deviceContext: ?win32.HDC, window_width: i32, window_height: i32, buffer: OffscreenBuffer) void {
    _ = win32.StretchDIBits(
        deviceContext,
        0,
        0,
        window_width,
        window_height,
        0,
        0,
        buffer.width,
        buffer.height,
        buffer.memory,
        &buffer.info,
        win32.DIB_RGB_COLORS,
        win32.SRCCOPY,
    );
}

fn windowProcedure(
    window: win32.HWND,
    message: u32,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(.C) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_SIZE => {},
        win32.WM_ACTIVATEAPP => {
            win32.OutputDebugStringA("WM_ACTIVATEAPP\n");
        },
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const opt_device_context: ?win32.HDC = win32.BeginPaint(window, &paint);
            if (opt_device_context) |device_context| {
                const window_dimension = getWindowDimension(window);
                displayBufferInWindow(device_context, window_dimension.width, window_dimension.height, back_buffer);
            }
            _ = win32.EndPaint(window, &paint);
        },
        win32.WM_CLOSE, win32.WM_DESTROY => {
            running = false;
        },
        else => {
            result = win32.DefWindowProc(window, message, wParam, lParam);
        },
    }

    return result;
}

pub export fn wWinMain(
    instance: ?win32.HINSTANCE,
    prev_instance: ?win32.HINSTANCE,
    cmd_line: ?win32.PWSTR,
    cmd_show: c_int,
) c_int {
    _ = prev_instance;
    _ = cmd_line;
    _ = cmd_show;

    resizeDBISection(&back_buffer, 1280, 720);

    const window_class: win32.WNDCLASSW = .{
        .style = .{ .HREDRAW = 1, .VREDRAW = 1 },
        .lpfnWndProc = windowProcedure,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeZigWindowClass"),
    };

    if (win32.RegisterClassW(&window_class) != 0) {
        const opt_window_handle: ?win32.HWND = win32.CreateWindowExW(
            .{},
            window_class.lpszClassName,
            win32.L("Handmade Zig"),
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
            running = true;
            var x_offset: u32 = 0;
            var y_offset: u32 = 0;

            while (running) {
                var message: win32.MSG = undefined;
                while (win32.PeekMessageW(&message, window_handle, 0, 0, win32.PM_REMOVE) != 0) {
                    if (message.message == win32.WM_QUIT) {
                        running = false;
                    }
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);
                }

                renderWeirdGradient(back_buffer, x_offset, y_offset);
                x_offset += 1;
                y_offset += 2;

                const device_context = win32.GetDC(window_handle);
                const window_dimension = getWindowDimension(window_handle);
                displayBufferInWindow(device_context, window_dimension.width, window_dimension.height, back_buffer);
                _ = win32.ReleaseDC(window_handle, device_context);
            }
        } else {
            win32.OutputDebugStringA("Window handle is null.\n");
        }
    } else {
        // const lastError = win32.GetLastError();
        // _ = lastError;
        win32.OutputDebugStringA("Register class failed.\n");
    }

    return 0;
}
