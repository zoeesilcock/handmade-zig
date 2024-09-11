const shared = @import("shared.zig");
const asset = @import("asset.zig");
const math = @import("math.zig");
const intrinsics = @import("intrinsics.zig");
const std = @import("std");

// Types.
const State = shared.State;
const MemoryArena = shared.MemoryArena;
const SoundId = asset.SoundId;
const SoundOutputBuffer = shared.SoundOutputBuffer;
const Assets = asset.Assets;
const Vector2 = math.Vector2;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;

pub const PlayingSound = struct {
    id: SoundId,

    current_volume: Vector2,
    current_volume_velocity: Vector2,
    target_volume: Vector2,

    sample_velocity: f32,

    samples_played: f32,
    next: ?*PlayingSound,
};

pub const AudioState = struct {
    permanent_arena: *MemoryArena,
    first_playing_sound: ?*PlayingSound = null,
    first_free_playing_sound: ?*PlayingSound = null,
    master_volume: Vector2,

    pub fn initialize(self: *AudioState, arena: *MemoryArena) void {
        self.permanent_arena = arena;
        self.master_volume = Vector2.one();
    }

    pub fn playSound(self: *AudioState, opt_sound_id: ?SoundId) ?*PlayingSound {
        var result: ?*PlayingSound = null;

        if (opt_sound_id) |sound_id| {
            if (self.first_free_playing_sound == null) {
                self.first_free_playing_sound = self.permanent_arena.pushStruct(PlayingSound);
                self.first_free_playing_sound.?.next = null;
            }

            if (self.first_free_playing_sound) |first_free_sound| {
                const playing_sound = first_free_sound;
                self.first_free_playing_sound = self.first_free_playing_sound.?.next;

                playing_sound.samples_played = 0;
                playing_sound.current_volume = Vector2.one();
                playing_sound.current_volume_velocity = Vector2.zero();
                playing_sound.target_volume = Vector2.one();
                playing_sound.id = sound_id;
                playing_sound.sample_velocity = 1;

                playing_sound.next = self.first_playing_sound;
                self.first_playing_sound = playing_sound;

                result = playing_sound;
            }
        }

        return result;
    }

    pub fn changeVolume(
        self: *AudioState,
        sound: *PlayingSound,
        fade_duration_in_seconds: f32,
        volume: Vector2,
    ) void {
        _ = self;

        if (fade_duration_in_seconds <= 0) {
            sound.target_volume = volume;
            sound.current_volume = volume;
        } else {
            const one_over_fade = 1.0 / fade_duration_in_seconds;

            sound.target_volume = volume;
            sound.current_volume_velocity = sound.target_volume.minus(sound.current_volume).scaledTo(one_over_fade);
        }
    }

    pub fn changePitch(
        self: *AudioState,
        sound: *PlayingSound,
        sample_velocity: f32,
    ) void {
        _ = self;
        sound.sample_velocity = sample_velocity;
    }

    pub fn outputPlayingSounds(
        self: *AudioState,
        sound_buffer: *SoundOutputBuffer,
        assets: *Assets,
        temp_arena: *MemoryArena,
    ) void {
        const mixer_memory = temp_arena.beginTemporaryMemory();
        defer temp_arena.endTemporaryMemory(mixer_memory);

        std.debug.assert((sound_buffer.sample_count & 3) == 0);
        const chunk_count = sound_buffer.sample_count / 4;

        const real_channel0: [*]Vec4f = temp_arena.pushArrayAligned(chunk_count, Vec4f, 16);
        const real_channel1: [*]Vec4f = temp_arena.pushArrayAligned(chunk_count, Vec4f, 16);

        const seconds_per_sample = 1.0 / @as(f32, @floatFromInt(sound_buffer.samples_per_second));
        const output_channel_count = 2;
        const zero: Vec4f = @splat(0);
        const one: Vec4f = @splat(1);

        // Clear out the mixer channels.
        {
            var dest0: [*]Vec4f = real_channel0;
            var dest1: [*]Vec4f = real_channel1;
            var sample_index: u32 = 0;
            while (sample_index < chunk_count) : (sample_index += 1) {
                dest0[0] = zero;
                dest0 += 1;
                dest1[0] = zero;
                dest1 += 1;
            }
        }

        // Sum all sounds.
        var opt_playing_sound = &self.first_playing_sound;
        while (opt_playing_sound.* != null) {
            if (opt_playing_sound.*) |playing_sound| {
                var sound_finished = false;

                var total_chunks_to_mix: i32 = @intCast(chunk_count);
                var dest0 = real_channel0;
                var dest1 = real_channel1;

                while (total_chunks_to_mix > 0 and !sound_finished) {
                    const opt_loaded_sound = assets.getSound(playing_sound.id);
                    if (opt_loaded_sound) |loaded_sound| {
                        const info = assets.getSoundInfo(playing_sound.id);
                        assets.prefetchSound(info.next_id_to_play);

                        const volume = playing_sound.current_volume;
                        const volume_velocity = playing_sound.current_volume_velocity.scaledTo(seconds_per_sample);
                        const volume_velocity_chunk = volume_velocity.scaledTo(4.0);
                        const sample_velocity: f32 = playing_sound.sample_velocity * 1.9;
                        const sample_velocity_chunk: f32 = sample_velocity * 4.0;

                        // Channel 0.
                        const master_volume0: Vec4f = @splat(self.master_volume.values[0]);
                        var volume0 = Vec4f{
                            volume.values[0] + 0 * volume_velocity.values[0],
                            volume.values[0] + 1 * volume_velocity.values[0],
                            volume.values[0] + 2 * volume_velocity.values[0],
                            volume.values[0] + 3 * volume_velocity.values[0],
                        };
                        // const volume_velocity0: Vec4f = @splat(volume_velocity.values[0]);
                        const volume_velocity_chunk0: Vec4f = @splat(volume_velocity_chunk.values[0]);

                        // Channel 1.
                        const master_volume1: Vec4f = @splat(self.master_volume.values[1]);
                        var volume1 = Vec4f{
                            volume.values[1] + 0 * volume_velocity.values[1],
                            volume.values[1] + 1 * volume_velocity.values[1],
                            volume.values[1] + 2 * volume_velocity.values[1],
                            volume.values[1] + 3 * volume_velocity.values[1],
                        };
                        // const volume_velocity1: Vec4f = @splat(volume_velocity.values[1]);
                        const volume_velocity_chunk1: Vec4f = @splat(volume_velocity_chunk.values[1]);

                        std.debug.assert(playing_sound.samples_played >= 0);

                        var chunks_to_mix = total_chunks_to_mix;
                        const chunks_remaining: i32 =
                            @as(i32, @intCast(loaded_sound.sample_count)) -
                            intrinsics.roundReal32ToInt32(playing_sound.samples_played);
                        const float_chunks_remaining_in_sound =
                            @as(f32, @floatFromInt(chunks_remaining)) / sample_velocity_chunk;
                        const chunks_remaining_in_sound: i32 =
                            intrinsics.roundReal32ToInt32(float_chunks_remaining_in_sound);

                        if (chunks_to_mix > chunks_remaining_in_sound) {
                            chunks_to_mix = chunks_remaining_in_sound;
                        }

                        var volume_ends_at: [output_channel_count]u32 = [1]u32{0} ** output_channel_count;

                        // Limit the output to the end of the current volume fade.
                        {
                            var channel_index: u32 = 0;
                            while (channel_index < output_channel_count) : (channel_index += 1) {
                                if (volume_velocity_chunk.values[channel_index] != 0) {
                                    const delta_volume: f32 = playing_sound.target_volume.values[channel_index] -
                                        volume.values[channel_index];

                                    if (delta_volume != 0) {
                                        const volume_chunk_count: u32 =
                                            @intFromFloat((delta_volume / volume_velocity_chunk.values[channel_index]) + 0.5);
                                        if (chunks_to_mix > volume_chunk_count) {
                                            chunks_to_mix = @intCast(volume_chunk_count);
                                            volume_ends_at[channel_index] = volume_chunk_count;
                                        }
                                    }
                                }
                            }
                        }

                        // TODO: Handle stereo.
                        const begin_sample_position: f32 = playing_sound.samples_played;
                        const end_sample_position: f32 = begin_sample_position + (@as(f32, @floatFromInt(chunks_to_mix)) * sample_velocity_chunk);
                        const loop_index_c = (end_sample_position - begin_sample_position) / @as(f32, @floatFromInt(chunks_to_mix));
                        var loop_index: u32 = 0;
                        while (loop_index < chunks_to_mix) : (loop_index += 1) {
                            const sample_position: f32 = begin_sample_position + loop_index_c * @as(f32, @floatFromInt(loop_index));
                            var sample_value: Vec4f = zero;

                            if (true) {
                                // With linear interpolation.
                                const sample_pos = Vec4f{
                                    sample_position + 0 * sample_velocity,
                                    sample_position + 1 * sample_velocity,
                                    sample_position + 2 * sample_velocity,
                                    sample_position + 3 * sample_velocity,
                                };
                                const sample_index: Vec4i = @intFromFloat(sample_pos);
                                const fraction: Vec4f = sample_pos - @as(Vec4f, @floatFromInt(sample_index));
                                const sample_value_f = Vec4f{
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[0])]),
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[1])]),
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[2])]),
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[3])]),
                                };
                                const sample_value_c = Vec4f{
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[0] + 1)]),
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[1] + 1)]),
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[2] + 1)]),
                                    @floatFromInt(loaded_sound.samples[0].?[@intCast(sample_index[3] + 1)]),
                                };
                                sample_value = ((one - fraction) * sample_value_f) + (fraction * sample_value_c);
                            } else {
                                // Without linear interpolation.
                                sample_value = Vec4f{
                                    @floatFromInt(loaded_sound.samples[0].?[intrinsics.roundReal32ToUInt32(sample_position + 0 * sample_velocity)]),
                                    @floatFromInt(loaded_sound.samples[0].?[intrinsics.roundReal32ToUInt32(sample_position + 1 * sample_velocity)]),
                                    @floatFromInt(loaded_sound.samples[0].?[intrinsics.roundReal32ToUInt32(sample_position + 2 * sample_velocity)]),
                                    @floatFromInt(loaded_sound.samples[0].?[intrinsics.roundReal32ToUInt32(sample_position + 3 * sample_velocity)]),
                                };
                            }

                            var d0: [*]Vec4f = @ptrCast(&dest0[0]);
                            var d1: [*]Vec4f = @ptrCast(&dest1[0]);

                            d0[0] += (master_volume0 * volume0) * sample_value;
                            d1[0] += (master_volume1 * volume1) * sample_value;

                            dest0[0] = d0[0];
                            dest1[0] = d1[0];

                            dest0 += 1;
                            dest1 += 1;

                            // Update volume.
                            volume0 += volume_velocity_chunk0;
                            volume1 += volume_velocity_chunk1;
                        }

                        playing_sound.current_volume.values[0] = volume0[0];
                        playing_sound.current_volume.values[1] = volume1[0];

                        // Stop any volume fades that ended.
                        {
                            var channel_index: u32 = 0;
                            while (channel_index < output_channel_count) : (channel_index += 1) {
                                if (chunks_to_mix == volume_ends_at[channel_index]) {
                                    playing_sound.current_volume.values[channel_index] =
                                        playing_sound.target_volume.values[channel_index];
                                    playing_sound.current_volume_velocity.values[channel_index] = 0;
                                }
                            }
                        }

                        playing_sound.samples_played = end_sample_position;
                        std.debug.assert(total_chunks_to_mix >= chunks_to_mix);
                        total_chunks_to_mix -= chunks_to_mix;

                        if (chunks_to_mix == chunks_remaining_in_sound) {
                            if (info.next_id_to_play) |next_id| {
                                if (next_id.isValid()) {
                                    playing_sound.id = next_id;

                                    // TODO: This assertion fires, but everything seems to work without it.
                                    // std.debug.assert(playing_sound.samples_played >= @as(f32, @floatFromInt(loaded_sound.sample_count)));

                                    playing_sound.samples_played -= @floatFromInt(loaded_sound.sample_count);

                                    if (playing_sound.samples_played < 0) {
                                        playing_sound.samples_played = 0;
                                    }
                                } else {
                                    sound_finished = true;
                                }
                            } else {
                                sound_finished = true;
                            }
                        }
                    } else {
                        assets.loadSound(playing_sound.id);
                        break;
                    }
                }

                if (sound_finished) {
                    opt_playing_sound.* = playing_sound.next;
                    playing_sound.next = self.first_free_playing_sound;
                    self.first_free_playing_sound = playing_sound;
                } else {
                    opt_playing_sound = &opt_playing_sound.*.?.next;
                }
            }
        }

        // Convert back to 16-bit.
        {
            const source0: [*]Vec4f = real_channel0;
            const source1: [*]Vec4f = real_channel1;
            var sample_out: [*]@Vector(8, i16) = @ptrCast(@alignCast(sound_buffer.samples));

            var sample_index: u32 = 0;
            while (sample_index < chunk_count) : (sample_index += 1) {
                const l: Vec4i = @intFromFloat(source0[sample_index]);
                const r: Vec4i = @intFromFloat(source1[sample_index]);
                const lr0: Vec4i = @shuffle(i32, l, r, Vec4i{0, -1, 1, -2});
                const lr1: Vec4i = @shuffle(i32, l, r, Vec4i{2, -3, 3, -4});
                const s01: @Vector(8, i16) = @truncate(std.simd.join(lr0, lr1));

                sample_out[sample_index] = s01;
            }
        }
    }
};

pub fn outputSineWave(sound_buffer: *SoundOutputBuffer, tone_hz: u32, state: *State) void {
    const tone_volume = 3000;
    const wave_period = @divFloor(sound_buffer.samples_per_second, tone_hz);

    var sample_out: [*]i16 = sound_buffer.samples;
    var sample_index: u32 = 0;
    while (sample_index < sound_buffer.sample_count) : (sample_index += 1) {
        var sample_value: i16 = 0;
        const sine_value: f32 = @sin(state.t_sine);
        sample_value = @intFromFloat(sine_value * @as(f32, @floatFromInt(tone_volume)));

        sample_out += 1;
        sample_out[0] = sample_value;
        sample_out += 1;
        sample_out[0] = sample_value;

        state.t_sine += shared.TAU32 / @as(f32, @floatFromInt(wave_period));
        if (state.t_sine > shared.TAU32) {
            state.t_sine -= shared.TAU32;
        }
    }
}
