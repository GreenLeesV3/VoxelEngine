/* RENDERTARGETS: 0 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/depth_utils.glsl"
#include "/include/water_color.glsl"
#include "/include/ocean_waves.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex7;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;
uniform sampler2D dhDepthTex;
uniform sampler2D vxDepthTexTrans;

uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 dhProjectionInverse;
uniform mat4 vxProjInv;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex0;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 shadowLightPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float near;
uniform float sunAngle;
uniform float dhFarPlane;
uniform float dhNearPlane;

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

uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_savanna;
uniform float biome_beach;
uniform float biome_ocean;
uniform vec3 fogColor;
uniform vec3 skyColor;

in vec2 texcoord;

#ifdef CLOUDS_3D_ENABLED
#include "/include/volumetric_clouds.glsl"
#endif
#ifdef CLOUDS_VANILLA_ENABLED
#include "/include/vanilla_clouds.glsl"
#endif
#include "/include/ilv_reflections.glsl"
#include "/include/noise.glsl"

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

float pow4(float x) { return (x * x) * (x * x); }
float quartic_length_c0(vec2 v) { return sqrt(sqrt(pow4(v.x) + pow4(v.y))); }
vec3 distortShadowClipPos(vec3 pos) {
float factor = quartic_length_c0(pos.xy) + SHADOW_DISTORTION;
return vec3(pos.xy / factor, pos.z * SHADOW_DEPTH_SCALE);
}

void main() {
ivec2 texelcoord = ivec2(gl_FragCoord.xy);

vec4 opaqueData = texelFetch(colortex0, texelcoord, 0);
vec3 opaqueColor = opaqueData.rgb;
float cloudAlpha = opaqueData.a;

vec4 translucentData = texelFetch(colortex7, texelcoord, 0);
vec4 maskData = texelFetch(colortex1, texelcoord, 0);
vec4 glassTint = texelFetch(colortex4, texelcoord, 0);
vec4 reflData = texelFetch(colortex5, texelcoord, 0);

float depth0 = texelFetch(depthtex0, texelcoord, 0).r;
float depth1 = texelFetch(depthtex1, texelcoord, 0).r;
float dhDepth = texelFetch(dhDepthTex, texelcoord, 0).r;

float depth2 = texelFetch(depthtex2, texelcoord, 0).r;
bool isHandEarly = (depth0 < depth2 - 0.000001) && (abs(depth0 - depth1) < 0.000001);
float transAlpha = translucentData.a;
vec3 color = opaqueColor;

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

color = uwRefrColor;
transAlpha = 0.0;
}
}

bool opaqueIsEntity = (maskData.a > 0.3 && maskData.a < 0.7);
bool skipBehindEntity = opaqueIsEntity && (depth0 >= depth1 - 0.00005);
if (transAlpha > 0.001 && !isHandEarly && !skipBehindEntity) {
color = color * (1.0 - transAlpha) + translucentData.rgb;
}

vec3 rawGbufColor = color;

#ifdef GLASS_FILTER_ENABLED
if (glassTint.a > 0.55 && glassTint.a < 0.65) {
vec3 tint = glassTint.rgb;
float maxTint = max(max(tint.r, tint.g), tint.b);
if (maxTint > 0.01) {
tint /= maxTint;
float sat = GLASS_FILTER_SATURATION;
float tintLum = dot(tint, vec3(0.299, 0.587, 0.114));
tint = mix(vec3(tintLum), tint, sat);
float str = GLASS_FILTER_STRENGTH;
float enforce = GLASS_FILTER_ENFORCEMENT;
color = mix(color, color * tint, str * enforce);
}
}
#endif

#if defined(WATER_REFLECTIONS_ENABLED) || defined(MATERIAL_REFLECTIONS_ENABLED)

bool hasReflection = (reflData.z > 0.001 || reflData.w > 0.001) && !isHandEarly;

float nx = reflData.z * 2.0 - 1.0;
float ny = reflData.w * 2.0 - 1.0;
float nz = sqrt(max(1.0 - nx * nx - ny * ny, 0.0));
vec3 decodedWorldNormal = vec3(nx, ny, nz);
bool isHorizontalSurface = (decodedWorldNormal.y > 0.5);

bool isWaterTagged = (reflData.y > 0.9);

float voxyMarker = maskData.a;
bool isEntityOrHand = (voxyMarker > 0.01 && voxyMarker < 0.99) || isHandEarly;

bool isWater = hasReflection && isWaterTagged && !isEntityOrHand;
bool isVoxyLod = (voxyMarker > 0.999);
bool isVoxyWater = hasReflection && isWaterTagged && isVoxyLod && !isWater;
if (isVoxyWater) isWater = true;
bool isDhWater = hasReflection && isWaterTagged && !isWater && (depth0 >= 0.9999) && (dhDepth < 0.9999);
bool isMaterialRefl = hasReflection && !isWater && !isDhWater;

vec3 preSpecularColor = color;

float beachWaveHeight = reflData.x;
float beachWaveHeightSm = beachWaveHeight;
if (isWater || isDhWater) {
float whL1 = texelFetch(colortex5, texelcoord + ivec2(-1, 0), 0).x;
float whR1 = texelFetch(colortex5, texelcoord + ivec2( 1, 0), 0).x;
float whU1 = texelFetch(colortex5, texelcoord + ivec2(0, -1), 0).x;
float whD1 = texelFetch(colortex5, texelcoord + ivec2(0,  1), 0).x;
beachWaveHeightSm = (beachWaveHeight + whL1 + whR1 + whU1 + whD1) * 0.2;
}

#ifdef WATER_REFLECTION_DEBUG
if (isWater) color = vec3(1.0, 0.0, 1.0);
if (isDhWater) color = vec3(1.0, 1.0, 0.0);
if (isMaterialRefl) color = vec3(0.0, 1.0, 1.0);
#else

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

float waveBiome = max(biome_beach, biome_ocean);

#ifdef WATER_FOAM_ENABLED
if ((isWater || isDhWater) && isEyeInWater != 1) {
vec3 rfViewPos;
if (isDhWater || isVoxyWater) {
float rfDepthLOD = isDhWater ? dhDepth : depth0;
vec4 rfClipDH = dhProjectionInverse * vec4(texcoord * 2.0 - 1.0, rfDepthLOD * 2.0 - 1.0, 1.0);
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
float refrBase = (biome_beach > 0.01) ? 18.0 : 14.0;
float refrPx = refrBase * rfBiomeFactor / max(rfDist * 0.02, 0.5);
ivec2 refrCoord = texelcoord + ivec2(rfSlope * refrPx);
refrCoord = clamp(refrCoord, ivec2(0), ivec2(viewWidth - 1.0, viewHeight - 1.0));
float refrDepth = texelFetch(depthtex1, refrCoord, 0).r;
if (refrDepth > depth0) {

vec3 refrOpaque = texelFetch(colortex0, refrCoord, 0).rgb;
vec4 refrTrans = texelFetch(colortex7, refrCoord, 0);
vec3 refrColor = refrTrans.a > 0.001 ? refrOpaque * (1.0 - refrTrans.a) + refrTrans.rgb : refrOpaque;
color = mix(color, refrColor, 0.95);
}
}
#endif

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
reflectionStrength *= sideSkyGate;

vec3 sideNormalPerturbed = sideNormalWorld;
sideNormalPerturbed.y += (sideNoise - 0.5) * 0.1;
sideNormalPerturbed.x += (sideNoise - 0.5) * 0.05;
sideNormalPerturbed = normalize(sideNormalPerturbed);
vec3 sideNormalView = normalize(mat3(gbufferModelView) * sideNormalPerturbed);
vec2 sideWaveOffset = vec2((sideNoise - 0.5) * 0.008, (sideNoise - 0.5) * 0.015);
vec3 preRefl = color;
ilv_addReflection(color, viewPos, sideNormalView, lmcoord, reflectionStrength * max(ssrFade, 0.001), sideWaveOffset);
vec3 ssrDelta = color - preRefl;
color = preRefl;
color += ssrDelta * WATER_BRIGHTNESS;
float ssrHit = clamp(length(ssrDelta) * 5.0, 0.0, 1.0);
color = mix(mix(color, sideSkyCol, reflectionStrength), color, ssrHit);

{
vec3 sideN = normalize(mat3(gbufferModelView) * sideNormalWorld);
sideN = normalize(sideN + vec3((sideNoise - 0.5) * 0.5, (sideNoise - 0.5) * 0.5, 0.0));
vec3 sideL = normalize(shadowLightPosition);
vec3 sideV = normalize(-viewPos);
vec3 sideH = normalize(sideV + sideL);
float sideNdotH = max(dot(sideN, sideH), 0.0);
float sideSpec = smoothstep(0.985, 0.995, sideNdotH);
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
color += sideGlowCol * sideGlow * WATER_SPECULAR_INTENSITY * sideShadow;
}
} else {

vec3 preRefl = color;
ilv_addReflection(color, viewPos, normal, lmcoord, reflectionStrength * max(ssrFade, 0.001), waveOffset);
vec3 reflDelta = color - preRefl;
float wb = WATER_BRIGHTNESS;
color = preRefl + reflDelta * wb;

vec3 topL = normalize(shadowLightPosition);
vec3 topV = normalize(-viewPos);
vec3 topWorldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
float topWt = frameTimeCounter * WATER_WAVE_SPEED;

#define SPEC_HASH(p) fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453)
vec3 sp1 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 0.4, topWt * 0.5);
vec3 si1 = floor(sp1); vec3 sf1 = fract(sp1);
sf1 = sf1 * sf1 * (3.0 - 2.0 * sf1);
float sn1 = mix(mix(mix(SPEC_HASH(si1), SPEC_HASH(si1+vec3(1,0,0)), sf1.x),
mix(SPEC_HASH(si1+vec3(0,1,0)), SPEC_HASH(si1+vec3(1,1,0)), sf1.x), sf1.y),
mix(mix(SPEC_HASH(si1+vec3(0,0,1)), SPEC_HASH(si1+vec3(1,0,1)), sf1.x),
mix(SPEC_HASH(si1+vec3(0,1,1)), SPEC_HASH(si1+vec3(1,1,1)), sf1.x), sf1.y), sf1.z);
vec3 sp2 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 0.9, topWt * 1.2) + vec3(17.0);
vec3 si2 = floor(sp2); vec3 sf2 = fract(sp2);
sf2 = sf2 * sf2 * (3.0 - 2.0 * sf2);
float sn2 = mix(mix(mix(SPEC_HASH(si2), SPEC_HASH(si2+vec3(1,0,0)), sf2.x),
mix(SPEC_HASH(si2+vec3(0,1,0)), SPEC_HASH(si2+vec3(1,1,0)), sf2.x), sf2.y),
mix(mix(SPEC_HASH(si2+vec3(0,0,1)), SPEC_HASH(si2+vec3(1,0,1)), sf2.x),
mix(SPEC_HASH(si2+vec3(0,1,1)), SPEC_HASH(si2+vec3(1,1,1)), sf2.x), sf2.y), sf2.z);
vec3 sp3 = vec3(topWorldPos.xz * WATER_WAVE_SCALE * 1.8, topWt * 2.0) + vec3(31.0);
vec3 si3 = floor(sp3); vec3 sf3 = fract(sp3);
sf3 = sf3 * sf3 * (3.0 - 2.0 * sf3);
float sn3 = mix(mix(mix(SPEC_HASH(si3), SPEC_HASH(si3+vec3(1,0,0)), sf3.x),
mix(SPEC_HASH(si3+vec3(0,1,0)), SPEC_HASH(si3+vec3(1,1,0)), sf3.x), sf3.y),
mix(mix(SPEC_HASH(si3+vec3(0,0,1)), SPEC_HASH(si3+vec3(1,0,1)), sf3.x),
mix(SPEC_HASH(si3+vec3(0,1,1)), SPEC_HASH(si3+vec3(1,1,1)), sf3.x), sf3.y), sf3.z);
#undef SPEC_HASH

float wx = (sn1 - 0.5) * 0.5 + (sn2 - 0.5) * 0.3 + (sn3 - 0.5) * 0.2;
float wz = (sn2 - 0.5) * 0.5 + (sn3 - 0.5) * 0.3 + (sn1 - 0.5) * 0.2;

vec3 topN = normalize(normal + mat3(gbufferModelView) * vec3(wx * 0.5, 0.0, wz * 0.5));
vec3 topH = normalize(topV + topL);
float topNdotH = max(dot(topN, topH), 0.0);
TimeWeightsSimple topTS = getTimeWeightsSimple(sunAngle);
float topDayFactor = topTS.day + topTS.twilight * 0.7;
float topSunsetBoost = 1.0 + topTS.twilight * 2.0;
float topSpec = smoothstep(0.985, 0.995, topNdotH);
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
float topGlowAmt = topGlow * WATER_SPECULAR_INTENSITY * topShadow;
preSpecularColor = color;
color += topGlowCol * topGlowAmt;
}
}
}

if (isDhWater && isEyeInWater != 1) {
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
float dhFresnelMod = mix(0.3, 1.0, dhFresnel) * WATER_REFLECTION_FADE;
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
vec3 dhSkyColor = ilv_getSkyColor(dhReflDir, dhWorldPos, false) * 1.3;

float dhReflStrength = WATER_REFLECTION_AMOUNT * dhReflTOD * dhFresnelMod * WATER_SKY_REFLECTION * WATER_OPACITY;
float dhCrestReflectCut = 1.0;
dhReflStrength *= dhCrestReflectCut;
float dhSkylight = texelFetch(colortex1, texelcoord, 0).b;
dhReflStrength *= smoothstep(13.0 / 15.0, 14.0 / 15.0, dhSkylight);
dhReflStrength = clamp(dhReflStrength, 0.0, 1.0);
color = mix(color, dhSkyColor, dhReflStrength);
}
#endif

#ifdef WATER_FOAM_ENABLED
if ((isWater || isDhWater) && waveBiome > 0.01 && beachWaveHeight > 0.001 && isEyeInWater != 1) {
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

#ifdef MATERIAL_REFLECTIONS_ENABLED
bool isHandPixel = isHandEarly;
bool isEntityPixel = isEntityOrHand;
if (isMaterialRefl && isEyeInWater != 1 && !isHandPixel && !isEntityPixel) {
if (depth0 < 1.0) {
float mnx = reflData.z * 2.0 - 1.0;
float mny = reflData.w * 2.0 - 1.0;
float mnz = sqrt(max(1.0 - mnx * mnx - mny * mny, 0.0));
vec3 worldNormal = vec3(mnx, mny, mnz);
vec3 matNormal = normalize(mat3(gbufferModelView) * worldNormal);

float matReflStr = MATERIAL_REFLECTION_AMOUNT;
vec3 screenPos = vec3(texcoord, depth0);
vec3 matViewPos = ilv_screenToView(screenPos);

vec3 V = normalize(-matViewPos);
float NdotV = max(dot(matNormal, V), 0.0);
float fresnel = pow(1.0 - NdotV, 3.0) * MATERIAL_REFLECTION_FRESNEL;
matReflStr = mix(matReflStr * 0.4, matReflStr, fresnel);

float matSsrDist = length(matViewPos);
float matSsrFade = 1.0 - smoothstep(float(SSR_RENDER_DISTANCE) * 0.8, float(SSR_RENDER_DISTANCE), matSsrDist);
matReflStr *= matSsrFade;
if (matReflStr > 0.001)
ilv_addMaterialReflection(color, matViewPos, matNormal, matReflStr);
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
if (puddleDepth < 0.9999 && pxSkylight > 0.95) {
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

float puddleMask = puddleStrength * flatMask * patches;
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
ilv_addReflection(color, puddleViewPos, reflNormal, vec2(0.0, 1.0), reflStr, vec2(0.0));
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

if ((isWater || isDhWater) && isEyeInWater != 1) {
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
float fogAmount = 1.0 - exp(-wDist * fogDensity);
fogAmount = clamp(fogAmount, 0.0, fogMax);

if (fogAmount > 0.001) {
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
color *= mix(vec3(1.0), uwWaterTint * 3.0, fogAmount);
color += uwWaterTint * fogAmount;
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

if ((isWater || isDhWater) && isEyeInWater != 1) {
vec3 specDelta = max(color - preSpecularColor, vec3(0.0));
vec3 biomeWater = biomeWaterColor(sunAngle, biome_beach, biome_swamp, biome_jungle, biome_snowy, biome_arid);
vec3 defaultBlue = vec3(0.0, 66.0, 102.0) / 255.0;
float hasBiome = max(max(biome_swamp, biome_jungle), max(biome_snowy, biome_arid));
vec3 waterTint = mix(defaultBlue, biomeWater, clamp(hasBiome, 0.0, 1.0));

float tintLum = dot(waterTint, vec3(0.299, 0.587, 0.114));
waterTint = mix(vec3(tintLum), waterTint, 2.0);
waterTint = max(waterTint, vec3(0.0));

float waterSkyDim = mix(0.05, 1.0, texelFetch(colortex1, texelcoord, 0).b);
waterTint *= waterSkyDim;
vec3 tinted = mix(preSpecularColor, waterTint, 0.5);

float foamAmount = clamp(reflData.x - 1.0, 0.0, 1.0);
vec3 foamColor = vec3(WATER_FOAM_COLOR_R, WATER_FOAM_COLOR_G, WATER_FOAM_COLOR_B) * WATER_FOAM_INTENSITY;
color = mix(tinted, foamColor, foamAmount) + specDelta;
}

bool isGlassPixel = (glassTint.a > 0.55 && glassTint.a < 0.65);
if (isGlassPixel && !isWater && isEyeInWater != 1) {

float glassOpaqueDepth = texelFetch(depthtex1, texelcoord, 0).r;
if (glassOpaqueDepth < 0.9999) {
vec4 glassClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, glassOpaqueDepth * 2.0 - 1.0, 1.0);
vec3 glassViewP = glassClip.xyz / glassClip.w;
vec3 glassBehindWorld = (gbufferModelViewInverse * vec4(glassViewP, 1.0)).xyz + cameraPosition;
if (glassBehindWorld.y < float(SEA_LEVEL_OFFSET)) {

vec3 glassViewDir = normalize(glassViewP);
vec3 glassNormal = normalize(mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0));
vec3 glassReflDir = reflect(glassViewDir, glassNormal);
vec3 glassReflWorld = mat3(gbufferModelViewInverse) * glassReflDir;
vec3 glassSkyRefl = ilv_getSkyColor(glassReflDir, glassBehindWorld, false) * WATER_SKY_REFLECTION;
float glassFresnel = 1.0 - abs(dot(normalize(-glassViewP), glassNormal));
glassFresnel = glassFresnel * glassFresnel * glassFresnel;
float glassReflStr = mix(0.2, 0.8, glassFresnel) * WATER_OPACITY;
color = mix(color, glassSkyRefl, glassReflStr);
}
}
}

#endif

#endif

if (isEyeInWater == 1) {
float uwtDepth = texture(depthtex0, texcoord).r;
if (uwtDepth < 1.0) {
vec4 uwtClip = vec4(texcoord * 2.0 - 1.0, uwtDepth * 2.0 - 1.0, 1.0);
vec4 uwtView = gbufferProjectionInverse * uwtClip;
uwtView /= uwtView.w;
float uwtDist = length(uwtView.xyz);
float tintAmount = smoothstep(0.0, 40.0, uwtDist) * 0.6;
vec3 uwTintColor = vec3(UNDERWATER_FOG_R, UNDERWATER_FOG_G, UNDERWATER_FOG_B);
float lum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 tinted = lum * uwTintColor;
color = mix(color, tinted, tintAmount);
}
}

gl_FragData[0] = vec4(color, cloudAlpha);
}
