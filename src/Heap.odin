package Valhalla

import "base:runtime"
import "core:log"
import vk "vendor:vulkan"

Heap_Error :: enum {
	None,
	Heap_Too_Small,
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
	buffer:  Host_Buffer,
	address: vk.DeviceAddress,
	size:    vk.DeviceSize,
}

@(private = "file")
Slot_Pool :: struct {
	first: u32,
	free:  [dynamic]u32,
}

@(private = "file")
Descriptor_Heap :: struct {
	resource:     Heap_Storage,
	sampler:      Heap_Storage,
	buffers:      Slot_Pool,
	images:       Slot_Pool,
	samplers:     Slot_Pool,
	null_buffer:  Buffer,
	null_image:   Image,
	null_view:    vk.ImageViewCreateInfo,
	null_sampler: Sampler,
}

@(private = "file")
heap: Descriptor_Heap

@(private)
null_buffer_index :: proc() -> u32 {
	return heap.buffers.first
}

@(private)
null_image_index :: proc() -> u32 {
	return heap.images.first
}

@(private)
null_sampler_index :: proc() -> u32 {
	return heap.samplers.first
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
	slot := take_slot(&heap.buffers, "buffer") or_return
	index := heap.buffers.first + slot
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
		append(&heap.buffers.free, slot)
		return .Descriptor_Write_Failed
	}
	buffer.heap_index = index
	return nil
}

@(private)
release_buffer_slot :: proc(buffer: ^Buffer) {
	give_back_slot(&heap.buffers, buffer.heap_index)
	buffer.heap_index = 0
}

@(private)
@(require_results)
acquire_image_slots :: proc(image: ^Image, view_info: ^vk.ImageViewCreateInfo) -> Error {
	if image.usage & {.SAMPLED, .STORAGE} == {} || image.aspect == {.DEPTH, .STENCIL} {
		return nil
	}
	pair := take_slot(&heap.images, "image") or_return
	index := heap.images.first + 2 * pair
	sampled_view := view_info if .SAMPLED in image.usage else &heap.null_view
	storage_view := view_info if .STORAGE in image.usage else &heap.null_view
	if !write_image_descriptor(sampled_view, .SAMPLED_IMAGE, index) || !write_image_descriptor(storage_view, .STORAGE_IMAGE, index + 1) {
		append(&heap.images.free, pair)
		return .Descriptor_Write_Failed
	}
	image.heap_index = index
	return nil
}

@(private)
release_image_slots :: proc(image: ^Image) {
	if image.heap_index > heap.images.first {
		append(&heap.images.free, (image.heap_index - heap.images.first) / 2)
	}
	image.heap_index = 0
}

@(private)
@(require_results)
acquire_sampler_slot :: proc(sampler: ^Sampler, info: ^vk.SamplerCreateInfo) -> Error {
	slot := take_slot(&heap.samplers, "sampler") or_return
	index := heap.samplers.first + slot
	destination := heap_destination(heap.sampler, index, device.heap_properties.samplerDescriptorSize)
	if res := vk.WriteSamplerDescriptorsEXT(device.handle, 1, info, &destination); res != .SUCCESS {
		log.errorf("Failed to write a sampler descriptor: %v", res)
		append(&heap.samplers.free, slot)
		return .Descriptor_Write_Failed
	}
	sampler.heap_index = index
	return nil
}

@(private)
release_sampler_slot :: proc(sampler: ^Sampler) {
	give_back_slot(&heap.samplers, sampler.heap_index)
	sampler.heap_index = 0
}

@(private = "file")
write_image_descriptor :: proc(view: ^vk.ImageViewCreateInfo, type: vk.DescriptorType, index: u32) -> bool {
	image_info: vk.ImageDescriptorInfoEXT = {
		sType  = .IMAGE_DESCRIPTOR_INFO_EXT,
		pView  = view,
		layout = .GENERAL,
	}
	info: vk.ResourceDescriptorInfoEXT = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		type = type,
		data = {pImage = &image_info},
	}
	return write_resource_descriptor(&info, index, device.heap_properties.imageDescriptorSize)
}

@(private = "file")
write_resource_descriptor :: proc(info: ^vk.ResourceDescriptorInfoEXT, index: u32, descriptor_size: vk.DeviceSize) -> bool {
	destination := heap_destination(heap.resource, index, descriptor_size)
	if res := vk.WriteResourceDescriptorsEXT(device.handle, 1, info, &destination); res != .SUCCESS {
		log.errorf("Failed to write a %v descriptor: %v", info.type, res)
		return false
	}
	return true
}

@(private = "file")
heap_destination :: proc(storage: Heap_Storage, index: u32, descriptor_size: vk.DeviceSize) -> vk.HostAddressRangeEXT {
	return {address = &storage.buffer.allocation.mapped[vk.DeviceSize(index) * descriptor_size], size = int(descriptor_size)}
}

@(private = "file")
make_slot_pool :: proc(first: u32, count: int) -> Slot_Pool {
	pool := Slot_Pool {
		first = first,
		free  = make([dynamic]u32, count),
	}
	for &slot, index in pool.free {
		slot = u32(count - 1 - index)
	}
	return pool
}

@(private = "file")
@(require_results)
take_slot :: proc(pool: ^Slot_Pool, kind: string) -> (slot: u32, err: Error) {
	if len(pool.free) == 0 {
		log.errorf("The descriptor heap is out of %v slots (%v)", kind, cap(pool.free))
		return 0, .Heap_Full
	}
	return pop(&pool.free), nil
}

@(private = "file")
give_back_slot :: proc(pool: ^Slot_Pool, index: u32) {
	if index > pool.first {
		append(&pool.free, index - pool.first)
	}
}

@(private = "file")
@(require_results)
make_heap_storage :: proc(size: vk.DeviceSize) -> (storage: Heap_Storage, err: Error) {
	storage.buffer = make_host_buffer(size, {.DESCRIPTOR_HEAP_EXT, .SHADER_DEVICE_ADDRESS}) or_return
	storage.address = buffer_address(storage.buffer.handle)
	storage.size = size
	return
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

	heap.resource = make_heap_storage(resource_size) or_return
	heap.sampler = make_heap_storage(sampler_size) or_return
	heap.buffers = make_slot_pool(u32(buffer_base / buffer_size), MAX_HEAP_BUFFERS)
	heap.images = make_slot_pool(u32(image_base / image_size), MAX_HEAP_IMAGES)
	heap.samplers = make_slot_pool(u32(sampler_base / sampler_descriptor_size), MAX_HEAP_SAMPLERS)

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
	command_buffer := staging_commands() or_return
	emit_clear(command_buffer, {image = heap.null_image})
	heap.null_sampler = make_sampler() or_return
	log.infof("Descriptor heaps: resource %v KiB, sampler %v KiB", resource_size / 1024, sampler_size / 1024)
	return nil
}

@(private)
close_descriptor_heap :: proc() {
	if heap.resource.buffer.handle == 0 {
		return
	}
	delete_image(&heap.null_image)
	delete_buffer(&heap.null_buffer)
	destroy_host_buffer(&heap.resource.buffer)
	destroy_host_buffer(&heap.sampler.buffer)
	delete(heap.buffers.free)
	delete(heap.images.free)
	delete(heap.samplers.free)
	heap = {}
}
