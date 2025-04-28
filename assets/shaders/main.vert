#version 460

layout(binding = 0) readonly uniform UniformBuffer {
    mat4 view;
    mat4 projection;
    mat4 viewProjection;
    uint lightCount;
} uniformBuffer;

struct InstanceInfo {
    mat4 model;
    uint boneOffset;
};

layout(binding = 1) readonly buffer InstanceBuffer {
    InstanceInfo[] instanceInfo;
} instanceBuffer;

struct Light {
    vec4 position;
    vec4 colourIntensity;
    float near;
    float far;
};

layout(binding = 3) readonly buffer TransformBuffer {
    mat4[] vertexTransforms;
} transformBuffer;

layout(push_constant) uniform PushConstants {
	float ambientLight;
    uint vertexOffset;
    uint albedoTextureIndex;
    uint normalTextureIndex;
} pushConstants;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in uvec4 inBones;
layout(location = 4) in vec4 inWeights;

layout(location = 0) out vec3 outPosition;
layout(location = 1) out vec2 outUV;
layout(location = 2) out vec3 outNormal;

void main() {
    mat4 vertexTransform = transformBuffer.vertexTransforms[gl_VertexIndex - gl_BaseVertex + pushConstants.vertexOffset];

    vec4 position = vertexTransform * vec4(inPosition, 1.0);
    gl_Position = uniformBuffer.viewProjection * position;

    outPosition = position.xyz / position.w;
    outUV = inUV;
    outNormal = normalize(mat3(vertexTransform) * inNormal);
}
