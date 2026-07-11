/* RENDERTARGETS: 7,1,3 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/hovering.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;
uniform float sunAngle;
uniform vec3 fogColor;
uniform int biome_category;
uniform float fogStart;
uniform float fogEnd;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform int frameCounter;
#ifdef LPV_ENABLED
uniform mat4 gbufferModelViewInverse;
#endif
uniform int isEyeInWater;
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
in vec3 viewPos;
in float skylight;
in float blocklight;
in float viewDistance;
flat in float emissive;
flat in float emissiveType;

#include "/include/fog_color.glsl"

float random(float x) {
return fract(sin(x * 12.9898) * 43758.5453);
}

#include "/include/noise.glsl"

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;

bool isSignText = (abs(emissiveType + 20.0) < 0.5);
if (isSignText) {
if (color.a < 0.01) discard;
gl_FragData[0] = color;
gl_FragData[1] = vec4(0.95, 0.0, skylight, 0.0);
gl_FragData[2] = vec4(0.0);
return;
}

int et = int(emissiveType + 0.5);
if (et == 43 && emissive > 0.5) {
float portalNoise = fract(sin(dot(texcoord * 8.0 + vec2(frameTimeCounter * 0.3), vec2(12.9898, 78.233))) * 43758.5453);
vec3 portalBase = vec3(0.1, 0.5, 0.4);
vec3 portalBright = vec3(0.3, 0.9, 0.7);
color = vec4(mix(portalBase, portalBright, portalNoise * 0.5 + 0.3), 1.0);
}

if (color.a <= 0.001 || color.a < alphaTestRef) {
discard;
}

if (!isForcedNetherBiome(biome) && !isForcedEndBiome(biome)) {
#ifdef CHUNK_FADE_OUT_ENABLED
#ifndef DISTANT_HORIZONS
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
#endif
#endif
}

#ifndef MAGICAL_TOUCH
vec3 worldNormalFace = normalize(mat3(gbufferModelViewInverse) * normal);
color.rgb *= getVanillaFaceShade(worldNormalFace);
#endif

vec3 rawColor = color.rgb;
vec3 bloomColor = vec3(0.0);
float finalEmissive = emissive;
#ifdef LPV_ENABLED

lpvSurfaceColor = rawColor;
lpvTexLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
lpvNeutralPreserveStrength = 1.0;
#endif

if (finalEmissive > 0.5) {
int t = int(emissiveType + 0.5);
if (t == 68) {

float portalLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
float portalBrightMask = smoothstep(0.10, 0.70, portalLuma);
float portalGain = mix(0.55, 1.95, portalBrightMask * portalBrightMask);
color.rgb = rawColor * EMISSIVE_BRIGHTNESS * 2.5 * portalGain;
bloomColor = vec3(0.6, 0.1, 1.0) * 3.0;
} else if (t == 43) {

float portalNoise = fract(sin(dot(texcoord * 8.0 + vec2(frameTimeCounter * 0.3), vec2(12.9898, 78.233))) * 43758.5453);
vec3 portalBase = vec3(0.1, 0.5, 0.4);
vec3 portalBright = vec3(0.3, 0.9, 0.7);
color.rgb = mix(portalBase, portalBright, portalNoise * 0.5 + 0.3) * EMISSIVE_BRIGHTNESS;
bloomColor = vec3(0.2, 0.8, 0.6) * 3.0;
} else {
color.rgb = rawColor * EMISSIVE_BRIGHTNESS * 2.5;
bloomColor = vec3(1.0, 0.7, 0.4);
}
bloomColor *= EMISSIVE_BRIGHTNESS;
} else {

#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLighting(color.rgb, sunAngle, skylight, blocklight, worldPos.y);
#ifdef HANDHELD_LIGHT_ENABLED
color.rgb += getHandheldLightBoost(worldPos, rawColor, color.rgb);
#endif
}
color.rgb *= TERRAIN_BRIGHTNESS;

if (finalEmissive < 0.5) {
float denom = max(fogEnd - fogStart, 0.0001);
float fogFactor = clamp((fogEnd - viewDistance) / denom, 0.0, 1.0);
color.rgb = mix(getTimeBasedFogColor(), color.rgb, fogFactor);
}

color.a = 1.0;
gl_FragData[0] = color;

gl_FragData[1] = vec4(0.95, finalEmissive, skylight, 0.0);
gl_FragData[2] = vec4(bloomColor, 1.0);
}
