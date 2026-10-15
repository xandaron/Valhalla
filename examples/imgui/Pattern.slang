import Valhalla;

struct PatternPush {
	ValhallaHeader header;
	float2 size;
	float time;
	float speed;
	float4 tint;
};

[[vk::push_constant]]
ConstantBuffer<PatternPush> pattern_push;

struct PatternVaryings {
	float4 position : SV_Position;
};

[shader("vertex")]
PatternVaryings pattern_vertex(uint vertex_id : SV_VertexID) {
	float2 corner = float2((vertex_id << 1) & 2, vertex_id & 2);
	PatternVaryings output;
	output.position = float4(corner * 2 - 1, 0, 1);
	return output;
}

[shader("fragment")]
float4 pattern_fragment(PatternVaryings input) : SV_Target {
	float2 uv = input.position.xy / pattern_push.size;
	float t = pattern_push.time * pattern_push.speed;
	float wave = sin(uv.x * 10 + t) + sin(uv.y * 12 - t * 1.3) + sin((uv.x + uv.y) * 9 + t * 0.7) + sin(length(uv - 0.5) * 18 - t * 2);
	float3 colour = 0.5 + 0.5 * cos(wave * 1.6 + float3(0, 2.1, 4.2));
	return float4(colour * pattern_push.tint.rgb, 1);
}
