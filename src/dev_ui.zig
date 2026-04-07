const shared = @import("shared.zig");
const types = @import("types.zig");
const debug = @import("debug.zig");
const math = @import("math.zig");
const asset = @import("asset.zig");
const renderer = @import("renderer.zig");
const asset_rendering = @import("asset_rendering.zig");
const file_formats = @import("file_formats.zig");
const std = @import("std");

// Types.
const DebugState = debug.DebugState;
const DebugElement = debug.DebugElement;
const DebugVariableLink = debug.DebugVariableLink;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle2 = math.Rectangle2;
const Color = math.Color;
const String = types.String;
const RenderGroup = renderer.RenderGroup;
const ObjectTransform = renderer.ObjectTransform;
const LoadedFont = asset.LoadedFont;
const HHAFont = file_formats.HHAFont;
const DevId = types.DevId;

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
    id: DevId = .empty(),
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

    pub fn equals(self: *const Interaction, other: *const Interaction) bool {
        return self.id.equals(other.id) and
            self.interaction_type == other.interaction_type and
            self.target == other.target and
            std.meta.eql(self.data, other.data);
    }

    pub fn isHot(self: *const Interaction, debug_state: *const DebugState) bool {
        var result: bool = self.equals(&debug_state.hot_interaction);

        if (self.interaction_type == .None) {
            result = false;
        }

        return result;
    }

    pub fn elementInteraction(
        debug_state: *DebugState,
        debug_id: DevId,
        element: *DebugElement,
        interaction_type: InteractionType,
    ) Interaction {
        _ = debug_state;
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
            .id = .empty(),
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

pub const Context = struct {
    render_group: *RenderGroup,
    font: ?*LoadedFont,
    font_info: ?*HHAFont,
    font_scale: f32,

    shadow_transform: ObjectTransform,
    text_transform: ObjectTransform,

    pub fn fromDebugState(debug_state: *DebugState) Context {
        return .{
            .render_group = &debug_state.render_group,
            .font = debug_state.debug_font,
            .font_info = debug_state.debug_font_info,
            .font_scale = debug_state.font_scale,
            .shadow_transform = debug_state.shadow_transform,
            .text_transform = debug_state.text_transform,
        };
    }
};

pub fn textOp(
    context: *Context,
    op: TextOp,
    text: [:0]const u8,
    position: Vector2,
    color_in: Color,
    opt_z: ?f32,
) Rectangle2 {
    var render_group: *RenderGroup = context.render_group;
    const opt_font: ?*asset.LoadedFont = context.font;
    const font_info: ?*HHAFont = context.font_info;
    const font_scale: f32 = context.font_scale;
    const shadow_transform: *ObjectTransform = &context.shadow_transform;
    const text_transform: *ObjectTransform = &context.text_transform;

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

                        if (op == .DrawText) {
                            asset_rendering.pushBitmapId(
                                render_group,
                                shadow_transform,
                                bitmap_id,
                                bitmap_scale,
                                bitamp_offset.plus(Vector3.new(2, -2, 0)),
                                Color.black(),
                                null,
                                null,
                                null,
                            );
                            asset_rendering.pushBitmapId(
                                render_group,
                                text_transform,
                                bitmap_id,
                                bitmap_scale,
                                bitamp_offset,
                                color,
                                null,
                                null,
                                null,
                            );
                        } else {
                            std.debug.assert(op == .SizeText);

                            if (render_group.assets.getBitmap(bitmap_id)) |bitmap| {
                                const dim = asset_rendering.getBitmapDim(
                                    &ObjectTransform.defaultFlat(),
                                    bitmap,
                                    bitmap_scale,
                                    bitamp_offset,
                                    1,
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

pub const Layout = struct {
    pub fn beginSection(self: *Layout, label: []const u8) void {
        _ = self;
        _ = label;
    }

    pub fn endSection(self: *Layout) void {
        _ = self;
    }

    pub fn beginLine(self: *Layout) void {
        _ = self;
    }

    pub fn endLine(self: *Layout) void {
        _ = self;
    }

    pub fn labelF(self: *Layout, fmt: []const u8, args: anytype) void {
        _ = self;
        _ = fmt;
        _ = args;
    }

    pub fn button(self: *Layout, label: []const u8, opt_enabled: ?bool) bool {
        const enabled: bool = opt_enabled orelse true;
        _ = self;
        _ = label;
        _ = enabled;
        return false;
    }

    pub fn beginEditBlock(self: *Layout) EditBlock {
        _ = self;
        return .{};
    }

    pub fn endEditBlock(self: *Layout, block: EditBlock) bool {
        _ = self;
        _ = block;
        return false;
    }

    pub fn editableBoolean(self: *Layout, label: []const u8, value: *bool) void {
        _ = self;
        _ = label;
        _ = value;
    }
    pub fn editableType(self: *Layout, label: []const u8, value_name: String, value: *u32) void {
        _ = self;
        _ = label;
        _ = value_name;
        _ = value;
    }
    pub fn editableSize(self: *Layout, label: []const u8, value: *f32) void {
        _ = self;
        _ = label;
        _ = value;
    }
    pub fn editablePositionXY(
        self: *Layout,
        label: []const u8,
        min_x: f32,
        x: *f32,
        max_x: f32,
        min_y: f32,
        y: *f32,
        max_y: f32,
    ) void {
        _ = self;
        _ = label;
        _ = min_x;
        _ = x;
        _ = max_x;
        _ = min_y;
        _ = y;
        _ = max_y;
    }
};

pub const EditBlock = struct {
    //
};
