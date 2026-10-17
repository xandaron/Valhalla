package Valhalla

import "core:log"
import vk "vendor:vulkan"

Filter :: vk.Filter

Mipmap_Mode :: vk.SamplerMipmapMode

Address_Mode :: vk.SamplerAddressMode

Border_Colour :: vk.BorderColor

LOD_CLAMP_NONE :: vk.LOD_CLAMP_NONE

Sampler_Error :: enum {
	None,
	Unsupported_Anisotropy,
	Unsupported_Lod_Bias,
	Invalid_Lod_Range,
}

Sampler :: struct {
	heap_index: u32,
}

@(require_results)
make_sampler :: proc(
	filter := Filter.LINEAR,
	mipmap_mode := Mipmap_Mode.LINEAR,
	address_mode := Address_Mode.REPEAT,
	anisotropy: f32 = 1,
	compare_op: Maybe(Compare_Op) = nil,
	min_lod: f32 = 0,
	max_lod: f32 = LOD_CLAMP_NONE,
	lod_bias: f32 = 0,
	border_colour := Border_Colour.FLOAT_TRANSPARENT_BLACK,
) -> (
	sampler: Sampler,
	err: Error,
) {
	assert(initialised, "Valhalla.init must be called before make_sampler")
	limits := device.properties.limits
	if anisotropy < 1 || anisotropy > limits.maxSamplerAnisotropy {
		log.errorf("Sampler anisotropy must be between 1 and the device's %v, got %v", limits.maxSamplerAnisotropy, anisotropy)
		return {}, .Unsupported_Anisotropy
	}
	if abs(lod_bias) > limits.maxSamplerLodBias {
		log.errorf("Sampler LOD bias must be within the device's ±%v, got %v", limits.maxSamplerLodBias, lod_bias)
		return {}, .Unsupported_Lod_Bias
	}
	if min_lod < 0 || min_lod > max_lod {
		log.errorf("Sampler LOD range %v to %v is invalid", min_lod, max_lod)
		return {}, .Invalid_Lod_Range
	}
	compare, has_compare := compare_op.?
	info: vk.SamplerCreateInfo = {
		sType            = .SAMPLER_CREATE_INFO,
		magFilter        = filter,
		minFilter        = filter,
		mipmapMode       = mipmap_mode,
		addressModeU     = address_mode,
		addressModeV     = address_mode,
		addressModeW     = address_mode,
		mipLodBias       = lod_bias,
		anisotropyEnable = b32(anisotropy > 1),
		maxAnisotropy    = anisotropy,
		compareEnable    = b32(has_compare),
		compareOp        = compare,
		minLod           = min_lod,
		maxLod           = max_lod,
		borderColor      = border_colour,
	}
	acquire_sampler_slot(&sampler, &info) or_return
	return
}

delete_sampler :: proc(sampler: ^Sampler) {
	if sampler.heap_index != 0 {
		bury(sampler^)
	}
	sampler^ = {}
}
