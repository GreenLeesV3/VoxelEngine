#include "/settings.glsl"

#include "/include/waving.glsl"
#include "/include/hovering.glsl"
#include "/include/shadow.glsl"
#include "/include/ocean_waves.glsl"

const float ambientOcclusionLevel = 0.0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform float sunAngle;
uniform int frameCounter;
uniform float biome_beach;
uniform float biome_ocean;
uniform float biome_swamp;
out vec2 texcoord;
out vec4 glcolor;
out float viewDistance;
out float postMask;
out float isWater;
out float isHologram;
out vec3 worldPos;
out vec3 viewPos;
out vec3 normal;
out float skylight;
out float blocklight;
out vec3 waveNormal;
out float waveHeight;
out vec4 shadowPos;
flat out float isIce;
flat out float isHeatSource;
flat out int blockId;
out float waterBlockFracY;
out float waterFlowFlag;
#ifdef PBR_ENABLED
out vec3 tangentVec;
out vec3 binormalVec;
#endif

attribute vec4 mc_Entity;
attribute vec4 at_midBlock;
#ifdef PBR_ENABLED
attribute vec4 at_tangent;
#endif

void main() {
texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
glcolor = gl_Color;
viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
vec3 world_pos = scenePos + cameraPosition;

int block_id_raw = int(mc_Entity.x);
bool has_block_properties_id = (block_id_raw >= 10000);
int block_id = has_block_properties_id ? (block_id_raw - 10000) : 0;
bool water = (has_block_properties_id && block_id == 1);

float blockY = floor(world_pos.y);
float vertexInBlock = world_pos.y - blockY;

float distFromStillLevel = abs(vertexInBlock - 0.875);

waterBlockFracY = clamp(distFromStillLevel * 4.0, 0.0, 1.0);

waterFlowFlag = (distFromStillLevel > 0.05) ? 1.0 : 0.0;

waveNormal = vec3(0.0, 1.0, 0.0);
waveHeight = 0.0;
#ifdef WATER_WAVES_ENABLED

#define WAVE_RAW(f) (smoothstep(0.15, 0.25, f) * (1.0 - pow(smoothstep(0.25, 1.15, f), 0.45)))
#define WAVE(px) WAVE_RAW(1.0 - fract(px))

#define OWAVE(px) (pow(0.5 + 0.5 * sin((fract(px) - 0.25) * 6.2832), 1.6))
#define SMAX(a, b, k) (max(a, b) + pow(max(k - abs(a - b), 0.0) / k, 3.0) * k * 0.166667)

bool atSeaLevel = abs(world_pos.y - float(SEA_LEVEL_OFFSET)) < 1.0;
if (water && gl_Normal.y > 0.5 && biome_beach > 0.01 && biome_beach >= biome_ocean && atSeaLevel) {

float t = frameTimeCounter * WATER_WAVE_SPEED;
float wx = world_pos.x * WATER_WAVE_SCALE;
float wz = world_pos.z * WATER_WAVE_SCALE;
float distFade = 1.0 - smoothstep(48.0, 80.0, length(world_pos.xz - cameraPosition.xz));
float amp = 0.8 * biome_beach * distFade;

float zOff1 = sin(wz * 0.21 + 3.7) * 2.5 + sin(wz * 0.53 + 1.2) * 1.3;
float zOff2 = sin(wz * 0.37 + 5.1) * 1.8 + sin(wz * 0.71 + 2.8) * 1.1;
float zOff3 = sin(wz * 0.62 + 0.9) * 1.2 + sin(wz * 0.89 + 4.3) * 0.8;

float w1 = WAVE((wx * 0.8 + zOff1 - t * 1.0) / 6.2832);
float w2 = WAVE((wx * 1.8 + zOff2 - t * 1.6) / 6.2832);
float height = clamp(SMAX(w1, w2 * 0.55, 0.15), 0.0, 1.0);
height += WAVE((wx * 4.0 + zOff3 - t * 2.2) / 6.2832) * 0.15 * height;

float displacement = -amp * (1.0 - height);
world_pos.y += displacement;
waveHeight = clamp(height, 0.0, 1.0);

float eps = 0.05;
float wxp = (world_pos.x + eps) * WATER_WAVE_SCALE;
float wzp = (world_pos.z + eps) * WATER_WAVE_SCALE;

float hx = clamp(SMAX(WAVE((wxp * 0.8 + zOff1 - t) / 6.2832), WAVE((wxp * 1.8 + zOff2 - t * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
hx += WAVE((wxp * 4.0 + zOff3 - t * 2.2) / 6.2832) * 0.15 * hx;

float zOff1z = sin(wzp * 0.21 + 3.7) * 2.5 + sin(wzp * 0.53 + 1.2) * 1.3;
float zOff2z = sin(wzp * 0.37 + 5.1) * 1.8 + sin(wzp * 0.71 + 2.8) * 1.1;
float zOff3z = sin(wzp * 0.62 + 0.9) * 1.2 + sin(wzp * 0.89 + 4.3) * 0.8;
float hz = clamp(SMAX(WAVE((wx * 0.8 + zOff1z - t) / 6.2832), WAVE((wx * 1.8 + zOff2z - t * 1.6) / 6.2832) * 0.55, 0.15), 0.0, 1.0);
hz += WAVE((wx * 4.0 + zOff3z - t * 2.2) / 6.2832) * 0.15 * hz;

float dhdx = (-amp * (1.0 - hx) - displacement) / eps;
float dhdz = (-amp * (1.0 - hz) - displacement) / eps;
waveNormal = normalize(vec3(-dhdx, 1.0, -dhdz));

} else if (water && gl_Normal.y > 0.5 && biome_swamp < 0.01) {

waveHeight = 0.5;
waveNormal = vec3(0.0, 1.0, 0.0);
}
#undef WAVE
#undef WAVE_RAW
#undef OWAVE
#undef SMAX
#endif

float hoverOffset = getHoverOffset(world_pos);
world_pos.y += hoverOffset;
scenePos = world_pos - cameraPosition;
viewPos = (gbufferModelView * vec4(scenePos, 1.0)).xyz;
gl_Position = gl_ProjectionMatrix * vec4(viewPos, 1.0);

worldPos = world_pos;
viewDistance = length(viewPos);

normal = normalize(gl_NormalMatrix * gl_Normal);
#ifdef PBR_ENABLED
tangentVec = normalize(gl_NormalMatrix * at_tangent.xyz);
binormalVec = normalize(cross(normal, tangentVec) * at_tangent.w);
#endif

isWater = water ? 1.0 : 0.0;
bool iceBlock = (has_block_properties_id && block_id == 8);
isIce = iceBlock ? 1.0 : 0.0;
bool isSlime = (has_block_properties_id && block_id == 14);
postMask = (isWater > 0.5) ? 0.0 : 1.0;

isHologram = (isWater < 0.5 && !iceBlock && !isSlime) ? 1.0 : 0.0;
bool isHeat = (block_id == 20 || block_id == 21 || block_id == 22 || block_id == 36 || block_id == 39 || block_id == 40);
isHeatSource = (has_block_properties_id && isHeat) ? 1.0 : 0.0;
blockId = block_id;

vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
blocklight = clamp(lmcoord.x, 0.0, 1.0);
skylight = clamp(lmcoord.y, 0.0, 1.0);

#ifdef SWAYING_LANTERNS
if (has_block_properties_id && (block_id == 6 || block_id == 89)) {
world_pos = animate_vertex(world_pos, false, skylight, block_id, at_midBlock.xyz);
scenePos = world_pos - cameraPosition;
viewPos = (gbufferModelView * vec4(scenePos, 1.0)).xyz;
gl_Position = gl_ProjectionMatrix * vec4(viewPos, 1.0);
worldPos = world_pos;
viewDistance = length(viewPos);
}
#endif

shadowPos = vec4(0.0);
#ifdef SHADOWS_ENABLED
vec4 shadowClipPos4 = shadowProjection * shadowModelView * vec4(scenePos, 1.0);
vec3 shadowClipPosXYZ = shadowClipPos4.xyz;
float bias = computeBias(shadowClipPosXYZ);
vec3 distorted = distortShadowClipPos(shadowClipPosXYZ);
shadowPos.xyz = distorted * 0.5 + 0.5;

vec4 shadowNormalVec = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * normal), 1.0);
shadowPos.xyz += shadowNormalVec.xyz / shadowNormalVec.w * bias;
shadowPos.w = dot(normalize(shadowLightPosition), normalize(gl_NormalMatrix * gl_Normal));
#endif
}
