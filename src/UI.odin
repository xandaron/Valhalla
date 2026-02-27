package Valhalla

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../imgui"
import tinyfd "../tinyfiledialogs"


UIData :: struct {
	lockInput:           bool,
	createComponentInfo: CreateComponentData,
	showUI:              bool,
	showMetrics:         bool,
	objectInspector:     ^Object,
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
		oerr: os.Error
		scene.path, oerr = os.replace_path_separators(relPath, '/', context.allocator)
		if oerr != nil {
			log(.Error, "Failed to replace path seperators!")
		}
		saveScene(scene)
	}
}

toCstring :: #force_inline proc(str: string, allocator := context.temp_allocator) -> cstring {
	return strings.clone_to_cstring(str, allocator = allocator)
}

drawImgui :: proc() {
	uiData := &globals.uiData
	dockspaceID := imgui.Gui_GetID("Screen Dock")
	viewport := imgui.Gui_GetMainViewport()

	if imgui.Gui_DockBuilderGetNode(dockspaceID) == nil {
		imgui.Gui_DockBuilderAddNodeEx(
			dockspaceID,
			transmute(imgui.GuiDockNodeFlags)(u32(1 << 10)),
		)
		imgui.Gui_DockBuilderSetNodeSize(dockspaceID, viewport.Size)

		main, leftDock, rightDock: imgui.GuiID
		main = dockspaceID
		imgui.Gui_DockBuilderSplitNode(dockspaceID, .Left, .2, &leftDock, &main)
		imgui.Gui_DockBuilderSplitNode(dockspaceID, .Right, .25, &rightDock, &main)

		imgui.Gui_DockBuilderDockWindow("Scene Inspector", leftDock)
		imgui.Gui_DockBuilderDockWindow("Object Inspector", rightDock)
		imgui.Gui_DockBuilderFinish(dockspaceID)
	}
	imgui.Gui_DockSpaceOverViewportEx(
		dockspaceID,
		viewport,
		{.PassthruCentralNode, .NoDockingOverCentralNode, .NoUndocking},
		nil,
	)

	if !uiData.showUI {
		return
	}

	if uiData.showMetrics {
		imgui.Gui_SetNextWindowBgAlpha(1.0)
		imgui.Gui_ShowMetricsWindow(nil)
	}

	imgui.Gui_SetNextWindowBgAlpha(1.0)
	sceneInspector()

	if uiData.objectInspector != nil {
		objectInspector(uiData.objectInspector)
	}

	newScenePopup()
	newModelPopup()
	newTexturePopup()
}

sceneInspector :: proc() {
	uiData := &globals.uiData

	defer imgui.Gui_End()
	if !imgui.Gui_Begin("Scene Inspector", nil, {.MenuBar}) {
		return
	}

	scene := &globals.scenes[globals.activeScene]
	if imgui.Gui_BeginMenuBar() {
		if imgui.Gui_BeginMenu("File") {
			if imgui.Gui_MenuItem("Open") {
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
				path, oerr := os.replace_path_separators(relPath, '/', context.allocator)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}
				append(&globals.scenes, Scene{path = path})
				loadScene(&globals.scenes[len(globals.scenes) - 1])
			}

			if imgui.Gui_MenuItem("Save") {
				if scene.path != "" {
					saveScene(scene)
				} else {
					saveAs(scene)
				}
			}

			if imgui.Gui_MenuItem("Save As...") {
				saveAs(scene)
			}

			if imgui.Gui_MenuItem("Close") {
				saveScene(scene)
				if len(globals.scenes) > 1 {
					deleteScene(scene)
					unordered_remove(&globals.scenes, globals.activeScene)
					globals.activeScene = 0
					scene := &globals.scenes[0]
				}
			}

			imgui.Gui_SeparatorText("Assets")
			if imgui.Gui_BeginMenu("Import") {
				if imgui.Gui_MenuItem("Model") {
					path := tinyfd.openFileDialog("Open Model", MODELS_PATH, 0, nil, nil, 0)
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

				if imgui.Gui_MenuItem("Texture") {
					path := tinyfd.openFileDialog("Open Texture", TEXTURES_PATH, 0, nil, nil, 0)
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
						path, oerr := os.replace_path_separators(relPath, '/', context.allocator)
						if oerr != nil {
							log(.Error, "Failed to replace path seperators!")
						}
						append(&scene.textures, Texture{path = path})
						texture := &scene.textures[len(scene.textures) - 1]
						if err := loadTextureComponent(texture); err != nil {
							logf(.Error, "Failed to load texture: %v", err)
							delete(texture.path)
							unordered_remove(&scene.textures, len(scene.textures) - 1)
						} else {
							err := addImages(
								&globals.graphicsData,
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
				imgui.Gui_EndMenu()
			}
			imgui.Gui_EndMenu()
		}
		imgui.Gui_EndMenuBar()
	}

	if imgui.Gui_CollapsingHeader("Settings##header", nil) {
		if imgui.Gui_Button("New Scene") {
			uiData.lockInput = true
			imgui.Gui_OpenPopup("New Scene", nil)
		}

		imgui.Gui_SameLine()
		if imgui.Gui_BeginCombo("Scene", toCstring(scene.name), nil) {
			for &scene, sceneIdx in globals.scenes {
				if globals.activeScene == u32(sceneIdx) {
					continue
				}
				if imgui.Gui_Selectable(toCstring(scene.name)) {
					globals.activeScene = u32(sceneIdx)

					globals.graphicsData.reloadBuffers = true
					globals.graphicsData.rerecordCommands = true
				}
			}
			imgui.Gui_EndCombo()
		}

		if imgui.Gui_DragFloatEx(
			"Contrast",
			&globals.graphicsData.contrast,
			0.01,
			0,
			0,
			"%.3f",
			nil,
		) {
			globals.graphicsData.reloadBuffers = true
		}
		if imgui.Gui_DragFloatEx(
			"Brightness",
			&globals.graphicsData.brightness,
			0.01,
			0,
			0,
			"%.3f",
			nil,
		) {
			globals.graphicsData.reloadBuffers = true
		}
		if imgui.Gui_DragFloatEx(
			"Saturation",
			&globals.graphicsData.saturation,
			0.01,
			0,
			0,
			"%.3f",
			nil,
		) {
			globals.graphicsData.reloadBuffers = true
		}
		if imgui.Gui_DragFloatEx(
			"Exposure",
			&globals.graphicsData.exposure,
			0.01,
			0,
			0,
			"%.3f",
			nil,
		) {
			globals.graphicsData.reloadBuffers = true
		}
		if imgui.Gui_DragFloatEx(
			"Exposure Cap",
			&globals.graphicsData.maxExposure,
			0.01,
			0,
			0,
			"%.3f",
			nil,
		) {
			globals.graphicsData.reloadBuffers = true
		}
		if imgui.Gui_Combo(
			"Tonemapper",
			transmute(^i32)(&globals.graphicsData.tonemapper),
			"None\000Narkowicz ACES\000",
		) {
			globals.graphicsData.reloadBuffers = true
		}
		if imgui.Gui_DragFloatEx("Gamma", &globals.graphicsData.gamma, 0.01, 0, 0, "%.3f", nil) {
			globals.graphicsData.reloadBuffers = true
		}
	}

	if imgui.Gui_CollapsingHeader("Scene##header", nil) {
		if imgui.Gui_DragFloatEx(
			"Ambient light##scene",
			&scene.ambientLight,
			0.01,
			0,
			1,
			"%.3f",
			nil,
		) {
			globals.graphicsData.reloadBuffers = true
		}
		if imgui.Gui_DragFloat4Ex(
			"Clear colour##scene",
			&scene.clearColour,
			0.01,
			0,
			1,
			"%.3f",
			nil,
		) {
			globals.graphicsData.reloadBuffers = true
		}
	}

	if imgui.Gui_CollapsingHeader("Objects##header", nil) {
		if imgui.Gui_Button("New Object##objects") {
			addObject(scene, 0)

			globals.graphicsData.reloadBuffers = true
			globals.graphicsData.rerecordCommands = true
		}

		for &object, objectIdx in scene.objects {
			if imgui.Gui_Button(fmt.ctprintf("%s##object%v", object.name, objectIdx)) {
				uiData.objectInspector = &object
			}
		}
	}

	if imgui.Gui_CollapsingHeader("Cameras##header", nil) {
		for &camera, cameraIdx in scene.cameras {
			suffix := fmt.tprintf("##camera%v", cameraIdx)
			if imgui.Gui_TreeNode(toCstring(camera.name)) {
				if imgui.Gui_BeginCombo(
					fmt.ctprintf("Mode%s", suffix),
					toCstring(fmt.tprintf("%v", camera.mode)),
					nil,
				) {
					for mode in CameraMode {
						if mode == camera.mode {
							continue
						}

						if imgui.Gui_Selectable(toCstring(fmt.tprintf("%v", mode))) {
							camera.mode = mode
						}
					}
					imgui.Gui_EndCombo()
				}

				imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Eye%s", suffix),
					&camera.eye,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)
				imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Center%s", suffix),
					&camera.center,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)
				imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Up%s", suffix),
					&camera.up,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)

				imgui.Gui_DragFloatEx(
					fmt.ctprintf("FOV%s", suffix),
					&camera.fov,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)
				imgui.Gui_DragFloatEx(
					fmt.ctprintf("Near Plane%s", suffix),
					&camera.near,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)
				imgui.Gui_DragFloatEx(
					fmt.ctprintf("Far Plane%s", suffix),
					&camera.far,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)

				imgui.Gui_TreePop()
			}
		}
	}

	if imgui.Gui_CollapsingHeader("Lights##header", nil) {
		for &light, lightIdx in scene.lights {
			suffix := fmt.tprintf("##light%v", lightIdx)
			if imgui.Gui_TreeNode(toCstring(light.name)) {
				imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Position%v", suffix),
					&light.position,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)
				imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Colour%v", suffix),
					&light.colour,
					0.01,
					0,
					1,
					"%.3f",
					nil,
				)
				imgui.Gui_DragFloatEx(
					fmt.ctprintf("Brightness%v", suffix),
					&light.brightness,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)
				imgui.Gui_DragFloatEx(
					fmt.ctprintf("Dropoff%v", suffix),
					&light.dropoff,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)

				imgui.Gui_TreePop()
			}
		}
	}

	if imgui.Gui_CollapsingHeader("Models##header", nil) {
		if imgui.Gui_Button("Add New Model") {
			uiData.lockInput = true
			imgui.Gui_OpenPopup("New Model", nil)
		}

		for &model, modelIdx in scene.models {
			suffix := fmt.tprintf("##model%v", modelIdx)
			if imgui.Gui_TreeNode(toCstring(model.name)) {
				imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Position%v", suffix),
					&model.position,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)

				x, y, z := quatToEuler(model.rotation)
				rotation := Vec3{degrees(x), degrees(y), degrees(z)}
				if imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Rotation%v", suffix),
					&rotation,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				) {
					model.rotation = quatFromEuler(
						radians(rotation.x),
						radians(rotation.y),
						radians(rotation.z),
						.XYZ,
					)
				}

				imgui.Gui_DragFloat3Ex(
					fmt.ctprintf("Scale%v", suffix),
					&model.scale,
					0.1,
					0,
					0,
					"%.3f",
					nil,
				)
				imgui.Gui_TreePop()
			}
		}
	}

	if imgui.Gui_CollapsingHeader("Textures##header", nil) {
		if imgui.Gui_Button("Add New Texture") {
			uiData.lockInput = true
			imgui.Gui_OpenPopup("New Texture", nil)
		}

		for &texture, textureIdx in scene.textures {
			suffix := fmt.tprintf("##texture%v", textureIdx)
			if imgui.Gui_TreeNode(toCstring(texture.name)) {
				imgui.Gui_Text("Asset Path: ")
				imgui.Gui_SameLine()
				imgui.Gui_Text(toCstring(texture.assetPath))
				imgui.Gui_TreePop()
			}
		}
	}
}

objectInspector :: proc(object: ^Object) {
	uiData := &globals.uiData
	defer imgui.Gui_End()
	if !imgui.Gui_Begin("Object Inspector", nil, {}) {
		return
	}

	scene := &globals.scenes[globals.activeScene]
	imgui.Gui_DragFloat3Ex("Position##objectinspector", &object.position, 0.1, 0, 0, "%.3f", nil)

	x, y, z := quatToEuler(object.rotation)
	x = degrees(x)
	y = degrees(y)
	z = degrees(z)
	rotation := Vec3{x, y, z}
	if imgui.Gui_DragFloat3Ex("Rotation##objectinspector", &rotation, 0.1, 0, 0, "%.3f", nil) {
		delta := rotation - Vec3{x, y, z}
		object.rotation *= quatFromEuler(
			radians(delta.x),
			radians(delta.y),
			radians(delta.z),
			.XYZ,
		)
	}
	imgui.Gui_DragFloat3Ex("Scale##objectinspector", &object.scale, 0.1, 0, 0, "%.3f", nil)

	if imgui.Gui_TreeNode("Flags:##objectinspector") {
		for flag in ObjectFlag {
			present := flag in object.flags
			if imgui.Gui_Checkbox(fmt.ctprintf("%v##objectinspector", flag), &present) {
				if present {
					object.flags += {flag}
				} else {
					object.flags -= {flag}
				}
			}
		}
		imgui.Gui_TreePop()
	}

	imgui.Gui_SeparatorText("Animation##objectinspector")
	animationData := &object.animation
	if len(scene.models[object.modelIdx].animations) > 0 {
		animationName: string
		if animationData.idx >= 0 {
			animationName = scene.models[object.modelIdx].animations[animationData.idx].name
		} else {
			animationName = "None"
		}

		if imgui.Gui_BeginCombo("Animation Clip##objectinspector", toCstring(animationName), nil) {
			if animationData.idx >= 0 {
				if imgui.Gui_Selectable("None") {
					animationData.idx = -1
					animationData.timer = 0
				}
			}

			for &animation, animationIdx in scene.models[object.modelIdx].animations {
				if i32(animationIdx) == animationData.idx {
					continue
				}

				if imgui.Gui_Selectable(toCstring(animation.name)) {
					animationData.idx = i32(animationIdx)
					animationData.timer = 0
					for &node in animationData.cache {
						node.positionIdx = 0
						node.rotationIdx = 0
						node.scaleIdx = 0
					}
				}
			}
			imgui.Gui_EndCombo()
		}
	}

	imgui.Gui_Checkbox("Playing##objectinspector", &animationData.playing)

	timer := f32(animationData.timer)
	if imgui.Gui_DragFloatEx("Animation time##objectinspector", &timer, 0.01, 0, 0, "%.3f", nil) {
		animationData.timer = f64(timer)
	}

	if imgui.Gui_BeginCombo(
		"Animation Behavior##objectinspector",
		fmt.ctprintf("%v", animationData.end.behavior),
		nil,
	) {
		for behavior in AnimationBehavior {
			if behavior == animationData.end.behavior {
				continue
			}

			if imgui.Gui_Selectable(fmt.ctprintf("%v", behavior)) {
				animationData.end.behavior = behavior
			}
		}
		imgui.Gui_EndCombo()
	}

	if imgui.Gui_BeginCombo(
		"Model##objectinspector",
		toCstring(scene.models[object.modelIdx].name),
		nil,
	) {
		for modelIdx in 0 ..< len(scene.models) {
			if u32(modelIdx) == object.modelIdx {
				continue
			}

			model := &scene.models[modelIdx]
			if imgui.Gui_Selectable(toCstring(model.name)) {
				objectIdx := 0
				for &obj, idx in scene.objects {
					if &obj == object {
						objectIdx = idx
						break
					}
				}

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
				object.animation.cache = make([]ObjectAnimationCache, len(model.skeleton))

				globals.graphicsData.reloadBuffers = true
				globals.graphicsData.rerecordCommands = true
			}
		}
		imgui.Gui_EndCombo()
	}

	for mesh, meshIdx in scene.models[object.modelIdx].meshes {
		meshSuffix := fmt.ctprintf("##objectinspector_mesh%v", meshIdx)
		if imgui.Gui_TreeNode(toCstring(mesh.name)) {
			if imgui.Gui_BeginCombo(
				fmt.ctprintf("Albedo%v", meshSuffix),
				toCstring(scene.textures[object.textureIdxs[meshIdx][.Albedo]].name),
				nil,
			) {
				for &texture, textureIdx in scene.textures {
					if object.textureIdxs[meshIdx][.Albedo] == u32(textureIdx) {
						continue
					}

					if imgui.Gui_Selectable(toCstring(texture.name)) {
						object.textureIdxs[meshIdx][.Albedo] = u32(textureIdx)
						globals.graphicsData.reloadBuffers = true
					}
				}
				imgui.Gui_EndCombo()
			}

			if imgui.Gui_BeginCombo(
				fmt.ctprintf("Normal Map%v", meshSuffix),
				toCstring(scene.textures[object.textureIdxs[meshIdx][.NormalMap]].name),
				nil,
			) {
				for &texture, textureIdx in scene.textures {
					if object.textureIdxs[meshIdx][.NormalMap] == u32(textureIdx) {
						continue
					}
					if imgui.Gui_Selectable(toCstring(texture.name)) {
						object.textureIdxs[meshIdx][.NormalMap] = u32(textureIdx)
						globals.graphicsData.reloadBuffers = true
					}
				}
				imgui.Gui_EndCombo()
			}
			imgui.Gui_TreePop()
		}
	}
}

newScenePopup :: proc() {
	uiData := &globals.uiData

	if !imgui.Gui_BeginPopupModal("New Scene", nil, nil) {
		return
	}

	createComponentInfo := &uiData.createComponentInfo
	imgui.Gui_Text("Name:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText(
		"##scenename",
		cstring(&createComponentInfo.name[0]),
		len(createComponentInfo.name),
		nil,
	)

	imgui.Gui_Text("Save Path:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText(
		"##savepath",
		cstring(&createComponentInfo.savePath[0]),
		len(createComponentInfo.savePath),
		nil,
	)
	imgui.Gui_SameLine()
	if imgui.Gui_Button("Browse##save") {
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
			overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
		}
	}

	if imgui.Gui_Button("Create") {
		scene := &globals.scenes[globals.activeScene]

		if createComponentInfo.name[0] != 0 && createComponentInfo.savePath[0] != 0 {
			name, path: string
			oerr: os.Error

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
					textureIdxs = make([][TextureIndex]u32, 1),
					animation = ObjectAnimation{idx = -1},
					attachment = Attachment{targetIdx = -1},
				},
			)
			addInstance(scene, &scene.models[0], 0)

			clearComponentData(createComponentInfo)
			uiData.lockInput = false
			imgui.Gui_CloseCurrentPopup()
		}
	}

	imgui.Gui_SameLine()
	if imgui.Gui_Button("Cancel") {
		imgui.Gui_CloseCurrentPopup()
		uiData.lockInput = false
		clearComponentData(createComponentInfo)
	}
	imgui.Gui_End()
}

newModelPopup :: proc() {
	uiData := &globals.uiData

	if !imgui.Gui_BeginPopupModal("New Model", nil, nil) {
		return
	}

	createComponentInfo := &uiData.createComponentInfo
	imgui.Gui_Text("Name:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText("##texturename", cstring(&createComponentInfo.name[0]), 100, nil)

	imgui.Gui_Text("Image Path:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText("##texturepath", cstring(&createComponentInfo.assetPath[0]), 100, nil)
	imgui.Gui_SameLine()
	if imgui.Gui_Button("Browse##texture") {
		absPath, _ := filepath.abs(ASSETS_PATH, context.temp_allocator)
		str := tinyfd.openFileDialog("Load Image", fmt.ctprintf("%s/", absPath), 0, nil, nil, 0)
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
			overwriteBuffer(&createComponentInfo.assetPath, transmute([]byte)relPath)
		}
	}

	imgui.Gui_Text("Save Path:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText("##savepath", cstring(&createComponentInfo.savePath[0]), 100, nil)
	imgui.Gui_SameLine()
	if imgui.Gui_Button("Browse##save") {
		absPath, _ := filepath.abs(MODELS_PATH, context.temp_allocator)
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
			overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
		}
	}

	if imgui.Gui_Button("Create") {
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
			imgui.Gui_CloseCurrentPopup()
		}
	}

	imgui.Gui_SameLine()
	if imgui.Gui_Button("Cancel") {
		imgui.Gui_CloseCurrentPopup()
		uiData.lockInput = false
		clearComponentData(createComponentInfo)
	}
	imgui.Gui_End()
}

newTexturePopup :: proc() {
	uiData := &globals.uiData

	if !imgui.Gui_BeginPopupModal("New Texture", nil, nil) {
		return
	}

	createComponentInfo := &uiData.createComponentInfo
	imgui.Gui_Text("Name:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText("##texturename", cstring(&createComponentInfo.name[0]), 100, nil)

	imgui.Gui_Text("Image Path:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText("##texturepath", cstring(&createComponentInfo.assetPath[0]), 100, nil)
	imgui.Gui_SameLine()
	if imgui.Gui_Button("Browse##texture") {
		absPath, _ := filepath.abs(ASSETS_PATH, context.temp_allocator)
		str := tinyfd.openFileDialog("Load Image", fmt.ctprintf("%s/", absPath), 0, nil, nil, 0)
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
			overwriteBuffer(&createComponentInfo.assetPath, transmute([]byte)relPath)
		}
	}

	imgui.Gui_Text("Save Path:")
	imgui.Gui_SameLine()
	imgui.Gui_InputText("##savepath", cstring(&createComponentInfo.savePath[0]), 100, nil)
	imgui.Gui_SameLine()
	if imgui.Gui_Button("Browse##save") {
		absPath, _ := filepath.abs(MODELS_PATH, context.temp_allocator)
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
			overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
		}
	}

	if imgui.Gui_Button("Create") {
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
			imgui.Gui_CloseCurrentPopup()
		}
	}

	imgui.Gui_SameLine()
	if imgui.Gui_Button("Cancel") {
		imgui.Gui_CloseCurrentPopup()
		uiData.lockInput = false
		clearComponentData(createComponentInfo)
	}
	imgui.Gui_End()
}

ImguiAllocatorData :: mem.Allocator

// Using a tracking allocator we wont know eactly which line allocated the leaked memory
// but we will know that something was allocated that wasn't freed.
imguiAlloc :: proc "c" (sz: c.size_t, user_data: rawptr) -> rawptr {
	context = runtime.default_context()
	allocator := (^ImguiAllocatorData)(user_data)^
	ptr, _ := mem.alloc(int(sz), allocator = allocator)
	return ptr
}

imguiFree :: proc "c" (ptr: rawptr, user_data: rawptr) {
	context = runtime.default_context()
	allocator := (^ImguiAllocatorData)(user_data)^
	mem.free(ptr, allocator = allocator)
}

