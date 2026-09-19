import "Buffers.slang";

Texture2D textureAt(uint index) {
	DescriptorHandle<Texture2D> d = { index };
	return d;
}

extension HeapIndices {
	property TextureCubeArray ShadowMap {
		get {
			DescriptorHandle<TextureCubeArray> d = { shadowMap };
			return d;
		}
	}

	property Texture2D SceneDepth {
		get {
			DescriptorHandle<Texture2D> d = { sceneDepth };
			return d;
		}
	}

	property RWTexture2D<float4> RenderedImage {
		get {
			DescriptorHandle<RWTexture2D<float4>> d = { renderedImage };
			return d;
		}
	}

	property RWTexture2D<float4> ProcessedImage {
		get {
			DescriptorHandle<RWTexture2D<float4>> d = { processedImage };
			return d;
		}
	}

	property RWTexture2D<float4> UiImage {
		get {
			DescriptorHandle<RWTexture2D<float4>> d = { uiImage };
			return d;
		}
	}

	property SamplerState LinearSampler {
		get {
			DescriptorHandle<SamplerState> d = { linearSampler };
			return d;
		}
	}

	property SamplerState AnisotropicSampler {
		get {
			DescriptorHandle<SamplerState> d = { anisotropicSampler };
			return d;
		}
	}
}
