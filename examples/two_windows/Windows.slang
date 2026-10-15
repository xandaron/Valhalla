import Valhalla;

struct Shared {
	float4 colour;
	float2 pick;
	float radius;
	float padding;
};

struct Push {
	ValhallaHeader header;
	float2 size;
	DescriptorHandle<StructuredBuffer<Shared>> shared;
};

[[vk::push_constant]]
ConstantBuffer<Push> push;

struct Varyings {
	float4 position : SV_Position;
};

[shader("vertex")]
Varyings fullscreen(uint vertex_id : SV_VertexID) {
	float2 corner = float2((vertex_id << 1) & 2, vertex_id & 2);
	Varyings output;
	output.position = float4(corner * 2 - 1, 0, 1);
	return output;
}

float3 hue_value(float2 uv) {
	float3 rgb = saturate(abs(fmod(uv.x * 6.0 + float3(0, 4, 2), 6.0) - 3.0) - 1.0);
	return rgb * (1.0 - uv.y);
}

[shader("fragment")]
float4 palette(Varyings input) : SV_Target {
	Shared shared = push.shared[0];
	float distance = length(input.position.xy - shared.pick * push.size);
	if (distance > 7 && distance < 10) {
		return float4(1, 1, 1, 1);
	}
	if (distance >= 10 && distance < 12) {
		return float4(0, 0, 0, 1);
	}
	return float4(hue_value(input.position.xy / push.size), 1);
}

[shader("fragment")]
float4 disc(Varyings input) : SV_Target {
	Shared shared = push.shared[0];
	float radius = shared.radius * min(push.size.x, push.size.y);
	float distance = length(input.position.xy - push.size * 0.5);
	float coverage = saturate(radius - distance + 0.5);
	return float4(lerp(float3(0.08, 0.08, 0.1), shared.colour.rgb, coverage), 1);
}
