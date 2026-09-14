package RefDisk

import "base:runtime"
import "core:os"
import "core:reflect"

load :: proc(fp: ^os.File, $T: typeid, allocator := context.allocator) -> T {
	val: T
	load_internal(fp, any{&val, typeid_of(T)}, allocator)
	return val
}

load_internal :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	if value.id == nil do return

	ti := runtime.type_info_base(type_info_of(value.id))
	if is_type_plain(ti) {
		os.read_ptr(fp, value.data, ti.size)
		return
	}

	#partial switch reflect.type_kind(value.id) {
	case .Named:
		load_internal(fp, any{value.data, reflect.typeid_base(value.id)}, allocator)
	case .Struct:
		load_struct(fp, value, allocator)
	case .String:
		load_string(fp, value, allocator)
	case .Dynamic_Array:
		load_dynamic_array(fp, value, allocator)
	case .Slice:
		load_slice(fp, value, allocator)
	case .Array:
		load_array(fp, value, allocator)
	case .Enumerated_Array:
		load_enumerated_array(fp, value, allocator)
	case .Fixed_Capacity_Dynamic_Array:
		load_fixed_capacity_dynamic_array(fp, value, allocator)
	case .Union:
		load_union(fp, value, allocator)
	case .Map:
		load_map(fp, value, allocator)
	case .Pointer:
		load_pointer(fp, value, allocator)
	case .Any:
		load_any(fp, value, allocator)
	case .Type_Id:
		os.read_ptr(fp, value.data, size_of(typeid))
	case:
		os.read_ptr(fp, value.data, ti.size)
	}
}

@(private)
load_struct :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	bytes := ([^]byte)(value.data)
	for &field in reflect.struct_fields_zipped(value.id) {
		if should_skip_field(field.tag) {
			continue
		}
		load_internal(fp, any{&bytes[field.offset], field.type.id}, allocator)
	}
}

@(private)
load_string :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	switch value.id {
	case string:
		length: u32
		os.read_ptr(fp, &length, size_of(u32))
		if length > 0 {
			bytes := make([]byte, length, allocator)
			os.read(fp, bytes)
			(^string)(value.data)^ = string(bytes)
		} else {
			(^string)(value.data)^ = ""
		}
	case cstring:
		length: u32
		os.read_ptr(fp, &length, size_of(u32))
		if length > 0 {
			bytes := make([]byte, length + 1, allocator)
			os.read(fp, bytes[:length])
			bytes[length] = 0
			(^cstring)(value.data)^ = cstring(raw_data(bytes))
		} else {
			(^cstring)(value.data)^ = ""
		}
	case:
		length: u32
		os.read_ptr(fp, &length, size_of(u32))
		if length > 0 {
			bytes := make([]byte, length, allocator)
			os.read(fp, bytes)
			(^string)(value.data)^ = string(bytes)
		} else {
			(^string)(value.data)^ = ""
		}
	}
}

@(private)
load_dynamic_array :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	ti := runtime.type_info_base(type_info_of(value.id))
	array_info := ti.variant.(runtime.Type_Info_Dynamic_Array)
	count: u32
	os.read_ptr(fp, &count, size_of(u32))
	if count == 0 {
		(^runtime.Raw_Dynamic_Array)(value.data)^ = runtime.Raw_Dynamic_Array{
			allocator = allocator,
		}
	} else {
		elem_info := runtime.type_info_base(array_info.elem)
		context.allocator = allocator
		runtime.__dynamic_array_make(value.data, array_info.elem_size, array_info.elem.align, int(count), int(count))
		raw_array := (^runtime.Raw_Dynamic_Array)(value.data)
		if is_type_plain(elem_info) {
			os.read_ptr(fp, raw_array.data, int(count) * array_info.elem_size)
		} else {
			runtime.mem_zero(raw_array.data, int(count) * array_info.elem_size)
			bytes := ([^]byte)(raw_array.data)
			for idx in 0..<int(count) {
				load_internal(fp, any{&bytes[idx * array_info.elem_size], array_info.elem.id}, allocator)
			}
		}
	}
}

@(private)
load_slice :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	ti := runtime.type_info_base(type_info_of(value.id))
	slice_info := ti.variant.(runtime.Type_Info_Slice)
	count: u32
	os.read_ptr(fp, &count, size_of(u32))
	if count == 0 {
		(^runtime.Raw_Slice)(value.data)^ = runtime.Raw_Slice{}
	} else {
		elem_info := runtime.type_info_base(slice_info.elem)
		total_bytes := int(count) * slice_info.elem_size
		data, err := runtime.mem_alloc(total_bytes, slice_info.elem.align, allocator)
		if err == nil {
			raw_slice := (^runtime.Raw_Slice)(value.data)
			raw_slice.data = raw_data(data)
			raw_slice.len = int(count)
			if is_type_plain(elem_info) {
				os.read_ptr(fp, raw_slice.data, total_bytes)
			} else {
				runtime.mem_zero(raw_slice.data, total_bytes)
				bytes := ([^]byte)(raw_slice.data)
				for idx in 0..<int(count) {
					load_internal(fp, any{&bytes[idx * slice_info.elem_size], slice_info.elem.id}, allocator)
				}
			}
		}
	}
}

@(private)
load_array :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	ti := runtime.type_info_base(type_info_of(value.id))
	array_info := ti.variant.(runtime.Type_Info_Array)
	elem_info := runtime.type_info_base(array_info.elem)
	if is_type_plain(elem_info) {
		os.read_ptr(fp, value.data, ti.size)
	} else {
		bytes := ([^]byte)(value.data)
		for idx in 0..<array_info.count {
			load_internal(fp, any{&bytes[idx * array_info.elem_size], array_info.elem.id}, allocator)
		}
	}
}

@(private)
load_enumerated_array :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	ti := runtime.type_info_base(type_info_of(value.id))
	array_info := ti.variant.(runtime.Type_Info_Enumerated_Array)
	elem_info := runtime.type_info_base(array_info.elem)
	if is_type_plain(elem_info) {
		os.read_ptr(fp, value.data, ti.size)
	} else {
		bytes := ([^]byte)(value.data)
		for idx in 0..<array_info.count {
			load_internal(fp, any{&bytes[idx * array_info.elem_size], array_info.elem.id}, allocator)
		}
	}
}

@(private)
load_fixed_capacity_dynamic_array :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	ti := runtime.type_info_base(type_info_of(value.id))
	info := ti.variant.(runtime.Type_Info_Fixed_Capacity_Dynamic_Array)
	count: u32
	os.read_ptr(fp, &count, size_of(u32))
	count = min(count, u32(info.capacity))
	len_ptr := (^int)(uintptr(value.data) + info.len_offset)
	len_ptr^ = int(count)
	if count > 0 {
		elem_info := runtime.type_info_base(info.elem)
		if is_type_plain(elem_info) {
			os.read_ptr(fp, value.data, int(count) * info.elem_size)
		} else {
			bytes := ([^]byte)(value.data)
			for idx in 0..<int(count) {
				load_internal(fp, any{&bytes[idx * info.elem_size], info.elem.id}, allocator)
			}
		}
	}
}

@(private)
load_union :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	tag_i64: i64
	os.read_ptr(fp, &tag_i64, size_of(i64))

	ti := runtime.type_info_base(type_info_of(value.id))
	union_info := ti.variant.(runtime.Type_Info_Union)

	runtime.mem_zero(value.data, ti.size)

	if !union_info.no_nil && tag_i64 == 0 {
		return
	}

	idx := int(tag_i64) if union_info.no_nil else int(tag_i64 - 1)
	if idx >= 0 && idx < len(union_info.variants) {
		reflect.set_union_variant_raw_tag(value, tag_i64)
		variant_info := union_info.variants[idx]
		load_internal(fp, any{value.data, variant_info.id}, allocator)
	}
}

@(private)
load_map :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	ti := runtime.type_info_base(type_info_of(value.id))
	map_info := ti.variant.(runtime.Type_Info_Map)
	rm := (^runtime.Raw_Map)(value.data)
	count: u32
	os.read_ptr(fp, &count, size_of(u32))
	rm.allocator = allocator
	if count > 0 {
		_ = runtime.map_reserve_dynamic(rm, map_info.map_info, uintptr(count))
		key_size := map_info.key.size
		val_size := map_info.value.size
		key_buf, _ := runtime.mem_alloc(key_size, map_info.key.align, context.temp_allocator)
		val_buf, _ := runtime.mem_alloc(val_size, map_info.value.align, context.temp_allocator)
		key_ptr := raw_data(key_buf)
		val_ptr := raw_data(val_buf)
		for _ in 0..<count {
			runtime.mem_zero(key_ptr, key_size)
			runtime.mem_zero(val_ptr, val_size)
			load_internal(fp, any{key_ptr, map_info.key.id}, allocator)
			load_internal(fp, any{val_ptr, map_info.value.id}, allocator)
			hash := map_info.map_info.key_hasher(key_ptr, runtime.map_seed(rm^))
			_ = runtime.map_insert_hash_dynamic(rm, map_info.map_info, hash, uintptr(key_ptr), uintptr(val_ptr))
			rm.len += 1
		}
	}
}

@(private)
load_pointer :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	flag: u8
	os.read_ptr(fp, &flag, size_of(u8))
	if flag == 0 {
		(^rawptr)(value.data)^ = nil
	} else {
		ti := runtime.type_info_base(type_info_of(value.id))
		ptr_info := ti.variant.(runtime.Type_Info_Pointer)
		if ptr_info.elem != nil {
			elem_info := runtime.type_info_base(ptr_info.elem)
			elem_mem, err := runtime.mem_alloc(elem_info.size, elem_info.align, allocator)
			if err == nil {
				elem_ptr := raw_data(elem_mem)
				runtime.mem_zero(elem_ptr, elem_info.size)
				(^rawptr)(value.data)^ = elem_ptr
				load_internal(fp, any{elem_ptr, ptr_info.elem.id}, allocator)
			}
		}
	}
}

@(private)
load_any :: proc(fp: ^os.File, value: any, allocator: runtime.Allocator) {
	type_val: typeid
	os.read_ptr(fp, &type_val, size_of(typeid))
	if type_val == nil {
		(^any)(value.data)^ = any{}
	} else {
		ti_inner := runtime.type_info_base(type_info_of(type_val))
		mem_inner, err := runtime.mem_alloc(ti_inner.size, ti_inner.align, allocator)
		if err == nil {
			inner_ptr := raw_data(mem_inner)
			runtime.mem_zero(inner_ptr, ti_inner.size)
			load_internal(fp, any{inner_ptr, type_val}, allocator)
			(^any)(value.data)^ = any{inner_ptr, type_val}
		}
	}
}
