#version 450

layout(binding = 0) readonly uniform UniformBuffer {
	mat4 view;
	mat4 projection;
	mat4 viewProjection;
    uint lightCount;
} uniformBuffer;

struct InstanceInfo {
    mat4 model;
    uint boneOffset;
    float albedoSamplerOffset;
    float normalSamplerOffset;
};

layout(binding = 1) readonly buffer InstanceBuffer {
    InstanceInfo[] instanceInfo;
} instanceBuffer;

layout(binding = 2) readonly buffer BoneBuffer {
	mat4[] boneTransforms;
} boneBuffer;

struct Light {
    vec4 position;
    vec4 colourIntensity;
    float near;
    float far;
};

layout(binding = 3) readonly buffer LightBuffer {
    Light[] lights;
} lightBuffer;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in uvec4 inBones;
layout(location = 4) in vec4 inWeights;

layout(location = 0) out vec4 outPosition;
layout(location = 1) out vec2 outUV;
layout(location = 2) out vec3 outNormal;
layout(location = 3) out float outAlbedoIndex;
layout(location = 4) out float outNormalIndex;

void main() {
    // This computation is being done 6 * lightCount + 1 times per render.
    // This should be done as part of a precompute step ---------------------------------------
    mat4 boneTransform = mat4(0.0);
    uint boneOffset = instanceBuffer.instanceInfo[gl_InstanceIndex].boneOffset;
    boneTransform += boneBuffer.boneTransforms[boneOffset + inBones[0]] * inWeights[0];
    boneTransform += boneBuffer.boneTransforms[boneOffset + inBones[1]] * inWeights[1];
    boneTransform += boneBuffer.boneTransforms[boneOffset + inBones[2]] * inWeights[2];
    boneTransform += boneBuffer.boneTransforms[boneOffset + inBones[3]] * inWeights[3];
    mat4 vertexTransform = instanceBuffer.instanceInfo[gl_InstanceIndex].model * boneTransform;
    // ----------------------------------------------------------------------------------------

    outPosition = vertexTransform * vec4(inPosition, 1.0);
    gl_Position = uniformBuffer.viewProjection * outPosition;

    outUV = inUV;
    outNormal = normalize(mat3(vertexTransform) * inNormal);
    outAlbedoIndex = instanceBuffer.instanceInfo[gl_InstanceIndex].albedoSamplerOffset;
    outNormalIndex = instanceBuffer.instanceInfo[gl_InstanceIndex].normalSamplerOffset;
}