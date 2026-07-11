/* RENDERTARGETS: 7,1,3,4,5 */

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
float handSkylight = max(skylight, handShadowVal * 0.95);
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

float emissiveStrength = pixelIsEmissive ? 1.0 : 0.0;
gl_FragData[0] = color;
gl_FragData[1] = vec4(0.0, emissiveStrength, 0.0, 0.5);
gl_FragData[2] = vec4(0.0);

vec3 glcNorm = glcolor.rgb;
float glcMax = max(max(glcNorm.r, glcNorm.g), glcNorm.b);
if (glcMax > 0.001) glcNorm /= glcMax;
vec4 heldGlassTint = vec4(texture(gtexture, texcoord).rgb * glcNorm, 0.6);

gl_FragData[3] = pixelIsEmissive ? vec4(0.0) : heldGlassTint;
gl_FragData[4] = vec4(0.0);
}
