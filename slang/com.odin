package slang

// Base COM-lite interface. Every Slang interface (IGlobalSession, ISession,
// IModule, IComponentType, IEntryPoint, IBlob, ...) starts with this vtable
// layout, exactly like C++'s ISlangUnknown / COM's IUnknown.
//
//   session->AddRef()
//   session->Release()
//   session->QueryInterface(&IGlobalSession_UUID, &ptr)
IUnknown :: struct {
	using vtable: ^IUnknown_VTable,
}

IUnknown_VTable :: struct {
	QueryInterface: proc "system" (this: ^IUnknown, uuid: ^UUID, out_object: ^rawptr) -> Result,
	AddRef:         proc "system" (this: ^IUnknown) -> u32,
	Release:        proc "system" (this: ^IUnknown) -> u32,
}

IUnknown_UUID := UUID{0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}

// Query `this` for the interface identified by `uuid`. On success the
// returned object has already been AddRef'd - Release it when done.
query_interface :: proc(this: ^IUnknown, uuid: ^UUID) -> (object: rawptr, ok: bool) {
	ok = succeeded(this->QueryInterface(uuid, &object))
	return
}

// A "blob" of binary data. Compatible with ID3DBlob/ID3D10Blob.
IBlob :: struct #raw_union {
	#subtype unknown: IUnknown,
	using vtable:     ^IBlob_VTable,
}

IBlob_VTable :: struct {
	using unknown_vtable: IUnknown_VTable,
	GetBufferPointer: proc "system" (this: ^IBlob) -> rawptr,
	GetBufferSize:    proc "system" (this: ^IBlob) -> uint,
}

IBlob_UUID := UUID{0x8BA5FB08, 0x5195, 0x40e2, {0xAC, 0x58, 0x0D, 0x98, 0x9C, 0x3A, 0x01, 0x02}}

// Opaque handle types.
//
// These interfaces/structs are part of the Slang ABI (pointers to them are
// passed across the API boundary) but their own methods/fields are not bound
// here, since the compilation pipeline this package targets never needs to
// call through them directly - only to hold and forward the pointer.
ISlangFileSystem :: struct {}
ISlangMutableFileSystem :: struct {}
ISlangSharedLibrary :: struct {}
ISlangSharedLibraryLoader :: struct {}
IMetadata :: struct {}
ITypeConformance :: struct {}
Compile_Request :: struct {} // slang::SlangCompileRequest / ICompileRequest (deprecated API)

// Reflection types. Opaque for now - not bound by this package.
Type_Reflection :: struct {}
Type_Layout_Reflection :: struct {}
Program_Layout :: struct {} // aka ShaderReflection
Function_Reflection :: struct {}
Decl_Reflection :: struct {}
