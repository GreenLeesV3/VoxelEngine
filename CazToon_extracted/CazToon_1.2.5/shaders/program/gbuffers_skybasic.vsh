out vec3 viewPos;
out vec4 starColor;

void main() {
gl_Position = ftransform();

viewPos = (mat3(gl_ModelViewMatrix) * gl_Vertex.xyz);

starColor = gl_Color;
}
