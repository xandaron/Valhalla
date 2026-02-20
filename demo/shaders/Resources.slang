struct Vertex {
	float3 position : POSITION;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	float3 bitangent : BITANGENT;
	float2 uv : TEXCOORD0;
	uint4 bones : BLENDINDICES;
	float4 weights : BLENDWEIGHT;
};

struct UniformData {
	float4x4 projection;
	float4x4 viewProjection;
	uint lightCount;
	float ambientLight;
};

struct InstanceInfo {
	float4x4 model;
	uint boneOffset;
};

struct Light {
	float3 position;
	float3 colourIntensity;
	float dropoff;
	float near;
	float far;
};

enum TextureIndex {
	ALBEDO,
	NORMAL,
	// METALLIC,
	// ROUGHNESS,

	COUNT,
};

// Buffers
StructuredBuffer<Vertex>.Handle vertexBuffer;
StructuredBuffer<uint>.Handle textureIndexBuffer;
ConstantBuffer<UniformData>.Handle uniformBuffer;
StructuredBuffer<InstanceInfo>.Handle instanceBuffer;
StructuredBuffer<float4x4>.Handle boneBuffer;
StructuredBuffer<float4x4>.Handle transformBufferRO;
RWStructuredBuffer<float4x4>.Handle transformBufferRW;
StructuredBuffer<Light>.Handle lightBuffer;

// Images
TextureCubeArray.Handle shadowMap;
Texture2D.Handle sceneDepth;
RWTexture2D.Handle renderedImage;
RWTexture2D.Handle processedImage;
Texture2D.Handle[] images;

// Samplers
SamplerState.Handle noAnisoSampler;
SamplerState.Handle anisoSampler;

// All texture and buffer handles are defined in descriptor set 100.
// [vk::binding(0, 100)]
// __DynamicResource<__DynamicResourceKind.General> resourceHandles[];

// All sampler handles are defined in descriptor set 101.
// [vk::binding(0, 101)]
// __DynamicResource<__DynamicResourceKind.Sampler> samplerHandles[];

// export T getDescriptorFromHandle<T>(DescriptorHandle<T> handle)
// 		where T : IOpaqueDescriptor {
// 	__target_switch {
// 	case spirv:
// 		if (T.kind == DescriptorKind.Sampler)
// 			return samplerHandles[((uint2)handle).x].asOpaqueDescriptor<T>();
// 		else
// 			return resourceHandles[((uint2)handle).x].asOpaqueDescriptor<T>();
// 	default:
// 		return defaultGetDescriptorFromHandle(handle);
// 	}
// }
