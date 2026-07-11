#include "/settings.glsl"

#if TERRAIN_PROFILE_MODE == 1
#undef SHADOWS_ENABLED
#undef CLOUD_SHADOWS_ENABLED
#elif TERRAIN_PROFILE_MODE == 2
#undef LPV_ENABLED
#elif TERRAIN_PROFILE_MODE == 3
#undef BLOOM_ENABLED
#elif TERRAIN_PROFILE_MODE == 4
#undef MATERIAL_REFLECTIONS_ENABLED
#elif TERRAIN_PROFILE_MODE == 5
#undef PBR_ENABLED
#elif TERRAIN_PROFILE_MODE == 6
#undef METALNESS_ENABLED
#elif TERRAIN_PROFILE_MODE == 7
#undef EMISSIVE_MASKING
#undef HANDHELD_LIGHT_ENABLED
#elif TERRAIN_PROFILE_MODE == 8
#undef LEAF_SHEEN_ENABLED
#elif TERRAIN_PROFILE_MODE == 9
#undef CHUNK_FADE_OUT_ENABLED
#elif TERRAIN_PROFILE_MODE == 10
#undef WATER_WAVES_ENABLED
#elif TERRAIN_PROFILE_MODE == 11
#define TERRAIN_PROFILE_SKIP_PURE_TEX_FETCH
#elif TERRAIN_PROFILE_MODE == 12
#define TERRAIN_PROFILE_SKIP_FOLIAGE_LIGHT_GRADIENT
#elif TERRAIN_PROFILE_MODE == 13
#define TERRAIN_PROFILE_SKIP_FACE_SHADING
#elif TERRAIN_PROFILE_MODE == 14
#define TERRAIN_PROFILE_SKIP_GRASS_PATCH_NOISE
#elif TERRAIN_PROFILE_MODE == 15
#define TERRAIN_PROFILE_BASE_TEXTURE_ONLY
#elif TERRAIN_PROFILE_MODE == 16
#define TERRAIN_PROFILE_SKIP_MAIN_LIGHTING
#elif TERRAIN_PROFILE_MODE == 21
#undef BLOOM_ENABLED
#undef MATERIAL_REFLECTIONS_ENABLED
#define TERRAIN_PROFILE_BASE_TEXTURE_ONLY
#endif

#if defined(BLOOM_ENABLED) && defined(MATERIAL_REFLECTIONS_ENABLED)
/* RENDERTARGETS: 0,1,2,3,5 */
#define TERRAIN_SSR_OUT 4
#elif defined(BLOOM_ENABLED)
/* RENDERTARGETS: 0,1,2,3 */
#elif defined(MATERIAL_REFLECTIONS_ENABLED)
/* RENDERTARGETS: 0,1,5 */
#define TERRAIN_SSR_OUT 2
#else
/* RENDERTARGETS: 0,1 */
#endif

#include "/include/biome_overrides.glsl"
#include "/include/shadow.glsl"
#include "/include/hovering.glsl"
#include "/include/ocean_waves.glsl"

uniform sampler2D gtexture;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
#ifdef PBR_ENABLED
uniform sampler2D normals;
uniform sampler2D specular;
uniform sampler2D noisetex;
#define LAVA_HAS_NOISETEX
#endif
uniform float alphaTestRef;
uniform vec3 fogColor;
uniform int biome_category;
uniform float fogStart;
uniform float fogEnd;
uniform float far;
uniform float sunAngle;
uniform vec3 shadowLightPosition;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform int currentRenderedItemId;
uniform float biome_swamp;
uniform int isEyeInWater;
uniform int frameCounter;

uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

#include "/include/lighting.glsl"
#ifdef EMISSIVE_MASKING
#include "/include/emissive_mask.glsl"
#endif
uniform float frameTimeCounter;
#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
#include "/include/end_event.glsl"
#endif
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_arid;
uniform float biome_savanna;

in vec2 texcoord;
in vec2 midTexCoord;
in vec4 glcolor;
in float viewDistance;
in float outlineMask;
in float skylight;
in float blocklight;
flat in float emissive;
flat in float emissiveType;
in vec3 worldPos;
flat in vec3 blockCenterWorld;
in vec4 shadowPos;
flat in float isGrassGeometry;
flat in float isHeatSource;
flat in float isHologram;
flat in float metalness;
flat in float reflective;
in vec3 normal;
flat in vec3 geoNormal;
flat in float blockId;
in float leafAO;
#ifdef PBR_ENABLED
in vec3 tangentVec;
in vec3 binormalVec;
#endif

#include "/include/fog_color.glsl"

#if defined(CLOUDS_2D_ENABLED) && defined(CLOUD_SHADOWS_ENABLED)
#include "/include/cloud_shadow.glsl"
#endif

float random(float x) {
return fract(sin(x * 12.9898) * 43758.5453);
}

#include "/include/noise.glsl"
#include "/include/lava_crust.glsl"

#include "/include/metalness.glsl"
#ifdef PBR_ENABLED
#include "/include/pbr.glsl"
#endif

void main() {
vec2 finalUV = texcoord;

vec4 color = texture(gtexture, finalUV) * glcolor;

if (color.a < alphaTestRef) {
discard;
}

if (!isForcedNetherBiome(biome) && !isForcedEndBiome(biome) && isEyeInWater != 1) {
#ifdef CHUNK_FADE_OUT_ENABLED
#ifndef DISTANT_HORIZONS

float horizontalDist = length(worldPos.xz - cameraPosition.xz);
float distGate = smoothstep(CHUNK_FADE_OUT_RADIUS, CHUNK_FADE_OUT_RADIUS + 24.0, horizontalDist);
if (distGate > 0.001) {
float reveal = 1.0 - distGate;
float minY = SEA_LEVEL_OFFSET - 96.0;
float maxY = SEA_LEVEL_OFFSET + 320.0;

float mask = smoothChunkNoise(worldPos.xz * 0.12);
float jitterY = (mask - 0.5) * 10.0;
float revealY = mix(minY, maxY, reveal) + jitterY;
float visible = 1.0 - smoothstep(revealY - 8.0, revealY + 8.0, worldPos.y);
color.rgb *= mix(0.60, 1.0, visible);
if (visible < 0.02) {
discard;
}
}
#endif
#endif
}

#if defined(TERRAIN_PROFILE_SKIP_PURE_TEX_FETCH)
vec3 pureTexColor = color.rgb;
#elif defined(EMISSIVE_MASKING) || defined(LPV_ENABLED)
vec3 pureTexColor = texture(gtexture, finalUV).rgb;
#else
vec3 pureTexColor = color.rgb;
#endif

vec3 rawColor = color.rgb;

float finalBlocklight = blocklight;
float finalSkylight = skylight;
float finalEmissive = emissive;

#ifdef TERRAIN_PROFILE_BASE_TEXTURE_ONLY
gl_FragData[0] = vec4(rawColor, color.a);
gl_FragData[1] = vec4(outlineMask, finalEmissive, finalSkylight, isHeatSource);
#ifdef BLOOM_ENABLED
gl_FragData[2] = vec4(0.0);
gl_FragData[3] = vec4(0.0);
#endif
#ifdef MATERIAL_REFLECTIONS_ENABLED
gl_FragData[TERRAIN_SSR_OUT] = vec4(0.0);
#endif
return;
#endif

#ifdef EMISSIVE_MASKING
float emissiveMask = 0.0;
if (emissive > 0.5) {
emissiveMask = getEmissiveMask(int(floor(emissiveType + 0.5)), pureTexColor);

int cbEt = int(floor(emissiveType + 0.5));
if (cbEt == 39 || cbEt == 40 || cbEt == 41) {
vec3 blockUV = fract(worldPos);
vec3 absN = abs(normalize(mat3(gbufferModelViewInverse) * normal));
vec2 faceUV;
if (absN.y > absN.x && absN.y > absN.z) faceUV = blockUV.xz;
else if (absN.x > absN.z) faceUV = blockUV.yz;
else faceUV = blockUV.xy;
const int cbMask[16] = int[](
0, 0, 1632, 1632, 1632, 15996, 15996, 0,
0, 15996, 15996, 1632, 1632, 1632, 0, 0
);
ivec2 texel = clamp(ivec2(floor(faceUV * 16.0)), ivec2(0), ivec2(15));
bool isEmissivePixel = (cbMask[texel.y] & (1 << texel.x)) != 0;
emissiveMask *= isEmissivePixel ? 1.0 : 0.0;
}

if (emissiveMask < 0.05) {
finalEmissive = 0.0;
}

int emEt = int(floor(emissiveType + 0.5));
if (emEt == 44) {
finalEmissive = 0.0;
}
}
#endif

bool isHeldLight = (currentRenderedItemId == 10020 || currentRenderedItemId == 10021);

int terrainBid = int(blockId + 0.5);
bool allowThinFoliageGradient = (terrainBid == 10015);
#ifndef TERRAIN_PROFILE_SKIP_FOLIAGE_LIGHT_GRADIENT
if (isGrassGeometry > 0.5 && allowThinFoliageGradient) {
float dLightX = dFdx(blocklight);
float dLightZ = dFdy(blocklight);
vec2 blockFract = fract(worldPos.xz);
float gradientOffset = (blockFract.x - 0.5) * dLightX * 8.0 + (blockFract.y - 0.5) * dLightZ * 8.0;
finalBlocklight = clamp(blocklight + gradientOffset, 0.0, 1.0);
}
#endif

vec3 shadow = vec3(1.0);
float directSunLit = 0.0;
vec3 directSunColor = vec3(0.0);
float transmittedSunLit = 0.0;
vec3 transmittedSunColor = vec3(0.0);
#ifdef SHADOWS_ENABLED
if (finalEmissive < 0.5 && !isForcedNetherBiome(biome)) {

vec3 shadowSamplePos = shadowPos.xyz;

#ifdef LEAF_SHEEN_ENABLED
#ifdef MAGICAL_TOUCH
{
int bid = int(blockId + 0.5);
if (bid == 10005 || bid == 10082) {
vec3 wN = normalize(mat3(gbufferModelViewInverse) * normal);
vec3 wL = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
float backFace = max(0.0, -dot(wN, wL));
float notBottomFace = step(-0.5, wN.y);
shadowSamplePos.z -= backFace * notBottomFace * LEAF_SHADOW_TRANSMITTANCE * 0.02;
}
}
#endif
#endif

int shadowBid = int(blockId + 0.5);
#ifdef MAGICAL_TOUCH
bool isLeafShadow = (shadowBid == 10005 || shadowBid == 10082);
#else
bool isLeafShadow = false;
#endif
float shadowCoverage = 1.0 - smoothstep(SHADOW_DISTANCE * 0.8, SHADOW_DISTANCE, viewDistance);

float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
float r = quartic_length(shadowSamplePos.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;

if (isLeafShadow) {
#if defined(LEAF_VOXEL_SHADOW_ENABLED) && defined(LPV_ENABLED)

vec3 vxWorldN = normalize(mat3(gbufferModelViewInverse) * normal);
vec3 vxWorldL = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
float voxShadow = sampleLeafVoxelShadow(blockCenterWorld, vxWorldL, vxWorldN);
shadow = vec3(voxShadow);
#elif LEAF_SHADOW_SOFTNESS <= 0.0

float mapDepth = texture(shadowtex0, shadowSamplePos.xy).r;
shadow = vec3(step(shadowSamplePos.z, mapDepth));
float shadowCoverageFade = 1.0 - shadowDistanceFade(shadowSamplePos, viewDistance);
shadow = mix(vec3(1.0), shadow, shadowEdgeFade(shadowSamplePos) * shadowCoverageFade);
#else

shadow = vec3(getShadowLeafFaded(shadowtex0, shadowSamplePos, distortFactor, viewDistance, dither));
#endif
} else {
#if defined(SHARP_SHADOWS) || defined(MAGICAL_TOUCH)
float mapDepth0 = texture(shadowtex0, shadowSamplePos.xy).r;
float mapDepth1 = texture(shadowtex1, shadowSamplePos.xy).r;
float inShadow0 = 1.0 - step(shadowSamplePos.z, mapDepth0);
float inShadow1 = 1.0 - step(shadowSamplePos.z, mapDepth1);

float isTranslucentShadow = inShadow0 * (1.0 - inShadow1);
float isOpaqueShadow = inShadow1;

vec4 shCol = texture(shadowcolor0, shadowSamplePos.xy);

vec3 tintColor = shCol.rgb;
float tintMax = max(max(tintColor.r, tintColor.g), tintColor.b);
if (tintMax > 0.001) tintColor /= tintMax;

vec3 transmit = mix(vec3(1.0), tintColor, 0.7) * 2.10;
transmittedSunLit = max(transmittedSunLit, isTranslucentShadow * shadowCoverage);
transmittedSunColor = max(transmittedSunColor, transmit * transmittedSunLit);

shadow = vec3(1.0);
shadow = mix(shadow, vec3(0.0), isOpaqueShadow);
shadow = mix(shadow, min(transmit, vec3(1.6)), isTranslucentShadow);
float shadowCoverageFade = 1.0 - shadowDistanceFade(shadowSamplePos, viewDistance);
shadow = mix(vec3(1.0), shadow, shadowEdgeFade(shadowSamplePos) * shadowCoverageFade);
#else
shadow = getShadowColorFaded(shadowtex0, shadowcolor0, shadowSamplePos, distortFactor, viewDistance, dither);
#endif
}

#ifdef MAGICAL_TOUCH
bool isFoliageShadowId = (shadowBid == 10002 || shadowBid == 10003 || shadowBid == 10004 || shadowBid == 10019 || shadowBid == 10060 || shadowBid == 10061 || shadowBid == 10062);
#else
bool isFoliageShadowId = false;
#endif
if (isGrassGeometry < 0.5 && !isFoliageShadowId) {
float grazeBlend = smoothstep(0.15, 0.0, shadowPos.w) * shadowCoverage;
shadow = mix(shadow, vec3(0.0), grazeBlend);
}

if (shadowBid == 10018) {
shadow = mix(shadow, vec3(1.0), 0.5);
}

directSunLit = dot(shadow, vec3(0.333)) * shadowCoverage;
directSunColor = shadow * shadowCoverage;

shadow = mix(vec3(1.0), shadow, finalSkylight);

float shadowLum = dot(shadow, vec3(0.299, 0.587, 0.114));

float darkened = mix(1.0, shadowLum, SHADOW_OPACITY);

shadow = (shadowLum > 0.001) ? shadow * (darkened / shadowLum) : vec3(darkened);
}
#endif

float shadowLum = 1.0;
#ifdef SHADOWS_ENABLED
shadowLum = dot(shadow, vec3(0.299, 0.587, 0.114));
#endif

#if defined(CLOUDS_2D_ENABLED) && defined(CLOUD_SHADOWS_ENABLED)
if (finalSkylight > 0.1) {
float cloudShadow = getCloudShadow(worldPos, frameTimeCounter);
shadow *= cloudShadow;
}
#endif

#ifndef TERRAIN_PROFILE_SKIP_FACE_SHADING
{
#ifdef MAGICAL_TOUCH
float faceShadeGate = 1.0 - smoothstep(0.0, 2.0 / 15.0, finalSkylight);
#else
float faceShadeGate = 1.0;
#endif
if (faceShadeGate > 0.01) {
vec3 worldNormalFace = normalize(mat3(gbufferModelViewInverse) * geoNormal);
float faceShade = getVanillaFaceShade(worldNormalFace);
color.rgb *= mix(1.0, faceShade, faceShadeGate);
}
}
#endif

#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
if (isGrassGeometry > 0.5) {

lpvWorldNormal = vec3(0.0, 1.0, 0.0);
}

bool lpvUseTintedFoliageColor =
isGrassGeometry > 0.5 ||
terrainBid == 10005 || terrainBid == 10015 || terrainBid == 10018 ||
terrainBid == 10060 || terrainBid == 10061 || terrainBid == 10062 ||
terrainBid == 10082;
lpvReceiverStrength = 1.0;
vec3 lpvCatchColor = lpvUseTintedFoliageColor ? rawColor : pureTexColor;
lpvSurfaceColor = lpvCatchColor;

lpvTexLuma = dot(lpvCatchColor, vec3(0.299, 0.587, 0.114));
#endif

vec3 lightingBaseColor = color.rgb;
float sunOverrideSkyHint = smoothstep(0.5 / 15.0, 2.0 / 15.0, finalSkylight);
float sunOverrideHeightGate = smoothstep(float(SEA_LEVEL_OFFSET) - 4.0, float(SEA_LEVEL_OFFSET) + 2.0, worldPos.y);
float sunOverrideInteriorGate = max(sunOverrideSkyHint, sunOverrideHeightGate);
directSunVisibility = clamp(max(directSunLit, transmittedSunLit) * getStableDayFactor(sunAngle) * sunOverrideInteriorGate, 0.0, 1.0);
#ifdef TERRAIN_PROFILE_SKIP_MAIN_LIGHTING
color.rgb = lightingBaseColor;
#else
color.rgb = applyLightingWithShadow(lightingBaseColor, sunAngle, finalSkylight, finalBlocklight, finalEmissive, shadow, worldPos.y);
float shadowTransitionDip = getSunMoonShadowTransitionDip(sunAngle) * getHasSkylightMask(finalSkylight);
if (shadowTransitionDip > 0.001) {
vec3 transitionNoShadow = applyLightingWithShadow(lightingBaseColor, sunAngle, finalSkylight, finalBlocklight, finalEmissive, vec3(1.0), worldPos.y);
color.rgb = mix(color.rgb, transitionNoShadow, shadowTransitionDip);
}
color.rgb *= getSunMoonShadowTransitionDarken(shadowTransitionDip, getTimeOfDayLighting(sunAngle).x, finalSkylight);
#endif

#ifdef WATER_WAVES_ENABLED
if (isEyeInWater == 1 && worldPos.y < float(SEA_LEVEL_OFFSET) && finalSkylight > 0.1) {
float waterSurfaceY = float(SEA_LEVEL_OFFSET);
float submergedDepth = waterSurfaceY - worldPos.y;

float ct = frameTimeCounter * WATER_WAVE_SPEED * 0.4;
vec3 cPos3D = worldPos * 0.75;

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

float depthFade = exp(-submergedDepth * 0.03);

float causticSunLit = clamp(shadowPos.w, 0.0, 1.0);

float causticFogFade = 1.0;
#ifdef UNDERWATER_FOG_ENABLED
{
float causticViewDist = length(worldPos - cameraPosition);
float causticExtCoeff = UNDERWATER_FOG_DENSITY * 0.008;
causticFogFade = exp(-causticViewDist * causticExtCoeff);
}
#endif

float causticStrength = caustic * depthFade * causticFogFade * causticSunLit * finalSkylight * 0.45;

color.rgb *= 1.0 + causticStrength;
}
#endif

#ifdef EMISSIVE_MASKING
if (emissive > 0.5 && emissiveMask >= 0.05) {
int sceneEt = int(floor(emissiveType + 0.5));
if (sceneEt == 44) {

float whiteness = smoothstep(0.7, 0.95, dot(rawColor, vec3(0.333)));
color.rgb = mix(color.rgb, rawColor * (1.0 + whiteness * 0.1), 0.75);
} else {
vec3 emSrc = (sceneEt == 19) ? pureTexColor : rawColor;
vec3 emissiveResult = emSrc * EMISSIVE_BRIGHTNESS;
#ifdef END_SHADER
emissiveResult *= END_EMISSIVE_BOOST;
#endif
color.rgb = mix(color.rgb, emissiveResult, clamp(emissiveMask, 0.0, 1.0));
}
}
#endif

bool outputHeldBloom = false;
vec3 heldBloomColor = vec3(0.0);
#ifdef HANDHELD_LIGHT_ENABLED
float distToEye = length(worldPos - eyePosition);

bool isHeldLightItem = (heldItemId >= 10020 && heldItemId <= 10059) || heldItemId == 10087 || heldItemId == 10089 ||
(heldItemId2 >= 10020 && heldItemId2 <= 10059) || heldItemId2 == 10087 || heldItemId2 == 10089;

if (distToEye < 2.0 && isHeldLightItem && blockId < 1.0) {
#ifdef EMISSIVE_MASKING
int heldEt = 0;
if (heldItemId == 10087) heldEt = 46;
else if (heldItemId == 10089) heldEt = 47;
else if (heldItemId >= 10020 && heldItemId <= 10059) heldEt = heldItemId - 10020;
else if (heldItemId2 == 10087) heldEt = 46;
else if (heldItemId2 == 10089) heldEt = 47;
else if (heldItemId2 >= 10020 && heldItemId2 <= 10059) heldEt = heldItemId2 - 10020;
float heldMask = getEmissiveMask(heldEt, rawColor);
float hm = clamp(heldMask, 0.0, 1.0);

vec3 litColor = applyLighting(rawColor, sunAngle, skylight, blocklight, worldPos.y);
vec3 emResult = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_EMISSION;
color.rgb = mix(litColor, emResult, hm);
finalEmissive = (hm > 0.05) ? 1.0 : 0.0;
float heldBloomMult = (heldEt == 46) ? 0.15 : 1.0;
heldBloomColor = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_STRENGTH * hm * heldBloomMult;
outputHeldBloom = (hm > 0.05);
#else
color.rgb = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_EMISSION;
finalEmissive = 1.0;
heldBloomColor = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_STRENGTH;
outputHeldBloom = true;
#endif
}

if (!outputHeldBloom) {
bool holdingLight = (heldBlockLightValue > 7 || heldBlockLightValue2 > 7);
if (holdingLight && distToEye < HELD_BLOOM_RADIUS && blockId < 1.0) {
float rawColorLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
if (rawColorLuma > HELD_BLOOM_THRESHOLD && blocklight > 0.8) {
#ifdef EMISSIVE_MASKING
int fbEt = 0;
if (heldItemId == 10087) fbEt = 46;
else if (heldItemId == 10089) fbEt = 47;
else if (heldItemId >= 10020 && heldItemId <= 10063) fbEt = heldItemId - 10020;
else if (heldItemId2 == 10087) fbEt = 46;
else if (heldItemId2 == 10089) fbEt = 47;
else if (heldItemId2 >= 10020 && heldItemId2 <= 10063) fbEt = heldItemId2 - 10020;
float fbMask = getEmissiveMask(fbEt, rawColor);
float fm = clamp(fbMask, 0.0, 1.0);
vec3 litColor = applyLighting(rawColor, sunAngle, skylight, blocklight, worldPos.y);
vec3 emResult = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_EMISSION;
color.rgb = mix(litColor, emResult, fm);
finalEmissive = (fm > 0.05) ? 1.0 : 0.0;
heldBloomColor = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_STRENGTH * fm;
outputHeldBloom = (fm > 0.05);
#else
color.rgb = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_EMISSION;
finalEmissive = 1.0;
heldBloomColor = rawColor * EMISSIVE_BRIGHTNESS * HELD_BLOOM_STRENGTH;
outputHeldBloom = true;
#endif
}
}
}
#endif
#ifdef HANDHELD_LIGHT_ENABLED
if (finalEmissive < 0.5) color.rgb += getHandheldLightBoost(worldPos, rawColor, color.rgb);
#endif
color.rgb *= TERRAIN_BRIGHTNESS;

#ifdef END_SHADER
if (finalEmissive < 0.5) {

#ifdef END_TERRAIN_PATCHES_ENABLED
{
vec3 patchPos3D = worldPos * END_TERRAIN_PATCH_SCALE;
float pn = 0.0;
float pAmp = 0.6;
for (int octave = 0; octave < 3; octave++) {
vec3 ip = floor(patchPos3D);
vec3 fp = fract(patchPos3D);
fp = fp * fp * (3.0 - 2.0 * fp);
float a = fract(sin(dot(ip, vec3(127.1, 311.7, 74.7))) * 43758.5453);
float b = fract(sin(dot(ip + vec3(1,0,0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
float c = fract(sin(dot(ip + vec3(0,1,0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
float d = fract(sin(dot(ip + vec3(1,1,0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
float e = fract(sin(dot(ip + vec3(0,0,1), vec3(127.1, 311.7, 74.7))) * 43758.5453);
float f = fract(sin(dot(ip + vec3(1,0,1), vec3(127.1, 311.7, 74.7))) * 43758.5453);
float g = fract(sin(dot(ip + vec3(0,1,1), vec3(127.1, 311.7, 74.7))) * 43758.5453);
float h = fract(sin(dot(ip + vec3(1,1,1), vec3(127.1, 311.7, 74.7))) * 43758.5453);
float z0 = mix(mix(a, b, fp.x), mix(c, d, fp.x), fp.y);
float z1 = mix(mix(e, f, fp.x), mix(g, h, fp.x), fp.y);
pn += mix(z0, z1, fp.z) * pAmp;
patchPos3D *= 2.3;
pAmp *= 0.45;
}
float patchDark = smoothstep(0.25, 0.55, pn);
patchDark = mix(1.0, 1.0 - END_TERRAIN_PATCH_STRENGTH, 1.0 - patchDark);
color.rgb *= patchDark;
}
#endif

#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
EndEvent endEvent = getEndEvent(frameTimeCounter);
#endif
#if defined(END_SHADER) && defined(END_EVENT_ENABLED) && defined(END_EVENT_EYE_ENABLED) && defined(END_EVENT_SPOTLIGHT_ENABLED)
if (endEvent.eyeOpen > 0.01) {

vec2 playerXZ = eyePosition.xz;
vec2 fragXZ = worldPos.xz;
float hDist = length(fragXZ - playerXZ);

float spotRadius = END_EVENT_SPOTLIGHT_RADIUS;
float spot = 1.0 - smoothstep(spotRadius * 0.4, spotRadius, hDist);

float upFacing = max(normal.y, 0.0);
spot *= upFacing;

spot *= endEvent.eyeOpen;

vec3 spotColor = vec3(
END_EVENT_EYE_IRIS_R * 0.5 + 0.5,
END_EVENT_EYE_IRIS_G * 0.3 + 0.4,
END_EVENT_EYE_IRIS_B * 0.4 + 0.6
);
color.rgb += rawColor * spotColor * spot * END_EVENT_SPOTLIGHT_INTENSITY * TERRAIN_BRIGHTNESS;
}
#endif
}
#endif

#if !defined(END_SHADER) && !defined(TERRAIN_PROFILE_SKIP_GRASS_PATCH_NOISE)
{
int bid = int(blockId + 0.5);
int btype = (bid >= 10000) ? (bid - 10000) : -1;
if (btype == 15 && finalEmissive < 0.5) {

float upFacing = max(normal.y, 0.0);
if (upFacing > 0.3) {
vec2 patchPos = worldPos.xz * 0.15;
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

float patchMask = 1.0 - smoothstep(0.25, 0.55, pn);
float patchStrength = 0.20 * patchMask * upFacing;

color.rgb *= mix(vec3(1.0), vec3(0.7, 0.8, 0.95), patchStrength);
}
}
}
#endif

#ifdef TEXTURE_PALETTE_ENABLED
if (finalEmissive < 0.5) {
float levels = float(TEXTURE_PALETTE_LEVELS);
color.rgb = floor(color.rgb * levels) / levels;
}
#endif

#ifdef METALNESS_ENABLED
if (metalness > 0.5 && finalEmissive < 0.5) {
int metalBid = int(blockId + 0.5);
vec3 viewDir = normalize(worldPos - cameraPosition);

vec3 worldNormalMetal = normalize(mat3(gbufferModelViewInverse) * normal);
vec3 worldLightMetal = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 metalLocalLight = vec3(1.0, 0.85, 0.60) * blocklight * blocklight;
#ifdef LPV_ENABLED
{
vec3 lpvMetalLight = sampleLpvLight(worldPos, worldNormalMetal, 1.0) * BLOCKLIGHT_BRIGHTNESS * 5.0;
float lpvMetalLuma = dot(lpvMetalLight, vec3(0.299, 0.587, 0.114));
if (lpvMetalLuma > 0.001) metalLocalLight = lpvMetalLight;
}
#endif
float metalApplyMask = 1.0;
if (metalBid == 10090) {

float railBright = max(max(rawColor.r, rawColor.g), rawColor.b);
metalApplyMask = smoothstep(0.40, 0.62, railBright);
}

#ifdef END_SHADER
float endLightAngle = frameTimeCounter * 0.15;
vec3 endLight = normalize(vec3(sin(endLightAngle) * 0.4, 0.8, cos(endLightAngle) * 0.4));
vec3 metalColor = applyMetalnessEnd(color.rgb, viewDir, worldNormalMetal, endLight, metalness, worldPos, frameTimeCounter, rawColor, 1.0, blocklight, metalLocalLight);
color.rgb = mix(color.rgb, metalColor, metalApplyMask);
#else
float shadowLit = dot(shadow, vec3(0.333)) * smoothstep(0.1, 0.5, skylight);
vec3 metalColor = applyMetalness(color.rgb, viewDir, worldNormalMetal, worldLightMetal, sunAngle, metalness, worldPos, rawColor, shadowLit, blocklight, metalLocalLight);
color.rgb = mix(color.rgb, metalColor, metalApplyMask);
#endif
}
#endif

#ifdef PBR_ENABLED
PBRMaterial pbrMat = pbr_fallback(normal, DEFAULT_STONE_ROUGHNESS);
vec3 pbrNormal = normal;

if (finalEmissive < 0.5) {
vec4 normalData = texture(normals, texcoord);
vec4 specData   = texture(specular, texcoord);

pbrMat = pbr_decode(normalData, specData, rawColor, PBR_NORMAL_STRENGTH);

vec3 N;
if (pbrMat.hasData) {
N = pbr_tangentToView(pbrMat.nTangent, tangentVec, binormalVec, normal);
} else {

int bid = int(blockId + 0.5);
int btype = (bid >= 10000) ? (bid - 10000) : -1;
if      (btype == 10) pbrMat.roughness = DEFAULT_WOOD_ROUGHNESS;
else if (btype == 17) pbrMat.roughness = 0.45;
else if (btype == 18) pbrMat.roughness = DEFAULT_STONE_ROUGHNESS;
else                  pbrMat.roughness = -1.0;
N = normalize(normal);
}
pbrNormal = N;
}

if (finalEmissive < 0.5 && metalness < 0.5) {

if (pbrMat.hasNormal && PBR_AO_STRENGTH > 0.001) {
float directAmount = dot(shadow, vec3(0.299, 0.587, 0.114)) * finalSkylight;
float indirectAmount = 1.0 - directAmount;
float aoMul = mix(1.0, pbrMat.ao, PBR_AO_STRENGTH * 0.5);
color.rgb *= mix(1.0, aoMul, indirectAmount);
}

if (pbrMat.hasSpec && pbrMat.roughness < 0.999) {
vec3 L      = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 Nworld = normalize(mat3(gbufferModelViewInverse) * pbrNormal);
vec3 Vworld = normalize(cameraPosition - worldPos);
vec3 Hworld = normalize(Vworld + L);
float NdotL = max(dot(Nworld, L),      0.0);
float NdotH = max(dot(Nworld, Hworld), 0.0);
float NdotV = max(dot(Nworld, Vworld), 1e-3);
vec3 pbrLocalLight = vec3(0.0);
float pbrLocalLuma = 0.0;
#ifdef LPV_ENABLED
if (pbrMat.hasSpec || pbrMat.metalness > 0.5) {
pbrLocalLight = sampleLpvLight(worldPos, Nworld, 1.0) * BLOCKLIGHT_BRIGHTNESS * 5.0;
pbrLocalLuma = dot(pbrLocalLight, vec3(0.299, 0.587, 0.114));
}
#endif

float sunVisibility = dot(shadow, vec3(0.299, 0.587, 0.114)) * finalSkylight;

float sunFrac = fract(sunAngle);
float dayFactor = smoothstep(0.00, 0.15, sunFrac) * smoothstep(0.55, 0.40, sunFrac);

float grazeSoft = smoothstep(0.02, 0.15, NdotV);

float r = clamp(pbrMat.roughness, 0.5, 1.0);

float shininess = mix(32.0, 4.0, r);
float specPow = pow(NdotH, shininess);

float norm = (shininess + 2.0) / (2.0 * 3.14159265);
vec3  F = pbr_fresnelSchlickColor(NdotV, pbrMat.F0);
vec3 specular = specPow * norm * F * NdotL;
specular *= grazeSoft * PBR_SPECULAR_STRENGTH * sunVisibility * dayFactor;

vec3 ambientSpec = pbrMat.F0 * (1.0 - r) * grazeSoft;
ambientSpec *= 0.15 * finalSkylight + pbrLocalLuma * 0.35;
if (pbrLocalLuma > 0.001) {
vec3 pbrLocalHue = clamp(pbrLocalLight / max(pbrLocalLuma, 0.0001), vec3(0.0), vec3(4.0));
ambientSpec *= mix(vec3(1.0), pbrLocalHue, smoothstep(0.004, 0.06, pbrLocalLuma) * 0.45);
}

color.rgb += specular + ambientSpec;

if (pbrMat.metalness > 0.5) {
vec3 R = reflect(-Vworld, Nworld);
float pbrSkyEnvGate = smoothstep(7.0 / 15.0, 12.0 / 15.0, finalSkylight);
vec3 envColor = getEnvironmentColor(R, sunAngle) * pbrSkyEnvGate;
if (pbrLocalLuma > 0.001) {
vec3 pbrLocalEnv = pbrLocalLight * 1.4;
envColor = mix(envColor, pbrLocalEnv, smoothstep(0.004, 0.06, pbrLocalLuma) * (1.0 - pbrSkyEnvGate));
}
vec3 envF = pbr_fresnelSchlickColor(NdotV, pbrMat.F0);
float envMul = 0.35 * PBR_METAL_TINT_STRENGTH * pbrMat.metalness * grazeSoft;
color.rgb += envColor * envF * envMul * max(max(finalSkylight, 0.2), pbrLocalLuma * 1.5);
}
}

if (pbrMat.hasData && pbrMat.porosity > 0.001 && PBR_POROSITY_STRENGTH > 0.001) {
float wetness = clamp(rainStrength, 0.0, 1.0) * smoothstep(0.5, 1.0, finalSkylight);
float wetDarken = 1.0 - 0.35 * pbrMat.porosity * PBR_POROSITY_STRENGTH * wetness;
color.rgb *= wetDarken;
}

if (pbrMat.hasData && pbrMat.hasSSS && PBR_SSS_STRENGTH > 0.001) {
vec3 L = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 V = normalize(worldPos - cameraPosition);
float VdotL = max(dot(V, L), 0.0);
float sssTerm = pow(VdotL, 3.0) * pbrMat.sss * PBR_SSS_STRENGTH;
float sssLight = dot(shadow, vec3(0.299, 0.587, 0.114)) * finalSkylight;
color.rgb += rawColor * sssTerm * sssLight * 0.8;
}

if (pbrMat.emission > 0.01) {
finalEmissive = max(finalEmissive, pbrMat.emission);
color.rgb = mix(color.rgb, rawColor * 1.5, pbrMat.emission * 0.5);
}
}
#endif

#ifdef LEAF_SHEEN_ENABLED
#ifdef MAGICAL_TOUCH
{
int bid = int(blockId + 0.5);
if ((bid == 10005 || bid == 10082) && finalEmissive < 0.5) {
vec3 worldLightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 viewDir = normalize(worldPos - cameraPosition);

float VdotL = max(dot(viewDir, worldLightDir), 0.0);
float sss = pow(VdotL, 3.0) * LEAF_SSS_STRENGTH;
vec3 sssColor = color.rgb * vec3(1.2, 1.1, 0.7) * sss * finalSkylight * shadow;

color.rgb += sssColor;
}
}
#endif
#endif

#ifdef LAVA_CRUST_ENABLED
{
int lavaBid = int(blockId + 0.5);
bool isLava = (lavaBid == 10039);
if (isLava) {
vec3 lavaN = normalize(mat3(gbufferModelViewInverse) * normal);
color.rgb = applyLavaCrust(color.rgb, worldPos, lavaN);

#ifdef BIOME_SOUL_SAND_VALLEY
if (biome == BIOME_SOUL_SAND_VALLEY) {
float lavaLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
vec3 blueLava = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * lavaLum * 2.0;
color.rgb = blueLava;
}
#endif
}
}
#endif

#ifdef BIOME_SOUL_SAND_VALLEY
{
int magmaBid = int(blockId + 0.5);
if (magmaBid == 10040 && biome == BIOME_SOUL_SAND_VALLEY) {
float magmaLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
vec3 blueMagma = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * magmaLum * 2.0;

float magmaWarmth = max(color.r - color.b, 0.0);
color.rgb = mix(color.rgb, blueMagma, smoothstep(0.05, 0.2, magmaWarmth));
}
}
#endif

if (finalEmissive < 0.5 && isEyeInWater != 1 && !isForcedNetherBiome(biome)) {
float denom = max(fogEnd - fogStart, 0.0001);
float fogFactor = clamp((fogEnd - viewDistance) / denom, 0.0, 1.0);
color.rgb = mix(getTimeBasedFogColor(), color.rgb, fogFactor);
}

#ifdef VOXY_DEBUG_BRIGHTNESS_MATCH
{
float litLuma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
color.rgb = vec3(litLuma);
}
#endif

gl_FragData[0] = color;

gl_FragData[1] = vec4(outlineMask, finalEmissive, finalSkylight, isHeatSource);

#ifdef BLOOM_ENABLED

vec3 lightColor = vec3(0.0);
#ifdef EMISSIVE_MASKING
if (emissive > 0.5 && emissiveMask >= 0.05) {
int bloomEt = int(floor(emissiveType + 0.5));
if (bloomEt == 19) {
lightColor = vec3(1.0, 0.75, 0.2) * EMISSIVE_BRIGHTNESS * 0.15;
} else if (bloomEt == 17) {

lightColor = vec3(1.0, 0.8, 0.3) * EMISSIVE_BRIGHTNESS * clamp(emissiveMask, 0.0, 1.0) * 1.5;
} else if (bloomEt == 46) {

lightColor = rawColor * EMISSIVE_BRIGHTNESS * 0.15;
} else {
lightColor = rawColor * EMISSIVE_BRIGHTNESS * clamp(emissiveMask, 0.0, 1.0);
}
}
#else
if (finalEmissive > 0.5) {
int et = int(floor(emissiveType + 0.5));
bool isWarmLight = (et == -14 || et == 0 || et == 15 || et == 16 || et == 22 || et == 30);
bool isSoulLight = (et == 1 || et == 23);
if (isWarmLight) {
lightColor = vec3(1.0, 0.85, 0.4) * EMISSIVE_BRIGHTNESS;
} else if (isSoulLight) {
lightColor = vec3(0.3, 0.7, 1.0) * EMISSIVE_BRIGHTNESS;
} else {
lightColor = rawColor * EMISSIVE_BRIGHTNESS;
}
}
#endif

if (outputHeldBloom) {
lightColor = heldBloomColor;
}

#ifdef BIOME_SOUL_SAND_VALLEY
{
int bloomBid = int(blockId + 0.5);
if ((bloomBid == 10039 || bloomBid == 10040) && biome == BIOME_SOUL_SAND_VALLEY) {
float bloomLum = dot(lightColor, vec3(0.299, 0.587, 0.114));
lightColor = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * bloomLum * 2.0;
}
}
#endif
gl_FragData[2] = vec4(lightColor, 1.0);
gl_FragData[3] = vec4(lightColor, 1.0);
#endif

#ifdef MATERIAL_REFLECTIONS_ENABLED

float ssrTextureLum = dot(pureTexColor, vec3(0.299, 0.587, 0.114));
float ssrFallbackSmoothness = smoothstep(0.08, 0.72, ssrTextureLum);
float ssrFallbackRoughness = pow(1.0 - ssrFallbackSmoothness, 2.0);

bool ssrReflectivePixel = (reflective > 0.5);
#ifdef PBR_ENABLED
float ssrPbrSmoothness = 0.0;
if (pbrMat.hasSpec && pbrMat.roughness >= 0.0) {
ssrPbrSmoothness = 1.0 - sqrt(clamp(pbrMat.roughness, 0.0, 1.0));

ssrReflectivePixel = ssrReflectivePixel
|| (ssrPbrSmoothness > 0.08)
|| (pbrMat.metalness > 0.5)
|| (pbrMat.F0scalar > 0.08);
}
#endif

if (ssrReflectivePixel && finalEmissive < 0.5) {
#ifdef PBR_ENABLED
vec3 ssrNormal = pbrNormal;
PBRMaterial ssrMat = pbrMat;

if (!ssrMat.hasSpec || ssrMat.roughness < 0.0) {
ssrMat.roughness = ssrFallbackRoughness;
}
vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * ssrNormal);
gl_FragData[TERRAIN_SSR_OUT] = pbr_packToColortex5(ssrMat, worldNormal);
#else

vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
gl_FragData[TERRAIN_SSR_OUT] = vec4(ssrFallbackRoughness, 0.0, worldNormal.x * 0.5 + 0.5, worldNormal.y * 0.5 + 0.5);
#endif
} else {
gl_FragData[TERRAIN_SSR_OUT] = vec4(0.0);
}
#endif
}
