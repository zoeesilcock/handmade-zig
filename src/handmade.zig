pub const GameOffscreenBuffer = struct {
    memory: ?*anyopaque = undefined,
    width: i32 = 0,
    height: i32 = 0,
    pitch: usize = 0,
};

pub fn gameUpdateAndRender(buffer: *GameOffscreenBuffer, x_offset: u32, y_offset: u32) void {
    renderWeirdGradient(buffer, x_offset, y_offset);
}

fn renderWeirdGradient(buffer: *GameOffscreenBuffer, x_offset: u32, y_offset: u32) void {
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

