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
	blobToString :: proc(blob: ^slang.IBlob, allocator := context.temp_allocator) -> string {
		if blob == nil {
			return ""
		}
		size := blob->GetBufferSize()
		if size == 0 {
			return ""
		}
		return strings.clone_from_bytes(
			([^]u8)(blob->GetBufferPointer())[:size],
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
	defer globalSession->Release()

	heapCapability := globalSession->FindCapability("spvDescriptorHeapEXT")
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
	target.profile = globalSession->FindProfile("spirv_1_6")
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
	defer session->Release()

	module, moduleDiagnostics, moduleOk := slang.load_module(
		session,
		strings.clone_to_cstring(file, context.temp_allocator),
	)
	defer if moduleDiagnostics != nil do moduleDiagnostics->Release()
	if !moduleOk {
		log(.Error, blobToString(moduleDiagnostics))
		err = .Module
		return
	}
	defer module->Release()

	ep, epDiagnostics, epOk := slang.find_and_check_entry_point(
		module,
		strings.clone_to_cstring(entryPoint, context.temp_allocator),
		stage,
	)
	defer if epDiagnostics != nil do epDiagnostics->Release()
	if !epOk {
		log(.Error, blobToString(epDiagnostics))
		err = .EntryPoint
		return
	}
	defer ep->Release()

	components := []^slang.IComponentType{module, ep}
	program, programDiagnostics, programOk := slang.create_composite_component_type(
		session,
		components,
	)
	defer if programDiagnostics != nil do programDiagnostics->Release()
	if !programOk {
		log(.Error, blobToString(programDiagnostics))
		err = .Program
		return
	}
	defer program->Release()

	linkedProgram, linkDiagnostics, linkOk := slang.link(program)
	defer if linkDiagnostics != nil do linkDiagnostics->Release()
	if !linkOk {
		log(.Error, blobToString(linkDiagnostics))
		err = .LinkedProgram
		return
	}
	defer linkedProgram->Release()

	codeBlob, codeDiagnostics, codeOk := slang.get_entry_point_code(linkedProgram, 0, 0)
	defer if codeDiagnostics != nil do codeDiagnostics->Release()
	if !codeOk {
		log(.Error, blobToString(codeDiagnostics))
		err = .Code
		return
	}
	defer codeBlob->Release()

	size := codeBlob->GetBufferSize()
	if size == 0 {
		log(.Error, "Shader code length is zero")
		err = .Code
		return
	}

	shaderCode = make([]u8, size)
	mem.copy(raw_data(shaderCode), codeBlob->GetBufferPointer(), int(size))
	return
}

endSlang :: proc() {
	slang.shutdown()
}
