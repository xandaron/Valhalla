// Healpers added to simplify the binding
package ImGui

import "core:mem"


Vector :: struct($T: typeid) {
	Size:     i32,
	Capacity: i32,
	Data:     [^]T,
}

// Constructors, destructor
// inline ImVector()                                       { Size = Capacity = 0; Data = NULL; }
NewVectorZero :: #force_inline proc($T: typeid) -> Vector(T) {
	return {}
}

// inline ImVector(const ImVector<T>& src)                 { Size = Capacity = 0; Data = NULL; operator=(src); }
NewVectorCopy :: #force_inline proc(src: Vector($T)) -> Vector(T) {
	return VectorClone(src)
}

// These constructors are mostly pointless but are included for completeness
NewVector :: proc {
	NewVectorZero,
	NewVectorCopy,
}

// inline ImVector<T>& operator=(const ImVector<T>& src)   { clear(); resize(src.Size); if (Data && src.Data) memcpy(Data, src.Data, (size_t)Size * sizeof(T)); return *this; }
VectorClone :: #force_inline proc(src: Vector($T)) -> Vector(T) {
	this: Vector(T)
	VectorResize(&this, src.Size)
	if this.Data != nil && src.Data != nil {
		mem.copy(this.Data, src.Data, this.Size * size_of(T))
	}
	return this
}

// inline ~ImVector()                                      { if (Data) IM_FREE(Data); } // Important: does not destruct anything
VectorDestroy :: #force_inline proc(this: Vector($T)) {
	if this.Data != nil {
		Gui_MemFree(this.Data)
	}
}

// inline void         clear()                             { if (Data) { Size = Capacity = 0; IM_FREE(Data); Data = NULL; } }  // Important: does not destruct anything
VectorClear :: #force_inline proc(this: ^Vector($T)) {
	if this.Data != nil {
		this.Size = 0
		this.Capacity = 0
		Gui_MemFree(this.Data)
		this.Data = nil
	}
}

// inline void         clear_delete()                      { for (int n = 0; n < Size; n++) IM_DELETE(Data[n]); clear(); }     // Important: never called automatically! always explicit.
// I'm not sure about this one. I made it so the vector must be of a pointer type but I would still avoid using this.
VectorClearDelete :: #force_inline proc(this: ^Vector(^$T)) {
	for n := 0; n < this.Size; n += 1 {
		if this.Data[n] != nil {
			Gui_MemFree(this.Data[n])
		}
	}
	VectorClear(this)
}

// inline void         clear_destruct()                    { for (int n = 0; n < Size; n++) Data[n].~T(); clear(); }           // Important: never called automatically! always explicit.
// We dont have destructors.

// inline bool         empty() const                       { return Size == 0; }
VectorEmpty :: #force_inline proc(this: Vector($T)) -> bool {
	return this.Size == 0
}

// inline int          size() const                        { return Size; }
// inline int          capacity() const                    { return Capacity; }
// Just access the fields yourself.

// inline int          size_in_bytes() const               { return Size * (int)sizeof(T); }
VectorSizeInBytes :: #force_inline proc(this: Vector($T)) -> int {
	return int(this.Size) * size_of(T)
}

// inline int          max_size() const                    { return 0x7FFFFFFF / (int)sizeof(T); }
VectorMaxSize :: #force_inline proc(this: Vector($T)) -> int {
	return 0x7FFFFFFF / size_of(T)
}

// inline T&           operator[](int i)                   { IM_ASSERT(i >= 0 && i < Size); return Data[i]; }
// inline const T&     operator[](int i) const             { IM_ASSERT(i >= 0 && i < Size); return Data[i]; }
VectorIndex :: #force_inline proc(this: Vector($T), #any_int i: int) -> ^T {
	assert(i >= 0 && i < this.Size)
	return &this.Data[i]
}

// inline T*           begin()                             { return Data; }
// inline const T*     begin() const                       { return Data; }
VectorBegin :: #force_inline proc(this: Vector($T)) -> ^T {
	return &this.Data[0]
}

// inline T*           end()                               { return Data + Size; }
// inline const T*     end() const                         { return Data + Size; }
VectorEnd :: #force_inline proc(this: Vector($T)) -> ^T {
	return (^T)(uintptr(this.Data) + uintptr(this.Size) * size_of(T))
}

// inline T&           front()                             { IM_ASSERT(Size > 0); return Data[0]; }
// inline const T&     front() const                       { IM_ASSERT(Size > 0); return Data[0]; }
VectorFront :: #force_inline proc(this: Vector($T)) -> ^T {
	assert(this.Size > 0)
	return &this.Data[0]
}

// inline T&           back()                              { IM_ASSERT(Size > 0); return Data[Size - 1]; }
// inline const T&     back() const                        { IM_ASSERT(Size > 0); return Data[Size - 1]; }
VectorBack :: #force_inline proc(this: Vector($T)) -> ^T {
	assert(this.Size > 0)
	return &this.Data[this.Size - 1]
}

// inline void         swap(ImVector<T>& rhs)              { int rhs_size = rhs.Size; rhs.Size = Size; Size = rhs_size; int rhs_cap = rhs.Capacity; rhs.Capacity = Capacity; Capacity = rhs_cap; T* rhs_data = rhs.Data; rhs.Data = Data; Data = rhs_data; }
VectorSwap :: #force_inline proc(lhs, rhs: ^Vector($T)) {
	rhs_size := rhs.Size
	rhs.Size = lhs.Size
	lhs.Size = rhs_size
	
	rhs_cap := rhs.Capacity
	rhs.Capacity = lhs.Capacity
	lhs.Capacity = rhs_cap
	
	rhs_data := rhs.Data
	rhs.Data = lhs.Data
	lhs.Data = rhs_data
}

// inline int          _grow_capacity(int sz) const        { int new_capacity = Capacity ? (Capacity + Capacity / 2) : 8; return new_capacity > sz ? new_capacity : sz; }
VectorGrowCap :: #force_inline proc(this: ^Vector($T), #any_int sz: int) -> int {
	new_capacity := this.Capacity != 0 ? this.Capacity + this.Capacity / 2 : 8
	return new_capacity > i32(sz) ? int(new_capacity) : sz
}

// inline void         resize(int new_size)                { if (new_size > Capacity) reserve(_grow_capacity(new_size)); Size = new_size; }
VectorResizeZero :: proc(this: ^Vector($T), #any_int new_size: int) {
	if i32(new_size) > this.Capacity {
		VectorReserve(this, VectorGrowCap(this, new_size))
	}
	this.Size = i32(new_size)
}

// inline void         resize(int new_size, const T& v)    { if (new_size > Capacity) reserve(_grow_capacity(new_size)); if (new_size > Size) for (int n = Size; n < new_size; n++) memcpy(&Data[n], &v, sizeof(v)); Size = new_size; }
VectorResizeValue :: #force_inline proc(this: ^Vector($T), #any_int new_size: int, v: ^T) {
	if new_size > this.Capacity {
		VectorReserve(this, VectorGrowCap(this, new_size))
	}
	if new_size > this.Size {
		for n := this.Size; n < new_size; n += 1 {
			this.Data[n] = v
		}
	}
	this.Size = new_size
}

VectorResize :: proc {
	VectorResizeZero,
	VectorResizeValue,
}

// inline void         shrink(int new_size)                { IM_ASSERT(new_size <= Size); Size = new_size; } // Resize a vector to a smaller size, guaranteed not to cause a reallocation
VectorShrink :: #force_inline proc(this: ^Vector($T), #any_int new_size: int) {
	assert(new_size <= this.Size)
	this.Size = i32(new_size)
}

// inline void         reserve(int new_capacity)           { if (new_capacity <= Capacity) return; T* new_data = (T*)IM_ALLOC((size_t)new_capacity * sizeof(T)); if (Data) { memcpy(new_data, Data, (size_t)Size * sizeof(T)); IM_FREE(Data); } Data = new_data; Capacity = new_capacity; }
VectorReserve :: #force_inline proc(this: ^Vector($T), #any_int new_capacity: int) {
	if i32(new_capacity) <= this.Capacity {
		return
	}

	new_data := ([^]T)(Gui_MemAlloc(uint(new_capacity) * size_of(T)))
	if this.Data != nil {
		mem.copy(new_data, this.Data, int(this.Size) * size_of(T))
		Gui_MemFree(this.Data)
	}

	this.Data = new_data
	this.Capacity = i32(new_capacity)
}

// inline void         reserve_discard(int new_capacity)   { if (new_capacity <= Capacity) return; if (Data) IM_FREE(Data); Data = (T*)IM_ALLOC((size_t)new_capacity * sizeof(T)); Capacity = new_capacity; }
VectorReserveDiscard :: #force_inline proc(this: ^Vector($T), #any_int new_capacity: int) {
	if new_capacity <= this.Capacity {
		return
	}

	if this.Data != nil {
		Gui_MemFree(this.Data)
	}

	this.Data = ([^]T)(Gui_MemAlloc(new_capacity * size_of(T)))
	this.Capacity = new_capacity
}

// NB: It is illegal to call push_back/push_front/insert with a reference pointing inside the ImVector data itself! e.g. v.push_back(v[10]) is forbidden.
// inline void         push_back(const T& v)               { if (Size == Capacity) reserve(_grow_capacity(Size + 1)); memcpy(&Data[Size], &v, sizeof(v)); Size++; }
VectorPushBack :: #force_inline proc(this: ^Vector($T), v: T) {
	if this.Size == this.Capacity {
		VectorReserve(this, VectorGrowCap(this, this.Size + 1))
	}

	this.Data[this.Size] = v
	this.Size += 1
}

// inline void         pop_back()                          { IM_ASSERT(Size > 0); Size--; }
VectorPopBack :: #force_inline proc(this: ^Vector($T)) {
	assert(this.Size > 0)
	this.Size -= 1
}

// inline void         push_front(const T& v)              { if (Size == 0) push_back(v); else insert(Data, v); }
VectorPushFront :: #force_inline proc(this: ^Vector($T), v: T) {
	if (this.Size == 0) {
		VectorPushBack(this, v)
	} else {
		VectorInsert(this, &this.Data, v)
	}
}

// inline T*           erase(const T* it)                  { IM_ASSERT(it >= Data && it < Data + Size); const ptrdiff_t off = it - Data; memmove(Data + off, Data + off + 1, ((size_t)Size - (size_t)off - 1) * sizeof(T)); Size--; return Data + off; }
VectorEraseWOLast :: #force_inline proc(this: ^Vector($T), it: ^T) -> ^T {
	assert(uintptr(it) >= uintptr(this.Data) && uintptr(it) < uintptr(this.Data) + uintptr(this.Size))
	off := int(uintptr(it) - uintptr(this.Data)) / size_of(T)
	mem.copy(
		it,
		&this.Data[off + 1],
		(int(this.Size) - off - 1) * size_of(T)
	)
	this.Size -= 1
	return (^T)(&this.Data[off])
}

// inline T*           erase(const T* it, const T* it_last){ IM_ASSERT(it >= Data && it < Data + Size && it_last >= it && it_last <= Data + Size); const ptrdiff_t count = it_last - it; const ptrdiff_t off = it - Data; memmove(Data + off, Data + off + count, ((size_t)Size - (size_t)off - (size_t)count) * sizeof(T)); Size -= (int)count; return Data + off; }
VectorEraseWLast :: #force_inline proc(this: ^Vector($T), it, it_last: ^T) -> ^T {
	assert(
		uintptr(it) >= uintptr(this.Data) && 
		uintptr(it) < uintptr(this.Data) + uintptr(this.Size * size_of(T)) && 
		uintptr(it_last) >= uintptr(it) && 
		uintptr(it_last) <= uintptr(this.Data) + uintptr(this.Size * size_of(T))
	)
	count := int(uintptr(it_last) - uintptr(it)) / size_of(T)
	off := int(uintptr(it) - uintptr(this.Data)) / size_of(T)
	mem.copy(
		it,
		it_last,
		(int(this.Size) - off - count) * size_of(T)
	)
	this.Size -= i32(count)
	return (^T)(&this.Data[off])
}

VectorErase :: proc {
	VectorEraseWOLast,
	VectorEraseWLast,
}

// inline T*           erase_unsorted(const T* it)         { IM_ASSERT(it >= Data && it < Data + Size);  const ptrdiff_t off = it - Data; if (it < Data + Size - 1) memcpy(Data + off, Data + Size - 1, sizeof(T)); Size--; return Data + off; }
VectorEraseUnsorted :: #force_inline proc(this: ^Vector($T), it: ^T) -> ^T {
	assert(uintptr(it) >= uintptr(this.Data) && uintptr(it) < uintptr(this.Data) + uintptr(this.Size))
	off := int(uintptr(it) - uintptr(this.Data)) / size_of(T)
	if uintptr(it) < uintptr(this.Data) + uintptr(this.Size - 1) * size_of(T) {
		it^ = this.Data[this.Size - 1]
	}
	this.Size -= 1
	return (^T)(&this.Data[off])
}

// inline T*           insert(const T* it, const T& v)     { IM_ASSERT(it >= Data && it <= Data + Size); const ptrdiff_t off = it - Data; if (Size == Capacity) reserve(_grow_capacity(Size + 1)); if (off < (int)Size) memmove(Data + off + 1, Data + off, ((size_t)Size - (size_t)off) * sizeof(T)); memcpy(&Data[off], &v, sizeof(v)); Size++; return Data + off; }
VectorInsert :: #force_inline proc(this: ^Vector($T), it: ^T, v: T) -> ^T {
	assert(uintptr(it) >= uintptr(this.Data) && uintptr(it) <= uintptr(this.Data) + uintptr(this.Size * size_of(T)))
	off := int(uintptr(it) - uintptr(this.Data)) / size_of(T)
	if this.Size == this.Capacity {
		VectorReserve(this, VectorGrowCap(this, this.Size + 1))
	}
	if off < this.Size {
		mem.copy(
			&this.Data[off + 1],
			&this.Data[off],
			(this.Size - off) * size_of(T)
		)
	}
	this.Data[off] = v
	this.Size += 1
	return (^T)(&this.Data[off])
}

// inline bool         contains(const T& v) const          { const T* data = Data;  const T* data_end = Data + Size; while (data < data_end) if (*data++ == v) return true; return false; }
VectorContains :: #force_inline proc(this: Vector($T), v: T) -> bool {
	for &entry in this.Data[:this.Size] {
		if entry == v {
			return true
		}
	}
	return false
}

// inline T*           find(const T& v)                    { T* data = Data;  const T* data_end = Data + Size; while (data < data_end) if (*data == v) break; else ++data; return data; }
// inline const T*     find(const T& v) const              { const T* data = Data;  const T* data_end = Data + Size; while (data < data_end) if (*data == v) break; else ++data; return data; }
VectorFind :: #force_inline proc(this: Vector($T), v: T) -> ^T {
	idx := VectorFindIndex(this, v)
	if idx == -1 {
		// I did this to mirror the c++ behaviour but maybe we should return nil instead.
		// This might cause a read access violation, I'm not sure.
		// If it does replace with:
		// return (^T)(uintptr(this.Data) + uintptr((this.Size + 1) * size_of(T)))
		return &this.Data[this.Size + 1]
	}
	return &this.Data[idx]
}

// inline int          find_index(const T& v) const        { const T* data_end = Data + Size; const T* it = find(v); if (it == data_end) return -1; const ptrdiff_t off = it - Data; return (int)off; }
VectorFindIndex :: #force_inline proc(this: Vector($T), v: T) -> int {
	for &entry, idx in this.Data[:this.Size] {
		if entry == v {
			return idx
		}
	}
	return -1
}

// inline bool         find_erase(const T& v)              { const T* it = find(v); if (it < Data + Size) { erase(it); return true; } return false; }
VectorFindErase :: #force_inline proc(this: ^Vector($T), v: T) -> bool {
	it_idx := VectorFindIndex(this^, v)
	if it_idx != -1 {
		VectorErase(this, &this.Data[it_idx])
		return true
	}
	return false
}

// inline bool         find_erase_unsorted(const T& v)     { const T* it = find(v); if (it < Data + Size) { erase_unsorted(it); return true; } return false; }
VectorFindEraseUnsorted :: #force_inline proc(this: ^Vector($T), v: T) -> bool {
	it_idx := VectorFindIndex(this^, v)
	if it_idx != -1 {
		VectorEraseUnsorted(this, &this.Data[it_idx])
		return true
	}
	return false
}

// inline int          index_from_ptr(const T* it) const   { IM_ASSERT(it >= Data && it < Data + Size); const ptrdiff_t off = it - Data; return (int)off; }
VectorIndexFromPtr :: #force_inline proc(this: Vector($T), it: ^T) -> int {
	assert(uintptr(it) >= uintptr(this.Data) && uintptr(it) < uintptr(this.Data) + uintptr(this.Size))
	return int(uintptr(it) - uintptr(this.Data)) / size_of(T)
}

