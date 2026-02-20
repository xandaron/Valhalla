#+build Linux, FreeBSD, OpenBSD, NetBSD
package ImGui_ImplGlfw

@(private = "package")
Data :: struct {
	using _: DataBase,

	// Platform specific
	// void*                       X11Module;
	// PFN_XInternAtom             XInternAtom;
	// PFN_XChangeProperty         XChangeProperty;
	// PFN_XChangeWindowAttributes XChangeWindowAttributes;
	// PFN_XFlush                  XFlush;
}

@(private = "package")
ViewportData :: distinct ViewportDataBase

@(private = "package")
SetWindowFloating :: proc(bd: ^Data, window: glfw.WindowHandle) {
	if glfw.GetPlatform() == GLFW_PLATFORM_X11 {
		display := glfw.GetX11Display()
		xwindow := glfw.GetX11Window(window)
		wm_type := bd.XInternAtom(display, "_NET_WM_WINDOW_TYPE", false)
		wm_type_dialog := bd.XInternAtom(display, "_NET_WM_WINDOW_TYPE_DIALOG", false)
		bd.XChangeProperty(
			display,
			xwindow,
			wm_type,
			XA_ATOM,
			32,
			PropModeReplace,
			/*(unsigned char*)&*/
			wm_type_dialog,
			1,
		)
		// XSetWindowAttributes attrs
		attrs.override_redirect = false
		bd.XChangeWindowAttributes(display, xwindow, CWOverrideRedirect, &attrs)
		bd.XFlush(display)
	}
	// #ifdef GLFW_EXPOSE_NATIVE_WAYLAND
	// FIXME: Help needed, see #8884, #8474 for discussions about this.
	// #endif // GLFW_EXPOSE_NATIVE_X11
}

