package slang

import "core:mem"
import "core:strings"
import "core:testing"

when ODIN_TEST {
	TEST_SHADER_SEARCH_PATH :: #directory + "/../shaders"

	TEST_COMPUTE_SHADER :: `
RWStructuredBuffer<uint> output;

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
	output[0] = 7;
}
`

	Test_Compile :: struct {
		spirv:       []u32,
		diagnostics: string,
		ok:          bool,
	}

	make_test_global_session :: proc(t: ^testing.T) -> ^Global_Session {
		desc := global_session_desc_default()
		global, ok := create_global_session2(&desc)
		if !ok {
			testing.fail_now(t, "Slang's global session could not be created")
		}
		return global
	}

	test_blob_text :: proc(blob: ^Blob) -> string {
		if blob == nil || get_buffer_size(blob) == 0 {
			return ""
		}
		return strings.clone(strings.string_from_ptr(([^]u8)(get_buffer_pointer(blob)), int(get_buffer_size(blob))), context.temp_allocator)
	}

	compile_test_shader :: proc(global: ^Global_Session, source: string, entry_point: string) -> (result: Test_Compile) {
		heap_capability := find_capability(global, "spvDescriptorHeapEXT")
		target_options := []Compiler_Option_Entry {
			{name = .Capability, value = {kind = .Int, intValue0 = i32(heap_capability)}},
			{name = .VulkanUseEntryPointName, value = {kind = .Int, intValue0 = 1}},
		}
		target := target_desc_default()
		target.format = .SPIRV
		target.profile = find_profile(global, "spirv_1_6")
		target.compilerOptionEntries = raw_data(target_options)
		target.compilerOptionEntryCount = u32(len(target_options))

		search_paths := []cstring{TEST_SHADER_SEARCH_PATH}
		session_desc := session_desc_default()
		session_desc.targets = &target
		session_desc.targetCount = 1
		session_desc.defaultMatrixLayoutMode = .COLUMN_MAJOR
		session_desc.searchPaths = raw_data(search_paths)
		session_desc.searchPathCount = Int(len(search_paths))

		session, session_ok := create_session(global, &session_desc)
		if !session_ok {
			result.diagnostics = "A Slang session could not be created"
			return
		}
		defer release(session)

		module, module_diagnostics, module_ok := load_module_from_source_string(
			session,
			"test_shader",
			"test_shader.slang",
			strings.clone_to_cstring(source, context.temp_allocator),
		)
		defer release(module_diagnostics)
		result.diagnostics = test_blob_text(module_diagnostics)
		if !module_ok {
			return
		}

		entry, found := find_entry_point_by_name(module, strings.clone_to_cstring(entry_point, context.temp_allocator))
		if !found {
			result.diagnostics = strings.concatenate({"Entry point not found: ", entry_point}, context.temp_allocator)
			return
		}
		defer release(entry)

		components := []^Component_Type{module, entry}
		program, program_diagnostics, program_ok := create_composite_component_type(session, components)
		defer release(program_diagnostics)
		if !program_ok {
			result.diagnostics = test_blob_text(program_diagnostics)
			return
		}
		defer release(program)

		linked, link_diagnostics, link_ok := link(program)
		defer release(link_diagnostics)
		if !link_ok {
			result.diagnostics = test_blob_text(link_diagnostics)
			return
		}
		defer release(linked)

		code, code_diagnostics, code_ok := get_target_code(linked, 0)
		defer release(code_diagnostics)
		if !code_ok {
			result.diagnostics = test_blob_text(code_diagnostics)
			return
		}
		defer release(code)

		size := int(get_buffer_size(code))
		result.spirv = make([]u32, size / size_of(u32), context.temp_allocator)
		mem.copy(raw_data(result.spirv), get_buffer_pointer(code), size)
		result.ok = size > 0 && size % size_of(u32) == 0
		return
	}

	@(test)
	global_session_reports_its_build :: proc(t: ^testing.T) {
		global := make_test_global_session(t)
		defer release(global)
		testing.expect(t, get_build_tag_string(global) != "", "the global session has no build tag")
	}

	@(test)
	descriptor_heap_capability_is_known :: proc(t: ^testing.T) {
		global := make_test_global_session(t)
		defer release(global)
		testing.expect(t, find_capability(global, "spvDescriptorHeapEXT") != 0, "Slang does not know spvDescriptorHeapEXT; Valhalla cannot compile shaders")
	}

	@(test)
	spirv_profile_is_known :: proc(t: ^testing.T) {
		global := make_test_global_session(t)
		defer release(global)
		testing.expect(t, find_profile(global, "spirv_1_6") != 0, "Slang does not know the spirv_1_6 profile")
	}

	@(test)
	module_compiles_to_spirv :: proc(t: ^testing.T) {
		global := make_test_global_session(t)
		defer release(global)
		result := compile_test_shader(global, TEST_COMPUTE_SHADER, "main")
		testing.expectf(t, result.ok, "compilation failed: %v", result.diagnostics)
		testing.expect(t, len(result.spirv) > 5 && result.spirv[0] == 0x07230203, "the code is not SPIR-V")
	}

	@(test)
	missing_entry_points_are_not_found :: proc(t: ^testing.T) {
		global := make_test_global_session(t)
		defer release(global)
		result := compile_test_shader(global, TEST_COMPUTE_SHADER, "missing")
		testing.expect(t, !result.ok, "a missing entry point compiled")
	}
}
