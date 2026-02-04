/// This is only the barest of bones for a raytracer! We are computing things inaccurately and physically
/// incorrect everywhere. We'll fix it some day when we come back to it.
const std = @import("std");
const math = @import("math");
const lane = @import("ray_lane.zig");
const win32 = if (PLATFORM == .windows) @import("ray_win32.zig") else @panic("Unsupported platform");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("math.h");
    @cInclude("time.h");
});

const PLATFORM = @import("builtin").os.tag;
const LANE_WIDTH = lane.LANE_WIDTH;

// Types.
const Vector3 = math.Vector3;
const Color = math.Color;
const Color3 = math.Color3;
const Lane_bool = lane.Lane_bool;
const Lane_f32 = lane.Lane_f32;
const Lane_u32 = lane.Lane_u32;
const Lane_Vector3 = lane.Lane_Vector3;
const Lane_Color3 = lane.Lane_Color3;

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
    loops_computed: u64 = 0,
    tile_retired_count: u64 = 0,
};

const WorkOrder = struct {
    world: *World,
    image: *ImageU32,
    x_min: u32,
    y_min: u32,
    one_past_x_max: u32,
    one_past_y_max: u32,
    entropy: RandomSeries,
};

const Material = struct {
    specular: f32 = 0, // 0 is pure diffuse (chalk), 1 is pure specular (mirror).
    reflect_color: Color3 = .zero(),
    emit_color: Color3 = .zero(),
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

const RandomSeries = struct {
    state: Lane_u32,

    pub fn xorshift32(self: *RandomSeries) Lane_u32 {
        var result = self.state;

        result ^= result << @splat(13);
        result ^= result >> @splat(17);
        result ^= result << @splat(5);

        self.state = result;

        return result;
    }

    fn randomUnilateral(self: *RandomSeries) Lane_f32 {
        return @as(Lane_f32, @floatFromInt(self.xorshift32())) /
            @as(Lane_f32, @floatFromInt(@as(Lane_u32, @splat(std.math.maxInt(u32)))));
    }

    fn randomBilateral(self: *RandomSeries) Lane_f32 {
        return @as(Lane_f32, @splat(-1)) + @as(Lane_f32, @splat(2)) * self.randomUnilateral();
    }
};

const CastState = struct {
    world: *World,
    rays_per_pixel: u32,
    max_bounce_count: u32,
    series: RandomSeries = undefined,

    camera_position: Vector3 = .zero(),
    camera_x: Vector3 = .zero(),
    camera_y: Vector3 = .zero(),
    camera_z: Vector3 = .zero(),

    film_width: f32 = 0,
    film_height: f32 = 0,
    film_half_width: f32 = 0,
    film_half_height: f32 = 0,
    film_center: Vector3 = .zero(),

    half_pixel_width: f32 = 0,
    half_pixel_height: f32 = 0,

    film_x: f32 = 0,
    film_y: f32 = 0,

    // Out.
    final_color: Color3 = .zero(),
    bounces_computed: u64 = 0,
    loops_computed: u64 = 0,
};

fn castSampleRays(state: *CastState) void {
    const world: *World = state.world;
    const rays_per_pixel: u32 = state.rays_per_pixel;
    const max_bounce_count: u32 = state.max_bounce_count;
    const film_half_width: Lane_f32 = @splat(state.film_half_width);
    const film_half_height: Lane_f32 = @splat(state.film_half_height);
    const film_center: Lane_Vector3 = .splat(state.film_center);
    const half_pixel_width: Lane_f32 = @splat(state.half_pixel_width);
    const half_pixel_height: Lane_f32 = @splat(state.half_pixel_height);
    const film_x: Lane_f32 = @as(Lane_f32, @splat(state.film_x)) + half_pixel_width;
    const film_y: Lane_f32 = @as(Lane_f32, @splat(state.film_y)) + half_pixel_height;
    const camera_x: Lane_Vector3 = .splat(state.camera_x);
    const camera_y: Lane_Vector3 = .splat(state.camera_y);
    const camera_position: Lane_Vector3 = .splat(state.camera_position);
    var series: RandomSeries = state.series;

    const zero: Lane_u32 = @splat(0);
    const zero_f: Lane_f32 = @splat(0);
    const two: Lane_f32 = @splat(2.0);
    const four: Lane_f32 = @splat(4.0);

    var bounces_computed: Lane_u32 = @splat(0);
    var loops_computed: u64 = 0;
    var final_color: Lane_Color3 = .splat(.zero());

    const lane_width: u32 = LANE_WIDTH;
    const lane_ray_count: u32 = rays_per_pixel / lane_width;
    std.debug.assert((lane_ray_count * LANE_WIDTH) == rays_per_pixel);

    const contribution: f32 = 1.0 / @as(f32, @floatFromInt(rays_per_pixel));
    var ray_index: u32 = 0;
    while (ray_index < lane_ray_count) : (ray_index += 1) {
        const offset_x: Lane_f32 = film_x + series.randomBilateral() * half_pixel_width;
        const offset_y: Lane_f32 = film_y + series.randomBilateral() * half_pixel_height;
        const film_position: Lane_Vector3 = film_center.plus(
            camera_x.scaledTo(offset_x * film_half_width),
        ).plus(
            camera_y.scaledTo(offset_y * film_half_height),
        );
        var ray_origin: Lane_Vector3 = camera_position;
        var ray_direction: Lane_Vector3 = film_position.minus(camera_position).normalizeOrZero();

        const tolerance: Lane_f32 = @splat(0.0001);
        const min_hit_distance: Lane_f32 = @splat(0.001);

        var sample: Lane_Color3 = .splat(.zero());
        var attenuation: Lane_Color3 = .splat(.one());

        var lane_mask: Lane_bool = @splat(true);

        var bounce_count: u32 = 0;
        while (bounce_count < max_bounce_count) : (bounce_count += 1) {
            var hit_distance: Lane_f32 = @splat(std.math.floatMax(f32));
            var hit_material_index: Lane_u32 = @splat(0);
            var next_normal: Lane_Vector3 = .splat(.zero());

            const lane_increment: Lane_u32 = @splat(1);
            bounces_computed += (lane_increment & @intFromBool(lane_mask));
            loops_computed += LANE_WIDTH;

            var plane_index: u32 = 0;
            while (plane_index < world.plane_count) : (plane_index += 1) {
                const plane: Plane = world.planes[plane_index];

                const plane_normal: Lane_Vector3 = .splat(plane.normal);
                const plane_distance: Lane_f32 = @splat(plane.distance);

                const denominator: Lane_f32 = plane_normal.dotProduct(ray_direction);
                const denominator_mask: Lane_bool = ((denominator < -tolerance) | (denominator > tolerance));

                if (!lane.maskIsZeroed(denominator_mask)) {
                    const t: Lane_f32 =
                        @as(Lane_f32, -plane_distance - plane_normal.dotProduct(ray_origin)) / denominator;
                    const t_mask: Lane_bool = ((t > min_hit_distance) & (t < hit_distance));
                    const hit_mask: Lane_bool = denominator_mask & t_mask;

                    if (!lane.maskIsZeroed(hit_mask)) {
                        const plane_material_index: Lane_u32 = @splat(plane.material_index);

                        lane.conditionalAssign(Lane_f32, &hit_distance, hit_mask, t);
                        lane.conditionalAssign(Lane_u32, &hit_material_index, hit_mask, plane_material_index);
                        lane.conditionalAssign(Lane_Vector3, &next_normal, hit_mask, plane_normal);
                    }
                }
            }

            var sphere_index: u32 = 0;
            while (sphere_index < world.sphere_count) : (sphere_index += 1) {
                const sphere: Sphere = world.spheres[sphere_index];

                const sphere_position: Lane_Vector3 = .splat(sphere.position);
                const sphere_radius: Lane_f32 = @splat(sphere.radius);

                const sphere_relative_ray_origin: Lane_Vector3 = ray_origin.minus(sphere_position);
                const a: Lane_f32 = ray_direction.dotProduct(ray_direction);
                const b: Lane_f32 = two * ray_direction.dotProduct(sphere_relative_ray_origin);
                const sphere_c: Lane_f32 =
                    sphere_relative_ray_origin.dotProduct(sphere_relative_ray_origin) - sphere_radius * sphere_radius;

                const root_term: Lane_f32 = @sqrt(b * b - four * a * sphere_c);
                const root_mask: Lane_bool = (root_term > tolerance);
                if (!lane.maskIsZeroed(root_mask)) {
                    const denominator: Lane_f32 = two * a;
                    const tp: Lane_f32 = (-b + root_term) / denominator;
                    const tn: Lane_f32 = (-b - root_term) / denominator;
                    var t = tp;
                    const pick_mask: Lane_bool = ((tn > min_hit_distance) & (tn < tp));
                    lane.conditionalAssign(Lane_f32, &t, pick_mask, tn);

                    const t_mask: Lane_bool = ((t > min_hit_distance) & (t < hit_distance));
                    const hit_mask: Lane_bool = root_mask & t_mask;

                    if (!lane.maskIsZeroed(hit_mask)) {
                        const sphere_material_index: Lane_u32 = @splat(sphere.material_index);

                        lane.conditionalAssign(Lane_f32, &hit_distance, hit_mask, t);
                        lane.conditionalAssign(Lane_u32, &hit_material_index, hit_mask, sphere_material_index);
                        lane.conditionalAssign(
                            Lane_Vector3,
                            &next_normal,
                            hit_mask,
                            ray_direction.scaledTo(t).plus(sphere_relative_ray_origin).normalizeOrZero(),
                        );
                    }
                }
            }

            const material_emit_color: Lane_Color3 =
                lane.andBoolWithColor3(
                    lane_mask,
                    lane.gatherColor3(Material, world.materials.ptr, hit_material_index, "emit_color"),
                );
            const material_reflect_color: Lane_Color3 =
                lane.gatherColor3(Material, world.materials.ptr, hit_material_index, "reflect_color");
            const material_specular: Lane_f32 =
                lane.gatherF32(Material, world.materials.ptr, hit_material_index, "specular");

            sample = sample.plus(attenuation.hadamardProduct(material_emit_color));
            lane_mask &= (hit_material_index != zero);

            if (lane.maskIsZeroed(lane_mask)) {
                break;
            } else {
                const cosine_attenuation: Lane_f32 = @max(ray_direction.negated().dotProduct(next_normal), zero_f);
                attenuation = attenuation.hadamardProduct(material_reflect_color.scaledTo(cosine_attenuation));

                ray_origin = ray_origin.plus(ray_direction.scaledTo(hit_distance));

                const pure_bounce: Lane_Vector3 =
                    ray_direction.minus(next_normal.scaledTo(two * ray_direction.dotProduct(next_normal)));
                const random_bounce: Lane_Vector3 =
                    next_normal.plus(.new(
                        series.randomBilateral(),
                        series.randomBilateral(),
                        series.randomBilateral(),
                    )).normalizeOrZero();
                ray_direction = random_bounce.lerp(pure_bounce, material_specular).normalizeOrZero();
            }
        }

        final_color = final_color.plus(sample.scaledTo(@splat(contribution)));
    }

    state.bounces_computed += lane.horizontalAddU64(bounces_computed);
    state.loops_computed += loops_computed;
    state.final_color = lane.horizontalAddColor3(final_color);
    state.series = series;
}

pub fn renderTile(queue: *WorkQueue) bool {
    const work_order_index: u64 = lockedAddAndReturnPreviousValue(&queue.next_work_order_index, 1);
    if (work_order_index >= queue.work_order_count) {
        return false;
    }

    const order: *WorkOrder = &queue.work_orders[work_order_index];

    const image: *ImageU32 = order.image;
    const x_min: u32 = order.x_min;
    const y_min: u32 = order.y_min;
    const one_past_x_max: u32 = order.one_past_x_max;
    const one_past_y_max: u32 = order.one_past_y_max;
    const film_distance: f32 = 1;

    const camera_position: Lane_Vector3 = .splat(.new(0, -10, 1));
    const camera_z: Lane_Vector3 = camera_position.normalized();
    const camera_x: Lane_Vector3 = Lane_Vector3.splat(Vector3.new(0, 0, 1)).crossProduct(camera_z).normalizeOrZero();
    const camera_y: Lane_Vector3 = camera_z.crossProduct(camera_x).normalizeOrZero();
    const film_center: Lane_Vector3 = camera_position.plus(camera_z.negated().scaledTo(@splat(film_distance)));

    var state: CastState = .{
        .world = order.world,
        .rays_per_pixel = queue.rays_per_pixel,
        .max_bounce_count = queue.max_bounce_count,
        .series = order.entropy,
    };

    state.camera_position = camera_position.extract0();
    state.camera_z = camera_z.extract0();
    state.camera_x = camera_x.extract0();
    state.camera_y = camera_y.extract0();

    state.film_width = 1;
    state.film_height = 1;
    if (image.width > image.height) {
        state.film_height =
            state.film_width * @as(f32, @floatFromInt(image.height)) / @as(f32, @floatFromInt(image.width));
    } else if (image.height > image.width) {
        state.film_width =
            state.film_height * @as(f32, @floatFromInt(image.width)) / @as(f32, @floatFromInt(image.height));
    }

    state.film_half_width = 0.5 * state.film_width;
    state.film_half_height = 0.5 * state.film_height;
    state.film_center = film_center.extract0();

    state.half_pixel_width = 0.5 / @as(f32, @floatFromInt(image.width));
    state.half_pixel_height = 0.5 / @as(f32, @floatFromInt(image.height));

    state.bounces_computed = 0;
    state.loops_computed = 0;

    var y: u32 = y_min;
    while (y < one_past_y_max) : (y += 1) {
        var out: []u32 = getPixelPointer(image, x_min, y);
        state.film_y = -1 + 2 * (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(image.height)));

        var x: u32 = x_min;
        while (x < one_past_x_max) : (x += 1) {
            state.film_x = -1 + 2 * (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(image.width)));

            castSampleRays(&state);

            const r: f32 = 255 * exactLinearToSRGB(state.final_color.r());
            const g: f32 = 255 * exactLinearToSRGB(state.final_color.g());
            const b: f32 = 255 * exactLinearToSRGB(state.final_color.b());
            const a: f32 = 255;

            const bmp_value: u32 =
                ((@as(u32, @intFromFloat(a + 0.5)) << 24) |
                    (@as(u32, @intFromFloat(r)) << 16) |
                    (@as(u32, @intFromFloat(g)) << 8) |
                    (@as(u32, @intFromFloat(b)) << 0));

            out[0] = bmp_value; //if (y < 32) 0xffff0000 else 0xff0000ff;
            out = out[1..];
        }
    }

    _ = lockedAddAndReturnPreviousValue(&queue.bounces_computed, state.bounces_computed);
    _ = lockedAddAndReturnPreviousValue(&queue.loops_computed, state.loops_computed);
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
        .{ .specular = 0.7, .reflect_color = .new(0.4, 0.8, 0.2) },
        .{ .specular = 0.85, .reflect_color = .new(0.4, 0.8, 0.9) },
        .{ .specular = 1, .reflect_color = .new(0.95, 0.95, 0.95) },
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
    // const tile_width: u32 = @divFloor(image.width, core_count);
    // const tile_height: u32 = tile_width;
    const tile_width: u32 = 64;
    const tile_height: u32 = tile_width;
    const tile_count_x: u32 = @divFloor(image.width + tile_width - 1, tile_width);
    const tile_count_y: u32 = @divFloor(image.height + tile_height - 1, tile_height);
    const total_tile_count: u32 = tile_count_x * tile_count_y;

    var queue: WorkQueue = .{
        .work_orders = try allocator.alloc(WorkOrder, total_tile_count),
        .rays_per_pixel = 1024,
        .max_bounce_count = 8,
    };

    std.log.info(
        "Configuration: {d} cores with {d} {d}x{d} ({d}k/tile) tiles, {d}-wide lanes.",
        .{
            core_count,
            total_tile_count,
            tile_width,
            tile_height,
            (tile_width * tile_height * @sizeOf(u32)) / 1024,
            LANE_WIDTH,
        },
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
            order.entropy = .{ .state = @splat(0) };

            const seeds = [_]u32{
                2397458 + tile_x * 29083 + tile_y * 97843,
                9878934 + tile_x * 89243 + tile_y * 12938,
                6783234 + tile_x * 29738 + tile_y * 97853,
                2945085 + tile_x * 54378 + tile_y * 89722,
                7653902 + tile_x * 65422 + tile_y * 57821,
                5839067 + tile_x * 89435 + tile_y * 78120,
                9435786 + tile_x * 12398 + tile_y * 32178,
                9604351 + tile_x * 20789 + tile_y * 43521,
            };
            std.debug.assert(LANE_WIDTH <= seeds.len);
            inline for (0..LANE_WIDTH) |i| {
                order.entropy.state[i] = seeds[i];
            }
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

    const used_bounces: u64 = queue.bounces_computed;
    const total_bounces: u64 = queue.loops_computed;
    const wasted_bounces: u64 = total_bounces - used_bounces;

    std.log.info("Raycasting time: {d}ms.", .{time_elapsed});
    std.log.info("Used bounces: {d}.", .{used_bounces});
    std.log.info("Total bounces: {d}.", .{total_bounces});
    std.log.info("Wasted bounces: {d} ({d:.02}).", .{
        wasted_bounces,
        (100.0 * @as(f32, @floatFromInt(wasted_bounces)) / @as(f32, @floatFromInt(total_bounces))),
    });
    std.log.info(
        "Performance: {d:.7}ms/bounce.",
        .{@as(f64, @floatFromInt(time_elapsed)) / @as(f64, @floatFromInt(queue.bounces_computed))},
    );

    try writeImage(image, "test.bmp");

    std.log.err("Done.", .{});
}
