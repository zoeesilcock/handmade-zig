const asset = @import("asset.zig");
const math = @import("math.zig");
const render = @import("render.zig");
const shared = @import("shared.zig");
const file_formats = @import("file_formats");
const std = @import("std");

const AssetTagId = file_formats.AssetTagId;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;

pub fn renderCutscene(
    assets: *asset.Assets,
    render_group: *render.RenderGroup,
    draw_buffer: *asset.LoadedBitmap,
    cutscene_time: f32,
) void {
    const width_of_monitor_in_meters = 0.635;
    const meters_to_pixels: f32 = @as(f32, @floatFromInt(draw_buffer.width)) * width_of_monitor_in_meters;

    const focal_length: f32 = 0.6;

    const time_start: f32 = 0;
    const time_end: f32 = 5;
    const normal_time = math.clamp01MapToRange(time_start, time_end, cutscene_time);

    const camera_start: Vector3 = Vector3.new(0, 0, 0);
    const camera_end: Vector3 = Vector3.new(-4, -2, 0);
    const camera_offset: Vector3 = camera_start.lerp(camera_end, normal_time);
    const distance_above_ground: f32 = 10 - normal_time * 5;
    render_group.perspectiveMode(
        draw_buffer.width,
        draw_buffer.height,
        meters_to_pixels,
        focal_length,
        distance_above_ground,
    );

    var match_vector = asset.AssetVector{};
    var weight_vector = asset.AssetVector{};
    weight_vector.e[AssetTagId.ShotIndex.toInt()] = 10;
    weight_vector.e[AssetTagId.LayerIndex.toInt()] = 1;

    const layer_placement: []const Vector4 = &.{
        Vector4.new(0, 0, distance_above_ground - 200, 300), // Sky background.
        Vector4.new(0, 0, -170, 300), // Weird sky light.
        Vector4.new(0, 0, -100, 40), // Backmost row of trees
        Vector4.new(0, 10, -70, 80), // Middle hills and trees.
        Vector4.new(0, 0, -50, 70), // Front hills and trees.
        Vector4.new(30, 0, -30, 50), // Right side tree and fence.
        Vector4.new(0, -2, -20, 40), // Orphanage.
        Vector4.new(2, -1, -5, 25), // Foreground.
    };

    const shot_index: u32 = 1;
    match_vector.e[AssetTagId.ShotIndex.toInt()] = shot_index;
    var layer_index: u32 = 1;
    while (layer_index <= 8) : (layer_index += 1) {
        const placement: Vector4 = layer_placement[layer_index - 1];
        render_group.transform.offset_position = placement.xyz().minus(camera_offset);
        match_vector.e[AssetTagId.LayerIndex.toInt()] = @floatFromInt(layer_index);

        const layer_image = assets.getBestMatchBitmap(.OpeningCutscene, &match_vector, &weight_vector);
        render_group.pushBitmapId(layer_image, placement.w(), Vector3.zero(), Color.white(), null);
    }
}
