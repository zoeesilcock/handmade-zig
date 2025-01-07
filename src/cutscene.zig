const asset = @import("asset.zig");
const math = @import("math.zig");
const render = @import("render.zig");
const shared = @import("shared.zig");
const file_formats = @import("file_formats");
const std = @import("std");

const AssetTagId = file_formats.AssetTagId;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;
const Color = math.Color;

const SceneLayerFlags = enum(u32) {
    AtInfinity = 0x1,
    CounterCameraX = 0x2,
    CounterCameraY = 0x4,
    Transient = 0x8,
    Floaty = 0x10,
};

const SceneLayer = struct {
    position: Vector3,
    height: f32,
    flags: u32 = 0,
    params: Vector2 = Vector2.zero(),
};

const LayeredScene = struct {
    asset_type: file_formats.AssetTypeId,
    shot_index: u32,
    layers: []const SceneLayer,
    duration: f32,
    camera_start: Vector3,
    camera_end: Vector3,
};

const intro_cutscene: []const LayeredScene = &.{
    LayeredScene{
        .shot_index = 1,
        .asset_type = .OpeningCutscene,
        .duration = 20,
        .camera_start = Vector3.new(0, 0, 10),
        .camera_end = Vector3.new(-4, -2, 5),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -200), .height = 300, .flags = @intFromEnum(SceneLayerFlags.AtInfinity) }, // Sky background.
            SceneLayer{ .position = Vector3.new(0, 0, -170), .height = 300 }, // Weird sky light.
            SceneLayer{ .position = Vector3.new(0, 0, -100), .height = 40 }, // Backmost row of trees.
            SceneLayer{ .position = Vector3.new(0, 10, -70), .height = 80 }, // Middle hills and trees.
            SceneLayer{ .position = Vector3.new(0, 0, -50), .height = 70 }, // Front hills and trees.
            SceneLayer{ .position = Vector3.new(30, 0, -30), .height = 50 }, // Right side tree and fence.
            SceneLayer{ .position = Vector3.new(0, -2, -20), .height = 40 }, // Orphanage.
            SceneLayer{ .position = Vector3.new(2, -1, -5), .height = 25 }, // Foreground.
        },
    },
    LayeredScene{
        .shot_index = 2,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(0.5, -0.5, -1),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(2, -1, -22), .height = 32 }, // Hero and tree.
            SceneLayer{ .position = Vector3.new(0, 0, -14), .height = 22 }, // Wall and window.
            SceneLayer{ .position = Vector3.new(0, 2, -8), .height = 10 }, // Icicles.
        },
    },
    LayeredScene{
        .shot_index = 3,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0.5, 0),
        .camera_end = Vector3.new(0, 6.5, -1.5),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -30), .height = 90, .flags = @intFromEnum(SceneLayerFlags.AtInfinity) }, // Sky.
            SceneLayer{ .position = Vector3.new(0, 0, -20), .height = 45, .flags = @intFromEnum(SceneLayerFlags.CounterCameraY) }, // Trees.
            SceneLayer{ .position = Vector3.new(0, -2, -4), .height = 15, .flags = @intFromEnum(SceneLayerFlags.CounterCameraY) }, // Window.
            SceneLayer{ .position = Vector3.new(0, 0.35, -0.5), .height = 1 }, // Hero.
        },
    },
    LayeredScene{
        .shot_index = 4,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(0, 0, -0.5),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -4), .height = 6 }, // Background.
            SceneLayer{ .position = Vector3.new(-1.2, -0.2, -4), .height = 4, .params = Vector2.new(0, 0.5), .flags = @intFromEnum(SceneLayerFlags.Transient) }, // Santa 1.
            SceneLayer{ .position = Vector3.new(-1.2, -0.2, -4), .height = 4, .params = Vector2.new(0.5, 1), .flags = @intFromEnum(SceneLayerFlags.Transient) }, // Santa 2.
            SceneLayer{ .position = Vector3.new(2.25, -1.5, -3), .height = 2 }, // Foreground 1.
            SceneLayer{ .position = Vector3.new(0, 0.35, -1), .height = 1 }, // Tinsel.
        },
    },
    LayeredScene{
        .shot_index = 5,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(0, 0.5, -1),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -20), .height = 30 }, // Background.
            SceneLayer{ .position = Vector3.new(0, 0, -5), .height = 8, .params = Vector2.new(0, 0.5), .flags = @intFromEnum(SceneLayerFlags.Transient) }, // Entrance.
            SceneLayer{ .position = Vector3.new(0, 0, -5), .height = 8, .params = Vector2.new(0.5, 1), .flags = @intFromEnum(SceneLayerFlags.Transient) }, // Entrance open.
            SceneLayer{ .position = Vector3.new(0, 0, -3), .height = 4, .params = Vector2.new(0.5, 1), .flags = @intFromEnum(SceneLayerFlags.Transient) }, // Crampus.
            SceneLayer{ .position = Vector3.new(0, 0, -2), .height = 3, .params = Vector2.new(0.5, 1), .flags = @intFromEnum(SceneLayerFlags.Transient) }, // Snow.
        },
    },

    LayeredScene{
        .shot_index = 6,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(-0.5, 0.5, -1),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -8), .height = 12 }, // Background.
            SceneLayer{ .position = Vector3.new(0, 0, -5), .height = 8 }, // Snow.
            SceneLayer{ .position = Vector3.new(1, -1, -3), .height = 3 }, // Scared child.
            SceneLayer{ .position = Vector3.new(0.85, -0.95, -3), .height = 0.5 }, // Tears.
            SceneLayer{ .position = Vector3.new(-2, -1, -2.5), .height = 2 }, // Other child.
            SceneLayer{ .position = Vector3.new(0.2, 0.5, -1), .height = 1 }, // Garland.
        },
    },

    LayeredScene{
        .shot_index = 7,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(2, 0, 0),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(-0.5, 0, -8), .height = 12, .flags = @intFromEnum(SceneLayerFlags.CounterCameraX) }, // Background.
            SceneLayer{ .position = Vector3.new(-1, 0, -4), .height = 6 }, // Crampus.
        },
    },

    LayeredScene{
        .shot_index = 8,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(0, -0.5, -1),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -8), .height = 12 }, // Background.
            SceneLayer{ .position = Vector3.new(0, -1, -5), .height = 4, .params = Vector2.new(0.05, 15), .flags = @intFromEnum(SceneLayerFlags.Floaty) }, // Glove.
            SceneLayer{ .position = Vector3.new(3, -1.5, -3), .height = 2 }, // Children.
            SceneLayer{ .position = Vector3.new(0, 0, -1.5), .height = 2.5 }, // Tinsel.
        },
    },

    LayeredScene{
        .shot_index = 9,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(-0.75, -0.5, -1),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -8), .height = 12 }, // Background.
            SceneLayer{ .position = Vector3.new(0, 0.25, -3), .height = 4 }, // Ceiling 1.
            SceneLayer{ .position = Vector3.new(1, 0, -2), .height = 3 }, // Ceiling 2.
            SceneLayer{ .position = Vector3.new(1, 0.1, -1), .height = 2 }, // Ceiling 3.
        },
    },

    LayeredScene{
        .shot_index = 10,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(-0.1, 0.05, -0.5),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(-15, 25, -100), .height = 130, .flags = @intFromEnum(SceneLayerFlags.AtInfinity) }, // Background.
            SceneLayer{ .position = Vector3.new(0, 0, -10), .height = 22 }, // Window.
            SceneLayer{ .position = Vector3.new(-0.8, -0.2, -3), .height = 4.5 }, // Hero.
            SceneLayer{ .position = Vector3.new(0, 0, -2), .height = 4.5 }, // Door.
            SceneLayer{ .position = Vector3.new(0, -0.25, -1), .height = 1.5 }, // Hats.
            SceneLayer{ .position = Vector3.new(0.2, 0.2, -0.5), .height = 1 }, // Tinsel.
        },
    },
    LayeredScene{
        .shot_index = 11,
        .duration = 20,
        .asset_type = .OpeningCutscene,
        .camera_start = Vector3.new(0, 0, 0),
        .camera_end = Vector3.new(0.6, 0.5, -2),
        .layers = &.{
            SceneLayer{ .position = Vector3.new(0, 0, -100), .height = 150, .flags = @intFromEnum(SceneLayerFlags.AtInfinity) }, // Background.
            SceneLayer{ .position = Vector3.new(0, 10, -40), .height = 40 }, // Hills.
            SceneLayer{ .position = Vector3.new(0, 3.2, -20), .height = 23 }, // Hills.
            SceneLayer{ .position = Vector3.new(0.25, 0.9, -10), .height = 13.5 }, // Hills.
            SceneLayer{ .position = Vector3.new(-0.5, 0.625, -5), .height = 7 }, // Trees.
            SceneLayer{ .position = Vector3.new(0, 0.1, -2.5), .height = 3.9 }, // Foreground.
            SceneLayer{ .position = Vector3.new(-0.3, -0.15, -1), .height = 1.2 }, // Hero.
        },
    },
};

pub fn renderCutscene(
    assets: *asset.Assets,
    render_group: *render.RenderGroup,
    draw_buffer: *asset.LoadedBitmap,
    cutscene_time: *f32,
) void {
    var pretty_stupid = false;
    var time_base: f32 = 0;
    var shot_index: u32 = 1;
    while (shot_index < intro_cutscene.len) : (shot_index += 1) {
        const scene: *const LayeredScene = &intro_cutscene[shot_index - 1];
        const time_start: f32 = time_base;
        const time_end = time_start + scene.duration;

        if (cutscene_time.* >= time_start and cutscene_time.* < time_end) {
            const normal_time = math.clamp01MapToRange(time_start, time_end, cutscene_time.*);
            renderLayeredScene(assets, render_group, draw_buffer, scene, normal_time);
            pretty_stupid = true;
        }

        time_base = time_end;
    }

    if (!pretty_stupid) {
        cutscene_time.* = 0;
    }
}

fn renderLayeredScene(
    assets: *asset.Assets,
    render_group: *render.RenderGroup,
    draw_buffer: *asset.LoadedBitmap,
    scene: *const LayeredScene,
    normal_time: f32,
) void {
    const width_of_monitor_in_meters = 0.635;
    const meters_to_pixels: f32 = @as(f32, @floatFromInt(draw_buffer.width)) * width_of_monitor_in_meters;
    const focal_length: f32 = 0.6;
    const camera_offset: Vector3 = scene.camera_start.lerp(scene.camera_end, normal_time);
    render_group.perspectiveMode(
        draw_buffer.width,
        draw_buffer.height,
        meters_to_pixels,
        focal_length,
        0,
    );

    var match_vector = asset.AssetVector{};
    var weight_vector = asset.AssetVector{};
    weight_vector.e[AssetTagId.ShotIndex.toInt()] = 10;
    weight_vector.e[AssetTagId.LayerIndex.toInt()] = 1;
    match_vector.e[AssetTagId.ShotIndex.toInt()] = @floatFromInt(scene.shot_index);

    var layer_index: u32 = 1;
    while (layer_index <= scene.layers.len) : (layer_index += 1) {
        const layer: SceneLayer = scene.layers[layer_index - 1];
        var active = true;
        var position: Vector3 = layer.position;

        if (layer.flags & @intFromEnum(SceneLayerFlags.Transient) != 0) {
            active = normal_time >= layer.params.x() and normal_time < layer.params.y();
        }

        if (active) {
            if (layer.flags & @intFromEnum(SceneLayerFlags.AtInfinity) != 0) {
                _ = position.setZ(position.z() + camera_offset.z());
            }

            if (layer.flags & @intFromEnum(SceneLayerFlags.Floaty) != 0) {
                _ = position.setY(position.y() + (layer.params.x() * @sin(layer.params.y() * normal_time)));
            }

            if (layer.flags & @intFromEnum(SceneLayerFlags.CounterCameraX) != 0) {
                _ = render_group.transform.offset_position.setX(position.x() + camera_offset.x());
            } else {
                _ = render_group.transform.offset_position.setX(position.x() - camera_offset.x());
            }

            if (layer.flags & @intFromEnum(SceneLayerFlags.CounterCameraY) != 0) {
                _ = render_group.transform.offset_position.setY(position.y() + camera_offset.y());
            } else {
                _ = render_group.transform.offset_position.setY(position.y() - camera_offset.y());
            }

            _ = render_group.transform.offset_position.setZ(position.z() - camera_offset.z());
            match_vector.e[AssetTagId.LayerIndex.toInt()] = @floatFromInt(layer_index);

            const layer_image = assets.getBestMatchBitmap(scene.asset_type, &match_vector, &weight_vector);
            render_group.pushBitmapId(layer_image, layer.height, Vector3.zero(), Color.white(), null);
        }
    }
}
