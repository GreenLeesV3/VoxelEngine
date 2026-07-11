#version 330 compatibility

#include "/settings.glsl"

out vec2 texcoord;

void main() {
gl_Position = ftransform();
gl_Position.xy = (gl_Position.xy * 0.5 + 0.5) * (0.01 + FOG_RENDER_SCALE) * 2.0 - 1.0;
texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
