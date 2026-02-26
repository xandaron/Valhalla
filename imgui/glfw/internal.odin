#+private
package ImGui_ImplGlfw

import imgui ".."
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:sys/windows"
import "vendor:glfw"
import glfwBindings "vendor:glfw/bindings"
import vk "vendor:vulkan"

internal_allocator: mem.Allocator
ContextMap: map[glfw.WindowHandle]^imgui.GuiContext

DataBase :: struct {
	Context:                             ^imgui.GuiContext,
	Window:                              glfw.WindowHandle,
	ClientApi:                           GlfwClientApi,
	Time:                                f64,
	MouseWindow:                         glfw.WindowHandle,
	MouseCursors:                        [imgui.GuiMouseCursor.COUNT]glfw.CursorHandle,
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
	PrevUserCallbackMonitor:             glfw.MonitorProc,
}

Init :: proc(
	window: glfw.WindowHandle,
	install_callbacks: bool,
	client_api: GlfwClientApi,
	allocator: mem.Allocator,
) -> bool {
	internal_allocator = allocator

	io := imgui.Gui_GetIO()
	imgui.CHECKVERSION()
	assert(io.BackendPlatformUserData == nil, "Already initialized a platform backend!")

	// Setup backend capabilities flags
	bd := new(Data, internal_allocator)
	fmt.bprintf(bd.BackendPlatformName[:], "imgui_impl_glfw (%d)", GLFW_VERSION_COMBINED)
	io.BackendPlatformUserData = bd
	io.BackendPlatformName = cstring(&bd.BackendPlatformName[0])
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

	bd.Context = imgui.Gui_GetCurrentContext()
	bd.Window = window
	bd.Time = 0.0
	ContextMap = make(map[glfw.WindowHandle]^imgui.GuiContext, allocator = internal_allocator)
	ContextMap[window] = bd.Context

	platform_io := imgui.Gui_GetPlatformIO()

	SetClipboardText :: proc "c" (ctx: ^imgui.GuiContext, text: cstring) {
		glfw.SetClipboardString(nil, text)
	}
	GetClipboardText :: proc "c" (ctx: ^imgui.GuiContext) -> cstring {
		return glfwBindings.GetClipboardString(nil)
	}

	platform_io.Platform_SetClipboardTextFn = SetClipboardText
	platform_io.Platform_GetClipboardTextFn = GetClipboardText

	// Create mouse cursors
	// (By design, on X11 cursors are user configurable and some cursors may be missing. When a cursor doesn't exist,
	// GLFW will emit an error which will often be printed by the app, so we temporarily disable error reporting.
	// Missing cursors will return nullptr and our _UpdateMouseCursor() function will use the Arrow cursor instead.)
	prev_error_callback := glfw.SetErrorCallback(nil)
	bd.MouseCursors[imgui.GuiMouseCursor.Arrow] = glfw.CreateStandardCursor(glfw.ARROW_CURSOR)
	bd.MouseCursors[imgui.GuiMouseCursor.TextInput] = glfw.CreateStandardCursor(glfw.IBEAM_CURSOR)
	bd.MouseCursors[imgui.GuiMouseCursor.ResizeNS] = glfw.CreateStandardCursor(glfw.VRESIZE_CURSOR)
	bd.MouseCursors[imgui.GuiMouseCursor.ResizeEW] = glfw.CreateStandardCursor(glfw.HRESIZE_CURSOR)
	bd.MouseCursors[imgui.GuiMouseCursor.Hand] = glfw.CreateStandardCursor(glfw.HAND_CURSOR)
	bd.MouseCursors[imgui.GuiMouseCursor.ResizeAll] = glfw.CreateStandardCursor(
		glfw.RESIZE_ALL_CURSOR,
	)
	bd.MouseCursors[imgui.GuiMouseCursor.ResizeNESW] = glfw.CreateStandardCursor(
		glfw.RESIZE_NESW_CURSOR,
	)
	bd.MouseCursors[imgui.GuiMouseCursor.ResizeNWSE] = glfw.CreateStandardCursor(
		glfw.RESIZE_NWSE_CURSOR,
	)
	bd.MouseCursors[imgui.GuiMouseCursor.NotAllowed] = glfw.CreateStandardCursor(
		glfw.NOT_ALLOWED_CURSOR,
	)
	glfw.SetErrorCallback(prev_error_callback)
	glfw.GetError()

	if install_callbacks {
		InstallCallbacks(window)
	}

	UpdateMonitors()
	glfw.SetMonitorCallback(MonitorCallback)

	// Set platform dependent data in viewport
	main_viewport := imgui.Gui_GetMainViewport()
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
		hwnd := windows.HWND(main_viewport.PlatformHandleRaw)
		windows.SetPropW(hwnd, "IMGUI_BACKEND_DATA", windows.HANDLE(bd))
		bd.PrevWndProc = transmute(windows.WNDPROC)windows.GetWindowLongPtrW(
			hwnd,
			windows.GWLP_WNDPROC,
		)
		assert(bd.PrevWndProc != nil)
		windows.SetWindowLongPtrW(hwnd, windows.GWLP_WNDPROC, transmute(windows.LONG_PTR)WndProc)
	}

	bd.ClientApi = client_api
	return true
}

// Get data for current context
GetBackendDataNoWindow :: proc() -> ^Data {
	return(
		imgui.Gui_GetCurrentContext() != nil ? (^Data)(imgui.Gui_GetIO().BackendPlatformUserData) : nil \
	)
}

// Get data for a given GLFW window, regardless of current context (since GLFW events are sent together)
GetBackendDataWindow :: proc(window: glfw.WindowHandle) -> ^Data {
	return (^Data)(imgui.Gui_GetIOImGuiContextPtr(ContextMap[window]).BackendPlatformUserData)
}

GetBackendData :: proc {
	GetBackendDataNoWindow,
	GetBackendDataWindow,
}

KeyToImGuiKey :: proc(keycode, scancode: i32) -> imgui.GuiKey {
	switch keycode {
	case glfw.KEY_TAB:
		return .Key_Tab
	case glfw.KEY_LEFT:
		return .Key_LeftArrow
	case glfw.KEY_RIGHT:
		return .Key_RightArrow
	case glfw.KEY_UP:
		return .Key_UpArrow
	case glfw.KEY_DOWN:
		return .Key_DownArrow
	case glfw.KEY_PAGE_UP:
		return .Key_PageUp
	case glfw.KEY_PAGE_DOWN:
		return .Key_PageDown
	case glfw.KEY_HOME:
		return .Key_Home
	case glfw.KEY_END:
		return .Key_End
	case glfw.KEY_INSERT:
		return .Key_Insert
	case glfw.KEY_DELETE:
		return .Key_Delete
	case glfw.KEY_BACKSPACE:
		return .Key_Backspace
	case glfw.KEY_SPACE:
		return .Key_Space
	case glfw.KEY_ENTER:
		return .Key_Enter
	case glfw.KEY_ESCAPE:
		return .Key_Escape
	case glfw.KEY_APOSTROPHE:
		return .Key_Apostrophe
	case glfw.KEY_COMMA:
		return .Key_Comma
	case glfw.KEY_MINUS:
		return .Key_Minus
	case glfw.KEY_PERIOD:
		return .Key_Period
	case glfw.KEY_SLASH:
		return .Key_Slash
	case glfw.KEY_SEMICOLON:
		return .Key_Semicolon
	case glfw.KEY_EQUAL:
		return .Key_Equal
	case glfw.KEY_LEFT_BRACKET:
		return .Key_LeftBracket
	case glfw.KEY_BACKSLASH:
		return .Key_Backslash
	case glfw.KEY_WORLD_1:
		return .Key_Oem102
	case glfw.KEY_WORLD_2:
		return .Key_Oem102
	case glfw.KEY_RIGHT_BRACKET:
		return .Key_RightBracket
	case glfw.KEY_GRAVE_ACCENT:
		return .Key_GraveAccent
	case glfw.KEY_CAPS_LOCK:
		return .Key_CapsLock
	case glfw.KEY_SCROLL_LOCK:
		return .Key_ScrollLock
	case glfw.KEY_NUM_LOCK:
		return .Key_NumLock
	case glfw.KEY_PRINT_SCREEN:
		return .Key_PrintScreen
	case glfw.KEY_PAUSE:
		return .Key_Pause
	case glfw.KEY_KP_0:
		return .Key_Keypad0
	case glfw.KEY_KP_1:
		return .Key_Keypad1
	case glfw.KEY_KP_2:
		return .Key_Keypad2
	case glfw.KEY_KP_3:
		return .Key_Keypad3
	case glfw.KEY_KP_4:
		return .Key_Keypad4
	case glfw.KEY_KP_5:
		return .Key_Keypad5
	case glfw.KEY_KP_6:
		return .Key_Keypad6
	case glfw.KEY_KP_7:
		return .Key_Keypad7
	case glfw.KEY_KP_8:
		return .Key_Keypad8
	case glfw.KEY_KP_9:
		return .Key_Keypad9
	case glfw.KEY_KP_DECIMAL:
		return .Key_KeypadDecimal
	case glfw.KEY_KP_DIVIDE:
		return .Key_KeypadDivide
	case glfw.KEY_KP_MULTIPLY:
		return .Key_KeypadMultiply
	case glfw.KEY_KP_SUBTRACT:
		return .Key_KeypadSubtract
	case glfw.KEY_KP_ADD:
		return .Key_KeypadAdd
	case glfw.KEY_KP_ENTER:
		return .Key_KeypadEnter
	case glfw.KEY_KP_EQUAL:
		return .Key_KeypadEqual
	case glfw.KEY_LEFT_SHIFT:
		return .Key_LeftShift
	case glfw.KEY_LEFT_CONTROL:
		return .Key_LeftCtrl
	case glfw.KEY_LEFT_ALT:
		return .Key_LeftAlt
	case glfw.KEY_LEFT_SUPER:
		return .Key_LeftSuper
	case glfw.KEY_RIGHT_SHIFT:
		return .Key_RightShift
	case glfw.KEY_RIGHT_CONTROL:
		return .Key_RightCtrl
	case glfw.KEY_RIGHT_ALT:
		return .Key_RightAlt
	case glfw.KEY_RIGHT_SUPER:
		return .Key_RightSuper
	case glfw.KEY_MENU:
		return .Key_Menu
	case glfw.KEY_0:
		return .Key_0
	case glfw.KEY_1:
		return .Key_1
	case glfw.KEY_2:
		return .Key_2
	case glfw.KEY_3:
		return .Key_3
	case glfw.KEY_4:
		return .Key_4
	case glfw.KEY_5:
		return .Key_5
	case glfw.KEY_6:
		return .Key_6
	case glfw.KEY_7:
		return .Key_7
	case glfw.KEY_8:
		return .Key_8
	case glfw.KEY_9:
		return .Key_9
	case glfw.KEY_A:
		return .Key_A
	case glfw.KEY_B:
		return .Key_B
	case glfw.KEY_C:
		return .Key_C
	case glfw.KEY_D:
		return .Key_D
	case glfw.KEY_E:
		return .Key_E
	case glfw.KEY_F:
		return .Key_F
	case glfw.KEY_G:
		return .Key_G
	case glfw.KEY_H:
		return .Key_H
	case glfw.KEY_I:
		return .Key_I
	case glfw.KEY_J:
		return .Key_J
	case glfw.KEY_K:
		return .Key_K
	case glfw.KEY_L:
		return .Key_L
	case glfw.KEY_M:
		return .Key_M
	case glfw.KEY_N:
		return .Key_N
	case glfw.KEY_O:
		return .Key_O
	case glfw.KEY_P:
		return .Key_P
	case glfw.KEY_Q:
		return .Key_Q
	case glfw.KEY_R:
		return .Key_R
	case glfw.KEY_S:
		return .Key_S
	case glfw.KEY_T:
		return .Key_T
	case glfw.KEY_U:
		return .Key_U
	case glfw.KEY_V:
		return .Key_V
	case glfw.KEY_W:
		return .Key_W
	case glfw.KEY_X:
		return .Key_X
	case glfw.KEY_Y:
		return .Key_Y
	case glfw.KEY_Z:
		return .Key_Z
	case glfw.KEY_F1:
		return .Key_F1
	case glfw.KEY_F2:
		return .Key_F2
	case glfw.KEY_F3:
		return .Key_F3
	case glfw.KEY_F4:
		return .Key_F4
	case glfw.KEY_F5:
		return .Key_F5
	case glfw.KEY_F6:
		return .Key_F6
	case glfw.KEY_F7:
		return .Key_F7
	case glfw.KEY_F8:
		return .Key_F8
	case glfw.KEY_F9:
		return .Key_F9
	case glfw.KEY_F10:
		return .Key_F10
	case glfw.KEY_F11:
		return .Key_F11
	case glfw.KEY_F12:
		return .Key_F12
	case glfw.KEY_F13:
		return .Key_F13
	case glfw.KEY_F14:
		return .Key_F14
	case glfw.KEY_F15:
		return .Key_F15
	case glfw.KEY_F16:
		return .Key_F16
	case glfw.KEY_F17:
		return .Key_F17
	case glfw.KEY_F18:
		return .Key_F18
	case glfw.KEY_F19:
		return .Key_F19
	case glfw.KEY_F20:
		return .Key_F20
	case glfw.KEY_F21:
		return .Key_F21
	case glfw.KEY_F22:
		return .Key_F22
	case glfw.KEY_F23:
		return .Key_F23
	case glfw.KEY_F24:
		return .Key_F24
	case:
		return .Key_None
	}
}

UpdateKeyModifiers :: proc(io: ^imgui.GuiIO, window: glfw.WindowHandle) {
	imgui.GuiIO_AddKeyEvent(
		io,
		.Mod_Ctrl,
		(glfw.GetKey(window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_CONTROL) == glfw.PRESS),
	)
	imgui.GuiIO_AddKeyEvent(
		io,
		.Mod_Shift,
		(glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS),
	)
	imgui.GuiIO_AddKeyEvent(
		io,
		.Mod_Alt,
		(glfw.GetKey(window, glfw.KEY_LEFT_ALT) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_ALT) == glfw.PRESS),
	)
	imgui.GuiIO_AddKeyEvent(
		io,
		.Mod_Super,
		(glfw.GetKey(window, glfw.KEY_LEFT_SUPER) == glfw.PRESS) ||
		(glfw.GetKey(window, glfw.KEY_RIGHT_SUPER) == glfw.PRESS),
	)
}

// FIXME: should this be baked into ImGui_ImplGlfw_KeyToImGuiKey()? then what about the values passed to io.SetKeyEventNativeData()?
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

UpdateMouseData :: proc() {
	bd := GetBackendData()
	io := imgui.Gui_GetIO()
	platform_io := imgui.Gui_GetPlatformIO()

	mouse_viewport_id: imgui.GuiID = 0
	mouse_pos_prev := io.MousePos
	for n: i32 = 0; n < platform_io.Viewports.Size; n += 1 {
		viewport := platform_io.Viewports.Data[n]
		window := glfw.WindowHandle(viewport.PlatformHandle)

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
				imgui.GuiIO_AddMousePosEvent(io, f32(mouse_x), f32(mouse_y))
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
			mouse_viewport_id = viewport.ID
		}
		// We cannot use bd->MouseWindow maintained from CursorEnter/Leave callbacks, because it is locked to the window capturing mouse.
	}

	if .HasMouseHoveredViewport in io.BackendFlags {
		imgui.GuiIO_AddMouseViewportEvent(io, mouse_viewport_id)
	}
}

UpdateMouseCursor :: proc() {
	io := imgui.Gui_GetIO()
	bd := GetBackendData()
	if .NoMouseCursorChange in io.ConfigFlags ||
	   glfw.GetInputMode(bd.Window, glfw.CURSOR) == glfw.CURSOR_DISABLED {
		return
	}

	imgui_cursor := imgui.Gui_GetMouseCursor()
	platform_io := imgui.Gui_GetPlatformIO()
	for n: i32 = 0; n < platform_io.Viewports.Size; n += 1 {
		window := glfw.WindowHandle(platform_io.Viewports.Data[n].PlatformHandle)
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
				bd.MouseCursors[imgui_cursor] != nil ? bd.MouseCursors[imgui_cursor] : bd.MouseCursors[imgui.GuiMouseCursor.Arrow]
			if bd.LastMouseCursor != cursor {
				glfw.SetCursor(window, cursor)
				bd.LastMouseCursor = cursor
			}
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		}
	}
}

// Update gamepad inputs
Saturate :: #force_inline proc(v: f32) -> f32 {
	return math.clamp(v, 0, 1)
}

UpdateGamepads :: proc() {
	io := imgui.Gui_GetIO()
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
		io: ^imgui.GuiIO,
		gamepad: ^glfw.GamepadState,
		keyNo: imgui.GuiKey,
		buttonNo, _: i32,
	) {
		imgui.GuiIO_AddKeyEvent(io, keyNo, gamepad.buttons[buttonNo] != 0)
	}

	MAP_ANALOG :: #force_inline proc(
		io: ^imgui.GuiIO,
		gamepad: ^glfw.GamepadState,
		keyNo: imgui.GuiKey,
		axisNo, _: i32,
		v0, v1: f32,
	) {
		v := gamepad.axes[axisNo]
		v = (v - v0) / (v1 - v0)
		imgui.GuiIO_AddKeyAnalogEvent(io, keyNo, v > 0.10, Saturate(v))
	}

	io.BackendFlags += {.HasGamepad}
	MAP_BUTTON(io, &gamepad, .Key_GamepadStart, glfw.GAMEPAD_BUTTON_START, 7)
	MAP_BUTTON(io, &gamepad, .Key_GamepadBack, glfw.GAMEPAD_BUTTON_BACK, 6)
	MAP_BUTTON(io, &gamepad, .Key_GamepadFaceLeft, glfw.GAMEPAD_BUTTON_X, 2) // Xbox X, PS Square
	MAP_BUTTON(io, &gamepad, .Key_GamepadFaceRight, glfw.GAMEPAD_BUTTON_B, 1) // Xbox B, PS Circle
	MAP_BUTTON(io, &gamepad, .Key_GamepadFaceUp, glfw.GAMEPAD_BUTTON_Y, 3) // Xbox Y, PS Triangle
	MAP_BUTTON(io, &gamepad, .Key_GamepadFaceDown, glfw.GAMEPAD_BUTTON_A, 0) // Xbox A, PS Cross
	MAP_BUTTON(io, &gamepad, .Key_GamepadDpadLeft, glfw.GAMEPAD_BUTTON_DPAD_LEFT, 13)
	MAP_BUTTON(io, &gamepad, .Key_GamepadDpadRight, glfw.GAMEPAD_BUTTON_DPAD_RIGHT, 11)
	MAP_BUTTON(io, &gamepad, .Key_GamepadDpadUp, glfw.GAMEPAD_BUTTON_DPAD_UP, 10)
	MAP_BUTTON(io, &gamepad, .Key_GamepadDpadDown, glfw.GAMEPAD_BUTTON_DPAD_DOWN, 12)
	MAP_BUTTON(io, &gamepad, .Key_GamepadL1, glfw.GAMEPAD_BUTTON_LEFT_BUMPER, 4)
	MAP_BUTTON(io, &gamepad, .Key_GamepadR1, glfw.GAMEPAD_BUTTON_RIGHT_BUMPER, 5)
	MAP_ANALOG(io, &gamepad, .Key_GamepadL2, glfw.GAMEPAD_AXIS_LEFT_TRIGGER, 4, -0.75, +1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadR2, glfw.GAMEPAD_AXIS_RIGHT_TRIGGER, 5, -0.75, +1.0)
	MAP_BUTTON(io, &gamepad, .Key_GamepadL3, glfw.GAMEPAD_BUTTON_LEFT_THUMB, 8)
	MAP_BUTTON(io, &gamepad, .Key_GamepadR3, glfw.GAMEPAD_BUTTON_RIGHT_THUMB, 9)
	MAP_ANALOG(io, &gamepad, .Key_GamepadLStickLeft, glfw.GAMEPAD_AXIS_LEFT_X, 0, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadLStickRight, glfw.GAMEPAD_AXIS_LEFT_X, 0, +0.25, +1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadLStickUp, glfw.GAMEPAD_AXIS_LEFT_Y, 1, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadLStickDown, glfw.GAMEPAD_AXIS_LEFT_Y, 1, +0.25, +1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadRStickLeft, glfw.GAMEPAD_AXIS_RIGHT_X, 2, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadRStickRight, glfw.GAMEPAD_AXIS_RIGHT_X, 2, +0.25, +1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadRStickUp, glfw.GAMEPAD_AXIS_RIGHT_Y, 3, -0.25, -1.0)
	MAP_ANALOG(io, &gamepad, .Key_GamepadRStickDown, glfw.GAMEPAD_AXIS_RIGHT_Y, 3, +0.25, +1.0)
}

UpdateMonitors :: proc() {
	platform_io := imgui.Gui_GetPlatformIO()
	glfw_monitors := glfw.GetMonitors()

	updated_monitors := false
	for n := 0; n < len(glfw_monitors); n += 1 {
		monitor: imgui.GuiPlatformMonitor
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

		imgui.VectorPushBack(&platform_io.Monitors, monitor)
	}
}

// - On Windows the process needs to be marked DPI-aware!! SDL2 doesn't do it by default. You can call ::SetProcessDPIAware() or call ImGui_ImplWin32_EnableDpiAwareness() from Win32 backend.
// - Apple platforms use FramebufferScale so we always return 1.0f.
// - Some accessibility applications are declaring virtual monitors with a DPI of 0.0f, see #7902. We preserve this value for caller to handle.
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

ViewportDataBase :: struct {
	Window:                     glfw.WindowHandle,
	WindowOwned:                bool,
	IgnoreWindowPosEventFrame:  i32,
	IgnoreWindowSizeEventFrame: i32,
}

WindowCloseCallback :: proc "c" (window: glfw.WindowHandle) {
	if viewport := imgui.Gui_FindViewportByPlatformHandle(window); viewport != nil {
		viewport.PlatformRequestClose = true
	}
}

// GLFW may dispatch window pos/size events after calling glfwSetWindowPos()/glfwSetWindowSize().
// However: depending on the platform the callback may be invoked at different time:
// - on Windows it appears to be called within the glfwSetWindowPos()/glfwSetWindowSize() call
// - on Linux it is queued and invoked during glfwPollEvents()
// Because the event doesn't always fire on glfwSetWindowXXX() we use a frame counter tag to only
// ignore recent glfwSetWindowXXX() calls.
WindowPosCallback :: proc "c" (window: glfw.WindowHandle, _, _: i32) {
	if viewport := imgui.Gui_FindViewportByPlatformHandle(window); viewport != nil {
		if vd := (^ViewportData)(viewport.PlatformUserData); vd != nil {
			//data->IgnoreWindowPosEventFrame = -1;
			if imgui.Gui_GetFrameCount() <= vd.IgnoreWindowPosEventFrame + 1 {
				return
			}
		}
		viewport.PlatformRequestMove = true
	}
}

WindowSizeCallback :: proc "c" (window: glfw.WindowHandle, _, _: i32) {
	if viewport := imgui.Gui_FindViewportByPlatformHandle(window); viewport != nil {
		if vd := (^ViewportData)(viewport.PlatformUserData); vd != nil {
			//data->IgnoreWindowSizeEventFrame = -1;
			if imgui.Gui_GetFrameCount() <= vd.IgnoreWindowSizeEventFrame + 1 {
				return
			}
		}
		viewport.PlatformRequestResize = true
	}
}

CreateWindow :: proc "cdecl" (viewport: ^imgui.GuiViewport) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := new(ViewportData, internal_allocator)
	viewport.PlatformUserData = vd

	// Workaround for Linux: ignore mouse up events corresponding to losing focus of the previously focused window (#7733, #3158, #7922)
	when ODIN_OS == .Linux {
		bd.MouseIgnoreButtonUpWaitForFocusLoss = true
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
		bd.ClientApi == .OpenGL ? bd.Window : nil,
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
			windows.HWND(viewport.PlatformHandleRaw),
			"IMGUI_BACKEND_DATA",
			windows.HANDLE(bd),
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

	if bd.ClientApi == .OpenGL {
		glfw.MakeContextCurrent(vd.Window)
		glfw.SwapInterval(0)
	}
}

DestroyWindow :: proc "cdecl" (viewport: ^imgui.GuiViewport) {
	context = runtime.default_context()
	bd := GetBackendData()
	if vd := (^ViewportData)(viewport.PlatformUserData); vd != nil {
		if vd.WindowOwned {
			when ODIN_OS == .Windows {
				hwnd := windows.HWND(viewport.PlatformHandleRaw)
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

			delete_key(&ContextMap, vd.Window)
			glfw.DestroyWindow(vd.Window)
		}
		vd.Window = nil
		free(vd, internal_allocator)
	}
	viewport.PlatformUserData = nil
	viewport.PlatformHandle = nil
}

ShowWindow :: proc "cdecl" (viewport: ^imgui.GuiViewport) {
	vd := (^ViewportData)(viewport.PlatformUserData)

	when ODIN_OS == .Windows {
		// GLFW hack: Hide icon from task bar
		hwnd := windows.HWND(viewport.PlatformHandleRaw)
		if .NoTaskBarIcon in viewport.Flags {
			ex_style := windows.GetWindowLongW(hwnd, windows.GWL_EXSTYLE)
			ex_style &= transmute(i32)(~windows.WS_EX_APPWINDOW)
			ex_style |= i32(windows.WS_EX_TOOLWINDOW)
			windows.SetWindowLongW(hwnd, windows.GWL_EXSTYLE, ex_style)
		}

		// GLFW hack: install WndProc for mouse source event and WM_NCHITTEST message handler.
		windows.SetPropW(hwnd, "IMGUI_VIEWPORT", windows.HANDLE(viewport))
		vd.PrevWndProc = transmute(windows.WNDPROC)windows.GetWindowLongPtrW(
			hwnd,
			windows.GWLP_WNDPROC,
		)
		windows.SetWindowLongPtrW(hwnd, windows.GWLP_WNDPROC, transmute(windows.LONG_PTR)WndProc)
	}

	glfw.ShowWindow(vd.Window)
}

GetWindowPos :: proc "cdecl" (viewport: ^imgui.GuiViewport) -> imgui.Vec2 {
	vd := (^ViewportData)(viewport.PlatformUserData)
	x, y := glfw.GetWindowPos(vd.Window)
	return {f32(x), f32(y)}
}

SetWindowPos :: proc "cdecl" (viewport: ^imgui.GuiViewport, pos: imgui.Vec2) {
	vd := (^ViewportData)(viewport.PlatformUserData)
	vd.IgnoreWindowPosEventFrame = imgui.Gui_GetFrameCount()
	glfw.SetWindowPos(vd.Window, i32(pos.x), i32(pos.y))
}

GetWindowSize :: proc "cdecl" (viewport: ^imgui.GuiViewport) -> imgui.Vec2 {
	vd := (^ViewportData)(viewport.PlatformUserData)
	w, h := glfw.GetWindowSize(vd.Window)
	return {f32(w), f32(h)}
}

SetWindowSize :: proc "cdecl" (viewport: ^imgui.GuiViewport, size: imgui.Vec2) {
	vd := (^ViewportData)(viewport.PlatformUserData)
	vd.IgnoreWindowSizeEventFrame = imgui.Gui_GetFrameCount()
	glfw.SetWindowSize(vd.Window, i32(size.x), i32(size.y))
}

GetWindowFramebufferScale :: proc "cdecl" (viewport: ^imgui.GuiViewport) -> imgui.Vec2 {
	context = runtime.default_context()
	vd := (^ViewportData)(viewport.PlatformUserData)
	framebuffer_scale: imgui.Vec2 = ---
	GetWindowSizeAndFramebufferScale(vd.Window, nil, &framebuffer_scale)
	return framebuffer_scale
}

SetWindowTitle :: proc "cdecl" (viewport: ^imgui.GuiViewport, title: cstring) {
	vd := (^ViewportData)(viewport.PlatformUserData)
	glfw.SetWindowTitle(vd.Window, title)
}

SetWindowFocus :: proc "cdecl" (viewport: ^imgui.GuiViewport) {
	vd := (^ViewportData)(viewport.PlatformUserData)
	glfw.FocusWindow(vd.Window)
}

GetWindowFocus :: proc "cdecl" (viewport: ^imgui.GuiViewport) -> bool {
	vd := (^ViewportData)(viewport.PlatformUserData)
	return glfw.GetWindowAttrib(vd.Window, glfw.FOCUSED) != 0
}

GetWindowMinimized :: proc "cdecl" (viewport: ^imgui.GuiViewport) -> bool {
	vd := (^ViewportData)(viewport.PlatformUserData)
	return glfw.GetWindowAttrib(vd.Window, glfw.ICONIFIED) != 0
}

SetWindowAlpha :: proc "cdecl" (viewport: ^imgui.GuiViewport, alpha: f32) {
	vd := (^ViewportData)(viewport.PlatformUserData)
	glfw.SetWindowOpacity(vd.Window, alpha)
}

RenderWindow :: proc "cdecl" (viewport: ^imgui.GuiViewport, _: rawptr) {
	context = runtime.default_context()
	if GetBackendData().ClientApi != .OpenGL {
		return
	}

	vd := (^ViewportData)(viewport.PlatformUserData)
	glfw.MakeContextCurrent(vd.Window)
}

SwapBuffers :: proc "cdecl" (viewport: ^imgui.GuiViewport, _: rawptr) {
	context = runtime.default_context()
	if GetBackendData().ClientApi != .OpenGL {
		return
	}

	vd := (^ViewportData)(viewport.PlatformUserData)
	glfw.MakeContextCurrent(vd.Window)
	glfw.SwapBuffers(vd.Window)
}

//--------------------------------------------------------------------------------------------------------
// Vulkan support (the Vulkan renderer needs to call a platform-side support function to create the surface)
//--------------------------------------------------------------------------------------------------------

CreateVkSurface :: proc "cdecl" (
	viewport: ^imgui.GuiViewport,
	vk_instance: u64,
	vk_allocator: rawptr,
	out_vk_surface: ^u64,
) -> i32 {
	vd := (^ViewportData)(viewport.PlatformUserData)
	err := glfw.CreateWindowSurface(
		transmute(vk.Instance)vk_instance,
		vd.Window,
		transmute(^vk.AllocationCallbacks)vk_allocator,
		(^vk.SurfaceKHR)(out_vk_surface),
	)
	return i32(err)
}

InitMultiViewportSupport :: proc() {
	// Register platform interface (will be coupled with a renderer interface)
	bd := GetBackendData()
	platform_io := imgui.Gui_GetPlatformIO()
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
	main_viewport := imgui.Gui_GetMainViewport()
	vd := new(ViewportData, internal_allocator)
	vd.Window = bd.Window
	vd.WindowOwned = false
	main_viewport.PlatformUserData = vd
	main_viewport.PlatformHandle = bd.Window
}

ShutdownMultiViewportSupport :: proc() {
	imgui.Gui_DestroyPlatformWindows()
}

