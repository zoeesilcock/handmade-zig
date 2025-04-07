pub var global_config = Config{};

pub const Config = struct {
    Renderer_Camera_UseDebug: bool = false,
    Renderer_Camera_DebugDistance: f32 = 25,
    Renderer_Camera_RoomBased: bool = true,
    Renderer_TestWeirdDrawBufferSize: bool = false,
    AI_Familiar_FollowsHero: bool = false,
    Particles_Test: bool = false,
    Particles_ShowGrid: bool = false,
    Game_SkipIntro: bool = true,
    Simulation_TimestepPercentage: f32 = 100,
};
