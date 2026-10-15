package Valhalla

import win32 "core:sys/windows"
import "vendor:glfw"

@(private = "file")
MODAL_LOOP_TIMER :: 1

@(private = "file")
MODAL_LOOP_INTERVAL_MS :: 8

@(private = "file")
glfw_window_proc: win32.WNDPROC

@(private = "file")
modal_loop_window_proc :: proc "system" (
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	switch msg {
	case win32.WM_ENTERSIZEMOVE:
		win32.SetTimer(hwnd, MODAL_LOOP_TIMER, MODAL_LOOP_INTERVAL_MS, nil)
	case win32.WM_EXITSIZEMOVE:
		win32.KillTimer(hwnd, MODAL_LOOP_TIMER)
	case win32.WM_TIMER:
		if wparam == MODAL_LOOP_TIMER {
			context = runtime_context
			request_frame()
			return 0
		}
	}
	return win32.CallWindowProcW(glfw_window_proc, hwnd, msg, wparam, lparam)
}

@(private)
install_modal_loop_timer :: proc(handle: glfw.WindowHandle) {
	previous := transmute(win32.WNDPROC)win32.SetWindowLongPtrW(
		glfw.GetWin32Window(handle),
		win32.GWLP_WNDPROC,
		transmute(win32.LONG_PTR)modal_loop_window_proc,
	)
	assert(glfw_window_proc == nil || glfw_window_proc == previous, "GLFW windows no longer share one window procedure")
	glfw_window_proc = previous
}
