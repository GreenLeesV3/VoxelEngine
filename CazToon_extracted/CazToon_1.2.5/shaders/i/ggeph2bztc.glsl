#ifndef SKY_NIGHT_FEATURES_GLSL
#define SKY_NIGHT_FEATURES_GLSL

#ifndef SKY_HASH_DEFINED
#define SKY_HASH_DEFINED

float skyHash11(float p) {
p = fract(p * 0.1031);
p *= p + 33.33;
p *= p + p;
return fract(p);
}

float skyHash21(vec2 p) {
vec3 p3 = fract(vec3(p.xyx) * 0.1031);
p3 += dot(p3, p3.yzx + 33.33);
return fract((p3.x + p3.y) * p3.z);
}

vec2 skyHash22(vec2 p) {
vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
p3 += dot(p3, p3.yzx + 33.33);
return fract((p3.xx + p3.yz) * p3.zy);
}

float skyHash31(vec3 p) {
p = fract(p * 0.1031);
p += dot(p, p.zyx + 31.32);
return fract((p.x + p.y) * p.z);
}
#endif

#ifndef SKY_ROTATE_DEFINED
#define SKY_ROTATE_DEFINED

vec3 skyRotateX(vec3 v, float angle) {
float c = cos(angle); float s = sin(angle);
return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
}

vec3 skyRotateZ(vec3 v, float angle) {
float c = cos(angle); float s = sin(angle);
return vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
}

vec3 skyCelestialRotate(vec3 dir, float sunAng) {
dir = skyRotateZ(dir, radians(sunPathRotation));
dir = skyRotateX(dir, sunAng * 6.28318);
return dir;
}
#endif

vec2 skyCubeProject(vec3 dir) {
vec3 a = abs(dir);
vec2 uv;
float face;
if (a.x >= a.y && a.x >= a.z) {
uv = dir.zy / a.x; face = dir.x > 0.0 ? 0.0 : 1.0;
} else if (a.y >= a.z) {
uv = dir.xz / a.y; face = dir.y > 0.0 ? 2.0 : 3.0;
} else {
uv = dir.xy / a.z; face = dir.z > 0.0 ? 4.0 : 5.0;
}
uv += face * 100.0;
return uv;
}

float skyNoise3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);
f = f * f * (3.0 - 2.0 * f);

float a = skyHash31(i);
float b = skyHash31(i + vec3(1,0,0));
float c = skyHash31(i + vec3(0,1,0));
float d = skyHash31(i + vec3(1,1,0));
float e = skyHash31(i + vec3(0,0,1));
float g = skyHash31(i + vec3(1,0,1));
float h = skyHash31(i + vec3(0,1,1));
float k = skyHash31(i + vec3(1,1,1));

return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float skyFbm3D(vec3 p, int octaves) {
float v = 0.0, amp = 0.5;
for (int i = 0; i < octaves; i++) {
v += amp * skyNoise3D(p);
p *= 2.0; amp *= 0.5;
}
return v;
}

#ifdef STARS_ENABLED
float skyStarField(vec3 dir, float time, float sunAng) {
dir = normalize(dir);
dir = skyCelestialRotate(dir, sunAng);

vec2 starUV = skyCubeProject(dir) * STAR_SCALE;
vec2 cell = floor(starUV);
vec2 local = fract(starUV);

float star = 0.0;
for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
vec2 nc = cell + vec2(x, y);
float rnd = skyHash21(nc);
if (rnd > STAR_DENSITY) continue;

vec2 sp = skyHash22(nc) * 0.6 + 0.2;
vec2 d = local - vec2(x, y) - sp;
float dist = length(d);

float baseBright = 0.4 + skyHash21(nc + 500.0) * 0.6;
float twinklePhase = skyHash21(nc + 700.0) * 6.28318;
float twinkleSpeed = 0.5 + skyHash21(nc + 800.0) * 2.0;
float twinkle = 0.7 + 0.3 * sin(time * twinkleSpeed + twinklePhase);
float twinkleAmount = skyHash21(nc + 900.0);
twinkle = mix(1.0, twinkle, twinkleAmount * STAR_TWINKLE);

float bright = baseBright * twinkle * STAR_BRIGHTNESS;
float radius = STAR_SIZE * (0.5 + skyHash21(nc + 400.0) * 0.5);
float s = 1.0 - smoothstep(0.0, radius, dist);
star = max(star, s * bright);
}
}
return star;
}
#endif

#ifdef STAR_SHOOTING_ENABLED
vec3 skyShootingStar(vec3 dir, float time, float sunAng) {
dir = normalize(dir);
dir = skyCelestialRotate(dir, sunAng);

vec3 result = vec3(0.0);
for (int i = 0; i < 3; i++) {
float slotOffset = float(i) * 47.0;
float cycleTime = 15.0 + skyHash11(slotOffset) * 20.0;
float t = mod(time + slotOffset, cycleTime);

float duration = 0.5 + skyHash11(slotOffset + 10.0) * 1.0;
if (t > duration) continue;

float startPhi = skyHash11(slotOffset + 20.0) * 6.28318;
float startTheta = 0.2 + skyHash11(slotOffset + 30.0) * 0.6;
vec3 startDir = vec3(cos(startPhi) * cos(startTheta), sin(startTheta), sin(startPhi) * cos(startTheta));

float travelAngle = skyHash11(slotOffset + 40.0) * 6.28318;
vec3 travelDir = normalize(vec3(cos(travelAngle), -0.3, sin(travelAngle)));

float speed = 0.3 + skyHash11(slotOffset + 50.0) * 0.4;
vec3 currentPos = normalize(startDir + travelDir * t * speed);

vec3 toViewer = dir - currentPos;
float along = dot(toViewer, travelDir);
float perpDist = length(toViewer - travelDir * along);

float trailWidth = 0.003;
float trailLength = 0.08 * (1.0 - t / duration);

if (perpDist < trailWidth && along > -trailLength && along < 0.01) {
float intensity = (1.0 - perpDist / trailWidth);
intensity *= smoothstep(-trailLength, 0.0, along);
intensity *= 1.0 - t / duration;
intensity *= STAR_SHOOTING_BRIGHTNESS;
result += vec3(0.9, 0.95, 1.0) * intensity;
}
}
return result;
}
#endif

#ifdef NIGHT_NEBULA_ENABLED
vec3 skyNightNebula(vec3 dir, float time) {
vec3 d = normalize(dir);
float scale = NIGHT_NEBULA_SCALE * 2.0;
float drift = time * NIGHT_NEBULA_SPEED;

vec3 p1 = d * scale + vec3(drift * 0.4, drift * 0.15, 0.0);
vec3 p2 = d * scale * 1.4 + vec3(31.7, 17.3, 5.1) + vec3(-drift * 0.25, drift * 0.35, 0.0);
vec3 p3 = d * scale * 0.3 + vec3(-50.0, 25.0, 12.3) + drift * 0.08;

float large1    = skyFbm3D(p1, 4);
float large2    = skyFbm3D(p2, 3);
float colorLayer = skyFbm3D(p3, 3);

float mask = smoothstep(0.28, 0.60, large1);
mask *= 0.55 + 0.45 * large2;
mask  = max(mask, smoothstep(0.50, 0.80, large1) * 0.5);

float heightFade = smoothstep(-0.05, 0.18, d.y) * (1.0 - smoothstep(0.88, 1.00, d.y));
mask *= heightFade;

vec3 col1 = vec3(NIGHT_NEBULA_R1, NIGHT_NEBULA_G1, NIGHT_NEBULA_B1);
vec3 col2 = vec3(NIGHT_NEBULA_R2, NIGHT_NEBULA_G2, NIGHT_NEBULA_B2);
vec3 nebulaColor = mix(col1, col2, smoothstep(0.3, 0.7, colorLayer));
nebulaColor += vec3(0.5, 0.4, 0.8) * smoothstep(0.65, 0.85, large1) * 0.35;

return nebulaColor * mask * NIGHT_NEBULA_INTENSITY;
}
#endif

#ifdef METEORS_ENABLED
vec3 skyFantasyMeteor(vec3 dir, float time, float sunAng) {
dir = normalize(dir);

vec3 result = vec3(0.0);

for (int i = 0; i < 3; i++) {
float slot = float(i);
float cycleBase = 20.0 + skyHash11(slot * 53.0 + 7.0) * 25.0;
float cycle = floor((time + slot * 137.0) / cycleBase);
float t = mod(time + slot * 137.0, cycleBase);
float duration = 2.5 + skyHash11(slot * 31.0 + 3.0) * 2.0;

if (t > duration) continue;
float progress = t / duration;

float seed = slot * 53.0 + cycle * 137.0;

float azimuth = skyHash11(seed + 20.0) * 6.28318;
float elevation = 0.52 + skyHash11(seed + 30.0) * 0.79;

float speed = METEOR_SPEED * (0.8 + skyHash11(seed + 50.0) * 0.4);
float arcSpeed = speed * 0.15;
float traveled = t * arcSpeed;
float trailArc = min(traveled, 0.8 * METEOR_TRAIL_LENGTH);

float azHead = azimuth + traveled;
float azTail = azimuth + max(traveled - trailArc, 0.0);
float elHead = elevation - traveled * 0.08;
float elTail = elevation - max(traveled - trailArc, 0.0) * 0.08;

vec3 headPos = normalize(vec3(
cos(azHead) * cos(elHead), sin(elHead), sin(azHead) * cos(elHead)
));
vec3 tailPos = normalize(vec3(
cos(azTail) * cos(elTail), sin(elTail), sin(azTail) * cos(elTail)
));

vec3 seg = tailPos - headPos;
float seg2 = dot(seg, seg);
float tSeg = (seg2 > 0.0001) ? clamp(dot(dir - headPos, seg) / seg2, 0.0, 1.0) : 0.0;
vec3 closestPt = normalize(headPos + seg * tSeg);
float angDist = acos(clamp(dot(dir, closestPt), -1.0, 1.0));

float flashIn = smoothstep(0.0, 0.02, progress);
float fadeOut = 1.0 - smoothstep(0.8, 1.0, progress);
float life = flashIn * fadeOut;

float sizeMul = METEOR_SIZE;

float headAng = acos(clamp(dot(dir, headPos), -1.0, 1.0));
if (headAng < 0.06 * sizeMul) {
vec3 up = abs(headPos.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
vec3 tangent = normalize(cross(headPos, up));
vec3 bitangent = cross(headPos, tangent);

vec3 toDir = dir - headPos;
vec2 offset = vec2(dot(toDir, tangent), dot(toDir, bitangent));

float core = exp(-dot(offset, offset) / (0.000003 * sizeMul * sizeMul)) * 3.0;

float spikeH = exp(-abs(offset.x) / (0.0008 * sizeMul)) * exp(-offset.y * offset.y / (0.000004 * sizeMul * sizeMul));
float spikeV = exp(-abs(offset.y) / (0.0008 * sizeMul)) * exp(-offset.x * offset.x / (0.000004 * sizeMul * sizeMul));
float crossFlare = (spikeH + spikeV) * 0.5;

result += vec3(1.0, 0.98, 0.95) * (core + crossFlare) * life * METEOR_BRIGHTNESS;
}

if (angDist < 0.04 * sizeMul && tSeg < 0.5) {
float glowWidth = 0.025 * sizeMul * (1.0 - tSeg * 2.0);
float glow = exp(-angDist * angDist / (glowWidth * glowWidth * 0.5));
glow *= (1.0 - tSeg * 2.0);
vec3 glowCol = vec3(METEOR_GLOW_R, METEOR_GLOW_G, METEOR_GLOW_B);
result += glowCol * glow * 0.8 * life * METEOR_BRIGHTNESS;
}

if (angDist < 0.015 * sizeMul && tSeg < 0.7) {
float bandWidth = 0.012 * sizeMul * (1.0 - tSeg * 1.2);
float band = exp(-angDist * angDist / (bandWidth * bandWidth * 0.3));
band *= (1.0 - tSeg * 1.43);

float hue = tSeg * 2.0 + skyHash11(seed + 60.0) * 0.5;
vec3 rainbow;
rainbow.r = 0.5 + 0.5 * cos(6.28318 * (hue + 0.0));
rainbow.g = 0.5 + 0.5 * cos(6.28318 * (hue + 0.33));
rainbow.b = 0.5 + 0.5 * cos(6.28318 * (hue + 0.67));
rainbow = mix(vec3(1.0), rainbow, 0.7);

result += rainbow * band * 0.6 * life * METEOR_BRIGHTNESS;
}

{
float tailWidth = 0.003 * sizeMul;
float tail = exp(-angDist * angDist / (tailWidth * tailWidth * 0.5));
tail *= (1.0 - tSeg);
result += vec3(0.7, 0.7, 0.75) * tail * 0.4 * life * METEOR_BRIGHTNESS;
}
}

return result;
}
#endif

vec3 skyAddNightFeatures(vec3 skyCol, vec3 worldDir, float sunAng, float time, float rain) {
float angle = fract(sunAng);
float isNight = smoothstep(0.55, 0.60, angle) * (1.0 - smoothstep(0.94, 0.98, angle));
float blueHour = smoothstep(0.50, 0.52, angle) * (1.0 - smoothstep(0.55, 0.58, angle));
float rainFade = 1.0 - smoothstep(0.15, 0.70, rain);

#ifdef STARS_ENABLED
{
float nightVis = (isNight + blueHour * 0.5) * rainFade;
if (nightVis > 0.01 && worldDir.y > -0.1) {
float stars = skyStarField(worldDir, time, sunAng);
float horizonFade = smoothstep(-0.1, 0.15, worldDir.y);
skyCol += vec3(stars) * nightVis * horizonFade;

#ifdef STAR_SHOOTING_ENABLED
if (isNight > 0.5) {
skyCol += skyShootingStar(worldDir, time, sunAng) * horizonFade * rainFade;
}
#endif
}
}
#endif

#ifdef NIGHT_NEBULA_ENABLED
{
float nebulaVis = (isNight + blueHour * 0.4) * rainFade;
if (nebulaVis > 0.01) {
skyCol += skyNightNebula(worldDir, time) * nebulaVis;
}
}
#endif

#ifdef METEORS_ENABLED
{
float meteorVis = (isNight + blueHour * 0.3) * rainFade;
if (meteorVis > 0.01 && worldDir.y > -0.05) {
vec3 meteors = skyFantasyMeteor(worldDir, time, sunAng);
float mHorizonFade = smoothstep(-0.05, 0.15, worldDir.y);
skyCol += meteors * meteorVis * mHorizonFade;
}
}
#endif

return skyCol;
}

#endif
