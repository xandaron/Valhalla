package Valhalla

import "base:runtime"
import "core:strings"
import "vendor:glfw"

// ===[ Window ]================================================================

Window_Error :: enum {
	None,
	Window_Creation_Failed,
	Unsupported_On_Platform,
}

Window :: struct {
	handle: glfw.WindowHandle,
	data:   ^Window_Data,
}

@(private)
Window_Data :: struct {
	window:               Window,
	user_pointer:         rawptr,
	observer:             Input_Observer,
	key:                  Key_Proc,
	text:                 Text_Proc,
	mouse_button:         Mouse_Button_Proc,
	cursor_position:      Cursor_Position_Proc,
	cursor_enter:         Cursor_Enter_Proc,
	scroll:               Scroll_Proc,
	drop:                 Drop_Proc,
	window_position:      Window_Position_Proc,
	window_size:          Window_Size_Proc,
	window_close:         Window_Close_Proc,
	window_refresh:       Window_Refresh_Proc,
	window_focus:         Window_Focus_Proc,
	window_minimise:      Window_Minimise_Proc,
	window_maximise:      Window_Maximise_Proc,
	framebuffer_size:     Framebuffer_Size_Proc,
	window_content_scale: Window_Content_Scale_Proc,
	windowed_position:    [2]i32,
	windowed_size:        [2]i32,
}

@(private = "file")
position_on_monitor :: proc(position: [2]i32) -> bool {
	for monitor in monitors() {
		origin, size := monitor_work_area(monitor)
		if position.x >= origin.x && position.y >= origin.y && position.x < origin.x + size.x && position.y < origin.y + size.y {
			return true
		}
	}
	return false
}

@(require_results)
make_window :: proc(
	title := "",
	size := [2]i32{1280, 720},
	position: Maybe([2]i32) = nil,
	resizable := true,
	focus_on_show := true,
) -> (
	Window,
	Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(initialised, "Valhalla.init must be called before make_window")

	glfw.DefaultWindowHints()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.VISIBLE, false)
	glfw.WindowHint(glfw.RESIZABLE, b32(resizable))
	glfw.WindowHint(glfw.FOCUS_ON_SHOW, b32(focus_on_show))

	handle := glfw.CreateWindow(size.x, size.y, strings.clone_to_cstring(title, context.temp_allocator), nil, nil)
	if handle == nil {
		return {}, .Window_Creation_Failed
	}

	data := new(Window_Data)
	data.window = {
		handle = handle,
		data   = data,
	}
	if position, placed := position.?; placed && position_on_monitor(position) {
		_ = set_window_position(data.window, position)
	}
	glfw.SetWindowUserPointer(handle, data)
	install_window_callbacks(handle)
	glfw.ShowWindow(handle)

	return data.window, nil
}

delete_window :: proc(window: ^Window) {
	if window.handle == nil {
		return
	}
	glfw.DestroyWindow(window.handle)
	free(window.data)
	window^ = {}
}

should_close :: proc(window: Window) -> bool {
	return bool(glfw.WindowShouldClose(window.handle))
}

request_close :: proc(window: Window) {
	glfw.SetWindowShouldClose(window.handle, true)
}

window_size :: proc(window: Window) -> [2]i32 {
	width, height := glfw.GetWindowSize(window.handle)
	return {width, height}
}

window_framebuffer_size :: proc(window: Window) -> [2]i32 {
	width, height := glfw.GetFramebufferSize(window.handle)
	return {width, height}
}

@(require_results)
window_position :: proc(window: Window) -> (position: [2]i32, err: Error) {
	if glfw.GetPlatform() == glfw.PLATFORM_WAYLAND {
		return {}, .Unsupported_On_Platform
	}
	position.x, position.y = glfw.GetWindowPos(window.handle)
	return
}

window_content_scale :: proc(window: Window) -> [2]f32 {
	x, y := glfw.GetWindowContentScale(window.handle)
	return {x, y}
}

window_focused :: proc(window: Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.FOCUSED) != 0
}

window_hovered :: proc(window: Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.HOVERED) != 0
}

set_window_title :: proc(window: Window, title: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	glfw.SetWindowTitle(window.handle, strings.clone_to_cstring(title, context.temp_allocator))
}

set_window_user_pointer :: proc(window: Window, pointer: rawptr) {
	window.data.user_pointer = pointer
}

window_user_pointer :: proc(window: Window) -> rawptr {
	return window.data.user_pointer
}

set_window_size :: proc(window: Window, size: [2]i32) {
	glfw.SetWindowSize(window.handle, size.x, size.y)
}

@(require_results)
set_window_position :: proc(window: Window, position: [2]i32) -> Error {
	if glfw.GetPlatform() == glfw.PLATFORM_WAYLAND {
		return .Unsupported_On_Platform
	}
	glfw.SetWindowPos(window.handle, position.x, position.y)
	return nil
}

set_window_size_limits :: proc(window: Window, minimum: Maybe([2]i32) = nil, maximum: Maybe([2]i32) = nil) {
	low := minimum.? or_else {glfw.DONT_CARE, glfw.DONT_CARE}
	high := maximum.? or_else {glfw.DONT_CARE, glfw.DONT_CARE}
	glfw.SetWindowSizeLimits(window.handle, low.x, low.y, high.x, high.y)
}

set_window_aspect_ratio :: proc(window: Window, ratio: Maybe([2]i32)) {
	fixed := ratio.? or_else {glfw.DONT_CARE, glfw.DONT_CARE}
	glfw.SetWindowAspectRatio(window.handle, fixed.x, fixed.y)
}

minimise_window :: proc(window: Window) {
	glfw.IconifyWindow(window.handle)
}

maximise_window :: proc(window: Window) {
	glfw.MaximizeWindow(window.handle)
}

restore_window :: proc(window: Window) {
	glfw.RestoreWindow(window.handle)
}

show_window :: proc(window: Window) {
	glfw.ShowWindow(window.handle)
}

hide_window :: proc(window: Window) {
	glfw.HideWindow(window.handle)
}

focus_window :: proc(window: Window) {
	glfw.FocusWindow(window.handle)
}

request_window_attention :: proc(window: Window) {
	glfw.RequestWindowAttention(window.handle)
}

window_minimised :: proc(window: Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.ICONIFIED) != 0
}

window_maximised :: proc(window: Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.MAXIMIZED) != 0
}

window_visible :: proc(window: Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.VISIBLE) != 0
}

set_window_opacity :: proc(window: Window, opacity: f32) {
	glfw.SetWindowOpacity(window.handle, clamp(opacity, 0, 1))
}

window_opacity :: proc(window: Window) -> f32 {
	return glfw.GetWindowOpacity(window.handle)
}

set_window_resizable :: proc(window: Window, resizable: bool) {
	glfw.SetWindowAttrib(window.handle, glfw.RESIZABLE, i32(resizable))
}

set_window_decorated :: proc(window: Window, decorated: bool) {
	glfw.SetWindowAttrib(window.handle, glfw.DECORATED, i32(decorated))
}

set_window_floating :: proc(window: Window, floating: bool) {
	glfw.SetWindowAttrib(window.handle, glfw.FLOATING, i32(floating))
}

