const std = @import("std");
const win32 = @import("win32").everything;
const math = @import("math.zig");
const types = @import("types.zig");
const intrinsics = @import("intrinsics.zig");
const renderer = @import("renderer.zig");
const opengl = @import("renderer_opengl.zig");
const wgl = @import("win32_opengl.zig");

const c = @cImport({
    @cInclude("stdlib.h");
});

// Build options.
pub const INTERNAL = @import("build_options").internal;

// Globals.
var running: bool = false;
var open_gl = &opengl.open_gl;

// Types.
const Color = math.Color;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Matrix4x4 = math.Matrix4x4;
const Rectangle2i = math.Rectangle2i;
const RenderCommands = renderer.RenderCommands;
const RenderGroup = renderer.RenderGroup;
const RenderGroupFlags = renderer.RenderGroupFlags;
const TexturedVertex = renderer.TexturedVertex;
const RendererTexture = renderer.RendererTexture;
const CameraParams = renderer.CameraParams;
const TextureOp = renderer.TextureOp;

const TEST_SCENE_DIM_X = 40;
const TEST_SCENE_DIM_Y = 50;

const TestSceneElement = enum(u32) {
    Grass,
    Tree,
    Wall,
};

const TestScene = struct {
    min_position: Vector3 = .zero(),
    elements: [TEST_SCENE_DIM_Y][TEST_SCENE_DIM_X]TestSceneElement =
        [1][TEST_SCENE_DIM_X]TestSceneElement{[1]TestSceneElement{.Grass} ** TEST_SCENE_DIM_X} ** TEST_SCENE_DIM_Y,
    grass_texture: RendererTexture = .empty,
    wall_texture: RendererTexture = .empty,
    tree_texture: RendererTexture = .empty,
    head_texture: RendererTexture = .empty,
    cover_texture: RendererTexture = .empty,
};

fn initTestScene(scene: *TestScene, allocator: std.mem.Allocator) void {
    scene.grass_texture = loadBMP("test_cube_grass.bmp", allocator);
    scene.wall_texture = loadBMP("test_cube_wall.bmp", allocator);
    scene.tree_texture = loadBMP("test_sprite_tree.bmp", allocator);
    scene.head_texture = loadBMP("test_sprite_head.bmp", allocator);
    scene.cover_texture = loadBMP("test_cover_grass.bmp", allocator);
    scene.min_position = .new(
        -0.5 * @as(f32, @floatFromInt(TEST_SCENE_DIM_X)),
        -0.5 * @as(f32, @floatFromInt(TEST_SCENE_DIM_Y)),
        0,
    );

    const total_square_count: u32 = TEST_SCENE_DIM_X * TEST_SCENE_DIM_Y;

    var wall_index: u32 = 0;
    while (wall_index < 8) : (wall_index += 1) {
        const x: u32 = 1 + @mod(@as(u32, @intCast(c.rand())), TEST_SCENE_DIM_X - 10);
        const y: u32 = 1 + @mod(@as(u32, @intCast(c.rand())), TEST_SCENE_DIM_Y - 10);

        const dim_x: u32 = 2 + @as(u32, @intCast(@mod(c.rand(), 6)));
        const dim_y: u32 = 2 + @as(u32, @intCast(@mod(c.rand(), 6)));

        _ = placeRectangularWall(scene, x, y, x + dim_x, y + dim_y);
    }

    placeRandomInUnoccupied(scene, .Tree, total_square_count / 15);
}

fn countOccupantsIn3x3(scene: *TestScene, center_x: u32, center_y: u32) u32 {
    var occupant_count: u32 = 0;
    var y: u32 = center_y - 1;
    while (y <= center_y + 1) : (y += 1) {
        var x: u32 = center_x - 1;
        while (x <= center_x + 1) : (x += 1) {
            if (!isEmpty(scene, x, y)) {
                occupant_count += 1;
            }
        }
    }
    return occupant_count;
}

fn isEmpty(scene: *TestScene, x: u32, y: u32) bool {
    return (scene.elements[y][x] == .Grass);
}

fn placeRandomInUnoccupied(scene: *TestScene, element: TestSceneElement, count: u32) void {
    var placed: u32 = 0;
    while (placed < count) {
        const x: u32 = 1 + @mod(@as(u32, @intCast(c.rand())), TEST_SCENE_DIM_X - 1);
        const y: u32 = 1 + @mod(@as(u32, @intCast(c.rand())), TEST_SCENE_DIM_Y - 1);

        if (countOccupantsIn3x3(scene, x, y) == 0) {
            scene.elements[y][x] = element;
            placed += 1;
        }
    }
}

fn placeRectangularWall(scene: *TestScene, min_x: u32, min_y: u32, max_x: u32, max_y: u32) bool {
    var placed: bool = true;

    var pass: u32 = 0;
    while (placed and pass <= 1) : (pass += 1) {
        var x: u32 = min_x;
        while (x <= max_x) : (x += 1) {
            if (pass == 0) {
                if (!(isEmpty(scene, x, min_y) and isEmpty(scene, x, max_y))) {
                    placed = false;
                    break;
                }
            } else {
                scene.elements[min_y][x] = .Wall;
                scene.elements[max_y][x] = .Wall;
            }
        }

        var y: u32 = min_y + 1;
        while (y <= max_y) : (y += 1) {
            if (pass == 0) {
                if (!(isEmpty(scene, min_x, y) and isEmpty(scene, max_x, y))) {
                    placed = false;
                    break;
                }
            } else {
                scene.elements[y][min_x] = .Wall;
                scene.elements[y][max_x] = .Wall;
            }
        }
    }

    return placed;
}

fn pushSimpleScene(group: *RenderGroup, scene: *TestScene) void {
    c.srand(1234);

    var y: u32 = 0;
    while (y < TEST_SCENE_DIM_Y) : (y += 1) {
        var x: u32 = 0;
        while (x < TEST_SCENE_DIM_X) : (x += 1) {
            const element: TestSceneElement = scene.elements[y][x];
            const z: f32 = 0.4 * @as(f32, @floatFromInt(c.rand())) / @as(f32, @floatFromInt(c.RAND_MAX));
            const r: f32 = 0.5 + 0.5 * @as(f32, @floatFromInt(c.rand())) / @as(f32, @floatFromInt(c.RAND_MAX));
            const z_radius: f32 = 2;
            const color: Color = .new(r, 1, 1, 1);
            const position: Vector3 = scene.min_position.plus(.new(@floatFromInt(x), @floatFromInt(y), z));

            group.pushCube(
                scene.grass_texture,
                position,
                .new(0.5, 0.5, z_radius),
                color,
                null,
                null,
            );

            const ground_position: Vector3 = position.plus(.new(0, 0, z_radius));
            if (element == .Tree) {
                group.pushSprite(
                    scene.tree_texture,
                    true,
                    ground_position,
                    .new(2, 2.5),
                    .zero(),
                    .one(),
                    null,
                    null,
                    null,
                );
            } else if (element == .Wall) {
                const wall_radius: f32 = 1;
                group.pushCube(
                    scene.wall_texture,
                    ground_position.plus(.new(0, 0, wall_radius)),
                    .new(0.5, 0.5, wall_radius),
                    color,
                    null,
                    null,
                );
            } else {
                var cover_index: u32 = 0;
                while (cover_index < 5) : (cover_index += 1) {
                    const displacement: Vector2 = Vector2.new(
                        @as(f32, @floatFromInt(c.rand())) / @as(f32, @floatFromInt(c.RAND_MAX)),
                        @as(f32, @floatFromInt(c.rand())) / @as(f32, @floatFromInt(c.RAND_MAX)),
                    ).minus(.new(0.4, 0.4)).scaledTo(0.8);

                    group.pushSprite(
                        scene.cover_texture,
                        true,
                        ground_position.plus(displacement.toVector3(0)),
                        .new(0.4, 0.4),
                        .zero(),
                        .one(),
                        null,
                        null,
                        null,
                    );
                }
            }
        }
    }

    group.pushSprite(scene.head_texture, true, .new(0, 2, 3), .new(4, 4), .zero(), .one(), null, null, null);
}

fn renderLoop(lp_parameter: ?*anyopaque) callconv(.c) u32 {
    if (lp_parameter) |parameter| {
        // When the render thread is created, the HWND render target is passed as the lpParameter.
        const window: win32.HWND = @ptrCast(@alignCast(parameter));

        // This times our rendering, it has nothing to do with the renderer API.
        var frame_stats: FrameStats = .init();

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        // Initialize OpenGL so that we can render to our window. The win32 startup code is contained within
        // `win32_opengl.zig`, so we get the DC for our window and pass that to its `initOpenGL` function so it can
        // do all the startup for us.
        const opengl_dc = win32.GetDC(window);
        _ = wgl.initOpenGL(opengl_dc);

        // Ask for no vsync in case we get better timings. We may still get vsync due to either the Windows compositor
        // or the GPU settings.
        wgl.setVSync(false);

        // Allocate memory that we're going to use for queueing render commands. The sizes used here depend entirely
        // on how much and what kind of rendering the app does.
        const push_buffer_size: u32 = @intCast(types.megabytes(64));
        const push_buffer: [*]u8 = @ptrCast(allocateMemory(push_buffer_size));

        const max_vertex_count: u32 = 10 * 65536;
        const vertex_array: [*]TexturedVertex =
            @ptrCast(@alignCast(allocateMemory(max_vertex_count * @sizeOf(TexturedVertex))));
        const bitmap_array: [*]RendererTexture =
            @ptrCast(@alignCast(allocateMemory(max_vertex_count * @sizeOf(RendererTexture))));

        // Allocate a set of operations for submitting textures. We allocate as many as we think we will want
        // in-flight at a given time. For this render test, we really only need a few, because we only load 5 or 6
        // textures. But in a real engine, you want to makesure you have as many ops allocated as textures you might
        // download during a single frame.
        const texture_op_count: u32 = 256;
        opengl.initTextureQueue(
            &open_gl.texture_queue,
            texture_op_count,
            @ptrCast(@alignCast(allocateMemory(@sizeOf(renderer.TextureOp) * texture_op_count))),
        );

        // Initialize the test scene. This has nothing to do with the renderer API, it's just a way of making a data
        // structure we can use later to figure out what we want to render ever frame.
        var scene: TestScene = .{};
        initTestScene(&scene, allocator);

        // Setup some parameters that we use to animate the camera view.
        const camera_pitch: f32 = 0.3 * math.PI32; // Tilt of the camera.
        var camera_orbit: f32 = 0; // Rotation of the camera around the subject.
        const camera_dolly: f32 = 20; // Distance away from the subject.
        const camera_drop_shift: f32 = -1; // Amount to drop the camera down from the center of the subject.
        const camera_focal_length: f32 = 3; // Amount of perspective foreshortening.

        const near_clip_plane: f32 = 0.2; // Closest you can be to the camera and still be seen.
        const far_clip_plane: f32 = 1000; // Furthest you can be from the camera and still be seen.

        var camera_shift_t: f32 = 0; // Accumulator used in the rendering loop to animate the camera.

        // The camera goes through two animation tests in the loop.
        // First it does a rotation around the scene (camera_is_panning == false) with no panning.
        // Thene it does a pand around the scene (camera_is_panning == true) with no rotation.
        var camera_is_panning: bool = false;

        while (running) {
            var client_rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window, &client_rect);
            const window_width: i32 = client_rect.right - client_rect.left;
            const window_height: i32 = client_rect.bottom - client_rect.top;

            const fog: bool = false;

            const draw_region: Rectangle2i =
                math.aspectRatioFit(16, 9, @intCast(window_width), @intCast(window_height));

            const camera: CameraParams = .get(camera_focal_length);

            if (camera_shift_t > math.TAU32) {
                camera_shift_t -= math.TAU32;
                camera_is_panning = !camera_is_panning;
            }
            var camera_offset: Vector3 = .new(0, 0, camera_drop_shift);

            if (camera_is_panning) {
                camera_offset =
                    camera_offset.plus(Vector3.new(@cos(camera_shift_t), -0.2 + @sin(camera_shift_t), 0).scaledTo(10));
            } else {
                camera_orbit = camera_shift_t;
            }

            var camera_o: Matrix4x4 =
                Matrix4x4.zRotation(camera_orbit).times(.xRotation(camera_pitch));
            const camera_ot: Vector3 = camera_o.timesV(.new(0, 0, camera_dolly));

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

            const background_color: Color = .new(0.15, 0.15, 0.15, 0);
            var group: RenderGroup = .begin(undefined, &render_commands, RenderGroupFlags.default, background_color);
            group.setCameraTransform(
                camera.focal_length,
                camera_o.getColumn(0),
                camera_o.getColumn(1),
                camera_o.getColumn(2),
                camera_ot.plus(camera_offset),
                0,
                near_clip_plane,
                far_clip_plane,
                fog,
            );
            pushSimpleScene(&group, &scene);
            group.end();

            opengl.renderCommands(&render_commands, draw_region, window_width, window_height);
            _ = win32.SwapBuffers(opengl_dc);

            const seconds_elapsed: f32 = frame_stats.update();
            camera_shift_t += 0.1 * seconds_elapsed;
        }
    }

    return 0;
}

//
//
//
// Everything below here is just win32 code to open a window and file code to read a .bmp file for textures.
// None of it is related to the renderer API.
//
//
//

const WINDOW_DECORATION_WIDTH = 16;
const WINDOW_DECORATION_HEIGHT = 39;
const WINDOW_WIDTH = 1920;
const WINDOW_HEIGHT = 1080;

const FrameStats = struct {
    performance_frequency: win32.LARGE_INTEGER = .{ .QuadPart = 0 },
    last_counter: win32.LARGE_INTEGER = .{ .QuadPart = 0 },

    min_spf: f32 = std.math.floatMax(f32),
    max_spf: f32 = 0,
    display_counter: u32 = 0,

    pub fn init() FrameStats {
        var stats: FrameStats = .{};
        _ = win32.QueryPerformanceFrequency(&stats.performance_frequency);
        return stats;
    }

    pub fn update(self: *FrameStats) f32 {
        var seconds_elapsed: f32 = 0;

        var end_counter: win32.LARGE_INTEGER = undefined;
        _ = win32.QueryPerformanceCounter(&end_counter);

        if (self.last_counter.QuadPart != 0) {
            seconds_elapsed =
                @as(f32, @floatFromInt(end_counter.QuadPart - self.last_counter.QuadPart)) /
                @as(f32, @floatFromInt(self.performance_frequency.QuadPart));

            self.min_spf = @min(self.min_spf, seconds_elapsed);
            self.max_spf = @max(self.max_spf, seconds_elapsed);

            if (self.display_counter == 120) {
                std.log.info("Min: {d:.02}ms, Max: {d:.02}ms", .{ 1000 * self.min_spf, 1000 * self.max_spf });
                self.min_spf = std.math.floatMax(f32);
                self.max_spf = 0;
                self.display_counter = 0;
            }

            self.display_counter += 1;
        }

        self.last_counter = end_counter;

        return seconds_elapsed;
    }
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

const EntireFile = struct {
    content_size: u32 = 0,
    contents: []const u8 = undefined,
};

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
) RendererTexture {
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

    var texture: RendererTexture = .empty;
    const texture_op: TextureOp = .{
        .is_allocate = true,
        .op = .{
            .allocate = .{
                .width = result.?.width,
                .height = result.?.height,
                .data = result.?.memory.?,
                .result_texture = &texture,
            },
        },
    };
    renderer.addOp(&open_gl.texture_queue, &texture_op);
    opengl.manageTextures();

    return texture;
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
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const opt_device_context: ?win32.HDC = win32.BeginPaint(window, &paint);
            _ = opt_device_context;
            _ = win32.EndPaint(window, &paint);
        },
        else => {
            result = win32.DefWindowProcA(window, message, w_param, l_param);
        },
    }

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
        .lpszClassName = win32.L("HandmadeZigRendererTestWindowClass"),
    };

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
            WINDOW_WIDTH + WINDOW_DECORATION_WIDTH,
            WINDOW_HEIGHT + WINDOW_DECORATION_HEIGHT,
            null,
            null,
            instance,
            null,
        );

        if (opt_window_handle) |window| {
            running = true;

            var thread_id: std.os.windows.DWORD = undefined;
            const thread_handle = win32.CreateThread(
                null,
                types.megabytes(16),
                renderLoop,
                @ptrCast(window),
                win32.THREAD_CREATE_RUN_IMMEDIATELY,
                &thread_id,
            );
            _ = win32.CloseHandle(thread_handle);

            while (running) {
                var message: win32.MSG = undefined;
                if (win32.GetMessageA(&message, null, 0, 0) > 0) {
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageA(&message);
                } else {
                    running = false;
                }
            }
        }
    }

    win32.ExitProcess(0);
    return 0;
}
