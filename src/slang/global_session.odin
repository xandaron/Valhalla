package slang

// A global session for interacting with the Slang library. Base cost of
// standing up the compiler (e.g. loading the core module) is paid once per
// global session, so applications should create one and reuse it to create
// multiple Session instances.
//
// Not thread-safe: a global session and the objects created from it should be
// externally synchronized when shared across threads. Distinct global
// sessions may be used from different threads in parallel.
@(private)
Global_Session :: struct #raw_union {
	#subtype unknown: Unknown,
	using vtable:     ^Global_Session_VTable,
}

@(private="file")
Global_Session_VTable :: struct {
	QueryInterface: proc "system" (this: ^Unknown, uuid: ^UUID, out_object: ^rawptr) -> Result,
	AddRef:         proc "system" (this: ^Unknown) -> u32,
	Release:        proc "system" (this: ^Unknown) -> u32,

	// Create a new session for loading and compiling code.
	CreateSession: proc "system" (this: ^Global_Session, desc: ^Session_Desc, out_session: ^^Session) -> Result,

	// Look up the internal ID of a profile by its `name` (e.g. "vs_5_0", "glsl_450").
	// Profile IDs are not guaranteed to be stable across Slang versions.
	FindProfile: proc "system" (this: ^Global_Session, name: cstring) -> Profile_ID,

	SetDownstreamCompilerPath: proc "system" (this: ^Global_Session, pass_through: Pass_Through, path: cstring),

	// DEPRECATED: use SetLanguagePrelude.
	SetDownstreamCompilerPrelude: proc "system" (this: ^Global_Session, pass_through: Pass_Through, prelude_text: cstring),
	// DEPRECATED: use GetLanguagePrelude.
	GetDownstreamCompilerPrelude: proc "system" (this: ^Global_Session, pass_through: Pass_Through, out_prelude: ^^Blob),

	GetBuildTagString: proc "system" (this: ^Global_Session) -> cstring,

	SetDefaultDownstreamCompiler: proc "system" (this: ^Global_Session, source_language: Source_Language, default_compiler: Pass_Through) -> Result,
	GetDefaultDownstreamCompiler: proc "system" (this: ^Global_Session, source_language: Source_Language) -> Pass_Through,

	SetLanguagePrelude: proc "system" (this: ^Global_Session, source_language: Source_Language, prelude_text: cstring),
	GetLanguagePrelude: proc "system" (this: ^Global_Session, source_language: Source_Language, out_prelude: ^^Blob),

	// DEPRECATED.
	CreateCompileRequest: proc "system" (this: ^Global_Session, out_compile_request: ^^Compile_Request) -> Result,
	// DEPRECATED.
	AddBuiltins: proc "system" (this: ^Global_Session, source_path: cstring, source_string: cstring),

	SetSharedLibraryLoader: proc "system" (this: ^Global_Session, loader: ^Slang_Shared_Library_Loader),
	GetSharedLibraryLoader: proc "system" (this: ^Global_Session) -> ^Slang_Shared_Library_Loader,

	CheckCompileTargetSupport: proc "system" (this: ^Global_Session, target: Compile_Target) -> Result,
	CheckPassThroughSupport:   proc "system" (this: ^Global_Session, pass_through: Pass_Through) -> Result,

	// EXPERIMENTAL.
	CompileCoreModule: proc "system" (this: ^Global_Session, flags: Compile_Core_Module_Flags) -> Result,
	// EXPERIMENTAL.
	LoadCoreModule: proc "system" (this: ^Global_Session, core_module: rawptr, core_module_size_in_bytes: uint) -> Result,
	// EXPERIMENTAL.
	SaveCoreModule: proc "system" (this: ^Global_Session, archive_type: Archive_Type, out_blob: ^^Blob) -> Result,

	FindCapability: proc "system" (this: ^Global_Session, name: cstring) -> Capability_ID,

	SetDownstreamCompilerForTransition: proc "system" (this: ^Global_Session, source: Compile_Target, target: Compile_Target, compiler: Pass_Through),
	GetDownstreamCompilerForTransition: proc "system" (this: ^Global_Session, source: Compile_Target, target: Compile_Target) -> Pass_Through,

	GetCompilerElapsedTime: proc "system" (this: ^Global_Session, out_total_time: ^f64, out_downstream_time: ^f64),

	SetSPIRVCoreGrammar: proc "system" (this: ^Global_Session, json_path: cstring) -> Result,

	ParseCommandLineArguments: proc "system" (this: ^Global_Session, argc: i32, argv: [^]cstring, out_session_desc: ^Session_Desc, out_aux_allocation: ^^Unknown) -> Result,

	GetSessionDescDigest: proc "system" (this: ^Global_Session, session_desc: ^Session_Desc, out_blob: ^^Blob) -> Result,

	// EXPERIMENTAL.
	CompileBuiltinModule: proc "system" (this: ^Global_Session, module: Builtin_Module_Name, flags: Compile_Core_Module_Flags) -> Result,
	// EXPERIMENTAL.
	LoadBuiltinModule: proc "system" (this: ^Global_Session, module: Builtin_Module_Name, module_data: rawptr, size_in_bytes: uint) -> Result,
	// EXPERIMENTAL.
	SaveBuiltinModule: proc "system" (this: ^Global_Session, module: Builtin_Module_Name, archive_type: Archive_Type, out_blob: ^^Blob) -> Result,

	// Get the on-disk path of the downstream compiler Slang resolves for `pass_through`.
	GetDownstreamCompilerPath: proc "system" (this: ^Global_Session, pass_through: Pass_Through, out_path: ^^Blob) -> Result,
}

@(private="file")
Global_Session_UUID := UUID{0xc140b5fd, 0x0c78, 0x452e, {0xba, 0x7c, 0x1a, 0x1e, 0x70, 0xc7, 0xf7, 0x1c}}

// Create a new session for loading and compiling code.
create_session :: proc(this: ^Global_Session, desc: ^Session_Desc) -> (session: ^Session, ok: bool) {
	ok = succeeded(this->CreateSession(desc, &session))
	return
}

// Look up the internal ID of a profile by its `name` (e.g. "vs_5_0", "glsl_450").
// Profile IDs are not guaranteed to be stable across Slang versions.
find_profile :: proc(this: ^Global_Session, name: cstring) -> Profile_ID {
	return this->FindProfile(name)
}

set_downstream_compiler_path :: proc(this: ^Global_Session, pass_through: Pass_Through, path: cstring) {
	this->SetDownstreamCompilerPath(pass_through, path)
}

// DEPRECATED: use set_language_prelude.
set_downstream_compiler_prelude :: proc(this: ^Global_Session, pass_through: Pass_Through, prelude_text: cstring) {
	this->SetDownstreamCompilerPrelude(pass_through, prelude_text)
}

// DEPRECATED: use get_language_prelude.
get_downstream_compiler_prelude :: proc(this: ^Global_Session, pass_through: Pass_Through) -> (prelude: ^Blob, ok: bool) {
	this->GetDownstreamCompilerPrelude(pass_through, &prelude)
	ok = prelude != nil
	return
}

get_build_tag_string :: proc(this: ^Global_Session) -> cstring {
	return this->GetBuildTagString()
}

set_default_downstream_compiler :: proc(this: ^Global_Session, source_language: Source_Language, default_compiler: Pass_Through) -> bool {
	return succeeded(this->SetDefaultDownstreamCompiler(source_language, default_compiler))
}

get_default_downstream_compiler :: proc(this: ^Global_Session, source_language: Source_Language) -> Pass_Through {
	return this->GetDefaultDownstreamCompiler(source_language)
}

set_language_prelude :: proc(this: ^Global_Session, source_language: Source_Language, prelude_text: cstring) {
	this->SetLanguagePrelude(source_language, prelude_text)
}

get_language_prelude :: proc(this: ^Global_Session, source_language: Source_Language) -> (prelude: ^Blob, ok: bool) {
	this->GetLanguagePrelude(source_language, &prelude)
	ok = prelude != nil
	return
}

// DEPRECATED.
add_builtins :: proc(this: ^Global_Session, source_path: cstring, source_string: cstring) {
	this->AddBuiltins(source_path, source_string)
}

set_shared_library_loader :: proc(this: ^Global_Session, loader: ^Slang_Shared_Library_Loader) {
	this->SetSharedLibraryLoader(loader)
}

get_shared_library_loader :: proc(this: ^Global_Session) -> ^Slang_Shared_Library_Loader {
	return this->GetSharedLibraryLoader()
}

check_compile_target_support :: proc(this: ^Global_Session, target: Compile_Target) -> bool {
	return succeeded(this->CheckCompileTargetSupport(target))
}

check_pass_through_support :: proc(this: ^Global_Session, pass_through: Pass_Through) -> bool {
	return succeeded(this->CheckPassThroughSupport(pass_through))
}

// EXPERIMENTAL.
compile_core_module :: proc(this: ^Global_Session, flags: Compile_Core_Module_Flags) -> bool {
	return succeeded(this->CompileCoreModule(flags))
}

// EXPERIMENTAL.
load_core_module :: proc(this: ^Global_Session, core_module: rawptr, core_module_size_in_bytes: uint) -> bool {
	return succeeded(this->LoadCoreModule(core_module, core_module_size_in_bytes))
}

// EXPERIMENTAL.
save_core_module :: proc(this: ^Global_Session, archive_type: Archive_Type) -> (blob: ^Blob, ok: bool) {
	ok = succeeded(this->SaveCoreModule(archive_type, &blob))
	return
}

find_capability :: proc(this: ^Global_Session, name: cstring) -> Capability_ID {
	return this->FindCapability(name)
}

set_downstream_compiler_for_transition :: proc(this: ^Global_Session, source: Compile_Target, target: Compile_Target, compiler: Pass_Through) {
	this->SetDownstreamCompilerForTransition(source, target, compiler)
}

get_downstream_compiler_for_transition :: proc(this: ^Global_Session, source: Compile_Target, target: Compile_Target) -> Pass_Through {
	return this->GetDownstreamCompilerForTransition(source, target)
}

get_compiler_elapsed_time :: proc(this: ^Global_Session) -> (total_time: f64, downstream_time: f64) {
	this->GetCompilerElapsedTime(&total_time, &downstream_time)
	return
}

set_spirv_core_grammar :: proc(this: ^Global_Session, json_path: cstring) -> bool {
	return succeeded(this->SetSPIRVCoreGrammar(json_path))
}

parse_command_line_arguments :: proc(this: ^Global_Session, argv: []cstring) -> (session_desc: Session_Desc, aux_allocation: ^Unknown, ok: bool) {
	ok = succeeded(this->ParseCommandLineArguments(i32(len(argv)), raw_data(argv), &session_desc, &aux_allocation))
	return
}

get_session_desc_digest :: proc(this: ^Global_Session, session_desc: ^Session_Desc) -> (digest: ^Blob, ok: bool) {
	ok = succeeded(this->GetSessionDescDigest(session_desc, &digest))
	return
}

// EXPERIMENTAL.
compile_builtin_module :: proc(this: ^Global_Session, module: Builtin_Module_Name, flags: Compile_Core_Module_Flags) -> bool {
	return succeeded(this->CompileBuiltinModule(module, flags))
}

// EXPERIMENTAL.
load_builtin_module :: proc(this: ^Global_Session, module: Builtin_Module_Name, module_data: rawptr, size_in_bytes: uint) -> bool {
	return succeeded(this->LoadBuiltinModule(module, module_data, size_in_bytes))
}

// EXPERIMENTAL.
save_builtin_module :: proc(this: ^Global_Session, module: Builtin_Module_Name, archive_type: Archive_Type) -> (blob: ^Blob, ok: bool) {
	ok = succeeded(this->SaveBuiltinModule(module, archive_type, &blob))
	return
}

// Get the on-disk path of the downstream compiler Slang resolves for `pass_through`.
get_downstream_compiler_path :: proc(this: ^Global_Session, pass_through: Pass_Through) -> (path: ^Blob, ok: bool) {
	ok = succeeded(this->GetDownstreamCompilerPath(pass_through, &path))
	return
}

// DEPRECATED.
create_compile_request :: proc{
	global_session_create_compile_request,
	session_create_compile_request,
}

@(private)
global_session_create_compile_request :: proc(this: ^Global_Session) -> (compile_request: ^Compile_Request, ok: bool) {
	ok = succeeded(this->CreateCompileRequest(&compile_request))
	return
}
