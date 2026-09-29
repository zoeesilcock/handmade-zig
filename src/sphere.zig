const math = @import("math.zig");
const random = @import("random.zig");
const lighting = @import("lighting.zig");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const LightingSolution = lighting.LightingSolution;

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

pub fn generateLightingPattern(solution: *LightingSolution, pattern_index: u32) void {
    var series: random.Series = solution.series;

    var version_index: u32 = 0;
    while (version_index < solution.sample_points.len) : (version_index += 1) {
        var temp: [72]Vector3 = undefined;
        generatePoissonSamples(&series, temp.len, &temp);

        // var sum: f32 = 0;
        // var dir_index: u32 = 0;
        // while (dir_index < temp.len) : (dir_index += 1) {
        //     sum += testFunc(temp[dir_index]);
        // }
        // const avg: f32 = sum / @as(f32, @floatFromInt(sample_count));
        // min_avg = @min(min_avg, avg);
        // max_avg = @max(max_avg, avg);

        const sampling_sphere: *LightSamplingSphere = &solution.sampling_spheres[version_index];
        var dest = &sampling_sphere.sample_direction[version_index];
        var dir_index: u32 = 0;
        while (dir_index < sampling_sphere.sample_direction.len) : (dir_index += 1) {
            dest[dir_index] = .new(
                temp[4 * dir_index + 0],
                temp[4 * dir_index + 1],
                temp[4 * dir_index + 2],
                temp[4 * dir_index + 3],
            );
        }
    }

    solution.pattern_name = pattern.name;
}
