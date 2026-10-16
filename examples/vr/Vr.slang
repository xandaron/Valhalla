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

struct Eye {
	float4x4 view_projection;
	float4 position;
};

struct View {
	float4 sun;
	float4 settings;
};

struct Push {
	ValhallaHeader header;
	DescriptorHandle<StructuredBuffer<Vertex>> vertices;
	DescriptorHandle<StructuredBuffer<Object>> objects;
	DescriptorHandle<StructuredBuffer<Eye>> eyes;
	DescriptorHandle<StructuredBuffer<View>> view;
	DescriptorHandle<Texture2DArray<float4>> eye_images;
	DescriptorHandle<SamplerState> sampler;
};

[[vk::push_constant]]
ConstantBuffer<Push> push;

static const float3 SUN_COLOUR = float3(1.0, 0.93, 0.82);
static const float3 SKY = float3(0.42, 0.56, 0.78);
static const float3 GROUND_AMBIENT = float3(0.05, 0.045, 0.04);
static const float LENS_K1 = 0.22;
static const float LENS_K2 = 0.24;

struct Varyings {
	float4 position : SV_Position;
	float3 world : POSITION0;
	float3 normal : NORMAL0;
	nointerpolation uint object : OBJECT0;
	nointerpolation uint eye : EYE0;
};

[shader("vertex")]
Varyings scene_vertex(
	uint vertex_id : SV_VertexID,
	uint base_vertex : SV_StartVertexLocation,
	uint view_id : SV_ViewID) {
	Vertex vertex = push.vertices[vertex_id + base_vertex];
	Object object = push.objects[push.header.draw_data];
	float4 world = mul(object.model, vertex.position);
	Varyings output;
	output.position = mul(push.eyes[view_id].view_projection, world);
	output.world = world.xyz;
	output.normal = mul((float3x3)object.model, vertex.normal.xyz);
	output.object = push.header.draw_data;
	output.eye = view_id;
	return output;
}

float checker(float2 position) {
	float2 cell = floor(position);
	return fmod(abs(cell.x + cell.y), 2) < 1 ? 1 : 0.55;
}

[shader("fragment")]
float4 scene_fragment(Varyings input) : SV_Target {
	Object object = push.objects[input.object];
	float3 albedo = object.colour.rgb;
	if (object.material.z > 0) {
		albedo *= checker(input.world.xz);
	}
	float3 normal = normalize(input.normal);
	float3 to_eye = push.eyes[input.eye].position.xyz - input.world;
	float distance = length(to_eye);
	to_eye /= distance;

	float4 sun = push.view[0].sun;
	float3 to_sun = -normalize(sun.xyz);
	float3 halfway = normalize(to_sun + to_eye);
	float diffuse = saturate(dot(normal, to_sun));
	float specular = pow(saturate(dot(normal, halfway)), object.material.x) * object.material.y * (diffuse > 0 ? 1 : 0);
	float3 colour = albedo * lerp(GROUND_AMBIENT, SKY * 0.35, normal.y * 0.5 + 0.5);
	colour += (albedo * diffuse + specular) * SUN_COLOUR * sun.w;

	float fog = 1 - exp(-distance * 0.025);
	colour = lerp(colour, SKY, fog);
	return float4(colour, 1);
}

struct Screen {
	float4 position : SV_Position;
	float2 uv : TEXCOORD0;
};

[shader("vertex")]
Screen composite_vertex(uint vertex_id : SV_VertexID) {
	float2 corner = float2((vertex_id << 1) & 2, vertex_id & 2);
	Screen output;
	output.position = float4(corner * 2 - 1, 0, 1);
	output.uv = corner;
	return output;
}

[shader("fragment")]
float4 composite_fragment(Screen input) : SV_Target {
	float4 settings = push.view[0].settings;
	uint side = input.uv.x < 0.5 ? 0 : 1;
	float2 local = float2(input.uv.x * 2 - side, input.uv.y);
	uint eye = settings.y > 0.5 ? 1 - side : side;

	float vignette = 1;
	if (settings.x > 0.5) {
		float2 centred = local * 2 - 1;
		float radius2 = dot(centred, centred);
		float2 distorted = centred * (1 + LENS_K1 * radius2 + LENS_K2 * radius2 * radius2) / (1 + LENS_K1 + LENS_K2);
		if (any(abs(distorted) > 1)) {
			return float4(0, 0, 0, 1);
		}
		local = distorted * 0.5 + 0.5;
		vignette = saturate(1.25 - 0.45 * radius2);
	}

	Texture2DArray<float4> eye_images = push.eye_images;
	float3 colour = eye_images.SampleLevel(push.sampler, float3(local, eye), 0).rgb * vignette;
	colour = saturate(colour * (2.51 * colour + 0.03) / (colour * (2.43 * colour + 0.59) + 0.14));
	return float4(colour, 1);
}
