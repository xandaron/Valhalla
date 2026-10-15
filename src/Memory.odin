package Valhalla

import "base:runtime"
import "core:log"
import vk "vendor:vulkan"

@(private)
find_memory_type :: proc(type_bits: u32, properties: vk.MemoryPropertyFlags) -> (index: u32, found: bool) {
	for memory_type, type_index in device.memory_properties.memoryTypes[:device.memory_properties.memoryTypeCount] {
		if type_bits & (1 << u32(type_index)) != 0 && properties <= memory_type.propertyFlags {
			return u32(type_index), true
		}
	}
	return
}

Memory_Error :: enum {
	None,
	No_Suitable_Memory_Type,
	Allocation_Failed,
	Map_Failed,
	Out_Of_Budget,
	Host_Buffer_Creation_Failed,
}

Allocation :: struct {
	memory: vk.DeviceMemory,
	offset: vk.DeviceSize,
	size:   vk.DeviceSize,
	mapped: [^]byte,
	block:  ^Memory_Block,
}

@(private)
Memory_Usage :: enum {
	Linear,
	Optimal,
}

@(private)
Memory_Range :: struct {
	offset: vk.DeviceSize,
	size:   vk.DeviceSize,
}

@(private)
Memory_Block :: struct {
	memory:      vk.DeviceMemory,
	size:        vk.DeviceSize,
	memory_type: u32,
	usage:       Memory_Usage,
	mapped:      [^]byte,
	free:        [dynamic]Memory_Range,
}

@(private = "file")
Memory_Allocator :: struct {
	blocks:              [dynamic]^Memory_Block,
	dedicated_count:     u32,
	suballocation_count: u32,
	live_dedicated:      u32,
	live_suballocations: u32,
}

@(private = "file")
memory_allocator: Memory_Allocator

@(private = "file")
MEMORY_BLOCK_SIZE: vk.DeviceSize : 64 * 1024 * 1024

@(private = "file")
MEMORY_FIRST_BLOCK_SIZE: vk.DeviceSize : 8 * 1024 * 1024

@(private = "file")
DEDICATED_THRESHOLD: vk.DeviceSize : MEMORY_BLOCK_SIZE / 4

@(private = "file")
MEMORY_PRIORITY_DEDICATED :: f32(1.0)

@(private = "file")
MEMORY_PRIORITY_BLOCK :: f32(0.5)

@(private)
Memory_Resource :: union {
	vk.Buffer,
	vk.Image,
}

@(private)
@(require_results)
allocate_memory :: proc(resource: Memory_Resource, properties: vk.MemoryPropertyFlags) -> (allocation: Allocation, err: Error) {
	dedicated_requirements: vk.MemoryDedicatedRequirements = {
		sType = .MEMORY_DEDICATED_REQUIREMENTS,
	}
	requirements2: vk.MemoryRequirements2 = {
		sType = .MEMORY_REQUIREMENTS_2,
		pNext = &dedicated_requirements,
	}
	dedicated_info: vk.MemoryDedicatedAllocateInfo = {
		sType = .MEMORY_DEDICATED_ALLOCATE_INFO,
	}
	usage: Memory_Usage
	switch handle in resource {
	case vk.Buffer:
		vk.GetBufferMemoryRequirements2(device.handle, &{sType = .BUFFER_MEMORY_REQUIREMENTS_INFO_2, buffer = handle}, &requirements2)
		dedicated_info.buffer = handle
		usage = .Linear
	case vk.Image:
		vk.GetImageMemoryRequirements2(device.handle, &{sType = .IMAGE_MEMORY_REQUIREMENTS_INFO_2, image = handle}, &requirements2)
		dedicated_info.image = handle
		usage = .Optimal
	}
	requirements := requirements2.memoryRequirements
	dedicated: ^vk.MemoryDedicatedAllocateInfo
	if dedicated_requirements.prefersDedicatedAllocation || dedicated_requirements.requiresDedicatedAllocation {
		dedicated = &dedicated_info
	}

	memory_type, found := find_memory_type(requirements.memoryTypeBits, properties)
	if !found {
		log.errorf("No memory type has the properties %v", properties)
		return {}, .No_Suitable_Memory_Type
	}
	host_visible := .HOST_VISIBLE in device.memory_properties.memoryTypes[memory_type].propertyFlags

	if dedicated != nil || requirements.size >= DEDICATED_THRESHOLD {
		if !memory_within_budget(memory_type, requirements.size) {
			log.errorf("The heap for memory type %v cannot fit a %v byte dedicated allocation", memory_type, requirements.size)
			return {}, .Out_Of_Budget
		}
		memory, mapped := allocate_device_memory(requirements.size, memory_type, host_visible, dedicated, MEMORY_PRIORITY_DEDICATED) or_return
		memory_allocator.dedicated_count += 1
		memory_allocator.live_dedicated += 1
		return {memory = memory, size = requirements.size, mapped = mapped}, nil
	}

	block: ^Memory_Block
	offset: vk.DeviceSize
	carved := false
	for candidate in memory_allocator.blocks {
		if candidate.memory_type == memory_type && candidate.usage == usage {
			if offset, carved = carve_block(candidate, requirements.size, requirements.alignment); carved {
				block = candidate
				break
			}
		}
	}
	if !carved {
		block = add_memory_block(memory_type, usage, host_visible, requirements.size + requirements.alignment) or_return
		if offset, carved = carve_block(block, requirements.size, requirements.alignment); !carved {
			log.error("An allocation did not fit in a fresh memory block")
			return {}, .Allocation_Failed
		}
	}
	memory_allocator.suballocation_count += 1
	memory_allocator.live_suballocations += 1
	return block_allocation(block, offset, requirements.size), nil
}

@(private)
free_memory :: proc(allocation: ^Allocation) {
	if allocation.memory == 0 {
		return
	}
	if allocation.block == nil {
		release_device_memory(allocation.memory, allocation.mapped)
		memory_allocator.live_dedicated -= 1
	} else {
		release_block_range(allocation.block, allocation.offset, allocation.size)
		memory_allocator.live_suballocations -= 1
	}
	allocation^ = {}
}

@(private)
report_memory_leaks :: proc() {
	log.infof(
		"Memory live: %v blocks + %v dedicated, serving %v suballocations",
		len(memory_allocator.blocks),
		memory_allocator.live_dedicated,
		memory_allocator.live_suballocations,
	)
	log.infof(
		"Memory lifetime: %v vkAllocateMemory calls, %v suballocations",
		u32(len(memory_allocator.blocks)) + memory_allocator.dedicated_count,
		memory_allocator.suballocation_count,
	)
	for block, index in memory_allocator.blocks {
		used := block.size
		for range in block.free {
			used -= range.size
		}
		if used != 0 {
			log.warnf("Memory block %v (type %v) still has %v bytes allocated", index, block.memory_type, used)
		}
	}
	if memory_allocator.live_dedicated != 0 {
		log.warnf("%v dedicated allocations were never freed", memory_allocator.live_dedicated)
	}
}

@(private)
destroy_memory_allocator :: proc() {
	for block in memory_allocator.blocks {
		release_device_memory(block.memory, block.mapped)
		delete(block.free)
		free(block)
	}
	delete(memory_allocator.blocks)
	memory_allocator = {}
}

@(private = "file")
memory_within_budget :: proc(memory_type: u32, size: vk.DeviceSize) -> bool {
	budget_properties: vk.PhysicalDeviceMemoryBudgetPropertiesEXT = {
		sType = .PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT,
	}
	properties: vk.PhysicalDeviceMemoryProperties2 = {
		sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2,
		pNext = &budget_properties,
	}
	vk.GetPhysicalDeviceMemoryProperties2(device.physical_device, &properties)
	heap := device.memory_properties.memoryTypes[memory_type].heapIndex
	budget, usage := budget_properties.heapBudget[heap], budget_properties.heapUsage[heap]
	return budget == 0 || usage + size <= budget
}

@(private = "file")
@(require_results)
allocate_device_memory :: proc(
	size: vk.DeviceSize,
	memory_type: u32,
	host_visible: bool,
	dedicated: ^vk.MemoryDedicatedAllocateInfo,
	priority: f32,
) -> (
	memory: vk.DeviceMemory,
	mapped: [^]byte,
	err: Error,
) {
	priority_info: vk.MemoryPriorityAllocateInfoEXT = {
		sType    = .MEMORY_PRIORITY_ALLOCATE_INFO_EXT,
		pNext    = dedicated,
		priority = priority,
	}
	flags_info: vk.MemoryAllocateFlagsInfo = {
		sType = .MEMORY_ALLOCATE_FLAGS_INFO,
		pNext = &priority_info,
		flags = {.DEVICE_ADDRESS},
	}
	allocate_info: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = &flags_info,
		allocationSize  = size,
		memoryTypeIndex = memory_type,
	}
	if res := vk.AllocateMemory(device.handle, &allocate_info, nil, &memory); res != .SUCCESS {
		log.errorf("Failed to allocate device memory: %v", res)
		return 0, nil, .Allocation_Failed
	}

	if host_visible {
		map_info: vk.MemoryMapInfo = {
			sType  = .MEMORY_MAP_INFO,
			memory = memory,
			size   = size,
		}
		pointer: rawptr
		if res := vk.MapMemory2(device.handle, &map_info, &pointer); res != .SUCCESS {
			log.errorf("Failed to map device memory: %v", res)
			vk.FreeMemory(device.handle, memory, nil)
			return 0, nil, .Map_Failed
		}
		mapped = ([^]byte)(pointer)
	}
	return memory, mapped, nil
}

@(private = "file")
release_device_memory :: proc(memory: vk.DeviceMemory, mapped: [^]byte) {
	if mapped != nil {
		unmap_info: vk.MemoryUnmapInfo = {
			sType  = .MEMORY_UNMAP_INFO,
			memory = memory,
		}
		vk.UnmapMemory2(device.handle, &unmap_info)
	}
	vk.FreeMemory(device.handle, memory, nil)
}

@(private = "file")
@(require_results)
add_memory_block :: proc(
	memory_type: u32,
	usage: Memory_Usage,
	host_visible: bool,
	minimum_size: vk.DeviceSize,
) -> (
	block: ^Memory_Block,
	err: Error,
) {
	existing := 0
	for other in memory_allocator.blocks {
		if other.memory_type == memory_type && other.usage == usage {
			existing += 1
		}
	}
	block_size := MEMORY_FIRST_BLOCK_SIZE
	for _ in 0 ..< existing {
		block_size *= 2
		if block_size >= MEMORY_BLOCK_SIZE {
			block_size = MEMORY_BLOCK_SIZE
			break
		}
	}
	block_size = max(block_size, minimum_size)

	for !memory_within_budget(memory_type, block_size) {
		if block_size <= minimum_size {
			log.errorf("The heap for memory type %v is out of budget (needed %v bytes)", memory_type, minimum_size)
			return nil, .Out_Of_Budget
		}
		block_size = max(block_size / 2, minimum_size)
	}

	memory, mapped := allocate_device_memory(block_size, memory_type, host_visible, nil, MEMORY_PRIORITY_BLOCK) or_return
	block = new(Memory_Block)
	block^ = {
		memory      = memory,
		size        = block_size,
		memory_type = memory_type,
		usage       = usage,
		mapped      = mapped,
		free        = make([dynamic]Memory_Range),
	}
	append(&block.free, Memory_Range{offset = 0, size = block_size})
	append(&memory_allocator.blocks, block)
	log.infof("Allocated a %v MiB %v memory block (type %v)", block_size / (1024 * 1024), usage, memory_type)
	return block, nil
}

@(private = "file")
block_allocation :: proc(block: ^Memory_Block, offset, size: vk.DeviceSize) -> Allocation {
	allocation := Allocation {
		memory = block.memory,
		offset = offset,
		size   = size,
		block  = block,
	}
	if block.mapped != nil {
		allocation.mapped = block.mapped[offset:]
	}
	return allocation
}

@(private)
round_up :: proc(value, multiple: vk.DeviceSize) -> vk.DeviceSize {
	if multiple == 0 {
		return value
	}
	return (value + multiple - 1) / multiple * multiple
}

@(private = "file")
carve_block :: proc(block: ^Memory_Block, size, alignment: vk.DeviceSize) -> (offset: vk.DeviceSize, ok: bool) {
	for &range, index in block.free {
		aligned := round_up(range.offset, alignment)
		padding := aligned - range.offset
		if range.size < padding + size {
			continue
		}
		trailing := range.size - padding - size
		switch {
		case padding == 0 && trailing == 0:
			ordered_remove(&block.free, index)
		case padding == 0:
			range.offset = aligned + size
			range.size = trailing
		case trailing == 0:
			range.size = padding
		case:
			range.size = padding
			inject_at(&block.free, index + 1, Memory_Range{aligned + size, trailing})
		}
		return aligned, true
	}
	return 0, false
}

@(private = "file")
release_block_range :: proc(block: ^Memory_Block, offset, size: vk.DeviceSize) {
	index := 0
	for index < len(block.free) && block.free[index].offset < offset {
		index += 1
	}
	inject_at(&block.free, index, Memory_Range{offset, size})
	if index + 1 < len(block.free) && block.free[index].offset + block.free[index].size == block.free[index + 1].offset {
		block.free[index].size += block.free[index + 1].size
		ordered_remove(&block.free, index + 1)
	}
	if index > 0 && block.free[index - 1].offset + block.free[index - 1].size == block.free[index].offset {
		block.free[index - 1].size += block.free[index].size
		ordered_remove(&block.free, index)
	}
}

Staging_Error :: enum {
	None,
	Staging_Semaphore_Creation_Failed,
	Staging_Pool_Creation_Failed,
	Staging_Recording_Failed,
	Staging_Submit_Failed,
}

@(private = "file")
STAGING_SIZE: vk.DeviceSize : 64 * 1024 * 1024

@(private = "file")
Staging_Batch :: struct {
	head:           u64,
	value:          u64,
	command_buffer: vk.CommandBuffer,
	oversized:      [dynamic]Host_Buffer,
}

@(private = "file")
Staging_Ring :: struct {
	buffer:         Host_Buffer,
	head:           u64,
	tail:           u64,
	timeline:       vk.Semaphore,
	submitted:      u64,
	pending:        [dynamic]Staging_Batch,
	command_pool:   vk.CommandPool,
	command_buffer: vk.CommandBuffer,
	recording:      bool,
	idle:           [dynamic]vk.CommandBuffer,
	oversized:      [dynamic]Host_Buffer,
}

@(private = "file")
staging: Staging_Ring

@(private)
@(require_results)
stage :: proc(
	size: vk.DeviceSize,
	alignment: vk.DeviceSize = 16,
) -> (
	buffer: vk.Buffer,
	offset: vk.DeviceSize,
	mapped: [^]byte,
	err: Error,
) {
	if staging.buffer.handle == 0 {
		open_staging() or_return
		staging.buffer = make_host_buffer(STAGING_SIZE, {.TRANSFER_SRC}) or_return
		log.infof("Staging ring: %v MiB", STAGING_SIZE / (1024 * 1024))
	}
	if reserved_offset, reserved := reserve_staging(size, alignment); reserved {
		return staging.buffer.handle, reserved_offset, staging.buffer.allocation.mapped[reserved_offset:], nil
	}
	oversized := make_host_buffer(size, {.TRANSFER_SRC}) or_return
	append(&staging.oversized, oversized)
	return oversized.handle, 0, oversized.allocation.mapped, nil
}

@(private)
@(require_results)
staging_commands :: proc() -> (command_buffer: vk.CommandBuffer, err: Error) {
	if staging.recording {
		memory_barrier(staging.command_buffer, {.ALL_TRANSFER}, {.TRANSFER_READ, .TRANSFER_WRITE}, {.ALL_TRANSFER}, {.TRANSFER_READ, .TRANSFER_WRITE})
		return staging.command_buffer, nil
	}
	open_staging() or_return
	retire_staging()
	if len(staging.idle) > 0 {
		staging.command_buffer = pop(&staging.idle)
	} else {
		allocate_info: vk.CommandBufferAllocateInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = staging.command_pool,
			level              = .PRIMARY,
			commandBufferCount = 1,
		}
		if res := vk.AllocateCommandBuffers(device.handle, &allocate_info, &staging.command_buffer); res != .SUCCESS {
			log.errorf("Failed to allocate a staging command buffer: %v", res)
			return nil, .Staging_Recording_Failed
		}
	}
	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if res := vk.BeginCommandBuffer(staging.command_buffer, &begin_info); res != .SUCCESS {
		log.errorf("Failed to begin a staging command buffer: %v", res)
		return nil, .Staging_Recording_Failed
	}
	memory_barrier(staging.command_buffer, {.ALL_COMMANDS}, {.MEMORY_READ, .MEMORY_WRITE}, {.ALL_TRANSFER}, {.TRANSFER_READ, .TRANSFER_WRITE})
	staging.recording = true
	return staging.command_buffer, nil
}

@(private)
@(require_results)
flush_staging :: proc() -> Error {
	if !staging.recording {
		return nil
	}
	memory_barrier(staging.command_buffer, {.ALL_TRANSFER}, {.TRANSFER_WRITE}, {.ALL_COMMANDS}, {.MEMORY_READ, .MEMORY_WRITE})
	if res := vk.EndCommandBuffer(staging.command_buffer); res != .SUCCESS {
		log.errorf("Failed to end a staging command buffer: %v", res)
		return .Staging_Recording_Failed
	}
	staging.recording = false
	staging.submitted += 1
	command_buffer := staging.command_buffer
	staging.command_buffer = nil

	command_info: vk.CommandBufferSubmitInfo = {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = command_buffer,
	}
	signal_info: vk.SemaphoreSubmitInfo = {
		sType     = .SEMAPHORE_SUBMIT_INFO,
		semaphore = staging.timeline,
		value     = staging.submitted,
		stageMask = {.ALL_COMMANDS},
	}
	submit_info: vk.SubmitInfo2 = {
		sType                    = .SUBMIT_INFO_2,
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = &command_info,
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = &signal_info,
	}
	if res := vk.QueueSubmit2(device.graphics_queue, 1, &submit_info, 0); res != .SUCCESS {
		log.errorf("Failed to submit staging commands: %v", res)
		append(&staging.idle, command_buffer)
		return .Staging_Submit_Failed
	}
	append(
		&staging.pending,
		Staging_Batch{head = staging.head, value = staging.submitted, command_buffer = command_buffer, oversized = staging.oversized},
	)
	staging.oversized = {}
	return nil
}

@(private)
@(require_results)
upload_to_buffer :: proc(destination: vk.Buffer, destination_offset: vk.DeviceSize, source: []u8) -> Error {
	size := vk.DeviceSize(len(source))
	buffer, offset, mapped := stage(size) or_return
	runtime.mem_copy_non_overlapping(mapped, raw_data(source), len(source))
	command_buffer := staging_commands() or_return
	emit_buffer_copy(command_buffer, buffer, destination, {sType = .BUFFER_COPY_2, srcOffset = offset, dstOffset = destination_offset, size = size})
	return nil
}

@(private = "file")
@(require_results)
open_staging :: proc() -> Error {
	if staging.command_pool != 0 {
		return nil
	}
	pool_info: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.TRANSIENT, .RESET_COMMAND_BUFFER},
		queueFamilyIndex = device.queue_families.graphics,
	}
	if res := vk.CreateCommandPool(device.handle, &pool_info, nil, &staging.command_pool); res != .SUCCESS {
		log.errorf("Failed to create the staging command pool: %v", res)
		return .Staging_Pool_Creation_Failed
	}
	type_info: vk.SemaphoreTypeCreateInfo = {
		sType         = .SEMAPHORE_TYPE_CREATE_INFO,
		semaphoreType = .TIMELINE,
	}
	semaphore_info: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = &type_info,
	}
	if res := vk.CreateSemaphore(device.handle, &semaphore_info, nil, &staging.timeline); res != .SUCCESS {
		log.errorf("Failed to create the staging timeline semaphore: %v", res)
		return .Staging_Semaphore_Creation_Failed
	}
	return nil
}

@(private)
close_staging :: proc() {
	if staging.command_pool == 0 {
		return
	}
	wait_staging()
	if staging.timeline != 0 {
		vk.DestroySemaphore(device.handle, staging.timeline, nil)
	}
	destroy_host_buffer(&staging.buffer)
	vk.DestroyCommandPool(device.handle, staging.command_pool, nil)
	delete(staging.pending)
	delete(staging.idle)
	delete(staging.oversized)
	staging = {}
}

@(private)
settle_staging :: proc() {
	if !staging.recording && len(staging.pending) > 0 {
		retire_staging()
	}
	if staging.recording || len(staging.pending) > 0 {
		wait_staging()
	}
}

@(private = "file")
wait_staging :: proc() {
	if flush_staging() != nil {
		log.error("Staging commands could not be submitted before waiting")
	}
	for len(staging.pending) > 0 {
		wait_staging_batch()
	}
}

@(private)
Host_Buffer :: struct {
	handle:     vk.Buffer,
	allocation: Allocation,
}

@(private)
@(require_results)
make_host_buffer :: proc(size: vk.DeviceSize, usage: vk.BufferUsageFlags2) -> (buffer: Host_Buffer, err: Error) {
	usage_info: vk.BufferUsageFlags2CreateInfo = {
		sType = .BUFFER_USAGE_FLAGS_2_CREATE_INFO,
		usage = usage,
	}
	buffer_info: vk.BufferCreateInfo = {
		sType       = .BUFFER_CREATE_INFO,
		pNext       = &usage_info,
		size        = size,
		sharingMode = .EXCLUSIVE,
	}
	if res := vk.CreateBuffer(device.handle, &buffer_info, nil, &buffer.handle); res != .SUCCESS {
		log.errorf("Failed to create a host buffer: %v", res)
		return {}, .Host_Buffer_Creation_Failed
	}
	defer if err != nil {
		destroy_host_buffer(&buffer)
	}
	buffer.allocation = allocate_memory(buffer.handle, {.HOST_VISIBLE, .HOST_COHERENT}) or_return
	if res := vk.BindBufferMemory(device.handle, buffer.handle, buffer.allocation.memory, buffer.allocation.offset); res != .SUCCESS {
		log.errorf("Failed to bind host buffer memory: %v", res)
		return buffer, .Host_Buffer_Creation_Failed
	}
	return
}

@(private)
destroy_host_buffer :: proc(buffer: ^Host_Buffer) {
	if buffer.handle != 0 {
		vk.DestroyBuffer(device.handle, buffer.handle, nil)
	}
	free_memory(&buffer.allocation)
	buffer^ = {}
}

@(private)
buffer_address :: proc(buffer: vk.Buffer) -> vk.DeviceAddress {
	return vk.GetBufferDeviceAddress(device.handle, &{sType = .BUFFER_DEVICE_ADDRESS_INFO, buffer = buffer})
}

@(private = "file")
reserve_staging :: proc(size, alignment: vk.DeviceSize) -> (offset: vk.DeviceSize, ok: bool) {
	if size > STAGING_SIZE {
		return 0, false
	}
	head := u64(round_up(vk.DeviceSize(staging.head), alignment))
	if vk.DeviceSize(head % u64(STAGING_SIZE)) + size > STAGING_SIZE {
		head += u64(STAGING_SIZE) - head % u64(STAGING_SIZE)
	}
	for head + u64(size) - staging.tail > u64(STAGING_SIZE) {
		if len(staging.pending) == 0 {
			if flush_staging() != nil || len(staging.pending) == 0 {
				break
			}
		}
		wait_staging_batch()
	}
	staging.head = head + u64(size)
	return vk.DeviceSize(head % u64(STAGING_SIZE)), true
}

@(private = "file")
retire_oldest_batch :: proc() {
	batch := pop_front(&staging.pending)
	staging.tail = batch.head
	append(&staging.idle, batch.command_buffer)
	for &buffer in batch.oversized {
		destroy_host_buffer(&buffer)
	}
	delete(batch.oversized)
}

@(private = "file")
retire_staging :: proc() {
	completed: u64
	if res := vk.GetSemaphoreCounterValue(device.handle, staging.timeline, &completed); res != .SUCCESS {
		log.errorf("Failed to read the staging timeline: %v", res)
		return
	}
	for len(staging.pending) > 0 && staging.pending[0].value <= completed {
		retire_oldest_batch()
	}
}

@(private = "file")
wait_staging_batch :: proc() {
	if len(staging.pending) == 0 {
		return
	}
	value := staging.pending[0].value
	wait_info: vk.SemaphoreWaitInfo = {
		sType          = .SEMAPHORE_WAIT_INFO,
		semaphoreCount = 1,
		pSemaphores    = &staging.timeline,
		pValues        = &value,
	}
	if res := vk.WaitSemaphores(device.handle, &wait_info, max(u64)); res != .SUCCESS {
		log.errorf("Failed to wait on the staging timeline: %v", res)
	}
	retire_oldest_batch()
}
