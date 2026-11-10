const win32 = @import("win32").everything;
const math = @import("math.zig");
const renderer = @import("renderer.zig");

// Types.
const Vector2u = math.Vector2u;
const Rectangle2i = math.Rectangle2i;
const PlatformRenderer = renderer.PlatformRenderer;
const RenderCommands = renderer.RenderCommands;

pub const win32LoadRendererType = fn (
    opt_window_dc: ?win32.HDC,
    limits: *renderer.PlatformRendererLimits,
) callconv(.c) ?*PlatformRenderer;

pub const win32BeginFrameType = fn (
    platform_renderer: *PlatformRenderer,
    window_dim: Vector2u,
    render_dim: Vector2u,
    draw_region: Rectangle2i,
) callconv(.c) ?*RenderCommands;

pub const win32EndFrameType = fn (
    platform_renderer: *PlatformRenderer,
    frame: *RenderCommands,
) callconv(.c) void;

pub const renderer_function_table_names: [3][*:0]const u8 = .{
    "win32LoadRenderer",
    "win32BeginFrame",
    "win32EndFrame",
};

pub const RendererFunctionTable = struct {
    win32LoadRenderer: ?*const win32LoadRendererType = null,
    win32BeginFrame: ?*const win32BeginFrameType = null,
    win32EndFrame: ?*const win32EndFrameType = null,
};
