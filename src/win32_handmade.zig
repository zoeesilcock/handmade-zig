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
/// * QueryCancelAutoplay.
/// * WM_ACTIVATEAPP (for when we are not the active application).
/// * Blit speed improvements (BitBlt).
/// * Hardware acceleration (OpenGL or Direct3D or BOTH?).
/// * Get KeyboardLayout (for international keyboards).
pub const UNICODE = true;

const MIDDLE_C: u32 = 261;
const TREBLE_C: u32 = 523;

// const WIDTH = 960;
// const HEIGHT = 540;
// const WIDTH = 960 / 2;
// const HEIGHT = 540 / 2;
const WIDTH = 1920;
const HEIGHT = 1080;
const WINDOW_DECORATION_WIDTH = 16;
const WINDOW_DECORATION_HEIGHT = 39;
const BYTES_PER_PIXEL = 4;

const DEBUG_WINDOW_POS_X = -7 + 210; // + 2560;
const DEBUG_WINDOW_POS_Y = 0 + 30;
const DEBUG_WINDOW_WIDTH = WIDTH + WINDOW_DECORATION_WIDTH + 20;
const DEBUG_WINDOW_HEIGHT = HEIGHT + WINDOW_DECORATION_HEIGHT + 20;
const DEBUG_WINDOW_ACTIVE_OPACITY = 255;
const DEBUG_WINDOW_INACTIVE_OPACITY = 255;
const DEBUG_TIME_MARKER_COUNT = 30;
const STATE_FILE_NAME_COUNT = win32.MAX_PATH;

// Build options.
const INTERNAL = shared.INTERNAL;
const DEBUG = shared.DEBUG;

const shared = @import("shared.zig");
const debug_interface = @import("debug_interface.zig");

// Types
const TimedBlock = debug_interface.TimedBlock;

const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").media;
    usingnamespace @import("win32").media.audio;
    usingnamespace @import("win32").media.audio.direct_sound;
    usingnamespace @import("win32").storage.file_system;
    usingnamespace @import("win32").system.com;
    usingnamespace @import("win32").system.io;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").system.performance;
    usingnamespace @import("win32").system.threading;
    usingnamespace @import("win32").ui.input;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.shell;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").zig;
};

// Globals.
var running: bool = false;
var back_buffer: OffscreenBuffer = .{};
var opt_secondary_buffer: ?*win32.IDirectSoundBuffer = undefined;
var perf_count_frequency: i64 = 0;
var show_debug_cursor = INTERNAL;
var window_placement: win32.WINDOWPLACEMENT = undefined;
var local_stub_debug_table: debug_interface.DebugTable = if (INTERNAL) debug_interface.DebugTable{} else undefined;

const OffscreenBuffer = struct {
    info: win32.BITMAPINFO = undefined,
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
    bytes_per_pixel: i32 = BYTES_PER_PIXEL,
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
    safety_bytes: u32,
};

const SoundOutputInfo = struct {
    byte_to_lock: u32 = 0,
    bytes_to_write: u32 = 0,
    is_valid: bool = false,
    output_buffer: shared.SoundOutputBuffer,
};

const DebugTimeMarker = struct {
    output_play_cursor: std.os.windows.DWORD = 0,
    output_write_cursor: std.os.windows.DWORD = 0,
    output_location: std.os.windows.DWORD = 0,
    output_byte_count: std.os.windows.DWORD = 0,

    expected_flip_play_coursor: std.os.windows.DWORD = 0,
    flip_play_cursor: std.os.windows.DWORD = 0,
    flip_write_cursor: std.os.windows.DWORD = 0,
};

const RecordedInput = struct {
    input_stream: [*:0]shared.GameInput,
};

const ReplayBuffer = struct {
    memory_map: win32.HANDLE = undefined,
    file_handle: win32.HANDLE = undefined,
    replay_file_name: [STATE_FILE_NAME_COUNT:0]u8 = undefined,
    memory_block: ?*anyopaque = null,
};

const Win32State = struct {
    total_size: usize = 0,
    game_memory_block: ?*anyopaque = undefined,
    replay_buffers: [4]ReplayBuffer = [1]ReplayBuffer{ReplayBuffer{}} ** 4,

    recording_handle: win32.HANDLE = undefined,
    input_recording_index: u32 = 0,

    playback_handle: win32.HANDLE = undefined,
    input_playing_index: u32 = 0,

    exe_file_name: [STATE_FILE_NAME_COUNT:0]u8 = undefined,
    one_past_last_exe_file_name_slash: usize = 0,
};

const FaderState = enum {
    FadingIn,
    WaitingForShow,
    Inactive,
    FadingGame,
    FadingOut,
    WaitingForClose,
};

const Fader = struct {
    window: ?win32.HWND = null,

    alpha: f32 = 0,
    state: FaderState = undefined,

    pub fn init(self: *Fader, instance: win32.HINSTANCE) void {
        const window_class: win32.WNDCLASSW = .{
            .style = .{ .HREDRAW = 1, .VREDRAW = 1 },
            .lpfnWndProc = Fader.windowProcedure,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = instance,
            .hIcon = null,
            .hbrBackground = win32.GetStockObject(win32.BLACK_BRUSH),
            .hCursor = null,
            .lpszMenuName = null,
            .lpszClassName = win32.L("HandmadeZigFadeOutWindowClass"),
        };

        if (win32.RegisterClassW(&window_class) != 0) {
            self.window = win32.CreateWindowExW(
                .{
                    .LAYERED = 1,
                },
                window_class.lpszClassName,
                win32.L("Handmade Zig"),
                win32.WINDOW_STYLE{
                    .VISIBLE = 0,
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

            if (self.window) |fade_window| {
                toggleFullscreen(fade_window);
            }
        }
    }

    pub fn beginFadeToGame(self: *Fader) void {
        self.state = .FadingIn;
        self.alpha = 0;
    }

    pub fn beginFadeToDesktop(self: *Fader) void {
        if (self.state == .Inactive) {
            self.state = .FadingGame;
            self.alpha = 1;
        }
    }

    pub fn update(self: *Fader, delta_time: f32, game_window: win32.HWND) FaderState {
        switch (self.state) {
            .FadingIn => {
                if (self.alpha >= 1) {
                    setFadeAlpha(self.window.?, 1);

                    _ = win32.ShowWindow(game_window, win32.SW_SHOW);
                    _ = win32.InvalidateRect(game_window, null, win32.TRUE);
                    _ = win32.UpdateWindow(game_window);

                    self.state = .WaitingForShow;
                } else {
                    setFadeAlpha(self.window.?, self.alpha);
                    self.alpha += delta_time;
                }
            },
            .WaitingForShow => {
                setFadeAlpha(self.window.?, 0);
                self.state = .Inactive;
            },
            .Inactive => {
                // Nothing to do.
            },
            .FadingGame => {
                if (self.alpha >= 1) {
                    setFadeAlpha(self.window.?, 1);
                    _ = win32.ShowWindow(game_window, win32.SW_HIDE);
                    self.state = .FadingOut;
                } else {
                    setFadeAlpha(self.window.?, self.alpha);
                    self.alpha += delta_time;
                }
            },
            .FadingOut => {
                self.alpha -= delta_time;

                if (self.alpha <= 0) {
                    setFadeAlpha(self.window.?, 0);
                    self.state = .WaitingForClose;
                } else {
                    setFadeAlpha(self.window.?, self.alpha);
                }
            },
            .WaitingForClose => {
                // Nothing to do.
            },
        }

        return self.state;
    }

    fn setFadeAlpha(fade_window: win32.HWND, alpha: f32) void {
        const alpha_level: u8 = @intFromFloat(255 * alpha);

        if (alpha == 0) {
            if (win32.IsWindowVisible(fade_window) != 0) {
                _ = win32.ShowWindow(fade_window, win32.SW_HIDE);
            }
        } else {
            _ = win32.SetLayeredWindowAttributes(fade_window, 0, @intCast(alpha_level), win32.LWA_ALPHA);
            if (win32.IsWindowVisible(fade_window) == 0) {
                _ = win32.ShowWindow(fade_window, win32.SW_SHOW);
            }
        }
    }

    fn windowProcedure(
        window: win32.HWND,
        message: u32,
        w_param: win32.WPARAM,
        l_param: win32.LPARAM,
    ) callconv(std.os.windows.WINAPI) win32.LRESULT {
        var result: win32.LRESULT = 0;

        switch (message) {
            win32.WM_CLOSE => {},
            win32.WM_SETCURSOR => {
                _ = win32.SetCursor(null);
            },
            else => {
                result = win32.DefWindowProc(window, message, w_param, l_param);
            },
        }

        return result;
    }
};

pub const Game = struct {
    dll: ?win32.HINSTANCE = undefined,
    last_write_time: win32.FILETIME = undefined,
    updateAndRender: *const @TypeOf(shared.updateAndRenderStub) = undefined,
    getSoundSamples: *const @TypeOf(shared.getSoundSamplesStub) = undefined,
    debugFrameEnd: ?*const @TypeOf(shared.debugFrameEndStub) = undefined,
};

const Win32PlatformFileGroup = extern struct {
    find_handle: win32.FindFileHandle,
    find_data: win32.WIN32_FIND_DATAW,
};

const Win32PlatformFileHandle = extern struct {
    win32_handle: win32.HANDLE,
};

fn getAllFilesOfTypeBegin(file_type: shared.PlatformFileTypes) callconv(.C) shared.PlatformFileGroup {
    var result = shared.PlatformFileGroup{};
    var win32_file_group: *Win32PlatformFileGroup = undefined;

    if (win32.VirtualAlloc(
        null,
        @sizeOf(Win32PlatformFileGroup),
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    )) |space| {
        win32_file_group = @ptrCast(@alignCast(space));
    }
    result.platform = win32_file_group;

    const wildcard: [:0]const u16 = switch (file_type) {
        shared.PlatformFileTypes.AssetFile => win32.L("*.hha"),
        shared.PlatformFileTypes.SaveGameFile => win32.L("*.hhs"),
    };

    var find_data: win32.WIN32_FIND_DATAW = undefined;
    var find_handle = win32.FindFirstFileW(wildcard, &find_data);

    while (@as(*anyopaque, @ptrCast(&find_handle)) != win32.INVALID_HANDLE_VALUE) {
        result.file_count += 1;

        if (win32.FindNextFileW(find_handle, &find_data) == 0) {
            break;
        }
    }

    _ = win32.FindClose(find_handle);

    win32_file_group.find_handle = win32.FindFirstFileW(wildcard, &win32_file_group.find_data);

    return result;
}

fn getAllFilesOfTypeEnd(file_group: *shared.PlatformFileGroup) callconv(.C) void {
    const win32_file_group: *Win32PlatformFileGroup = @ptrCast(@alignCast(file_group.platform));

    _ = win32.FindClose(win32_file_group.find_handle);
    _ = win32.VirtualFree(win32_file_group, 0, win32.MEM_RELEASE);
}

fn openNextFile(file_group: *shared.PlatformFileGroup) callconv(.C) shared.PlatformFileHandle {
    var result = shared.PlatformFileHandle{};
    const win32_file_group: *Win32PlatformFileGroup = @ptrCast(@alignCast(file_group.platform));

    if (@as(*anyopaque, @ptrCast(&win32_file_group.find_handle)) != win32.INVALID_HANDLE_VALUE) {
        const file_name = win32_file_group.find_data.cFileName;

        if (win32.VirtualAlloc(
            null,
            @sizeOf(Win32PlatformFileHandle),
            win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
            win32.PAGE_READWRITE,
        )) |space| {
            const win32_handle: *Win32PlatformFileHandle = @ptrCast(@alignCast(space));
            result.platform = win32_handle;
            win32_handle.win32_handle = win32.CreateFileW(
                @ptrCast(&file_name),
                win32.FILE_GENERIC_READ,
                win32.FILE_SHARE_READ,
                null,
                win32.FILE_CREATION_DISPOSITION.OPEN_EXISTING,
                win32.FILE_FLAGS_AND_ATTRIBUTES{},
                null,
            );
            result.no_errors = (win32_handle.win32_handle != win32.INVALID_HANDLE_VALUE);

            if (win32.FindNextFileW(win32_file_group.find_handle, &win32_file_group.find_data) == 0) {
                _ = win32.FindClose(win32_file_group.find_handle);
                win32_file_group.find_handle = -1;
            }
        }
    }

    return result;
}

fn readDataFromFile(source: *shared.PlatformFileHandle, offset: u64, size: u64, dest: *anyopaque) callconv(.C) void {
    if (shared.defaultNoFileErrors(source)) {
        const handle: *Win32PlatformFileHandle = @ptrCast(@alignCast(source.platform));

        var overlapped = win32.OVERLAPPED{
            .Internal = 0,
            .InternalHigh = 0,
            .hEvent = null,
            .Anonymous = .{
                .Anonymous = .{
                    .Offset = @as(u32, @intCast((offset >> 0) & 0xFFFFFFFF)),
                    .OffsetHigh = @as(u32, @intCast((offset >> 32) & 0xFFFFFFFF)),
                },
            },
        };

        const file_size32 = shared.safeTruncateI64(@intCast(size));

        var bytes_read: u32 = undefined;
        const read_result = win32.ReadFile(
            handle.win32_handle,
            dest,
            file_size32,
            &bytes_read,
            &overlapped,
        );

        if (read_result != 0 and bytes_read == file_size32) {
            // File read successfully.
        } else {
            const error_number = win32.GetLastError();
            std.debug.print("Error loading file: {d}\n", .{ @intFromEnum(error_number) });
            fileError(source, "Read file failed.");
        }
    }
}

fn fileError(file_handle: *shared.PlatformFileHandle, message: [*:0]const u8) callconv(.C) void {
    if (INTERNAL) {
        win32.OutputDebugStringA("WIN32 FILE ERROR: ");
        win32.OutputDebugStringA(message);
        win32.OutputDebugStringA("\n");
    }

    file_handle.no_errors = false;
}

fn allocateMemory(size: shared.MemoryIndex) callconv(.C) ?*anyopaque {
    return win32.VirtualAlloc(
        null,
        size,
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    );
}

fn deallocateMemory(opt_memory: ?*anyopaque) callconv(.C) void {
    if (opt_memory) |memory| {
        _ = win32.VirtualFree(memory, 0, win32.MEM_RELEASE);
    }
}

const DebugFunctions = if (INTERNAL) struct {
    pub fn debugReadEntireFile(file_name: [*:0]const u8) callconv(.C) shared.DebugReadFileResult {
        var result = shared.DebugReadFileResult{};

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
                const file_size32 = shared.safeTruncateI64(file_size.QuadPart);

                if (win32.VirtualAlloc(
                    null,
                    file_size32,
                    win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                    win32.PAGE_READWRITE,
                )) |file_contents| {
                    var bytes_read: u32 = undefined;
                    const read_result = win32.ReadFile(
                        file_handle,
                        file_contents,
                        file_size32,
                        &bytes_read,
                        null,
                    );

                    if (read_result != 0 and bytes_read == file_size32) {
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

    pub fn debugWriteEntireFile(file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) callconv(.C) bool {
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

    pub fn debugExecuteSystemCommand(
        path: [*:0]const u8,
        command: [*:0]const u8,
        command_line: [*:0]const u8,
    ) callconv(.C) shared.DebugExecutingProcess {
        var result: shared.DebugExecutingProcess = .{};
        const h_process: *win32.HANDLE = @ptrCast(@alignCast(&result.os_handle));

        var startup_info: win32.STARTUPINFOA = .{
            .cb = @sizeOf(win32.STARTUPINFOA),
            .lpReserved = null,
            .lpDesktop = null,
            .lpTitle = null,
            .dwX = 0,
            .dwY = 0,
            .dwXSize = 0,
            .dwYSize = 0,
            .dwXCountChars = 0,
            .dwYCountChars = 0,
            .dwFillAttribute = 0,
            .dwFlags = win32.STARTUPINFOW_FLAGS{ .USESHOWWINDOW = 1 },
            .wShowWindow = 0,
            .cbReserved2 = 0,
            .lpReserved2 = null,
            .hStdInput = null,
            .hStdOutput = null,
            .hStdError = null,
        };

        var process_info: win32.PROCESS_INFORMATION = .{
            .hProcess = null,
            .hThread = null,
            .dwProcessId = 0,
            .dwThreadId = 0,
        };

        if (win32.CreateProcessA(
            command,
            @constCast(command_line),
            null,
            null,
            win32.FALSE,
            win32.PROCESS_CREATION_FLAGS{},
            null,
            path,
            &startup_info,
            &process_info,
        ) != 0) {
            if (process_info.hProcess) |process_handle| {
                std.debug.assert(@sizeOf(u64) >= @sizeOf(win32.HANDLE));
                h_process.* = process_handle;
            }
        } else {
            h_process.* = win32.INVALID_HANDLE_VALUE;
            std.debug.print("Error executing system command: {d}\n", .{@intFromEnum(win32.GetLastError())});
        }

        return result;
    }

    pub fn debugGetProcessState(process: shared.DebugExecutingProcess) callconv(.C) shared.DebugExecutingProcessState {
        var result: shared.DebugExecutingProcessState = .{};
        const h_process: *const win32.HANDLE = @ptrCast(&process.os_handle);

        if (h_process.* != win32.INVALID_HANDLE_VALUE) {
            result.started_successfully = true;

            if (win32.WaitForSingleObject(h_process.*, 0) == @intFromEnum(win32.WAIT_OBJECT_0)) {
                var exit_code: u32 = undefined;
                _ = win32.GetExitCodeProcess(h_process.*, &exit_code);
                _ = win32.CloseHandle(h_process.*);
            } else {
                result.is_running = true;
            }
        }

        return result;
    }

    pub fn debugFreeFileMemory(memory: *anyopaque) callconv(.C) void {
        _ = win32.VirtualFree(memory, 0, win32.MEM_RELEASE);
    }
} else struct {
    pub fn debugFreeFileMemory(_: *anyopaque) callconv(.C) void {}
    pub fn debugReadEntireFile(_: [*:0]const u8) callconv(.C) shared.DebugReadFileResult {
        return undefined;
    }
    pub fn debugWriteEntireFile(_: [*:0]const u8, _: u32, _: *anyopaque) callconv(.C) bool {
        return false;
    }
    pub fn debugExecuteSystemCommand(
        _: [*:0]const u8,
        _: [*:0]const u8,
        _: [*:0]const u8,
    ) callconv(.C) shared.DebugExecutingProcess {
        return undefined;
    }
    pub fn debugGetProcessState(_: shared.DebugExecutingProcess) callconv(.C) shared.DebugExecutingProcessState {
        return undefined;
    }
};

inline fn getLastWriteTime(file_name: [*:0]const u8) win32.FILETIME {
    var last_write_time = win32.FILETIME{
        .dwLowDateTime = 0,
        .dwHighDateTime = 0,
    };

    var find_data: win32.WIN32_FIND_DATAA = undefined;
    const find_handle = win32.FindFirstFileA(file_name, &find_data);
    if (find_handle != 0) {
        last_write_time = find_data.ftLastWriteTime;
        _ = win32.FindClose(find_handle);
    }

    return last_write_time;
}

fn loadGameCode(source_dll_name: [*:0]const u8, temp_dll_name: [*:0]const u8) Game {
    var result = Game{};

    _ = win32.CopyFileA(source_dll_name, temp_dll_name, win32.FALSE);

    result.last_write_time = getLastWriteTime(source_dll_name);
    result.dll = win32.LoadLibraryA(temp_dll_name);
    result.updateAndRender = shared.updateAndRenderStub;
    result.getSoundSamples = shared.getSoundSamplesStub;
    result.debugFrameEnd = null;

    if (result.dll) |library| {
        if (win32.GetProcAddress(library, "updateAndRender")) |procedure| {
            result.updateAndRender = @as(@TypeOf(result.updateAndRender), @ptrCast(procedure));
        }

        if (win32.GetProcAddress(library, "getSoundSamples")) |procedure| {
            result.getSoundSamples = @as(@TypeOf(result.getSoundSamples), @ptrCast(procedure));
        }

        if (win32.GetProcAddress(library, "debugFrameEnd")) |procedure| {
            result.debugFrameEnd = @as(@TypeOf(result.debugFrameEnd), @ptrCast(procedure));
        }
    }

    return result;
}

fn unloadGameCode(game: *Game) void {
    if (game.dll) |dll| {
        _ = win32.FreeLibrary(dll);
        game.dll = undefined;
    }

    game.updateAndRender = shared.updateAndRenderStub;
    game.getSoundSamples = shared.getSoundSamplesStub;
    game.debugFrameEnd = null;
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

fn processMouseInput(old_input: *shared.GameInput, new_input: *shared.GameInput, window: win32.HWND) void {
    var mouse_point: win32.POINT = undefined;
    if (win32.GetCursorPos(&mouse_point) == win32.TRUE) {
        _ = win32.ScreenToClient(window, &mouse_point);

        const dim = calculateGameOffset(window);
        const window_dimension = getWindowDimension(window);
        new_input.mouse_x = @as(f32, @floatFromInt(mouse_point.x)) - @as(f32, @floatFromInt(dim.offset_x));
        new_input.mouse_y = @as(f32, @floatFromInt((window_dimension.height - 1) - mouse_point.y)) - @as(f32, @floatFromInt(dim.offset_y));
        new_input.mouse_z = 0; // TODO: Add mouse wheel support.
        new_input.shift_down = win32.GetKeyState(@intFromEnum(win32.VK_SHIFT)) & (1 << 7) != 0;
        new_input.alt_down = win32.GetKeyState(@intFromEnum(win32.VK_MENU)) & (1 << 7) != 0;
        new_input.control_down = win32.GetKeyState(@intFromEnum(win32.VK_CONTROL)) & (1 << 7) != 0;
    }

    const win_button_ids = [_]win32.VIRTUAL_KEY{
        win32.VK_LBUTTON,
        win32.VK_MBUTTON,
        win32.VK_RBUTTON,
        win32.VK_XBUTTON1,
        win32.VK_XBUTTON2,
    };

    var button_index: u32 = 0;
    while (button_index < old_input.mouse_buttons.len) : (button_index += 1) {
        new_input.mouse_buttons[button_index] = old_input.mouse_buttons[button_index];
        new_input.mouse_buttons[button_index].half_transitions = 0;

        processKeyboardInputMessage(
            &new_input.mouse_buttons[button_index],
            win32.GetKeyState(@intFromEnum(win_button_ids[button_index])) & (1 << 7) != 0,
        );
    }
}

fn processXInput(old_input: *shared.GameInput, new_input: *shared.GameInput) void {
    var dwResult: isize = 0;
    var controller_index: u8 = 0;

    var max_controller_count = win32.XUSER_MAX_COUNT;
    if (max_controller_count > (shared.MAX_CONTROLLER_COUNT - 1)) {
        max_controller_count = shared.MAX_CONTROLLER_COUNT;
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
            new_controller.is_connected = true;
            new_controller.is_analog = old_controller.is_analog;

            // Left stick X.
            new_controller.stick_average_x = processXInputStick(pad.sThumbLX, win32.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);

            // Left stick Y.
            new_controller.stick_average_y = processXInputStick(pad.sThumbLY, win32.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);

            if (new_controller.stick_average_x != 0.0 or new_controller.stick_average_y != 0.0) {
                new_controller.is_analog = true;
            }

            // D-pad overrides the stick value.
            if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_UP) > 0) {
                new_controller.stick_average_y = 1.0;
                new_controller.is_analog = false;
            } else if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_DOWN) > 0) {
                new_controller.stick_average_y = -1.0;
                new_controller.is_analog = false;
            }
            if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_LEFT) > 0) {
                new_controller.stick_average_x = -1.0;
                new_controller.is_analog = false;
            } else if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_RIGHT) > 0) {
                new_controller.stick_average_x = 1.0;
                new_controller.is_analog = false;
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

fn processXInputDigitalButton(
    x_input_button_state: u32,
    button_bit: u32,
    old_state: *shared.ControllerButtonState,
    new_state: *shared.ControllerButtonState,
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

fn processKeyboardInput(message: win32.MSG, keyboard_controller: *shared.ControllerInput, state: *Win32State) void {
    const vk_code = message.wParam;
    const alt_was_down: bool = if ((message.lParam & (1 << 29) != 0)) true else false;
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
                processKeyboardInputMessage(&keyboard_controller.action_right, is_down);
            },
            @intFromEnum(win32.VK_SPACE) => {
                processKeyboardInputMessage(&keyboard_controller.start_button, is_down);
            },
            @intFromEnum(win32.VK_ESCAPE) => {
                processKeyboardInputMessage(&keyboard_controller.back_button, is_down);
            },
            @intFromEnum(win32.VK_F4) => {
                if (is_down and alt_was_down) {
                    running = false;
                }
            },
            @intFromEnum(win32.VK_RETURN) => {
                if (is_down and alt_was_down) {
                    if (message.hwnd) |window| {
                        toggleFullscreen(window);
                    }
                }
            },
            'L' => {
                if (is_down) {
                    if (state.input_recording_index == 0 and state.input_playing_index == 0) {
                        beginRecordingInput(state, 1);
                    } else if (state.input_recording_index > 0) {
                        endRecordingInput(state);
                        beginInputPlayback(state, 1);
                    } else if (state.input_playing_index > 0) {
                        endInputPlayback(state);
                    }
                }
            },
            else => {},
        }
    }
}

fn processKeyboardInputMessage(
    new_state: *shared.ControllerButtonState,
    is_down: bool,
) void {
    if (new_state.ended_down != is_down) {
        new_state.ended_down = is_down;
        new_state.half_transitions += 1;
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
                        .dwFlags = win32.DSBCAPS_GETCURRENTPOSITION2,
                        .dwBufferBytes = buffer_size,
                        .dwReserved = 0,
                        .lpwfxFormat = &wave_format,
                        .guid3DAlgorithm = win32.Guid.initString("00000000-0000-0000-0000-000000000000"),
                    };

                    if (INTERNAL) {
                        buffer_description.dwFlags |= win32.DSBCAPS_GLOBALFOCUS;
                    }

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

fn getWindowDimension(window: win32.HWND) WindowDimension {
    var client_rect: win32.RECT = undefined;
    _ = win32.GetClientRect(window, &client_rect);

    return WindowDimension{
        .width = client_rect.right - client_rect.left,
        .height = client_rect.bottom - client_rect.top,
    };
}

fn resizeDIBSection(buffer: *OffscreenBuffer, width: i32, height: i32) void {
    if (buffer.memory) |memory| {
        _ = win32.VirtualFree(memory, 0, win32.MEM_RELEASE);
    }

    buffer.width = width;
    buffer.height = height;

    buffer.info = win32.BITMAPINFO{
        .bmiHeader = win32.BITMAPINFOHEADER{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = buffer.width,
            .biHeight = buffer.height,
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

    buffer.pitch = shared.align16(@intCast(buffer.width * BYTES_PER_PIXEL));
    const bitmap_memory_size: usize = @intCast((@as(i32, @intCast(buffer.pitch)) * buffer.height) + 1);
    buffer.memory = win32.VirtualAlloc(null, bitmap_memory_size, win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 }, win32.PAGE_READWRITE);
}

fn getGameBuffer() shared.OffscreenBuffer {
    return shared.OffscreenBuffer{
        .memory = back_buffer.memory,
        .width = back_buffer.width,
        .height = back_buffer.height,
        .pitch = back_buffer.pitch,
    };
}

const GameBufferDimensions = struct {
    blit_height: i32,
    blit_width: i32,
    offset_x: i32,
    offset_y: i32,
};

fn calculateGameOffset(window: win32.HWND) GameBufferDimensions {
    const win_dim = getWindowDimension(window);
    const window_width = win_dim.width;
    const window_height = win_dim.height;

    // Double size if we have space for it.
    const should_double_size = window_width >= back_buffer.width * 2 and window_height >= back_buffer.height * 2;
    const blit_width = if (should_double_size) back_buffer.width * 2 else back_buffer.width;
    const blit_height = if (should_double_size) back_buffer.height * 2 else back_buffer.height;

    return GameBufferDimensions{
        .blit_width = blit_width,
        .blit_height = blit_height,
        .offset_x = @divFloor((window_width - blit_width), 2),
        .offset_y = @divFloor((window_height - blit_height), 2),
    };
}

fn displayBufferInWindow(buffer: *OffscreenBuffer, device_context: ?win32.HDC, window: win32.HWND, window_width: i32, window_height: i32,) void {
    const dim = calculateGameOffset(window);

    // Clear areas outside of our drawing area.
    _ = win32.PatBlt(device_context, 0, 0, window_width, dim.offset_y, win32.BLACKNESS);
    _ = win32.PatBlt(device_context, 0, dim.offset_y + dim.blit_height, window_width, window_height, win32.BLACKNESS);
    _ = win32.PatBlt(device_context, 0, 0, dim.offset_x, window_height, win32.BLACKNESS);
    _ = win32.PatBlt(device_context, dim.offset_x + dim.blit_width, 0, window_width, window_height, win32.BLACKNESS);

    _ = win32.StretchDIBits(
        device_context,
        dim.offset_x,
        dim.offset_y,
        dim.blit_width,
        dim.blit_height,
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
        win32.WM_QUIT, win32.WM_CLOSE, win32.WM_DESTROY => {
            running = false;
        },
        win32.WM_SETCURSOR => {
            if (show_debug_cursor) {
                result = win32.DefWindowProc(window, message, w_param, l_param);
            } else {
                _ = win32.SetCursor(null);
            }
        },
        win32.WM_SIZE => {},
        win32.WM_ACTIVATEAPP => {
            if (INTERNAL) {
                const active = (w_param != 0);
                _ = win32.SetLayeredWindowAttributes(window, 0, if (active) DEBUG_WINDOW_ACTIVE_OPACITY else DEBUG_WINDOW_INACTIVE_OPACITY, win32.LWA_ALPHA);
            }
            win32.OutputDebugStringA("WM_ACTIVATEAPP\n");
        },
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const opt_device_context: ?win32.HDC = win32.BeginPaint(window, &paint);
            if (opt_device_context) |device_context| {
                const window_dimension = getWindowDimension(window);
                displayBufferInWindow(&back_buffer, device_context, window, window_dimension.width, window_dimension.height);
            }
            _ = win32.EndPaint(window, &paint);
        },
        win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYDOWN, win32.WM_KEYUP => {
            // No keyboard input should come from anywhere other than the main loop.
            std.debug.assert(false);
        },
        else => {
            result = win32.DefWindowProc(window, message, w_param, l_param);
        },
    }

    return result;
}

fn toggleFullscreen(window: win32.HWND) void {
    const style = win32.GetWindowLong(window, win32.GWL_STYLE);

    if ((style & @as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW))) != 0) {
        var monitor_info: win32.MONITORINFO = undefined;
        monitor_info.cbSize = @sizeOf(win32.MONITORINFO);

        if (win32.GetWindowPlacement(window, &window_placement) != 0 and
            win32.GetMonitorInfo(win32.MonitorFromWindow(window, win32.MONITOR_DEFAULTTOPRIMARY), &monitor_info) != 0)
        {
            // Set fullscreen.
            _ = win32.SetWindowLong(window, win32.GWL_STYLE, style & ~@as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW)));
            _ = win32.SetWindowPos(
                window,
                if (INTERNAL or DEBUG) win32.HWND_NOTOPMOST else win32.HWND_TOPMOST,
                monitor_info.rcMonitor.left,
                monitor_info.rcMonitor.top,
                monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
                monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
                win32.SET_WINDOW_POS_FLAGS{ .NOOWNERZORDER = 1, .DRAWFRAME = 1 },
            );
        }
    } else {
        // Set windowed.
        _ = win32.SetWindowLong(window, win32.GWL_STYLE, style | @as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW)));
        _ = win32.SetWindowPlacement(window, &window_placement);
        _ = win32.SetWindowPos(
            window,
            null,
            0,
            0,
            0,
            0,
            win32.SET_WINDOW_POS_FLAGS{ .NOMOVE = 1, .NOSIZE = 1, .NOZORDER = 1, .NOOWNERZORDER = 1, .DRAWFRAME = 1 },
        );
    }
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
    const limited_top = if (top <= 0) 0 else top;
    const limited_bottom = if (bottom > buffer.height) buffer.height else bottom;

    if (x >= 0 and x < buffer.width) {
        var pixel: [*]u8 = @ptrCast(buffer.memory);
        pixel += @as(u32, @intCast((x * BYTES_PER_PIXEL) + (limited_top * @as(i32, @intCast(buffer.pitch)))));

        var y = limited_top;
        while (y < limited_bottom) : (y += 1) {
            const p = @as(*u32, @ptrCast(@alignCast(pixel)));
            p.* = color;
            pixel += buffer.pitch;
        }
    }
}

fn debugDrawSoundBufferMarker(
    buffer: *OffscreenBuffer,
    value: std.os.windows.DWORD,
    c: f32,
    pad_x: i32,
    top: i32,
    bottom: i32,
    color: u32,
) void {
    const x: i32 = pad_x + @as(i32, @intFromFloat(c * @as(f32, @floatFromInt(value))));
    debugDrawVertical(buffer, x, top, bottom, color);
}

fn debugSyncDisplay(
    buffer: *OffscreenBuffer,
    markers: []DebugTimeMarker,
    current_marker_index: u32,
    sound_output: *SoundOutput,
    seconds_per_frame: f32,
) void {
    _ = seconds_per_frame;

    const pad_x = 16;
    const pad_y = 16;
    const line_height = 32;
    const c: f32 =
        @as(f32, @floatFromInt(buffer.width - (2 * pad_x))) /
        @as(f32, @floatFromInt(sound_output.secondary_buffer_size));

    for (markers, 0..) |marker, marker_index| {
        // TODO: How come these two values can be bigger that secondary_buffer_size?
        // std.debug.assert(marker.output_play_cursor < sound_output.secondary_buffer_size);
        // std.debug.assert(marker.output_write_cursor < sound_output.secondary_buffer_size);
        std.debug.assert(marker.output_location < sound_output.secondary_buffer_size);
        std.debug.assert(marker.output_byte_count < sound_output.secondary_buffer_size);
        std.debug.assert(marker.flip_play_cursor < sound_output.secondary_buffer_size);
        std.debug.assert(marker.flip_write_cursor < sound_output.secondary_buffer_size);

        const play_color: u32 = 0xFFFFFFFF;
        const write_color: u32 = 0xFFFF0000;
        const expected_flip_color: u32 = 0xFFFFFF00;
        const play_window_color: u32 = 0xFFFF00FF;

        var top: i32 = pad_y;
        var bottom: i32 = pad_y + line_height;

        if (marker_index == current_marker_index) {
            top += line_height + pad_y;
            bottom += line_height + pad_y;

            const first_top = top;

            debugDrawSoundBufferMarker(buffer, marker.output_play_cursor, c, pad_x, top, bottom, play_color);
            debugDrawSoundBufferMarker(buffer, marker.output_write_cursor, c, pad_x, top, bottom, write_color);

            top += line_height + pad_y;
            bottom += line_height + pad_y;

            debugDrawSoundBufferMarker(buffer, marker.output_location, c, pad_x, top, bottom, play_color);
            debugDrawSoundBufferMarker(buffer, marker.output_location + marker.output_byte_count, c, pad_x, top, bottom, write_color);

            top += line_height + pad_y;
            bottom += line_height + pad_y;

            debugDrawSoundBufferMarker(buffer, marker.expected_flip_play_coursor, c, pad_x, first_top, bottom, expected_flip_color);
        }

        debugDrawSoundBufferMarker(buffer, marker.flip_play_cursor, c, pad_x, top, bottom, play_color);
        debugDrawSoundBufferMarker(buffer, marker.flip_play_cursor + (480 * sound_output.bytes_per_sample), c, pad_x, top, bottom, play_window_color);
        debugDrawSoundBufferMarker(buffer, marker.flip_write_cursor, c, pad_x, top, bottom, write_color);
    }
}

fn catStrings(
    source_a: []const u8,
    source_b: []const u8,
    dest: [:0]u8,
) void {
    var index: usize = 0;
    for (source_a) |a| {
        dest[index] = a;
        index += 1;
    }

    for (source_b) |b| {
        dest[index] = b;
        index += 1;
    }
}

fn getExeFileName(state: *Win32State) void {
    state.exe_file_name = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;

    _ = win32.GetModuleFileNameA(null, &state.exe_file_name, @sizeOf(u8) * STATE_FILE_NAME_COUNT);

    state.one_past_last_exe_file_name_slash = 0;
    for (state.exe_file_name, 0..) |char, index| {
        if (char == '\\') {
            state.one_past_last_exe_file_name_slash = index + 1;
        }
    }
}

fn buildExePathFileName(state: *Win32State, file_name: []const u8, dest: [:0]u8) void {
    catStrings(
        state.exe_file_name[0..state.one_past_last_exe_file_name_slash],
        file_name,
        dest,
    );
}

fn getInputFileLocation(state: *Win32State, is_input: bool, slot_index: u32, dest: [:0]u8) void {
    var temp: [64]u8 = undefined;
    var arglist = .{ slot_index, if (is_input) "input" else "state" };
    _ = win32.wvsprintfA(@ptrCast(&temp), "loop_edit_%d_%s.hmi", @ptrCast(&arglist));
    buildExePathFileName(state, &temp, dest);
}

fn getReplayBuffer(state: *Win32State, index: u32) *ReplayBuffer {
    std.debug.assert(index < state.replay_buffers.len);
    return &state.replay_buffers[index];
}

fn beginRecordingInput(state: *Win32State, input_recording_index: u32) void {
    const replay_buffer = getReplayBuffer(state, input_recording_index);
    if (replay_buffer.memory_block != null) {
        var file_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
        getInputFileLocation(state, true, @intCast(input_recording_index), &file_path);
        state.recording_handle = win32.CreateFileA(
            &file_path,
            win32.FILE_GENERIC_WRITE,
            win32.FILE_SHARE_NONE,
            null,
            win32.FILE_CREATION_DISPOSITION.CREATE_ALWAYS,
            win32.FILE_FLAGS_AND_ATTRIBUTES{},
            null,
        );
        state.input_recording_index = input_recording_index;

        const bytes_to_write: u32 = @intCast(state.total_size);
        std.debug.assert(state.total_size == bytes_to_write);

        @memcpy(
            @as([*]u8, @ptrCast(replay_buffer.memory_block))[0..state.total_size],
            @as([*]u8, @ptrCast(state.game_memory_block))[0..state.total_size],
        );
    }
}

fn recordInput(state: *Win32State, new_input: *shared.GameInput) void {
    var bytes_written: u32 = undefined;
    _ = win32.WriteFile(state.recording_handle, new_input, @sizeOf(@TypeOf(new_input.*)), &bytes_written, null);
}

fn endRecordingInput(state: *Win32State) void {
    _ = win32.CloseHandle(state.recording_handle);
    state.input_recording_index = 0;
    state.recording_handle = undefined;
}

fn beginInputPlayback(state: *Win32State, input_playing_index: u32) void {
    const replay_buffer = getReplayBuffer(state, input_playing_index);
    if (replay_buffer.memory_block != null) {
        var file_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
        getInputFileLocation(state, true, @intCast(input_playing_index), &file_path);
        state.playback_handle = win32.CreateFileA(
            &file_path,
            win32.FILE_GENERIC_READ,
            win32.FILE_SHARE_NONE,
            null,
            win32.FILE_CREATION_DISPOSITION.OPEN_EXISTING,
            win32.FILE_FLAGS_AND_ATTRIBUTES{},
            null,
        );

        state.input_playing_index = input_playing_index;

        const bytes_to_read: u32 = @intCast(state.total_size);
        std.debug.assert(state.total_size == bytes_to_read);

        @memcpy(
            @as([*]u8, @ptrCast(state.game_memory_block))[0..state.total_size],
            @as([*]u8, @ptrCast(replay_buffer.memory_block))[0..state.total_size],
        );
    }
}

fn playbackInput(state: *Win32State, new_input: *shared.GameInput) void {
    var bytes_read: u32 = undefined;
    if (win32.ReadFile(state.playback_handle, new_input, @sizeOf(@TypeOf(new_input.*)), &bytes_read, null) == 0 or bytes_read == 0) {
        const playing_index = state.input_playing_index;
        endInputPlayback(state);
        beginInputPlayback(state, playing_index);

        _ = win32.ReadFile(state.playback_handle, new_input, @sizeOf(@TypeOf(new_input.*)), &bytes_read, null);
    }
}

fn endInputPlayback(state: *Win32State) void {
    _ = win32.CloseHandle(state.playback_handle);
    state.input_playing_index = 0;
    state.playback_handle = undefined;
}

fn makeQueue(queue: *shared.PlatformWorkQueue, thread_count: i32) void {
    const initial_count = 0;
    const opt_semaphore_handle = win32.CreateSemaphoreEx(
        null,
        initial_count,
        thread_count,
        null,
        0,
        0x1F0003, // win32.SEMAPHORE_ALL_ACCESS,
    );

    if (opt_semaphore_handle) |semaphore_handle| {
        queue.semaphore_handle = semaphore_handle;

        var thread_index: u32 = 0;
        while (thread_index < thread_count) : (thread_index += 1) {
            var thread_id: std.os.windows.DWORD = undefined;
            const thread_handle = win32.CreateThread(
                null,
                0,
                threadProc,
                @ptrCast(@constCast(queue)),
                win32.THREAD_CREATE_RUN_IMMEDIATELY,
                &thread_id,
            );

            _ = win32.CloseHandle(thread_handle);
        }
    }
}

pub fn addQueueEntry(
    queue: *shared.PlatformWorkQueue,
    callback: shared.PlatformWorkQueueCallback,
    data: *anyopaque,
) callconv(.C) void {
    const original_next_entry_to_write = @atomicLoad(u32, &queue.next_entry_to_write, .acquire);
    const original_next_entry_to_read = @atomicLoad(u32, &queue.next_entry_to_read, .acquire);
    const new_next_entry_to_write: u32 = @mod(original_next_entry_to_write + 1, @as(u32, @intCast(queue.entries.len)));
    std.debug.assert(new_next_entry_to_write != original_next_entry_to_read);

    var entry = &queue.entries[original_next_entry_to_write];
    entry.data = data;
    entry.callback = callback;
    _ = @atomicRmw(u32, &queue.completion_goal, .Add, 1, .monotonic);

    @atomicStore(u32, &queue.next_entry_to_write, new_next_entry_to_write, .release);
    _ = win32.ReleaseSemaphore(queue.semaphore_handle, 1, null);
}

pub fn completeAllQueuedWork(queue: *shared.PlatformWorkQueue) callconv(.C) void {
    while (@atomicLoad(u32, &queue.completion_goal, .acquire) != @atomicLoad(u32, &queue.completion_count, .acquire)) {
        _ = doNextWorkQueueEntry(queue);
    }

    @atomicStore(u32, &queue.completion_goal, 0, .release);
    @atomicStore(u32, &queue.completion_count, 0, .release);
}

pub fn doNextWorkQueueEntry(queue: *shared.PlatformWorkQueue) bool {
    var should_wait = false;

    const original_next_entry_to_read = @atomicLoad(u32, &queue.next_entry_to_read, .acquire);
    const new_next_entry_to_read: u32 = @mod(original_next_entry_to_read + 1, @as(u32, @intCast(queue.entries.len)));
    if (original_next_entry_to_read != @atomicLoad(u32, &queue.next_entry_to_write, .acquire)) {
        if (@cmpxchgStrong(
            u32,
            &queue.next_entry_to_read,
            original_next_entry_to_read,
            new_next_entry_to_read,
            .seq_cst,
            .seq_cst,
        ) == null) {
            const entry = &queue.entries[original_next_entry_to_read];
            entry.callback(queue, entry.data);
            _ = @atomicRmw(u32, &queue.completion_count, .Add, 1, .monotonic);
        }
    } else {
        should_wait = true;
    }

    return should_wait;
}

fn threadProc(lp_parameter: ?*anyopaque) callconv(.C) u32 {
    if (lp_parameter) |parameter| {
        const queue: *shared.PlatformWorkQueue = @ptrCast(@alignCast(parameter));

        while (true) {
            if (doNextWorkQueueEntry(queue)) {
                _ = win32.WaitForSingleObjectEx(queue.semaphore_handle, std.math.maxInt(u32), 0);
            }
        }
    }

    return 0;
}

fn doWorkerWork(queue: *shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;

    var buffer: [256]u8 = undefined;
    const slice = std.fmt.bufPrintZ(&buffer, "Thread {d}: {s}\n", .{
        win32.GetCurrentThreadId(),
        @as([*:0]const u8, @ptrCast(data)),
    }) catch "";

    win32.OutputDebugStringA(@ptrCast(slice.ptr));
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

    if (INTERNAL) {
        shared.global_debug_table = &local_stub_debug_table;
    }

    var state = Win32State{};
    getExeFileName(&state);

    var high_priority_queue = shared.PlatformWorkQueue{};
    makeQueue(&high_priority_queue, 6);
    var low_priority_queue = shared.PlatformWorkQueue{};
    makeQueue(&low_priority_queue, 2);

    if (false) {
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A0")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A1")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A2")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A3")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A4")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A5")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A6")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A7")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A8")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String A9")));

        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B0")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B1")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B2")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B3")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B4")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B5")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B6")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B7")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B8")));
        addQueueEntry(&high_priority_queue, &doWorkerWork, @ptrCast(@constCast("String B9")));

        completeAllQueuedWork(&high_priority_queue);
    }

    var source_dll_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
    buildExePathFileName(&state, "handmade.dll", &source_dll_path);
    var temp_dll_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
    buildExePathFileName(&state, "handmade_temp.dll", &temp_dll_path);

    var performance_frequency: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&performance_frequency);
    perf_count_frequency = performance_frequency.QuadPart;

    // Set the Windows schedular granularity so that our Sleep() call can be more grannular.
    const desired_scheduler_ms = 1;
    const sleep_is_grannular = win32.timeBeginPeriod(desired_scheduler_ms) == win32.TIMERR_NOERROR;

    loadXInput();

    var fader: Fader = .{};
    fader.init(instance.?);

    resizeDIBSection(&back_buffer, WIDTH, HEIGHT);
    var platform = shared.Platform{
        .addQueueEntry = addQueueEntry,
        .completeAllQueuedWork = completeAllQueuedWork,

        .getAllFilesOfTypeBegin = getAllFilesOfTypeBegin,
        .getAllFilesOfTypeEnd = getAllFilesOfTypeEnd,
        .openNextFile = openNextFile,
        .readDataFromFile = readDataFromFile,
        .fileError = fileError,

        .allocateMemory = allocateMemory,
        .deallocateMemory = deallocateMemory,
    };

    if (INTERNAL) {
        platform.debugFreeFileMemory = DebugFunctions.debugFreeFileMemory;
        platform.debugReadEntireFile = DebugFunctions.debugReadEntireFile;
        platform.debugWriteEntireFile = DebugFunctions.debugWriteEntireFile;
        platform.debugExecuteSystemCommand = DebugFunctions.debugExecuteSystemCommand;
        platform.debugGetProcessState = DebugFunctions.debugGetProcessState;
    }

    const window_class: win32.WNDCLASSW = .{
        .style = .{ .HREDRAW = 1, .VREDRAW = 1 },
        .lpfnWndProc = windowProcedure,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .hbrBackground = win32.GetStockObject(win32.BLACK_BRUSH),
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeZigWindowClass"),
    };

    if (win32.RegisterClassW(&window_class) != 0) {
        const opt_window_handle: ?win32.HWND = win32.CreateWindowExW(
            .{
                // .TOPMOST = if (INTERNAL) 1 else 0,
                // .LAYERED = if (INTERNAL) 1 else 0,
            },
            window_class.lpszClassName,
            win32.L("Handmade Zig"),
            win32.WINDOW_STYLE{
                .VISIBLE = 0,
                .TABSTOP = 1,
                .GROUP = 1,
                .THICKFRAME = 1,
                .SYSMENU = 1,
                .DLGFRAME = 1,
                .BORDER = 1,
            },
            if (INTERNAL) DEBUG_WINDOW_POS_X else win32.CW_USEDEFAULT,
            if (INTERNAL) DEBUG_WINDOW_POS_Y else win32.CW_USEDEFAULT,
            if (INTERNAL) DEBUG_WINDOW_WIDTH else WIDTH + WINDOW_DECORATION_WIDTH,
            if (INTERNAL) DEBUG_WINDOW_HEIGHT else HEIGHT + WINDOW_DECORATION_HEIGHT,
            null,
            null,
            instance,
            null,
        );

        if (opt_window_handle) |window_handle| {
            toggleFullscreen(window_handle);

            if (INTERNAL) {
                _ = win32.SetLayeredWindowAttributes(window_handle, 0, DEBUG_WINDOW_ACTIVE_OPACITY, win32.LWA_ALPHA);
            }

            var monitor_refresh_hz: i32 = 60;
            const device_context = win32.GetDC(window_handle);
            const device_refresh_rate = win32.GetDeviceCaps(device_context, win32.VREFRESH);
            if (device_refresh_rate > 0) {
                monitor_refresh_hz = device_refresh_rate;
            }

            const game_update_hz: f32 = @as(f32, @floatFromInt(monitor_refresh_hz)) / 2.0;
            const target_seconds_per_frame: f32 = 1.0 / game_update_hz;

            var sound_output = SoundOutput{
                .samples_per_second = 48000,
                .bytes_per_sample = @sizeOf(i16) * 2,
                .secondary_buffer_size = 0,
                .running_sample_index = 0,
                .safety_bytes = 0,
            };

            sound_output.secondary_buffer_size = sound_output.samples_per_second * sound_output.bytes_per_sample;
            sound_output.safety_bytes = @intFromFloat(@as(f32, @floatFromInt(sound_output.secondary_buffer_size)) / game_update_hz / 2.0);
            var sound_output_info = SoundOutputInfo{ .output_buffer = undefined };

            const max_possible_overrun = 2 * 8 * @sizeOf(u16);
            const samples: ?[*]i16 = @ptrCast(@alignCast(win32.VirtualAlloc(
                null,
                sound_output.secondary_buffer_size + max_possible_overrun,
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            )));

            const debug_time_marker_index: u32 = 0;
            var debug_time_markers: [DEBUG_TIME_MARKER_COUNT]DebugTimeMarker = [1]DebugTimeMarker{DebugTimeMarker{}} ** DEBUG_TIME_MARKER_COUNT;

            initDirectSound(window_handle, sound_output.samples_per_second, sound_output.secondary_buffer_size);
            if (opt_secondary_buffer) |secondary_buffer| {
                clearSoundBuffer(&sound_output, secondary_buffer);
                _ = secondary_buffer.vtable.Play(secondary_buffer, 0, 0, win32.DSBPLAY_LOOPING);
            }

            var game_memory: shared.Memory = shared.Memory{
                .permanent_storage_size = shared.megabytes(256),
                .permanent_storage = null,
                .transient_storage_size = shared.gigabytes(1),
                .transient_storage = null,
                .debug_storage_size = shared.megabytes(64),
                .debug_storage = null,
                .high_priority_queue = &high_priority_queue,
                .low_priority_queue = &low_priority_queue,
            };

            state.total_size = game_memory.permanent_storage_size + game_memory.transient_storage_size + game_memory.debug_storage_size;
            const base_address = if (INTERNAL) @as(*u8, @ptrFromInt(shared.terabytes(2))) else null;
            state.game_memory_block = win32.VirtualAlloc(
                base_address,
                state.total_size,
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            );

            if (state.game_memory_block) |memory_block| {
                game_memory.permanent_storage = @ptrCast(memory_block);
                game_memory.transient_storage = @as([*]void, @ptrCast(memory_block)) + game_memory.permanent_storage_size;
                game_memory.debug_storage = game_memory.transient_storage.? + game_memory.transient_storage_size;
            }

            for (0..state.replay_buffers.len) |index| {
                var buffer = &state.replay_buffers[index];

                getInputFileLocation(&state, false, @intCast(index + 1), &buffer.replay_file_name);
                const generic_read_write = win32.FILE_ACCESS_FLAGS{
                    .FILE_READ_DATA = 1,
                    .FILE_READ_EA = 1,
                    .FILE_READ_ATTRIBUTES = 1,
                    .FILE_WRITE_DATA = 1,
                    .FILE_APPEND_DATA = 1,
                    .FILE_WRITE_EA = 1,
                    .FILE_WRITE_ATTRIBUTES = 1,
                    .READ_CONTROL = 1,
                    .SYNCHRONIZE = 1,
                };
                buffer.file_handle = win32.CreateFileA(
                    &buffer.replay_file_name,
                    generic_read_write,
                    win32.FILE_SHARE_NONE,
                    null,
                    win32.FILE_CREATION_DISPOSITION.CREATE_ALWAYS,
                    win32.FILE_FLAGS_AND_ATTRIBUTES{},
                    null,
                );

                const max_size_high: std.os.windows.DWORD = @intCast(state.total_size >> 32);
                const max_size_low: std.os.windows.DWORD = @intCast(state.total_size & 0xFFFFFFFF);
                const opt_memory_map = win32.CreateFileMappingA(
                    buffer.file_handle,
                    null,
                    win32.PAGE_READWRITE,
                    max_size_high,
                    max_size_low,
                    null,
                );
                if (opt_memory_map) |memory_map| {
                    buffer.memory_map = memory_map;
                    buffer.memory_block = win32.MapViewOfFileEx(
                        buffer.memory_map,
                        win32.FILE_MAP_ALL_ACCESS,
                        0,
                        0,
                        state.total_size,
                        null,
                    );
                }
            }

            if (samples != null and game_memory.permanent_storage != null and game_memory.transient_storage != null) {
                var game_input = [2]shared.GameInput{
                    shared.GameInput{
                        .frame_delta_time = target_seconds_per_frame,
                    },
                    shared.GameInput{
                        .frame_delta_time = target_seconds_per_frame,
                    },
                };
                var new_input = &game_input[0];
                var old_input = &game_input[1];

                // Initialize timing.
                var last_counter: win32.LARGE_INTEGER = getWallClock();
                var flip_wall_clock: win32.LARGE_INTEGER = getWallClock();

                // Load the game code.
                var game = loadGameCode(&source_dll_path, &temp_dll_path);

                running = true;

                while (running) {
                    var timed_block = TimedBlock.beginBlock(@src(), .ExecutableRefresh);

                    //
                    //
                    //

                    if (fader.update(new_input.frame_delta_time, window_handle) == .WaitingForClose) {
                        running = false;
                    }

                    // Reload the game code if it has changed.
                    const last_dll_write_time = getLastWriteTime(&source_dll_path);
                    game_memory.executable_reloaded = false;
                    if (win32.CompareFileTime(&last_dll_write_time, &game.last_write_time) != 0) {
                        completeAllQueuedWork(&high_priority_queue);
                        completeAllQueuedWork(&low_priority_queue);

                        if (INTERNAL) {
                            shared.global_debug_table = &local_stub_debug_table;
                        }

                        unloadGameCode(&game);
                        game = loadGameCode(&source_dll_path, &temp_dll_path);
                        game_memory.executable_reloaded = true;
                    }

                    timed_block.end();

                    //
                    //
                    //

                    timed_block = TimedBlock.beginBlock(@src(), .InputProcessing);

                    var message: win32.MSG = undefined;

                    const old_keyboard_controller = &old_input.controllers[0];
                    var new_keyboard_controller = &new_input.controllers[0];
                    new_keyboard_controller.is_connected = true;

                    // Transfer buttons state from previous loop to this one.
                    old_keyboard_controller.copyButtonStatesTo(new_keyboard_controller);

                    // Process all messages provided by Windows.
                    while (win32.PeekMessageW(&message, window_handle, 0, 0, win32.PM_REMOVE) != 0) {
                        switch (message.message) {
                            win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYDOWN, win32.WM_KEYUP => {
                                processKeyboardInput(message, new_keyboard_controller, &state);
                            },
                            else => {
                                _ = win32.TranslateMessage(&message);
                                _ = win32.DispatchMessageW(&message);
                            },
                        }
                    }

                    // Prepare input to game.
                    var game_buffer = getGameBuffer();
                    processMouseInput(old_input, new_input, window_handle);
                    processXInput(old_input, new_input);

                    timed_block.end();

                    //
                    //
                    //

                    timed_block = TimedBlock.beginBlock(@src(), .GameUpdate);

                    if (state.input_recording_index > 0) {
                        recordInput(&state, new_input);
                    } else if (state.input_playing_index > 0) {
                        const temp: shared.GameInput = new_input.*;

                        playbackInput(&state, new_input);

                        new_input.mouse_buttons = temp.mouse_buttons;
                        new_input.mouse_x = temp.mouse_x;
                        new_input.mouse_y = temp.mouse_y;
                        new_input.mouse_z = temp.mouse_z;
                        new_input.shift_down = temp.shift_down;
                        new_input.alt_down = temp.alt_down;
                        new_input.control_down = temp.control_down;
                    }

                    // Send all input to game.
                    game.updateAndRender(platform, &game_memory, new_input, &game_buffer);

                    if (new_input.quit_requested) {
                        fader.beginFadeToDesktop();
                    }

                    timed_block.end();

                    //
                    //
                    //

                    timed_block = TimedBlock.beginBlock(@src(), .AudioUpdate);

                    // Output sound.
                    if (opt_secondary_buffer) |secondary_buffer| {
                        var play_cursor: std.os.windows.DWORD = undefined;
                        var write_cursor: std.os.windows.DWORD = undefined;
                        const audio_wall_clock = getWallClock();
                        const from_begin_to_audio_seconds = getSecondsElapsed(flip_wall_clock, audio_wall_clock);

                        if (win32.SUCCEEDED(secondary_buffer.vtable.GetCurrentPosition(
                            secondary_buffer,
                            &play_cursor,
                            &write_cursor,
                        ))) {
                            // We define a safety margin that is the number of samples that our game loop can vary by.
                            // Check where play cursor is and forecast ahead where we think the play cursor will be on the
                            // next frame boundary.
                            //
                            // Low latency: Check if the write cursor is before that by at least the safety margin. If so the
                            // target fill position is the frame boundary plus one frame.
                            //
                            // High latency: If the write cursor is after that safety valye, we assume we can never
                            // sync perfectly. So we write one frame's worth of audio plus the safety value number of samples.
                            if (!sound_output_info.is_valid) {
                                sound_output.running_sample_index = write_cursor / sound_output.bytes_per_sample;
                                sound_output_info.is_valid = true;
                            }

                            sound_output_info.byte_to_lock = (sound_output.running_sample_index * sound_output.bytes_per_sample) % sound_output.secondary_buffer_size;

                            const expected_sound_bytes_per_frame =
                                (sound_output.samples_per_second * sound_output.bytes_per_sample) / @as(u32, @intFromFloat(game_update_hz));

                            const seconds_left_until_flip = target_seconds_per_frame - from_begin_to_audio_seconds;
                            var expected_bytes_until_flip: std.os.windows.DWORD = expected_sound_bytes_per_frame;

                            if (seconds_left_until_flip > 0) {
                                expected_bytes_until_flip =
                                    @intFromFloat((seconds_left_until_flip / target_seconds_per_frame) *
                                    @as(f32, @floatFromInt(expected_sound_bytes_per_frame)));
                            }

                            const expected_frame_boundary_byte: std.os.windows.DWORD = play_cursor + expected_bytes_until_flip;

                            var safety_write_cursor: std.os.windows.DWORD = write_cursor;
                            if (safety_write_cursor < play_cursor) {
                                safety_write_cursor += sound_output.secondary_buffer_size;
                            }
                            write_cursor += sound_output.safety_bytes;
                            const audio_card_is_low_latency = (safety_write_cursor < expected_sound_bytes_per_frame);

                            var target_cursor: u32 = 0;
                            if (audio_card_is_low_latency) {
                                target_cursor = (expected_frame_boundary_byte + expected_sound_bytes_per_frame);
                            } else {
                                target_cursor =
                                    (write_cursor + expected_sound_bytes_per_frame + sound_output.safety_bytes);
                            }
                            target_cursor = (target_cursor % sound_output.secondary_buffer_size);

                            if (sound_output_info.byte_to_lock > target_cursor) {
                                sound_output_info.bytes_to_write = sound_output.secondary_buffer_size - sound_output_info.byte_to_lock;
                                sound_output_info.bytes_to_write += target_cursor;
                            } else {
                                sound_output_info.bytes_to_write = target_cursor - sound_output_info.byte_to_lock;
                            }

                            sound_output_info.output_buffer = shared.SoundOutputBuffer{
                                .samples = samples.?,
                                .sample_count = shared.align8(@divFloor(sound_output_info.bytes_to_write, sound_output.bytes_per_sample)),
                                .samples_per_second = sound_output.samples_per_second,
                            };
                            sound_output_info.bytes_to_write = sound_output_info.output_buffer.sample_count * sound_output.bytes_per_sample;

                            game.getSoundSamples(&game_memory, &sound_output_info.output_buffer);

                            if (INTERNAL) {
                                var marker = &debug_time_markers[debug_time_marker_index];
                                marker.output_play_cursor = play_cursor;
                                marker.output_write_cursor = write_cursor;
                                marker.expected_flip_play_coursor = expected_frame_boundary_byte;
                                marker.output_location = sound_output_info.byte_to_lock;
                                marker.output_byte_count = sound_output_info.bytes_to_write;

                                var unwrapped_write_cursor = write_cursor;
                                if (unwrapped_write_cursor < play_cursor) {
                                    unwrapped_write_cursor += sound_output.secondary_buffer_size;
                                }
                                const audio_latency_bytes: std.os.windows.DWORD = unwrapped_write_cursor - play_cursor;
                                const audio_latency_seconds: f32 =
                                    (@as(f32, @floatFromInt(audio_latency_bytes)) /
                                    @as(f32, @floatFromInt(sound_output.bytes_per_sample))) /
                                    @as(f32, @floatFromInt(sound_output.samples_per_second));
                                var buffer: [128]u8 = undefined;
                                const slice = std.fmt.bufPrintZ(&buffer, "Audio: BTL:{d} TC:{d} BTW:{d} - PC:{d} WC:{d} DELTA:{d} Latency:{d:>3.4}\n", .{
                                    sound_output_info.byte_to_lock,
                                    target_cursor,
                                    sound_output_info.bytes_to_write,
                                    play_cursor,
                                    write_cursor,
                                    audio_latency_bytes,
                                    audio_latency_seconds,
                                }) catch "";
                                win32.OutputDebugStringA(@ptrCast(slice.ptr));
                            }

                            fillSoundBuffer(&sound_output, secondary_buffer, &sound_output_info);
                        } else {
                            sound_output_info.is_valid = false;
                        }
                    }

                    timed_block.end();

                    //
                    //
                    //

                    if (INTERNAL) {
                        timed_block = TimedBlock.beginBlock(@src(), .DebugCollation);
                        defer timed_block.end();

                        if (game.debugFrameEnd) |frameEndFn| {
                            shared.global_debug_table = frameEndFn(&game_memory, new_input.*, &game_buffer);
                        }

                        local_stub_debug_table.event_array_index_event_index = 0;
                    }

                    //
                    //
                    //

                    if (true) {
                        timed_block = TimedBlock.beginBlock(@src(), .FrameRateWait);

                        // Capture timing.
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

                        timed_block.end();
                    }

                    //
                    //
                    //

                    timed_block = TimedBlock.beginBlock(@src(), .FrameDisplay);

                    if (INTERNAL) {
                        if (false) {
                            var marker_index = debug_time_marker_index;
                            if (marker_index > 1) {
                                marker_index -= 1;
                            } else {
                                marker_index = debug_time_markers.len - 1;
                            }

                            debugSyncDisplay(
                                &back_buffer,
                                &debug_time_markers,
                                marker_index,
                                &sound_output,
                                target_seconds_per_frame,
                            );
                        }
                    }

                    // Output game to screen.
                    const window_dimension = getWindowDimension(window_handle);
                    displayBufferInWindow(&back_buffer, device_context, window_handle, window_dimension.width, window_dimension.height);

                    flip_wall_clock = getWallClock();

                    // Flip the controller inputs for next frame.
                    const temp: *shared.GameInput = new_input;
                    new_input = old_input;
                    old_input = temp;

                    //
                    //
                    //

                    timed_block.end();

                    const end_counter = getWallClock();

                    var frame_marker = TimedBlock.frameMarker(
                        @src(),
                        .TotalPlatformLoop,
                        getSecondsElapsed(last_counter, end_counter),
                    );
                    defer frame_marker.end();
                    last_counter = end_counter;
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
