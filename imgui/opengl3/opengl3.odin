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

// About GLSL version:
//  The 'glsl_version' initialization parameter should be nullptr (default) or a "#version XXX" string.
//  On computer platform the GLSL version default to "#version 130". On OpenGL ES 3 platform it defaults to "#version 300 es"
//  Only override if your GL version doesn't handle this GLSL version. See GLSL version table at the top of imgui_impl_opengl3.cpp.

package ImGui_ImplOpenGL3

import imgui ".."

import "core:mem"
import "core:strconv"
import "core:strings"
import "vendor:OpenGL"

// Follow "Getting Started" link and check examples/ folder to learn about using backends!
Init :: proc(glsl_version: cstring = nil, allocator := context.allocator) -> bool {
	glsl_version := glsl_version

	if !imgui.CHECKVERSION() {
		return false
	}

	io := imgui.GetIO()
	assert(io.BackendRendererUserData == nil, "Already initialized a renderer backend!")
	internal_allocator = allocator

	// Setup backend capabilities flags
	bd := new(Data, internal_allocator)
	io.BackendRendererUserData = bd
	io.BackendRendererName = "imgui_impl_opengl3"

	majour, minor: i32
	OpenGL.GetIntegerv(OpenGL.MAJOR_VERSION, &majour)
	OpenGL.GetIntegerv(OpenGL.MINOR_VERSION, &minor)

	bd.GlVersion = u32(majour) * 100 + u32(minor) * 10
	OpenGL.GetIntegerv(OpenGL.MAX_TEXTURE_SIZE, &bd.MaxTextureSize)

	if !bd.GlProfileIsES3 && bd.GlVersion >= 320 {
		OpenGL.GetIntegerv(OpenGL.CONTEXT_PROFILE_MASK, &bd.GlProfileMask)
	}
	bd.GlProfileIsCompat = bd.GlProfileMask & OpenGL.CONTEXT_COMPATIBILITY_PROFILE_BIT != 0

	bd.UseBufferSubData = false

	if bd.GlVersion >= 320 {
		// We can honor the ImDrawCmd::VtxOffset field, allowing for large meshes.
		io.BackendFlags += {.RendererHasVtxOffset}
	}
	// We can honor ImGuiPlatformIO::Textures[] requests during render.
	// We can create multi-viewports on the Renderer side (optional)
	io.BackendFlags += {.RendererHasTextures, .RendererHasViewports}

	platform_io := imgui.GetPlatformIO()
	platform_io.Renderer_TextureMaxWidth = bd.MaxTextureSize
	platform_io.Renderer_TextureMaxHeight = bd.MaxTextureSize

	// Store GLSL version string so we can refer to it later in case we recreate shaders.
	// Note: GLSL version is NOT the same as GL version. Leave this to nullptr if unsure.
	if (glsl_version == nil) {
		when ODIN_OS == .Darwin {
			glsl_version = "#version 150"
		} else {
			glsl_version = "#version 130"
		}
	}
	assert(len(glsl_version) + 2 < len(bd.GlslVersionString))
	mem.copy(&bd.GlslVersionString, rawptr(glsl_version), len(glsl_version))
	bd.GlslVersionString[len(glsl_version)] = '\n'

	// Detect extensions we support
	bd.HasPolygonMode = !bd.GlProfileIsES2 && bd.GlProfileIsES3
	bd.HasBindSampler = bd.GlVersion >= 330 || bd.GlProfileIsES3
	bd.HasClipOrigin = bd.GlVersion >= 450

	num_extensions: i32
	OpenGL.GetIntegerv(OpenGL.NUM_EXTENSIONS, &num_extensions)
	for i: i32 = 0; i < num_extensions; i += 1 {
		extension := OpenGL.GetStringi(OpenGL.EXTENSIONS, u32(i))
		if extension != nil && extension == "GL_ARB_clip_control" {
			bd.HasClipOrigin = true
		}
	}

	InitMultiViewportSupport()
	return true
}

Shutdown :: proc() {
	bd := GetBackendData()
	assert(bd != nil, "No renderer backend to shutdown, or already shutdown?")
	io := imgui.GetIO()
	platform_io := imgui.GetPlatformIO()

	ShutdownMultiViewportSupport()
	DestroyDeviceObjects()

	io.BackendRendererName = nil
	io.BackendRendererUserData = nil
	io.BackendFlags -= {.RendererHasVtxOffset, .RendererHasTextures, .RendererHasViewports}
	imgui.GuiPlatformIO_ClearRendererHandlers(platform_io)
	free(bd, internal_allocator)
}

NewFrame :: proc() {
	bd := GetBackendData()
	assert(bd != nil, "Context or backend not initialized! Did you call Init()?")

	if bd.ShaderHandle == 0 {
		if !CreateDeviceObjects() {
			panic("CreateDeviceObjects() failed!")
		}
	}
}

// OpenGL3 Render function.
// Note that this implementation is little overcomplicated because we are saving/setting up/restoring every OpenGL state explicitly.
// This is in order to be able to run within an OpenGL engine that doesn't do so.
RenderDrawData :: proc(draw_data: ^imgui.DrawData) {
	// Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
	fb_width := i32(draw_data.DisplaySize.x * draw_data.FramebufferScale.x)
	fb_height := i32(draw_data.DisplaySize.y * draw_data.FramebufferScale.y)
	if fb_width <= 0 || fb_height <= 0 {
		return
	}

	bd := GetBackendData()

	// Catch up with texture updates. Most of the times, the list will have 1 element with an OK status, aka nothing to do.
	// (This almost always points to ImGui::GetPlatformIO().Textures[] but is part of ImDrawData to allow overriding or disabling texture updates).
	if draw_data.Textures != nil {
		texs := draw_data.Textures
		for tex in texs.Data[:texs.Size] {
			if tex.Status != .OK {
				UpdateTexture(tex)
			}
		}
	}

	// Backup GL state
	last_active_texture: i32
	OpenGL.GetIntegerv(OpenGL.ACTIVE_TEXTURE, &last_active_texture)
	OpenGL.ActiveTexture(OpenGL.TEXTURE0)

	last_program, last_texture: i32
	OpenGL.GetIntegerv(OpenGL.CURRENT_PROGRAM, &last_program)
	OpenGL.GetIntegerv(OpenGL.TEXTURE_BINDING_2D, &last_texture)

	last_sampler, last_array_buffer: i32
	if bd.HasBindSampler {
		OpenGL.GetIntegerv(OpenGL.SAMPLER_BINDING, &last_sampler)
	} else {
		last_sampler = 0
	}
	OpenGL.GetIntegerv(OpenGL.ARRAY_BUFFER_BINDING, &last_array_buffer)

	last_vertex_array_object: i32
	OpenGL.GetIntegerv(OpenGL.VERTEX_ARRAY_BINDING, &last_vertex_array_object)

	last_polygon_mode: [2]i32
	if bd.HasPolygonMode {
		OpenGL.GetIntegerv(OpenGL.POLYGON_MODE, &last_polygon_mode[0])
	}

	last_viewport, last_scissor_box: [4]i32
	OpenGL.GetIntegerv(OpenGL.VIEWPORT, &last_viewport[0])
	OpenGL.GetIntegerv(OpenGL.SCISSOR_BOX, &last_scissor_box[0])

	last_blend_src_rgb, last_blend_dst_rgb, last_blend_src_alpha: i32
	last_blend_dst_alpha, last_blend_equation_rgb, last_blend_equation_alpha: i32
	OpenGL.GetIntegerv(OpenGL.BLEND_SRC_RGB, &last_blend_src_rgb)
	OpenGL.GetIntegerv(OpenGL.BLEND_DST_RGB, &last_blend_dst_rgb)
	OpenGL.GetIntegerv(OpenGL.BLEND_SRC_ALPHA, &last_blend_src_alpha)
	OpenGL.GetIntegerv(OpenGL.BLEND_DST_ALPHA, &last_blend_dst_alpha)
	OpenGL.GetIntegerv(OpenGL.BLEND_EQUATION_RGB, &last_blend_equation_rgb)
	OpenGL.GetIntegerv(OpenGL.BLEND_EQUATION_ALPHA, &last_blend_equation_alpha)

	last_enable_blend := OpenGL.IsEnabled(OpenGL.BLEND)
	last_enable_cull_face := OpenGL.IsEnabled(OpenGL.CULL_FACE)
	last_enable_depth_test := OpenGL.IsEnabled(OpenGL.DEPTH_TEST)
	last_enable_stencil_test := OpenGL.IsEnabled(OpenGL.STENCIL_TEST)
	last_enable_scissor_test := OpenGL.IsEnabled(OpenGL.SCISSOR_TEST)
	last_enable_primitive_restart :=
		!bd.GlProfileIsES3 && bd.GlVersion >= 310 ? OpenGL.IsEnabled(OpenGL.PRIMITIVE_RESTART) : false

	// Setup desired GL state
	// Recreate the VAO every time (this is to easily allow multiple GL contexts to be rendered to. VAO are not shared among GL contexts)
	// The renderer would actually work without any VAO bound, but then our VertexAttrib calls would overwrite the default one currently bound.
	vertex_array_object: u32
	OpenGL.GenVertexArrays(1, &vertex_array_object)
	SetupRenderState(draw_data, fb_width, fb_height, vertex_array_object)

	// Will project scissor/clipping rectangles into framebuffer space
	clip_off := draw_data.DisplayPos // (0,0) unless using multi-viewports
	clip_scale := draw_data.FramebufferScale // (1,1) unless using retina display which are often (2,2)

	// Render command lists
	draw_lists := &draw_data.CmdLists
	for draw_list in draw_lists.Data[:draw_lists.Size] {
		// Upload vertex/index buffers
		// - OpenGL drivers are in a very sorry state nowadays....
		//   During 2021 we attempted to switch from glBufferData() to orphaning+glBufferSubData() following reports
		//   of leaks on Intel GPU when using multi-viewports on Windows.
		// - After this we kept hearing of various display corruptions issues. We started disabling on non-Intel GPU, but issues still got reported on Intel.
		// - We are now back to using exclusively glBufferData(). So bd->UseBufferSubData IS ALWAYS FALSE in this code.
		//   We are keeping the old code path for a while in case people finding new issues may want to test the bd->UseBufferSubData path.
		// - See https://github.com/ocornut/imgui/issues/4468 and please report any corruption issues.
		vtx_buffer_size := imgui.VectorSizeInBytes(draw_list.VtxBuffer)
		idx_buffer_size := imgui.VectorSizeInBytes(draw_list.IdxBuffer)
		if bd.UseBufferSubData {
			if bd.VertexBufferSize < int(vtx_buffer_size) {
				bd.VertexBufferSize = int(vtx_buffer_size)
				OpenGL.BufferData(
					OpenGL.ARRAY_BUFFER,
					bd.VertexBufferSize,
					nil,
					OpenGL.STREAM_DRAW,
				)
			}
			if bd.IndexBufferSize < int(idx_buffer_size) {
				bd.IndexBufferSize = int(idx_buffer_size)
				OpenGL.BufferData(
					OpenGL.ELEMENT_ARRAY_BUFFER,
					bd.IndexBufferSize,
					nil,
					OpenGL.STREAM_DRAW,
				)
			}
			OpenGL.BufferSubData(
				OpenGL.ARRAY_BUFFER,
				0,
				int(vtx_buffer_size),
				draw_list.VtxBuffer.Data,
			)
			OpenGL.BufferSubData(
				OpenGL.ELEMENT_ARRAY_BUFFER,
				0,
				int(idx_buffer_size),
				draw_list.IdxBuffer.Data,
			)
		} else {
			OpenGL.BufferData(
				OpenGL.ARRAY_BUFFER,
				int(vtx_buffer_size),
				draw_list.VtxBuffer.Data,
				OpenGL.STREAM_DRAW,
			)
			OpenGL.BufferData(
				OpenGL.ELEMENT_ARRAY_BUFFER,
				int(idx_buffer_size),
				draw_list.IdxBuffer.Data,
				OpenGL.STREAM_DRAW,
			)
		}

		for cmd_i: i32 = 0; cmd_i < draw_list.CmdBuffer.Size; cmd_i += 1 {
			pcmd := &draw_list.CmdBuffer.Data[cmd_i]
			if pcmd.UserCallback != nil {
				// User callback, registered via ImDrawList::AddCallback()
				// (ImDrawCallback_ResetRenderState is a special callback value used by the user to request the renderer to reset render state.)
				if transmute(uintptr)pcmd.UserCallback == imgui.DrawCallback_ResetRenderState {
					SetupRenderState(draw_data, fb_width, fb_height, vertex_array_object)
				} else {
					pcmd.UserCallback(draw_list, pcmd)
				}
			} else {
				// Project scissor/clipping rectangles into framebuffer space
				clip_min := imgui.Vec2 {
					(pcmd.ClipRect.x - clip_off.x) * clip_scale.x,
					(pcmd.ClipRect.y - clip_off.y) * clip_scale.y,
				}
				clip_max := imgui.Vec2 {
					(pcmd.ClipRect.z - clip_off.x) * clip_scale.x,
					(pcmd.ClipRect.w - clip_off.y) * clip_scale.y,
				}
				if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y {
					continue
				}

				// Apply scissor/clipping rectangle (Y is inverted in OpenGL)
				OpenGL.Scissor(
					i32(clip_min.x),
					i32(f32(fb_height) - clip_max.y),
					i32(clip_max.x - clip_min.x),
					i32(clip_max.y - clip_min.y),
				)

				// Bind texture, Draw
				OpenGL.BindTexture(OpenGL.TEXTURE_2D, u32(imgui.DrawCmd_GetTexID(pcmd)))
				if bd.GlVersion >= 320 {
					OpenGL.DrawElementsBaseVertex(
						OpenGL.TRIANGLES,
						i32(pcmd.ElemCount),
						size_of(imgui.DrawIdx) == 2 ? OpenGL.UNSIGNED_SHORT : OpenGL.UNSIGNED_INT,
						rawptr(uintptr(pcmd.IdxOffset * size_of(imgui.DrawIdx))),
						i32(pcmd.VtxOffset),
					)
				} else {
					OpenGL.DrawElements(
						OpenGL.TRIANGLES,
						i32(pcmd.ElemCount),
						size_of(imgui.DrawIdx) == 2 ? OpenGL.UNSIGNED_SHORT : OpenGL.UNSIGNED_INT,
						rawptr(uintptr(pcmd.IdxOffset * size_of(imgui.DrawIdx))),
					)
				}
			}
		}
	}

	// Destroy the temporary VAO
	OpenGL.DeleteVertexArrays(1, &vertex_array_object)

	// Restore modified GL state
	// This "glIsProgram()" check is required because if the program is "pending deletion" at the time of binding backup, it will have been deleted by now and will cause an OpenGL error. See #6220.
	if last_program == 0 || OpenGL.IsProgram(u32(last_program)) {
		OpenGL.UseProgram(u32(last_program))
	}

	OpenGL.BindTexture(OpenGL.TEXTURE_2D, u32(last_texture))
	if bd.HasBindSampler {
		OpenGL.BindSampler(0, u32(last_sampler))
	}

	OpenGL.ActiveTexture(u32(last_active_texture))
	OpenGL.BindVertexArray(u32(last_vertex_array_object))
	OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, u32(last_array_buffer))
	OpenGL.BlendEquationSeparate(u32(last_blend_equation_rgb), u32(last_blend_equation_alpha))
	OpenGL.BlendFuncSeparate(
		u32(last_blend_src_rgb),
		u32(last_blend_dst_rgb),
		u32(last_blend_src_alpha),
		u32(last_blend_dst_alpha),
	)

	if last_enable_blend {
		OpenGL.Enable(OpenGL.BLEND)
	} else {
		OpenGL.Disable(OpenGL.BLEND)
	}

	if last_enable_cull_face {
		OpenGL.Enable(OpenGL.CULL_FACE)
	} else {
		OpenGL.Disable(OpenGL.CULL_FACE)
	}

	if last_enable_depth_test {
		OpenGL.Enable(OpenGL.DEPTH_TEST)
	} else {
		OpenGL.Disable(OpenGL.DEPTH_TEST)
	}

	if last_enable_stencil_test {
		OpenGL.Enable(OpenGL.STENCIL_TEST)
	} else {
		OpenGL.Disable(OpenGL.STENCIL_TEST)
	}

	if last_enable_scissor_test {
		OpenGL.Enable(OpenGL.SCISSOR_TEST)
	} else {
		OpenGL.Disable(OpenGL.SCISSOR_TEST)
	}

	if !bd.GlProfileIsES3 && bd.GlVersion >= 310 {
		if last_enable_primitive_restart {
			OpenGL.Enable(OpenGL.PRIMITIVE_RESTART)
		} else {
			OpenGL.Disable(OpenGL.PRIMITIVE_RESTART)
		}
	}

	// Desktop OpenGL 3.0 and OpenGL 3.1 had separate polygon draw modes for front-facing and back-facing faces of polygons
	if bd.HasPolygonMode {
		if (bd.GlVersion <= 310 || bd.GlProfileIsCompat) {
			OpenGL.PolygonMode(OpenGL.FRONT, u32(last_polygon_mode[0]))
			OpenGL.PolygonMode(OpenGL.BACK, u32(last_polygon_mode[1]))
		} else {
			OpenGL.PolygonMode(OpenGL.FRONT_AND_BACK, u32(last_polygon_mode[0]))
		}
	}

	OpenGL.Viewport(last_viewport[0], last_viewport[1], last_viewport[2], last_viewport[3])
	OpenGL.Scissor(
		last_scissor_box[0],
		last_scissor_box[1],
		last_scissor_box[2],
		last_scissor_box[3],
	)
}

// (Optional) Called by Init/NewFrame/Shutdown
CreateDeviceObjects :: proc() -> bool {
	bd := GetBackendData()

	// Backup GL state
	last_texture, last_array_buffer: i32
	OpenGL.GetIntegerv(OpenGL.TEXTURE_BINDING_2D, &last_texture)
	OpenGL.GetIntegerv(OpenGL.ARRAY_BUFFER_BINDING, &last_array_buffer)

	last_pixel_unpack_buffer: i32
	if bd.GlVersion >= 210 {
		OpenGL.GetIntegerv(OpenGL.PIXEL_UNPACK_BUFFER_BINDING, &last_pixel_unpack_buffer)
		OpenGL.BindBuffer(OpenGL.PIXEL_UNPACK_BUFFER, 0)
	}

	last_vertex_array: i32
	OpenGL.GetIntegerv(OpenGL.VERTEX_ARRAY_BINDING, &last_vertex_array)

	// Parse GLSL version string
	glsl_version: i32 = 130
	// sscanf(bd.GlslVersionString, "#version %d", &glsl_version)
	if strings.has_prefix(string(bd.GlslVersionString[:]), "#version ") {
		ver, ok := strconv.parse_int(string(bd.GlslVersionString[len("#version "):]))
		if ok {
			glsl_version = i32(ver)
		}
	}

	vertex_shader_glsl_120: cstring = "\nuniform mat4 ProjMtx;attribute vec2 Position;attribute vec2 UV;attribute vec4 Color;varying vec2 Frag_UV;varying vec4 Frag_Color;void main(){Frag_UV = UV;Frag_Color = Color;gl_Position = ProjMtx * vec4(Position.xy,0,1);}"

	vertex_shader_glsl_130: cstring = "\nuniform mat4 ProjMtx;in vec2 Position;in vec2 UV;in vec4 Color;out vec2 Frag_UV;out vec4 Frag_Color;void main(){Frag_UV = UV;Frag_Color = Color;gl_Position = ProjMtx * vec4(Position.xy,0,1);}"

	vertex_shader_glsl_300_es: cstring = "\nprecision highp float;layout (location = 0) in vec2 Position;layout (location = 1) in vec2 UV;layout (location = 2) in vec4 Color;uniform mat4 ProjMtx;out vec2 Frag_UV;out vec4 Frag_Color;void main(){Frag_UV = UV;Frag_Color = Color;gl_Position = ProjMtx * vec4(Position.xy,0,1);}"

	vertex_shader_glsl_410_core: cstring = "\nlayout (location = 0) in vec2 Position;layout (location = 1) in vec2 UV;layout (location = 2) in vec4 Color;uniform mat4 ProjMtx;out vec2 Frag_UV;out vec4 Frag_Color;void main(){Frag_UV = UV;Frag_Color = Color;gl_Position = ProjMtx * vec4(Position.xy,0,1);}"

	fragment_shader_glsl_120: cstring = "\n#ifdef GL_ES\nprecision mediump float;\n#endif\nuniform sampler2D Texture;varying vec2 Frag_UV;varying vec4 Frag_Color;void main(){gl_FragColor = Frag_Color * texture2D(Texture, Frag_UV.st);}"

	fragment_shader_glsl_130: cstring = "\nuniform sampler2D Texture;in vec2 Frag_UV;in vec4 Frag_Color;out vec4 Out_Color;void main(){Out_Color = Frag_Color * texture(Texture, Frag_UV.st);}"

	fragment_shader_glsl_300_es: cstring = "\nprecision mediump float;uniform sampler2D Texture;in vec2 Frag_UV;in vec4 Frag_Color;layout (location = 0) out vec4 Out_Color;void main(){Out_Color = Frag_Color * texture(Texture, Frag_UV.st);}"

	fragment_shader_glsl_410_core: cstring = "\nin vec2 Frag_UV;in vec4 Frag_Color;uniform sampler2D Texture;layout (location = 0) out vec4 Out_Color;void main(){Out_Color = Frag_Color * texture(Texture, Frag_UV.st);}"

	// Select shaders matching our GLSL versions
	vertex_shader: cstring
	fragment_shader: cstring
	if glsl_version < 130 {
		vertex_shader = vertex_shader_glsl_120
		fragment_shader = fragment_shader_glsl_120
	} else if glsl_version >= 410 {
		vertex_shader = vertex_shader_glsl_410_core
		fragment_shader = fragment_shader_glsl_410_core
	} else if glsl_version == 300 {
		vertex_shader = vertex_shader_glsl_300_es
		fragment_shader = fragment_shader_glsl_300_es
	} else {
		vertex_shader = vertex_shader_glsl_130
		fragment_shader = fragment_shader_glsl_130
	}

	// Create shaders
	vertex_shader_with_version: [2]cstring = {cstring(&bd.GlslVersionString[0]), vertex_shader}
	vert_handle: u32
	vert_handle = OpenGL.CreateShader(OpenGL.VERTEX_SHADER)
	OpenGL.ShaderSource(vert_handle, 2, &vertex_shader_with_version[0], nil)
	OpenGL.CompileShader(vert_handle)
	if !CheckShader(vert_handle, "vertex shader") {
		return false
	}

	fragment_shader_with_version: [2]cstring = {cstring(&bd.GlslVersionString[0]), fragment_shader}
	frag_handle := OpenGL.CreateShader(OpenGL.FRAGMENT_SHADER)
	OpenGL.ShaderSource(frag_handle, 2, &fragment_shader_with_version[0], nil)
	OpenGL.CompileShader(frag_handle)
	if !CheckShader(frag_handle, "fragment shader") {
		return false
	}

	// Link
	bd.ShaderHandle = OpenGL.CreateProgram()
	OpenGL.AttachShader(bd.ShaderHandle, vert_handle)
	OpenGL.AttachShader(bd.ShaderHandle, frag_handle)
	OpenGL.LinkProgram(bd.ShaderHandle)
	if !CheckProgram(bd.ShaderHandle, "shader program") {
		return false
	}

	OpenGL.DetachShader(bd.ShaderHandle, vert_handle)
	OpenGL.DetachShader(bd.ShaderHandle, frag_handle)
	OpenGL.DeleteShader(vert_handle)
	OpenGL.DeleteShader(frag_handle)

	bd.AttribLocationTex = OpenGL.GetUniformLocation(bd.ShaderHandle, "Texture")
	bd.AttribLocationProjMtx = OpenGL.GetUniformLocation(bd.ShaderHandle, "ProjMtx")
	bd.AttribLocationVtxPos = u32(OpenGL.GetAttribLocation(bd.ShaderHandle, "Position"))
	bd.AttribLocationVtxUV = u32(OpenGL.GetAttribLocation(bd.ShaderHandle, "UV"))
	bd.AttribLocationVtxColor = u32(OpenGL.GetAttribLocation(bd.ShaderHandle, "Color"))

	// Create buffers
	OpenGL.GenBuffers(1, &bd.VboHandle)
	OpenGL.GenBuffers(1, &bd.ElementsHandle)

	// Restore modified GL state
	OpenGL.BindTexture(OpenGL.TEXTURE_2D, u32(last_texture))
	OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, u32(last_array_buffer))
	if bd.GlVersion >= 210 {
		OpenGL.BindBuffer(OpenGL.PIXEL_UNPACK_BUFFER, u32(last_pixel_unpack_buffer))
	}
	OpenGL.BindVertexArray(u32(last_vertex_array))

	return true
}


DestroyDeviceObjects :: proc() {
	bd := GetBackendData()

	if bd.VboHandle != 0 {
		OpenGL.DeleteBuffers(1, &bd.VboHandle)
		bd.VboHandle = 0
	}

	if bd.ElementsHandle != 0 {
		OpenGL.DeleteBuffers(1, &bd.ElementsHandle)
		bd.ElementsHandle = 0
	}

	if bd.ShaderHandle != 0 {
		OpenGL.DeleteProgram(bd.ShaderHandle)
		bd.ShaderHandle = 0
	}

	// Destroy all textures
	texs := &imgui.GetPlatformIO().Textures
	for tex in texs.Data[:texs.Size] {
		if tex.RefCount == 1 {
			DestroyTexture(tex)
		}
	}
}

// (Advanced) Use e.g. if you need to precisely control the timing of texture updates (e.g. for staged rendering), by setting ImDrawData::Textures = nullptr to handle this manually.
UpdateTexture :: proc(tex: ^imgui.TextureData) {
	// FIXME: Consider backing up and restoring
	if tex.Status == .WantCreate || tex.Status == .WantUpdates {
		OpenGL.PixelStorei(OpenGL.UNPACK_ROW_LENGTH, 0)
	}

	if tex.Status == .WantCreate {
		// Create and upload new texture to graphics system
		//IMGUI_DEBUG_LOG("UpdateTexture #%03d: WantCreate %dx%d\n", tex->UniqueID, tex->Width, tex->Height);
		assert(tex.TexID == 0 && tex.BackendUserData == nil)
		assert(tex.Format == .RGBA32)
		pixels := imgui.TextureData_GetPixels(tex)
		gl_texture_id: u32

		// Upload texture to graphics system
		// (Bilinear sampling is required by default. Set 'io.Fonts->Flags |= ImFontAtlasFlags_NoBakedLines' or 'style.AntiAliasedLinesUseTex = false' to allow point/nearest sampling)
		last_texture: i32
		OpenGL.GetIntegerv(OpenGL.TEXTURE_BINDING_2D, &last_texture)
		OpenGL.GenTextures(1, &gl_texture_id)
		OpenGL.BindTexture(OpenGL.TEXTURE_2D, gl_texture_id)
		OpenGL.TexParameteri(OpenGL.TEXTURE_2D, OpenGL.TEXTURE_MIN_FILTER, OpenGL.LINEAR)
		OpenGL.TexParameteri(OpenGL.TEXTURE_2D, OpenGL.TEXTURE_MAG_FILTER, OpenGL.LINEAR)
		OpenGL.TexParameteri(OpenGL.TEXTURE_2D, OpenGL.TEXTURE_WRAP_S, OpenGL.CLAMP_TO_EDGE)
		OpenGL.TexParameteri(OpenGL.TEXTURE_2D, OpenGL.TEXTURE_WRAP_T, OpenGL.CLAMP_TO_EDGE)
		OpenGL.TexImage2D(
			OpenGL.TEXTURE_2D,
			0,
			OpenGL.RGBA,
			tex.Width,
			tex.Height,
			0,
			OpenGL.RGBA,
			OpenGL.UNSIGNED_BYTE,
			pixels,
		)

		// Store identifiers
		imgui.TextureData_SetTexID(tex, imgui.TextureID(gl_texture_id))
		imgui.TextureData_SetStatus(tex, .OK)

		// Restore state
		OpenGL.BindTexture(OpenGL.TEXTURE_2D, u32(last_texture))
	} else if tex.Status == .WantUpdates {
		// Update selected blocks. We only ever write to textures regions which have never been used before!
		// This backend choose to use tex->Updates[] but you can use tex->UpdateRect to upload a single region.
		last_texture: i32
		OpenGL.GetIntegerv(OpenGL.TEXTURE_BINDING_2D, &last_texture)

		gl_tex_id := tex.TexID
		OpenGL.BindTexture(OpenGL.TEXTURE_2D, u32(gl_tex_id))
		OpenGL.PixelStorei(OpenGL.UNPACK_ROW_LENGTH, tex.Width)
		updates := &tex.Updates
		for r in updates.Data[:updates.Size] {
			OpenGL.TexSubImage2D(
				OpenGL.TEXTURE_2D,
				0,
				i32(r.x),
				i32(r.y),
				i32(r.w),
				i32(r.h),
				OpenGL.RGBA,
				OpenGL.UNSIGNED_BYTE,
				imgui.TextureData_GetPixelsAt(tex, i32(r.x), i32(r.y)),
			)
		}
		OpenGL.PixelStorei(OpenGL.UNPACK_ROW_LENGTH, 0)
		imgui.TextureData_SetStatus(tex, .OK)
		OpenGL.BindTexture(OpenGL.TEXTURE_2D, u32(last_texture)) // Restore state
	} else if tex.Status == .WantDestroy && tex.UnusedFrames > 0 {
		DestroyTexture(tex)
	}
}

