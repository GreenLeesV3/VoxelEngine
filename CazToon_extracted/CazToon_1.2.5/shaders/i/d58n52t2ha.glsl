#ifndef VANILLA_CLOUDS_GLSL
#define VANILLA_CLOUDS_GLSL

uniform sampler2D cloudTex;

vec2 vanillaRoundedCoord(vec2 pos, float roundness) {
vec2 coord = pos + 0.5;
vec2 signCoord = sign(coord);
coord = abs(coord) + 1.0;
vec2 i, f = modf(coord, i);
f = smoothstep(0.5 - roundness, 0.5 + roundness, f);
coord = i + f;
return (coord - 0.5) * signCoord / 256.0;
}

vec2 vanillaWindOffset(float time) {
return vec2(1.0, 0.0) * float(VANILLA_CLOUD_SPEED) * time;
}

vec2 vanillaCloudTraceBias(vec2 dirXZ, float cellSize) {
vec2 dirSign = vec2(
dirXZ.x > 0.0 ? 1.0 : (dirXZ.x < 0.0 ? -1.0 : 0.0),
dirXZ.y > 0.0 ? 1.0 : (dirXZ.y < 0.0 ? -1.0 : 0.0)
);

vec2 fallbackSign = mix(vec2(-1.0), dirSign, step(vec2(0.5), abs(dirSign)));
return fallbackSign * (cellSize * 0.0005);
}

float vanillaCloudMap(vec2 worldXZ, float time, float coverage, float narrowness, int layerIdx) {
vec2 moved = worldXZ + vanillaWindOffset(time);

vec2 modCoord = moved;
if (layerIdx == 2) {
modCoord = vec2(moved.y, -moved.x);
} else if (layerIdx == 3) {
modCoord = vec2(-moved.x, -moved.y);
}

vec2 texPos = modCoord * narrowness;
vec2 uv = vanillaRoundedCoord(texPos, 0.125);

vec2 wrappedUV = fract(uv);
vec4 texel = texture(cloudTex, wrappedUV);

float field = texel.b * 0.72 + texel.r * 0.28;

float cutoff = mix(0.78, 0.16, clamp(coverage, 0.0, 1.0));
return smoothstep(cutoff - 0.08, cutoff + 0.08, field);
}

void vanillaTimeOfDay(float sunAngle, out float dayAmt, out float twlAmt, out float nightAmt) {
float ang = fract(sunAngle);
dayAmt = smoothstep(0.04, 0.10, ang) * smoothstep(0.50, 0.46, ang);
twlAmt = smoothstep(0.46, 0.49, ang) * smoothstep(0.54, 0.51, ang)
+ smoothstep(0.97, 1.0, ang) + smoothstep(0.05, 0.0, ang);
nightAmt = smoothstep(0.52, 0.58, ang) * smoothstep(0.98, 0.94, ang);
float tot = max(dayAmt + twlAmt + nightAmt, 0.001);
dayAmt /= tot; twlAmt /= tot; nightAmt /= tot;
}

vec3 vanillaCloudColor(float dayAmt, float twlAmt, float nightAmt, float shadeType, float layerDarknessMultiplier) {

vec3 baseCol = vec3(float(VANILLA_CLOUD_R), float(VANILLA_CLOUD_G), float(VANILLA_CLOUD_B)) * float(VANILLA_CLOUD_BRIGHTNESS) * layerDarknessMultiplier;

vec3 dayLit    = baseCol;
vec3 dayShadow = baseCol * vec3(0.60, 0.65, 0.90);
float wSavanna = getSavannaWeightWithoutSwamp(biome_savanna, biome_swamp);
if (wSavanna > 0.001) {
vec3 savannaLit = baseCol * mix(vec3(1.0), getSavannaSkyHorizonColor(), 0.35);
vec3 savannaShadow = baseCol * mix(getSavannaSkyZenithColor(), getSavannaSkyHorizonColor(), 0.35) * 0.70;
dayLit = mix(dayLit, savannaLit, wSavanna);
dayShadow = mix(dayShadow, savannaShadow, wSavanna);
}
float wPaleGarden = clamp(biome_pale_garden, 0.0, 1.0);
if (wPaleGarden > 0.001) {

vec3 paleLit = baseCol * mix(vec3(1.0), getPaleGardenSkyZenithColor(), 0.55);
vec3 paleShadow = baseCol * getPaleGardenSkyHorizonColor() * 0.65;
dayLit = mix(dayLit, paleLit, wPaleGarden);
dayShadow = mix(dayShadow, paleShadow, wPaleGarden);
}

vec3 sunsetLit    = baseCol * vec3(1.0, 0.85, 0.65);
vec3 sunsetShadow = baseCol * vec3(0.80, 0.60, 0.70);

vec3 nightLit    = baseCol * vec3(0.50, 0.60, 0.90);
vec3 nightShadow = baseCol * vec3(0.20, 0.25, 0.45);

vec3 litColor   = dayLit * dayAmt + sunsetLit * twlAmt + nightLit * nightAmt;
vec3 shadowColor = dayShadow * dayAmt + sunsetShadow * twlAmt + nightShadow * nightAmt;

return mix(shadowColor, litColor, shadeType);
}

float vanillaNightOpacityFade(float sunAngle) {
float ang = fract(sunAngle);

float evening = smoothstep(0.46, 0.505, ang);
float morning = 1.0 - smoothstep(0.00, 0.10, ang);
return clamp(max(evening, morning), 0.0, 1.0);
}

bool raySlabIntersect(vec3 origin, vec3 dir, float yBottom, float yTop, out float tNear, out float tFar) {
if (abs(dir.y) < 0.0005) {
if (origin.y >= yBottom && origin.y <= yTop) {
tNear = 0.0; tFar = 1e6;
return true;
}
return false;
}
float t0 = (yBottom - origin.y) / dir.y;
float t1 = (yTop    - origin.y) / dir.y;
tNear = min(t0, t1);
tFar  = max(t0, t1);
if (tFar < 0.0) return false;
tNear = max(tNear, 0.0);
return tNear < tFar;
}

bool rayCloudBoxIntersect(vec3 origin, vec3 dir, vec3 boxMin, vec3 boxMax, out float tHit, out vec3 faceNormal) {
vec3 safeDir = vec3(
abs(dir.x) > 0.00001 ? dir.x : (dir.x >= 0.0 ? 0.00001 : -0.00001),
abs(dir.y) > 0.00001 ? dir.y : (dir.y >= 0.0 ? 0.00001 : -0.00001),
abs(dir.z) > 0.00001 ? dir.z : (dir.z >= 0.0 ? 0.00001 : -0.00001)
);

vec3 invDir = 1.0 / safeDir;
vec3 t0 = (boxMin - origin) * invDir;
vec3 t1 = (boxMax - origin) * invDir;
vec3 tMin3 = min(t0, t1);
vec3 tMax3 = max(t0, t1);

float tNear = max(max(tMin3.x, tMin3.y), tMin3.z);
float tFar = min(min(tMax3.x, tMax3.y), tMax3.z);
if (tFar < max(tNear, 0.0)) return false;

tHit = max(tNear, 0.0);

float axisEps = 0.0005;
if (abs(tNear - tMin3.y) <= axisEps) {
faceNormal = vec3(0.0, dir.y > 0.0 ? -1.0 : 1.0, 0.0);
} else if (abs(tNear - tMin3.x) <= axisEps) {
faceNormal = vec3(dir.x > 0.0 ? -1.0 : 1.0, 0.0, 0.0);
} else {
faceNormal = vec3(0.0, 0.0, dir.z > 0.0 ? -1.0 : 1.0);
}

return true;
}

vec4 traceVanillaLayer(
vec3 camPos, vec3 dir, float tNear, float tFar, float layerBottom, float layerTop,
float coverage, float cellSize, float narrowness, float time,
float cloudRenderDist, float maxDist, float dayAmt, float twlAmt, float nightAmt,
float layerDarknessMultiplier, int layerIdx, out float outHitT
) {
outHitT = 1e6;

int neededSteps = int(cloudRenderDist / (cellSize * 0.7071)) + 2;

int maxSteps = min(neededSteps, 1536);

float maxGuaranteedDist = float(maxSteps) * cellSize * 0.7071;
float layerRenderDist = min(cloudRenderDist, maxGuaranteedDist);

if (tNear >= tFar || tNear >= maxDist || tNear >= layerRenderDist) return vec4(0.0);

vec2 windOff = vanillaWindOffset(time);
vec3 entryPos = camPos + dir * tNear;
vec2 startXZ = entryPos.xz + windOff;
vec2 dirXZ = dir.xz;
vec2 stableStartXZ = startXZ + vanillaCloudTraceBias(dirXZ, cellSize);

vec2 cellIdx = floor(stableStartXZ / cellSize);

if (length(dirXZ) < 0.0005) {
vec2 worldCell = (cellIdx + 0.5) * cellSize - windOff;
float cloudFill = vanillaCloudMap(worldCell, time, coverage, narrowness, layerIdx);
if (cloudFill > 0.5) {
vec3 cellMinWorld = vec3(cellIdx.x * cellSize - windOff.x, layerBottom, cellIdx.y * cellSize - windOff.y);
vec3 cellMaxWorld = cellMinWorld + vec3(cellSize, layerTop - layerBottom, cellSize);
float boxHitT;
vec3 faceNormal;
if (rayCloudBoxIntersect(camPos, dir, cellMinWorld, cellMaxWorld, boxHitT, faceNormal)) {
float hitDist = length((camPos + dir * boxHitT).xz - camPos.xz);
float distFade = 1.0 - smoothstep(layerRenderDist * 0.6, layerRenderDist, hitDist);
if (distFade > 0.001) {
float shadeType;
bool isBottomFace = false;
bool isSideFace = false;
if (faceNormal.y < -0.5) {
shadeType = 0.0;
isBottomFace = true;
} else if (faceNormal.y > 0.5) {
shadeType = 1.0;
} else {
float sideY = clamp(((camPos + dir * boxHitT).y - layerBottom) / (layerTop - layerBottom), 0.0, 1.0);
shadeType = mix(0.1, 0.95, sideY);
isSideFace = true;
}

vec3 col = vanillaCloudColor(dayAmt, twlAmt, nightAmt, shadeType, layerDarknessMultiplier);
if (isBottomFace) {
col *= mix(1.0, 0.35, clamp(float(VANILLA_CLOUD_BOTTOM_DARKNESS) / 100.0, 0.0, 1.0));
} else if (isSideFace) {
col *= mix(1.0, 0.50, clamp(float(VANILLA_CLOUD_SIDE_DARKNESS) / 100.0, 0.0, 1.0));
}

outHitT = boxHitT;
return vec4(col, distFade * cloudFill);
}
}
}
return vec4(0.0);
}

vec2 stepDir = vec2(
dirXZ.x > 0.0 ? 1.0 : (dirXZ.x < 0.0 ? -1.0 : 0.0),
dirXZ.y > 0.0 ? 1.0 : (dirXZ.y < 0.0 ? -1.0 : 0.0)
);

vec2 invDir = vec2(1e20);
vec2 tMaxXZ = vec2(1e20);
vec2 tDelta = vec2(1e20);

if (abs(dirXZ.x) > 0.0001) {
invDir.x = 1.0 / dirXZ.x;
tDelta.x = abs(cellSize * invDir.x);
float nextX = (cellIdx.x + (stepDir.x > 0.0 ? 1.0 : 0.0)) * cellSize;
tMaxXZ.x = (nextX - stableStartXZ.x) * invDir.x;
}
if (abs(dirXZ.y) > 0.0001) {
invDir.y = 1.0 / dirXZ.y;
tDelta.y = abs(cellSize * invDir.y);
float nextY = (cellIdx.y + (stepDir.y > 0.0 ? 1.0 : 0.0)) * cellSize;
tMaxXZ.y = (nextY - stableStartXZ.y) * invDir.y;
}

float tLimit = min(tFar, min(maxDist, layerRenderDist));

for (int i = 0; i < maxSteps; i++) {
vec2 worldCell = (cellIdx + 0.5) * cellSize - windOff;

float cloudFill = vanillaCloudMap(worldCell, time, coverage, narrowness, layerIdx);
if (cloudFill > 0.5) {
vec3 cellMinWorld = vec3(cellIdx.x * cellSize - windOff.x, layerBottom, cellIdx.y * cellSize - windOff.y);
vec3 cellMaxWorld = cellMinWorld + vec3(cellSize, layerTop - layerBottom, cellSize);
float boxHitT;
vec3 faceNormal;

if (rayCloudBoxIntersect(camPos, dir, cellMinWorld, cellMaxWorld, boxHitT, faceNormal)) {
if (boxHitT > tLimit) break;

vec3 hitPos = camPos + dir * boxHitT;
float hitDist = length(hitPos.xz - camPos.xz);
float distFade = 1.0 - smoothstep(layerRenderDist * 0.6, layerRenderDist, hitDist);
if (distFade < 0.001) break;

outHitT = boxHitT;

float shadeType;
bool isBottomFace = false;
bool isSideFace = false;
if (faceNormal.y < -0.5) {
shadeType = 0.0;
isBottomFace = true;
} else if (faceNormal.y > 0.5) {
shadeType = 1.0;
} else {
float sideY = clamp((hitPos.y - layerBottom) / (layerTop - layerBottom), 0.0, 1.0);
shadeType = mix(0.1, 0.95, sideY);
isSideFace = true;
}

vec3 col = vanillaCloudColor(dayAmt, twlAmt, nightAmt, shadeType, layerDarknessMultiplier);
if (isBottomFace) {
col *= mix(1.0, 0.35, clamp(float(VANILLA_CLOUD_BOTTOM_DARKNESS) / 100.0, 0.0, 1.0));
} else if (isSideFace) {
col *= mix(1.0, 0.50, clamp(float(VANILLA_CLOUD_SIDE_DARKNESS) / 100.0, 0.0, 1.0));
}
return vec4(col, distFade * cloudFill);
}
}

float sharedT = min(tMaxXZ.x, tMaxXZ.y);
if (abs(tMaxXZ.x - tMaxXZ.y) <= 0.0005) {
cellIdx += stepDir;
if (tNear + sharedT > tLimit) break;
tMaxXZ += tDelta;
} else if (tMaxXZ.x < tMaxXZ.y) {
cellIdx.x += stepDir.x;
if (tNear + tMaxXZ.x > tLimit) break;
tMaxXZ.x += tDelta.x;
} else {
cellIdx.y += stepDir.y;
if (tNear + tMaxXZ.y > tLimit) break;
tMaxXZ.y += tDelta.y;
}
}

return vec4(0.0);
}

vec4 computeVanillaClouds(vec3 worldDir, float time, vec3 camPos, float sunAngle, vec3 sunDirWorld, float maxDist, vec2 fragCoord, int frame, out float outCloudDepth, float rainOpacityMul) {
outCloudDepth = 0.0;
vec3 dir = normalize(worldDir);
float cloudRenderDist = float(VANILLA_CLOUD_DISTANCE);

float dayAmt, twlAmt, nightAmt;
vanillaTimeOfDay(sunAngle, dayAmt, twlAmt, nightAmt);

float nightFade = vanillaNightOpacityFade(sunAngle);

float nightVisual = smoothstep(0.60, 0.95, nightFade);
float dayColorAmt = dayAmt;
float twlColorAmt = twlAmt + nightAmt * (1.0 - nightVisual);
float nightColorAmt = nightAmt * nightVisual;
float colorTot = max(dayColorAmt + twlColorAmt + nightColorAmt, 0.001);
dayColorAmt /= colorTot;
twlColorAmt /= colorTot;
nightColorAmt /= colorTot;
float nightOpacityMul = 1.0 - nightFade * (float(VANILLA_CLOUD_NIGHT_OPACITY_REDUCTION) / 100.0);
nightOpacityMul = clamp(nightOpacityMul, 0.0, 1.0);

float baseAltitude = float(VANILLA_CLOUD_HEIGHT) + float(SEA_LEVEL_OFFSET);
float thick = float(VANILLA_CLOUD_THICKNESS);
float spread = float(VANILLA_CLOUD_LAYER_SPACING);

float l1Bottom = baseAltitude;
float l1Top    = l1Bottom + thick;

float l2Bottom = l1Top + spread;
float l2Top    = l2Bottom + thick;

float l3Bottom = l2Top + spread;
float l3Top    = l3Bottom + thick;

float narrowness = 0.07;

vec4 bestColor = vec4(0.0);
float bestT = 1e6;
vec4 result;
float hitT;

vec4 resultL1 = vec4(0.0); float tL1 = 1e6;
if (float(VANILLA_CLOUD_L1_OPACITY) > 0.0) {
float l1TN, l1TF; float hitT;
if (raySlabIntersect(camPos, dir, l1Bottom, l1Top, l1TN, l1TF)) {
vec4 temp = traceVanillaLayer(
camPos, dir, l1TN, l1TF, l1Bottom, l1Top,
float(VANILLA_CLOUD_L1_COVERAGE), float(VANILLA_CLOUD_L1_PIXEL_SIZE), narrowness, time,
cloudRenderDist, maxDist, dayColorAmt, twlColorAmt, nightColorAmt, 0.60, 1, hitT
);
if (temp.a > 0.0) {
tL1 = hitT;
resultL1 = temp * vec4(1.0, 1.0, 1.0, (float(VANILLA_CLOUD_L1_OPACITY) / 100.0) * nightOpacityMul * rainOpacityMul);

resultL1.rgb *= resultL1.a;
}
}
}

vec4 resultL2 = vec4(0.0); float tL2 = 1e6;
if (float(VANILLA_CLOUD_L2_OPACITY) > 0.0) {
float l2TN, l2TF; float hitT;
if (raySlabIntersect(camPos, dir, l2Bottom, l2Top, l2TN, l2TF)) {

vec4 temp = traceVanillaLayer(
camPos, dir, l2TN, l2TF, l2Bottom, l2Top,
float(VANILLA_CLOUD_L2_COVERAGE), float(VANILLA_CLOUD_L2_PIXEL_SIZE), narrowness, time,
cloudRenderDist, maxDist, dayColorAmt, twlColorAmt, nightColorAmt, 0.85, 2, hitT
);
if (temp.a > 0.0) {
tL2 = hitT;
resultL2 = temp * vec4(1.0, 1.0, 1.0, (float(VANILLA_CLOUD_L2_OPACITY) / 100.0) * nightOpacityMul * rainOpacityMul);

resultL2.rgb *= resultL2.a;
}
}
}

vec4 resultL3 = vec4(0.0); float tL3 = 1e6;
if (float(VANILLA_CLOUD_L3_OPACITY) > 0.0) {
float l3TN, l3TF; float hitT;
if (raySlabIntersect(camPos, dir, l3Bottom, l3Top, l3TN, l3TF)) {

vec4 temp = traceVanillaLayer(
camPos, dir, l3TN, l3TF, l3Bottom, l3Top,
float(VANILLA_CLOUD_L3_COVERAGE), float(VANILLA_CLOUD_L3_PIXEL_SIZE), narrowness, time,
cloudRenderDist, maxDist, dayColorAmt, twlColorAmt, nightColorAmt, 1.15, 3, hitT
);
if (temp.a > 0.0) {
tL3 = hitT;
resultL3 = temp * vec4(1.0, 1.0, 1.0, (float(VANILLA_CLOUD_L3_OPACITY) / 100.0) * nightOpacityMul * rainOpacityMul);

resultL3.rgb *= resultL3.a;
}
}
}

vec4 layers[3] = vec4[3](vec4(0), vec4(0), vec4(0));
float dists[3] = float[3](1e6, 1e6, 1e6);
int count = 0;

if (resultL1.a > 0.0) { layers[count] = resultL1; dists[count] = tL1; count++; }
if (resultL2.a > 0.0) { layers[count] = resultL2; dists[count] = tL2; count++; }
if (resultL3.a > 0.0) { layers[count] = resultL3; dists[count] = tL3; count++; }

for (int i = 0; i < count - 1; i++) {
for (int j = 0; j < count - i - 1; j++) {
if (dists[j] < dists[j+1]) {
float tempD = dists[j]; dists[j] = dists[j+1]; dists[j+1] = tempD;
vec4 tempL = layers[j]; layers[j] = layers[j+1]; layers[j+1] = tempL;
}
}
}

vec4 finalColor = vec4(0.0);
for (int i = 0; i < count; i++) {
finalColor.rgb = finalColor.rgb * (1.0 - layers[i].a) + layers[i].rgb;
finalColor.a   = finalColor.a   * (1.0 - layers[i].a) + layers[i].a;
}

if (count > 0) {
outCloudDepth = dists[count - 1];
}

return finalColor;
}

#endif
