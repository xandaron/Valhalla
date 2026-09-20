package Valhalla

import "core:bytes"
import "vendor:glfw"


cursorRay :: proc(cursor: Vec2) -> (origin, direction: Vec3, ok: bool) {
	ndc, inside := cursorToRenderNDC(&globals.graphicsData, cursor)
	if !inside {
		return
	}

	scene := &globals.scenes[globals.activeScene]
	camera := scene.cameras[scene.activeCamera]
	inverseViewProjection := inverse(projection(camera) * view(camera))

	near := inverseViewProjection * Vec4{ndc.x, ndc.y, 0, 1}
	far := inverseViewProjection * Vec4{ndc.x, ndc.y, 1, 1}
	near /= near.w
	far /= far.w

	return near.xyz, normalize(far.xyz - near.xyz), true
}

pick :: proc(scene: ^Scene, origin, direction: Vec3) -> (item: InspectorItem, hit: bool) {
	rayHitsBox :: proc(origin, direction: Vec3, box: AABB) -> (hit: bool, distance: f32) {
		t1 := (box.min - origin) / direction
		t2 := (box.max - origin) / direction
		tmin := minVec3(t1, t2)
		tmax := maxVec3(t1, t2)
		enter := max(tmin.x, tmin.y, tmin.z)
		exit := min(tmax.x, tmax.y, tmax.z)
		return exit >= max(enter, 0), max(enter, 0)
	}

	rayHitsSphere :: proc(origin, direction, centre: Vec3, radius: f32) -> (hit: bool, distance: f32) {
		offset := origin - centre
		b := dot(offset, direction)
		discriminant := b * b - (dot(offset, offset) - radius * radius)
		if discriminant < 0 {
			return false, 0
		}
		root := sqrt(discriminant)
		distance = -b - root
		if distance < 0 {
			distance = -b + root
		}
		return distance >= 0, distance
	}

	closest := max(f32)
	for &object, idx in scene.objects {
		toLocal := inverse(objectTransform(scene, &object))
		localOrigin := (toLocal * Vec4{origin.x, origin.y, origin.z, 1}).xyz
		localDirection := (toLocal * Vec4{direction.x, direction.y, direction.z, 0}).xyz
		for &mesh in scene.models[object.modelIdx].meshes {
			if boxHit, distance := rayHitsBox(localOrigin, localDirection, mesh.boundingBox);
			   boxHit && distance < closest {
				closest = distance
				item = {.Object, u32(idx)}
				hit = true
			}
		}
	}

	settings := &globals.graphicsData.settings
	if settings.showLightGizmos {
		for &light, idx in scene.lights {
			if sphereHit, distance := rayHitsSphere(
				origin,
				direction,
				light.position,
				settings.lightGizmoRadius,
			); sphereHit && distance <= closest {
				closest = distance
				item = {.Light, u32(idx)}
				hit = true
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

	if e, ok := event.(KeyEvent); ok && e.key == glfw.KEY_F1 && e.action == glfw.PRESS {
		globals.uiData.hidden = !globals.uiData.hidden
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
		if e.button == glfw.MOUSE_BUTTON_LEFT &&
		   e.action == glfw.PRESS &&
		   !mouseMode &&
		   !globals.uiData.gizmo.hot {
			if origin, direction, ok := cursorRay(mousePos); ok {
				if item, hit := pick(&globals.scenes[globals.activeScene], origin, direction); hit {
					inspect(item)
				}
			}
		}
		if e.button == glfw.MOUSE_BUTTON_MIDDLE && e.action == glfw.PRESS {
			mouseMode = !mouseMode
			setFlyMode(mouseMode)
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
		case glfw.KEY_R:
			if e.mods & glfw.MOD_CONTROL != 0 {
				setGizmoMode(.Rotate)
			}
		case glfw.KEY_D:
			if e.mods & glfw.MOD_CONTROL != 0 {
				setGizmoMode(.Translate)
			}
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
