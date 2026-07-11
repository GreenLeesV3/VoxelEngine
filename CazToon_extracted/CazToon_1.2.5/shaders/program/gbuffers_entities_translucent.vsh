#include "/settings.glsl"

#include "/include/shadow.glsl"

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform int entityId;
uniform float frameTimeCounter;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

out vec2 texcoord;
out vec4 glcolor;
out vec3 worldPos;
out float skylight;
out float blocklight;
out float viewDistance;
out float nametagHolo;
out vec4 shadowPos;
out vec3 normal;

void main() {
gl_Position = ftransform();

texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

skylight = clamp(gl_MultiTexCoord1.y / 240.0, 0.0, 1.0);
blocklight = clamp(gl_MultiTexCoord1.x / 240.0, 0.0, 1.0);

glcolor = gl_Color;

vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
viewDistance = length(viewPos);
vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
worldPos = scenePos + cameraPosition;

shadowPos = vec4(0.0);
#ifdef SHADOWS_ENABLED

normal = normalize(gl_NormalMatrix * gl_Normal);

vec4 shadowClipPos4 = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shadowClipPosXYZ = shadowClipPos4.xyz;
float bias = computeBias(shadowClipPosXYZ);
vec3 distorted = distortShadowClipPos(shadowClipPosXYZ);
shadowPos.xyz = distorted * 0.5 + 0.5;
vec4 shadowNormal = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal)), 1.0);
shadowPos.xyz += shadowNormal.xyz / shadowNormal.w * bias;
shadowPos.w = 1.0;
#endif
nametagHolo = 0.0;
}
