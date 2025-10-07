pub var global_config = Config{};

pub const Config = struct {
    Renderer_Camera_UseDebug: bool = false,
    Renderer_Camera_DebugDistance: f32 = 30,
    Renderer_Camera_RoomBased: bool = true,
    Renderer_Lighting_ShowReflectors: bool = true,
    Renderer_Lighting_ShowVisibility: bool = false,
    Renderer_Lighting_IterationCount: usize = 4,
    Renderer_Lighting_OcclusionIterationCount: usize = 0,
    AI_Familiar_FollowsHero: bool = false,
    Particles_Test: bool = false,
    Particles_ShowGrid: bool = false,
    Game_SkipIntro: bool = true,
    Simulation_TimestepPercentage: f32 = 100,
    Simulation_VisualizeCollisionVolumes: bool = false,
    Simulation_InspectSelectedEntity: bool = true,
};
