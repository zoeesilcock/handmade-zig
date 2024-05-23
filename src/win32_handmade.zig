const win32 = struct {
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
};

pub export fn wWinMain(hInstance: ?win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE, lpCmdLine: ?win32.PWSTR, nCmdShow: c_int) c_int {
    _ = hInstance;
    _ = hPrevInstance;
    _ = lpCmdLine;
    _ = nCmdShow;

    _ = win32.MessageBoxA(null, "This is handmade!", "Handmade Zig", win32.MB_ICONINFORMATION);

    return 0;
}
