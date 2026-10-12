package Valhalla

import "base:intrinsics"

Scene :: struct($Base, $ModelType, $TextureType, $ObjectType, $PointLightType: typeid) where
	intrinsics.type_is_struct(Base) &&
	intrinsics.type_is_specialization_of(ModelType, Model) &&
	intrinsics.type_is_specialization_of(TextureType, Texture) &&
	intrinsics.type_is_specialization_of(ObjectType, Object) &&
	intrinsics.type_is_specialization_of(PointLightType, PointLight) {
	using _:      Base `imrefl:"flatten"`,

	ambientLight: f32 `imrefl:"label=Ambient light,min=0,max=10,speed=0.01"`,
	clearColour:  Vec4 `imrefl:"label=Clear colour,colour"`,

	boneCount:    int,
	models:       [dynamic]ModelType,
	textures:     [dynamic]TextureType,
	objects:      [dynamic]ObjectType,
	lights:       [dynamic]PointLightType,
	vertexCount:  u32,
	vertices:     [dynamic]Vertex `imrefl:"ignore"`,
	indices:      [dynamic]u32 `imrefl:"ignore"`,

	buffers:      SceneBuffers `imrefl:"ignore"`,
}

deleteScene :: proc(graphicsData: ^GraphicsData, scene: ^Scene($SB, $M, $T, $O, $L)) {
	for &model in scene.models {
		deleteModel(&model)
	}
	delete(scene.models)

	delete(scene.textures)

	for &object in scene.objects {
		deleteGameObject(&object)
	}
	delete(scene.objects)

	delete(scene.lights)

	delete(scene.vertices)
	delete(scene.indices)

	if res := waitDeviceIdle(graphicsData); res != nil {
		panic("Failed to wait for device idle?")
	}
	deleteSceneBuffers(graphicsData, &scene.buffers)
}
