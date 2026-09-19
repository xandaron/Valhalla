package Valhalla

import "core:bytes"
import "vendor:glfw"


screenPositionToWorldRay :: proc(pos: Vec2) -> (origin: Vec3, direction: Vec3) {
	scene := &globals.scenes[globals.activeScene]
	camera := &scene.cameras[scene.activeCamera]

	width, height := windowSize(&globals.graphicsData)

	vpPos := pos / Vec2{f32(width), f32(height)}
	vpPos = vpPos * 2 - 1

	proj := perspective(radians(camera.fov), f32(width) / f32(height), 0.1, 100)
	view := lookAt(camera.eye, camera.center, camera.up)
	ivp := inverse(proj * view)

	ndcNear := Vec4{vpPos.x, vpPos.y, 0, 1}
	ndcFar := Vec4{vpPos.x, vpPos.y, 1, 1}

	worldNear := ivp * ndcNear
	worldFar := ivp * ndcFar

	worldNear /= worldNear.w
	worldFar /= worldFar.w

	origin = worldNear.xyz
	direction = normalize(worldFar.xyz - worldNear.xyz)

	return
}

castRay :: proc(rayOrigin, rayDirection: Vec3, scene: ^Scene) -> (object: ^Object, distance: f32) {
	rayIntersects :: proc(
		rayOrigin, rayDirection: Vec3,
		boundingBox: ^AABB,
	) -> (
		hit: bool,
		distance: f32,
	) {
		t1 := (boundingBox.min - rayOrigin) / rayDirection
		t2 := (boundingBox.max - rayOrigin) / rayDirection

		tmin := minVec3(t1, t2)
		tmax := maxVec3(t1, t2)

		mint := max(tmin.x, max(tmin.y, tmin.z))
		maxt := min(tmax.x, min(tmax.y, tmax.z))

		return maxt >= mint, mint
	}

	object = nil

	distance = max(f32)
	for &obj in scene.objects {
		model := scene.models[obj.modelIdx]
		for &mesh in model.meshes {
			transform :=
				translate(obj.position + model.position) *
				quatToMat4(obj.rotation * model.rotation) *
				scale(obj.scale * model.scale)
			corners: [8]Vec3 = {
				mesh.boundingBox.min,
				{mesh.boundingBox.min.x, mesh.boundingBox.min.y, mesh.boundingBox.max.z},
				{mesh.boundingBox.min.x, mesh.boundingBox.max.y, mesh.boundingBox.min.z},
				{mesh.boundingBox.min.x, mesh.boundingBox.max.y, mesh.boundingBox.max.z},
				{mesh.boundingBox.max.x, mesh.boundingBox.min.y, mesh.boundingBox.min.z},
				{mesh.boundingBox.max.x, mesh.boundingBox.min.y, mesh.boundingBox.max.z},
				{mesh.boundingBox.max.x, mesh.boundingBox.max.y, mesh.boundingBox.min.z},
				mesh.boundingBox.max,
			}
			for i in 0 ..< 8 {
				corners[i] = (transform * Vec4{corners[i].x, corners[i].y, corners[i].z, 1}).xyz
			}
			newMin := corners[0]
			newMax := corners[0]
			for i in 1 ..< 8 {
				newMin = minVec3(newMin, corners[i])
				newMax = maxVec3(newMax, corners[i])
			}
			boundingBox := AABB {
				min = newMin,
				max = newMax,
			}
			intersects, dist := rayIntersects(rayOrigin, rayDirection, &boundingBox)
			if intersects && dist < distance {
				distance = dist
				object = &obj
			}
		}
	}

	return
}

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

InputDevice :: enum {
	None,
	Mouse,
	Keyboard,
}

@(private = "file")
inputDevice :: proc(event: InputEvent) -> InputDevice {
	switch _ in event {
	case KeyEvent, CharEvent:
		return .Keyboard
	case MouseButtonEvent, CursorPosEvent, ScrollEvent:
		return .Mouse
	case CursorEnterEvent, FocusEvent:
	}
	return .None
}

handleInput :: proc(event: InputEvent) {
	imguiInputEvent(&globals.graphicsData, event)

	if e, ok := event.(KeyEvent);
	   ok && e.key == glfw.KEY_Q && e.action == glfw.PRESS && e.mods & glfw.MOD_CONTROL != 0 {
		requestClose(&globals.graphicsData)
		return
	}

	consumed: bool
	switch inputDevice(event) {
	case .None:
		return
	case .Mouse:
		consumed = imguiWantsMouse(&globals.graphicsData)
	case .Keyboard:
		consumed = imguiWantsKeyboard(&globals.graphicsData)
	}

	if e, ok := event.(CursorPosEvent); ok {
		newPos: Vec2 = {f32(e.x), f32(e.y)}
		if mouseMode && !consumed {
			mouseDelta.xy += newPos - mousePos
		}
		mousePos = newPos
		return
	}

	if consumed {
		return
	}

	window := globals.graphicsData.window

	#partial switch e in event {
	case MouseButtonEvent:
		if e.button == glfw.MOUSE_BUTTON_MIDDLE && e.action == glfw.PRESS {
			mouseMode = !mouseMode
			glfw.SetInputMode(window, glfw.CURSOR, mouseMode ? glfw.CURSOR_DISABLED : glfw.CURSOR_NORMAL)
			x, y := glfw.GetCursorPos(window)
			mousePos = {f32(x), f32(y)}
			mouseDelta = {0, 0, 0}
		}
	case ScrollEvent:
		mouseDelta.z = f32(e.y)
	case KeyEvent:
		if e.action != glfw.PRESS {
			return
		}
		switch e.key {
		case glfw.KEY_P:
			globals.paused = !globals.paused
		case glfw.KEY_H:
			globals.uiData.showDemo = !globals.uiData.showDemo
		case glfw.KEY_M:
			globals.uiData.showMetrics = !globals.uiData.showMetrics
		}
	}
}

keyCallback: GLFWKeyCallback : proc "c" (window: WindowHandle, key, scancode, action, mods: i32) {
	context = globals.runtimeContext
	handleInput(KeyEvent{key, scancode, action, mods})
}

charCallback: GLFWCharCallback : proc "c" (window: WindowHandle, codepoint: rune) {
	context = globals.runtimeContext
	handleInput(CharEvent{codepoint})
}

mouseButtonCallback: GLFWMouseButtonCallback : proc "c" (
	window: WindowHandle,
	button, action, mods: i32,
) {
	context = globals.runtimeContext
	handleInput(MouseButtonEvent{button, action, mods})
}

cursorPosCallback: GLFWCursorPosCallback : proc "c" (window: WindowHandle, xpos, ypos: f64) {
	context = globals.runtimeContext
	handleInput(CursorPosEvent{xpos, ypos})
}

scrollCallback: GLFWScrollCallback : proc "c" (window: WindowHandle, xoffset, yoffset: f64) {
	context = globals.runtimeContext
	handleInput(ScrollEvent{xoffset, yoffset})
}

cursorEnterCallback: GLFWCursorEnterCallback : proc "c" (window: WindowHandle, entered: i32) {
	context = globals.runtimeContext
	handleInput(CursorEnterEvent{entered != 0})
}

windowFocusCallback: GLFWWindowFocusCallback : proc "c" (window: WindowHandle, focused: i32) {
	context = globals.runtimeContext
	handleInput(FocusEvent{focused != 0})
}

windowRefreshCallback: GLFWWindowRefreshCallback : proc "c" (window: WindowHandle) {
	context = globals.runtimeContext
	tickFrame()
}

framebufferSizeCallback: GLFWFramebufferSizeCallback : proc "c" (
	window: WindowHandle,
	width, height: i32,
) {
	context = globals.runtimeContext
	if width == 0 || height == 0 {
		return
	}
	tickFrame()
}
