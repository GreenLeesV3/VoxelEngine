#ifndef LIGHTING_GLSL
#define LIGHTING_GLSL

#include "/include/color_utils.glsl"
#include "/include/biome_overrides.glsl"
#include "/include/sky_timeline.glsl"

#ifdef LPV_ENABLED
#include "/include/lpv/lpv_sample.glsl"
#endif

uniform float rainStrength;

uniform vec3 skyColor;
float directSunVisibility = 0.0;

#ifdef LPV_ENABLED
vec3 lpvWorldPos = vec3(0.0);
vec3 lpvWorldNormal = vec3(0.0, 1.0, 0.0);

vec3 lpvSurfaceColor = vec3(0.75);

float lpvTexLuma = 0.5;
float lpvNeutralPreserveStrength = 1.0;
float lpvReceiverStrength = 1.0;
#endif

uniform int biome;

#ifdef HANDHELD_LIGHT_ENABLED
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform int heldItemId;
uniform int heldItemId2;

uniform vec3 eyePosition;
#endif

vec3 normalizeLightColor(vec3 c);
vec3 getTimeOfDaySkylightColor(float sunAngle);
vec3 getDaySkylightTintColor();

float getVanillaFaceShade(vec3 worldNormal) {
if (worldNormal.y > 0.5) return 1.0;
if (worldNormal.y < -0.5) return 0.85;
if (abs(worldNormal.z) > 0.5) return 0.92;
return 0.88;
}

#ifdef HANDHELD_LIGHT_ENABLED
vec3 getHeldItemLightColor(int heldId) {
if (heldId == 10021 || heldId == 10043) return vec3(0.3, 0.7, 1.0);
if (heldId == 10087 || heldId == 10089) return vec3(0.3, 1.0, 0.4);
if (heldId == 10038 || heldId == 10058) return vec3(1.0, 0.2, 0.2);
return vec3(1.0, 0.75, 0.4);
}

vec3 getHandheldLightBoost(vec3 worldPos, vec3 baseColor, vec3 litColor) {
float mainHeld = clamp(float(max(heldBlockLightValue,  0)) / 15.0, 0.0, 1.0);
float offHeld  = clamp(float(max(heldBlockLightValue2, 0)) / 15.0, 0.0, 1.0);

float heldLevel = max(mainHeld, offHeld);
if (heldLevel < 0.001) return vec3(0.0);

vec3 playerCenter = eyePosition - vec3(0.0, 0.5, 0.0);
vec3 delta = worldPos - playerCenter;

float radius = max(HANDHELD_LIGHT_RADIUS, 0.01);

float xzDist = sqrt(delta.x * delta.x + delta.z * delta.z);
float yOffset = max(abs(delta.y) - 1.0, 0.0);
float dist = sqrt(xzDist * xzDist + yOffset * yOffset);

float t = clamp(dist / radius, 0.0, 1.0);
float atten = 1.0 - t * t;
atten = atten * atten * atten;

float intensity = heldLevel * atten * HANDHELD_LIGHT_STRENGTH;

float tintWeight = max(mainHeld + offHeld, 0.001);
vec3 tint = (getHeldItemLightColor(heldItemId)  * mainHeld +
getHeldItemLightColor(heldItemId2) * offHeld) / tintWeight;

vec3 lightColor = baseColor * tint * intensity;
vec3 boost = litColor + lightColor - litColor * lightColor;
return max(boost - litColor, vec3(0.0));
}
#endif

vec3 applySaturationAndVibrance(vec3 c, float saturationMult, float vibrance) {
c = max(c, vec3(0.0));

float lum = dot(c, vec3(0.299, 0.587, 0.114));
c = mix(vec3(lum), c, max(saturationMult, 0.0));

vec3 hsv = rgb2hsv(clamp(c, vec3(0.0), vec3(10.0)));
float v = clamp(vibrance, 0.0, 2.0);
hsv.y = clamp(hsv.y + (1.0 - hsv.y) * v * (1.0 - hsv.y), 0.0, 1.0);
return hsv2rgb(hsv);
}

float getStableDayFactor(float sunAngle) {
TimeWeights tw = getTimeWeights(sunAngle);
return smoothstep(0.5, 0.9, tw.day);
}

vec3 getBiomeSkylightColor() {

float biomeLum = dot(skyColor, vec3(0.299, 0.587, 0.114));
if (biomeLum <= 0.0005) return vec3(1.0);
return normalizeLightColor(skyColor);
}

vec3 getCombinedSkylightTintColor(float sunAngle) {

vec3 tod = getTimeOfDaySkylightColor(sunAngle);
vec3 biome = mix(vec3(1.0), getBiomeSkylightColor(), getStableDayFactor(sunAngle));
return normalizeLightColor(tod * biome);
}

vec3 getStaticNightTintColor() {

vec3 nightSky = vec3(NIGHT_ZENITH_R, NIGHT_ZENITH_G, NIGHT_ZENITH_B);
vec3 nightTint = normalizeLightColor(nightSky);
float nightTintLuma = dot(nightTint, vec3(0.299, 0.587, 0.114));

return normalizeLightColor(mix(vec3(nightTintLuma), nightTint, 0.08));
}

vec3 getStaticNightTintLitColor() {
vec3 nightTint = getStaticNightTintColor();
float lightSatBlend = clamp(SKYLIGHT_TINT_LIGHT_SATURATION, 0.0, 1.0);
float litSat = mix(1.0, SKYLIGHT_TINT_SATURATION, lightSatBlend);
vec3 litTint = normalizeLightColor(applySaturationAndVibrance(nightTint, litSat, 0.0));
float litTintLuma = dot(litTint, vec3(0.299, 0.587, 0.114));

return normalizeLightColor(mix(vec3(litTintLuma), litTint, 0.08));
}

vec4 getTimeOfDayLighting(float sunAngle) {
vec2 bd = getTimelineBrightness(sunAngle);

return vec4(bd.x, 0.0, 0.0, bd.y);
}

vec3 normalizeLightColor(vec3 c) {

float lum = dot(c, vec3(0.299, 0.587, 0.114));
vec3 n = c / max(lum, 0.35);
return clamp(n, vec3(0.0), vec3(2.0));
}

#ifdef LPV_ENABLED
vec3 getLpvCatchAlbedo(vec3 surfaceColor, float surfaceLuma) {
float luma = clamp(surfaceLuma, 0.0, 1.0);
float maxC = max(max(surfaceColor.r, surfaceColor.g), surfaceColor.b);
float minC = min(min(surfaceColor.r, surfaceColor.g), surfaceColor.b);
float chroma = maxC - minC;

float brightCatchMask = smoothstep(0.18, 0.88, luma);
float brightNeutralMask = smoothstep(0.72, 0.98, luma) * (1.0 - smoothstep(0.05, 0.22, chroma));
float whiteSoftener = 1.0 - 0.20 * brightNeutralMask;
float catchStrength = (1.0 + 0.55 * pow(brightCatchMask, 0.85)) * whiteSoftener;
return vec3(catchStrength);
}

vec3 blendLpvShortestHuePath(vec3 baseLit, vec3 surfaceColor, vec3 lpvContribution) {
return baseLit + surfaceColor * lpvContribution;
}
#endif

vec3 getTimeOfDaySkylightColor(float sunAngle) {
TimeWeights tw = getTimeWeights(sunAngle);

vec3 daySky     = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B);
vec3 sunsetSky  = vec3(SUNSET_ZENITH_R, SUNSET_ZENITH_G, SUNSET_ZENITH_B);
vec3 blueSky    = vec3(BLUEHOUR_ZENITH_R, BLUEHOUR_ZENITH_G, BLUEHOUR_ZENITH_B);
vec3 nightSky   = vec3(NIGHT_ZENITH_R, NIGHT_ZENITH_G, NIGHT_ZENITH_B);
vec3 sunriseSky = vec3(SUNRISE_ZENITH_R, SUNRISE_ZENITH_G, SUNRISE_ZENITH_B);
vec3 dawnSky    = vec3(DAWN_ZENITH_R, DAWN_ZENITH_G, DAWN_ZENITH_B);

vec3 sky = daySky     * tw.day
+ sunsetSky  * tw.sunset
+ blueSky    * tw.blueHour
+ nightSky   * tw.night
+ sunriseSky * tw.sunrise
+ dawnSky    * tw.dawn;

float daySunsetMix = min(tw.day, tw.sunset) * 2.0;
sky = mix(sky, vec3(0.9, 0.15, 0.85), daySunsetMix * 0.5);
float sunsetBlueMix = min(tw.sunset, tw.blueHour) * 2.0;
sky = mix(sky, vec3(0.4, 0.1, 1.0), sunsetBlueMix * 0.5);

return normalizeLightColor(sky);
}

vec3 getDaySkylightTintColor() {
vec3 daySky = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B);
return normalizeLightColor(daySky);
}

float getVanillaSkylightBrightness(float skylight) {
float light = clamp(skylight, 0.0, 1.0);
return light / (4.0 - 3.0 * light);
}

float getQuantizedLightLevel(float light) {
return floor(clamp(light, 0.0, 1.0) * 15.0 + 0.001);
}

float getHasSkylightMask(float skylight) {

return smoothstep(1.0 / 15.0, 2.0 / 15.0, clamp(skylight, 0.0, 1.0));
}

float getZeroSkylightMask(float skylight) {
return 1.0 - getHasSkylightMask(skylight);
}

float getZeroBlocklightMask(float blocklight) {
return 1.0 - smoothstep(0.0, 4.0 / 15.0, clamp(blocklight, 0.0, 1.0));
}

float getBlocklightFalloff(float blocklight, float skylight) {
float x = clamp(blocklight, 0.0, 1.0);
float falloff = x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
falloff *= smoothstep(0.0, 0.15, blocklight);
return falloff;
}

vec3 getBlockLightColor(float intensity) {
vec3 warmLight = vec3(1.0, 0.9, 0.8);
return warmLight * intensity * intensity * BLOCKLIGHT_BRIGHTNESS;
}

float getNightDarkenAmount(float todBrightness, float skylight, float blocklight) {
float nightFactor = 1.0 - smoothstep(0.0, 0.35, todBrightness);
float skylightGate = getHasSkylightMask(skylight);
float blocklightGate = 1.0 - smoothstep(0.45, 0.95, blocklight);
return NIGHT_DARKNESS * nightFactor * skylightGate * blocklightGate;
}

float getWeatherDarkenAmount(float todBrightness, float skylight, float blocklight) {
float dayFactor = smoothstep(0.28, 0.88, todBrightness);
float skylightGate = getHasSkylightMask(skylight);
float blocklightGate = 1.0 - smoothstep(0.30, 0.95, blocklight);
float weatherDarkness = float(SKY_RAIN_DARKNESS) / 100.0;
return rainStrength * dayFactor * skylightGate * blocklightGate * weatherDarkness;
}

float getPaleGardenDarkenAmount(float todBrightness, float skylight, float blocklight) {
float dayFactor = smoothstep(0.28, 0.88, todBrightness);
float skylightGate = getHasSkylightMask(skylight);
float blocklightGate = 1.0 - smoothstep(0.30, 0.95, blocklight);
return clamp(biome_pale_garden, 0.0, 1.0) * dayFactor * skylightGate * blocklightGate;
}

float getCaveLookAmount(float skylight, float blocklight) {
float caveTintGate = 1.0 - smoothstep(0.00, 7.0 / 15.0, skylight);
float zeroBlocklightMask = getZeroBlocklightMask(blocklight);
return caveTintGate * zeroBlocklightMask;
}

float getCaveTintAmount(float skylight, float blocklight) {
if (isEyeInWater == 1) return 0.0;
float caveTintGate = 1.0 - smoothstep(0.00, 14.0 / 15.0, skylight);
float zeroBlocklightMask = getZeroBlocklightMask(blocklight);
return caveTintGate * zeroBlocklightMask;
}

float getCaveDarkenAmount(float skylight, float blocklight) {
if (isEyeInWater == 1) return 0.0;

float caveTintFade = getCaveTintAmount(skylight, blocklight);
return CAVE_DARKNESS * caveTintFade * caveTintFade;
}

float getSunMoonShadowTransitionDip(float sunAngle) {
float angle = fract(sunAngle);
float sunsetTransitionDip = smoothstep(0.46, 0.5146, angle) * (1.0 - smoothstep(0.5146, 0.57, angle));
float sunriseTransitionDip = max(
smoothstep(0.93, 0.9854, angle),
1.0 - smoothstep(0.0146, 0.07, angle)
);
return max(sunsetTransitionDip, sunriseTransitionDip);
}

float getSunMoonShadowTransitionShadowFloor(float todBrightness, float skylight) {
float isNightTime = 1.0 - smoothstep(0.0, 0.25, todBrightness);
return 0.15 * clamp(skylight, 0.0, 1.0) * (1.0 - isNightTime * 0.75);
}

float getSunMoonShadowTransitionDarken(float transitionDip, float todBrightness, float skylight) {
float shadowFloor = getSunMoonShadowTransitionShadowFloor(todBrightness, skylight);
float transitionTarget = mix(1.0, shadowFloor, SHADOW_OPACITY);
return mix(1.0, transitionTarget, transitionDip);
}

vec3 applyLighting(vec3 color, float sunAngle, float skylight, float blocklight, float worldY) {
vec4 todLighting = getTimeOfDayLighting(sunAngle);
float todBrightness = todLighting.x;
float darkness = todLighting.w;

float swampNightExtra = smoothstep(0.15, 0.0, todBrightness) * 0.5;
todBrightness *= mix(1.0, 0.6 - swampNightExtra, biome_swamp);

float angle_ = fract(sunAngle);

bool isNether = isForcedNetherBiome(biome);

float zeroSkylightLift = (1.0 - step(0.5, getQuantizedLightLevel(skylight))) * (1.0 / 15.0);
float effectiveSkylight = isNether ? 1.0 : max(skylight, zeroSkylightLift);
float lmSkylight = isNether ? 1.0 : getVanillaSkylightBrightness(effectiveSkylight);
float sunsetTintBoost = smoothstep(0.38, 0.45, angle_) * (1.0 - smoothstep(0.48, 0.55, angle_))
+ smoothstep(0.95, 1.0, angle_) + (1.0 - smoothstep(0.0, 0.05, angle_));

float dayTintReduce = smoothstep(0.07, 0.15, angle_) * (1.0 - smoothstep(0.40, 0.46, angle_));

float nightTintReduce = smoothstep(0.58, 0.66, angle_) * (1.0 - smoothstep(0.92, 0.98, angle_));
float baseTint = SKYLIGHT_COLOR_TINT * (1.0 - dayTintReduce * 0.6) * (1.0 - nightTintReduce * 0.7);
float tintStrength = clamp(baseTint + sunsetTintBoost * SUNSET_TERRAIN_TINT, 0.0, 1.0);
float lightSatBlend = clamp(SKYLIGHT_TINT_LIGHT_SATURATION, 0.0, 1.0);

vec3 caveTint = getStaticNightTintColor();
float terrainShadingBlocklight = blocklight;
#ifdef LPV_ENABLED
terrainShadingBlocklight = 0.0;
#endif
float sunlitLowSkySuppress = clamp(directSunVisibility, 0.0, 1.0);
float rawCaveTintAmount = getCaveTintAmount(skylight, terrainShadingBlocklight);
vec3 caveTintApplied = getStaticNightTintLitColor();
float isDaySuppress = isNether ? 0.0 : smoothstep(0.25, 0.85, todBrightness);
float effectiveBlocklight = clamp(blocklight * (1.0 - BLOCKLIGHT_SKYLIGHT_REDUCTION * lmSkylight * isDaySuppress), 0.0, 1.0);
float blocklightFalloff = getBlocklightFalloff(effectiveBlocklight, lmSkylight);
vec3 vanillaBlockLight = getBlockLightColor(blocklightFalloff);
float skyVis = lmSkylight;
float blocklightSkySuppress = 1.0 - smoothstep(5.0 / 15.0, 1.0, skyVis * isDaySuppress);
float lpvCaveSuppress = 0.0;
#ifdef LPV_ENABLED
#if LPV_ISOLATION_STAGE > 0
float nightFactorLpv = 1.0 - smoothstep(0.0, 1.0, todBrightness);

float skylightGateLpv = smoothstep(7.0 / 15.0, 12.0 / 15.0, skylight);
float nightDimAmountLpv = nightFactorLpv * skylightGateLpv;
float lpvNightMul = mix(1.0, LPV_NIGHT_STRENGTH, nightDimAmountLpv);
vec3 blockLight = sampleLpvLight(lpvWorldPos, lpvWorldNormal, blocklightFalloff) * BLOCKLIGHT_BRIGHTNESS * lpvNightMul * lpvReceiverStrength;
#else
vec3 blockLight = vec3(0.0);
#endif
#else
vec3 blockLight = vanillaBlockLight;
#endif
float caveTintAmount = rawCaveTintAmount * (1.0 - lpvCaveSuppress) * (1.0 - sunlitLowSkySuppress);
vec3 tintBase = mix(getCombinedSkylightTintColor(sunAngle), caveTint, caveTintAmount);
float caveTintBaseLuma = dot(tintBase, vec3(0.299, 0.587, 0.114));
tintBase = mix(tintBase, mix(vec3(caveTintBaseLuma), tintBase, 0.32), caveTintAmount);

{
float tbLuma = dot(tintBase, vec3(0.299, 0.587, 0.114));
tintBase = mix(tintBase, vec3(tbLuma), nightTintReduce * 0.85);
}

float sunsetSatBoost = 1.0 + sunsetTintBoost * (SUNSET_TERRAIN_TINT * 1.09);
vec3 tintShadow = normalizeLightColor(applySaturationAndVibrance(tintBase, SKYLIGHT_TINT_SATURATION * sunsetSatBoost, 0.0));
float litSat = mix(1.0, SKYLIGHT_TINT_SATURATION * sunsetSatBoost, lightSatBlend);
vec3 tintLit = normalizeLightColor(applySaturationAndVibrance(tintBase, litSat, 0.0));

float visibleTintStrength = clamp(tintStrength * 0.68, 0.0, 1.0);
vec3 visibleTintShadow = normalizeLightColor(mix(vec3(1.0), tintShadow, visibleTintStrength));
vec3 visibleTintLit = normalizeLightColor(mix(vec3(1.0), tintLit, visibleTintStrength));

#ifdef END_SHADER
float skyTintGate = 0.0;
vec3 skyTint = vec3(1.0);
#else

float skyTintGate = smoothstep(1.0 / 15.0, 1.0, skylight);
vec3 skyTint = mix(vec3(1.0), tintShadow, tintStrength * lmSkylight * skyTintGate);
#endif

vec3 rawShadowHue = hueToRGB(SHADOW_HUE > 0.0 ? 180.0 + SHADOW_HUE : 360.0 + SHADOW_HUE);
float hueLuminance = dot(rawShadowHue, vec3(0.299, 0.587, 0.114));
vec3 normalizedHue = rawShadowHue / max(hueLuminance, 0.3);
normalizedHue = min(normalizedHue, vec3(2.0));

float nightSatReduce = smoothstep(0.0, 0.20, todBrightness);
float caveSatReduce = smoothstep(0.10, 0.55, lmSkylight);
float effectiveLmSat = mix(LIGHTMAP_SATURATION * 0.10, LIGHTMAP_SATURATION, nightSatReduce * caveSatReduce);
vec3 shadowTintColor = normalizedHue;

float lightAmount = clamp(lmSkylight * todBrightness, 0.0, 1.0);

float shadowDark = 0.15 * lmSkylight;

vec3 darkShadowColor = visibleTintShadow * shadowDark;

vec3 litColor = visibleTintLit;
vec3 lightMultiplier = mix(darkShadowColor, litColor, lightAmount);
if (isNether) lightMultiplier *= NETHER_BRIGHTNESS;

float caveDarkenAmount = getCaveDarkenAmount(skylight, terrainShadingBlocklight) * (1.0 - lpvCaveSuppress);
vec3 skylitResult = color * lightMultiplier;
float nightDarkenAmount = getNightDarkenAmount(todBrightness, skylight, terrainShadingBlocklight);
float weatherDarkenAmount = getWeatherDarkenAmount(todBrightness, skylight, terrainShadingBlocklight);
float paleGardenDarkenAmount = getPaleGardenDarkenAmount(todBrightness, skylight, terrainShadingBlocklight);
skylitResult *= mix(vec3(1.0), caveTintApplied, caveTintAmount);
skylitResult *= 1.0 - nightDarkenAmount * 0.45;

skylitResult *= 1.0 - weatherDarkenAmount * 0.45 * lightAmount;

skylitResult *= 1.0 - paleGardenDarkenAmount * 0.40 * lightAmount;
skylitResult *= 1.0 - caveDarkenAmount * 0.45;

vec3 blockContribution = vec3(0.0);
vec3 blockAssistTint = tintBase;
#ifdef END_SHADER
vec3 endBlockColor = vec3(END_BLOCKLIGHT_R, END_BLOCKLIGHT_G, END_BLOCKLIGHT_B);
vec3 endBlockLight = endBlockColor * blocklightFalloff * blocklightFalloff * END_BLOCKLIGHT_BRIGHTNESS;
blockAssistTint = normalizeLightColor(endBlockColor);
blockContribution = color * endBlockLight;
vec3 result = skylitResult + blockContribution;
#else
#ifdef LPV_ENABLED

vec3 lpvAlbedo = getLpvCatchAlbedo(lpvSurfaceColor, lpvTexLuma);
vec3 rawLpvLight = blockLight * blocklightSkySuppress;
vec3 lpvContribution = lpvAlbedo * rawLpvLight;
blockAssistTint = normalizeLightColor(max(blockLight, vec3(0.001)));
blockContribution = lpvContribution;
vec3 result = blendLpvShortestHuePath(skylitResult, lpvSurfaceColor, blockContribution);

#else
blockAssistTint = normalizeLightColor(max(blockLight, vec3(0.001)));
blockContribution = color * blockLight * blocklightSkySuppress;
vec3 result = skylitResult + blockContribution;
#endif
#endif

float seaLevel = float(SEA_LEVEL_OFFSET);
float depthBelow = max(seaLevel - worldY, 0.0);
float heightAmbient = 1.0 - smoothstep(0.0, 96.0, depthBelow);

float undergroundBright = mix(0.30, 0.18, heightAmbient);
float interiorBright = 0.35;
float enclosedFactor = 1.0 - lmSkylight;
float undergroundBlend = smoothstep(24.0, 96.0, depthBelow);
float baseInteriorToCave = mix(interiorBright, undergroundBright, undergroundBlend);
float lowSkylightFloorFade = getHasSkylightMask(skylight);
float ambientFloorFactor = mix(1.0, enclosedFactor + darkness * 0.5 * lmSkylight, lowSkylightFloorFade);
float minBright = mix(CAVE_AMBIENT_FLOOR, baseInteriorToCave, 1.0 - caveDarkenAmount)
* ambientFloorFactor;
minBright *= 1.0 - nightDarkenAmount * 0.35;

minBright *= 1.0 - caveDarkenAmount * 0.35;
float zeroSkylightAmbientMask = getZeroSkylightMask(skylight) * getZeroBlocklightMask(terrainShadingBlocklight);
minBright = max(minBright, 0.08 * zeroSkylightAmbientMask);
vec3 ambientFloorColor = color * minBright * tintBase;
float albedoLuma = dot(color, vec3(0.299, 0.587, 0.114));
float darkAlbedoAssist = zeroSkylightAmbientMask * (1.0 - smoothstep(0.04, 0.25, albedoLuma));

ambientFloorColor = max(ambientFloorColor, color * tintBase * minBright * (1.0 + 0.5 * darkAlbedoAssist));
result = max(result, ambientFloorColor);
float darkSurfaceMask = 1.0 - smoothstep(0.04, 0.22, albedoLuma);
float lowSkylightAssist = 1.0 - smoothstep(0.08, 0.45, lmSkylight);
vec3 lowSkylightAssistColor = color * tintBase * (minBright * 0.35) * darkSurfaceMask * lowSkylightAssist;
vec3 blockAssistColor = vec3(0.0);
#if !defined(LPV_ENABLED) || defined(END_SHADER)
float blocklightAssist = smoothstep(0.04, 0.30, blocklightFalloff) * blocklightSkySuppress;
vec3 blockAssistBlendTint = normalizeLightColor(mix(tintBase, tintBase * blockAssistTint, 0.55));
blockAssistColor = color * blockAssistBlendTint * (0.08 * blocklightFalloff) * darkSurfaceMask * blocklightAssist;
#endif
vec3 darkSurfaceAssistColor = lowSkylightAssistColor + blockAssistColor;
result = max(result, darkSurfaceAssistColor);

#ifdef SHADOW_DEBUG_TINT
float debugShadowMask = clamp(1.0 - lightAmount, 0.0, 1.0);
result = mix(result, vec3(1.0, 0.1, 0.1), debugShadowMask * 0.85);
#endif

#ifdef CAVE_LIGHT_DEBUG
float lowSkyDebug = 1.0 - lmSkylight;
float caveFloorDebug = clamp(minBright / max(dot(color, vec3(0.3333)), 0.001), 0.0, 1.0);
vec3 debugColor = vec3(caveFloorDebug, 0.0, lowSkyDebug);
result = mix(result, debugColor, 0.9);
#endif

return result;
}

vec3 applyLightingWithShadow(vec3 color, float sunAngle, float skylight, float blocklight, float emissive, vec3 shadow, float worldY) {
if (emissive > 0.5) {
#ifdef END_SHADER

return color * EMISSIVE_BRIGHTNESS * END_EMISSIVE_BOOST;
#else
return color * EMISSIVE_BRIGHTNESS;
#endif
}

vec4 todLighting = getTimeOfDayLighting(sunAngle);
float todBrightness = todLighting.x;
float darkness = todLighting.w;

float swampNightExtra = smoothstep(0.15, 0.0, todBrightness) * 0.5;
todBrightness *= mix(1.0, 0.6 - swampNightExtra, biome_swamp);

bool isNether = isForcedNetherBiome(biome);

float zeroSkylightLift = (1.0 - step(0.5, getQuantizedLightLevel(skylight))) * (1.0 / 15.0);
float effectiveSkylight = isNether ? 1.0 : max(skylight, zeroSkylightLift);
float lmSkylight = isNether ? 1.0 : getVanillaSkylightBrightness(effectiveSkylight);

float angleS = fract(sunAngle);
float sunsetTintBoostS = smoothstep(0.38, 0.45, angleS) * (1.0 - smoothstep(0.48, 0.55, angleS))
+ smoothstep(0.95, 1.0, angleS) + (1.0 - smoothstep(0.0, 0.05, angleS));

float dayTintReduceS = smoothstep(0.07, 0.15, angleS) * (1.0 - smoothstep(0.40, 0.46, angleS));

float nightTintReduceS = smoothstep(0.58, 0.66, angleS) * (1.0 - smoothstep(0.92, 0.98, angleS));
float baseTintS = SKYLIGHT_COLOR_TINT * (1.0 - dayTintReduceS * 0.6) * (1.0 - nightTintReduceS * 0.7);
float tintStrength = clamp(baseTintS + sunsetTintBoostS * SUNSET_TERRAIN_TINT, 0.0, 1.0);
float lightSatBlend = clamp(SKYLIGHT_TINT_LIGHT_SATURATION, 0.0, 1.0);

vec3 caveTint = getStaticNightTintColor();
float terrainShadingBlocklight = blocklight;
#ifdef LPV_ENABLED
terrainShadingBlocklight = 0.0;
#endif
float rawCaveTintAmount = getCaveTintAmount(skylight, terrainShadingBlocklight);
vec3 caveTintApplied = getStaticNightTintLitColor();
float isDaySuppress = isNether ? 0.0 : smoothstep(0.25, 0.85, todBrightness);
float effectiveBlocklight = clamp(blocklight * (1.0 - BLOCKLIGHT_SKYLIGHT_REDUCTION * lmSkylight * isDaySuppress), 0.0, 1.0);
float blocklightFalloff = getBlocklightFalloff(effectiveBlocklight, lmSkylight);
float shadowOverride = clamp(blocklightFalloff * BLOCKLIGHT_SHADOW_OVERRIDE, 0.0, 1.0);
#ifdef LPV_ENABLED
shadowOverride = 0.0;
#endif
vec3 vanillaBlockLight = getBlockLightColor(blocklightFalloff);
float skyVis = lmSkylight;
float blocklightSkySuppress = 1.0 - smoothstep(5.0 / 15.0, 1.0, skyVis * isDaySuppress);
float lpvCaveSuppress = 0.0;
#ifdef LPV_ENABLED
#if LPV_ISOLATION_STAGE > 0

float skylightGate = smoothstep(7.0 / 15.0, 12.0 / 15.0, skylight);
float nightFactor = 1.0 - smoothstep(0.0, 1.0, todBrightness);
float nightDimAmount = nightFactor * skylightGate;
float lpvNightMul = mix(1.0, LPV_NIGHT_STRENGTH, nightDimAmount);
vec3 lpvDetectLight = sampleLpvLight(lpvWorldPos, lpvWorldNormal, blocklightFalloff) * BLOCKLIGHT_BRIGHTNESS * lpvNightMul * lpvReceiverStrength;
vec3 blockLight = lpvDetectLight * 5.0;
#else
vec3 blockLight = vec3(0.0);
#endif
#else
vec3 blockLight = vanillaBlockLight;
#endif
float sunlitLowSkySuppress = clamp(directSunVisibility, 0.0, 1.0);
float caveTintAmount = rawCaveTintAmount * (1.0 - lpvCaveSuppress) * (1.0 - sunlitLowSkySuppress);
vec3 tintBase = mix(getCombinedSkylightTintColor(sunAngle), caveTint, caveTintAmount);
float caveTintBaseLuma = dot(tintBase, vec3(0.299, 0.587, 0.114));
tintBase = mix(tintBase, mix(vec3(caveTintBaseLuma), tintBase, 0.32), caveTintAmount);

{
float tbLumaS = dot(tintBase, vec3(0.299, 0.587, 0.114));
tintBase = mix(tintBase, vec3(tbLumaS), nightTintReduceS * 0.85);
}
float sunsetSatBoostS = 1.0 + sunsetTintBoostS * (SUNSET_TERRAIN_TINT * 1.09);
vec3 tintShadow = normalizeLightColor(applySaturationAndVibrance(tintBase, SKYLIGHT_TINT_SATURATION * sunsetSatBoostS, 0.0));
float litSat = mix(1.0, SKYLIGHT_TINT_SATURATION * sunsetSatBoostS, lightSatBlend);
vec3 tintLit = normalizeLightColor(applySaturationAndVibrance(tintBase, litSat, 0.0));
float visibleTintStrength = clamp(tintStrength * 0.68, 0.0, 1.0);
vec3 visibleTintShadow = normalizeLightColor(mix(vec3(1.0), tintShadow, visibleTintStrength));
vec3 visibleTintLit = normalizeLightColor(mix(vec3(1.0), tintLit, visibleTintStrength));

#ifdef END_SHADER
float skyTintGate = 0.0;
vec3 skyTint = vec3(1.0);
#else

float skyTintGate = smoothstep(1.0 / 15.0, 1.0, skylight);
vec3 skyTint = mix(vec3(1.0), tintShadow, tintStrength * lmSkylight * skyTintGate);
#endif

vec3 rawShadowHue = hueToRGB(SHADOW_HUE > 0.0 ? 180.0 + SHADOW_HUE : 360.0 + SHADOW_HUE);
float hueLuminance = dot(rawShadowHue, vec3(0.299, 0.587, 0.114));
vec3 normalizedHue = rawShadowHue / max(hueLuminance, 0.3);
normalizedHue = min(normalizedHue, vec3(2.0));

float nightSatReduceS = smoothstep(0.0, 0.20, todBrightness);
float caveSatReduceS = smoothstep(0.10, 0.55, lmSkylight);
float effectiveShadowSat = mix(SHADOW_SATURATION * 0.10, SHADOW_SATURATION, nightSatReduceS * caveSatReduceS);
vec3 shadowTintColor = normalizedHue;

float shadowVal = dot(shadow, vec3(0.299, 0.587, 0.114));

float shadowValLifted = mix(shadowVal, 1.0, shadowOverride);

float sunlitLmSkylight = max(lmSkylight, sunlitLowSkySuppress);
float lightAmount = clamp(sunlitLmSkylight * todBrightness * shadowValLifted, 0.0, 1.0);

float isNightTime = 1.0 - smoothstep(0.0, 0.25, todBrightness);
float shadowDark = 0.15 * sunlitLmSkylight * (1.0 - isNightTime * 0.75);
float lowSkyInteriorHeightGate = smoothstep(float(SEA_LEVEL_OFFSET) - 4.0, float(SEA_LEVEL_OFFSET) + 2.0, worldY);
float lowSkyInteriorShadowFloor = getStableDayFactor(sunAngle) * (1.0 - smoothstep(0.08, 0.35, lmSkylight)) * lowSkyInteriorHeightGate * sunlitLowSkySuppress;
shadowDark = max(shadowDark, 0.08 * lowSkyInteriorShadowFloor);

lightAmount += sunlitLmSkylight * shadowValLifted * isNightTime * 0.30;

vec3 darkShadowColor = visibleTintShadow * shadowDark;

vec3 litColor = visibleTintLit;
vec3 lightMultiplier = mix(darkShadowColor, litColor, lightAmount);

if (isNether) lightMultiplier *= NETHER_BRIGHTNESS;

float caveDarkenAmount = getCaveDarkenAmount(skylight, terrainShadingBlocklight) * (1.0 - lpvCaveSuppress) * (1.0 - sunlitLowSkySuppress);
vec3 skylitResult = color * lightMultiplier;
float nightDarkenAmount = getNightDarkenAmount(todBrightness, skylight, terrainShadingBlocklight);
float weatherDarkenAmount = getWeatherDarkenAmount(todBrightness, skylight, terrainShadingBlocklight);
float paleGardenDarkenAmount = getPaleGardenDarkenAmount(todBrightness, skylight, terrainShadingBlocklight);
skylitResult *= mix(vec3(1.0), caveTintApplied, caveTintAmount);
skylitResult *= 1.0 - nightDarkenAmount * 0.45;

skylitResult *= 1.0 - weatherDarkenAmount * 0.45 * lightAmount;

skylitResult *= 1.0 - paleGardenDarkenAmount * 0.40 * lightAmount;
skylitResult *= 1.0 - caveDarkenAmount * 0.45;

float sLum = dot(shadow, vec3(0.299, 0.587, 0.114));
if (sLum > 0.001) {
vec3 shadowNorm = shadow / sLum;
float sat = max(shadowNorm.r, max(shadowNorm.g, shadowNorm.b)) - min(shadowNorm.r, min(shadowNorm.g, shadowNorm.b));
if (sat > 0.1) {

skylitResult *= mix(vec3(1.0), shadowNorm, smoothstep(0.1, 0.4, sat) * 0.4);
}
}

vec3 blockContribution = vec3(0.0);
vec3 blockAssistTint = tintBase;
#ifdef END_SHADER

vec3 endBlockColor = vec3(END_BLOCKLIGHT_R, END_BLOCKLIGHT_G, END_BLOCKLIGHT_B);
vec3 endBlockLight = endBlockColor * blocklightFalloff * blocklightFalloff * END_BLOCKLIGHT_BRIGHTNESS;
blockAssistTint = normalizeLightColor(endBlockColor);
blockContribution = color * endBlockLight;
vec3 result = skylitResult + blockContribution;
#else
#ifdef LPV_ENABLED

vec3 lpvAlbedo = getLpvCatchAlbedo(lpvSurfaceColor, lpvTexLuma);
vec3 rawLpvLight = blockLight * blocklightSkySuppress;
vec3 lpvContribution = lpvAlbedo * rawLpvLight;
blockAssistTint = normalizeLightColor(max(blockLight, vec3(0.001)));
blockContribution = lpvContribution;
vec3 result = blendLpvShortestHuePath(skylitResult, lpvSurfaceColor, blockContribution);

#else
blockAssistTint = normalizeLightColor(max(blockLight, vec3(0.001)));
blockContribution = color * blockLight * blocklightSkySuppress;
vec3 result = skylitResult + blockContribution;
#endif
#endif

float seaLevel = float(SEA_LEVEL_OFFSET);
float depthBelow = max(seaLevel - worldY, 0.0);
float heightAmbient = 1.0 - smoothstep(0.0, 96.0, depthBelow);

float undergroundBright = mix(0.30, 0.18, heightAmbient);
float interiorBright = 0.35;
float enclosedFactor = 1.0 - lmSkylight;
float undergroundBlend = smoothstep(24.0, 96.0, depthBelow);
float baseInteriorToCave = mix(interiorBright, undergroundBright, undergroundBlend);
float lowSkylightFloorFade = getHasSkylightMask(skylight);
float ambientFloorFactor = mix(1.0, enclosedFactor + darkness * 0.5 * lmSkylight, lowSkylightFloorFade);
float minBright = mix(CAVE_AMBIENT_FLOOR, baseInteriorToCave, 1.0 - caveDarkenAmount)
* ambientFloorFactor;
minBright *= 1.0 - nightDarkenAmount * 0.35;

minBright *= 1.0 - caveDarkenAmount * 0.35;
float zeroSkylightAmbientMask = getZeroSkylightMask(skylight) * getZeroBlocklightMask(terrainShadingBlocklight);
minBright = max(minBright, 0.08 * zeroSkylightAmbientMask);
vec3 ambientFloorColor = color * minBright * tintBase;
float albedoLuma = dot(color, vec3(0.299, 0.587, 0.114));
float darkAlbedoAssist = zeroSkylightAmbientMask * (1.0 - smoothstep(0.04, 0.25, albedoLuma));

ambientFloorColor = max(ambientFloorColor, color * tintBase * minBright * (1.0 + 0.5 * darkAlbedoAssist));
result = max(result, ambientFloorColor);
float darkSurfaceMask = 1.0 - smoothstep(0.04, 0.22, albedoLuma);
float lowSkylightAssist = 1.0 - smoothstep(0.08, 0.45, lmSkylight);
vec3 lowSkylightAssistColor = color * tintBase * (minBright * 0.35) * darkSurfaceMask * lowSkylightAssist;
vec3 blockAssistColor = vec3(0.0);
#if !defined(LPV_ENABLED) || defined(END_SHADER)
float blocklightAssist = smoothstep(0.04, 0.30, blocklightFalloff) * blocklightSkySuppress;
vec3 blockAssistBlendTint = normalizeLightColor(mix(tintBase, tintBase * blockAssistTint, 0.55));
blockAssistColor = color * blockAssistBlendTint * (0.08 * blocklightFalloff) * darkSurfaceMask * blocklightAssist;
#endif
vec3 darkSurfaceAssistColor = lowSkylightAssistColor + blockAssistColor;
result = max(result, darkSurfaceAssistColor);

#ifdef SHADOW_DEBUG_TINT
float debugShadowMask = clamp(1.0 - shadowValLifted, 0.0, 1.0);
result = mix(result, vec3(1.0, 0.1, 0.1), debugShadowMask * 0.85);
#endif

#ifdef CAVE_LIGHT_DEBUG
float lowSkyDebug = 1.0 - lmSkylight;
float caveFloorDebug = clamp(minBright / max(dot(color, vec3(0.3333)), 0.001), 0.0, 1.0);
vec3 debugColor = vec3(caveFloorDebug, 0.0, lowSkyDebug);
result = mix(result, debugColor, 0.9);
#endif

#if defined(LPV_ENABLED) && defined(LPV_DEBUG)

{
vec3 debugScenePos = lpvWorldPos - cameraPosition;
vec3 debugVoxelPos = sceneToVoxelSpace(debugScenePos, cameraPosition);
if (isInVoxelVolume(debugVoxelPos)) {
uint voxelId = debugReadLpvVoxel(lpvWorldPos);
vec3 dbgLpv = sampleLpvLight(lpvWorldPos, lpvWorldNormal);
float dbgSig = max(dbgLpv.r, max(dbgLpv.g, dbgLpv.b));

if (voxelId > 0u) {

result = vec3(
float(voxelId & 3u) / 3.0,
float((voxelId >> 2u) & 3u) / 3.0,
float((voxelId >> 4u) & 3u) / 3.0
);
} else if (dbgSig > 0.001) {

result = dbgLpv * 5.0;
} else {

result = vec3(0.8, 0.0, 0.8);
}
} else {
result = vec3(0.0);
}
}
#endif

return result;
}

vec3 applyLightingWithShadow(vec3 color, float sunAngle, float skylight, float blocklight, float emissive, float shadow, float worldY) {
return applyLightingWithShadow(color, sunAngle, skylight, blocklight, emissive, vec3(shadow), worldY);
}

vec3 applyLightingEmissive(vec3 color, float sunAngle, float skylight, float blocklight, float emissive, float worldY) {
if (emissive > 0.5) {
#ifdef END_SHADER
return color * EMISSIVE_BRIGHTNESS * END_EMISSIVE_BOOST;
#else
return color * EMISSIVE_BRIGHTNESS;
#endif
}
return applyLighting(color, sunAngle, skylight, blocklight, worldY);
}

vec3 applyLightingEmissiveWithWorldPos(vec3 color, float sunAngle, float skylight, float blocklight, float emissive, vec3 worldPos) {
return applyLightingEmissive(color, sunAngle, skylight, blocklight, emissive, worldPos.y);
}

vec3 applyTimeOfDayLighting(vec3 color, float sunAngle, float skylight, float worldY) {
return applyLighting(color, sunAngle, skylight, 0.0, worldY);
}

#endif
