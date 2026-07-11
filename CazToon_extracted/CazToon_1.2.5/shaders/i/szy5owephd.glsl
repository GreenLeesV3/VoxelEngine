#ifndef OCEAN_WAVES_GLSL
#define OCEAN_WAVES_GLSL

vec2 oceanWaveDx(vec2 position, vec2 direction, float frequency, float timeshift) {
float x = dot(direction, position) * frequency + timeshift;
float wave = exp(sin(x) - 1.0);
float dx = wave * cos(x);
return vec2(wave, -dx);
}

float oceanWaveHeightRaw(vec2 position, float time, int iterations) {

float windA = 188.0 * 3.14159265 / 180.0;
float wc = cos(windA), ws = sin(windA);
position = vec2(wc * position.x - ws * position.y, ws * position.x + wc * position.y);
position.x *= 1.15;
vec2 windDir = vec2(cos(windA), sin(windA));
float wavePhaseShift = length(position) * 0.1;
float iter = 0.0;
float freq = 1.0;
float timeMul = 2.0;
float weight = 1.0;
float sumVal = 0.0;
float sumWeight = 0.0;
for (int i = 0; i < iterations; i++) {
vec2 dir = vec2(sin(iter), cos(iter));
dir = normalize(mix(dir, windDir * sign(dot(dir, windDir)), 0.55));
vec2 res = oceanWaveDx(position, dir, freq, time * timeMul + wavePhaseShift);
position += dir * res.y * weight * OCEAN_WAVE_DRAG;
sumVal += res.x * weight;
sumWeight += weight;
weight = mix(weight, 0.0, 0.2);
freq *= 1.45;
timeMul *= 1.08;
iter += 2692.0;
}
return sumVal / sumWeight;
}

float oceanWaveHeight(vec2 position, float time, int iterations) {
float raw = oceanWaveHeightRaw(position, time, iterations);

float centered = (raw - 0.53) * 2.0;
float expanded = tanh(centered) * 0.5 + 0.5;
float h = clamp(expanded, 0.0, 1.0);
h = pow(h, 0.7);
return h;
}

float oceanWaveHeightSum(vec2 position, float time, int iterations) {

float windA = 188.0 * 3.14159265 / 180.0;
float wc = cos(windA), ws = sin(windA);
position = vec2(wc * position.x - ws * position.y, ws * position.x + wc * position.y);
position.x *= 1.15;
vec2 windDir = vec2(cos(windA), sin(windA));
float wavePhaseShift = length(position) * 0.1;
float iter = 0.0;
float freq = 1.0;
float timeMul = 2.0;
float weight = 1.0;
float sumVal = 0.0;
for (int i = 0; i < iterations; i++) {
vec2 dir = vec2(sin(iter), cos(iter));
dir = normalize(mix(dir, windDir * sign(dot(dir, windDir)), 0.55));
vec2 res = oceanWaveDx(position, dir, freq, time * timeMul + wavePhaseShift);
position += dir * res.y * weight * OCEAN_WAVE_DRAG;
sumVal += res.x * weight;
weight = mix(weight, 0.0, 0.2);
freq *= 1.45;
timeMul *= 1.08;
iter += 2692.0;
}
return sumVal;
}

vec3 oceanWaveNormal(vec2 position, float time, int iterations) {
float e = 0.01;
float depth = 0.005;
float H  = oceanWaveHeightSum(position, time, iterations) * depth;
float Hx = oceanWaveHeightSum(position - vec2(e, 0.0), time, iterations) * depth;
float Hz = oceanWaveHeightSum(position + vec2(0.0, e), time, iterations) * depth;

float dhdx = (H - Hx) / e;
float dhdz = (Hz - H) / e;

return normalize(vec3(-dhdx, 1.0, -dhdz));
}

#endif
