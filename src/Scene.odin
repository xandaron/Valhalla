package Valhalla

import "core:strings"

Scene :: struct {
	path:         string,
	name:         string,

	ambientLight: f32 `imrefl:"label=Ambient light,min=0,max=10,speed=0.01"`,
	clearColour:  Vec4 `imrefl:"label=Clear colour,colour"`,

	models:       [dynamic]Model,
	textures:     [dynamic]Texture,
	objects:      [dynamic]Object,
	lights:       [dynamic]PointLight,
	cameras:      [dynamic]Camera,
	activeCamera: u32,
	vertexCount:  u32,
	vertices:     [dynamic]Vertex `imrefl:"ignore"`,
	indices:      [dynamic]u32 `imrefl:"ignore"`,
	boneCount:    int,

	buffers:      SceneBuffers `imrefl:"ignore"`,
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

	if globals.project.defaultModel == "" ||
	   globals.project.defaultAlbedo == "" ||
	   globals.project.defaultNormal == "" {
		log(
			.Error,
			"Project declares no default model, albedo or normal, so there is nothing to put in a new scene.",
		)
		return false
	}

	append(&scene.models, Model{path = strings.clone(globals.project.defaultModel)})
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
		globals.project.defaultAlbedo,
		globals.project.defaultNormal,
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

changeModelAsset :: proc(scene: ^Scene, modelIdx: u32, assetPath: string) -> LoadError {
	vertexStart := len(scene.vertices)
	indexStart := len(scene.indices)
	replacement := Model {
		assetPath = strings.clone(assetPath),
	}
	if err := loadModel(scene, &replacement); err != .None {
		resize(&scene.vertices, vertexStart)
		resize(&scene.indices, indexStart)
		deleteModel(&replacement)
		return err
	}

	model := &scene.models[modelIdx]
	oldVertices := modelVertexCount(model)
	newVertices := modelVertexCount(&replacement)
	for _ in model.instances {
		scene.boneCount += len(replacement.skeleton) - len(model.skeleton)
		scene.vertexCount = scene.vertexCount - oldVertices + newVertices
	}

	if len(model.meshes) > 0 {
		vertexFirst, vertexEnd := max(u32), u32(0)
		indexFirst, indexEnd := max(u32), u32(0)
		for &mesh in model.meshes {
			vertexFirst = min(vertexFirst, mesh.vertexOffset)
			vertexEnd = max(vertexEnd, mesh.vertexOffset + mesh.vertexCount)
			indexFirst = min(indexFirst, mesh.indexOffset)
			indexEnd = max(indexEnd, mesh.indexOffset + mesh.indexCount)
		}
		remove_range(&scene.vertices, int(vertexFirst), int(vertexEnd))
		remove_range(&scene.indices, int(indexFirst), int(indexEnd))

		shift :: proc(meshes: []Mesh, vertexEnd, vertexCount, indexEnd, indexCount: u32) {
			for &mesh in meshes {
				if mesh.vertexOffset >= vertexEnd {
					mesh.vertexOffset -= vertexCount
				}
				if mesh.indexOffset >= indexEnd {
					mesh.indexOffset -= indexCount
				}
			}
		}
		for &other, otherIdx in scene.models {
			if u32(otherIdx) != modelIdx {
				shift(other.meshes, vertexEnd, vertexEnd - vertexFirst, indexEnd, indexEnd - indexFirst)
			}
		}
		shift(replacement.meshes, vertexEnd, vertexEnd - vertexFirst, indexEnd, indexEnd - indexFirst)
	}

	model.meshes, replacement.meshes = replacement.meshes, model.meshes
	model.skeleton, replacement.skeleton = replacement.skeleton, model.skeleton
	model.animations, replacement.animations = replacement.animations, model.animations
	model.assetPath, replacement.assetPath = replacement.assetPath, model.assetPath
	deleteModel(&replacement)

	for objectIdx in model.instances {
		object := &scene.objects[objectIdx]
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
		if int(object.animation.idx) >= len(model.animations) {
			object.animation.idx = -1
		}
		object.animation.timer = 0
	}
	return .None
}

@(private = "file")
modelVertexCount :: proc(model: ^Model) -> u32 {
	count: u32
	for &mesh in model.meshes {
		count += mesh.vertexCount
	}
	return count
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
