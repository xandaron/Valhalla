package imgui

import "core:mem"


Vector :: struct($T: typeid) {
	Size:     i32,
	Capacity: i32,
	Data:     [^]T,
}

Vector_Push_Back :: proc(vector: ^Vector($T), value: T) {
	if vector.Size == vector.Capacity {
		if vector.Capacity == 0 {
			vector.Data = MemAlloc(size_of(T))
			vector.Capacity = 1
		} else {
			newCap := vector.Capacity * 2
			newPtr := MemAlloc(uint(newCap) * size_of(T))

			mem.copy(newPtr, vector.Data, int(vector.Size) * size_of(T))
			MemFree(vector.Data)

			vector.Capacity = newCap
			vector.Data = newPtr
		}
	}

	vector.Data[vector.Size] = value
	vector.Size += 1
}

