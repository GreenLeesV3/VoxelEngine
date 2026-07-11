/* RENDERTARGETS: 2,3 */

#include "/settings.glsl"

uniform sampler2D colortex2;
uniform sampler2D colortex3;

in vec2 texcoord;

const float weights[7] = float[7](
0.198596, 0.175713, 0.121703, 0.065984, 0.028002, 0.009300, 0.002216
);

vec4 sampleBloomWide(vec2 uv, vec2 bloomMin, vec2 bloomMax) {
if (uv.x < 0.0 || uv.y < 0.0 || uv.x > BLOOM_RENDER_SCALE || uv.y > BLOOM_RENDER_SCALE) return vec4(0.0);
return texture(colortex2, clamp(uv, bloomMin, bloomMax));
}

vec4 sampleBloomTight(vec2 uv, vec2 bloomMin, vec2 bloomMax) {
if (uv.x < 0.0 || uv.y < 0.0 || uv.x > BLOOM_RENDER_SCALE || uv.y > BLOOM_RENDER_SCALE) return vec4(0.0);
return texture(colortex3, clamp(uv, bloomMin, bloomMax));
}

void main() {
#ifdef BLOOM_ENABLED
vec2 texelSize = 1.0 / vec2(textureSize(colortex2, 0));
vec2 bloomTexcoord = texcoord * BLOOM_RENDER_SCALE;
vec2 bloomMin = texelSize * 0.5;
vec2 bloomMax = vec2(BLOOM_RENDER_SCALE) - texelSize * 0.5;
vec2 wideDirection = vec2(texelSize.x * BLOOM_RADIUS * BLOOM_CLOSE_RADIUS * 8.0 * BLOOM_RENDER_SCALE, 0.0);
vec2 tightDirection = vec2(texelSize.x * BLOOM_RADIUS * BLOOM_FAR_RADIUS * 3.0 * BLOOM_RENDER_SCALE, 0.0);

vec4 bloom = sampleBloomWide(bloomTexcoord, bloomMin, bloomMax) * weights[0];
vec4 coloredLight = sampleBloomTight(bloomTexcoord, bloomMin, bloomMax) * weights[0];

for (int i = 1; i < 5; i++) {
vec2 wideOffset = wideDirection * (float(i) + 0.5);
vec2 tightOffset = tightDirection * (float(i) + 0.5);
bloom += sampleBloomWide(bloomTexcoord + wideOffset, bloomMin, bloomMax) * weights[i];
bloom += sampleBloomWide(bloomTexcoord - wideOffset, bloomMin, bloomMax) * weights[i];
coloredLight += sampleBloomTight(bloomTexcoord + tightOffset, bloomMin, bloomMax) * weights[i];
coloredLight += sampleBloomTight(bloomTexcoord - tightOffset, bloomMin, bloomMax) * weights[i];
}

gl_FragData[0] = bloom;
gl_FragData[1] = coloredLight;
#else
gl_FragData[0] = vec4(0.0);
gl_FragData[1] = vec4(0.0);
#endif
}
