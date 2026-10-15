package Valhalla

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/bits"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import stbi "vendor:stb/image"
import vk "vendor:vulkan"

Image_Error :: enum {
	None,
	Invalid_Settings,
	Unsupported_Format,
	Image_Creation_Failed,
	Memory_Bind_Failed,
	Invalid_Upload,
	View_Creation_Failed,
	Image_File_Read_Failed,
	Image_Decode_Failed,
	No_Mip_Levels,
}

Image_Kind :: enum {
	Colour,
	Depth,
	Generic,
}

Image_Shape :: enum {
	D1,
	D1_Array,
	D2,
	D2_Array,
	D3,
	Cube,
	Cube_Array,
}

MAX_VIEW_FORMATS :: 4

Image_Settings :: struct {
	kind:         Image_Kind,
	shape:      Image_Shape,
	format:     vk.Format,
	size:       [3]u32,
	layers:     u32,
	mip_levels: u32,
	samples:    u32,
	name:       string,
	view_formats: [MAX_VIEW_FORMATS]vk.Format,
}

Image :: struct {
	handle:          vk.Image,
	view:            vk.ImageView,
	attachment_view: vk.ImageView,
	format:          vk.Format,
	extent:          [3]u32,
	layers:          u32,
	mip_levels:      u32,
	samples:         vk.SampleCountFlags,
	aspect:          vk.ImageAspectFlags,
	usage:           vk.ImageUsageFlags,
	layout:          vk.ImageLayout,
	heap_index:      u32,
	version:         u32,
	producer:        u64,
	variant:    union {
		Owned_Image,
		External_Image,
		Swapchain_Image,
		View_Image,
	},
}

Owned_Image :: struct {
	allocation:   Allocation,
	kind:         Image_Kind,
	shape:        Image_Shape,
	name:         string,
	view_formats: [MAX_VIEW_FORMATS]vk.Format,
}

External_Image :: struct {}

View_Image :: struct {
	mip_level:   u32,
	first_layer: u32,
	shape:       Image_Shape,
}

Swapchain_Image :: struct {
	surface: ^Surface,
}

@(private = "file")
IMAGE_USAGE := [Image_Kind]vk.ImageUsageFlags {
	.Colour  = {.COLOR_ATTACHMENT, .SAMPLED, .TRANSFER_SRC, .TRANSFER_DST},
	.Depth   = {.DEPTH_STENCIL_ATTACHMENT, .SAMPLED, .TRANSFER_SRC, .TRANSFER_DST},
	.Generic = {.STORAGE, .SAMPLED, .TRANSFER_SRC, .TRANSFER_DST},
}

@(private = "file")
IMAGE_TYPES := [Image_Shape]vk.ImageType {
	.D1         = .D1,
	.D1_Array   = .D1,
	.D2         = .D2,
	.D2_Array   = .D2,
	.D3         = .D3,
	.Cube       = .D2,
	.Cube_Array = .D2,
}

@(private = "file")
VIEW_TYPES := [Image_Shape]vk.ImageViewType {
	.D1         = .D1,
	.D1_Array   = .D1_ARRAY,
	.D2         = .D2,
	.D2_Array   = .D2_ARRAY,
	.D3         = .D3,
	.Cube       = .CUBE,
	.Cube_Array = .CUBE_ARRAY,
}

@(require_results)
make_empty_image :: proc(
	format: vk.Format,
	size: [3]u32,
	kind := Image_Kind.Colour,
	shape := Image_Shape.D2,
	layers: u32 = 1,
	mip_levels: u32 = 1,
	samples: u32 = 1,
	name := "",
	view_formats := [MAX_VIEW_FORMATS]vk.Format{},
) -> (
	image: Image,
	err: Error,
) {
	return make_owned_image(format, size, kind, shape, layers, mip_levels, samples, name, view_formats, {})
}

@(private)
@(require_results)
make_owned_image :: proc(
	format: vk.Format,
	size: [3]u32,
	kind: Image_Kind,
	shape: Image_Shape,
	layers: u32,
	mip_levels: u32,
	samples: u32,
	name: string,
	view_formats: [MAX_VIEW_FORMATS]vk.Format,
	extra_usage: vk.ImageUsageFlags,
) -> (
	image: Image,
	err: Error,
) {
	assert(initialised, "Valhalla.init must be called before make_image")
	settings := Image_Settings {
		kind       = kind,
		shape      = shape,
		format     = format,
		size       = size,
		layers     = layers,
		mip_levels = mip_levels,
		samples    = samples,
	}
	image = describe_image(settings) or_return
	image.usage += extra_usage
	owned := &image.variant.(Owned_Image)

	flags: vk.ImageCreateFlags = {.CUBE_COMPATIBLE} if settings.shape == .Cube || settings.shape == .Cube_Array else {}
	listed := make([dynamic]vk.Format, 0, MAX_VIEW_FORMATS + 1, context.temp_allocator)
	for view_format in view_formats {
		if view_format == .UNDEFINED {
			break
		}
		if len(listed) == 0 {
			append(&listed, image.format)
		}
		view_size, view_known := format_texel_size(view_format)
		image_size, image_known := format_texel_size(image.format)
		fmt.assertf(view_known && image_known && view_size == image_size, "view format %v must have the same texel size as %v", view_format, image.format)
		if view_format != image.format {
			append(&listed, view_format)
		}
	}
	format_list: vk.ImageFormatListCreateInfo = {
		sType           = .IMAGE_FORMAT_LIST_CREATE_INFO,
		viewFormatCount = u32(len(listed)),
		pViewFormats    = raw_data(listed),
	}
	if len(listed) > 0 {
		flags += {.MUTABLE_FORMAT}
		owned.view_formats = view_formats
	}
	format_info: vk.PhysicalDeviceImageFormatInfo2 = {
		sType  = .PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2,
		pNext  = &format_list if len(listed) > 0 else nil,
		format = image.format,
		type   = IMAGE_TYPES[owned.shape],
		tiling = .OPTIMAL,
		usage  = image.usage,
		flags  = flags,
	}
	format_properties: vk.ImageFormatProperties2 = {
		sType = .IMAGE_FORMAT_PROPERTIES_2,
	}
	if res := vk.GetPhysicalDeviceImageFormatProperties2(device.physical_device, &format_info, &format_properties);
	   res != .SUCCESS {
		log.errorf("Image format %v is not supported for %v %v images: %v", image.format, owned.kind, owned.shape, res)
		return {}, .Unsupported_Format
	}
	limits := format_properties.imageFormatProperties
	if image.extent.x > limits.maxExtent.width ||
	   image.extent.y > limits.maxExtent.height ||
	   image.extent.z > limits.maxExtent.depth ||
	   image.mip_levels > limits.maxMipLevels ||
	   image.layers > limits.maxArrayLayers ||
	   image.samples & limits.sampleCounts != image.samples {
		log.errorf("Image settings exceed what format %v supports: %v", image.format, limits)
		return {}, .Unsupported_Format
	}

	image_info: vk.ImageCreateInfo = {
		sType         = .IMAGE_CREATE_INFO,
		pNext         = &format_list if len(listed) > 0 else nil,
		flags         = flags,
		imageType     = IMAGE_TYPES[owned.shape],
		format        = image.format,
		extent        = {image.extent.x, image.extent.y, image.extent.z},
		mipLevels     = image.mip_levels,
		arrayLayers   = image.layers,
		samples       = image.samples,
		tiling        = .OPTIMAL,
		usage         = image.usage,
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if res := vk.CreateImage(device.handle, &image_info, nil, &image.handle); res != .SUCCESS {
		log.errorf("Failed to create image: %v", res)
		return {}, .Image_Creation_Failed
	}
	defer if err != nil {
		delete_image(&image)
	}

	dedicated_requirements: vk.MemoryDedicatedRequirements = {
		sType = .MEMORY_DEDICATED_REQUIREMENTS,
	}
	requirements: vk.MemoryRequirements2 = {
		sType = .MEMORY_REQUIREMENTS_2,
		pNext = &dedicated_requirements,
	}
	vk.GetImageMemoryRequirements2(
		device.handle,
		&vk.ImageMemoryRequirementsInfo2{sType = .IMAGE_MEMORY_REQUIREMENTS_INFO_2, image = image.handle},
		&requirements,
	)
	dedicated_info: vk.MemoryDedicatedAllocateInfo = {
		sType = .MEMORY_DEDICATED_ALLOCATE_INFO,
		image = image.handle,
	}
	dedicated: ^vk.MemoryDedicatedAllocateInfo
	if dedicated_requirements.prefersDedicatedAllocation || dedicated_requirements.requiresDedicatedAllocation {
		dedicated = &dedicated_info
	}
	owned.allocation = allocate_memory(requirements.memoryRequirements, {.DEVICE_LOCAL}, .Optimal, dedicated) or_return
	bind_info: vk.BindImageMemoryInfo = {
		sType        = .BIND_IMAGE_MEMORY_INFO,
		image        = image.handle,
		memory       = owned.allocation.memory,
		memoryOffset = owned.allocation.offset,
	}
	if res := vk.BindImageMemory2(device.handle, 1, &bind_info); res != .SUCCESS {
		log.errorf("Failed to bind image memory: %v", res)
		return image, .Memory_Bind_Failed
	}

	view_info: vk.ImageViewCreateInfo = {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image.handle,
		viewType = VIEW_TYPES[owned.shape],
		format = image.format,
		subresourceRange = {
			aspectMask = image.aspect,
			levelCount = image.mip_levels,
			layerCount = image.layers,
		},
	}
	if res := vk.CreateImageView(device.handle, &view_info, nil, &image.view); res != .SUCCESS {
		log.errorf("Failed to create image view: %v", res)
		return image, .View_Creation_Failed
	}
	image.attachment_view = image.view
	if image.usage & {.COLOR_ATTACHMENT, .DEPTH_STENCIL_ATTACHMENT} != {} && owned.shape != .D3 &&
	   (owned.shape != .D2 || image.mip_levels > 1) {
		attachment_info := view_info
		attachment_info.viewType = .D2_ARRAY if image.layers > 1 else .D2
		attachment_info.subresourceRange.levelCount = 1
		if res := vk.CreateImageView(device.handle, &attachment_info, nil, &image.attachment_view); res != .SUCCESS {
			log.errorf("Failed to create attachment view: %v", res)
			image.attachment_view = 0
			return image, .View_Creation_Failed
		}
	}
	acquire_image_slots(&image, &view_info) or_return
	if name != "" {
		owned.name = strings.clone(name)
		name_image(image, name)
	}
	command_buffer := staging_commands() or_return
	transition(command_buffer, image.handle, image.aspect, .UNDEFINED, .GENERAL)
	image.layout = .GENERAL
	return
}

@(require_results)
make_image_from_file :: proc(
	filename: string,
	kind := Image_Kind.Colour,
	srgb := true,
	view_formats := [MAX_VIEW_FORMATS]vk.Format{},
) -> (
	image: Image,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	data := read_image_file(filename) or_return
	length := i32(len(data))
	format: vk.Format = .R8G8B8A8_SRGB if srgb else .R8G8B8A8_UNORM
	if stbi.is_hdr_from_memory(raw_data(data), length) != 0 {
		format = .R32G32B32A32_SFLOAT
	} else if !srgb && stbi.is_16_bit_from_memory(raw_data(data), length) != 0 {
		format = .R16G16B16A16_UNORM
	}
	width, height, channels: i32
	if stbi.info_from_memory(raw_data(data), length, &width, &height, &channels) == 0 {
		log.errorf("Failed to read the header of %v: %v", filename, stbi.failure_reason())
		return {}, .Image_Decode_Failed
	}
	image = make_empty_image(format, {u32(width), u32(height), 1}, kind, name = filepath.base(filename), view_formats = view_formats) or_return
	if err = load_encoded_to_image(filename, data, &image, 0, 0); err != nil {
		delete_image(&image)
		return {}, err
	}
	return
}

@(require_results)
make_image_from_memory :: proc(memory: []u8, settings: Image_Settings) -> (image: Image, err: Error) {
	image = make_empty_image(settings.format, settings.size, settings.kind, settings.shape, settings.layers, settings.mip_levels, settings.samples, settings.name, settings.view_formats) or_return
	if err = load_memory_to_image(memory, &image); err != nil {
		delete_image(&image)
		return {}, err
	}
	return
}

@(require_results)
make_image_from_image :: proc(source: ^Image, settings: Image_Settings) -> (image: Image, err: Error) {
	image = make_empty_image(settings.format, settings.size, settings.kind, settings.shape, settings.layers, settings.mip_levels, settings.samples, settings.name, settings.view_formats) or_return
	defer if err != nil {
		delete_image(&image)
	}
	region := Image_Region {
		layers = min(source.layers, image.layers),
	}
	source_texel, _ := format_texel_size(source.format)
	image_texel, _ := format_texel_size(image.format)
	if source.extent == image.extent && source_texel == image_texel && source.samples == image.samples {
		return image, load_image_to_image(source, &image, region, region)
	}
	return image, blit_image_to_image(source, &image, region, region)
}

@(require_results)
make_image_from_buffer :: proc(source: ^Buffer, settings: Image_Settings) -> (image: Image, err: Error) {
	image = make_empty_image(settings.format, settings.size, settings.kind, settings.shape, settings.layers, settings.mip_levels, settings.samples, settings.name, settings.view_formats) or_return
	if err = load_buffer_to_image(source, &image); err != nil {
		delete_image(&image)
		return {}, err
	}
	return
}

make_image :: proc {
	make_empty_image,
	make_image_from_file,
	make_image_from_memory,
	make_image_from_image,
	make_image_from_buffer,
}

resize_image :: proc(image: ^Image, size: [3]u32) -> (resized: bool, err: Error) {
	owned, is_owned := image.variant.(Owned_Image)
	assert(is_owned && image.handle != 0, "resize_image needs an image made by make_image")
	if image.extent == size {
		return false, nil
	}
	mip_limit := u32(bits.len(max(size.x, size.y, size.z, 1)))
	replacement := make_empty_image(
		image.format,
		size,
		owned.kind,
		owned.shape,
		image.layers,
		min(image.mip_levels, mip_limit),
		transmute(u32)image.samples,
		owned.name,
		owned.view_formats,
	) or_return
	delete_image(image)
	image^ = replacement
	return true, nil
}

@(require_results)
load_file_to_image :: proc(filename: string, image: ^Image, mip_level: u32 = 0, layer: u32 = 0) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	data := read_image_file(filename) or_return
	return load_encoded_to_image(filename, data, image, mip_level, layer)
}

@(require_results)
load_memory_to_image :: proc(
	source: []u8,
	image: ^Image,
	mip_level: u32 = 0,
	first_layer: u32 = 0,
	offset := [3]u32{},
	size := [3]u32{},
) -> Error {
	if .TRANSFER_DST not_in image.usage {
		log.error("The image cannot be written to: it was not created as a transfer destination")
		return .Invalid_Upload
	}
	if image.aspect == {.DEPTH, .STENCIL} {
		log.error("Combined depth-stencil images cannot be loaded from memory")
		return .Invalid_Upload
	}
	if mip_level >= image.mip_levels {
		log.errorf("Mip level %v is outside an image with %v levels", mip_level, image.mip_levels)
		return .Invalid_Upload
	}
	texel_size, known := format_texel_size(image.format)
	if !known {
		log.errorf("Loading %v images from memory is not supported yet", image.format)
		return .Unsupported_Format
	}
	full := mip_extent(image^, mip_level)
	if offset.x >= full.x || offset.y >= full.y || offset.z >= full.z {
		log.errorf("Offset %v lies outside mip %v, which is %v", offset, mip_level, full)
		return .Invalid_Upload
	}
	extent := size if size != {} else full - offset
	if extent.x == 0 || extent.y == 0 || extent.z == 0 || offset.x + extent.x > full.x || offset.y + extent.y > full.y || offset.z + extent.z > full.z {
		log.errorf("A %v region at %v does not fit inside mip %v, which is %v", extent, offset, mip_level, full)
		return .Invalid_Upload
	}
	layer_size := int(texel_size * extent.x * extent.y * extent.z)
	if len(source) == 0 || len(source) % layer_size != 0 {
		log.errorf(
			"A %v region of this image takes %v bytes of tightly packed texels per layer; %v bytes is not a whole number of layers",
			extent,
			layer_size,
			len(source),
		)
		return .Invalid_Upload
	}
	layer_count := u32(len(source) / layer_size)
	if first_layer + layer_count > image.layers {
		log.errorf("Loading %v layers from layer %v overruns an image with %v layers", layer_count, first_layer, image.layers)
		return .Invalid_Upload
	}

	buffer, staged_offset, mapped := stage(vk.DeviceSize(len(source))) or_return
	copy(mapped[:len(source)], source)
	command_buffer := staging_commands() or_return
	base_mip, base_layer := view_base(image^)

	if image.layout != .GENERAL {
		transition(command_buffer, image.handle, image.aspect, image.layout, .GENERAL)
		image.layout = .GENERAL
	}
	region: vk.BufferImageCopy2 = {
		sType = .BUFFER_IMAGE_COPY_2,
		bufferOffset = staged_offset,
		imageSubresource = {aspectMask = image.aspect, mipLevel = base_mip + mip_level, baseArrayLayer = base_layer + first_layer, layerCount = layer_count},
		imageOffset = {i32(offset.x), i32(offset.y), i32(offset.z)},
		imageExtent = {extent.x, extent.y, extent.z},
	}
	copy_info: vk.CopyBufferToImageInfo2 = {
		sType          = .COPY_BUFFER_TO_IMAGE_INFO_2,
		srcBuffer      = buffer,
		dstImage       = image.handle,
		dstImageLayout = .GENERAL,
		regionCount    = 1,
		pRegions       = &region,
	}
	vk.CmdCopyBufferToImage2(command_buffer, &copy_info)
	return nil
}

@(require_results)
load_image_to_image :: proc(source, image: ^Image, source_region := Image_Region{}, region := Image_Region{}) -> Error {
	assert(source.layout == .GENERAL && image.layout == .GENERAL, "immediate copies need images in GENERAL, as every image Valhalla makes is")
	resolved := image_copy_region(source^, image^, source_region, region)
	cmd := staged_transfer() or_return
	emit_image_copy(cmd, source^, image^, resolved)
	end_staged_transfer(cmd)
	return nil
}

@(require_results)
blit_image_to_image :: proc(source, image: ^Image, source_region := Image_Region{}, region := Image_Region{}, filter := vk.Filter.LINEAR) -> Error {
	assert(source.layout == .GENERAL && image.layout == .GENERAL, "immediate copies need images in GENERAL, as every image Valhalla makes is")
	resolved := image_blit_region(source^, image^, source_region, region, filter)
	cmd := staged_transfer() or_return
	emit_image_blit(cmd, source^, image^, resolved, filter)
	end_staged_transfer(cmd)
	return nil
}

@(require_results)
load_buffer_to_image :: proc(source: ^Buffer, image: ^Image, #any_int source_offset: int = 0, region := Image_Region{}) -> Error {
	assert(image.layout == .GENERAL, "immediate copies need an image in GENERAL, as every image Valhalla makes is")
	resolved := buffer_image_region(source^, image^, source_offset, region, to_image = true)
	cmd := staged_transfer() or_return
	emit_buffer_to_image(cmd, source^, image^, resolved)
	end_staged_transfer(cmd)
	return nil
}

load_to_image :: proc {
	load_file_to_image,
	load_memory_to_image,
	load_image_to_image,
	load_buffer_to_image,
}

@(require_results)
write_image_to_file :: proc(source: ^Image, filename: string, encoded := true) -> Error {
	workload := make_workload() or_return
	defer delete_workload(&workload)
	shot := readback_image(&workload, source^) or_return
	finalize_workload(&workload) or_return
	execution := execute_workload(&workload) or_return
	wait_execution(execution) or_return
	return write_readback_to_file(shot, filename, encoded)
}

write_image_to_image :: load_image_to_image

write_image_to_buffer :: load_image_to_buffer

@(require_results)
write_image_to_surface :: proc(source: ^Image, surface: ^Surface, source_region := Image_Region{}, filter := vk.Filter.LINEAR) -> Error {
	workload := make_workload() or_return
	defer delete_workload(&workload)
	image := acquire(&workload, surface) or_return
	region := source_region
	region.layers = max(region.layers, 1)
	shown := blit_image(&workload, source^, image, region, {}, filter)
	present(&workload, shown)
	finalize_workload(&workload) or_return
	execution := execute_workload(&workload) or_return
	return wait_execution(execution)
}

write_image :: proc {
	write_image_to_file,
	write_image_to_image,
	write_image_to_buffer,
	write_image_to_surface,
}

@(require_results)
generate_image_mips :: proc(image: ^Image) -> Error {
	assert(image.handle != 0, "generate_mips needs an image")
	assert(image.layout == .GENERAL, "generate_mips needs an image in GENERAL, as every image Valhalla makes is")
	if image.mip_levels < 2 {
		log.error("The image has one mip level, so there are no mips to generate; make it with mip_levels")
		return .No_Mip_Levels
	}
	features: vk.FormatFeatureFlags = {.BLIT_SRC, .BLIT_DST, .SAMPLED_IMAGE_FILTER_LINEAR}
	if .COLOR not_in image.aspect || !format_has_features(image.format, features) {
		log.errorf("%v images cannot generate mips: the format needs linear blits", image.format)
		return .Unsupported_Format
	}
	cmd := staged_transfer() or_return
	for mip in 1 ..< image.mip_levels {
		region := image_blit_region(image^, image^, {mip_level = mip - 1}, {mip_level = mip}, .LINEAR)
		emit_image_blit(cmd, image^, image^, region, .LINEAR)
		end_staged_transfer(cmd)
	}
	return nil
}

generate_mips :: proc {
	generate_image_mips,
	generate_workload_mips,
}

image_settings :: proc(image: Image) -> Image_Settings {
	owned, is_owned := image.variant.(Owned_Image)
	settings := Image_Settings {
		format     = image.format,
		size       = image.extent,
		layers     = image.layers,
		mip_levels = image.mip_levels,
		samples    = transmute(u32)image.samples,
	}
	if is_owned {
		settings.kind = owned.kind
		settings.shape = owned.shape
		settings.name = owned.name
		settings.view_formats = owned.view_formats
		if owned.shape == .Cube || owned.shape == .Cube_Array {
			settings.layers /= 6
		}
	}
	return settings
}

@(require_results)
make_image_view :: proc(
	image: Image,
	mip_level: u32 = 0,
	mip_levels: u32 = 0,
	first_layer: u32 = 0,
	layers: u32 = 0,
	shape: Maybe(Image_Shape) = nil,
	format := vk.Format.UNDEFINED,
	aspect := vk.ImageAspectFlags{},
) -> (
	view: Image,
	err: Error,
) {
	_, is_swapchain := image.variant.(Swapchain_Image)
	assert(image.handle != 0 && !is_swapchain, "views are made of images that outlive a workload, not of acquired surface images")
	assert(mip_level < image.mip_levels, "the view's first mip is past the image's last mip")
	assert(first_layer < image.layers, "the view's first layer is past the image's last layer")
	mips := mip_levels if mip_levels > 0 else image.mip_levels - mip_level
	count := layers if layers > 0 else image.layers - first_layer
	assert(mip_level + mips <= image.mip_levels, "the view's mips run past the image's last mip")
	assert(first_layer + count <= image.layers, "the view's layers run past the image's last layer")
	parent := image_shape(image)
	view_shape := shape.? or_else default_view_shape(parent, count)
	switch view_shape {
	case .D1, .D2, .D3:
		assert(count == 1, "a non-array view covers one layer")
	case .Cube:
		assert(count == 6, "a cube view covers six layers")
	case .Cube_Array:
		assert(count % 6 == 0, "a cube array view covers a multiple of six layers")
	case .D1_Array, .D2_Array:
	}
	assert((view_shape == .D3) == (parent == .D3), "only a 3D image has 3D views, and its views are 3D")
	assert(view_shape != .Cube && view_shape != .Cube_Array || parent == .Cube || parent == .Cube_Array, "cube views need an image made as a cube")
	assert((view_shape == .D1 || view_shape == .D1_Array) == (parent == .D1 || parent == .D1_Array), "1D images have 1D views, and only they do")

	view_format := format if format != .UNDEFINED else image.format
	if view_format != image.format {
		if owned, is_owned := image.variant.(Owned_Image); is_owned {
			fmt.assertf(slice.contains(owned.view_formats[:], view_format), "the image was not made with %v in its view_formats", view_format)
		}
	}
	view_aspect := aspect if aspect != {} else image.aspect
	assert(view_aspect <= image.aspect, "a view's aspect must be part of the image's")

	base_mip, base_layer := view_base(image)
	view = image
	view.format = view_format
	view.aspect = view_aspect
	view.view = 0
	view.attachment_view = 0
	view.heap_index = 0
	view.extent = mip_extent(image, mip_level)
	view.mip_levels = mips
	view.layers = count
	view.variant = View_Image {
		mip_level   = base_mip + mip_level,
		first_layer = base_layer + first_layer,
		shape       = view_shape,
	}
	view_info: vk.ImageViewCreateInfo = {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image.handle,
		viewType = VIEW_TYPES[view_shape],
		format = view_format,
		subresourceRange = {
			aspectMask = view_aspect,
			baseMipLevel = base_mip + mip_level,
			levelCount = mips,
			baseArrayLayer = base_layer + first_layer,
			layerCount = count,
		},
	}
	if res := vk.CreateImageView(device.handle, &view_info, nil, &view.view); res != .SUCCESS {
		log.errorf("Failed to create image view: %v", res)
		return {}, .View_Creation_Failed
	}
	defer if err != nil {
		delete_image(&view)
	}
	view.attachment_view = view.view
	if view.usage & {.COLOR_ATTACHMENT, .DEPTH_STENCIL_ATTACHMENT} != {} && view_shape != .D3 && (view_shape != .D2 || mips > 1) {
		attachment_info := view_info
		attachment_info.viewType = .D2_ARRAY if count > 1 else .D2
		attachment_info.subresourceRange.levelCount = 1
		if res := vk.CreateImageView(device.handle, &attachment_info, nil, &view.attachment_view); res != .SUCCESS {
			log.errorf("Failed to create attachment view: %v", res)
			view.attachment_view = 0
			return view, .View_Creation_Failed
		}
	}
	acquire_image_slots(&view, &view_info) or_return
	if parent, has_parent := image.variant.(Owned_Image); has_parent && parent.name != "" {
		name_image(view, fmt.tprintf("%v mips %v-%v layers %v-%v", parent.name, mip_level, mip_level + mips - 1, first_layer, first_layer + count - 1))
	}
	return
}

@(private = "file")
name_image :: proc(image: Image, name: string) {
	name_object(.IMAGE, u64(image.handle), name)
	name_object(.IMAGE_VIEW, u64(image.view), name)
	if image.attachment_view != image.view {
		name_object(.IMAGE_VIEW, u64(image.attachment_view), fmt.tprintf("%v attachment", name))
	}
}

@(private)
view_base :: proc(image: Image) -> (mip_level, first_layer: u32) {
	if view, is_view := image.variant.(View_Image); is_view {
		return view.mip_level, view.first_layer
	}
	return 0, 0
}

@(private = "file")
image_shape :: proc(image: Image) -> Image_Shape {
	#partial switch variant in image.variant {
	case Owned_Image:
		return variant.shape
	case View_Image:
		return variant.shape
	}
	if image.extent.z > 1 {
		return .D3
	}
	return .D2 if image.layers == 1 else .D2_Array
}

@(private = "file")
default_view_shape :: proc(parent: Image_Shape, layers: u32) -> Image_Shape {
	switch parent {
	case .D1, .D1_Array:
		return .D1 if layers == 1 else .D1_Array
	case .D3:
		return .D3
	case .Cube, .Cube_Array:
		if layers == 6 {
			return .Cube
		} else if layers % 6 == 0 {
			return .Cube_Array
		}
	case .D2, .D2_Array:
	}
	return .D2 if layers == 1 else .D2_Array
}

delete_image :: proc(image: ^Image) {
	if _, is_view := image.variant.(View_Image); is_view {
		release_image_slots(image)
		if image.attachment_view != 0 && image.attachment_view != image.view {
			vk.DestroyImageView(device.handle, image.attachment_view, nil)
		}
		if image.view != 0 {
			vk.DestroyImageView(device.handle, image.view, nil)
		}
	}
	if owned, is_owned := &image.variant.(Owned_Image); is_owned {
		settle_staging()
		release_image_slots(image)
		if image.attachment_view != 0 && image.attachment_view != image.view {
			vk.DestroyImageView(device.handle, image.attachment_view, nil)
		}
		if image.view != 0 {
			vk.DestroyImageView(device.handle, image.view, nil)
		}
		if image.handle != 0 {
			vk.DestroyImage(device.handle, image.handle, nil)
		}
		free_memory(&owned.allocation)
		delete(owned.name)
	}
	image^ = {}
}

@(private = "file")
@(require_results)
read_image_file :: proc(filename: string) -> ([]u8, Error) {
	data, read_err := os.read_entire_file(filename, context.temp_allocator)
	if read_err != nil {
		log.errorf("Failed to read %v: %v", filename, read_err)
		return nil, .Image_File_Read_Failed
	}
	return data, nil
}

@(private = "file")
@(require_results)
load_encoded_to_image :: proc(filename: string, data: []u8, image: ^Image, mip_level, layer: u32) -> Error {
	width, height, channels: i32
	pixels: rawptr
	#partial switch image.format {
	case .R8G8B8A8_SRGB, .R8G8B8A8_UNORM:
		pixels = stbi.load_from_memory(raw_data(data), i32(len(data)), &width, &height, &channels, 4)
	case .R16G16B16A16_UNORM:
		pixels = stbi.load_16_from_memory(raw_data(data), i32(len(data)), &width, &height, &channels, 4)
	case .R32G32B32A32_SFLOAT:
		pixels = stbi.loadf_from_memory(raw_data(data), i32(len(data)), &width, &height, &channels, 4)
	case:
		log.errorf("Image files load into RGBA8, RGBA16 UNORM or RGBA32 float images, not %v", image.format)
		return .Unsupported_Format
	}
	if pixels == nil {
		log.errorf("Failed to decode %v: %v", filename, stbi.failure_reason())
		return .Image_Decode_Failed
	}
	defer stbi.image_free(pixels)

	extent := mip_extent(image^, mip_level)
	if mip_level >= image.mip_levels || u32(width) != extent.x || u32(height) != extent.y || extent.z != 1 {
		log.errorf("%v is %vx%v, which does not match mip %v of a %v image", filename, width, height, mip_level, image.extent)
		return .Invalid_Upload
	}
	texel_size, _ := format_texel_size(image.format)
	return load_memory_to_image(([^]u8)(pixels)[:int(width) * int(height) * int(texel_size)], image, mip_level, layer)
}

@(private)
mip_extent :: proc(image: Image, mip_level: u32) -> [3]u32 {
	return {max(image.extent.x >> mip_level, 1), max(image.extent.y >> mip_level, 1), max(image.extent.z >> mip_level, 1)}
}

is_srgb_format :: proc(format: vk.Format) -> bool {
	#partial switch format {
	case .R8_SRGB, .R8G8_SRGB, .R8G8B8_SRGB, .B8G8R8_SRGB, .R8G8B8A8_SRGB, .B8G8R8A8_SRGB, .A8B8G8R8_SRGB_PACK32,
	     .BC1_RGB_SRGB_BLOCK, .BC1_RGBA_SRGB_BLOCK, .BC2_SRGB_BLOCK, .BC3_SRGB_BLOCK, .BC7_SRGB_BLOCK,
	     .ETC2_R8G8B8_SRGB_BLOCK, .ETC2_R8G8B8A1_SRGB_BLOCK, .ETC2_R8G8B8A8_SRGB_BLOCK, .ASTC_4x4_SRGB_BLOCK:
		return true
	}
	return false
}

srgb_to_linear :: proc(colour: [4]f32) -> (linear: [4]f32) {
	for channel in 0 ..< 3 {
		value := colour[channel]
		linear[channel] = value / 12.92 if value <= 0.04045 else math.pow((value + 0.055) / 1.055, 2.4)
	}
	linear.a = colour.a
	return
}

linear_to_srgb :: proc(colour: [4]f32) -> (encoded: [4]f32) {
	for channel in 0 ..< 3 {
		value := clamp(colour[channel], 0, 1)
		encoded[channel] = value * 12.92 if value <= 0.0031308 else 1.055 * math.pow(value, 1 / 2.4) - 0.055
	}
	encoded.a = colour.a
	return
}

@(private = "file")
is_depth_format :: proc(format: vk.Format) -> bool {
	#partial switch format {
	case .D16_UNORM, .X8_D24_UNORM_PACK32, .D32_SFLOAT, .S8_UINT, .D16_UNORM_S8_UINT, .D24_UNORM_S8_UINT, .D32_SFLOAT_S8_UINT:
		return true
	}
	return false
}

@(private = "file")
format_aspect :: proc(format: vk.Format) -> vk.ImageAspectFlags {
	#partial switch format {
	case .S8_UINT:
		return {.STENCIL}
	case .D16_UNORM_S8_UINT, .D24_UNORM_S8_UINT, .D32_SFLOAT_S8_UINT:
		return {.DEPTH, .STENCIL}
	case .D16_UNORM, .X8_D24_UNORM_PACK32, .D32_SFLOAT:
		return {.DEPTH}
	}
	return {.COLOR}
}

@(private = "file")
@(require_results)
describe_image :: proc(settings: Image_Settings) -> (image: Image, err: Error) {
	if settings.format == .UNDEFINED {
		log.error("Image settings need a format")
		return {}, .Invalid_Settings
	}
	if (settings.kind == .Depth) != is_depth_format(settings.format) {
		log.errorf("A %v image cannot use format %v", settings.kind, settings.format)
		return {}, .Invalid_Settings
	}

	size := settings.size
	elements := max(settings.layers, 1)
	switch settings.shape {
	case .D1:
		image.extent, image.layers = {size.x, 1, 1}, 1
	case .D1_Array:
		image.extent, image.layers = {size.x, 1, 1}, elements
	case .D2:
		image.extent, image.layers = {size.x, size.y, 1}, 1
	case .D2_Array:
		image.extent, image.layers = {size.x, size.y, 1}, elements
	case .D3:
		image.extent, image.layers = size, 1
	case .Cube:
		image.extent, image.layers = {size.x, size.y, 1}, 6
	case .Cube_Array:
		image.extent, image.layers = {size.x, size.y, 1}, 6 * elements
	}
	if image.extent.x == 0 || image.extent.y == 0 || image.extent.z == 0 {
		log.errorf("A %v image needs a non-zero size, got %v", settings.shape, size)
		return {}, .Invalid_Settings
	}
	if (settings.shape == .Cube || settings.shape == .Cube_Array) && image.extent.x != image.extent.y {
		log.errorf("Cube image faces must be square, got %v", size.xy)
		return {}, .Invalid_Settings
	}

	full_chain := u32(bits.len(max(image.extent.x, image.extent.y, image.extent.z, 1)))
	image.mip_levels = max(settings.mip_levels, 1)
	if image.mip_levels > full_chain {
		log.errorf("%v mip levels requested but a %v image has at most %v", image.mip_levels, image.extent, full_chain)
		return {}, .Invalid_Settings
	}

	samples := max(settings.samples, 1)
	if samples & (samples - 1) != 0 || samples > 64 {
		log.errorf("Image sample count must be a power of two up to 64, got %v", samples)
		return {}, .Invalid_Settings
	}
	if samples > 1 && (settings.shape != .D2 || image.mip_levels > 1 || settings.kind == .Generic) {
		log.error("Multisampled images must be single-mip 2D colour or depth images")
		return {}, .Invalid_Settings
	}
	image.samples = transmute(vk.SampleCountFlags)samples

	image.format = settings.format
	image.variant = Owned_Image {
		kind  = settings.kind,
		shape = settings.shape,
	}
	image.aspect = format_aspect(settings.format)
	image.usage = IMAGE_USAGE[settings.kind]
	if samples > 1 {
		image.usage -= {.SAMPLED, .STORAGE}
	}
	image.layout = .UNDEFINED
	return
}

@(private)
format_texel_size :: proc(format: vk.Format) -> (size: u32, known: bool) {
	#partial switch format {
	case .R8_UNORM, .R8_SNORM, .R8_UINT, .R8_SINT, .R8_SRGB, .S8_UINT:
		return 1, true
	case .R8G8_UNORM, .R8G8_SNORM, .R8G8_UINT, .R8G8_SINT, .R8G8_SRGB, .R16_UNORM, .R16_SNORM, .R16_UINT, .R16_SINT, .R16_SFLOAT, .D16_UNORM:
		return 2, true
	case .R8G8B8A8_UNORM, .R8G8B8A8_SNORM, .R8G8B8A8_UINT, .R8G8B8A8_SINT, .R8G8B8A8_SRGB, .B8G8R8A8_UNORM, .B8G8R8A8_SRGB, .R16G16_UNORM, .R16G16_SNORM, .R16G16_UINT, .R16G16_SINT, .R16G16_SFLOAT, .R32_UINT, .R32_SINT, .R32_SFLOAT, .A2B10G10R10_UNORM_PACK32, .A2R10G10B10_UNORM_PACK32, .B10G11R11_UFLOAT_PACK32, .E5B9G9R9_UFLOAT_PACK32, .D32_SFLOAT, .X8_D24_UNORM_PACK32:
		return 4, true
	case .R16G16B16A16_UNORM, .R16G16B16A16_SNORM, .R16G16B16A16_UINT, .R16G16B16A16_SINT, .R16G16B16A16_SFLOAT, .R32G32_UINT, .R32G32_SINT, .R32G32_SFLOAT:
		return 8, true
	case .R32G32B32A32_UINT, .R32G32B32A32_SINT, .R32G32B32A32_SFLOAT:
		return 16, true
	}
	return 0, false
}
