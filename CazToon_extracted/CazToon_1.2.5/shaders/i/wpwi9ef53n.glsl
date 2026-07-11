#ifdef WATER_DEBUG_COLORS_ENABLED
color.rgb = vec3(1.0, 0.0, 0.0);
color.a = 0.35;
#else

{
float t = frameTimeCounter * 0.4;
vec3 np = vec3(worldPos.xz * 0.6, t);

float n1 = noise3D(np * 1.0 + vec3(t * 0.3, 0.0, 0.0));
float n2 = noise3D(np * 2.0 - vec3(0.0, t * 0.2, 0.0));
float n = n1 * 0.6 + n2 * 0.4;

vec3 deepColor = vec3(0.01, 0.03, 0.08);
vec3 waveColor = vec3(0.06, 0.14, 0.22);
color.rgb = mix(deepColor, waveColor, n);

float ceilingSkyDim = mix(0.15, 1.0, skylight);
color.rgb *= ceilingSkyDim;
}
color.a = WATER_OPACITY;

{
vec2 ceilPixPos = floor(worldPos.xz * 16.0) / 16.0;
float cst = frameTimeCounter * WATER_WAVE_SPEED * 0.15;
vec3 csPos = vec3(ceilPixPos.x, 0.0, ceilPixPos.y) * 0.35;

float csA = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = csPos;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
csA += abs(noise3D(p * freq + cst * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
csA = 1.0 - csA / total;
}
float csB = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = csPos + 5.0;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
csB += abs(noise3D(p * freq + cst * 1.15 * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
csB = 1.0 - csB / total;
}
float ceilCaustic = min(csA, csB);
ceilCaustic = pow(ceilCaustic, 2.0) * 2.5;
ceilCaustic = max(ceilCaustic - 0.15, 0.0) * (1.0 / 0.85);

float ceilSpecNoise = noise3D(vec3(ceilPixPos * 6.0, cst * 0.5)) * 0.6;
ceilCaustic += ceilSpecNoise;
ceilCaustic = floor(ceilCaustic * 5.0 + 0.5) / 5.0;
ceilCaustic = max(ceilCaustic, 0.0);

vec3 ceilSpecColor = getTimelineHorizonColor(sunAngle, 0.2) * 0.05;
float ceilSpecSkyGate = smoothstep(0.5, 0.8, skylight);
color.rgb += ceilSpecColor * ceilCaustic * ceilSpecSkyGate;
}

{
float ceilTexBright = dot(color.rgb, vec3(0.299, 0.587, 0.114));
vec2 ceilTexPixPos = floor(worldPos.xz * 16.0) / 16.0;
float ceilWarp1 = smoothChunkNoise(ceilTexPixPos * 0.3 + vec2(7.1, -3.4));
float ceilWarp2 = smoothChunkNoise(ceilTexPixPos * 0.25 + vec2(-5.8, 11.2));
vec2 ceilWarpedPos = ceilTexPixPos * 0.5 + vec2(ceilWarp1 - 0.5, ceilWarp2 - 0.5) * 2.0;
float ceilTexMask = smoothChunkNoise(ceilWarpedPos + vec2(frameTimeCounter * 0.02, -frameTimeCounter * 0.015));
ceilTexMask *= smoothChunkNoise(ceilWarpedPos * 1.7 + vec2(-frameTimeCounter * 0.03, frameTimeCounter * 0.01) + vec2(13.0, -8.0));
ceilTexMask = smoothstep(0.08, 0.45, ceilTexMask);
float ceilTexFoam = smoothstep(0.10, 0.50, ceilTexBright) * ceilTexMask * 0.15;
float ceilTexDist = length(worldPos.xz - cameraPosition.xz);
float ceilTexDistFade = 1.0 - smoothstep(24.0, 60.0, ceilTexDist);
texFoam = ceilTexFoam * ceilTexDistFade;
}

#ifdef WATER_FOAM_ENABLED
{
float caft = frameTimeCounter;
vec2 cPixPos = floor(worldPos.xz * 16.0) / 16.0;
float cct = caft * WATER_WAVE_SPEED * 0.2;
vec3 ccPos3D = vec3(cPixPos.x, 0.0, cPixPos.y) * 0.35;

float ccA = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = ccPos3D;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
ccA += abs(noise3D(p * freq + cct * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
ccA = 1.0 - ccA / total;
}
float ccB = 0.0;
{
float amp = 1.0, freq = 0.7, total = 0.0;
vec3 p = ccPos3D + 5.0;
for (int i = 0; i < 2; i++) {
p = vec3(p.x * 0.866 - p.z * 0.5, p.y, p.x * 0.5 + p.z * 0.866);
ccB += abs(noise3D(p * freq + cct * 1.15 * (1.0 + float(i) * 0.3)) - 0.5) * amp;
total += amp * 0.5;
amp *= 0.5;
freq *= 2.0;
}
ccB = 1.0 - ccB / total;
}
float ceilAmbCaustic = min(ccA, ccB);
ceilAmbCaustic = pow(ceilAmbCaustic, 2.0) * 2.5;
ceilAmbCaustic = max(ceilAmbCaustic - 0.15, 0.0) * (1.0 / 0.85);

float cCycle = 12.0;
float cGridScale = 0.07;
vec2 cGridPos = worldPos.xz * cGridScale;
vec2 cCellBase = floor(cGridPos);
float cAmbFoam = 0.0;
for (int gx = -1; gx <= 1; gx++) {
for (int gy = -1; gy <= 1; gy++) {
vec2 cell = cCellBase + vec2(float(gx), float(gy));
float h1 = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
float h2 = fract(sin(dot(cell, vec2(269.5, 183.3))) * 43758.5453);
float h3 = fract(sin(dot(cell, vec2(419.2, 371.9))) * 43758.5453);
float cellCycleId = floor((caft + h1 * cCycle) / cCycle);
float h4 = fract(sin(dot(vec2(cellCycleId, h1 * 100.0), vec2(127.1, 311.7))) * 43758.5453);
float h5 = fract(sin(dot(vec2(cellCycleId, h2 * 100.0), vec2(269.5, 183.3))) * 43758.5453);
float patchPhaseRaw = mod(caft + h1 * cCycle, cCycle) / cCycle;
vec2 drift = vec2(h3 - 0.5, h1 - 0.5) * patchPhaseRaw * 0.5;
vec2 center = cell + vec2(0.2 + h4 * 0.6, 0.2 + h5 * 0.6) + drift;
vec2 delta = cGridPos - center;
float angle = atan(delta.y, delta.x);
float deform = 1.0 + 0.2 * sin(angle * 3.0 + h3 * 6.28) + 0.1 * sin(angle * 5.0 + h1 * 6.28);
float dist = length(delta) * deform;
float patchPhase = mod(caft + h1 * cCycle, cCycle) / cCycle;
float maxRadius = 0.45;
float outerRadius = smoothstep(0.0, 0.4, patchPhase) * maxRadius;
float innerRadius = smoothstep(0.3, 0.95, patchPhase) * maxRadius * 1.3;
float outerMask = 1.0 - smoothstep(outerRadius * 0.4, outerRadius, dist);
float innerMask = smoothstep(innerRadius * 0.3, innerRadius, dist);
float patchShape = outerMask * innerMask;
float cellActive = step(0.4, h2);
cAmbFoam = max(cAmbFoam, ceilAmbCaustic * patchShape * cellActive);
}
}
cAmbFoam *= 0.10;
float cAfDist = length(worldPos.xz - cameraPosition.xz);
float cAfDistFade = 1.0 - smoothstep(24.0, 60.0, cAfDist);
texFoam += cAmbFoam * cAfDistFade;
}
#endif

waterReflData.x = 0.5 + texFoam;
waterReflData.y = 1.0;
waterReflData.z = 0.5;
waterReflData.w = 1.0;
#endif
