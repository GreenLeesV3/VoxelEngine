#include "/settings.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;

in vec2 texcoord;

/* RENDERTARGETS: 0 */

bool isVoxyLodPixel(ivec2 texel) {
vec4 maskData = texelFetch(colortex1, texel, 0);
float depth = texelFetch(depthtex0, texel, 0).r;
return (maskData.a > 0.999 && maskData.g < 0.01 && depth >= 0.9999);
}

#ifdef FXAA_ENABLED

const float quality[12] = float[12](1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0);

float GetLuma(vec3 c) {
return dot(c, vec3(0.299, 0.587, 0.114));
}

void main() {
ivec2 texelCoord = ivec2(gl_FragCoord.xy);
vec4 centerSample = texelFetch(colortex0, texelCoord, 0);
vec3 color = centerSample.rgb;

if (!isVoxyLodPixel(texelCoord)) {
#ifdef FXAA_DEBUG

float g = dot(color, vec3(0.299, 0.587, 0.114));
gl_FragData[0] = vec4(vec3(g) * 0.5, centerSample.a);
#else
gl_FragData[0] = centerSample;
#endif
return;
}

float edgeThresholdMin = 0.0312 / FXAA_QUALITY;
float edgeThresholdMax = 0.125  / FXAA_QUALITY;
float subpixelQuality  = 0.75;
int   iterations       = 12;

vec2 view = 1.0 / vec2(viewWidth, viewHeight);

float lumaCenter = GetLuma(color);
float lumaDown   = GetLuma(texelFetch(colortex0, texelCoord + ivec2( 0, -1), 0).rgb);
float lumaUp     = GetLuma(texelFetch(colortex0, texelCoord + ivec2( 0,  1), 0).rgb);
float lumaLeft   = GetLuma(texelFetch(colortex0, texelCoord + ivec2(-1,  0), 0).rgb);
float lumaRight  = GetLuma(texelFetch(colortex0, texelCoord + ivec2( 1,  0), 0).rgb);

float lumaMin = min(lumaCenter, min(min(lumaDown, lumaUp), min(lumaLeft, lumaRight)));
float lumaMax = max(lumaCenter, max(max(lumaDown, lumaUp), max(lumaLeft, lumaRight)));
float lumaRange = lumaMax - lumaMin;

if (lumaRange < max(edgeThresholdMin, lumaMax * edgeThresholdMax)) {
#ifdef FXAA_DEBUG

float gray = lumaCenter;
gl_FragData[0] = vec4(vec3(gray) * 0.5, centerSample.a);
#else
gl_FragData[0] = centerSample;
#endif
return;
}

float lumaDownLeft  = GetLuma(texelFetch(colortex0, texelCoord + ivec2(-1, -1), 0).rgb);
float lumaUpRight   = GetLuma(texelFetch(colortex0, texelCoord + ivec2( 1,  1), 0).rgb);
float lumaUpLeft    = GetLuma(texelFetch(colortex0, texelCoord + ivec2(-1,  1), 0).rgb);
float lumaDownRight = GetLuma(texelFetch(colortex0, texelCoord + ivec2( 1, -1), 0).rgb);

float lumaDownUp    = lumaDown + lumaUp;
float lumaLeftRight = lumaLeft + lumaRight;

float lumaLeftCorners  = lumaDownLeft  + lumaUpLeft;
float lumaDownCorners  = lumaDownLeft  + lumaDownRight;
float lumaRightCorners = lumaDownRight + lumaUpRight;
float lumaUpCorners    = lumaUpRight   + lumaUpLeft;

float edgeHorizontal = abs(-2.0 * lumaLeft   + lumaLeftCorners ) +
abs(-2.0 * lumaCenter + lumaDownUp      ) * 2.0 +
abs(-2.0 * lumaRight  + lumaRightCorners);
float edgeVertical   = abs(-2.0 * lumaUp     + lumaUpCorners   ) +
abs(-2.0 * lumaCenter + lumaLeftRight   ) * 2.0 +
abs(-2.0 * lumaDown   + lumaDownCorners );

bool isHorizontal = (edgeHorizontal >= edgeVertical);

float luma1 = isHorizontal ? lumaDown : lumaLeft;
float luma2 = isHorizontal ? lumaUp : lumaRight;
float gradient1 = luma1 - lumaCenter;
float gradient2 = luma2 - lumaCenter;

bool is1Steepest = abs(gradient1) >= abs(gradient2);
float gradientScaled = 0.25 * max(abs(gradient1), abs(gradient2));

float stepLength = isHorizontal ? view.y : view.x;
float lumaLocalAverage = 0.0;

if (is1Steepest) {
stepLength = -stepLength;
lumaLocalAverage = 0.5 * (luma1 + lumaCenter);
} else {
lumaLocalAverage = 0.5 * (luma2 + lumaCenter);
}

vec2 currentUv = texcoord;
if (isHorizontal) currentUv.y += stepLength * 0.5;
else              currentUv.x += stepLength * 0.5;

vec2 offset = isHorizontal ? vec2(view.x, 0.0) : vec2(0.0, view.y);

vec2 uv1 = currentUv - offset;
vec2 uv2 = currentUv + offset;
float lumaEnd1 = GetLuma(texture2D(colortex0, uv1).rgb) - lumaLocalAverage;
float lumaEnd2 = GetLuma(texture2D(colortex0, uv2).rgb) - lumaLocalAverage;

bool reached1 = abs(lumaEnd1) >= gradientScaled;
bool reached2 = abs(lumaEnd2) >= gradientScaled;
bool reachedBoth = reached1 && reached2;

if (!reached1) uv1 -= offset;
if (!reached2) uv2 += offset;

if (!reachedBoth) {
for (int i = 2; i < iterations; i++) {
if (!reached1) {
lumaEnd1 = GetLuma(texture2D(colortex0, uv1).rgb) - lumaLocalAverage;
}
if (!reached2) {
lumaEnd2 = GetLuma(texture2D(colortex0, uv2).rgb) - lumaLocalAverage;
}
reached1 = abs(lumaEnd1) >= gradientScaled;
reached2 = abs(lumaEnd2) >= gradientScaled;
reachedBoth = reached1 && reached2;
if (!reached1) uv1 -= offset * quality[i];
if (!reached2) uv2 += offset * quality[i];
if (reachedBoth) break;
}
}

float distance1 = isHorizontal ? (texcoord.x - uv1.x) : (texcoord.y - uv1.y);
float distance2 = isHorizontal ? (uv2.x - texcoord.x) : (uv2.y - texcoord.y);

bool isDirection1 = distance1 < distance2;
float distanceFinal = min(distance1, distance2);
float edgeThickness = (distance1 + distance2);
float pixelOffset = -distanceFinal / edgeThickness + 0.5;

bool isLumaCenterSmaller = lumaCenter < lumaLocalAverage;
bool correctVariation = ((isDirection1 ? lumaEnd1 : lumaEnd2) < 0.0) != isLumaCenterSmaller;
float finalOffset = correctVariation ? pixelOffset : 0.0;

float lumaAverage = (1.0 / 12.0) * (2.0 * (lumaDownUp + lumaLeftRight) + lumaLeftCorners + lumaRightCorners);
float subPixelOffset1 = clamp(abs(lumaAverage - lumaCenter) / lumaRange, 0.0, 1.0);
float subPixelOffset2 = (-2.0 * subPixelOffset1 + 3.0) * subPixelOffset1 * subPixelOffset1;
float subPixelOffsetFinal = subPixelOffset2 * subPixelOffset2 * subpixelQuality;

finalOffset = max(finalOffset, subPixelOffsetFinal);

vec2 finalUv = texcoord;
if (isHorizontal) finalUv.y += finalOffset * stepLength;
else              finalUv.x += finalOffset * stepLength;

vec3 aaColor = texture2D(colortex0, finalUv).rgb;

#ifdef FXAA_DEBUG

float strength = clamp(finalOffset * 2.0, 0.0, 1.0);
vec3 dbgColor = mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), strength);
gl_FragData[0] = vec4(dbgColor, centerSample.a);
#else
gl_FragData[0] = vec4(aaColor, centerSample.a);
#endif
}

#else

void main() {
gl_FragData[0] = texture(colortex0, texcoord);
}

#endif
