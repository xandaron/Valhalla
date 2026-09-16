package ImGui

// These imports could be wrong.
@(private)
ARCH :: "x64" when ODIN_ARCH == .amd64 else "arm64"

@(private)
IMGUI_LIB :: (
	     "imgui_windows_" + ARCH + ".lib" when ODIN_OS == .Windows
	else "imgui_linux_" + ARCH + ".a"     when ODIN_OS == .Linux
	else "imgui_darwin_" + ARCH + ".a"    when ODIN_OS == .Darwin
	else "wasm/c_imgui.o"                 when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32
	else ""
)

when IMGUI_LIB != "" {
	when !#exists(IMGUI_LIB) {
		#panic("Could not find the compiled ImGui library")
	}
}

@(private)
TRUETYPE_LIB :: (
	     "vendor:stb/lib/stb_truetype.lib"      when ODIN_OS == .Windows
	else "vendor:stb/lib/stb_truetype.a"        when ODIN_OS == .Linux
	else "vendor:stb/lib/darwin/stb_truetype.a" when ODIN_OS == .Darwin
	else "vendor:stb/lib/stb_truetype_wasm.o"   when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32
	else ""
)

when TRUETYPE_LIB != "" {
	when !#exists(TRUETYPE_LIB) {
		#panic("Could not find the compiled STB libraries, they can be compiled by running `make -C \"" + ODIN_ROOT + "vendor/stb/src\"`")
	}
}

@(private)
RECT_PACK_LIB :: (
	     "vendor:stb/lib/stb_rect_pack.lib"      when ODIN_OS == .Windows
	else "vendor:stb/lib/stb_rect_pack.a"        when ODIN_OS == .Linux
	else "vendor:stb/lib/darwin/stb_rect_pack.a" when ODIN_OS == .Darwin
	else "vendor:stb/lib/stb_rect_pack_wasm.o"   when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32
	else ""
)

when RECT_PACK_LIB != "" {
	when !#exists(RECT_PACK_LIB) {
		#panic("Could not find the compiled STB libraries, they can be compiled by running `make -C \"" + ODIN_ROOT + "vendor/stb/src\"`")
	}
}

@(private)
SPRINTF_LIB :: (
	     "vendor:stb/lib/stb_sprintf.lib"      when ODIN_OS == .Windows
	else "vendor:stb/lib/stb_sprintf.a"        when ODIN_OS == .Linux
	else "vendor:stb/lib/darwin/stb_sprintf.a" when ODIN_OS == .Darwin
	else "vendor:stb/lib/stb_sprintf_wasm.o"   when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32
	else ""
)

when SPRINTF_LIB != "" {
	when !#exists(SPRINTF_LIB) {
		#panic("Could not find the compiled STB libraries, they can be compiled by running `make -C \"" + ODIN_ROOT + "vendor/stb/src\"`")
	}
}

