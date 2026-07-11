#ifndef INCLUDE_TORNADO_PARTICLES_GLSL
#define INCLUDE_TORNADO_PARTICLES_GLSL

#include "/settings.glsl"

#ifdef TORNADO_LEAVES_ENABLED

#ifndef TP_TAU_DEFINED
#define TP_TAU_DEFINED
const float tp_tau = 6.28318530718;
#endif

const int LEAF_VARIANT_COUNT = 3;

const uint LEAF_ROWS_V0[32] = uint[](
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x10000000u, 0x00011111u,
0x10000000u, 0x00011111u,
0x10000000u, 0x00011111u,
0x22220000u, 0x00011122u,
0x22220000u, 0x00011122u,
0x22220000u, 0x00011122u,
0x22220000u, 0x00000022u,
0x22220000u, 0x00000022u,
0x22220000u, 0x00000022u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u
);

const uint LEAF_ROWS_V1[32] = uint[](
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x10000000u, 0x00011111u,
0x10000000u, 0x00011111u,
0x22200000u, 0x00011222u,
0x22200000u, 0x00011222u,
0x33330000u, 0x00011223u,
0x33330000u, 0x00011223u,
0x33330000u, 0x00000223u,
0x33000000u, 0x00000223u,
0x33000000u, 0x00000003u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u
);

const uint LEAF_ROWS_V2[32] = uint[](
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x00000000u, 0x00000000u,
0x11000000u, 0x00111111u,
0x11000000u, 0x00111111u,
0x11000000u, 0x00111111u,
0x20000000u, 0x00111222u,
0x22222200u, 0x00111222u,
0x22222200u, 0x00111222u,
0x22222200u, 0x00111222u,
0x22220000u, 0x00111022u,
0x22220000u, 0x00000022u,
0x22220000u, 0x00000022u,
0x20000000u, 0x00000022u,
0x20000000u, 0x00000022u,
0x00000000u, 0x00000000u
);

vec3 getLeafBiomeTint() {
float wSnow   = max(clamp(biome_snowy, 0.0, 1.0), (isForcedSnowyBiome(biome) || isCategorySnowy(biome_category)) ? 1.0 : 0.0);
float wJungle = max(clamp(biome_jungle, 0.0, 1.0), (isForcedJungleBiome(biome) || isCategoryJungle(biome_category)) ? 1.0 : 0.0);
float wSwamp  = max(clamp(biome_swamp, 0.0, 1.0), (isForcedSwampyBiome(biome) || isCategorySwampy(biome_category)) ? 1.0 : 0.0);
float wArid   = max(clamp(biome_arid, 0.0, 1.0), (isForcedDesertBiome(biome) || isCategoryDesert(biome_category) || isForcedSavannaBiome(biome) || isCategorySavanna(biome_category)) ? 1.0 : 0.0);

vec3 tint = vec3(1.0);
tint = mix(tint, vec3(0.86, 0.98, 0.90), wSnow * 0.70);
tint = mix(tint, vec3(0.88, 1.12, 0.82), wJungle * 0.55);
tint = mix(tint, vec3(0.66, 0.82, 0.50), wSwamp * 0.85);
tint = mix(tint, vec3(0.95, 0.98, 0.72), wArid * 0.40);
return tint;
}

vec3 getLeafVariantColor(int variant, int idx) {
if (variant == 1) {
if (idx == 1) return vec3(0.2902, 0.5373, 0.1961);
if (idx == 2) return vec3(0.2275, 0.4196, 0.1490);
return vec3(0.1765, 0.3137, 0.0941);
}
if (variant == 2) {
if (idx == 1) return vec3(0.2275, 0.4196, 0.1490);
return vec3(0.1882, 0.3569, 0.1255);
}
if (idx == 1) return vec3(0.2745, 0.4745, 0.1647);
return vec3(0.2275, 0.4196, 0.1490);
}

int getRandomLeafVariant(float seed) {
return clamp(int(floor(fract(seed) * float(LEAF_VARIANT_COUNT))), 0, LEAF_VARIANT_COUNT - 1);
}

bool areFlyingLeavesAllowed() {
if (isForcedNetherBiome(biome) || isForcedEndBiome(biome)) return false;

bool treeLessBiome =
biome_beach > 0.5 ||
biome_ocean > 0.5 ||
isForcedDesertBiome(biome) ||
isCategoryDesert(biome_category);

return !treeLessBiome;
}

vec4 sampleLeaf(vec2 uv, int variant) {
if (uv.x < 0.0 || uv.x >= 1.0 || uv.y < 0.0 || uv.y >= 1.0) return vec4(0.0);
int x = int(uv.x * 16.0);
int y = int(uv.y * 16.0);
int rowBase = y * 2;
uint rowLo = LEAF_ROWS_V0[rowBase];
uint rowHi = LEAF_ROWS_V0[rowBase + 1];
if (variant == 1) {
rowLo = LEAF_ROWS_V1[rowBase];
rowHi = LEAF_ROWS_V1[rowBase + 1];
} else if (variant == 2) {
rowLo = LEAF_ROWS_V2[rowBase];
rowHi = LEAF_ROWS_V2[rowBase + 1];
}
uint row = (x < 8) ? rowLo : rowHi;
int col = (x < 8) ? x : (x - 8);
int idx = int((row >> (uint(col) * 4u)) & 0xFu);
if (idx == 0) return vec4(0.0);
return vec4(getLeafVariantColor(variant, idx) * getLeafBiomeTint(), 1.0);
}

const float TP_CYCLE_LEN  = 100.0;
const float TP_ACTIVE_LEN = 70.0;
const float TP_RADIUS     = 2.5;
const float TP_REGION     = 40.0;
const float TP_WORLD_Y_MIN = 60.0;
const float TP_WORLD_Y_MAX = 200.0;
const float TP_RENDER_RADIUS = FLYING_LEAF_RENDER_RADIUS;
const int   TP_PER_TORNADO = 2;
const float TP_PIX_SIZE   = 0.27;

vec3 applyLeafSunFaceGlow(vec3 leafColor, vec3 leafNormal, vec3 viewDir) {
vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * sunPosition);
float sunAboveHorizon = step(0.0, sunDirWorld.y);
vec3 visibleFaceNormal = dot(leafNormal, -viewDir) >= 0.0 ? leafNormal : -leafNormal;
float faceToSun = max(dot(visibleFaceNormal, sunDirWorld), 0.0);
float glow = sunAboveHorizon * faceToSun * faceToSun * 0.85;
return leafColor * (1.0 + glow) + vec3(0.10, 0.08, 0.03) * glow;
}

bool tp_particle_ray_gate(vec3 camPos, vec3 viewDir, vec3 particleWorld, float sceneDist, float closestHit, float halfSize, out float centerDist) {
vec3 toP = particleWorld - camPos;
centerDist = length(toP);
if (centerDist > TP_RENDER_RADIUS || centerDist >= closestHit) return false;

float projDist = dot(toP, viewDir);
if (projDist < 0.5 || projDist > sceneDist) return false;

float radial2 = max(dot(toP, toP) - projDist * projDist, 0.0);
float gateRadius = halfSize * 1.45 + 0.05;
return radial2 <= gateRadius * gateRadius;
}

void tp_build_leaf_basis(float tumble, float roll, out vec3 n, out vec3 uAxis, out vec3 vAxis) {
float ct = cos(tumble);
float st = sin(tumble);
float cr = cos(roll);
float sr = sin(roll);
n = vec3(ct * cr, st, ct * sr);
vAxis = vec3(-st * cr, ct, -st * sr);
uAxis = cross(vAxis, n);
}

float tp_hash21(vec2 p) {
return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

bool tp_get_tornado(vec2 region, float tY, out vec2 center, out float env, out float eU, out float tIdx) {
float tphase = tp_hash21(region + vec2(211.3, 47.8)) * TP_CYCLE_LEN;
float tCyclePos = mod(tY + tphase, TP_CYCLE_LEN);
if (tCyclePos >= TP_ACTIVE_LEN) return false;
tIdx = floor((tY + tphase) / TP_CYCLE_LEN);
center = region * TP_REGION + vec2(
TP_RADIUS + 1.0 + tp_hash21(region + vec2(tIdx * 7.1, 11.9)) * (TP_REGION - 2.0 * (TP_RADIUS + 1.0)),
TP_RADIUS + 1.0 + tp_hash21(region + vec2(tIdx * 19.3, 83.5)) * (TP_REGION - 2.0 * (TP_RADIUS + 1.0))
);
eU = tCyclePos / TP_ACTIVE_LEN;
env = smoothstep(0.0, 0.2, eU) * (1.0 - smoothstep(0.8, 1.0, eU));
return true;
}

vec4 render_tornado_leaves(vec3 camPos, vec3 viewDir, float sceneDist, float tY) {
if (!areFlyingLeavesAllowed()) return vec4(0.0);
vec4 result = vec4(0.0);
float closestHit = 1e9;

vec3 winParticle = vec3(0.0);
vec3 winN = vec3(0.0);
vec3 winU = vec3(0.0);
vec3 winV = vec3(0.0);
int winVariant = 0;
bool haveWinner = false;

vec2 camRegion = floor(camPos.xz / TP_REGION);

for (int ox = -1; ox <= 1; ox++) {
for (int oz = -1; oz <= 1; oz++) {
vec2 region = camRegion + vec2(float(ox), float(oz));
vec2 center;
float env, eU, tIdx;
if (!tp_get_tornado(region, tY, center, env, eU, tIdx)) continue;
if (env < 0.01) continue;

for (int i = 0; i < TP_PER_TORNADO; i++) {
float fi = float(i);

float phase = tp_hash21(region + vec2(tIdx * 11.0 + fi, 17.0));
float rOff  = tp_hash21(region + vec2(tIdx * 5.3 + fi, 29.0));
int leafVariant = getRandomLeafVariant(tp_hash21(region + vec2(tIdx * 13.7 + fi * 5.1, 61.3)));
float radius = mix(TP_RADIUS * 0.3, TP_RADIUS * 0.95, rOff);

float angularSpeed = 6.0 + phase * 3.0;
float angle = eU * TP_ACTIVE_LEN * angularSpeed + phase * tp_tau;

float yOffset = phase * 20.0;
float y = mix(TP_WORLD_Y_MIN, TP_WORLD_Y_MAX, eU) + yOffset;
vec3 particleWorld = vec3(
center.x + cos(angle) * radius,
y,
center.y + sin(angle) * radius
);

float halfSize = TP_PIX_SIZE;
float centerDist = 0.0;
if (!tp_particle_ray_gate(camPos, viewDir, particleWorld, sceneDist, closestHit, halfSize, centerDist)) continue;

float tumbleSpeed = 2.0 + phase * 1.5;
float rollSpeed   = 3.0 + rOff  * 2.0;
float tumble = eU * TP_ACTIVE_LEN * tumbleSpeed + phase * tp_tau;
float roll   = eU * TP_ACTIVE_LEN * rollSpeed   + rOff  * tp_tau;
vec3 n, uAxis, vAxis;
tp_build_leaf_basis(tumble, roll, n, uAxis, vAxis);

float denom = dot(viewDir, n);
if (abs(denom) < 1e-4) continue;
float tHit = dot(particleWorld - camPos, n) / denom;
if (tHit < 0.5 || tHit > sceneDist) continue;

vec3 hitPoint = camPos + viewDir * tHit;
vec3 rel = hitPoint - particleWorld;
float u = dot(rel, uAxis);
float v = dot(rel, vAxis);
float halfQuad = TP_PIX_SIZE;
if (abs(u) > halfQuad || abs(v) > halfQuad) continue;

closestHit = centerDist;
winParticle = particleWorld;
winN = n;
winU = uAxis;
winV = vAxis;
winVariant = leafVariant;
haveWinner = true;
}
}
}

if (haveWinner) {
float denom = dot(viewDir, winN);
float tHit = dot(winParticle - camPos, winN) / denom;
vec3 hitPoint = camPos + viewDir * tHit;
vec3 rel = hitPoint - winParticle;
float u = dot(rel, winU);
float v = dot(rel, winV);
vec2 leafUV = vec2(u, v) / (2.0 * TP_PIX_SIZE) + 0.5;
result = sampleLeaf(leafUV, winVariant);
if (result.a > 0.0) result.rgb = applyLeafSunFaceGlow(result.rgb, winN, viewDir);
}

return result;
}

const float FL_PATCH_SIZE = 6.0;
const float FL_CELL_XZ    = 60.0;
const float FL_CELL_Y     = 10.0;
const float FL_SPEED      = 3.0;
const int   FL_RANGE_XZ   = 2;
const int   FL_RANGE_Y    = 4;
const int   FL_STREAMS    = 3;
const int   FL_SOLO_STREAMS = 2;
const int   FL_SOLO_PATHS = 5;
const int   FL_TRAIL_MAX  = FLYING_LEAF_TRAIL_MAX;
const float FL_DENSITY    = FLYING_LEAF_DENSITY;
const float FL_SOLO_TRAVEL_SPAN  = 96.0;
const float FL_GROUP_TRAVEL_SPAN = 96.0;

float fl_cell_spawn_field(vec3 cellId, vec3 cellCenter) {
vec2 macroId = floor(cellCenter.xz / 192.0);
float macroSeed = tp_hash21(macroId + vec2(17.3, 81.9));
float laneAngle = tp_hash21(macroId + vec2(31.7, 9.3)) * tp_tau;
vec2 laneDir = vec2(cos(laneAngle), sin(laneAngle));

float laneSpacing = 42.0 + macroSeed * 18.0;
float lanePhase = tp_hash21(macroId + vec2(53.1, 27.4)) * 6.0;
float laneCoord = dot(cellCenter.xz, laneDir) / laneSpacing + lanePhase;
float laneCore = 1.0 - abs(fract(laneCoord) - 0.5) * 2.0;
laneCore = smoothstep(0.18, 0.82, laneCore);

float clusterSeed = tp_hash21(macroId + vec2(71.1, 44.7));
float cluster = smoothstep(0.28, 0.78, clusterSeed);

float localSeed = tp_hash21(cellId.xz + vec2(cellId.y * 0.37, 91.7));
float localKeep = smoothstep(0.25, 0.80, localSeed);

float seaLevel = float(SEA_LEVEL_OFFSET);
float heightBias = 1.0 - smoothstep(48.0, 160.0, abs(cellCenter.y - (seaLevel + 24.0)));
heightBias = mix(0.75, 1.0, heightBias);

return clamp((laneCore * 0.65 + cluster * 0.20 + localKeep * 0.15) * heightBias, 0.0, 1.0);
}

vec2 fl_sample_wind_dir(vec2 worldXZ, float t) {
vec2 patchId = floor(worldXZ / FL_PATCH_SIZE);
float speedHash = tp_hash21(patchId + vec2(67.3, 29.1));
float speedMult = 0.2;
if      (speedHash > 0.75) speedMult = 1.0;
else if (speedHash > 0.50) speedMult = 0.7;
else if (speedHash > 0.25) speedMult = 0.5;
t *= speedMult;

float patchPhase = tp_hash21(patchId + vec2(41.3, 11.9)) * tp_tau;
float tLocal = t + patchPhase;

float ph0 = tp_hash21(patchId + vec2(77.0, 13.0)) * tp_tau;
float ph1 = tp_hash21(patchId + vec2(19.0, 57.0)) * tp_tau;
float ph2 = tp_hash21(patchId + vec2(91.0, 31.0)) * tp_tau;
float ph3 = tp_hash21(patchId + vec2(43.0, 71.0)) * tp_tau;
float ph4 = tp_hash21(patchId + vec2(11.0, 97.0)) * tp_tau;
float ph5 = tp_hash21(patchId + vec2(59.0, 23.0)) * tp_tau;

vec2 dirVec = vec2(
sin(tLocal * 0.37 + ph0) + 0.55 * sin(tLocal * 0.91 + ph1) + 0.25 * sin(tLocal * 1.63 + ph2),
cos(tLocal * 0.33 + ph3) + 0.50 * cos(tLocal * 0.79 + ph4) + 0.22 * cos(tLocal * 1.47 + ph5)
);
float dirLen = max(length(dirVec), 1e-4);
return dirVec / dirLen;
}

vec3 fl_compute_solo_leaf_position(vec3 cellOrigin, vec3 cellId, float sf, float tY) {
float phaseSeed = tp_hash21(cellId.xy + vec2(17.0 + sf * 7.3, cellId.z + sf * 11.1));
float phase = phaseSeed * tp_tau;
vec2 windDir = fl_sample_wind_dir(cellOrigin.xz + vec2(sf * 4.3, sf * 6.1), tY + sf * 0.9);
vec2 crossDir = vec2(-windDir.y, windDir.x);
int pathType = clamp(int(floor(tp_hash21(cellId.xz + vec2(73.7 + sf * 13.0, cellId.y + sf * 5.7)) * float(FL_SOLO_PATHS))), 0, FL_SOLO_PATHS - 1);

float travelCycle = FL_SOLO_TRAVEL_SPAN;
float travelSeed = tp_hash21(cellId.yz + vec2(9.7 + sf * 11.0, cellId.x + sf * 4.1)) * travelCycle;
float advance = mod(tY * FL_SPEED + travelSeed, travelCycle) - travelCycle * 0.5;
float fastAdvance = mod(tY * (FL_SPEED * 1.8) + travelSeed, travelCycle) - travelCycle * 0.5;
float slowAdvance = mod(tY * (FL_SPEED * 0.55) + travelSeed, travelCycle) - travelCycle * 0.5;

vec3 particleWorld = cellOrigin;

if (pathType == 0) {
float swirlT = tY * 1.8 + phase;
float radius = 1.4 + tp_hash21(cellId.xy + vec2(5.1 + sf * 3.0, cellId.z)) * 1.6;
vec2 swirl = windDir * advance + crossDir * sin(swirlT) * radius + windDir * cos(swirlT * 0.7) * 0.9;
particleWorld += vec3(swirl.x, sin(swirlT * 1.1) * 1.2 + cos(swirlT * 0.6) * 0.5, swirl.y);
} else if (pathType == 1) {
float spiralT = tY * 3.8 + phase;
float radius = 0.8 + tp_hash21(cellId.yz + vec2(2.7 + sf * 4.0, cellId.x)) * 1.1;
vec2 spiral = windDir * fastAdvance + crossDir * cos(spiralT) * radius + windDir * sin(spiralT) * 0.6;
particleWorld += vec3(spiral.x, sin(spiralT * 0.8) * 1.5 + cos(spiralT * 1.4) * 0.8, spiral.y);
} else if (pathType == 2) {
float featherT = tY * 1.4 + phase;
float fallBand = mod(tY * 0.85 + tp_hash21(cellId.xy + vec2(14.3 + sf * 5.0, cellId.z)) * 9.0, 9.0) - 4.5;
vec2 drift = windDir * slowAdvance + crossDir * sin(featherT * 1.7) * 2.2;
particleWorld += vec3(drift.x, -fallBand + sin(featherT * 0.9) * 0.7, drift.y);
} else if (pathType == 3) {
float raceT = tY * 2.6 + phase;
vec2 race = windDir * (fastAdvance * 1.25) + crossDir * sin(raceT * 2.2) * 0.6;
particleWorld += vec3(race.x, sin(raceT * 1.4) * 0.45 + cos(raceT * 2.5) * 0.2, race.y);
} else {
float swayT = tY * 1.15 + phase;
vec2 meander = windDir * (advance * 0.8) + crossDir * (sin(swayT) * 1.7 + cos(swayT * 0.45) * 0.9);
particleWorld += vec3(meander.x, sin(swayT * 0.8) * 0.9 + cos(swayT * 1.6) * 0.35, meander.y);
}

return particleWorld;
}

bool fl_try_leaf_candidate(
vec3 camPos, vec3 viewDir, float sceneDist, float tY, vec3 cellId, float sf, float ti, int leafVariant, vec3 particleWorld,
inout float closestHit, inout vec3 winParticle, inout vec3 winN, inout vec3 winU, inout vec3 winV, inout int winVariant, inout bool haveWinner
) {
float halfSize = TP_PIX_SIZE;
float centerDist = 0.0;
if (!tp_particle_ray_gate(camPos, viewDir, particleWorld, sceneDist, closestHit, halfSize, centerDist)) return false;

float tumble = tY * 5.0 + tp_hash21(cellId.xz + vec2(1.1 + ti * 2.3 + sf * 7.0, cellId.y + sf * 2.0)) * tp_tau;
float roll   = tY * 7.0 + tp_hash21(cellId.xy + vec2(2.3 + ti * 1.7 + sf * 5.0, cellId.z + sf * 3.0)) * tp_tau;
vec3 n, uAxis, vAxis;
tp_build_leaf_basis(tumble, roll, n, uAxis, vAxis);

float denom = dot(viewDir, n);
if (abs(denom) < 1e-4) return false;
float tHit = dot(particleWorld - camPos, n) / denom;
if (tHit < 0.5 || tHit > sceneDist) return false;

vec3 hitPoint = camPos + viewDir * tHit;
vec3 rel = hitPoint - particleWorld;
float u = dot(rel, uAxis);
float v = dot(rel, vAxis);
float halfQuad = TP_PIX_SIZE;
if (abs(u) > halfQuad || abs(v) > halfQuad) return false;

closestHit = centerDist;
winParticle = particleWorld;
winN = n;
winU = uAxis;
winV = vAxis;
winVariant = leafVariant;
haveWinner = true;
return true;
}

vec4 render_free_leaves(vec3 camPos, vec3 viewDir, float sceneDist, float tY) {
if (!areFlyingLeavesAllowed()) return vec4(0.0);
vec4 result = vec4(0.0);
float closestHit = 1e9;

vec3 winParticle = vec3(0.0);
vec3 winN = vec3(0.0);
vec3 winU = vec3(0.0);
vec3 winV = vec3(0.0);
int winVariant = 0;
bool haveWinner = false;

vec3 camCell = floor(camPos / vec3(FL_CELL_XZ, FL_CELL_Y, FL_CELL_XZ));

for (int ox = -FL_RANGE_XZ; ox <= FL_RANGE_XZ; ox++) {
for (int oy = -FL_RANGE_Y;  oy <= FL_RANGE_Y;  oy++) {
for (int oz = -FL_RANGE_XZ; oz <= FL_RANGE_XZ; oz++) {
vec3 cellId = camCell + vec3(float(ox), float(oy), float(oz));

vec3 cellCenter = (cellId + 0.5) * vec3(FL_CELL_XZ, FL_CELL_Y, FL_CELL_XZ);
vec3 toCell = cellCenter - camPos;
if (length(toCell) > TP_RENDER_RADIUS + length(vec3(FL_CELL_XZ, FL_CELL_Y, FL_CELL_XZ)) * 0.5) continue;
if (dot(toCell, viewDir) < -FL_CELL_XZ) continue;
float aboveCamera = cellCenter.y - camPos.y;
float verticalViewBias = 1.0 - smoothstep(12.0, 34.0, aboveCamera);
if (verticalViewBias <= 0.0001) continue;
float cellField = fl_cell_spawn_field(cellId, cellCenter) * FL_DENSITY;
cellField *= mix(0.55, 1.0, verticalViewBias);
if (cellField < 0.40) continue;
int activeStreams = 1 + int(floor(clamp((cellField - 0.40) / 0.60, 0.0, 0.999) * float(FL_STREAMS)));
activeStreams = clamp(activeStreams, 1, FL_STREAMS);
for (int streamI = 0; streamI < activeStreams; streamI++) {
float sf = float(streamI);

float yRand = tp_hash21(cellId.xy + vec2(7.3 + sf * 13.1, cellId.z + sf * 3.1));
yRand = pow(yRand, 1.9) * 0.58 + 0.05;
vec3 cellOrigin = (cellId + vec3(
tp_hash21(cellId.xz + vec2(3.1 + sf * 11.7, cellId.y + sf * 2.3)),
yRand,
tp_hash21(cellId.yz + vec2(2.9 + sf * 9.7,  cellId.x + sf * 4.7))
)) * vec3(FL_CELL_XZ, FL_CELL_Y, FL_CELL_XZ);

float trailHash = tp_hash21(cellId.xz + vec2(53.1 + sf * 19.3, cellId.y + sf * 7.1));
bool soloStream = streamI < FL_SOLO_STREAMS;
int trailLen = soloStream ? 1 : (int(floor(trailHash * float(FL_TRAIL_MAX))) + 1);
const float TRAIL_SPACING = 0.8;

if (soloStream) {
float ti = 0.0;
int leafVariant = getRandomLeafVariant(tp_hash21(cellId.xz + vec2(cellId.y * 13.0 + sf * 23.0, 91.7 + sf * 11.0)));
vec3 particleWorld = fl_compute_solo_leaf_position(cellOrigin, cellId, sf, tY);
fl_try_leaf_candidate(camPos, viewDir, sceneDist, tY, cellId, sf, ti, leafVariant, particleWorld,
closestHit, winParticle, winN, winU, winV, winVariant, haveWinner);
continue;
}

for (int trailI = 0; trailI < FL_TRAIL_MAX; trailI++) {
if (trailI >= trailLen) break;
float ti = float(trailI);
int leafVariant = getRandomLeafVariant(tp_hash21(cellId.xz + vec2(cellId.y * 13.0 + ti * 5.7 + sf * 23.0, 91.7 + sf * 11.0)));

float angle = tp_hash21(cellId.xz + vec2(31.7 + sf * 17.0, cellId.y + sf * 5.0)) * tp_tau;
vec2 windDir = vec2(cos(angle), sin(angle));
float yPhase = tp_hash21(cellId.xy + vec2(11.0 + ti * 3.7 + sf * 13.0, cellId.z + sf * 5.3)) * tp_tau;
float yDrift = sin(tY * 0.7 + yPhase) * 2.0;

float trailOffset = ti * TRAIL_SPACING;
float cyclePhase = tp_hash21(cellId.xz + vec2(7.3 + sf * 29.1, cellId.y + sf * 3.0)) * FL_GROUP_TRAVEL_SPAN;
float travel = mod(tY * FL_SPEED + cyclePhase - trailOffset, FL_GROUP_TRAVEL_SPAN) - FL_GROUP_TRAVEL_SPAN * 0.5;

vec3 particleWorld = vec3(
cellOrigin.x + windDir.x * travel,
cellOrigin.y + yDrift + ti * 0.1 + sf * 0.35,
cellOrigin.z + windDir.y * travel
);

fl_try_leaf_candidate(camPos, viewDir, sceneDist, tY, cellId, sf, ti, leafVariant, particleWorld,
closestHit, winParticle, winN, winU, winV, winVariant, haveWinner);
}
}
}
}
}

if (haveWinner) {
float denom = dot(viewDir, winN);
float tHit = dot(winParticle - camPos, winN) / denom;
vec3 hitPoint = camPos + viewDir * tHit;
vec3 rel = hitPoint - winParticle;
float u = dot(rel, winU);
float v = dot(rel, winV);
vec2 leafUV = vec2(u, v) / (2.0 * TP_PIX_SIZE) + 0.5;
result = sampleLeaf(leafUV, winVariant);
if (result.a > 0.0) result.rgb = applyLeafSunFaceGlow(result.rgb, winN, viewDir);
}

return result;
}

#endif

#endif
