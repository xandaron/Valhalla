package ImGui


StableVector :: struct($T: typeid, $BLOCKSIZE: i32) {
	Size:     i32,
	Capacity: i32,
	Blocks:   Vector(^[BLOCKSIZE]T),
}

// inline ~ImStableVector()                        { for (T* block : Blocks) IM_FREE(block); }
StableVectorDestroy :: #force_inline proc(this: StableVector($T, $BLOCKSIZE)) {
	for &block in this.Blocks.Data[:this.Blocks.Size] {
		GuiMemFree(block)
	}
}

// inline void         clear()                     { Size = Capacity = 0; Blocks.clear_delete(); }
StableVectorClear :: #force_inline proc(this: ^StableVector($T, $BLOCKSIZE)) {
	this.Size = 0
	this.Capacity = 0
	VectorClearDelete(&this.Blocks)
}

// inline void         resize(int new_size)        { if (new_size > Capacity) reserve(new_size); Size = new_size; }
StableVectorResize :: #force_inline proc(this: ^StableVector($T, $BLOCKSIZE), #any_int new_size: int) {
	if i32(new_size) > this.Size {
		StableVectorReserve(this, new_size)
	}
	this.Size = new_size
}

// inline void         reserve(int new_cap)
// {
//     new_cap = IM_MEMALIGN(new_cap, BLOCKSIZE);
//     int old_count = Capacity / BLOCKSIZE;
//     int new_count = new_cap / BLOCKSIZE;
//     if (new_count <= old_count)
//         return;
//     Blocks.resize(new_count);
//     for (int n = old_count; n < new_count; n++)
//         Blocks[n] = (T*)IM_ALLOC(sizeof(T) * BLOCKSIZE);
//     Capacity = new_cap;
// }
StableVectorReserve :: #force_inline proc(this: ^StableVector($T, $BLOCKSIZE), #any_int new_cap: int) {
	new_cap := (new_cap + (BLOCKSIZE - 1)) & ~(BLOCKSIZE - 1)
	old_count := int(this.Capacity) / BLOCKSIZE
	new_count := new_cap / BLOCKSIZE
	if new_count <= old_count {
		return
	}
	VectorResize(&this.Blocks, new_count)
	for n := old_count; n < new_count; n += 1 {
		this.Blocks[n] = (^T[BLOCKSIZE])(Gui_MemAlloc(size_of(T) * BLOCKSIZE))
	}
	this.Capacity = i32(new_cap)
}

// inline T&           operator[](int i)           { IM_ASSERT(i >= 0 && i < Size); return Blocks[i / BLOCKSIZE][i % BLOCKSIZE]; }
// inline const T&     operator[](int i) const     { IM_ASSERT(i >= 0 && i < Size); return Blocks[i / BLOCKSIZE][i % BLOCKSIZE]; }
StableVectorIndex :: #force_inline proc(this: StableVector($T, $BLOCKSIZE), i: int) -> ^T {
	assert(i >= 0 && i < this.Size)
	return Blocks[i / BLOCKSIZE][i % BLOCKSIZE];
}

// inline T*           push_back(const T& v)       { int i = Size; IM_ASSERT(i >= 0); if (Size == Capacity) reserve(Capacity + BLOCKSIZE); void* ptr = &Blocks[i / BLOCKSIZE][i % BLOCKSIZE]; memcpy(ptr, &v, sizeof(v)); Size++; return (T*)ptr; }
StableVectorPushBack :: #force_inline proc(this: ^StableVector($T, $BLOCKSIZE), v: T) -> ^T {
	i := this.Size
	assert(i >= 0)
	if (this.Size == this.Capacity) {
		StableVectorReserve(this, int(this.Capacity) + BLOCKSIZE)
	}
	ptr := &this.Blocks.Data[i / BLOCKSIZE][i % BLOCKSIZE]
	// memcpy(ptr, &v, sizeof(v))
	ptr^ = v
	this.Size += 1
	return ptr
}

