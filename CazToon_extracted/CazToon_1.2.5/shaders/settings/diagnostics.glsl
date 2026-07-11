// ============================================================================
// =====                        DIAGNOSTICS                                =====
// ============================================================================

// Terrain pass profiling mode. Use this with the CazTools GPU delta profiler:
// 0 normal
// 1 terrain without shadow sampling
// 2 terrain without LPV sampling
// 3 terrain without terrain bloom outputs
// 4 terrain without material reflection output
// 5 terrain without PBR texture/decode/apply
// 6 terrain without metalness
// 7 terrain without emissive/held-light masking
// 8 terrain without leaf sheen extras
// 9 terrain without chunk fade
// 10 terrain without water wave terrain work
// 11 terrain without second raw texture fetch
// 12 terrain without foliage blocklight gradient
// 13 terrain without vanilla face shading
// 14 terrain without grass block patch noise
// 15 terrain base texture only (alpha test + core outputs)
// 16 terrain without main lighting apply
// 17 terrain without waving plants/grass
// 18 terrain without waving leaves
// 19 terrain without player plant interaction
// 20 terrain without all foliage waving
// 21 minimal terrain pass (base texture, core outputs, no foliage waving)
#define TERRAIN_PROFILE_MODE 0 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21]

// Fog profiling mode. This compiles fog families in/out so GPU pass deltas
// point at a real fog group instead of just saying "composite".
// 0 normal
// 1 atmospheric fog only
// 2 cave fog only
// 3 underwater fog only
// 4 haze fog only
// 5 weather fog only
// 6 distance fog only (Overworld/Nether/End simple distance fog)
// 7 all fog disabled
#define FOG_PROFILE_MODE 0 // [0 1 2 3 4 5 6 7]

#if FOG_PROFILE_MODE != 0
    #undef ATMO_FOG_ENABLED
    #undef CAVE_FOG_ENABLED
    #undef UNDERWATER_FOG_ENABLED
    #undef HAZE_FOG_ENABLED
    #undef WEATHER_FOG_ENABLED
    #undef OVERWORLD_FOG_ENABLED
    #undef NETHER_FOG_ENABLED
    #undef END_FOG_ENABLED
#endif

#if FOG_PROFILE_MODE == 1
    #define ATMO_FOG_ENABLED
#elif FOG_PROFILE_MODE == 2
    #define CAVE_FOG_ENABLED
#elif FOG_PROFILE_MODE == 3
    #define UNDERWATER_FOG_ENABLED
#elif FOG_PROFILE_MODE == 4
    #define HAZE_FOG_ENABLED
#elif FOG_PROFILE_MODE == 5
    #define WEATHER_FOG_ENABLED
#elif FOG_PROFILE_MODE == 6
    #define OVERWORLD_FOG_ENABLED
    #define NETHER_FOG_ENABLED
    #define END_FOG_ENABLED
#endif
