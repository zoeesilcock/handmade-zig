const intrinsics = @import("intrinsics.zig");
const rendergroup = @import("rendergroup.zig");
const entities = @import("entities.zig");
const asset = @import("asset.zig");
const shared = @import("shared.zig");
const math = @import("math.zig");
const simd = @import("simd.zig");
const random = @import("random.zig");
const memory = @import("memory.zig");
const file_formats = @import("file_formats");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const Vec4f = simd.Vec4f;
const V3_4x = simd.V3_4x;
const V4_4x = simd.V4_4x;
const RenderGroup = rendergroup.RenderGroup;
const ObjectTransform = rendergroup.ObjectTransform;
const EntityId = entities.EntityId;
const GameModeWorld = @import("world_mode.zig").GameModeWorld;
const Assets = asset.Assets;
const AssetTagId = asset.AssetTagId;
const RandomSeries = random.Series;
const BitmapId = file_formats.BitmapId;
const TimedBlock = debug_interface.TimedBlock;

var global_config = &@import("config.zig").global_config;
pub const PARTICLE_CEL_DIM = 32;

const MAX_PARTICLE_COUNT = 1024;
const MAX_PARTICLE_COUNT_4 = MAX_PARTICLE_COUNT / 4;

pub const ParticleCache = struct {
    particle_entropy: RandomSeries, // Not for gameplay, ever!
    fire_system: ParticleSystem,
};

pub const ParticleSystem = struct {
    particles: [MAX_PARTICLE_COUNT_4]Particle4x,
    next_particle_4: u32,
    bitmap_id: ?BitmapId,
};

const Particle4x = struct {
    p: V3_4x,
    dp: V3_4x,
    ddp: V3_4x,
    c: V4_4x,
    dc: V4_4x,
};

pub fn initParticleCache(cache: *ParticleCache, assets: *Assets) void {
    memory.zeroStruct(ParticleCache, cache);
    cache.particle_entropy = .seed(1234);

    var match_vector = asset.AssetVector{};
    match_vector.e[AssetTagId.FacingDirection.toInt()] = 0;
    var weight_vector = asset.AssetVector{};
    weight_vector.e[AssetTagId.FacingDirection.toInt()] = 1;

    cache.fire_system.bitmap_id = assets.getBestMatchBitmap(.Head, &match_vector, &weight_vector);
}

pub fn updateAndRenderParticleSystem(
    cache: *ParticleCache,
    delta_time: f32,
    render_group: *RenderGroup,
    frame_displacement: Vector3,
    transform: *ObjectTransform,
) void {
    TimedBlock.beginFunction(@src(), .UpdateAndRenderParticleSystem);
    defer TimedBlock.endFunction(@src(), .UpdateAndRenderParticleSystem);

    updateAndRenderFire(
        &cache.fire_system,
        delta_time,
        frame_displacement,
        render_group,
        transform,
    );
}

pub fn spawnFire(cache: *ParticleCache, at_position_in: Vector3) void {
    const system: *ParticleSystem = &cache.fire_system;
    const entropy: *RandomSeries = &cache.particle_entropy;
    const at_position: V3_4x = .fromVector3(at_position_in);

    const particle_index = system.next_particle_4;
    system.next_particle_4 += 1;

    if (system.next_particle_4 >= MAX_PARTICLE_COUNT_4) {
        system.next_particle_4 = 0;
    }

    const a: *Particle4x = &system.particles[particle_index];

    a.p.x = simd.mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, -0.05, 0.05 });
    a.p.y = @splat(0);
    a.p.z = @splat(0);
    a.p = a.p.plus(at_position);

    a.dp.x = simd.mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, -0.01, 0.01 });
    a.dp.y = simd.mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.7, 1 }) * @as(Vec4f, @splat(7));
    a.dp.z = @splat(0);

    a.ddp.x = @splat(0);
    a.ddp.y = @splat(-9.8);
    a.ddp.z = @splat(0);

    a.c.r = simd.mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.75, 1 });
    a.c.g = simd.mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.75, 1 });
    a.c.b = simd.mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.75, 1 });
    a.c.a = @splat(1);

    a.dc.r = @splat(0);
    a.dc.g = @splat(0);
    a.dc.b = @splat(0);
    a.dc.a = @splat(-1);
}

fn updateAndRenderFire(
    system: *ParticleSystem,
    delta_time: f32,
    frame_displacement_in: Vector3,
    render_group: *RenderGroup,
    transform: *ObjectTransform,
) void {
    const frame_displacement: V3_4x = .fromVector3(frame_displacement_in);

    // const grid_scale: f32 = 0.25;
    // const inv_grid_scale: f32 = 1 / grid_scale;
    // const grid_origin = Vector3.new(-0.5 * grid_scale * PARTICLE_CEL_DIM, 0, 0);
    //
    // {
    //     // Zero the paricle cels.
    //     {
    //         var y: u32 = 0;
    //         while (y < PARTICLE_CEL_DIM) : (y += 1) {
    //             var x: u32 = 0;
    //             while (x < PARTICLE_CEL_DIM) : (x += 1) {
    //                 world_mode.particle_cels[y][x] = ParticleCel{};
    //             }
    //         }
    //     }
    //
    //     var particle_index: u32 = 0;
    //     while (particle_index < world_mode.particles.len) : (particle_index += 1) {
    //         const particle: *Particle = &world_mode.particles[particle_index];
    //         const position = particle.position.minus(grid_origin).scaledTo(inv_grid_scale);
    //         const ix: i32 = intrinsics.floorReal32ToInt32(position.x());
    //         const iy: i32 = intrinsics.floorReal32ToInt32(position.y());
    //         var x: u32 = if (ix > 0) 0 +% @as(u32, @intCast(ix)) else 0 -% @abs(ix);
    //         var y: u32 = if (iy > 0) 0 +% @as(u32, @intCast(iy)) else 0 -% @abs(iy);
    //
    //         if (x < 0) {
    //             x = 0;
    //         }
    //         if (x > (PARTICLE_CEL_DIM - 1)) {
    //             x = (PARTICLE_CEL_DIM - 1);
    //         }
    //         if (y < 0) {
    //             y = 0;
    //         }
    //         if (y > (PARTICLE_CEL_DIM - 1)) {
    //             y = (PARTICLE_CEL_DIM - 1);
    //         }
    //
    //         const cel = &world_mode.particle_cels[y][x];
    //         const density: f32 = particle.color.a();
    //         cel.density += density;
    //         cel.velocity_times_density =
    //             cel.velocity_times_density.plus(particle.velocity.scaledTo(density));
    //     }
    // }
    //
    // if (global_config.Particles_ShowGrid) {
    //     var y: u32 = 0;
    //     while (y < PARTICLE_CEL_DIM) : (y += 1) {
    //         var x: u32 = 0;
    //         while (x < PARTICLE_CEL_DIM) : (x += 1) {
    //             const cel = &world_mode.particle_cels[y][x];
    //             const alpha: f32 = math.clampf01(0.1 * cel.density);
    //             render_group.pushRectangle(
    //                 particle_transform,
    //                 Vector2.one().scaledTo(grid_scale),
    //                 Vector3.new(
    //                     @floatFromInt(x),
    //                     @floatFromInt(y),
    //                     0,
    //                 ).scaledTo(grid_scale).plus(grid_origin),
    //                 Color.new(alpha, alpha, alpha, 0),
    //             );
    //         }
    //     }
    // }

    var particle_index: u32 = 0;
    while (particle_index < MAX_PARTICLE_COUNT_4) : (particle_index += 1) {
        const a: *Particle4x = &system.particles[particle_index];

        // const position = particle.position.minus(grid_origin).scaledTo(inv_grid_scale);
        // const ix: i32 = intrinsics.floorReal32ToInt32(position.x());
        // const iy: i32 = intrinsics.floorReal32ToInt32(position.y());
        // var x: u32 = if (ix > 0) 0 +% @as(u32, @intCast(ix)) else 0 -% @abs(ix);
        // var y: u32 = if (iy > 0) 0 +% @as(u32, @intCast(iy)) else 0 -% @abs(iy);
        //
        // if (x < 1) {
        //     x = 1;
        // }
        // if (x > (PARTICLE_CEL_DIM - 2)) {
        //     x = (PARTICLE_CEL_DIM - 2);
        // }
        // if (y < 1) {
        //     y = 1;
        // }
        // if (y > (PARTICLE_CEL_DIM - 2)) {
        //     y = (PARTICLE_CEL_DIM - 2);
        // }
        //
        // const cel_center = &world_mode.particle_cels[y][x];
        // const cel_left = &world_mode.particle_cels[y][x - 1];
        // const cel_right = &world_mode.particle_cels[y][x + 1];
        // const cel_down = &world_mode.particle_cels[y - 1][x];
        // const cel_up = &world_mode.particle_cels[y + 1][x];
        //
        // var dispersion = Vector3.zero();
        // const dispersion_coefficient: f32 = 1;
        // dispersion = dispersion.plus(Vector3.new(-1, 0, 0)
        //     .scaledTo(dispersion_coefficient * (cel_center.density - cel_left.density)));
        // dispersion = dispersion.plus(Vector3.new(1, 0, 0)
        //     .scaledTo(dispersion_coefficient * (cel_center.density - cel_right.density)));
        // dispersion = dispersion.plus(Vector3.new(0, -1, 0)
        //     .scaledTo(dispersion_coefficient * (cel_center.density - cel_down.density)));
        // dispersion = dispersion.plus(Vector3.new(0, 1, 0)
        //     .scaledTo(dispersion_coefficient * (cel_center.density - cel_up.density)));

        // Simulate particle.
        a.p = a.p.plus(a.ddp.scaledTo(0.5 * math.square(delta_time))
            .plus(a.dp.scaledTo(delta_time)))
            .plus(frame_displacement);
        a.dp = a.dp.plus(a.ddp.scaledTo(delta_time));
        a.c = a.c.plus(a.dc.scaledTo(delta_time));

        // if (particle.position.y() < 0) {
        //     const coefficient_of_restitution = 0.3;
        //     const coefficient_of_friction = 0.7;
        //     _ = particle.position.setY(-particle.position.y());
        //     _ = particle.velocity.setY(-coefficient_of_restitution * particle.velocity.y());
        //     _ = particle.velocity.setX(coefficient_of_friction * particle.velocity.x());
        // }
        //
        // var color = particle.color.clamp01();
        // if (particle.color.a() > 0.9) {
        //     _ = color.setA(0.9 * math.clamp01MapToRange(1, 0.9, color.a()));
        // }

        // Render particle.
        var sub_index: u32 = 0;
        while (sub_index < 4) : (sub_index += 1) {
            const p: Vector3 = .new(a.p.x[sub_index], a.p.y[sub_index], a.p.z[sub_index]);
            const c: Color = .new(a.c.r[sub_index], a.c.g[sub_index], a.c.b[sub_index], a.c.a[sub_index]);
            if (c.a() > 0) {
                render_group.pushBitmapId(transform, system.bitmap_id, 1, p, c, null, null, null);
            }
        }
    }
}
