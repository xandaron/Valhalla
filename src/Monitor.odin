package Valhalla

import "vendor:glfw"

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

nearest_monitor :: proc(window: Window) -> (monitor: Monitor, found: bool) {
	if fullscreen, is_fullscreen := window_monitor(window); is_fullscreen {
		return fullscreen, true
	}
	position, err := window_position(window)
	if err != nil {
		return primary_monitor()
	}
	size := window_size(window)
	best: i64 = -1
	for candidate in monitors() {
		mode := video_mode(candidate)
		origin := monitor_position(candidate)
		overlap_x := max(min(position.x + size.x, origin.x + mode.size.x) - max(position.x, origin.x), 0)
		overlap_y := max(min(position.y + size.y, origin.y + mode.size.y) - max(position.y, origin.y), 0)
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

window_monitor :: proc(window: Window) -> (monitor: Monitor, fullscreen: bool) {
	monitor.handle = glfw.GetWindowMonitor(window.handle)
	return monitor, monitor.handle != nil
}

set_window_fullscreen :: proc(window: Window, monitor: Monitor, mode: Maybe(Video_Mode) = nil) {
	assert(monitor.handle != nil, "set_window_fullscreen needs a monitor")
	if _, fullscreen := window_monitor(window); !fullscreen {
		window.data.windowed_size = window_size(window)
		window.data.windowed_position, _ = window_position(window)
	}
	chosen := mode.? or_else video_mode(monitor)
	glfw.SetWindowMonitor(window.handle, monitor.handle, 0, 0, chosen.size.x, chosen.size.y, chosen.refresh_rate)
}

set_window_windowed :: proc(window: Window, position: Maybe([2]i32) = nil, size: Maybe([2]i32) = nil) {
	data := window.data
	placed_at := position.? or_else data.windowed_position
	placed_size := size.? or_else data.windowed_size
	if placed_size == {} {
		placed_size = window_size(window)
	}
	glfw.SetWindowMonitor(window.handle, nil, placed_at.x, placed_at.y, placed_size.x, placed_size.y, glfw.DONT_CARE)
}
