package Valhalla

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import stbi "vendor:stb/image"
import vk "vendor:vulkan"

Workload_Error :: enum {
	None,
	Command_Pool_Creation_Failed,
	Command_Buffer_Allocation_Failed,
	Recording_Failed,
	Sync_Creation_Failed,
	Submit_Failed,
	Wait_Failed,
	Present_Failed,
	Swapchain_Changed,
	Readback_Format_Unsupported,
	Readback_Write_Failed,
}

PUSH_HEADER_SIZE :: 16

MAX_EXECUTIONS_IN_FLIGHT :: 3

@(private)
TABLE_HEADER_WORDS :: 4

@(private)
TABLE_CHUNK_SIZE :: 16 * 1024

Workload_State :: enum {
	Recording,
	Finalized,
}

Execution :: struct {
	fence: vk.Fence,
}

Readback :: struct {
	buffer: Buffer,
	format: vk.Format,
	extent: [3]u32,
	layers: u32,
}

@(private)
Resource_Key :: struct {
	handle:      u64,
	image:       bool,
	first_mip:   u32,
	mips:        u32,
	first_layer: u32,
	layers:      u32,
	aspect:      vk.ImageAspectFlags,
	format:      vk.Format,
}

@(private)
Handle_Key :: struct {
	handle: u64,
	image:  bool,
}

@(private)
Resource_State :: struct {
	version:  u32,
	writer:   u64,
	used:     bool,
	produced: bool,
	name:     string,
}

@(private)
Handle_State :: struct {
	written:   u32,
	read:      u32,
	presented: bool,
	discarded: bool,
	keys:      int,
	layout:    vk.ImageLayout,
	image:     vk.Image,
	aspect:    vk.ImageAspectFlags,
}

@(private)
Rendering_Scope :: struct {
	open:         bool,
	colours:      [MAX_COLOUR_ATTACHMENTS]u64,
	colour_count: int,
	depth:        u64,
	view_mask:    u32,
}

@(private)
Acquired_Surface :: struct {
	surface:    ^Surface,
	generation: u64,
	presented:  bool,
}

@(private)
Execution_Slot :: struct {
	fence:    vk.Fence,
	acquired: [dynamic]vk.Semaphore,
}

Workload :: struct {
	name:           string,
	id:             u64,
	consumed:       [dynamic]u64,
	command_pool:   vk.CommandPool,
	command_buffer: vk.CommandBuffer,
	state:        Workload_State,
	resources:    map[Resource_Key]Resource_State,
	handles:      map[Handle_Key]Handle_State,
	clears:       [dynamic]Pending_Clear,
	scope:        Rendering_Scope,
	raw_written:  bool,
	epoch:        u32,
	emitted:      Emitted_State,
	tables:       [dynamic]Buffer,
	table_used:   int,
	acquired:     [dynamic]Acquired_Surface,
	readbacks:    [dynamic]Buffer,
	slots:        [MAX_EXECUTIONS_IN_FLIGHT]Execution_Slot,
	next_slot:    int,
}

@(private)
Pending_Clear :: struct {
	image:   Image,
	value:   vk.ClearValue,
	version: u32,
}

@(private)
Emitted_State :: struct {
	valid:        bool,
	state:        Draw_State,
	viewport:     vk.Viewport,
	scissor:      vk.Rect2D,
	samples:      vk.SampleCountFlags,
	colour_count: int,
}

@(private = "file")
Access :: struct {
	key:        Resource_Key,
	version:    u32,
	producer:   u64,
	name:       string,
	read:       bool,
	write:      bool,
	attachment: bool,
	layout:     vk.ImageLayout,
	image:      vk.Image,
	aspect:     vk.ImageAspectFlags,
}

@(require_results)
make_workload :: proc(name := "workload") -> (workload: Workload, err: Error) {
	assert(initialised, "Valhalla.init must be called before make_workload")
	for index := len(retired_workloads) - 1; index >= 0; index -= 1 {
		if !workload_idle(&retired_workloads[index]) {
			continue
		}
		workload = retired_workloads[index]
		unordered_remove(&retired_workloads, index)
		set_workload_name(&workload, name)
		register_workload(&workload)
		if err = begin_recording(&workload); err != nil {
			destroy_workload(&workload)
			return {}, err
		}
		return
	}
	pool_info: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = device.queue_families.graphics,
	}
	if res := vk.CreateCommandPool(device.handle, &pool_info, nil, &workload.command_pool); res != .SUCCESS {
		log.errorf("Failed to create workload command pool: %v", res)
		return {}, .Command_Pool_Creation_Failed
	}
	defer if err != nil {
		destroy_workload(&workload)
	}
	set_workload_name(&workload, name)
	register_workload(&workload)
	begin_recording(&workload) or_return
	return
}

@(private = "file")
set_workload_name :: proc(workload: ^Workload, name: string) {
	delete(workload.name)
	workload.name = strings.clone(name)
	name_object(.COMMAND_POOL, u64(workload.command_pool), name)
	if workload.command_buffer != nil {
		name_object(.COMMAND_BUFFER, u64(uintptr(workload.command_buffer)), name)
	}
}

@(private = "file")
MAX_RETIRED_WORKLOADS :: 8

@(private = "file")
retired_workloads: [dynamic]Workload

@(private = "file")
workload_idle :: proc(workload: ^Workload) -> bool {
	for slot in workload.slots {
		if slot.fence != 0 && vk.GetFenceStatus(device.handle, slot.fence) != .SUCCESS {
			return false
		}
	}
	return true
}

@(private)
release_workload_pool :: proc() {
	for &workload in retired_workloads {
		destroy_workload(&workload)
	}
	delete(retired_workloads)
	retired_workloads = nil
	for _, record in workload_records {
		delete(record.name)
	}
	delete(workload_records)
	workload_records = nil
	for warning in warned_writes {
		delete(warning.workload)
	}
	delete(warned_writes)
	warned_writes = nil
}

@(require_results)
acquire :: proc(workload: ^Workload, surface: ^Surface) -> (image: Image, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	for acquired in workload.acquired {
		assert(acquired.surface != surface, "a workload acquires from each surface once")
	}
	update_surface(surface) or_return
	if surface.minimised {
		return {}, .Surface_Minimised
	}
	append(&workload.acquired, Acquired_Surface{surface = surface, generation = surface.generation})
	image = surface.stand_in
	image.variant = Swapchain_Image {
		surface = surface,
	}
	return image, nil
}

@(require_results)
bind_shader :: proc(workload: ^Workload, shader: Shader) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot bind a shader to a finalized workload; reset_workload to record again")
	recording := shader.recording
	graphics, is_graphics := shader.variant.(Graphics_Shader)
	assert(
		shader.push_size <= PUSH_HEADER_SIZE || len(recording.push_data) > 0,
		"the shader's push block holds more than the Valhalla header, but no set_push_data was recorded",
	)

	accesses := make([dynamic]Access, 0, len(recording.bindings) + MAX_COLOUR_ATTACHMENTS + 2, context.temp_allocator)
	push_reads := make([dynamic]Shader_Resource, context.temp_allocator)
	pack_push_data(shader, &push_reads)
	for resource in push_reads {
		#partial switch read in resource {
		case Image:
			append(&accesses, image_access(read, read = true, write = false))
		case Buffer:
			append(&accesses, buffer_access(read, read = true, write = false))
		}
	}
	for binding in recording.bindings {
		switch resource in binding.resource {
		case Image:
			append(&accesses, image_access(resource, read = !binding.written, write = binding.written))
		case Buffer:
			append(&accesses, buffer_access(resource, read = !binding.written, write = binding.written))
		case Sampler:
		}
	}
	if index_buffer, has_index_buffer := recording.index_buffer.?; has_index_buffer {
		append(&accesses, buffer_access(index_buffer, read = true, write = false))
	}
	for command in recording.commands {
		#partial switch draw in command {
		case Draw_Indirect_Command:
			append(&accesses, buffer_access(draw.buffer, read = true, write = false))
			if count, has_count := draw.count_buffer.?; has_count {
				append(&accesses, buffer_access(count, read = true, write = false))
			}
		case Dispatch_Indirect_Command:
			append(&accesses, buffer_access(draw.buffer, read = true, write = false))
		}
	}

	scope: Rendering_Scope
	extent: [2]u32
	samples: vk.SampleCountFlags
	if is_graphics {
		check_graphics_recording(recording, graphics)
		scope.view_mask = graphics.config.view_mask
		for image, index in recording.colour_attachments {
			check_view_mask(scope.view_mask, image)
			access := attachment_access(image)
			scope.colours[index] = u64(image.attachment_view if image.attachment_view != 0 else image.view)
			append(&accesses, access)
			extent, samples = attachment_extent(extent, samples, image)
		}
		scope.colour_count = len(recording.colour_attachments)
		if depth, has_depth := recording.depth_attachment.?; has_depth {
			check_view_mask(scope.view_mask, depth)
			access := attachment_access(depth)
			scope.depth = u64(depth.attachment_view if depth.attachment_view != 0 else depth.view)
			append(&accesses, access)
			extent, samples = attachment_extent(extent, samples, depth)
		}
		scope.open = true
		for access in accesses {
			if access.attachment {
				continue
			}
			for other in accesses {
				rendered := other.key
				rendered.mips = 1
				assert(!other.attachment || !keys_overlap(rendered, access.key), "a shader cannot read or write an image it also renders to")
			}
		}
	}

	same_scope := is_graphics && workload.scope.open && workload.scope == scope
	folded_colours: [MAX_COLOUR_ATTACHMENTS]Maybe(vk.ClearValue)
	folded_depth: Maybe(vk.ClearValue)
	folded_keys := make([dynamic]Resource_Key, 0, MAX_COLOUR_ATTACHMENTS + 1, context.temp_allocator)
	if len(workload.clears) > 0 {
		depth, has_depth := recording.depth_attachment.?
		for pending in workload.clears {
			folded := false
			if is_graphics && !same_scope {
				for image, index in recording.colour_attachments {
					if folds_into(pending, image, scope.view_mask) {
						folded_colours[index] = pending.value
						append(&folded_keys, attachment_access(image).key)
						folded = true
					}
				}
				if has_depth && folds_into(pending, depth, scope.view_mask) {
					folded_depth = pending.value
					append(&folded_keys, attachment_access(depth).key)
					folded = true
				}
			}
			if !folded {
				close_scope(workload)
				emit_clear(workload.command_buffer, pending)
			}
		}
		clear(&workload.clears)
	}
	hazard := workload.raw_written
	now := workload.epoch + 1
	for access in accesses {
		state, handle := resource_state(workload, access)
		check_version(state, handle, access, recording.id, handle.read == now)
		if same_scope && access.attachment {
			continue
		}
		if access.attachment && slice.contains(folded_keys[:], access.key) {
			continue
		}
		if handle.layout != .GENERAL {
			hazard = true
		}
		if access.read && handle.written == now {
			hazard = true
		}
		if access.write && (handle.written == now || handle.read == now) {
			hazard = true
		}
	}

	if hazard || !same_scope {
		close_scope(workload)
	}
	if hazard {
		emit_barrier(workload, accesses[:])
	}
	if is_graphics && !workload.scope.open {
		open_scope(workload, recording, scope, extent, folded_colours, folded_depth)
	}

	now = workload.epoch + 1
	for access in accesses {
		state := &workload.resources[access.key]
		handle := &workload.handles[handle_key(access.key)]
		if access.write {
			assert(!state.produced, "this resource was produced by this workload and is written again; produce its final version")
			state.version = access.version + 1
			state.writer = recording.id
			state.used = false
			handle.written = now
		} else if access.read {
			handle.read = now
			mark_used(workload, state, handle^, access.key)
		}
	}

	table: vk.DeviceAddress
	if len(recording.bindings) > 0 {
		table = write_table(workload, recording) or_return
	}
	begin_label(workload.command_buffer, shader.name)
	workload.emitted = replay(workload.command_buffer, shader, recording, scope, extent, samples, table, workload.emitted)
	end_label(workload.command_buffer)
	return nil
}

clear_image :: proc(workload: ^Workload, image: Image, value: vk.ClearValue) -> (written: Image) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	assert(.TRANSFER_DST in image.usage, "the image cannot be cleared: it is not a transfer destination")
	for pending in workload.clears {
		if pending.image.handle == image.handle {
			flush_clears(workload)
			break
		}
	}
	record_write(workload, image_access(image, read = false, write = true), flush = false)
	append(&workload.clears, Pending_Clear{image = image, value = value, version = image.version + 1})
	written = image
	written.version += 1
	return
}

@(private = "file")
flush_clears :: proc(workload: ^Workload) {
	for pending in workload.clears {
		emit_clear(workload.command_buffer, pending)
	}
	clear(&workload.clears)
}

@(private = "file")
emit_clear :: proc(cmd: vk.CommandBuffer, pending: Pending_Clear) {
	image := pending.image
	value := pending.value
	base_mip, base_layer := view_base(image)
	range: vk.ImageSubresourceRange = {
		aspectMask     = image.aspect,
		baseMipLevel   = base_mip,
		levelCount     = image.mip_levels,
		baseArrayLayer = base_layer,
		layerCount     = image.layers,
	}
	begin_label(cmd, "clear_image")
	if .COLOR in image.aspect {
		vk.CmdClearColorImage(cmd, image.handle, .GENERAL, &value.color, 1, &range)
	} else {
		vk.CmdClearDepthStencilImage(cmd, image.handle, .GENERAL, &value.depthStencil, 1, &range)
	}
	end_label(cmd)
}

@(private = "file")
folds_into :: proc(pending: Pending_Clear, attachment: Image, view_mask: u32) -> bool {
	image := pending.image
	if image.view != attachment.view || pending.version != attachment.version || image.mip_levels != 1 {
		return false
	}
	if view_mask == 0 {
		return image.layers == 1
	}
	return image.layers < 32 && view_mask == (u32(1) << image.layers) - 1
}

clear_buffer :: proc(workload: ^Workload, buffer: Buffer, value: u32 = 0) -> (written: Buffer) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	access := buffer_access(buffer, read = false, write = true)
	record_write(workload, access)
	begin_label(workload.command_buffer, "clear_buffer")
	vk.CmdFillBuffer(workload.command_buffer, buffer.handle, 0, vk.DeviceSize(vk.WHOLE_SIZE), value)
	end_label(workload.command_buffer)
	written = buffer
	written.version += 1
	return
}

Image_Region :: struct {
	mip_level:   u32,
	first_layer: u32,
	layers:      u32,
	offset:      [3]u32,
	size:        [3]u32,
}

copy_buffer :: proc(
	workload: ^Workload,
	source, destination: Buffer,
	#any_int source_offset: int = 0,
	#any_int destination_offset: int = 0,
	#any_int size: int = 0,
) -> (
	written: Buffer,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	region := buffer_copy_region(source, destination, source_offset, destination_offset, size)
	record_copy(workload, buffer_access(source, read = true, write = false), buffer_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_buffer")
	emit_buffer_copy(workload.command_buffer, source, destination, region)
	end_label(workload.command_buffer)
	written = destination
	written.version += 1
	return
}

copy_image :: proc(
	workload: ^Workload,
	source, destination: Image,
	source_region := Image_Region{},
	destination_region := Image_Region{},
) -> (
	written: Image,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	region := image_copy_region(source, destination, source_region, destination_region)
	record_copy(workload, image_access(source, read = true, write = false), image_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_image")
	emit_image_copy(workload.command_buffer, source, destination, region)
	end_label(workload.command_buffer)
	written = destination
	written.version += 1
	return
}

blit_image :: proc(
	workload: ^Workload,
	source, destination: Image,
	source_region := Image_Region{},
	destination_region := Image_Region{},
	filter := vk.Filter.LINEAR,
) -> (
	written: Image,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	region := image_blit_region(source, destination, source_region, destination_region, filter)
	record_copy(workload, image_access(source, read = true, write = false), image_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "blit_image")
	emit_image_blit(workload.command_buffer, source, destination, region, filter)
	end_label(workload.command_buffer)
	written = destination
	written.version += 1
	return
}

generate_workload_mips :: proc(workload: ^Workload, image: Image) -> (written: Image) {
	assert(image.mip_levels > 1, "the image has one mip level, so there are no mips to generate; make it with mip_levels")
	written = image
	for mip in 1 ..< image.mip_levels {
		written = blit_image(workload, written, written, {mip_level = mip - 1}, {mip_level = mip})
	}
	return
}

copy_buffer_to_image :: proc(
	workload: ^Workload,
	source: Buffer,
	destination: Image,
	#any_int source_offset: int = 0,
	destination_region := Image_Region{},
) -> (
	written: Image,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	region := buffer_image_region(source, destination, source_offset, destination_region, to_image = true)
	record_copy(workload, buffer_access(source, read = true, write = false), image_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_buffer_to_image")
	emit_buffer_to_image(workload.command_buffer, source, destination, region)
	end_label(workload.command_buffer)
	written = destination
	written.version += 1
	return
}

copy_image_to_buffer :: proc(
	workload: ^Workload,
	source: Image,
	destination: Buffer,
	source_region := Image_Region{},
	#any_int destination_offset: int = 0,
) -> (
	written: Buffer,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	region := buffer_image_region(destination, source, destination_offset, source_region, to_image = false)
	record_copy(workload, image_access(source, read = true, write = false), buffer_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_image_to_buffer")
	emit_image_to_buffer(workload.command_buffer, source, destination, region)
	end_label(workload.command_buffer)
	written = destination
	written.version += 1
	return
}

@(require_results)
readback_image :: proc(workload: ^Workload, image: Image) -> (readback: Readback, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	assert(.TRANSFER_SRC in image.usage, "the image cannot be read back: it is not a transfer source")
	assert(card(image.aspect) == 1, "images with both depth and stencil cannot be read back yet")
	texel_size, known := format_texel_size(image.format)
	assert(known, "reading back this format is not supported yet")
	readback.buffer = make_readback_buffer(workload, int(texel_size * image.extent.x * image.extent.y * image.extent.z * image.layers)) or_return
	readback.format = image.format
	readback.extent = image.extent
	readback.layers = image.layers
	base_mip, base_layer := view_base(image)
	access := image_access(image, read = true, write = false)
	record_read(workload, access)
	region: vk.BufferImageCopy2 = {
		sType            = .BUFFER_IMAGE_COPY_2,
		imageSubresource = {aspectMask = image.aspect, mipLevel = base_mip, baseArrayLayer = base_layer, layerCount = image.layers},
		imageExtent      = {image.extent.x, image.extent.y, image.extent.z},
	}
	copy_info: vk.CopyImageToBufferInfo2 = {
		sType          = .COPY_IMAGE_TO_BUFFER_INFO_2,
		srcImage       = image.handle,
		srcImageLayout = .GENERAL,
		dstBuffer      = readback.buffer.handle,
		regionCount    = 1,
		pRegions       = &region,
	}
	begin_label(workload.command_buffer, "readback_image")
	vk.CmdCopyImageToBuffer2(workload.command_buffer, &copy_info)
	host_barrier(workload.command_buffer)
	end_label(workload.command_buffer)
	return
}

@(require_results)
readback_buffer :: proc(workload: ^Workload, buffer: Buffer) -> (readback: Readback, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	readback.buffer = make_readback_buffer(workload, int(buffer.size)) or_return
	access := buffer_access(buffer, read = true, write = false)
	record_read(workload, access)
	region: vk.BufferCopy2 = {
		sType = .BUFFER_COPY_2,
		size  = buffer.size,
	}
	copy_info: vk.CopyBufferInfo2 = {
		sType       = .COPY_BUFFER_INFO_2,
		srcBuffer   = buffer.handle,
		dstBuffer   = readback.buffer.handle,
		regionCount = 1,
		pRegions    = &region,
	}
	begin_label(workload.command_buffer, "readback_buffer")
	vk.CmdCopyBuffer2(workload.command_buffer, &copy_info)
	host_barrier(workload.command_buffer)
	end_label(workload.command_buffer)
	return
}

workload_produces_image :: proc(workload: ^Workload, image: Image) -> (produced: Image) {
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	_, is_swapchain := image.variant.(Swapchain_Image)
	assert(!is_swapchain, "a surface image's output is its present; it cannot be produced")
	mark_produced(workload, image_access(image, read = false, write = false))
	produced = image
	produced.version = 0
	produced.producer = workload.id
	return
}

workload_produces_buffer :: proc(workload: ^Workload, buffer: Buffer) -> (produced: Buffer) {
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	mark_produced(workload, buffer_access(buffer, read = false, write = false))
	produced = buffer
	produced.version = 0
	produced.producer = workload.id
	return
}

workload_produces :: proc {
	workload_produces_image,
	workload_produces_buffer,
}

workload_discards_image :: proc(workload: ^Workload, image: Image) {
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	_, handle := resource_state(workload, image_access(image, read = false, write = false))
	handle.discarded = true
}

workload_discards_buffer :: proc(workload: ^Workload, buffer: Buffer) {
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	_, handle := resource_state(workload, buffer_access(buffer, read = false, write = false))
	handle.discarded = true
}

workload_discards :: proc {
	workload_discards_image,
	workload_discards_buffer,
}

@(private = "file")
mark_produced :: proc(workload: ^Workload, access: Access) {
	state, written := &workload.resources[access.key]
	assert(written && access.version > 0, "workload_produces needs a version written in this workload")
	assert(state.version == access.version, "this version was already overwritten in this workload; produce the final version")
	state.produced = true
}

@(private = "file")
Warning_Key :: struct {
	workload: string,
	key:      Resource_Key,
}

@(private = "file")
warned_writes: map[Warning_Key]bool

@(private = "file")
warn_unused_writes :: proc(workload: ^Workload) {
	for key, state in workload.resources {
		if state.version == 0 || state.used || state.produced {
			continue
		}
		handle := workload.handles[handle_key(key)]
		if handle.discarded || handle.presented {
			continue
		}
		warning := Warning_Key{workload.name, key}
		if warning in warned_writes {
			continue
		}
		warning.workload = strings.clone(workload.name)
		warned_writes[warning] = true
		what := fmt.tprintf("\"%v\"", state.name) if state.name != "" else ("an unnamed image" if key.image else "an unnamed buffer")
		log.warnf(
			"Workload \"%v\" writes %v and nothing uses it; mark it with workload_produces if another workload or the next execution reads it, or workload_discards if it is scratch",
			workload.name,
			what,
		)
	}
}

@(private = "file")
Workload_Record :: struct {
	name:     string,
	executed: bool,
	warned:   bool,
}

@(private = "file")
workload_records: map[u64]Workload_Record

@(private = "file")
next_workload_id: u64

@(private = "file")
register_workload :: proc(workload: ^Workload) {
	next_workload_id += 1
	workload.id = next_workload_id
	workload_records[workload.id] = {name = strings.clone(workload.name)}
}

@(private = "file")
unregister_workload :: proc(workload: ^Workload) {
	if record, found := workload_records[workload.id]; found {
		delete(record.name)
		delete_key(&workload_records, workload.id)
	}
}

readback :: proc {
	readback_image,
	readback_buffer,
}

readback_data :: proc(readback: Readback) -> []u8 {
	return readback.buffer.mapped[:readback.buffer.size]
}

@(require_results)
write_readback :: proc(readback: Readback, file: ^os.File, encoded := true) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	data := readback_data(readback)
	if !encoded || readback.format == .UNDEFINED {
		if _, err := os.write(file, data); err != nil {
			log.errorf("Failed to write a readback: %v", err)
			return .Readback_Write_Failed
		}
		return nil
	}
	width, height := i32(readback.extent.x), i32(readback.extent.y) * i32(readback.extent.z * max(readback.layers, 1))
	sink := Readback_Sink {
		file = file,
	}
	written: i32
	#partial switch readback.format {
	case .R8G8B8A8_UNORM, .R8G8B8A8_SRGB:
		written = stbi.write_png_to_func(write_to_sink, &sink, width, height, 4, raw_data(data), width * 4)
	case .B8G8R8A8_UNORM, .B8G8R8A8_SRGB:
		swizzled := make([]u8, len(data), context.temp_allocator)
		for index := 0; index < len(data); index += 4 {
			swizzled[index + 0] = data[index + 2]
			swizzled[index + 1] = data[index + 1]
			swizzled[index + 2] = data[index + 0]
			swizzled[index + 3] = data[index + 3]
		}
		written = stbi.write_png_to_func(write_to_sink, &sink, width, height, 4, raw_data(swizzled), width * 4)
	case .R32G32B32A32_SFLOAT:
		written = stbi.write_hdr_to_func(write_to_sink, &sink, width, height, 4, ([^]f32)(raw_data(data)))
	case:
		log.errorf("Encoding %v readbacks is not supported; RGBA8, BGRA8 and RGBA32 float are, or pass encoded = false for the raw texels", readback.format)
		return .Readback_Format_Unsupported
	}
	if written == 0 || sink.failed {
		log.error("Failed to write an encoded readback")
		return .Readback_Write_Failed
	}
	return nil
}

@(require_results)
write_readback_to_file :: proc(readback: Readback, filename: string, encoded := true) -> Error {
	file, open_err := os.open(filename, {.Write, .Create, .Trunc})
	if open_err != nil {
		log.errorf("Failed to open %v: %v", filename, open_err)
		return .Readback_Write_Failed
	}
	defer os.close(file)
	return write_readback(readback, file, encoded)
}

@(private = "file")
Readback_Sink :: struct {
	file:   ^os.File,
	failed: bool,
}

@(private = "file")
write_to_sink :: proc "c" (ctx: rawptr, data: rawptr, size: c.int) {
	context = runtime_context
	sink := (^Readback_Sink)(ctx)
	if sink.failed {
		return
	}
	if _, err := os.write(sink.file, ([^]u8)(data)[:size]); err != nil {
		sink.failed = true
	}
}

present :: proc(workload: ^Workload, image: Image) {
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	swapchain_image, is_swapchain := image.variant.(Swapchain_Image)
	assert(is_swapchain, "present needs an image from acquire")
	acquired := find_acquired(workload, swapchain_image.surface)
	assert(acquired != nil, "present needs an image this workload acquired")
	assert(!acquired.presented, "a workload presents each acquired image once")

	flush_clears(workload)
	access := image_access(image, read = true, write = false)
	state, handle := resource_state(workload, access)
	check_version(state, handle, access, 0, handle.read == workload.epoch + 1)
	close_scope(workload)
	handle.presented = true
	state.used = true
	acquired.presented = true
}

raw_commands :: proc(workload: ^Workload) -> vk.CommandBuffer {
	assert(workload.state == .Recording, "cannot record into a finalized workload")
	close_scope(workload)
	flush_clears(workload)
	global_barrier(workload.command_buffer)
	workload.epoch += 1
	workload.emitted = {}
	workload.raw_written = true
	return workload.command_buffer
}

@(require_results)
finalize_workload :: proc(workload: ^Workload) -> Error {
	assert(workload.state == .Recording, "finalize_workload called twice")
	for acquired in workload.acquired {
		assert(acquired.presented, "a workload that acquires a swapchain image must present it")
	}
	close_scope(workload)
	flush_clears(workload)
	warn_unused_writes(workload)
	end_label(workload.command_buffer)
	if res := vk.EndCommandBuffer(workload.command_buffer); res != .SUCCESS {
		log.errorf("Failed to finish recording workload: %v", res)
		return .Recording_Failed
	}
	workload.state = .Finalized
	return nil
}

@(require_results)
execute_workload :: proc(workload: ^Workload) -> (execution: Execution, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(workload.state == .Finalized, "a workload must be finalized before it is executed")
	for producer in workload.consumed {
		if record, found := &workload_records[producer]; found && !record.executed && !record.warned {
			record.warned = true
			log.warnf("Workload \"%v\" uses an output of workload \"%v\", which has not been executed yet, so it reads whatever the resource held before", workload.name, record.name)
		}
	}
	flush_staging() or_return
	slot := take_slot(workload) or_return

	for acquired in workload.acquired {
		update_surface(acquired.surface) or_return
		if acquired.surface.minimised || acquired.surface.generation != acquired.generation {
			return {}, .Swapchain_Changed
		}
	}
	indices := make([]u32, len(workload.acquired), context.temp_allocator)
	for &acquired, index in workload.acquired {
		acquire_err: Error
		indices[index], acquire_err = acquire_next_image(acquired.surface, slot.acquired[index])
		if acquire_err != nil {
			release_acquires(slot.acquired[:index])
			if acquire_err == Surface_Error.Out_Of_Date {
				return {}, .Swapchain_Changed
			}
			return {}, acquire_err
		}
	}

	submit_count := 1 + len(workload.acquired)
	submits := make([]vk.SubmitInfo2, submit_count, context.temp_allocator)
	command_infos := make([]vk.CommandBufferSubmitInfo, submit_count, context.temp_allocator)
	wait_infos := make([]vk.SemaphoreSubmitInfo, submit_count, context.temp_allocator)
	signal_infos := make([]vk.SemaphoreSubmitInfo, submit_count, context.temp_allocator)
	command_infos[0] = {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = workload.command_buffer,
	}
	submits[0] = {
		sType                  = .SUBMIT_INFO_2,
		commandBufferInfoCount = 1,
		pCommandBufferInfos    = &command_infos[0],
	}
	for acquired, index in workload.acquired {
		submit := index + 1
		command_infos[submit] = {
			sType         = .COMMAND_BUFFER_SUBMIT_INFO,
			commandBuffer = acquired.surface.copies[indices[index]],
		}
		wait_infos[submit] = {
			sType     = .SEMAPHORE_SUBMIT_INFO,
			semaphore = slot.acquired[index],
			stageMask = {.ALL_TRANSFER},
		}
		signal_infos[submit] = {
			sType     = .SEMAPHORE_SUBMIT_INFO,
			semaphore = acquired.surface.present_semaphores[indices[index]],
			stageMask = {.ALL_COMMANDS},
		}
		submits[submit] = {
			sType                    = .SUBMIT_INFO_2,
			waitSemaphoreInfoCount   = 1,
			pWaitSemaphoreInfos      = &wait_infos[submit],
			commandBufferInfoCount   = 1,
			pCommandBufferInfos      = &command_infos[submit],
			signalSemaphoreInfoCount = 1,
			pSignalSemaphoreInfos    = &signal_infos[submit],
		}
	}

	vk.ResetFences(device.handle, 1, &slot.fence)
	if res := vk.QueueSubmit2(device.graphics_queue, u32(submit_count), raw_data(submits), slot.fence); res != .SUCCESS {
		log.errorf("Failed to submit workload: %v", res)
		empty: vk.SubmitInfo2 = {
			sType = .SUBMIT_INFO_2,
		}
		vk.QueueSubmit2(device.graphics_queue, 1, &empty, slot.fence)
		return {}, .Submit_Failed
	}
	workload.next_slot = (workload.next_slot + 1) % MAX_EXECUTIONS_IN_FLIGHT
	execution.fence = slot.fence
	if record, found := &workload_records[workload.id]; found {
		record.executed = true
	}

	if len(workload.acquired) > 0 {
		swapchains := make([]vk.SwapchainKHR, len(workload.acquired), context.temp_allocator)
		waits := make([]vk.Semaphore, len(workload.acquired), context.temp_allocator)
		results := make([]vk.Result, len(workload.acquired), context.temp_allocator)
		for acquired, index in workload.acquired {
			swapchains[index] = acquired.surface.swapchain
			waits[index] = signal_infos[index + 1].semaphore
		}
		present_info: vk.PresentInfoKHR = {
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = u32(len(waits)),
			pWaitSemaphores    = raw_data(waits),
			swapchainCount     = u32(len(swapchains)),
			pSwapchains        = raw_data(swapchains),
			pImageIndices      = raw_data(indices),
			pResults           = raw_data(results),
		}
		vk.QueuePresentKHR(device.present_queue, &present_info)
		for result, index in results {
			#partial switch result {
			case .SUCCESS:
			case .SUBOPTIMAL_KHR, .ERROR_OUT_OF_DATE_KHR:
				workload.acquired[index].surface.suboptimal = true
			case:
				log.errorf("Failed to present: %v", result)
				err = .Present_Failed
			}
		}
	}
	return
}

@(require_results)
wait_execution :: proc(execution: Execution) -> Error {
	fence := execution.fence
	if fence == 0 {
		return nil
	}
	if res := vk.WaitForFences(device.handle, 1, &fence, true, max(u64)); res != .SUCCESS {
		log.errorf("Failed to wait for a workload execution: %v", res)
		return .Wait_Failed
	}
	return nil
}

@(require_results)
reset_workload :: proc(workload: ^Workload) -> Error {
	wait_all(workload)
	return begin_recording(workload)
}

delete_workload :: proc(workload: ^Workload) {
	if workload.command_pool == 0 {
		workload^ = {}
		return
	}
	unregister_workload(workload)
	if len(retired_workloads) < MAX_RETIRED_WORKLOADS {
		append(&retired_workloads, workload^)
		workload^ = {}
		return
	}
	destroy_workload(workload)
}

@(private = "file")
destroy_workload :: proc(workload: ^Workload) {
	unregister_workload(workload)
	wait_all(workload)
	for &slot in workload.slots {
		if slot.fence != 0 {
			vk.DestroyFence(device.handle, slot.fence, nil)
		}
		for semaphore in slot.acquired {
			vk.DestroySemaphore(device.handle, semaphore, nil)
		}
		delete(slot.acquired)
	}
	if workload.command_pool != 0 {
		vk.DestroyCommandPool(device.handle, workload.command_pool, nil)
	}
	delete(workload.acquired)
	for &table in workload.tables {
		delete_buffer(&table)
	}
	delete(workload.tables)
	for &buffer in workload.readbacks {
		delete_buffer(&buffer)
	}
	delete(workload.readbacks)
	delete(workload.resources)
	delete(workload.handles)
	delete(workload.consumed)
	delete(workload.clears)
	delete(workload.name)
	workload^ = {}
}

@(private)
transition :: proc(command_buffer: vk.CommandBuffer, image: vk.Image, aspect: vk.ImageAspectFlags, from, to: vk.ImageLayout) {
	barrier: vk.ImageMemoryBarrier2 = {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = {.ALL_COMMANDS},
		srcAccessMask = {.MEMORY_WRITE},
		dstStageMask = {.ALL_COMMANDS},
		dstAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
		oldLayout = from,
		newLayout = to,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {aspectMask = aspect, levelCount = vk.REMAINING_MIP_LEVELS, layerCount = vk.REMAINING_ARRAY_LAYERS},
	}
	dependency: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(command_buffer, &dependency)
}

@(private = "file")
find_acquired :: proc(workload: ^Workload, surface: ^Surface) -> ^Acquired_Surface {
	for &acquired in workload.acquired {
		if acquired.surface == surface {
			return &acquired
		}
	}
	return nil
}

@(private = "file")
check_view_mask :: proc(view_mask: u32, image: Image) {
	if view_mask == 0 {
		return
	}
	highest := u32(31 - intrinsics.count_leading_zeros(view_mask))
	assert(highest < image.layers, "multiview renders view i into layer i, so every attachment needs a layer for each view in the shader's view mask")
}

@(private = "file")
image_access :: proc(image: Image, read, write: bool) -> Access {
	base_mip, base_layer := view_base(image)
	name: string
	if owned, is_owned := image.variant.(Owned_Image); is_owned {
		name = owned.name
	}
	return Access {
		producer = image.producer,
		name = name,
		key = {
			handle = u64(image.handle),
			image = true,
			first_mip = base_mip,
			mips = image.mip_levels,
			first_layer = base_layer,
			layers = image.layers,
			aspect = image.aspect,
			format = image.format,
		},
		version = image.version,
		read = read,
		write = write,
		layout = image.layout,
		image = image.handle,
		aspect = image.aspect,
	}
}

@(private = "file")
buffer_access :: proc(buffer: Buffer, read, write: bool) -> Access {
	name: string
	if owned, is_owned := buffer.variant.(Owned_Buffer); is_owned {
		name = owned.name
	}
	return {
		key = {handle = u64(buffer.handle)},
		version = buffer.version,
		producer = buffer.producer,
		name = name,
		read = read,
		write = write,
		layout = .GENERAL,
	}
}

@(private = "file")
attachment_access :: proc(image: Image) -> Access {
	access := image_access(image, read = true, write = true)
	access.attachment = true
	return access
}

@(private = "file")
attachment_extent :: proc(
	extent: [2]u32,
	samples: vk.SampleCountFlags,
	image: Image,
) -> (
	[2]u32,
	vk.SampleCountFlags,
) {
	assert(extent == {} || extent == image.extent.xy, "every attachment of a shader must be the same size")
	assert(samples == {} || samples == image.samples, "every attachment of a shader must have the same sample count")
	return image.extent.xy, image.samples
}

@(private)
Resolved_Region :: struct {
	subresource: vk.ImageSubresourceLayers,
	offset:      vk.Offset3D,
	extent:      vk.Extent3D,
}

@(private)
Image_Copy_Region :: struct {
	from, to: Resolved_Region,
}

@(private)
Buffer_Image_Region :: struct {
	offset: vk.DeviceSize,
	image:  Resolved_Region,
}

@(private)
buffer_copy_region :: proc(source, destination: Buffer, source_offset, destination_offset, size: int) -> vk.BufferCopy2 {
	assert(source_offset >= 0 && vk.DeviceSize(source_offset) <= source.size, "the copy starts past the end of the source buffer")
	length := vk.DeviceSize(size) if size > 0 else source.size - vk.DeviceSize(source_offset)
	assert(vk.DeviceSize(source_offset) + length <= source.size, "the copy reads past the end of the source buffer")
	assert(destination_offset >= 0 && vk.DeviceSize(destination_offset) + length <= destination.size, "the copy writes past the end of the destination buffer")
	if source.handle == destination.handle {
		assert(source.version == destination.version, "a copy within one buffer reads and writes the same version")
		lower, upper := min(source_offset, destination_offset), max(source_offset, destination_offset)
		assert(vk.DeviceSize(lower) + length <= vk.DeviceSize(upper), "a copy within one buffer cannot overlap itself")
	}
	return {sType = .BUFFER_COPY_2, srcOffset = vk.DeviceSize(source_offset), dstOffset = vk.DeviceSize(destination_offset), size = length}
}

@(private)
image_copy_region :: proc(source, destination: Image, source_region, destination_region: Image_Region) -> Image_Copy_Region {
	assert(.TRANSFER_SRC in source.usage, "the source image is not a transfer source")
	assert(.TRANSFER_DST in destination.usage, "the destination image is not a transfer destination")
	assert(source.aspect == destination.aspect, "a copy needs images with the same aspects")
	assert(source.samples == destination.samples, "a copy needs images with the same sample count")
	source_size, source_known := format_texel_size(source.format)
	destination_size, destination_known := format_texel_size(destination.format)
	assert(source_known && destination_known && source_size == destination_size, "a copy needs formats with the same texel size; use blit_image to convert")
	from := resolve_region(source, source_region)
	to := resolve_region(destination, destination_region, from.extent, from.subresource.layerCount)
	check_same_image(source, destination, from, to)
	return {from = from, to = to}
}

@(private)
image_blit_region :: proc(source, destination: Image, source_region, destination_region: Image_Region, filter: vk.Filter) -> Image_Copy_Region {
	assert(.TRANSFER_SRC in source.usage, "the source image is not a transfer source")
	assert(.TRANSFER_DST in destination.usage, "the destination image is not a transfer destination")
	assert(source.samples == {._1} && destination.samples == {._1}, "multisampled images cannot be blitted")
	assert(source.aspect == destination.aspect, "a blit needs images with the same aspects")
	assert(format_has_features(source.format, {.BLIT_SRC}), "the source format cannot be blitted from on this device")
	assert(format_has_features(destination.format, {.BLIT_DST}), "the destination format cannot be blitted to on this device")
	if filter == .LINEAR {
		assert(.COLOR in source.aspect, "depth and stencil images can only be blitted with .NEAREST")
		assert(format_has_features(source.format, {.SAMPLED_IMAGE_FILTER_LINEAR}), "the source format cannot be filtered linearly; blit with .NEAREST")
	}
	from := resolve_region(source, source_region)
	to := resolve_region(destination, destination_region, {}, from.subresource.layerCount)
	check_same_image(source, destination, from, to)
	return {from = from, to = to}
}

@(private = "file")
check_same_image :: proc(source, destination: Image, from, to: Resolved_Region) {
	if source.handle != destination.handle {
		return
	}
	assert(source.version == destination.version, "a copy within one image reads and writes the same version")
	a, b := from.subresource, to.subresource
	disjoint := a.mipLevel != b.mipLevel || a.baseArrayLayer + a.layerCount <= b.baseArrayLayer || b.baseArrayLayer + b.layerCount <= a.baseArrayLayer
	assert(disjoint, "a copy within one image must be between different mips or layers")
}

@(private)
buffer_image_region :: proc(buffer: Buffer, image: Image, buffer_offset: int, image_region: Image_Region, to_image: bool) -> Buffer_Image_Region {
	if to_image {
		assert(.TRANSFER_DST in image.usage, "the destination image is not a transfer destination")
	} else {
		assert(.TRANSFER_SRC in image.usage, "the source image is not a transfer source")
	}
	assert(card(image.aspect) == 1, "copies between buffers and images need a single-aspect image")
	resolved := resolve_region(image, image_region)
	assert(buffer_offset >= 0 && vk.DeviceSize(buffer_offset) + region_bytes(image.format, resolved) <= buffer.size, "the image region needs more bytes than the buffer holds from that offset")
	return {offset = vk.DeviceSize(buffer_offset), image = resolved}
}

@(private)
emit_buffer_copy :: proc(cmd: vk.CommandBuffer, source, destination: Buffer, region: vk.BufferCopy2) {
	region := region
	copy_info: vk.CopyBufferInfo2 = {
		sType       = .COPY_BUFFER_INFO_2,
		srcBuffer   = source.handle,
		dstBuffer   = destination.handle,
		regionCount = 1,
		pRegions    = &region,
	}
	vk.CmdCopyBuffer2(cmd, &copy_info)
}

@(private)
emit_image_copy :: proc(cmd: vk.CommandBuffer, source, destination: Image, region: Image_Copy_Region) {
	copy_region: vk.ImageCopy2 = {
		sType          = .IMAGE_COPY_2,
		srcSubresource = region.from.subresource,
		srcOffset      = region.from.offset,
		dstSubresource = region.to.subresource,
		dstOffset      = region.to.offset,
		extent         = region.from.extent,
	}
	copy_info: vk.CopyImageInfo2 = {
		sType          = .COPY_IMAGE_INFO_2,
		srcImage       = source.handle,
		srcImageLayout = .GENERAL,
		dstImage       = destination.handle,
		dstImageLayout = .GENERAL,
		regionCount    = 1,
		pRegions       = &copy_region,
	}
	vk.CmdCopyImage2(cmd, &copy_info)
}

@(private)
emit_image_blit :: proc(cmd: vk.CommandBuffer, source, destination: Image, region: Image_Copy_Region, filter: vk.Filter) {
	far :: proc(region: Resolved_Region) -> vk.Offset3D {
		return {region.offset.x + i32(region.extent.width), region.offset.y + i32(region.extent.height), region.offset.z + i32(region.extent.depth)}
	}
	blit_region: vk.ImageBlit2 = {
		sType          = .IMAGE_BLIT_2,
		srcSubresource = region.from.subresource,
		srcOffsets     = {region.from.offset, far(region.from)},
		dstSubresource = region.to.subresource,
		dstOffsets     = {region.to.offset, far(region.to)},
	}
	blit_info: vk.BlitImageInfo2 = {
		sType          = .BLIT_IMAGE_INFO_2,
		srcImage       = source.handle,
		srcImageLayout = .GENERAL,
		dstImage       = destination.handle,
		dstImageLayout = .GENERAL,
		regionCount    = 1,
		pRegions       = &blit_region,
		filter         = filter,
	}
	vk.CmdBlitImage2(cmd, &blit_info)
}

@(private)
emit_buffer_to_image :: proc(cmd: vk.CommandBuffer, source: Buffer, destination: Image, region: Buffer_Image_Region) {
	copy_region: vk.BufferImageCopy2 = {
		sType            = .BUFFER_IMAGE_COPY_2,
		bufferOffset     = region.offset,
		imageSubresource = region.image.subresource,
		imageOffset      = region.image.offset,
		imageExtent      = region.image.extent,
	}
	copy_info: vk.CopyBufferToImageInfo2 = {
		sType          = .COPY_BUFFER_TO_IMAGE_INFO_2,
		srcBuffer      = source.handle,
		dstImage       = destination.handle,
		dstImageLayout = .GENERAL,
		regionCount    = 1,
		pRegions       = &copy_region,
	}
	vk.CmdCopyBufferToImage2(cmd, &copy_info)
}

@(private)
emit_image_to_buffer :: proc(cmd: vk.CommandBuffer, source: Image, destination: Buffer, region: Buffer_Image_Region) {
	copy_region: vk.BufferImageCopy2 = {
		sType            = .BUFFER_IMAGE_COPY_2,
		bufferOffset     = region.offset,
		imageSubresource = region.image.subresource,
		imageOffset      = region.image.offset,
		imageExtent      = region.image.extent,
	}
	copy_info: vk.CopyImageToBufferInfo2 = {
		sType          = .COPY_IMAGE_TO_BUFFER_INFO_2,
		srcImage       = source.handle,
		srcImageLayout = .GENERAL,
		dstBuffer      = destination.handle,
		regionCount    = 1,
		pRegions       = &copy_region,
	}
	vk.CmdCopyImageToBuffer2(cmd, &copy_info)
}

@(private = "file")
resolve_region :: proc(image: Image, region: Image_Region, default_extent: vk.Extent3D = {}, default_layers: u32 = 0) -> Resolved_Region {
	assert(region.mip_level < image.mip_levels, "the region's mip level is past the image's last mip")
	assert(region.first_layer < image.layers, "the region's first layer is past the image's last layer")
	layers := region.layers
	if layers == 0 {
		layers = default_layers if default_layers > 0 else image.layers - region.first_layer
	}
	assert(region.first_layer + layers <= image.layers, "the region's layers run past the image's last layer")
	mip := mip_extent(image, region.mip_level)
	defaults := [3]u32{default_extent.width, default_extent.height, default_extent.depth}
	size: [3]u32
	for axis in 0 ..< 3 {
		assert(region.offset[axis] < mip[axis], "the region starts outside the mip level")
		size[axis] = region.size[axis]
		if size[axis] == 0 {
			size[axis] = defaults[axis] if defaults[axis] > 0 else mip[axis] - region.offset[axis]
		}
		assert(defaults[axis] == 0 || size[axis] == defaults[axis], "a copy's destination region must be the size of its source region")
		assert(region.offset[axis] + size[axis] <= mip[axis], "the region runs past the edge of the mip level")
	}
	base_mip, base_layer := view_base(image)
	return {
		subresource = {aspectMask = image.aspect, mipLevel = base_mip + region.mip_level, baseArrayLayer = base_layer + region.first_layer, layerCount = layers},
		offset = {i32(region.offset.x), i32(region.offset.y), i32(region.offset.z)},
		extent = {size.x, size.y, size.z},
	}
}

@(private)
image_region_bytes :: proc(image: Image, region: Image_Region) -> int {
	return int(region_bytes(image.format, resolve_region(image, region)))
}

@(private = "file")
region_bytes :: proc(format: vk.Format, region: Resolved_Region) -> vk.DeviceSize {
	texel_size, known := format_texel_size(format)
	assert(known, "copying this format between buffers and images is not supported yet")
	extent := region.extent
	return vk.DeviceSize(texel_size) * vk.DeviceSize(extent.width) * vk.DeviceSize(extent.height) * vk.DeviceSize(extent.depth) * vk.DeviceSize(region.subresource.layerCount)
}

@(private)
format_has_features :: proc(format: vk.Format, features: vk.FormatFeatureFlags) -> bool {
	properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(device.physical_device, format, &properties)
	return properties.optimalTilingFeatures >= features
}

@(private = "file")
record_copy :: proc(workload: ^Workload, source, destination: Access) {
	if source.key == destination.key {
		record_write(workload, destination)
		return
	}
	record_read(workload, source)
	record_write(workload, destination)
}

@(private)
@(require_results)
staged_transfer :: proc() -> (cmd: vk.CommandBuffer, err: Error) {
	cmd = staging_commands() or_return
	memory_barrier(cmd, {.ALL_TRANSFER}, {.TRANSFER_WRITE}, {.ALL_TRANSFER}, {.TRANSFER_READ, .TRANSFER_WRITE})
	return
}

@(private)
end_staged_transfer :: proc(cmd: vk.CommandBuffer) {
	memory_barrier(cmd, {.ALL_TRANSFER}, {.TRANSFER_READ, .TRANSFER_WRITE}, {.ALL_TRANSFER}, {.TRANSFER_READ, .TRANSFER_WRITE})
}

@(private = "file")
handle_key :: proc(key: Resource_Key) -> Handle_Key {
	return {handle = key.handle, image = key.image}
}

@(private = "file")
keys_overlap :: proc(a, b: Resource_Key) -> bool {
	if a.handle != b.handle || a.image != b.image {
		return false
	}
	if !a.image {
		return true
	}
	mips := a.first_mip < b.first_mip + b.mips && b.first_mip < a.first_mip + a.mips
	layers := a.first_layer < b.first_layer + b.layers && b.first_layer < a.first_layer + a.layers
	return mips && layers
}

@(private = "file")
resource_state :: proc(workload: ^Workload, access: Access) -> (state: ^Resource_State, handle: ^Handle_State) {
	new_key: bool
	_, state, new_key, _ = map_entry(&workload.resources, access.key)
	if state.name == "" {
		state.name = access.name
	}
	if access.producer != 0 && access.producer != workload.id && !slice.contains(workload.consumed[:], access.producer) {
		append(&workload.consumed, access.producer)
	}
	inserted: bool
	_, handle, inserted, _ = map_entry(&workload.handles, handle_key(access.key))
	if inserted {
		handle^ = {
			layout = access.layout,
			image  = access.image,
			aspect = access.aspect,
		}
	}
	if new_key {
		handle.keys += 1
	}
	return
}

@(private = "file")
check_version :: proc(state: ^Resource_State, handle: ^Handle_State, access: Access, recording_id: u64, read_since_barrier: bool) {
	assert(!handle.presented, "an image cannot be used after it is presented in the same workload")
	missing :: "this version of the resource has not been written in this workload; bind its writer first, bind the original resource, or, if another workload wrote it, pass what workload_produces returned there"
	overwritten :: "this version of the resource was already overwritten in this workload; bind its readers before its writer"
	if access.write {
		continuing := recording_id != 0 && access.version + 1 == state.version && state.writer == recording_id && !read_since_barrier
		assert(access.version <= state.version, missing)
		assert(access.version == state.version || continuing, overwritten)
		return
	}
	assert(access.version <= state.version, missing)
	assert(access.version == state.version, overwritten)
}

@(private = "file")
record_write :: proc(workload: ^Workload, access: Access, flush := true) {
	if flush {
		flush_clears(workload)
	}
	state, handle := resource_state(workload, access)
	now := workload.epoch + 1
	check_version(state, handle, access, 0, handle.read == now)
	close_scope(workload)
	if workload.raw_written || handle.written == now || handle.read == now || handle.layout != .GENERAL {
		emit_barrier(workload, {access})
	}
	assert(!state.produced, "this resource was produced by this workload and is written again; produce its final version")
	state.version = access.version + 1
	state.writer = 0
	state.used = false
	handle.written = workload.epoch + 1
}

@(private = "file")
record_read :: proc(workload: ^Workload, access: Access) {
	flush_clears(workload)
	state, handle := resource_state(workload, access)
	now := workload.epoch + 1
	check_version(state, handle, access, 0, handle.read == now)
	close_scope(workload)
	if workload.raw_written || handle.written == now || handle.layout != .GENERAL {
		emit_barrier(workload, {access})
	}
	handle.read = workload.epoch + 1
	mark_used(workload, state, handle^, access.key)
}

@(private = "file")
mark_used :: proc(workload: ^Workload, state: ^Resource_State, handle: Handle_State, key: Resource_Key) {
	state.used = true
	if handle.keys < 2 {
		return
	}
	for other, &other_state in workload.resources {
		if keys_overlap(other, key) {
			other_state.used = true
		}
	}
}

@(private = "file")
emit_barrier :: proc(workload: ^Workload, accesses: []Access) {
	transitions := make([dynamic]^Handle_State, 0, len(accesses), context.temp_allocator)
	for access in accesses {
		handle := &workload.handles[handle_key(access.key)]
		if access.key.image && handle.layout != .GENERAL && !slice.contains(transitions[:], handle) {
			append(&transitions, handle)
		}
	}
	barriers := make([]vk.ImageMemoryBarrier2, len(transitions), context.temp_allocator)
	memory_barrier: vk.MemoryBarrier2 = {
		sType         = .MEMORY_BARRIER_2,
		srcStageMask  = {.ALL_COMMANDS},
		srcAccessMask = {.MEMORY_WRITE},
		dstStageMask  = {.ALL_COMMANDS},
		dstAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
	}
	for state, index in transitions {
		barriers[index] = {
			sType = .IMAGE_MEMORY_BARRIER_2,
			srcStageMask = {.ALL_COMMANDS},
			srcAccessMask = {.MEMORY_WRITE},
			dstStageMask = {.ALL_COMMANDS},
			dstAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
			oldLayout = state.layout,
			newLayout = .GENERAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = state.image,
			subresourceRange = {
				aspectMask = state.aspect,
				levelCount = vk.REMAINING_MIP_LEVELS,
				layerCount = vk.REMAINING_ARRAY_LAYERS,
			},
		}
	}
	dependency: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		memoryBarrierCount      = 1,
		pMemoryBarriers         = &memory_barrier,
		imageMemoryBarrierCount = u32(len(barriers)),
		pImageMemoryBarriers    = raw_data(barriers),
	}
	vk.CmdPipelineBarrier2(workload.command_buffer, &dependency)
	for state in transitions {
		state.layout = .GENERAL
	}
	workload.epoch += 1
	workload.raw_written = false
}

@(private)
memory_barrier :: proc(
	cmd: vk.CommandBuffer,
	src_stage: vk.PipelineStageFlags2,
	src_access: vk.AccessFlags2,
	dst_stage: vk.PipelineStageFlags2,
	dst_access: vk.AccessFlags2,
) {
	barrier: vk.MemoryBarrier2 = {
		sType         = .MEMORY_BARRIER_2,
		srcStageMask  = src_stage,
		srcAccessMask = src_access,
		dstStageMask  = dst_stage,
		dstAccessMask = dst_access,
	}
	vk.CmdPipelineBarrier2(cmd, &vk.DependencyInfo{sType = .DEPENDENCY_INFO, memoryBarrierCount = 1, pMemoryBarriers = &barrier})
}

@(private = "file")
global_barrier :: proc(cmd: vk.CommandBuffer) {
	memory_barrier(cmd, {.ALL_COMMANDS}, {.MEMORY_WRITE}, {.ALL_COMMANDS}, {.MEMORY_READ, .MEMORY_WRITE})
}

@(private = "file")
host_barrier :: proc(cmd: vk.CommandBuffer) {
	memory_barrier(cmd, {.ALL_TRANSFER}, {.TRANSFER_WRITE}, {.HOST}, {.HOST_READ})
}

@(private = "file")
open_scope :: proc(
	workload: ^Workload,
	recording: Shader_Recording,
	scope: Rendering_Scope,
	extent: [2]u32,
	folded_colours: [MAX_COLOUR_ATTACHMENTS]Maybe(vk.ClearValue),
	folded_depth: Maybe(vk.ClearValue),
) {
	colours := make([]vk.RenderingAttachmentInfo, len(recording.colour_attachments), context.temp_allocator)
	depth, has_depth := recording.depth_attachment.?
	for image, index in recording.colour_attachments {
		colours[index] = {
			sType       = .RENDERING_ATTACHMENT_INFO,
			imageView   = image.attachment_view if image.attachment_view != 0 else image.view,
			imageLayout = .GENERAL,
			loadOp      = .LOAD,
			storeOp     = .STORE,
		}
		if value, folded := folded_colours[index].?; folded {
			colours[index].loadOp = .CLEAR
			colours[index].clearValue = value
		}
	}
	depth_info: vk.RenderingAttachmentInfo
	if has_depth {
		depth_info = {
			sType       = .RENDERING_ATTACHMENT_INFO,
			imageView   = depth.attachment_view if depth.attachment_view != 0 else depth.view,
			imageLayout = .GENERAL,
			loadOp      = .LOAD,
			storeOp     = .STORE,
		}
		if value, folded := folded_depth.?; folded {
			depth_info.loadOp = .CLEAR
			depth_info.clearValue = value
		}
	}
	rendering_info: vk.RenderingInfo = {
		sType                = .RENDERING_INFO,
		renderArea           = {extent = {extent.x, extent.y}},
		layerCount           = 1,
		viewMask             = scope.view_mask,
		colorAttachmentCount = u32(len(colours)),
		pColorAttachments    = raw_data(colours),
		pDepthAttachment     = &depth_info if has_depth && .DEPTH in depth.aspect else nil,
		pStencilAttachment   = &depth_info if has_depth && .STENCIL in depth.aspect else nil,
	}
	vk.CmdBeginRendering(workload.command_buffer, &rendering_info)
	workload.scope = scope
}

@(private = "file")
close_scope :: proc(workload: ^Workload) {
	if workload.scope.open {
		vk.CmdEndRendering(workload.command_buffer)
		workload.scope = {}
	}
}

@(private = "file")
replay :: proc(
	cmd: vk.CommandBuffer,
	shader: Shader,
	recording: Shader_Recording,
	scope: Rendering_Scope,
	extent: [2]u32,
	samples: vk.SampleCountFlags,
	table: vk.DeviceAddress,
	emitted: Emitted_State,
) -> Emitted_State {
	draw_data := command_draw_data(recording.commands[0]) if len(recording.commands) > 0 else 0
	header := Push_Header {
		table     = table,
		draw_data = draw_data,
	}
	push_info: vk.PushDataInfoEXT = {
		sType = .PUSH_DATA_INFO_EXT,
		data  = {address = &header, size = size_of(header)},
	}
	if len(recording.push_data) > 0 {
		(^Push_Header)(raw_data(recording.push_data))^ = header
		push_info.data = {address = raw_data(recording.push_data), size = len(recording.push_data)}
	}
	vk.CmdPushDataEXT(cmd, &push_info)

	graphics, is_graphics := shader.variant.(Graphics_Shader)
	if is_graphics {
		vk.CmdBindPipeline(cmd, .GRAPHICS, shader.handle)
		if index_buffer, has_index_buffer := recording.index_buffer.?; has_index_buffer {
			index_type: vk.IndexType = .UINT32 if recording.index_type == .U32 else .UINT16
			vk.CmdBindIndexBuffer2(cmd, index_buffer.handle, 0, index_buffer.size, index_type)
		}
	} else {
		vk.CmdBindPipeline(cmd, .COMPUTE, shader.handle)
	}
	last := emitted
	if is_graphics && graphics.mesh {
		last.valid = false
	}
	current := -1
	for command in recording.commands {
		if next := command_draw_data(command); next != draw_data {
			draw_data = next
			draw_data_info: vk.PushDataInfoEXT = {
				sType  = .PUSH_DATA_INFO_EXT,
				offset = u32(offset_of(Push_Header, draw_data)),
				data   = {address = &draw_data, size = size_of(draw_data)},
			}
			vk.CmdPushDataEXT(cmd, &draw_data_info)
		}
		state_index := -1
		switch draw in command {
		case Draw_Command:
			state_index = draw.state
		case Draw_Indexed_Command:
			state_index = draw.state
		case Draw_Indirect_Command:
			state_index = draw.state
		case Draw_Mesh_Command:
			state_index = draw.state
		case Dispatch_Command, Dispatch_Indirect_Command:
		}
		if state_index >= 0 && state_index != current {
			emit_draw_state(cmd, recording.states[state_index], scope, extent, samples, &last)
			current = state_index
		}
		switch draw in command {
		case Draw_Command:
			vk.CmdDraw(cmd, draw.vertex_count, draw.instances, draw.first_vertex, draw.first_instance)
		case Draw_Indexed_Command:
			vk.CmdDrawIndexed(cmd, draw.index_count, draw.instances, draw.first_index, draw.vertex_offset, draw.first_instance)
		case Draw_Indirect_Command:
			emit_indirect(cmd, draw)
		case Draw_Mesh_Command:
			vk.CmdDrawMeshTasksEXT(cmd, draw.groups.x, draw.groups.y, draw.groups.z)
		case Dispatch_Command:
			vk.CmdDispatch(cmd, draw.groups.x, draw.groups.y, draw.groups.z)
		case Dispatch_Indirect_Command:
			vk.CmdDispatchIndirect(cmd, draw.buffer.handle, draw.offset)
		}
	}
	if is_graphics && graphics.mesh {
		last.valid = false
	}
	return last
}

@(private = "file")
Push_Header :: struct {
	table:     vk.DeviceAddress,
	draw_data: u32,
	reserved:  u32,
}

#assert(size_of(Push_Header) == PUSH_HEADER_SIZE)

@(private = "file")
command_draw_data :: proc(command: Shader_Command) -> u32 {
	switch draw in command {
	case Draw_Command:
		return draw.draw_data
	case Draw_Indexed_Command:
		return draw.draw_data
	case Draw_Indirect_Command:
		return draw.draw_data
	case Draw_Mesh_Command:
		return draw.draw_data
	case Dispatch_Command:
		return draw.draw_data
	case Dispatch_Indirect_Command:
		return draw.draw_data
	}
	return 0
}

@(private = "file")
emit_indirect :: proc(cmd: vk.CommandBuffer, draw: Draw_Indirect_Command) {
	buffer := draw.buffer.handle
	if count, has_count := draw.count_buffer.?; has_count {
		switch draw.kind {
		case .Vertices:
			vk.CmdDrawIndirectCount(cmd, buffer, draw.offset, count.handle, draw.count_offset, draw.draws, draw.stride)
		case .Indexed:
			vk.CmdDrawIndexedIndirectCount(cmd, buffer, draw.offset, count.handle, draw.count_offset, draw.draws, draw.stride)
		case .Mesh_Tasks:
			vk.CmdDrawMeshTasksIndirectCountEXT(cmd, buffer, draw.offset, count.handle, draw.count_offset, draw.draws, draw.stride)
		}
		return
	}
	switch draw.kind {
	case .Vertices:
		vk.CmdDrawIndirect(cmd, buffer, draw.offset, draw.draws, draw.stride)
	case .Indexed:
		vk.CmdDrawIndexedIndirect(cmd, buffer, draw.offset, draw.draws, draw.stride)
	case .Mesh_Tasks:
		vk.CmdDrawMeshTasksIndirectEXT(cmd, buffer, draw.offset, draw.draws, draw.stride)
	}
}

@(private = "file")
check_graphics_recording :: proc(recording: Shader_Recording, graphics: Graphics_Shader) {
	config := graphics.config
	assert(
		len(recording.colour_attachments) == colour_format_count(config),
		"a graphics shader must bind one colour attachment per colour format it was made with",
	)
	depth, has_depth := recording.depth_attachment.?
	wants_depth := config.depth_format != .UNDEFINED || config.stencil_format != .UNDEFINED
	assert(has_depth == wants_depth, "a graphics shader binds a depth attachment exactly when it was made with a depth or stencil format")
	assert(len(recording.colour_attachments) > 0 || has_depth, "a graphics shader needs at least one attachment")
	for command in recording.commands {
		_, is_indexed := command.(Draw_Indexed_Command)
		if indirect, is_indirect := command.(Draw_Indirect_Command); is_indirect && indirect.kind == .Indexed {
			is_indexed = true
		}
		if is_indexed {
			_, has_index_buffer := recording.index_buffer.?
			assert(has_index_buffer, "indexed draws need bind_shader_index_buffer")
		}
	}
	colour_slots: bit_set[0 ..< MAX_COLOUR_ATTACHMENTS]
	for index in 0 ..< len(recording.colour_attachments) {
		colour_slots += {index}
	}
	for state in recording.states {
		assert(state.colour_state_set <= colour_slots, "the shader sets blending or a write mask on a colour attachment it does not bind")
		assert(!(state.depth_test || state.depth_write || state.depth_bias) || (has_depth && .DEPTH in depth.aspect), "depth state needs a depth attachment")
		assert(!state.stencil_test || (has_depth && .STENCIL in depth.aspect), "stencil testing needs a stencil attachment")
	}
}

@(private = "file")
emit_draw_state :: proc(
	cmd: vk.CommandBuffer,
	state: Draw_State,
	scope: Rendering_Scope,
	extent: [2]u32,
	samples: vk.SampleCountFlags,
	last: ^Emitted_State,
) {
	viewport, has_viewport := state.viewport.?
	if !has_viewport {
		viewport = {width = f32(extent.x), height = f32(extent.y), maxDepth = 1}
	}
	scissor, has_scissor := state.scissor.?
	if !has_scissor {
		scissor = {extent = {extent.x, extent.y}}
	}
	fresh := !last.valid
	previous := last.state
	if fresh || viewport != last.viewport {
		vk.CmdSetViewportWithCount(cmd, 1, &viewport)
	}
	if fresh || scissor != last.scissor {
		vk.CmdSetScissorWithCount(cmd, 1, &scissor)
	}
	if fresh || state.depth_bias != previous.depth_bias {
		vk.CmdSetDepthBiasEnable(cmd, b32(state.depth_bias))
	}
	if fresh || state.depth_bias_values != previous.depth_bias_values {
		vk.CmdSetDepthBias(cmd, state.depth_bias_values[0], state.depth_bias_values[2], state.depth_bias_values[1])
	}
	if fresh || state.blend_constants != previous.blend_constants {
		blend_constants := state.blend_constants
		vk.CmdSetBlendConstants(cmd, &blend_constants)
	}
	front, back := state.stencil_front, state.stencil_back
	front_changed := fresh || front != previous.stencil_front
	back_changed := fresh || back != previous.stencil_back
	if front_changed && back_changed && front == back {
		emit_stencil(cmd, {.FRONT, .BACK}, front)
	} else {
		if front_changed {
			emit_stencil(cmd, {.FRONT}, front)
		}
		if back_changed {
			emit_stencil(cmd, {.BACK}, back)
		}
	}
	if fresh || state.stencil_test != previous.stencil_test {
		vk.CmdSetStencilTestEnable(cmd, b32(state.stencil_test))
	}
	if fresh || state.cull_mode != previous.cull_mode {
		vk.CmdSetCullMode(cmd, state.cull_mode)
	}
	if fresh || state.front_face != previous.front_face {
		vk.CmdSetFrontFace(cmd, state.front_face)
	}
	if fresh || state.topology != previous.topology {
		vk.CmdSetPrimitiveTopology(cmd, state.topology)
	}
	if fresh || state.primitive_restart != previous.primitive_restart {
		vk.CmdSetPrimitiveRestartEnable(cmd, b32(state.primitive_restart))
	}
	if fresh || state.depth_test != previous.depth_test {
		vk.CmdSetDepthTestEnable(cmd, b32(state.depth_test))
	}
	if fresh || state.depth_write != previous.depth_write {
		vk.CmdSetDepthWriteEnable(cmd, b32(state.depth_write))
	}
	if fresh || state.depth_compare != previous.depth_compare {
		vk.CmdSetDepthCompareOp(cmd, state.depth_compare)
	}
	if fresh || state.polygon_mode != previous.polygon_mode {
		vk.CmdSetPolygonModeEXT(cmd, state.polygon_mode)
	}
	if fresh || samples != last.samples {
		vk.CmdSetRasterizationSamplesEXT(cmd, samples)
	}
	if fresh || state.alpha_to_coverage != previous.alpha_to_coverage {
		vk.CmdSetAlphaToCoverageEnableEXT(cmd, b32(state.alpha_to_coverage))
	}
	if fresh || state.depth_clamp != previous.depth_clamp {
		vk.CmdSetDepthClampEnableEXT(cmd, b32(state.depth_clamp))
	}

	count := scope.colour_count
	colour_changed := fresh || count != last.colour_count
	for index in 0 ..< count {
		if colour_changed {
			break
		}
		equation, enabled := state.blend[index].?
		previous_equation, previous_enabled := previous.blend[index].?
		colour_changed = enabled != previous_enabled || (enabled && equation != previous_equation) || state.write_masks[index] != previous.write_masks[index]
	}
	if count > 0 && colour_changed {
		enables: [MAX_COLOUR_ATTACHMENTS]b32
		equations: [MAX_COLOUR_ATTACHMENTS]vk.ColorBlendEquationEXT
		for index in 0 ..< count {
			equation, enabled := state.blend[index].?
			enables[index] = b32(enabled)
			equations[index] = equation if enabled else BLEND_REPLACE
		}
		write_masks := state.write_masks
		vk.CmdSetColorBlendEnableEXT(cmd, 0, u32(count), &enables[0])
		vk.CmdSetColorBlendEquationEXT(cmd, 0, u32(count), &equations[0])
		vk.CmdSetColorWriteMaskEXT(cmd, 0, u32(count), &write_masks[0])
	}
	last^ = {
		valid        = true,
		state        = state,
		viewport     = viewport,
		scissor      = scissor,
		samples      = samples,
		colour_count = count,
	}
}

@(private = "file")
BLEND_REPLACE :: vk.ColorBlendEquationEXT {
	srcColorBlendFactor = .ONE,
	dstColorBlendFactor = .ZERO,
	colorBlendOp        = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ZERO,
	alphaBlendOp        = .ADD,
}

@(private = "file")
emit_stencil :: proc(cmd: vk.CommandBuffer, faces: vk.StencilFaceFlags, stencil: Stencil_State) {
	vk.CmdSetStencilOp(cmd, faces, stencil.fail_op, stencil.pass_op, stencil.depth_fail_op, stencil.compare_op)
	vk.CmdSetStencilReference(cmd, faces, stencil.reference)
	vk.CmdSetStencilCompareMask(cmd, faces, stencil.compare_mask)
	vk.CmdSetStencilWriteMask(cmd, faces, stencil.write_mask)
}

@(private = "file")
@(require_results)
write_table :: proc(workload: ^Workload, recording: Shader_Recording) -> (address: vk.DeviceAddress, err: Error) {
	size := align_up(vk.DeviceSize(size_of(u32) * (TABLE_HEADER_WORDS + len(recording.bindings))), 16)
	if len(workload.tables) == 0 || vk.DeviceSize(workload.table_used) + size > vk.DeviceSize(TABLE_CHUNK_SIZE) {
		chunk := make_empty_buffer(TABLE_CHUNK_SIZE, Buffer_Settings{memory = .Host_Visible}) or_return
		append(&workload.tables, chunk)
		workload.table_used = 0
	}
	chunk := workload.tables[len(workload.tables) - 1]
	words := ([^]u32)(&chunk.mapped[workload.table_used])
	words[0] = u32(len(recording.bindings))
	words[1] = null_buffer_index()
	words[2] = null_image_index() | HEAP_IMAGE_TAG
	words[3] = null_sampler_index() | HEAP_SAMPLER_TAG
	for binding, index in recording.bindings {
		entry: u32
		switch resource in binding.resource {
		case Image:
			entry = resource.heap_index | HEAP_IMAGE_TAG
		case Buffer:
			entry = resource.heap_index
		case Sampler:
			entry = resource.heap_index | HEAP_SAMPLER_TAG
		}
		words[TABLE_HEADER_WORDS + index] = entry
	}
	address = chunk.address + vk.DeviceAddress(workload.table_used)
	workload.table_used += int(size)
	return
}

@(private = "file")
@(require_results)
make_readback_buffer :: proc(workload: ^Workload, size: int) -> (buffer: Buffer, err: Error) {
	buffer = make_empty_buffer(size, Buffer_Settings{memory = .Host_Readback}) or_return
	append(&workload.readbacks, buffer)
	return
}

@(private = "file")
@(require_results)
begin_command_buffer :: proc(workload: ^Workload) -> Error {
	if workload.command_buffer == nil {
		buffer_info: vk.CommandBufferAllocateInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = workload.command_pool,
			level              = .PRIMARY,
			commandBufferCount = 1,
		}
		if res := vk.AllocateCommandBuffers(device.handle, &buffer_info, &workload.command_buffer); res != .SUCCESS {
			log.errorf("Failed to allocate a workload command buffer: %v", res)
			workload.command_buffer = nil
			return .Command_Buffer_Allocation_Failed
		}
		name_object(.COMMAND_BUFFER, u64(uintptr(workload.command_buffer)), workload.name)
	} else if res := vk.ResetCommandBuffer(workload.command_buffer, {}); res != .SUCCESS {
		log.errorf("Failed to reset the workload command buffer: %v", res)
		return .Recording_Failed
	}
	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.SIMULTANEOUS_USE},
	}
	if res := vk.BeginCommandBuffer(workload.command_buffer, &begin_info); res != .SUCCESS {
		log.errorf("Failed to begin recording workload: %v", res)
		return .Recording_Failed
	}
	bind_descriptor_heaps(workload.command_buffer)
	begin_label(workload.command_buffer, workload.name)
	global_barrier(workload.command_buffer)
	workload.emitted = {}
	return nil
}

@(private = "file")
@(require_results)
take_slot :: proc(workload: ^Workload) -> (slot: ^Execution_Slot, err: Error) {
	slot = &workload.slots[workload.next_slot]
	if slot.fence == 0 {
		fence_info: vk.FenceCreateInfo = {
			sType = .FENCE_CREATE_INFO,
			flags = {.SIGNALED},
		}
		if res := vk.CreateFence(device.handle, &fence_info, nil, &slot.fence); res != .SUCCESS {
			log.errorf("Failed to create a workload fence: %v", res)
			return nil, .Sync_Creation_Failed
		}
	}
	for len(slot.acquired) < len(workload.acquired) {
		semaphore_info: vk.SemaphoreCreateInfo = {
			sType = .SEMAPHORE_CREATE_INFO,
		}
		semaphore: vk.Semaphore
		if res := vk.CreateSemaphore(device.handle, &semaphore_info, nil, &semaphore); res != .SUCCESS {
			log.errorf("Failed to create an acquire semaphore: %v", res)
			return nil, .Sync_Creation_Failed
		}
		append(&slot.acquired, semaphore)
	}
	if res := vk.WaitForFences(device.handle, 1, &slot.fence, true, max(u64)); res != .SUCCESS {
		log.errorf("Failed to wait for an earlier execution: %v", res)
		return nil, .Wait_Failed
	}
	return
}

@(private = "file")
release_acquires :: proc(semaphores: []vk.Semaphore) {
	if len(semaphores) == 0 {
		return
	}
	waits := make([]vk.SemaphoreSubmitInfo, len(semaphores), context.temp_allocator)
	for semaphore, index in semaphores {
		waits[index] = {
			sType     = .SEMAPHORE_SUBMIT_INFO,
			semaphore = semaphore,
			stageMask = {.ALL_COMMANDS},
		}
	}
	submit_info: vk.SubmitInfo2 = {
		sType                  = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount = u32(len(waits)),
		pWaitSemaphoreInfos    = raw_data(waits),
	}
	vk.QueueSubmit2(device.graphics_queue, 1, &submit_info, 0)
}

@(private = "file")
wait_all :: proc(workload: ^Workload) {
	for &slot in workload.slots {
		if slot.fence != 0 {
			vk.WaitForFences(device.handle, 1, &slot.fence, true, max(u64))
		}
	}
}

@(private = "file")
@(require_results)
begin_recording :: proc(workload: ^Workload) -> Error {
	clear(&workload.acquired)
	begin_command_buffer(workload) or_return
	workload.state = .Recording
	clear(&workload.resources)
	clear(&workload.consumed)
	clear(&workload.clears)
	clear(&workload.handles)
	workload.scope = {}
	workload.raw_written = false
	workload.table_used = 0
	for &table in workload.tables[min(1, len(workload.tables)):] {
		delete_buffer(&table)
	}
	resize(&workload.tables, min(1, len(workload.tables)))
	for &buffer in workload.readbacks {
		delete_buffer(&buffer)
	}
	clear(&workload.readbacks)
	return nil
}
