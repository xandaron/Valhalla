package slang

when ODIN_OS == .Windows {
	when !#exists("slang.lib") {
		#panic("Could not find slang.lib - copy Slang's prebuilt slang.lib into the slang/ package directory (see README.md).")
	}
	foreign import lib {
		"slang.lib",
	}
} else {
	foreign import lib {
		"system:slang",
	}
}

@(default_calling_convention = "c", link_prefix = "slang_")
foreign lib {
	// Create a global session with the built-in core module.
	createGlobalSession :: proc(api_version: Int, out_global_session: ^^IGlobalSession) -> Result ---

	// Create a global session, configured via GlobalSessionDesc (search paths,
	// GLSL support, minimum language version, ...).
	createGlobalSession2 :: proc(desc: ^Global_Session_Desc, out_global_session: ^^IGlobalSession) -> Result ---

	// Create a global session without setting up the core module. The core
	// module can then be loaded via IGlobalSession.LoadCoreModule/CompileCoreModule.
	// EXPERIMENTAL.
	createGlobalSessionWithoutCoreModule :: proc(api_version: Int, out_global_session: ^^IGlobalSession) -> Result ---

	// Create a blob that copies `size` bytes from `data`. Caller owns the
	// returned reference and must Release() it.
	createBlob :: proc(data: rawptr, size: uint) -> ^IBlob ---

	// Clean up all global allocations used by Slang, so memory leak detectors
	// don't report them. Only call after every Slang object has been
	// released; no other Slang function (including createGlobalSession) may
	// be called afterwards.
	shutdown :: proc() ---

	// The last internally-signaled error message, if any.
	getLastInternalErrorMessage :: proc() -> cstring ---
}

// Create a global session with the built-in core module.
create_global_session :: proc() -> (global_session: ^IGlobalSession, ok: bool) {
	ok = succeeded(createGlobalSession(API_VERSION, &global_session))
	return
}

// Create a global session, configured via Global_Session_Desc (search paths,
// GLSL support, minimum language version, ...).
create_global_session2 :: proc(desc: ^Global_Session_Desc) -> (global_session: ^IGlobalSession, ok: bool) {
	ok = succeeded(createGlobalSession2(desc, &global_session))
	return
}

// Create a global session without setting up the core module. The core
// module can then be loaded via IGlobalSession.LoadCoreModule/CompileCoreModule.
// EXPERIMENTAL.
create_global_session_without_core_module :: proc() -> (global_session: ^IGlobalSession, ok: bool) {
	ok = succeeded(createGlobalSessionWithoutCoreModule(API_VERSION, &global_session))
	return
}
