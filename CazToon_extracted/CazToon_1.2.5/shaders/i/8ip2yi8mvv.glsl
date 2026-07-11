#ifdef END_VOID_CLOUDS_ENABLED

float voidCloudNoise3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);

f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

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

float voidCloudFBM(vec3 p) {
float value = 0.0;
float amp = 0.6;
float freq = 1.0;

for (int i = 0; i < 3; i++) {
value += amp * voidCloudNoise3D(p * freq);
freq *= 2.0;
amp *= 0.4;
}
return value;
}

float voidCloudDensity(vec3 worldPos, float cloudTime, float rawTime, float suctionWarp) {
float y = worldPos.y;

float upperBand = smoothstep(60.0, 150.0, y) * smoothstep(400.0, 250.0, y);
float lowerBand = smoothstep(0.0, -60.0, y) * smoothstep(-300.0, -180.0, y);
float heightDensity = max(upperBand, lowerBand);

float horizDist = length(worldPos.xz);
float clearingMask = smoothstep(END_VOID_CLOUD_CLEARING * 80.0,
END_VOID_CLOUD_CLEARING * 300.0, horizDist);

if (heightDensity < 0.01 || clearingMask < 0.01) return 0.0;

float orbitAngle = cloudTime * END_VOID_CLOUD_SWIRL_SPEED * 0.5;
float cosO = cos(orbitAngle);
float sinO = sin(orbitAngle);
vec3 orbitPos = vec3(
worldPos.x * cosO - worldPos.z * sinO,
worldPos.y,
worldPos.x * sinO + worldPos.z * cosO
);

float swirlInput = (y * 0.003 + log(max(horizDist, 1.0)) * 0.4) * END_VOID_CLOUD_SWIRL
+ cloudTime * END_VOID_CLOUD_SWIRL_SPEED;
float cosA = cos(swirlInput);
float sinA = sin(swirlInput);
vec3 swirlPos = vec3(
orbitPos.x * cosA - orbitPos.z * sinA,
orbitPos.y,
orbitPos.x * sinA + orbitPos.z * cosA
);

vec3 noisePos = swirlPos * END_VOID_CLOUD_SCALE * 0.0006
+ vec3(rawTime * END_VOID_CLOUD_SPEED, rawTime * END_VOID_CLOUD_SPEED * 0.3, 0.0);

float n = voidCloudFBM(noisePos);

float density = smoothstep(END_VOID_CLOUD_COVERAGE, END_VOID_CLOUD_COVERAGE + 0.35, n);
density *= heightDensity;
density *= clearingMask;

density *= (1.0 - suctionWarp * 0.9);

return density;
}

float voidCloudLightning(vec3 worldPos, float time) {
float flash = 0.0;

for (int i = 0; i < 4; i++) {
float fi = float(i);

vec3 cellCenter = vec3(
sin(fi * 73.17) * 400.0,
cos(fi * 47.53) * 150.0 + 100.0,
sin(fi * 91.31 + 2.0) * 400.0
);

float cellDist = length(worldPos - cellCenter);
float influence = smoothstep(500.0, 50.0, cellDist);
if (influence < 0.01) continue;

float cyclePeriod = 6.0 + fi * 3.5;
float phase = fi * 17.3 + 5.0;
float cycleTime = mod(time + phase, cyclePeriod);

float pulse1 = smoothstep(0.0, 0.03, cycleTime) * smoothstep(0.12, 0.05, cycleTime);
float pulse2 = smoothstep(0.18, 0.21, cycleTime) * smoothstep(0.30, 0.24, cycleTime);
float lightning = pulse1 + pulse2 * 0.5;

flash += lightning * influence;
}

return flash;
}

vec3 voidCloudLighting(vec3 worldPos, vec3 viewDir, float density, float dist, float time) {
vec3 color1 = vec3(END_VOID_CLOUD_R1, END_VOID_CLOUD_G1, END_VOID_CLOUD_B1);
vec3 color2 = vec3(END_VOID_CLOUD_R2, END_VOID_CLOUD_G2, END_VOID_CLOUD_B2);

float colorVar = voidCloudNoise3D(worldPos * 0.0004 + time * 0.003);
vec3 baseColor = mix(color1, color2, smoothstep(0.3, 0.7, colorVar));

float edgeBright = (1.0 - density) * END_VOID_CLOUD_EDGE_GLOW;

float heightGlow = smoothstep(0.0, 300.0, worldPos.y) * 0.15;
float belowGlow = max(-viewDir.y, 0.0) * 0.15;

vec3 cloudColor = baseColor * (END_VOID_CLOUD_INTENSITY + edgeBright + heightGlow + belowGlow);

vec3 vortexGlow = vec3(0.44, 0.25, 0.95);
float edgeFade = 1.0 - smoothstep(0.0, 0.5, density);
cloudColor = mix(cloudColor, vortexGlow * 0.6, edgeFade * 0.7);

float lightning = voidCloudLightning(worldPos, time);

vec3 lightningColor = vec3(0.7, 0.5, 1.0);
cloudColor += lightningColor * lightning * density * 2.5;

return cloudColor;
}

vec4 endVoidClouds(vec3 worldDir, float cloudTime, float time, vec3 camPos, float maxDist, float suctionWarp) {
vec3 dir = normalize(worldDir);

float innerR = 50.0;
float outerR = 2000.0;
float marchEnd = min(outerR, maxDist);
if (marchEnd <= innerR) return vec4(0.0);

float stepSize = (outerR - innerR) / float(END_VOID_CLOUD_STEPS);

float dither = fract(dot(gl_FragCoord.xy, vec2(0.7548776662, 0.5698402909))) * stepSize;

vec3 accColor = vec3(0.0);
float accAlpha = 0.0;

for (int i = 0; i < END_VOID_CLOUD_STEPS; i++) {
float t = innerR + dither + float(i) * stepSize;
if (t > marchEnd) break;

vec3 samplePos = camPos + dir * t;

float d = voidCloudDensity(samplePos, cloudTime, time, suctionWarp);

if (d > 0.001) {
float sampleAlpha = 1.0 - exp(-d * stepSize * END_VOID_CLOUD_DENSITY * 0.02);

vec3 sampleColor = voidCloudLighting(samplePos, dir, d, t, time);

accColor += sampleColor * sampleAlpha * (1.0 - accAlpha);
accAlpha += sampleAlpha * (1.0 - accAlpha);

if (accAlpha > 0.95) break;
}
}

return vec4(accColor, accAlpha);
}

#endif
