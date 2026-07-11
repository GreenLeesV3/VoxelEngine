vec3 getTimeBasedFogColor() {
if (isForcedNetherBiome(biome)) {
return getForcedBiomeFogColorCat(biome, biome_category, fogColor);
}

TimeWeights tw = getTimeWeights(sunAngle);

float biomeDayGate = smoothstep(0.18, 0.78, tw.day + (tw.sunset + tw.sunrise) * 0.30);
float wSnow = getBiomeSnowyWeight(biome_snowy, biome, biome_category);
float wSwamp = getBiomeSwampWeight(biome_swamp, biome, biome_category);
float wJungle = getBiomeJungleWeight(biome_jungle, biome, biome_category, wSwamp);
float wArid = getBiomeAridWeight(biome_arid, biome, biome_category);
float wSavanna = getSavannaWeightWithoutSwamp(getBiomeSavannaWeight(biome_savanna, biome, biome_category), wSwamp);
bool hasForcedBiome = max(max(max(max(wSnow, wJungle), max(wSwamp, wArid)), wSavanna), clamp(biome_pale_garden, 0.0, 1.0)) > 0.001;
float biomeBlendStrength = hasForcedBiome ? 1.0 : (SKY_BIOME_BLEND * biomeDayGate);
float biomeTintDay = biomeBlendStrength;
float biomeTintTwilight = biomeBlendStrength * 0.55;
float biomeTintBlueHour = biomeBlendStrength * 0.40;
float biomeTintNight = biomeBlendStrength * 0.20;
vec3 biomeFogOverride = getSmoothBiomeFogColorSavanna(vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B), wSnow, wJungle, wSwamp, wArid, wSavanna);

vec3 dayFog     = mix(vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B), biomeFogOverride, biomeTintDay) * DAY_BRIGHTNESS;
vec3 sunsetFog  = mix(vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), biomeFogOverride, biomeTintTwilight) * SUNSET_BRIGHTNESS;
vec3 blueFog    = mix(vec3(BLUEHOUR_HORIZON_R, BLUEHOUR_HORIZON_G, BLUEHOUR_HORIZON_B), biomeFogOverride, biomeTintBlueHour) * BLUEHOUR_BRIGHTNESS;
vec3 nightFog   = mix(vec3(NIGHT_HORIZON_R, NIGHT_HORIZON_G, NIGHT_HORIZON_B), biomeFogOverride, biomeTintNight) * NIGHT_BRIGHTNESS;
vec3 sunriseFog = mix(vec3(SUNRISE_HORIZON_R, SUNRISE_HORIZON_G, SUNRISE_HORIZON_B), biomeFogOverride, biomeTintTwilight) * SUNRISE_BRIGHTNESS;
vec3 dawnFog    = mix(vec3(DAWN_HORIZON_R, DAWN_HORIZON_G, DAWN_HORIZON_B), biomeFogOverride, biomeTintBlueHour) * DAWN_BRIGHTNESS;

vec3 color = dayFog     * tw.day
+ sunsetFog  * tw.sunset
+ blueFog    * tw.blueHour
+ nightFog   * tw.night
+ sunriseFog * tw.sunrise
+ dawnFog    * tw.dawn;

float daySunsetMix = min(tw.day, tw.sunset) * 2.0;
color = mix(color, vec3(0.9, 0.15, 0.85) * mix(DAY_BRIGHTNESS, SUNSET_BRIGHTNESS, 0.5), daySunsetMix * 0.5);
float sunsetBlueMix = min(tw.sunset, tw.blueHour) * 2.0;
color = mix(color, vec3(0.4, 0.1, 1.0) * mix(SUNSET_BRIGHTNESS, BLUEHOUR_BRIGHTNESS, 0.5), sunsetBlueMix * 0.5);

return color;
}
