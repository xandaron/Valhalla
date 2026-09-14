package Valhalla

import "core:mem"
import vk "vendor:vulkan"

@(private = "file")
BLOCK_SIZE: vk.DeviceSize : 64 * 1024 * 1024

@(private = "file")
DEDICATED_THRESHOLD: vk.DeviceSize : BLOCK_SIZE / 4

@(private = "file")
STAGING_SIZE: vk.DeviceSize : 64 * 1024 * 1024

MemoryUsage :: enum {
	Linear,
	Optimal,
}

MemoryError :: enum {
	None = 0,
	NoSuitableMemoryType,
	FailedToAllocate,
	FailedToMap,
	OutOfBudget,
}

StagingError :: enum {
	None = 0,
	FailedToCreateBuffer,
	FailedToCreateSemaphore,
	FailedToRecord,
	FailedToSubmit,
}

@(private = "file")
MemoryRange :: struct {
	offset: vk.DeviceSize,
	size:   vk.DeviceSize,
}

@(private = "file")
MemoryBlock :: struct {
	memory:          vk.DeviceMemory,
	size:            vk.DeviceSize,
	memoryTypeIndex: u32,
	usage:           MemoryUsage,
	mapped:          rawptr,
	free:            [dynamic]MemoryRange,
}

Allocation :: struct {
	memory: vk.DeviceMemory,
	offset: vk.DeviceSize,
	size:   vk.DeviceSize,
	mapped: rawptr,
	block:  ^MemoryBlock,
}

MemoryAllocator :: struct {
	device:         vk.Device,
	physicalDevice: vk.PhysicalDevice,
	properties:     vk.PhysicalDeviceMemoryProperties,
	blocks:         [dynamic]^MemoryBlock,
	dedicatedCount: u32,
	suballocCount:  u32,
}

@(private = "file")
StagingBatch :: struct {
	head:  u64,
	value: u64,
}

StagingRing :: struct {
	buffer:        vk.Buffer,
	allocation:    Allocation,
	mapped:        rawptr,

	size:          vk.DeviceSize,
	head:          u64,
	tail:          u64,

	timeline:      vk.Semaphore,
	submitted:     u64,
	pending:       [dynamic]StagingBatch,

	commandBuffer: vk.CommandBuffer,
	recording:     bool,

	oversized:     [dynamic]Buffer,
}

memoryAllocatorInit :: proc(
	allocator: ^MemoryAllocator,
	device: vk.Device,
	physicalDevice: vk.PhysicalDevice,
	properties: vk.PhysicalDeviceMemoryProperties,
) {
	allocator.device = device
	allocator.physicalDevice = physicalDevice
	allocator.properties = properties
	allocator.blocks = make([dynamic]^MemoryBlock)
}

@(require_results)
memoryHeapBudget :: proc(
	allocator: ^MemoryAllocator,
	heapIndex: u32,
) -> (
	budget, usage: vk.DeviceSize,
) {
	budgetProperties: vk.PhysicalDeviceMemoryBudgetPropertiesEXT = {
		sType = .PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT,
		pNext = nil,
	}
	properties: vk.PhysicalDeviceMemoryProperties2 = {
		sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2,
		pNext = &budgetProperties,
	}
	vk.GetPhysicalDeviceMemoryProperties2(allocator.physicalDevice, &properties)
	return budgetProperties.heapBudget[heapIndex], budgetProperties.heapUsage[heapIndex]
}

@(require_results)
memoryWithinBudget :: proc(
	allocator: ^MemoryAllocator,
	memoryTypeIndex: u32,
	size: vk.DeviceSize,
) -> bool {
	heapIndex := allocator.properties.memoryTypes[memoryTypeIndex].heapIndex
	budget, usage := memoryHeapBudget(allocator, heapIndex)
	if budget == 0 {
		return true
	}
	return usage + size <= budget
}

memoryAllocatorDestroy :: proc(allocator: ^MemoryAllocator) {
	for block in allocator.blocks {
		if block.mapped != nil {
			vk.UnmapMemory(allocator.device, block.memory)
		}
		vk.FreeMemory(allocator.device, block.memory, nil)
		delete(block.free)
		free(block)
	}
	delete(allocator.blocks)
	allocator.blocks = nil
}

memoryAllocatorReportLeaks :: proc(allocator: ^MemoryAllocator) {
	logf(
		.Info,
		"Memory: %v blocks + %v dedicated = %v vkAllocateMemory calls, serving %v suballocations.",
		len(allocator.blocks),
		allocator.dedicatedCount,
		u32(len(allocator.blocks)) + allocator.dedicatedCount,
		allocator.suballocCount,
	)

	for block, index in allocator.blocks {
		used := block.size
		for range in block.free {
			used -= range.size
		}
		if used != 0 {
			logf(
				.Warning,
				"Memory block %v (type %v) still has %v bytes allocated.",
				index,
				block.memoryTypeIndex,
				used,
			)
		}
	}
}

@(require_results)
memoryFindType :: proc(
	allocator: ^MemoryAllocator,
	typeFilter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	index: u32,
	ok: bool,
) {
	for i in 0 ..< allocator.properties.memoryTypeCount {
		if typeFilter & (1 << i) != 0 &&
		   (allocator.properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i, true
		}
	}
	return 0, false
}

@(require_results)
memoryAllocate :: proc(
	allocator: ^MemoryAllocator,
	requirements: vk.MemoryRequirements,
	properties: vk.MemoryPropertyFlags,
	usage: MemoryUsage,
	dedicatedInfo: ^vk.MemoryDedicatedAllocateInfo = nil,
) -> (
	allocation: Allocation,
	err: MemoryError,
) {
	memoryTypeIndex, found := memoryFindType(allocator, requirements.memoryTypeBits, properties)
	if !found {
		log(.Error, "Failed to find a suitable memory type!")
		return {}, .NoSuitableMemoryType
	}

	hostVisible := .HOST_VISIBLE in allocator.properties.memoryTypes[memoryTypeIndex].propertyFlags

	if dedicatedInfo != nil || requirements.size >= DEDICATED_THRESHOLD {
		if !memoryWithinBudget(allocator, memoryTypeIndex, requirements.size) {
			logf(
				.Error,
				"Heap for memory type %v cannot fit a %v byte dedicated allocation.",
				memoryTypeIndex,
				requirements.size,
			)
			return {}, .OutOfBudget
		}
		memory, mapped := memoryAllocateRaw(
			allocator,
			requirements.size,
			memoryTypeIndex,
			hostVisible,
			dedicatedInfo,
		) or_return
		allocator.dedicatedCount += 1
		return {memory = memory, offset = 0, size = requirements.size, mapped = mapped}, .None
	}

	for block in allocator.blocks {
		if block.memoryTypeIndex != memoryTypeIndex || block.usage != usage {
			continue
		}
		if offset, ok := blockCarve(block, requirements.size, requirements.alignment); ok {
			allocator.suballocCount += 1
			return makeAllocation(block, offset, requirements.size), .None
		}
	}

	block := memoryAddBlock(
		allocator,
		memoryTypeIndex,
		usage,
		hostVisible,
		requirements.size + requirements.alignment,
	) or_return
	offset, ok := blockCarve(block, requirements.size, requirements.alignment)
	if !ok {
		log(.Error, "Allocation did not fit in a fresh memory block!")
		return {}, .FailedToAllocate
	}
	allocator.suballocCount += 1
	return makeAllocation(block, offset, requirements.size), .None
}

memoryFree :: proc(allocator: ^MemoryAllocator, allocation: ^Allocation) {
	if allocation.memory == 0 {
		return
	}

	if allocation.block == nil {
		if allocation.mapped != nil {
			vk.UnmapMemory(allocator.device, allocation.memory)
		}
		vk.FreeMemory(allocator.device, allocation.memory, nil)
	} else {
		blockRelease(allocation.block, allocation.offset, allocation.size)
	}

	allocation^ = {}
}

@(private = "file")
makeAllocation :: proc(
	block: ^MemoryBlock,
	offset, size: vk.DeviceSize,
) -> (
	allocation: Allocation,
) {
	allocation = {
		memory = block.memory,
		offset = offset,
		size   = size,
		block  = block,
	}
	if block.mapped != nil {
		allocation.mapped = rawptr(uintptr(block.mapped) + uintptr(offset))
	}
	return
}

@(private = "file")
@(require_results)
memoryAllocateRaw :: proc(
	allocator: ^MemoryAllocator,
	size: vk.DeviceSize,
	memoryTypeIndex: u32,
	hostVisible: bool,
	dedicatedInfo: ^vk.MemoryDedicatedAllocateInfo,
) -> (
	memory: vk.DeviceMemory,
	mapped: rawptr,
	err: MemoryError,
) {
	allocInfo: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = dedicatedInfo,
		allocationSize  = size,
		memoryTypeIndex = memoryTypeIndex,
	}
	if res := vk.AllocateMemory(allocator.device, &allocInfo, nil, &memory); res != .SUCCESS {
		logf(.Error, "Failed to allocate device memory! vkResult: %v", res)
		return 0, nil, .FailedToAllocate
	}

	if hostVisible {
		if res := vk.MapMemory(allocator.device, memory, 0, size, {}, &mapped); res != .SUCCESS {
			logf(.Error, "Failed to map device memory! vkResult: %v", res)
			vk.FreeMemory(allocator.device, memory, nil)
			return 0, nil, .FailedToMap
		}
	}
	return memory, mapped, .None
}

@(private = "file")
@(require_results)
memoryAddBlock :: proc(
	allocator: ^MemoryAllocator,
	memoryTypeIndex: u32,
	usage: MemoryUsage,
	hostVisible: bool,
	minimumSize: vk.DeviceSize,
) -> (
	block: ^MemoryBlock,
	err: MemoryError,
) {
	blockSize := BLOCK_SIZE
	for !memoryWithinBudget(allocator, memoryTypeIndex, blockSize) {
		if blockSize <= minimumSize {
			logf(
				.Error,
				"Heap for memory type %v is out of budget (needed %v bytes).",
				memoryTypeIndex,
				minimumSize,
			)
			return nil, .OutOfBudget
		}
		blockSize /= 2
		if blockSize < minimumSize {
			blockSize = minimumSize
		}
	}

	memory, mapped := memoryAllocateRaw(
		allocator,
		blockSize,
		memoryTypeIndex,
		hostVisible,
		nil,
	) or_return

	block = new(MemoryBlock)
	block^ = {
		memory          = memory,
		size            = blockSize,
		memoryTypeIndex = memoryTypeIndex,
		usage           = usage,
		mapped          = mapped,
		free            = make([dynamic]MemoryRange),
	}
	append(&block.free, MemoryRange{offset = 0, size = blockSize})
	append(&allocator.blocks, block)

	logf(
		.Info,
		"Allocated a %v MiB %v memory block (type %v).",
		blockSize / (1024 * 1024),
		usage,
		memoryTypeIndex,
	)
	return block, .None
}

memoryAlignUp :: proc(value, alignment: vk.DeviceSize) -> vk.DeviceSize {
	if alignment == 0 {
		return value
	}
	return (value + alignment - 1) & ~(alignment - 1)
}

@(private = "file")
blockCarve :: proc(
	block: ^MemoryBlock,
	size, alignment: vk.DeviceSize,
) -> (
	offset: vk.DeviceSize,
	ok: bool,
) {
	for &range, index in block.free {
		aligned := memoryAlignUp(range.offset, alignment)
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
			inject_at(&block.free, index + 1, MemoryRange{aligned + size, trailing})
		}
		return aligned, true
	}
	return 0, false
}

@(private = "file")
blockRelease :: proc(block: ^MemoryBlock, offset, size: vk.DeviceSize) {
	index := 0
	for index < len(block.free) && block.free[index].offset < offset {
		index += 1
	}
	inject_at(&block.free, index, MemoryRange{offset, size})

	if index + 1 < len(block.free) &&
	   block.free[index].offset + block.free[index].size == block.free[index + 1].offset {
		block.free[index].size += block.free[index + 1].size
		ordered_remove(&block.free, index + 1)
	}

	if index > 0 &&
	   block.free[index - 1].offset + block.free[index - 1].size == block.free[index].offset {
		block.free[index - 1].size += block.free[index].size
		ordered_remove(&block.free, index)
	}
}

@(require_results)
stagingInit :: proc(graphicsData: ^GraphicsData) -> StagingError {
	ring := &graphicsData.staging
	ring.size = STAGING_SIZE
	ring.pending = make([dynamic]StagingBatch)
	ring.oversized = make([dynamic]Buffer)

	buffer: Buffer
	if err := createBuffer(
		graphicsData,
		int(STAGING_SIZE),
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&buffer,
	); err != nil {
		logf(.Error, "Failed to create staging ring! Error: %v", err)
		return .FailedToCreateBuffer
	}
	ring.buffer = buffer.buffer
	ring.allocation = buffer.allocation
	ring.mapped = buffer.mapped

	semaphoreTypeInfo: vk.SemaphoreTypeCreateInfo = {
		sType         = .SEMAPHORE_TYPE_CREATE_INFO,
		pNext         = nil,
		semaphoreType = .TIMELINE,
		initialValue  = 0,
	}
	semaphoreInfo: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = &semaphoreTypeInfo,
		flags = {},
	}
	if res := vk.CreateSemaphore(graphicsData.device, &semaphoreInfo, nil, &ring.timeline);
	   res != .SUCCESS {
		logf(.Error, "Failed to create staging timeline semaphore! vkResult: %v", res)
		return .FailedToCreateSemaphore
	}

	logf(.Info, "Staging ring: %v MiB.", STAGING_SIZE / (1024 * 1024))
	return .None
}

stagingDestroy :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging

	stagingWait(graphicsData)

	if ring.commandBuffer != nil {
		vk.FreeCommandBuffers(
			graphicsData.device,
			graphicsData.graphicsCommandPool,
			1,
			&ring.commandBuffer,
		)
	}
	vk.DestroySemaphore(graphicsData.device, ring.timeline, nil)
	vk.DestroyBuffer(graphicsData.device, ring.buffer, nil)
	memoryFree(&graphicsData.memoryAllocator, &ring.allocation)

	delete(ring.pending)
	delete(ring.oversized)
	ring^ = {}
}

@(require_results)
stagingCommands :: proc(graphicsData: ^GraphicsData) -> (vk.CommandBuffer, StagingError) {
	ring := &graphicsData.staging
	if ring.recording {
		return ring.commandBuffer, .None
	}

	if ring.commandBuffer == nil {
		allocInfo: vk.CommandBufferAllocateInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			pNext              = nil,
			commandPool        = graphicsData.graphicsCommandPool,
			level              = .PRIMARY,
			commandBufferCount = 1,
		}
		if res := vk.AllocateCommandBuffers(graphicsData.device, &allocInfo, &ring.commandBuffer);
		   res != .SUCCESS {
			logf(.Error, "Failed to allocate staging command buffer! vkResult: %v", res)
			return nil, .FailedToRecord
		}
		vkNameObject(
			graphicsData.device,
			.COMMAND_BUFFER,
			u64(uintptr(ring.commandBuffer)),
			"Cmd: Staging",
		)
	}

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.ONE_TIME_SUBMIT},
		pInheritanceInfo = nil,
	}
	if res := vk.BeginCommandBuffer(ring.commandBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to begin staging command buffer! vkResult: %v", res)
		return nil, .FailedToRecord
	}
	ring.recording = true
	return ring.commandBuffer, .None
}

@(require_results)
stagingReserve :: proc(
	graphicsData: ^GraphicsData,
	size: vk.DeviceSize,
	alignment: vk.DeviceSize = 16,
) -> (
	offset: vk.DeviceSize,
	ptr: rawptr,
	ok: bool,
) {
	ring := &graphicsData.staging
	if size > ring.size {
		return 0, nil, false
	}

	head := u64(memoryAlignUp(vk.DeviceSize(ring.head), alignment))

	if vk.DeviceSize(head % u64(ring.size)) + size > ring.size {
		head += u64(ring.size) - (head % u64(ring.size))
	}

	for head + u64(size) - ring.tail > u64(ring.size) {
		if len(ring.pending) == 0 {
			stagingFlush(graphicsData)
			if len(ring.pending) == 0 {
				break
			}
		}
		stagingWaitBatch(graphicsData)
	}

	ring.head = head + u64(size)
	offset = vk.DeviceSize(head % u64(ring.size))
	return offset, rawptr(uintptr(ring.mapped) + uintptr(offset)), true
}

@(require_results)
stagingOversized :: proc(
	graphicsData: ^GraphicsData,
	size: vk.DeviceSize,
) -> (
	buffer: vk.Buffer,
	ptr: rawptr,
	err: StagingError,
) {
	staging: Buffer
	if createErr := createBuffer(
		graphicsData,
		int(size),
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging,
	); createErr != nil {
		logf(.Error, "Failed to create oversized staging buffer! Error: %v", createErr)
		return 0, nil, .FailedToCreateBuffer
	}
	append(&graphicsData.staging.oversized, staging)
	return staging.buffer, staging.mapped, .None
}

stagingFlush :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging
	if !ring.recording {
		return
	}

	if res := vk.EndCommandBuffer(ring.commandBuffer); res != .SUCCESS {
		logf(.Error, "Failed to end staging command buffer! vkResult: %v", res)
		return
	}
	ring.recording = false
	ring.submitted += 1

	submitInfo: vk.SubmitInfo2 = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = &vk.CommandBufferSubmitInfo {
			sType = .COMMAND_BUFFER_SUBMIT_INFO,
			pNext = nil,
			commandBuffer = ring.commandBuffer,
			deviceMask = 0,
		},
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = &vk.SemaphoreSubmitInfo {
			sType = .SEMAPHORE_SUBMIT_INFO,
			pNext = nil,
			semaphore = ring.timeline,
			value = ring.submitted,
			stageMask = {.ALL_COMMANDS},
			deviceIndex = 0,
		},
	}
	if res := vk.QueueSubmit2(graphicsData.graphicsQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Error, "Failed to submit staging commands! vkResult: %v", res)
		return
	}

	append(&ring.pending, StagingBatch{head = ring.head, value = ring.submitted})
}

@(private = "file")
stagingWaitBatch :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging
	if len(ring.pending) == 0 {
		return
	}

	batch := ring.pending[0]
	value := batch.value
	waitInfo: vk.SemaphoreWaitInfo = {
		sType          = .SEMAPHORE_WAIT_INFO,
		pNext          = nil,
		flags          = {},
		semaphoreCount = 1,
		pSemaphores    = &ring.timeline,
		pValues        = &value,
	}
	if res := vk.WaitSemaphores(graphicsData.device, &waitInfo, max(u64)); res != .SUCCESS {
		logf(.Error, "Failed to wait on staging timeline! vkResult: %v", res)
	}

	ring.tail = batch.head
	ordered_remove(&ring.pending, 0)
}

stagingWait :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging

	stagingFlush(graphicsData)
	for len(ring.pending) > 0 {
		stagingWaitBatch(graphicsData)
	}

	for &buffer in ring.oversized {
		deleteBuffer(graphicsData, &buffer)
	}
	clear(&ring.oversized)
}

@(require_results)
stagingUploadBuffer :: proc(
	graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	dst: vk.Buffer,
	dstOffset: vk.DeviceSize,
	src: rawptr,
	size: vk.DeviceSize,
) -> StagingError {
	srcBuffer: vk.Buffer
	srcOffset: vk.DeviceSize
	ptr: rawptr

	if offset, mapped, ok := stagingReserve(graphicsData, size); ok {
		srcBuffer = graphicsData.staging.buffer
		srcOffset = offset
		ptr = mapped
	} else {
		buffer, mapped := stagingOversized(graphicsData, size) or_return
		srcBuffer = buffer
		srcOffset = 0
		ptr = mapped
	}

	mem.copy(ptr, src, int(size))

	copyRegion: vk.BufferCopy2 = {
		sType     = .BUFFER_COPY_2,
		pNext     = nil,
		srcOffset = srcOffset,
		dstOffset = dstOffset,
		size      = size,
	}
	vk.CmdCopyBuffer2(
		commandBuffer,
		&vk.CopyBufferInfo2 {
			sType = .COPY_BUFFER_INFO_2,
			pNext = nil,
			srcBuffer = srcBuffer,
			dstBuffer = dst,
			regionCount = 1,
			pRegions = &copyRegion,
		},
	)
	return .None
}
