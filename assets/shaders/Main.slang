#include "Buffers.slang"
#include "Textures.slang"

struct PushConstants
{
    float ambientLight;
    uint vertexOffset;
    uint albedoTextureIndex;
    uint normalTextureIndex;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

struct VertOut
{
    float4 position : SV_Position;
    float3 worldPosition : POSITION;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    float3 bitangent : BITANGENT;
    float2 uv : TEXCOORD0;
};

[shader("vertex")]
VertOut vert(Vertex vertex, uint vertexID: SV_VertexID)
{
    VertOut output;

    const float4x4 vertexTransform = transformBuffer[vertexID + pushConstants.vertexOffset];
    const float4 worldPosition = mul(vertexTransform, float4(vertex.position, 1.0));
    output.position = mul(uniformBuffer.viewProjection, worldPosition);
    output.worldPosition = worldPosition.xyz / worldPosition.w;

    output.normal = normalize(mul((float3x3)vertexTransform, vertex.normal));
    output.tangent = normalize(mul((float3x3)vertexTransform, vertex.tangent));
    output.bitangent = normalize(mul((float3x3)vertexTransform, vertex.bitangent));

    output.uv = vertex.uv;

    return output;
}

struct FragOut
{
    float4 colour : SV_Target0;
};

[shader("fragment")]
FragOut frag(VertOut input)
{
    FragOut output;

    #define SAMPLES 20
    #define BIAS 0.015
    #define DISK_RADIUS 0.02

    // Sample offset directions for shadow sampling
    static const float3 sampleOffsetDirections[SAMPLES] = {
        float3(1, 0, 0), float3(-1, 0, 0),
        float3(0, 1, 0), float3(0, -1, 0),
        float3(0, 0, 1), float3(0, 0, -1),
        float3(1, 1, 0), float3(-1, -1, 0),
        float3(1, -1, 0), float3(-1, 1, 0),
        float3(1, 0, 1), float3(-1, 0, -1),
        float3(1, 0, -1), float3(-1, 0, 1),
        float3(0, 1, 1), float3(0, -1, -1),
        float3(0, 1, -1), float3(0, -1, 1),
        float3(1, 1, 1), float3(-1, -1, -1)
    };

    float3 cumulativeColour = { 0.0, 0.0, 0.0 };

    const float3 albedo = pow(albedoArray.Sample(float3(input.uv, pushConstants.albedoTextureIndex)).xyz, 1 / 2.2);

    const float3x3 TBN = transpose(float3x3(
        input.tangent,
        input.bitangent,
        input.normal
    ));
    const float3 normalSample = 2 * normalArray.Sample(float3(input.uv, pushConstants.normalTextureIndex)).xyz - 1;
    const float3 normal = normalize(mul(TBN, normalSample));

    for (uint index = 0; index < uniformBuffer.lightCount; index++)
    {
        const Light light = lightBuffer[index];

        const float3 relativePosition = light.position.xyz - input.worldPosition;
        const float lightSquaredDistance = dot(relativePosition, relativePosition);
        const float lightDistance = sqrt(lightSquaredDistance);
        const float3 negativeLightDirection = relativePosition / lightDistance;

        float shadow = 0.0;

        for (int i = 0; i < SAMPLES; i++)
        {
            const float3 offsetDir = DISK_RADIUS * sampleOffsetDirections[i] - relativePosition;
            const float sampleDepth = shadowMap.Sample(float4(offsetDir, float(index))).r;

            if (lightSquaredDistance < sampleDepth + BIAS)
            {
                shadow += 1.0;
            }
        }

        shadow /= float(SAMPLES);

        const float lambertainCoefficient = clamp(dot(normal, negativeLightDirection), 0.0, 1.0);
        cumulativeColour += shadow * lambertainCoefficient * light.colourIntensity.xyz / lightDistance;
    }

    cumulativeColour = max(cumulativeColour, float3(pushConstants.ambientLight, pushConstants.ambientLight, pushConstants.ambientLight));

    output.colour = float4(albedo * cumulativeColour, 1.0);
    return output;
}
