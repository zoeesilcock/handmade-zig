const rendergroup = @import("rendergroup.zig");
const entities = @import("entities.zig");
const std = @import("std");

const RenderGroup = rendergroup.RenderGroup;
const EntityId = entities.EntityId;

const MAX_PARTICLE_COUNT = 4096;
const PARTICLE_SYSTEM_COUNT = 64;

pub const ParticleSystemInfo = struct {
    id: EntityId,
    frames_since_touched: u32,
};

pub const ParticleSystem = struct {
    x: [MAX_PARTICLE_COUNT]f32,
    y: [MAX_PARTICLE_COUNT]f32,
    z: [MAX_PARTICLE_COUNT]f32,

    r: [MAX_PARTICLE_COUNT]f32,
    g: [MAX_PARTICLE_COUNT]f32,
    b: [MAX_PARTICLE_COUNT]f32,
    a: [MAX_PARTICLE_COUNT]f32,

    t: [MAX_PARTICLE_COUNT]f32,
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
    _ = delta_time;
    _ = render_group;

    std.debug.assert(cache.systems.len == cache.system_infos.len);

    var system_index: u32 = 0;
    while (system_index < cache.systems.len) : (system_index += 1) {
        const system: *ParticleSystem = &cache.systems[system_index];
        const info: *ParticleSystemInfo = &cache.system_infos[system_index];
        _ = system;
        _ = info;
        // info.frames_since_touched += 1;
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
