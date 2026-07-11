/* RENDERTARGETS: 0,1,2,3 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/shadow.glsl"

uniform sampler2D gtexture;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor1;
uniform float alphaTestRef;
uniform vec3 fogColor;
uniform int biome_category;
uniform float fogStart;
uniform float fogEnd;
uniform float sunAngle;
uniform vec3 shadowLightPosition;
uniform int frameCounter;
uniform int entityId;
uniform int currentRenderedItemId;
uniform float frameTimeCounter;
uniform int isEyeInWater;
uniform vec3 cameraPosition;
#ifdef LPV_ENABLED
uniform mat4 gbufferModelViewInverse;
#endif
uniform vec4 entityColor;
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_arid;
uniform float biome_savanna;

#include "/include/lighting.glsl"
#ifdef EMISSIVE_MASKING
#include "/include/emissive_mask.glsl"
#endif
#ifdef PBR_ENABLED
uniform sampler2D normals;
uniform sampler2D specular;
#include "/include/pbr.glsl"
#endif
#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
#include "/include/end_event.glsl"
#endif

in vec2 texcoord;
in vec4 glcolor;
in float viewDistance;
in float skylight;
in float blocklight;
in float emissive;
flat in float emissiveType;
in vec4 shadowPos;
in vec3 normal;
in vec3 worldPos;
in float nametagHolo;
#ifdef PBR_ENABLED
in vec3 tangentVec;
in vec3 binormalVec;
in vec3 viewPosOut;
#endif

#include "/include/fog_color.glsl"

#include "/include/noise.glsl"

void main() {

#ifdef EMISSIVE
{
vec4 emColor = texture(gtexture, texcoord) * glcolor;
if (emColor.a < 0.01) discard;
emColor.rgb *= EMISSIVE_BRIGHTNESS;
gl_FragData[0] = vec4(emColor.rgb, 1.0);
gl_FragData[1] = vec4(0.0, 1.0, 0.0, 0.5);
gl_FragData[2] = vec4(emColor.rgb * 0.5, 1.0);
gl_FragData[3] = vec4(emColor.rgb * 0.5, 1.0);
return;
}
#endif

vec4 color = texture(gtexture, texcoord) * glcolor;
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

float emissiveStrength = emissive;

if (emissiveStrength > 0.5) {
vec3 rawTex = texture(gtexture, texcoord).rgb;
float rawLuma = dot(rawTex, vec3(0.299, 0.587, 0.114));
float rawMax = max(rawTex.r, max(rawTex.g, rawTex.b));
float rawMin = min(rawTex.r, min(rawTex.g, rawTex.b));
float rawSat = (rawMax - rawMin) / max(rawMax, 0.001);
if (rawLuma > 0.65 && rawSat < 0.3) emissiveStrength = 0.0;
}

#ifdef TEXTURE_PALETTE_ENABLED
{
float levels = float(TEXTURE_PALETTE_LEVELS);
color.rgb = floor(color.rgb * levels) / levels;
}
#endif

color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);

if (color.a < alphaTestRef) {
discard;
}

float entityShadowMax = max(color.r, max(color.g, color.b));
bool vanillaEntityShadow = (color.a < 0.9 && entityShadowMax < 0.08 && entityColor.a < 0.001 && nametagHolo < 0.5);
#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
if (vanillaEntityShadow && getEndEventTerrainDarkness(frameTimeCounter) > 0.98) {
discard;
}
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
color.rgb *= mix(0.60, 1.0, visible);
if (visible < 0.02) {
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

{
if (entityId == 100) {

} else if (entityId == 101) {
if (color.r > 0.8 && color.g < 0.2 && color.b < 0.2) emissiveStrength = 1.0 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 102) {

} else if (entityId == 103) {
if (color.r > 0.7 && color.g > 0.8 && color.b < 0.4) emissiveStrength = 0.8 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 104) {
if (color.r > 0.8 && color.g > 0.9 && color.b > 0.9) emissiveStrength = 0.9 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 105) {
emissiveStrength = 0.7 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 106) {
if (color.r > 0.5 && color.g > 0.8 && color.b > 0.9) emissiveStrength = 0.8 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 107) {
if (color.r > 0.6 && color.g < 0.3 && color.b < 0.3) emissiveStrength = 0.9 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 108) {
if (color.r > 0.9 && color.g > 0.5 && color.b < 0.6) emissiveStrength = 0.6 * PROCEDURAL_GLOW_STRENGTH;
} else if (entityId == 109) {
emissiveStrength = 1.0;
}
}

bool isHeldEmissiveItem = (currentRenderedItemId >= 10020 && currentRenderedItemId <= 10059) || currentRenderedItemId == 10087 || currentRenderedItemId == 10089;
bool heldPixelIsEmissive = false;
float heldEmissiveMask = 0.0;
if (isHeldEmissiveItem) {
#ifdef EMISSIVE_MASKING
int heldEt = (currentRenderedItemId == 10087) ? 46 : ((currentRenderedItemId == 10089) ? 47 : currentRenderedItemId - 10020);
heldEmissiveMask = getEmissiveMask(heldEt, entityRawColor);
heldPixelIsEmissive = (heldEmissiveMask >= 0.05);
#else
heldPixelIsEmissive = true;
#endif
}

vec3 entityEmissiveVisible = vec3(0.0);
vec3 entityEmissiveBloom = vec3(0.0);

if (heldPixelIsEmissive) {

entityEmissiveVisible = entityRawColor * EMISSIVE_BRIGHTNESS;

#ifdef EMISSIVE_MASKING
entityEmissiveBloom = entityRawColor * EMISSIVE_BRIGHTNESS * clamp(heldEmissiveMask, 0.0, 1.0);
#else
entityEmissiveBloom = vec3(1.0, 0.85, 0.4) * EMISSIVE_BRIGHTNESS;
if (currentRenderedItemId == 10021 || currentRenderedItemId == 10043) {
entityEmissiveBloom = vec3(0.3, 0.7, 1.0) * EMISSIVE_BRIGHTNESS;
}
int cid = currentRenderedItemId;
if (cid == 10023 || cid == 10024 || cid == 10025 ||
cid == 10027 || cid == 10028 || cid == 10029 || cid == 10031 ||
cid == 10032 || cid == 10033 || cid == 10034 ||
cid == 10040 || cid == 10044 ||
cid == 10046 || cid == 10047 || cid == 10048 || cid == 10049 ||
cid == 10051 || cid == 10052 || cid == 10053 ||
cid == 10054 || cid == 10055 || cid == 10058 || cid == 10059) {
entityEmissiveBloom = entityRawColor * EMISSIVE_BRIGHTNESS;
}
#endif
emissiveStrength = 1.0;
} else if (isHeldEmissiveItem && !heldPixelIsEmissive) {

emissiveStrength = 0.0;
} else if (emissiveStrength > 0.5 && !isHeldEmissiveItem) {

float entityEmissiveScale = EMISSIVE_BRIGHTNESS * max(emissiveStrength, 1.0);
float entityBloomSeedBoost = 1.25 + 0.75 * max(emissiveStrength, 1.0);
entityEmissiveVisible = entityRawColor;
entityEmissiveBloom = entityRawColor * entityEmissiveScale * ENTITY_EMISSIVE_BLOOM * entityBloomSeedBoost;
}

if (entityId == 109 && emissiveStrength > 0.5) {
entityEmissiveVisible = entityRawColor;
entityEmissiveBloom = entityRawColor * 0.15;
}

if (entityId == 105 && emissiveStrength > 0.5) {
entityEmissiveVisible = entityRawColor;
entityEmissiveBloom = entityRawColor * 0.01;
}

#ifdef SHADOWS_ENABLED
if (shadowPos.w > 0.5 && emissiveStrength < 0.5 && !isForcedNetherBiome(biome)) {

float dotNL = dot(normal, normalize(shadowLightPosition));

float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
float r = quartic_length(shadowPos.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;

vec3 biasedShadowPos = shadowPos.xyz;
biasedShadowPos.z -= 0.0005;

#ifdef MAGICAL_TOUCH
vec3 shadow = getShadowColorSharpNoEntity(shadowtex1, shadowcolor0, shadowcolor1, biasedShadowPos, 0.0);
#else
vec3 shadow = getShadowColorPCFNoEntity(shadowtex1, shadowcolor0, shadowcolor1, biasedShadowPos, distortFactor, dither, 0.0);
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
color.rgb = applyLightingWithShadow(lightingBaseColor, sunAngle, entitySkylight, blocklight, emissiveStrength, shadow, worldPos.y);
float shadowTransitionDip = getSunMoonShadowTransitionDip(sunAngle);
if (shadowTransitionDip > 0.001) {
vec3 transitionNoShadow = applyLightingWithShadow(lightingBaseColor, sunAngle, entitySkylight, blocklight, emissiveStrength, vec3(1.0), worldPos.y);
color.rgb = mix(color.rgb, transitionNoShadow, shadowTransitionDip);
}
color.rgb *= getSunMoonShadowTransitionDarken(shadowTransitionDip, getTimeOfDayLighting(sunAngle).x, entitySkylight);
} else {
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
lpvReceiverStrength = smoothstep(0.02, 0.20, blocklight);
#endif
color.rgb = applyLightingEmissive(color.rgb, sunAngle, skylight, blocklight, emissiveStrength, worldPos.y);
}
#else
{
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
lpvReceiverStrength = smoothstep(0.02, 0.20, blocklight);
#endif
color.rgb = applyLightingEmissive(color.rgb, sunAngle, skylight, blocklight, emissiveStrength, worldPos.y);
}
#endif
#ifdef HANDHELD_LIGHT_ENABLED
if (emissiveStrength < 0.5) color.rgb += getHandheldLightBoost(worldPos, entityRawColor, color.rgb);
#endif
float entityRawMax = max(entityRawColor.r, max(entityRawColor.g, entityRawColor.b));
color.rgb *= smoothstep(0.01, 0.06, entityRawMax);

color.rgb *= TERRAIN_BRIGHTNESS;

#ifdef PBR_ENABLED
if (emissiveStrength < 0.5) {
vec4 normalData = texture(normals, texcoord);
vec4 specData   = texture(specular, texcoord);
PBRMaterial pm = pbr_decode(normalData, specData, entityRawColor, PBR_NORMAL_STRENGTH);

if (pm.hasNormal && PBR_AO_STRENGTH > 0.001) {
float indirectAmt = 1.0 - skylight;
color.rgb *= mix(1.0, mix(1.0, pm.ao, PBR_AO_STRENGTH * 0.5), indirectAmt);
}

if (pm.hasSpec && pm.roughness < 0.999) {
vec3 N = pbr_tangentToView(pm.nTangent, tangentVec, binormalVec, normal);
vec3 L = normalize(shadowLightPosition);
vec3 V = normalize(-viewPosOut);
vec3 H = normalize(V + L);
float NdotL = max(dot(N, L), 0.0);
float NdotH = max(dot(N, H), 0.0);
float NdotV = max(dot(N, V), 1e-3);
float grazeSoft = smoothstep(0.02, 0.15, NdotV);
float r = clamp(pm.roughness, 0.5, 1.0);
vec3  F = pbr_fresnelSchlickColor(NdotV, pm.F0);
vec3 ambientSpec = pm.F0 * (1.0 - r) * 0.15 * skylight * grazeSoft;
if (NdotL > 0.0) {
float shininess = mix(32.0, 4.0, r);
float specPow = pow(NdotH, shininess);
float norm = (shininess + 2.0) / (2.0 * 3.14159265);
vec3 spec = specPow * norm * F * NdotL;
float sunFrac = fract(sunAngle);
float dayFactor = smoothstep(0.00, 0.15, sunFrac) * smoothstep(0.55, 0.40, sunFrac);
color.rgb += spec * grazeSoft * PBR_SPECULAR_STRENGTH * skylight * dayFactor;
}
color.rgb += ambientSpec;
}

if (pm.emission > 0.01) {
emissiveStrength = max(emissiveStrength, pm.emission);
color.rgb = mix(color.rgb, entityRawColor * 1.5, pm.emission * 0.5);
}
}
#endif

#ifdef END_SHADER
if (emissiveStrength < 0.5) {
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

if (heldPixelIsEmissive) {

color.rgb = entityRawColor * EMISSIVE_BRIGHTNESS;
} else if (emissiveStrength > 0.5) {
color.rgb = max(color.rgb, entityEmissiveVisible);
}

if (isEyeInWater != 1) {
float denom = max(fogEnd - fogStart, 0.0001);
float fogFactor = clamp((fogEnd - viewDistance) / denom, 0.0, 1.0);
color.rgb = mix(getTimeBasedFogColor(), color.rgb, fogFactor);
}

gl_FragData[0] = vec4(color.rgb, 1.0);
float entityLayerMarker = 0.5;
#ifdef END_SHADER
if (vanillaEntityShadow) entityLayerMarker = 0.0;
#endif
gl_FragData[1] = vec4(1.0, emissiveStrength, entityMaskSkylight, entityLayerMarker);
gl_FragData[2] = vec4(entityEmissiveBloom, 1.0);
gl_FragData[3] = vec4(entityEmissiveBloom, 1.0);
}
