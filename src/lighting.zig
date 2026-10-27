const math = @import("math.zig");
const box_mod = @import("box.zig");
const renderer = @import("renderer.zig");
const lighting = @import("lighting.zig");
const simd = @import("simd.zig");
const shared = @import("shared.zig");
const memory = @import("memory.zig");
const asset = @import("asset.zig");
const world_mod = @import("world.zig");
const intrinsics = @import("intrinsics.zig");
const random = @import("random.zig");
const handmade = @import("handmade.zig");
const sampling_spheres = @import("sampling_spheres_generated.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

var global_config = &@import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Vector3i = math.Vector3i;
const Vector3u = math.Vector3u;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const Color3 = math.Color3;
const V3_4x = simd.V3_4x;
const F32_4x = simd.F32_4x;
const U32_4x = simd.U32_4x;
const Bool_4x = simd.Bool_4x;
const RenderGroup = renderer.RenderGroup;
const RenderSetup = renderer.RenderSetup;
const RenderCommands = renderer.RenderCommands;
const RendererTexture = renderer.RendererTexture;
const LightingBox = renderer.LightingBox;
const LightProbeIrradiance = renderer.LightProbeIrradiance;
const MemoryArena = memory.MemoryArena;
const DebugInterface = debug_interface.DebugInterface;
const TimedBlock = debug_interface.TimedBlock;
const LightSamplingSphere = sampling_spheres.LightSamplingSphere;
const World = world_mod.World;
const WorldPosition = world_mod.WorldPosition;

const LIGHT_SAMPLING_SPHERE_COUNT = sampling_spheres.LIGHT_SAMPLING_SPHERE_COUNT;
const LIGHT_SAMPLING_SPHERE_MASK = sampling_spheres.LIGHT_SAMPLING_SPHERE_MASK;
const LIGHT_SAMPLING_RAY_BUNDLES_PER_SPHERE = sampling_spheres.LIGHT_SAMPLING_RAY_BUNDLES_PER_SPHERE;
const LIGHT_SAMPLING_TOTAL_RAYS_PER_SPHERE = sampling_spheres.LIGHT_SAMPLING_TOTAL_RAYS_PER_SPHERE;
const LIGHT_POINTS_PER_CHUNK = renderer.LIGHT_POINTS_PER_CHUNK;
const INTERNAL = shared.INTERNAL;
pub const LIGHT_TEST_ACCUMULATION_COUNT = 1024;
pub const MAX_LIGHT_EMISSION = 25.0;
pub const LIGHT_DATA_WIDTH = 2 * 8192;
pub const MAX_LIGHT_BOX_COUNT = 2 * 8192;
pub const LIGHT_DIRECTION_COUNT = 4;
pub const LIGHT_CHUNK_COUNT = LIGHT_DATA_WIDTH / LIGHT_POINTS_PER_CHUNK;
pub const LIGHT_LOOKUP_VOXEL_DIM_POW_2 = 5;
pub const LIGHT_LOOKUP_VOXEL_DIM = (1 << LIGHT_LOOKUP_VOXEL_DIM_POW_2);
pub const LIGHT_LARGE_VOXEL_DIM_POW_2 = LIGHT_LOOKUP_VOXEL_DIM_POW_2 + 1;
pub const LIGHT_LARGE_VOXEL_DIM = (1 << LIGHT_LARGE_VOXEL_DIM_POW_2);
pub const MAX_LIGHT_PROBE_COUNT = 2 * 8192;
pub const MAX_LIGHT_OCCLUDER_COUNT = 2 * 8192;
pub const MAX_LIGHT_INTENSITY: f32 = 10.0;
const TEST_LIGHT_SPHERE = false;
const TEST_LIGHT_CHECKERBOARD = false;
const TEST_LIGHT_TRANSFER = true;

const SLOW = shared.SLOW;

// const SpatialIndexMapping = extern struct {
//     cell_coord: Vector3i = .zero(),
//     uvw: Vector3 = .zero(),
// };
//
// const LightProbeSpatialIndex = extern struct {
//     min_corner: Vector3,
//     cell_dimension: Vector3,
//     inverse_cell_dimension: Vector3,
//     dimension_power_of_2: Vector3i,
//     total_cell_count: u32,
//     light_index: [*]u16,
//
//     fn mapIntoGrid(self: *LightProbeSpatialIndex, position: Vector3) SpatialIndexMapping {
//         var result: SpatialIndexMapping = .{};
//         var f_coord: Vector3 = self.inverse_cell_dimension.hadamardProduct(position.minus(self.min_corner));
//         result.cell_coord = f_coord.f32ToI32();
//
//         // Doing this here makes it well-bounded, but it gives incorrect results for queries outside the grid.
//         result.uvw = f_coord.minus(result.cell_coord.i32ToF32());
//
//         _ = result.cell_coord.setX(math.clampi32(
//             0,
//             result.cell_coord.x(),
//             (@as(i32, 1) << @intCast(self.dimension_power_of_2.x())) - 1,
//         ));
//         _ = result.cell_coord.setY(math.clampi32(
//             0,
//             result.cell_coord.y(),
//             (@as(i32, 1) << @intCast(self.dimension_power_of_2.y())) - 1,
//         ));
//         _ = result.cell_coord.setZ(math.clampi32(
//             0,
//             result.cell_coord.z(),
//             (@as(i32, 1) << @intCast(self.dimension_power_of_2.z())) - 1,
//         ));
//
//         return result;
//     }
//
//     fn getSpatialIndexAddress(self: *LightProbeSpatialIndex, cell_coord: Vector3i) u32 {
//         const index: u32 =
//             @as(u32, @intCast((((cell_coord.z() << @as(u5, @intCast(self.dimension_power_of_2.y()))) | cell_coord.y()) <<
//                 @as(u5, @intCast(self.dimension_power_of_2.x()))) | @as(i32, @intCast(cell_coord.x()))));
//
//         return index;
//     }
//
//     fn getCornerLightIndex(self: *LightProbeSpatialIndex, cell_coord: Vector3i) *u16 {
//         const index: u32 = self.getSpatialIndexAddress(cell_coord);
//         std.debug.assert(index < (@as(u32, 1) << @intCast(self.dimension_power_of_2.x() + self.dimension_power_of_2.y() + self.dimension_power_of_2.z())));
//         const result: *u16 = &self.light_index[index];
//         return result;
//     }
//
//     fn getMinCorner(self: *LightProbeSpatialIndex, cell_coord: Vector3i) Vector3 {
//         return self.min_corner.plus(cell_coord.i32ToF32().hadamardProduct(self.cell_dimension));
//     }
//
//     fn getCenter(self: *LightProbeSpatialIndex, cell_coord: Vector3i) Vector3 {
//         return self.min_corner.plus(
//             cell_coord.i32ToF32().plus(.new(0.5, 0.5, 0.5)).hadamardProduct(self.cell_dimension),
//         );
//     }
// };

pub fn getLightFromProbe(self: *const LightProbeIrradiance, emission_direction: Vector3) Color3 {
    // TODO: As we try to optimize the lighting, we can definitely make this routine a lot faster. We can probably
    // just do a 6-way blend and use min/max in SSE to zero out the contribution of the values which are facing in
    // the opposite direction.

    var uvw: Vector3 = .new(
        @abs(emission_direction.x()),
        @abs(emission_direction.y()),
        @abs(emission_direction.z()),
    );

    // TODO: This needs to guard for division by zero eventually when we SIMD this.
    const inverse_normal: f32 = 1 / (uvw.x() + uvw.y() + uvw.z());
    uvw = uvw.scaledTo(inverse_normal);

    const x_color: Color3 = if (emission_direction.x() < 0) self.light[0] else self.light[1];
    const y_color: Color3 = if (emission_direction.y() < 0) self.light[2] else self.light[3];
    const z_color: Color3 = if (emission_direction.z() < 0) self.light[4] else self.light[5];

    const result = x_color.scaledTo(uvw.x()).plus(y_color.scaledTo(uvw.y())).plus(z_color.scaledTo(uvw.z()));
    return result;
}

pub fn accumulate(self: *LightProbeIrradiance, contribution: f32, source: *LightProbeIrradiance) void {
    self.light[0] = self.light[0].plus(source.light[0].scaledTo(contribution));
    self.light[1] = self.light[1].plus(source.light[1].scaledTo(contribution));
    self.light[2] = self.light[2].plus(source.light[2].scaledTo(contribution));
    self.light[3] = self.light[3].plus(source.light[3].scaledTo(contribution));
    self.light[4] = self.light[4].plus(source.light[4].scaledTo(contribution));
    self.light[5] = self.light[5].plus(source.light[5].scaledTo(contribution));
}

const LightVoxelCell = struct {
    light_color: [LIGHT_DIRECTION_COUNT]Color3,
    light_normal: [LIGHT_DIRECTION_COUNT]Vector3,
};

pub const LightingSolution = struct {
    // TODO: We probably want to convert this system to one that actually uses a permanent box array where entities
    // just write their box position directly into the cache in a known location, rather than generating the entire
    // array every frame?
    box_count: u16 = 0,
    boxes: [*]LightingBox = undefined,

    scratch_a: [LIGHT_DATA_WIDTH]u16 = @splat(0),
    scratch_b: [LIGHT_DATA_WIDTH]u16 = @splat(0),

    box_reference_count: u16 = 0,
    box_table: [LIGHT_DATA_WIDTH]u16 = @splat(0),
    root_box_index: u16,

    series: random.Series,

    debug_box_draw_depth: u32,

    max_work_count: u32,
    works: [*]LightingWork = undefined, // 256.
    accumulated_pps: [*]Color3 = undefined, // LIGHT_DATA_WIDTH * 6.

    update_debug_lines: bool,
    debug_probe_index: u32,
    debug_line_count: u32,
    debug_lines: [4096]DebugLine = undefined,

    accumulation_count: f32 = 0,
    accumulating: bool = false,

    sampling_spheres: [*]LightSamplingSphere,

    light_probe_count: u32,
    light_probe_position: [*]Vector3,
    // light_probe_irradiance: [*]LightProbeIrradiance,
    // spatial_probe_index: LightProbeSpatialIndex,

    voxel_min_corner_large: Vector3,
    voxel_min_corner_hot: Vector3,
    hot_corner_i: Vector3u,

    voxel_cell_dimension: Vector3,
    inverse_voxel_cell_dimension: Vector3,
    hot_x: f32,
    hot_y: f32,
    hot_z: f32,
    cells: [LIGHT_LARGE_VOXEL_DIM][LIGHT_LARGE_VOXEL_DIM][LIGHT_LARGE_VOXEL_DIM]LightVoxelCell,

    debug_light_position: Vector3,

    // pub fn addProbeToSpacialIndex(
    //     self: *LightingSolution,
    //     spatial_index: *LightProbeSpatialIndex,
    //     probe_index: u16,
    //     probe_position: Vector3,
    //     radius: Vector3,
    // ) void {
    //     const probe_min_position: Vector3 = probe_position.minus(radius);
    //     const probe_max_position: Vector3 = probe_position.plus(radius);
    //
    //     const min_index: Vector3i = spatial_index.mapIntoGrid(probe_min_position).cell_coord;
    //     const max_index: Vector3i = spatial_index.mapIntoGrid(probe_max_position).cell_coord;
    //
    //     var z: i32 = min_index.z();
    //     while (z <= max_index.z()) : (z += 1) {
    //         var y: i32 = min_index.y();
    //         while (y <= max_index.y()) : (y += 1) {
    //             var x: i32 = min_index.x();
    //             while (x <= max_index.x()) : (x += 1) {
    //                 const cell_coord: Vector3i = .new(x, y, z);
    //                 const cell_center: Vector3 = spatial_index.getCenter(cell_coord);
    //
    //                 // Find out what light is in there to begin with.
    //                 const existing_index: *u16 = spatial_index.getCornerLightIndex(cell_coord);
    //
    //                 // If we're the more appropriate lookup, use us instead of it.
    //                 if (existing_index.* == 0) {
    //                     existing_index.* = probe_index;
    //                 } else {
    //                     const existing_probe_position: Vector3 = self.light_probe_position[existing_index.*];
    //                     const distance_to_this_sq: f32 = probe_position.minus(cell_center).lengthSquared();
    //                     const distance_to_existing_sq: f32 = existing_probe_position.minus(cell_center).lengthSquared();
    //                     if (distance_to_existing_sq > distance_to_this_sq) {
    //                         existing_index.* = probe_index;
    //                     }
    //                 }
    //             }
    //         }
    //     }
    // }
    //
    // pub fn getProbe(self: *LightingSolution, index: u16) *LightProbeIrradiance {
    //     const result: *LightProbeIrradiance = &self.light_probe_irradiance[index];
    //     return result;
    // }
    //
    // pub fn getProbeFromCell(self: *LightingSolution, cell_position: Vector3i) *LightProbeIrradiance {
    //     const result: *LightProbeIrradiance =
    //         self.getProbe(self.spatial_probe_index.getCornerLightIndex(cell_position).*);
    //     return result;
    // }
    //
    // pub fn getProbeLightingForCell(
    //     self: *LightingSolution,
    //     position: Vector3i,
    //     uvw: Vector3,
    // ) LightProbeIrradiance {
    //     const p0: *LightProbeIrradiance = self.getProbeFromCell(position);
    //     const p1: *LightProbeIrradiance = self.getProbeFromCell(position.plus(.new(1, 0, 0)));
    //     const p2: *LightProbeIrradiance = self.getProbeFromCell(position.plus(.new(0, 1, 0)));
    //     const p3: *LightProbeIrradiance = self.getProbeFromCell(position.plus(.new(0, 0, 1)));
    //     const p4: *LightProbeIrradiance = self.getProbeFromCell(position.plus(.new(0, 1, 1)));
    //     const p5: *LightProbeIrradiance = self.getProbeFromCell(position.plus(.new(1, 1, 0)));
    //     const p6: *LightProbeIrradiance = self.getProbeFromCell(position.plus(.new(1, 0, 1)));
    //     const p7: *LightProbeIrradiance = self.getProbeFromCell(position.plus(.new(1, 1, 1)));
    //
    //     var c: LightProbeIrradiance = .{};
    //     c.accumulate((1 - uvw.x()) * (1 - uvw.y()) * (1 - uvw.z()), p0);
    //     c.accumulate((uvw.x()) * (1 - uvw.y()) * (1 - uvw.z()), p1);
    //     c.accumulate((1 - uvw.x()) * (uvw.y()) * (1 - uvw.z()), p2);
    //     c.accumulate((1 - uvw.x()) * (1 - uvw.y()) * (uvw.z()), p3);
    //     c.accumulate((1 - uvw.x()) * (uvw.y()) * (uvw.z()), p4);
    //     c.accumulate((uvw.x()) * (uvw.y()) * (1 - uvw.z()), p5);
    //     c.accumulate((uvw.x()) * (1 - uvw.y()) * (uvw.z()), p6);
    //     c.accumulate((uvw.x()) * (uvw.y()) * (uvw.z()), p7);
    //
    //     return c;
    // }
    //
    // pub fn getProbeLightingForWorldPosition(
    //     self: *LightingSolution,
    //     spatial_index: *LightProbeSpatialIndex,
    //     position: Vector3,
    // ) LightProbeIrradiance {
    //     const mapping = spatial_index.mapIntoGrid(position);
    //     return self.getProbeLightingForCell(mapping.cell_coord, mapping.uvw);
    // }
};

const LightingWork = extern struct {
    solution: *LightingSolution,
    first_light_probe_index: u32,
    one_past_last_light_probe_index: u32,

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

pub const LightingPoint = extern struct {
    position: Vector3,
    reflection_color: Color3,
    normal: Vector3,
    x_axis: Vector3,
    y_axis: Vector3,
    pack_index: u32,
};

const RaycastResult = struct {
    position: V3_4x = .splat(@splat(0)),
    normal: V3_4x = .splat(@splat(0)),
    reflection_color: V3_4x = .splat(@splat(0)),

    t_ray: F32_4x = @splat(0),
    emission: F32_4x = @splat(0),
};

fn testFunc(dir: Vector3) f32 {
    return 3.0 * dir.x() + 2.0 * dir.y() - 0.5 * dir.z() * dir.z();
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
    debugging: bool,
) RaycastResult {
    const solution: *LightingSolution = work.solution;
    work.total_casts_initiated += 1;

    var depth: u32 = 0;
    var box_stack: [64]*LightingBox = undefined;
    box_stack[depth] = getBox(solution, solution.root_box_index);
    depth += 1;

    var t_ray: F32_4x = @splat(std.math.floatMax(f32));
    const zero: F32_4x = @splat(0);
    const one: F32_4x = @splat(1);
    const one_u: U32_4x = @splat(1);
    const t_close_enough: F32_4x = @splat(10);

    const inverse_ray_direction: V3_4x = @as(V3_4x, .splat(one)).dividedBy(ray_direction);

    var hit_box_center: V3_4x = .splat(zero);
    var hit_box_radius: V3_4x = .splat(zero);
    var hit_reflection_color: V3_4x = .splat(zero);
    var hit_emission: F32_4x = @splat(0);

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

            const t_box_min: V3_4x = box_min.minus(ray_origin).hadamardProduct(inverse_ray_direction);
            const t_box_max: V3_4x = box_max.minus(ray_origin).hadamardProduct(inverse_ray_direction);

            const t_min3: V3_4x = t_box_min.min(t_box_max);
            const t_max3: V3_4x = t_box_min.max(t_box_max);

            const t_min: F32_4x = @max(t_min3.x, @max(t_min3.y, t_min3.z));
            const t_max: F32_4x = @min(t_max3.x, @min(t_max3.y, t_max3.z));

            const max_pass: Bool_4x = t_max >= @as(F32_4x, zero);

            var box_color: Color = .new(0, 0, 0, 1);

            // TODO: We probably want t_close_enough to be based on the particular box, such that boxes at the root of
            // the hierarchy are more likely to be entered than boxes near the leaves.
            if (simd.anyTrue(max_pass)) {
                const t_inside: Bool_4x = max_pass & (t_min <= @as(F32_4x, zero));
                // TODO: Do we actually need `(t_min < t_max)` here?
                const t_valid: Bool_4x = (t_min > @as(F32_4x, zero)) & (t_min < t_max);
                const mask: Bool_4x = t_valid & (t_min < t_ray);
                const close_enough: Bool_4x = mask & (t_min < t_close_enough);
                const any_closer: bool = simd.anyTrue(mask);
                const any_inside: bool = simd.anyTrue(t_inside);
                const any_close_enough: bool = simd.anyTrue(close_enough);

                // if (box.child_count > 0 and (any_inside or (any_closer and any_close_enough))) {
                if (box.child_count > 0 and (any_inside or any_close_enough)) {
                    std.debug.assert(depth < box_stack.len);
                    box_stack[depth] = box;
                    depth += 1;

                    box_color = .new(1, 0, 1, 1);
                } else if (any_closer) {
                    t_ray = @select(f32, mask, t_min, t_ray);
                    hit_box_center = hit_box_center.select(mask, box_position);
                    hit_box_radius = hit_box_radius.select(mask, box_radius);
                    hit_reflection_color =
                        hit_reflection_color.select(mask, .fromVector3(box.reflection_color.toVector3()));
                    hit_emission = @select(f32, mask, @as(F32_4x, @splat(box.emission)), hit_emission);
                    work.total_partition_leaves_used += 1;

                    box_color = if (box.child_count > 0) .new(0, 1, 1, 1) else .new(1, 1, 0, 1);
                }
            }

            if (debugging) {
                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_min.y[0], box_min.z[0]),
                    .new(box_min.x[0], box_max.y[0], box_min.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_max.y[0], box_min.z[0]),
                    .new(box_min.x[0], box_max.y[0], box_max.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_max.y[0], box_max.z[0]),
                    .new(box_min.x[0], box_min.y[0], box_max.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_min.y[0], box_max.z[0]),
                    .new(box_min.x[0], box_min.y[0], box_min.z[0]),
                    box_color,
                );

                pushDebugLine(
                    solution,
                    .new(box_max.x[0], box_min.y[0], box_min.z[0]),
                    .new(box_max.x[0], box_max.y[0], box_min.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_max.x[0], box_max.y[0], box_min.z[0]),
                    .new(box_max.x[0], box_max.y[0], box_max.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_max.x[0], box_max.y[0], box_max.z[0]),
                    .new(box_max.x[0], box_min.y[0], box_max.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_max.x[0], box_min.y[0], box_max.z[0]),
                    .new(box_max.x[0], box_min.y[0], box_min.z[0]),
                    box_color,
                );

                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_min.y[0], box_min.z[0]),
                    .new(box_max.x[0], box_min.y[0], box_min.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_max.y[0], box_min.z[0]),
                    .new(box_max.x[0], box_max.y[0], box_min.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_max.y[0], box_max.z[0]),
                    .new(box_max.x[0], box_max.y[0], box_max.z[0]),
                    box_color,
                );
                pushDebugLine(
                    solution,
                    .new(box_min.x[0], box_min.y[0], box_max.z[0]),
                    .new(box_max.x[0], box_min.y[0], box_max.z[0]),
                    box_color,
                );
            }
        }
    }

    const hit_position: V3_4x = ray_origin.plus(ray_direction.scaledToV(t_ray));
    const hit_box_inv_radius: V3_4x = @as(V3_4x, .splat(one)).dividedBy(hit_box_radius);
    const unscaled_direction: V3_4x = hit_position.minus(hit_box_center);
    const scaled_direction: V3_4x = hit_box_inv_radius.hadamardProduct(unscaled_direction);

    const x_mask: U32_4x =
        @intFromBool((scaled_direction.x < scaled_direction.y) & (scaled_direction.x < scaled_direction.z));
    const y_mask: U32_4x =
        @intFromBool((scaled_direction.y < scaled_direction.x) & (scaled_direction.y < scaled_direction.z));
    const z_mask: U32_4x =
        @intFromBool((scaled_direction.z < scaled_direction.x) & (scaled_direction.z < scaled_direction.y));
    const hit_normal: V3_4x = .fromAxes(
        @floatFromInt(x_mask & (one_u | simd.signBitFrom(scaled_direction.x))),
        @floatFromInt(y_mask & (one_u | simd.signBitFrom(scaled_direction.y))),
        @floatFromInt(z_mask & (one_u | simd.signBitFrom(scaled_direction.z))),
    );

    var result: RaycastResult = .{};

    result.position = hit_position;
    result.t_ray = t_ray;
    result.normal = hit_normal;
    result.reflection_color = hit_reflection_color;
    result.emission = hit_emission;

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
    TimedBlock.beginFunction(@src(), .ComputeLightPropagation);
    defer TimedBlock.endFunction(@src(), .ComputeLightPropagation);

    const solution: *LightingSolution = work.solution;
    const first_light_probe_index: u32 = work.first_light_probe_index;
    const one_past_last_light_probe_index: u32 = work.one_past_last_light_probe_index;

    var series: random.Series = solution.series;
    const sample_point_entropy: u32 = series.randomInt();

    // TOOD: Make this procedurla in some way, since we don\t want to add moonlight in areas that aren't outside.
    const moon_color: Color3 = Color3.new(0.1, 0.8, 1.0).scaledTo(0.4);

    var light_probe_index: u32 = first_light_probe_index; // Light point index 0 is never used.
    while (light_probe_index < one_past_last_light_probe_index) : (light_probe_index += 1) {
        const light_probe_position: Vector3 = solution.light_probe_position[light_probe_index];
        const ray_origin: V3_4x = .fromVector3(light_probe_position);

        if (INTERNAL) {
            if (light_probe_index == solution.debug_probe_index) {
                pushDebugLine(solution, light_probe_position, light_probe_position.plus(.new(1, 0, 0)), .new(1, 0, 0, 1));
                pushDebugLine(solution, light_probe_position, light_probe_position.plus(.new(0, 1, 0)), .new(0, 1, 0, 1));
                pushDebugLine(solution, light_probe_position, light_probe_position.plus(.new(0, 0, 1)), .new(0, 0, 1, 1));
            }
        }

        const direction_sample_index: u32 = light_probe_index + sample_point_entropy & LIGHT_SAMPLING_SPHERE_MASK;
        const sampling_sphere: *LightSamplingSphere = &solution.sampling_spheres[direction_sample_index];
        const ray_count: u32 = sampling_sphere.sample_direction.len;
        const ray_weight: f32 = 6 / @as(f32, @floatFromInt(ray_count));

        var ray_index: u32 = 0;
        while (ray_index < ray_count) : (ray_index += 1) {
            const ray_direction: V3_4x = sampling_sphere.sample_direction[ray_index];

            const ray: RaycastResult = raycast(work, ray_origin, ray_direction, false);
            const t_hit: F32_4x = @as(F32_4x, @splat(std.math.floatMax(f32))) != ray.t_ray;

            var sub_ray: u32 = 0;
            while (sub_ray < 4) : (sub_ray += 1) {
                const hit: bool = @as([4]bool, t_hit)[sub_ray];

                if (INTERNAL) {
                    if (light_probe_index == solution.debug_probe_index) {
                        const sample_direction: Vector3 = ray_direction.getComponent(sub_ray);
                        pushDebugLine(
                            solution,
                            light_probe_position,
                            if (hit)
                                ray.position.getComponent(sub_ray)
                            else
                                light_probe_position.plus(sample_direction.scaledTo(0.25)),
                            if (hit) .new(0, 1, 1, 1) else .new(1, 1, 0, 1),
                        );
                    }
                }

                var transfer_pps: Color3 = .zero();
                const emission_direction: Vector3 = ray_direction.getComponent(sub_ray).negated();
                if (hit) {
                    unreachable;
                    // const probe_sample_position: Vector3 = ray.position.getComponent(sub_ray);
                    // const probe_sample_normal: Vector3 = ray.normal.getComponent(sub_ray);
                    // const sample_reflection_color: Vector3 = ray.reflection_color.getComponent(sub_ray);
                    // const emission: f32 = @as([4]f32, ray.emission)[sub_ray];
                    //
                    // const reflection_falloff: f32 = math.clampf01(probe_sample_normal.dotProduct(emission_direction));

                    // const composite_probe: LightProbeIrradiance =
                    //     solution.getProbeLightingForWorldPosition(spatial_index, probe_sample_position);
                    // const light_sample: Color3 = getLightFromProbe(composite_probe, probe_sample_normal);
                    // transfer_pps =
                    //     light_sample.hadamardProduct(sample_reflection_color.toColor3()).scaledTo(reflection_falloff).plus(
                    //         sample_reflection_color.toColor3().scaledTo(emission),
                    //     );
                } else {
                    transfer_pps = moon_color.scaledTo(math.clampf01(emission_direction.z()));
                }

                var pps: [*]Vector3 = @ptrCast(&solution.accumulated_pps[6 * light_probe_index]);
                const cube_side_weight: [*]f32 = &sampling_sphere.cube_side_weight[4 * ray_index + sub_ray];

                // TODO: Does it make sense to accumulate the weighting here or can it safely be skipped because it
                // should average out over time if your sampling is reasonably distributed?
                pps[0] = pps[0].plus(transfer_pps.toVector3().scaledTo(ray_weight * cube_side_weight[0]));
                pps[1] = pps[1].plus(transfer_pps.toVector3().scaledTo(ray_weight * cube_side_weight[1]));
                pps[2] = pps[2].plus(transfer_pps.toVector3().scaledTo(ray_weight * cube_side_weight[2]));
                pps[3] = pps[3].plus(transfer_pps.toVector3().scaledTo(ray_weight * cube_side_weight[3]));
                pps[4] = pps[4].plus(transfer_pps.toVector3().scaledTo(ray_weight * cube_side_weight[4]));
                pps[5] = pps[5].plus(transfer_pps.toVector3().scaledTo(ray_weight * cube_side_weight[5]));
            }
        }
    }

    solution.series = series;
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
        const probes_per_work: u32 = 256;
        var done: bool = false;

        var work_index: u32 = 0;
        while (work_index < solution.max_work_count) : (work_index += 1) {
            const work = &works[work_count];
            work_count += 1;

            std.debug.assert((@intFromPtr(work) & 63) == 0);

            memory.zeroStruct(LightingWork, work);

            work.solution = solution;
            work.first_light_probe_index = work_index * probes_per_work;
            work.one_past_last_light_probe_index = work.first_light_probe_index + probes_per_work;
            if (work.one_past_last_light_probe_index > solution.light_probe_count) {
                work.one_past_last_light_probe_index = solution.light_probe_count;
                done = true;
            }

            if (work.first_light_probe_index == 0) {
                work.first_light_probe_index = 1;
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
            .first_light_probe_index = 1,
            .one_past_last_light_probe_index = solution.light_probe_count,
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

    var partitions_per_cast: f32 =
        @floatCast(@as(f64, @floatFromInt(total_partitions_tested)) / @as(f64, @floatFromInt(total_casts_initiated)));
    var leaves_per_cast: f32 =
        @floatCast(@as(f64, @floatFromInt(total_leaves_tested)) / @as(f64, @floatFromInt(total_casts_initiated)));
    var partitions_per_leaf: f32 =
        @floatCast(@as(f64, @floatFromInt(total_partitions_tested)) / @as(f64, @floatFromInt(total_leaves_tested)));

    DebugInterface.debugBeginDataBlock(@src(), "Lighting");
    {
        DebugInterface.debugUIHUD(@src(), .Lighting);
        DebugInterface.debugValue(@src(), &global_config.Lighting_ShowProbes, "Lighting_ShowProbes");

        DebugInterface.debugValue(@src(), &solution.box_count, "BoxCount");
        DebugInterface.debugValue(@src(), &solution.light_probe_count, "LightProbeCount");

        DebugInterface.debugValue(@src(), &total_casts_initiated, "TotalCastsInitiated");
        DebugInterface.debugValue(@src(), &total_partitions_tested, "TotalPartitionsTested");
        DebugInterface.debugValue(@src(), &total_partition_leaves_used, "TotalPartitionLeavesUsed");
        DebugInterface.debugValue(@src(), &total_leaves_tested, "TotalLeavesTested");
        DebugInterface.debugValue(@src(), &partitions_per_cast, "PartitionsPerCast");
        DebugInterface.debugValue(@src(), &leaves_per_cast, "LeavesPerCast");
        DebugInterface.debugValue(@src(), &partitions_per_leaf, "PartitionsPerLeaf");
    }
    DebugInterface.debugEndDataBlock(@src());
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
                class_direction.setValueAt(dimension_index, 1.0);
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

fn irradiancePack(light_intensity: Color3) u32 {
    var result: u32 = 0;
    const max_value: f32 = @max(light_intensity.r(), @max(light_intensity.g(), light_intensity.b()));

    if (max_value > 0) {
        const inverse_max_value: f32 = 1.0 / max_value;
        const alpha: f32 = math.clampf01(max_value / MAX_LIGHT_INTENSITY);

        result = Color.new(
            inverse_max_value * light_intensity.r(),
            inverse_max_value * light_intensity.g(),
            inverse_max_value * light_intensity.b(),
            alpha,
        ).scaledTo(255).packColorBGRA();
    }

    return result;
}

fn binormalToNormal(normal: Vector3) Vector3 {
    const result: Vector3 = normal.scaledTo(0.5).plus(.splat(0.5));
    return result;
}

pub fn initLighting(solution: *LightingSolution, arena: *MemoryArena, fundamental_unit: f32) void {
    solution.series = .seed(1234, null, null, null);
    solution.max_work_count = 256;
    solution.works = arena.pushArray(solution.max_work_count, LightingWork, .aligned(64, true), @src());
    solution.accumulated_pps = arena.pushArray(6 * LIGHT_DATA_WIDTH, Color3, .aligned(64, true), @src());
    solution.sampling_spheres = &sampling_spheres.light_sampling_sphere_table;

    solution.voxel_cell_dimension = .splat(fundamental_unit);
    solution.inverse_voxel_cell_dimension = solution.voxel_cell_dimension.divideFByMe(1);

    solution.update_debug_lines = true;
}

pub fn beginLightingComputation(
    solution: *LightingSolution,
    group: *RenderGroup,
    origin_position: WorldPosition,
    camera_offset_from_origin: Vector3,
    enable_lighting: bool,
) void {
    if (enable_lighting) {
        const large_cell_count: u32 = LIGHT_LARGE_VOXEL_DIM;
        const hot_cell_count: u32 = group.commands.light_voxel_dimension;

        const offset_i: u32 = (large_cell_count - hot_cell_count) / 2;
        solution.hot_corner_i = .splat(offset_i);

        const large_dimension: Vector3 = solution.voxel_cell_dimension.scaledTo(@floatFromInt(large_cell_count));
        const hot_dimension: Vector3 = solution.voxel_cell_dimension.scaledTo(@floatFromInt(hot_cell_count));

        const inverse_hot_dimension: Vector3 = hot_dimension.divideFByMe(1);

        _ = origin_position;
        _ = camera_offset_from_origin;
        // TODO: Should we just divid chunk_dumension_in_meters by some constant here, so that we know that the origin
        // is always aligned?
        // const x_displacement: f32 = @mod((origin_position.chunk_x & 1) * @mod(chunk_dimension_in_meters, 2), 2);

        // solution.voxel_min_corner_hot = .new(-x_displacement, 0, 0);
        // solution.voxel_min_corner_large = solution.voxel_min_corner_hot.minus(
        //     solution.voxel_cell_dimension.hadamardProduct(solution.hot_corner_i.fromV3u()),
        // );

        solution.voxel_min_corner_hot = hot_dimension.scaledTo(0.5).negated();
        solution.voxel_min_corner_large = solution.voxel_min_corner_hot.minus(
            @as(Vector3, .fromV3u(solution.hot_corner_i)).hadamardProduct(solution.voxel_cell_dimension),
        );

        const large_voxel_rect: Rectangle3 = .fromMinDimension(solution.voxel_min_corner_large, large_dimension);
        const hot_voxel_rect: Rectangle3 = .fromMinDimension(solution.voxel_min_corner_hot, hot_dimension);

        group.pushVolumeOutline(large_voxel_rect, .new(0, 0, 1, 1), 0.1);
        group.pushVolumeOutline(hot_voxel_rect, .new(0, 1, 1, 1), 0.1);

        group.setLightBounds(hot_voxel_rect.min, inverse_hot_dimension);
        group.enableLighting(hot_voxel_rect);
    }
}

pub fn endLightingComputation(
    solution: *LightingSolution,
    group: *RenderGroup,
    lighting_queue: *shared.PlatformWorkQueue,
) void {
    TimedBlock.beginFunction(@src(), .LightingTest);
    defer TimedBlock.endFunction(@src(), .LightingTest);

    const setup: *RenderSetup = &group.last_setup;
    const commands: *RenderCommands = group.commands;
    const hot_dimension: u32 = commands.light_voxel_dimension;
    const large_dimension: u32 = LIGHT_LARGE_VOXEL_DIM;
    const inverse_hot_dimension: Vector3 = Vector3.fromV3u(.splat(hot_dimension)).divideFByMe(1);

    solution.light_probe_count = commands.light_probe_count;
    solution.light_probe_position = commands.light_probe_position;
    // solution.light_probe_irradiance = commands.light_probe_irradiance;

    if (solution.update_debug_lines) {
        solution.debug_line_count = 0;
    }
    solution.box_reference_count = 0;
    solution.box_count = @intCast(group.commands.light_occluder_count);
    solution.boxes = group.commands.light_occluders;
    // solution.point_count = group.light_point_index;

    // From the linear blend coeeficient t_irradiance_preservation between the two successive frames of irradiance data,
    // we "derive" two coefficients, one for the multiplication at the end that renormalizes, and one for the new ray
    // contributions. This is to avoid pre-multiplying the existing probes in a first pass.
    const t_irradiance_preservation: f32 = 59.0 / 60.0;
    var irradiance_blend_u: f32 = t_irradiance_preservation;
    var irradiance_blend_v: f32 = (1 - irradiance_blend_u) / irradiance_blend_u;

    // When doing long-term accumulation for testing, we turn off the linear blend and instead just set the
    // coefficients for long-term averaging.
    if (solution.accumulating) {
        irradiance_blend_u = 1;
        if (solution.accumulation_count < LIGHT_TEST_ACCUMULATION_COUNT) {
            irradiance_blend_v = 1.0 / @as(f32, @floatFromInt(LIGHT_TEST_ACCUMULATION_COUNT));
        } else {
            irradiance_blend_v = 0;
        }
    }

    const light_position: Vector3 = solution.debug_light_position;
    const light_intensity: f32 = 0.1 * MAX_LIGHT_INTENSITY;

    buildSpatialPartitionForLighting(solution);
    if (false) {
        computeAllLightPropagation(solution, lighting_queue, irradiance_blend_u);
    }

    if (true) {
        const voxel_inverse_total_dimension: Vector3 = setup.voxel_inverse_total_dimension;

        const light_position2: Vector3 = light_position.plus(.new(0, 8, 0));
        const light_position3: Vector3 = light_position.plus(.new(8, 0, 0));
        const light_position4: Vector3 = light_position.plus(.new(8, 8, 0));
        const light_uvw: Vector3 =
            voxel_inverse_total_dimension.hadamardProduct(light_position.minus(setup.voxel_min_corner));
        const light2_uvw: Vector3 =
            voxel_inverse_total_dimension.hadamardProduct(light_position2.minus(setup.voxel_min_corner));
        const light3_uvw: Vector3 =
            voxel_inverse_total_dimension.hadamardProduct(light_position3.minus(setup.voxel_min_corner));
        const light4_uvw: Vector3 =
            voxel_inverse_total_dimension.hadamardProduct(light_position4.minus(setup.voxel_min_corner));

        var work: LightingWork = .{
            .solution = solution,
            .first_light_probe_index = 0,
            .one_past_last_light_probe_index = 0,
        };

        {
            var z: u32 = 0;
            while (z < large_dimension) : (z += 1) {
                var y: u32 = 0;
                while (y < large_dimension) : (y += 1) {
                    var x: u32 = 0;
                    while (x < large_dimension) : (x += 1) {
                        var light_normal0: Vector3 = .zero();
                        var light_color0: Color3 = .zero();

                        if (true) {
                            const voxel_center_position: Vector3 = solution.voxel_min_corner_large.plus(
                                Vector3.newU(x, y, z).plus(.splat(0.5)).hadamardProduct(solution.voxel_cell_dimension),
                            );

                            var light_normal: Vector3 = light_position.minus(voxel_center_position);
                            const light_distance: f32 = light_normal.length();
                            light_normal = light_normal.normalizeOrZero();

                            var light_distance_falloff: f32 = math.clampf01(1.0 - 0.12 * light_distance);

                            if (true) {
                                const voxel_center_position4x: V3_4x = .fromVector3(voxel_center_position);
                                const light_normal4x: V3_4x = .fromVector3(light_normal);

                                const is_test_cast: bool = false;

                                // const is_test_cast: bool =
                                //     x >= (solution.hot_corner_i.x() + hot_dimension / 2 - 4) and
                                //     y >= (solution.hot_corner_i.y() + hot_dimension / 2 - 4) and
                                //     z >= (solution.hot_corner_i.z() + hot_dimension / 2 - 4) and
                                //     x < (solution.hot_corner_i.x() + hot_dimension / 2 + 4) and
                                //     y < (solution.hot_corner_i.y() + hot_dimension / 2 + 4) and
                                //     z < (solution.hot_corner_i.z() + hot_dimension / 2 + 4);

                                // const is_test_cast: bool =
                                //     x == (solution.hot_corner_i.x() + hot_dimension / 2 + 3) and
                                //     y == (solution.hot_corner_i.y() + hot_dimension / 2 - 2) and
                                //     z == (solution.hot_corner_i.z() + hot_dimension / 2 + 2);

                                const cast: RaycastResult = raycast(&work, voxel_center_position4x, light_normal4x, false);
                                const hit: bool = cast.t_ray[0] < light_distance;
                                const line_color: Color = if (hit) .new(1, 1, 0, 1) else .new(0, 0, 0, 1);
                                if (true) {
                                    var cast_position: Vector3 = cast.position.getComponent(0);

                                    if (!hit) {
                                        cast_position = voxel_center_position.plus(light_normal.scaledTo(light_distance));
                                    }

                                    if (is_test_cast) {
                                        pushDebugLine(
                                            solution,
                                            voxel_center_position,
                                            cast_position,
                                            line_color,
                                        );
                                        pushDebugLine(
                                            solution,
                                            voxel_center_position,
                                            voxel_center_position.plus(.new(0, 0, 0.025)),
                                            .new(0, 1, 1, 1),
                                        );
                                        pushDebugLine(
                                            solution,
                                            voxel_center_position,
                                            voxel_center_position.plus(light_normal.scaledTo(0.1)),
                                            .new(1, 0, 1, 1),
                                        );
                                    }

                                    if (hit) {
                                        light_distance_falloff = 0;
                                    }
                                }
                            }

                            // TODO: We should probably have our "darkness" range be quite a bit less than our brightness
                            // range - maybe encode -0.2 to 1.0 instead of -1 to 1.
                            const light_alpha: f32 = math.lerpf(
                                0.4 * MAX_LIGHT_INTENSITY,
                                0.75 * MAX_LIGHT_INTENSITY,
                                light_distance_falloff,
                            );

                            light_normal0 = light_normal;
                            light_color0 = Color3.new(1, 1, 1).scaledTo(light_alpha);
                        } else {
                            light_normal0 = Vector3.new(1, 1, 1).normalizeOrZero();
                            light_color0 = .zero();

                            if (((x & 1) ^ (y & 1) ^ (z & 1)) != 0) {
                                light_color0 = .new(10, 10, 10);
                            } else {
                                light_color0 = .new(7, 7, 7);
                            }
                        }

                        solution.cells[z][y][x].light_normal[0] = light_normal0;
                        solution.cells[z][y][x].light_color[0] = light_color0;
                    }
                }
            }
        }

        var z: u32 = 0;
        while (z < hot_dimension) : (z += 1) {
            var y: u32 = 0;
            while (y < hot_dimension) : (y += 1) {
                var x: u32 = 0;
                while (x < hot_dimension) : (x += 1) {
                    var light_normal0: Vector3 = .zero();
                    var light_color0: u32 = 0;
                    var light_normal1: Vector3 = .zero();
                    var light_color1: u32 = 0;
                    var light_normal2: Vector3 = .zero();
                    var light_color2: u32 = 0;
                    var light_normal3: Vector3 = .zero();
                    var light_color3: u32 = 0;

                    if (TEST_LIGHT_SPHERE) {
                        const voxel_center_position: Vector3 = Vector3.newU(x, y, z).plus(.splat(0.5));
                        const voxel_uvw: Vector3 = inverse_hot_dimension.hadamardProduct(voxel_center_position);

                        {
                            var light_normal: Vector3 = light_uvw.minus(voxel_uvw);
                            const light_distance: f32 = light_normal.length();
                            light_normal = light_normal.normalizeOrZero();

                            var light_coefficient: f32 = 1.0 - 3.0 * light_distance;
                            light_coefficient *= 6 * light_intensity / MAX_LIGHT_INTENSITY;

                            // TODO: We should probably have our "darkness" range be quite a bit less than our brightness
                            // range - maybe encode -0.2 to 1.0 instead of -1 to 1.
                            const light_alpha: f32 = math.clampf(-1, light_coefficient, 1);

                            light_normal0 = light_normal;
                            light_color0 = Color.new(1, 1, 1, 0.5 + 0.5 * light_alpha).scaledTo(255).packColorBGRA();
                        }

                        {
                            var light_normal: Vector3 = light2_uvw.minus(voxel_uvw);
                            const light_distance: f32 = light_normal.length();
                            light_normal = light_normal.normalizeOrZero();

                            var light_coefficient: f32 = 1.0 - 3.0 * light_distance;
                            light_coefficient *= 6 * light_intensity / MAX_LIGHT_INTENSITY;

                            // TODO: We should probably have our "darkness" range be quite a bit less than our brightness
                            // range - maybe encode -0.2 to 1.0 instead of -1 to 1.
                            const light_alpha: f32 = math.clampf(-1, light_coefficient, 1);

                            light_normal1 = light_normal;
                            light_color1 = Color.new(1, 0, 0, 0.5 + 0.5 * light_alpha).scaledTo(255).packColorBGRA();
                        }

                        {
                            var light_normal: Vector3 = light3_uvw.minus(voxel_uvw);
                            const light_distance: f32 = light_normal.length();
                            light_normal = light_normal.normalizeOrZero();

                            var light_coefficient: f32 = 1.0 - 3.0 * light_distance;
                            light_coefficient *= 6 * light_intensity / MAX_LIGHT_INTENSITY;

                            // TODO: We should probably have our "darkness" range be quite a bit less than our brightness
                            // range - maybe encode -0.2 to 1.0 instead of -1 to 1.
                            const light_alpha: f32 = math.clampf(-1, light_coefficient, 1);

                            light_normal2 = light_normal;
                            light_color2 = Color.new(0, 1, 0, 0.5 + 0.5 * light_alpha).scaledTo(255).packColorBGRA();
                        }

                        {
                            var light_normal: Vector3 = light4_uvw.minus(voxel_uvw);
                            const light_distance: f32 = light_normal.length();
                            light_normal = light_normal.normalizeOrZero();

                            var light_coefficient: f32 = 1.0 - 3.0 * light_distance;
                            light_coefficient *= 6 * light_intensity / MAX_LIGHT_INTENSITY;

                            // TODO: We should probably have our "darkness" range be quite a bit less than our brightness
                            // range - maybe encode -0.2 to 1.0 instead of -1 to 1.
                            const light_alpha: f32 = math.clampf(-1, light_coefficient, 1);

                            light_normal3 = light_normal;
                            light_color3 = Color.new(0, 0, 1, 0.5 + 0.5 * light_alpha).scaledTo(255).packColorBGRA();
                        }
                    }

                    if (TEST_LIGHT_CHECKERBOARD) {
                        light_normal0 = Vector3.new(1, 1, 1).normalizeOrZero();
                        light_color0 = 0xa0000000;

                        if (((x & 1) ^ (y & 1) ^ (z & 1)) != 0) {
                            light_color0 |= 0x00ffffff;
                        } else {
                            light_color0 |= 0x00404040;
                        }
                    }

                    if (TEST_LIGHT_TRANSFER) {
                        const hot_z: u32 = solution.hot_corner_i.z() + z;
                        const hot_y: u32 = solution.hot_corner_i.y() + y;
                        const hot_x: u32 = solution.hot_corner_i.x() + x;
                        const cell: *LightVoxelCell = &solution.cells[hot_z][hot_y][hot_x];

                        light_normal0 = cell.light_normal[0];
                        light_color0 = irradiancePack(cell.light_color[0]);

                        light_normal1 = cell.light_normal[1];
                        light_color1 = irradiancePack(cell.light_color[1]);

                        light_normal2 = cell.light_normal[2];
                        light_color2 = irradiancePack(cell.light_color[2]);

                        light_normal3 = cell.light_normal[3];
                        light_color3 = irradiancePack(cell.light_color[3]);
                    }

                    const element_index: u32 = z * hot_dimension * hot_dimension + y * hot_dimension + x;
                    commands.light_voxel_normal[0][element_index] = binormalToNormal(light_normal0);
                    commands.light_voxel_color[0][element_index] = light_color0;

                    commands.light_voxel_normal[1][element_index] = binormalToNormal(light_normal1);
                    commands.light_voxel_color[1][element_index] = light_color1;

                    commands.light_voxel_normal[2][element_index] = binormalToNormal(light_normal2);
                    commands.light_voxel_color[2][element_index] = light_color2;

                    commands.light_voxel_normal[3][element_index] = binormalToNormal(light_normal3);
                    commands.light_voxel_color[3][element_index] = light_color3;
                }
            }
        }
    }

    _ = group.getCurrentQuads(solution.debug_line_count, group.white_texture);
    const white_texture: RendererTexture = group.white_texture;
    var debug_line_index: u32 = 0;
    while (debug_line_index < solution.debug_line_count) : (debug_line_index += 1) {
        const line: *DebugLine = &solution.debug_lines[debug_line_index];

        group.pushLineSegment(white_texture, line.from_position, line.color, line.to_position, line.color, 0.01);
    }
}

fn outputLightingPointsRecurse(
    group: *RenderGroup,
    solution: *LightingSolution,
    box: *LightingBox,
    depth: u32,
) void {
    if (depth == 0 or box.child_count == 0) {
        const white_texture: RendererTexture = group.white_texture;

        if (false) {
            var box_surface_index: u32 = 0;
            while (box_surface_index < 6) : (box_surface_index += 1) {
                const box_surface: box_mod.LightBoxSurface =
                    box_mod.getBoxSurface(box.position, box.radius, box_surface_index);

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
                        white_texture,
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
                    );
                }
            }
        } //else {
    }
    {
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

// Old light transport code.
// if (false) {
//     const original_box_count: u32 = solution.box_count;
//     const t_update: f32 = 0.05;
//     var box_index: u32 = 0;
//     while (box_index < original_box_count) : (box_index += 1) {
//         const box: *LightingBox = @ptrCast(solution.boxes + box_index);
//         const local_count: u32 = box.light_index[6] - box.light_index[0];
//         var local_index: u32 = 0;
//         while (local_index < local_count) : (local_index += 1) {
//             const point_index: u32 = local_index + box.light_index[0];
//
//             // Can probably remove the accumulated weight check if we always guarantee at least
//             // one positively weighted sample per point?
//             const accumulated_weight: f32 = solution.accumulated_weight[point_index];
//             var inverse_weight: f32 = 0;
//             if (accumulated_weight > 0) {
//                 inverse_weight = 1.0 / accumulated_weight;
//             }
//             const accumulated_pps: Color3 = solution.accumulated_pps[point_index].scaledTo(inverse_weight);
//             const direction: Vector3 = solution.average_direction_to_light[point_index].normalizeOrZero();
//
//             var last_pps: Color3 = accumulated_pps;
//             var last_direction: Vector3 = direction;
//
//             const box_store_direction: Vector3 = box.storage[local_index].last_direction;
//             const valid: bool =
//                 box_store_direction.x() != 0 or
//                 box_store_direction.y() != 0 or
//                 box_store_direction.z() != 0;
//             if (valid) {
//                 last_pps = box.storage[local_index].last_pps;
//                 last_direction = box_store_direction;
//             }
//
//             if (solution.accumulating) {
//                 if (should_accumulate) {
//                     box.storage[local_index].last_pps = last_pps.plus(accumulated_pps);
//                 }
//                 solution.accumulated_pps[point_index] =
//                     box.storage[local_index].last_pps.scaledTo(accumulation_coefficient);
//             } else {
//                 box.storage[local_index].last_pps = last_pps.lerp(accumulated_pps, t_update);
//                 solution.accumulated_pps[point_index] = box.storage[local_index].last_pps;
//             }
//
//             box.storage[local_index].last_direction =
//                 last_direction.lerp(direction, t_update).normalizeOrZero();
//             solution.average_direction_to_light[point_index] = box.storage[local_index].last_direction;
//         }
//     }
// }
//
// if (false) {
//     const cluster_table = [_]u32{
//         0,
//         1,
//         3,
//         6,
//
//         2,
//         4,
//         7,
//         12,
//
//         9,
//         14,
//         17,
//         22,
//     };
//
//     const color_table = [_]Color{
//         .new(0, 0, 0, 1),
//         .new(1, 0, 0, 1),
//         .new(0, 1, 0, 1),
//         .new(0, 0, 1, 1),
//         .new(1, 1, 0, 1),
//         .new(0, 1, 1, 1),
//         .new(1, 0, 1, 1),
//         .new(1, 1, 1, 1),
//     };
//
//     var point_index: u32 = 0;
//     while (point_index < cluster_table.len) : (point_index += 1) {
//         const color: Color = color_table[@mod(point_index / 4, color_table.len)];
//         const normal: Vector3 = solution.sample_points[cluster_table[point_index]];
//         group.pushLineSegment(
//             white_texture,
//             start_point.plus(normal),
//             color,
//             start_point.plus(normal.scaledTo(1.06)),
//             color,
//             0.01,
//         );
//     }
// }
//
// if (false) {
//     var sphere_index: u32 = 0;
//     while (sphere_index < LIGHT_SAMPLING_SPHERE_COUNT) : (sphere_index += 1) {
//         const sphere: *LightSamplingSphere = &solution.sampling_spheres[sphere_index];
//         var point_index: u32 = 0;
//         while (point_index < LIGHT_SAMPLING_RAY_BUNDLES_PER_SPHERE) : (point_index += 1) {
//             var component_index: u32 = 0;
//             while (component_index < 4) : (component_index += 1) {
//                 const color: Color = handmade.getDebugColor4(sphere_index, null);
//                 const normal: Vector3 = sphere.sample_direction[point_index].getComponent(component_index);
//
//                 group.pushCube(
//                     white_texture,
//                     start_point.plus(normal),
//                     .splat(0.01),
//                     color,
//                     null,
//                     null,
//                     null,
//                 );
//             }
//         }
//     }
// }
//
// if (false) {
//     const draw_point_count: u32 = 2 * 1024;
//     _ = group.getCurrentQuads(draw_point_count * 4 * 6, group.white_texture);
//     var test_series_x: random.SeriesPCG = .seed(23984593284, 3249823984);
//     var test_series_y: random.SeriesPCG = .seed(85462378423, 90857892378);
//     var test_series_z: random.SeriesPCG = .seed(34205873903, 94569083);
//     // var test_series_x: random.Series = .seed(239843284, null, null, null);
//     // var test_series_y: random.Series = .seed(854623723, null, null, null);
//     // var test_series_z: random.Series = .seed(342058739, null, null, null);
//     var point_index: u32 = 0;
//     while (point_index < draw_point_count) : (point_index += 1) {
//         while (true) {
//             if (false) {
//                 var dir: Vector3 = Vector3.new(
//                     test_series_x.randomBilateral(),
//                     test_series_y.randomBilateral(),
//                     test_series_z.randomBilateral(),
//                 );
//
//                 if (dir.z() < 0) {
//                     _ = dir.setZ(-dir.z());
//                 }
//
//                 if (dir.lengthSquared() <= 1.0) {
//                     dir = dir.normalizeOrZero();
//                     group.pushCube(
//                         white_texture,
//                         start_point.plus(dir),
//                         0.01,
//                         0.02,
//                         .new(1, 1, 0, 1),
//                         null,
//                         null,
//                     );
//                     break;
//                 }
//             } else {
//                 const x1: f32 = test_series_x.randomBilateral();
//                 const x2: f32 = test_series_y.randomBilateral();
//                 const sqr: f32 = x1 * x1 + x2 * x2;
//                 const root: f32 = @sqrt(1 - x1 * x1 - x2 * x2);
//
//                 const dir: Vector3 = .new(
//                     2.0 * x1 * root,
//                     2.0 * x2 * root,
//                     1.0 - 2.0 * sqr,
//                 );
//
//                 if (sqr < 0.5) {
//                     group.pushCube(
//                         white_texture,
//                         start_point.plus(dir),
//                         0.01,
//                         0.02,
//                         .new(1, 1, 0, 1),
//                         null,
//                         null,
//                     );
//                     break;
//                 }
//             }
//         }
//     }
// }
//
// if (false) {
//     TimedBlock.beginFunction(@src(), .OutputLightingTextures);
//     defer TimedBlock.endFunction(@src(), .OutputLightingTextures);
//
//     var point_index: u32 = 1; // Light point index 0 is never used.
//     while (point_index < solution.point_count) : (point_index += 1) {
//         const point: *LightingPoint = &solution.points[point_index];
//         // const position: Vector3 = point.position;
//         var color: Color3 = solution.accumulated_pps[point_index].plus(solution.emission_pps[point_index]);
//         const direction: Vector3 = point.normal;
//
//         if (direction.z() < 0) {
//             // _ = direction.setZ(-direction.z());
//             // Negate the red channel to indicate that Z was negative, since we have no storage for the sign of Z.
//             _ = color.setR(-color.r());
//         }
//
//         // dest.light_data0[point.pack_index] = .new(position.x(), position.y(), position.z(), direction.x());
//         // dest.light_data1[point.pack_index] = .new(color.r(), color.g(), color.b(), direction.y());
//     }
// }
