const shared = @import("shared.zig");
const config = @import("config.zig");
const debug = @import("debug.zig");
const std = @import("std");

const DebugState = debug.DebugState;
const DebugVariable = debug.DebugVariable;
const DebugVariableType = debug.DebugVariableType;
const DebugVariableGroup = debug.DebugVariableGroup;

const DebugVariableDefinitionContext = struct {
    state: *DebugState,
    arena: *shared.MemoryArena,

    group: ?*DebugVariable,
};

fn addDebugVariable(
    context: *DebugVariableDefinitionContext,
    variable_type: DebugVariableType,
    name: [:0]const u8,
) *DebugVariable {
    const variable = context.arena.pushStruct(debug.DebugVariable);
    variable.variable_type = variable_type;
    variable.name = name;
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

fn beginVariableGroup(context: *DebugVariableDefinitionContext, name: [:0]const u8) *DebugVariable {
    const group_variable: *DebugVariable = addDebugVariable(context, .Group, name);
    group_variable.data = .{ .group = .{
        .expanded = false,
        .first_child = null,
        .last_child = null,
    } };

    context.group = group_variable;

    return group_variable;
}

fn addDebugVariableBool(context: *DebugVariableDefinitionContext, name: [:0]const u8, value: bool) *DebugVariable {
    var variable: *DebugVariable = addDebugVariable(context, .Bool, name);
    variable.data.bool_value = value;

    return variable;
}

fn endVariableGroup(context: *DebugVariableDefinitionContext) void {
    std.debug.assert(context.group != null);

    context.group = context.group.?.parent;
}

pub fn debugVariableListing(comptime name: [:0]const u8, context: *DebugVariableDefinitionContext) *DebugVariable {
    var variable: *DebugVariable = addDebugVariable(context, .Boolean, name);
    variable.data.bool_value = @field(config, "DEBUGUI_" ++ name);

    return variable;
}

pub fn createDebugVariables(state: *DebugState) void {
    var context: DebugVariableDefinitionContext = .{
        .state = state,
        .arena = &state.debug_arena,
        .group = null,
    };

    context.group = beginVariableGroup(&context, "Root");

    _ = beginVariableGroup(&context, "Ground chunks");
    _ = debugVariableListing("GROUND_CHUNK_OUTLINES", &context);
    _ = debugVariableListing("GROUND_CHUNK_CHECKERBOARDS", &context);
    _ = debugVariableListing("RECOMPUTE_GROUND_CUNKS_ON_EXE_CHANGE", &context);
    endVariableGroup(&context);

    _ = beginVariableGroup(&context, "Particles");
    _ = debugVariableListing("PARTICLE_TEST", &context);
    _ = debugVariableListing("PARTICLE_GRID", &context);
    endVariableGroup(&context);

    _ = beginVariableGroup(&context, "Renderer");
    {
        _ = debugVariableListing("TEST_WEIRD_DRAW_BUFFER_SIZE", &context);
        _ = debugVariableListing("SHOW_LIGHTING_SAMPLES", &context);

        _ = beginVariableGroup(&context, "Camera");
        {
            _ = debugVariableListing("USE_DEBUG_CAMERA", &context);
            _ = debugVariableListing("USE_ROOM_BASED_CAMERA", &context);
        }
        endVariableGroup(&context);

        endVariableGroup(&context);
    }

    _ = debugVariableListing("FAMILIAR_FOLLOWS_HERO", &context);
    _ = debugVariableListing("SPACE_OUTLINES", &context);

    state.root_group = context.group;
}
