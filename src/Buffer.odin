package Valhalla

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:mem"
import "core:strings"

import vk "vendor:vulkan"

Buffer_Error :: enum {
	None,
	Invalid_Buffer_Size,
	Buffer_Creation_Failed,
	Buffer_Bind_Failed,
	Buffer_Out_Of_Range,
	Buffer_Not_Mapped,
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

@(private)
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
	allocation:  Allocation,
	name:        string,
	usage:       Buffer_Usages,
	memory:      Buffer_Memory,
	extra_usage: vk.BufferUsageFlags,
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
make_buffer :: proc(
	#any_int size: int,
	usage: Buffer_Usages,
	memory := Buffer_Memory.Device_Local,
	name := "",
) -> (
	buffer: Buffer,
	err: Error,
) {
	return make_owned_buffer(size, {usage, memory, name}, {})
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
	assert(
		settings.usage & {.Storage, .Uniform} != {.Storage, .Uniform},
		"a buffer reaches shaders as either a StructuredBuffer (.Storage) or a ConstantBuffer (.Uniform), not both",
	)
	if size <= 0 {
		log.errorf("A buffer needs a positive size, got %v", size)
		return {}, .Invalid_Buffer_Size
	}
	if .Uniform in settings.usage && size > int(device.properties.limits.maxUniformBufferRange) {
		log.errorf(
			"A uniform buffer can hold at most %v bytes, got %v",
			device.properties.limits.maxUniformBufferRange,
			size,
		)
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
		name        = strings.clone(settings.name) if settings.name != "" else "",
		usage       = settings.usage,
		memory      = settings.memory,
		extra_usage = extra_usage,
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
make_buffer_from :: proc(
	source: $T,
	usage: Buffer_Usages,
	memory := Buffer_Memory.Device_Local,
	name := "",
) -> (
	buffer: Buffer,
	err: Error,
) {
	buffer = make_buffer(source_size(source), usage, memory, name) or_return
	if err = load_to_buffer(source, buffer); err != nil {
		delete_buffer(&buffer)
		return {}, err
	}
	return
}

@(require_results)
resize_buffer :: proc(buffer: ^Buffer, #any_int size: int) -> (resized: bool, err: Error) {
	owned, is_owned := buffer.variant.(Owned_Buffer)
	assert(is_owned && buffer.handle != 0, "resize_buffer needs a buffer made by make_buffer")
	if vk.DeviceSize(size) == buffer.size {
		return false, nil
	}
	replacement := make_owned_buffer(size, {owned.usage, owned.memory, owned.name}, owned.extra_usage) or_return
	if err = load_buffer_to_buffer(buffer^, replacement, size = min(size, int(buffer.size))); err != nil {
		delete_buffer(&replacement)
		return false, err
	}
	delete_buffer(buffer)
	buffer^ = replacement
	return true, nil
}

@(require_results)
load_to_buffer :: proc(source: $T, buffer: Buffer, #any_int offset: int = 0) -> Error {
	when T == Image {
		return load_image_to_buffer(source, buffer, offset = offset)
	} else when T == Buffer {
		return load_buffer_to_buffer(source, buffer, offset = offset)
	} else {
		source := source
		data, size := source_span(&source)
		return load_ptr_to_buffer(data, size, buffer, offset)
	}
}

@(require_results)
load_ptr_to_buffer :: proc(
	source: rawptr,
	size: int,
	buffer: Buffer,
	#any_int offset: int = 0,
) -> Error {
	if offset < 0 || vk.DeviceSize(offset + size) > buffer.size {
		log.errorf(
			"Writing %v bytes at offset %v overruns a %v byte buffer",
			size,
			offset,
			buffer.size,
		)
		return .Buffer_Out_Of_Range
	}
	if size == 0 {
		return nil
	}
	if buffer.mapped != nil {
		mem.copy(&buffer.mapped[offset], source, size)
		return nil
	}
	return upload_to_buffer(buffer.handle, vk.DeviceSize(offset), source, size)
}

@(require_results)
load_from_buffer :: proc(buffer: Buffer, destination: $T, #any_int offset: int = 0) -> Error {
	data, size := destination_span(destination)
	return load_buffer_to_ptr(buffer, data, size, offset)
}

@(require_results)
load_buffer_to_ptr :: proc(
	buffer: Buffer,
	destination: rawptr,
	size: int,
	#any_int offset: int = 0,
) -> Error {
	if offset < 0 || size < 0 || vk.DeviceSize(offset + size) > buffer.size {
		log.errorf(
			"Reading %v bytes at offset %v overruns a %v byte buffer",
			size,
			offset,
			buffer.size,
		)
		return .Buffer_Out_Of_Range
	}
	if buffer.mapped == nil {
		log.error("Only a Host_Visible buffer can be read directly; read a Device_Local buffer with readback")
		return .Buffer_Not_Mapped
	}
	if size == 0 {
		return nil
	}
	mem.copy(destination, &buffer.mapped[offset], size)
	return nil
}

@(require_results)
load_image_to_buffer :: proc(
	source: Image,
	buffer: Buffer,
	source_region := Image_Region{},
	#any_int offset: int = 0,
) -> Error {
	assert_general(source)
	region := buffer_image_region(buffer, source, offset, source_region, to_image = false)
	cmd := staging_commands() or_return
	emit_image_to_buffer(cmd, source.handle, buffer.handle, region)
	return nil
}

@(require_results)
load_buffer_to_buffer :: proc(
	source, buffer: Buffer,
	#any_int source_offset: int = 0,
	#any_int offset: int = 0,
	#any_int size: int = 0,
) -> Error {
	region := buffer_copy_region(source, buffer, source_offset, offset, size)
	cmd := staging_commands() or_return
	emit_buffer_copy(cmd, source.handle, buffer.handle, region)
	return nil
}

@(private)
source_size :: proc(source: $T) -> int {
	when T == Image {
		return image_region_bytes(source, {})
	} else when T == Buffer {
		return int(source.size)
	} else {
		source := source
		_, size := source_span(&source)
		return size
	}
}

@(private)
source_span :: proc(source: ^$T) -> (data: rawptr, size: int) {
	#assert(!intrinsics.type_is_pointer(T), "a source is passed by value, not by pointer")
	#assert(!intrinsics.type_is_multi_pointer(T), "a multi-pointer does not say how many elements it covers")
	#assert(!intrinsics.type_is_map(T), "a map cannot be a source")
	#assert(!intrinsics.type_is_proc(T), "a procedure cannot be a source")
	#assert(!intrinsics.type_is_any(T), "an any cannot be a source")
	#assert(!intrinsics.type_is_typeid(T), "a typeid cannot be a source")
	when intrinsics.type_is_cstring(T) {
		return rawptr(source^), len(source^)
	} else when intrinsics.type_is_cstring16(T) {
		return rawptr(source^), len(source^) * size_of(u16)
	} else when intrinsics.type_is_slice(T) || intrinsics.type_is_dynamic_array(T) || intrinsics.type_is_string(T) {
		return raw_data(source^), len(source^) * size_of(raw_data(source^)[0])
	} else when intrinsics.type_is_fixed_capacity_dynamic_array(T) {
		return raw_data(source^[:]), len(source^) * size_of(source^[0])
	} else {
		return source, size_of(T)
	}
}

@(private)
destination_span :: proc(destination: $T) -> (data: rawptr, size: int) {
	when intrinsics.type_is_slice(T) {
		return raw_data(destination), len(destination) * size_of(raw_data(destination)[0])
	} else when intrinsics.type_is_pointer(T) && T != rawptr {
		E :: intrinsics.type_elem_type(T)
		#assert(
			!intrinsics.type_is_slice(E) &&
			!intrinsics.type_is_dynamic_array(E) &&
			!intrinsics.type_is_fixed_capacity_dynamic_array(E) &&
			!intrinsics.type_is_string(E),
			"a pointer to a slice, dynamic array or string would overwrite its header; pass the slice itself",
		)
		#assert(
			!intrinsics.type_is_pointer(E) &&
			!intrinsics.type_is_multi_pointer(E) &&
			!intrinsics.type_is_map(E) &&
			!intrinsics.type_is_proc(E) &&
			!intrinsics.type_is_any(E) &&
			!intrinsics.type_is_typeid(E),
			"a copy destination must point at plain data",
		)
		return destination, size_of(E)
	} else {
		#assert(false, "a copy destination is a pointer to a value or a slice")
		return nil, 0
	}
}

delete_buffer :: proc(buffer: ^Buffer) {
	if _, is_owned := buffer.variant.(Owned_Buffer); is_owned {
		bury(buffer^)
	}
	buffer^ = {}
}

@(private)
destroy_buffer :: proc(buffer: ^Buffer) {
	owned, is_owned := &buffer.variant.(Owned_Buffer)
	if !is_owned {
		return
	}
	release_buffer_slot(buffer)
	if buffer.handle != 0 {
		vk.DestroyBuffer(device.handle, buffer.handle, nil)
	}
	free_memory(&owned.allocation)
	delete(owned.name)
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
	}
	return make_acceleration_structure(.BOTTOM_LEVEL, described, ranges, name)
}

@(require_results)
make_top_level :: proc(
	instances: []Acceleration_Instance,
	name := "",
) -> (
	structure: Acceleration_Structure,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	instance_buffer, described, ranges := describe_instances(instances) or_return
	defer delete_buffer(&instance_buffer)
	return make_acceleration_structure(.TOP_LEVEL, described, ranges, name)
}

@(require_results)
update_top_level :: proc(
	structure: Acceleration_Structure,
	instances: []Acceleration_Instance,
) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(structure.handle != 0, "update_top_level needs a structure made by make_top_level")
	instance_buffer, described, ranges := describe_instances(instances) or_return
	defer delete_buffer(&instance_buffer)
	build_info, sizes := acceleration_build_sizes(.TOP_LEVEL, described, ranges)
	assert(
		sizes.accelerationStructureSize <= structure.storage.size,
		"update_top_level cannot grow a structure; make a new one with make_top_level",
	)
	return build_acceleration_structure(structure, &build_info, ranges, sizes)
}

delete_acceleration_structure :: proc(structure: ^Acceleration_Structure) {
	if structure.handle != 0 {
		bury(structure^)
	} else {
		delete_buffer(&structure.storage)
	}
	structure^ = {}
}

@(private = "file")
@(require_results)
describe_instances :: proc(
	instances: []Acceleration_Instance,
) -> (
	buffer: Buffer,
	geometries: []vk.AccelerationStructureGeometryKHR,
	ranges: []vk.AccelerationStructureBuildRangeInfoKHR,
	err: Error,
) {
	assert(len(instances) > 0, "a top level acceleration structure needs instances")
	buffer = make_owned_buffer(
		len(instances) * size_of(vk.AccelerationStructureInstanceKHR),
		{memory = .Host_Visible},
		{.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	) or_return
	written := ([^]vk.AccelerationStructureInstanceKHR)(buffer.mapped)
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
	geometries = make([]vk.AccelerationStructureGeometryKHR, 1, context.temp_allocator)
	geometries[0] = {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .INSTANCES,
		geometry = {
			instances = {
				sType = .ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
				data = {deviceAddress = buffer.address},
			},
		},
	}
	ranges = make([]vk.AccelerationStructureBuildRangeInfoKHR, 1, context.temp_allocator)
	ranges[0] = {
		primitiveCount = u32(len(instances)),
	}
	return
}

@(private = "file")
acceleration_build_sizes :: proc(
	type: vk.AccelerationStructureTypeKHR,
	geometries: []vk.AccelerationStructureGeometryKHR,
	ranges: []vk.AccelerationStructureBuildRangeInfoKHR,
) -> (
	build_info: vk.AccelerationStructureBuildGeometryInfoKHR,
	sizes: vk.AccelerationStructureBuildSizesInfoKHR,
) {
	build_info = {
		sType         = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type          = type,
		flags         = {.PREFER_FAST_TRACE},
		mode          = .BUILD,
		geometryCount = u32(len(geometries)),
		pGeometries   = raw_data(geometries),
	}
	counts := make([]u32, len(ranges), context.temp_allocator)
	for range, index in ranges {
		counts[index] = range.primitiveCount
	}
	sizes = {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}
	vk.GetAccelerationStructureBuildSizesKHR(
		device.handle,
		.DEVICE,
		&build_info,
		raw_data(counts),
		&sizes,
	)
	return
}

@(private = "file")
@(require_results)
make_acceleration_structure :: proc(
	type: vk.AccelerationStructureTypeKHR,
	geometries: []vk.AccelerationStructureGeometryKHR,
	ranges: []vk.AccelerationStructureBuildRangeInfoKHR,
	name: string,
) -> (
	structure: Acceleration_Structure,
	err: Error,
) {
	assert(
		device.optional.ray_query,
		"acceleration structures need a device with ray queries (device.optional.ray_query)",
	)
	build_info, sizes := acceleration_build_sizes(type, geometries, ranges)
	structure.storage = make_owned_buffer(
		sizes.accelerationStructureSize,
		{name = name},
		{.ACCELERATION_STRUCTURE_STORAGE_KHR},
	) or_return
	defer if err != nil {
		delete_acceleration_structure(&structure)
	}
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
	err = build_acceleration_structure(structure, &build_info, ranges, sizes)
	return
}

@(private = "file")
@(require_results)
build_acceleration_structure :: proc(
	structure: Acceleration_Structure,
	build_info: ^vk.AccelerationStructureBuildGeometryInfoKHR,
	ranges: []vk.AccelerationStructureBuildRangeInfoKHR,
	sizes: vk.AccelerationStructureBuildSizesInfoKHR,
) -> Error {
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
	vk.CmdBuildAccelerationStructuresKHR(cmd, 1, build_info, &range_pointer)
	memory_barrier(
		cmd,
		{.ACCELERATION_STRUCTURE_BUILD_KHR},
		{.ACCELERATION_STRUCTURE_WRITE_KHR},
		{.ALL_COMMANDS},
		{.MEMORY_READ, .ACCELERATION_STRUCTURE_READ_KHR},
	)
	return nil
}
