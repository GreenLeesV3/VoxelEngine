/* RENDERTARGETS: 11 */

#include "/settings.glsl"

#ifdef WEATHER_FOG_ENABLED

#include "/include/shadow.glsl"
#include "/include/biome_overrides.glsl"

#ifdef LPV_ENABLED
#include "/include/lpv/lpv_common.glsl"
#endif

in vec2 texcoord;

uniform sampler2D colortex1;
uniform sampler2D colortex11;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D dhDepthTex;
uniform sampler2D shadowtex0;
uniform sampler2D noisetex;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 vxProjInv;
uniform sampler2D vxDepthTexTrans;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float sunAngle;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform float rainStrength;
uniform float thunderStrength;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform int biome;
uniform int biome_category;
uniform int isEyeInWater;
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_arid;
uniform float biome_savanna;

#ifdef LPV_ENABLED
uniform sampler3D lpvLightSamplerA;
uniform sampler3D lpvLightSamplerB;

vec3 weatherFogLpvTap(vec3 uv) {
return (frameCounter & 1) == 0 ? texture(lpvLightSamplerA, uv).rgb : texture(lpvLightSamplerB, uv).rgb;
}

vec3 weatherFogLpvSample(vec3 worldPos) {
vec3 scenePos = worldPos - cameraPosition;
vec3 voxelPos = sceneToVoxelSpace(scenePos, cameraPosition);
if (!isInVoxelVolume(voxelPos)) return vec3(0.0);

vec3 uv = voxelPos / lpvVolumeSize;
vec3 lpvLight = compressRawLpvLight(weatherFogLpvTap(uv)) * WEATHER_FOG_LPV_STRENGTH;
return softCapLpvLight(lpvLight, 0.018, 0.006);
}
#endif

#include "/include/noise.glsl"
#include "/include/sky_timeline.glsl"
#include "/include/depth_utils.glsl"

#ifdef LIGHTNING_ENABLED
#include "/include/lightning.glsl"
#endif

vec3 getWeatherFogColor(float timeBrightness) {
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

float nightVisibility = clamp(tw.night + tw.blueHour * 0.35, 0.0, 1.0);
float brightnessScale = mix(0.7, 0.9, nightVisibility);
return zenithColor * WEATHER_FOG_BRIGHTNESS * timeBrightness * brightnessScale;
}

void main() {

vec2 fogRayTexcoord = (floor(gl_FragCoord.xy) / FOG_RENDER_SCALE + 0.5) / vec2(viewWidth, viewHeight);
#define texcoord fogRayTexcoord

float swampW = getBiomeSwampWeight(biome_swamp, biome, biome_category);
if (rainStrength < 0.01 && swampW < 0.01) {
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

if (isEyeInWater == 1) {
gl_FragData[0] = vec4(0.0);
return;
}

float depth0 = texture(depthtex0, texcoord).r;
float depth1 = texture(depthtex1, texcoord).r;
float vxDepth = texture(vxDepthTexTrans, texcoord).r;
bool hasVoxyDepth = (vxDepth > 0.00001 && vxDepth < 0.9999);
vec4 maskData = texture(colortex1, texcoord);

bool isVoxyLodPixel = (maskData.a > 0.999 && maskData.g < 0.01 && depth0 >= 0.9999);
bool isTranslucent = (depth0 < depth1 - 0.00001);
bool isEntityPixel = (maskData.a > 0.01 && maskData.a < 0.99);

float sceneDepth;
bool useVoxyProj = false;
if (isEntityPixel) {
sceneDepth = depth0;
} else if (hasVoxyDepth && (isTranslucent || isVoxyLodPixel)) {
sceneDepth = vxDepth;
useVoxyProj = true;
} else if (isTranslucent) {

sceneDepth = (depth1 < 0.9999) ? depth1 : depth0;
} else if (isVoxyLodPixel) {
sceneDepth = depth0;
useVoxyProj = true;
} else {
sceneDepth = depth0;
}
bool isSky = (sceneDepth >= 1.0) && !hasVoxyDepth && !isVoxyLodPixel;
float dhDepth = texture(dhDepthTex, texcoord).r;
bool hasDH = hasValidDHDepth(dhDepth);

vec3 rayDir;
float maxDist;

if (!isSky) {
vec4 clipPos = vec4(texcoord * 2.0 - 1.0, sceneDepth * 2.0 - 1.0, 1.0);
mat4 projInv = useVoxyProj ? vxProjInv : gbufferProjectionInverse;
vec4 viewPos = projInv * clipPos;
viewPos /= viewPos.w;
vec3 worldPos = (gbufferModelViewInverse * viewPos).xyz + cameraPosition;
rayDir = normalize(worldPos - cameraPosition);
maxDist = length(worldPos - cameraPosition);
} else if (hasDH) {
float dhLinear = linearizeDepthDH(dhDepth);
vec4 clipFar = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec4 viewPosFar = gbufferProjectionInverse * clipFar;
vec3 viewDir = normalize(viewPosFar.xyz / max(viewPosFar.w, 0.0001));
maxDist = dhLinear / max(-viewDir.z, 0.001);
rayDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
} else {
vec4 vd4 = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
rayDir = normalize(mat3(gbufferModelViewInverse) * (vd4.xyz / vd4.w));
maxDist = 256.0;
}

maxDist = min(maxDist, 256.0);

float tEntry = WEATHER_FOG_NEAR_DIST;
float tExit  = maxDist;

if (tEntry >= tExit) {
gl_FragData[0] = vec4(0.0);
return;
}

vec3 windOffset = vec3(-1.0, -0.3, 0.0) * frameTimeCounter * 12.0;

float blueNoise = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 255, 0).b;
float dither = fract(blueNoise + float(frameCounter) * 0.6180339887);

float angle = fract(sunAngle);
float dayFactor = smoothstep(0.02, 0.08, angle) * (1.0 - smoothstep(0.44, 0.52, angle));
float nightFactor = smoothstep(0.55, 0.62, angle) * (1.0 - smoothstep(0.90, 0.96, angle));
float timeBrightness = max(dayFactor, nightFactor * 0.30);
TimeWeights twWeather = getTimeWeights(sunAngle);
float weatherFogNightBoost = clamp(twWeather.night + twWeather.blueHour * 0.35, 0.0, 1.0);

vec3 fogColor = getWeatherFogColor(timeBrightness);

float snowW = getBiomeSnowyWeight(biome_snowy, biome, biome_category);
float jungleW = getBiomeJungleWeight(biome_jungle, biome, biome_category, swampW);
float aridW = getBiomeAridWeight(biome_arid, biome, biome_category);
float savannaW = getSavannaWeightWithoutSwamp(getBiomeSavannaWeight(biome_savanna, biome, biome_category), swampW);
float biomeFogW = max(max(max(snowW, jungleW), max(swampW, aridW)), savannaW);
if (biomeFogW > 0.001) {
vec3 biomeFogTint = getSmoothBiomeFogColorSavanna(vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B), snowW, jungleW, swampW, aridW, savannaW);
float biomeLuma = dot(biomeFogTint, vec3(0.299, 0.587, 0.114));
biomeFogTint = mix(vec3(biomeLuma), biomeFogTint, 0.6);
biomeFogTint *= timeBrightness * WEATHER_FOG_BRIGHTNESS * 0.7;
fogColor = mix(fogColor, biomeFogTint, 0.6 * biomeFogW);
}

TimeWeights twFog = getTimeWeights(sunAngle);
float twilightBlend = twFog.sunset + twFog.sunrise;
vec3 sunsetHorizon = vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B) * SUNSET_BRIGHTNESS;
vec3 sunriseHorizon = vec3(SUNRISE_HORIZON_R, SUNRISE_HORIZON_G, SUNRISE_HORIZON_B) * SUNRISE_BRIGHTNESS;
vec3 twilightColor = (sunsetHorizon * twFog.sunset + sunriseHorizon * twFog.sunrise) / max(twilightBlend, 0.001);

if (twilightBlend > 0.01) {
fogColor = mix(fogColor, twilightColor * 0.5, twilightBlend * 0.4);
}

vec3 swampFogColor = vec3(0.0);
float swampDensity = 0.0;
if (swampW > 0.01) {
swampFogColor = vec3(30.0, 55.0, 25.0) / 255.0;
swampFogColor *= timeBrightness * 3.0;

if (twilightBlend > 0.01) {
swampFogColor = mix(swampFogColor, twilightColor * 0.4, twilightBlend * 0.5);
}
fogColor = mix(fogColor, swampFogColor, swampW);
swampDensity = 1.5 * swampW;
}

float thunderBoost = 1.0 + rainStrength * WEATHER_FOG_THUNDER_BOOST;
float density = WEATHER_FOG_DENSITY * rainStrength * thunderBoost * mix(1.0, 2.0, weatherFogNightBoost);

float marchLength = tExit - tEntry;
const float weatherExpFactor = 11.0;
float weatherStepCount = float(WEATHER_FOG_STEPS);

vec3  fogAccum = vec3(0.0);
float transmittance = 1.0;

for (int i = 0; i < WEATHER_FOG_STEPS; i++) {
float weatherStep = (float(i) + dither) / weatherStepCount;
float weatherExpSample = pow(weatherExpFactor, weatherStep);
float weatherSamplePos = (weatherExpSample - 1.0) / (weatherExpFactor - 1.0);
float weatherSegmentLen = weatherExpSample * log(weatherExpFactor) / weatherStepCount / (weatherExpFactor - 1.0) * marchLength;
float t = tEntry + weatherSamplePos * marchLength;
vec3 samplePos = cameraPosition + rayDir * t;

vec3 noiseCoord = (samplePos + windOffset) * WEATHER_FOG_NOISE_SCALE;
float noiseSample = noise3D(noiseCoord);

float fogPresence = smoothstep(0.2, 0.65, noiseSample);

float distFade = smoothstep(WEATHER_FOG_NEAR_DIST, WEATHER_FOG_FAR_DIST, t);

float localDensity = fogPresence * distFade * density * 0.002;

if (swampW > 0.01) {
vec3 swampNoiseCoord = (samplePos + windOffset * 0.3) * 0.04;
float swampNoise = noise3D(swampNoiseCoord);
float swampPresence = smoothstep(0.25, 0.6, swampNoise);
float swampDistFade = smoothstep(8.0, 80.0, t);
float swampLocalDensity = swampPresence * swampDistFade * swampDensity * 0.01;
if (swampLocalDensity * weatherSegmentLen > 0.0001) {
float swampExtinction = min(swampLocalDensity * weatherSegmentLen, 0.08);
float swampStepWeight = transmittance * (1.0 - exp(-swampExtinction));
fogAccum += swampFogColor * swampStepWeight;
transmittance *= exp(-swampExtinction);
}
}

if (localDensity * weatherSegmentLen > 0.000001) {

float shadow = 1.0;
#ifdef SHADOWS_ENABLED
{
vec3 scenePos = samplePos - cameraPosition;
vec4 shadowViewPos = shadowModelView * vec4(scenePos, 1.0);
vec4 shadowClipPos = shadowProjection * shadowViewPos;
vec3 shadowNDC = distortShadowClipPos(shadowClipPos.xyz);
vec3 shadowScreenPos = shadowNDC * 0.5 + 0.5;
shadowScreenPos.z -= 0.0005;

if (shadowScreenPos.x > 0.0 && shadowScreenPos.x < 1.0 &&
shadowScreenPos.y > 0.0 && shadowScreenPos.y < 1.0 &&
shadowScreenPos.z > 0.0 && shadowScreenPos.z < 1.0) {
shadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
}
}
#endif

float extinction = min(localDensity * weatherSegmentLen, 0.08);
float scatterExtinction = min(localDensity * shadow * weatherSegmentLen, 0.08);
float stepTransmittance = exp(-extinction);
float stepWeight = transmittance * (1.0 - stepTransmittance);
float scatterWeight = transmittance * (1.0 - exp(-scatterExtinction));

#ifdef LIGHTNING_ENABLED
{
float lGlow = getLightningGlow(samplePos, frameTimeCounter, thunderStrength);
fogAccum += vec3(LIGHTNING_R, LIGHTNING_G, LIGHTNING_B) * scatterWeight * lGlow;
}
#endif

#ifdef LPV_ENABLED
vec3 lpvFogLight = weatherFogLpvSample(samplePos);
fogAccum += lpvFogLight * stepWeight;
#endif

fogAccum += fogColor * scatterWeight;
transmittance *= stepTransmittance;
}

if (transmittance < 0.01) break;
}

float fogOpacity = 1.0 - transmittance;

gl_FragData[0] = vec4(fogAccum, fogOpacity);
#undef texcoord
}

#else

in vec2 texcoord;

void main() {
gl_FragData[0] = vec4(0.0);
}

#endif
