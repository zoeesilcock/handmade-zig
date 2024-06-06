/// TODO: This is not a final platform layer!
///
/// Partial list of missing parts:
///
/// * Save game locations.
/// * Getting a handle to our own executable file.
/// * Asset loading path.
/// * Threading (launching a thread).
/// * Raw Input (support for multiple keyboards).
/// * ClipCursor() (for multi-monitor support).
/// * WM_SETCURSOR (control cursor visibility).
/// * QueryCancelAutoplay.
/// * WM_ACTIVATEAPP (for when we are not the active application).
/// * Blit speed improvements (BitBlt).
/// * Hardware acceleration (OpenGL or Direct3D or BOTH?).
/// * Get KeyboardLayout (for international keyboards).
pub const UNICODE = true;

const MIDDLE_C: u32 = 261;
const TREBLE_C: u32 = 523;

const WIDTH = 1280;
const HEIGHT = 720;
const WINDOW_DECORATION_WIDTH = 16;
const WINDOW_DECORATION_HEIGHT = 39;
const BYTES_PER_PIXEL = 4;

const OUTPUT_TIMING = @import("build_options").timing;
const DEBUG = @import("builtin").mode == std.builtin.OptimizeMode.Debug;

const game = @import("handmade.zig");

const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").media;
    usingnamespace @import("win32").media.audio;
    usingnamespace @import("win32").media.audio.direct_sound;
    usingnamespace @import("win32").storage.file_system;
    usingnamespace @import("win32").system.com;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").system.performance;
    usingnamespace @import("win32").system.threading;
    usingnamespace @import("win32").ui.input;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").zig;
};

// Globals.
var running: bool = false;
var back_buffer: OffscreenBuffer = .{};
var opt_secondary_buffer: ?*win32.IDirectSoundBuffer = undefined;
var perf_count_frequency: i64 = 0;

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
    latency_sample_count: u32,
};

const SoundOutputInfo = struct {
    byte_to_lock: u32 = 0,
    bytes_to_write: u32 = 0,
    is_valid: bool = false,
    output_buffer: game.SoundOutputBuffer,
};

const DebugTimeMarker = struct {
    play_cursor: std.os.windows.DWORD = 0,
    write_cursor: std.os.windows.DWORD = 0,
};

fn debugReadEntireFile(file_name: [*:0]const u8) game.DebugReadFileResult {
    var result = game.DebugReadFileResult{};

    const file_handle: win32.HANDLE = win32.CreateFileA(
        file_name,
        win32.FILE_GENERIC_READ,
        win32.FILE_SHARE_READ,
        null,
        win32.FILE_CREATION_DISPOSITION.OPEN_EXISTING,
        win32.FILE_FLAGS_AND_ATTRIBUTES{},
        null,
    );

    if (file_handle != win32.INVALID_HANDLE_VALUE) {
        var file_size: win32.LARGE_INTEGER = undefined;
        if (win32.GetFileSizeEx(file_handle, &file_size) != 0) {
            const file_size32 = game.safeTruncateI64(file_size.QuadPart);

            if (win32.VirtualAlloc(
                undefined,
                file_size32,
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            )) |file_contents| {
                var bytes_read: u32 = undefined;

                if (win32.ReadFile(
                    file_handle,
                    file_contents,
                    file_size32,
                    &bytes_read,
                    null,
                ) != 0 and bytes_read == file_size32) {
                    // File read successfully.
                    result.contents = file_contents;
                    result.content_size = file_size32;
                } else {
                    debugFreeFileMemory(result.contents);
                    result.contents = undefined;
                }
            }
        }

        _ = win32.CloseHandle(file_handle);
    }

    return result;
}

fn debugWriteEntireFile(file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) bool {
    var result: bool = false;

    const file_handle: win32.HANDLE = win32.CreateFileA(
        file_name,
        win32.FILE_GENERIC_WRITE,
        win32.FILE_SHARE_NONE,
        null,
        win32.FILE_CREATION_DISPOSITION.CREATE_ALWAYS,
        win32.FILE_FLAGS_AND_ATTRIBUTES{},
        null,
    );

    if (file_handle != win32.INVALID_HANDLE_VALUE) {
        var bytes_written: u32 = undefined;

        if (win32.WriteFile(file_handle, memory, memory_size, &bytes_written, null) != 0) {
            // File written successfully.
            result = bytes_written == memory_size;
        }

        _ = win32.CloseHandle(file_handle);
    }

    return result;
}

fn debugFreeFileMemory(memory: *anyopaque) void {
    _ = win32.VirtualFree(memory, 0, win32.MEM_RELEASE);
}

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

fn processXInput(old_input: *game.ControllerInputs, new_input: *game.ControllerInputs) void {
    var dwResult: isize = 0;
    var controller_index: u8 = 0;

    var max_controller_count = win32.XUSER_MAX_COUNT;
    if (max_controller_count > (game.MAX_CONTROLLER_COUNT - 1)) {
        max_controller_count = game.MAX_CONTROLLER_COUNT;
    }

    while (controller_index < max_controller_count) : (controller_index += 1) {
        const our_controller_index = controller_index + 1;
        const old_controller = &old_input.controllers[our_controller_index];
        const new_controller = &new_input.controllers[our_controller_index];

        var controller_state: win32.XINPUT_STATE = undefined;
        dwResult = XInputGetState(controller_index, &controller_state);

        if (dwResult == @intFromEnum(win32.ERROR_SUCCESS)) {
            // Controller is connected
            const pad = &controller_state.Gamepad;
            new_controller.is_analog = true;
            new_controller.is_connected = true;

            // Left stick X.
            new_controller.stick_average_x = processXInputStick(pad.sThumbLX, win32.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);

            // Left stick Y.
            new_controller.stick_average_y = processXInputStick(pad.sThumbLY, win32.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);

            // D-pad overrides the stick value.
            if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_UP) > 0) {
                new_controller.stick_average_y = 1.0;
                new_controller.is_analog = true;
            } else if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_DOWN) > 0) {
                new_controller.stick_average_y = -1.0;
                new_controller.is_analog = true;
            }
            if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_LEFT) > 0) {
                new_controller.stick_average_x = 1.0;
                new_controller.is_analog = true;
            } else if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_RIGHT) > 0) {
                new_controller.stick_average_x = -1.0;
                new_controller.is_analog = true;
            }

            // Movement buttons based on left stick.
            const threshold = 0.5;
            processXInputDigitalButton(
                if (new_controller.stick_average_y > threshold) 1 else 0,
                1,
                &old_controller.move_up,
                &new_controller.move_up,
            );
            processXInputDigitalButton(
                if (new_controller.stick_average_y < -threshold) 1 else 0,
                1,
                &old_controller.move_down,
                &new_controller.move_down,
            );
            processXInputDigitalButton(
                if (new_controller.stick_average_x < -threshold) 1 else 0,
                1,
                &old_controller.move_left,
                &new_controller.move_left,
            );
            processXInputDigitalButton(
                if (new_controller.stick_average_x > threshold) 1 else 0,
                1,
                &old_controller.move_right,
                &new_controller.move_right,
            );

            // Main buttons.
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_A,
                &old_controller.action_down,
                &new_controller.action_down,
            );
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_B,
                &old_controller.action_right,
                &new_controller.action_right,
            );
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_X,
                &old_controller.action_left,
                &new_controller.action_left,
            );
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_Y,
                &old_controller.action_up,
                &new_controller.action_up,
            );

            // Shoulder buttons.
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_LEFT_SHOULDER,
                &old_controller.left_shoulder,
                &new_controller.left_shoulder,
            );
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_RIGHT_SHOULDER,
                &old_controller.right_shoulder,
                &new_controller.right_shoulder,
            );

            // Special buttons.
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_START,
                &old_controller.start_button,
                &new_controller.start_button,
            );
            processXInputDigitalButton(
                pad.wButtons,
                win32.XINPUT_GAMEPAD_BACK,
                &old_controller.back_button,
                &new_controller.back_button,
            );
        } else {
            // Controller is not connected
        }
    }
}

fn copyButtonStates(new_controller: *game.ControllerInput, old_controller: *game.ControllerInput) void {
    new_controller.move_up.ended_down = old_controller.move_up.ended_down;
    new_controller.move_down.ended_down = old_controller.move_down.ended_down;
    new_controller.move_left.ended_down = old_controller.move_left.ended_down;
    new_controller.move_right.ended_down = old_controller.move_right.ended_down;

    new_controller.action_up.ended_down = old_controller.action_up.ended_down;
    new_controller.action_down.ended_down = old_controller.action_down.ended_down;
    new_controller.action_left.ended_down = old_controller.action_left.ended_down;
    new_controller.action_right.ended_down = old_controller.action_right.ended_down;

    new_controller.left_shoulder.ended_down = old_controller.left_shoulder.ended_down;
    new_controller.right_shoulder.ended_down = old_controller.right_shoulder.ended_down;

    new_controller.start_button.ended_down = old_controller.start_button.ended_down;
    new_controller.back_button.ended_down = old_controller.back_button.ended_down;
}

fn processXInputDigitalButton(
    x_input_button_state: u32,
    button_bit: u32,
    old_state: *game.ControllerButtonState,
    new_state: *game.ControllerButtonState,
) void {
    new_state.ended_down = (x_input_button_state & button_bit) > 0;
    new_state.half_transitions = if (old_state.ended_down != new_state.ended_down) 1 else 0;
}

fn processXInputStick(value: i16, dead_zone: i16) f32 {
    var result: f32 = 0;
    const float_value: f32 = @floatFromInt(value);
    const float_dead_zone: f32 = @floatFromInt(dead_zone);

    if (value < -@as(i16, @intCast(dead_zone))) {
        result = (float_value + float_dead_zone) / (32768.0 - float_dead_zone);
    } else if (value > dead_zone) {
        result = (float_value - float_dead_zone) / (32767.0 + float_dead_zone);
    }

    return result;
}

fn processKeyboardInput(message: win32.MSG, keyboard_controller: *game.ControllerInput) void {
    const vk_code = message.wParam;
    const was_down: bool = if ((message.lParam & (1 << 30) != 0)) true else false;
    const is_down: bool = if ((message.lParam & (1 << 31) == 0)) true else false;

    if (is_down != was_down) {
        switch (vk_code) {
            'W' => {
                processKeyboardInputMessage(&keyboard_controller.move_up, is_down);
            },
            'A' => {
                processKeyboardInputMessage(&keyboard_controller.move_left, is_down);
            },
            'S' => {
                processKeyboardInputMessage(&keyboard_controller.move_down, is_down);
            },
            'D' => {
                processKeyboardInputMessage(&keyboard_controller.move_right, is_down);
            },
            'Q' => {
                processKeyboardInputMessage(&keyboard_controller.left_shoulder, is_down);
            },
            'E' => {
                processKeyboardInputMessage(&keyboard_controller.right_shoulder, is_down);
            },
            @intFromEnum(win32.VK_UP) => {
                processKeyboardInputMessage(&keyboard_controller.action_up, is_down);
            },
            @intFromEnum(win32.VK_DOWN) => {
                processKeyboardInputMessage(&keyboard_controller.action_down, is_down);
            },
            @intFromEnum(win32.VK_LEFT) => {
                processKeyboardInputMessage(&keyboard_controller.action_left, is_down);
            },
            @intFromEnum(win32.VK_RIGHT) => {
                processKeyboardInputMessage(&keyboard_controller.action_left, is_down);
            },
            @intFromEnum(win32.VK_SPACE) => {
                processKeyboardInputMessage(&keyboard_controller.start_button, is_down);
            },
            @intFromEnum(win32.VK_ESCAPE) => {
                processKeyboardInputMessage(&keyboard_controller.back_button, is_down);
            },
            else => {},
        }
    }
}

fn processKeyboardInputMessage(
    new_state: *game.ControllerButtonState,
    is_down: bool,
) void {
    std.debug.assert(is_down != new_state.ended_down);

    new_state.ended_down = is_down;
    new_state.half_transitions += 1;
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

fn clearSoundBuffer(sound_output: *SoundOutput, secondary_buffer: *win32.IDirectSoundBuffer) void {
    var region1: ?*anyopaque = undefined;
    var region1_size: std.os.windows.DWORD = 0;
    var region2: ?*anyopaque = undefined;
    var region2_size: std.os.windows.DWORD = 0;

    if (win32.SUCCEEDED(secondary_buffer.vtable.Lock(
        secondary_buffer,
        0,
        sound_output.secondary_buffer_size,
        &region1,
        &region1_size,
        &region2,
        &region2_size,
        0,
    ))) {
        if (region1) |region| {
            var sample_out: [*]u8 = @ptrCast(@alignCast(region));
            var byte_index: u32 = 0;
            while (byte_index < region1_size) {
                sample_out[0] = 0;
                sample_out += 1;
                byte_index += 1;
            }
        }

        if (region2) |region| {
            var sample_out: [*]u8 = @ptrCast(@alignCast(region));
            var byte_index: u32 = 0;
            while (byte_index < region2_size) {
                sample_out[0] = 0;
                sample_out += 1;
                byte_index += 1;
            }
        }

        _ = secondary_buffer.vtable.Unlock(secondary_buffer, region1, region1_size, region2, region2_size);
    }
}

fn fillSoundBuffer(sound_output: *SoundOutput, secondary_buffer: *win32.IDirectSoundBuffer, info: *SoundOutputInfo) void {
    var region1: ?*anyopaque = undefined;
    var region1_size: std.os.windows.DWORD = 0;
    var region2: ?*anyopaque = undefined;
    var region2_size: std.os.windows.DWORD = 0;

    if (win32.SUCCEEDED(secondary_buffer.vtable.Lock(
        secondary_buffer,
        info.byte_to_lock,
        info.bytes_to_write,
        &region1,
        &region1_size,
        &region2,
        &region2_size,
        0,
    ))) {
        var source_sample: [*]i16 = info.output_buffer.samples;

        if (region1) |region| {
            var sample_out: [*]i16 = @ptrCast(@alignCast(region));
            var sample_index: u32 = 0;
            const region1_sample_count = region1_size / sound_output.bytes_per_sample;
            while (sample_index < region1_sample_count) {
                sample_out[0] = source_sample[0];
                sample_out += 1;
                source_sample += 1;

                sample_out[0] = source_sample[0];
                sample_out += 1;
                source_sample += 1;

                sample_index += 1;
                sound_output.running_sample_index += 1;
            }
        }

        if (region2) |region| {
            var sample_out: [*]i16 = @ptrCast(@alignCast(region));
            var sample_index: u32 = 0;
            const region2_sample_count = region2_size / sound_output.bytes_per_sample;
            while (sample_index < region2_sample_count) {
                sample_out[0] = source_sample[0];
                sample_out += 1;
                source_sample += 1;

                sample_out[0] = source_sample[0];
                sample_out += 1;
                source_sample += 1;

                sample_index += 1;
                sound_output.running_sample_index += 1;
            }
        }

        _ = secondary_buffer.vtable.Unlock(secondary_buffer, region1, region1_size, region2, region2_size);
    }
}

fn calculateSoundOutputInfo(
    sound_output: SoundOutput,
    info: *SoundOutputInfo,
    samples: [*]i16,
    last_play_cursor: std.os.windows.DWORD,
) void {
    if (info.is_valid) {
        const target_cursor: u32 = (last_play_cursor + (sound_output.latency_sample_count * sound_output.bytes_per_sample)) % sound_output.secondary_buffer_size;
        info.byte_to_lock = (sound_output.running_sample_index * sound_output.bytes_per_sample) % sound_output.secondary_buffer_size;

        if (info.byte_to_lock > target_cursor) {
            info.bytes_to_write = sound_output.secondary_buffer_size - info.byte_to_lock;
            info.bytes_to_write += target_cursor;
        } else {
            info.bytes_to_write = target_cursor - info.byte_to_lock;
        }

        if (OUTPUT_TIMING) {
            var buffer: [64]u8 = undefined;
            _ = std.fmt.bufPrint(&buffer, "LPC:{d} BTL:{d} TC:{d} BTW:{d}    \n", .{
                last_play_cursor,
                info.byte_to_lock,
                target_cursor,
                info.bytes_to_write,
            }) catch {};
            win32.OutputDebugStringA(@ptrCast(&buffer));
        }
    }

    info.output_buffer = game.SoundOutputBuffer{
        .samples = samples,
        .sample_count = @divFloor(info.bytes_to_write, sound_output.bytes_per_sample),
        .samples_per_second = sound_output.samples_per_second,
    };
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

fn getGameBuffer() game.OffscreenBuffer {
    return game.OffscreenBuffer{
        .memory = back_buffer.memory,
        .width = back_buffer.width,
        .height = back_buffer.height,
        .pitch = back_buffer.pitch,
    };
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
) callconv(std.os.windows.WINAPI) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_QUIT => {
            running = false;
        },
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
            // No keyboard input should come from anywhere other than the main loop.
            std.debug.assert(false);
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

inline fn getWallClock() win32.LARGE_INTEGER {
    var result: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceCounter(&result);
    return result;
}

inline fn getSecondsElapsed(start: win32.LARGE_INTEGER, end: win32.LARGE_INTEGER) f32 {
    return @as(f32, @floatFromInt(end.QuadPart - start.QuadPart)) / @as(f32, @floatFromInt(perf_count_frequency));
}

fn debugDrawVertical(buffer: *OffscreenBuffer, x: i32, top: i32, bottom: i32, color: u32) void {
    var pixel: [*]u8 = @ptrCast(buffer.memory);
    pixel += @as(u32, @intCast((x * BYTES_PER_PIXEL) + (top * @as(i32, @intCast(buffer.pitch)))));

    var y = top;
    while (y < bottom) : (y += 1) {
        const p = @as(*u32, @ptrCast(@alignCast(pixel)));
        p.* = color;
        pixel += buffer.pitch;
    }
}

fn debugDrawSoundBufferMarker(
    buffer: *OffscreenBuffer,
    sound_output: *SoundOutput,
    value: std.os.windows.DWORD,
    c: f32,
    pad_x: i32,
    top: i32,
    bottom: i32,
    color: u32,
) void {
    std.debug.assert(value < sound_output.secondary_buffer_size);

    const x: i32 = pad_x + @as(i32, @intFromFloat(c * @as(f32, @floatFromInt(value))));
    debugDrawVertical(buffer, x, top, bottom, color);
}

fn debugSyncDisplay(
    buffer: *OffscreenBuffer,
    markers: []DebugTimeMarker,
    sound_output: *SoundOutput,
    seconds_per_frame: f32,
) void {
    _ = seconds_per_frame;

    const pad_x = 16;
    const pad_y = 16;
    const top = pad_y;
    const bottom = buffer.height - pad_y;
    const c: f32 = @as(f32, @floatFromInt(buffer.width - (2 * pad_x))) / @as(f32, @floatFromInt(sound_output.secondary_buffer_size));

    for (markers) |marker| {
        debugDrawSoundBufferMarker(buffer, sound_output, marker.play_cursor, c, pad_x, top, bottom, 0xFFFFFFFF);
        debugDrawSoundBufferMarker(buffer, sound_output, marker.write_cursor, c, pad_x, top, bottom, 0xFFFF0000);
    }
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
    perf_count_frequency = performance_frequency.QuadPart;

    // Set the Windows schedular granularity so that our Sleep() call can be more grannular.
    const desired_scheduler_ms = 1;
    const sleep_is_grannular = win32.timeBeginPeriod(desired_scheduler_ms) == win32.TIMERR_NOERROR;

    loadXInput();
    resizeDBISection(&back_buffer, WIDTH, HEIGHT);
    const platform = game.Platform{
        .debugReadEntireFile = debugReadEntireFile,
        .debugWriteEntireFile = debugWriteEntireFile,
        .debugFreeFileMemory = debugFreeFileMemory,
    };

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

    // TODO: Calculate actual screen refresh rate here.
    const frames_of_audio_latency = 3;
    const monitor_refresh_hz = 60;
    const game_update_hz = monitor_refresh_hz / 2;
    const target_seconds_per_frame: f32 = 1.0 / @as(f32, @floatFromInt(game_update_hz));

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
            var sound_output = SoundOutput{
                .samples_per_second = 48000,
                .bytes_per_sample = @sizeOf(i16) * 2,
                .secondary_buffer_size = 0,
                .running_sample_index = 0,
                .latency_sample_count = 0,
            };

            sound_output.secondary_buffer_size = sound_output.samples_per_second * sound_output.bytes_per_sample;
            sound_output.latency_sample_count = frames_of_audio_latency * @divFloor(sound_output.samples_per_second, game_update_hz);
            var last_play_cursor: std.os.windows.DWORD = 0;
            var sound_output_info = SoundOutputInfo{ .output_buffer = undefined };

            const samples: [*]i16 = @ptrCast(@alignCast(win32.VirtualAlloc(
                null,
                sound_output.secondary_buffer_size,
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            )));

            var debug_time_marker_index: u32 = 0;
            var debug_time_markers: [game_update_hz / 2]DebugTimeMarker = [1]DebugTimeMarker{DebugTimeMarker{}} ** (game_update_hz / 2);

            initDirectSound(window_handle, sound_output.samples_per_second, sound_output.secondary_buffer_size);
            if (opt_secondary_buffer) |secondary_buffer| {
                clearSoundBuffer(&sound_output, secondary_buffer);
                _ = secondary_buffer.vtable.Play(secondary_buffer, 0, 0, win32.DSBPLAY_LOOPING);
            }

            var game_memory: game.Memory = game.Memory{
                .is_initialized = false,
                .permanent_storage_size = game.megabytes(64),
                .permanent_storage = undefined,
                .transient_storage_size = game.gigabytes(4),
                .transient_storage = undefined,
            };

            const base_address = if (DEBUG) @as(*u8, @ptrFromInt(game.terabytes(2))) else null;
            game_memory.permanent_storage = win32.VirtualAlloc(
                base_address,
                game_memory.permanent_storage_size + game_memory.transient_storage_size,
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            ) orelse undefined;
            if (game_memory.permanent_storage != undefined) {
                game_memory.transient_storage = @ptrFromInt(@intFromPtr(&game_memory.permanent_storage) + game_memory.permanent_storage_size);
            }

            if (samples != undefined and game_memory.permanent_storage != undefined and game_memory.transient_storage != undefined) {
                var game_input = [2]game.ControllerInputs{
                    game.ControllerInputs{},
                    game.ControllerInputs{},
                };
                var new_input = &game_input[0];
                var old_input = &game_input[1];

                running = true;

                // Initialize timing.
                var last_cycle_count: u64 = 0;
                var last_counter: win32.LARGE_INTEGER = getWallClock();
                last_cycle_count = rdtsc();

                while (running) {
                    var message: win32.MSG = undefined;

                    const old_keyboard_controller = &old_input.controllers[0];
                    const new_keyboard_controller = &new_input.controllers[0];
                    new_keyboard_controller.is_connected = true;

                    // Transfer buttons state from previous loop to this one.
                    copyButtonStates(new_keyboard_controller, old_keyboard_controller);

                    // Process all messages provided by Windows.
                    while (win32.PeekMessageW(&message, window_handle, 0, 0, win32.PM_REMOVE) != 0) {
                        switch (message.message) {
                            win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYDOWN, win32.WM_KEYUP => {
                                processKeyboardInput(message, new_keyboard_controller);
                            },
                            else => {
                                _ = win32.TranslateMessage(&message);
                                _ = win32.DispatchMessageW(&message);
                            },
                        }
                    }

                    // Prepare input to game.
                    calculateSoundOutputInfo(sound_output, &sound_output_info, samples, last_play_cursor);
                    var game_buffer = getGameBuffer();
                    processXInput(old_input, new_input);

                    // Send all input to game.
                    game.updateAndRender(platform, &game_memory, new_input.*, &game_buffer, &sound_output_info.output_buffer);

                    // Output sound.
                    if (sound_output_info.is_valid) {
                        if (opt_secondary_buffer) |secondary_buffer| {
                            fillSoundBuffer(&sound_output, secondary_buffer, &sound_output_info);

                            if (OUTPUT_TIMING) {
                                var play_cursor: std.os.windows.DWORD = undefined;
                                var write_cursor: std.os.windows.DWORD = undefined;
                                if (win32.SUCCEEDED(secondary_buffer.vtable.GetCurrentPosition(
                                    secondary_buffer,
                                    &play_cursor,
                                    &write_cursor,
                                ))) {
                                    var buffer: [64]u8 = undefined;
                                    _ = std.fmt.bufPrint(&buffer, "PC:{d} WC:{d}   \n", .{ play_cursor, write_cursor }) catch {};
                                    win32.OutputDebugStringA(@ptrCast(&buffer));
                                }
                            }
                        }
                    }

                    // Capture timing.
                    const end_cycle_count = rdtsc();
                    const work_counter = getWallClock();
                    const work_seconds_elapsed = getSecondsElapsed(last_counter, work_counter);

                    // Wait until we reach frame rate target.
                    var seconds_elapsed_for_frame = work_seconds_elapsed;
                    if (seconds_elapsed_for_frame < target_seconds_per_frame) {
                        if (sleep_is_grannular) {
                            const sleep_ms: u32 = @intFromFloat(1000.0 * (target_seconds_per_frame - seconds_elapsed_for_frame));
                            if (sleep_ms > 0) {
                                win32.Sleep(sleep_ms);
                            }
                        }

                        while (seconds_elapsed_for_frame < target_seconds_per_frame) {
                            seconds_elapsed_for_frame = getSecondsElapsed(last_counter, getWallClock());
                        }
                    } else {
                        // Target frame rate missed.
                    }

                    const end_counter = getWallClock();
                    const time_per_frame = getSecondsElapsed(last_counter, end_counter);
                    last_counter = end_counter;

                    if (DEBUG) {
                        debugSyncDisplay(
                            &back_buffer,
                            &debug_time_markers,
                            &sound_output,
                            target_seconds_per_frame,
                        );
                    }

                    // Output game to screen.
                    const window_dimension = getWindowDimension(window_handle);
                    displayBufferInWindow(&back_buffer, device_context, window_dimension.width, window_dimension.height);

                    // Calculate play cursor at the end of the frame.
                    if (opt_secondary_buffer) |secondary_buffer| {
                        var play_cursor: std.os.windows.DWORD = undefined;
                        var write_cursor: std.os.windows.DWORD = undefined;
                        if (win32.SUCCEEDED(secondary_buffer.vtable.GetCurrentPosition(
                            secondary_buffer,
                            &play_cursor,
                            &write_cursor,
                        ))) {
                            last_play_cursor = play_cursor;

                            if (!sound_output_info.is_valid) {
                                sound_output.running_sample_index = write_cursor / sound_output.bytes_per_sample;
                                sound_output_info.is_valid = true;
                            }

                            if (DEBUG) {
                                std.debug.assert(debug_time_marker_index < debug_time_markers.len);

                                debug_time_marker_index += 1;
                                if (debug_time_marker_index == debug_time_markers.len) {
                                    debug_time_marker_index = 0;
                                }

                                debug_time_markers[debug_time_marker_index].play_cursor = play_cursor;
                                debug_time_markers[debug_time_marker_index].write_cursor = write_cursor;
                            }
                        } else {
                            sound_output_info.is_valid = true;
                        }
                    }

                    if (OUTPUT_TIMING) {
                        // Calculate timing information.
                        const ms_elapsed: f32 = (1000.0 * time_per_frame);
                        const fps: f32 = 1.0 / seconds_elapsed_for_frame;
                        const cycles_elapsed: u64 = @intCast(end_cycle_count - last_cycle_count);
                        const mega_cycles_per_frame: f32 = @as(f32, @floatFromInt(cycles_elapsed)) / @as(f32, @floatFromInt(1000 * 1000));

                        // Output timing information.
                        var buffer: [64]u8 = undefined;
                        _ = std.fmt.bufPrint(&buffer, "{d:>3.2}ms/f, {d:>3.2}:f/s, {d:>3.2}:mc/f   ", .{ ms_elapsed, fps, mega_cycles_per_frame }) catch {};
                        win32.OutputDebugStringA(@ptrCast(&buffer));
                    }

                    // Flip the controller inputs for next frame.
                    const temp: *game.ControllerInputs = new_input;
                    new_input = old_input;
                    old_input = temp;

                    last_cycle_count = end_cycle_count;
                }
            } else {
                win32.OutputDebugStringA("Failed to allocate memory.\n");
            }
        } else {
            win32.OutputDebugStringA("Window handle is null.\n");
        }
    } else {
        win32.OutputDebugStringA("Register class failed.\n");
    }

    return 0;
}
