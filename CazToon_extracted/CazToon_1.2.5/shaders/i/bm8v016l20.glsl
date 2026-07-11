#include "/settings.glsl"

#ifdef LPV_ENABLED
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(2, 2, 1);
#else
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);
#endif

layout(std430, binding = 0) buffer persistentBuffer {
float storedExposure;
float smoothBeach;
float smoothSwamp;
float smoothJungle;
float smoothSnowy;
float smoothArid;
float storedScreenSkylight;
float smoothOcean;
float smoothNetherFogR;
float smoothNetherFogG;
float smoothNetherFogB;
float smoothCaveFogR;
float smoothCaveFogG;
float smoothCaveFogB;
float storedAtmoSceneFactor;
float storedCaveFogTakeover;
float smoothBiomeFogR;
float smoothBiomeFogG;
float smoothBiomeFogB;
float smoothBiomeSkyR;
float smoothBiomeSkyG;
float smoothBiomeSkyB;
float smoothPaleGarden;
};

uniform float biome_beach;
uniform float biome_swamp;
uniform float biome_jungle;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_ocean;
uniform vec3 fogColor;
uniform vec3 skyColor;

vec3 smoothRuntimeBiomeColor(vec3 previousColor, vec3 targetColor) {
vec3 prev = previousColor;
vec3 target = clamp(targetColor, vec3(0.0), vec3(1.0));
if (any(isnan(prev)) || any(isinf(prev)) || dot(abs(prev), vec3(1.0)) < 0.001) {
return target;
}
float delta = length(prev - target);
float rate = mix(0.025, 0.12, smoothstep(0.15, 0.60, delta));
return mix(prev, target, rate);
}

void updatePersistentBiomeWeights() {
smoothBeach  = biome_beach;
smoothSwamp  = biome_swamp;
smoothJungle = biome_jungle;
smoothSnowy  = biome_snowy;
smoothArid   = biome_arid;
smoothOcean  = biome_ocean;

vec3 smoothedFog = smoothRuntimeBiomeColor(
vec3(smoothBiomeFogR, smoothBiomeFogG, smoothBiomeFogB), fogColor);
vec3 smoothedSky = smoothRuntimeBiomeColor(
vec3(smoothBiomeSkyR, smoothBiomeSkyG, smoothBiomeSkyB), skyColor);

smoothBiomeFogR = smoothedFog.r;
smoothBiomeFogG = smoothedFog.g;
smoothBiomeFogB = smoothedFog.b;
smoothBiomeSkyR = smoothedSky.r;
smoothBiomeSkyG = smoothedSky.g;
smoothBiomeSkyB = smoothedSky.b;
}

#ifdef LPV_ENABLED
#include "/include/lpv/lpv_common.glsl"
#include "/include/lpv/lpv_blocks.glsl"

uint getLpvSetupMask(int blockId) {
if (blockId < 0) return 0u;
if (isLpvOpaqueBlock(blockId)) return 0u;

uint mask = buildLpvMask(1u, 1u, 1u, 1u, 1u, 1u);

if (blockId == 5 || blockId == 82) {
mask = buildLpvMask(1u, 1u, 0u, 0u, 1u, 1u);
}

return mask;
}
#endif

void main() {
if (all(equal(gl_GlobalInvocationID, uvec3(0u)))) {
updatePersistentBiomeWeights();
memoryBarrierBuffer();
}

#ifdef LPV_ENABLED
int blockId = int(gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * 16u);
if (blockId < 256) {
imageStore(lpvBlockMaskImg, blockId, uvec4(getLpvSetupMask(blockId), 0u, 0u, 0u));
}
#endif
}
