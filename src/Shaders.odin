package Valhalla

import "../slang"
import "core:mem"
import "core:strings"

CompileError :: enum {
	None = 0,
	GlobalSession,
	Capability,
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
		size := slang.get_buffer_size(blob)
		if size == 0 {
			return ""
		}
		return strings.clone_from_bytes(
			([^]u8)(slang.get_buffer_pointer(blob))[:size],
			allocator = allocator,
		)
	}

	globalSessionDesc := slang.global_session_desc_default()
	globalSession, globalSessionOk := slang.create_global_session2(&globalSessionDesc)
	if !globalSessionOk {
		log(.Error, "Failed to start slang compiler session!")
		err = .GlobalSession
		return
	}
	defer slang.release(globalSession)

	heapCapability := slang.find_capability(globalSession, "spvDescriptorHeapEXT")
	if heapCapability == 0 {
		log(.Error, "Slang does not know the spvDescriptorHeapEXT capability!")
		err = .Capability
		return
	}

	targetOptions := []slang.Compiler_Option_Entry {
		{name = .Capability, value = {kind = .Int, intValue0 = i32(heapCapability)}},
	}

	target := slang.target_desc_default()
	target.format = .SPIRV
	target.profile = slang.find_profile(globalSession, "spirv_1_6")
	target.compilerOptionEntries = raw_data(targetOptions)
	target.compilerOptionEntryCount = u32(len(targetOptions))

	sessionDesc := slang.session_desc_default()
	sessionDesc.targets = &target
	sessionDesc.targetCount = 1
	sessionDesc.defaultMatrixLayoutMode = .COLUMN_MAJOR

	session, sessionOk := slang.create_session(globalSession, &sessionDesc)
	if !sessionOk {
		log(.Error, "Failed to start slang compiler session!")
		err = .Session
		return
	}
	defer slang.release(session)

	module, moduleDiagnostics, moduleOk := slang.load_module(
		session,
		strings.clone_to_cstring(file, context.temp_allocator),
	)
	defer slang.release(moduleDiagnostics)
	if !moduleOk {
		log(.Error, blobToString(moduleDiagnostics))
		err = .Module
		return
	}
	defer slang.release(module)

	ep, epDiagnostics, epOk := slang.find_and_check_entry_point(
		module,
		strings.clone_to_cstring(entryPoint, context.temp_allocator),
		stage,
	)
	defer slang.release(epDiagnostics)
	if !epOk {
		log(.Error, blobToString(epDiagnostics))
		err = .EntryPoint
		return
	}
	defer slang.release(ep)

	components := []^slang.Component_Type{module, ep}
	program, programDiagnostics, programOk := slang.create_composite_component_type(
		session,
		components,
	)
	defer slang.release(programDiagnostics)
	if !programOk {
		log(.Error, blobToString(programDiagnostics))
		err = .Program
		return
	}
	defer slang.release(program)

	linkedProgram, linkDiagnostics, linkOk := slang.link(program)
	defer slang.release(linkDiagnostics)
	if !linkOk {
		log(.Error, blobToString(linkDiagnostics))
		err = .LinkedProgram
		return
	}
	defer slang.release(linkedProgram)

	codeBlob, codeDiagnostics, codeOk := slang.get_entry_point_code(linkedProgram, 0, 0)
	defer slang.release(codeDiagnostics)
	if !codeOk {
		log(.Error, blobToString(codeDiagnostics))
		err = .Code
		return
	}
	defer slang.release(codeBlob)

	size := slang.get_buffer_size(codeBlob)
	if size == 0 {
		log(.Error, "Shader code length is zero")
		err = .Code
		return
	}

	shaderCode = make([]u8, size)
	mem.copy(raw_data(shaderCode), slang.get_buffer_pointer(codeBlob), int(size))
	return
}

endSlang :: proc() {
	slang.shutdown()
}
