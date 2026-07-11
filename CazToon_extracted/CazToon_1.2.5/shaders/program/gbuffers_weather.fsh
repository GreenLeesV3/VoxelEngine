/* RENDERTARGETS: 7,1 */

#include "/settings.glsl"

uniform sampler2D gtexture;
uniform sampler2D depthtex1;

in vec2 texcoord;
in vec4 glcolor;
in vec2 lmcoord;
in float viewDist;

void main() {

float skylight = lmcoord.y;
if (skylight < 0.8) discard;

float sceneDepth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;
if (gl_FragCoord.z > sceneDepth) discard;

vec4 color = texture(gtexture, texcoord) * glcolor;
color.a *= clamp(RAIN_OPACITY, 0.0, 1.0);
gl_FragData[0] = color;
gl_FragData[1] = vec4(1.0, 0.0, 0.0, 0.0);
}
