#ifndef SETTINGS_INCLUDED
#define SETTINGS_INCLUDED

// ############################################################################
// ##                                                                        ##
// ##                         CAZFPS SHADER SETTINGS                         ##
// ##                                                                        ##
// ############################################################################

// Dummy constant for settings UI credit label (not used in shaders)
#define SHADER_CREDITS 0 // [0]

// Wetness/dryness transition speed (seconds). Controls how fast the wetness
// uniform ramps when weather changes. Used for smooth cloud rain fade.
const float wetnessHalflife = 3.0;
const float drynessHalflife = 3.0;

// Enable water debug colors for development
//#define WATER_DEBUG_COLORS_ENABLED

#include "/settings/lighting.glsl"
#include "/settings/lpv.glsl"
#include "/settings/post_processing.glsl"
#include "/settings/effects.glsl"
#include "/settings/water_glass_animation.glsl"
#include "/settings/sky.glsl"
#include "/settings/compatibility.glsl"
#include "/settings/diagnostics.glsl"

#endif
