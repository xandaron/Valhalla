// dear imgui: Platform Backend for GLFW
// This needs to be used along with a Renderer (e.g. OpenGL3, Vulkan, WebGPU..)
// (Info: GLFW is a cross-platform general purpose library for handling windows, inputs, OpenGL/Vulkan graphics context creation, etc.)
// (Requires: GLFW 3.0+. Prefer GLFW 3.3+/3.4+ for full feature support.)

// Implemented features:
//  [X] Platform: Clipboard support.
//  [X] Platform: Mouse support. Can discriminate Mouse/TouchScreen/Pen (Windows only).
//  [X] Platform: Keyboard support. Since 1.87 we are using the io.AddKeyEvent() function. Pass ImGuiKey values to all key functions e.g. ImGui::IsKeyPressed(ImGuiKey_Space). [Legacy GLFW_KEY_* values are obsolete since 1.87 and not supported since 1.91.5]
//  [X] Platform: Gamepad support. Enable with 'io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad'.
//  [X] Platform: Mouse cursor shape and visibility (ImGuiBackendFlags_HasMouseCursors) with GLFW 3.1+. Resizing cursors requires GLFW 3.4+! Disable with 'io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange'.
//  [X] Platform: Multi-viewport support (multiple windows). Enable with 'io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable'.
//  [X] Multiple Dear ImGui contexts support.
// Missing features or Issues:
//  [ ] Platform: Touch events are only correctly identified as Touch on Windows. This create issues with some interactions. GLFW doesn't provide a way to identify touch inputs from mouse inputs, we cannot call io.AddMouseSourceEvent() to identify the source. We provide a Windows-specific workaround.
//  [ ] Platform: Missing ImGuiMouseCursor_Wait and ImGuiMouseCursor_Progress cursors.
//  [ ] Platform: Multi-viewport: Missing ImGuiBackendFlags_HasParentViewport support. The viewport->ParentViewportID field is ignored, and therefore io.ConfigViewportsNoDefaultParent has no effect either.

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

package ImGui_ImplGlfw

import imgui ".."

import "base:runtime"
import "core:time"
import "vendor:glfw"
import glfwBindings "vendor:glfw/bindings"

import "core:sys/windows"

GLFW_VERSION_COMBINED ::
	glfw.VERSION_MAJOR * 1000 + glfw.VERSION_MINOR * 100 + glfw.VERSION_REVISION

// C++ included NetBSD but odin's x11 package doesn't support NetBSD
X11 :: ODIN_OS == .Linux || ODIN_OS == .FreeBSD || ODIN_OS == .OpenBSD

GlfwClientApi :: enum {
	OpenGL,
	Vulkan,
	Unknown, // Anything else fits here.
}

ShouldChainCallback :: proc(bd: ^Data, window: glfw.WindowHandle) -> bool {
	return bd.CallbacksChainForAllWindows ? true : (window == bd.Window)
}

MouseButtonCallback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackMousebutton != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackMousebutton(window, button, action, mods)
	}

	// Workaround for Linux: ignore mouse up events which are following an focus loss following a viewport creation
	if bd.MouseIgnoreButtonUp && action == glfw.RELEASE {
		return
	}

	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)
	UpdateKeyModifiers(io, window)
	if button >= 0 && button < i32(imgui.GuiMouseButton.COUNT) {
		imgui.GuiIO_AddMouseButtonEvent(io, button, action == glfw.PRESS)
	}
}

ScrollCallback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackScroll != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackScroll(window, xoffset, yoffset)
	}

	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)
	imgui.GuiIO_AddMouseWheelEvent(io, f32(xoffset), f32(yoffset))
}

KeyCallback :: proc "c" (window: glfw.WindowHandle, keycode, scancode, action, mods: i32) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackKey != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackKey(window, keycode, scancode, action, mods)
	}

	if action != glfw.PRESS && action != glfw.RELEASE {
		return
	}

	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)
	UpdateKeyModifiers(io, window)

	if keycode >= 0 && keycode < len(bd.KeyOwnerWindows) {
		bd.KeyOwnerWindows[keycode] = action == glfw.PRESS ? window : nil
	}

	keycode := TranslateUntranslatedKey(keycode, scancode)

	imgui_key := KeyToImGuiKey(keycode, scancode)
	imgui.GuiIO_AddKeyEvent(io, imgui_key, action == glfw.PRESS)
	imgui.GuiIO_SetKeyEventNativeData(io, imgui_key, keycode, scancode) // To support legacy indexing (<1.87 user code)
}

WindowFocusCallback :: proc "c" (window: glfw.WindowHandle, focused: i32) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackWindowFocus != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackWindowFocus(window, focused)
	}

	// Workaround for Linux: when losing focus with MouseIgnoreButtonUpWaitForFocusLoss set, we will temporarily ignore subsequent Mouse Up events
	bd.MouseIgnoreButtonUp = bd.MouseIgnoreButtonUpWaitForFocusLoss && focused == 0
	bd.MouseIgnoreButtonUpWaitForFocusLoss = false

	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)
	imgui.GuiIO_AddFocusEvent(io, focused != 0)
}

CursorPosCallback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackCursorPos != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackCursorPos(window, x, y)
	}

	vec2: imgui.Vec2 = {f32(x), f32(y)}
	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)
	if .ViewportsEnable in io.ConfigFlags {
		window_x, window_y := glfw.GetWindowPos(window)
		vec2 += {f32(window_x), f32(window_y)}
	}
	imgui.GuiIO_AddMousePosEvent(io, vec2.x, vec2.y)
	bd.LastValidMousePos = vec2
}

// Workaround: X11 seems to send spurious Leave/Enter events which would make us lose our position,
// so we back it up and restore on Leave/Enter (see https://github.com/ocornut/imgui/issues/4984)
CursorEnterCallback :: proc "c" (window: glfw.WindowHandle, entered: i32) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackCursorEnter != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackCursorEnter(window, entered)
	}

	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)
	if entered == 1 {
		bd.MouseWindow = window
		imgui.GuiIO_AddMousePosEvent(io, bd.LastValidMousePos.x, bd.LastValidMousePos.y)
	} else if bd.MouseWindow == window {
		bd.LastValidMousePos = io.MousePos
		bd.MouseWindow = nil
		imgui.GuiIO_AddMousePosEvent(io, -max(f32), -max(f32))
	}
}

CharCallback :: proc "c" (window: glfw.WindowHandle, c: rune) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackChar != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackChar(window, rune(c))
	}

	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)
	imgui.GuiIO_AddInputCharacter(io, u32(c))
}

// This function is technically part of the API even if we stopped using the callback, so leaving it around.
MonitorCallback :: proc "c" (_: glfw.MonitorHandle, _: i32) {}

InstallCallbacks :: proc(window: glfw.WindowHandle) {
	bd := GetBackendData(window)
	assert(bd.Window == window)
	assert(!bd.InstalledCallbacks, "Callbacks already installed!")

	bd.PrevUserCallbackWindowFocus = glfw.SetWindowFocusCallback(window, WindowFocusCallback)
	bd.PrevUserCallbackCursorEnter = glfw.SetCursorEnterCallback(window, CursorEnterCallback)
	bd.PrevUserCallbackCursorPos = glfw.SetCursorPosCallback(window, CursorPosCallback)
	bd.PrevUserCallbackMousebutton = glfw.SetMouseButtonCallback(window, MouseButtonCallback)
	bd.PrevUserCallbackScroll = glfw.SetScrollCallback(window, ScrollCallback)
	bd.PrevUserCallbackKey = glfw.SetKeyCallback(window, KeyCallback)
	bd.PrevUserCallbackChar = glfw.SetCharCallback(window, CharCallback)
	bd.PrevUserCallbackMonitor = glfw.SetMonitorCallback(MonitorCallback)
	bd.InstalledCallbacks = true
}

RestoreCallbacks :: proc(window: glfw.WindowHandle) {
	bd := GetBackendData(window)
	assert(bd.Window == window)
	assert(bd.InstalledCallbacks, "Callbacks not installed!")

	glfw.SetWindowFocusCallback(window, bd.PrevUserCallbackWindowFocus)
	glfw.SetCursorEnterCallback(window, bd.PrevUserCallbackCursorEnter)
	glfw.SetCursorPosCallback(window, bd.PrevUserCallbackCursorPos)
	glfw.SetMouseButtonCallback(window, bd.PrevUserCallbackMousebutton)
	glfw.SetScrollCallback(window, bd.PrevUserCallbackScroll)
	glfw.SetKeyCallback(window, bd.PrevUserCallbackKey)
	glfw.SetCharCallback(window, bd.PrevUserCallbackChar)
	bd.InstalledCallbacks = false
	bd.PrevUserCallbackWindowFocus = nil
	bd.PrevUserCallbackCursorEnter = nil
	bd.PrevUserCallbackCursorPos = nil
	bd.PrevUserCallbackMousebutton = nil
	bd.PrevUserCallbackScroll = nil
	bd.PrevUserCallbackKey = nil
	bd.PrevUserCallbackChar = nil
}

// Set to 'true' to enable chaining installed callbacks for all windows (including secondary viewports created by backends or by user).
// This is 'false' by default meaning we only chain callbacks for the main viewport.
// We cannot set this to 'true' by default because user callbacks code may be not testing the 'window' parameter of their callback.
// If you set this to 'true' your user callback code will need to make sure you are testing the 'window' parameter.
SetCallbacksChainForAllWindows :: proc(chain_for_all_windows: bool) {
	GetBackendData().CallbacksChainForAllWindows = chain_for_all_windows
}

InitForOpenGL :: proc(
	window: glfw.WindowHandle,
	install_callbacks: bool,
	allocator := context.allocator,
) -> bool {
	return Init(window, install_callbacks, .OpenGL, allocator)
}

InitForVulkan :: proc(
	window: glfw.WindowHandle,
	install_callbacks: bool,
	allocator := context.allocator,
) -> bool {
	return Init(window, install_callbacks, .Vulkan, allocator)
}

InitForOther :: proc(
	window: glfw.WindowHandle,
	install_callbacks: bool,
	allocator := context.allocator,
) -> bool {
	return Init(window, install_callbacks, .Unknown, allocator)
}

Shutdown :: proc() {
	bd := GetBackendData()
	assert(bd != nil, "No platform backend to shutdown, or already shutdown?")

	io := imgui.Gui_GetIO()
	platform_io := imgui.Gui_GetPlatformIO()

	ShutdownMultiViewportSupport()
	if bd.InstalledCallbacks {
		RestoreCallbacks(bd.Window)
	}

	for cursor_n := 0; cursor_n < int(imgui.GuiMouseCursor.COUNT); cursor_n += 1 {
		glfw.DestroyCursor(bd.MouseCursors[cursor_n])
	}

	when ODIN_OS == .Windows {
		// Windows: restore our WndProc hook
		main_viewport := imgui.Gui_GetMainViewport()
		windows.SetPropW(
			windows.HWND(main_viewport.PlatformHandleRaw),
			"IMGUI_BACKEND_DATA",
			nil,
		)
		windows.SetWindowLongPtrW(
			windows.HWND(main_viewport.PlatformHandleRaw),
			windows.GWLP_WNDPROC,
			transmute(windows.LONG_PTR)(bd.PrevWndProc),
		)
		bd.PrevWndProc = nil
	}

	io.BackendPlatformName = nil
	io.BackendPlatformUserData = nil
	io.BackendFlags -= {
		.HasMouseCursors,
		.HasSetMousePos,
		.HasGamepad,
		.PlatformHasViewports,
		.HasMouseHoveredViewport,
	}
	imgui.GuiPlatformIO_ClearPlatformHandlers(platform_io)
	free(imgui.Gui_GetMainViewport().PlatformUserData, internal_allocator)
	delete_key(&ContextMap, bd.Window)
	delete(ContextMap)
	free(bd, internal_allocator)
}

NewFrame :: proc() {
	io := imgui.Gui_GetIO()
	bd := GetBackendData()
	assert(
		bd != nil,
		"Context or backend not initialized! Did you call ImGui_ImplGlfw_InitForXXX()?",
	)

	// Setup main viewport size (every frame to accommodate for window resizing)
	GetWindowSizeAndFramebufferScale(bd.Window, &io.DisplaySize, &io.DisplayFramebufferScale)
	UpdateMonitors()

	// Setup time step
	// (Accept glfwGetTime() not returning a monotonically increasing value. Seems to happens on disconnecting peripherals and probably on VMs and Emscripten, see #6491, #6189, #6114, #3644)
	current_time := glfw.GetTime()
	if current_time <= bd.Time {
		current_time = bd.Time + 0.00001
	}
	io.DeltaTime = bd.Time > 0 ? f32(current_time - bd.Time) : f32(1 / 60)
	bd.Time = current_time

	bd.MouseIgnoreButtonUp = false
	UpdateMouseData()
	UpdateMouseCursor()

	// Update game controllers (if enabled and available)
	UpdateGamepads()
}

Sleep :: #force_inline proc(milliseconds: i32) {
	time.sleep(time.Duration(milliseconds) * time.Millisecond)
}

