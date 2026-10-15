package Valhalla

import "base:runtime"
import "core:log"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"

Surface_Error :: enum {
	None,
	Surface_Creation_Failed,
	Presentation_Unsupported,
	No_Swapchain_Support,
	Swapchain_Creation_Failed,
	Unsupported_Present_Mode,
	HDR_Unavailable,
	Surface_Minimised,
	Out_Of_Date,
	Acquire_Failed,
}

Present_Mode :: enum {
	Fifo,
	Fifo_Relaxed,
	Mailbox,
	Immediate,
}

Surface_Settings :: struct {
	present_mode:    Present_Mode,
	prefer_hdr:      bool,
	manual_encoding: bool,
}

Surface :: struct {
	window:             ^Window,
	settings:           Surface_Settings,
	handle:             vk.SurfaceKHR,
	swapchain:          vk.SwapchainKHR,
	format:             vk.SurfaceFormatKHR,
	extent:             [2]u32,
	images:             []vk.Image,
	present_semaphores: []vk.Semaphore,
	stand_in:           Image,
	copy_pool:          vk.CommandPool,
	copies:             []vk.CommandBuffer,
	generation:         u64,
	hdr:                bool,
	hdr_available:      bool,
	encodes_srgb:       bool,
	minimised:          bool,
	suboptimal:         bool,
}

@(private = "file")
PRESENT_MODES := [Present_Mode]vk.PresentModeKHR {
	.Fifo         = .FIFO,
	.Fifo_Relaxed = .FIFO_RELAXED,
	.Mailbox      = .MAILBOX,
	.Immediate    = .IMMEDIATE,
}

@(private = "file")
Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	modes:        []vk.PresentModeKHR,
}

@(require_results)
make_surface :: proc(window: ^Window, settings: Surface_Settings) -> (surface: Surface, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(initialised, "Valhalla.init must be called before make_surface")
	surface.window = window
	surface.settings = settings

	if res := glfw.CreateWindowSurface(device.instance, window.handle, nil, &surface.handle); res != .SUCCESS {
		log.errorf("Failed to create window surface: %v", res)
		return {}, .Surface_Creation_Failed
	}
	defer if err != nil {
		delete_surface(&surface)
	}

	supported: b32
	vk.GetPhysicalDeviceSurfaceSupportKHR(device.physical_device, device.queue_families.present, surface.handle, &supported)
	if !supported {
		return surface, .Presentation_Unsupported
	}

	recreate_swapchain(&surface) or_return
	return
}

delete_surface :: proc(surface: ^Surface) {
	if surface.handle == 0 {
		return
	}
	vk.DeviceWaitIdle(device.handle)
	destroy_presentation(surface)
	destroy_present_semaphores(surface)
	destroy_swapchain(surface.swapchain, surface.images)
	vk.DestroySurfaceKHR(device.instance, surface.handle, nil)
	surface^ = {}
}

update_surface :: proc(surface: ^Surface) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	size := window_framebuffer_size(surface.window)
	if surface.minimised || surface.suboptimal || u32(size.x) != surface.extent.x || u32(size.y) != surface.extent.y {
		return recreate_swapchain(surface)
	}
	return nil
}

@(private)
@(require_results)
acquire_next_image :: proc(surface: ^Surface, semaphore: vk.Semaphore) -> (index: u32, err: Error) {
	res := vk.AcquireNextImageKHR(device.handle, surface.swapchain, max(u64), semaphore, 0, &index)
	#partial switch res {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		surface.suboptimal = true
	case .ERROR_OUT_OF_DATE_KHR:
		recreate_swapchain(surface) or_return
		return 0, .Out_Of_Date
	case:
		log.errorf("Failed to acquire a swapchain image: %v", res)
		return 0, .Acquire_Failed
	}
	return
}

surface_supports_present_mode :: proc(surface: ^Surface, mode: Present_Mode) -> bool {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	support := query_swapchain_support(surface.handle)
	return slice.contains(support.modes, PRESENT_MODES[mode])
}

set_surface_present_mode :: proc(surface: ^Surface, mode: Present_Mode) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if !surface_supports_present_mode(surface, mode) {
		return .Unsupported_Present_Mode
	}
	if mode == surface.settings.present_mode {
		return nil
	}
	surface.settings.present_mode = mode
	return recreate_swapchain(surface)
}

set_surface_hdr :: proc(surface: ^Surface, enabled: bool) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if enabled && !surface.hdr_available {
		return .HDR_Unavailable
	}
	surface.settings.prefer_hdr = enabled
	if enabled == surface.hdr {
		return nil
	}
	return recreate_swapchain(surface)
}

@(private = "file")
query_swapchain_support :: proc(surface: vk.SurfaceKHR) -> (support: Swapchain_Support) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device.physical_device, surface, &support.capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device.physical_device, surface, &format_count, nil)
	support.formats = make([]vk.SurfaceFormatKHR, format_count, context.temp_allocator)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device.physical_device, surface, &format_count, raw_data(support.formats))

	mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device.physical_device, surface, &mode_count, nil)
	support.modes = make([]vk.PresentModeKHR, mode_count, context.temp_allocator)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device.physical_device, surface, &mode_count, raw_data(support.modes))
	return
}

@(private = "file")
is_hdr_format :: proc(format: vk.SurfaceFormatKHR) -> bool {
	return(
		format.colorSpace == .HDR10_ST2084_EXT &&
		(format.format == .A2B10G10R10_UNORM_PACK32 || format.format == .A2R10G10B10_UNORM_PACK32) \
	)
}

@(private = "file")
choose_format :: proc(formats: []vk.SurfaceFormatKHR, want_hdr, manual_encoding: bool) -> (vk.SurfaceFormatKHR, bool) {
	if want_hdr {
		if index, found := slice.linear_search_proc(formats, is_hdr_format); found {
			return formats[index], true
		}
	}
	encoding := [2]vk.Format{.B8G8R8A8_SRGB, .R8G8B8A8_SRGB}
	unencoded := [2]vk.Format{.B8G8R8A8_UNORM, .R8G8B8A8_UNORM}
	for preferred in ([2][2]vk.Format{unencoded, encoding} if manual_encoding else {encoding, unencoded}) {
		for format in formats {
			if (format.format == preferred[0] || format.format == preferred[1]) && format.colorSpace == .SRGB_NONLINEAR {
				return format, false
			}
		}
	}
	return formats[0], false
}

@(private = "file")
choose_extent :: proc(capabilities: vk.SurfaceCapabilitiesKHR, framebuffer: [2]i32) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}
	return {
		width = clamp(u32(framebuffer.x), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
		height = clamp(u32(framebuffer.y), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
	}
}

@(private = "file")
destroy_swapchain :: proc(swapchain: vk.SwapchainKHR, images: []vk.Image) {
	delete(images)
	if swapchain != 0 {
		vk.DestroySwapchainKHR(device.handle, swapchain, nil)
	}
}

@(private = "file")
@(require_results)
recreate_swapchain :: proc(surface: ^Surface) -> Error {
	framebuffer := window_framebuffer_size(surface.window)
	if framebuffer.x <= 0 || framebuffer.y <= 0 {
		surface.minimised = true
		return nil
	}

	support := query_swapchain_support(surface.handle)
	if len(support.formats) == 0 || len(support.modes) == 0 {
		return .No_Swapchain_Support
	}
	if !slice.contains(support.modes, PRESENT_MODES[surface.settings.present_mode]) {
		return .Unsupported_Present_Mode
	}

	usage: vk.ImageUsageFlags = {.TRANSFER_DST, .COLOR_ATTACHMENT}
	if .TRANSFER_SRC in support.capabilities.supportedUsageFlags {
		usage += {.TRANSFER_SRC}
	}
	extent := choose_extent(support.capabilities, framebuffer)
	if extent.width == 0 || extent.height == 0 {
		surface.minimised = true
		return nil
	}

	vk.DeviceWaitIdle(device.handle)

	surface.hdr_available = slice.any_of_proc(support.formats, is_hdr_format)
	format, hdr := choose_format(support.formats, surface.settings.prefer_hdr && surface.hdr_available, surface.settings.manual_encoding)

	max_count := support.capabilities.maxImageCount
	min_count := support.capabilities.minImageCount
	image_count := max_count if max_count == 1 else max(2, min_count)

	family_indices := unique_queue_families()
	old_swapchain, old_images := surface.swapchain, surface.images
	surface.swapchain, surface.images = 0, nil
	defer destroy_swapchain(old_swapchain, old_images)

	swapchain_info: vk.SwapchainCreateInfoKHR = {
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		surface               = surface.handle,
		minImageCount         = image_count,
		imageFormat           = format.format,
		imageColorSpace       = format.colorSpace,
		imageExtent           = extent,
		imageArrayLayers      = 1,
		imageUsage            = usage,
		imageSharingMode      = .EXCLUSIVE if len(family_indices) == 1 else .CONCURRENT,
		queueFamilyIndexCount = u32(len(family_indices)),
		pQueueFamilyIndices   = raw_data(family_indices),
		preTransform          = support.capabilities.currentTransform,
		compositeAlpha        = {.OPAQUE},
		presentMode           = PRESENT_MODES[surface.settings.present_mode],
		clipped               = true,
		oldSwapchain          = old_swapchain,
	}
	if res := vk.CreateSwapchainKHR(device.handle, &swapchain_info, nil, &surface.swapchain); res != .SUCCESS {
		log.errorf("Failed to create swapchain: %v", res)
		surface.swapchain = 0
		return .Swapchain_Creation_Failed
	}

	surface.format = format
	surface.hdr = hdr
	surface.encodes_srgb = is_srgb_format(format.format)
	surface.extent = {extent.width, extent.height}
	surface.minimised = false
	surface.suboptimal = false
	surface.generation += 1

	count: u32
	vk.GetSwapchainImagesKHR(device.handle, surface.swapchain, &count, nil)
	surface.images = make([]vk.Image, count)
	vk.GetSwapchainImagesKHR(device.handle, surface.swapchain, &count, raw_data(surface.images))
	rebuild_present_semaphores(surface) or_return
	return rebuild_presentation(surface)
}

@(private = "file")
destroy_presentation :: proc(surface: ^Surface) {
	if surface.copy_pool != 0 {
		vk.DestroyCommandPool(device.handle, surface.copy_pool, nil)
		surface.copy_pool = 0
	}
	delete(surface.copies)
	surface.copies = nil
	delete_image(&surface.stand_in)
}

@(private = "file")
@(require_results)
rebuild_presentation :: proc(surface: ^Surface) -> Error {
	destroy_presentation(surface)
	storage: vk.ImageUsageFlags = {.STORAGE} if format_has_features(surface.format.format, {.STORAGE_IMAGE}) else {}
	stand_in := Image_Settings {
		shape  = .D2,
		format = surface.format.format,
		size   = {surface.extent.x, surface.extent.y, 1},
		name   = "surface stand-in",
	}
	surface.stand_in = make_owned_image(stand_in, storage) or_return
	pool_info: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = device.queue_families.graphics,
	}
	if res := vk.CreateCommandPool(device.handle, &pool_info, nil, &surface.copy_pool); res != .SUCCESS {
		log.errorf("Failed to create the surface's copy command pool: %v", res)
		return .Swapchain_Creation_Failed
	}
	surface.copies = make([]vk.CommandBuffer, len(surface.images))
	allocate_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = surface.copy_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(surface.copies)),
	}
	if res := vk.AllocateCommandBuffers(device.handle, &allocate_info, raw_data(surface.copies)); res != .SUCCESS {
		log.errorf("Failed to allocate the surface's copy command buffers: %v", res)
		return .Swapchain_Creation_Failed
	}
	for cmd, index in surface.copies {
		record_present_copy(cmd, surface.stand_in, surface.images[index], surface.extent) or_return
	}
	return nil
}

@(private = "file")
@(require_results)
record_present_copy :: proc(cmd: vk.CommandBuffer, stand_in: Image, target: vk.Image, extent: [2]u32) -> Error {
	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.SIMULTANEOUS_USE},
	}
	if res := vk.BeginCommandBuffer(cmd, &begin_info); res != .SUCCESS {
		log.errorf("Failed to begin a present copy: %v", res)
		return .Swapchain_Creation_Failed
	}
	colour := vk.ImageSubresourceRange {
		aspectMask = {.COLOR},
		levelCount = 1,
		layerCount = 1,
	}
	stand_in_ready: vk.MemoryBarrier2 = {
		sType         = .MEMORY_BARRIER_2,
		srcStageMask  = {.ALL_COMMANDS},
		srcAccessMask = {.MEMORY_WRITE},
		dstStageMask  = {.ALL_TRANSFER},
		dstAccessMask = {.TRANSFER_READ},
	}
	to_transfer: vk.ImageMemoryBarrier2 = {
		sType               = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask        = {.ALL_TRANSFER},
		dstStageMask        = {.ALL_TRANSFER},
		dstAccessMask       = {.TRANSFER_WRITE},
		oldLayout           = .UNDEFINED,
		newLayout           = .TRANSFER_DST_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = target,
		subresourceRange    = colour,
	}
	vk.CmdPipelineBarrier2(
		cmd,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			memoryBarrierCount = 1,
			pMemoryBarriers = &stand_in_ready,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &to_transfer,
		},
	)
	region: vk.ImageCopy2 = {
		sType          = .IMAGE_COPY_2,
		srcSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		dstSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		extent         = {extent.x, extent.y, 1},
	}
	copy_info: vk.CopyImageInfo2 = {
		sType          = .COPY_IMAGE_INFO_2,
		srcImage       = stand_in.handle,
		srcImageLayout = .GENERAL,
		dstImage       = target,
		dstImageLayout = .TRANSFER_DST_OPTIMAL,
		regionCount    = 1,
		pRegions       = &region,
	}
	vk.CmdCopyImage2(cmd, &copy_info)
	to_present: vk.ImageMemoryBarrier2 = {
		sType               = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask        = {.ALL_TRANSFER},
		srcAccessMask       = {.TRANSFER_WRITE},
		oldLayout           = .TRANSFER_DST_OPTIMAL,
		newLayout           = .PRESENT_SRC_KHR,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = target,
		subresourceRange    = colour,
	}
	vk.CmdPipelineBarrier2(cmd, &vk.DependencyInfo{sType = .DEPENDENCY_INFO, imageMemoryBarrierCount = 1, pImageMemoryBarriers = &to_present})
	if res := vk.EndCommandBuffer(cmd); res != .SUCCESS {
		log.errorf("Failed to finish a present copy: %v", res)
		return .Swapchain_Creation_Failed
	}
	return nil
}

@(private = "file")
destroy_present_semaphores :: proc(surface: ^Surface) {
	for semaphore in surface.present_semaphores {
		if semaphore != 0 {
			vk.DestroySemaphore(device.handle, semaphore, nil)
		}
	}
	delete(surface.present_semaphores)
	surface.present_semaphores = nil
}

@(private = "file")
@(require_results)
rebuild_present_semaphores :: proc(surface: ^Surface) -> Error {
	destroy_present_semaphores(surface)
	surface.present_semaphores = make([]vk.Semaphore, len(surface.images))
	for &semaphore in surface.present_semaphores {
		semaphore_info: vk.SemaphoreCreateInfo = {
			sType = .SEMAPHORE_CREATE_INFO,
		}
		if res := vk.CreateSemaphore(device.handle, &semaphore_info, nil, &semaphore); res != .SUCCESS {
			log.errorf("Failed to create a present semaphore: %v", res)
			return .Swapchain_Creation_Failed
		}
	}
	return nil
}
