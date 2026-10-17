package External

import "core:log"
import "core:math"
import vk "vendor:vulkan"

import Valhalla "../../src"

Push :: struct {
	tint: [4]f32,
}

Raw_Buffer :: struct {
	buffer: Valhalla.Buffer,
	memory: vk.DeviceMemory,
}

Raw_Image :: struct {
	image:  Valhalla.Image,
	memory: vk.DeviceMemory,
}

QUAD_INDICES :: [6]u32{0, 1, 2, 2, 3, 0}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("External failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "External resources and raw commands") or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(window) or_return
	defer Valhalla.delete_surface(&surface)

	indices := make_raw_buffer(size_of(QUAD_INDICES), {.INDEX_BUFFER, .TRANSFER_DST}) or_return
	defer destroy_raw_buffer(&indices)

	target := make_raw_image(surface.format, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}) or_return
	defer destroy_raw_image(&target)
	prepare_raw_image(&target) or_return

	quad := Valhalla.make_shader(
		#load("External.slang"),
		[]string{"vertex_main", "fragment_main"},
		push_type = Push, colour_formats = {0 = target.image.format},
	) or_return
	defer Valhalla.delete_shader(&quad)

	for !Valhalla.should_close(window) {
		Valhalla.poll_events()
		draw_frame(&surface, &quad, indices.buffer, target.image) or_return
		if surface.minimised {
			Valhalla.wait_events()
		}
	}
	return nil
}

draw_frame :: proc(surface: ^Valhalla.Surface, quad: ^Valhalla.Shader, indices: Valhalla.Buffer, target: Valhalla.Image) -> Valhalla.Error {
	frame := Valhalla.make_workload() or_return
	defer Valhalla.delete_workload(&frame)

	index_data := QUAD_INDICES
	upload := Valhalla.raw_commands(&frame)
	vk.CmdUpdateBuffer(upload, indices.handle, 0, size_of(index_data), &index_data)

	seconds := f32(Valhalla.time())
	cleared := Valhalla.clear_image(&frame, target, {0.05, 0.05, 0.08, 1})
	Valhalla.reset_shader(quad)
	Valhalla.set_push_data(quad, Push{tint = {1, 0.75 + 0.25 * math.sin(seconds), 1, 1}})
	Valhalla.bind_shader_index_buffer(quad, indices)
	drawn := Valhalla.bind_shader_colour(quad, cleared)
	Valhalla.draw_indexed(quad, len(QUAD_INDICES))
	Valhalla.bind_shader(&frame, quad^) or_return

	mirror_left_half(Valhalla.raw_commands(&frame), target)

	Valhalla.present(&frame, drawn, surface)
	Valhalla.finalize_workload(&frame) or_return
	execution := Valhalla.execute_workloads(&frame) or_return
	return Valhalla.wait_execution(execution)
}

mirror_left_half :: proc(cmd: vk.CommandBuffer, image: Valhalla.Image) {
	width, height := i32(image.extent.x), i32(image.extent.y)
	region: vk.ImageBlit2 = {
		sType          = .IMAGE_BLIT_2,
		srcSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		srcOffsets     = {{0, 0, 0}, {width / 2, height, 1}},
		dstSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		dstOffsets     = {{width, 0, 0}, {width / 2, height, 1}},
	}
	blit: vk.BlitImageInfo2 = {
		sType          = .BLIT_IMAGE_INFO_2,
		srcImage       = image.handle,
		srcImageLayout = .GENERAL,
		dstImage       = image.handle,
		dstImageLayout = .GENERAL,
		regionCount    = 1,
		pRegions       = &region,
		filter         = .NEAREST,
	}
	vk.CmdBlitImage2(cmd, &blit)
}

// ===[ Raw Vulkan Resources ]==================================================

make_raw_buffer :: proc(#any_int size: int, usage: vk.BufferUsageFlags) -> (raw: Raw_Buffer, err: Valhalla.Error) {
	device := Valhalla.device.handle
	raw.buffer = {
		size    = vk.DeviceSize(size),
		usage   = usage,
		variant = Valhalla.External_Buffer{},
	}
	info: vk.BufferCreateInfo = {
		sType       = .BUFFER_CREATE_INFO,
		size        = raw.buffer.size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	if res := vk.CreateBuffer(device, &info, nil, &raw.buffer.handle); res != .SUCCESS {
		log.errorf("Failed to create the external buffer: %v", res)
		return {}, Valhalla.Buffer_Error.Buffer_Creation_Failed
	}
	defer if err != nil {
		destroy_raw_buffer(&raw)
	}
	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, raw.buffer.handle, &requirements)
	raw.memory = allocate_device_memory(requirements) or_return
	if res := vk.BindBufferMemory(device, raw.buffer.handle, raw.memory, 0); res != .SUCCESS {
		log.errorf("Failed to bind the external buffer's memory: %v", res)
		return raw, Valhalla.Buffer_Error.Buffer_Bind_Failed
	}
	return
}

destroy_raw_buffer :: proc(raw: ^Raw_Buffer) {
	device := Valhalla.device.handle
	if raw.buffer.handle != 0 {
		vk.DestroyBuffer(device, raw.buffer.handle, nil)
	}
	if raw.memory != 0 {
		vk.FreeMemory(device, raw.memory, nil)
	}
	raw^ = {}
}

make_raw_image :: proc(format: Valhalla.Format, size: [3]u32) -> (raw: Raw_Image, err: Valhalla.Error) {
	device := Valhalla.device.handle
	raw.image = {
		format     = format,
		extent     = size,
		layers     = 1,
		mip_levels = 1,
		samples    = {._1},
		aspect     = {.COLOR},
		usage      = {.COLOR_ATTACHMENT, .TRANSFER_SRC, .TRANSFER_DST},
		layout     = .UNDEFINED,
		variant    = Valhalla.External_Image{},
	}
	info: vk.ImageCreateInfo = {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = format,
		extent        = {size.x, size.y, size.z},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = raw.image.usage,
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if res := vk.CreateImage(device, &info, nil, &raw.image.handle); res != .SUCCESS {
		log.errorf("Failed to create the external image: %v", res)
		return {}, Valhalla.Image_Error.Image_Creation_Failed
	}
	defer if err != nil {
		destroy_raw_image(&raw)
	}
	requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, raw.image.handle, &requirements)
	raw.memory = allocate_device_memory(requirements) or_return
	if res := vk.BindImageMemory(device, raw.image.handle, raw.memory, 0); res != .SUCCESS {
		log.errorf("Failed to bind the external image's memory: %v", res)
		return raw, Valhalla.Image_Error.Memory_Bind_Failed
	}
	view_info: vk.ImageViewCreateInfo = {
		sType            = .IMAGE_VIEW_CREATE_INFO,
		image            = raw.image.handle,
		viewType         = .D2,
		format           = format,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	if res := vk.CreateImageView(device, &view_info, nil, &raw.image.view); res != .SUCCESS {
		log.errorf("Failed to create the external image's view: %v", res)
		return raw, Valhalla.Image_Error.View_Creation_Failed
	}
	return
}

prepare_raw_image :: proc(raw: ^Raw_Image) -> Valhalla.Error {
	setup := Valhalla.make_workload("external setup") or_return
	defer Valhalla.delete_workload(&setup)
	barrier: vk.ImageMemoryBarrier2 = {
		sType               = .IMAGE_MEMORY_BARRIER_2,
		dstStageMask        = {.ALL_COMMANDS},
		dstAccessMask       = {.MEMORY_READ, .MEMORY_WRITE},
		oldLayout           = .UNDEFINED,
		newLayout           = .GENERAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = raw.image.handle,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	dependency: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(Valhalla.raw_commands(&setup), &dependency)
	Valhalla.finalize_workload(&setup) or_return
	execution := Valhalla.execute_workloads(&setup) or_return
	Valhalla.wait_execution(execution) or_return
	raw.image.layout = .GENERAL
	return nil
}

destroy_raw_image :: proc(raw: ^Raw_Image) {
	device := Valhalla.device.handle
	if raw.image.view != 0 {
		vk.DestroyImageView(device, raw.image.view, nil)
	}
	if raw.image.handle != 0 {
		vk.DestroyImage(device, raw.image.handle, nil)
	}
	if raw.memory != 0 {
		vk.FreeMemory(device, raw.memory, nil)
	}
	raw^ = {}
}

allocate_device_memory :: proc(requirements: vk.MemoryRequirements) -> (memory: vk.DeviceMemory, err: Valhalla.Error) {
	types := Valhalla.device.memory_properties
	for memory_type, index in types.memoryTypes[:types.memoryTypeCount] {
		if requirements.memoryTypeBits & (1 << u32(index)) == 0 || .DEVICE_LOCAL not_in memory_type.propertyFlags {
			continue
		}
		info: vk.MemoryAllocateInfo = {
			sType           = .MEMORY_ALLOCATE_INFO,
			allocationSize  = requirements.size,
			memoryTypeIndex = u32(index),
		}
		if res := vk.AllocateMemory(Valhalla.device.handle, &info, nil, &memory); res != .SUCCESS {
			log.errorf("Failed to allocate memory for an external resource: %v", res)
			return 0, Valhalla.Memory_Error.Allocation_Failed
		}
		return
	}
	return 0, Valhalla.Memory_Error.No_Suitable_Memory_Type
}
