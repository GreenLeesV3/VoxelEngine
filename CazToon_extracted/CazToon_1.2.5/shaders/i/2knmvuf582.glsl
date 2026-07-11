vec3 rgb2hsl(vec3 c) {
float maxC = max(max(c.r, c.g), c.b);
float minC = min(min(c.r, c.g), c.b);
float l = (maxC + minC) * 0.5;

if (maxC - minC < 1e-6) return vec3(0.0, 0.0, l);

float d = maxC - minC;
float s = (l > 0.5) ? d / (2.0 - maxC - minC) : d / (maxC + minC);

float h;
if (maxC == c.r) {
h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
} else if (maxC == c.g) {
h = (c.b - c.r) / d + 2.0;
} else {
h = (c.r - c.g) / d + 4.0;
}
h /= 6.0;

return vec3(h, s, l);
}

float emLinearStep(float edge0, float edge1, float x) {
return clamp((x - edge0) / (edge1 - edge0 + 1e-6), 0.0, 1.0);
}

float isolateHue(vec3 hsl, float centerDeg, float widthDeg) {
if (hsl.y < 0.01 || hsl.z < 0.01) return 0.0;
float hueDeg = hsl.x * 360.0;
float dist = abs(hueDeg - centerDeg);
dist = min(dist, 360.0 - dist);
return 1.0 - clamp(dist / widthDeg, 0.0, 1.0);
}

float emCube(float x) { return x * x * x; }

float getEmissiveMask(int et, vec3 rawColor) {
vec3 hsl = rgb2hsl(rawColor);
vec3 sqrtC = sqrt(max(rawColor, vec3(0.0)));
float sqrtAvg = (sqrtC.r + sqrtC.g + sqrtC.b) / 3.0;

if (et == 0) {
return 0.85 * sqrtAvg * hsl.z * emLinearStep(0.4, 0.6, 0.2 * hsl.y + 0.55 * hsl.z);
}

if (et == 16) {
return 0.85 * sqrtAvg * hsl.z * emLinearStep(0.4, 0.6, 0.2 * hsl.y + 0.55 * hsl.z);
}

if (et == -14 || et == 15) {

float soulCyan = isolateHue(hsl, 198.0, 36.0);
if (soulCyan > 0.3) {

float brightGate = emLinearStep(0.30, 0.45, hsl.z);
float satGate = emLinearStep(0.15, 0.35, hsl.y);
return 0.90 * sqrtAvg * max(brightGate * satGate, emLinearStep(0.55, 0.70, hsl.z));
}

return 0.85 * sqrtAvg * hsl.z * emLinearStep(0.4, 0.6, 0.2 * hsl.y + 0.55 * hsl.z);
}

if (et == 30) {
return 0.85 * sqrtAvg * emLinearStep(0.78, 0.85, hsl.z);
}

if (et == 1 || et == 23) {

float brightGate = emLinearStep(0.20, 0.35, hsl.z);
float satGate = emLinearStep(0.10, 0.25, hsl.y);
return 0.90 * sqrtAvg * max(brightGate * satGate, emLinearStep(0.45, 0.60, hsl.z));
}

if (et == 2) {
return 0.80 * sqrtAvg * (0.1 + 0.9 * emCube(hsl.z));
}

if (et == 19) {
return 2.0 * sqrtAvg * (0.2 + 0.8 * isolateHue(hsl, 30.0, 15.0)) * step(0.4, hsl.y) * hsl.z;
}

if (et == 20 || et == 5) {
return 0.60 * sqrtAvg * (0.1 + 0.9 * emCube(hsl.z));
}

if (et == 39) return 0.20;
if (et == 40) return 0.05;
if (et == 41) return 0.008;

if (et == 3) {
return 0.85 * sqrtAvg * hsl.z * emLinearStep(0.4, 0.6, 0.2 * hsl.y + 0.55 * hsl.z);
}

if (et == 4 || et == 12) {
return 1.0 * sqrtAvg * (0.1 + 0.9 * emCube(hsl.z));
}

if (et == 24) {
return sqrtAvg * step(0.2, hsl.z);
}

if (et == 6 || et == 18) {
float redness = rawColor.r / max(rawColor.g + rawColor.b, 0.001);
float l = 0.5 * (min(min(rawColor.r, rawColor.g), rawColor.b) + max(max(rawColor.r, rawColor.g), rawColor.b));
return 0.33 * sqrtAvg * step(0.45, redness * l);
}

if (et == 7 || et == 8 || et == 9 || et == 31 || et == 32 || et == 33) {
return 0.40 * sqrtAvg * (0.1 + 0.9 * emCube(hsl.z));
}

if (et == 10) {
return 1.0;
}

if (et == 11 || et == 13) {
return 0.66 * sqrtAvg * emLinearStep(0.75, 0.9, hsl.z);
}

if (et == 14) {
return 0.2 * sqrtAvg * (0.1 + 0.9 * hsl.z * hsl.z * hsl.z * hsl.z);
}

if (et == 17) {
float blue = isolateHue(hsl, 200.0, 30.0);
return 1.0 * sqrtAvg * emLinearStep(0.35, 0.42, 0.2 * hsl.y + 0.5 * hsl.z + 0.1 * blue);
}

if (et == 21) {
return 0.85 * sqrtAvg * emLinearStep(0.77, 0.85, hsl.z);
}

if (et == 22) {
return 0.80 * sqrtAvg * step(0.73, 0.8 * hsl.z);
}

if (et == 25) {
return 0.33 * sqrtAvg * isolateHue(hsl, 120.0, 50.0);
}

if (et == 26 || et == 36 || et == 37) {
return 0.2 * sqrtAvg * isolateHue(hsl, 200.0, 40.0) * smoothstep(0.5, 0.7, hsl.z);
}

if (et == 27) {
return 0.75 * isolateHue(hsl, 310.0, 50.0);
}

if (et == 28) {
return 0.5 * sqrtAvg * emLinearStep(0.5, 0.6, hsl.z);
}

if (et == 29) {
return 0.80 * sqrtAvg * step(0.73, 0.1 * hsl.y + 0.7 * hsl.z);
}

if (et == 34) {
return 0.3 * sqrtAvg * emLinearStep(0.5, 0.7, hsl.z);
}

if (et == 35) {
return 0.20 * sqrtAvg * (0.1 + 0.9 * hsl.z);
}

if (et == 44) {
return 0.05;
}

if (et == 38) {
return 0.33 * sqrtAvg;
}

if (et == 45) {
return 0.30;
}

if (et == 46 || et == 47) {
return 0.85;
}

if (et == 39) {
return 0.9 * sqrtAvg * step(0.5, hsl.y);
}

if (et == 68) {
return 1.0;
}

if (et == 43) {
return 1.0;
}

return sqrtAvg * (0.1 + 0.9 * emCube(hsl.z));
}
