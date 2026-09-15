__exported import "Vertex.slang";

struct UniformData {
	float4x4 projection;
	float4x4 viewProjection;
	float3 cameraPosition;
	uint lightCount;
	float ambientLight;
};

struct InstanceInfo {
	float4x4 model;
	uint boneOffset;
};

struct Light {
	float3 position;
	float3 lumens;
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

struct HeapIndices {
	uint vertexBuffer;
	uint uniformBuffer;
	uint instanceBuffer;
	uint boneBuffer;
	uint transformBuffer;
	uint positionBuffer;
	uint lightBuffer;
	uint textureIndexBuffer;
	uint shadowMap;
	uint sceneDepth;
	uint renderedImage;
	uint processedImage;
	uint linearSampler;
	uint anisotropicSampler;

	property StructuredBuffer<Vertex> Vertices {
		get {
			DescriptorHandle<StructuredBuffer<Vertex>> d = { vertexBuffer };
			return d;
		}
	}

	property StructuredBuffer<UniformData> Uniforms {
		get {
			DescriptorHandle<StructuredBuffer<UniformData>> d = { uniformBuffer };
			return d;
		}
	}

	property StructuredBuffer<InstanceInfo> Instances {
		get {
			DescriptorHandle<StructuredBuffer<InstanceInfo>> d = { instanceBuffer };
			return d;
		}
	}

	property StructuredBuffer<float4x4> Bones {
		get {
			DescriptorHandle<StructuredBuffer<float4x4>> d = { boneBuffer };
			return d;
		}
	}

	property StructuredBuffer<float4x4> Transforms {
		get {
			DescriptorHandle<StructuredBuffer<float4x4>> d = { transformBuffer };
			return d;
		}
	}

	property RWStructuredBuffer<float4x4> TransformsRW {
		get {
			DescriptorHandle<RWStructuredBuffer<float4x4>> d = { transformBuffer };
			return d;
		}
	}

	property StructuredBuffer<float4> Positions {
		get {
			DescriptorHandle<StructuredBuffer<float4>> d = { positionBuffer };
			return d;
		}
	}

	property RWStructuredBuffer<float4> PositionsRW {
		get {
			DescriptorHandle<RWStructuredBuffer<float4>> d = { positionBuffer };
			return d;
		}
	}

	property StructuredBuffer<Light> Lights {
		get {
			DescriptorHandle<StructuredBuffer<Light>> d = { lightBuffer };
			return d;
		}
	}

	property StructuredBuffer<uint> TextureIndices {
		get {
			DescriptorHandle<StructuredBuffer<uint>> d = { textureIndexBuffer };
			return d;
		}
	}
};
