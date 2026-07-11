#ifdef RINGED_PLANET_ENABLED

#ifndef PI
#define PI 3.14159265359
#endif

float curve_p(float x) { return x * x * (3.0 - 2.0 * x); }
float saturate_p(float x) { return clamp(x, 0.0, 1.0); }

vec2 RaySphereIntersectionIO_p(vec3 p, vec3 dir, float r) {
float b = dot(p, dir);
float c = -r * r + dot(p, p);
float d = b * b - c;
if (d < 0.0) return vec2(-1e10, 1e10);
d = sqrt(d);
return vec2(-b + d, -b - d);
}

vec3 RayPlaneIntersection_p(vec3 ori, vec3 dir, vec3 normal) {
float rayPlaneAngle = dot(dir, normal);
float planeRayDist = 1e8;
vec3 intersectionPos = dir * planeRayDist;
if (rayPlaneAngle > 0.0001 || rayPlaneAngle < -0.0001) {
planeRayDist = dot(-ori, normal) / rayPlaneAngle;
intersectionPos = ori + dir * planeRayDist;
}
return intersectionPos;
}

vec3 H_p(vec3 albedo, float a) {
a = max(a, 0.001);
vec3 R = sqrt(vec3(1.0) - clamp(albedo, 0.001, 0.999));
vec3 r = (1.0 - R) / (1.0 + R);
vec3 H = r + (0.5 - r * a) * log((1.0 + a) / a);
H *= albedo * a;
return 1.0 / (1.0 - clamp(H, 0.0, 0.99));
}

vec3 ppss_p(vec3 albedo, vec3 normal, vec3 eyeDir, vec3 lightDir, float s) {
float NdotL = dot(normal, lightDir);
float NdotV = dot(normal, eyeDir);
albedo *= curve_p(saturate_p(NdotL));
NdotL = max(NdotL, 0.001);
NdotV = max(NdotV, 0.001);
vec3 color = albedo * H_p(albedo, NdotL) * H_p(albedo, NdotV) / (4.0 * PI * (NdotL + NdotV));
return clamp(color, 0.0, 1.0);
}

float Disc_p(float a, float s, float h) {
float disc = curve_p(saturate_p((a - (1.0 - s)) * h));
return disc * disc;
}

float MiePhase_p(float g, float cosTheta) {
float g2 = g * g;
return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

void PlanetEnd2(inout vec3 color, in vec3 eyeIn, in vec3 rayDir, in vec3 lightDir) {
float Rground = 20e6;
vec3 eye = vec3(0.0);
eye.y += Rground;
eye.y += 15e6;

float VdotL = dot(lightDir, rayDir);

float angleX = -1.8;
float angleY = 3.0;

mat3 eyeRotationMatrixX = mat3(1, 0, 0, 0, cos(angleX), -sin(angleX), 0, sin(angleX), cos(angleX));
mat3 eyeRotationMatrixY = mat3(cos(angleY), 0, sin(angleY), 0, 1, 0, -sin(angleY), 0, cos(angleY));
mat3 eyeRotationMatrix = eyeRotationMatrixX * eyeRotationMatrixY;

float ringAngle = 0.008;

mat3 ringRotationMatrix = mat3(1.0, 0.0, 0.0,
0.0, cos(ringAngle), sin(ringAngle),
0.0, -sin(ringAngle), cos(ringAngle));
mat3 ringRotationMatrixInverse = transpose(ringRotationMatrix);

rayDir = eyeRotationMatrix * rayDir;
lightDir = eyeRotationMatrix * lightDir;

vec3 rayDirRing = ringRotationMatrix * rayDir;
vec3 lightDirRing = ringRotationMatrix * lightDir;

vec3 ringOrigin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground);
vec2 ringRadius = vec2(1.6, 2.6);

vec3 surface = vec3(0.0);

vec2 RgroundIntersection = RaySphereIntersectionIO_p(eye, rayDir, Rground);
if (RgroundIntersection.x > 0.0) {
color *= 0.0;
vec3 surfacePos = rayDir * RgroundIntersection.y;
vec3 surfaceNormal = normalize(surfacePos - vec3(0.0, -eye.y, 0.0));
vec3 surfaceAlbedo = vec3(1.0, 0.87, 0.55);

float NdotL = max(dot(surfaceNormal, lightDir), 0.0);
surface = surfaceAlbedo * (NdotL * 0.7 + 0.3);

vec3 origin = ringOrigin + surfacePos / Rground;
vec3 rayPos = RayPlaneIntersection_p(origin, lightDirRing, vec3(0.0, 0.0, 1.0));
float rayRadiusShadow = length(rayPos);

if (rayRadiusShadow > ringRadius.x && rayRadiusShadow < ringRadius.y && dot(rayPos - origin, lightDirRing) > 0.0) {
float accum = 0.0;
float alpha = 0.5;
float position = rayRadiusShadow * 0.5 + 0.69;
for (int i = 0; i < 5; i++) {
accum += alpha * texture(noisetex, vec2(position, 0.0)).z;
position = position * 4.0;
alpha *= 0.5;
}
float octShift = 0.025;
surface *= exp(-pow(saturate_p(accum + octShift - 0.1) * 1.5, 3.0) * smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadiusShadow));
}

float UdotN = saturate_p(dot(ringRotationMatrixInverse[2], surfaceNormal));
float DdotN = saturate_p(dot(-ringRotationMatrixInverse[2], surfaceNormal));
float OLdotN = saturate_p(dot(ringRotationMatrixInverse * normalize(vec3(-lightDir.xy, 0.0)), surfaceNormal));

float ringLighting = Disc_p(UdotN, 1.2, 1.5) * (1.0 - Disc_p(UdotN, 3.4, 0.3));
ringLighting += Disc_p(DdotN, 1.2, 1.5) * (1.0 - Disc_p(DdotN, 3.4, 0.3));
ringLighting *= 1.0 - Disc_p(OLdotN, 0.7, 1.3);

surface += surfaceAlbedo * (0.01 + ringLighting * 0.7);
}

color += surface * 0.5;

vec3 ring = vec3(0.0);

{
vec3 origin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground);
vec3 ringPos = RayPlaneIntersection_p(origin, rayDirRing, vec3(0.0, 0.0, 1.0));
float rayRadiusRing = length(ringPos);

if (rayRadiusRing > ringRadius.x && rayRadiusRing < ringRadius.y) {

float ringNorm = (rayRadiusRing - ringRadius.x) / (ringRadius.y - ringRadius.x);
float pattern = sin(rayRadiusRing * 15.0) * 0.2 + 0.7;
pattern *= smoothstep(0.0, 0.1, ringNorm);
pattern *= smoothstep(1.0, 0.9, ringNorm);

ring = vec3(pattern);

if (ringPos.y < 0.0 && RgroundIntersection.x > 0.0) {
ring *= 0.0;
} else {
color *= exp(-ring * 1.5);
}

float d = length(cross(lightDirRing, ringPos));
if (d < 1.0 && dot(lightDirRing, ringPos) < 0.0) ring *= 0.1;
}
}
ring *= vec3(1.0, 0.85, 0.60) * (1.0 + MiePhase_p(0.8, VdotL) * 10.0);

color += ring * 0.3;
}
#endif
