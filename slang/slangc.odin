package slang

import "core:c"

_ :: c

when ODIN_OS == .Windows {
    foreign import lib {
        "gfx.lib",
        "slang-rt.lib", 
        "slang.lib",
        "slangc.lib",
    }
}
else {
    foreign import lib {
        "gfx.a",
        "slang-rt.a",
        "slang.a", 
        "slangc.a",
    }
}

// Component type - can be either a module, entry point, or composite
Component_Type_Kind :: enum c.int {
	MODULE,
	ENTRY_POINT,
	COMPOSITE,
}

// Component type struct - exposed so users can access it directly
Component_Type :: struct {
	kind: Component_Type_Kind,
	using _: struct #raw_union {
		module:     ^Module,
		entryPoint: ^Entry_Point,
		composite:  rawptr, // Opaque pointer to internal composite type
	},
}

// Forward declarations for opaque handles
Global_Session :: struct {}

Session :: struct {}

Module :: struct {}

Entry_Point :: struct {}

Blob :: struct {}

OK :: 0

// Result codes (still useful for some functions)
Result :: i32

FAIL :: -1
E_NOT_IMPLEMENTED :: -2
E_INVALID_ARG :: -3
E_OUT_OF_MEMORY :: -4
E_BUFFER_TOO_SMALL :: -5

// API version
API_VERSION :: 1

// Source languages
Source_Language :: enum c.int {
	UNKNOWN = 0,
	SLANG,
	HLSL,
	GLSL,
	C,
	CPP,
}

// Compilation targets
Compile_Target :: enum c.int {
	UNKNOWN = 0,
	NONE,
	HLSL,
	GLSL,
	SPIRV,
	SPIRV_ASM,
	DXBC,
	DXBC_ASM,
	DXIL,
	DXIL_ASM,
	C_SOURCE,
	CPP_SOURCE,
	CUDA_SOURCE,
	PTX,
	CUBIN,
	METAL,
	METAL_LIB,
	HOST_CALLABLE,
	SHADER_SHARED_LIBRARY,
	SHADER_HOST_CALLABLE,
	WGSL,
}

// Stage types
Stage :: enum c.int {
	NONE = 0,
	VERTEX,
	HULL,
	DOMAIN,
	GEOMETRY,
	FRAGMENT,
	COMPUTE,
	RAY_GENERATION,
	INTERSECTION,
	ANY_HIT,
	CLOSEST_HIT,
	MISS,
	CALLABLE,
	MESH,
	AMPLIFICATION,
}

// Profile IDs (opaque)
Profile_Id :: u32

// Session description
Session_Desc :: struct {
	targets:                [^]Compile_Target,
	targetCount:            i32,
	searchPaths:            [^]cstring,
	searchPathCount:        i32,
	preprocessorMacros:     [^]cstring,
	preprocessorMacroCount: i32,
}

// Global session description
Global_Session_Desc :: struct {
	apiVersion:      u32,
	searchPaths:     [^]cstring,
	searchPathCount: i32,
	enableGLSL:      bool,
}

@(default_calling_convention="c", link_prefix="slangc_")
foreign lib {
	// Error handling - for functions that return pointers directly
	/** Check if the last operation succeeded.
	* @return true if the last operation succeeded, false otherwise
	*/
	hasError :: proc() -> bool ---

	/** Get the last error message.
	* @return Error message string (do not free), or NULL if no error
	*/
	getLastError :: proc() -> cstring ---

	/** Clear the last error state.
	*/
	clearError :: proc() ---

	/** Create a global session with default settings.
	* @return Pointer to the created global session, or NULL on failure
	*/
	createGlobalSession :: proc() -> ^Global_Session ---

	/** Create a global session with custom settings.
	* @param desc Description of the global session configuration
	* @return Pointer to the created global session, or NULL on failure
	*/
	createGlobalSessionWithDesc :: proc(desc: ^Global_Session_Desc) -> ^Global_Session ---

	/** Release a global session and free its resources.
	* @param globalSession The global session to release
	*/
	releaseGlobalSession :: proc(globalSession: ^Global_Session) ---

	/** Find a profile by name.
	* @param globalSession The global session
	* @param name The profile name (e.g., "vs_5_0", "ps_5_0", "cs_5_0")
	* @return The profile ID, or 0 if not found
	*/
	findProfile :: proc(globalSession: ^Global_Session, name: cstring) -> Profile_Id ---

	/** Create a compilation session.
	* @param globalSession The global session
	* @param desc Session description (can be NULL for defaults)
	* @return Pointer to the created session, or NULL on failure
	*/
	createSession :: proc(globalSession: ^Global_Session, desc: ^Session_Desc) -> ^Session ---

	/** Release a session and free its resources.
	* @param session The session to release
	*/
	releaseSession :: proc(session: ^Session) ---

	/** Load a module by name (for import statements).
	* @param session The compilation session
	* @param moduleName The name of the module to load
	* @param outDiagnostics Pointer to receive diagnostic messages (can be NULL)
	* @return Pointer to the loaded module, or NULL on failure
	*/
	loadModule :: proc(session: ^Session, moduleName: cstring, outDiagnostics: ^^Blob) -> ^Module ---

	/** Load a module from source code.
	* @param session The compilation session
	* @param moduleName The name to give the module
	* @param path The file path (for error reporting)
	* @param sourceText The source code text
	* @param sourceSize The size of the source code (or 0 if null-terminated)
	* @param outDiagnostics Pointer to receive diagnostic messages (can be NULL)
	* @return Pointer to the loaded module, or NULL on failure
	*/
	loadModuleFromSource :: proc(session: ^Session, moduleName: cstring, path: cstring, sourceText: cstring, sourceSize: c.size_t, outDiagnostics: ^^Blob) -> ^Module ---

	/** Release a module.
	* @param module The module to release
	*/
	releaseModule :: proc(module: ^Module) ---

	/** Get the kind of a component type.
	* @param componentType The component type to query
	* @return The kind of component type, or SLANGC_COMPONENT_TYPE_MODULE if invalid
	*/
	getComponentTypeKind :: proc(componentType: ^Component_Type) -> Component_Type_Kind ---

	/** Get the underlying module from a module component type.
	* @param componentType The component type (must be SLANGC_COMPONENT_TYPE_MODULE)
	* @return Pointer to the module, or NULL if not a module component type
	*/
	getComponentTypeModule :: proc(componentType: ^Component_Type) -> ^Module ---

	/** Get the underlying entry point from an entry point component type.
	* @param componentType The component type (must be SLANGC_COMPONENT_TYPE_ENTRY_POINT)
	* @return Pointer to the entry point, or NULL if not an entry point component type
	*/
	getComponentTypeEntryPoint :: proc(componentType: ^Component_Type) -> ^Entry_Point ---

	/** Create a composite component type from multiple components.
	* @param session The compilation session
	* @param componentTypes Array of component type structs to combine
	* @param componentTypeCount Number of component types
	* @param outDiagnostics Pointer to receive diagnostic messages (can be NULL)
	* @return Pointer to the composite component type, or NULL on failure
	*/
	createCompositeComponentType :: proc(session: ^Session, componentTypes: [^]Component_Type, componentTypeCount: i32, outDiagnostics: ^^Blob) -> ^Component_Type ---

	/** Find and check an entry point in a module.
	* @param module The loaded module
	* @param entryPointName The name of the entry point function
	* @param stage The shader stage for the entry point
	* @param outDiagnostics Pointer to receive diagnostic messages (can be NULL)
	* @return Pointer to the entry point, or NULL on failure
	*/
	findEntryPoint :: proc(module: ^Module, entryPointName: cstring, stage: Stage, outDiagnostics: ^^Blob) -> ^Entry_Point ---

	/** Release an entry point.
	* @param entryPoint The entry point to release
	*/
	releaseEntryPoint :: proc(entryPoint: ^Entry_Point) ---

	/** Create a component type from a module.
	* @param module The module to wrap as a component type
	* @return Pointer to the component type, or NULL on failure
	*/
	createModuleComponentType :: proc(module: ^Module) -> ^Component_Type ---

	/** Create a component type from an entry point.
	* @param entryPoint The entry point to wrap as a component type
	* @return Pointer to the component type, or NULL on failure
	*/
	createEntryPointComponentType :: proc(entryPoint: ^Entry_Point) -> ^Component_Type ---

	/** Link a component type to produce a linked program.
	* @param componentType The component type to link
	* @param outDiagnostics Pointer to receive diagnostic messages (can be NULL)
	* @return Pointer to the linked component type, or NULL on failure
	*/
	linkComponentType :: proc(componentType: ^Component_Type, outDiagnostics: ^^Blob) -> ^Component_Type ---

	/** Get entry point code for a specific entry point and target.
	* @param componentType The component type to compile (must be fully linked)
	* @param entryPointIndex The entry point index (0-based). For simple cases with one entry point, use 0.
	*                        For composite types, this corresponds to the order entry points were added.
	* @param targetIndex The target index (0-based, from session targets)
	* @param outDiagnostics Pointer to receive diagnostic messages (can be NULL)
	* @return Pointer to the compiled code blob, or NULL on failure
	*/
	getEntryPointCode :: proc(componentType: ^Component_Type, entryPointIndex: i32, targetIndex: i32, outDiagnostics: ^^Blob) -> ^Blob ---

	/** Release a component type.
	* @param componentType The component type to release
	*/
	releaseComponentType :: proc(componentType: ^Component_Type) ---

	/** Get the data pointer from a blob.
	* @param blob The blob
	* @return Pointer to the blob data
	*/
	getBlobData :: proc(blob: ^Blob) -> rawptr ---

	/** Get the size of a blob.
	* @param blob The blob
	* @return Size in bytes
	*/
	getBlobSize :: proc(blob: ^Blob) -> c.size_t ---

	/** Release a blob.
	* @param blob The blob to release
	*/
	releaseBlob :: proc(blob: ^Blob) ---

	/** Get version information.
	* @return Version string (do not free)
	*/
	getVersionString :: proc() -> cstring ---

	/** Shutdown the Slang system (call after all objects are released).
	*/
	shutdown :: proc() ---

	/** Get the last internal error message.
	* @return Error message string (do not free)
	*/
	getLastErrorMessage :: proc() -> cstring ---
}
