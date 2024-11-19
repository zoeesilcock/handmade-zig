const shared = @import("shared.zig");
const config = @import("config.zig");
const debug = @import("debug.zig");
const math = @import("math.zig");
const std = @import("std");

const DebugState = debug.DebugState;
const DebugVariable = debug.DebugVariable;
const DebugVariableType = debug.DebugVariableType;
const DebugVariableGroup = debug.DebugVariableGroup;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;

pub const DebugVariableDefinitionContext = struct {
    state: *DebugState,
    arena: *shared.MemoryArena,

    group: ?*DebugVariable,
};

pub fn addDebugVariable(
    context: *DebugVariableDefinitionContext,
    variable_type: DebugVariableType,
    name: [:0]const u8,
) *DebugVariable {
    const variable = context.arena.pushStruct(debug.DebugVariable);
    variable.variable_type = variable_type;
    variable.name = @ptrCast(context.arena.pushCopy(name.len + 1, @ptrCast(@constCast(name))));
    variable.next = null;
    variable.parent = context.group;

    if (context.group) |group_variable| {
        if (group_variable.data.group.last_child) |last_child| {
            last_child.next = variable;
            group_variable.data.group.last_child = variable;
        } else {
            group_variable.data.group.first_child = variable;
            group_variable.data.group.last_child = variable;
        }
    }

    return variable;
}

pub fn beginVariableGroup(context: *DebugVariableDefinitionContext, name: [:0]const u8) *DebugVariable {
    const group_variable: *DebugVariable = addDebugVariable(context, .Group, name);
    group_variable.data = .{ .group = .{
        .expanded = false,
        .first_child = null,
        .last_child = null,
    } };

    context.group = group_variable;

    return group_variable;
}

pub fn endVariableGroup(context: *DebugVariableDefinitionContext) void {
    std.debug.assert(context.group != null);

    context.group = context.group.?.parent;
}

fn addDebugVariableBool(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: bool) *DebugVariable {
    var variable: *DebugVariable = addDebugVariable(context, .Boolean, name);
    variable.data.bool_value = value;

    return variable;
}

fn addDebugVariableFloat(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: f32) *DebugVariable {
    var variable: *DebugVariable = addDebugVariable(context, .Float, name);
    variable.data = .{ .float_value = value };

    return variable;
}

fn addDebugVariableVector2(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: Vector2) *DebugVariable {
    var variable: *DebugVariable = addDebugVariable(context, .Vector2, name);
    variable.data = .{ .vector2_value = value };

    return variable;
}

fn addDebugVariableVector3(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: Vector3) *DebugVariable {
    var variable: *DebugVariable = addDebugVariable(context, .Vector3, name);
    variable.data = .{ .vector3_value = value };

    return variable;
}

fn addDebugVariableVector4(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: Vector4) *DebugVariable {
    var variable: *DebugVariable = addDebugVariable(context, .Vector4, name);
    variable.data = .{ .vector4_value = value };

    return variable;
}

pub fn debugVariableListing(comptime name: [:0]const u8, context: *DebugVariableDefinitionContext) *DebugVariable {
    var variable: *DebugVariable = undefined;

    switch (@TypeOf(@field(config, "DEBUGUI_" ++ name))) {
        bool => {
            variable = addDebugVariableBool(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        f32 => {
            variable = addDebugVariableFloat(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        Vector2 => {
            variable = addDebugVariableVector2(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        Vector3 => {
            variable = addDebugVariableVector3(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        Vector4 => {
            variable = addDebugVariableVector4(context, name, @field(config, "DEBUGUI_" ++ name));
        },
        else => unreachable,
    }

    return variable;
}

pub fn createDebugVariables(context: *DebugVariableDefinitionContext) void {
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
            _ = debugVariableListing("DEBUG_CAMERA_DISTANCE", context);
            _ = debugVariableListing("USE_ROOM_BASED_CAMERA", context);
        }
        endVariableGroup(context);

        endVariableGroup(context);
    }

    _ = debugVariableListing("FAMILIAR_FOLLOWS_HERO", context);
    _ = debugVariableListing("USE_SPACE_OUTLINES", context);
    _ = debugVariableListing("FAUX_V4", context);
}
