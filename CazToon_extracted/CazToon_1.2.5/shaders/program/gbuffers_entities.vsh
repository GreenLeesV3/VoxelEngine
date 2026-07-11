#include "/settings.glsl"

#include "/include/shadow.glsl"

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform int entityId;
uniform float frameTimeCounter;

uniform int currentRenderedItemId;

out vec2 texcoord;
out vec4 glcolor;
out float viewDistance;
out float skylight;
out float blocklight;
out float emissive;
flat out float emissiveType;
out vec4 shadowPos;
out vec3 normal;
out vec3 worldPos;
out float nametagHolo;
#ifdef PBR_ENABLED
out vec3 tangentVec;
out vec3 binormalVec;
out vec3 viewPosOut;
attribute vec4 at_tangent;
#endif

void main() {
gl_Position = ftransform();

texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

glcolor = gl_Color;

vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
viewDistance = length(viewPos);
skylight = clamp(gl_MultiTexCoord1.y / 240.0, 0.0, 1.0);
blocklight = clamp(gl_MultiTexCoord1.x / 240.0, 0.0, 1.0);

#ifdef EMISSIVE
emissive = 1.0;
emissiveType = 0.0;
#else
emissive = 0.0;
emissiveType = 0.0;

int itemBlockId = max(currentRenderedItemId - 10000, 0);
if ((itemBlockId >= 20 && itemBlockId <= 63) || itemBlockId == 6) {
emissive = 1.0;
emissiveType = float(itemBlockId == 6 ? 0 : itemBlockId - 20);
}
#endif

shadowPos = vec4(0.0);

normal = normalize(gl_NormalMatrix * gl_Normal);
#ifdef PBR_ENABLED
tangentVec  = normalize(gl_NormalMatrix * at_tangent.xyz);
binormalVec = normalize(cross(normal, tangentVec) * at_tangent.w);
viewPosOut  = viewPos;
#endif

#ifdef SHADOWS_ENABLED

vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec4 shadowClipPos4 = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shadowClipPosXYZ = shadowClipPos4.xyz;
float bias = computeBias(shadowClipPosXYZ);
vec3 distorted = distortShadowClipPos(shadowClipPosXYZ);
shadowPos.xyz = distorted * 0.5 + 0.5;

vec4 shadowNormal = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal)), 1.0);
shadowPos.xyz += shadowNormal.xyz / shadowNormal.w * bias;
shadowPos.w = 1.0;
#else
vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
#endif

worldPos = scenePos + cameraPosition;
nametagHolo = 0.0;
}
