const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").system.com;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.input;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").media.audio;
    usingnamespace @import("win32").media.audio.direct_sound;
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
var opt_secondary_buffer: ?*win32.IDirectSoundBuffer = undefined;

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
    const x_input_library = win32.LoadLibraryA("xinput1_4.dll") orelse win32.LoadLibraryA("xinput1_3.dll");
    if (x_input_library) |library| {
        if (win32.GetProcAddress(library, "XInputGetState")) |procedure| {
            XInputGetState = @as(@TypeOf(XInputGetState), @ptrCast(procedure));
        }
        if (win32.GetProcAddress(library, "XInputSetState")) |procedure| {
            XInputSetState = @as(@TypeOf(XInputSetState), @ptrCast(procedure));
        }
    }
}

fn initDirectSound(window: win32.HWND, samples_per_second: u32, buffer_size: u32) void {
    // Load the library.
    if (win32.LoadLibraryA("dsound.dll")) |library| {
        if (win32.GetProcAddress(library, "DirectSoundCreate")) |procedure| {
            var DirectSoundCreate: *const fn (?*const win32.Guid, ?*?*win32.IDirectSound, ?*win32.IUnknown) win32.HRESULT = undefined;
            DirectSoundCreate = @as(@TypeOf(DirectSoundCreate), @ptrCast(procedure));

            // Create the DirectSound object.
            var opt_direct_sound: ?*win32.IDirectSound = undefined;
            if (win32.SUCCEEDED(DirectSoundCreate(null, &opt_direct_sound, null))) {
                if (opt_direct_sound) |direct_sound| {
                    var wave_format = win32.WAVEFORMATEX{
                        .wFormatTag = win32.WAVE_FORMAT_PCM,
                        .nChannels = 2,
                        .nSamplesPerSec = samples_per_second,
                        .nAvgBytesPerSec = 0,
                        .nBlockAlign = 0,
                        .wBitsPerSample = 16,
                        .cbSize = 0,
                    };

                    wave_format.nBlockAlign = (wave_format.nChannels * wave_format.wBitsPerSample) / 8;
                    wave_format.nAvgBytesPerSec = wave_format.nSamplesPerSec * wave_format.nBlockAlign;

                    if (win32.SUCCEEDED(direct_sound.vtable.SetCooperativeLevel(direct_sound, window, win32.DSSCL_PRIORITY))) {
                        // Create the primary buffer.
                        var buffer_description = win32.DSBUFFERDESC{
                            .dwSize = @sizeOf(win32.DSBUFFERDESC),
                            .dwFlags = win32.DSBCAPS_PRIMARYBUFFER,
                            .dwBufferBytes = 0,
                            .dwReserved = 0,
                            .lpwfxFormat = null,
                            .guid3DAlgorithm = win32.Guid.initString("00000000-0000-0000-0000-000000000000"),
                        };
                        var opt_primary_buffer: ?*win32.IDirectSoundBuffer = undefined;

                        if (win32.SUCCEEDED(direct_sound.vtable.CreateSoundBuffer(direct_sound, &buffer_description, &opt_primary_buffer, null))) {
                            if (opt_primary_buffer) |primary_buffer| {
                                if (win32.SUCCEEDED(primary_buffer.vtable.SetFormat(primary_buffer, &wave_format))) {
                                    win32.OutputDebugStringA("Primary buffer created!\n");
                                }
                            }
                        }
                    }

                    // Create the secondary buffer.
                    var buffer_description = win32.DSBUFFERDESC{
                        .dwSize = @sizeOf(win32.DSBUFFERDESC),
                        .dwFlags = 0,
                        .dwBufferBytes = buffer_size,
                        .dwReserved = 0,
                        .lpwfxFormat = &wave_format,
                        .guid3DAlgorithm = win32.Guid.initString("00000000-0000-0000-0000-000000000000"),
                    };
                    if (win32.SUCCEEDED(direct_sound.vtable.CreateSoundBuffer(direct_sound, &buffer_description, &opt_secondary_buffer, null))) {
                        if (opt_secondary_buffer) |secondary_buffer| {
                            _ = secondary_buffer;
                            win32.OutputDebugStringA("Secondary buffer created!\n");
                        }
                    }
                }
            }
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
    buffer.memory = win32.VirtualAlloc(null, bitmap_memory_size, win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 }, win32.PAGE_READWRITE);
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
                    else => {
                        result = win32.DefWindowProc(window, message, w_param, l_param);
                    },
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

            const samples_per_second = 48000;
            const bytes_per_sample = @sizeOf(i16) * 2;
            const secondary_buffer_size = samples_per_second * bytes_per_sample;
            var running_sample_index: u32 = 0;

            const square_wave_hz: i32 = 256;
            const square_wave_period: i32 = samples_per_second / square_wave_hz;
            const half_square_wave_period: i32 = square_wave_period / 2;
            const square_wave_volume: i32 = 3000;
            var sound_is_playing: bool = false;

            initDirectSound(window_handle, samples_per_second, secondary_buffer_size);

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

                if (opt_secondary_buffer) |secondary_buffer| {
                    var play_cursor: std.os.windows.DWORD = undefined;
                    var write_cursor: std.os.windows.DWORD = undefined;

                    if (win32.SUCCEEDED(secondary_buffer.vtable.GetCurrentPosition(secondary_buffer, &play_cursor, &write_cursor))) {
                        const byte_to_lock: std.os.windows.DWORD = running_sample_index * bytes_per_sample % secondary_buffer_size;
                        var bytes_to_write: u32 = 0;

                        if (byte_to_lock == play_cursor) {
                            bytes_to_write = secondary_buffer_size;
                        } else if (byte_to_lock > play_cursor) {
                            bytes_to_write = secondary_buffer_size - byte_to_lock;
                            bytes_to_write += play_cursor;
                        } else {
                            bytes_to_write = play_cursor - byte_to_lock;
                        }

                        var region1: ?*anyopaque = undefined;
                        var region1_size: std.os.windows.DWORD = 0;
                        var region2: ?*anyopaque = undefined;
                        var region2_size: std.os.windows.DWORD = 0;

                        if (win32.SUCCEEDED(secondary_buffer.vtable.Lock(
                            secondary_buffer,
                            byte_to_lock,
                            bytes_to_write,
                            &region1,
                            &region1_size,
                            &region2,
                            &region2_size,
                            0,
                        ))) {
                            if (region1) |region| {
                                var sample_out: [*]i16 = @ptrCast(@alignCast(region));
                                var sample_index: u32 = 0;
                                const region1_sample_count = region1_size / bytes_per_sample;
                                while (sample_index < region1_sample_count) {
                                    const sample_value: i16 = if ((@divFloor(running_sample_index, half_square_wave_period) % 2) == 1) square_wave_volume else -square_wave_volume;
                                    sample_out += 1;
                                    sample_out[0] = sample_value;
                                    sample_out += 1;
                                    sample_out[0] = sample_value;

                                    sample_index += 1;
                                    running_sample_index += 1;
                                }
                            }

                            if (region2) |region| {
                                var sample_out: [*]i16 = @ptrCast(@alignCast(region));
                                var sample_index: u32 = 0;
                                const region2_sample_count = region2_size / bytes_per_sample;
                                while (sample_index < region2_sample_count) {
                                    const sample_value: i16 = if ((@divFloor(running_sample_index, half_square_wave_period) % 2) == 1) square_wave_volume else -square_wave_volume;
                                    sample_out += 1;
                                    sample_out[0] = sample_value;
                                    sample_out += 1;
                                    sample_out[0] = sample_value;

                                    sample_index += 1;
                                    running_sample_index += 1;
                                }
                            }

                            _ = secondary_buffer.vtable.Unlock(secondary_buffer, region1, region1_size, region2, region2_size);
                        }
                    }

                    if (!sound_is_playing) {
                        _ = secondary_buffer.vtable.Play(secondary_buffer, 0, 0, win32.DSBPLAY_LOOPING);
                        sound_is_playing = true;
                    }
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
