float hash12(vec2 p) {
return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smoothChunkNoise(vec2 p) {
vec2 i = floor(p);
vec2 f = fract(p);
f = f * f * (3.0 - 2.0 * f);
float a = hash12(i);
float b = hash12(i + vec2(1.0, 0.0));
float c = hash12(i + vec2(0.0, 1.0));
float d = hash12(i + vec2(1.0, 1.0));
return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float hash31(vec3 p) {
p = fract(p * vec3(0.1031, 0.1030, 0.0973));
p += dot(p, p.yzx + 33.33);
return fract((p.x + p.y) * p.z);
}

float noise3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);
f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

float a = hash31(i);
float b = hash31(i + vec3(1,0,0));
float c = hash31(i + vec3(0,1,0));
float d = hash31(i + vec3(1,1,0));
float e = hash31(i + vec3(0,0,1));
float g = hash31(i + vec3(1,0,1));
float h = hash31(i + vec3(0,1,1));
float k = hash31(i + vec3(1,1,1));

return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}
