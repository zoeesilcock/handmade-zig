const std = @import("std");
const memory = @import("memory.zig");
const stream = @import("stream.zig");

// Types.
const MemoryArena = memory.MemoryArena;
const Stream = stream.Stream;

pub const SoundI16 = struct {
    sample_count: u32,
    channel_count: u32,
    samples: []i16,

    pub fn getTotalSoundSize(self: SoundI16) u32 {
        return self.channel_count * self.sample_count * 2;
    }

    pub fn pushSound(arena: *MemoryArena, sample_count: u32, channel_count: u32) SoundI16 {
        var result: SoundI16 = .{
            .sample_count = sample_count,
            .channel_count = channel_count,
            .samples = undefined,
        };
        const size: u32 = result.getTotalSoundSize();
        result.samples = arena.pushArray(size, u32, null)[0..size];
        return result;
    }
};

const WaveHeader = extern struct {
    riff_id: u32,
    size: u32,
    wave_id: u32,
};

const WaveChunk = extern struct {
    id: u32,
    size: u32,
};

const WaveFmt = extern struct {
    w_format_tag: u16,
    channels: u16,
    n_samples_per_second: u32,
    n_avg_bytes_per_second: u32,
    n_block_align: u16,
    bits_per_sample: u16,
    cb_size: u16,
    w_valid_width_per_sample: u16,
    dw_channel_mask: u32,
    sub_format: [16]u8,
};

const LoadedSound = struct {
    sample_count: u32,
    channel_count: u32,
    samples: [2]?[*]i16,
    free: []const u8,
};

fn riffCode(a: u32, b: u32, in_c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, in_c << 16) | @as(u32, d << 24);
}

const WaveChunkId = enum(u32) {
    ChunkID_fmt = riffCode('f', 'm', 't', ' '),
    ChunkID_data = riffCode('d', 'a', 't', 'a'),
    ChunkID_RIFF = riffCode('R', 'I', 'F', 'F'),
    ChunkID_WAVE = riffCode('W', 'A', 'V', 'E'),
    _,
};

const RiffIterator = struct {
    at: [*]u8,
    stop: [*]u8,

    fn nextChunk(self: RiffIterator) RiffIterator {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        const size = (chunk.size + 1) & ~@as(u32, @intCast(1));
        return RiffIterator{ .at = self.at + @sizeOf(WaveChunk) + size, .stop = self.stop };
    }

    fn isValid(self: RiffIterator) bool {
        return @intFromPtr(self.at) < @intFromPtr(self.stop);
    }

    fn getType(self: RiffIterator) ?WaveChunkId {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        return std.enums.fromInt(WaveChunkId, chunk.id);
    }

    fn getChunkData(self: RiffIterator) *anyopaque {
        return @ptrCast(self.at + @sizeOf(WaveChunk));
    }

    fn getChunkDataSize(self: RiffIterator) u32 {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        return chunk.size;
    }
};

fn parseWaveChunkAt(at: *anyopaque, stop: *anyopaque) RiffIterator {
    return RiffIterator{ .at = @ptrCast(at), .stop = @ptrCast(stop) };
}

pub fn parseWAV(arena: *MemoryArena, file: Stream, info: ?*Stream) SoundI16 {
    _ = arena;
    _ = file;
    _ = info;

    const result: SoundI16 = undefined;
    // const header: *WaveHeader = file.consumeType(*WaveHeader);
    //
    // std.debug.assert(header.riff_id == @intFromEnum(WaveChunkId.ChunkID_RIFF));
    // std.debug.assert(header.wave_id == @intFromEnum(WaveChunkId.ChunkID_WAVE));
    //
    // var channel_count: ?u16 = null;
    // var sample_data: ?[*]i16 = null;
    // var sample_data_size: ?u32 = null;
    //
    // const chunk_address = @intFromPtr(header) + @sizeOf(WaveHeader);
    // var iterator = parseWaveChunkAt(@ptrFromInt(chunk_address), @ptrFromInt(chunk_address + header.size - 4));
    // while (iterator.isValid()) : (iterator = iterator.nextChunk()) {
    //     if (iterator.getType()) |chunk_type| {
    //         switch (chunk_type) {
    //             .ChunkID_fmt => {
    //                 const fmt: *WaveFmt = @ptrCast(@alignCast(iterator.getChunkData()));
    //
    //                 std.debug.assert(fmt.w_format_tag == 1);
    //                 std.debug.assert(fmt.n_samples_per_second == 48000);
    //                 std.debug.assert(fmt.bits_per_sample == 16);
    //                 std.debug.assert(fmt.n_block_align == (@sizeOf(i16) * fmt.channels));
    //
    //                 channel_count = fmt.channels;
    //             },
    //             .ChunkID_data => {
    //                 sample_data = @ptrCast(@alignCast(iterator.getChunkData()));
    //                 sample_data_size = iterator.getChunkDataSize();
    //             },
    //             else => {},
    //         }
    //     }
    // }
    //
    // std.debug.assert(channel_count != null and sample_data != null and sample_data_size != null);
    //
    // result.channel_count = channel_count.?;
    // var sample_count = sample_data_size.? / (channel_count.? * @sizeOf(i16));
    //
    // if (sample_data) |data| {
    //     if (channel_count == 1) {
    //         result.samples[0] = @ptrCast(data);
    //         result.samples[1] = null;
    //     } else if (channel_count == 2) {
    //         result.samples[0] = @ptrCast(data);
    //         result.samples[1] = @ptrCast(data + sample_count);
    //
    //         if (false) {
    //             var i: i16 = 0;
    //             while (i < sample_count) : (i += 1) {
    //                 data[2 * @as(usize, @intCast(i)) + 0] = i;
    //                 data[2 * @as(usize, @intCast(i)) + 1] = i;
    //             }
    //         }
    //
    //         var sample_index: u32 = 0;
    //         while (sample_index < sample_count) : (sample_index += 1) {
    //             const source = data[2 * sample_index];
    //             data[2 * sample_index] = data[sample_index];
    //             data[sample_index] = source;
    //         }
    //     } else {
    //         // Invalid channel count in WAV file.
    //         unreachable;
    //     }
    // }
    //
    // // TODO: Load right channels.
    // result.channel_count = 1;
    //
    // var at_end = true;
    // if (section_sample_count != 0) {
    //     std.debug.assert((section_first_sample_index + section_sample_count) <= sample_count);
    //
    //     at_end = (section_first_sample_index + section_sample_count) == sample_count;
    //     sample_count = section_sample_count;
    //
    //     var channel_index: u32 = 0;
    //     while (channel_index < result.channel_count) : (channel_index += 1) {
    //         result.samples[channel_index].? += section_first_sample_index;
    //     }
    // }
    //
    // if (at_end) {
    //     var channel_index: u32 = 0;
    //     while (channel_index < result.channel_count) : (channel_index += 1) {
    //         var sample_index: u32 = sample_count;
    //         while (sample_index < (sample_count + 8)) : (sample_index += 1) {
    //             result.samples[channel_index].?[sample_index] = 0;
    //         }
    //     }
    // }
    //
    // result.sample_count = sample_count;

    return result;
}
