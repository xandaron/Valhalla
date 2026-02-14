package Valhalla

import "../slang"
import "core:mem"
import "core:strings"

CompileError :: enum {
	None = 0,
	GlobalSession,
	Session,
	Module,
	EntryPoint,
	Program,
	LinkedProgram,
	Code,
}

@(require_results)
compileShader :: proc(
	file, entryPoint: string,
	stage: slang.Stage,
) -> (
	shaderCode: []byte,
	err: CompileError,
) {
	// TODO: Add ability to compile for multiple entry points at once.
	blobToString :: proc(blob: ^slang.Blob, allocator := context.temp_allocator) -> string {
		if blob == nil {
			return ""
		}
		size := slang.getBlobSize(blob)
		if size == 0 {
			return ""
		}

		return strings.clone_from_bytes(
			([^]u8)(slang.getBlobData(blob))[:size],
			allocator = allocator,
		)
	}

	diagnosticsBlob: ^slang.Blob
	desc := slang.Global_Session_Desc {
		searchPaths     = nil,
		searchPathCount = 0,
	}
	globalSession := slang.createGlobalSessionWithDesc(&desc)
	if globalSession == nil {
		log(.Error, "Failed to start slang compiler session!")
		err = .GlobalSession
		return
	}
	defer slang.releaseGlobalSession(globalSession)

	compileTargets := []slang.Compile_Target{.SPIRV}
	sessionDesc := slang.Session_Desc {
		targets                = raw_data(compileTargets),
		targetCount            = i32(len(compileTargets)),
		searchPaths            = nil,
		searchPathCount        = 0,
		preprocessorMacros     = nil,
		preprocessorMacroCount = 0,
		matrixLayoutMode       = .COLUMN_MAJOR,
	}
	session := slang.createSessionWithProfile(
		globalSession,
		slang.findProfile(globalSession, "spirv_1_6"),
		&sessionDesc,
	)
	if session == nil {
		log(.Error, "Failed to start slang compiler session!")
		err = .Session
		return
	}
	defer slang.releaseSession(session)

	module := slang.loadModule(
		session,
		strings.clone_to_cstring(file, context.temp_allocator),
		&diagnosticsBlob,
	)
	if module == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		err = .Module
		return
	}
	defer slang.releaseModule(module)

	ep := slang.findEntryPoint(
		module,
		strings.clone_to_cstring(entryPoint, context.temp_allocator),
		stage,
		&diagnosticsBlob,
	)
	if ep == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		err = .EntryPoint
		return
	}
	defer slang.releaseEntryPoint(ep)

	components: [2]slang.Component_Type = {
		{kind = .MODULE, module = module},
		{kind = .ENTRY_POINT, entryPoint = ep},
	}

	program := slang.createCompositeComponentType(
		session,
		&components[0],
		i32(len(components)),
		&diagnosticsBlob,
	)
	if program == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		err = .Program
		return
	}
	defer slang.releaseComponentType(program)

	linkedProgram := slang.linkComponentType(program, &diagnosticsBlob)
	if linkedProgram == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		err = .LinkedProgram
		return
	}
	defer slang.releaseComponentType(linkedProgram)

	codeBlob := slang.getEntryPointCode(linkedProgram, 0, 0, &diagnosticsBlob)
	defer slang.releaseBlob(codeBlob)
	if codeBlob == nil {
		log(.Error, blobToString(diagnosticsBlob))
		err = .Code
		return
	}

	if slang.getBlobSize(codeBlob) <= 0 {
		log(.Error, "Shader code length <= 0; %v", slang.getBlobSize(codeBlob))
		err = .Code
		return
	}

	shaderCode = make([]u8, slang.getBlobSize(codeBlob))
	mem.copy(raw_data(shaderCode), slang.getBlobData(codeBlob), (int)(slang.getBlobSize(codeBlob)))
	return
}

endSlang :: proc() {
	slang.shutdown()
}

