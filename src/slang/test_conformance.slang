import Valhalla;

struct Bone {
	float3 position;
	float radius;
	float4x4 transform;
	float2 uv;
	uint flags;
};

struct Camera {
	float4x4 view_projection;
	float3 position;
	float exposure;
	float weights[3];
	float2 jitter;
};

struct Push {
	ValhallaHeader header;
	DescriptorHandle<StructuredBuffer<Bone>> bones;
	DescriptorHandle<ConstantBuffer<Camera>> camera;
	DescriptorHandle<Texture2D<float4>> textures[2];
	float3 tint;
	uint mode;
	float4x4 model;
	uint output;
};

[[vk::push_constant]]
ConstantBuffer<Push> push;

void write(float4 value) {
	RWStructuredBuffer<float4> output = valhalla_rw_buffer<float4>(push.header, push.output);
	output[0] = value;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void push_data() {
	write(mul(push.model, float4(push.tint, float(push.mode))));
}

[shader("compute")]
[numthreads(1, 1, 1)]
void structured_buffer() {
	Bone bone = push.bones[0];
	write(mul(bone.transform, float4(bone.position, bone.radius)) + float4(bone.uv, float(bone.flags), 0));
}

[shader("compute")]
[numthreads(1, 1, 1)]
void constant_buffer() {
	write(float4(push.camera->position, push.camera->exposure) + float4(push.camera->jitter, push.camera->weights[1], 0));
}

[shader("compute")]
[numthreads(1, 1, 1)]
void constant_buffer_matrix() {
	write(mul(push.camera->view_projection, float4(1, 2, 3, 4)));
}

float sum(float values[3]) {
	return values[0] + values[1] + values[2];
}

[shader("compute")]
[numthreads(1, 1, 1)]
void constant_buffer_array_argument() {
	write(float4(sum(push.camera->weights)));
}

[shader("fragment")]
float4 discard_fragment(float4 position : SV_Position) : SV_Target {
	if (position.x < push.tint.x) {
		discard;
	}
	return float4(push.tint, 1);
}
