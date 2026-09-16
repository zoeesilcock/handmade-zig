const std = @import("std");
const math = @import("math.zig");
const memory = @import("memory.zig");
const renderer = @import("renderer.zig");
const handmade = @import("handmade.zig");

// Types.
const MemoryArena = memory.MemoryArena;
const TextureOp = renderer.TextureOp;
const Color = math.Color;

pub const ImageU32 = struct {
    width: u32,
    height: u32,
    pixels: ?[*]u32,

    pub fn getTotalImageSize(self: ImageU32) u32 {
        return self.width * self.height * 4;
    }

    pub fn pushImage(arena: *MemoryArena, width: u32, height: u32) ImageU32 {
        var result: ImageU32 = .{
            .width = width,
            .height = height,
            .pixels = undefined,
        };
        const size: u32 = result.getTotalImageSize();
        result.pixels = arena.pushArray(size, u32, null, @src());
        return result;
    }
};

pub const MipIterator = struct {
    level: u32 = 0,
    image: ImageU32,

    pub fn iterateMips(width: u32, height: u32, data: ?*anyopaque) MipIterator {
        return .{
            .level = 0,
            .image = .{
                .width = width,
                .height = height,
                .pixels = @ptrCast(@alignCast(data)),
            },
        };
    }

    pub fn isValid(self: *MipIterator) bool {
        return self.image.width != 0 and self.image.height != 0;
    }

    pub fn advance(self: *MipIterator) void {
        if (self.image.pixels != null) {
            self.image.pixels.? += self.image.width * self.image.height;
        }

        if (self.image.width == 1 and self.image.height == 1) {
            self.image.width = 0;
            self.image.height = 0;
        } else {
            self.level += 1;
            if (self.image.width > 1) {
                self.image.width = (self.image.width + 1) / 2;
            }
            if (self.image.height > 1) {
                self.image.height = (self.image.height + 1) / 2;
            }
        }
    }
};

pub fn generateSequentialMIPs(width: u32, height: u32, data: *anyopaque) void {
    var mip: MipIterator = .iterateMips(width, height, data);
    var source: ImageU32 = mip.image;
    mip.advance();
    while (mip.isValid()) {
        std.debug.assert((@intFromPtr(source.pixels) + (source.width * source.height * 4)) == @intFromPtr(mip.image.pixels));
        downsample2x(source, &mip.image);
        source = mip.image;
        mip.advance();
    }

    std.debug.assert(getTotalSizeForMIPs(width, height) == (@intFromPtr(mip.image.pixels) - @intFromPtr(data)));
}

pub fn fillImage(dest: *ImageU32, color: u32) void {
    var dest_pixel: [*]u32 = @ptrCast(dest.pixels);
    var count: u32 = dest.width * dest.height * 4;
    while (count > 0) : (count -= 1) {
        dest_pixel[0] = color;
        dest_pixel += 1;
    }
}

pub fn getTotalSizeForMIPs(width: u32, height: u32) u32 {
    var result: u32 = 0;
    var mip: MipIterator = .iterateMips(width, height, null);
    while (mip.isValid()) : (mip.advance()) {
        result += mip.image.width * mip.image.height * 4;
    }
    return result;
}

pub fn downsample2x(source: ImageU32, dest: *ImageU32) void {
    var dest_pixel: [*]u32 = @ptrCast(dest.pixels);
    var source_row: [*]u32 = @ptrCast(source.pixels);

    var y: u32 = 0;
    while (y < dest.height) : (y += 1) {
        var source_pixel0: [*]u32 = source_row;
        var source_pixel1: [*]u32 = source_row;
        if ((y + 1) < source.height) {
            source_pixel1 += source.width;
        }

        var x: u32 = 0;
        while (x < dest.width) : (x += 1) {
            var pixel_00: Color = .unpackColorBGRA(source_pixel0[0]);
            source_pixel0 += 1;
            var pixel_01: Color = .unpackColorBGRA(source_pixel1[0]);
            source_pixel1 += 1;

            var pixel_10: Color = pixel_00;
            var pixel_11: Color = pixel_01;
            if ((x + 1) < source.width) {
                pixel_10 = .unpackColorBGRA(source_pixel0[0]);
                source_pixel0 += 1;
                pixel_11 = .unpackColorBGRA(source_pixel1[0]);
                source_pixel1 += 1;
            }

            pixel_00 = math.sRGB255ToLinear1(pixel_00);
            pixel_10 = math.sRGB255ToLinear1(pixel_10);
            pixel_01 = math.sRGB255ToLinear1(pixel_01);
            pixel_11 = math.sRGB255ToLinear1(pixel_11);

            var color: Color = pixel_00.plus(pixel_10).plus(pixel_01).plus(pixel_11).scaledTo(0.25);

            color = math.linear1ToSRGB255(color);

            dest_pixel[0] = Color.packColorBGRA(color);
            dest_pixel += 1;
        }

        source_row += source.width * 2;
    }
}
