const win32 = @import("std").os.windows;

extern "user32" fn MessageBoxA(?win32.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(win32.WINAPI) i32;

pub export fn wWinMain(hInstance: ?win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE, lpCmdLine: ?win32.PWSTR, nCmdShow: c_int) c_int {
    _ = hInstance;
    _ = hPrevInstance;
    _ = lpCmdLine;
    _ = nCmdShow;

    _ = MessageBoxA(null, "This is handmade!", "Handmade Zig", 0);

    return 0;
}
