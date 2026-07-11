#include "/settings.glsl"

out vec2 texcoord;
out vec4 glcolor;
out vec2 lmcoord;
out float viewDist;

uniform float frameTimeCounter;
uniform float rainStrength;
uniform ivec2 eyeBrightnessSmooth;
uniform int biome_precipitation;

float hash11(float n) {
return fract(sin(n) * 43758.5453123);
}

vec2 hash21(vec2 p) {
float n = dot(p, vec2(127.1, 311.7));
float n2 = dot(p, vec2(269.5, 183.3));
return fract(sin(vec2(n, n2)) * 43758.5453123);
}

void main() {
vec2 uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
texcoord = uv;
glcolor = gl_Color;
lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

float playerSkylight = float(eyeBrightnessSmooth.y) / 240.0;
float outdoorFactor = smoothstep(0.5, 0.9, playerSkylight);
float isRain = float(biome_precipitation == 1);
float rs = clamp(rainStrength, 0.0, 1.0);
float w = clamp(RAIN_WIND_STRENGTH, 0.0, 1.0) * rs * outdoorFactor * isRain;

viewDist = length(viewPos.xyz);

gl_Position = gl_ProjectionMatrix * viewPos;

if (w > 0.0001) {
float t = frameTimeCounter;

vec3 windWorld = normalize(vec3(1.0, 0.0, 0.65));
vec4 windClip = gl_ProjectionMatrix * (gl_ModelViewMatrix * vec4(windWorld, 0.0));
vec2 windDir = windClip.xy;
float wLen = length(windDir);
windDir = (wLen > 0.00001) ? (windDir / wLen) : vec2(1.0, 0.0);

float gust = 0.75 + 0.25 * sin(t * 2.6);
float shearAmt = w * gust;

float along = (uv.y - 0.5) * 2.0;

float slantNDC = 0.03 * shearAmt;
gl_Position.xy += windDir * (along * slantNDC) * gl_Position.w;
}

}
