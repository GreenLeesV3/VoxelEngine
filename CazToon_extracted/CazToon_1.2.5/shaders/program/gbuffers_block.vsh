#include "/settings.glsl"

#include "/include/shadow.glsl"
#include "/include/hovering.glsl"

out vec2 texcoord;
out vec4 glcolor;
out vec3 worldPos;
out vec3 normal;
out float isHologram;
out float skylight;
out float blocklight;
out float viewDistance;
out vec4 shadowPos;
flat out int blockIdOut;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;

void main() {
texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

glcolor = gl_Color;

vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
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

int block_id_raw = int(mc_Entity.x);
bool has_block_properties_id = (block_id_raw >= 10000);
int block_id = has_block_properties_id ? (block_id_raw - 10000) : 0;
isHologram = (has_block_properties_id && block_id == 80) ? 1.0 : 0.0;
blockIdOut = block_id;

shadowPos = vec4(0.0);
#ifdef SHADOWS_ENABLED
{
vec4 shadowClipPos4 = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shadowClipPosXYZ = shadowClipPos4.xyz;
float bias = computeBias(shadowClipPosXYZ);
vec3 distorted = distortShadowClipPos(shadowClipPosXYZ);
shadowPos.xyz = distorted * 0.5 + 0.5;
vec4 shadowNormal = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal)), 1.0);
shadowPos.xyz += shadowNormal.xyz / shadowNormal.w * bias;
shadowPos.w = 1.0;
}
#endif
}
