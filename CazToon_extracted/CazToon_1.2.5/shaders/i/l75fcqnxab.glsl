#ifdef NIGHT_NEBULA_ENABLED

float hash31(vec3 p) {
p = fract(p * 0.1031);
p += dot(p, p.zyx + 31.32);
return fract((p.x + p.y) * p.z);
}

float noise3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);
f = f * f * (3.0 - 2.0 * f);

float a = hash31(i);
float b = hash31(i + vec3(1,0,0));
float c = hash31(i + vec3(0,1,0));
float d = hash31(i + vec3(1,1,0));
float e = hash31(i + vec3(0,0,1));
float g = hash31(i + vec3(1,0,1));
float h = hash31(i + vec3(0,1,1));
float k = hash31(i + vec3(1,1,1));

return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float fbm3D(vec3 p, int octaves) {
float v = 0.0, a = 0.5;
for (int i = 0; i < octaves; i++) {
v += a * noise3D(p);
p *= 2.0; a *= 0.5;
}
return v;
}

vec3 nightNebula(vec3 dir, float time) {
vec3 d = normalize(dir);
float scale = NIGHT_NEBULA_SCALE * 2.0;
float drift = time * NIGHT_NEBULA_SPEED;

vec3 p1 = d * scale + vec3(drift * 0.4, drift * 0.15, 0.0);
vec3 p2 = d * scale * 1.4 + vec3(31.7, 17.3, 5.1) + vec3(-drift * 0.25, drift * 0.35, 0.0);
vec3 p3 = d * scale * 0.3 + vec3(-50.0, 25.0, 12.3) + drift * 0.08;

float large1    = fbm3D(p1, 4);
float large2    = fbm3D(p2, 3);
float colorLayer = fbm3D(p3, 3);

float mask = smoothstep(0.28, 0.60, large1);
mask *= 0.55 + 0.45 * large2;
mask  = max(mask, smoothstep(0.50, 0.80, large1) * 0.5);

float heightFade = smoothstep(-0.05, 0.18, d.y)
* (1.0 - smoothstep(0.88, 1.00, d.y));
mask *= heightFade;

vec3 col1 = vec3(NIGHT_NEBULA_R1, NIGHT_NEBULA_G1, NIGHT_NEBULA_B1);
vec3 col2 = vec3(NIGHT_NEBULA_R2, NIGHT_NEBULA_G2, NIGHT_NEBULA_B2);
vec3 nebulaColor = mix(col1, col2, smoothstep(0.3, 0.7, colorLayer));
nebulaColor += vec3(0.5, 0.4, 0.8) * smoothstep(0.65, 0.85, large1) * 0.35;

return nebulaColor * mask * NIGHT_NEBULA_INTENSITY;
}
#endif

#ifdef METEORS_ENABLED
vec3 fantasyMeteor(vec3 dir, float time) {
dir = normalize(dir);

vec3 result = vec3(0.0);

for (int i = 0; i < 3; i++) {
float slot = float(i);
float cycleBase = 20.0 + hash11(slot * 53.0 + 7.0) * 25.0;
float cycle = floor((time + slot * 137.0) / cycleBase);
float t = mod(time + slot * 137.0, cycleBase);
float duration = 2.5 + hash11(slot * 31.0 + 3.0) * 2.0;

if (t > duration) continue;
float progress = t / duration;

float seed = slot * 53.0 + cycle * 137.0;

float azimuth = hash11(seed + 20.0) * 6.28318;
float elevation = 0.52 + hash11(seed + 30.0) * 0.79;

float speed = METEOR_SPEED * (0.8 + hash11(seed + 50.0) * 0.4);
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
vec3 up = abs(headPos.y) < 0.99 ? vec3(0,1,0) : vec3(1,0,0);
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

float hue = tSeg * 2.0 + hash11(seed + 60.0) * 0.5;
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
