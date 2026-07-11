#include "/settings.glsl"
#define VOXY_PROGRAM
#include "/include/water_color.glsl"
#include "/include/voxy_compat.glsl"
#include "/include/ocean_waves.glsl"

layout(location = 0) out vec4 voxyOut0;
layout(location = 1) out vec4 voxyOut1;
layout(location = 2) out vec4 voxyOut2;
layout(location = 3) out vec4 voxyOut3;
layout(location = 4) out vec4 voxyOut4;

#include "/include/noise.glsl"

void voxy_emitFragment(VoxyFragmentParameters parameters) {
vec4 src = parameters.sampledColour * parameters.tinting;
vec3 color = max(src.rgb, vec3(0.0));

float faceShade = mix(1.0, voxy_face_shade(parameters.face), VOXY_SHADOW_OPACITY);
color *= faceShade;

float skylight = clamp(parameters.lightMap.y, 0.0, 1.0);
float blocklight = clamp(parameters.lightMap.x, 0.0, 1.0);

uint rawId = parameters.customId;
uint id = voxy_block_id(rawId);
bool isWater = (rawId == 10001u || id == 1u);
bool isIce = (rawId == 10008u || id == 8u);
vec3 worldNormal = normalize(voxy_face_normal(parameters.face));

float postMask = isWater ? 0.0 : 1.0;
bool isEmissive = (rawId >= 10020u && rawId <= 10031u);
float emissive = isEmissive ? 1.0 : 0.0;
vec3 lightColor = vec3(0.0);
vec4 glassTint = vec4(0.0);
vec4 reflData = vec4(0.0);

#if defined(VOXY_TILE_BLUR_ENABLED) && !defined(END_SHADER)
vec4 flatSample = voxy_tile_blur(parameters.uv, gl_FragCoord.z);
vec3 flatColor = max((flatSample * parameters.tinting).rgb, vec3(0.0));
float flatStrength = voxy_tile_blur_strength(gl_FragCoord.z);
#endif

if (isWater) {
vec3 biomeBase = biomeWaterColor(sunAngle, 0.0, 0.0, 0.0, 0.0, 0.0);
glassTint = vec4(biomeBase, 0.3);
color = waterLitColor(color, sunAngle, skylight, blocklight);
src.a = clamp(WATER_OPACITY, 0.0, 1.0);

if (worldNormal.y > 0.5) {
reflData = vec4(0.0, 1.0, worldNormal.x * 0.5 + 0.5, worldNormal.y * 0.5 + 0.5);
}
} else if (isEmissive) {
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

src.a = clamp(src.a, 0.0, 1.0);
glassTint = vec4(clamp(src.rgb, vec3(0.0), vec3(1.0)), 0.6);
} else {
color = voxy_apply_chunk_like_lighting(color, sunAngle, skylight, blocklight, float(SEA_LEVEL_OFFSET) + 1.0);
color = voxy_apply_color_adjust(color);

#if defined(VOXY_TILE_BLUR_ENABLED) && !defined(END_SHADER)
flatColor = voxy_apply_chunk_like_lighting(flatColor, sunAngle, skylight, blocklight, float(SEA_LEVEL_OFFSET) + 1.0);
flatColor = voxy_apply_color_adjust(flatColor);
color = mix(color, flatColor, flatStrength);
#endif

src.a = clamp(src.a, 0.0, 1.0);
if (isIce) {
glassTint = vec4(clamp(src.rgb, vec3(0.0), vec3(1.0)), 0.8);
reflData = vec4(0.0, 0.0, worldNormal.x * 0.5 + 0.5, worldNormal.y * 0.5 + 0.5);
} else {
glassTint = vec4(clamp(src.rgb, vec3(0.0), vec3(1.0)), 0.6);
}
}

voxyOut0 = vec4(color, src.a);

voxyOut1 = vec4(postMask, emissive * VOXY_EMISSIVE_INTENSITY, skylight, 1.0);
voxyOut2 = vec4(lightColor, 1.0);
voxyOut3 = glassTint;
voxyOut4 = reflData;
}
