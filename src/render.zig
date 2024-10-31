//! Software renderer.
//!
//! 1: Everywhere outside the renderer, Y always goeas upward, X to the right.
//!
//! 2: All bitmaps including the render target are assumed to be bottom-up (meaning that the first row pointer points
//! to the bottom-most row when viewed on the screen).
//!
//! 3: It is mandatory that all inputs to the renderer are in world coordinates (meters), not pixels. If for some
//! reason something absolutely has to be specified in pixels, that will be explicitly marked in the API, but
//! this should occur exceedingly sparingly.
//!
//! 4: Z is a special coordinate because it is broken up into discrete slices, and the renderer actually understands
//! these slices. Z slices are what control the scaling of things, whereas Z offsets inside a slice are what control
//! Y offsetting.
//!
//! 5: All color values specified to the renderer using the Color and Color3 types are in non-premultiplied alpha.
//!

const shared = @import("shared.zig");
const math = @import("math.zig");
const asset = @import("asset.zig");
const intrinsics = @import("intrinsics.zig");
const debug = @import("debug.zig");
const file_formats = @import("file_formats");
const std = @import("std");

pub const ENTITY_VISIBLE_PIECE_COUNT = 4096;

// Types.
const Vector2 = math.Vector2;
const Vector2i = math.Vector2i;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;
const Color3 = math.Color3;
const Rectangle2 = math.Rectangle2;
const Rectangle2i = math.Rectangle2i;
const LoadedBitmap = asset.LoadedBitmap;
const LoadedFont = asset.LoadedFont;

const Vec4f = math.Vec4f;
const Vec4u = math.Vec4u;
const Vec4i = math.Vec4i;

pub const EnvironmentMap = extern struct {
    lod: [4]LoadedBitmap,
    z_position: f32,
};

const BilinearSample = struct {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
};

pub const RenderEntityBasisResult = extern struct {
    position: Vector2 = Vector2.zero(),
    scale: f32 = 0,
    valid: bool = false,
};

pub const RenderEntryType = enum(u8) {
    RenderEntryClear,
    RenderEntryBitmap,
    RenderEntryRectangle,
    RenderEntryCoordinateSystem,
    RenderEntrySaturation,
};

pub const RenderEntryHeader = extern struct {
    type: RenderEntryType,
};

pub const RenderEntryClear = extern struct {
    color: Color,
};

pub const RenderEntrySaturation = extern struct {
    level: f32,
};

pub const RenderEntryBitmap = extern struct {
    bitmap: ?*const LoadedBitmap,
    position: Vector2,
    size: Vector2,
    color: Color,
};

pub const RenderEntryRectangle = extern struct {
    position: Vector2,
    dimension: Vector2 = Vector2.zero(),
    color: Color,
};

/// This is only for testing.
pub const RenderEntryCoordinateSystem = extern struct {
    origin: Vector2,
    x_axis: Vector2,
    y_axis: Vector2,
    color: Color,

    texture: *LoadedBitmap,
    normal_map: ?*LoadedBitmap,

    pixels_to_meters: f32,

    top: *EnvironmentMap,
    middle: *EnvironmentMap,
    bottom: *EnvironmentMap,
};

const RenderTransform = extern struct {
    orthographic: bool,

    meters_to_pixels: f32,
    screen_center: Vector2,

    focal_length: f32,
    distance_above_target: f32,

    offset_position: Vector3,
    scale: f32,
};

const TileRenderWork = struct {
    group: *RenderGroup,
    output_target: *LoadedBitmap,
    clip_rect: Rectangle2i,
};

pub fn doTileRenderWork(queue: ?*shared.PlatformWorkQueue, data: *anyopaque) callconv(.C) void {
    _ = queue;
    const work: *TileRenderWork = @ptrCast(@alignCast(data));

    work.group.renderTo(work.output_target, work.clip_rect, true);
    work.group.renderTo(work.output_target, work.clip_rect, false);
}

fn getRenderEntityBasisPosition(transform: *RenderTransform, original_position: Vector3) RenderEntityBasisResult {
    var timed_block = shared.TimedBlock.begin(@src(), .GetRenderEntityBasisPosition);
    defer timed_block.end();

    var result = RenderEntityBasisResult{};

    const position = original_position.xy().toVector3(0).plus(transform.offset_position);

    if (transform.orthographic) {
        result.position = transform.screen_center.plus(position.xy().scaledTo(transform.meters_to_pixels));
        result.scale = transform.meters_to_pixels;
        result.valid = true;
    } else {
        const offset_z: f32 = 0;
        var distance_above_target = transform.distance_above_target;
        if (false) {
            // TODO: How do we want to control the debug camera?
            distance_above_target += 50;
        }

        const distance_to_position_z = distance_above_target - position.z();
        const near_clip_plane = 0.2;

        const raw_xy = position.xy().toVector3(1);

        if (distance_to_position_z > near_clip_plane) {
            const projected_xy = raw_xy.scaledTo((1.0 / distance_to_position_z) * transform.focal_length);
            result.scale = projected_xy.z() * transform.meters_to_pixels;
            result.position = transform.screen_center.plus(projected_xy.xy().scaledTo(transform.meters_to_pixels))
                .plus(Vector2.new(0, result.scale * offset_z));
            result.valid = true;
        }
    }

    return result;
}

pub const RenderGroup = extern struct {
    assets: *asset.Assets,
    global_alpha: f32,

    generation_id: u32,

    monitor_half_dim_in_meters: Vector2,

    transform: RenderTransform,

    max_push_buffer_size: u32,
    push_buffer_size: u32,
    push_buffer_base: [*]u8,

    missing_resource_count: u32,
    renders_in_background: bool,

    inside_renderer: bool,

    pub fn allocate(
        assets: *asset.Assets,
        arena: *shared.MemoryArena,
        max_push_buffer_size: u32,
        renders_in_background: bool,
    ) *RenderGroup {
        var result = arena.pushStruct(RenderGroup);

        if (max_push_buffer_size == 0) {
            result.max_push_buffer_size = @intCast(arena.getRemainingSize(null));
        } else {
            result.max_push_buffer_size = max_push_buffer_size;
        }

        result.push_buffer_size = 0;
        result.push_buffer_base = @ptrCast(arena.pushSize(result.max_push_buffer_size, @alignOf(u8)));

        result.assets = assets;
        result.global_alpha = 1;

        result.generation_id = 0;

        // Default transform.
        result.transform.offset_position = Vector3.zero();
        result.transform.scale = 1;

        result.missing_resource_count = 0;
        result.renders_in_background = renders_in_background;

        result.inside_renderer = false;

        return result;
    }

    pub fn allResourcesPresent(self: *RenderGroup) bool {
        return self.missing_resource_count == 0;
    }

    pub fn perspectiveMode(
        self: *RenderGroup,
        pixel_width: i32,
        pixel_height: i32,
        meters_to_pixels: f32,
        focal_length: f32,
        distance_above_target: f32,
    ) void {
        const pixels_to_meters: f32 = math.safeRatio1(1.0, meters_to_pixels);
        self.monitor_half_dim_in_meters = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)) * pixels_to_meters,
            0.5 * @as(f32, @floatFromInt(pixel_height)) * pixels_to_meters,
        );

        self.transform.meters_to_pixels = meters_to_pixels;
        self.transform.focal_length = focal_length;
        self.transform.distance_above_target = distance_above_target;
        self.transform.screen_center = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)),
            0.5 * @as(f32, @floatFromInt(pixel_height)),
        );
        self.transform.orthographic = false;
    }

    pub fn orthographicMode(
        self: *RenderGroup,
        pixel_width: i32,
        pixel_height: i32,
        meters_to_pixels: f32,
    ) void {
        const pixels_to_meters: f32 = math.safeRatio1(1.0, meters_to_pixels);
        self.monitor_half_dim_in_meters = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)) * pixels_to_meters,
            0.5 * @as(f32, @floatFromInt(pixel_height)) * pixels_to_meters,
        );

        self.transform.meters_to_pixels = meters_to_pixels;
        self.transform.focal_length = 1;
        self.transform.distance_above_target = 1;
        self.transform.screen_center = Vector2.new(
            0.5 * @as(f32, @floatFromInt(pixel_width)),
            0.5 * @as(f32, @floatFromInt(pixel_height)),
        );
        self.transform.orthographic = true;
    }

    fn pushRenderElement(self: *RenderGroup, comptime T: type) ?*T {
        var timed_block = shared.TimedBlock.begin(@src(), .PushRenderElement);
        defer timed_block.end();

        const entry_type: RenderEntryType = @field(RenderEntryType, @typeName(T)[7..]);
        return @ptrCast(@alignCast(self.pushRenderElement_(@sizeOf(T), entry_type, @alignOf(T))));
    }

    fn pushRenderElement_(
        self: *RenderGroup,
        in_size: u32,
        entry_type: RenderEntryType,
        comptime alignment: u32,
    ) ?*void {
        std.debug.assert(self.inside_renderer);

        var result: ?*void = null;
        const size = in_size + @sizeOf(RenderEntryHeader);

        if ((self.push_buffer_size + size) < self.max_push_buffer_size) {
            const header: *RenderEntryHeader = @ptrCast(self.push_buffer_base + self.push_buffer_size);
            header.type = entry_type;

            const data_address = @intFromPtr(header) + @sizeOf(RenderEntryHeader);
            const aligned_address = std.mem.alignForward(usize, data_address, alignment);
            const aligned_offset = aligned_address - data_address;
            const aligned_size = size + aligned_offset;

            result = @ptrFromInt(aligned_address);
            self.push_buffer_size += @intCast(aligned_size);
        } else {
            unreachable;
        }

        return result;
    }

    // Renderer API.
    pub fn unproject(self: *RenderGroup, projected_xy: Vector2, distance_from_camera: f32) Vector2 {
        return projected_xy.scaledTo(distance_from_camera / self.transform.focal_length);
    }

    pub fn getCameraRectangleAtDistance(self: *RenderGroup, distance_from_camera: f32) Rectangle2 {
        const raw_xy = self.unproject(self.monitor_half_dim_in_meters, distance_from_camera);
        return Rectangle2.fromCenterHalfDimension(Vector2.zero(), raw_xy);
    }

    pub fn getCameraRectangleAtTarget(self: *RenderGroup) Rectangle2 {
        return self.getCameraRectangleAtDistance(self.transform.distance_above_target);
    }

    pub fn pushClear(self: *RenderGroup, color: Color) void {
        if (self.pushRenderElement(RenderEntryClear)) |entry| {
            entry.color = color;
        }
    }

    pub fn pushSaturation(self: *RenderGroup, level: f32) void {
        if (self.pushRenderElement(RenderEntrySaturation)) |entry| {
            entry.level = level;
        }
    }

    pub fn pushBitmap(
        self: *RenderGroup,
        bitmap: *const LoadedBitmap,
        height: f32,
        offset: Vector3,
        color: Color,
    ) void {
        const size = Vector2.new(height * bitmap.width_over_height, height);
        const alignment = bitmap.alignment_percentage.hadamardProduct(size);
        const position = offset.minus(alignment.toVector3(0));

        const basis = getRenderEntityBasisPosition(&self.transform, position);
        if (basis.valid) {
            if (self.pushRenderElement(RenderEntryBitmap)) |entry| {
                entry.bitmap = bitmap;
                entry.position = basis.position;
                entry.size = size.scaledTo(basis.scale);
                entry.color = color.scaledTo(self.global_alpha);
            }
        }
    }

    pub fn pushBitmapId(
        self: *RenderGroup,
        opt_id: ?file_formats.BitmapId,
        height: f32,
        offset: Vector3,
        color: Color,
    ) void {
        if (opt_id) |id| {
            var opt_bitmap = self.assets.getBitmap(id, self.generation_id);

            if (self.renders_in_background and opt_bitmap == null) {
                self.assets.loadBitmap(id, true);
                opt_bitmap = self.assets.getBitmap(id, self.generation_id);
            }

            if (opt_bitmap) |bitmap| {
                self.pushBitmap(bitmap, height, offset, color);
            } else {
                std.debug.assert(!self.renders_in_background);

                self.assets.loadBitmap(id, false);
                self.missing_resource_count += 1;
            }
        }
    }

    pub fn pushFont(
        self: *RenderGroup,
        opt_id: ?file_formats.FontId,
    ) ?*LoadedFont {
        var opt_font: ?*LoadedFont = null;

        if (opt_id) |id| {
            opt_font = self.assets.getFont(id, self.generation_id);

            if (opt_font == null) {
                std.debug.assert(!self.renders_in_background);

                self.assets.loadFont(id, false);
                self.missing_resource_count += 1;
            }
        }

        return opt_font;
    }

    pub fn pushRectangle(
        self: *RenderGroup,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
    ) void {
        const position = offset.minus(dimension.scaledTo(0.5).toVector3(0));

        const basis = getRenderEntityBasisPosition(&self.transform, position);
        if (basis.valid) {
            if (self.pushRenderElement(RenderEntryRectangle)) |entry| {
                entry.position = basis.position;
                entry.dimension = dimension.scaledTo(basis.scale);
                entry.color = color;
            }
        }
    }

    pub fn pushRectangleOutline(
        self: *RenderGroup,
        dimension: Vector2,
        offset: Vector3,
        color: Color,
    ) void {
        const thickness: f32 = 0.15;
        self.pushRectangle(
            Vector2.new(dimension.x() + thickness, thickness),
            offset.minus(Vector3.new(0, dimension.y() / 2, 0)),
            color,
        );
        self.pushRectangle(
            Vector2.new(dimension.x() + thickness, thickness),
            offset.plus(Vector3.new(0, dimension.y() / 2, 0)),
            color,
        );

        self.pushRectangle(
            Vector2.new(thickness, dimension.y() + thickness),
            offset.minus(Vector3.new(dimension.x() / 2, 0, 0)),
            color,
        );
        self.pushRectangle(
            Vector2.new(thickness, dimension.y() + thickness),
            offset.plus(Vector3.new(dimension.x() / 2, 0, 0)),
            color,
        );
    }

    pub fn pushCoordinateSystem(
        self: *RenderGroup,
        origin: Vector2,
        x_axis: Vector2,
        y_axis: Vector2,
        color: Color,
        texture: *LoadedBitmap,
        normal_map: ?*LoadedBitmap,
        top: *EnvironmentMap,
        middle: *EnvironmentMap,
        bottom: *EnvironmentMap,
    ) void {
        _ = self;
        _ = origin;
        _ = x_axis;
        _ = y_axis;
        _ = color;
        _ = texture;
        _ = normal_map;
        _ = top;
        _ = middle;
        _ = bottom;
        // const basis = getRenderEntityBasisPosition(&entry.entity_basis, screen_dimension);
        //
        // if (basis.valid) {
        //     if (self.pushRenderElement(RenderEntryCoordinateSystem)) |entry| {
        //         entry.origin = origin;
        //         entry.x_axis = x_axis;
        //         entry.y_axis = y_axis;
        //         entry.color = color;
        //         entry.texture = texture;
        //         entry.normal_map = normal_map;
        //         entry.top = top;
        //         entry.middle = middle;
        //         entry.bottom = bottom;
        //     }
        // }
    }

    pub fn singleRenderTo(
        self: *RenderGroup,
        output_target: *LoadedBitmap,
    ) void {
        var timed_block = shared.TimedBlock.begin(@src(), .SingleRenderToOutput);
        defer timed_block.end();

        std.debug.assert(self.inside_renderer);

        std.debug.assert((@intFromPtr(output_target.memory) & 15) == 0);

        const clip_rect = Rectangle2i.new(0, 0, output_target.width, output_target.height);
        var work = TileRenderWork{
            .group = self,
            .output_target = output_target,
            .clip_rect = clip_rect,
        };

        doTileRenderWork(null, @ptrCast(&work));
    }

    pub fn tiledRenderTo(
        self: *RenderGroup,
        render_queue: *shared.PlatformWorkQueue,
        output_target: *LoadedBitmap,
    ) void {
        var timed_block = shared.TimedBlock.begin(@src(), .TiledRenderToOutput);
        defer timed_block.end();

        std.debug.assert(self.inside_renderer);

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
            .group = self,
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
                    shared.platform.addQueueEntry(render_queue, &doTileRenderWork, work);
                } else {
                    doTileRenderWork(render_queue, work);
                }
            }
        }

        shared.platform.completeAllQueuedWork(render_queue);
    }

    pub fn renderTo(self: *RenderGroup, output_target: *LoadedBitmap, clip_rect: Rectangle2i, even: bool) void {
        var timed_block = shared.TimedBlock.begin(@src(), .RenderToOutput);
        defer timed_block.end();

        const null_pixels_to_meters: f32 = 1.0;

        var base_address: u32 = 0;
        while (base_address < self.push_buffer_size) {
            const header: *RenderEntryHeader = @ptrCast(self.push_buffer_base + base_address);
            const alignment: usize = switch (header.type) {
                .RenderEntryClear => @alignOf(RenderEntryClear),
                .RenderEntryBitmap => @alignOf(RenderEntryBitmap),
                .RenderEntryRectangle => @alignOf(RenderEntryRectangle),
                .RenderEntryCoordinateSystem => @alignOf(RenderEntryCoordinateSystem),
                .RenderEntrySaturation => @alignOf(RenderEntrySaturation),
            };

            const header_address = @intFromPtr(header);
            const data_address = header_address + @sizeOf(RenderEntryHeader);
            const aligned_address = std.mem.alignForward(usize, data_address, alignment);
            const aligned_offset: u32 = @intCast(aligned_address - data_address);
            const data: *void = @ptrFromInt(aligned_address);

            base_address += @sizeOf(RenderEntryHeader) + aligned_offset;

            switch (header.type) {
                .RenderEntryClear => {
                    const entry: *RenderEntryClear = @ptrCast(@alignCast(data));
                    const dimension = Vector2.newI(output_target.width, output_target.height);
                    drawRectangle(output_target, Vector2.zero(), dimension, entry.color, clip_rect, even);

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntrySaturation => {
                    const entry: *RenderEntrySaturation = @ptrCast(@alignCast(data));

                    changeSaturation(output_target, entry.level);

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryBitmap => {
                    const entry: *RenderEntryBitmap = @ptrCast(@alignCast(data));
                    if (entry.bitmap) |bitmap| {
                        if (false) {
                            drawRectangleSlowly(
                                output_target,
                                entry.position,
                                Vector2.new(entry.size.x(), 0),
                                Vector2.new(0, entry.size.y()),
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
                                Vector2.new(entry.size.x(), 0),
                                Vector2.new(0, entry.size.y()),
                                entry.color,
                                @constCast(bitmap),
                                null_pixels_to_meters,
                                clip_rect,
                                even,
                            );
                        }
                    }

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryRectangle => {
                    const entry: *RenderEntryRectangle = @ptrCast(@alignCast(data));

                    drawRectangle(
                        output_target,
                        entry.position,
                        entry.position.plus(entry.dimension),
                        entry.color,
                        clip_rect,
                        even,
                    );

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
                .RenderEntryCoordinateSystem => {
                    const entry: *RenderEntryCoordinateSystem = @ptrCast(@alignCast(data));

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

                    base_address += @sizeOf(@TypeOf(entry.*));
                },
            }
        }
    }

    pub fn beginRender(self: *RenderGroup) void {
        var timed_block = shared.TimedBlock.begin(@src(), .BeginRender);
        defer timed_block.end();

        std.debug.assert(!self.inside_renderer);
        self.inside_renderer = true;

        self.generation_id = self.assets.beginGeneration();
    }

    pub fn endRender(self: *RenderGroup) void {
        var timed_block = shared.TimedBlock.begin(@src(), .EndRender);
        defer timed_block.end();

        std.debug.assert(self.inside_renderer);
        self.inside_renderer = false;

        self.assets.endGeneration(self.generation_id);
        self.generation_id = 0;
        self.push_buffer_size = 0;
    }
};

pub fn drawRectangle(
    draw_buffer: *LoadedBitmap,
    min: Vector2,
    max: Vector2,
    color: Color,
    clip_rect: Rectangle2i,
    even: bool,
) void {
    var timed_block = shared.TimedBlock.begin(@src(), .DrawRectangle);
    defer timed_block.end();

    var fill_rect = Rectangle2i.new(
        intrinsics.floorReal32ToInt32(min.x()),
        intrinsics.floorReal32ToInt32(min.y()),
        intrinsics.floorReal32ToInt32(max.x()),
        intrinsics.floorReal32ToInt32(max.y()),
    );
    fill_rect = fill_rect.getIntersectionWith(clip_rect);
    if (@intFromBool(!even) == fill_rect.min.y() & 1) {
        _ = fill_rect.min.setY(fill_rect.min.y() + 1);
    }

    // Set the pointer to the top left corner of the rectangle.
    var row: [*]u8 = @ptrCast(draw_buffer.memory);
    row += @as(
        u32,
        @intCast((fill_rect.min.x() * shared.BITMAP_BYTES_PER_PIXEL) +
            (fill_rect.min.y() * @as(i32, @intCast(draw_buffer.pitch)))),
    );

    var y = fill_rect.min.y();
    while (y < fill_rect.max.y()) : (y += 2) {
        var pixel = @as([*]u32, @ptrCast(@alignCast(row)));

        var x = fill_rect.min.x();
        while (x < fill_rect.max.x()) : (x += 1) {
            pixel[0] = color.packColor();
            pixel += 1;
        }

        row += @as(usize, @intCast(draw_buffer.pitch * 2));
    }
}

fn changeSaturation(draw_buffer: *LoadedBitmap, level: f32) void {
    var timed_block = shared.TimedBlock.begin(@src(), .ChangeSaturation);
    defer timed_block.end();

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
    even: bool,
) void {
    _ = pixels_to_meters;

    var timed_block = shared.TimedBlock.begin(@src(), .DrawRectangleQuickly);
    defer timed_block.end();

    var color = color_in;
    _ = color.setRGB(color.rgb().scaledTo(color.a()));

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

    if (@intFromBool(!even) == fill_rect.min.y() & 1) {
        _ = fill_rect.min.setY(fill_rect.min.y() + 1);
    }

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

        const row_advance: usize = @intCast(draw_buffer.pitch * 2);
        var row: [*]u8 = @ptrCast(draw_buffer.memory);
        row += @as(u32, @intCast((min_x * shared.BITMAP_BYTES_PER_PIXEL) + (min_y * draw_buffer.pitch)));

        var process_timed_block = shared.TimedBlock.beginWithCount(@src(), .ProcessPixel, @intCast(@divFloor(fill_rect.getClampedArea(), 2)));
        defer process_timed_block.end();

        var y: i32 = min_y;
        while (y < max_y) : (y += 2) {
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
    color_in: Color,
    texture: *LoadedBitmap,
    opt_normal_map: ?*LoadedBitmap,
    top: *EnvironmentMap,
    middle: *EnvironmentMap,
    bottom: *EnvironmentMap,
    pixels_to_meters: f32,
) void {
    const timed_block = shared.TimedBlock.begin(@src(), .DrawRectangleSlowly);
    defer timed_block.end();

    var color = color_in;
    _ = color.setRGB(color.rgb().scaledTo(color.a()));

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

    const timed_block_pixel = shared.TimedBlock.beginWithCount(@src(), .ProcessPixel, @intCast((x_max - x_min + 1) * (y_max - y_min + 1)));
    defer timed_block_pixel.end();

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
    var timed_block = shared.TimedBlock.begin(@src(), .DrawBitmap);
    defer timed_block.end();

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

    if (false) {
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
