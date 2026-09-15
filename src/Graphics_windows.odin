package Valhalla

import win32 "core:sys/windows"
import "vendor:glfw"

@(private = "file")
MODAL_LOOP_TIMER :: 1

@(private = "file")
originalWindowProc: win32.WNDPROC

@(private = "file")
modalLoopWindowProc :: proc "system" (
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	switch msg {
	case win32.WM_ENTERSIZEMOVE:
		win32.SetTimer(hwnd, MODAL_LOOP_TIMER, 8, nil)
	case win32.WM_EXITSIZEMOVE:
		win32.KillTimer(hwnd, MODAL_LOOP_TIMER)
	case win32.WM_TIMER:
		if wparam == MODAL_LOOP_TIMER {
			context = globals.runtimeContext
			tickFrame()
			return 0
		}
	}
	return win32.CallWindowProcW(originalWindowProc, hwnd, msg, wparam, lparam)
}

@(private)
installModalLoopTimer :: proc(window: WindowHandle) {
	previous := win32.SetWindowLongPtrW(
		glfw.GetWin32Window(window),
		win32.GWLP_WNDPROC,
		win32.LONG_PTR(uintptr(rawptr(modalLoopWindowProc))),
	)
	originalWindowProc = win32.WNDPROC(rawptr(uintptr(previous)))
}
