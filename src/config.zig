pub const global_constants = GlobalConstants{};

pub const GlobalConstants = struct {
    Renderer_ShowLightingSamples: bool = false,
    Renderer_UseSoftware: bool = false,
    Renderer_Camera_UseDebug: bool = false,
    Renderer_Camera_DebugDistance: f32 = 25,
    Renderer_Camera_RoomBased: bool = false,
    GroundChunks_Checkerboards: bool = false,
    GroundChunks_RecomputeOnEXEChange: bool = false,
    Renderer_TestWeirdDrawBufferSize: bool = false,
    GroundChunks_Outlines: bool = false,
    AI_Familiar_FollowsHero: bool = false,
    Particles_Test: bool = false,
    Particles_ShowGrid: bool = false,
    Simulation_UseSpaceOutlines: bool = false,
};
