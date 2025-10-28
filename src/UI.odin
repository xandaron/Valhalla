package Valhalla

import "../imgui"
import tinyfd "../tinyfiledialogs"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "vendor:glfw"

drawImgui :: proc(graphicsContext: ^GraphicsContext) {
	toCstring :: #force_inline proc(str: string, allocator := context.temp_allocator) -> cstring {
		return strings.clone_to_cstring(str, allocator = allocator)
	}

	if globals.showMetrics {
		imgui.SetNextWindowBgAlpha(1.0)
		imgui.ShowMetricsWindow()
	}

	if globals.showDemo {
		imgui.SetNextWindowBgAlpha(1.0)
		imgui.ShowDemoWindow()
	}

	imgui.SetNextWindowBgAlpha(1.0)
	if imgui.Begin("Scene Editor", nil, {.MenuBar}) {
		scene := &globals.scenes[globals.activeScene]
		if imgui.BeginMenuBar() {
			if imgui.BeginMenu("File") {
				if imgui.MenuItem("Open Scene", enabled = false) {
					// TODO: Open file dialog
					// and load scene
				}

				if imgui.MenuItem("Save", enabled = false) {
					// TODO: Save current scene
					// Open file dialog if no path exists
				}

				if imgui.MenuItem("Save As...", enabled = false) {
					// TODO: Open file dialog and save scene
				}

				if imgui.MenuItem("Close", enabled = false) {
					// TODO: Close current scene
				}

				imgui.SeparatorText("Assets")
				if imgui.BeginMenu("Import") {
					if imgui.MenuItem("Model", enabled = false) {
						// TODO: Open file dialog and import model
					}

					if imgui.MenuItem("Texture", enabled = false) {
						// TODO: Open file dialog and import texture
					}
					imgui.EndMenu()
				}
				imgui.EndMenu()
			}
			imgui.EndMenuBar()
		}

		if imgui.CollapsingHeader("Scene Settings") {
			str: cstring = strings.clone_to_cstring("None0Narkowicz ACES0", context.temp_allocator)
			str_buff := transmute([^]u8)(str)
			str_buff[len("None")] = 0
			str_buff[len("None0Narkowicz ACES")] = 0
			if imgui.DragFloat("Contrast", &graphicsContext.contrast, 0.01) ||
			   imgui.DragFloat("Brightness", &graphicsContext.brightness, 0.01) ||
			   imgui.DragFloat("Saturation", &graphicsContext.saturation, 0.01) ||
			   imgui.DragFloat("Exposure", &graphicsContext.exposure, 0.01) ||
			   imgui.Combo("Tonemapper", transmute(^i32)(&graphicsContext.tonemapper), str) ||
			   imgui.DragFloat("Gamma", &graphicsContext.gamma, 0.01) {
				if err := updateSceneBuffers(graphicsContext, scene); err != nil {
					logf(.Error, "Failed to update scene buffers: %v", err)
					panic("Failed to update scene buffers")
				}
			}
		}

		if imgui.CollapsingHeader("Scene") {
			if imgui.DragFloat("Ambient light", &scene.ambientLight, 0.01, 0, 1) ||
			   imgui.DragFloat4("Clear colour", &scene.clearColour, 0.01, 0, 1) {
				if err := updateSceneBuffers(graphicsContext, scene); err != nil {
					logf(.Error, "Failed to update scene buffers: %v", err)
					panic("Failed to update scene buffers")
				}
			}
		}

		if imgui.CollapsingHeader("Objects") {
			for &object, objectIdx in scene.objects {
				if imgui.TreeNode(toCstring(object.name)) {
					imgui.DragFloat3("Position", &object.position, 0.1)

					x, y, z := quatToEuler(object.rotation)
					rotation := Vec3{degrees(x), degrees(y), degrees(z)}
					if imgui.DragFloat3("Rotation", &rotation, 0.1) {
						object.rotation = quatFromEuler(
							radians(rotation.x),
							radians(rotation.y),
							radians(rotation.z),
							.XYZ,
						)
					}
					imgui.DragFloat3("Scale", &object.scale, 0.1)

					imgui.SeparatorText("Animation")
					animationData := &object.animation
					if animationData.idx >= 0 &&
					   animationData.idx < i32(len(scene.models[object.modelIdx].animations)) {
						animation := &scene.models[object.modelIdx].animations[animationData.idx]
						if imgui.BeginCombo("Animation Clip", toCstring(animation.name)) {
							for &animation, animationIdx in scene.models[object.modelIdx].animations {
								if i32(animationIdx) == animationData.idx {
									continue
								}

								if imgui.Selectable(toCstring(animation.name)) {
									animationData.idx = i32(animationIdx)
									animationData.timer = 0
								}
							}
						}
					}

					imgui.Checkbox("Playing", &animationData.playing)

					timer := f32(animationData.timer)
					if imgui.DragFloat("Animation time", &timer, 0.01) {
						animationData.timer = f64(timer)
					}

					if imgui.BeginCombo(
						"Animation Behavior",
						toCstring(fmt.tprintf("%v", animationData.end.behavior)),
					) {
						for behavior in AnimationBehavior {
							if behavior == animationData.end.behavior {
								continue
							}

							if imgui.Selectable(toCstring(fmt.tprintf("%v", behavior))) {
								animationData.end.behavior = behavior
							}
						}
						imgui.EndCombo()
					}

					if imgui.BeginCombo("Model", toCstring(scene.models[object.modelIdx].name)) {
						for modelIdx in 0 ..< len(scene.models) {
							if u32(modelIdx) == object.modelIdx {
								continue
							}

							model := &scene.models[modelIdx]
							if imgui.Selectable(toCstring(model.name)) {
								changeModel(scene, u32(objectIdx), u32(modelIdx))
								if err := updateSceneBuffers(graphicsContext, scene); err != nil {
									logf(.Error, "Failed to update scene buffers: %v", err)
									panic("Failed to update scene buffers")
								}
								if err := updateCommandBuffers(graphicsContext, scene);
								   err != nil {
									logf(.Error, "Failed to update command buffers: %v", err)
									panic("Failed to update command buffers")
								}
							}
						}
						imgui.EndCombo()
					}

					for mesh, meshIdx in scene.models[object.modelIdx].meshes {
						if imgui.TreeNode(toCstring(mesh.name)) {
							buf: [10]u8
							num_str := strconv.write_uint(
								buf[:],
								u64(object.textureIdxs[meshIdx][TextureIndex.ALBEDO]),
								10,
							)
							if imgui.BeginCombo(
								"Albedo",
								toCstring(fmt.tprintf("Texture %s", transmute(cstring)(&buf[0]))),
							) {
								for textureIdx in 0 ..< scene.textureCount {
									if object.textureIdxs[meshIdx][TextureIndex.ALBEDO] ==
									   u32(textureIdx) {
										continue
									}

									buf: [10]u8
									num_str := strconv.write_uint(buf[:], u64(textureIdx), 10)
									if imgui.Selectable(
										toCstring(
											fmt.tprintf("Texture %s", transmute(cstring)(&buf[0])),
										),
									) {
										object.textureIdxs[meshIdx][TextureIndex.ALBEDO] = u32(
											textureIdx,
										)
										if err := updateSceneBuffers(graphicsContext, scene);
										   err != nil {
											logf(.Error, "Failed to update scene buffers: %v", err)
											panic("Failed to update scene buffers")
										}
									}
								}
								imgui.EndCombo()
							}

							num_str = strconv.write_uint(
								buf[:],
								u64(object.textureIdxs[meshIdx][TextureIndex.NORMAL_MAP]),
								10,
							)
							if imgui.BeginCombo(
								"Normal Map",
								toCstring(fmt.tprintf("Texture %s", transmute(cstring)(&buf[0]))),
							) {
								for textureIdx in 0 ..< scene.textureCount {
									if object.textureIdxs[meshIdx][TextureIndex.NORMAL_MAP] ==
									   u32(textureIdx) {
										continue
									}
									buf: [10]u8
									num_str := strconv.write_uint(buf[:], u64(textureIdx), 10)
									if imgui.Selectable(
										toCstring(
											fmt.tprintf("Texture %s", transmute(cstring)(&buf[0])),
										),
									) {
										object.textureIdxs[meshIdx][TextureIndex.NORMAL_MAP] = u32(
											textureIdx,
										)
										if err := updateSceneBuffers(graphicsContext, scene);
										   err != nil {
											logf(.Error, "Failed to update scene buffers: %v", err)
											panic("Failed to update scene buffers")
										}
									}
								}
								imgui.EndCombo()
							}
							imgui.TreePop()
						}
					}
					imgui.TreePop()
				}
			}
		}

		if imgui.CollapsingHeader("Cameras") {
			for &camera, cameraIdx in scene.cameras {
				if imgui.TreeNode(toCstring(camera.name)) {
					if imgui.BeginCombo("Mode", toCstring(fmt.tprintf("%v", camera.mode))) {
						for mode in CameraMode {
							if mode == camera.mode {
								continue
							}

							if imgui.Selectable(toCstring(fmt.tprintf("%v", mode))) {
								camera.mode = mode
							}
						}
						imgui.EndCombo()
					}

					imgui.DragFloat3("Eye", &camera.eye, 0.1)
					imgui.DragFloat3("Center", &camera.center, 0.1)
					imgui.DragFloat3("Up", &camera.up, 0.1)

					imgui.DragFloat("FOV", &camera.fov, 0.1)
					imgui.DragFloat("Near Plane", &camera.near, 0.1)
					imgui.DragFloat("Far Plane", &camera.far, 0.1)

					imgui.TreePop()
				}
			}
		}

		if imgui.CollapsingHeader("Lights") {
			for &light, lightIdx in scene.lights {
				if imgui.TreeNode(toCstring(light.name)) {
					imgui.DragFloat3("Position", &light.position, 0.1)
					imgui.DragFloat3("Colour", &light.colour, 0.01, 0, 1)
					imgui.DragFloat("Brightness", &light.brightness, 0.1)
					imgui.DragFloat("Dropoff", &light.dropoff, 0.1)

					imgui.TreePop()
				}
			}
		}

		if imgui.CollapsingHeader("Models") {
			for &model, modelIdx in scene.models {
				if imgui.TreeNode(toCstring(model.name)) {
					imgui.DragFloat3("Position", &model.position, 0.1)

					x, y, z := quatToEuler(model.rotation)
					rotation := Vec3{degrees(x), degrees(y), degrees(z)}
					if imgui.DragFloat3("Rotation", &rotation, 0.1) {
						model.rotation = quatFromEuler(
							radians(rotation.x),
							radians(rotation.y),
							radians(rotation.z),
							.XYZ,
						)
					}

					imgui.DragFloat3("Scale", &model.scale, 0.1)
					imgui.TreePop()
				}
			}
		}
	}
	imgui.End()
}

mouseButtonCallback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = globals.runtimeContext

	if globals.inputLock {
		return
	}

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
	newPos: Vec2 = {f32(xpos), f32(ypos)}
	mouseDelta.xy += newPos - mousePos
	mousePos = newPos
}

scrollCallback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	mouseDelta.z = f32(yoffset)
}

keyCallback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
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
			globals.showDemo = !globals.showDemo
		}
	case glfw.KEY_M:
		if action == glfw.PRESS {
			globals.showMetrics = !globals.showMetrics
		}
	}
}
