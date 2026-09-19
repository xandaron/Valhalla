import "Buffers.slang";
import "Textures.slang";
#include "Resources.slang"

struct PushConstants {
	HeapIndices resources;
	float2 scale;
	float2 translate;
	uint texture;
	float rangeMin;
	float rangeMax;
	uint remap;
};

static const float UI_GAMMA = 2.2;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

DECLARE_RESOURCES(pushConstants)

struct VertOut {
	float4 position : SV_Position;
	float4 colour;
	float2 uv;
};

[shader("vertex")]
VertOut vert(uint vertexID: SV_VertexID, uint baseVertex: SV_StartVertexLocation) {
	const ImDrawVert vertex = Resources.ImguiVertices[vertexID + baseVertex];

	const uint4 channels = uint4(vertex.colour, vertex.colour >> 8, vertex.colour >> 16,
															 vertex.colour >> 24) &
												 0xFF;

	VertOut output;
	output.position =
			float4(float2(vertex.positionX, vertex.positionY) * pushConstants.scale +
								 pushConstants.translate,
						 0.0, 1.0);
	output.colour = float4(channels) / 255.0;
	output.uv = float2(vertex.u, vertex.v);
	return output;
}

struct FragOut {
	float4 colour : SV_Target0;
};

[shader("fragment")]
FragOut frag(VertOut input) {
	float4 texel = textureAt(pushConstants.texture).Sample(Resources.LinearSampler, input.uv);
	if (pushConstants.remap != 0) {
		const float span = max(pushConstants.rangeMax - pushConstants.rangeMin, 1e-6);
		texel = float4(saturate((texel.rgb - pushConstants.rangeMin) / span), 1.0);
	}
	float4 colour = input.colour * texel;
	colour.rgb = pow(colour.rgb, UI_GAMMA);

	FragOut output;
	output.colour = colour;
	return output;
}
