#+private
// dear imgui: Renderer Backend for modern OpenGL with shaders / programmatic pipeline
// - Desktop GL: 2.x 3.x 4.x
// - Embedded GL: ES 2.0 (WebGL 1.0), ES 3.0 (WebGL 2.0)
// This needs to be used along with a Platform Backend (e.g. GLFW, SDL, Win32, custom..)

// Implemented features:
//  [X] Renderer: User texture binding. Use 'GLuint' OpenGL texture as texture identifier. Read the FAQ about ImTextureID/ImTextureRef!
//  [x] Renderer: Large meshes support (64k+ vertices) even with 16-bit indices (ImGuiBackendFlags_RendererHasVtxOffset) [Desktop OpenGL only!]
//  [X] Renderer: Texture updates support for dynamic font atlas (ImGuiBackendFlags_RendererHasTextures).
//  [X] Renderer: Multi-viewport support (multiple windows). Enable with 'io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable'.

// About WebGL/ES:
// - You need to '#define IMGUI_IMPL_OPENGL_ES2' or '#define IMGUI_IMPL_OPENGL_ES3' to use WebGL or OpenGL ES.
// - This is done automatically on iOS, Android and Emscripten targets.
// - For other targets, the define needs to be visible from the imgui_impl_opengl3.cpp compilation unit. If unsure, define globally or in imconfig.h.

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// CHANGELOG
// (minor and older changes stripped away, please see git history for details)
//  2026-XX-XX: Platform: Added support for multiple windows via the ImGuiPlatformIO interface.
//  2025-12-11: OpenGL: Fixed embedded loader multiple init/shutdown cycles broken on some platforms. (#8792, #9112)
//  2025-09-18: Call platform_io.ClearRendererHandlers() on shutdown.
//  2025-07-22: OpenGL: Add and call embedded loader shutdown during ImGui_ImplOpenGL3_Shutdown() to facilitate multiple init/shutdown cycles in same process. (#8792)
//  2025-07-15: OpenGL: Set GL_UNPACK_ALIGNMENT to 1 before updating textures (#8802) + restore non-WebGL/ES update path that doesn't require a CPU-side copy.
//  2025-06-11: OpenGL: Added support for ImGuiBackendFlags_RendererHasTextures, for dynamic font atlas. Removed ImGui_ImplOpenGL3_CreateFontsTexture() and ImGui_ImplOpenGL3_DestroyFontsTexture().
//  2025-06-04: OpenGL: Made GLES 3.20 contexts not access GL_CONTEXT_PROFILE_MASK nor GL_PRIMITIVE_RESTART. (#8664)
//  2025-02-18: OpenGL: Lazily reinitialize embedded GL loader for when calling backend from e.g. other DLL boundaries. (#8406)
//  2024-10-07: OpenGL: Changed default texture sampler to Clamp instead of Repeat/Wrap.
//  2024-06-28: OpenGL: ImGui_ImplOpenGL3_NewFrame() recreates font texture if it has been destroyed by ImGui_ImplOpenGL3_DestroyFontsTexture(). (#7748)
//  2024-05-07: OpenGL: Update loader for Linux to support EGL/GLVND. (#7562)
//  2024-04-16: OpenGL: Detect ES3 contexts on desktop based on version string, to e.g. avoid calling glPolygonMode() on them. (#7447)
//  2024-01-09: OpenGL: Update GL3W based imgui_impl_opengl3_loader.h to load "libGL.so" and variants, fixing regression on distros missing a symlink.
//  2023-11-08: OpenGL: Update GL3W based imgui_impl_opengl3_loader.h to load "libGL.so" instead of "libGL.so.1", accommodating for NetBSD systems having only "libGL.so.3" available. (#6983)
//  2023-10-05: OpenGL: Rename symbols in our internal loader so that LTO compilation with another copy of gl3w is possible. (#6875, #6668, #4445)
//  2023-06-20: OpenGL: Fixed erroneous use glGetIntegerv(GL_CONTEXT_PROFILE_MASK) on contexts lower than 3.2. (#6539, #6333)
//  2023-05-09: OpenGL: Support for glBindSampler() backup/restore on ES3. (#6375)
//  2023-04-18: OpenGL: Restore front and back polygon mode separately when supported by context. (#6333)
//  2023-03-23: OpenGL: Properly restoring "no shader program bound" if it was the case prior to running the rendering function. (#6267, #6220, #6224)
//  2023-03-15: OpenGL: Fixed GL loader crash when GL_VERSION returns nullptr. (#6154, #4445, #3530)
//  2023-03-06: OpenGL: Fixed restoration of a potentially deleted OpenGL program, by calling glIsProgram(). (#6220, #6224)
//  2022-11-09: OpenGL: Reverted use of glBufferSubData(), too many corruptions issues + old issues seemingly can't be reproed with Intel drivers nowadays (revert 2021-12-15 and 2022-05-23 changes).
//  2022-10-11: Using 'nullptr' instead of 'NULL' as per our switch to C++11.
//  2022-09-27: OpenGL: Added ability to '#define IMGUI_IMPL_OPENGL_DEBUG'.
//  2022-05-23: OpenGL: Reworking 2021-12-15 "Using buffer orphaning" so it only happens on Intel GPU, seems to cause problems otherwise. (#4468, #4825, #4832, #5127).
//  2022-05-13: OpenGL: Fixed state corruption on OpenGL ES 2.0 due to not preserving GL_ELEMENT_ARRAY_BUFFER_BINDING and vertex attribute states.
//  2021-12-15: OpenGL: Using buffer orphaning + glBufferSubData(), seems to fix leaks with multi-viewports with some Intel HD drivers.
//  2021-08-23: OpenGL: Fixed ES 3.0 shader ("#version 300 es") use normal precision floats to avoid wobbly rendering at HD resolutions.
//  2021-08-19: OpenGL: Embed and use our own minimal GL loader (imgui_impl_opengl3_loader.h), removing requirement and support for third-party loader.
//  2021-06-29: Reorganized backend to pull data from a single structure to facilitate usage with multiple-contexts (all g_XXXX access changed to bd->XXXX).
//  2021-06-25: OpenGL: Use OES_vertex_array extension on Emscripten + backup/restore current state.
//  2021-06-21: OpenGL: Destroy individual vertex/fragment shader objects right after they are linked into the main shader.
//  2021-05-24: OpenGL: Access GL_CLIP_ORIGIN when "GL_ARB_clip_control" extension is detected, inside of just OpenGL 4.5 version.
//  2021-05-19: OpenGL: Replaced direct access to ImDrawCmd::TextureId with a call to ImDrawCmd::GetTexID(). (will become a requirement)
//  2021-04-06: OpenGL: Don't try to read GL_CLIP_ORIGIN unless we're OpenGL 4.5 or greater.
//  2021-02-18: OpenGL: Change blending equation to preserve alpha in output buffer.
//  2021-01-03: OpenGL: Backup, setup and restore GL_STENCIL_TEST state.
//  2020-10-23: OpenGL: Backup, setup and restore GL_PRIMITIVE_RESTART state.
//  2020-10-15: OpenGL: Use glGetString(GL_VERSION) instead of glGetIntegerv(GL_MAJOR_VERSION, ...) when the later returns zero (e.g. Desktop GL 2.x)
//  2020-09-17: OpenGL: Fix to avoid compiling/calling glBindSampler() on ES or pre-3.3 context which have the defines set by a loader.
//  2020-07-10: OpenGL: Added support for glad2 OpenGL loader.
//  2020-05-08: OpenGL: Made default GLSL version 150 (instead of 130) on OSX.
//  2020-04-21: OpenGL: Fixed handling of glClipControl(GL_UPPER_LEFT) by inverting projection matrix.
//  2020-04-12: OpenGL: Fixed context version check mistakenly testing for 4.0+ instead of 3.2+ to enable ImGuiBackendFlags_RendererHasVtxOffset.
//  2020-03-24: OpenGL: Added support for glbinding 2.x OpenGL loader.
//  2020-01-07: OpenGL: Added support for glbinding 3.x OpenGL loader.
//  2019-10-25: OpenGL: Using a combination of GL define and runtime GL version to decide whether to use glDrawElementsBaseVertex(). Fix building with pre-3.2 GL loaders.
//  2019-09-22: OpenGL: Detect default GL loader using __has_include compiler facility.
//  2019-09-16: OpenGL: Tweak initialization code to allow application calling ImGui_ImplOpenGL3_CreateFontsTexture() before the first NewFrame() call.
//  2019-05-29: OpenGL: Desktop GL only: Added support for large mesh (64K+ vertices), enable ImGuiBackendFlags_RendererHasVtxOffset flag.
//  2019-04-30: OpenGL: Added support for special ImDrawCallback_ResetRenderState callback to reset render state.
//  2019-03-29: OpenGL: Not calling glBindBuffer more than necessary in the render loop.
//  2019-03-15: OpenGL: Added a GL call + comments in ImGui_ImplOpenGL3_Init() to detect uninitialized GL function loaders early.
//  2019-03-03: OpenGL: Fix support for ES 2.0 (WebGL 1.0).
//  2019-02-20: OpenGL: Fix for OSX not supporting OpenGL 4.5, we don't try to read GL_CLIP_ORIGIN even if defined by the headers/loader.
//  2019-02-11: OpenGL: Projecting clipping rectangles correctly using draw_data->FramebufferScale to allow multi-viewports for retina display.
//  2019-02-01: OpenGL: Using GLSL 410 shaders for any version over 410 (e.g. 430, 450).
//  2018-11-30: Misc: Setting up io.BackendRendererName so it can be displayed in the About Window.
//  2018-11-13: OpenGL: Support for GL 4.5's glClipControl(GL_UPPER_LEFT) / GL_CLIP_ORIGIN.
//  2018-08-29: OpenGL: Added support for more OpenGL loaders: glew and glad, with comments indicative that any loader can be used.
//  2018-08-09: OpenGL: Default to OpenGL ES 3 on iOS and Android. GLSL version default to "#version 300 ES".
//  2018-07-30: OpenGL: Support for GLSL 300 ES and 410 core. Fixes for Emscripten compilation.
//  2018-07-10: OpenGL: Support for more GLSL versions (based on the GLSL version string). Added error output when shaders fail to compile/link.
//  2018-06-08: Misc: Extracted imgui_impl_opengl3.cpp/.h away from the old combined GLFW/SDL+OpenGL3 examples.
//  2018-06-08: OpenGL: Use draw_data->DisplayPos and draw_data->DisplaySize to setup projection matrix and clipping rectangle.
//  2018-05-25: OpenGL: Removed unnecessary backup/restore of GL_ELEMENT_ARRAY_BUFFER_BINDING since this is part of the VAO state.
//  2018-05-14: OpenGL: Making the call to glBindSampler() optional so 3.2 context won't fail if the function is a nullptr pointer.
//  2018-03-06: OpenGL: Added const char* glsl_version parameter to ImGui_ImplOpenGL3_Init() so user can override the GLSL version e.g. "#version 150".
//  2018-02-23: OpenGL: Create the VAO in the render function so the setup can more easily be used with multiple shared GL context.
//  2018-02-16: Misc: Obsoleted the io.RenderDrawListsFn callback and exposed ImGui_ImplSdlGL3_RenderDrawData() in the .h file so you can call it yourself.
//  2018-01-07: OpenGL: Changed GLSL shader version from 330 to 150.
//  2017-09-01: OpenGL: Save and restore current bound sampler. Save and restore current polygon mode.
//  2017-05-01: OpenGL: Fixed save and restore of current blend func state.
//  2017-05-01: OpenGL: Fixed save and restore of current GL_ACTIVE_TEXTURE.
//  2016-09-05: OpenGL: Fixed save and restore of current scissor rectangle.
//  2016-07-29: OpenGL: Explicitly setting GL_UNPACK_ROW_LENGTH to reduce issues because SDL changes it. (#752)

//----------------------------------------
// OpenGL    GLSL      GLSL
// version   version   string
//----------------------------------------
//  2.0       110       "#version 110"
//  2.1       120       "#version 120"
//  3.0       130       "#version 130"
//  3.1       140       "#version 140"
//  3.2       150       "#version 150"
//  3.3       330       "#version 330 core"
//  4.0       400       "#version 400 core"
//  4.1       410       "#version 410 core"
//  4.2       420       "#version 410 core"
//  4.3       430       "#version 430 core"
//  ES 2.0    100       "#version 100"      = WebGL 1.0
//  ES 3.0    300       "#version 300 es"   = WebGL 2.0
//----------------------------------------

package ImGui_ImplOpenGL3

import imgui ".."

import "base:runtime"
import "core:mem"
import "core:fmt"
import "vendor:OpenGL"


internal_allocator: mem.Allocator

// OpenGL Data
Data :: struct {
	GlVersion:                 u32, // Extracted at runtime using GL_MAJOR_VERSION, GL_MINOR_VERSION queries (e.g. 320 for GL 3.2)
	GlslVersionString:         [32]u8, // Specified by user or detected based on compile time GL settings.
	GlProfileIsES2:            bool,
	GlProfileIsES3:            bool,
	GlProfileIsCompat:         bool,
	GlProfileMask:             i32,
	MaxTextureSize:            i32,
	ShaderHandle:              u32,
	AttribLocationTex:         i32, // Uniforms location
	AttribLocationProjMtx:     i32,
	AttribLocationVtxPos:      u32, // Vertex attributes location
	AttribLocationVtxUV:       u32,
	AttribLocationVtxColor:    u32,
	VboHandle, ElementsHandle: u32,
	VertexBufferSize:          int,
	IndexBufferSize:           int,
	HasPolygonMode:            bool,
	HasBindSampler:            bool,
	HasClipOrigin:             bool,
	UseBufferSubData:          bool,
	TempBuffer:                imgui.Vector(u8),
}

// Backend data stored in io.BackendRendererUserData to allow support for multiple Dear ImGui contexts
// It is STRONGLY preferred that you use docking branch with multi-viewports (== single Dear ImGui context + multiple windows) instead of multiple Dear ImGui contexts.
GetBackendData :: proc() -> ^Data {
	return(
		imgui.GetCurrentContext() != nil ? (^Data)(imgui.GetIO().BackendRendererUserData) : nil \
	)
}

SetupRenderState :: proc(
	draw_data: ^imgui.DrawData,
	fb_width, fb_height: i32,
	vertex_array_object: u32,
) {
	bd := GetBackendData()

	// Setup render state: alpha-blending enabled, no face culling, no depth testing, scissor enabled, polygon fill
	OpenGL.Enable(OpenGL.BLEND)
	OpenGL.BlendEquation(OpenGL.FUNC_ADD)
	OpenGL.BlendFuncSeparate(
		OpenGL.SRC_ALPHA,
		OpenGL.ONE_MINUS_SRC_ALPHA,
		OpenGL.ONE,
		OpenGL.ONE_MINUS_SRC_ALPHA,
	)
	OpenGL.Disable(OpenGL.CULL_FACE)
	OpenGL.Disable(OpenGL.DEPTH_TEST)
	OpenGL.Disable(OpenGL.STENCIL_TEST)
	OpenGL.Enable(OpenGL.SCISSOR_TEST)
	if !bd.GlProfileIsES3 && bd.GlVersion >= 310 {
		OpenGL.Disable(OpenGL.PRIMITIVE_RESTART)
	}
	if bd.HasPolygonMode {
		OpenGL.PolygonMode(OpenGL.FRONT_AND_BACK, OpenGL.FILL)
	}

	// Support for GL 4.5 rarely used glClipControl(GL_UPPER_LEFT)
	clip_origin_lower_left := true
	if bd.HasClipOrigin {
		current_clip_origin: i32
		OpenGL.GetIntegerv(OpenGL.CLIP_ORIGIN, &current_clip_origin)
		if current_clip_origin == OpenGL.UPPER_LEFT {
			clip_origin_lower_left = false
		}
	}

	// Setup viewport, orthographic projection matrix
	// Our visible imgui space lies from draw_data->DisplayPos (top left) to draw_data->DisplayPos+data_data->DisplaySize (bottom right). DisplayPos is (0,0) for single viewport apps.
	OpenGL.Viewport(0, 0, fb_width, fb_height)
	L := draw_data.DisplayPos.x
	R := draw_data.DisplayPos.x + draw_data.DisplaySize.x
	T := draw_data.DisplayPos.y
	B := draw_data.DisplayPos.y + draw_data.DisplaySize.y
	if !clip_origin_lower_left {
		tmp := T
		T = B
		B = tmp
	}
	ortho_projection := [4][4]f32 {
		{2 / (R - L), 0, 0, 0},
		{0, 2 / (T - B), 0, 0},
		{0, 0, -1, 0},
		{(R + L) / (L - R), (T + B) / (B - T), 0, 1},
	}
	OpenGL.UseProgram(bd.ShaderHandle)
	OpenGL.Uniform1i(bd.AttribLocationTex, 0)
	OpenGL.UniformMatrix4fv(bd.AttribLocationProjMtx, 1, false, &ortho_projection[0][0])

	if bd.HasBindSampler {
		// We use combined texture/sampler state. Applications using GL 3.3 and GL ES 3.0 may set that otherwise.
		OpenGL.BindSampler(0, 0)
	}

	OpenGL.BindVertexArray(vertex_array_object);

	// Bind vertex/index buffers and setup attributes for ImDrawVert
	OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, bd.VboHandle)
	OpenGL.BindBuffer(OpenGL.ELEMENT_ARRAY_BUFFER, bd.ElementsHandle)
	OpenGL.EnableVertexAttribArray(bd.AttribLocationVtxPos)
	OpenGL.EnableVertexAttribArray(bd.AttribLocationVtxUV)
	OpenGL.EnableVertexAttribArray(bd.AttribLocationVtxColor)
	OpenGL.VertexAttribPointer(
		bd.AttribLocationVtxPos,
		2,
		OpenGL.FLOAT,
		false,
		size_of(imgui.DrawVert),
		offset_of(imgui.DrawVert, pos),
	)
	OpenGL.VertexAttribPointer(
		bd.AttribLocationVtxUV,
		2,
		OpenGL.FLOAT,
		false,
		size_of(imgui.DrawVert),
		offset_of(imgui.DrawVert, uv),
	)
	OpenGL.VertexAttribPointer(
		bd.AttribLocationVtxColor,
		4,
		OpenGL.UNSIGNED_BYTE,
		true,
		size_of(imgui.DrawVert),
		offset_of(imgui.DrawVert, col),
	)
}

DestroyTexture :: proc(tex: ^imgui.TextureData) {
	OpenGL.DeleteTextures(1, ([^]u32)(&tex.TexID))

	// Clear identifiers and mark as destroyed (in order to allow e.g. calling InvalidateDeviceObjects while running)
	imgui.TextureData_SetTexID(tex, imgui.TextureID_Invalid)
	imgui.TextureData_SetStatus(tex, .Destroyed)
}

// If you get an error please report on github. You may try different GL context version or GLSL version. See GL<>GLSL version table at the top of this file.
// TODO: error logging
CheckShader :: proc(handle: u32, desc: cstring) -> bool {
	bd := GetBackendData()
	status, log_length: i32
	OpenGL.GetShaderiv(handle, OpenGL.COMPILE_STATUS, &status)
	OpenGL.GetShaderiv(handle, OpenGL.INFO_LOG_LENGTH, &log_length)
	if status == 0 {
		fmt.printfln("ERROR: CreateDeviceObjects: failed to compile %s! With GLSL: %s", desc, cstring(&bd.GlslVersionString[0]))
	}
	if log_length > 1 {
		buf := imgui.NewVector(u8)
		imgui.VectorResize(&buf, log_length + 1)
		OpenGL.GetShaderInfoLog(handle, log_length, nil, imgui.VectorBegin(buf))
		fmt.printfln(string(buf.Data[:buf.Size]))
	}
	return status != 0
}

// If you get an error please report on GitHub. You may try different GL context version or GLSL version.
CheckProgram :: proc(handle: u32, desc: cstring) -> bool {
	bd := GetBackendData()
	status, log_length: i32
	OpenGL.GetProgramiv(handle, OpenGL.LINK_STATUS, &status)
	OpenGL.GetProgramiv(handle, OpenGL.INFO_LOG_LENGTH, &log_length)
	if status == 0 {
		fmt.printfln("ERROR: ImGui_ImplOpenGL3_CreateDeviceObjects: failed to link %s! With GLSL %s", desc, cstring(&bd.GlslVersionString[0]))
	}
	if log_length > 1 {
		buf := imgui.NewVector(u8)
		imgui.VectorResize(&buf, log_length + 1)
		OpenGL.GetProgramInfoLog(handle, log_length, nil, imgui.VectorBegin(buf))
		fmt.printfln(string(buf.Data[:buf.Size]))
	}
	return status != 0
}

// //--------------------------------------------------------------------------------------------------------
// // MULTI-VIEWPORT / PLATFORM INTERFACE SUPPORT
// // This is an _advanced_ and _optional_ feature, allowing the backend to create and handle multiple viewports simultaneously.
// // If you are new to dear imgui or creating a new binding for dear imgui, it is recommended that you completely ignore this section first..
// //--------------------------------------------------------------------------------------------------------

RenderWindow :: proc "c" (viewport: ^imgui.GuiViewport, _: rawptr) {
	if .NoRendererClear not_in viewport.Flags {
		clear_color := imgui.Vec4{0, 0, 0, 1}
		OpenGL.ClearColor(clear_color.x, clear_color.y, clear_color.z, clear_color.w)
		OpenGL.Clear(OpenGL.COLOR_BUFFER_BIT)
	}

	context = runtime.default_context()
	RenderDrawData(viewport.DrawData)
}

InitMultiViewportSupport :: proc() {
	platform_io := imgui.GetPlatformIO()
	platform_io.Renderer_RenderWindow = RenderWindow
}

ShutdownMultiViewportSupport :: proc() {
	imgui.DestroyPlatformWindows()
}

