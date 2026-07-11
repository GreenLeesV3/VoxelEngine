/* RENDERTARGETS: 9,13 */

const bool colortex13Clear = false;

#extension GL_ARB_shader_storage_buffer_object : require

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"

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

in vec2 texcoord;

uniform sampler2D colortex1;
uniform sampler2D colortex9;
uniform sampler2D colortex13;
uniform sampler2D depthtex0;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform int isEyeInWater;
uniform float biome_swamp;
uniform int biome;
uniform int biome_category;
uniform float sunAngle;
uniform ivec2 eyeBrightnessSmooth;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;

#if defined(ATMO_FOG_ENABLED) || defined(UNDERWATER_FOG_ENABLED) || defined(CAVE_FOG_ENABLED)

#include "/include/fog_taa.glsl"

float fogResolveLinearDepth(float depth) {
return (near * far) / (depth * (near - far) + far);
}

vec4 depthAwareFogResolve(sampler2D fogTex) {
vec2 viewSize = vec2(viewWidth, viewHeight);
ivec2 lowSize = ivec2(max(viewSize * FOG_RENDER_SCALE, vec2(1.0)));
ivec2 lowBase = ivec2(floor(gl_FragCoord.xy * FOG_RENDER_SCALE));
float referenceDepth = fogResolveLinearDepth(texture(depthtex0, texcoord).r);

const ivec2 OFFSETS[5] = ivec2[](
ivec2(0, 0),
ivec2(1, 0),
ivec2(-1, 0),
ivec2(0, 1),
ivec2(0, -1)
);

vec4 sum = vec4(0.0);
float weightSum = 0.0;
float threshold = max(referenceDepth * 0.05, 0.25);

for (int i = 0; i < 5; i++) {
ivec2 lowCoord = clamp(lowBase + OFFSETS[i], ivec2(0), lowSize - ivec2(1));
vec2 fogUv = (vec2(lowCoord) + 0.5) / viewSize;
vec2 sourceUv = (vec2(lowCoord) / FOG_RENDER_SCALE + 0.5) / viewSize;
float sampleDepth = fogResolveLinearDepth(texture(depthtex0, clamp(sourceUv, vec2(0.0), vec2(1.0))).r);
float weight = abs(sampleDepth - referenceDepth) < threshold ? 1.0 : 0.0001;
sum += texture(fogTex, fogUv) * weight;
weightSum += weight;
}

return sum / max(weightSum, 0.0001);
}

void main() {
ivec2 texelcoord = ivec2(gl_FragCoord.xy);
vec4 current = depthAwareFogResolve(colortex9);
if (isEyeInWater == 1) {

gl_FragData[0] = current;
gl_FragData[1] = current;
} else {
vec4 result = FogTemporalAccumulate(current, colortex13, depthtex0, texcoord);

float pxSkylight = texture(colortex1, texcoord).b;
float atmoZeroSkylightGate = smoothstep(0.5 / 15.0, 1.0 / 15.0, pxSkylight);
float atmoNightFactor = smoothstep(0.55, 0.60, fract(sunAngle)) * (1.0 - smoothstep(0.94, 0.98, fract(sunAngle)));
float atmoSkylightGate = mix(1.0, atmoZeroSkylightGate, atmoNightFactor);
float caveHistoryMask = 1.0 - smoothstep(1.0 / 15.0, 3.0 / 15.0, pxSkylight);
float caveHistoryKeep = mix(1.0, 0.0, caveHistoryMask);
float currentFogLum = dot(current.rgb, vec3(0.299, 0.587, 0.114));
float currentShaftHistory = smoothstep(ATMO_DUST_MIN_BRIGHTNESS, ATMO_DUST_MAX_BRIGHTNESS * 0.20, currentFogLum);
caveHistoryKeep = mix(max(caveHistoryKeep, currentShaftHistory), 0.0, caveHistoryMask);
float atmoTaaSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
result = mix(result, current, atmoTaaSwamp);
float nightAngle = fract(sunAngle);
float nightSkip = smoothstep(0.55, 0.6, nightAngle) * smoothstep(0.95, 0.9, nightAngle);
result = mix(result, current, nightSkip);
result = mix(current, result, caveHistoryKeep);
if (atmoSkylightGate <= 0.001 && current.a <= 0.001) result = current;

gl_FragData[0] = result;
gl_FragData[1] = result;
}
}

#else

void main() {
gl_FragData[0] = vec4(0.0);
gl_FragData[1] = vec4(0.0);
}

#endif
