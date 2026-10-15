package Valhalla

import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"

Buffer_Error :: enum {
	None,
	Invalid_Buffer_Size,
	Buffer_Creation_Failed,
	Buffer_Bind_Failed,
	Buffer_Out_Of_Range,
	Buffer_File_Read_Failed,
}

Buffer_Usage :: enum {
	Storage,
	Index,
	Uniform,
	Indirect,
}

Buffer_Usages :: bit_set[Buffer_Usage]

Buffer_Memory :: enum {
	Device_Local,
	Host_Visible,
	Host_Readback,
}

Buffer_Settings :: struct {
	usage:  Buffer_Usages,
	memory: Buffer_Memory,
	name:   string,
}

Buffer :: struct {
	handle:  vk.Buffer,
	size:    vk.DeviceSize,
	usage:   vk.BufferUsageFlags,
	address: vk.DeviceAddress,
	mapped:     [^]byte,
	heap_index: u32,
	version:    u32,
	producer:   u64,
	variant:    union {
		Owned_Buffer,
		External_Buffer,
	},
}

Owned_Buffer :: struct {
	allocation: Allocation,
	memory:     Buffer_Memory,
	name:       string,
}

External_Buffer :: struct {}

@(private = "file")
BUFFER_USAGE_FLAGS := [Buffer_Usage]vk.BufferUsageFlags {
	.Storage  = {.STORAGE_BUFFER},
	.Index    = {.INDEX_BUFFER},
	.Uniform  = {.UNIFORM_BUFFER},
	.Indirect = {.INDIRECT_BUFFER},
}

@(private = "file")
BUFFER_MEMORY_PROPERTIES := [Buffer_Memory]vk.MemoryPropertyFlags {
	.Device_Local  = {.DEVICE_LOCAL},
	.Host_Visible  = {.HOST_VISIBLE, .HOST_COHERENT},
	.Host_Readback = {.HOST_VISIBLE, .HOST_COHERENT, .HOST_CACHED},
}

@(require_results)
make_empty_buffer :: proc(#any_int size: int, settings: Buffer_Settings) -> (buffer: Buffer, err: Error) {
	assert(initialised, "Valhalla.init must be called before make_buffer")
	if size <= 0 {
		log.errorf("A buffer needs a positive size, got %v", size)
		return {}, .Invalid_Buffer_Size
	}

	buffer.size = vk.DeviceSize(size)
	buffer.usage = {.TRANSFER_SRC, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS}
	for usage in settings.usage {
		buffer.usage += BUFFER_USAGE_FLAGS[usage]
	}
	buffer_info: vk.BufferCreateInfo = {
		sType       = .BUFFER_CREATE_INFO,
		size        = buffer.size,
		usage       = buffer.usage,
		sharingMode = .EXCLUSIVE,
	}
	if res := vk.CreateBuffer(device.handle, &buffer_info, nil, &buffer.handle); res != .SUCCESS {
		log.errorf("Failed to create buffer: %v", res)
		return {}, .Buffer_Creation_Failed
	}
	name_object(.BUFFER, u64(buffer.handle), settings.name)
	buffer.variant = Owned_Buffer {
		memory = settings.memory,
		name   = strings.clone(settings.name) if settings.name != "" else "",
	}
	defer if err != nil {
		delete_buffer(&buffer)
	}
	owned := &buffer.variant.(Owned_Buffer)
	owned.allocation = allocate_memory(buffer.handle, BUFFER_MEMORY_PROPERTIES[settings.memory]) or_return
	if res := vk.BindBufferMemory(device.handle, buffer.handle, owned.allocation.memory, owned.allocation.offset); res != .SUCCESS {
		log.errorf("Failed to bind buffer memory: %v", res)
		return buffer, .Buffer_Bind_Failed
	}
	buffer.mapped = owned.allocation.mapped
	buffer.address = buffer_address(buffer.handle)
	acquire_buffer_slot(&buffer) or_return
	return
}

@(require_results)
make_buffer_from_file :: proc(filename: string, settings: Buffer_Settings) -> (buffer: Buffer, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	data, read_err := os.read_entire_file(filename, context.temp_allocator)
	if read_err != nil {
		log.errorf("Failed to read %v: %v", filename, read_err)
		return {}, .Buffer_File_Read_Failed
	}
	return make_buffer_from_memory(data, settings)
}

@(require_results)
make_buffer_from_memory :: proc(memory: []u8, settings: Buffer_Settings) -> (buffer: Buffer, err: Error) {
	buffer = make_empty_buffer(len(memory), settings) or_return
	if err = load_memory_to_buffer(memory, &buffer); err != nil {
		delete_buffer(&buffer)
		return {}, err
	}
	return
}

@(require_results)
make_buffer_from_image :: proc(source: ^Image, settings: Buffer_Settings, source_region := Image_Region{}) -> (buffer: Buffer, err: Error) {
	buffer = make_empty_buffer(image_region_bytes(source^, source_region), settings) or_return
	if err = load_image_to_buffer(source, &buffer, source_region); err != nil {
		delete_buffer(&buffer)
		return {}, err
	}
	return
}

@(require_results)
make_buffer_from_buffer :: proc(source: ^Buffer, settings: Buffer_Settings) -> (buffer: Buffer, err: Error) {
	buffer = make_empty_buffer(source.size, settings) or_return
	if err = load_buffer_to_buffer(source, &buffer); err != nil {
		delete_buffer(&buffer)
		return {}, err
	}
	return
}

make_buffer :: proc {
	make_empty_buffer,
	make_buffer_from_file,
	make_buffer_from_memory,
	make_buffer_from_image,
	make_buffer_from_buffer,
}

@(require_results)
load_memory_to_buffer :: proc(source: []u8, buffer: ^Buffer, #any_int offset: int = 0) -> Error {
	if offset < 0 || vk.DeviceSize(offset + len(source)) > buffer.size {
		log.errorf("Writing %v bytes at offset %v overruns a %v byte buffer", len(source), offset, buffer.size)
		return .Buffer_Out_Of_Range
	}
	if len(source) == 0 {
		return nil
	}
	if buffer.mapped != nil {
		copy(buffer.mapped[offset:][:len(source)], source)
		return nil
	}
	return upload_to_buffer(buffer.handle, vk.DeviceSize(offset), source)
}

@(require_results)
load_image_to_buffer :: proc(source: ^Image, buffer: ^Buffer, source_region := Image_Region{}, #any_int offset: int = 0) -> Error {
	assert(source.layout == .GENERAL, "immediate copies need an image in GENERAL, as every image Valhalla makes is")
	region := buffer_image_region(buffer^, source^, offset, source_region, to_image = false)
	cmd := staging_commands() or_return
	emit_image_to_buffer(cmd, source.handle, buffer.handle, region)
	return nil
}

@(require_results)
load_buffer_to_buffer :: proc(
	source, buffer: ^Buffer,
	#any_int source_offset: int = 0,
	#any_int offset: int = 0,
	#any_int size: int = 0,
) -> Error {
	region := buffer_copy_region(source^, buffer^, source_offset, offset, size)
	cmd := staging_commands() or_return
	emit_buffer_copy(cmd, source.handle, buffer.handle, region)
	return nil
}

load_to_buffer :: proc {
	load_memory_to_buffer,
	load_image_to_buffer,
	load_buffer_to_buffer,
}

@(require_results)
write_buffer_to_file :: proc(source: ^Buffer, filename: string) -> Error {
	workload := make_workload() or_return
	defer delete_workload(&workload)
	shot := readback_buffer(&workload, source^) or_return
	run_workload(&workload) or_return
	return write_readback_to_file(shot, filename, encoded = false)
}

write_buffer_to_image :: load_buffer_to_image

write_buffer_to_buffer :: load_buffer_to_buffer

@(require_results)
write_buffer_to_surface :: proc(source: ^Buffer, surface: ^Surface, #any_int source_offset: int = 0) -> Error {
	workload := make_workload() or_return
	defer delete_workload(&workload)
	image := acquire(&workload, surface) or_return
	shown := copy_buffer_to_image(&workload, source^, image, source_offset)
	present(&workload, shown)
	return run_workload(&workload)
}

write_buffer :: proc {
	write_buffer_to_file,
	write_buffer_to_image,
	write_buffer_to_buffer,
	write_buffer_to_surface,
}

delete_buffer :: proc(buffer: ^Buffer) {
	if owned, is_owned := &buffer.variant.(Owned_Buffer); is_owned {
		settle_staging()
		release_buffer_slot(buffer)
		if buffer.handle != 0 {
			vk.DestroyBuffer(device.handle, buffer.handle, nil)
		}
		free_memory(&owned.allocation)
		delete(owned.name)
	}
	buffer^ = {}
}
