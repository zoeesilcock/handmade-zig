const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").graphics.gdi;
};

pub const UNICODE = true;
var running: bool = false;

var bitmap_infooo: win32.BITMAPINFO = undefined;
var bitmap_memory: ?*anyopaque = undefined;
var bitmap_handle: ?win32.HBITMAP = undefined;
var bitmap_device_context: win32.HDC = undefined;

fn resizeDBISection(width: i32, height: i32) void {
    if (bitmap_handle) |handle| {
        _ = win32.DeleteObject(handle);
    }

    if (bitmap_device_context == undefined) {
        bitmap_device_context = win32.CreateCompatibleDC(undefined);
    }

    bitmap_infooo = win32.BITMAPINFO{
        .bmiHeader = win32.BITMAPINFOHEADER{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = width,
            .biHeight = height,
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

    bitmap_handle = win32.CreateDIBSection(
        bitmap_device_context,
        &bitmap_infooo,
        win32.DIB_RGB_COLORS,
        &bitmap_memory,
        null,
        0,
    );
}

fn updateWindow(deviceContext: ?win32.HDC, x: i32, y: i32, width: i32, height: i32) void {
    _ = win32.StretchDIBits(
        deviceContext,
        x,
        y,
        width,
        height,
        x,
        y,
        width,
        height,
        bitmap_memory,
        &bitmap_infooo,
        win32.DIB_RGB_COLORS,
        win32.SRCCOPY,
    );
}

fn Wndproc(
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
                const x = paint.rcPaint.left;
                const y = paint.rcPaint.top;
                const width = paint.rcPaint.right - paint.rcPaint.left;
                const height = paint.rcPaint.bottom - paint.rcPaint.top;
                updateWindow(device_context, x, y, width, height);
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
        .lpfnWndProc = Wndproc,
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
            while (running) {
                var message: win32.MSG = undefined;
                const messageResult: win32.BOOL = win32.GetMessageW(&message, window_handle, 0, 0);
                if (messageResult > 0) {
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);
                } else {
                    break;
                }
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
