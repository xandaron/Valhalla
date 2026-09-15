import "Buffers.slang";
import "Textures.slang";
#include "Resources.slang"

enum ToneMapper : uint32_t {
	None = 0,
	NarkowiczACES = 1,
}

enum TransferFunction : uint32_t {
	Gamma = 0,
	PQ = 1,
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

float3 rec709ToRec2020(float3 colour) {
	return float3(dot(colour, float3(0.6274040, 0.3292820, 0.0433136)),
								dot(colour, float3(0.0690970, 0.9195400, 0.0113612)),
								dot(colour, float3(0.0163916, 0.0880132, 0.8955950)));
}

// SMPTE ST 2084. Takes absolute luminance in nits and returns the encoded signal an HDR10
// display expects, which is why HDR cannot simply reuse the gamma path.
float3 pqEncode(float3 nits) {
	const float m1 = 0.1593017578125;
	const float m2 = 78.84375;
	const float c1 = 0.8359375;
	const float c2 = 18.8515625;
	const float c3 = 18.6875;

	const float3 y = clamp(nits / 10000.0, 0.0, 1.0);
	const float3 ym1 = pow(y, float3(m1));
	return pow((c1 + c2 * ym1) / (1.0 + c3 * ym1), float3(m2));
}

[shader("compute")]
[numthreads(32, 32, 1)]
void comp(uint3 dispatchThreadID: SV_DispatchThreadID) {
	uint x = dispatchThreadID.x;
	uint y = dispatchThreadID.y;

	uint2 imageSize;
	Resources.RenderedImage.GetDimensions(imageSize.x, imageSize.y);
	if (x >= imageSize.x || y >= imageSize.y) {
		return;
	}

	const uint2 contentOffset =
			uint2(pushConstants.contentOffsetX, pushConstants.contentOffsetY);
	const uint2 contentExtent =
			uint2(pushConstants.contentExtentX, pushConstants.contentExtentY);
	const uint2 content = uint2(x, y) - contentOffset;
	if (x < contentOffset.x || y < contentOffset.y || content.x >= contentExtent.x ||
			content.y >= contentExtent.y) {
		Resources.ProcessedImage[int2(x, y)] = float4(0.0, 0.0, 0.0, 1.0);
		return;
	}

	float3 colour = Resources.RenderedImage[int2(x, y)].xyz;

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
