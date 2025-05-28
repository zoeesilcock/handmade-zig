const intrinsics = @import("intrinsics.zig");
const rendergroup = @import("rendergroup.zig");
const entities = @import("entities.zig");
const asset = @import("asset.zig");
const shared = @import("shared.zig");
const math = @import("math.zig");
const random = @import("random.zig");
const std = @import("std");

const Vec4f = math.Vec4f;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Color = math.Color;
const RenderGroup = rendergroup.RenderGroup;
const ObjectTransform = rendergroup.ObjectTransform;
const EntityId = entities.EntityId;
const GameModeWorld = @import("world_mode.zig").GameModeWorld;
const AssetTagId = asset.AssetTagId;
const RandomSeries = random.Series;

var global_config = &@import("config.zig").global_config;
pub const PARTICLE_CEL_DIM = 32;

const MAX_PARTICLE_COUNT = 4096;
const MAX_PARTICLE_COUNT_4 = MAX_PARTICLE_COUNT / 4;
const PARTICLE_SYSTEM_COUNT = 64;

pub const ParticleSystemInfo = struct {
    id: EntityId,
    frames_since_touched: u32,
};

pub const ParticleSystem = extern struct {
    p_x: [MAX_PARTICLE_COUNT_4]Vec4f,
    p_y: [MAX_PARTICLE_COUNT_4]Vec4f,
    p_z: [MAX_PARTICLE_COUNT_4]Vec4f,

    dp_x: [MAX_PARTICLE_COUNT_4]Vec4f,
    dp_y: [MAX_PARTICLE_COUNT_4]Vec4f,
    dp_z: [MAX_PARTICLE_COUNT_4]Vec4f,

    ddp_x: [MAX_PARTICLE_COUNT_4]Vec4f,
    ddp_y: [MAX_PARTICLE_COUNT_4]Vec4f,
    ddp_z: [MAX_PARTICLE_COUNT_4]Vec4f,

    c_r: [MAX_PARTICLE_COUNT_4]Vec4f,
    c_g: [MAX_PARTICLE_COUNT_4]Vec4f,
    c_b: [MAX_PARTICLE_COUNT_4]Vec4f,
    c_a: [MAX_PARTICLE_COUNT_4]Vec4f,

    dc_r: [MAX_PARTICLE_COUNT_4]Vec4f,
    dc_g: [MAX_PARTICLE_COUNT_4]Vec4f,
    dc_b: [MAX_PARTICLE_COUNT_4]Vec4f,
    dc_a: [MAX_PARTICLE_COUNT_4]Vec4f,

    next_particle_4: u32,
};

const ParticleVec3 = extern struct {
    x: Vec4f,
    ignored0: [MAX_PARTICLE_COUNT_4 - 1]Vec4f,

    y: Vec4f,
    ignored1: [MAX_PARTICLE_COUNT_4 - 1]Vec4f,

    z: Vec4f,
    ignored2: [MAX_PARTICLE_COUNT_4 - 1]Vec4f,

    pub fn plus(self: ParticleVec3, other: ParticleVec3) ParticleVec3 {
        var result = self;
        result.x += other.x;
        result.y += other.y;
        result.z += other.z;
        return result;
    }

    pub fn scaledTo(self: ParticleVec3, scalar: f32) ParticleVec3 {
        var result = self;
        result.x *= @splat(scalar);
        result.y *= @splat(scalar);
        result.z *= @splat(scalar);
        return result;
    }
};

const ParticleVec4 = extern struct {
    r: Vec4f,
    ignored0: [MAX_PARTICLE_COUNT_4 - 1]Vec4f,

    g: Vec4f,
    ignored1: [MAX_PARTICLE_COUNT_4 - 1]Vec4f,

    b: Vec4f,
    ignored2: [MAX_PARTICLE_COUNT_4 - 1]Vec4f,

    a: Vec4f,
    ignored3: [MAX_PARTICLE_COUNT_4 - 1]Vec4f,

    pub fn plus(self: ParticleVec4, other: ParticleVec4) ParticleVec4 {
        var result = self;
        result.r += other.r;
        result.g += other.g;
        result.b += other.b;
        result.a += other.a;
        return result;
    }

    pub fn scaledTo(self: ParticleVec4, scalar: f32) ParticleVec4 {
        var result = self;
        result.r *= @splat(scalar);
        result.g *= @splat(scalar);
        result.b *= @splat(scalar);
        result.a *= @splat(scalar);
        return result;
    }
};

const Particle = extern struct {
    p: *ParticleVec3 = undefined,
    dp: *ParticleVec3 = undefined,
    ddp: *ParticleVec3 = undefined,
    c: *ParticleVec4 = undefined,
    dc: *ParticleVec4 = undefined,
};

pub const ParticleSpec = extern struct {
    something_something_something: f32,
};

pub const ParticleCache = struct {
    system_infos: [PARTICLE_SYSTEM_COUNT]ParticleSystemInfo,
    systems: [PARTICLE_SYSTEM_COUNT]ParticleSystem,
};

pub fn initParticleCache(cache: *ParticleCache) void {
    var system_index: u32 = 0;
    while (system_index < cache.systems.len) : (system_index += 1) {
        const info: *ParticleSystemInfo = &cache.system_infos[system_index];
        info.id.value = 0;
        info.frames_since_touched = 0;
    }
}

pub fn initParticleSystem(
    cache: *ParticleCache,
    system: ?*ParticleSystem,
    id: EntityId,
    spec: *ParticleSpec,
) void {
    _ = cache;
    _ = system;
    _ = id;
    _ = spec;
}

pub fn updateAndRenderParticleSystem(cache: *ParticleCache, delta_time: f32, render_group: *RenderGroup) void {
    std.debug.assert(cache.systems.len == cache.system_infos.len);

    var system_index: u32 = 0;
    while (system_index < cache.systems.len) : (system_index += 1) {
        const system: *ParticleSystem = &cache.systems[system_index];
        const info: *ParticleSystemInfo = &cache.system_infos[system_index];

        var entropy: RandomSeries = .seed(3);
        playAround(system, &entropy, delta_time, render_group, .defaultFlat());
        info.frames_since_touched += 1;
    }
}

pub fn getOrCreateParticleSystem(
    cache: *ParticleCache,
    id: EntityId,
    spec: *ParticleSpec,
    create_if_not_found: bool,
) ?*ParticleSystem {
    var result: ?*ParticleSystem = null;
    var max_frames_since_touched: u32 = 0;
    var replace: ?*ParticleSystem = null;
    var system_index: u32 = 0;
    while (system_index < cache.system_infos.len) : (system_index += 1) {
        const system_info: *ParticleSystemInfo = &cache.system_infos[system_index];
        if (id.equals(system_info.id)) {
            result = &cache.systems[system_index];
            break;
        }

        if (max_frames_since_touched < system_info.frames_since_touched) {
            max_frames_since_touched = system_info.frames_since_touched;
            replace = &cache.systems[system_index];
        }
    }

    if (create_if_not_found and result == null) {
        result = replace;
        initParticleSystem(cache, result, id, spec);
    }

    return result;
}

pub fn touchParticleSystem(cache: *ParticleCache, opt_system: ?*ParticleSystem) void {
    if (opt_system) |system| {
        const index: u32 = @intCast(@intFromPtr(system) - @intFromPtr(&cache.systems));
        std.debug.assert(index < cache.system_infos.len);
        const info: *ParticleSystemInfo = &cache.system_infos[index];

        info.frames_since_touched = 0;
    }
}

fn mmSetExpr(comptime method: anytype, args: anytype) Vec4f {
    return [_]f32{
        @call(.auto, method, args),
        @call(.auto, method, args),
        @call(.auto, method, args),
        @call(.auto, method, args),
    };
}

fn getParticle(system: *ParticleSystem, ai: u32, result: *Particle) void {
    result.p = @ptrCast(&system.p_x[ai]);
    result.dp = @ptrCast(&system.dp_x[ai]);
    result.ddp = @ptrCast(&system.ddp_x[ai]);
    result.c = @ptrCast(&system.c_r[ai]);
    result.dc = @ptrCast(&system.dc_r[ai]);
}

fn playAround(
    system: *ParticleSystem,
    entropy: *RandomSeries,
    delta_time: f32,
    render_group: *RenderGroup,
    entity_transform: ObjectTransform,
) void {
    {
        const ai = system.next_particle_4;
        system.next_particle_4 += 1;

        if (system.next_particle_4 >= MAX_PARTICLE_COUNT_4) {
            system.next_particle_4 = 0;
        }

        var a: Particle = .{};
        getParticle(system, ai, &a);

        a.p.*.x = mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, -0.05, 0.05 });
        a.p.*.y = @splat(0);
        a.p.*.z = @splat(0);

        a.dp.*.x = mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, -0.01, 0.01 });
        a.dp.*.y = mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.7, 1 });
        a.dp.*.z = @splat(0);

        a.ddp.*.x = @splat(0);
        a.ddp.*.y = @splat(-9.8);
        a.ddp.*.z = @splat(0);

        a.c.*.r = mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.75, 1 });
        a.c.*.g = mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.75, 1 });
        a.c.*.b = mmSetExpr(RandomSeries.randomFloatBetween, .{ entropy, 0.75, 1 });
        a.c.*.a = @splat(1);

        a.dc.*.r = @splat(0);
        a.dc.*.g = @splat(0);
        a.dc.*.b = @splat(0);
        a.dc.*.a = @splat(-0.5);
    }

    _ = render_group;
    _ = entity_transform;
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
    //                 entity_transform,
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

    var ai: u32 = 0;
    while (ai < MAX_PARTICLE_COUNT_4) : (ai += 1) {
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
        var a: Particle = .{};
        getParticle(system, ai, &a);

        a.p.* = a.p.plus(a.ddp.scaledTo(0.5 * math.square(delta_time)).plus(a.dp.scaledTo(delta_time)));
        // a.p.*.x += delta_time_half_squared * a.ddp.x + delta_time_4 * a.dp.x;
        // a.p.*.y += delta_time_half_squared * a.ddp.y + delta_time_4 * a.dp.y;
        // a.p.*.z += delta_time_half_squared * a.ddp.z + delta_time_4 * a.dp.z;

        a.dp.* = a.dp.plus(a.ddp.scaledTo(delta_time));
        // a.dp.*.x += delta_time_4 * a.ddp.x;
        // a.dp.*.y += delta_time_4 * a.ddp.y;
        // a.dp.*.z += delta_time_4 * a.ddp.z;

        a.c.* = a.c.plus(a.dc.scaledTo(delta_time));
        // a.c.*.r += delta_time_4 * a.dc.r;
        // a.c.*.g += delta_time_4 * a.dc.g;
        // a.c.*.b += delta_time_4 * a.dc.b;
        // a.c.*.a += delta_time_4 * a.dc.a;

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
        // render_group.pushBitmapId(
        //     entity_transform,
        //     particle.bitmap_id,
        //     1,
        //     particle.position,
        //     color,
        //     null,
        //     null,
        //     null,
        // );
    }
}
