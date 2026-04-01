const shared = @import("shared.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const world = @import("world.zig");
const world_mode = @import("world_mode.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const renderer = @import("renderer.zig");
const asset = @import("asset.zig");
const file_formats = shared.file_formats;
const audio = @import("audio.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const cutscene = @import("cutscene.zig");
const random = @import("random.zig");
const config = @import("config.zig");
const debug_interface = @import("debug_interface.zig");
const in_game_editor = @import("in_game_editor.zig");
const std = @import("std");

/// TODO: An overview of upcoming tasks.
///
/// * Graphics upgrade
///     * Fix unproject! (getCameraRectangleAtTarget)
///         * Handle divide-by-z in unproject.
///         * Fix clip rectangles for debug UI.
///         * Fix Z settings for debug UI.
///     * Fix Z buffer to be better resolution - what's the best plan here?
///     * Re-enable alpha fading.
///     * Re-enable fog.
///     * Particle systems.
///         * Bug with sliding relative to the grid during camera offset?
///     * Transition to real artwork.
///         * Clean up our notion of multi-part-entities and how they are animated.
///     * Lighting.
///
/// * Implement multiple sim regions per frame.
///     * Fix has table routines in SimRegion to not have to do clears on returns (just have them return a bool
///     as to wheter they found the entry or not).
///     * Eliminate world mode from sim step entirely.
///     * Per-entity clocking.
///     * Sim region merging? For multiple players?
///
/// * Collision detection?
///     * Clean up predicate proliferation! Can we make a nice clean set of flag rules so that it's easy to understnad
///     how things work in terms of special handling? This may involve making the iteration handle everything
///     instead of handling overlap outside and so on.
///     * Transient collusion rules. Clear based on flag.
///         * Allow non-transient rules to override transient ones.
///         * Entry/exit?
///     * Robustness/shape definition?
///     * Implement reprojection to handle interpenetration.
///     * Things pushing other things.
///
///
/// Production:
///
/// * Game.
///     * Rudimentary world generation to understand which elements will be needed.
///         * Placement of background things.
///         * Connectivity?
///             * Large-scale AI athfinding.
///         * None-overlapping?
///         * Map display.
///     * Rigorous definition of how things move, when things trigger, etc.
/// * Metagame/save game?
///     * How do you enter a save slot? Multiple profiles and potential "menu world".
///     * Persistent unlocks, etc.
///     * De we allo save games? Probably yes, just for "pausing".
///     * Continuous save for crash recovery?
///
///
/// Clean up:
///
/// * Debug code.
///     * Diagramming.
///     * Draw tile chunks so we can verify things are aligned / in the chunks we want them to be in etc.
///     * Frame view not showing bad frames?
///
/// * Hardware Rendering
///     * Shaders?
///
///
/// * Pixel buffer objects for texture downloads?
///
/// * Audio.
///     * Fix clicking bug at end of samples.
///
///
/// Extra credit.
///
/// * Serious optimization of the software renderer.
///

// Build options.
const INTERNAL = shared.INTERNAL;

var global_config = &@import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Rectangle2i = math.Rectangle2i;
const Color = math.Color;
const Color3 = math.Color3;
const MemoryArena = memory.MemoryArena;
const TemporaryMemory = memory.TemporaryMemory;
const ArenaPushParams = memory.ArenaPushParams;
const State = shared.State;
const WorldPosition = world.WorldPosition;
const AddLowEntityResult = shared.AddLowEntityResult;
const RenderGroup = renderer.RenderGroup;
const Assets = asset.Assets;
const AssetTypeId = asset.AssetTypeId;
const AssetTagId = file_formats.AssetTagId;
const AssetFontType = file_formats.AssetFontType;
const LoadedBitmap = asset.LoadedBitmap;
const LoadedFont = asset.LoadedFont;
const Particle = shared.Particle;
const ParticleCel = shared.ParticleCel;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;
const EditableHitTest = in_game_editor.EditableHitTest;

pub export fn updateAndRender(
    platform: shared.Platform,
    game_memory: *shared.Memory,
    input: *shared.GameInput,
    render_commands: *renderer.RenderCommands,
) void {
    shared.platform = platform;

    if (INTERNAL) {
        shared.debug_global_memory = game_memory;
        shared.global_debug_table = game_memory.debug_table;

        DebugInterface.debugBeginDataBlock(@src(), "Renderer");
        {
            DebugInterface.debugValue(@src(), &render_commands.settings.multisample_debug, "Renderer_MultisampleDebug");
            DebugInterface.debugValue(@src(), &render_commands.settings.multisampling_hint, "Renderer_Multisampling");
            DebugInterface.debugValue(@src(), &render_commands.settings.pixelation_hint, "Renderer_Pixelation");
            DebugInterface.debugValue(@src(), &render_commands.settings.lighting_disabled, "Renderer_LightingDisabled");
            DebugInterface.debugBeginDataBlock(@src(), "Camera");
            {
                DebugInterface.debugValue(@src(), &global_config.Renderer_Camera_UseDebug, "Renderer_Camera_UseDebug");
                DebugInterface.debugValue(@src(), &global_config.Renderer_Camera_DebugDistance, "Renderer_Camera_DebugDistance");
                DebugInterface.debugValue(@src(), &global_config.Renderer_Camera_RoomBased, "Renderer_Camera_RoomBased");
            }
            DebugInterface.debugEndDataBlock(@src());
            DebugInterface.debugBeginDataBlock(@src(), "Lighting");
            {
                DebugInterface.debugValue(@src(), &global_config.Renderer_Lighting_ShowReflectors, "Renderer_Lighting_ShowReflectors");
            }
            DebugInterface.debugEndDataBlock(@src());
        }
        DebugInterface.debugEndDataBlock(@src());

        DebugInterface.debugBeginDataBlock(@src(), "AI/Familiar");
        {
            DebugInterface.debugValue(@src(), &global_config.AI_Familiar_FollowsHero, "AI_Familiar_FollowsHero");
        }
        DebugInterface.debugEndDataBlock(@src());

        DebugInterface.debugBeginDataBlock(@src(), "Particles");
        {
            DebugInterface.debugValue(@src(), &global_config.Particles_Test, "Particles_Test");
            DebugInterface.debugValue(@src(), &global_config.Particles_ShowGrid, "Particles_ShowGrid");
        }
        DebugInterface.debugEndDataBlock(@src());

        DebugInterface.debugBeginDataBlock(@src(), "Simulation");
        {
            DebugInterface.debugValue(@src(), &global_config.Simulation_TimestepPercentage, "TimestepPercentage");
            DebugInterface.debugValue(@src(), &global_config.Simulation_VisualizeCollisionVolumes, "VisualizeCollisionVolumes");
            DebugInterface.debugValue(@src(), &global_config.Simulation_InspectSelectedEntity, "InspectSelectedEntity");
        }
        DebugInterface.debugEndDataBlock(@src());

        DebugInterface.debugBeginDataBlock(@src(), "Profile");
        {
            DebugInterface.debugUIElement(@src(), .LastFrameInfo, "LastFrameInfo");
            DebugInterface.debugUIElement(@src(), .DebugMemoryInfo, "DebugMemoryInfo");
            DebugInterface.debugUIElement(@src(), .TopClocksList, "updateAndRender");
            DebugInterface.debugUIElement(@src(), .FrameSlider, "FrameSlider");
        }
        DebugInterface.debugEndDataBlock(@src());
    }

    TimedBlock.beginFunction(@src(), .GameUpdateAndRender);
    defer TimedBlock.endFunction(@src(), .GameUpdateAndRender);

    // Clamp the delta time for the frame so that we don't have too high or too low frame rates in any circumstance.
    if (input.frame_delta_time > 0.1) {
        input.frame_delta_time = 0.1;
    } else if (input.frame_delta_time < 0.001) {
        input.frame_delta_time = 0.001;
    }
    input.frame_delta_time *= (config.global_config.Simulation_TimestepPercentage / 100);

    var state: *State = game_memory.game_state orelse undefined;
    if (game_memory.game_state == null) {
        state = memory.bootstrapPushStruct(
            State,
            "total_arena",
            null,
            ArenaPushParams.aligned(@alignOf(State), true),
        );
        game_memory.game_state = state;

        state.audio_state.initialize(&state.audio_arena);

        state.high_priority_queue = game_memory.high_priority_queue;
        state.low_priority_queue = game_memory.low_priority_queue;

        var task_index: u32 = 0;
        while (task_index < state.tasks.len) : (task_index += 1) {
            var task: *shared.TaskWithMemory = &state.tasks[task_index];
            task.being_used = false;
        }

        state.assets = Assets.allocate(types.megabytes(256), state, game_memory.texture_queue);

        state.frame_arena_temp = state.frame_arena.beginTemporaryMemory();
    }

    state.frame_arena.endTemporaryMemory(state.frame_arena_temp);
    std.debug.assert(state.frame_arena.current_block == null);
    state.frame_arena.checkArena();

    state.frame_arena_temp = state.frame_arena.beginTemporaryMemory();

    DebugInterface.debugBeginDataBlock(@src(), "Memory");
    {
        DebugInterface.debugValue(@src(), &state.mode_arena, "ModeArena");
        DebugInterface.debugValue(@src(), &state.audio_arena, "AudioArena");
        DebugInterface.debugValue(@src(), &state.frame_arena, "FrameArena");
    }
    DebugInterface.debugEndDataBlock(@src());

    if (state.current_mode == .None) {
        cutscene.playIntroCutscene(state);

        // This automatically skips the intro cutscene.
        if (global_config.Game_SkipIntro) {
            input.controllers[0].start_button.ended_down = true;
            input.controllers[0].start_button.half_transitions = 1;
        }
    }

    // if (false) {
    //     var music_volume = Vector2.zero();
    //     _ = music_volume.setY(math.safeRatio0(input.mouse_x, @as(f32, @floatFromInt(buffer.width))));
    //     _ = music_volume.setX(1.0 - music_volume.y());
    //     state.audio_state.changeVolume(state.music, 0.01, music_volume);
    // }

    var hit_test: EditableHitTest = state.editor.beginHitTest(input);

    var rerun: bool = true;
    while (rerun) {
        switch (state.current_mode) {
            .None => {},
            .TitleScreen => {
                rerun = cutscene.updateAndRenderTitleScreen(
                    state,
                    render_commands,
                    input,
                    state.mode.title_screen,
                );
            },
            .Cutscene => {
                rerun = cutscene.updateAndRenderCutscene(
                    state,
                    render_commands,
                    input,
                    state.mode.cutscene,
                );
            },
            .World => {
                rerun = world_mode.updateAndRenderWorld(
                    state,
                    state.mode.world,
                    input,
                    render_commands,
                    &hit_test,
                );
            },
        }
    }

    state.editor.endHitTest(input, &hit_test);
    state.editor.updateAndRender(render_commands, state.assets);

    if (state.current_mode == .World) {
        state.mode.world.world.arena.checkArena();
    }

    state.mode_arena.checkArena();
}

pub export fn debugFrameEnd(game_memory: *shared.Memory, input: shared.GameInput, commands: *renderer.RenderCommands) void {
    shared.debugFrameEnd(game_memory, input, commands);
}

pub export fn getSoundSamples(
    game_memory: *shared.Memory,
    sound_buffer: *shared.SoundOutputBuffer,
) void {
    if (game_memory.game_state) |state| {
        state.audio_state.outputPlayingSounds(sound_buffer, state.assets, &state.frame_arena);
        // audio.outputSineWave(sound_buffer, shared.MIDDLE_C, state);
    }
}

pub fn beginTaskWithMemory(game_state: *State, depends_on_game_mode: bool) ?*shared.TaskWithMemory {
    var found_task: ?*shared.TaskWithMemory = null;

    var task_index: u32 = 0;
    while (task_index < game_state.tasks.len) : (task_index += 1) {
        var task = &game_state.tasks[task_index];

        if (!task.being_used) {
            task.being_used = true;
            task.depends_on_game_mode = depends_on_game_mode;
            task.memory_flush = task.arena.beginTemporaryMemory();

            found_task = task;

            break;
        }
    }

    return found_task;
}

pub fn endTaskWithMemory(task: *shared.TaskWithMemory) void {
    task.arena.endTemporaryMemory(task.memory_flush);
    @atomicStore(bool, &task.being_used, false, .release);
}

fn clearBitmap(bitmap: *LoadedBitmap) void {
    if (bitmap.memory) |*bitmap_memory| {
        const total_bitmap_size: u32 = @intCast(bitmap.*.width * bitmap.*.height * shared.BITMAP_BYTES_PER_PIXEL);
        memory.zeroSize(total_bitmap_size, bitmap_memory.*);
    }
}

fn makeEmptyBitmap(arena: *MemoryArena, width: i32, height: i32, clear_to_zero: bool) LoadedBitmap {
    const result = arena.pushStruct(LoadedBitmap, null);

    result.alignment_percentage = Vector2.splat(0.5);
    result.width_over_height = math.safeRatio1(@floatFromInt(width), @floatFromInt(height));

    result.width = types.safeTruncateToUInt16(width);
    result.height = types.safeTruncateToUInt16(height);
    result.pitch = result.width * shared.BITMAP_BYTES_PER_PIXEL;

    const total_bitmap_size: u32 =
        @as(u32, @intCast(result.width)) * @as(u32, @intCast(result.height)) * shared.BITMAP_BYTES_PER_PIXEL;
    result.memory = @ptrCast(arena.pushSize(total_bitmap_size, ArenaPushParams.aligned(16, clear_to_zero)));

    if (clear_to_zero) {
        clearBitmap(result);
    }

    return result.*;
}

fn makeSphereNormalMap(bitmap: *LoadedBitmap, roughness: f32, cx: f32, cy: f32) void {
    const inv_width: f32 = 1.0 / (@as(f32, @floatFromInt(bitmap.width - 1)));
    const inv_height: f32 = 1.0 / (@as(f32, @floatFromInt(bitmap.height - 1)));

    var row: [*]u8 = @ptrCast(bitmap.memory);
    var y: u32 = 0;
    while (y < bitmap.height) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x: u32 = 0;
        while (x < bitmap.width) : (x += 1) {
            const bitmap_uv = Vector2.new(
                inv_width * @as(f32, @floatFromInt(x)),
                inv_height * @as(f32, @floatFromInt(y)),
            );

            const nx: f32 = cx * (2.0 * bitmap_uv.x() - 1.0);
            const ny: f32 = cy * (2.0 * bitmap_uv.y() - 1.0);

            const root_term: f32 = 1.0 - nx * nx - ny * ny;
            var normal = Vector3.new(0, 0.7071067811865475244, 0.7071067811865475244);
            var nz: f32 = 0;
            if (root_term >= 0) {
                nz = intrinsics.squareRoot(root_term);
                normal = Vector3.new(nx, ny, nz);
            }

            var color = Color.new(
                255.0 * (0.5 * (normal.x() + 1.0)),
                255.0 * (0.5 * (normal.y() + 1.0)),
                255.0 * (0.5 * (normal.z() + 1.0)),
                255.0 * roughness,
            );

            pixel[0] = color.packColorBGRA();

            pixel += 1;
        }

        row += @as(usize, @intCast(bitmap.pitch));
    }
}

fn makeSphereDiffuseMap(bitmap: *LoadedBitmap, cx: f32, cy: f32) void {
    const inv_width: f32 = 1.0 / (@as(f32, @floatFromInt(bitmap.width - 1)));
    const inv_height: f32 = 1.0 / (@as(f32, @floatFromInt(bitmap.height - 1)));

    var row: [*]u8 = @ptrCast(bitmap.memory);
    var y: u32 = 0;
    while (y < bitmap.height) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x: u32 = 0;
        while (x < bitmap.width) : (x += 1) {
            const bitmap_uv = Vector2.new(
                inv_width * @as(f32, @floatFromInt(x)),
                inv_height * @as(f32, @floatFromInt(y)),
            );

            const nx: f32 = cx * (2.0 * bitmap_uv.x() - 1.0);
            const ny: f32 = cy * (2.0 * bitmap_uv.y() - 1.0);

            const root_term: f32 = 1.0 - nx * nx - ny * ny;
            var alpha: f32 = 0;
            if (root_term >= 0) {
                alpha = 1;
            }

            const base_color = Color3.splat(0);
            alpha *= 255.0;

            var color = Color.new(
                alpha * base_color.r(),
                alpha * base_color.g(),
                alpha * base_color.b(),
                alpha,
            );

            pixel[0] = color.packColorBGRA();

            pixel += 1;
        }

        row += @as(usize, @intCast(bitmap.pitch));
    }
}

fn makePyramidNormalMap(bitmap: *LoadedBitmap, roughness: f32) void {
    var row: [*]u8 = @ptrCast(bitmap.memory);
    var y: u32 = 0;
    while (y < bitmap.height) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x: u32 = 0;
        while (x < bitmap.width) : (x += 1) {
            const seven = 0.7071067811865475244;
            var normal = Vector3.new(0, 0, seven);
            const inv_x: u32 = (@as(u32, @intCast(bitmap.width)) - 1) - x;
            if (x < y) {
                if (inv_x < y) {
                    _ = normal.setX(-seven);
                } else {
                    _ = normal.setY(seven);
                }
            } else {
                if (inv_x < y) {
                    _ = normal.setY(-seven);
                } else {
                    _ = normal.setX(seven);
                }
            }

            var color = Color.new(
                255.0 * (0.5 * (normal.x() + 1.0)),
                255.0 * (0.5 * (normal.y() + 1.0)),
                255.0 * (0.5 * (normal.z() + 1.0)),
                255.0 * roughness,
            );

            pixel[0] = color.packColorBGRA();

            pixel += 1;
        }

        row += @as(usize, @intCast(bitmap.pitch));
    }
}
