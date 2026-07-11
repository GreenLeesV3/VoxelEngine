#ifndef PBR_GLSL_INCLUDED
#define PBR_GLSL_INCLUDED

#ifndef PBR_FORMAT
#define PBR_FORMAT 0
#endif

#if PBR_FORMAT == 1
#define PBR_USE_LABPBR
#elif PBR_FORMAT == 2
#define PBR_USE_OLDPBR
#else

#ifdef MC_TEXTURE_FORMAT_LAB_PBR
#define PBR_USE_LABPBR
#else
#define PBR_USE_OLDPBR
#endif
#endif

#ifndef PBR_GGX_DEFINED
#define PBR_GGX_DEFINED
float pbr_distributionGGX(float NdotH, float roughness) {
float a  = roughness * roughness;
float a2 = a * a;
float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
return a2 / (3.14159265 * d * d);
}

float pbr_fresnelSchlick(float cosTheta, float F0) {
float ct = max(cosTheta, 0.0);
float m  = 1.0 - ct;
float m2 = m * m;
return F0 + (1.0 - F0) * m2 * m2 * m;
}

vec3 pbr_fresnelSchlickColor(float cosTheta, vec3 F0) {
float ct = max(cosTheta, 0.0);
float m  = 1.0 - ct;
float m2 = m * m;
return F0 + (vec3(1.0) - F0) * m2 * m2 * m;
}

float pbr_geometrySmith(float NdotV, float NdotL, float roughness) {
float r = roughness + 1.0;
float k = (r * r) * 0.125;
float gv = NdotV / (NdotV * (1.0 - k) + k);
float gl = NdotL / (NdotL * (1.0 - k) + k);
return gv * gl;
}
#endif

vec3 pbr_getMetalF0(int metalId) {
if (metalId == 230) return vec3(0.560, 0.570, 0.580);
if (metalId == 231) return vec3(1.000, 0.710, 0.290);
if (metalId == 232) return vec3(0.913, 0.922, 0.924);
if (metalId == 233) return vec3(0.550, 0.556, 0.554);
if (metalId == 234) return vec3(0.955, 0.638, 0.538);
if (metalId == 235) return vec3(0.632, 0.626, 0.641);
if (metalId == 236) return vec3(0.673, 0.637, 0.585);
if (metalId == 237) return vec3(0.972, 0.960, 0.915);
return vec3(0.560, 0.570, 0.580);
}

struct PBRMaterial {

vec3  nTangent;
float height;
float ao;

float roughness;
float F0scalar;
vec3  F0;
float metalness;
int   metalId;

float porosity;
float sss;
bool  hasSSS;

float emission;

bool  hasData;
bool  hasNormal;
bool  hasSpec;
};

bool pbr_hasPackData(vec4 normalTex, vec4 specTex) {
bool normalFlat = abs(normalTex.r - 0.5) < 0.02
&& abs(normalTex.g - 0.5) < 0.02
&& normalTex.b > 0.95;
bool specEmpty  = (specTex.r + specTex.g + specTex.b + specTex.a) < 0.01;
return !(normalFlat && specEmpty);
}

PBRMaterial pbr_decode(vec4 normalTex, vec4 specTex, vec3 albedo, float normalStrength) {
PBRMaterial m;

bool normalFlat = abs(normalTex.r - 0.5) < 0.02
&& abs(normalTex.g - 0.5) < 0.02
&& normalTex.b > 0.95;
bool specEmpty  = (specTex.r + specTex.g + specTex.b + specTex.a) < 0.01;
m.hasNormal = !normalFlat;
m.hasSpec   = !specEmpty;
m.hasData   = m.hasNormal || m.hasSpec;

vec2 nxy = normalTex.rg * 2.0 - 1.0;
nxy *= normalStrength;
float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
m.nTangent = normalize(vec3(nxy, max(nz, 1e-4)));

#ifdef PBR_USE_LABPBR
m.ao     = normalTex.b;
m.height = normalTex.a;
#else
m.ao     = 1.0;
m.height = 1.0;
#endif

#ifdef PBR_USE_LABPBR

float perceptualSmooth = specTex.r;
m.roughness = pow(1.0 - perceptualSmooth, 2.0);

float g255 = specTex.g * 255.0;
if (g255 > 229.5) {
int id = int(floor(g255 + 0.5));
m.metalId   = id;
m.metalness = 1.0;
if (id == 255) {

m.F0       = max(albedo, vec3(0.04));
m.F0scalar = dot(m.F0, vec3(0.333));
} else {
m.F0       = pbr_getMetalF0(id);
m.F0scalar = dot(m.F0, vec3(0.333));
}
} else {
m.metalId   = 0;
m.metalness = 0.0;

m.F0scalar = clamp(specTex.g * (255.0 / 229.0), 0.0, 1.0);
m.F0scalar = max(m.F0scalar, 0.02);
m.F0       = vec3(m.F0scalar);
}

float b255 = specTex.b * 255.0;
if (b255 < 64.5) {
m.porosity = b255 / 64.0;
m.sss      = 0.0;
m.hasSSS   = false;
} else {
m.porosity = 0.0;
m.sss      = (b255 - 65.0) / 190.0;
m.hasSSS   = (m.sss > 0.001);
}

float a255 = specTex.a * 255.0;
m.emission = (a255 > 254.5) ? 0.0 : a255 / 254.0;
#else

m.roughness = pow(1.0 - specTex.r, 2.0);

m.metalness = specTex.g;
bool isMetal = (m.metalness > 0.5);
m.metalId = 0;
if (isMetal) {

m.F0       = max(albedo, vec3(0.04));
m.F0scalar = dot(m.F0, vec3(0.333));
} else {
m.F0scalar = 0.04;
m.F0       = vec3(0.04);
}

m.emission = specTex.b;

m.porosity = 0.0;
m.sss      = 0.0;
m.hasSSS   = false;
#endif

if (!m.hasSpec) {
m.roughness = 1.0;
m.F0scalar  = 0.04;
m.F0        = vec3(0.04);
m.metalness = 0.0;
m.metalId   = 0;
m.emission  = 0.0;
m.porosity  = 0.0;
m.sss       = 0.0;
m.hasSSS    = false;
}

return m;
}

PBRMaterial pbr_fallback(vec3 geometricNormalViewSpace, float defaultRoughness) {
PBRMaterial m;
m.nTangent  = vec3(0.0, 0.0, 1.0);
m.height    = 1.0;
m.ao        = 1.0;
m.roughness = defaultRoughness;
m.F0scalar  = 0.04;
m.F0        = vec3(0.04);
m.metalness = 0.0;
m.metalId   = 0;
m.porosity  = 0.0;
m.sss       = 0.0;
m.hasSSS    = false;
m.emission  = 0.0;
m.hasData   = false;
m.hasNormal = false;
m.hasSpec   = false;
return m;
}

vec3 pbr_tangentToView(vec3 nTangent, vec3 tangentV, vec3 binormalV, vec3 normalV) {
mat3 TBN = mat3(normalize(tangentV), normalize(binormalV), normalize(normalV));
return normalize(TBN * nTangent);
}

vec4 pbr_packToColortex5(PBRMaterial m, vec3 worldNormal) {
float x = clamp(m.roughness, 0.0, 1.0);
float y = clamp(m.metalness, 0.0, 0.85);
return vec4(x, y, worldNormal.x * 0.5 + 0.5, worldNormal.y * 0.5 + 0.5);
}

void pbr_unpackFromColortex5(vec4 tex, out float roughness, out float metalness) {
roughness = clamp(tex.x, 0.0, 1.0);
metalness = clamp(tex.y / 0.85, 0.0, 1.0);
}

#endif
