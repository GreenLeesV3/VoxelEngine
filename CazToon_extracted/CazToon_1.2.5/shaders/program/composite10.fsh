#include "/settings.glsl"

/* RENDERTARGETS: 9 */

#if defined(ATMO_FOG_ENABLED) || defined(UNDERWATER_FOG_ENABLED) || defined(CAVE_FOG_ENABLED)

#include "/include/shadow.glsl"
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

#define BIOME_COLOR_SMOOTHING_HAS_SSBO
#include "/include/biome_color_smoothing.glsl"

in vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex5;
uniform sampler2D colortex9;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor1;
uniform sampler2D dhDepthTex;
uniform sampler2D noisetex;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 vxProjInv;
uniform sampler2D vxDepthTexTrans;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float sunAngle;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform int biome;
uniform int biome_category;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_savanna;
uniform float biome_beach;
uniform float biome_ocean;
uniform int isEyeInWater;

#ifdef LPV_ENABLED
#include "/include/lpv/lpv_common.glsl"
uniform sampler3D lpvLightSamplerA;
uniform sampler3D lpvLightSamplerB;
uniform usampler3D lpvVoxelSampler;

vec3 caveFogLpvTap(vec3 uv) {
return (frameCounter & 1) == 0 ? texture(lpvLightSamplerA, uv).rgb : texture(lpvLightSamplerB, uv).rgb;
}
vec3 caveFogLpvBlurred(vec3 uv) {
vec3 texel = 1.0 / lpvVolumeSize;
vec3 sum = caveFogLpvTap(uv) * 2.0;
sum += caveFogLpvTap(clamp(uv + vec3(texel.x, 0.0, 0.0), vec3(0.0), vec3(1.0)));
sum += caveFogLpvTap(clamp(uv - vec3(texel.x, 0.0, 0.0), vec3(0.0), vec3(1.0)));
sum += caveFogLpvTap(clamp(uv + vec3(0.0, texel.y, 0.0), vec3(0.0), vec3(1.0)));
sum += caveFogLpvTap(clamp(uv - vec3(0.0, texel.y, 0.0), vec3(0.0), vec3(1.0)));
return sum / 6.0;
}

float caveFogLitCull(vec3 lpvFogLight) {
return 1.0 - smoothstep(0.0040, 0.0140, getLpvLuma(lpvFogLight));
}

float caveFogLpvSourceGate(vec3 lpvVox) {
ivec3 baseTexel = voxelToTexel(lpvVox);
float sourceGate = 0.0;

for (int z = -1; z <= 1; z++) {
for (int y = -1; y <= 1; y++) {
for (int x = -1; x <= 1; x++) {
ivec3 texel = clamp(baseTexel + ivec3(x, y, z), ivec3(0), lpvTexelSize - ivec3(1));
int blockId = int(texelFetch(lpvVoxelSampler, texel, 0).r) - 1;
float emitLuma = getLpvLuma(getLpvEmitColor(blockId));
if (emitLuma > 0.001) {
float dist = length((vec3(texel) + vec3(0.5)) - lpvVox);
float sourceFade = 1.0 - smoothstep(0.30, 1.45, dist);
sourceFade = pow(sourceFade, 0.45);
float emitGate = smoothstep(0.02, 0.20, emitLuma);
sourceGate = max(sourceGate, sourceFade * emitGate);
}
}
}
}

return sourceGate;
}
#endif
uniform ivec2 eyeBrightnessSmooth;

#include "/include/noise.glsl"
#include "/include/sky_timeline.glsl"

float afFogDensity(vec3 pos) {
float n = noise3D(pos);
n += 0.50 * noise3D(pos * 1.97);
n /= 1.50;
return n;
}

float caveFogDensityField(vec3 worldPos) {
vec3 p = worldPos * 0.050;
float n = afFogDensity(p);
float presence = smoothstep(0.20, 0.78, n);
return mix(0.35, 1.15, presence);
}

#ifdef SHADOWS_ENABLED
float caveFogSunVisibility(vec3 worldPos, float sunUp) {
if (sunUp <= 0.001) return 0.0;

vec3 scenePos = worldPos - cameraPosition;
vec4 shadowClipPos = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shadowNdc = distortShadowClipPos(shadowClipPos.xyz);
vec3 shadowScreenPos = shadowNdc * 0.5 + 0.5;
shadowScreenPos.z -= 0.001;

vec2 edgeDist = min(shadowScreenPos.xy, 1.0 - shadowScreenPos.xy);
float edgeFade = smoothstep(0.0, 0.05, min(edgeDist.x, edgeDist.y));

if (shadowScreenPos.x <= 0.0 || shadowScreenPos.x >= 1.0 ||
shadowScreenPos.y <= 0.0 || shadowScreenPos.y >= 1.0 ||
shadowScreenPos.z <= 0.0 || shadowScreenPos.z >= 1.0 ||
edgeFade <= 0.001) {
return 0.0;
}

float sunVisibility = step(shadowScreenPos.z, texture(shadowtex1, shadowScreenPos.xy).r);
return sunVisibility * edgeFade * sunUp;
}
#endif

#include "/include/depth_utils.glsl"

void main() {

vec2 fogRayTexcoord = (floor(gl_FragCoord.xy) / FOG_RENDER_SCALE + 0.5) / vec2(viewWidth, viewHeight);
#define texcoord fogRayTexcoord

vec4 caveFogOut = vec4(0.0);

if (isEyeInWater == 2) {
gl_FragData[0] = vec4(0.0);
return;
}

if (isForcedNetherBiome(biome)) {
gl_FragData[0] = vec4(0.0);
return;
}
#ifdef END_SHADER
gl_FragData[0] = vec4(0.0);
return;
#else
#ifdef CAT_THE_END
if (biome_category == CAT_THE_END) {
gl_FragData[0] = vec4(0.0);
return;
}
#endif
#endif

#ifdef UNDERWATER_FOG_ENABLED
if (isEyeInWater == 1) {

float uwDepth0 = min(texture(depthtex0, texcoord).r, texture(depthtex1, texcoord).r);
float uwMaxDist;
vec3 uwRayDir;
bool uwHitsAboveSurface = false;

if (uwDepth0 < 1.0) {
vec4 uwClipPos = vec4(texcoord * 2.0 - 1.0, uwDepth0 * 2.0 - 1.0, 1.0);
vec4 uwViewPos = gbufferProjectionInverse * uwClipPos;
uwViewPos /= uwViewPos.w;
vec3 uwWorldPos = (gbufferModelViewInverse * uwViewPos).xyz + cameraPosition;
uwRayDir = normalize(uwWorldPos - cameraPosition);
uwMaxDist = length(uwWorldPos - cameraPosition);

float uwWaterSurface = float(SEA_LEVEL_OFFSET) - 0.125;
if (uwWorldPos.y > uwWaterSurface - 0.5) {
uwHitsAboveSurface = true;

float surfaceDist = max(uwWaterSurface - cameraPosition.y, 0.1);
float upComponent = max(uwRayDir.y, 0.01);
uwMaxDist = min(uwMaxDist, surfaceDist / upComponent);
}
} else {
float uwDhDepth = texture(dhDepthTex, texcoord).r;
if (hasValidDHDepth(uwDhDepth)) {
float uwDhLinear = linearizeDepthDH(uwDhDepth);
vec4 uwClipFar = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec4 uwViewPosFar = gbufferProjectionInverse * uwClipFar;
vec3 uwViewDir = normalize(uwViewPosFar.xyz / max(uwViewPosFar.w, 0.0001));
uwMaxDist = uwDhLinear / max(-uwViewDir.z, 0.001);
uwRayDir = normalize(mat3(gbufferModelViewInverse) * uwViewDir);

vec3 uwDhWorldPos = cameraPosition + uwRayDir * uwMaxDist;
uwHitsAboveSurface = (uwDhWorldPos.y > float(SEA_LEVEL_OFFSET) - 0.625);
} else {

uwHitsAboveSurface = true;
vec4 uwVd4 = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
uwRayDir = normalize(mat3(gbufferModelViewInverse) * (uwVd4.xyz / uwVd4.w));

float surfaceDist = max(float(SEA_LEVEL_OFFSET) - 0.125 - cameraPosition.y, 0.1);

float upComponent = max(uwRayDir.y, 0.01);
uwMaxDist = surfaceDist / upComponent;
}
}

float uwSwampDistScale = mix(1.0, 0.3, biome_swamp);
float uwSwampStart = mix(UNDERWATER_FOG_START, 0.0, biome_swamp);
float uwSwampMaxDist = mix(float(UNDERWATER_FOG_DISTANCE), 5.0, biome_swamp);
uwMaxDist = min(uwMaxDist, uwSwampMaxDist);

float uwExtCoeff = mix(UNDERWATER_FOG_DENSITY * 0.008, 0.6, biome_swamp);
float uwFogDist = max(uwMaxDist - uwSwampStart, 0.0);
float uwTransmittance = exp(-uwFogDist * uwExtCoeff);
float uwFogOpacity = 1.0 - uwTransmittance;

vec3 uwSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
vec3 uwMoonDir = normalize(mat3(gbufferModelViewInverse) * moonPosition);
float uwSunDot = dot(uwRayDir, uwSunDir);
float uwSunFactor = uwSunDot * 0.5 + 0.5;
uwSunFactor = pow(uwSunFactor, 2.0);

float nightFade = 1.0 - smoothstep(-0.05, 0.3, uwSunDir.y);

float uwSunHeight = uwSunDir.y;
float sunsetFade = smoothstep(0.0, 0.15, uwSunHeight) * (1.0 - smoothstep(0.15, 0.35, uwSunHeight));
sunsetFade = pow(sunsetFade, 0.7);

vec3 uwDarkDay  = vec3(0.12, 0.22, 0.50);
vec3 uwBrightDay = vec3(0.25, 0.94, 1.0);

vec3 uwDarkSunset  = vec3(0.60, 0.22, 0.05);
vec3 uwBrightSunset = vec3(1.0, 0.80, 0.15);

vec3 uwDarkNight  = vec3(0.10, 0.18, 0.42);
vec3 uwBrightNight = vec3(0.10, 0.22, 0.45);

vec3 uwDarkBlue  = mix(mix(uwDarkDay, uwDarkSunset, sunsetFade), uwDarkNight, nightFade);
vec3 uwBrightBlue = mix(mix(uwBrightDay, uwBrightSunset, sunsetFade), uwBrightNight, nightFade);
vec3 uwScatterColor = mix(uwDarkBlue, uwBrightBlue, uwSunFactor);

if (biome_swamp > 0.001) {
vec3 uwSwampDark  = vec3(0.04, 0.10, 0.02);
vec3 uwSwampBright = vec3(0.10, 0.22, 0.05);
vec3 uwSwampScatter = mix(uwSwampDark, uwSwampBright, uwSunFactor);
uwScatterColor = mix(uwScatterColor, uwSwampScatter, biome_swamp);
}

float uwMoonDot = dot(uwRayDir, uwMoonDir) * 0.5 + 0.5;
uwMoonDot = pow(uwMoonDot, 2.0);
vec3 uwMoonBright = vec3(0.18, 0.32, 0.75);
uwScatterColor = mix(uwScatterColor, uwMoonBright, uwMoonDot * nightFade * 0.7);

float surfaceY = float(SEA_LEVEL_OFFSET) - 0.125;

vec3  uwFogAccum = uwScatterColor * uwFogOpacity;

{
float viewFogStart = float(UNDERWATER_VIEW_FOG_START) * uwSwampDistScale;
float viewFogEnd   = float(UNDERWATER_VIEW_FOG_END) * uwSwampDistScale;
float viewFogFactor = smoothstep(viewFogStart, viewFogEnd, uwMaxDist);
if (viewFogFactor > 0.001) {
float viewFogTransmittance = 1.0 - viewFogFactor;
uwFogAccum = uwFogAccum * viewFogTransmittance + uwScatterColor * viewFogFactor;
uwFogOpacity = min(1.0 - (1.0 - uwFogOpacity) * viewFogTransmittance, 0.99);
}
}

float camY = cameraPosition.y;
float depthBelow = surfaceY - camY;
float bandStrength = smoothstep(0.0, 6.0, depthBelow);
if (bandStrength > 0.001 && uwHitsAboveSurface) {
float bandTop = surfaceY;
float bandBottom = surfaceY - 0.5;

float tEnter = 0.0;
float tExit = 0.0;
bool hitsBank = false;

if (camY >= bandBottom && camY <= bandTop) {

tEnter = 0.0;
if (uwRayDir.y > 0.001) {
tExit = (bandTop - camY) / uwRayDir.y;
} else if (uwRayDir.y < -0.001) {
tExit = (bandBottom - camY) / uwRayDir.y;
} else {
tExit = 3.0;
}
hitsBank = true;
} else if (camY < bandBottom && uwRayDir.y > 0.001) {

tEnter = (bandBottom - camY) / uwRayDir.y;
tExit = (bandTop - camY) / uwRayDir.y;
hitsBank = tEnter < 200.0;
}

if (hitsBank) {
float bandOpacity = mix(0.50, 1.0, bandStrength);
float bandTransmittance = 1.0 - bandOpacity;

float bandDirDot = mix(
dot(uwRayDir, uwSunDir) * 0.5 + 0.5,
dot(uwRayDir, uwMoonDir) * 0.5 + 0.5,
nightFade
);
bandDirDot = pow(bandDirDot, 3.0);

vec3 bandDayTarget = vec3(0.30, 0.95, 1.0);
vec3 bandSunsetTarget = vec3(1.0, 0.65, 0.10);
vec3 bandNightTarget = vec3(0.16, 0.30, 0.70);
vec3 bandCyanTarget = mix(mix(bandDayTarget, bandSunsetTarget, sunsetFade), bandNightTarget, nightFade);

if (biome_swamp > 0.001) {
bandCyanTarget = mix(bandCyanTarget, vec3(0.08, 0.18, 0.04), biome_swamp);
}
vec3 bandColor = mix(uwScatterColor, bandCyanTarget, bandDirDot * 0.25);

{

float tSurface = max((surfaceY - camY) / max(uwRayDir.y, 0.001), 0.0);
vec3 surfHitPos = cameraPosition + uwRayDir * tSurface;
vec2 ceilPix = floor(surfHitPos.xz * 16.0) / 16.0;

float ceilCt = frameTimeCounter * WATER_WAVE_SPEED * 0.15;
vec3 ceilCPos = vec3(ceilPix.x, 0.0, ceilPix.y) * 0.35;
float ceilCA = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = ceilCPos;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
ceilCA += abs(noise3D(p * freq + ceilCt * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
ceilCA = 1.0 - ceilCA / total;
}
float ceilCB = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = ceilCPos + 5.0;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
ceilCB += abs(noise3D(p * freq + ceilCt * 1.15 * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
ceilCB = 1.0 - ceilCB / total;
}
float ceilCaustic = min(ceilCA, ceilCB);
ceilCaustic = pow(ceilCaustic, 2.0) * 2.5;
ceilCaustic = max(ceilCaustic - 0.15, 0.0) * (1.0 / 0.85);

float ceilNoise = noise3D(vec3(ceilPix * 6.0, ceilCt * 0.5)) * 0.6;
ceilCaustic += ceilNoise;
ceilCaustic = floor(ceilCaustic * 5.0 + 0.5) / 5.0;
ceilCaustic = max(ceilCaustic, 0.0);

float ceilSunDot = dot(uwRayDir, uwSunDir);
float ceilSunGate = smoothstep(0.3, 0.8, ceilSunDot);

float ceilMoonDot = dot(uwRayDir, uwMoonDir);
float ceilMoonGate = smoothstep(0.3, 0.8, ceilMoonDot) * nightFade * 0.3;
float ceilLightGate = max(ceilSunGate, ceilMoonGate);

bandColor += bandCyanTarget * ceilCaustic * 0.05 * ceilLightGate;
}

uwFogAccum = uwFogAccum * bandTransmittance + bandColor * (1.0 - bandTransmittance);
uwFogOpacity = min(1.0 - (1.0 - uwFogOpacity) * bandTransmittance, 1.0);
}
}

#ifdef UNDERWATER_SHAFTS_ENABLED
{
float glowSunUp = max(uwSunDir.y + sunsetFade * 0.15, 0.0);
if (glowSunUp > 0.01) {

vec3 viewUp = normalize(mat3(gbufferModelViewInverse) * vec3(0.0, 1.0, 0.0));
vec3 sunRight = normalize(cross(uwSunDir, viewUp));
vec3 sunUp = cross(sunRight, uwSunDir);

float sunDot = dot(uwRayDir, uwSunDir);
float combined = 0.0;
if (sunDot > 0.0) {

vec3 delta = uwRayDir - uwSunDir * sunDot;
float dx = abs(dot(delta, sunRight));
float dy = abs(dot(delta, sunUp));

float sqDist = pow(pow(dx, 4.0) + pow(dy, 4.0), 0.25);
combined = 0.35 / (1.0 + sqDist * sqDist * 100.0);
}

float glowShadow = 1.0;
#ifdef SHADOWS_ENABLED
{

float tSurf = max((surfaceY - cameraPosition.y) / max(uwRayDir.y, 0.001), 0.0);
vec3 surfCheckPos = uwRayDir * min(tSurf, uwMaxDist);
vec4 gsClip = shadowProjection * shadowModelView * vec4(surfCheckPos, 1.0);
vec3 gsNDC = distortShadowClipPos(gsClip.xyz);
vec3 gsScreen = gsNDC * 0.5 + 0.5;
gsScreen.z -= 0.001;
if (gsScreen.x > 0.0 && gsScreen.x < 1.0 &&
gsScreen.y > 0.0 && gsScreen.y < 1.0) {
glowShadow = step(gsScreen.z, texture(shadowtex0, gsScreen.xy).r);
}
}
#endif
combined *= glowSunUp * UNDERWATER_SHAFTS_INTENSITY * glowShadow;

vec3 glowColor = mix(vec3(0.75, 0.95, 1.0), vec3(1.0, 0.70, 0.15), sunsetFade);
uwFogAccum += glowColor * combined;
}

float glowMoonUp = max(uwMoonDir.y, 0.0);
if (glowMoonUp > 0.01) {
vec3 viewUpM = normalize(mat3(gbufferModelViewInverse) * vec3(0.0, 1.0, 0.0));
vec3 moonRight = normalize(cross(uwMoonDir, viewUpM));
vec3 moonUp = cross(moonRight, uwMoonDir);

float moonDot = dot(uwRayDir, uwMoonDir);
float moonCombined = 0.0;
if (moonDot > 0.0) {
vec3 delta = uwRayDir - uwMoonDir * moonDot;
float dx = abs(dot(delta, moonRight));
float dy = abs(dot(delta, moonUp));
float sqDist = pow(pow(dx, 4.0) + pow(dy, 4.0), 0.25);
moonCombined = 0.35 / (1.0 + sqDist * sqDist * 100.0);
}
float moonGlowShadow = 1.0;
#ifdef SHADOWS_ENABLED
{
float tSurf = max((surfaceY - cameraPosition.y) / max(uwRayDir.y, 0.001), 0.0);
vec3 surfCheckPos = uwRayDir * min(tSurf, uwMaxDist);
vec4 gsClip = shadowProjection * shadowModelView * vec4(surfCheckPos, 1.0);
vec3 gsNDC = distortShadowClipPos(gsClip.xyz);
vec3 gsScreen = gsNDC * 0.5 + 0.5;
gsScreen.z -= 0.001;
if (gsScreen.x > 0.0 && gsScreen.x < 1.0 &&
gsScreen.y > 0.0 && gsScreen.y < 1.0) {
moonGlowShadow = step(gsScreen.z, texture(shadowtex0, gsScreen.xy).r);
}
}
#endif
moonCombined *= glowMoonUp * UNDERWATER_SHAFTS_INTENSITY * 0.7 * moonGlowShadow;
uwFogAccum += vec3(0.6, 0.7, 0.9) * moonCombined;
}
}
#endif

float dither = fract(52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y)
+ 5.588238 * float(frameCounter & 63));
vec3 uwColorFog = vec3(0.0);
float uwColorFogDensity = 0.0;
int uwColorSteps = 32;
float uwColorStepSize = min(uwMaxDist, float(UNDERWATER_FOG_DISTANCE)) / float(uwColorSteps);

vec3 uwColor1 = vec3(1.0, 0.502, 0.682);
vec3 uwColor2 = vec3(0.071, 0.922, 1.0);
vec3 uwColor3 = vec3(0.722, 0.612, 1.0);

if (biome_swamp > 0.001) {
uwColor1 = mix(uwColor1, vec3(0.15, 0.25, 0.05), biome_swamp);
uwColor2 = mix(uwColor2, vec3(0.08, 0.18, 0.03), biome_swamp);
uwColor3 = mix(uwColor3, vec3(0.12, 0.10, 0.04), biome_swamp);
}

for (int i = 0; i < uwColorSteps; i++) {
float t = (float(i) + dither) * uwColorStepSize;
vec3 samplePos = cameraPosition + uwRayDir * t;

float warpTime = frameTimeCounter * 0.6;
vec3 warpedPos = samplePos;
warpedPos.x += sin(samplePos.z * 0.04 + warpTime * 1.3) * 15.0 + cos(samplePos.y * 0.06 + warpTime * 0.7) * 10.0;
warpedPos.y += sin(samplePos.x * 0.05 + warpTime * 0.9) * 12.0 + cos(samplePos.z * 0.03 + warpTime * 1.1) * 8.0;
warpedPos.z += cos(samplePos.x * 0.04 + warpTime * 1.5) * 14.0 + sin(samplePos.y * 0.05 + warpTime * 0.6) * 10.0;

float n = noise3D(vec3(warpedPos.x * 0.035, warpedPos.y * 0.03, warpedPos.z * 0.035));

if (n > 0.58) {
float fogAmount = smoothstep(0.58, 0.8, n) * 0.005;

float colorSelect = noise3D(vec3(warpedPos.x * 0.025, warpedPos.y * 0.02, warpedPos.z * 0.025) + vec3(100.0, 0.0, 50.0));
vec3 fogColor;
if (colorSelect < 0.33) fogColor = uwColor1;
else if (colorSelect < 0.66) fogColor = uwColor2;
else fogColor = uwColor3;

uwColorFog += fogColor * fogAmount;
uwColorFogDensity += fogAmount;
}
}

uwFogAccum += uwColorFog;
uwFogOpacity = min(uwFogOpacity + uwColorFogDensity, 1.0);

#ifdef UNDERWATER_SHAFTS_ENABLED
{
vec3 sunDir = uwSunDir;
float sunUpFactor = max(sunDir.y, 0.0);

if (sunUpFactor > 0.01) {
vec3 shaftScatter = vec3(0.0);
int shaftSteps = 24;

float shaftCeilingY = surfaceY - 2.0;
float shaftStartT = 0.0;
if (uwRayDir.y > 0.001 && cameraPosition.y < shaftCeilingY) {

shaftStartT = 0.0;
} else if (uwRayDir.y > 0.001) {

shaftStartT = (shaftCeilingY - cameraPosition.y) / uwRayDir.y;
}
float shaftMaxDist = min(uwMaxDist, 48.0);
float shaftRange = max(shaftMaxDist - shaftStartT, 0.0);
float shaftStepSize = shaftRange / float(shaftSteps);

vec3 shaftColorBright = vec3(0.75, 0.95, 1.0);
vec3 shaftColorDeep   = vec3(0.3, 0.55, 0.9);

for (int i = 0; i < shaftSteps; i++) {
float t = shaftStartT + (float(i) + dither) * shaftStepSize;
vec3 sampleWorldPos = cameraPosition + uwRayDir * t;

float distToSurface = (surfaceY - sampleWorldPos.y) / max(sunDir.y, 0.001);
vec3 surfaceHit = sampleWorldPos + sunDir * distToSurface;
vec3 shaftCoord = vec3(surfaceHit.xz * (UNDERWATER_SHAFTS_SCALE * 5.0), 0.0)
+ vec3(0.0, frameTimeCounter * UNDERWATER_SHAFTS_SPEED, 0.0);

float shaft = noise3D(shaftCoord);

float shaftMask = smoothstep(1.0 - UNDERWATER_SHAFTS_DENSITY * 0.6, 1.0, shaft);

float sampleDepth = max(surfaceY - sampleWorldPos.y, 0.0);
if (sampleDepth < 2.0) continue;

#ifdef SHADOWS_ENABLED
{
vec3 scenePos = sampleWorldPos - cameraPosition;
vec4 shClipPos = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shNDC = distortShadowClipPos(shClipPos.xyz);
vec3 shScreen = shNDC * 0.5 + 0.5;
shScreen.z -= 0.001;
if (shScreen.x > 0.0 && shScreen.x < 1.0 &&
shScreen.y > 0.0 && shScreen.y < 1.0) {
if (step(shScreen.z, texture(shadowtex0, shScreen.xy).r) < 0.5) continue;
}
}
#endif

float surfaceFadeIn = smoothstep(2.0, 6.0, sampleDepth);

float depthAtten = exp(-sampleDepth * 0.025) * surfaceFadeIn;

float surfaceProximity = smoothstep(16.0, 5.0, sampleDepth);
vec3 shaftColor = mix(shaftColorDeep, shaftColorBright, surfaceProximity);

float localDensity = shaftMask * depthAtten * UNDERWATER_SHAFTS_INTENSITY * 0.15;
float scatter = localDensity * shaftStepSize * 0.2;

shaftScatter += shaftColor * scatter;
}

uwFogAccum += shaftScatter * sunUpFactor;
}

float moonUpFactor = max(uwMoonDir.y, 0.0);
if (moonUpFactor > 0.01) {
vec3 moonShaftScatter = vec3(0.0);
int moonSteps = 24;

float mCeilingY = surfaceY - 2.0;
float mStartT = 0.0;
if (uwRayDir.y > 0.001 && cameraPosition.y < mCeilingY) {
mStartT = 0.0;
} else if (uwRayDir.y > 0.001) {
mStartT = (mCeilingY - cameraPosition.y) / uwRayDir.y;
}
float mMaxDist = min(uwMaxDist, 48.0);
float mRange = max(mMaxDist - mStartT, 0.0);
float mStepSize = mRange / float(moonSteps);

vec3 mBright = vec3(0.5, 0.6, 0.8);
vec3 mDeep   = vec3(0.2, 0.3, 0.6);

for (int i = 0; i < moonSteps; i++) {
float t = mStartT + (float(i) + dither) * mStepSize;
vec3 sampleWorldPos = cameraPosition + uwRayDir * t;

float distToSurface = (surfaceY - sampleWorldPos.y) / max(uwMoonDir.y, 0.001);
vec3 surfaceHit = sampleWorldPos + uwMoonDir * distToSurface;

vec3 mCoord = vec3(surfaceHit.xz * (UNDERWATER_SHAFTS_SCALE * 5.0) + 100.0, 0.0)
+ vec3(0.0, frameTimeCounter * UNDERWATER_SHAFTS_SPEED * 0.7, 0.0);
float mShaft = noise3D(mCoord);
float mMask = smoothstep(1.0 - UNDERWATER_SHAFTS_DENSITY * 0.6, 1.0, mShaft);

float sampleDepth = max(surfaceY - sampleWorldPos.y, 0.0);
if (sampleDepth < 2.0) continue;

#ifdef SHADOWS_ENABLED
{
vec3 scenePos = sampleWorldPos - cameraPosition;
vec4 shClipPos = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shNDC = distortShadowClipPos(shClipPos.xyz);
vec3 shScreen = shNDC * 0.5 + 0.5;
shScreen.z -= 0.001;
if (shScreen.x > 0.0 && shScreen.x < 1.0 &&
shScreen.y > 0.0 && shScreen.y < 1.0) {
if (step(shScreen.z, texture(shadowtex0, shScreen.xy).r) < 0.5) continue;
}
}
#endif

float surfaceFadeIn = smoothstep(2.0, 6.0, sampleDepth);
float depthAtten = exp(-sampleDepth * 0.025) * surfaceFadeIn;
float surfaceProximity = smoothstep(16.0, 5.0, sampleDepth);
vec3 mColor = mix(mDeep, mBright, surfaceProximity);

float scatter = mMask * depthAtten * UNDERWATER_SHAFTS_INTENSITY * 0.15 * mStepSize * 0.2;
moonShaftScatter += mColor * scatter;
}

uwFogAccum += moonShaftScatter * moonUpFactor * 0.25;
}
}
#endif

gl_FragData[0] = vec4(uwFogAccum, uwFogOpacity);
return;
}
#else

if (isEyeInWater == 1) {
gl_FragData[0] = vec4(0.0);
return;
}
#endif

#ifdef CAVE_FOG_ENABLED
if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {

storedCaveFogTakeover = 1.0;
memoryBarrierBuffer();
}
vec4 cfMaskData = texture(colortex1, texcoord);
float caveFogSurfaceMask = 1.0 - smoothstep(1.0 / 15.0, 3.0 / 15.0, cfMaskData.b);
float caveFogEyeSkylight = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
float caveFogAirMask = 1.0 - smoothstep(2.0 / 15.0, 6.0 / 15.0, caveFogEyeSkylight);
float caveFogSceneMask = max(caveFogSurfaceMask, caveFogAirMask);
if (isEyeInWater == 0 && !isForcedNetherBiome(biome) && caveFogSceneMask > 0.001) {

vec3 caveTargetAbove = getCaveFogAboveTarget(biome, biome_category);
vec3 caveSmoothedAbove;
if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
vec3 prevFog = vec3(smoothCaveFogR, smoothCaveFogG, smoothCaveFogB);
if (any(isnan(prevFog)) || any(isinf(prevFog)) || length(prevFog) < 0.001) prevFog = caveTargetAbove;
vec3 newFog = mix(prevFog, caveTargetAbove, 0.02);
smoothCaveFogR = newFog.r;
smoothCaveFogG = newFog.g;
smoothCaveFogB = newFog.b;
memoryBarrierBuffer();
caveSmoothedAbove = newFog;
} else {
caveSmoothedAbove = vec3(smoothCaveFogR, smoothCaveFogG, smoothCaveFogB);
}

float cfDepth0 = texture(depthtex0, texcoord).r;
float cfDepth1 = texture(depthtex1, texcoord).r;
float cfVxDepth = texture(vxDepthTexTrans, texcoord).r;
bool cfIsVoxyLodPixel = (cfMaskData.a > 0.999 && cfMaskData.g < 0.01 && cfDepth0 >= 0.9999);
bool cfHasVoxyDepth = (cfVxDepth > 0.00001 && cfVxDepth < 0.9999);
bool cfIsTranslucent = (cfDepth0 < cfDepth1 - 0.00001);
bool cfIsEntityPixel = (cfMaskData.a > 0.01 && cfMaskData.a < 0.99);
bool cfIsHeatPixel = (cfMaskData.a > 0.999 && cfDepth0 < 0.9999);
float cfDepth;
bool cfUseVoxyProj = false;

if (cfIsEntityPixel) {
cfDepth = cfDepth0;
} else if (cfIsHeatPixel && cfIsTranslucent) {

cfDepth = cfDepth0;
} else if (cfHasVoxyDepth && (cfIsTranslucent || cfIsVoxyLodPixel)) {
cfDepth = cfVxDepth;
cfUseVoxyProj = true;
} else if (cfIsTranslucent) {
cfDepth = (cfDepth1 < 0.9999) ? cfDepth1 : cfDepth0;
} else if (cfIsVoxyLodPixel) {
cfDepth = cfDepth0;
cfUseVoxyProj = true;
} else {
cfDepth = cfDepth0;
}

bool cfHasSceneDepth = cfDepth < 0.9999;
if (cfHasSceneDepth || caveFogAirMask > 0.001) {
vec3 cfView;
float cfPixelDist;
if (cfHasSceneDepth) {
mat4 cfProjInv = cfUseVoxyProj ? vxProjInv : gbufferProjectionInverse;
vec4 cfClip = cfProjInv * vec4(texcoord * 2.0 - 1.0, cfDepth * 2.0 - 1.0, 1.0);
cfView = cfClip.xyz / cfClip.w;
cfPixelDist = length(cfView);
} else {
vec4 cfClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
cfView = cfClip.xyz / cfClip.w;
cfPixelDist = CAVE_FOG_MAX_DIST;
}

vec3 cfWorldDir = normalize((gbufferModelViewInverse * vec4(cfView, 0.0)).xyz);
float cfRayLen = min(cfPixelDist, CAVE_FOG_MAX_DIST);
float cfRayStart = 0.0;
float cfBlueNoise = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 255, 0).b;
float cfDither = fract(cfBlueNoise + float(frameCounter) * 0.6180339887);
float cfTrans = 1.0;
vec3 cfBase = vec3(0.0);
vec3 cfLpv  = vec3(0.0);
float cfMarchLen = max(cfRayLen - cfRayStart, 0.0);
const float cfExpFactor = 11.0;
float cfStepCount = float(CAVE_FOG_STEPS);
float caveFogSunUp = 0.0;
#ifdef SHADOWS_ENABLED
caveFogSunUp = smoothstep(0.02, 0.10, normalize(mat3(gbufferModelViewInverse) * sunPosition).y);
#endif
for (int i = 0; i < CAVE_FOG_STEPS; i++) {
float cfStep = (float(i) + cfDither) / cfStepCount;
float cfExpSample = pow(cfExpFactor, cfStep);
float cfSamplePos = (cfExpSample - 1.0) / (cfExpFactor - 1.0);
float cfSegmentLen = cfExpSample * log(cfExpFactor) / cfStepCount / (cfExpFactor - 1.0) * cfMarchLen;
float t = cfRayStart + cfSamplePos * cfMarchLen;
vec3 sp = cameraPosition + cfWorldDir * t;
vec3 baseCol = getCaveFogColorSmoothed(caveSmoothedAbove, sp.y);
float localLightClearGate = step(float(SEA_LEVEL_OFFSET), sp.y);
float cfNearFade = smoothstep(0.5, 3.0, t);

vec3 lpvCol = vec3(0.0);
float litCull = 1.0;
#ifdef LPV_ENABLED
if (caveFogSceneMask > 0.001) {
vec3 lpvScene = sp - cameraPosition;
vec3 lpvVox = sceneToVoxelSpace(lpvScene, cameraPosition);
if (isInVoxelVolume(lpvVox)) {
vec3 lpvUv = lpvVox / lpvVolumeSize;
vec3 lpvLightColor = compressRawLpvLight(caveFogLpvBlurred(lpvUv));
vec3 lpvLightCull  = compressRawLpvLight(caveFogLpvTap(lpvUv));
vec3 visibleFogLpv = softCapLpvLight(lpvLightColor * CAVE_FOG_LPV_STRENGTH, 0.09, 0.05) * caveFogSceneMask;
vec3 visibleFogCull = softCapLpvLight(lpvLightCull * CAVE_FOG_LPV_STRENGTH, 0.022, 0.008) * caveFogSceneMask;

float lpvSourceGate = caveFogLpvSourceGate(lpvVox);
float lpvSmoothCore = smoothstep(0.38, 1.20, getLpvLuma(lpvLightCull)) * 0.55;
lpvSourceGate = clamp(max(lpvSourceGate, lpvSmoothCore), 0.0, 1.0);
float lpvCullFactor = caveFogLitCull(visibleFogCull);

litCull = mix(1.0, lpvCullFactor, localLightClearGate * lpvSourceGate);
lpvCol = visibleFogLpv * lpvSourceGate * 1.10;
}
}
#endif

float sunCull = 1.0;
#ifdef SHADOWS_ENABLED
if (caveFogSunUp > 0.001) {
float sampleSunVisibility = caveFogSunVisibility(sp, caveFogSunUp);
sunCull = 1.0 - smoothstep(0.02, 0.20, sampleSunVisibility);
sunCull = max(sunCull, caveFogAirMask * 0.28);
}
#endif

float localFogDensity = CAVE_FOG_DENSITY * caveFogDensityField(sp) * caveFogSceneMask * sunCull * cfNearFade;
float localDensity = localFogDensity * litCull;
float localExtinction = min(localDensity * cfSegmentLen * 1.15, 0.08);
float lpvExtinction = min(localFogDensity * cfSegmentLen * 1.15, 0.08);
float sT = exp(-localExtinction);
float stepWeight = cfTrans * (1.0 - sT);
float lpvStepWeight = cfTrans * (1.0 - exp(-lpvExtinction));
float lpvAirWeight = cfTrans * min(cfSegmentLen * 0.12 * caveFogSceneMask * sunCull * smoothstep(0.25, 1.5, t), 0.20);
cfBase += stepWeight * baseCol;
cfLpv  += max(lpvStepWeight, lpvAirWeight) * lpvCol;
cfTrans *= sT;
}

float cfAlpha = (1.0 - cfTrans);
vec3 caveFogColor = cfBase;
#ifdef LPV_ENABLED
caveFogColor += cfLpv;
#endif
caveFogOut = vec4(caveFogColor, 1.0 + cfAlpha);
}
}
#endif

#if !defined(ATMO_FOG_ENABLED)
{

if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
smoothBeach  = biome_beach;
smoothSwamp  = biome_swamp;
smoothJungle = biome_jungle;
smoothSnowy  = biome_snowy;
smoothArid   = biome_arid;
smoothOcean  = biome_ocean;
smoothPaleGarden = biome_pale_garden;

vec3 targetFog = getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B));
vec3 prevFog = vec3(smoothNetherFogR, smoothNetherFogG, smoothNetherFogB);

if (any(isnan(prevFog)) || any(isinf(prevFog)) || prevFog == vec3(0.0)) prevFog = targetFog;
vec3 newFog = mix(prevFog, targetFog, 0.03);
smoothNetherFogR = newFog.r;
smoothNetherFogG = newFog.g;
smoothNetherFogB = newFog.b;

memoryBarrierBuffer();
}
vec4 fogOut = vec4(0.0);
if (caveFogOut.a > 1.0) {
vec4 caveFog = vec4(caveFogOut.rgb, caveFogOut.a - 1.0);
fogOut = caveFog;
}
gl_FragData[0] = fogOut;
return;
}
#endif

vec4 maskData = texture(colortex1, texcoord);
float depth0 = texture(depthtex0, texcoord).r;
float depth1 = texture(depthtex1, texcoord).r;
float dhDepth = texture(dhDepthTex, texcoord).r;
float vxDepth = texture(vxDepthTexTrans, texcoord).r;
bool hasDHAtPixel = hasValidDHDepth(dhDepth);
bool isVoxyLodPixel = (maskData.a > 0.999 && maskData.g < 0.01 && depth0 >= 0.9999);
bool hasVoxyDepth = (vxDepth > 0.00001 && vxDepth < 0.9999);

bool isTranslucent = (depth0 < depth1 - 0.00001);
bool isEntityPixel = (maskData.a > 0.01 && maskData.a < 0.99);
bool isWaterPixel = (texture(colortex5, texcoord).y > 0.9) && isTranslucent;
float sceneDepth;
bool useVoxyProj = false;
if (isEntityPixel) {

sceneDepth = depth0;
} else if (hasVoxyDepth && (isTranslucent || isVoxyLodPixel)) {

sceneDepth = vxDepth;
useVoxyProj = true;
} else if (isWaterPixel && depth0 < 0.9999) {
sceneDepth = depth0;
} else if (isTranslucent) {

sceneDepth = (depth1 < 0.9999) ? depth1 : depth0;
} else if (isVoxyLodPixel) {

sceneDepth = depth0;
useVoxyProj = true;
} else {
sceneDepth = depth0;
}
bool hasMCDepth = (sceneDepth < 0.9999) || isVoxyLodPixel || hasVoxyDepth;
bool isSky = !hasMCDepth;
float pxSkylight = isSky ? 1.0 : maskData.b;
float atmoZeroSkylightGate = isSky ? 1.0 : smoothstep(0.5 / 15.0, 1.0 / 15.0, pxSkylight);
float atmoSkylightGate = 1.0;
float pxLowSkylightMask = 1.0 - smoothstep(2.0 / 15.0, 6.0 / 15.0, pxSkylight);
float playerSkylight = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
float playerLowSkylightMask = 1.0 - smoothstep(2.0 / 15.0, 6.0 / 15.0, playerSkylight);

vec3 rayDir;
float maxDist;
float surfaceSunVisibility = 0.0;

if (hasMCDepth) {
vec4 clipPos = vec4(texcoord * 2.0 - 1.0, sceneDepth * 2.0 - 1.0, 1.0);
mat4 projInv = useVoxyProj ? vxProjInv : gbufferProjectionInverse;
vec4 viewPos = projInv * clipPos;
viewPos /= viewPos.w;
vec3 worldPos = (gbufferModelViewInverse * viewPos).xyz + cameraPosition;
rayDir = normalize(worldPos - cameraPosition);
maxDist = length(worldPos - cameraPosition);

#ifdef SHADOWS_ENABLED
vec3 scenePos = worldPos - cameraPosition;
vec4 surfaceShadowViewPos = shadowModelView * vec4(scenePos, 1.0);
vec4 surfaceShadowClipPos = shadowProjection * surfaceShadowViewPos;
vec3 surfaceShadowNdc = distortShadowClipPos(surfaceShadowClipPos.xyz);
vec3 surfaceShadowScreenPos = surfaceShadowNdc * 0.5 + 0.5;
surfaceShadowScreenPos.z -= 0.001;

vec2 surfaceEdgeDist = min(surfaceShadowScreenPos.xy, 1.0 - surfaceShadowScreenPos.xy);
float surfaceEdgeFade = smoothstep(0.0, 0.05, min(surfaceEdgeDist.x, surfaceEdgeDist.y));
if (surfaceShadowScreenPos.x > 0.0 && surfaceShadowScreenPos.x < 1.0 &&
surfaceShadowScreenPos.y > 0.0 && surfaceShadowScreenPos.y < 1.0 &&
surfaceShadowScreenPos.z > 0.0 && surfaceShadowScreenPos.z < 1.0 &&
surfaceEdgeFade > 0.001) {
surfaceSunVisibility = step(surfaceShadowScreenPos.z, texture(shadowtex1, surfaceShadowScreenPos.xy).r) * surfaceEdgeFade;
}
#endif
} else {

if (hasDHAtPixel) {
float dhLinear = linearizeDepthDH(dhDepth);
vec4 clipFar = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec4 viewPosFar = gbufferProjectionInverse * clipFar;
vec3 viewDir = normalize(viewPosFar.xyz / max(viewPosFar.w, 0.0001));
maxDist = dhLinear / max(-viewDir.z, 0.001);
rayDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
} else {

vec4 vd4 = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
rayDir = normalize(mat3(gbufferModelViewInverse) * (vd4.xyz / vd4.w));
maxDist = 0.0;
#ifdef ATMO_FOG_ENABLED
maxDist = max(maxDist, float(ATMO_FOG_DISTANCE));
#endif
}
}

float fogMaxDist = 0.0;
#ifdef ATMO_FOG_ENABLED
fogMaxDist = max(fogMaxDist, float(ATMO_FOG_DISTANCE));
#endif

if (isSky || (isTranslucent && sceneDepth >= 0.9999)) {
maxDist = fogMaxDist;
} else {
maxDist = min(maxDist, fogMaxDist);
}

float fogBottom = 0.0;
float fogTop    = 0.0;
float tEntry = 0.0;
float tExit  = 0.0;
bool hasAtmoSegment = false;

#ifdef ATMO_FOG_ENABLED

fogBottom = float(SEA_LEVEL_OFFSET);
fogTop    = cameraPosition.y + float(ATMO_FOG_ABOVE);
tEntry = 0.0;
tExit  = maxDist;

if (abs(rayDir.y) > 0.0001) {
float tBottom = (fogBottom - cameraPosition.y) / rayDir.y;
float tTop    = (fogTop    - cameraPosition.y) / rayDir.y;
float tNear = min(tBottom, tTop);
float tFar  = max(tBottom, tTop);
tEntry = max(tNear, 0.0);
tExit  = min(tFar, maxDist);
hasAtmoSegment = tEntry < tExit;
} else {
hasAtmoSegment = !(cameraPosition.y < fogBottom || cameraPosition.y > fogTop);
if (hasAtmoSegment) tExit = maxDist;
}

#endif

if (!hasAtmoSegment) {

if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
smoothBeach  = biome_beach;
smoothSwamp  = biome_swamp;
smoothJungle = biome_jungle;
smoothSnowy  = biome_snowy;
smoothArid   = biome_arid;
smoothOcean  = biome_ocean;
smoothPaleGarden = biome_pale_garden;

vec3 targetFog = getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B));
vec3 prevFog = vec3(smoothNetherFogR, smoothNetherFogG, smoothNetherFogB);

if (any(isnan(prevFog)) || any(isinf(prevFog))) prevFog = targetFog;
float fogLerpSpeed = (length(prevFog) < 0.001) ? 1.0 : 0.03;
vec3 newFog = mix(prevFog, targetFog, fogLerpSpeed);
smoothNetherFogR = newFog.r;
smoothNetherFogG = newFog.g;
smoothNetherFogB = newFog.b;

memoryBarrierBuffer();
}
vec4 fogOut = vec4(0.0);
if (caveFogOut.a > 1.0) {
vec4 caveFog = vec4(caveFogOut.rgb, caveFogOut.a - 1.0);
fogOut = caveFog;
}
gl_FragData[0] = fogOut;
return;
}

float windAngle = 1.2;
vec2 windDir2D = vec2(cos(windAngle), sin(windAngle));
vec3 windOffset = vec3(windDir2D.x, 0.0, windDir2D.y) * frameTimeCounter * ATMO_FOG_WIND_SPEED * 2.0;

float blueNoise = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 255, 0).b;
float dither = fract(blueNoise + float(frameCounter) * 0.6180339887);

vec3 smoothedAtmoFogColor = getSmoothedBiomeFogColorRaw(fogColor);
float atmoWSnow = getBiomeVisualSnowyWeight(biome_snowy);
float atmoWSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float atmoWJungle = getBiomeJungleWeight(biome_jungle, biome, biome_category, atmoWSwamp);
float atmoWArid = getBiomeVisualAridWeight(biome_arid);
float atmoWSavanna = getSavannaWeightWithoutSwamp(getBiomeVisualSavannaWeight(biome_savanna), atmoWSwamp);
vec3 baseFogColor = getSmoothBiomeFogColorSavanna(smoothedAtmoFogColor, atmoWSnow, atmoWJungle, atmoWSwamp, atmoWArid, atmoWSavanna);
float fogLuma = dot(baseFogColor, vec3(0.299, 0.587, 0.114));
TimeWeightsSimple ts = getTimeWeightsSimple(sunAngle);
float dayFactor = ts.day;
float nightFactor = ts.night;
atmoSkylightGate = mix(1.0, atmoZeroSkylightGate, nightFactor);

vec3 moonlightTint = vec3(0.55, 0.65, 1.0);
baseFogColor = mix(baseFogColor, moonlightTint, nightFactor);

fogLuma = dot(baseFogColor, vec3(0.299, 0.587, 0.114));
baseFogColor = max(mix(vec3(fogLuma), baseFogColor, 1.3), vec3(0.0));
if (atmoWSavanna > 0.001) {
baseFogColor = mix(baseFogColor, getSavannaSkyHorizonColor(), atmoWSavanna * dayFactor);
}

float timeBrightness = max(dayFactor, nightFactor * 0.45);

float fogAngle = fract(sunAngle);
float fogTransitionDip = smoothstep(0.42, 0.5146, fogAngle) * (1.0 - smoothstep(0.5146, 0.5604, fogAngle));
timeBrightness *= 1.0 - fogTransitionDip;

float smoothedMask = storedExposure;
if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
int shadowedCount = 0;
int litCount = 0;
for (int sy = 0; sy < 8; sy++) {
for (int sx = 0; sx < 8; sx++) {
vec2 sampleUV = (vec2(float(sx), float(sy)) + 0.5) / 8.0;

float d = texture(depthtex0, sampleUV).r;
bool inShadow = false;
if (d < 1.0) {
vec4 cp = vec4(sampleUV * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
vec4 vp = gbufferProjectionInverse * cp;
vp /= vp.w;
vec3 scenePos = (gbufferModelViewInverse * vp).xyz;
vec4 sv = shadowModelView * vec4(scenePos, 1.0);
vec4 sc = shadowProjection * sv;
vec3 sn = distortShadowClipPos(sc.xyz);
vec3 ss = sn * 0.5 + 0.5;
if (ss.x > 0.0 && ss.x < 1.0 && ss.y > 0.0 && ss.y < 1.0) {
float mapD = texture(shadowtex0, ss.xy).r;
inShadow = (ss.z - 0.003) > mapD;
}
}

if (inShadow) {
shadowedCount++;
} else {
litCount++;
}
}
}

float shadowRatio = (shadowedCount + litCount > 0) ? float(shadowedCount) / float(shadowedCount + litCount) : 0.0;
float shadowMask = smoothstep(0.4, 0.75, shadowRatio);
float targetMask = shadowMask;

float prevMask = storedExposure;
if (prevMask >= 0.0 && prevMask <= 1.5) {
smoothedMask = mix(prevMask, targetMask, 0.01);
} else {
smoothedMask = targetMask;
}
storedExposure = smoothedMask;

smoothBeach  = biome_beach;
smoothSwamp  = biome_swamp;
smoothJungle = biome_jungle;
smoothSnowy  = biome_snowy;
smoothArid   = biome_arid;
smoothOcean  = biome_ocean;
smoothPaleGarden = biome_pale_garden;

vec3 targetFog = getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B));
vec3 prevFog = vec3(smoothNetherFogR, smoothNetherFogG, smoothNetherFogB);

if (any(isnan(prevFog)) || any(isinf(prevFog))) prevFog = targetFog;
float fogLerpSpeed = (length(prevFog) < 0.001) ? 1.0 : 0.03;
vec3 newFog = mix(prevFog, targetFog, fogLerpSpeed);
smoothNetherFogR = newFog.r;
smoothNetherFogG = newFog.g;
smoothNetherFogB = newFog.b;

memoryBarrierBuffer();
}

float coverageBrightness = mix(0.0, 2.0, smoothedMask);

if (atmoWSwamp > 0.001) {

baseFogColor = mix(baseFogColor, vec3(144.0, 199.0, 90.0) / 255.0, atmoWSwamp);

float swampCovDay = mix(1.20, 1.90, smoothedMask);
float swampCovNight = mix(0.60, 1.00, smoothedMask);
float swampCov = mix(swampCovDay, swampCovNight, nightFactor);
coverageBrightness = mix(coverageBrightness, swampCov, atmoWSwamp);
}

float smoothedScreenSkylight = storedScreenSkylight;
if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
float rawScreenSkylight = 0.0;
for (int sy = 0; sy < 4; sy++) {
for (int sx = 0; sx < 4; sx++) {
vec2 sampleUV = (vec2(float(sx), float(sy)) + 0.5) / 4.0;
float sd = texture(depthtex0, sampleUV).r;
float sl = (sd >= 1.0) ? 1.0 : texture(colortex1, sampleUV).b;
rawScreenSkylight += sl;
}
}
rawScreenSkylight /= 16.0;
float prev = storedScreenSkylight;
if (prev >= 0.0 && prev <= 1.0) {

float smoothRate = (rawScreenSkylight < prev) ? 0.08 : 0.05;
smoothedScreenSkylight = mix(prev, rawScreenSkylight, smoothRate);
} else {
smoothedScreenSkylight = rawScreenSkylight;
}
storedScreenSkylight = smoothedScreenSkylight;
}

float sceneAwareFactor = clamp(storedAtmoSceneFactor, 0.0, 1.0);
float sceneAwareDensityMul = 1.0;
float sceneAwarePresenceBias = 0.0;
float sceneAwareCoverageFloor = 0.0;
float shaftIntensityMul = 1.0;
float shaftDensityMul = 1.0;
#ifdef ATMO_SCENE_AWARE_SHAFTS_ENABLED
{
if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
float nextSceneAware = clamp(storedAtmoSceneFactor, 0.0, 1.0);

if ((frameCounter & 3) == 0) {
vec2 shadowMapResolutionM = vec2(textureSize(shadowtex0, 0));
vec2 viewM = vec2(1.0 / 5.0);
float salsSampleSum = 0.0;
int salsSampleCount = 0;

for (float i = 0.25; i < 5.0; i++) {
for (float h = 0.45; h < 5.0; h++) {
vec2 coord = 0.3 + 0.4 * viewM * vec2(i, h);
ivec2 icoord = ivec2(coord * shadowMapResolutionM);
float salsSample = texelFetch(shadowtex0, icoord, 0).x;
if (salsSample < 0.55) {
float sampledHeight = texture(shadowcolor1, coord).a;
if (sampledHeight > 0.0) {
sampledHeight = max(sampledHeight - 0.25, 0.0) / 0.05;
salsSampleSum += sampledHeight;
salsSampleCount++;
}
}
}
}

float salsCheck = (salsSampleCount > 0) ? (salsSampleSum / float(salsSampleCount)) : 0.0;
int reduceAmount = 2;

ivec2 depthSize = textureSize(depthtex0, 0);
int skyCheck = 0;
for (int k = 0; k < 5; k++) {
float x = 0.1 + 0.2 * float(k);
ivec2 skyCoord = ivec2(vec2(float(depthSize.x) * x, float(depthSize.y) * 0.9));
skyCoord = clamp(skyCoord, ivec2(0), depthSize - 1);
skyCheck += int(texelFetch(depthtex0, skyCoord, 0).x == 1.0);
}

if (skyCheck >= 4) {
salsCheck = 0.0;
reduceAmount = 3;
}

if (salsCheck > 6.0) {
nextSceneAware = min(nextSceneAware + (1.0 / 255.0), 1.0);
} else {
nextSceneAware = max(nextSceneAware - (1.0 / 255.0) * float(reduceAmount), 0.0);
}

storedAtmoSceneFactor = nextSceneAware;
memoryBarrierBuffer();
}
}

sceneAwareFactor = clamp(storedAtmoSceneFactor, 0.0, 1.0);
sceneAwareFactor = clamp(sceneAwareFactor * ATMO_SCENE_AWARE_STRENGTH, 0.0, 1.0);

sceneAwareDensityMul = mix(1.0, 1.85, sceneAwareFactor);
sceneAwarePresenceBias = mix(0.0, 0.12, sceneAwareFactor);
sceneAwareCoverageFloor = mix(0.0, 0.90, sceneAwareFactor);
shaftIntensityMul = mix(1.0, 1.35, sceneAwareFactor);
shaftDensityMul = mix(1.0, 1.20, sceneAwareFactor);
}
#endif

float finalCoverage = coverageBrightness;
vec3 fogLitColor = baseFogColor * ATMO_FOG_BRIGHTNESS * timeBrightness * finalCoverage;

vec3 shaftLitColor = mix(
baseFogColor * ATMO_FOG_BRIGHTNESS * timeBrightness * max(coverageBrightness, 1.0) * shaftIntensityMul,
fogLitColor,
nightFactor
);

vec3 lightDirWorld = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 shaftRefUp = (abs(lightDirWorld.y) > 0.95) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
vec3 shaftBasisU = normalize(cross(lightDirWorld, shaftRefUp));
vec3 shaftBasisV = normalize(cross(lightDirWorld, shaftBasisU));

float marchStart = maxDist;
#ifdef ATMO_FOG_ENABLED
if (hasAtmoSegment) marchStart = min(marchStart, tEntry);
#endif

float marchEnd = 0.0;
#ifdef ATMO_FOG_ENABLED
if (hasAtmoSegment) marchEnd = max(marchEnd, tExit);
#endif

if (marchEnd <= marchStart + 0.0001) {
gl_FragData[0] = vec4(0.0);
return;
}

float marchLength = marchEnd - marchStart;

int stepCount = ATMO_FOG_STEPS;
float stepSize = marchLength / float(stepCount);
float density = max(ATMO_FOG_DENSITY + rainStrength * 0.5, 0.01);

vec3  fogAccum = vec3(0.0);
float transmittance = 1.0;

float noiseThreshold = mix(0.25, 0.10, atmoWSwamp);

for (int i = 0; i < ATMO_FOG_STEPS; i++) {
if (i >= stepCount) break;
float t = marchStart + (float(i) + dither) * stepSize;
vec3 samplePos = cameraPosition + rayDir * t;

float extinction = 0.0;

float shadow = 0.0;
vec3 shadowTint = vec3(1.0);
#ifdef SHADOWS_ENABLED
{
vec3 scenePos = samplePos - cameraPosition;
vec4 shadowViewPos = shadowModelView * vec4(scenePos, 1.0);
vec4 shadowClipPos = shadowProjection * shadowViewPos;
vec3 shadowNDC = distortShadowClipPos(shadowClipPos.xyz);
vec3 shadowScreenPos = shadowNDC * 0.5 + 0.5;
shadowScreenPos.z -= 0.0005;

vec2 edgeDist2 = min(shadowScreenPos.xy, 1.0 - shadowScreenPos.xy);
float edgeFade = smoothstep(0.0, 0.05, min(edgeDist2.x, edgeDist2.y));

if (shadowScreenPos.x > 0.0 && shadowScreenPos.x < 1.0 &&
shadowScreenPos.y > 0.0 && shadowScreenPos.y < 1.0 &&
shadowScreenPos.z > 0.0 && shadowScreenPos.z < 1.0 &&
edgeFade > 0.001) {

float shadow0 = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
shadow = step(shadowScreenPos.z, texture(shadowtex1, shadowScreenPos.xy).r);

shadow0 *= edgeFade;
shadow  *= edgeFade;

#ifdef ATMO_COLORED_SHAFTS_ENABLED
if (shadow0 < 1.0 && shadow > 0.0) {
vec2 shadowTexelSize = 1.0 / vec2(textureSize(shadowcolor0, 0));
vec3 shCol  = texture(shadowcolor0, shadowScreenPos.xy).rgb * 4.0;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2( 1.0,  0.0) * shadowTexelSize).rgb * 2.0;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2(-1.0,  0.0) * shadowTexelSize).rgb * 2.0;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2( 0.0,  1.0) * shadowTexelSize).rgb * 2.0;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2( 0.0, -1.0) * shadowTexelSize).rgb * 2.0;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2( 1.0,  1.0) * shadowTexelSize).rgb;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2(-1.0,  1.0) * shadowTexelSize).rgb;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2( 1.0, -1.0) * shadowTexelSize).rgb;
shCol += texture(shadowcolor0, shadowScreenPos.xy + vec2(-1.0, -1.0) * shadowTexelSize).rgb;
shCol *= (1.0 / 16.0);
shCol *= shCol;
shadowTint = shCol * shadow + shadow0;
shadow = max(max(shadowTint.r, shadowTint.g), shadowTint.b);
shadowTint = (shadow > 0.001) ? shadowTint / shadow : vec3(1.0);
}
#endif
}
}
#endif

float stepSunMask = smoothstep(0.35, 0.85, shadow);
float surfaceSunMask = smoothstep(0.20, 0.60, surfaceSunVisibility);
float sunFacingLowSkyMask = pxLowSkylightMask * max(stepSunMask, surfaceSunMask) * (1.0 - nightFactor);
float tintMin = min(shadowTint.r, min(shadowTint.g, shadowTint.b));
float tintMax = max(shadowTint.r, max(shadowTint.g, shadowTint.b));
bool hasColorTint = (tintMax - tintMin) > 0.15;

#ifdef ATMO_COLORED_SHAFTS_ENABLED
if (hasColorTint && atmoSkylightGate > 0.001) {
float shaftDensity = stepSize * 0.012 * shaftDensityMul;
float shaftExtinction = min(shaftDensity, 0.03);
float shaftStepT = exp(-shaftExtinction);
float shaftWeight = (shaftExtinction > 0.0001)
? (1.0 - shaftStepT) / shaftExtinction
: 1.0;
float shaftBoost = mix(8.0, 1.0, nightFactor);
fogAccum += shaftLitColor * shadowTint * shaftDensity * shaftWeight * transmittance * shaftBoost;
extinction += shaftExtinction;
}
#endif

#ifdef ATMO_FOG_ENABLED
if (hasAtmoSegment && atmoSkylightGate > 0.001 && t >= tEntry && t <= tExit) {
vec3 noiseCoord = (samplePos + windOffset) * ATMO_FOG_SCALE;
float noiseSample = afFogDensity(noiseCoord);
float heightFrac = (samplePos.y - fogBottom) / max(fogTop - fogBottom, 1.0);
float heightFade = smoothstep(1.0, 0.7, heightFrac);
float distFade = 1.0 - smoothstep(float(ATMO_FOG_DISTANCE) * 0.5, float(ATMO_FOG_DISTANCE), t);

float smoothWidth = mix(0.45, 0.65, atmoWSwamp);
float adaptiveNoiseThreshold = max(noiseThreshold - sceneAwarePresenceBias, 0.0);
float fogPresence = smoothstep(adaptiveNoiseThreshold, adaptiveNoiseThreshold + smoothWidth, noiseSample);
if (fogPresence > 0.001) {

float caveLikeMask = 1.0 - smoothstep(1.0 / 15.0, 3.0 / 15.0, smoothedScreenSkylight);
float nearBoostMask = max(smoothedMask, sceneAwareFactor) * (1.0 - caveLikeMask);
float nearBoost = 1.0 + smoothstep(2.0, 10.0, t) * smoothstep(10.0, 2.0, t) * nearBoostMask * 19.0;
float localDensity = density * fogPresence * heightFade * distFade * stepSize * 0.006 * nearBoost * sceneAwareDensityMul * atmoSkylightGate;
float fogCoverage = max(coverageBrightness, sceneAwareCoverageFloor);
float scatterLighting = shadow;
float scatterAmount = min(localDensity * fogCoverage * scatterLighting, 0.06);

float fogExtinction = isSky
? scatterAmount
: min(localDensity * fogCoverage, 0.06);

float stepTransmittance = exp(-fogExtinction);
float integratedWeight = (fogExtinction > 0.0001)
? (1.0 - stepTransmittance) / fogExtinction
: 1.0;
fogAccum += fogLitColor * scatterAmount * integratedWeight * transmittance;
extinction += fogExtinction;
}
}
#endif

transmittance *= exp(-extinction);

if (transmittance < 0.01) break;
}

float fogOpacity = 1.0 - transmittance;

vec4 fogOut = vec4(fogAccum, fogOpacity);
if (caveFogOut.a > 1.0) {
vec4 caveFog = vec4(caveFogOut.rgb, caveFogOut.a - 1.0);
fogOut.rgb = caveFog.rgb + fogOut.rgb * (1.0 - caveFog.a);
fogOut.a = caveFog.a + fogOut.a * (1.0 - caveFog.a);
}
gl_FragData[0] = fogOut;
#undef texcoord
}

#else

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

uniform float biome_beach;
uniform float biome_swamp;
uniform float biome_jungle;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_savanna;
uniform float biome_ocean;

in vec2 texcoord;

void main() {
if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
smoothBeach  = biome_beach;
smoothSwamp  = biome_swamp;
smoothJungle = biome_jungle;
smoothSnowy  = biome_snowy;
smoothArid   = biome_arid;
smoothOcean  = biome_ocean;
smoothPaleGarden = biome_pale_garden;

memoryBarrierBuffer();
}
gl_FragData[0] = vec4(0.0);
}

#endif
