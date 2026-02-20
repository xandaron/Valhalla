package ImGui_ImplGlfw

import imgui ".."

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:time"
import "vendor:glfw"
import glfwBindings "vendor:glfw/bindings"
import vk "vendor:vulkan"

import "core:sys/linux"
import "core:sys/posix"
import "core:sys/windows"

GLFW_VERSION_COMBINED ::
	glfw.VERSION_MAJOR * 1000 + glfw.VERSION_MINOR * 100 + glfw.VERSION_REVISION

X11 :: ODIN_OS == .Linux || ODIN_OS == .FreeBSD || ODIN_OS == .OpenBSD || ODIN_OS == .NetBSD

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

	io := imgui.GetIOImGuiContextPtr(bd.Context)
	UpdateKeyModifiers(io, window)
	if button >= 0 && button < transmute(i32)imgui.MouseButton.COUNT {
		imgui.IO_AddMouseButtonEvent(io, button, action == glfw.PRESS)
	}
}

ScrollCallback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackScroll != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackScroll(window, xoffset, yoffset)
	}

	io := imgui.GetIOImGuiContextPtr(bd.Context)
	imgui.IO_AddMouseWheelEvent(io, f32(xoffset), f32(yoffset))
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

	io := imgui.GetIOImGuiContextPtr(bd.Context)
	UpdateKeyModifiers(io, window)

	if keycode >= 0 && keycode < len(bd.KeyOwnerWindows) {
		bd.KeyOwnerWindows[keycode] = action == glfw.PRESS ? window : nil
	}

	keycode := TranslateUntranslatedKey(keycode, scancode)

	imgui_key := KeyToImGuiKey(keycode, scancode)
	imgui.IO_AddKeyEvent(io, imgui_key, action == glfw.PRESS)
	imgui.IO_SetKeyEventNativeData(io, imgui_key, keycode, scancode) // To support legacy indexing (<1.87 user code)
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

	io := imgui.GetIOImGuiContextPtr(bd.Context)
	imgui.IO_AddFocusEvent(io, focused != 0)
}

CursorPosCallback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackCursorPos != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackCursorPos(window, x, y)
	}

	vec2: imgui.Vec2 = {f32(x), f32(y)}
	io := imgui.GetIOImGuiContextPtr(bd.Context)
	if .ViewportsEnable in io.ConfigFlags {
		window_x, window_y := glfw.GetWindowPos(window)
		vec2 += {f32(window_x), f32(window_y)}
	}
	imgui.IO_AddMousePosEvent(io, vec2.x, vec2.y)
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

	io := imgui.GetIOImGuiContextPtr(bd.Context)
	if entered == 1 {
		bd.MouseWindow = window
		imgui.IO_AddMousePosEvent(io, bd.LastValidMousePos.x, bd.LastValidMousePos.y)
	} else if bd.MouseWindow == window {
		bd.LastValidMousePos = io.MousePos
		bd.MouseWindow = nil
		imgui.IO_AddMousePosEvent(io, -max(f32), -max(f32))
	}
}

CharCallback :: proc "c" (window: glfw.WindowHandle, c: rune) {
	context = runtime.default_context()
	bd := GetBackendData(window)
	if bd.PrevUserCallbackChar != nil && ShouldChainCallback(bd, window) {
		bd.PrevUserCallbackChar(window, rune(c))
	}

	io := imgui.GetIOImGuiContextPtr(bd.Context)
	imgui.IO_AddInputCharacter(io, u32(c))
}

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

Init :: proc(window: glfw.WindowHandle, install_callbacks: bool) -> bool {
	io := imgui.GetIO()
	imgui.CHECKVERSION()
	assert(io.BackendPlatformUserData == nil, "Already initialized a platform backend!")

	// Setup backend capabilities flags
	bd := new(Data)
	fmt.bprintf(bd.BackendPlatformName[:], "imgui_impl_glfw (%d)", GLFW_VERSION_COMBINED)
	io.BackendPlatformUserData = bd
	io.BackendPlatformName = transmute(cstring)(&bd.BackendPlatformName[0])
	io.BackendFlags += {.HasMouseCursors, .HasSetMousePos}

	bd.IsWayland = glfw.GetPlatform() == glfw.PLATFORM_WAYLAND

	has_viewports := true
	if bd.IsWayland {
		has_viewports = false
	}
	if has_viewports {
		io.BackendFlags += {.PlatformHasViewports} // We can create multi-viewports on the Platform side (optional)
	}
	io.BackendFlags += {.HasMouseHoveredViewport} // We can call io.AddMouseViewportEvent() with correct data (optional)

	bd.Context = imgui.GetCurrentContext()
	bd.Window = window
	bd.Time = 0.0
	ContextMap[window] = bd.Context

	platform_io := imgui.GetPlatformIO()

	SetClipboardText :: proc "c" (ctx: ^imgui.Context, text: cstring) {
		glfw.SetClipboardString(nil, text)
	}
	GetClipboardText :: proc "c" (ctx: ^imgui.Context) -> cstring {
		return glfwBindings.GetClipboardString(nil)
	}

	platform_io.Platform_SetClipboardTextFn = SetClipboardText
	platform_io.Platform_GetClipboardTextFn = GetClipboardText

	// Create mouse cursors
	// (By design, on X11 cursors are user configurable and some cursors may be missing. When a cursor doesn't exist,
	// GLFW will emit an error which will often be printed by the app, so we temporarily disable error reporting.
	// Missing cursors will return nullptr and our _UpdateMouseCursor() function will use the Arrow cursor instead.)
	prev_error_callback := glfw.SetErrorCallback(nil)
	bd.MouseCursors[imgui.MouseCursor.Arrow] = glfw.CreateStandardCursor(glfw.ARROW_CURSOR)
	bd.MouseCursors[imgui.MouseCursor.TextInput] = glfw.CreateStandardCursor(glfw.IBEAM_CURSOR)
	bd.MouseCursors[imgui.MouseCursor.ResizeNS] = glfw.CreateStandardCursor(glfw.VRESIZE_CURSOR)
	bd.MouseCursors[imgui.MouseCursor.ResizeEW] = glfw.CreateStandardCursor(glfw.HRESIZE_CURSOR)
	bd.MouseCursors[imgui.MouseCursor.Hand] = glfw.CreateStandardCursor(glfw.HAND_CURSOR)
	bd.MouseCursors[imgui.MouseCursor.ResizeAll] = glfw.CreateStandardCursor(
		glfw.RESIZE_ALL_CURSOR,
	)
	bd.MouseCursors[imgui.MouseCursor.ResizeNESW] = glfw.CreateStandardCursor(
		glfw.RESIZE_NESW_CURSOR,
	)
	bd.MouseCursors[imgui.MouseCursor.ResizeNWSE] = glfw.CreateStandardCursor(
		glfw.RESIZE_NWSE_CURSOR,
	)
	bd.MouseCursors[imgui.MouseCursor.NotAllowed] = glfw.CreateStandardCursor(
		glfw.NOT_ALLOWED_CURSOR,
	)
	glfw.SetErrorCallback(prev_error_callback)
	glfw.GetError()

	if install_callbacks {
		InstallCallbacks(window)
	}

	UpdateMonitors()

	// Set platform dependent data in viewport
	main_viewport := imgui.GetMainViewport()
	main_viewport.PlatformHandle = bd.Window
	when ODIN_OS == .Windows {
		main_viewport.PlatformHandleRaw = glfw.GetWin32Window(bd.Window)
	} else when ODIN_OS == .Darwin {
		main_viewport.PlatformHandleRaw = glfw.GetCocoaWindow(bd.Window)
	}

	if has_viewports {
		InitMultiViewportSupport()
	}

	// Windows: register a WndProc hook so we can intercept some messages.
	when ODIN_OS == .Windows {
		hwnd := transmute(windows.HWND)main_viewport.PlatformHandleRaw
		windows.SetPropW(hwnd, "IMGUI_BACKEND_DATA", transmute(windows.HANDLE)bd)
		bd.PrevWndProc = transmute(windows.WNDPROC)windows.GetWindowLongPtrW(
			hwnd,
			windows.GWLP_WNDPROC,
		)
		assert(bd.PrevWndProc != nil)
		windows.SetWindowLongPtrW(hwnd, windows.GWLP_WNDPROC, transmute(windows.LONG_PTR)WndProc)
	} else when X11 {
		//     if (!bd->IsWayland)
		//     {
		//         // Load X11 module dynamically. Copied from the way that GLFW does it in x11_init.c
		// #if defined(__CYGWIN__)
		//         const char* x11_module_path = "libX11-6.so";
		// #elif defined(__OpenBSD__) || defined(__NetBSD__)
		//         const char* x11_module_path = "libX11.so";
		// #else
		//         const char* x11_module_path = "libX11.so.6";
		// #endif
		//         bd->X11Module = dlopen(x11_module_path, RTLD_LAZY | RTLD_LOCAL);
		//         bd->XInternAtom = (PFN_XInternAtom)dlsym(bd->X11Module, "XInternAtom");
		//         bd->XChangeProperty = (PFN_XChangeProperty)dlsym(bd->X11Module, "XChangeProperty");
		//         bd->XChangeWindowAttributes = (PFN_XChangeWindowAttributes)dlsym(bd->X11Module, "XChangeWindowAttributes");
		//         bd->XFlush = (PFN_XFlush)dlsym(bd->X11Module, "XFlush");
		//         IM_ASSERT(bd->XInternAtom != nullptr && bd->XChangeProperty != nullptr && bd->XChangeWindowAttributes != nullptr && bd->XFlush != nullptr);
		//     }
	}

	return true
}

Shutdown :: proc() {
	bd := GetBackendData()
	assert(bd != nil, "No platform backend to shutdown, or already shutdown?")

	io := imgui.GetIO()
	platform_io := imgui.GetPlatformIO()

	ShutdownMultiViewportSupport()
	if bd.InstalledCallbacks {
		RestoreCallbacks(bd.Window)
	}

	for cursor_n := 0; cursor_n < int(imgui.MouseCursor.COUNT); cursor_n += 1 {
		glfw.DestroyCursor(bd.MouseCursors[cursor_n])
	}

	when ODIN_OS == .Windows {
		// Windows: restore our WndProc hook
		main_viewport := imgui.GetMainViewport()
		windows.SetPropW(
			transmute(windows.HWND)main_viewport.PlatformHandleRaw,
			"IMGUI_BACKEND_DATA",
			nil,
		)
		windows.SetWindowLongPtrW(
			transmute(windows.HWND)main_viewport.PlatformHandleRaw,
			windows.GWLP_WNDPROC,
			transmute(windows.LONG_PTR)bd.PrevWndProc,
		)
		bd.PrevWndProc = nil
	} else when X11 {
		if (bd.X11Module != nil) {
			// dlclose(bd.X11Module)
		}
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
	imgui.PlatformIO_ClearPlatformHandlers(platform_io)
	imgui.DestroyContext(bd.Context)
	ContextMap[bd.Window] = nil
	free(bd)
}

NewFrame :: proc() {
	io := imgui.GetIO()
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

// GLFW doesn't provide a portable sleep function
Sleep :: proc(milliseconds: i32) {
	time.sleep(time.Duration(milliseconds) * time.Millisecond)
}

@(private = "package")
DataBase :: struct {
	Context:                             ^imgui.Context,
	Window:                              glfw.WindowHandle,
	Time:                                f64,
	MouseWindow:                         glfw.WindowHandle,
	MouseCursors:                        [imgui.MouseCursor.COUNT]glfw.CursorHandle,
	LastMouseCursor:                     glfw.CursorHandle,
	MouseIgnoreButtonUpWaitForFocusLoss: bool,
	MouseIgnoreButtonUp:                 bool,
	LastValidMousePos:                   imgui.Vec2,
	KeyOwnerWindows:                     [glfw.KEY_LAST]glfw.WindowHandle,
	IsWayland:                           bool,
	InstalledCallbacks:                  bool,
	CallbacksChainForAllWindows:         bool,
	BackendPlatformName:                 [32]u8,

	// Chain GLFW callbacks: our callbacks will call the user's previously installed callbacks, if any.
	PrevUserCallbackWindowFocus:         glfw.WindowFocusProc,
	PrevUserCallbackCursorPos:           glfw.CursorPosProc,
	PrevUserCallbackCursorEnter:         glfw.CursorEnterProc,
	PrevUserCallbackMousebutton:         glfw.MouseButtonProc,
	PrevUserCallbackScroll:              glfw.ScrollProc,
	PrevUserCallbackKey:                 glfw.KeyProc,
	PrevUserCallbackChar:                glfw.CharProc,

	// 	#ifdef _WIN32
	//     WNDPROC                 PrevWndProc;
	// #endif

	// #if GLFW_HAS_X11
	//     // Module and function pointers loaded at initialization to avoid linking statically with X11.
	//     void*                       X11Module;
	//     PFN_XInternAtom             XInternAtom;
	//     PFN_XChangeProperty         XChangeProperty;
	//     PFN_XChangeWindowAttributes XChangeWindowAttributes;
	//     PFN_XFlush                  XFlush;
	// #endif
}

@(private = "package")
ContextMap: map[glfw.WindowHandle]^imgui.Context

// Get data for current context
@(private = "package")
GetBackendDataNoWindow :: proc() -> ^Data {
	return(
		imgui.GetCurrentContext() != nil ? transmute(^Data)imgui.GetIO().BackendPlatformUserData : nil \
	)
}

// Get data for a given GLFW window, regardless of current context (since GLFW events are sent together)
@(private = "package")
GetBackendDataWindow :: proc(window: glfw.WindowHandle) -> ^Data {
	return transmute(^Data)imgui.GetIOImGuiContextPtr(ContextMap[window]).BackendPlatformUserData
}

@(private = "package")
GetBackendData :: proc {
	GetBackendDataNoWindow,
	GetBackendDataWindow,
}

@(private = "package")
KeyToImGuiKey :: proc(keycode, scancode: i32) -> imgui.Key {
	switch keycode {
	case glfw.KEY_TAB:
		return .Tab
	case glfw.KEY_LEFT:
		return .LeftArrow
	case glfw.KEY_RIGHT:
		return .RightArrow
	case glfw.KEY_UP:
		return .UpArrow
	case glfw.KEY_DOWN:
		return .DownArrow
	case glfw.KEY_PAGE_UP:
		return .PageUp
	case glfw.KEY_PAGE_DOWN:
		return .PageDown
	case glfw.KEY_HOME:
		return .Home
	case glfw.KEY_END:
		return .End
	case glfw.KEY_INSERT:
		return .Insert
	case glfw.KEY_DELETE:
		return .Delete
	case glfw.KEY_BACKSPACE:
		return .Backspace
	case glfw.KEY_SPACE:
		return .Space
	case glfw.KEY_ENTER:
		return .Enter
	case glfw.KEY_ESCAPE:
		return .Escape
	case glfw.KEY_APOSTROPHE:
		return .Apostrophe
	case glfw.KEY_COMMA:
		return .Comma
	case glfw.KEY_MINUS:
		return .Minus
	case glfw.KEY_PERIOD:
		return .Period
	case glfw.KEY_SLASH:
		return .Slash
	case glfw.KEY_SEMICOLON:
		return .Semicolon
	case glfw.KEY_EQUAL:
		return .Equal
	case glfw.KEY_LEFT_BRACKET:
		return .LeftBracket
	case glfw.KEY_BACKSLASH:
		return .Backslash
	case glfw.KEY_WORLD_1:
		return .Oem102
	case glfw.KEY_WORLD_2:
		return .Oem102
	case glfw.KEY_RIGHT_BRACKET:
		return .RightBracket
	case glfw.KEY_GRAVE_ACCENT:
		return .GraveAccent
	case glfw.KEY_CAPS_LOCK:
		return .CapsLock
	case glfw.KEY_SCROLL_LOCK:
		return .ScrollLock
	case glfw.KEY_NUM_LOCK:
		return .NumLock
	case glfw.KEY_PRINT_SCREEN:
		return .PrintScreen
	case glfw.KEY_PAUSE:
		return .Pause
	case glfw.KEY_KP_0:
		return .Keypad0
	case glfw.KEY_KP_1:
		return .Keypad1
	case glfw.KEY_KP_2:
		return .Keypad2
	case glfw.KEY_KP_3:
		return .Keypad3
	case glfw.KEY_KP_4:
		return .Keypad4
	case glfw.KEY_KP_5:
		return .Keypad5
	case glfw.KEY_KP_6:
		return .Keypad6
	case glfw.KEY_KP_7:
		return .Keypad7
	case glfw.KEY_KP_8:
		return .Keypad8
	case glfw.KEY_KP_9:
		return .Keypad9
	case glfw.KEY_KP_DECIMAL:
		return .KeypadDecimal
	case glfw.KEY_KP_DIVIDE:
		return .KeypadDivide
	case glfw.KEY_KP_MULTIPLY:
		return .KeypadMultiply
	case glfw.KEY_KP_SUBTRACT:
		return .KeypadSubtract
	case glfw.KEY_KP_ADD:
		return .KeypadAdd
	case glfw.KEY_KP_ENTER:
		return .KeypadEnter
	case glfw.KEY_KP_EQUAL:
		return .KeypadEqual
	case glfw.KEY_LEFT_SHIFT:
		return .LeftShift
	case glfw.KEY_LEFT_CONTROL:
		return .LeftCtrl
	case glfw.KEY_LEFT_ALT:
		return .LeftAlt
	case glfw.KEY_LEFT_SUPER:
		return .LeftSuper
	case glfw.KEY_RIGHT_SHIFT:
		return .RightShift
	case glfw.KEY_RIGHT_CONTROL:
		return .RightCtrl
	case glfw.KEY_RIGHT_ALT:
		return .RightAlt
	case glfw.KEY_RIGHT_SUPER:
		return .RightSuper
	case glfw.KEY_MENU:
		return .Menu
	case glfw.KEY_0:
		return ._0
	case glfw.KEY_1:
		return ._1
	case glfw.KEY_2:
		return ._2
	case glfw.KEY_3:
		return ._3
	case glfw.KEY_4:
		return ._4
	case glfw.KEY_5:
		return ._5
	case glfw.KEY_6:
		return ._6
	case glfw.KEY_7:
		return ._7
	case glfw.KEY_8:
		return ._8
	case glfw.KEY_9:
		return ._9
	case glfw.KEY_A:
		return .A
	case glfw.KEY_B:
		return .B
	case glfw.KEY_C:
		return .C
	case glfw.KEY_D:
		return .D
	case glfw.KEY_E:
		return .E
	case glfw.KEY_F:
		return .F
	case glfw.KEY_G:
		return .G
	case glfw.KEY_H:
		return .H
	case glfw.KEY_I:
		return .I
	case glfw.KEY_J:
		return .J
	case glfw.KEY_K:
		return .K
	case glfw.KEY_L:
		return .L
	case glfw.KEY_M:
		return .M
	case glfw.KEY_N:
		return .N
	case glfw.KEY_O:
		return .O
	case glfw.KEY_P:
		return .P
	case glfw.KEY_Q:
		return .Q
	case glfw.KEY_R:
		return .R
	case glfw.KEY_S:
		return .S
	case glfw.KEY_T:
		return .T
	case glfw.KEY_U:
		return .U
	case glfw.KEY_V:
		return .V
	case glfw.KEY_W:
		return .W
	case glfw.KEY_X:
		return .X
	case glfw.KEY_Y:
		return .Y
	case glfw.KEY_Z:
		return .Z
	case glfw.KEY_F1:
		return .F1
	case glfw.KEY_F2:
		return .F2
	case glfw.KEY_F3:
		return .F3
	case glfw.KEY_F4:
		return .F4
	case glfw.KEY_F5:
		return .F5
	case glfw.KEY_F6:
		return .F6
	case glfw.KEY_F7:
		return .F7
	case glfw.KEY_F8:
		return .F8
	case glfw.KEY_F9:
		return .F9
	case glfw.KEY_F10:
		return .F10
	case glfw.KEY_F11:
		return .F11
	case glfw.KEY_F12:
		return .F12
	case glfw.KEY_F13:
		return .F13
	case glfw.KEY_F14:
		return .F14
	case glfw.KEY_F15:
		return .F15
	case glfw.KEY_F16:
		return .F16
	case glfw.KEY_F17:
		return .F17
	case glfw.KEY_F18:
		return .F18
	case glfw.KEY_F19:
		return .F19
	case glfw.KEY_F20:
		return .F20
	case glfw.KEY_F21:
		return .F21
	case glfw.KEY_F22:
		return .F22
	case glfw.KEY_F23:
		return .F23
	case glfw.KEY_F24:
		return .F24
	case:
		return .None
	}
}

@(private = "package")
UpdateKeyModifiers :: proc(io: ^imgui.IO, window: glfw.WindowHandle) {
	imgui.IO_AddKeyEvent(
		io,
		.ImGuiMod_Ctrl,
		(glfw.GetKey(window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_CONTROL) == glfw.PRESS),
	)
	imgui.IO_AddKeyEvent(
		io,
		.ImGuiMod_Shift,
		(glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS),
	)
	imgui.IO_AddKeyEvent(
		io,
		.ImGuiMod_Alt,
		(glfw.GetKey(window, glfw.KEY_LEFT_ALT) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_ALT) == glfw.PRESS),
	)
	imgui.IO_AddKeyEvent(
		io,
		.ImGuiMod_Super,
		(glfw.GetKey(window, glfw.KEY_LEFT_SUPER) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_SUPER) == glfw.PRESS),
	)
}

// FIXME: should this be baked into ImGui_ImplGlfw_KeyToImGuiKey()? then what about the values passed to io.SetKeyEventNativeData()?
@(private = "package")
TranslateUntranslatedKey :: proc(key, scancode: i32) -> i32 {
	// GLFW 3.1+ attempts to "untranslate" keys, which goes the opposite of what every other framework does, making using lettered shortcuts difficult.
	// (It had reasons to do so: namely GLFW is/was more likely to be used for WASD-type game controls rather than lettered shortcuts, but IHMO the 3.1 change could have been done differently)
	// See https://github.com/glfw/glfw/issues/1502 for details.
	// Adding a workaround to undo this (so our keys are translated->untranslated->translated, likely a lossy process).
	// This won't cover edge cases but this is at least going to cover common cases.
	key := key
	if key >= glfw.KEY_KP_0 && key <= glfw.KEY_KP_EQUAL {
		return key
	}

	prev_error_callback := glfw.SetErrorCallback(nil)
	key_name := glfw.GetKeyName(key, scancode)
	glfw.SetErrorCallback(prev_error_callback)
	_, _ = glfw.GetError()
	if len(key_name) == 1 && key_name[0] != 0 {
		char_names :: [?]u8{'`', '-', '=', '[', ']', '\\', ',', ';', '\'', '.', '/'}
		char_keys :: [?]int {
			glfw.KEY_GRAVE_ACCENT,
			glfw.KEY_MINUS,
			glfw.KEY_EQUAL,
			glfw.KEY_LEFT_BRACKET,
			glfw.KEY_RIGHT_BRACKET,
			glfw.KEY_BACKSLASH,
			glfw.KEY_COMMA,
			glfw.KEY_SEMICOLON,
			glfw.KEY_APOSTROPHE,
			glfw.KEY_PERIOD,
			glfw.KEY_SLASH,
		}
		#assert(len(char_names) == len(char_keys))

		if key_name[0] >= '0' && key_name[0] <= '9' {
			key = glfw.KEY_0 + i32(key_name[0] - '0')
		} else if key_name[0] >= 'A' && key_name[0] <= 'Z' {
			key = glfw.KEY_A + i32(key_name[0] - 'A')
		} else if key_name[0] >= 'a' && key_name[0] <= 'z' {
			key = glfw.KEY_A + i32(key_name[0] - 'a')
		} else {
			for char in char_names {
				if char == key_name[0] {
					key = i32(char)
					break
				}
			}
		}
	}
	return key
}

@(private = "package")
UpdateMouseData :: proc() {
	bd := GetBackendData()
	io := imgui.GetIO()
	platform_io := imgui.GetPlatformIO()

	mouse_viewport_id: imgui.ID = 0
	mouse_pos_prev := io.MousePos
	for n: i32 = 0; n < platform_io.Viewports.Size; n += 1 {
		viewport := platform_io.Viewports.Data[n]
		window := transmute(glfw.WindowHandle)(viewport.PlatformHandle)

		is_window_focused := glfw.GetWindowAttrib(window, glfw.FOCUSED) != 0
		if is_window_focused {
			// (Optional) Set OS mouse position from Dear ImGui if requested (rarely used, only when io.ConfigNavMoveSetMousePos is enabled by user)
			// When multi-viewports are enabled, all Dear ImGui positions are same as OS positions.
			if io.WantSetMousePos {
				glfw.SetCursorPos(
					window,
					f64(mouse_pos_prev.x - viewport.Pos.x),
					f64(mouse_pos_prev.y - viewport.Pos.y),
				)
			}

			// (Optional) Fallback to provide mouse position when focused (ImGui_ImplGlfw_CursorPosCallback already provides this when hovered or captured)
			if bd.MouseWindow == nil {
				mouse_x, mouse_y := glfw.GetCursorPos(window)
				if .ViewportsEnable in io.ConfigFlags {
					// Single viewport mode: mouse position in client window coordinates (io.MousePos is (0,0) when the mouse is on the upper-left corner of the app window)
					// Multi-viewport mode: mouse position in OS absolute coordinates (io.MousePos is (0,0) when the mouse is on the upper-left of the primary monitor)
					window_x, window_y := glfw.GetWindowPos(window)
					mouse_x += f64(window_x)
					mouse_y += f64(window_y)
				}
				bd.LastValidMousePos = {f32(mouse_x), f32(mouse_y)}
				imgui.IO_AddMousePosEvent(io, f32(mouse_x), f32(mouse_y))
			}
		}

		// (Optional) When using multiple viewports: call io.AddMouseViewportEvent() with the viewport the OS mouse cursor is hovering.
		// If ImGuiBackendFlags_HasMouseHoveredViewport is not set by the backend, Dear imGui will ignore this field and infer the information using its flawed heuristic.
		// - [X] GLFW >= 3.3 backend ON WINDOWS ONLY does correctly ignore viewports with the _NoInputs flag (since we implement hit via our WndProc hook)
		//       On other platforms we rely on the library fallbacking to its own search when reporting a viewport with _NoInputs flag.
		// - [!] GLFW <= 3.2 backend CANNOT correctly ignore viewports with the _NoInputs flag, and CANNOT reported Hovered Viewport because of mouse capture.
		//       Some backend are not able to handle that correctly. If a backend report an hovered viewport that has the _NoInputs flag (e.g. when dragging a window
		//       for docking, the viewport has the _NoInputs flag in order to allow us to find the viewport under), then Dear ImGui is forced to ignore the value reported
		//       by the backend, and use its flawed heuristic to guess the viewport behind.
		// - [X] GLFW backend correctly reports this regardless of another viewport behind focused and dragged from (we need this to find a useful drag and drop target).
		// FIXME: This is currently only correct on Win32. See what we do below with the WM_NCHITTEST, missing an equivalent for other systems.
		// See https://github.com/glfw/glfw/issues/1236 if you want to help in making this a GLFW feature.
		window_no_input := .NoInputs in viewport.Flags
		glfw.SetWindowAttrib(window, glfw.MOUSE_PASSTHROUGH, i32(window_no_input))
		if glfw.GetWindowAttrib(window, glfw.HOVERED) == 1 {
			mouse_viewport_id = viewport.ID_
		}
		// We cannot use bd->MouseWindow maintained from CursorEnter/Leave callbacks, because it is locked to the window capturing mouse.
	}

	if .HasMouseHoveredViewport in io.BackendFlags {
		imgui.IO_AddMouseViewportEvent(io, mouse_viewport_id)
	}
}

@(private = "package")
UpdateMouseCursor :: proc() {
	io := imgui.GetIO()
	bd := GetBackendData()
	if .NoMouseCursorChange in io.ConfigFlags ||
	   glfw.GetInputMode(bd.Window, glfw.CURSOR) == glfw.CURSOR_DISABLED {
		return
	}

	imgui_cursor := imgui.GetMouseCursor()
	platform_io := imgui.GetPlatformIO()
	for n: i32 = 0; n < platform_io.Viewports.Size; n += 1 {
		window := transmute(glfw.WindowHandle)(platform_io.Viewports.Data[n].PlatformHandle)
		if imgui_cursor == .None || io.MouseDrawCursor {
			if bd.LastMouseCursor != nil {
				// Hide OS mouse cursor if imgui is drawing it or if it wants no cursor
				glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_HIDDEN)
				bd.LastMouseCursor = nil
			}
		} else {
			// Show OS mouse cursor
			// FIXME-PLATFORM: Unfocused windows seems to fail changing the mouse cursor with GLFW 3.2, but 3.3 works here.
			cursor :=
				bd.MouseCursors[imgui_cursor] != nil ? bd.MouseCursors[imgui_cursor] : bd.MouseCursors[imgui.MouseCursor.Arrow]
			if bd.LastMouseCursor != cursor {
				glfw.SetCursor(window, cursor)
				bd.LastMouseCursor = cursor
			}
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		}
	}
}

// Update gamepad inputs
@(private = "package")
Saturate :: #force_inline proc(v: f32) -> f32 {
	return math.clamp(v, 0, 1)
}

@(private = "package")
UpdateGamepads :: proc() {
	io := imgui.GetIO()
	// FIXME: Technically feeding gamepad shouldn't depend on this now that they are regular inputs, but see #8075
	if .NavEnableGamepad not_in io.ConfigFlags {
		return
	}

	io.BackendFlags -= {.HasGamepad}
	gamepad: glfw.GamepadState
	if !glfw.GetGamepadState(glfw.JOYSTICK_1, &gamepad) {
		return
	}

	MAP_BUTTON :: #force_inline proc(
		io: ^imgui.IO,
		gamepad: ^glfw.GamepadState,
		keyNo: imgui.Key,
		buttonNo, _: i32,
	) {
		imgui.IO_AddKeyEvent(io, keyNo, gamepad.buttons[buttonNo] != 0)
	}

	MAP_ANALOG :: #force_inline proc(
		io: ^imgui.IO,
		gamepad: ^glfw.GamepadState,
		keyNo: imgui.Key,
		axisNo, _: i32,
		v0, v1: f32,
	) {
		v := gamepad.axes[axisNo]
		v = (v - v0) / (v1 - v0)
		imgui.IO_AddKeyAnalogEvent(io, keyNo, v > 0.10, Saturate(v))
	}

	io.BackendFlags += {.HasGamepad}
	MAP_BUTTON(io, &gamepad, .GamepadStart, glfw.GAMEPAD_BUTTON_START, 7)
	MAP_BUTTON(io, &gamepad, .GamepadBack, glfw.GAMEPAD_BUTTON_BACK, 6)
	MAP_BUTTON(io, &gamepad, .GamepadFaceLeft, glfw.GAMEPAD_BUTTON_X, 2) // Xbox X, PS Square
	MAP_BUTTON(io, &gamepad, .GamepadFaceRight, glfw.GAMEPAD_BUTTON_B, 1) // Xbox B, PS Circle
	MAP_BUTTON(io, &gamepad, .GamepadFaceUp, glfw.GAMEPAD_BUTTON_Y, 3) // Xbox Y, PS Triangle
	MAP_BUTTON(io, &gamepad, .GamepadFaceDown, glfw.GAMEPAD_BUTTON_A, 0) // Xbox A, PS Cross
	MAP_BUTTON(io, &gamepad, .GamepadDpadLeft, glfw.GAMEPAD_BUTTON_DPAD_LEFT, 13)
	MAP_BUTTON(io, &gamepad, .GamepadDpadRight, glfw.GAMEPAD_BUTTON_DPAD_RIGHT, 11)
	MAP_BUTTON(io, &gamepad, .GamepadDpadUp, glfw.GAMEPAD_BUTTON_DPAD_UP, 10)
	MAP_BUTTON(io, &gamepad, .GamepadDpadDown, glfw.GAMEPAD_BUTTON_DPAD_DOWN, 12)
	MAP_BUTTON(io, &gamepad, .GamepadL1, glfw.GAMEPAD_BUTTON_LEFT_BUMPER, 4)
	MAP_BUTTON(io, &gamepad, .GamepadR1, glfw.GAMEPAD_BUTTON_RIGHT_BUMPER, 5)
	MAP_ANALOG(io, &gamepad, .GamepadL2, glfw.GAMEPAD_AXIS_LEFT_TRIGGER, 4, -0.75, +1.0)
	MAP_ANALOG(io, &gamepad, .GamepadR2, glfw.GAMEPAD_AXIS_RIGHT_TRIGGER, 5, -0.75, +1.0)
	MAP_BUTTON(io, &gamepad, .GamepadL3, glfw.GAMEPAD_BUTTON_LEFT_THUMB, 8)
	MAP_BUTTON(io, &gamepad, .GamepadR3, glfw.GAMEPAD_BUTTON_RIGHT_THUMB, 9)
	MAP_ANALOG(io, &gamepad, .GamepadLStickLeft, glfw.GAMEPAD_AXIS_LEFT_X, 0, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .GamepadLStickRight, glfw.GAMEPAD_AXIS_LEFT_X, 0, +0.25, +1.0)
	MAP_ANALOG(io, &gamepad, .GamepadLStickUp, glfw.GAMEPAD_AXIS_LEFT_Y, 1, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .GamepadLStickDown, glfw.GAMEPAD_AXIS_LEFT_Y, 1, +0.25, +1.0)
	MAP_ANALOG(io, &gamepad, .GamepadRStickLeft, glfw.GAMEPAD_AXIS_RIGHT_X, 2, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .GamepadRStickRight, glfw.GAMEPAD_AXIS_RIGHT_X, 2, +0.25, +1.0)
	MAP_ANALOG(io, &gamepad, .GamepadRStickUp, glfw.GAMEPAD_AXIS_RIGHT_Y, 3, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .GamepadRStickDown, glfw.GAMEPAD_AXIS_RIGHT_Y, 3, +0.25, +1.0)
}

@(private = "package")
UpdateMonitors :: proc() {
	platform_io := imgui.GetPlatformIO()
	glfw_monitors := glfw.GetMonitors()

	updated_monitors := false
	for n := 0; n < len(glfw_monitors); n += 1 {
		monitor: imgui.PlatformMonitor
		x, y := glfw.GetMonitorPos(glfw_monitors[n])
		vid_mode := glfw.GetVideoMode(glfw_monitors[n])
		if vid_mode != nil {
			continue // Failed to get Video mode (e.g. Emscripten does not support this function)
		}
		if vid_mode.width <= 0 || vid_mode.height <= 0 {
			continue // Failed to query suitable monitor info (#9195)
		}
		monitor.WorkPos = imgui.Vec2{f32(x), f32(y)}
		monitor.MainPos = monitor.WorkPos
		monitor.WorkSize = imgui.Vec2{f32(vid_mode.width), f32(vid_mode.height)}
		monitor.MainSize = monitor.WorkSize
		w, h: i32
		x, y, w, h = glfw.GetMonitorWorkarea(glfw_monitors[n])
		if w > 0 && h > 0 { 	// Workaround a small GLFW issue reporting zero on monitor changes: https://github.com/glfw/glfw/pull/1761
			monitor.WorkPos = imgui.Vec2{f32(x), f32(y)}
			monitor.WorkSize = imgui.Vec2{f32(w), f32(h)}
		}
		scale := GetContentScaleForMonitor(glfw_monitors[n])
		if scale == 0 {
			continue // Some accessibility applications are declaring virtual monitors with a DPI of 0 (#7902)
		}
		monitor.DpiScale = scale
		monitor.PlatformHandle = glfw_monitors[n] // [...] GLFW doc states: "guaranteed to be valid only until the monitor configuration changes"

		// Preserve existing monitor list until a valid one is added.
		// Happens on macOS sleeping (#5683) and seemingly occasionally on Windows (#9195)
		if !updated_monitors {
			platform_io.Monitors.Size = 0
		}
		updated_monitors = true

		imgui.Vector_Push_Back(&platform_io.Monitors, monitor)
	}
}

// - On Windows the process needs to be marked DPI-aware!! SDL2 doesn't do it by default. You can call ::SetProcessDPIAware() or call ImGui_ImplWin32_EnableDpiAwareness() from Win32 backend.
// - Apple platforms use FramebufferScale so we always return 1.0f.
// - Some accessibility applications are declaring virtual monitors with a DPI of 0.0f, see #7902. We preserve this value for caller to handle.
@(private = "package")
GetContentScaleForWindow :: proc(window: glfw.WindowHandle) -> f32 {
	when X11 {
		if bd := GetBackendData(window); bd != nil && bd.IsWayland {
			return 1
		}
	} else when ODIN_OS != .Darwin {
		x_scale, _ := glfw.GetWindowContentScale(window)
		return x_scale
	}
	return 1
}

@(private = "package")
GetContentScaleForMonitor :: proc(monitor: glfw.MonitorHandle) -> f32 {
	when X11 {
		if glfw.GetPlatform() == glfw.PLATFORM_WAYLAND { 	// We can't access our bd->IsWayland cache for a monitor.
			return 1
		}
	} else when ODIN_OS != .Darwin {
		x_scale, _ := glfw.GetMonitorContentScale(monitor)
		return x_scale
	}
	return 1
}

@(private = "package")
GetWindowSizeAndFramebufferScale :: proc(
	window: glfw.WindowHandle,
	out_size, out_framebuffer_scale: ^imgui.Vec2,
) {
	w, h := glfw.GetWindowSize(window)
	display_w, display_h := glfw.GetFramebufferSize(window)
	fb_scale_x: f32 = (w > 0) ? f32(display_w) / f32(w) : 1
	fb_scale_y: f32 = (h > 0) ? f32(display_h) / f32(h) : 1
	when X11 {
		bd := GetBackendData(window)
		if !bd.IsWayland {
			fb_scale_x = 1
			fb_scale_y = fb_scale_y
		}
	}
	if out_size != nil {
		out_size^ = imgui.Vec2{f32(w), f32(h)}
	}
	if out_framebuffer_scale != nil {
		out_framebuffer_scale^ = imgui.Vec2{fb_scale_x, fb_scale_y}
	}
}

@(private = "package")
ViewportDataBase :: struct {
	Window:                     glfw.WindowHandle,
	WindowOwned:                bool,
	IgnoreWindowPosEventFrame:  i32,
	IgnoreWindowSizeEventFrame: i32,
}

@(private = "package")
WindowCloseCallback :: proc "c" (window: glfw.WindowHandle) {
	if viewport := imgui.FindViewportByPlatformHandle(window); viewport != nil {
		viewport.PlatformRequestClose = true
	}
}

// GLFW may dispatch window pos/size events after calling glfwSetWindowPos()/glfwSetWindowSize().
// However: depending on the platform the callback may be invoked at different time:
// - on Windows it appears to be called within the glfwSetWindowPos()/glfwSetWindowSize() call
// - on Linux it is queued and invoked during glfwPollEvents()
// Because the event doesn't always fire on glfwSetWindowXXX() we use a frame counter tag to only
// ignore recent glfwSetWindowXXX() calls.
@(private = "package")
WindowPosCallback :: proc "c" (window: glfw.WindowHandle, _, _: i32) {
	if viewport := imgui.FindViewportByPlatformHandle(window); viewport != nil {
		if vd := transmute(^ViewportData)viewport.PlatformUserData; vd != nil {
			//data->IgnoreWindowPosEventFrame = -1;
			if imgui.GetFrameCount() <= vd.IgnoreWindowPosEventFrame + 1 {
				return
			}
		}
		viewport.PlatformRequestMove = true
	}
}

@(private = "package")
WindowSizeCallback :: proc "c" (window: glfw.WindowHandle, _, _: i32) {
	if viewport := imgui.FindViewportByPlatformHandle(window); viewport != nil {
		if vd := transmute(^ViewportData)viewport.PlatformUserData; vd != nil {
			//data->IgnoreWindowSizeEventFrame = -1;
			if imgui.GetFrameCount() <= vd.IgnoreWindowSizeEventFrame + 1 {
				return
			}
		}
		viewport.PlatformRequestResize = true
	}
}

@(private = "package")
CreateWindow :: proc "cdecl" (viewport: ^imgui.Viewport) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := new(ViewportData)
	viewport.PlatformUserData = vd

	// Workaround for Linux: ignore mouse up events corresponding to losing focus of the previously focused window (#7733, #3158, #7922)
	when ODIN_OS == .Linux {
		bd->MouseIgnoreButtonUpWaitForFocusLoss = true
	}

	// GLFW 3.2 unfortunately always set focus on glfwCreateWindow() if GLFW_VISIBLE is set, regardless of GLFW_FOCUSED
	// With GLFW 3.3, the hint GLFW_FOCUS_ON_SHOW fixes this problem
	glfw.WindowHint(glfw.VISIBLE, false)
	glfw.WindowHint(glfw.FOCUSED, false)
	glfw.WindowHint(glfw.FOCUS_ON_SHOW, false)
	glfw.WindowHint(glfw.DECORATED, .NoDecoration in viewport.Flags)
	glfw.WindowHint(glfw.FLOATING, .TopMost in viewport.Flags)
	vd.Window = glfw.CreateWindow(
		i32(viewport.Size.x),
		i32(viewport.Size.y),
		"No Title Yet",
		nil,
		nil,
	)
	vd.WindowOwned = true
	ContextMap[vd.Window] = bd.Context
	viewport.PlatformHandle = vd.Window

	when X11 {
		SetWindowFloating(bd, vd.Window)
	}

	when ODIN_OS == .Windows {
		viewport.PlatformHandleRaw = glfw.GetWin32Window(vd.Window)
		windows.SetPropW(
			transmute(windows.HWND)viewport.PlatformHandleRaw,
			"IMGUI_BACKEND_DATA",
			transmute(windows.HANDLE)bd,
		)
	} else when ODIN_OS == .Darwin {
		viewport.PlatformHandleRaw = glfw.GetCocoaWindow(vd.Window)
	}
	glfw.SetWindowPos(vd.Window, i32(viewport.Pos.x), i32(viewport.Pos.y))

	// Install GLFW callbacks for secondary viewports
	glfw.SetWindowFocusCallback(vd.Window, WindowFocusCallback)
	glfw.SetCursorEnterCallback(vd.Window, CursorEnterCallback)
	glfw.SetCursorPosCallback(vd.Window, CursorPosCallback)
	glfw.SetMouseButtonCallback(vd.Window, MouseButtonCallback)
	glfw.SetScrollCallback(vd.Window, ScrollCallback)
	glfw.SetKeyCallback(vd.Window, KeyCallback)
	glfw.SetCharCallback(vd.Window, CharCallback)
	glfw.SetWindowCloseCallback(vd.Window, WindowCloseCallback)
	glfw.SetWindowPosCallback(vd.Window, WindowPosCallback)
	glfw.SetWindowSizeCallback(vd.Window, WindowSizeCallback)
}

@(private = "package")
DestroyWindow :: proc "cdecl" (viewport: ^imgui.Viewport) {
	context = runtime.default_context()
	bd := GetBackendData()
	if vd := transmute(^ViewportData)viewport.PlatformUserData; vd != nil {
		if vd.WindowOwned {
			when ODIN_OS == .Windows {
				hwnd := transmute(windows.HWND)viewport.PlatformHandleRaw
				windows.RemovePropW(hwnd, "IMGUI_VIEWPORT")
			}

			// Release any keys that were pressed in the window being destroyed and are still held down,
			// because we will not receive any release events after window is destroyed.
			for i: i32 = 0; i < len(bd.KeyOwnerWindows); i += 1 {
				if bd.KeyOwnerWindows[i] == vd.Window {
					// Later params are only used for main viewport, on which this function is never called.
					KeyCallback(vd.Window, i, 0, glfw.RELEASE, 0)
				}
			}

			free(ContextMap[vd.Window])
			ContextMap[vd.Window] = nil
			glfw.DestroyWindow(vd.Window)
		}
		vd.Window = nil
		free(vd)
	}
	viewport.PlatformUserData = nil
	viewport.PlatformHandle = nil
}

@(private = "package")
ShowWindow :: proc "cdecl" (viewport: ^imgui.Viewport) {
	vd := transmute(^ViewportData)viewport.PlatformUserData

	when ODIN_OS == .Windows {
		// GLFW hack: Hide icon from task bar
		hwnd := transmute(windows.HWND)viewport.PlatformHandleRaw
		if .NoTaskBarIcon in viewport.Flags {
			ex_style := windows.GetWindowLongW(hwnd, windows.GWL_EXSTYLE)
			ex_style &= transmute(i32)~windows.WS_EX_APPWINDOW
			ex_style |= transmute(i32)windows.WS_EX_TOOLWINDOW
			windows.SetWindowLongW(hwnd, windows.GWL_EXSTYLE, ex_style)
		}

		// GLFW hack: install WndProc for mouse source event and WM_NCHITTEST message handler.
		windows.SetPropW(hwnd, "IMGUI_VIEWPORT", transmute(windows.HANDLE)viewport)
		vd.PrevWndProc = transmute(windows.WNDPROC)windows.GetWindowLongPtrW(
			hwnd,
			windows.GWLP_WNDPROC,
		)
		windows.SetWindowLongPtrW(hwnd, windows.GWLP_WNDPROC, transmute(windows.LONG_PTR)WndProc)
	}

	glfw.ShowWindow(vd.Window)
}

@(private = "package")
GetWindowPos :: proc "cdecl" (viewport: ^imgui.Viewport) -> imgui.Vec2 {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	x, y := glfw.GetWindowPos(vd.Window)
	return {f32(x), f32(y)}
}

@(private = "package")
SetWindowPos :: proc "cdecl" (viewport: ^imgui.Viewport, pos: imgui.Vec2) {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	vd.IgnoreWindowPosEventFrame = imgui.GetFrameCount()
	glfw.SetWindowPos(vd.Window, i32(pos.x), i32(pos.y))
}

@(private = "package")
GetWindowSize :: proc "cdecl" (viewport: ^imgui.Viewport) -> imgui.Vec2 {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	w, h := glfw.GetWindowSize(vd.Window)
	return {f32(w), f32(h)}
}

@(private = "package")
SetWindowSize :: proc "cdecl" (viewport: ^imgui.Viewport, size: imgui.Vec2) {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	vd.IgnoreWindowSizeEventFrame = imgui.GetFrameCount()
	glfw.SetWindowSize(vd.Window, i32(size.x), i32(size.y))
}

@(private = "package")
GetWindowFramebufferScale :: proc "cdecl" (viewport: ^imgui.Viewport) -> imgui.Vec2 {
	context = runtime.default_context()
	vd := transmute(^ViewportData)viewport.PlatformUserData
	framebuffer_scale: imgui.Vec2 = ---
	GetWindowSizeAndFramebufferScale(vd.Window, nil, &framebuffer_scale)
	return framebuffer_scale
}

@(private = "package")
SetWindowTitle :: proc "cdecl" (viewport: ^imgui.Viewport, title: cstring) {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	glfw.SetWindowTitle(vd.Window, title)
}

@(private = "package")
SetWindowFocus :: proc "cdecl" (viewport: ^imgui.Viewport) {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	glfw.FocusWindow(vd.Window)
}

@(private = "package")
GetWindowFocus :: proc "cdecl" (viewport: ^imgui.Viewport) -> bool {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	return glfw.GetWindowAttrib(vd.Window, glfw.FOCUSED) != 0
}

@(private = "package")
GetWindowMinimized :: proc "cdecl" (viewport: ^imgui.Viewport) -> bool {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	return glfw.GetWindowAttrib(vd.Window, glfw.ICONIFIED) != 0
}

@(private = "package")
SetWindowAlpha :: proc "cdecl" (viewport: ^imgui.Viewport, alpha: f32) {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	glfw.SetWindowOpacity(vd.Window, alpha)
}

@(private = "package")
RenderWindow :: proc "cdecl" (viewport: ^imgui.Viewport, _: rawptr) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := transmute(^ViewportData)viewport.PlatformUserData
}

@(private = "package")
SwapBuffers :: proc "cdecl" (viewport: ^imgui.Viewport, _: rawptr) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := transmute(^ViewportData)viewport.PlatformUserData
}

//--------------------------------------------------------------------------------------------------------
// Vulkan support (the Vulkan renderer needs to call a platform-side support function to create the surface)
//--------------------------------------------------------------------------------------------------------

CreateVkSurface :: proc "cdecl" (
	viewport: ^imgui.Viewport,
	vk_instance: u64,
	vk_allocator: rawptr,
	out_vk_surface: ^u64,
) -> i32 {
	vd := transmute(^ViewportData)viewport.PlatformUserData
	err := glfw.CreateWindowSurface(
		transmute(vk.Instance)vk_instance,
		vd.Window,
		transmute(^vk.AllocationCallbacks)vk_allocator,
		transmute(^vk.SurfaceKHR)(out_vk_surface),
	)
	return i32(err)
}

InitMultiViewportSupport :: proc() {
	// Register platform interface (will be coupled with a renderer interface)
	bd := GetBackendData()
	platform_io := imgui.GetPlatformIO()
	platform_io.Platform_CreateWindow = CreateWindow
	platform_io.Platform_DestroyWindow = DestroyWindow
	platform_io.Platform_ShowWindow = ShowWindow
	platform_io.Platform_SetWindowPos = SetWindowPos
	platform_io.Platform_GetWindowPos = GetWindowPos
	platform_io.Platform_SetWindowSize = SetWindowSize
	platform_io.Platform_GetWindowSize = GetWindowSize
	platform_io.Platform_GetWindowFramebufferScale = GetWindowFramebufferScale
	platform_io.Platform_SetWindowFocus = SetWindowFocus
	platform_io.Platform_GetWindowFocus = GetWindowFocus
	platform_io.Platform_GetWindowMinimized = GetWindowMinimized
	platform_io.Platform_SetWindowTitle = SetWindowTitle
	platform_io.Platform_RenderWindow = RenderWindow
	platform_io.Platform_SwapBuffers = SwapBuffers
	platform_io.Platform_SetWindowAlpha = SetWindowAlpha
	platform_io.Platform_CreateVkSurface = CreateVkSurface

	// Register main window handle (which is owned by the main application, not by us)
	// This is mostly for simplicity and consistency, so that our code (e.g. mouse handling etc.) can use same logic for main and secondary viewports.
	main_viewport := imgui.GetMainViewport()
	vd := new(ViewportData)
	vd.Window = bd.Window
	vd.WindowOwned = false
	main_viewport.PlatformUserData = vd
	main_viewport.PlatformHandle = bd.Window
}

ShutdownMultiViewportSupport :: proc() {
	imgui.DestroyPlatformWindows()
}

