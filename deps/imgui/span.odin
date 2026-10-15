package ImGui


Span :: struct($T: typeid) {
	Data:    ^T,
	DataEnd: ^T,
}

// inline ImSpan()                                 { Data = DataEnd = NULL; }
NewSpanZero :: #force_inline proc($T: typeid) -> Span(T) {
	return {}
}

// inline ImSpan(T* data, int size)                { Data = data; DataEnd = data + size; }
NewSpanFromDataAndSize :: #force_inline proc(data: ^$T, size: i32) -> Span(T) {
	span: Span(T)
	span.Data = data
	span.DataEnd = (^T)(uintptr(data) + uintptr(size) * size_of(T))
	return span
}

// inline ImSpan(T* data, T* data_end)             { Data = data; DataEnd = data_end; }
NewSpanStartAndEnd :: #force_inline proc(data: ^$T, dataEnd: ^T) -> Span(T) {
	span: Span(T)
	span.Data = data
	span.DataEnd = dataEnd
	return span
}

NewSpan :: proc{
	NewSpanZero,
	NewSpanFromDataAndSize,
	NewSpanStartAndEnd,
}

// inline void         set(T* data, int size)      { Data = data; DataEnd = data + size; }
SpanSet :: #force_inline proc(span: ^Span($T), data: ^T, size: i32) {
	span.Data = data
	span.DataEnd = (^T)(uintptr(data) + uintptr(size) * size_of(T))
}

// inline void         set(T* data, T* data_end)   { Data = data; DataEnd = data_end; }
// Just access the fields and set them.

// inline int          size() const                { return (int)(ptrdiff_t)(DataEnd - Data); }
SpanSize :: #force_inline proc(span: Span($T)) -> i32 {
	return SpanSizeInBytes(span) / size_of(T)
}

// inline int          size_in_bytes() const       { return (int)(ptrdiff_t)(DataEnd - Data) * (int)sizeof(T); }
SpanSizeInBytes :: #force_inline proc(span: Span($T)) -> i32 {
	return i32(uintptr(span.DataEnd) - uintptr(span.Data))
}

// inline T&           operator[](int i)           { T* p = Data + i; IM_ASSERT(p >= Data && p < DataEnd); return *p; }
// inline const T&     operator[](int i) const     { const T* p = Data + i; IM_ASSERT(p >= Data && p < DataEnd); return *p; }
SpanIndex :: #force_inline proc(span: Span($T), #any_int i: int) -> ^T {
	ptr := uintptr(span.Data) + uintptr(i * size_of(T))
	assert(ptr >= uintptr(span.Data) && ptr < uintptr(span.DataEnd))
	return (^T)(ptr)
}

// I'm not going to do these ones. Just access the data directly
// inline T*           begin()                     { return Data; }
// inline const T*     begin() const               { return Data; }
// inline T*           end()                       { return DataEnd; }
// inline const T*     end() const                 { return DataEnd; }

// Utilities
// inline int  index_from_ptr(const T* it) const   { IM_ASSERT(it >= Data && it < DataEnd); const ptrdiff_t off = it - Data; return (int)off; }
SpanIndexFromPtr :: #force_inline proc(span: ^Span($T), it: ^T) -> i32 {
	assert(uintptr(it) >= uintptr(span.Data) && uintptr(it) < uintptr(span.DataEnd))
	off := i32(uintptr(it) - uintptr(span.Data)) / size_of(T)
	return off
}

