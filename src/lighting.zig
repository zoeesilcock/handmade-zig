const math = @import("math.zig");
const rendergroup = @import("rendergroup.zig");
const lighting = @import("lighting.zig");
const simd = @import("simd.zig");
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
const V3_4x = simd.V3_4x;
const F32_4x = simd.F32_4x;
const U32_4x = simd.U32_4x;
const Bool_4x = simd.Bool_4x;
const RenderGroup = rendergroup.RenderGroup;
const RenderCommands = shared.RenderCommands;
const LoadedBitmap = asset.LoadedBitmap;
const MemoryArena = memory.MemoryArena;
const DebugInterface = debug_interface.DebugInterface;
const TimedBlock = debug_interface.TimedBlock;

pub const LIGHT_POINTS_PER_CHUNK = 24;
pub const MAX_LIGHT_EMISSION = 25.0;
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
    extended_point_count: u16,
    points: [LIGHT_DATA_WIDTH]LightingPoint = undefined,

    // PPS = Photons per second.
    initial_pps: [LIGHT_DATA_WIDTH]Color3 = undefined,
    emission_pps: [LIGHT_DATA_WIDTH]Color3 = undefined, // This isn't really needed, could be recomputed on output.

    entropy_counter: u32,

    debug_box_draw_depth: u32,

    sample_table: [16]Vector3 = undefined, // Must always have a length that is a power of two.

    max_work_count: u32,
    works: [*]LightingWork = undefined, // 256.
    accumulated_weight: [*]f32 = undefined, // LIGHT_DATA_WIDTH.
    accumulated_pps: [*]Color3 = undefined, // LIGHT_DATA_WIDTH.
    average_direction_to_light: [*]Vector3 = undefined, // LIGHT_DATA_WIDTH.

    update_debug_lines: bool,
    debug_point_index: u32,
    debug_line_count: u32,
    debug_lines: [4096]DebugLine = undefined,
};

const LightingWork = extern struct {
    solution: *LightingSolution,
    first_sample_index: u32,
    one_past_last_sample_index: u32,

    total_casts_initiated: u32 = 0, // Number of attempts to raycast from a point.
    total_partitions_tested: u32 = 0, // Number of partition boxes checked.
    total_partition_leaves_used: u32 = 0, // Number of partition boxes used as leaves.
    total_leaves_tested: u32 = 0, // Number of leaf boxes checked.
    big_pad: [32]u8 = undefined,
};

const DebugLine = extern struct {
    from_position: Vector3,
    to_position: Vector3,
    color: Color,
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
    x_axis: Vector3,
    y_axis: Vector3,
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
    hit: Bool_4x = @splat(false),
    box_index: U32_4x = @splat(0),
    box_surface_index: U32_4x = @splat(0),
    t_ray: F32_4x = @splat(0),
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
    work: *LightingWork,
    ray_origin: V3_4x,
    ray_direction: V3_4x,
) RaycastResult {
    const solution: *LightingSolution = work.solution;
    work.total_casts_initiated += 1;

    var result: RaycastResult = .{};
    result.t_ray = @splat(std.math.floatMax(f32));

    var depth: u32 = 0;
    var box_stack: [64]*LightingBox = undefined;
    box_stack[depth] = getBox(solution, solution.root_box_index);
    depth += 1;

    const t_close_enough: F32_4x = @splat(5);

    if (false) {
        // const ray_direction_positive: V3_4x = ray_direction.lessThan(@as(V3_4x, @splat(0)));
        var sign: [3]F32_4x = undefined;
        var box_surface_index: [3]U32_4x = undefined;
        {
            var axis_index: u32 = 0;
            while (axis_index < 3) : (axis_index += 1) {
                var c_index: u32 = 0;
                while (c_index < 4) : (c_index += 1) {
                    const positive: u32 = @intFromBool(ray_direction.getComponent(c_index).values[axis_index] < 0);

                    box_surface_index[axis_index][c_index] = @intCast((axis_index << 1) | positive);
                    sign[axis_index][c_index] = if (positive != 0) 1.0 else 0.0;
                }
            }
        }

        while (depth > 0) {
            depth -= 1;
            const root_box: *LightingBox = box_stack[depth];

            var source_index: u32 = root_box.first_child_index;
            while (source_index < (root_box.first_child_index + root_box.child_count)) : (source_index += 1) {
                const box: *LightingBox = getBox(solution, source_index);

                const box_position: V3_4x = .fromVector3(box.position);
                const rel_origin: V3_4x = ray_origin.minus(box_position);
                const box_radius: V3_4x = .fromVector3(box.radius);

                var is_in_box = false;
                if (box.child_count > 0) {
                    work.total_partitions_tested += 1;
                    const comparison: V3_4x = rel_origin.absoluteValue().lessThanOrEqualTo(box_radius);
                    is_in_box = comparison.all3TrueInAtLeastOneLane();
                } else {
                    work.total_leaves_tested += 1;
                }

                if (is_in_box) {
                    std.debug.assert(depth < box_stack.len);
                    box_stack[depth] = box;
                    depth += 1;
                } else {
                    var axis_index: u32 = 0;
                    while (axis_index < 3) : (axis_index += 1) {
                        var face_rel_origin: V3_4x = rel_origin;
                        face_rel_origin.setLane(
                            axis_index,
                            face_rel_origin.getLane(axis_index) - sign[axis_index] * box_radius.getLane(axis_index),
                        );
                        const t_ray: F32_4x =
                            face_rel_origin.negated().getLane(axis_index) / ray_direction.getLane(axis_index);

                        const delta: V3_4x = ray_direction.scaledToV(t_ray);
                        const face_rel_position: V3_4x = face_rel_origin.plus(delta);

                        const zero: F32_4x = @splat(0);
                        const t_check: Bool_4x = (t_ray > zero) & (t_ray < result.t_ray);

                        if (simd.anyTrue(t_check)) {
                            const x_check: F32_4x = if (axis_index == 0) face_rel_position.y else face_rel_position.x;
                            const half_width: F32_4x = if (axis_index == 0) box_radius.y else box_radius.x;

                            const y_check: F32_4x = if (axis_index == 2) face_rel_position.y else face_rel_position.z;
                            const half_height: F32_4x = if (axis_index == 2) box_radius.y else box_radius.z;

                            const bound_check: Bool_4x = (@abs(x_check) <= half_width) & (@abs(y_check) <= half_height);
                            const mask: Bool_4x = bound_check & t_check;
                            const close_enough: Bool_4x = mask & (t_ray < t_close_enough);

                            if (box.child_count > 0 and simd.anyTrue(close_enough)) {
                                std.debug.assert(depth < box_stack.len);
                                box_stack[depth] = box;
                                depth += 1;
                                break;
                            } else if (simd.anyTrue(@bitCast(mask))) {
                                result.hit |= mask;
                                result.t_ray = @select(f32, mask, t_ray, result.t_ray);
                                result.box_index =
                                    @select(u32, mask, @as(U32_4x, @splat(source_index)), result.box_index);
                                result.box_surface_index =
                                    @select(u32, mask, box_surface_index[axis_index], result.box_surface_index);

                                if (simd.allTrue(@bitCast(mask))) {
                                    work.total_partition_leaves_used += 1;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    } else {
        const inverse_ray_direction: V3_4x = @as(V3_4x, .splat(@splat(1))).dividedBy(ray_direction);

        while (depth > 0) {
            depth -= 1;
            const root_box: *LightingBox = box_stack[depth];

            var source_index: u32 = root_box.first_child_index;
            while (source_index < (root_box.first_child_index + root_box.child_count)) : (source_index += 1) {
                const box: *LightingBox = getBox(solution, source_index);

                if (box.child_count > 0) {
                    work.total_partitions_tested += 1;
                } else {
                    work.total_leaves_tested += 1;
                }

                const box_position: V3_4x = .fromVector3(box.position);
                const box_radius: V3_4x = .fromVector3(box.radius);
                const box_min: V3_4x = box_position.minus(box_radius);
                const box_max: V3_4x = box_position.plus(box_radius);

                const t_box_min: V3_4x = box_min.minus(ray_origin).times(inverse_ray_direction);
                const t_box_max: V3_4x = box_max.minus(ray_origin).times(inverse_ray_direction);

                const t_min3: V3_4x = t_box_min.min(t_box_max);
                const t_max3: V3_4x = t_box_min.max(t_box_max);

                const t_min: F32_4x = @max(t_min3.x, @max(t_min3.y, t_min3.z));
                const t_max: F32_4x = @min(t_max3.x, @min(t_max3.y, t_max3.z));

                const max_pass: Bool_4x = t_max > @as(F32_4x, @splat(0));
                if (simd.anyTrue(max_pass)) {
                    const t_inside: Bool_4x = max_pass & (t_min < @as(F32_4x, @splat(0)));
                    const t_valid: Bool_4x = t_min < t_max;
                    const mask: Bool_4x = t_valid & (t_min < result.t_ray);
                    const close_enough: Bool_4x = mask & (t_min < t_close_enough);

                    if (box.child_count > 0 and (simd.anyTrue(t_inside) or simd.anyTrue(close_enough))) {
                        std.debug.assert(depth < box_stack.len);
                        box_stack[depth] = box;
                        depth += 1;
                    } else if (simd.anyTrue(t_valid)) {
                        var box_surface_index: U32_4x = @as(U32_4x, @splat(0)) &
                            @as(U32_4x, @intFromBool(t_box_min.x == t_min));
                        box_surface_index |= @as(U32_4x, @splat(1)) &
                            @as(U32_4x, @intFromBool(t_box_min.x == t_min));
                        box_surface_index |= @as(U32_4x, @splat(2)) &
                            @as(U32_4x, @intFromBool(t_box_min.y == t_min));
                        box_surface_index |= @as(U32_4x, @splat(3)) &
                            @as(U32_4x, @intFromBool(t_box_min.y == t_min));
                        box_surface_index |= @as(U32_4x, @splat(4)) &
                            @as(U32_4x, @intFromBool(t_box_min.z == t_min));
                        box_surface_index |= @as(U32_4x, @splat(5)) &
                            @as(U32_4x, @intFromBool(t_box_min.z == t_min));

                        result.t_ray = @select(f32, mask, t_min, result.t_ray);
                        result.hit |= mask;
                        result.box_index =
                            @select(u32, mask, @as(U32_4x, @splat(source_index)), result.box_index);
                        result.box_surface_index =
                            @select(u32, mask, box_surface_index, result.box_surface_index);

                        if (simd.allTrue(@bitCast(mask))) {
                            work.total_partition_leaves_used += 1;
                            break;
                        }
                    }
                }
            }
        }
    }

    return result;
}

fn pushDebugLine(solution: *LightingSolution, from_position: Vector3, to_position: Vector3, color: Color) void {
    if (solution.update_debug_lines) {
        std.debug.assert(solution.debug_line_count < solution.debug_lines.len);

        const line: *DebugLine = &solution.debug_lines[solution.debug_line_count];
        solution.debug_line_count += 1;

        line.from_position = from_position;
        line.to_position = to_position;
        line.color = color;
    }
}

fn computeLightPropagation(
    work: *LightingWork,
) void {
    // TimedBlock.beginFunction(@src(), .ComputeLightPropagation);
    // defer TimedBlock.endFunction(@src(), .ComputeLightPropagation);

    const ray_count: u32 = 16;
    const solution: *LightingSolution = work.solution;
    const first_sample_index: u32 = work.first_sample_index;
    const one_past_last_sample_index: u32 = work.one_past_last_sample_index;

    // const sky_color: Color3 = .new(0.2, 0.2, 0.95);
    const moon_color: Color3 = Color3.new(0.1, 0.8, 1.0).scaledTo(0.2);
    // const ground_color: Color3 = .new(0.3, 0.2, 0.1);
    // const sun_direction: Vector3 = Vector3.new(1, 1, 1).normalizeOrZero();

    var sample_point_index: u32 = first_sample_index; // Light point index 0 is never used.
    while (sample_point_index < one_past_last_sample_index) : (sample_point_index += 1) {
        const sample_point: *LightingPoint = &solution.points[sample_point_index];
        const ray_origin: V3_4x = .fromVector3(sample_point.position);
        const sample_point_normal: V3_4x = .fromVector3(sample_point.normal);

        var series: random.Series = .seed(213897 * (2398 + solution.entropy_counter));

        var ray_index: u32 = 0;
        while (ray_index < ray_count) : (ray_index += 1) {
            const basis: V3_4x = .fromVector3(
                Vector3.new(
                    series.randomBilateral(),
                    series.randomBilateral(),
                    series.randomBilateral(),
                ).normalizeOrZero(),
            );
            var delta: V3_4x = .fromAxes(
                series.randomBilateral_4x(),
                series.randomBilateral_4x(),
                series.randomBilateral_4x(),
            );

            var sample_direction_4x: V3_4x = basis.plus(delta.scaledTo(0.1)).approxNormalizeOrZero();
            const mask: Bool_4x =
                sample_direction_4x.dotProduct(sample_point_normal) < @as(F32_4x, @splat(0));
            sample_direction_4x = sample_direction_4x.select(mask, sample_direction_4x.negated());

            const ray: RaycastResult = raycast(work, ray_origin, sample_direction_4x);

            const ray_position_4x: V3_4x = ray_origin.plus(sample_direction_4x.scaledToV(ray.t_ray));

            var sub_ray: u32 = 0;
            while (sub_ray < 4) : (sub_ray += 1) {
                // if (false) {
                //     if (sample_point_index == solution.debug_point_index) {
                //         const draw_length: f32 = 0.25;
                //         const end_point: Vector3 = sample_point.position.plus(sample_direction.scaledTo(
                //             if (ray.box != null) t_ray else draw_length,
                //         ));
                //
                //         pushDebugLine(
                //             solution,
                //             sample_point.position,
                //             end_point,
                //             if (ray.box != null) .new(0, 1, 0, 1) else .new(1, 0, 0, 1),
                //         );
                //     }
                // }

                var transfer_pps: Color3 = .zero();
                if (ray.hit[sub_ray]) {
                    const hit_box: *LightingBox = getBox(solution, ray.box_index[sub_ray]);
                    const box_surface_index: u32 = ray.box_surface_index[sub_ray];
                    const ray_position: Vector3 = ray_position_4x.getComponent(sub_ray);

                    // TODO: Update this transfer to be bidirectional.
                    // TODO: Stratified sampling?

                    const hit_index: u32 = hit_box.light_index[box_surface_index];
                    const hit_point_count: u32 =
                        hit_box.light_index[box_surface_index + 1] - hit_index;

                    var total_weight: f32 = 0;
                    var surface_point_index: u32 = 0;
                    while (surface_point_index < hit_point_count) : (surface_point_index += 1) {
                        const hit_point_index: u32 = hit_index + surface_point_index;
                        const hit_point: *LightingPoint = &solution.points[hit_point_index];
                        const distance_sq: f32 =
                            ray_position.minus(hit_point.position).lengthSquared();
                        const inverse_distance_sq: f32 = 1.0 / (1.0 + distance_sq);

                        transfer_pps = transfer_pps.plus(
                            hit_point.reflection_color.hadamardProduct(solution.initial_pps[hit_point_index])
                                .scaledTo(inverse_distance_sq),
                        );
                        total_weight += inverse_distance_sq;
                    }

                    var inverse_total_weight: f32 = 1;
                    if (total_weight > 0) {
                        inverse_total_weight = 1.0 / total_weight;
                        transfer_pps = transfer_pps.scaledTo(inverse_total_weight);
                    }
                } else {
                    transfer_pps = moon_color;
                }

                // Accumulate sample.
                const normal_to_light: Vector3 = sample_direction_4x.getComponent(sub_ray);
                const surface_normal: Vector3 = solution.points[sample_point_index].normal;
                const angular_falloff: f32 = math.clampf01(surface_normal.dotProduct(normal_to_light));

                const sample_color: Color3 = transfer_pps.scaledTo(angular_falloff);
                const weight: f32 = sample_color.length();

                solution.accumulated_weight[sample_point_index] += 1;
                solution.accumulated_pps[sample_point_index] =
                    solution.accumulated_pps[sample_point_index].plus(
                        sample_color,
                    );
                solution.average_direction_to_light[sample_point_index] =
                    solution.average_direction_to_light[sample_point_index].plus(
                        normal_to_light.scaledTo(weight),
                    );
            }
        }
    }
}

pub fn doLightingWork(queue: shared.PlatformWorkQueuePtr, data: *anyopaque) callconv(.c) void {
    _ = queue;

    TimedBlock.beginFunction(@src(), .DoLightingWork);
    defer TimedBlock.endFunction(@src(), .DoLightingWork);

    const work: *LightingWork = @ptrCast(@alignCast(data));

    computeLightPropagation(work);
}

fn computeAllLightPropagation(
    solution: *LightingSolution,
    lighting_queue: *shared.PlatformWorkQueue,
) void {
    var work_count: u32 = 0;
    var works: [*]LightingWork = solution.works;

    if (true) {
        const points_per_work: u32 = 256;
        var done: bool = false;

        var work_index: u32 = 0;
        while (work_index < solution.max_work_count) : (work_index += 1) {
            const work = &works[work_count];
            work_count += 1;

            std.debug.assert((@intFromPtr(work) & 63) == 0);

            memory.zeroStruct(LightingWork, work);

            work.solution = solution;
            work.first_sample_index = work_index * points_per_work;
            work.one_past_last_sample_index = work.first_sample_index + points_per_work;
            if (work.one_past_last_sample_index > solution.point_count) {
                work.one_past_last_sample_index = solution.point_count;
                done = true;
            }

            if (work.first_sample_index == 0) {
                work.first_sample_index = 1;
            }
            shared.platform.addQueueEntry(lighting_queue, &doLightingWork, work);

            if (done) {
                break;
            }
        }
        shared.platform.completeAllQueuedWork(lighting_queue);
        std.debug.assert(done == true);
    } else {
        const work = &works[work_count];
        work_count += 1;
        work.* = .{
            .solution = solution,
            .first_sample_index = 1,
            .one_past_last_sample_index = solution.point_count,
        };
        computeLightPropagation(work);
    }

    var total_casts_initiated: u32 = 0;
    var total_partitions_tested: u32 = 0;
    var total_partition_leaves_used: u32 = 0;
    var total_leaves_tested: u32 = 0;

    var work_index: u32 = 0;
    while (work_index < work_count) : (work_index += 1) {
        const work = &works[work_index];
        total_casts_initiated += work.total_casts_initiated;
        total_partitions_tested += work.total_partitions_tested;
        total_partition_leaves_used += work.total_partition_leaves_used;
        total_leaves_tested += work.total_leaves_tested;
    }

    DebugInterface.debugValue(@src(), &total_casts_initiated, "TotalCastsInitiated");
    DebugInterface.debugValue(@src(), &total_partitions_tested, "TotalPartitionsTested");
    DebugInterface.debugValue(@src(), &total_partition_leaves_used, "TotalPartitionLeavesUsed");
    DebugInterface.debugValue(@src(), &total_leaves_tested, "TotalLeavesTested");

    var partitions_per_cast: f32 =
        @floatCast(@as(f64, @floatFromInt(total_partitions_tested)) / @as(f64, @floatFromInt(total_casts_initiated)));
    var leaves_per_cast: f32 =
        @floatCast(@as(f64, @floatFromInt(total_leaves_tested)) / @as(f64, @floatFromInt(total_casts_initiated)));
    var partitions_per_leaf: f32 =
        @floatCast(@as(f64, @floatFromInt(total_partitions_tested)) / @as(f64, @floatFromInt(total_leaves_tested)));

    DebugInterface.debugValue(@src(), &partitions_per_cast, "PartitionsPerCast");
    DebugInterface.debugValue(@src(), &leaves_per_cast, "LeavesPerCast");
    DebugInterface.debugValue(@src(), &partitions_per_leaf, "PartitionsPerLeaf");
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
            var next_dimension_index: u32 = 0;

            if (true) {
                // One-plane case (k-d-tree-like).
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

                next_dimension_index = @mod(dimension_index + 1, 3);

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
            } else {
                // Two-plane case (quad-tree-like).
            }

            dimension_index = next_dimension_index;
        }
    }

    parent_box.child_count = source_count;
    parent_box.first_child_index = addBoxReferences(solution, source_count, source);

    var assign_light_index: u16 = solution.extended_point_count;
    parent_box.light_index[0] = assign_light_index;
    assign_light_index += 1;
    parent_box.light_index[1] = assign_light_index;
    assign_light_index += 1;
    parent_box.light_index[2] = assign_light_index;
    assign_light_index += 1;
    parent_box.light_index[3] = assign_light_index;
    assign_light_index += 1;
    parent_box.light_index[4] = assign_light_index;
    assign_light_index += 1;
    parent_box.light_index[5] = assign_light_index;
    assign_light_index += 1;
    parent_box.light_index[6] = assign_light_index;
    solution.extended_point_count = assign_light_index;

    var surface_index: u32 = 0;
    while (surface_index < 6) : (surface_index += 1) {
        const light_index: u16 = parent_box.light_index[surface_index];
        var point: *LightingPoint = &solution.points[light_index];
        const surface: LightBoxSurface = getBoxSurface(parent_box.position, parent_box.radius, surface_index);

        point.normal = surface.normal;
        point.position = surface.position;
        solution.average_direction_to_light[light_index] = .zero();
        solution.accumulated_weight[light_index] = 0;

        var reflection_color: Color3 = .zero();
        var emission_pps: Color3 = .zero();
        var initial_pps: Color3 = .zero();
        var total_weight: f32 = 0;

        var child_index: u16 = parent_box.first_child_index;
        while (child_index < (parent_box.first_child_index + parent_box.child_count)) : (child_index += 1) {
            const child_box: *LightingBox = getBox(solution, child_index);
            var child_point_index: u32 = child_box.light_index[surface_index];
            while (child_point_index < child_box.light_index[surface_index + 1]) : (child_point_index += 1) {
                const child_point: *LightingPoint = &solution.points[child_point_index];
                const weight: f32 = 1.0 / (1.0 + point.position.minus(child_point.position).lengthSquared());

                reflection_color = reflection_color.plus(child_point.reflection_color.scaledTo(weight));
                emission_pps = emission_pps.plus(solution.emission_pps[child_point_index].scaledTo(weight));
                initial_pps = initial_pps.plus(solution.initial_pps[child_point_index].scaledTo(weight));
                total_weight += weight;
            }
        }

        var inverse_weight: f32 = 1;
        if (total_weight > 0) {
            inverse_weight = 1.0 / total_weight;
        }

        point.reflection_color = reflection_color.scaledTo(inverse_weight);
        solution.emission_pps[light_index] = emission_pps.scaledTo(inverse_weight);
        solution.initial_pps[light_index] = initial_pps.scaledTo(inverse_weight);
        solution.accumulated_pps[light_index] = solution.initial_pps[light_index];
    }
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

pub fn initLighting(solution: *LightingSolution, arena: *MemoryArena) void {
    solution.max_work_count = 256;
    solution.works = arena.pushArray(solution.max_work_count, LightingWork, .aligned(64, true));
    solution.accumulated_weight = arena.pushArray(LIGHT_DATA_WIDTH, f32, .aligned(64, true));
    solution.accumulated_pps = arena.pushArray(LIGHT_DATA_WIDTH, Color3, .aligned(64, true));
    solution.average_direction_to_light = arena.pushArray(LIGHT_DATA_WIDTH, Vector3, .aligned(64, true));
}

pub fn lightingTest(
    group: *RenderGroup,
    solution: *LightingSolution,
    lighting_queue: *shared.PlatformWorkQueue,
) void {
    TimedBlock.beginHudFunction(@src(), .LightingTest);
    defer TimedBlock.endHudFunction(@src(), .LightingTest);

    solution.sample_table[0] = Vector3.new(0.2, 0, 1).normalizeOrZero();
    solution.sample_table[1] = Vector3.new(-0.2, 0, 1).normalizeOrZero();
    solution.sample_table[2] = Vector3.new(0, 0.2, 1).normalizeOrZero();
    solution.sample_table[3] = Vector3.new(0, -0.2, 1).normalizeOrZero();

    solution.sample_table[4] = Vector3.new(-0.5, -0.5, 0.5).normalizeOrZero();
    solution.sample_table[5] = Vector3.new(-0.5, 0, 0.5).normalizeOrZero();
    solution.sample_table[6] = Vector3.new(-0.5, 0.5, 0.5).normalizeOrZero();
    solution.sample_table[7] = Vector3.new(0.5, -0.5, 0.5).normalizeOrZero();
    solution.sample_table[8] = Vector3.new(0.5, 0, 0.5).normalizeOrZero();
    solution.sample_table[9] = Vector3.new(0.5, 0.5, 0.5).normalizeOrZero();
    solution.sample_table[10] = Vector3.new(0, -0.5, 0.5).normalizeOrZero();
    solution.sample_table[11] = Vector3.new(0, 0.5, 0.5).normalizeOrZero();

    solution.sample_table[12] = Vector3.new(1, 0, 0.25).normalizeOrZero();
    solution.sample_table[13] = Vector3.new(-1, 0, 0.25).normalizeOrZero();
    solution.sample_table[14] = Vector3.new(0, 1, 0.25).normalizeOrZero();
    solution.sample_table[15] = Vector3.new(0, -1, 0.25).normalizeOrZero();

    if (solution.update_debug_lines) {
        solution.debug_line_count = 0;
    }
    solution.box_reference_count = 0;
    solution.box_count = @intCast(group.commands.light_box_count);
    const original_box_count: u32 = solution.box_count;
    solution.boxes = group.commands.light_boxes;
    solution.point_count = group.commands.light_point_index;
    solution.extended_point_count = solution.point_count;

    const entropy_frame_count: u32 = 256;
    const t_update: f32 = 0.05;

    const debug_location: Vector3 = .new(0, 0, 1);
    var debug_point_distance: f32 = std.math.floatMax(f32);

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
                    point.x_axis = surface.x_axis;
                    point.y_axis = surface.y_axis;
                    point.position = surface.position
                        .plus(surface.x_axis.scaledTo(x_sub_ratio * surface.half_width))
                        .plus(surface.y_axis.scaledTo(y_sub_ratio * surface.half_height));

                    point.reflection_color = box.reflection_color.scaledTo(0.95);

                    const local_index: u32 = light_index - box.light_index[0];
                    solution.emission_pps[light_index] =
                        Color3.new(1, 1, 1).scaledTo(box.emission * MAX_LIGHT_EMISSION);
                    solution.initial_pps[light_index] = solution.emission_pps[light_index].plus(
                        box.storage[local_index].emit,
                    );
                    solution.average_direction_to_light[light_index] = .zero();
                    solution.accumulated_pps[light_index] = .zero();
                    solution.accumulated_weight[light_index] = 0;

                    const this_distance: f32 = point.position.minus(debug_location).lengthSquared();
                    if (debug_point_distance > this_distance) {
                        solution.debug_point_index = light_index;
                        debug_point_distance = this_distance;
                    }

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

    computeAllLightPropagation(solution, lighting_queue);

    box_index = 0;
    while (box_index < original_box_count) : (box_index += 1) {
        const box: *LightingBox = @ptrCast(solution.boxes + box_index);
        const local_count: u32 = box.light_index[6] - box.light_index[0];
        var local_index: u32 = 0;
        while (local_index < local_count) : (local_index += 1) {
            const point_index: u32 = local_index + box.light_index[0];

            // Can probably remove the accumulated weight check if we always guarantee at least
            // one positively weighted sample per point?
            const accumulated_weight: f32 = solution.accumulated_weight[point_index];
            var inverse_weight: f32 = 0;
            if (accumulated_weight > 0) {
                inverse_weight = 1.0 / accumulated_weight;
            }
            const accumulated_pps: Color3 = solution.accumulated_pps[point_index].scaledTo(inverse_weight);
            const direction: Vector3 = solution.average_direction_to_light[point_index].normalizeOrZero();

            var last_pps: Color3 = accumulated_pps;
            var last_direction: Vector3 = direction;

            const box_store_direction: Vector3 = box.storage[local_index].direction;
            const valid: bool =
                box_store_direction.x() != 0 or
                box_store_direction.y() != 0 or
                box_store_direction.z() != 0;
            if (valid) {
                last_pps = box.storage[local_index].emit;
                last_direction = box_store_direction;
            }

            box.storage[local_index].emit = last_pps.lerp(accumulated_pps, t_update);
            solution.accumulated_pps[point_index] = box.storage[local_index].emit;

            box.storage[local_index].direction =
                last_direction.lerp(direction, t_update).normalizeOrZero();
            solution.average_direction_to_light[point_index] = box.storage[local_index].direction;
        }
    }

    _ = group.getCurrentQuads(solution.debug_line_count);
    const bitmap: ?*LoadedBitmap = group.commands.white_bitmap;
    var debug_line_index: u32 = 0;
    while (debug_line_index < solution.debug_line_count) : (debug_line_index += 1) {
        const line: *DebugLine = &solution.debug_lines[debug_line_index];

        group.pushLineSegment(bitmap, line.from_position, line.color, line.to_position, line.color, 0.01);
    }

    solution.entropy_counter += 1;
    if (solution.entropy_counter >= entropy_frame_count) {
        solution.entropy_counter = 0;
    }
}

fn outputLightingPointsRecurse(
    group: *RenderGroup,
    solution: *LightingSolution,
    box: *LightingBox,
    depth: u32,
) void {
    if (depth == 0 or box.child_count == 0) {
        const bitmap: ?*LoadedBitmap = group.commands.white_bitmap;

        var box_surface_index: u32 = 0;
        while (box_surface_index < 6) : (box_surface_index += 1) {
            const box_surface: LightBoxSurface =
                getBoxSurface(box.position, box.radius, box_surface_index);

            const point_count: u32 = box.light_index[box_surface_index + 1] - box.light_index[box_surface_index];
            var size_ratio: f32 = 1.8;
            if (point_count > 1) {
                size_ratio /= @floatFromInt(point_count);
            }
            const element_width: f32 = size_ratio * box_surface.half_width;
            const element_height: f32 = size_ratio * box_surface.half_height;

            var point_index: u32 = box.light_index[box_surface_index];
            while (point_index < box.light_index[box_surface_index + 1]) : (point_index += 1) {
                const point: *LightingPoint = &solution.points[point_index];

                const position: Vector3 = point.position;
                const x_axis: Vector3 = box_surface.x_axis;
                const y_axis: Vector3 = box_surface.y_axis;

                var emission_color: Color3 = solution.accumulated_pps[point_index];
                if (box.child_count == 0) {
                    emission_color = emission_color.plus(solution.emission_pps[point_index]);
                }

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
    } else {
        var child_index: u32 = 0;
        while (child_index < box.child_count) : (child_index += 1) {
            outputLightingPointsRecurse(
                group,
                solution,
                getBox(solution, (box.first_child_index + child_index)),
                depth - 1,
            );
        }
    }
}

pub fn outputLightingPoints(
    group: *RenderGroup,
    solution: *LightingSolution,
    opt_textures: ?*LightingTextures,
) void {
    TimedBlock.beginFunction(@src(), .OutputLightingPoints);
    defer TimedBlock.endFunction(@src(), .OutputLightingPoints);

    _ = opt_textures;
    _ = group.getCurrentQuads(solution.point_count);

    outputLightingPointsRecurse(
        group,
        solution,
        getBox(solution, solution.root_box_index),
        solution.debug_box_draw_depth,
    );
}

pub fn outputLightingTextures(group: *RenderGroup, solution: *LightingSolution, dest: *LightingTextures) void {
    TimedBlock.beginFunction(@src(), .OutputLightingTextures);
    defer TimedBlock.endFunction(@src(), .OutputLightingTextures);

    var point_index: u32 = 1; // Light point index 0 is never used.
    while (point_index < solution.point_count) : (point_index += 1) {
        const position: Vector3 = solution.points[point_index].position;
        var color: Color3 = solution.accumulated_pps[point_index].plus(solution.emission_pps[point_index]);
        var direction: Vector3 = solution.average_direction_to_light[point_index];

        // TODO: Stop stuffing normal once we're sure about the variance.
        // direction = solution.points[point_index].normal;

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
