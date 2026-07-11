#include "/settings.glsl"
#include "/include/waving.glsl"
#include "/include/shadow.glsl"
#include "/include/hovering.glsl"

#ifdef LPV_ENABLED
#include "/include/lpv/lpv_common.glsl"
layout(r8ui) uniform writeonly uimage3D lpvVoxelImg;
#endif

out vec2 texcoord;
flat out int block_id_out;
flat out float grass_blade_mask_out;
flat out float grass_cube_mask_out;
flat out float leaf_flat_mask_out;
flat out int block_id_raw_out;
out float shaft_height_metric_out;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
attribute vec3 at_midBlock;

vec3 transform(mat4 m, vec3 p) {
return (m * vec4(p, 1.0)).xyz;
}

void main() {
texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

float skylight = clamp(gl_MultiTexCoord1.y / 240.0, 0.0, 1.0);
bool is_top_vertex = texcoord.y < mc_midTexCoord.y;

int block_id_raw = int(mc_Entity.x);
block_id_raw_out = block_id_raw;
bool has_block_properties_id = (block_id_raw >= 10000);
int block_id = has_block_properties_id ? (block_id_raw - 10000) : 0;
float blocklight = clamp(gl_MultiTexCoord1.x / 240.0, 0.0, 1.0);
block_id_out = block_id;
grass_blade_mask_out = 0.0;
grass_cube_mask_out = 1.0;
leaf_flat_mask_out = 0.0;

bool should_wave = false;
#ifdef WAVING_PLANTS
should_wave = should_wave || (block_id == 2 || block_id == 3 || block_id == 4 || block_id == 15 || block_id == 60 || block_id == 61 || block_id == 62);
#endif
#ifdef WAVING_LEAVES
should_wave = should_wave || (block_id == 5 || block_id == 82);
#endif
#ifdef SWAYING_LANTERNS
should_wave = should_wave || (block_id == 6 || block_id == 89);
#endif

should_wave = should_wave && has_block_properties_id;

vec3 pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);
vec3 world_pos = transform(shadowModelViewInverse, pos) + cameraPosition;

#ifdef LPV_ENABLED
if (has_block_properties_id) {

bool skipTinyLpvVoxel = (block_id >= 90 && block_id <= 93);
if (!skipTinyLpvVoxel) {
int lpv_block_id = block_id;
if (block_id == 30) {
int lightBlockLevel = clamp(int(floor(blocklight * 15.0 + 0.5)), 1, 15);
lpv_block_id = (lightBlockLevel >= 15) ? 30 : (100 + lightBlockLevel);
}
vec3 modelPos = gl_Vertex.xyz + at_midBlock.xyz / 64.0;
vec3 lpvView = (gl_ModelViewMatrix * vec4(modelPos, 1.0)).xyz;
vec3 lpvScene = (shadowModelViewInverse * vec4(lpvView, 1.0)).xyz;
vec3 voxelPos = sceneToVoxelSpace(lpvScene, cameraPosition);
if (isInVoxelVolume(voxelPos)) {
ivec3 texel = voxelToTexel(voxelPos);
imageStore(lpvVoxelImg, texel, uvec4(uint(lpv_block_id + 1), 0u, 0u, 0u));
}
}
}
#endif

if (block_id == 15) {
vec3 n = normalize(gl_Normal);
float horiz = 1.0 - step(0.2, abs(n.y));
float axis_aligned = step(0.98, max(abs(n.x), abs(n.z)));
grass_blade_mask_out = horiz * (1.0 - axis_aligned);

vec3 cubeErr = abs(abs(at_midBlock.xyz) - vec3(32.0));
float cubeErrMax = max(max(cubeErr.x, cubeErr.y), cubeErr.z);
grass_cube_mask_out = 1.0 - step(0.25, cubeErrMax);
}

if (block_id == 5 || block_id == 82) {
vec3 cubeErr = abs(abs(at_midBlock.xyz) - vec3(32.0));
float cubeErrMax = max(max(cubeErr.x, cubeErr.y), cubeErr.z);
leaf_flat_mask_out = step(0.25, cubeErrMax);
}

if (should_wave) {
if (block_id == 15) {

if (grass_blade_mask_out > 0.5) {
world_pos = animate_vertex(world_pos, is_top_vertex, skylight, block_id, at_midBlock.xyz);
}
} else {
world_pos = animate_vertex(world_pos, is_top_vertex, skylight, block_id, at_midBlock.xyz);
}
}

float hoverOffset = getHoverOffset(world_pos);
world_pos.y += hoverOffset;
shaft_height_metric_out = world_pos.y - cameraPosition.y;

pos = transform(shadowModelView, world_pos - cameraPosition);

gl_Position = gl_ProjectionMatrix * vec4(pos, 1.0);

gl_Position.xyz = distortShadowClipPos(gl_Position.xyz);
}
