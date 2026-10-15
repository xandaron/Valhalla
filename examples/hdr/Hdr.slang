import Valhalla;

struct Push {
	ValhallaHeader header;
	float2 size;
	DescriptorHandle<Texture2D<float4>> scene;
	uint pq;
	float paper_white;
};

[[vk::push_constant]]
ConstantBuffer<Push> push;

static const float LOWEST_STOP = -4;
static const float HIGHEST_STOP = 3;

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
float4 ramps(Varyings input) : SV_Target {
	float2 uv = input.position.xy / push.size;
	float band_height = push.size.y / 4;
	uint band = min(uint(input.position.y / band_height), 3);
	float3 tints[4] = { float3(1, 1, 1), float3(1, 0.1, 0.1), float3(0.1, 1, 0.1), float3(0.15, 0.25, 1) };

	float paper_white_x = push.size.x * (0 - LOWEST_STOP) / (HIGHEST_STOP - LOWEST_STOP);
	float within_band = input.position.y - band * band_height;
	if (abs(input.position.x - paper_white_x) < 1.5 || within_band < 3) {
		return float4(0, 0, 0, 1);
	}
	float intensity = exp2(lerp(LOWEST_STOP, HIGHEST_STOP, uv.x));
	return float4(tints[band] * intensity, 1);
}

float3 rec709_to_rec2020(float3 colour) {
	return float3(
		dot(colour, float3(0.6274040, 0.3292820, 0.0433136)),
		dot(colour, float3(0.0690970, 0.9195400, 0.0113612)),
		dot(colour, float3(0.0163916, 0.0880132, 0.8955950)));
}

float3 pq_encode(float3 nits) {
	const float m1 = 0.1593017578125;
	const float m2 = 78.84375;
	const float c1 = 0.8359375;
	const float c2 = 18.8515625;
	const float c3 = 18.6875;
	float3 y = clamp(nits / 10000.0, 0.0, 1.0);
	float3 ym1 = pow(y, float3(m1));
	return pow((c1 + c2 * ym1) / (1.0 + c3 * ym1), float3(m2));
}

[shader("fragment")]
float4 encode(Varyings input) : SV_Target {
	float3 colour = push.scene.Load(int3(int2(input.position.xy), 0)).rgb;
	if (push.pq != 0) {
		return float4(pq_encode(rec709_to_rec2020(colour) * push.paper_white), 1);
	}
	return float4(pow(saturate(colour), 1.0 / 2.2), 1);
}
