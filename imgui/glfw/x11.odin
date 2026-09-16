#+build Linux, FreeBSD, OpenBSD
package ImGui_ImplGlfw

import x11 "vendor:x11/xlib"


@(private = "package")
SetWindowFloating :: proc(bd: ^Data, window: glfw.WindowHandle) {
	if glfw.GetPlatform() == GLFW_PLATFORM_X11 {
		display := glfw.GetX11Display()
		xwindow := glfw.GetX11Window(window)
		wm_type := x11.InternAtom(display, "_NET_WM_WINDOW_TYPE", false)
		wm_type_dialog := x11.InternAtom(display, "_NET_WM_WINDOW_TYPE_DIALOG", false)
		x11.ChangeProperty(
			display,
			xwindow,
			x11.InternAtom(display, "_NET_WM_WINDOW_TYPE", false),
			x11.XA_ATOM,
			32,
			x11.PropModeReplace,
			wm_type_dialog,
			1,
		)

		arrts: x11.SetWindowAttributes
		attrs.override_redirect = false
		x11.ChangeWindowAttributes(display, xwindow, x11.CWOverrideRedirect, &attrs)
		x11.Flush(display)
	}
	// #ifdef GLFW_EXPOSE_NATIVE_WAYLAND
	// FIXME: Help needed, see #8884, #8474 for discussions about this.
	// #endif // GLFW_EXPOSE_NATIVE_WAYLAND
}

