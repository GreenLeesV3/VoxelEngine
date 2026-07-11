#ifndef LPV_COMMON_GLSL
#define LPV_COMMON_GLSL

#include "/settings.glsl"

#ifdef LPV_ENABLED

const int lpvSize = LPV_VOLUME_SIZE;
const int lpvHeight = LPV_VOLUME_HEIGHT;
const ivec3 lpvTexelSize = ivec3(LPV_VOLUME_SIZE, LPV_VOLUME_HEIGHT, LPV_VOLUME_SIZE);
const vec3 lpvVolumeSize = vec3(lpvTexelSize);
const vec3 lpvHalfSize = lpvVolumeSize * 0.5;
const float lpvWorldScale = LPV_WORLD_SCALE;

float getLpvLuma(vec3 color) {
return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 compressRawLpvLight(vec3 rawLight) {
vec3 lpvColor = sqrt(max(rawLight, vec3(0.0)));
float rawLuma = getLpvLuma(lpvColor);
if (rawLuma <= 0.0001) return vec3(0.0);

vec3 hue = lpvColor / rawLuma;
float compressedLuma = rawLuma / (1.0 + rawLuma * 0.30);
return hue * compressedLuma;
}

vec3 softCapLpvLight(vec3 light, float knee, float headroom) {
float luma = getLpvLuma(light);
if (luma <= knee || headroom <= 0.0) return light;

float over = luma - knee;
float cappedLuma = knee + (over * headroom) / (over + headroom);
return light * (cappedLuma / max(luma, 0.0001));
}

uint buildLpvMask(uint west, uint east, uint down, uint up, uint north, uint south) {
return west | (east << 1) | (down << 2) | (up << 3) | (north << 4) | (south << 5);
}

vec3 sceneToVoxelSpace(vec3 scenePos, vec3 camPos) {
return scenePos / lpvWorldScale + fract(camPos / lpvWorldScale) + lpvHalfSize;
}

bool isInVoxelVolume(vec3 voxelPos) {
return all(greaterThanEqual(voxelPos, vec3(0.0))) &&
all(lessThan(voxelPos, lpvVolumeSize));
}

ivec3 voxelToTexel(vec3 voxelPos) {
return clamp(ivec3(voxelPos), ivec3(0), lpvTexelSize - ivec3(1));
}

#define LPV_FIRE_COLOR        (vec3(2.25, 0.83, 0.27) * 3.7)

#define LPV_LAVA_COLOR        (vec3(2.20, 1.20, 0.30) * 1.4)
#define LPV_NETHER_PORTAL_COL (vec3(1.80, 0.40, 2.20) * 0.8)
#define LPV_REDSTONE_COLOR    (vec3(4.00, 0.10, 0.10))
#define LPV_SOUL_FIRE_COLOR   (vec3(0.30, 2.00, 2.20) * 2.0)
#define LPV_CANDLE_COLOR      (vec3(2.00, 1.30, 0.24))
#define LPV_CANDLE_MULT       (4.5)

#define LPV_TORCH_COLOR       (vec3(1.80, 1.30, 0.50) * 8.4)

vec3 getLpvLightBlockEmit(float level) {
float radiusBlocks = clamp(level, 1.0, 15.0);

float perLevelReach = 0.78;
float radiusScale = pow(perLevelReach, 15.0 - radiusBlocks);
return vec3(1.0) * 21.0 * radiusScale;
}

vec3 getLpvEmitColor(int blockId) {

if (blockId == 6) return LPV_TORCH_COLOR;

if (blockId == 20) return LPV_TORCH_COLOR;

if (blockId == 21) return LPV_SOUL_FIRE_COLOR;

if (blockId == 22) return LPV_FIRE_COLOR;

if (blockId == 23) return vec3(1.8, 1.4, 0.2) * 4.0;

if (blockId == 24) return vec3(1.5, 1.8, 2.2) * 12.0;

if (blockId == 25) return vec3(3.0, 0.9, 0.2) * 3.0;

if (blockId == 26) return vec3(1.9, 1.45, 0.45) * 12.0;

if (blockId == 27) return vec3(1.1, 0.85, 0.35) * 5.0;

if (blockId == 28) return vec3(0.6, 1.3, 0.6) * 4.5;

if (blockId == 29) return vec3(1.1, 0.5, 0.9) * 4.5;

if (blockId == 30) return getLpvLightBlockEmit(15.0);

if (blockId == 31) return vec3(1.0, 1.0, 1.0) * 4.0;

if (blockId >= 101 && blockId <= 114) return getLpvLightBlockEmit(float(blockId - 100));

if (blockId == 32) return vec3(1.5, 1.8, 2.2) * 12.0;
if (blockId == 33) return vec3(1.0, 1.0, 1.0) * 4.0;
if (blockId == 34) return vec3(0.25, 1.2, 0.25) * 1.0;
if (blockId == 35) return vec3(1.9, 1.45, 0.45) * 12.0;
if (blockId == 36) return LPV_TORCH_COLOR;
if (blockId == 37) return vec3(1.6, 1.35, 0.25) * 2.2;
if (blockId == 38) return LPV_REDSTONE_COLOR;
if (blockId == 39) return LPV_LAVA_COLOR;
if (blockId == 40) return vec3(3.0, 0.9, 0.2) * 3.0;
if (blockId == 41) return vec3(2.5, 1.2, 0.4) * 0.1;
if (blockId == 42) return LPV_FIRE_COLOR;
if (blockId == 43) return LPV_SOUL_FIRE_COLOR;
if (blockId == 44) return vec3(0.7, 1.5, 2.0) * 3.0;
if (blockId == 45) return vec3(0.0, 1.4, 1.4) * 4.0;
if (blockId == 46) return vec3(0.1, 0.3, 0.4) * 0.5;
if (blockId == 47) return LPV_NETHER_PORTAL_COL;
if (blockId == 48) return vec3(0.7, 1.5, 1.5) * 1.7;
if (blockId == 49) return vec3(3.0, 0.9, 0.2) * 0.125;
if (blockId == 50) return LPV_CANDLE_COLOR * 0.25 * LPV_CANDLE_MULT;
if (blockId == 51) return vec3(1.1, 0.85, 0.35) * 5.0;
if (blockId == 52) return vec3(0.6, 1.3, 0.6) * 4.5;
if (blockId == 53) return vec3(1.1, 0.5, 0.9) * 4.5;
if (blockId == 54) return vec3(1.4, 1.1, 0.5);
if (blockId == 55) return vec3(0.325, 0.15, 0.425) * 2.0;
if (blockId == 56) return vec3(0.1, 0.3, 0.4) * 0.5;
if (blockId == 57) return vec3(0.1, 0.3, 0.4) * 0.5;
if (blockId == 58) return LPV_REDSTONE_COLOR * 4.0;
if (blockId == 59) return vec3(0.957, 0.957, 0.478) * 24.0;
if (blockId == 83) return vec3(0.957, 0.957, 0.478) * 12.0;
if (blockId == 84) return vec3(0.957, 0.957, 0.478) *  6.0;

if (blockId == 95) return vec3(0.5, 1.4, 1.7) * 2.5;

if (blockId == 96) return vec3(0.4, 1.5, 0.5) * 1.8;

if (blockId == 97) return vec3(2.0, 0.7, 1.2) * 3.5;

if (blockId == 88) return LPV_NETHER_PORTAL_COL * 2.0;
if (blockId == 63) return vec3(0.0, 1.4, 1.4) * 4.0;
if (blockId == 85) return vec3(0.65, 0.35, 0.95) * 0.3;
if (blockId == 86) return LPV_REDSTONE_COLOR * 0.05;
if (blockId == 87) return vec3(0.1, 2.5, 0.1) * 3.6;
if (blockId == 89) return vec3(0.1, 2.5, 0.1) * 3.6;

return vec3(0.0);
}

vec3 shapeLpvGlassTint(vec3 tint) {
float maxTint = max(max(tint.r, tint.g), tint.b);
if (maxTint <= 0.0001) return vec3(1.0);

tint /= maxTint;

float tintLum = dot(tint, vec3(0.299, 0.587, 0.114));
tint = mix(vec3(tintLum), tint, GLASS_FILTER_SATURATION);
tint = clamp(tint, vec3(0.0), vec3(1.0));

tint = pow(tint, vec3(1.35));

return clamp(tint, vec3(0.0), vec3(1.0));
}

vec3 getLpvTintColor(int blockId) {
if (blockId < 64 || blockId > 79) return vec3(1.0);

if (blockId == 64) return shapeLpvGlassTint(vec3(1.0, 0.1, 0.1));
if (blockId == 65) return shapeLpvGlassTint(vec3(1.0, 0.3, 0.1));
if (blockId == 66) return shapeLpvGlassTint(vec3(1.0, 1.0, 0.1));
if (blockId == 67) return shapeLpvGlassTint(vec3(1.0, 0.75, 0.5));
if (blockId == 68) return shapeLpvGlassTint(vec3(0.3, 1.0, 0.3));
if (blockId == 69) return shapeLpvGlassTint(vec3(0.1, 1.0, 0.1));
if (blockId == 70) return shapeLpvGlassTint(vec3(0.1, 0.15, 1.0));
if (blockId == 71) return shapeLpvGlassTint(vec3(0.5, 0.65, 1.0));
if (blockId == 72) return shapeLpvGlassTint(vec3(0.3, 0.8, 1.0));
if (blockId == 73) return shapeLpvGlassTint(vec3(0.7, 0.3, 1.0));
if (blockId == 74) return shapeLpvGlassTint(vec3(1.0, 0.1, 1.0));
if (blockId == 75) return shapeLpvGlassTint(vec3(1.0, 0.4, 1.0));
if (blockId == 76) return vec3(0.05, 0.05, 0.05);
if (blockId == 77) return vec3(1.0);
if (blockId == 78) return vec3(1.0);
if (blockId == 79) return vec3(1.0);
return vec3(1.0);
}

float getLpvTintTransmission(int blockId) {
if (blockId < 64 || blockId > 79) return 1.0;
if (blockId == 76) return 0.10;
if (blockId >= 77 && blockId <= 79) return 1.0;

float tintLuma = dot(getLpvTintColor(blockId), vec3(0.299, 0.587, 0.114));
return mix(0.28, 0.50, clamp(tintLuma, 0.0, 1.0));
}

bool isLpvOpaqueBlock(int blockId) {
if (blockId <= 0) return false;
if (blockId == 1) return false;
if (blockId >= 2 && blockId <= 10) return false;
if (blockId == 14) return false;

if (blockId >= 20 && blockId <= 31) return false;

if (blockId >= 32 && blockId <= 60) return false;
if (blockId >= 64 && blockId <= 80) return false;
if (blockId == 82) return false;
if (blockId == 83) return false;
if (blockId == 84) return false;
if (blockId == 85) return false;
if (blockId == 86) return false;
if (blockId == 87) return false;
if (blockId == 89) return false;
if (blockId >= 90 && blockId <= 93) return false;
if (blockId == 94) return false;
if (blockId >= 95 && blockId <= 97) return false;
if (blockId >= 101 && blockId <= 114) return false;

return true;
}

#endif
#endif
