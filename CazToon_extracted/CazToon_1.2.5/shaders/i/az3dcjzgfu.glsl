vec3 rgb2hsv(vec3 c) {
vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
float d = q.x - min(q.w, q.y);
float e = 1.0e-10;
return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 hueShift(vec3 color, float hueShiftDegrees, float satMult) {
vec3 hsv = rgb2hsv(color);
hsv.x = fract(hsv.x + hueShiftDegrees / 360.0);
hsv.y *= satMult;
return hsv2rgb(hsv);
}

vec3 hueToRGB(float hue) {
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

vec3 applyColorTint(vec3 color, float hue, float tintStrength, float saturation) {
if (tintStrength < 0.001) return color;

float adjustedHue = hue > 0.0 ? 180.0 + hue : 360.0 + hue;
vec3 tintColor = hueToRGB(adjustedHue);

tintColor = mix(vec3(1.0), tintColor, clamp(saturation, 0.0, 5.0));

vec3 tinted = color * tintColor;

return mix(color, tinted, clamp(tintStrength, 0.0, 1.0));
}

vec3 blendColorsHSV(vec3 color1, vec3 color2, float t) {
vec3 hsv1 = rgb2hsv(color1);
vec3 hsv2 = rgb2hsv(color2);

float hueDiff = hsv2.x - hsv1.x;
if (hueDiff > 0.5) hsv1.x += 1.0;
else if (hueDiff < -0.5) hsv2.x += 1.0;

vec3 hsvBlend = mix(hsv1, hsv2, t);
hsvBlend.x = fract(hsvBlend.x);

return hsv2rgb(hsvBlend);
}

vec3 blendColorsSaturated(vec3 color1, vec3 color2, float t) {

vec3 blended = mix(color1, color2, t);

float midBoost = 1.0 + 0.3 * sin(t * 3.14159);
vec3 hsv = rgb2hsv(blended);
hsv.y = min(hsv.y * midBoost, 1.0);

return hsv2rgb(hsv);
}
