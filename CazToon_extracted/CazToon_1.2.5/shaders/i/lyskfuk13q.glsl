#ifndef WATER_COLOR_GLSL
#define WATER_COLOR_GLSL

#include "/include/sky_timeline.glsl"

const float MC_WATER_BRIGHTNESS  = 0.4;
const float MC_WATER_EXPOSURE    = 1.0;
const float MC_WATER_CONTRAST    = 1.0;
const float MC_WATER_SATURATION  = 0.6;
const float MC_WATER_VIBRANCE    = 0.0;
const float MC_WATER_GAMMA       = 1.5;
const float MC_WATER_BLACK_POINT = 0.0;
const float MC_WATER_WHITE_POINT = 1.0;
const vec3  MC_WATER_TINT        = vec3(1.0, 1.0, 1.0);

const float DH_WATER_BRIGHTNESS  = MC_WATER_BRIGHTNESS;
const float DH_WATER_EXPOSURE    = MC_WATER_EXPOSURE;
const float DH_WATER_CONTRAST    = MC_WATER_CONTRAST;
const float DH_WATER_SATURATION  = MC_WATER_SATURATION;
const float DH_WATER_VIBRANCE    = MC_WATER_VIBRANCE;
const float DH_WATER_GAMMA       = MC_WATER_GAMMA;
const float DH_WATER_BLACK_POINT = MC_WATER_BLACK_POINT;
const float DH_WATER_WHITE_POINT = MC_WATER_WHITE_POINT;
const vec3  DH_WATER_TINT        = MC_WATER_TINT;

vec4 waterTimeOfDay(float sunAngle) {
TimeWeightsSimple ts = getTimeWeightsSimple(sunAngle);

float day = ts.day;
float twilight = ts.twilight;
float night = ts.night + ts.blueHour;

float brightness = 1.0 * day + 0.85 * twilight + 0.15 * night;
return vec4(day, twilight, night, brightness);
}

vec3 waterAmbientTint(float day, float sunset, float night) {
vec3 daySky = mix(vec3(DAY_MID_R, DAY_MID_G, DAY_MID_B),
vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B), 0.35);
vec3 sunsetSky = mix(vec3(SUNSET_MID_R, SUNSET_MID_G, SUNSET_MID_B),
vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), 0.75);
vec3 nightSky = mix(vec3(NIGHT_MID_R, NIGHT_MID_G, NIGHT_MID_B),
vec3(NIGHT_HORIZON_R, NIGHT_HORIZON_G, NIGHT_HORIZON_B), 0.55);

float dL = dot(daySky, vec3(0.299, 0.587, 0.114));
daySky = clamp(daySky / max(dL, 0.35), vec3(0.0), vec3(2.0));
float sL = dot(sunsetSky, vec3(0.299, 0.587, 0.114));
sunsetSky = clamp(sunsetSky / max(sL, 0.35), vec3(0.0), vec3(2.0));
float nL = dot(nightSky, vec3(0.299, 0.587, 0.114));
nightSky = clamp(nightSky / max(nL, 0.35), vec3(0.0), vec3(2.0));
vec3 tint = daySky * day + sunsetSky * sunset + nightSky * night;
return mix(vec3(1.0), tint, SKYLIGHT_COLOR_TINT);
}

vec3 biomeWaterColor(float sunAngle, float wBeach, float wSwamp, float wJungle, float wSnowy, float wArid) {

vec3 horizonColor = getTimelineHorizonColor(sunAngle, 0.4);

vec4 todWC = waterTimeOfDay(sunAngle);
float waterDarken = mix(0.3, 0.5, todWC.y);
vec3 baseColor = horizonColor * waterDarken;

vec4 tod = waterTimeOfDay(sunAngle);
float day = tod.x;
float night = tod.z;

vec3 result = baseColor;
if (wSwamp > 0.001)  result = mix(result, vec3(0.18, 0.28, 0.08) * day + vec3(0.06, 0.10, 0.04) * night, wSwamp);
if (wJungle > 0.001) result = mix(result, vec3(0.08, 0.32, 0.30) * day + vec3(0.04, 0.12, 0.14) * night, wJungle);

return result;
}

vec3 waterLitColor(vec3 baseColor, float sunAngle) {

float baseLum = dot(baseColor, vec3(0.299, 0.587, 0.114));
if (baseLum > 0.01) {
baseColor = baseColor / baseLum * 0.35;
}
baseColor = clamp(baseColor, vec3(0.0), vec3(1.0));

vec4 tod = waterTimeOfDay(sunAngle);
vec3 tint = waterAmbientTint(tod.x, tod.y, tod.z);
return baseColor * tod.w * tint;
}

float waterLowSkylightBrightness(float todBrightness, float skylight, float blocklight) {
float lowSky = 1.0 - smoothstep(2.0 / 15.0, 8.0 / 15.0, clamp(skylight, 0.0, 1.0));
float localLight = smoothstep(1.0 / 15.0, 12.0 / 15.0, clamp(blocklight, 0.0, 1.0));
float indoorFloor = mix(0.55, 0.95, localLight);
return mix(todBrightness, max(todBrightness, indoorFloor), lowSky);
}

vec3 waterLitColor(vec3 baseColor, float sunAngle, float skylight, float blocklight) {

float baseLum = dot(baseColor, vec3(0.299, 0.587, 0.114));
if (baseLum > 0.01) baseColor = baseColor / baseLum * 0.35;
baseColor = clamp(baseColor, vec3(0.0), vec3(1.0));

vec4 tod = waterTimeOfDay(sunAngle);

float skyTintGate = smoothstep(1.0 / 15.0, 2.0 / 15.0, skylight);
vec3 tint = mix(vec3(1.0), waterAmbientTint(tod.x, tod.y, tod.z), skyTintGate);
float brightness = waterLowSkylightBrightness(tod.w, skylight, blocklight);
return baseColor * brightness * tint;
}

vec3 waterLitColor(vec3 baseColor, float sunAngle, float skylight) {
return waterLitColor(baseColor, sunAngle, skylight, 0.0);
}

vec3 waterSpecular(vec3 viewDir, vec3 sunDir, vec3 normal, float sunAngle) {
vec3 halfDir = normalize(viewDir + sunDir);
float NdotH = max(dot(normal, halfDir), 0.0);

float specTight = pow(NdotH, 256.0);

float specWide = pow(NdotH, 48.0);
float spec = specTight * 6.0 + specWide * 1.2;
vec4 tod = waterTimeOfDay(sunAngle);

vec3 specColor = vec3(1.0, 1.0, 1.0) * tod.x
+ vec3(1.0, 0.7, 0.4) * tod.y
+ vec3(0.7, 0.8, 1.0) * tod.z * 0.5;

#ifdef VOXY_PROGRAM
float rainSpecFade = 1.0;
#else
float rainSpecFade = 1.0 - rainStrength * 0.85;
#endif
return specColor * spec * WATER_SPECULAR_INTENSITY * rainSpecFade;
}

#endif
