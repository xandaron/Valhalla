package slang

// A session provides a scope for loaded/compiled code: active search paths,
// global preprocessor definitions, and a list of compilation targets.
//
// Code loaded and compiled within a session is owned by the session and
// stays resident until the session is released. Use multiple sessions to
// control the memory usage of compiled/loaded code independently.
@(private)
Session :: struct #raw_union {
	#subtype unknown: Unknown,
	using vtable:     ^Session_VTable,
}

@(private="file")
Session_VTable :: struct {
	QueryInterface: proc "system" (this: ^Unknown, uuid: ^UUID, out_object: ^rawptr) -> Result,
	AddRef:         proc "system" (this: ^Unknown) -> u32,
	Release:        proc "system" (this: ^Unknown) -> u32,

	// Get the global session that was used to create this session.
	GetGlobalSession: proc "system" (this: ^Session) -> ^Global_Session,

	// Load a module as it would be by code using `import`.
	LoadModule: proc "system" (this: ^Session, module_name: cstring, out_diagnostics: ^^Blob) -> ^Module,

	// Load a module from Slang source code. If `source` is nil and `path`
	// names a readable file, the module is loaded from that file's contents.
	LoadModuleFromSource: proc "system" (this: ^Session, module_name: cstring, path: cstring, source: ^Blob, out_diagnostics: ^^Blob) -> ^Module,

	// Combine multiple component types (modules, entry points, ...) into a
	// composite component type. See slang.h for the full semantics around
	// parameter/requirement ordering and deduplication.
	CreateCompositeComponentType: proc "system" (this: ^Session, component_types: [^]^Component_Type, component_type_count: Int, out_composite_component_type: ^^Component_Type, out_diagnostics: ^^Blob) -> Result,

	// Specialize a type based on type arguments.
	SpecializeType: proc "system" (this: ^Session, type: ^Type_Reflection, specialization_args: [^]Specialization_Arg, specialization_arg_count: Int, out_diagnostics: ^^Blob) -> ^Type_Reflection,

	// Get the layout of `type` on the chosen `target_index`.
	GetTypeLayout: proc "system" (this: ^Session, type: ^Type_Reflection, target_index: Int, rules: Layout_Rules, out_diagnostics: ^^Blob) -> ^Type_Layout_Reflection,

	// Get a container type from `element_type`, e.g. T -> StructuredBuffer<T>.
	GetContainerType: proc "system" (this: ^Session, element_type: ^Type_Reflection, container_type: Container_Type, out_diagnostics: ^^Blob) -> ^Type_Reflection,

	// Returns a TypeReflection representing the `__Dynamic` type, usable as a
	// specialization argument to request dynamic dispatch.
	GetDynamicType: proc "system" (this: ^Session) -> ^Type_Reflection,

	GetTypeRTTIMangledName: proc "system" (this: ^Session, type: ^Type_Reflection, out_name_blob: ^^Blob) -> Result,

	GetTypeConformanceWitnessMangledName: proc "system" (this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection, out_name_blob: ^^Blob) -> Result,

	GetTypeConformanceWitnessSequentialID: proc "system" (this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection, out_id: ^u32) -> Result,

	// DEPRECATED.
	CreateCompileRequest: proc "system" (this: ^Session, out_compile_request: ^^Compile_Request) -> Result,

	// Creates a Component_Type representing a type's conformance to an
	// interface. Pass -1 for `conformance_id_override` to let Slang assign
	// dispatch IDs automatically.
	CreateTypeConformanceComponentType: proc "system" (this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection, out_conformance: ^^Type_Conformance, conformance_id_override: Int, out_diagnostics: ^^Blob) -> Result,

	// Load a module from a Slang module blob (a `.slang-module` container).
	LoadModuleFromIRBlob: proc "system" (this: ^Session, module_name: cstring, path: cstring, source: ^Blob, out_diagnostics: ^^Blob) -> ^Module,

	GetLoadedModuleCount: proc "system" (this: ^Session) -> Int,
	GetLoadedModule:      proc "system" (this: ^Session, index: Int) -> ^Module,

	IsBinaryModuleUpToDate: proc "system" (this: ^Session, module_path: cstring, binary_module_blob: ^Blob) -> Bool,

	// Load a module from a string.
	LoadModuleFromSourceString: proc "system" (this: ^Session, module_name: cstring, path: cstring, source_string: cstring, out_diagnostics: ^^Blob) -> ^Module,

	// Get the 16-byte RTTI header to fill into a dynamic object. See slang.h
	// for the full explanation and layout of the dynamic-object convention.
	GetDynamicObjectRTTIBytes: proc "system" (this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection, out_rtti_data_buffer: [^]u32, buffer_size_in_bytes: u32) -> Result,

	// Read module info (name and version) from a module blob. The returned
	// pointers are valid for as long as the session.
	LoadModuleInfoFromIRBlob: proc "system" (this: ^Session, source: ^Blob, out_module_version: ^Int, out_module_compiler_version: ^cstring, out_module_name: ^cstring) -> Result,

	// Get the source location of a declaration. The returned filePath
	// pointer is valid for as long as the session.
	GetDeclSourceLocation: proc "system" (this: ^Session, decl: ^Decl_Reflection, out_location: ^Source_Location) -> Result,
}

@(private="file")
Session_UUID := UUID{0x67618701, 0xd116, 0x468f, {0xab, 0x3b, 0x47, 0x4b, 0xed, 0xce, 0x0e, 0x3d}}

// Get the global session that was used to create this session.
get_global_session :: proc(this: ^Session) -> ^Global_Session {
	return this->GetGlobalSession()
}

// Load a module as it would be by code using `import`.
load_module :: proc(this: ^Session, module_name: cstring) -> (module: ^Module, diagnostics: ^Blob, ok: bool) {
	module = this->LoadModule(module_name, &diagnostics)
	ok = module != nil
	return
}

// Load a module from Slang source code. If `source` is nil and `path`
// names a readable file, the module is loaded from that file's contents.
load_module_from_source :: proc(this: ^Session, module_name: cstring, path: cstring, source: ^Blob) -> (module: ^Module, diagnostics: ^Blob, ok: bool) {
	module = this->LoadModuleFromSource(module_name, path, source, &diagnostics)
	ok = module != nil
	return
}

// Combine multiple component types (modules, entry points, ...) into a
// composite component type. See slang.h for the full semantics around
// parameter/requirement ordering and deduplication.
create_composite_component_type :: proc(this: ^Session, component_types: []^Component_Type) -> (composite: ^Component_Type, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->CreateCompositeComponentType(raw_data(component_types), len(component_types), &composite, &diagnostics))
	return
}

// Specialize a type based on type arguments.
specialize_type :: proc(this: ^Session, type: ^Type_Reflection, specialization_args: []Specialization_Arg) -> (specialized: ^Type_Reflection, diagnostics: ^Blob, ok: bool) {
	specialized = this->SpecializeType(type, raw_data(specialization_args), len(specialization_args), &diagnostics)
	ok = specialized != nil
	return
}

// Get the layout of `type` on the chosen `target_index`.
get_type_layout :: proc(this: ^Session, type: ^Type_Reflection, target_index: Int, rules: Layout_Rules) -> (layout: ^Type_Layout_Reflection, diagnostics: ^Blob, ok: bool) {
	layout = this->GetTypeLayout(type, target_index, rules, &diagnostics)
	ok = layout != nil
	return
}

// Get a container type from `element_type`, e.g. T -> StructuredBuffer<T>.
get_container_type :: proc(this: ^Session, element_type: ^Type_Reflection, container_type: Container_Type) -> (type: ^Type_Reflection, diagnostics: ^Blob, ok: bool) {
	type = this->GetContainerType(element_type, container_type, &diagnostics)
	ok = type != nil
	return
}

// Returns a TypeReflection representing the `__Dynamic` type, usable as a
// specialization argument to request dynamic dispatch.
get_dynamic_type :: proc(this: ^Session) -> ^Type_Reflection {
	return this->GetDynamicType()
}

get_type_rtti_mangled_name :: proc(this: ^Session, type: ^Type_Reflection) -> (name: ^Blob, ok: bool) {
	ok = succeeded(this->GetTypeRTTIMangledName(type, &name))
	return
}

get_type_conformance_witness_mangled_name :: proc(this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection) -> (name: ^Blob, ok: bool) {
	ok = succeeded(this->GetTypeConformanceWitnessMangledName(type, interface_type, &name))
	return
}

get_type_conformance_witness_sequential_id :: proc(this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection) -> (id: u32, ok: bool) {
	ok = succeeded(this->GetTypeConformanceWitnessSequentialID(type, interface_type, &id))
	return
}

@(private)
session_create_compile_request :: proc(this: ^Session) -> (compile_request: ^Compile_Request, ok: bool) {
	ok = succeeded(this->CreateCompileRequest(&compile_request))
	return
}

// Creates a Component_Type representing a type's conformance to an
// interface. Pass -1 for `conformance_id_override` to let Slang assign
// dispatch IDs automatically.
create_type_conformance_component_type :: proc(this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection, conformance_id_override: Int) -> (conformance: ^Type_Conformance, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->CreateTypeConformanceComponentType(type, interface_type, &conformance, conformance_id_override, &diagnostics))
	return
}

// Load a module from a Slang module blob (a `.slang-module` container).
load_module_from_ir_blob :: proc(this: ^Session, module_name: cstring, path: cstring, source: ^Blob) -> (module: ^Module, diagnostics: ^Blob, ok: bool) {
	module = this->LoadModuleFromIRBlob(module_name, path, source, &diagnostics)
	ok = module != nil
	return
}

get_loaded_module_count :: proc(this: ^Session) -> Int {
	return this->GetLoadedModuleCount()
}

get_loaded_module :: proc(this: ^Session, index: Int) -> (module: ^Module, ok: bool) {
	module = this->GetLoadedModule(index)
	ok = module != nil
	return
}

is_binary_module_up_to_date :: proc(this: ^Session, module_path: cstring, binary_module_blob: ^Blob) -> bool {
	return bool(this->IsBinaryModuleUpToDate(module_path, binary_module_blob))
}

// Load a module from a string.
load_module_from_source_string :: proc(this: ^Session, module_name: cstring, path: cstring, source_string: cstring) -> (module: ^Module, diagnostics: ^Blob, ok: bool) {
	module = this->LoadModuleFromSourceString(module_name, path, source_string, &diagnostics)
	ok = module != nil
	return
}

// Read module info (name and version) from a module blob. The returned
// strings are valid for as long as the session.
load_module_info_from_ir_blob :: proc(this: ^Session, source: ^Blob) -> (module_version: Int, module_compiler_version: cstring, module_name: cstring, ok: bool) {
	ok = succeeded(this->LoadModuleInfoFromIRBlob(source, &module_version, &module_compiler_version, &module_name))
	return
}

// Get the source location of a declaration. The returned filePath is valid
// for as long as the session.
get_decl_source_location :: proc(this: ^Session, decl: ^Decl_Reflection) -> (location: Source_Location, ok: bool) {
	ok = succeeded(this->GetDeclSourceLocation(decl, &location))
	return
}

// Get the 16-byte RTTI header to fill into a dynamic object. See slang.h for
// the full explanation and layout of the dynamic-object convention.
get_dynamic_object_rtti_bytes :: proc(this: ^Session, type: ^Type_Reflection, interface_type: ^Type_Reflection, rtti_data_buffer: [^]u32, buffer_size_in_bytes: u32) -> bool {
	return succeeded(this->GetDynamicObjectRTTIBytes(type, interface_type, rtti_data_buffer, buffer_size_in_bytes))
}
