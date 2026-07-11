/* RENDERTARGETS: 0,1,2 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"

uniform sampler2D gtexture;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int biome;
uniform int biome_category;
uniform int isEyeInWater;
uniform float biome_swamp;

in vec2 uv;
in vec3 viewPos;
in vec4 tint;

bool isSkylessWorldHeuristic() {
float sunLen = length(sunPosition);
float shadowLen = length(shadowLightPosition);
vec3 skyMax = max(skyColor, vec3(0.0));
vec3 fogMax = max(fogColor, vec3(0.0));
float skyPeak = max(max(skyMax.r, skyMax.g), skyMax.b);
float fogPeak = max(max(fogMax.r, fogMax.g), fogMax.b);
bool noDirectionalLight = (sunLen < 0.001 && shadowLen < 0.001);
bool darkFlatAtmosphere = (skyPeak < 0.06 && fogPeak < 0.08);
return darkFlatAtmosphere && noDirectionalLight;
}

void main() {

if (isSkylessWorldHeuristic()) {
discard;
}

#ifdef END_SKY_ENABLED
{
bool endLike = false;
#ifdef CAT_THE_END
endLike = (biome_category == CAT_THE_END);
#else
endLike = isForcedEndBiome(biome);
#endif
if (endLike) discard;
}
#endif

vec4 color = texture(gtexture, uv) * tint;

if (color.a < 0.1) discard;

float sunDot = dot(normalize(viewPos), normalize(shadowLightPosition));
float moonDot = dot(normalize(viewPos), normalize(-shadowLightPosition));
bool isSunMoon = sunDot > 0.8 || moonDot > 0.8;

#ifdef STARS_ENABLED

if (!isSunMoon) {
float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
bool likelyStar = (lum < 0.20) && (color.a < 0.99);
if (likelyStar) discard;
}
#endif

float wSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
if (!isSunMoon && wSwamp > 0.01) {
float lum2 = dot(color.rgb, vec3(0.299, 0.587, 0.114));
if (lum2 < 0.30 && color.a < 0.99) discard;
}

gl_FragData[0] = color;

float emissive = isSunMoon ? 1.0 : 0.0;

float sunBloomLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
vec3 sunBloomTint = sunBloomLum > 0.01 ? color.rgb / sunBloomLum : vec3(1.0);
vec3 sunBloom = sunBloomTint * SUN_MOON_BLOOM;

if (isEyeInWater == 1) { sunBloom = vec3(0.0); }
gl_FragData[1] = vec4(0.0, emissive, 0.0, 0.0);
gl_FragData[2] = vec4(sunBloom, 1.0);
}
