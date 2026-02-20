import "Resources.slang";

enum ToneMapper : uint32_t {
	None = 0,
	NarkowiczACES = 1,
}

struct PushConstants {
	float contrast;
	float brightness;
	float saturation;
	float exposure;
	ToneMapper tonemapper;
	float gamma;
	bool drawLights;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

float3 narkowiczACES(float3 colour) {
	const float A = 2.51;
	const float B = 0.03;
	const float C = 2.43;
	const float D = 0.59;
	const float E = 0.14;
	return clamp((colour * (A * colour + B)) / (colour * (C * colour + D) + E),
							 0.0, 1.0);
}

[shader("compute")]
[numthreads(32, 32, 1)]
void comp(uint3 dispatchThreadID: SV_DispatchThreadID) {
	uint x = dispatchThreadID.x;
	uint y = dispatchThreadID.y;

	uint2 imageSize;
	renderedImage.GetDimensions(imageSize.x, imageSize.y);
	float2 screenPosition = float2(x, y) / imageSize;

	float3 colour = renderedImage[int2(x, y)].xyz;

	if (pushConstants.drawLights) {
		for (uint i = 0; i < (*uniformBuffer).lightCount; i++) {
			float4 lightPosition = mul((*uniformBuffer).viewProjection,
																 float4(lightBuffer[i].position, 1.0));
			lightPosition /= lightPosition.w;

			float depth = sceneDepth.Sample(noAnisoSampler, screenPosition).r;
			if (lightPosition.z <= depth && lightPosition.z >= 0) {
				lightPosition.xy += 1.0;
				lightPosition.xy /= 2.0;

				const float radius = 0.1;
				float2 position = screenPosition - lightPosition.xy;
				if (dot(position, position) <=
						(radius * radius) * (1 - lightPosition.z)) {
					colour = (0.5 * 0.5) / colour;
				}
			}
		}
	}

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

	colour = pow(colour, float3(1.0 / pushConstants.gamma));
	processedImage[int2(x, y)] = float4(colour, 1.0);
}
