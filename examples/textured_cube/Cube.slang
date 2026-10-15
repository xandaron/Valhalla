import Valhalla;

struct Vertex {
	float4 position;
	float2 uv;
	float2 padding;
};

struct Frame {
	float4x4 transform;
};

struct Push {
	ValhallaHeader header;
	DescriptorHandle<StructuredBuffer<Frame>> frame;
	DescriptorHandle<StructuredBuffer<Vertex>> vertices;
	DescriptorHandle<Texture2D<float4>> albedo;
	DescriptorHandle<SamplerState> linear_sampler;
};

[[vk::push_constant]]
ConstantBuffer<Push> push;

struct Varyings {
	float4 position : SV_Position;
	float2 uv       : TEXCOORD0;
};

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
	Vertex vertex = push.vertices[vertex_id];
	Varyings output;
	Frame frame = push.frame[0];
	output.position = mul(frame.transform, vertex.position);
	output.uv = vertex.uv;
	return output;
}

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
	return push.albedo.Sample(push.linear_sampler, input.uv);
}
