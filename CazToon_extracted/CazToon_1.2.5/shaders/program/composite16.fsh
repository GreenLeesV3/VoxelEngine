/* RENDERTARGETS: 11,15 */

const bool colortex15Clear = false;

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"

in vec2 texcoord;

uniform sampler2D colortex11;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float sunAngle;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform float biome_swamp;
uniform int biome;
uniform int biome_category;
uniform ivec2 eyeBrightnessSmooth;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;

#ifdef WEATHER_FOG_ENABLED

#include "/include/fog_taa.glsl"
#include "/include/sky_timeline.glsl"

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

float c16EyeSky = float(eyeBrightnessSmooth.y) / 240.0;
vec4 preservedFog15 = texture(colortex15, texcoord);
vec4 current = depthAwareFogResolve(colortex11);
if (c16EyeSky < 0.10 || preservedFog15.a > 1.001) {
gl_FragData[0] = current;
gl_FragData[1] = preservedFog15;
return;
}

vec4 result = FogTemporalAccumulate(current, colortex15, depthtex0, texcoord);
TimeWeights tw = getTimeWeights(sunAngle);
float nightHistoryReduce = clamp(tw.night + tw.blueHour * 0.35, 0.0, 1.0);
float weatherHistoryKeep = mix(1.0, 0.30, nightHistoryReduce);
vec3 currentRgb = max(current.rgb, vec3(0.0));
float currentLuma = dot(currentRgb, vec3(0.299, 0.587, 0.114));
float lpvChroma = length(currentRgb - vec3(currentLuma));
float lpvFogMask = smoothstep(0.04, 0.14, lpvChroma) * smoothstep(0.01, 0.08, current.a);
float finalWeatherHistoryKeep = mix(weatherHistoryKeep, 0.70, lpvFogMask);
result = mix(current, result, finalWeatherHistoryKeep);

float weatherTaaSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
result = mix(result, current, weatherTaaSwamp);
gl_FragData[0] = result;
gl_FragData[1] = result;
}

#else

void main() {
gl_FragData[0] = vec4(0.0);
gl_FragData[1] = vec4(0.0);
}

#endif
