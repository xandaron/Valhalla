#+build Windows
package ImGui_ImplGlfw

import "base:runtime"
import "core:sys/windows"

import imgui ".."


@(private = "package")
Data :: struct {
	using _:     DataBase,

	// Platform specific
	PrevWndProc: windows.WNDPROC,
}

@(private = "package")
ViewportData :: struct {
	using _:     ViewportDataBase,

	// Platform Data
	PrevWndProc: windows.WNDPROC,
}

// WndProc hook (declared here because we will need access to ImGui_ImplGlfw_ViewportData)
GetMouseSourceFromMessageExtraInfo :: proc() -> imgui.GuiMouseSource {
	extra_info := windows.GetMessageExtraInfo()
	if (extra_info & 0xFFFFFF80) == 0xFF515700 {
		return .Pen
	}
	if (extra_info & 0xFFFFFF80) == 0xFF515780 {
		return .TouchScreen
	}
	return .Mouse
}

WndProc :: proc "system" (
	hWnd: windows.HWND,
	msg: windows.UINT,
	wParam: windows.WPARAM,
	lParam: windows.LPARAM,
) -> windows.LRESULT {
	context = runtime.default_context()
	bd := transmute(^Data)windows.GetPropW(hWnd, "IMGUI_BACKEND_DATA")
	io := imgui.Gui_GetIOImGuiContextPtr(bd.Context)

	prev_wndproc := bd.PrevWndProc
	viewport := transmute(^imgui.GuiViewport)windows.GetPropW(hWnd, "IMGUI_VIEWPORT")
	if viewport != nil {
		if vd := transmute(^ViewportData)(viewport.PlatformUserData); vd != nil {
			prev_wndproc = vd.PrevWndProc
		}
	}

	switch msg {
	// GLFW doesn't allow to distinguish Mouse vs TouchScreen vs Pen.
	// Add support for Win32 (based on imgui_impl_win32), because we rely on _TouchScreen info to trickle inputs differently.
	case windows.WM_MOUSEMOVE,
	     windows.WM_NCMOUSEMOVE,
	     windows.WM_LBUTTONDOWN,
	     windows.WM_LBUTTONDBLCLK,
	     windows.WM_LBUTTONUP,
	     windows.WM_RBUTTONDOWN,
	     windows.WM_RBUTTONDBLCLK,
	     windows.WM_RBUTTONUP,
	     windows.WM_MBUTTONDOWN,
	     windows.WM_MBUTTONDBLCLK,
	     windows.WM_MBUTTONUP,
	     windows.WM_XBUTTONDOWN,
	     windows.WM_XBUTTONDBLCLK,
	     windows.WM_XBUTTONUP:
		imgui.GuiIO_AddMouseSourceEvent(io, GetMouseSourceFromMessageExtraInfo())
		break
	// We have submitted https://github.com/glfw/glfw/pull/1568 to allow GLFW to support "transparent inputs".
	// In the meanwhile we implement custom per-platform workarounds here (FIXME-VIEWPORT: Implement same work-around for Linux/OSX!)
	case windows.WM_NCHITTEST:
		// Let mouse pass-through the window. This will allow the backend to call io.AddMouseViewportEvent() properly (which is OPTIONAL).
		// The ImGuiViewportFlags_NoInputs flag is set while dragging a viewport, as want to detect the window behind the one we are dragging.
		// If you cannot easily access those viewport flags from your windowing/event code: you may manually synchronize its state e.g. in
		// your main loop after calling UpdatePlatformWindows(). Iterate all viewports/platform windows and pass the flag to your windowing system.
		if viewport != nil && .NoInputs in viewport.Flags {
			return windows.HTTRANSPARENT
		}
		break
	}
	return windows.CallWindowProcW(prev_wndproc, hWnd, msg, wParam, lParam)
}

