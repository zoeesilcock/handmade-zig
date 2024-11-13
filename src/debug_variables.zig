const debug = @import("debug.zig");

const DebugVariable = debug.DebugVariable;

pub const debug_variable_list = [_]DebugVariable{
    DebugVariable.new("DEBUGUI_USE_DEBUG_CAMERA"),
    DebugVariable.new("DEBUGUI_GROUND_CHUNK_OUTLINES"),
    DebugVariable.new("DEBUGUI_GROUND_CHUNK_CHECKERBOARDS"),
    DebugVariable.new("DEBUGUI_RECOMPUTE_GROUND_CUNKS_ON_EXE_CHANGE"),
    DebugVariable.new("DEBUGUI_PARTICLE_TEST"),
    DebugVariable.new("DEBUGUI_PARTICLE_GRID"),
    DebugVariable.new("DEBUGUI_SPACES"),
    DebugVariable.new("DEBUGUI_TEST_WEIRD_DRAW_BUFFER_SIZE"),
    DebugVariable.new("DEBUGUI_FAMILIAR_FOLLOWS_HERO"),
    DebugVariable.new("DEBUGUI_SHOW_LIGHTING_SAMPLES"),
    DebugVariable.new("DEBUGUI_USE_ROOM_BASED_CAMERA"),
};
