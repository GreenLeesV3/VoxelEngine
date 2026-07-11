/* RENDERTARGETS: 0,1,3 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/color_utils.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float fogStart;
uniform float fogEnd;
uniform float sunAngle;
uniform int biome;
uniform int biome_category;
uniform vec3 cameraPosition;
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_arid;
uniform float biome_savanna;

in vec2 texcoord;
in vec4 glcolor;
in float viewDistance;
in float emissive;
in vec3 worldPos;

#include "/include/fog_color.glsl"

#include "/include/noise.glsl"

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;

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
if (color.a < 0.01) discard;
}
}
#endif

color.rgb *= EMISSIVE_BRIGHTNESS;

float denom = max(fogEnd - fogStart, 0.0001);
float fogFactor = clamp((fogEnd - viewDistance) / denom, 0.0, 1.0);
color.rgb = mix(getTimeBasedFogColor(), color.rgb, fogFactor);

gl_FragData[0] = color;
gl_FragData[1] = vec4(1.0, emissive, 0.0, 0.5);
gl_FragData[2] = vec4(color.rgb, 1.0);
}
