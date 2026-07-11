float linearizeDepth(float depth) {
return (near * far) / (depth * (near - far) + far);
}

float linearizeDepthDH(float depth) {
return (dhNearPlane * dhFarPlane) / (depth * (dhNearPlane - dhFarPlane) + dhFarPlane);
}

bool hasValidDHDepth(float depth) {
return depth > 0.00001 && depth < 0.9999;
}
