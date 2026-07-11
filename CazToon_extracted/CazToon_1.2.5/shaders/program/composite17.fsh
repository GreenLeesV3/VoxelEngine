/* RENDERTARGETS: 0 */

#include "/settings.glsl"

in vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;

uniform float viewWidth;
uniform float viewHeight;
uniform vec3 cameraPosition;

uniform int isEyeInWater;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;
uniform sampler2D dhDepthTex;
uniform float far;
uniform float dhFarPlane;
uniform float near;
uniform vec3 fogColor;
uniform float sunAngle;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex0;

#include "/include/shadow.glsl"

layout(std430, binding = 0) buffer persistentBuffer {
float storedExposure;
float smoothBeach;
float smoothSwamp;
float smoothJungle;
float smoothSnowy;
float smoothArid;
float storedScreenSkylight;
float smoothOcean;
float smoothNetherFogR;
float smoothNetherFogG;
float smoothNetherFogB;
float smoothCaveFogR;
float smoothCaveFogG;
float smoothCaveFogB;
float storedAtmoSceneFactor;
float storedCaveFogTakeover;
float smoothBiomeFogR;
float smoothBiomeFogG;
float smoothBiomeFogB;
float smoothBiomeSkyR;
float smoothBiomeSkyG;
float smoothBiomeSkyB;
float smoothPaleGarden;
};

#define SEA_LEVEL_OFFSET_DEFAULT 63
#ifndef SEA_LEVEL_OFFSET
#define SEA_LEVEL_OFFSET SEA_LEVEL_OFFSET_DEFAULT
#endif

void main() {
vec4 sceneData = texture(colortex0, texcoord);
vec3 color = sceneData.rgb;
float originalAlpha = sceneData.a;

float depthOpaque = texture(depthtex1, texcoord).r;
float depthNoHand = texture(depthtex2, texcoord).r;
float depthAll = texture(depthtex0, texcoord).r;
vec4 maskData = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0);
bool isSky = (depthOpaque >= 0.9999);

bool isHandPixel = (depthAll < depthNoHand - 0.000001) && (abs(depthAll - depthOpaque) < 0.000001);

if (isHandPixel) {
gl_FragData[0] = vec4(color, originalAlpha);
return;
}

bool isUnderwaterSurface = false;

bool entityInFront = !isHandPixel && (maskData.a > 0.01 && maskData.a < 0.99);

vec4 waterData = texelFetch(colortex5, ivec2(gl_FragCoord.xy), 0);
vec4 glassTintC17 = texelFetch(colortex4, ivec2(gl_FragCoord.xy), 0);
bool isGlassC17 = (glassTintC17.a > 0.45);
bool particleOverSky = isSky && (depthAll < 0.9999) && (waterData.y < 0.5) && !isGlassC17;
if (isEyeInWater != 1) {

vec2 cloudUV = texcoord;
bool isWaterSide = (waterData.y > 0.9) && (waterData.w * 2.0 - 1.0 < 0.5);
if (isWaterSide) {
float sideNoise = waterData.x;
vec2 refrOffset = vec2((sideNoise - 0.5) * 0.8, (sideNoise - 0.5) * 1.2);
float refrPx = 14.0 / max(viewWidth, 1.0);
cloudUV += refrOffset * refrPx;
cloudUV = clamp(cloudUV, vec2(0.0), vec2(1.0));
}
vec4 cloudData = texture(colortex8, cloudUV);

cloudData.a *= 1.0 - smoothSwamp;
cloudData.rgb *= 1.0 - smoothSwamp;
if (cloudData.a > 0.001 && !entityInFront && !particleOverSky) {
color = color * (1.0 - cloudData.a) + cloudData.rgb;
}
}

#if defined(ATMO_FOG_ENABLED) || defined(UNDERWATER_FOG_ENABLED)
if (isEyeInWater != 1) {
vec4 atmoFog = max(texture(colortex9, texcoord), vec4(0.0));
if (atmoFog.a > 0.001) {
color = atmoFog.rgb + color * (1.0 - atmoFog.a);
}
}
#endif

#if defined(ATMO_FOG_ENABLED) || defined(UNDERWATER_FOG_ENABLED)
if (isEyeInWater == 1) {
vec4 atmoFog = max(texture(colortex9, texcoord), vec4(0.0));
if (atmoFog.a > 0.001) {
float uwEmissive = texture(colortex1, texcoord).g;

float emissiveBypass = uwEmissive * 0.5 * (1.0 - smoothstep(0.3, 0.6, atmoFog.a));
float uwFogAlpha = atmoFog.a * (1.0 - emissiveBypass);
color = atmoFog.rgb * (uwFogAlpha / max(atmoFog.a, 0.001)) + color * (1.0 - uwFogAlpha);
}
}
#endif

#ifdef UNDERWATER_FOG_ENABLED
if (isEyeInWater == 1) {
float uwEmissiveBoost = texture(colortex1, texcoord).g;
if (uwEmissiveBoost > 0.01) {
vec4 uwFogCheck = max(texture(colortex9, texcoord), vec4(0.0));
float uwFogTrans = 1.0 - uwFogCheck.a;
color *= 1.0 + uwEmissiveBoost * 3.5 * uwFogTrans;
}
}
#endif

#ifdef UNDERWATER_FOG_ENABLED
if (isEyeInWater == 1) {
vec4 cloudData = texture(colortex8, texcoord);

float uwDepthBelow = float(SEA_LEVEL_OFFSET) - cameraPosition.y;
float uwBandFade = smoothstep(0.5, 6.0, uwDepthBelow);
cloudData.a *= (1.0 - uwBandFade);
cloudData.rgb *= (1.0 - uwBandFade);
if (cloudData.a > 0.001 && !entityInFront && !particleOverSky) {

color += cloudData.rgb * cloudData.a;
}
}
#endif

gl_FragData[0] = vec4(color, originalAlpha);
}
