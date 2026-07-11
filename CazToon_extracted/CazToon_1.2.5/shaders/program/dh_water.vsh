#include "/settings.glsl"

#include "/include/hovering.glsl"
#include "/include/ocean_waves.glsl"

const float ambientOcclusionLevel = 0.0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

out vec4 vColor;
out float viewDistance;
out vec3 viewDir;
out vec3 viewPos;
out vec3 worldPos;
out vec3 normal;
out float skylight;
out float blocklight;
out float waveHeight;
out vec3 waveNormal;
flat out int materialId;

void main() {
vColor = gl_Color;

vec3 vPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scenePos = (gbufferModelViewInverse * vec4(vPos, 1.0)).xyz;
vec3 world_pos = scenePos + cameraPosition;

bool isWater = (dhMaterialId == DH_BLOCK_WATER);
waveHeight = 0.0;
waveNormal = vec3(0.0, 1.0, 0.0);

#ifdef WATER_WAVES_ENABLED
if (false) {
}
#endif

float hoverOffset = getHoverOffset(world_pos);
world_pos.y += hoverOffset;
scenePos = world_pos - cameraPosition;
vPos = (gbufferModelView * vec4(scenePos, 1.0)).xyz;
gl_Position = gl_ProjectionMatrix * vec4(vPos, 1.0);

viewDistance = length(vPos);
viewDir = normalize(scenePos);
viewPos = vPos;
worldPos = world_pos;

normal = normalize(gl_NormalMatrix * gl_Normal);

materialId = dhMaterialId;

vec2 lmRaw = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
vec2 lmCoord = clamp((lmRaw - 0.03125) * 1.06667, 0.0, 1.0);
skylight = lmCoord.y;
blocklight = lmCoord.x;
}
