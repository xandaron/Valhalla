package Valhalla

import "base:runtime"

Callbacks :: struct {
	frame: proc(),
	input: proc(event: InputEvent),
	ui:    proc(graphicsData: ^GraphicsData),
}

@(private)
runtimeContext: runtime.Context

@(private)
callbacks: Callbacks

@(private)
configPath: string

@(private)
activeGraphics: ^GraphicsData

KeyEvent :: struct {
	key, scancode, action, mods: i32,
}

CharEvent :: struct {
	codepoint: rune,
}

MouseButtonEvent :: struct {
	button, action, mods: i32,
}

CursorPosEvent :: struct {
	x, y: f64,
}

ScrollEvent :: struct {
	x, y: f64,
}

CursorEnterEvent :: struct {
	entered: bool,
}

FocusEvent :: struct {
	focused: bool,
}

InputEvent :: union {
	KeyEvent,
	CharEvent,
	MouseButtonEvent,
	CursorPosEvent,
	ScrollEvent,
	CursorEnterEvent,
	FocusEvent,
}

handleInput :: proc(event: InputEvent) {
	imguiInputEvent(activeGraphics, event)
	if callbacks.input != nil {
		callbacks.input(event)
	}
}

@(private)
requestFrame :: proc() {
	if callbacks.frame != nil {
		callbacks.frame()
	}
}

keyCallback: GLFWKeyCallback : proc "c" (window: WindowHandle, key, scancode, action, mods: i32) {
	context = runtimeContext
	handleInput(KeyEvent{key, scancode, action, mods})
}

charCallback: GLFWCharCallback : proc "c" (window: WindowHandle, codepoint: rune) {
	context = runtimeContext
	handleInput(CharEvent{codepoint})
}

mouseButtonCallback: GLFWMouseButtonCallback : proc "c" (
	window: WindowHandle,
	button, action, mods: i32,
) {
	context = runtimeContext
	handleInput(MouseButtonEvent{button, action, mods})
}

cursorPosCallback: GLFWCursorPosCallback : proc "c" (window: WindowHandle, xpos, ypos: f64) {
	context = runtimeContext
	handleInput(CursorPosEvent{xpos, ypos})
}

scrollCallback: GLFWScrollCallback : proc "c" (window: WindowHandle, xoffset, yoffset: f64) {
	context = runtimeContext
	handleInput(ScrollEvent{xoffset, yoffset})
}

cursorEnterCallback: GLFWCursorEnterCallback : proc "c" (window: WindowHandle, entered: i32) {
	context = runtimeContext
	handleInput(CursorEnterEvent{entered != 0})
}

windowFocusCallback: GLFWWindowFocusCallback : proc "c" (window: WindowHandle, focused: i32) {
	context = runtimeContext
	handleInput(FocusEvent{focused != 0})
}

windowRefreshCallback: GLFWWindowRefreshCallback : proc "c" (window: WindowHandle) {
	context = runtimeContext
	requestFrame()
}

framebufferSizeCallback: GLFWFramebufferSizeCallback : proc "c" (
	window: WindowHandle,
	width, height: i32,
) {
	context = runtimeContext
	if width == 0 || height == 0 {
		return
	}
	requestFrame()
}
