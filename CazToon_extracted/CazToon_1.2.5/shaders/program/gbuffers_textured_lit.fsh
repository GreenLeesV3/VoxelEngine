/* RENDERTARGETS: 7,1 */

#include "/settings.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;
uniform float frameTimeCounter;
uniform float sunAngle;
uniform int isEyeInWater;
uniform float biome_swamp;
uniform int frameCounter;
uniform vec3 cameraPosition;
#ifdef LPV_ENABLED
uniform mat4 gbufferModelViewInverse;
#endif

#include "/include/lighting.glsl"

in vec2 texcoord;
in vec4 glcolor;
in vec3 worldPos;
in vec3 normal;
in float isHologram;
in float skylight;
in float blocklight;

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

float emissive = 0.0;
vec3 rawColor = color.rgb;

float brightness = dot(color.rgb, vec3(0.299, 0.587, 0.114));
float warmth = color.r - color.b;
if (brightness > 0.7 || (warmth > 0.2 && brightness > 0.4)) {
emissive = 1.0;
color.rgb *= EMISSIVE_BRIGHTNESS;
} else {

#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
lpvSurfaceColor = rawColor;
lpvTexLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
#endif
color.rgb = applyLighting(color.rgb, sunAngle, skylight, blocklight, worldPos.y);
color.rgb *= TERRAIN_BRIGHTNESS;
}

gl_FragData[0] = color;
gl_FragData[1] = vec4(1.0, emissive, skylight, 0.0);
}
