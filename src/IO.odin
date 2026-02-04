package Valhalla

import "vendor:glfw"

mouseButtonCallback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	if globals.uiData.lockInput {
		return
	}

	context = globals.runtimeContext

	if button == glfw.MOUSE_BUTTON_MIDDLE && action == glfw.PRESS {
		if mouseMode {
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL)
			mouseMode = false
		} else {
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)
			mouseMode = true
		}
		return
	}
}

cursorPosCallback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	if globals.uiData.lockInput {
		return
	}

	newPos: Vec2 = {f32(xpos), f32(ypos)}
	mouseDelta.xy += newPos - mousePos
	mousePos = newPos
}

scrollCallback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	if globals.uiData.lockInput {
		return
	}

	mouseDelta.z = f32(yoffset)
}

keyCallback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if globals.uiData.lockInput {
		return
	}

	context = globals.runtimeContext

	switch key {
	case glfw.KEY_ESCAPE:
		glfw.SetWindowShouldClose(window, glfw.TRUE)
	case glfw.KEY_P:
		if action == glfw.PRESS do globals.paused = !globals.paused
	case glfw.KEY_D:
		if action == glfw.PRESS {
			cameraMove.x += 1
		} else if action == glfw.RELEASE {
			cameraMove.x -= 1
		}
	case glfw.KEY_A:
		if action == glfw.PRESS {
			cameraMove.x -= 1
		} else if action == glfw.RELEASE {
			cameraMove.x += 1
		}
	case glfw.KEY_SPACE:
		if action == glfw.PRESS {
			cameraMove.y += 1
		} else if action == glfw.RELEASE {
			cameraMove.y -= 1
		}
	case glfw.KEY_LEFT_SHIFT:
		if action == glfw.PRESS {
			cameraMove.y -= 1
		} else if action == glfw.RELEASE {
			cameraMove.y += 1
		}
	case glfw.KEY_W:
		if action == glfw.PRESS {
			cameraMove.z += 1
		} else if action == glfw.RELEASE {
			cameraMove.z -= 1
		}
	case glfw.KEY_S:
		if action == glfw.PRESS {
			cameraMove.z -= 1
		} else if action == glfw.RELEASE {
			cameraMove.z += 1
		}
	case glfw.KEY_H:
		if action == glfw.PRESS {
			globals.uiData.showDemo = !globals.uiData.showDemo
		}
	case glfw.KEY_M:
		if action == glfw.PRESS {
			globals.uiData.showMetrics = !globals.uiData.showMetrics
		}
	}
}

