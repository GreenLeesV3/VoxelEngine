/* RENDERTARGETS: 0,2,3 */

#include "/settings.glsl"

#ifdef END_SHADER
#include "/include/end_sky.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D colortex14;
uniform sampler2D depthtex0;
uniform sampler2D dhDepthTex;
uniform sampler2D noisetex;

uniform float sunAngle;
uniform float near;
uniform float far;
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
uniform mat4 gbufferProjection;

#ifdef END_SHADER
uniform float frameTimeCounter;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
#endif

in vec2 texcoord;

#include "/include/depth_utils.glsl"

float getCombinedLinearDepth(vec2 coord) {
float depthMC = texture(depthtex0, coord).r;
float depthDH = texture(dhDepthTex, coord).r;

if (depthMC >= 0.9999 && depthDH < 0.9999) {
return linearizeDepthDH(depthDH);
}
return linearizeDepth(depthMC);
}

float getBloomCompStrength() {
return clamp(BLOOM_DISTANCE_COMPENSATION * 4.0, 0.0, 1.0);
}

float getBloomEffectiveDistance(float linearDepth) {

float defaultFovScale = 1.73;
float fovScale = max(gbufferProjection[1][1] / defaultFovScale, 0.35);
return linearDepth / fovScale;
}

float getBloomDistanceGain(float effectiveDist) {
float midRange = smoothstep(10.0, 28.0, effectiveDist);
float farRange = smoothstep(26.0, 84.0, effectiveDist);
float extremeRange = smoothstep(180.0, 320.0, effectiveDist);
return clamp(1.0 + midRange * 0.30 + farRange * 0.95 - extremeRange * 0.35, 1.0, 2.25);
}

float getBloomHaloBoost(float effectiveDist) {
float midRange = smoothstep(8.0, 24.0, effectiveDist);
float farRange = smoothstep(24.0, 84.0, effectiveDist);
float extremeRange = smoothstep(180.0, 320.0, effectiveDist);
return clamp(1.0 + midRange * 0.45 + farRange * 1.20 - extremeRange * 0.55, 1.0, 2.6);
}

float getEmitterScreenSize(vec2 uv) {
vec2 texelSize = 1.0 / vec2(textureSize(colortex1, 0));
float size = 0.0;

size += step(0.5, texture(colortex1, uv).g) * 0.18;

size += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x, 0.0), vec2(0.0), vec2(1.0))).g) * 0.12;
size += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x, 0.0), vec2(0.0), vec2(1.0))).g) * 0.12;
size += step(0.5, texture(colortex1, clamp(uv + vec2(0.0, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.12;
size += step(0.5, texture(colortex1, clamp(uv + vec2(0.0,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.12;

size += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;
size += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x, -texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;
size += step(0.5, texture(colortex1, clamp(uv + vec2(-texelSize.x,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;
size += step(0.5, texture(colortex1, clamp(uv + vec2( texelSize.x,  texelSize.y), vec2(0.0), vec2(1.0))).g) * 0.08;

return clamp(size, 0.0, 1.0);
}

float getEntityBloomMask(vec2 uv) {
float entityTag = texture(colortex1, uv).a;
return step(0.31, entityTag) * (1.0 - step(0.71, entityTag));
}

vec3 stylizeBloomColor(vec3 sourceColor) {
float peak = max(max(sourceColor.r, sourceColor.g), sourceColor.b);
if (peak < 0.0001) return vec3(0.0);

vec3 hue = sourceColor / peak;
float warm = clamp((hue.r - hue.b) * 0.90 + hue.g * 0.35, 0.0, 1.0);
float cool = clamp((max(hue.g, hue.b) - hue.r) * 0.65, 0.0, 1.0);
float energy = peak * (1.0 + warm * 0.18 - cool * 0.04);

vec3 toonTint = hue;
toonTint.r = max(toonTint.r, warm * 0.16);
toonTint.g = mix(toonTint.g, max(toonTint.g, 0.42), warm * 0.16);

return toonTint * energy;
}

vec3 sampleBloomEmitter(vec2 uv, float weight, float haloSample, float compStrength, float chainMode) {
uv = clamp(uv, vec2(0.0), vec2(1.0));
float emissive = texture(colortex1, uv).g;
if (emissive < 0.5 || weight <= 0.0) return vec3(0.0);

vec3 source = stylizeBloomColor(texture(colortex3, uv).rgb);
float entityMask = getEntityBloomMask(uv);
float effectiveDist = getBloomEffectiveDistance(getCombinedLinearDepth(uv));

float distFalloff = 1.0 / (1.0 + effectiveDist * 0.03);
float distGain = distFalloff * mix(1.0, ENTITY_BLOOM_STRENGTH, entityMask);
float haloGain = mix(1.0, ENTITY_BLOOM_RADIUS, entityMask);
float sampleWeight = weight * mix(1.0, haloGain, haloSample);
float emitterSize = getEmitterScreenSize(uv);
float closeWeight = smoothstep(0.16, 0.68, emitterSize);
float farWeight = 1.0 - smoothstep(0.08, 0.38, emitterSize);

closeWeight = mix(closeWeight, max(closeWeight, 0.82), entityMask * smoothstep(1.0, 2.0, ENTITY_BLOOM_RADIUS));
farWeight *= mix(1.0, 1.0 / max(ENTITY_BLOOM_RADIUS, 0.1), entityMask * 0.35);

float weightSum = max(closeWeight + farWeight, 0.0001);
closeWeight /= weightSum;
farWeight /= weightSum;
float chainFactor = mix(closeWeight, farWeight, chainMode);

return source * distGain * sampleWeight * chainFactor;
}

void main() {
vec4 sceneSample = texture(colortex0, texcoord);
vec3 color = sceneSample.rgb;
float sceneAlpha = sceneSample.a;

#ifdef MATERIAL_REFLECTIONS_ENABLED
{
ivec2 texelCoord = ivec2(gl_FragCoord.xy);
vec4 centerRefl = texelFetch(colortex14, texelCoord, 0);

if (centerRefl.a > 0.5) {
vec4 reflData = texelFetch(colortex5, texelCoord, 0);
vec4 maskData = texelFetch(colortex1, texelCoord, 0);

bool isMaterialPx = (reflData.z > 0.001 || reflData.w > 0.001)
&& !(maskData.a > 0.01 && maskData.a < 0.99)
&& (reflData.y < 0.9);

if (isMaterialPx) {

vec3 centerNormal = vec3(reflData.z * 2.0 - 1.0, reflData.w * 2.0 - 1.0, 0.0);
centerNormal.z = sqrt(max(1.0 - dot(centerNormal.xy, centerNormal.xy), 0.0));

float materialRoughness = clamp(reflData.x, 0.0, 1.0);

float dither = texture(noisetex, gl_FragCoord.xy / 128.0).b;
vec2 px = vec2(1.0 / viewWidth, 1.0 / viewHeight);

float smoothnessDecoded = 1.0 - sqrt(materialRoughness);
const float spatialFactor = 2.5;
const float spatialFactorM = 2.0 * spatialFactor * spatialFactor;
vec2 texelSize = (3.0 + 6.0 * dither) * px;
texelSize *= 1.0 - 0.75 * pow(smoothnessDecoded, 8.0);

vec4 sum = vec4(0.0);
float wsum = 0.0;
const int K = 2;
for (int dy = -K; dy <= K; dy++) {
for (int dx = -K; dx <= K; dx++) {
vec2 offset = vec2(float(dx), float(dy)) * texelSize;
vec2 sampleCoord = texcoord + offset;
if (sampleCoord.x < 0.0 || sampleCoord.x > 1.0 ||
sampleCoord.y < 0.0 || sampleCoord.y > 1.0) continue;

ivec2 sampleTexel = clamp(ivec2(sampleCoord * vec2(viewWidth, viewHeight)), ivec2(0), ivec2(viewWidth - 1.0, viewHeight - 1.0));

vec4 sReflData = texelFetch(colortex5, sampleTexel, 0);
vec3 sNormal = vec3(sReflData.z * 2.0 - 1.0, sReflData.w * 2.0 - 1.0, 0.0);
sNormal.z = sqrt(max(1.0 - dot(sNormal.xy, sNormal.xy), 0.0));
if (length(centerNormal - sNormal) > 0.1) continue;

vec4 sRefl = texelFetch(colortex14, sampleTexel, 0);
if (sRefl.a < 0.95) continue;

float spatialDist2 = float(dx * dx + dy * dy);
float w = exp(-spatialDist2 / spatialFactorM);

sum += sRefl * w;
wsum += w;
}
}

if (wsum > 0.001) {
vec3 blurredRefl = sum.rgb / wsum;
float reflLum = dot(blurredRefl, vec3(0.299, 0.587, 0.114));
blurredRefl = mix(vec3(reflLum), blurredRefl, 0.72);

float metalnessDecoded = clamp(reflData.y / 0.85, 0.0, 1.0);

float pxSkylight = maskData.b;
float skyFade = smoothstep(0.5, 1.0, pxSkylight);
float metalBoost = metalnessDecoded * 0.15 * (1.0 - skyFade);
float ssrStrength = mix(1.0, 0.3, skyFade);
const float materialSsrCleanBoost = 1.75;
color = max(color + blurredRefl * (ssrStrength + metalBoost) * materialSsrCleanBoost, vec3(0.0));
}
}
}
}
#endif

#if defined(END_SHADER) && defined(END_SKY_ENABLED)
{
float depth = texture(depthtex0, texcoord).r;
vec4 maskData = texture(colortex1, texcoord);

bool isVoxyPixel = (maskData.a > 0.99 && maskData.g < 0.5);
#ifdef DISTANT_HORIZONS
float depthDH = texture(dhDepthTex, texcoord).r;
if (depth >= 0.9999 && depthDH >= 0.9999 && !isVoxyPixel) {
#else
if (depth >= 0.9999 && !isVoxyPixel) {
#endif

vec4 clipPos = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
vec4 viewPos = gbufferProjectionInverse * clipPos;
viewPos.xyz /= viewPos.w;
vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewPos.xyz);
color = renderEndSky(worldDir, frameTimeCounter, cameraPosition);
}
}
#endif

gl_FragData[0] = vec4(color, sceneAlpha);

#ifdef BLOOM_ENABLED
vec3 bloomWideColor = vec3(0.0);
vec3 bloomTightColor = vec3(0.0);
float compStrength = getBloomCompStrength();
vec2 texelSize = 1.0 / vec2(textureSize(colortex3, 0));

bloomWideColor += sampleBloomEmitter(texcoord, 0.60, 0.0, compStrength, 0.0);
bloomTightColor += sampleBloomEmitter(texcoord, 0.32, 0.0, compStrength, 1.0);

bloomWideColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x, 0.0), 0.34, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2( texelSize.x, 0.0), 0.34, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(0.0, -texelSize.y), 0.34, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(0.0,  texelSize.y), 0.34, 1.0, compStrength, 0.0);

bloomTightColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x, 0.0), 0.20, 0.0, compStrength, 1.0);
bloomTightColor += sampleBloomEmitter(texcoord + vec2( texelSize.x, 0.0), 0.20, 0.0, compStrength, 1.0);
bloomTightColor += sampleBloomEmitter(texcoord + vec2(0.0, -texelSize.y), 0.20, 0.0, compStrength, 1.0);
bloomTightColor += sampleBloomEmitter(texcoord + vec2(0.0,  texelSize.y), 0.20, 0.0, compStrength, 1.0);

bloomWideColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x, -texelSize.y), 0.24, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2( texelSize.x, -texelSize.y), 0.24, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x,  texelSize.y), 0.24, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2( texelSize.x,  texelSize.y), 0.24, 1.0, compStrength, 0.0);

bloomTightColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x, -texelSize.y), 0.12, 0.0, compStrength, 1.0);
bloomTightColor += sampleBloomEmitter(texcoord + vec2( texelSize.x, -texelSize.y), 0.12, 0.0, compStrength, 1.0);
bloomTightColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x,  texelSize.y), 0.12, 0.0, compStrength, 1.0);
bloomTightColor += sampleBloomEmitter(texcoord + vec2( texelSize.x,  texelSize.y), 0.12, 0.0, compStrength, 1.0);

bloomWideColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x * 2.0, 0.0), 0.18, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2( texelSize.x * 2.0, 0.0), 0.18, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(0.0, -texelSize.y * 2.0), 0.18, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(0.0,  texelSize.y * 2.0), 0.18, 1.0, compStrength, 0.0);

bloomWideColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x * 2.0, -texelSize.y * 2.0), 0.12, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2( texelSize.x * 2.0, -texelSize.y * 2.0), 0.12, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x * 2.0,  texelSize.y * 2.0), 0.12, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2( texelSize.x * 2.0,  texelSize.y * 2.0), 0.12, 1.0, compStrength, 0.0);

bloomWideColor += sampleBloomEmitter(texcoord + vec2(-texelSize.x * 3.0, 0.0), 0.08, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2( texelSize.x * 3.0, 0.0), 0.08, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(0.0, -texelSize.y * 3.0), 0.08, 1.0, compStrength, 0.0);
bloomWideColor += sampleBloomEmitter(texcoord + vec2(0.0,  texelSize.y * 3.0), 0.08, 1.0, compStrength, 0.0);

float dayScale = 1.0;
#ifndef END_SHADER
float emitterSkylight = texture(colortex1, texcoord).b;
float emitterEmissive = texture(colortex1, texcoord).g;
float dayFactor = smoothstep(0.02, 0.10, fract(sunAngle)) * smoothstep(0.48, 0.40, fract(sunAngle));

float emitterDayGate = (emitterEmissive > 0.5) ? emitterSkylight : 1.0;
dayScale = mix(1.0, BLOOM_DAY_STRENGTH, dayFactor * emitterDayGate);
#endif

float emitterDepth = getCombinedLinearDepth(texcoord);
float encodedDepth = clamp(emitterDepth / 512.0, 0.0, 1.0);

#ifdef END_SHADER
{
float endDepth = texture(depthtex0, texcoord).r;
if (endDepth >= 0.9999) {
float skyLum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 skyBloom = vec3(0.5, 0.2, 0.7) * skyLum;
bloomWideColor += skyBloom;
}
}
#endif

float bloomWideAlpha = (length(bloomWideColor) > 0.001) ? encodedDepth : 0.0;
float bloomTightAlpha = (length(bloomTightColor) > 0.001) ? encodedDepth : 0.0;
gl_FragData[1] = vec4(bloomWideColor * BLOOM_INTENSITY * BLOOM_CLOSE_STRENGTH * dayScale, bloomWideAlpha);
gl_FragData[2] = vec4(bloomTightColor * BLOOM_INTENSITY * BLOOM_FAR_STRENGTH * dayScale, bloomTightAlpha);
#else
gl_FragData[1] = vec4(0.0);
gl_FragData[2] = vec4(0.0);
#endif
}
