#ifdef COLOR_GRADING_ENABLED

vec3 rgbToHsv(vec3 c) {
vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
float d = q.x - min(q.w, q.y);
float e = 1.0e-10;
return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsvToRgb(vec3 c) {
vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float cgLuma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 applyTemperature(vec3 color, float temp) {
float lum = cgLuma(color);
vec3 warmRef = vec3(1.0, 0.85, 0.65);
vec3 coolRef = vec3(0.65, 0.85, 1.0);
vec3 target = mix(coolRef, warmRef, temp * 0.5 + 0.5);
return clamp(mix(color, color * target, abs(temp) * 0.4 * smoothstep(0.0, 0.1, lum)), 0.0, 1.0);
}

vec3 applyTint(vec3 color, float tint) {
float lum = cgLuma(color);
vec3 magentaRef = vec3(1.0, 0.85, 1.0);
vec3 greenRef   = vec3(0.85, 1.0, 0.85);
vec3 target = mix(greenRef, magentaRef, tint * 0.5 + 0.5);
return clamp(mix(color, color * target, abs(tint) * 0.4 * smoothstep(0.0, 0.1, lum)), 0.0, 1.0);
}

vec3 applyExposure(vec3 color, float ev) {
vec3 lin = pow(color, vec3(2.2));
lin *= pow(2.0, ev);
return clamp(pow(clamp(lin, 0.0, 4.0), vec3(1.0/2.2)), 0.0, 1.0);
}

vec3 applyBrightness(vec3 color, float b) {
return clamp(color * (1.0 + b * 0.5), 0.0, 1.0);
}

vec3 applyContrast(vec3 color, float c) {
return clamp((color - 0.5) * (1.0 + c) + 0.5, 0.0, 1.0);
}

vec3 applyBlacks(vec3 color, float blacks) {
float lum = cgLuma(color);
float mask = 1.0 - smoothstep(0.0, 0.35, lum);
return max(color + blacks * 0.10 * mask, vec3(0.0));
}

vec3 applyWhites(vec3 color, float whites) {
float lum = cgLuma(color);
float mask = smoothstep(0.65, 1.0, lum);
return clamp(color + whites * 0.10 * mask, 0.0, 1.0);
}

vec3 applyShadowsHighlights(vec3 color, float shadows, float highlights) {
float lum = cgLuma(color);
float shadowMask = 1.0 - smoothstep(0.0, 0.5, lum);
float highlightMask = smoothstep(0.5, 1.0, lum);
return clamp(color + vec3(shadows * 0.20 * shadowMask + highlights * 0.20 * highlightMask), 0.0, 1.0);
}

vec3 applySplitToning(vec3 color, vec3 shadowTint, vec3 highlightTint, float intensity, float balance) {
float lum = dot(color, vec3(0.299, 0.587, 0.114));

float crossover = 0.5 + balance * 0.3;

float shadowWeight = 1.0 - smoothstep(0.0, crossover, lum);

float highlightWeight = smoothstep(crossover, 1.0, lum);

vec3 tint = mix(shadowTint * shadowWeight, highlightTint * highlightWeight, 0.5);

return mix(color, color + (tint - 0.5) * color, intensity);
}

vec3 applyLiftGammaGain(vec3 color, vec3 lift, vec3 gamma, vec3 gain) {
vec3 result = color;

result *= gain;

vec3 liftOffset = (lift - 1.0) * (1.0 - result);
result += liftOffset * 0.5;

result = pow(max(result, vec3(0.001)), 1.0 / gamma);

return clamp(result, 0.0, 1.0);
}

vec3 applyVignette(vec3 color, vec2 uv, float intensity, float radius, float softness, float roundness) {
vec2 center = uv - 0.5;
center.x *= roundness;

float dist = length(center) * 2.0;
float vignette = smoothstep(radius, radius - softness, dist);

return mix(color * (1.0 - intensity), color, vignette);
}

vec3 applyFilmGrain(vec3 color, vec2 uv, float intensity, float size, bool luminanceOnly, float time, int frameCount) {

vec2 noiseCoord = uv * size * 200.0;
float t = time * 10.0 + float(frameCount);

float noise = fract(sin(dot(noiseCoord + t, vec2(12.9898, 78.233))) * 43758.5453);
noise += fract(sin(dot(noiseCoord.yx - t * 0.7, vec2(93.9898, 67.345))) * 28462.1253);
noise = noise * 0.5 - 0.5;

if (luminanceOnly) {
color += vec3(noise * intensity);
} else {
vec3 colorNoise;
colorNoise.r = noise;
colorNoise.g = fract(sin(dot(noiseCoord + t * 1.1, vec2(45.233, 97.113))) * 32145.6789) - 0.5;
colorNoise.b = fract(sin(dot(noiseCoord - t * 0.9, vec2(78.345, 23.897))) * 54321.9876) - 0.5;
color += colorNoise * intensity;
}

return clamp(color, 0.0, 1.0);
}

vec3 applyHueShift(vec3 color, float degrees) {
vec3 hsv = rgbToHsv(color);
hsv.x = fract(hsv.x + degrees / 360.0);
return hsvToRgb(hsv);
}

vec3 applyVibrance(vec3 color, float vibrance) {
float maxC = max(max(color.r, color.g), color.b);
float minC = min(min(color.r, color.g), color.b);
float curSat = maxC > 0.001 ? (maxC - minC) / maxC : 0.0;
float vibranceWeight = pow(1.0 - curSat, 1.5);
float lum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 saturatedColor = mix(vec3(lum), color, max(1.0 + vibrance * vibranceWeight, 0.0));

return clamp(saturatedColor, 0.0, 1.0);
}

vec3 applyStylePreset(vec3 color, int preset, float intensity) {
if (preset == 0) return color;

vec3 styled = color;

if (preset == 1) {

float lum = dot(color, vec3(0.299, 0.587, 0.114));
vec3 shadowTint = vec3(0.08, 0.1, 0.18);
vec3 highlightTint = vec3(0.22, 0.18, 0.12);
styled = applySplitToning(color, shadowTint, highlightTint, 0.35, 0.1);
styled = applyVibrance(styled, -0.15);
styled = applyLiftGammaGain(styled, vec3(0.98, 0.98, 1.02), vec3(1.0), vec3(1.05, 1.02, 0.98));
}
else if (preset == 2) {

styled = applyTemperature(color, 0.4);
styled = applyVibrance(styled, -0.3);
styled = applyLiftGammaGain(styled, vec3(1.05, 1.02, 0.95), vec3(0.95), vec3(0.95, 0.93, 0.88));

float lum = dot(styled, vec3(0.299, 0.587, 0.114));
vec3 sepia = vec3(lum * 1.1, lum * 0.95, lum * 0.75);
styled = mix(styled, sepia, 0.2);
}
else if (preset == 3) {

vec3 shadowTint = vec3(0.0, 0.25, 0.35);
vec3 highlightTint = vec3(0.35, 0.2, 0.05);
styled = applySplitToning(color, shadowTint, highlightTint, 0.5, 0.0);
styled = applyVibrance(styled, 0.4);
styled = (styled - 0.5) * 1.15 + 0.5;
styled = applyLiftGammaGain(styled, vec3(0.95, 1.0, 1.08), vec3(1.0), vec3(1.08, 1.0, 0.92));
}
else if (preset == 4) {

styled = applyVibrance(color, -0.5);
styled = applyTint(styled, -0.3);
styled = applyLiftGammaGain(styled, vec3(0.9, 0.95, 0.9), vec3(1.1), vec3(0.9, 0.92, 0.88));

styled = max(styled - 0.05, vec3(0.0));
}
else if (preset == 5) {

vec3 shadowTint = vec3(0.18, 0.08, 0.28);
vec3 highlightTint = vec3(0.28, 0.22, 0.1);
styled = applySplitToning(color, shadowTint, highlightTint, 0.4, 0.15);
styled = applyVibrance(styled, 0.35);
styled = applyLiftGammaGain(styled, vec3(1.0, 0.95, 1.1), vec3(0.95), vec3(1.1, 1.05, 0.95));
}
else if (preset == 6) {

styled = applyTemperature(color, -0.35);
styled = applyVibrance(styled, -0.25);
vec3 shadowTint = vec3(0.1, 0.12, 0.22);
vec3 highlightTint = vec3(0.18, 0.18, 0.2);
styled = applySplitToning(styled, shadowTint, highlightTint, 0.3, -0.2);
styled = applyLiftGammaGain(styled, vec3(0.95, 0.97, 1.05), vec3(1.05), vec3(0.98, 1.0, 1.05));
}
else if (preset == 7) {

styled = applyTemperature(color, 0.2);
styled = applyVibrance(styled, 0.4);

styled.g = pow(styled.g, 0.9);
styled.b = pow(styled.b, 0.95);
styled = applyLiftGammaGain(styled, vec3(1.0, 1.03, 1.02), vec3(0.95), vec3(1.02, 1.05, 1.08));
}
else if (preset == 8) {

styled = applyVibrance(color, -0.7);
styled = applyTemperature(styled, -0.15);
styled = (styled - 0.5) * 1.25 + 0.5;
styled = applyLiftGammaGain(styled, vec3(0.9, 0.9, 0.95), vec3(1.1), vec3(1.1, 1.08, 1.05));
}

return mix(color, clamp(styled, 0.0, 1.0), intensity);
}

vec3 applyColorGrading(vec3 color, vec2 uv, float time, int frameCount) {
vec3 result = color;

#if CG_STYLE_PRESET > 0
result = applyStylePreset(result, CG_STYLE_PRESET, CG_STYLE_INTENSITY);
#endif

#if CG_TEMPERATURE != 0.0
result = applyTemperature(result, CG_TEMPERATURE);
#endif

#if CG_TINT != 0.0
result = applyTint(result, CG_TINT);
#endif

#if CG_EXPOSURE != 0.0
result = applyExposure(result, CG_EXPOSURE);
#endif

#if CG_BRIGHTNESS != 0.0
result = applyBrightness(result, CG_BRIGHTNESS);
#endif

#if CG_CONTRAST != 0.0
result = applyContrast(result, CG_CONTRAST);
#endif

#if CG_BLACKS != 0.0
result = applyBlacks(result, CG_BLACKS);
#endif

#if CG_WHITES != 0.0
result = applyWhites(result, CG_WHITES);
#endif

#if CG_SHADOWS != 0.0 || CG_HIGHLIGHTS != 0.0
result = applyShadowsHighlights(result, CG_SHADOWS, CG_HIGHLIGHTS);
#endif

#if CG_HUE_SHIFT != 0.0
result = applyHueShift(result, CG_HUE_SHIFT);
#endif

#if CG_SATURATION != 0.0
{
float lum = dot(result, vec3(0.299, 0.587, 0.114));
result = mix(vec3(lum), result, max(1.0 + CG_SATURATION, 0.0));
}
#endif

#if CG_VIBRANCE != 0.0
result = applyVibrance(result, CG_VIBRANCE);
#endif

#ifdef CG_SPLIT_TONING_ENABLED
{
vec3 shadowTint = vec3(CG_SHADOW_TINT_R, CG_SHADOW_TINT_G, CG_SHADOW_TINT_B);
vec3 highlightTint = vec3(CG_HIGHLIGHT_TINT_R, CG_HIGHLIGHT_TINT_G, CG_HIGHLIGHT_TINT_B);
result = applySplitToning(result, shadowTint, highlightTint, CG_SPLIT_TONING_INTENSITY, CG_SPLIT_TONING_BALANCE);
}
#endif

{
vec3 lift = vec3(CG_LIFT_R, CG_LIFT_G, CG_LIFT_B);
vec3 gamma = vec3(CG_GAMMA_R, CG_GAMMA_G, CG_GAMMA_B);
vec3 gain = vec3(CG_GAIN_R, CG_GAIN_G, CG_GAIN_B);

if (lift != vec3(1.0) || gamma != vec3(1.0) || gain != vec3(1.0)) {
result = applyLiftGammaGain(result, lift, gamma, gain);
}
}

#ifdef CG_VIGNETTE_ENABLED
result = applyVignette(result, uv, CG_VIGNETTE_INTENSITY, CG_VIGNETTE_RADIUS, CG_VIGNETTE_SOFTNESS, CG_VIGNETTE_ROUNDNESS);
#endif

#ifdef CG_FILM_GRAIN_ENABLED
#ifdef CG_FILM_GRAIN_LUMINANCE
result = applyFilmGrain(result, uv, CG_FILM_GRAIN_INTENSITY, CG_FILM_GRAIN_SIZE, true, time, frameCount);
#else
result = applyFilmGrain(result, uv, CG_FILM_GRAIN_INTENSITY, CG_FILM_GRAIN_SIZE, false, time, frameCount);
#endif
#endif

return result;
}
#endif
