package Valhalla

import vk "vendor:vulkan"

@(private = "file")
BLOCK_SIZE: vk.DeviceSize : 64 * 1024 * 1024

@(private = "file")
DEDICATED_THRESHOLD: vk.DeviceSize : BLOCK_SIZE / 4

MemoryUsage :: enum {
	Linear,
	Optimal,
}

MemoryError :: enum {
	None = 0,
	NoSuitableMemoryType,
	FailedToAllocate,
	FailedToMap,
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
	properties:     vk.PhysicalDeviceMemoryProperties,
	blocks:         [dynamic]^MemoryBlock,
	dedicatedCount: u32,
	suballocCount:  u32,
}

memoryAllocatorInit :: proc(
	allocator: ^MemoryAllocator,
	device: vk.Device,
	properties: vk.PhysicalDeviceMemoryProperties,
) {
	allocator.device = device
	allocator.properties = properties
	allocator.blocks = make([dynamic]^MemoryBlock)
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

	block := memoryAddBlock(allocator, memoryTypeIndex, usage, hostVisible) or_return
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
) -> (
	block: ^MemoryBlock,
	err: MemoryError,
) {
	memory, mapped := memoryAllocateRaw(
		allocator,
		BLOCK_SIZE,
		memoryTypeIndex,
		hostVisible,
		nil,
	) or_return

	block = new(MemoryBlock)
	block^ = {
		memory          = memory,
		size            = BLOCK_SIZE,
		memoryTypeIndex = memoryTypeIndex,
		usage           = usage,
		mapped          = mapped,
		free            = make([dynamic]MemoryRange),
	}
	append(&block.free, MemoryRange{offset = 0, size = BLOCK_SIZE})
	append(&allocator.blocks, block)

	logf(
		.Info,
		"Allocated a %v MiB %v memory block (type %v).",
		BLOCK_SIZE / (1024 * 1024),
		usage,
		memoryTypeIndex,
	)
	return block, .None
}

@(private = "file")
alignUp :: proc(value, alignment: vk.DeviceSize) -> vk.DeviceSize {
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
		aligned := alignUp(range.offset, alignment)
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
