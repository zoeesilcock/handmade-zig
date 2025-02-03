const shared = @import("shared.zig");
const world = @import("world.zig");
const world_mode = @import("world_mode.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const rendergroup = @import("rendergroup.zig");
const asset = @import("asset.zig");
const file_formats = @import("file_formats");
const audio = @import("audio.zig");
const intrinsics = @import("intrinsics.zig");
const math = @import("math.zig");
const cutscene = @import("cutscene.zig");
const random = @import("random.zig");
const config = @import("config.zig");
const debug_interface = @import("debug_interface.zig");
const std = @import("std");

/// TODO: An overview of upcoming tasks.
///
/// * Debug code.
///     * Logging.
///     * Diagramming.
///     * Switches, sliders etc.
///     * Draw tile chunks so we can verify things are aligned / in the chunks we want them to be in etc.
///     * Thread visualization.
///
/// * Audio.
///     * Fix clicking bug at end of samples.
///
/// * Rendering.
///     * Real projections with solid concept of project/unproject.
///     * Straighten out all coordinate systems!
///         * Screen.
///         * World.
///         * Texture.
///     * Particle systems.
///     * Lighting.
///     * Final optimization.
///     * Hardware Rendering
///         * Shaders?
///         * Render-to-texture?
///
/// ----
///
/// Architecture exploration:
///
/// * Z-axis.
///     * Need to make a solid concept of ground levels so thet camer can be freely placed in Z and have multiple
///     ground levels in one sim region.
///     * Concept of ground in the collision loop so it can handle collisions coming onto and off of stairwells.
///     * Make sure flying things can go over low walls.
///     * How it this rendered.
///     * Z fudge!
/// * Collision detection?
///     * Fix sword collisions!
///     * Clean up predicate proliferation! Can we make a nice clean set of flag rules so that it's easy to understnad
///     how things work in terms of special handling? This may involve making the iteration handle everything
///     instead of handling overlap outside and so on.
///     * Transient collusion rules. Clear based on flag.
///         * Allow non-transient rules to override transient ones.
///         * Entry/exit?
///     * Robustness/shape definition?
///     * Implement reprojection to handle interpenetration.
///     * Things pushing other things.
/// * Animation.
///     * Skeletal animation.
/// * Implement multiple sim regions per frame.
///     * Per-entity clocking.
///     * Sim region merging? For multiple players?
///     * Simple zoomed-out view for testing?
/// * AI.
///     * Rudimentary monster behaviour example.
///     * Pathfinding.
///     * AI storage.
///
/// Production:
///
/// * Game.
///     * Entity system.
///     * World generation.
///     * Rudimentary world generation to understand which elements will be needed.
///         * Placement of background things.
///         * Connectivity?
///         * None-overlapping?
///         * Map display.
/// * Metagame/save game?
///     * How do you enter a save slot? Multiple profiles and potential "menu world".
///     * Persistent unlocks, etc.
///     * De we allo save games? Probably yes, just for "pausing".
///     * Continuous save for crash recovery?
///

// Build options.
const INTERNAL = shared.INTERNAL;

const global_config = @import("config.zig").global_config;

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Rectangle3 = math.Rectangle3;
const Rectangle2i = math.Rectangle2i;
const Color = math.Color;
const Color3 = math.Color3;
const State = shared.State;
const TransientState = shared.TransientState;
const WorldPosition = world.WorldPosition;
const AddLowEntityResult = shared.AddLowEntityResult;
const RenderGroup = rendergroup.RenderGroup;
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
const ArenaPushParams = shared.ArenaPushParams;

pub export fn updateAndRender(
    platform: shared.Platform,
    memory: *shared.Memory,
    input: *shared.GameInput,
    render_commands: *shared.RenderCommands,
) void {
    shared.platform = platform;

    if (INTERNAL) {
        shared.debug_global_memory = memory;
    }

    const timed_block = TimedBlock.beginFunction(@src(), .GameUpdateAndRender);
    defer timed_block.end();

    std.debug.assert(@sizeOf(State) <= memory.permanent_storage_size);
    const state: *State = @ptrCast(@alignCast(memory.permanent_storage));
    if (!state.is_initialized) {
        state.* = State{
            .test_diffuse = undefined,
            .test_normal = undefined,
        };

        var total_arena: shared.MemoryArena = shared.MemoryArena{
            .size = undefined,
            .base = undefined,
            .used = undefined,
            .temp_count = undefined,
        };
        total_arena.initialize(
            memory.permanent_storage_size - @sizeOf(State),
            memory.permanent_storage.? + @sizeOf(State),
        );
        total_arena.makeSubArena(&state.audio_arena, shared.megabytes(1), null);
        total_arena.makeSubArena(&state.mode_arena, total_arena.getRemainingSize(null), null);

        state.audio_state.initialize(&state.audio_arena);

        state.is_initialized = true;
    }

    // Transient initialization.
    std.debug.assert(@sizeOf(TransientState) <= memory.transient_storage_size);
    var transient_state: *TransientState = @ptrCast(@alignCast(memory.transient_storage));
    if (!transient_state.is_initialized) {
        transient_state.arena.initialize(
            memory.transient_storage_size - @sizeOf(TransientState),
            memory.transient_storage.? + @sizeOf(TransientState),
        );

        transient_state.high_priority_queue = memory.high_priority_queue;
        transient_state.low_priority_queue = memory.low_priority_queue;

        var task_index: u32 = 0;
        while (task_index < transient_state.tasks.len) : (task_index += 1) {
            var task: *shared.TaskWithMemory = &transient_state.tasks[task_index];

            task.being_used = false;
            transient_state.arena.makeSubArena(&task.arena, shared.megabytes(1), null);
        }

        transient_state.assets = Assets.allocate(
            &transient_state.arena,
            shared.megabytes(256),
            transient_state,
            &memory.texture_op_queue,
        );

        // if (state.audio_state.playSound(transient_state.assets.getFirstSound(.Music))) |music| {
        //     state.music = music;
        // }

        transient_state.ground_buffer_count = 256;
        transient_state.ground_buffers = transient_state.arena.pushArray(transient_state.ground_buffer_count, shared.GroundBuffer, ArenaPushParams.aligned(@alignOf(shared.GroundBuffer), true));

        for (0..transient_state.ground_buffer_count) |ground_buffer_index| {
            const ground_buffer = &transient_state.ground_buffers[ground_buffer_index];
            ground_buffer.bitmap = makeEmptyBitmap(
                &transient_state.arena,
                world_mode.GROUND_BUFFER_WIDTH,
                world_mode.GROUND_BUFFER_HEIGHT,
                false,
            );
            ground_buffer.position = WorldPosition.nullPosition();
        }

        state.test_diffuse = makeEmptyBitmap(&transient_state.arena, 256, 256, false);
        // render.drawRectangle(
        //     &state.test_diffuse,
        //     Vector2.zero(),
        //     Vector2.newI(state.test_diffuse.width, state.test_diffuse.height),
        //     Color.new(0.5, 0.5, 0.5, 1),
        // );
        state.test_normal = makeEmptyBitmap(
            &transient_state.arena,
            state.test_diffuse.width,
            state.test_diffuse.height,
            false,
        );

        makeSphereNormalMap(&state.test_normal, 0, 1, 1);
        makeSphereDiffuseMap(&state.test_diffuse, 1, 1);
        // makePyramidNormalMap(&state.test_normal, 0);

        transient_state.env_map_width = 512;
        transient_state.env_map_height = 256;

        for (&transient_state.env_maps) |*map| {
            var width: i32 = transient_state.env_map_width;
            var height: i32 = transient_state.env_map_height;

            for (&map.lod) |*lod| {
                lod.* = makeEmptyBitmap(&transient_state.arena, width, height, false);
                width >>= 1;
                height >>= 1;
            }
        }

        transient_state.is_initialized = true;
    }

    if (transient_state.main_generation_id != 0) {
        transient_state.assets.endGeneration(transient_state.main_generation_id);
    }
    transient_state.main_generation_id = transient_state.assets.beginGeneration();

    if (state.current_mode == .None) {
        cutscene.playIntroCutscene(state, transient_state);
    }

    if (global_config.GroundChunks_RecomputeOnEXEChange) {
        if (memory.executable_reloaded) {
            for (0..transient_state.ground_buffer_count) |ground_buffer_index| {
                const ground_buffer = &transient_state.ground_buffers[ground_buffer_index];
                ground_buffer.position = WorldPosition.nullPosition();
            }
        }
    }

    // if (false) {
    //     var music_volume = Vector2.zero();
    //     _ = music_volume.setY(math.safeRatio0(input.mouse_x, @as(f32, @floatFromInt(buffer.width))));
    //     _ = music_volume.setX(1.0 - music_volume.y());
    //     state.audio_state.changeVolume(state.music, 0.01, music_volume);
    // }

    // if (global_config.Renderer_TestWeirdDrawBufferSize) {
    //     // Enable this to test weird buffer sizes in the renderer.
    //     draw_buffer.width = 1279;
    //     draw_buffer.height = 719;
    // }

    // Create the piece group.
    const render_memory = transient_state.arena.beginTemporaryMemory();
    var render_group_ = RenderGroup.begin(
        transient_state.assets,
        render_commands,
        transient_state.main_generation_id,
        false,
    );
    var render_group = &render_group_;

    // TODO: Replace this with a specification of the size of the render area.
    var draw_buffer: LoadedBitmap = .{
        .width = @intCast(render_commands.width),
        .height = @intCast(render_commands.height),
        .memory = undefined,
    };

    var rerun: bool = true;
    while (rerun) {
        switch (state.current_mode) {
            .None => {},
            .TitleScreen => {
                rerun = cutscene.updateAndRenderTitleScreen(
                    state,
                    transient_state,
                    render_group,
                    &draw_buffer,
                    input,
                    state.mode.title_screen,
                );
            },
            .Cutscene => {
                rerun = cutscene.updateAndRenderCutscene(
                    state,
                    transient_state,
                    render_group,
                    &draw_buffer,
                    input,
                    state.mode.cutscene,
                );
            },
            .World => {
                rerun = world_mode.updateAndRenderWorld(
                    state,
                    state.mode.world,
                    transient_state,
                    input,
                    render_group,
                    &draw_buffer,
                );
            },
        }
    }

    render_group.end();

    transient_state.arena.endTemporaryMemory(render_memory);

    if (state.current_mode == .World) {
        state.mode.world.world.arena.checkArena();
    }

    transient_state.arena.checkArena();
}

pub export fn debugFrameEnd(
    memory: *shared.Memory,
    input: shared.GameInput,
    commands: *shared.RenderCommands,
) *debug_interface.DebugTable {
    return shared.debugFrameEnd(memory, input, commands);
}

pub export fn getSoundSamples(
    memory: *shared.Memory,
    sound_buffer: *shared.SoundOutputBuffer,
) void {
    const state: *State = @ptrCast(@alignCast(memory.permanent_storage));
    const transient_state: *TransientState = @ptrCast(@alignCast(memory.transient_storage));

    state.audio_state.outputPlayingSounds(sound_buffer, transient_state.assets, &transient_state.arena);
    // audio.outputSineWave(sound_buffer, shared.MIDDLE_C, state);
}

pub fn beginTaskWithMemory(transient_state: *TransientState, depends_on_game_mode: bool) ?*shared.TaskWithMemory {
    var found_task: ?*shared.TaskWithMemory = null;

    var task_index: u32 = 0;
    while (task_index < transient_state.tasks.len) : (task_index += 1) {
        var task = &transient_state.tasks[task_index];

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
    if (bitmap.memory) |*memory| {
        const total_bitmap_size: u32 = @intCast(bitmap.*.width * bitmap.*.height * shared.BITMAP_BYTES_PER_PIXEL);
        shared.zeroSize(total_bitmap_size, memory.*);
    }
}

fn makeEmptyBitmap(arena: *shared.MemoryArena, width: i32, height: i32, clear_to_zero: bool) LoadedBitmap {
    const result = arena.pushStruct(LoadedBitmap, null);

    result.alignment_percentage = Vector2.splat(0.5);
    result.width_over_height = math.safeRatio1(@floatFromInt(width), @floatFromInt(height));

    result.width = shared.safeTruncateToUInt16(width);
    result.height = shared.safeTruncateToUInt16(height);
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

            pixel[0] = color.packColor1();

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

            pixel[0] = color.packColor1();

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

            pixel[0] = color.packColor1();

            pixel += 1;
        }

        row += @as(usize, @intCast(bitmap.pitch));
    }
}
