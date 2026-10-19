import Valhalla;

struct Vertex {
	float4 position;
	float4 normal;
};

struct Object {
	float4x4 model;
	float4 colour;
	float4 material;
};

struct Light {
	float4 position;
	float4 colour;
};

struct View {
	float4 view_projection[4];
	float4 camera;
};

struct Push {
	ValhallaHeader header;
	float4x4 light_view_projection;
	float4 sun;
	DescriptorHandle<StructuredBuffer<Vertex>> vertices;
	DescriptorHandle<StructuredBuffer<Object>> objects;
	DescriptorHandle<StructuredBuffer<Light>> lights;
	uint light_count;
	DescriptorHandle<Texture2D<float>> shadow_map;
	DescriptorHandle<SamplerComparisonState> shadow_sampler;
	DescriptorHandle<StructuredBuffer<float4x4>> faces;
	DescriptorHandle<TextureCube<float>> point_shadow_maps[4];
	uint shadow_light;
	DescriptorHandle<ConstantBuffer<View>> view;
};

[[vk::push_constant]]
ConstantBuffer<Push> push;

static const float3 SUN_COLOUR = float3(1.0, 0.92, 0.8);
static const float3 SKY_AMBIENT = float3(0.05, 0.065, 0.1);
static const float3 GROUND_AMBIENT = float3(0.025, 0.02, 0.018);
static const float POINT_NEAR = 0.05;
static const float POINT_FAR = 8;

struct Varyings {
	float4 position : SV_Position;
	float3 world : POSITION0;
	float3 normal : NORMAL0;
	nointerpolation uint object : OBJECT0;
};

Varyings transform(uint vertex_id, uint base_vertex, uint object_index, float4x4 view_projection) {
	Vertex vertex = push.vertices[vertex_id + base_vertex];
	Object object = push.objects[object_index];
	float4 world = mul(object.model, vertex.position);
	Varyings output;
	output.position = mul(view_projection, world);
	output.world = world.xyz;
	output.normal = mul((float3x3)object.model, vertex.normal.xyz);
	output.object = object_index;
	return output;
}

[shader("vertex")]
float4 shadow_vertex(
	uint vertex_id : SV_VertexID,
	uint base_vertex : SV_StartVertexLocation) : SV_Position {
	return transform(vertex_id, base_vertex, push.header.draw_data, push.light_view_projection).position;
}

[shader("vertex")]
float4 point_shadow_vertex(
	uint vertex_id : SV_VertexID,
	uint base_vertex : SV_StartVertexLocation,
	uint face : SV_ViewID) : SV_Position {
	float4x4 face_view_projection = push.faces[push.shadow_light * 6 + face];
	return transform(vertex_id, base_vertex, push.header.draw_data, face_view_projection).position;
}

[shader("vertex")]
Varyings lit_vertex(
	uint vertex_id : SV_VertexID,
	uint base_vertex : SV_StartVertexLocation) {
	const float4x4 view_projection = transpose(float4x4(
		push.view->view_projection[0],
		push.view->view_projection[1],
		push.view->view_projection[2],
		push.view->view_projection[3]));
	return transform(vertex_id, base_vertex, push.header.draw_data, view_projection);
}

float sun_visibility(float3 world, float3 normal) {
	Texture2D<float> shadow_map = push.shadow_map;
	SamplerComparisonState compare = push.shadow_sampler;
	float4 clip = mul(push.light_view_projection, float4(world + normal * 0.03, 1));
	float2 uv = clip.xy * 0.5 + 0.5;
	uint width, height;
	shadow_map.GetDimensions(width, height);
	float2 texel = 1.0 / float2(width, height);
	float lit = 0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			lit += shadow_map.SampleCmpLevelZero(compare, uv + float2(x, y) * texel, clip.z);
		}
	}
	return lit / 9;
}

float cube_depth(float3 offset) {
	float axis = max(abs(offset.x), max(abs(offset.y), abs(offset.z)));
	return POINT_NEAR * POINT_FAR / ((POINT_FAR - POINT_NEAR) * axis) - POINT_NEAR / (POINT_FAR - POINT_NEAR);
}

float point_visibility(uint light, float3 world, float3 normal, float3 light_position) {
	TextureCube<float> shadow_map = push.point_shadow_maps[light];
	SamplerComparisonState compare = push.shadow_sampler;
	float3 offset = world + normal * 0.04 - light_position;
	float distance = length(offset);
	float3 direction = offset / distance;
	float3 tangent = normalize(cross(direction, abs(direction.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
	float3 bitangent = cross(direction, tangent);
	float spread = 0.015 * distance;
	float2 taps[8] = {
		float2(1, 0), float2(-1, 0), float2(0, 1), float2(0, -1),
		float2(0.7, 0.7), float2(-0.7, 0.7), float2(0.7, -0.7), float2(-0.7, -0.7),
	};
	float lit = shadow_map.SampleCmpLevelZero(compare, offset, cube_depth(offset));
	for (int index = 0; index < 8; index++) {
		float3 tap = offset + (tangent * taps[index].x + bitangent * taps[index].y) * spread;
		lit += shadow_map.SampleCmpLevelZero(compare, tap, cube_depth(tap));
	}
	return lit / 9;
}

[shader("fragment")]
float4 lit_fragment(Varyings input) : SV_Target {
	Object object = push.objects[input.object];
	float3 albedo = object.colour.rgb;
	float shininess = object.material.x;
	float specular_strength = object.material.y;
	float emission = object.material.z;

	float3 colour;
	if (emission > 0) {
		colour = albedo * emission;
	} else {
		float3 normal = normalize(input.normal);
		float3 to_camera = normalize(push.view->camera.xyz - input.world);
		colour = albedo * lerp(GROUND_AMBIENT, SKY_AMBIENT, normal.y * 0.5 + 0.5);

		float3 to_sun = -normalize(push.sun.xyz);
		float sun_diffuse = saturate(dot(normal, to_sun));
		if (sun_diffuse > 0) {
			float visibility = sun_visibility(input.world, normal);
			float3 halfway = normalize(to_sun + to_camera);
			float specular = pow(saturate(dot(normal, halfway)), shininess) * specular_strength;
			colour += (albedo * sun_diffuse + specular) * SUN_COLOUR * push.sun.w * visibility;
		}

		StructuredBuffer<Light> lights = push.lights;
		for (uint index = 0; index < push.light_count; index++) {
			Light light = lights[index];
			float3 offset = light.position.xyz - input.world;
			float distance = length(offset);
			float3 to_light = offset / distance;
			float falloff = saturate(1 - pow(distance / light.position.w, 4));
			float attenuation = falloff * falloff / (distance * distance + 1);
			float diffuse = saturate(dot(normal, to_light));
			if (diffuse <= 0 || attenuation <= 0) {
				continue;
			}
			float visibility = point_visibility(index, input.world, normal, light.position.xyz);
			float3 halfway = normalize(to_light + to_camera);
			float specular = pow(saturate(dot(normal, halfway)), shininess) * specular_strength;
			colour += (albedo * diffuse + specular) * light.colour.rgb * light.colour.w * attenuation * visibility;
		}
	}

	colour = saturate(colour * (2.51 * colour + 0.03) / (colour * (2.43 * colour + 0.59) + 0.14));
	return float4(colour, 1);
}
