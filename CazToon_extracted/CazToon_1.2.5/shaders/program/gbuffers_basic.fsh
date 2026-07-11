/* RENDERTARGETS: 0,1 */

#include "/settings.glsl"

in vec4 glcolor;

void main() {

#ifdef STARS_ENABLED

if (glcolor.a < 0.99 && glcolor.r > 0.5 && glcolor.g > 0.5 && glcolor.b > 0.5) {
discard;
}
#endif

gl_FragData[0] = glcolor;
gl_FragData[1] = vec4(1.0, 0.0, 0.0, 0.0);
}
