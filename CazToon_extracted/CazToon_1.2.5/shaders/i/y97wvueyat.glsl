#ifdef WATER_DEBUG_COLORS_ENABLED
color.rgb = vec3(0.0, 1.0, 0.0);
color.a = 0.35;
#else

float sideTexBright = dot(color.rgb, vec3(0.299, 0.587, 0.114));
color.rgb = waterLitColor(color.rgb, sunAngle, skylight, bl_water);

float sideTextureSpec = smoothstep(0.08, 0.42, sideTexBright);
waterTextureSpec = max(waterTextureSpec, sideTextureSpec * 0.75);
float sideLowSkySheen = 1.0 - smoothstep(3.0 / 15.0, 10.0 / 15.0, skylight);
float sideBlockSheen = smoothstep(1.0 / 15.0, 12.0 / 15.0, bl_water);
vec3 sideSheenLight = vec3(0.05) * (0.35 + sideLowSkySheen * 0.55 + sideBlockSheen * 0.45);
#ifdef LPV_ENABLED
{
vec3 lpvSideLight = sampleLpvLight(worldPos, waterWorldNormal, sideBlockSheen) * BLOCKLIGHT_BRIGHTNESS;
sideSheenLight += lpvSideLight * (1.0 + sideLowSkySheen);
}
#endif
color.rgb += sideSheenLight * sideTextureSpec * (0.30 + sideLowSkySheen * 0.55);

float sideWaveNoise = 0.5;
#ifdef WATER_WAVES_ENABLED
{
#define WF_H3(p) fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453)
float fallSpeed = frameTimeCounter * 8.0;

vec3 wPos = worldPos * vec3(1.5, 0.4, 1.5);
wPos.y += frameTimeCounter * 4.0;
vec3 _wi = floor(wPos); vec3 _wf = fract(wPos);
float _wx = smoothstep(0.0,1.0,_wf.x), _wy = smoothstep(0.0,1.0,_wf.y), _wz = smoothstep(0.0,1.0,_wf.z);
float wn = mix(mix(mix(WF_H3(_wi),WF_H3(_wi+vec3(1,0,0)),_wx),mix(WF_H3(_wi+vec3(0,1,0)),WF_H3(_wi+vec3(1,1,0)),_wx),_wy),
mix(mix(WF_H3(_wi+vec3(0,0,1)),WF_H3(_wi+vec3(1,0,1)),_wx),mix(WF_H3(_wi+vec3(0,1,1)),WF_H3(_wi+vec3(1,1,1)),_wx),_wy),_wz);

float refrShift = wn * 0.2;
color.rgb *= 1.0 + refrShift;
sideWaveNoise = wn;

vec3 L = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
vec3 V = normalize(cameraPosition - worldPos);
vec3 sideN = waterWorldNormal;
vec3 halfDir = normalize(V + L);
float NdotH = max(dot(sideN, halfDir), 0.0);
vec4 tod = waterTimeOfDay(sunAngle);
float dayFactor = tod.x + tod.y * 0.7 + tod.z * 0.15;
float sunHeight = abs(L.y);
float noonDim = 1.0 - smoothstep(0.5, 0.9, sunHeight) * 0.7;
float sunsetBoost = 1.0 + tod.y * 2.0;
float core = pow(NdotH, 128.0) * 0.8;
float spread = pow(NdotH, 8.0) * 0.5;
float sunGlow = (core + spread) * dayFactor * skylight * noonDim * sunsetBoost;
vec3 glowColor = mix(vec3(1.0, 0.95, 0.85), vec3(SUNSET_HORIZON_R, SUNSET_HORIZON_G, SUNSET_HORIZON_B), tod.y);
float glowAmt = min(sunGlow * WATER_SPECULAR_INTENSITY, 0.8);
glowAmt *= shadow;
color.rgb = mix(color.rgb, glowColor * 1.2, glowAmt);
color.a = max(color.a, sunGlow * 0.5 * shadow);

#undef WF_H3
}
#endif

waterReflData = vec4(sideWaveNoise, 0.95, waterWorldNormal.x * 0.5 + 0.5, waterWorldNormal.y * 0.5 + 0.5);
#endif
