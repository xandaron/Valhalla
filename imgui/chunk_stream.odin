package ImGui


ChunkStream :: struct($T: typeid) {
	Buf: Vector(byte),
}

// void    clear()                     { Buf.clear(); }
ChunkStreamClear :: #force_inline proc(this: ^ChunkStream($T)) {
	VectorClear(&this.Buf)
}

// bool    empty() const               { return Buf.Size == 0; }
ChunkStreamEmpty :: #force_inline proc(this: ChunkStream($T)) -> bool {
	return this.Buf.Size == 0
}

// int     size() const                { return Buf.Size; }
ChunkStreamSize :: #force_inline proc(this: ChunkStream($T)) -> int {
	return int(this.Buf.Size)
}

// T*      alloc_chunk(size_t sz)      { size_t HDR_SZ = 4; sz = IM_MEMALIGN(HDR_SZ + sz, 4u); int off = Buf.Size; Buf.resize(off + (int)sz); ((int*)(void*)(Buf.Data + off))[0] = (int)sz; return (T*)(void*)(Buf.Data + off + (int)HDR_SZ); }
ChunkStreamAllocChunk :: #force_inline proc(this: ^ChunkStream($T), #any_int sz: int) -> ^T {
	HDR_SZ :: size_of(i32)
	sz := (HDR_SZ + sz + 3) & int(~u32(3))
	off := this.Buf.Size
	VectorResize(&this.Buf, int(off) + sz)
	// ((int*)(void*)(Buf.Data + off))[0] = (int)sz
	(^i32)(&this.Buf.Data[off])^ = i32(sz)
	return (^T)(uintptr(&this.Buf.Data[off]) + uintptr(HDR_SZ))
}

// T*      begin()                     { size_t HDR_SZ = 4; if (!Buf.Data) return NULL; return (T*)(void*)(Buf.Data + HDR_SZ); }
ChunkStreamBegin :: #force_inline proc(this: ChunkStream($T)) -> ^T {
	HDR_SZ :: size_of(i32)
	if this.Buf.Data == nil {
		return nil
	}
	return (^T)(uintptr(this.Buf.Data) + uintptr(HDR_SZ))
}

// T*      next_chunk(T* p)            { size_t HDR_SZ = 4; IM_ASSERT(p >= begin() && p < end()); p = (T*)(void*)((char*)(void*)p + chunk_size(p)); if (p == (T*)(void*)((char*)end() + HDR_SZ)) return (T*)0; IM_ASSERT(p < end()); return p; }
ChunkStreamNextChunk :: #force_inline proc(this: ChunkStream($T), p: ^T) -> ^T {
	HDR_SZ :: size_of(i32)
	assert(uintptr(p) >= uintptr(ChunkStreamBegin(this)) && uintptr(p) < uintptr(ChunkStreamEnd(this)))
	p := (^T)(uintptr(p) + uintptr(ChunkStreamChunkSize(p)))
	if p == (^T)(uintptr(ChunkStreamEnd(this)) + uintptr(HDR_SZ)) {
		return nil
	}
	assert(uintptr(p) < uintptr(ChunkStreamEnd(this)))
	return p
}

// int     chunk_size(const T* p)      { return ((const int*)p)[-1]; }
ChunkStreamChunkSize :: #force_inline proc(p: ^$T) -> int {
	return (^i32)(uintptr(p) - uintptr(size_of(i32)))^
}

// T*      end()                       { return (T*)(void*)(Buf.Data + Buf.Size); }
ChunkStreamEnd :: #force_inline proc(this: ChunkStream($T)) -> ^T {
	return (^T)(&this.Buf.Data[this.Buf.Size])
}

// int     offset_from_ptr(const T* p) { IM_ASSERT(p >= begin() && p < end()); const ptrdiff_t off = (const char*)p - Buf.Data; return (int)off; }
ChunkStreamOffsetFromPtr :: #force_inline proc(this: ChunkStream($T), p: ^T) -> int {
	assert(uintptr(p) >= uintptr(ChunkStreamBegin(this)) && uintptr(p) < uintptr(ChunkStreamEnd(this)))
	off := uintptr(p) - uintptr(this.Buf.Data)
	return int(off)
}

// T*      ptr_from_offset(int off)    { IM_ASSERT(off >= 4 && off < Buf.Size); return (T*)(void*)(Buf.Data + off); }
ChunkStreamPtrFromOffset :: #force_inline proc(this: ChunkStream($T), #any_int off: int) -> ^T {
	assert(off >= 4 && off < int(this.Buf.Size))
	return (^T)(uintptr(this.Buf.Data) + uintptr(off))
}

// void    swap(ImChunkStream<T>& rhs) { rhs.Buf.swap(Buf); }
ChunkStreamSwap :: #force_inline proc(lhs, rhs: ^ChunkStream($T)) {
	VectorSwap(&lhs.Buf, &rhs.Buf)
}

