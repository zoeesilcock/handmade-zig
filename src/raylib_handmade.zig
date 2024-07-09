const rl = @import("raylib");
const shared = @import("shared.zig");
const game = @import("handmade.zig");
const std = @import("std");

const WIDTH = 960;
const HEIGHT = 540;
const BYTES_PER_PIXEL = 4;

const DEBUG_WINDOW_POS_X = 0 + 2560;
const DEBUG_WINDOW_POS_Y = 30;
const DEBUG_WINDOW_WIDTH = 1280;
const DEBUG_WINDOW_HEIGHT = 720;
const DEBUG_WINDOW_ACTIVE_OPACITY = 1.0;
const DEBUG_WINDOW_INACTIVE_OPACITY = 0.25;

// Build options.
const DEBUG = shared.DEBUG;

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
    } else |_| {}

    return result;
}

fn debugWriteEntireFile(thread: *shared.ThreadContext, file_name: [*:0]const u8, memory_size: u32, memory: *anyopaque) callconv(.C) bool {
    _ = thread;

    const data: []u8 = @as([*]u8, @ptrCast(@alignCast(memory)))[0..memory_size];
    return rl.saveFileData(std.mem.span(file_name), data);
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
    game_memory.permanent_storage = @as([*]void, @ptrCast(rl.memAlloc(@intCast(total_size))));
    game_memory.transient_storage = game_memory.permanent_storage.? + game_memory.permanent_storage_size;

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
    const window_width: i32 = if (DEBUG) DEBUG_WINDOW_WIDTH else WIDTH;
    const window_height: i32 = if (DEBUG) DEBUG_WINDOW_HEIGHT else HEIGHT;
    rl.initWindow(window_width, window_height, "Handmade Zig");

    if (DEBUG) {
        rl.setWindowPosition(DEBUG_WINDOW_POS_X, DEBUG_WINDOW_POS_Y);
        rl.setWindowState(rl.ConfigFlags{ .window_transparent = true });
    }

    defer rl.closeWindow();

    const monitor_id = rl.getCurrentMonitor();
    const monitor_refresh_hz = rl.getMonitorRefreshRate(monitor_id);
    const game_update_hz: f32 = @as(f32, @floatFromInt(monitor_refresh_hz)) / 2.0;
    const target_seconds_per_frame = 1.0 / game_update_hz;
    rl.setTargetFPS(@intFromFloat(game_update_hz));

    // Initialize input.
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
    rl.setExitKey(rl.KeyboardKey.key_null);

    rl.setTraceLogLevel(rl.TraceLogLevel.log_warning);

    var window_was_focused = rl.isWindowFocused();

    while (!rl.windowShouldClose()) {
        const old_keyboard_controller = &old_input.controllers[0];
        var new_keyboard_controller = &new_input.controllers[0];
        new_keyboard_controller.is_connected = true;

        // Transfer buttons state from previous loop to this one.
        old_keyboard_controller.copyButtonStatesTo(new_keyboard_controller);

        captureKeyboardInput(new_keyboard_controller);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        game.updateAndRender(&thread, platform, &game_memory, new_input.*, &game_buffer);

        displayBufferInWindow(&back_buffer, rl.getScreenWidth(), rl.getScreenHeight());

        rl.drawFPS(10, 10);

        // Flip the controller inputs for next frame.
        const temp: *shared.GameInput = new_input;
        new_input = old_input;
        old_input = temp;

        if (DEBUG) {
            const window_is_focused = rl.isWindowFocused();
            if (window_was_focused != window_is_focused) {
                rl.setWindowOpacity(if (window_is_focused) DEBUG_WINDOW_ACTIVE_OPACITY else DEBUG_WINDOW_INACTIVE_OPACITY);
            }
            window_was_focused = window_is_focused;
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

fn displayBufferInWindow(buffer: *OffscreenBuffer, window_width: i32, window_height: i32) void {
    var row: [*]u8 = @ptrCast(buffer.memory);
    var y: i32 = 0;
    var image = rl.genImageColor(buffer.width, buffer.height, rl.Color.black);
    while (y < buffer.height) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x: i32 = 0;
        while (x < buffer.width - 1) : (x += 1) {
            rl.imageDrawPixel(&image, x, y, handmadeColorToRaylib(pixel[0]));
            pixel += 1;
        }

        row += buffer.pitch;
    }

    const should_double_size = window_width >= buffer.width * 2 and window_height >= buffer.height * 2;
    const blit_width = if (should_double_size) buffer.width * 2 else buffer.width;
    const blit_height = if (should_double_size) buffer.height * 2 else buffer.height;
    const offset_x = @divFloor((window_width - blit_width), 2);
    const offset_y = @divFloor((window_height - blit_height), 2);

    const source = rl.Rectangle.init(0, 0, @floatFromInt(buffer.width), @floatFromInt(buffer.height));
    const dest = rl.Rectangle.init(@floatFromInt(offset_x), @floatFromInt(offset_y), @floatFromInt(blit_width), @floatFromInt(blit_height));
    rl.drawTexturePro(rl.loadTextureFromImage(image), source, dest, rl.Vector2.zero(), 0, rl.Color.white);
}

fn captureKeyboardInput(keyboard_controller: *shared.ControllerInput) void {
    processKeyboardInput(&keyboard_controller.move_up, rl.isKeyDown(rl.KeyboardKey.key_w));
    processKeyboardInput(&keyboard_controller.move_left, rl.isKeyDown(rl.KeyboardKey.key_a));
    processKeyboardInput(&keyboard_controller.move_down, rl.isKeyDown(rl.KeyboardKey.key_s));
    processKeyboardInput(&keyboard_controller.move_right, rl.isKeyDown(rl.KeyboardKey.key_d));
    processKeyboardInput(&keyboard_controller.left_shoulder, rl.isKeyDown(rl.KeyboardKey.key_q));
    processKeyboardInput(&keyboard_controller.right_shoulder, rl.isKeyDown(rl.KeyboardKey.key_e));

    processKeyboardInput(&keyboard_controller.action_up, rl.isKeyDown(rl.KeyboardKey.key_up));
    processKeyboardInput(&keyboard_controller.action_down, rl.isKeyDown(rl.KeyboardKey.key_down));
    processKeyboardInput(&keyboard_controller.action_left, rl.isKeyDown(rl.KeyboardKey.key_left));
    processKeyboardInput(&keyboard_controller.action_right, rl.isKeyDown(rl.KeyboardKey.key_right));

    processKeyboardInput(&keyboard_controller.start_button, rl.isKeyDown(rl.KeyboardKey.key_space));
    processKeyboardInput(&keyboard_controller.back_button, rl.isKeyDown(rl.KeyboardKey.key_escape));

    if (rl.isKeyPressed(rl.KeyboardKey.key_enter) and rl.isKeyDown(rl.KeyboardKey.key_left_alt)) {
        rl.toggleBorderlessWindowed();
    }
}

fn processKeyboardInput(new_state: *shared.ControllerButtonState, is_down: bool) void {
    if (new_state.ended_down != is_down) {
        new_state.ended_down = is_down;
        new_state.half_transitions += 1;
    }
}
