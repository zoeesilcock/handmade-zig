const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
};

pub const UNICODE = true;

fn Wndproc(
    window: win32.HWND,
    message: u32,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(.C) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_SIZE => {
            win32.OutputDebugStringA("WM_SIZE\n");
        },
        win32.WM_DESTROY => {
            win32.OutputDebugStringA("WM_DESTROY\n");
        },
        win32.WM_CLOSE => {
            win32.OutputDebugStringA("WM_CLOSE\n");
        },
        win32.WM_ACTIVATEAPP => {
            win32.OutputDebugStringA("WM_ACTIVATEAPP\n");
        },
        else => {
            result = win32.DefWindowProc(window, message, wParam, lParam);
        },
    }

    return result;
}

pub export fn wWinMain(
    instance: ?win32.HINSTANCE,
    prevInstance: ?win32.HINSTANCE,
    cmdLine: ?win32.PWSTR,
    cmdShow: c_int,
) c_int {
    _ = prevInstance;
    _ = cmdLine;
    _ = cmdShow;

    win32.OutputDebugStringA("wWinMain\n");

    const windowClass: win32.WNDCLASSW = .{
        .style = .{ .OWNDC = 1, .HREDRAW = 1, .VREDRAW = 1 },
        .lpfnWndProc = Wndproc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeZigWindowClass"),
    };

    if (win32.RegisterClassW(&windowClass) != 0) {
        const windowHandle: ?win32.HWND = win32.CreateWindowExW(
            .{},
            windowClass.lpszClassName,
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

        if (windowHandle != null) {
            while (true) {
                win32.OutputDebugStringA("Handle messges\n");
                var message: win32.MSG = undefined;
                const messageResult: win32.BOOL = win32.GetMessageW(&message, windowHandle, 0, 0);
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
