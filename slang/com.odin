package slang

// Base COM-lite interface. Every Slang interface (Global_Session, Session,
// Module, Component_Type, Entry_Point, Blob, ...) starts with this vtable
// layout, exactly like C++'s ISlangUnknown / COM's IUnknown.
//
//   session->AddRef()
//   session->Release()
//   session->QueryInterface(&Global_Session_UUID, &ptr)
Unknown :: struct {
	using vtable: ^Unknown_VTable,
}

@(private="file")
Unknown_VTable :: struct {
	QueryInterface: proc "system" (this: ^Unknown, uuid: ^UUID, out_object: ^rawptr) -> Result,
	AddRef:         proc "system" (this: ^Unknown) -> u32,
	Release:        proc "system" (this: ^Unknown) -> u32,
}

@(private="file")
Unknown_UUID := UUID{0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}

// Query `this` for the interface identified by `uuid`. On success the
// returned object has already been AddRef'd - Release it when done.
query_interface :: proc(this: ^Unknown, uuid: ^UUID) -> (object: rawptr, ok: bool) {
	ok = succeeded(this->QueryInterface(uuid, &object))
	return
}

add_ref :: proc(object: ^Unknown) {
	if object == nil {
		return
	}
	object->AddRef()
}

release :: proc(object: ^Unknown) {
	if object == nil {
		return
	}
	object->Release()
}

// A "blob" of binary data. Compatible with ID3DBlob/ID3D10Blob.
Blob :: struct #raw_union {
	#subtype unknown: Unknown,
	using vtable:     ^Blob_VTable,
}

@(private="file")
Blob_VTable :: struct {
	using unknown_vtable: Unknown_VTable,
	GetBufferPointer: proc "system" (this: ^Blob) -> rawptr,
	GetBufferSize:    proc "system" (this: ^Blob) -> uint,
}

@(private="file")
Blob_UUID := UUID{0x8BA5FB08, 0x5195, 0x40e2, {0xAC, 0x58, 0x0D, 0x98, 0x9C, 0x3A, 0x01, 0x02}}

get_buffer_pointer :: proc(this: ^Blob) -> rawptr {
	return this->GetBufferPointer()
}

get_buffer_size :: proc(this: ^Blob) -> uint {
	return this->GetBufferSize()
}

// Opaque handle types.
//
// These interfaces/structs are part of the Slang ABI (pointers to them are
// passed across the API boundary) but their own methods/fields are not bound
// here, since the compilation pipeline this package targets never needs to
// call through them directly - only to hold and forward the pointer.
Slang_File_System :: struct {}
Slang_Mutable_File_System :: struct {}
Slang_Shared_Library :: struct {}
Slang_Shared_Library_Loader :: struct {}
Metadata :: struct {}
Type_Conformance :: struct {}
Compile_Request :: struct {} // slang::SlangCompileRequest / ICompileRequest (deprecated API)

// Reflection types. Opaque for now - not bound by this package.
Type_Reflection :: struct {}
Type_Layout_Reflection :: struct {}
Program_Layout :: struct {} // aka ShaderReflection
Function_Reflection :: struct {}
Decl_Reflection :: struct {}
