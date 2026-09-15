import "Vertex.slang";
import "Buffers.slang";
import "Textures.slang";
#include "Resources.slang"

#define PI 3.14159265358979323846264338327950288

struct PushConstants {
	HeapIndices resources;
	uint vertexOffset;
	uint vertexCount;
	uint instanceOffset;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

DECLARE_RESOURCES(pushConstants)

float3x3 inverse3x3(float3x3 m) {
	float det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
							m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
							m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

	float invDet = 1.0 / det;

	float3x3 inv;
	inv[0][0] = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) * invDet;
	inv[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * invDet;
	inv[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * invDet;
	inv[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) * invDet;
	inv[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * invDet;
	inv[1][2] = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * invDet;
	inv[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) * invDet;
	inv[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * invDet;
	inv[2][2] = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * invDet;

	return inv;
}

struct VertOut {
	float4 position : SV_Position;
	float3 worldPosition : POSITION;
	float3x3 TBN;
	float2 uv : TEXCOORD0;
	uint instanceID;
};

[shader("vertex")]
VertOut vert(uint vertexID: SV_VertexID, uint baseVertex: SV_StartVertexLocation,
						 uint instanceID: SV_InstanceID) {
	VertOut output;

	const Vertex vertex = Resources.Vertices[vertexID + baseVertex];

	const uint idx = vertexID + pushConstants.vertexOffset +
									 instanceID * pushConstants.vertexCount;
	const float4x4 vertexTransform = Resources.Transforms[idx];
	const float4 worldPosition =
			mul(vertexTransform, float4(vertex.position, 1.0));
	output.position = mul(Resources.Uniforms[0].viewProjection, worldPosition);
	output.worldPosition = worldPosition.xyz / worldPosition.w;

	// I need to figue this out. I think the tangent and bitangent are not being
	// set correctly.
	const float3x3 transform = (float3x3)vertexTransform;
	const float3x3 transposedInverse = transpose(inverse3x3(transform));
	output.TBN = transpose(
			float3x3(float3(0.0, 0.0, 0.0), // normalize(mul(t, vertex.tangent)),
							 float3(0.0, 0.0, 0.0), // normalize(mul(t, vertex.bitangent)),
							 normalize(mul(transposedInverse, vertex.normal)), ));
	output.uv = vertex.uv;

	output.instanceID = instanceID;
	return output;
}

struct FragOut {
	float4 colour : SV_Target0;
};

[shader("fragment")]
FragOut frag(VertOut input) {
	FragOut output;

	static const int SAMPLES = 20;
	// Sample offset directions for shadow sampling
	static const float3 sampleOffsetDirections[SAMPLES] = {
		float3(1, 0, 0),	float3(-1, 0, 0), float3(0, 1, 0), float3(0, -1, 0),
		float3(0, 0, 1),	float3(0, 0, -1), float3(1, 1, 0), float3(-1, -1, 0),
		float3(1, -1, 0), float3(-1, 1, 0), float3(1, 0, 1), float3(-1, 0, -1),
		float3(1, 0, -1), float3(-1, 0, 1), float3(0, 1, 1), float3(0, -1, -1),
		float3(0, 1, -1), float3(0, -1, 1), float3(1, 1, 1), float3(-1, -1, -1)
	};

	float3 cumulativeColour = { 0.0, 0.0, 0.0 };

	const uint textureIndex =
			(pushConstants.instanceOffset + input.instanceID) * TextureIndex.COUNT;
	const float3 albedo =
			textureAt(Resources.TextureIndices[textureIndex + TextureIndex.ALBEDO])
					.Sample(Resources.AnisotropicSampler, input.uv)
					.xyz;
	const float3 normal = normalize(mul(
			input.TBN,
			2.0 * textureAt(Resources.TextureIndices[textureIndex + TextureIndex.NORMAL]).Sample(Resources.AnisotropicSampler, input.uv)
									.xyz -
					1.0));

	for (uint index = 0; index < Resources.Uniforms[0].lightCount; index++) {
		const Light light = Resources.Lights[index];

		const float3 relativePosition = light.position.xyz - input.worldPosition;
		const float lightSquaredDistance = dot(relativePosition, relativePosition);
		const float lightDistance = sqrt(lightSquaredDistance);
		const float3 negativeLightDirection = relativePosition / lightDistance;

		float shadow = 0.0;

		for (int i = 0; i < SAMPLES; i++) {
			static const float DISK_RADIUS = 0.01;
			const float3 offsetDir =
					DISK_RADIUS * sampleOffsetDirections[i] - relativePosition;
			const float sampleDepth =
					Resources.ShadowMap.Sample(Resources.LinearSampler, float4(offsetDir, float(index))).r;

			static const float BIAS = 0.005;
			if (lightSquaredDistance < sampleDepth + BIAS) {
				shadow += 1.0;
			}
		}

		shadow /= float(SAMPLES);

		// Point light photometry. An isotropic source of flux F has luminous intensity
		// I = F / 4pi, giving illuminance E = I / d^2 at the surface, and a Lambertian surface
		// reflects L = albedo * E * cos(theta) / pi. Albedo is applied once after the loop, so
		// what accumulates here is E * cos(theta) / pi.
		//
		// The distance is clamped because a true point source diverges at its own position;
		// the clamp stands in for the light having physical size.
		static const float MIN_DISTANCE_SQUARED = 0.0001;
		const float attenuation =
				1.0 / (4.0 * PI * PI * max(lightSquaredDistance, MIN_DISTANCE_SQUARED));

		const float lambertainCoefficient =
				clamp(dot(normal, negativeLightDirection), 0.0, 1.0);
		cumulativeColour += shadow * lambertainCoefficient * light.lumens * attenuation;
	}

	cumulativeColour += Resources.Uniforms[0].ambientLight / PI;

	output.colour = float4(albedo * cumulativeColour, 1.0);
	return output;
}

[shader("fragment")]
FragOut norm(VertOut input) {
	FragOut output;

	const uint textureIndex =
			(pushConstants.instanceOffset + input.instanceID) * TextureIndex.COUNT;
	const float3 normal = normalize(mul(
			input.TBN,
			2.0 * textureAt(Resources.TextureIndices[textureIndex + TextureIndex.NORMAL]).Sample(Resources.AnisotropicSampler, input.uv)
									.xyz -
					1.0));

	const float3 outColour = (normal + 1) / 2;
	output.colour = float4(outColour, 1.0);
	return output;
}
