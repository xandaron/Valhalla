import "Vertex.slang";
import "Buffers.slang";

struct PushConstants
{
    uint vertexOffset;
    uint layerIndex;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

#define PI 3.14159265358979323846264338327950288
#define tanHalfFOVReciprocal (1.0 / tan(PI / 4.0))

float4x4 getProjection(Light light)
{
    return float4x4(
        float4(tanHalfFOVReciprocal, 0, 0, 0),
        float4(0, tanHalfFOVReciprocal, 0, 0),
        float4(0, 0, light.far / (light.near - light.far), -1),
        float4(0, 0, -(light.far * light.near) / (light.far - light.near), 0));
}

float4x4 getView(Light light, uint face)
{
    // Cube map face view matrices
    switch (face)
    {
    case 0: // +X
        return mul(getProjection(light), float4x4(
                                             float4(0, 0, -1, 0),
                                             float4(0, -1, 0, 0),
                                             float4(-1, 0, 0, 0),
                                             float4(light.position.z, light.position.y, light.position.x, 1)));
    case 1: // -X
        return mul(getProjection(light), float4x4(
                                             float4(0, 0, 1, 0),
                                             float4(0, -1, 0, 0),
                                             float4(1, 0, 0, 0),
                                             float4(-light.position.z, light.position.y, -light.position.x, 1)));
    case 2: // +Y
        return mul(getProjection(light), float4x4(
                                             float4(1, 0, 0, 0),
                                             float4(0, 0, -1, 0),
                                             float4(0, 1, 0, 0),
                                             float4(-light.position.x, -light.position.z, light.position.y, 1)));
    case 3: // -Y
        return mul(getProjection(light), float4x4(
                                             float4(1, 0, 0, 0),
                                             float4(0, 0, 1, 0),
                                             float4(0, -1, 0, 0),
                                             float4(-light.position.x, light.position.z, -light.position.y, 1)));
    case 4: // +Z
        return mul(getProjection(light), float4x4(
                                             float4(1, 0, 0, 0),
                                             float4(0, -1, 0, 0),
                                             float4(0, 0, -1, 0),
                                             float4(-light.position.x, light.position.y, light.position.z, 1)));
    case 5: // -Z
        return mul(getProjection(light), float4x4(
                                             float4(-1, 0, 0, 0),
                                             float4(0, -1, 0, 0),
                                             float4(0, 0, 1, 0),
                                             float4(light.position.x, light.position.y, -light.position.z, 1)));
    }
    return float4x4(1.0); // Fallback, should never happen
}

struct VertOut
{
    float4 position : SV_Position;
    uint layer : SV_ViewportArrayIndex;
    float depth;
};

[shader("vertex")]
VertOut vert(Vertex input, uint vertexID: SV_VertexID)
{
    VertOut output;

    Light light = lightBuffer[pushConstants.layerIndex / 6];
    float4 vertexPosition = mul(transformBufferReadOnly[vertexID + pushConstants.vertexOffset], float4(input.position, 1.0));

    uint face = pushConstants.layerIndex % 6;
    float4x4 viewProj = getView(light, face);

    output.position = mul(viewProj, vertexPosition);
    output.layer = pushConstants.layerIndex;

    float3 relativePosition = (vertexPosition.xyz / vertexPosition.w) - light.position.xyz;
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
