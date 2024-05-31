const PI32: f32 = 3.1415926535897932384626433;
const TAU32: f32 = PI32 * 2.0;

pub const OffscreenBuffer = struct {
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
};

pub const SoundOutputBuffer = struct {
    samples: [*]i16,
    samples_per_second: u32,
    sample_count: u32,
};

pub fn updateAndRender(
    buffer: *OffscreenBuffer,
    x_offset: u32,
    y_offset: u32,
    sound_buffer: *SoundOutputBuffer,
    tone_hz: u32,
) void {
    outputSound(sound_buffer, tone_hz);
    renderWeirdGradient(buffer, x_offset, y_offset);
}

fn renderWeirdGradient(buffer: *OffscreenBuffer, x_offset: u32, y_offset: u32) void {
    var row: [*]u8 = @ptrCast(buffer.memory);
    var y: u32 = 0;

    while (y < buffer.height) {
        var x: u32 = 0;
        var pixel: [*]align(4) u32 = @ptrCast(@alignCast(row));

        while (x < buffer.width) {
            const blue: u32 = @as(u8, @truncate(x +% x_offset));
            const green: u32 = @as(u8, @truncate(y +% y_offset));

            pixel[0] = (green << 8) | blue;

            pixel += 1;
            x += 1;
        }

        row += buffer.pitch;
        y += 1;
    }
}

var t_sine: f32 = 0.0;
fn outputSound(sound_buffer: *SoundOutputBuffer, tone_hz: u32) void {
    const tone_volume = 3000;
    const wave_period = @divFloor(sound_buffer.samples_per_second, tone_hz);

    var sample_out: [*]i16 = sound_buffer.samples;
    var sample_index: u32 = 0;
    while (sample_index < sound_buffer.sample_count) {
        const sine_value: f32 = @sin(t_sine);
        const sample_value: i16 = @intFromFloat(sine_value * @as(f32, @floatFromInt(tone_volume)));

        sample_out += 1;
        sample_out[0] = sample_value;
        sample_out += 1;
        sample_out[0] = sample_value;

        sample_index += 1;
        t_sine += TAU32 / @as(f32, @floatFromInt(wave_period));
    }
}
