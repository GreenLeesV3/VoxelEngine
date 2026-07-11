#ifndef INCLUDE_WAVING_GLSL
#define INCLUDE_WAVING_GLSL

const float pi           = 3.14159265359;
const float tau          = 6.28318530718;
const float degree       = pi / 180.0;
const float golden_angle = 2.39996322973;

float sqr(float x) { return x * x; }
float clamp01(float x) { return clamp(x, 0.0, 1.0); }

#ifndef WAVING_STYLE
#define WAVING_STYLE 1
#endif

#ifndef IS_IRIS

uniform vec3 cameraPosition;
#define eyePosition cameraPosition
#else

uniform vec3 eyePosition;
#endif

#ifndef FRAME_TIME_COUNTER_DECLARED
#define FRAME_TIME_COUNTER_DECLARED
uniform float frameTimeCounter;
#endif

float get_waving_distance_boost(vec3 world_pos) {

float d = length(world_pos - eyePosition);
float t = smoothstep(WAVING_DISTANCE_BOOST_START, WAVING_DISTANCE_BOOST_END, d);
return mix(1.0, WAVING_DISTANCE_BOOST_MAX, t);
}

uniform float rainStrength;
uniform sampler2D noisetex;
uniform int isEyeInWater;

const int BLOCK_SMALL_PLANTS      = 2;
const int BLOCK_TALL_PLANTS_LOWER = 3;
const int BLOCK_TALL_PLANTS_UPPER = 4;
const int BLOCK_LEAVES            = 5;
const int BLOCK_HANGING_LANTERN   = 6;
const int BLOCK_HANGING_COPPER_LANTERN = 89;
const int BLOCK_GRASS_BLOCK       = 15;
const int BLOCK_GRASS             = 60;
const int BLOCK_TALL_GRASS_LOWER  = 61;
const int BLOCK_TALL_GRASS_UPPER  = 62;
const int BLOCK_OAK_LEAVES        = 82;

vec3 rotate_x(vec3 p, float a) {
float s = sin(a);
float c = cos(a);
return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

vec3 rotate_z(vec3 p, float a) {
float s = sin(a);
float c = cos(a);
return vec3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

void swing_lantern(inout vec3 world_pos, vec3 mid_block_offset, float swayFactor) {
vec3 center = world_pos + mid_block_offset / 64.0;
vec3 pivot = center;
pivot.y = floor(pivot.y + 1.0);

vec2 cell = floor(center.xz);
float n1 = texture(noisetex, (cell + vec2(0.5, 0.5)) / 256.0).r;
float n2 = texture(noisetex, (cell + vec2(1.5, 2.5)) / 256.0).r;

float rainLanternBoost = mix(1.0, 1.45, rainStrength);
float strength = 0.08 * rainLanternBoost * LANTERN_SWAY_INTENSITY;
strength *= get_waving_distance_boost(center) * swayFactor;

float t = frameTimeCounter * LANTERN_SWAY_SPEED;
float angle_x = sin(t * 1.2 + n1 * tau) * strength;
float angle_z = sin(t * 1.6 + n2 * tau) * strength * 0.8;

vec3 local_pos = world_pos - pivot;
local_pos = rotate_x(local_pos, angle_x);
local_pos = rotate_z(local_pos, angle_z);
world_pos = pivot + local_pos;
}

float wind_hash11(float x) {
return fract(sin(x * 12.9898) * 43758.5453);
}
vec2 wind_hash12(float x) {
return fract(sin(vec2(x, x + 1.0) * vec2(12.9898, 78.233)) * 43758.5453);
}
float wind_hash21(vec2 p) {
return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 sample_patch_wind(vec2 patchId, float t) {

float speedHash = wind_hash21(patchId + vec2(67.3, 29.1));
float speedMult = 0.2;
if      (speedHash > 0.75) speedMult = 1.0;
else if (speedHash > 0.50) speedMult = 0.7;
else if (speedHash > 0.25) speedMult = 0.5;
t *= speedMult;

float baseMag = 0.8 + 0.2 * wind_hash21(patchId + vec2(5.1, 2.3));
float patchPhase = wind_hash21(patchId + vec2(41.3, 11.9)) * tau;
float tLocal = t + patchPhase;

float ph0 = wind_hash21(patchId + vec2(77.0, 13.0)) * tau;
float ph1 = wind_hash21(patchId + vec2(19.0, 57.0)) * tau;
float ph2 = wind_hash21(patchId + vec2(91.0, 31.0)) * tau;
float ph3 = wind_hash21(patchId + vec2(43.0, 71.0)) * tau;
float ph4 = wind_hash21(patchId + vec2(11.0, 97.0)) * tau;
float ph5 = wind_hash21(patchId + vec2(59.0, 23.0)) * tau;

vec2 dirVec = vec2(
sin(tLocal * 0.37 + ph0) + 0.55 * sin(tLocal * 0.91 + ph1) + 0.25 * sin(tLocal * 1.63 + ph2),
cos(tLocal * 0.33 + ph3) + 0.50 * cos(tLocal * 0.79 + ph4) + 0.22 * cos(tLocal * 1.47 + ph5)
);
float dirLen = max(length(dirVec), 1e-4);
vec2 dir = dirVec / dirLen;

float magPulse = 0.88
+ 0.10 * sin(tLocal * 0.41 + ph1)
+ 0.06 * sin(tLocal * 1.07 + ph4);
float mag = baseMag * clamp(magPulse, 0.72, 1.08);
return dir * mag;
}

vec2 sample_turbulence(vec2 cellId, float t) {
float angle = wind_hash21(cellId) * tau + t * 1.5;
vec2 dir = vec2(cos(angle), sin(angle));
float phase = wind_hash21(cellId + vec2(11.3, 47.9)) * tau;
float wave = sin(30.0 * t + phase);
return dir * wave;
}

vec2 bilinear_turbulence(vec2 worldXZ, float cellSize, float t) {
vec2 fp = worldXZ / cellSize;
vec2 base = floor(fp);
vec2 f = smoothstep(0.0, 1.0, fp - base);
vec2 t00 = sample_turbulence(base + vec2(0.0, 0.0), t);
vec2 t10 = sample_turbulence(base + vec2(1.0, 0.0), t);
vec2 t01 = sample_turbulence(base + vec2(0.0, 1.0), t);
vec2 t11 = sample_turbulence(base + vec2(1.0, 1.0), t);
vec2 a = mix(t00, t10, f.x);
vec2 b = mix(t01, t11, f.x);
return mix(a, b, f.y);
}

vec3 get_wind_displacement(vec3 world_pos, float wind_speed, float wind_strength, bool is_tall_plant_top_vertex) {
const float PATCH_SIZE = 6.0;
const float Y_DELAY    = 0.05;
const float AMPLITUDE  = 1.10;

float t = frameTimeCounter * wind_speed * 3.9;

float yLag = max(world_pos.y, 0.0) * Y_DELAY;
float tY = t - yLag;

vec2 fp = world_pos.xz / PATCH_SIZE;
vec2 base = floor(fp);
vec2 f = smoothstep(0.0, 1.0, fp - base);

vec2 w00 = sample_patch_wind(base + vec2(0.0, 0.0), tY);
vec2 w10 = sample_patch_wind(base + vec2(1.0, 0.0), tY);
vec2 w01 = sample_patch_wind(base + vec2(0.0, 1.0), tY);
vec2 w11 = sample_patch_wind(base + vec2(1.0, 1.0), tY);

vec2 w0 = mix(w00, w10, f.x);
vec2 w1 = mix(w01, w11, f.x);
vec2 total = mix(w0, w1, f.y) * AMPLITUDE;

{
vec2 baseAxis = (length(total) > 1e-5) ? normalize(total) : vec2(0.0);

vec2 cellAnchor = floor(world_pos.xz) + 0.5;
vec2 cellId = floor(cellAnchor * 8.0);
float phaseA = wind_hash21(cellId + vec2(11.3, 47.9)) * tau;
float phaseB = wind_hash21(cellId + vec2(73.1,  5.7)) * tau;
float freqA  = 18.0 + wind_hash21(cellId + vec2(1.0,  2.0)) * 12.0;
float freqB  = 11.0 + wind_hash21(cellId + vec2(3.0,  4.0)) *  8.0;
float kick   = 0.6 * sin(freqA * tY + phaseA)
+ 0.4 * sin(freqB * tY + phaseB);
total += baseAxis * kick * AMPLITUDE * 0.15;
}

{
const float CYCLE_LEN  = 6.0;
const float ACTIVE_LEN = 3.0;
vec2 region = floor(world_pos.xz / 10.0);

vec2 gustOffset = vec2(
wind_hash21(region + vec2(21.7,  3.1)),
wind_hash21(region + vec2( 8.9, 55.4))
) * 8.0;
vec2 gustMin = region * 10.0 + gustOffset;

vec2 block_xz = floor(world_pos.xz) + 0.5;
vec2 local = block_xz - gustMin;
if (all(greaterThanEqual(local, vec2(0.0))) && all(lessThan(local, vec2(2.0)))) {

float regionPhase = wind_hash21(region + vec2(2.3, 61.7)) * CYCLE_LEN;
float cyclePos = mod(tY + regionPhase, CYCLE_LEN);
if (cyclePos < ACTIVE_LEN) {

float u = cyclePos / ACTIVE_LEN;
float ampEnv = sin(u * pi);
float flip   = sin(u * tau);

float cycleIdx = floor((tY + regionPhase) / CYCLE_LEN);
float angle = wind_hash21(region + vec2(cycleIdx * 17.0, 91.0)) * tau;
vec2 gustDir = vec2(cos(angle), sin(angle));
total += gustDir * ampEnv * flip * AMPLITUDE * 1.8;
}
}
}

{
const float RCYCLE_LEN  = 20.0;
const float RACTIVE_LEN = 1.5;
const float RWIDTH      = 0.5;

vec2 rregion = floor(world_pos.xz / 30.0);
float rphase = wind_hash21(rregion + vec2(133.7, 91.4)) * RCYCLE_LEN;
float rCyclePos = mod(tY + rphase, RCYCLE_LEN);
if (rCyclePos < RACTIVE_LEN) {
float rIdx = floor((tY + rphase) / RCYCLE_LEN);

vec2 origin = rregion * 30.0 + vec2(
5.0 + wind_hash21(rregion + vec2(rIdx * 13.1, 7.3)) * 20.0,
5.0 + wind_hash21(rregion + vec2(rIdx * 23.7, 3.9)) * 20.0
);

float rAngle = wind_hash21(rregion + vec2(rIdx * 5.1, 77.2)) * tau;
vec2 rDir = vec2(cos(rAngle), sin(rAngle));

float rLen = 3.0 + wind_hash21(rregion + vec2(rIdx * 9.3, 41.0)) * 2.0;

vec2 block_xz = floor(world_pos.xz) + 0.5;
vec2 rel = block_xz - origin;
float alongT = dot(rel, rDir);
float perp   = length(rel - rDir * alongT);

if (alongT >= 0.0 && alongT <= rLen && perp <= RWIDTH) {

float eU = rCyclePos / RACTIVE_LEN;
float rocketFront = eU * rLen;
float dt = abs(alongT - rocketFront);
float wave = exp(-dt * 4.0);

total = rDir * wave * AMPLITUDE * 2.5;
}
}
}

{
const float TCYCLE_LEN  = 25.0;
const float TACTIVE_LEN = 4.0;
const float TRADIUS     = 2.5;

vec2 tregion = floor(world_pos.xz / 40.0);
float tphase = wind_hash21(tregion + vec2(211.3, 47.8)) * TCYCLE_LEN;
float tCyclePos = mod(tY + tphase, TCYCLE_LEN);
if (tCyclePos < TACTIVE_LEN) {
float tIdx = floor((tY + tphase) / TCYCLE_LEN);

vec2 center = tregion * 40.0 + vec2(
TRADIUS + 1.0 + wind_hash21(tregion + vec2(tIdx * 7.1, 11.9)) * (40.0 - 2.0 * (TRADIUS + 1.0)),
TRADIUS + 1.0 + wind_hash21(tregion + vec2(tIdx * 19.3, 83.5)) * (40.0 - 2.0 * (TRADIUS + 1.0))
);
vec2 block_xz = floor(world_pos.xz) + 0.5;
vec2 rel = block_xz - center;
float dist = length(rel);
if (dist < TRADIUS && dist > 0.01) {
vec2 radial = rel / dist;

vec2 tangent = vec2(-radial.y, radial.x);

float spinSign = (wind_hash21(tregion + vec2(tIdx * 31.0, 5.0)) > 0.5) ? 1.0 : -1.0;
tangent *= spinSign;

float eU = tCyclePos / TACTIVE_LEN;
float env = smoothstep(0.0, 0.22, eU) * (1.0 - smoothstep(0.72, 1.0, eU));
float radius01 = dist / TRADIUS;
float ringMask = smoothstep(0.08, 0.32, radius01) * (1.0 - smoothstep(0.82, 1.0, radius01));

float spiralPhase = tY * 10.0 - dist * 7.0 + float(tIdx) * 1.7;
float swirl = sin(spiralPhase);
float swirl2 = cos(spiralPhase * 1.7 + 0.6);
float tangentAmp = 0.80 + 0.35 * swirl;
float radialAmp = 0.28 + 0.22 * swirl2;
vec2 spiralDir = tangent * tangentAmp - radial * radialAmp;
spiralDir = (length(spiralDir) > 1e-5) ? normalize(spiralDir) : tangent;

float spiralBands = 0.65 + 0.35 * sin(spiralPhase * 1.3 + radius01 * 8.0);
float vortexStrength = ringMask * spiralBands;
vec2 vortexTarget = spiralDir * vortexStrength * AMPLITUDE * 2.8;

float tornadoBlend = env * ringMask * 0.9;
total = mix(total, vortexTarget, tornadoBlend);
}
}
}

float stretch = sin(tY * 2.3 + world_pos.x * 0.2 + world_pos.z * 0.2) * 0.25 * length(total);
float yBob = sin(tY * 7.0 + world_pos.x * 0.3 + world_pos.z * 0.3) * 0.06 * length(total);
vec3 result = vec3(total.x, stretch + yBob - 0.04 * length(total), total.y);

if (is_tall_plant_top_vertex) result *= 1.5;

return wind_strength * result;
}

vec3 sample_leaves_patch_wind(vec2 patchId, float t) {
float baseAngle = wind_hash21(patchId + vec2(17.3, 91.4)) * tau;
float rotSpeed = 0.08 + wind_hash21(patchId + vec2(5.7, 23.1)) * 0.06;
float angle = baseAngle + t * rotSpeed;
vec2 dir = vec2(cos(angle), sin(angle));

float phase = wind_hash21(patchId + vec2(3.7, 67.9)) * tau;
float wave = sin(9.0 * t + phase);
float ampMod = 0.7 + 0.3 * sin(t * 0.8 + wind_hash21(patchId + vec2(5.1, 2.3)) * tau);

float pa = wind_hash21(patchId + vec2(41.0, 17.0)) * tau;
vec2 pDir = vec2(cos(pa), sin(pa));
float pFreq = 15.0 + wind_hash21(patchId + vec2(73.1, 5.7)) * 10.0;
float pPhase = wind_hash21(patchId + vec2(3.3, 91.0)) * tau;
float pWave = sin(pFreq * t + pPhase);

float yFreq = 2.0 + wind_hash21(patchId + vec2(29.7, 13.3)) * 2.5;
float yPhase = wind_hash21(patchId + vec2(55.1, 8.9)) * tau;
float yWave = sin(yFreq * t + yPhase);

vec2 xz = dir * wave * ampMod + pDir * pWave * 0.35;
return vec3(xz.x, yWave * 0.30, xz.y);
}

vec3 get_leaves_wind_displacement(vec3 world_pos, float wind_speed, float wind_strength, vec3 mid_block_offset) {
const float PATCH_SIZE = 5.0;
const float Y_DELAY    = 0.015;
const float AMPLITUDE  = 0.44;

const float HORIZ_SCALE = 0.18;

vec3 blockCenter = world_pos + mid_block_offset / 64.0;
wind_strength *= get_waving_distance_boost(blockCenter);

float t = frameTimeCounter * wind_speed * 2.5;
float yLag = max(blockCenter.y, 0.0) * Y_DELAY;
float tY = t - yLag;

vec2 fp = blockCenter.xz / PATCH_SIZE;
vec2 base = floor(fp);
vec2 f = smoothstep(0.0, 1.0, fp - base);

vec3 w00 = sample_leaves_patch_wind(base + vec2(0.0, 0.0), tY);
vec3 w10 = sample_leaves_patch_wind(base + vec2(1.0, 0.0), tY);
vec3 w01 = sample_leaves_patch_wind(base + vec2(0.0, 1.0), tY);
vec3 w11 = sample_leaves_patch_wind(base + vec2(1.0, 1.0), tY);

vec3 w0 = mix(w00, w10, f.x);
vec3 w1 = mix(w01, w11, f.x);
vec3 total3 = mix(w0, w1, f.y) * AMPLITUDE;
total3.xz *= HORIZ_SCALE;

float horizMag = length(total3.xz);
float yBob = sin(tY * 7.0 + blockCenter.x * 0.3 + blockCenter.z * 0.3) * 0.08 * horizMag;
vec3 result = vec3(total3.x, total3.y + yBob - 0.04 * horizMag, total3.z);
return wind_strength * result;
}

vec3 get_player_displacement(vec3 world_pos) {
vec3 to_player = eyePosition - world_pos;
return vec3(
-6.0 * to_player.xz * exp2(-length(to_player * vec3(6.0, 2.0, 6.0))),
0.0
).xzy;
}

vec3 get_player_displacement_grass(vec3 world_pos) {

vec2 to_player_xz = (eyePosition - world_pos).xz;
float d = length(to_player_xz);
float t = 1.0 - smoothstep(0.0, GRASS_INTERACTION_RADIUS, d);

float yDist = abs(eyePosition.y - world_pos.y);
float yFade = 1.0 - smoothstep(1.0, 2.5, yDist);

vec2 dir = (d > 1e-4) ? (to_player_xz / d) : vec2(0.0);

float strength = t * t * yFade;
return vec3(-dir * (0.35 * strength), 0.0).xzy;
}

vec3 animate_vertex(vec3 world_pos, bool is_top_vertex, float skylight, int block_id, vec3 mid_block_offset) {
bool disableUnderwaterCropWaving =
isEyeInWater == 1 &&
(block_id == BLOCK_SMALL_PLANTS ||
block_id == BLOCK_TALL_PLANTS_LOWER ||
block_id == BLOCK_TALL_PLANTS_UPPER ||
block_id == BLOCK_GRASS ||
block_id == BLOCK_TALL_GRASS_LOWER ||
block_id == BLOCK_TALL_GRASS_UPPER);
bool attenuateInteriorWaving =
(block_id == BLOCK_SMALL_PLANTS ||
block_id == BLOCK_TALL_PLANTS_LOWER ||
block_id == BLOCK_TALL_PLANTS_UPPER ||
block_id == BLOCK_GRASS ||
block_id == BLOCK_TALL_GRASS_LOWER ||
block_id == BLOCK_TALL_GRASS_UPPER ||
block_id == BLOCK_LEAVES ||
block_id == BLOCK_OAK_LEAVES);

if (disableUnderwaterCropWaving) return world_pos;

float wind_speed    = 0.3 * WAVING_SPEED;

float effectiveSkylight = max(skylight, 0.5);

float rainWaveBoost = mix(1.55, 1.85, rainStrength);
float wind_strength = sqr(effectiveSkylight) * 0.25 * rainWaveBoost * WAVING_INTENSITY;
vec3 blockCenter = world_pos + mid_block_offset / 64.0;
float interiorWaveFactor = attenuateInteriorWaving ? smoothstep(0.0, 14.0 / 15.0, skylight) : 1.0;

float lanternInteriorWaveFactor = 1.0;
wind_speed *= interiorWaveFactor;
wind_strength *= interiorWaveFactor;

#if WAVING_STYLE == 0

vec3 player_disp = vec3(0.0);
#ifdef PLAYER_PLANT_INTERACTION
player_disp = get_player_displacement(blockCenter) * PLAYER_INTERACTION_INTENSITY;
#endif

#ifdef WAVING_PLANTS
if (block_id == BLOCK_SMALL_PLANTS || block_id == BLOCK_GRASS) {
return world_pos + (get_wind_displacement(blockCenter, wind_speed, wind_strength, false) + player_disp) * float(is_top_vertex);
}
if (block_id == BLOCK_TALL_PLANTS_LOWER || block_id == BLOCK_TALL_GRASS_LOWER) {
return world_pos + (get_wind_displacement(blockCenter, wind_speed, wind_strength, false) + player_disp) * float(is_top_vertex);
}
if (block_id == BLOCK_TALL_PLANTS_UPPER || block_id == BLOCK_TALL_GRASS_UPPER) {
vec3 lowerBlockCenter = blockCenter - vec3(0.0, 1.0, 0.0);
vec3 plantPlayerDisp = player_disp;
#ifdef PLAYER_PLANT_INTERACTION
plantPlayerDisp = get_player_displacement(lowerBlockCenter) * PLAYER_INTERACTION_INTENSITY;
#endif
vec3 seamDisp = get_wind_displacement(lowerBlockCenter, wind_speed, wind_strength, false) + plantPlayerDisp;
vec3 topDisp = get_wind_displacement(blockCenter, wind_speed, wind_strength, true) + plantPlayerDisp;
return world_pos + mix(seamDisp, topDisp, float(is_top_vertex));
}
if (block_id == BLOCK_GRASS_BLOCK) {
return world_pos + (get_wind_displacement(blockCenter, wind_speed, wind_strength, false) + player_disp) * float(is_top_vertex);
}
#endif

#ifdef WAVING_LEAVES
if (block_id == BLOCK_LEAVES || block_id == BLOCK_OAK_LEAVES) {
float leafRainBoost = mix(1.35, 1.6, rainStrength);
return world_pos + get_leaves_wind_displacement(world_pos, wind_speed, wind_strength * 0.5 * leafRainBoost, mid_block_offset);
}
#endif

return world_pos;
#else

wind_strength *= get_waving_distance_boost(blockCenter);

vec3 player_disp = vec3(0.0);
vec3 player_disp_grass = vec3(0.0);
#ifdef PLAYER_PLANT_INTERACTION
player_disp = get_player_displacement(blockCenter) * PLAYER_INTERACTION_INTENSITY;
player_disp_grass = get_player_displacement_grass(blockCenter) * GRASS_INTERACTION_INTENSITY;
#endif

#ifdef WAVING_PLANTS
if (block_id == BLOCK_SMALL_PLANTS || block_id == BLOCK_GRASS) {
return world_pos + (get_wind_displacement(blockCenter, wind_speed, wind_strength, false) + player_disp) * float(is_top_vertex);
}
if (block_id == BLOCK_TALL_PLANTS_LOWER || block_id == BLOCK_TALL_GRASS_LOWER) {
return world_pos + (get_wind_displacement(blockCenter, wind_speed, wind_strength, false) + player_disp) * float(is_top_vertex);
}
if (block_id == BLOCK_TALL_PLANTS_UPPER || block_id == BLOCK_TALL_GRASS_UPPER) {
vec3 lowerBlockCenter = blockCenter - vec3(0.0, 1.0, 0.0);
vec3 plantPlayerDisp = player_disp;
#ifdef PLAYER_PLANT_INTERACTION
plantPlayerDisp = get_player_displacement(lowerBlockCenter) * PLAYER_INTERACTION_INTENSITY;
#endif
vec3 seamDisp = get_wind_displacement(lowerBlockCenter, wind_speed, wind_strength, false) + plantPlayerDisp;
vec3 topDisp = get_wind_displacement(blockCenter, wind_speed, wind_strength, true) + plantPlayerDisp;
return world_pos + mix(seamDisp, topDisp, float(is_top_vertex));
}
if (block_id == BLOCK_GRASS_BLOCK) {

float grass_speed = wind_speed * GRASS_WAVING_SPEED;
float grass_strength = wind_strength * GRASS_WAVING_INTENSITY;
return world_pos + (get_wind_displacement(blockCenter, grass_speed, grass_strength, false) + player_disp_grass) * float(is_top_vertex);
}
#endif

#ifdef WAVING_LEAVES
if (block_id == BLOCK_LEAVES || block_id == BLOCK_OAK_LEAVES) {
float leafRainBoost = mix(1.35, 1.6, rainStrength);
return world_pos + get_leaves_wind_displacement(world_pos, wind_speed, wind_strength * 1.5 * leafRainBoost, mid_block_offset);
}
#endif

#ifdef SWAYING_LANTERNS
if (block_id == BLOCK_HANGING_LANTERN || block_id == BLOCK_HANGING_COPPER_LANTERN) {
swing_lantern(world_pos, mid_block_offset, lanternInteriorWaveFactor);
return world_pos;
}
#endif

return world_pos;
#endif
}

#endif
