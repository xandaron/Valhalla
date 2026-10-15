import Valhalla;

struct Disc {
	float4 colour;
	float2 position;
	float radius;
	uint locked;
};

struct Push {
	ValhallaHeader header;
	DescriptorHandle<StructuredBuffer<Disc>> disc;
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

[shader("fragment")]
float4 scene(Varyings input) : SV_Target {
	Disc disc = push.disc[0];
	float2 cell = floor(input.position.xy / 40);
	float checker = fmod(cell.x + cell.y, 2);
	float3 background = lerp(float3(0.06, 0.06, 0.08), float3(0.09, 0.09, 0.12), checker);
	if (disc.locked != 0) {
		background += float3(0.04, 0.0, 0.0);
	}
	float distance = length(input.position.xy - disc.position);
	float coverage = saturate(disc.radius - distance + 0.5);
	return float4(lerp(background, disc.colour.rgb, coverage), 1);
}
