const std = @import("std");
const shared = @import("shared.zig");
const math = @import("math.zig");
const renderer = @import("renderer.zig");
const asset_mod = @import("asset.zig");
const asset_rendering = @import("asset_rendering.zig");
const file_formats = @import("file_formats.zig");

// Types.
const Vector2 = math.Vector2;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const GameInput = shared.GameInput;
const RenderCommands = renderer.RenderCommands;
const RenderGroup = renderer.RenderGroup;
const RenderGroupFlags = renderer.RenderGroupFlags;
const Assets = asset_mod.Assets;
const LoadedFont = asset_mod.LoadedFont;
const AssetFile = asset_mod.AssetFile;
const HHAAsset = file_formats.HHAAsset;
const HHABitmap = file_formats.HHABitmap;
const HHAAlignPoint = file_formats.HHAAlignPoint;
const HHAAlignPointType = file_formats.HHAAlignPointType;
const HHAAnnotation = file_formats.HHAAnnotation;
const LoadedHHAAnnotation = file_formats.LoadedHHAAnnotation;
const HHAFont = file_formats.HHAFont;
const FontId = file_formats.FontId;

const EditableAsset = struct {
    asset_index: u32,
    sort_key: f32, // Less is better.
};

const EditableAssetGroup = struct {
    asset_count: u32,
    assets: [8]EditableAsset,

    pub const empty: EditableAssetGroup = .{ .asset_count = 0, .assets = undefined };
};

pub const EditableHitTest = struct {
    dest_group: ?*EditableAssetGroup = null,
    clip_space_mouse_position: Vector2 = .zero(),

    highlight_asset_index: u32 = 0,
    highlight_color: Color = .zero(),

    pub fn addHit(self: *EditableHitTest, asset_index: u32, sort_key: f32) void {
        const dest_group: *EditableAssetGroup = self.dest_group.?;
        var test_index: u32 = 0;

        var added: bool = false;
        while (test_index < dest_group.asset_count) : (test_index += 1) {
            const dest: *EditableAsset = &dest_group.assets[test_index];
            if (dest.sort_key > sort_key) {
                if (dest_group.asset_count < dest_group.assets.len) {
                    dest_group.asset_count += 1;
                }

                var copy_index: u32 = dest_group.asset_count - 1;
                while (copy_index > test_index) : (copy_index -= 1) {
                    dest_group.assets[copy_index] = dest_group.assets[copy_index - 1];
                }

                dest.asset_index = asset_index;
                dest.sort_key = sort_key;

                added = true;
                break;
            }
        }

        if (!added and dest_group.asset_count < dest_group.assets.len) {
            const dest: *EditableAsset = &dest_group.assets[dest_group.asset_count];
            dest_group.asset_count += 1;

            dest.asset_index = asset_index;
            dest.sort_key = sort_key;
        }
    }

    pub fn shouldHitTest(self: *EditableHitTest) bool {
        return self.dest_group != null;
    }
};

const InGameEditorMode = enum(u32) {
    None,
    EditingAssets,
};

pub const InGameEditor = struct {
    active_group: EditableAssetGroup = .empty,
    hot_group: EditableAssetGroup = .empty,

    mode: InGameEditorMode = .None,
    active_asset_index: u32 = 0,

    pub fn beginHitTest(self: *InGameEditor, input: *GameInput) EditableHitTest {
        var result: EditableHitTest = .{};

        if (input.f_key_pressed[9]) {
            self.mode = .None;
        } else if (input.f_key_pressed[10]) {
            self.mode = .EditingAssets;
        }

        if (self.mode == .EditingAssets) {
            result.dest_group = &self.hot_group;
            result.clip_space_mouse_position = input.clip_space_mouse_position.xy();
            result.highlight_asset_index = self.active_asset_index;
            result.highlight_color = .new(1, 1, 0, 1);
            result.dest_group.?.asset_count = 0;
        }

        return result;
    }

    pub fn updateAndRender(self: *InGameEditor, commands: *RenderCommands, assets: *Assets) void {
        if (self.mode != .None) {
            const width: f32 = @floatFromInt(commands.window_width);
            const height: f32 = @floatFromInt(commands.window_height);

            var render_group: RenderGroup =
                RenderGroup.begin(assets, commands, @intFromEnum(RenderGroupFlags.ClearDepth), null);
            render_group.setCameraTransform(
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

            var match_vector = asset_mod.AssetVector{};
            var weight_vector = asset_mod.AssetVector{};
            match_vector.e[asset_mod.AssetTagId.FontType.toInt()] = @intFromEnum(file_formats.AssetFontType.Debug);
            weight_vector.e[asset_mod.AssetTagId.FontType.toInt()] = 1;
            const font_id: ?FontId = assets.getBestMatchFont(.Font, &match_vector, &weight_vector);
            const font: ?*LoadedFont = asset_rendering.pushFont(&render_group, font_id);
            const font_info: *HHAFont = assets.getFontInfo(font_id.?);

            _ = font;
            _ = font_info;
            _ = height;
            switch (self.mode) {
                .EditingAssets => self.assetEditor(assets),
                else => {},
            }

            render_group.end();
        }
    }

    pub fn assetEditor(self: *InGameEditor, assets: *Assets) void {
        const asset_index: u32 = self.active_asset_index;
        _ = asset_index;
        _ = assets;

        // if (assets.getAsset(self.active_asset_index)) |asset| {
        //     const hha: *HHAAsset = &asset.hha;
        //
        //     switch (hha.type) {
        //         .Bitmap => {
        //             const bitmap: *HHABitmap = &asset.bitmap;
        //             layout.beginSection("Alignment Points");
        //             var point_index: u32 = 0;
        //             while (point_index < bitmap.alignment_points.len) : (point_index += 1) {
        //                 const point: *HHAAlignPoint = bitmap.align_points[point_index];
        //
        //                 var to_parent: bool = point.isToParent();
        //                 var align_point_type: HHAAlignPointType = point.getType();
        //                 var position_percent: Vector2 = point.getPositionPercent();
        //                 var size: f32 = point.getSize();
        //
        //                 layout.beginLine();
        //                 layout.labelF("[%d]", point_index);
        //
        //                 if (point.align_type == .None) {
        //                     if (layout.button("[Unused]")) {
        //                         setAlignPoint(point, .Default, false, 1, .new(0.5, 0.5));
        //                     }
        //                 } else {
        //                     layout.beginEditBlock();
        //                     layout.editableBoolean("ToParent", &to_parent);
        //                     layout.editableType("Type", file_formats.alignPointNameFromType(align_point_type), &align_point_type);
        //                     layout.editableSize("Size", &size);
        //                     layout.editablePositionXY(
        //                         "PercentP",
        //                         0,
        //                         &position_percent.x,
        //                         1,
        //                         0,
        //                         &position_percent.y,
        //                         1,
        //                     );
        //
        //                     if (layout.endEditBlock()) {
        //                         setAlignPoint(point, align_point_type, to_parent, size, position_percent);
        //                     }
        //                     if (layout.button("[DELETE]")) {
        //                         setAlignPoint(point, .None, to_parent, size, position_percent);
        //                     }
        //                 }
        //                 layout.endLine();
        //             }
        //             layout.endSection();
        //         },
        //         else => {},
        //     }
        // }
    }

    pub fn endHitTest(self: *InGameEditor, input: *GameInput, hit_test: *EditableHitTest) void {
        _ = input;

        if (hit_test.shouldHitTest()) {
            self.active_asset_index = 0;
            if (hit_test.dest_group.?.asset_count > 0) {
                self.active_asset_index = hit_test.dest_group.?.assets[0].asset_index;
            }
        }
    }
};
