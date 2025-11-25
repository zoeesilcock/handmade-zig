const math = @import("math.zig");
const rendergroup = @import("rendergroup.zig");
const shared = @import("shared.zig");
const memory = @import("memory.zig");
const asset = @import("asset.zig");
const intrinsics = @import("intrinsics.zig");
const random = @import("random.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

var global_config = &@import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const Color3 = math.Color3;
const RenderGroup = rendergroup.RenderGroup;
const RenderCommands = shared.RenderCommands;
const LoadedBitmap = asset.LoadedBitmap;
const DebugInterface = debug_interface.DebugInterface;
const TimedBlock = debug_interface.TimedBlock;

pub const LIGHT_POINTS_PER_CHUNK = 24;
pub const MAX_LIGHT_EMISSION = 5.0;
pub const LIGHT_DATA_WIDTH = 2 * 8192;
pub const LIGHT_CHUNK_COUNT = LIGHT_DATA_WIDTH / LIGHT_POINTS_PER_CHUNK;
const SLOW = shared.SLOW;

pub const LightingTextures = extern struct {
    light_data0: [LIGHT_DATA_WIDTH]Vector4, // Px, Py, Pz, Dx
    light_data1: [LIGHT_DATA_WIDTH]Vector4, // SignDz*Cr, Cg, Cb, Dy
};

pub const LightingSolution = extern struct {
    box_count: u16 = 0,
    boxes: [*]LightingBox = undefined,

    scratch_a: [LIGHT_DATA_WIDTH]u16 = [1]u16{0} ** LIGHT_DATA_WIDTH,
    scratch_b: [LIGHT_DATA_WIDTH]u16 = [1]u16{0} ** LIGHT_DATA_WIDTH,

    box_reference_count: u16 = 0,
    box_table: [LIGHT_DATA_WIDTH]u16 = [1]u16{0} ** LIGHT_DATA_WIDTH,
    root_box_index: u16,

    point_count: u16,
    points: [LIGHT_DATA_WIDTH]LightingPoint = undefined,

    emission_color0: [LIGHT_DATA_WIDTH]Color3 = undefined,
    emission_color1: [LIGHT_DATA_WIDTH]Color3 = undefined,
    average_direction_to_light: [LIGHT_DATA_WIDTH]Vector3 = undefined,
    series: random.Series,

    total_ray_count: u32, // Number of total rays cast.
    raycast_point_count: u32, // Number of times a point got used as an origin.
    raycast_box_count: u32, // Number of times a box got considered for intersection.
};

pub const LightingSurface = extern struct {
    position: Vector3,
    normal: Vector3,
    transparency: f32,
    width: f32,
    height: f32,
    x_axis: Vector3,
    y_axis: Vector3,
    light_index: u16 = 0,
    light_count: u16 = 0,
};

pub const LightingBox = extern struct {
    storage: [*]LightingPointState,
    position: Vector3,
    radius: Vector3,
    reflection_color: Color3,
    transparency: f32,
    emission: f32,
    light_index: [7]u16 = [1]u16{0} ** 7,
    child_count: u16 = 0,
    first_child_index: u16,
};

pub const LightingPointState = extern struct {
    emit: Color3,
    direction: Vector3,
};

pub const LightingPoint = extern struct {
    position: Vector3,
    reflection_color: Color3,
    normal: Vector3,
};

pub const LightBoxSurface = struct {
    position: Vector3,
    normal: Vector3,
    x_axis: Vector3,
    y_axis: Vector3,
    half_width: f32,
    half_height: f32,
};

const RaycastResult = struct {
    box: ?*LightingBox,
    box_surface_index: u32,
    t_ray: f32,
};

pub fn getBoxSurface(position_in: Vector3, radius: Vector3, surface_index: u32) LightBoxSurface {
    const axis_index: u32 = surface_index >> 1;
    const positive: u32 = surface_index & 0x1;

    var normal: Vector3 = .zero();
    var y_axis: Vector3 = if (axis_index == 2) .new(0, 1, 0) else .new(0, 0, 1);

    var position: Vector3 = position_in;
    if (positive == 1) {
        normal.values[axis_index] = 1;
        position.values[axis_index] += radius.values[axis_index];
    } else {
        normal.values[axis_index] = -1;
        position.values[axis_index] -= radius.values[axis_index];
    }

    var sign_x: f32 = if (positive == 1) 1 else -1;
    if (axis_index == 1) {
        sign_x *= -1;
    }
    var x_axis: Vector3 = if (axis_index == 0) .new(0, sign_x, 0) else .new(sign_x, 0, 0);

    const half_width: f32 = intrinsics.absoluteValue(x_axis.dotProduct(radius));
    const half_height: f32 = intrinsics.absoluteValue(y_axis.dotProduct(radius));

    const result: LightBoxSurface = .{
        .position = position,
        .normal = normal,
        .x_axis = x_axis,
        .y_axis = y_axis,
        .half_width = half_width,
        .half_height = half_height,
    };

    return result;
}

fn getBox(solution: *LightingSolution, box_index: u32) *LightingBox {
    // TODO: Why is this considerably slower on my version, but not on Casey's version.
    const box = solution.boxes + solution.box_table[box_index];
    // const box = solution.boxes + box_index;
    return @ptrCast(box);
}

fn addBoxReference(solution: *LightingSolution, box_storage_index: u16) u16 {
    std.debug.assert(solution.box_reference_count < solution.box_table.len);

    const result = solution.box_reference_count;
    solution.box_reference_count += 1;
    solution.box_table[result] = box_storage_index;

    return result;
}

fn addBoxReferences(solution: *LightingSolution, count: u16, references: [*]u16) u16 {
    std.debug.assert(
        @as(u32, @intCast(solution.box_reference_count)) + @as(u32, @intCast(count)) <= solution.box_table.len,
    );

    const result: u16 = solution.box_reference_count;
    solution.box_reference_count += count;

    var index: u16 = 0;
    while (index < count) : (index += 1) {
        solution.box_table[result + index] = references[index];
    }

    return result;
}

fn addBoxStorage(solution: *LightingSolution) u16 {
    std.debug.assert(solution.box_count < LIGHT_DATA_WIDTH);

    const result = solution.box_count;
    solution.box_count += 1;

    return @intCast(result);
}

fn raycast(
    solution: *LightingSolution,
    ray_origin: Vector3,
    ray_direction: Vector3,
) RaycastResult {
    var result: RaycastResult = .{
        .box = null,
        .box_surface_index = 0,
        .t_ray = std.math.floatMax(f32),
    };

    raycastRecurse(
        solution,
        ray_origin,
        ray_direction,
        getBox(solution, solution.root_box_index),
        &result,
    );

    return result;
}

fn raycastRecurse(
    solution: *LightingSolution,
    ray_origin: Vector3,
    ray_direction: Vector3,
    root_box: *LightingBox,
    result: *RaycastResult,
) void {
    solution.total_ray_count += 1;

    var source_index: u32 = root_box.first_child_index;
    while (source_index < (root_box.first_child_index + root_box.child_count)) : (source_index += 1) {
        const box: *LightingBox = getBox(solution, source_index);

        solution.raycast_box_count += 1;

        if (box.child_count > 0 and math.isInRectangleCenterHalfDim(box.position, box.radius, ray_origin)) {
            raycastRecurse(solution, ray_origin, ray_direction, box, result);
        } else {
            var axis_index: u32 = 0;
            while (axis_index < 3) : (axis_index += 1) {
                const positive: u32 = @intFromBool(ray_direction.values[axis_index] < 0);
                const box_surface_index: u32 = @intCast((axis_index << 1) | positive);

                const sign: f32 = if (positive == 1) 1 else -1;

                const radius: Vector3 = box.radius;
                var position: Vector3 = box.position;
                position.values[axis_index] += sign * radius.values[axis_index];

                const relative_origin: Vector3 = ray_origin.minus(position);
                const t_ray: f32 = -relative_origin.values[axis_index] / ray_direction.values[axis_index];
                if (t_ray > 0 and t_ray < result.t_ray) {
                    const ray_position: Vector3 = relative_origin.plus(ray_direction.scaledTo(t_ray));

                    const x_check: f32 = if (axis_index == 0) ray_position.y() else ray_position.x();
                    const half_width: f32 = if (axis_index == 0) radius.y() else radius.x();

                    const y_check: f32 = if (axis_index == 2) ray_position.y() else ray_position.z();
                    const half_height: f32 = if (axis_index == 2) radius.y() else radius.z();

                    if (@abs(x_check) <= half_width and
                        @abs(y_check) <= half_height)
                    {
                        if (box.child_count > 0) {
                            raycastRecurse(solution, ray_origin, ray_direction, box, result);
                        } else {
                            result.t_ray = t_ray;
                            result.box = box;
                            result.box_surface_index = box_surface_index;
                        }

                        break;
                    }
                }
            }
        }
    }
}

fn sampleHemisphere(series: *random.Series, normal: Vector3) Vector3 {
    var result: Vector3 = Vector3.new(
        series.randomBilateral(),
        series.randomBilateral(),
        series.randomBilateral(),
    ).normalizeOrZero();

    if (result.dotProduct(normal) < 0) {
        result = result.negated();
    }

    return result;
}

fn accumulateSample(
    surface_normal: Vector3,
    dest_emission_color: *Color3,
    average_direction_to_light: *Vector3,
    light_color: Color3,
    light_power: f32,
    normal_to_light: Vector3,
) Color3 {
    const angular_falloff: f32 = math.clampf01(surface_normal.dotProduct(normal_to_light));
    const power: f32 = light_power * angular_falloff;
    const weight: f32 = power * light_color.length();

    const result: Color3 = light_color.scaledTo(power);
    dest_emission_color.* = dest_emission_color.plus(result);
    average_direction_to_light.* = average_direction_to_light.plus(
        normal_to_light.scaledTo(weight),
    );

    return result;
}

fn computeLightPropagation(solution: *LightingSolution) void {
    TimedBlock.beginFunction(@src(), .ComputeLightPropagation);
    defer TimedBlock.endFunction(@src(), .ComputeLightPropagation);

    const source_emission_color: [*]Color3 = &solution.emission_color0;
    var dest_emission_color: [*]Color3 = &solution.emission_color1;

    const blend_amount: f32 = 0.01;
    const ray_count: u32 = 4;
    const power: f32 = blend_amount / @as(f32, @floatFromInt(ray_count));

    // const sky_color: Color = .new(0.2, 0.2, 0.95, 0.5);
    const moon_color: Color = Color.new(0.1, 0.8, 1.0, 1.0);
    // const ground_color: Color = .new(0.3, 0.2, 0.1, 1.0);
    // const sun_direction: Vector3 = Vector3.new(1, 1, 1).normalizeOrZero();

    var total_added: Color3 = .zero();
    var total_removed: Color3 = .zero();

    var series: random.Series = solution.series;
    var sample_point_index: u32 = 1; // Light point index 0 is never used.
    while (sample_point_index < solution.point_count) : (sample_point_index += 1) {
        dest_emission_color[sample_point_index] = dest_emission_color[sample_point_index].plus(
            source_emission_color[sample_point_index],
        );

        const sample_point: *LightingPoint = &solution.points[sample_point_index];

        var ray_index: u32 = 0;
        while (ray_index < ray_count) : (ray_index += 1) {
            const sample_direction: Vector3 = sampleHemisphere(&series, sample_point.normal);

            const ray: RaycastResult = raycast(
                solution,
                sample_point.position,
                sample_direction,
            );

            var emission_color: Color3 = undefined;
            if (ray.box) |hit_box| {
                const hit_index: u32 = hit_box.light_index[ray.box_surface_index];
                const hit_point_count: u32 =
                    hit_box.light_index[ray.box_surface_index + 1] - hit_index;
                const ray_position: Vector3 =
                    sample_point.position.plus(sample_direction.scaledTo(ray.t_ray));

                var total_weight: f32 = 0;
                var surface_point_index: u32 = 0;
                while (surface_point_index < hit_point_count) : (surface_point_index += 1) {
                    const hit_point_index: u32 = hit_index + surface_point_index;
                    const hit_point: *LightingPoint = &solution.points[hit_point_index];
                    const distance_sq: f32 =
                        ray_position.minus(hit_point.position).lengthSquared();
                    const inverse_distance_sq: f32 = 1.0 / (1.0 + distance_sq);

                    total_weight += inverse_distance_sq;
                    emission_color = emission_color.plus(
                        hit_point.reflection_color.hadamardProduct(source_emission_color[hit_point_index])
                            .scaledTo(inverse_distance_sq),
                    );
                }

                var inverse_total_weight: f32 = 1;
                if (total_weight > 0) {
                    inverse_total_weight = 1.0 / total_weight;
                }

                surface_point_index = 0;
                while (surface_point_index < hit_point_count) : (surface_point_index += 1) {
                    const hit_point_index: u32 = hit_index + surface_point_index;
                    const hit_point: *LightingPoint = &solution.points[hit_point_index];
                    const distance_sq: f32 =
                        ray_position.minus(hit_point.position).lengthSquared();
                    const inverse_distance_sq: f32 = 1.0 / (1.0 + distance_sq);
                    const weight: f32 = inverse_distance_sq * inverse_total_weight;

                    std.debug.assert(weight <= 1);

                    const contrib_color: Color3 =
                        hit_point.reflection_color.hadamardProduct(source_emission_color[hit_point_index]);
                    const removed_color: Color3 = contrib_color.scaledTo(power * weight);
                    dest_emission_color[hit_point_index] = dest_emission_color[hit_point_index].minus(removed_color);
                    emission_color = emission_color.plus(contrib_color.scaledTo(weight));

                    total_removed = total_removed.plus(removed_color);
                }
            } else {
                emission_color = moon_color.rgb();
            }

            total_added = total_added.plus(accumulateSample(
                sample_point.normal,
                @ptrCast(dest_emission_color + sample_point_index),
                &solution.average_direction_to_light[sample_point_index],
                emission_color,
                power,
                sample_direction,
            ));
        }
    }

    {
        var total_source_light: Color3 = .zero();
        var total_dest_light: Color3 = .zero();
        var point_index: u32 = 0;
        while (point_index < solution.point_count) : (point_index += 1) {
            total_source_light = total_source_light.plus(
                source_emission_color[point_index],
            );
            total_dest_light = total_dest_light.plus(
                dest_emission_color[point_index],
            );
        }

        // const source_sum: f32 = total_source_light.r() + total_source_light.g() + total_source_light.b();
        const source_sum: f32 = 10000;
        const dest_sum: f32 = total_dest_light.r() + total_dest_light.g() + total_dest_light.b();
        var check_dest_light: Color3 = .zero();

        if (dest_sum > 0) {
            const normalization_coefficient: f32 = source_sum / dest_sum;
            point_index = 0;
            while (point_index < solution.point_count) : (point_index += 1) {
                source_emission_color[point_index] =
                    dest_emission_color[point_index].scaledTo(normalization_coefficient);
                dest_emission_color[point_index] = .zero();

                check_dest_light = check_dest_light.plus(source_emission_color[point_index]);
            }
        }
    }

    solution.series = series;
}

fn splitBox(
    solution: *LightingSolution,
    parent_box: *LightingBox,
    source_count_in: u16,
    source: [*]u16,
    dest: [*]u16,
    dimension_index_in: u32,
) void {
    var source_count: u16 = source_count_in;
    var dimension_index: u32 = dimension_index_in;

    if (source_count > 4) {
        var attempt: u32 = 0;
        while (attempt < 3) : (attempt += 1) {
            var class_direction: Vector3 = .zero();
            class_direction.values[dimension_index] = 1.0;
            const class_distance: f32 = class_direction.dotProduct(parent_box.position);

            var count_a: u16 = 0;
            var count_b: u16 = 0;
            var bounds_a: Rectangle3 = Rectangle3.invertedInfinity();
            var bounds_b: Rectangle3 = Rectangle3.invertedInfinity();

            var source_index: u16 = 0;
            while (source_index < source_count) : (source_index += 1) {
                const box_reference: u16 = source[source_index];
                const box: *LightingBox = @ptrCast(solution.boxes + box_reference);

                var box_rect: Rectangle3 = Rectangle3.fromCenterHalfDimension(box.position, box.radius);
                if (class_direction.dotProduct(box.position) < class_distance) {
                    dest[count_a] = box_reference;
                    bounds_a = bounds_a.getUnionWith(&box_rect);
                    count_a += 1;
                } else {
                    dest[(source_count - 1) - count_b] = box_reference;
                    bounds_b = bounds_b.getUnionWith(&box_rect);
                    count_b += 1;
                }
            }

            const next_dimension_index: u32 = @mod(dimension_index + 1, 3);

            if (count_a > 0 and count_b > 0) {
                const child_box_a_at: u16 = addBoxStorage(solution);
                var child_box_a: *LightingBox = @ptrCast(solution.boxes + child_box_a_at);
                child_box_a.position = bounds_a.getCenter();
                child_box_a.radius = bounds_a.getRadius();
                splitBox(solution, child_box_a, count_a, dest, source, next_dimension_index);

                const child_box_b_at: u16 = addBoxStorage(solution);
                var child_box_b: *LightingBox = @ptrCast(solution.boxes + child_box_b_at);
                child_box_b.position = bounds_b.getCenter();
                child_box_b.radius = bounds_b.getRadius();
                splitBox(solution, child_box_b, count_b, dest + count_a, source, next_dimension_index);

                source_count = 2;
                source[0] = child_box_a_at;
                source[1] = child_box_b_at;
                break;
            }

            dimension_index = next_dimension_index;
        }
    }

    parent_box.child_count = source_count;
    parent_box.first_child_index = addBoxReferences(solution, source_count, source);
}

fn buildSpatialPartitionForLighting(solution: *LightingSolution) void {
    TimedBlock.beginFunction(@src(), .BuildSpatialPartitionForLighting);
    defer TimedBlock.endFunction(@src(), .BuildSpatialPartitionForLighting);

    const actual_box_count: u16 = solution.box_count;

    var bounds: Rectangle3 = Rectangle3.invertedInfinity();
    var box_index: u16 = 0;
    while (box_index < solution.box_count) : (box_index += 1) {
        const box: *LightingBox = @ptrCast(solution.boxes + box_index);
        solution.scratch_a[box_index] = box_index;
        var box_rect: Rectangle3 = Rectangle3.fromCenterHalfDimension(box.position, box.radius);
        bounds = bounds.getUnionWith(&box_rect);
    }

    solution.root_box_index = addBoxReference(solution, addBoxStorage(solution));
    const root_box: *LightingBox = getBox(solution, solution.root_box_index);
    root_box.position = bounds.getCenter();
    root_box.radius = bounds.getRadius();

    splitBox(solution, root_box, actual_box_count, &solution.scratch_a, &solution.scratch_b, 0);
}

pub fn lightingTest(group: *RenderGroup, solution: *LightingSolution) void {
    solution.box_reference_count = 0;
    solution.box_count = @intCast(group.commands.light_box_count);
    const original_box_count: u32 = solution.box_count;
    solution.boxes = group.commands.light_boxes;
    solution.point_count = group.commands.light_point_index;

    solution.total_ray_count = 0;
    solution.raycast_point_count = 0;
    solution.raycast_box_count = 0;

    var box_index: u32 = 0;
    while (box_index < original_box_count) : (box_index += 1) {
        const box: *LightingBox = @ptrCast(solution.boxes + box_index);

        var light_index: u32 = box.light_index[0];
        var surface_index: u32 = 0;
        while (surface_index < 6) : (surface_index += 1) {
            const surface: LightBoxSurface = getBoxSurface(box.position, box.radius, surface_index);
            const y_subdivision_count = 2;
            const x_subdivision_count = 2;
            std.debug.assert((x_subdivision_count * y_subdivision_count) == 4);
            for (0..y_subdivision_count) |y_sub| {
                const y_sub_ratio: f32 = -0.5 + @as(f32, @floatFromInt(y_sub));
                for (0..x_subdivision_count) |x_sub| {
                    const x_sub_ratio: f32 = -0.5 + @as(f32, @floatFromInt(x_sub));
                    var point: *LightingPoint = &solution.points[light_index];

                    point.normal = surface.normal;
                    point.position = surface.position
                        .plus(surface.x_axis.scaledTo(x_sub_ratio * surface.half_width))
                        .plus(surface.y_axis.scaledTo(y_sub_ratio * surface.half_height));

                    point.reflection_color = box.reflection_color.scaledTo(0.95);

                    const local_index: u32 = light_index - box.light_index[0];
                    solution.emission_color0[light_index] =
                        Color3.new(1, 1, 1).scaledTo(box.emission * MAX_LIGHT_EMISSION);
                    solution.emission_color0[light_index] = solution.emission_color0[light_index].plus(
                        box.storage[local_index].emit,
                    );
                    solution.average_direction_to_light[light_index] = box.storage[local_index].direction;

                    light_index += 1;
                    std.debug.assert(light_index < LIGHT_DATA_WIDTH);
                }
            }
            std.debug.assert(light_index == box.light_index[surface_index + 1]);
        }
    }

    buildSpatialPartitionForLighting(solution);

    DebugInterface.debugValue(@src(), &group.commands.light_box_count, "LightBoxCount");
    DebugInterface.debugValue(@src(), &solution.box_count, "BoxCount");
    DebugInterface.debugValue(@src(), &solution.point_count, "PointCount");

    if (SLOW) {
        var point_index: u32 = 0;
        while (point_index < solution.point_count) : (point_index += 1) {
            const emission_color1: Color3 = solution.emission_color1[point_index];
            std.debug.assert(emission_color1.r() == 0 and emission_color1.g() == 0 and emission_color1.b() == 0);
        }
    }

    computeLightPropagation(solution);

    box_index = 0;
    while (box_index < original_box_count) : (box_index += 1) {
        const box: *LightingBox = @ptrCast(solution.boxes + box_index);
        // const first_point: *LightingPointState = @ptrCast(box.storage);
        // const valid: bool = first_point.direction.x() != 0 or
        //     first_point.direction.y() != 0 or
        //     first_point.direction.z() != 0;
        const valid: bool = false;

        const local_count: u32 = box.light_index[6] - box.light_index[0];
        if (valid) {
            const t: f32 = 0.1;
            var local_index: u32 = 0;
            while (local_index < local_count) : (local_index += 1) {
                const point_index: u32 = local_index + box.light_index[0];
                box.storage[local_index].emit =
                    box.storage[local_index].emit.lerp(solution.emission_color0[point_index], t);
                solution.emission_color0[point_index] = box.storage[local_index].emit;

                box.storage[local_index].direction =
                    box.storage[local_index].direction.lerp(
                        solution.average_direction_to_light[point_index].normalizeOrZero(),
                        t,
                    ).normalizeOrZero();
                solution.average_direction_to_light[point_index] = box.storage[local_index].direction;
            }
        } else {
            var local_index: u32 = 0;
            while (local_index < local_count) : (local_index += 1) {
                const point_index: u32 = local_index + box.light_index[0];
                box.storage[local_index].emit = solution.emission_color0[point_index];
                const direction: Vector3 = solution.average_direction_to_light[point_index].normalizeOrZero();
                solution.average_direction_to_light[point_index] = direction;
                box.storage[local_index].direction = direction;
            }
        }
    }

    DebugInterface.debugValue(@src(), &solution.total_ray_count, "TotalRayCount");
    DebugInterface.debugValue(@src(), &solution.raycast_point_count, "RaycastPointCount");
    DebugInterface.debugValue(@src(), &solution.raycast_box_count, "RaycastBoxCount");
}

pub fn outputLightingPoints(
    group: *RenderGroup,
    solution: *LightingSolution,
    opt_textures: ?*LightingTextures,
) void {
    TimedBlock.beginFunction(@src(), .OutputLightingPoints);
    defer TimedBlock.endFunction(@src(), .OutputLightingPoints);

    _ = opt_textures;

    const commands: *RenderCommands = group.commands;
    _ = group.getCurrentQuads(solution.point_count);

    const element_width: f32 = 0.25;
    const element_height: f32 = 0.25;
    const bitmap: ?*LoadedBitmap = commands.white_bitmap;

    var box_index: u32 = 0;
    while (box_index < commands.light_box_count) : (box_index += 1) {
        var box_surface_index: u32 = 0;
        while (box_surface_index < 6) : (box_surface_index += 1) {
            const box: *LightingBox = &solution.boxes[box_index];
            const box_surface: LightBoxSurface =
                getBoxSurface(box.position, box.radius, box_surface_index);

            var point_index: u32 = box.light_index[box_surface_index];
            while (point_index < box.light_index[box_surface_index + 1]) : (point_index += 1) {
                const point: *LightingPoint = &solution.points[point_index];

                const position: Vector3 = point.position;
                const x_axis: Vector3 = box_surface.x_axis;
                const y_axis: Vector3 = box_surface.y_axis;

                const emission_color: Color3 = solution.emission_color0[point_index];

                var front_emission_color: Color = emission_color.clamp01().toColor(1);

                var position0: Vector4 = .zero();
                var position1: Vector4 = .zero();
                var position2: Vector4 = .zero();
                var position3: Vector4 = .zero();

                var color0: u32 = 0;
                var color1: u32 = 0;
                var color2: u32 = 0;
                var color3: u32 = 0;

                const x: Vector3 = x_axis.scaledTo(0.5 * element_width);
                const y: Vector3 = y_axis.scaledTo(0.5 * element_height);

                _ = position0.setXYZ(position.minus(x).minus(y));
                _ = position1.setXYZ(position.plus(x).minus(y));
                _ = position2.setXYZ(position.plus(x).plus(y));
                _ = position3.setXYZ(position.minus(x).plus(y));

                _ = position0.setW(0);
                _ = position1.setW(0);
                _ = position2.setW(0);
                _ = position3.setW(0);

                const front_emission_color32 = front_emission_color.scaledTo(255.0).packColorRGBA();
                color0 = front_emission_color32;
                color1 = front_emission_color32;
                color2 = front_emission_color32;
                color3 = front_emission_color32;

                const uv: Vector2 = .zero();
                group.pushQuad(
                    bitmap,
                    position0,
                    uv,
                    color0,
                    position1,
                    uv,
                    color1,
                    position2,
                    uv,
                    color2,
                    position3,
                    uv,
                    color3,
                    null,
                    null,
                    null,
                );
            }
        }
    }
}

pub fn outputLightingTextures(group: *RenderGroup, solution: *LightingSolution, dest: *LightingTextures) void {
    TimedBlock.beginFunction(@src(), .OutputLightingTextures);
    defer TimedBlock.endFunction(@src(), .OutputLightingTextures);

    var point_index: u32 = 1; // Light point index 0 is never used.
    while (point_index < solution.point_count) : (point_index += 1) {
        const position: Vector3 = solution.points[point_index].position;
        var color: Color3 = solution.emission_color0[point_index];
        var direction: Vector3 = solution.average_direction_to_light[point_index];

        if (direction.z() < 0) {
            // _ = direction.setZ(-direction.z());
            // Negate the red channel to indicate that Z was negative, since we have no storage for the sign of Z.
            _ = color.setR(-color.r());
        }

        dest.light_data0[point_index] = .new(position.x(), position.y(), position.z(), direction.x());
        dest.light_data1[point_index] = .new(color.r(), color.g(), color.b(), direction.y());
    }

    group.pushLighting(dest);
}
