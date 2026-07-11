/* RENDERTARGETS: 0,14 */

const bool colortex14Clear = false;
const bool DEBUG_CAVE_FOG_ALPHA_VIEW = false;
const bool DEBUG_CAVE_FOG_DISTANCE_VIEW = false;

#include "/settings.glsl"
#ifdef PBR_ENABLED
#include "/include/pbr.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;
uniform sampler2D dhDepthTex;
uniform sampler2D dhDepthTex1;
uniform sampler2D vxDepthTexTrans;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform mat4 dhProjection;
uniform mat4 dhProjectionInverse;
uniform mat4 vxProjInv;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex0;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float near;
uniform float sunAngle;
uniform float dhFarPlane;
uniform float dhNearPlane;
uniform float darknessFactor;
uniform float darknessLightFactor;
uniform float blindness;
uniform float nightVision;

uniform int isEyeInWater;
uniform int biome;
uniform int biome_category;
uniform int worldDay;
uniform int worldTime;
uniform int frameCounter;
uniform int renderVanillaClouds;

#define FRAME_TIME_COUNTER_DECLARED
uniform float frameTimeCounter;
#define RAIN_STRENGTH_DECLARED
uniform float rainStrength;
uniform float thunderStrength;

uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_savanna;
uniform float biome_beach;
uniform float biome_ocean;
uniform vec3 fogColor;
uniform vec3 skyColor;

uniform ivec2 eyeBrightnessSmooth;

#ifdef HANDHELD_LIGHT_ENABLED
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform int heldItemId;
uniform int heldItemId2;
uniform vec3 eyePosition;
#endif

in vec2 texcoord;

#include "/include/biome_overrides.glsl"

#include "/include/depth_utils.glsl"
#include "/include/water_color.glsl"
#include "/include/ocean_waves.glsl"
#include "/include/color_utils.glsl"
#include "/include/sky_timeline.glsl"
#include "/include/voxy_compat.glsl"
#include "/include/noise.glsl"
#include "/include/shadow.glsl"
#include "/include/tornado_particles.glsl"
#ifdef HANDHELD_LIGHT_ENABLED
#include "/include/held_light_post.glsl"
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

#define SEA_LEVEL_OFFSET_DEFAULT 63
#ifndef SEA_LEVEL_OFFSET
#define SEA_LEVEL_OFFSET SEA_LEVEL_OFFSET_DEFAULT
#endif

#ifdef CLOUDS_3D_ENABLED
#include "/include/volumetric_clouds.glsl"
#endif
#ifdef CLOUDS_VANILLA_ENABLED
#include "/include/vanilla_clouds.glsl"
#endif
#include "/include/ilv_reflections.glsl"

#ifdef END_SHADER
#if defined(END_EVENT_ENABLED)
#include "/include/end_event.glsl"
#endif
#ifdef END_SKY_ENABLED
#include "/include/end_sky.glsl"
#endif
#endif

vec3 getHorizonColor();
vec3 getSkyCastHorizonColor();

bool isEndDimension() {
#ifdef END_SHADER
return true;
#else
#ifdef CAT_THE_END
return biome_category == CAT_THE_END;
#else
return isForcedEndBiome(biome);
#endif
#endif
}

bool isSkylessWorldHeuristic() {
float sunLen = length(sunPosition);
float shadowLen = length(shadowLightPosition);
vec3 skyMax = max(skyColor, vec3(0.0));
vec3 fogMax = max(fogColor, vec3(0.0));
float skyPeak = max(max(skyMax.r, skyMax.g), skyMax.b);
float fogPeak = max(max(fogMax.r, fogMax.g), fogMax.b);
bool noDirectionalLight = (sunLen < 0.001 && shadowLen < 0.001);
bool darkFlatAtmosphere = (skyPeak < 0.06 && fogPeak < 0.08);
return darkFlatAtmosphere && noDirectionalLight;
}

vec2 getSunScreenUV() {
vec3 sunDirView = normalize(shadowLightPosition);
vec3 sunPosView = sunDirView * 1000.0;
vec4 clip = gbufferProjection * vec4(sunPosView, 1.0);
if (clip.w <= 0.00001) return vec2(-1.0);
vec2 ndc = clip.xy / clip.w;
return ndc * 0.5 + 0.5;
}

vec4 sampleFogSmooth(sampler2D tex, vec2 uv) {
vec4 fog = max(texture(tex, uv), vec4(0.0));
fog.rgb = fog.rgb * fog.rgb;
fog.rgb = fog.rgb * fog.rgb;
fog.rgb *= 32.0;
return fog;
}

vec3 getWorldPos(vec2 uv, float depth) {
vec4 clipPos = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
vec4 viewPos = gbufferProjectionInverse * clipPos;
viewPos /= viewPos.w;
vec4 worldPos = gbufferModelViewInverse * viewPos;
return worldPos.xyz + cameraPosition;
}

vec3 getWorldPosDH(vec2 uv, float depth) {
float linearDepth = linearizeDepthDH(depth);
vec4 clipPos = vec4(uv * 2.0 - 1.0, -1.0, 1.0);
vec4 viewPosNear = gbufferProjectionInverse * clipPos;
viewPosNear /= viewPosNear.w;
vec3 viewDir = normalize(viewPosNear.xyz);
vec3 viewPos = viewDir * (linearDepth / max(abs(viewDir.z), 0.001));
vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
return worldPos.xyz + cameraPosition;
}

vec3 reconstructViewPos(mat4 projInv, vec2 uv, float depth) {
vec4 clipPos = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
vec4 viewPos = projInv * clipPos;
float safeW = (abs(viewPos.w) < 1e-6) ? (viewPos.w < 0.0 ? -1e-6 : 1e-6) : viewPos.w;
return viewPos.xyz / safeW;
}

vec3 getVoxyWaterViewPos(vec2 uv, float fallbackDepth) {
float vxDepth = texture(vxDepthTexTrans, uv).r;
float waterDepth = (vxDepth > 0.00001 && vxDepth < 0.9999) ? vxDepth : fallbackDepth;
return reconstructViewPos(vxProjInv, uv, waterDepth);
}

vec3 projectViewToScreen(mat4 proj, vec3 viewPos) {
vec4 clip = proj * vec4(viewPos, 1.0);
float safeW = (abs(clip.w) < 1e-6) ? (clip.w < 0.0 ? -1e-6 : 1e-6) : clip.w;
vec3 ndc = clip.xyz / safeW;
return ndc * 0.5 + 0.5;
}

float getVoxyScreenSpaceShadow(vec3 positionView, float depthLod, float skylight) {
if (depthLod <= 0.00001 || depthLod >= 0.99999) return 1.0;
if (skylight <= 0.05) return 1.0;

vec3 viewLightDir = normalize(shadowLightPosition);
if (length(viewLightDir) < 0.001) return 1.0;

float viewDistance = length(positionView);
vec3 scenePos = (gbufferModelViewInverse * vec4(positionView, 1.0)).xyz;
vec4 shadowClip = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shadowNdc = distortShadowClipPos(shadowClip.xyz);
vec3 shadowScreenPos = shadowNdc * 0.5 + 0.5;
float chunkShadowCoverage = 0.0;
if (shadowScreenPos.x > 0.0 && shadowScreenPos.x < 1.0 &&
shadowScreenPos.y > 0.0 && shadowScreenPos.y < 1.0 &&
shadowScreenPos.z > 0.0 && shadowScreenPos.z < 1.0) {
chunkShadowCoverage =
shadowEdgeFade(shadowScreenPos) *
(1.0 - shadowDistanceFade(shadowScreenPos, viewDistance));
}
float handoffSignal = 1.0 - clamp(chunkShadowCoverage, 0.0, 1.0);
float handoffFade = smoothstep(0.0, 0.85, min(1.0, handoffSignal * 1.35));
if (handoffFade <= 0.0001) return 1.0;

bool useCombinedDepth = dot(positionView, positionView) < (far + 64.0) * (far + 64.0);
mat4 lodProj = inverse(vxProjInv);

float marchT = 1.5;
float stepLen = 2.0;
const int VXY_SSRT_STEPS = 10;

for (int i = 0; i < VXY_SSRT_STEPS; i++) {
vec3 sampleView = positionView + viewLightDir * marchT;
vec3 sampleScreen = useCombinedDepth
? projectViewToScreen(gbufferProjection, sampleView)
: projectViewToScreen(lodProj, sampleView);

if (sampleScreen.x <= 0.0 || sampleScreen.x >= 1.0 ||
sampleScreen.y <= 0.0 || sampleScreen.y >= 1.0 ||
sampleScreen.z <= 0.0 || sampleScreen.z >= 1.0) {
break;
}

float sampleDepth = useCombinedDepth
? texture(depthtex2, sampleScreen.xy).r
: texture(vxDepthTexTrans, sampleScreen.xy).r;

if (sampleDepth > 0.00001 && sampleDepth < 0.99999) {
if (useCombinedDepth) {
float sampleMarker = texture(colortex1, sampleScreen.xy).a;
if (sampleMarker > 0.01 && sampleMarker < 0.99) {
marchT += stepLen;
stepLen *= 1.18;
continue;
}
}

vec3 occluderView = useCombinedDepth
? reconstructViewPos(gbufferProjectionInverse, sampleScreen.xy, sampleDepth)
: reconstructViewPos(vxProjInv, sampleScreen.xy, sampleDepth);

if (occluderView.z > sampleView.z + 0.35) {
return mix(1.0, 0.0, handoffFade);
}
}

marchT += stepLen;
stepLen *= 1.18;
}

return 1.0;
}

vec3 getVoxyShadowTintMultiplier(float shadowVal, float skylight) {
vec4 tod = voxy_time_of_day_lighting(sunAngle);
float todBrightness = tod.x;
float dayAmount = tod.z;
float voxyAngle = fract(sunAngle);

float sunsetTintBoost = smoothstep(0.38, 0.45, voxyAngle) * (1.0 - smoothstep(0.48, 0.55, voxyAngle))
+ smoothstep(0.95, 1.0, voxyAngle) + (1.0 - smoothstep(0.0, 0.05, voxyAngle));
float dayTintReduce = smoothstep(0.07, 0.15, voxyAngle) * (1.0 - smoothstep(0.40, 0.46, voxyAngle));
float baseTint = SKYLIGHT_COLOR_TINT * (1.0 - dayTintReduce * 0.6);
float tintStrength = clamp(baseTint + sunsetTintBoost * SUNSET_TERRAIN_TINT, 0.0, 1.0);
vec3 todTint = voxy_tod_skylight_tint(sunAngle);
vec3 biomeTint = voxy_normalize_light_color(skyColor);
float biomeWeight = smoothstep(0.5, 0.9, dayAmount);
vec3 tintBase = voxy_normalize_light_color(todTint * mix(vec3(1.0), biomeTint, biomeWeight));

float sunsetSatBoost = 1.0 + sunsetTintBoost * (SUNSET_TERRAIN_TINT * 1.09);
vec3 tintShadow = voxy_normalize_light_color(voxy_applySaturation(tintBase, SKYLIGHT_TINT_SATURATION * sunsetSatBoost));

float skyTintGate = smoothstep(1.0 / 15.0, 2.0 / 15.0, skylight);
vec3 skyTintShadow = mix(vec3(1.0), tintShadow, tintStrength * skylight * skyTintGate);

vec3 rawShadowHue = voxy_hueToRGB(SHADOW_HUE > 0.0 ? 180.0 + SHADOW_HUE : 360.0 + SHADOW_HUE);
float hueLuminance = voxy_luma(rawShadowHue);
vec3 normalizedHue = min(rawShadowHue / max(hueLuminance, 0.3), vec3(2.0));
float nightSatReduce = smoothstep(0.0, 0.20, todBrightness);
float caveSatReduce = smoothstep(0.10, 0.55, skylight);
float effectiveLmSat = mix(LIGHTMAP_SATURATION * 0.10, LIGHTMAP_SATURATION, nightSatReduce * caveSatReduce);
vec3 shadowTintColor = mix(vec3(1.0), normalizedHue, effectiveLmSat);

float isNightTime = 1.0 - smoothstep(0.0, 0.25, todBrightness);
float shadowDark = 0.15 * skylight * (1.0 - isNightTime * 0.75);
vec3 darkShadowColor = shadowTintColor * shadowDark;
darkShadowColor *= skyTintShadow;
vec3 litColor = mix(vec3(1.0), tintShadow, tintStrength * skyTintGate);

float litAmountBase = clamp(skylight * todBrightness, 0.0, 1.0);
float litAmountShadow = clamp(skylight * todBrightness * shadowVal, 0.0, 1.0);
litAmountBase = clamp(litAmountBase + skylight * isNightTime * 0.30, 0.0, 1.0);
litAmountShadow = clamp(litAmountShadow + skylight * shadowVal * isNightTime * 0.30, 0.0, 1.0);

vec3 baseLitMultiplier = mix(darkShadowColor, litColor, litAmountBase);
vec3 shadowedMultiplier = mix(darkShadowColor, litColor, litAmountShadow);
return shadowedMultiplier / max(baseLitMultiplier, vec3(0.001));
}

#define BIOME_COLOR_SMOOTHING_HAS_SSBO
#include "/include/distance_fog.glsl"

#if (defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)) && defined(WALL_RUNOFF_ENABLED)
float runoffHash(vec2 p) {
return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float runoffNoise(vec2 p) {
vec2 i = floor(p);
vec2 f = fract(p);
f = f * f * (3.0 - 2.0 * f);
float a = runoffHash(i);
float b = runoffHash(i + vec2(1.0, 0.0));
float c = runoffHash(i + vec2(0.0, 1.0));
float d = runoffHash(i + vec2(1.0, 1.0));
return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
#endif

void main() {
ivec2 texelcoord = ivec2(gl_FragCoord.xy);

vec4 opaqueData = texelFetch(colortex0, texelcoord, 0);
vec3 opaqueColor = opaqueData.rgb;
float cloudAlpha = opaqueData.a;
float cloudMask = cloudAlpha;

vec4 translucentData = texelFetch(colortex7, texelcoord, 0);
vec4 maskData = texelFetch(colortex1, texelcoord, 0);
vec4 glassTint = texelFetch(colortex4, texelcoord, 0);
vec4 reflData = texelFetch(colortex5, texelcoord, 0);
float waterSurfaceSkylight = clamp(maskData.b, 0.0, 1.0);

float depth0 = texelFetch(depthtex0, texelcoord, 0).r;
float depth1 = texelFetch(depthtex1, texelcoord, 0).r;
float depth2 = texelFetch(depthtex2, texelcoord, 0).r;
float dhDepth = texelFetch(dhDepthTex, texelcoord, 0).r;

float depthOpaque = depth1;
float depthNoHand = depth2;
float depthAll = depth0;
bool isSky = (depthOpaque >= 0.9999);
bool isHandPixel = (depthAll < depthNoHand - 0.000001) && (abs(depthAll - depthOpaque) < 0.000001);
bool isHandEarly = (depth0 < depth2 - 0.000001) && (abs(depth0 - depth1) < 0.000001);

vec3 color = opaqueColor;

if (isHandPixel) {

float transAlpha = translucentData.a;
if (transAlpha > 0.001 && !isHandEarly) {
color = color * (1.0 - transAlpha) + translucentData.rgb;
}
gl_FragData[0] = vec4(color, cloudAlpha);
gl_FragData[1] = vec4(0.0);
return;
}

float transAlpha = translucentData.a;
bool entityInFront = !isHandPixel && (maskData.a > 0.01 && maskData.a < 0.99);
bool blockEntityPixel =
!entityInFront &&
!isHandEarly &&
(maskData.a <= 0.01) &&
(maskData.r > 0.90 && maskData.r < 0.99);

bool opaqueBlockEntityInFront =
(blockEntityPixel ||
(!entityInFront &&
!isHandEarly &&
(transAlpha <= 0.001) &&
(depth0 < depth1 - 0.00001) &&
(glassTint.a <= 0.01)));
vec4 waterData = reflData;
bool isGlassC17 = (glassTint.a > 0.45);
bool translucentOverSky = isSky && (transAlpha > 0.001);
bool particleOverSky = isSky && (depthAll < 0.9999) && (waterData.y < 0.5) && !isGlassC17;

bool isEntityOrHand = isHandEarly;
bool isWaterTagged = false;
bool isWater = false;
bool isVoxyLod = (maskData.a > 0.999);
bool isVoxyWater = false;
bool isDhWater = false;
bool isMaterialRefl = false;
bool isIceBlock = false;
bool isWaterOnly = false;
vec3 decodedWorldNormal = vec3(0.0, 1.0, 0.0);
vec3 preSpecularColor = color;
vec4 ssrTaaOutput = vec4(0.0);

#if defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)

bool hasReflection = (reflData.z > 0.001 || reflData.w > 0.001) && !isHandEarly;

float nx = reflData.z * 2.0 - 1.0;
float ny = reflData.w * 2.0 - 1.0;
float nz = sqrt(max(1.0 - nx * nx - ny * ny, 0.0));
decodedWorldNormal = vec3(nx, ny, nz);
bool isHorizontalSurface = (decodedWorldNormal.y > 0.5);

isWaterTagged = (reflData.y > 0.9);

float voxyMarker = maskData.a;
isEntityOrHand = (voxyMarker > 0.01 && voxyMarker < 0.99) || isHandEarly;

bool hasTranslucent = (depth0 < depth1 - 0.00001) || (transAlpha > 0.001);

isWater = hasReflection && isWaterTagged && !isEntityOrHand && hasTranslucent && !isGlassC17 && (depth0 < 0.9999);
isVoxyLod = (voxyMarker > 0.999);
isVoxyWater = hasReflection && isWaterTagged && isVoxyLod && !isWater;
if (isVoxyWater) isWater = true;
isDhWater = hasReflection && isWaterTagged && !isWater && (depth0 >= 0.9999) && (dhDepth < 0.9999);
isMaterialRefl = hasReflection && !isWater && !isDhWater;

isIceBlock = (glassTint.a > 0.75 && glassTint.a < 0.85);

if (isIceBlock) {
isWater = false;
isDhWater = false;
isMaterialRefl = false;
}
bool isGlassOverWater = (isWater || isDhWater) && isGlassC17;
isWaterOnly = (isWater || isDhWater) && !isGlassOverWater;

preSpecularColor = color;

#ifdef VOXY_SSS_ENABLED
#ifdef SHADOWS_ENABLED
if (isVoxyLod && !isVoxyWater && !isWater && !isGlassC17 && !entityInFront) {
float voxyDepthShadow = texture(vxDepthTexTrans, texcoord).r;
if (voxyDepthShadow > 0.00001 && voxyDepthShadow < 0.99999) {
vec4 voxyClipShadow = vxProjInv * vec4(texcoord * 2.0 - 1.0, voxyDepthShadow * 2.0 - 1.0, 1.0);
vec3 voxyViewShadow = voxyClipShadow.xyz / voxyClipShadow.w;
float voxySsrtShadow = getVoxyScreenSpaceShadow(voxyViewShadow, voxyDepthShadow, maskData.b);
voxySsrtShadow = mix(1.0, voxySsrtShadow, SHADOW_OPACITY);
float shadowTransitionDip = voxy_shadow_transition_dip(sunAngle);
voxySsrtShadow = mix(voxySsrtShadow, 1.0, shadowTransitionDip);
color *= getVoxyShadowTintMultiplier(voxySsrtShadow, maskData.b);
color *= voxy_shadow_transition_darken(shadowTransitionDip, voxy_time_of_day_lighting(sunAngle).x, maskData.b);
}
}
#endif
#endif

float beachWaveHeight = reflData.x;
float beachWaveHeightSm = beachWaveHeight;
if (isWater || isDhWater) {
float whL1 = texelFetch(colortex5, texelcoord + ivec2(-1, 0), 0).x;
float whR1 = texelFetch(colortex5, texelcoord + ivec2( 1, 0), 0).x;
float whU1 = texelFetch(colortex5, texelcoord + ivec2(0, -1), 0).x;
float whD1 = texelFetch(colortex5, texelcoord + ivec2(0,  1), 0).x;
beachWaveHeightSm = (beachWaveHeight + whL1 + whR1 + whU1 + whD1) * 0.2;
}

float waveBiome = max(biome_beach, biome_ocean);

#ifdef WATER_REFLECTION_DEBUG
if (isWater) color = vec3(1.0, 0.0, 1.0);
if (isDhWater) color = vec3(1.0, 1.0, 0.0);
if (isMaterialRefl) color = vec3(0.0, 1.0, 1.0);
#else

#if 0

#ifdef WATER_REFLECTIONS_ENABLED
if (isWater && isEyeInWater != 1) {
if (depth0 < 1.0) {
vec3 viewPos;
if (isVoxyWater) {
vec4 vClip = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
viewPos = vClip.xyz / vClip.w;
} else {
vec3 screenPos = vec3(texcoord, depth0);
viewPos = ilv_screenToView(screenPos);
}
vec3 waterWorldN = decodedWorldNormal;
bool isSideWater = (waterWorldN.y < 0.5);
if (isSideWater) waterWorldN = vec3(0.0, 1.0, 0.0);
waterWorldN = normalize(mix(vec3(0.0, 1.0, 0.0), waterWorldN, 0.05));
vec3 normal = normalize(mat3(gbufferModelView) * waterWorldN);

vec2 waveOffset = vec2(0.0);
#ifdef WATER_WAVES_ENABLED
{
ivec2 tcMax = ivec2(viewWidth - 1.0, viewHeight - 1.0);
ivec2 tcL = clamp(texelcoord + ivec2(-1, 0), ivec2(0), tcMax);
ivec2 tcR = clamp(texelcoord + ivec2( 1, 0), ivec2(0), tcMax);
ivec2 tcU = clamp(texelcoord + ivec2(0, -1), ivec2(0), tcMax);
ivec2 tcD = clamp(texelcoord + ivec2(0,  1), ivec2(0), tcMax);
float whL = texelFetch(colortex5, tcL, 0).x;
float whR = texelFetch(colortex5, tcR, 0).x;
float whU = texelFetch(colortex5, tcU, 0).x;
float whD = texelFetch(colortex5, tcD, 0).x;
vec2 hGrad = vec2(whR - whL, whD - whU);
float waveDist = max(length(viewPos), 1.0);
float distScale = 1.0 / waveDist;
waveOffset = vec2(0.0);
}
#endif

TimeWeightsSimple reflTS = getTimeWeightsSimple(sunAngle);
float reflDay = reflTS.day + reflTS.twilight;
float reflNight = reflTS.night + reflTS.blueHour;
float reflTOD = mix(0.15, 1.0, reflDay) + reflNight * 0.85;
float reflectionStrength = mix(WATER_REFLECTION_AMOUNT, max(WATER_REFLECTION_AMOUNT, 0.85), reflNight) * reflTOD * WATER_OPACITY;
float crestReflectCut = 1.0;
reflectionStrength *= crestReflectCut;
reflectionStrength *= waterEffectScale;
float waterSkylight = texelFetch(colortex1, texelcoord, 0).b;

vec2 lmcoord = vec2(0.0, waterSkylight);

vec3 reflDirView = reflect(normalize(viewPos), normal);
vec3 reflDirWorld = mat3(gbufferModelViewInverse) * reflDirView;

float ssrDist = length(viewPos);
float ssrFade = 1.0 - smoothstep(float(SSR_RENDER_DISTANCE) * 0.8, float(SSR_RENDER_DISTANCE), ssrDist);

if (isSideWater) {

vec3 sideNormalWorld = decodedWorldNormal;
sideNormalWorld.y = 0.0;
float sideNLen = length(sideNormalWorld);
if (sideNLen < 0.001) sideNormalWorld = vec3(0.0, 0.0, 1.0);
else sideNormalWorld /= sideNLen;

vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec3 viewDirWorld = normalize(worldPos);
vec3 sideReflWorld = reflect(viewDirWorld, sideNormalWorld);
sideReflWorld.y += 0.15;

float sideNoise = reflData.x;
sideReflWorld.x += (sideNoise - 0.5) * 0.12;
sideReflWorld.y += (sideNoise - 0.5) * 0.08;
sideReflWorld = normalize(sideReflWorld);

vec3 sideSkyCol;
if (sideReflWorld.y > 0.0) {
vec3 sideReflView = normalize(mat3(gbufferModelView) * sideReflWorld);
sideSkyCol = ilv_getSkyColor(sideReflView, worldPos + cameraPosition, false) * 0.8;
} else {
vec3 horizDir = normalize(vec3(sideReflWorld.x, 0.001, sideReflWorld.z));
vec3 horizView = normalize(mat3(gbufferModelView) * horizDir);
sideSkyCol = ilv_getSkyColor(horizView, worldPos + cameraPosition, false) * 0.8;
}

float sideSkyGate = smoothstep(13.0 / 15.0, 14.0 / 15.0, waterSkylight);

vec3 sideNormalPerturbed = sideNormalWorld;
sideNormalPerturbed.y += (sideNoise - 0.5) * 0.1;
sideNormalPerturbed.x += (sideNoise - 0.5) * 0.05;
sideNormalPerturbed = normalize(sideNormalPerturbed);
vec3 sideNormalView = normalize(mat3(gbufferModelView) * sideNormalPerturbed);
vec2 sideWaveOffset = vec2((sideNoise - 0.5) * 0.008, (sideNoise - 0.5) * 0.015);
vec3 preRefl = color;
ilv_addReflection(color, viewPos, sideNormalView, lmcoord, reflectionStrength * max(ssrFade, 0.001), sideWaveOffset, waterTintCol, waterTintStr);
vec3 ssrDeltaLocal = color - preRefl;
color = preRefl;
color += ssrDeltaLocal * WATER_BRIGHTNESS;
float ssrHit = clamp(length(ssrDeltaLocal) * 5.0, 0.0, 1.0);
vec3 sideSkyFallback = mix(color, sideSkyCol, reflectionStrength * sideSkyGate);
color = mix(sideSkyFallback, color, ssrHit);

{
vec3 sideN = normalize(mat3(gbufferModelView) * sideNormalWorld);
sideN = normalize(sideN + vec3((sideNoise - 0.5) * 0.5, (sideNoise - 0.5) * 0.5, 0.0));
vec3 sideL = normalize(shadowLightPosition);
vec3 sideV = normalize(-viewPos);
vec3 sideH = normalize(sideV + sideL);
float sideNdotH = max(dot(sideN, sideH), 0.0);
float sideSpec = smoothstep(0.95, 0.99, sideNdotH);
TimeWeightsSimple sideSpecTS = getTimeWeightsSimple(sunAngle);
float sideDayFactor = sideSpecTS.day + sideSpecTS.twilight * 0.7;
float sideSunsetBoost = 1.0 + sideSpecTS.twilight * 2.0;
float sideGlow = sideSpec * sideDayFactor * waterSkylight * sideSunsetBoost;
vec3 sideGlowCol = mix(vec3(1.0, 0.95, 0.85),
vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), sideSpecTS.twilight);
vec3 sideShadowScenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec4 sideShadowClip = shadowProjection * shadowModelView * vec4(sideShadowScenePos, 1.0);
vec3 sideShadowDistorted = distortShadowClipPos(sideShadowClip.xyz / sideShadowClip.w);
vec3 sideShadowScreen = sideShadowDistorted * 0.5 + 0.5;
float sideShadow = 0.0;
if (sideShadowScreen.x > 0.0 && sideShadowScreen.x < 1.0 && sideShadowScreen.y > 0.0 && sideShadowScreen.y < 1.0) {
float sideShadowDepth = texture(shadowtex0, sideShadowScreen.xy).r;
sideShadow = step(sideShadowScreen.z - 0.001, sideShadowDepth);
}
preSpecularColor = color;
color += sideGlowCol * sideGlow * WATER_SPECULAR_INTENSITY * sideShadow * waterEffectScale * mix(1.0, 0.1, smoothSwamp);
}
} else {

vec3 preRefl = color;
ilv_addReflection(color, viewPos, normal, lmcoord, reflectionStrength * max(ssrFade, 0.001), waveOffset, waterTintCol, waterTintStr);
vec3 reflDelta = color - preRefl;
float wb = WATER_BRIGHTNESS;
color = preRefl + reflDelta * wb;

vec3 topL = normalize(shadowLightPosition);
vec3 topV = normalize(-viewPos);
vec3 topWorldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
float topWt = frameTimeCounter * WATER_WAVE_SPEED * 0.5;

#define SPEC_HASH(p) fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453)
vec3 sp1 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 0.4, topWt * 0.25);
vec3 si1 = floor(sp1); vec3 sf1 = fract(sp1);
sf1 = sf1 * sf1 * (3.0 - 2.0 * sf1);
float sn1 = mix(mix(mix(SPEC_HASH(si1), SPEC_HASH(si1+vec3(1,0,0)), sf1.x),
mix(SPEC_HASH(si1+vec3(0,1,0)), SPEC_HASH(si1+vec3(1,1,0)), sf1.x), sf1.y),
mix(mix(SPEC_HASH(si1+vec3(0,0,1)), SPEC_HASH(si1+vec3(1,0,1)), sf1.x),
mix(SPEC_HASH(si1+vec3(0,1,1)), SPEC_HASH(si1+vec3(1,1,1)), sf1.x), sf1.y), sf1.z);
vec3 sp2 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 0.9, topWt * 0.6) + vec3(17.0);
vec3 si2 = floor(sp2); vec3 sf2 = fract(sp2);
sf2 = sf2 * sf2 * (3.0 - 2.0 * sf2);
float sn2 = mix(mix(mix(SPEC_HASH(si2), SPEC_HASH(si2+vec3(1,0,0)), sf2.x),
mix(SPEC_HASH(si2+vec3(0,1,0)), SPEC_HASH(si2+vec3(1,1,0)), sf2.x), sf2.y),
mix(mix(SPEC_HASH(si2+vec3(0,0,1)), SPEC_HASH(si2+vec3(1,0,1)), sf2.x),
mix(SPEC_HASH(si2+vec3(0,1,1)), SPEC_HASH(si2+vec3(1,1,1)), sf2.x), sf2.y), sf2.z);
vec3 sp3 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 1.8, topWt * 1.0) + vec3(31.0);
vec3 si3 = floor(sp3); vec3 sf3 = fract(sp3);
sf3 = sf3 * sf3 * (3.0 - 2.0 * sf3);
float sn3 = mix(mix(mix(SPEC_HASH(si3), SPEC_HASH(si3+vec3(1,0,0)), sf3.x),
mix(SPEC_HASH(si3+vec3(0,1,0)), SPEC_HASH(si3+vec3(1,1,0)), sf3.x), sf3.y),
mix(mix(SPEC_HASH(si3+vec3(0,0,1)), SPEC_HASH(si3+vec3(1,0,1)), sf3.x),
mix(SPEC_HASH(si3+vec3(0,1,1)), SPEC_HASH(si3+vec3(1,1,1)), sf3.x), sf3.y), sf3.z);
#undef SPEC_HASH

float wx = (sn1 - 0.5) * 0.5 + (sn2 - 0.5) * 0.3 + (sn3 - 0.5) * 0.2;
float wz = (sn2 - 0.5) * 0.5 + (sn3 - 0.5) * 0.3 + (sn1 - 0.5) * 0.2;

vec3 topN = normalize(normal + mat3(gbufferModelView) * vec3(wx * 1.0, 0.0, wz * 1.0));
vec3 topH = normalize(topV + topL);
float topNdotH = max(dot(topN, topH), 0.0);
TimeWeightsSimple topTS = getTimeWeightsSimple(sunAngle);
float topDayFactor = topTS.day + topTS.twilight * 0.7;
float topSunsetBoost = 1.0 + topTS.twilight * 2.0;
float topSpec = smoothstep(0.95, 0.99, topNdotH);
float topGlow = topSpec * topDayFactor * waterSkylight * topSunsetBoost;
vec3 topGlowCol = mix(vec3(1.0, 0.95, 0.85),
vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), topTS.twilight);

vec3 topShadowScenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec4 topShadowClip = shadowProjection * shadowModelView * vec4(topShadowScenePos, 1.0);
vec3 topShadowDistorted = distortShadowClipPos(topShadowClip.xyz / topShadowClip.w);
vec3 topShadowScreen = topShadowDistorted * 0.5 + 0.5;
float topShadow = 0.0;
if (topShadowScreen.x > 0.0 && topShadowScreen.x < 1.0 && topShadowScreen.y > 0.0 && topShadowScreen.y < 1.0) {
float topShadowDepth = texture(shadowtex0, topShadowScreen.xy).r;
topShadow = step(topShadowScreen.z - 0.001, topShadowDepth);
}
float topGlowAmt = topGlow * WATER_SPECULAR_INTENSITY * 0.4 * topShadow * waterEffectScale * mix(1.0, 0.1, smoothSwamp);
preSpecularColor = color;
color += topGlowCol * topGlowAmt;
}
}
}

if (isDhWater && isWaterOnly && isEyeInWater != 1) {
vec3 dhWorldNormal = vec3(
reflData.z * 2.0 - 1.0,
reflData.w * 2.0 - 1.0,
0.0
);
dhWorldNormal.z = sqrt(max(1.0 - dhWorldNormal.x * dhWorldNormal.x - dhWorldNormal.y * dhWorldNormal.y, 0.0));
vec3 dhNormalView = normalize(mat3(gbufferModelView) * dhWorldNormal);

vec3 dhScreenPos = vec3(texcoord, dhDepth);
vec3 dhNdc = dhScreenPos * 2.0 - 1.0;
vec4 dhViewH = dhProjectionInverse * vec4(dhNdc, 1.0);
vec3 dhViewPos = dhViewH.xyz / dhViewH.w;

float dhFresnel = 1.0 - abs(dot(normalize(-dhViewPos), dhNormalView));
dhFresnel *= dhFresnel;
dhFresnel *= dhFresnel;
float dhFresnelMod = mix(0.6, 1.0, dhFresnel) * WATER_REFLECTION_FADE;
dhFresnelMod = clamp(dhFresnelMod, 0.0, 1.0);

TimeWeightsSimple dhReflTS = getTimeWeightsSimple(sunAngle);
float dhReflDay = dhReflTS.day + dhReflTS.twilight;
float dhReflNight = dhReflTS.night + dhReflTS.blueHour;
float dhReflTOD = mix(0.15, 1.0, dhReflDay) + dhReflNight * 0.85;

vec3 dhReflDir = reflect(normalize(dhViewPos), dhNormalView);
vec3 dhWorldPos = (gbufferModelViewInverse * vec4(dhViewPos, 1.0)).xyz + cameraPosition;
{
float dhWT = frameTimeCounter * WATER_WAVE_SPEED;
vec2 dhWP = dhWorldPos.xz * WATER_WAVE_SCALE * 2.5;
float dhWX = sin(dhWP.x * 3.0 + dhWP.y * 0.3 + dhWT * 1.5) * 0.5
+ sin(dhWP.x * 5.0 + dhWP.y * 0.5 + dhWT * 2.2) * 0.3
+ sin(dhWP.x * 8.0 + dhWP.y * 0.2 + dhWT * 3.0) * 0.2;
float dhWZ = sin(dhWP.x * 0.3 + dhWP.y * 3.0 + dhWT * 1.3) * 0.5
+ sin(dhWP.x * 0.5 + dhWP.y * 5.0 + dhWT * 2.0) * 0.3;
dhReflDir.x += dhWX * 0.005;
dhReflDir.z += dhWZ * 0.005;
dhReflDir = normalize(dhReflDir);
}
float dhRbTOD = mix(0.20, 1.0, dhReflNight / max(dhReflDay + dhReflNight, 0.001));
float dhRbActive = max(dhReflDay, dhReflNight);
dhRbTOD = mix(0.60, dhRbTOD, dhRbActive);
float dhNightBlend = dhReflNight / max(dhReflDay + dhReflNight, 0.001);
float dhSkyBright = mix(WATER_SKY_BRIGHTNESS_DAY, WATER_SKY_BRIGHTNESS_NIGHT, dhNightBlend);
dhSkyBright = mix(mix(WATER_SKY_BRIGHTNESS_DAY, WATER_SKY_BRIGHTNESS_NIGHT, 0.5), dhSkyBright, dhRbActive);
vec3 dhSkyColor = ilv_getSkyColor(dhReflDir, dhWorldPos, false) * 1.0;

float dhReflStrength = WATER_REFLECTION_AMOUNT * dhReflTOD * dhFresnelMod * WATER_SKY_REFLECTION * WATER_OPACITY;
float dhCrestReflectCut = 1.0;
dhReflStrength *= dhCrestReflectCut;
float dhSkylight = texelFetch(colortex1, texelcoord, 0).b;
dhReflStrength *= smoothstep(13.0 / 15.0, 14.0 / 15.0, dhSkylight);
dhReflStrength = clamp(dhReflStrength, 0.0, 1.0);
dhReflStrength *= waterEffectScale;
color = mix(color, dhSkyColor, dhReflStrength);
}
#endif

ssrDelta = color - preSSR;

ssrPreSpecularColor = preSpecularColor;

color = preSSR;

preSpecularColor = preSSR;

#endif
#endif
#endif

if (isEyeInWater != 1) {
vec2 cloudUV = texcoord;
bool isWaterSide = (waterData.y > 0.9) && (waterData.w * 2.0 - 1.0 < 0.5);
if (isWaterSide) {
float sideNoise = waterData.x;
vec2 refrOffset = vec2((sideNoise - 0.5) * 0.8, (sideNoise - 0.5) * 1.2);
float refrPx = 14.0 / max(viewWidth, 1.0);
cloudUV += refrOffset * refrPx;
cloudUV = clamp(cloudUV, vec2(0.0), vec2(1.0));
}
vec4 cloudData = texture(colortex8, cloudUV);
float cloudBlend = clamp(1.0 - cloudAlpha, 0.0, 1.0);
float cloudHitDist = cloudData.a;
float cloudSceneDist = 1e20;

if (depth1 < 0.9999) {
cloudSceneDist = min(cloudSceneDist, length(reconstructViewPos(gbufferProjectionInverse, texcoord, depth1)));
}
if (hasValidDHDepth(dhDepth)) {
cloudSceneDist = min(cloudSceneDist, length(getWorldPosDH(texcoord, dhDepth) - cameraPosition));
}
float cloudVxDepth = texture(vxDepthTexTrans, texcoord).r;
if (cloudVxDepth > 0.00001 && cloudVxDepth < 0.9999) {
cloudSceneDist = min(cloudSceneDist, length(reconstructViewPos(vxProjInv, texcoord, cloudVxDepth)));
}

bool cloudBehindScene = (cloudHitDist > 0.001) && (cloudSceneDist < cloudHitDist - 1.0);
if (cloudBlend > 0.001 && !entityInFront && !particleOverSky && !cloudBehindScene) {
color = color * (1.0 - cloudBlend) + cloudData.rgb;
}
}

float fogAmount = 0.0;
vec3 savedSunColor = color;

#if defined(NETHER_FOG_ENABLED) || defined(END_FOG_ENABLED) || defined(OVERWORLD_FOG_ENABLED)

bool netherEntityFog = entityInFront && isForcedNetherBiome(biome);
{
vec3 fogScatter = vec3(0.0);
float fogTrans = 1.0;
float fogAmountLocal = 0.0;

float fogDepth;
vec3 fogWorldPos;
bool fogIsSky = false;
bool fogFromDH = false;

float vxDepthFog = texture(vxDepthTexTrans, texcoord).r;
bool hasVoxyDepthFog = (vxDepthFog > 0.00001 && vxDepthFog < 0.9999);
bool isVoxyLodPixel = (maskData.a > 0.999);
bool hasDHAtPixel = hasValidDHDepth(dhDepth);
bool fogUseWaterSurface =
isWaterOnly &&
((isVoxyWater && (hasVoxyDepthFog || depth0 < 0.9999)) ||
(isDhWater && hasDHAtPixel) ||
(!isVoxyWater && !isDhWater && isWater && depthAll < 0.9999));

if (entityInFront || opaqueBlockEntityInFront) {
fogDepth = depth0;
fogWorldPos = getWorldPos(texcoord, depth0);
fogFromDH = false;
fogIsSky = false;
} else if (fogUseWaterSurface) {
if (isVoxyWater) {
fogDepth = hasVoxyDepthFog ? vxDepthFog : depth0;
vec3 vxWaterView = getVoxyWaterViewPos(texcoord, depth0);
fogWorldPos = (gbufferModelViewInverse * vec4(vxWaterView, 1.0)).xyz + cameraPosition;
fogFromDH = false;
} else if (isDhWater) {
fogDepth = dhDepth;
fogWorldPos = getWorldPosDH(texcoord, fogDepth);
fogFromDH = true;
} else {
fogDepth = depthAll;
fogWorldPos = getWorldPos(texcoord, fogDepth);
fogFromDH = false;
}
fogIsSky = false;
} else if (hasVoxyDepthFog) {
fogDepth = vxDepthFog;
vec4 vxClip = vxProjInv * vec4(texcoord * 2.0 - 1.0, vxDepthFog * 2.0 - 1.0, 1.0);
vec3 vxView = vxClip.xyz / vxClip.w;
fogWorldPos = (gbufferModelViewInverse * vec4(vxView, 1.0)).xyz + cameraPosition;
fogFromDH = false;
fogIsSky = false;
} else if (depthOpaque < 0.9999 || isVoxyLodPixel) {
fogDepth = depthOpaque;
fogWorldPos = getWorldPos(texcoord, fogDepth);
fogFromDH = false;
float linearOpaque = linearizeDepth(depthOpaque);
float linearDH = hasDHAtPixel ? linearizeDepthDH(dhDepth) : 1e10;
if (hasDHAtPixel && linearDH < linearOpaque) {
fogDepth = dhDepth;
fogWorldPos = getWorldPosDH(texcoord, fogDepth);
fogFromDH = true;
}
fogIsSky = false;
} else if (hasDHAtPixel) {
fogDepth = dhDepth;
fogWorldPos = getWorldPosDH(texcoord, fogDepth);
fogFromDH = true;
fogIsSky = false;
} else {
fogIsSky = true;
fogDepth = 1.0;
vec4 clipPos = vec4(texcoord * 2.0 - 1.0, 0.0, 1.0);
vec4 viewPos = gbufferProjectionInverse * clipPos;
vec3 viewDir = normalize(viewPos.xyz);
vec4 worldDir = gbufferModelViewInverse * vec4(viewDir, 0.0);
fogWorldPos = cameraPosition + worldDir.xyz * far;
fogFromDH = false;
}

vec4 fog = (isEyeInWater == 2) ? vec4(0.0, 0.0, 0.0, 1.0) : computeVolumetricFog(texcoord, fogDepth, fogWorldPos, fogIsSky, fogFromDH);

if (entityInFront || blockEntityPixel) {
fog = vec4(0.0, 0.0, 0.0, 1.0);
}

fogScatter = fog.rgb;
fogTrans = clamp(fog.a, 0.0, 1.0);
fogAmountLocal = clamp(1.0 - fogTrans, 0.0, 1.0);

#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome) && fogIsSky) {
vec3 netherSkyFog = getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B)) * NETHER_BRIGHTNESS;
color = netherSkyFog;
fogAmountLocal = 1.0;
}
#endif

fogAmountLocal *= cloudMask;
fogScatter *= cloudMask;
fogTrans = 1.0 - fogAmountLocal;

if (fogAmountLocal > 0.001) {

bool isEmissive = maskData.g > 0.5;
#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome) && isEmissive) {
float emissiveDist = length(fogWorldPos - cameraPosition);
float emissiveFogStart = NETHER_DISTANCE_FOG_START * 1.5;
float emissiveFogResist = 1.0 - smoothstep(emissiveFogStart, float(NETHER_FOG_DISTANCE), emissiveDist);
fogAmountLocal *= mix(1.0, 0.0, emissiveFogResist);
fogScatter *= mix(1.0, 0.0, emissiveFogResist);
fogTrans = 1.0 - fogAmountLocal;
}
#endif

#ifdef END_SHADER

{
float fogTransLocal = 1.0 - fogAmountLocal;
vec3 additiveResult = color * (1.0 - fogAmountLocal * 0.4) + fogScatter;
vec3 standardResult = color * fogTransLocal + fogScatter;

float baseMix = 0.5;
#ifdef END_EVENT_ENABLED
float endBlendDark = getEndEvent(frameTimeCounter).fogDarkness;
baseMix = mix(baseMix, 1.0, endBlendDark);
#endif

color = mix(additiveResult, standardResult, baseMix);
}
#else

color = color * fogTrans + fogScatter;
#endif
fogAmount = max(fogAmount, fogAmountLocal);
}
}
#endif

#ifdef END_SHADER
{
bool endIsEmissive = (maskData.g > 0.5) && !entityInFront;
bool endIsTrueSky = isSky && !hasValidDHDepth(dhDepth) && !(maskData.a > 0.999);
if (!endIsEmissive && !endIsTrueSky) {
vec3 endPreDarkColor = color;
float baseDarken = 0.73;
vec3 purpleTint = vec3(0.08, 0.06, 0.35);
float tintMult = 0.15;
float colorShift = 0.55;

#ifdef END_EVENT_ENABLED
float eventDarkness = getEndEvent(frameTimeCounter).terrainDarkness;
baseDarken = mix(baseDarken, 0.02, eventDarkness);
tintMult = mix(tintMult, 0.0, eventDarkness);
colorShift = mix(colorShift, 0.0, eventDarkness);
#endif

float entityDarkenScale = entityInFront ? 0.1 : 1.0;
color *= mix(1.0, baseDarken, entityDarkenScale);
color += purpleTint * tintMult * entityDarkenScale;
color = mix(color, color * vec3(0.55, 0.58, 1.35), colorShift * entityDarkenScale);

vec3 endWorldPos;
if (maskData.a > 0.999) {

float endVxD = texture(vxDepthTexTrans, texcoord).r;
if (endVxD > 0.00001 && endVxD < 0.9999) {
vec4 endVxClip = vxProjInv * vec4(texcoord * 2.0 - 1.0, endVxD * 2.0 - 1.0, 1.0);
endWorldPos = (gbufferModelViewInverse * vec4(endVxClip.xyz / endVxClip.w, 1.0)).xyz + cameraPosition;
} else {
vec4 endClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depthOpaque * 2.0 - 1.0, 1.0);
endWorldPos = (gbufferModelViewInverse * vec4(endClip.xyz / endClip.w, 1.0)).xyz + cameraPosition;
}
} else if (depthOpaque >= 0.9999 && hasValidDHDepth(dhDepth)) {
endWorldPos = getWorldPosDH(texcoord, dhDepth);
} else {
vec4 endClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depthOpaque * 2.0 - 1.0, 1.0);
endWorldPos = (gbufferModelViewInverse * vec4(endClip.xyz / endClip.w, 1.0)).xyz + cameraPosition;
}
float depthDarken = entityInFront ? 0.0 : (1.0 - smoothstep(28.0, 53.0, endWorldPos.y));
color *= mix(1.0, 0.25, depthDarken);

#if defined(END_EVENT_ENABLED) && defined(HANDHELD_LIGHT_ENABLED)
if (!entityInFront && eventDarkness > 0.001) {
color += getPostHandheldLightBoost(endWorldPos, endPreDarkColor, color) * eventDarkness;
}
#endif
}
}
#endif

#if 0
#if defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)

TimeWeightsSimple wsTS = getTimeWeightsSimple(sunAngle);
float wsDay = wsTS.day + wsTS.twilight;
float wsNight = wsTS.night + wsTS.blueHour;
float wsNightFactor = wsNight / max(wsDay + wsNight, 0.001);
float wsActive = max(wsDay, wsNight);
wsNightFactor = mix(0.0, wsNightFactor, wsActive);

if (isWater || isDhWater) {
float lum = dot(color, vec3(0.299, 0.587, 0.114));
float sat = mix(WATER_SATURATION, WATER_SATURATION * WATER_NIGHT_SATURATION, wsNightFactor);
color = mix(vec3(lum), color, sat);
}

#ifdef UNDERWATER_FOG_ENABLED
if ((isWater || isDhWater) && isEyeInWater != 1) {
float beerDepth0 = depth0;
float beerDepth1 = texelFetch(depthtex1, texelcoord, 0).r;

vec4 beerWaterClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, beerDepth0 * 2.0 - 1.0, 1.0);
vec3 beerWaterView = beerWaterClip.xyz / beerWaterClip.w;
vec4 beerTerrainClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, beerDepth1 * 2.0 - 1.0, 1.0);
vec3 beerTerrainView = beerTerrainClip.xyz / beerTerrainClip.w;

float waterThickness = max(length(beerTerrainView) - length(beerWaterView), 0.0);

if (waterThickness < 0.5 && (isVoxyLod || isDhWater)) {
vec3 beerWorldPos = (gbufferModelViewInverse * vec4(beerWaterView, 1.0)).xyz + cameraPosition;
waterThickness = max(float(SEA_LEVEL_OFFSET) - beerWorldPos.y + 2.0, 0.0);
}

vec3 beerAbsorb = vec3(0.009, 0.004, 0.0015);
vec3 beerTrans = exp(-waterThickness * beerAbsorb);
vec3 beerTint = vec3(0.1, 0.4, 0.8);

#ifdef WATER_DEBUG_COLORS_ENABLED
color = vec3(voxyMarker);
if (isVoxyLod) color = vec3(1.0, 0.0, 0.0);
if (isDhWater) color = vec3(0.0, 1.0, 0.0);
if (isVoxyWater) color = vec3(1.0, 1.0, 0.0);
#endif
}
#endif

#ifdef WATER_FOAM_ENABLED
if ((isWater || isDhWater) && isEyeInWater != 1) {
vec3 rfViewPos;
if (isVoxyWater) {
rfViewPos = getVoxyWaterViewPos(texcoord, depth0);
} else if (isDhWater) {
vec4 rfClipDH = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, dhDepth * 2.0 - 1.0, 1.0);
rfViewPos = rfClipDH.xyz / rfClipDH.w;
} else {
vec4 rfClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
rfViewPos = rfClip.xyz / rfClip.w;
}
vec3 rfWorldPos = (gbufferModelViewInverse * vec4(rfViewPos, 1.0)).xyz + cameraPosition;
float rft = frameTimeCounter * WATER_WAVE_SPEED;
float rfEps = 0.15;

#define RF_WAVE_RAW(f) (smoothstep(0.15, 0.25, f) * (1.0 - pow(smoothstep(0.25, 1.15, f), 0.45)))
#define RF_WAVE(px) RF_WAVE_RAW(1.0 - fract(px))
#define RF_OWAVE(px) (pow(0.5 + 0.5 * sin((fract(px) - 0.25) * 6.2832), 1.6))
#define RF_SMAX(a, b, k) (max(a, b) + pow(max(k - abs(a - b), 0.0) / k, 3.0) * k * 0.166667)

vec2 rfSlope = vec2(0.0);
bool rfIsSide = (decodedWorldNormal.y < 0.5) && isWaterTagged;

if (rfIsSide) {
float sideRefrNoise = texelFetch(colortex5, texelcoord, 0).x;
rfSlope = vec2((sideRefrNoise - 0.5) * 0.8, (sideRefrNoise - 0.5) * 1.2);
} else if (biome_beach > 0.01 && biome_beach >= biome_ocean) {
float rfwx = rfWorldPos.x * WATER_WAVE_SCALE;
float rfwz = rfWorldPos.z * WATER_WAVE_SCALE;
float rfzOff1 = sin(rfwz * 0.21 + 3.7) * 2.5 + sin(rfwz * 0.53 + 1.2) * 1.3;
float rfzOff2 = sin(rfwz * 0.37 + 5.1) * 1.8 + sin(rfwz * 0.71 + 2.8) * 1.1;
float rfzOff3 = sin(rfwz * 0.62 + 0.9) * 1.2 + sin(rfwz * 0.89 + 4.3) * 0.8;
float rfH = clamp(RF_SMAX(RF_WAVE((rfwx * 0.8 + rfzOff1 - rft) / 6.2832), RF_WAVE((rfwx * 1.8 + rfzOff2 - rft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
rfH += RF_WAVE((rfwx * 4.0 + rfzOff3 - rft * 2.2) / 6.2832) * 0.15 * rfH;
float rfwxp = (rfWorldPos.x + rfEps) * WATER_WAVE_SCALE;
float rfHx = clamp(RF_SMAX(RF_WAVE((rfwxp * 0.8 + rfzOff1 - rft) / 6.2832), RF_WAVE((rfwxp * 1.8 + rfzOff2 - rft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
rfHx += RF_WAVE((rfwxp * 4.0 + rfzOff3 - rft * 2.2) / 6.2832) * 0.15 * rfHx;
float rfwzp = (rfWorldPos.z + rfEps) * WATER_WAVE_SCALE;
float rfzOff1z = sin(rfwzp * 0.21 + 3.7) * 2.5 + sin(rfwzp * 0.53 + 1.2) * 1.3;
float rfzOff2z = sin(rfwzp * 0.37 + 5.1) * 1.8 + sin(rfwzp * 0.71 + 2.8) * 1.1;
float rfzOff3z = sin(rfwzp * 0.62 + 0.9) * 1.2 + sin(rfwzp * 0.89 + 4.3) * 0.8;
float rfHz = clamp(RF_SMAX(RF_WAVE((rfwx * 0.8 + rfzOff1z - rft) / 6.2832), RF_WAVE((rfwx * 1.8 + rfzOff2z - rft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
rfHz += RF_WAVE((rfwx * 4.0 + rfzOff3z - rft * 2.2) / 6.2832) * 0.15 * rfHz;
rfSlope = vec2(rfHx - rfH, rfHz - rfH) / rfEps;
}
#undef RF_WAVE
#undef RF_WAVE_RAW
#undef RF_OWAVE
#undef RF_SMAX

float rfBiomeFactor = max(waveBiome, 0.5);
float rfDist = max(length(rfViewPos), 1.0);
float refrDistFade = 1.0 - smoothstep(30.0, 80.0, rfDist);
float refrBase = (biome_beach > 0.01) ? 18.0 : 14.0;
float refrPx = refrBase * rfBiomeFactor / max(rfDist * 0.02, 0.5);
ivec2 refrCoord = texelcoord + ivec2(rfSlope * refrPx);
refrCoord = clamp(refrCoord, ivec2(0), ivec2(viewWidth - 1.0, viewHeight - 1.0));
float refrDepth = texelFetch(depthtex1, refrCoord, 0).r;
if (refrDepth > depth0 && refrDistFade > 0.01) {
vec3 refrOpaque = texelFetch(colortex0, refrCoord, 0).rgb;
vec4 refrTrans = texelFetch(colortex7, refrCoord, 0);
vec3 refrColor = refrTrans.a > 0.001 ? refrOpaque * (1.0 - refrTrans.a) + refrTrans.rgb : refrOpaque;
color = mix(color, refrColor, 0.95 * refrDistFade);
}
}
#endif

if (false && (isWater || isDhWater) && isWaterOnly && isEyeInWater != 1) {
float wDist;
if (isDhWater) {
vec4 dhClip = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, dhDepth * 2.0 - 1.0, 1.0);
wDist = -dhClip.z / dhClip.w;
} else {
vec4 wClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
wDist = -wClip.z / wClip.w;
}

float fogDensity = mix(0.025, 2.0, biome_swamp);
float fogMax = mix(0.95, 1.0, biome_swamp);
float uwFogAmount = 1.0 - exp(-wDist * fogDensity);
uwFogAmount = clamp(uwFogAmount, 0.0, fogMax);

if (uwFogAmount > 0.001) {
float uwAngle = fract(sunAngle);
float uwTwilight = smoothstep(0.40, 0.48, uwAngle) * smoothstep(0.55, 0.48, uwAngle)
+ smoothstep(0.94, 1.0, uwAngle) + smoothstep(0.06, 0.0, uwAngle);
if (uwTwilight > 0.001) {
float uwLum = dot(color, vec3(0.299, 0.587, 0.114));
color = mix(color, vec3(uwLum), uwTwilight * 0.6);
}
vec3 beachTint = biomeWaterColor(sunAngle, 1.0, 0.0, 0.0, 0.0, 0.0);
vec3 swampTint = vec3(0.04, 0.08, 0.02);
vec3 uwWaterTint = mix(beachTint, swampTint, biome_swamp);
color *= mix(vec3(1.0), uwWaterTint * 3.0, uwFogAmount);
color += uwWaterTint * uwFogAmount;
}
}

#ifdef SWAMP_SNAKE_LIGHT_ENABLED
if ((isWater || isDhWater) && isEyeInWater != 1 && biome_swamp > 0.01) {
float waterSurfDepth = isDhWater ? dhDepth : depth0;
vec3 surfViewPos = ilv_screenToView(vec3(texcoord, waterSurfDepth));
vec3 surfWorldPos = (gbufferModelViewInverse * vec4(surfViewPos, 1.0)).xyz + cameraPosition;

float st = frameTimeCounter;
vec3 snakeAnchor = vec3(
floor(cameraPosition.x / 16.0) * 16.0 + 8.0,
surfWorldPos.y,
floor(cameraPosition.z / 16.0) * 16.0 + 8.0
);

vec3 viewDir = normalize(surfWorldPos - cameraPosition);
float snakeGlow = 0.0;
int steps = 6;
float maxDist = 6.0;
float stepLen = maxDist / float(steps);

for (int s = 0; s < steps; s++) {
float marchDist = stepLen * (float(s) + 0.5);
vec3 samplePos = surfWorldPos + viewDir * marchDist;
float fogAtten = exp(-marchDist * 1.0);
for (int i = 0; i < 16; i++) {
float tt = float(i) * 0.8;
float sx = sin(tt * 1.2 + st * 0.4) * 3.0 + sin(tt * 0.5 + st * 0.15) * 6.0;
float sz = cos(tt * 0.9 + st * 0.3) * 4.0 + cos(tt * 0.4 + st * 0.2) * 5.0;
float sy = -0.5 - sin(tt * 1.8 + st * 0.5) * 0.5 - abs(sin(tt * 0.3 + st * 0.1)) * 1.0;
vec3 spinePos = snakeAnchor + vec3(sx, sy, sz);
float dist = length(samplePos - spinePos);
snakeGlow += fogAtten / (1.0 + dist * dist * 2.0);
}
}
snakeGlow = snakeGlow / float(steps);
snakeGlow = clamp(snakeGlow * 0.25, 0.0, 1.0);
vec3 glowColor = vec3(0.2, 0.55, 0.1);
color += glowColor * snakeGlow * biome_swamp;
}
#endif

#endif
#endif

if (isEyeInWater == 1) {
bool uwAbove = (depth1 >= 0.9999);
if (!uwAbove) {
bool uwIsVoxy = (maskData.a > 0.99);
mat4 uwProj = uwIsVoxy ? dhProjectionInverse : gbufferProjectionInverse;
vec4 uwClip = uwProj * vec4(texcoord * 2.0 - 1.0, depth1 * 2.0 - 1.0, 1.0);
vec3 uwViewP = uwClip.xyz / uwClip.w;
vec3 uwWorldP = (gbufferModelViewInverse * vec4(uwViewP, 1.0)).xyz + cameraPosition;
uwAbove = (uwWorldP.y > float(SEA_LEVEL_OFFSET) + 0.5);
}
if (uwAbove) {
vec4 uwrClip = vec4(texcoord * 2.0 - 1.0, 0.5, 1.0);
vec4 uwrView = gbufferProjectionInverse * uwrClip;
vec3 uwViewDir = normalize(uwrView.xyz);
vec3 uwWorldDir = normalize(mat3(gbufferModelViewInverse) * uwViewDir);
float uwTRay = (float(SEA_LEVEL_OFFSET) - cameraPosition.y) / max(uwWorldDir.y, 0.001);
vec2 uwSurfXZ = cameraPosition.xz + uwWorldDir.xz * max(uwTRay, 0.0);

vec2 uwWP = uwSurfXZ * 0.5;
float uwT = frameTimeCounter * WATER_WAVE_SPEED;
float uwSx = cos(uwWP.x * 2.0 + uwWP.y * 0.7 + uwT * 1.2) * 0.3
+ cos(uwWP.x * 1.3 - uwWP.y * 1.8 + uwT * 0.8) * 0.2;
float uwSz = cos(uwWP.y * 2.2 + uwWP.x * 0.5 + uwT * 1.0) * 0.3
+ cos(uwWP.y * 1.5 - uwWP.x * 1.6 + uwT * 1.1) * 0.2;

float uwRefrPx = 14.0;
ivec2 uwRefrCoord = texelcoord + ivec2(vec2(uwSx, uwSz) * uwRefrPx);
uwRefrCoord = clamp(uwRefrCoord, ivec2(0), ivec2(viewWidth - 1.0, viewHeight - 1.0));
vec3 uwRefrOpaque = texelFetch(colortex0, uwRefrCoord, 0).rgb;
vec4 uwRefrTrans = texelFetch(colortex7, uwRefrCoord, 0);
vec3 uwRefrColor = uwRefrTrans.a > 0.001
? uwRefrOpaque * (1.0 - uwRefrTrans.a) + uwRefrTrans.rgb
: uwRefrOpaque;

float uwSurfDist = length(uwSurfXZ - cameraPosition.xz);
float uwRadius = 8.0;
float uwRadiusFade = 1.0 - smoothstep(uwRadius * 0.5, uwRadius, uwSurfDist);

vec3 uwSunDirC = normalize(mat3(gbufferModelViewInverse) * sunPosition);
float uwNightFadeC = 1.0 - smoothstep(-0.05, 0.3, uwSunDirC.y);
float uwSunsetFadeC = smoothstep(0.0, 0.15, uwSunDirC.y) * (1.0 - smoothstep(0.15, 0.35, uwSunDirC.y));
vec3 uwDarkDay = vec3(0.12, 0.22, 0.50);
vec3 uwDarkSunset = vec3(0.60, 0.22, 0.05);
vec3 uwDarkNight = vec3(0.10, 0.18, 0.42);

vec3 uwSwampDay = vec3(0.06, 0.12, 0.05);
vec3 uwSwampNight = vec3(0.04, 0.08, 0.03);
uwDarkDay = mix(uwDarkDay, uwSwampDay, smoothSwamp);
uwDarkSunset = mix(uwDarkSunset, uwSwampDay, smoothSwamp);
uwDarkNight = mix(uwDarkNight, uwSwampNight, smoothSwamp);
vec3 uwCeilingDark = mix(mix(uwDarkDay, uwDarkSunset, uwSunsetFadeC), uwDarkNight, uwNightFadeC);
color = mix(uwCeilingDark, uwRefrColor * 2.0, uwRadiusFade);
transAlpha = 0.0;
}
}

if ((isWater || isDhWater) && isWaterOnly && isEyeInWater != 1) {

vec3 beerWaterView;
if (isVoxyWater) {
beerWaterView = getVoxyWaterViewPos(texcoord, depth0);
} else if (isDhWater) {
vec4 beerWClipDH = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
beerWaterView = beerWClipDH.xyz / beerWClipDH.w;
} else {
vec4 beerWaterClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
beerWaterView = beerWaterClip.xyz / beerWaterClip.w;
}

float beerTerrainDepth = texelFetch(depthtex1, texelcoord, 0).r;
vec4 beerTerrainClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, beerTerrainDepth * 2.0 - 1.0, 1.0);
vec3 beerTerrainView = beerTerrainClip.xyz / beerTerrainClip.w;

vec3 beerWaterWorld = (gbufferModelViewInverse * vec4(beerWaterView, 1.0)).xyz + cameraPosition;
vec3 beerTerrainWorld = (gbufferModelViewInverse * vec4(beerTerrainView, 1.0)).xyz + cameraPosition;
float waterThickness;
if (isDhWater) {

float dhTerrainDepth = texelFetch(dhDepthTex1, texelcoord, 0).r;
if (hasValidDHDepth(dhTerrainDepth)) {
vec4 dhTerrainClip = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, dhTerrainDepth * 2.0 - 1.0, 1.0);
vec3 dhTerrainView = dhTerrainClip.xyz / dhTerrainClip.w;
vec3 dhTerrainWorld = (gbufferModelViewInverse * vec4(dhTerrainView, 1.0)).xyz + cameraPosition;
waterThickness = max(beerWaterWorld.y - dhTerrainWorld.y, 0.0);
} else {
waterThickness = max(float(SEA_LEVEL_OFFSET) - beerWaterWorld.y + 2.0, 0.0);
}
} else if (beerTerrainDepth < 0.9999 && !isVoxyLod) {
waterThickness = max(beerWaterWorld.y - beerTerrainWorld.y, 0.0);
} else {
waterThickness = max(float(SEA_LEVEL_OFFSET) - beerWaterWorld.y + 2.0, 0.0);
}
waterThickness = min(waterThickness, 16.0);

vec3 beerAbsorb = vec3(0.12, 0.06, 0.025);
vec3 beerTrans = exp(-waterThickness * beerAbsorb);

vec3 beerFogCol = biomeWaterColor(sunAngle, biome_beach, biome_swamp, biome_jungle, biome_snowy, biome_arid) * 0.4;
vec3 beerColor = mix(beerFogCol, color, beerTrans);
color = mix(color, beerColor, waterSurfaceSkylight);
}

float aboveWaterCausticStrength = 0.0;

#ifdef WATER_WAVES_ENABLED
if (isWaterOnly && !isVoxyWater && isEyeInWater != 1 && storedScreenSkylight > 0.1) {
float causticWaterDepthRaw = isDhWater ? dhDepth : depth0;
bool causticHasWaterSurface = isDhWater ? hasValidDHDepth(causticWaterDepthRaw)
: (causticWaterDepthRaw > 0.00001 && causticWaterDepthRaw < 0.9999);

float causticTerrainDepth = depth1;
bool causticTerrainUsesDH = false;
bool causticTerrainUsesVoxy = false;
bool causticHasTerrain = (causticTerrainDepth > 0.00001 && causticTerrainDepth < 0.9999);

if (isDhWater) {
float causticDhTerrainDepth = texelFetch(dhDepthTex1, texelcoord, 0).r;
causticHasTerrain = hasValidDHDepth(causticDhTerrainDepth);
causticTerrainDepth = causticDhTerrainDepth;
causticTerrainUsesDH = causticHasTerrain;
} else if (!causticHasTerrain) {
float causticVxTerrainDepth = texture(vxDepthTexTrans, texcoord).r;
causticHasTerrain = (causticVxTerrainDepth > 0.00001 && causticVxTerrainDepth < 0.9999);
causticTerrainDepth = causticVxTerrainDepth;
causticTerrainUsesVoxy = causticHasTerrain;
}

if (causticHasWaterSurface && causticHasTerrain) {
vec3 causticWaterWorld = isDhWater ? getWorldPosDH(texcoord, causticWaterDepthRaw)
: getWorldPos(texcoord, causticWaterDepthRaw);
vec3 causticTerrainWorld;
if (causticTerrainUsesDH) {
causticTerrainWorld = getWorldPosDH(texcoord, causticTerrainDepth);
} else if (causticTerrainUsesVoxy) {
vec4 causticVxClip = vxProjInv * vec4(texcoord * 2.0 - 1.0, causticTerrainDepth * 2.0 - 1.0, 1.0);
vec3 causticVxView = causticVxClip.xyz / causticVxClip.w;
causticTerrainWorld = (gbufferModelViewInverse * vec4(causticVxView, 1.0)).xyz + cameraPosition;
} else {
causticTerrainWorld = getWorldPos(texcoord, causticTerrainDepth);
}
float causticWaterDepth = causticWaterWorld.y - causticTerrainWorld.y;

if (causticWaterDepth > 0.05) {
float ct = frameTimeCounter * WATER_WAVE_SPEED * 0.4;
vec3 cPos3D = causticTerrainWorld * 0.75;

float cA = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = cPos3D;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
cA += abs(noise3D(p * freq + ct * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
cA = 1.0 - cA / total;
}

float cB = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = cPos3D + 5.0;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
cB += abs(noise3D(p * freq + ct * 1.15 * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
cB = 1.0 - cB / total;
}

float caustic = min(cA, cB);
caustic = pow(caustic, 2.0) * 2.5;
caustic = max(caustic - 0.15, 0.0) * (1.0 / 0.85);

float causticDepthFade = 1.0 - smoothstep(1.5, 8.0, causticWaterDepth);
causticDepthFade *= exp(-causticWaterDepth * 0.25);
TimeWeightsSimple causticTS = getTimeWeightsSimple(sunAngle);
float causticSunGate = causticTS.day + causticTS.twilight * 0.5;
float causticShadow = 1.0;
#ifdef SHADOWS_ENABLED
{
vec3 causticScenePos = causticTerrainWorld - cameraPosition;
vec4 causticShadowClip = shadowProjection * shadowModelView * vec4(causticScenePos, 1.0);
vec3 causticShadowDist = distortShadowClipPos(causticShadowClip.xyz / causticShadowClip.w);
vec3 causticShadowScreen = causticShadowDist * 0.5 + 0.5;
if (causticShadowScreen.x > 0.0 && causticShadowScreen.x < 1.0 &&
causticShadowScreen.y > 0.0 && causticShadowScreen.y < 1.0 &&
causticShadowScreen.z > 0.0 && causticShadowScreen.z < 1.0) {
float causticShadowDepth = texture(shadowtex0, causticShadowScreen.xy).r;
causticShadow = step(causticShadowScreen.z - 0.001, causticShadowDepth);
causticShadow = mix(1.0, causticShadow, shadowEdgeFade(causticShadowScreen));
}
}
#endif
aboveWaterCausticStrength = caustic * causticDepthFade * causticSunGate * causticShadow * storedScreenSkylight * 0.28;
}
}
}
#endif

if ((isWater || isDhWater) && isWaterOnly && isEyeInWater != 1 && (depth1 < 1.0 || isVoxyWater) && storedScreenSkylight > 0.01) {
float uwAngle = fract(sunAngle);
float uwSunsetTint = smoothstep(0.38, 0.45, uwAngle) * (1.0 - smoothstep(0.48, 0.55, uwAngle))
+ smoothstep(0.95, 1.0, uwAngle) + (1.0 - smoothstep(0.0, 0.05, uwAngle));
float uwDayReduce = smoothstep(0.07, 0.15, uwAngle) * (1.0 - smoothstep(0.40, 0.46, uwAngle));
float uwTintStr = clamp(SKYLIGHT_COLOR_TINT * (1.0 - uwDayReduce * 0.6) + uwSunsetTint * SUNSET_TERRAIN_TINT, 0.0, 1.0);

vec3 uwTintBase = getTimelineHorizonColor(sunAngle, 0.5);
float uwTintLum = max(dot(uwTintBase, vec3(0.299, 0.587, 0.114)), 0.35);
uwTintBase = clamp(uwTintBase / uwTintLum, vec3(0.0), vec3(2.0));
vec3 uwTint = mix(vec3(1.0), uwTintBase, uwTintStr);
color *= uwTint;
}

#ifdef WATER_WAVES_ENABLED
if (isEyeInWater != 1 && aboveWaterCausticStrength > 0.001) {
color *= 1.0 + aboveWaterCausticStrength;
}
#endif

vec3 rawGbufColor;
{

bool translucentInFront = (depth0 < depth1 - 0.00005);
bool frontOpaqueBlockEntity =
!entityInFront &&
!isGlassC17 &&
(depth0 < depth1 - 0.00005) &&
(glassTint.a <= 0.01);

bool ambiguousSharedTranslucentOverEntity =
entityInFront &&
!translucentInFront &&
!translucentOverSky &&
!isWater &&
!isDhWater &&
!isGlassC17 &&
!isMaterialRefl;

bool particleLikeSharedTranslucent =
entityInFront &&
(transAlpha > 0.001) &&
!isWater &&
!isDhWater &&
!isGlassC17 &&
!isMaterialRefl;
bool allowSharedTranslucent =
(translucentOverSky ||
translucentInFront ||
!frontOpaqueBlockEntity) &&
(!ambiguousSharedTranslucentOverEntity || particleLikeSharedTranslucent);
if (transAlpha > 0.001 && !isHandEarly && allowSharedTranslucent) {
vec4 sharedTransData = translucentData;
#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
{
float sharedTransLuma = dot(max(sharedTransData.rgb, vec3(0.0)), vec3(0.299, 0.587, 0.114));
bool sharedShadowLike = (sharedTransData.a < 0.9 && sharedTransLuma < 0.04 && glassTint.a <= 0.01);
if (sharedShadowLike) {
float sharedShadowFade = 1.0 - getEndEvent(frameTimeCounter).terrainDarkness;
sharedTransData.rgb *= sharedShadowFade;
sharedTransData.a *= sharedShadowFade;
}
}
#endif
color = color * (1.0 - sharedTransData.a) + sharedTransData.rgb;
}
rawGbufColor = color;
}

#if defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)
#ifndef WATER_REFLECTION_DEBUG
#ifdef WATER_FOAM_ENABLED

if ((isWater || isDhWater) && isWaterOnly && isEyeInWater != 1 && !isVoxyWater) {
vec3 rfViewPos;
if (isDhWater) {
float rfDepthLOD = dhDepth;
vec4 rfClipDH = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, rfDepthLOD * 2.0 - 1.0, 1.0);
rfViewPos = rfClipDH.xyz / rfClipDH.w;
} else {
vec4 rfClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
rfViewPos = rfClip.xyz / rfClip.w;
}
vec3 rfWorldPos = (gbufferModelViewInverse * vec4(rfViewPos, 1.0)).xyz + cameraPosition;
float rft = frameTimeCounter * WATER_WAVE_SPEED;
float rfEps = 0.15;

#define RF_WAVE_RAW_10B(f) (smoothstep(0.15, 0.25, f) * (1.0 - pow(smoothstep(0.25, 1.15, f), 0.45)))
#define RF_WAVE_10B(px) RF_WAVE_RAW_10B(1.0 - fract(px))
#define RF_SMAX_10B(a, b, k) (max(a, b) + pow(max(k - abs(a - b), 0.0) / k, 3.0) * k * 0.166667)

vec2 rfSlope = vec2(0.0);
bool rfIsSide = (decodedWorldNormal.y < 0.5) && isWaterTagged;

if (rfIsSide) {
float sideRefrNoise = texelFetch(colortex5, texelcoord, 0).x;
rfSlope = vec2((sideRefrNoise - 0.5) * 0.8, (sideRefrNoise - 0.5) * 1.2);
} else if (biome_beach > 0.01 && biome_beach >= biome_ocean) {
float rfwx = rfWorldPos.x * WATER_WAVE_SCALE;
float rfwz = rfWorldPos.z * WATER_WAVE_SCALE;
float rfzOff1 = sin(rfwz * 0.21 + 3.7) * 2.5 + sin(rfwz * 0.53 + 1.2) * 1.3;
float rfzOff2 = sin(rfwz * 0.37 + 5.1) * 1.8 + sin(rfwz * 0.71 + 2.8) * 1.1;
float rfzOff3 = sin(rfwz * 0.62 + 0.9) * 1.2 + sin(rfwz * 0.89 + 4.3) * 0.8;
float rfH = clamp(RF_SMAX_10B(RF_WAVE_10B((rfwx * 0.8 + rfzOff1 - rft) / 6.2832), RF_WAVE_10B((rfwx * 1.8 + rfzOff2 - rft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
rfH += RF_WAVE_10B((rfwx * 4.0 + rfzOff3 - rft * 2.2) / 6.2832) * 0.15 * rfH;
float rfwxp = (rfWorldPos.x + rfEps) * WATER_WAVE_SCALE;
float rfHx = clamp(RF_SMAX_10B(RF_WAVE_10B((rfwxp * 0.8 + rfzOff1 - rft) / 6.2832), RF_WAVE_10B((rfwxp * 1.8 + rfzOff2 - rft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
rfHx += RF_WAVE_10B((rfwxp * 4.0 + rfzOff3 - rft * 2.2) / 6.2832) * 0.15 * rfHx;
float rfwzp = (rfWorldPos.z + rfEps) * WATER_WAVE_SCALE;
float rfzOff1z = sin(rfwzp * 0.21 + 3.7) * 2.5 + sin(rfwzp * 0.53 + 1.2) * 1.3;
float rfzOff2z = sin(rfwzp * 0.37 + 5.1) * 1.8 + sin(rfwzp * 0.71 + 2.8) * 1.1;
float rfzOff3z = sin(rfwzp * 0.62 + 0.9) * 1.2 + sin(rfwzp * 0.89 + 4.3) * 0.8;
float rfHz = clamp(RF_SMAX_10B(RF_WAVE_10B((rfwx * 0.8 + rfzOff1z - rft) / 6.2832), RF_WAVE_10B((rfwx * 1.8 + rfzOff2z - rft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
rfHz += RF_WAVE_10B((rfwx * 4.0 + rfzOff3z - rft * 2.2) / 6.2832) * 0.15 * rfHz;
rfSlope = vec2(rfHx - rfH, rfHz - rfH) / rfEps;
} else {

#define RF_HASH(p) fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453)
vec3 rfsp1 = vec3(rfWorldPos.xz * WATER_WAVE_SCALE * 0.4, rft * 0.5);
vec3 rfsi1 = floor(rfsp1); vec3 rfsf1 = fract(rfsp1);
rfsf1 = rfsf1 * rfsf1 * (3.0 - 2.0 * rfsf1);
float rfsn1 = mix(mix(mix(RF_HASH(rfsi1), RF_HASH(rfsi1+vec3(1,0,0)), rfsf1.x),
mix(RF_HASH(rfsi1+vec3(0,1,0)), RF_HASH(rfsi1+vec3(1,1,0)), rfsf1.x), rfsf1.y),
mix(mix(RF_HASH(rfsi1+vec3(0,0,1)), RF_HASH(rfsi1+vec3(1,0,1)), rfsf1.x),
mix(RF_HASH(rfsi1+vec3(0,1,1)), RF_HASH(rfsi1+vec3(1,1,1)), rfsf1.x), rfsf1.y), rfsf1.z);
vec3 rfsp2 = vec3(rfWorldPos.xz * WATER_WAVE_SCALE * 0.9, rft * 1.2) + vec3(17.0);
vec3 rfsi2 = floor(rfsp2); vec3 rfsf2 = fract(rfsp2);
rfsf2 = rfsf2 * rfsf2 * (3.0 - 2.0 * rfsf2);
float rfsn2 = mix(mix(mix(RF_HASH(rfsi2), RF_HASH(rfsi2+vec3(1,0,0)), rfsf2.x),
mix(RF_HASH(rfsi2+vec3(0,1,0)), RF_HASH(rfsi2+vec3(1,1,0)), rfsf2.x), rfsf2.y),
mix(mix(RF_HASH(rfsi2+vec3(0,0,1)), RF_HASH(rfsi2+vec3(1,0,1)), rfsf2.x),
mix(RF_HASH(rfsi2+vec3(0,1,1)), RF_HASH(rfsi2+vec3(1,1,1)), rfsf2.x), rfsf2.y), rfsf2.z);
vec3 rfsp3 = vec3(rfWorldPos.xz * WATER_WAVE_SCALE * 1.8, rft * 2.0) + vec3(31.0);
vec3 rfsi3 = floor(rfsp3); vec3 rfsf3 = fract(rfsp3);
rfsf3 = rfsf3 * rfsf3 * (3.0 - 2.0 * rfsf3);
float rfsn3 = mix(mix(mix(RF_HASH(rfsi3), RF_HASH(rfsi3+vec3(1,0,0)), rfsf3.x),
mix(RF_HASH(rfsi3+vec3(0,1,0)), RF_HASH(rfsi3+vec3(1,1,0)), rfsf3.x), rfsf3.y),
mix(mix(RF_HASH(rfsi3+vec3(0,0,1)), RF_HASH(rfsi3+vec3(1,0,1)), rfsf3.x),
mix(RF_HASH(rfsi3+vec3(0,1,1)), RF_HASH(rfsi3+vec3(1,1,1)), rfsf3.x), rfsf3.y), rfsf3.z);
#undef RF_HASH
float rfwx = (rfsn1 - 0.5) * 0.5 + (rfsn2 - 0.5) * 0.3 + (rfsn3 - 0.5) * 0.2;
float rfwz = (rfsn2 - 0.5) * 0.5 + (rfsn3 - 0.5) * 0.3 + (rfsn1 - 0.5) * 0.2;
rfSlope = vec2(rfwx, rfwz) * 0.8;
}
#undef RF_WAVE_10B
#undef RF_WAVE_RAW_10B
#undef RF_SMAX_10B

float rfBiomeFactor = max(waveBiome, 0.5);
float rfDist = max(length(rfViewPos), 1.0);

float refrFadeStart = mix(30.0, 60.0, smoothSwamp);
float refrFadeEnd = mix(80.0, 120.0, smoothSwamp);
float refrDistFade = 1.0 - smoothstep(refrFadeStart, refrFadeEnd, rfDist);
float refrBase = (biome_beach > 0.01) ? 18.0 : mix(14.0, 22.0, smoothSwamp);
float refrPx = refrBase * rfBiomeFactor / max(rfDist * 0.02, 0.5);
ivec2 refrCoord = texelcoord + ivec2(rfSlope * refrPx);
refrCoord = clamp(refrCoord, ivec2(0), ivec2(viewWidth - 1.0, viewHeight - 1.0));
float refrDepth = texelFetch(depthtex1, refrCoord, 0).r;
if (refrDepth > depth0 && refrDistFade > 0.01) {
vec3 refrOpaque = texelFetch(colortex0, refrCoord, 0).rgb;
vec4 refrTrans = texelFetch(colortex7, refrCoord, 0);
vec3 refrColor = refrTrans.a > 0.001 ? refrOpaque * (1.0 - refrTrans.a) + refrTrans.rgb : refrOpaque;
color = mix(color, refrColor, 0.95 * refrDistFade);
}
}
#endif
#endif
#endif

preSpecularColor = color;

vec3 waterTintCol = vec3(0.0);
float waterTintStr = 0.0;
if ((isWater || isDhWater) && isWaterOnly && isEyeInWater != 1) {
vec3 biomeWaterT = biomeWaterColor(sunAngle, biome_beach, biome_swamp, biome_jungle, biome_snowy, biome_arid);
vec3 defaultBlueT = vec3(0.0, 66.0, 102.0) / 255.0;
float hasBiomeT = max(max(biome_swamp, biome_jungle), max(biome_snowy, biome_arid));
waterTintCol = mix(defaultBlueT, biomeWaterT, clamp(hasBiomeT, 0.0, 1.0));
float tintLumT = dot(waterTintCol, vec3(0.299, 0.587, 0.114));
waterTintCol = mix(vec3(tintLumT), waterTintCol, 2.0);
waterTintCol = max(waterTintCol, vec3(0.0));
float skyDimT = mix(0.05, 1.0, texelFetch(colortex1, texelcoord, 0).b);
waterTintCol *= skyDimT;

waterTintStr = 0.0;
}

float waterEffectScale = 1.0;
if ((isWater || isDhWater) && transAlpha > WATER_OPACITY + 0.02) {
float particleCover = clamp((transAlpha - WATER_OPACITY) / (1.0 - WATER_OPACITY), 0.0, 1.0);
waterEffectScale *= 1.0 - particleCover;
}

#ifdef WATER_REFLECTIONS_ENABLED
if (isWater && isWaterOnly && isEyeInWater != 1) {
if (depth0 < 1.0) {
vec3 viewPos;
if (isVoxyWater) {
viewPos = getVoxyWaterViewPos(texcoord, depth0);
} else {
vec3 screenPos = vec3(texcoord, depth0);
viewPos = ilv_screenToView(screenPos);
}
vec3 waterWorldN = decodedWorldNormal;
bool isSideWater = (waterWorldN.y < 0.5);
if (isSideWater) waterWorldN = vec3(0.0, 1.0, 0.0);
waterWorldN = normalize(mix(vec3(0.0, 1.0, 0.0), waterWorldN, 0.05));
vec3 normal = normalize(mat3(gbufferModelView) * waterWorldN);

vec2 waveOffset = vec2(0.0);
#ifdef WATER_WAVES_ENABLED
{
ivec2 tcMax = ivec2(viewWidth - 1.0, viewHeight - 1.0);
ivec2 tcL = clamp(texelcoord + ivec2(-1, 0), ivec2(0), tcMax);
ivec2 tcR = clamp(texelcoord + ivec2( 1, 0), ivec2(0), tcMax);
ivec2 tcU = clamp(texelcoord + ivec2(0, -1), ivec2(0), tcMax);
ivec2 tcD = clamp(texelcoord + ivec2(0,  1), ivec2(0), tcMax);
float whL = texelFetch(colortex5, tcL, 0).x;
float whR = texelFetch(colortex5, tcR, 0).x;
float whU = texelFetch(colortex5, tcU, 0).x;
float whD = texelFetch(colortex5, tcD, 0).x;
vec2 hGrad = vec2(whR - whL, whD - whU);
float waveDist = max(length(viewPos), 1.0);
float distScale = 1.0 / waveDist;
waveOffset = vec2(0.0);
}
#endif

TimeWeightsSimple reflTS = getTimeWeightsSimple(sunAngle);
float reflDay = reflTS.day + reflTS.twilight;
float reflNight = reflTS.night + reflTS.blueHour;
float reflTOD = mix(0.15, 1.0, reflDay) + reflNight * 0.85;
float reflectionStrength = mix(WATER_REFLECTION_AMOUNT, max(WATER_REFLECTION_AMOUNT, 0.85), reflNight) * reflTOD * WATER_OPACITY;
float crestReflectCut = 1.0;
reflectionStrength *= crestReflectCut;
reflectionStrength *= waterEffectScale;
float waterSkylight = waterSurfaceSkylight;

vec2 lmcoord = vec2(0.0, waterSkylight);

vec3 reflDirView = reflect(normalize(viewPos), normal);
vec3 reflDirWorld = mat3(gbufferModelViewInverse) * reflDirView;

float ssrDist = length(viewPos);
float ssrFade = 1.0 - smoothstep(float(SSR_RENDER_DISTANCE) * 0.8, float(SSR_RENDER_DISTANCE), ssrDist);

if (isSideWater) {
vec3 sideNormalWorld = decodedWorldNormal;
sideNormalWorld.y = 0.0;
float sideNLen = length(sideNormalWorld);
if (sideNLen < 0.001) sideNormalWorld = vec3(0.0, 0.0, 1.0);
else sideNormalWorld /= sideNLen;

vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec3 viewDirWorld = normalize(worldPos);
vec3 sideReflWorld = reflect(viewDirWorld, sideNormalWorld);
sideReflWorld.y += 0.15;

float sideNoise = reflData.x;
sideReflWorld.x += (sideNoise - 0.5) * 0.12;
sideReflWorld.y += (sideNoise - 0.5) * 0.08;
sideReflWorld = normalize(sideReflWorld);

vec3 sideSkyCol;
if (sideReflWorld.y > 0.0) {
vec3 sideReflView = normalize(mat3(gbufferModelView) * sideReflWorld);
sideSkyCol = ilv_getSkyColor(sideReflView, worldPos + cameraPosition, false) * 0.8;
} else {
vec3 horizDir = normalize(vec3(sideReflWorld.x, 0.001, sideReflWorld.z));
vec3 horizView = normalize(mat3(gbufferModelView) * horizDir);
sideSkyCol = ilv_getSkyColor(horizView, worldPos + cameraPosition, false) * 0.8;
}

float sideSkyGate = smoothstep(13.0 / 15.0, 14.0 / 15.0, waterSkylight);

vec3 sideNormalPerturbed = sideNormalWorld;
sideNormalPerturbed.y += (sideNoise - 0.5) * 0.1;
sideNormalPerturbed.x += (sideNoise - 0.5) * 0.05;
sideNormalPerturbed = normalize(sideNormalPerturbed);
vec3 sideNormalView = normalize(mat3(gbufferModelView) * sideNormalPerturbed);
vec2 sideWaveOffset = vec2((sideNoise - 0.5) * 0.008, (sideNoise - 0.5) * 0.015);
vec3 preRefl = color;
ilv_addReflection(color, viewPos, sideNormalView, lmcoord, reflectionStrength * max(ssrFade, 0.001), sideWaveOffset, waterTintCol, waterTintStr);
vec3 ssrDeltaLocal = color - preRefl;
color = preRefl;
color += ssrDeltaLocal * WATER_BRIGHTNESS;
float sideTextureSpecSignal = smoothstep(0.05, 0.75, clamp(glassTint.b, 0.0, 1.0));
float sideLowSkyTextureBoost = 1.0 - smoothstep(3.0 / 15.0, 10.0 / 15.0, waterSkylight);
float sideReflLuma = dot(max(ssrDeltaLocal, vec3(0.0)), vec3(0.299, 0.587, 0.114));
vec3 sideTextureReflLight = max(ssrDeltaLocal * (1.8 + sideLowSkyTextureBoost * 1.1), vec3(sideReflLuma));
color += sideTextureReflLight * sideTextureSpecSignal * (0.14 + sideLowSkyTextureBoost * 0.40) * WATER_BRIGHTNESS;
float ssrHit = clamp(length(ssrDeltaLocal) * 5.0, 0.0, 1.0);
vec3 sideSkyFallback = mix(color, sideSkyCol, reflectionStrength * sideSkyGate);
color = mix(sideSkyFallback, color, ssrHit);

{
vec3 sideN = normalize(mat3(gbufferModelView) * sideNormalWorld);
sideN = normalize(sideN + vec3((sideNoise - 0.5) * 0.5, (sideNoise - 0.5) * 0.5, 0.0));
vec3 sideL = normalize(shadowLightPosition);
vec3 sideV = normalize(-viewPos);
vec3 sideH = normalize(sideV + sideL);
float sideNdotH = max(dot(sideN, sideH), 0.0);
float sideSpec = smoothstep(0.95, 0.99, sideNdotH);
TimeWeightsSimple sideSpecTS = getTimeWeightsSimple(sunAngle);
float sideDayFactor = sideSpecTS.day + sideSpecTS.twilight * 0.7;
float sideSunsetBoost = 1.0 + sideSpecTS.twilight * 2.0;
float sideGlow = sideSpec * sideDayFactor * waterSkylight * sideSunsetBoost;
vec3 sideGlowCol = mix(vec3(1.0, 0.95, 0.85),
vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), sideSpecTS.twilight);
vec3 sideShadowScenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec4 sideShadowClip = shadowProjection * shadowModelView * vec4(sideShadowScenePos, 1.0);
vec3 sideShadowDistorted = distortShadowClipPos(sideShadowClip.xyz / sideShadowClip.w);
vec3 sideShadowScreen = sideShadowDistorted * 0.5 + 0.5;
float sideShadow = 0.0;
if (sideShadowScreen.x > 0.0 && sideShadowScreen.x < 1.0 && sideShadowScreen.y > 0.0 && sideShadowScreen.y < 1.0) {
float sideShadowDepth = texture(shadowtex0, sideShadowScreen.xy).r;
sideShadow = step(sideShadowScreen.z - 0.001, sideShadowDepth);
}
preSpecularColor = color;
color += sideGlowCol * sideGlow * WATER_SPECULAR_INTENSITY * sideShadow * waterEffectScale * mix(1.0, 0.1, smoothSwamp);
}
} else {

vec3 preRefl = color;
ilv_addReflection(color, viewPos, normal, lmcoord, reflectionStrength * max(ssrFade, 0.001), waveOffset, waterTintCol, waterTintStr);
vec3 reflDelta = color - preRefl;
float wb = WATER_BRIGHTNESS;
color = preRefl + reflDelta * wb;
float textureSpecSignal = smoothstep(0.05, 0.75, clamp(glassTint.b, 0.0, 1.0));
float lowSkyTextureBoost = 1.0 - smoothstep(3.0 / 15.0, 10.0 / 15.0, waterSkylight);
float reflLuma = dot(max(reflDelta, vec3(0.0)), vec3(0.299, 0.587, 0.114));
vec3 textureReflLight = max(reflDelta * (2.2 + lowSkyTextureBoost * 1.4), vec3(reflLuma));
color += textureReflLight * textureSpecSignal * (0.20 + lowSkyTextureBoost * 0.55) * WATER_BRIGHTNESS;

vec3 topL = normalize(shadowLightPosition);
vec3 topV = normalize(-viewPos);
vec3 topWorldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
float topWt = frameTimeCounter * WATER_WAVE_SPEED * 0.5;

#define SPEC_HASH(p) fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453)
vec3 sp1 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 0.4, topWt * 0.25);
vec3 si1 = floor(sp1); vec3 sf1 = fract(sp1);
sf1 = sf1 * sf1 * (3.0 - 2.0 * sf1);
float sn1 = mix(mix(mix(SPEC_HASH(si1), SPEC_HASH(si1+vec3(1,0,0)), sf1.x),
mix(SPEC_HASH(si1+vec3(0,1,0)), SPEC_HASH(si1+vec3(1,1,0)), sf1.x), sf1.y),
mix(mix(SPEC_HASH(si1+vec3(0,0,1)), SPEC_HASH(si1+vec3(1,0,1)), sf1.x),
mix(SPEC_HASH(si1+vec3(0,1,1)), SPEC_HASH(si1+vec3(1,1,1)), sf1.x), sf1.y), sf1.z);
vec3 sp2 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 0.9, topWt * 0.6) + vec3(17.0);
vec3 si2 = floor(sp2); vec3 sf2 = fract(sp2);
sf2 = sf2 * sf2 * (3.0 - 2.0 * sf2);
float sn2 = mix(mix(mix(SPEC_HASH(si2), SPEC_HASH(si2+vec3(1,0,0)), sf2.x),
mix(SPEC_HASH(si2+vec3(0,1,0)), SPEC_HASH(si2+vec3(1,1,0)), sf2.x), sf2.y),
mix(mix(SPEC_HASH(si2+vec3(0,0,1)), SPEC_HASH(si2+vec3(1,0,1)), sf2.x),
mix(SPEC_HASH(si2+vec3(0,1,1)), SPEC_HASH(si2+vec3(1,1,1)), sf2.x), sf2.y), sf2.z);
vec3 sp3 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 1.8, topWt * 1.0) + vec3(31.0);
vec3 si3 = floor(sp3); vec3 sf3 = fract(sp3);
sf3 = sf3 * sf3 * (3.0 - 2.0 * sf3);
float sn3 = mix(mix(mix(SPEC_HASH(si3), SPEC_HASH(si3+vec3(1,0,0)), sf3.x),
mix(SPEC_HASH(si3+vec3(0,1,0)), SPEC_HASH(si3+vec3(1,1,0)), sf3.x), sf3.y),
mix(mix(SPEC_HASH(si3+vec3(0,0,1)), SPEC_HASH(si3+vec3(1,0,1)), sf3.x),
mix(SPEC_HASH(si3+vec3(0,1,1)), SPEC_HASH(si3+vec3(1,1,1)), sf3.x), sf3.y), sf3.z);
#undef SPEC_HASH

float wx = (sn1 - 0.5) * 0.5 + (sn2 - 0.5) * 0.3 + (sn3 - 0.5) * 0.2;
float wz = (sn2 - 0.5) * 0.5 + (sn3 - 0.5) * 0.3 + (sn1 - 0.5) * 0.2;

vec3 topN = normalize(normal + mat3(gbufferModelView) * vec3(wx * 1.0, 0.0, wz * 1.0));
vec3 topH = normalize(topV + topL);
float topNdotH = max(dot(topN, topH), 0.0);
TimeWeightsSimple topTS = getTimeWeightsSimple(sunAngle);
float topDayFactor = topTS.day + topTS.twilight * 0.7;
float topSunsetBoost = 1.0 + topTS.twilight * 2.0;
float topSpec = smoothstep(0.95, 0.99, topNdotH);
float topGlow = topSpec * topDayFactor * waterSkylight * topSunsetBoost;
vec3 topGlowCol = mix(vec3(1.0, 0.95, 0.85),
vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), topTS.twilight);

vec3 topShadowScenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec4 topShadowClip = shadowProjection * shadowModelView * vec4(topShadowScenePos, 1.0);
vec3 topShadowDistorted = distortShadowClipPos(topShadowClip.xyz / topShadowClip.w);
vec3 topShadowScreen = topShadowDistorted * 0.5 + 0.5;
float topShadow = 0.0;
if (topShadowScreen.x > 0.0 && topShadowScreen.x < 1.0 && topShadowScreen.y > 0.0 && topShadowScreen.y < 1.0) {
float topShadowDepth = texture(shadowtex0, topShadowScreen.xy).r;
topShadow = step(topShadowScreen.z - 0.001, topShadowDepth);
}
float topGlowAmt = topGlow * WATER_SPECULAR_INTENSITY * 0.4 * topShadow * waterEffectScale * mix(1.0, 0.1, smoothSwamp);
preSpecularColor = color;
color += topGlowCol * topGlowAmt;
}
}
}

if (isDhWater && isWaterOnly && isEyeInWater != 1) {

vec3 dhWorldNormal = vec3(
reflData.z * 2.0 - 1.0,
reflData.w * 2.0 - 1.0,
0.0
);
dhWorldNormal.z = sqrt(max(1.0 - dhWorldNormal.x * dhWorldNormal.x - dhWorldNormal.y * dhWorldNormal.y, 0.0));
vec3 dhNormalView = normalize(mat3(gbufferModelView) * dhWorldNormal);

vec3 dhScreenPos = vec3(texcoord, dhDepth);
vec3 dhNdc = dhScreenPos * 2.0 - 1.0;
vec4 dhViewH = dhProjectionInverse * vec4(dhNdc, 1.0);
vec3 dhViewPos = dhViewH.xyz / dhViewH.w;
vec3 dhWorldPos = (gbufferModelViewInverse * vec4(dhViewPos, 1.0)).xyz + cameraPosition;
float dhViewDist = length(dhViewPos);

vec3 dhV = normalize(-dhViewPos);
float dhNdotV = max(dot(dhNormalView, dhV), 0.0);
float dhFresnelRaw = 1.0 - dhNdotV;
dhFresnelRaw *= dhFresnelRaw;
dhFresnelRaw *= dhFresnelRaw;
float dhFresnel = mix(0.6, 1.0, dhFresnelRaw);

TimeWeightsSimple dhReflTS = getTimeWeightsSimple(sunAngle);
float dhReflDay = dhReflTS.day + dhReflTS.twilight;
float dhReflNight = dhReflTS.night + dhReflTS.blueHour;
float dhReflTOD = mix(0.15, 1.0, dhReflDay) + dhReflNight * 0.85;
float dhReflStrength = mix(WATER_REFLECTION_AMOUNT, max(WATER_REFLECTION_AMOUNT, 0.85), dhReflNight) * dhReflTOD * WATER_OPACITY;
dhReflStrength *= dhFresnel;
dhReflStrength *= waterEffectScale;
dhReflStrength = clamp(dhReflStrength, 0.0, 1.0);

float dhDistDamp = 1.0 / (1.0 + dhViewDist * 0.005);
float dhWt = frameTimeCounter * WATER_WAVE_SPEED;
vec2 dhWp = dhWorldPos.xz * WATER_WAVE_SCALE * 2.5;
float dhWaveX = sin(dhWp.x * 3.0 + dhWp.y * 0.3 + dhWt * 1.5) * 0.5
+ sin(dhWp.x * 5.0 + dhWp.y * 0.5 + dhWt * 2.2) * 0.3
+ sin(dhWp.x * 8.0 + dhWp.y * 0.2 + dhWt * 3.0) * 0.2;
float dhWaveZ = sin(dhWp.x * 0.3 + dhWp.y * 3.0 + dhWt * 1.3) * 0.5
+ sin(dhWp.x * 0.5 + dhWp.y * 5.0 + dhWt * 2.0) * 0.3;
dhWaveX *= dhDistDamp;
dhWaveZ *= dhDistDamp;

vec3 dhReflDirWorld = reflect(normalize(dhWorldPos - cameraPosition), dhWorldNormal);
dhReflDirWorld.x += dhWaveX * 0.01;
dhReflDirWorld.z += dhWaveZ * 0.01;
dhReflDirWorld = normalize(dhReflDirWorld);

vec3 dhReflDirView = reflect(normalize(dhViewPos), dhNormalView);
dhReflDirView.x += dhWaveX * 0.008;
dhReflDirView.z += dhWaveZ * 0.008;
dhReflDirView = normalize(dhReflDirView);

bool dhSsrHit = false;
vec3 dhSsrColor = vec3(0.0);
{

float dhDither = ilv_bayer8(gl_FragCoord.xy);

float dhStartOffset = dhViewDist * 0.015 + 0.25;
vec3 dhMarchStart = dhViewPos + dhNormalView * dhStartOffset;

float dhStepLen = 1.0 + dhDither * 1.5;
vec3 dhStepDir = dhReflDirView;
vec3 dhMarchPos = dhMarchStart;

for (int i = 0; i < 32; i++) {
dhMarchPos += dhStepDir * dhStepLen;

vec4 dhMarchClip = dhProjection * vec4(dhMarchPos, 1.0);
if (dhMarchClip.w <= 0.0) break;
vec3 dhMarchScreen = (dhMarchClip.xyz / dhMarchClip.w) * 0.5 + 0.5;

if (dhMarchScreen.x < 0.0 || dhMarchScreen.x > 1.0 ||
dhMarchScreen.y < 0.0 || dhMarchScreen.y > 1.0) break;

float dhSceneDepth = texture(dhDepthTex, dhMarchScreen.xy).r;
if (hasValidDHDepth(dhSceneDepth)) {
float dhMarchLinear = linearizeDepthDH(dhMarchScreen.z);
float dhSceneLinear = linearizeDepthDH(dhSceneDepth);
float dhDelta = dhMarchLinear - dhSceneLinear;

if (dhDelta > 0.0 && dhDelta < dhStepLen * 2.0) {
float dhEdgeX = smoothstep(0.0, 0.08, min(dhMarchScreen.x, 1.0 - dhMarchScreen.x));
float dhEdgeY = smoothstep(0.0, 0.08, min(dhMarchScreen.y, 1.0 - dhMarchScreen.y));
float dhEdge = dhEdgeX * dhEdgeY;
if (dhEdge > 0.01) {
dhSsrColor = texture(colortex0, dhMarchScreen.xy).rgb;
dhSsrHit = true;

dhSsrColor *= dhEdge;
dhSsrHit = (dhEdge > 0.3);
}
break;
}
}

dhStepLen *= 1.22;
}
}

vec3 dhSkyColor = ilv_getSkyColor(dhReflDirWorld, dhWorldPos, false);
float dhSkyAngle = fract(sunAngle);
float dhSkyDimSunset = smoothstep(0.46, 0.54, dhSkyAngle);
float dhSkyBrightBase = mix(1.0, 0.6, dhSkyDimSunset);
float dhNightBoost = smoothstep(0.54, 0.59, dhSkyAngle) * (1.0 - smoothstep(0.92, 0.96, dhSkyAngle));
dhSkyBrightBase = mix(dhSkyBrightBase, 1.0, dhNightBoost);
dhSkyColor *= dhSkyBrightBase * 1.5;
float dhSkLum = dot(dhSkyColor, vec3(0.299, 0.587, 0.114));
dhSkyColor = mix(vec3(dhSkLum), dhSkyColor, WATER_SATURATION);

vec3 dhReflColor = dhSsrHit ? dhSsrColor : dhSkyColor;

color = mix(color, dhReflColor, dhReflStrength * WATER_BRIGHTNESS);

{
vec3 dhL = normalize(shadowLightPosition);

float dhSpecDamp = dhDistDamp * dhDistDamp;

float dhSpecWt = frameTimeCounter * WATER_WAVE_SPEED * 0.5 * dhSpecDamp;

#define DH_SPEC_HASH(p) fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453)
vec3 dhsp1 = vec3(dhWorldPos.xz * WATER_WAVE_SCALE * 0.4, dhSpecWt * 0.25);
vec3 dhsi1 = floor(dhsp1); vec3 dhsf1 = fract(dhsp1);
dhsf1 = dhsf1 * dhsf1 * (3.0 - 2.0 * dhsf1);
float dhsn1 = mix(mix(mix(DH_SPEC_HASH(dhsi1), DH_SPEC_HASH(dhsi1+vec3(1,0,0)), dhsf1.x),
mix(DH_SPEC_HASH(dhsi1+vec3(0,1,0)), DH_SPEC_HASH(dhsi1+vec3(1,1,0)), dhsf1.x), dhsf1.y),
mix(mix(DH_SPEC_HASH(dhsi1+vec3(0,0,1)), DH_SPEC_HASH(dhsi1+vec3(1,0,1)), dhsf1.x),
mix(DH_SPEC_HASH(dhsi1+vec3(0,1,1)), DH_SPEC_HASH(dhsi1+vec3(1,1,1)), dhsf1.x), dhsf1.y), dhsf1.z);
vec3 dhsp2 = vec3(dhWorldPos.xz * WATER_WAVE_SCALE * 0.9, dhSpecWt * 0.6) + vec3(17.0);
vec3 dhsi2 = floor(dhsp2); vec3 dhsf2 = fract(dhsp2);
dhsf2 = dhsf2 * dhsf2 * (3.0 - 2.0 * dhsf2);
float dhsn2 = mix(mix(mix(DH_SPEC_HASH(dhsi2), DH_SPEC_HASH(dhsi2+vec3(1,0,0)), dhsf2.x),
mix(DH_SPEC_HASH(dhsi2+vec3(0,1,0)), DH_SPEC_HASH(dhsi2+vec3(1,1,0)), dhsf2.x), dhsf2.y),
mix(mix(DH_SPEC_HASH(dhsi2+vec3(0,0,1)), DH_SPEC_HASH(dhsi2+vec3(1,0,1)), dhsf2.x),
mix(DH_SPEC_HASH(dhsi2+vec3(0,1,1)), DH_SPEC_HASH(dhsi2+vec3(1,1,1)), dhsf2.x), dhsf2.y), dhsf2.z);
#undef DH_SPEC_HASH

float dhwx = ((dhsn1 - 0.5) * 0.5 + (dhsn2 - 0.5) * 0.3) * dhSpecDamp;
float dhwz = ((dhsn2 - 0.5) * 0.5 + (dhsn1 - 0.5) * 0.3) * dhSpecDamp;
vec3 dhSpecN = normalize(dhNormalView + mat3(gbufferModelView) * vec3(dhwx, 0.0, dhwz));
vec3 dhH = normalize(dhV + dhL);
float dhNdotH = max(dot(dhSpecN, dhH), 0.0);
float dhSpec = smoothstep(0.95, 0.99, dhNdotH);
float dhDayFactor = dhReflTS.day + dhReflTS.twilight * 0.7;
float dhSunsetBoost = 1.0 + dhReflTS.twilight * 2.0;
float dhGlow = dhSpec * dhDayFactor * dhSunsetBoost;
vec3 dhGlowCol = mix(vec3(1.0, 0.95, 0.85),
vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), dhReflTS.twilight);
color += dhGlowCol * dhGlow * WATER_SPECULAR_INTENSITY * waterEffectScale * mix(1.0, 0.1, smoothSwamp);
}
}

#endif

if (isIceBlock && depthAll < 0.9999) {
vec3 iceViewPos;
bool iceIsVoxy = (maskData.a > 0.999);
if (iceIsVoxy) {
vec4 iceClip = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
iceViewPos = iceClip.xyz / iceClip.w;
} else {
iceViewPos = ilv_screenToView(vec3(texcoord, depth0));
}
vec3 iceWorldNormal = decodedWorldNormal;
if (length(iceWorldNormal) < 0.01) iceWorldNormal = vec3(0.0, 1.0, 0.0);
vec3 iceNormalView = normalize(mat3(gbufferModelView) * iceWorldNormal);

float iceSkylight = texelFetch(colortex1, texelcoord, 0).b;
float iceReflStr = 0.3 * smoothstep(0.1, 0.8, iceSkylight);

vec3 preIceRefl = color;
ilv_addReflection(color, iceViewPos, iceNormalView, vec2(0.0, iceSkylight), iceReflStr, vec2(0.0), vec3(1.0), 0.0);

vec3 iceWorldPos = (gbufferModelViewInverse * vec4(iceViewPos, 1.0)).xyz + cameraPosition;
float iceWt = frameTimeCounter * 0.5;
float iceWaveX = sin(iceWorldPos.x * 2.5 + iceWorldPos.z * 0.3 + iceWt * 1.2) * 0.5
+ sin(iceWorldPos.x * 4.0 + iceWorldPos.z * 0.8 + iceWt * 1.8) * 0.3;
float iceWaveZ = sin(iceWorldPos.z * 2.5 + iceWorldPos.x * 0.3 + iceWt * 1.0) * 0.5
+ sin(iceWorldPos.z * 4.0 + iceWorldPos.x * 0.6 + iceWt * 1.5) * 0.3;

vec3 icePerturbedNormal = iceNormalView;
icePerturbedNormal.x += iceWaveX * 0.03;
icePerturbedNormal.z += iceWaveZ * 0.03;
icePerturbedNormal = normalize(icePerturbedNormal);

vec3 iceL = normalize(shadowLightPosition);
vec3 iceV = normalize(-iceViewPos);
vec3 iceH = normalize(iceV + iceL);
float iceNdotH = max(dot(icePerturbedNormal, iceH), 0.0);
float iceSpec = smoothstep(0.985, 0.995, iceNdotH);
TimeWeightsSimple iceTS = getTimeWeightsSimple(sunAngle);
float iceDayFactor = iceTS.day + iceTS.twilight * 0.7;
float iceSunsetBoost = 1.0 + iceTS.twilight * 2.0;
float iceGlow = iceSpec * iceDayFactor * iceSkylight * iceSunsetBoost;
vec3 iceGlowCol = mix(vec3(1.0, 0.95, 0.85),
vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), iceTS.twilight);

vec3 iceScenePos = (gbufferModelViewInverse * vec4(iceViewPos, 1.0)).xyz;
vec4 iceShadowClip = shadowProjection * shadowModelView * vec4(iceScenePos, 1.0);
vec3 iceShadowDist = distortShadowClipPos(iceShadowClip.xyz / iceShadowClip.w);
vec3 iceShadowScreen = iceShadowDist * 0.5 + 0.5;
float iceShadow = 0.0;
if (iceShadowScreen.x > 0.0 && iceShadowScreen.x < 1.0 && iceShadowScreen.y > 0.0 && iceShadowScreen.y < 1.0) {
iceShadow = step(iceShadowScreen.z - 0.001, texture(shadowtex0, iceShadowScreen.xy).r);
}
color += iceGlowCol * iceGlow * WATER_SPECULAR_INTENSITY * iceShadow;
}

#if defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)
#ifndef WATER_REFLECTION_DEBUG

if (false && (isWater || isDhWater) && isWaterOnly && isEyeInWater != 1) {
float wDist;
if (isDhWater) {
vec4 dhClip = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, dhDepth * 2.0 - 1.0, 1.0);
wDist = -dhClip.z / dhClip.w;
} else {
vec4 wClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
wDist = -wClip.z / wClip.w;
}

float fogDensity = mix(0.025, 2.0, biome_swamp);
float fogMax = mix(0.95, 1.0, biome_swamp);
float uwFogAmount = 1.0 - exp(-wDist * fogDensity);
uwFogAmount = clamp(uwFogAmount, 0.0, fogMax);

if (uwFogAmount > 0.001) {
float uwAngle = fract(sunAngle);
float uwTwilight = smoothstep(0.40, 0.48, uwAngle) * smoothstep(0.55, 0.48, uwAngle)
+ smoothstep(0.94, 1.0, uwAngle) + smoothstep(0.06, 0.0, uwAngle);
if (uwTwilight > 0.001) {
float uwLum = dot(color, vec3(0.299, 0.587, 0.114));
color = mix(color, vec3(uwLum), uwTwilight * 0.6);
}
vec3 beachTint = biomeWaterColor(sunAngle, 1.0, 0.0, 0.0, 0.0, 0.0);
vec3 swampTint = vec3(0.04, 0.08, 0.02);
vec3 uwWaterTint = mix(beachTint, swampTint, biome_swamp);
color *= mix(vec3(1.0), uwWaterTint * 3.0, uwFogAmount);
color += uwWaterTint * uwFogAmount;
}
}

#endif
#endif

#if defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)
#ifndef WATER_REFLECTION_DEBUG

#ifdef WATER_FOAM_ENABLED
if ((isWater || isDhWater) && isWaterOnly && waveBiome > 0.01 && beachWaveHeight > 0.001 && isEyeInWater != 1) {
vec4 wvClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
float wvDist = max(-wvClip.z / wvClip.w, 1.0);
int sampleOff = clamp(int(wvDist * 0.15), 2, 20);
float whL = texelFetch(colortex5, texelcoord + ivec2(-sampleOff, 0), 0).x;
float whR = texelFetch(colortex5, texelcoord + ivec2( sampleOff, 0), 0).x;
float slope = abs(whR - whL);
float wallMask = 0.0;
color *= mix(vec3(1.0), vec3(0.75, 0.88, 0.90), wallMask);
}
#endif

bool glassInFront = (depth0 < depth1 - 0.0001) && !entityInFront;
bool hasGlassLayer = (glassTint.a > 0.55 && glassTint.a < 0.65) && glassInFront && (transAlpha > 0.001);
#ifdef GLASS_FILTER_ENABLED
if (hasGlassLayer && !entityInFront) {
vec3 tint = glassTint.rgb;
float maxTint = max(max(tint.r, tint.g), tint.b);
if (maxTint > 0.01) {
tint /= maxTint;
float sat = GLASS_FILTER_SATURATION;
float tintLumGF = dot(tint, vec3(0.299, 0.587, 0.114));
tint = mix(vec3(tintLumGF), tint, sat);
tint = min(tint, vec3(1.0));
float str = GLASS_FILTER_STRENGTH;
float enforce = GLASS_FILTER_ENFORCEMENT;
color = mix(color, color * tint, str * enforce);
}
}
#endif

if (hasGlassLayer && !entityInFront && glassInFront && isEyeInWater != 1) {
float glassOpaqueDepth = texelFetch(depthtex1, texelcoord, 0).r;
if (glassOpaqueDepth < 0.9999) {
vec4 glassClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, glassOpaqueDepth * 2.0 - 1.0, 1.0);
vec3 glassViewP = glassClip.xyz / glassClip.w;
vec3 glassBehindWorld = (gbufferModelViewInverse * vec4(glassViewP, 1.0)).xyz + cameraPosition;
{
float glassWaterFade = smoothstep(float(SEA_LEVEL_OFFSET), float(SEA_LEVEL_OFFSET) - 2.0, glassBehindWorld.y);
if (glassWaterFade > 0.001) {
vec3 glassViewDir = normalize(glassViewP);
vec3 glassNormal = normalize(mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0));
vec3 glassReflDir = reflect(glassViewDir, glassNormal);
vec3 glassReflWorld = mat3(gbufferModelViewInverse) * glassReflDir;
vec3 glassSkyRefl = ilv_getSkyColor(glassReflDir, glassBehindWorld, false) * WATER_SKY_REFLECTION;
float glassFresnel = 1.0 - abs(dot(normalize(-glassViewP), glassNormal));
glassFresnel = glassFresnel * glassFresnel * glassFresnel;
float glassReflStr = mix(0.2, 0.8, glassFresnel) * WATER_OPACITY * glassWaterFade;
color = mix(color, glassSkyRefl, glassReflStr);
}
}
}
}

#if defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)
#ifndef WATER_REFLECTION_DEBUG
bool isSideFaceWater = (reflData.y > 0.9 && reflData.y < 0.99);

float foamWaterY = 0.0;
{
vec3 fwvPos;
if (isVoxyWater) {
fwvPos = getVoxyWaterViewPos(texcoord, depth0);
} else {
vec4 fc = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
fwvPos = fc.xyz / fc.w;
}
foamWaterY = ((gbufferModelViewInverse * vec4(fwvPos, 1.0)).xyz + cameraPosition).y;
}
bool foamAtSeaLevel = (foamWaterY > float(SEA_LEVEL_OFFSET) - 1.5 && foamWaterY < float(SEA_LEVEL_OFFSET) + 1.5);
if ((isWater || isDhWater) && isWaterOnly && isEyeInWater != 1 && waterEffectScale > 0.01 && !isSideFaceWater && foamAtSeaLevel) {
float foamAmount = smoothstep(0.5, 1.0, reflData.x);
vec3 foamColor = vec3(WATER_FOAM_COLOR_R, WATER_FOAM_COLOR_G, WATER_FOAM_COLOR_B) * WATER_FOAM_INTENSITY;

TimeWeightsSimple foamTS = getTimeWeightsSimple(sunAngle);
float foamAngle = fract(sunAngle);
float foamNightDim = smoothstep(0.50, 0.60, foamAngle) * (1.0 - smoothstep(0.92, 0.98, foamAngle));
float foamBright = mix(1.0, 0.55, foamNightDim);
foamColor *= foamBright;

vec3 foamWP;
if (isVoxyWater) {
foamWP = (gbufferModelViewInverse * vec4(getVoxyWaterViewPos(texcoord, depth0), 1.0)).xyz;
} else {
vec4 fwClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
foamWP = (gbufferModelViewInverse * vec4(fwClip.xyz / fwClip.w, 1.0)).xyz;
}
vec3 foamViewDir = normalize(foamWP);
vec3 foamSunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
float foamSunDot = max(dot(foamViewDir, foamSunDir), 0.0);
float foamSunsetBoost = foamTS.twilight * 2.0 + foamTS.day * 0.5;
float foamSunBoost = 1.0 + pow(foamSunDot, 4.0) * foamSunsetBoost;
foamColor *= foamSunBoost;
color = mix(color, foamColor, foamAmount * waterEffectScale * (1.0 - smoothSwamp));
}
#endif
#endif

if ((isWater || isDhWater) && isWaterOnly && isEyeInWater != 1 && waterEffectScale > 0.01 && !isSideFaceWater && foamAtSeaLevel && smoothSwamp < 0.99) {

vec3 specViewPos;
if (isVoxyWater) {
specViewPos = getVoxyWaterViewPos(texcoord, depth0);
} else {
vec4 svClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
specViewPos = svClip.xyz / svClip.w;
}
vec3 specWorldPos = (gbufferModelViewInverse * vec4(specViewPos, 1.0)).xyz + cameraPosition;
vec2 swp = floor(specWorldPos.xz * 16.0) / 16.0;

float st = frameTimeCounter * WATER_WAVE_SPEED;

float ct = st * 0.15;
vec3 cPos3D = vec3(swp.x, 0.0, swp.y) * 0.35;

float cA = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = cPos3D;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
cA += abs(noise3D(p * freq + ct * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
cA = 1.0 - cA / total;
}
float cB = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = cPos3D + 5.0;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
cB += abs(noise3D(p * freq + ct * 1.15 * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
cB = 1.0 - cB / total;
}
float waveSpec = min(cA, cB);
waveSpec = pow(waveSpec, 2.0) * 2.5;
waveSpec = max(waveSpec - 0.15, 0.0) * (1.0 / 0.85);

float specNoise = noise3D(vec3(swp * 4.0, ct * 0.5)) * 0.4;
waveSpec += specNoise;

waveSpec = floor(waveSpec * 5.0 + 0.5) / 5.0;
waveSpec = max(waveSpec, 0.0);

vec3 specHorizon = getTimelineHorizonColor(sunAngle, 0.2);

TimeWeightsSimple specTS = getTimeWeightsSimple(sunAngle);
float specBright = specTS.day * 1.0 + specTS.twilight * 0.8 + (specTS.night + specTS.blueHour) * 0.1;

float specDist = length(specViewPos);
float specDistFade = 1.0 - smoothstep(80.0, 200.0, specDist);

float specSkylight = texelFetch(colortex1, texelcoord, 0).b;
float specSkyGate = smoothstep(0.5, 0.8, specSkylight);

vec3 specWorldDir = normalize(specWorldPos - cameraPosition);
vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
float sunDot = max(dot(specWorldDir, sunDirWorld), 0.0);
float sunsetBoost = specTS.twilight * 3.0 + specTS.day * 1.0;
float sunBoost = 1.0 + pow(sunDot, 4.0) * sunsetBoost;

vec3 skySpec = specHorizon * waveSpec * specBright * specDistFade * specSkyGate * 0.07 * sunBoost * (1.0 - smoothSwamp);
color += skySpec * waterEffectScale;
}

ssrTaaOutput = vec4(0.0);
#ifdef MATERIAL_REFLECTIONS_ENABLED
{
bool isHandPixelMat = isHandEarly;
bool isEntityPixelMat = isEntityOrHand;
if (isMaterialRefl && isEyeInWater != 1 && !isHandPixelMat && !isEntityPixelMat) {
if (depth0 < 1.0) {
float mnx = reflData.z * 2.0 - 1.0;
float mny = reflData.w * 2.0 - 1.0;
float mnz = sqrt(max(1.0 - mnx * mnx - mny * mny, 0.0));
vec3 worldNormal = vec3(mnx, mny, mnz);
vec3 matNormal = normalize(mat3(gbufferModelView) * worldNormal);

float matRoughness = clamp(reflData.x, 0.0, 1.0);
float matMetalness = 0.0;
#ifdef PBR_ENABLED
pbr_unpackFromColortex5(reflData, matRoughness, matMetalness);
#endif
float matSmoothness = 1.0 - sqrt(clamp(matRoughness, 0.0, 1.0));

vec3 screenPos = vec3(texcoord, depth0);
vec3 matViewPos = ilv_screenToView(screenPos);
float matSkylight = texelFetch(colortex1, texelcoord, 0).b;

vec3 V = normalize(-matViewPos);
float NdotV = max(dot(matNormal, V), 0.0);

float fresnel = 1.0 - NdotV;
float fresnelFactor = (1.0 - matSmoothness) * 0.7;
float smoothnessFresnel = max(fresnel - fresnelFactor, 0.0) / max(1.0 - fresnelFactor, 0.001);
smoothnessFresnel = smoothnessFresnel * smoothnessFresnel;
smoothnessFresnel = max(smoothnessFresnel * sqrt(max(matSmoothness, 0.0)) - ilv_bayer8(gl_FragCoord.xy) * 0.01, 0.0);

float matDayFactor = smoothstep(0.02, 0.10, fract(sunAngle)) * smoothstep(0.48, 0.40, fract(sunAngle));
float matSkyTimeGate = smoothstep(7.0 / 15.0, 12.0 / 15.0, matSkylight);
float materialAmount = clamp(MATERIAL_REFLECTION_AMOUNT, 0.0, 1.0);
float thresholdReflectance = max(smoothnessFresnel, matSmoothness * 0.35);
float dielectricReflectance = materialAmount * MATERIAL_REFLECTION_FRESNEL;
dielectricReflectance *= thresholdReflectance;
dielectricReflectance *= mix(1.0, mix(0.1, 1.0, matDayFactor), matSkyTimeGate);
float metalReflectance = max(dielectricReflectance, materialAmount * (0.45 + 0.55 * matSmoothness));
float matReflStr = mix(dielectricReflectance, metalReflectance, matMetalness);

float matSsrDist = length(matViewPos);
float matSsrFade = 1.0 - smoothstep(float(SSR_RENDER_DISTANCE) * 0.8, float(SSR_RENDER_DISTANCE), matSsrDist);
matReflStr *= matSsrFade;

if (matReflStr > 0.001) {

vec3 preSSRColor = color;
ilv_addMaterialReflection(color, matViewPos, matNormal, matReflStr, matSkylight, matRoughness);

vec3 ssrDelta = color - preSSRColor;

color = preSSRColor;
ssrTaaOutput = vec4(ssrDelta, 1.0);
}

}
}
}
#endif

#if defined(PUDDLES_ENABLED)
{
float rs = clamp(rainStrength, 0.0, 1.0);
float puddleStrength = clamp(PUDDLES_STRENGTH, 0.0, 1.0) * rs;

float puddleDepth2 = depth2;
bool isHandHeld = isHandEarly;
if (!isWater && !isEntityOrHand && !isHandHeld && puddleStrength > 0.0001 && isEyeInWater != 1) {
float puddleDepth = puddleDepth2;
float pxSkylight = texelFetch(colortex1, texelcoord, 0).b;
float pxOutlineMask = texelFetch(colortex1, texelcoord, 0).r;
bool isLeafPixel = (pxOutlineMask < 0.1);
if (puddleDepth < 0.9999 && pxSkylight > 0.95 && !isLeafPixel) {
vec2 px = vec2(1.0 / max(viewWidth, 1.0), 1.0 / max(viewHeight, 1.0));
vec3 puddleViewPos = ilv_screenToView(vec3(texcoord, puddleDepth));
float dR = texelFetch(depthtex2, ivec2(texelcoord + ivec2(1, 0)), 0).r;
float dL = texelFetch(depthtex2, ivec2(texelcoord + ivec2(-1, 0)), 0).r;
float dU = texelFetch(depthtex2, ivec2(texelcoord + ivec2(0, -1)), 0).r;
float dD = texelFetch(depthtex2, ivec2(texelcoord + ivec2(0, 1)), 0).r;
vec3 vR = ilv_screenToView(vec3(texcoord + vec2(px.x, 0.0), dR));
vec3 vL = ilv_screenToView(vec3(texcoord - vec2(px.x, 0.0), dL));
vec3 vU = ilv_screenToView(vec3(texcoord - vec2(0.0, px.y), dU));
vec3 vD = ilv_screenToView(vec3(texcoord + vec2(0.0, px.y), dD));
vec3 pdx = vR - vL;
vec3 pdy = vD - vU;
vec3 viewNormal = normalize(cross(pdx, pdy));
vec3 upV = normalize(gbufferModelView[1].xyz);
float upness = clamp(abs(dot(viewNormal, upV)), 0.0, 1.0);
float flatMask = smoothstep(0.85, 0.98, upness);

vec3 scenePos = (gbufferModelViewInverse * vec4(puddleViewPos, 1.0)).xyz;
vec3 puddleWorldPos = scenePos + cameraPosition;
float n = smoothChunkNoise(puddleWorldPos.xz * 0.12);
float patches = smoothstep(0.62, 0.86, n);
patches = pow(patches, 1.35);
float outer = smoothstep(0.56, 0.82, n);
float inner = patches;
float edgeBand = clamp(outer - inner, 0.0, 1.0);

float topSkyGate = smoothstep(0.90, 0.98, pxSkylight);
float puddleMask = puddleStrength * flatMask * patches * topSkyGate;
if (puddleMask > 0.0001) {
float wetDarken = mix(1.0, 0.80, puddleMask);
wetDarken *= mix(1.0, 0.82, edgeBand * puddleStrength);
color *= wetDarken;
color += vec3(0.03) * edgeBand * puddleStrength;

vec3 reflNormal = normalize(mix(viewNormal, upV, 0.75));
float t = float(frameCounter) * 0.016;
float r1 = sin(puddleWorldPos.x * 18.0 + t * 6.0);
float r2 = sin(puddleWorldPos.z * 21.0 - t * 5.2);
float r3 = sin((puddleWorldPos.x + puddleWorldPos.z) * 14.0 + t * 7.4);
float r4 = sin((puddleWorldPos.x - puddleWorldPos.z) * 32.0 - t * 8.1);
float ripple = (r1 + r2 + 0.65 * r3 + 0.35 * r4) / 3.0;
float rippleAmp = 0.014 * rs * puddleStrength;
vec3 tangent = normalize(cross(upV, vec3(0.0, 0.0, 1.0)));
if (length(tangent) < 0.01) tangent = normalize(cross(upV, vec3(1.0, 0.0, 0.0)));
vec3 bitangent = normalize(cross(upV, tangent));
reflNormal = normalize(reflNormal + tangent * (ripple * rippleAmp) + bitangent * (r2 * rippleAmp * 0.35));
float reflStr = puddleMask * clamp(PUDDLES_REFLECTION_STRENGTH, 0.0, 1.0);
reflStr *= mix(0.85, 1.20, patches);
reflStr *= (1.0 - 0.05 * abs(ripple) * rs);
ilv_addReflection(color, puddleViewPos, reflNormal, vec2(0.0, 1.0), reflStr, vec2(0.0), vec3(1.0), 0.0);
}
}
}
}
#endif

#if defined(WALL_RUNOFF_ENABLED)
{
float rs = clamp(rainStrength, 0.0, 1.0);
float runoffStrength = clamp(WALL_RUNOFF_STRENGTH, 0.0, 1.0) * rs;
if (!isWater && runoffStrength > 0.0001 && isEyeInWater != 1) {
float pxSkylight = texelFetch(colortex1, texelcoord, 0).b;
float outdoor = smoothstep(0.15, 0.60, pxSkylight);
if (outdoor > 0.001) {
float roDepth = texelFetch(depthtex2, texelcoord, 0).r;
if (roDepth < 0.9999) {
vec2 px = vec2(1.0 / max(viewWidth, 1.0), 1.0 / max(viewHeight, 1.0));
vec3 roViewPos = ilv_screenToView(vec3(texcoord, roDepth));
float rdR = texelFetch(depthtex2, ivec2(texelcoord + ivec2(1, 0)), 0).r;
float rdL = texelFetch(depthtex2, ivec2(texelcoord + ivec2(-1, 0)), 0).r;
float rdU = texelFetch(depthtex2, ivec2(texelcoord + ivec2(0, -1)), 0).r;
float rdD = texelFetch(depthtex2, ivec2(texelcoord + ivec2(0, 1)), 0).r;
vec3 roVR = ilv_screenToView(vec3(texcoord + vec2(px.x, 0.0), rdR));
vec3 roVL = ilv_screenToView(vec3(texcoord - vec2(px.x, 0.0), rdL));
vec3 roVU = ilv_screenToView(vec3(texcoord - vec2(0.0, px.y), rdU));
vec3 roVD = ilv_screenToView(vec3(texcoord + vec2(0.0, px.y), rdD));
vec3 roDx = roVR - roVL;
vec3 roDy = roVD - roVU;
vec3 roViewNormal = normalize(cross(roDx, roDy));
vec3 roUpV = normalize(gbufferModelView[1].xyz);
float roUpness = clamp(abs(dot(roViewNormal, roUpV)), 0.0, 1.0);
float vertical = 1.0 - smoothstep(0.30, 0.70, roUpness);

vec3 roScenePos = (gbufferModelViewInverse * vec4(roViewPos, 1.0)).xyz;
vec3 roWorldPos = roScenePos + cameraPosition;

float laneLayout = runoffNoise(roWorldPos.xz * 0.90);
float lanes = roWorldPos.x * 2.2 + roWorldPos.z * 1.7 + laneLayout * 2.0;
float laneCell = fract(lanes);
float laneCore = 1.0 - abs(laneCell - 0.5) * 2.0;
laneCore = pow(clamp(laneCore, 0.0, 1.0), 6.0);

float t = float(frameCounter) * 0.016 * clamp(WALL_RUNOFF_SPEED, 0.0, 5.0);
float flow = fract(roWorldPos.y * 1.25 - t + laneLayout);
float drops = smoothstep(0.10, 0.00, flow) + smoothstep(0.90, 1.00, flow);
drops = clamp(drops, 0.0, 1.0);

float mask = runoffStrength * outdoor * vertical * laneCore;
mask *= mix(0.55, 1.0, drops);
mask = clamp(mask, 0.0, 1.0);

if (mask > 0.0001) {
color *= mix(1.0, 0.86, mask);
color += vec3(0.05, 0.06, 0.07) * mask;
}
}
}
}
}
#endif

#endif
#endif

if (isEyeInWater != 1 && (isWater || isDhWater || isVoxyWater)) {
vec4 cloudReapply = texture(colortex8, texcoord);
float cloudReapplyBlend = clamp(1.0 - cloudAlpha, 0.0, 1.0);
if (cloudReapplyBlend > 0.001) {
color = color * (1.0 - cloudReapplyBlend) + cloudReapply.rgb;
}
}

#ifdef SHADOWS_ENABLED
if (isEyeInWater != 1 && (isWater || isDhWater) && !isVoxyWater) {
vec4 waterViewClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
vec3 waterViewPos = waterViewClip.xyz / waterViewClip.w;
vec3 waterScenePos = (gbufferModelViewInverse * vec4(waterViewPos, 1.0)).xyz;
vec4 waterShadowClip = shadowProjection * shadowModelView * vec4(waterScenePos, 1.0);
vec3 waterShadowNDC = distortShadowClipPos(waterShadowClip.xyz);
vec3 waterShadowUV = waterShadowNDC * 0.5 + 0.5;
waterShadowUV.z -= 0.001;
float waterShadow = 1.0;
if (waterShadowUV.x > 0.0 && waterShadowUV.x < 1.0 &&
waterShadowUV.y > 0.0 && waterShadowUV.y < 1.0 &&
waterShadowUV.z > 0.0 && waterShadowUV.z < 1.0) {
waterShadow = step(waterShadowUV.z, texture(shadowtex0, waterShadowUV.xy).r);
}

waterShadow = mix(1.0, waterShadow, shadowEdgeFade(waterShadowUV));

waterShadow = mix(1.0, waterShadow, SHADOW_OPACITY);
color *= waterShadow;
}
#endif

if (isEyeInWater != 1) {

bool isEmissivePixel = (maskData.g > 0.5);
float emissiveFogResist = isEmissivePixel ? 0.15 : 1.0;

float sharedTransLuma = dot(max(translucentData.rgb, vec3(0.0)), vec3(0.299, 0.587, 0.114));
float beaconHazeMask =
smoothstep(0.001, 0.035, transAlpha) *
smoothstep(0.12, 0.45, sharedTransLuma) *
(isGlassC17 ? 0.0 : 1.0) *
((waterData.y > 0.5 || isWater || isDhWater || isVoxyWater || isMaterialRefl) ? 0.0 : 1.0);

#if defined(HAZE_FOG_ENABLED) || defined(NETHER_FOG_ENABLED)
{
vec4 haze = max(texture(colortex10, texcoord), vec4(0.0));

if (blockEntityPixel) haze = vec4(0.0);
haze *= 1.0 - beaconHazeMask;
#ifdef HAZE_FOG_ENABLED
if (!isForcedNetherBiome(biome)) {
float hazeVxD = texture(vxDepthTexTrans, texcoord).r;
bool hazeHasVoxy = (hazeVxD > 0.00001 && hazeVxD < 0.9999) || (maskData.a > 0.999);
bool hazeIsTrueSky = isSky && !hasValidDHDepth(dhDepth) && !hazeHasVoxy;
if (hazeIsTrueSky) haze = vec4(0.0);
}
#endif
if (haze.a > 0.001) {
float hazeA = haze.a * emissiveFogResist;
color = haze.rgb * emissiveFogResist + color * (1.0 - hazeA);
}
}
#endif

#if defined(ATMO_FOG_ENABLED) || defined(UNDERWATER_FOG_ENABLED) || defined(CAVE_FOG_ENABLED)
{
vec4 atmoFog = max(texture(colortex9, texcoord), vec4(0.0));
atmoFog *= cloudAlpha;

if (atmoFog.a > 0.001) {
float atmoA = atmoFog.a * emissiveFogResist;
color = atmoFog.rgb * emissiveFogResist + color * (1.0 - atmoA);
}
}
#endif

#ifdef WEATHER_FOG_ENABLED
{
vec4 weatherFog = max(texture(colortex11, texcoord), vec4(0.0));
if (weatherFog.a > 0.001) {
float weatherA = weatherFog.a * emissiveFogResist;
color = weatherFog.rgb * emissiveFogResist + color * (1.0 - weatherA);
}
}
#endif

#ifdef TORNADO_LEAVES_ENABLED
{
float tlDepth = texture(depthtex1, texcoord).r;
bool tlSkyPixel = tlDepth >= 0.999999;
float tlMinSkyLight = 10.0 / 15.0;
float tlSkyLight = texture(colortex1, texcoord).b;
float tlPlayerSkyLight = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
bool tlAllowLeaves = tlSkyLight > tlMinSkyLight || (tlSkyPixel && tlPlayerSkyLight > tlMinSkyLight);
if (tlAllowLeaves) {
vec4 tlClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, tlDepth * 2.0 - 1.0, 1.0);
vec3 tlView = tlClip.xyz / tlClip.w;
vec3 tlWorld = (gbufferModelViewInverse * vec4(tlView, 1.0)).xyz;
vec3 tlDir   = normalize(tlWorld);
float tlDist = length(tlWorld);
vec4 leafHit = render_tornado_leaves(cameraPosition, tlDir, tlDist, frameTimeCounter);
color = mix(color, leafHit.rgb, leafHit.a);
vec4 freeLeaf = render_free_leaves(cameraPosition, tlDir, tlDist, frameTimeCounter);
color = mix(color, freeLeaf.rgb, freeLeaf.a);
}
}
#endif
}

if (isEyeInWater == 1) {
float uwtDepth = texture(depthtex0, texcoord).r;
float uwtVxDepth = texture(vxDepthTexTrans, texcoord).r;
bool uwtHasVoxyDepth = (maskData.a > 0.999) && (uwtVxDepth > 0.00001 && uwtVxDepth < 0.9999);
bool uwtHasSceneDepth = (uwtDepth < 1.0) || uwtHasVoxyDepth;
if (uwtHasSceneDepth) {
float uwtEmissive = texture(colortex1, texcoord).g;

float emissiveReduce = (uwtEmissive > 0.5) ? 0.15 : 1.0;
vec3 uwtViewPos;
if (uwtHasVoxyDepth && uwtDepth >= 0.9999) {
vec4 uwtClip = vec4(texcoord * 2.0 - 1.0, uwtVxDepth * 2.0 - 1.0, 1.0);
vec4 uwtView = vxProjInv * uwtClip;
uwtViewPos = uwtView.xyz / uwtView.w;
} else {
vec4 uwtClip = vec4(texcoord * 2.0 - 1.0, uwtDepth * 2.0 - 1.0, 1.0);
vec4 uwtView = gbufferProjectionInverse * uwtClip;
uwtViewPos = uwtView.xyz / uwtView.w;
}
float uwtDist = length(uwtViewPos);
float tintAmount = smoothstep(0.0, 40.0, uwtDist) * 0.6 * emissiveReduce;
vec3 uwTintColor = vec3(UNDERWATER_FOG_R, UNDERWATER_FOG_G, UNDERWATER_FOG_B);
float lumUW = dot(color, vec3(0.299, 0.587, 0.114));
vec3 tintedUW = lumUW * uwTintColor;
color = mix(color, tintedUW, tintAmount);
}
}

#if defined(ATMO_FOG_ENABLED) || defined(UNDERWATER_FOG_ENABLED)
if (isEyeInWater == 1) {
vec4 atmoFog = max(texture(colortex9, texcoord), vec4(0.0));
if (atmoFog.a > 0.001) {
float uwEmissive = texture(colortex1, texcoord).g;
float emissiveBypass = uwEmissive * 0.5 * (1.0 - smoothstep(0.3, 0.6, atmoFog.a));
float uwFogAlpha = atmoFog.a * (1.0 - emissiveBypass);
color = atmoFog.rgb * (uwFogAlpha / max(atmoFog.a, 0.001)) + color * (1.0 - uwFogAlpha);
}
}
#endif

#ifdef UNDERWATER_FOG_ENABLED
if (isEyeInWater == 1) {
vec4 cloudData = texture(colortex8, texcoord);
float underwaterCloudBlend = clamp(1.0 - cloudAlpha, 0.0, 1.0);
float uwDepthBelow = float(SEA_LEVEL_OFFSET) - cameraPosition.y;
float uwBandFade = smoothstep(0.5, 6.0, uwDepthBelow);
underwaterCloudBlend *= (1.0 - uwBandFade);
cloudData.rgb *= (1.0 - uwBandFade);
if (underwaterCloudBlend > 0.001 && !entityInFront && !particleOverSky) {
color += cloudData.rgb * underwaterCloudBlend;
}
}
#endif

#if !defined(NETHER_SHADER) && !defined(END_SHADER)
{
vec2 sunUV = getSunScreenUV();
float fsAngle = fract(sunAngle);
float fsDayVis = smoothstep(0.02, 0.08, fsAngle) * smoothstep(0.48, 0.42, fsAngle);
float fsSunrise = smoothstep(0.0, 0.03, fsAngle) * smoothstep(0.10, 0.06, fsAngle);
float fsSunset  = smoothstep(0.40, 0.44, fsAngle) * smoothstep(0.48, 0.46, fsAngle);
float fsVis = fsDayVis + max(fsSunrise, fsSunset) * 0.5;

if (sunUV.x > -0.5 && fsVis > 0.001) {
vec2 delta = texcoord - sunUV;
delta.x *= viewWidth / viewHeight;
float dist = length(delta);

float noonFactor = 1.0 - smoothstep(0.0, 0.25, abs(fsAngle - 0.25));
float radiusScale = mix(1.0, 1.8, noonFactor);

float r = SUN_GLOW_RADIUS * 0.08 * radiusScale;
float glow = exp(-dist * dist / (r * r));

float r2 = SUN_GLOW_RADIUS * 0.2 * radiusScale;
float halo = 1.0 / (1.0 + pow(dist / r2, 4.0));

float combined = glow * 0.35 + halo * 0.08;
combined *= fsVis * SUN_GLOW_INTENSITY;
if (isEyeInWater == 1) combined *= 0.0;

bool postIsSky = isSky && !hasValidDHDepth(dhDepth);
if (!postIsSky) {
#ifdef WEATHER_FOG_ENABLED
float weatherAlpha = max(texture(colortex11, texcoord), vec4(0.0)).a;
combined *= weatherAlpha * 0.5;
#else
combined = 0.0;
#endif
}
combined *= smoothstep(0.0, 0.15, max(rainStrength, biome_swamp));

color += vec3(1.0) * combined;
}
}
#endif

#if !defined(NETHER_SHADER) && !defined(END_SHADER)
{
vec3 moonDirView = normalize(moonPosition);
vec3 moonPosView = moonDirView * 1000.0;
vec4 moonClip = gbufferProjection * vec4(moonPosView, 1.0);
if (moonClip.w > 0.00001) {
vec2 moonUV = (moonClip.xy / moonClip.w) * 0.5 + 0.5;
float moonAngle = fract(sunAngle);
float moonVis = smoothstep(0.52, 0.58, moonAngle) * (1.0 - smoothstep(0.94, 0.98, moonAngle));

if (moonVis > 0.001) {
vec2 moonDelta = texcoord - moonUV;
moonDelta.x *= viewWidth / viewHeight;
float moonDist = length(moonDelta);

float mr = SUN_GLOW_RADIUS * 0.12;
float moonGlow = exp(-moonDist * moonDist / (mr * mr));

float mr2 = SUN_GLOW_RADIUS * 0.35;
float moonHalo = 1.0 / (1.0 + pow(moonDist / mr2, 4.0));

float moonCombined = moonGlow * 0.25 + moonHalo * 0.04;
moonCombined *= moonVis;
if (isEyeInWater == 1) moonCombined = 0.0;
bool postIsSkyMoon = isSky && !hasValidDHDepth(dhDepth);
if (!postIsSkyMoon) moonCombined = 0.0;

color += vec3(0.7, 0.8, 1.0) * moonCombined;
}
}
}
#endif

#if !defined(NETHER_SHADER) && !defined(END_SHADER)
{
if (!isSkylessWorldHeuristic()) {
ivec2 sunTexel = ivec2(gl_FragCoord.xy);
float sunDepthMC = texelFetch(depthtex0, sunTexel, 0).x;
float sunDepthDH = texelFetch(dhDepthTex, sunTexel, 0).x;
bool sunIsSky = (sunDepthMC >= 0.9999 && !hasValidDHDepth(sunDepthDH));
if (sunIsSky && fogAmount > 0.05) {
float sunGateAngle = fract(sunAngle);
float sunTexGate = smoothstep(0.0, 0.04, sunGateAngle) * (1.0 - smoothstep(0.50, 0.54, sunGateAngle));
float savedLum = dot(savedSunColor, vec3(0.299, 0.587, 0.114));
float foggedLum = dot(color, vec3(0.299, 0.587, 0.114));
float sunStrength = smoothstep(0.15, 0.4, savedLum - foggedLum);
sunStrength *= 1.0 - smoothstep(0.3, 0.8, fogAmount);
sunStrength *= sunTexGate;
color = mix(color, savedSunColor, sunStrength);
}
}
}
#endif

if (isEyeInWater == 1) {
float uwEmissiveFlag = texture(colortex1, texcoord).g;
float uwTintStr = (uwEmissiveFlag > 0.5) ? 0.05 : 1.0;
vec3 uwScreenTint = vec3(UNDERWATER_FOG_R, UNDERWATER_FOG_G, UNDERWATER_FOG_B);
vec3 uwOrigColor = color;

color.r *= mix(0.55, 0.75, uwScreenTint.r);
color.g *= mix(0.75, 0.95, uwScreenTint.g);

float uwLum = dot(color, vec3(0.299, 0.587, 0.114));
color.b = mix(color.b, max(color.b, uwLum * 0.6), 0.3);

color = mix(vec3(uwLum), color, 0.85);

color = mix(uwOrigColor, color, uwTintStr);
}

if (darknessFactor > 0.01) {
float darkPulse = darknessLightFactor;

float emFlag = texture(colortex1, texcoord).g;
float emResist = (emFlag > 0.5) ? 0.4 : 0.0;
float darkenAmount = darkPulse * (1.0 - emResist);
color *= 1.0 - darkenAmount * 0.85;

vec2 vignetteUV = texcoord * 2.0 - 1.0;
float vignette = dot(vignetteUV, vignetteUV);
color *= 1.0 - vignette * darkPulse * 0.5;
}

if (blindness > 0.01) {
float blindDepth = texture(depthtex0, texcoord).r;
if (blindDepth < 0.9999) {
vec4 blindClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, blindDepth * 2.0 - 1.0, 1.0);
float blindDist = length(blindClip.xyz / blindClip.w);
float blindFog = smoothstep(3.0, 6.0, blindDist) * blindness;
color = mix(color, vec3(0.0), blindFog);
} else {

color = mix(color, vec3(0.0), blindness);
}
}

if (nightVision > 0.01) {
float nvLum = dot(color, vec3(0.299, 0.587, 0.114));

float nvBoost = (1.0 - smoothstep(0.0, 0.5, nvLum)) * 0.6;
color *= 1.0 + nvBoost * nightVision;

color.g *= 1.0 + 0.05 * nightVision;
}

if (smoothSwamp > 0.01 && isEyeInWater != 1 && depth0 < 0.9999 && (isWater || isDhWater)) {

float swampTerrainY;
bool swampHasTerrain = (depth1 < 0.9999);
if (swampHasTerrain) {
vec4 stClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth1 * 2.0 - 1.0, 1.0);
vec3 stView = stClip.xyz / stClip.w;
swampTerrainY = ((gbufferModelViewInverse * vec4(stView, 1.0)).xyz + cameraPosition).y;
} else {

swampTerrainY = float(SEA_LEVEL_OFFSET) - 10.0;
}
float swampDepthBelow = float(SEA_LEVEL_OFFSET) - swampTerrainY;
if (swampDepthBelow > 0.0) {

float swampFogAmount = smoothstep(0.0, 4.0, swampDepthBelow);

float swampMudMask = smoothstep(0.5, 0.8, transAlpha);
swampFogAmount *= (1.0 - swampMudMask);
vec3 swampFogCol = vec3(0.06, 0.12, 0.05);
color = mix(color, swampFogCol, swampFogAmount * smoothSwamp);
}
}

if (smoothSwamp > 0.01 && isEyeInWater != 1 && depth0 < 0.9999 && (isWater || isDhWater)) {
float swampTexBright = glassTint.r;
float swampTexOverlay = smoothstep(0.1, 0.5, swampTexBright);
if (swampTexOverlay > 0.001) {

vec4 stpClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
vec3 stpViewPos = stpClip.xyz / stpClip.w;
vec3 stpWorldPos = (gbufferModelViewInverse * vec4(stpViewPos, 1.0)).xyz + cameraPosition;
float stpAft = frameTimeCounter;

float stpCycle = 16.0;
float stpGridScale = 0.05;
vec2 stpGridPos = stpWorldPos.xz * stpGridScale;
vec2 stpCellBase = floor(stpGridPos);
float stpPatchMask = 0.0;
for (int gx = -1; gx <= 1; gx++) {
for (int gy = -1; gy <= 1; gy++) {
vec2 cell = stpCellBase + vec2(float(gx), float(gy));

float h1 = fract(sin(dot(cell, vec2(213.7, 479.1))) * 28571.3);
float h2 = fract(sin(dot(cell, vec2(367.3, 151.9))) * 63841.7);
float h3 = fract(sin(dot(cell, vec2(523.1, 289.5))) * 91547.1);
float cellCycleId = floor((stpAft + h1 * stpCycle) / stpCycle);
float h4 = fract(sin(dot(vec2(cellCycleId, h1 * 100.0), vec2(213.7, 479.1))) * 28571.3);
float h5 = fract(sin(dot(vec2(cellCycleId, h2 * 100.0), vec2(367.3, 151.9))) * 63841.7);
float patchPhase = mod(stpAft + h1 * stpCycle, stpCycle) / stpCycle;
vec2 drift = vec2(h3 - 0.5, h1 - 0.5) * patchPhase * 0.4;
vec2 center = cell + vec2(0.2 + h4 * 0.6, 0.2 + h5 * 0.6) + drift;
vec2 delta = stpGridPos - center;
float angle = atan(delta.y, delta.x);
float deform = 1.0 + 0.2 * sin(angle * 3.0 + h3 * 6.28) + 0.1 * sin(angle * 5.0 + h1 * 6.28);
float dist = length(delta) * deform;
float maxRadius = 0.5;
float outerRadius = smoothstep(0.0, 0.35, patchPhase) * maxRadius;
float innerRadius = smoothstep(0.25, 0.90, patchPhase) * maxRadius * 1.3;
float outerMask = 1.0 - smoothstep(outerRadius * 0.4, outerRadius, dist);
float innerMask = smoothstep(innerRadius * 0.3, innerRadius, dist);
float patchShape = outerMask * innerMask;
float cellActive = step(0.35, h2);
stpPatchMask = max(stpPatchMask, patchShape * cellActive);
}
}

swampTexOverlay *= stpPatchMask;

vec3 stSpecWorldDir = normalize((gbufferModelViewInverse * vec4(stpViewPos, 1.0)).xyz);
vec3 stSunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
float stSunDot = max(dot(stSpecWorldDir, stSunDir), 0.0);
TimeWeightsSimple stTS = getTimeWeightsSimple(sunAngle);
float stDayFactor = stTS.day + stTS.twilight * 0.7;
float stSunBoost = pow(stSunDot, 4.0) * stDayFactor * 2.0;
vec3 swampTexCol = vec3(0.18, 0.25, 0.12) + vec3(0.15, 0.12, 0.05) * stSunBoost;
color = mix(color, swampTexCol, swampTexOverlay * smoothSwamp);
}
}

if (smoothSwamp > 0.01 && isEyeInWater != 1 && depth0 < 0.9999 && (isWater || isDhWater)) {
float rx = reflData.x;
float mudAmount = smoothstep(0.5, 1.0, rx);
if (mudAmount > 0.001) {
color = mix(color, color * vec3(0.55, 0.35, 0.15), mudAmount * smoothSwamp);
}
}

vec4 caveFogDebugEncoded = texelFetch(colortex13, texelcoord, 0);
float caveFogApplyOut = isForcedNetherBiome(biome) ? 0.0 : ((caveFogDebugEncoded.a > 1.0) ? (caveFogDebugEncoded.a - 1.0) : 0.0);
if (DEBUG_CAVE_FOG_DISTANCE_VIEW && caveFogApplyOut > 0.001) {
float dbgDepth0 = texture(depthtex0, texcoord).r;
float dbgDepth1 = texture(depthtex1, texcoord).r;
float dbgDepth  = max(dbgDepth0, dbgDepth1);
float caveDistDebug = 0.0;
if (dbgDepth < 0.9999) {
vec4 dbgClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, dbgDepth * 2.0 - 1.0, 1.0);
vec3 dbgView = dbgClip.xyz / dbgClip.w;
caveDistDebug = clamp(length(dbgView) / CAVE_FOG_MAX_DIST, 0.0, 1.0);
}
gl_FragData[0] = vec4(vec3(caveDistDebug), 1.0);
} else if (DEBUG_CAVE_FOG_ALPHA_VIEW && caveFogApplyOut > 0.001) {
gl_FragData[0] = vec4(vec3(caveFogApplyOut), 1.0);
} else {
gl_FragData[0] = vec4(color, cloudAlpha);
}

if (ssrTaaOutput.a < 0.5) {
ssrTaaOutput = (caveFogApplyOut > 0.001) ? vec4(0.0) : vec4(fogAmount, 0.0, 0.0, 0.0);
}
gl_FragData[1] = ssrTaaOutput;
}
