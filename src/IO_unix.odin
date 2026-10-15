#+build linux, freebsd, openbsd, netbsd
package Valhalla

import "vendor:glfw"

// X11 and Wayland keep glfwPollEvents returning through a resize, so the refresh and framebuffer size callbacks already drive every frame.
@(private)
install_modal_loop_timer :: proc(handle: glfw.WindowHandle) {}
