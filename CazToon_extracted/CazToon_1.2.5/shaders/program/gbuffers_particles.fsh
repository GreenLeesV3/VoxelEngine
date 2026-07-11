/* RENDERTARGETS: 7,1 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;
uniform vec3 cameraPosition;
uniform float sunAngle;
uniform int isEyeInWater;
uniform float biome_swamp;
uniform int frameCounter;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 worldPos;

#include "/include/lighting.glsl"
#include "/include/sky_timeline.glsl"

#include "/include/noise.glsl"

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;
vec3 rawColor = color.rgb;

#ifdef TEXTURE_PALETTE_ENABLED
{
float levels = float(TEXTURE_PALETTE_LEVELS);
color.rgb = floor(color.rgb * levels) / levels;
}
#endif

if (color.a < alphaTestRef) {
discard;
}

#ifdef CHUNK_FADE_OUT_ENABLED
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
if (color.a < alphaTestRef) discard;
}
}
#endif

{
float skylight = clamp(lmcoord.y, 0.0, 1.0);
float angle = fract(sunAngle);
float sunsetTintBoost = smoothstep(0.38, 0.45, angle) * (1.0 - smoothstep(0.48, 0.55, angle))
+ smoothstep(0.95, 1.0, angle) + (1.0 - smoothstep(0.0, 0.05, angle));
float dayTintReduce = smoothstep(0.07, 0.15, angle) * (1.0 - smoothstep(0.40, 0.46, angle));
float baseTint = SKYLIGHT_COLOR_TINT * (1.0 - dayTintReduce * 0.6);
float tintStr = clamp(baseTint + sunsetTintBoost * SUNSET_TERRAIN_TINT, 0.0, 1.0);
TimeWeights tw = getTimeWeights(sunAngle);
vec3 tintColor = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B) * tw.day
+ vec3(SUNSET_ZENITH_R, SUNSET_ZENITH_G, SUNSET_ZENITH_B) * tw.sunset
+ vec3(BLUEHOUR_ZENITH_R, BLUEHOUR_ZENITH_G, BLUEHOUR_ZENITH_B) * tw.blueHour
+ vec3(NIGHT_ZENITH_R, NIGHT_ZENITH_G, NIGHT_ZENITH_B) * tw.night
+ vec3(SUNRISE_ZENITH_R, SUNRISE_ZENITH_G, SUNRISE_ZENITH_B) * tw.sunrise
+ vec3(DAWN_ZENITH_R, DAWN_ZENITH_G, DAWN_ZENITH_B) * tw.dawn;
float tintLum = dot(tintColor, vec3(0.299, 0.587, 0.114));
tintColor = clamp(tintColor / max(tintLum, 0.35), vec3(0.0), vec3(2.0));
vec3 skyTint = mix(vec3(1.0), tintColor, tintStr * skylight);
color.rgb *= skyTint;
}

float brightness = dot(color.rgb, vec3(0.299, 0.587, 0.114));
float warmth = color.r - color.b;

float maxC = max(max(color.r, color.g), color.b);
float minC = min(min(color.r, color.g), color.b);
float saturation = (maxC > 0.001) ? (maxC - minC) / maxC : 0.0;
bool isSmoke = saturation < 0.15 && brightness > 0.3 && brightness < 0.95;

bool isBlockBreaking = brightness < 0.85 && warmth < 0.3 && saturation < 0.7;

float emissive = 0.0;

bool isDesaturated = saturation < 0.2 && brightness > 0.5;
if (!isSmoke && !isBlockBreaking && !isDesaturated && (brightness > PARTICLE_BLOOM_THRESHOLD || (warmth > PARTICLE_BLOOM_WARMTH && brightness > PARTICLE_BLOOM_THRESHOLD * 0.5))) {
emissive = PARTICLE_BLOOM_INTENSITY;
color.rgb *= EMISSIVE_BRIGHTNESS;
} else {

float skylight = clamp(lmcoord.y, 0.0, 1.0);
float blocklight = clamp(lmcoord.x, 0.0, 1.0);
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvSurfaceColor = rawColor;
lpvTexLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
#endif
color.rgb = applyLighting(color.rgb, sunAngle, skylight, blocklight, worldPos.y);
color.rgb *= TERRAIN_BRIGHTNESS;
}

#ifdef BIOME_SOUL_SAND_VALLEY
if (biome == BIOME_SOUL_SAND_VALLEY && warmth > 0.1) {
float pLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
vec3 blueParticle = vec3(1.0/255.0, 158.0/255.0, 210.0/255.0) * pLum * 2.0;
float warmFactor = smoothstep(0.1, 0.4, warmth);
color.rgb = mix(color.rgb, blueParticle, warmFactor);
}
#endif

gl_FragData[0] = color;
gl_FragData[1] = vec4(0.0, emissive, 0.0, 0.0);
}
