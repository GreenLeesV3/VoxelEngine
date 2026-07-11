out vec2 texcoord;
out vec4 glcolor;
out vec3 worldPos;
out vec3 normal;
out float isHologram;

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;

void main() {
gl_Position = ftransform();

texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
glcolor = gl_Color;

vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
worldPos = scenePos + cameraPosition;
normal = normalize(gl_NormalMatrix * gl_Normal);

int block_id_raw = int(mc_Entity.x);
bool has_block_properties_id = (block_id_raw >= 10000);
int block_id = has_block_properties_id ? (block_id_raw - 10000) : 0;

bool isGlass = (block_id == 14 || block_id == 80 || (block_id >= 64 && block_id <= 79));
isHologram = (has_block_properties_id && isGlass) ? 1.0 : 0.0;
}
