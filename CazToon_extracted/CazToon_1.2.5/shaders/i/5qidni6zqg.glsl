#ifdef END_VORTEX_ENABLED

float endSpiralValue(float angle, float logR, float vortexTime) {

float spiralCoord = angle * END_VORTEX_ARMS + logR * END_VORTEX_TIGHTNESS * 3.0 - vortexTime * END_VORTEX_SPEED * 3.0;

float spiral1 = sin(spiralCoord) * 0.5 + 0.5;
spiral1 = pow(spiral1, 2.5);

float spiral2 = sin(spiralCoord * 0.7 + 2.0) * 0.5 + 0.5;
spiral2 = pow(spiral2, 3.0);

float spiral3 = sin(spiralCoord * 1.3 - 1.5) * 0.5 + 0.5;
spiral3 = pow(spiral3, 3.5);

return spiral1 * 0.5 + spiral2 * 0.3 + spiral3 * 0.2;
}

vec3 endVortex(vec3 dir, float vortexTime, float time, float sizeMult, float eyeOpen) {
if (dir.y < -0.1) return vec3(0.0);

if (sizeMult < 0.001 && eyeOpen < 0.001) return vec3(0.0);

float upAmount = dir.y;
float normDist = 1.0 - clamp(upAmount, 0.0, 1.0);
float horizonFade = smoothstep(-0.1, 0.2, dir.y);

float scaledDist = normDist / max(sizeMult, 0.001);

float angle1 = atan(dir.z, dir.x);
float angle2 = atan(-dir.z, -dir.x);

float logR = log(max(normDist, 0.001));

float spirals1 = endSpiralValue(angle1, logR, vortexTime);
float spirals2 = endSpiralValue(angle2 + 3.14159, logR, vortexTime);

float seamBlend = smoothstep(0.5, -0.5, dir.x) * smoothstep(0.5, 0.0, abs(dir.z));
float spirals = mix(spirals1, spirals2, seamBlend);

float noise1 = endNoise3D(vec3(dir.xz * 4.0, vortexTime * END_VORTEX_SPEED * 0.4));
float noise2 = endFbm3D(vec3(dir.xz * 2.0 + vortexTime * 0.05, scaledDist * 3.0), 3);
spirals *= 0.5 + 0.5 * noise1;
spirals *= 0.6 + 0.4 * noise2;

float radialBright = smoothstep(1.0, 0.1, scaledDist);
radialBright = pow(radialBright, 0.8);
float innerBoost = smoothstep(0.5, 0.05, scaledDist) * 1.5;

float coreGlow = smoothstep(END_VORTEX_CORE_SIZE * 2.0, 0.0, scaledDist);
coreGlow = pow(coreGlow, 2.0);
float hotCenter = smoothstep(END_VORTEX_CORE_SIZE * 0.8, 0.0, scaledDist);
hotCenter = pow(hotCenter, 3.0);

vec3 coreColor = vec3(END_VORTEX_R2, END_VORTEX_G2, END_VORTEX_B2);
vec3 outerStreakColor = coreColor * 0.4;
vec3 innerStreakColor = coreColor * 1.2;
vec3 streakColor = mix(outerStreakColor, innerStreakColor, radialBright);

vec3 result = vec3(0.0);
result += streakColor * spirals * radialBright * 0.8;
result += streakColor * spirals * innerBoost * 0.4;
result += coreColor * coreGlow * 0.6;
result += mix(coreColor, vec3(1.0), 0.6) * hotCenter * 0.8;

#ifdef END_EVENT_EYE_ENABLED
if (eyeOpen > 0.001 && normDist < END_VORTEX_CORE_SIZE * 0.5) {
float eyeRadius = END_VORTEX_CORE_SIZE * 0.15;
float eyeR = normDist / eyeRadius;

float horizLen = max(sqrt(dir.x * dir.x + dir.z * dir.z), 0.0001);
float vertFrac = dir.z / horizLen;
float eyeY = vertFrac * eyeR;
float lidHeight = eyeOpen * 1.2;
float eyeMask = smoothstep(lidHeight + 0.06, lidHeight - 0.06, abs(eyeY));
eyeMask *= smoothstep(1.05, 0.90, eyeR);
eyeMask *= smoothstep(0.0, 0.05, eyeOpen);

if (eyeMask > 0.001) {
vec2 eyeDir = normalize(dir.xz + 0.001);

vec3 warmColor = vec3(END_EVENT_EYE_IRIS_R, END_EVENT_EYE_IRIS_G, END_EVENT_EYE_IRIS_B);

result = mix(result, vec3(0.0), eyeMask);

float ringR = 0.88;
float ringDist = abs(eyeR - ringR);
float brightRing = smoothstep(0.05, 0.005, ringDist);
result += warmColor * 0.8 * brightRing * eyeMask;

float irisInner = 0.18;
float irisOuter = 0.72;
float irisMask = smoothstep(irisInner - 0.03, irisInner + 0.06, eyeR)
* smoothstep(irisOuter + 0.05, irisOuter - 0.06, eyeR);

float tn1 = endNoise3D(vec3(eyeDir * 5.0 + eyeR * 15.0 - time * 0.3, 11.0));
float tn2 = endNoise3D(vec3(eyeDir * 3.0 - eyeR * 10.0 + time * 0.18, 57.0));
float tn3 = endNoise3D(vec3(eyeDir * 7.0 + eyeR * 20.0 + time * 0.1, 3.0));

float tendrils = tn1 * 0.5 + tn2 * 0.3 + tn3 * 0.2;
tendrils = smoothstep(0.45, 0.56, tendrils);

float tendrilColorMix = smoothstep(0.35, 0.65, tn1);
vec3 tendrilColor = mix(vec3(0.4, 0.25, 0.6), warmColor, tendrilColorMix);

result += tendrilColor * tendrils * irisMask * eyeMask * 1.8;

float innerRingR = irisInner + 0.02;
float innerRingDist = abs(eyeR - innerRingR);
float innerRing = smoothstep(0.04, 0.005, innerRingDist);
result += warmColor * 0.5 * innerRing * eyeMask;

float focusCycle = mod(time, END_EVENT_CYCLE);
float eyePhaseStart = END_EVENT_CYCLE - 22.0;
float eyeLocalTime = focusCycle - eyePhaseStart;

float focusT = 0.0;

if (eyeLocalTime > 3.0 && eyeLocalTime < 3.3) {
focusT = smoothstep(3.0, 3.3, eyeLocalTime);
} else if (eyeLocalTime >= 3.3 && eyeLocalTime < 4.5) {
focusT = 1.0;
} else if (eyeLocalTime >= 4.5 && eyeLocalTime < 5.5) {
focusT = 1.0 - smoothstep(4.5, 5.5, eyeLocalTime);
}

if (eyeLocalTime > 8.0 && eyeLocalTime < 8.25) {
focusT = smoothstep(8.0, 8.25, eyeLocalTime);
} else if (eyeLocalTime >= 8.25 && eyeLocalTime < 9.2) {
focusT = 1.0;
} else if (eyeLocalTime >= 9.2 && eyeLocalTime < 10.0) {
focusT = 1.0 - smoothstep(9.2, 10.0, eyeLocalTime);
}
float pupilSize = mix(0.14, 0.06, focusT);
float hotSize = mix(0.05, 0.02, focusT);

float pupilGlow = smoothstep(pupilSize, 0.0, eyeR);
pupilGlow = pupilGlow * pupilGlow;
result += vec3(1.0) * pupilGlow * eyeMask * 2.0;

float hotDot = smoothstep(hotSize, 0.0, eyeR);
result += vec3(1.0) * hotDot * eyeMask * 3.0;
}

vec3 bloomColor = vec3(END_EVENT_EYE_IRIS_R, END_EVENT_EYE_IRIS_G, END_EVENT_EYE_IRIS_B);
float bloomOpen = smoothstep(0.0, 0.15, eyeOpen);

float outerBloom = smoothstep(2.5, 0.8, eyeR);
outerBloom = outerBloom * outerBloom * 0.3;
result += bloomColor * outerBloom * bloomOpen;

float pupilBloom = smoothstep(0.6, 0.0, eyeR);
pupilBloom = pupilBloom * pupilBloom * pupilBloom * 0.5;
result += vec3(1.0) * pupilBloom * bloomOpen;

float irisBloom = smoothstep(1.8, 0.3, eyeR) * smoothstep(0.0, 0.15, eyeR);
irisBloom *= 0.15;
result += bloomColor * 0.6 * irisBloom * bloomOpen;
}
#endif

result *= END_VORTEX_INTENSITY * horizonFade;

return result;
}
#endif
