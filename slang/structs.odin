package slang

// Description of a code generation target.
Target_Desc :: struct {
	structureSize:              uint,
	format:                     Compile_Target,
	profile:                    Profile_ID,
	flags:                      Target_Flags,
	floatingPointMode:          Floating_Point_Mode,
	lineDirectiveMode:          Line_Directive_Mode,
	forceGLSLScalarBufferLayout: Bool,
	compilerOptionEntries:      [^]Compiler_Option_Entry,
	compilerOptionEntryCount:   u32,
}

target_desc_default :: proc() -> Target_Desc {
	return Target_Desc{structureSize = size_of(Target_Desc), flags = DEFAULT_TARGET_FLAGS}
}

Preprocessor_Macro_Desc :: struct {
	name:  cstring,
	value: cstring,
}

// A session provides a scope for code that is loaded: search paths, global
// preprocessor definitions, and the set of compilation targets to generate
// code for.
Session_Desc :: struct {
	structureSize:            uint,
	targets:                  [^]Target_Desc,
	targetCount:               Int,
	flags:                    Session_Flags,
	defaultMatrixLayoutMode:  Matrix_Layout_Mode,
	searchPaths:              [^]cstring,
	searchPathCount:          Int,
	preprocessorMacros:       [^]Preprocessor_Macro_Desc,
	preprocessorMacroCount:   Int,
	fileSystem:               ^Slang_File_System,
	enableEffectAnnotations:  Bool,
	allowGLSLSyntax:          Bool,
	compilerOptionEntries:    [^]Compiler_Option_Entry,
	compilerOptionEntryCount: u32,
	skipSPIRVValidation:      Bool,
}

session_desc_default :: proc() -> Session_Desc {
	return Session_Desc {
		structureSize = size_of(Session_Desc),
		defaultMatrixLayoutMode = .ROW_MAJOR,
	}
}

// Description of a Slang global session, passed to createGlobalSession2.
Global_Session_Desc :: struct {
	structureSize:      u32,
	apiVersion:         u32,
	minLanguageVersion: u32,
	enableGLSL:         Bool,
	reserved:           [16]u32,
}

// SLANG_LANGUAGE_VERSION_2025, the default minLanguageVersion used by
// global_session_desc_default.
LANGUAGE_VERSION_2025 :: 2025

global_session_desc_default :: proc() -> Global_Session_Desc {
	return Global_Session_Desc {
		structureSize = size_of(Global_Session_Desc),
		apiVersion = API_VERSION,
		minLanguageVersion = LANGUAGE_VERSION_2025,
	}
}

Source_Location :: struct {
	filePath: cstring,
	line:     Int,
	column:   Int,
}

Specialization_Arg_Kind :: enum i32 {
	Unknown = 0,
	Type    = 1,
	Expr    = 2,
}

// Argument used for specialization to types/values.
Specialization_Arg :: struct {
	kind: Specialization_Arg_Kind,
	using _: struct #raw_union {
		type: ^Type_Reflection,
		expr: cstring,
	},
}
