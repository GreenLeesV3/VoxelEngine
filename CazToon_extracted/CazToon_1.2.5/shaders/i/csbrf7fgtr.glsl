#ifndef VOXY_COMPAT_GLSL
#define VOXY_COMPAT_GLSL

#include "/include/sky_timeline.glsl"

float voxy_luma(vec3 c) {
return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 voxy_normalize_light_color(vec3 c) {
float lum = voxy_luma(c);
vec3 n = c / max(lum, 0.35);
return clamp(n, vec3(0.0), vec3(2.0));
}

vec3 voxy_apply_color_adjust(vec3 color) {

float adjContrast = mix(VOXY_CONTRAST, 1.0, 0.5);
float adjSaturation = mix(VOXY_SATURATION, 1.0, 0.3);
color = (color - 0.5) * adjContrast + 0.5;
color = max(color, vec3(0.0));
float l = voxy_luma(color);
color = mix(vec3(l), color, adjSaturation);

if (VOXY_HIGHLIGHT_COMPRESS > 0.001) {
color = color / (color + vec3(VOXY_HIGHLIGHT_COMPRESS));
color *= (1.0 + VOXY_HIGHLIGHT_COMPRESS);
}

return color;
}

uint voxy_block_id(uint rawId) {
return (rawId >= 10000u) ? (rawId - 10000u) : rawId;
}

vec3 voxy_face_normal(uint face) {
vec3 axis = vec3(
float((face >> 1u) == 2u),
float((face >> 1u) == 0u),
float((face >> 1u) == 1u)
);
float sign = float((int(face) & 1) * 2 - 1);
return axis * sign;
}

vec4 voxy_time_of_day_lighting(float sunAngle) {
vec2 bd = getTimelineBrightness(sunAngle);
TimeWeightsSimple ts = getTimeWeightsSimple(sunAngle);
return vec4(bd.x, bd.y, ts.day, ts.twilight);
}

vec3 voxy_tod_skylight_tint(float sunAngle) {
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

return voxy_normalize_light_color(sky);
}

float voxy_blocklight_falloff(float blocklight) {
float x = clamp(blocklight, 0.0, 1.0);
float falloff = x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
falloff *= smoothstep(0.0, 0.15, x);
return falloff;
}

float voxy_face_shade(uint face) {
float shadeValues[6] = float[6](
0.5,
1.0,
0.8,
0.8,
0.6,
0.6
);
return shadeValues[min(face, 5u)];
}

vec3 voxy_hueToRGB(float hue) {
float h = mod(hue, 360.0) / 60.0;
float x = 1.0 - abs(mod(h, 2.0) - 1.0);
vec3 rgb;
if (h < 1.0) rgb = vec3(1.0, x, 0.0);
else if (h < 2.0) rgb = vec3(x, 1.0, 0.0);
else if (h < 3.0) rgb = vec3(0.0, 1.0, x);
else if (h < 4.0) rgb = vec3(0.0, x, 1.0);
else if (h < 5.0) rgb = vec3(x, 0.0, 1.0);
else rgb = vec3(1.0, 0.0, x);
return rgb;
}

vec3 voxy_applySaturation(vec3 c, float satMult) {
float lum = voxy_luma(c);
return mix(vec3(lum), c, max(satMult, 0.0));
}

vec3 voxy_static_night_tint() {
vec3 nightSky = vec3(NIGHT_ZENITH_R, NIGHT_ZENITH_G, NIGHT_ZENITH_B);
return voxy_normalize_light_color(nightSky);
}

vec3 voxy_static_night_tint_lit() {
vec3 nightTint = voxy_static_night_tint();
float lightSatBlend = clamp(SKYLIGHT_TINT_LIGHT_SATURATION, 0.0, 1.0);
float litSat = mix(1.0, SKYLIGHT_TINT_SATURATION, lightSatBlend);
return voxy_normalize_light_color(voxy_applySaturation(nightTint, litSat));
}

float voxy_quantized_light_level(float light) {
return floor(clamp(light, 0.0, 1.0) * 15.0 + 0.001);
}

float voxy_vanilla_skylight_brightness(float skylight) {
float light = clamp(skylight, 0.0, 1.0);
return light / (4.0 - 3.0 * light);
}

float voxy_has_skylight_mask(float skylight) {

return smoothstep(1.0 / 15.0, 2.0 / 15.0, clamp(skylight, 0.0, 1.0));
}

float voxy_zero_skylight_mask(float skylight) {
return 1.0 - voxy_has_skylight_mask(skylight);
}

float voxy_zero_blocklight_mask(float blocklight) {
return 1.0 - smoothstep(0.0, 4.0 / 15.0, clamp(blocklight, 0.0, 1.0));
}

float voxy_night_darken_amount(float todBrightness, float skylight, float blocklight) {
float nightFactor = 1.0 - smoothstep(0.0, 0.35, todBrightness);
float skylightGate = voxy_has_skylight_mask(skylight);
float blocklightGate = 1.0 - smoothstep(0.45, 0.95, blocklight);
return NIGHT_DARKNESS * nightFactor * skylightGate * blocklightGate;
}

float voxy_weather_darken_amount(float todBrightness, float skylight, float blocklight) {
float dayFactor = smoothstep(0.28, 0.88, todBrightness);
float skylightGate = voxy_has_skylight_mask(skylight);
float blocklightGate = 1.0 - smoothstep(0.30, 0.95, blocklight);
float weatherDarkness = float(SKY_RAIN_DARKNESS) / 100.0;
return rainStrength * dayFactor * skylightGate * blocklightGate * weatherDarkness;
}

float voxy_pale_garden_darken_amount(float todBrightness, float skylight, float blocklight) {
#ifdef VOXY_HAS_SSBO
float weight = clamp(smoothPaleGarden, 0.0, 1.0);
#else
float weight = 0.0;
#endif
if (weight < 0.001) return 0.0;
float dayFactor = smoothstep(0.28, 0.88, todBrightness);
float skylightGate = voxy_has_skylight_mask(skylight);
float blocklightGate = 1.0 - smoothstep(0.30, 0.95, blocklight);
return weight * dayFactor * skylightGate * blocklightGate;
}

float voxy_cave_look_amount(float skylight, float blocklight) {
float caveTintGate = 1.0 - smoothstep(0.00, 7.0 / 15.0, skylight);
float zeroBlocklightMask = voxy_zero_blocklight_mask(blocklight);
return caveTintGate * zeroBlocklightMask;
}

float voxy_cave_tint_amount(float skylight, float blocklight) {
if (isEyeInWater == 1) return 0.0;
float caveTintGate = 1.0 - smoothstep(0.00, 14.0 / 15.0, skylight);
float zeroBlocklightMask = voxy_zero_blocklight_mask(blocklight);
return caveTintGate * zeroBlocklightMask;
}

float voxy_cave_darken_amount(float skylight, float blocklight) {
if (isEyeInWater == 1) return 0.0;
float caveTintFade = voxy_cave_tint_amount(skylight, blocklight);
return CAVE_DARKNESS * caveTintFade * caveTintFade;
}

float voxy_shadow_transition_dip(float sunAngle) {
float angle = fract(sunAngle);
float sunsetTransitionDip = smoothstep(0.46, 0.5146, angle) * (1.0 - smoothstep(0.5146, 0.57, angle));
float sunriseTransitionDip = max(
smoothstep(0.93, 0.9854, angle),
1.0 - smoothstep(0.0146, 0.07, angle)
);
return max(sunsetTransitionDip, sunriseTransitionDip);
}

float voxy_shadow_transition_shadow_floor(float todBrightness, float skylight) {
float isNightTime = 1.0 - smoothstep(0.0, 0.25, todBrightness);
return 0.15 * clamp(skylight, 0.0, 1.0) * (1.0 - isNightTime * 0.75);
}

float voxy_shadow_transition_darken(float transitionDip, float todBrightness, float skylight) {
float shadowFloor = voxy_shadow_transition_shadow_floor(todBrightness, skylight);
float transitionTarget = mix(1.0, shadowFloor, SHADOW_OPACITY);
return mix(1.0, transitionTarget, transitionDip);
}

vec3 voxy_apply_chunk_like_lighting(vec3 color, float sunAngle, float skylight, float blocklight, float worldY) {
vec4 tod = voxy_time_of_day_lighting(sunAngle);
float todBrightness = tod.x;
float darkness = tod.y;
float dayAmount = tod.z;
float sunsetAmount = tod.w;

float voxyAngle = fract(sunAngle);

float zeroSkylightLift = (1.0 - step(0.5, voxy_quantized_light_level(skylight))) * (1.0 / 15.0);
float lmSkylight = voxy_vanilla_skylight_brightness(max(skylight, zeroSkylightLift));

float sunsetTintBoost = smoothstep(0.38, 0.45, voxyAngle) * (1.0 - smoothstep(0.48, 0.55, voxyAngle))
+ smoothstep(0.95, 1.0, voxyAngle) + (1.0 - smoothstep(0.0, 0.05, voxyAngle));

float dayTintReduce = smoothstep(0.07, 0.15, voxyAngle) * (1.0 - smoothstep(0.40, 0.46, voxyAngle));
float baseTint = SKYLIGHT_COLOR_TINT * (1.0 - dayTintReduce * 0.6);
float tintStrength = clamp((baseTint + sunsetTintBoost * SUNSET_TERRAIN_TINT) * VOXY_SKY_TINT_BOOST, 0.0, 1.0);
float lightSatBlend = clamp(SKYLIGHT_TINT_LIGHT_SATURATION, 0.0, 1.0);

vec3 todTint = voxy_tod_skylight_tint(sunAngle);
vec3 biomeTint = voxy_normalize_light_color(skyColor);
float biomeWeight = smoothstep(0.5, 0.9, dayAmount);
vec3 caveTint = voxy_static_night_tint();
vec3 caveTintApplied = voxy_static_night_tint_lit();
float terrainShadingBlocklight = blocklight;
#ifdef LPV_ENABLED
terrainShadingBlocklight = 0.0;
#endif
float caveTintAmount = voxy_cave_tint_amount(skylight, terrainShadingBlocklight);
vec3 tintBase = voxy_normalize_light_color(todTint * mix(vec3(1.0), biomeTint, biomeWeight));
tintBase = voxy_normalize_light_color(mix(tintBase, caveTint, caveTintAmount));
float caveTintBaseLuma = voxy_luma(tintBase);
tintBase = mix(tintBase, mix(vec3(caveTintBaseLuma), tintBase, 0.32), caveTintAmount);

float sunsetSatBoost = 1.0 + sunsetTintBoost * (SUNSET_TERRAIN_TINT * 1.09);
vec3 tintShadow = voxy_normalize_light_color(voxy_applySaturation(tintBase, SKYLIGHT_TINT_SATURATION * sunsetSatBoost));
float litSat = mix(1.0, SKYLIGHT_TINT_SATURATION * sunsetSatBoost, lightSatBlend);
vec3 tintLit = voxy_normalize_light_color(voxy_applySaturation(tintBase, litSat));
float visibleTintStrength = clamp(tintStrength * 0.68, 0.0, 1.0);
vec3 visibleTintShadow = voxy_normalize_light_color(mix(vec3(1.0), tintShadow, visibleTintStrength));
vec3 visibleTintLit = voxy_normalize_light_color(mix(vec3(1.0), tintLit, visibleTintStrength));

float skyTintGate = smoothstep(1.0 / 15.0, 1.0, skylight);
#ifdef END_SHADER
vec3 skyTintShadow = vec3(1.0);
#else
vec3 skyTintShadow = mix(vec3(1.0), tintShadow, tintStrength * lmSkylight * skyTintGate);
#endif

vec3 rawShadowHue = voxy_hueToRGB(SHADOW_HUE > 0.0 ? 180.0 + SHADOW_HUE : 360.0 + SHADOW_HUE);
float hueLuminance = voxy_luma(rawShadowHue);
vec3 normalizedHue = rawShadowHue / max(hueLuminance, 0.3);
normalizedHue = min(normalizedHue, vec3(2.0));

float nightSatReduce = smoothstep(0.0, 0.20, todBrightness);
float caveSatReduce = smoothstep(0.10, 0.55, lmSkylight);
float effectiveLmSat = mix(LIGHTMAP_SATURATION * 0.10, LIGHTMAP_SATURATION, nightSatReduce * caveSatReduce);
vec3 shadowTintColor = normalizedHue;

float isNightTime = 1.0 - smoothstep(0.0, 0.25, todBrightness);
float lightAmount = clamp(lmSkylight * todBrightness, 0.0, 1.0);

float shadowDark = 0.15 * lmSkylight * (1.0 - isNightTime * 0.75);
lightAmount += lmSkylight * isNightTime * 0.30;

vec3 darkShadowColor = visibleTintShadow * shadowDark;

vec3 litColor = visibleTintLit;
vec3 lightMultiplier = mix(darkShadowColor, litColor, lightAmount);

float isDaySuppress = smoothstep(0.25, 0.85, todBrightness);
float effectiveBlock = clamp(blocklight * (1.0 - BLOCKLIGHT_SKYLIGHT_REDUCTION * lmSkylight * isDaySuppress), 0.0, 1.0);
float bFalloff = voxy_blocklight_falloff(effectiveBlock);
vec3 blockLight = vec3(1.0, 0.9, 0.8) * bFalloff * bFalloff * BLOCKLIGHT_BRIGHTNESS;
float blocklightSkySuppress = 1.0 - smoothstep(0.6, 1.0, lmSkylight * isDaySuppress);

float seaLevel = float(SEA_LEVEL_OFFSET);
float depthBelow = max(seaLevel - worldY, 0.0);
float heightAmbient = 1.0 - smoothstep(0.0, 96.0, depthBelow);
float undergroundBright = mix(0.30, 0.18, heightAmbient);
float interiorBright = 0.35;
float enclosedFactor = 1.0 - lmSkylight;
float undergroundBlend = smoothstep(24.0, 96.0, depthBelow);
float baseInteriorToCave = mix(interiorBright, undergroundBright, undergroundBlend);
float caveDarkenAmount = voxy_cave_darken_amount(skylight, terrainShadingBlocklight);
float lowSkylightFloorFade = voxy_has_skylight_mask(skylight);
float ambientFloorFactor = mix(1.0, enclosedFactor + darkness * 0.5 * lmSkylight, lowSkylightFloorFade);
float minBright = mix(CAVE_AMBIENT_FLOOR, baseInteriorToCave, 1.0 - caveDarkenAmount)
* ambientFloorFactor;
float nightDarkenAmount = voxy_night_darken_amount(todBrightness, skylight, terrainShadingBlocklight);
float weatherDarkenAmount = voxy_weather_darken_amount(todBrightness, skylight, terrainShadingBlocklight);
float paleGardenDarkenAmount = voxy_pale_garden_darken_amount(todBrightness, skylight, terrainShadingBlocklight);
vec3 skylitResult = color * lightMultiplier * mix(vec3(1.0), caveTintApplied, caveTintAmount)
* (1.0 - nightDarkenAmount * 0.45) * (1.0 - caveDarkenAmount * 0.45);

skylitResult *= 1.0 - weatherDarkenAmount * 0.45 * lightAmount;
skylitResult *= 1.0 - paleGardenDarkenAmount * 0.40 * lightAmount;
vec3 blockContribution = color * blockLight * blocklightSkySuppress;
vec3 result = skylitResult + blockContribution;
minBright *= 1.0 - nightDarkenAmount * 0.35;
minBright *= 1.0 - caveDarkenAmount * 0.35;
float zeroSkylightAmbientMask = voxy_zero_skylight_mask(skylight) * voxy_zero_blocklight_mask(terrainShadingBlocklight);
minBright = max(minBright, 0.08 * zeroSkylightAmbientMask);
vec3 ambientFloorColor = color * minBright * tintBase;
float albedoLuma = dot(color, vec3(0.299, 0.587, 0.114));
float darkAlbedoAssist = zeroSkylightAmbientMask * (1.0 - smoothstep(0.04, 0.25, albedoLuma));

ambientFloorColor = max(ambientFloorColor, color * tintBase * minBright * (1.0 + 0.5 * darkAlbedoAssist));
result = max(result, ambientFloorColor);
float darkSurfaceMask = 1.0 - smoothstep(0.04, 0.22, albedoLuma);
float lowSkylightAssist = 1.0 - smoothstep(0.08, 0.45, lmSkylight);
float blocklightAssist = smoothstep(0.04, 0.30, bFalloff) * blocklightSkySuppress;
vec3 blockAssistTint = voxy_normalize_light_color(max(blockLight, vec3(0.001)));
vec3 lowSkylightAssistColor = color * tintBase * (minBright * 0.35) * darkSurfaceMask * lowSkylightAssist;
vec3 blockAssistBlendTint = voxy_normalize_light_color(mix(tintBase, tintBase * blockAssistTint, 0.55));
vec3 blockAssistColor = color * blockAssistBlendTint * (0.08 * bFalloff) * darkSurfaceMask * blocklightAssist;
vec3 darkSurfaceAssistColor = lowSkylightAssistColor + blockAssistColor;
result = max(result, darkSurfaceAssistColor);

#ifdef END_SHADER
result *= mix(1.0, TERRAIN_BRIGHTNESS * VOXY_LOD_BRIGHTNESS, 0.3);
#else
result *= TERRAIN_BRIGHTNESS * VOXY_LOD_BRIGHTNESS;
#endif

return result;
}

#ifdef VOXY_TILE_BLUR_ENABLED

vec4 voxy_tile_blur(vec2 uv, float depth) {
const vec2 tileSize = vec2(1.0 / (3.0 * 256.0), 1.0 / (2.0 * 256.0));
vec2 tileMin = floor(uv / tileSize) * tileSize;
vec2 centerUV = tileMin + tileSize * 0.5;
return textureLod(blockModelAtlas, centerUV, 0);
}

float voxy_tile_blur_strength(float depth) {
return smoothstep(VOXY_TILE_BLUR_START, min(VOXY_TILE_BLUR_START + 0.1, 0.999), depth);
}
#endif

#endif
