#include "/settings.glsl"

#ifdef LPV_ENABLED

#include "/include/lpv/lpv_common.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

const ivec3 workGroups = ivec3(32, 16, 32);

uniform usampler3D lpvVoxelSampler;

writeonly uniform image3D lpvLightA;
writeonly uniform image3D lpvLightB;

uniform sampler3D lpvLightSamplerA;
uniform sampler3D lpvLightSamplerB;

uniform int frameCounter;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferModelViewInverse;

ivec3 clampToVolume(ivec3 p) {
return clamp(p, ivec3(0), lpvTexelSize - ivec3(1));
}

int getLpvVoxelBlockId(ivec3 texelPos) {
return int(texelFetch(lpvVoxelSampler, clampToVolume(texelPos), 0).r) - 1;
}

bool isLpvVoxelOpaque(ivec3 texelPos) {
return isLpvOpaqueBlock(getLpvVoxelBlockId(texelPos));
}

uint getLpvBlockMask(int blockId) {
const uint openMask = 0x3Fu;
const uint leafMask = 0x33u;

if (blockId < 0) return openMask;
if (isLpvOpaqueBlock(blockId)) return 0u;

if (blockId == 5 || blockId == 82) return leafMask;

return openMask;
}

bool maskBit(uint mask, int bitIndex) {
return ((mask >> bitIndex) & 1u) != 0u;
}

vec3 readLpvHistory(sampler3D lightSampler, ivec3 historyPos) {
return texelFetch(lightSampler, clampToVolume(historyPos), 0).rgb;
}

vec3 getLpvCameraForward() {

return normalize(mat3(gbufferModelViewInverse) * vec3(0.0, 0.0, -1.0));
}

bool shouldCullBehindPlayer(ivec3 pos) {
#ifndef LPV_OPT_BEHIND_PLAYER_CULL
return false;
#else
vec3 sceneCell = (vec3(pos) + vec3(0.5) - lpvHalfSize) * lpvWorldScale;
vec3 absCell = abs(sceneCell);

if (absCell.x + absCell.y + absCell.z <= 16.0) return false;
if (dot(sceneCell, sceneCell) <= 1.0) return false;

return dot(normalize(sceneCell), getLpvCameraForward()) < -0.05;
#endif
}

bool shouldSpreadThisFrame(ivec3 pos) {
#ifndef LPV_OPT_HALF_RATE_SPREADING
return true;
#else
bool backHalf = pos.z >= (lpvTexelSize.z / 2);
bool updateBackHalf = (frameCounter & 1) != 0;
return backHalf == updateBackHalf;
#endif
}

bool shouldCullOutsideRenderDistance(ivec3 pos) {
vec3 centerDist = abs((vec3(pos) + vec3(0.5)) - lpvHalfSize);
float centerDistMax = max(max(centerDist.x, centerDist.y), centerDist.z);
float activeRadius = lpvVolumeSize.x * 0.5 * clamp(LPV_RENDER_DISTANCE, 0.0, 1.0);

return centerDistMax > activeRadius + 2.0;
}

bool canPropagateMasked(uint currentMask, ivec3 neighborPos, ivec3 dir) {
int neighborBlockId = getLpvVoxelBlockId(neighborPos);

if (isLpvOpaqueBlock(neighborBlockId)) return false;

uint neighborMask = getLpvBlockMask(neighborBlockId);

if (dir.x < 0) return maskBit(currentMask, 0) && maskBit(neighborMask, 1);
if (dir.x > 0) return maskBit(currentMask, 1) && maskBit(neighborMask, 0);
if (dir.y < 0) return maskBit(currentMask, 2) && maskBit(neighborMask, 3);
if (dir.y > 0) return maskBit(currentMask, 3) && maskBit(neighborMask, 2);
if (dir.z < 0) return maskBit(currentMask, 4) && maskBit(neighborMask, 5);
if (dir.z > 0) return maskBit(currentMask, 5) && maskBit(neighborMask, 4);

return false;
}

vec3 gatherLight(sampler3D lightSampler, ivec3 historyPos, ivec3 currentPos) {
vec3 sum = vec3(0.0);
int currentBlockId = getLpvVoxelBlockId(currentPos);
uint currentMask = getLpvBlockMask(currentBlockId);

ivec3 dir = ivec3( 1, 0, 0);
if (canPropagateMasked(currentMask, currentPos + dir, dir)) sum += readLpvHistory(lightSampler, historyPos + dir);
dir = ivec3(-1, 0, 0);
if (canPropagateMasked(currentMask, currentPos + dir, dir)) sum += readLpvHistory(lightSampler, historyPos + dir);
dir = ivec3( 0, 1, 0);
if (canPropagateMasked(currentMask, currentPos + dir, dir)) sum += readLpvHistory(lightSampler, historyPos + dir);
dir = ivec3( 0,-1, 0);
if (canPropagateMasked(currentMask, currentPos + dir, dir)) sum += readLpvHistory(lightSampler, historyPos + dir);
dir = ivec3( 0, 0, 1);
if (canPropagateMasked(currentMask, currentPos + dir, dir)) sum += readLpvHistory(lightSampler, historyPos + dir);
dir = ivec3( 0, 0,-1);
if (canPropagateMasked(currentMask, currentPos + dir, dir)) sum += readLpvHistory(lightSampler, historyPos + dir);

float lpvDivisor = 7.0 + 2.0 / (1.0 + 4.0 * max(LPV_RADIUS, 0.01));

lpvDivisor = max(lpvDivisor - 1.0, 6.0005);
return sum / lpvDivisor;
}

void updateLpv(writeonly image3D writeImg, sampler3D readSampler) {
ivec3 pos = ivec3(gl_GlobalInvocationID);
if (any(greaterThanEqual(pos, lpvTexelSize))) return;

if (shouldCullOutsideRenderDistance(pos)) {
imageStore(writeImg, pos, vec4(0.0));
return;
}

ivec3 prevPos = pos
- ivec3(floor(previousCameraPosition / lpvWorldScale))
+ ivec3(floor(cameraPosition / lpvWorldScale));

uint voxelData = texelFetch(lpvVoxelSampler, pos, 0).r;
int blockId = int(voxelData) - 1;

bool isOpaque = blockId >= 0 && isLpvOpaqueBlock(blockId);
if (isOpaque) {
imageStore(writeImg, pos, vec4(0.0));
return;
}

if (shouldCullBehindPlayer(pos)) {
return;
}

vec3 emitColor = vec3(0.0);
vec3 tintColor = vec3(1.0);
float tintTransmission = 1.0;

if (blockId >= 0) {

vec3 rawEmit = getLpvEmitColor(blockId);
emitColor = rawEmit * rawEmit;
tintColor = getLpvTintColor(blockId);
tintTransmission = getLpvTintTransmission(blockId);

#ifdef LPV_DEBUG_GLASS_VOXELS

if (blockId == 64) {
emitColor = vec3(250.0, 0.0, 0.0);
} else if (blockId == 68) {
emitColor = vec3(0.0, 250.0, 0.0);
}
#endif
}

if (!shouldSpreadThisFrame(pos)) {
vec3 historyLight = readLpvHistory(readSampler, prevPos);
imageStore(writeImg, pos, vec4(max(historyLight, emitColor), 1.0));
return;
}

#if LPV_ISOLATION_STAGE <= 1
vec3 propagated = vec3(0.0);
#else
vec3 propagated = gatherLight(readSampler, prevPos, pos);
propagated *= tintColor * tintTransmission;
#endif

vec3 finalLight = propagated + emitColor;

imageStore(writeImg, pos, vec4(finalLight, 1.0));
}

void main() {
if ((frameCounter & 1) == 0) {
updateLpv(lpvLightA, lpvLightSamplerB);
} else {
updateLpv(lpvLightB, lpvLightSamplerA);
}
}

#else

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);
void main() {}

#endif
