#ifdef METALNESS_ENABLED

vec3 getEnvironmentColor(vec3 reflectDir, float sunAngle) {
TimeWeightsSimple ts = getTimeWeightsSimple(sunAngle);

float upAmount = reflectDir.y * 0.5 + 0.5;
vec3 dayColor = mix(vec3(0.6, 0.7, 0.8), vec3(0.4, 0.6, 1.0), upAmount);
vec3 twilightColor = mix(vec3(0.4, 0.3, 0.3), vec3(1.0, 0.6, 0.4), upAmount);
vec3 nightColor = mix(vec3(0.02, 0.02, 0.04), vec3(0.1, 0.15, 0.25), upAmount);

return dayColor * ts.day + twilightColor * ts.twilight + nightColor * ts.night;
}

float fresnelSchlick(float cosTheta, float F0) {
float ct = max(cosTheta, 0.05);
return F0 + (1.0 - F0) * pow(1.0 - ct, 5.0);
}

float distributionGGX(float NdotH, float roughness) {
float a = roughness * roughness;
float a2 = a * a;
float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
return a2 / (3.14159265 * denom * denom);
}

vec3 getEndEnvironmentColor(vec3 reflectDir) {
float upAmount = reflectDir.y * 0.5 + 0.5;
vec3 downColor = vec3(0.05, 0.02, 0.10);
vec3 upColor = vec3(0.25, 0.10, 0.45);
return mix(downColor, upColor, upAmount);
}

float getMetalTextureResponse(vec3 rawColor) {
float lum = dot(rawColor, vec3(0.299, 0.587, 0.114));
return mix(0.35, 1.20, smoothstep(0.20, 0.78, lum));
}

vec3 getMetalLocalLightSpec(vec3 rawColor, vec3 localLight, float textureResponse, float intensity) {
float localLuma = dot(localLight, vec3(0.299, 0.587, 0.114));
if (localLuma <= 0.0005) return vec3(0.0);

vec3 localHue = clamp(localLight / max(localLuma, 0.0001), vec3(0.0), vec3(4.0));
float lightResponse = localLuma * textureResponse * intensity;
return rawColor * localHue * lightResponse;
}

vec3 applyMetalnessEnd(vec3 baseColor, vec3 viewDir, vec3 surfaceNormal, vec3 lightDir, float metalType, vec3 wPos, float time, vec3 rawColor, float shadowLit, float blocklight, vec3 localLight) {
bool isMetal = (metalType > 0.5 && metalType < 1.5);
bool isGem = (metalType > 1.5);

float pixelBright = getMetalTextureResponse(rawColor);

vec3 N = normalize(surfaceNormal);
vec3 L = normalize(lightDir);
vec3 V = normalize(-viewDir);
vec3 H = normalize(V + L);
vec3 R = reflect(-V, N);

float NdotV = max(dot(N, V), 0.001);
float NdotH = max(dot(N, H), 0.0);
float NdotL = max(dot(N, L), 0.0);

float specExponent = isMetal ? 16.0 : 32.0;
float endSpec = pow(NdotH, specExponent);
vec3 specular = rawColor * endSpec * pixelBright * METALNESS_INTENSITY * 5.0;

vec3 blocklightSpec = getMetalLocalLightSpec(rawColor, localLight, pixelBright, METALNESS_INTENSITY) * 0.6;

return baseColor + specular + blocklightSpec;
}

vec3 applyMetalness(vec3 baseColor, vec3 viewDir, vec3 surfaceNormal, vec3 lightDir, float sunAngle, float metalType, vec3 wPos, vec3 rawColor, float shadowLit, float blocklight, vec3 localLight) {
bool isMetal = (metalType > 0.5 && metalType < 1.5);
bool isGem = (metalType > 1.5);

float pixelBright = getMetalTextureResponse(rawColor);

vec3 N = normalize(surfaceNormal);
vec3 L = normalize(lightDir);
vec3 V = normalize(-viewDir);
vec3 H = normalize(V + L);
vec3 R = reflect(-V, N);

float NdotV = max(dot(N, V), 0.001);
float NdotH = max(dot(N, H), 0.0);
float NdotL = max(dot(N, L), 0.0);

TimeWeightsSimple metalTS = getTimeWeightsSimple(sunAngle);
float dayStrength = metalTS.day + metalTS.twilight * 0.5;
float nightDim = mix(0.08, 1.0, dayStrength);

float specExponent = isMetal ? 16.0 : 8.0;
float sunSpec = pow(NdotH, specExponent);
float specMult = isMetal ? 4.0 : 1.5;
vec3 specular = rawColor * sunSpec * pixelBright * METALNESS_INTENSITY * specMult * shadowLit * nightDim;

vec3 sparkle = vec3(0.0);

vec3 blocklightSpec = getMetalLocalLightSpec(rawColor, localLight, pixelBright, METALNESS_INTENSITY) * 0.75;

return baseColor + specular + blocklightSpec;
}
#endif
