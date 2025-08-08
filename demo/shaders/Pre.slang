import "../../src/shaders/Vertex.slang";
import "../../src/shaders/Buffers.slang";

struct PushConstants {
    uint instance;
    uint vertexCount;
    uint vertexOffset;
    uint transformOffset;
};

[[vk::push_constant]] PushConstants pushConstants;

[shader("compute")]
[numthreads(64, 1, 1)]
void comp(uint3 dispatchThreadID : SV_DispatchThreadID)
{
    if (dispatchThreadID.x >= pushConstants.vertexCount) {
        return;
    }

    const Vertex vertex = vertexBuffer[pushConstants.vertexOffset + dispatchThreadID.x];
    const uint boneOffset = instanceBuffer[pushConstants.instance].boneOffset;

    float4x4 boneTransform = float4x4(0.0);
    for (uint index = 0; index < 4; index++) {
        boneTransform += vertex.weights[index] * boneBuffer[boneOffset + vertex.bones[index]];
    }
    transformBufferRW[pushConstants.transformOffset + dispatchThreadID.x] = mul(instanceBuffer[pushConstants.instance].model, boneTransform);
}
