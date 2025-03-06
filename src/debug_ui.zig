const asset = @import("asset.zig");
const math = @import("math.zig");
const debug = @import("debug.zig");
const debug_interface = @import("debug_interface.zig");
const rendergroup = @import("rendergroup.zig");
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
const DebugElement = debug.DebugElement;
const DebugVariableLink = debug.DebugVariableLink;
const DebugId = debug_interface.DebugId;
const DebugType = debug_interface.DebugType;
const ObjectTransform = rendergroup.ObjectTransform;
const RenderGroup = rendergroup.RenderGroup;

const DebugTextOp = enum {
    DrawText,
    SizeText,
};

const DebugInteractionType = enum(u32) {
    None,
    NoOp,
    AutoModifyVariable,
    ToggleValue,
    DragValue,
    TearValue,
    Resize,
    Move,
    Select,
    ToggleExpansion,
    SetUInt32,
    SetBool,
    SetPointer,
};

const DebugInteractionTargetType = enum(u32) {
    uint32,
    bool,
    tree,
    link,
    position,
    debug_type,
    pointer,
    element,
};

pub const DebugInteraction = struct {
    id: DebugId = undefined,
    interaction_type: DebugInteractionType = .None,

    target: ?*anyopaque = null,
    pointer_target: ?*?*const anyopaque = null,

    data: union(DebugInteractionTargetType) {
        uint32: u32,
        bool: bool,
        tree: ?*DebugTree,
        link: ?*DebugVariableLink,
        position: *Vector2,
        debug_type: DebugType,
        pointer: ?*const anyopaque,
        element: ?*DebugElement,
    } = .{ .uint32 = 0 },

    pub fn equals(self: *const DebugInteraction, other: *const DebugInteraction) bool {
        return self.id.equals(other.id) and
            self.interaction_type == other.interaction_type and
            self.target == other.target and
            std.meta.eql(self.data, other.data);
    }

    pub fn isHot(self: *const DebugInteraction, debug_state: *const DebugState) bool {
        var result: bool = self.equals(&debug_state.hot_interaction);

        if (self.interaction_type == .None) {
            result = false;
        }

        return result;
    }

    pub fn elementInteraction(
        debug_state: *DebugState,
        debug_id: DebugId,
        element: *DebugElement,
        interaction_type: DebugInteractionType,
    ) DebugInteraction {
        _ = debug_state;
        return DebugInteraction{
            .id = debug_id,
            .interaction_type = interaction_type,
            .data = .{ .element = element },
        };
    }

    pub fn fromId(id: DebugId, interaction_type: DebugInteractionType) DebugInteraction {
        return DebugInteraction{
            .id = id,
            .interaction_type = interaction_type,
            .data = undefined,
        };
    }

    pub fn fromLink(link: *DebugVariableLink, interaction_type: DebugInteractionType) DebugInteraction {
        return DebugInteraction{
            .id = undefined,
            .interaction_type = interaction_type,
            .data = .{ .link = link },
        };
    }

    pub fn setUInt32(debug_id: DebugId, target: *anyopaque, value: u32) DebugInteraction {
        const result: DebugInteraction = DebugInteraction{
            .id = debug_id,
            .interaction_type = .SetUInt32,
            .target = target,
            .data = .{ .uint32 = value },
        };
        return result;
    }

    pub fn setBool(debug_id: DebugId, target: *anyopaque, value: bool) DebugInteraction {
        const result: DebugInteraction = DebugInteraction{
            .id = debug_id,
            .interaction_type = .SetBool,
            .target = target,
            .data = .{ .bool = value },
        };
        return result;
    }

    pub fn setPointer(debug_id: DebugId, target: ?*?*const anyopaque, value: ?*const anyopaque) DebugInteraction {
        const result: DebugInteraction = DebugInteraction{
            .id = debug_id,
            .interaction_type = .SetPointer,
            .pointer_target = target,
            .data = .{ .pointer = value },
        };
        return result;
    }
};

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
        const null_interaction: DebugInteraction = .{};
        _ = basicTextElement(name, self, null_interaction, Color.white(), Color.white(), null, null);
    }

    pub fn actionButton(self: *Layout, name: [:0]const u8, interaction: DebugInteraction) void {
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

    pub fn booleanButton(self: *Layout, name: [:0]const u8, highlight: bool, interaction: DebugInteraction) void {
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
    default_interaction: ?DebugInteraction = null,

    bounds: Rectangle2 = undefined,

    pub fn makeSizable(self: *LayoutElement) void {
        self.size = self.dimension;
    }

    pub fn defaultInteraction(self: *LayoutElement, interaction: DebugInteraction) void {
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
                no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(total_min_corner.x(), interior_min_corner.y()),
                    Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                ),
                0,
                Color.black(),
            );
            render_group.pushRectangle2(
                no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                    Vector2.new(total_max_corner.x(), total_max_corner.y()),
                ),
                0,
                Color.black(),
            );
            render_group.pushRectangle2(
                no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(interior_min_corner.x(), total_min_corner.y()),
                    Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                ),
                0,
                Color.black(),
            );
            render_group.pushRectangle2(
                no_transform,
                Rectangle2.fromMinMax(
                    Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                    Vector2.new(interior_max_corner.x(), total_max_corner.y()),
                ),
                0,
                Color.black(),
            );

            const size_interaction: DebugInteraction = DebugInteraction{
                .interaction_type = .Resize,
                .data = .{ .position = size },
            };

            const size_box: Rectangle2 = Rectangle2.fromMinMax(
                Vector2.new(interior_max_corner.x(), total_min_corner.y()),
                Vector2.new(total_max_corner.x(), interior_min_corner.y()),
            ).addRadius(Vector2.splat(4));
            const size_box_color: Color =
                if (size_interaction.isHot(debug_state)) Color.new(1, 1, 0, 1) else Color.white();
            render_group.pushRectangle2(no_transform, size_box, 0, size_box_color);

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
    item_interaction: DebugInteraction,
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
        textOutAt(layout.debug_state, text, text_position, if (is_hot) hot_color else item_color, null);

        if (opt_backdrop_color) |backdrop_color| {
            layout.debug_state.render_group.pushRectangle2(
                layout.debug_state.backing_transform,
                layout_element.bounds,
                0,
                backdrop_color,
            );
        }
    }
    return dim;
}

pub fn textOutAt(debug_state: *DebugState, text: [:0]const u8, position: Vector2, color: Color, opt_z: ?f32) void {
    _ = textOp(debug_state, .DrawText, text, position, color, opt_z);
}

pub fn getTextSize(debug_state: *DebugState, text: [:0]const u8) Rectangle2 {
    return textOp(debug_state, .SizeText, text, Vector2.zero(), Color.white(), null);
}

pub fn addTooltip(debug_state: *DebugState, text: [:0]const u8) void {
    var layout: *Layout = &debug_state.mouse_text_layout;

    if (layout.debug_state.debug_font_info) |font_info| {
        const render_group: *RenderGroup = &debug_state.render_group;
        const old_clip_rect: u32 = render_group.current_clip_rect_index;
        render_group.current_clip_rect_index = debug_state.default_clip_rect;
        defer render_group.current_clip_rect_index = old_clip_rect;

        const text_bounds = getTextSize(layout.debug_state, text);
        var dim: Vector2 = Vector2.new(text_bounds.getDimension().x(), layout.line_advance);

        var layout_element: LayoutElement = layout.beginElementRectangle(&dim);
        layout_element.end();

        const text_position: Vector2 = Vector2.new(
            layout_element.bounds.min.x(),
            layout_element.bounds.max.y() - layout.debug_state.font_scale * font_info.getStartingBaselineY(),
        );
        textOutAt(layout.debug_state, text, text_position, Color.white(), 10000);
    }
}

fn isHex(char: u8) bool {
    return (char >= '0' and char <= '9') or (char >= 'A' and char <= 'F');
}

fn getHex(char: u8) u32 {
    var result: u32 = 0;

    if (char >= '0' and char <= '9') {
        result = char - '0';
    } else if (char >= 'A' and char <= 'F') {
        result = 0xA + (char - 'A');
    }

    return result;
}

pub fn textOp(
    debug_state: *DebugState,
    op: DebugTextOp,
    text: [:0]const u8,
    position: Vector2,
    color_in: Color,
    opt_z: ?f32,
) Rectangle2 {
    var result: Rectangle2 = Rectangle2.invertedInfinity();
    var rect_found = false;
    var color = color_in;
    const z: f32 = opt_z orelse 0;

    var render_group: *RenderGroup = &debug_state.render_group;
    if (debug_state.debug_font) |font| {
        if (debug_state.debug_font_info) |font_info| {
            var match_vector = asset.AssetVector{};
            var prev_code_point: u32 = 0;
            var char_scale = debug_state.font_scale;
            var x: f32 = position.x();

            var at: [*]const u8 = @ptrCast(text);
            while (at[0] != 0) {
                if (at[0] == '\\' and
                    at[1] == '#' and
                    at[2] != 0 and
                    at[3] != 0 and
                    at[4] != 0)
                {
                    const c_scale: f32 = 1.0 / 9.0;
                    color = Color.new(
                        math.clampf01(c_scale * @as(f32, @floatFromInt(at[2] - '0'))),
                        math.clampf01(c_scale * @as(f32, @floatFromInt(at[3] - '0'))),
                        math.clampf01(c_scale * @as(f32, @floatFromInt(at[4] - '0'))),
                        1,
                    );

                    at += 5;
                } else if (at[0] == '\\' and
                    at[1] == '^' and
                    at[2] != 0)
                {
                    const c_scale: f32 = 1.0 / 9.0;
                    char_scale = debug_state.font_scale * math.clampf01(c_scale * @as(f32, @floatFromInt(at[2] - '0')));
                    at += 3;
                } else {
                    var code_point: u32 = at[0];

                    if (at[0] == '\\' and
                        (isHex(at[1])) and
                        (isHex(at[2])) and
                        (isHex(at[3])) and
                        (isHex(at[4])))
                    {
                        code_point = ((getHex(at[1]) << 12) |
                            (getHex(at[2]) << 8) |
                            (getHex(at[3]) << 4) |
                            (getHex(at[4]) << 0));

                        at += 4;
                    }

                    const advance_x: f32 = char_scale * font.getHorizontalAdvanceForPair(
                        font_info,
                        prev_code_point,
                        code_point,
                    );
                    x += advance_x;

                    if (code_point != ' ') {
                        match_vector.e[@intFromEnum(asset.AssetTagId.UnicodeCodepoint)] = @floatFromInt(code_point);
                        if (font.getBitmapForGlyph(font_info, render_group.assets, code_point)) |bitmap_id| {
                            const info = render_group.assets.getBitmapInfo(bitmap_id);
                            const bitmap_scale = char_scale * @as(f32, @floatFromInt(info.dim[1]));
                            const bitamp_offset: Vector3 = Vector3.new(x, position.y(), z);

                            if (op == .DrawText) {
                                render_group.pushBitmapId(
                                    debug_state.text_transform,
                                    bitmap_id,
                                    bitmap_scale,
                                    bitamp_offset,
                                    color,
                                    null,
                                );
                                render_group.pushBitmapId(
                                    debug_state.shadow_transform,
                                    bitmap_id,
                                    bitmap_scale,
                                    bitamp_offset.plus(Vector3.new(2, -2, 0)),
                                    Color.black(),
                                    null,
                                );
                            } else {
                                std.debug.assert(op == .SizeText);

                                if (render_group.assets.getBitmap(bitmap_id, render_group.generation_id)) |bitmap| {
                                    const dim = render_group.getBitmapDim(
                                        ObjectTransform.defaultFlat(),
                                        bitmap,
                                        bitmap_scale,
                                        bitamp_offset,
                                        1,
                                    );
                                    var glyph_dim: Rectangle2 = Rectangle2.fromMinDimension(
                                        dim.position.xy(),
                                        dim.size,
                                    );
                                    result = result.getUnionWith(&glyph_dim);
                                    rect_found = true;
                                }
                            }
                        }
                    }

                    prev_code_point = code_point;

                    at += 1;
                }
            }
        }
    }

    if (!rect_found) {
        result = Rectangle2.zero();
    }

    return result;
}
