const std = @import("std");
const memory = @import("memory.zig");
const types = @import("types.zig");

pub const RiffChunkHeader = extern struct {
    id: u32,
    size: u32,
};

pub const RiffHeader = extern struct {
    riff_id: u32,
    size: u32,
    file_type_id: u32,
};

pub const RiffId = enum(u32) {
    RIFF = riffCode('R', 'I', 'F', 'F'),
    _,
};

pub const RiffIterator = struct {
    at: [*]u8,
    stop: [*]u8,

    pub fn iterateRiff(buffer: types.Buffer, header: *RiffHeader) RiffIterator {
        var result: RiffIterator = .{ .at = undefined, .stop = undefined };
        if (buffer.count >= @sizeOf(RiffHeader)) {
            header.* = @as(*RiffHeader, @ptrCast(@alignCast(buffer.data))).*;
            const data_start: [*]u8 = buffer.data + @sizeOf(RiffHeader);
            result = RiffIterator.parseWaveChunkAt(data_start, data_start + header.size - 4);
        } else {
            memory.zeroStruct(RiffHeader, header);
        }
        return result;
    }

    pub fn parseWaveChunkAt(at: *anyopaque, stop: *anyopaque) RiffIterator {
        return RiffIterator{ .at = @ptrCast(at), .stop = @ptrCast(stop) };
    }

    pub fn nextChunk(self: RiffIterator) RiffIterator {
        const chunk: *RiffChunkHeader = @ptrCast(@alignCast(self.at));
        const size = (chunk.size + 1) & ~@as(u32, @intCast(1));
        return RiffIterator{ .at = self.at + @sizeOf(RiffChunkHeader) + size, .stop = self.stop };
    }

    pub fn isValid(self: RiffIterator) bool {
        return @intFromPtr(self.at) < @intFromPtr(self.stop);
    }

    pub fn getType(self: RiffIterator) ?u32 {
        const chunk: *RiffChunkHeader = @ptrCast(@alignCast(self.at));
        return chunk.id;
    }

    pub fn getChunkData(self: RiffIterator) *anyopaque {
        return @ptrCast(self.at + @sizeOf(RiffChunkHeader));
    }

    pub fn getChunkDataSize(self: RiffIterator) u32 {
        const chunk: *RiffChunkHeader = @ptrCast(@alignCast(self.at));
        return chunk.size;
    }
};

pub fn riffCode(a: u32, b: u32, in_c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, in_c << 16) | @as(u32, d << 24);
}
