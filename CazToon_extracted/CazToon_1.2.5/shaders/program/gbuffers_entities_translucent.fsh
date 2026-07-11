/* RENDERTARGETS: 0,1,3 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"

uniform sampler2D gtexture;
uniform int entityId;
uniform float frameTimeCounter;
uniform float sunAngle;
uniform vec3 fogColor;
uniform int biome_category;
uniform float fogStart;
uniform float fogEnd;
uniform vec3 cameraPosition;
#ifdef LPV_ENABLED
uniform mat4 gbufferModelViewInverse;
#endif
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor1;
uniform vec3 shadowLightPosition;
uniform int frameCounter;
uniform int isEyeInWater;
uniform vec4 entityColor;
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_arid;
uniform float biome_savanna;

#include "/include/shadow.glsl"
#include "/include/lighting.glsl"
#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
#include "/include/end_event.glsl"
#endif

in vec2 texcoord;
in vec4 glcolor;
in vec3 worldPos;
in float skylight;
in float blocklight;
in float viewDistance;
in float nametagHolo;
in vec4 shadowPos;
in vec3 normal;

#include "/include/fog_color.glsl"

#include "/include/noise.glsl"

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;

float magentaTest = color.r - color.g + color.b - color.g;
if (magentaTest > 1.0 && color.g < 0.15) {
color = glcolor;
color.a = max(color.a, 0.7);
}

color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);

if (color.a < 0.01) {
discard;
}

float entityShadowMax = max(color.r, max(color.g, color.b));
bool vanillaEntityShadow = (entityId != 20002 && color.a < 0.9 && entityShadowMax < 0.08 && entityColor.a < 0.001 && nametagHolo < 0.5);
#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
if (vanillaEntityShadow && getEndEventTerrainDarkness(frameTimeCounter) > 0.98) {
discard;
}
#endif

if (entityId == 20002 || color.a < 0.9) {
gl_FragData[0] = color;
float entityLayerMarker = 0.5;
#ifdef END_SHADER
if (vanillaEntityShadow) entityLayerMarker = 0.0;
#endif
gl_FragData[1] = vec4(0.0, 0.0, 0.0, entityLayerMarker);
gl_FragData[2] = vec4(0.0);
return;
}

#ifdef MAGICAL_TOUCH

float maxC = max(max(glcolor.r, glcolor.g), glcolor.b);
float minC = min(min(glcolor.r, glcolor.g), glcolor.b);
float chroma = maxC - minC;
bool neutralFaceShade = (maxC > 0.70 && chroma < 0.035);
if (neutralFaceShade) color.rgb /= maxC;
#else
vec3 worldNormalFace = normalize(mat3(gbufferModelViewInverse) * normal);
color.rgb *= getVanillaFaceShade(worldNormalFace);
#endif

#ifdef CHUNK_FADE_OUT_ENABLED
#ifndef DISTANT_HORIZONS
if (!isForcedNetherBiome(biome) && !isForcedEndBiome(biome)) {
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
color.a *= visible;
if (color.a < 0.01) {
discard;
}
}
}
#endif
#endif

vec3 entityRawColor = color.rgb;
float entityMaskSkylight = skylight;
#ifdef LPV_ENABLED

lpvSurfaceColor = entityRawColor;
lpvTexLuma = dot(entityRawColor, vec3(0.299, 0.587, 0.114));
lpvNeutralPreserveStrength = 1.0;
#endif
float emissive = 0.0;

if (entityId == 100) {

} else if (entityId == 101) {
if (color.r > 0.8 && color.g < 0.2 && color.b < 0.2) emissive = 1.0 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 102) {

} else if (entityId == 103) {
if (color.r > 0.7 && color.g > 0.8 && color.b < 0.4) emissive = 0.8 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 104) {
if (color.r > 0.8 && color.g > 0.9 && color.b > 0.9) emissive = 0.9 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 105) {
emissive = 0.7 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 106) {
if (color.r > 0.5 && color.g > 0.8 && color.b > 0.9) emissive = 0.8 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 107) {
if (color.r > 0.6 && color.g < 0.3 && color.b < 0.3) emissive = 0.9 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 108) {
if (color.r > 0.9 && color.g > 0.5 && color.b < 0.6) emissive = 0.6 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 109) {
emissive = 0.0;
}

vec3 entityEmissiveVisible = vec3(0.0);
vec3 entityEmissiveBloom = vec3(0.0);
if (emissive > 0.5) {
float entityEmissiveScale = EMISSIVE_BRIGHTNESS * max(emissive, 1.0);
float entityBloomSeedBoost = 1.25 + 0.75 * max(emissive, 1.0);
entityEmissiveVisible = entityRawColor * entityEmissiveScale * ENTITY_EMISSIVE_BRIGHTNESS;
entityEmissiveBloom = entityRawColor * entityEmissiveScale * ENTITY_EMISSIVE_BLOOM * entityBloomSeedBoost;
}

if (entityId == 105 && emissive > 0.5) {
entityEmissiveVisible = entityRawColor;
entityEmissiveBloom = entityRawColor * 0.01;
}

if (entityId == 109) {
entityEmissiveBloom = entityRawColor * EMISSIVE_BRIGHTNESS * 0.5;
}

#ifdef SHADOWS_ENABLED
if (shadowPos.w > 0.5 && emissive < 0.5) {
float dotNL = dot(normal, normalize(shadowLightPosition));

float dither = hash12(gl_FragCoord.xy);
float r = quartic_length(shadowPos.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;

vec3 biasedShadowPos = shadowPos.xyz;
biasedShadowPos.z -= 0.0005;

#ifdef MAGICAL_TOUCH
vec3 shadow = getShadowColorSharpNoEntity(shadowtex0, shadowcolor0, shadowcolor1, biasedShadowPos, 0.0);
#else
vec3 shadow = getShadowColorPCFNoEntity(shadowtex0, shadowcolor0, shadowcolor1, biasedShadowPos, distortFactor, dither, 0.0);
#endif

float rawShadowVal = dot(shadow, vec3(0.299, 0.587, 0.114));
float entityDirectSunLit = rawShadowVal;
float entitySkylight = max(skylight, min(rawShadowVal * 0.95, 1.0 / 15.0));
entityMaskSkylight = entitySkylight;

shadow = mix(vec3(1.0), shadow, entitySkylight);

shadow = mix(vec3(1.0), shadow, SHADOW_OPACITY);

#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
lpvReceiverStrength = smoothstep(0.02, 0.20, blocklight);
#endif
vec3 lightingBaseColor = color.rgb;
float entitySunOverrideSkyHint = smoothstep(0.5 / 15.0, 2.0 / 15.0, skylight);
float entitySunOverrideHeightGate = smoothstep(float(SEA_LEVEL_OFFSET) - 4.0, float(SEA_LEVEL_OFFSET) + 2.0, worldPos.y);
float entitySunOverrideGate = max(entitySunOverrideSkyHint, entitySunOverrideHeightGate);
directSunVisibility = clamp(entityDirectSunLit * getStableDayFactor(sunAngle) * entitySunOverrideGate, 0.0, 1.0);
color.rgb = applyLightingWithShadow(lightingBaseColor, sunAngle, entitySkylight, blocklight, emissive, shadow, worldPos.y);
} else {
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
lpvReceiverStrength = smoothstep(0.02, 0.20, blocklight);
#endif
color.rgb = applyLightingEmissive(color.rgb, sunAngle, skylight, blocklight, emissive, worldPos.y);
}
#else
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
lpvReceiverStrength = smoothstep(0.02, 0.20, blocklight);
#endif
color.rgb = applyLightingEmissive(color.rgb, sunAngle, skylight, blocklight, emissive, worldPos.y);
#endif
#ifdef HANDHELD_LIGHT_ENABLED
if (emissive < 0.5) color.rgb += getHandheldLightBoost(worldPos, entityRawColor, color.rgb);
#endif
float entityRawMax = max(entityRawColor.r, max(entityRawColor.g, entityRawColor.b));
color.rgb *= smoothstep(0.01, 0.06, entityRawMax);
color.rgb *= TERRAIN_BRIGHTNESS;

#ifdef END_SHADER
if (emissive < 0.5) {
float entBaseDarken = 0.55;
vec3 purpleTint = vec3(0.08, 0.06, 0.35);
float entTintMult = 0.15;
float entColorShift = 0.55;

float entPreserveBlend = 0.0;
vec3 entPreservedLight = vec3(0.0);

#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
float entEventDarkness = getEndEventTerrainDarkness(frameTimeCounter);
if (entEventDarkness > 0.001) {
float bFalloff = getBlocklightFalloff(blocklight, skylight);
vec3 endBlockColor = vec3(END_BLOCKLIGHT_R, END_BLOCKLIGHT_G, END_BLOCKLIGHT_B);
entPreservedLight = entityRawColor * endBlockColor * bFalloff * bFalloff * END_BLOCKLIGHT_BRIGHTNESS * TERRAIN_BRIGHTNESS;

#ifdef HANDHELD_LIGHT_ENABLED
entPreservedLight += getHandheldLightBoost(worldPos, entityRawColor, vec3(0.0)) * TERRAIN_BRIGHTNESS;
#endif

entPreserveBlend = entEventDarkness;
}
entBaseDarken = mix(entBaseDarken, 0.02, entEventDarkness);
entTintMult = mix(entTintMult, 0.0, entEventDarkness);
entColorShift = mix(entColorShift, 0.0, entEventDarkness);
#endif

color.rgb *= entBaseDarken;
color.rgb += purpleTint * entTintMult;
color.rgb = mix(color.rgb, color.rgb * vec3(0.55, 0.58, 1.35), entColorShift);

color.rgb += entPreservedLight * entPreserveBlend;
}
#endif

if (entityId == 109) {
color.rgb = mix(color.rgb, entityRawColor, 0.6);
}

if (emissive > 0.5) {
color.rgb = max(color.rgb, entityEmissiveVisible);
}

float denom = max(fogEnd - fogStart, 0.0001);
float fogFactor = clamp((fogEnd - viewDistance) / denom, 0.0, 1.0);
color.rgb = mix(getTimeBasedFogColor(), color.rgb, fogFactor);

gl_FragData[0] = vec4(color.rgb, 1.0);
float entityLayerMarker = 0.5;
#ifdef END_SHADER
if (vanillaEntityShadow) entityLayerMarker = 0.0;
#endif
gl_FragData[1] = vec4(1.0, emissive, entityMaskSkylight, entityLayerMarker);
gl_FragData[2] = vec4(entityEmissiveBloom, 1.0);
}
