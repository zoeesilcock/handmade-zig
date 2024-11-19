const math = @import("math.zig");

const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Vector4 = math.Vector4;

// Debugging
    // Ground chunks
        pub const DEBUGUI_GROUND_CHUNK_OUTLINES: bool = false;
        pub const DEBUGUI_GROUND_CHUNK_CHECKERBOARDS: bool = false;
        pub const DEBUGUI_RECOMPUTE_GROUND_CUNKS_ON_EXE_CHANGE: bool = false;
    // Particles
        pub const DEBUGUI_PARTICLE_TEST: bool = false;
        pub const DEBUGUI_PARTICLE_GRID: bool = false;
    // Renderer
        pub const DEBUGUI_TEST_WEIRD_DRAW_BUFFER_SIZE: bool = false;
        pub const DEBUGUI_SHOW_LIGHTING_SAMPLES: bool = false;
        // Camera
            pub const DEBUGUI_USE_DEBUG_CAMERA: bool = false;
            pub const DEBUGUI_DEBUG_CAMERA_DISTANCE: f32 = 50;
            pub const DEBUGUI_USE_ROOM_BASED_CAMERA: bool = false;
    pub const DEBUGUI_FAMILIAR_FOLLOWS_HERO: bool = false;
    pub const DEBUGUI_USE_SPACE_OUTLINES: bool = true;
    pub const DEBUGUI_FAUX_V4: Vector4 = Vector4.new(1, 2, 3, 4);
    // Profile
        // By Thread
        // By Function
