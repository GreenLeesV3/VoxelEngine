#ifdef CLOUDS_2D_ENABLED

float cloudNoise(vec2 p) {
vec2 i = floor(p);
vec2 f = fract(p);
f = f * f * (3.0 - 2.0 * f);

float a = hash21(i);
float b = hash21(i + vec2(1.0, 0.0));
float c = hash21(i + vec2(0.0, 1.0));
float d = hash21(i + vec2(1.0, 1.0));

return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cloudFBM(vec2 p) {
float value = 0.0;
float amplitude = 0.5;
float frequency = 1.0;

for (int i = 0; i < 5; i++) {
value += amplitude * cloudNoise(p * frequency);
amplitude *= 0.5;
frequency *= 2.0;
}

return value;
}

float sampleCloudDensity(vec2 worldXZ, float time) {

float r = 2500.0;
float speed = CLOUD_SPEED * 3.0;
float angle = time * speed / r;
vec2 offset = vec2(cos(angle), sin(angle)) * r;

vec2 cloudPos = (worldXZ + offset) * CLOUD_SCALE;

float noise = cloudFBM(cloudPos);

float density = smoothstep(1.0 - CLOUD_COVERAGE, 1.0 - CLOUD_COVERAGE + 0.3, noise);

#if CLOUD_TOON_EDGES == 1

density = step(0.3, density);
#endif

return density;
}

vec4 render2DClouds(vec3 worldDir, vec3 camPos, float time, float sunAngle) {

if (worldDir.y < 0.01) return vec4(0.0);

float t = ((CLOUD_HEIGHT + SEA_LEVEL_OFFSET) - camPos.y) / worldDir.y;

if (t < 0.0) return vec4(0.0);

if (t > 50000.0) return vec4(0.0);

vec2 cloudWorldPos = camPos.xz + worldDir.xz * t;

float density = sampleCloudDensity(cloudWorldPos, time);

if (density < 0.01) return vec4(0.0);

vec2 offsetPos = cloudWorldPos + worldDir.xz * CLOUD_THICKNESS * 0.5 / max(worldDir.y, 0.1);
float density2 = sampleCloudDensity(offsetPos, time);

float finalDensity = max(density, density2 * 0.7);

float dayTime = fract(sunAngle);
float sunHeight = sin(dayTime * 6.28318);

vec3 cloudLit, cloudShadow;

float sunsetFactor = smoothstep(0.0, 0.15, abs(sunHeight)) * (1.0 - smoothstep(0.15, 0.3, abs(sunHeight)));
float nightFactor = 1.0 - smoothstep(-0.10, 0.05, sunHeight);

cloudLit = vec3(1.0, 1.0, 1.0) * CLOUD_BRIGHTNESS;
cloudShadow = vec3(CLOUD_SHADOW_R, CLOUD_SHADOW_G, CLOUD_SHADOW_B);

vec3 sunsetLit = vec3(1.0, 0.7, 0.5) * CLOUD_BRIGHTNESS;
vec3 sunsetShadow = vec3(0.8, 0.4, 0.5);
cloudLit = mix(cloudLit, sunsetLit, sunsetFactor);
cloudShadow = mix(cloudShadow, sunsetShadow, sunsetFactor);

vec3 nightLit = vec3(0.15, 0.18, 0.25);
vec3 nightShadow = vec3(0.05, 0.08, 0.12);
cloudLit = mix(cloudLit, nightLit, nightFactor);
cloudShadow = mix(cloudShadow, nightShadow, nightFactor);

float r = 2500.0;
float speed = CLOUD_SPEED * 3.0;
float angle = time * speed / r;
vec2 offset = vec2(cos(angle), sin(angle)) * r;

float lightGradient = cloudNoise((cloudWorldPos + offset) * CLOUD_SCALE * 0.5);

vec3 cloudShadowSafe = max(cloudShadow, cloudLit * 0.28);
vec3 cloudColor = mix(cloudShadowSafe, cloudLit, lightGradient);

float edgeFactor = smoothstep(0.0, 0.5, finalDensity) * (1.0 - smoothstep(0.5, 1.0, finalDensity));
cloudColor += vec3(1.0, 0.5, 0.2) * edgeFactor * sunsetFactor * 0.5;

float horizonFade = smoothstep(-0.02, 0.16, worldDir.y);
finalDensity *= horizonFade;

vec3 smoothedCloudSky = getSmoothedBiomeSkyColorRaw(skyColor);
float wSnow = getBiomeVisualSnowyWeight(biome_snowy);
float wSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float wJungle = getBiomeJungleWeight(biome_jungle, biome, biome_category, wSwamp);
float wArid = getBiomeVisualAridWeight(biome_arid);
float wSavanna = getSavannaWeightWithoutSwamp(getBiomeVisualSavannaWeight(biome_savanna), wSwamp);
vec3 biomeCloudColor = getSmoothBiomeSkyZenithSavanna(smoothedCloudSky, wSnow, wJungle, wSwamp, wArid, wSavanna);
float biomeCloudLum = max(dot(biomeCloudColor, vec3(0.299, 0.587, 0.114)), 0.001);
float cloudLum = max(dot(cloudColor, vec3(0.299, 0.587, 0.114)), 0.001);
vec3 biomeCloudMatch = clamp(biomeCloudColor * (cloudLum / biomeCloudLum), vec3(0.0), vec3(2.0));
float biomeTintAmount = smoothstep(0.0, 0.07, fract(sunAngle)) * smoothstep(0.57, 0.48, fract(sunAngle)) * 0.75;
cloudColor = mix(cloudColor, biomeCloudMatch, biomeTintAmount);
finalDensity *= (1.0 - wArid) * (1.0 - wSwamp);

return vec4(cloudColor, finalDensity);
}
#endif
