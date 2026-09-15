package slang

// A logical unit of shader code: a module, an entry point, or a composite
// built from other component types via session.create_composite_component_type
// or component_type.link. Module and Entry_Point are both component types
// (see below) and can be passed anywhere a ^Component_Type is expected.
Component_Type :: struct #raw_union {
	#subtype unknown: Unknown,
	using vtable:     ^Component_Type_VTable,
}

@(private="file")
Component_Type_VTable :: struct {
	QueryInterface: proc "system" (this: ^Unknown, uuid: ^UUID, out_object: ^rawptr) -> Result,
	AddRef:         proc "system" (this: ^Unknown) -> u32,
	Release:        proc "system" (this: ^Unknown) -> u32,

	// Get the session this component type belongs to.
	GetSession: proc "system" (this: ^Component_Type) -> ^Session,

	// Get the (possibly incomplete, if unspecialized) layout for `target_index`.
	GetLayout: proc "system" (this: ^Component_Type, target_index: Int, out_diagnostics: ^^Blob) -> ^Program_Layout,

	GetSpecializationParamCount: proc "system" (this: ^Component_Type) -> Int,

	// Get compiled code for the entry point at `entry_point_index` for
	// `target_index`. Requires a component type that is fully specialized
	// and fully linked (see Link below).
	GetEntryPointCode: proc "system" (this: ^Component_Type, entry_point_index: Int, target_index: Int, out_code: ^^Blob, out_diagnostics: ^^Blob) -> Result,

	// Get the compilation result as an in-memory file system.
	GetResultAsFileSystem: proc "system" (this: ^Component_Type, entry_point_index: Int, target_index: Int, out_file_system: ^^Slang_Mutable_File_System) -> Result,

	// Hash of all dependencies plus target settings; usable as a shader-cache key.
	GetEntryPointHash: proc "system" (this: ^Component_Type, entry_point_index: Int, target_index: Int, out_hash: ^^Blob),

	// Bind specialization parameters to concrete type/value arguments.
	Specialize: proc "system" (this: ^Component_Type, specialization_args: [^]Specialization_Arg, specialization_arg_count: Int, out_specialized_component_type: ^^Component_Type, out_diagnostics: ^^Blob) -> Result,

	// Link against all unsatisfied dependencies (e.g. a module's imports, or
	// an entry point's defining module), producing a fully linked program
	// suitable for GetEntryPointCode/GetTargetCode.
	Link: proc "system" (this: ^Component_Type, out_linked_component_type: ^^Component_Type, out_diagnostics: ^^Blob) -> Result,

	// Requires a compilation target of SLANG_HOST_CALLABLE.
	GetEntryPointHostCallable: proc "system" (this: ^Component_Type, entry_point_index: i32, target_index: i32, out_shared_library: ^^Slang_Shared_Library, out_diagnostics: ^^Blob) -> Result,

	RenameEntryPoint: proc "system" (this: ^Component_Type, new_name: cstring, out_entry_point: ^^Component_Type) -> Result,

	// Link and specify additional compiler options for code generation.
	LinkWithOptions: proc "system" (this: ^Component_Type, out_linked_component_type: ^^Component_Type, compiler_option_entry_count: u32, compiler_option_entries: [^]Compiler_Option_Entry, out_diagnostics: ^^Blob) -> Result,

	GetTargetCode: proc "system" (this: ^Component_Type, target_index: Int, out_code: ^^Blob, out_diagnostics: ^^Blob) -> Result,

	GetTargetMetadata: proc "system" (this: ^Component_Type, target_index: Int, out_metadata: ^^Metadata, out_diagnostics: ^^Blob) -> Result,

	GetEntryPointMetadata: proc "system" (this: ^Component_Type, entry_point_index: Int, target_index: Int, out_metadata: ^^Metadata, out_diagnostics: ^^Blob) -> Result,
}

@(private="file")
Component_Type_UUID := UUID{0x5bc42be8, 0x5c50, 0x4929, {0x9e, 0x5e, 0xd1, 0x5e, 0x7c, 0x24, 0x01, 0x5f}}

// Get the session this component type belongs to.
get_session :: proc(this: ^Component_Type) -> ^Session {
	return this->GetSession()
}

// Get the (possibly incomplete, if unspecialized) layout for `target_index`.
get_layout :: proc(this: ^Component_Type, target_index: Int) -> (layout: ^Program_Layout, diagnostics: ^Blob, ok: bool) {
	layout = this->GetLayout(target_index, &diagnostics)
	ok = layout != nil
	return
}

get_specialization_param_count :: proc(this: ^Component_Type) -> Int {
	return this->GetSpecializationParamCount()
}

// Get compiled code for the entry point at `entry_point_index` for
// `target_index`. Requires a component type that is fully specialized and
// fully linked (see link below).
get_entry_point_code :: proc(this: ^Component_Type, entry_point_index: Int, target_index: Int) -> (code: ^Blob, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->GetEntryPointCode(entry_point_index, target_index, &code, &diagnostics))
	return
}

// Get the compilation result as an in-memory file system.
get_result_as_file_system :: proc(this: ^Component_Type, entry_point_index: Int, target_index: Int) -> (file_system: ^Slang_Mutable_File_System, ok: bool) {
	ok = succeeded(this->GetResultAsFileSystem(entry_point_index, target_index, &file_system))
	return
}

// Hash of all dependencies plus target settings; usable as a shader-cache key.
get_entry_point_hash :: proc(this: ^Component_Type, entry_point_index: Int, target_index: Int) -> (hash: ^Blob, ok: bool) {
	this->GetEntryPointHash(entry_point_index, target_index, &hash)
	ok = hash != nil
	return
}

// Bind specialization parameters to concrete type/value arguments.
specialize :: proc(this: ^Component_Type, specialization_args: []Specialization_Arg) -> (specialized: ^Component_Type, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->Specialize(raw_data(specialization_args), len(specialization_args), &specialized, &diagnostics))
	return
}

// Link against all unsatisfied dependencies (e.g. a module's imports, or an
// entry point's defining module), producing a fully linked program suitable
// for get_entry_point_code/get_target_code.
link :: proc(this: ^Component_Type) -> (linked: ^Component_Type, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->Link(&linked, &diagnostics))
	return
}

// Requires a compilation target of SLANG_HOST_CALLABLE.
get_entry_point_host_callable :: proc(this: ^Component_Type, entry_point_index: i32, target_index: i32) -> (shared_library: ^Slang_Shared_Library, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->GetEntryPointHostCallable(entry_point_index, target_index, &shared_library, &diagnostics))
	return
}

rename_entry_point :: proc(this: ^Component_Type, new_name: cstring) -> (entry_point: ^Component_Type, ok: bool) {
	ok = succeeded(this->RenameEntryPoint(new_name, &entry_point))
	return
}

// Link and specify additional compiler options for code generation.
link_with_options :: proc(this: ^Component_Type, compiler_option_entries: []Compiler_Option_Entry) -> (linked: ^Component_Type, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->LinkWithOptions(&linked, u32(len(compiler_option_entries)), raw_data(compiler_option_entries), &diagnostics))
	return
}

get_target_code :: proc(this: ^Component_Type, target_index: Int) -> (code: ^Blob, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->GetTargetCode(target_index, &code, &diagnostics))
	return
}

get_target_metadata :: proc(this: ^Component_Type, target_index: Int) -> (metadata: ^Metadata, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->GetTargetMetadata(target_index, &metadata, &diagnostics))
	return
}

get_entry_point_metadata :: proc(this: ^Component_Type, entry_point_index: Int, target_index: Int) -> (metadata: ^Metadata, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->GetEntryPointMetadata(entry_point_index, target_index, &metadata, &diagnostics))
	return
}

// A module is the granularity of shader code compilation and loading -
// typically a single `.slang`/`.hlsl` file plus everything it `#include`s.
// Things it `import`s remain distinct modules in the same session.
@(private)
Module :: struct #raw_union {
	#subtype component_type: Component_Type,
	using vtable:            ^Module_VTable,
}

@(private="file")
Module_VTable :: struct {
	using component_type_vtable: Component_Type_VTable,

	// Find an entry point by name. Does not work for functions that aren't
	// explicitly marked with a `[shader("...")]` attribute - for those, use
	// FindAndCheckEntryPoint instead.
	FindEntryPointByName: proc "system" (this: ^Module, name: cstring, out_entry_point: ^^Entry_Point) -> Result,

	// Entry points defined in a module aren't part of its linkage by default,
	// so Component_Type.GetSpecializationParamCount-style entry-point counts
	// on the module itself stay 0; these two report the module's own defined
	// entry points instead.
	GetDefinedEntryPointCount: proc "system" (this: ^Module) -> i32,
	GetDefinedEntryPoint:      proc "system" (this: ^Module, index: i32, out_entry_point: ^^Entry_Point) -> Result,

	Serialize:   proc "system" (this: ^Module, out_serialized_blob: ^^Blob) -> Result,
	WriteToFile: proc "system" (this: ^Module, file_name: cstring) -> Result,

	GetName:           proc "system" (this: ^Module) -> cstring,
	GetFilePath:       proc "system" (this: ^Module) -> cstring,
	GetUniqueIdentity: proc "system" (this: ^Module) -> cstring,

	// Find and validate an entry point by name, even without a
	// `[shader("...")]` attribute. This is what a "give me entry point X for
	// stage Y" workflow should call.
	FindAndCheckEntryPoint: proc "system" (this: ^Module, name: cstring, stage: Stage, out_entry_point: ^^Entry_Point, out_diagnostics: ^^Blob) -> Result,

	GetDependencyFileCount: proc "system" (this: ^Module) -> i32,
	GetDependencyFilePath:  proc "system" (this: ^Module, index: i32) -> cstring,

	GetModuleReflection: proc "system" (this: ^Module) -> ^Decl_Reflection,

	Disassemble: proc "system" (this: ^Module, out_disassembled_blob: ^^Blob) -> Result,
}

@(private="file")
Module_UUID := UUID{0x0c720e64, 0x8722, 0x4d31, {0x89, 0x90, 0x63, 0x8a, 0x98, 0xb1, 0xc2, 0x79}}

// Find an entry point by name. Does not work for functions that aren't
// explicitly marked with a `[shader("...")]` attribute - for those, use
// find_and_check_entry_point instead.
find_entry_point_by_name :: proc(this: ^Module, name: cstring) -> (entry_point: ^Entry_Point, ok: bool) {
	ok = succeeded(this->FindEntryPointByName(name, &entry_point))
	return
}

// Entry points defined in a module aren't part of its linkage by default,
// so get_specialization_param_count-style entry-point counts on the module
// itself stay 0; this reports the module's own defined entry point count
// instead.
get_defined_entry_point_count :: proc(this: ^Module) -> i32 {
	return this->GetDefinedEntryPointCount()
}

// Entry points defined in a module aren't part of its linkage by default,
// so get_specialization_param_count-style entry-point counts on
// the module itself stay 0; this reports the module's own defined entry
// points instead.
get_defined_entry_point :: proc(this: ^Module, index: i32) -> (entry_point: ^Entry_Point, ok: bool) {
	ok = succeeded(this->GetDefinedEntryPoint(index, &entry_point))
	return
}

serialize :: proc(this: ^Module) -> (blob: ^Blob, ok: bool) {
	ok = succeeded(this->Serialize(&blob))
	return
}

write_to_file :: proc(this: ^Module, file_name: cstring) -> bool {
	return succeeded(this->WriteToFile(file_name))
}

get_name :: proc(this: ^Module) -> cstring {
	return this->GetName()
}

get_file_path :: proc(this: ^Module) -> cstring {
	return this->GetFilePath()
}

get_unique_identity :: proc(this: ^Module) -> cstring {
	return this->GetUniqueIdentity()
}

// Find and validate an entry point by name, even without a
// `[shader("...")]` attribute. This is what a "give me entry point X for
// stage Y" workflow should call.
find_and_check_entry_point :: proc(this: ^Module, name: cstring, stage: Stage) -> (entry_point: ^Entry_Point, diagnostics: ^Blob, ok: bool) {
	ok = succeeded(this->FindAndCheckEntryPoint(name, stage, &entry_point, &diagnostics))
	return
}

get_dependency_file_count :: proc(this: ^Module) -> i32 {
	return this->GetDependencyFileCount()
}

get_dependency_file_path :: proc(this: ^Module, index: i32) -> cstring {
	return this->GetDependencyFilePath(index)
}

get_module_reflection :: proc(this: ^Module) -> ^Decl_Reflection {
	return this->GetModuleReflection()
}

disassemble :: proc(this: ^Module) -> (blob: ^Blob, ok: bool) {
	ok = succeeded(this->Disassemble(&blob))
	return
}

// An entry point (e.g. a `[shader("vertex")]` function) found or validated
// within a module. Also a Component_Type: pass it directly to
// session.create_composite_component_type alongside its owning module.
@(private="file")
Entry_Point :: struct #raw_union {
	#subtype component_type: Component_Type,
	using vtable:            ^Entry_Point_VTable,
}

@(private="file")
Entry_Point_VTable :: struct {
	using component_type_vtable: Component_Type_VTable,

	GetFunctionReflection: proc "system" (this: ^Entry_Point) -> ^Function_Reflection,
}

@(private="file")
Entry_Point_UUID := UUID{0x8f241361, 0xf5bd, 0x4ca0, {0xa3, 0xac, 0x02, 0xf7, 0xfa, 0x24, 0x02, 0xb8}}

get_function_reflection :: proc(this: ^Entry_Point) -> ^Function_Reflection {
	return this->GetFunctionReflection()
}
