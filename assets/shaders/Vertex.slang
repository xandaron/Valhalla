struct Vertex
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    float3 bitangent : BITANGENT;
    float2 uv : TEXCOORD0;
    uint4 bones : BLENDINDICES;
    float4 weights : BLENDWEIGHT;
};