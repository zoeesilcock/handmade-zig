const std = @import("std");
const shared = @import("shared.zig");
const memory = @import("memory.zig");
const math = @import("math.zig");
const rendergroup = @import("rendergroup.zig");
const asset = @import("asset.zig");
const intrinsics = @import("intrinsics.zig");
const sort = @import("sort.zig");
const debug_interface = @import("debug_interface.zig");

// TODO: How would we import other platforms here?
const platform = @import("win32_handmade.zig");
var show_lighting_samples: bool = false;

const INTERNAL = shared.INTERNAL;

const Vector2 = math.Vector2;
const Vector2i = math.Vector2i;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Rectangle2 = math.Rectangle2;
const Vec4f = math.Vec4f;
const Vec4u = math.Vec4u;
const Vec4i = math.Vec4i;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle2i = math.Rectangle2i;
const MemoryArena = memory.MemoryArena;
const RenderCommands = shared.RenderCommands;
const GameRenderPrep = shared.GameRenderPrep;
const RenderGroup = rendergroup.RenderGroup;
const RenderEntryHeader = rendergroup.RenderEntryHeader;
const RenderEntryClear = rendergroup.RenderEntryClear;
const RenderEntryClipRect = rendergroup.RenderEntryClipRect;
const RenderEntryBitmap = rendergroup.RenderEntryBitmap;
const RenderEntryRectangle = rendergroup.RenderEntryRectangle;
const RenderEntryCoordinateSystem = rendergroup.RenderEntryCoordinateSystem;
const RenderEntrySaturation = rendergroup.RenderEntrySaturation;
const EnvironmentMap = rendergroup.EnvironmentMap;
const LoadedBitmap = asset.LoadedBitmap;
const TimedBlock = debug_interface.TimedBlock;
const DebugInterface = debug_interface.DebugInterface;

const BilinearSample = struct {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
};

pub const TileRenderWork = struct {
    commands: *RenderCommands,
    prep: *GameRenderPrep,
    output_target: *LoadedBitmap,
    clip_rect: Rectangle2i,
};

const TextureOpAllocate = struct {
    width: i32,
    height: i32,
    data: *anyopaque,
    result_handle: *u32,
};

const TextureOpDeallocate = struct {
    handle: u32,
};

pub const TextureOp = struct {
    next: ?*TextureOp = null,
    is_allocate: bool,

    op: union {
        allocate: TextureOpAllocate,
        deallocate: TextureOpDeallocate,
    },
};

const SpriteFlag = enum(u32) {
    Visited = 0x1,
    Drawn = 0x2,
};

pub const SortSpriteBound = struct {
    first_edge_with_me_as_front: ?*SpriteEdge,
    screen_area: Rectangle2,
    sort_key: SpriteBound,
    offset: u32,
    flags: u32,
};

pub const SpriteBound = struct {
    y_min: f32,
    y_max: f32,
    z_max: f32,
};

const SpriteEdge = struct {
    next_edge_with_same_front: ?*SpriteEdge,
    front: u32,
    behind: u32,
};

pub fn softwareRenderCommands(
    render_queue: *shared.PlatformWorkQueue,
    commands: *RenderCommands,
    prep: *GameRenderPrep,
    output_target: *LoadedBitmap,
) void {
    TimedBlock.beginFunction(@src(), .TiledRenderToOutput);
    defer TimedBlock.endFunction(@src(), .TiledRenderToOutput);

    // TODO
    // * Make sure that tiles are all cache-aligned.
    // * Can we get hyperthreads synced so they do interleaved lines?
    // * How big should the tiles be for performance?
    // * Actually ballpark the memory bandwith for drawRectangleQuickly.
    // * Re-test some of our instruction choices.

    const tile_count_x = 4;
    const tile_count_y = 4;
    const work_count = tile_count_x * tile_count_y;
    var work_array: [work_count]TileRenderWork = [1]TileRenderWork{TileRenderWork{
        .commands = commands,
        .prep = prep,
        .output_target = output_target,
        .clip_rect = undefined,
    }} ** work_count;

    std.debug.assert((@intFromPtr(output_target.memory) & 15) == 0);

    var tile_width = @divFloor(output_target.width, tile_count_x);
    const tile_height = @divFloor(output_target.height, tile_count_y);

    tile_width = @divFloor(tile_width + 3, 4) * 4;

    var work_index: u32 = 0;
    var tile_y: i32 = 0;
    while (tile_y < tile_count_y) : (tile_y += 1) {
        var tile_x: i32 = 0;
        while (tile_x < tile_count_x) : (tile_x += 1) {
            var work = &work_array[work_index];
            work_index += 1;

            var clip_rect = Rectangle2i.zero();
            _ = clip_rect.min.setX(tile_x * tile_width);
            _ = clip_rect.min.setY(tile_y * tile_height);
            _ = clip_rect.max.setX(clip_rect.min.x() + tile_width);
            _ = clip_rect.max.setY(clip_rect.min.y() + tile_height);

            if (tile_x == (tile_count_x - 1)) {
                _ = clip_rect.max.setX(output_target.width);
            }
            if (tile_y == (tile_count_y - 1)) {
                _ = clip_rect.max.setY(output_target.height);
            }

            work.clip_rect = clip_rect;

            if (true) {
                platform.platform.addQueueEntry(render_queue, &doTileRenderWork, work);
            } else {
                doTileRenderWork(render_queue, work);
            }
        }
    }

    platform.platform.completeAllQueuedWork(render_queue);
}

pub fn doTileRenderWork(queue: shared.PlatformWorkQueuePtr, data: *anyopaque) callconv(.C) void {
    _ = queue;

    TimedBlock.beginFunction(@src(), .DoTiledRenderWork);
    defer TimedBlock.endFunction(@src(), .DoTiledRenderWork);

    const work: *TileRenderWork = @ptrCast(@alignCast(data));

    renderCommandsToBitmap(work.commands, work.prep, work.output_target, work.clip_rect);
}

pub fn renderCommandsToBitmap(
    commands: *RenderCommands,
    prep: *GameRenderPrep,
    output_target: *LoadedBitmap,
    base_clip_rect: Rectangle2i,
) void {
    // TimedBlock.beginFunction(@src(), .RenderCommandsToBitmap);
    // defer TimedBlock.endFunction(@src(), .RenderCommandsToBitmap);

    const null_pixels_to_meters: f32 = 1.0;

    var clip_rect_index: u32 = 0xffffffff;
    var clip_rect: Rectangle2i = base_clip_rect;

    const sort_entry_count: u32 = commands.push_buffer_element_count;

    var sort_entry: [*]u32 = prep.sorted_indices;
    var sort_entry_index: u32 = 0;
    while (sort_entry_index < sort_entry_count) : (sort_entry_index += 1) {
        defer sort_entry += 1;

        const header: *RenderEntryHeader = @ptrCast(@alignCast(commands.push_buffer_base + sort_entry[0]));
        const alignment: usize = switch (header.type) {
            .RenderEntryClear => @alignOf(RenderEntryClear),
            .RenderEntryBitmap => @alignOf(RenderEntryBitmap),
            .RenderEntryRectangle => @alignOf(RenderEntryRectangle),
            .RenderEntryCoordinateSystem => @alignOf(RenderEntryCoordinateSystem),
            .RenderEntrySaturation => @alignOf(RenderEntrySaturation),
            else => {
                unreachable;
            },
        };

        const header_address = @intFromPtr(header);
        const data_address = header_address + @sizeOf(RenderEntryHeader);
        const aligned_address = std.mem.alignForward(usize, data_address, alignment);
        const data: *anyopaque = @ptrFromInt(aligned_address);

        if (clip_rect_index != header.clip_rect_index) {
            clip_rect_index = header.clip_rect_index;

            std.debug.assert(clip_rect_index < commands.clip_rect_count);

            const clip: RenderEntryClipRect = prep.clip_rects[clip_rect_index];
            clip_rect = base_clip_rect.getIntersectionWith(clip.rect);
        }

        switch (header.type) {
            .RenderEntryClear => {
                const entry: *RenderEntryClear = @ptrCast(@alignCast(data));
                const dimension = Vector2.newI(output_target.width, output_target.height);
                drawRectangle(output_target, Vector2.zero(), dimension, entry.premultiplied_color.rgb().toColor(1), clip_rect);
            },
            .RenderEntrySaturation => {
                const entry: *RenderEntrySaturation = @ptrCast(@alignCast(data));

                changeSaturation(output_target, entry.level);
            },
            .RenderEntryBitmap => {
                const entry: *RenderEntryBitmap = @ptrCast(@alignCast(data));
                if (entry.bitmap) |bitmap| {
                    if (false) {
                        drawRectangleSlowly(
                            output_target,
                            entry.position,
                            entry.x_axis,
                            entry.y_axis,
                            entry.color,
                            @constCast(bitmap),
                            null,
                            undefined,
                            undefined,
                            undefined,
                            null_pixels_to_meters,
                        );
                    } else {
                        drawRectangleQuickly(
                            output_target,
                            entry.position,
                            entry.x_axis,
                            entry.y_axis,
                            entry.premultiplied_color,
                            @constCast(bitmap),
                            null_pixels_to_meters,
                            clip_rect,
                        );
                    }
                }
            },
            .RenderEntryRectangle => {
                const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));

                drawRectangle(
                    output_target,
                    entry.position,
                    entry.position.plus(entry.dimension),
                    entry.premultiplied_color,
                    clip_rect,
                );
            },
            .RenderEntryCoordinateSystem => {
                // const entry: *RenderEntryCoordinateSystem = @ptrCast(@alignCast(data));
                // const max = entry.origin.plus(entry.x_axis).plus(entry.y_axis);
                // drawRectangleSlowly(
                //     output_target,
                //     entry.origin,
                //     entry.x_axis,
                //     entry.y_axis,
                //     entry.color,
                //     entry.texture,
                //     entry.normal_map,
                //     entry.top,
                //     entry.middle,
                //     entry.bottom,
                //     null_pixels_to_meters,
                // );
                //
                // const color = Color.new(1, 1, 0, 1);
                // const dimension = Vector2.new(2, 2);
                // var position = entry.origin;
                // drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);
                //
                // position = entry.origin.plus(entry.x_axis);
                // drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);
                //
                // position = entry.origin.plus(entry.y_axis);
                // drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);
                //
                // position = max;
                // drawRectangle(output_target, position.minus(dimension), position.plus(dimension), color);
            },
            else => {
                unreachable;
            },
        }
    }
}

pub fn drawRectangle(
    draw_buffer: *LoadedBitmap,
    min: Vector2,
    max: Vector2,
    color_in: Color,
    clip_rect: Rectangle2i,
) void {
    // TimedBlock.beginFunction(@src(), .DrawRectangle);
    // defer TimedBlock.endFunction(@src(), .DrawRectangle);

    var fill_rect = Rectangle2i.new(
        intrinsics.floorReal32ToInt32(min.x()),
        intrinsics.floorReal32ToInt32(min.y()),
        intrinsics.floorReal32ToInt32(max.x()),
        intrinsics.floorReal32ToInt32(max.y()),
    );
    fill_rect = fill_rect.getIntersectionWith(clip_rect);

    if (false) {
        // Set the pointer to the top left corner of the rectangle.
        var row: [*]u8 = @ptrCast(draw_buffer.memory);
        row += @as(
            u32,
            @intCast((fill_rect.min.x() * shared.BITMAP_BYTES_PER_PIXEL) +
                (fill_rect.min.y() * @as(i32, @intCast(draw_buffer.pitch)))),
        );

        var y = fill_rect.min.y();
        while (y < fill_rect.max.y()) : (y += 1) {
            var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

            var x = fill_rect.min.x();
            while (x < fill_rect.max.x()) : (x += 1) {
                pixel[0] = color_in.packColor();
                pixel += 1;
            }

            row += @as(usize, @intCast(draw_buffer.pitch));
        }
    } else {
        var color = color_in;
        color = color.scaledTo(255);
        _ = color.setRGB(color.rgb().scaledTo(255));

        const mask_ffffffff: Vec4u = @splat(0xFFFFFFFF);
        const one: Vec4f = @splat(1);
        const two: Vec4f = @splat(2);
        const three: Vec4f = @splat(3);
        const four: Vec4f = @splat(4);

        if (fill_rect.hasArea()) {
            var start_clip_mask = mask_ffffffff;
            var end_clip_mask = mask_ffffffff;

            const start_clip_masks: [4]Vec4u = .{
                start_clip_mask,
                start_clip_mask << one * four,
                start_clip_mask << two * four,
                start_clip_mask << three * four,
            };

            const end_clip_masks: [4]Vec4u = .{
                end_clip_mask,
                end_clip_mask >> three * four,
                end_clip_mask >> two * four,
                end_clip_mask >> one * four,
            };

            if (fill_rect.min.x() & 3 != 0) {
                start_clip_mask = start_clip_masks[@intCast(fill_rect.min.x() & 3)];
                _ = fill_rect.min.setX(fill_rect.min.x() & ~@as(i32, @intCast(3)));
            }

            if (fill_rect.max.x() & 3 != 0) {
                end_clip_mask = end_clip_masks[@intCast(fill_rect.max.x() & 3)];
                _ = fill_rect.max.setX((fill_rect.max.x() & ~@as(i32, @intCast(3))) + 4);
            }

            const min_x = fill_rect.min.x();
            const min_y = fill_rect.min.y();
            const max_x = fill_rect.max.x();
            const max_y = fill_rect.max.y();

            const inv_255: Vec4f = @splat(1.0 / 255.0);
            const max_color_value: Vec4f = @splat(255.0 * 255.0);
            const color_r: Vec4f = @splat(color.r());
            const color_g: Vec4f = @splat(color.g());
            const color_b: Vec4f = @splat(color.b());
            const color_a: Vec4f = @splat(color.a());
            const one_255: Vec4f = @splat(255.0);
            const zero: Vec4f = @splat(0);
            // const half: Vec4f = @splat(0.5);
            // const zero_to_three: Vec4f = .{ 0, 1, 2, 3 };
            const shift_24: Vec4u = @splat(24);
            const shift_16: Vec4u = @splat(16);
            const shift_8: Vec4u = @splat(8);
            // const shift_2: Vec4u = @splat(2);
            const mask_ff: Vec4u = @splat(0xFF);

            const row_advance: usize = @intCast(draw_buffer.pitch);
            var row: [*]u8 = @ptrCast(draw_buffer.memory);
            row += @as(u32, @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * draw_buffer.pitch)));

            // TimedBlock.beginWithCount(@src(), .ProcessPixel, @intCast(@divFloor(fill_rect.getClampedArea(), 2)));
            // defer TimedBlock.endBlock(@src(), .ProcessPixel);

            var y: i32 = min_y;
            while (y < max_y) : (y += 1) {
                var pixel = @as([*]u32, @ptrCast(@alignCast(row)));
                var clip_mask: Vec4u = start_clip_mask;

                var xi: i32 = min_x;
                while (xi < max_x) : (xi += 4) {
                    asm volatile ("# LLVM-MCA-BEGIN ProcessPixel");

                    const original_dest: Vec4u = @as(*align(@alignOf(u32)) Vec4u, @ptrCast(@alignCast(pixel))).*;
                    const write_mask: Vec4u = clip_mask;

                    // Load destination.
                    var dest_r: Vec4f = @floatFromInt((original_dest >> shift_16) & mask_ff);
                    var dest_g: Vec4f = @floatFromInt((original_dest >> shift_8) & mask_ff);
                    var dest_b: Vec4f = @floatFromInt((original_dest) & mask_ff);
                    const dest_a: Vec4f = @floatFromInt((original_dest >> shift_24) & mask_ff);

                    // Modulate by incoming color.
                    var texelr = color_r;
                    var texelg = color_g;
                    var texelb = color_b;
                    var texela = color_a;

                    // Clamp colors to valid range.
                    texelr = @max(zero, texelr);
                    texelr = @min(max_color_value, texelr);
                    texelg = @max(zero, texelg);
                    texelg = @min(max_color_value, texelg);
                    texelb = @max(zero, texelb);
                    texelb = @min(max_color_value, texelb);
                    texela = @max(zero, texela);
                    texela = @min(one_255, texela);

                    // Go from sRGB to linear brightness space.
                    dest_r = math.square_v4(dest_r);
                    dest_g = math.square_v4(dest_g);
                    dest_b = math.square_v4(dest_b);

                    // Destination blend.
                    const inv_texel_a = one - (inv_255 * texela);
                    var blended_r: Vec4f = dest_r * inv_texel_a + texelr;
                    var blended_g: Vec4f = dest_g * inv_texel_a + texelg;
                    var blended_b: Vec4f = dest_b * inv_texel_a + texelb;
                    const blended_a: Vec4f = dest_a * inv_texel_a + texela;

                    // Go from linear brightness space to sRGB.
                    blended_r = @sqrt(blended_r);
                    blended_g = @sqrt(blended_g);
                    blended_b = @sqrt(blended_b);

                    const int_r: Vec4u = @intFromFloat(blended_r);
                    const int_g: Vec4u = @intFromFloat(blended_g);
                    const int_b: Vec4u = @intFromFloat(blended_b);
                    const int_a: Vec4u = @intFromFloat(blended_a);

                    const out: Vec4u = int_r << shift_16 | int_g << shift_8 | int_b | int_a << shift_24;
                    const masked_out: Vec4u = (write_mask & out) | (~write_mask & original_dest);

                    const pixels = @as(*align(@alignOf(u32)) Vec4u, @ptrCast(@alignCast(pixel)));
                    pixels.* = masked_out;

                    pixel += 4;

                    if ((xi + 8) < max_x) {
                        clip_mask = mask_ffffffff;
                    } else {
                        clip_mask = end_clip_mask;
                    }

                    asm volatile ("# LLVM-MCA-END ProcessPixel");
                }

                row += row_advance;
            }
        }
    }
}

fn changeSaturation(draw_buffer: *LoadedBitmap, level: f32) void {
    // TimedBlock.beginFunction(@src(), .ChangeSaturation);
    // defer TimedBlock.endFunction(@src(), .ChangeSaturation);

    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);

    var y: u32 = 0;
    while (y < draw_buffer.height) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));

        var x: u32 = 0;
        while (x < draw_buffer.width) : (x += 1) {
            const d = Color.unpackColor(dest[0]);
            const average: f32 = (1.0 / 3.0) * (d.r() + d.g() + d.b());
            const delta = Color3.new(d.r() - average, d.g() - average, d.b() - average);
            var result = Color3.splat(average).plus(delta.scaledTo(level)).toColor(d.a());

            dest[0] = result.packColor1();

            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
    }
}

pub fn drawRectangleQuickly(
    draw_buffer: *LoadedBitmap,
    origin: Vector2,
    x_axis: Vector2,
    y_axis: Vector2,
    color_in: Color,
    texture: *LoadedBitmap,
    pixels_to_meters: f32,
    clip_rect: Rectangle2i,
) void {
    _ = pixels_to_meters;

    // TimedBlock.beginFunction(@src(), .DrawRectangleQuickly);
    // defer TimedBlock.endFunction(@src(), .DrawRectangleQuickly);

    var color = color_in;

    const mask_ffffffff: Vec4u = @splat(0xFFFFFFFF);
    const one: Vec4f = @splat(1);
    const two: Vec4f = @splat(2);
    const three: Vec4f = @splat(3);
    const four: Vec4f = @splat(4);
    const inv_x_axis_length_squared = 1.0 / x_axis.lengthSquared();
    const inv_y_axis_length_squared = 1.0 / y_axis.lengthSquared();
    const points: [4]Vector2 = .{
        origin,
        origin.plus(x_axis),
        origin.plus(x_axis).plus(y_axis),
        origin.plus(y_axis),
    };
    var fill_rect = Rectangle2i.invertedInfinity();

    // Expand the fill rect to include all four corners of the potentially rotated rectangle.
    for (points) |point| {
        const floor_x = intrinsics.floorReal32ToInt32(point.x());
        const ceil_x = intrinsics.ceilReal32ToInt32(point.x()) + 1;
        const floor_y = intrinsics.floorReal32ToInt32(point.y());
        const ceil_y = intrinsics.ceilReal32ToInt32(point.y()) + 1;

        if (fill_rect.min.x() > floor_x) {
            _ = fill_rect.min.setX(floor_x);
        }
        if (fill_rect.min.y() > floor_y) {
            _ = fill_rect.min.setY(floor_y);
        }
        if (fill_rect.max.x() < ceil_x) {
            _ = fill_rect.max.setX(ceil_x);
        }
        if (fill_rect.max.y() < ceil_y) {
            _ = fill_rect.max.setY(ceil_y);
        }
    }

    // const clip_rect = Rectangle2i.new(0, 0, width_max, height_max);
    fill_rect = fill_rect.getIntersectionWith(clip_rect);

    if (fill_rect.hasArea()) {
        var start_clip_mask = mask_ffffffff;
        var end_clip_mask = mask_ffffffff;

        const start_clip_masks: [4]Vec4u = .{
            start_clip_mask,
            start_clip_mask << one * four,
            start_clip_mask << two * four,
            start_clip_mask << three * four,
        };

        const end_clip_masks: [4]Vec4u = .{
            end_clip_mask,
            end_clip_mask >> three * four,
            end_clip_mask >> two * four,
            end_clip_mask >> one * four,
        };

        if (fill_rect.min.x() & 3 != 0) {
            start_clip_mask = start_clip_masks[@intCast(fill_rect.min.x() & 3)];
            _ = fill_rect.min.setX(fill_rect.min.x() & ~@as(i32, @intCast(3)));
        }

        if (fill_rect.max.x() & 3 != 0) {
            end_clip_mask = end_clip_masks[@intCast(fill_rect.max.x() & 3)];
            _ = fill_rect.max.setX((fill_rect.max.x() & ~@as(i32, @intCast(3))) + 4);
        }

        const min_x = fill_rect.min.x();
        const min_y = fill_rect.min.y();
        const max_x = fill_rect.max.x();
        const max_y = fill_rect.max.y();

        const texture_pitch: u32 = @intCast(texture.pitch);
        const texture_memory = texture.memory.?;
        const texture_pitch_4x: Vec4u = @splat(texture_pitch);
        const inv_255: Vec4f = @splat(1.0 / 255.0);
        const max_color_value: Vec4f = @splat(255.0 * 255.0);
        const color_r: Vec4f = @splat(color.r());
        const color_g: Vec4f = @splat(color.g());
        const color_b: Vec4f = @splat(color.b());
        const color_a: Vec4f = @splat(color.a());
        const one_255: Vec4f = @splat(255.0);
        const zero: Vec4f = @splat(0);
        const half: Vec4f = @splat(0.5);
        const zero_to_three: Vec4f = .{ 0, 1, 2, 3 };
        const shift_24: Vec4u = @splat(24);
        const shift_16: Vec4u = @splat(16);
        const shift_8: Vec4u = @splat(8);
        const shift_2: Vec4u = @splat(2);
        const mask_ff: Vec4u = @splat(0xFF);
        const width_m2: Vec4f = @splat(@floatFromInt(texture.width - 2));
        const height_m2: Vec4f = @splat(@floatFromInt(texture.height - 2));

        const n_x_axis = x_axis.scaledTo(inv_x_axis_length_squared);
        const n_y_axis = y_axis.scaledTo(inv_y_axis_length_squared);
        const n_x_axis_x: Vec4f = @splat(n_x_axis.x());
        const n_x_axis_y: Vec4f = @splat(n_x_axis.y());
        const n_y_axis_x: Vec4f = @splat(n_y_axis.x());
        const n_y_axis_y: Vec4f = @splat(n_y_axis.y());
        const origin_x: Vec4f = @splat(origin.x());
        const origin_y: Vec4f = @splat(origin.y());

        const row_advance: usize = @intCast(draw_buffer.pitch);
        var row: [*]u8 = @ptrCast(draw_buffer.memory);
        row += @as(u32, @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * draw_buffer.pitch)));

        // TimedBlock.beginWithCount(@src(), .ProcessPixel, @intCast(@divFloor(fill_rect.getClampedArea(), 2)));
        // defer TimedBlock.endBlock(@src(), .ProcessPixel);

        var y: i32 = min_y;
        while (y < max_y) : (y += 1) {
            var pixel = @as([*]u32, @ptrCast(@alignCast(row)));
            var pixel_position_x: Vec4f =
                @as(Vec4f, @splat(@floatFromInt(min_x))) - origin_x + zero_to_three;
            const pixel_position_y: Vec4f = @as(Vec4f, @splat(@floatFromInt(y))) - origin_y;
            var clip_mask: Vec4u = start_clip_mask;

            var xi: i32 = min_x;
            while (xi < max_x) : (xi += 4) {
                asm volatile ("# LLVM-MCA-BEGIN ProcessPixel");
                var u = pixel_position_x * n_x_axis_x + pixel_position_y * n_x_axis_y;
                var v = pixel_position_x * n_y_axis_x + pixel_position_y * n_y_axis_y;

                const original_dest: Vec4u = @as(*align(@alignOf(u32)) Vec4u, @ptrCast(@alignCast(pixel))).*;
                var write_mask: Vec4u =
                    (@intFromBool(u >= zero) & @intFromBool(u <= one) & @intFromBool(v >= zero) & @intFromBool(v <= one)) * mask_ffffffff;
                write_mask = write_mask & clip_mask;

                // Clamp UV to valid range so we don't read out of invalid memory.
                u = @max(zero, u);
                u = @min(one, u);
                v = @max(zero, v);
                v = @min(one, v);

                // Bias texture coordinates to start on the boundary between the 0,0 and 1,1 pixels.
                const texel_x: Vec4f = (u * width_m2) + half;
                const texel_y: Vec4f = (v * height_m2) + half;
                var texel_rounded_x: Vec4u = @intFromFloat(texel_x);
                var texel_rounded_y: Vec4u = @intFromFloat(texel_y);

                // Prepare for bilinear texture blend.
                const fx = texel_x - @as(Vec4f, @floatFromInt(texel_rounded_x));
                const fy = texel_y - @as(Vec4f, @floatFromInt(texel_rounded_y));
                const ifx = one - fx;
                const ify = one - fy;
                const l0 = ify * ifx;
                const l1 = ify * fx;
                const l2 = fy * ifx;
                const l3 = fy * fx;

                // Locate source memory.
                texel_rounded_x = texel_rounded_x << shift_2;
                texel_rounded_y *= texture_pitch_4x;
                const texel_offsets = texel_rounded_x + texel_rounded_y;
                const texel_pointer0 = texture_memory + @as(u32, @intCast(texel_offsets[0]));
                const texel_pointer1 = texture_memory + @as(u32, @intCast(texel_offsets[1]));
                const texel_pointer2 = texture_memory + @as(u32, @intCast(texel_offsets[2]));
                const texel_pointer3 = texture_memory + @as(u32, @intCast(texel_offsets[3]));

                const sample_a: Vec4u = .{
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer0))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer1))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer2))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer3))).*,
                };
                const sample_b: Vec4u = .{
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer0 + @sizeOf(u32)))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer1 + @sizeOf(u32)))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer2 + @sizeOf(u32)))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer3 + @sizeOf(u32)))).*,
                };
                const sample_c: Vec4u = .{
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer0 + texture_pitch))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer1 + texture_pitch))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer2 + texture_pitch))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer3 + texture_pitch))).*,
                };
                const sample_d: Vec4u = .{
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer0 + @sizeOf(u32) + texture_pitch))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer1 + @sizeOf(u32) + texture_pitch))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer2 + @sizeOf(u32) + texture_pitch))).*,
                    @as(*align(@alignOf(u8)) u32, @ptrCast(@alignCast(texel_pointer3 + @sizeOf(u32) + texture_pitch))).*,
                };

                // Load the source.
                var texel_a_r: Vec4f = @floatFromInt((sample_a >> shift_16) & mask_ff);
                var texel_a_g: Vec4f = @floatFromInt((sample_a >> shift_8) & mask_ff);
                var texel_a_b: Vec4f = @floatFromInt((sample_a) & mask_ff);
                const texel_a_a: Vec4f = @floatFromInt((sample_a >> shift_24) & mask_ff);

                var texel_b_r: Vec4f = @floatFromInt((sample_b >> shift_16) & mask_ff);
                var texel_b_g: Vec4f = @floatFromInt((sample_b >> shift_8) & mask_ff);
                var texel_b_b: Vec4f = @floatFromInt((sample_b) & mask_ff);
                const texel_b_a: Vec4f = @floatFromInt((sample_b >> shift_24) & mask_ff);

                var texel_c_r: Vec4f = @floatFromInt((sample_c >> shift_16) & mask_ff);
                var texel_c_g: Vec4f = @floatFromInt((sample_c >> shift_8) & mask_ff);
                var texel_c_b: Vec4f = @floatFromInt((sample_c) & mask_ff);
                const texel_c_a: Vec4f = @floatFromInt((sample_c >> shift_24) & mask_ff);

                var texel_d_r: Vec4f = @floatFromInt((sample_d >> shift_16) & mask_ff);
                var texel_d_g: Vec4f = @floatFromInt((sample_d >> shift_8) & mask_ff);
                var texel_d_b: Vec4f = @floatFromInt((sample_d) & mask_ff);
                const texel_d_a: Vec4f = @floatFromInt((sample_d >> shift_24) & mask_ff);

                // Load destination.
                var dest_r: Vec4f = @floatFromInt((original_dest >> shift_16) & mask_ff);
                var dest_g: Vec4f = @floatFromInt((original_dest >> shift_8) & mask_ff);
                var dest_b: Vec4f = @floatFromInt((original_dest) & mask_ff);
                const dest_a: Vec4f = @floatFromInt((original_dest >> shift_24) & mask_ff);

                // Convert texture from sRGB to linear brightness space.
                texel_a_r = math.square_v4(texel_a_r);
                texel_a_g = math.square_v4(texel_a_g);
                texel_a_b = math.square_v4(texel_a_b);

                texel_b_r = math.square_v4(texel_b_r);
                texel_b_g = math.square_v4(texel_b_g);
                texel_b_b = math.square_v4(texel_b_b);

                texel_c_r = math.square_v4(texel_c_r);
                texel_c_g = math.square_v4(texel_c_g);
                texel_c_b = math.square_v4(texel_c_b);

                texel_d_r = math.square_v4(texel_d_r);
                texel_d_g = math.square_v4(texel_d_g);
                texel_d_b = math.square_v4(texel_d_b);

                // Bilinear texture blend.
                var texelr = l0 * texel_a_r + l1 * texel_b_r + l2 * texel_c_r + l3 * texel_d_r;
                var texelg = l0 * texel_a_g + l1 * texel_b_g + l2 * texel_c_g + l3 * texel_d_g;
                var texelb = l0 * texel_a_b + l1 * texel_b_b + l2 * texel_c_b + l3 * texel_d_b;
                var texela = l0 * texel_a_a + l1 * texel_b_a + l2 * texel_c_a + l3 * texel_d_a;

                // Modulate by incoming color.
                texelr *= color_r;
                texelg *= color_g;
                texelb *= color_b;
                texela *= color_a;

                // Clamp colors to valid range.
                texelr = @max(zero, texelr);
                texelr = @min(max_color_value, texelr);
                texelg = @max(zero, texelg);
                texelg = @min(max_color_value, texelg);
                texelb = @max(zero, texelb);
                texelb = @min(max_color_value, texelb);
                texela = @max(zero, texela);
                texela = @min(one_255, texela);

                // Go from sRGB to linear brightness space.
                dest_r = math.square_v4(dest_r);
                dest_g = math.square_v4(dest_g);
                dest_b = math.square_v4(dest_b);

                // Destination blend.
                const inv_texel_a = one - (inv_255 * texela);
                var blended_r: Vec4f = dest_r * inv_texel_a + texelr;
                var blended_g: Vec4f = dest_g * inv_texel_a + texelg;
                var blended_b: Vec4f = dest_b * inv_texel_a + texelb;
                const blended_a: Vec4f = dest_a * inv_texel_a + texela;

                // Go from linear brightness space to sRGB.
                blended_r = @sqrt(blended_r);
                blended_g = @sqrt(blended_g);
                blended_b = @sqrt(blended_b);

                const int_r: Vec4u = @intFromFloat(blended_r);
                const int_g: Vec4u = @intFromFloat(blended_g);
                const int_b: Vec4u = @intFromFloat(blended_b);
                const int_a: Vec4u = @intFromFloat(blended_a);

                const out: Vec4u = int_r << shift_16 | int_g << shift_8 | int_b | int_a << shift_24;
                const masked_out: Vec4u = (write_mask & out) | (~write_mask & original_dest);

                const pixels = @as(*align(@alignOf(u32)) Vec4u, @ptrCast(@alignCast(pixel)));
                pixels.* = masked_out;

                pixel += 4;
                pixel_position_x += four;

                if ((xi + 8) < max_x) {
                    clip_mask = mask_ffffffff;
                } else {
                    clip_mask = end_clip_mask;
                }

                asm volatile ("# LLVM-MCA-END ProcessPixel");
            }

            row += row_advance;
        }
    }
}

pub fn drawRectangleSlowly(
    draw_buffer: *LoadedBitmap,
    origin: Vector2,
    x_axis: Vector2,
    y_axis: Vector2,
    color: Color,
    texture: *LoadedBitmap,
    opt_normal_map: ?*LoadedBitmap,
    top: *EnvironmentMap,
    middle: *EnvironmentMap,
    bottom: *EnvironmentMap,
    pixels_to_meters: f32,
) void {
    // TimedBlock.beginFunction(@src(), .DrawRectangleSlowly);
    // defer TimedBlock.endFunction(@src(), .DrawRectangleSlowly);

    const y_axis_length = y_axis.length();
    const x_axis_length = x_axis.length();
    const normal_x_axis = x_axis.scaledTo(y_axis_length / x_axis_length);
    const normal_y_axis = y_axis.scaledTo(x_axis_length / y_axis_length);
    const normal_z_scale = 0.5 * (x_axis_length + y_axis_length);

    const inv_x_axis_length_squared = 1.0 / x_axis.lengthSquared();
    const inv_y_axis_length_squared = 1.0 / y_axis.lengthSquared();
    const points: [4]Vector2 = .{
        origin,
        origin.plus(x_axis),
        origin.plus(x_axis).plus(y_axis),
        origin.plus(y_axis),
    };

    const width_max = draw_buffer.width - 1;
    const height_max = draw_buffer.height - 1;
    const inv_width_max: f32 = 1.0 / @as(f32, @floatFromInt(width_max));
    const inv_height_max: f32 = 1.0 / @as(f32, @floatFromInt(height_max));
    var y_min: i32 = height_max;
    var y_max: i32 = 0;
    var x_min: i32 = width_max;
    var x_max: i32 = 0;

    const origin_z: f32 = 0.0;
    const origin_y: f32 = (origin.plus(x_axis.scaledTo(0.5).plus(y_axis.scaledTo(0.5)))).y();
    const fixed_cast_y = inv_height_max * origin_y;

    for (points) |point| {
        const floor_x = intrinsics.floorReal32ToInt32(point.x());
        const ceil_x = intrinsics.ceilReal32ToInt32(point.x());
        const floor_y = intrinsics.floorReal32ToInt32(point.y());
        const ceil_y = intrinsics.ceilReal32ToInt32(point.y());

        if (x_min > floor_x) {
            x_min = floor_x;
        }
        if (y_min > floor_y) {
            y_min = floor_y;
        }
        if (x_max < ceil_x) {
            x_max = ceil_x;
        }
        if (y_max < ceil_y) {
            y_max = ceil_y;
        }
    }

    if (x_min < 0) {
        x_min = 0;
    }
    if (y_min < 0) {
        y_min = 0;
    }
    if (x_max > width_max) {
        x_max = width_max;
    }
    if (y_max > height_max) {
        y_max = height_max;
    }

    var row: [*]u8 = @ptrCast(draw_buffer.memory);
    row += @as(u32, @intCast((x_min * shared.BITMAP_BYTES_PER_PIXEL) + (y_min * draw_buffer.pitch)));

    // TimedBlock.beginWithCount(@src(), .ProcessPixel, @intCast((x_max - x_min + 1) * (y_max - y_min + 1)));
    // defer TimedBlock.endBlock(@src(), .ProcessPixel);

    var y: i32 = y_min;
    while (y < y_max) : (y += 1) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x: i32 = x_min;
        while (x < x_max) : (x += 1) {
            const pixel_position = Vector2.newI(x, y);
            const d = pixel_position.minus(origin);

            const edge0 = d.dotProduct(x_axis.perp().negated());
            const edge1 = d.minus(x_axis).dotProduct(y_axis.perp().negated());
            const edge2 = d.minus(x_axis).minus(y_axis).dotProduct(x_axis.perp());
            const edge3 = d.minus(y_axis).dotProduct(y_axis.perp());

            if (edge0 < 0 and edge1 < 0 and edge2 < 0 and edge3 < 0) {
                // For items that are standing up.
                var screen_space_uv = Vector2.new(
                    inv_width_max * @as(f32, @floatFromInt(x)),
                    fixed_cast_y,
                );
                var z_diff: f32 = pixels_to_meters * (@as(f32, @floatFromInt(y)) - origin_y);

                if (false) {
                    // For items that are lying down on the ground.
                    screen_space_uv = Vector2.new(
                        inv_width_max * @as(f32, @floatFromInt(x)),
                        inv_height_max * @as(f32, @floatFromInt(y)),
                    );
                    z_diff = 0;
                }

                const u = d.dotProduct(x_axis) * inv_x_axis_length_squared;
                const v = d.dotProduct(y_axis) * inv_y_axis_length_squared;

                // std.debug.assert(u >= 0 and u <= 1.0);
                // std.debug.assert(v >= 0 and v <= 1.0);

                const texel_x: f32 = 1 + (u * @as(f32, @floatFromInt(texture.width - 2)));
                const texel_y: f32 = 1 + (v * @as(f32, @floatFromInt(texture.height - 2)));

                const texel_rounded_x: i32 = @intFromFloat(texel_x);
                const texel_rounded_y: i32 = @intFromFloat(texel_y);

                const texel_fraction_x: f32 = texel_x - @as(f32, @floatFromInt(texel_rounded_x));
                const texel_fraction_y: f32 = texel_y - @as(f32, @floatFromInt(texel_rounded_y));

                std.debug.assert(texel_rounded_x >= 0 and texel_rounded_x <= texture.width);
                std.debug.assert(texel_rounded_y >= 0 and texel_rounded_y <= texture.height);

                const texel_sample = bilinearSample(texture, texel_rounded_x, texel_rounded_y);
                var texel = sRGBBilinearBlend(texel_sample, texel_fraction_x, texel_fraction_y);

                if (opt_normal_map) |normal_map| {
                    const normal_sample = bilinearSample(normal_map, texel_rounded_x, texel_rounded_y);
                    const normal_a = Color.unpackColor(normal_sample.a);
                    const normal_b = Color.unpackColor(normal_sample.b);
                    const normal_c = Color.unpackColor(normal_sample.c);
                    const normal_d = Color.unpackColor(normal_sample.d);
                    var normal = normal_a.lerp(normal_b, texel_fraction_x).lerp(
                        normal_c.lerp(normal_d, texel_fraction_x),
                        texel_fraction_y,
                    ).toVector4();

                    normal = unscaleAndBiasNormal(normal);

                    _ = normal.setXY(normal_x_axis.scaledTo(normal.x()).plus(normal_y_axis.scaledTo(normal.y())));
                    _ = normal.setZ(normal.z() * normal_z_scale);
                    _ = normal.setXYZ(normal.xyz().normalized());

                    // The eye vector is always asumed to be 0, 0, 1.
                    var bounce_direction = normal.xyz().scaledTo(2.0 * normal.z());
                    _ = bounce_direction.setZ(bounce_direction.z() - 1.0);
                    _ = bounce_direction.setZ(-bounce_direction.z());

                    const z_position = origin_z + z_diff;
                    var opt_far_map: ?*EnvironmentMap = null;
                    const env_map_blend: f32 = bounce_direction.y();
                    var far_map_blend: f32 = 0;
                    if (env_map_blend < -0.5) {
                        opt_far_map = bottom;
                        far_map_blend = -1.0 - 2.0 * env_map_blend;
                    } else if (env_map_blend > 0.5) {
                        opt_far_map = top;
                        far_map_blend = 2.0 * (env_map_blend - 0.5);
                    }

                    far_map_blend *= far_map_blend;
                    far_map_blend *= far_map_blend;

                    var light_color = Color3.zero();
                    _ = middle;

                    if (opt_far_map) |far_map| {
                        const distance_from_map_in_z = far_map.z_position - z_position;
                        const far_map_color = sampleEnvironmentMap(
                            far_map,
                            screen_space_uv,
                            bounce_direction,
                            normal.w(),
                            distance_from_map_in_z,
                        );
                        light_color = light_color.lerp(far_map_color, far_map_blend);
                    }

                    _ = texel.setRGB(texel.rgb().plus(light_color.scaledTo(texel.a())));

                    if (false) {
                        // Draw bounce direction.
                        _ = texel.setRGB(bounce_direction.scaledTo(0.5).plus(Vector3.splat(0.5)).toColor3());
                        _ = texel.setRGB(texel.rgb().scaledTo(texel.a()));
                    }

                    // texel = Color.new(
                    //     normal.x() * 0.5 + 0.5,
                    //     normal.y() * 0.5 + 0.5,
                    //     normal.z() * 0.5 + 0.5,
                    //     1.0,
                    // );
                }

                texel = texel.hadamardProduct(color);
                _ = texel.setRGB(texel.rgb().clamp01());

                var dest = Color.unpackColor(pixel[0]);
                dest = math.sRGB255ToLinear1(dest);

                const blended = dest.scaledTo(1.0 - texel.a()).plus(texel);
                const blended255 = math.linear1ToSRGB255(blended);

                pixel[0] = blended255.packColor1();
            }

            pixel += 1;
        }

        row += @as(usize, @intCast(draw_buffer.pitch));
    }
}

pub fn drawRectangleOutline(
    draw_buffer: *LoadedBitmap,
    min: Vector2,
    max: Vector2,
    color: Color,
    radius: f32,
) void {
    // Top.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, min.y() - radius),
        Vector2.new(max.x() + radius, min.y() + radius),
        color,
    );

    // Bottom.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, max.y() - radius),
        Vector2.new(max.x() + radius, max.y() + radius),
        color,
    );

    // Left.
    drawRectangle(
        draw_buffer,
        Vector2.new(min.x() - radius, min.y() - radius),
        Vector2.new(min.x() + radius, max.y() + radius),
        color,
    );

    // Right.
    drawRectangle(
        draw_buffer,
        Vector2.new(max.x() - radius, min.y() - radius),
        Vector2.new(max.x() + radius, max.y() + radius),
        color,
    );
}

pub fn drawBitmap(
    draw_buffer: *LoadedBitmap,
    bitmap: *const LoadedBitmap,
    real_x: f32,
    real_y: f32,
    in_alpha: f32,
) void {
    // TimedBlock.beginFunction(@src(), .DrawBitmap);
    // defer TimedBlock.endFunction(@src(), .DrawBitmap);

    // TODO: Should we really clamp here?
    const alpha = math.clampf01(in_alpha);

    // The pixel color calculation below doesn't handle sizes outside the range of 0 - 1.
    std.debug.assert(alpha >= 0 and alpha <= 1);

    // Calculate extents.
    var min_x = intrinsics.floorReal32ToInt32(real_x);
    var min_y = intrinsics.floorReal32ToInt32(real_y);
    var max_x: i32 = @intFromFloat(real_x + @as(f32, @floatFromInt(bitmap.width)));
    var max_y: i32 = @intFromFloat(real_y + @as(f32, @floatFromInt(bitmap.height)));

    // Clip input values to buffer.
    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = -min_x;
        min_x = 0;
    }
    var source_offset_y: i32 = 0;
    if (min_y < 0) {
        source_offset_y = -min_y;
        min_y = 0;
    }
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Move to the correct spot in the data.
    const source_offset: i32 =
        @intCast(source_offset_y * @as(i32, @intCast(bitmap.pitch)) + shared.BITMAP_BYTES_PER_PIXEL * source_offset_x);
    const bitmap_pointer = @as([*]u8, @ptrCast(@alignCast(bitmap.memory.?)));
    var source_row: [*]u8 = shared.incrementPointer(bitmap_pointer, source_offset);

    // Move to the correct spot in the destination.
    const dest_offset: usize =
        @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch))));
    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);
    dest_row += dest_offset;

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(source_row));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            var texel = Color.unpackColor(source[0]);

            texel = math.sRGB255ToLinear1(texel);
            texel = texel.scaledTo(alpha);

            var d = Color.unpackColor(dest[0]);

            d = math.sRGB255ToLinear1(d);

            var result = d.scaledTo(1.0 - texel.a()).plus(texel);
            result = math.linear1ToSRGB255(result);

            dest[0] = result.packColor1();

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));

        source_row = shared.incrementPointer(source_row, bitmap.pitch);
    }
}

pub fn drawBitmapMatte(
    draw_buffer: *LoadedBitmap,
    bitmap: *LoadedBitmap,
    real_x: f32,
    real_y: f32,
    in_alpha: f32,
) void {
    // TODO: Should we really clamp here?
    const alpha = math.clampf01(in_alpha);

    // The pixel color calculation below doesn't handle sizes outside the range of 0 - 1.
    std.debug.assert(alpha >= 0 and alpha <= 1);

    // Calculate extents.
    var min_x = intrinsics.floorReal32ToInt32(real_x);
    var min_y = intrinsics.floorReal32ToInt32(real_y);
    var max_x: i32 = @intFromFloat(real_x + @as(f32, @floatFromInt(bitmap.width)));
    var max_y: i32 = @intFromFloat(real_y + @as(f32, @floatFromInt(bitmap.height)));

    // Clip input values to buffer.
    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = -min_x;
        min_x = 0;
    }
    var source_offset_y: i32 = 0;
    if (min_y < 0) {
        source_offset_y = -min_y;
        min_y = 0;
    }
    if (max_x > draw_buffer.width) {
        max_x = draw_buffer.width;
    }
    if (max_y > draw_buffer.height) {
        max_y = draw_buffer.height;
    }

    // Move to the correct spot in the data.
    const source_offset: i32 =
        @intCast(source_offset_y * @as(i32, @intCast(bitmap.pitch)) + shared.BITMAP_BYTES_PER_PIXEL * source_offset_x);
    const bitmap_pointer = @as([*]u8, @ptrCast(@alignCast(bitmap.memory.?)));
    var source_row: [*]u8 = shared.incrementPointer(bitmap_pointer, source_offset);

    // Move to the correct spot in the destination.
    const dest_offset: usize =
        @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * @as(i32, @intCast(draw_buffer.pitch))));
    var dest_row: [*]u8 = @ptrCast(draw_buffer.memory);
    dest_row += dest_offset;

    var y = min_y;
    while (y < max_y) : (y += 1) {
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));
        var source: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(source_row));

        var x = min_x;
        while (x < max_x) : (x += 1) {
            const sa: f32 = @floatFromInt((source[0] >> 24) & 0xFF);
            const rsa: f32 = alpha * (sa / 255.0);

            const da: f32 = @floatFromInt((dest[0] >> 24) & 0xFF);
            const dr: f32 = @floatFromInt((dest[0] >> 16) & 0xFF);
            const dg: f32 = @floatFromInt((dest[0] >> 8) & 0xFF);
            const db: f32 = @floatFromInt((dest[0] >> 0) & 0xFF);

            const inv_rsa = (1.0 - rsa);
            const color = Color.new(
                inv_rsa * da,
                inv_rsa * dr,
                inv_rsa * dg,
                inv_rsa * db,
            );

            dest[0] = color.packColor1();

            source += 1;
            dest += 1;
        }

        dest_row += @as(usize, @intCast(draw_buffer.pitch));
        source_row = shared.incrementPointer(source_row, bitmap.pitch);
    }
}

inline fn sRGBBilinearBlend(texel_sample: BilinearSample, x: f32, y: f32) Color {
    var texel_a = Color.unpackColor(texel_sample.a);
    var texel_b = Color.unpackColor(texel_sample.b);
    var texel_c = Color.unpackColor(texel_sample.c);
    var texel_d = Color.unpackColor(texel_sample.d);

    texel_a = math.sRGB255ToLinear1(texel_a);
    texel_b = math.sRGB255ToLinear1(texel_b);
    texel_c = math.sRGB255ToLinear1(texel_c);
    texel_d = math.sRGB255ToLinear1(texel_d);

    return texel_a.lerp(texel_b, x).lerp(
        texel_c.lerp(texel_d, x),
        y,
    );
}

inline fn unscaleAndBiasNormal(normal: Vector4) Vector4 {
    const inv_255: f32 = 1.0 / 255.0;

    return Vector4.new(
        -1.0 + 2.0 * (inv_255 * normal.x()),
        -1.0 + 2.0 * (inv_255 * normal.y()),
        -1.0 + 2.0 * (inv_255 * normal.z()),
        inv_255 * normal.w(),
    );
}

/// Sample from environment map, used when calculating light impact on a normal map.
///
/// * screen_space_uv tells us where the ray is being cast from in normalized screen coordinates.
/// * sample_direction tells us what direction the cast is going.
/// * roughness says which LODs of the map we sample from.
/// * distance_from_map_in_z says how far the map is from the sample point in Z, given in meters.
inline fn sampleEnvironmentMap(
    map: *EnvironmentMap,
    screen_space_uv: Vector2,
    sample_direction: Vector3,
    roughness: f32,
    distance_from_map_in_z: f32,
) Color3 {
    // Pick which LOD to sample from.
    const lod_index: u32 = @intFromFloat(roughness * @as(f32, @floatFromInt(map.lod.len - 1)) + 0.5);
    std.debug.assert(lod_index < map.lod.len);
    var lod = map.lod[lod_index];

    // Calculate the distance to the map and the scaling factor for meters to UVs.
    const uvs_per_meter = 0.1;
    const coefficient = (uvs_per_meter * distance_from_map_in_z) / sample_direction.y();
    const offset = Vector2.new(sample_direction.x(), sample_direction.z()).scaledTo(coefficient);

    // Find the intersection point and clamp it to a valid range.
    var uv = screen_space_uv.plus(offset).clamp01();

    // Bilinear sample.
    const map_x: f32 = (uv.x() * @as(f32, @floatFromInt(lod.width - 2)));
    const map_y: f32 = (uv.y() * @as(f32, @floatFromInt(lod.height - 2)));

    const rounded_x: i32 = @intFromFloat(map_x);
    const rounded_y: i32 = @intFromFloat(map_y);

    const fraction_x: f32 = map_x - @as(f32, @floatFromInt(rounded_x));
    const fraction_y: f32 = map_y - @as(f32, @floatFromInt(rounded_y));

    std.debug.assert(rounded_x >= 0 and rounded_x < lod.width);
    std.debug.assert(rounded_y >= 0 and rounded_y < lod.height);

    if (show_lighting_samples) {
        // Debug where we are sampling from on the environment map.
        const test_offset: i32 = @intCast((rounded_x * @sizeOf(u32)) + (rounded_y * lod.pitch));
        const texture_base = shared.incrementPointer(lod.memory.?, test_offset);
        const texel_pointer: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base));
        texel_pointer[0] = Color.new(255, 255, 255, 255).packColor();
    }

    const sample = bilinearSample(&lod, rounded_x, rounded_y);
    const result = sRGBBilinearBlend(sample, fraction_x, fraction_y).rgb();

    return result;
}

inline fn bilinearSample(texture: *LoadedBitmap, x: i32, y: i32) BilinearSample {
    const offset: i32 = @intCast((x * @sizeOf(u32)) + (y * texture.pitch));
    const texture_base = shared.incrementPointer(texture.memory.?, offset);
    const texel_pointer_a: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(texture_base));
    const texel_pointer_b: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(
        shared.incrementPointer(texture_base, @sizeOf(u32)),
    ));
    const texel_pointer_c: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(
        shared.incrementPointer(texture_base, texture.pitch),
    ));
    const texel_pointer_d: [*]align(@alignOf(u8)) u32 = @ptrCast(@alignCast(
        shared.incrementPointer(texture_base, @sizeOf(u32) + texture.pitch),
    ));

    return BilinearSample{
        .a = texel_pointer_a[0],
        .b = texel_pointer_b[0],
        .c = texel_pointer_c[0],
        .d = texel_pointer_d[0],
    };
}

pub fn prepForRender(commands: *RenderCommands, temp_arena: *MemoryArena) GameRenderPrep {
    var prep: GameRenderPrep = .{};

    prep.sorted_indices = sortEntries(commands, temp_arena);
    prep.clip_rects = linearizeClipRects(commands, temp_arena);

    return prep;
}

pub fn linearizeClipRects(commands: *RenderCommands, temp_arena: *MemoryArena) [*]RenderEntryClipRect {
    const result: [*]RenderEntryClipRect = temp_arena.pushArray(
        commands.push_buffer_element_count,
        RenderEntryClipRect,
        .aligned(@alignOf(RenderEntryClipRect), true),
    );

    var out: [*]RenderEntryClipRect = result;
    var opt_rect: ?*RenderEntryClipRect = commands.first_clip_rect;
    while (opt_rect) |rect| : (opt_rect = @ptrCast(rect.next)) {
        out[0] = rect.*;
        out += 1;
    }

    return result;
}

pub fn getSortTempMemorySize(commands: *shared.RenderCommands) u64 {
    return commands.push_buffer_element_count * @sizeOf(SortSpriteBound);
}

fn addEdge(a: SpriteEdge, b: SpriteEdge) void {
    _ = a;
    _ = b;
}

fn buildSpriteGraph(input_node_count: u32, input_nodes: [*]SortSpriteBound, arena: *MemoryArena) void {
    if (input_node_count > 0) {
        var node_index_a: u32 = 0;
        while (node_index_a < input_node_count - 1) : (node_index_a += 1) {
            const a: *SortSpriteBound = @ptrCast(input_nodes + node_index_a);
            std.debug.assert(a.flags == 0);

            var node_index_b: u32 = node_index_a;
            while (node_index_b < input_node_count) : (node_index_b += 1) {
                const b: *SortSpriteBound = @ptrCast(input_nodes + node_index_b);

                if (a.screen_area.intersects(&b.screen_area)) {
                    var front_index: u32 = node_index_a;
                    var back_index: u32 = node_index_b;
                    if (isInFrontOf(b.sort_key, a.sort_key)) {
                        const temp: u32 = front_index;
                        front_index = back_index;
                        back_index = temp;
                    }

                    var edge: *SpriteEdge = arena.pushStruct(SpriteEdge, null);
                    const front: *SortSpriteBound = @ptrCast(input_nodes + front_index);
                    edge.front = front_index;
                    edge.behind = back_index;

                    edge.next_edge_with_same_front = front.first_edge_with_me_as_front;
                    front.first_edge_with_me_as_front = edge;
                }
            }
        }
    }
}

const SpriteGraphWalk = struct {
    input_nodes: [*]SortSpriteBound,
    out_index: [*]u32,
};

fn recursiveFrontToBack(walk: *SpriteGraphWalk, at_index: u32) void {
    const at: *SortSpriteBound = @ptrCast(walk.input_nodes + at_index);
    if ((at.flags & @intFromEnum(SpriteFlag.Visited)) == 0) {
        at.flags |= @intFromEnum(SpriteFlag.Visited);

        var opt_edge: ?*SpriteEdge = at.first_edge_with_me_as_front;
        while (opt_edge) |edge| : (opt_edge = edge.next_edge_with_same_front) {
            std.debug.assert(edge.front == at_index);
            recursiveFrontToBack(walk, edge.behind);
        }

        walk.out_index[0] = at.offset;
        walk.out_index += 1;
    }
}

fn walkSpriteGraph(input_node_count: u32, input_nodes: [*]SortSpriteBound, out_index_array: [*]u32) void {
    var walk: SpriteGraphWalk = .{
        .input_nodes = input_nodes,
        .out_index = out_index_array,
    };
    var node_index_a: u32 = 0;
    while (node_index_a < input_node_count) : (node_index_a += 1) {
        recursiveFrontToBack(&walk, node_index_a);
    }
    std.debug.assert((walk.out_index - out_index_array) == input_node_count);
}

pub fn getSortEntries(commands: *shared.RenderCommands) [*]SortSpriteBound {
    return @ptrFromInt(@intFromPtr(commands.push_buffer_base) + commands.sort_entry_at);
}

pub fn sortEntries(commands: *RenderCommands, temp_arena: *MemoryArena) [*]u32 {
    TimedBlock.beginFunction(@src(), .SortEntries);
    defer TimedBlock.endFunction(@src(), .SortEntries);

    const count: u32 = commands.push_buffer_element_count;
    const entries: [*]SortSpriteBound = getSortEntries(commands);
    const result: [*]u32 = temp_arena.pushArray(count, u32, .aligned(@alignOf(u32), true),
);

    if (true) {
        buildSpriteGraph(count, entries, temp_arena);
        walkSpriteGraph(count, entries, result);
    } else {
        var node_index_a: u32 = 0;
        while (node_index_a < count - 1) : (node_index_a += 1) {
            result[node_index_a] = entries[node_index_a].index;
        }
    }

    if (INTERNAL and false) {
        if (count > 0) {
            // Validate the sort result.
            var index: u32 = 0;
            while (index < @as(i32, @intCast(count)) - 1) : (index += 1) {
                var index_b: u32 = index + 1;
                // Partial ordering check, 0(n), only neighbors are verified.
                var count_b: u32 = 1;

                if (true) {
                    // Total ordering check, 0(n^2), all pairs verified.
                    count_b = count;
                }

                while (index_b < count_b) : (index_b += 1) {
                    const entry_a: [*]SortSpriteBound = entries + index;
                    const entry_b: [*]SortSpriteBound = entries + index_b;

                    if (isInFrontOf(entry_a[0].sort_key, entry_b[0].sort_key)) {
                        std.debug.assert(entry_a[0].sort_key.y_min == entry_b[0].sort_key.y_min and
                            entry_a[0].sort_key.y_max == entry_b[0].sort_key.y_max and
                            entry_a[0].sort_key.z_max == entry_b[0].sort_key.z_max);
                    }
                }
            }
        }
    }

    return result;
}

pub fn isInFrontOf(a: SpriteBound, b: SpriteBound) bool {
    const both_z_sprites: bool = a.y_min != a.y_max and b.y_min != b.y_max;
    const a_includes_b: bool = b.y_min >= a.y_min and b.y_min < a.y_max;
    const b_includes_a: bool = a.y_min >= b.y_min and a.y_min < b.y_max;

    const sort_by_z: bool = both_z_sprites or a_includes_b or b_includes_a;

    const result: bool = if (sort_by_z)
        a.z_max > b.z_max
    else
        a.y_min < b.y_min;

    return result;
}

fn swapSpriteBound(a: [*]SortSpriteBound, b: [*]SortSpriteBound) void {
    const temp: SortSpriteBound = b[0];
    b[0] = a[0];
    a[0] = temp;
}

pub fn mergeSortSpriteBound(count: u32, first: [*]SortSpriteBound, temp: [*]SortSpriteBound) void {
    if (count <= 1) {
        // Nothing to do.
    } else if (count == 2) {
        const entry_a: [*]SortSpriteBound = first;
        const entry_b: [*]SortSpriteBound = first + 1;
        if (isInFrontOf(entry_a[0].sort_key, entry_b[0].sort_key)) {
            swapSpriteBound(entry_a, entry_b);
        }
    } else {
        const half0: u32 = @divFloor(count, 2);
        const half1: u32 = count - half0;

        std.debug.assert(half0 >= 1);
        std.debug.assert(half1 >= 1);

        const in_half0: [*]SortSpriteBound = first;
        const in_half1: [*]SortSpriteBound = first + half0;
        const end: [*]SortSpriteBound = first + count;

        mergeSortSpriteBound(half0, in_half0, temp);
        mergeSortSpriteBound(half1, in_half1, temp);

        var read_half0: [*]SortSpriteBound = in_half0;
        var read_half1: [*]SortSpriteBound = in_half1;

        var out: [*]SortSpriteBound = temp;
        var index: u32 = 0;
        while (index < count) : (index += 1) {
            if (read_half0 == in_half1) {
                out[0] = read_half1[0];
                read_half1 += 1;
                out += 1;
            } else if (read_half1 == end) {
                out[0] = read_half0[0];
                read_half0 += 1;
                out += 1;
            } else if (isInFrontOf(read_half1[0].sort_key, read_half0[0].sort_key)) {
                out[0] = read_half0[0];
                read_half0 += 1;
                out += 1;
            } else {
                out[0] = read_half1[0];
                read_half1 += 1;
                out += 1;
            }
        }

        std.debug.assert(out == (temp + count));
        std.debug.assert(read_half0 == in_half1);
        std.debug.assert(read_half1 == end);

        index = 0;
        while (index < count) : (index += 1) {
            first[index] = temp[index];
        }
    }
}

fn isZSprite(bound: SpriteBound) bool {
    return bound.y_min != bound.y_max;
}

fn verifyBuffer(count: u32, buffer: [*]SortSpriteBound, z_sprite: bool) void {
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        std.debug.assert(isZSprite(buffer[index].sort_key) == z_sprite);
        if (index > 0) {
            std.debug.assert(isInFrontOf(buffer[index].sort_key, buffer[index - 1].sort_key));
        }
    }
}

pub fn separatedSort(count: u32, first: [*]SortSpriteBound, temp: [*]SortSpriteBound) void {
    var y_count: u32 = 0;
    var z_count: u32 = 0;
    {
        var index: u32 = 0;
        while (index < count) : (index += 1) {
            const this: [*]SortSpriteBound = first + index;
            if (isZSprite(this[0].sort_key)) {
                temp[z_count] = this[0];
                z_count += 1;
            } else {
                first[y_count] = this[0];
                y_count += 1;
            }
        }
    }

    if (INTERNAL) {
        verifyBuffer(y_count, first, false);
        verifyBuffer(z_count, temp, true);
    }

    mergeSortSpriteBound(y_count, first, temp + z_count);
    mergeSortSpriteBound(z_count, temp, first + y_count);

    if (y_count == 1) {
        temp[z_count] = first[0];
    } else if (y_count == 2) {
        temp[y_count] = first[0];
        temp[y_count + 1] = first[1];
    }

    const in_half0: [*]SortSpriteBound = temp;
    const in_half1: [*]SortSpriteBound = temp + z_count;

    if (INTERNAL) {
        verifyBuffer(y_count, in_half1, false);
        verifyBuffer(z_count, in_half0, true);
    }

    const end: [*]SortSpriteBound = in_half1 + y_count;
    var read_half0: [*]SortSpriteBound = in_half0;
    var read_half1: [*]SortSpriteBound = in_half1;

    var out: [*]SortSpriteBound = first;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (read_half0 == in_half1) {
            out[0] = read_half1[0];
            read_half1 += 1;
            out += 1;
        } else if (read_half1 == end) {
            out[0] = read_half0[0];
            read_half0 += 1;
            out += 1;
            // TODO: This merge comparison can be simpler now since we know which sprite is a Z sprite and which is a Y sprite.
        } else if (isInFrontOf(read_half1[0].sort_key, read_half0[0].sort_key)) {
            out[0] = read_half0[0];
            read_half0 += 1;
            out += 1;
        } else {
            out[0] = read_half1[0];
            read_half1 += 1;
            out += 1;
        }
    }

    std.debug.assert(out == (first + count));
    std.debug.assert(read_half0 == in_half1);
    std.debug.assert(read_half1 == end);
}
