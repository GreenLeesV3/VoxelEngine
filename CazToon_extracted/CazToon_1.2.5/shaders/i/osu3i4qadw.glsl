#ifdef LAVA_CRUST_ENABLED

vec3 applyLavaCrust(vec3 color, vec3 worldP, vec3 N) {

#ifndef VOXY_PROGRAM
if (biome == 82 && abs(N.y) > 0.5) {
vec2 spiralUV = floor(worldP.xz * 16.0) / 16.0;
float t = frameTimeCounter * 0.15;

float angle = atan(spiralUV.y - floor(spiralUV.y / 6.0) * 6.0 - 3.0,
spiralUV.x - floor(spiralUV.x / 6.0) * 6.0 - 3.0);
float dist = length(vec2(spiralUV.x - floor(spiralUV.x / 6.0) * 6.0 - 3.0,
spiralUV.y - floor(spiralUV.y / 6.0) * 6.0 - 3.0));

float s1 = sin(angle * 2.0 + dist * 5.0 - t * 1.5) * 0.5 + 0.5;

vec2 off2 = spiralUV + vec2(2.7, 1.3);
float a2 = atan(off2.y - floor(off2.y / 8.0) * 8.0 - 4.0,
off2.x - floor(off2.x / 8.0) * 8.0 - 4.0);
float d2 = length(vec2(off2.x - floor(off2.x / 8.0) * 8.0 - 4.0,
off2.y - floor(off2.y / 8.0) * 8.0 - 4.0));
float s2 = sin(a2 * 3.0 - d2 * 4.0 + t * 1.2) * 0.5 + 0.5;

float detail = noise3D(vec3(spiralUV * 2.0, t * 0.3)) * 0.5 + 0.5;
float spiral = mix(s1, s2, 0.4) * 0.7 + detail * 0.3;

float crust = smoothstep(0.05, 0.55, spiral);
crust = floor(crust * 7.0 + 0.5) / 7.0;
float crustDepth = smoothstep(0.05, 0.8, spiral);
crustDepth = floor(crustDepth * 7.0 + 0.5) / 7.0;

vec3 darkLava = mix(color * 0.15, color * 0.5, crustDepth);
vec3 crustColor = mix(color, darkLava, crust);
crustColor = max(vec3(0.01), crustColor);

float yFade = (worldP.y > 30.0 && worldP.y < 32.0) ? 1.0 : 0.5;
return mix(color, crustColor, LAVA_NOISE_INTENSITY * yFade);
}
#endif

float lum = dot(color, vec3(0.299, 0.587, 0.114));
float lavaEmission = lum * 7.48 + 0.5;

float sideFace = 1.0 - abs(N.y);

vec2 lavaPos = (floor(worldP.xz * 16.0) + worldP.y * 32.0) * 0.000666;
vec2 wind = vec2(frameTimeCounter * 0.012, 0.0);

float noise = -1.0 * LAVA_NOISE_AMOUNT;
float lavaNoiseIntensity = LAVA_NOISE_INTENSITY;
vec3 lavaNoiseColor = color;

float e2 = lavaEmission * 0.50;
e2 = e2 * e2; e2 = e2 * e2;
lavaNoiseColor += min(e2, 0.2) * LAVA_TEMPERATURE * 0.65;

if (sideFace > 0.5) {
vec3 pixP = floor(worldP * 16.0) / 16.0;
float flow = frameTimeCounter * 0.7;

float wobble = noise3D(vec3(pixP.x * 3.0, (pixP.y + flow) * 0.8, pixP.z * 3.0)) * 0.3;
wobble += noise3D(vec3(pixP.x * 1.5, (pixP.y + flow) * 0.4, pixP.z * 1.5)) * 0.4;

float phaseOffset = noise3D(vec3(pixP.x * 0.5, 0.0, pixP.z * 0.5)) * 12.0;

float band = sin((pixP.y + flow) * 0.7 + wobble + phaseOffset) * 0.5 + 0.5;

float detail = noise3D(pixP * 2.5 + vec3(0.0, flow * 0.5, 0.0)) * 0.5 + 0.5;
detail -= (noise3D(pixP * 8.0 + vec3(0.0, flow * 0.3, 0.0)) * 0.5 + 0.5) * 0.08;
detail += (noise3D(pixP * 5.0 + vec3(0.0, flow * 0.2, 0.0)) * 0.5 + 0.5) * 0.3;
band = clamp(band * 0.45 + detail * 0.55, 0.0, 1.0);

float crust = 1.0 - pow(band, 5.0);
crust = floor(crust * 7.0 + 0.5) / 7.0;

float depth = sqrt(band);
depth = floor(depth * 7.0 + 0.5) / 7.0;
vec3 darkLava = mix(vec3(0.25, 0.05, 0.02), vec3(0.71, 0.16, 0.07), depth);
lavaNoiseColor = mix(color, darkLava, crust * 0.6);

lavaNoiseColor = max(vec3(0.01), lavaNoiseColor);
return mix(color, lavaNoiseColor, lavaNoiseIntensity);
}

#ifdef LAVA_HAS_NOISETEX
noise += texture2DLod(noisetex, lavaPos * 0.15 + wind * 0.1, 2.0).r;
noise -= texture2DLod(noisetex, lavaPos * 5.0 + wind * 0.05, 3.0).g * 0.08;
noise += texture2DLod(noisetex, lavaPos * 1.5 + wind * 0.03, 2.0).r * 0.45;
noise *= texture2DLod(noisetex, lavaPos * 0.05 + wind * 0.02, 2.0).r * 0.5;
lavaEmission *= 1.6;
float crust = smoothstep(0.05, 0.55, noise);
crust = floor(crust * 7.0 + 0.5) / 7.0;
float depth = smoothstep(0.05, 0.8, noise);
depth = floor(depth * 7.0 + 0.5) / 7.0;
vec3 darkLava = mix(vec3(0.71, 0.16, 0.07), vec3(0.25, 0.05, 0.02), depth);
lavaNoiseColor = mix(color, darkLava, crust);
#else

noise += noise3D(vec3((lavaPos * 0.15 + wind * 0.1) * 256.0, 0.0)) * 0.5 + 0.5;
noise -= (noise3D(vec3((lavaPos * 5.0 + wind * 0.05) * 256.0, 0.0)) * 0.5 + 0.5) * 0.08;
noise += (noise3D(vec3((lavaPos * 1.5 + wind * 0.03) * 256.0, 0.0)) * 0.5 + 0.5) * 0.45;
noise *= (noise3D(vec3((lavaPos * 0.05 + wind * 0.02) * 256.0, 0.0)) * 0.5 + 0.5) * 0.5;
lavaEmission *= 1.6;
float crust = smoothstep(0.05, 0.55, noise);
crust = floor(crust * 7.0 + 0.5) / 7.0;
float depth = smoothstep(0.05, 0.8, noise);
depth = floor(depth * 7.0 + 0.5) / 7.0;
vec3 darkLava = mix(vec3(0.71, 0.16, 0.07), vec3(0.25, 0.05, 0.02), depth);
lavaNoiseColor = mix(color, darkLava, crust);
#endif

lavaNoiseColor = max(vec3(0.01), lavaNoiseColor);

float yFade = (worldP.y > 30.0 && worldP.y < 32.0) ? 1.0 : 0.5;
color = mix(color, lavaNoiseColor, lavaNoiseIntensity * yFade);

return color;
}

#endif
