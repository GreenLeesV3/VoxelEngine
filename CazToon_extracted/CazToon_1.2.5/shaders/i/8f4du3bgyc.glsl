float getLightningGlow(vec3 worldPos, float time, float thunderStrength) {
if (thunderStrength < 0.01) return 0.0;

float glow = 0.0;

for (int i = 0; i < 3; i++) {
float fi = float(i);

float angle = fi * 2.094 + time * 0.03 + fi * 2.5;
float dist = 50.0 + fi * 30.0;
vec3 cellCenter = vec3(
cos(angle) * dist,
10.0 + fi * 20.0,
sin(angle) * dist
);

float d = length(worldPos - cameraPosition - cellCenter);
float influence = smoothstep(50.0, 5.0, d);
if (influence < 0.01) continue;

float period = LIGHTNING_INTERVAL + fi * 3.1;
float phase = fi * 5.7 + 1.3;
float t = mod(time + phase, period);
float blink = smoothstep(0.0, 0.03, t) * smoothstep(0.30, 0.06, t);

float seed = fract(sin(fi * 91.7 + floor((time + phase) / period) * 37.3) * 43758.5453);
float intensity = 0.5 + 0.5 * seed;

glow = max(glow, blink * influence * intensity);
}

return glow * thunderStrength * LIGHTNING_BRIGHTNESS;
}
