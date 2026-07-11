#include "/settings.glsl"

#include "/include/hovering.glsl"

out vec2 texcoord;
out vec4 glcolor;
out vec3 worldPos;
out vec3 normal;
out float isHologram;
out vec3 viewPos;
out float skylight;
out float blocklight;
out float viewDistance;
flat out float emissive;
flat out float emissiveType;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;

void main() {
texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

int block_id_raw = int(mc_Entity.x);
bool has_block_properties_id = (block_id_raw >= 10000);
int block_id = has_block_properties_id ? (block_id_raw - 10000) : 0;

if (has_block_properties_id) {
float maxChannel = max(max(gl_Color.r, gl_Color.g), gl_Color.b);
vec3 flatColor = (maxChannel > 0.15) ? (gl_Color.rgb / maxChannel) : gl_Color.rgb;
glcolor = vec4(flatColor, gl_Color.a);
} else {
glcolor = gl_Color;
}

viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec3 world_pos = scenePos + cameraPosition;

float hoverOffset = getHoverOffset(world_pos);
if (hoverOffset != 0.0) {
world_pos.y += hoverOffset;
scenePos = world_pos - cameraPosition;
viewPos = (gbufferModelView * vec4(scenePos, 1.0)).xyz;
}
gl_Position = gl_ProjectionMatrix * vec4(viewPos, 1.0);

worldPos = world_pos;
normal = normalize(gl_NormalMatrix * gl_Normal);
viewDistance = length(viewPos);

vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
blocklight = clamp(lmcoord.x, 0.0, 1.0);
skylight = clamp(lmcoord.y, 0.0, 1.0);

bool isIce = (block_id == 8);
bool isSlimeHoney = false;
bool isGlass = (block_id == 80 || (block_id >= 64 && block_id <= 79));
isHologram = (has_block_properties_id && isGlass && !isIce) ? 1.0 : 0.0;

bool is_emissive = (block_id == 88 || block_id == 63);
emissive = is_emissive ? 1.0 : 0.0;
emissiveType = float(block_id - 20);
}
