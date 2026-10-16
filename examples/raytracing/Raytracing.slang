import Valhalla;

struct Vertex {
	float4 position;
	float4 normal;
};

struct Object {
	float4x4 model;
	float4 colour;
	float4 material;
	uint base_vertex;
	uint first_index;
	uint checker;
	uint pad;
};

struct Frame {
	float4x4 inverse_view_projection;
	float4 camera;
	float4 sun;
};

struct Push {
	ValhallaHeader header;
	uint2 scene;
	DescriptorHandle<StructuredBuffer<Vertex>> vertices;
	DescriptorHandle<StructuredBuffer<uint>> indices;
	DescriptorHandle<StructuredBuffer<Object>> objects;
	DescriptorHandle<StructuredBuffer<Frame>> frame;
	DescriptorHandle<RWTexture2D<float4>> output;
	uint encode;
};

[[vk::push_constant]]
ConstantBuffer<Push> push;

static const uint MAX_BOUNCES = 4;
static const float3 SUN_COLOUR = float3(1.0, 0.94, 0.85);

struct Hit {
	bool found;
	float distance;
	float3 position;
	float3 normal;
	uint object;
};

Hit trace(float3 origin, float3 direction) {
	RaytracingAccelerationStructure scene = valhalla_acceleration_structure(push.scene);
	RayDesc ray;
	ray.Origin = origin;
	ray.Direction = direction;
	ray.TMin = 0.001;
	ray.TMax = 1000;
	RayQuery<RAY_FLAG_FORCE_OPAQUE> query;
	query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, ray);
	query.Proceed();

	Hit hit;
	hit.found = query.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
	if (!hit.found) {
		return hit;
	}
	hit.distance = query.CommittedRayT();
	hit.position = origin + direction * hit.distance;
	hit.object = query.CommittedInstanceID();
	Object object = push.objects[hit.object];
	uint first = object.first_index + query.CommittedPrimitiveIndex() * 3;
	float2 barycentrics = query.CommittedTriangleBarycentrics();
	float3 n0 = push.vertices[object.base_vertex + push.indices[first]].normal.xyz;
	float3 n1 = push.vertices[object.base_vertex + push.indices[first + 1]].normal.xyz;
	float3 n2 = push.vertices[object.base_vertex + push.indices[first + 2]].normal.xyz;
	float3 normal = n0 * (1 - barycentrics.x - barycentrics.y) + n1 * barycentrics.x + n2 * barycentrics.y;
	hit.normal = normalize(mul((float3x3)object.model, normal));
	if (dot(hit.normal, direction) > 0) {
		hit.normal = -hit.normal;
	}
	return hit;
}

bool shadowed(float3 origin, float3 direction) {
	RaytracingAccelerationStructure scene = valhalla_acceleration_structure(push.scene);
	RayDesc ray;
	ray.Origin = origin;
	ray.Direction = direction;
	ray.TMin = 0.001;
	ray.TMax = 1000;
	RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> query;
	query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, ray);
	query.Proceed();
	return query.CommittedStatus() != COMMITTED_NOTHING;
}

float3 sky(float3 direction, float3 to_sun) {
	float height = saturate(direction.y * 0.5 + 0.5);
	float3 colour = lerp(float3(0.75, 0.8, 0.85), float3(0.25, 0.45, 0.85), height);
	float sun = pow(saturate(dot(direction, to_sun)), 800) * 40;
	return colour + SUN_COLOUR * sun;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void raytrace(uint3 thread : SV_DispatchThreadID) {
	RWTexture2D<float4> output = push.output;
	uint width, height;
	output.GetDimensions(width, height);
	if (thread.x >= width || thread.y >= height) {
		return;
	}
	Frame frame = push.frame[0];
	float2 ndc = (float2(thread.xy) + 0.5) / float2(width, height) * 2 - 1;
	float4 target = mul(frame.inverse_view_projection, float4(ndc, 1, 1));
	float3 origin = frame.camera.xyz;
	float3 direction = normalize(target.xyz / target.w - origin);
	float3 to_sun = -normalize(frame.sun.xyz);

	float3 colour = 0;
	float3 throughput = 1;
	for (uint bounce = 0; bounce < MAX_BOUNCES; bounce++) {
		Hit hit = trace(origin, direction);
		if (!hit.found) {
			colour += throughput * sky(direction, to_sun);
			break;
		}
		Object object = push.objects[hit.object];
		float3 albedo = object.colour.rgb;
		if (object.checker != 0) {
			float2 cell = floor(hit.position.xz);
			albedo *= fmod(abs(cell.x + cell.y), 2) < 1 ? 1 : 0.35;
		}
		float reflectivity = object.material.x;
		float3 lift = hit.position + hit.normal * 0.002;
		float diffuse = saturate(dot(hit.normal, to_sun));
		float lit = diffuse > 0 && !shadowed(lift, to_sun) ? diffuse : 0;
		float3 ambient = lerp(float3(0.06, 0.05, 0.05), float3(0.12, 0.16, 0.24), hit.normal.y * 0.5 + 0.5);
		float3 direct = albedo * (ambient + SUN_COLOUR * frame.sun.w * lit);
		colour += throughput * (1 - reflectivity) * direct;
		if (reflectivity <= 0) {
			break;
		}
		throughput *= reflectivity * lerp(float3(1, 1, 1), albedo, object.material.y);
		origin = lift;
		direction = reflect(direction, hit.normal);
	}

	colour = saturate(colour * (2.51 * colour + 0.03) / (colour * (2.43 * colour + 0.59) + 0.14));
	if (push.encode != 0) {
		colour = valhalla_linear_to_srgb(colour);
	}
	output[thread.xy] = float4(colour, 1);
}
