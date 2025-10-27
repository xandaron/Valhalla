import "Vertex.slang";
import "Buffers.slang";

struct PushConstants
{
    uint instance;
    uint instanceCount;
    uint vertexCount;
    uint vertexOffset;
    uint transformOffset;
};

[[vk::push_constant]]
PushConstants pushConstants;

[shader("compute")]
[numthreads(64, 1, 1)]
void comp(uint3 dispatchThreadID: SV_DispatchThreadID)
{
    if (dispatchThreadID.x >= pushConstants.vertexCount)
    {
        return;
    }

    const Vertex vertex = vertexBuffer[pushConstants.vertexOffset + dispatchThreadID.x];
    for (int i = 0; i < pushConstants.instanceCount; i++)
    {
        const uint instanceIndex = pushConstants.instance + i;
        const uint boneOffset = instanceBuffer[instanceIndex].boneOffset;

        float4x4 boneTransform = float4x4(0.0);
        for (uint j = 0; j < 4; j++)
        {
            boneTransform += vertex.weights[j] * boneBuffer[boneOffset + vertex.bones[i]];
        }

        transformBufferRW[pushConstants.transformOffset + dispatchThreadID.x + i * pushConstants.vertexCount] = mul(instanceBuffer[instanceIndex].model, boneTransform);
    }
}
