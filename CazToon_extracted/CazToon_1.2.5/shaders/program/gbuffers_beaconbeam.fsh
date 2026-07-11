/* RENDERTARGETS: 7 */

#include "/settings.glsl"

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;

gl_FragData[0] = color;
}
