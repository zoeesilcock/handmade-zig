const std = @import("std");
const memory = @import("memory.zig");
const stream = @import("stream.zig");
const types = @import("types.zig");
const riff = @import("riff.zig");

// Types.
const MemoryArena = memory.MemoryArena;
const Stream = stream.Stream;
const Buffer = types.Buffer;
const RiffIterator = riff.RiffIterator;
const RiffHeader = riff.RiffHeader;
const RiffId = riff.RiffId;

pub const SoundI16 = struct {
    sample_count: u32,
    channel_count: u32,
    samples: []i16,

    pub fn getTotalSoundSize(self: SoundI16) u32 {
        return self.channel_count * self.sample_count * @sizeOf(i16);
    }

    pub fn pushSound(arena: *MemoryArena, sample_count: u32, channel_count: u32) SoundI16 {
        var result: SoundI16 = .{
            .sample_count = sample_count,
            .channel_count = channel_count,
            .samples = undefined,
        };
        const size: u32 = result.getTotalSoundSize();
        result.samples = arena.pushArray(size, i16, null)[0..size];
        return result;
    }

    pub fn getChannelSamples(self: SoundI16, channel_index: u32) [*]i16 {
        std.debug.assert(channel_index < self.channel_count);
        const start = channel_index * self.sample_count;
        return self.samples.ptr + start;
    }
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

pub const WaveChunkId = enum(u32) {
    ChunkID_fmt = riff.riffCode('f', 'm', 't', ' '),
    ChunkID_data = riff.riffCode('d', 'a', 't', 'a'),
    ChunkID_RIFF = riff.riffCode('R', 'I', 'F', 'F'),
    ChunkID_WAVE = riff.riffCode('W', 'A', 'V', 'E'),
    _,
};

pub fn parseWAV(arena: *MemoryArena, contents: Buffer, errors: *Stream) SoundI16 {
    var result: SoundI16 = undefined;
    var header: RiffHeader = undefined;
    var iterator: RiffIterator = .iterateRiff(contents, &header);

    if (header.riff_id == @intFromEnum(RiffId.RIFF) and
        header.file_type_id == @intFromEnum(WaveChunkId.ChunkID_WAVE))
    {
        var channel_count: ?u16 = null;
        var sample_data: ?[*]i16 = null;
        var sample_data_size: ?u32 = null;

        iterator = iterator.nextChunk();
        while (iterator.isValid()) : (iterator = iterator.nextChunk()) {
            if (iterator.getType()) |chunk_type_u32| {
                const chunk_type: WaveChunkId = @enumFromInt(chunk_type_u32);
                switch (chunk_type) {
                    .ChunkID_fmt => {
                        const fmt: *WaveFmt = @ptrCast(@alignCast(iterator.getChunkData()));

                        if (fmt.w_format_tag == 1 and // 1 = PCM.
                            fmt.n_samples_per_second == 48000 and
                            fmt.bits_per_sample == 16 and
                            fmt.n_block_align == (@sizeOf(i16) * fmt.channels))
                        {
                            channel_count = fmt.channels;
                        } else {
                            _ = stream.outputWithSrc(
                                errors,
                                @src(),
                                "ERROR: Unsupported WAV layout: format %u, %uhz, %ubps, %u align.\n",
                                .{
                                    fmt.w_format_tag,
                                    fmt.n_samples_per_second,
                                    fmt.bits_per_sample,
                                    fmt.n_block_align,
                                },
                            );
                        }
                    },
                    .ChunkID_data => {
                        sample_data = @ptrCast(@alignCast(iterator.getChunkData()));
                        sample_data_size = iterator.getChunkDataSize();
                    },
                    else => {},
                }
            }
        }

        if (channel_count != null and sample_data != null and sample_data_size != null) {
            const sample_count = sample_data_size.? / (channel_count.? * @sizeOf(i16));
            result = .pushSound(arena, sample_count, @intCast(channel_count.?));

            var source_sample: [*]i16 = sample_data.?;
            var sample_index: u32 = 0;
            while (sample_index < sample_count) : (sample_index += 1) {
                var channel_index: u32 = 0;
                while (channel_index < channel_count.?) : (channel_index += 1) {
                    result.getChannelSamples(channel_index)[sample_index] = source_sample[0];
                    source_sample += 1;
                }
            }
        } else {
            _ = stream.outputWithSrc(errors, @src(), "ERROR: Unrecognized WAVE data layout.\n", .{});
        }
    } else {
        _ = stream.outputWithSrc(errors, @src(), "ERROR: Unable to parse WAVE header.\n", .{});
    }

    return result;
}
