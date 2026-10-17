import Valhalla;

struct Push {
	ValhallaHeader header;
	float4 tint;
};
[[vk::push_constant]] ConstantBuffer<Push> push;

struct Varyings {
	float4 position : SV_Position;
	float2 uv       : TEXCOORD0;
}

static const float2 CORNERS[4] = { float2(-0.8, -0.8), float2(0.8, -0.8), float2(0.8, 0.8), float2(-0.8, 0.8) };

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
	Varyings output;
	output.position = float4(CORNERS[vertex_id], 0.0, 1.0);
	output.uv = CORNERS[vertex_id] * 0.5 + 0.5;
	return output;
}

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
	return float4(input.uv.x, input.uv.y, 0.3, 1.0) * push.tint;
}
