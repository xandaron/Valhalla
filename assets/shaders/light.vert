#version 460

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
    uint faceIndex;
} pushConstants;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in uvec4 inBones;
layout(location = 4) in vec4 inWeights;

layout(location = 0) out float outColour;

#define PI 3.14159265358979323846264338327950288
#define tanHalfFOVReciprocal (1.0 / tan(PI / 4.0))

// TODO: Might be better as a compute shader using a cubeSampler.
void main() {
    const Light light = lightBuffer.lights[pushConstants.lightIndex];
    mat4 projection = mat4(
            vec4(tanHalfFOVReciprocal, 0.0, 0.0, 0.0),
            vec4(0.0, -tanHalfFOVReciprocal, 0.0, 0.0),
            vec4(0.0, 0.0, light.far / (light.far - light.near), 1.0),
            vec4(0.0, 0.0, -(light.far * light.near) / (light.far - light.near), 0.0)
        );

    mat4 view;
    switch (pushConstants.faceIndex) {
        case 0: // POSITIVE_X
        view = mat4(
                vec4(0, 0, 1, 0),
                vec4(0, 1, 0, 0),
                vec4(-1, 0, 0, 0),
                vec4(light.position.z, -light.position.yx, 1.0)
            );
        break;
        case 1: // NEGATIVE_X
        view = mat4(
                vec4(0, 0, -1, 0),
                vec4(0, 1, 0, 0),
                vec4(1, 0, 0, 0),
                vec4(-light.position.zy, light.position.x, 1.0)

            );
        break;
        case 2: // POSITIVE_Y
        view = mat4(
                vec4(1, 0, 0, 0),
                vec4(0, 0, 1, 0),
                vec4(0, -1, 0, 0),
                vec4(-light.position.x, light.position.z, -light.position.y, 1.0)
            );
        break;
        case 3: // NEGATIVE_Y
        view = mat4(
                vec4(1, 0, 0, 0),
                vec4(0, 0, -1, 0),
                vec4(0, 1, 0, 0),
                vec4(-light.position.xz, light.position.y, 1.0)
            );
        break;
        case 4: // POSITIVE_Z
        view = mat4(
                vec4(1.0, 0.0, 0.0, 0.0),
                vec4(0.0, 1.0, 0.0, 0.0),
                vec4(0.0, 0.0, 1.0, 0.0),
                vec4(-light.position.xyz, 1.0)
            );
        break;
        case 5: // NEGATIVE_Z
        view = mat4(
                vec4(-1.0, 0.0, 0.0, 0.0),
                vec4(0.0, 1.0, 0.0, 0.0),
                vec4(0.0, 0.0, -1.0, 0.0),
                vec4(light.position.x, -light.position.y, light.position.z, 1.0)
            );
        break;
    }
    mat4 vertexTransform = transformBuffer.vertexTransforms[gl_VertexIndex - gl_BaseVertex + pushConstants.vertexOffset];

    vec4 vertexPosition = vertexTransform * vec4(inPosition, 1.0);
    gl_Position = projection * view * vertexPosition;
    vertexPosition.xyz /= vertexPosition.w;
    outColour = length(vertexPosition.xyz - light.position.xyz);
}
