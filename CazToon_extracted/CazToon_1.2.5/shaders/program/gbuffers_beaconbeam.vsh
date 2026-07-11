#include "/settings.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

out vec2 texcoord;
out vec4 glcolor;

void main() {

vec3 view_pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scene_pos = (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
vec3 world_pos = scene_pos + cameraPosition;

scene_pos = world_pos - cameraPosition;
view_pos = (gbufferModelView * vec4(scene_pos, 1.0)).xyz;
gl_Position = gl_ProjectionMatrix * vec4(view_pos, 1.0);

texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
glcolor = gl_Color;
}
