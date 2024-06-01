const PI32: f32 = 3.1415926535897932384626433;
const TAU32: f32 = PI32 * 2.0;
const MIDDLE_C: u32 = 261;
const TREBLE_C: u32 = 523;

pub const MAX_CONTROLLER_COUNT: u8 = 4;

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

pub const ControllerInputs = struct {
    controllers: [MAX_CONTROLLER_COUNT]ControllerInput = [MAX_CONTROLLER_COUNT]ControllerInput{ undefined, undefined, undefined, undefined },
};

pub const ControllerButtonState = struct {
    ended_down: bool = false,
    half_transitions: u8 = 0,
};

pub const ControllerInput = struct {
    is_analog: bool = false,

    start_x: f32 = 0,
    start_y: f32 = 0,

    min_x: f32 = 0,
    min_y: f32 = 0,

    max_x: f32 = 0,
    max_y: f32 = 0,

    end_x: f32 = 0,
    end_y: f32 = 0,

    up_button: ControllerButtonState,
    down_button: ControllerButtonState,
    left_button: ControllerButtonState,
    right_button: ControllerButtonState,
    left_shoulder_button: ControllerButtonState,
    right_shoulder_button: ControllerButtonState,
};

var x_offset: i32 = 0;
var y_offset: i32 = 0;

pub fn updateAndRender(
    input: ControllerInputs,
    buffer: *OffscreenBuffer,
    sound_buffer: *SoundOutputBuffer,
) void {
    const input0 = &input.controllers[0];
    if (input0.is_analog) {
        x_offset += @intFromFloat(4.0 * input0.end_x);
        tone_hz = @intCast(@as(i32, MIDDLE_C) + @as(i32, @intFromFloat(128.0 * input0.end_y)));
    }

    if (input0.down_button.ended_down) {
        y_offset += 1;
    }

    outputSound(sound_buffer);
    renderWeirdGradient(buffer);
}

fn renderWeirdGradient(buffer: *OffscreenBuffer) void {
    var row: [*]u8 = @ptrCast(buffer.memory);
    var y: u32 = 0;
    var wrapped_x_offset: u32 = 0;
    var wrapped_y_offset: u32 = 0;

    // Wrap the x offset.
    if (x_offset < 0) {
        wrapped_x_offset -%= @as(u32, @intCast(@abs(x_offset)));
    } else {
        wrapped_x_offset +%= @as(u32, @intCast(x_offset));
    }

    // Wrap the y offset.
    if (y_offset < 0) {
        wrapped_y_offset -%= @as(u32, @intCast(@abs(y_offset)));
    } else {
        wrapped_y_offset +%= @as(u32, @intCast(y_offset));
    }

    while (y < buffer.height) {
        var x: u32 = 0;
        var pixel: [*]u32 = @ptrCast(@alignCast(row));

        while (x < buffer.width) {
            const blue: u32 = @as(u8, @truncate(x +% wrapped_x_offset));
            const green: u32 = @as(u8, @truncate(y +% wrapped_y_offset));

            pixel[0] = (green << 8) | blue;

            pixel += 1;
            x += 1;
        }

        row += buffer.pitch;
        y += 1;
    }
}

var t_sine: f32 = 0.0;
var tone_hz: u32 = MIDDLE_C;

fn outputSound(sound_buffer: *SoundOutputBuffer) void {
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
