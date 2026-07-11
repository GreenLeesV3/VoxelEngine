#include "/settings.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

in vec2 texcoord;
flat in int block_id_out;
flat in float grass_blade_mask_out;
flat in float grass_cube_mask_out;
flat in float leaf_flat_mask_out;
flat in int block_id_raw_out;
in float shaft_height_metric_out;

/* DRAWBUFFERS:01 */
layout(location = 0) out vec4 shadowcolor;
layout(location = 1) out vec4 shadowcolor1out;

vec3 shapeShadowGlassTint(vec3 tint) {
float maxTint = max(max(tint.r, tint.g), tint.b);
if (maxTint <= 0.0001) return vec3(1.0);
tint /= maxTint;
tint = pow(clamp(tint, vec3(0.0), vec3(1.0)), vec3(1.35));
return clamp(tint, vec3(0.0), vec3(1.0));
}

vec3 getShadowGlassTintFromBlockId(int blockId) {
if (blockId == 64) return shapeShadowGlassTint(vec3(1.0, 0.1, 0.1));
if (blockId == 65) return shapeShadowGlassTint(vec3(1.0, 0.3, 0.1));
if (blockId == 66) return shapeShadowGlassTint(vec3(1.0, 1.0, 0.1));
if (blockId == 67) return shapeShadowGlassTint(vec3(1.0, 0.75, 0.5));
if (blockId == 68) return shapeShadowGlassTint(vec3(0.3, 1.0, 0.3));
if (blockId == 69) return shapeShadowGlassTint(vec3(0.1, 1.0, 0.1));
if (blockId == 70) return shapeShadowGlassTint(vec3(0.1, 0.15, 1.0));
if (blockId == 71) return shapeShadowGlassTint(vec3(0.5, 0.65, 1.0));
if (blockId == 72) return shapeShadowGlassTint(vec3(0.3, 0.8, 1.0));
if (blockId == 73) return shapeShadowGlassTint(vec3(0.7, 0.3, 1.0));
if (blockId == 74) return shapeShadowGlassTint(vec3(1.0, 0.1, 1.0));
if (blockId == 75) return shapeShadowGlassTint(vec3(1.0, 0.4, 1.0));
if (blockId == 76) return vec3(0.05);
return vec3(1.0);
}

void main() {

float isEntity = (block_id_raw_out == 0) ? 1.0 : 0.0;
float shaftHeightAlpha = 0.25 + max(shaft_height_metric_out, 0.0) * 0.05;
shaftHeightAlpha = clamp(shaftHeightAlpha, 0.25, 1.0);
if (isEntity > 0.5) shaftHeightAlpha = 0.25;

vec4 color = texture(gtexture, texcoord);
bool isNetherPortal = (block_id_out == 88);

#ifdef MAGICAL_TOUCH
if (block_id_out == 2 || block_id_out == 3 || block_id_out == 4 || block_id_out == 19 || block_id_out == 60 || block_id_out == 61 || block_id_out == 62) {
discard;
}
if (block_id_out == 15) {

if (grass_cube_mask_out < 0.5 || grass_blade_mask_out > 0.5) {
discard;
}
}
#endif

if (block_id_out == 1 || block_id_out == 8) discard;

if (leaf_flat_mask_out > 0.5) discard;

float shadowAlphaCutoff = alphaTestRef;
bool isCropLikeShadowCaster = (block_id_out == 2 || block_id_out == 3 || block_id_out == 4 || block_id_out == 19 || block_id_out == 60 || block_id_out == 61 || block_id_out == 62);
if (isCropLikeShadowCaster) shadowAlphaCutoff = max(shadowAlphaCutoff, 0.35);

bool isLeafShadowCaster = (block_id_out == 5 || block_id_out == 82);

if (!isNetherPortal && !isLeafShadowCaster && block_id_out != 63 && color.a < shadowAlphaCutoff) {
discard;
}
if ((isNetherPortal || block_id_out == 63) && color.a < alphaTestRef) {
discard;
}

if (isNetherPortal) {
shadowcolor1out = vec4(isEntity, 0.0, 0.0, 0.25);
shadowcolor = vec4(0.6, 0.1, 1.0, 0.05);
return;
}
if (block_id_out == 63) {
shadowcolor1out = vec4(isEntity, 0.0, 0.0, 0.25);
shadowcolor = vec4(0.2, 0.8, 0.6, 0.05);
return;
}

if (isCropLikeShadowCaster) {
shadowcolor1out = vec4(isEntity, 0.0, 0.0, shaftHeightAlpha);
shadowcolor = vec4(0.0, 0.0, 0.0, 1.0);
return;
}

bool isGlass = (block_id_out == 14 || (block_id_out >= 64 && block_id_out <= 79) || block_id_out == 80);
if (isGlass) {
vec3 tint = getShadowGlassTintFromBlockId(block_id_out);

shadowcolor1out = vec4(isEntity, 0.0, 0.0, 0.25);
shadowcolor = vec4(tint, 0.05);
return;
}

shadowcolor1out = vec4(isEntity, 0.0, 0.0, shaftHeightAlpha);

shadowcolor = vec4(color.rgb, 1.0);
}
