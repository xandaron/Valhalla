import "Buffers.slang";

struct PushConstants {
	float3 v0;
	float3 v1;
	float4 colour;
	float thickness;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

struct VertOut {
	float4 position : SV_Position;
};

[shader("vertex")]
VertOut vert(uint vertexID: SV_VertexID) {
	VertOut output;

	float3 vertex = vertexID == 0 ? pushConstants.v0 : pushConstants.v1;
	output.position = mul(uniformBuffer.viewProjection, float4(vertex, 1.0));
	
	return output;
}

struct FragOut {
	float4 colour : SV_Target0;
};

[shader("fragment")]
FragOut frag(VertOut input) {
	FragOut output;
	output.colour = pushConstants.colour;
	return output;
}