// LPV (Light Propagation Volumes) — Colored Block Lighting
// Replaces vanilla warm blocklight with per-block colored lighting using
// 3D voxel flood-fill propagation. Requires Iris with CUSTOM_IMAGES (GL 4.3+).

// Master toggle
#define LPV_ENABLED // [ON]

// DEBUG: emit bright color from stained glass voxels to check voxelization.
//#define LPV_DEBUG_GLASS_VOXELS

// Terrain LPV isolation stages for debugging leak sources.
// 0 = terrain LPV off
// 1 = emitter voxels only (no propagated carry)
// 2 = propagated volume with nearest-voxel surface read
// 3 = propagated volume with filtered surface read
// 4 = add sampler-side visible spread shaping
// 5 = full terrain LPV helper logic (current normal terrain path)
#define LPV_ISOLATION_STAGE 5 // [0 1 2 3 4 5]

// Brightness of LPV colored light on surfaces. Does not change radius.
#define LPV_STRENGTH 1.00 // [0.00 0.10 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.50 3.00 4.00 5.00 7.50 10.00]

// Night-time strength multiplier. 1.0 = same as day, lower = dimmer at night.
// Smooth mix from 1.0 at day to this value at midnight.
#define LPV_NIGHT_STRENGTH 0.50 // [0.00 0.10 0.25 0.50 0.70 0.85 1.00 1.25 1.50 2.00 3.00]
// Radius — how far light reaches from each source. Maps to the per-step energy
// conservation in lpv_floodfill.glsl. Higher = longer reach. Clamped to never
// cause runaway amplification even at maximum.
#define LPV_RADIUS 1.00 // [0.10 0.25 0.50 0.75 1.00 1.50 2.00 3.00 5.00 7.50 10.00 15.00 25.00 50.00 100.00]
// Render distance — how far from the player the LPV contribution reaches.
// Also trims the expensive flood-fill compute outside that visible area, so lower
// values are now a real performance lever. 1.00 = full volume (~128 blocks).
#define LPV_RENDER_DISTANCE 1.00 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// Fade-out distance — width (in voxels) of the smooth fade band at the edge of
// render distance. Higher = softer fade, lower = sharper cutoff.
#define LPV_FADE_OUT_DISTANCE 12.0 // [1.0 2.0 4.0 8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0]

// Vibrancy — saturation of LPV colored hues on surfaces. 1.0 = natural,
// higher = more saturated/colorful, lower = closer to white.
#define LPV_VIBRANCY 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00 4.00 5.00]

// Volume size. X/Z stay 256, Y is half-height like Complementary's ACT volume.
// Keep these matched with the image3D dimensions in shaders.properties.
#define LPV_VOLUME_SIZE 256
#define LPV_VOLUME_HEIGHT 128

// Complementary-style LPV optimizations. These keep Caz-Toon's block-aware
// propagation masks, but avoid doing the expensive spread for every voxel every frame.
#define LPV_OPT_HALF_RATE_SPREADING
#define LPV_OPT_BEHIND_PLAYER_CULL

// World coverage scale — 1.0 = 1 voxel per block (stable). Do not change.
#define LPV_WORLD_SCALE 1.0
