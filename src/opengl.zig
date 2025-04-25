const shared = @import("shared.zig");
const rendergroup = @import("rendergroup.zig");
const render = @import("render.zig");
const asset = @import("asset.zig");
const math = @import("math.zig");
const sort = @import("sort.zig");
const debug_interface = @import("debug_interface.zig");
const platform = @import("win32_handmade.zig");
const std = @import("std");

pub const GL_FRAMEBUFFER_SRGB = 0x8DB9;
pub const GL_SRGB8_ALPHA8 = 0x8C43;
pub const GL_SHADING_LANGUAGE_VERSION = 0x8B8C;

// Windows specific.
pub const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
pub const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
pub const WGL_CONTEXT_LAYER_PLANE_ARB = 0x2093;
pub const WGL_CONTEXT_FLAGS_ARB = 0x2094;
pub const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;

pub const WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001;
pub const WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;

pub const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
pub const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;

pub const ERROR_INVALID_VERSION_ARB = 0x2095;
pub const ERROR_INVALID_PROFILE_ARB = 0x2096;

pub const WGL_DRAW_TO_WINDOW_ARB = 0x2001;
pub const WGL_ACCELERATION_ARB = 0x2003;
pub const WGL_FULL_ACCELERATION_ARB = 0x2027;
pub const WGL_SUPPORT_OPENGL_ARB = 0x2010;
pub const WGL_DOUBLE_BUFFER_ARB = 0x2011;
pub const WGL_PIXEL_TYPE_ARB = 0x2013;
pub const WGL_TYPE_RGBA_ARB = 0x202B;
pub const WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB = 0x20A9;

// Build options.
const INTERNAL = shared.INTERNAL;

const RenderCommands = shared.RenderCommands;
const GameRenderPrep = shared.GameRenderPrep;
const RenderGroup = rendergroup.RenderGroup;
const RenderEntryHeader = rendergroup.RenderEntryHeader;
const RenderEntryClear = rendergroup.RenderEntryClear;
const RenderEntryClipRect = rendergroup.RenderEntryClipRect;
const RenderEntryBitmap = rendergroup.RenderEntryBitmap;
const RenderEntryRectangle = rendergroup.RenderEntryRectangle;
const RenderEntryCoordinateSystem = rendergroup.RenderEntryCoordinateSystem;
const RenderEntrySaturation = rendergroup.RenderEntrySaturation;
const LoadedBitmap = asset.LoadedBitmap;
const Vector2 = math.Vector2;
const Color = math.Color;
const Rectangle2 = math.Rectangle2;
const Rectangle2i = math.Rectangle2i;
const TimedBlock = debug_interface.TimedBlock;
const TextureOp = render.TextureOp;
const SortSpriteBound = render.SortSpriteBound;
const SpriteFlag = render.SpriteFlag;
const SpriteEdge = render.SpriteEdge;

const debug_color_table = shared.debug_color_table;
var global_config = &@import("config.zig").global_config;

pub const gl = struct {
    // TODO: How do we import OpenGL on other platforms here?
    usingnamespace @import("win32").graphics.open_gl;
};

pub var default_internal_texture_format: i32 = 0;

pub const Info = struct {
    is_modern_context: bool,
    vendor: ?*const u8,
    renderer: ?*const u8,
    version: ?*const u8,
    shader_language_version: ?*const u8 = undefined,
    extensions: ?*const u8,

    gl_ext_texture_srgb: bool = false,
    gl_ext_framebuffer_srgb: bool = false,

    pub fn get(is_modern_context: bool) Info {
        var result: Info = .{
            .is_modern_context = is_modern_context,
            .vendor = gl.glGetString(gl.GL_VENDOR),
            .renderer = gl.glGetString(gl.GL_RENDERER),
            .version = gl.glGetString(gl.GL_VERSION),
            .extensions = gl.glGetString(gl.GL_EXTENSIONS),
        };

        if (is_modern_context) {
            result.shader_language_version = gl.glGetString(GL_SHADING_LANGUAGE_VERSION);
        } else {
            result.shader_language_version = @ptrCast("(none)");
        }

        if (result.extensions) |extensions| {
            var at: [*]const u8 = @ptrCast(extensions);
            while (at[0] != 0) {
                while (shared.isWhitespace(at[0])) {
                    at += 1;
                }
                var end = at;
                while (end[0] != 0 and !shared.isWhitespace(end[0])) {
                    end += 1;
                }

                const count = @intFromPtr(end) - @intFromPtr(at);

                if (shared.stringsWithOneLengthAreEqual(at, count, "GL_EXT_texture_sRGB")) {
                    result.gl_ext_texture_srgb = true;
                } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_EXT_framebuffer_sRGB")) {
                    result.gl_ext_framebuffer_srgb = true;
                } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_ARB_framebuffer_sRGB")) {
                    result.gl_ext_framebuffer_srgb = true;
                }

                at = end;
            }
        }

        return result;
    }
};

pub fn init(is_modern_context: bool, framebuffer_supports_sRGB: bool) void {
    const info = Info.get(is_modern_context);

    default_internal_texture_format = gl.GL_RGBA8;

    if (framebuffer_supports_sRGB and info.gl_ext_texture_srgb and info.gl_ext_framebuffer_srgb) {
        default_internal_texture_format = GL_SRGB8_ALPHA8;
        gl.glEnable(GL_FRAMEBUFFER_SRGB);
    }
}

pub fn renderCommands(
    commands: *RenderCommands,
    prep: *GameRenderPrep,
    window_width: i32,
    window_height: i32,
) callconv(.C) void {
    _ = window_width;
    _ = window_height;

    // TimedBlock.beginFunction(@src(), .RenderCommandsToOpenGL);
    // defer TimedBlock.endFunction(@src(), .RenderCommandsToOpenGL);

    gl.glDisable(gl.GL_SCISSOR_TEST);
    gl.glClearColor(commands.clear_color.r(), commands.clear_color.g(), commands.clear_color.b(), commands.clear_color.a());
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl.glViewport(commands.offset_x, commands.offset_y, @intCast(commands.width), @intCast(commands.height));

    gl.glEnable(gl.GL_TEXTURE_2D);
    gl.glEnable(gl.GL_SCISSOR_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

    gl.glMatrixMode(gl.GL_TEXTURE);
    gl.glLoadIdentity();

    setScreenSpace(commands.width, commands.height);

    const sort_entry_count: u32 = commands.push_buffer_element_count;

    var clip_rect_index: u32 = 0xffffffff;
    var sort_entry: [*]u32 = prep.sorted_indices;
    var sort_entry_index: u32 = 0;
    while (sort_entry_index < sort_entry_count) : (sort_entry_index += 1) {
        defer sort_entry += 1;

        const header: *RenderEntryHeader = @ptrCast(@alignCast(commands.push_buffer_base + sort_entry[0]));
        const alignment: usize = switch (header.type) {
            .RenderEntryBitmap => @alignOf(RenderEntryBitmap),
            .RenderEntryRectangle => @alignOf(RenderEntryRectangle),
            .RenderEntryCoordinateSystem => @alignOf(RenderEntryCoordinateSystem),
            .RenderEntrySaturation => @alignOf(RenderEntrySaturation),
            else => {
                unreachable;
            },
        };

        const header_address = @intFromPtr(header);
        const data_address = header_address + @sizeOf(RenderEntryHeader);
        const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        const data: *anyopaque = @ptrFromInt(aligned_address);

        if (clip_rect_index != header.clip_rect_index) {
            clip_rect_index = header.clip_rect_index;

            std.debug.assert(clip_rect_index < commands.clip_rect_count);

            const clip: RenderEntryClipRect = prep.clip_rects[clip_rect_index];
            gl.glScissor(
                clip.rect.min.x() + commands.offset_x,
                clip.rect.min.y() + commands.offset_y,
                clip.rect.max.x() - clip.rect.min.x(),
                clip.rect.max.y() - clip.rect.min.y(),
            );
        }

        switch (header.type) {
            .RenderEntryBitmap => {
                var entry: *RenderEntryBitmap = @ptrCast(@alignCast(data));
                if (entry.bitmap) |bitmap| {
                    if (bitmap.width > 0 and bitmap.height > 0) {
                        const x_axis: Vector2 = entry.x_axis;
                        const y_axis: Vector2 = entry.y_axis;
                        const min_position: Vector2 = entry.position;

                        if (bitmap.texture_handle > 0) {
                            gl.glBindTexture(gl.GL_TEXTURE_2D, bitmap.texture_handle);
                        }

                        const one_texel_u: f32 = 1 / @as(f32, @floatFromInt(bitmap.width));
                        const one_texel_v: f32 = 1 / @as(f32, @floatFromInt(bitmap.height));
                        const min_uv = Vector2.new(one_texel_u, one_texel_v);
                        const max_uv = Vector2.new(1 - one_texel_u, 1 - one_texel_v);

                        gl.glBegin(gl.GL_TRIANGLES);
                        {
                            // This value is not gamma corrected by OpenGL.
                            gl.glColor4fv(entry.premultiplied_color.toGL());

                            const min_x_min_y: Vector2 = min_position;
                            const min_x_max_y: Vector2 = min_position.plus(y_axis);
                            const max_x_min_y: Vector2 = min_position.plus(x_axis);
                            const max_x_max_y: Vector2 = min_position.plus(x_axis).plus(y_axis);

                            // Lower triangle.
                            gl.glTexCoord2f(min_uv.x(), min_uv.y());
                            gl.glVertex2fv(min_x_min_y.toGL());
                            gl.glTexCoord2f(max_uv.x(), min_uv.y());
                            gl.glVertex2fv(max_x_min_y.toGL());
                            gl.glTexCoord2f(max_uv.x(), max_uv.y());
                            gl.glVertex2fv(max_x_max_y.toGL());

                            // Upper triangle
                            gl.glTexCoord2f(min_uv.x(), min_uv.y());
                            gl.glVertex2fv(min_x_min_y.toGL());
                            gl.glTexCoord2f(max_uv.x(), max_uv.y());
                            gl.glVertex2fv(max_x_max_y.toGL());
                            gl.glTexCoord2f(min_uv.x(), max_uv.y());
                            gl.glVertex2fv(min_x_max_y.toGL());
                        }
                        gl.glEnd();

                        gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
                    }
                }
            },
            .RenderEntryRectangle => {
                const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));
                gl.glDisable(gl.GL_TEXTURE_2D);
                drawRectangle(entry.position, entry.position.plus(entry.dimension), entry.premultiplied_color, null, null);

                gl.glBegin(gl.GL_LINES);
                gl.glColor4f(0, 0, 0, 1);
                drawLineVertices(entry.position, entry.position.plus(entry.dimension));
                gl.glEnd();

                gl.glEnable(gl.GL_TEXTURE_2D);
            },
            .RenderEntrySaturation => {
                // const entry: *RenderEntrySaturation = @ptrCast(@alignCast(data));
            },
            .RenderEntryCoordinateSystem => {
                // const entry: *RenderEntryCoordinateSystem = @ptrCast(@alignCast(data));
            },
            else => {
                unreachable;
            },
        }
    }

    gl.glDisable(gl.GL_TEXTURE_2D);
    if (global_config.Platform_ShowSortGroups) {
        const bound_count: u32 = commands.push_buffer_element_count;
        const bounds: [*]SortSpriteBound = render.getSortEntries(commands);
        var group_index: u32 = 0;
        var bound_index: u32 = 0;
        while (bound_index < bound_count) : (bound_index += 1) {
            const bound: *SortSpriteBound = @ptrCast(bounds + bound_index);
            if ((bound.flags & @intFromEnum(SpriteFlag.DebugBox)) == 0) {
                var color: Color = debug_color_table[group_index % debug_color_table.len].toColor(0.2);
                group_index += 1;

                if ((bound.flags & @intFromEnum(SpriteFlag.Cycle)) != 0) {
                    _ = color.setA(1);
                }
                _ = color.setRGB(color.rgb().scaledTo(color.a()));

                gl.glBegin(gl.GL_LINES);
                gl.glColor4f(
                    color.r(),
                    color.g(),
                    color.b(),
                    color.a(),
                );
                drawBoundsRecursive(bounds, bound_index);
                gl.glEnd();

                group_index += 1;
            }
        }
    }
}

fn drawBoundsRecursive(bounds: [*]SortSpriteBound, bound_index: u32) void {
    const bound: *SortSpriteBound = @ptrCast(bounds + bound_index);
    if ((bound.flags & @intFromEnum(SpriteFlag.DebugBox)) == 0) {
        const center: Vector2 = bound.screen_area.getCenter();
        bound.flags |= @intFromEnum(SpriteFlag.DebugBox);

        var opt_edge: ?*SpriteEdge = bound.first_edge_with_me_as_front;
        while (opt_edge) |edge| : (opt_edge = edge.next_edge_with_same_front) {
            const behind: *SortSpriteBound = @ptrCast(bounds + edge.behind);
            const behind_center: Vector2 = behind.screen_area.getCenter();
            gl.glVertex2fv(@ptrCast(&center.values));
            gl.glVertex2fv(@ptrCast(&behind_center.values));

            drawBoundsRecursive(bounds, edge.behind);
        }

        const screen_min = bound.screen_area.getMinCorner();
        const screen_max = bound.screen_area.getMaxCorner();
        drawLineVertices(screen_min, screen_max);
    }
}

pub fn manageTextures(first_op: ?*TextureOp) void {
    var opt_op: ?*render.TextureOp = first_op;
    while (opt_op) |op| : (opt_op = op.next) {
        if (op.is_allocate) {
            op.op.allocate.result_handle.* = allocateTexture(
                op.op.allocate.width,
                op.op.allocate.height,
                op.op.allocate.data,
            );
        } else {
            gl.glDeleteTextures(1, &op.op.deallocate.handle);
        }
    }
}

fn allocateTexture(width: i32, height: i32, data: *anyopaque) callconv(.C) u32 {
    var handle: u32 = 0;

    gl.glGenTextures(1, &handle);
    gl.glBindTexture(gl.GL_TEXTURE_2D, handle);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        default_internal_texture_format,
        width,
        height,
        0,
        gl.GL_BGRA_EXT,
        gl.GL_UNSIGNED_BYTE,
        data,
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP);
    gl.glTexEnvi(gl.GL_TEXTURE_ENV, gl.GL_TEXTURE_ENV_MODE, gl.GL_MODULATE);

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);

    return handle;
}

fn drawLineVertices(
    min_position: Vector2,
    max_position: Vector2,
) void {
    gl.glVertex2f(min_position.x(), min_position.y());
    gl.glVertex2f(max_position.x(), min_position.y());

    gl.glVertex2f(max_position.x(), min_position.y());
    gl.glVertex2f(max_position.x(), max_position.y());

    gl.glVertex2f(max_position.x(), max_position.y());
    gl.glVertex2f(min_position.x(), max_position.y());

    gl.glVertex2f(min_position.x(), max_position.y());
    gl.glVertex2f(min_position.x(), min_position.y());
}

fn drawRectangle(
    min_position: Vector2,
    max_position: Vector2,
    premultiplied_color: Color,
    opt_min_uv: ?Vector2,
    opt_max_uv: ?Vector2,
) void {
    const min_uv = opt_min_uv orelse Vector2.splat(0);
    const max_uv = opt_max_uv orelse Vector2.splat(1);

    gl.glBegin(gl.GL_TRIANGLES);
    {
        // This value is not gamma corrected by OpenGL.
        gl.glColor4f(
            premultiplied_color.r(),
            premultiplied_color.g(),
            premultiplied_color.b(),
            premultiplied_color.a(),
        );

        // Lower triangle.
        gl.glTexCoord2f(min_uv.x(), min_uv.y());
        gl.glVertex2f(min_position.x(), min_position.y());
        gl.glTexCoord2f(max_uv.x(), min_uv.y());
        gl.glVertex2f(max_position.x(), min_position.y());
        gl.glTexCoord2f(max_uv.x(), max_uv.y());
        gl.glVertex2f(max_position.x(), max_position.y());

        // Upper triangle
        gl.glTexCoord2f(min_uv.x(), min_uv.y());
        gl.glVertex2f(min_position.x(), min_position.y());
        gl.glTexCoord2f(max_uv.x(), max_uv.y());
        gl.glVertex2f(max_position.x(), max_position.y());
        gl.glTexCoord2f(min_uv.x(), max_uv.y());
        gl.glVertex2f(min_position.x(), max_position.y());
    }
    gl.glEnd();
}

fn setScreenSpace(width: u32, height: u32) void {
    gl.glMatrixMode(gl.GL_MODELVIEW);
    gl.glLoadIdentity();

    gl.glMatrixMode(gl.GL_PROJECTION);
    const a = math.safeRatio1(2, @as(f32, @floatFromInt(width)));
    const b = math.safeRatio1(2, @as(f32, @floatFromInt(height)));
    const projection: []const f32 = &.{
        a,  0,  0, 0,
        0,  b,  0, 0,
        0,  0,  1, 0,
        -1, -1, 0, 1,
    };
    gl.glLoadMatrixf(@ptrCast(projection));
}

pub fn displayBitmap(
    width: i32,
    height: i32,
    offset_x: i32,
    offset_y: i32,
    window_width: i32,
    window_height: i32,
    pitch: usize,
    memory: ?*const anyopaque,
    blit_texture: u32,
) void {
    _ = window_width;
    _ = window_height;

    std.debug.assert(pitch == width * 4);

    gl.glDisable(gl.GL_SCISSOR_TEST);
    gl.glViewport(offset_x, offset_y, width, height);

    gl.glBindTexture(gl.GL_TEXTURE_2D, blit_texture);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        GL_SRGB8_ALPHA8,
        width,
        height,
        0,
        gl.GL_BGRA_EXT,
        gl.GL_UNSIGNED_BYTE,
        memory,
    );

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP);
    gl.glTexEnvi(gl.GL_TEXTURE_ENV, gl.GL_TEXTURE_ENV_MODE, gl.GL_MODULATE);

    gl.glEnable(gl.GL_TEXTURE_2D);

    gl.glClearColor(1, 0, 1, 0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    // Reset all transforms.
    gl.glMatrixMode(gl.GL_TEXTURE);
    gl.glLoadIdentity();

    setScreenSpace(@intCast(width), @intCast(height));

    const min_position = math.Vector2.new(0, 0);
    const max_position = math.Vector2.new(@floatFromInt(width), @floatFromInt(height));
    const color = math.Color.new(1, 1, 1, 1);

    drawRectangle(min_position, max_position, color, null, null);

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
}
