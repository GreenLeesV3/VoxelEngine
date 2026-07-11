#ifndef SKY_FALLBACK_GLSL
#define SKY_FALLBACK_GLSL

#include "/include/sky_timeline.glsl"

vec3 getSkyFallback(vec3 reflectDir, float sunAngle) {
TimeWeightsSimple ts = getTimeWeightsSimple(sunAngle);

vec3 worldReflect = normalize(mat3(gbufferModelViewInverse) * reflectDir);

float height = clamp(worldReflect.y * 0.5 + 0.5, 0.0, 1.0);

vec3 sky = getTimelineHorizonColor(sunAngle, height);

if (worldReflect.y < 0.0) {
sky *= 0.5 + 0.5 * (1.0 + worldReflect.y);
}

vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
float sunDot = dot(worldReflect, worldSunDir);

float sunGlow = pow(max(sunDot, 0.0), 32.0);
vec3 sunColor = mix(vec3(1.0, 0.95, 0.8), vec3(1.0, 0.6, 0.3), ts.twilight);
sky += sunColor * sunGlow * (ts.day + ts.twilight * 0.5) * 0.6;

float moonGlow = pow(max(-sunDot, 0.0), 16.0);
sky += vec3(0.4, 0.5, 0.7) * moonGlow * ts.night * 0.3;

return sky;
}

#endif
