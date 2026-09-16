package ImRefl

import "base:runtime"
import "core:math"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:math/linalg"

import imgui "../imgui"


Draw_Flag :: enum {
	Read_Only,
	Callable,
	Euler,
	Colour,
	Normalized,
	Flatten,
	Ignore,
	Has_Min,
	Has_Max,
	Has_Speed,
}
Draw_Flags :: bit_set[Draw_Flag]

Draw_Info :: struct {
	flags: Draw_Flags,
	min:   f64,
	max:   f64,
	speed: f64,
	label: string,
}

DONT_PROPAGATE :: Draw_Flags{.Callable, .Flatten, .Euler, .Colour, .Normalized}

draw_value :: proc(name: string, value: any, info: Draw_Info = {}, ptr: rawptr = nil) -> (changed: bool) {
	switch reflect.type_kind(value.id) {
	case .Invalid: panic("Invalid Type!")
	case .Named:            return draw_value(name, any{value.data, reflect.typeid_base(value.id)}, info, ptr)
	case .Struct:           return draw_struct_type(name, value, info)
	case .Bit_Field:        return draw_bit_field_type(name, value, info)
	case .Union:            return draw_union_type(name, value, info)
	case .Bit_Set:          return draw_bit_set_type(name, value, info)
	case .Enum:             return draw_enum_type(name, value, info)
	case .Any:              return draw_any_type(name, value, info)
	case .Type_Id:          return draw_type_id(name, value, info)
	case .Pointer:          return draw_pointer_type(name, value, info)
	case .String:           return draw_string_type(name, value, info)
	case .Complex:          return draw_complex_type(name, value, info)
	case .Quaternion:       return draw_quat_type(name, value, info)
	case .Boolean:          return draw_bool_type(name, value, info)
	case .Integer, .Rune:   return draw_integer_type(name, value, info)
	case .Float:            return draw_float_type(name,value, info)
	case .Map:              return draw_map_type(name, value, info)
	case .Matrix:           return draw_matrix_type(name, value, info)
	case .Array:            return draw_array_type(name, value, info)
	case .Slice:            return draw_slice_type(name, value, info)
	case .Enumerated_Array: return draw_enum_array_type(name, value, info)
	case .Dynamic_Array:    return draw_dyn_array_type(name, value, info)
	case .Fixed_Capacity_Dynamic_Array: return draw_fixed_capacity_dyn_array_type(name, value, info)
	case .Multi_Pointer:    return draw_multi_pointer_type(name, value, info)
	case .Simd_Vector:      return draw_simd_vec_type(name, value, info)
	case .Soa_Pointer:      return draw_soa_pointer_type(name, value, info)
	case .Procedure:        return draw_proc_type(name, value, info, ptr)
	case .Parameters: // As is a proc param? I don't think we need to cover this.
	}
	return
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
	// refdisk reads the same `imrefl` tag, so the two must agree on this vocabulary or a field
	// silently hides from one and not the other.
	case "ignore":    return .Ignore, true
	case "callable":  return .Callable, true
	case "euler":     return .Euler, true
	case "colour", "color": return .Colour, true
	case "normalized", "normalised": return .Normalized, true
	// Draws a struct's fields inline instead of behind its own tree node. Set automatically for an
	// anonymous `using _` field, and writable by hand on any struct.
	case "flatten":   return .Flatten, true
	}
	return nil, false
}

@(private)
without_flatten :: proc(info: Draw_Info) -> (out: Draw_Info) {
	out = info
	out.flags -= {.Flatten}
	return
}

@(private)
info_from_field_tag :: proc(tag: reflect.Struct_Tag, base: Draw_Info) -> (info: Draw_Info) {
	info = base
	values, ok := reflect.struct_tag_lookup(tag, "imrefl")
	if !ok {
		return
	}

	for len(values) > 0 {
		str := values
		if idx := strings.index_byte(values, ','); idx != -1 {
			str = values[:idx]
			values = values[idx + 1:]
		} else {
			values = ""
		}
		str = strings.trim_space(str)

		if eq := strings.index_byte(str, '='); eq != -1 {
			key := strings.trim_space(str[:eq])
			text := strings.trim_space(str[eq + 1:])

			// Values are split on commas, so a label cannot contain one.
			if key == "label" {
				info.label = text
				continue
			}

			number, parsed := strconv.parse_f64(text)
			if !parsed {
				continue
			}
			switch key {
			case "min":   info.min = number;   info.flags += {.Has_Min}
			case "max":   info.max = number;   info.flags += {.Has_Max}
			case "speed": info.speed = number; info.flags += {.Has_Speed}
			}
			continue
		}

		if flag, found := tag_value_to_flag(str); found {
			info.flags += {flag}
		}
	}
	return
}

@(private)
draw_struct_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	struct_content :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
		bytes := ([^]byte)(value.data)
		propagate := info
		propagate.flags -= DONT_PROPAGATE
		propagate.label = ""
		for &field in reflect.struct_fields_zipped(value.id) {
			field_info := info_from_field_tag(field.tag, propagate)
			if .Ignore in field_info.flags {
				continue
			}

			// An anonymous `using` field has no name worth showing, so it always flattens.
			if field.is_using && field.name == "_" {
				field_info.flags += {.Flatten}
			}
			label := field_info.label if field_info.label != "" else field.name
			changed |= draw_value(label, any{&bytes[field.offset], field.type.id}, field_info, value.data)
		}
		return
	}
	assert_kind(reflect.type_kind(value.id), .Struct)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if .Flatten not_in info.flags {
		if imgui.TreeNode(fmt.ctprint(name)) {
			defer imgui.TreePop()
			changed = struct_content(name, value, info)
		}
	} else {
		changed = struct_content(name, value, without_flatten(info))
	}
	return
}

@(private)
draw_bit_field_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	bit_field_content :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
		// Unteseted on big-endian platforms.
		swap_endian := false
		when ODIN_ENDIAN == .Little {
			swap_endian = reflect.is_endian_big(reflect.type_info_core(type_info_of(value.id)))
		} else when ODIN_ENDIAN == .Big {
			swap_endian = reflect.is_endian_little(reflect.type_info_core(type_info_of(value.id)))
		}

		buf := ([^]byte)(value.data)
		bit_field_base := info
		bit_field_base.label = ""
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

			field_info := info_from_field_tag(field.tag, bit_field_base)
			label := field_info.label if field_info.label != "" else field.name
			changed |= draw_value(label, any{&value_u64, strip_endianness(field.type.id)}, field_info)

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
		return
	}
	assert_kind(reflect.type_kind(value.id), .Bit_Field)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if .Flatten not_in info.flags {
		if imgui.TreeNode(fmt.ctprint(name)) {
			defer imgui.TreePop()
			changed = bit_field_content(name, value, info)
		}
	} else {
		changed = bit_field_content(name, value, without_flatten(info))
	}
	return
}

@(private)
draw_union_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Union)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		type_info := type_info_of(value.id)
		union_info := type_info.variant.(reflect.Type_Info_Union)
		bytes := ([^]byte)(value.data)

		variant_idx, _ := reflect.as_u64(any{&bytes[union_info.tag_offset], union_info.tag_type.id})
		if variant_idx == 0 {
			imgui.TextEx(fmt.ctprint("variant: nil"))
			return
		}

		variant_info := union_info.variants[variant_idx - 1]
		imgui.TextEx(fmt.ctprintf("variant: %v", variant_info.id))
		changed = draw_value("data", any{value.data, variant_info.id}, info)
	}
	return
}

@(private)
draw_bit_set_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	value := value
	assert_kind(reflect.type_kind(value.id), .Bit_Set)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		type_info := type_info_of(value.id)
		set_info := type_info.variant.(reflect.Type_Info_Bit_Set)

		value.id = runtime.typeid_underlying(value.id)
		value_u128 := read_any_int_as(value, u128)

		imgui.BeginDisabled(.Read_Only in info.flags)
		defer imgui.EndDisabled()

		for &enum_value in reflect.enum_fields_zipped(set_info.elem.id) {
			active := (1 << u64(enum_value.value)) & value_u128 != 0
			if imgui.Checkbox(fmt.ctprint(enum_value.name), &active) {
				value_u128 ~= (1 << u64(enum_value.value))
				changed = true
			}
		}
		write_int_to_any(value_u128, value)
	}
	return
}

@(private)
draw_enum_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Enum)

	getter :: proc "c" (user_data: rawptr, idx: i32) -> cstring {
		context = runtime.default_context()
		fields := (^#soa[]reflect.Enum_Field)(user_data)
		return fmt.ctprint(fields[idx].name)
	}

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	if imgui.BeginCombo(fmt.ctprint(name), fmt.ctprint(reflect.enum_string(value)), nil) {
		defer imgui.EndCombo()

		value_i64 := read_any_int_as(value, i64)
		for &enum_value in reflect.enum_fields_zipped(value.id) {
			if i64(enum_value.value) == value_i64 {
				continue
			}

			if imgui.Selectable(fmt.ctprint(enum_value.name)) {
				write_int_to_any(enum_value.value, value)
				changed = true
				break
			}
		}
	}
	return
}

@(private)
draw_any_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Any)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if (^any)(value.data).id == nil {
		imgui.TextEx(fmt.ctprintf("%s: nil", name))
		return
	}

	if imgui.TreeNode(fmt.ctprint(name)) {
		draw_type_id("typeid", (^any)(value.data).id, info)
		changed = draw_value("data", (^any)(value.data)^, info)
		imgui.TreePop()
	}
	return
}

@(private)
draw_type_id :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Type_Id)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	imgui.TextEx(fmt.ctprintf("%s: %v", name, (^typeid)(value.data)^))
	return
}

@(private)
draw_pointer_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Pointer)
	
	imgui.PushIDPtr(value.data)
	defer imgui.PopID()
	
	if (^rawptr)(value.data)^ == nil {
		imgui.TextEx(fmt.ctprintf("%s: nil", name))
	} else if value.id == rawptr {
		imgui.TextEx(fmt.ctprintf("%s: %v", name, (^rawptr)(value.data)^))
	} else {
		pointee_type_id := type_info_of(value.id).variant.(reflect.Type_Info_Pointer).elem.id
		data_ptr := (^rawptr)(value.data)^
		changed = draw_value(fmt.tprintf("%s: %v", name, data_ptr), any{data_ptr, pointee_type_id}, info)
	}
	return
}

@(private)
draw_string_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .String)
	
	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	switch value.id {
	// How do we support utf16 strings properly?
	case cstring:   imgui.TextEx(fmt.ctprintf("\"%s\" %s", (^cstring  )(value.data)^, name))
	case cstring16: imgui.TextEx(fmt.ctprintf("\"%s\" %s", (^cstring16)(value.data)^, name))
	case string:    imgui.TextEx(fmt.ctprintf("\"%s\" %s", (^string   )(value.data)^, name))
	case string16:  imgui.TextEx(fmt.ctprintf("\"%s\" %s", (^string16 )(value.data)^, name))
	}
	return
}

@(private)
draw_complex_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
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

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	// this is very arbitrary
	width := (imgui.GetContentRegionAvail().x - 120 - imgui.GetStyle().CellPadding.x * 4) / 2
	imgui.SetNextItemWidth(width)
	changed |= draw_float_type("+", any{real, type}, info)
	imgui.SameLine()
	imgui.SetNextItemWidth(width)
	changed |= draw_float_type(fmt.tprintf("i %s", name), any{imag, type}, info)
	return
}

@(private)
draw_quat_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Quaternion)

	if .Euler in info.flags && value.id == quaternion128 {
		return draw_quat_as_euler(name, (^quaternion128)(value.data), info)
	}

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

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()	

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	// len(name) * 7 was chosen arbitrarily.
	width := (imgui.GetContentRegionAvail().x - 110 - imgui.GetStyle().CellPadding.x * 7) / 4.0
	for idx in 0..<4 {
		imgui.SetNextItemWidth(width)
		changed |= draw_float_type("", any{ptrs[idx], type}, info)
		imgui.SameLine()
	}
	imgui.TextEx(fmt.ctprint(name))
	return
}

// Four raw components are editable but not authorable, so a tagged rotation is shown as XYZ Euler
// degrees instead.
//
// The edit is applied as a delta onto the existing quaternion rather than rebuilding it from the
// displayed angles. Euler extraction is not injective — the same orientation has several valid
// triples, and near a pole the extracted angles jump — so rebuilding would make the numbers snap
// around while dragging even though the orientation never moved.
@(private)
draw_quat_as_euler :: proc(
	name: string,
	rotation: ^quaternion128,
	info: Draw_Info,
) -> (
	changed: bool,
) {
	imgui.PushIDPtr(rotation)
	defer imgui.PopID()

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	x, y, z := linalg.euler_angles_xyz_from_quaternion(rotation^)
	current := [3]f32{math.to_degrees(x), math.to_degrees(y), math.to_degrees(z)}
	edited := current

	speed := f32(info.speed) if .Has_Speed in info.flags else 0.5
	if imgui.DragScalarN(fmt.ctprint(name), .Float, &edited, 3, speed) {
		delta := edited - current
		rotation^ *= linalg.quaternion_from_euler_angles_f32(
			math.to_radians(delta.x),
			math.to_radians(delta.y),
			math.to_radians(delta.z),
			.XYZ,
		)
		changed = true
	}
	return
}

@(private)
draw_bool_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Boolean)
	value_bool, _ := reflect.as_bool(value)
	
	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	if imgui.Checkbox(fmt.ctprint(name), &value_bool) {
		switch value.id {
		case b8:   (^b8  )(value.data)^ = auto_cast value_bool
		case b16:  (^b16 )(value.data)^ = auto_cast value_bool
		case b32:  (^b32 )(value.data)^ = auto_cast value_bool
		case b64:  (^b64 )(value.data)^ = auto_cast value_bool
		case bool: (^bool)(value.data)^ = value_bool
		}
		changed = true
	}
	return
}

@(private)
draw_integer_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	kind := reflect.type_kind(value.id)
	fmt.assertf(kind == .Integer || kind == .Rune, "Value type kind must be %v or %v! Got %v", reflect.Type_Kind.Integer, reflect.Type_Kind.Rune, kind)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	is_unsigned := reflect.is_unsigned(type_info_of(value.id))
	tmp := read_any_int_as(value, u64)
	if imgui.InputScalar(fmt.ctprint(name), is_unsigned ? .U64 : .S64, &tmp) {
		write_int_to_any(tmp, value)
		changed = true
	}
	return
}

@(private)
draw_float_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Float)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	// A bound or a speed means the field has a meaningful range, which a drag expresses and a
	// text box does not. Untagged fields keep the text box so precise values stay typeable.
	if info.flags & {.Has_Min, .Has_Max, .Has_Speed} != {} {
		tmp := read_any_float_as(value, f32)
		speed := f32(info.speed) if .Has_Speed in info.flags else 0.05
		low, high := bounds_f32(info)
		if imgui.DragScalar(fmt.ctprint(name), .Float, &tmp, speed, low, high) {
			write_float_to_any(tmp, value)
			changed = true
		}
		return
	}

	tmp := read_any_float_as(value, f64)
	if imgui.InputScalar(fmt.ctprint(name), .Double, &tmp) {
		write_float_to_any(tmp, value)
		changed = true
	}
	return
}

@(private)
draw_map_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Map)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		map_info := type_info_of(value.id).variant.(reflect.Type_Info_Map)

		width := (imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x * 3) / 4
		imgui.SetNextItemWidth(width)
		
		it: int = 0
		for idx := 0;; idx += 1 {
			key, value, ok := reflect.iterate_map(value, &it)
			if !ok {
				break
			}

			if imgui.TreeNode(fmt.ctprint(idx)) {
				changed |= draw_value("key",   any{key.data, map_info.key.id}, info)
				changed |= draw_value("value", any{value.data, map_info.value.id}, info)
				imgui.TreePop()
			}
		}
	}
	return
}

@(private)
draw_matrix_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Matrix)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		type_info := type_info_of(value.id)
		matrix_info := type_info.variant.(reflect.Type_Info_Matrix)

		row_stride := matrix_info.layout == .Row_Major ? (matrix_info.elem_size * matrix_info.column_count) : matrix_info.elem_size
		column_stride := matrix_info.layout == .Column_Major ? (matrix_info.elem_size * matrix_info.row_count) : matrix_info.elem_size

		width := (imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x * 3) / f32(matrix_info.column_count)
		bytes := ([^]byte)(value.data)

		for c in 0..<matrix_info.column_count {
			for r in 0..<matrix_info.row_count {
				imgui.SetNextItemWidth(width)
				if r > 0 {
					imgui.SameLine()
				}

				ptr := &bytes[c * column_stride + r * row_stride]
				imgui.PushIDPtr(ptr)
				defer imgui.PopID()

				changed |= draw_value("", any{ptr, matrix_info.elem.id}, info)
			}
		}
	}
	return
}

// imgui can edit 2 to 4 numeric components on one row. Without this a Vec3 reflects as an array
// of three floats and draws as a collapsible node with three rows, which is a bad trade for the
// most common type in a 3D editor.
//
// Each arm selects its imgui data type with an implicit selector so this file never spells an
// imgui type name, which is how the rest of the package refers to the binding.
@(private)
draw_inline_vector :: proc(
	name: string,
	data: rawptr,
	elem: ^runtime.Type_Info,
	count: int,
	info: Draw_Info,
) -> (
	changed: bool,
	handled: bool,
) {
	if count < 2 || count > 4 {
		return false, false
	}

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	label := fmt.ctprint(name)
	components := i32(count)

	// A colour is the one case where the generic row is the wrong widget entirely.
	if .Colour in info.flags && reflect.is_float(elem) && elem.size == 4 {
		switch count {
		case 3:
			return imgui.ColorEdit3(label, (^[3]f32)(data)), true
		case 4:
			return imgui.ColorEdit4(label, (^[4]f32)(data)), true
		}
	}

	speed := f32(info.speed) if .Has_Speed in info.flags else 0.05
	low, high := bounds_f32(info)

	#partial switch elem_info in elem.variant {
	case runtime.Type_Info_Float:
		// Dragging suits spatial values, which is what most small float vectors are.
		switch elem.size {
		case 4: changed = imgui.DragScalarN(label, .Float, data, components, speed, low, high)
		case 8: changed = imgui.DragScalarN(label, .Double, data, components, speed, low, high)
		case: return false, false
		}
		if changed && .Normalized in info.flags {
			normalize_floats(data, elem.size, count)
		}
		return changed, true
	case runtime.Type_Info_Integer:
		// Integers step rather than slide so they stay exact.
		switch elem.size {
		case 1: return imgui.InputScalarN(label, elem_info.signed ? .S8 : .U8, data, components), true
		case 2: return imgui.InputScalarN(label, elem_info.signed ? .S16 : .U16, data, components), true
		case 4: return imgui.InputScalarN(label, elem_info.signed ? .S32 : .U32, data, components), true
		case 8: return imgui.InputScalarN(label, elem_info.signed ? .S64 : .U64, data, components), true
		}
	}
	return false, false
}

// imgui takes bounds as pointers and treats min >= max as "unbounded", so an absent tag has to be
// a nil pointer rather than a zero.
@(private)
bounds_f32 :: proc(info: Draw_Info) -> (low: rawptr, high: rawptr) {
	@(static) low_value, high_value: f32
	if .Has_Min in info.flags {
		low_value = f32(info.min)
		low = &low_value
	}
	if .Has_Max in info.flags {
		high_value = f32(info.max)
		high = &high_value
	}
	return
}

@(private)
normalize_floats :: proc(data: rawptr, elem_size: int, count: int) {
	if elem_size == 4 {
		values := ([^]f32)(data)[:count]
		length := f32(0)
		for v in values {
			length += v * v
		}
		if length <= 0 {
			return
		}
		length = math.sqrt(length)
		for &v in values {
			v /= length
		}
		return
	}
	values := ([^]f64)(data)[:count]
	length := f64(0)
	for v in values {
		length += v * v
	}
	if length <= 0 {
		return
	}
	length = math.sqrt(length)
	for &v in values {
		v /= length
	}
}

@(private)
draw_array_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Array)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	inline_info := type_info_of(value.id).variant.(reflect.Type_Info_Array)
	if edited, handled := draw_inline_vector(
		name,
		value.data,
		inline_info.elem,
		inline_info.count,
		info,
	); handled {
		return edited
	}

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		array_info := type_info_of(value.id).variant.(reflect.Type_Info_Array)
		for idx in 0..<array_info.count {
			changed |= draw_value(fmt.tprint(idx), any{rawptr(uintptr(value.data) + uintptr(array_info.elem.size * idx)), array_info.elem.id}, info)
		}
	}
	return
}

@(private)
draw_slice_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Slice)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		slice_info := type_info_of(value.id).variant.(reflect.Type_Info_Slice)
		raw_slice := (^runtime.Raw_Slice)(value.data)
		bytes := ([^]byte)(raw_slice.data)
		
		for idx in 0..<raw_slice.len {
			changed |= draw_value(fmt.tprint(idx), any{&bytes[idx * slice_info.elem_size], slice_info.elem.id}, info)
		}
	}
	return
}

@(private)
draw_enum_array_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Enumerated_Array)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		array_info := type_info_of(value.id).variant.(reflect.Type_Info_Enumerated_Array)
		// TODO: Implement.
	}
	return
}

@(private)
draw_dyn_array_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Dynamic_Array)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		array_info := type_info_of(value.id).variant.(reflect.Type_Info_Dynamic_Array)
		raw_array := (^runtime.Raw_Dynamic_Array)(value.data)
		bytes := ([^]byte)(raw_array.data)
		
		for idx in 0..<raw_array.len {
			changed |= draw_value(fmt.tprint(idx), any{&bytes[array_info.elem_size * idx], array_info.elem.id}, info)
		}
	}
	return
}

@(private)
draw_fixed_capacity_dyn_array_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Fixed_Capacity_Dynamic_Array)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		array_info := type_info_of(value.id).variant.(reflect.Type_Info_Fixed_Capacity_Dynamic_Array)
		bytes := ([^]byte)(value.data)

		// Unlike a dynamic array there is no header: the elements are stored inline and the length
		// sits after them, which is why this reads through len_offset rather than a Raw_ struct.
		length := (^int)(&bytes[array_info.len_offset])^

		imgui.TextEx(fmt.ctprintf("len %v / cap %v", length, array_info.capacity))
		for idx in 0 ..< length {
			changed |= draw_value(fmt.tprint(idx), any{&bytes[array_info.elem_size * idx], array_info.elem.id}, info)
		}
	}
	return
}

@(private)
draw_multi_pointer_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Multi_Pointer)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	imgui.BeginDisabled(.Read_Only in info.flags)
	defer imgui.EndDisabled()

	changed = draw_pointer_type(name, any{value.data, typeid_of(rawptr)}, {})
	return
}

@(private)
draw_simd_vec_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Simd_Vector)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		vector_info := type_info_of(value.id).variant.(reflect.Type_Info_Simd_Vector)
		bytes := ([^]byte)(value.data)
		for idx in 0..<vector_info.count {
			changed |= draw_value(fmt.tprint(idx), any{&bytes[vector_info.elem_size * idx], vector_info.elem.id}, info)
		}
	}
	return
}

// TODO: What's this even meant to represent?
// How should we display this?
@(private)
draw_soa_pointer_type :: proc(name: string, value: any, info: Draw_Info) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Soa_Pointer)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		raw_soa := (^runtime.Raw_Soa_Pointer)(value.data)
		soa_info := type_info_of(value.id).variant.(reflect.Type_Info_Soa_Pointer)
	}
	return
}

// What should this even do? I'll just write the proc address.
// Maybe we can make the proc callable with struct tags.
@(private)
draw_proc_type :: proc(name: string, value: any, info: Draw_Info, ptr: rawptr = nil) -> (changed: bool) {
	assert_kind(reflect.type_kind(value.id), .Procedure)

	imgui.PushIDPtr(value.data)
	defer imgui.PopID()

	if imgui.TreeNode(fmt.ctprint(name)) {
		defer imgui.TreePop()

		imgui.Text(fmt.ctprintf("%v proc address", (^rawptr)(value.data)^))

		if .Callable in info.flags {
			proc_info := type_info_of(value.id).variant.(reflect.Type_Info_Procedure)
			if proc_info.params != nil {
				param_info := proc_info.params.variant.(reflect.Type_Info_Parameters)
				if len(param_info.types) == 1 && param_info.types[0].id == rawptr {
					imgui.SameLine()
					if imgui.Button("call") {
						(^proc(rawptr))(value.data)^(ptr)
						changed = true
					}
				}
			}
		}
	}
	return
}

