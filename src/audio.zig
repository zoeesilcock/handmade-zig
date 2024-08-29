const shared = @import("shared.zig");
const asset = @import("asset.zig");
const math = @import("math.zig");
const std = @import("std");

// Types.
const State = shared.State;
const MemoryArena = shared.MemoryArena;
const SoundId = asset.SoundId;
const SoundOutputBuffer = shared.SoundOutputBuffer;
const Assets = asset.Assets;
const Vector2 = math.Vector2;

pub const PlayingSound = struct {
    id: SoundId,

    current_volume: Vector2,
    current_volume_velocity: Vector2,
    target_volume: Vector2,

    samples_played: i32,
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

    pub fn outputPlayingSounds(
        self: *AudioState,
        sound_buffer: *SoundOutputBuffer,
        assets: *Assets,
        temp_arena: *MemoryArena,
    ) void {
        const mixer_memory = temp_arena.beginTemporaryMemory();
        defer temp_arena.endTemporaryMemory(mixer_memory);

        const real_channel0: [*]f32 = temp_arena.pushArray(sound_buffer.sample_count, f32);
        const real_channel1: [*]f32 = temp_arena.pushArray(sound_buffer.sample_count, f32);

        const seconds_per_sample = 1.0 / @as(f32, @floatFromInt(sound_buffer.samples_per_second));
        const output_channel_count = 2;

        // Clear out the mixer channels.
        {
            var dest0: [*]f32 = real_channel0;
            var dest1: [*]f32 = real_channel1;
            var sample_index: u32 = 0;
            while (sample_index < sound_buffer.sample_count) : (sample_index += 1) {
                dest0[0] = 0;
                dest0 += 1;
                dest1[0] = 0;
                dest1 += 1;
            }
        }

        // Sum all sounds.
        var opt_playing_sound = &self.first_playing_sound;
        while (opt_playing_sound.* != null) {
            if (opt_playing_sound.*) |playing_sound| {
                var sound_finished = false;

                var total_samples_to_mix: i32 = @intCast(sound_buffer.sample_count);
                var dest0: [*]f32 = real_channel0;
                var dest1: [*]f32 = real_channel1;

                while (total_samples_to_mix > 0 and !sound_finished) {
                    const opt_loaded_sound = assets.getSound(playing_sound.id);
                    if (opt_loaded_sound) |loaded_sound| {
                        const info = assets.getSoundInfo(playing_sound.id);
                        assets.prefetchSound(info.next_id_to_play);

                        var volume = playing_sound.current_volume;
                        const volume_velocity = playing_sound.current_volume_velocity.scaledTo(seconds_per_sample);

                        std.debug.assert(playing_sound.samples_played >= 0);

                        var samples_to_mix = total_samples_to_mix;
                        const samples_remaining_in_sound: i32 =
                            @as(i32, @intCast(loaded_sound.sample_count)) - playing_sound.samples_played;

                        if (samples_to_mix > samples_remaining_in_sound) {
                            samples_to_mix = samples_remaining_in_sound;
                        }

                        var volume_ended: [output_channel_count]bool = [1]bool{false} ** output_channel_count;

                        // Limit the output to the end of the current volume fade.
                        {
                            var channel_index: u32 = 0;
                            while (channel_index < output_channel_count) : (channel_index += 1) {
                                if (volume_velocity.values[channel_index] != 0) {
                                    const delta_volume: f32 = playing_sound.target_volume.values[channel_index] -
                                        volume.values[channel_index];

                                    if (delta_volume != 0) {
                                        const volume_sample_count: u32 =
                                            @intFromFloat((delta_volume / volume_velocity.values[channel_index]) + 0.5);
                                        if (samples_to_mix > volume_sample_count) {
                                            samples_to_mix = @intCast(volume_sample_count);
                                            volume_ended[channel_index] = true;
                                        }
                                    }
                                }
                            }
                        }

                        // TODO: Handle stereo.
                        var sample_index: u32 = @intCast(playing_sound.samples_played);
                        const end_sample_index = playing_sound.samples_played + samples_to_mix;
                        while (sample_index < end_sample_index) : (sample_index += 1) {
                            const sample_value = loaded_sound.samples[0].?[sample_index];

                            dest0[0] += self.master_volume.values[0] * volume.values[0] * @as(f32, @floatFromInt(sample_value));
                            dest0 += 1;
                            dest1[0] += self.master_volume.values[1] * volume.values[1] * @as(f32, @floatFromInt(sample_value));
                            dest1 += 1;

                            // Update volume.
                            volume = volume.plus(volume_velocity);
                        }

                        // Stop any volume fades that ended.
                        {
                            var channel_index: u32 = 0;
                            while (channel_index < output_channel_count) : (channel_index += 1) {
                                if (volume_ended[channel_index]) {
                                    playing_sound.current_volume.values[channel_index] =
                                        playing_sound.target_volume.values[channel_index];
                                    playing_sound.current_volume_velocity.values[channel_index] = 0;
                                }
                            }
                        }

                        playing_sound.current_volume = volume;

                        std.debug.assert(total_samples_to_mix >= samples_to_mix);
                        playing_sound.samples_played += samples_to_mix;
                        total_samples_to_mix -= samples_to_mix;

                        if (playing_sound.samples_played == loaded_sound.sample_count) {
                            if (info.next_id_to_play) |next_id| {
                                if (next_id.isValid()) {
                                    playing_sound.id = next_id;
                                    playing_sound.samples_played = 0;
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
            var source0: [*]f32 = real_channel0;
            var source1: [*]f32 = real_channel1;

            var sample_out: [*]i16 = sound_buffer.samples;
            var sample_index: u32 = 0;
            while (sample_index < sound_buffer.sample_count) : (sample_index += 1) {
                sample_out[0] = @intFromFloat(source0[0] + 0.5);
                sample_out += 1;
                source0 += 1;

                sample_out[0] = @intFromFloat(source1[0] + 0.5);
                sample_out += 1;
                source1 += 1;
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
