/* RENDERTARGETS: 2,3 */

#include "/settings.glsl"

uniform sampler2D colortex2;
uniform sampler2D colortex3;

in vec2 texcoord;

const float weights[13] = float[13](
0.1176, 0.1133, 0.1009, 0.0831, 0.0633, 0.0446, 0.0291, 0.0175, 0.0098, 0.0050, 0.0024, 0.0010, 0.0004
);

vec4 sampleBloomWide(vec2 uv) {
if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
return texture(colortex2, uv);
}

vec4 sampleBloomTight(vec2 uv) {
if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
return texture(colortex3, uv);
}

void main() {
#ifdef BLOOM_ENABLED
vec2 texelSize = 1.0 / vec2(textureSize(colortex2, 0));
vec2 wideDirection = vec2(texelSize.x * BLOOM_RADIUS * BLOOM_CLOSE_RADIUS * 2.0, 0.0);
vec2 tightDirection = vec2(texelSize.x * BLOOM_RADIUS * BLOOM_FAR_RADIUS * 0.85, 0.0);

vec4 bloom = sampleBloomWide(texcoord) * weights[0];
vec4 coloredLight = sampleBloomTight(texcoord) * weights[0];

for (int i = 1; i < 7; i++) {
vec2 wideOffset = wideDirection * float(i);
vec2 tightOffset = tightDirection * float(i);
bloom += sampleBloomWide(texcoord + wideOffset) * weights[i];
bloom += sampleBloomWide(texcoord - wideOffset) * weights[i];
coloredLight += sampleBloomTight(texcoord + tightOffset) * weights[i];
coloredLight += sampleBloomTight(texcoord - tightOffset) * weights[i];
}

gl_FragData[0] = bloom;
gl_FragData[1] = coloredLight;
#else
gl_FragData[0] = vec4(0.0);
gl_FragData[1] = vec4(0.0);
#endif
}
