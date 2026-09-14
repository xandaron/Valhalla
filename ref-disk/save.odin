package RefDisk

import "base:runtime"
import "core:os"
import "core:reflect"

// Serializes arbitrary data to disk using reflection.
// Arrays and strings are handled using length-prefixed binary layouts matching src/Files.odin.
save :: proc(fp: ^os.File, data: any) {
	assert(fp != nil)
	save_internal(fp, data)
	os.flush(fp)
}

save_internal :: proc(fp: ^os.File, value: any) {
	if value.id == nil do return

	ti := runtime.type_info_base(type_info_of(value.id))
	if is_type_plain(ti) {
		os.write_ptr(fp, value.data, ti.size)
		return
	}

	#partial switch reflect.type_kind(value.id) {
	case .Named:
		save_internal(fp, any{value.data, reflect.typeid_base(value.id)})
	case .Struct:
		save_struct(fp, value)
	case .String:
		save_string(fp, value)
	case .Dynamic_Array:
		save_dynamic_array(fp, value)
	case .Slice:
		save_slice(fp, value)
	case .Array:
		save_array(fp, value)
	case .Enumerated_Array:
		save_enumerated_array(fp, value)
	case .Fixed_Capacity_Dynamic_Array:
		save_fixed_capacity_dynamic_array(fp, value)
	case .Union:
		save_union(fp, value)
	case .Map:
		save_map(fp, value)
	case .Pointer:
		save_pointer(fp, value)
	case .Any:
		save_any(fp, value)
	case .Type_Id:
		os.write_ptr(fp, value.data, size_of(typeid))
	case:
		os.write_ptr(fp, value.data, ti.size)
	}
}

@(private)
save_struct :: proc(fp: ^os.File, value: any) {
	bytes := ([^]byte)(value.data)
	for &field in reflect.struct_fields_zipped(value.id) {
		if should_skip_field(field.tag) {
			continue
		}
		save_internal(fp, any{&bytes[field.offset], field.type.id})
	}
}

@(private)
save_string :: proc(fp: ^os.File, value: any) {
	switch value.id {
	case string:
		str := (^string)(value.data)^
		length := u32(len(str))
		os.write_ptr(fp, &length, size_of(u32))
		if length > 0 {
			os.write_string(fp, str)
		}
	case cstring:
		cstr := (^cstring)(value.data)^
		str := string(cstr)
		length := u32(len(str))
		os.write_ptr(fp, &length, size_of(u32))
		if length > 0 {
			os.write_string(fp, str)
		}
	case:
		str := (^string)(value.data)^
		length := u32(len(str))
		os.write_ptr(fp, &length, size_of(u32))
		if length > 0 {
			os.write_string(fp, str)
		}
	}
}

@(private)
save_dynamic_array :: proc(fp: ^os.File, value: any) {
	ti := runtime.type_info_base(type_info_of(value.id))
	array_info := ti.variant.(runtime.Type_Info_Dynamic_Array)
	raw_array := (^runtime.Raw_Dynamic_Array)(value.data)
	count := u32(raw_array.len)
	os.write_ptr(fp, &count, size_of(u32))
	if count > 0 {
		elem_info := runtime.type_info_base(array_info.elem)
		if is_type_plain(elem_info) {
			os.write_ptr(fp, raw_array.data, int(count) * array_info.elem_size)
		} else {
			bytes := ([^]byte)(raw_array.data)
			for idx in 0..<int(count) {
				save_internal(fp, any{&bytes[idx * array_info.elem_size], array_info.elem.id})
			}
		}
	}
}

@(private)
save_slice :: proc(fp: ^os.File, value: any) {
	ti := runtime.type_info_base(type_info_of(value.id))
	slice_info := ti.variant.(runtime.Type_Info_Slice)
	raw_slice := (^runtime.Raw_Slice)(value.data)
	count := u32(raw_slice.len)
	os.write_ptr(fp, &count, size_of(u32))
	if count > 0 {
		elem_info := runtime.type_info_base(slice_info.elem)
		if is_type_plain(elem_info) {
			os.write_ptr(fp, raw_slice.data, int(count) * slice_info.elem_size)
		} else {
			bytes := ([^]byte)(raw_slice.data)
			for idx in 0..<int(count) {
				save_internal(fp, any{&bytes[idx * slice_info.elem_size], slice_info.elem.id})
			}
		}
	}
}

@(private)
save_array :: proc(fp: ^os.File, value: any) {
	ti := runtime.type_info_base(type_info_of(value.id))
	array_info := ti.variant.(runtime.Type_Info_Array)
	elem_info := runtime.type_info_base(array_info.elem)
	if is_type_plain(elem_info) {
		os.write_ptr(fp, value.data, ti.size)
	} else {
		bytes := ([^]byte)(value.data)
		for idx in 0..<array_info.count {
			save_internal(fp, any{&bytes[idx * array_info.elem_size], array_info.elem.id})
		}
	}
}

@(private)
save_enumerated_array :: proc(fp: ^os.File, value: any) {
	ti := runtime.type_info_base(type_info_of(value.id))
	array_info := ti.variant.(runtime.Type_Info_Enumerated_Array)
	elem_info := runtime.type_info_base(array_info.elem)
	if is_type_plain(elem_info) {
		os.write_ptr(fp, value.data, ti.size)
	} else {
		bytes := ([^]byte)(value.data)
		for idx in 0..<array_info.count {
			save_internal(fp, any{&bytes[idx * array_info.elem_size], array_info.elem.id})
		}
	}
}

@(private)
save_fixed_capacity_dynamic_array :: proc(fp: ^os.File, value: any) {
	ti := runtime.type_info_base(type_info_of(value.id))
	info := ti.variant.(runtime.Type_Info_Fixed_Capacity_Dynamic_Array)
	len_ptr := (^int)(uintptr(value.data) + info.len_offset)
	count := u32(len_ptr^)
	os.write_ptr(fp, &count, size_of(u32))
	if count > 0 {
		elem_info := runtime.type_info_base(info.elem)
		if is_type_plain(elem_info) {
			os.write_ptr(fp, value.data, int(count) * info.elem_size)
		} else {
			bytes := ([^]byte)(value.data)
			for idx in 0..<int(count) {
				save_internal(fp, any{&bytes[idx * info.elem_size], info.elem.id})
			}
		}
	}
}

@(private)
save_union :: proc(fp: ^os.File, value: any) {
	tag := reflect.get_union_variant_raw_tag(value)
	tag_i64 := i64(tag)
	os.write_ptr(fp, &tag_i64, size_of(i64))

	ti := runtime.type_info_base(type_info_of(value.id))
	union_info := ti.variant.(runtime.Type_Info_Union)

	if !union_info.no_nil && tag_i64 == 0 {
		return
	}

	idx := int(tag_i64) if union_info.no_nil else int(tag_i64 - 1)
	if idx >= 0 && idx < len(union_info.variants) {
		variant_info := union_info.variants[idx]
		save_internal(fp, any{value.data, variant_info.id})
	}
}

@(private)
save_map :: proc(fp: ^os.File, value: any) {
	rm := (^runtime.Raw_Map)(value.data)
	count := u32(runtime.map_len(rm^))
	os.write_ptr(fp, &count, size_of(u32))
	if count > 0 {
		it: int = 0
		for {
			key, val, ok := reflect.iterate_map(value, &it)
			if !ok do break
			save_internal(fp, key)
			save_internal(fp, val)
		}
	}
}

@(private)
save_pointer :: proc(fp: ^os.File, value: any) {
	ptr := (^rawptr)(value.data)^
	if ptr == nil {
		flag: u8 = 0
		os.write_ptr(fp, &flag, size_of(u8))
	} else {
		ti := runtime.type_info_base(type_info_of(value.id))
		ptr_info := ti.variant.(runtime.Type_Info_Pointer)
		if ptr_info.elem == nil {
			flag: u8 = 0
			os.write_ptr(fp, &flag, size_of(u8))
		} else {
			flag: u8 = 1
			os.write_ptr(fp, &flag, size_of(u8))
			save_internal(fp, any{ptr, ptr_info.elem.id})
		}
	}
}

@(private)
save_any :: proc(fp: ^os.File, value: any) {
	a := (^any)(value.data)^
	if a.id == nil {
		type_val: typeid = nil
		os.write_ptr(fp, &type_val, size_of(typeid))
	} else {
		type_val := a.id
		os.write_ptr(fp, &type_val, size_of(typeid))
		save_internal(fp, a)
	}
}
