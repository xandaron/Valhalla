package ImRefl

import "base:runtime"
import "core:math"
import "core:fmt"
import "core:reflect"
import "core:strings"

import imgui "../imgui"


Draw_Flag :: enum {
	Read_Only,
	Callable,

	// For internal use.
	Using_Flatten,
	Padding,
}
Draw_Flags :: bit_set[Draw_Flag]

DONT_PROPAGATE :: Draw_Flags{.Callable, .Using_Flatten}

draw_value :: proc(name: string, value: any, flags: Draw_Flags = nil, ptr: rawptr = nil) {
	switch reflect.type_kind(value.id) {
	case .Invalid: panic("Invalid Type!")
	case .Named:            draw_value(name, any{value.data, reflect.typeid_base(value.id)}, flags, ptr)
	case .Struct:           draw_struct_type(name, value, flags)
	case .Bit_Field:        draw_bit_field_type(name, value, flags)
	case .Union:            draw_union_type(name, value, flags)
	case .Bit_Set:          draw_bit_set_type(name, value, flags)
	case .Enum:             draw_enum_type(name, value, flags)
	case .Any:              draw_any_type(name, value, flags)
	case .Type_Id:          draw_type_id(name, value, flags)
	case .Pointer:          draw_pointer_type(name, value, flags)
	case .String:           draw_string_type(name, value, flags)
	case .Complex:          draw_complex_type(name, value, flags)
	case .Quaternion:       draw_quat_type(name, value, flags)
	case .Boolean:          draw_bool_type(name, value, flags)
	case .Integer, .Rune:   draw_integer_type(name, value, flags)
	case .Float:            draw_float_type(name,value, flags)
	case .Map:              draw_map_type(name, value, flags)
	case .Matrix:           draw_matrix_type(name, value, flags)
	case .Array:            draw_array_type(name, value, flags)
	case .Slice:            draw_slice_type(name, value, flags)
	case .Enumerated_Array: draw_enum_array_type(name, value, flags)
	case .Dynamic_Array:    draw_dyn_array_type(name, value, flags)
	case .Multi_Pointer:    draw_multi_pointer_type(name, value, flags)
	case .Simd_Vector:      draw_simd_vec_type(name, value, flags)
	case .Soa_Pointer:      draw_soa_pointer_type(name, value, flags)
	case .Procedure:        draw_proc_type(name, value, flags, ptr)
	case .Parameters: // As is a proc param? I don't think we need to cover this.
	}
}

@(private)
assert_kind :: #force_inline proc(got, expected: reflect.Type_Kind, loc := #caller_location) {
	fmt.assertf(got == expected, "Value type kind must be %v! Got %v", expected, got, loc = loc)
}

@(private)
strip_endianness :: proc(type: typeid) -> typeid {
	switch type {
	case i16le,  i16be:  return i16
	case u16le,  u16be:  return u16
	case i32le,  i32be:  return i32
	case u32le,  u32be:  return u32
	case i64le,  i64be:  return i64
	case u64le,  u64be:  return u64
	case i128le, i128be: return i128
	case u128le, u128be: return u128
	case f16le,  f16be:  return f16
	case f32le,  f32be:  return f32
	case f64le,  f64be:  return f64
	}
	return type // If not an endian type just return the original.
}

@(private)
endian_swap :: proc(ptr: rawptr, #any_int len: uint) {
	buf := ([^]byte)(ptr)
	for idx in 0..<(len/2) {
		// Swap byte order
		buf[idx]       ~= buf[len-1-idx]
		buf[len-idx-1] ~= buf[idx]
		buf[idx]       ~= buf[len-1-idx]
	}
}

@(private)
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
	case: fmt.panicf("Non-int typeid: %v", value.id)
	}
}

@(private)
read_any_int_as :: proc(value: any, $T: typeid) -> T {
	switch runtime.typeid_underlying(value.id) {
	case i8:      return T((^i8     )(value.data)^)
	case i16:     return T((^i16    )(value.data)^)
	case i32:     return T((^i32    )(value.data)^)
	case i64:     return T((^i64    )(value.data)^)
	case i128:    return T((^i128   )(value.data)^)
	case int:     return T((^int    )(value.data)^)
	case u8:      return T((^u8     )(value.data)^)
	case u16:     return T((^u16    )(value.data)^)
	case u32:     return T((^u32    )(value.data)^)
	case u64:     return T((^u64    )(value.data)^)
	case u128:    return T((^u128   )(value.data)^)
	case uint:    return T((^uint   )(value.data)^)
	case uintptr: return T((^uintptr)(value.data)^)
	case u16le:   return T((^u16le  )(value.data)^)
	case u32le:   return T((^u32le  )(value.data)^)
	case u64le:   return T((^u64le  )(value.data)^)
	case u128le:  return T((^u128le )(value.data)^)
	case i16le:   return T((^i16le  )(value.data)^)
	case i32le:   return T((^i32le  )(value.data)^)
	case i64le:   return T((^i64le  )(value.data)^)
	case i128le:  return T((^i128le )(value.data)^)
	case u16be:   return T((^u16be  )(value.data)^)
	case u32be:   return T((^u32be  )(value.data)^)
	case u64be:   return T((^u64be  )(value.data)^)
	case u128be:  return T((^u128be )(value.data)^)
	case i16be:   return T((^i16be  )(value.data)^)
	case i32be:   return T((^i32be  )(value.data)^)
	case i64be:   return T((^i64be  )(value.data)^)
	case i128be:  return T((^i128be )(value.data)^)
	case rune:    return T((^rune   )(value.data)^)
	}
	fmt.panicf("Non-int typeid: %v", value.id)
}

@(private)
write_float_to_any :: proc(f: $T, value: any) {
	switch runtime.typeid_underlying(value.id) {
	case f16:   (^f16  )(value.data)^ = f16(f)
	case f32:   (^f32  )(value.data)^ = f32(f)
	case f64:   (^f64  )(value.data)^ = f64(f)
	case f16le: (^f16le)(value.data)^ = f16le(f)
	case f32le: (^f32le)(value.data)^ = f32le(f)
	case f64le: (^f64le)(value.data)^ = f64le(f)
	case f16be: (^f16be)(value.data)^ = f16be(f)
	case f32be: (^f32be)(value.data)^ = f32be(f)
	case f64be: (^f64be)(value.data)^ = f64be(f)
	case: fmt.panicf("Non-float typeid: %v", value.id)
	}
}

@(private)
read_any_float_as :: proc(value: any, $T: typeid) -> T {
	switch runtime.typeid_underlying(value.id) {
	case f16:   return T((^f16  )(value.data)^)
	case f32:   return T((^f32  )(value.data)^)
	case f64:   return T((^f64  )(value.data)^)
	case f16le: return T((^f16le)(value.data)^)
	case f32le: return T((^f32le)(value.data)^)
	case f64le: return T((^f64le)(value.data)^)
	case f16be: return T((^f16be)(value.data)^)
	case f32be: return T((^f32be)(value.data)^)
	case f64be: return T((^f64be)(value.data)^)
	}
	fmt.panicf("Non-float typeid: %v", value.id)
}

@(private)
tag_value_to_flag :: proc(str: string) -> (Draw_Flag, bool) {
	switch str {
	case "read-only": return .Read_Only, true
	case "padding":   return .Padding, true
	case "callable":  return .Callable, true
	}
	return nil, false
}

@(private)
flags_from_field_tag :: proc(tag: reflect.Struct_Tag) -> (flags: Draw_Flags) {
	values, ok := reflect.struct_tag_lookup(tag, "imrefl")
	if !ok {
		return nil
	}

	for true {
		idx := strings.index_byte(values, ',')
		str: string
		if idx == -1 {
			str = values
		} else {
			str = values[:idx]
		}

		flag, ok := tag_value_to_flag(str)
		if ok {
			flags += {flag}
		}

		if idx == -1 {
			break
		}
		values = values[idx + 1:]
	}
	return
}

@(private)
draw_struct_type :: proc(name: string, value: any, flags: Draw_Flags) {
	struct_content :: proc(name: string, value: any, flags: Draw_Flags) {
		bytes := ([^]byte)(value.data)
		propagate_flags := flags - DONT_PROPAGATE
		for &field in reflect.struct_fields_zipped(value.id) {
			field_flags := propagate_flags + flags_from_field_tag(field.tag)
			if .Padding in field_flags {
				continue
			}

			if field.is_using && field.name == "_" {
				field_flags += {.Using_Flatten}
			}
			draw_value(field.name, any{&bytes[field.offset], field.type.id}, field_flags, value.data)
		}
	}
	assert_kind(reflect.type_kind(value.id), .Struct)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if .Using_Flatten not_in flags {
		if imgui.Gui_TreeNode(fmt.ctprint(name)) {
			defer imgui.Gui_TreePop()
			struct_content(name, value, flags)
		}
	} else {
		struct_content(name, value, flags - {.Using_Flatten})
	}
}

@(private)
draw_bit_field_type :: proc(name: string, value: any, flags: Draw_Flags) {
	bit_field_content :: proc(name: string, value: any, flags: Draw_Flags) {
		// Unteseted on big-endian platforms.
		swap_endian := false
		when ODIN_ENDIAN == .Little {
			swap_endian = reflect.is_endian_big(reflect.type_info_core(type_info_of(value.id)))
		} else when ODIN_ENDIAN == .Big {
			swap_endian = reflect.is_endian_little(reflect.type_info_core(type_info_of(value.id)))
		}

		buf := ([^]byte)(value.data)
		for &field in reflect.bit_fields_zipped(value.id) {
			mask: u64 = (1 << field.size) - 1
			idx := field.offset / 8
			offset := field.offset % 8
			data_ptr := (^u128)(&buf[idx])
			value_u128 := (data_ptr^) & (u128(mask) << offset)
			data_ptr^ ~= value_u128 // Zero bits withing fields bit range
			// It should be safe to downcast as the field size cant be larger that 64 bits
			value_u64 := u64(value_u128 >> offset)

			if swap_endian {
				endian_swap(&value_u64, uint(math.ceil(f64(field.size) / 8.0)))
			}

			if reflect.is_signed(field.type) && (1 << (field.size - 1)) & value_u64 != 0 {
				value_u64 |= ~mask // Sign extend if negative.
			}

			draw_value(field.name, any{&value_u64, strip_endianness(field.type.id)}, flags + flags_from_field_tag(field.tag))

			if reflect.is_signed(field.type) {
				// We can't just check tmp < 0 as draw_value won't set the upper bits if size_of(field.type.id) < 8
				if (1 << u64(field.type.size * 8 - 1)) & value_u64 != 0 {
					value_u64 = max(value_u64, ~(mask >> 1))
				} else {
					value_u64 = min(value_u64, mask >> 1)
				}
			} else {
				value_u64 = min(value_u64, mask)
			}

			if swap_endian {
				endian_swap(&value_u64, uint(math.ceil(f64(field.size) / 8.0)))
			}

			data_ptr^ |= u128(value_u64 & mask) << offset
		}
	}
	assert_kind(reflect.type_kind(value.id), .Bit_Field)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if .Using_Flatten not_in flags {
		if imgui.Gui_TreeNode(fmt.ctprint(name)) {
			defer imgui.Gui_TreePop()
			bit_field_content(name, value, flags)
		}
	} else {
		bit_field_content(name, value, flags - {.Using_Flatten})
	}
}

@(private)
draw_union_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Union)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		type_info := type_info_of(value.id)
		union_info := type_info.variant.(reflect.Type_Info_Union)
		bytes := ([^]byte)(value.data)

		variant_idx, _ := reflect.as_u64(any{&bytes[union_info.tag_offset], union_info.tag_type.id})
		if variant_idx == 0 {
			imgui.Gui_TextEx(fmt.ctprint("variant: nil"))
			return
		}

		variant_info := union_info.variants[variant_idx - 1]
		imgui.Gui_TextEx(fmt.ctprintf("variant: %v", variant_info.id))
		draw_value("data", any{value.data, variant_info.id}, flags)
	}
}

@(private)
draw_bit_set_type :: proc(name: string, value: any, flags: Draw_Flags) {
	value := value
	assert_kind(reflect.type_kind(value.id), .Bit_Set)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		type_info := type_info_of(value.id)
		set_info := type_info.variant.(reflect.Type_Info_Bit_Set)

		value.id = runtime.typeid_underlying(value.id)
		value_u128 := read_any_int_as(value, u128)

		imgui.Gui_BeginDisabled(.Read_Only in flags)
		defer imgui.Gui_EndDisabled()

		for &enum_value in reflect.enum_fields_zipped(set_info.elem.id) {
			active := (1 << u64(enum_value.value)) & value_u128 != 0
			if imgui.Gui_Checkbox(fmt.ctprint(enum_value.name), &active) {
				value_u128 ~= (1 << u64(enum_value.value))
			}
		}
		write_int_to_any(value_u128, value)
	}
}

@(private)
draw_enum_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Enum)

	getter :: proc "c" (user_data: rawptr, idx: i32) -> cstring {
		context = runtime.default_context()
		fields := (^#soa[]reflect.Enum_Field)(user_data)
		return fmt.ctprint(fields[idx].name)
	}

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	imgui.Gui_BeginDisabled(.Read_Only in flags)
	defer imgui.Gui_EndDisabled()

	if imgui.Gui_BeginCombo(fmt.ctprint(name), fmt.ctprint(reflect.enum_string(value)), nil) {
		defer imgui.Gui_EndCombo()

		value_i64 := read_any_int_as(value, i64)
		for &enum_value in reflect.enum_fields_zipped(value.id) {
			if i64(enum_value.value) == value_i64 {
				continue
			}

			if imgui.Gui_Selectable(fmt.ctprint(enum_value.name)) {
				write_int_to_any(enum_value.value, value)
				break
			}
		}
	}
}

@(private)
draw_any_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Any)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if (^any)(value.data).id == nil {
		imgui.Gui_TextEx(fmt.ctprintf("%s: nil", name))
		return
	}

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		draw_type_id("typeid", (^any)(value.data).id, flags)
		draw_value("data", (^any)(value.data)^, flags)
		imgui.Gui_TreePop()
	}
}

@(private)
draw_type_id :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Type_Id)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	imgui.Gui_TextEx(fmt.ctprintf("%s: %v", name, (^typeid)(value.data)^))
}

@(private)
draw_pointer_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Pointer)
	
	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()
	
	if (^rawptr)(value.data)^ == nil {
		imgui.Gui_TextEx(fmt.ctprintf("%s: nil", name))
	} else if value.id == rawptr {
		imgui.Gui_TextEx(fmt.ctprintf("%s: %v", name, (^rawptr)(value.data)^))
	} else {
		pointee_type_id := type_info_of(value.id).variant.(reflect.Type_Info_Pointer).elem.id
		data_ptr := (^rawptr)(value.data)^
		draw_value(fmt.tprintf("%s: %v", name, data_ptr), any{data_ptr, pointee_type_id}, flags)
	}
}

@(private)
draw_string_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .String)
	
	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	switch value.id {
	// How do we support utf16 strings properly?
	case cstring:   imgui.Gui_TextEx(fmt.ctprintf("\"%s\" %s", (^cstring  )(value.data)^, name))
	case cstring16: imgui.Gui_TextEx(fmt.ctprintf("\"%s\" %s", (^cstring16)(value.data)^, name))
	case string:    imgui.Gui_TextEx(fmt.ctprintf("\"%s\" %s", (^string   )(value.data)^, name))
	case string16:  imgui.Gui_TextEx(fmt.ctprintf("\"%s\" %s", (^string16 )(value.data)^, name))
	}
}

@(private)
draw_complex_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Complex)
	real, imag: rawptr
	type: typeid
	switch value.id {
	case complex32:
		type = f16
		raw := (^runtime.Raw_Complex32)(value.data)
		real = &raw.real
		imag = &raw.imag
	case complex64:
		type = f32
		raw := (^runtime.Raw_Complex64)(value.data)
		real = &raw.real
		imag = &raw.imag
	case complex128:
		type = f64
		raw := (^runtime.Raw_Complex128)(value.data)
		real = &raw.real
		imag = &raw.imag
	case: panic("Invalid type id!")
	}

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	// this is very arbitrary
	width := (imgui.Gui_GetContentRegionAvail().x - 120 - imgui.Gui_GetStyle().CellPadding.x * 4) / 2
	imgui.Gui_SetNextItemWidth(width)
	draw_float_type("+", any{real, type}, flags)
	imgui.Gui_SameLine()
	imgui.Gui_SetNextItemWidth(width)
	draw_float_type(fmt.tprintf("i %s", name), any{imag, type}, flags)
}

@(private)
draw_quat_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Quaternion)
	ptrs: [4]rawptr
	type: typeid
	switch value.id {
	case quaternion64:
		type = f16
		raw := (^runtime.Raw_Quaternion64)(value.data)
		ptrs[0] = &raw.imag
		ptrs[1] = &raw.jmag
		ptrs[2] = &raw.kmag
		ptrs[3] = &raw.real
	case quaternion128:
		type = f32
		raw := (^runtime.Raw_Quaternion128)(value.data)
		ptrs[0] = &raw.imag
		ptrs[1] = &raw.jmag
		ptrs[2] = &raw.kmag
		ptrs[3] = &raw.real
	case quaternion256:
		type = f64
		raw := (^runtime.Raw_Quaternion256)(value.data)
		ptrs[0] = &raw.imag
		ptrs[1] = &raw.jmag
		ptrs[2] = &raw.kmag
		ptrs[3] = &raw.real
	case: panic("Invalid type id!!")
	}

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()	

	imgui.Gui_BeginDisabled(.Read_Only in flags)
	defer imgui.Gui_EndDisabled()

	// len(name) * 7 was chosen arbitrarily.
	width := (imgui.Gui_GetContentRegionAvail().x - 110 - imgui.Gui_GetStyle().CellPadding.x * 7) / 4.0
	for idx in 0..<4 {
		imgui.Gui_SetNextItemWidth(width)
		draw_float_type("", any{ptrs[idx], type}, flags)
		imgui.Gui_SameLine()
	}
	imgui.Gui_TextEx(fmt.ctprint(name))
}

@(private)
draw_bool_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Boolean)
	value_bool, _ := reflect.as_bool(value)
	
	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	imgui.Gui_BeginDisabled(.Read_Only in flags)
	defer imgui.Gui_EndDisabled()

	if imgui.Gui_Checkbox(fmt.ctprint(name), &value_bool) {
		switch value.id {
		case b8:   (^b8  )(value.data)^ = auto_cast value_bool
		case b16:  (^b16 )(value.data)^ = auto_cast value_bool
		case b32:  (^b32 )(value.data)^ = auto_cast value_bool
		case b64:  (^b64 )(value.data)^ = auto_cast value_bool
		case bool: (^bool)(value.data)^ = value_bool
		}
	}
}

@(private)
draw_integer_type :: proc(name: string, value: any, flags: Draw_Flags) {
	kind := reflect.type_kind(value.id)
	fmt.assertf(kind == .Integer || kind == .Rune, "Value type kind must be %v or %v! Got %v", reflect.Type_Kind.Integer, reflect.Type_Kind.Rune, kind)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	imgui.Gui_BeginDisabled(.Read_Only in flags)
	defer imgui.Gui_EndDisabled()

	is_unsigned := reflect.is_unsigned(type_info_of(value.id))
	tmp := read_any_int_as(value, u64)
	if imgui.Gui_InputScalar(fmt.ctprint(name), is_unsigned ? .U64 : .S64, &tmp) {
		write_int_to_any(tmp, value)
	}
}

@(private)
draw_float_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Float)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	imgui.Gui_BeginDisabled(.Read_Only in flags)
	defer imgui.Gui_EndDisabled()

	tmp := read_any_float_as(value, f64)
	if imgui.Gui_InputScalar(fmt.ctprint(name), .Double, &tmp) {
		write_float_to_any(tmp, value)
	}
}

@(private)
draw_map_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Map)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		map_info := type_info_of(value.id).variant.(reflect.Type_Info_Map)

		width := (imgui.Gui_GetContentRegionAvail().x - imgui.Gui_GetStyle().ItemSpacing.x * 3) / 4
		imgui.Gui_SetNextItemWidth(width)
		
		it: int = 0
		for idx := 0;; idx += 1 {
			key, value, ok := reflect.iterate_map(value, &it)
			if !ok {
				break
			}

			if imgui.Gui_TreeNode(fmt.ctprint(idx)) {
				draw_value("key",   any{key.data, map_info.key.id}, flags)
				draw_value("value", any{value.data, map_info.value.id}, flags)
				imgui.Gui_TreePop()
			}
		}
	}
}

@(private)
draw_matrix_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Matrix)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		type_info := type_info_of(value.id)
		matrix_info := type_info.variant.(reflect.Type_Info_Matrix)

		row_stride := matrix_info.layout == .Row_Major ? (matrix_info.elem_size * matrix_info.column_count) : matrix_info.elem_size
		column_stride := matrix_info.layout == .Column_Major ? (matrix_info.elem_size * matrix_info.row_count) : matrix_info.elem_size

		width := (imgui.Gui_GetContentRegionAvail().x - imgui.Gui_GetStyle().ItemSpacing.x * 3) / f32(matrix_info.column_count)
		bytes := ([^]byte)(value.data)

		for c in 0..<matrix_info.column_count {
			for r in 0..<matrix_info.row_count {
				imgui.Gui_SetNextItemWidth(width)
				if r > 0 {
					imgui.Gui_SameLine()
				}

				ptr := &bytes[c * column_stride + r * row_stride]
				imgui.Gui_PushIDPtr(ptr)
				defer imgui.Gui_PopID()

				draw_value("", any{ptr, matrix_info.elem.id}, flags)
			}
		}
	}
}

@(private)
draw_array_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Array)
	
	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		array_info := type_info_of(value.id).variant.(reflect.Type_Info_Array)
		for idx in 0..<array_info.count {
			draw_value(fmt.tprint(idx), any{rawptr(uintptr(value.data) + uintptr(array_info.elem.size * idx)), array_info.elem.id}, flags)
		}
	}
}

@(private)
draw_slice_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Slice)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		slice_info := type_info_of(value.id).variant.(reflect.Type_Info_Slice)
		raw_slice := (^runtime.Raw_Slice)(value.data)
		bytes := ([^]byte)(raw_slice.data)
		
		for idx in 0..<raw_slice.len {
			draw_value(fmt.tprint(idx), any{&bytes[idx * slice_info.elem_size], slice_info.elem.id}, flags)
		}
	}
}

@(private)
draw_enum_array_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Enumerated_Array)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		array_info := type_info_of(value.id).variant.(reflect.Type_Info_Enumerated_Array)
		// TODO: Implement.
	}
}

@(private)
draw_dyn_array_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Dynamic_Array)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		array_info := type_info_of(value.id).variant.(reflect.Type_Info_Dynamic_Array)
		raw_array := (^runtime.Raw_Dynamic_Array)(value.data)
		bytes := ([^]byte)(raw_array.data)
		
		for idx in 0..<raw_array.len {
			draw_value(fmt.tprint(idx), any{&bytes[array_info.elem_size * idx], array_info.elem.id}, flags)
		}
	}
}

@(private)
draw_multi_pointer_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Multi_Pointer)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	imgui.Gui_BeginDisabled(.Read_Only in flags)
	defer imgui.Gui_EndDisabled()

	draw_pointer_type(name, any{value.data, typeid_of(rawptr)}, nil)
}

@(private)
draw_simd_vec_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Simd_Vector)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		vector_info := type_info_of(value.id).variant.(reflect.Type_Info_Simd_Vector)
		bytes := ([^]byte)(value.data)
		for idx in 0..<vector_info.count {
			draw_value(fmt.tprint(idx), any{&bytes[vector_info.elem_size * idx], vector_info.elem.id}, flags)
		}
	}
}

// TODO: What's this even meant to represent?
// How should we display this?
@(private)
draw_soa_pointer_type :: proc(name: string, value: any, flags: Draw_Flags) {
	assert_kind(reflect.type_kind(value.id), .Soa_Pointer)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		raw_soa := (^runtime.Raw_Soa_Pointer)(value.data)
		soa_info := type_info_of(value.id).variant.(reflect.Type_Info_Soa_Pointer)
	}
}

// What should this even do? I'll just write the proc address.
// Maybe we can make the proc callable with struct tags.
@(private)
draw_proc_type :: proc(name: string, value: any, flags: Draw_Flags, ptr: rawptr = nil) {
	assert_kind(reflect.type_kind(value.id), .Procedure)

	imgui.Gui_PushIDPtr(value.data)
	defer imgui.Gui_PopID()

	if imgui.Gui_TreeNode(fmt.ctprint(name)) {
		defer imgui.Gui_TreePop()

		imgui.Gui_Text(fmt.ctprintf("%v proc address", (^rawptr)(value.data)^))

		if .Callable in flags {
			proc_info := type_info_of(value.id).variant.(reflect.Type_Info_Procedure)
			if proc_info.params != nil {
				param_info := proc_info.params.variant.(reflect.Type_Info_Parameters)
				if len(param_info.types) == 1 && param_info.types[0].id == rawptr {
					imgui.Gui_SameLine()
					if imgui.Gui_Button("call") {
						(^proc(rawptr))(value.data)^(ptr)
					}
				}
			}
		}
	}
}

