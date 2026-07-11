#ifndef HELD_LIGHT_POST_GLSL
#define HELD_LIGHT_POST_GLSL

vec3 getPostHeldItemLightColor(int heldId) {
if (heldId == 10021 || heldId == 10043) return vec3(0.3, 0.7, 1.0);
if (heldId == 10087 || heldId == 10089) return vec3(0.3, 1.0, 0.4);
if (heldId == 10038 || heldId == 10058) return vec3(1.0, 0.2, 0.2);
return vec3(1.0, 0.75, 0.4);
}

vec3 getPostHandheldLightBoost(vec3 worldPos, vec3 baseColor, vec3 litColor) {
float mainHeld = clamp(float(max(heldBlockLightValue,  0)) / 15.0, 0.0, 1.0);
float offHeld  = clamp(float(max(heldBlockLightValue2, 0)) / 15.0, 0.0, 1.0);

float heldLevel = max(mainHeld, offHeld);
if (heldLevel < 0.001) return vec3(0.0);

vec3 playerCenter = eyePosition - vec3(0.0, 0.5, 0.0);
vec3 delta = worldPos - playerCenter;
float radius = max(HANDHELD_LIGHT_RADIUS, 0.01);
float xzDist = length(delta.xz);
float yOffset = max(abs(delta.y) - 1.0, 0.0);
float dist = sqrt(xzDist * xzDist + yOffset * yOffset);

float t = clamp(dist / radius, 0.0, 1.0);
float atten = 1.0 - t * t;
atten = atten * atten * atten;

float intensity = heldLevel * atten * HANDHELD_LIGHT_STRENGTH;
float tintWeight = max(mainHeld + offHeld, 0.001);
vec3 tint = (getPostHeldItemLightColor(heldItemId)  * mainHeld +
getPostHeldItemLightColor(heldItemId2) * offHeld) / tintWeight;
vec3 lightColor = max(baseColor, vec3(0.04)) * tint * intensity;
vec3 boost = litColor + lightColor - litColor * lightColor;
return max(boost - litColor, vec3(0.0));
}

#endif
