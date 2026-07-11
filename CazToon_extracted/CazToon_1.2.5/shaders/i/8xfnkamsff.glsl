#include "/include/biome_color_smoothing.glsl"

vec3 applyFogSaturation(vec3 color, float satMult) {
vec3 hsv = rgb2hsv(color);
hsv.y = clamp(hsv.y * satMult, 0.0, 1.0);
return hsv2rgb(hsv);
}

vec3 getSkyCastHorizonColor() {
if (isSkylessWorldHeuristic()) {
return max(fogColor, skyColor * 0.8);
}

if (isForcedNetherBiome(biome)) {
return getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B));
}
#ifdef END_FOG_ENABLED
if (isEndDimension()) {
return (vec3(END_FOG_R, END_FOG_G, END_FOG_B) * 3.0 + vec3(0.02, 0.01, 0.04)) * END_SKY_BRIGHTNESS;
}
#endif

TimeWeights tw = getTimeWeights(sunAngle);

vec3 baseDayHorizon = vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B);
vec3 baseDayZenith = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B);
vec3 smoothedFogColor = getSmoothedBiomeFogColorRaw(fogColor);
vec3 smoothedSkyColor = getSmoothedBiomeSkyColorRaw(skyColor);
float wSnow = getBiomeVisualSnowyWeight(biome_snowy);
float wSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float wJungle = getBiomeJungleWeight(biome_jungle, biome, biome_category, wSwamp);
float wArid = getBiomeVisualAridWeight(biome_arid);
float wSavanna = getSavannaWeightWithoutSwamp(getBiomeVisualSavannaWeight(biome_savanna), wSwamp);
float wOcean = getBiomeVisualOceanWeight(biome_ocean);

float smoothBiomeWeight = max(max(max(max(wSnow, wJungle), max(wSwamp, wArid)), wSavanna), clamp(biome_pale_garden, 0.0, 1.0));
bool hasForcedBiomeSky = smoothBiomeWeight > 0.001;

float dynDelta = max(length(smoothedSkyColor - baseDayZenith), length(smoothedFogColor - baseDayHorizon));
float dynBiomeWeight = max(smoothstep(0.03, 0.18, dynDelta), wOcean);
float biomeBlendStrength = hasForcedBiomeSky ? 1.0 : (SKY_BIOME_BLEND * dynBiomeWeight);
float biomeTintDay = biomeBlendStrength;

vec3 biomeFogOverride = getSmoothBiomeFogColorSavanna(baseDayHorizon, wSnow, wJungle, wSwamp, wArid, wSavanna);
float rawTwilight = tw.sunset + tw.sunrise;
if (!hasForcedBiomeSky && dynBiomeWeight > 0.001) {
float fogDesat = clamp(rawTwilight, 0.0, 1.0);
float fogSat = mix(1.0, 0.35, fogDesat);
float fogLum = dot(smoothedFogColor, vec3(0.299, 0.587, 0.114));
vec3 blendFogColor = mix(vec3(fogLum), smoothedFogColor, fogSat);
biomeFogOverride = mix(biomeFogOverride, blendFogColor, dynBiomeWeight);
}

vec3 dayHorizon = mix(baseDayHorizon, biomeFogOverride, biomeTintDay);
vec3 sunsetHorizon = vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B);
vec3 blueHorizon = vec3(BLUEHOUR_HORIZON_R, BLUEHOUR_HORIZON_G, BLUEHOUR_HORIZON_B);
vec3 nightHorizon = vec3(NIGHT_HORIZON_R, NIGHT_HORIZON_G, NIGHT_HORIZON_B);
vec3 sunriseHorizon = vec3(SUNRISE_HORIZON_R, SUNRISE_HORIZON_G, SUNRISE_HORIZON_B);
vec3 dawnHorizon = vec3(DAWN_HORIZON_R, DAWN_HORIZON_G, DAWN_HORIZON_B);

dayHorizon = applyFogSaturation(dayHorizon, SKY_SATURATION);
sunsetHorizon = applyFogSaturation(sunsetHorizon, SKY_SATURATION);
blueHorizon = applyFogSaturation(blueHorizon, SKY_SATURATION);
nightHorizon = applyFogSaturation(nightHorizon, SKY_SATURATION);
sunriseHorizon = applyFogSaturation(sunriseHorizon, SKY_SATURATION);
dawnHorizon = applyFogSaturation(dawnHorizon, SKY_SATURATION);

if (wSavanna > 0.001) {
float savannaLock = clamp(wSavanna * biomeTintDay, 0.0, 1.0);
dayHorizon = mix(dayHorizon, getSavannaSkyHorizonColor(), savannaLock);
}

vec3 color = dayHorizon     * DAY_BRIGHTNESS      * tw.day
+ sunsetHorizon  * SUNSET_BRIGHTNESS    * tw.sunset
+ blueHorizon    * BLUEHOUR_BRIGHTNESS  * tw.blueHour
+ nightHorizon   * NIGHT_BRIGHTNESS     * tw.night
+ sunriseHorizon * SUNRISE_BRIGHTNESS   * tw.sunrise
+ dawnHorizon    * DAWN_BRIGHTNESS      * tw.dawn;

float daySunsetMix = min(tw.day, tw.sunset) * 2.0;
color = mix(color, vec3(0.9, 0.15, 0.85) * mix(DAY_BRIGHTNESS, SUNSET_BRIGHTNESS, 0.5), daySunsetMix * 0.5);
float sunsetBlueMix = min(tw.sunset, tw.blueHour) * 2.0;
color = mix(color, vec3(0.4, 0.1, 1.0) * mix(SUNSET_BRIGHTNESS, BLUEHOUR_BRIGHTNESS, 0.5), sunsetBlueMix * 0.5);

return color;
}

vec3 getHorizonColor() {
if (isSkylessWorldHeuristic()) {
return max(fogColor, skyColor * 0.8);
}

if (isForcedNetherBiome(biome)) {
return getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B));
}

#ifdef END_FOG_ENABLED
if (isEndDimension()) {
return (vec3(END_FOG_R, END_FOG_G, END_FOG_B) * 3.0 + vec3(0.02, 0.01, 0.04)) * END_SKY_BRIGHTNESS;
}
#endif

TimeWeights tw = getTimeWeights(sunAngle);

vec3 baseDayHorizon = vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B);
vec3 baseDayZenith = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B);
vec3 smoothedFogColor = getSmoothedBiomeFogColorRaw(fogColor);
vec3 smoothedSkyColor = getSmoothedBiomeSkyColorRaw(skyColor);
float wSnow = getBiomeVisualSnowyWeight(biome_snowy);
float wSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float wJungle = getBiomeJungleWeight(biome_jungle, biome, biome_category, wSwamp);
float wArid = getBiomeVisualAridWeight(biome_arid);
float wSavanna = getSavannaWeightWithoutSwamp(getBiomeVisualSavannaWeight(biome_savanna), wSwamp);
float wOcean = getBiomeVisualOceanWeight(biome_ocean);

float smoothBiomeWeight = max(max(max(max(wSnow, wJungle), max(wSwamp, wArid)), wSavanna), clamp(biome_pale_garden, 0.0, 1.0));
bool hasForcedBiomeSky = smoothBiomeWeight > 0.001;

float dynDelta = max(length(smoothedSkyColor - baseDayZenith), length(smoothedFogColor - baseDayHorizon));
float dynBiomeWeight = max(smoothstep(0.03, 0.18, dynDelta), wOcean);

float biomeBlendStrength = hasForcedBiomeSky ? 1.0 : (SKY_BIOME_BLEND * dynBiomeWeight);
float biomeTintDay = biomeBlendStrength;

float horizonHeight = 0.15;

vec3 biomeFogOverride = getSmoothBiomeFogColorSavanna(baseDayHorizon, wSnow, wJungle, wSwamp, wArid, wSavanna);
float rawTwilight = tw.sunset + tw.sunrise;
if (!hasForcedBiomeSky && dynBiomeWeight > 0.001) {
float fogDesat = clamp(rawTwilight, 0.0, 1.0);
float fogSat = mix(1.0, 0.35, fogDesat);
float fogLum = dot(smoothedFogColor, vec3(0.299, 0.587, 0.114));
vec3 blendFogColor = mix(vec3(fogLum), smoothedFogColor, fogSat);
biomeFogOverride = mix(biomeFogOverride, blendFogColor, dynBiomeWeight);
}

vec3 dayColor = mix(vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B),
vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B),
smoothstep(0.0, max(DAY_ZENITH_HEIGHT, 0.001), horizonHeight));
dayColor = mix(dayColor, biomeFogOverride, biomeTintDay);
if (wSavanna > 0.001) {
float savannaLock = clamp(wSavanna * biomeTintDay, 0.0, 1.0);
dayColor = mix(dayColor, getSavannaSkyHorizonColor(), savannaLock);
}

vec3 sunsetColor = mix(vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B),
vec3(SUNSET_ZENITH_R, SUNSET_ZENITH_G, SUNSET_ZENITH_B),
smoothstep(0.0, max(SUNSET_ZENITH_HEIGHT, 0.001), horizonHeight));

vec3 blueColor = mix(vec3(BLUEHOUR_HORIZON_R, BLUEHOUR_HORIZON_G, BLUEHOUR_HORIZON_B),
vec3(BLUEHOUR_ZENITH_R, BLUEHOUR_ZENITH_G, BLUEHOUR_ZENITH_B),
smoothstep(0.0, max(BLUEHOUR_ZENITH_HEIGHT, 0.001), horizonHeight));

vec3 nightColor = mix(vec3(NIGHT_HORIZON_R, NIGHT_HORIZON_G, NIGHT_HORIZON_B),
vec3(NIGHT_ZENITH_R, NIGHT_ZENITH_G, NIGHT_ZENITH_B),
smoothstep(0.0, max(NIGHT_ZENITH_HEIGHT, 0.001), horizonHeight));

vec3 sunriseColor = mix(vec3(SUNRISE_HORIZON_R, SUNRISE_HORIZON_G, SUNRISE_HORIZON_B),
vec3(SUNRISE_ZENITH_R, SUNRISE_ZENITH_G, SUNRISE_ZENITH_B),
smoothstep(0.0, max(SUNSET_ZENITH_HEIGHT, 0.001), horizonHeight));

vec3 dawnColor = mix(vec3(DAWN_HORIZON_R, DAWN_HORIZON_G, DAWN_HORIZON_B),
vec3(DAWN_ZENITH_R, DAWN_ZENITH_G, DAWN_ZENITH_B),
smoothstep(0.0, max(BLUEHOUR_ZENITH_HEIGHT, 0.001), horizonHeight));

vec3 color = dayColor     * DAY_BRIGHTNESS     * tw.day
+ sunsetColor  * SUNSET_BRIGHTNESS   * tw.sunset
+ blueColor    * BLUEHOUR_BRIGHTNESS * tw.blueHour
+ nightColor   * NIGHT_BRIGHTNESS    * tw.night
+ sunriseColor * SUNRISE_BRIGHTNESS  * tw.sunrise
+ dawnColor    * DAWN_BRIGHTNESS     * tw.dawn;

float daySunsetMix = min(tw.day, tw.sunset) * 2.0;
color = mix(color, vec3(0.9, 0.15, 0.85) * mix(DAY_BRIGHTNESS, SUNSET_BRIGHTNESS, 0.5), daySunsetMix * 0.5);
float sunsetBlueMix = min(tw.sunset, tw.blueHour) * 2.0;
color = mix(color, vec3(0.4, 0.1, 1.0) * mix(SUNSET_BRIGHTNESS, BLUEHOUR_BRIGHTNESS, 0.5), sunsetBlueMix * 0.5);

return color;
}

#if defined(NETHER_FOG_ENABLED) || defined(END_FOG_ENABLED) || defined(OVERWORLD_FOG_ENABLED)

vec4 computeVolumetricFog(vec2 uv, float sceneDepth, vec3 sceneWorldPos, bool isSky, bool fromDH) {
vec3 camPos = cameraPosition;
float sceneDist = length(sceneWorldPos - camPos);

#ifdef NETHER_FOG_ENABLED
if (isForcedNetherBiome(biome)) {
float fogStart = max(NETHER_DISTANCE_FOG_START, 0.0);
float fogEnd = max(float(NETHER_FOG_DISTANCE), fogStart + 1.0);
float depthT = clamp((sceneDist - fogStart) / max(fogEnd - fogStart, 1.0), 0.0, 1.0);
float density = max(NETHER_DISTANCE_FOG_OPACITY, 0.01);
float fogAmt = 1.0 - exp(-depthT * depthT * density * 2.2);
fogAmt = clamp(fogAmt, 0.0, 0.98);
if (fromDH) fogAmt = clamp(fogAmt * 1.1, 0.0, 0.98);

vec3 netherFogColor = getForcedBiomeFogColor(biome, vec3(NETHER_FOG_R, NETHER_FOG_G, NETHER_FOG_B)) * NETHER_BRIGHTNESS;
return vec4(netherFogColor * fogAmt, 1.0 - fogAmt);
}
#endif

#ifdef END_FOG_ENABLED
if (isEndDimension()) {
if (isSky) return vec4(0.0, 0.0, 0.0, 1.0);
float depthRange = max(float(END_FOG_DISTANCE) - END_FOG_START, 1.0);
float depthT = clamp((sceneDist - END_FOG_START) / depthRange, 0.0, 1.0);
float density = max(END_FOG_DENSITY, 0.01);

float fogAmt = 1.0 - exp(-depthT * depthT * depthT * density * 4.0);
fogAmt = clamp(fogAmt, 0.0, 0.95);

vec3 endFogColor = vec3(END_FOG_R, END_FOG_G, END_FOG_B);
#if defined(END_SHADER) && defined(END_EVENT_ENABLED)
float vfogEventDark = getEndEvent(frameTimeCounter).fogDarkness;
endFogColor *= (1.0 - vfogEventDark);
fogAmt *= (1.0 - vfogEventDark);
#endif
return vec4(endFogColor * fogAmt, 1.0 - fogAmt);
}
#endif

#ifdef OVERWORLD_FOG_ENABLED
if (!isForcedNetherBiome(biome) && !isEndDimension() && !isSkylessWorldHeuristic()) {
if (isSky) return vec4(0.0, 0.0, 0.0, 1.0);

float rainPull = rainStrength * 0.6;
float fogStart = OVERWORLD_FOG_START * (1.0 - rainPull);
float fogDistance = float(OVERWORLD_FOG_DISTANCE) * (1.0 - rainPull);

float fogDist = max(sceneDist - fogStart, 0.0);

float density = max(OVERWORLD_FOG_DENSITY + rainStrength * OVERWORLD_FOG_RAIN_BOOST, 0.01);

float coeff = (density * 3.0) / max(fogDistance, 1.0);
float fogAmt = 1.0 - exp(-fogDist * fogDist * coeff * coeff);

if (fromDH) fogAmt = clamp(fogAmt * 1.15, 0.0, 0.98);
fogAmt = clamp(fogAmt, 0.0, 1.0);

vec3 owFogColor = getSkyCastHorizonColor();

float swampW = getBiomeSwampWeight(biome_swamp, biome, biome_category);
if (swampW > 0.001) {
vec3 swampHorizon = vec3(66.0, 128.0, 75.0) / 255.0;

float owLum = dot(owFogColor, vec3(0.299, 0.587, 0.114));
float swLum = dot(swampHorizon, vec3(0.299, 0.587, 0.114));
vec3 swampFogColor = (swLum > 0.001) ? swampHorizon * (owLum / swLum) : swampHorizon;
owFogColor = mix(owFogColor, swampFogColor, swampW);
}

owFogColor *= 1.0 - rainStrength * (float(SKY_RAIN_DARKNESS) / 100.0);

return vec4(owFogColor * fogAmt, 1.0 - fogAmt);
}
#endif

return vec4(0.0, 0.0, 0.0, 1.0);
}
#endif
