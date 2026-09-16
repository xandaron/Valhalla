package Valhalla

import "../imgui"
import ImRefl "../imreflect"
import tinyfd "../tinyfiledialogs"
import "core:fmt"
import "core:os"
import "core:path/filepath"
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

bufferText :: proc(buffer: ^[100]byte) -> string {
	length := 0
	for length < len(buffer) && buffer[length] != 0 {
		length += 1
	}
	return string(buffer[:length])
}

clearComponentData :: proc(componentInfo: ^CreateComponentData) {
	clearBuffer(&componentInfo.name)
	clearBuffer(&componentInfo.savePath)
	clearBuffer(&componentInfo.assetPath)
}

saveAs :: proc(scene: ^Scene) {
	absPath, _ := filepath.abs(SCENE_PATH(), context.temp_allocator)
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
		newPath, oerr := os.replace_path_separators(relPath, '/', context.allocator)
		if oerr != nil {
			log(.Error, "Failed to replace path seperators!")
			return
		}
		delete(scene.path)
		scene.path = newPath
		saveScene(scene)
	}
}

@(private = "file")
sceneEdited :: proc(graphicsData: ^GraphicsData) {
	graphicsData.reloadBuffers = true
	markCommandsDirty(graphicsData, DIRTY_ALL)
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
					str := string(tinyfd.openFileDialog("Open Scene", projectPathC(SCENE_PATH()), 0, nil, nil, 0))
					if str != "" && os.exists(str) {
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
								str,
							)
							relPath = str
						}
						path, oerr := os.replace_path_separators(
							relPath,
							'/',
							context.allocator,
						)
						if oerr != nil {
							log(.Error, "Failed to replace path seperators!")
						}
						append(&globals.scenes, Scene{path = path})
						sceneIdx := len(globals.scenes) - 1
						if lerr := loadScene(&globals.scenes[sceneIdx]); lerr != .None {
							logf(.Error, "Failed to open scene \"%s\": %v", path, lerr)
							deleteScene(&globals.scenes[sceneIdx])
							unordered_remove(&globals.scenes, sceneIdx)
						}
					}
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
						path := tinyfd.openFileDialog("Open Model", projectPathC(RESOURCE_PATH()), 0, nil, nil, 0)
						if str := string(path);
						   str != "" && os.exists(str) && filepath.ext(string(str)) == ".model" {
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
							finalPath, oerr := os.replace_path_separators(
								relPath,
								'/',
								context.allocator,
							)
							if oerr != nil {
								log(.Error, "Failed to replace path seperators!")
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
							projectPathC(RESOURCE_PATH()),
							0,
							nil,
							nil,
							0,
						)
						if str := string(path);
						   str != "" && os.exists(str) && filepath.ext(string(str)) == ".texture" {
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
							path, oerr := os.replace_path_separators(
								relPath,
								'/',
								context.allocator,
							)
							if oerr != nil {
								log(.Error, "Failed to replace path seperators!")
							}
							append(&scene.textures, Texture{path = path})
							texture := &scene.textures[len(scene.textures) - 1]
							if err := loadTextureComponent(texture); err != nil {
								logf(.Error, "Failed to load texture: %v", err)
								delete(texture.path)
								unordered_remove(&scene.textures, len(scene.textures) - 1)
							} else if err := addImages(
								graphicsData,
								scene,
								{texture.assetPath},
							); err != nil {
								logf(
									.Error,
									"Failed to add texture image \"%s\": %v",
									texture.assetPath,
									err,
								)
								deleteTexture(texture)
								unordered_remove(&scene.textures, len(scene.textures) - 1)
							} else {
								graphicsData.reloadBuffers = true
								markCommandsDirty(graphicsData, DIRTY_ALL)
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
						markCommandsDirty(graphicsData, DIRTY_ALL)
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

			imgui.BeginDisabled(hdrActive(graphicsData))
			if imgui.DragFloat("Gamma", &graphicsData.gamma, 0.01) {
				graphicsData.reloadBuffers = true
			}
			imgui.EndDisabled()
			if hdrActive(graphicsData) {
				imgui.SetItemTooltip("Unused in HDR; the PQ transfer function replaces it.")
			}

			available := hdrAvailable(graphicsData)
			hdr := hdrEnabled(graphicsData)
			imgui.BeginDisabled(!available)
			if imgui.Checkbox("HDR", &hdr) {
				setHDREnabled(graphicsData, hdr)
			}
			imgui.EndDisabled()
			if !available {
				imgui.SetItemTooltip("This surface offers no HDR10 format.")
			}
			imgui.SameLine()
			if !available {
				imgui.Text("(unavailable)")
			} else {
				imgui.Text(hdrActive(graphicsData) ? "(HDR10 PQ)" : "(sRGB)")
			}

			if imgui.Checkbox("Light gizmos", &graphicsData.showLightGizmos) {
				markCommandsDirty(graphicsData, {.Scene})
			}
			imgui.BeginDisabled(!graphicsData.showLightGizmos)
			if imgui.DragFloat("Gizmo radius", &graphicsData.lightGizmoRadius, 0.01, 0.01, 5.0) {
				markCommandsDirty(graphicsData, {.Scene})
			}
			imgui.EndDisabled()

			imgui.BeginDisabled(!hdrActive(graphicsData))
			if imgui.DragFloat("Paper white (nits)", &graphicsData.paperWhiteNits, 1.0, 50, 1000) {
				graphicsData.reloadBuffers = true
			}
			imgui.EndDisabled()
		}

		if imgui.CollapsingHeader("Scene##header") {
			if ImRefl.draw_value("Ambient light", scene.ambientLight) {
				graphicsData.reloadBuffers = true
			}
			if ImRefl.draw_value("Clear colour", scene.clearColour, {flags = {.Colour}}) {
				graphicsData.reloadBuffers = true
			}
		}

		if imgui.CollapsingHeader("Objects##header") {
			if imgui.Button("New Object##objects") {
				addObject(scene, 0)

				globals.graphicsData.reloadBuffers = true
				markCommandsDirty(&globals.graphicsData, DIRTY_GEOMETRY)
			}

			for &object, objectIdx in scene.objects {
				suffix := fmt.tprintf("##object%v", objectIdx)
				if imgui.TreeNode(toCstring(object.name)) {
					defer imgui.TreePop()

					if ImRefl.draw_value(object.name, object, {flags = {.Flatten}}) {
						sceneEdited(graphicsData)
					}

					imgui.SeparatorText("Model")
					if imgui.BeginCombo(fmt.ctprintf("Model%v", suffix), toCstring(scene.models[object.modelIdx].name)) {
						defer imgui.EndCombo()
						for modelIdx in 0 ..< len(scene.models) {
							if u32(modelIdx) == object.modelIdx {
								continue
							}

							model := &scene.models[modelIdx]
							if imgui.Selectable(toCstring(model.name)) {
								changeModel(scene, u32(objectIdx), u32(modelIdx))
								textureIdxs := make([][TextureIndex]u32, len(model.meshes))
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
								markCommandsDirty(graphicsData, DIRTY_GEOMETRY)
							}
						}
					}

					animationData := &object.animation
					if len(scene.models[object.modelIdx].animations) > 0 {
						imgui.SeparatorText("Animation")
						animationName: string
						if animationData.idx >= 0 {
							animationName =
								scene.models[object.modelIdx].animations[animationData.idx].name
						} else {
							animationName = "None"
						}

						if imgui.BeginCombo(fmt.ctprintf("Animation Clip%v", suffix), toCstring(animationName)) {
							defer imgui.EndCombo()
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
						}
					}

					imgui.SeparatorText("Textures")
					for mesh, meshIdx in scene.models[object.modelIdx].meshes {
						meshSuffix := fmt.ctprintf("%v##mesh%v", suffix, meshIdx)
						if imgui.TreeNode(toCstring(mesh.name)) {
							defer imgui.TreePop()
							for slot in TextureIndex {
								current := &object.textureIdxs[meshIdx][slot]
								if imgui.BeginCombo(fmt.ctprintf("%v%v", slot, meshSuffix), toCstring(scene.textures[current^].name)) {
									defer imgui.EndCombo()
									for &texture, textureIdx in scene.textures {
										if current^ == u32(textureIdx) {
											continue
										}
										if imgui.Selectable(toCstring(texture.name)) {
											current^ = u32(textureIdx)
											graphicsData.reloadBuffers = true
										}
									}
								}
							}
						}
					}
				}
			}
		}

		if imgui.CollapsingHeader("Cameras##header") {
			for &camera in scene.cameras {
				if ImRefl.draw_value(camera.name, camera) {
					sceneEdited(graphicsData)
				}
			}
		}

		if imgui.CollapsingHeader("Lights##header") {
			for &light in scene.lights {
				if ImRefl.draw_value(light.name, light) {
					sceneEdited(graphicsData)
				}
			}
		}

		if imgui.CollapsingHeader("Models##header") {
			if imgui.Button("Add New Model") {
				uiData.lockInput = true
				imgui.OpenPopup("New Model")
			}

			for &model in scene.models {
				if ImRefl.draw_value(model.name, model) {
					sceneEdited(graphicsData)
				}
			}
		}

		if imgui.CollapsingHeader("Textures##header") {
			if imgui.Button("Add New Texture") {
				uiData.lockInput = true
				imgui.OpenPopup("New Texture")
			}

			for &texture in scene.textures {
				ImRefl.draw_value(texture.name, texture)
			}
		}
	}

	if imgui.BeginPopupModal("New Scene") {
		createComponentInfo := &uiData.createComponentInfo
		imgui.Text("Name:")
		imgui.SameLine()
		imgui.InputText("##scenename", cstring(&createComponentInfo.name[0]), len(createComponentInfo.name))

		imgui.Text("Save Path:")
		imgui.SameLine()
		imgui.InputText("##savepath", cstring(&createComponentInfo.savePath[0]), len(createComponentInfo.savePath))
		imgui.SameLine()
		if imgui.Button("Browse##save") {
			absPath, _ := filepath.abs(SCENE_PATH(), context.temp_allocator)
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
			name := bufferText(&createComponentInfo.name)
			savePath := bufferText(&createComponentInfo.savePath)

			if name != "" && savePath != "" {
				path, oerr := os.replace_path_separators(
					savePath,
					'/',
					context.temp_allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				} else if newScene(name, path) {
					clearComponentData(createComponentInfo)
					uiData.lockInput = false
					imgui.CloseCurrentPopup()
				}
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
			absPath, _ := filepath.abs(ASSETS_PATH(), context.temp_allocator)
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
			absPath, _ := filepath.abs(RESOURCE_PATH(), context.temp_allocator)
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
			oerr: os.Error

			if createComponentInfo.name[0] != 0 &&
			   createComponentInfo.savePath[0] != 0 &&
			   createComponentInfo.assetPath[0] != 0 {
				name, oerr = os.replace_path_separators(
					string(createComponentInfo.name[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				path, oerr = os.replace_path_separators(
					string(createComponentInfo.savePath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				assetPath, oerr = os.replace_path_separators(
					string(createComponentInfo.assetPath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
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
			absPath, _ := filepath.abs(ASSETS_PATH(), context.temp_allocator)
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
			absPath, _ := filepath.abs(RESOURCE_PATH(), context.temp_allocator)
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
			oerr: os.Error

			if createComponentInfo.name[0] != 0 &&
			   createComponentInfo.savePath[0] != 0 &&
			   createComponentInfo.assetPath[0] != 0 {
				name, oerr = os.replace_path_separators(
					string(createComponentInfo.name[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				path, oerr = os.replace_path_separators(
					string(createComponentInfo.savePath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				assetPath, oerr = os.replace_path_separators(
					string(createComponentInfo.assetPath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
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
