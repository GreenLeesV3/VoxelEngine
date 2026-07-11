/* RENDERTARGETS: 0,8 */
#extension GL_ARB_shader_storage_buffer_object : require

#include "/settings.glsl"
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

uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_savanna;

#ifdef CLOUDS_3D_ENABLED
#include "/include/volumetric_clouds.glsl"
#endif

#ifdef CLOUDS_VANILLA_ENABLED
#include "/include/vanilla_clouds.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D dhDepthTex;

uniform float near;
uniform float far;
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform float sunAngle;
uniform int worldDay;
uniform int worldTime;
uniform int frameCounter;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int biome;
uniform int biome_category;
uniform float rainStrength;
uniform float thunderStrength;
uniform float wetness;
uniform int isEyeInWater;
uniform float frameTimeCounter;

in vec2 texcoord;

#include "/include/depth_utils.glsl"

float getDhWorldY(vec2 uv, float depth) {
float linearDepth = linearizeDepthDH(depth);
vec4 clipPos = vec4(uv * 2.0 - 1.0, -1.0, 1.0);
vec4 viewPosNear = gbufferProjectionInverse * clipPos;
viewPosNear /= viewPosNear.w;
vec3 viewDir = normalize(viewPosNear.xyz);
vec3 viewPos = viewDir * (linearDepth / max(abs(viewDir.z), 0.001));
vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
return worldPos.y + cameraPosition.y;
}

bool isEnd() {
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

void main() {
vec3 color = texture(colortex0, texcoord).rgb;
vec3 cloudColor = vec3(0.0);
float cloudAlpha = 0.0;
float cloudDepthOut = 0.0;

float dhDepth = texture(dhDepthTex, texcoord).r;
bool hasDhAtPixel = hasValidDHDepth(dhDepth);
float depth0 = texture(depthtex0, texcoord).r;
float depth1 = texture(depthtex1, texcoord).r;
vec4 maskData = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0);
bool isEntityOrHand = (maskData.a > 0.01 && maskData.a < 0.99);

float cloudSceneDepth = isEntityOrHand ? depth0 : depth1;
bool isSky = (cloudSceneDepth >= 1.0);

vec3 cloudDir;
float cloudMaxDistVanilla;
float cloudMaxDist3D;

if (!isSky && isEyeInWater != 1) {

float closestDepth = cloudSceneDepth;
vec4 clipPos = vec4(texcoord * 2.0 - 1.0, closestDepth * 2.0 - 1.0, 1.0);
vec4 viewPos = gbufferProjectionInverse * clipPos;
viewPos /= viewPos.w;
vec3 worldPos = (gbufferModelViewInverse * viewPos).xyz + cameraPosition;
cloudDir = normalize(worldPos - cameraPosition);
float sceneDist = length(worldPos - cameraPosition);
cloudMaxDistVanilla = sceneDist;
cloudMaxDist3D = sceneDist;
} else {

cloudDir = normalize(mat3(gbufferModelViewInverse) * (gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0)).xyz);
cloudMaxDistVanilla = 30000.0;
cloudMaxDist3D = 30000.0;

if (isEyeInWater == 1 && !isSky) {
float closestDepth = cloudSceneDepth;
vec4 clipPos = vec4(texcoord * 2.0 - 1.0, closestDepth * 2.0 - 1.0, 1.0);
vec4 viewPos = gbufferProjectionInverse * clipPos;
viewPos /= viewPos.w;
float sceneDist = length(viewPos.xyz);
cloudMaxDistVanilla = min(cloudMaxDistVanilla, sceneDist);
cloudMaxDist3D = min(cloudMaxDist3D, sceneDist);
}

if (hasDhAtPixel) {
float dhLinear = linearizeDepthDH(dhDepth);

vec4 clipFar = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec4 viewPosFar = gbufferProjectionInverse * clipFar;
vec3 viewDir = normalize(viewPosFar.xyz / max(viewPosFar.w, 0.0001));
float dhRayDist = dhLinear / max(-viewDir.z, 0.001);
float cappedDist = max(dhRayDist - 1.0, 0.0);
cloudMaxDistVanilla = min(cloudMaxDistVanilla, cappedDist);
cloudMaxDist3D = min(cloudMaxDist3D, cappedDist);
}
}

if (isEyeInWater == 1) {

float uwTRay = (float(SEA_LEVEL_OFFSET) - cameraPosition.y) / max(cloudDir.y, 0.001);
vec2 uwSurfXZ = cameraPosition.xz + cloudDir.xz * max(uwTRay, 0.0);
vec2 uwWP = uwSurfXZ * 0.5;
float uwT = frameTimeCounter * WATER_WAVE_SPEED;
float uwSx = cos(uwWP.x * 2.0 + uwWP.y * 0.7 + uwT * 1.2) * 0.3
+ cos(uwWP.x * 1.3 - uwWP.y * 1.8 + uwT * 0.8) * 0.2;
float uwSz = cos(uwWP.y * 2.2 + uwWP.x * 0.5 + uwT * 1.0) * 0.3
+ cos(uwWP.y * 1.5 - uwWP.x * 1.6 + uwT * 1.1) * 0.2;
cloudDir = normalize(cloudDir + vec3(uwSx, 0.0, uwSz) * 0.02);
}

vec3 smoothedCloudSky = getSmoothedBiomeSkyColorRaw(skyColor);
float wSnow = getBiomeVisualSnowyWeight(biome_snowy);
float wSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float wJungle = getBiomeJungleWeight(biome_jungle, biome, biome_category, wSwamp);
float wArid = getBiomeVisualAridWeight(biome_arid);
float wSavanna = getSavannaWeightWithoutSwamp(getBiomeVisualSavannaWeight(biome_savanna), wSwamp);
vec3 biomeAtmColor = getSmoothBiomeSkyZenithSavanna(smoothedCloudSky, wSnow, wJungle, wSwamp, wArid, wSavanna);
float biomeAtmLum = max(dot(biomeAtmColor, vec3(0.299, 0.587, 0.114)), 0.001);

float btAngle = fract(sunAngle);
float biomeTintAmount = smoothstep(0.0, 0.07, btAngle) * smoothstep(0.57, 0.48, btAngle) * 0.75;

float cloudBiomeOpacity = (1.0 - wArid) * (1.0 - wSwamp);

cloudBiomeOpacity *= mix(1.0, 0.2, clamp(biome_pale_garden, 0.0, 1.0));
float cloudRainFade = (1.0 - wetness * (float(CLOUD_RAIN_OPACITY_REDUCTION) / 100.0)) * cloudBiomeOpacity;

if (isEyeInWater == 1) cloudRainFade *= 0.3;

#ifdef CLOUDS_VANILLA_ENABLED
if (!isEnd() && !isForcedNetherBiome(biome)) {
vec3 vanSunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);

float vanTimeSec = frameTimeCounter;

float vanHitT = 0.0;
vec4 vanResult = computeVanillaClouds(cloudDir, vanTimeSec, cameraPosition, sunAngle, vanSunDir, cloudMaxDistVanilla, gl_FragCoord.xy, frameCounter, vanHitT, cloudRainFade);
if (vanResult.a > 0.001) {

float cLum = max(dot(vanResult.rgb, vec3(0.299, 0.587, 0.114)), 0.001);
vec3 biomeMatch = clamp(biomeAtmColor * (cLum / biomeAtmLum), vec3(0.0), vec3(2.0));
vanResult.rgb = mix(vanResult.rgb, biomeMatch, biomeTintAmount);
cloudColor = vanResult.rgb;
cloudAlpha = max(cloudAlpha, vanResult.a);
cloudDepthOut = vanHitT;
}
}
#endif

#ifdef CLOUDS_3D_ENABLED
if (!isEnd() && !isForcedNetherBiome(biome)) {
vec3 vc3dSunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
float gameTimeSec = (float(worldDay) * 24000.0 + float(worldTime)) / 20.0;

float vc3dHitT = 0.0;
vec4 vc3dResult = renderVolumetricClouds(cloudDir, gameTimeSec, cameraPosition, sunAngle, vc3dSunDir, cloudMaxDist3D, gl_FragCoord.xy, frameCounter, vc3dHitT);
vc3dResult.a *= cloudRainFade;

if (vc3dResult.a > 0.001) {
float cLum = max(dot(vc3dResult.rgb, vec3(0.299, 0.587, 0.114)), 0.001);
vec3 biomeMatch = clamp(biomeAtmColor * (cLum / biomeAtmLum), vec3(0.0), vec3(2.0));
vc3dResult.rgb = mix(vc3dResult.rgb, biomeMatch, biomeTintAmount);

cloudColor = cloudColor * (1.0 - vc3dResult.a) + vc3dResult.rgb;
cloudAlpha = max(cloudAlpha, vc3dResult.a);
if (vc3dHitT > 0.0 && (cloudDepthOut <= 0.0 || vc3dHitT < cloudDepthOut)) cloudDepthOut = vc3dHitT;
}
}
#endif

gl_FragData[0] = vec4(color, 1.0 - cloudAlpha);
gl_FragData[1] = vec4(cloudColor, cloudAlpha > 0.001 ? cloudDepthOut : 0.0);
}
