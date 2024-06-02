const PI32: f32 = 3.1415926535897932384626433;
const TAU32: f32 = PI32 * 2.0;
const MIDDLE_C: u32 = 261;
const TREBLE_C: u32 = 523;

pub const MAX_CONTROLLER_COUNT: u8 = 4;

const std = @import("std");

pub inline fn kilobytes(value: u32) u64 {
    return value * 1024;
}

pub inline fn megabytes(value: u32) u64 {
    return kilobytes(value) * 1024;
}

pub inline fn gigabytes(value: u32) u64 {
    return megabytes(value) * 1024;
}

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

pub const Memory = struct {
    is_initialized: bool,
    permanent_storage_size: u64,
    permanent_storage: *anyopaque,
    transient_storage_size: u64,
    transient_storage: *anyopaque,
};

const State = struct {
    x_offset: i32 = 0,
    y_offset: i32 = 0,
    t_sine: f32 = 0.0,
    tone_hz: u32 = MIDDLE_C,
};

pub fn updateAndRender(
    memory: *Memory,
    input: ControllerInputs,
    buffer: *OffscreenBuffer,
    sound_buffer: *SoundOutputBuffer,
) void {
    std.debug.assert(@sizeOf(State) <= memory.permanent_storage_size);

    var state: *State = @ptrCast(@alignCast(memory.permanent_storage));

    if (!memory.is_initialized) {
        state.* = State{};
        memory.is_initialized = true;
    }

    const input0 = &input.controllers[0];
    if (input0.is_analog) {
        state.x_offset += @intFromFloat(4.0 * input0.end_x);
        state.tone_hz = @intCast(@as(i32, MIDDLE_C) + @as(i32, @intFromFloat(128.0 * input0.end_y)));
    }

    if (input0.down_button.ended_down) {
        state.y_offset += 1;
    }

    renderWeirdGradient(buffer, state.x_offset, state.y_offset);
    outputSound(sound_buffer, state.tone_hz, &state.t_sine);
}

fn renderWeirdGradient(buffer: *OffscreenBuffer, x_offset: i32, y_offset: i32) void {
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

fn outputSound(sound_buffer: *SoundOutputBuffer, tone_hz: u32, t_sine: *f32) void {
    const tone_volume = 3000;
    const wave_period = @divFloor(sound_buffer.samples_per_second, tone_hz);

    var sample_out: [*]i16 = sound_buffer.samples;
    var sample_index: u32 = 0;
    while (sample_index < sound_buffer.sample_count) {
        const sine_value: f32 = @sin(t_sine.*);
        const sample_value: i16 = @intFromFloat(sine_value * @as(f32, @floatFromInt(tone_volume)));

        sample_out += 1;
        sample_out[0] = sample_value;
        sample_out += 1;
        sample_out[0] = sample_value;

        sample_index += 1;
        t_sine.* += TAU32 / @as(f32, @floatFromInt(wave_period));
    }
}
