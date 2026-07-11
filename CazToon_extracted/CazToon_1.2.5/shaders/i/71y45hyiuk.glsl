#ifdef END_SKY_ENABLED

#ifdef END_EVENT_ENABLED
#include "/include/end_event.glsl"
#endif

float endHash21(vec2 p) {
vec3 p3 = fract(vec3(p.xyx) * 0.1031);
p3 += dot(p3, p3.yzx + 33.33);
return fract((p3.x + p3.y) * p3.z);
}

vec2 endHash22(vec2 p) {
vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
p3 += dot(p3, p3.yzx + 33.33);
return fract((p3.xx + p3.yz) * p3.zy);
}

float endHash31(vec3 p) {
p = fract(p * 0.1031);
p += dot(p, p.zyx + 31.32);
return fract((p.x + p.y) * p.z);
}

float endNoise3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);
f = f * f * (3.0 - 2.0 * f);

float a = endHash31(i);
float b = endHash31(i + vec3(1,0,0));
float c = endHash31(i + vec3(0,1,0));
float d = endHash31(i + vec3(1,1,0));
float e = endHash31(i + vec3(0,0,1));
float g = endHash31(i + vec3(1,0,1));
float h = endHash31(i + vec3(0,1,1));
float k = endHash31(i + vec3(1,1,1));

return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float endFbm3D(vec3 p, int octaves) {
float value = 0.0;
float amplitude = 0.5;
float frequency = 1.0;
for (int i = 0; i < octaves; i++) {
value += amplitude * endNoise3D(p * frequency);
frequency *= 2.0;
amplitude *= 0.5;
}
return value;
}

float endVoronoi3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);
float minDist = 1.0;
for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
for (int z = -1; z <= 1; z++) {
vec3 neighbor = vec3(float(x), float(y), float(z));
vec3 point = vec3(endHash31(i + neighbor + vec3(0.0)),
endHash31(i + neighbor + vec3(100.0)),
endHash31(i + neighbor + vec3(200.0)));
float dist = length(neighbor + point - f);
minDist = min(minDist, dist);
}
}
}
return minDist;
}

vec2 endCubeProject(vec3 d) {
vec3 a = abs(d);
if (a.x >= a.y && a.x >= a.z) return d.yz / a.x + vec2(0.0, 2.0) * sign(d.x);
else if (a.y >= a.z) return d.xz / a.y + vec2(4.0, 0.0) * sign(d.y);
else return d.xy / a.z + vec2(0.0, 6.0) * sign(d.z);
}

vec3 endBlendSkyLayers(vec3 horizon, vec3 mid, vec3 zenith, float height, float midH, float zenithH) {
float toMid = clamp((height - 0.0) / midH, 0.0, 1.0);
toMid = toMid * toMid * toMid * (toMid * (toMid * 6.0 - 15.0) + 10.0);
float toZenith = clamp((height - midH) / (zenithH - midH), 0.0, 1.0);
toZenith = toZenith * toZenith * toZenith * (toZenith * (toZenith * 6.0 - 15.0) + 10.0);
vec3 result = mix(horizon, mid, toMid);
result = mix(result, zenith, toZenith);
return result;
}

#ifdef END_STARS_ENABLED
vec3 endStarField(vec3 dir, float time, float suctionWarp) {
dir = normalize(dir);

if (suctionWarp > 0.001) {
float warpStrength = suctionWarp * suctionWarp * 0.85;
vec3 horizDir = normalize(vec3(dir.x, 0.0, dir.z));
float nearZenith = clamp(dir.y, 0.0, 1.0);
float pullAmount = warpStrength * nearZenith;
dir = normalize(mix(dir, horizDir, pullAmount));
}
vec2 starUV = endCubeProject(dir) * STAR_SCALE;
vec2 cell = floor(starUV);
vec2 local = fract(starUV);
vec3 result = vec3(0.0);

for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
vec2 nc = cell + vec2(float(x), float(y));
float rnd = endHash21(nc);
if (rnd > END_STAR_DENSITY) continue;

vec2 sp = endHash22(nc) * 0.6 + 0.2;
vec2 d = local - vec2(float(x), float(y)) - sp;
float dist = length(d);
float baseBright = 0.4 + endHash21(nc + 500.0) * 0.6;
float twinklePhase = endHash21(nc + 700.0) * 6.28318;
float twinkleSpeed = 0.5 + endHash21(nc + 800.0) * 2.0;
float twinkle = 0.7 + 0.3 * sin(time * twinkleSpeed + twinklePhase);
float bright = baseBright * twinkle * END_STAR_BRIGHTNESS;
float radius = STAR_SIZE * (0.5 + endHash21(nc + 400.0) * 0.5);
float s = 1.0 - smoothstep(0.0, radius, dist);

vec3 sColor = vec3(1.0);
if (END_STAR_COLOR_SHIFT > 0.0) {
float colorRnd = endHash21(nc + 1000.0);
vec3 tint;
if (colorRnd < 0.3) tint = vec3(0.7, 0.5, 1.0);
else if (colorRnd < 0.55) tint = vec3(0.4, 0.7, 1.0);
else if (colorRnd < 0.75) tint = vec3(0.3, 0.9, 0.8);
else tint = vec3(1.0, 0.95, 0.9);
sColor = mix(vec3(1.0), tint, END_STAR_COLOR_SHIFT);
}
result = max(result, sColor * s * bright);
}
}
return result;
}
#endif

#ifdef END_NEBULA_ENABLED
vec3 endNebula(vec3 dir, float time) {

vec3 p = normalize(dir) * END_NEBULA_SCALE;
float drift = time * END_NEBULA_SPEED;
vec3 p1 = p + vec3(drift, drift * 0.3, drift * 0.1);
vec3 p2 = p + vec3(-drift * 0.7, drift * 0.5, -drift * 0.2);

float largeClouds = endFbm3D(p1 * 0.6, 5);
float largeClouds2 = endFbm3D(p2 * 0.8 + vec3(50.0, 25.0, 10.0), 4);
float medDetail = endFbm3D(p1 * 1.2 + vec3(100.0, 50.0, 30.0), 4);
float colorLayer = endFbm3D(p * 0.4 + vec3(-30.0, 80.0, 40.0) + drift * 0.3, 3);
float v = endVoronoi3D(p1 * 2.0);

float nebulaMask = smoothstep(0.20, 0.55, largeClouds);
nebulaMask *= 0.5 + 0.5 * smoothstep(0.15, 0.50, largeClouds2);
nebulaMask *= 0.6 + 0.4 * smoothstep(0.25, 0.60, medDetail);
nebulaMask *= 0.6 + 0.4 * (1.0 - smoothstep(0.0, 0.5, v));
float coreGlow = smoothstep(0.50, 0.80, largeClouds) * 0.5;
nebulaMask += coreGlow;

vec3 color1 = vec3(END_NEBULA_R1, END_NEBULA_G1, END_NEBULA_B1);
vec3 color2 = vec3(END_NEBULA_R2, END_NEBULA_G2, END_NEBULA_B2);
float colorMix = smoothstep(0.3, 0.7, colorLayer);
vec3 nebulaColor = mix(color1, color2, colorMix);
vec3 highlight = vec3(0.7, 0.6, 0.9) * smoothstep(0.70, 0.95, largeClouds) * 0.3;

return (nebulaColor * nebulaMask + highlight) * END_NEBULA_INTENSITY;
}
#endif

#ifdef END_AURORA_ENABLED
vec3 endAurora(vec3 dir, float time) {
float elevation = dir.y;
if (elevation < 0.02) return vec3(0.0);

float heightMask = smoothstep(0.02, END_AURORA_HEIGHT * 0.3, elevation)
* smoothstep(END_AURORA_HEIGHT + 0.3, END_AURORA_HEIGHT * 0.5, elevation);
float angle = atan(dir.z, dir.x);

float curtain1 = sin(angle * 3.0 + time * END_AURORA_SPEED * 0.7) * 0.5 + 0.5;
float curtain2 = sin(angle * 5.0 - time * END_AURORA_SPEED * 1.1 + 2.0) * 0.5 + 0.5;
float curtain3 = sin(angle * 7.0 + time * END_AURORA_SPEED * 0.4 + 4.5) * 0.5 + 0.5;
float curtain4 = sin(angle * 2.0 + time * END_AURORA_SPEED * 0.9 + 1.0) * 0.5 + 0.5;

float waveNoise = endNoise3D(vec3(dir.xz * 2.0, time * END_AURORA_SPEED * 0.3));
float wave = sin(elevation * 12.0 + waveNoise * 4.0 + time * END_AURORA_SPEED) * 0.5 + 0.5;
float vertStreak = endNoise3D(vec3(dir.xz * 4.0 + time * 0.05, elevation * 8.0));
vertStreak = smoothstep(0.1, 0.6, vertStreak);

float auroraShape = curtain1 * curtain2 * 0.5 + curtain3 * 0.3 + curtain4 * 0.2;
auroraShape *= wave;
auroraShape *= 0.6 + 0.4 * vertStreak;
auroraShape = pow(auroraShape, 1.5);

vec3 color1 = vec3(END_AURORA_R1, END_AURORA_G1, END_AURORA_B1);
vec3 color2 = vec3(END_AURORA_R2, END_AURORA_G2, END_AURORA_B2);
float colorPhase = sin(angle * 2.0 + time * END_AURORA_SPEED * 0.2) * 0.5 + 0.5;
vec3 auroraColor = mix(color1, color2, colorPhase);

return auroraColor * auroraShape * heightMask * END_AURORA_INTENSITY;
}
#endif

#ifdef END_VOID_PARTICLES_ENABLED
vec3 endVoidParticles(vec3 dir, float time, float suctionWarp) {
dir = normalize(dir);

if (suctionWarp > 0.001) {
float warpStrength = suctionWarp * suctionWarp * 0.85;
vec3 horizDir = normalize(vec3(dir.x, 0.0, dir.z));
float nearZenith = clamp(dir.y, 0.0, 1.0);
float pullAmount = warpStrength * nearZenith;
dir = normalize(mix(dir, horizDir, pullAmount));
}
vec2 particleUV = endCubeProject(dir) * 30.0;
vec2 cell = floor(particleUV);
vec2 local = fract(particleUV);
vec3 result = vec3(0.0);

for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
vec2 nc = cell + vec2(float(x), float(y));
float rnd = endHash21(nc + vec2(200.0, 300.0));
if (rnd > END_VOID_PARTICLE_DENSITY) continue;

vec2 sp = endHash22(nc + vec2(200.0, 300.0)) * 0.6 + 0.2;
float pulsePhase = endHash21(nc + vec2(500.0, 600.0)) * 6.28318;
float pulseSpeed = 0.3 + endHash21(nc + vec2(700.0, 800.0)) * 1.5;
float pulse = 0.5 + 0.5 * sin(time * pulseSpeed + pulsePhase);
float driftX = sin(time * 0.1 + pulsePhase) * 0.02;
float driftY = cos(time * 0.08 + pulsePhase * 1.3) * 0.02;

vec2 d = local - vec2(float(x), float(y)) - sp + vec2(driftX, driftY);
float dist = length(d);
float particle = 1.0 - smoothstep(0.0, 0.04, dist);
particle *= pulse;

float hueRnd = endHash21(nc + vec2(900.0, 100.0));
vec3 pColor = mix(vec3(0.6, 0.2, 1.0), vec3(0.2, 0.8, 0.9), hueRnd);
result += pColor * particle * END_VOID_PARTICLE_BRIGHTNESS * 0.3;
}
}
return result;
}
#endif

#ifdef END_ASTEROIDS_ENABLED

vec3 endWarpStreaks(vec3 dir, float time) {
dir = normalize(dir);
vec3 result = vec3(0.0);

int numSlots = 12;
for (int slot = 0; slot < numSlots; slot++) {
float slotF = float(slot);

float cycleDuration = 8.0 + endHash21(vec2(slotF, 0.0) + vec2(7000.0)) * 12.0;
float activeWindow = 0.6 + endHash21(vec2(slotF, 1.0) + vec2(7100.0)) * 0.8;
float phase = endHash21(vec2(slotF, 2.0) + vec2(7200.0)) * 200.0;

float cycleTime = mod(time * END_ASTEROID_SPEED + phase, cycleDuration);

if (cycleTime > activeWindow) continue;

float lifecycle = cycleTime / activeWindow;

float fadeMask = smoothstep(0.0, 0.1, lifecycle) * smoothstep(1.0, 0.85, lifecycle);
if (fadeMask < 0.001) continue;

float theta = endHash21(vec2(slotF, 3.0) + vec2(7300.0)) * 6.28318;
float phi = endHash21(vec2(slotF, 4.0) + vec2(7400.0)) * 2.8 - 0.4;
vec3 streakCenter = normalize(vec3(cos(theta) * cos(phi), sin(phi), sin(theta) * cos(phi)));

float travelAngle = endHash21(vec2(slotF, 5.0) + vec2(7500.0)) * 6.28318;
float travelElev = (endHash21(vec2(slotF, 6.0) + vec2(7600.0)) - 0.5) * 1.0;
vec3 travelDir = normalize(vec3(cos(travelAngle), travelElev, sin(travelAngle)));

float speed = 0.3 + endHash21(vec2(slotF, 7.0) + vec2(7700.0)) * 0.4;
vec3 currentPos = streakCenter + travelDir * (lifecycle - 0.5) * speed;

float dotToStreak = dot(dir, normalize(currentPos));
float angDist = acos(clamp(dotToStreak, -1.0, 1.0));

if (angDist > END_ASTEROID_LENGTH * 1.5) continue;

vec3 streakDir = normalize(travelDir - dir * dot(travelDir, dir));
float along = dot(dir - normalize(currentPos), streakDir);
float perp = length(dir - normalize(currentPos) - streakDir * along);

float halfLen = END_ASTEROID_LENGTH * (0.4 + endHash21(vec2(slotF, 8.0) + vec2(7800.0)) * 0.6);
float thickness = END_ASTEROID_THICKNESS;

float alongMask = smoothstep(halfLen, halfLen * 0.3, abs(along));
float perpMask = smoothstep(thickness, thickness * 0.15, perp);
float streak = alongMask * perpMask;

float taper = smoothstep(-halfLen, halfLen * 0.2, along);
streak *= taper * fadeMask;

float colorRnd = endHash21(vec2(slotF, 9.0) + vec2(7900.0));
vec3 streakColor;
if (colorRnd < 0.3) streakColor = vec3(0.6, 0.3, 1.0);
else if (colorRnd < 0.55) streakColor = vec3(0.3, 0.7, 1.0);
else if (colorRnd < 0.8) streakColor = vec3(0.8, 0.75, 1.0);
else streakColor = vec3(1.0, 0.95, 1.0);

result += streakColor * streak * END_ASTEROID_BRIGHTNESS;
}

return result;
}
#endif

#include "/include/end_void_clouds.glsl"

#ifdef END_ENDER_PARTICLES_ENABLED

vec3 endEnderParticles(vec3 viewDir, float time, vec3 camPos, float sceneDist) {
vec3 result = vec3(0.0);
float maxDist = min(sceneDist, END_ENDER_PARTICLE_RANGE);

float cellSize = END_ENDER_PARTICLE_SPACING;
float invCell = 1.0 / cellSize;
float stepSize = cellSize * 0.7;
float size = END_ENDER_PARTICLE_SIZE;
float maxBloomRadius = size * 4.5;

vec3 right = normalize(cross(viewDir, vec3(0.0, 1.0, 0.0)));
vec3 up = cross(right, viewDir);

float dither = fract(dot(gl_FragCoord.xy, vec2(0.7548776662, 0.5698402909))) * stepSize;

vec3 lastCell = vec3(-999.0);

for (int i = 0; i < 16; i++) {
float t = 6.0 + dither + float(i) * stepSize;
if (t > maxDist) break;

vec3 worldP = camPos + viewDir * t;
vec3 cellId = floor(worldP * invCell);

if (cellId == lastCell) continue;
lastCell = cellId;

float rnd = endHash31(cellId + vec3(5000.0));
if (rnd > END_ENDER_PARTICLE_DENSITY) continue;

vec3 particlePos = (cellId + vec3(
endHash31(cellId + vec3(100.0)),
endHash31(cellId + vec3(200.0)),
endHash31(cellId + vec3(300.0))
)) * cellSize;

float phase = endHash31(cellId + vec3(400.0)) * 6.28318;
float driftSpeed = 0.3 + endHash31(cellId + vec3(500.0)) * 0.5;
particlePos.x += sin(time * driftSpeed * 0.4 + phase) * 0.8;
particlePos.y += sin(time * driftSpeed * 0.3 + phase * 1.3) * 1.2
+ sin(time * 0.05 + phase * 2.7) * cellSize * 0.4;
particlePos.z += cos(time * driftSpeed * 0.35 + phase * 0.7) * 0.8;

vec3 toParticle = particlePos - camPos;
float projDist = dot(toParticle, viewDir);
if (projDist < 6.0 || projDist > maxDist) continue;

vec3 closest = camPos + viewDir * projDist;
vec3 offset = particlePos - closest;

float ox = abs(dot(offset, right));
float oy = abs(dot(offset, up));
float squareDist = max(ox, oy);
if (squareDist > maxBloomRadius) continue;

float brightVar = endHash31(cellId + vec3(800.0));
float brightMult = brightVar < 0.2 ? (2.0 + brightVar * 5.0) : (0.5 + brightVar * 0.875);

float core = step(squareDist, size);
float bloomRadius = size * (3.0 + brightMult * 1.5);
float bloomGlow = smoothstep(bloomRadius, size * 0.5, squareDist);
bloomGlow *= bloomGlow;
float totalGlow = core + bloomGlow * 0.4 * brightMult;
if (totalGlow < 0.001) continue;

float pulse = 0.5 + 0.5 * sin(time * (1.0 + endHash31(cellId + vec3(600.0))) + phase);

float distFade = smoothstep(maxDist, maxDist * 0.3, projDist)
* smoothstep(6.0, 12.0, projDist);

float hueRnd = endHash31(cellId + vec3(700.0));
vec3 pColor;
if (hueRnd < 0.4) pColor = vec3(0.6, 0.15, 1.0);
else if (hueRnd < 0.7) pColor = vec3(0.9, 0.2, 0.8);
else if (hueRnd < 0.85) pColor = vec3(0.3, 0.5, 1.0);
else pColor = vec3(0.5, 0.8, 1.0);

result += pColor * (pulse * distFade * END_ENDER_PARTICLE_BRIGHTNESS * brightMult * totalGlow);
}

return result;
}
#endif

#ifdef END_RINGS_ENABLED

vec3 endRings(vec3 dir, float time, vec3 camPos, float maxDist) {
dir = normalize(dir);
vec3 baseColor = vec3(END_RINGS_R, END_RINGS_G, END_RINGS_B);
vec3 result = vec3(0.0);

vec3 islandCenter = vec3(0.0, 64.0, 0.0);
float tubeR = END_RINGS_DEPTH * 0.5;

for (int i = 0; i < END_RINGS_COUNT; i++) {
float fi = float(i);

float majorR = END_RINGS_INNER + END_RINGS_WIDTH * 0.5 + fi * (END_RINGS_WIDTH + 20.0);

float orbit = time * END_RINGS_SPEED * (0.8 + fi * 0.2) + fi * 2.094;

float baseTilt = 0.3927 + fi * 0.10;
float tilt = baseTilt * cos(orbit);

vec3 localN = normalize(vec3(sin(tilt), cos(tilt), 0.0));
float cO = cos(orbit);
float sO = sin(orbit);
vec3 axis = vec3(
localN.x * cO,
localN.y,
localN.x * sO
);

float outerBound = majorR + tubeR * 2.0;
vec3 toCenter = camPos - islandCenter;
float b = dot(toCenter, dir);
float c = dot(toCenter, toCenter) - outerBound * outerBound;
float disc = b * b - c;
if (disc < 0.0) continue;
float sqrtDisc = sqrt(disc);
float tNear = max(-b - sqrtDisc, 0.0);
float tFar = min(-b + sqrtDisc, maxDist);
if (tNear >= tFar) continue;

float accum = 0.0;
float stepSize = (tFar - tNear) / 32.0;
float dither = fract(dot(gl_FragCoord.xy, vec2(0.7548776662, 0.5698402909))) * stepSize;

for (int s = 0; s < 32; s++) {
float t = tNear + dither + float(s) * stepSize;
if (t > tFar) break;

vec3 p = camPos + dir * t - islandCenter;

float axisProj = dot(p, axis);
vec3 inPlane = p - axis * axisProj;
float planeDist = length(inPlane);
float toRing = planeDist - majorR;
float d = length(vec2(toRing, axisProj));

float density = smoothstep(tubeR * 2.0, 0.0, d);
density *= density;

accum += density * stepSize;
}

if (accum < 0.001) continue;

float opacity = 1.0 - exp(-accum * 0.25);

float distFade = smoothstep(3000.0, 500.0, (tNear + tFar) * 0.5);

vec3 thisColor = baseColor;
if (i == 1) thisColor = mix(baseColor, vec3(0.3, 0.5, 1.0), 0.25);
if (i == 2) thisColor = mix(baseColor, vec3(0.6, 0.2, 0.9), 0.25);

result += thisColor * opacity * distFade * END_RINGS_BRIGHTNESS;
}

return result;
}
#endif

#include "/include/end_vortex.glsl"

#ifdef END_EVENT_ENABLED
vec3 endBigBangRings(vec3 dir, float bangProgress, float bangFlash) {
if (bangFlash < 0.001 && bangProgress <= 0.0) return vec3(0.0);

vec3 result = vec3(0.0);

float upAmount = max(dir.y, 0.0);
float flashGlow = smoothstep(0.0, 0.8, upAmount) * bangFlash;
result += vec3(0.9, 0.7, 1.0) * flashGlow * 4.0;

if (bangProgress > 0.0 && bangProgress < 1.0) {
float elevAngle = acos(clamp(dir.y, -1.0, 1.0));
for (int i = 0; i < 3; i++) {
float fi = float(i);
float ringDelay = fi * 0.08;
float ringProgress = clamp((bangProgress - ringDelay) / max(1.0 - ringDelay, 0.01), 0.0, 1.0);

float ringExpand = pow(ringProgress, 0.4);
float ringAngle = ringExpand * 3.14159;

float distToRing = abs(elevAngle - ringAngle);
float ringWidth = 0.04 + fi * 0.01;
float ring = smoothstep(ringWidth, ringWidth * 0.15, distToRing);
float ringFade = (1.0 - ringProgress) * (1.0 - fi * 0.2);

vec3 ringColor = mix(vec3(1.0, 0.9, 1.0), vec3(0.5, 0.3, 1.0), fi * 0.3);
result += ringColor * ring * ringFade * 2.5;
}
}

return result;
}
#endif

vec3 renderEndSky(vec3 worldDir, float time, vec3 camPos) {
float height = max(worldDir.y, 0.0);

#ifdef END_EVENT_ENABLED
EndEvent event = getEndEvent(time);

vec3 warpedDir = worldDir;
if (event.suctionWarp > 0.001) {
float warpStrength = event.suctionWarp * event.suctionWarp * 0.85;

vec3 horizonDir = normalize(vec3(worldDir.x, 0.0, worldDir.z));

float nearZenith = clamp(worldDir.y, 0.0, 1.0);
float pullAmount = warpStrength * nearZenith;
warpedDir = normalize(mix(worldDir, horizonDir, pullAmount));
}
#else
vec3 warpedDir = worldDir;
#endif

vec3 horizonColor = vec3(END_SKY_HORIZON_R, END_SKY_HORIZON_G, END_SKY_HORIZON_B);
vec3 midColor = vec3(END_SKY_MID_R, END_SKY_MID_G, END_SKY_MID_B);
vec3 zenithColor = vec3(END_SKY_ZENITH_R, END_SKY_ZENITH_G, END_SKY_ZENITH_B);

vec3 sky = endBlendSkyLayers(horizonColor, midColor, zenithColor, height, 0.25, 0.65);

if (worldDir.y < 0.0) {
float belowFade = smoothstep(0.0, -0.4, worldDir.y);
#ifdef END_FOG_ENABLED
vec3 voidColor = vec3(END_FOG_R, END_FOG_G, END_FOG_B);
#else
vec3 voidColor = horizonColor * 0.3;
#endif
sky = mix(horizonColor, voidColor, belowFade);
}

sky *= END_SKY_BRIGHTNESS;

#ifdef END_EVENT_ENABLED
sky *= (1.0 - event.skyDarkness);
#endif

#ifdef END_STARS_ENABLED
{
#ifdef END_EVENT_ENABLED
vec3 stars = endStarField(warpedDir, time, event.suctionWarp);
sky += stars * event.effectsFade;
#else
sky += endStarField(worldDir, time, 0.0);
#endif
}
#endif
#ifdef END_NEBULA_ENABLED
{
#ifdef END_EVENT_ENABLED
sky += endNebula(warpedDir, time) * event.effectsFade;
#else
sky += endNebula(worldDir, time);
#endif
}
#endif
#ifdef END_AURORA_ENABLED
{
#ifdef END_EVENT_ENABLED
sky += endAurora(warpedDir, time) * event.effectsFade;
#else
sky += endAurora(worldDir, time);
#endif
}
#endif
#ifdef END_VOID_PARTICLES_ENABLED
{
#ifdef END_EVENT_ENABLED
sky += endVoidParticles(warpedDir, time, event.suctionWarp) * event.effectsFade;
#else
sky += endVoidParticles(worldDir, time, 0.0);
#endif
}
#endif
#ifdef END_VOID_CLOUDS_ENABLED
{
#ifdef END_EVENT_ENABLED
vec4 clouds = endVoidClouds(worldDir, event.cloudTime, time, camPos, 10000.0, event.suctionWarp);
#else
vec4 clouds = endVoidClouds(worldDir, time, time, camPos, 10000.0, 0.0);
#endif
if (clouds.a > 0.001) {
vec3 cloudRGB = clouds.rgb / clouds.a;
#ifdef END_EVENT_ENABLED
float cloudAlpha = clouds.a * event.effectsFade;
#else
float cloudAlpha = clouds.a;
#endif
sky = mix(sky, cloudRGB, cloudAlpha);
}
}
#endif
#ifdef END_ASTEROIDS_ENABLED
{
#ifdef END_EVENT_ENABLED
sky += endWarpStreaks(warpedDir, time) * event.effectsFade;
#else
sky += endWarpStreaks(worldDir, time);
#endif
}
#endif
#ifdef END_VORTEX_ENABLED
{
#ifdef END_EVENT_ENABLED
sky += endVortex(worldDir, event.vortexTime, time, event.vortexSizeMult, event.eyeOpen);
#else
sky += endVortex(worldDir, time, time, 1.0, 0.0);
#endif
}
#endif

#ifdef END_EVENT_ENABLED
sky += endBigBangRings(worldDir, event.bangProgress, event.bangFlash);
#endif

return sky;
}

#endif
