const std = @import("std");
const shared = @import("shared");
const math = shared.math;
const simd = shared.simd;
const random = shared.random;

// Types.
const Vector3 = math.Vector3;
const V3_4x = simd.V3_4x;

const CubeStore = struct {
    weights: [6]f32 = @splat(0),
};

const SphereStore = struct {
    sample_direction: []V3_4x = undefined,
    weights: []CubeStore = undefined,
};

fn generatePoissonSamples(series: *random.Series, dest_count: u32, dest: [*]Vector3) void {
    // TODO: We could put a much more efficient poisson noise generate in here, and probably should at some point.

    // TODO: Right now we just hard code min_dist_sq, but that wouldn't work if you wanted to adjust the dest_count to
    // something else, so we probably need something that determines what the correct "packing ratio" is.

    const min_dist_sq: f32 = math.square(0.17);
    var point_count: u32 = 0;
    while (point_count < dest_count) {
        var p: Vector3 = Vector3.new(
            series.randomBilateral(),
            series.randomBilateral(),
            series.randomBilateral(),
        );
        const p_sq: f32 = p.lengthSquared();
        if (p_sq > 0.01) {
            p = p.scaledTo(1.0 / @sqrt(p_sq));

            // const max_cos: f32 = @cos((0.120 * math.PI32) - (0.07 * math.PI32 * p.z()));

            var test_index: u32 = 0;
            var valid: bool = true;
            while (test_index < point_count) : (test_index += 1) {
                if (dest[test_index].minus(p).lengthSquared() < min_dist_sq) {
                    valid = false;
                    break;
                }
            }

            if (valid) {
                dest[point_count] = p;
                point_count += 1;
            }
        }
    }
}

pub fn generateLightingPattern(
    light_sampling_sphere_count: u32,
    ray_bundles_per_sphere: u32,
    spheres: []SphereStore,
    allocator: std.mem.Allocator,
) !void {
    var series: random.Series = .seed(1234, null, null, null);

    const total_direction_count: u32 = light_sampling_sphere_count * ray_bundles_per_sphere * 4;
    var directions: []Vector3 = try allocator.alloc(Vector3, total_direction_count);
    // const used: []bool = try allocator.alloc(bool, total_direction_count);

    var dir_index: u32 = 0;
    while (dir_index < total_direction_count) {
        var direction: Vector3 = .new(
            series.randomBilateral(),
            series.randomBilateral(),
            series.randomBilateral(),
        );

        direction = direction.normalizeOrZero();

        if (direction.lengthSquared() > 0.1) {
            directions[dir_index] = direction;
            dir_index += 1;
        }
    }

    var sphere_index: u32 = 0;
    while (sphere_index < light_sampling_sphere_count) : (sphere_index += 1) {
        const sphere: *SphereStore = &spheres[sphere_index];
        var direction_from: [*]Vector3 = @ptrCast(&directions[sphere_index]);
        var bundle_index: u32 = 0;
        while (bundle_index < ray_bundles_per_sphere) : (bundle_index += 1) {
            sphere.sample_direction[bundle_index] = .new(
                direction_from[0],
                direction_from[1],
                direction_from[2],
                direction_from[3],
            );
            direction_from += 4;

            var bundle_component: u32 = 0;
            while (bundle_component < 4) : (bundle_component += 1) {
                const weight_index: u32 = 4 * bundle_index + bundle_component;

                sphere.weights[weight_index].weights[0] = 0;
                sphere.weights[weight_index].weights[1] = 0;
                sphere.weights[weight_index].weights[2] = 0;
                sphere.weights[weight_index].weights[3] = 0;
                sphere.weights[weight_index].weights[4] = 0;
                sphere.weights[weight_index].weights[5] = 0;
            }
        }
    }
}

fn outputSpheres(
    light_sampling_sphere_count: u32,
    ray_bundles_per_sphere: u32,
    spheres: []SphereStore,
    writer: *std.Io.Writer,
) !void {
    try writer.print("const simd = @import(\"simd.zig\");\n\n", .{});

    try writer.print("// Types.\n", .{});
    try writer.print("const V3_4x = simd.V3_4x;\n\n", .{});

    try writer.print("pub const LIGHT_SAMPLING_SPHERE_COUNT = {d};\n", .{light_sampling_sphere_count});
    try writer.print("pub const LIGHT_SAMPLING_SPHERE_MASK = {d};\n", .{light_sampling_sphere_count - 1});
    try writer.print("pub const LIGHT_SAMPLING_RAY_BUNDLES_PER_SPHERE = {d};\n", .{ray_bundles_per_sphere});
    try writer.print("pub const LIGHT_SAMPLING_TOTAL_RAYS_PER_SPHERE = 4 * LIGHT_SAMPLING_RAY_BUNDLES_PER_SPHERE;\n", .{});
    try writer.print("pub const LightSamplingSphere = extern struct {{\n", .{});
    try writer.print("    sample_direction: [LIGHT_SAMPLING_RAY_BUNDLES_PER_SPHERE]V3_4x = @splat(.splat(@splat(0))),\n", .{});
    try writer.print("    cube_side_weight: [LIGHT_SAMPLING_TOTAL_RAYS_PER_SPHERE][6]f32 = @splat(@splat(0)),\n", .{});
    try writer.print("}};\n\n", .{});

    try writer.print("pub var light_sampling_sphere_table: [LIGHT_SAMPLING_SPHERE_COUNT]LightSamplingSphere = .{{\n", .{});

    var sphere_index: u32 = 0;
    while (sphere_index < light_sampling_sphere_count) : (sphere_index += 1) {
        const sphere: *SphereStore = &spheres[sphere_index];

        try writer.print("    .{{\n", .{});
        try writer.print("        .sample_direction = .{{\n", .{});
        var ray_budle_index: u32 = 0;
        while (ray_budle_index < ray_bundles_per_sphere) : (ray_budle_index += 1) {
            const bundle: V3_4x = sphere.sample_direction[ray_budle_index];

            try writer.print(
                "            .fromAxes(.{{ {d}, {d}, {d}, {d} }}, .{{ {d}, {d}, {d}, {d} }}, .{{ {d}, {d}, {d}, {d} }}),\n",
                .{
                    bundle.x[0],
                    bundle.x[1],
                    bundle.x[2],
                    bundle.x[3],

                    bundle.y[0],
                    bundle.y[1],
                    bundle.y[2],
                    bundle.y[3],

                    bundle.z[0],
                    bundle.z[1],
                    bundle.z[2],
                    bundle.z[3],
                },
            );
        }
        try writer.print("        }},\n", .{});

        try writer.print("        .cube_side_weight = .{{\n", .{});
        var weight_bundle: u32 = 0;
        while (weight_bundle < 4 * ray_bundles_per_sphere) : (weight_bundle += 1) {
            const cube: CubeStore = sphere.weights[weight_bundle];

            try writer.print(
                "            .{{ {d}, {d}, {d}, {d}, {d}, {d} }},\n",
                .{
                    cube.weights[0],
                    cube.weights[1],
                    cube.weights[2],
                    cube.weights[3],
                    cube.weights[4],
                    cube.weights[5],
                },
            );
        }
        try writer.print("        }},\n", .{});

        try writer.print("    }},\n", .{});
    }

    try writer.print("}};\n", .{});
    try writer.flush();
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len == 4) {
        const light_sampling_sphere_count: u32 = try std.fmt.parseInt(u32, args[1], 10);
        const ray_bundles_per_sphere: u32 = try std.fmt.parseInt(u32, args[2], 10);
        const dest_file_name: []const u8 = args[3];

        const spheres: []SphereStore = try allocator.alloc(SphereStore, light_sampling_sphere_count);
        var sphere_index: u32 = 0;
        while (sphere_index < light_sampling_sphere_count) : (sphere_index += 1) {
            var sphere: *SphereStore = &spheres[sphere_index];
            sphere.sample_direction = try allocator.alloc(V3_4x, ray_bundles_per_sphere);
            sphere.weights = try allocator.alloc(CubeStore, ray_bundles_per_sphere * 4);
        }

        try generateLightingPattern(light_sampling_sphere_count, ray_bundles_per_sphere, spheres, allocator);

        if (std.Io.Dir.cwd().createFile(init.io, dest_file_name, .{})) |dest_file| {
            defer dest_file.close(init.io);

            var buf: [1024]u8 = undefined;
            var file_writer = dest_file.writer(init.io, &buf);
            const writer = &file_writer.interface;

            try outputSpheres(light_sampling_sphere_count, ray_bundles_per_sphere, spheres, writer);
        } else |err| {
            std.log.err("Unable to open file {s} for writing. {s}", .{ dest_file_name, @errorName(err) });
        }
    } else {
        std.log.err("Usage: {s} <sphere count> <ray bundle count> <destination .zig file>", .{args[0]});
    }
}
