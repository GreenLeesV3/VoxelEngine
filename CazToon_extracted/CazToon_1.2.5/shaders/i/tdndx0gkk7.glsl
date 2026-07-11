float cloudShadowHash(vec2 p) {
vec3 p3 = fract(vec3(p.xyx) * 0.1031);
p3 += dot(p3, p3.yzx + 33.33);
return fract((p3.x + p3.y) * p3.z);
}

float cloudShadowNoise(vec2 p) {
vec2 i = floor(p);
vec2 f = fract(p);
f = f * f * (3.0 - 2.0 * f);

float a = cloudShadowHash(i);
float b = cloudShadowHash(i + vec2(1.0, 0.0));
float c = cloudShadowHash(i + vec2(0.0, 1.0));
float d = cloudShadowHash(i + vec2(1.0, 1.0));

return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cloudShadowFBM(vec2 p) {
float value = 0.0;
float amplitude = 0.5;
float frequency = 1.0;

for (int i = 0; i < 5; i++) {
value += amplitude * cloudShadowNoise(p * frequency);
amplitude *= 0.5;
frequency *= 2.0;
}

return value;
}

float getCloudShadow(vec3 wPos, float time) {

float r = 2500.0;
float speed = CLOUD_SPEED * 3.0;
float angle = time * speed / r;
vec2 offset = vec2(cos(angle), sin(angle)) * r;

vec2 cloudPos = (wPos.xz + offset) * CLOUD_SCALE;

float noise = cloudShadowFBM(cloudPos);
float density = smoothstep(1.0 - CLOUD_COVERAGE, 1.0 - CLOUD_COVERAGE + 0.3, noise);

#if CLOUD_TOON_EDGES == 1
density = step(0.3, density);
#endif

return 1.0 - density * CLOUD_SHADOW_STRENGTH;
}
