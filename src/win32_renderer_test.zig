const std = @import("std");
const win32 = @import("win32").everything;
const math = @import("math.zig");
const types = @import("types.zig");
const intrinsics = @import("intrinsics.zig");
const renderer = @import("renderer.zig");
const opengl = @import("renderer_opengl.zig");
const wgl = @import("win32_opengl.zig");

// Build options.
pub const INTERNAL = @import("build_options").internal;

// Types.
const Color = math.Color;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Matrix4x4 = math.Matrix4x4;
const Rectangle2i = math.Rectangle2i;
const RenderCommands = renderer.RenderCommands;
const RenderGroup = renderer.RenderGroup;
const TexturedVertex = renderer.TexturedVertex;
const RendererTexture = renderer.RendererTexture;
const CameraParams = renderer.CameraParams;

const EntireFile = struct {
    content_size: u32 = 0,
    contents: []const u8 = undefined,
};

const BitmapHeader = packed struct {
    file_type: u16,
    file_size: u32,
    reserved1: u16,
    reserved2: u16,
    bitmap_offset: u32,
    size: u32,
    width: i32,
    height: i32,
    planes: u16,
    bits_per_pxel: u16,
    compression: u32,
    size_of_bitmap: u32,
    horz_resolution: i32,
    vert_resolution: i32,
    colors_used: u32,
    colors_important: u32,
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
};

const LoadedBitmap = extern struct {
    memory: ?[*]void,
    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
};

// Globals.
var running: bool = false;
var open_gl = &opengl.open_gl;

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
        win32.WM_SIZE => {},
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const opt_device_context: ?win32.HDC = win32.BeginPaint(window, &paint);
            _ = opt_device_context;
            _ = win32.EndPaint(window, &paint);
        },
        else => {
            result = win32.DefWindowProcW(window, message, w_param, l_param);
        },
    }

    return result;
}

fn processPendingMessages() void {
    var message: win32.MSG = undefined;
    while (true) {
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

        if (!got_message) {
            break;
        }

        switch (message.message) {
            win32.WM_QUIT => running = false,
            else => {
                _ = win32.TranslateMessage(&message);
                _ = win32.DispatchMessageW(&message);
            },
        }
    }
}

fn allocateMemory(size: usize) ?*anyopaque {
    const result = win32.VirtualAlloc(
        null,
        size,
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    );

    return result;
}

fn readEntireFile(file_name: []const u8, allocator: std.mem.Allocator) EntireFile {
    var result = EntireFile{};

    if (std.fs.cwd().openFile(file_name, .{ .mode = .read_only })) |file| {
        defer file.close();

        _ = file.seekFromEnd(0) catch undefined;
        result.content_size = @as(u32, @intCast(file.getPos() catch 0));
        _ = file.seekTo(0) catch undefined;

        const buffer = file.readToEndAlloc(allocator, std.math.maxInt(u32)) catch "";
        result.contents = buffer;
    } else |err| {
        std.log.err("Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}

fn loadBMP(
    file_name: []const u8,
    allocator: std.mem.Allocator,
) ?LoadedBitmap {
    var result: ?LoadedBitmap = null;
    const read_result = readEntireFile(file_name, allocator);

    if (read_result.content_size > 0) {
        const header = @as(*BitmapHeader, @ptrCast(@alignCast(@constCast(read_result.contents))));

        std.debug.assert(header.height >= 0);
        std.debug.assert(header.compression == 3);

        result = LoadedBitmap{
            .memory = @ptrFromInt(@intFromPtr(read_result.contents.ptr) + header.bitmap_offset),
            .width = header.width,
            .height = header.height,
        };

        const alpha_mask = ~(header.red_mask | header.green_mask | header.blue_mask);
        const alpha_scan = intrinsics.findLeastSignificantSetBit(alpha_mask);
        const red_scan = intrinsics.findLeastSignificantSetBit(header.red_mask);
        const green_scan = intrinsics.findLeastSignificantSetBit(header.green_mask);
        const blue_scan = intrinsics.findLeastSignificantSetBit(header.blue_mask);

        std.debug.assert(alpha_scan.found);
        std.debug.assert(red_scan.found);
        std.debug.assert(green_scan.found);
        std.debug.assert(blue_scan.found);

        const red_shift_down = @as(u5, @intCast(red_scan.index));
        const green_shift_down = @as(u5, @intCast(green_scan.index));
        const blue_shift_down = @as(u5, @intCast(blue_scan.index));
        const alpha_shift_down = @as(u5, @intCast(alpha_scan.index));

        var source_dest: [*]align(@alignOf(u8)) u32 = @ptrCast(result.?.memory);
        var x: u32 = 0;
        while (x < header.width) : (x += 1) {
            var y: u32 = 0;
            while (y < header.height) : (y += 1) {
                const color = source_dest[0];
                var texel = Color.new(
                    @floatFromInt((color & header.red_mask) >> red_shift_down),
                    @floatFromInt((color & header.green_mask) >> green_shift_down),
                    @floatFromInt((color & header.blue_mask) >> blue_shift_down),
                    @floatFromInt((color & alpha_mask) >> alpha_shift_down),
                );
                texel = math.sRGB255ToLinear1(texel);

                _ = texel.setRGB(texel.rgb().scaledTo(texel.a()));

                texel = math.linear1ToSRGB255(texel);

                source_dest[0] = ((@as(u32, @intFromFloat(texel.a() + 0.5)) << 24) |
                    (@as(u32, @intFromFloat(texel.r() + 0.5)) << 16) |
                    (@as(u32, @intFromFloat(texel.g() + 0.5)) << 8) |
                    (@as(u32, @intFromFloat(texel.b() + 0.5)) << 0));

                source_dest += 1;
            }
        }
    }

    result.?.pitch = result.?.width * 4;

    return result;
}

/// This is needed for it to work when lib_c is linked.
pub export fn wWinMain(
    instance: win32.HINSTANCE,
    prev_instance: ?win32.HINSTANCE,
    cmd_line: ?win32.PWSTR,
    cmd_show: c_int,
) callconv(.winapi) c_int {
    return WinMain(instance, prev_instance, cmd_line, cmd_show);
}

pub export fn WinMain(
    instance: ?win32.HINSTANCE,
    prev_instance: ?win32.HINSTANCE,
    cmd_line: ?win32.PWSTR,
    cmd_show: c_int,
) c_int {
    _ = prev_instance;
    _ = cmd_line;
    _ = cmd_show;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var perf_count_frequency: i64 = 0;
    var performance_frequency: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&performance_frequency);
    perf_count_frequency = performance_frequency.QuadPart;

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
        .lpszClassName = win32.L("HandmadeZigRendererTestWindowClass"),
    };

    var last_counter: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceCounter(&last_counter);

    if (win32.RegisterClassW(&window_class) != 0) {
        const opt_window_handle: ?win32.HWND = win32.CreateWindowExW(
            .{},
            window_class.lpszClassName,
            win32.L("Handmade Zig Renderer Test"),
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
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        );

        if (opt_window_handle) |window_handle| {
            const window_dc = win32.GetDC(window_handle);
            _ = wgl.initOpenGL(window_dc);
            running = true;

            const push_buffer_size: u32 = @intCast(types.megabytes(64));
            const push_buffer: [*]u8 = @ptrCast(allocateMemory(push_buffer_size));

            const max_vertex_count: u32 = 65536;
            const vertex_array: [*]TexturedVertex =
                @ptrCast(@alignCast(allocateMemory(max_vertex_count * @sizeOf(TexturedVertex))));
            const bitmap_array: [*]RendererTexture =
                @ptrCast(@alignCast(allocateMemory(max_vertex_count * @sizeOf(RendererTexture))));

            const cube_texture = loadBMP("cube_test.bmp", allocator);
            _ = cube_texture;

            while (running) {
                processPendingMessages();

                var client_rect: win32.RECT = undefined;
                _ = win32.GetClientRect(window_handle, &client_rect);
                const window_width: i32 = client_rect.right - client_rect.left;
                const window_height: i32 = client_rect.bottom - client_rect.top;

                const draw_region: Rectangle2i =
                    math.aspectRatioFit(16, 9, @intCast(window_width), @intCast(window_height));

                var render_commands: RenderCommands = RenderCommands.default(
                    push_buffer_size,
                    push_buffer,
                    @intCast(draw_region.getWidth()),
                    @intCast(draw_region.getHeight()),
                    max_vertex_count,
                    vertex_array,
                    bitmap_array,
                    open_gl.white_bitmap,
                );

                const camera: CameraParams = .get(@intCast(draw_region.getWidth()), 1);

                const camera_offset: Vector3 = .zero();
                const camera_pitch: f32 = 0.1 * math.PI32;
                const camera_orbit: f32 = 0;
                const camera_dolly: f32 = 10;

                const near_clip_plane: f32 = 0.2;
                const far_clip_plane: f32 = 1000;

                var camera_o: Matrix4x4 =
                    Matrix4x4.zRotation(camera_orbit).times(.xRotation(camera_pitch));
                const camera_ot: Vector3 =
                    camera_o.timesV(camera_offset.plus(.new(0, 0, camera_dolly)));

                var group: RenderGroup = .begin(
                    undefined,
                    &render_commands,
                    1,
                    draw_region.getWidth(),
                    draw_region.getHeight(),
                );
                group.setCameraTransform(
                    camera.focal_length,
                    camera_o.getColumn(0),
                    camera_o.getColumn(1),
                    camera_o.getColumn(2),
                    camera_ot,
                    0,
                    near_clip_plane,
                    far_clip_plane,
                    true,
                );

                const background_color: Color = .new(0.15, 0.15, 0.15, 0);
                group.beginDepthPeel(background_color);
                group.pushCube(
                    open_gl.white_bitmap,
                    .zero(),
                    .new(1, 1, 2),
                    .new(1, 1, 1, 1),
                    null,
                    null,
                );
                group.endDepthPeel();
                group.end();

                opengl.renderCommands(&render_commands, draw_region, window_width, window_height);
                _ = win32.SwapBuffers(window_dc);

                var end_counter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&end_counter);
                const seconds_elapsed: f32 =
                    @as(f32, @floatFromInt(end_counter.QuadPart - last_counter.QuadPart)) /
                    @as(f32, @floatFromInt(perf_count_frequency));
                _ = seconds_elapsed;
                last_counter = end_counter;
            }
        }
    }

    win32.ExitProcess(0);

    return 0;
}
