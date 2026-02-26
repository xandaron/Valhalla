package ImGui


Pool :: struct($T: typeid) {
	Buf:        Vector(T),
	Map:        GuiStorage,
	FreeIdx:    PoolIdx,
	AliveCount: PoolIdx,
}

// ImPool()    { FreeIdx = AliveCount = 0; }
// Just initalize the var normally

// ~ImPool()   { Clear(); }
PoolDestroy :: #force_inline proc(this: ^Pool($T)) {
	PoolClear(this)
}

// T*          GetByKey(ImGuiID key)               { int idx = Map.GetInt(key, -1); return (idx != -1) ? &Buf[idx] : NULL; }
PoolGetByKey :: #force_inline proc(this: Pool($T), key: GuiID) -> ^T {
	idx := GuiStorage_GetInt(&this.Map, key, -1)
	return idx != -1 ? &this.Buf.Data[idx] : nil
}

// T*          GetByIndex(ImPoolIdx n)             { return &Buf[n]; }
PoolGetByIndex :: #force_inline proc(this: Pool($T), n: PoolIdx) -> ^T {
	return &this.Buf.Data[n]
}

// ImPoolIdx   GetIndex(const T* p) const          { IM_ASSERT(p >= Buf.Data && p < Buf.Data + Buf.Size); return (ImPoolIdx)(p - Buf.Data); }
PoolGetIndex :: #force_inline proc(this: ^Pool($T), p: ^T) -> PoolIdx {
	assert(uintptr(p) >= uintptr(this.Buf.Data) && uintptr(p) < uintptr(this.Buf.Data) + uintptr(this.Buf.Size))
	return PoolIdx(uintptr(p) - uintptr(this.Buf.Data)) / size_of(T)
}

// T*          GetOrAddByKey(ImGuiID key)          { int* p_idx = Map.GetIntRef(key, -1); if (*p_idx != -1) return &Buf[*p_idx]; *p_idx = FreeIdx; return Add(); }
PoolGetOrAddByKey :: #force_inline proc(this: ^Pool($T), key: GuiID) -> ^T {
	p_idx := GuiStorage_GetIntRef(&this.Map, key, -1)
	if p_idx^ != -1 {
		return &this.Buf.Data[p_idx^]
	}
	p_idx^ = this.FreeIdx
	return PoolAdd(this)
}

// bool        Contains(const T* p) const          { return (p >= Buf.Data && p < Buf.Data + Buf.Size); }
PoolContains :: #force_inline proc(this: ^Pool($T), p: ^T) -> bool {
	return uintptr(p) >= uintptr(this.Buf.Data) && uintptr(p) < uintptr(this.Buf.Data) + uintptr(this.Buf.Size * size_of(T))
}

// void        Clear()                             { for (int n = 0; n < Map.Data.Size; n++) { int idx = Map.Data[n].val_i; if (idx != -1) Buf[idx].~T(); } Map.Clear(); Buf.clear(); FreeIdx = AliveCount = 0; }
// We don't have type destructors so I'm not really sure what to do here.
PoolClear :: #force_inline proc(this: ^Pool($T)) {
	for n := 0; n < this.Map.Data.Size; n += 1 {
		idx := this.Map.Data[n].val_i
		if idx != -1 {
			// We dont have destructors...
			// this.Buf.Data[idx].~T()
		}
	}

	GuiStorage_Clear(&this.Map)
	VectorClear(&this.Buf)
	this.FreeIdx = 0
	this.AliveCount = 0
}

// T*          Add()                               { int idx = FreeIdx; if (idx == Buf.Size) { Buf.resize(Buf.Size + 1); FreeIdx++; } else { FreeIdx = *(int*)&Buf[idx]; } IM_PLACEMENT_NEW(&Buf[idx]) T(); AliveCount++; return &Buf[idx]; }
PoolAdd :: #force_inline proc(this: ^Pool($T)) -> ^T {
	idx := this.FreeIdx
	if idx == this.Buf.Size {
		VectorResize(&this.Buf, this.Buf.Size + 1)
		this.FreeIdx += 1
	} else {
		this.FreeIdx = (^i32)(&this.Buf.Data[idx])^
	}
	this.Buf.Data[idx] = {}
	this.AliveCount += 1
	return &this.Buf.Data[idx]
}

// void        Remove(ImGuiID key, const T* p)     { Remove(key, GetIndex(p)); }
PoolRemovePointer :: #force_inline proc(this: ^Pool($T), key: GuiID, p: ^T) {
	PoolRemoveIndex(this, key, PoolGetIndex(this, p))
}

// void        Remove(ImGuiID key, ImPoolIdx idx)  { Buf[idx].~T(); *(int*)&Buf[idx] = FreeIdx; FreeIdx = idx; Map.SetInt(key, -1); AliveCount--; }
PoolRemoveIndex :: #force_inline proc(this: ^Pool($T), key: GuiID, idx: PoolIdx) {
	// Again we don't have destructors...
	// this.Buf.Data[idx].~T()
	(^i32)(&this.Buf.Data[idx])^ = this.FreeIdx
	this.FreeIdx = idx
	GuiStorage_SetInt(&this.Map, key, -1)
	this.AliveCount -= 1
}

// void        Reserve(int capacity)               { Buf.reserve(capacity); Map.Data.reserve(capacity); }
PoolReserve :: #force_inline proc(this: Pool($T), #any_int capacity: int) {
	VectorReserve(&this.Buf, capacity)
	VectorReserve(&this.Map.Data, capacity)
}

// To iterate a ImPool: for (int n = 0; n < pool.GetMapSize(); n++) if (T* t = pool.TryGetMapData(n)) { ... }
// Can be avoided if you know .Remove() has never been called on the pool, or AliveCount == GetMapSize()
// int         GetAliveCount() const               { return AliveCount; }      // Number of active/alive items in the pool (for display purpose)
// int         GetBufSize() const                  { return Buf.Size; }
// int         GetMapSize() const                  { return Map.Data.Size; }   // It is the map we need iterate to find valid items, since we don't have "alive" storage anywhere
// Just access the data fields directly

// T*          TryGetMapData(ImPoolIdx n)          { int idx = Map.Data[n].val_i; if (idx == -1) return NULL; return GetByIndex(idx); }
PoolTryGetMapData :: #force_inline proc(this: Pool($T), n: PoolIdx) -> ^T {
	idx := this.Map.Data[n].val_i
	if idx == -1 {
		return nil
	}
	return PoolGetByIndex(this, idx)
}

