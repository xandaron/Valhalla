#version 460

#extension GL_EXT_multiview : enable

struct InstanceInfo {
    mat4 model;
    uint boneOffset;
    float samplerOffset;
};

layout(binding = 0) readonly buffer InstanceBuffer {
    InstanceInfo[] instanceInfo;
} instanceBuffer;

struct Light {
    vec4 position;
    vec4 colourIntensity;
    float near;
    float far;
};

layout(binding = 1) readonly buffer LightBuffer {
    Light[] lights;
} lightBuffer;

layout(binding = 2) readonly buffer TransformBuffer {
    mat4[] vertexTransforms;
} transformBuffer;

layout(push_constant) uniform PushConstants {
    uint vertexOffset;
    uint lightIndex;
} pushConstants;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in uvec4 inBones;
layout(location = 4) in vec4 inWeights;

layout(location = 0) out float outColour;

#define PI 3.14159265358979323846264338327950288
#define tanHalfFOVReciprocal (1.0 / tan(PI / 4.0)) // 1
#define projection mat4(vec4(tanHalfFOVReciprocal, 0, 0, 0), vec4(0, tanHalfFOVReciprocal, 0, 0), vec4(0, 0, light.far / (light.near - light.far), -1), vec4(0, 0, -(light.far * light.near)/(light.far - light.near), 0))

#define positiveX (projection * mat4(vec4(0, 0, -1, 0), vec4(0, -1, 0, 0), vec4(-1, 0, 0, 0), vec4(light.position.z, light.position.y, light.position.x, 1)))
#define negativeX (projection * mat4(vec4(0, 0, 1, 0), vec4(0, -1, 0, 0), vec4(1, 0, 0, 0), vec4(-light.position.z, light.position.y, -light.position.x, 1)))
#define positiveY (projection * mat4(vec4(1, 0, 0, 0), vec4(0, 0, -1, 0), vec4(0, 1, 0, 0), vec4(-light.position.x, -light.position.z, light.position.y, 1)))
#define negativeY (projection * mat4(vec4(1, 0, 0, 0), vec4(0, 0, 1, 0), vec4(0, -1, 0, 0), vec4(-light.position.x, light.position.z, -light.position.y, 1)))
#define positiveZ (projection * mat4(vec4(1, 0, 0, 0), vec4(0, -1, 0, 0), vec4(0, 0, -1, 0), vec4(-light.position.x, light.position.y, light.position.z, 1)))
#define negativeZ (projection * mat4(vec4(-1, 0, 0, 0), vec4(0, -1, 0, 0), vec4(0, 0, 1, 0), vec4(light.position.x, light.position.y, -light.position.z, 1)))

void main() {
    const Light light = lightBuffer.lights[pushConstants.lightIndex];

    const vec4 vertexPosition = transformBuffer.vertexTransforms[gl_VertexIndex - gl_BaseVertex + pushConstants.vertexOffset] * vec4(inPosition, 1.0);

    // +x = 0, -x = 1, +y = 2, -y = 3, +z = 4, -z = 5
    switch(gl_ViewIndex) {
        case 0:
            gl_Position = positiveX * vertexPosition;
            break;
        case 1:
            gl_Position = negativeX * vertexPosition;
            break;
        case 2:
            gl_Position = positiveY * vertexPosition;
            break;
        case 3:
            gl_Position = negativeY * vertexPosition;
            break;
        case 4:
            gl_Position = positiveZ * vertexPosition;
            break;
        case 5:
            gl_Position = negativeZ * vertexPosition;
            break;
    }

    const vec3 relativePosition = (vertexPosition.xyz / vertexPosition.w) - light.position.xyz;
    outColour = dot(relativePosition, relativePosition);
}
