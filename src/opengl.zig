const render = @import("render.zig");
const asset = @import("asset.zig");
const math = @import("math.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

const RenderGroup = render.RenderGroup;
const TileSortEntry = render.TileSortEntry;
const RenderEntryHeader = render.RenderEntryHeader;
const RenderEntryClear = render.RenderEntryClear;
const RenderEntryBitmap = render.RenderEntryBitmap;
const RenderEntryRectangle = render.RenderEntryRectangle;
const RenderEntryCoordinateSystem = render.RenderEntryCoordinateSystem;
const RenderEntrySaturation = render.RenderEntrySaturation;
const LoadedBitmap = asset.LoadedBitmap;
const Vector2 = math.Vector2;
const Color = math.Color;
const Rectangle2i = math.Rectangle2i;
const TimedBlock = debug_interface.TimedBlock;

const gl = struct {
    // TODO: How do we import OpenGL on other platforms here?
    usingnamespace @import("win32").graphics.open_gl;
};

pub fn renderGroupToOutput(render_group: *RenderGroup, output_target: *LoadedBitmap, clip_rect: Rectangle2i) void {
    _ = clip_rect;

    var timed_block = TimedBlock.beginFunction(@src(), .RenderToOutput);
    defer timed_block.end();

    gl.glEnable(gl.GL_TEXTURE_2D);
    gl.glViewport(0, 0, output_target.width, output_target.height);

    gl.glMatrixMode(gl.GL_TEXTURE);
    gl.glLoadIdentity();

    gl.glMatrixMode(gl.GL_MODELVIEW);
    gl.glLoadIdentity();

    gl.glMatrixMode(gl.GL_PROJECTION);
    const a = math.safeRatio1(2, @as(f32, @floatFromInt(output_target.width)));
    const b = math.safeRatio1(2, @as(f32, @floatFromInt(output_target.height)));
    const projection: []const f32 = &.{
        a,  0,  0, 0,
        0,  b,  0, 0,
        0,  0,  1, 0,
        -1, -1, 0, 1,
    };
    gl.glLoadMatrixf(@ptrCast(projection));

    const sort_entry_count: u32 = render_group.push_buffer_element_count;
    const sort_entries: [*]TileSortEntry = @ptrFromInt(@intFromPtr(render_group.push_buffer_base) + render_group.sort_entry_at);

    var sort_entry: [*]TileSortEntry = sort_entries;
    var sort_entry_index: u32 = 0;
    while (sort_entry_index < sort_entry_count) : (sort_entry_index += 1) {
        defer sort_entry += 1;

        const header: *RenderEntryHeader = @ptrCast(render_group.push_buffer_base + sort_entry[0].push_buffer_offset);
        const alignment: usize = switch (header.type) {
            .RenderEntryClear => @alignOf(RenderEntryClear),
            .RenderEntryBitmap => @alignOf(RenderEntryBitmap),
            .RenderEntryRectangle => @alignOf(RenderEntryRectangle),
            .RenderEntryCoordinateSystem => @alignOf(RenderEntryCoordinateSystem),
            .RenderEntrySaturation => @alignOf(RenderEntrySaturation),
        };

        const header_address = @intFromPtr(header);
        const data_address = header_address + @sizeOf(RenderEntryHeader);
        const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        const data: *void = @ptrFromInt(aligned_address);

        switch (header.type) {
            .RenderEntryClear => {
                const entry: *RenderEntryClear = @ptrCast(@alignCast(data));
                gl.glClearColor(entry.color.r(), entry.color.g(), entry.color.b(), entry.color.a());
                gl.glClear(gl.GL_COLOR_BUFFER_BIT);
            },
            .RenderEntryBitmap => {
                const entry: *RenderEntryBitmap = @ptrCast(@alignCast(data));
                const x_axis: Vector2 = Vector2.new(1, 0);
                const y_axis: Vector2 = Vector2.new(0, 1);
                const min_position: Vector2 = entry.position;
                const max_position: Vector2 = min_position.plus(
                    x_axis.scaledTo(entry.size.x).plus(y_axis.scaledTo(entry.size.y)),
                );
                openGLRectangle(min_position, max_position, entry.color);
            },
            .RenderEntryRectangle => {
                const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));
                openGLRectangle(entry.position, entry.position.plus(entry.dimension), entry.color);
            },
            .RenderEntrySaturation => {
                // const entry: *RenderEntrySaturation = @ptrCast(@alignCast(data));
            },
            .RenderEntryCoordinateSystem => {
                // const entry: *RenderEntryCoordinateSystem = @ptrCast(@alignCast(data));
            },
        }
    }
}

fn openGLRectangle(min_position: Vector2, max_position: Vector2, color: Color) void {
    gl.glBegin(gl.GL_TRIANGLES);
    {
        gl.glColor4f(color.r(), color.g(), color.b(), color.a());

        // Lower triangle.
        gl.glTexCoord2f(0, 0);
        gl.glVertex2f(min_position.x(), min_position.y());
        gl.glTexCoord2f(1, 0);
        gl.glVertex2f(max_position.x(), min_position.y());
        gl.glTexCoord2f(1, 1);
        gl.glVertex2f(max_position.x(), max_position.y());

        // Upper triangle
        gl.glTexCoord2f(0, 0);
        gl.glVertex2f(min_position.x(), min_position.y());
        gl.glTexCoord2f(1, 1);
        gl.glVertex2f(max_position.x(), max_position.y());
        gl.glTexCoord2f(0, 1);
        gl.glVertex2f(min_position.x(), max_position.y());
    }
    gl.glEnd();
}
