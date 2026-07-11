#include "/settings.glsl"

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

#include "/include/color_utils.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/sky_timeline.glsl"
#include "/include/water_color.glsl"
#include "/include/volumetric_clouds.glsl"

#ifdef END_SHADER
#if defined(END_EVENT_ENABLED)
#include "/include/end_event.glsl"
#endif
#ifdef END_SKY_ENABLED
#include "/include/end_sky.glsl"
#endif
#endif

vec4 sampleFogSmooth(sampler2D tex, vec2 uv) {
vec4 fog = max(texture(tex, uv), vec4(0.0));

fog.rgb = fog.rgb * fog.rgb;
fog.rgb = fog.rgb * fog.rgb;
fog.rgb *= 32.0;
return fog;
}

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform sampler2D colortex7;
uniform sampler2D colortex14;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D dhDepthTex;
uniform sampler2D vxDepthTexTrans;
uniform mat4 vxProjInv;
uniform float near;
uniform float far;
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float sunAngle;
uniform int worldDay;
uniform int worldTime;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int biome;
uniform int biome_category;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_savanna;
uniform float biome_ocean;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;
uniform vec3 eyePosition;
uniform float rainStrength;
uniform float thunderStrength;
uniform ivec2 eyeBrightnessSmooth;

float getBloomCompStrength() {
return clamp(BLOOM_DISTANCE_COMPENSATION * 4.0, 0.0, 1.0);
}

float getBloomEffectiveDistance(float linearDepth) {
float defaultFovScale = 1.73;
float fovScale = max(gbufferProjection[1][1] / defaultFovScale, 0.35);
return linearDepth / fovScale;
}

float getBloomSourceKeep(float effectiveDist, float coverage) {
float tinySource = 1.0 - smoothstep(0.15, 0.75, coverage);
float keep = mix(0.35, 0.62, tinySource);
keep += 0.08 * smoothstep(10.0, 28.0, effectiveDist) * tinySource;
keep += 0.06 * smoothstep(28.0, 84.0, effectiveDist) * tinySource;
keep -= 0.08 * smoothstep(180.0, 320.0, effectiveDist);
return clamp(keep, 0.35, 0.68);
}

float getEmissiveCoverage(vec2 uv) {
vec2 texelSize = 1.0 / vec2(textureSize(colortex1, 0));
float coverage = 0.0;

coverage += step(0.5, texture(colortex1, uv).g) * 0.24;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x, 0.0), vec2(0.0), vec2(1.0))).g) * 0.13;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x, 0.0), vec2(0.0), vec2(1.0))).g) * 0.13;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2(0.0, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.13;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2(0.0,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.13;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.06;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.06;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.06;
coverage += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.06;

return clamp(coverage, 0.0, 1.0);
}

float getEmitterScreenSize(vec2 uv) {
vec2 texelSize = 1.0 / vec2(textureSize(colortex1, 0));
float size = 0.0;

size += step(0.5, texture(colortex1, uv).g) * 0.18;

size += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x, 0.0), vec2(0.0), vec2(1.0))).g) * 0.12;
size += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x, 0.0), vec2(0.0), vec2(1.0))).g) * 0.12;
size += step(0.5, texture(colortex1, clamp(uv + vec2(0.0, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.12;
size += step(0.5, texture(colortex1, clamp(uv + vec2(0.0,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.12;

size += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;
size += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;
size += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;
size += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;

size += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x * 2.0, 0.0), vec2(0.0), vec2(1.0))).g) * 0.05;
size += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x * 2.0, 0.0), vec2(0.0), vec2(1.0))).g) * 0.05;
size += step(0.5, texture(colortex1, clamp(uv + vec2(0.0, -texelSize.y * 2.0), vec2(0.0), vec2(1.0))).g) * 0.05;
size += step(0.5, texture(colortex1, clamp(uv + vec2(0.0,  texelSize.y * 2.0), vec2(0.0), vec2(1.0))).g) * 0.05;

return clamp(size, 0.0, 1.0);
}

in vec2 texcoord;

vec3 getHorizonColor();
vec3 getSkyCastHorizonColor();

#include "/include/depth_utils.glsl"

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

vec3 applyPosterize(vec3 color, float levels, float dither, vec2 fragCoord, int frameCount) {

float noise = fract(sin(dot(fragCoord + float(frameCount) * 0.1, vec2(12.9898, 78.233))) * 43758.5453);
noise = (noise - 0.5) * dither / levels;

color += noise;
color = floor(color * levels + 0.5) / levels;

return clamp(color, 0.0, 1.0);
}

vec3 getHeldItemLightColor(int heldId) {
if (heldId == 10021 || heldId == 10043) return vec3(0.35, 0.82, 1.0);
if (heldId == 10022 || heldId == 10039) return vec3(1.0, 0.42, 0.15);
if (heldId == 10024 || heldId == 10032 || heldId == 10044) return vec3(0.70, 0.92, 1.0);
if (heldId == 10026 || heldId == 10038 || heldId == 10058) return vec3(1.0, 0.25, 0.15);
if (heldId == 10052) return vec3(0.45, 1.00, 0.70);
if (heldId == 10053) return vec3(0.95, 0.72, 1.00);
if (heldId == 10027 || heldId == 10051) return vec3(1.0, 0.80, 0.45);
return vec3(1.0, 0.78, 0.50);
}

float saturate(in float x) {
return clamp(x, 0.0, 1.0);
}

vec3 applySafeSaturation(vec3 color, float saturationAmount) {
float baseLum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 gray = vec3(baseLum);
vec3 saturated = gray + (color - gray) * max(saturationAmount, 0.0);
saturated = max(saturated, vec3(0.0));

float satLum = dot(saturated, vec3(0.299, 0.587, 0.114));
if (satLum > 0.0001 && baseLum > 0.0001) {
saturated *= baseLum / satLum;
}

return max(saturated, vec3(0.0));
}

#include "/include/color_grading.glsl"

#include "/include/outline.glsl"

#ifdef HANDHELD_LIGHT_ENABLED
#include "/include/held_light_post.glsl"
#endif

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

#include "/include/noise.glsl"
#define BIOME_COLOR_SMOOTHING_HAS_SSBO
#include "/include/distance_fog.glsl"

void main() {
vec2 texelSize = 1.0 / vec2(textureSize(colortex0, 0));
vec2 distortedUV = texcoord;

vec3 color = texture(colortex0, distortedUV).rgb;
float cloudMask = texture(colortex0, distortedUV).a;
float cloudAlpha = 1.0 - cloudMask;
float outlineMask = texture(colortex1, texcoord).r;

#ifdef UNDERWATER_FOG_ENABLED
if (isEyeInWater == 1) {

float earlyDepth0 = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x;
float earlyVoxyM = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0).a;
bool isVoxy = (earlyVoxyM > 0.999);
bool earlySky = (earlyDepth0 >= 0.9999) && !isVoxy;
bool earlyUwSurface = false;

if (earlyUwSurface || earlySky) {
vec2 px = 1.0 / vec2(viewWidth, viewHeight);
float blurR = 2.5;

vec3 blurred = color * 0.25;
float totalWeight = 0.25;

vec2 offsets[8] = vec2[8](
vec2( px.x, 0.0) * blurR,   vec2(-px.x, 0.0) * blurR,
vec2(0.0,  px.y) * blurR,   vec2(0.0, -px.y) * blurR,
vec2( px.x,  px.y) * blurR * 0.7, vec2(-px.x,  px.y) * blurR * 0.7,
vec2( px.x, -px.y) * blurR * 0.7, vec2(-px.x, -px.y) * blurR * 0.7
);
float weights[8] = float[8](0.125, 0.125, 0.125, 0.125, 0.0625, 0.0625, 0.0625, 0.0625);

for (int i = 0; i < 8; i++) {
vec2 sampleUV = distortedUV + offsets[i];
float sD0 = texture(depthtex0, sampleUV).r;
float sD1 = texture(depthtex1, sampleUV).r;
bool sWater = (sD0 < sD1 - 0.00001);
bool sSky = (sD0 >= 0.9999);
if (sWater || sSky) {
blurred += texture(colortex0, sampleUV).rgb * weights[i];
totalWeight += weights[i];
}
}

color = blurred / totalWeight;
}
}
#endif

float fogAmount = 0.0;

vec4 glassTint = texture(colortex4, texcoord);

{
ivec2 texelCoordSBF = ivec2(gl_FragCoord.xy);
float depthAllSBF = texelFetch(depthtex0, texelCoordSBF, 0).x;
float depthOpaqueSBF = texelFetch(depthtex1, texelCoordSBF, 0).x;
float depthDHSBF = texelFetch(dhDepthTex, texelCoordSBF, 0).x;
bool isTranslucentSBF = (depthAllSBF < depthOpaqueSBF - 0.00001);
bool isGlassSBF = isTranslucentSBF && (glassTint.a > 0.45);
float vxDepthSBF = texture(vxDepthTexTrans, texcoord).r;
bool hasVoxySBF = (vxDepthSBF > 0.00001 && vxDepthSBF < 0.9999);
float voxyMarkerSBF = texture(colortex1, texcoord).a;
bool isVoxyMarkerSBF = (voxyMarkerSBF > 0.999);
bool skyBehindSBF = (depthOpaqueSBF >= 0.9999) && !hasValidDHDepth(depthDHSBF) && !hasVoxySBF && !isVoxyMarkerSBF;

if (isGlassSBF && skyBehindSBF && isEyeInWater != 1) {

vec3 skyFill = getSkyCastHorizonColor();

float glassAlpha = clamp(glassTint.a > 0.45 ? 0.45 : 0.5, 0.0, 1.0);

color = color + skyFill * (1.0 - glassAlpha);
}
}

#ifdef GLASS_FILTER_ENABLED
{
ivec2 texelCoordGF = ivec2(gl_FragCoord.xy);
float depthAllGF = texelFetch(depthtex0, texelCoordGF, 0).x;
float depthOpaqueGF = texelFetch(depthtex1, texelCoordGF, 0).x;
bool isTranslucentGF = (depthAllGF < depthOpaqueGF - 0.00001);

bool isGlassLikeGF = (glassTint.a > 0.45);

float gfStrength = clamp(glassTint.a * GLASS_FILTER_STRENGTH, 0.0, 1.0);
bool isEntityGF = (texture(colortex1, texcoord).a > 0.01 && texture(colortex1, texcoord).a < 0.99);
gfStrength *= (isTranslucentGF && isGlassLikeGF && !isEntityGF) ? 1.0 : 0.0;

if (gfStrength > 0.0001) {
vec3 tint = max(glassTint.rgb, vec3(0.0));

float tLum0 = dot(tint, vec3(0.299, 0.587, 0.114));
tint = mix(vec3(tLum0), tint, GLASS_FILTER_SATURATION);

float tLum = max(dot(tint, vec3(0.299, 0.587, 0.114)), 0.25);
vec3 tintNorm = clamp(tint / tLum, vec3(0.0), vec3(3.0));

float lum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 multiplied = color * tintNorm;
vec3 enforced = lum * tintNorm;
vec3 target = mix(multiplied, enforced, clamp(GLASS_FILTER_ENFORCEMENT, 0.0, 1.0));

color = mix(color, target, gfStrength);
}
}
#endif

bool fakeTerrainHitForFog = false;

#ifdef FAKE_TERRAIN_ENABLED
{

if (!isForcedNetherBiome(biome) && !isEndDimension()) {
float ftDepth = texture(depthtex0, texcoord).x;
float ftDhDepth = texture(dhDepthTex, texcoord).x;

float ftDhProbe1 = texture(dhDepthTex, vec2(0.5, 0.05)).x;
float ftDhProbe2 = texture(dhDepthTex, vec2(0.15, 0.05)).x;
float ftDhProbe3 = texture(dhDepthTex, vec2(0.85, 0.05)).x;
bool dhActiveForFakeTerrain = hasValidDHDepth(ftDhDepth) || hasValidDHDepth(ftDhProbe1) || hasValidDHDepth(ftDhProbe2) || hasValidDHDepth(ftDhProbe3) || (dhFarPlane > far * 1.5);
if (!dhActiveForFakeTerrain) {

} else {

bool hasDhAtFtPixel = hasValidDHDepth(ftDhDepth);
bool isSky = (ftDepth >= 0.9999 && !hasDhAtFtPixel);

bool dhBelowWater = false;
if (!isSky && ftDepth >= 0.9999 && hasDhAtFtPixel) {
vec3 dhWorldPos = getWorldPosDH(texcoord, ftDhDepth);
dhBelowWater = (dhWorldPos.y < float(FAKE_TERRAIN_Y));
}

if (isSky || dhBelowWater) {

vec4 ftClipFar = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec4 ftViewFar = gbufferProjectionInverse * ftClipFar;
ftViewFar /= ftViewFar.w;
vec3 ftRayDir = normalize(mat3(gbufferModelViewInverse) * ftViewFar.xyz);

float planeY = float(FAKE_TERRAIN_Y);
float camY = cameraPosition.y;

if (camY > planeY) {

float t = -1.0;
if (ftRayDir.y < -0.001) {

t = (planeY - camY) / ftRayDir.y;
}

if (t > 0.0 && t < FAKE_TERRAIN_DISTANCE) {
vec3 hitPos = cameraPosition + ftRayDir * t;
float hitDist = length(hitPos - cameraPosition);

if (hitDist > FAKE_TERRAIN_START) {
vec3 waterColor = vec3(WATER_COLOR_R, WATER_COLOR_G, WATER_COLOR_B);

vec3 litColor = waterLitColor(waterColor, sunAngle);

vec3 viewDir = -ftRayDir;
vec3 waterNormal = vec3(0.0, 1.0, 0.0);
vec3 viewDirView = normalize(mat3(gbufferModelView) * viewDir);
vec3 waterNormalView = normalize(mat3(gbufferModelView) * waterNormal);
litColor += waterSpecular(viewDirView, normalize(shadowLightPosition), waterNormalView, sunAngle);

vec3 reflDirView = reflect(normalize(-viewDirView), waterNormalView);
vec3 reflDirWorld = reflect(-viewDir, waterNormal);

TimeWeightsSimple ilvTS = getTimeWeightsSimple(sunAngle);
float upDot = max(dot(reflDirView, gbufferModelView[1].xyz), 0.0);
float hBias = 1.0 - upDot; hBias *= hBias; hBias *= hBias; hBias = 1.0 - hBias;
vec3 skCol = getTimelineHorizonColor(sunAngle, hBias);
float sDot = dot(reflDirView, normalize(shadowLightPosition)) * 0.5 + 0.5;
sDot = 1.0 - (1.0 - sDot) * (1.0 - sDot);
sDot *= (1.0 - upDot) * (1.0 - (1.0 - ilvTS.twilight) * (1.0 - ilvTS.twilight));
vec3 sunH = (sunAngle > 0.25 && sunAngle < 0.75)
? vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B)
: vec3(SUNRISE_HORIZON_R, SUNRISE_HORIZON_G, SUNRISE_HORIZON_B);
skCol = mix(skCol, sunH, sDot);
skCol = min(skCol, 1.0);

skCol *= 1.5;

#ifdef CLOUDS_3D_ENABLED
if (reflDirWorld.y > 0.001) {
float pxSkylight = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0).b;
float cloudSkyGate = step(12.0 / 15.0, pxSkylight);
float gameTimeSec = (float(worldDay) * 24000.0 + float(worldTime)) / 20.0;
vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 cloudReflDir = reflDirWorld;
cloudReflDir.y = max(cloudReflDir.y, 0.12);
cloudReflDir = normalize(cloudReflDir);
vec3 ftReflOrigin = vec3(cameraPosition.x, 63.0, cameraPosition.z);
vec4 ftCloudRefl = renderCloudReflection(cloudReflDir, gameTimeSec, ftReflOrigin, sunAngle, worldSunDir, gl_FragCoord.xy, frameCounter);
ftCloudRefl.a *= cloudSkyGate * 0.4;
if (ftCloudRefl.a > 0.001) {
skCol = mix(skCol, ftCloudRefl.rgb, ftCloudRefl.a);
}
}
#endif

float cosTheta = abs(dot(viewDirView, waterNormalView));
float fresnel = 1.0 - cosTheta;
fresnel *= fresnel;
fresnel *= fresnel;
float fresnelMod = mix(0.3, 1.0, fresnel) * WATER_REFLECTION_FADE;
fresnelMod = clamp(fresnelMod, 0.0, 1.0);
float reflStrength = WATER_REFLECTION_AMOUNT * fresnelMod * WATER_SKY_REFLECTION;
litColor = mix(litColor, skCol, reflStrength);

float distFade = smoothstep(FAKE_TERRAIN_DISTANCE * 0.6, FAKE_TERRAIN_DISTANCE * 0.95, hitDist);

float fadeIn = smoothstep(FAKE_TERRAIN_START, FAKE_TERRAIN_START + 32.0, hitDist);

float angleFade = smoothstep(0.0, 0.06, -ftRayDir.y);

litColor = mix(litColor, color.rgb, distFade);
float cloudProtect = 1.0 - clamp(cloudAlpha, 0.0, 1.0);
float terrainBlend = fadeIn * cloudProtect * angleFade;
color.rgb = mix(color.rgb, litColor, terrainBlend);
if (terrainBlend > 0.001) {
fakeTerrainHitForFog = true;
}
}
}
} else if (ftRayDir.y > 0.001 && camY < planeY) {

float t = (planeY - camY) / ftRayDir.y;

if (t > 0.0 && t < FAKE_TERRAIN_DISTANCE) {
vec3 hitPos = cameraPosition + ftRayDir * t;
float hitDist = length(hitPos - cameraPosition);

if (hitDist > FAKE_TERRAIN_START) {
vec3 waterColor = vec3(WATER_COLOR_R, WATER_COLOR_G, WATER_COLOR_B) * 0.2;
float fadeIn = smoothstep(FAKE_TERRAIN_START, FAKE_TERRAIN_START + 200.0, hitDist);
float cloudProtect = 1.0 - clamp(cloudAlpha, 0.0, 1.0);
float terrainBlend = fadeIn * cloudProtect;
color.rgb = mix(color.rgb, waterColor, terrainBlend);
if (terrainBlend > 0.001) {
fakeTerrainHitForFog = true;
}
}
}
}
}
}
}
}
#endif

bool postIsSky = false;
bool postFromDH = false;
vec3 postSceneWorldPos = cameraPosition;

vec4 maskData = texture(colortex1, texcoord);
float emissiveFlag = maskData.g;
bool isEmissive = emissiveFlag > 0.5;
bool isEntityPixel = (maskData.a > 0.3 && maskData.a < 0.7);
bool isVoxyLodPixel = (maskData.a > 0.999 && emissiveFlag < 0.01);

vec3 savedSunColor = color;

ivec2 texelCoord = ivec2(gl_FragCoord.xy);
float depthAll = texelFetch(depthtex0, texelCoord, 0).x;
float depthOpaque = texelFetch(depthtex1, texelCoord, 0).x;
float depthDH = texelFetch(dhDepthTex, texelCoord, 0).x;
bool hasLodDepth = (depthDH < 0.9999);
bool hasDHAtPixel = hasValidDHDepth(depthDH);

bool isTranslucentPx = (depthAll < depthOpaque - 0.00001);
bool isEntityPixelFog = (maskData.a > 0.01 && maskData.a < 0.99);
bool isWaterSurface = isTranslucentPx && glassTint.a > 0.01 && glassTint.a <= 0.45;

bool isUnderwaterSurface = (isEyeInWater == 1) && (glassTint.a > 0.20 && glassTint.a < 0.40);

bool isTranslucent = isTranslucentPx;
bool isGlass = isTranslucent && glassTint.a > 0.45;

float sceneDepth;
vec3 sceneWorldPos;
bool isSky = false;
bool sceneFromDH = false;

{

float sceneCheckDepth = (isEyeInWater == 1) ? depthOpaque : depthAll;

bool hasMCDepth = (sceneCheckDepth < 0.9999) || isVoxyLodPixel;

float vxDepthScene = texture(vxDepthTexTrans, texcoord).r;
bool hasVoxyDepth = isVoxyLodPixel && (vxDepthScene > 0.00001 && vxDepthScene < 0.9999);

float linearAll = hasMCDepth ? linearizeDepth(sceneCheckDepth) : 1e10;
float linearDH = hasDHAtPixel ? linearizeDepthDH(depthDH) : 1e10;
if (hasMCDepth && linearAll < linearDH) {
sceneDepth = sceneCheckDepth;
if (hasVoxyDepth && sceneCheckDepth >= 0.9999) {

vec4 vxClip = vxProjInv * vec4(texcoord * 2.0 - 1.0, vxDepthScene * 2.0 - 1.0, 1.0);
vec3 vxView = vxClip.xyz / vxClip.w;
sceneWorldPos = (gbufferModelViewInverse * vec4(vxView, 1.0)).xyz + cameraPosition;
} else {
sceneWorldPos = getWorldPos(texcoord, sceneDepth);
}
sceneFromDH = false;
} else if (hasDHAtPixel) {
sceneDepth = depthDH;
sceneWorldPos = getWorldPosDH(texcoord, sceneDepth);
sceneFromDH = true;
} else {
isSky = true;
sceneDepth = 1.0;
vec4 clipPos = vec4(texcoord * 2.0 - 1.0, 0.0, 1.0);
vec4 viewPos = gbufferProjectionInverse * clipPos;
vec3 viewDir = normalize(viewPos.xyz);
vec4 worldDir = gbufferModelViewInverse * vec4(viewDir, 0.0);
sceneWorldPos = cameraPosition + worldDir.xyz * far;
sceneFromDH = false;
}
}

postIsSky = isSky;
postFromDH = sceneFromDH;
postSceneWorldPos = sceneWorldPos;

#ifdef CG_POSTERIZE_ENABLED
color = applyPosterize(color, float(CG_POSTERIZE_LEVELS), CG_POSTERIZE_DITHER, gl_FragCoord.xy, frameCounter);
#endif

float volFogTransmittance = 1.0;

#ifdef WEATHER_FOG_ENABLED
volFogTransmittance *= (1.0 - max(texture(colortex11, texcoord), vec4(0.0)).a);
#endif
#ifdef HAZE_FOG_ENABLED
{
float hazeA = isSky ? 0.0 : max(texture(colortex10, texcoord), vec4(0.0)).a;
volFogTransmittance *= (1.0 - hazeA);
}
#endif
#if defined(ATMO_FOG_ENABLED) || defined(UNDERWATER_FOG_ENABLED)
volFogTransmittance *= (1.0 - max(texture(colortex9, texcoord), vec4(0.0)).a);
#endif

{
vec4 dfData = texture(colortex14, texcoord);
float dfAmount = (dfData.a < 0.5) ? dfData.r : 0.0;
fogAmount = max(1.0 - volFogTransmittance, dfAmount);
}

#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome) && isSky) fogAmount = 1.0;
#endif

#if 0
if (isTranslucentPx && !isEntityPixelFog) {
if (hasVoxyDepthFog) {
fogDepth = vxDepthFog;
vec4 vxClip = vxProjInv * vec4(texcoord * 2.0 - 1.0, vxDepthFog * 2.0 - 1.0, 1.0);
vec3 vxView = vxClip.xyz / vxClip.w;
fogWorldPos = (gbufferModelViewInverse * vec4(vxView, 1.0)).xyz + cameraPosition;
fogFromDH = false;
fogIsSky = false;
} else if (depthOpaque < 0.9999) {
float opaqueLinear = linearizeDepth(depthOpaque);
float dhLinear = hasDHAtPixel ? linearizeDepthDH(depthDH) : 1e10;
if (opaqueLinear < dhLinear) {
fogDepth = depthOpaque;
fogWorldPos = getWorldPos(texcoord, fogDepth);
fogFromDH = false;
fogIsSky = false;
} else {
fogDepth = depthDH;
fogWorldPos = getWorldPosDH(texcoord, fogDepth);
fogFromDH = true;
fogIsSky = false;
}
} else if (hasDHAtPixel) {
fogDepth = depthDH;
fogWorldPos = getWorldPosDH(texcoord, fogDepth);
fogFromDH = true;
fogIsSky = false;
} else {

fogDepth = depthAll;
fogWorldPos = getWorldPos(texcoord, fogDepth);
fogFromDH = false;
fogIsSky = false;
}
}

vec4 fog = (isEyeInWater == 2) ? vec4(0.0, 0.0, 0.0, 1.0) : computeVolumetricFog(texcoord, fogDepth, fogWorldPos, fogIsSky, fogFromDH);

#ifdef OVERWORLD_FOG_ENABLED
if (isEyeInWater == 1 && !isForcedNetherBiome(biome) && !isEndDimension()) {
fog = vec4(0.0, 0.0, 0.0, 1.0);
}

if (isEyeInWater != 1 && !isForcedNetherBiome(biome) && !isEndDimension()) {

bool isUnderwaterOpaque = !isTranslucentPx && sceneWorldPos.y < float(SEA_LEVEL_OFFSET);
if (isWaterSurface || isUnderwaterOpaque) {
float underwaterFogFade = smoothstep(float(SEA_LEVEL_OFFSET) - 4.0, float(SEA_LEVEL_OFFSET) + 1.0, sceneWorldPos.y);
if (isWaterSurface) underwaterFogFade = 0.0;
fog.rgb *= underwaterFogFade;
fog.a = mix(1.0, fog.a, underwaterFogFade);
}
}
#endif
fogScatter = fog.rgb;
fogTrans = clamp(fog.a, 0.0, 1.0);
fogAmountLocal = clamp(1.0 - fogTrans, 0.0, 1.0);

#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome) && isSky) {
vec3 netherSkyFog = getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B)) * NETHER_BRIGHTNESS;
color = netherSkyFog;
fogAmountLocal = 1.0;
}
#endif

fogAmountLocal *= cloudMask;
fogScatter *= cloudMask;
fogTrans = 1.0 - fogAmountLocal;

if (fogAmountLocal > 0.001) {

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
vec3 additiveResult = color * (1.0 - fogAmountLocal * 0.25) + fogScatter;
vec3 standardResult = color * fogTransLocal + fogScatter;

#ifdef END_EVENT_ENABLED
float endBlendDark = getEndEvent(frameTimeCounter).fogDarkness;
float totalMixWeight = endBlendDark;
#else
float totalMixWeight = 0.0;
#endif

color = mix(additiveResult, standardResult, totalMixWeight);
}
#else

color = color * fogTrans + fogScatter;
#endif
fogAmount = max(fogAmount, fogAmountLocal);
volFogTransmittance *= fogTrans;
}
}
#endif

#if 0

#ifdef HAZE_FOG_ENABLED
{
vec4 haze = max(texture(colortex10, texcoord), vec4(0.0));
if (postIsSky) haze = vec4(0.0);
if (haze.a > 0.001) {
color = haze.rgb + color * (1.0 - haze.a);
}
}
#endif

#ifdef WEATHER_FOG_ENABLED
{
vec4 weatherFog = max(texture(colortex11, texcoord), vec4(0.0));
if (weatherFog.a > 0.001) {
color = weatherFog.rgb + color * (1.0 - weatherFog.a);
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

if (!postIsSky) {
#ifdef WEATHER_FOG_ENABLED
float weatherAlpha = max(texture(colortex11, texcoord), vec4(0.0)).a;
combined *= weatherAlpha * 0.5;
#else
combined = 0.0;
#endif
}
combined *= smoothstep(0.0, 0.15, max(rainStrength, biome_swamp));

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
if (!postIsSky) moonCombined = 0.0;

}
}
}
#endif
#endif

#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
if (isEndDimension() && !postIsSky) {
float horrorEventDark = getEndEvent(frameTimeCounter).fogDarkness;
if (horrorEventDark > 0.001) {
vec3 preHorrorColor = color;
float horrorSceneDist = length(postSceneWorldPos - cameraPosition);
float horrorRange = 20.0;
float horrorT = clamp(horrorSceneDist / horrorRange, 0.0, 1.0);
float horrorFog = 1.0 - exp(-horrorT * horrorT * 8.0);
horrorFog *= horrorEventDark;
color = mix(color, vec3(0.0), horrorFog);
#ifdef HANDHELD_LIGHT_ENABLED
color += getPostHandheldLightBoost(postSceneWorldPos, preHorrorColor, color) * horrorEventDark;
#endif
fogAmount = max(fogAmount, horrorFog);
}
}
#endif

#if defined(END_SHADER) && defined(END_SKY_ENABLED) && defined(END_VOID_CLOUDS_ENABLED)
if (isEndDimension() && !postIsSky) {
float vcSceneDist = length(postSceneWorldPos - cameraPosition);
vec3 vcDir = normalize(postSceneWorldPos - cameraPosition);
#ifdef END_EVENT_ENABLED
EndEvent vcEvent = getEndEvent(frameTimeCounter);
vec4 vcClouds = endVoidClouds(vcDir, vcEvent.cloudTime, frameTimeCounter, cameraPosition, vcSceneDist, vcEvent.suctionWarp);
#else
vec4 vcClouds = endVoidClouds(vcDir, frameTimeCounter, frameTimeCounter, cameraPosition, vcSceneDist, 0.0);
#endif
if (vcClouds.a > 0.001) {
vec3 vcCloudRGB = vcClouds.rgb / vcClouds.a;
#ifdef END_EVENT_ENABLED
float vcAlpha = vcClouds.a * vcEvent.effectsFade;
#else
float vcAlpha = vcClouds.a;
#endif
color = mix(color, vcCloudRGB, vcAlpha);
}
}
#endif

#if defined(END_SHADER) && defined(END_SKY_ENABLED) && defined(END_ENDER_PARTICLES_ENABLED)
if (isEndDimension()) {
float epSceneDist = postIsSky ? END_ENDER_PARTICLE_RANGE : length(postSceneWorldPos - cameraPosition);
vec3 epDir = postIsSky ? normalize(mat3(gbufferModelViewInverse) * (gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0)).xyz) : normalize(postSceneWorldPos - cameraPosition);
vec3 particles = endEnderParticles(epDir, frameTimeCounter, cameraPosition, epSceneDist);
#ifdef END_EVENT_ENABLED
particles *= getEndEvent(frameTimeCounter).effectsFade;
#endif
color += particles;
}
#endif

#if defined(END_SHADER) && defined(END_SKY_ENABLED) && defined(END_RINGS_ENABLED)
if (isEndDimension()) {
vec3 ringDir = normalize(mat3(gbufferModelViewInverse) * (gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0)).xyz);
float ringMaxDist = postIsSky ? 10000.0 : length(postSceneWorldPos - cameraPosition);
vec3 rings = endRings(ringDir, frameTimeCounter, cameraPosition, ringMaxDist);
#ifdef END_EVENT_ENABLED
rings *= getEndEvent(frameTimeCounter).effectsFade;
#endif
color += rings;
}
#endif

#if defined(END_SHADER) && defined(END_EVENT_ENABLED) && defined(END_EVENT_EYE_ENABLED) && defined(END_EVENT_SPOTLIGHT_ENABLED)
{
EndEvent ebEvent = getEndEvent(frameTimeCounter);
if (isEndDimension() && ebEvent.eyeOpen > 0.01) {

ivec2 ebTexel = ivec2(gl_FragCoord.xy);
float ebDepthMC = texelFetch(depthtex0, ebTexel, 0).x;
float ebDepthDH = texelFetch(dhDepthTex, ebTexel, 0).x;
bool ebHasDH = hasValidDHDepth(ebDepthDH);

vec4 ebClipPos = vec4(texcoord * 2.0 - 1.0, 0.5, 1.0);
vec4 ebViewPos = gbufferProjectionInverse * ebClipPos;
vec3 ebViewDir = normalize(ebViewPos.xyz);
vec4 ebWorldDir4 = gbufferModelViewInverse * vec4(ebViewDir, 0.0);
vec3 ebRayDir = normalize(ebWorldDir4.xyz);

float ebMaxDist = 1000.0;
bool ebIsSky = (ebDepthMC >= 0.9999 && !ebHasDH);
if (!ebIsSky) {
vec3 ebWorldPos = vec3(0.0);
if (ebDepthMC < 0.9999) {
ebWorldPos = getWorldPos(texcoord, ebDepthMC);
} else if (ebHasDH) {
ebWorldPos = getWorldPosDH(texcoord, ebDepthDH);
} else {
ebIsSky = true;
}
if (!ebIsSky) ebMaxDist = length(ebWorldPos - cameraPosition);
}

vec3 ebBeamCenter = vec3(eyePosition.x, 0.0, eyePosition.z);
float ebBeamRadius = END_EVENT_SPOTLIGHT_RADIUS;
float ebBeamBottom = eyePosition.y - 1.6;
float ebBeamTop = ebBeamBottom + 300.0;

vec2 ebOC = cameraPosition.xz - ebBeamCenter.xz;
vec2 ebDxz = ebRayDir.xz;
float ebA = dot(ebDxz, ebDxz);
float ebB = 2.0 * dot(ebOC, ebDxz);
float ebC = dot(ebOC, ebOC) - ebBeamRadius * ebBeamRadius;
float ebDisc = ebB * ebB - 4.0 * ebA * ebC;

float ebBeam = 0.0;
if (ebDisc > 0.0 && ebA > 0.0001) {
float ebSqrtDisc = sqrt(ebDisc);
float ebT1 = (-ebB - ebSqrtDisc) / (2.0 * ebA);
float ebT2 = (-ebB + ebSqrtDisc) / (2.0 * ebA);

float ebTMax = ebIsSky ? 1000.0 : ebMaxDist;
ebT1 = max(ebT1, 0.0);
ebT2 = min(ebT2, ebTMax);

if (ebT2 > ebT1) {

if (abs(ebRayDir.y) > 0.0001) {
float ebTBot = (ebBeamBottom - cameraPosition.y) / ebRayDir.y;
float ebTTop = (ebBeamTop - cameraPosition.y) / ebRayDir.y;
if (ebTBot > ebTTop) { float tmp = ebTBot; ebTBot = ebTTop; ebTTop = tmp; }
ebT1 = max(ebT1, ebTBot);
ebT2 = min(ebT2, ebTTop);
} else {

if (cameraPosition.y < ebBeamBottom || cameraPosition.y > ebBeamTop) {
ebT2 = ebT1;
}
}

if (ebT2 > ebT1) {

float ebPathLen = ebT2 - ebT1;

ebBeam = ebPathLen / (ebBeamRadius * 2.0);

vec2 ebMidXZ = cameraPosition.xz + ebDxz * ((ebT1 + ebT2) * 0.5) - ebBeamCenter.xz;
float ebMidDist = length(ebMidXZ);
float ebEdgeFade = smoothstep(ebBeamRadius, ebBeamRadius * 0.3, ebMidDist);
ebBeam *= ebEdgeFade;

float ebMidY = cameraPosition.y + ebRayDir.y * ((ebT1 + ebT2) * 0.5);
float ebTopFade = smoothstep(ebBeamTop, ebBeamTop - 60.0, ebMidY);
ebBeam *= ebTopFade;
}
}
}

float ebExposureBase = mix(1.0, 0.35, ebEvent.eyeOpen);
float ebProtect = 0.0;
if (!ebIsSky) {

vec3 ebPixelWorld;
if (ebDepthMC < 0.9999) {
ebPixelWorld = getWorldPos(texcoord, ebDepthMC);
} else if (ebHasDH) {
ebPixelWorld = getWorldPosDH(texcoord, ebDepthDH);
} else {
ebPixelWorld = cameraPosition;
}

float ebGroundDist = length(ebPixelWorld.xz - eyePosition.xz);
float ebSpotProtect = 1.0 - smoothstep(END_EVENT_SPOTLIGHT_RADIUS * 0.3, END_EVENT_SPOTLIGHT_RADIUS * 1.2, ebGroundDist);

float ebEntityDist = length(ebPixelWorld - eyePosition);
float ebEntityProtect = 1.0 - smoothstep(1.0, 3.0, ebEntityDist);
ebProtect = max(ebSpotProtect, ebEntityProtect);
}
float ebExposureDark = mix(ebExposureBase, 1.0, ebProtect);
color *= ebExposureDark;

vec3 ebColor = vec3(
END_EVENT_EYE_IRIS_R * 0.4 + 0.6,
END_EVENT_EYE_IRIS_G * 0.2 + 0.5,
END_EVENT_EYE_IRIS_B * 0.3 + 0.7
);

color += ebColor * ebBeam * ebEvent.eyeOpen * END_EVENT_SPOTLIGHT_INTENSITY * 0.4;

float ebChaos = ebEvent.eyeOpen;
float ebOutside = 1.0 - clamp(ebBeam * 3.0 + ebProtect, 0.0, 1.0);

float ebLuma = dot(color, vec3(0.299, 0.587, 0.114));
color = mix(color, vec3(ebLuma), ebOutside * ebChaos * 0.65);

vec3 ebEerieTint = vec3(0.35, 0.15, 0.65);
color = mix(color, color * ebEerieTint * 2.5, ebOutside * ebChaos * 0.3);

float ebVigDist = length(texcoord - vec2(0.5));
float ebVignette = smoothstep(0.25, 0.8, ebVigDist);
color *= 1.0 - ebVignette * ebChaos * 0.8;
}
}
#endif

#if OUTLINES != 0 && !defined(NEON_GAME_MODE)
ivec2 screenTexelCoord = ivec2(gl_FragCoord.xy);

float volFogAmount = 1.0 - volFogTransmittance;
float outlineFadeFog = smoothstep(0.35, 0.0, max(fogAmount, volFogAmount));

float olSkylight = texture(colortex1, texcoord).b;
float olCaveGate = 1.0 - smoothstep(1.0 / 15.0, 3.0 / 15.0, olSkylight);
float olDepth = texture(depthtex0, texcoord).r;
float olDist = (olDepth < 0.9999) ? linearizeDepth(olDepth) : 0.0;
float outlineFadeCave = 1.0 - smoothstep(10.0, 40.0, olDist);
float outlineFade = mix(outlineFadeFog, outlineFadeCave, olCaveGate) * (1.0 - rainStrength);

float outlineWaterMask = isWaterSurface ? 0.0 : 1.0;
float outlineCloudMask = 1.0;
#if defined(CLOUDS_3D_ENABLED) || defined(CLOUDS_VANILLA_ENABLED)

float cloudCover = clamp(cloudAlpha, 0.0, 1.0);
outlineCloudMask = 1.0 - smoothstep(0.02, 0.20, cloudCover);
#endif
bool outlineIsDH = postFromDH && !postIsSky;
vec3 outlineColorSample = color;
float outlineDhGreenMask = getDHGreenOutlineMask(outlineColorSample, outlineIsDH);
float outlineVoxyMask = 1.0;
#ifndef VOXY_LOD_OUTLINES
if (isVoxyLodPixel) outlineVoxyMask = 0.0;
#endif
float outlineStrength = getOutline(screenTexelCoord) * outlineMask * outlineFade * outlineWaterMask * outlineCloudMask * outlineDhGreenMask * outlineVoxyMask;
color *= 1.0 + outlineStrength * OUTLINE_BRIGHTNESS;
float outlineLuma = dot(color, vec3(0.299, 0.587, 0.114));
vec3 saturatedOutlineColor = mix(vec3(outlineLuma), color, max(OUTLINE_SATURATION, 0.0));
color = mix(color, max(saturatedOutlineColor, vec3(0.0)), clamp(outlineStrength, 0.0, 1.0));
#endif

#ifdef BLOOM_ENABLED
vec2 bloomTexelSize = 1.0 / vec2(textureSize(colortex2, 0));
vec2 bloomUv = clamp(texcoord * BLOOM_RENDER_SCALE, bloomTexelSize * 0.5, vec2(BLOOM_RENDER_SCALE) - bloomTexelSize * 0.5);
vec3 bloomWide = texture(colortex2, bloomUv).rgb;
vec3 bloomTight = texture(colortex3, bloomUv).rgb;
vec3 bloom = bloomWide + bloomTight;

if (emissiveFlag >= 0.5 && !isSky) {
bloom = vec3(0.0);
}

#ifdef END_SHADER
if (isSky) bloom = vec3(0.0);
#endif

bloom *= sqrt(BLOOM_RADIUS / 0.3);
#ifdef END_SHADER
bloom *= END_BLOOM_BOOST;
#endif

#ifdef ATMO_FOG_ENABLED
if (isEyeInWater != 1) {
vec4 atmoFog = max(texture(colortex9, texcoord), vec4(0.0));
float fogPxSkylight = postIsSky ? 1.0 : texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0).b;
float outdoorBloom = smoothstep(0.4, 0.8, fogPxSkylight);
bloom += atmoFog.rgb * atmoFog.a * outdoorBloom * 0.5;
}
#endif

bloom = applySafeSaturation(bloom, BLOOM_SATURATION);

float bloomFloor = (isEyeInWater == 1) ? 0.0 : 0.3;

vec4 distFogData = texture(colortex14, texcoord);
float distFogAmount = (distFogData.a < 0.5) ? distFogData.r : 0.0;
volFogTransmittance *= (1.0 - distFogAmount);
#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome)) bloomFloor = 0.05;
#endif

#ifdef CAVE_FOG_ENABLED
#ifndef END_SHADER
if (!isForcedNetherBiome(biome))
{

bool caveTransOverwrite = (depthAll < depthOpaque - 0.00001);
float caveSkylight = caveTransOverwrite ? 1.0 : texture(colortex1, texcoord).b;
float caveFogGate = 1.0 - smoothstep(1.0 / 15.0, 3.0 / 15.0, caveSkylight);
if (caveFogGate > 0.01) {

bloomFloor = mix(bloomFloor, 0.0, caveFogGate);
float caveDepthRaw = texture(depthtex0, texcoord).r;
if (caveDepthRaw < 0.9999) {
float caveDist = linearizeDepth(caveDepthRaw);
float caveBloomFade = smoothstep(3.0, 20.0, caveDist) * caveFogGate;
volFogTransmittance *= 1.0 - caveBloomFade;
}
}
}
#endif
#endif
bloom *= max(volFogTransmittance, bloomFloor);

color += bloom;
#endif

#if !defined(NETHER_SHADER) && !defined(END_SHADER)
{
vec2 sunUV = getSunScreenUV();
float glowAngle = fract(sunAngle);

float sunrise = smoothstep(0.0, 0.03, glowAngle) * smoothstep(0.10, 0.06, glowAngle);
float sunset  = smoothstep(0.40, 0.44, glowAngle) * smoothstep(0.48, 0.46, glowAngle);
float noon    = smoothstep(0.10, 0.20, glowAngle) * smoothstep(0.40, 0.30, glowAngle);
float sunVis  = max(sunrise, sunset) + noon * 0.35;
if (isEyeInWater != 1 && sunUV.x > -0.5 && sunVis > 0.001) {
vec2 delta = texcoord - sunUV;
delta.x *= viewWidth / viewHeight;
float dist = length(delta);
float r = SUN_GLOW_RADIUS * 0.7;
float glow = 1.0 / (1.0 + pow(dist / r, 2.5));

float glowOcclusion;
bool isCloudOrSky = (isSky || (cloudAlpha > 0.1) || isGlass) && !isEntityPixel;
if (isCloudOrSky) {
glowOcclusion = 1.0;
} else {

vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);
vec2 toSun = normalize(sunUV - texcoord) * texelSize;
float skyCount = 0.0;
for (int i = 1; i <= 8; i++) {
vec2 sampleUV = texcoord + toSun * float(i) * 2.0;
float sDepth = (isEyeInWater == 1) ? texture(depthtex1, sampleUV).r : texture(depthtex0, sampleUV).r;
float sCloud = 1.0 - texture(colortex0, sampleUV).a;
bool sSkyOrCloud = (sDepth >= 0.9999) || (sCloud > 0.1);
if (sSkyOrCloud) skyCount += 1.0;
}

float leak = smoothstep(4.0, 7.0, skyCount);
glowOcclusion = leak * 0.5;
if (isVoxyLodPixel || isEntityPixel) glowOcclusion = 0.0;
}

if (glowOcclusion > 0.01) {
glow *= sunVis * SUN_GLOW_INTENSITY * 0.15 * glowOcclusion;
vec3 glowColor = getSkyCastHorizonColor();
float glowLum = dot(glowColor, vec3(0.299, 0.587, 0.114));
if (glowLum < 0.1) glowColor = vec3(1.0, 0.95, 0.8);
else glowColor /= glowLum;
glow *= 1.0 - clamp(fogAmount * 0.8, 0.0, 1.0);
glow *= 1.0 - smoothstep(0.15, 0.70, rainStrength);
glow *= 1.0 - clamp(biome_swamp, 0.0, 1.0);
color += glowColor * glow;
}
}
}
#endif

#if !defined(NETHER_SHADER) && !defined(END_SHADER)
{
float agAngle = fract(sunAngle);

float afterglowStrength = smoothstep(0.38, 0.44, agAngle) * smoothstep(0.60, 0.50, agAngle);

if (afterglowStrength > 0.001 && isEyeInWater != 1) {
vec3 agWorldDir = normalize(mat3(gbufferModelViewInverse) * normalize(vec3(
(texcoord.x * 2.0 - 1.0) / gbufferProjection[0][0],
(texcoord.y * 2.0 - 1.0) / gbufferProjection[1][1],
-1.0)));

float horizonGlow = exp(-agWorldDir.y * agWorldDir.y * 20.0);

float agMask = isSky ? 1.0 : cloudAlpha * 0.5;

float agAmount = afterglowStrength * horizonGlow * agMask * SUN_GLOW_INTENSITY * 0.3;
agAmount *= 1.0 - smoothstep(0.15, 0.70, rainStrength);
agAmount *= 1.0 - clamp(biome_swamp, 0.0, 1.0);

float agTimeProg = smoothstep(0.38, 0.56, agAngle);
vec3 agColor = mix(vec3(1.0, 0.95, 0.5), vec3(0.85, 0.3, 0.5), agTimeProg);

color += agColor * agAmount;
}
}
#endif

#if !defined(NETHER_SHADER) && !defined(END_SHADER)
#if SUN_BRIGHTNESS_BOOST > 0.0
{
vec2 sunUV = getSunScreenUV();
if (sunUV.x > -0.5) {

vec2 delta = texcoord - sunUV;
delta.x *= viewWidth / viewHeight;
float sunDist = length(delta);

float lookFactor = 1.0 / (1.0 + sunDist * sunDist * 4.0);

float angle = fract(sunAngle);
float dayFactor = smoothstep(0.02, 0.07, angle) * smoothstep(0.48, 0.44, angle);

float weatherFade = (1.0 - smoothstep(0.1, 0.6, rainStrength)) * (1.0 - clamp(fogAmount * 0.8, 0.0, 1.0));

float boost = lookFactor * dayFactor * weatherFade * SUN_BRIGHTNESS_BOOST;
boost *= 1.0 - clamp(biome_swamp, 0.0, 1.0);

}
}
#endif
#endif

{

#ifdef POST_SHARPEN
{
vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);
vec3 n = texture(colortex0, texcoord + vec2(0.0,  texelSize.y)).rgb;
vec3 s = texture(colortex0, texcoord + vec2(0.0, -texelSize.y)).rgb;
vec3 e = texture(colortex0, texcoord + vec2( texelSize.x, 0.0)).rgb;
vec3 w = texture(colortex0, texcoord + vec2(-texelSize.x, 0.0)).rgb;
vec3 blur = (n + s + e + w) * 0.25;
color = color + (color - blur) * POST_SHARPEN_STRENGTH;
}
#endif

color = (color - 0.5) * POST_CONTRAST + 0.5 + POST_BRIGHTNESS;

float luma = dot(color, vec3(0.299, 0.587, 0.114));
color = mix(vec3(luma), color, POST_SATURATION);

#ifdef Y_FADE_ENABLED
{
if (!postIsSky) {
float yFade = 1.0 - smoothstep(YFADE_BOTTOM_Y, YFADE_TOP_Y, postSceneWorldPos.y);
vec3 fadeColor = vec3(YFADE_COLOR_R, YFADE_COLOR_G, YFADE_COLOR_B);
color = mix(color, fadeColor, yFade * YFADE_OPACITY);
}
}
#endif

#ifdef COLOR_GRADING_ENABLED
color = applyColorGrading(color, texcoord, frameTimeCounter, frameCounter);
#endif
}

#ifdef LAVA_FOG_ENABLED

if (isEyeInWater == 2) {
vec3 lavaFogCol = vec3(0.75, 0.28, 0.03);
vec3 lavaYellow = vec3(0.95, 0.65, 0.1);
#ifdef BIOME_SOUL_SAND_VALLEY
if (biome == BIOME_SOUL_SAND_VALLEY) {
lavaFogCol = vec3(0.01, 0.45, 0.65);
lavaYellow = vec3(0.1, 0.6, 0.85);
}
#endif
float lavaLinear = isSky ? 100.0 : linearizeDepth(depthAll);
float lavaFogAmt = 1.0 - exp(-lavaLinear * 1.5);

vec2 vigUV = texcoord * 2.0 - 1.0;
float vignette = dot(vigUV, vigUV);
float yellowVig = smoothstep(0.3, 1.2, vignette) * 0.3;

vec3 finalFogCol = mix(lavaFogCol, lavaYellow, yellowVig);
color = mix(color, finalFogCol, clamp(lavaFogAmt, 0.0, 1.0));
}
#endif
#ifdef VOXY_DEBUG_BRIGHTNESS_MATCH

{
vec4 debugSample = texture(colortex0, texcoord);
gl_FragColor = vec4(debugSample.rgb, 1.0);
return;
}
#endif
gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
