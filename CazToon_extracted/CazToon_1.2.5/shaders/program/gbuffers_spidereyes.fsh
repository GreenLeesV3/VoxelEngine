/* RENDERTARGETS: 0,1,3 */

#include "/settings.glsl"

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;
if (color.a < 0.1) discard;

vec3 visibleColor = color.rgb * EMISSIVE_BRIGHTNESS * ENTITY_EMISSIVE_BRIGHTNESS;
vec3 bloomColor = color.rgb * EMISSIVE_BRIGHTNESS * ENTITY_EMISSIVE_BLOOM * 2.0;

gl_FragData[0] = vec4(visibleColor, color.a);
gl_FragData[1] = vec4(0.0, 1.0, 0.0, 0.5);
gl_FragData[2] = vec4(bloomColor, 1.0);
}
