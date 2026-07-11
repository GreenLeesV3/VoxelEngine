#version 330 compatibility

in vec2 texcoord;
uniform sampler2D colortex0;
/* RENDERTARGETS: 0 */
void main() {
gl_FragData[0] = texture(colortex0, texcoord);
}
