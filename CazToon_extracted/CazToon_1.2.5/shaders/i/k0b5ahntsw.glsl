#ifndef INCLUDE_BIOME_OVERRIDES_GLSL
#define INCLUDE_BIOME_OVERRIDES_GLSL

uniform float biome_pale_garden;

uniform bool hasCeiling;
uniform bool hasSkylight;

bool isForcedDesertBiome(int b) {
bool m = false;
#ifdef BIOME_DESERT
m = m || (b == BIOME_DESERT);
#endif
#ifdef BIOME_BADLANDS
m = m || (b == BIOME_BADLANDS);
#endif
#ifdef BIOME_ERODED_BADLANDS
m = m || (b == BIOME_ERODED_BADLANDS);
#endif
#ifdef BIOME_WOODED_BADLANDS
m = m || (b == BIOME_WOODED_BADLANDS);
#endif
return m;
}

bool isForcedSwampyBiome(int b) {
return b == BIOME_SWAMP || b == BIOME_MANGROVE_SWAMP || b == 7;
}

bool isForcedJungleBiome(int b) {
bool m = b == BIOME_JUNGLE || b == BIOME_BAMBOO_JUNGLE || b == BIOME_SPARSE_JUNGLE;
return m && !isForcedSwampyBiome(b);
}

bool isForcedPaleGardenBiome(int b) {
bool m = false;
#ifdef BIOME_PALE_GARDEN
m = m || (b == BIOME_PALE_GARDEN);
#endif
return m;
}

bool isForcedSavannaBiome(int b) {
bool m = false;
#ifdef BIOME_SAVANNA
m = m || (b == BIOME_SAVANNA);
#endif
#ifdef BIOME_SAVANNA_PLATEAU
m = m || (b == BIOME_SAVANNA_PLATEAU);
#endif
#ifdef BIOME_WINDSWEPT_SAVANNA
m = m || (b == BIOME_WINDSWEPT_SAVANNA);
#endif
return m;
}

bool isForcedSnowyBiome(int b) {
bool m = false;
#ifdef BIOME_SNOWY_PLAINS
m = m || (b == BIOME_SNOWY_PLAINS);
#endif
#ifdef BIOME_SNOWY_TAIGA
m = m || (b == BIOME_SNOWY_TAIGA);
#endif
#ifdef BIOME_SNOWY_BEACH
m = m || (b == BIOME_SNOWY_BEACH);
#endif
#ifdef BIOME_SNOWY_SLOPES
m = m || (b == BIOME_SNOWY_SLOPES);
#endif
#ifdef BIOME_FROZEN_RIVER
m = m || (b == BIOME_FROZEN_RIVER);
#endif
#ifdef BIOME_FROZEN_OCEAN
m = m || (b == BIOME_FROZEN_OCEAN);
#endif
#ifdef BIOME_FROZEN_PEAKS
m = m || (b == BIOME_FROZEN_PEAKS);
#endif
#ifdef BIOME_ICE_SPIKES
m = m || (b == BIOME_ICE_SPIKES);
#endif
#ifdef BIOME_GROVE
m = m || (b == BIOME_GROVE);
#endif
return m;
}

bool isForcedNetherBiome(int b) {

if (hasCeiling && !hasSkylight) return true;

bool m = false;
#ifdef BIOME_NETHER_WASTES
m = m || (b == BIOME_NETHER_WASTES);
#endif
#ifdef BIOME_CRIMSON_FOREST
m = m || (b == BIOME_CRIMSON_FOREST);
#endif
#ifdef BIOME_WARPED_FOREST
m = m || (b == BIOME_WARPED_FOREST);
#endif
#ifdef BIOME_SOUL_SAND_VALLEY
m = m || (b == BIOME_SOUL_SAND_VALLEY);
#endif
#ifdef BIOME_BASALT_DELTAS
m = m || (b == BIOME_BASALT_DELTAS);
#endif
return m;
}

bool isForcedEndBiome(int b) {
bool m = false;
#ifdef BIOME_THE_END
m = m || (b == BIOME_THE_END);
#endif
#ifdef BIOME_END_BARRENS
m = m || (b == BIOME_END_BARRENS);
#endif
#ifdef BIOME_END_HIGHLANDS
m = m || (b == BIOME_END_HIGHLANDS);
#endif
#ifdef BIOME_END_MIDLANDS
m = m || (b == BIOME_END_MIDLANDS);
#endif
#ifdef BIOME_SMALL_END_ISLANDS
m = m || (b == BIOME_SMALL_END_ISLANDS);
#endif
return m;
}

bool isCategoryDesert(int c) {

bool m = (c == 12) || (c == 4);
#ifdef CAT_DESERT
m = m || (c == CAT_DESERT);
#endif
#ifdef CAT_BADLANDS
m = m || (c == CAT_BADLANDS);
#endif
return m;
}

bool isCategorySwampy(int c) {

bool m = (c == 14);
#ifdef CAT_SWAMP
m = m || (c == CAT_SWAMP);
#endif
return m;
}

bool isCategoryJungle(int c) {

bool m = (c == 3);
#ifdef CAT_JUNGLE
m = m || (c == CAT_JUNGLE);
#endif
return m;
}

bool isCategorySnowy(int c) {

bool m = (c == 7);
#ifdef CAT_ICY
m = m || (c == CAT_ICY);
#endif
#ifdef CAT_SNOWY
m = m || (c == CAT_SNOWY);
#endif
return m;
}

bool isCategorySavanna(int c) {

bool m = (c == 6);
#ifdef CAT_SAVANNA
m = m || (c == CAT_SAVANNA);
#endif
return m;
}

float getBiomeSnowyWeight(float smoothSnowy, int biomeId, int biomeCategory) {
return clamp(smoothSnowy, 0.0, 1.0);
}

float getBiomeSwampWeight(float smoothSwamp, int biomeId, int biomeCategory) {
return clamp(smoothSwamp, 0.0, 1.0);
}

float getBiomeJungleWeight(float smoothJungle, int biomeId, int biomeCategory, float swampWeight) {
return clamp(smoothJungle, 0.0, 1.0) * (1.0 - clamp(swampWeight, 0.0, 1.0));
}

float getBiomeAridWeight(float smoothArid, int biomeId, int biomeCategory) {
return clamp(smoothArid, 0.0, 1.0);
}

float getBiomeSavannaWeight(float smoothSavanna, int biomeId, int biomeCategory) {
return clamp(smoothSavanna, 0.0, 1.0);
}

float getBiomeVisualSnowyWeight(float smoothSnowy) {
return clamp(smoothSnowy, 0.0, 1.0);
}

float getBiomeVisualSwampWeight(float smoothSwamp) {
return clamp(smoothSwamp, 0.0, 1.0);
}

float getBiomeVisualJungleWeight(float smoothJungle, float swampWeight) {
return clamp(smoothJungle, 0.0, 1.0) * (1.0 - clamp(swampWeight, 0.0, 1.0));
}

float getBiomeVisualAridWeight(float smoothArid) {
return clamp(smoothArid, 0.0, 1.0);
}

float getBiomeVisualSavannaWeight(float smoothSavanna) {
return clamp(smoothSavanna, 0.0, 1.0);
}

float getBiomeVisualOceanWeight(float smoothOcean) {
return clamp(smoothOcean, 0.0, 1.0);
}

float getSavannaWeightWithoutSwamp(float savannaWeight, float swampWeight) {
return clamp(savannaWeight, 0.0, 1.0) * (1.0 - clamp(swampWeight, 0.0, 1.0));
}

vec3 getSavannaSkyHorizonColor() {
return vec3(101.0, 224.0, 196.0) / 255.0;
}

vec3 getSavannaSkyZenithColor() {
return vec3(98.0, 148.0, 240.0) / 255.0;
}

vec3 getSavannaSkyMidColor() {
return mix(getSavannaSkyHorizonColor(), getSavannaSkyZenithColor(), 0.55);
}

vec3 getPaleGardenSkyHorizonColor() {
return vec3(138.0, 129.0, 124.0) / 255.0;
}

vec3 getPaleGardenSkyZenithColor() {
return vec3(177.0, 176.0, 175.0) / 255.0;
}

vec3 getPaleGardenSkyMidColor() {
return mix(getPaleGardenSkyHorizonColor(), getPaleGardenSkyZenithColor(), 0.5);
}

vec3 getPaleGardenFogColor() {
return getPaleGardenSkyHorizonColor();
}

vec3 getForcedBiomeFogColor(int biomeId, vec3 fallbackFog) {

#ifdef END_FOG_ENABLED
if (isForcedEndBiome(biomeId)) return vec3(END_FOG_R, END_FOG_G, END_FOG_B);
#endif

#ifdef BIOME_CRIMSON_FOREST
if (biomeId == BIOME_CRIMSON_FOREST) return vec3(0.75, 0.12, 0.08);
#endif
#ifdef BIOME_BASALT_DELTAS
if (biomeId == BIOME_BASALT_DELTAS) return vec3(0.38, 0.38, 0.40);
#endif
#if defined(BIOME_WARPED_FOREST) || defined(BIOME_SOUL_SAND_VALLEY)
#ifdef BIOME_WARPED_FOREST
if (biomeId == BIOME_WARPED_FOREST) return vec3(0.09, 0.83, 1.00);
#endif
#ifdef BIOME_SOUL_SAND_VALLEY
if (biomeId == BIOME_SOUL_SAND_VALLEY) return vec3(0.10, 0.72, 0.76);
#endif
#endif

if (isForcedNetherBiome(biomeId)) return fallbackFog;

if (isForcedSnowyBiome(biomeId)) return vec3(0.92, 0.94, 0.96);
if (isForcedSavannaBiome(biomeId)) return getSavannaSkyHorizonColor();
if (isForcedDesertBiome(biomeId)) return vec3(235.0, 213.0, 185.0) / 255.0;
if (isForcedSwampyBiome(biomeId)) return vec3(0.32, 0.42, 0.28);
if (isForcedJungleBiome(biomeId)) return vec3(0.36, 0.62, 0.28);
if (isForcedPaleGardenBiome(biomeId)) return getPaleGardenFogColor();
return fallbackFog;
}

vec3 getForcedBiomeSkyColor(int biomeId, vec3 fallbackSky) {
#ifdef END_SKY_ENABLED
if (isForcedEndBiome(biomeId)) return vec3(END_SKY_ZENITH_R, END_SKY_ZENITH_G, END_SKY_ZENITH_B);
#endif
if (isForcedSnowyBiome(biomeId)) return vec3(0.85, 0.90, 0.98);
if (isForcedSavannaBiome(biomeId)) return getSavannaSkyZenithColor();
if (isForcedDesertBiome(biomeId)) return vec3(150.0, 145.0, 207.0) / 255.0;
if (isForcedSwampyBiome(biomeId)) return vec3(0.45, 0.55, 0.42);
if (isForcedJungleBiome(biomeId)) return vec3(0.28, 0.56, 0.24);
if (isForcedPaleGardenBiome(biomeId)) return getPaleGardenSkyZenithColor();

return fallbackSky;
}

vec3 getForcedBiomeFogColorCat(int biomeId, int biomeCategory, vec3 fallbackFog) {

if (isForcedSnowyBiome(biomeId) || isCategorySnowy(biomeCategory)) return vec3(0.92, 0.94, 0.96);
if (isForcedSwampyBiome(biomeId) || isCategorySwampy(biomeCategory)) return vec3(66.0, 128.0, 75.0) / 255.0;
if (isForcedJungleBiome(biomeId) || isCategoryJungle(biomeCategory)) return vec3(81.0, 189.0, 92.0) / 255.0;
if (isForcedSavannaBiome(biomeId) || isCategorySavanna(biomeCategory)) {
return getSavannaSkyHorizonColor();
}
if (isForcedDesertBiome(biomeId) || isCategoryDesert(biomeCategory)) {
return vec3(235.0, 213.0, 185.0) / 255.0;
}
if (isForcedPaleGardenBiome(biomeId)) return getPaleGardenFogColor();
return fallbackFog;
}

vec3 getForcedBiomeSkyColorCat(int biomeId, int biomeCategory, vec3 fallbackSky) {

if (isForcedSnowyBiome(biomeId) || isCategorySnowy(biomeCategory)) return vec3(0.75, 0.85, 0.95);
if (isForcedSwampyBiome(biomeId) || isCategorySwampy(biomeCategory)) return vec3(144.0, 199.0, 90.0) / 255.0;
if (isForcedJungleBiome(biomeId) || isCategoryJungle(biomeCategory)) return vec3(122.0, 211.0, 255.0) / 255.0;
if (isForcedSavannaBiome(biomeId) || isCategorySavanna(biomeCategory)) {
return getSavannaSkyZenithColor();
}
if (isForcedDesertBiome(biomeId) || isCategoryDesert(biomeCategory)) {
return vec3(150.0, 145.0, 207.0) / 255.0;
}
if (isForcedPaleGardenBiome(biomeId)) return getPaleGardenSkyZenithColor();
return fallbackSky;
}

vec3 getForcedBiomeSkyHorizonCat(int biomeId, int biomeCategory, vec3 fallbackHorizon) {
if (isForcedSnowyBiome(biomeId) || isCategorySnowy(biomeCategory)) return vec3(0.92, 0.94, 0.96);
if (isForcedSwampyBiome(biomeId) || isCategorySwampy(biomeCategory)) return vec3(66.0, 128.0, 75.0) / 255.0;
if (isForcedJungleBiome(biomeId) || isCategoryJungle(biomeCategory)) return vec3(81.0, 189.0, 92.0) / 255.0;
if (isForcedSavannaBiome(biomeId) || isCategorySavanna(biomeCategory)) {
return getSavannaSkyHorizonColor();
}
if (isForcedDesertBiome(biomeId) || isCategoryDesert(biomeCategory)) {
return vec3(235.0, 213.0, 185.0) / 255.0;
}
if (isForcedPaleGardenBiome(biomeId)) return getPaleGardenSkyHorizonColor();
return fallbackHorizon;
}

vec3 getForcedBiomeSkyMidCat(int biomeId, int biomeCategory, vec3 fallbackMid) {
if (isForcedSnowyBiome(biomeId) || isCategorySnowy(biomeCategory)) return vec3(0.92, 0.94, 0.98);

if (isForcedSwampyBiome(biomeId) || isCategorySwampy(biomeCategory)) return vec3(83.0, 77.0, 102.0) / 255.0;
if (isForcedJungleBiome(biomeId) || isCategoryJungle(biomeCategory)) return vec3(154.0, 194.0, 110.0) / 255.0;
if (isForcedSavannaBiome(biomeId) || isCategorySavanna(biomeCategory)) {
return getSavannaSkyMidColor();
}
if (isForcedDesertBiome(biomeId) || isCategoryDesert(biomeCategory)) {
return vec3(214.0, 206.0, 224.0) / 255.0;
}
if (isForcedPaleGardenBiome(biomeId)) return getPaleGardenSkyMidColor();
return fallbackMid;
}

vec3 getForcedBiomeSkyZenithCat(int biomeId, int biomeCategory, vec3 fallbackZenith) {
if (isForcedSnowyBiome(biomeId) || isCategorySnowy(biomeCategory)) return vec3(0.75, 0.85, 0.95);
if (isForcedSwampyBiome(biomeId) || isCategorySwampy(biomeCategory)) return vec3(144.0, 199.0, 90.0) / 255.0;
if (isForcedJungleBiome(biomeId) || isCategoryJungle(biomeCategory)) return vec3(122.0, 211.0, 255.0) / 255.0;
if (isForcedSavannaBiome(biomeId) || isCategorySavanna(biomeCategory)) {
return getSavannaSkyZenithColor();
}
if (isForcedPaleGardenBiome(biomeId)) return getPaleGardenSkyZenithColor();
if (isForcedDesertBiome(biomeId) || isCategoryDesert(biomeCategory)) {
return vec3(150.0, 145.0, 207.0) / 255.0;
}
return fallbackZenith;
}

float getAridWeightWithoutSavanna(float wArid, float wSavanna) {
return clamp(wArid, 0.0, 1.0);
}

vec3 getSmoothBiomeFogColor(vec3 defaultFog, float wSnowy, float wJungle, float wSwamp, float wArid) {
vec3 result = defaultFog;
if (wSnowy  > 0.001) result = mix(result, vec3(0.92, 0.94, 0.96), wSnowy);
if (wJungle > 0.001) result = mix(result, vec3(81.0, 189.0, 92.0) / 255.0,  wJungle);
if (wSwamp  > 0.001) result = mix(result, vec3(66.0, 128.0, 75.0) / 255.0,  wSwamp);
if (wArid   > 0.001) result = mix(result, vec3(235.0, 213.0, 185.0) / 255.0, wArid);
return result;
}

vec3 getSmoothBiomeFogColorSavanna(vec3 defaultFog, float wSnowy, float wJungle, float wSwamp, float wArid, float wSavanna) {
float savanna = getSavannaWeightWithoutSwamp(wSavanna, wSwamp);
vec3 result = getSmoothBiomeFogColor(defaultFog, wSnowy, wJungle, wSwamp, getAridWeightWithoutSavanna(wArid, savanna));
if (savanna > 0.001) result = mix(result, getSavannaSkyHorizonColor(), savanna);
if (biome_pale_garden > 0.001) result = mix(result, getPaleGardenFogColor(), clamp(biome_pale_garden, 0.0, 1.0));
return result;
}

vec3 getSmoothBiomeSkyZenith(vec3 defaultZenith, float wSnowy, float wJungle, float wSwamp, float wArid) {
vec3 result = defaultZenith;
if (wSnowy  > 0.001) result = mix(result, vec3(0.75, 0.85, 0.95), wSnowy);
if (wJungle > 0.001) result = mix(result, vec3(122.0, 211.0, 255.0) / 255.0, wJungle);
if (wSwamp  > 0.001) result = mix(result, vec3(144.0, 199.0, 90.0) / 255.0,  wSwamp);
if (wArid   > 0.001) result = mix(result, vec3(150.0, 145.0, 207.0) / 255.0, wArid);
return result;
}

vec3 getSmoothBiomeSkyZenithSavanna(vec3 defaultZenith, float wSnowy, float wJungle, float wSwamp, float wArid, float wSavanna) {
float savanna = getSavannaWeightWithoutSwamp(wSavanna, wSwamp);
vec3 result = getSmoothBiomeSkyZenith(defaultZenith, wSnowy, wJungle, wSwamp, getAridWeightWithoutSavanna(wArid, savanna));
if (savanna > 0.001) result = mix(result, getSavannaSkyZenithColor(), savanna);
if (biome_pale_garden > 0.001) result = mix(result, getPaleGardenSkyZenithColor(), clamp(biome_pale_garden, 0.0, 1.0));
return result;
}

vec3 getSmoothBiomeSkyHorizon(vec3 defaultHorizon, float wSnowy, float wJungle, float wSwamp, float wArid) {
vec3 result = defaultHorizon;
if (wSnowy  > 0.001) result = mix(result, vec3(0.92, 0.94, 0.96), wSnowy);
if (wJungle > 0.001) result = mix(result, vec3(81.0, 189.0, 92.0) / 255.0,  wJungle);
if (wSwamp  > 0.001) result = mix(result, vec3(66.0, 128.0, 75.0) / 255.0,  wSwamp);
if (wArid   > 0.001) result = mix(result, vec3(235.0, 213.0, 185.0) / 255.0, wArid);
return result;
}

vec3 getSmoothBiomeSkyHorizonSavanna(vec3 defaultHorizon, float wSnowy, float wJungle, float wSwamp, float wArid, float wSavanna) {
float savanna = getSavannaWeightWithoutSwamp(wSavanna, wSwamp);
vec3 result = getSmoothBiomeSkyHorizon(defaultHorizon, wSnowy, wJungle, wSwamp, getAridWeightWithoutSavanna(wArid, savanna));
if (savanna > 0.001) result = mix(result, getSavannaSkyHorizonColor(), savanna);
if (biome_pale_garden > 0.001) result = mix(result, getPaleGardenSkyHorizonColor(), clamp(biome_pale_garden, 0.0, 1.0));
return result;
}

vec3 getSmoothBiomeSkyMid(vec3 defaultMid, float wSnowy, float wJungle, float wSwamp, float wArid) {
vec3 result = defaultMid;
if (wSnowy  > 0.001) result = mix(result, vec3(0.92, 0.94, 0.98), wSnowy);
if (wJungle > 0.001) result = mix(result, vec3(154.0, 194.0, 110.0) / 255.0, wJungle);
if (wSwamp  > 0.001) result = mix(result, vec3(83.0, 77.0, 102.0) / 255.0,   wSwamp);
if (wArid   > 0.001) result = mix(result, vec3(214.0, 206.0, 224.0) / 255.0, wArid);
return result;
}

vec3 getSmoothBiomeSkyMidSavanna(vec3 defaultMid, float wSnowy, float wJungle, float wSwamp, float wArid, float wSavanna) {
float savanna = getSavannaWeightWithoutSwamp(wSavanna, wSwamp);
vec3 result = getSmoothBiomeSkyMid(defaultMid, wSnowy, wJungle, wSwamp, getAridWeightWithoutSavanna(wArid, savanna));
if (savanna > 0.001) result = mix(result, getSavannaSkyMidColor(), savanna);
if (biome_pale_garden > 0.001) result = mix(result, getPaleGardenSkyMidColor(), clamp(biome_pale_garden, 0.0, 1.0));
return result;
}

vec3 getCaveFogAboveTarget(int biomeId, int biomeCategory) {
vec3 aboveColor = vec3(0.18, 0.26, 0.40);
#ifdef CAVE_FOG_USE_BIOME_SKY_COLOR
return getForcedBiomeSkyZenithCat(biomeId, biomeCategory, aboveColor);
#endif
#ifdef BIOME_DRIPSTONE_CAVES
if (biomeId == BIOME_DRIPSTONE_CAVES) aboveColor = vec3(107.0,  98.0,  95.0) / 255.0;
#endif
#ifdef BIOME_LUSH_CAVES
if (biomeId == BIOME_LUSH_CAVES)      aboveColor = vec3( 80.0,  83.0,   5.0) / 255.0;
#endif
#ifdef BIOME_DEEP_DARK
if (biomeId == BIOME_DEEP_DARK)       aboveColor = vec3(0.14, 0.20, 0.30);
#endif

#ifdef BIOME_TERRALITH_GLOWING_GROTTO
if (biomeId == BIOME_TERRALITH_GLOWING_GROTTO) aboveColor = vec3(0.20, 0.55, 0.95);
#endif
#ifdef BIOME_GLOWING_GROTTO
if (biomeId == BIOME_GLOWING_GROTTO) aboveColor = vec3(0.20, 0.55, 0.95);
#endif
#ifdef BIOME_TERRALITH_CAVE_GLOWING_GROTTO
if (biomeId == BIOME_TERRALITH_CAVE_GLOWING_GROTTO) aboveColor = vec3(0.20, 0.55, 0.95);
#endif
return aboveColor;
}

vec3 getCaveFogAboveTarget(int biomeId) {
return getCaveFogAboveTarget(biomeId, 0);
}

vec3 getCaveFogColorSmoothed(vec3 smoothedAbove, float worldY) {
vec3 deepColor = smoothedAbove;
float t = smoothstep(-8.0, 8.0, worldY);
return mix(deepColor, smoothedAbove, t);
}

vec3 getCaveFogColor(int biomeId, float worldY) {
return getCaveFogColorSmoothed(getCaveFogAboveTarget(biomeId, 0), worldY);
}

#endif
