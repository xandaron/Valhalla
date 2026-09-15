#define DECLARE_RESOURCES(PC)                                                              \
	struct ResourceAccess {                                                                \
		property StructuredBuffer<Vertex> Vertices { get { return PC.resources.Vertices; } }       \
		property StructuredBuffer<UniformData> Uniforms { get { return PC.resources.Uniforms; } }  \
		property StructuredBuffer<InstanceInfo> Instances { get { return PC.resources.Instances; } } \
		property StructuredBuffer<float4x4> Bones { get { return PC.resources.Bones; } }           \
		property StructuredBuffer<float4x4> Transforms { get { return PC.resources.Transforms; } } \
		property RWStructuredBuffer<float4x4> TransformsRW { get { return PC.resources.TransformsRW; } } \
		property StructuredBuffer<Light> Lights { get { return PC.resources.Lights; } }            \
		property StructuredBuffer<uint> TextureIndices { get { return PC.resources.TextureIndices; } } \
		property TextureCubeArray ShadowMap { get { return PC.resources.ShadowMap; } }             \
		property Texture2D SceneDepth { get { return PC.resources.SceneDepth; } }                  \
		property RWTexture2D<float4> RenderedImage { get { return PC.resources.RenderedImage; } }  \
		property RWTexture2D<float4> ProcessedImage { get { return PC.resources.ProcessedImage; } } \
		property SamplerState LinearSampler { get { return PC.resources.LinearSampler; } }         \
		property SamplerState AnisotropicSampler { get { return PC.resources.AnisotropicSampler; } } \
	};                                                                                     \
	static const ResourceAccess Resources = {};
