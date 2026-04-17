const shared = @import("shared.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const debug = @import("debug.zig");
const math = @import("math.zig");
const asset = @import("asset.zig");
const renderer = @import("renderer.zig");
const asset_rendering = @import("asset_rendering.zig");
const file_formats = @import("file_formats.zig");
const std = @import("std");

// Types.
const Assets = asset.Assets;
const RenderCommands = renderer.RenderCommands;
const RenderGroupFlags = renderer.RenderGroupFlags;
const GameInput = shared.GameInput;
const DebugElement = debug.DebugElement;
const DebugVariableLink = debug.DebugVariableLink;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const Color = math.Color;
const String = types.String;
const RenderGroup = renderer.RenderGroup;
const LoadedFont = asset.LoadedFont;
const FontId = file_formats.FontId;
const HHAFont = file_formats.HHAFont;
const DevId = types.DevId;
const TransientClipRect = renderer.TransientClipRect;

pub const DevUI = struct {
    font_id: FontId,
    font_info: ?*HHAFont,
    font_scale: f32,
    backing_transform: Vector3,
    shadow_transform: Vector3,
    ui_transform: Vector3,
    text_transform: Vector3,
    tooltip_transform: Vector3,

    ui_space: Rectangle2,

    mouse_position: Vector2,
    last_mouse_position: Vector2,
    delta_mouse_position: Vector2,
    alt_ui: bool,

    interaction: Interaction,

    hot_interaction: Interaction,
    next_hot_interaction: Interaction,

    //
    // Per-frame.
    //

    tooltips: LineBuffer,

    render_group: RenderGroup,
    font: ?*LoadedFont,
    default_clip_rect: Rectangle2,

    pub fn init(self: *DevUI, assets: *Assets) void {
        var match_vector = asset.AssetVector{};
        var weight_vector = asset.AssetVector{};
        match_vector.e[asset.AssetTagId.FontType.toInt()] = @intFromEnum(file_formats.AssetFontType.Debug);
        weight_vector.e[asset.AssetTagId.FontType.toInt()] = 1;
        self.font_id = assets.getBestMatchFont(.Font, &match_vector, &weight_vector).?;

        self.font_info = assets.getFontInfo(self.font_id);
        self.font_scale = 1;

        self.backing_transform = .new(0, 0, -5000);
        self.shadow_transform = .new(0, 0, -4000);
        self.ui_transform = .new(0, 0, -3000);
        self.text_transform = .new(0, 0, -2000);
        self.tooltip_transform = .new(0, 0, -1000);

        self.last_mouse_position = .zero();
        self.alt_ui = false;
        memory.zeroStruct(Interaction, &self.interaction);
        memory.zeroStruct(Interaction, &self.hot_interaction);
        memory.zeroStruct(Interaction, &self.next_hot_interaction);
    }

    pub fn beginFrame(self: *DevUI, assets: *Assets, commands: *RenderCommands, input: *const GameInput) void {
        const width: f32 = @floatFromInt(commands.window_width);
        const height: f32 = @floatFromInt(commands.window_height);

        self.render_group =
            RenderGroup.begin(assets, commands, @intFromEnum(RenderGroupFlags.ClearDepth), null);
        self.font = asset_rendering.pushFont(&self.render_group, self.font_id);
        self.render_group.setCameraTransform(
            1,
            .new(2 / width, 0, 0),
            .new(0, 2 / width, 0),
            .new(0, 0, 1),
            .zero(),
            @intFromEnum(renderer.CameraTransformFlag.IsOrthographic),
            -10000,
            10000,
            null,
            null,
        );

        self.ui_space = .fromCenterDimension(
            .new(0, 0),
            .new(width, height),
        );

        self.default_clip_rect = self.render_group.last_setup.clip_rect;
        self.tooltips.line_count = 0;

        const mouse_clip_position: Vector2 = input.clip_space_mouse_position.xy();
        self.last_mouse_position = self.mouse_position;
        self.alt_ui = input.alt_down;
        self.mouse_position =
            self.render_group.unproject(&self.render_group.game_transform, mouse_clip_position, 0).xy();
        self.delta_mouse_position = self.mouse_position.minus(self.last_mouse_position);
    }

    pub fn endFrame(self: *DevUI) void {
        var mouse_layout: Layout = .begin(self, self.mouse_position);
        drawLineBuffer(self, &self.tooltips, &mouse_layout);
        mouse_layout.end();

        self.render_group.end();
        memory.zeroStruct(Interaction, &self.next_hot_interaction);
    }

    pub fn interactionIsHot(self: *DevUI, interaction: *const Interaction) bool {
        var result: bool = interaction.equals(self.hot_interaction);

        if (interaction.interaction_type == .None) {
            result = false;
        }

        return result;
    }

    pub fn getLineAdvance(self: *DevUI) f32 {
        var result: f32 = 0;
        if (self.font_info) |font_info| {
            result = font_info.getLineAdvance() * self.font_scale;
        }
        return result;
    }

    pub fn getBaseline(self: *DevUI) f32 {
        var result: f32 = 0;
        if (self.font_info) |font_info| {
            result = self.font_scale * font_info.getStartingBaselineY();
        }
        return result;
    }
};

pub const InteractionType = enum(u32) {
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
    ImmediateButton,
    Draggable,
    PickAsset,
};

const InteractionTargetType = enum(u32) {
    uint32,
    bool,
    link,
    position,
    pointer,
    element,
};

pub const Interaction = struct {
    id: DevId = .empty,
    interaction_type: InteractionType = .None,

    target: ?*anyopaque = null,
    pointer_target: ?*?*const anyopaque = null,

    data: union(InteractionTargetType) {
        uint32: u32,
        bool: bool,
        link: ?*DebugVariableLink,
        position: *Vector2,
        pointer: ?*const anyopaque,
        element: ?*DebugElement,
    } = .{ .uint32 = 0 },

    pub const none: Interaction = .{
        .interaction_type = .None,
    };

    pub fn isValid(self: *Interaction) bool {
        return self.interaction_type != .None;
    }

    pub fn equals(self: Interaction, other: Interaction) bool {
        return self.id.equals(other.id) and
            self.interaction_type == other.interaction_type and
            self.target == other.target and
            std.meta.eql(self.data, other.data);
    }

    pub fn clear(self: *Interaction) void {
        self.interaction_type = .None;
        self.data = .{ .pointer = null };
    }

    pub fn elementInteraction(
        ui: *DevUI,
        debug_id: DevId,
        element: *DebugElement,
        interaction_type: InteractionType,
    ) Interaction {
        _ = ui;
        return Interaction{
            .id = debug_id,
            .interaction_type = interaction_type,
            .data = .{ .element = element },
        };
    }

    pub fn fromId(id: DevId, interaction_type: InteractionType) Interaction {
        return Interaction{
            .id = id,
            .interaction_type = interaction_type,
            .data = .{ .bool = false },
        };
    }

    pub fn fromLink(link: *DebugVariableLink, interaction_type: InteractionType) Interaction {
        return Interaction{
            .id = .empty,
            .interaction_type = interaction_type,
            .data = .{ .link = link },
        };
    }

    pub fn setUInt32(debug_id: DevId, target: *anyopaque, value: u32) Interaction {
        const result: Interaction = Interaction{
            .id = debug_id,
            .interaction_type = .SetUInt32,
            .target = target,
            .data = .{ .uint32 = value },
        };
        return result;
    }

    pub fn setBool(debug_id: DevId, target: *anyopaque, value: bool) Interaction {
        const result: Interaction = Interaction{
            .id = debug_id,
            .interaction_type = .SetBool,
            .target = target,
            .data = .{ .bool = value },
        };
        return result;
    }

    pub fn setPointer(debug_id: DevId, target: ?*?*const anyopaque, value: ?*const anyopaque) Interaction {
        const result: Interaction = Interaction{
            .id = debug_id,
            .interaction_type = .SetPointer,
            .pointer_target = target,
            .data = .{ .pointer = value },
        };
        return result;
    }
};

const TextOp = enum {
    DrawText,
    SizeText,
};

pub fn textOp(
    ui: *DevUI,
    op: TextOp,
    text: [:0]const u8,
    position: Vector2,
    color_in: Color,
    opt_z: ?f32,
) Rectangle2 {
    var render_group: *RenderGroup = &ui.render_group;
    const opt_font: ?*asset.LoadedFont = ui.font;
    const font_info: ?*HHAFont = ui.font_info;
    const font_scale: f32 = ui.font_scale;
    const shadow_transform: *Vector3 = &ui.shadow_transform;
    const text_transform: *Vector3 = &ui.text_transform;

    var rect_found = false;
    var color = color_in;
    const z: f32 = opt_z orelse 0;

    var result: Rectangle2 = Rectangle2.invertedInfinity();
    if (opt_font) |font| {
        var match_vector = asset.AssetVector{};
        var prev_code_point: u32 = 0;
        var char_scale = font_scale;
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
                char_scale = font_scale * math.clampf01(c_scale * @as(f32, @floatFromInt(at[2] - '0')));
                at += 3;
            } else {
                var code_point: u32 = at[0];

                if (at[0] == '\\' and
                    (shared.isHex(at[1])) and
                    (shared.isHex(at[2])) and
                    (shared.isHex(at[3])) and
                    (shared.isHex(at[4])))
                {
                    code_point = ((shared.getHex(at[1]) << 12) |
                        (shared.getHex(at[2]) << 8) |
                        (shared.getHex(at[3]) << 4) |
                        (shared.getHex(at[4]) << 0));

                    at += 4;
                }

                const advance_x: f32 = char_scale * font.getHorizontalAdvanceForPair(
                    font_info.?,
                    prev_code_point,
                    code_point,
                );
                x += advance_x;

                if (code_point != ' ') {
                    match_vector.e[@intFromEnum(asset.AssetTagId.UnicodeCodepoint)] = @floatFromInt(code_point);
                    if (font.getBitmapForGlyph(font_info.?, render_group.assets, code_point)) |bitmap_id| {
                        const bitmap_info = render_group.assets.getBitmapInfo(bitmap_id);
                        const bitmap_scale = char_scale * @as(f32, @floatFromInt(bitmap_info.dim[1]));
                        const bitamp_offset: Vector3 = Vector3.new(x, position.y(), z);

                        const align_percentage: Vector2 = bitmap_info.getFirstAlign();

                        if (op == .DrawText) {
                            asset_rendering.pushBitmapId(
                                render_group,
                                bitmap_id,
                                bitmap_scale,
                                shadow_transform.plus(bitamp_offset).plus(Vector3.new(2, -2, 0)),
                                Color.black(),
                                align_percentage,
                                null,
                                null,
                            );
                            asset_rendering.pushBitmapId(
                                render_group,
                                bitmap_id,
                                bitmap_scale,
                                text_transform.plus(bitamp_offset),
                                color,
                                align_percentage,
                                null,
                                null,
                            );
                        } else {
                            std.debug.assert(op == .SizeText);

                            if (render_group.assets.getBitmap(bitmap_id)) |bitmap| {
                                const dim = asset_rendering.getBitmapDim(
                                    bitmap,
                                    bitmap_scale,
                                    bitamp_offset,
                                    align_percentage,
                                    null,
                                    null,
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

    if (!rect_found) {
        result = Rectangle2.zero();
    }

    return result;
}

const SectionPickerMove = enum(u32) {
    Init,
    Keep,
    Previous,
    Next,
};

pub const SectionPicker = struct {
    move: SectionPickerMove,
    previous_section_id: DevId,
    current_section_id: DevId,
    current_name: String,
    current_section_exists: bool,
};

pub const Layout = struct {
    ui: *DevUI = undefined,
    mouse_position: Vector2 = .zero(),
    base_corner: Vector2 = .zero(),

    depth: u32 = 0,

    at: Vector2 = .zero(),
    line_advance: f32 = 0,
    next_y_delta: f32 = 0,
    spacing_x: f32 = 0,
    spacing_y: f32 = 0,
    thickness: f32 = 0,

    no_line_feed: u32 = 0,
    line_initialized: bool = false,

    edit_occurred: bool = false,

    to_execute: Interaction = .none,

    pub fn begin(ui: *DevUI, upper_corner: Vector2) Layout {
        var layout: Layout = .{
            .ui = ui,
            .mouse_position = ui.mouse_position,
            .base_corner = upper_corner,
            .at = upper_corner,
            .line_advance = 0,
            .depth = 0,
            .spacing_x = 4,
            .spacing_y = 4,
            .thickness = 6,
            .line_initialized = false,
        };

        if (ui.font_info) |font_info| {
            layout.line_advance = ui.font_scale * font_info.getLineAdvance();
        }
        return layout;
    }

    pub fn beginBox(ui: *DevUI, box: Rectangle2, opt_backdrop_color: ?Color) Layout {
        const backdrop_color: Color = opt_backdrop_color orelse .new(0, 0, 0, 0.75);
        const upper_corner: Vector2 = .new(box.min.x() + 6, box.max.y() - 6);
        const layout: Layout = begin(ui, upper_corner);

        if (layout.mouse_position.isInRectangle(box)) {
            ui.next_hot_interaction.interaction_type = .NoOp;
        }

        ui.render_group.pushRectangle2(
            box,
            ui.backing_transform,
            backdrop_color,
        );

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
        const null_interaction: Interaction = .{};
        _ = basicTextElement(name, self, null_interaction, Color.white(), Color.white(), self.thickness, null);
    }

    pub fn actionButton(self: *Layout, name: [:0]const u8, interaction: Interaction) void {
        _ = basicTextElement(
            name,
            self,
            interaction,
            Color.new(0.5, 0.5, 0.5, 1),
            Color.white(),
            self.thickness,
            Color.new(0, 0.5, 1, 1),
        );
    }

    pub fn booleanButton(self: *Layout, name: [:0]const u8, highlight: bool, interaction: Interaction) void {
        _ = basicTextElement(
            name,
            self,
            interaction,
            if (highlight) Color.white() else Color.new(0.5, 0.5, 0.5, 1),
            Color.white(),
            self.thickness,
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

    pub fn beginSection(self: *Layout, picker: *SectionPicker, section_id: DevId, name: String) bool {
        switch (picker.move) {
            .Init => {
                picker.current_section_id = section_id;
                picker.move = .Keep;
            },
            .Previous => {
                if (picker.current_section_id.equals(section_id)) {
                    picker.current_section_id = picker.previous_section_id;
                    picker.move = .Keep;
                    picker.current_section_exists = true;
                }
            },
            .Next => {
                if (picker.current_section_id.equals(picker.previous_section_id)) {
                    picker.current_section_id = section_id;
                    picker.move = .Keep;
                }
            },
            else => {},
        }

        if (picker.current_section_id.equals(picker.previous_section_id)) {}

        const result: bool = picker.current_section_id.equals(section_id);
        picker.previous_section_id = section_id;

        if (result) {
            picker.current_name = name;
            picker.current_section_exists = true;
        }

        _ = self;
        return result;
    }

    pub fn endSection(self: *Layout) void {
        _ = self;
    }

    pub fn sectionPicker(self: *Layout, picker: *SectionPicker) void {
        const id: DevId = .fromPointer(@ptrCast(picker));

        var left_label: [:0]const u8 = "<";
        var right_label: [:0]const u8 = ">";

        if (self.buttonWithClassifier(id, @ptrCast(&left_label), left_label, null, null)) {
            picker.move = .Previous;
        }

        if (self.buttonWithClassifier(id, @ptrCast(&right_label), right_label, null, null)) {
            picker.move = .Next;
        }

        self.labelF("%s", .{picker.current_name.data});

        if (!picker.current_section_exists) {
            picker.move = .Init;
        }

        picker.current_section_exists = false;
    }

    pub fn labelF(self: *Layout, comptime format: [*]const u8, args: anytype) void {
        var temp: [64]u8 = undefined;
        const length: usize = shared.formatString(temp.len, &temp, format, args);
        self.label(@ptrCast(temp[0..length]));
    }

    pub fn buttonWithClassifier(
        self: *Layout,
        id: DevId,
        classifier: ?*anyopaque,
        label_text: [:0]const u8,
        opt_enabled: ?bool,
        opt_backdrop_color: ?Color,
    ) bool {
        const backdrop_color: Color = opt_backdrop_color orelse .new(0, 0.35, 0.7, 1);
        const enabled: bool = opt_enabled orelse true;
        var interaction: Interaction = .{
            .id = id,
            .interaction_type = .ImmediateButton,
            .target = classifier,
        };

        var result: bool = false;
        if (id.isValid()) {
            result = interaction.equals(self.to_execute);
        }

        if (enabled) {
            _ = basicTextElement(
                label_text,
                self,
                interaction,
                Color.new(0.75, 0.75, 0.75, 1),
                Color.white(),
                self.thickness,
                backdrop_color,
            );
        } else {
            interaction.interaction_type = .NoOp;
            _ = basicTextElement(
                label_text,
                self,
                interaction,
                Color.new(0.5, 0.5, 0.5, 1),
                Color.new(0.5, 0.5, 0.5, 1),
                self.thickness,
                Color.new(0.25, 0.25, 0.25, 1),
            );
        }

        return result;
    }

    pub fn button(
        self: *Layout,
        id: DevId,
        label_text: [:0]const u8,
        opt_enabled: ?bool,
        opt_backdrop_color: ?Color,
    ) bool {
        const result = self.buttonWithClassifier(id, null, label_text, opt_enabled, opt_backdrop_color);
        return result;
    }

    pub fn beginEditBlock(self: *Layout) EditBlock {
        return .{
            .previous_edit_occurred = self.edit_occurred,
        };
    }

    pub fn endEditBlock(self: *Layout, block: EditBlock) bool {
        const result: bool = self.edit_occurred;
        self.edit_occurred = block.previous_edit_occurred;
        return result;
    }

    pub fn editableBoolean(self: *Layout, id: DevId, label_text: [:0]const u8, value: *bool) void {
        var temp: [64]u8 = undefined;
        const check_mark: [:0]const u8 = if (value.*) "+" else "-";
        const length: usize = shared.formatString(temp.len, &temp, "%s%s", .{ check_mark, label_text });
        const backdrop_color: Color = if (value.*) .new(0.1, 0.5, 0.1, 1) else .new(0.5, 0.1, 0.1, 1);

        if (self.button(id, @ptrCast(temp[0..length]), true, backdrop_color)) {
            self.edit_occurred = true;
            value.* = !value.*;
        }
    }

    pub fn editableType(self: *Layout, id: DevId, label_text: [:0]const u8, value_name: String, value: *u32) void {
        var left_label: [:0]const u8 = "<";
        var right_label: [:0]const u8 = ">";

        if (label_text.len > 0) {
            self.label(label_text);
        }

        if (self.buttonWithClassifier(id, @ptrCast(&left_label), left_label, null, null)) {
            value.* -= 1;
            self.edit_occurred = true;
        }

        if (self.buttonWithClassifier(id, @ptrCast(&right_label), right_label, null, null)) {
            value.* += 1;
            self.edit_occurred = true;
        }

        self.labelF("%s", .{value_name.data});
    }

    pub fn editableSize(self: *Layout, id: DevId, label_text: [:0]const u8, value: *f32) void {
        var temp: [64]u8 = undefined;
        const length: usize = shared.formatString(temp.len, &temp, "%s(%.02f)", .{ label_text, value.* });

        const interaction: Interaction = .{
            .id = id,
            .interaction_type = .Draggable,
        };

        _ = basicTextElement(
            @ptrCast(temp[0..length]),
            self,
            interaction,
            .new(0.8, 0.8, 0.8, 1),
            .white(),
            self.thickness,
            .new(0.7, 0.5, 0.3, 0.5),
        );

        if (interaction.equals(self.ui.interaction)) {
            value.* += 0.001 * value.* * self.ui.delta_mouse_position.y();
            self.edit_occurred = true;
        }
    }

    pub fn editablePositionXY(
        self: *Layout,
        id: DevId,
        label_text: [:0]const u8,
        min_x: f32,
        x: *f32,
        max_x: f32,
        min_y: f32,
        y: *f32,
        max_y: f32,
    ) void {
        var temp: [64]u8 = undefined;
        const length: usize = shared.formatString(temp.len, &temp, "%s(%.02f,%.02f)", .{ label_text, x.*, y.* });

        const interaction: Interaction = .{
            .id = id,
            .interaction_type = .Draggable,
        };

        _ = basicTextElement(
            @ptrCast(temp[0..length]),
            self,
            interaction,
            .new(0.8, 0.8, 0.8, 1),
            .white(),
            self.thickness,
            .new(0.7, 0.5, 0.3, 0.5),
        );

        if (interaction.equals(self.ui.interaction)) {
            const delta_x: f32 = 0.001 * (max_x - min_x);
            const delta_y: f32 = 0.001 * (max_y - min_y);

            x.* = math.clampf(min_x, x.* + delta_x * self.ui.delta_mouse_position.x(), max_x);
            y.* = math.clampf(min_y, y.* + delta_y * self.ui.delta_mouse_position.y(), max_y);
            self.edit_occurred = true;
        }
    }
};

pub const LayoutElement = struct {
    layout: *Layout,
    dimension: *Vector2,
    size: ?*Vector2 = null,
    default_interaction: ?Interaction = null,

    bounds: Rectangle2 = undefined,

    pub fn makeSizable(self: *LayoutElement) void {
        self.size = self.dimension;
    }

    pub fn defaultInteraction(self: *LayoutElement, interaction: Interaction) void {
        self.default_interaction = interaction;
    }

    pub fn end(self: *LayoutElement) void {
        const layout: *Layout = self.layout;
        const ui: *DevUI = layout.ui;

        if (!layout.line_initialized) {
            _ = layout.at.setX(
                layout.base_corner.x() + @as(f32, @floatFromInt(layout.depth)) * 2 * layout.line_advance,
            );
            layout.next_y_delta = 0;
            layout.line_initialized = true;
        }

        var render_group: *RenderGroup = &ui.render_group;
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
                ui.next_hot_interaction = interaction;
            }
        }

        if (self.size) |size| {
            render_group.pushRectangle2(
                Rectangle2.fromMinMax(
                    Vector2.new(total_min_corner.x(), interior_min_corner.y()),
                    Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                ),
                .zero(),
                Color.black(),
            );
            render_group.pushRectangle2(
                Rectangle2.fromMinMax(
                    Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                    Vector2.new(total_max_corner.x(), total_max_corner.y()),
                ),
                .zero(),
                Color.black(),
            );
            render_group.pushRectangle2(
                Rectangle2.fromMinMax(
                    Vector2.new(interior_min_corner.x(), total_min_corner.y()),
                    Vector2.new(interior_max_corner.x(), interior_min_corner.y()),
                ),
                .zero(),
                Color.black(),
            );
            render_group.pushRectangle2(
                Rectangle2.fromMinMax(
                    Vector2.new(interior_min_corner.x(), interior_max_corner.y()),
                    Vector2.new(interior_max_corner.x(), total_max_corner.y()),
                ),
                .zero(),
                Color.black(),
            );

            const size_interaction: Interaction = Interaction{
                .interaction_type = .Resize,
                .data = .{ .position = size },
            };

            const size_box: Rectangle2 = Rectangle2.fromMinMax(
                Vector2.new(interior_max_corner.x(), total_min_corner.y()),
                Vector2.new(total_max_corner.x(), interior_min_corner.y()),
            ).addRadius(Vector2.splat(4));
            const size_box_color: Color =
                if (layout.ui.interactionIsHot(&size_interaction)) Color.new(1, 1, 0, 1) else Color.white();
            render_group.pushRectangle2(size_box, .zero(), size_box_color);

            if (layout.mouse_position.isInRectangle(size_box)) {
                ui.next_hot_interaction = size_interaction;
            }
        }

        layout.advanceElement(total_bounds);
    }
};

pub fn basicTextElement(
    text: [:0]const u8,
    layout: *Layout,
    item_interaction: Interaction,
    opt_color: ?Color,
    opt_hot_color: ?Color,
    opt_border: ?f32,
    opt_backdrop_color: ?Color,
) Vector2 {
    const ui: *DevUI = layout.ui;
    var dim: Vector2 = Vector2.zero();
    const border: f32 = opt_border orelse 0;

    const item_color = opt_color orelse Color.new(0.8, 0.8, 0.8, 1);
    const hot_color = opt_hot_color orelse Color.white();
    const text_bounds = getTextSize(ui, text);
    dim = Vector2.new(text_bounds.getDimension().x() + 2 * border, layout.line_advance + 2 * border);

    var layout_element: LayoutElement = layout.beginElementRectangle(&dim);
    layout_element.defaultInteraction(item_interaction);
    layout_element.end();

    const is_hot: bool = ui.interactionIsHot(&item_interaction);

    const text_position: Vector2 = Vector2.new(
        layout_element.bounds.min.x() + border,
        layout_element.bounds.max.y() - border - ui.getBaseline(),
    );

    if (opt_backdrop_color) |backdrop_color| {
        ui.render_group.pushRectangle2(
            layout_element.bounds,
            ui.backing_transform,
            backdrop_color,
        );
    }
    textOutAt(ui, text, text_position, if (is_hot) hot_color else item_color, null);

    return dim;
}

pub fn textOutAt(ui: *DevUI, text: [:0]const u8, position: Vector2, color: Color, opt_z: ?f32) void {
    _ = textOp(ui, .DrawText, text, position, color, opt_z);
}

pub fn getTextSize(ui: *DevUI, text: [:0]const u8) Rectangle2 {
    return textOp(ui, .SizeText, text, Vector2.zero(), Color.white(), null);
}

pub fn getTextSizeAt(ui: *DevUI, text: [:0]const u8, at: Vector2) Rectangle2 {
    return textOp(ui, .SizeText, text, at, Color.white(), null);
}

pub const TooltipBuffer = struct {
    size: usize = 0,
    data: [*]u8 = undefined,
};

pub const LineBuffer = struct {
    line_count: u32,
    line_text: [16][256]u8,
};

pub fn addLine(buffer: *LineBuffer) TooltipBuffer {
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

pub fn drawLineBuffer(ui: *DevUI, buffer: *LineBuffer, layout: *Layout) void {
    const render_group: *RenderGroup = &ui.render_group;
    const transient_clip_rect: TransientClipRect = .initWith(render_group, ui.default_clip_rect);
    defer transient_clip_rect.restore();

    var tooltip_index: u32 = 0;
    while (tooltip_index < buffer.line_count) : (tooltip_index += 1) {
        const text = buffer.line_text[tooltip_index];
        const text_bounds = getTextSize(layout.ui, @ptrCast(&text));
        var dim: Vector2 = Vector2.new(text_bounds.getDimension().x(), layout.line_advance);

        var layout_element: LayoutElement = layout.beginElementRectangle(&dim);
        layout_element.end();

        layout.ui.render_group.pushRectangle2(
            layout_element.bounds.addRadius(.new(4, 4)),
            layout.ui.tooltip_transform,
            .new(0, 0, 0, 0.75),
        );

        const text_position: Vector2 = Vector2.new(
            layout_element.bounds.min.x(),
            layout_element.bounds.max.y() - ui.getBaseline(),
        );
        // TODO: It's probably the right thing to do to make z flow through the debug system sensibly.
        textOutAt(layout.ui, @ptrCast(&text), text_position, Color.white(), 4000);
    }
}

pub const EditBlock = struct {
    previous_edit_occurred: bool,
};
