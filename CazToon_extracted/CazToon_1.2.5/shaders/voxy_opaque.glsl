#include "/settings.glsl"
#define VOXY_PROGRAM
#define VOXY_HAS_SSBO

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

#include "/include/voxy_compat.glsl"
#include "/include/noise.glsl"
#include "/include/lava_crust.glsl"
#include "/include/biome_overrides.glsl"

vec3 voxy_grass_fallback_tint(int b) {
if (isForcedSwampyBiome(b))  return vec3(0.41, 0.43, 0.22);
if (isForcedJungleBiome(b))  return vec3(0.36, 0.75, 0.18);
if (isForcedSavannaBiome(b)) return vec3(0.71, 0.73, 0.34);
if (isForcedDesertBiome(b))  return vec3(0.75, 0.70, 0.33);
if (isForcedSnowyBiome(b))   return vec3(0.50, 0.65, 0.45);
return vec3(0.49, 0.73, 0.33);
}

layout(location = 0) out vec4 voxyOut0;
layout(location = 1) out vec4 voxyOut1;
layout(location = 2) out vec4 voxyOut2;

void voxy_emitFragment(VoxyFragmentParameters parameters) {
uint rawId = parameters.customId;
uint id = voxy_block_id(rawId);

vec4 src;
vec3 rawTint;
if (id == 15u && parameters.face >= 2u) {
rawTint = voxy_grass_fallback_tint(biome);
} else {
rawTint = parameters.tinting.rgb;
}
float tintMax = max(max(rawTint.r, rawTint.g), rawTint.b);
vec3 normTint = (tintMax > 0.001) ? rawTint / tintMax : rawTint;
src = vec4(parameters.sampledColour.rgb * normTint, parameters.sampledColour.a);
vec3 color = max(src.rgb, vec3(0.0));

#ifdef VOXY_DEBUG_BRIGHTNESS_MATCH
vec3 debugRawColorLod = color;
#endif

if (rawId == 10060u || rawId == 10061u || rawId == 10062u) discard;

vec2 voxyScreenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
vec3 voxyNdc = vec3(voxyScreenUV, gl_FragCoord.z) * 2.0 - 1.0;
vec4 voxyViewH = vxProjInv * vec4(voxyNdc, 1.0);
vec3 voxyViewPos = voxyViewH.xyz / voxyViewH.w;
vec3 voxyWorldPos = (gbufferModelViewInverse * vec4(voxyViewPos, 1.0)).xyz + cameraPosition;
float voxyUnderwaterDepthMask = 0.0;
if (isEyeInWater == 1) {
voxyUnderwaterDepthMask = 1.0 - smoothstep(float(SEA_LEVEL_OFFSET) - 2.0, float(SEA_LEVEL_OFFSET) + 1.0, voxyWorldPos.y);
}

float rawSkylight = clamp(parameters.lightMap.y, 0.0, 1.0);
bool isCave = (rawSkylight < 2.0 / 15.0);
float faceShade = (voxyWorldPos.y < float(SEA_LEVEL_OFFSET) && !isCave) ? 1.0 : mix(1.0, voxy_face_shade(parameters.face), VOXY_SHADOW_OPACITY);
color *= faceShade;

float skylight = clamp(parameters.lightMap.y, 0.0, 1.0);

if (isEyeInWater == 1) {
skylight = max(skylight, (1.0 / 15.0) * voxyUnderwaterDepthMask);
}

float blocklight = clamp(parameters.lightMap.x, 0.0, 1.0);

bool isSculk = (rawId == 10046u || rawId == 10056u || rawId == 10057u);
bool isEmissive = (rawId >= 10020u && rawId <= 10059u) && !isSculk;
float emissive = isEmissive ? 1.0 : 0.0;
vec3 lightColor = vec3(0.0);

#if defined(VOXY_TILE_BLUR_ENABLED) && !defined(END_SHADER)

vec4 flatSample = voxy_tile_blur(parameters.uv, gl_FragCoord.z);
vec3 flatColor = max((flatSample * parameters.tinting).rgb, vec3(0.0));
flatColor *= faceShade;
float flatStrength = voxy_tile_blur_strength(gl_FragCoord.z);
#endif

if (!isEmissive) {
color = voxy_apply_chunk_like_lighting(color, sunAngle, skylight, blocklight, voxyWorldPos.y);

#if defined(VOXY_TILE_BLUR_ENABLED) && !defined(END_SHADER)
flatColor = voxy_apply_chunk_like_lighting(flatColor, sunAngle, skylight, blocklight, voxyWorldPos.y);
#endif

} else {
vec3 whiteGlow = vec3(1.0);
vec3 coloredGlow = src.rgb;
vec3 emissiveColor = mix(whiteGlow, coloredGlow, VOXY_EMISSIVE_COLOR_STRENGTH);
float cappedBrightness = min(EMISSIVE_BRIGHTNESS * VOXY_LOD_BRIGHTNESS, VOXY_EMISSIVE_BRIGHTNESS_CAP);
color = emissiveColor * cappedBrightness;

if (rawId == 10022u) {
lightColor = vec3(1.0, 0.4, 0.1);
} else {
float brightness = max(max(src.r, src.g), src.b);
if (brightness > 0.01) {
lightColor = normalize(src.rgb + 0.1) * 1.2;
} else {
lightColor = vec3(1.0, 0.85, 0.6);
}
}
lightColor *= VOXY_EMISSIVE_INTENSITY;

}

bool isLava = (rawId == 10039u || id == 39u);

#if defined(VOXY_TILE_BLUR_ENABLED) && !defined(END_SHADER)
if (!isLava) color = mix(color, flatColor, flatStrength);
#endif

#ifdef LAVA_CRUST_ENABLED
if (isLava) {
vec3 voxyN = voxy_face_normal(parameters.face);
color = applyLavaCrust(color, voxyWorldPos, voxyN);

#ifdef BIOME_SOUL_SAND_VALLEY
if (biome == BIOME_SOUL_SAND_VALLEY) {
float lavaLum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 blueLava = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * lavaLum * 2.0;
color = blueLava;
}
#endif
}
#endif

#if defined(END_SHADER) && defined(END_TERRAIN_PATCHES_ENABLED)
if (!isEmissive) {
vec3 patchPos3D = voxyWorldPos * END_TERRAIN_PATCH_SCALE;
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
color *= patchDark;
}
#endif

if (isEyeInWater == 1) {
color *= mix(1.0, 1.05, voxyUnderwaterDepthMask);
}

{
bool isMagma = (rawId == 10040u || id == 40u);

bool isSoulValley = (smoothNetherFogB > smoothNetherFogR * 1.5);
if ((isLava || isMagma) && isSoulValley) {
float bloomLum = dot(lightColor, vec3(0.299, 0.587, 0.114));
lightColor = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * bloomLum * 2.0;

if (isMagma) {
float magmaWarmth = max(color.r - color.b, 0.0);
float magmaLum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 blueMagma = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * magmaLum * 2.0;
color = mix(color, blueMagma, smoothstep(0.05, 0.2, magmaWarmth));
}
}
}

#ifdef VOXY_DEBUG_BRIGHTNESS_MATCH
{
float litLuma = dot(color, vec3(0.299, 0.587, 0.114));
color = vec3(litLuma);
}
#endif

voxyOut0 = vec4(color, 1.0);

voxyOut1 = vec4(1.0, emissive * VOXY_EMISSIVE_INTENSITY, skylight, 1.0);
voxyOut2 = vec4(lightColor, 1.0);
}
