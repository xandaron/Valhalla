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
	for monitor in glfw.GetMonitors() {
		x, y, width, height := glfw.GetMonitorWorkarea(monitor)
		if position.x >= x && position.y >= y && position.x < x + width && position.y < y + height {
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

	if position, placed := position.?;
	   placed && glfw.GetPlatform() != glfw.PLATFORM_WAYLAND && position_on_monitor(position) {
		glfw.SetWindowPos(handle, position.x, position.y)
	}
	data := new(Window_Data)
	data.window = {
		handle = handle,
		data   = data,
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

should_close :: proc(window: ^Window) -> bool {
	assert(window != nil)
	return bool(glfw.WindowShouldClose(window.handle))
}

request_close :: proc(window: ^Window) {
	glfw.SetWindowShouldClose(window.handle, true)
}

window_size :: proc(window: ^Window) -> [2]i32 {
	width, height := glfw.GetWindowSize(window.handle)
	return {width, height}
}

window_framebuffer_size :: proc(window: ^Window) -> [2]i32 {
	width, height := glfw.GetFramebufferSize(window.handle)
	return {width, height}
}

window_position :: proc(window: ^Window) -> (position: [2]i32, err: Error) {
	if glfw.GetPlatform() == glfw.PLATFORM_WAYLAND {
		return {}, .Unsupported_On_Platform
	}
	position.x, position.y = glfw.GetWindowPos(window.handle)
	return
}

window_content_scale :: proc(window: ^Window) -> [2]f32 {
	x, y := glfw.GetWindowContentScale(window.handle)
	return {x, y}
}

window_focused :: proc(window: ^Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.FOCUSED) != 0
}

window_hovered :: proc(window: ^Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.HOVERED) != 0
}

set_window_title :: proc(window: ^Window, title: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	glfw.SetWindowTitle(window.handle, strings.clone_to_cstring(title, context.temp_allocator))
}

set_window_user_pointer :: proc(window: ^Window, pointer: rawptr) {
	window.data.user_pointer = pointer
}

window_user_pointer :: proc(window: ^Window) -> rawptr {
	return window.data.user_pointer
}

set_window_size :: proc(window: ^Window, size: [2]i32) {
	glfw.SetWindowSize(window.handle, size.x, size.y)
}

set_window_position :: proc(window: ^Window, position: [2]i32) -> Error {
	if glfw.GetPlatform() == glfw.PLATFORM_WAYLAND {
		return .Unsupported_On_Platform
	}
	glfw.SetWindowPos(window.handle, position.x, position.y)
	return nil
}

set_window_size_limits :: proc(window: ^Window, minimum: Maybe([2]i32) = nil, maximum: Maybe([2]i32) = nil) {
	low := minimum.? or_else {glfw.DONT_CARE, glfw.DONT_CARE}
	high := maximum.? or_else {glfw.DONT_CARE, glfw.DONT_CARE}
	glfw.SetWindowSizeLimits(window.handle, low.x, low.y, high.x, high.y)
}

set_window_aspect_ratio :: proc(window: ^Window, ratio: Maybe([2]i32)) {
	fixed := ratio.? or_else {glfw.DONT_CARE, glfw.DONT_CARE}
	glfw.SetWindowAspectRatio(window.handle, fixed.x, fixed.y)
}

minimise_window :: proc(window: ^Window) {
	glfw.IconifyWindow(window.handle)
}

maximise_window :: proc(window: ^Window) {
	glfw.MaximizeWindow(window.handle)
}

restore_window :: proc(window: ^Window) {
	glfw.RestoreWindow(window.handle)
}

show_window :: proc(window: ^Window) {
	glfw.ShowWindow(window.handle)
}

hide_window :: proc(window: ^Window) {
	glfw.HideWindow(window.handle)
}

focus_window :: proc(window: ^Window) {
	glfw.FocusWindow(window.handle)
}

request_window_attention :: proc(window: ^Window) {
	glfw.RequestWindowAttention(window.handle)
}

window_minimised :: proc(window: ^Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.ICONIFIED) != 0
}

window_maximised :: proc(window: ^Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.MAXIMIZED) != 0
}

window_visible :: proc(window: ^Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.VISIBLE) != 0
}

set_window_opacity :: proc(window: ^Window, opacity: f32) {
	glfw.SetWindowOpacity(window.handle, clamp(opacity, 0, 1))
}

window_opacity :: proc(window: ^Window) -> f32 {
	return glfw.GetWindowOpacity(window.handle)
}

set_window_resizable :: proc(window: ^Window, resizable: bool) {
	glfw.SetWindowAttrib(window.handle, glfw.RESIZABLE, i32(resizable))
}

set_window_decorated :: proc(window: ^Window, decorated: bool) {
	glfw.SetWindowAttrib(window.handle, glfw.DECORATED, i32(decorated))
}

set_window_floating :: proc(window: ^Window, floating: bool) {
	glfw.SetWindowAttrib(window.handle, glfw.FLOATING, i32(floating))
}

// ===[ Monitors and Fullscreen ]===============================================

Monitor :: struct {
	handle: glfw.MonitorHandle,
}

#assert(size_of(Monitor) == size_of(glfw.MonitorHandle))

Video_Mode :: struct {
	size:         [2]i32,
	bits:         [3]i32,
	refresh_rate: i32,
}

#assert(size_of(Video_Mode) == size_of(glfw.VidMode))
#assert(offset_of(Video_Mode, bits) == offset_of(glfw.VidMode, red_bits))
#assert(offset_of(Video_Mode, refresh_rate) == offset_of(glfw.VidMode, refresh_rate))

Monitor_Proc :: #type proc(monitor: Monitor, event: Connection_Event)

monitors :: proc() -> []Monitor {
	return transmute([]Monitor)glfw.GetMonitors()
}

primary_monitor :: proc() -> (monitor: Monitor, found: bool) {
	monitor.handle = glfw.GetPrimaryMonitor()
	return monitor, monitor.handle != nil
}

monitor_name :: proc(monitor: Monitor) -> string {
	return glfw.GetMonitorName(monitor.handle)
}

monitor_position :: proc(monitor: Monitor) -> [2]i32 {
	x, y := glfw.GetMonitorPos(monitor.handle)
	return {x, y}
}

monitor_work_area :: proc(monitor: Monitor) -> (position, size: [2]i32) {
	position.x, position.y, size.x, size.y = glfw.GetMonitorWorkarea(monitor.handle)
	return
}

monitor_physical_size :: proc(monitor: Monitor) -> [2]i32 {
	width, height := glfw.GetMonitorPhysicalSize(monitor.handle)
	return {width, height}
}

monitor_content_scale :: proc(monitor: Monitor) -> [2]f32 {
	x, y := glfw.GetMonitorContentScale(monitor.handle)
	return {x, y}
}

video_mode :: proc(monitor: Monitor) -> Video_Mode {
	return (^Video_Mode)(glfw.GetVideoMode(monitor.handle))^
}

video_modes :: proc(monitor: Monitor) -> []Video_Mode {
	return transmute([]Video_Mode)glfw.GetVideoModes(monitor.handle)
}

set_monitor_callback :: proc(callback: Monitor_Proc) -> (previous: Monitor_Proc) {
	previous, monitor_callback = monitor_callback, callback
	return
}

@(private = "file")
monitor_callback: Monitor_Proc

@(private)
install_monitor_callback :: proc() {
	glfw.SetMonitorCallback(proc "c" (handle: glfw.MonitorHandle, event: i32) {
		context = runtime_context
		if monitor_callback != nil {
			monitor_callback({handle}, Connection_Event(event))
		}
	})
}

nearest_monitor :: proc(window: ^Window) -> (monitor: Monitor, found: bool) {
	if fullscreen, is_fullscreen := window_monitor(window); is_fullscreen {
		return fullscreen, true
	}
	if glfw.GetPlatform() == glfw.PLATFORM_WAYLAND {
		return primary_monitor()
	}
	x, y := glfw.GetWindowPos(window.handle)
	size := window_size(window)
	best: i64 = -1
	for candidate in monitors() {
		mode := video_mode(candidate)
		origin := monitor_position(candidate)
		overlap_x := max(min(x + size.x, origin.x + mode.size.x) - max(x, origin.x), 0)
		overlap_y := max(min(y + size.y, origin.y + mode.size.y) - max(y, origin.y), 0)
		if area := i64(overlap_x) * i64(overlap_y); area > best {
			best = area
			monitor = candidate
		}
	}
	if best <= 0 {
		return primary_monitor()
	}
	return monitor, true
}

window_monitor :: proc(window: ^Window) -> (monitor: Monitor, fullscreen: bool) {
	monitor.handle = glfw.GetWindowMonitor(window.handle)
	return monitor, monitor.handle != nil
}

set_window_fullscreen :: proc(window: ^Window, monitor: Monitor, mode: Maybe(Video_Mode) = nil) {
	assert(monitor.handle != nil, "set_window_fullscreen needs a monitor")
	if glfw.GetWindowMonitor(window.handle) == nil {
		data := window.data
		data.windowed_size = window_size(window)
		data.windowed_position = {}
		if glfw.GetPlatform() != glfw.PLATFORM_WAYLAND {
			data.windowed_position.x, data.windowed_position.y = glfw.GetWindowPos(window.handle)
		}
	}
	chosen := mode.? or_else video_mode(monitor)
	glfw.SetWindowMonitor(window.handle, monitor.handle, 0, 0, chosen.size.x, chosen.size.y, chosen.refresh_rate)
}

set_window_windowed :: proc(window: ^Window, position: Maybe([2]i32) = nil, size: Maybe([2]i32) = nil) {
	data := window.data
	placed_at := position.? or_else data.windowed_position
	placed_size := size.? or_else data.windowed_size
	if placed_size == {} {
		placed_size = window_size(window)
	}
	glfw.SetWindowMonitor(window.handle, nil, placed_at.x, placed_at.y, placed_size.x, placed_size.y, glfw.DONT_CARE)
}
