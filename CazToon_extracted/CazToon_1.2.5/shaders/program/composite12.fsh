/* RENDERTARGETS: 10 */

#include "/settings.glsl"

#if defined(HAZE_FOG_ENABLED) || defined(NETHER_FOG_ENABLED)

#include "/include/biome_overrides.glsl"

in vec2 texcoord;

uniform sampler2D colortex1;
uniform sampler2D colortex5;
uniform sampler2D colortex10;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D dhDepthTex;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 vxProjInv;
uniform sampler2D vxDepthTexTrans;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
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
uniform int frameCounter;
uniform int biome;
uniform int biome_category;
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_arid;
uniform float biome_savanna;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;

#include "/include/depth_utils.glsl"
#include "/include/sky_timeline.glsl"

vec3 getHazeColor() {

vec3 timelineColor = getTimelineHorizonColor(sunAngle, 0.0);
vec3 color = mix(fogColor, timelineColor, 0.5);
float snowW = getBiomeSnowyWeight(biome_snowy, biome, biome_category);
float swampW = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float jungleW = getBiomeJungleWeight(biome_jungle, biome, biome_category, swampW);
float aridW = getBiomeAridWeight(biome_arid, biome, biome_category);
float savannaW = getSavannaWeightWithoutSwamp(getBiomeSavannaWeight(biome_savanna, biome, biome_category), swampW);
color = getSmoothBiomeFogColorSavanna(color, snowW, jungleW, swampW, aridW, savannaW);
float luma = dot(color, vec3(0.299, 0.587, 0.114));

color = mix(vec3(luma), color, 1.5);
color = max(color, vec3(0.0));

float maxC = max(color.r, max(color.g, color.b));
if (maxC > 0.001) color /= maxC;
return color * HAZE_FOG_BRIGHTNESS;
}

vec3 getRainMatchedHazeColor() {
TimeWeights tw = getTimeWeights(sunAngle);

vec3 dayZenith      = vec3(DAY_ZENITH_R,      DAY_ZENITH_G,      DAY_ZENITH_B);
vec3 sunsetZenith   = vec3(SUNSET_ZENITH_R,   SUNSET_ZENITH_G,   SUNSET_ZENITH_B);
vec3 bluehourZenith = vec3(BLUEHOUR_ZENITH_R,  BLUEHOUR_ZENITH_G,  BLUEHOUR_ZENITH_B);
vec3 nightZenith    = vec3(NIGHT_ZENITH_R,     NIGHT_ZENITH_G,     NIGHT_ZENITH_B);
vec3 sunriseZenith  = vec3(SUNRISE_ZENITH_R,   SUNRISE_ZENITH_G,   SUNRISE_ZENITH_B);

vec3 zenithColor = dayZenith      * tw.day
+ sunsetZenith   * tw.sunset
+ bluehourZenith * tw.blueHour
+ nightZenith    * tw.night
+ sunriseZenith  * tw.sunrise;

float luma = dot(zenithColor, vec3(0.299, 0.587, 0.114));
zenithColor = mix(vec3(luma), zenithColor, 0.5);
zenithColor *= vec3(0.7, 0.75, 1.0);

float angle = fract(sunAngle);
float dayFactor = smoothstep(0.02, 0.08, angle) * (1.0 - smoothstep(0.44, 0.52, angle));
float nightFactor = smoothstep(0.55, 0.62, angle) * (1.0 - smoothstep(0.90, 0.96, angle));
float timeBrightness = max(dayFactor, nightFactor * 0.30);
float nightVisibility = clamp(tw.night + tw.blueHour * 0.35, 0.0, 1.0);

float brightnessScale = mix(1.15, 1.05, nightVisibility);

return zenithColor * WEATHER_FOG_BRIGHTNESS * timeBrightness * brightnessScale;
}

void main() {

vec2 fogRayTexcoord = (floor(gl_FragCoord.xy) / FOG_RENDER_SCALE + 0.5) / vec2(viewWidth, viewHeight);
#define texcoord fogRayTexcoord

#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome)) {

float nDepth1 = texture(depthtex1, texcoord).r;
float nVxDepth = texture(vxDepthTexTrans, texcoord).r;
vec4 nMask = texture(colortex1, texcoord);
bool nHasVoxy = (nVxDepth > 0.00001 && nVxDepth < 0.9999);

bool nIsEntity = (nMask.a > 0.01 && nMask.a < 0.99);

vec3 nWorldPos;
if (nIsEntity && nDepth1 < 0.9999) {

vec4 nClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, nDepth1 * 2.0 - 1.0, 1.0);
nWorldPos = (gbufferModelViewInverse * vec4(nClip.xyz / nClip.w, 1.0)).xyz + cameraPosition;
} else if (nHasVoxy) {
vec4 nClip = vxProjInv * vec4(texcoord * 2.0 - 1.0, nVxDepth * 2.0 - 1.0, 1.0);
nWorldPos = (gbufferModelViewInverse * vec4(nClip.xyz / nClip.w, 1.0)).xyz + cameraPosition;
} else if (nDepth1 < 0.9999 || nMask.a > 0.999) {
vec4 nClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, nDepth1 * 2.0 - 1.0, 1.0);
nWorldPos = (gbufferModelViewInverse * vec4(nClip.xyz / nClip.w, 1.0)).xyz + cameraPosition;
} else {
vec4 nSkyClip = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec3 nSkyDir = normalize(mat3(gbufferModelViewInverse) * (nSkyClip.xyz / nSkyClip.w));
nWorldPos = cameraPosition + nSkyDir * 640.0;
}

vec3 nRayDir = normalize(nWorldPos - cameraPosition);
float nMaxDist = min(length(nWorldPos - cameraPosition), 640.0);

int nSteps = 24;
float nStepSize = nMaxDist / float(nSteps);
float nDither = fract(52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y)
+ 0.6180339887 * float(frameCounter));

vec3 nHazeColorBase = vec3(1.0, 0.35, 0.08);
#ifdef BIOME_SOUL_SAND_VALLEY
if (biome == BIOME_SOUL_SAND_VALLEY) {
nHazeColorBase = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * 1.5;
}
#endif
vec3 nFogAccum = vec3(0.0);
float nTransmittance = 1.0;

for (int i = 0; i < nSteps; i++) {
float t = (float(i) + nDither) * nStepSize;
if (t > nMaxDist) break;
vec3 samplePos = cameraPosition + nRayDir * t;

float ht = clamp((samplePos.y - 31.0) / (45.0 - 31.0), 0.0, 1.0);

float heightFade = 1.0 - pow(ht, 0.3);
float localDensity = heightFade * 15.0 * nStepSize * 0.005;

if (localDensity > 0.0) {
float scatterFade = heightFade;
vec3 hazeColor = nHazeColorBase * (0.3 + 0.7 * scatterFade);
nFogAccum += hazeColor * localDensity * nTransmittance;
nTransmittance *= exp(-localDensity);
}
if (nTransmittance < 0.01) break;
}

float nFogOpacity = 1.0 - nTransmittance;

if (nMask.g > 0.5) {
nFogAccum *= 0.7;
nFogOpacity *= 0.7;
}

gl_FragData[0] = vec4(nFogAccum, nFogOpacity);
return;
}
#else
if (isForcedNetherBiome(biome)) {
gl_FragData[0] = vec4(0.0);
return;
}
#endif
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

if (isEyeInWater == 1) {
gl_FragData[0] = vec4(0.0);
return;
}

#ifdef HAZE_FOG_ENABLED

float depth0 = texture(depthtex0, texcoord).r;
float depth1 = texture(depthtex1, texcoord).r;
float dhDepth = texture(dhDepthTex, texcoord).r;
float vxDepth = texture(vxDepthTexTrans, texcoord).r;
bool hasDH = hasValidDHDepth(dhDepth);
bool hasVoxyDepth = (vxDepth > 0.00001 && vxDepth < 0.9999);
vec4 maskData = texture(colortex1, texcoord);
bool isVoxyLodPixel = (maskData.a > 0.999 && maskData.g < 0.01 && depth0 >= 0.9999);
bool isEntityOrHand = (maskData.a > 0.01 && maskData.a < 0.99);
bool isTranslucent = (depth0 < depth1 - 0.00001);
bool isWaterPixel = (texture(colortex5, texcoord).y > 0.9) && isTranslucent;
bool useVoxyDepthForHaze = hasVoxyDepth && (isTranslucent || isVoxyLodPixel);

float sceneDepth;
bool useVoxyProj = false;
if (isEntityOrHand) {

sceneDepth = depth0;
} else if (isWaterPixel && depth0 < 0.9999) {
sceneDepth = depth0;
} else if (useVoxyDepthForHaze) {
sceneDepth = vxDepth;
useVoxyProj = true;
} else if (isTranslucent && !isEntityOrHand) {
sceneDepth = (depth1 < 0.9999) ? depth1 : depth0;
} else if (isVoxyLodPixel) {
sceneDepth = depth0;
useVoxyProj = true;
} else {
sceneDepth = depth0;
}
bool hasMC = (sceneDepth < 0.9999) || isVoxyLodPixel || useVoxyDepthForHaze;

if (!hasMC && !hasDH) {

gl_FragData[0] = vec4(0.0);
return;
}

vec3 rayDir;
float maxDist;

if (hasMC) {
vec4 clipPos = vec4(texcoord * 2.0 - 1.0, sceneDepth * 2.0 - 1.0, 1.0);
mat4 projInv = useVoxyProj ? vxProjInv : gbufferProjectionInverse;
vec4 viewPos = projInv * clipPos;
viewPos /= viewPos.w;
vec3 worldPos = (gbufferModelViewInverse * viewPos).xyz + cameraPosition;
rayDir = normalize(worldPos - cameraPosition);
maxDist = length(worldPos - cameraPosition);
} else {

if (hasDH) {
float dhLinear = linearizeDepthDH(dhDepth);
vec4 clipFar = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec4 viewPosFar = gbufferProjectionInverse * clipFar;
vec3 viewDir = normalize(viewPosFar.xyz / max(viewPosFar.w, 0.0001));
maxDist = dhLinear / max(-viewDir.z, 0.001);
rayDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
} else {

vec4 vd4 = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
rayDir = normalize(mat3(gbufferModelViewInverse) * (vd4.xyz / vd4.w));
maxDist = float(HAZE_FOG_DIST_END);
}
}

float fogBottom = float(SEA_LEVEL_OFFSET) + float(HAZE_FOG_MIN_Y);
float hazeHeight = float(HAZE_FOG_MAX_Y - HAZE_FOG_MIN_Y);
float fogTop    = fogBottom + hazeHeight * (1.0 + rainStrength);
float fadeHeight = (fogTop - fogBottom) * 0.5;

float hazeRainPull = rainStrength * 0.8;
float tEntry = max(0.0, float(HAZE_FOG_DIST_START) * (1.0 - hazeRainPull));
float tExit  = min(maxDist, float(HAZE_FOG_DIST_END));

if (tEntry >= tExit) {
gl_FragData[0] = vec4(0.0);
return;
}

float segmentStartY = cameraPosition.y + rayDir.y * tEntry;
float segmentEndY = cameraPosition.y + rayDir.y * tExit;
if (max(segmentStartY, segmentEndY) < fogBottom || min(segmentStartY, segmentEndY) > fogTop) {
gl_FragData[0] = vec4(0.0);
return;
}

if (abs(rayDir.y) > 0.0001) {
float slabT0 = (fogBottom - cameraPosition.y) / rayDir.y;
float slabT1 = (fogTop    - cameraPosition.y) / rayDir.y;
float slabEntry = min(slabT0, slabT1);
float slabExit  = max(slabT0, slabT1);
tEntry = max(tEntry, slabEntry);
tExit  = min(tExit, slabExit);
if (tEntry >= tExit) {
gl_FragData[0] = vec4(0.0);
return;
}
}

float transitionZone = fadeHeight;
float insideAmount = smoothstep(fogTop + transitionZone, fogTop, cameraPosition.y)
* smoothstep(fogBottom - transitionZone, fogBottom, cameraPosition.y);
bool isInside = (insideAmount > 0.01);

float dither = 0.5;

vec3 hazeColor = getHazeColor();
vec3 rainMatchedHaze = getRainMatchedHazeColor();
hazeColor = mix(hazeColor, rainMatchedHaze, rainStrength);

float density = max(HAZE_FOG_DENSITY + rainStrength * 0.3, 0.01);
float playerSkylight = float(eyeBrightnessSmooth.y) / 240.0;
float caveEnclosure = 1.0 - smoothstep(0.18, 0.52, playerSkylight);
float hazeCaveCull = smoothstep(0.12, 0.55, caveEnclosure);

float marchLength = tExit - tEntry;
float stepSize = marchLength / float(HAZE_FOG_STEPS);

float densityScale = density * 0.003;

vec3  fogAccum = vec3(0.0);
float transmittance = 1.0;

for (int i = 0; i < HAZE_FOG_STEPS; i++) {
float t = tEntry + (float(i) + dither) * stepSize;
vec3 samplePos = cameraPosition + rayDir * t;

float topFade = smoothstep(fogTop, fogTop - fadeHeight, samplePos.y);
float bottomFade = smoothstep(fogBottom, fogBottom + 2.0, samplePos.y);
float heightFade = topFade * bottomFade;

float distEnd = float(HAZE_FOG_DIST_END);
float distFade = 1.0 - smoothstep(distEnd * 0.2, distEnd, t);

float localDensity = heightFade * distFade * densityScale * stepSize * (1.0 - hazeCaveCull);

if (localDensity > 0.0) {
fogAccum += hazeColor * localDensity * transmittance;
transmittance *= exp(-localDensity);
}

if (transmittance < 0.01) break;
}

float fogOpacity = 1.0 - transmittance;

float insideAtten = mix(1.0, HAZE_FOG_INSIDE_OPACITY, insideAmount);
fogOpacity *= insideAtten;
fogAccum *= insideAtten;

gl_FragData[0] = vec4(fogAccum, fogOpacity);
#else
gl_FragData[0] = vec4(0.0);
#endif
#undef texcoord
}

#else

in vec2 texcoord;

void main() {
gl_FragData[0] = vec4(0.0);
}

#endif
