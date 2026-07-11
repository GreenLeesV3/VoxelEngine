#ifndef INCLUDE_BIOME_COLOR_SMOOTHING_GLSL
#define INCLUDE_BIOME_COLOR_SMOOTHING_GLSL

vec3 safeRuntimeBiomeColor(vec3 colorValue, vec3 fallback) {
if (any(isnan(colorValue)) || any(isinf(colorValue))) return fallback;
if (dot(abs(colorValue), vec3(1.0)) < 0.001) return fallback;
return clamp(colorValue, vec3(0.0), vec3(1.0));
}

vec3 getSmoothedBiomeFogColorRaw(vec3 fallbackFog) {
#ifndef BIOME_COLOR_SMOOTHING_HAS_SSBO
return fallbackFog;
#else
return safeRuntimeBiomeColor(vec3(smoothBiomeFogR, smoothBiomeFogG, smoothBiomeFogB), fallbackFog);
#endif
}

vec3 getSmoothedBiomeSkyColorRaw(vec3 fallbackSky) {
#ifndef BIOME_COLOR_SMOOTHING_HAS_SSBO
return fallbackSky;
#else
return safeRuntimeBiomeColor(vec3(smoothBiomeSkyR, smoothBiomeSkyG, smoothBiomeSkyB), fallbackSky);
#endif
}

float getRuntimeBiomeColorWeight(vec3 horizonColor, vec3 zenithColor, vec3 baseHorizon, vec3 baseZenith) {
float horizonDelta = length(horizonColor - baseHorizon);
float zenithDelta = length(zenithColor - baseZenith);
return smoothstep(0.03, 0.18, max(horizonDelta, zenithDelta));
}

#endif
