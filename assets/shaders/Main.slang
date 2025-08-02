import "Vertex.slang";
import "Light.slang";
import "Buffers.slang";
import "Textures.slang";

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
    float3x3 TBN;
    float2 uv : TEXCOORD0;
};

float3x3 inverse3x3(float3x3 m)
{
    float det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
              - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
              + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

    float invDet = 1.0 / det;

    float3x3 inv;
    inv[0][0] = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) * invDet;
    inv[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * invDet;
    inv[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * invDet;
    inv[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) * invDet;
    inv[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * invDet;
    inv[1][2] = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * invDet;
    inv[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) * invDet;
    inv[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * invDet;
    inv[2][2] = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * invDet;

    return inv;
}

[shader("vertex")]
VertOut vert(Vertex vertex, uint vertexID: SV_VertexID)
{
    VertOut output;

    const float4x4 vertexTransform = transformBufferRO[vertexID + pushConstants.vertexOffset];
    const float4 worldPosition = mul(vertexTransform, float4(vertex.position, 1.0));
    output.position = mul(uniformBuffer.viewProjection, worldPosition);
    output.worldPosition = worldPosition.xyz / worldPosition.w;

    // I need to figue this out. I think the tangent and bitangent are not being set correctly.
    float3x3 t = (float3x3)vertexTransform;
    float3x3 tt = transpose(inverse3x3((float3x3)vertexTransform));
    output.TBN = transpose(float3x3(
        float3(0.0, 0.0, 0.0), // normalize(mul(t, vertex.tangent)),
        float3(0.0, 0.0, 0.0), // normalize(mul(t, vertex.bitangent)),
        normalize(mul(tt, vertex.normal)),
    ));
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
    #define BIAS 0.002
    #define DISK_RADIUS 0.0015

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

    const float3 albedo = pow(albedoArray.Sample(float3(input.uv, pushConstants.albedoTextureIndex)).xyz, 1.0 / 2.2);

    const float3 normalSample = 2.0 * normalArray.Sample(float3(input.uv, pushConstants.normalTextureIndex)).xyz - 1.0;
    const float3 normal = normalize(mul(input.TBN, normalSample));

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

        const float scalingFactor = 1.0 / max(lightDistance - light.dropoff, 1.0);

        const float lambertainCoefficient = clamp(dot(normal, negativeLightDirection), 0.0, 1.0);
        cumulativeColour += shadow * lambertainCoefficient * light.colourIntensity.xyz * scalingFactor;
    }

    cumulativeColour = max(cumulativeColour, float3(pushConstants.ambientLight, pushConstants.ambientLight, pushConstants.ambientLight));

    output.colour = float4(albedo * cumulativeColour, 1.0);
    // output.colour = float4(normal, 1.0);
    return output;
}
