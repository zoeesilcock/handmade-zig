const rl = @import("raylib");
const shared = @import("shared.zig");
const game = @import("handmade.zig");
const std = @import("std");

const DEBUG = shared.DEBUG;

const WIDTH = 960;
const HEIGHT = 540;
const BYTES_PER_PIXEL = 4;

var back_buffer: OffscreenBuffer = .{
    .width = WIDTH,
    .height = HEIGHT,
};

const OffscreenBuffer = struct {
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
    bytes_per_pixel: i32 = BYTES_PER_PIXEL,
};

fn debugReadEntireFile(thread: *shared.ThreadContext, file_name: [*:0]const u8) callconv(.C) shared.DebugReadFileResult {
    _ = thread;

    var result = shared.DebugReadFileResult{};

    if (rl.loadFileData(std.mem.span(file_name))) |data| {
        result.content_size = @intCast(rl.getFileLength(std.mem.span(file_name)));
        result.contents = data.ptr;
    } else |_| {
    }

    return result;
}

fn debugWriteEntireFile(thread: *shared.ThreadContext, file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) callconv(.C) bool {
    _ = thread;
    _ = memory_size;

    _ = file_name;
    _ = memory;
    return false;

    // return rl.saveFileData(std.mem.span(file_name), @ptrCast(memory[0..0]));
}

fn debugFreeFileMemory(thread: *shared.ThreadContext, memory: *anyopaque) callconv(.C) void {
    _ = thread;

    rl.memFree(memory);
}

pub fn main() anyerror!void {
    var thread = shared.ThreadContext{};
    const platform = shared.Platform{
        .debugReadEntireFile = debugReadEntireFile,
        .debugWriteEntireFile = debugWriteEntireFile,
        .debugFreeFileMemory = debugFreeFileMemory,
    };

    // Allocate game memory.
    var game_memory: shared.Memory = shared.Memory{
        .is_initialized = false,
        .permanent_storage_size = shared.megabytes(256),
        .permanent_storage = null,
        .transient_storage_size = shared.megabytes(256),
        .transient_storage = null,
    };
    const total_size = game_memory.permanent_storage_size + game_memory.transient_storage_size;
    // const base_address = if (DEBUG) @as(*u8, @ptrFromInt(shared.terabytes(2))) else null;
    game_memory.permanent_storage = rl.memAlloc(@intCast(total_size));
    game_memory.transient_storage = @ptrFromInt(@intFromPtr(&game_memory.permanent_storage) + game_memory.permanent_storage_size);

    // TODO: Capture input
    const input: shared.GameInput = shared.GameInput{};

    // Create the back buffer.
    const bitmap_memory_size: usize = @intCast((back_buffer.width * back_buffer.height) * BYTES_PER_PIXEL);
    back_buffer.memory = rl.memAlloc(@intCast(bitmap_memory_size));
    back_buffer.pitch = @intCast(back_buffer.width * BYTES_PER_PIXEL);
    var game_buffer = shared.OffscreenBuffer{
        .memory = back_buffer.memory,
        .width = back_buffer.width,
        .height = back_buffer.height,
        .pitch = back_buffer.pitch,
        .bytes_per_pixel = back_buffer.bytes_per_pixel,
    };

    // Create the window.
    rl.initWindow(WIDTH, HEIGHT, "Handmade Zig");
    defer rl.closeWindow();

    rl.setTargetFPS(30);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        game.updateAndRender(&thread, platform, &game_memory, input, &game_buffer);

        // Blit the graphics to the screen.
        var row: [*]u8 = @ptrCast(game_buffer.memory);
        var y: i32 = 0;
        while (y < game_buffer.height) : (y += 1) {
            var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

            var x: i32 = 0;
            while (x < game_buffer.width - 1) : (x += 1) {
                rl.drawPixel(x, y, handmadeColorToRaylib(pixel[0]));
                pixel += 1;
            }

            row += game_buffer.pitch;
        }

    }
}

fn handmadeColorToRaylib(color: u32) rl.Color {
    return rl.Color{
        .r = @truncate((color) >> 16),
        .g = @truncate((color) >> 8),
        .b = @truncate((color) >> 0),
        .a = 255,
    };
}
