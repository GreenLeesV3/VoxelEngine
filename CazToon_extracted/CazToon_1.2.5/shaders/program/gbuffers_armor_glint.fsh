/* RENDERTARGETS: 0,1,4 */

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

void main() {
vec4 color = texture(gtexture, texcoord) * glcolor;
gl_FragData[0] = color;
gl_FragData[1] = vec4(0.0);
gl_FragData[2] = vec4(0.0);
}
