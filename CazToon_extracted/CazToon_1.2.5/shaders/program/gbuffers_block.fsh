/* RENDERTARGETS: 0,1,3,5 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/shadow.glsl"
#include "/include/hovering.glsl"

uniform sampler2D gtexture;
uniform sampler2D shadowtex0;
uniform float alphaTestRef;
uniform float sunAngle;
uniform vec3 fogColor;
uniform vec3 shadowLightPosition;
uniform int biome_category;
uniform float fogStart;
uniform float fogEnd;
uniform int isEyeInWater;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform int frameCounter;
uniform mat4 gbufferModelViewInverse;
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_arid;
uniform float biome_savanna;

#include "/include/lighting.glsl"

in vec2 texcoord;
in vec4 glcolor;
in vec3 worldPos;
in vec3 normal;
in float isHologram;
in float skylight;
in float blocklight;
in float viewDistance;
in vec4 shadowPos;
flat in int blockIdOut;

#include "/include/fog_color.glsl"

float random(float x) {
return fract(sin(x * 12.9898) * 43758.5453);
}

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

#ifndef MAGICAL_TOUCH
vec3 worldNormalFace = normalize(mat3(gbufferModelViewInverse) * normal);
color.rgb *= getVanillaFaceShade(worldNormalFace);
#endif

vec3 rawColor = color.rgb;
float blockEntityMaskSkylight = skylight;
float emissive = 0.0;
#ifdef LPV_ENABLED

lpvSurfaceColor = rawColor;
lpvTexLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
lpvNeutralPreserveStrength = 1.0;
#endif

#ifdef SHADOWS_ENABLED
if (shadowPos.w > 0.5 && emissive < 0.5) {
float dotNL = dot(normal, normalize(shadowLightPosition));
float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
float r = quartic_length(shadowPos.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;

float selfShadowBias = 0.003;
float slopeBias = (SHADOW_NORMAL_BIAS * 0.0001) * (1.1 - dotNL);
vec3 biasedShadowPos = shadowPos.xyz;
biasedShadowPos.z -= selfShadowBias + slopeBias;

#ifdef MAGICAL_TOUCH
vec3 shadow = getShadowColorSharp(shadowtex0, shadowcolor0, biasedShadowPos, 0.0);
#else
vec3 shadow = getShadowColorPCF(shadowtex0, shadowcolor0, biasedShadowPos, distortFactor, dither, 0.0);
#endif

float rawShadowVal = dot(shadow, vec3(0.299, 0.587, 0.114));

float fixedSkylight = max(skylight, min(rawShadowVal * 0.50, 1.0 / 15.0));
blockEntityMaskSkylight = fixedSkylight;

shadow = mix(vec3(1.0), shadow, SHADOW_OPACITY);

#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLightingWithShadow(color.rgb, sunAngle, fixedSkylight, blocklight, emissive, shadow, worldPos.y);
} else {
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLightingEmissive(color.rgb, sunAngle, skylight, blocklight, emissive, worldPos.y);
}
#else
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLightingEmissive(color.rgb, sunAngle, skylight, blocklight, emissive, worldPos.y);
#endif
#ifdef HANDHELD_LIGHT_ENABLED
if (emissive < 0.5) color.rgb += getHandheldLightBoost(worldPos, rawColor, color.rgb);
#endif
color.rgb *= TERRAIN_BRIGHTNESS;

float denom = max(fogEnd - fogStart, 0.0001);
float fogFactor = clamp((fogEnd - viewDistance) / denom, 0.0, 1.0);
color.rgb = mix(getTimeBasedFogColor(), color.rgb, fogFactor);

gl_FragData[0] = color;

gl_FragData[1] = vec4(0.95, emissive, blockEntityMaskSkylight, 0.0);

vec3 lightColor = vec3(0.0);
if (emissive > 0.5) {
lightColor = color.rgb * EMISSIVE_BRIGHTNESS;
}
gl_FragData[2] = vec4(lightColor, 1.0);

gl_FragData[3] = vec4(0.0);
}
