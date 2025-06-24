const shared = @import("shared.zig");
const intrinsics = @import("intrinsics.zig");
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
pub const GL_FRAMEBUFFER = 0x8D40;
pub const GL_COLOR_ATTACHMENT0 = 0x8CE0;
pub const GL_FRAME_BUFFER_COMPLETE = 0x8CD5;

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
const RenderEntryBlendRenderTarget = rendergroup.RenderEntryBlendRenderTarget;
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
var frame_buffer_count: u32 = 1;
var frame_buffer_handles: [256]c_uint = [1]c_uint{0} ** 256;
var frame_buffer_textures: [256]c_uint = [1]c_uint{0} ** 256;

pub const Info = struct {
    is_modern_context: bool,
    vendor: ?*const u8,
    renderer: ?*const u8,
    version: ?*const u8,
    shader_language_version: ?*const u8 = undefined,
    extensions: ?*const u8,

    gl_ext_texture_srgb: bool = false,
    gl_ext_framebuffer_srgb: bool = false,
    gl_arb_framebuffer_object: bool = false,

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
                } else if (shared.stringsWithOneLengthAreEqual(at, count, "GL_ARB_framebuffer_object")) {
                    result.gl_arb_framebuffer_object = true;
                }

                at = end;
            }
        }

        const opt_major_at: ?[*]const u8 = @ptrCast(result.version);
        var opt_minor_at: ?[*]const u8 = null;
        var at: [*]const u8 = @ptrCast(result.version);
        while (at[0] != 0) : (at += 1) {
            if (at[0] == '.') {
                opt_minor_at = at + 1;
                break;
            }
        }

        var major: i32 = 1;
        var minor: i32 = 0;
        if (opt_major_at) |major_at| {
            if (opt_minor_at) |minor_at| {
                major = shared.i32FromZ(major_at);
                minor = shared.i32FromZ(minor_at);
            }
        }

        if (major > 2 or (major == 2 and minor >= 1)) {
            result.gl_ext_texture_srgb = true;
        }

        return result;
    }
};

pub fn init(is_modern_context: bool, framebuffer_supports_sRGB: bool) Info {
    const info = Info.get(is_modern_context);

    default_internal_texture_format = gl.GL_RGBA8;

    if (framebuffer_supports_sRGB and info.gl_ext_texture_srgb and info.gl_ext_framebuffer_srgb) {
        default_internal_texture_format = GL_SRGB8_ALPHA8;
        gl.glEnable(GL_FRAMEBUFFER_SRGB);
    }

    gl.glTexEnvi(gl.GL_TEXTURE_ENV, gl.GL_TEXTURE_ENV_MODE, gl.GL_MODULATE);

    return info;
}

fn bindFrameBuffer(target_index: u32, draw_region: Rectangle2i) void {
    if (platform.optGlBindFramebufferEXT) |glBindFramebuffer| {
        const window_width: i32 = draw_region.getWidth();
        const window_height: i32 = draw_region.getHeight();

        glBindFramebuffer(GL_FRAMEBUFFER, frame_buffer_handles[target_index]);

        if (target_index > 0) {
            gl.glViewport(0, 0, window_width, window_height);
        } else {
            gl.glViewport(draw_region.min.x(), draw_region.min.y(), window_width, window_height);
        }
    }
}

pub fn renderCommands(
    commands: *RenderCommands,
    prep: *GameRenderPrep,
    draw_region: Rectangle2i,
    window_width: i32,
    window_height: i32,
) callconv(.C) void {
    // TimedBlock.beginFunction(@src(), .RenderCommandsToOpenGL);
    // defer TimedBlock.endFunction(@src(), .RenderCommandsToOpenGL);

    gl.glEnable(gl.GL_TEXTURE_2D);
    gl.glEnable(gl.GL_SCISSOR_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

    gl.glMatrixMode(gl.GL_TEXTURE);
    gl.glLoadIdentity();

    std.debug.assert(commands.max_render_target_index < frame_buffer_handles.len);

    const use_render_targets: bool = platform.optGlBindFramebufferEXT != null;
    const max_render_target_index: u32 = if (use_render_targets) commands.max_render_target_index else 0;
    if (max_render_target_index >= frame_buffer_count) {
        const new_frame_buffer_count: u32 = max_render_target_index + 1;
        std.debug.assert(new_frame_buffer_count < frame_buffer_handles.len);

        const new_count: u32 = new_frame_buffer_count - frame_buffer_count;
        if (platform.optGlGenFramebuffersEXT) |glGenFrameBuffers| {
            glGenFrameBuffers(new_count, @ptrCast(&frame_buffer_handles[frame_buffer_count]));
        }

        if (platform.optGlBindFramebufferEXT) |glBindFramebuffer| {
            if (platform.optGlFrameBufferTexture2DEXT) |glBindFrameBufferTexture2D| {
                var target_index: u32 = frame_buffer_count;
                while (target_index <= new_frame_buffer_count) : (target_index += 1) {
                    const texture_handle: u32 = allocateTexture(draw_region.getWidth(), draw_region.getHeight(), null);
                    frame_buffer_textures[target_index] = texture_handle;

                    glBindFramebuffer(GL_FRAMEBUFFER, frame_buffer_handles[target_index]);
                    glBindFrameBufferTexture2D(
                        GL_FRAMEBUFFER,
                        GL_COLOR_ATTACHMENT0,
                        gl.GL_TEXTURE_2D,
                        texture_handle,
                        0,
                    );

                    if (platform.optGlCheckFramebufferStatusEXT) |checkFramebufferStatus| {
                        const status: u32 = checkFramebufferStatus(GL_FRAMEBUFFER);
                        std.debug.assert(status == GL_FRAME_BUFFER_COMPLETE);
                    }
                }
            }
        }

        frame_buffer_count = new_frame_buffer_count;
    }

    var target_index: u32 = 0;
    while (target_index <= max_render_target_index) : (target_index += 1) {
        if (use_render_targets) {
            bindFrameBuffer(target_index, draw_region);
        }

        if (target_index == 0) {
            gl.glScissor(0, 0, window_width, window_height);
        } else {
            gl.glScissor(0, 0, draw_region.getWidth(), draw_region.getHeight());
        }

        gl.glClearColor(
            commands.clear_color.r(),
            commands.clear_color.g(),
            commands.clear_color.b(),
            commands.clear_color.a(),
        );

        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
    }

    const clip_scale_x: f32 = math.safeRatio0(@floatFromInt(draw_region.getWidth()), @floatFromInt(commands.width));
    const clip_scale_y: f32 = math.safeRatio0(@floatFromInt(draw_region.getHeight()), @floatFromInt(commands.height));

    setScreenSpace(commands.width, commands.height);

    var clip_rect_index: u32 = 0xffffffff;
    var current_render_target_index: u32 = 0xffffffff;
    var entry_offset: [*]u32 = prep.sorted_indices;
    var sort_entry_index: u32 = 0;
    while (sort_entry_index < prep.sorted_index_count) : (sort_entry_index += 1) {
        defer entry_offset += 1;

        const header: *RenderEntryHeader = @ptrCast(@alignCast(commands.push_buffer_base + entry_offset[0]));
        const alignment: usize = switch (header.type) {
            .RenderEntryBitmap => @alignOf(RenderEntryBitmap),
            .RenderEntryRectangle => @alignOf(RenderEntryRectangle),
            .RenderEntryCoordinateSystem => @alignOf(RenderEntryCoordinateSystem),
            .RenderEntrySaturation => @alignOf(RenderEntrySaturation),
            .RenderEntryBlendRenderTarget => @alignOf(RenderEntryBlendRenderTarget),
            else => {
                unreachable;
            },
        };

        const header_address = @intFromPtr(header);
        const data_address = header_address + @sizeOf(RenderEntryHeader);
        const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        const data: *anyopaque = @ptrFromInt(aligned_address);

        if (use_render_targets or
            prep.clip_rects[header.clip_rect_index].render_target_index <= max_render_target_index)
        {
            if (clip_rect_index != header.clip_rect_index) {
                clip_rect_index = header.clip_rect_index;

                std.debug.assert(clip_rect_index < commands.clip_rect_count);

                const clip: RenderEntryClipRect = prep.clip_rects[clip_rect_index];
                var clip_rect: Rectangle2i = clip.rect;

                if (current_render_target_index != clip.render_target_index) {
                    current_render_target_index = clip.render_target_index;
                    std.debug.assert(current_render_target_index <= max_render_target_index);
                    if (use_render_targets) {
                        bindFrameBuffer(current_render_target_index, draw_region);
                    }
                }

                _ = clip_rect.min.setX(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.min.x())) * clip_scale_x),
                );
                _ = clip_rect.max.setX(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.max.x())) * clip_scale_x),
                );
                _ = clip_rect.min.setY(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.min.y())) * clip_scale_y),
                );
                _ = clip_rect.max.setY(
                    intrinsics.roundReal32ToInt32(@as(f32, @floatFromInt(clip_rect.max.y())) * clip_scale_y),
                );

                if (!use_render_targets or clip.render_target_index == 0) {
                    clip_rect = clip_rect.offsetBy(draw_region.min);
                }

                gl.glScissor(
                    clip_rect.min.x(),
                    clip_rect.min.y(),
                    clip_rect.max.x() - clip_rect.min.x(),
                    clip_rect.max.y() - clip_rect.min.y(),
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
                        }
                    }
                },
                .RenderEntryRectangle => {
                    const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));
                    gl.glDisable(gl.GL_TEXTURE_2D);
                    drawRectangle(entry.position, entry.position.plus(entry.dimension), entry.premultiplied_color, null, null);

                    if (true) {
                        gl.glBegin(gl.GL_LINES);
                        gl.glColor4f(0, 0, 0, entry.premultiplied_color.a());
                        drawLineVertices(entry.position, entry.position.plus(entry.dimension));
                        gl.glEnd();
                    }

                    gl.glEnable(gl.GL_TEXTURE_2D);
                },
                .RenderEntrySaturation => {
                    // const entry: *RenderEntrySaturation = @ptrCast(@alignCast(data));
                },
                .RenderEntryCoordinateSystem => {
                    // const entry: *RenderEntryCoordinateSystem = @ptrCast(@alignCast(data));
                },
                .RenderEntryBlendRenderTarget => {
                    const entry: *RenderEntryBlendRenderTarget = @ptrCast(@alignCast(data));
                    if (use_render_targets) {
                        gl.glBindTexture(gl.GL_TEXTURE_2D, frame_buffer_textures[entry.source_target_index]);
                        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
                        drawRectangle(
                            .zero(),
                            .new(@floatFromInt(commands.width), @floatFromInt(commands.height)),
                            .new(1, 1, 1, entry.alpha),
                            null,
                            null,
                        );
                        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
                    }
                },
                else => {
                    unreachable;
                },
            }
        }
    }

    if (use_render_targets) {
        if (platform.optGlBindFramebufferEXT) |glBindFramebuffer| {
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
        }
    }

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
    gl.glDisable(gl.GL_TEXTURE_2D);

    if (global_config.Platform_ShowSortGroups) {
        const bound_count: u32 = commands.sort_entry_count;
        const bounds: [*]SortSpriteBound = render.getSortEntries(commands);
        var group_index: u32 = 0;
        var bound_index: u32 = 0;
        while (bound_index < bound_count) : (bound_index += 1) {
            const bound: *SortSpriteBound = @ptrCast(bounds + bound_index);
            if (bound.offset != render.SPRITE_BARRIER_OFFSET_VALUE and
                (bound.flags & @intFromEnum(SpriteFlag.DebugBox)) == -1)
            {
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

fn allocateTexture(width: i32, height: i32, data: ?*anyopaque) callconv(.C) u32 {
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
    draw_region: Rectangle2i,
    pitch: usize,
    memory: ?*const anyopaque,
    clear_color: Color,
    blit_texture: u32,
) void {
    std.debug.assert(pitch == width * 4);

    bindFrameBuffer(0, draw_region);

    gl.glDisable(gl.GL_SCISSOR_TEST);
    gl.glDisable(gl.GL_BLEND);

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

    gl.glEnable(gl.GL_TEXTURE_2D);

    gl.glClearColor(0, 0, 0, 0);
    gl.glClearColor(clear_color.r(), clear_color.g(), clear_color.b(), clear_color.a());
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
    gl.glEnable(gl.GL_BLEND);
}
