/* RENDERTARGETS: 0,1,3 */

#include "/settings.glsl"
#include "/include/hovering.glsl"

uniform float far;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float sunAngle;
uniform vec3 cameraPosition;
#ifdef LPV_ENABLED
uniform mat4 gbufferModelViewInverse;
#endif
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 dhProjectionInverse;
uniform int isEyeInWater;
uniform float biome_swamp;

#ifdef END_SHADER
#ifdef END_EVENT_ENABLED
#include "/include/end_event.glsl"
#endif
#endif

#include "/include/lighting.glsl"
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
#include "/include/shadow.glsl"

#if defined(CLOUDS_2D_ENABLED) && defined(CLOUD_SHADOWS_ENABLED)
#include "/include/cloud_shadow.glsl"
#endif

in vec4 vColor;
in float viewDistance;
in vec3 normal;
in float NdotL;
in vec3 worldPos;
flat in int materialId;
in float skylight;
in float blockLight;
in vec4 shadowPos;

float interleaved_gradient_noise(vec2 v) {
return fract(52.9829189 * fract(0.06711056 * v.x + 0.00583715 * v.y));
}

#include "/include/noise.glsl"

vec3 getEmissiveLightColor(int matId, vec3 baseColor) {
if (matId == DH_BLOCK_LAVA) return vec3(1.0, 0.4, 0.1);
if (matId == DH_BLOCK_ILLUMINATED) {
float brightness = max(max(baseColor.r, baseColor.g), baseColor.b);
if (brightness > 0.01) {
return normalize(baseColor + 0.1) * 1.2;
}
return vec3(1.0, 0.85, 0.6);
}
float brightness = max(max(baseColor.r, baseColor.g), baseColor.b);
if (brightness > 0.01) {
return normalize(baseColor + 0.1) * 1.2;
}
return vec3(1.0, 0.7, 0.4);
}

float sampleShadow(vec3 shadowCoord, float viewDistance) {
if (shadowCoord.x < -0.01 || shadowCoord.x > 1.01 ||
shadowCoord.y < -0.01 || shadowCoord.y > 1.01 ||
shadowCoord.z < -0.01 || shadowCoord.z > 1.01) {
return 1.0;
}

#if defined(SHARP_SHADOWS) || defined(MAGICAL_TOUCH)
float mapDepth = texture(shadowtex1, shadowCoord.xy).r;
float shadow = step(shadowCoord.z, mapDepth);
float shadowCoverageFade = 1.0 - shadowDistanceFade(shadowCoord, viewDistance);
shadow = mix(1.0, shadow, shadowEdgeFade(shadowCoord) * shadowCoverageFade);
return shadow;
#else
float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
float r = quartic_length(shadowCoord.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;
return getShadowFaded(shadowtex1, shadowCoord, distortFactor, viewDistance, dither);
#endif
}

void main() {
vec4 color = vColor;
vec3 originalColor = vColor.rgb;
#ifdef LPV_ENABLED
lpvSurfaceColor = originalColor;
lpvTexLuma = dot(originalColor, vec3(0.299, 0.587, 0.114));
#endif

float colorBrightness = max(max(originalColor.r, originalColor.g), originalColor.b);

bool isEmissive = (materialId == DH_BLOCK_ILLUMINATED) ||
(materialId == DH_BLOCK_LAVA);
float emissive = isEmissive ? 1.0 : 0.0;

float darknessFactor = 1.0;

float angle = fract(sunAngle);
float isDay = getTimeWeightsSimple(sunAngle).day;
float fade_start = max(far - DH_OVERDRAW_DISTANCE - DH_OVERDRAW_FADE_LENGTH, 0.0);
float fade_end = max(far - DH_OVERDRAW_DISTANCE, 0.0);
float overdrawFade = smoothstep(fade_start, fade_end, viewDistance);

if (overdrawFade > 0.001 && overdrawFade < 0.999) {
ivec2 pixel = ivec2(gl_FragCoord.xy);
float dC = texelFetch(depthtex0, pixel, 0).r;
if (dC < 0.9999) {
float dR = texelFetch(depthtex0, pixel + ivec2(1, 0), 0).r;
float dL = texelFetch(depthtex0, pixel + ivec2(-1, 0), 0).r;
float dU = texelFetch(depthtex0, pixel + ivec2(0, -1), 0).r;
float dD = texelFetch(depthtex0, pixel + ivec2(0, 1), 0).r;

float cov = 0.0;
cov += step(dC, 0.9999);
cov += step(dR, 0.9999);
cov += step(dL, 0.9999);
cov += step(dU, 0.9999);
cov += step(dD, 0.9999);

float maxDiff = max(max(abs(dC - dR), abs(dC - dL)), max(abs(dC - dU), abs(dC - dD)));
bool solidCoverage = (cov >= 4.5) && (maxDiff < 0.0030);

if (solidCoverage) {
vec2 texSize = vec2(textureSize(depthtex0, 0));
vec2 uv = (gl_FragCoord.xy + vec2(0.5)) / texSize;

vec4 mcClip = vec4(uv * 2.0 - 1.0, dC * 2.0 - 1.0, 1.0);
vec4 mcView = gbufferProjectionInverse * mcClip;
float mcDist = -mcView.z / mcView.w;

vec4 dhClip = vec4(uv * 2.0 - 1.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);
vec4 dhView = dhProjectionInverse * dhClip;
float dhDist = -dhView.z / dhView.w;

if (mcDist + 0.10 < dhDist) {
discard;
}
}
}
}

float shadow = 1.0;
float directSunLit = 0.0;
#ifdef SHADOWS_ENABLED
if (isDay > 0.1 && skylight > 0.05 && !isEmissive) {
float lightDot = shadowPos.w;
bool isSunGrazingSurface = lightDot < 0.001;
float shadowCoverage = 1.0 - smoothstep(SHADOW_DISTANCE * 0.8, SHADOW_DISTANCE, viewDistance);

if (isSunGrazingSurface) {
shadow = mix(1.0, 0.6, DH_SHADOW_OPACITY * shadowCoverage);
} else {
shadow = sampleShadow(shadowPos.xyz, viewDistance);
}

directSunLit = shadow;

shadow = mix(1.0, shadow, skylight);
shadow = mix(1.0, shadow, DH_SHADOW_OPACITY);
}
#endif

#if defined(CLOUDS_2D_ENABLED) && defined(CLOUD_SHADOWS_ENABLED)
if (isDay > 0.1 && !isEmissive) {
float cloudShadow = getCloudShadow(worldPos, frameTimeCounter);
shadow *= cloudShadow;
}
#endif

shadow = mix(shadow, 1.0, overdrawFade);

TimeWeightsSimple dhTS = getTimeWeightsSimple(sunAngle);
float sunsetAmount = dhTS.twilight;
float dhSunsetDarken = mix(1.0, 0.82, sunsetAmount);

if (!isEmissive) {
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLightingWithShadow(color.rgb, sunAngle, skylight, blockLight, 0.0, shadow, worldPos.y);
#ifdef HANDHELD_LIGHT_ENABLED
color.rgb += getHandheldLightBoost(worldPos, originalColor, color.rgb);
#endif

color.rgb *= darknessFactor;
color.rgb *= dhSunsetDarken;
}

if (!isEmissive) {
color.rgb *= TERRAIN_BRIGHTNESS * DH_BRIGHTNESS;

if (materialId == DH_BLOCK_GRASS) {
color.rgb *= DH_GRASS_BRIGHTNESS;
} else if (materialId == DH_BLOCK_LEAVES) {
color.rgb *= DH_LEAF_BRIGHTNESS;
}

color.rgb = (color.rgb - 0.5) * DH_CONTRAST + 0.5;
color.rgb = max(color.rgb, vec3(0.0));

float dhLuma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
color.rgb = mix(vec3(dhLuma), color.rgb, DH_SATURATION);

#ifdef END_SHADER
{

#ifdef END_TERRAIN_PATCHES_ENABLED
{
float patchUpFacing = max(normal.y, 0.0);
if (patchUpFacing > 0.3) {
vec2 patchPos = worldPos.xz * END_TERRAIN_PATCH_SCALE;
float pn = 0.0;
float pAmp = 0.6;
for (int octave = 0; octave < 3; octave++) {
vec2 ip = floor(patchPos);
vec2 fp = fract(patchPos);
fp = fp * fp * (3.0 - 2.0 * fp);
float a = fract(sin(dot(ip, vec2(127.1, 311.7))) * 43758.5453);
float b = fract(sin(dot(ip + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
float c = fract(sin(dot(ip + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
float d = fract(sin(dot(ip + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
pn += mix(mix(a, b, fp.x), mix(c, d, fp.x), fp.y) * pAmp;
patchPos *= 2.3;
pAmp *= 0.45;
}
float patchDark = smoothstep(0.25, 0.55, pn);
patchDark = mix(1.0, 1.0 - END_TERRAIN_PATCH_STRENGTH, 1.0 - patchDark);
color.rgb *= mix(1.0, patchDark, patchUpFacing);
}
}
#endif

float dhBaseDarken = 0.55;
float dhTintMult = 0.15;
float dhColorShift = 0.55;

float dhPreserveBlend = 0.0;
vec3 dhPreservedLight = vec3(0.0);

#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
float dhEventDarkness = getEndEventTerrainDarkness(frameTimeCounter);
if (dhEventDarkness > 0.001) {

float bFalloff = getBlocklightFalloff(blockLight, skylight);
vec3 endBlockColor = vec3(END_BLOCKLIGHT_R, END_BLOCKLIGHT_G, END_BLOCKLIGHT_B);
dhPreservedLight = originalColor * endBlockColor * bFalloff * bFalloff * END_BLOCKLIGHT_BRIGHTNESS * TERRAIN_BRIGHTNESS * DH_BRIGHTNESS;

#ifdef HANDHELD_LIGHT_ENABLED
dhPreservedLight += getHandheldLightBoost(worldPos, originalColor, vec3(0.0)) * TERRAIN_BRIGHTNESS * DH_BRIGHTNESS;
#endif

dhPreserveBlend = dhEventDarkness;
}
dhBaseDarken = mix(dhBaseDarken, 0.02, dhEventDarkness);
dhTintMult = mix(dhTintMult, 0.0, dhEventDarkness);
dhColorShift = mix(dhColorShift, 0.0, dhEventDarkness);
#endif

color.rgb *= dhBaseDarken;
vec3 purpleTint = vec3(0.08, 0.06, 0.35);
color.rgb += purpleTint * dhTintMult;
color.rgb = mix(color.rgb, color.rgb * vec3(0.55, 0.58, 1.35), dhColorShift);

color.rgb += dhPreservedLight * dhPreserveBlend;
}
#endif
}

if (isEmissive) {
vec3 whiteGlow = vec3(1.0);
vec3 coloredGlow = originalColor;
vec3 emissiveColor = mix(whiteGlow, coloredGlow, DH_EMISSIVE_COLOR_STRENGTH);
float cappedBrightness = min(EMISSIVE_BRIGHTNESS * DH_BRIGHTNESS, DH_EMISSIVE_BRIGHTNESS_CAP);
#ifdef END_SHADER
cappedBrightness *= END_EMISSIVE_BOOST;
#endif
color.rgb = emissiveColor * cappedBrightness;
}

#ifdef DH_EMISSIVE_DEBUG
if (isEmissive) {
color.rgb = vec3(1.0);
}
#endif

float dither = interleaved_gradient_noise(gl_FragCoord.xy + float(frameCounter));

if (overdrawFade < 0.999) {
float reveal = overdrawFade;
float minY = SEA_LEVEL_OFFSET - 96.0;
float maxY = SEA_LEVEL_OFFSET + 320.0;

float mask = smoothChunkNoise(worldPos.xz * 0.12);
float jitterY = (mask - 0.5) * 10.0;
float revealY = mix(minY, maxY, reveal) + jitterY;
float visible = 1.0 - smoothstep(revealY - 8.0, revealY + 8.0, worldPos.y);
color.rgb *= mix(0.60, 1.0, visible);
if (visible < 0.02 || (dither > overdrawFade && overdrawFade < 0.05)) {
discard;
}
}

#ifndef END_SHADER
#ifndef NETHER_SHADER
if (isEyeInWater == 1) {
if (worldPos.y < float(SEA_LEVEL_OFFSET)) {
float uwDepth = (float(SEA_LEVEL_OFFSET) - worldPos.y) / 24.0;
uwDepth = clamp(uwDepth, 0.0, 1.0);
vec3 uwFogColor = vec3(0.08, 0.22, 0.35);
color.rgb = mix(color.rgb, uwFogColor, uwDepth * 0.85);
}
}
#endif
#endif

gl_FragData[0] = color;
gl_FragData[1] = vec4(1.0, emissive * DH_EMISSIVE_INTENSITY, skylight, 0.0);
vec3 lightColor = vec3(0.0);
if (isEmissive) {
lightColor = getEmissiveLightColor(materialId, vColor.rgb) * DH_EMISSIVE_INTENSITY;
}
gl_FragData[2] = vec4(lightColor, 1.0);
}
