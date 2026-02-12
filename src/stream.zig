const std = @import("std");
const memory = @import("memory.zig");
const shared = @import("shared.zig");

// Types.
const Buffer = shared.Buffer;
const MemoryArena = memory.MemoryArena;

pub const Chunk = struct {
    file_name: [:0]const u8,
    line: u32,

    contents: shared.Buffer = .{},

    next: ?*Chunk = null,
};

pub const Stream = struct {
    arena: ?*MemoryArena = null,
    errors: ?*Stream = null,

    contents: shared.Buffer = .{},

    bit_count: u32 = 0,
    bit_buf: u32 = 0,
    underflowed: bool = false,

    first: ?*Chunk = null,
    last: ?*Chunk = null,

    pub fn makeReadStream(contents: Buffer, errors: ?*Stream) Stream {
        return .{
            .contents = contents,
            .errors = errors,
        };
    }

    pub fn onDemandMemoryStream(arena: ?*MemoryArena, errors: ?*Stream) Stream {
        return .{
            .arena = arena,
            .errors = errors,
        };
    }

    pub fn consumeType(self: *Stream, T: type) ?*T {
        return @ptrCast(@alignCast(self.consumeSize(@sizeOf(T))));
    }

    pub fn peekBits(self: *Stream, bit_count: u32) u32 {
        std.debug.assert(bit_count <= 32);

        var result: u32 = 0;

        while (self.bit_count < bit_count and !self.underflowed) {
            const byte: u32 = @intCast(self.consumeType(u8).?.*);
            self.bit_buf |= (byte << @as(u5, @intCast(self.bit_count)));
            self.bit_count += 8;
        }

        result = self.bit_buf & ((@as(u32, 1) << @as(u5, @intCast(bit_count))) - 1);

        return result;
    }

    pub fn discardBits(self: *Stream, bit_count: u32) void {
        self.bit_count -= bit_count;
        self.bit_buf >>= @intCast(bit_count);
    }

    pub fn consumeBits(self: *Stream, bit_count: u32) u32 {
        const result: u32 = self.peekBits(bit_count);
        self.discardBits(bit_count);
        return result;
    }

    pub fn flushByte(self: *Stream) void {
        const flush_count = @mod(self.bit_count, 8);
        _ = self.consumeBits(flush_count);
    }

    pub fn refillIfNecessary(self: *Stream) void {
        // TODO: Use a free list to recycle chunks?
        if (self.contents.count == 0 and self.first != null) {
            const this: *Chunk = self.first.?;
            self.contents = this.contents;
            self.first = this.next;
        }
    }

    pub fn consumeSize(self: *Stream, size: usize) ?[*]u8 {
        self.refillIfNecessary();

        const result: ?[*]u8 = self.contents.advance(size);
        if (result == null) {
            output(self.errors, @src(), "File underflow", .{});
            self.underflowed = true;
        }

        std.debug.assert(!self.underflowed);

        return result;
    }

    pub fn appendChunk(self: *Stream, size: usize, contents: [:0]align(1) u8) *Chunk {
        const chunk: *Chunk = self.arena.?.pushStruct(Chunk, .aligned(@alignOf(Chunk), false));
        chunk.contents.count = size;
        chunk.contents.data = @ptrCast(contents);
        chunk.next = null;

        // Casey's "ridiculous" version.
        // self.last = ((if (self.last != null) self.last.?.next else self.first) = chunk);

        if (self.last != null) {
            self.last.?.next = chunk;
        } else {
            self.first = chunk;
        }
        self.last = chunk;

        return chunk;
    }
};

pub fn output(
    output_stream: ?*Stream,
    comptime source: std.builtin.SourceLocation,
    comptime format: []const u8,
    args: anytype,
) void {
    if (output_stream) |stream| {
        var buffer: [1024]u8 = undefined;
        const size: usize = shared.formatString(buffer.len, @ptrCast(&buffer), @ptrCast(format), args);

        const contents = stream.arena.?.pushCopy(size, &buffer);
        var chunk = stream.appendChunk(size, @ptrCast(contents));
        chunk.line = source.line;
        chunk.file_name = source.file;
    }
}
