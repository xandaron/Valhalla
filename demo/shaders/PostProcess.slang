import "Buffers.slang";
import "Colour.slang";
import "Textures.slang";
#include "Resources.slang"

enum ToneMapper : uint32_t {
	None = 0,
	NarkowiczACES = 1,
}

struct PushConstants {
	HeapIndices resources;
	float contrast;
	float brightness;
	float saturation;
	float exposure;
	ToneMapper tonemapper;
	float gamma;
	uint contentOffsetX;
	uint contentOffsetY;
	uint contentExtentX;
	uint contentExtentY;
	TransferFunction transferFunction;
	float paperWhiteNits;
	uint outputExtentX;
	uint outputExtentY;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

DECLARE_RESOURCES(pushConstants)

float3 narkowiczACES(float3 colour) {
	const float A = 2.51;
	const float B = 0.03;
	const float C = 2.43;
	const float D = 0.59;
	const float E = 0.14;
	return clamp((colour * (A * colour + B)) / (colour * (C * colour + D) + E),
							 0.0, 1.0);
}

float3 grade(float3 colour) {
	colour =
			pushConstants.contrast * (colour - 0.5) + 0.5 + pushConstants.brightness;
	colour = max(colour, 0.0);

	float grayscale = dot(colour, float3(0.299, 0.587, 0.114));
	colour = lerp(float3(grayscale, grayscale, grayscale), colour,
								pushConstants.saturation);
	colour *= pushConstants.exposure;

	switch (pushConstants.tonemapper) {
	case ToneMapper.None:
		break;
	case ToneMapper.NarkowiczACES:
		colour = narkowiczACES(colour);
		break;
	}
	return colour;
}

[shader("compute")]
[numthreads(32, 32, 1)]
void comp(uint3 dispatchThreadID: SV_DispatchThreadID) {
	uint x = dispatchThreadID.x;
	uint y = dispatchThreadID.y;

	if (x >= pushConstants.outputExtentX || y >= pushConstants.outputExtentY) {
		return;
	}

	const uint2 contentOffset =
			uint2(pushConstants.contentOffsetX, pushConstants.contentOffsetY);
	const uint2 contentExtent =
			uint2(pushConstants.contentExtentX, pushConstants.contentExtentY);
	const uint2 content = uint2(x, y) - contentOffset;
	const bool inContent = x >= contentOffset.x && y >= contentOffset.y &&
												 content.x < contentExtent.x && content.y < contentExtent.y;

	const float3 scene = inContent ? grade(Resources.RenderedImage[int2(x, y)].xyz)
																 : float3(0.0, 0.0, 0.0);
	const float4 ui = Resources.UiImage[int2(x, y)];
	float3 colour = ui.rgb + scene * (1.0 - ui.a);

	switch (pushConstants.transferFunction) {
	case TransferFunction.Gamma:
		colour = pow(colour, float3(1.0 / pushConstants.gamma));
		break;
	case TransferFunction.PQ:
		colour = pqEncode(rec709ToRec2020(colour) * pushConstants.paperWhiteNits);
		break;
	}
	Resources.ProcessedImage[int2(x, y)] = float4(colour, 1.0);
}
