#include "/settings.glsl"

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out float viewDistance;
out vec3 viewDir;
out vec3 worldPos;

void main() {
gl_Position = ftransform();

texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
glcolor = gl_Color;

vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
viewDistance = length(viewPos);

vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
viewDir = normalize(scenePos);
worldPos = scenePos + cameraPosition;
}
