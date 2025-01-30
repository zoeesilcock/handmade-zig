const shared = @import("shared.zig");
const rendergroup = @import("rendergroup.zig");
const asset = @import("asset.zig");
const math = @import("math.zig");
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

const RenderGroup = rendergroup.RenderGroup;
const TileSortEntry = rendergroup.TileSortEntry;
const RenderEntryHeader = rendergroup.RenderEntryHeader;
const RenderEntryClear = rendergroup.RenderEntryClear;
const RenderEntryBitmap = rendergroup.RenderEntryBitmap;
const RenderEntryRectangle = rendergroup.RenderEntryRectangle;
const RenderEntryCoordinateSystem = rendergroup.RenderEntryCoordinateSystem;
const RenderEntrySaturation = rendergroup.RenderEntrySaturation;
const LoadedBitmap = asset.LoadedBitmap;
const Vector2 = math.Vector2;
const Color = math.Color;
const Rectangle2i = math.Rectangle2i;
const TimedBlock = debug_interface.TimedBlock;

pub const gl = struct {
    // TODO: How do we import OpenGL on other platforms here?
    usingnamespace @import("win32").graphics.open_gl;
};

pub var default_internal_texture_format: i32 = 0;
var texture_bind_count: u32 = 0;

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
                }

                at = end;
            }
        }

        return result;
    }
};

pub fn init(is_modern_context: bool) void {
    const info = Info.get(is_modern_context);

    default_internal_texture_format = gl.GL_RGBA8;

    if (info.gl_ext_texture_srgb) {
        default_internal_texture_format = GL_SRGB8_ALPHA8;
    }

    if (info.gl_ext_framebuffer_srgb) {
        gl.glEnable(GL_FRAMEBUFFER_SRGB);
    }
}

pub fn renderCommands(commands: *shared.RenderCommands, window_width: i32, window_height: i32) callconv(.C) void {
    _ = window_width;
    _ = window_height;

    var timed_block = TimedBlock.beginFunction(@src(), .RenderToOutputOpenGL);
    defer timed_block.end();

    gl.glViewport(commands.offset_x, commands.offset_y, @intCast(commands.width), @intCast(commands.height));

    gl.glEnable(gl.GL_TEXTURE_2D);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

    gl.glMatrixMode(gl.GL_TEXTURE);
    gl.glLoadIdentity();

    setScreenSpace(commands.width, commands.height);

    const sort_entry_count: u32 = commands.push_buffer_element_count;
    const sort_entries: [*]TileSortEntry = @ptrFromInt(@intFromPtr(commands.push_buffer_base) + commands.sort_entry_at);

    var sort_entry: [*]TileSortEntry = sort_entries;
    var sort_entry_index: u32 = 0;
    while (sort_entry_index < sort_entry_count) : (sort_entry_index += 1) {
        defer sort_entry += 1;

        const header: *RenderEntryHeader = @ptrCast(commands.push_buffer_base + sort_entry[0].push_buffer_offset);
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
        const data: *anyopaque = @ptrFromInt(aligned_address);

        switch (header.type) {
            .RenderEntryClear => {
                const entry: *RenderEntryClear = @ptrCast(@alignCast(data));
                gl.glClearColor(entry.color.r(), entry.color.g(), entry.color.b(), entry.color.a());
                gl.glClear(gl.GL_COLOR_BUFFER_BIT);
            },
            .RenderEntryBitmap => {
                var entry: *RenderEntryBitmap = @ptrCast(@alignCast(data));
                if (entry.bitmap) |bitmap| {
                    const x_axis: Vector2 = Vector2.new(1, 0);
                    const y_axis: Vector2 = Vector2.new(0, 1);
                    const min_position: Vector2 = entry.position;
                    const max_position: Vector2 = min_position.plus(
                        x_axis.scaledTo(entry.size.x()).plus(y_axis.scaledTo(entry.size.y())),
                    );

                    if (bitmap.texture_handle) |texture| {
                        gl.glBindTexture(gl.GL_TEXTURE_2D, @as(*u32, @ptrCast(@alignCast(texture))).*);
                    }
                    drawRectangle(min_position, max_position, entry.color);
                }
            },
            .RenderEntryRectangle => {
                const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));
                gl.glDisable(gl.GL_TEXTURE_2D);
                drawRectangle(entry.position, entry.position.plus(entry.dimension), entry.color);
                gl.glEnable(gl.GL_TEXTURE_2D);
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

fn drawRectangle(min_position: Vector2, max_position: Vector2, color: Color) void {
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
) void {
    _ = window_width;
    _ = window_height;

    std.debug.assert(pitch == width * 4);

    gl.glViewport(offset_x, offset_y, width, height);

    gl.glBindTexture(gl.GL_TEXTURE_2D, 1);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        gl.GL_RGBA8,
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

    if (INTERNAL) {
        gl.glClearColor(1, 0, 1, 0);
    } else {
        gl.glClearColor(0, 0, 0, 0);
    }
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    // Reset all transforms.
    gl.glMatrixMode(gl.GL_TEXTURE);
    gl.glLoadIdentity();

    setScreenSpace(@intCast(width), @intCast(height));

    const min_position = math.Vector2.new(0, 0);
    const max_position = math.Vector2.new(@floatFromInt(width), @floatFromInt(height));
    const color = math.Color.new(1, 1, 1, 1);

    drawRectangle(min_position, max_position, color);
}

pub fn allocateTexture(width: i32, height: i32, data: *anyopaque) callconv(.C) ?*anyopaque {
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

    std.debug.assert(@sizeOf(u32) <= @sizeOf(*anyopaque));

    // TODO: Surely this is a dangling pointer?
    return @ptrCast(&handle);
}

pub fn deallocateTexture(texture: ?*anyopaque) callconv(.C) void {
    gl.glDeleteTextures(1, @ptrCast(@alignCast(texture)));
}
