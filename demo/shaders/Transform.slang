import "Vertex.slang";
import "Buffers.slang";
import "Textures.slang";
#include "Resources.slang"

struct PushConstants {
	HeapIndices resources;
	uint instance;
	uint instanceCount;
	uint vertexCount;
	uint vertexOffset;
	uint transformOffset;
};

[[vk::push_constant]]
PushConstants pushConstants;

DECLARE_RESOURCES(pushConstants)

[shader("compute")]
[numthreads(64, 1, 1)]
void comp(uint3 dispatchThreadID: SV_DispatchThreadID) {
	if (dispatchThreadID.x >= pushConstants.vertexCount) {
		return;
	}

	const Vertex vertex =
			Resources.Vertices[pushConstants.vertexOffset + dispatchThreadID.x];
	for (int i = 0; i < pushConstants.instanceCount; i++) {
		const uint instanceIndex = pushConstants.instance + i;
		const uint boneOffset = Resources.Instances[instanceIndex].boneOffset;

		float4x4 boneTransform = float4x4(0.0);
		for (uint j = 0; j < 4; j++) {
			boneTransform +=
					vertex.weights[j] * Resources.Bones[boneOffset + vertex.bones[i]];
		}

		Resources.TransformsRW[pushConstants.transformOffset + dispatchThreadID.x +
											i * pushConstants.vertexCount] =
				mul(Resources.Instances[instanceIndex].model, boneTransform);
	}
}
