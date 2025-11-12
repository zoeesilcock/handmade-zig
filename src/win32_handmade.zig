/// TODO: This is not a final platform layer!
///
/// Partial list of missing parts:
///
/// * Save game locations.
/// * Getting a handle to our own executable file.
/// * Raw Input (support for multiple keyboards).
/// * ClipCursor() (for multi-monitor support).
/// * QueryCancelAutoplay.
/// * WM_ACTIVATEAPP (for when we are not the active application).
/// * Get KeyboardLayout (for international keyboards).
pub const UNICODE = true;

const MIDDLE_C: u32 = 261;
const TREBLE_C: u32 = 523;

// const WIDTH = 1920 / 10;
// const HEIGHT = 1080 / 10;
// const WIDTH = 960;
// const HEIGHT = 540;
// const WIDTH = 960 / 2;
// const HEIGHT = 540 / 2;
// const WIDTH = 1280;
// const HEIGHT = 720;
// const WIDTH = 2560;
// const HEIGHT = 1440;
// const WIDTH = 1920 * 2;
// const HEIGHT = 1080 * 2;
const WIDTH = 1920;
const HEIGHT = 1080;
const WINDOW_DECORATION_WIDTH = 16;
const WINDOW_DECORATION_HEIGHT = 39;
const BYTES_PER_PIXEL = 4;

const DEBUG_WINDOW_POS_X = -7 + 210; // + 2560;
const DEBUG_WINDOW_POS_Y = 0 + 30;
const DEBUG_WINDOW_WIDTH = WIDTH + WINDOW_DECORATION_WIDTH;
const DEBUG_WINDOW_HEIGHT = HEIGHT + WINDOW_DECORATION_HEIGHT;
const DEBUG_WINDOW_ACTIVE_OPACITY = 255;
const DEBUG_WINDOW_INACTIVE_OPACITY = 255;
const DEBUG_TIME_MARKER_COUNT = 30;
const STATE_FILE_NAME_COUNT = win32.MAX_PATH;
const LIGHT_DATA_WIDTH = shared.LIGHT_DATA_WIDTH;

// Build options.
const INTERNAL = shared.INTERNAL;
const DEBUG = shared.DEBUG;

const shared = @import("shared.zig");
const memory = @import("memory.zig");
const render = @import("render.zig");
const rendergroup = @import("rendergroup.zig");
const asset = @import("asset.zig");
const sort = @import("sort.zig");
const opengl = @import("opengl.zig");
const debug_interface = @import("debug_interface.zig");

// Types
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const DebugId = debug_interface.DebugId;
const MemoryArena = memory.MemoryArena;
const MemoryIndex = memory.MemoryIndex;
const DebugPlatformMemoryStats = shared.DebugPlatformMemoryStats;
const TexturedVertex = shared.TexturedVertex;
const Rectangle2i = math.Rectangle2i;
const TicketMutex = shared.TicketMutex;
const PlatformMemoryBlock = shared.PlatformMemoryBlock;
const PlatformMemoryBlockFlags = shared.PlatformMemoryBlockFlags;
const LoadedBitmap = asset.LoadedBitmap;
const LightingSurface = shared.LightingSurface;
const LightingPoint = shared.LightingPoint;

const std = @import("std");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const win32 = @import("win32").everything;

const gl = @cImport({
    @cInclude("GL/glcorearb.h");
});
var open_gl = &@import("opengl.zig").open_gl;

// Manual import of a function that is incorrectly defined in zigwin32.
// Remove once this is resloved: https://github.com/marlersoft/zigwin32/issues/33
pub extern "gdi32" fn DescribePixelFormat(
    hdc: ?win32.HDC,
    iPixelFormat: c_int, // The field that is wrong in zigwin32.
    nBytes: u32,
    ppfd: ?*win32.PIXELFORMATDESCRIPTOR,
) callconv(.winapi) i32;

// OpenGL
const WglSwapIntervalEXT: type = fn (interval: i32) callconv(.winapi) bool;
var optWglSwapIntervalEXT: ?*const WglSwapIntervalEXT = null;

const WglCreateContextAttribsARB: type = fn (
    hdc: win32.HDC,
    share_context: ?win32.HGLRC,
    attrib_list: ?[*:0]const c_int,
) callconv(.winapi) ?win32.HGLRC;
var optWglCreateContextAttribsARB: ?*const WglCreateContextAttribsARB = null;

const WglChoosePixelFormatARB: type = fn (
    hdc: win32.HDC,
    piAttribIList: [*:0]const c_int,
    pfAttribFList: ?[*:0]const f32,
    nMaxFormats: c_uint,
    piFormats: *c_int,
    nNumFormats: *c_uint,
) callconv(.winapi) win32.BOOL;
var optWglChoosePixelFormatARB: ?*const WglChoosePixelFormatARB = null;

const WglGetExtensionsStringEXT: type = fn (hdc: win32.HDC) callconv(.winapi) ?*u8;
var optWglGetExtensionsStringEXT: ?*const WglGetExtensionsStringEXT = null;

const GLBindFramebufferEXT: type = fn (target: u32, framebuffer: u32) callconv(.winapi) void;
pub var optGLBindFramebufferEXT: ?*const GLBindFramebufferEXT = null;
const GLGenFramebuffersEXT: type = fn (n: u32, framebuffer: [*]u32) callconv(.winapi) void;
pub var optGLGenFramebuffersEXT: ?*const GLGenFramebuffersEXT = null;
const GLDeleteFramebuffersEXT: type = fn (n: u32, framebuffer: [*]u32) callconv(.winapi) void;
pub var optGLDeleteFramebuffersEXT: ?*const GLDeleteFramebuffersEXT = null;
const GLFrameBufferTexture2DEXT: type = fn (target: u32, attachment: u32, textarget: u32, texture: u32, level: i32) callconv(.winapi) void;
pub var optGLFrameBufferTexture2DEXT: ?*const GLFrameBufferTexture2DEXT = null;
const GLCheckFramebufferStatusEXT: type = fn (target: u32) callconv(.winapi) u32;
pub var optGLCheckFramebufferStatusEXT: ?*const GLCheckFramebufferStatusEXT = null;
const GLTexImage2DMultiSample: type = fn (target: u32, samples: i32, internal_format: i32, width: i32, height: i32, fixed_sample_locations: bool) callconv(.winapi) u32;
pub var optGLTexImage2DMultiSample: ?*const GLTexImage2DMultiSample = null;
const GLBlitFrameBuffer: type = fn (src_x0: i32, src_y0: i32, src_x1: i32, src_y1: i32, dst_x0: i32, dst_y0: i32, dst_x1: i32, dst_y1: i32, mask: u32, filter: u32) callconv(.winapi) void;
pub var optGLBlitFrameBuffer: ?*const GLBlitFrameBuffer = null;
const GLCreateShader: type = fn (shader_type: u32) callconv(.winapi) u32;
pub var optGLCreateShader: ?*const GLCreateShader = null;
const GLDeleteShader: type = fn (shader: u32) callconv(.winapi) void;
pub var optGLDeleteShader: ?*const GLDeleteShader = null;
const GLShaderSource: type = fn (shader: u32, count: i32, string: [*]const [*:0]const u8, length: ?*i32) callconv(.winapi) void;
pub var optGLShaderSource: ?*const GLShaderSource = null;
const GLCompileShader: type = fn (shader: u32) callconv(.winapi) void;
pub var optGLCompileShader: ?*const GLCompileShader = null;
const GLCreateProgram: type = fn () callconv(.winapi) u32;
pub var optGLCreateProgram: ?*const GLCreateProgram = null;
const GLDeleteProgram: type = fn (program: u32) callconv(.winapi) void;
pub var optGLDeleteProgram: ?*const GLDeleteProgram = null;
const GLLinkProgram: type = fn (shader: u32) callconv(.winapi) void;
pub var optGLLinkProgram: ?*const GLLinkProgram = null;
const GLAttachShader: type = fn (program: u32, shader: u32) callconv(.winapi) void;
pub var optGLAttachShader: ?*const GLAttachShader = null;
const GLValidateProgram: type = fn (program: u32) callconv(.winapi) void;
pub var optGLValidateProgram: ?*const GLValidateProgram = null;
const GLGetProgramiv: type = fn (program: u32, pname: u32, params: *i32) callconv(.winapi) void;
pub var optGLGetProgramiv: ?*const GLGetProgramiv = null;
const GLGetShaderInfoLog: type = fn (shader: u32, bufSize: i32, length: *i32, infoLog: [*]u8) callconv(.winapi) void;
pub var optGLGetShaderInfoLog: ?*const GLGetShaderInfoLog = null;
const GLGetProgramInfoLog: type = fn (program: u32, bufSize: i32, length: *i32, infoLog: [*]u8) callconv(.winapi) void;
pub var optGLGetProgramInfoLog: ?*const GLGetProgramInfoLog = null;
const GLUseProgram: type = fn (program: u32) callconv(.winapi) void;
pub var optGLUseProgram: ?*const GLUseProgram = null;
const GLUniformMatrix4fv: type = fn (location: i32, count: i32, transpose: bool, value: *const f32) callconv(.winapi) void;
pub var optGLUniformMatrix4fv: ?*const GLUniformMatrix4fv = null;
const GLUniform1f: type = fn (location: i32, value: f32) callconv(.winapi) void;
pub var optGLUniform1f: ?*const GLUniform1f = null;
const GLUniform2fv: type = fn (location: i32, count: i32, value: *const f32) callconv(.winapi) void;
pub var optGLUniform2fv: ?*const GLUniform2fv = null;
const GLUniform3fv: type = fn (location: i32, count: i32, value: *const f32) callconv(.winapi) void;
pub var optGLUniform3fv: ?*const GLUniform3fv = null;
const GLUniform4fv: type = fn (location: i32, count: i32, value: *const f32) callconv(.winapi) void;
pub var optGLUniform4fv: ?*const GLUniform4fv = null;
const GLUniform1i: type = fn (location: i32, value: i32) callconv(.winapi) void;
pub var optGLUniform1i: ?*const GLUniform1i = null;
const GLGetUniformLocation: type = fn (program: u32, [*]const u8) callconv(.winapi) i32;
pub var optGLGetUniformLocation: ?*const GLGetUniformLocation = null;
const GLGetAttribLocation: type = fn (program: u32, name: [*]const u8) callconv(.winapi) i32;
pub var optGLGetAttribLocation: ?*const GLGetAttribLocation = null;
const GLEnableVertexAttribArray: type = fn (index: u32) callconv(.winapi) void;
pub var optGLEnableVertexAttribArray: ?*const GLEnableVertexAttribArray = null;
const GLDisableVertexAttribArray: type = fn (index: u32) callconv(.winapi) void;
pub var optGLDisableVertexAttribArray: ?*const GLDisableVertexAttribArray = null;
const GLVertexAttribPointer: type = fn (index: u32, size: i32, data_type: u32, normalized: bool, stride: isize, pointer: ?*anyopaque) callconv(.winapi) void;
pub var optGLVertexAttribPointer: ?*const GLVertexAttribPointer = null;
const GLVertexAttribIPointer: type = fn (index: u32, size: i32, data_type: u32, stride: isize, pointer: ?*anyopaque) callconv(.winapi) void;
pub var optGLVertexAttribIPointer: ?*const GLVertexAttribIPointer = null;
const GLGenVertexArrays: type = fn (size: i32, arrays: ?*u32) callconv(.winapi) void;
pub var optGLGenVertexArrays: ?*const GLGenVertexArrays = null;
const GLBindVertexArray: type = fn (array: u32) callconv(.winapi) void;
pub var optGLBindVertexArray: ?*const GLBindVertexArray = null;
const GLDrawArrays: type = fn (mode: u32, first: i32, count: i32) callconv(.winapi) void;
pub var optGLDrawArrays: ?*const GLDrawArrays = null;
const GLDebugProcArb = ?*const fn (source: u32, message_type: u32, id: u32, severity: u32, length: i32, message: [*]const u8, user_param: ?*const anyopaque) callconv(.winapi) void;
const GLDebugMessageCallbackARB: type = fn (callback: GLDebugProcArb, user_param: ?*const anyopaque) callconv(.winapi) void;
pub var optGLDebugMessageCallbackARB: ?*const GLDebugMessageCallbackARB = null;
const GLDebugMessageControlARB: type = fn (source: u32, message_type: u32, severity: u32, count: i32, ids: [*]const i32, enabled: bool) callconv(.winapi) void;
pub var optGLDebugMessageControlARB: ?*const GLDebugMessageControlARB = null;
const GLGetStringi: type = fn (name: u32, index: u32) callconv(.winapi) ?*u8;
pub var optGLGetStringi: ?*const GLGetStringi = null;
const GLGenBuffers: type = fn (count: i32, buffers: *u32) callconv(.winapi) void;
pub var optGLGenBuffers: ?*const GLGenBuffers = null;
const GLBindBuffer: type = fn (target: u32, buffer: u32) callconv(.winapi) void;
pub var optGLBindBuffer: ?*const GLBindBuffer = null;
const GLBufferData: type = fn (target: u32, size: isize, data: *anyopaque, usage: u32) callconv(.winapi) void;
pub var optGLBufferData: ?*const GLBufferData = null;
const GLActiveTexture: type = fn (texture: u32) callconv(.winapi) void;
pub var optGLActiveTexture: ?*const GLActiveTexture = null;
const GLDrawBuffers: type = fn (n: u32, buffers: [*]const u32) callconv(.winapi) void;
pub var optGLDrawBuffers: ?*const GLDrawBuffers = null;
const GLBindFragDataLocation: type = fn (program: u32, color: u32, name: [*]const u8) callconv(.winapi) void;
pub var optGLBindFragDataLocation: ?*const GLBindFragDataLocation = null;
const GLTexImage3D: type = fn (target: u32, level: i32, internalformat: i32, width: isize, height: isize, depth: isize, border: i32, format: u32, type: u32, pixels: ?*const anyopaque) callconv(.winapi) void;
pub var optGLTexImage3D: ?*const GLTexImage3D = null;
const GLTexSubImage3D: type = fn (target: u32, level: i32, xoffset: i32, yoffset: i32, zoffset: i32, width: isize, height: isize, depth: isize, format: u32, type: u32, pixels: ?*const anyopaque) callconv(.winapi) void;
pub var optGLTexSubImage3D: ?*const GLTexSubImage3D = null;

// Globals.
pub var platform: shared.Platform = undefined;
pub var running: bool = false;
pub var paused: bool = false;
pub var software_rendering: bool = false;
var global_state: Win32State = .{};
var back_buffer: OffscreenBuffer = .{};
var opt_secondary_buffer: ?*win32.IDirectSoundBuffer = undefined;
var perf_count_frequency: i64 = 0;
var show_debug_cursor = INTERNAL;
var window_placement: win32.WINDOWPLACEMENT = undefined;
var global_debug_table_: debug_interface.DebugTable = if (INTERNAL) debug_interface.DebugTable{} else undefined;
var global_debug_table = &global_debug_table_;

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

const Win32State = extern struct {
    // To touch the memory ring, you must take the memory mutex.
    memory_mutex: TicketMutex = undefined,
    memory_sentinel: MemoryBlock = undefined,

    recording_handle: win32.HANDLE = undefined,
    input_recording_index: u32 = 0,

    playback_handle: win32.HANDLE = undefined,
    input_playing_index: u32 = 0,

    exe_file_name: [STATE_FILE_NAME_COUNT:0]u8 = undefined,
    one_past_last_exe_file_name_slash: usize = 0,
};

const MemoryBlockLoopingFlag = enum(u64) {
    AllocatedDuringLooping = 0x1,
    FreedDuringLooping = 0x2,
};

const MemoryBlock = extern struct {
    block: shared.PlatformMemoryBlock,
    prev: *MemoryBlock,
    next: *MemoryBlock,
    looping_flags: u64 = 0,
};

const SavedMemoryBlock = extern struct {
    base_pointer: u64 = 0,
    size: u64 = 0,
};

const ThreadStartup = struct {
    queue: *shared.PlatformWorkQueue = undefined,
};

pub const Game = struct {
    is_valid: bool = false,
    dll: ?win32.HINSTANCE = undefined,
    last_write_time: win32.FILETIME = undefined,
    updateAndRender: ?*const @TypeOf(shared.updateAndRenderStub) = null,
    getSoundSamples: ?*const @TypeOf(shared.getSoundSamplesStub) = null,
    debugFrameEnd: ?*const @TypeOf(shared.debugFrameEndStub) = null,
};

const Win32PlatformFileGroup = extern struct {
    find_handle: win32.FindFileHandle,
    find_data: win32.WIN32_FIND_DATAW,
};

const Win32PlatformFileHandle = extern struct {
    win32_handle: win32.HANDLE,
};

fn getAllFilesOfTypeBegin(file_type: shared.PlatformFileTypes) callconv(.c) shared.PlatformFileGroup {
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

fn getAllFilesOfTypeEnd(file_group: *shared.PlatformFileGroup) callconv(.c) void {
    const win32_file_group: *Win32PlatformFileGroup = @ptrCast(@alignCast(file_group.platform));

    _ = win32.FindClose(win32_file_group.find_handle);
    _ = win32.VirtualFree(win32_file_group, 0, win32.MEM_RELEASE);
}

fn openNextFile(file_group: *shared.PlatformFileGroup) callconv(.c) shared.PlatformFileHandle {
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

fn readDataFromFile(source: *shared.PlatformFileHandle, offset: u64, size: u64, dest: *anyopaque) callconv(.c) void {
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
            std.debug.print("Error loading file: {d}\n", .{@intFromEnum(error_number)});
            fileError(source, "Read file failed.");
        }
    }
}

fn fileError(file_handle: *shared.PlatformFileHandle, message: [*:0]const u8) callconv(.c) void {
    if (INTERNAL) {
        win32.OutputDebugStringA("WIN32 FILE ERROR: ");
        win32.OutputDebugStringA(message);
        win32.OutputDebugStringA("\n");
    }

    file_handle.no_errors = false;
}

fn isInLoop() bool {
    const result: bool = global_state.input_recording_index != 0 or global_state.input_playing_index != 0;
    return result;
}

fn allocateMemory(size: MemoryIndex, flags: u64) callconv(.c) ?*PlatformMemoryBlock {
    // We require memory block headers not to change the cache line alignment of an allocation.
    std.debug.assert(@sizeOf(MemoryBlock) == 64);

    const page_size: MemoryIndex = 4096;
    var total_size: MemoryIndex = size + @sizeOf(MemoryBlock);
    var base_offset: MemoryIndex = @sizeOf(MemoryBlock);
    var protected_offset: MemoryIndex = 0;
    if (flags & @intFromEnum(PlatformMemoryBlockFlags.UnderflowCheck) != 0) {
        total_size = size + 2 * page_size;
        base_offset = 2 * page_size;
        protected_offset = page_size;
    } else if (flags & @intFromEnum(PlatformMemoryBlockFlags.OverflowCheck) != 0) {
        const size_rounded_up: MemoryIndex = shared.alignPow2(@intCast(size), page_size);
        total_size = size_rounded_up + 2 * page_size;
        base_offset = page_size + size_rounded_up - size;
        protected_offset = page_size + size_rounded_up;
    }

    var result: ?*PlatformMemoryBlock = null;
    const opt_block: ?*MemoryBlock = @ptrCast(@alignCast(win32.VirtualAlloc(
        null,
        total_size,
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    )));

    if (opt_block) |b| {
        var block = b;
        block.block.base = @ptrFromInt(@intFromPtr(block) + base_offset);

        std.debug.assert(block.block.used == 0);
        std.debug.assert(block.block.arena_prev == null);

        if (flags &
            (@intFromEnum(PlatformMemoryBlockFlags.UnderflowCheck) |
                @intFromEnum(PlatformMemoryBlockFlags.OverflowCheck)) != 0)
        {
            var old_protect: win32.PAGE_PROTECTION_FLAGS = undefined;
            const protected = win32.VirtualProtect(@ptrFromInt(@intFromPtr(block) + protected_offset), page_size, win32.PAGE_NOACCESS, &old_protect);
            std.debug.assert(protected != 0);
        }

        const sentinel: *MemoryBlock = &global_state.memory_sentinel;
        block.next = sentinel;
        block.block.size = size;
        block.block.flags = flags;
        block.looping_flags = if (isInLoop()) @intFromEnum(MemoryBlockLoopingFlag.AllocatedDuringLooping) else 0;

        global_state.memory_mutex.begin();
        block.prev = sentinel.prev;
        block.prev.next = block;
        block.next.prev = block;
        global_state.memory_mutex.end();

        result = &block.block;
    } else {
        outputLastError("Failed to allocate memory");
        unreachable;
    }

    return result;
}

fn freeMemoryBlock(block: *MemoryBlock) void {
    global_state.memory_mutex.begin();
    block.prev.next = block.next;
    block.next.prev = block.prev;
    global_state.memory_mutex.end();

    const result = win32.VirtualFree(@ptrCast(block), 0, win32.MEM_RELEASE);
    std.debug.assert(result != 0);
}

fn deallocateMemory(opt_platform_block: ?*PlatformMemoryBlock) callconv(.c) void {
    if (opt_platform_block) |platform_block| {
        var block: *MemoryBlock = @ptrCast(platform_block);
        if (isInLoop()) {
            block.looping_flags = @intFromEnum(MemoryBlockLoopingFlag.FreedDuringLooping);
        } else {
            freeMemoryBlock(block);
        }
    }
}

const DebugFunctions = if (INTERNAL) struct {
    pub fn debugFreeFileMemory(mem: *anyopaque) callconv(.c) void {
        _ = win32.VirtualFree(mem, 0, win32.MEM_RELEASE);
    }

    pub fn debugReadEntireFile(file_name: [*:0]const u8) callconv(.c) shared.DebugReadFileResult {
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

    pub fn debugWriteEntireFile(file_name: [*:0]const u8, content_size: u32, contents: *anyopaque) callconv(.c) bool {
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

            if (win32.WriteFile(file_handle, contents, content_size, &bytes_written, null) != 0) {
                // File written successfully.
                result = bytes_written == content_size;
            }

            _ = win32.CloseHandle(file_handle);
        }

        return result;
    }

    pub fn debugExecuteSystemCommand(
        path: [*:0]const u8,
        command: [*:0]const u8,
        command_line: [*:0]const u8,
    ) callconv(.c) shared.DebugExecutingProcess {
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

    pub fn debugGetProcessState(process: shared.DebugExecutingProcess) callconv(.c) shared.DebugExecutingProcessState {
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

    pub fn debugGetMemoryStats() callconv(.c) DebugPlatformMemoryStats {
        global_state.memory_mutex.begin();
        defer global_state.memory_mutex.end();

        var stats: DebugPlatformMemoryStats = .{};
        const sentinel: *MemoryBlock = &global_state.memory_sentinel;
        var source_block = sentinel.next;
        while (source_block != sentinel) : (source_block = source_block.next) {
            std.debug.assert(source_block.block.size <= std.math.maxInt(u32));

            stats.block_count += 1;
            stats.total_size += source_block.block.size;
            stats.total_used += source_block.block.used;
        }

        return stats;
    }
} else struct {
    pub fn debugFreeFileMemory(_: *anyopaque) callconv(.c) void {}
    pub fn debugReadEntireFile(_: [*:0]const u8) callconv(.c) shared.DebugReadFileResult {
        return undefined;
    }
    pub fn debugWriteEntireFile(_: [*:0]const u8, _: u32, _: *anyopaque) callconv(.c) bool {
        return false;
    }
    pub fn debugExecuteSystemCommand(
        _: [*:0]const u8,
        _: [*:0]const u8,
        _: [*:0]const u8,
    ) callconv(.c) shared.DebugExecutingProcess {
        return undefined;
    }
    pub fn debugGetProcessState(_: shared.DebugExecutingProcess) callconv(.c) shared.DebugExecutingProcessState {
        return undefined;
    }
    pub fn debugGetMemoryStats() callconv(.c) DebugPlatformMemoryStats {}
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

fn timeIsValid(time: win32.FILETIME) bool {
    return time.dwLowDateTime != 0 or time.dwHighDateTime != 0;
}

fn loadGameCode(source_dll_name: [*:0]const u8, temp_dll_name: [*:0]const u8) Game {
    var result = Game{};

    _ = win32.CopyFileA(source_dll_name, temp_dll_name, win32.FALSE);

    result.last_write_time = getLastWriteTime(source_dll_name);
    result.dll = win32.LoadLibraryA(temp_dll_name);
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

        result.is_valid =
            result.updateAndRender != null and result.getSoundSamples != null and result.debugFrameEnd != null;
    } else {
        outputLastError("LoadLibraryA error");
        @panic("Failed to load game library.");
    }

    if (!result.is_valid) {
        result.updateAndRender = null;
        result.getSoundSamples = null;
        result.debugFrameEnd = null;
    }

    return result;
}

fn unloadGameCode(game: *Game) void {
    if (game.dll) |dll| {
        _ = win32.FreeLibrary(dll);
        game.dll = undefined;
    }

    game.updateAndRender = null;
    game.getSoundSamples = null;
    game.debugFrameEnd = null;
}

fn XInputGetStateStub(_: u32, _: ?*win32.XINPUT_STATE) callconv(.winapi) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
fn XInputSetStateStub(_: u32, _: ?*win32.XINPUT_VIBRATION) callconv(.winapi) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
var XInputGetState: *const fn (u32, ?*win32.XINPUT_STATE) callconv(.winapi) isize = XInputGetStateStub;
var XInputSetState: *const fn (u32, ?*win32.XINPUT_VIBRATION) callconv(.winapi) isize = XInputSetStateStub;

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

fn processMouseInput(
    old_input: *shared.GameInput,
    new_input: *shared.GameInput,
    window: win32.HWND,
    render_commands: *shared.RenderCommands,
    draw_region: Rectangle2i,
    window_dimension: WindowDimension,
) void {
    TimedBlock.beginBlock(@src(), .ProcessMouseInput);
    defer TimedBlock.endBlock(@src(), .ProcessMouseInput);

    var mouse_point: win32.POINT = undefined;
    if (win32.GetCursorPos(&mouse_point) == win32.TRUE) {
        _ = win32.ScreenToClient(window, &mouse_point);

        const mouse_x: f32 = @as(f32, @floatFromInt(mouse_point.x));
        const mouse_y: f32 = @as(f32, @floatFromInt((window_dimension.height - 1) - mouse_point.y));
        const mouse_u: f32 = math.clamp01MapToRange(
            @as(f32, @floatFromInt(draw_region.min.x())),
            @as(f32, @floatFromInt(draw_region.max.x())),
            mouse_x,
        );
        const mouse_v: f32 = math.clamp01MapToRange(
            @as(f32, @floatFromInt(draw_region.min.y())),
            @as(f32, @floatFromInt(draw_region.max.y())),
            mouse_y,
        );

        new_input.mouse_x = @as(f32, @floatFromInt(render_commands.settings.width)) * mouse_u;
        new_input.mouse_y = @as(f32, @floatFromInt(render_commands.settings.height)) * mouse_v;

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

fn processXInput(
    xbox_controller_present: *[win32.XUSER_MAX_COUNT]bool,
    old_input: *shared.GameInput,
    new_input: *shared.GameInput,
) void {
    TimedBlock.beginBlock(@src(), .ProcessXInput);
    defer TimedBlock.endBlock(@src(), .ProcessXInput);

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

        if (xbox_controller_present[controller_index]) {
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
                new_controller.is_connected = false;
                xbox_controller_present[controller_index] = false;
            }
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

fn processPendingMessages(
    state: *Win32State,
    window_handle: win32.HWND,
    keyboard_controller: *shared.ControllerInput,
    input: *shared.GameInput,
) void {
    var message: win32.MSG = undefined;
    _ = window_handle;
    while (true) {
        TimedBlock.beginBlock(@src(), .PeekMessage);

        const skip_messages = [_]u32{
            // win32.WM_PAINT,
            // Ignoring WM_MOUSEMOVE lead to performance issues.
            // win32.WM_MOUSEMOVE,
            // Guard against an unknown message which spammed the game on Casey's machine.
            0x738,
            0xffffffff,
        };

        var got_message: bool = false;
        var last_message: u32 = 0;
        for (skip_messages) |skip| {
            got_message = win32.PeekMessageW(
                &message,
                null,
                last_message,
                skip - 1,
                win32.PM_REMOVE,
            ) != 0;

            if (got_message) {
                break;
            }

            last_message = skip +% 1;
        }

        TimedBlock.endBlock(@src(), .PeekMessage);

        if (!got_message) {
            break;
        }

        switch (message.message) {
            win32.WM_QUIT => running = false,
            win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYDOWN, win32.WM_KEYUP => {
                processKeyboardInput(message, keyboard_controller, input, state);
            },
            else => {
                _ = win32.TranslateMessage(&message);
                _ = win32.DispatchMessageW(&message);
            },
        }
    }
}

fn processKeyboardInput(
    message: win32.MSG,
    keyboard_controller: *shared.ControllerInput,
    input: *shared.GameInput,
    state: *Win32State,
) void {
    const vk_code = message.wParam;
    const alt_was_down: bool = if ((message.lParam & (1 << 29) != 0)) true else false;
    const shift_was_down: bool = win32.GetKeyState(@intFromEnum(win32.VK_SHIFT)) & (1 << 7) != 0;
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
            @intFromEnum(win32.VK_RETURN) => {
                if (is_down and alt_was_down) {
                    if (message.hwnd) |window| {
                        toggleFullscreen(window);
                    }
                }
            },
            'P' => {
                if (INTERNAL and is_down) {
                    paused = !paused;
                }
            },
            'L' => {
                if (INTERNAL and is_down) {
                    if (alt_was_down) {
                        beginInputPlayback(state, 1);
                    } else {
                        if (state.input_recording_index == 0 and state.input_playing_index == 0) {
                            beginRecordingInput(state, 1);
                        } else if (state.input_recording_index > 0) {
                            endRecordingInput(state);
                            beginInputPlayback(state, 1);
                        } else if (state.input_playing_index > 0) {
                            endInputPlayback(state);
                        }
                    }
                }
            },
            @intFromEnum(win32.VK_OEM_PLUS) => {
                if (INTERNAL and is_down) {
                    if (shift_was_down) {
                        open_gl.debug_light_buffer_index += 1;
                    } else {
                        open_gl.debug_light_buffer_texture_index += 1;
                    }
                }
            },
            @intFromEnum(win32.VK_OEM_MINUS) => {
                if (INTERNAL and is_down) {
                    if (shift_was_down) {
                        open_gl.debug_light_buffer_index -= 1;
                    } else {
                        open_gl.debug_light_buffer_texture_index -= 1;
                    }
                }
            },
            @intFromEnum(win32.VK_F1)...@intFromEnum(win32.VK_F12) => {
                if (is_down) {
                    if (alt_was_down and vk_code == @intFromEnum(win32.VK_F4)) {
                        running = false;
                    } else {
                        input.f_key_pressed[vk_code - @intFromEnum(win32.VK_F1) + 1] = true;
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

const opengl_flags: c_int = if (INTERNAL)
    // 0 | opengl.WGL_CONTEXT_DEBUG_BIT_ARB
    opengl.WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB | opengl.WGL_CONTEXT_DEBUG_BIT_ARB
else
    opengl.WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB;
const opengl_attribs = [_:0]c_int{
    opengl.WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
    opengl.WGL_CONTEXT_MINOR_VERSION_ARB, 3,
    opengl.WGL_CONTEXT_FLAGS_ARB,         opengl_flags,
    // opengl.WGL_CONTEXT_PROFILE_MASK_ARB,  opengl.WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,
    opengl.WGL_CONTEXT_PROFILE_MASK_ARB,  opengl.WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
    0,
};

fn setPixelFormat(window_dc: win32.HDC) void {
    var suggested_pixel_format_index: c_int = 0;
    var extended_pick: c_uint = 0;

    if (optWglChoosePixelFormatARB) |wglChoosePixelFormatARB| {
        var int_attrib_list = [_:0]c_int{
            opengl.WGL_DRAW_TO_WINDOW_ARB,           win32.GL_TRUE,
            opengl.WGL_ACCELERATION_ARB,             opengl.WGL_FULL_ACCELERATION_ARB,
            opengl.WGL_SUPPORT_OPENGL_ARB,           win32.GL_TRUE,
            opengl.WGL_DOUBLE_BUFFER_ARB,            win32.GL_TRUE,
            opengl.WGL_PIXEL_TYPE_ARB,               opengl.WGL_TYPE_RGBA_ARB,
            opengl.WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB, win32.GL_TRUE,
            0,
        };

        if (!open_gl.supports_srgb_frame_buffer) {
            int_attrib_list[10] = 0;
        }

        if (wglChoosePixelFormatARB(
            window_dc,
            &int_attrib_list,
            null,
            1,
            &suggested_pixel_format_index,
            &extended_pick,
        ) == 0) {
            outputLastGLError("wglChoosePixelFormatARB failed");
        }
    }

    if (extended_pick == 0) {
        var desired_pixel_format: win32.PIXELFORMATDESCRIPTOR = .{
            .nSize = @sizeOf(win32.PIXELFORMATDESCRIPTOR),
            .nVersion = 1,
            .iPixelType = win32.PFD_TYPE_RGBA,
            .dwFlags = win32.PFD_FLAGS{
                .SUPPORT_OPENGL = 1,
                .DRAW_TO_WINDOW = 1,
                .DOUBLEBUFFER = 1,
            },
            .cColorBits = 32,
            .cAlphaBits = 8,
            .cDepthBits = 24,
            .iLayerType = win32.PFD_MAIN_PLANE,
            // Clear the rest to zero.
            .cRedBits = 0,
            .cRedShift = 0,
            .cGreenBits = 0,
            .cGreenShift = 0,
            .cBlueBits = 0,
            .cBlueShift = 0,
            .cAlphaShift = 0,
            .cAccumBits = 0,
            .cAccumRedBits = 0,
            .cAccumGreenBits = 0,
            .cAccumBlueBits = 0,
            .cAccumAlphaBits = 0,
            .cStencilBits = 0,
            .cAuxBuffers = 0,
            .bReserved = 0,
            .dwLayerMask = 0,
            .dwVisibleMask = 0,
            .dwDamageMask = 0,
        };

        suggested_pixel_format_index = win32.ChoosePixelFormat(window_dc, &desired_pixel_format);
        if (suggested_pixel_format_index == 0) {
            outputLastError("ChoosePixelFormat failed");
        }
    }

    var suggested_pixel_format: win32.PIXELFORMATDESCRIPTOR = undefined;
    const describe_result = DescribePixelFormat(
        window_dc,
        suggested_pixel_format_index,
        @sizeOf(win32.PIXELFORMATDESCRIPTOR),
        &suggested_pixel_format,
    );
    if (describe_result == 0) {
        outputLastError("DescribePixelFormat failed");
    }

    if (win32.SetPixelFormat(window_dc, suggested_pixel_format_index, &suggested_pixel_format) == 0) {
        outputLastError("SetPixelFormat failed");
    }
}

fn loadWglExtensions() void {
    const window_class: win32.WNDCLASSW = .{
        .style = .{ .HREDRAW = 1, .VREDRAW = 1 },
        .lpfnWndProc = win32.DefWindowProcW,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = win32.GetModuleHandleW(null),
        .hIcon = null,
        .hbrBackground = win32.GetStockObject(win32.BLACK_BRUSH),
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeZigWglLoaderWindowClass"),
    };

    if (win32.RegisterClassW(&window_class) != 0) {
        const opt_window = win32.CreateWindowExW(
            .{},
            window_class.lpszClassName,
            win32.L("Handmade Zig WglLoader"),
            win32.WINDOW_STYLE{},
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            window_class.hInstance,
            null,
        );

        if (opt_window) |dummy_window| {
            if (win32.GetDC(dummy_window)) |dummy_window_dc| {
                setPixelFormat(dummy_window_dc);

                const opengl_rc = win32.wglCreateContext(dummy_window_dc);
                if (win32.wglMakeCurrent(dummy_window_dc, opengl_rc) != 0) {
                    optWglCreateContextAttribsARB = @ptrCast(win32.wglGetProcAddress("wglCreateContextAttribsARB"));
                    optWglChoosePixelFormatARB = @ptrCast(win32.wglGetProcAddress("wglChoosePixelFormatARB"));
                    optWglGetExtensionsStringEXT = @ptrCast(win32.wglGetProcAddress("wglGetExtensionsStringEXT"));

                    if (optWglGetExtensionsStringEXT) |wglGetExtensionsStringEXT| {
                        const extensions = wglGetExtensionsStringEXT(dummy_window_dc);

                        var at: [*]const u8 = @ptrCast(extensions);
                        while (at[0] != 0) {
                            while (shared.isWhitespace(at[0])) {
                                at += 1;
                            }
                            var end = at;
                            while (end[0] != 0 and !shared.isWhitespace(end[0])) {
                                end += 1;
                            }

                            const count = @intFromPtr(end) - @intFromPtr(at);

                            if (shared.stringsWithOneLengthAreEqual(at, count, "WGL_EXT_framebuffer_sRGB") or
                                shared.stringsWithOneLengthAreEqual(at, count, "WGL_ARB_framebuffer_sRGB"))
                            {
                                open_gl.supports_srgb_frame_buffer = true;
                            }

                            at = end;
                        }
                    }

                    _ = win32.wglMakeCurrent(null, null);
                }

                _ = win32.wglDeleteContext(opengl_rc);
                _ = win32.ReleaseDC(dummy_window, dummy_window_dc);
            }

            _ = win32.DestroyWindow(dummy_window);
        }
    }
}

fn initOpenGL(opt_window_dc: ?win32.HDC) ?win32.HGLRC {
    var opengl_rc: ?win32.HGLRC = null;

    loadWglExtensions();

    if (opt_window_dc) |window_dc| {
        setPixelFormat(window_dc);

        var is_modern_context: bool = true;

        if (optWglCreateContextAttribsARB) |wglCreateContextAttribsARB| {
            opengl_rc = wglCreateContextAttribsARB(window_dc, null, &opengl_attribs);

            if (opengl_rc == null) {
                outputLastGLError("Failed to create modern context");
            }
        }

        if (opengl_rc == null) {
            is_modern_context = false;
            opengl_rc = win32.wglCreateContext(window_dc);
        }

        if (win32.wglMakeCurrent(window_dc, opengl_rc) != 0) {
            optGLGetStringi = @ptrCast(win32.wglGetProcAddress("glGetStringi"));
            std.debug.assert(optGLGetStringi != null);

            const info = opengl.Info.get(is_modern_context);

            if (info.gl_arb_framebuffer_object) {
                optGLBindFramebufferEXT = @ptrCast(win32.wglGetProcAddress("glBindFramebufferEXT"));
                optGLGenFramebuffersEXT = @ptrCast(win32.wglGetProcAddress("glGenFramebuffersEXT"));
                optGLDeleteFramebuffersEXT = @ptrCast(win32.wglGetProcAddress("glDeleteFramebuffersEXT"));
                optGLFrameBufferTexture2DEXT = @ptrCast(win32.wglGetProcAddress("glFramebufferTexture2D"));
                optGLCheckFramebufferStatusEXT = @ptrCast(win32.wglGetProcAddress("glCheckFramebufferStatusEXT"));

                std.debug.assert(optGLBindFramebufferEXT != null);
                std.debug.assert(optGLGenFramebuffersEXT != null);
                std.debug.assert(optGLDeleteFramebuffersEXT != null);
                std.debug.assert(optGLFrameBufferTexture2DEXT != null);
                std.debug.assert(optGLCheckFramebufferStatusEXT != null);
            }

            optGLTexImage2DMultiSample = @ptrCast(win32.wglGetProcAddress("glTexImage2DMultisample"));
            optGLBlitFrameBuffer = @ptrCast(win32.wglGetProcAddress("glBlitFramebuffer"));
            optGLCreateShader = @ptrCast(win32.wglGetProcAddress("glCreateShader"));
            optGLDeleteShader = @ptrCast(win32.wglGetProcAddress("glDeleteShader"));
            optGLShaderSource = @ptrCast(win32.wglGetProcAddress("glShaderSource"));
            optGLCompileShader = @ptrCast(win32.wglGetProcAddress("glCompileShader"));
            optGLCreateProgram = @ptrCast(win32.wglGetProcAddress("glCreateProgram"));
            optGLDeleteProgram = @ptrCast(win32.wglGetProcAddress("glDeleteProgram"));
            optGLLinkProgram = @ptrCast(win32.wglGetProcAddress("glLinkProgram"));
            optGLAttachShader = @ptrCast(win32.wglGetProcAddress("glAttachShader"));
            optGLValidateProgram = @ptrCast(win32.wglGetProcAddress("glValidateProgram"));
            optGLGetProgramiv = @ptrCast(win32.wglGetProcAddress("glGetProgramiv"));
            optGLGetShaderInfoLog = @ptrCast(win32.wglGetProcAddress("glGetShaderInfoLog"));
            optGLGetProgramInfoLog = @ptrCast(win32.wglGetProcAddress("glGetProgramInfoLog"));
            optGLUseProgram = @ptrCast(win32.wglGetProcAddress("glUseProgram"));
            optGLUniformMatrix4fv = @ptrCast(win32.wglGetProcAddress("glUniformMatrix4fv"));
            optGLUniform1f = @ptrCast(win32.wglGetProcAddress("glUniform1f"));
            optGLUniform2fv = @ptrCast(win32.wglGetProcAddress("glUniform2fv"));
            optGLUniform3fv = @ptrCast(win32.wglGetProcAddress("glUniform3fv"));
            optGLUniform4fv = @ptrCast(win32.wglGetProcAddress("glUniform4fv"));
            optGLUniform1i = @ptrCast(win32.wglGetProcAddress("glUniform1i"));
            optGLGetUniformLocation = @ptrCast(win32.wglGetProcAddress("glGetUniformLocation"));
            optGLGetAttribLocation = @ptrCast(win32.wglGetProcAddress("glGetAttribLocation"));
            optGLEnableVertexAttribArray = @ptrCast(win32.wglGetProcAddress("glEnableVertexAttribArray"));
            optGLDisableVertexAttribArray = @ptrCast(win32.wglGetProcAddress("glDisableVertexAttribArray"));
            optGLVertexAttribPointer = @ptrCast(win32.wglGetProcAddress("glVertexAttribPointer"));
            optGLVertexAttribIPointer = @ptrCast(win32.wglGetProcAddress("glVertexAttribIPointer"));
            optGLGenVertexArrays = @ptrCast(win32.wglGetProcAddress("glGenVertexArrays"));
            optGLBindVertexArray = @ptrCast(win32.wglGetProcAddress("glBindVertexArray"));
            optGLDrawArrays = @ptrCast(win32.wglGetProcAddress("glDrawArrays"));
            optGLDebugMessageCallbackARB = @ptrCast(win32.wglGetProcAddress("glDebugMessageCallbackARB"));
            optGLDebugMessageControlARB = @ptrCast(win32.wglGetProcAddress("glDebugMessageControlARB"));
            optGLGenBuffers = @ptrCast(win32.wglGetProcAddress("glGenBuffers"));
            optGLBindBuffer = @ptrCast(win32.wglGetProcAddress("glBindBuffer"));
            optGLBufferData = @ptrCast(win32.wglGetProcAddress("glBufferData"));
            optGLActiveTexture = @ptrCast(win32.wglGetProcAddress("glActiveTexture"));
            optGLDrawBuffers = @ptrCast(win32.wglGetProcAddress("glDrawBuffers"));
            optGLBindFragDataLocation = @ptrCast(win32.wglGetProcAddress("glBindFragDataLocation"));
            optGLTexImage3D = @ptrCast(win32.wglGetProcAddress("glTexImage3D"));
            optGLTexSubImage3D = @ptrCast(win32.wglGetProcAddress("glTexSubImage3D"));

            std.debug.assert(optGLTexImage2DMultiSample != null);
            std.debug.assert(optGLBlitFrameBuffer != null);
            std.debug.assert(optGLCreateShader != null);
            std.debug.assert(optGLDeleteShader != null);
            std.debug.assert(optGLShaderSource != null);
            std.debug.assert(optGLCompileShader != null);
            std.debug.assert(optGLCreateProgram != null);
            std.debug.assert(optGLDeleteProgram != null);
            std.debug.assert(optGLLinkProgram != null);
            std.debug.assert(optGLAttachShader != null);
            std.debug.assert(optGLValidateProgram != null);
            std.debug.assert(optGLGetProgramiv != null);
            std.debug.assert(optGLGetShaderInfoLog != null);
            std.debug.assert(optGLGetProgramInfoLog != null);
            std.debug.assert(optGLUseProgram != null);
            std.debug.assert(optGLUniformMatrix4fv != null);
            std.debug.assert(optGLUniform1f != null);
            std.debug.assert(optGLUniform2fv != null);
            std.debug.assert(optGLUniform3fv != null);
            std.debug.assert(optGLUniform4fv != null);
            std.debug.assert(optGLUniform1i != null);
            std.debug.assert(optGLGetUniformLocation != null);
            std.debug.assert(optGLGetAttribLocation != null);
            std.debug.assert(optGLEnableVertexAttribArray != null);
            std.debug.assert(optGLDisableVertexAttribArray != null);
            std.debug.assert(optGLVertexAttribPointer != null);
            std.debug.assert(optGLVertexAttribIPointer != null);
            std.debug.assert(optGLGenVertexArrays != null);
            std.debug.assert(optGLBindVertexArray != null);
            std.debug.assert(optGLDrawArrays != null);
            std.debug.assert(optGLDebugMessageCallbackARB != null);
            std.debug.assert(optGLDebugMessageControlARB != null);
            std.debug.assert(optGLGenBuffers != null);
            std.debug.assert(optGLBindBuffer != null);
            std.debug.assert(optGLBufferData != null);
            std.debug.assert(optGLActiveTexture != null);
            std.debug.assert(optGLDrawBuffers != null);
            std.debug.assert(optGLBindFragDataLocation != null);
            std.debug.assert(optGLTexImage3D != null);
            std.debug.assert(optGLTexSubImage3D != null);

            optWglSwapIntervalEXT = @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT"));
            if (optWglSwapIntervalEXT) |wglSwapIntervalEXT| {
                _ = wglSwapIntervalEXT(1);
            }

            opengl.init(info, open_gl.supports_srgb_frame_buffer);
        } else {
            outputLastGLError("Failed to make modern context current");
        }
    }

    return opengl_rc;
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
    if (buffer.memory) |mem| {
        _ = win32.VirtualFree(mem, 0, win32.MEM_RELEASE);
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
    buffer.memory = win32.VirtualAlloc(
        null,
        bitmap_memory_size,
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    );
}

fn getGameBuffer() shared.OffscreenBuffer {
    return shared.OffscreenBuffer{
        .memory = back_buffer.memory,
        .width = back_buffer.width,
        .height = back_buffer.height,
        .pitch = back_buffer.pitch,
    };
}

fn displayBufferInWindow(
    render_queue: *shared.PlatformWorkQueue,
    commands: *shared.RenderCommands,
    device_context: ?win32.HDC,
    draw_region: Rectangle2i,
    temp_arena: *MemoryArena,
    window_width: i32,
    window_height: i32,
) void {
    var temporary_memory: memory.TemporaryMemory = undefined;
    if (DEBUG) {
        // TODO: Unclear why this has to be avoided in release mode.
        temporary_memory = temp_arena.beginTemporaryMemory();
    }

    // TODO: Do we want to check for resources like before?
    // if (render_group.allResourcesPresent()) {
    //     render_group.renderToOutput(transient_state.high_priority_queue, draw_buffer, &transient_state.arena);
    // }

    if (software_rendering) {
        var output_target: asset.LoadedBitmap = .{
            .memory = @ptrCast(back_buffer.memory.?),
            .width = @intCast(back_buffer.width),
            .height = @intCast(back_buffer.height),
            .pitch = @intCast(back_buffer.pitch),
        };
        render.softwareRenderCommands(render_queue, commands, &output_target, temp_arena);

        opengl.displayBitmap(
            back_buffer.width,
            back_buffer.height,
            draw_region,
            output_target.pitch,
            back_buffer.memory,
            commands.clear_color,
            open_gl.reserved_blit_texture,
        );
        _ = win32.SwapBuffers(device_context.?);
    } else {
        TimedBlock.beginBlock(@src(), .OpenGLRenderCommands);
        opengl.renderCommands(commands, draw_region, window_width, window_height);
        TimedBlock.endBlock(@src(), .OpenGLRenderCommands);

        TimedBlock.beginBlock(@src(), .SwapBuffers);
        _ = win32.SwapBuffers(device_context.?);
        TimedBlock.endBlock(@src(), .SwapBuffers);
    }

    if (DEBUG) {
        temp_arena.endTemporaryMemory(temporary_memory);
    }
}

fn windowProcedure(
    window: win32.HWND,
    message: u32,
    w_param: win32.WPARAM,
    l_param: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_QUIT, win32.WM_CLOSE, win32.WM_DESTROY => {
            running = false;
        },
        win32.WM_WINDOWPOSCHANGING => {
            var mutable_l_param: win32.LPARAM = l_param;

            if (win32.GetKeyState(@intFromEnum(win32.VK_SHIFT)) & (1 << 7) != 0) {
                var new_pos: *win32.WINDOWPOS = @ptrCast(&mutable_l_param);
                var window_rect: win32.RECT = undefined;
                var client_rect: win32.RECT = undefined;
                if (win32.GetWindowRect(window, &window_rect) == 1) {
                    if (win32.GetClientRect(window, &client_rect) == 1) {
                        const client_width = (client_rect.right - client_rect.left);
                        const client_height = (client_rect.bottom - client_rect.top);
                        const width_add = (window_rect.right - window_rect.left) - client_width;
                        const height_add = (window_rect.bottom - window_rect.top) - client_height;
                        const render_width = back_buffer.width;
                        const render_height = back_buffer.height;
                        const new_cx = @divFloor((render_width * (new_pos.cy - height_add)), render_height);
                        const new_cy = @divFloor((render_height * (new_pos.cx - width_add)), render_width);

                        if (@abs(new_pos.cx - new_cx) > @abs(new_pos.cy - new_cy)) {
                            new_pos.cx = new_cx + width_add;
                        } else {
                            new_pos.cy = new_cy + height_add;
                        }

                        mutable_l_param = @as(*win32.LPARAM, @ptrCast(new_pos)).*;
                    }
                }
            }

            if (l_param != mutable_l_param) {
                std.log.info("l_param changed", .{});
            }

            result = win32.DefWindowProcW(window, message, w_param, mutable_l_param);
        },
        win32.WM_SETCURSOR => {
            if (show_debug_cursor) {
                _ = win32.SetCursor(win32.LoadCursorW(null, win32.IDC_ARROW));
                // result = win32.DefWindowProcW(window, message, w_param, l_param);
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
            result = 1;
        },
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const opt_device_context: ?win32.HDC = win32.BeginPaint(window, &paint);
            _ = opt_device_context;
            // if (opt_device_context) |device_context| {
            //     const window_dimension = getWindowDimension(window);
            //     displayBufferInWindow(&back_buffer, device_context, window, window_dimension.width, window_dimension.height);
            // }
            _ = win32.EndPaint(window, &paint);
        },
        win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYDOWN, win32.WM_KEYUP => {
            // No keyboard input should come from anywhere other than the main loop.
            std.debug.assert(false);
        },
        else => {
            result = win32.DefWindowProcW(window, message, w_param, l_param);
        },
    }

    return result;
}

fn toggleFullscreen(window: win32.HWND) void {
    const style = win32.GetWindowLongW(window, win32.GWL_STYLE);

    if ((style & @as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW))) != 0) {
        var monitor_info: win32.MONITORINFO = undefined;
        monitor_info.cbSize = @sizeOf(win32.MONITORINFO);

        if (win32.GetWindowPlacement(window, &window_placement) != 0 and
            win32.GetMonitorInfoW(win32.MonitorFromWindow(window, win32.MONITOR_DEFAULTTOPRIMARY), &monitor_info) != 0)
        {
            // Set fullscreen.
            _ = win32.SetWindowLongW(window, win32.GWL_STYLE, style & ~@as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW)));
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
        _ = win32.SetWindowLongW(window, win32.GWL_STYLE, style | @as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW)));
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

var integrity_fail_counter: u32 = 0;
fn verifyMemoryListIntegrity() void {
    global_state.memory_mutex.begin();
    defer global_state.memory_mutex.end();

    const sentinel: *MemoryBlock = &global_state.memory_sentinel;
    var source_block = sentinel.next;
    while (source_block != sentinel) : (source_block = source_block.next) {
        std.debug.assert(source_block.block.size <= std.math.maxInt(u32));
    }

    integrity_fail_counter += 1;
}

fn beginRecordingInput(state: *Win32State, input_recording_index: u32) void {
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

    if (state.playback_handle != win32.INVALID_HANDLE_VALUE) {
        state.input_recording_index = input_recording_index;

        var bytes_written: u32 = undefined;
        const sentinel: *MemoryBlock = &global_state.memory_sentinel;

        global_state.memory_mutex.begin();
        var source_block = sentinel.next;
        while (source_block != sentinel) : (source_block = source_block.next) {
            if ((source_block.block.flags & @intFromEnum(PlatformMemoryBlockFlags.NotRestored)) == 0) {
                const base_pointer = source_block.block.base;
                var dest_block: SavedMemoryBlock = .{
                    .base_pointer = @intFromPtr(base_pointer),
                    .size = source_block.block.size,
                };
                _ = win32.WriteFile(
                    state.recording_handle,
                    &dest_block,
                    @sizeOf(SavedMemoryBlock),
                    &bytes_written,
                    null,
                );

                std.debug.assert(dest_block.size <= std.math.maxInt(u32));

                _ = win32.WriteFile(
                    state.recording_handle,
                    base_pointer,
                    @intCast(dest_block.size),
                    &bytes_written,
                    null,
                );
            }
        }
        global_state.memory_mutex.end();

        var dest_block: SavedMemoryBlock = .{};
        _ = win32.WriteFile(
            state.recording_handle,
            &dest_block,
            @sizeOf(SavedMemoryBlock),
            &bytes_written,
            null,
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

fn clearBlocksByMask(state: *Win32State, mask: u64) void {
    var block_iter: *MemoryBlock = state.memory_sentinel.next;
    while (block_iter != &state.memory_sentinel) {
        const block = block_iter;
        block_iter = block_iter.next;

        if ((block.looping_flags & mask) == mask) {
            freeMemoryBlock(block);
        } else {
            block.looping_flags = 0;
        }
    }
}

fn beginInputPlayback(state: *Win32State, input_playing_index: u32) void {
    clearBlocksByMask(state, @intFromEnum(MemoryBlockLoopingFlag.AllocatedDuringLooping));

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

    if (state.playback_handle != win32.INVALID_HANDLE_VALUE) {
        state.input_playing_index = input_playing_index;

        while (true) {
            var block: SavedMemoryBlock = .{};
            var bytes_read: u32 = undefined;
            _ = win32.ReadFile(
                state.playback_handle,
                &block,
                @sizeOf(SavedMemoryBlock),
                &bytes_read,
                null,
            );

            if (block.base_pointer != 0) {
                std.debug.assert(block.size <= std.math.maxInt(u32));

                _ = win32.ReadFile(
                    state.playback_handle,
                    @ptrFromInt(block.base_pointer),
                    @intCast(block.size),
                    &bytes_read,
                    null,
                );
            } else {
                break;
            }
        }
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
    clearBlocksByMask(state, @intFromEnum(MemoryBlockLoopingFlag.FreedDuringLooping));

    _ = win32.CloseHandle(state.playback_handle);
    state.input_playing_index = 0;
    state.playback_handle = undefined;
}

fn makeQueue(queue: *shared.PlatformWorkQueue, thread_count: i32, startups: [*]ThreadStartup) void {
    const initial_count = 0;
    const opt_semaphore_handle = win32.CreateSemaphoreExA(
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
            var startup: [*]ThreadStartup = startups + thread_index;
            startup[0].queue = queue;

            const thread_handle = win32.CreateThread(
                null,
                0,
                threadProc,
                @ptrCast(@constCast(startup)),
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
) callconv(.c) void {
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

pub fn completeAllQueuedWork(queue: *shared.PlatformWorkQueue) callconv(.c) void {
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

fn threadProc(lp_parameter: ?*anyopaque) callconv(.c) u32 {
    if (lp_parameter) |parameter| {
        const thread: *ThreadStartup = @ptrCast(@alignCast(parameter));
        const queue: *shared.PlatformWorkQueue = thread.queue;

        while (true) {
            if (doNextWorkQueueEntry(queue)) {
                _ = win32.WaitForSingleObjectEx(queue.semaphore_handle, std.math.maxInt(u32), 0);
            }
        }
    }

    return 0;
}

fn outputLastError(title: []const u8) void {
    const last_error = win32.GetLastError();

    if (INTERNAL) {
        std.debug.print("{s}: {d}\n", .{ title, @intFromEnum(last_error) });
    } else {
        var buffer: [128]u8 = undefined;
        const length = shared.formatString(buffer.len, &buffer, "%s: %d\n", .{
            title,
            @intFromEnum(last_error),
        });
        win32.OutputDebugStringA(@ptrCast(buffer[0..length]));
    }
}

pub fn outputLastGLError(title: []const u8) void {
    const last_error = win32.glGetError();

    if (INTERNAL) {
        std.debug.print("{s}: {d}\n", .{ title, last_error });
    } else {
        var buffer: [128]u8 = undefined;
        const length = shared.formatString(buffer.len, &buffer, "{s}: {d}\n", .{ title, last_error });
        win32.OutputDebugStringA(@ptrCast(buffer[0..length]));
    }
}

fn fullRestart(source_exe: [*:0]const u8, dest_exe: [*:0]const u8, delete_exe: [*:0]const u8) void {
    _ = win32.DeleteFileA(delete_exe);

    if (win32.MoveFileA(dest_exe, delete_exe) != 0) {
        if (win32.MoveFileA(source_exe, dest_exe) != 0) {
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
                dest_exe,
                win32.GetCommandLineA(),
                null,
                null,
                win32.FALSE,
                win32.PROCESS_CREATION_FLAGS{},
                null,
                "C:\\", // TODO: Specify the full path to the data directory here.
                &startup_info,
                &process_info,
            ) != 0) {
                if (process_info.hProcess) |process_handle| {
                    _ = win32.CloseHandle(process_handle);
                }
            } else {
                std.log.err("Error performing full restart: {d}", .{@intFromEnum(win32.GetLastError())});
            }

            win32.ExitProcess(0);
        }
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

    global_debug_table.setEventRecording(true);
    var state: *Win32State = &global_state;
    state.memory_sentinel.prev = &state.memory_sentinel;
    state.memory_sentinel.next = &state.memory_sentinel;

    getExeFileName(state);

    if (INTERNAL) {
        shared.global_debug_table = global_debug_table;
    }

    var exe_full_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
    buildExePathFileName(state, "handmade-zig.exe", &exe_full_path);
    var temp_exe_full_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
    buildExePathFileName(state, "handmade-zig-temp.exe", &temp_exe_full_path);
    var delete_exe_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
    buildExePathFileName(state, "handmade-zig-old.exe", &delete_exe_path);

    var source_dll_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
    buildExePathFileName(state, "handmade.dll", &source_dll_path);
    var temp_dll_path = [_:0]u8{0} ** STATE_FILE_NAME_COUNT;
    buildExePathFileName(state, "handmade_temp.dll", &temp_dll_path);

    var performance_frequency: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&performance_frequency);
    perf_count_frequency = performance_frequency.QuadPart;

    // Set the Windows schedular granularity so that our Sleep() call can be more grannular.
    const desired_scheduler_ms = 1;
    const sleep_is_grannular = win32.timeBeginPeriod(desired_scheduler_ms) == win32.TIMERR_NOERROR;

    loadXInput();

    resizeDIBSection(&back_buffer, WIDTH, HEIGHT);
    platform = shared.Platform{
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
    shared.platform = platform;

    if (INTERNAL) {
        platform.debugFreeFileMemory = DebugFunctions.debugFreeFileMemory;
        platform.debugReadEntireFile = DebugFunctions.debugReadEntireFile;
        platform.debugWriteEntireFile = DebugFunctions.debugWriteEntireFile;
        platform.debugExecuteSystemCommand = DebugFunctions.debugExecuteSystemCommand;
        platform.debugGetProcessState = DebugFunctions.debugGetProcessState;
        platform.debugGetMemoryStats = DebugFunctions.debugGetMemoryStats;
    }

    const window_class: win32.WNDCLASSW = .{
        .style = .{ .HREDRAW = 1, .VREDRAW = 1, .OWNDC = 1 },
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
            if (!INTERNAL) {
                toggleFullscreen(window_handle);
            }
            const window_dc = win32.GetDC(window_handle);
            _ = initOpenGL(window_dc);

            var high_priority_startups: [6]ThreadStartup = [1]ThreadStartup{ThreadStartup{}} ** 6;
            var high_priority_queue = shared.PlatformWorkQueue{};
            makeQueue(&high_priority_queue, high_priority_startups.len, @ptrCast(&high_priority_startups));

            var low_priority_startups: [2]ThreadStartup = [1]ThreadStartup{ThreadStartup{}} ** 2;
            var low_priority_queue = shared.PlatformWorkQueue{};
            makeQueue(&low_priority_queue, low_priority_startups.len, @ptrCast(&low_priority_startups));

            if (INTERNAL) {
                _ = win32.SetLayeredWindowAttributes(window_handle, 0, DEBUG_WINDOW_ACTIVE_OPACITY, win32.LWA_ALPHA);
            }

            var monitor_refresh_hz: i32 = 60;
            const device_context = win32.GetDC(window_handle);
            const device_refresh_rate = win32.GetDeviceCaps(device_context, win32.VREFRESH);
            if (device_refresh_rate > 0) {
                monitor_refresh_hz = device_refresh_rate;
            }

            const game_update_hz: f32 = @floatFromInt(monitor_refresh_hz);

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
                .debug_table = if (INTERNAL) global_debug_table else undefined,
                .high_priority_queue = &high_priority_queue,
                .low_priority_queue = &low_priority_queue,
                .debug_state = null,
            };

            const texture_op_count: u32 = 1024;
            var texture_op_queue: *shared.PlatformTextureOpQueue = &game_memory.texture_op_queue;
            texture_op_queue.first_free = @ptrCast(@alignCast(win32.VirtualAlloc(
                null,
                @sizeOf(render.TextureOp) * texture_op_count,
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            )));

            var texture_op_index: u32 = 0;
            while (texture_op_index < (texture_op_count - 1)) : (texture_op_index += 1) {
                const first_free: [*]render.TextureOp = @ptrCast(game_memory.texture_op_queue.first_free.?);
                var op: [*]render.TextureOp = first_free + texture_op_index;
                op[0].next = @ptrCast(first_free + texture_op_index + 1);
            }

            if (samples != null) {
                // TODO: This currently doesn't support connecting controllers after the game has started.
                var xbox_controller_present: [win32.XUSER_MAX_COUNT]bool = [1]bool{true} ** win32.XUSER_MAX_COUNT;
                var game_input = [1]shared.GameInput{shared.GameInput{}} ** 2;
                var new_input = &game_input[0];
                var old_input = &game_input[1];

                // Initialize timing.
                var last_counter: win32.LARGE_INTEGER = getWallClock();
                var flip_wall_clock: win32.LARGE_INTEGER = getWallClock();

                // Load the game code.
                var game = loadGameCode(&source_dll_path, &temp_dll_path);
                global_debug_table.setEventRecording(game.is_valid);

                running = true;

                var frame_temp_arena: MemoryArena = .{};
                const push_buffer_size: u32 = shared.megabytes(64);
                const push_buffer_block: ?*PlatformMemoryBlock = allocateMemory(
                    push_buffer_size,
                    @intFromEnum(PlatformMemoryBlockFlags.NotRestored),
                );
                const push_buffer = push_buffer_block.?.base;

                const max_vertex_count: u32 = 65536;
                const vertex_array_block: ?*PlatformMemoryBlock = allocateMemory(
                    max_vertex_count * @sizeOf(TexturedVertex),
                    @intFromEnum(PlatformMemoryBlockFlags.NotRestored),
                );
                const vertex_array: [*]TexturedVertex = @ptrCast(@alignCast(vertex_array_block.?.base));
                const bitmap_array_block: ?*PlatformMemoryBlock = allocateMemory(
                    max_vertex_count * @sizeOf(LoadedBitmap),
                    @intFromEnum(PlatformMemoryBlockFlags.NotRestored),
                );
                const bitmap_array: [*]?*LoadedBitmap = @ptrCast(@alignCast(bitmap_array_block.?.base));
                const surfaces: [*]LightingSurface = @ptrCast(@alignCast(allocateMemory(
                    LIGHT_DATA_WIDTH * @sizeOf(LightingSurface),
                    @intFromEnum(PlatformMemoryBlockFlags.NotRestored),
                ).?.base));
                const light_points: [*]LightingPoint = @ptrCast(@alignCast(allocateMemory(
                    LIGHT_DATA_WIDTH * @sizeOf(LightingPoint),
                    @intFromEnum(PlatformMemoryBlockFlags.NotRestored),
                ).?.base));
                const emission_color0: [*]math.Color3 = @ptrCast(@alignCast(allocateMemory(
                    LIGHT_DATA_WIDTH * @sizeOf(math.Color3),
                    @intFromEnum(PlatformMemoryBlockFlags.NotRestored),
                ).?.base));

                var render_commands: shared.RenderCommands = shared.RenderCommands.default(
                    push_buffer_size,
                    push_buffer,
                    @intCast(back_buffer.width),
                    @intCast(back_buffer.height),
                    max_vertex_count,
                    vertex_array,
                    bitmap_array,
                    &open_gl.white_bitmap,
                    surfaces,
                    light_points,
                    emission_color0,
                );

                _ = win32.ShowWindow(window_handle, win32.SW_SHOW);

                var expected_frames_per_update: u32 = 1;
                var target_seconds_per_frame: f32 =
                    @as(f32, @floatFromInt(expected_frames_per_update)) / game_update_hz;
                while (running) {
                    DebugInterface.debugBeginDataBlock(@src(), "Platform");
                    {
                        DebugInterface.debugValue(@src(), &expected_frames_per_update, "expected_frames_per_update");
                    }
                    DebugInterface.debugEndDataBlock(@src());

                    DebugInterface.debugBeginDataBlock(@src(), "Platform/Controls");
                    {
                        DebugInterface.debugValue(@src(), &paused, "paused");
                        DebugInterface.debugValue(@src(), &software_rendering, "software_rendering");
                    }
                    DebugInterface.debugEndDataBlock(@src());

                    //
                    //
                    //

                    new_input.frame_delta_time = target_seconds_per_frame;

                    //
                    //
                    //

                    // TimedBlock.beginBlock(@src(), .InputProcessing);
                    const window_dimension = getWindowDimension(window_handle);
                    const draw_region = render.aspectRatioFit(
                        @intCast(render_commands.settings.width),
                        @intCast(render_commands.settings.height),
                        @intCast(window_dimension.width),
                        @intCast(window_dimension.height),
                    );

                    TimedBlock.beginBlock(@src(), .ControllerClearing);
                    const old_keyboard_controller = &old_input.controllers[0];
                    var new_keyboard_controller = &new_input.controllers[0];
                    new_keyboard_controller.is_connected = true;

                    // Transfer buttons state from previous frame to this one.
                    old_keyboard_controller.copyButtonStatesTo(new_keyboard_controller);
                    old_keyboard_controller.resetButtonTransitionCounts();
                    TimedBlock.endBlock(@src(), .ControllerClearing);

                    TimedBlock.beginBlock(@src(), .MessageProcessing);
                    new_input.f_key_pressed = [1]bool{false} ** 13;
                    processPendingMessages(state, window_handle, new_keyboard_controller, new_input);
                    TimedBlock.endBlock(@src(), .MessageProcessing);

                    if (!paused) {
                        // Prepare input to game.
                        processMouseInput(
                            old_input,
                            new_input,
                            window_handle,
                            &render_commands,
                            draw_region,
                            window_dimension,
                        );
                        processXInput(&xbox_controller_present, old_input, new_input);
                    }

                    // TimedBlock.endBlock(@src(), .InputProcessing);

                    //
                    //
                    //

                    TimedBlock.beginBlock(@src(), .GameUpdate);

                    if (!paused) {
                        if (state.input_recording_index > 0) {
                            recordInput(state, new_input);
                        } else if (state.input_playing_index > 0) {
                            const temp: shared.GameInput = new_input.*;

                            playbackInput(state, new_input);

                            new_input.mouse_buttons = temp.mouse_buttons;
                            new_input.mouse_x = temp.mouse_x;
                            new_input.mouse_y = temp.mouse_y;
                            new_input.mouse_z = temp.mouse_z;
                            new_input.shift_down = temp.shift_down;
                            new_input.alt_down = temp.alt_down;
                            new_input.control_down = temp.control_down;
                        }

                        // Send all input to game.
                        game.updateAndRender.?(platform, &game_memory, new_input, &render_commands);

                        if (new_input.quit_requested) {
                            running = false;
                        }
                    }

                    TimedBlock.endBlock(@src(), .GameUpdate);

                    //
                    //
                    //

                    TimedBlock.beginBlock(@src(), .AudioUpdate);

                    // Output sound.
                    if (!paused) {
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

                                game.getSoundSamples.?(&game_memory, &sound_output_info.output_buffer);

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
                                }

                                fillSoundBuffer(&sound_output, secondary_buffer, &sound_output_info);
                            } else {
                                sound_output_info.is_valid = false;
                            }
                        }
                    }

                    TimedBlock.endBlock(@src(), .AudioUpdate);

                    //
                    //
                    //

                    if (INTERNAL) {
                        TimedBlock.beginBlock(@src(), .DebugCollation);
                        defer TimedBlock.endBlock(@src(), .DebugCollation);

                        const last_dll_write_time = getLastWriteTime(&source_dll_path);
                        const executable_needs_reloading: bool =
                            win32.CompareFileTime(&last_dll_write_time, &game.last_write_time) != 0;

                        if (false) {
                            const new_exe_time = getLastWriteTime(&exe_full_path);
                            const old_exe_time = getLastWriteTime(&temp_exe_full_path);
                            if (timeIsValid(new_exe_time)) {
                                const needs_full_reload: bool = win32.CompareFileTime(&new_exe_time, &old_exe_time) != 0;

                                if (needs_full_reload) {
                                    fullRestart(&temp_exe_full_path, &exe_full_path, &delete_exe_path);
                                }
                            }
                        }

                        game_memory.executable_reloaded = false;
                        if (executable_needs_reloading) {
                            completeAllQueuedWork(&high_priority_queue);
                            completeAllQueuedWork(&low_priority_queue);
                            global_debug_table.setEventRecording(false);
                        }

                        if (game.debugFrameEnd) |frameEndFn| {
                            frameEndFn(&game_memory, new_input.*, &render_commands);
                        }

                        if (executable_needs_reloading) {
                            unloadGameCode(&game);
                            game = loadGameCode(&source_dll_path, &temp_dll_path);
                            game_memory.executable_reloaded = true;
                            global_debug_table.setEventRecording(game.is_valid);
                        }
                    }

                    //
                    //
                    //

                    if (false) {
                        TimedBlock.beginBlock(@src(), .FrameRateWait);
                        defer TimedBlock.endBlock(@src(), .FrameRateWait);

                        if (!paused) {
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
                        }
                    }

                    //
                    //
                    //

                    TimedBlock.beginBlock(@src(), .FrameDisplay);

                    // Output game to screen.
                    texture_op_queue.mutex.begin();
                    const first_texture_op: ?*render.TextureOp = texture_op_queue.first;
                    const last_texture_op: ?*render.TextureOp = texture_op_queue.last;
                    texture_op_queue.first = null;
                    texture_op_queue.last = null;
                    texture_op_queue.mutex.end();

                    if (first_texture_op != null) {
                        std.debug.assert(last_texture_op != null);

                        opengl.manageTextures(first_texture_op);

                        texture_op_queue.mutex.begin();
                        last_texture_op.?.next = texture_op_queue.first_free;
                        texture_op_queue.first_free = first_texture_op;
                        texture_op_queue.mutex.end();
                    }

                    displayBufferInWindow(
                        &high_priority_queue,
                        &render_commands,
                        device_context,
                        draw_region,
                        &frame_temp_arena,
                        window_dimension.width,
                        window_dimension.height,
                    );
                    render_commands.reset();

                    flip_wall_clock = getWallClock();

                    // Flip the controller inputs for next frame.
                    const temp: *shared.GameInput = new_input;
                    new_input = old_input;
                    old_input = temp;

                    //
                    //
                    //

                    TimedBlock.endBlock(@src(), .FrameDisplay);

                    const end_counter = getWallClock();

                    const measured_seconds_per_frame: f32 = getSecondsElapsed(last_counter, end_counter);
                    const exact_target_frames_per_update: f32 = measured_seconds_per_frame * @as(f32, @floatFromInt(monitor_refresh_hz));
                    const new_expected_frames_per_update: u32 = intrinsics.roundReal32ToUInt32(exact_target_frames_per_update);
                    expected_frames_per_update = new_expected_frames_per_update;

                    target_seconds_per_frame = measured_seconds_per_frame;

                    TimedBlock.frameMarker(
                        @src(),
                        .TotalPlatformLoop,
                        measured_seconds_per_frame,
                    );
                    TimedBlock.endBlock(@src(), .TotalPlatformLoop);
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
