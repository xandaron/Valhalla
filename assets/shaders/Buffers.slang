import "Vertex.slang";

[[vk::binding(0, 0)]]
StructuredBuffer<Vertex> vertexBuffer;

struct UniformData
{
    float4x4 view;
    float4x4 projection;
    float4x4 viewProjection;
    uint lightCount;
};

[[vk::binding(1, 0)]]
ConstantBuffer<UniformData> uniformBuffer;

struct InstanceInfo
{
    float4x4 model;
    uint boneOffset;
};

[[vk::binding(2, 0)]]
StructuredBuffer<InstanceInfo> instanceBuffer;

[[vk::binding(3, 0)]]
StructuredBuffer<float4x4> boneBuffer;

// Read-only version for vertex shader
[[vk::binding(4, 0)]]
StructuredBuffer<float4x4> transformBufferReadOnly;

// Read-write version for compute shader
[[vk::binding(4, 0)]]
RWStructuredBuffer<float4x4> transformBufferReadWrite;

struct Light
{
    float4 position;
    float4 colourIntensity;
    float near;
    float far;
};

[[vk::binding(5, 0)]]
StructuredBuffer<Light> lightBuffer;