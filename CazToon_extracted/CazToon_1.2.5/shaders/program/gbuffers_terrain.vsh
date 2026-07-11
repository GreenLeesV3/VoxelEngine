const float ambientOcclusionLevel = 0.0;

#include "/settings.glsl"

#if TERRAIN_PROFILE_MODE == 17
#undef WAVING_PLANTS
#elif TERRAIN_PROFILE_MODE == 18
#undef WAVING_LEAVES
#elif TERRAIN_PROFILE_MODE == 19
#undef PLAYER_PLANT_INTERACTION
#elif TERRAIN_PROFILE_MODE == 20
#undef WAVING_PLANTS
#undef WAVING_LEAVES
#undef PLAYER_PLANT_INTERACTION
#undef SWAYING_LANTERNS
#elif TERRAIN_PROFILE_MODE == 21
#undef WAVING_PLANTS
#undef WAVING_LEAVES
#undef PLAYER_PLANT_INTERACTION
#undef SWAYING_LANTERNS
#endif

#include "/include/waving.glsl"
#include "/include/hovering.glsl"
#include "/include/shadow.glsl"

out vec2 texcoord;
out vec2 midTexCoord;
out vec4 glcolor;
out float viewDistance;
out float outlineMask;
out float skylight;
out float blocklight;
flat out float emissive;
flat out float emissiveType;
out vec3 worldPos;
flat out vec3 blockCenterWorld;
flat out float isGrassGeometry;
flat out float isHeatSource;
flat out float isHologram;
flat out float metalness;
flat out float reflective;
out vec4 shadowPos;
out vec3 normal;
flat out vec3 geoNormal;
flat out float blockId;
out float leafAO;
#ifdef PBR_ENABLED
out vec3 tangentVec;
out vec3 binormalVec;
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
attribute vec4 at_midBlock;
#ifdef PBR_ENABLED
attribute vec4 at_tangent;
#endif

void main() {

shadowPos = vec4(0.0);
texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
midTexCoord = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
outlineMask = 1.0;

float maxChannel = max(max(gl_Color.r, gl_Color.g), gl_Color.b);
vec3 flatColor = (maxChannel > 0.001) ? (gl_Color.rgb / maxChannel) : gl_Color.rgb;

skylight = clamp(gl_MultiTexCoord1.y / 240.0, 0.0, 1.0);
blocklight = clamp(gl_MultiTexCoord1.x / 240.0, 0.0, 1.0);

vec2 uv = texcoord;
bool is_top_vertex = uv.y < mc_midTexCoord.y;

int block_id_raw = int(mc_Entity.x);
bool has_block_properties_id = (block_id_raw >= 10000);
int block_id = has_block_properties_id ? (block_id_raw - 10000) : 0;
blockId = float(block_id_raw);

if (has_block_properties_id) {
#ifdef MAGICAL_TOUCH
bool is_outline_blacklisted = (block_id == 2 || block_id == 3 || block_id == 4 || block_id == 5 || block_id == 15 || block_id == 18 || block_id == 19 || block_id == 82 || block_id == 60 || block_id == 61 || block_id == 62);
#else
bool is_outline_blacklisted = false;
#endif
if (is_outline_blacklisted) {
outlineMask = 0.0;
}

bool is_emissive = (block_id >= 20 && block_id <= 59) || block_id == 6 || block_id == 83 || block_id == 84 || block_id == 85 || block_id == 86 || block_id == 87 || block_id == 89 || (block_id >= 95 && block_id <= 97);
emissive = is_emissive ? 1.0 : 0.0;

float bopEmissiveType = (block_id >= 95 && block_id <= 97) ? 5.0 : float(block_id - 20);

float copperBulbType = (block_id == 83) ? 40.0 : (block_id == 84) ? 41.0 : bopEmissiveType;
emissiveType = (block_id == 85) ? 44.0 : (block_id == 86) ? 45.0 : (block_id == 87) ? 46.0 : (block_id == 89) ? 47.0 : copperBulbType;

bool is_heat = (block_id == 20 || block_id == 21 || block_id == 22 || block_id == 36 || block_id == 39 || block_id == 40);
isHeatSource = is_heat ? 1.0 : 0.0;

bool isGlass = (block_id == 14 || block_id == 80 || (block_id >= 64 && block_id <= 79));
isHologram = isGlass ? 1.0 : 0.0;

if (block_id == 12 || block_id == 90 || block_id == 92) {
metalness = 1.0;
} else if (block_id == 13) {
metalness = 2.0;
} else {
metalness = 0.0;
}

reflective = (block_id == 17 || block_id == 12 || block_id == 13 || block_id == 91 || block_id == 92) ? 1.0 : 0.0;
} else {

emissive = 0.0;
emissiveType = 0.0;
isHeatSource = 0.0;
isHologram = 0.0;
metalness = 0.0;
reflective = 0.0;
}

glcolor = vec4(flatColor, gl_Color.a);
leafAO = 0.0;

bool should_wave = false;
#ifdef WAVING_PLANTS
should_wave = should_wave || (block_id == 2 || block_id == 3 || block_id == 4 || block_id == 15 || block_id == 60 || block_id == 61 || block_id == 62);
#endif
#ifdef WAVING_LEAVES
should_wave = should_wave || (block_id == 5 || block_id == 82);
#endif
#ifdef SWAYING_LANTERNS
should_wave = should_wave || (block_id == 6 || block_id == 89);
#endif

should_wave = should_wave && has_block_properties_id;

normal = normalize(gl_NormalMatrix * gl_Normal);
geoNormal = normal;
#ifdef PBR_ENABLED
tangentVec = normalize(gl_NormalMatrix * at_tangent.xyz);
binormalVec = normalize(cross(normal, tangentVec) * at_tangent.w);
#endif

if (!should_wave) {
vec3 view_pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scene_pos = (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
vec3 world_pos_temp = scene_pos + cameraPosition;

float hoverOffset = getHoverOffset(world_pos_temp);
world_pos_temp.y += hoverOffset;
scene_pos = world_pos_temp - cameraPosition;
view_pos = (gbufferModelView * vec4(scene_pos, 1.0)).xyz;
gl_Position = gl_ProjectionMatrix * vec4(view_pos, 1.0);

worldPos = world_pos_temp;
viewDistance = length(view_pos);

bool isFoliageBlock = has_block_properties_id && (block_id == 2 || block_id == 3 || block_id == 4 || block_id == 15 || block_id == 60 || block_id == 61 || block_id == 62);
vec3 n = abs(gl_Normal);
float maxAxis = max(max(n.x, n.y), n.z);
bool isAxisAligned = maxAxis > 0.95;
bool isThinFoliage = isFoliageBlock && !isAxisAligned;
isGrassGeometry = isThinFoliage ? 1.0 : 0.0;

#ifdef SHADOWS_ENABLED
float lightDot = dot(normalize(shadowLightPosition), normalize(gl_NormalMatrix * gl_Normal));

if (isThinFoliage || block_id == 5 || block_id == 82 || block_id == 2 || block_id == 18 || block_id == 19 || block_id == 81 || block_id == 60 || block_id == 61 || block_id == 62) lightDot = 1.0;

{

vec4 shadowClipPos4 = shadowProjection * shadowModelView * vec4(scene_pos, 1.0);
vec3 shadowClipPosXYZ = shadowClipPos4.xyz;

float bias = computeBias(shadowClipPosXYZ);

vec3 distorted = distortShadowClipPos(shadowClipPosXYZ);

shadowPos.xyz = distorted * 0.5 + 0.5;

vec4 normal = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal)), 1.0);
shadowPos.xyz += normal.xyz / normal.w * bias;
}
shadowPos.w = lightDot;
#endif
return;
}

vec3 view_pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
vec3 scene_pos = (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
vec3 world_pos = scene_pos + cameraPosition;

vec3 modelBlockCenter = gl_Vertex.xyz + at_midBlock.xyz / 64.0;
vec3 bcView = (gl_ModelViewMatrix * vec4(modelBlockCenter, 1.0)).xyz;
vec3 bcScene = (gbufferModelViewInverse * vec4(bcView, 1.0)).xyz;
blockCenterWorld = bcScene + cameraPosition;

#ifdef WAVING_PLANTS

bool isFoliageBlock = (block_id == 2 || block_id == 3 || block_id == 4 || block_id == 15 || block_id == 60 || block_id == 61 || block_id == 62);

vec3 n = abs(gl_Normal);
float maxAxis = max(max(n.x, n.y), n.z);
bool isAxisAligned = maxAxis > 0.95;
bool isThinFoliage = isFoliageBlock && !isAxisAligned;
if (block_id == 15) {
vec3 world_pos_animated = animate_vertex(world_pos, is_top_vertex, skylight, block_id, at_midBlock.xyz);
vec3 n = normalize(gl_Normal);
float horiz = 1.0 - step(0.2, abs(n.y));
float axis_aligned = step(0.98, max(abs(n.x), abs(n.z)));
float rotated_blade_mask = horiz * (1.0 - axis_aligned);

if (rotated_blade_mask > 0.5) {
world_pos = world_pos_animated;
}
} else {
world_pos = animate_vertex(world_pos, is_top_vertex, skylight, block_id, at_midBlock.xyz);
}
isGrassGeometry = isThinFoliage ? 1.0 : 0.0;
#else
world_pos = animate_vertex(world_pos, is_top_vertex, skylight, block_id, at_midBlock.xyz);

bool isFoliageBlock2 = (block_id == 2 || block_id == 3 || block_id == 4 || block_id == 15 || block_id == 60 || block_id == 61 || block_id == 62);
vec3 n2 = abs(gl_Normal);
float maxAxis2 = max(max(n2.x, n2.y), n2.z);
bool isAxisAligned2 = maxAxis2 > 0.95;
bool isThinFoliage2 = isFoliageBlock2 && !isAxisAligned2;
isGrassGeometry = isThinFoliage2 ? 1.0 : 0.0;
#endif

float hoverOffset = getHoverOffset(world_pos);
world_pos.y += hoverOffset;
scene_pos = world_pos - cameraPosition;
view_pos = (gbufferModelView * vec4(scene_pos, 1.0)).xyz;

gl_Position = gl_ProjectionMatrix * vec4(view_pos, 1.0);

viewDistance = length(view_pos);
worldPos = world_pos;

#ifdef SHADOWS_ENABLED
float lightDot = dot(normalize(shadowLightPosition), normalize(gl_NormalMatrix * gl_Normal));

bool isGrassBlockBlade = (block_id == 15) && (max(max(abs(gl_Normal.x), abs(gl_Normal.y)), abs(gl_Normal.z)) < 0.95);
if (isGrassGeometry > 0.5 || isGrassBlockBlade || block_id == 5 || block_id == 82 || block_id == 2 || block_id == 19 || block_id == 81 || block_id == 60 || block_id == 61 || block_id == 62) lightDot = 1.0;

{

vec4 shadowClipPos4 = shadowProjection * shadowModelView * vec4(scene_pos, 1.0);
vec3 shadowClipPosXYZ = shadowClipPos4.xyz;

float bias = computeBias(shadowClipPosXYZ);

vec3 distorted = distortShadowClipPos(shadowClipPosXYZ);

shadowPos.xyz = distorted * 0.5 + 0.5;

vec4 normal = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal)), 1.0);
shadowPos.xyz += normal.xyz / normal.w * bias;
}
shadowPos.w = lightDot;
#endif
}
