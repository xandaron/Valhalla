import Valhalla;

struct DrawVert {
	float x;
	float y;
	float u;
	float v;
	uint colour;
};

struct ImGuiPush {
	ValhallaHeader header;
	float2 scale;
	float2 translate;
	DescriptorHandle<StructuredBuffer<DrawVert>> vertices;
	DescriptorHandle<SamplerState> sampler;
	DescriptorHandle<SamplerState> nearest_sampler;
	uint srgb_target;
};

[[vk::push_constant]]
ConstantBuffer<ImGuiPush> imgui_push;

struct ImGuiVaryings {
	float4 position : SV_Position;
	float4 colour : COLOR0;
	float2 uv : TEXCOORD0;
	nointerpolation uint texture : TEXCOORD1;
	nointerpolation uint decoded : TEXCOORD2;
	nointerpolation uint nearest : TEXCOORD3;
};

[shader("vertex")]
ImGuiVaryings imgui_vertex(uint vertex_id : SV_VertexID, uint base_vertex : SV_StartVertexLocation) {
	DrawVert vertex = imgui_push.vertices[vertex_id + base_vertex];
	uint4 channels = (uint4(vertex.colour, vertex.colour >> 8, vertex.colour >> 16, vertex.colour >> 24)) & 0xFF;
	ImGuiVaryings output;
	output.position = float4(float2(vertex.x, vertex.y) * imgui_push.scale + imgui_push.translate, 0, 1);
	output.colour = float4(channels) / 255.0;
	output.uv = float2(vertex.u, vertex.v);
	output.texture = imgui_push.header.draw_data & 0x3FFFFFFFu;
	output.decoded = imgui_push.header.draw_data >> 31;
	output.nearest = (imgui_push.header.draw_data >> 30) & 1u;
	return output;
}

[shader("fragment")]
float4 imgui_fragment(ImGuiVaryings input) : SV_Target {
	Texture2D<float4> texture = valhalla_sampled<Texture2D<float4>>(imgui_push.header, input.texture);
	SamplerState sampler = input.nearest != 0 ? imgui_push.nearest_sampler : imgui_push.sampler;
	float4 texel = texture.Sample(sampler, input.uv);
	if (input.decoded != 0) {
		texel.rgb = valhalla_linear_to_srgb(texel.rgb);
	}
	float4 colour = input.colour * texel;
	if (imgui_push.srgb_target != 0) {
		colour.rgb = valhalla_srgb_to_linear(colour.rgb);
	}
	return colour;
}
