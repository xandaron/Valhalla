package Valhalla

import "base:runtime"
import "core:log"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"

Colour_Space :: vk.ColorSpaceKHR

Surface_Error :: enum {
	None,
	Surface_Creation_Failed,
	Presentation_Unsupported,
	No_Swapchain_Support,
	Swapchain_Creation_Failed,
	Unsupported_Present_Mode,
	HDR_Unavailable,
	Acquire_Failed,
}

Present_Mode :: enum {
	Fifo,
	Fifo_Relaxed,
	Mailbox,
	Immediate,
}

@(private)
Surface_Settings :: struct {
	present_mode: Present_Mode,
	prefer_hdr:   bool,
	encode_srgb:  bool,
}

Surface :: struct {
	window:             Window,
	settings:           Surface_Settings,
	handle:             vk.SurfaceKHR,
	swapchain:          vk.SwapchainKHR,
	format:             Format,
	colour_space:       Colour_Space,
	extent:             [2]u32,
	images:             []vk.Image,
	present_semaphores: []vk.Semaphore,
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
make_surface :: proc(
	window: Window,
	present_mode := Present_Mode.Fifo,
	prefer_hdr := false,
	encode_srgb := true,
) -> (
	surface: Surface,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(initialised, "Valhalla.init must be called before make_surface")
	surface.window = window
	surface.settings = {present_mode, prefer_hdr, encode_srgb}

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
	destroy_present_semaphores(surface)
	destroy_swapchain(surface.swapchain, surface.images)
	vk.DestroySurfaceKHR(device.instance, surface.handle, nil)
	surface^ = {}
}

@(require_results)
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
acquire_next_image :: proc(surface: ^Surface, semaphore: vk.Semaphore) -> (index: u32, acquired: bool, err: Error) {
	res := vk.AcquireNextImageKHR(device.handle, surface.swapchain, max(u64), semaphore, 0, &index)
	#partial switch res {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		surface.suboptimal = true
	case .ERROR_OUT_OF_DATE_KHR:
		recreate_swapchain(surface) or_return
		return 0, false, nil
	case:
		log.errorf("Failed to acquire a swapchain image: %v", res)
		return 0, false, .Acquire_Failed
	}
	return index, true, nil
}

surface_supports_present_mode :: proc(surface: ^Surface, mode: Present_Mode) -> bool {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	support := query_swapchain_support(surface.handle)
	return slice.contains(support.modes, PRESENT_MODES[mode])
}

@(require_results)
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

@(require_results)
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
choose_format :: proc(formats: []vk.SurfaceFormatKHR, want_hdr, encode_srgb: bool) -> (vk.SurfaceFormatKHR, bool) {
	if want_hdr {
		if index, found := slice.linear_search_proc(formats, is_hdr_format); found {
			return formats[index], true
		}
	}
	encoding := [2]Format{.B8G8R8A8_SRGB, .R8G8B8A8_SRGB}
	unencoded := [2]Format{.B8G8R8A8_UNORM, .R8G8B8A8_UNORM}
	for preferred in ([2][2]Format{encoding, unencoded} if encode_srgb else {unencoded, encoding}) {
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

	extent := choose_extent(support.capabilities, framebuffer)
	if extent.width == 0 || extent.height == 0 {
		surface.minimised = true
		return nil
	}

	vk.DeviceWaitIdle(device.handle)

	surface.hdr_available = slice.any_of_proc(support.formats, is_hdr_format)
	format, hdr := choose_format(support.formats, surface.settings.prefer_hdr && surface.hdr_available, surface.settings.encode_srgb)

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
		imageUsage            = {.TRANSFER_DST},
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

	surface.format = format.format
	surface.colour_space = format.colorSpace
	surface.hdr = hdr
	surface.encodes_srgb = is_srgb_format(format.format)
	surface.extent = {extent.width, extent.height}
	surface.minimised = false
	surface.suboptimal = false

	count: u32
	vk.GetSwapchainImagesKHR(device.handle, surface.swapchain, &count, nil)
	surface.images = make([]vk.Image, count)
	vk.GetSwapchainImagesKHR(device.handle, surface.swapchain, &count, raw_data(surface.images))
	return rebuild_present_semaphores(surface)
}

@(private)
@(require_results)
record_present :: proc(surface: ^Surface, source: Image, image_index: u32, cmd: vk.CommandBuffer) -> Error {
	begin_commands(cmd, {.ONE_TIME_SUBMIT}) or_return
	target := surface.images[image_index]
	source_ready := GLOBAL_BARRIER
	to_transfer := layout_barrier(target, {.COLOR}, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	vk.CmdPipelineBarrier2(
		cmd,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			memoryBarrierCount = 1,
			pMemoryBarriers = &source_ready,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &to_transfer,
		},
	)
	base_mip, base_layer := view_base(source)
	region := Image_Copy_Region {
		from = {subresource = {aspectMask = {.COLOR}, mipLevel = base_mip, baseArrayLayer = base_layer, layerCount = 1}, extent = {source.extent.x, source.extent.y, 1}},
		to = {subresource = {aspectMask = {.COLOR}, layerCount = 1}, extent = {surface.extent.x, surface.extent.y, 1}},
	}
	emit_image_blit(cmd, source.handle, target, region, .LINEAR, .TRANSFER_DST_OPTIMAL)
	to_present := layout_barrier(target, {.COLOR}, .TRANSFER_DST_OPTIMAL, .PRESENT_SRC_KHR)
	vk.CmdPipelineBarrier2(cmd, &vk.DependencyInfo{sType = .DEPENDENCY_INFO, imageMemoryBarrierCount = 1, pImageMemoryBarriers = &to_present})
	if res := vk.EndCommandBuffer(cmd); res != .SUCCESS {
		log.errorf("Failed to finish a present: %v", res)
		return .Recording_Failed
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
		semaphore = make_semaphore(false, "present") or_return
	}
	return nil
}
