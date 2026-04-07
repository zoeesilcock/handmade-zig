const shared = @import("shared.zig");
const asset = @import("asset.zig");
const asset_rendering = @import("asset_rendering.zig");
const math = @import("math.zig");
const debug = @import("debug.zig");
const debug_interface = @import("debug_interface.zig");
const renderer = @import("renderer.zig");
const types = @import("types.zig");
const dev_ui = @import("dev_ui.zig");
const std = @import("std");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle2 = math.Rectangle2;
const Rectangle3 = math.Rectangle3;
const DebugState = debug.DebugState;
const DebugTree = debug.DebugTree;
const DebugLineBuffer = debug.DebugLineBuffer;
const DevId = types.DevId;
const DebugType = debug_interface.DebugType;
const ObjectTransform = renderer.ObjectTransform;
const RenderGroup = renderer.RenderGroup;
const TransientClipRect = renderer.TransientClipRect;

pub const Layout = struct {
    debug_state: *DebugState,
    mouse_position: Vector2,
    base_corner: Vector2,

    depth: u32,

    at: Vector2,
    line_advance: f32,
    next_y_delta: f32 = 0,
    spacing_x: f32,
    spacing_y: f32,

    no_line_feed: u32 = 0,
    line_initialized: bool,

    pub fn begin(debug_state: *DebugState, mouse_position: Vector2, upper_corner: Vector2) Layout {
        var layout: Layout = .{
            .debug_state = debug_state,
            .mouse_position = mouse_position,
            .base_corner = upper_corner,
            .at = upper_corner,
            .line_advance = 0,
            .depth = 0,
            .spacing_x = 4,
            .spacing_y = 4,
            .line_initialized = false,
        };

        if (debug_state.debug_font_info) |font_info| {
            layout.line_advance = font_info.getLineAdvance() * debug_state.font_scale;
        }
        return layout;
    }

    pub fn end(self: *Layout) void {
        _ = self;
    }

    pub fn beginElementRectangle(self: *Layout, dimension: *Vector2) LayoutElement {
        const element: LayoutElement = .{
            .layout = self,
            .dimension = dimension,
        };
        return element;
    }

    pub fn beginRow(self: *Layout) void {
        self.no_line_feed += 1;
    }

    pub fn label(self: *Layout, name: [:0]const u8) void {
        const null_interaction: dev_ui.Interaction = .{};
        _ = basicTextElement(name, self, null_interaction, Color.white(), Color.white(), null, null);
    }

    pub fn actionButton(self: *Layout, name: [:0]const u8, interaction: dev_ui.Interaction) void {
        _ = basicTextElement(
            name,
            self,
            interaction,
            Color.new(0.5, 0.5, 0.5, 1),
            Color.white(),
            4,
            Color.new(0, 0.5, 1, 1),
        );
    }

    pub fn booleanButton(self: *Layout, name: [:0]const u8, highlight: bool, interaction: dev_ui.Interaction) void {
        _ = basicTextElement(
            name,
            self,
            interaction,
            if (highlight) Color.white() else Color.new(0.5, 0.5, 0.5, 1),
            Color.white(),
            4,
            Color.new(0, 0.5, 1, 1),
        );
    }

    pub fn advanceElement(self: *Layout, element_rect: Rectangle2) void {
        self.next_y_delta = @min(self.next_y_delta, element_rect.min.y() - self.at.y());

        if (self.no_line_feed > 0) {
            _ = self.at.setX(element_rect.getMaxCorner().x() + self.spacing_x);
        } else {
            _ = self.at.setY(self.at.y() + self.next_y_delta - self.spacing_y);
            self.line_initialized = false;
        }
    }

    pub fn endRow(self: *Layout) void {
        std.debug.assert(self.no_line_feed > 0);

        self.no_line_feed -= 1;
        self.advanceElement(Rectangle2.fromMinMax(self.at, self.at));
    }
};

pub const LayoutElement = struct {
    layout: *Layout,
    dimension: *Vector2,
    size: ?*Vector2 = null,
    default_interaction: ?dev_ui.Interaction = null,

    bounds: Rectangle2 = undefined,

    pub fn makeSizable(self: *LayoutElement) void {
        self.size = self.dimension;
    }

    pub fn defaultInteraction(self: *LayoutElement, interaction: dev_ui.Interaction) void {
        self.default_interaction = interaction;
    }

    pub fn end(self: *LayoutElement) void {
        const layout: *Layout = self.layout;
        const debug_state: *DebugState = layout.debug_state;
        const no_transform = debug_state.backing_transform;

        if (!layout.line_initialized) {
            _ = layout.at.setX(
                layout.base_corner.x() + @as(f32, @floatFromInt(layout.depth)) * 2 * layout.line_advance,
            );
            layout.next_y_delta = 0;
            layout.line_initialized = true;
        }

        var render_group: *RenderGroup = &debug_state.render_group;
        const size_handle_pixels: f32 = 4;
        var frame: Vector2 = Vector2.new(0, 0);

        if (self.size != null) {
            frame = Vector2.splat(size_handle_pixels);
        }

        const total_dimension: Vector2 = self.dimension.plus(frame.scaledTo(2));

        const total_min_corner: Vector2 = Vector2.new(
            layout.at.x(),
            layout.at.y() - total_dimension.y(),
        );
        const total_max_corner: Vector2 = total_min_corner.plus(total_dimension);

        const interior_min_corner: Vector2 = total_min_corner.plus(frame);
        const interior_max_corner: Vector2 = interior_min_corner.plus(self.dimension.*);

        const total_bounds: Rectangle2 = Rectangle2.fromMinMax(total_min_corner, total_max_corner);
        self.bounds = Rectangle2.fromMinMax(interior_min_corner, interior_max_corner);

        if (self.default_interaction) |interaction| {
            if (interaction.interaction_type != .None and layout.mouse_position.isInRectangle(self.bounds)) {
                debug_state.next_hot_interaction = interaction;
            }
        }

        if (self.size) |size| {
            render_group.pushRectangle2(
                &no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(total_min_corner.x(), interior_min_corner.y()),
                    Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                ),
                0,
                Color.black(),
            );
            render_group.pushRectangle2(
                &no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                    Vector2.new(total_max_corner.x(), total_max_corner.y()),
                ),
                0,
                Color.black(),
            );
            render_group.pushRectangle2(
                &no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(interior_min_corner.x(), total_min_corner.y()),
                    Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                ),
                0,
                Color.black(),
            );
            render_group.pushRectangle2(
                &no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                    Vector2.new(interior_max_corner.x(), total_max_corner.y()),
                ),
                0,
                Color.black(),
            );

            const size_interaction: dev_ui.Interaction = dev_ui.Interaction{
                .interaction_type = .Resize,
                .data = .{ .position = size },
            };

            const size_box: Rectangle2 = Rectangle2.fromMinMax(
                Vector2.new(interior_max_corner.x(), total_min_corner.y()),
                Vector2.new(total_max_corner.x(), interior_min_corner.y()),
            ).addRadius(Vector2.splat(4));
            const size_box_color: Color =
                if (size_interaction.isHot(debug_state)) Color.new(1, 1, 0, 1) else Color.white();
            render_group.pushRectangle2(&no_transform, size_box, 0, size_box_color);

            if (layout.mouse_position.isInRectangle(size_box)) {
                debug_state.next_hot_interaction = size_interaction;
            }
        }

        layout.advanceElement(total_bounds);
    }
};

pub fn basicTextElement(
    text: [:0]const u8,
    layout: *Layout,
    item_interaction: dev_ui.Interaction,
    opt_color: ?Color,
    opt_hot_color: ?Color,
    opt_border: ?f32,
    opt_backdrop_color: ?Color,
) Vector2 {
    var dim: Vector2 = Vector2.zero();
    const border: f32 = opt_border orelse 0;

    if (layout.debug_state.debug_font_info) |font_info| {
        const item_color = opt_color orelse Color.new(0.8, 0.8, 0.8, 1);
        const hot_color = opt_hot_color orelse Color.white();
        const text_bounds = getTextSize(layout.debug_state, text);
        dim = Vector2.new(text_bounds.getDimension().x() + 2 * border, layout.line_advance + 2 * border);

        var layout_element: LayoutElement = layout.beginElementRectangle(&dim);
        layout_element.defaultInteraction(item_interaction);
        layout_element.end();

        const is_hot: bool = item_interaction.isHot(layout.debug_state);

        const text_position: Vector2 = Vector2.new(
            layout_element.bounds.min.x() + border,
            layout_element.bounds.max.y() - border - layout.debug_state.font_scale * font_info.getStartingBaselineY(),
        );

        if (opt_backdrop_color) |backdrop_color| {
            layout.debug_state.render_group.pushRectangle2(
                &layout.debug_state.backing_transform,
                layout_element.bounds,
                0,
                backdrop_color,
            );
        }
        textOutAt(layout.debug_state, text, text_position, if (is_hot) hot_color else item_color, null);
    }
    return dim;
}

pub fn textOutAt(debug_state: *DebugState, text: [:0]const u8, position: Vector2, color: Color, opt_z: ?f32) void {
    _ = dev_ui.textOp(&debug_state.dev_ui_context, .DrawText, text, position, color, opt_z);
}

pub fn getTextSize(debug_state: *DebugState, text: [:0]const u8) Rectangle2 {
    return dev_ui.textOp(&debug_state.dev_ui_context, .SizeText, text, Vector2.zero(), Color.white(), null);
}

pub fn getTextSizeAt(debug_state: *DebugState, text: [:0]const u8, at: Vector2) Rectangle2 {
    return dev_ui.textOp(&debug_state.dev_ui_context, .SizeText, text, at, Color.white(), null);
}

pub const TooltipBuffer = struct {
    size: usize = 0,
    data: [*]u8 = undefined,
};

pub fn addLine(buffer: *DebugLineBuffer) TooltipBuffer {
    var result: TooltipBuffer = .{
        .size = buffer.line_text[0].len,
    };

    if (buffer.line_count < buffer.line_text.len) {
        result.data = &buffer.line_text[buffer.line_count];
        buffer.line_count += 1;
    } else {
        result.data = &buffer.line_text[buffer.line_count - 1];
    }

    return result;
}

pub fn drawLineBuffer(debug_state: *DebugState, buffer: *DebugLineBuffer) void {
    var layout: *Layout = &debug_state.mouse_text_layout;

    if (layout.debug_state.debug_font_info) |font_info| {
        const render_group: *RenderGroup = &debug_state.render_group;
        const transient_clip_rect: TransientClipRect = .initWith(render_group, debug_state.default_clip_rect);
        defer transient_clip_rect.restore();

        var tooltip_index: u32 = 0;
        while (tooltip_index < buffer.line_count) : (tooltip_index += 1) {
            const text = buffer.line_text[tooltip_index];
            const text_bounds = getTextSize(layout.debug_state, @ptrCast(&text));
            var dim: Vector2 = Vector2.new(text_bounds.getDimension().x(), layout.line_advance);

            var layout_element: LayoutElement = layout.beginElementRectangle(&dim);
            layout_element.end();

            layout.debug_state.render_group.pushRectangle2(
                &layout.debug_state.tooltip_transform,
                layout_element.bounds.addRadius(.new(4, 4)),
                0,
                .new(0, 0, 0, 0.75),
            );

            const text_position: Vector2 = Vector2.new(
                layout_element.bounds.min.x(),
                layout_element.bounds.max.y() - layout.debug_state.font_scale * font_info.getStartingBaselineY(),
            );
            // TODO: It's probably the right thing to do to make z flow through the debug system sensibly.
            textOutAt(layout.debug_state, @ptrCast(&text), text_position, Color.white(), 4000);
        }
    }
}
