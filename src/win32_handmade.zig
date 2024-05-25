const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").graphics.gdi;
};

pub const UNICODE = true;
var running: bool = false;

const bytes_per_pixel: u8 = 4;
var bitmap_info: win32.BITMAPINFO = undefined;
var bitmap_memory: ?*anyopaque = undefined;
var bitmap_width: i32 = 0;
var bitmap_height: i32 = 0;

fn renderWeirdGradient(x_offset: u32, y_offset: u32) void {
    const pitch: usize = @intCast(bitmap_width * bytes_per_pixel);
    var row: [*]u8 = @ptrCast(bitmap_memory);
    var y: u32 = 0;

    while (y < bitmap_height) {
        var x: u32 = 0;
        var pixel: [*]align(4) u32 = @ptrCast(@alignCast(row));

        while (x < bitmap_width) {
            const blue: u32 = @as(u8, @truncate(x + x_offset));
            const green: u32 = @as(u8, @truncate(y + y_offset));

            pixel[0] = (green << 8) | blue;

            pixel += 1;
            x += 1;
        }

        row += pitch;
        y += 1;
    }
}

fn resizeDBISection(width: i32, height: i32) void {
    if (bitmap_memory) |memory| {
        _ = win32.VirtualFree(memory, 0, win32.MEM_RELEASE);
    }

    bitmap_width = width;
    bitmap_height = height;

    bitmap_info = win32.BITMAPINFO{
        .bmiHeader = win32.BITMAPINFOHEADER{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = bitmap_width,
            .biHeight = -bitmap_height,
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

    const bitmap_memory_size: usize = @intCast((bitmap_width * bitmap_height) * bytes_per_pixel);
    bitmap_memory = win32.VirtualAlloc(null, bitmap_memory_size, win32.MEM_COMMIT, win32.PAGE_READWRITE);
}

fn updateWindow(deviceContext: ?win32.HDC, client_rect: win32.RECT) void {
    const window_width = client_rect.right - client_rect.left;
    const window_height = client_rect.bottom - client_rect.top;

    _ = win32.StretchDIBits(
        deviceContext,
        0,
        0,
        bitmap_width,
        bitmap_height,
        0,
        0,
        window_width,
        window_height,
        bitmap_memory,
        &bitmap_info,
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
        win32.WM_SIZE => {
            var client_rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window, &client_rect);
            const width = client_rect.right - client_rect.left;
            const height = client_rect.bottom - client_rect.top;
            resizeDBISection(width, height);
        },
        win32.WM_ACTIVATEAPP => {
            win32.OutputDebugStringA("WM_ACTIVATEAPP\n");
        },
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const opt_device_context: ?win32.HDC = win32.BeginPaint(window, &paint);
            if (opt_device_context) |device_context| {
                var client_rect: win32.RECT = undefined;
                _ = win32.GetClientRect(window, &client_rect);
                updateWindow(device_context, client_rect);
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

    const window_class: win32.WNDCLASSW = .{
        .style = .{},
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
            const y_offset: u32 = 0;

            while (running) {
                var message: win32.MSG = undefined;
                while (win32.PeekMessageW(&message, window_handle, 0, 0, win32.PM_REMOVE) != 0) {
                    if (message.message == win32.WM_QUIT) {
                        running = false;
                    }
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);
                }

                renderWeirdGradient(x_offset, y_offset);
                x_offset += 1;

                const device_context = win32.GetDC(window_handle);
                var client_rect: win32.RECT = undefined;
                _ = win32.GetClientRect(window_handle, &client_rect);
                updateWindow(device_context, client_rect);
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
