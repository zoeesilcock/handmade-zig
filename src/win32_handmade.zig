const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.input;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").graphics.gdi;
};

pub const UNICODE = true;

const WIDTH = 1280;
const HEIGHT = 720;
const WINDOW_DECORATION_WIDTH = 16;
const WINDOW_DECORATION_HEIGHT = 39;
const BYTES_PER_PIXEL = 4;
const STICK_DOWN_SHIFT = 12;
const STICK_DEAD_ZONE = 1;

var running: bool = false;
var back_buffer: OffscreenBuffer = .{};

const OffscreenBuffer = struct {
    info: win32.BITMAPINFO = undefined,
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
};

const WindowDimension = struct {
    width: i32,
    height: i32,
};

fn XInputGetStateStub(_: u32, _: ?*win32.XINPUT_STATE) callconv(@import("std").os.windows.WINAPI) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
fn XInputSetStateStub(_: u32, _: ?*win32.XINPUT_VIBRATION) callconv(@import("std").os.windows.WINAPI) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
var XInputGetState: *const fn (u32, ?*win32.XINPUT_STATE) callconv(@import("std").os.windows.WINAPI) isize = XInputGetStateStub;
var XInputSetState: *const fn (u32, ?*win32.XINPUT_VIBRATION) callconv(@import("std").os.windows.WINAPI) isize = XInputSetStateStub;

fn loadXInput() void {
    if (win32.LoadLibraryA("xinput1_4.dll")) |library| {
        if (win32.GetProcAddress(library, "XInputGetState")) |procedure| {
            XInputGetState = @as(@TypeOf(XInputGetState), @ptrCast(procedure));
        }
        if (win32.GetProcAddress(library, "XInputSetState")) |procedure| {
            XInputSetState = @as(@TypeOf(XInputSetState), @ptrCast(procedure));
        }
    }
}

fn getWindowDimension(window: win32.HWND) WindowDimension {
    var client_rect: win32.RECT = undefined;
    _ = win32.GetClientRect(window, &client_rect);

    return WindowDimension{
        .width = client_rect.right - client_rect.left,
        .height = client_rect.bottom - client_rect.top,
    };
}

fn renderWeirdGradient(buffer: *OffscreenBuffer, x_offset: u32, y_offset: u32) void {
    var row: [*]u8 = @ptrCast(buffer.memory);
    var y: u32 = 0;

    while (y < buffer.height) {
        var x: u32 = 0;
        var pixel: [*]align(4) u32 = @ptrCast(@alignCast(row));

        while (x < buffer.width) {
            const blue: u32 = @as(u8, @truncate(x +% x_offset));
            const green: u32 = @as(u8, @truncate(y +% y_offset));

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

    const bitmap_memory_size: usize = @intCast((buffer.width * buffer.height) * BYTES_PER_PIXEL);
    buffer.memory = win32.VirtualAlloc(null, bitmap_memory_size, win32.MEM_COMMIT, win32.PAGE_READWRITE);
    buffer.pitch = @intCast(buffer.width * BYTES_PER_PIXEL);
}

fn displayBufferInWindow(buffer: *OffscreenBuffer, device_context: ?win32.HDC, window_width: i32, window_height: i32) void {
    _ = win32.StretchDIBits(
        device_context,
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
    w_param: win32.WPARAM,
    l_param: win32.LPARAM,
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
                displayBufferInWindow(&back_buffer, device_context, window_dimension.width, window_dimension.height);
            }
            _ = win32.EndPaint(window, &paint);
        },
        win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYDOWN, win32.WM_KEYUP => {
            const vk_code = w_param;
            const was_down: bool = if ((l_param & (1 << 30) != 0)) true else false;
            const is_down: bool = if ((l_param & (1 << 31) == 0)) true else false;

            if (is_down != was_down) {
                switch (vk_code) {
                    'W' => {},
                    'A' => {},
                    'S' => {},
                    'D' => {},
                    'Q' => {},
                    'E' => {},
                    @intFromEnum(win32.VK_UP) => {},
                    @intFromEnum(win32.VK_DOWN) => {},
                    @intFromEnum(win32.VK_LEFT) => {},
                    @intFromEnum(win32.VK_RIGHT) => {},
                    @intFromEnum(win32.VK_ESCAPE) => {
                        if (is_down) {
                            win32.OutputDebugStringA("ESC is_down\n");
                        }
                        if (was_down) {
                            win32.OutputDebugStringA("ESC was_down\n");
                        }
                    },
                    @intFromEnum(win32.VK_SPACE) => {},
                    else => {},
                }
            }
        },
        win32.WM_CLOSE, win32.WM_DESTROY => {
            running = false;
        },
        else => {
            result = win32.DefWindowProc(window, message, w_param, l_param);
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

    loadXInput();
    resizeDBISection(&back_buffer, WIDTH, HEIGHT);

    const window_class: win32.WNDCLASSW = .{
        .style = .{ .HREDRAW = 1, .VREDRAW = 1, .OWNDC = 1 },
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
            WIDTH + WINDOW_DECORATION_WIDTH,
            HEIGHT + WINDOW_DECORATION_HEIGHT,
            null,
            null,
            instance,
            null,
        );

        if (opt_window_handle) |window_handle| {
            const device_context = win32.GetDC(window_handle);
            var x_offset: u32 = 0;
            var y_offset: u32 = 0;

            running = true;
            while (running) {
                var message: win32.MSG = undefined;
                while (win32.PeekMessageW(&message, window_handle, 0, 0, win32.PM_REMOVE) != 0) {
                    if (message.message == win32.WM_QUIT) {
                        running = false;
                    }
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);
                }

                var dwResult: isize = 0;
                var controller_index: u8 = 0;
                while (controller_index < win32.XUSER_MAX_COUNT) {
                    var controller_state: win32.XINPUT_STATE = undefined;
                    dwResult = XInputGetState(controller_index, &controller_state);

                    if (dwResult == @intFromEnum(win32.ERROR_SUCCESS)) {
                        // Controller is connected
                        const pad = &controller_state.Gamepad;
                        const up: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_UP) > 0;
                        const down: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_DOWN) > 0;
                        const left: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_LEFT) > 0;
                        const right: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_RIGHT) > 0;
                        //
                        // const start: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_START) > 0;
                        // const back: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_BACK) > 0;
                        //
                        // const left_shoulder: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_LEFT_SHOULDER) > 0;
                        // const right_shoulder: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_RIGHT_SHOULDER) > 0;
                        //
                        const a_button: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_A) > 0;
                        // const b_button: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_B) > 0;
                        // const x_button: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_X) > 0;
                        // const y_button: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_Y) > 0;

                        const stick_x = pad.sThumbLX >> STICK_DOWN_SHIFT;
                        const stick_y = pad.sThumbLY >> STICK_DOWN_SHIFT;

                        // Apply left stick X.
                        if (stick_x < -STICK_DEAD_ZONE) {
                            x_offset -%= @abs(stick_x);
                        } else if (stick_x > STICK_DEAD_ZONE) {
                            x_offset +%= @abs(stick_x);
                        }

                        // Apply left stick Y.
                        if (stick_y > STICK_DEAD_ZONE) {
                            y_offset -%= @abs(stick_y);
                        } else if (stick_y < -STICK_DEAD_ZONE) {
                            y_offset +%= @abs(stick_y);
                        }

                        // Apply D-Pad X;
                        if (left) {
                            x_offset -%= 1;
                        } else if (right) {
                            x_offset +%= 1;
                        }

                        // Apply D-Pad Y;
                        if (up) {
                            y_offset -%= 1;
                        } else if (down) {
                            y_offset +%= 1;
                        }

                        if (a_button) {
                            var vibration: win32.XINPUT_VIBRATION = win32.XINPUT_VIBRATION{
                                .wRightMotorSpeed = 9000,
                                .wLeftMotorSpeed = 9000,
                            };
                            _ = XInputSetState(controller_index, &vibration);
                        } else {
                            var vibration: win32.XINPUT_VIBRATION = win32.XINPUT_VIBRATION{
                                .wRightMotorSpeed = 0,
                                .wLeftMotorSpeed = 0,
                            };
                            _ = XInputSetState(controller_index, &vibration);
                        }
                    } else {
                        // Controller is not connected
                    }

                    controller_index += 1;
                }
                renderWeirdGradient(&back_buffer, x_offset, y_offset);

                const window_dimension = getWindowDimension(window_handle);
                displayBufferInWindow(&back_buffer, device_context, window_dimension.width, window_dimension.height);
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
