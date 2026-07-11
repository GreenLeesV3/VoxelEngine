/* RENDERTARGETS: 0,1,3,4,5 */

#include "/settings.glsl"
#include "/include/shadow.glsl"
uniform float biome_swamp;

uniform sampler2D gtexture;
uniform sampler2D shadowtex0;
uniform float alphaTestRef;
uniform float sunAngle;
uniform int currentRenderedItemId;
uniform int isEyeInWater;
uniform vec3 shadowLightPosition;
uniform int frameCounter;
uniform vec3 cameraPosition;
#ifdef LPV_ENABLED
uniform mat4 gbufferModelViewInverse;
#endif
#include "/include/lighting.glsl"
#ifdef EMISSIVE_MASKING
#include "/include/emissive_mask.glsl"
#endif
#ifdef PBR_ENABLED
uniform sampler2D normals;
uniform sampler2D specular;
#include "/include/pbr.glsl"
#endif

#ifdef END_SHADER
uniform float frameTimeCounter;
#ifdef END_EVENT_ENABLED
#include "/include/end_event.glsl"
#endif
#endif

in vec2 texcoord;
in vec4 glcolor;
in float skylight;
in float blocklight;
in float viewDistance;
in vec4 shadowPos;
in vec3 normal;
in vec3 worldPos;
#ifdef PBR_ENABLED
in vec3 tangentVec;
in vec3 binormalVec;
in vec3 viewPosOut;
#endif

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;

#ifdef TEXTURE_PALETTE_ENABLED
{
float levels = float(TEXTURE_PALETTE_LEVELS);
color.rgb = floor(color.rgb * levels) / levels;
}
#endif

if (color.a < alphaTestRef) {
discard;
}

vec3 rawColor = color.rgb;
#ifdef LPV_ENABLED
lpvSurfaceColor = rawColor;
lpvTexLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
#endif

bool isEmissiveItem = (currentRenderedItemId >= 10020 && currentRenderedItemId <= 10059) || currentRenderedItemId == 10087 || currentRenderedItemId == 10089;

#ifdef EMISSIVE_MASKING
float handMask = 0.0;
bool pixelIsEmissive = false;
if (isEmissiveItem) {
int handEt = (currentRenderedItemId == 10087) ? 46 : ((currentRenderedItemId == 10089) ? 47 : currentRenderedItemId - 10020);
handMask = getEmissiveMask(handEt, rawColor);
pixelIsEmissive = (handMask >= 0.05);
}
#else
bool pixelIsEmissive = isEmissiveItem;
#endif

#ifdef END_SHADER
if (!pixelIsEmissive) {

#ifdef SHADOWS_ENABLED
if (shadowPos.w > 0.5) {
float dotNL = dot(normal, normalize(shadowLightPosition));
float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
float r = quartic_length(shadowPos.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;

float selfShadowBias = 0.003;
float slopeBias = (SHADOW_NORMAL_BIAS * 0.0001) * (1.1 - dotNL);
float totalBias = selfShadowBias + slopeBias;

vec3 biasedShadowPos = shadowPos.xyz;
biasedShadowPos.z -= totalBias;

vec3 shadow = getShadowColorPCF(shadowtex0, shadowcolor0, biasedShadowPos, distortFactor, dither, 0.0);
float shadowSkylight = max(skylight, 0.15);
shadow = mix(vec3(1.0), shadow, shadowSkylight);
shadow = mix(vec3(1.0), shadow, SHADOW_OPACITY);
float handShadowVal = dot(shadow, vec3(0.299, 0.587, 0.114));
float handSkylight = skylight;
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
vec3 lightingBaseColor = color.rgb;
color.rgb = applyLightingWithShadow(lightingBaseColor, sunAngle, handSkylight, blocklight, 0.0, shadow, worldPos.y);
float shadowTransitionDip = getSunMoonShadowTransitionDip(sunAngle);
if (shadowTransitionDip > 0.001) {
vec3 transitionNoShadow = applyLightingWithShadow(lightingBaseColor, sunAngle, handSkylight, blocklight, 0.0, vec3(1.0), worldPos.y);
color.rgb = mix(color.rgb, transitionNoShadow, shadowTransitionDip);
}
color.rgb *= getSunMoonShadowTransitionDarken(shadowTransitionDip, getTimeOfDayLighting(sunAngle).x, handSkylight);
} else {
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLighting(color.rgb, sunAngle, skylight, blocklight, worldPos.y);
}
#else
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLighting(color.rgb, sunAngle, skylight, blocklight, worldPos.y);
#endif

float handDarken = mix(0.15, 1.0, smoothstep(0.0, 0.5, skylight));
color.rgb *= handDarken;

float baseDarken = 0.55;
float tintMult = 0.15;

float preserveBlend = 0.0;
vec3 preservedLight = vec3(0.0);

#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
float eventDarkness = getEndEventTerrainDarkness(frameTimeCounter);
if (eventDarkness > 0.001) {
float bFalloff = getBlocklightFalloff(blocklight, skylight);
vec3 endBlockColor = vec3(END_BLOCKLIGHT_R, END_BLOCKLIGHT_G, END_BLOCKLIGHT_B);
preservedLight = rawColor * endBlockColor * bFalloff * bFalloff * END_BLOCKLIGHT_BRIGHTNESS;
preserveBlend = eventDarkness;
}
baseDarken = mix(baseDarken, 0.02, eventDarkness);
tintMult = mix(tintMult, 0.0, eventDarkness);
#endif

color.rgb *= baseDarken;
vec3 purpleTint = vec3(0.08, 0.06, 0.35);
color.rgb += purpleTint * tintMult;

color.rgb += preservedLight * preserveBlend;

#ifdef HANDHELD_LIGHT_ENABLED
color.rgb += getHandheldLightBoost(worldPos, rawColor, color.rgb);
#endif
} else {

color.rgb = rawColor * EMISSIVE_BRIGHTNESS * END_EMISSIVE_BOOST;
}
#else

if (!pixelIsEmissive) {

#ifdef SHADOWS_ENABLED
if (shadowPos.w > 0.5) {
float dotNL = dot(normal, normalize(shadowLightPosition));
float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
float r = quartic_length(shadowPos.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;

float selfShadowBias = 0.003;
float slopeBias = (SHADOW_NORMAL_BIAS * 0.0001) * (1.1 - dotNL);
float totalBias = selfShadowBias + slopeBias;

vec3 biasedShadowPos = shadowPos.xyz;
biasedShadowPos.z -= totalBias;

vec3 shadow = getShadowColorPCF(shadowtex0, shadowcolor0, biasedShadowPos, distortFactor, dither, 0.0);
float shadowSkylight = max(skylight, 0.15);
shadow = mix(vec3(1.0), shadow, shadowSkylight);
shadow = mix(vec3(1.0), shadow, SHADOW_OPACITY);

float handShadowVal = dot(shadow, vec3(0.299, 0.587, 0.114));
float handSkylight = skylight;
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLightingWithShadow(color.rgb, sunAngle, handSkylight, blocklight, 0.0, shadow, worldPos.y);
} else {
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLighting(color.rgb, sunAngle, skylight, blocklight, worldPos.y);
}
#else
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLighting(color.rgb, sunAngle, skylight, blocklight, worldPos.y);
#endif

#ifdef HANDHELD_LIGHT_ENABLED
color.rgb += getHandheldLightBoost(worldPos, rawColor, color.rgb);
#endif
} else {

color.rgb = rawColor * EMISSIVE_BRIGHTNESS;
}
#endif

float emissiveStrength = pixelIsEmissive ? 1.0 : 0.0;

#ifdef PBR_ENABLED
if (!pixelIsEmissive) {
vec4 normalData = texture(normals, texcoord);
vec4 specData   = texture(specular, texcoord);
PBRMaterial pm = pbr_decode(normalData, specData, rawColor, PBR_NORMAL_STRENGTH);
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
vec3 ambientSpec = pm.F0 * (1.0 - r) * 0.15 * max(skylight, 0.15) * grazeSoft;
if (NdotL > 0.0) {
float shininess = mix(32.0, 4.0, r);
float specPow = pow(NdotH, shininess);
float norm = (shininess + 2.0) / (2.0 * 3.14159265);
vec3 spec = specPow * norm * F * NdotL;
float sunFrac = fract(sunAngle);
float dayFactor = smoothstep(0.00, 0.15, sunFrac) * smoothstep(0.55, 0.40, sunFrac);
color.rgb += spec * grazeSoft * PBR_SPECULAR_STRENGTH * max(skylight, 0.15) * dayFactor;
}
color.rgb += ambientSpec;
}
if (pm.emission > 0.01) {
emissiveStrength = max(emissiveStrength, pm.emission);
color.rgb = mix(color.rgb, rawColor * 1.5, pm.emission * 0.5);
}
}
#endif

gl_FragData[0] = color;

gl_FragData[1] = vec4(0.0, emissiveStrength, 0.0, 0.75);

vec3 bloomColor = vec3(0.0);

const float HAND_BLOOM_SCALE = 0.6;
if (pixelIsEmissive) {
int cid = currentRenderedItemId;
vec3 tint;
if (cid == 10021 || cid == 10043) {
tint = vec3(0.3, 0.7, 1.0);
} else if (cid == 10087 || cid == 10089) {
tint = vec3(0.3, 1.0, 0.4);
} else if (cid == 10038 || cid == 10058) {
tint = vec3(1.0, 0.2, 0.2);
} else if (cid == 10023 || cid == 10024 || cid == 10025 ||
cid == 10027 || cid == 10028 || cid == 10029 || cid == 10031 ||
cid == 10032 || cid == 10033 || cid == 10034 ||
cid == 10040 || cid == 10044 ||
cid == 10046 || cid == 10047 || cid == 10048 || cid == 10049 ||
cid == 10051 || cid == 10052 || cid == 10053 ||
cid == 10054 || cid == 10055 || cid == 10059) {

tint = rawColor;
} else {
tint = vec3(1.0, 0.85, 0.4);
}
bloomColor = tint * EMISSIVE_BRIGHTNESS * HAND_BLOOM_SCALE * clamp(handMask, 0.0, 1.0);
}
gl_FragData[2] = vec4(bloomColor, 1.0);
gl_FragData[3] = vec4(0.0);
gl_FragData[4] = vec4(0.0);
}
