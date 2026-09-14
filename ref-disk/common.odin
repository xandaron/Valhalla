package RefDisk

import "base:runtime"
import "core:reflect"
import "core:strings"

// Determines whether a struct field should be skipped based on struct tags.
// Supports refdisk:"ignore", refdisk:"padding", refdisk:"-", and imrefl:"padding", imrefl:"ignore".
should_skip_field :: proc(tag: reflect.Struct_Tag) -> bool {
	if val, ok := reflect.struct_tag_lookup(tag, "refdisk"); ok {
		if val == "ignore" || val == "padding" || val == "-" {
			return true
		}
	}
	if val, ok := reflect.struct_tag_lookup(tag, "imrefl"); ok {
		if strings.contains(val, "padding") || strings.contains(val, "ignore") {
			return true
		}
	}
	return false
}

// Checks if any field of a struct type has been marked to be ignored or skipped.
has_ignored_fields :: proc(T: typeid) -> bool {
	ti := runtime.type_info_base(type_info_of(T))
	if _, ok := ti.variant.(runtime.Type_Info_Struct); ok {
		for &field in reflect.struct_fields_zipped(T) {
			if should_skip_field(field.tag) {
				return true
			}
		}
	}
	return false
}

// Checks if a type is plain data (contains no pointers, strings, dynamic arrays, slices, maps, procedures, or any).
// Plain types can be serialized and deserialized in a single bulk read/write operation.
is_type_plain :: proc(ti: ^runtime.Type_Info) -> bool {
	if ti == nil do return false
	base := runtime.type_info_base(ti)
	#partial switch v in base.variant {
	case runtime.Type_Info_Integer,
	     runtime.Type_Info_Rune,
	     runtime.Type_Info_Float,
	     runtime.Type_Info_Boolean,
	     runtime.Type_Info_Complex,
	     runtime.Type_Info_Quaternion,
	     runtime.Type_Info_Enum,
	     runtime.Type_Info_Bit_Set,
	     runtime.Type_Info_Simd_Vector,
	     runtime.Type_Info_Matrix,
	     runtime.Type_Info_Bit_Field:
		return true
	case runtime.Type_Info_Array:
		return is_type_plain(v.elem)
	case runtime.Type_Info_Enumerated_Array:
		return is_type_plain(v.elem)
	case runtime.Type_Info_Struct:
		if has_ignored_fields(base.id) {
			return false
		}
		for type in v.types[:v.field_count] {
			if !is_type_plain(type) {
				return false
			}
		}
		return true
	case:
		return false
	}
}

// Writes an integer value to an any whose underlying type is an integer or rune.
write_int_to_any :: proc(i: $T, value: any) {
	switch runtime.typeid_underlying(value.id) {
	case i8:      (^i8     )(value.data)^ = i8(i)
	case i16:     (^i16    )(value.data)^ = i16(i)
	case i32:     (^i32    )(value.data)^ = i32(i)
	case i64:     (^i64    )(value.data)^ = i64(i)
	case i128:    (^i128   )(value.data)^ = i128(i)
	case int:     (^int    )(value.data)^ = int(i)
	case u8:      (^u8     )(value.data)^ = u8(i)
	case u16:     (^u16    )(value.data)^ = u16(i)
	case u32:     (^u32    )(value.data)^ = u32(i)
	case u64:     (^u64    )(value.data)^ = u64(i)
	case u128:    (^u128   )(value.data)^ = u128(i)
	case uint:    (^uint   )(value.data)^ = uint(i)
	case uintptr: (^uintptr)(value.data)^ = uintptr(i)
	case u16le:   (^u16le  )(value.data)^ = u16le(i)
	case u32le:   (^u32le  )(value.data)^ = u32le(i)
	case u64le:   (^u64le  )(value.data)^ = u64le(i)
	case u128le:  (^u128le )(value.data)^ = u128le(i)
	case i16le:   (^i16le  )(value.data)^ = i16le(i)
	case i32le:   (^i32le  )(value.data)^ = i32le(i)
	case i64le:   (^i64le  )(value.data)^ = i64le(i)
	case i128le:  (^i128le )(value.data)^ = i128le(i)
	case u16be:   (^u16be  )(value.data)^ = u16be(i)
	case u32be:   (^u32be  )(value.data)^ = u32be(i)
	case u64be:   (^u64be  )(value.data)^ = u64be(i)
	case u128be:  (^u128be )(value.data)^ = u128be(i)
	case i16be:   (^i16be  )(value.data)^ = i16be(i)
	case i32be:   (^i32be  )(value.data)^ = i32be(i)
	case i64be:   (^i64be  )(value.data)^ = i64be(i)
	case i128be:  (^i128be )(value.data)^ = i128be(i)
	case rune:    (^rune   )(value.data)^ = rune(i)
	}
}
