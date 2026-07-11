/* RENDERTARGETS: 0 */

in vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform float viewWidth;
uniform float viewHeight;

void main() {
vec4 sceneData = texture(colortex0, texcoord);
vec3 color = sceneData.rgb;

vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);

const float P_UP = 100.0 / 255.0;
const float P_X  = 150.0 / 255.0;
const float P_Z  = 200.0 / 255.0;
const float P_TOL = 2.0 / 255.0;

float thisCode = texture(colortex1, texcoord).a;
bool thisIsPortal = (abs(thisCode - P_UP) < P_TOL) ||
(abs(thisCode - P_X)  < P_TOL) ||
(abs(thisCode - P_Z)  < P_TOL);

if (thisIsPortal) {
gl_FragData[0] = sceneData;
return;
}

vec3 glow = vec3(0.0);
float glowWeight = 0.0;

const float GLOW_RADIUS = 40.0;
const int RING_SAMPLES = 12;
const int RINGS = 5;

for (int r = 1; r <= RINGS; r++) {
float radius = GLOW_RADIUS * float(r) / float(RINGS);
float falloff = 1.0 - float(r - 1) / float(RINGS);
falloff = falloff * falloff * falloff;

for (int s = 0; s < RING_SAMPLES; s++) {
float angle = float(s) * 6.2831853 / float(RING_SAMPLES);
vec2 offset = vec2(cos(angle), sin(angle)) * radius;
vec2 sampleUV = texcoord + offset * pixelSize;

if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) continue;

float sampleCode = texture(colortex1, sampleUV).a;
bool sampleIsPortal = (abs(sampleCode - P_UP) < P_TOL) ||
(abs(sampleCode - P_X)  < P_TOL) ||
(abs(sampleCode - P_Z)  < P_TOL);

if (sampleIsPortal) {
vec3 portalColor = texture(colortex0, sampleUV).rgb;
glow += portalColor * falloff;
glowWeight += falloff;
}
}
}

if (glowWeight > 0.01) {
glow /= glowWeight;
float intensity = min(glowWeight * 0.08, 0.6);
color += glow * intensity;
}

gl_FragData[0] = vec4(color, sceneData.a);
}
