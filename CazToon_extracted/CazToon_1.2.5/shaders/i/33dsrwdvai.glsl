float sampleCombinedDepth(ivec2 texel) {
float depthMC = texelFetch(depthtex0, texel, 0).x;
float depthDH = texelFetch(dhDepthTex, texel, 0).x;
bool validDH = hasValidDHDepth(depthDH);

if (depthMC >= 0.9999 && validDH) {
return depthDH;
}
return depthMC;
}

float linearizeCombinedDepth(ivec2 texel) {
float depthMC = texelFetch(depthtex0, texel, 0).x;
float depthDH = texelFetch(dhDepthTex, texel, 0).x;
bool validDH = hasValidDHDepth(depthDH);

if (depthMC >= 0.9999 && validDH) {
return linearizeDepthDH(depthDH);
}
return linearizeDepth(depthMC);
}

float getOutline(in ivec2 iUv) {
int pixelSize = OUTLINE_PIXEL_SIZE;

ivec2 topRightCorner = iUv - pixelSize;
ivec2 bottomLeftCorner = iUv + pixelSize;

float depthMC = texelFetch(depthtex0, iUv, 0).x;
float depthDH = texelFetch(dhDepthTex, iUv, 0).x;

float mc0 = texelFetch(depthtex0, topRightCorner, 0).x;
float mc1 = texelFetch(depthtex0, bottomLeftCorner, 0).x;
float mc2 = texelFetch(depthtex0, ivec2(topRightCorner.x, bottomLeftCorner.y), 0).x;
float mc3 = texelFetch(depthtex0, ivec2(bottomLeftCorner.x, topRightCorner.y), 0).x;

float dh0 = texelFetch(dhDepthTex, topRightCorner, 0).x;
float dh1 = texelFetch(dhDepthTex, bottomLeftCorner, 0).x;
float dh2 = texelFetch(dhDepthTex, ivec2(topRightCorner.x, bottomLeftCorner.y), 0).x;
float dh3 = texelFetch(dhDepthTex, ivec2(bottomLeftCorner.x, topRightCorner.y), 0).x;

float combinedC = (depthMC >= 0.9999 && hasValidDHDepth(depthDH)) ? depthDH : depthMC;
float combined0 = (mc0 >= 0.9999 && hasValidDHDepth(dh0)) ? dh0 : mc0;
float combined1 = (mc1 >= 0.9999 && hasValidDHDepth(dh1)) ? dh1 : mc1;
float combined2 = (mc2 >= 0.9999 && hasValidDHDepth(dh2)) ? dh2 : mc2;
float combined3 = (mc3 >= 0.9999 && hasValidDHDepth(dh3)) ? dh3 : mc3;

float zC = (depthMC >= 0.9999 && hasValidDHDepth(depthDH))
? linearizeDepthDH(depthDH)
: linearizeDepth(depthMC);

bool centerIsMC = depthMC < 0.9999;
bool centerIsDH = depthMC >= 0.9999 && hasValidDHDepth(depthDH);

bool neighbor0IsMC = mc0 < 0.9999;
bool neighbor1IsMC = mc1 < 0.9999;
bool neighbor2IsMC = mc2 < 0.9999;
bool neighbor3IsMC = mc3 < 0.9999;

bool neighbor0IsDH = mc0 >= 0.9999 && hasValidDHDepth(dh0);
bool neighbor1IsDH = mc1 >= 0.9999 && hasValidDHDepth(dh1);
bool neighbor2IsDH = mc2 >= 0.9999 && hasValidDHDepth(dh2);
bool neighbor3IsDH = mc3 >= 0.9999 && hasValidDHDepth(dh3);

if (centerIsMC) {

if (neighbor0IsDH || neighbor1IsDH || neighbor2IsDH || neighbor3IsDH) {
return 0.0;
}
}

if (centerIsDH) {

if (neighbor0IsMC || neighbor1IsMC || neighbor2IsMC || neighbor3IsMC) {
return 0.0;
}

float zCenter = linearizeDepthDH(depthDH);
float maxZ = zCenter;
float minZ = zCenter;

if (neighbor0IsDH) { float z = linearizeDepthDH(dh0); maxZ = max(maxZ, z); minZ = min(minZ, z); }
if (neighbor1IsDH) { float z = linearizeDepthDH(dh1); maxZ = max(maxZ, z); minZ = min(minZ, z); }
if (neighbor2IsDH) { float z = linearizeDepthDH(dh2); maxZ = max(maxZ, z); minZ = min(minZ, z); }
if (neighbor3IsDH) { float z = linearizeDepthDH(dh3); maxZ = max(maxZ, z); minZ = min(minZ, z); }

if (maxZ - minZ > 100.0) {
return 0.0;
}
}

#if OUTLINES == 1
float depth0 = near / (1.0 - combined0);
float depth1 = near / (1.0 - combined1);
float depth2 = near / (1.0 - combined2);
float depth3 = near / (1.0 - combined3);

float sumDepth = depth0 + depth1 + depth2 + depth3;
return saturate(sumDepth - (near * 4.0) / (1.0 - combinedC));
#else
float z0 = (neighbor0IsDH) ? linearizeDepthDH(dh0) : linearizeDepth(mc0);
float z1 = (neighbor1IsDH) ? linearizeDepthDH(dh1) : linearizeDepth(mc1);
float z2 = (neighbor2IsDH) ? linearizeDepthDH(dh2) : linearizeDepth(mc2);
float z3 = (neighbor3IsDH) ? linearizeDepthDH(dh3) : linearizeDepth(mc3);

float dz0 = z0 - zC;
float dz1 = z1 - zC;
float dz2 = z2 - zC;
float dz3 = z3 - zC;

float maxBehind = max(max(max(dz0, dz1), dz2), dz3);

float diagonal1 = abs(dz0 - dz1);
float diagonal2 = abs(dz2 - dz3);
float edgeness = max(diagonal1, diagonal2);

float rel = maxBehind / max(zC, 1.0);
float edgeRel = edgeness / max(zC, 1.0);

return smoothstep(0.10, 0.22, rel) * smoothstep(0.05, 0.12, edgeRel);
#endif
}

float getDHGreenOutlineMask(vec3 c, bool isDhPixel) {
if (!isDhPixel) return 1.0;
vec3 col = clamp(c, vec3(0.0), vec3(1.0));
vec3 hsv = rgb2hsv(col);
float greenDominance = col.g - max(col.r, col.b);
float greenRatio = col.g / max(0.0001, (col.r + col.b) * 0.5);
float hueDist = abs(hsv.x - 0.3333333);
hueDist = min(hueDist, 1.0 - hueDist);
float hueMask = 1.0 - smoothstep(0.10, 0.18, hueDist);
float satMask = smoothstep(0.28, 0.60, hsv.y);
float valMask = smoothstep(0.08, 0.35, hsv.z);
float domMask = smoothstep(0.06, 0.18, greenDominance);
float ratioMask = smoothstep(1.15, 1.75, greenRatio);
float greenMask = hueMask * satMask * valMask * domMask * ratioMask;
return 1.0 - clamp(greenMask, 0.0, 1.0);
}
