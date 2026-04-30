const std = @import("std");
const shared = @import("shared.zig");
const types = @import("types.zig");
const math = @import("math.zig");
const renderer = @import("renderer.zig");
const asset_mod = @import("asset.zig");
const asset_rendering = @import("asset_rendering.zig");
const file_formats = @import("file_formats.zig");
const memory = @import("memory.zig");
const dev_ui = @import("dev_ui.zig");

// Types.
const DevUI = dev_ui.DevUI;
const DevId = types.DevId;
const String = types.String;
const Vector2 = math.Vector2;
const Rectangle3 = math.Rectangle3;
const Color = math.Color;
const GameInput = shared.GameInput;
const DevMode = shared.DevMode;
const PlatformMemoryBlockFlags = shared.PlatformMemoryBlockFlags;
const RenderCommands = renderer.RenderCommands;
const RenderGroup = renderer.RenderGroup;
const RenderGroupFlags = renderer.RenderGroupFlags;
const Assets = asset_mod.Assets;
const LoadedFont = asset_mod.LoadedFont;
const Asset = asset_mod.Asset;
const AssetFile = asset_mod.AssetFile;
const BitmapId = file_formats.BitmapId;
const HHAAsset = file_formats.HHAAsset;
const HHABitmap = file_formats.HHABitmap;
const HHAAlignPoint = file_formats.HHAAlignPoint;
const HHAAlignPointType = file_formats.HHAAlignPointType;
const HHAAnnotation = file_formats.HHAAnnotation;
const LoadedHHAAnnotation = file_formats.LoadedHHAAnnotation;
const HHAFont = file_formats.HHAFont;
const FontId = file_formats.FontId;
const MemoryArena = memory.MemoryArena;

const HHA_ALIGN_POINT_TYPE_COUNT = file_formats.HHA_ALIGN_POINT_TYPE_COUNT;
const HHA_BITMAP_ALIGN_POINT_COUNT = file_formats.HHA_BITMAP_ALIGN_POINT_COUNT;

const EditableAsset = struct {
    id: DevId,
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

    highlight_color: Color = .zero(),
    highlight_id: DevId = .empty,

    editor: *InGameEditor,

    pub fn addHit(self: *EditableHitTest, id: DevId, asset_index: u32, sort_key: f32) void {
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

                dest.id = id;
                dest.asset_index = asset_index;
                dest.sort_key = sort_key;

                added = true;
                break;
            }
        }

        if (!added and dest_group.asset_count < dest_group.assets.len) {
            const dest: *EditableAsset = &dest_group.assets[dest_group.asset_count];
            dest_group.asset_count += 1;

            dest.id = id;
            dest.asset_index = asset_index;
            dest.sort_key = sort_key;
        }
    }

    pub fn shouldHitTest(self: *EditableHitTest) bool {
        return self.dest_group != null;
    }

    pub fn shouldDrawAlignPoint(self: *EditableHitTest, ap_index: u32) bool {
        var result: bool = false;
        if (ap_index < self.editor.draw_align_point.len) {
            result = self.editor.draw_align_point[ap_index];
        }
        return result;
    }
};

const InGameEditType = enum {
    None,
    AlignPointEdit,
};

const InGameEditChangeType = enum(u32) {
    ChangeFrom = 0,
    ChangeTo = 1,
};
const IN_GAME_EDIT_CHANGE_TYPE_COUNT = @typeInfo(InGameEditChangeType).@"enum".fields.len;

const AlignPointEdit = struct {
    asset_index: u32,
    align_point_index: u32,
    change: [IN_GAME_EDIT_CHANGE_TYPE_COUNT]HHAAlignPoint,
};

const InGameEdit = struct {
    next: ?*InGameEdit,
    prev: ?*InGameEdit,

    edit_type: InGameEditType,
    operation: union {
        align_point_edit: AlignPointEdit,
    },

    // TODO: We may want to group edits together, so that undo can undo more than one change at a time. This
    // facilitates undoing edit operations as the user preceives them rather than how they're implemented internally
    // in the case of edits that edit multiple things at once.

    pub fn isEmpty(self: *InGameEdit) bool {
        const result: bool = self.next == self;
        std.debug.assert((result and self.prev == self) or (!result and self.prev != self));
        return result;
    }

    pub fn sentinelize(self: *InGameEdit) void {
        self.prev = self;
        self.next = self;
    }

    pub fn link(self: *InGameEdit, edit: *InGameEdit) void {
        edit.prev = self;
        edit.next = self.next;

        edit.prev.?.next = edit;
        edit.next.?.prev = edit;
    }

    pub fn unlink(self: *InGameEdit) void {
        self.prev.?.next = self.next;
        self.next.?.prev = self.prev;

        self.sentinelize();
    }

    pub fn popFirst(self: *InGameEdit) ?*InGameEdit {
        var result: ?*InGameEdit = null;

        if (self.next != self) {
            result = self.next;
            self.next.?.unlink();
        }

        return result;
    }

    pub fn pushFirst(self: *InGameEdit, edit: *InGameEdit) void {
        self.link(edit);
    }

    pub fn hasEdit(self: *InGameEdit, match: ?*InGameEdit) bool {
        var result: bool = (self == match);

        var test_edit: ?*InGameEdit = self.next;
        while (!result and test_edit != self) : (test_edit = test_edit.?.next) {
            result = (test_edit == match);
        }

        return result;
    }
};

pub const InGameEditor = struct {
    undo_memory: MemoryArena = .{},
    assets: *Assets,

    active_group: EditableAssetGroup = .empty,
    hot_group: EditableAssetGroup = .empty,

    dev_mode: DevMode,
    active_asset_index: u32 = 0,
    highlight_id: DevId,

    main_section: dev_ui.SectionPicker,

    clean_edit: ?*InGameEdit, // Tells us whether we are "dirty" or not.
    undo_sentinel: InGameEdit,
    redo_sentinel: InGameEdit,
    in_progress_sentinel: InGameEdit,

    to_execute: dev_ui.Interaction,
    next_to_execute: dev_ui.Interaction,

    draw_align_point: [HHA_BITMAP_ALIGN_POINT_COUNT]bool,

    pub fn init(self: *InGameEditor, assets: *Assets) void {
        self.undo_memory.allocation_flags |= @intFromEnum(PlatformMemoryBlockFlags.NotRestored);
        self.assets = assets;

        self.undo_sentinel.sentinelize();
        self.redo_sentinel.sentinelize();
        self.in_progress_sentinel.sentinelize();
        self.clean_edit = self.undo_sentinel.next;

        self.draw_align_point = [1]bool{true} ** HHA_BITMAP_ALIGN_POINT_COUNT;
    }

    fn isDirty(self: *InGameEditor) bool {
        return self.undo_sentinel.next != self.clean_edit;
    }

    fn undoAvailable(self: *InGameEditor) bool {
        return !self.undo_sentinel.isEmpty();
    }

    fn redoAvailable(self: *InGameEditor) bool {
        return !self.redo_sentinel.isEmpty();
    }

    fn alignPointFromAssetAndIndex(assets: *Assets, asset_index: u32, point_index: u32) ?*HHAAlignPoint {
        var result: ?*HHAAlignPoint = null;
        if (assets.getAsset(asset_index)) |asset| {
            std.debug.assert(asset.hha.type == .Bitmap);
            const bitmap: *HHABitmap = &asset.hha.info.bitmap;
            result = &bitmap.align_points[point_index];
        }
        return result;
    }

    fn getOrCreatedEditInProgress(self: *InGameEditor, match: *InGameEdit) *InGameEdit {
        var result: ?*InGameEdit = null;
        var test_edit: *InGameEdit = self.in_progress_sentinel.next.?;
        while (result == null and test_edit != &self.in_progress_sentinel) : (test_edit = test_edit.next.?) {
            if (test_edit.edit_type == match.edit_type) {
                switch (test_edit.edit_type) {
                    .AlignPointEdit => {
                        if (match.operation.align_point_edit.asset_index ==
                            test_edit.operation.align_point_edit.asset_index and
                            match.operation.align_point_edit.align_point_index ==
                                test_edit.operation.align_point_edit.align_point_index)
                        {
                            result = test_edit;
                        }
                        break;
                    },
                    else => {},
                }
            }
        }

        if (result == null) {
            result = self.undo_memory.pushStruct(InGameEdit, null);
            result.?.* = match.*;
            self.in_progress_sentinel.pushFirst(result.?);
        }

        return result.?;
    }

    fn getAssetForEdit(self: *InGameEditor, edit: *InGameEdit) ?*Asset {
        var result: ?*Asset = null;
        switch (edit.edit_type) {
            .AlignPointEdit => {
                result = self.assets.getAsset(edit.operation.align_point_edit.asset_index);
            },
            else => {},
        }
        return result;
    }

    fn editAlignPoint(
        self: *InGameEditor,
        asset_index: u32,
        point_index: u32,
        align_point_type: HHAAlignPointType,
        to_parent: bool,
        size: f32,
        position_percent: Vector2,
    ) void {
        if (alignPointFromAssetAndIndex(self.assets, asset_index, point_index)) |point| {
            var match: InGameEdit = .{
                .next = null,
                .prev = null,
                .edit_type = .AlignPointEdit,
                .operation = .{
                    .align_point_edit = .{
                        .asset_index = asset_index,
                        .align_point_index = point_index,
                        .change = undefined,
                    },
                },
            };
            match.operation.align_point_edit.change[@intFromEnum(InGameEditChangeType.ChangeFrom)] = point.*;

            var edit: *InGameEdit = self.getOrCreatedEditInProgress(&match);

            point.set(align_point_type, to_parent, size, position_percent);
            edit.operation.align_point_edit.change[@intFromEnum(InGameEditChangeType.ChangeTo)] = point.*;
        }
    }

    fn applyEditChange(
        self: *InGameEditor,
        edit: *InGameEdit,
        change_type: InGameEditChangeType,
    ) void {
        switch (edit.edit_type) {
            .AlignPointEdit => {
                const align_edit: *AlignPointEdit = &edit.operation.align_point_edit;
                const point: ?*HHAAlignPoint = alignPointFromAssetAndIndex(
                    self.assets,
                    align_edit.asset_index,
                    align_edit.align_point_index,
                );
                point.?.* = align_edit.change[@intFromEnum(change_type)];
            },
            else => unreachable,
        }
    }

    fn undo(self: *InGameEditor) void {
        const edit: ?*InGameEdit = self.undo_sentinel.popFirst();
        self.applyEditChange(edit.?, .ChangeFrom);
        self.redo_sentinel.pushFirst(edit.?);
    }

    fn redo(self: *InGameEditor) void {
        const edit: ?*InGameEdit = self.redo_sentinel.popFirst();
        self.applyEditChange(edit.?, .ChangeTo);
        self.undo_sentinel.pushFirst(edit.?);
    }

    pub fn beginHitTest(self: *InGameEditor, input: *GameInput, dev_mode: DevMode) EditableHitTest {
        var result: EditableHitTest = .{ .editor = self };

        self.dev_mode = dev_mode;

        if (self.dev_mode == .EditingAssets) {
            result.dest_group = &self.hot_group;
            result.dest_group.?.asset_count = 0;

            result.highlight_color = .new(1, 1, 0, 1);
            result.highlight_id = self.highlight_id;
            result.clip_space_mouse_position = input.clip_space_mouse_position.xy();
        }

        return result;
    }

    fn findCleanEditList(self: *InGameEditor) ?*InGameEdit {
        var result: ?*InGameEdit = null;
        if (self.undo_sentinel.hasEdit(self.clean_edit)) {
            result = &self.undo_sentinel;
        } else {
            result = &self.redo_sentinel;
            std.debug.assert(self.redo_sentinel.hasEdit(self.clean_edit));
        }
        return result;
    }

    fn saveAllChanges(self: *InGameEditor) void {
        const list: ?*InGameEdit = self.findCleanEditList();
        var edit: ?*InGameEdit = list.?.next;
        while (edit != self.clean_edit) : (edit = edit.?.next) {
            if (self.getAssetForEdit(edit.?)) |asset| {
                if (self.assets.getFile(asset.file_index)) |file| {
                    file.modified = true;
                }
            }
        }

        self.clean_edit = self.undo_sentinel.next;

        asset_mod.writeAllHHAModifications(self.assets);
    }

    pub fn updateAndRender(self: *InGameEditor, ui: *DevUI) void {
        if (self.dev_mode == .EditingAssets) {
            var layout: dev_ui.Layout = .beginBox(
                ui,
                .fromMinMax(ui.ui_space.min, .new(ui.ui_space.min.x() + 700, ui.ui_space.max.y())),
                null,
            );
            layout.to_execute = self.to_execute;

            layout.beginRow();
            var asset_index_index: u32 = 0;
            while (asset_index_index < self.active_group.asset_count) : (asset_index_index += 1) {
                const edit_asset: *EditableAsset = &self.active_group.assets[asset_index_index];
                const bitmap_id: BitmapId = .{ .value = edit_asset.asset_index };
                if (layout.bitmapButton(
                    edit_asset.id,
                    edit_asset,
                    64,
                    64,
                    bitmap_id,
                    true,
                    edit_asset.asset_index == self.active_asset_index,
                )) {
                    self.setActiveAsset(edit_asset);
                }
            }
            layout.endRow();

            layout.beginRow();
            if (layout.button(.fromPointerAndLine(self, @src()), "UNDO", self.undoAvailable(), null)) {
                self.undo();
            }
            if (layout.button(.fromPointerAndLine(self, @src()), "REDO", self.redoAvailable(), null)) {
                self.redo();
            }

            layout.sectionPicker(&self.main_section);
            layout.endRow();

            var hha_section_name: []const u8 = "HHA";
            if (layout.beginSection(
                &self.main_section,
                .fromPointerAndLine(@ptrCast(&hha_section_name), @src()),
                .fromSlice(hha_section_name),
            )) {
                layout.beginRow();
                if (layout.button(.fromPointerAndLine(self, @src()), "SAVE", self.isDirty(), null)) {
                    self.saveAllChanges();
                }
                if (layout.button(.fromPointerAndLine(self, @src()), "IMPORT & SAVE", true, null)) {
                    asset_mod.importChangedAssets(self.assets);
                    self.saveAllChanges();
                }
                layout.endRow();

                layout.beginRow();
                layout.endRow();

                layout.beginRow();
                if (layout.button(.fromPointerAndLine(self, @src()), "REVERT", self.isDirty(), null)) {
                    if (self.undo_sentinel.hasEdit(self.clean_edit)) {
                        while (self.clean_edit != self.undo_sentinel.next) {
                            self.undo();
                        }
                    } else {
                        std.debug.assert(self.redo_sentinel.hasEdit(self.clean_edit));
                        while (self.clean_edit != self.undo_sentinel.next) {
                            self.redo();
                        }
                    }
                }
                layout.endRow();
                layout.endSection();
            }

            switch (self.dev_mode) {
                .EditingAssets => self.assetEditor(&layout),
                else => {},
            }

            if (self.to_execute.isValid() and !self.next_to_execute.isValid()) {
                while (!self.in_progress_sentinel.isEmpty()) {
                    self.undo_sentinel.pushFirst(
                        self.in_progress_sentinel.popFirst().?,
                    );
                }
            }
            self.to_execute = self.next_to_execute;
            memory.zeroStruct(dev_ui.Interaction, &self.next_to_execute);
        }
    }

    pub fn interact(self: *InGameEditor, ui: *DevUI, input: *GameInput) void {
        if (!ui.next_hot_interaction.isValid()) {
            ui.next_hot_interaction.interaction_type = .PickAsset;
        }

        const transition_count: u32 = input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].half_transitions;
        var mouse_button: bool = input.mouse_buttons[shared.GameInputMouseButton.Left.toInt()].ended_down;
        if (@mod(transition_count, 2) != 0) {
            mouse_button = !mouse_button;
        }

        var transition_index: u32 = 0;
        while (transition_index <= transition_count) : (transition_index += 1) {
            var mouse_move: bool = false;
            var mouse_down: bool = false;
            var mouse_up: bool = false;
            if (transition_index == 0) {
                mouse_move = true;
            } else {
                mouse_down = mouse_button;
                mouse_up = !mouse_button;
            }

            var end_interaction: bool = false;

            switch (ui.interaction.interaction_type) {
                .ImmediateButton, .Draggable => {
                    if (mouse_up) {
                        self.next_to_execute = ui.interaction;
                        end_interaction = true;
                    }
                },
                .PickAsset => {
                    if (mouse_up) {
                        self.active_group = self.hot_group;

                        if (self.active_group.asset_count > 0) {
                            self.setActiveAsset(&self.hot_group.assets[0]);
                        } else {
                            self.setActiveAsset(null);
                        }
                        end_interaction = true;
                    }
                },
                .None => {
                    ui.hot_interaction = ui.next_hot_interaction;

                    if (mouse_down) {
                        ui.interaction = ui.hot_interaction;
                    }
                },
                else => {
                    if (mouse_up) {
                        end_interaction = true;
                    }
                },
            }

            if (end_interaction) {
                ui.interaction.clear();
            }

            mouse_button = !mouse_button;
        }
    }

    fn assetEditor(self: *InGameEditor, layout: *dev_ui.Layout) void {
        const asset_index: u32 = self.active_asset_index;

        if (self.assets.getAsset(self.active_asset_index)) |asset| {
            const hha: *const HHAAsset = &asset.hha;

            switch (hha.type) {
                .Bitmap => {
                    const bitmap: *HHABitmap = &asset.hha.info.bitmap;
                    var section_name: []const u8 = "Alignment Points";
                    if (layout.beginSection(
                        &self.main_section,
                        .fromPointerAndLine(@ptrCast(&section_name), @src()),
                        .fromSlice(section_name),
                    )) {
                        var point_index: u32 = 0;
                        while (point_index < bitmap.align_points.len) : (point_index += 1) {
                            const point: *HHAAlignPoint = &bitmap.align_points[point_index];

                            var to_parent: bool = point.isToParent();
                            const align_point_type: HHAAlignPointType = point.getType();
                            var align_point_type_int: u32 = @intFromEnum(align_point_type);
                            var position_percent: Vector2 = point.getPositionPercent();
                            var size: f32 = point.getSize();

                            var point_name: [64]u8 = undefined;
                            const point_name_length: usize =
                                shared.formatString(point_name.len, &point_name, "[%d]", .{point_index});

                            layout.beginRow();
                            const draw_toggle: *bool = &self.draw_align_point[point_index];
                            const button_color: Color = if (draw_toggle.*)
                                shared.getDebugColor4(point_index, null)
                            else
                                .new(0.25, 0.25, 0.25, 1);
                            if (layout.button(
                                .fromPointerAndLine(draw_toggle, @src()),
                                @ptrCast(point_name[0..point_name_length]),
                                align_point_type_int != @intFromEnum(HHAAlignPointType.None),
                                button_color,
                            )) {
                                draw_toggle.* = !draw_toggle.*;
                            }

                            if (align_point_type_int == @intFromEnum(HHAAlignPointType.None)) {
                                if (layout.button(.fromPointerAndLine(point, @src()), "[ADD]", null, null)) {
                                    self.editAlignPoint(
                                        asset_index,
                                        point_index,
                                        .Default,
                                        false,
                                        1,
                                        .new(0.5, 0.5),
                                    );
                                }
                            } else {
                                const change_block: dev_ui.EditBlock = layout.beginEditBlock();
                                if (layout.button(.fromPointerAndLine(point, @src()), "[DEL]", null, null)) {
                                    self.editAlignPoint(
                                        asset_index,
                                        point_index,
                                        .None,
                                        false,
                                        1,
                                        .new(0.5, 0.5),
                                    );
                                }
                                layout.editableBoolean(.fromPointerAndLine(point, @src()), "ToPar", &to_parent);
                                layout.editableSize(.fromPointerAndLine(point, @src()), "S", &size);
                                layout.editablePositionXY(
                                    .fromPointerAndLine(point, @src()),
                                    "P",
                                    0,
                                    &position_percent.values[0],
                                    1,
                                    0,
                                    &position_percent.values[1],
                                    1,
                                );
                                layout.editableType(
                                    .fromPointerAndLine(point, @src()),
                                    "",
                                    file_formats.alignPointNameFromType(align_point_type),
                                    &align_point_type_int,
                                );

                                if (layout.endEditBlock(change_block)) {
                                    if (align_point_type_int == 0) {
                                        align_point_type_int = HHA_ALIGN_POINT_TYPE_COUNT - 1;
                                    } else if (align_point_type_int >= HHA_ALIGN_POINT_TYPE_COUNT) {
                                        align_point_type_int = 1;
                                    }

                                    self.editAlignPoint(
                                        asset_index,
                                        point_index,
                                        @enumFromInt(align_point_type_int),
                                        to_parent,
                                        size,
                                        position_percent,
                                    );
                                }
                            }
                            layout.endRow();
                        }
                        layout.endSection();
                    }
                },
                else => {},
            }
        }
    }

    fn setActiveAsset(self: *InGameEditor, opt_asset: ?*EditableAsset) void {
        if (opt_asset) |asset| {
            self.highlight_id = asset.id;
            self.active_asset_index = asset.asset_index;
        } else {
            self.highlight_id = .empty;
            self.active_asset_index = 0;
        }
    }

    pub fn endHitTest(self: *InGameEditor, input: *GameInput, hit_test: *EditableHitTest) void {
        _ = self;
        _ = input;
        _ = hit_test;
    }
};
