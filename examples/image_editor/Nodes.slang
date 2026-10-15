import Valhalla;

struct NodeParams {
	float4 p0;
	float4 p1;
};

struct NodePush {
	ValhallaHeader header;
	float2 texel;
	float2 direction;
	DescriptorHandle<Texture2D<float4>> a;
	DescriptorHandle<Texture2D<float4>> b;
	DescriptorHandle<SamplerState> sampler;
	DescriptorHandle<StructuredBuffer<NodeParams>> params;
};

[[vk::push_constant]]
ConstantBuffer<NodePush> push;

NodeParams params() {
	return push.params[push.header.draw_data];
}

struct Varyings {
	float4 position : SV_Position;
	float2 uv : TEXCOORD0;
};

[shader("vertex")]
Varyings fullscreen(uint vertex_id : SV_VertexID) {
	float2 corner = float2((vertex_id << 1) & 2, vertex_id & 2);
	Varyings output;
	output.position = float4(corner * 2 - 1, 0, 1);
	output.uv = corner;
	return output;
}

float4 sample_a(float2 uv) {
	return push.a.Sample(push.sampler, uv);
}

float4 sample_b(float2 uv) {
	return push.b.Sample(push.sampler, uv);
}

static const float3 LUMA = float3(0.2126, 0.7152, 0.0722);

[shader("fragment")]
float4 adjust(Varyings input) : SV_Target {
	float4 colour = sample_a(input.uv);
	NodeParams p = params();
	float3 rgb = colour.rgb * exp2(p.p0.x);
	rgb *= float3(1 + p.p1.x * 0.1, 1, 1 - p.p1.x * 0.1);
	rgb = max(rgb, 0);
	float3 log_rgb = log2(rgb + 1e-5);
	rgb = exp2((log_rgb - log2(0.18)) * p.p0.y + log2(0.18));
	rgb = lerp(dot(rgb, LUMA).xxx, rgb, p.p0.z);
	rgb = pow(max(rgb, 0), 1.0 / max(p.p0.w, 0.01));
	return float4(rgb, colour.a);
}

[shader("fragment")]
float4 blur(Varyings input) : SV_Target {
	float radius = params().p0.x;
	if (radius < 0.5) {
		return sample_a(input.uv);
	}
	float2 step = push.direction * push.texel;
	float sigma = radius * 0.5;
	int taps = int(ceil(radius));
	float4 total = 0;
	float weights = 0;
	for (int i = -taps; i <= taps; i++) {
		float weight = exp(-float(i * i) / (2 * sigma * sigma));
		total += sample_a(input.uv + step * float(i)) * weight;
		weights += weight;
	}
	return total / weights;
}

[shader("fragment")]
float4 sharpen(Varyings input) : SV_Target {
	float2 t = push.texel;
	float4 centre = sample_a(input.uv);
	float4 around = sample_a(input.uv + float2(t.x, 0)) + sample_a(input.uv - float2(t.x, 0)) + sample_a(input.uv + float2(0, t.y)) + sample_a(input.uv - float2(0, t.y));
	return float4(centre.rgb + (centre.rgb * 4 - around.rgb) * params().p0.x, centre.a);
}

[shader("fragment")]
float4 mix(Varyings input) : SV_Target {
	return lerp(sample_a(input.uv), sample_b(input.uv), params().p0.x);
}

[shader("fragment")]
float4 encode(Varyings input) : SV_Target {
	float2 size;
	push.a.GetDimensions(size.x, size.y);
	float2 footprint = max(size * push.texel, 1);
	int2 taps = min(int2(ceil(footprint * 0.5)), 8);
	float4 total = 0;
	for (int y = 0; y < taps.y; y++) {
		for (int x = 0; x < taps.x; x++) {
			float2 offset = ((float2(x, y) + 0.5) / float2(taps) - 0.5) * footprint / size;
			total += sample_a(input.uv + offset);
		}
	}
	float4 colour = total / float(taps.x * taps.y);
	return float4(valhalla_linear_to_srgb(colour.rgb), 1);
}

[shader("fragment")]
float4 copy(Varyings input) : SV_Target {
	return sample_a(input.uv);
}
