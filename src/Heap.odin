package Valhalla

import "base:runtime"
import "core:log"
import vk "vendor:vulkan"

Heap_Error :: enum {
	None,
	Heap_Too_Small,
	Heap_Creation_Failed,
	Heap_Full,
	Descriptor_Write_Failed,
}

@(private)
HEAP_IMAGE_TAG :: u32(1) << 31

@(private)
HEAP_SAMPLER_TAG :: u32(1) << 30

@(private = "file")
MAX_HEAP_BUFFERS :: 16384

@(private = "file")
MAX_HEAP_IMAGES :: 16384

@(private = "file")
MAX_HEAP_SAMPLERS :: 256

@(private = "file")
Heap_Storage :: struct {
	handle:     vk.Buffer,
	allocation: Allocation,
	address:    vk.DeviceAddress,
	size:       vk.DeviceSize,
}

@(private = "file")
Descriptor_Heap :: struct {
	resource:     Heap_Storage,
	sampler:      Heap_Storage,
	buffer_first:  u32,
	image_first:   u32,
	sampler_first: u32,
	free_buffers:  [dynamic]u32,
	free_images:   [dynamic]u32,
	free_samplers: [dynamic]u32,
	null_buffer:   Buffer,
	null_image:    Image,
	null_view:     vk.ImageViewCreateInfo,
	null_sampler:  Sampler,
}

@(private = "file")
heap: Descriptor_Heap

@(private)
null_buffer_index :: proc() -> u32 {
	return heap.buffer_first
}

@(private)
null_image_index :: proc() -> u32 {
	return heap.image_first
}

@(private)
null_sampler_index :: proc() -> u32 {
	return heap.sampler_first
}

@(private)
bind_descriptor_heaps :: proc(command_buffer: vk.CommandBuffer) {
	resource_info: vk.BindHeapInfoEXT = {
		sType = .BIND_HEAP_INFO_EXT,
		heapRange = {address = heap.resource.address, size = heap.resource.size},
		reservedRangeSize = device.heap_properties.minResourceHeapReservedRange,
	}
	vk.CmdBindResourceHeapEXT(command_buffer, &resource_info)
	sampler_info: vk.BindHeapInfoEXT = {
		sType = .BIND_HEAP_INFO_EXT,
		heapRange = {address = heap.sampler.address, size = heap.sampler.size},
		reservedRangeSize = device.heap_properties.minSamplerHeapReservedRange,
	}
	vk.CmdBindSamplerHeapEXT(command_buffer, &sampler_info)
}

@(private)
@(require_results)
acquire_buffer_slot :: proc(buffer: ^Buffer) -> Error {
	if .STORAGE_BUFFER not_in buffer.usage {
		return nil
	}
	if len(heap.free_buffers) == 0 {
		log.errorf("The descriptor heap is out of buffer slots (%v)", MAX_HEAP_BUFFERS)
		return .Heap_Full
	}
	index := heap.buffer_first + pop(&heap.free_buffers)
	range: vk.DeviceAddressRangeEXT = {
		address = buffer.address,
		size    = buffer.size,
	}
	info: vk.ResourceDescriptorInfoEXT = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		type = .STORAGE_BUFFER,
		data = {pAddressRange = &range},
	}
	if !write_resource_descriptor(&info, index, device.heap_properties.bufferDescriptorSize) {
		append(&heap.free_buffers, index - heap.buffer_first)
		return .Descriptor_Write_Failed
	}
	buffer.heap_index = index
	return nil
}

@(private)
release_buffer_slot :: proc(buffer: ^Buffer) {
	if buffer.heap_index > heap.buffer_first {
		append(&heap.free_buffers, buffer.heap_index - heap.buffer_first)
	}
	buffer.heap_index = 0
}

@(private)
@(require_results)
acquire_image_slots :: proc(image: ^Image, view_info: ^vk.ImageViewCreateInfo) -> Error {
	if image.usage & {.SAMPLED, .STORAGE} == {} || image.aspect == {.DEPTH, .STENCIL} {
		return nil
	}
	if len(heap.free_images) == 0 {
		log.errorf("The descriptor heap is out of image slots (%v)", MAX_HEAP_IMAGES)
		return .Heap_Full
	}
	pair := pop(&heap.free_images)
	index := heap.image_first + 2 * pair
	image_size := device.heap_properties.imageDescriptorSize

	sampled_view := view_info if .SAMPLED in image.usage else &heap.null_view
	sampled_image: vk.ImageDescriptorInfoEXT = {
		sType  = .IMAGE_DESCRIPTOR_INFO_EXT,
		pView  = sampled_view,
		layout = .GENERAL,
	}
	sampled: vk.ResourceDescriptorInfoEXT = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		type = .SAMPLED_IMAGE,
		data = {pImage = &sampled_image},
	}
	storage_view := view_info if .STORAGE in image.usage else &heap.null_view
	storage_image: vk.ImageDescriptorInfoEXT = {
		sType  = .IMAGE_DESCRIPTOR_INFO_EXT,
		pView  = storage_view,
		layout = .GENERAL,
	}
	storage: vk.ResourceDescriptorInfoEXT = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		type = .STORAGE_IMAGE,
		data = {pImage = &storage_image},
	}
	if !write_resource_descriptor(&sampled, index, image_size) || !write_resource_descriptor(&storage, index + 1, image_size) {
		append(&heap.free_images, pair)
		return .Descriptor_Write_Failed
	}
	image.heap_index = index
	return nil
}

@(private)
release_image_slots :: proc(image: ^Image) {
	if image.heap_index > heap.image_first {
		append(&heap.free_images, (image.heap_index - heap.image_first) / 2)
	}
	image.heap_index = 0
}

@(private)
@(require_results)
acquire_sampler_slot :: proc(sampler: ^Sampler, info: ^vk.SamplerCreateInfo) -> Error {
	if len(heap.free_samplers) == 0 {
		log.errorf("The descriptor heap is out of sampler slots (%v)", MAX_HEAP_SAMPLERS)
		return .Heap_Full
	}
	index := heap.sampler_first + pop(&heap.free_samplers)
	descriptor_size := device.heap_properties.samplerDescriptorSize
	destination: vk.HostAddressRangeEXT = {
		address = &heap.sampler.allocation.mapped[vk.DeviceSize(index) * descriptor_size],
		size    = int(descriptor_size),
	}
	if res := vk.WriteSamplerDescriptorsEXT(device.handle, 1, info, &destination); res != .SUCCESS {
		log.errorf("Failed to write a sampler descriptor: %v", res)
		append(&heap.free_samplers, index - heap.sampler_first)
		return .Descriptor_Write_Failed
	}
	sampler.heap_index = index
	return nil
}

@(private)
release_sampler_slot :: proc(sampler: ^Sampler) {
	if sampler.heap_index > heap.sampler_first {
		append(&heap.free_samplers, sampler.heap_index - heap.sampler_first)
	}
	sampler.heap_index = 0
}

@(private = "file")
write_resource_descriptor :: proc(info: ^vk.ResourceDescriptorInfoEXT, index: u32, descriptor_size: vk.DeviceSize) -> bool {
	destination: vk.HostAddressRangeEXT = {
		address = &heap.resource.allocation.mapped[vk.DeviceSize(index) * descriptor_size],
		size    = int(descriptor_size),
	}
	if res := vk.WriteResourceDescriptorsEXT(device.handle, 1, info, &destination); res != .SUCCESS {
		log.errorf("Failed to write a %v descriptor: %v", info.type, res)
		return false
	}
	return true
}

@(private = "file")
@(require_results)
make_heap_storage :: proc(size: vk.DeviceSize) -> (storage: Heap_Storage, err: Error) {
	usage_info: vk.BufferUsageFlags2CreateInfo = {
		sType = .BUFFER_USAGE_FLAGS_2_CREATE_INFO,
		usage = {.DESCRIPTOR_HEAP_EXT, .SHADER_DEVICE_ADDRESS},
	}
	buffer_info: vk.BufferCreateInfo = {
		sType       = .BUFFER_CREATE_INFO,
		pNext       = &usage_info,
		size        = size,
		usage       = {.SHADER_DEVICE_ADDRESS},
		sharingMode = .EXCLUSIVE,
	}
	if res := vk.CreateBuffer(device.handle, &buffer_info, nil, &storage.handle); res != .SUCCESS {
		log.errorf("Failed to create a descriptor heap: %v", res)
		return {}, .Heap_Creation_Failed
	}
	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device.handle, storage.handle, &requirements)
	allocation, allocate_err := allocate_memory(requirements, {.HOST_VISIBLE, .HOST_COHERENT}, .Linear)
	if allocate_err != nil {
		vk.DestroyBuffer(device.handle, storage.handle, nil)
		return {}, allocate_err
	}
	storage.allocation = allocation
	if res := vk.BindBufferMemory(device.handle, storage.handle, allocation.memory, allocation.offset); res != .SUCCESS {
		log.errorf("Failed to bind descriptor heap memory: %v", res)
		destroy_heap_storage(&storage)
		return {}, .Heap_Creation_Failed
	}
	storage.size = size
	address_info: vk.BufferDeviceAddressInfo = {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = storage.handle,
	}
	storage.address = vk.GetBufferDeviceAddress(device.handle, &address_info)
	return
}

@(private = "file")
destroy_heap_storage :: proc(storage: ^Heap_Storage) {
	if storage.handle != 0 {
		vk.DestroyBuffer(device.handle, storage.handle, nil)
	}
	free_memory(&storage.allocation)
	storage^ = {}
}

@(private)
@(require_results)
open_descriptor_heap :: proc() -> (err: Error) {
	properties := device.heap_properties
	buffer_size := properties.bufferDescriptorSize
	image_size := properties.imageDescriptorSize

	buffer_base := round_up(properties.minResourceHeapReservedRange, buffer_size)
	image_base := round_up(buffer_base + MAX_HEAP_BUFFERS * buffer_size, image_size)
	resource_size := round_up(image_base + 2 * MAX_HEAP_IMAGES * image_size, properties.resourceHeapAlignment)
	if resource_size > properties.maxResourceHeapSize {
		log.errorf("The resource heap needs %v bytes but the device allows %v", resource_size, properties.maxResourceHeapSize)
		return .Heap_Too_Small
	}
	sampler_descriptor_size := properties.samplerDescriptorSize
	sampler_base := round_up(round_up(properties.minSamplerHeapReservedRange, properties.samplerDescriptorAlignment), sampler_descriptor_size)
	sampler_size := round_up(sampler_base + MAX_HEAP_SAMPLERS * sampler_descriptor_size, properties.samplerHeapAlignment)
	if sampler_size > properties.maxSamplerHeapSize {
		log.errorf("The sampler heap needs %v bytes but the device allows %v", sampler_size, properties.maxSamplerHeapSize)
		return .Heap_Too_Small
	}

	heap.buffer_first = u32(buffer_base / buffer_size)
	heap.image_first = u32(image_base / image_size)
	heap.sampler_first = u32(sampler_base / sampler_descriptor_size)
	heap.resource = make_heap_storage(resource_size) or_return
	heap.sampler = make_heap_storage(sampler_size) or_return
	heap.free_buffers = make([dynamic]u32, 0, MAX_HEAP_BUFFERS)
	for slot := MAX_HEAP_BUFFERS - 1; slot >= 0; slot -= 1 {
		append(&heap.free_buffers, u32(slot))
	}
	heap.free_images = make([dynamic]u32, 0, MAX_HEAP_IMAGES)
	for pair := MAX_HEAP_IMAGES - 1; pair >= 0; pair -= 1 {
		append(&heap.free_images, u32(pair))
	}
	heap.free_samplers = make([dynamic]u32, 0, MAX_HEAP_SAMPLERS)
	for slot := MAX_HEAP_SAMPLERS - 1; slot >= 0; slot -= 1 {
		append(&heap.free_samplers, u32(slot))
	}

	heap.null_buffer = make_empty_buffer(16, Buffer_Settings{usage = {.Storage}, memory = .Host_Visible}) or_return
	runtime.mem_zero(heap.null_buffer.mapped, 16)
	heap.null_image = make_empty_image(.R8G8B8A8_UNORM, {1, 1, 1}, kind = .Generic) or_return
	heap.null_view = {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = heap.null_image.handle,
		viewType = .D2,
		format = heap.null_image.format,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	clear_null_image() or_return
	heap.null_sampler = make_sampler() or_return
	log.infof("Descriptor heaps: resource %v KiB, sampler %v KiB", resource_size / 1024, sampler_size / 1024)
	return nil
}

@(private = "file")
@(require_results)
clear_null_image :: proc() -> Error {
	command_buffer := staging_commands() or_return
	black: vk.ClearColorValue
	range: vk.ImageSubresourceRange = {
		aspectMask = {.COLOR},
		levelCount = 1,
		layerCount = 1,
	}
	vk.CmdClearColorImage(command_buffer, heap.null_image.handle, .GENERAL, &black, 1, &range)
	return nil
}

@(private)
close_descriptor_heap :: proc() {
	if heap.resource.handle == 0 {
		return
	}
	delete_image(&heap.null_image)
	delete_buffer(&heap.null_buffer)
	destroy_heap_storage(&heap.resource)
	destroy_heap_storage(&heap.sampler)
	delete(heap.free_buffers)
	delete(heap.free_images)
	delete(heap.free_samplers)
	heap = {}
}

@(private = "file")
round_up :: proc(value, multiple: vk.DeviceSize) -> vk.DeviceSize {
	if multiple == 0 {
		return value
	}
	return (value + multiple - 1) / multiple * multiple
}
