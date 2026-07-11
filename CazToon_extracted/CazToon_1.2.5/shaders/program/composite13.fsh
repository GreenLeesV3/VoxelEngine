/* RENDERTARGETS: 10 */

#include "/settings.glsl"

in vec2 texcoord;

uniform sampler2D colortex10;
uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;

float fogResolveLinearDepth(float depth) {
return (near * far) / (depth * (near - far) + far);
}

vec4 depthAwareFogResolve(sampler2D fogTex) {
vec2 viewSize = vec2(viewWidth, viewHeight);
ivec2 lowSize = ivec2(max(viewSize * FOG_RENDER_SCALE, vec2(1.0)));
ivec2 lowBase = ivec2(floor(gl_FragCoord.xy * FOG_RENDER_SCALE));
float referenceDepth = fogResolveLinearDepth(texture(depthtex0, texcoord).r);

const ivec2 OFFSETS[5] = ivec2[](
ivec2(0, 0),
ivec2(1, 0),
ivec2(-1, 0),
ivec2(0, 1),
ivec2(0, -1)
);

vec4 sum = vec4(0.0);
float weightSum = 0.0;
float threshold = max(referenceDepth * 0.05, 0.25);

for (int i = 0; i < 5; i++) {
ivec2 lowCoord = clamp(lowBase + OFFSETS[i], ivec2(0), lowSize - ivec2(1));
vec2 fogUv = (vec2(lowCoord) + 0.5) / viewSize;
vec2 sourceUv = (vec2(lowCoord) / FOG_RENDER_SCALE + 0.5) / viewSize;
float sampleDepth = fogResolveLinearDepth(texture(depthtex0, clamp(sourceUv, vec2(0.0), vec2(1.0))).r);
float weight = abs(sampleDepth - referenceDepth) < threshold ? 1.0 : 0.0001;
sum += texture(fogTex, fogUv) * weight;
weightSum += weight;
}

return sum / max(weightSum, 0.0001);
}

void main() {
gl_FragData[0] = depthAwareFogResolve(colortex10);
}
