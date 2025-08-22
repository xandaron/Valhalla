import "../../src/shaders/Vertex.slang";
import "../../src/shaders/Light.slang";
import "../../src/shaders/Buffers.slang";

struct PushConstants
{
    uint layerIndex;
    uint vertexOffset;
    uint vertexCount;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

#define PI 3.14159265358979323846264338327950288
#define tanHalfFOVReciprocal (1.0 / tan(PI / 4.0))

float4x4 projection(Light light) {
    return float4x4(
        float4(tanHalfFOVReciprocal, 0, 0, 0),
        float4(0, tanHalfFOVReciprocal, 0, 0),
        float4(0, 0, light.far / (light.near - light.far), -(light.far * light.near) / (light.far - light.near)),
        float4(0, 0, -1, 0),
    );
}

float4x4 view(Light light, uint face)
{
    switch (face)
    {
    case 0: // +X
        return float4x4(
            float4(0, 0, -1, light.position.z),
            float4(0, -1, 0, light.position.y),
            float4(-1, 0, 0, light.position.x),
            float4(0, 0, 0, 1)
        );
    case 1: // -X
        return float4x4(
            float4(0, 0, 1, -light.position.z),
            float4(0, -1, 0, light.position.y),
            float4(1, 0, 0, -light.position.x),
            float4(0, 0, 0, 1)
        );
    case 2: // +Y
        return float4x4(
            float4(1, 0, 0, -light.position.x),
            float4(0, 0, 1, -light.position.z),
            float4(0, -1, 0, light.position.y),
            float4(0, 0, 0, 1)
        );
    case 3: // -Y
        return float4x4(
            float4(1, 0, 0, -light.position.x),
            float4(0, 0, -1, light.position.z),
            float4(0, 1, 0, -light.position.y),
            float4(0, 0, 0, 1)
        );
    case 4: // +Z
        return float4x4(
            float4(1, 0, 0, -light.position.x),
            float4(0, -1, 0, light.position.y),
            float4(0, 0, -1, light.position.z),
            float4(0, 0, 0, 1)
        );
    case 5: // -Z
        return float4x4(
            float4(-1, 0, 0, light.position.x),
            float4(0, -1, 0, light.position.y),
            float4(0, 0, 1, -light.position.z),
            float4(0, 0, 0, 1)
        );
    }
    return float4x4(1.0); // Fallback, should never happen
}

struct VertOut
{
    float4 position : SV_Position;
    uint layer : SV_RenderTargetArrayIndex;
    float depth;
};

[shader("vertex")]
VertOut vert(Vertex input, uint vertexID: SV_VertexID, uint instanceID: SV_InstanceID)
{
    VertOut output;

    const Light light = lightBuffer[pushConstants.layerIndex / 6];
    const uint idx = vertexID + pushConstants.vertexOffset + instanceID * pushConstants.vertexCount;
    const float4x4 vertexTransform = transformBufferRO[idx];
    const float4 vertexPosition = mul(vertexTransform, float4(input.position, 1.0));

    const uint face = pushConstants.layerIndex % 6;
    const float4x4 viewProj = mul(projection(light), view(light, face));

    output.position = mul(viewProj, vertexPosition);
    output.layer = pushConstants.layerIndex;

    const float3 relativePosition = (vertexPosition.xyz / vertexPosition.w) - light.position.xyz;
    output.depth = dot(relativePosition, relativePosition);

    return output;
}

struct FragOut
{
    float depth : SV_Target0;
};

[shader("fragment")]
FragOut frag(VertOut input)
{
    FragOut output;
    output.depth = input.depth;
    return output;
}
