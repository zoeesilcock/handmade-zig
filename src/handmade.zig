const shared = @import("shared.zig");
const std = @import("std");

pub export fn updateAndRender(
    platform: shared.Platform,
    memory: *shared.Memory,
    input: shared.ControllerInputs,
    buffer: *shared.OffscreenBuffer,
) void {
    std.debug.assert(@sizeOf(shared.State) <= memory.permanent_storage_size);

    var state: *shared.State = @ptrCast(@alignCast(memory.permanent_storage));

    if (!memory.is_initialized) {
        state.* = shared.State{};
        memory.is_initialized = true;

        const file_name = "build.zig";
        const bitmap_memory = platform.debugReadEntireFile(file_name);
        if (bitmap_memory.contents != undefined) {
            // _ = platform.debugWriteEntireFile("test_out_file.txt", bitmap_memory.content_size, bitmap_memory.contents);
            platform.debugFreeFileMemory(bitmap_memory.contents);
        }
    }

    for (&input.controllers) |controller| {
        if (controller.is_analog) {
            state.x_offset += @intFromFloat(4.0 * controller.stick_average_x);
            state.y_offset -= @intFromFloat(4.0 * controller.stick_average_y);
            state.tone_hz = @intCast(@as(i32, shared.MIDDLE_C) + @as(i32, @intFromFloat(128.0 * controller.stick_average_y)));
        } else {
            if (controller.move_up.ended_down) {
                state.y_offset -= 1;
            }
            if (controller.move_down.ended_down) {
                state.y_offset += 1;
            }
            if (controller.move_left.ended_down) {
                state.x_offset -= 1;
            }
            if (controller.move_right.ended_down) {
                state.x_offset += 1;
            }
        }

        if (controller.action_down.ended_down) {
            state.y_offset += 1;
        }
    }

    renderWeirdGradient(buffer, state.x_offset, state.y_offset);
}

pub export fn getSoundSamples(
    memory: *shared.Memory,
    sound_buffer: *shared.SoundOutputBuffer,
) void {
    var state: *shared.State = @ptrCast(@alignCast(memory.permanent_storage));
    outputSound(sound_buffer, state.tone_hz, &state.t_sine);
}

fn renderWeirdGradient(buffer: *shared.OffscreenBuffer, x_offset: i32, y_offset: i32) void {
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

fn outputSound(sound_buffer: *shared.SoundOutputBuffer, tone_hz: u32, t_sine: *f32) void {
    const tone_volume = 3000;
    const wave_period = @divFloor(sound_buffer.samples_per_second, tone_hz);

    var sample_out: [*]i16 = sound_buffer.samples;
    var sample_index: u32 = 0;
    while (sample_index < sound_buffer.sample_count) {
        var sample_value: i16 = 0;

        if (!shared.DEBUG) {
            const sine_value: f32 = @sin(t_sine.*);
            sample_value = @intFromFloat(sine_value * @as(f32, @floatFromInt(tone_volume)));
        }

        sample_out += 1;
        sample_out[0] = sample_value;
        sample_out += 1;
        sample_out[0] = sample_value;

        sample_index += 1;
        t_sine.* += shared.TAU32 / @as(f32, @floatFromInt(wave_period));
        if (t_sine.* > shared.TAU32) {
            t_sine.* -= shared.TAU32;
        }
    }
}
