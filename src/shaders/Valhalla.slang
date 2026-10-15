module Valhalla;

public static const uint VALHALLA_IMAGE_TAG = 0x80000000u;
public static const uint VALHALLA_SAMPLER_TAG = 0x40000000u;
static const uint VALHALLA_TAGS = VALHALLA_IMAGE_TAG | VALHALLA_SAMPLER_TAG;
static const uint VALHALLA_HEADER_WORDS = 4;

public struct ValhallaHeader {
	public uint* table;
	public uint draw_data;
	public uint reserved;
};

uint valhalla_entry(ValhallaHeader header, uint index, uint tag, uint fallback) {
	uint* table = header.table;
	uint entry = index < table[0] ? table[VALHALLA_HEADER_WORDS + index] : table[fallback];
	uint checked = (entry & VALHALLA_TAGS) == tag ? entry : table[fallback];
	return checked & ~VALHALLA_TAGS;
}

public uint valhalla_buffer_index(ValhallaHeader header, uint index) {
	return valhalla_entry(header, index, 0, 1);
}

public uint valhalla_image_index(ValhallaHeader header, uint index) {
	return valhalla_entry(header, index, VALHALLA_IMAGE_TAG, 2);
}

public uint valhalla_sampler_index(ValhallaHeader header, uint index) {
	return valhalla_entry(header, index, VALHALLA_SAMPLER_TAG, 3);
}

public StructuredBuffer<T> valhalla_buffer<T>(ValhallaHeader header, uint index) {
	DescriptorHandle<StructuredBuffer<T>> handle = { valhalla_buffer_index(header, index) };
	return handle;
}

public RWStructuredBuffer<T> valhalla_rw_buffer<T>(ValhallaHeader header, uint index) {
	DescriptorHandle<RWStructuredBuffer<T>> handle = { valhalla_buffer_index(header, index) };
	return handle;
}

public DescriptorHandle<T> valhalla_sampled<T : IOpaqueDescriptor>(ValhallaHeader header, uint index) {
	DescriptorHandle<T> handle = { valhalla_image_index(header, index) };
	return handle;
}

public DescriptorHandle<T> valhalla_storage<T : IOpaqueDescriptor>(ValhallaHeader header, uint index) {
	DescriptorHandle<T> handle = { valhalla_image_index(header, index) + 1 };
	return handle;
}

public SamplerState valhalla_sampler(ValhallaHeader header, uint index) {
	DescriptorHandle<SamplerState> handle = { valhalla_sampler_index(header, index) };
	return handle;
}

public SamplerComparisonState valhalla_comparison_sampler(ValhallaHeader header, uint index) {
	DescriptorHandle<SamplerComparisonState> handle = { valhalla_sampler_index(header, index) };
	return handle;
}

public float3 valhalla_srgb_to_linear(float3 colour) {
	return select(colour <= 0.04045, colour / 12.92, pow((colour + 0.055) / 1.055, 2.4));
}

public float3 valhalla_linear_to_srgb(float3 colour) {
	colour = saturate(colour);
	return select(colour <= 0.0031308, colour * 12.92, 1.055 * pow(colour, 1.0 / 2.4) - 0.055);
}
