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
	Acceleration_Input,
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
	handle:     vk.Buffer,
	size:       vk.DeviceSize,
	usage:      vk.BufferUsageFlags,
	address:    vk.DeviceAddress,
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
	.Storage            = {.STORAGE_BUFFER},
	.Index              = {.INDEX_BUFFER},
	.Uniform            = {.UNIFORM_BUFFER},
	.Indirect           = {.INDIRECT_BUFFER},
	.Acceleration_Input = {.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
}

@(private = "file")
BUFFER_MEMORY_PROPERTIES := [Buffer_Memory]vk.MemoryPropertyFlags {
	.Device_Local  = {.DEVICE_LOCAL},
	.Host_Visible  = {.HOST_VISIBLE, .HOST_COHERENT},
	.Host_Readback = {.HOST_VISIBLE, .HOST_COHERENT, .HOST_CACHED},
}

@(require_results)
make_empty_buffer :: proc(
	#any_int size: int,
	settings: Buffer_Settings,
) -> (
	buffer: Buffer,
	err: Error,
) {
	return make_owned_buffer(size, settings, {})
}

@(private = "file")
@(require_results)
make_owned_buffer :: proc(
	#any_int size: int,
	settings: Buffer_Settings,
	extra_usage: vk.BufferUsageFlags,
) -> (
	buffer: Buffer,
	err: Error,
) {
	assert(initialised, "Valhalla.init must be called before make_buffer")
	assert(
		.Acceleration_Input not_in settings.usage || device.optional.ray_query,
		"acceleration structure inputs need a device with ray queries (device.optional.ray_query)",
	)
	if size <= 0 {
		log.errorf("A buffer needs a positive size, got %v", size)
		return {}, .Invalid_Buffer_Size
	}

	buffer.size = vk.DeviceSize(size)
	buffer.usage = {.TRANSFER_SRC, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS} + extra_usage
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
	owned.allocation = allocate_memory(
		buffer.handle,
		BUFFER_MEMORY_PROPERTIES[settings.memory],
	) or_return
	if res := vk.BindBufferMemory(
		device.handle,
		buffer.handle,
		owned.allocation.memory,
		owned.allocation.offset,
	); res != .SUCCESS {
		log.errorf("Failed to bind buffer memory: %v", res)
		return buffer, .Buffer_Bind_Failed
	}
	buffer.mapped = owned.allocation.mapped
	buffer.address = buffer_address(buffer.handle)
	acquire_buffer_slot(&buffer) or_return
	return
}

@(require_results)
make_buffer_from_file :: proc(
	filename: string,
	settings: Buffer_Settings,
) -> (
	buffer: Buffer,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	data, read_err := os.read_entire_file(filename, context.temp_allocator)
	if read_err != nil {
		log.errorf("Failed to read %v: %v", filename, read_err)
		return {}, .Buffer_File_Read_Failed
	}
	return make_buffer_from_memory(data, settings)
}

@(require_results)
make_buffer_from_memory :: proc(
	memory: []u8,
	settings: Buffer_Settings,
) -> (
	buffer: Buffer,
	err: Error,
) {
	buffer = make_empty_buffer(len(memory), settings) or_return
	if err = load_memory_to_buffer(memory, &buffer); err != nil {
		delete_buffer(&buffer)
		return {}, err
	}
	return
}

@(require_results)
make_buffer_from_image :: proc(
	source: ^Image,
	settings: Buffer_Settings,
	source_region := Image_Region{},
) -> (
	buffer: Buffer,
	err: Error,
) {
	buffer = make_empty_buffer(image_region_bytes(source^, source_region), settings) or_return
	if err = load_image_to_buffer(source, &buffer, source_region); err != nil {
		delete_buffer(&buffer)
		return {}, err
	}
	return
}

@(require_results)
make_buffer_from_buffer :: proc(
	source: ^Buffer,
	settings: Buffer_Settings,
) -> (
	buffer: Buffer,
	err: Error,
) {
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
		log.errorf(
			"Writing %v bytes at offset %v overruns a %v byte buffer",
			len(source),
			offset,
			buffer.size,
		)
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
load_image_to_buffer :: proc(
	source: ^Image,
	buffer: ^Buffer,
	source_region := Image_Region{},
	#any_int offset: int = 0,
) -> Error {
	assert(
		source.layout == .GENERAL,
		"immediate copies need an image in GENERAL, as every image Valhalla makes is",
	)
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
write_buffer_to_surface :: proc(
	source: ^Buffer,
	surface: ^Surface,
	#any_int source_offset: int = 0,
) -> Error {
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

// ===[ Acceleration Structures ]===============================================

Acceleration_Structure :: struct {
	handle:  vk.AccelerationStructureKHR,
	address: vk.DeviceAddress,
	storage: Buffer,
}

Triangle_Geometry :: struct {
	vertices:       Buffer,
	vertex_offset:  int,
	vertex_stride:  int,
	vertex_count:   int,
	indices:        Buffer,
	index_offset:   int,
	triangle_count: int,
}

Acceleration_Instance :: struct {
	structure:    Acceleration_Structure,
	transform:    matrix[4, 4]f32,
	custom_index: u32,
	mask:         u8,
}

@(require_results)
make_bottom_level :: proc(
	geometries: []Triangle_Geometry,
	name := "",
) -> (
	structure: Acceleration_Structure,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(
		device.optional.ray_query,
		"acceleration structures need a device with ray queries (device.optional.ray_query)",
	)
	assert(len(geometries) > 0, "a bottom level acceleration structure needs geometry")
	described := make(
		[]vk.AccelerationStructureGeometryKHR,
		len(geometries),
		context.temp_allocator,
	)
	ranges := make(
		[]vk.AccelerationStructureBuildRangeInfoKHR,
		len(geometries),
		context.temp_allocator,
	)
	counts := make([]u32, len(geometries), context.temp_allocator)
	for geometry, index in geometries {
		assert(
			.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR in geometry.vertices.usage &&
			.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR in geometry.indices.usage,
			"triangle geometry needs vertex and index buffers made with .Acceleration_Input usage",
		)
		described[index] = {
			sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
			geometryType = .TRIANGLES,
			flags = {.OPAQUE},
			geometry = {
				triangles = {
					sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
					vertexFormat = .R32G32B32_SFLOAT,
					vertexData = {
						deviceAddress = geometry.vertices.address +
						vk.DeviceAddress(geometry.vertex_offset),
					},
					vertexStride = vk.DeviceSize(geometry.vertex_stride),
					maxVertex = u32(max(geometry.vertex_count - 1, 0)),
					indexType = .UINT32,
					indexData = {
						deviceAddress = geometry.indices.address +
						vk.DeviceAddress(geometry.index_offset),
					},
				},
			},
		}
		ranges[index] = {
			primitiveCount = u32(geometry.triangle_count),
		}
		counts[index] = u32(geometry.triangle_count)
	}
	return build_acceleration_structure(.BOTTOM_LEVEL, described, ranges, counts, name)
}

@(require_results)
make_top_level :: proc(
	instances: []Acceleration_Instance,
	name := "",
) -> (
	structure: Acceleration_Structure,
	err: Error,
) {
	assert(
		device.optional.ray_query,
		"acceleration structures need a device with ray queries (device.optional.ray_query)",
	)
	assert(len(instances) > 0, "a top level acceleration structure needs instances")
	instance_buffer := make_owned_buffer(
		len(instances) * size_of(vk.AccelerationStructureInstanceKHR),
		{memory = .Host_Visible},
		{.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	) or_return
	defer delete_buffer(&instance_buffer)
	written := ([^]vk.AccelerationStructureInstanceKHR)(instance_buffer.mapped)
	for instance, index in instances {
		assert(
			instance.structure.handle != 0,
			"an instance needs a bottom level acceleration structure",
		)
		transform: vk.TransformMatrixKHR
		for row in 0 ..< 3 {
			for column in 0 ..< 4 {
				transform.mat[row][column] = instance.transform[row, column]
			}
		}
		written[index] = {
			transform                      = transform,
			instanceCustomIndex            = instance.custom_index,
			mask                           = u32(instance.mask) if instance.mask != 0 else 0xff,
			accelerationStructureReference = u64(instance.structure.address),
		}
	}
	described := []vk.AccelerationStructureGeometryKHR {
		{
			sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
			geometryType = .INSTANCES,
			geometry = {
				instances = {
					sType = .ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
					data = {deviceAddress = instance_buffer.address},
				},
			},
		},
	}
	ranges := []vk.AccelerationStructureBuildRangeInfoKHR{{primitiveCount = u32(len(instances))}}
	counts := []u32{u32(len(instances))}
	return build_acceleration_structure(.TOP_LEVEL, described, ranges, counts, name)
}

delete_acceleration_structure :: proc(structure: ^Acceleration_Structure) {
	if structure.handle != 0 {
		settle_staging()
		vk.DestroyAccelerationStructureKHR(device.handle, structure.handle, nil)
	}
	delete_buffer(&structure.storage)
	structure^ = {}
}

@(private = "file")
@(require_results)
build_acceleration_structure :: proc(
	type: vk.AccelerationStructureTypeKHR,
	geometries: []vk.AccelerationStructureGeometryKHR,
	ranges: []vk.AccelerationStructureBuildRangeInfoKHR,
	counts: []u32,
	name: string,
) -> (
	structure: Acceleration_Structure,
	err: Error,
) {
	build_info: vk.AccelerationStructureBuildGeometryInfoKHR = {
		sType         = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type          = type,
		flags         = {.PREFER_FAST_TRACE},
		mode          = .BUILD,
		geometryCount = u32(len(geometries)),
		pGeometries   = raw_data(geometries),
	}
	sizes: vk.AccelerationStructureBuildSizesInfoKHR = {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}
	vk.GetAccelerationStructureBuildSizesKHR(
		device.handle,
		.DEVICE,
		&build_info,
		raw_data(counts),
		&sizes,
	)

	defer if err != nil {
		delete_acceleration_structure(&structure)
	}
	structure.storage = make_owned_buffer(
		sizes.accelerationStructureSize,
		{name = name},
		{.ACCELERATION_STRUCTURE_STORAGE_KHR},
	) or_return
	create_info: vk.AccelerationStructureCreateInfoKHR = {
		sType  = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		buffer = structure.storage.handle,
		size   = sizes.accelerationStructureSize,
		type   = type,
	}
	if res := vk.CreateAccelerationStructureKHR(
		device.handle,
		&create_info,
		nil,
		&structure.handle,
	); res != .SUCCESS {
		log.errorf("Failed to create an acceleration structure: %v", res)
		return structure, .Buffer_Creation_Failed
	}
	name_object(.ACCELERATION_STRUCTURE_KHR, u64(structure.handle), name)
	address_info: vk.AccelerationStructureDeviceAddressInfoKHR = {
		sType                 = .ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
		accelerationStructure = structure.handle,
	}
	structure.address = vk.GetAccelerationStructureDeviceAddressKHR(device.handle, &address_info)

	properties: vk.PhysicalDeviceAccelerationStructurePropertiesKHR = {
		sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_PROPERTIES_KHR,
	}
	query: vk.PhysicalDeviceProperties2 = {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &properties,
	}
	vk.GetPhysicalDeviceProperties2(device.physical_device, &query)
	alignment := vk.DeviceSize(max(properties.minAccelerationStructureScratchOffsetAlignment, 1))
	scratch := make_owned_buffer(
		sizes.buildScratchSize + alignment,
		{},
		{.STORAGE_BUFFER},
	) or_return
	defer delete_buffer(&scratch)
	build_info.dstAccelerationStructure = structure.handle
	build_info.scratchData = {
		deviceAddress = vk.DeviceAddress(round_up(vk.DeviceSize(scratch.address), alignment)),
	}

	cmd := staging_commands() or_return
	memory_barrier(
		cmd,
		{.ALL_TRANSFER, .ACCELERATION_STRUCTURE_BUILD_KHR},
		{.TRANSFER_WRITE, .ACCELERATION_STRUCTURE_WRITE_KHR},
		{.ACCELERATION_STRUCTURE_BUILD_KHR},
		{.MEMORY_READ, .ACCELERATION_STRUCTURE_READ_KHR},
	)
	range_pointer := raw_data(ranges)
	vk.CmdBuildAccelerationStructuresKHR(cmd, 1, &build_info, &range_pointer)
	memory_barrier(
		cmd,
		{.ACCELERATION_STRUCTURE_BUILD_KHR},
		{.ACCELERATION_STRUCTURE_WRITE_KHR},
		{.ALL_COMMANDS},
		{.MEMORY_READ, .ACCELERATION_STRUCTURE_READ_KHR},
	)
	settle_staging()
	return
}
