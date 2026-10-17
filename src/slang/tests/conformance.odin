package slang_tests

import "core:fmt"
import "core:strings"
import "core:testing"

import slang "../"

CONFORMANCE_SHADER :: #load("conformance.slang", string)

when ODIN_OS == .Windows {
	SPIRV_TOOLS_DIR :: #config(SLANG_LIB_DIR, "")
	#assert(SPIRV_TOOLS_DIR != "", "the conformance tests validate with the SPIRV-Tools built with Slang; run them with -define:SLANG_LIB_DIR=../../libs")
	foreign import spirv_tools {
		"../" + SPIRV_TOOLS_DIR + "/SPIRV-Tools.lib",
	}
} else {
	foreign import spirv_tools "system:SPIRV-Tools-shared"
}

SPV_ENV_VULKAN_1_4 :: 26

Spv_Context :: distinct rawptr

Spv_Diagnostic :: struct {
	position:       struct {
		line, column, index: uint,
	},
	error:          cstring,
	is_text_source: bool,
}

@(default_calling_convention = "c")
foreign spirv_tools {
	spvContextCreate :: proc(env: i32) -> Spv_Context ---
	spvContextDestroy :: proc(spirv_context: Spv_Context) ---
	spvValidateBinary :: proc(spirv_context: Spv_Context, words: [^]u32, word_count: uint, diagnostic: ^^Spv_Diagnostic) -> i32 ---
	spvDiagnosticDestroy :: proc(diagnostic: ^Spv_Diagnostic) ---
}

Spirv_Op :: enum u32 {
	Name                        = 5,
	Member_Name                 = 6,
	Capability                  = 17,
	Type_Vector                 = 23,
	Type_Matrix                 = 24,
	Type_Array                  = 28,
	Type_Runtime_Array          = 29,
	Type_Struct                 = 30,
	Type_Pointer                = 32,
	Load                        = 61,
	Decorate                    = 71,
	Member_Decorate             = 72,
	Type_Untyped_Pointer        = 4417,
	Untyped_Variable            = 4418,
	Untyped_Access_Chain        = 4419,
	Untyped_In_Bounds_Access    = 4420,
	Untyped_Pointer_Access      = 4423,
	Buffer_Pointer              = 5119,
}

SPIRV_DECORATION_ROW_MAJOR :: 4
SPIRV_DECORATION_ARRAY_STRIDE :: 6
SPIRV_DECORATION_MATRIX_STRIDE :: 7
SPIRV_DECORATION_OFFSET :: 35

SPIRV_CAPABILITY_DEMOTE_TO_HELPER_INVOCATION :: 5379

Spirv_Type :: struct {
	op:       Spirv_Op,
	operands: []u32,
}

Spirv_Member :: struct {
	struct_id, index: u32,
}

Spirv_Module :: struct {
	names:                map[u32]string,
	member_names:         map[Spirv_Member]string,
	types:                map[u32]Spirv_Type,
	offsets:              map[Spirv_Member]u32,
	matrix_strides:       map[Spirv_Member]u32,
	row_major:            map[Spirv_Member]bool,
	array_strides:        map[u32]u32,
	capabilities:         [dynamic]u32,
	untyped_pointers:     map[u32]bool,
	untyped_matrix_loads: int,
}

Expected_Member :: struct {
	name:          string,
	offset:        u32,
	array_stride:  u32,
	matrix_stride: u32,
}

PUSH_LAYOUT :: []Expected_Member {
	{name = "header", offset = 0},
	{name = "bones", offset = 16},
	{name = "camera", offset = 24},
	{name = "textures", offset = 32, array_stride = 8},
	{name = "tint", offset = 48},
	{name = "mode", offset = 60},
	{name = "model", offset = 64, matrix_stride = 16},
	{name = "output", offset = 128},
}

BONE_LAYOUT :: []Expected_Member {
	{name = "position", offset = 0},
	{name = "radius", offset = 12},
	{name = "transform", offset = 16, matrix_stride = 16},
	{name = "uv", offset = 80},
	{name = "flags", offset = 88},
}

BONE_STRIDE :: 96

CAMERA_LAYOUT :: []Expected_Member {
	{name = "view_projection", offset = 0, matrix_stride = 16},
	{name = "position", offset = 64},
	{name = "exposure", offset = 76},
	{name = "weights", offset = 80, array_stride = 16},
	{name = "jitter", offset = 128},
}

compile_conformance :: proc(t: ^testing.T, entry_point: string) -> []u32 {
	global := make_test_global_session(t)
	defer slang.release(global)
	result := compile_test_shader(global, CONFORMANCE_SHADER, entry_point)
	if !result.ok {
		testing.fail_now(t, fmt.tprintf("%v did not compile: %v", entry_point, result.diagnostics))
	}
	return result.spirv
}

validate_spirv :: proc(spirv: []u32) -> (error: string, valid: bool) {
	spirv_context := spvContextCreate(SPV_ENV_VULKAN_1_4)
	defer spvContextDestroy(spirv_context)
	diagnostic: ^Spv_Diagnostic
	defer spvDiagnosticDestroy(diagnostic)
	if spvValidateBinary(spirv_context, raw_data(spirv), uint(len(spirv)), &diagnostic) == 0 {
		return "", true
	}
	if diagnostic != nil {
		error = strings.clone(string(diagnostic.error), context.temp_allocator)
	}
	return error, false
}

expect_valid :: proc(t: ^testing.T, spirv: []u32, loc := #caller_location) {
	error, valid := validate_spirv(spirv)
	testing.expectf(t, valid, "spirv-val rejects Slang's output: %v", error, loc = loc)
}

parse_spirv :: proc(spirv: []u32) -> (module: Spirv_Module) {
	module.names = make(map[u32]string, context.temp_allocator)
	module.member_names = make(map[Spirv_Member]string, context.temp_allocator)
	module.types = make(map[u32]Spirv_Type, context.temp_allocator)
	module.offsets = make(map[Spirv_Member]u32, context.temp_allocator)
	module.matrix_strides = make(map[Spirv_Member]u32, context.temp_allocator)
	module.row_major = make(map[Spirv_Member]bool, context.temp_allocator)
	module.array_strides = make(map[u32]u32, context.temp_allocator)
	module.capabilities = make([dynamic]u32, context.temp_allocator)
	module.untyped_pointers = make(map[u32]bool, context.temp_allocator)

	literal :: proc(words: []u32) -> string {
		return strings.clone(string(cstring(([^]u8)(raw_data(words)))), context.temp_allocator)
	}

	for i := 5; i < len(spirv); {
		word_count := int(spirv[i] >> 16)
		if word_count == 0 || i + word_count > len(spirv) {
			break
		}
		op := Spirv_Op(spirv[i] & 0xffff)
		operands := spirv[i + 1:i + word_count]
		i += word_count

		#partial switch op {
		case .Name:
			module.names[operands[0]] = literal(operands[1:])
		case .Member_Name:
			module.member_names[{operands[0], operands[1]}] = literal(operands[2:])
		case .Capability:
			append(&module.capabilities, operands[0])
		case .Type_Vector, .Type_Matrix, .Type_Array, .Type_Runtime_Array, .Type_Struct, .Type_Pointer, .Type_Untyped_Pointer:
			module.types[operands[0]] = {op, operands[1:]}
		case .Decorate:
			if operands[1] == SPIRV_DECORATION_ARRAY_STRIDE {
				module.array_strides[operands[0]] = operands[2]
			}
		case .Member_Decorate:
			member := Spirv_Member{operands[0], operands[1]}
			switch operands[2] {
			case SPIRV_DECORATION_OFFSET:
				module.offsets[member] = operands[3]
			case SPIRV_DECORATION_MATRIX_STRIDE:
				module.matrix_strides[member] = operands[3]
			case SPIRV_DECORATION_ROW_MAJOR:
				module.row_major[member] = true
			}
		case .Untyped_Variable, .Untyped_Access_Chain, .Untyped_In_Bounds_Access, .Untyped_Pointer_Access, .Buffer_Pointer:
			if type, known := module.types[operands[0]]; known && type.op == .Type_Untyped_Pointer {
				module.untyped_pointers[operands[1]] = true
			}
		case .Load:
			if module.untyped_pointers[operands[2]] && contains_matrix(module, operands[0]) {
				module.untyped_matrix_loads += 1
			}
		}
	}
	return
}

contains_matrix :: proc(module: Spirv_Module, type_id: u32) -> bool {
	type, known := module.types[type_id]
	if !known {
		return false
	}
	#partial switch type.op {
	case .Type_Matrix:
		return true
	case .Type_Array, .Type_Runtime_Array:
		return contains_matrix(module, type.operands[0])
	case .Type_Struct:
		for member in type.operands {
			if contains_matrix(module, member) {
				return true
			}
		}
	}
	return false
}

array_stride :: proc(module: Spirv_Module, type_id: u32) -> u32 {
	type := module.types[type_id]
	#partial switch type.op {
	case .Type_Array, .Type_Runtime_Array:
		return module.array_strides[type_id]
	case .Type_Struct:
		if len(type.operands) == 1 && module.offsets[{type_id, 0}] == 0 {
			return array_stride(module, type.operands[0])
		}
	}
	return 0
}

find_struct :: proc(t: ^testing.T, module: Spirv_Module, name: string) -> (id: u32, members: []u32) {
	for type_id, type_name in module.names {
		if type, known := module.types[type_id]; known && type_name == name && type.op == .Type_Struct {
			return type_id, type.operands
		}
	}
	testing.fail_now(t, fmt.tprintf("Slang's output has no struct named %v", name))
}

expect_struct_layout :: proc(t: ^testing.T, module: Spirv_Module, name: string, expected: []Expected_Member, loc := #caller_location) {
	struct_id, members := find_struct(t, module, name)
	testing.expectf(t, len(members) == len(expected), "%v has %v members, expected %v", name, len(members), len(expected), loc = loc)
	for want, index in expected {
		if index >= len(members) {
			break
		}
		member := Spirv_Member{struct_id, u32(index)}
		testing.expectf(t, module.member_names[member] == want.name, "%v member %v is `%v`, expected `%v`", name, index, module.member_names[member], want.name, loc = loc)
		testing.expectf(t, module.offsets[member] == want.offset, "%v.%v is at byte %v, expected %v", name, want.name, module.offsets[member], want.offset, loc = loc)
		if want.array_stride != 0 {
			stride := array_stride(module, members[index])
			testing.expectf(t, stride == want.array_stride, "%v.%v has array stride %v, expected %v", name, want.name, stride, want.array_stride, loc = loc)
		}
		if want.matrix_stride != 0 {
			stride := module.matrix_strides[member]
			testing.expectf(t, stride == want.matrix_stride, "%v.%v has matrix stride %v, expected %v", name, want.name, stride, want.matrix_stride, loc = loc)
			testing.expectf(t, module.row_major[member], "%v.%v is not RowMajor, so it does not match the memory of an Odin matrix", name, want.name, loc = loc)
		}
	}
}

expect_element_stride :: proc(t: ^testing.T, module: Spirv_Module, name: string, stride: u32, loc := #caller_location) {
	struct_id, _ := find_struct(t, module, name)
	for type_id, type in module.types {
		if type.op == .Type_Runtime_Array && type.operands[0] == struct_id {
			testing.expectf(t, module.array_strides[type_id] == stride, "an array of %v has stride %v, expected %v", name, module.array_strides[type_id], stride, loc = loc)
			return
		}
	}
	testing.fail_now(t, fmt.tprintf("Slang's output has no runtime array of %v", name), loc)
}

@(test)
push_data_layout :: proc(t: ^testing.T) {
	spirv := compile_conformance(t, "push_data")
	expect_valid(t, spirv)
	expect_struct_layout(t, parse_spirv(spirv), "Push_std430", PUSH_LAYOUT)
}

@(test)
structured_buffer_layout :: proc(t: ^testing.T) {
	spirv := compile_conformance(t, "structured_buffer")
	expect_valid(t, spirv)
	module := parse_spirv(spirv)
	expect_struct_layout(t, module, "Bone_std430", BONE_LAYOUT)
	expect_element_stride(t, module, "Bone_std430", BONE_STRIDE)
}

@(test)
constant_buffer_layout :: proc(t: ^testing.T) {
	spirv := compile_conformance(t, "constant_buffer")
	expect_valid(t, spirv)
	module := parse_spirv(spirv)
	expect_struct_layout(t, module, "Camera_std140", CAMERA_LAYOUT)
	testing.expect(t, module.untyped_matrix_loads == 0, "reading scalars and vectors from a ConstantBuffer loads a matrix through an untyped pointer")
}

@(test)
discard_needs_demote_to_helper_invocation :: proc(t: ^testing.T) {
	spirv := compile_conformance(t, "discard_fragment")
	expect_valid(t, spirv)
	module := parse_spirv(spirv)
	declared := false
	for capability in module.capabilities {
		declared ||= capability == SPIRV_CAPABILITY_DEMOTE_TO_HELPER_INVOCATION
	}
	testing.expect(t, declared, "discard no longer declares DemoteToHelperInvocation; shaders using it may not need shaderDemoteToHelperInvocation enabled any more")
}

@(test)
known_bug_constant_buffer_matrix_loads_through_untyped_pointer :: proc(t: ^testing.T) {
	spirv := compile_conformance(t, "constant_buffer_matrix")
	expect_valid(t, spirv)
	testing.expect(
		t,
		parse_spirv(spirv).untyped_matrix_loads > 0,
		"FIXED: a ConstantBuffer matrix no longer loads through an untyped pointer; revert the float4[4] workaround in examples/lighting/Lighting.slang and the Creature Builder's Builder_Body.slang, then rename this test",
	)
}

@(test)
known_bug_constant_buffer_array_argument_is_invalid :: proc(t: ^testing.T) {
	spirv := compile_conformance(t, "constant_buffer_array_argument")
	_, valid := validate_spirv(spirv)
	testing.expect(
		t,
		!valid,
		"FIXED: passing a ConstantBuffer array to a function is valid SPIR-V now; arrays can be handed to helper procedures again, then rename this test",
	)
}
