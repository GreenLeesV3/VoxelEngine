#ifndef LPV_SAMPLE_GLSL
#define LPV_SAMPLE_GLSL

#include "/include/lpv/lpv_common.glsl"

#ifdef LPV_ENABLED

uniform sampler3D lpvLightSamplerA;
uniform sampler3D lpvLightSamplerB;
uniform usampler3D lpvVoxelSampler;

vec3 readLpvTexel(ivec3 voxel) {
ivec3 clampedVoxel = clamp(voxel, ivec3(0), lpvTexelSize - ivec3(1));
if ((frameCounter & 1) == 0) {
return texelFetch(lpvLightSamplerA, clampedVoxel, 0).rgb;
} else {
return texelFetch(lpvLightSamplerB, clampedVoxel, 0).rgb;
}
}

vec3 readLpvFilteredTap(vec3 uv) {

vec3 voxelPos = clamp(uv * lpvVolumeSize, vec3(0.0), lpvVolumeSize - vec3(0.0001));
ivec3 posTX = ivec3(voxelPos);
vec3 texPos = voxelPos - vec3(0.5);
ivec3 base = ivec3(floor(texPos));
vec3 frac = fract(texPos);

vec3 lightVolume = vec3(0.0);
float lightDivide = 0.0;

for (int x = 0; x <= 1; x++) {
for (int y = 0; y <= 1; y++) {
for (int z = 0; z <= 1; z++) {
ivec3 offset = ivec3(x, y, z);
ivec3 newPos = clamp(base + offset, ivec3(0), lpvTexelSize - ivec3(1));

ivec3 realOffset = newPos - posTX;
ivec3 absRealOffset = abs(realOffset);
int totalRealOffset = absRealOffset.x + absRealOffset.y + absRealOffset.z;

if (totalRealOffset == 2) {
bool isReachable = false;
if (realOffset.x != 0 && !isLpvOpaqueBlock(int(texelFetch(lpvVoxelSampler, clamp(posTX + ivec3(realOffset.x, 0, 0), ivec3(0), lpvTexelSize - ivec3(1)), 0).r) - 1)) isReachable = true;
if (realOffset.y != 0 && !isLpvOpaqueBlock(int(texelFetch(lpvVoxelSampler, clamp(posTX + ivec3(0, realOffset.y, 0), ivec3(0), lpvTexelSize - ivec3(1)), 0).r) - 1)) isReachable = true;
if (realOffset.z != 0 && !isLpvOpaqueBlock(int(texelFetch(lpvVoxelSampler, clamp(posTX + ivec3(0, 0, realOffset.z), ivec3(0), lpvTexelSize - ivec3(1)), 0).r) - 1)) isReachable = true;
if (!isReachable) continue;
} else if (totalRealOffset == 3) {
continue;
}

if (isLpvOpaqueBlock(int(texelFetch(lpvVoxelSampler, newPos, 0).r) - 1)) continue;

vec3 w3 = mix(vec3(1.0) - frac, frac, vec3(offset));
float weight = w3.x * w3.y * w3.z;

lightVolume += weight * readLpvTexel(newPos);
lightDivide += weight;
}
}
}

if (lightDivide > 0.0) lightVolume /= lightDivide;
return lightVolume;
}

vec3 readLpvNearestTap(vec3 uv) {
ivec3 voxel = clamp(ivec3(floor(uv * lpvVolumeSize)), ivec3(0), lpvTexelSize - ivec3(1));
return readLpvTexel(voxel);
}

int readLpvVoxelBlockId(vec3 uv) {
ivec3 voxel = clamp(ivec3(floor(uv * lpvVolumeSize)), ivec3(0), lpvTexelSize - ivec3(1));
return int(texelFetch(lpvVoxelSampler, voxel, 0).r) - 1;
}

bool isLpvOpaqueAt(vec3 uv) {
int blockId = readLpvVoxelBlockId(uv);
return blockId >= 0 && isLpvOpaqueBlock(blockId);
}

vec3 readLpvUnifiedBlurred(vec3 texCoord, vec3 worldNormal) {
vec3 step3D = vec3(1.0) / lpvVolumeSize;
vec3 normal = normalize(worldNormal);
vec3 filteredCoord = clamp(
texCoord + normal * step3D * 0.55,
step3D * 0.5,
vec3(1.0) - step3D * 0.5
);
return readLpvFilteredTap(filteredCoord);
}

vec3 sampleLpvLight(vec3 worldPos, vec3 worldNormal, float vanillaIntensity) {
vec3 normalAbs = abs(worldNormal);
vec3 pixelatedWorldPos = worldPos;
float facePixelSize = 1.0 / 16.0;

if (normalAbs.x > normalAbs.y && normalAbs.x > normalAbs.z) {
pixelatedWorldPos.y = (floor(worldPos.y / facePixelSize) + 0.5) * facePixelSize;
pixelatedWorldPos.z = (floor(worldPos.z / facePixelSize) + 0.5) * facePixelSize;
} else if (normalAbs.y > normalAbs.z) {
pixelatedWorldPos.x = (floor(worldPos.x / facePixelSize) + 0.5) * facePixelSize;
pixelatedWorldPos.z = (floor(worldPos.z / facePixelSize) + 0.5) * facePixelSize;
} else {
pixelatedWorldPos.x = (floor(worldPos.x / facePixelSize) + 0.5) * facePixelSize;
pixelatedWorldPos.y = (floor(worldPos.y / facePixelSize) + 0.5) * facePixelSize;
}

vec3 scenePos = pixelatedWorldPos - cameraPosition;
vec3 offsetPos = scenePos + worldNormal * 0.5;
vec3 voxelPos = sceneToVoxelSpace(offsetPos, cameraPosition);

if (!isInVoxelVolume(voxelPos)) return vec3(0.0);

vec3 texCoord = voxelPos / lpvVolumeSize;

#if LPV_ISOLATION_STAGE >= 3
vec3 lpvRaw = readLpvUnifiedBlurred(texCoord, worldNormal);
#else
vec3 lpvRaw = readLpvNearestTap(texCoord);
#endif
vec3 compressedLight = compressRawLpvLight(lpvRaw);
float compressedLuma = getLpvLuma(compressedLight);

#if LPV_ISOLATION_STAGE >= 4

float vanillaGate = mix(0.28, 1.0, pow(clamp(vanillaIntensity, 0.0, 1.0), 0.72));
float lpvRadiusGate = smoothstep(0.010, 0.090, compressedLuma);
float spreadGate = max(vanillaGate, lpvRadiusGate * 0.95);
vec3 finalLight = compressedLight * 0.145 * spreadGate;
#else
vec3 finalLight = compressedLight * 0.145;
#endif

vec3 centerDist = abs(voxelPos - lpvVolumeSize * 0.5);
float centerDistMax = max(max(centerDist.x, centerDist.y), centerDist.z);
float renderRadius = lpvVolumeSize.x * 0.5 * LPV_RENDER_DISTANCE;
float fadeStart = max(renderRadius - LPV_FADE_OUT_DISTANCE, 0.0);
float renderFade = 1.0 - smoothstep(fadeStart, renderRadius, centerDistMax);
renderFade = sqrt(max(renderFade, 0.0));

vec3 edgeDist = min(voxelPos, lpvVolumeSize - voxelPos);
float minEdge = min(min(edgeDist.x, edgeDist.y), edgeDist.z);
float edgeFade = smoothstep(0.0, 8.0, minEdge);

float finalLuma = max(dot(finalLight, vec3(0.299, 0.587, 0.114)), 0.0);
finalLight = mix(vec3(finalLuma), finalLight, LPV_VIBRANCY);

finalLight *= edgeFade * renderFade * LPV_STRENGTH;
finalLight = softCapLpvLight(finalLight, 0.09, 0.05);

return finalLight;
}

vec3 sampleLpvLight(vec3 worldPos, vec3 worldNormal) {
return sampleLpvLight(worldPos, worldNormal, 1.0);
}

#ifdef LEAF_VOXEL_SHADOW_ENABLED
float sampleLeafVoxelShadow(vec3 blockCenterWorld, vec3 worldLightDir, vec3 worldNormal) {
float stepLen = float(LEAF_VOXEL_SHADOW_DISTANCE) / float(LEAF_VOXEL_SHADOW_STEPS);

vec3 scenePos = (blockCenterWorld - cameraPosition) + worldLightDir * stepLen;

float density = 0.0;
for (int i = 0; i < LEAF_VOXEL_SHADOW_STEPS; i++) {
vec3 samplePos = scenePos + worldLightDir * (stepLen * float(i));
vec3 voxelPos = sceneToVoxelSpace(samplePos, cameraPosition);
if (!isInVoxelVolume(voxelPos)) break;
ivec3 texel = voxelToTexel(voxelPos);
int bid = int(texelFetch(lpvVoxelSampler, texel, 0).r) - 1;
if (bid == 5 || bid == 82) {
density += 1.0;
}
}
float opticalDepth = density * stepLen * float(LEAF_VOXEL_SHADOW_DENSITY);
float transmit = exp(-opticalDepth);
return mix(float(LEAF_VOXEL_SHADOW_FLOOR), 1.0, transmit);
}
#endif

#endif
#endif
