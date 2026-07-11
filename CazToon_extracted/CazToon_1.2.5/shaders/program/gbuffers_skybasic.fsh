/* RENDERTARGETS: 0,1 */

#extension GL_ARB_shader_storage_buffer_object : require

#include "/settings.glsl"
#include "/include/color_utils.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/sky_timeline.glsl"

layout(std430, binding = 0) buffer persistentBuffer {
float storedExposure;
float smoothBeach;
float smoothSwamp;
float smoothJungle;
float smoothSnowy;
float smoothArid;
float storedScreenSkylight;
float smoothOcean;
float smoothNetherFogR;
float smoothNetherFogG;
float smoothNetherFogB;
float smoothCaveFogR;
float smoothCaveFogG;
float smoothCaveFogB;
float storedAtmoSceneFactor;
float storedCaveFogTakeover;
float smoothBiomeFogR;
float smoothBiomeFogG;
float smoothBiomeFogB;
float smoothBiomeSkyR;
float smoothBiomeSkyG;
float smoothBiomeSkyB;
float smoothPaleGarden;
};

#define BIOME_COLOR_SMOOTHING_HAS_SSBO
#include "/include/biome_color_smoothing.glsl"

uniform float sunAngle;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform mat4 gbufferModelViewInverse;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int biome;
uniform int biome_category;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_snowy;
uniform float biome_arid;
uniform float biome_savanna;
uniform float biome_ocean;
uniform sampler2D noisetex;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;

in vec3 viewPos;
in vec4 starColor;

float hash11(float p) {
p = fract(p * 0.1031);
p *= p + 33.33;
p *= p + p;
return fract(p);
}

float hash21(vec2 p) {
vec3 p3 = fract(vec3(p.xyx) * 0.1031);
p3 += dot(p3, p3.yzx + 33.33);
return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
p3 += dot(p3, p3.yzx + 33.33);
return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 hash33(vec3 p) {
p = fract(p * vec3(0.1031, 0.1030, 0.0973));
p += dot(p, p.yxz + 33.33);
return fract((p.xxy + p.yxx) * p.zyx);
}

vec3 rotateX(vec3 v, float angle) {
float c = cos(angle);
float s = sin(angle);
return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
}

vec3 rotateY(vec3 v, float angle) {
float c = cos(angle);
float s = sin(angle);
return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

vec3 rotateZ(vec3 v, float angle) {
float c = cos(angle);
float s = sin(angle);
return vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
}

vec3 celestialRotate(vec3 dir) {

float pathTilt = radians(sunPathRotation);
dir = rotateZ(dir, pathTilt);

float dailyRotation = sunAngle * 6.28318;
dir = rotateX(dir, dailyRotation);

return dir;
}

vec2 cubeProject(vec3 dir) {
vec3 absDir = abs(dir);
vec2 uv;
float face;

if (absDir.x >= absDir.y && absDir.x >= absDir.z) {
uv = dir.zy / absDir.x;
face = dir.x > 0.0 ? 0.0 : 1.0;
} else if (absDir.y >= absDir.x && absDir.y >= absDir.z) {
uv = dir.xz / absDir.y;
face = dir.y > 0.0 ? 2.0 : 3.0;
} else {
uv = dir.xy / absDir.z;
face = dir.z > 0.0 ? 4.0 : 5.0;
}

uv += face * 100.0;
return uv;
}

float simplexNoise(vec2 p) {
vec2 i = floor(p);
vec2 f = fract(p);
f = f * f * (3.0 - 2.0 * f);

float a = hash21(i);
float b = hash21(i + vec2(1.0, 0.0));
float c = hash21(i + vec2(0.0, 1.0));
float d = hash21(i + vec2(1.0, 1.0));

return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
float value = 0.0;
float amplitude = 0.5;
float frequency = 1.0;

for (int i = 0; i < octaves; i++) {
value += amplitude * simplexNoise(p * frequency);
amplitude *= 0.5;
frequency *= 2.0;
}

return value;
}

float voronoiNoise(vec2 p) {
vec2 i = floor(p);
vec2 f = fract(p);

float minDist = 1.0;
for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
vec2 neighbor = vec2(float(x), float(y));
vec2 point = hash22(i + neighbor);
vec2 diff = neighbor + point - f;
float d = length(diff);
minDist = min(minDist, d);
}
}
return minDist;
}

float starField(vec3 dir, float time) {
dir = normalize(dir);

dir = celestialRotate(dir);

vec2 starUV = cubeProject(dir) * STAR_SCALE;

vec2 cell = floor(starUV);
vec2 local = fract(starUV);

float star = 0.0;

for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
vec2 nc = cell + vec2(x, y);

float rnd = hash21(nc);
if (rnd > STAR_DENSITY) continue;

vec2 sp = hash22(nc) * 0.6 + 0.2;

vec2 d = local - vec2(x, y) - sp;
float dist = length(d);

float baseBright = 0.4 + hash21(nc + 500.0) * 0.6;

float twinklePhase = hash21(nc + 700.0) * 6.28318;
float twinkleSpeed = 0.5 + hash21(nc + 800.0) * 2.0;
float twinkle = 0.7 + 0.3 * sin(time * twinkleSpeed + twinklePhase);

float twinkleAmount = hash21(nc + 900.0);
twinkle = mix(1.0, twinkle, twinkleAmount * STAR_TWINKLE);

float bright = baseBright * twinkle * STAR_BRIGHTNESS;

float radius = STAR_SIZE * (0.5 + hash21(nc + 400.0) * 0.5);

float s = 1.0 - smoothstep(0.0, radius, dist);
star = max(star, s * bright);
}
}

return star;
}

vec3 shootingStar(vec3 dir, float time) {
dir = normalize(dir);

dir = celestialRotate(dir);

vec3 result = vec3(0.0);

for (int i = 0; i < 3; i++) {

float slotOffset = float(i) * 47.0;
float cycleTime = 15.0 + hash11(slotOffset) * 20.0;
float t = mod(time + slotOffset, cycleTime);

float duration = 0.5 + hash11(slotOffset + 10.0) * 1.0;
if (t > duration) continue;

float startPhi = hash11(slotOffset + 20.0) * 6.28318;
float startTheta = 0.2 + hash11(slotOffset + 30.0) * 0.6;
vec3 startDir = vec3(
cos(startPhi) * cos(startTheta),
sin(startTheta),
sin(startPhi) * cos(startTheta)
);

float travelAngle = hash11(slotOffset + 40.0) * 6.28318;
vec3 travelDir = vec3(cos(travelAngle), -0.3, sin(travelAngle));
travelDir = normalize(travelDir);

float speed = 0.3 + hash11(slotOffset + 50.0) * 0.4;
vec3 currentPos = startDir + travelDir * t * speed;
currentPos = normalize(currentPos);

float angleDist = acos(clamp(dot(dir, currentPos), -1.0, 1.0));

vec3 toViewer = dir - currentPos;
float alongTrail = dot(toViewer, travelDir);
float perpDist = length(toViewer - travelDir * alongTrail);

float trailWidth = 0.003;
float trailLength = 0.08 * (1.0 - t / duration);

if (perpDist < trailWidth && alongTrail > -trailLength && alongTrail < 0.01) {
float intensity = (1.0 - perpDist / trailWidth);
intensity *= smoothstep(-trailLength, 0.0, alongTrail);
intensity *= 1.0 - t / duration;
intensity *= STAR_SHOOTING_BRIGHTNESS;

result += vec3(0.9, 0.95, 1.0) * intensity;
}
}

return result;
}

vec3 blendSkyLayers(vec3 horizon, vec3 mid, vec3 zenith, float height, float midH, float zenithH) {
float h = clamp(height, 0.0, 1.0);

float transitionHeight = clamp(DAY_ZENITH_HEIGHT, 0.45, 0.95);
float t = smoothstep(0.0, transitionHeight, h);
return mix(horizon, zenith, t);
}

#include "/include/ringed_planet.glsl"

#ifdef END_SKY_ENABLED

#ifdef END_STARS_ENABLED
vec3 endStarField(vec3 dir, float time) {
dir = normalize(dir);
vec2 starUV = cubeProject(dir) * STAR_SCALE;

vec2 cell = floor(starUV);
vec2 local = fract(starUV);

vec3 result = vec3(0.0);

for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
vec2 nc = cell + vec2(float(x), float(y));

float rnd = hash21(nc);
if (rnd > END_STAR_DENSITY) continue;

vec2 sp = hash22(nc) * 0.6 + 0.2;
vec2 d = local - vec2(float(x), float(y)) - sp;
float dist = length(d);

float baseBright = 0.4 + hash21(nc + 500.0) * 0.6;

float twinklePhase = hash21(nc + 700.0) * 6.28318;
float twinkleSpeed = 0.5 + hash21(nc + 800.0) * 2.0;
float twinkle = 0.7 + 0.3 * sin(time * twinkleSpeed + twinklePhase);

float bright = baseBright * twinkle * END_STAR_BRIGHTNESS;

float radius = STAR_SIZE * (0.5 + hash21(nc + 400.0) * 0.5);
float s = 1.0 - smoothstep(0.0, radius, dist);

vec3 sColor = vec3(1.0);
if (END_STAR_COLOR_SHIFT > 0.0) {
float colorRnd = hash21(nc + 1000.0);
vec3 tint;
if (colorRnd < 0.3) {
tint = vec3(0.7, 0.5, 1.0);
} else if (colorRnd < 0.55) {
tint = vec3(0.4, 0.7, 1.0);
} else if (colorRnd < 0.75) {
tint = vec3(0.3, 0.9, 0.8);
} else {
tint = vec3(1.0, 0.95, 0.9);
}
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

vec2 uv = vec2(atan(dir.z, dir.x), asin(clamp(dir.y, -1.0, 1.0)));
uv *= END_NEBULA_SCALE;

float drift = time * END_NEBULA_SPEED;
vec2 uv1 = uv + vec2(drift, drift * 0.3);
vec2 uv2 = uv + vec2(-drift * 0.7, drift * 0.5);

float largeClouds = fbm(uv1 * 0.6, 5);
float largeClouds2 = fbm(uv2 * 0.8 + vec2(50.0, 25.0), 4);

float medDetail = fbm(uv1 * 1.2 + vec2(100.0, 50.0), 4);

float colorLayer = fbm(uv * 0.4 + vec2(-30.0, 80.0) + drift * 0.3, 3);

float v = voronoiNoise(uv1 * 2.0);

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

float waveNoise = simplexNoise(vec2(angle * 2.0, time * END_AURORA_SPEED * 0.3));
float wave = sin(elevation * 12.0 + waveNoise * 4.0 + time * END_AURORA_SPEED) * 0.5 + 0.5;

float vertStreak = simplexNoise(vec2(angle * 4.0 + time * 0.05, elevation * 8.0));
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
vec3 endVoidParticles(vec3 dir, float time) {
dir = normalize(dir);
vec2 particleUV = cubeProject(dir) * 30.0;

vec2 cell = floor(particleUV);
vec2 local = fract(particleUV);

vec3 result = vec3(0.0);

for (int x = -1; x <= 1; x++) {
for (int y = -1; y <= 1; y++) {
vec2 nc = cell + vec2(float(x), float(y));

float rnd = hash21(nc + vec2(200.0, 300.0));
if (rnd > END_VOID_PARTICLE_DENSITY) continue;

vec2 sp = hash22(nc + vec2(200.0, 300.0)) * 0.6 + 0.2;

float pulsePhase = hash21(nc + vec2(500.0, 600.0)) * 6.28318;
float pulseSpeed = 0.3 + hash21(nc + vec2(700.0, 800.0)) * 1.5;
float pulse = 0.5 + 0.5 * sin(time * pulseSpeed + pulsePhase);

float driftX = sin(time * 0.1 + pulsePhase) * 0.02;
float driftY = cos(time * 0.08 + pulsePhase * 1.3) * 0.02;

vec2 d = local - vec2(float(x), float(y)) - sp + vec2(driftX, driftY);
float dist = length(d);

float particle = 1.0 - smoothstep(0.0, 0.04, dist);
particle *= pulse;

float hueRnd = hash21(nc + vec2(900.0, 100.0));
vec3 pColor = mix(vec3(0.6, 0.2, 1.0), vec3(0.2, 0.8, 0.9), hueRnd);

result += pColor * particle * END_VOID_PARTICLE_BRIGHTNESS * 0.3;
}
}

return result;
}
#endif

vec3 renderEndSky(vec3 worldDir, float time) {
float height = applySkyGradientCurve(max(worldDir.y, 0.0));

vec3 horizonColor = vec3(END_SKY_HORIZON_R, END_SKY_HORIZON_G, END_SKY_HORIZON_B);
vec3 midColor = vec3(END_SKY_MID_R, END_SKY_MID_G, END_SKY_MID_B);
vec3 zenithColor = vec3(END_SKY_ZENITH_R, END_SKY_ZENITH_G, END_SKY_ZENITH_B);

vec3 sky = blendSkyLayers(horizonColor, midColor, zenithColor, height, 0.25, 0.65);

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

#ifdef END_STARS_ENABLED
sky += endStarField(worldDir, time);
#endif

#ifdef END_NEBULA_ENABLED
sky += endNebula(worldDir, time);
#endif

#ifdef END_AURORA_ENABLED
sky += endAurora(worldDir, time);
#endif

#ifdef END_VOID_PARTICLES_ENABLED
sky += endVoidParticles(worldDir, time);
#endif

return sky;
}

#endif

#include "/include/clouds_2d.glsl"

#include "/include/night_effects.glsl"

vec3 applySaturation(vec3 color, float satMult) {
vec3 hsv = rgb2hsv(color);
hsv.y = clamp(hsv.y * satMult, 0.0, 1.0);
return hsv2rgb(hsv);
}

float applySkyGradientCurve(float h) {
float x = clamp(h, 0.0, 1.0);
float curve = max(SKY_GRADIENT_CURVE, 0.001);
return pow(x, 1.0 / curve);
}

vec3 applyBiomeLayerBlend(vec3 baseColor, vec3 biomeColor, float amount) {
return mix(baseColor, biomeColor, clamp(amount, 0.0, 1.0));
}

bool isSkylessWorldHeuristic() {
float sunLen = length(sunPosition);
float shadowLen = length(shadowLightPosition);
vec3 skyMax = max(skyColor, vec3(0.0));
vec3 fogMax = max(fogColor, vec3(0.0));
float skyPeak = max(max(skyMax.r, skyMax.g), skyMax.b);
float fogPeak = max(max(fogMax.r, fogMax.g), fogMax.b);
bool noDirectionalLight = (sunLen < 0.001 && shadowLen < 0.001);
bool darkFlatAtmosphere = (skyPeak < 0.06 && fogPeak < 0.08);
return darkFlatAtmosphere && noDirectionalLight;
}

void main() {

vec3 viewDir = normalize(viewPos);
vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewDir);

#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome)) {
vec3 netherSky = getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B));
gl_FragData[0] = vec4(netherSky * 0.15, 1.0);
gl_FragData[1] = vec4(0.0);
return;
}
#endif

if (isSkylessWorldHeuristic()) {
vec3 flatSky = max(fogColor, skyColor * 0.8);
gl_FragData[0] = vec4(flatSky, 1.0);
gl_FragData[1] = vec4(0.0);
return;
}

float rawHeight = applySkyGradientCurve(max(worldDir.y, 0.0));
float angle = fract(sunAngle);

TimeWeights tw = getTimeWeights(sunAngle);
float isDay = tw.day;
float twilight = tw.sunset + tw.sunrise;
float blueHour = tw.blueHour + tw.dawn;
float isNight = tw.night;

float rawDay = isDay;
float rawTwilight = twilight;
float rawBlueHour = blueHour;
float rawNight = isNight;

vec3 baseDayHorizon = vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B);
vec3 baseDayMid = vec3(DAY_MID_R, DAY_MID_G, DAY_MID_B);
vec3 baseDayZenith = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B);
vec3 biomeHorizon = baseDayHorizon;
vec3 biomeMid = baseDayMid;
vec3 biomeZenith = baseDayZenith;

vec3 smoothedFogColor = getSmoothedBiomeFogColorRaw(fogColor);
vec3 smoothedSkyColor = getSmoothedBiomeSkyColorRaw(skyColor);
float wSnow = getBiomeVisualSnowyWeight(biome_snowy);
float wSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float wJungle = getBiomeJungleWeight(biome_jungle, biome, biome_category, wSwamp);
float wArid = getBiomeVisualAridWeight(biome_arid);
float wSavanna = getSavannaWeightWithoutSwamp(getBiomeVisualSavannaWeight(biome_savanna), wSwamp);
float wOcean = getBiomeVisualOceanWeight(biome_ocean);
float wAridSky = getAridWeightWithoutSavanna(wArid, wSavanna);
float wPaleGarden = clamp(biome_pale_garden, 0.0, 1.0);
#ifndef OVERWORLD_BIOME_SKY_ENABLED

wSnow = 0.0;
wSwamp = 0.0;
wJungle = 0.0;
wArid = 0.0;
wSavanna = 0.0;
wOcean = 0.0;
wAridSky = 0.0;
wPaleGarden = 0.0;
#endif
vec3 savannaSkyHorizon = getSavannaSkyHorizonColor();
vec3 savannaSkyZenith = getSavannaSkyZenithColor();
vec3 savannaSkyMid = getSavannaSkyMidColor();

if (wSnow > 0.001) {
biomeHorizon = mix(biomeHorizon, vec3(0.92, 0.94, 0.96), wSnow);
biomeMid = mix(biomeMid, vec3(0.88, 0.91, 0.95), wSnow);
biomeZenith = mix(biomeZenith, vec3(0.75, 0.85, 0.95), wSnow);
}
if (wJungle > 0.001) {
biomeHorizon = mix(biomeHorizon, vec3(81.0, 189.0, 92.0) / 255.0, wJungle);
biomeMid = mix(biomeMid, vec3(154.0, 194.0, 110.0) / 255.0, wJungle);
biomeZenith = mix(biomeZenith, vec3(122.0, 211.0, 255.0) / 255.0, wJungle);
}
if (wSwamp > 0.001) {
biomeHorizon = mix(biomeHorizon, vec3(66.0, 128.0, 75.0) / 255.0, wSwamp);
biomeMid = mix(biomeMid, vec3(83.0, 77.0, 102.0) / 255.0, wSwamp);
biomeZenith = mix(biomeZenith, vec3(144.0, 199.0, 90.0) / 255.0, wSwamp);
}
if (wAridSky > 0.001) {
biomeHorizon = mix(biomeHorizon, vec3(235.0, 213.0, 185.0) / 255.0, wAridSky);
biomeMid = mix(biomeMid, vec3(214.0, 206.0, 224.0) / 255.0, wAridSky);
biomeZenith = mix(biomeZenith, vec3(150.0, 145.0, 207.0) / 255.0, wAridSky);
}
if (wSavanna > 0.001) {
biomeHorizon = mix(biomeHorizon, savannaSkyHorizon, wSavanna);
biomeMid = mix(biomeMid, savannaSkyMid, wSavanna);
biomeZenith = mix(biomeZenith, savannaSkyZenith, wSavanna);
}
if (wPaleGarden > 0.001) {
biomeHorizon = mix(biomeHorizon, getPaleGardenSkyHorizonColor(), wPaleGarden);
biomeMid = mix(biomeMid, getPaleGardenSkyMidColor(), wPaleGarden);
biomeZenith = mix(biomeZenith, getPaleGardenSkyZenithColor(), wPaleGarden);
}

float smoothBiomeWeight = max(max(max(wSnow, wJungle), max(wSwamp, wAridSky)), max(wSavanna, wPaleGarden));
bool hasForcedBiomeSky = smoothBiomeWeight > 0.001;

float dynDelta = max(length(smoothedSkyColor - baseDayZenith), length(smoothedFogColor - baseDayHorizon));

float dynBiomeWeight = max(smoothstep(0.03, 0.18, dynDelta), wOcean);
#ifndef OVERWORLD_BIOME_SKY_ENABLED

dynBiomeWeight = 0.0;
#endif

if (!hasForcedBiomeSky && dynBiomeWeight > 0.001) {
vec3 dynHorizon = smoothedFogColor;
vec3 dynZenith = smoothedSkyColor;
vec3 dynMid = mix(dynHorizon, dynZenith, 0.55);
biomeHorizon = mix(biomeHorizon, dynHorizon, dynBiomeWeight);
biomeMid = mix(biomeMid, dynMid, dynBiomeWeight);
biomeZenith = mix(biomeZenith, dynZenith, dynBiomeWeight);
}

float biomeBlendStrength = hasForcedBiomeSky ? 1.0 : (SKY_BIOME_BLEND * dynBiomeWeight);
float biomeTintStrengthDay = biomeBlendStrength;

float overcastWeight = max(wSwamp, wPaleGarden);
float biomeTintStrengthTwilight = biomeBlendStrength * overcastWeight * 0.35;
float biomeTintStrengthBlueHour = biomeBlendStrength * overcastWeight * 0.25;
float biomeTintStrengthNight = biomeBlendStrength * overcastWeight * 0.2;

vec3 dayHorizon = vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B);
vec3 dayMid = vec3(DAY_MID_R, DAY_MID_G, DAY_MID_B);
vec3 dayZenith = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B);

dayHorizon = applyBiomeLayerBlend(dayHorizon, biomeHorizon, biomeTintStrengthDay);
dayMid = applyBiomeLayerBlend(dayMid, biomeMid, biomeTintStrengthDay);
dayZenith = applyBiomeLayerBlend(dayZenith, biomeZenith, biomeTintStrengthDay);

dayHorizon = applySaturation(dayHorizon, SKY_SATURATION);
dayMid = applySaturation(dayMid, SKY_SATURATION);
dayZenith = applySaturation(dayZenith, SKY_SATURATION);
if (wSavanna > 0.001) {
float savannaLock = clamp(wSavanna * biomeTintStrengthDay, 0.0, 1.0);
dayHorizon = mix(dayHorizon, savannaSkyHorizon, savannaLock);
dayMid = mix(dayMid, savannaSkyMid, savannaLock);
dayZenith = mix(dayZenith, savannaSkyZenith, savannaLock);
}
vec3 dayColor = blendSkyLayers(dayHorizon, dayMid, dayZenith, rawHeight, DAY_MID_HEIGHT, DAY_ZENITH_HEIGHT);

vec3 sunsetHorizon = vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B);
vec3 sunsetMid = vec3(SUNSET_MID_R, SUNSET_MID_G, SUNSET_MID_B);
vec3 sunsetZenith = vec3(SUNSET_ZENITH_R, SUNSET_ZENITH_G, SUNSET_ZENITH_B);
sunsetHorizon = applyBiomeLayerBlend(sunsetHorizon, biomeHorizon, biomeTintStrengthTwilight);
sunsetMid = applyBiomeLayerBlend(sunsetMid, biomeMid, biomeTintStrengthTwilight);
sunsetZenith = applyBiomeLayerBlend(sunsetZenith, biomeZenith, biomeTintStrengthTwilight);
sunsetHorizon = applySaturation(sunsetHorizon, SKY_SATURATION);
sunsetMid = applySaturation(sunsetMid, SKY_SATURATION);
sunsetZenith = applySaturation(sunsetZenith, SKY_SATURATION);
vec3 sunsetColor = blendSkyLayers(sunsetHorizon, sunsetMid, sunsetZenith, rawHeight, SUNSET_MID_HEIGHT, SUNSET_ZENITH_HEIGHT);

vec3 blueHorizon = vec3(BLUEHOUR_HORIZON_R, BLUEHOUR_HORIZON_G, BLUEHOUR_HORIZON_B);
vec3 blueMid = vec3(BLUEHOUR_MID_R, BLUEHOUR_MID_G, BLUEHOUR_MID_B);
vec3 blueZenith = vec3(BLUEHOUR_ZENITH_R, BLUEHOUR_ZENITH_G, BLUEHOUR_ZENITH_B);
blueHorizon = applyBiomeLayerBlend(blueHorizon, biomeHorizon, biomeTintStrengthBlueHour);
blueMid = applyBiomeLayerBlend(blueMid, biomeMid, biomeTintStrengthBlueHour);
blueZenith = applyBiomeLayerBlend(blueZenith, biomeZenith, biomeTintStrengthBlueHour);
blueHorizon = applySaturation(blueHorizon, SKY_SATURATION);
blueMid = applySaturation(blueMid, SKY_SATURATION);
blueZenith = applySaturation(blueZenith, SKY_SATURATION);
vec3 blueHourColor = blendSkyLayers(blueHorizon, blueMid, blueZenith, rawHeight, BLUEHOUR_MID_HEIGHT, BLUEHOUR_ZENITH_HEIGHT);

vec3 nightHorizon = vec3(NIGHT_HORIZON_R, NIGHT_HORIZON_G, NIGHT_HORIZON_B);
vec3 nightMid = vec3(NIGHT_MID_R, NIGHT_MID_G, NIGHT_MID_B);
vec3 nightZenith = vec3(NIGHT_ZENITH_R, NIGHT_ZENITH_G, NIGHT_ZENITH_B);
nightHorizon = applyBiomeLayerBlend(nightHorizon, biomeHorizon, biomeTintStrengthNight);
nightMid = applyBiomeLayerBlend(nightMid, biomeMid, biomeTintStrengthNight);
nightZenith = applyBiomeLayerBlend(nightZenith, biomeZenith, biomeTintStrengthNight);
nightHorizon = applySaturation(nightHorizon, SKY_SATURATION);
nightMid = applySaturation(nightMid, SKY_SATURATION);
nightZenith = applySaturation(nightZenith, SKY_SATURATION);
vec3 nightColor = blendSkyLayers(nightHorizon, nightMid, nightZenith, rawHeight, NIGHT_MID_HEIGHT, NIGHT_ZENITH_HEIGHT);

vec3 sunriseHorizon = vec3(SUNRISE_HORIZON_R, SUNRISE_HORIZON_G, SUNRISE_HORIZON_B);
vec3 sunriseMid = vec3(SUNRISE_MID_R, SUNRISE_MID_G, SUNRISE_MID_B);
vec3 sunriseZenith = vec3(SUNRISE_ZENITH_R, SUNRISE_ZENITH_G, SUNRISE_ZENITH_B);
sunriseHorizon = applySaturation(sunriseHorizon, SKY_SATURATION);
sunriseMid = applySaturation(sunriseMid, SKY_SATURATION);
sunriseZenith = applySaturation(sunriseZenith, SKY_SATURATION);
vec3 sunriseColor = blendSkyLayers(sunriseHorizon, sunriseMid, sunriseZenith, rawHeight, SUNSET_MID_HEIGHT, SUNSET_ZENITH_HEIGHT);

vec3 dawnHorizon = vec3(DAWN_HORIZON_R, DAWN_HORIZON_G, DAWN_HORIZON_B);
vec3 dawnMid = vec3(DAWN_MID_R, DAWN_MID_G, DAWN_MID_B);
vec3 dawnZenith = vec3(DAWN_ZENITH_R, DAWN_ZENITH_G, DAWN_ZENITH_B);
dawnHorizon = applySaturation(dawnHorizon, SKY_SATURATION);
dawnMid = applySaturation(dawnMid, SKY_SATURATION);
dawnZenith = applySaturation(dawnZenith, SKY_SATURATION);
vec3 dawnColor = blendSkyLayers(dawnHorizon, dawnMid, dawnZenith, rawHeight, BLUEHOUR_MID_HEIGHT, BLUEHOUR_ZENITH_HEIGHT);

vec3 dayFinal = dayColor * DAY_BRIGHTNESS;
vec3 sunsetFinal = sunsetColor * SUNSET_BRIGHTNESS;
vec3 blueFinal = blueHourColor * BLUEHOUR_BRIGHTNESS;
vec3 nightFinal = nightColor * NIGHT_BRIGHTNESS;
vec3 sunriseFinal = sunriseColor * SUNRISE_BRIGHTNESS;
vec3 dawnFinal = dawnColor * DAWN_BRIGHTNESS;

vec3 color = dayFinal    * tw.day
+ sunsetFinal * tw.sunset
+ blueFinal   * tw.blueHour
+ nightFinal  * tw.night
+ sunriseFinal * tw.sunrise
+ dawnFinal   * tw.dawn;

float heightBlend = smoothstep(0.0, 0.5, rawHeight);

float daySunsetMixH = min(tw.day, tw.sunset + tw.sunrise) * 2.5;
float daySunsetMixZ = min(tw.day, tw.sunset + tw.sunrise) * 2.0;
float daySunsetMix = mix(daySunsetMixH, daySunsetMixZ, heightBlend);

vec3 daySunsetCP = mix(vec3(1.0, 0.92, 0.4), vec3(0.85, 0.15, 0.55), heightBlend);
daySunsetCP *= max(DAY_BRIGHTNESS, SUNSET_BRIGHTNESS);
color = mix(color, daySunsetCP, daySunsetMix * mix(0.45, 0.55, heightBlend));

float sunsetBlueMix = min(tw.sunset, tw.blueHour) * 2.0;
vec3 sunsetBlueCP = mix(vec3(0.9, 0.25, 0.55), vec3(0.4, 0.1, 1.0), heightBlend);
sunsetBlueCP *= mix(SUNSET_BRIGHTNESS, BLUEHOUR_BRIGHTNESS, 0.5);
color = mix(color, sunsetBlueCP, sunsetBlueMix * mix(0.4, 0.55, heightBlend));

color *= 1.0 - rainStrength * (float(SKY_RAIN_DARKNESS) / 100.0);

#ifdef STARS_ENABLED

float starRainFade = 1.0 - smoothstep(0.15, 0.70, rainStrength);
float nightVisibility = (isNight + blueHour * 0.5) * starRainFade * (1.0 - wSwamp);
if (nightVisibility > 0.01 && worldDir.y > -0.1) {

float stars = starField(worldDir, frameTimeCounter);

float horizonFade = smoothstep(-0.1, 0.15, worldDir.y);

color += vec3(stars) * nightVisibility * horizonFade;

#ifdef STAR_SHOOTING_ENABLED
if (isNight > 0.5) {
vec3 shootingStars = shootingStar(worldDir, frameTimeCounter);
color += shootingStars * horizonFade * starRainFade;
}
#endif
}
#endif

#ifdef NIGHT_NEBULA_ENABLED
{
float starRainFadeN = 1.0 - smoothstep(0.15, 0.70, rainStrength);
float nebulaVis = (isNight + blueHour * 0.4) * starRainFadeN * (1.0 - wSwamp);
if (nebulaVis > 0.01) {
vec3 nebula = nightNebula(worldDir, frameTimeCounter);
color += nebula * nebulaVis;
}
}
#endif

#ifdef METEORS_ENABLED
{
float meteorRainFade = 1.0 - smoothstep(0.15, 0.70, rainStrength);
float meteorVis = (isNight + blueHour * 0.3) * meteorRainFade * (1.0 - wSwamp);
if (meteorVis > 0.01 && worldDir.y > -0.05) {
vec3 meteors = fantasyMeteor(worldDir, frameTimeCounter);
float mHorizonFade = smoothstep(-0.05, 0.15, worldDir.y);
color += meteors * meteorVis * mHorizonFade;
}
}
#endif

#ifdef CLOUDS_2D_ENABLED
{
vec4 clouds = render2DClouds(worldDir, cameraPosition, frameTimeCounter, sunAngle);

color = mix(color, clouds.rgb, clouds.a);
}
#endif

#ifdef RINGED_PLANET_ENABLED
{

vec3 sunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 eye = vec3(0.0);

PlanetEnd2(color, eye, worldDir, sunDir);
}
#endif

if (wSwamp > 0.001) {
color *= mix(1.0, 0.6, wSwamp);
}

gl_FragData[0] = vec4(color, 1.0);
gl_FragData[1] = vec4(0.0);
}
