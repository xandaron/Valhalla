package Valhalla

import "../imgui"
import tinyfd "../tinyfiledialogs"
import "core:fmt"
import "core:os/os2"
import "core:path/filepath"
import "core:reflect"
import "core:strings"

UIData :: struct {
	lockInput:           bool,
	createComponentInfo: CreateComponentData,
	showDemo:            bool,
	showMetrics:         bool,
}

CreateComponentData :: struct {
	name:      [100]byte,
	savePath:  [100]byte,
	assetPath: [100]byte,
}

overwriteBuffer :: proc(buffer: ^[100]byte, value: []byte) {
	i := 0
	for ; i < len(value); i += 1 {
		buffer[i] = value[i]
	}

	for ; i < len(buffer); i += 1 {
		if buffer[i] == 0 {
			break
		}
		buffer[i] = 0
	}
}

clearBuffer :: proc(buffer: ^[100]byte) {
	for i := 0; i < len(buffer); i += 1 {
		if buffer[i] == 0 {
			break
		}
		buffer[i] = 0
	}
}

clearComponentData :: proc(componentInfo: ^CreateComponentData) {
	clearBuffer(&componentInfo.name)
	clearBuffer(&componentInfo.savePath)
	clearBuffer(&componentInfo.assetPath)
}

saveAs :: proc(scene: ^Scene) {
	absPath, _ := filepath.abs(SCENE_PATH, context.temp_allocator)
	str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
	if str != "" {
		relPath, err := filepath.rel(globals.projectDir, string(str), context.temp_allocator)
		if err != nil {
			logf(
				.Error,
				"Failed to get relative path: %v\nBase: %v\nPath: %v",
				err,
				globals.projectDir,
				string(str),
			)
			relPath = string(str)
		}
		hasAlloc: bool
		scene.path, hasAlloc = filepath.to_slash(relPath)
		if !hasAlloc {
			scene.path = strings.clone(scene.path)
		}
		saveScene(scene)
	}
}

drawImgui :: proc(graphicsData: ^GraphicsData) {
	toCstring :: #force_inline proc(str: string, allocator := context.temp_allocator) -> cstring {
		return strings.clone_to_cstring(str, allocator = allocator)
	}

	uiData := &globals.uiData
	if uiData.showMetrics {
		imgui.SetNextWindowBgAlpha(1.0)
		imgui.ShowMetricsWindow()
	}

	if uiData.showDemo {
		imgui.SetNextWindowBgAlpha(1.0)
		imgui.ShowDemoWindow()
	}

	imgui.SetNextWindowBgAlpha(1.0)
	if imgui.Begin("Editor", nil, {.MenuBar}) {
		scene := &globals.scenes[globals.activeScene]
		if imgui.BeginMenuBar() {
			if imgui.BeginMenu("File") {
				if imgui.MenuItem("Open") {
					str := string(tinyfd.openFileDialog("Open Scene", SCENE_PATH, 0, nil, nil, 0))
					relPath, err := filepath.rel(globals.projectDir, str, context.temp_allocator)
					if err != nil {
						logf(
							.Error,
							"Failed to get relative path: %v\nBase: %v\nPath: %v",
							err,
							globals.projectDir,
							str,
						)
						relPath = str
					}
					path, hasAlloc := filepath.to_slash(str)
					if !hasAlloc {
						path = strings.clone(path)
					}
					append(&globals.scenes, Scene{path = path})
					loadScene(&globals.scenes[len(globals.scenes) - 1])
				}

				if imgui.MenuItem("Save") {
					if scene.path != "" {
						saveScene(scene)
					} else {
						saveAs(scene)
					}
				}

				if imgui.MenuItem("Save As...") {
					saveAs(scene)
				}

				if imgui.MenuItem("Close") {
					saveScene(scene)
					if len(globals.scenes) > 1 {
						deleteScene(scene)
						unordered_remove(&globals.scenes, globals.activeScene)
						globals.activeScene = 0
						scene := &globals.scenes[0]
					}
				}

				imgui.SeparatorText("Assets")
				if imgui.BeginMenu("Import") {
					if imgui.MenuItem("Model") {
						path := tinyfd.openFileDialog("Open Model", MODELS_PATH, 0, nil, nil, 0)
						if str := string(path);
						   str != "" && os2.exists(str) && filepath.ext(string(str)) == ".model" {
							relPath, err := filepath.rel(
								globals.projectDir,
								str,
								context.temp_allocator,
							)
							if err != nil {
								logf(
									.Error,
									"Failed to get relative path: %v\nBase: %v\nPath: %v",
									err,
									globals.projectDir,
									string(str),
								)
								relPath = string(str)
							}
							finalPath, wasAlloc := filepath.to_slash(relPath)
							if !wasAlloc {
								finalPath = strings.clone(finalPath)
							}
							append(&scene.models, Model{path = finalPath})
							model := &scene.models[len(scene.models) - 1]
							if err := loadModelComponent(model); err != nil {
								logf(.Error, "Failed to load model component: %v", err)
							} else {
								if err := loadModel(scene, model); err != nil {
									logf(.Error, "Failed to load model: %v", err)
									delete(scene.models[len(scene.models) - 1].path)
									unordered_remove(&scene.models, len(scene.models) - 1)
								}
							}
						}
					}

					if imgui.MenuItem("Texture") {
						path := tinyfd.openFileDialog(
							"Open Texture",
							TEXTURES_PATH,
							0,
							nil,
							nil,
							0,
						)
						if str := string(path);
						   str != "" &&
						   os2.exists(str) &&
						   filepath.ext(string(str)) == ".texture" {
							relPath, err := filepath.rel(
								globals.projectDir,
								str,
								context.temp_allocator,
							)
							if err != nil {
								logf(
									.Error,
									"Failed to get relative path: %v\nBase: %v\nPath: %v",
									err,
									globals.projectDir,
									string(str),
								)
								relPath = string(str)
							}
							path, wasAlloc := filepath.to_slash(relPath)
							if !wasAlloc {
								path = strings.clone(path)
							}
							append(&scene.textures, Texture{path = path})
							texture := &scene.textures[len(scene.textures) - 1]
							if err := loadTextureComponent(texture); err != nil {
								logf(.Error, "Failed to load texture: %v", err)
								delete(texture.path)
								unordered_remove(&scene.textures, len(scene.textures) - 1)
							} else {
								err := addImages(
									graphicsData,
									&scene.buffers.textures,
									u32(len(scene.textures)) - 1,
									{texture.path},
								)
								if err != nil {
									panic("Failed to add texture image")
								}
							}
						}
					}
					imgui.EndMenu()
				}
				imgui.EndMenu()
			}
			imgui.EndMenuBar()
		}

		if imgui.CollapsingHeader("Settings##header") {
			if imgui.Button("New Scene") {
				uiData.lockInput = true
				imgui.OpenPopup("New Scene")
			}

			imgui.SameLine()
			if imgui.BeginCombo("Scene", toCstring(scene.name)) {
				for &scene, sceneIdx in globals.scenes {
					if globals.activeScene == u32(sceneIdx) {
						continue
					}
					if imgui.Selectable(toCstring(scene.name)) {
						globals.activeScene = u32(sceneIdx)

						graphicsData.reloadBuffers = true
						graphicsData.rerecordCommands = true
					}
				}
				imgui.EndCombo()
			}

			if imgui.DragFloat("Contrast", &graphicsData.contrast, 0.01) {
				graphicsData.reloadBuffers = true
			}
			if imgui.DragFloat("Brightness", &graphicsData.brightness, 0.01) {
				graphicsData.reloadBuffers = true
			}
			if imgui.DragFloat("Saturation", &graphicsData.saturation, 0.01) {
				graphicsData.reloadBuffers = true
			}
			if imgui.DragFloat("Exposure", &graphicsData.exposure, 0.01) {
				graphicsData.reloadBuffers = true
			}
			if imgui.Combo(
				"Tonemapper",
				transmute(^i32)(&graphicsData.tonemapper),
				"None\000Narkowicz ACES\000",
			) {
				graphicsData.reloadBuffers = true
			}
			if imgui.DragFloat("Gamma", &graphicsData.gamma, 0.01) {
				graphicsData.reloadBuffers = true
			}
		}

		if imgui.CollapsingHeader("Scene##header") {
			if imgui.DragFloat("Ambient light##scene", &scene.ambientLight, 0.01, 0, 1) {
				graphicsData.reloadBuffers = true
			}
			if imgui.DragFloat4("Clear colour##scene", &scene.clearColour, 0.01, 0, 1) {
				graphicsData.reloadBuffers = true
			}
		}

		if imgui.CollapsingHeader("Objects##header") {
			if imgui.Button("New Object##objects") {
				addObject(scene, 0)

				globals.graphicsData.reloadBuffers = true
				globals.graphicsData.rerecordCommands = true
			}

			for &object, objectIdx in scene.objects {
				suffix := fmt.tprintf("##object%v", objectIdx)
				if imgui.TreeNode(toCstring(object.name)) {
					imgui.DragFloat3(fmt.ctprintf("Position%v", suffix), &object.position, 0.1)

					x, y, z := quatToEuler(object.rotation)
					x = degrees(x)
					y = degrees(y)
					z = degrees(z)
					rotation := Vec3{x, y, z}
					if imgui.DragFloat3(fmt.ctprintf("Rotation%v", suffix), &rotation, 0.1) {
						delta := rotation - Vec3{x, y, z}
						object.rotation *= quatFromEuler(
							radians(delta.x),
							radians(delta.y),
							radians(delta.z),
							.XYZ,
						)
					}
					imgui.DragFloat3(fmt.ctprintf("Scale%v", suffix), &object.scale, 0.1)

					if imgui.TreeNode("Flags:") {
						for flag in ObjectFlag {
							present := flag in object.flags
							if imgui.Checkbox(toCstring(reflect.enum_string(flag)), &present) {
								if present {
									object.flags += {flag}
								} else {
									object.flags -= {flag}
								}
							}
						}
						imgui.TreePop()
					}

					imgui.SeparatorText("Animation")
					animationData := &object.animation
					if len(scene.models[object.modelIdx].animations) > 0 {
						animationName: string
						if animationData.idx >= 0 {
							animationName =
								scene.models[object.modelIdx].animations[animationData.idx].name
						} else {
							animationName = "None"
						}

						if imgui.BeginCombo(
							fmt.ctprintf("Animation Clip%v", suffix),
							toCstring(animationName),
						) {
							if animationData.idx >= 0 {
								if imgui.Selectable("None") {
									animationData.idx = -1
									animationData.timer = 0
								}
							}

							for &animation, animationIdx in scene.models[object.modelIdx].animations {
								if i32(animationIdx) == animationData.idx {
									continue
								}

								if imgui.Selectable(toCstring(animation.name)) {
									animationData.idx = i32(animationIdx)
									animationData.timer = 0
									for &node in animationData.cache {
										node.positionIdx = 0
										node.rotationIdx = 0
										node.scaleIdx = 0
									}
								}
							}
							imgui.EndCombo()
						}
					}

					imgui.Checkbox(fmt.ctprintf("Playing%v", suffix), &animationData.playing)

					timer := f32(animationData.timer)
					if imgui.DragFloat(fmt.ctprintf("Animation time%v", suffix), &timer, 0.01) {
						animationData.timer = f64(timer)
					}

					if imgui.BeginCombo(
						fmt.ctprintf("Animation Behavior%v", suffix),
						fmt.ctprintf("%v", animationData.end.behavior),
					) {
						for behavior in AnimationBehavior {
							if behavior == animationData.end.behavior {
								continue
							}

							if imgui.Selectable(fmt.ctprintf("%v", behavior)) {
								animationData.end.behavior = behavior
							}
						}
						imgui.EndCombo()
					}

					if imgui.BeginCombo(
						fmt.ctprintf("Model%v", suffix),
						toCstring(scene.models[object.modelIdx].name),
					) {
						for modelIdx in 0 ..< len(scene.models) {
							if u32(modelIdx) == object.modelIdx {
								continue
							}

							model := &scene.models[modelIdx]
							if imgui.Selectable(toCstring(model.name)) {
								changeModel(scene, u32(objectIdx), u32(modelIdx))
								textureIdxs := make([][len(TextureIndex)]u32, len(model.meshes))
								for i in 0 ..< min(len(model.meshes), len(object.textureIdxs)) {
									textureIdxs[i] = object.textureIdxs[i]
								}
								delete(object.textureIdxs)
								object.textureIdxs = textureIdxs

								delete(object.animation.state)
								delete(object.animation.cache)
								object.animation.state = make([]Mat4, len(model.skeleton))
								object.animation.cache = make(
									[]ObjectAnimationCache,
									len(model.skeleton),
								)

								graphicsData.reloadBuffers = true
								graphicsData.rerecordCommands = true
							}
						}
						imgui.EndCombo()
					}

					for mesh, meshIdx in scene.models[object.modelIdx].meshes {
						meshSuffix := fmt.ctprintf("%v##mesh%v", suffix, meshIdx)
						if imgui.TreeNode(toCstring(mesh.name)) {
							if imgui.BeginCombo(
								fmt.ctprintf("Albedo%v", meshSuffix),
								toCstring(
									scene.textures[object.textureIdxs[meshIdx][TextureIndex.Albedo]].name,
								),
							) {
								for &texture, textureIdx in scene.textures {
									if object.textureIdxs[meshIdx][TextureIndex.Albedo] ==
									   u32(textureIdx) {
										continue
									}

									if imgui.Selectable(toCstring(texture.name)) {
										object.textureIdxs[meshIdx][TextureIndex.Albedo] = u32(
											textureIdx,
										)
										graphicsData.reloadBuffers = true
									}
								}
								imgui.EndCombo()
							}

							if imgui.BeginCombo(
								fmt.ctprintf("Normal Map%v", meshSuffix),
								toCstring(
									scene.textures[object.textureIdxs[meshIdx][TextureIndex.NormalMap]].name,
								),
							) {
								for &texture, textureIdx in scene.textures {
									if object.textureIdxs[meshIdx][TextureIndex.NormalMap] ==
									   u32(textureIdx) {
										continue
									}
									if imgui.Selectable(toCstring(texture.name)) {
										object.textureIdxs[meshIdx][TextureIndex.NormalMap] = u32(
											textureIdx,
										)
										graphicsData.reloadBuffers = true
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

		if imgui.CollapsingHeader("Cameras##header") {
			for &camera, cameraIdx in scene.cameras {
				suffix := fmt.tprintf("##camera%v", cameraIdx)
				if imgui.TreeNode(toCstring(camera.name)) {
					if imgui.BeginCombo(
						fmt.ctprintf("Mode%s", suffix),
						toCstring(fmt.tprintf("%v", camera.mode)),
					) {
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

					imgui.DragFloat3(fmt.ctprintf("Eye%s", suffix), &camera.eye, 0.1)
					imgui.DragFloat3(fmt.ctprintf("Center%s", suffix), &camera.center, 0.1)
					imgui.DragFloat3(fmt.ctprintf("Up%s", suffix), &camera.up, 0.1)

					imgui.DragFloat(fmt.ctprintf("FOV%s", suffix), &camera.fov, 0.1)
					imgui.DragFloat(fmt.ctprintf("Near Plane%s", suffix), &camera.near, 0.1)
					imgui.DragFloat(fmt.ctprintf("Far Plane%s", suffix), &camera.far, 0.1)

					imgui.TreePop()
				}
			}
		}

		if imgui.CollapsingHeader("Lights##header") {
			for &light, lightIdx in scene.lights {
				suffix := fmt.tprintf("##light%v", lightIdx)
				if imgui.TreeNode(toCstring(light.name)) {
					imgui.DragFloat3(fmt.ctprintf("Position%v", suffix), &light.position, 0.1)
					imgui.DragFloat3(fmt.ctprintf("Colour%v", suffix), &light.colour, 0.01, 0, 1)
					imgui.DragFloat(fmt.ctprintf("Brightness%v", suffix), &light.brightness, 0.1)
					imgui.DragFloat(fmt.ctprintf("Dropoff%v", suffix), &light.dropoff, 0.1)

					imgui.TreePop()
				}
			}
		}

		if imgui.CollapsingHeader("Models##header") {
			if imgui.Button("Add New Model") {
				uiData.lockInput = true
				imgui.OpenPopup("New Model")
			}

			for &model, modelIdx in scene.models {
				suffix := fmt.tprintf("##model%v", modelIdx)
				if imgui.TreeNode(toCstring(model.name)) {
					imgui.DragFloat3(fmt.ctprintf("Position%v", suffix), &model.position, 0.1)

					x, y, z := quatToEuler(model.rotation)
					rotation := Vec3{degrees(x), degrees(y), degrees(z)}
					if imgui.DragFloat3(fmt.ctprintf("Rotation%v", suffix), &rotation, 0.1) {
						model.rotation = quatFromEuler(
							radians(rotation.x),
							radians(rotation.y),
							radians(rotation.z),
							.XYZ,
						)
					}

					imgui.DragFloat3(fmt.ctprintf("Scale%v", suffix), &model.scale, 0.1)
					imgui.TreePop()
				}
			}
		}

		if imgui.CollapsingHeader("Textures##header") {
			if imgui.Button("Add New Texture") {
				uiData.lockInput = true
				imgui.OpenPopup("New Texture")
			}

			for &texture, textureIdx in scene.textures {
				suffix := fmt.tprintf("##texture%v", textureIdx)
				if imgui.TreeNode(toCstring(texture.name)) {
					imgui.Text("Asset Path: ")
					imgui.SameLine()
					imgui.Text(toCstring(texture.assetPath))
					imgui.TreePop()
				}
			}
		}
	}

	if imgui.BeginPopupModal("New Scene") {
		createComponentInfo := &uiData.createComponentInfo
		imgui.Text("Name:")
		imgui.SameLine()
		imgui.InputText(
			"##scenename",
			cstring(&createComponentInfo.name[0]),
			len(createComponentInfo.name),
		)

		imgui.Text("Save Path:")
		imgui.SameLine()
		imgui.InputText(
			"##savepath",
			cstring(&createComponentInfo.savePath[0]),
			len(createComponentInfo.savePath),
		)
		imgui.SameLine()
		if imgui.Button("Browse##save") {
			absPath, _ := filepath.abs(SCENE_PATH, context.temp_allocator)
			str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
			}
		}

		if imgui.Button("Create") {
			scene := &globals.scenes[globals.activeScene]

			if createComponentInfo.name[0] != 0 && createComponentInfo.savePath[0] != 0 {
				name, path: string
				didAlloc: bool

				name, didAlloc = filepath.to_slash(string(createComponentInfo.name[:]))
				if !didAlloc {
					name = strings.clone_from_bytes(createComponentInfo.name[:])
				}

				path, didAlloc = filepath.to_slash(string(createComponentInfo.savePath[:]))
				if !didAlloc {
					path = strings.clone_from_bytes(createComponentInfo.savePath[:])
				}

				append(&globals.scenes, Scene{name = name, path = path})
				scene := &globals.scenes[len(globals.scenes) - 1]
				if err := saveScene(scene); err != nil {
					delete(name)
					delete(path)
					unordered_remove(&globals.scenes, len(globals.scenes) - 1)
					logf(.Error, "Failed to make new scene: %v", err)
				}

				append(
					&scene.models,
					Model{path = strings.clone("scene_components/models/cube.model")},
				)
				loadModelComponent(&scene.models[0])
				loadModel(scene, &scene.models[0])

				append(
					&scene.textures,
					Texture{path = strings.clone("scene_components/textures/cube.texture")},
				)
				loadTextureComponent(&scene.textures[0])

				append(
					&scene.cameras,
					Camera {
						name = strings.clone("Main"),
						mode = .PERSPECTIVE,
						eye = Vec3{0, 0, -5},
						center = Vec3{0, 0, 0},
						up = Vec3{0, 1, 0},
						fov = 45,
						near = 0.1,
						far = 100,
					},
				)

				append(
					&scene.lights,
					PointLight {
						name = strings.clone("Light"),
						position = Vec3{0, 5, 0},
						colour = Vec3{1, 1, 1},
						brightness = 1,
						dropoff = 1,
					},
				)

				scene.boneCount = 1
				append(
					&scene.objects,
					Object {
						name = strings.clone("Cube"),
						position = Vec3{0, 0, 0},
						rotation = IQUAT,
						scale = Vec3{1, 1, 1},
						modelIdx = 0,
						instanceIdx = 0,
						textureIdxs = make([][len(TextureIndex)]u32, 1),
						animation = ObjectAnimation{idx = -1},
						attachment = Attachment{targetIdx = -1},
					},
				)
				addInstance(scene, &scene.models[0], 0)

				clearComponentData(createComponentInfo)
				uiData.lockInput = false
				imgui.CloseCurrentPopup()
			}
		}

		imgui.SameLine()
		if imgui.Button("Cancel") {
			imgui.CloseCurrentPopup()
			uiData.lockInput = false
			clearComponentData(createComponentInfo)
		}
		imgui.End()
	}

	if imgui.BeginPopupModal("New Model") {
		createComponentInfo := &uiData.createComponentInfo
		imgui.Text("Name:")
		imgui.SameLine()
		imgui.InputText("##texturename", cstring(&createComponentInfo.name[0]), 100)

		imgui.Text("Image Path:")
		imgui.SameLine()
		imgui.InputText("##texturepath", cstring(&createComponentInfo.assetPath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##texture") {
			absPath, _ := filepath.abs(ASSETS_PATH, context.temp_allocator)
			str := tinyfd.openFileDialog(
				"Load Image",
				fmt.ctprintf("%s/", absPath),
				0,
				nil,
				nil,
				0,
			)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.assetPath, transmute([]byte)relPath)
			}
		}

		imgui.Text("Save Path:")
		imgui.SameLine()
		imgui.InputText("##savepath", cstring(&createComponentInfo.savePath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##save") {
			absPath, _ := filepath.abs(MODELS_PATH, context.temp_allocator)
			str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
			}
		}

		if imgui.Button("Create") {
			scene := &globals.scenes[globals.activeScene]

			name, path, assetPath: string
			didAlloc: bool

			if createComponentInfo.name[0] != 0 &&
			   createComponentInfo.savePath[0] != 0 &&
			   createComponentInfo.assetPath[0] != 0 {
				name, didAlloc = filepath.to_slash(string(createComponentInfo.name[:]))
				if !didAlloc {
					name = strings.clone_from_bytes(createComponentInfo.name[:])
				}

				path, didAlloc = filepath.to_slash(string(createComponentInfo.savePath[:]))
				if !didAlloc {
					path = strings.clone_from_bytes(createComponentInfo.savePath[:])
				}

				assetPath, didAlloc = filepath.to_slash(string(createComponentInfo.assetPath[:]))
				if !didAlloc {
					assetPath = strings.clone_from_bytes(createComponentInfo.assetPath[:])
				}

				append(&scene.models, Model{name = name, path = path, assetPath = assetPath})

				model := &scene.models[len(scene.models) - 1]
				model.rotation = IQUAT
				model.scale = {1, 1, 1}
				loadModel(scene, model)

				saveModelComponent(model)
				clearComponentData(createComponentInfo)
				uiData.lockInput = false
				imgui.CloseCurrentPopup()
			}
		}

		imgui.SameLine()
		if imgui.Button("Cancel") {
			imgui.CloseCurrentPopup()
			uiData.lockInput = false
			clearComponentData(createComponentInfo)
		}
		imgui.End()
	}

	if imgui.BeginPopupModal("New Texture") {
		createComponentInfo := &uiData.createComponentInfo
		imgui.Text("Name:")
		imgui.SameLine()
		imgui.InputText("##texturename", cstring(&createComponentInfo.name[0]), 100)

		imgui.Text("Image Path:")
		imgui.SameLine()
		imgui.InputText("##texturepath", cstring(&createComponentInfo.assetPath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##texture") {
			absPath, _ := filepath.abs(ASSETS_PATH, context.temp_allocator)
			str := tinyfd.openFileDialog(
				"Load Image",
				fmt.ctprintf("%s/", absPath),
				0,
				nil,
				nil,
				0,
			)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.assetPath, transmute([]byte)relPath)
			}
		}

		imgui.Text("Save Path:")
		imgui.SameLine()
		imgui.InputText("##savepath", cstring(&createComponentInfo.savePath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##save") {
			absPath, _ := filepath.abs(MODELS_PATH, context.temp_allocator)
			str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
			}
		}

		if imgui.Button("Create") {
			scene := &globals.scenes[globals.activeScene]

			name, path, assetPath: string
			didAlloc: bool

			if createComponentInfo.name[0] != 0 &&
			   createComponentInfo.savePath[0] != 0 &&
			   createComponentInfo.assetPath[0] != 0 {
				name, didAlloc = filepath.to_slash(string(createComponentInfo.name[:]))
				if !didAlloc {
					name = strings.clone_from_bytes(createComponentInfo.name[:])
				}

				path, didAlloc = filepath.to_slash(string(createComponentInfo.savePath[:]))
				if !didAlloc {
					path = strings.clone_from_bytes(createComponentInfo.savePath[:])
				}

				assetPath, didAlloc = filepath.to_slash(string(createComponentInfo.assetPath[:]))
				if !didAlloc {
					assetPath = strings.clone_from_bytes(createComponentInfo.assetPath[:])
				}

				append(&scene.textures, Texture{name = name, path = path, assetPath = assetPath})

				texture := &scene.textures[len(scene.textures) - 1]

				saveTextureComponent(texture)
				clearComponentData(createComponentInfo)
				uiData.lockInput = false
				imgui.CloseCurrentPopup()
			}
		}

		imgui.SameLine()
		if imgui.Button("Cancel") {
			imgui.CloseCurrentPopup()
			uiData.lockInput = false
			clearComponentData(createComponentInfo)
		}
		imgui.End()
	}

	imgui.End()
}

