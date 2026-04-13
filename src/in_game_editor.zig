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
const MemoryArena = memory.MemoryArena;
const PlatformMemoryBlockFlags = shared.PlatformMemoryBlockFlags;
const ObjectTransform = renderer.ObjectTransform;

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
};

const InGameEditorMode = enum(u32) {
    None,
    EditingAssets,
};

pub const InGameEditor = struct {
    undo_memory: MemoryArena = .{},
    assets: *Assets,

    active_group: EditableAssetGroup = .empty,
    hot_group: EditableAssetGroup = .empty,

    mode: InGameEditorMode = .None,
    active_asset_index: u32 = 0,
    highlight_id: DevId,

    clean_undo_sentinel_next: ?*InGameEdit, // Tells us whether we are "dirty" or not.
    undo_sentinel: InGameEdit,
    redo_sentinel: InGameEdit,

    pub fn init(self: *InGameEditor, assets: *Assets) void {
        self.undo_memory.allocation_flags |= @intFromEnum(PlatformMemoryBlockFlags.NotRestored);
        self.assets = assets;

        self.undo_sentinel.sentinelize();
        self.redo_sentinel.sentinelize();
        self.clean_undo_sentinel_next = self.undo_sentinel.next;
    }

    fn isDirty(self: *InGameEditor) bool {
        return self.undo_sentinel.next != self.clean_undo_sentinel_next;
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

    fn allocateEdit(self: *InGameEditor, T: type) *T {
        var result: *InGameEdit = self.undo_memory.pushStruct(InGameEdit, null);
        result.edit_type = @field(InGameEditType, shared.shortTypeName(T));
        result.sentinelize();
        self.undo_sentinel.pushFirst(result);

        return @ptrCast(&result.operation);
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
        var edit: *AlignPointEdit = self.allocateEdit(AlignPointEdit);
        edit.asset_index = asset_index;
        edit.align_point_index = point_index;

        if (alignPointFromAssetAndIndex(self.assets, asset_index, point_index)) |point| {
            edit.change[@intFromEnum(InGameEditChangeType.ChangeFrom)] = point.*;
            point.set(align_point_type, to_parent, size, position_percent);
            edit.change[@intFromEnum(InGameEditChangeType.ChangeTo)] = point.*;
        }

        std.debug.assert(self.undo_sentinel.prev.?.next != null);
        std.debug.assert(self.undo_sentinel.next.?.prev != null);
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
            result.highlight_id = self.highlight_id;
            result.highlight_color = .new(1, 1, 0, 1);
            result.dest_group.?.asset_count = 0;
        }

        return result;
    }

    pub fn updateAndRender(self: *InGameEditor, ui: *DevUI) void {
        if (self.mode != .None) {
            var layout: dev_ui.Layout = .begin(ui, .new(0, 0));

            layout.beginRow();
            if (layout.button(.fromPointerAndLine(self, @src()), "SAVE", self.isDirty())) {
                self.clean_undo_sentinel_next = self.undo_sentinel.next;
            }

            if (layout.button(.fromPointerAndLine(self, @src()), "REVERT", self.isDirty())) {
                while (self.clean_undo_sentinel_next != self.undo_sentinel.next) {
                    self.undo();
                }
            }
            layout.endRow();

            layout.beginRow();
            if (layout.button(.fromPointerAndLine(self, @src()), "UNDO", self.undoAvailable())) {
                self.undo();
            }
            if (layout.button(.fromPointerAndLine(self, @src()), "REDO", self.redoAvailable())) {
                self.redo();
            }
            layout.endRow();

            switch (self.mode) {
                .EditingAssets => self.assetEditor(&layout),
                else => {},
            }
        }
    }

    pub fn interact(self: *InGameEditor, ui: *DevUI, input: *GameInput) void {
        if (!ui.next_hot_interaction.isValid()) {
            ui.next_hot_interaction.interaction_type = .PickAsset;
        }

        std.debug.assert(self.undo_sentinel.prev.?.next != null);
        std.debug.assert(self.undo_sentinel.next.?.prev != null);

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

            switch (ui.interaction.interaction_type) {
                .ImmediateButton => {
                    if (mouse_up) {
                        ui.next_id_to_execute = ui.interaction.id;
                        ui.interaction.clear();
                    }
                },
                .PickAsset => {
                    if (mouse_up) {
                        if (self.hot_group.asset_count > 0) {
                            self.highlight_id = self.hot_group.assets[0].id;
                            self.active_asset_index = self.hot_group.assets[0].asset_index;
                        } else {
                            self.highlight_id = .empty;
                            self.active_asset_index = 0;
                        }
                        ui.interaction.clear();
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
                        ui.interaction.clear();
                    }
                },
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
                    layout.beginSection("Alignment Points");
                    var point_index: u32 = 0;
                    while (point_index < bitmap.align_points.len) : (point_index += 1) {
                        const point: *HHAAlignPoint = &bitmap.align_points[point_index];

                        var to_parent: bool = point.isToParent();
                        const align_point_type: HHAAlignPointType = point.getType();
                        var align_point_type_int: u32 = @intFromEnum(align_point_type);
                        var position_percent: Vector2 = point.getPositionPercent();
                        var size: f32 = point.getSize();

                        layout.beginRow();
                        layout.labelF("[%d]", .{point_index});

                        if (align_point_type_int == @intFromEnum(HHAAlignPointType.None)) {
                            if (layout.button(.fromPointerAndLine(point, @src()), "[unused]", null)) {
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
                            layout.editableBoolean("ToParent", &to_parent);
                            layout.editableType(
                                "Type",
                                file_formats.alignPointNameFromType(align_point_type),
                                &align_point_type_int,
                            );
                            layout.editableSize("Size", &size);
                            layout.editablePositionXY(
                                "PercentP",
                                0,
                                &position_percent.values[0],
                                1,
                                0,
                                &position_percent.values[1],
                                1,
                            );

                            if (layout.endEditBlock(change_block)) {
                                self.editAlignPoint(
                                    asset_index,
                                    point_index,
                                    @enumFromInt(align_point_type_int),
                                    to_parent,
                                    size,
                                    position_percent,
                                );
                            }
                            if (layout.button(.fromPointerAndLine(point, @src()), "[DELETE]", null)) {
                                self.editAlignPoint(
                                    asset_index,
                                    point_index,
                                    .None,
                                    false,
                                    1,
                                    .new(0.5, 0.5),
                                );
                            }
                        }
                        layout.endRow();
                    }
                    layout.endSection();
                },
                else => {},
            }
        }
    }

    pub fn endHitTest(self: *InGameEditor, input: *GameInput, hit_test: *EditableHitTest) void {
        _ = self;
        _ = input;
        _ = hit_test;
    }
};
