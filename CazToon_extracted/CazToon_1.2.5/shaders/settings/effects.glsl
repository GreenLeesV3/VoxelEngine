// ============================================================================
// =====                        EFFECTS                                   =====
// ============================================================================

// ----------------------------------------------------------------------------
//   Overworld Fog
// ----------------------------------------------------------------------------

// Enable atmospheric distance haze in the Overworld
#define OVERWORLD_FOG_ENABLED

// Distance where fog reaches full thickness (blocks)
#define OVERWORLD_FOG_DISTANCE 6144 // [64 96 128 192 256 384 512 768 1024 1536 2048 3072 4096 6144 8192 12288 16384 20480]

// Distance from camera where fog begins (blocks)
#define OVERWORLD_FOG_START 8.0 // [0.0 8.0 16.0 32.0 48.0 64.0 96.0 128.0]

// Fog density/strength. Higher = thicker haze.
#define OVERWORLD_FOG_DENSITY 3.00 // [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50 2.00 3.00]

// Extra fog density during rain (added on top of base density)
#define OVERWORLD_FOG_RAIN_BOOST 0.50 // [0.00 0.10 0.20 0.30 0.40 0.50 0.75 1.00 1.50 2.00]

// ----------------------------------------------------------------------------
//   Chunk Fade Out (distance-based)
// ----------------------------------------------------------------------------

//#define CHUNK_FADE_OUT_ENABLED
// Radius (blocks) around the player where chunk fade begins.
#define CHUNK_FADE_OUT_RADIUS 128.0 // [32.0 48.0 64.0 80.0 96.0 100.0 112.0 128.0 144.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0]
// ----------------------------------------------------------------------------
//   Nether Fog
// ----------------------------------------------------------------------------

// Enable full-volume depth fog in Nether biomes (ignores height limits)
#define NETHER_FOG_ENABLED

// Max fog render distance in the Nether (blocks). Controls where fog becomes fully opaque.
#define NETHER_FOG_DISTANCE 128 // [0 32 48 64 96 128 160 192 256 320 384 512]

// Depth where Nether fog starts (blocks from camera). No fog closer than this.
#define NETHER_DISTANCE_FOG_START 32.0 // [0.0 8.0 16.0 24.0 32.0 48.0 64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0]

// Fog density/strength. Higher = thicker fog.
#define NETHER_DISTANCE_FOG_OPACITY 1.50 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.25 1.50 2.00 3.00 5.00]

// Nether brightness multiplier. Controls how bright/dark the ambient lighting is in the Nether.
#define NETHER_BRIGHTNESS 0.30 // [0.00 0.05 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.25 1.50 2.00 2.50 3.00 4.00 5.00]

// Nether fog color (RGB, 0.0-1.0)
#define NETHER_FOG_R 0.96 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define NETHER_FOG_G 0.28 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define NETHER_FOG_B 0.50 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

// ============================================================================
//   End Dimension
// ============================================================================

// Master toggle for all End-specific visuals
#define END_SKY_ENABLED

// --- End Sky Colors ---
// Horizon color (rich purple-blue void edge)
#define END_SKY_HORIZON_R 0.10 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.25 0.30 0.40 0.50]
#define END_SKY_HORIZON_G 0.06 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.25 0.30 0.40 0.50]
#define END_SKY_HORIZON_B 0.20 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.25 0.30 0.40 0.50]

// Mid color (deep purple/indigo zone)
#define END_SKY_MID_R 0.12 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.15 0.20 0.25 0.30 0.40 0.50]
#define END_SKY_MID_G 0.06 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.15 0.20 0.25 0.30 0.40 0.50]
#define END_SKY_MID_B 0.25 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.15 0.20 0.25 0.30 0.40 0.50]

// Zenith color (overhead deep indigo)
#define END_SKY_ZENITH_R 0.08 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.25 0.30 0.40]
#define END_SKY_ZENITH_G 0.04 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.25 0.30 0.40]
#define END_SKY_ZENITH_B 0.18 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.25 0.30 0.40]

// Sky brightness
#define END_SKY_BRIGHTNESS 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00 4.00]

// --- End Stars ---
#define END_STARS_ENABLED
#define END_STAR_DENSITY 0.40 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80]
#define END_STAR_BRIGHTNESS 1.50 // [0.50 0.75 1.00 1.50 2.00 2.50 3.00 4.00 5.00]
#define END_STAR_COLOR_SHIFT 0.70 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// --- End Nebula ---
#define END_NEBULA_ENABLED
#define END_NEBULA_INTENSITY 0.60 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50 2.00]
#define END_NEBULA_SCALE 1.5 // [0.5 1.0 1.5 2.0 3.0 4.0 5.0 8.0]
#define END_NEBULA_SPEED 0.03 // [0.00 0.005 0.01 0.02 0.03 0.05 0.06 0.08 0.10 0.15 0.20]
// Nebula primary color (deep indigo-purple)
#define END_NEBULA_R1 0.35 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_NEBULA_G1 0.10 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_NEBULA_B1 0.60 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
// Nebula secondary color (dark teal-blue)
#define END_NEBULA_R2 0.15 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_NEBULA_G2 0.20 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_NEBULA_B2 0.50 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// --- End Aurora / Void Shimmer ---
#define END_AURORA_ENABLED
#define END_AURORA_INTENSITY 1.25 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50]
#define END_AURORA_SPEED 0.25 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.70]
#define END_AURORA_HEIGHT 0.60 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80]
// Aurora primary color (deep purple)
#define END_AURORA_R1 0.40 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_AURORA_G1 0.10 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_AURORA_B1 0.80 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
// Aurora secondary color (cool blue)
#define END_AURORA_R2 0.20 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_AURORA_G2 0.40 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_AURORA_B2 0.75 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// --- End Void Particles ---
#define END_VOID_PARTICLES_ENABLED
#define END_VOID_PARTICLE_DENSITY 0.40 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_VOID_PARTICLE_BRIGHTNESS 2.0 // [0.50 0.75 1.00 1.50 2.00 3.00 4.00]

// --- End Warp Streaks (fast-flying debris flashing across the sky) ---
#define END_ASTEROIDS_ENABLED
#define END_ASTEROID_DENSITY 0.15 // [0.05 0.08 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80]
#define END_ASTEROID_SPEED 0.50 // [0.10 0.20 0.30 0.40 0.50 0.70 1.00 1.50 2.00]
#define END_ASTEROID_BRIGHTNESS 1.20 // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 1.00 1.20 1.50 2.00]
#define END_ASTEROID_LENGTH 0.08 // [0.03 0.05 0.08 0.10 0.12 0.15 0.20 0.25 0.30]
#define END_ASTEROID_THICKNESS 0.004 // [0.002 0.003 0.004 0.005 0.007 0.010 0.012 0.015]

// --- End Vortex (swirling void below the island) ---
#define END_VORTEX_ENABLED
#define END_VORTEX_INTENSITY 1.50 // [0.20 0.40 0.60 0.80 1.00 1.25 1.50 2.00 3.00]
#define END_VORTEX_SPEED 0.12 // [0.00 0.05 0.08 0.10 0.12 0.15 0.20 0.30 0.40 0.50]
#define END_VORTEX_ARMS 5.0 // [2.0 3.0 4.0 5.0 6.0 8.0 10.0]
#define END_VORTEX_TIGHTNESS 3.0 // [0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0 7.0]
#define END_VORTEX_CORE_SIZE 0.12 // [0.05 0.08 0.10 0.12 0.15 0.20 0.25 0.30]
// Vortex color (light streaks and core glow)
#define END_VORTEX_R2 0.45 // [0.00 0.10 0.20 0.30 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_VORTEX_G2 0.35 // [0.00 0.10 0.20 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_VORTEX_B2 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// --- End Rings (planetary rings around the center island) ---
#define END_RINGS_ENABLED
#define END_RINGS_COUNT 1 // [1 2 3 4 5]
#define END_RINGS_BRIGHTNESS 1.50 // [0.20 0.40 0.60 0.80 1.00 1.25 1.50 2.00 3.00]
#define END_RINGS_SPEED 0.10 // [0.00 0.01 0.02 0.03 0.05 0.08 0.10 0.15 0.20 0.30 0.50]
#define END_RINGS_INNER 150.0 // [40.0 60.0 80.0 100.0 120.0 150.0 200.0 250.0 300.0]
#define END_RINGS_WIDTH 15.0 // [5.0 10.0 15.0 20.0 30.0 40.0 50.0 60.0 80.0]
#define END_RINGS_DEPTH 6.0 // [2.0 4.0 6.0 8.0 10.0 15.0 20.0 30.0]
// Ring color (purple-blue glow)
#define END_RINGS_R 0.45 // [0.00 0.10 0.20 0.30 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_RINGS_G 0.25 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_RINGS_B 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// --- End Void Clouds (volumetric cloud shell wrapping around the island) ---
#define END_VOID_CLOUDS_ENABLED
#define END_VOID_CLOUD_INTENSITY 0.80 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.25 1.50]
#define END_VOID_CLOUD_STEPS 16 // [8 12 16 24 32]
#define END_VOID_CLOUD_COVERAGE 0.40 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.70 0.80]
#define END_VOID_CLOUD_DENSITY 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
#define END_VOID_CLOUD_SCALE 1.0 // [0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0]
#define END_VOID_CLOUD_SPEED 0.02 // [0.00 0.005 0.01 0.02 0.03 0.05 0.08 0.10]
#define END_VOID_CLOUD_SWIRL 3.0 // [0.0 0.5 1.0 1.5 2.0 3.0 4.0 5.0 7.0 10.0]
#define END_VOID_CLOUD_SWIRL_SPEED 0.05 // [0.00 0.01 0.02 0.03 0.05 0.08 0.10 0.15]
#define END_VOID_CLOUD_CLEARING 0.40 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80]
#define END_VOID_CLOUD_EDGE_GLOW 0.30 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.80 1.00]
// Void cloud primary color (#9269FF)
#define END_VOID_CLOUD_R1 0.57 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.57 0.60 0.70 0.80 0.90 1.00]
#define END_VOID_CLOUD_G1 0.41 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.41 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_VOID_CLOUD_B1 1.00 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
// Void cloud secondary color (darker #9269FF)
#define END_VOID_CLOUD_R2 0.30 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_VOID_CLOUD_G2 0.20 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_VOID_CLOUD_B2 0.60 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// --- End Lighting (separate lightmap and bloom for End dimension) ---
// Blocklight in the End ? the primary way lit areas stand out from dark terrain
#define END_BLOCKLIGHT_BRIGHTNESS 1.50 // [0.50 0.75 1.00 1.20 1.50 1.75 2.00 2.50 3.00 4.00 5.00]
// Blocklight tint color in the End (purple-magenta tint to match End atmosphere)
#define END_BLOCKLIGHT_R 0.85 // [0.50 0.60 0.70 0.80 0.85 0.90 1.00]
#define END_BLOCKLIGHT_G 0.65 // [0.40 0.50 0.60 0.65 0.70 0.80 0.90 1.00]
#define END_BLOCKLIGHT_B 1.00 // [0.50 0.60 0.70 0.80 0.90 1.00]
// Emissive brightness boost for End (makes glowing blocks pop against dark terrain)
#define END_EMISSIVE_BOOST 1.00 // [1.00 1.25 1.50 1.75 2.00 2.50 3.00 4.00]
// End bloom intensity multiplier (stacks with base BLOOM_INTENSITY)
#define END_BLOOM_BOOST 1.50 // [1.00 1.50 2.00 2.50 3.00 4.00 5.00 6.00]

// --- Lava Crust (animated dark noise on lava top face) ---
#define LAVA_CRUST_ENABLED
#define LAVA_NOISE_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define LAVA_NOISE_AMOUNT 0.0    // [-0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5]
#define LAVA_TEMPERATURE 0.0     // [-1.0 -0.8 -0.6 -0.4 -0.2 0.0 0.2 0.4 0.6 0.8 1.0]

// --- Lava Fog (dense fog when camera is submerged in lava) ---
#define LAVA_FOG_ENABLED
// Fog color — deep orange-red molten glow
#define LAVA_FOG_R 0.90 // [0.50 0.60 0.70 0.80 0.90 1.00]
#define LAVA_FOG_G 0.25 // [0.05 0.10 0.15 0.20 0.25 0.30 0.40]
#define LAVA_FOG_B 0.02 // [0.00 0.01 0.02 0.04 0.06 0.08 0.10]
// View distance — how far you can see (blocks) before full fog
#define LAVA_FOG_DISTANCE 2.0 // [1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0]

// --- End Ender Particles (floating motes in world space around the player) ---
#define END_ENDER_PARTICLES_ENABLED
#define END_ENDER_PARTICLE_DENSITY 0.40 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80]
#define END_ENDER_PARTICLE_BRIGHTNESS 1.25 // [0.10 0.20 0.30 0.40 0.50 0.60 0.80 1.00 1.25 1.50 2.00]
#define END_ENDER_PARTICLE_SIZE 0.02 // [0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.10 0.15 0.20]
#define END_ENDER_PARTICLE_SPACING 4.0 // [2.0 3.0 4.0 5.0 6.0 8.0 10.0]
#define END_ENDER_PARTICLE_RANGE 48.0 // [16.0 24.0 32.0 48.0 64.0 96.0 128.0]

// --- End Void Event (cinematic sky collapse & cosmic eye cycle) ---
#define END_EVENT_ENABLED
#define END_EVENT_CYCLE 300.0 // [60.0 120.0 180.0 240.0 300.0 420.0 600.0 900.0 1200.0]
#define END_EVENT_BLACKOUT 60.0 // [3.0 5.0 7.0 10.0 15.0 20.0 30.0 45.0 60.0 90.0 120.0 180.0 300.0 600.0]
#define END_EVENT_EYE_ENABLED
// Eye iris color (purple glow)
#define END_EVENT_EYE_IRIS_R 0.40 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_EVENT_EYE_IRIS_G 0.10 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define END_EVENT_EYE_IRIS_B 0.80 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
// Eye spotlight ? theatre-style light cone on the player when the eye is open
#define END_EVENT_SPOTLIGHT_ENABLED
#ifdef END_EVENT_SPOTLIGHT_ENABLED
#endif
#define END_EVENT_SPOTLIGHT_RADIUS 3.5 // [1.0 1.5 2.0 2.5 3.0 3.5 4.0 5.0 7.0 10.0]
#define END_EVENT_SPOTLIGHT_INTENSITY 3.00 // [0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]

// --- End Terrain Patches (darkness variation on ground surfaces) ---
#define END_TERRAIN_PATCHES_ENABLED
#ifdef END_TERRAIN_PATCHES_ENABLED
#endif
#define END_TERRAIN_PATCH_STRENGTH 0.25 // [0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50]
#define END_TERRAIN_PATCH_SCALE 0.15 // [0.05 0.08 0.10 0.12 0.15 0.20 0.25 0.30]

// --- End Fog (atmospheric purple mist) ---
#define END_FOG_ENABLED
#define END_FOG_DISTANCE 256 // [0 32 48 64 96 128 160 192 256 320 384 512]
#define END_FOG_START 8.0 // [0.0 4.0 8.0 16.0 24.0 32.0 48.0 64.0]
#define END_FOG_DENSITY 0.30 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50 2.00]
// End fog color (purple atmospheric mist)
#define END_FOG_R 0.12 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.15 0.20 0.25 0.30]
#define END_FOG_G 0.06 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.25 0.30]
#define END_FOG_B 0.22 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.22 0.25 0.30 0.35 0.40 0.45 0.50]
// --- God Rays ---

// God ray sharpness (enhances contrast at shadow edges)

// God ray smoothing (lower = sharper but more noise)

// God ray shadow tint strength (0 = neutral gray shadows, 1 = full colored tint)

// ============================================================================
//   Y-Fade (Global vertical color tint)
// ============================================================================

// Enable/disable the Y-Fade effect
//#define Y_FADE_ENABLED

// World Y level where the tint is at full strength (everything below is fully tinted)
#define YFADE_BOTTOM_Y 0.0// [0.0 10.0 20.0 30.0 40.0 50.0 60.0 70.0 80.0 90.0 100.0]

// World Y level where the tint fades to zero (everything above has no tint)
#define YFADE_TOP_Y 200.0// [40.0 50.0 60.0 70.0 80.0 90.0 100.0 110.0 120.0 128.0 150.0 180.0 200.0 256.0 320.0]

// Fade tint color (RGB)
#define YFADE_COLOR_R 0.60// [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define YFADE_COLOR_G 0.80// [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define YFADE_COLOR_B 0.30 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

// How strong the color tint is (0 = no effect, 1 = full color replacement)
#define YFADE_OPACITY 0.50 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
// ============================================================================
//   Atmospheric Fog (3D Particulate Haze)
// ============================================================================

// Enable 3D atmospheric fog -- patchy dust/mist clouds lit by sunlight through shadow map
#define ATMO_FOG_ENABLED
#define FOG_RENDER_SCALE 0.50 // [0.50 0.75 1.00]

// Ray march quality (more steps = smoother but slower)
#define ATMO_FOG_STEPS 12 // [4 6 8 10 12 16 20 24 32 64 128]
// Maximum ray march distance in blocks
#define ATMO_FOG_DISTANCE 128 // [32 48 64 96 128 192 256 384 512]

// Fog density multiplier
#define ATMO_FOG_DENSITY 1.00 // [0.05 0.10 0.20 0.30 0.40 0.50 0.75 1.00 1.50 2.00 3.00 5.00]

// Fog brightness multiplier
#define ATMO_FOG_BRIGHTNESS 1.00 // [0.05 0.10 0.15 0.20 0.25 0.35 0.50 0.70 0.75 1.00 1.50 2.00]
// Height slab below camera (blocks)
#define ATMO_FOG_BELOW 10 // [10 15 20 30 50 75 100 128 192 256]
// Height slab above camera (blocks)
#define ATMO_FOG_ABOVE 20 // [10 15 20 30 40 50 75 100]
// Noise scale -- larger values = bigger fog patches
#define ATMO_FOG_SCALE 0.04 // [0.01 0.02 0.03 0.04 0.06 0.08 0.10 0.15 0.20]

// Wind speed multiplier (0 = static fog)
#define ATMO_FOG_WIND_SPEED 1.00 // [0.00 0.25 0.50 0.75 1.00 1.50 2.00 3.00]

// Shadow influence -- how much shadows remove fog (1 = fully shadow-aware)
#define ATMO_FOG_SHADOW_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 0.80 0.90 1.00]

// Complementary-style scene-aware adaptation:
// boosts shafts in dark/enclosed scenes while restraining the general fog body.
#define ATMO_SCENE_AWARE_SHAFTS_ENABLED

// Overall strength of the scene-aware shaft adaptation.
#define ATMO_SCENE_AWARE_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]

// Enable stained-glass colored atmospheric shafts. Disabled for performance testing.
#define ATMO_COLORED_SHAFTS_ENABLED

// Dust (indoor sun shafts) brightness range
#define ATMO_DUST_MIN_BRIGHTNESS 0.002 // [0.000 0.001 0.002 0.005 0.010 0.020 0.030 0.050]
#define ATMO_DUST_MAX_BRIGHTNESS 0.500 // [0.010 0.020 0.030 0.040 0.050 0.075 0.100 0.150 0.200 0.300 0.500 0.750 1.000]

// TAA smoothing half-life in seconds (higher = smoother, more ghosting)
#define ATMO_FOG_TAA_BLEND 0.60 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.80 1.00]

// ============================================================================
//   Cave Fog (Underground Volumetric)
// ============================================================================



// ============================================================================
//   Haze Fog (Uniform Height-Slab Blanket)
// ============================================================================
// A uniform blanket of fog at a fixed height range. Uses sky horizon color.
// Accumulates in the distance when inside; looks like a flat layer from above.

#define HAZE_FOG_ENABLED

// Ray march quality
#define HAZE_FOG_STEPS 8 // [4 6 8 10 12 16 20 24 32]

// Density multiplier
#define HAZE_FOG_DENSITY 0.50 // [0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.75 1.00 1.25 1.50 2.00 3.00]

// Brightness multiplier
#define HAZE_FOG_BRIGHTNESS 1.25 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]

// Height range relative to SEA_LEVEL_OFFSET.
// 0 = sea level, 15 = 15 blocks above sea level, -10 = 10 blocks below.
#define HAZE_FOG_MIN_Y 0 // [-64 -48 -32 -24 -16 -12 -8 -4 0 2 4 6 8 10 12 15 20 24 32 48 64]
#define HAZE_FOG_MAX_Y 15 // [0 4 8 10 12 15 20 24 32 48 64 80 96 128 160 192 256]

// Distance range: fog starts fading in at START and reaches full density at END
#define HAZE_FOG_DIST_START 0 // [0 8 16 32 48 64 96 128 192 256 384 512]
#define HAZE_FOG_DIST_END 4096 // [64 96 128 192 256 384 512 768 1024 1536 2048 4096]
// Inside attenuation: how visible is haze when player is inside the slab
// 0.0 = invisible inside, 1.0 = full strength inside
#define HAZE_FOG_INSIDE_OPACITY 0.50 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.75 1.00]

// TAA smoothing half-life in seconds
#define HAZE_FOG_TAA_BLEND 0.60 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.80 1.00]


// ============================================================================
//   Cave Fog (Underground Volumetric Distance Fog)
// ============================================================================
// Ray-marched exponential fog in empty cave air. Only renders when camera
// skylight is 0. Biome-colored above y=0 (dripstone = pale blue, lush =
// olive, deep dark = black), near-black below y=0 regardless of biome.

#define CAVE_FOG_ENABLED

// Ray-march step count. Higher = smoother banding but slightly more cost.
#define CAVE_FOG_STEPS 12 // [8 12 16 20 24 32]
// Fog density per block. Higher = thicker fog, reaches opacity faster.
#define CAVE_FOG_DENSITY 0.040 // [0.002 0.004 0.006 0.008 0.010 0.015 0.020 0.025 0.030 0.040 0.050 0.080 0.120 0.200]
// Maximum ray march distance (blocks). Beyond this the fog is assumed fully
// opaque so we stop marching to save cost.
#define CAVE_FOG_MAX_DIST 64.0 // [16.0 24.0 32.0 48.0 64.0 96.0 128.0]

// How strongly LPV colored light scatters into the fog near light sources.
// 0 = fog ignores light sources entirely, 1 = strong colored glow near torches.
#define CAVE_FOG_LPV_STRENGTH 0.30 // [0.0 0.02 0.05 0.08 0.10 0.12 0.15 0.20 0.25 0.30 0.40 0.50 0.75 1.00 1.50 2.00 3.00 5.00]
// Optional biome-sky cave fog mode. When enabled, cave fog ignores the
// hard-coded cave palette and uses the biome sky color instead.
//#define CAVE_FOG_USE_BIOME_SKY_COLOR
// Render ambient shader-drawn flying leaves around the player.
// #define TORNADO_LEAVES_ENABLED
// Overall flying-leaf spawn density. Higher = more active leaf cells and streams.
#define FLYING_LEAF_DENSITY 1.00 // [0.25 0.35 0.50 0.65 0.80 1.00 1.25 1.50 1.75 2.00 2.50 3.00]

// Maximum number of leaves in each grouped trail.
#define FLYING_LEAF_TRAIL_MAX 5 // [1 2 3 4 5 6 7 8]

// Radius in blocks around the player where flying leaves can render.
#define FLYING_LEAF_RENDER_RADIUS 50.0 // [16.0 24.0 32.0 40.0 48.0 50.0 64.0 80.0 96.0 128.0]


// ============================================================================
//   Weather Fog (Rain/Thunder Volumetric)
// ============================================================================
// Volumetric fog that fades in during rain and gets denser during thunder.
// Uses sky zenith color, height-limited above sea level, with animated ceiling.

#define WEATHER_FOG_ENABLED

// Ray march quality (more steps = smoother, higher cost)
#define WEATHER_FOG_STEPS 8 // [4 6 8 10 12 16 20 24 32]
// Overall fog density
#define WEATHER_FOG_DENSITY 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]

// Fog brightness multiplier
#define WEATHER_FOG_BRIGHTNESS 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00]

// Distance where fog starts (blocks from camera)
#define WEATHER_FOG_NEAR_DIST 3.0 // [1.0 2.0 3.0 4.0 5.0 8.0 12.0 16.0]

// Distance where fog reaches max density (blocks from camera)
#define WEATHER_FOG_FAR_DIST 30.0 // [15.0 20.0 25.0 30.0 40.0 50.0 64.0 96.0 128.0]

// Height of fog slab above sea level (blocks)
#define WEATHER_FOG_HEIGHT 50.0 // [20.0 30.0 40.0 50.0 60.0 75.0 100.0 150.0 200.0 237.0 300.0 400.0]
// Animated ceiling layer density (0 = no ceiling)
#define WEATHER_FOG_CEILING_DENSITY 2.00 // [0.00 0.50 1.00 1.50 2.00 3.00 4.00 5.00]

// Ceiling layer thickness (blocks from top of fog slab)
#define WEATHER_FOG_CEILING_THICKNESS 10.0 // [5.0 8.0 10.0 15.0 20.0 25.0]

// Fog opacity when player is inside the slab
#define WEATHER_FOG_INSIDE_OPACITY 1.00 // [0.25 0.50 0.75 1.00]

// Fog opacity when player is above the slab
#define WEATHER_FOG_ABOVE_OPACITY 0.50 // [0.00 0.10 0.25 0.50 0.75 1.00]

// Extra density boost during thunderstorms (multiplier on top of rain)
#define WEATHER_FOG_THUNDER_BOOST 0.50 // [0.00 0.25 0.50 0.75 1.00 1.50 2.00]

// Noise scale for ceiling animation
#define WEATHER_FOG_NOISE_SCALE 0.04 // [0.01 0.02 0.03 0.04 0.06 0.08 0.10]

// TAA smoothing half-life in seconds
#define WEATHER_FOG_TAA_BLEND 0.50 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.80 1.00]

// LPV lighting contribution inside weather fog (lets colored light show in rainy air)
#define WEATHER_FOG_LPV_STRENGTH 0.084 // [0.00 0.02 0.05 0.08 0.10 0.12 0.15 0.20 0.25 0.30 0.40 0.50 0.75 1.00]


// ============================================================================
//   Lightning (Localized Fog Glow)
// ============================================================================
// Brief bright glow patches inside weather fog during thunderstorms.
// Multiple "bolt cells" flash independently at random positions in the fog volume.

#define LIGHTNING_ENABLED

// Glow brightness multiplier
#define LIGHTNING_BRIGHTNESS 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]

// Average seconds between lightning strikes per cell
#define LIGHTNING_INTERVAL 5.0 // [2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0]

// Glow tint color (cool white-blue like real lightning)
#define LIGHTNING_R 0.80 // [0.50 0.60 0.70 0.80 0.90 1.00]
#define LIGHTNING_G 0.85 // [0.50 0.60 0.70 0.80 0.85 0.90 1.00]
#define LIGHTNING_B 1.00 // [0.50 0.60 0.70 0.80 0.90 1.00]


// ============================================================================
//   Underwater Fog (Volumetric)
// ============================================================================
// Dark blue volumetric fog visible only when camera is submerged.

#define UNDERWATER_FOG_ENABLED

// Ray march quality (more steps = smoother shafts, higher cost)
#define UNDERWATER_FOG_STEPS 12 // [8 12 16 20 24 32 48 64]

// Max ray march distance in blocks
#define UNDERWATER_FOG_DISTANCE 512 // [16 24 32 48 64 96 128 192 256 384 512 768 1024 1152]

// Clear radius around player (blocks) — no fog inside this distance
#define UNDERWATER_FOG_START 0.0 // [0.0 2.0 4.0 6.0 8.0 10.0 12.0 16.0 20.0 24.0]

// Fog density (higher = thicker, shorter visibility)
#define UNDERWATER_FOG_DENSITY 0.50 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00 5.00]

// Fog color — how bright/saturated the distant fog looks
#define UNDERWATER_FOG_R 0.12 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.15 0.20 0.30 0.40]
#define UNDERWATER_FOG_G 0.45 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.45 0.50 0.60]
#define UNDERWATER_FOG_B 0.90 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// TAA smoothing half-life in seconds
#define UNDERWATER_FOG_TAA_BLEND 0.40 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.80]

// View distance fog — caps how far you can see underwater
#define UNDERWATER_VIEW_FOG_START 40 // [10 15 20 25 30 40 50 60 70 80 100 128 160 200 256]
#define UNDERWATER_VIEW_FOG_END   80 // [20 25 30 40 50 60 70 80 90 100 128 160 200 256 320 384 512]

// ─── Underwater Light Shafts ───────────────────────────────────────────────
#define UNDERWATER_SHAFTS_ENABLED // [ON] Light shafts (god rays) visible when submerged
#define UNDERWATER_SHAFTS_INTENSITY 2.0  // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0 2.5 3.0] Shaft brightness
#define UNDERWATER_SHAFTS_DENSITY  0.3   // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] Coverage (higher = more shafts)
#define UNDERWATER_SHAFTS_SCALE    0.15  // [0.02 0.03 0.04 0.05 0.06 0.08 0.10 0.12 0.15] Shaft width (lower = thinner)
#define UNDERWATER_SHAFTS_LENGTH   8.0   // [2.0 4.0 6.0 8.0 10.0 14.0 18.0 24.0] Stretch along sun direction
#define UNDERWATER_SHAFTS_SPEED    0.3   // [0.0 0.1 0.2 0.3 0.4 0.5 0.7 1.0] Animation speed


// ============================================================================
//   Auto-Exposure (Eye Adaptation)
// ============================================================================
// Global scene brightness adaptation based on skylight exposure.
// Brightens dark areas (caves, night) so fog shafts and details are visible.
// Dims bright areas (daylight) to prevent sky and fog from washing out.

#define AUTO_EXPOSURE_ENABLED

// How strong the effect is (0 = off, 1 = full adaptation)
#define AUTO_EXPOSURE_STRENGTH 0.50 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// Brightness boost in dark areas (caves, night)
#define AUTO_EXPOSURE_DARK_BOOST 1.50 // [1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]

// Brightness reduction in bright areas (daylight)
#define AUTO_EXPOSURE_BRIGHT_DIM 0.80 // [0.50 0.60 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
