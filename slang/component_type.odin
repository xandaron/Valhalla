package slang

// A logical unit of shader code: a module, an entry point, or a composite
// built from other component types via ISession.CreateCompositeComponentType
// or IComponentType.Link. IModule and IEntryPoint are both component types
// (see below) and can be passed anywhere an ^IComponentType is expected.
IComponentType :: struct #raw_union {
	#subtype unknown: IUnknown,
	using vtable:     ^IComponentType_VTable,
}

IComponentType_VTable :: struct {
	using unknown_vtable: IUnknown_VTable,

	// Get the session this component type belongs to.
	GetSession: proc "system" (this: ^IComponentType) -> ^ISession,

	// Get the (possibly incomplete, if unspecialized) layout for `target_index`.
	GetLayout: proc "system" (this: ^IComponentType, target_index: Int, out_diagnostics: ^^IBlob) -> ^Program_Layout,

	GetSpecializationParamCount: proc "system" (this: ^IComponentType) -> Int,

	// Get compiled code for the entry point at `entry_point_index` for
	// `target_index`. Requires a component type that is fully specialized
	// and fully linked (see Link below).
	GetEntryPointCode: proc "system" (this: ^IComponentType, entry_point_index: Int, target_index: Int, out_code: ^^IBlob, out_diagnostics: ^^IBlob) -> Result,

	// Get the compilation result as an in-memory file system.
	GetResultAsFileSystem: proc "system" (this: ^IComponentType, entry_point_index: Int, target_index: Int, out_file_system: ^^ISlangMutableFileSystem) -> Result,

	// Hash of all dependencies plus target settings; usable as a shader-cache key.
	GetEntryPointHash: proc "system" (this: ^IComponentType, entry_point_index: Int, target_index: Int, out_hash: ^^IBlob),

	// Bind specialization parameters to concrete type/value arguments.
	Specialize: proc "system" (this: ^IComponentType, specialization_args: [^]Specialization_Arg, specialization_arg_count: Int, out_specialized_component_type: ^^IComponentType, out_diagnostics: ^^IBlob) -> Result,

	// Link against all unsatisfied dependencies (e.g. a module's imports, or
	// an entry point's defining module), producing a fully linked program
	// suitable for GetEntryPointCode/GetTargetCode.
	Link: proc "system" (this: ^IComponentType, out_linked_component_type: ^^IComponentType, out_diagnostics: ^^IBlob) -> Result,

	// Requires a compilation target of SLANG_HOST_CALLABLE.
	GetEntryPointHostCallable: proc "system" (this: ^IComponentType, entry_point_index: i32, target_index: i32, out_shared_library: ^^ISlangSharedLibrary, out_diagnostics: ^^IBlob) -> Result,

	RenameEntryPoint: proc "system" (this: ^IComponentType, new_name: cstring, out_entry_point: ^^IComponentType) -> Result,

	// Link and specify additional compiler options for code generation.
	LinkWithOptions: proc "system" (this: ^IComponentType, out_linked_component_type: ^^IComponentType, compiler_option_entry_count: u32, compiler_option_entries: [^]Compiler_Option_Entry, out_diagnostics: ^^IBlob) -> Result,

	GetTargetCode: proc "system" (this: ^IComponentType, target_index: Int, out_code: ^^IBlob, out_diagnostics: ^^IBlob) -> Result,

	GetTargetMetadata: proc "system" (this: ^IComponentType, target_index: Int, out_metadata: ^^IMetadata, out_diagnostics: ^^IBlob) -> Result,

	GetEntryPointMetadata: proc "system" (this: ^IComponentType, entry_point_index: Int, target_index: Int, out_metadata: ^^IMetadata, out_diagnostics: ^^IBlob) -> Result,
}

IComponentType_UUID := UUID{0x5bc42be8, 0x5c50, 0x4929, {0x9e, 0x5e, 0xd1, 0x5e, 0x7c, 0x24, 0x01, 0x5f}}

// Get the (possibly incomplete, if unspecialized) layout for `target_index`.
get_layout :: proc(this: ^IComponentType, target_index: Int) -> (layout: ^Program_Layout, diagnostics: ^IBlob, ok: bool) {
	layout = this->GetLayout(target_index, &diagnostics)
	ok = layout != nil
	return
}

// Get compiled code for the entry point at `entry_point_index` for
// `target_index`. Requires a component type that is fully specialized and
// fully linked (see link below).
get_entry_point_code :: proc(this: ^IComponentType, entry_point_index: Int, target_index: Int) -> (code: ^IBlob, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->GetEntryPointCode(entry_point_index, target_index, &code, &diagnostics))
	return
}

// Get the compilation result as an in-memory file system.
get_result_as_file_system :: proc(this: ^IComponentType, entry_point_index: Int, target_index: Int) -> (file_system: ^ISlangMutableFileSystem, ok: bool) {
	ok = succeeded(this->GetResultAsFileSystem(entry_point_index, target_index, &file_system))
	return
}

// Hash of all dependencies plus target settings; usable as a shader-cache key.
get_entry_point_hash :: proc(this: ^IComponentType, entry_point_index: Int, target_index: Int) -> (hash: ^IBlob, ok: bool) {
	this->GetEntryPointHash(entry_point_index, target_index, &hash)
	ok = hash != nil
	return
}

// Bind specialization parameters to concrete type/value arguments.
specialize :: proc(this: ^IComponentType, specialization_args: []Specialization_Arg) -> (specialized: ^IComponentType, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->Specialize(raw_data(specialization_args), len(specialization_args), &specialized, &diagnostics))
	return
}

// Link against all unsatisfied dependencies (e.g. a module's imports, or an
// entry point's defining module), producing a fully linked program suitable
// for get_entry_point_code/get_target_code.
link :: proc(this: ^IComponentType) -> (linked: ^IComponentType, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->Link(&linked, &diagnostics))
	return
}

// Requires a compilation target of SLANG_HOST_CALLABLE.
get_entry_point_host_callable :: proc(this: ^IComponentType, entry_point_index: i32, target_index: i32) -> (shared_library: ^ISlangSharedLibrary, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->GetEntryPointHostCallable(entry_point_index, target_index, &shared_library, &diagnostics))
	return
}

rename_entry_point :: proc(this: ^IComponentType, new_name: cstring) -> (entry_point: ^IComponentType, ok: bool) {
	ok = succeeded(this->RenameEntryPoint(new_name, &entry_point))
	return
}

// Link and specify additional compiler options for code generation.
link_with_options :: proc(this: ^IComponentType, compiler_option_entries: []Compiler_Option_Entry) -> (linked: ^IComponentType, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->LinkWithOptions(&linked, u32(len(compiler_option_entries)), raw_data(compiler_option_entries), &diagnostics))
	return
}

get_target_code :: proc(this: ^IComponentType, target_index: Int) -> (code: ^IBlob, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->GetTargetCode(target_index, &code, &diagnostics))
	return
}

get_target_metadata :: proc(this: ^IComponentType, target_index: Int) -> (metadata: ^IMetadata, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->GetTargetMetadata(target_index, &metadata, &diagnostics))
	return
}

get_entry_point_metadata :: proc(this: ^IComponentType, entry_point_index: Int, target_index: Int) -> (metadata: ^IMetadata, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->GetEntryPointMetadata(entry_point_index, target_index, &metadata, &diagnostics))
	return
}

// A module is the granularity of shader code compilation and loading -
// typically a single `.slang`/`.hlsl` file plus everything it `#include`s.
// Things it `import`s remain distinct modules in the same session.
IModule :: struct #raw_union {
	#subtype component_type: IComponentType,
	using vtable:            ^IModule_VTable,
}

IModule_VTable :: struct {
	using component_type_vtable: IComponentType_VTable,

	// Find an entry point by name. Does not work for functions that aren't
	// explicitly marked with a `[shader("...")]` attribute - for those, use
	// FindAndCheckEntryPoint instead.
	FindEntryPointByName: proc "system" (this: ^IModule, name: cstring, out_entry_point: ^^IEntryPoint) -> Result,

	// Entry points defined in a module aren't part of its linkage by default,
	// so IComponentType.GetSpecializationParamCount-style entry-point counts
	// on the module itself stay 0; these two report the module's own defined
	// entry points instead.
	GetDefinedEntryPointCount: proc "system" (this: ^IModule) -> i32,
	GetDefinedEntryPoint:      proc "system" (this: ^IModule, index: i32, out_entry_point: ^^IEntryPoint) -> Result,

	Serialize:   proc "system" (this: ^IModule, out_serialized_blob: ^^IBlob) -> Result,
	WriteToFile: proc "system" (this: ^IModule, file_name: cstring) -> Result,

	GetName:           proc "system" (this: ^IModule) -> cstring,
	GetFilePath:       proc "system" (this: ^IModule) -> cstring,
	GetUniqueIdentity: proc "system" (this: ^IModule) -> cstring,

	// Find and validate an entry point by name, even without a
	// `[shader("...")]` attribute. This is what a "give me entry point X for
	// stage Y" workflow should call.
	FindAndCheckEntryPoint: proc "system" (this: ^IModule, name: cstring, stage: Stage, out_entry_point: ^^IEntryPoint, out_diagnostics: ^^IBlob) -> Result,

	GetDependencyFileCount: proc "system" (this: ^IModule) -> i32,
	GetDependencyFilePath:  proc "system" (this: ^IModule, index: i32) -> cstring,

	GetModuleReflection: proc "system" (this: ^IModule) -> ^Decl_Reflection,

	Disassemble: proc "system" (this: ^IModule, out_disassembled_blob: ^^IBlob) -> Result,
}

IModule_UUID := UUID{0x0c720e64, 0x8722, 0x4d31, {0x89, 0x90, 0x63, 0x8a, 0x98, 0xb1, 0xc2, 0x79}}

// Find an entry point by name. Does not work for functions that aren't
// explicitly marked with a `[shader("...")]` attribute - for those, use
// find_and_check_entry_point instead.
find_entry_point_by_name :: proc(this: ^IModule, name: cstring) -> (entry_point: ^IEntryPoint, ok: bool) {
	ok = succeeded(this->FindEntryPointByName(name, &entry_point))
	return
}

// Entry points defined in a module aren't part of its linkage by default,
// so IComponentType.GetSpecializationParamCount-style entry-point counts on
// the module itself stay 0; this reports the module's own defined entry
// points instead.
get_defined_entry_point :: proc(this: ^IModule, index: i32) -> (entry_point: ^IEntryPoint, ok: bool) {
	ok = succeeded(this->GetDefinedEntryPoint(index, &entry_point))
	return
}

serialize :: proc(this: ^IModule) -> (blob: ^IBlob, ok: bool) {
	ok = succeeded(this->Serialize(&blob))
	return
}

// Find and validate an entry point by name, even without a
// `[shader("...")]` attribute. This is what a "give me entry point X for
// stage Y" workflow should call.
find_and_check_entry_point :: proc(this: ^IModule, name: cstring, stage: Stage) -> (entry_point: ^IEntryPoint, diagnostics: ^IBlob, ok: bool) {
	ok = succeeded(this->FindAndCheckEntryPoint(name, stage, &entry_point, &diagnostics))
	return
}

disassemble :: proc(this: ^IModule) -> (blob: ^IBlob, ok: bool) {
	ok = succeeded(this->Disassemble(&blob))
	return
}

// An entry point (e.g. a `[shader("vertex")]` function) found or validated
// within a module. Also an IComponentType: pass it directly to
// ISession.CreateCompositeComponentType alongside its owning module.
IEntryPoint :: struct #raw_union {
	#subtype component_type: IComponentType,
	using vtable:            ^IEntryPoint_VTable,
}

IEntryPoint_VTable :: struct {
	using component_type_vtable: IComponentType_VTable,

	GetFunctionReflection: proc "system" (this: ^IEntryPoint) -> ^Function_Reflection,
}

IEntryPoint_UUID := UUID{0x8f241361, 0xf5bd, 0x4ca0, {0xa3, 0xac, 0x02, 0xf7, 0xfa, 0x24, 0x02, 0xb8}}
