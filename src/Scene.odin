package Valhalla

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

deleteScene :: proc(graphicsData: ^GraphicsData, scene: ^Scene) {
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

	if res := waitDeviceIdle(graphicsData); res != nil {
		panic("Failed to wait for device idle?")
	}
	deleteSceneBuffers(graphicsData, &scene.buffers)
}
