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

	deleteSceneBuffers(&globals.graphicsData, &scene.buffers)
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
			textureIdxs = make([][len(TextureIndex)]u32, len(scene.models[modelIdx].meshes)),
			animation = ObjectAnimation {
				idx = -1,
				state = make([]Mat4, len(scene.models[modelIdx].skeleton)),
				cache = make([]ObjectAnimationCache, len(scene.models[modelIdx].skeleton)),
			},
			attachment = {targetIdx = -1, bindpointIdx = 0},
		},
	)
}

