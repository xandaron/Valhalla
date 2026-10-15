package Valhalla

import "base:runtime"
import "core:log"
import "core:strings"
import "vendor:glfw"

Input_Error :: enum {
	None,
	Cursor_Creation_Failed,
	Gamepad_Mappings_Rejected,
}

// ===[ Events ]================================================================

Frame_Proc :: #type proc(user_data: rawptr) -> Error

@(private = "file")
frame_callback: Frame_Proc

@(private = "file")
frame_user_data: rawptr

@(private = "file")
frame_error: Error

@(private = "file")
in_frame: bool

@(private)
polling_events: bool

set_frame_callback :: proc(callback: Frame_Proc, user_data: rawptr = nil) -> (previous: Frame_Proc, previous_user_data: rawptr) {
	previous, previous_user_data = frame_callback, frame_user_data
	frame_callback, frame_user_data = callback, user_data
	return
}

@(private)
request_frame :: proc() {
	if frame_callback == nil || !polling_events || in_frame || frame_error != nil {
		return
	}
	in_frame = true
	defer in_frame = false
	frame_error = frame_callback(frame_user_data)
}

@(private = "file")
begin_pumping :: proc() {
	assert(!polling_events, "events cannot be pumped from inside a callback")
	polling_events = true
}

@(private = "file")
end_pumping :: proc() -> (err: Error) {
	polling_events = false
	err, frame_error = frame_error, nil
	return
}

poll_events :: proc() -> Error {
	begin_pumping()
	glfw.PollEvents()
	return end_pumping()
}

wait_events :: proc() -> Error {
	begin_pumping()
	glfw.WaitEvents()
	return end_pumping()
}

wait_events_timeout :: proc(timeout: f64) -> Error {
	begin_pumping()
	glfw.WaitEventsTimeout(timeout)
	return end_pumping()
}

wake_events :: proc() {
	glfw.PostEmptyEvent()
}

time :: proc() -> f64 {
	return glfw.GetTime()
}

set_time :: proc(time: f64) {
	glfw.SetTime(time)
}

Key_Proc :: #type proc(window: ^Window, key: Key, scancode: i32, action: Action, modifiers: Modifiers)
Text_Proc :: #type proc(window: ^Window, codepoint: rune)
Mouse_Button_Proc :: #type proc(window: ^Window, button: Mouse_Button, action: Action, modifiers: Modifiers)
Cursor_Position_Proc :: #type proc(window: ^Window, position: [2]f64)
Cursor_Enter_Proc :: #type proc(window: ^Window, entered: bool)
Scroll_Proc :: #type proc(window: ^Window, offset: [2]f64)
Drop_Proc :: #type proc(window: ^Window, paths: []string)
Window_Position_Proc :: #type proc(window: ^Window, position: [2]i32)
Window_Size_Proc :: #type proc(window: ^Window, size: [2]i32)
Window_Close_Proc :: #type proc(window: ^Window)
Window_Refresh_Proc :: #type proc(window: ^Window)
Window_Focus_Proc :: #type proc(window: ^Window, focused: bool)
Window_Minimise_Proc :: #type proc(window: ^Window, minimised: bool)
Window_Maximise_Proc :: #type proc(window: ^Window, maximised: bool)
Framebuffer_Size_Proc :: #type proc(window: ^Window, size: [2]i32)
Window_Content_Scale_Proc :: #type proc(window: ^Window, scale: [2]f32)
Joystick_Proc :: #type proc(joystick: int, event: Connection_Event)

set_key_callback :: proc(window: ^Window, callback: Key_Proc) -> (previous: Key_Proc) {
	previous, window.data.key = window.data.key, callback
	return
}

set_text_callback :: proc(window: ^Window, callback: Text_Proc) -> (previous: Text_Proc) {
	previous, window.data.text = window.data.text, callback
	return
}

set_mouse_button_callback :: proc(window: ^Window, callback: Mouse_Button_Proc) -> (previous: Mouse_Button_Proc) {
	previous, window.data.mouse_button = window.data.mouse_button, callback
	return
}

set_cursor_position_callback :: proc(window: ^Window, callback: Cursor_Position_Proc) -> (previous: Cursor_Position_Proc) {
	previous, window.data.cursor_position = window.data.cursor_position, callback
	return
}

set_cursor_enter_callback :: proc(window: ^Window, callback: Cursor_Enter_Proc) -> (previous: Cursor_Enter_Proc) {
	previous, window.data.cursor_enter = window.data.cursor_enter, callback
	return
}

set_scroll_callback :: proc(window: ^Window, callback: Scroll_Proc) -> (previous: Scroll_Proc) {
	previous, window.data.scroll = window.data.scroll, callback
	return
}

set_drop_callback :: proc(window: ^Window, callback: Drop_Proc) -> (previous: Drop_Proc) {
	previous, window.data.drop = window.data.drop, callback
	return
}

set_window_position_callback :: proc(window: ^Window, callback: Window_Position_Proc) -> (previous: Window_Position_Proc) {
	previous, window.data.window_position = window.data.window_position, callback
	return
}

set_window_size_callback :: proc(window: ^Window, callback: Window_Size_Proc) -> (previous: Window_Size_Proc) {
	previous, window.data.window_size = window.data.window_size, callback
	return
}

set_window_close_callback :: proc(window: ^Window, callback: Window_Close_Proc) -> (previous: Window_Close_Proc) {
	previous, window.data.window_close = window.data.window_close, callback
	return
}

set_window_refresh_callback :: proc(window: ^Window, callback: Window_Refresh_Proc) -> (previous: Window_Refresh_Proc) {
	previous, window.data.window_refresh = window.data.window_refresh, callback
	return
}

set_window_focus_callback :: proc(window: ^Window, callback: Window_Focus_Proc) -> (previous: Window_Focus_Proc) {
	previous, window.data.window_focus = window.data.window_focus, callback
	return
}

set_window_minimise_callback :: proc(window: ^Window, callback: Window_Minimise_Proc) -> (previous: Window_Minimise_Proc) {
	previous, window.data.window_minimise = window.data.window_minimise, callback
	return
}

set_window_maximise_callback :: proc(window: ^Window, callback: Window_Maximise_Proc) -> (previous: Window_Maximise_Proc) {
	previous, window.data.window_maximise = window.data.window_maximise, callback
	return
}

set_framebuffer_size_callback :: proc(window: ^Window, callback: Framebuffer_Size_Proc) -> (previous: Framebuffer_Size_Proc) {
	previous, window.data.framebuffer_size = window.data.framebuffer_size, callback
	return
}

set_window_content_scale_callback :: proc(
	window: ^Window,
	callback: Window_Content_Scale_Proc,
) -> (
	previous: Window_Content_Scale_Proc,
) {
	previous, window.data.window_content_scale = window.data.window_content_scale, callback
	return
}

set_joystick_callback :: proc(callback: Joystick_Proc) -> (previous: Joystick_Proc) {
	previous, joystick_callback = joystick_callback, callback
	return
}

@(private = "file")
joystick_callback: Joystick_Proc

@(private = "file")
window_data :: proc "contextless" (handle: glfw.WindowHandle) -> ^Window_Data {
	return (^Window_Data)(glfw.GetWindowUserPointer(handle))
}

@(private)
install_error_callback :: proc() {
	glfw.SetErrorCallback(proc "c" (code: i32, description: cstring) {
		context = runtime_context
		if reading_clipboard && code == glfw.FORMAT_UNAVAILABLE {
			return
		}
		log.errorf("GLFW error %v: %s", code, description)
	})
}

@(private)
install_joystick_callback :: proc() {
	glfw.SetJoystickCallback(proc "c" (joystick, event: i32) {
		context = runtime_context
		if joystick_callback != nil {
			joystick_callback(int(joystick), Connection_Event(event))
		}
	})
}

@(private)
install_window_callbacks :: proc(handle: glfw.WindowHandle) {
	install_modal_loop_timer(handle)
	glfw.SetKeyCallback(handle, proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
		context = runtime_context
		inject_key(&window_data(handle).window, Key(key), scancode, Action(action), transmute(Modifiers)u8(mods))
	})
	glfw.SetCharCallback(handle, proc "c" (handle: glfw.WindowHandle, codepoint: rune) {
		context = runtime_context
		inject_text(&window_data(handle).window, codepoint)
	})
	glfw.SetMouseButtonCallback(handle, proc "c" (handle: glfw.WindowHandle, button, action, mods: i32) {
		context = runtime_context
		inject_mouse_button(&window_data(handle).window, Mouse_Button(button), Action(action), transmute(Modifiers)u8(mods))
	})
	glfw.SetCursorPosCallback(handle, proc "c" (handle: glfw.WindowHandle, x, y: f64) {
		context = runtime_context
		inject_cursor_position(&window_data(handle).window, {x, y})
	})
	glfw.SetCursorEnterCallback(handle, proc "c" (handle: glfw.WindowHandle, entered: i32) {
		context = runtime_context
		inject_cursor_enter(&window_data(handle).window, entered != 0)
	})
	glfw.SetScrollCallback(handle, proc "c" (handle: glfw.WindowHandle, x, y: f64) {
		context = runtime_context
		inject_scroll(&window_data(handle).window, {x, y})
	})
	glfw.SetDropCallback(handle, proc "c" (handle: glfw.WindowHandle, count: i32, paths: [^]cstring) {
		context = runtime_context
		data := window_data(handle)
		if data.drop == nil {
			return
		}
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		dropped := make([]string, count, context.temp_allocator)
		for index in 0 ..< int(count) {
			dropped[index] = string(paths[index])
		}
		data.drop(&data.window, dropped)
	})
	glfw.SetWindowPosCallback(handle, proc "c" (handle: glfw.WindowHandle, x, y: i32) {
		context = runtime_context
		if data := window_data(handle); data.window_position != nil {
			data.window_position(&data.window, {x, y})
		}
	})
	glfw.SetWindowSizeCallback(handle, proc "c" (handle: glfw.WindowHandle, width, height: i32) {
		context = runtime_context
		if data := window_data(handle); data.window_size != nil {
			data.window_size(&data.window, {width, height})
		}
	})
	glfw.SetWindowCloseCallback(handle, proc "c" (handle: glfw.WindowHandle) {
		context = runtime_context
		if data := window_data(handle); data.window_close != nil {
			data.window_close(&data.window)
		}
	})
	glfw.SetWindowRefreshCallback(handle, proc "c" (handle: glfw.WindowHandle) {
		context = runtime_context
		if data := window_data(handle); data.window_refresh != nil {
			data.window_refresh(&data.window)
		}
		request_frame()
	})
	glfw.SetWindowFocusCallback(handle, proc "c" (handle: glfw.WindowHandle, focused: i32) {
		context = runtime_context
		inject_focus(&window_data(handle).window, focused != 0)
	})
	glfw.SetWindowIconifyCallback(handle, proc "c" (handle: glfw.WindowHandle, minimised: i32) {
		context = runtime_context
		if data := window_data(handle); data.window_minimise != nil {
			data.window_minimise(&data.window, minimised != 0)
		}
	})
	glfw.SetWindowMaximizeCallback(handle, proc "c" (handle: glfw.WindowHandle, maximised: i32) {
		context = runtime_context
		if data := window_data(handle); data.window_maximise != nil {
			data.window_maximise(&data.window, maximised != 0)
		}
	})
	glfw.SetFramebufferSizeCallback(handle, proc "c" (handle: glfw.WindowHandle, width, height: i32) {
		context = runtime_context
		if data := window_data(handle); data.framebuffer_size != nil {
			data.framebuffer_size(&data.window, {width, height})
		}
		if width > 0 && height > 0 {
			request_frame()
		}
	})
	glfw.SetWindowContentScaleCallback(handle, proc "c" (handle: glfw.WindowHandle, x, y: f32) {
		context = runtime_context
		if data := window_data(handle); data.window_content_scale != nil {
			data.window_content_scale(&data.window, {x, y})
		}
	})
}

// ===[ Keyboard and Mouse ]====================================================

Key :: enum i32 {
	Unknown         = glfw.KEY_UNKNOWN,
	Space           = glfw.KEY_SPACE,
	Apostrophe      = glfw.KEY_APOSTROPHE,
	Comma           = glfw.KEY_COMMA,
	Minus           = glfw.KEY_MINUS,
	Period          = glfw.KEY_PERIOD,
	Slash           = glfw.KEY_SLASH,
	Digit_0         = glfw.KEY_0,
	Digit_1         = glfw.KEY_1,
	Digit_2         = glfw.KEY_2,
	Digit_3         = glfw.KEY_3,
	Digit_4         = glfw.KEY_4,
	Digit_5         = glfw.KEY_5,
	Digit_6         = glfw.KEY_6,
	Digit_7         = glfw.KEY_7,
	Digit_8         = glfw.KEY_8,
	Digit_9         = glfw.KEY_9,
	Semicolon       = glfw.KEY_SEMICOLON,
	Equal           = glfw.KEY_EQUAL,
	A               = glfw.KEY_A,
	B               = glfw.KEY_B,
	C               = glfw.KEY_C,
	D               = glfw.KEY_D,
	E               = glfw.KEY_E,
	F               = glfw.KEY_F,
	G               = glfw.KEY_G,
	H               = glfw.KEY_H,
	I               = glfw.KEY_I,
	J               = glfw.KEY_J,
	K               = glfw.KEY_K,
	L               = glfw.KEY_L,
	M               = glfw.KEY_M,
	N               = glfw.KEY_N,
	O               = glfw.KEY_O,
	P               = glfw.KEY_P,
	Q               = glfw.KEY_Q,
	R               = glfw.KEY_R,
	S               = glfw.KEY_S,
	T               = glfw.KEY_T,
	U               = glfw.KEY_U,
	V               = glfw.KEY_V,
	W               = glfw.KEY_W,
	X               = glfw.KEY_X,
	Y               = glfw.KEY_Y,
	Z               = glfw.KEY_Z,
	Left_Bracket    = glfw.KEY_LEFT_BRACKET,
	Backslash       = glfw.KEY_BACKSLASH,
	Right_Bracket   = glfw.KEY_RIGHT_BRACKET,
	Grave_Accent    = glfw.KEY_GRAVE_ACCENT,
	World_1         = glfw.KEY_WORLD_1,
	World_2         = glfw.KEY_WORLD_2,
	Escape          = glfw.KEY_ESCAPE,
	Enter           = glfw.KEY_ENTER,
	Tab             = glfw.KEY_TAB,
	Backspace       = glfw.KEY_BACKSPACE,
	Insert          = glfw.KEY_INSERT,
	Delete          = glfw.KEY_DELETE,
	Right           = glfw.KEY_RIGHT,
	Left            = glfw.KEY_LEFT,
	Down            = glfw.KEY_DOWN,
	Up              = glfw.KEY_UP,
	Page_Up         = glfw.KEY_PAGE_UP,
	Page_Down       = glfw.KEY_PAGE_DOWN,
	Home            = glfw.KEY_HOME,
	End             = glfw.KEY_END,
	Caps_Lock       = glfw.KEY_CAPS_LOCK,
	Scroll_Lock     = glfw.KEY_SCROLL_LOCK,
	Num_Lock        = glfw.KEY_NUM_LOCK,
	Print_Screen    = glfw.KEY_PRINT_SCREEN,
	Pause           = glfw.KEY_PAUSE,
	F1              = glfw.KEY_F1,
	F2              = glfw.KEY_F2,
	F3              = glfw.KEY_F3,
	F4              = glfw.KEY_F4,
	F5              = glfw.KEY_F5,
	F6              = glfw.KEY_F6,
	F7              = glfw.KEY_F7,
	F8              = glfw.KEY_F8,
	F9              = glfw.KEY_F9,
	F10             = glfw.KEY_F10,
	F11             = glfw.KEY_F11,
	F12             = glfw.KEY_F12,
	F13             = glfw.KEY_F13,
	F14             = glfw.KEY_F14,
	F15             = glfw.KEY_F15,
	F16             = glfw.KEY_F16,
	F17             = glfw.KEY_F17,
	F18             = glfw.KEY_F18,
	F19             = glfw.KEY_F19,
	F20             = glfw.KEY_F20,
	F21             = glfw.KEY_F21,
	F22             = glfw.KEY_F22,
	F23             = glfw.KEY_F23,
	F24             = glfw.KEY_F24,
	F25             = glfw.KEY_F25,
	Keypad_0        = glfw.KEY_KP_0,
	Keypad_1        = glfw.KEY_KP_1,
	Keypad_2        = glfw.KEY_KP_2,
	Keypad_3        = glfw.KEY_KP_3,
	Keypad_4        = glfw.KEY_KP_4,
	Keypad_5        = glfw.KEY_KP_5,
	Keypad_6        = glfw.KEY_KP_6,
	Keypad_7        = glfw.KEY_KP_7,
	Keypad_8        = glfw.KEY_KP_8,
	Keypad_9        = glfw.KEY_KP_9,
	Keypad_Decimal  = glfw.KEY_KP_DECIMAL,
	Keypad_Divide   = glfw.KEY_KP_DIVIDE,
	Keypad_Multiply = glfw.KEY_KP_MULTIPLY,
	Keypad_Subtract = glfw.KEY_KP_SUBTRACT,
	Keypad_Add      = glfw.KEY_KP_ADD,
	Keypad_Enter    = glfw.KEY_KP_ENTER,
	Keypad_Equal    = glfw.KEY_KP_EQUAL,
	Left_Shift      = glfw.KEY_LEFT_SHIFT,
	Left_Control    = glfw.KEY_LEFT_CONTROL,
	Left_Alt        = glfw.KEY_LEFT_ALT,
	Left_Super      = glfw.KEY_LEFT_SUPER,
	Right_Shift     = glfw.KEY_RIGHT_SHIFT,
	Right_Control   = glfw.KEY_RIGHT_CONTROL,
	Right_Alt       = glfw.KEY_RIGHT_ALT,
	Right_Super     = glfw.KEY_RIGHT_SUPER,
	Menu            = glfw.KEY_MENU,
}

Action :: enum u8 {
	Release = glfw.RELEASE,
	Press   = glfw.PRESS,
	Repeat  = glfw.REPEAT,
}

Mouse_Button :: enum i32 {
	Left     = glfw.MOUSE_BUTTON_LEFT,
	Right    = glfw.MOUSE_BUTTON_RIGHT,
	Middle   = glfw.MOUSE_BUTTON_MIDDLE,
	Button_4 = glfw.MOUSE_BUTTON_4,
	Button_5 = glfw.MOUSE_BUTTON_5,
	Button_6 = glfw.MOUSE_BUTTON_6,
	Button_7 = glfw.MOUSE_BUTTON_7,
	Button_8 = glfw.MOUSE_BUTTON_8,
}

Modifier :: enum {
	Shift,
	Control,
	Alt,
	Super,
	Caps_Lock,
	Num_Lock,
}

Modifiers :: bit_set[Modifier;u8]

#assert(1 << uint(Modifier.Shift) == glfw.MOD_SHIFT)
#assert(1 << uint(Modifier.Num_Lock) == glfw.MOD_NUM_LOCK)

Cursor_Mode :: enum i32 {
	Normal   = glfw.CURSOR_NORMAL,
	Hidden   = glfw.CURSOR_HIDDEN,
	Disabled = glfw.CURSOR_DISABLED,
	Captured = glfw.CURSOR_CAPTURED,
}

Cursor_Shape :: enum i32 {
	Arrow         = glfw.ARROW_CURSOR,
	IBeam         = glfw.IBEAM_CURSOR,
	Crosshair     = glfw.CROSSHAIR_CURSOR,
	Pointing_Hand = glfw.POINTING_HAND_CURSOR,
	Resize_EW     = glfw.RESIZE_EW_CURSOR,
	Resize_NS     = glfw.RESIZE_NS_CURSOR,
	Resize_NWSE   = glfw.RESIZE_NWSE_CURSOR,
	Resize_NESW   = glfw.RESIZE_NESW_CURSOR,
	Resize_All    = glfw.RESIZE_ALL_CURSOR,
	Not_Allowed   = glfw.NOT_ALLOWED_CURSOR,
}

Cursor :: struct {
	handle: glfw.CursorHandle,
}

key_down :: proc(window: ^Window, key: Key) -> bool {
	assert(key != .Unknown, "key_down needs a known key")
	return glfw.GetKey(window.handle, i32(key)) == glfw.PRESS
}

key_name :: proc(key: Key, scancode: i32) -> string {
	return glfw.GetKeyName(i32(key), scancode)
}

key_scancode :: proc(key: Key) -> i32 {
	assert(key != .Unknown, "key_scancode needs a known key")
	return glfw.GetKeyScancode(i32(key))
}

mouse_button_down :: proc(window: ^Window, button: Mouse_Button) -> bool {
	return glfw.GetMouseButton(window.handle, i32(button)) == glfw.PRESS
}

cursor_position :: proc(window: ^Window) -> [2]f64 {
	x, y := glfw.GetCursorPos(window.handle)
	return {x, y}
}

set_cursor_position :: proc(window: ^Window, position: [2]f64) {
	glfw.SetCursorPos(window.handle, position.x, position.y)
}

cursor_mode :: proc(window: ^Window) -> Cursor_Mode {
	return Cursor_Mode(glfw.GetInputMode(window.handle, glfw.CURSOR))
}

set_cursor_mode :: proc(window: ^Window, mode: Cursor_Mode) {
	glfw.SetInputMode(window.handle, glfw.CURSOR, i32(mode))
}

set_sticky_keys :: proc(window: ^Window, enabled: bool) {
	glfw.SetInputMode(window.handle, glfw.STICKY_KEYS, i32(enabled))
}

set_sticky_mouse_buttons :: proc(window: ^Window, enabled: bool) {
	glfw.SetInputMode(window.handle, glfw.STICKY_MOUSE_BUTTONS, i32(enabled))
}

set_lock_key_modifiers :: proc(window: ^Window, enabled: bool) {
	glfw.SetInputMode(window.handle, glfw.LOCK_KEY_MODS, i32(enabled))
}

raw_mouse_motion_supported :: proc() -> bool {
	return bool(glfw.RawMouseMotionSupported())
}

set_raw_mouse_motion :: proc(window: ^Window, enabled: bool) -> Error {
	if !glfw.RawMouseMotionSupported() {
		return .Unsupported_On_Platform
	}
	glfw.SetInputMode(window.handle, glfw.RAW_MOUSE_MOTION, i32(enabled))
	return nil
}

@(require_results)
make_standard_cursor :: proc(shape: Cursor_Shape) -> (Cursor, Error) {
	assert(initialised, "Valhalla.init must be called before make_standard_cursor")
	handle := glfw.CreateStandardCursor(i32(shape))
	if handle == nil {
		return {}, .Cursor_Creation_Failed
	}
	return {handle = handle}, nil
}

@(require_results)
make_cursor :: proc(pixels: []u8, size: [2]i32, hotspot := [2]i32{}) -> (Cursor, Error) {
	assert(initialised, "Valhalla.init must be called before make_cursor")
	assert(size.x > 0 && size.y > 0, "make_cursor needs a non-empty size")
	assert(len(pixels) == int(size.x * size.y * 4), "make_cursor needs size.x * size.y RGBA8 pixels")
	image := glfw.Image {
		width  = size.x,
		height = size.y,
		pixels = raw_data(pixels),
	}
	handle := glfw.CreateCursor(&image, hotspot.x, hotspot.y)
	if handle == nil {
		return {}, .Cursor_Creation_Failed
	}
	return {handle = handle}, nil
}

delete_cursor :: proc(cursor: ^Cursor) {
	if cursor.handle == nil {
		return
	}
	glfw.DestroyCursor(cursor.handle)
	cursor^ = {}
}

set_cursor :: proc(window: ^Window, cursor: Maybe(Cursor)) {
	handle: glfw.CursorHandle
	if cursor, set := cursor.?; set {
		handle = cursor.handle
	}
	glfw.SetCursor(window.handle, handle)
}

@(private = "file")
reading_clipboard: bool

clipboard_text :: proc() -> string {
	reading_clipboard = true
	defer reading_clipboard = false
	return glfw.GetClipboardString(nil)
}

set_clipboard_text :: proc(text: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	glfw.SetClipboardString(nil, strings.clone_to_cstring(text, context.temp_allocator))
}

// ===[ Injected Input ]========================================================

inject_key :: proc(window: ^Window, key: Key, scancode: i32, action: Action, modifiers: Modifiers) {
	if window.data.key != nil {
		window.data.key(window, key, scancode, action, modifiers)
	}
}

inject_text :: proc(window: ^Window, codepoint: rune) {
	if window.data.text != nil {
		window.data.text(window, codepoint)
	}
}

inject_mouse_button :: proc(window: ^Window, button: Mouse_Button, action: Action, modifiers: Modifiers) {
	if window.data.mouse_button != nil {
		window.data.mouse_button(window, button, action, modifiers)
	}
}

inject_cursor_position :: proc(window: ^Window, position: [2]f64) {
	if window.data.cursor_position != nil {
		window.data.cursor_position(window, position)
	}
}

inject_cursor_enter :: proc(window: ^Window, entered: bool) {
	if window.data.cursor_enter != nil {
		window.data.cursor_enter(window, entered)
	}
}

inject_scroll :: proc(window: ^Window, offset: [2]f64) {
	if window.data.scroll != nil {
		window.data.scroll(window, offset)
	}
}

inject_focus :: proc(window: ^Window, focused: bool) {
	if window.data.window_focus != nil {
		window.data.window_focus(window, focused)
	}
}

// ===[ Joysticks and Gamepads ]================================================

MAX_JOYSTICKS :: glfw.JOYSTICK_LAST + 1

Connection_Event :: enum i32 {
	Connected    = glfw.CONNECTED,
	Disconnected = glfw.DISCONNECTED,
}

Hat_Direction :: enum {
	Up,
	Right,
	Down,
	Left,
}

Hat :: bit_set[Hat_Direction;u8]

#assert(1 << uint(Hat_Direction.Up) == glfw.HAT_UP)
#assert(1 << uint(Hat_Direction.Left) == glfw.HAT_LEFT)

Gamepad_Button :: enum i32 {
	A            = glfw.GAMEPAD_BUTTON_A,
	B            = glfw.GAMEPAD_BUTTON_B,
	X            = glfw.GAMEPAD_BUTTON_X,
	Y            = glfw.GAMEPAD_BUTTON_Y,
	Left_Bumper  = glfw.GAMEPAD_BUTTON_LEFT_BUMPER,
	Right_Bumper = glfw.GAMEPAD_BUTTON_RIGHT_BUMPER,
	Back         = glfw.GAMEPAD_BUTTON_BACK,
	Start        = glfw.GAMEPAD_BUTTON_START,
	Guide        = glfw.GAMEPAD_BUTTON_GUIDE,
	Left_Thumb   = glfw.GAMEPAD_BUTTON_LEFT_THUMB,
	Right_Thumb  = glfw.GAMEPAD_BUTTON_RIGHT_THUMB,
	Dpad_Up      = glfw.GAMEPAD_BUTTON_DPAD_UP,
	Dpad_Right   = glfw.GAMEPAD_BUTTON_DPAD_RIGHT,
	Dpad_Down    = glfw.GAMEPAD_BUTTON_DPAD_DOWN,
	Dpad_Left    = glfw.GAMEPAD_BUTTON_DPAD_LEFT,
}

Gamepad_Axis :: enum i32 {
	Left_X        = glfw.GAMEPAD_AXIS_LEFT_X,
	Left_Y        = glfw.GAMEPAD_AXIS_LEFT_Y,
	Right_X       = glfw.GAMEPAD_AXIS_RIGHT_X,
	Right_Y       = glfw.GAMEPAD_AXIS_RIGHT_Y,
	Left_Trigger  = glfw.GAMEPAD_AXIS_LEFT_TRIGGER,
	Right_Trigger = glfw.GAMEPAD_AXIS_RIGHT_TRIGGER,
}

Gamepad_State :: struct {
	buttons: [Gamepad_Button]Action,
	axes:    [Gamepad_Axis]f32,
}

#assert(size_of(Gamepad_State) == size_of(glfw.GamepadState))
#assert(offset_of(Gamepad_State, axes) == offset_of(glfw.GamepadState, axes))

@(private = "file")
joystick_id :: proc(joystick: int, loc := #caller_location) -> i32 {
	assert(joystick >= 0 && joystick < MAX_JOYSTICKS, "joystick out of range", loc)
	return i32(joystick)
}

joystick_present :: proc(joystick: int) -> bool {
	return bool(glfw.JoystickPresent(joystick_id(joystick)))
}

joystick_axes :: proc(joystick: int) -> []f32 {
	return glfw.GetJoystickAxes(joystick_id(joystick))
}

joystick_buttons :: proc(joystick: int) -> []Action {
	return transmute([]Action)glfw.GetJoystickButtons(joystick_id(joystick))
}

joystick_hats :: proc(joystick: int) -> []Hat {
	return transmute([]Hat)glfw.GetJoystickHats(joystick_id(joystick))
}

joystick_name :: proc(joystick: int) -> string {
	return glfw.GetJoystickName(joystick_id(joystick))
}

joystick_guid :: proc(joystick: int) -> string {
	return glfw.GetJoystickGUID(joystick_id(joystick))
}

set_joystick_user_pointer :: proc(joystick: int, pointer: rawptr) {
	glfw.SetJoystickUserPointer(joystick_id(joystick), pointer)
}

joystick_user_pointer :: proc(joystick: int) -> rawptr {
	return glfw.GetJoystickUserPointer(joystick_id(joystick))
}

joystick_is_gamepad :: proc(joystick: int) -> bool {
	return bool(glfw.JoystickIsGamepad(joystick_id(joystick)))
}

gamepad_name :: proc(joystick: int) -> string {
	return glfw.GetGamepadName(joystick_id(joystick))
}

gamepad_state :: proc(joystick: int) -> (state: Gamepad_State, ok: bool) {
	ok = bool(glfw.GetGamepadState(joystick_id(joystick), (^glfw.GamepadState)(&state)))
	return
}

update_gamepad_mappings :: proc(mappings: string) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if !glfw.UpdateGamepadMappings(strings.clone_to_cstring(mappings, context.temp_allocator)) {
		return .Gamepad_Mappings_Rejected
	}
	return nil
}
