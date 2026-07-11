/* RENDERTARGETS: 7,1,2,3,4,5 */

#include "/settings.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/shadow.glsl"
#include "/include/hovering.glsl"
#include "/include/water_color.glsl"
#include "/include/ocean_waves.glsl"

uniform sampler2D gtexture;
uniform sampler2D shadowtex0;
#ifdef PBR_ENABLED
uniform sampler2D normals;
uniform sampler2D specular;
#endif
uniform sampler2D depthtex1;
uniform mat4 gbufferProjectionInverse;
uniform float near;
uniform float far;
uniform float alphaTestRef;
uniform vec3 fogColor;
uniform int biome_category;
uniform float fogStart;
uniform float fogEnd;
uniform float sunAngle;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float biome_swamp;
uniform int isEyeInWater;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;

#include "/include/lighting.glsl"
#ifdef PBR_ENABLED
#include "/include/pbr.glsl"
#endif
uniform float frameTimeCounter;
uniform float biome_snowy;
uniform float biome_jungle;
uniform float biome_arid;
uniform float biome_savanna;
uniform float biome_beach;
uniform float biome_ocean;

in vec2 texcoord;
in vec4 glcolor;
in float viewDistance;
in float postMask;
in float isWater;
in float isHologram;
in vec3 worldPos;
in vec3 viewPos;
in vec3 normal;
in float skylight;
in float blocklight;
in vec3 waveNormal;
in float waveHeight;
in vec4 shadowPos;
flat in float isIce;
flat in float isHeatSource;
flat in int blockId;
in float waterBlockFracY;
in float waterFlowFlag;
#ifdef PBR_ENABLED
in vec3 tangentVec;
in vec3 binormalVec;
#endif

#include "/include/fog_color.glsl"

float random(float x) {
return fract(sin(x * 12.9898) * 43758.5453);
}

#include "/include/noise.glsl"

float detectGlass(vec3 color) {
float brightness = max(max(color.r, color.g), color.b);
float minC = min(min(color.r, color.g), color.b);
float saturation = brightness > 0.01 ? (brightness - minC) / brightness : 0.0;

bool isWaterLike = (color.b > color.r * 1.2) && (color.b > 0.25) && (saturation > 0.3);
if (isWaterLike) return 0.0;

bool isIceLike = (color.b > color.r) && (brightness > 0.6) && (saturation < 0.4);
if (isIceLike) return 0.0;

return 1.0;
}

void main() {
vec4 tex = texture(gtexture, texcoord);
vec4 color = tex * glcolor;
if (color.a < alphaTestRef) {
discard;
}

if (!isForcedNetherBiome(biome) && !isForcedEndBiome(biome) && isEyeInWater != 1) {
#ifdef CHUNK_FADE_OUT_ENABLED
#ifndef DISTANT_HORIZONS
float horizontalDist = length(worldPos.xz - cameraPosition.xz);
float distGate = smoothstep(CHUNK_FADE_OUT_RADIUS, CHUNK_FADE_OUT_RADIUS + 24.0, horizontalDist);
if (distGate > 0.001) {
float reveal = 1.0 - distGate;
float minY = SEA_LEVEL_OFFSET - 96.0;
float maxY = SEA_LEVEL_OFFSET + 320.0;
float mask = smoothChunkNoise(worldPos.xz * 0.12);
float jitterY = (mask - 0.5) * 10.0;
float revealY = mix(minY, maxY, reveal) + jitterY;
float visible = 1.0 - smoothstep(revealY - 8.0, revealY + 8.0, worldPos.y);
color.a *= visible;
if (color.a < 0.01) {
discard;
}
}
#endif
#endif
}

vec3 rawColor = color.rgb;
#ifdef LPV_ENABLED
lpvSurfaceColor = rawColor;
lpvTexLuma = dot(rawColor, vec3(0.299, 0.587, 0.114));
#endif
float emissive = 0.0;
vec3 lightColor = vec3(0.0);
vec3 waterTint = vec3(0.0);

float portalNormalFlag = 0.0;
if (blockId == 88 || blockId == 63) {
emissive = 1.0;
color.a = 1.0;
if (blockId == 88) {
float portalLuma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
float portalBrightMask = smoothstep(0.10, 0.70, portalLuma);
float portalGain = mix(0.55, 1.95, portalBrightMask * portalBrightMask);
color.rgb *= EMISSIVE_BRIGHTNESS * 2.5 * portalGain;
} else {
color.rgb *= EMISSIVE_BRIGHTNESS;
}

vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
portalNormalFlag = 100.0 / 255.0;
if (abs(worldNormal.x) > 0.5) portalNormalFlag = 150.0 / 255.0;
else if (abs(worldNormal.z) > 0.5) portalNormalFlag = 200.0 / 255.0;
}
bool isBackFace = !gl_FrontFacing;

float shadow = 1.0;
#ifdef SHADOWS_ENABLED
if (skylight > 0.1) {
#if defined(SHARP_SHADOWS) || defined(MAGICAL_TOUCH)
float mapDepth = texture(shadowtex0, shadowPos.xy).r;
shadow = step(shadowPos.z, mapDepth);
float shadowCoverageFade = 1.0 - shadowDistanceFade(shadowPos.xyz, viewDistance);
shadow = mix(1.0, shadow, shadowEdgeFade(shadowPos.xyz) * shadowCoverageFade);
#else
float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
float r = quartic_length(shadowPos.xy * 2.0 - 1.0);
float distortFactor = r + SHADOW_DISTORTION;
shadow = getShadowFaded(shadowtex0, shadowPos.xyz, distortFactor, viewDistance, dither);
#endif

shadow = mix(1.0, shadow, skylight);
shadow = mix(1.0, shadow, SHADOW_OPACITY);

float grazeBlend = smoothstep(0.15, 0.0, shadowPos.w);
shadow = mix(shadow, 0.0, grazeBlend);
}
#endif

float bl_water = blocklight;
vec4 waterReflData = vec4(0.0);
float waterfallFoam = 0.0;
float texFoam = 0.0;
float waterTextureSpec = 0.0;
bool isSideFace = false;

if (isWater > 0.5) {
vec3 waterWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);

if (isEyeInWater == 1) {

float waterSurfaceDist = abs(worldPos.y - float(SEA_LEVEL_OFFSET));
if (waterSurfaceDist < 1.5) {
discard;
}
if (isBackFace) {
if (waterWorldNormal.y > 0.5) {
#include "/include/water/water_inside_ceiling.glsl"
} else if (waterWorldNormal.y < -0.5) {
#include "/include/water/water_inside_floor.glsl"
} else {
#include "/include/water/water_inside_walls.glsl"
}
} else {
#include "/include/water/water_inside_front.glsl"
}
} else {

if (biome_beach > 0.01 && biome_beach >= biome_ocean
&& waterWorldNormal.y < 0.5 && waterWorldNormal.y > -0.5
&& worldPos.y > float(SEA_LEVEL_OFFSET) - 1.0 && worldPos.y < float(SEA_LEVEL_OFFSET) + 1.0) {
discard;
}

if (isBackFace) {
#include "/include/water/water_outside_back.glsl"
} else {
if (waterWorldNormal.y > 0.5) {
#include "/include/water/water_outside_top.glsl"
} else {
#include "/include/water/water_outside_sides.glsl"
isSideFace = true;
}
}

}

float flowOpacity = smoothstep(0.0, 0.8, waterBlockFracY);
color.a = WATER_OPACITY;

if (biome_swamp > 0.01 && isEyeInWater != 1 && waterWorldNormal.y > 0.5) {
float st = frameTimeCounter * 0.3;

vec2 mudPixPos = floor(worldPos.xz * 16.0) / 16.0;

float warpA = smoothChunkNoise(mudPixPos * 0.15 + vec2(st * 0.08, -st * 0.06));
float warpB = smoothChunkNoise(mudPixPos * 0.15 + vec2(-st * 0.07, st * 0.09) + vec2(13.5, -8.2));
vec2 mudWarp = (vec2(warpA, warpB) - 0.5) * 1.8;
vec2 warpedPos = mudPixPos + mudWarp;
float mudA = smoothChunkNoise(warpedPos * 0.35 + vec2(st * 0.10, -st * 0.08));
float mudB = smoothChunkNoise(warpedPos * 0.7 + vec2(-st * 0.12, st * 0.11) + vec2(7.3, -4.1));
float mudC = smoothChunkNoise(warpedPos * 1.4 + vec2(st * 0.06, st * 0.14) + vec2(-3.5, 9.2));
float mudField = mudA * 0.5 + mudB * 0.35 + mudC * 0.15;
float mud = smoothstep(0.35, 0.80, mudField);

float mudDist = length(worldPos.xz - cameraPosition.xz);
float mudDistFade = 1.0 - smoothstep(40.0, 80.0, mudDist);
mud *= mudDistFade;

float encodedMud = mix(0.5, 1.0, mud * biome_swamp);
waterReflData.x = max(waterReflData.x, encodedMud);
}

float waveBiome = max(biome_beach, biome_ocean);

float beachDistFade = 1.0 - smoothstep(WATER_BLUR_START, WATER_BLUR_END, length(worldPos.xz - cameraPosition.xz));
float foamDistFade = (biome_beach >= biome_ocean) ? beachDistFade : 1.0;

#define FWAVE_RAW(f) (smoothstep(0.15, 0.25, f) * (1.0 - pow(smoothstep(0.25, 1.15, f), 0.45)))
#define FWAVE(px) FWAVE_RAW(1.0 - fract(px))

#define FOWAVE(px) (pow(0.5 + 0.5 * sin((fract(px) - 0.25) * 6.2832), 1.6))
#define FSMAX(a, b, k) (max(a, b) + pow(max(k - abs(a - b), 0.0) / k, 3.0) * k * 0.166667)

#ifdef WATER_FOAM_ENABLED
if (biome_beach > 0.01 && biome_beach >= biome_ocean
&& worldPos.y > float(SEA_LEVEL_OFFSET) - 1.0 && worldPos.y < float(SEA_LEVEL_OFFSET) + 1.0) {
float ft = frameTimeCounter * WATER_WAVE_SPEED;
float fwx = worldPos.x * WATER_WAVE_SCALE;
float fwz = worldPos.z * WATER_WAVE_SCALE;

float fzOff1 = sin(fwz * 0.21 + 3.7) * 2.5 + sin(fwz * 0.53 + 1.2) * 1.3;
float fzOff2 = sin(fwz * 0.37 + 5.1) * 1.8 + sin(fwz * 0.71 + 2.8) * 1.1;
float fzOff3 = sin(fwz * 0.62 + 0.9) * 1.2 + sin(fwz * 0.89 + 4.3) * 0.8;

float fw1 = FWAVE((fwx * 0.8 + fzOff1 - ft) / 6.2832);
float fw2 = FWAVE((fwx * 1.8 + fzOff2 - ft * 1.6) / 6.2832);
float pixelWaveH = clamp(FSMAX(fw1, fw2 * 0.55, 0.15), 0.0, 1.0);
pixelWaveH += FWAVE((fwx * 4.0 + fzOff3 - ft * 2.2) / 6.2832) * 0.15 * pixelWaveH;

float fchop = sin(fwx * 4.5 + fwz * 1.2 - ft * 3.0) * 0.08
+ sin(fwx * 7.0 - fwz * 2.3 + ft * 4.5) * 0.05
+ sin(fwx * 2.8 + fwz * 5.5 + ft * 2.2) * 0.06
+ sin(fwx * 11.0 + fwz * 3.8 - ft * 5.5) * 0.03
+ sin(fwx * 5.5 - fwz * 8.0 + ft * 3.8) * 0.04;
pixelWaveH = clamp(pixelWaveH + fchop * pixelWaveH, 0.0, 1.0);

waterReflData.x = mix(0.5, pixelWaveH, biome_beach) + texFoam;

float wEps = 0.15;
float fwxE = (worldPos.x + wEps) * WATER_WAVE_SCALE;
float pixelWaveHx = clamp(FSMAX(FWAVE((fwxE * 0.8 + fzOff1 - ft) / 6.2832), FWAVE((fwxE * 1.8 + fzOff2 - ft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
pixelWaveHx += FWAVE((fwxE * 4.0 + fzOff3 - ft * 2.2) / 6.2832) * 0.15 * pixelWaveHx;
float fwzE = (worldPos.z + wEps) * WATER_WAVE_SCALE;
float fzOff1E = sin(fwzE * 0.21 + 3.7) * 2.5 + sin(fwzE * 0.53 + 1.2) * 1.3;
float fzOff2E = sin(fwzE * 0.37 + 5.1) * 1.8 + sin(fwzE * 0.71 + 2.8) * 1.1;
float fzOff3E = sin(fwzE * 0.62 + 0.9) * 1.2 + sin(fwzE * 0.89 + 4.3) * 0.8;
float pixelWaveHz = clamp(FSMAX(FWAVE((fwx * 0.8 + fzOff1E - ft) / 6.2832), FWAVE((fwx * 1.8 + fzOff2E - ft * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
pixelWaveHz += FWAVE((fwx * 4.0 + fzOff3E - ft * 2.2) / 6.2832) * 0.15 * pixelWaveHz;
float slopeX = (pixelWaveHx - pixelWaveH) / wEps;
float slopeZ = (pixelWaveHz - pixelWaveH) / wEps;
float slopeAbs = length(vec2(slopeX, slopeZ));
float frontFace = smoothstep(0.0, 0.28, slopeX);
float backFace = smoothstep(0.0, 0.28, -slopeX);

float crestFoam = smoothstep(0.84, 0.97, pixelWaveH);
float crestN1 = smoothChunkNoise(worldPos.xz * 2.2 + vec2(-ft * 0.9, ft * 0.5));
float crestN2 = smoothChunkNoise(worldPos.xz * 3.9 + vec2(ft * 1.3, -ft * 0.8) + vec2(5.7, -3.1));
crestFoam = smoothstep(0.10, 0.66, crestFoam + crestFoam * pow(clamp(crestN1 * 0.70 + crestN2 * 0.30, 0.0, 1.0), 3.6) * 0.38);

float tipZone = smoothstep(0.74, 0.92, pixelWaveH) * (1.0 - smoothstep(0.96, 0.995, pixelWaveH));
vec2 tipUV = worldPos.xz * vec2(3.8, 3.2) + vec2(-ft * 1.8, ft * 1.2);
float tipBurst = pow(clamp(smoothChunkNoise(tipUV + vec2(2.7, -1.9)) * 0.65 + smoothChunkNoise(tipUV * 1.7 + vec2(-5.4, 4.1)) * 0.35, 0.0, 1.0), 4.6);
crestFoam = max(crestFoam, tipBurst * tipZone * smoothstep(0.18, 0.95, slopeAbs) * mix(0.65, 1.0, frontFace) * 0.55);

float trailMask = smoothstep(0.08, 0.76, pixelWaveH) * (1.0 - smoothstep(0.90, 0.98, pixelWaveH));
vec2 flowDir = normalize(vec2(1.0, 0.24));
vec2 crossDir = vec2(-flowDir.y, flowDir.x);
vec2 flowUV = vec2(dot(worldPos.xz, flowDir), dot(worldPos.xz, crossDir)) + vec2(-ft * 0.55, ft * 0.10);
float warpA = smoothChunkNoise(flowUV * 0.28 + vec2(0.0, ft * 0.03));
float warpB = smoothChunkNoise(flowUV * 0.46 + vec2(13.7, -8.4) + vec2(-ft * 0.04, ft * 0.02));
vec2 warpedUV = flowUV + vec2((warpA - 0.5) * 0.9, (warpB - 0.5) * 0.6);
float nA = smoothChunkNoise(warpedUV * 0.72);
float nB = smoothChunkNoise(warpedUV * 1.25 + vec2(4.6, -2.9));
float nC = smoothChunkNoise(warpedUV * 2.10 + vec2(-7.1, 3.8));
float veinField = pow(clamp((1.0 - abs(nA * 2.0 - 1.0)) * 0.62 + (1.0 - abs(nB * 2.0 - 1.0)) * 0.30 + (1.0 - abs(nC * 2.0 - 1.0)) * 0.08, 0.0, 1.0), 1.85);
veinField *= smoothstep(0.36, 0.74, nA + nB * 0.38);
float heightSpike = pow(max(nB - 0.70, 0.0) * 3.3, 2.4) * mix(0.0002, 0.0020, smoothstep(0.45, 0.92, pixelWaveH));
float trailFoam = veinField * trailMask * mix(0.42, 1.0, backFace) * mix(0.70, 1.05, smoothstep(0.26, 0.88, clamp(pixelWaveH + heightSpike, 0.0, 1.0)));
float bigFoam = max(crestFoam, trailFoam);

float sm2 = fw2;
float sm2Hx = FWAVE((fwxE * 1.8 + fzOff2 - ft * 1.6) / 6.2832);
float sm2Hz = FWAVE((fwx * 1.8 + fzOff2E - ft * 1.6) / 6.2832);
float sm2SlopeMag = length(vec2(sm2Hx - sm2, sm2Hz - sm2)) / wEps;
float sm2BackFace = smoothstep(0.0, 0.24, -(sm2Hx - sm2) / wEps);
float smallFoam = max(smoothstep(0.56, 0.82, sm2) * (1.0 - smoothstep(0.88, 0.98, sm2)) * 0.65,
smoothstep(0.24, 0.54, sm2) * (1.0 - smoothstep(0.70, 0.92, sm2)) * sm2BackFace * 0.80);
smallFoam *= smoothstep(0.04, 0.20, sm2SlopeMag);
float sm2NoiseA = smoothChunkNoise(worldPos.xz * 1.25 + vec2(-ft * 0.55, ft * 0.25));
float sm2NoiseB = smoothChunkNoise(worldPos.xz * 2.10 + vec2(ft * 0.90, -ft * 0.60) + vec2(6.1, -2.3));
smallFoam *= smoothstep(0.40, 0.86, sm2NoiseA * 0.72 + sm2NoiseB * 0.28) * (1.0 - smoothstep(0.83, 0.96, pixelWaveH)) * 0.72;

float foam = max(bigFoam, smallFoam) * biome_beach * foamDistFade;

waterReflData.x += foam;
}

#endif
#undef FWAVE
#undef FWAVE_RAW
#undef FOWAVE
#undef FSMAX

#ifdef WATER_FOAM_ENABLED
if (isEyeInWater != 1 && waterWorldNormal.y > 0.5) {
vec2 screenUV = gl_FragCoord.xy / textureSize(depthtex1, 0);
float terrainDepthRaw = texture(depthtex1, screenUV).r;

vec4 terrainClip = vec4(screenUV * 2.0 - 1.0, terrainDepthRaw * 2.0 - 1.0, 1.0);
vec4 terrainView = gbufferProjectionInverse * terrainClip;
terrainView /= terrainView.w;
vec3 terrainWorldPos = (gbufferModelViewInverse * terrainView).xyz + cameraPosition;

float waterDepth = worldPos.y - terrainWorldPos.y;

float edgeFoam = 1.0 - smoothstep(0.0, 0.6, waterDepth);
edgeFoam *= edgeFoam;

edgeFoam *= step(0.0, waterDepth) * step(terrainDepthRaw, 0.9999);

float eft = frameTimeCounter;
float efn1 = smoothChunkNoise(worldPos.xz * 2.5 + vec2(eft * 0.8, -eft * 0.6));
float efn2 = smoothChunkNoise(worldPos.xz * 5.0 + vec2(-eft * 1.2, eft * 0.9) + vec2(7.3, -4.1));
float edgePattern = efn1 * 0.6 + efn2 * 0.4;
edgePattern = smoothstep(0.35, 0.55, edgePattern);
edgeFoam *= edgePattern;

edgeFoam *= foamDistFade;

waterReflData.x += edgeFoam * WATER_FOAM_INTENSITY * 0.15;
}
#endif

#ifdef WATER_PLAYER_FOAM_ENABLED
if (isEyeInWater != 1 && waterWorldNormal.y > 0.5) {
vec3 playerFeet = eyePosition - vec3(0.0, 1.62, 0.0);
vec2 toPlayer = worldPos.xz - playerFeet.xz;
float playerDist = length(toPlayer);
float pft = frameTimeCounter;

float verticalProximity = 1.0 - smoothstep(0.0, 1.0, abs(worldPos.y - playerFeet.y));

float radius = WATER_PLAYER_FOAM_RADIUS;
float foamMask = 1.0 - smoothstep(radius * 0.3, radius, playerDist);

float pfn1 = smoothChunkNoise(worldPos.xz * 6.0 + vec2(pft * 2.5, -pft * 1.8));
float pfn2 = smoothChunkNoise(worldPos.xz * 10.0 + vec2(-pft * 3.0, pft * 2.2) + vec2(3.7, -2.1));
float churn = pfn1 * 0.55 + pfn2 * 0.45;
churn = smoothstep(0.25, 0.55, churn);

float angle = atan(toPlayer.y, toPlayer.x);
float edgePulse = sin(angle * 5.0 + pft * 4.0) * 0.3
+ sin(angle * 8.0 - pft * 6.0) * 0.2;
foamMask *= smoothstep(-0.1, 0.2, foamMask + edgePulse * 0.3);

float playerFoam = foamMask * churn * verticalProximity * WATER_PLAYER_FOAM_INTENSITY * foamDistFade;

waterReflData.x += playerFoam * 0.12;
}
#endif

#ifdef WATER_WAVES_ENABLED
if (waterWorldNormal.y > 0.5 && waterReflData.y < 0.5) {
waterReflData.x = 0.5;
waterReflData.y = 1.0;
waterReflData.z = 0.5;
waterReflData.w = 1.0;
}
#endif

if (waterReflData.y < 0.5 && waterWorldNormal.y > 0.5) {
waterReflData.y = 1.0;
waterReflData.z = waterWorldNormal.x * 0.5 + 0.5;
waterReflData.w = waterWorldNormal.y * 0.5 + 0.5;
}

#ifdef WATER_FOAM_ENABLED
if (isEyeInWater != 1 && waterWorldNormal.y > 0.5 && biome_beach < 0.99) {
float aft = frameTimeCounter;
vec2 pixPos = floor(worldPos.xz * 16.0) / 16.0;

float ct = aft * WATER_WAVE_SPEED * 0.2;
vec3 cPos3D = vec3(pixPos.x, 0.0, pixPos.y) * 0.35;

float cA = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = cPos3D;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
cA += abs(noise3D(p * freq + ct * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
cA = 1.0 - cA / total;
}
float cB = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = cPos3D + 5.0;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
cB += abs(noise3D(p * freq + ct * 1.15 * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
cB = 1.0 - cB / total;
}
float caustic = min(cA, cB);
caustic = pow(caustic, 2.0) * 2.5;
caustic = max(caustic - 0.15, 0.0) * (1.0 / 0.85);

float cycle = 12.0;
float patchRadius = 2.5;
float gridScale = 0.07;
vec2 gridPos = worldPos.xz * gridScale;
vec2 cellBase = floor(gridPos);

float ambientFoam = 0.0;

for (int gx = -1; gx <= 1; gx++) {
for (int gy = -1; gy <= 1; gy++) {
vec2 cell = cellBase + vec2(float(gx), float(gy));

float h1 = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
float h2 = fract(sin(dot(cell, vec2(269.5, 183.3))) * 43758.5453);
float h3 = fract(sin(dot(cell, vec2(419.2, 371.9))) * 43758.5453);

float cellCycleId = floor((aft + h1 * cycle) / cycle);
float h4 = fract(sin(dot(vec2(cellCycleId, h1 * 100.0), vec2(127.1, 311.7))) * 43758.5453);
float h5 = fract(sin(dot(vec2(cellCycleId, h2 * 100.0), vec2(269.5, 183.3))) * 43758.5453);

float patchPhaseRaw = mod(aft + h1 * cycle, cycle) / cycle;
vec2 drift = vec2(h3 - 0.5, h1 - 0.5) * patchPhaseRaw * 0.5;
vec2 center = cell + vec2(0.2 + h4 * 0.6, 0.2 + h5 * 0.6) + drift;

vec2 delta = gridPos - center;

float angle = atan(delta.y, delta.x);
float deform = 1.0 + 0.2 * sin(angle * 3.0 + h3 * 6.28)
+ 0.1 * sin(angle * 5.0 + h1 * 6.28);
float dist = length(delta) * deform;

float patchPhase = mod(aft + h1 * cycle, cycle) / cycle;

float maxRadius = 0.45;
float outerRadius = smoothstep(0.0, 0.4, patchPhase) * maxRadius;
float innerRadius = smoothstep(0.3, 0.95, patchPhase) * maxRadius * 1.3;

float outerMask = 1.0 - smoothstep(outerRadius * 0.4, outerRadius, dist);
float innerMask = smoothstep(innerRadius * 0.3, innerRadius, dist);
float patchShape = outerMask * innerMask;

float cellActive = step(0.4, h2);

ambientFoam = max(ambientFoam, caustic * patchShape * cellActive);
}
}
ambientFoam *= 0.10 * (1.0 - biome_beach);

float afDist = length(worldPos.xz - cameraPosition.xz);
float afDistFade = 1.0 - smoothstep(24.0, 60.0, afDist);

waterReflData.x += ambientFoam * afDistFade;
}
#endif

}

if (isWater < 0.5 && emissive < 0.5) {
#ifdef LPV_ENABLED
lpvWorldPos = worldPos;
lpvWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
#endif
color.rgb = applyLightingWithShadow(color.rgb, sunAngle, skylight, bl_water, 0.0, shadow, worldPos.y);

#ifdef PBR_ENABLED
{
vec4 normalData = texture(normals, texcoord);
vec4 specData   = texture(specular, texcoord);
PBRMaterial pm = pbr_decode(normalData, specData, color.rgb, PBR_NORMAL_STRENGTH);
if (pm.hasSpec && pm.roughness < 0.999) {
vec3 N  = pbr_tangentToView(pm.nTangent, tangentVec, binormalVec, normal);
vec3 L  = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 Nw = normalize(mat3(gbufferModelViewInverse) * N);
vec3 Vw = normalize(cameraPosition - worldPos);
vec3 Hw = normalize(Vw + L);
float NdotL = max(dot(Nw, L),  0.0);
float NdotH = max(dot(Nw, Hw), 0.0);
float NdotV = max(dot(Nw, Vw), 1e-3);
float grazeSoft = smoothstep(0.02, 0.15, NdotV);
float r = clamp(pm.roughness, 0.5, 1.0);
float shininess = mix(32.0, 4.0, r);
float specPow = pow(NdotH, shininess);
float norm = (shininess + 2.0) / (2.0 * 3.14159265);
vec3  F = pbr_fresnelSchlickColor(NdotV, pm.F0);
vec3 spec = specPow * norm * F * NdotL;
vec3 ambientSpec = pm.F0 * (1.0 - r) * 0.15 * skylight * grazeSoft;
float sunFrac = fract(sunAngle);
float dayFactor = smoothstep(0.00, 0.15, sunFrac) * smoothstep(0.55, 0.40, sunFrac);
color.rgb += spec * grazeSoft * PBR_SPECULAR_STRENGTH * shadow * skylight * dayFactor + ambientSpec;
}
}
#endif
}

#ifdef HANDHELD_LIGHT_ENABLED
if (emissive < 0.5) color.rgb += getHandheldLightBoost(worldPos, rawColor, color.rgb);
#endif

if (emissive < 0.5) {
float denom = max(fogEnd - fogStart, 0.0001);
float fogFactor = clamp((fogEnd - viewDistance) / denom, 0.0, 1.0);
if (isEyeInWater == 1) {
vec3 uwFogCol = fogColor;
color.rgb = mix(uwFogCol, color.rgb, fogFactor);
}
}

if (isWater < 0.5) {
color.a *= 0.65;
}

if (isWater > 0.5) {

float swAngle = fract(sunAngle);
float swNight = 1.0 - smoothstep(0.02, 0.08, swAngle) * (1.0 - smoothstep(0.44, 0.52, swAngle));
color.a = mix(color.a, 1.0, biome_swamp * swNight);
}
gl_FragData[0] = color;

float maskA = (portalNormalFlag > 0.0) ? portalNormalFlag : isHeatSource;
gl_FragData[1] = vec4(postMask, emissive, skylight, maskA);
gl_FragData[2] = vec4(lightColor, 1.0);
gl_FragData[3] = vec4(lightColor, 1.0);

if (isWater > 0.5) {
vec3 biomeRaw = biomeWaterColor(sunAngle, 1.0, biome_swamp, 0.0, 0.0, 0.0);

biomeRaw.b = waterTextureSpec;

biomeRaw.r = mix(biomeRaw.r, texFoam * 2.0, biome_swamp);
gl_FragData[4] = vec4(biomeRaw, 0.3);
} else if (isIce > 0.5) {

vec4 rawTex = texture(gtexture, texcoord);
gl_FragData[4] = vec4(rawTex.rgb, 0.8);
} else {

vec4 rawTex = texture(gtexture, texcoord) * glcolor;
gl_FragData[4] = vec4(rawTex.rgb, 0.6);
}

if (isIce > 0.5 && isWater < 0.5) {
vec3 iceWorldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
vec3 iceEncodedNormal = iceWorldNormal * 0.5 + 0.5;
float iceLmPacked = dot(floor(255.0 * vec2(bl_water, skylight) + 0.5), vec2(1.0 / 65535.0, 256.0 / 65535.0));
float iceReflPacked = dot(floor(255.0 * vec2(0.5, 0.0) + 0.5), vec2(1.0 / 65535.0, 256.0 / 65535.0));
waterReflData = vec4(iceLmPacked, iceReflPacked, iceEncodedNormal.x, iceEncodedNormal.y);
}
gl_FragData[5] = waterReflData;
}
