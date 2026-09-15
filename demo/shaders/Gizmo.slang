import "Buffers.slang";
import "Textures.slang";
#include "Resources.slang"

struct PushConstants {
	HeapIndices resources;
	float radius;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

DECLARE_RESOURCES(pushConstants)

struct VertOut {
	float4 position : SV_Position;
	float2 offset;
	float3 colour;
};

[shader("vertex")]
VertOut vert(uint vertexID: SV_VertexID, uint instanceID: SV_InstanceID) {
	static const float2 CORNERS[6] = { float2(-1, -1), float2(1, -1), float2(1, 1),
																		 float2(-1, -1), float2(1, 1),  float2(-1, 1) };
	const float2 corner = CORNERS[vertexID];

	const Light light = Resources.Lights[instanceID];
	const float3 cameraPosition = Resources.Uniforms[0].cameraPosition;

	// Face the camera's position rather than its plane, so the quad reads as a sphere from any
	// angle instead of shearing as it approaches the edge of the view.
	float3 forward = cameraPosition - light.position;
	const float toCamera = length(forward);
	forward = toCamera > 1e-4 ? forward / toCamera : float3(0, 0, 1);

	// Any axis not parallel to forward works; swapping near the poles avoids a zero cross.
	const float3 reference = abs(forward.y) > 0.99 ? float3(1, 0, 0) : float3(0, 1, 0);
	const float3 right = normalize(cross(reference, forward));
	const float3 up = cross(forward, right);

	const float3 world =
			light.position + (right * corner.x + up * corner.y) * pushConstants.radius;

	VertOut output;
	output.position = mul(Resources.Uniforms[0].viewProjection, float4(world, 1.0));
	output.offset = corner;

	// Show the light's hue, not its flux: a 1600 lm bulb and a 100 lm one should look the same
	// colour, and brightness is carried by the falloff below.
	const float peak = max(light.lumens.r, max(light.lumens.g, light.lumens.b));
	output.colour = peak > 1e-4 ? light.lumens / peak : float3(1, 1, 1);
	return output;
}

struct FragOut {
	float4 colour : SV_Target0;
};

[shader("fragment")]
FragOut frag(VertOut input) {
	const float radius = length(input.offset);
	const float falloff = saturate(1.0 - radius);

	// A blown core with a wide soft halo, which is what an emitter looks like through a lens.
	// Values well above 1 are deliberate: this is linear light, before the display transform.
	const float intensity = falloff * falloff * 1.5 + pow(falloff, 8.0) * 8.0;

	FragOut output;
	output.colour = float4(input.colour * intensity, 1.0);
	return output;
}
