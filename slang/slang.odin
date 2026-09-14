package slang

// Odin bindings for the Slang shading language compiler.
//
// These bindings talk directly to Slang's COM-lite ABI (the same vtable-based
// interfaces used from C++: ISlangUnknown, IGlobalSession, ISession, IModule,
// IComponentType, IEntryPoint, ...) rather than a custom C shim. Interface
// pointers behave like their C++ counterparts: call methods with Odin's
// `obj->Method(args)` syntax (e.g. `session->loadModule(...)`), and every
// object derived from ISlangUnknown must be released with `->Release()` once
// you're done with it.
//
// See include/slang.h (copied from the Slang release this binding targets)
// for the authoritative API documentation these bindings mirror.

// SlangInt / SlangUInt are defined in slang.h to be pointer-width (64-bit on
// 64-bit targets, 32-bit on 32-bit targets). Odin's `int`/`uint` have the same
// property, so they line up without any conditional compilation.
Int :: int
UInt :: uint

Bool :: bool

// Matches the layout of SlangUUID / COM's GUID.
UUID :: struct {
	data1: u32,
	data2: u16,
	data3: u16,
	data4: [8]u8,
}

// A result code for a Slang API operation. Compatible with Windows HRESULT:
// negative is failure, zero or positive is success.
Result :: distinct i32

succeeded :: #force_inline proc "contextless" (result: Result) -> bool {
	return result >= 0
}

failed :: #force_inline proc "contextless" (result: Result) -> bool {
	return result < 0
}

OK: Result : 0
FAIL := transmute(Result)u32(0x8000_4005)

E_NOT_IMPLEMENTED := transmute(Result)u32(0x8000_4001)
E_NO_INTERFACE := transmute(Result)u32(0x8000_4002)
E_ABORT := transmute(Result)u32(0x8000_4004)

E_INVALID_HANDLE := transmute(Result)u32(0x8007_0006)
E_INVALID_ARG := transmute(Result)u32(0x8007_0057)
E_OUT_OF_MEMORY := transmute(Result)u32(0x8007_000e)

E_BUFFER_TOO_SMALL := transmute(Result)u32(0x8200_0001)
E_UNINITIALIZED := transmute(Result)u32(0x8200_0002)
E_PENDING := transmute(Result)u32(0x8200_0003)
E_CANNOT_OPEN := transmute(Result)u32(0x8200_0004)
E_NOT_FOUND := transmute(Result)u32(0x8200_0005)
E_INTERNAL_FAIL := transmute(Result)u32(0x8200_0006)
E_NOT_AVAILABLE := transmute(Result)u32(0x8200_0007)

// Passed as the apiVersion parameter of createGlobalSession / stored in
// GlobalSessionDesc.apiVersion to identify the API version client code uses.
API_VERSION :: 0
