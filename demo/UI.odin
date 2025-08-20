package Demo

import "../imgui"
import valhalla "../valhalla"
import "core:fmt"
import "core:log"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import tinyfd "tinyfiledialogs"
import "vendor:glfw"

drawUI :: proc(graphicsContext: ^valhalla.GraphicsContext) {
	constructSceneEditor :: proc(graphicsContext: ^valhalla.GraphicsContext) {
		scene := &globals.scene
		if imgui.BeginMenuBar() {
			constructMenuBar(graphicsContext)
			imgui.EndMenuBar()
		}

		imgui.Text(fmt.ctprintf("FPS: {:.2f}", globals.fps))

		if imgui.Button("Toggle Time", {100, 20}) {
			globals.paused = !globals.paused
		}

		// These all have to be seperate otherwise the ui will gain and loose options as the user interacts with them
		if imgui.DragFloat("Contrast", &graphicsContext.contrast, 0.01) {
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}
		if imgui.DragFloat("Brightness", &graphicsContext.brightness, 0.01) {
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}
		if imgui.DragFloat("Saturation", &graphicsContext.saturation, 0.01) {
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}
		if imgui.DragFloat("Exposure", &graphicsContext.exposure, 0.01) {
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}
		if imgui.DragFloat("Gamma", &graphicsContext.gamma, 0.01) {
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}

		cc := [4]i32 {
			i32(scene.graphicsData.clearColour.x * 255),
			i32(scene.graphicsData.clearColour.y * 255),
			i32(scene.graphicsData.clearColour.z * 255),
			i32(scene.graphicsData.clearColour.w * 255),
		}
		if imgui.DragInt4("Clear Colour", &cc) {
			scene.graphicsData.clearColour = Vec4 {
				f32(cc.x) / 255,
				f32(cc.y) / 255,
				f32(cc.z) / 255,
				f32(cc.w) / 255,
			}
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}
		if imgui.DragFloat("Ambient Light", &scene.graphicsData.ambientLight, 0.001) {
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}
		if imgui.Checkbox("Draw Light Sources", &graphicsContext.drawLights) {
			err := valhalla.updateCommandBuffers(graphicsContext)
			if err != nil {
				panic(fmt.tprintf("Failed to update command buffers: %v", err))
			}
		}

		if imgui.CollapsingHeader("Shaders") {
			constructShaderEditor(graphicsContext)
		}

		if imgui.CollapsingHeader("Cameras") {
			constructCamerasHeader(graphicsContext)
			if imgui.Button("Add Camera") {
				count: u32 = 0
				for &camera in scene.cameras {
					if strings.compare(string(camera.name)[:len(camera.name) - 3], "Camera") == 0 {
						count += 1
					}
				}
				newCamera: Camera = {
					name   = fmt.aprintf("Camera{:3d}", count),
					eye    = {0.0, 2.0, -4.0},
					center = {0.0, 0.0, 0.0},
					up     = {0.0, 1.0, 0.0},
					fov    = 45.0,
					mode   = .PERSPECTIVE,
				}
				append(&scene.cameras, newCamera)
			}
		}

		if imgui.CollapsingHeader("Lights") {
			constructLightsHeader(graphicsContext)
			if imgui.Button("Add Light") {
				count: u32 = 0
				for &light in scene.pointLights {
					if strings.compare(string(light.name)[:len(light.name) - 3], "Light") == 0 {
						count += 1
					}
				}

				pointLight := new(PointLight)
				pointLight^ = {
					name         = fmt.aprintf("Light{:3d}", count),
					graphicsData = new(valhalla.PointLight),
				}
				pointLight.graphicsData^ = {
					position   = {0, 2, 0},
					colour     = {1, 1, 1},
					brightness = 1,
				}
				append(&scene.pointLights, pointLight)
				valhalla.addLight(
					&scene.graphicsData,
					scene.pointLights[len(scene.pointLights) - 1].graphicsData,
				)

				if valhalla.updateScene(graphicsContext) != nil {
					panic(fmt.tprintf("Failed to update scene!"))
				}
			}
		}

		if imgui.CollapsingHeader("Scene Objects") {
			constructObjectsHeader(graphicsContext)
			if imgui.Button("Add Object") {
				count: u32 = 0
				for &object in scene.objects {
					if object.name[:len(object.name) - 3] == "Object" {
						count += 1
					}
				}

				gameObject := new(GameObject)
				gameObject^ = {
					name         = fmt.aprintf("Object{:3d}", count),
					position     = {0, 0, 0},
					rotation     = IQUAT,
					scale        = {1, 1, 1},
					graphicsData = new(valhalla.ModelInstance),
				}
				append(&scene.objects, gameObject)

				valhalla.addInstance(
					&scene.graphicsData,
					scene.models[0].graphicsData,
					scene.objects[len(scene.objects) - 1].graphicsData,
					&scene.objects[len(scene.objects) - 1].position,
					&scene.objects[len(scene.objects) - 1].rotation,
					&scene.objects[len(scene.objects) - 1].scale,
				)

				if valhalla.updateScene(graphicsContext) != nil {
					panic(fmt.tprintf("Failed to update scene!"))
				}
			}
		}

		if imgui.CollapsingHeader("Models") {
			constructModelsHeader(graphicsContext)
		}
	}

	constructMenuBar :: proc(graphicsContext: ^valhalla.GraphicsContext) {
		scene := &globals.scene
		if imgui.BeginMenu("File") {
			imgui.SeparatorText("Assets")
			if imgui.BeginMenu("Import") {
				if imgui.MenuItem("Model") {
					filterPatterns := []cstring{"*.gltf", "*.glb", "*.fbx", "*.obj"}
					path, _ := filepath.abs("./assets/models/", context.temp_allocator)
					file, err := filepath.rel(
						globals.baseDir,
						string(
							tinyfd.openFileDialog(
								"Load Model",
								fmt.ctprintf("%s%s", path, filepath.SEPARATOR),
								i32(len(filterPatterns)),
								raw_data(filterPatterns),
								".gltf .glb .fbx .obj",
								0,
							),
						),
						context.temp_allocator,
					)

					if file != "" {
						alreadyLoaded := false
						for &loadedFile in scene.modelPaths {
							if file == string(loadedFile) {
								alreadyLoaded = true
								break
							}
						}

						if !alreadyLoaded {
							valhalla.addModels(graphicsContext, &scene.graphicsData, {file})
							scene.models[len(scene.models) - 1].name = strings.clone("New Model")
							scene.models[len(scene.models) - 1].scale = {1, 1, 1}
							append(&scene.modelPaths, strings.clone(file))
							if valhalla.updateScene(graphicsContext) != nil {
								panic(fmt.tprintf("Failed to update scene!"))
							}
						}
					}
				}
				if imgui.MenuItem("Texture") {
					filterPatterns := []cstring{"*.jpg", "*.jpeg", "*.png"}
					path, _ := filepath.abs("./assets/textures/", context.temp_allocator)
					file, err := filepath.rel(
						globals.baseDir,
						string(
							tinyfd.openFileDialog(
								"Load Texture",
								fmt.ctprintf("{}{}", path, filepath.SEPARATOR),
								i32(len(filterPatterns)),
								raw_data(filterPatterns),
								".jpg .jpeg .png",
								0,
							),
						),
						context.temp_allocator,
					)

					extension := filepath.ext(file)[1:]
					if file != "" && extension == "png" ||
					   extension == "jpg" ||
					   extension == "jpeg" {
						alreadyLoaded := false
						for &loadedFile in scene.texturePaths {
							if file == string(loadedFile) {
								alreadyLoaded = true
								break
							}
						}

						if !alreadyLoaded {
							if valhalla.addImages(
								   graphicsContext,
								   &scene.graphicsData.textures,
								   scene.graphicsData.textureCount,
								   {file},
							   ) !=
							   nil {
								panic(fmt.tprintf("Failed to add texture: %v", file))
							}

							append(&scene.texturePaths, strings.clone(file))
							scene.graphicsData.textureCount += 1

							if valhalla.updateScene(graphicsContext) != nil {
								panic(fmt.tprintf("Failed to update scene!"))
							}
						}
					}
				}
				if imgui.MenuItem("Normal Map") {
					filterPatterns := []cstring{"*.jpg", "*.jpeg", "*.png"}
					path, _ := filepath.abs("./assets/textures/")
					defer delete(path)
					file, _ := filepath.rel(
						globals.baseDir,
						string(
							tinyfd.openFileDialog(
								"Load Normal",
								fmt.ctprintf("{}{}", path, filepath.SEPARATOR),
								i32(len(filterPatterns)),
								raw_data(filterPatterns),
								".jpg .jpeg, .png",
								0,
							),
						),
					)
					defer delete(file)

					extension := filepath.ext(file)[1:]
					if file != "" && extension == "png" ||
					   extension == "jpg" ||
					   extension == "jpeg" {
						alreadyLoaded := false
						for &loadedFile in scene.texturePaths {
							if file == string(loadedFile) {
								alreadyLoaded = true
								break
							}
						}

						if !alreadyLoaded {
							if valhalla.addImages(
								   graphicsContext,
								   &scene.graphicsData.textures,
								   scene.graphicsData.textureCount,
								   {file},
							   ) !=
							   nil {
								panic(fmt.tprintf("Failed to add normal map: %v", file))
							}

							append(&scene.texturePaths, strings.clone(file))
							scene.graphicsData.textureCount += 1

							if valhalla.updateScene(graphicsContext) != nil {
								panic(fmt.tprintf("Failed to update scene!"))
							}
						}
					}
				}
				imgui.EndMenu()
			}
			imgui.EndMenu()
		}
	}

	constructShaderEditor :: proc(graphicsContext: ^valhalla.GraphicsContext) {
		if imgui.Button("Reload Shaders") {
			if valhalla.reloadShaders(graphicsContext) != nil {
				panic(fmt.tprintf("Failed to reload shaders!"))
			}
			if valhalla.updateCommandBuffers(graphicsContext) != nil {
				panic(fmt.tprintf("Failed to reload shaders!"))
			}
		}
	}

	constructCamerasHeader :: proc(graphicsContext: ^valhalla.GraphicsContext) {
		scene := &globals.scene
		for index := len(scene.cameras) - 1; index >= 0; index -= 1 {
			camera := &scene.cameras[index]
			if !imgui.TreeNode(
				strings.clone_to_cstring(camera.name, allocator = context.temp_allocator),
			) {
				continue
			}

			active := u32(index) == scene.activeCamera
			imgui.Checkbox("Active", &active)
			if active {
				scene.activeCamera = u32(index)
			}
			imgui.DragFloat3("Eye", &camera.eye, 0.001)
			imgui.DragFloat3("Center", &camera.center, 0.001)
			imgui.DragFloat3("Up", &camera.up, 0.001)
			imgui.DragFloat("Near Plane", &camera.near, 0.01)
			imgui.DragFloat("Far Plane", &camera.far, 0.01)
			imgui.DragFloat("FOV", &camera.fov, 0.5)
			imgui.SeparatorText("Camera Mode")
			if imgui.RadioButton("Perspective", camera.mode == .PERSPECTIVE) {
				camera.mode = .PERSPECTIVE
			}
			if imgui.RadioButton("Orthographic", camera.mode == .ORTHOGRAPHIC) {
				camera.mode = .ORTHOGRAPHIC
			}
			imgui.BeginDisabled(len(scene.cameras) == 1)
			if imgui.Button("Delete") {
				delete(camera.name)
				unordered_remove(&scene.cameras, index)
				if active {
					scene.activeCamera = 0
				}
			}
			imgui.EndDisabled()
			imgui.TreePop()
		}
	}

	constructLightsHeader :: proc(graphicsContext: ^valhalla.GraphicsContext) {
		scene := &globals.scene
		for &light, index in scene.pointLights {
			if !imgui.TreeNode(
				strings.clone_to_cstring(light.name, allocator = context.temp_allocator),
			) {
				continue
			}

			imgui.DragFloat3("Position", &light.graphicsData.position, 0.001)
			imgui.DragFloat3("Colour", &light.graphicsData.colour, 0.01, 0.1, 1.0)
			imgui.DragFloat("Brightness", &light.graphicsData.brightness, 0.01)
			imgui.DragFloat("Dropoff", &light.graphicsData.dropoff, 0.1)

			imgui.BeginDisabled(len(scene.pointLights) == 1)
			if imgui.Button("Delete") {
				delete(light.name)
				unordered_remove(&scene.pointLights, index)
				unordered_remove(&scene.graphicsData.lights, index)

				if valhalla.updateScene(graphicsContext) != nil {
					panic(fmt.tprintf("Failed to update scene!"))
				}
			}
			imgui.EndDisabled()
			imgui.TreePop()
		}
	}

	constructObjectsHeader :: proc(graphicsContext: ^valhalla.GraphicsContext) {
		scene := &globals.scene
		for &object, objectIndex in scene.objects {
			if !imgui.TreeNode(
				strings.clone_to_cstring(object.name, allocator = context.temp_allocator),
			) {
				continue
			}

			imgui.Checkbox("Selectable", &object.selectable)
			imgui.Checkbox("Tiled", &object.tiled)

			imgui.SeparatorText("Object Properties")

			imgui.DragFloat3("Position", &object.position, 0.01)
			x, y, z := quatToEuler(object.rotation)
			vec := degrees(Vec3{x, y, z})
			if imgui.DragFloat3("Rotation", &vec, 5) {
				vec = radians(vec)
				object.rotation = quatFromEuler(vec.x, vec.y, vec.z, .XYZ)
			}
			imgui.DragFloat3("Scale", &object.scale, 0.001)
			if imgui.DragFloat3("Forward", &object.forward, 0.01) {
				object.forward = normalize(object.forward)
			}

			imgui.SeparatorText("Model Properties")

			if imgui.BeginCombo(
				"Model",
				strings.clone_to_cstring(
					scene.models[object.modelIdx].name,
					allocator = context.temp_allocator,
				),
			) {
				for &model, i in scene.models {
					if u32(i) != object.modelIdx &&
					   imgui.Selectable(
						   strings.clone_to_cstring(
							   model.name,
							   allocator = context.temp_allocator,
						   ),
					   ) {
						valhalla.updateInstanceModel(
							&scene.graphicsData,
							object.graphicsData,
							scene.models[i].graphicsData,
						)

						if valhalla.updateScene(graphicsContext) != nil {
							panic(fmt.tprintf("Failed to update scene!"))
						}
					}
				}
				imgui.EndCombo()
			}

			imgui.SeparatorText("Meshes")
			for &mesh, meshIndex in scene.models[object.modelIdx].graphicsData.meshes {
				buf := make([]byte, 10, allocator = context.temp_allocator)
				buf[len(strconv.itoa(buf, meshIndex))] = 0 // Terminating the string shouldn't be necessary but I'll do it anyway to be safe
				if !imgui.TreeNode(cstring(raw_data(buf))) {
					continue
				}

				if imgui.BeginCombo(
					"Texture",
					strings.clone_to_cstring(
						scene.texturePaths[object.graphicsData.textureIdxs[meshIndex][0]],
						allocator = context.temp_allocator,
					),
				) {
					for &texture, i in scene.texturePaths {
						if u32(i) != object.graphicsData.textureIdxs[meshIndex] &&
						   imgui.Selectable(
							   strings.clone_to_cstring(
								   texture,
								   allocator = context.temp_allocator,
							   ),
						   ) {
							valhalla.updateInstanceTexture(graphicsContext, object.graphicsData, u32(meshIndex), .ALBEDO, u32(i))
							object.graphicsData.textureIdxs[meshIndex] = u32(i)
							if valhalla.updateCommandBuffers(graphicsContext) != nil {
								panic(fmt.tprintf("Failed to update command buffers!"))
							}
						}
					}
					imgui.EndCombo()
				}

				if imgui.BeginCombo(
					"Normal Map",
					strings.clone_to_cstring(
						scene.texturePaths[object.graphicsData.textureIdxs[meshIndex][1]],
						allocator = context.temp_allocator,
					),
				) {
					for &normal, i in scene.texturePaths {
						if u32(i) != object.graphicsData.textureIdxs[meshIndex][1] &&
						   imgui.Selectable(
							   strings.clone_to_cstring(
								   normal,
								   allocator = context.temp_allocator,
							   ),
						   ) {
							valhalla.updateInstanceTexture(graphicsContext, object.graphicsData, u32(meshIndex), .NORMAL_MAP, u32(i))
							if valhalla.updateCommandBuffers(graphicsContext) != nil {
								panic(fmt.tprintf("Failed to update command buffers!"))
							}
						}
					}
					imgui.EndCombo()
				}
				imgui.TreePop()
			}

			animations := &scene.models[object.modelIdx].animations
			if len(animations) > 0 {
				imgui.SeparatorText("Animations")
				if imgui.BeginCombo(
					"Animation Selection",
					strings.clone_to_cstring(
						animations[object.animIdx].name,
						allocator = context.temp_allocator,
					),
				) {
					for &animation, i in animations {
						if object.animIdx != u32(i) &&
						   imgui.Selectable(
							   strings.clone_to_cstring(
								   animation.name,
								   allocator = context.temp_allocator,
							   ),
						   ) {
							object.animIdx = u32(i)
						}
					}
					imgui.EndCombo()
				}
				if imgui.DragScalar(
					"Animation Timer",
					.Double,
					&object.graphicsData.animTimer,
					0.01,
				) {
					if object.graphicsData.animTimer < 0 {
						object.graphicsData.animTimer =
							scene.models[object.modelIdx].animations[object.animIdx].graphicsData.duration +
							object.graphicsData.animTimer
					}
				}
			}

			imgui.BeginDisabled(len(scene.objects) == 1)
			if imgui.Button("Delete") {
				valhalla.removeInstance(&scene.graphicsData, object.graphicsData)
				unordered_remove(&scene.objects, objectIndex)
				delete(object.name)

				if valhalla.updateScene(graphicsContext) != nil {
					panic(fmt.tprintf("Failed to update scene!"))
				}
			}
			imgui.EndDisabled()
			imgui.TreePop()
		}
	}

	constructModelsHeader :: proc(graphicsContext: ^valhalla.GraphicsContext) {
		scene := &globals.scene
		for &model in scene.models {
			if !imgui.TreeNode(
				strings.clone_to_cstring(model.name, allocator = context.temp_allocator),
			) {
				continue
			}

			imgui.DragFloat3("Position", &model.position, 0.01)
			x, y, z := quatToEuler(model.rotation)
			vec := degrees(Vec3{x, y, z})
			if imgui.DragFloat3("Rotation", &vec, 5) {
				vec = radians(vec)
				model.rotation = quatFromEuler(vec.x, vec.y, vec.z, .XYZ)
			}
			imgui.DragFloat3("Scale", &model.scale, 0.001)

			imgui.TreePop()
		}
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
		constructSceneEditor(graphicsContext)
	}
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
	if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
		object, _ := castRay(screenPositionToWorldRay(mousePos), &globals.scene)
		if object != nil && object.selectable {
			log.logf(.Debug, "Selected instance: {}", object.name)
			globals.selectedObject = object
		} else {
			globals.selectedObject = nil
		}
		return
	}
	if button == glfw.MOUSE_BUTTON_RIGHT && action == glfw.RELEASE {
		if globals.selectedObject == nil {
			return
		}

		origin, direction := screenPositionToWorldRay(mousePos)
		object, distance := castRay(origin, direction, &globals.scene)
		if object != nil && object.tiled {
			pos := (origin + direction * distance)
			globals.selectedObject.action = MoveAction {
				destination = {round(pos.x), object.position.y, round(pos.z)},
			}
			globals.inputLock = true
		}
		return
	}
}

cursorPosCallback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	newPos: Vec2 = {f32(xpos), f32(ypos)}
	mouseDelta.xy = newPos - mousePos
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
