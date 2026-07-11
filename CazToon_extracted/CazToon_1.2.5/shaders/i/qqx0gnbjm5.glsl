#ifndef VOLUMETRIC_CLOUDS_GLSL
#define VOLUMETRIC_CLOUDS_GLSL

float vcHash31(vec3 p) {
p = fract(p * vec3(0.1031, 0.1030, 0.0973));
p += dot(p, p.yzx + 33.33);
return fract((p.x + p.y) * p.z);
}

float vcHash21(vec2 p) {
p = fract(p * vec2(0.1031, 0.1030));
p += dot(p, p.yx + 33.33);
return fract((p.x + p.y) * p.x);
}

float vcNoise3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);
f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

float a = vcHash31(i);
float b = vcHash31(i + vec3(1,0,0));
float c = vcHash31(i + vec3(0,1,0));
float d = vcHash31(i + vec3(1,1,0));
float e = vcHash31(i + vec3(0,0,1));
float g = vcHash31(i + vec3(1,0,1));
float h = vcHash31(i + vec3(0,1,1));
float k = vcHash31(i + vec3(1,1,1));

return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float vcNoise2D(vec2 p) {
vec2 i = floor(p);
vec2 f = fract(p);
f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

float a = vcHash21(i);
float b = vcHash21(i + vec2(1,0));
float c = vcHash21(i + vec2(0,1));
float d = vcHash21(i + vec2(1,1));

return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float vcCloudDensity(vec3 worldPos, float time, float distFromCam) {
float y = worldPos.y;
float baseHeight = CLOUD_3D_HEIGHT + SEA_LEVEL_OFFSET;
float thick = CLOUD_3D_THICKNESS;
float cellSize = max(CLOUD_3D_CELL_SIZE, 1.0);
float cellNorm = 25.0 / cellSize;

float layerBottom = baseHeight - thick * 0.8;
float layerTop = baseHeight + thick * 2.0;
if (y < layerBottom || y > layerTop) return 0.0;

float windAngle = 1.2;
vec2 windDir = vec2(cos(windAngle), sin(windAngle));
vec2 windVel = CLOUD_3D_SPEED * windDir;
float altFracRaw = clamp((y - baseHeight) / thick, 0.0, 1.0);
vec2 windOffset = windVel * (time + 30.0 * altFracRaw * altFracRaw);

vec2 hPos = (worldPos.xz + windVel * time) * CLOUD_3D_SCALE * 0.001 * cellNorm;
float heightOffset = vcNoise2D(hPos) * thick * 1.0
+ vcNoise2D(hPos * 3.3) * thick * 0.4
- thick * 0.5;

float localBase = baseHeight + heightOffset;
float localTop = localBase + thick;
if (y < localBase || y > localTop) return 0.0;

float altFrac = (y - localBase) / thick;

float baseScale = CLOUD_3D_SCALE * 0.001 * cellNorm;
vec3 basePos = vec3(
(worldPos.x + windOffset.x) * baseScale,
worldPos.y * baseScale * 0.8,
(worldPos.z + windOffset.y) * baseScale
);

float baseHighFreqFade = 1.0 - smoothstep(4000.0, 7000.0, distFromCam);
float noise = vcNoise3D(basePos) * (0.65 + 0.35 * (1.0 - baseHighFreqFade))
+ vcNoise3D(basePos * 2.7) * 0.35 * baseHighFreqFade;

float threshold = 1.0 - CLOUD_3D_COVERAGE;
float t = clamp((noise - threshold) / 0.3, 0.0, 1.0);
float density = t * t;

if (density < 0.001) return 0.0;

float bottomClip = smoothstep(0.0, 0.12, altFrac);
float topDome = 1.0 - smoothstep(0.6, 1.0, altFrac);
density *= bottomClip * topDome;

if (density < 0.001) return 0.0;

float lodFadeSmall  = 1.0 - smoothstep(1500.0, 3000.0, distFromCam);
float lodFadeMedium = 1.0 - smoothstep(3000.0, 5000.0, distFromCam);
float lodFadeLarge  = 1.0 - smoothstep(5000.0, 8000.0, distFromCam);

vec3 wind3D = vec3(windVel * time, 0.0).xzy;

float erosion = 0.0;

if (lodFadeLarge > 0.01) {
float detail0 = vcNoise3D((worldPos + wind3D * 0.2) * 0.005);
erosion += 0.7 * detail0 * detail0 * lodFadeLarge;
}

if (lodFadeMedium > 0.01) {
float detail1 = vcNoise3D((worldPos + wind3D * 0.15) * 0.012);
erosion += 0.5 * detail1 * detail1 * lodFadeMedium;
}

if (lodFadeSmall > 0.01) {
float detail2 = vcNoise3D((worldPos + wind3D * 0.1) * 0.028);
erosion += 0.3 * detail2 * detail2 * lodFadeSmall;
}
density -= CLOUD_3D_DETAIL * erosion;
density = max(density, 0.0);

return density;
}

float vcLightOpticalDepth(vec3 origin, vec3 lightDir, float time, float distFromCam) {
const int LIGHT_STEPS = 5;
float stepLen = 10.0;
float opticalDepth = 0.0;
vec3 pos = origin;

for (int i = 0; i < LIGHT_STEPS; i++) {
pos += lightDir * stepLen;
opticalDepth += vcCloudDensity(pos, time, distFromCam) * stepLen;
stepLen *= 2.0;
}

return opticalDepth;
}

vec3 vcCloudColor(float lightOptDepth, float altFrac, float sunAngleFrac) {
float angle = fract(sunAngleFrac);

float dayAmount = smoothstep(0.04, 0.10, angle) * smoothstep(0.50, 0.46, angle);
float twilightAmount = smoothstep(0.46, 0.49, angle) * smoothstep(0.54, 0.51, angle)
+ smoothstep(0.97, 1.0, angle) + smoothstep(0.05, 0.0, angle);
float nightAmount = smoothstep(0.52, 0.58, angle) * smoothstep(0.98, 0.94, angle);

float total = max(dayAmount + twilightAmount + nightAmount, 0.001);
dayAmount /= total;
twilightAmount /= total;
nightAmount /= total;

vec3 dayLit = vec3(CLOUD_3D_R, CLOUD_3D_G, CLOUD_3D_B) * CLOUD_3D_BRIGHTNESS;
vec3 dayShadow = vec3(0.45, 0.50, 0.70) * CLOUD_3D_BRIGHTNESS;

vec3 sunsetLit = vec3(1.0, 0.85, 0.65) * CLOUD_3D_BRIGHTNESS;
vec3 sunsetShadow = vec3(0.50, 0.38, 0.48) * CLOUD_3D_BRIGHTNESS;

vec3 nightLit = vec3(0.20, 0.24, 0.38) * CLOUD_3D_BRIGHTNESS;
vec3 nightShadow = vec3(0.08, 0.09, 0.18) * CLOUD_3D_BRIGHTNESS;

vec3 litColor = dayLit * dayAmount + sunsetLit * twilightAmount + nightLit * nightAmount;
vec3 shadowColor = dayShadow * dayAmount + sunsetShadow * twilightAmount + nightShadow * nightAmount;

float sunShadow = exp(-lightOptDepth * 0.04);

sunShadow = max(sunShadow, 0.15);

float altLight = mix(0.5, 1.0, altFrac);

float lightFactor = sunShadow * altLight;

return mix(shadowColor, litColor, lightFactor);
}

vec4 renderVolumetricClouds(vec3 worldDir, float time, vec3 camPos, float sunAngle, vec3 sunDirWorld, float maxDist, vec2 fragCoord, int frame, out float outCloudDepth) {
outCloudDepth = 0.0;
vec3 dir = normalize(worldDir);

float baseHeight = CLOUD_3D_HEIGHT + SEA_LEVEL_OFFSET;
float layerBottom = baseHeight - CLOUD_3D_THICKNESS * 0.8;
float layerTop = baseHeight + CLOUD_3D_THICKNESS * 2.0;

float tMin, tMax;
if (abs(dir.y) < 0.0005) {
if (camPos.y >= layerBottom && camPos.y <= layerTop) {
tMin = 0.0; tMax = 8000.0;
} else {
return vec4(0.0);
}
} else {
float t0 = (layerBottom - camPos.y) / dir.y;
float t1 = (layerTop - camPos.y) / dir.y;
tMin = min(t0, t1);
tMax = max(t0, t1);
}

tMin = max(tMin, 0.0);
if (tMin >= tMax) return vec4(0.0);
tMax = min(tMax, maxDist);
if (tMin >= tMax) return vec4(0.0);

float cloudRenderDist = float(CLOUD_3D_DISTANCE);
float fadeStart = cloudRenderDist * 0.4;

if (tMin > cloudRenderDist * 1.2) return vec4(0.0);

float marchDist = min(tMax - tMin, 12000.0);
float stepLen = marchDist / float(CLOUD_3D_STEPS);

float dither = fract(sin(dot(fragCoord + float(frame) * 0.7183, vec2(12.9898, 78.233))) * 43758.5453);
float rayStart = tMin + stepLen * dither;

float extinctCoeff = CLOUD_3D_DENSITY * 0.015;
vec3 accColor = vec3(0.0);
float transmittance = 1.0;

for (int i = 0; i < CLOUD_3D_STEPS; i++) {
if (transmittance < 0.05) break;

float t = rayStart + stepLen * float(i);
if (t > tMax) break;

vec3 samplePos = camPos + dir * t;
float density = vcCloudDensity(samplePos, time, t);

if (density < 0.001) continue;

float horizDist = length(samplePos.xz - camPos.xz);
float distFade = 1.0 - smoothstep(fadeStart, cloudRenderDist * 0.95, horizDist);
distFade *= distFade;
density *= distFade;

if (density < 0.001) continue;

if (outCloudDepth <= 0.0) outCloudDepth = t;

float stepOptDepth = density * extinctCoeff * stepLen;
float stepTransmittance = exp(-stepOptDepth);

float lightOD = vcLightOpticalDepth(samplePos, sunDirWorld, time, t);
float altFrac = clamp((samplePos.y - baseHeight) / max(CLOUD_3D_THICKNESS, 1.0), 0.0, 1.0);
vec3 stepColor = vcCloudColor(lightOD, altFrac, sunAngle);
float edgeGlow = (1.0 - smoothstep(0.18, 0.82, density)) * CLOUD_3D_EDGE_GLOW;
stepColor += stepColor * edgeGlow * 0.35;

float weight = (1.0 - stepTransmittance) * transmittance;
accColor += stepColor * weight;

transmittance *= stepTransmittance;
}

float alpha = 1.0 - transmittance;
return vec4(accColor, alpha);
}

vec4 renderCloudReflection(vec3 worldDir, float time, vec3 camPos, float sunAngleFrac, vec3 sunDirWorld, vec2 fragCoord, int frame) {
vec3 dir = normalize(worldDir);

float baseHeight = CLOUD_3D_HEIGHT + SEA_LEVEL_OFFSET;
float layerBottom = baseHeight - CLOUD_3D_THICKNESS * 0.8;
float layerTop = baseHeight + CLOUD_3D_THICKNESS * 2.0;

float tMin, tMax;
if (abs(dir.y) < 0.0005) {
return vec4(0.0);
} else {
float t0 = (layerBottom - camPos.y) / dir.y;
float t1 = (layerTop - camPos.y) / dir.y;
tMin = min(t0, t1);
tMax = max(t0, t1);
}

tMin = max(tMin, 0.0);
if (tMin >= tMax) return vec4(0.0);
tMax = min(tMax, 30000.0);
if (tMin >= tMax) return vec4(0.0);

float cloudRenderDist = float(CLOUD_3D_DISTANCE);
if (tMin > cloudRenderDist * 1.2) return vec4(0.0);
float fadeStart = cloudRenderDist * 0.4;

const int REFL_STEPS = 16;
float marchDist = min(tMax - tMin, 12000.0);
float stepLen = marchDist / float(REFL_STEPS);

float dither = fract(sin(dot(fragCoord + float(frame) * 0.7183, vec2(12.9898, 78.233))) * 43758.5453);
float rayStart = tMin + stepLen * dither;

float extinctCoeff = CLOUD_3D_DENSITY * 0.015;
vec3 accColor = vec3(0.0);
float transmittance = 1.0;

for (int i = 0; i < REFL_STEPS; i++) {
if (transmittance < 0.1) break;

float t = rayStart + stepLen * float(i);
if (t > tMax) break;

vec3 samplePos = camPos + dir * t;
float density = vcCloudDensity(samplePos, time, t);
if (density < 0.001) continue;

float horizDist = length(samplePos.xz - camPos.xz);
float distFade = 1.0 - smoothstep(fadeStart, cloudRenderDist * 0.95, horizDist);
distFade *= distFade;
density *= distFade;
if (density < 0.001) continue;

float stepOptDepth = density * extinctCoeff * stepLen;
float stepTransmittance = exp(-stepOptDepth);

float altFrac = clamp((samplePos.y - baseHeight) / max(CLOUD_3D_THICKNESS, 1.0), 0.0, 1.0);
float approxLightOD = (1.0 - altFrac) * 8.0;
vec3 stepColor = vcCloudColor(approxLightOD, altFrac, sunAngleFrac);

float weight = (1.0 - stepTransmittance) * transmittance;
accColor += stepColor * weight;
transmittance *= stepTransmittance;
}

float alpha = 1.0 - transmittance;
return vec4(accColor, alpha);
}

#endif
