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

mouseButtonCallback: GLFWMouseButtonCallback : proc "c" (
	window: WindowHandle,
	button, action, mods: i32,
) {
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

cursorPosCallback: GLFWCursorPosCallback : proc "c" (window: WindowHandle, xpos, ypos: f64) {
	if globals.uiData.lockInput {
		return
	}

	newPos: Vec2 = {f32(xpos), f32(ypos)}
	mouseDelta.xy += newPos - mousePos
	mousePos = newPos
}

scrollCallback: GLFWScrollCallback : proc "c" (window: WindowHandle, xoffset, yoffset: f64) {
	if globals.uiData.lockInput {
		return
	}

	mouseDelta.z = f32(yoffset)
}

keyCallback: GLFWKeyCallback : proc "c" (window: WindowHandle, key, scancode, action, mods: i32) {
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
			globals.uiData.showUI = !globals.uiData.showUI
		}
	case glfw.KEY_M:
		if action == glfw.PRESS {
			globals.uiData.showMetrics = !globals.uiData.showMetrics
		}
	case glfw.KEY_R:
		if action == glfw.PRESS {
			shaders: [2][]byte
			shaders[0], _ = compileShader("./shaders/Scene.slang", "vert", .VERTEX)
			shaders[1], _ = compileShader("./shaders/Scene.slang", "norm", .FRAGMENT)
			updatePipelineShaders(&globals.graphicsData, .Scene, shaders[:])
			delete(shaders[0])
			delete(shaders[1])
		}
	}
}

