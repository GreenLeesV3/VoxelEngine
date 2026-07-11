#ifndef SKY_TIMELINE_GLSL
#define SKY_TIMELINE_GLSL

struct TimeWeights {
float day;
float sunset;
float blueHour;
float night;
float sunrise;
float dawn;
};

TimeWeights getTimeWeights(float sunAngle) {
float angle = fract(sunAngle);
TimeWeights w;

w.day = smoothstep(0.02, 0.07, angle) * (1.0 - smoothstep(0.44, 0.48, angle));

w.sunset = smoothstep(0.46, 0.49, angle) * (1.0 - smoothstep(0.50, 0.52, angle));

w.sunrise = smoothstep(0.96, 0.99, angle) + (1.0 - smoothstep(0.0, 0.03, angle));

w.blueHour = smoothstep(0.50, 0.52, angle) * (1.0 - smoothstep(0.55, 0.58, angle));

w.dawn = 0.0;

w.night = smoothstep(0.55, 0.60, angle) * (1.0 - smoothstep(0.94, 0.98, angle));

float total = w.day + w.sunset + w.blueHour + w.night + w.sunrise + w.dawn;
if (total > 0.001) {
float inv = 1.0 / total;
w.day *= inv;
w.sunset *= inv;
w.blueHour *= inv;
w.night *= inv;
w.sunrise *= inv;
w.dawn *= inv;
} else {
w.day = 1.0;
}

return w;
}

struct TimeWeightsSimple {
float day;
float twilight;
float blueHour;
float night;
};

TimeWeightsSimple getTimeWeightsSimple(float sunAngle) {
TimeWeights w = getTimeWeights(sunAngle);
TimeWeightsSimple s;
s.day = w.day;
s.twilight = w.sunset + w.sunrise;
s.blueHour = w.blueHour + w.dawn;
s.night = w.night;
return s;
}

#define SUNRISE_HORIZON_R 1.00
#define SUNRISE_HORIZON_G 0.70
#define SUNRISE_HORIZON_B 0.45

#define SUNRISE_MID_R 0.90
#define SUNRISE_MID_G 0.55
#define SUNRISE_MID_B 0.55

#define SUNRISE_ZENITH_R 0.65
#define SUNRISE_ZENITH_G 0.45
#define SUNRISE_ZENITH_B 0.65

#define SUNRISE_BRIGHTNESS 0.85

#define DAWN_HORIZON_R 0.15
#define DAWN_HORIZON_G 0.50
#define DAWN_HORIZON_B 0.85

#define DAWN_MID_R 0.30
#define DAWN_MID_G 0.30
#define DAWN_MID_B 0.60

#define DAWN_ZENITH_R 0.12
#define DAWN_ZENITH_G 0.18
#define DAWN_ZENITH_B 0.45

#define DAWN_BRIGHTNESS 0.55

vec3 getTimelineHorizonColor(float sunAngle, float horizonBias) {
TimeWeights w = getTimeWeights(sunAngle);

vec3 dayH = vec3(DAY_HORIZON_R, DAY_HORIZON_G, DAY_HORIZON_B);
vec3 dayZ = vec3(DAY_ZENITH_R, DAY_ZENITH_G, DAY_ZENITH_B);
vec3 dayC = mix(dayH, dayZ, horizonBias) * DAY_BRIGHTNESS;

vec3 sunsetH = vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B);
vec3 sunsetZ = vec3(SUNSET_ZENITH_R, SUNSET_ZENITH_G, SUNSET_ZENITH_B);
vec3 sunsetC = mix(sunsetH, sunsetZ, horizonBias) * SUNSET_BRIGHTNESS;

vec3 blueH = vec3(BLUEHOUR_HORIZON_R, BLUEHOUR_HORIZON_G, BLUEHOUR_HORIZON_B);
vec3 blueZ = vec3(BLUEHOUR_ZENITH_R, BLUEHOUR_ZENITH_G, BLUEHOUR_ZENITH_B);
vec3 blueC = mix(blueH, blueZ, horizonBias) * BLUEHOUR_BRIGHTNESS;

vec3 nightH = vec3(NIGHT_HORIZON_R, NIGHT_HORIZON_G, NIGHT_HORIZON_B);
vec3 nightZ = vec3(NIGHT_ZENITH_R, NIGHT_ZENITH_G, NIGHT_ZENITH_B);
vec3 nightC = mix(nightH, nightZ, horizonBias) * NIGHT_BRIGHTNESS;

vec3 sunriseH = vec3(SUNRISE_HORIZON_R, SUNRISE_HORIZON_G, SUNRISE_HORIZON_B);
vec3 sunriseZ = vec3(SUNRISE_ZENITH_R, SUNRISE_ZENITH_G, SUNRISE_ZENITH_B);
vec3 sunriseC = mix(sunriseH, sunriseZ, horizonBias) * SUNRISE_BRIGHTNESS;

vec3 dawnH = vec3(DAWN_HORIZON_R, DAWN_HORIZON_G, DAWN_HORIZON_B);
vec3 dawnZ = vec3(DAWN_ZENITH_R, DAWN_ZENITH_G, DAWN_ZENITH_B);
vec3 dawnC = mix(dawnH, dawnZ, horizonBias) * DAWN_BRIGHTNESS;

vec3 color = dayC    * w.day
+ sunsetC * w.sunset
+ blueC   * w.blueHour
+ nightC  * w.night
+ sunriseC * w.sunrise
+ dawnC   * w.dawn;

float daySunsetMixH = min(w.day, w.sunset + w.sunrise) * 2.5;
float daySunsetMixZ = min(w.day, w.sunset + w.sunrise) * 2.0;
float daySunsetMix = mix(daySunsetMixH, daySunsetMixZ, horizonBias);
vec3 daySunsetCP = mix(vec3(1.0, 0.92, 0.4), vec3(0.85, 0.15, 0.55), horizonBias);
daySunsetCP *= max(DAY_BRIGHTNESS, SUNSET_BRIGHTNESS);
color = mix(color, daySunsetCP, daySunsetMix * mix(0.45, 0.55, horizonBias));
float sunsetBlueMix = min(w.sunset, w.blueHour) * 2.0;
vec3 sunsetBlueCP = mix(vec3(0.9, 0.25, 0.55), vec3(0.4, 0.1, 1.0), horizonBias);
sunsetBlueCP *= mix(SUNSET_BRIGHTNESS, BLUEHOUR_BRIGHTNESS, 0.5);
color = mix(color, sunsetBlueCP, sunsetBlueMix * mix(0.4, 0.55, horizonBias));

return color;
}

vec3 getTimelineHorizonColor(float sunAngle) {
return getTimelineHorizonColor(sunAngle, 0.0);
}

vec2 getTimelineBrightness(float sunAngle) {
TimeWeights w = getTimeWeights(sunAngle);

float brightness = w.day * 1.0
+ w.sunset * 0.85
+ w.sunrise * 0.80
+ w.blueHour * 0.45
+ w.dawn * 0.45
+ w.night * 0.04;

float darkness = w.night
+ (w.sunset + w.sunrise) * 0.4
+ (w.blueHour + w.dawn) * 0.6;

return vec2(brightness, darkness);
}

#endif
