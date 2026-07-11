#include "/settings.glsl"

#include "/include/hovering.glsl"
#include "/include/shadow.glsl"

const float ambientOcclusionLevel = float(DH_AO_INTENSITY) / 100.0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;

out vec4 vColor;
out float viewDistance;
out vec3 viewDir;
out vec3 normal;
out float NdotL;
out vec3 worldPos;
flat out int materialId;
out float skylight;
out float blockLight;
out vec4 shadowPos;

void main() {
vColor = gl_Color;

vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec3 world_pos = scenePos + cameraPosition;

float hoverOffset = getHoverOffset(world_pos);
world_pos.y += hoverOffset;
scenePos = world_pos - cameraPosition;
viewPos = (gbufferModelView * vec4(scenePos, 1.0)).xyz;
gl_Position = gl_ProjectionMatrix * vec4(viewPos, 1.0);

viewDistance = length(viewPos);
viewDir = normalize(scenePos);
worldPos = world_pos;

normal = normalize(gl_NormalMatrix * gl_Normal);

vec3 lightDir = normalize(shadowLightPosition);
NdotL = dot(normal, lightDir);

materialId = dhMaterialId;

vec2 lmRaw = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
vec2 lmCoord = clamp((lmRaw - 0.03125) * 1.06667, 0.0, 1.0);
skylight = lmCoord.y;
blockLight = lmCoord.x;

#ifdef SHADOWS_ENABLED

vec4 shadowClipPos4 = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shadowClipPosXYZ = shadowClipPos4.xyz;

float bias = computeBias(shadowClipPosXYZ);

vec3 distorted = distortShadowClipPos(shadowClipPosXYZ);

shadowPos.xyz = distorted * 0.5 + 0.5;

vec4 normalShadow = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal)), 1.0);
shadowPos.xyz += normalShadow.xyz / normalShadow.w * bias;

shadowPos.w = NdotL;
#else
shadowPos = vec4(0.0);
#endif
}
