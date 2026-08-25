pub var global_config = Config{};

pub const Config = struct {
    Renderer_Camera_UseDebug: bool = false,
    Renderer_Camera_DebugDistance: f32 = 30,
    Renderer_Camera_RoomBased: bool = true,
    Renderer_Lighting_ShowReflectors: bool = true,
    AI_Familiar_FollowsHero: bool = false,
    Particles_Test: bool = false,
    Particles_ShowGrid: bool = false,
    Game_SkipIntro: bool = true,
    Simulation_TimestepPercentage: f32 = 100,
    // This feature causes the renderer push buffer to overflow, likely due to one of our structs being bigger than
    // Casey's. The current solution is to increase the size of the push_buffer_memory array on the OpenGL string in
    // renderer_opengl.zig.
    Simulation_VisualizeCollisionVolumes: bool = false,
    Simulation_InspectSelectedEntity: bool = true,
};
