vec2 neighbourOffsets[8] = vec2[8](
vec2( 0.0, -1.0),
vec2(-1.0,  0.0),
vec2( 1.0,  0.0),
vec2( 0.0,  1.0),
vec2(-1.0, -1.0),
vec2( 1.0, -1.0),
vec2(-1.0,  1.0),
vec2( 1.0,  1.0)
);

vec2 Reprojection(vec3 pos) {
pos = pos * 2.0 - 1.0;

vec4 viewPosPrev = gbufferProjectionInverse * vec4(pos, 1.0);
viewPosPrev /= viewPosPrev.w;
viewPosPrev = gbufferModelViewInverse * viewPosPrev;

vec3 cameraOffset = cameraPosition - previousCameraPosition;

cameraOffset *= float(pos.z > 0.56);

vec4 previousPosition = viewPosPrev + vec4(cameraOffset, 0.0);
previousPosition = gbufferPreviousModelView * previousPosition;
previousPosition = gbufferPreviousProjection * previousPosition;
return previousPosition.xy / previousPosition.w * 0.5 + 0.5;
}

vec3 textureCatmullRom(sampler2D tex, vec2 uv, vec2 res) {
vec2 position = uv * res;
vec2 centerPosition = floor(position - 0.5) + 0.5;
vec2 f = position - centerPosition;
vec2 f2 = f * f;
vec2 f3 = f * f2;

float c = 0.7;
vec2 w0 =        -c  * f3 +  2.0 * c         * f2 - c * f;
vec2 w1 =  (2.0 - c) * f3 - (3.0 - c)        * f2         + 1.0;
vec2 w2 = -(2.0 - c) * f3 + (3.0 -  2.0 * c) * f2 + c * f;
vec2 w3 =         c  * f3 -                c  * f2;

vec2 w12 = w1 + w2;
vec2 tc12 = (centerPosition + w2 / w12) / res;
vec2 tc0 = (centerPosition - 1.0) / res;
vec2 tc3 = (centerPosition + 2.0) / res;

vec4 color = vec4(textureLod(tex, vec2(tc12.x, tc0.y ), 0).rgb, 1.0) * (w12.x * w0.y ) +
vec4(textureLod(tex, vec2(tc0.x,  tc12.y), 0).rgb, 1.0) * (w0.x  * w12.y) +
vec4(textureLod(tex, vec2(tc12.x, tc12.y), 0).rgb, 1.0) * (w12.x * w12.y) +
vec4(textureLod(tex, vec2(tc3.x,  tc12.y), 0).rgb, 1.0) * (w3.x  * w12.y) +
vec4(textureLod(tex, vec2(tc12.x, tc3.y ), 0).rgb, 1.0) * (w12.x * w3.y );
return color.rgb / color.a;
}

vec3 RGBToYCoCg(vec3 col) {
return vec3(
col.r * 0.25 + col.g * 0.5 + col.b * 0.25,
col.r * 0.5 - col.b * 0.5,
col.r * -0.25 + col.g * 0.5 + col.b * -0.25
);
}

vec3 YCoCgToRGB(vec3 col) {
float n = col.r - col.b;
return vec3(n + col.g, col.r + col.b, n - col.g);
}

vec3 ClipAABB(vec3 q, vec3 aabb_min, vec3 aabb_max) {
vec3 p_clip = 0.5 * (aabb_max + aabb_min);
vec3 e_clip = 0.5 * (aabb_max - aabb_min) + 0.00000001;

vec3 v_clip = q - p_clip;
vec3 v_unit = v_clip / e_clip;
vec3 a_unit = abs(v_unit);
float ma_unit = max(a_unit.x, max(a_unit.y, a_unit.z));

if (ma_unit > 1.0)
return p_clip + v_clip / ma_unit;
else
return q;
}

vec3 NeighbourhoodClipping(sampler2D currentTex, vec2 uv, vec3 color, vec3 tempColor, vec2 invView) {
vec3 minclr = RGBToYCoCg(color);
vec3 maxclr = minclr;

for (int i = 0; i < 8; i++) {
vec3 clr = textureLod(currentTex, uv + neighbourOffsets[i] * invView, 0.0).rgb;
clr = RGBToYCoCg(clr);
minclr = min(minclr, clr);
maxclr = max(maxclr, clr);
}

tempColor = RGBToYCoCg(tempColor);
tempColor = ClipAABB(tempColor, minclr, maxclr);
return YCoCgToRGB(tempColor);
}

void TemporalAA(inout vec3 color, sampler2D currentTex, sampler2D historyTex, vec2 texCoord) {
vec2 view = vec2(viewWidth, viewHeight);
float depth = texture(depthtex1, texCoord).r;

vec3 coord = vec3(texCoord, depth);
vec2 prvCoord = Reprojection(coord);

vec3 tempColor = textureCatmullRom(historyTex, prvCoord, view);

if (tempColor == vec3(0.0)) {
return;
}

tempColor = NeighbourhoodClipping(currentTex, texCoord, color, tempColor, 1.0 / view);

vec2 velocity = (texCoord - prvCoord) * view;
float blendFactor = float(
prvCoord.x > 0.0 && prvCoord.x < 1.0 &&
prvCoord.y > 0.0 && prvCoord.y < 1.0
);
blendFactor *= exp(-length(velocity)) * 0.2 + 0.7;

color = mix(color, tempColor, blendFactor);
}
