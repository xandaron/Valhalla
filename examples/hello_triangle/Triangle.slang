struct Varyings {
	float4 position : SV_Position;
	float3 colour   : COLOR0;
}

static const float2 POSITIONS[3] = { float2(0.0, -0.5), float2(0.5, 0.5), float2(-0.5, 0.5) };
static const float3 COLOURS[3] = { float3(1, 0, 0), float3(0, 1, 0), float3(0, 0, 1) };

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
	Varyings output;
	output.position = float4(POSITIONS[vertex_id], 0.0, 1.0);
	output.colour = COLOURS[vertex_id];
	return output;
}

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
	return float4(input.colour, 1.0);
}
