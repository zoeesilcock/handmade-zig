/// This is only the barest of bones for a raytracer! We are computing things inaccurately and physically
/// incorrect everywhere. We'll fix it some day when we come back to it.
const std = @import("std");
const math = @import("math");
const win32 = if (PLATFORM == .windows) @import("ray_win32.zig") else @panic("Unsupported platform");

const PLATFORM = @import("builtin").os.tag;

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("math.h");
    @cInclude("time.h");
});

// Types.
const Vector3 = math.Vector3;
const Color = math.Color;
const Color3 = math.Color3;

pub const std_options: std.Options = .{
    .logFn = myLogFn,
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    if (level == .err) {
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.fs.File.stderr().deprecatedWriter();
        nosuspend stderr.print(format ++ "\n", args) catch return;
    } else {
        var stdout_buf: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writerStreaming(&stdout_buf);
        var stdout = &stdout_writer.interface;
        stdout.print(format ++ "\n", args) catch return;
        stdout.flush() catch return;
    }
}

const World = struct {
    material_count: u32,
    materials: []Material,

    plane_count: u32,
    planes: []Plane,

    sphere_count: u32,
    spheres: []Sphere,
};

pub const WorkQueue = struct {
    rays_per_pixel: u32,
    max_bounce_count: u32,

    work_order_count: u32 = 0,
    work_orders: []WorkOrder,

    next_work_order_index: u64 = 0,
    bounces_computed: u64 = 0,
    tile_retired_count: u64 = 0,
};

const WorkOrder = struct {
    world: *World,
    image: *ImageU32,
    x_min: u32,
    y_min: u32,
    one_past_x_max: u32,
    one_past_y_max: u32,
};

const Material = struct {
    scatter: f32 = 0, // 0 is pure diffuse (chalk), 1 is pure specular (mirror).
    emit_color: Color3 = .zero(),
    reflect_color: Color3 = .zero(),
};

const Plane = struct {
    normal: Vector3,
    distance: f32,
    material_index: u32,
};

const Sphere = struct {
    position: Vector3,
    radius: f32,
    material_index: u32,
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
};

const ImageU32 = struct {
    width: u32,
    height: u32,
    pixels: []u32,
};

fn getTotalPixelSize(image: ImageU32) u32 {
    return @as(u32, @intCast(image.pixels.len)) * @sizeOf(u32);
}

fn getPixelPointer(image: *ImageU32, x: u32, y: u32) []u32 {
    const start = y * image.width + x;
    return image.pixels[start..];
}

fn allocateImage(width: u32, height: u32, allocator: std.mem.Allocator) !ImageU32 {
    return .{
        .width = width,
        .height = height,
        .pixels = try allocator.alloc(u32, @intCast(width * height)),
    };
}

fn writeImage(image: ImageU32, output_file_name: []const u8) !void {
    const output_pixel_size: u32 = getTotalPixelSize(image);
    const header_size: u32 = @sizeOf(BitmapHeader) - 10;
    const header: BitmapHeader = .{
        .file_type = 0x4d42,
        .file_size = header_size + @as(u32, @intCast(image.pixels.len)),
        .reserved1 = 0,
        .reserved2 = 0,
        .bitmap_offset = header_size,
        .size = header_size - 14,
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .planes = 1,
        .bits_per_pxel = 32,
        .compression = 0,
        .size_of_bitmap = output_pixel_size,
        .horz_resolution = 0,
        .vert_resolution = 0,
        .colors_used = 0,
        .colors_important = 0,
    };

    if (false) {
        const in_file_name: []const u8 = "reference.bmp";
        if (std.fs.cwd().openFile(in_file_name, .{})) |file| {
            defer file.close();

            var buf: [1024]u8 = undefined;
            var file_reader = file.reader(&buf);
            const reader = &file_reader.interface;

            const in_header: BitmapHeader = try reader.takeStruct(BitmapHeader, .little);
            std.log.info("Header: {x}", .{in_header.file_type});
        } else |err| {
            std.log.err("Unable to open reference file '{s}': {s}", .{ in_file_name, @errorName(err) });
        }
    }

    if (std.fs.cwd().createFile(output_file_name, .{})) |file| {
        defer file.close();

        var buf: [1024]u8 = undefined;
        var file_writer = file.writer(&buf);
        const writer = &file_writer.interface;

        try writer.writeAll(std.mem.asBytes(&header)[0..header_size]);
        try writer.writeAll(std.mem.sliceAsBytes(image.pixels));

        try writer.flush();
    } else |err| {
        std.log.err("Unable to write output file '{s}': {s}", .{ output_file_name, @errorName(err) });
    }
}

fn randomUnilateral() f32 {
    return @as(f32, @floatFromInt(c.rand())) / c.RAND_MAX;
}

fn randomBilateral() f32 {
    return -1 + 2 * randomUnilateral();
}

fn exactLinearToSRGB(input: f32) f32 {
    var linear: f32 = input;

    if (linear < 0) {
        linear = 0;
    }

    if (linear > 1) {
        linear = 1;
    }

    var srgb: f32 = linear * 12.92;
    if (linear > 0.0031308) {
        srgb = @floatCast(1.055 * c.pow(linear, 1.0 / 2.4) - 0.055);
    }

    return srgb;
}

fn lockedAddAndReturnPreviousValue(value: *u64, addend: u64) u64 {
    return @atomicRmw(u64, value, .Add, addend, .seq_cst);
}

pub fn renderTile(queue: *WorkQueue) bool {
    const work_order_index: u64 = lockedAddAndReturnPreviousValue(&queue.next_work_order_index, 1);
    if (work_order_index >= queue.work_order_count) {
        return false;
    }

    const order: *WorkOrder = &queue.work_orders[work_order_index];
    const world: *World = order.world;
    const image: *ImageU32 = order.image;
    const x_min: u32 = order.x_min;
    const y_min: u32 = order.y_min;
    const one_past_x_max: u32 = order.one_past_x_max;
    const one_past_y_max: u32 = order.one_past_y_max;

    const camera_position: Vector3 = .new(0, -10, 1);
    const camera_z: Vector3 = camera_position.normalized();
    const camera_x: Vector3 = Vector3.new(0, 0, 1).crossProduct(camera_z).normalizeOrZero();
    const camera_y: Vector3 = camera_z.crossProduct(camera_x).normalizeOrZero();

    const film_distance: f32 = 1;
    var film_width: f32 = 1;
    var film_height: f32 = 1;

    if (image.width > image.height) {
        film_height = film_width * @as(f32, @floatFromInt(image.height)) / @as(f32, @floatFromInt(image.width));
    } else if (image.height > image.width) {
        film_width = film_height * @as(f32, @floatFromInt(image.width)) / @as(f32, @floatFromInt(image.height));
    }

    const film_half_width: f32 = 0.5 * film_width;
    const film_half_height: f32 = 0.5 * film_height;
    const film_center: Vector3 = camera_position.plus(camera_z.negated().scaledTo(film_distance));

    const pixel_width: f32 = 0.5 / @as(f32, @floatFromInt(image.width));
    const pixel_height: f32 = 0.5 / @as(f32, @floatFromInt(image.height));

    var bounces_computed: u64 = 0;

    var y: u32 = y_min;
    while (y < one_past_y_max) : (y += 1) {
        var out: []u32 = getPixelPointer(image, x_min, y);
        const film_y: f32 = -1 + 2 * (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(image.height)));

        var x: u32 = x_min;
        while (x < one_past_x_max) : (x += 1) {
            const film_x: f32 = -1 + 2 * (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(image.width)));

            var final_color: Color3 = .zero();
            const contribution: f32 = 1.0 / @as(f32, @floatFromInt(queue.rays_per_pixel));
            var ray_index: u32 = 0;
            while (ray_index <= queue.rays_per_pixel) : (ray_index += 1) {
                const offset_x: f32 = film_x + randomBilateral() * pixel_width;
                const offset_y: f32 = film_y + randomBilateral() * pixel_height;
                const film_position: Vector3 = film_center.plus(
                    camera_x.scaledTo(offset_x * film_half_width),
                ).plus(
                    camera_y.scaledTo(offset_y * film_half_height),
                );
                var ray_origin: Vector3 = camera_position;
                var ray_direction: Vector3 = film_position.minus(camera_position).normalizeOrZero();

                const tolerance: f32 = 0.0001;
                const min_hit_distance: f32 = 0.001;

                var sample: Color3 = .zero();
                var attenuation: Color3 = .one();
                var bounce_count: u32 = 0;
                while (bounce_count <= queue.max_bounce_count) : (bounce_count += 1) {
                    var hit_distance: f32 = std.math.floatMax(f32);
                    var hit_material_index: u32 = 0;
                    var next_normal: Vector3 = .zero();

                    bounces_computed += 1;

                    var plane_index: u32 = 0;
                    while (plane_index < world.plane_count) : (plane_index += 1) {
                        const plane: Plane = world.planes[plane_index];

                        const denominator: f32 = plane.normal.dotProduct(ray_direction);
                        if (@abs(denominator) > tolerance) {
                            const t: f32 = (-plane.distance - plane.normal.dotProduct(ray_origin)) / denominator;
                            if (t > min_hit_distance and t < hit_distance) {
                                hit_distance = t;
                                hit_material_index = plane.material_index;

                                next_normal = plane.normal;
                            }
                        }
                    }

                    var sphere_index: u32 = 0;
                    while (sphere_index < world.sphere_count) : (sphere_index += 1) {
                        const sphere: Sphere = world.spheres[sphere_index];

                        const sphere_relative_ray_origin: Vector3 = ray_origin.minus(sphere.position);
                        const a: f32 = ray_direction.dotProduct(ray_direction);
                        const b: f32 = 2.0 * ray_direction.dotProduct(sphere_relative_ray_origin);
                        const sphere_c: f32 =
                            sphere_relative_ray_origin.dotProduct(sphere_relative_ray_origin) - sphere.radius * sphere.radius;

                        const denominator: f32 = 2.0 * a;
                        const root_term: f32 = @sqrt(b * b - 4.0 * a * sphere_c);

                        if (root_term > tolerance) {
                            const tp: f32 = (-b + root_term) / denominator;
                            const tn: f32 = (-b - root_term) / denominator;

                            var t = tp;
                            if (tn > min_hit_distance and tn < tp) {
                                t = tn;
                            }

                            if (t > min_hit_distance and t < hit_distance) {
                                hit_distance = t;
                                hit_material_index = sphere.material_index;

                                next_normal = ray_direction.scaledTo(t).plus(sphere_relative_ray_origin).normalizeOrZero();
                            }
                        }
                    }

                    if (hit_material_index > 0) {
                        const material = world.materials[hit_material_index];

                        sample = sample.plus(attenuation.hadamardProduct(material.emit_color));
                        var cosine_attenuation: f32 = ray_direction.negated().dotProduct(next_normal);
                        if (cosine_attenuation < 0) {
                            cosine_attenuation = 0;
                        }
                        attenuation = attenuation.hadamardProduct(material.reflect_color.scaledTo(cosine_attenuation));

                        ray_origin = ray_origin.plus(ray_direction.scaledTo(hit_distance));

                        const pure_bounce: Vector3 =
                            ray_direction.minus(next_normal.scaledTo(2 * ray_direction.dotProduct(next_normal)));
                        const random_bounce: Vector3 =
                            next_normal.plus(.new(randomBilateral(), randomBilateral(), randomBilateral())).normalizeOrZero();
                        ray_direction = random_bounce.lerp(pure_bounce, material.scatter).normalizeOrZero();
                    } else {
                        const material = world.materials[hit_material_index];
                        sample = sample.plus(attenuation.hadamardProduct(material.emit_color));
                        break;
                    }
                }
                final_color = final_color.plus(sample.scaledTo(contribution));
            }

            const bmp_color: Color = .new(
                255 * exactLinearToSRGB(final_color.r()),
                255 * exactLinearToSRGB(final_color.g()),
                255 * exactLinearToSRGB(final_color.b()),
                255,
            );
            const bmp_value: u32 = bmp_color.packColorBGRA();

            out[0] = bmp_value; //if (y < 32) 0xffff0000 else 0xff0000ff;
            out = out[1..];
        }
    }

    _ = lockedAddAndReturnPreviousValue(&queue.bounces_computed, bounces_computed);
    _ = lockedAddAndReturnPreviousValue(&queue.tile_retired_count, 1);

    return true;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var materials = [_]Material{
        .{ .emit_color = .new(0.3, 0.4, 0.5) },
        .{ .reflect_color = .new(0.5, 0.5, 0.5) },
        .{ .reflect_color = .new(0.7, 0.5, 0.3) },
        .{ .emit_color = .new(4, 0, 0) },
        .{ .reflect_color = .new(0.4, 0.8, 0.2), .scatter = 0.7 },
        .{ .reflect_color = .new(0.4, 0.8, 0.9), .scatter = 0.85 },
        .{ .reflect_color = .new(0.95, 0.95, 0.95), .scatter = 1 },
    };

    var planes = [_]Plane{
        .{ .material_index = 1, .normal = .new(0, 0, 1), .distance = 0 },
    };

    var spheres = [_]Sphere{
        .{ .material_index = 2, .position = .new(0, 0, 0), .radius = 1 },
        .{ .material_index = 3, .position = .new(3, -2, 0), .radius = 1 },
        .{ .material_index = 4, .position = .new(-2, -1, 2), .radius = 1 },
        .{ .material_index = 5, .position = .new(1, -1, 3), .radius = 1 },
        .{ .material_index = 6, .position = .new(-2, 3, 0), .radius = 2 },
    };

    var world: World = .{
        .material_count = materials.len,
        .materials = &materials,
        .plane_count = planes.len,
        .planes = &planes,
        .sphere_count = spheres.len,
        .spheres = &spheres,
    };

    var image: ImageU32 = try allocateImage(1280, 720, allocator);

    const core_count: u32 = win32.getCPUCoreCount();
    const tile_width: u32 = @divFloor(image.width, core_count);
    const tile_height: u32 = tile_width;
    // const tile_width: u32 = 64;
    // const tile_height: u32 = tile_width;
    const tile_count_x: u32 = @divFloor(image.width + tile_width - 1, tile_width);
    const tile_count_y: u32 = @divFloor(image.height + tile_height - 1, tile_height);
    const total_tile_count: u32 = tile_count_x * tile_count_y;

    var queue: WorkQueue = .{
        .work_orders = try allocator.alloc(WorkOrder, total_tile_count),
        .rays_per_pixel = 1024,
        .max_bounce_count = 8,
    };

    std.log.info(
        "Configuration: {d} cores with {d} {d}x{d} ({d}k/tile) tiles.",
        .{ core_count, total_tile_count, tile_width, tile_height, (tile_width * tile_height * @sizeOf(u32)) / 1024 },
    );
    std.log.info("Quality: {d} rays/pixel, {d} bounces per ray.", .{ queue.rays_per_pixel, queue.max_bounce_count });

    var tile_y: u32 = 0;
    while (tile_y < tile_count_y) : (tile_y += 1) {
        const y_min: u32 = tile_y * tile_height;
        var one_past_y_max: u32 = y_min + tile_height;
        if (one_past_y_max > image.height) {
            one_past_y_max = image.height;
        }

        var tile_x: u32 = 0;
        while (tile_x < tile_count_x) : (tile_x += 1) {
            const x_min: u32 = tile_x * tile_width;
            var one_past_x_max: u32 = x_min + tile_width;
            if (one_past_x_max > image.width) {
                one_past_x_max = image.width;
            }

            var order: *WorkOrder = &queue.work_orders[queue.work_order_count];
            queue.work_order_count += 1;

            std.debug.assert(queue.work_order_count <= total_tile_count);

            order.world = &world;
            order.image = &image;
            order.x_min = x_min;
            order.y_min = y_min;
            order.one_past_x_max = one_past_x_max;
            order.one_past_y_max = one_past_y_max;
        }
    }

    std.debug.assert(queue.work_order_count == total_tile_count);

    // This locked add is strictly for fencing.
    _ = lockedAddAndReturnPreviousValue(&queue.next_work_order_index, 0);

    const start_clock: c.clock_t = c.clock();

    var core_index: u32 = 1;
    while (core_index < core_count) : (core_index += 1) {
        win32.createWorkThread(&queue);
    }

    while (queue.tile_retired_count < total_tile_count) {
        if (renderTile(&queue)) {
            std.log.err("Raycasting {d:.0}%...", .{
                100 * (@as(f32, @floatFromInt(queue.tile_retired_count)) / @as(f32, @floatFromInt(total_tile_count))),
            });
        }
    }

    const end_clock: c.clock_t = c.clock();
    const time_elapsed: c.clock_t = end_clock - start_clock;

    std.log.err("Raycasting time: {d}ms.", .{time_elapsed});
    std.log.info("Total bounces: {d}.", .{queue.bounces_computed});
    std.log.info(
        "Performance: {d:.7}ms/bounce.",
        .{@as(f64, @floatFromInt(time_elapsed)) / @as(f64, @floatFromInt(queue.bounces_computed))},
    );

    try writeImage(image, "test.bmp");

    std.log.err("Done.", .{});
}
