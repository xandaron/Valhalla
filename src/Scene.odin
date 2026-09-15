package Valhalla

import "core:strings"

Scene :: struct {
	path:         string,
	name:         string,

	// Scene Settings
	ambientLight: f32,
	clearColour:  Vec4,

	// Assets
	models:       [dynamic]Model,
	textures:     [dynamic]Texture,
	objects:      [dynamic]Object,
	lights:       [dynamic]PointLight,
	cameras:      [dynamic]Camera,
	activeCamera: u32,
	vertexCount:  u32,
	vertices:     [dynamic]Vertex,
	indices:      [dynamic]u32,
	boneCount:    int,

	// Graphics Data
	buffers:      SceneBuffers,
}

deleteScene :: proc(scene: ^Scene) {
	delete(scene.name)
	delete(scene.path)

	for &model in scene.models {
		deleteModel(&model)
	}
	delete(scene.models)

	for &texture in scene.textures {
		deleteTexture(&texture)
	}
	delete(scene.textures)

	for &object in scene.objects {
		deleteGameObject(&object)
	}
	delete(scene.objects)

	for &light in scene.lights {
		deletePointLight(&light)
	}
	delete(scene.lights)

	for &camera in scene.cameras {
		deleteCamera(&camera)
	}
	delete(scene.cameras)

	delete(scene.vertices)
	delete(scene.indices)

	if &globals.scenes[globals.activeScene] == scene {
		if res := waitDeviceIdle(&globals.graphicsData); res != nil {
			panic("Failed to wait for device idle?")
		}
	}
	deleteSceneBuffers(&globals.graphicsData, &scene.buffers)
}

newScene :: proc(name, path: string) -> bool {
	graphicsData := &globals.graphicsData

	scene := Scene {
		name         = strings.clone(name),
		path         = strings.clone(path),
		ambientLight = 0.35,
		clearColour  = {0.05, 0.06, 0.08, 1},
	}

	created := false
	defer if !created {
		deleteScene(&scene)
	}

	append(&scene.models, Model{path = strings.clone(MODELS_PATH + "cube.model")})
	model := &scene.models[0]
	if err := loadModelComponent(model); err != .None {
		logf(.Error, "Failed to load the cube model component: %v", err)
		return false
	}
	if err := loadModel(&scene, model); err != .None {
		logf(.Error, "Failed to load the cube model: %v", err)
		return false
	}

	texturePaths := [?]string {
		TEXTURES_PATH + "cube.texture",
		TEXTURES_PATH + "blank_normal.texture",
	}
	assetPaths := make([]string, len(texturePaths), context.temp_allocator)
	for texturePath, i in texturePaths {
		append(&scene.textures, Texture{path = strings.clone(texturePath)})
		if err := loadTextureComponent(&scene.textures[i]); err != .None {
			logf(.Error, "Failed to load texture component \"%s\": %v", texturePath, err)
			return false
		}
		assetPaths[i] = scene.textures[i].assetPath
	}
	if err := loadImages(graphicsData, &scene, assetPaths); err != nil {
		logf(.Error, "Failed to load the new scene's images: %v", err)
		return false
	}

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
			position = Vec3{2, 3, -4},
			colour = Vec3{1, 1, 1},
			lumens = 1600,
		},
	)

	scene.boneCount = 1
	textureIdxs := make([][TextureIndex]u32, len(model.meshes))
	for &meshTextures in textureIdxs {
		meshTextures[.Albedo] = 0
		meshTextures[.NormalMap] = 1
	}

	append(
		&scene.objects,
		Object {
			name = strings.clone("Cube"),
			position = Vec3{0, 0, 0},
			rotation = IQUAT,
			scale = Vec3{1, 1, 1},
			modelIdx = 0,
			instanceIdx = addInstance(&scene, model, 0),
			textureIdxs = textureIdxs,
			animation = ObjectAnimation {
				idx = -1,
				state = make([]Mat4, len(model.skeleton)),
				cache = make([]ObjectAnimationCache, len(model.skeleton)),
			},
			attachment = Attachment{targetIdx = -1, bindpointIdx = 0},
		},
	)

	if err := saveScene(&scene); err != .None {
		logf(.Error, "Failed to save the new scene to \"%s\": %v", scene.path, err)
		return false
	}

	append(&globals.scenes, scene)
	globals.activeScene = u32(len(globals.scenes) - 1)
	graphicsData.reloadBuffers = true
	markCommandsDirty(graphicsData, DIRTY_ALL)

	created = true
	return true
}

addObject :: proc(scene: ^Scene, modelIdx: u32) {
	append(
		&scene.objects,
		Object {
			name = strings.clone("new_object"),
			position = Vec3{0, 0, 0},
			rotation = IQUAT,
			scale = Vec3{1, 1, 1},
			modelIdx = modelIdx,
			instanceIdx = addInstance(scene, &scene.models[modelIdx], u32(len(scene.objects))),
			textureIdxs = make([][TextureIndex]u32, len(scene.models[modelIdx].meshes)),
			animation = ObjectAnimation {
				idx = -1,
				state = make([]Mat4, len(scene.models[modelIdx].skeleton)),
				cache = make([]ObjectAnimationCache, len(scene.models[modelIdx].skeleton)),
			},
			attachment = {targetIdx = -1, bindpointIdx = 0},
		},
	)
}

