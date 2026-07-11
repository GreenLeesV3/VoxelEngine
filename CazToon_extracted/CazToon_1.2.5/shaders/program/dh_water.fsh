/* RENDERTARGETS: 7,1,3,4,5 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/hovering.glsl"
#include "/include/water_color.glsl"
#include "/include/ocean_waves.glsl"
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform mat4 gbufferProjectionInverse;
uniform mat4 dhProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform float far;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float sunAngle;
uniform int isEyeInWater;
uniform float biome_swamp;
uniform int biome_category;
uniform vec3 fogColor;
uniform vec3 cameraPosition;

#include "/include/lighting.glsl"

in vec4 vColor;
in float viewDistance;
in vec3 viewPos;
in vec3 worldPos;
in vec3 normal;
in float skylight;
in float blocklight;
in float waveHeight;
in vec3 waveNormal;
flat in int materialId;

vec3 getDhWaterNormalView(vec3 baseNormalView) {
return baseNormalView;
}

vec3 getDhWaterNormalWorld() {
return vec3(0.0, 1.0, 0.0);
}

float interleaved_gradient_noise(vec2 v) {
return fract(52.9829189 * fract(0.06711056 * v.x + 0.00583715 * v.y));
}

#include "/include/noise.glsl"

void main() {
vec4 color = vColor;

bool isWater = (materialId == DH_BLOCK_WATER);

float wSwamp = clamp(biome_swamp, 0.0, 1.0);

if (isWater && isEyeInWater == 1) {
discard;
}
if (isWater) {
color.rgb = waterLitColor(color.rgb, sunAngle, skylight, blocklight);

color.rgb *= WATER_DH_BRIGHTNESS;
float dhWaterLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
color.rgb = mix(vec3(dhWaterLum), color.rgb, WATER_DH_SATURATION);
color.rgb = max(color.rgb, vec3(0.0));
} else {

color.rgb *= DH_BRIGHTNESS;
}

ivec2 pixel = ivec2(gl_FragCoord.xy);
float mcDepth = texelFetch(depthtex0, pixel, 0).r;
float mcOpaqueDepth = texelFetch(depthtex1, pixel, 0).r;
if (isWater) {

if (mcDepth < 1.0) {
discard;
}
} else {

if (mcOpaqueDepth < 1.0) {
vec2 texSize = vec2(textureSize(depthtex1, 0));
vec2 uv = (gl_FragCoord.xy + vec2(0.5)) / texSize;

vec4 mcClip = vec4(uv * 2.0 - 1.0, mcOpaqueDepth * 2.0 - 1.0, 1.0);
vec4 mcView = gbufferProjectionInverse * mcClip;
float mcDist = -mcView.z / mcView.w;

vec4 dhClip = vec4(uv * 2.0 - 1.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);
vec4 dhView = dhProjectionInverse * dhClip;
float dhDist = -dhView.z / dhView.w;

if (mcDist + 1e-4 < dhDist) {
discard;
}
}
}

if (!isWater) {
float fade_start = max(far - DH_OVERDRAW_DISTANCE - DH_OVERDRAW_FADE_LENGTH, 0.0);
float fade_end = max(far - DH_OVERDRAW_DISTANCE, 0.0);
float fade = smoothstep(fade_start, fade_end, viewDistance);
float dither = interleaved_gradient_noise(gl_FragCoord.xy + float(frameCounter));
if (dither > fade) {
discard;
}
}

float emissive = 0.0;
vec3 lightColor = vec3(0.0);

vec3 testColor = vColor.rgb;
float maxC = max(max(testColor.r, testColor.g), testColor.b);
float minC = min(min(testColor.r, testColor.g), testColor.b);
float saturation = (maxC > 0.01) ? (maxC - minC) / maxC : 0.0;
bool isIceLike = (testColor.b > testColor.r * 1.2) && (testColor.b > testColor.g * 1.1) && (maxC > 0.4) && (saturation < 0.45);

bool isSlimeLike = false;
bool isGlass = !isWater && !isIceLike;

if (isIceLike) {
color.rgb = waterLitColor(color.rgb, sunAngle);
}

if (isGlass) {

vec3 glassColor = vColor.rgb;
float brightness = dot(glassColor, vec3(0.299, 0.587, 0.114));
vec3 saturatedColor = mix(vec3(brightness), glassColor, 3.0);
saturatedColor = max(saturatedColor, vec3(0.0));
float maxC2 = max(max(saturatedColor.r, saturatedColor.g), saturatedColor.b);
if (maxC2 > 0.01) {
saturatedColor = saturatedColor / maxC2 * max(brightness * 2.0, 0.4);
} else {
saturatedColor = vec3(0.4, 0.6, 0.8);
}
color.rgb = waterLitColor(saturatedColor, sunAngle);
color.a = max(color.a, 0.5);
}

if (isWater) {

color.a = clamp(WATER_OPACITY * 0.85, 0.0, 1.0);
}

if (isWater && wSwamp > 0.01 && isEyeInWater != 1) {
float st = frameTimeCounter;

float warpA = smoothChunkNoise(worldPos.xz * 0.15 + vec2(st * 0.08, -st * 0.06));
float warpB = smoothChunkNoise(worldPos.xz * 0.15 + vec2(-st * 0.07, st * 0.09) + vec2(13.5, -8.2));
vec2 mudWarp = (vec2(warpA, warpB) - 0.5) * 1.8;
vec2 warpedPos = worldPos.xz + mudWarp;
float mudA = smoothChunkNoise(warpedPos * 0.35 + vec2(st * 0.10, -st * 0.08));
float mudB = smoothChunkNoise(warpedPos * 0.7 + vec2(-st * 0.12, st * 0.11) + vec2(7.3, -4.1));
float mudC = smoothChunkNoise(warpedPos * 1.4 + vec2(st * 0.06, st * 0.14) + vec2(-3.5, 9.2));
float mudField = mudA * 0.5 + mudB * 0.35 + mudC * 0.15;
float mud = smoothstep(0.55, 0.70, mudField);
vec3 mudColor = vec3(0.03, 0.02, 0.01);
color.rgb = mix(color.rgb, mudColor, mud * 0.8 * wSwamp);
color.a = mix(color.a, 1.0, mud * 0.8 * wSwamp);

}

float postMask = isWater ? 0.0 : 1.0;
gl_FragData[0] = color;
gl_FragData[1] = vec4(postMask, emissive, skylight, 0.0);
gl_FragData[2] = vec4(lightColor, 1.0);

if (isWater) {
vec3 biomeRaw = biomeWaterColor(sunAngle, 1.0, wSwamp, 0.0, 0.0, 0.0);
gl_FragData[3] = vec4(biomeRaw, 0.3);
} else if (isGlass) {
float tintStrength = 0.6;
gl_FragData[3] = vec4(vColor.rgb, tintStrength);
} else {
gl_FragData[3] = vec4(0.0);
}

if (isWater) {
gl_FragData[4] = vec4(0.5, 1.0, 0.5, 1.0);
} else {
gl_FragData[4] = vec4(0.0);
}
}
