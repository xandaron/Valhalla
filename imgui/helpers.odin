package imgui

import "core:log"
import "core:mem"


when ODIN_DEBUG {
	tracking_allocator: mem.Tracking_Allocator
}

imgui_allocator_no_tracking: mem.Allocator
imgui_allocator: mem.Allocator

imgui_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	alloc_size :: proc(size, alignment: int) -> int {
		return size + alignment - (size % alignment)
	}

	alloc_mem :: proc(size, alignment: int) -> rawptr {
		return MemAlloc(uint(alloc_size(size, alignment)))
	}

	free_mem :: proc(old_memory: rawptr) {
		MemFree(old_memory)
	}

	#partial switch mode {
	case .Free:
		free_mem(old_memory)
		return nil, .None
	case .Alloc_Non_Zeroed:
		ptr := alloc_mem(size, alignment)
		return (transmute([^]byte)ptr)[:size], .None
	case .Alloc:
		ptr := alloc_mem(size, alignment)
		mem.zero(ptr, alloc_size(size, alignment))
		return (transmute([^]byte)ptr)[:size], .None
	case .Resize_Non_Zeroed:
		ptr := alloc_mem(size, alignment)
		mem.copy(ptr, old_memory, old_size)
		free_mem(old_memory)
		return (transmute([^]byte)ptr)[:size], .None
	case .Resize:
		ptr := alloc_mem(size, alignment)
		mem.copy(ptr, old_memory, old_size)
		free_mem(old_memory)
		mem.zero(rawptr(uintptr(ptr) + uintptr(old_size)), alloc_size(size, alignment) - old_size)
		return (transmute([^]byte)ptr)[:size], .None
	case:
		return nil, .Mode_Not_Implemented
	}
	panic("Unreachable!")
}

SetUpAllocator :: proc() {
	imgui_allocator_no_tracking.procedure = imgui_allocator_proc
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&tracking_allocator, imgui_allocator_no_tracking)
		imgui_allocator = mem.tracking_allocator(&tracking_allocator)
	} else {
		imgui_allocator = imgui_allocator_no_tracking
	}
}

CleanUpAllocator :: proc() {
	when ODIN_DEBUG {
		if len(tracking_allocator.allocation_map) > 0 {
			log.logf(
				.Debug,
				"=== %v allocations not freed: ===",
				len(tracking_allocator.allocation_map),
			)
			for _, entry in tracking_allocator.allocation_map {
				log.logf(.Debug, "- %v bytes @ %v", entry.size, entry.location)
			}
		}
		if len(tracking_allocator.bad_free_array) > 0 {
			log.logf(.Debug, "=== %v incorrect frees: ===", len(tracking_allocator.bad_free_array))
			for entry in tracking_allocator.bad_free_array {
				log.logf(.Debug, "- %p @ %v", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&tracking_allocator)
	}
}

Vector :: struct($T: typeid) {
	Size:     i32,
	Capacity: i32,
	Data:     [^]T,
}

// We have to alloc using imgui's alloc methods as the vector objects
// belong to it. Default to using the non tracking allocator as 
// C++ will handle cleanup for us.
Vector_Push_Back :: proc(vector: ^Vector($T), value: T, allocator := imgui_allocator_no_tracking) {
	if vector.Size == vector.Capacity {
		if vector.Capacity == 0 {
			ptr, _ := mem.alloc(size_of(T), allocator = allocator)
			vector.Data = transmute([^]T)ptr
			vector.Capacity = 1
		} else {
			newCap := vector.Capacity * 2
			ptr, _ := mem.resize(
				vector.Data,
				int(vector.Size) * size_of(T),
				int(newCap) * size_of(T),
				allocator = allocator,
			)
			vector.Data = transmute([^]T)ptr
			vector.Capacity = newCap
		}
	}

	vector.Data[vector.Size] = value
	vector.Size += 1
}

