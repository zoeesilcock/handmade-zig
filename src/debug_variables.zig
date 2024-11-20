const shared = @import("shared.zig");
const config = @import("config.zig");
const debug = @import("debug.zig");
const math = @import("math.zig");
const std = @import("std");

const DebugState = debug.DebugState;
const DebugVariable = debug.DebugVariable;
const DebugVariableReference = debug.DebugVariableReference;
const DebugVariableType = debug.DebugVariableType;
const DebugVariableGroup = debug.DebugVariableGroup;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;

pub const DebugVariableDefinitionContext = struct {
    state: *DebugState,
    arena: *shared.MemoryArena,

    group: ?*DebugVariableReference,
};

pub fn addDebugUnreferencedVariable(
    debug_state: *DebugState,
    variable_type: DebugVariableType,
    name: [:0]const u8,
) *DebugVariable {
    const variable = debug_state.debug_arena.pushStruct(debug.DebugVariable);
    variable.variable_type = variable_type;
    variable.name = @ptrCast(debug_state.debug_arena.pushCopy(name.len + 1, @ptrCast(@constCast(name))));

    return variable;
}

pub fn addVariableToGroup(debug_state: *DebugState, group_ref: ?*DebugVariableReference, variable: *DebugVariable) *DebugVariableReference {
    const ref: *DebugVariableReference = debug_state.debug_arena.pushStruct(DebugVariableReference);
    ref.variable = variable;
    ref.next = null;
    ref.parent = group_ref;

    if (ref.parent) |parent| {
        var group = parent.variable;
        if (group.data.group.last_child) |last_child| {
            last_child.next = ref;
            group.data.group.last_child = ref;
        } else {
            group.data.group.first_child = ref;
            group.data.group.last_child = ref;
        }
    }

    return ref;
}

fn addDebugVariableReference(context: *DebugVariableDefinitionContext, variable: *DebugVariable) *DebugVariableReference {
    return addVariableToGroup(context.state, context.group, variable);
}

pub fn addDebugVariable(
    context: *DebugVariableDefinitionContext,
    variable_type: DebugVariableType,
    name: [:0]const u8,
) *DebugVariableReference {
    const variable = addDebugUnreferencedVariable(context.state, variable_type, name);
    const ref: *DebugVariableReference = addDebugVariableReference(context, variable);
    return ref;
}

pub fn addRootGroupInternal(debug_state: *DebugState, name: [:0]const u8) *DebugVariable {
    const group: *DebugVariable = addDebugUnreferencedVariable(debug_state, .Group, name);
    group.data = .{ .group = .{
        .expanded = true,
        .first_child = null,
        .last_child = null,
    } };

    return group;
}

pub fn addRootGroup(debug_state: *DebugState, name: [:0]const u8) *DebugVariableReference {
    return addVariableToGroup(debug_state, null, addRootGroupInternal(debug_state, name));
}

pub fn beginVariableGroup(context: *DebugVariableDefinitionContext, name: [:0]const u8) *DebugVariableReference {
    const group = addDebugVariableReference(context, addRootGroupInternal(context.state, name));
    group.variable.data.group.expanded = false;

    context.group = group;

    return group;
}

pub fn endVariableGroup(context: *DebugVariableDefinitionContext) void {
    std.debug.assert(context.group != null);

    context.group = context.group.?.parent;
}

fn addDebugVariableBool(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: bool) *DebugVariableReference {
    var ref: *DebugVariableReference = addDebugVariable(context, .Boolean, name);
    ref.variable.data.bool_value = value;

    return ref;
}

fn addDebugVariableFloat(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: f32) *DebugVariableReference {
    var ref: *DebugVariableReference = addDebugVariable(context, .Float, name);
    ref.variable.data = .{ .float_value = value };

    return ref;
}

fn addDebugVariableVector2(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: Vector2) *DebugVariableReference {
    var ref: *DebugVariableReference = addDebugVariable(context, .Vector2, name);
    ref.variable.data = .{ .vector2_value = value };

    return ref;
}

fn addDebugVariableVector3(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: Vector3) *DebugVariableReference {
    var ref: *DebugVariableReference = addDebugVariable(context, .Vector3, name);
    ref.variable.data = .{ .vector3_value = value };

    return ref;
}

fn addDebugVariableVector4(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: Vector4) *DebugVariableReference {
    var ref: *DebugVariableReference = addDebugVariable(context, .Vector4, name);
    ref.variable.data = .{ .vector4_value = value };

    return ref;
}

pub fn debugVariableListing(comptime name: [:0]const u8, context: *DebugVariableDefinitionContext) *DebugVariableReference {
    var ref: *DebugVariableReference = undefined;

    switch (@TypeOf(@field(config, "DEBUGUI_" ++ name))) {
        bool => {
            ref = addDebugVariableBool(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        f32 => {
            ref = addDebugVariableFloat(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        Vector2 => {
            ref = addDebugVariableVector2(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        Vector3 => {
            ref = addDebugVariableVector3(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        Vector4 => {
            ref = addDebugVariableVector4(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        else => unreachable,
    }

    return ref;
}

pub fn createDebugVariables(context: *DebugVariableDefinitionContext) void {
    var use_debug_cam_ref: *DebugVariableReference = undefined;

    _ = beginVariableGroup(context, "Ground chunks");
    _ = debugVariableListing("GROUND_CHUNK_OUTLINES", context);
    _ = debugVariableListing("GROUND_CHUNK_CHECKERBOARDS", context);
    _ = debugVariableListing("RECOMPUTE_GROUND_CUNKS_ON_EXE_CHANGE", context);
    endVariableGroup(context);

    _ = beginVariableGroup(context, "Particles");
    _ = debugVariableListing("PARTICLE_TEST", context);
    _ = debugVariableListing("PARTICLE_GRID", context);
    endVariableGroup(context);

    _ = beginVariableGroup(context, "Renderer");
    {
        _ = debugVariableListing("TEST_WEIRD_DRAW_BUFFER_SIZE", context);
        _ = debugVariableListing("SHOW_LIGHTING_SAMPLES", context);

        _ = beginVariableGroup(context, "Camera");
        {
            _ = debugVariableListing("USE_DEBUG_CAMERA", context);
            use_debug_cam_ref = debugVariableListing("DEBUG_CAMERA_DISTANCE", context);
            _ = debugVariableListing("USE_ROOM_BASED_CAMERA", context);
        }
        endVariableGroup(context);

        endVariableGroup(context);
    }

    _ = debugVariableListing("FAMILIAR_FOLLOWS_HERO", context);
    _ = debugVariableListing("USE_SPACE_OUTLINES", context);
    _ = debugVariableListing("FAUX_V4", context);

    // _ = addDebugVariableReference(context, use_debug_cam_ref.variable);
}
