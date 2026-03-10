const math = @import("math.zig");
const renderer = @import("renderer.zig");

// Types.
const Matrix4x4 = math.Matrix4x4;
const Vector3 = math.Vector3;
const RenderGroup = renderer.RenderGroup;

pub const Camera = struct {
    pitch: f32,
    orbit: f32,
    dolly: f32,
    focal_length: f32,
    near_clip_plane: f32,
    far_clip_plane: f32,
    offset: Vector3,

    fog_start: f32,
    fog_end: f32,

    clip_alpha_start: f32,
    clip_alpha_end: f32,

    pub const standard: Camera = .{
        .pitch = 0.3 * math.PI32, // Tilt of the camera.
        .orbit = 0, // Rotation of the camera around the subject.
        .dolly = 20, // Distance away from the subject.
        .focal_length = 3, // Amount of perspective foreshortening.
        .near_clip_plane = 0.2, // Closest you can be to the camera and still be seen.
        .far_clip_plane = 1000, // Furthest you can be from the camera and still be seen.
        .offset = .new(0, 0, -1),
        .fog_start = 8,
        .fog_end = 20,
        .clip_alpha_start = 2,
        .clip_alpha_end = 2.25,
    };

    pub fn getObjectMatrix(self: *Camera) Matrix4x4 {
        return buildObjectMatrix(self.offset, self.orbit, self.pitch, self.dolly);
    }

    pub fn viewFromCamera(self: *Camera, group: *RenderGroup) void {
        var camera_matrix: Matrix4x4 = self.getObjectMatrix();
        const camera_z: Vector3 = camera_matrix.getColumn(2);

        var fog: renderer.FogParams = .{
            .direction = camera_z.negated(),
            .start_distance = self.fog_start,
            .end_distance = self.fog_end,
        };

        var alpha_clip: renderer.AlphaClipParams = .{
            .delta_start_distance = self.clip_alpha_start,
            .delta_end_distance = self.clip_alpha_end,
        };

        group.setCameraTransform(
            self.focal_length,
            camera_matrix.getColumn(0),
            camera_matrix.getColumn(1),
            camera_z,
            camera_matrix.getColumn(3),
            0,
            self.near_clip_plane,
            self.far_clip_plane,
            &fog,
            &alpha_clip,
        );
    }
};

pub fn buildObjectMatrix(offset: Vector3, orbit: f32, pitch: f32, dolly: f32) Matrix4x4 {
    return Matrix4x4.translation(offset)
        .times(.zRotation(orbit))
        .times(.xRotation(pitch))
        .times(.translation(.new(0, 0, dolly)));
}
