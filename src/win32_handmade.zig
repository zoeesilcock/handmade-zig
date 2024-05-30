/// TODO: This is not a final platform layer!
///
/// Partial list of missing parts:
///
/// * Save game locations.
/// * Getting a handle to our own executable file.
/// * Asset loading path.
/// * Threading (launching a thread).
/// * Raw Input (support for multiple keyboards).
/// * Sleep/timeBeginPeriod.
/// * ClipCursor() (for multi-monitor support).
/// * WM_SETCURSOR (control cursor visibility).
/// * QueryCancelAutoplay.
/// * WM_ACTIVATEAPP (for when we are not the active application).
/// * Blit speed improvements (BitBlt).
/// * Hardware acceleration (OpenGL or Direct3D or BOTH?).
/// * Get KeyboardLayout (for international keyboards).

pub const UNICODE = true;

const PI32: f32 = 3.1415926535897932384626433;
const TAU32: f32 = PI32 * 2.0;
const MIDDLE_C: u32 = 261;
const TREBLE_C: u32 = 523;

const WIDTH = 1280;
const HEIGHT = 720;
const WINDOW_DECORATION_WIDTH = 16;
const WINDOW_DECORATION_HEIGHT = 39;
const BYTES_PER_PIXEL = 4;
const STICK_DEAD_ZONE = 1;

const game = @import("handmade.zig");

const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").system.com;
    usingnamespace @import("win32").system.performance;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.input;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").media.audio;
    usingnamespace @import("win32").media.audio.direct_sound;
};

var running: bool = false;
var back_buffer: OffscreenBuffer = .{};
var opt_secondary_buffer: ?*win32.IDirectSoundBuffer = undefined;

pub inline fn rdtsc() u64 {
    var hi: u32 = 0;
    var low: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}

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

const SoundOutput = struct {
    samples_per_second: u32,
    bytes_per_sample: u32,
    secondary_buffer_size: u32,
    running_sample_index: u32,
    tone_hz: u32,
    wave_period: u32,
    wave_volume: i32,
    wave_time: f32,
    latency_sample_count: u32,
};

fn XInputGetStateStub(_: u32, _: ?*win32.XINPUT_STATE) callconv(std.os.windows.WINAPI) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
fn XInputSetStateStub(_: u32, _: ?*win32.XINPUT_VIBRATION) callconv(std.os.windows.WINAPI) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
var XInputGetState: *const fn (u32, ?*win32.XINPUT_STATE) callconv(std.os.windows.WINAPI) isize = XInputGetStateStub;
var XInputSetState: *const fn (u32, ?*win32.XINPUT_VIBRATION) callconv(std.os.windows.WINAPI) isize = XInputSetStateStub;

fn loadXInput() void {
    const x_input_library = win32.LoadLibraryA("xinput1_4.dll") orelse win32.LoadLibraryA("xinput1_3.dll") orelse win32.LoadLibraryA("xinput9_1_0.dll");

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

fn fillSoundBuffer(sound_output: *SoundOutput, secondary_buffer: *win32.IDirectSoundBuffer, byte_to_lock: u32, bytes_to_write: u32) void {
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
            const region1_sample_count = region1_size / sound_output.bytes_per_sample;
            while (sample_index < region1_sample_count) {
                const sine_value: f32 = @sin(sound_output.wave_time);
                const sample_value: i16 = @intFromFloat(sine_value * @as(f32, @floatFromInt(sound_output.wave_volume)));
                sample_out += 1;
                sample_out[0] = sample_value;
                sample_out += 1;
                sample_out[0] = sample_value;

                sample_index += 1;
                sound_output.running_sample_index += 1;
                sound_output.wave_time += TAU32 / @as(f32, @floatFromInt(sound_output.wave_period));
            }
        }

        if (region2) |region| {
            var sample_out: [*]i16 = @ptrCast(@alignCast(region));
            var sample_index: u32 = 0;
            const region2_sample_count = region2_size / sound_output.bytes_per_sample;
            while (sample_index < region2_sample_count) {
                const sine_value: f32 = @sin(sound_output.wave_time);
                const sample_value: i16 = @intFromFloat(sine_value * @as(f32, @floatFromInt(sound_output.wave_volume)));
                sample_out += 1;
                sample_out[0] = sample_value;
                sample_out += 1;
                sample_out[0] = sample_value;

                sample_index += 1;
                sound_output.running_sample_index += 1;
                sound_output.wave_time += TAU32 / @as(f32, @floatFromInt(sound_output.wave_period));
            }
        }

        _ = secondary_buffer.vtable.Unlock(secondary_buffer, region1, region1_size, region2, region2_size);
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
                        result = win32.DefWindowProcA(window, message, w_param, l_param);
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

    var performance_frequency: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&performance_frequency);
    const perf_count_frequency: i64 = performance_frequency.QuadPart;

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
            var sound_output = SoundOutput{
                .samples_per_second = 48000,
                .bytes_per_sample = @sizeOf(i16) * 2,
                .secondary_buffer_size = 0,
                .running_sample_index = 0,
                .tone_hz = MIDDLE_C,
                .wave_volume = 3000,
                .wave_period = 0,
                .wave_time = 0,
                .latency_sample_count = 0,
            };

            sound_output.secondary_buffer_size = sound_output.samples_per_second * sound_output.bytes_per_sample;
            sound_output.wave_period = @divFloor(sound_output.samples_per_second, sound_output.tone_hz);
            sound_output.latency_sample_count = @divFloor(sound_output.samples_per_second, 15);

            initDirectSound(window_handle, sound_output.samples_per_second, sound_output.secondary_buffer_size);
            if (opt_secondary_buffer) |secondary_buffer| {
                fillSoundBuffer(&sound_output, secondary_buffer, 0, sound_output.latency_sample_count * sound_output.samples_per_second);
                _ = secondary_buffer.vtable.Play(secondary_buffer, 0, 0, win32.DSBPLAY_LOOPING);
            }

            running = true;

            // Initialize timing.
            var last_cycle_count = rdtsc();
            var last_counter: win32.LARGE_INTEGER = undefined;
            _ = win32.QueryPerformanceCounter(&last_counter);

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

                        const stick_x = @divFloor(pad.sThumbLX, 4096);
                        const stick_y = @divFloor(pad.sThumbLY, 4096);

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

                        const hz: i32 = @as(i32, @intFromFloat(@as(f32, (@floatFromInt(MIDDLE_C))) * (@as(f32, @floatFromInt(pad.sThumbLY)) / 30000.0)));
                        if (hz > 0) {
                            sound_output.tone_hz = TREBLE_C + @abs(hz);
                        } else if (hz < 0) {
                            sound_output.tone_hz = TREBLE_C - @abs(hz);
                        }
                        sound_output.wave_period = @divFloor(sound_output.samples_per_second, sound_output.tone_hz);

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

                var gameBuffer = game.OffscreenBuffer{
                    .memory = back_buffer.memory,
                    .width = back_buffer.width,
                    .height = back_buffer.height,
                    .pitch = back_buffer.pitch,
                };
                game.updateAndRender(&gameBuffer, x_offset, y_offset);

                const window_dimension = getWindowDimension(window_handle);
                displayBufferInWindow(&back_buffer, device_context, window_dimension.width, window_dimension.height);

                if (opt_secondary_buffer) |secondary_buffer| {
                    var play_cursor: std.os.windows.DWORD = undefined;
                    var write_cursor: std.os.windows.DWORD = undefined;

                    if (win32.SUCCEEDED(secondary_buffer.vtable.GetCurrentPosition(secondary_buffer, &play_cursor, &write_cursor))) {
                        const target_cursor: u32 = (play_cursor + (sound_output.latency_sample_count * sound_output.bytes_per_sample)) % sound_output.secondary_buffer_size;
                        const byte_to_lock: u32 = (sound_output.running_sample_index * sound_output.bytes_per_sample) % sound_output.secondary_buffer_size;
                        var bytes_to_write: u32 = 0;

                        if (byte_to_lock > target_cursor) {
                            bytes_to_write = sound_output.secondary_buffer_size - byte_to_lock;
                            bytes_to_write += target_cursor;
                        } else {
                            bytes_to_write = target_cursor - byte_to_lock;
                        }

                        fillSoundBuffer(&sound_output, secondary_buffer, byte_to_lock, bytes_to_write);
                    }
                }

                // Capture timing.
                const end_cycle_count = rdtsc();
                var end_counter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&end_counter);

                // Calculate timing information.
                const counter_elapsed: i64 = end_counter.QuadPart - last_counter.QuadPart;
                const ms_elapsed: f32 = @as(f32, @floatFromInt(1000 * counter_elapsed)) / @as(f32, @floatFromInt(perf_count_frequency));
                const fps: f32 = @as(f32, @floatFromInt(perf_count_frequency)) / @as(f32, @floatFromInt(counter_elapsed));
                const cycles_elapsed: i32 = @intCast(end_cycle_count - last_cycle_count);
                const mega_cycles_per_frame: f32 = @as(f32, @floatFromInt(cycles_elapsed)) / @as(f32, @floatFromInt(1000 * 1000));

                // Output timing information.
                var buffer: [64]u8 = undefined;
                _ = std.fmt.bufPrint(&buffer, "{d:>3.2}ms/f, {d:>3.2}:f/s, {d:>3.2}:mc/f   ", .{ ms_elapsed, fps, mega_cycles_per_frame }) catch {};
                win32.OutputDebugStringA(@ptrCast(&buffer));

                last_counter = end_counter;
                last_cycle_count = end_cycle_count;
            }
        } else {
            win32.OutputDebugStringA("Window handle is null.\n");
        }
    } else {
        win32.OutputDebugStringA("Register class failed.\n");
    }

    return 0;
}
