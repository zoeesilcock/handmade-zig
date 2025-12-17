const std = @import("std");
const math = @import("math.zig");
const simd = @import("simd.zig");
const intrinsics = @import("intrinsics.zig");

pub const Series = extern struct {
    state: simd.U32_4x,

    pub fn seed(opt_seed1: ?u32, opt_seed2: ?u32, opt_seed3: ?u32, opt_seed4: ?u32) Series {
        const seed1 = opt_seed1 orelse 78953890;
        const seed2 = opt_seed2 orelse 235498;
        const seed3 = opt_seed3 orelse 893456;
        const seed4 = opt_seed4 orelse 93453080;
        return Series{ .state = .{ seed1, seed2, seed3, seed4 } };
    }

    pub fn randomInt_4x(self: *Series) simd.U32_4x {
        var result = self.state;
        result ^= result << @as(simd.U32_4x, @splat(13));
        result ^= result >> @as(simd.U32_4x, @splat(17));
        result ^= result << @as(simd.U32_4x, @splat(5));
        self.state = result;
        return result;
    }

    pub fn randomInt(self: *Series) u32 {
        return self.randomInt_4x()[0];
    }

    pub fn randomChoice(self: *Series, choice_count: u32) u32 {
        return self.randomInt() % choice_count;
    }

    pub fn randomUnilateral(self: *Series) f32 {
        const divisor = 1.0 / @as(f32, @floatFromInt(std.math.maxInt(u32)));
        return divisor * @as(f32, @floatFromInt(self.randomInt()));
    }

    pub fn randomBilateral(self: *Series) f32 {
        return 2.0 * self.randomUnilateral() - 1.0;
    }

    pub fn randomUnilateral_4x(self: *Series) simd.F32_4x {
        const divisor: simd.F32_4x = @splat(1.0 / @as(f32, @floatFromInt(std.math.maxInt(i32))));
        return divisor * @as(simd.F32_4x, @floatFromInt(
            self.randomInt_4x() & @as(simd.U32_4x, @splat(std.math.maxInt(i32))),
        ));
    }

    pub fn randomBilateral_4x(self: *Series) simd.F32_4x {
        return (@as(simd.F32_4x, @splat(2.0)) * self.randomUnilateral_4x()) - @as(simd.F32_4x, @splat(1.0));
    }

    pub fn randomFloatBetween(self: *Series, min: f32, max: f32) f32 {
        return math.lerpf(min, max, self.randomUnilateral());
    }

    pub fn randomIntBetween(self: *Series, min: i32, max: i32) i32 {
        return min + @mod(@as(i32, @intCast(self.randomInt())), ((max + 1) - min));
    }
};

pub const SeriesPCG = extern struct {
    state: u64,
    selector: u64,

    pub fn seed(seed_state: u64, selector: u64) SeriesPCG {
        return .{ .state = seed_state, .selector = (selector << 1) | 1 };
    }

    pub fn randomInt(self: *SeriesPCG) u32 {
        var state: u64 = self.state;
        state = state * 6364136223846793005 + self.selector;
        self.state = state;

        const pre_rotate: u32 = @intCast((state ^ (state >> 18)) >> 27);
        const result: u32 = intrinsics.rotateRight(pre_rotate, @intCast(state >> 59));
        return result;
    }

    pub fn randomUnilateral(self: *SeriesPCG) f32 {
        const divisor = 1.0 / @as(f32, @floatFromInt(std.math.maxInt(u32)));
        return divisor * @as(f32, @floatFromInt(self.randomInt()));
    }

    pub fn randomBilateral(self: *SeriesPCG) f32 {
        return 2.0 * self.randomUnilateral() - 1.0;
    }
};
