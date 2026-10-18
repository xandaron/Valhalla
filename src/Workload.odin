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
	Readback_Format_Unsupported,
	Readback_Write_Failed,
}

PUSH_HEADER_SIZE :: 16

MAX_EXECUTIONS_IN_FLIGHT :: 3

@(private)
TABLE_HEADER_WORDS :: 5

@(private)
TABLE_CHUNK_SIZE :: 16 * 1024

Workload_State :: enum {
	Recording,
	Finalized,
}

Execution :: struct {
	value: u64,
}

Readback :: struct {
	buffer: Buffer,
	format: Format,
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
	aspect:      Image_Aspect,
	format:      Format,
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
	aspect:    Image_Aspect,
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
Presentation :: struct {
	surface: ^Surface,
	image:   Image,
}

@(private)
Execution_Slot :: struct {
	value:              u64,
	acquire_semaphores: [dynamic]vk.Semaphore,
	present_commands:   [dynamic]vk.CommandBuffer,
}

@(private = "file")
Acquisition :: struct {
	surface:   ^Surface,
	semaphore: vk.Semaphore,
	index:     u32,
	copy:      vk.CommandBuffer,
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
	table_chunk:  int,
	table_used:   int,
	presentations: [dynamic]Presentation,
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
	aspect:     Image_Aspect,
}

@(require_results)
make_workload :: proc(name := "workload") -> (workload: Workload, err: Error) {
	assert(initialised, "Valhalla.init must be called before make_workload")
	reused := false
	for index := len(retired_workloads) - 1; index >= 0; index -= 1 {
		if workload_idle(&retired_workloads[index]) {
			workload = retired_workloads[index]
			unordered_remove(&retired_workloads, index)
			reused = true
			break
		}
	}
	if !reused {
		workload.command_pool = make_command_pool({.RESET_COMMAND_BUFFER}, name) or_return
	}
	defer if err != nil {
		destroy_workload(&workload)
	}
	delete(workload.name)
	workload.name = strings.clone(name)
	next_workload_id += 1
	workload.id = next_workload_id
	workload_records[workload.id] = {name = strings.clone(name)}
	begin_recording(&workload) or_return
	return
}

@(private = "file")
MAX_RETIRED_WORKLOADS :: 8

@(private = "file")
retired_workloads: [dynamic]Workload

@(private = "file")
timeline: vk.Semaphore

@(private = "file")
submitted_value: u64

@(private = "file")
workload_idle :: proc(workload: ^Workload) -> bool {
	completed := semaphore_value(timeline)
	for slot in workload.slots {
		if slot.value > completed {
			return false
		}
	}
	return true
}

// ===[ Deferred Destruction ]==================================================

@(private)
Grave_Resource :: union {
	Buffer,
	Image,
	vk.Pipeline,
	Sampler,
	Acceleration_Structure,
}

@(private = "file")
Grave :: struct {
	value:    u64,
	staging:  u64,
	resource: Grave_Resource,
}

@(private = "file")
graves: [dynamic]Grave

@(private)
bury :: proc(resource: Grave_Resource) {
	staging := staging_pending_value()
	if submitted_value <= semaphore_value(timeline) && staging <= staging_completed_value() {
		destroy_resource(resource)
		return
	}
	append(&graves, Grave{value = submitted_value, staging = staging, resource = resource})
}

@(private)
retire_graves :: proc(everything := false) {
	if len(graves) == 0 {
		return
	}
	completed := semaphore_value(timeline)
	staging := staging_completed_value()
	for index := 0; index < len(graves); {
		grave := graves[index]
		if everything || grave.value <= completed && grave.staging <= staging {
			destroy_resource(grave.resource)
			unordered_remove(&graves, index)
		} else {
			index += 1
		}
	}
	if everything {
		delete(graves)
		graves = nil
	}
}

@(private = "file")
destroy_resource :: proc(resource: Grave_Resource) {
	resource := resource
	switch &dead in resource {
	case Buffer:
		destroy_buffer(&dead)
	case Image:
		destroy_image(&dead)
	case vk.Pipeline:
		vk.DestroyPipeline(device.handle, dead, nil)
	case Sampler:
		release_sampler_slot(&dead)
	case Acceleration_Structure:
		vk.DestroyAccelerationStructureKHR(device.handle, dead.handle, nil)
		destroy_buffer(&dead.storage)
	}
}

@(private)
release_workload_pool :: proc() {
	retire_graves(everything = true)
	for &workload in retired_workloads {
		destroy_workload(&workload)
	}
	delete(retired_workloads)
	retired_workloads = nil
	if timeline != 0 {
		vk.DestroySemaphore(device.handle, timeline, nil)
		timeline = 0
	}
	submitted_value = 0
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
bind_shader :: proc(workload: ^Workload, shader: Shader) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	recording := shader.recording
	lock_recording(recording.id)
	graphics, is_graphics := shader.variant.(Graphics_Shader)
	assert(
		shader.push_size <= PUSH_HEADER_SIZE || len(recording.push_data) > 0,
		"the shader's push block holds more than the Valhalla header, but no set_push_data was recorded",
	)

	accesses := collect_accesses(shader)
	scope: Rendering_Scope
	extent: [2]u32
	samples: vk.SampleCountFlags
	if is_graphics {
		check_graphics_recording(recording, graphics)
		scope.view_mask = graphics.config.view_mask
		first_attachment := len(accesses)
		for image, index in recording.colour_attachments {
			check_view_mask(scope.view_mask, image)
			scope.colours[index] = u64(render_view(image))
			append(&accesses, attachment_access(image))
			extent, samples = attachment_extent(extent, samples, image)
		}
		scope.colour_count = len(recording.colour_attachments)
		if depth, has_depth := recording.depth_attachment.?; has_depth {
			check_view_mask(scope.view_mask, depth)
			scope.depth = u64(render_view(depth))
			append(&accesses, attachment_access(depth))
			extent, samples = attachment_extent(extent, samples, depth)
		}
		scope.open = true
		for access in accesses[:first_attachment] {
			for attachment in accesses[first_attachment:] {
				rendered := attachment.key
				rendered.mips = 1
				assert(!keys_overlap(rendered, access.key), "a shader cannot read or write an image it also renders to")
			}
		}
	}

	same_scope := is_graphics && workload.scope.open && workload.scope == scope
	folded_colours: [MAX_COLOUR_ATTACHMENTS]Maybe(vk.ClearValue)
	folded_depth: Maybe(vk.ClearValue)
	folded_keys := make([dynamic]Resource_Key, 0, MAX_COLOUR_ATTACHMENTS + 1, context.temp_allocator)
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

	hazard := workload.raw_written
	for access in accesses {
		state, handle := resource_state(workload, access)
		check_version(state, handle, access, recording.id, handle.read == workload.epoch)
		if access.attachment && (same_scope || slice.contains(folded_keys[:], access.key)) {
			continue
		}
		if has_hazard(workload, handle^, access) {
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
	for access in accesses {
		commit_access(workload, &workload.resources[access.key], &workload.handles[handle_key(access.key)], access, recording.id)
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

@(private = "file")
collect_accesses :: proc(shader: Shader) -> [dynamic]Access {
	recording := shader.recording
	accesses := make([dynamic]Access, 0, len(recording.bindings) + MAX_COLOUR_ATTACHMENTS + 2, context.temp_allocator)
	push_reads := make([dynamic]Shader_Resource, context.temp_allocator)
	pack_push_data(shader, &push_reads)
	for resource in push_reads {
		if access, tracked := resource_access(resource, read = true, write = false); tracked {
			append(&accesses, access)
		}
	}
	for binding in recording.bindings {
		if access, tracked := resource_access(binding.resource, read = !binding.written, write = binding.written); tracked {
			append(&accesses, access)
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
	return accesses
}

@(require_results)
clear_image :: proc(workload: ^Workload, image: Image, colour: [4]f32 = 0) -> Image {
	assert(.COLOR in image.aspect, "clear_image clears colour images; depth images are cleared with clear_depth")
	return record_clear(workload, image, {color = {float32 = colour}})
}

@(require_results)
clear_image_8bit :: proc(workload: ^Workload, image: Image, colour: [4]u8) -> Image {
	return clear_image(workload, image, [4]f32{f32(colour.r), f32(colour.g), f32(colour.b), f32(colour.a)} / 255)
}

@(require_results)
clear_depth :: proc(workload: ^Workload, image: Image, depth: f32 = 1, stencil: u32 = 0) -> Image {
	assert(.COLOR not_in image.aspect, "clear_depth clears depth and stencil images; colour images are cleared with clear_image")
	return record_clear(workload, image, {depthStencil = {depth = depth, stencil = stencil}})
}

@(private = "file")
@(require_results)
record_clear :: proc(workload: ^Workload, image: Image, value: vk.ClearValue) -> Image {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	assert(.TRANSFER_DST in image.usage, "the image cannot be cleared: it is not a transfer destination")
	for pending in workload.clears {
		if pending.image.handle == image.handle {
			flush_clears(workload)
			break
		}
	}
	record_access(workload, image_access(image, read = false, write = true), flush = false)
	append(&workload.clears, Pending_Clear{image = image, value = value, version = image.version + 1})
	return next_version(image)
}

@(private = "file")
flush_clears :: proc(workload: ^Workload) {
	for pending in workload.clears {
		emit_clear(workload.command_buffer, pending)
	}
	clear(&workload.clears)
}

@(private)
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

@(require_results)
clear_buffer :: proc(workload: ^Workload, buffer: Buffer, value: u32 = 0) -> Buffer {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	record_access(workload, buffer_access(buffer, read = false, write = true))
	begin_label(workload.command_buffer, "clear_buffer")
	vk.CmdFillBuffer(workload.command_buffer, buffer.handle, 0, vk.DeviceSize(vk.WHOLE_SIZE), value)
	end_label(workload.command_buffer)
	return next_version(buffer)
}

Image_Region :: struct {
	mip_level:   u32,
	first_layer: u32,
	layers:      u32,
	offset:      [3]u32,
	size:        [3]u32,
}

@(require_results)
copy_buffer :: proc(
	workload: ^Workload,
	source, destination: Buffer,
	#any_int source_offset: int = 0,
	#any_int destination_offset: int = 0,
	#any_int size: int = 0,
) -> Buffer {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	region := buffer_copy_region(source, destination, source_offset, destination_offset, size)
	record_copy(workload, buffer_access(source, read = true, write = false), buffer_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_buffer")
	emit_buffer_copy(workload.command_buffer, source.handle, destination.handle, region)
	end_label(workload.command_buffer)
	return next_version(destination)
}

@(require_results)
copy_image :: proc(
	workload: ^Workload,
	source, destination: Image,
	source_region := Image_Region{},
	destination_region := Image_Region{},
) -> Image {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	region := image_copy_region(source, destination, source_region, destination_region)
	record_copy(workload, image_access(source, read = true, write = false), image_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_image")
	emit_image_copy(workload.command_buffer, source.handle, destination.handle, region)
	end_label(workload.command_buffer)
	return next_version(destination)
}

@(require_results)
blit_image :: proc(
	workload: ^Workload,
	source, destination: Image,
	source_region := Image_Region{},
	destination_region := Image_Region{},
	filter := Filter.LINEAR,
) -> Image {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	region := image_blit_region(source, destination, source_region, destination_region, filter)
	record_copy(workload, image_access(source, read = true, write = false), image_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "blit_image")
	emit_image_blit(workload.command_buffer, source.handle, destination.handle, region, filter)
	end_label(workload.command_buffer)
	return next_version(destination)
}

@(require_results)
generate_mips :: proc(workload: ^Workload, image: Image) -> (written: Image) {
	assert(image.mip_levels > 1, "the image has one mip level, so there are no mips to generate; make it with mip_levels")
	written = image
	for mip in 1 ..< image.mip_levels {
		written = blit_image(workload, written, written, {mip_level = mip - 1}, {mip_level = mip})
	}
	return
}

@(require_results)
copy_buffer_to_image :: proc(
	workload: ^Workload,
	source: Buffer,
	destination: Image,
	#any_int source_offset: int = 0,
	destination_region := Image_Region{},
) -> Image {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	region := buffer_image_region(source, destination, source_offset, destination_region, to_image = true)
	record_copy(workload, buffer_access(source, read = true, write = false), image_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_buffer_to_image")
	emit_buffer_to_image(workload.command_buffer, source.handle, destination.handle, region)
	end_label(workload.command_buffer)
	return next_version(destination)
}

@(require_results)
copy_image_to_buffer :: proc(
	workload: ^Workload,
	source: Image,
	destination: Buffer,
	source_region := Image_Region{},
	#any_int destination_offset: int = 0,
) -> Buffer {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	region := buffer_image_region(destination, source, destination_offset, source_region, to_image = false)
	record_copy(workload, image_access(source, read = true, write = false), buffer_access(destination, read = false, write = true))
	begin_label(workload.command_buffer, "copy_image_to_buffer")
	emit_image_to_buffer(workload.command_buffer, source.handle, destination.handle, region)
	end_label(workload.command_buffer)
	return next_version(destination)
}

@(require_results)
readback_image :: proc(workload: ^Workload, image: Image) -> (readback: Readback, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	readback.buffer = make_readback_buffer(workload, image_region_bytes(image, {})) or_return
	readback.format = image.format
	readback.extent = image.extent
	readback.layers = image.layers
	region := buffer_image_region(readback.buffer, image, 0, {}, to_image = false)
	record_access(workload, image_access(image, read = true, write = false))
	begin_label(workload.command_buffer, "readback_image")
	emit_image_to_buffer(workload.command_buffer, image.handle, readback.buffer.handle, region)
	host_barrier(workload.command_buffer)
	end_label(workload.command_buffer)
	return
}

@(require_results)
readback_buffer :: proc(workload: ^Workload, buffer: Buffer) -> (readback: Readback, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert_recording(workload)
	readback.buffer = make_readback_buffer(workload, int(buffer.size)) or_return
	record_access(workload, buffer_access(buffer, read = true, write = false))
	begin_label(workload.command_buffer, "readback_buffer")
	emit_buffer_copy(workload.command_buffer, buffer.handle, readback.buffer.handle, {sType = .BUFFER_COPY_2, size = buffer.size})
	host_barrier(workload.command_buffer)
	end_label(workload.command_buffer)
	return
}

@(require_results)
workload_produces_image :: proc(workload: ^Workload, image: Image) -> (produced: Image) {
	assert_recording(workload)
	mark_produced(workload, image_access(image, read = false, write = false))
	produced = image
	produced.version = 0
	produced.producer = workload.id
	return
}

@(require_results)
workload_produces_buffer :: proc(workload: ^Workload, buffer: Buffer) -> (produced: Buffer) {
	assert_recording(workload)
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
	assert_recording(workload)
	_, handle := resource_state(workload, image_access(image, read = false, write = false))
	handle.discarded = true
}

workload_discards_buffer :: proc(workload: ^Workload, buffer: Buffer) {
	assert_recording(workload)
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
load_from_readback :: proc(readback: Readback, destination: $T, #any_int offset: int = 0) -> Error {
	return load_from_buffer(readback.buffer, destination, offset)
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

present :: proc(workload: ^Workload, image: Image, surface: ^Surface) {
	assert_recording(workload)
	assert(.COLOR in image.aspect && image.mip_levels >= 1, "present shows a colour image")
	for presentation in workload.presentations {
		assert(presentation.surface != surface, "a workload presents to each surface once")
	}

	flush_clears(workload)
	access := image_access(image, read = true, write = false)
	state, handle := resource_state(workload, access)
	check_version(state, handle, access, 0, handle.read == workload.epoch)
	close_scope(workload)
	handle.presented = true
	state.used = true
	append(&workload.presentations, Presentation{surface = surface, image = image})
}

raw_commands :: proc(workload: ^Workload) -> vk.CommandBuffer {
	assert_recording(workload)
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
execute_workloads :: proc(workloads: ..^Workload) -> (execution: Execution, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(len(workloads) > 0, "execute_workloads needs a workload")
	presentation_count := 0
	for workload, index in workloads {
		assert(workload.state == .Finalized, "a workload must be finalized before it is executed")
		assert(!slice.contains(workloads[:index], workload), "a workload appears once in an execution")
		for presentation in workload.presentations {
			for earlier in workloads[:index] {
				for other in earlier.presentations {
					assert(other.surface != presentation.surface, "an execution presents to each surface once")
				}
			}
		}
		presentation_count += len(workload.presentations)
		warn_unexecuted_producers(workload, workloads[:index])
	}
	create_timeline() or_return
	flush_staging() or_return
	slots := make([]^Execution_Slot, len(workloads), context.temp_allocator)
	for workload, index in workloads {
		slots[index] = take_slot(workload) or_return
	}
	retire_graves()

	acquisitions := make([dynamic]Acquisition, 0, presentation_count, context.temp_allocator)
	semaphores := make([dynamic]vk.Semaphore, 0, presentation_count, context.temp_allocator)
	for workload, index in workloads {
		for presentation, presentation_index in workload.presentations {
			surface := presentation.surface
			update_surface(surface) or_return
			semaphore := slots[index].acquire_semaphores[presentation_index]
			image_index: u32
			acquired: bool
			for !acquired && !surface.minimised {
				image_index, acquired = acquire_next_image(surface, semaphore) or_return
			}
			if !acquired {
				continue
			}
			append(&semaphores, semaphore)
			copy := slots[index].present_commands[presentation_index]
			if record_err := record_present(surface, presentation.image, image_index, copy); record_err != nil {
				release_acquires(semaphores[:])
				return {}, record_err
			}
			append(&acquisitions, Acquisition{surface = surface, semaphore = semaphore, index = image_index, copy = copy})
		}
	}
	acquired_count := len(acquisitions)

	value := submitted_value + 1
	submits := make([dynamic]vk.SubmitInfo2, 0, acquired_count + 2, context.temp_allocator)
	command_infos := make([]vk.CommandBufferSubmitInfo, len(workloads) + acquired_count, context.temp_allocator)
	wait_infos := make([]vk.SemaphoreSubmitInfo, acquired_count, context.temp_allocator)
	signal_infos := make([]vk.SemaphoreSubmitInfo, acquired_count + 1, context.temp_allocator)
	for workload, index in workloads {
		command_infos[index] = {sType = .COMMAND_BUFFER_SUBMIT_INFO, commandBuffer = workload.command_buffer}
	}
	append(&submits, vk.SubmitInfo2{sType = .SUBMIT_INFO_2, commandBufferInfoCount = u32(len(workloads)), pCommandBufferInfos = &command_infos[0]})
	for acquisition, index in acquisitions {
		command := &command_infos[len(workloads) + index]
		command^ = {sType = .COMMAND_BUFFER_SUBMIT_INFO, commandBuffer = acquisition.copy}
		wait_infos[index] = {sType = .SEMAPHORE_SUBMIT_INFO, semaphore = acquisition.semaphore, stageMask = {.ALL_TRANSFER}}
		signal_infos[index] = {sType = .SEMAPHORE_SUBMIT_INFO, semaphore = acquisition.surface.present_semaphores[acquisition.index], stageMask = {.ALL_COMMANDS}}
		append(
			&submits,
			vk.SubmitInfo2 {
				sType                    = .SUBMIT_INFO_2,
				waitSemaphoreInfoCount   = 1,
				pWaitSemaphoreInfos      = &wait_infos[index],
				commandBufferInfoCount   = 1,
				pCommandBufferInfos      = command,
				signalSemaphoreInfoCount = 1,
				pSignalSemaphoreInfos    = &signal_infos[index],
			},
		)
	}
	signal_infos[acquired_count] = {sType = .SEMAPHORE_SUBMIT_INFO, semaphore = timeline, value = value, stageMask = {.ALL_COMMANDS}}
	append(&submits, vk.SubmitInfo2{sType = .SUBMIT_INFO_2, signalSemaphoreInfoCount = 1, pSignalSemaphoreInfos = &signal_infos[acquired_count]})

	if res := vk.QueueSubmit2(device.graphics_queue, u32(len(submits)), raw_data(submits), 0); res != .SUCCESS {
		log.errorf("Failed to submit workloads: %v", res)
		release_acquires(semaphores[:])
		return {}, .Submit_Failed
	}
	submitted_value = value
	execution.value = value
	for workload, index in workloads {
		slots[index].value = value
		workload.next_slot = (workload.next_slot + 1) % MAX_EXECUTIONS_IN_FLIGHT
		if record, found := &workload_records[workload.id]; found {
			record.executed = true
		}
	}

	if acquired_count > 0 {
		swapchains := make([]vk.SwapchainKHR, acquired_count, context.temp_allocator)
		waits := make([]vk.Semaphore, acquired_count, context.temp_allocator)
		indices := make([]u32, acquired_count, context.temp_allocator)
		results := make([]vk.Result, acquired_count, context.temp_allocator)
		for acquisition, index in acquisitions {
			swapchains[index] = acquisition.surface.swapchain
			waits[index] = acquisition.surface.present_semaphores[acquisition.index]
			indices[index] = acquisition.index
		}
		present_info: vk.PresentInfoKHR = {
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = u32(acquired_count),
			pWaitSemaphores    = raw_data(waits),
			swapchainCount     = u32(acquired_count),
			pSwapchains        = raw_data(swapchains),
			pImageIndices      = raw_data(indices),
			pResults           = raw_data(results),
		}
		vk.QueuePresentKHR(device.present_queue, &present_info)
		for result, index in results {
			#partial switch result {
			case .SUCCESS:
			case .SUBOPTIMAL_KHR, .ERROR_OUT_OF_DATE_KHR:
				acquisitions[index].surface.suboptimal = true
			case:
				log.errorf("Failed to present: %v", result)
				err = .Present_Failed
			}
		}
	}
	return
}

@(private = "file")
warn_unexecuted_producers :: proc(workload: ^Workload, earlier: []^Workload) {
	consumed: for producer in workload.consumed {
		record, found := &workload_records[producer]
		if !found || record.executed || record.warned {
			continue
		}
		for other in earlier {
			if other.id == producer {
				continue consumed
			}
		}
		record.warned = true
		log.warnf("Workload \"%v\" uses an output of workload \"%v\", which has not been executed yet, so it reads whatever the resource held before", workload.name, record.name)
	}
}

@(require_results)
wait_execution :: proc(execution: Execution) -> Error {
	wait_value(execution.value) or_return
	retire_graves()
	return nil
}

@(private)
@(require_results)
wait_value :: proc(value: u64) -> Error {
	if value == 0 {
		return nil
	}
	return wait_semaphore(timeline, value)
}

@(private = "file")
@(require_results)
create_timeline :: proc() -> Error {
	if timeline != 0 {
		return nil
	}
	timeline = make_semaphore(true, "workload timeline") or_return
	return nil
}

@(private)
@(require_results)
run_workload :: proc(workload: ^Workload) -> Error {
	finalize_workload(workload) or_return
	execution := execute_workloads(workload) or_return
	return wait_execution(execution)
}

@(require_results)
reset_workload :: proc(workload: ^Workload) -> Error {
	wait_all(workload)
	retire_graves()
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
		for semaphore in slot.acquire_semaphores {
			vk.DestroySemaphore(device.handle, semaphore, nil)
		}
		delete(slot.acquire_semaphores)
		delete(slot.present_commands)
	}
	if workload.command_pool != 0 {
		vk.DestroyCommandPool(device.handle, workload.command_pool, nil)
	}
	delete(workload.presentations)
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
GLOBAL_BARRIER :: vk.MemoryBarrier2 {
	sType         = .MEMORY_BARRIER_2,
	srcStageMask  = {.ALL_COMMANDS},
	srcAccessMask = {.MEMORY_WRITE},
	dstStageMask  = {.ALL_COMMANDS},
	dstAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
}

@(private)
layout_barrier :: proc(image: vk.Image, aspect: Image_Aspect, from, to: vk.ImageLayout) -> vk.ImageMemoryBarrier2 {
	return {
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
}

@(private)
transition :: proc(command_buffer: vk.CommandBuffer, image: vk.Image, aspect: Image_Aspect, from, to: vk.ImageLayout) {
	barrier := layout_barrier(image, aspect, from, to)
	dependency: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(command_buffer, &dependency)
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
resource_access :: proc(resource: Shader_Resource, read, write: bool) -> (access: Access, tracked: bool) {
	switch bound in resource {
	case Image:
		return image_access(bound, read, write), true
	case Buffer:
		return buffer_access(bound, read, write), true
	case Sampler:
	}
	return
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
	assert(same_texel_size(source.format, destination.format), "a copy needs formats with the same texel size; use blit_image to convert")
	from := resolve_region(source, source_region)
	to := resolve_region(destination, destination_region, from.extent, from.subresource.layerCount)
	check_same_image(source, destination, from, to)
	return {from = from, to = to}
}

@(private)
image_blit_region :: proc(source, destination: Image, source_region, destination_region: Image_Region, filter: Filter) -> Image_Copy_Region {
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
emit_buffer_copy :: proc(cmd: vk.CommandBuffer, source, destination: vk.Buffer, region: vk.BufferCopy2) {
	region := region
	copy_info: vk.CopyBufferInfo2 = {
		sType       = .COPY_BUFFER_INFO_2,
		srcBuffer   = source,
		dstBuffer   = destination,
		regionCount = 1,
		pRegions    = &region,
	}
	vk.CmdCopyBuffer2(cmd, &copy_info)
}

@(private)
emit_image_copy :: proc(cmd: vk.CommandBuffer, source, destination: vk.Image, region: Image_Copy_Region) {
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
		srcImage       = source,
		srcImageLayout = .GENERAL,
		dstImage       = destination,
		dstImageLayout = .GENERAL,
		regionCount    = 1,
		pRegions       = &copy_region,
	}
	vk.CmdCopyImage2(cmd, &copy_info)
}

@(private)
emit_image_blit :: proc(cmd: vk.CommandBuffer, source, destination: vk.Image, region: Image_Copy_Region, filter: Filter, destination_layout := vk.ImageLayout.GENERAL) {
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
		srcImage       = source,
		srcImageLayout = .GENERAL,
		dstImage       = destination,
		dstImageLayout = destination_layout,
		regionCount    = 1,
		pRegions       = &blit_region,
		filter         = filter,
	}
	vk.CmdBlitImage2(cmd, &blit_info)
}

@(private)
emit_buffer_to_image :: proc(cmd: vk.CommandBuffer, source: vk.Buffer, destination: vk.Image, region: Buffer_Image_Region) {
	copy_region: vk.BufferImageCopy2 = {
		sType            = .BUFFER_IMAGE_COPY_2,
		bufferOffset     = region.offset,
		imageSubresource = region.image.subresource,
		imageOffset      = region.image.offset,
		imageExtent      = region.image.extent,
	}
	copy_info: vk.CopyBufferToImageInfo2 = {
		sType          = .COPY_BUFFER_TO_IMAGE_INFO_2,
		srcBuffer      = source,
		dstImage       = destination,
		dstImageLayout = .GENERAL,
		regionCount    = 1,
		pRegions       = &copy_region,
	}
	vk.CmdCopyBufferToImage2(cmd, &copy_info)
}

@(private)
emit_image_to_buffer :: proc(cmd: vk.CommandBuffer, source: vk.Image, destination: vk.Buffer, region: Buffer_Image_Region) {
	copy_region: vk.BufferImageCopy2 = {
		sType            = .BUFFER_IMAGE_COPY_2,
		bufferOffset     = region.offset,
		imageSubresource = region.image.subresource,
		imageOffset      = region.image.offset,
		imageExtent      = region.image.extent,
	}
	copy_info: vk.CopyImageToBufferInfo2 = {
		sType          = .COPY_IMAGE_TO_BUFFER_INFO_2,
		srcImage       = source,
		srcImageLayout = .GENERAL,
		dstBuffer      = destination,
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
region_bytes :: proc(format: Format, region: Resolved_Region) -> vk.DeviceSize {
	texel_size, known := format_texel_size(format)
	assert(known, "copying this format between buffers and images is not supported yet")
	extent := region.extent
	return vk.DeviceSize(texel_size) * vk.DeviceSize(extent.width) * vk.DeviceSize(extent.height) * vk.DeviceSize(extent.depth) * vk.DeviceSize(region.subresource.layerCount)
}

@(private)
format_has_features :: proc(format: Format, features: vk.FormatFeatureFlags) -> bool {
	properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(device.physical_device, format, &properties)
	return properties.optimalTilingFeatures >= features
}

@(private = "file")
record_copy :: proc(workload: ^Workload, source, destination: Access) {
	if source.key != destination.key {
		record_access(workload, source)
	}
	record_access(workload, destination)
}

@(private = "file")
assert_recording :: proc(workload: ^Workload, loc := #caller_location) {
	assert(workload.state == .Recording, "cannot record into a finalized workload; reset_workload to record again", loc)
}

@(private)
next_version :: proc(resource: $T) -> T {
	written := resource
	written.version += 1
	return written
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
record_access :: proc(workload: ^Workload, access: Access, flush := true) {
	if flush {
		flush_clears(workload)
	}
	state, handle := resource_state(workload, access)
	check_version(state, handle, access, 0, handle.read == workload.epoch)
	close_scope(workload)
	if has_hazard(workload, handle^, access) {
		emit_barrier(workload, {access})
	}
	commit_access(workload, state, handle, access, 0)
}

@(private = "file")
has_hazard :: proc(workload: ^Workload, handle: Handle_State, access: Access) -> bool {
	if workload.raw_written || handle.layout != .GENERAL || handle.written == workload.epoch {
		return true
	}
	return access.write && handle.read == workload.epoch
}

@(private = "file")
commit_access :: proc(workload: ^Workload, state: ^Resource_State, handle: ^Handle_State, access: Access, writer: u64) {
	if access.write {
		assert(!state.produced, "this resource was produced by this workload and is written again; produce its final version")
		state.version = access.version + 1
		state.writer = writer
		state.used = false
		handle.written = workload.epoch
	} else if access.read {
		handle.read = workload.epoch
		mark_used(workload, state, handle^, access.key)
	}
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
	memory_barrier := GLOBAL_BARRIER
	for state, index in transitions {
		barriers[index] = layout_barrier(state.image, state.aspect, state.layout, .GENERAL)
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
	barrier := GLOBAL_BARRIER
	vk.CmdPipelineBarrier2(cmd, &vk.DependencyInfo{sType = .DEPENDENCY_INFO, memoryBarrierCount = 1, pMemoryBarriers = &barrier})
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
	for image, index in recording.colour_attachments {
		colours[index] = rendering_attachment(image, folded_colours[index])
	}
	depth, has_depth := recording.depth_attachment.?
	depth_info: vk.RenderingAttachmentInfo
	if has_depth {
		depth_info = rendering_attachment(depth, folded_depth)
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
rendering_attachment :: proc(image: Image, folded_clear: Maybe(vk.ClearValue)) -> vk.RenderingAttachmentInfo {
	info: vk.RenderingAttachmentInfo = {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = render_view(image),
		imageLayout = .GENERAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}
	if value, folded := folded_clear.?; folded {
		info.loadOp = .CLEAR
		info.clearValue = value
	}
	return info
}

@(private = "file")
render_view :: proc(image: Image) -> vk.ImageView {
	return image.attachment_view if image.attachment_view != 0 else image.view
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
		equations: [MAX_COLOUR_ATTACHMENTS]Blend_Equation
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
BLEND_REPLACE :: Blend_Equation {
	srcColorBlendFactor = .ONE,
	dstColorBlendFactor = .ZERO,
	colorBlendOp        = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ZERO,
	alphaBlendOp        = .ADD,
}

@(private = "file")
emit_stencil :: proc(cmd: vk.CommandBuffer, faces: Stencil_Faces, stencil: Stencil_State) {
	vk.CmdSetStencilOp(cmd, faces, stencil.fail_op, stencil.pass_op, stencil.depth_fail_op, stencil.compare_op)
	vk.CmdSetStencilReference(cmd, faces, stencil.reference)
	vk.CmdSetStencilCompareMask(cmd, faces, stencil.compare_mask)
	vk.CmdSetStencilWriteMask(cmd, faces, stencil.write_mask)
}

@(private = "file")
@(require_results)
write_table :: proc(workload: ^Workload, recording: Shader_Recording) -> (address: vk.DeviceAddress, err: Error) {
	count := table_size(recording)
	size := round_up(vk.DeviceSize(size_of(u32) * (TABLE_HEADER_WORDS + count)), 16)
	if vk.DeviceSize(workload.table_used) + size > TABLE_CHUNK_SIZE {
		workload.table_chunk += 1
		workload.table_used = 0
	}
	if workload.table_chunk == len(workload.tables) {
		chunk := make_buffer(TABLE_CHUNK_SIZE, {}, .Host_Visible) or_return
		append(&workload.tables, chunk)
	}
	chunk := workload.tables[workload.table_chunk]
	words := ([^]u32)(&chunk.mapped[workload.table_used])
	words[0] = u32(count)
	words[1] = null_buffer_index()
	words[2] = null_image_index() | HEAP_IMAGE_TAG
	words[3] = null_sampler_index() | HEAP_SAMPLER_TAG
	words[4] = null_uniform_index() | HEAP_UNIFORM_TAG
	index := 0
	for binding in recording.bindings {
		if !binding.table {
			continue
		}
		defer index += 1
		entry: u32
		switch resource in binding.resource {
		case Image:
			entry = resource.heap_index | HEAP_IMAGE_TAG
		case Buffer:
			entry = resource.heap_index | HEAP_UNIFORM_TAG if .UNIFORM_BUFFER in resource.usage else resource.heap_index
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
	buffer = make_buffer(size, {}, .Host_Readback) or_return
	append(&workload.readbacks, buffer)
	return
}

@(private = "file")
@(require_results)
take_slot :: proc(workload: ^Workload) -> (slot: ^Execution_Slot, err: Error) {
	slot = &workload.slots[workload.next_slot]
	for len(slot.acquire_semaphores) < len(workload.presentations) {
		append(&slot.acquire_semaphores, make_semaphore(false, "acquire") or_return)
		append(&slot.present_commands, allocate_command_buffer(workload.command_pool, "present") or_return)
	}
	wait_value(slot.value) or_return
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
	for slot in workload.slots {
		_ = wait_value(slot.value)
	}
}

@(private = "file")
@(require_results)
begin_recording :: proc(workload: ^Workload) -> Error {
	clear(&workload.presentations)
	if workload.command_buffer == nil {
		workload.command_buffer = allocate_command_buffer(workload.command_pool, workload.name) or_return
	} else if res := vk.ResetCommandBuffer(workload.command_buffer, {}); res != .SUCCESS {
		log.errorf("Failed to reset the workload command buffer: %v", res)
		return .Recording_Failed
	}
	begin_commands(workload.command_buffer, {.SIMULTANEOUS_USE}) or_return
	bind_descriptor_heaps(workload.command_buffer)
	begin_label(workload.command_buffer, workload.name)
	global_barrier(workload.command_buffer)
	workload.emitted = {}
	workload.state = .Recording
	clear(&workload.resources)
	clear(&workload.consumed)
	clear(&workload.clears)
	clear(&workload.handles)
	workload.scope = {}
	workload.raw_written = false
	workload.epoch = 1
	workload.table_chunk = 0
	workload.table_used = 0
	for &buffer in workload.readbacks {
		delete_buffer(&buffer)
	}
	clear(&workload.readbacks)
	return nil
}
