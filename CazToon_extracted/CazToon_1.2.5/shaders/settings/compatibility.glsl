// ============================================================================
// =====                    COMPATIBILITY                                 =====
// ============================================================================

#include "/settings/dh.glsl"
#include "/settings/voxy.glsl"

// ============================================================================
// FAKE HORIZON WATER (fills beyond DH LODs with ocean)
// ============================================================================

// Enable fake water plane where DH LODs don't exist
//#define FAKE_TERRAIN_ENABLED

// Y level of the water plane (world coordinates)
#define FAKE_TERRAIN_Y 63 // [-64 0 15 32 48 63 64 80 96 100 128]

// Distance where fake water starts fading in (blocks from camera)
// Lower values fill gaps closer to the player (set near your DH render distance)
#define FAKE_TERRAIN_START 0.0// [0.0 50.0 100.0 200.0 300.0 500.0 750.0 1000.0 1500.0 2000.0]

// Maximum render distance for fake water
#define FAKE_TERRAIN_DISTANCE 10000.0// [5000.0 10000.0 15000.0 20000.0 30000.0 50000.0]
