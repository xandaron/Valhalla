package Valhalla

Object :: struct {
	name:        string,
	flags:       ObjectFlags,
	position:    Vec3 `imrefl:"speed=0.1"`,
	rotation:    Quat `imrefl:"euler"`,
	scale:       Vec3 `imrefl:"speed=0.1"`,
	// Hand-written in the editor rather than reflected. Changing modelIdx has to resize
	// textureIdxs and the animation state to the new model, instanceIdx is bookkeeping that
	// model.instances mirrors, and textureIdxs is an index into scene.textures. None of that is a
	// plain assignment, so reflection must not offer one.
	modelIdx:    u32 `imrefl:"ignore"`,
	instanceIdx: u32 `imrefl:"ignore"`,
	textureIdxs: [][TextureIndex]u32 `imrefl:"ignore"`,
	animation:   ObjectAnimation,
	// targetIdx indexes scene.objects and bindpointIdx indexes that model's bindpoints; both are
	// only checked for >= 0, so a free-form integer here reads out of bounds.
	attachment:  Attachment `imrefl:"ignore"`,
}

ObjectFlag :: enum u64 {
	Selectable = 0,
}
ObjectFlags :: bit_set[ObjectFlag;u64]

deleteGameObject :: proc(object: ^Object) {
	delete(object.name)
	delete(object.textureIdxs)
	deleteObjectAnimation(&object.animation)
}

Attachment :: struct {
	targetIdx:    i32,
	bindpointIdx: u32,
}

changeModel :: proc(scene: ^Scene, objectIdx: u32, modelIdx: u32) {
	object := &scene.objects[objectIdx]
	model := &scene.models[object.modelIdx]

	// Remove from old model's instance list
	removeInstance(scene, model, object.instanceIdx)

	// Add to new model's instance list
	object.modelIdx = modelIdx
	object.instanceIdx = addInstance(scene, &scene.models[modelIdx], objectIdx)
}

Texture :: struct {
	path:      string,
	assetPath: string,
	name:      string,
	// I want to transition to having multiple vk.Images and binding them as opposed to how I do it right now.
	// vkImage: vk.Image,
	// memory:  vk.DeviceMemory,
	// view:    vk.ImageView,
	// format:  vk.Format,
	// sampler: u32,
}

deleteTexture :: proc(texture: ^Texture) {
	delete(texture.name)
	delete(texture.path)
	delete(texture.assetPath)
}

Model :: struct {
	path:       string,
	assetPath:  string,
	name:       string,
	position:   Vec3 `imrefl:"speed=0.1"`,
	rotation:   Quat `imrefl:"euler"`,
	scale:      Vec3 `imrefl:"speed=0.1"`,
	meshes:     []Mesh `imrefl:"ignore"`,
	skeleton:   []Bone `imrefl:"ignore"`,
	animations: []Animation `imrefl:"read-only"`,
	bindpoints: [dynamic]Bindpoint,
	instances:  [dynamic]u32 `imrefl:"read-only"`,
}

deleteModel :: proc(model: ^Model) {
	delete(model.name)
	delete(model.path)
	delete(model.assetPath)

	for &mesh in model.meshes {
		deleteMesh(&mesh)
	}
	delete(model.meshes)

	for &bone in model.skeleton {
		deleteBone(&bone)
	}
	delete(model.skeleton)

	for &animation in model.animations {
		deleteAnimation(&animation)
	}
	delete(model.animations)

	for &bindpoint in model.bindpoints {
		deleteBindpoint(&bindpoint)
	}
	delete(model.bindpoints)

	delete(model.instances)
}

Mesh :: struct {
	name:                      string,
	vertexOffset, vertexCount: u32,
	indexOffset, indexCount:   u32,
	boundingBox:               AABB,
	bindpoints:                []Bindpoint,
}

deleteMesh :: proc(mesh: ^Mesh) {
	delete(mesh.name)
}

addInstance :: proc(scene: ^Scene, model: ^Model, objectIdx: u32) -> u32 {
	append(&model.instances, objectIdx)

	scene.boneCount += len(model.skeleton)
	for &mesh in model.meshes {
		scene.vertexCount += mesh.vertexCount
	}
	return u32(len(model.instances) - 1)
}

removeInstance :: proc(scene: ^Scene, model: ^Model, instanceIdx: u32) {
	unordered_remove(&model.instances, instanceIdx) // Replace with last
	if u32(len(model.instances)) > instanceIdx {
		// Update the moved instance's index
		scene.objects[model.instances[instanceIdx]].instanceIdx = instanceIdx
	}

	scene.boneCount -= len(model.skeleton)
	for &mesh in model.meshes {
		scene.vertexCount -= mesh.vertexCount
	}
}

AABB :: struct {
	min, max: Vec3,
}

Bindpoint :: struct {
	name:         string,
	boneIdx:      u32,
	offsetMatrix: Mat4,
}

deleteBindpoint :: proc(bindpoint: ^Bindpoint) {
	delete(bindpoint.name)
}

Camera :: struct {
	name:   string,
	mode:   CameraMode,
	eye:    Vec3 `imrefl:"speed=0.1"`,
	center: Vec3 `imrefl:"speed=0.1"`,
	up:     Vec3 `imrefl:"speed=0.1,normalized"`,
	fov:    f32 `imrefl:"min=1,max=179,speed=0.1"`,
	near:   f32 `imrefl:"min=0.001,max=1000,speed=0.1"`,
	far:    f32 `imrefl:"min=0.002,max=10000,speed=0.1"`,
}

deleteCamera :: proc(camera: ^Camera) {
	delete(camera.name)
}

CameraMode :: enum {
	PERSPECTIVE,
	ORTHOGRAPHIC,
}

view :: #force_inline proc(camera: Camera) -> Mat4 {
	return lookAt(camera.eye, camera.center, camera.up)
}

projection :: proc(camera: Camera) -> Mat4 {
	switch camera.mode {
	case .PERSPECTIVE:
		return perspective(
			radians(camera.fov),
			getRenderAspectRatio(&globals.graphicsData),
			camera.near,
			camera.far,
		)
	case .ORTHOGRAPHIC:
		return orthographic(
			radians(camera.fov),
			getRenderAspectRatio(&globals.graphicsData),
			camera.near,
			camera.far,
		)
	}
	panic("Unreachable!")
}

PointLight :: struct {
	name:     string,
	position: Vec3 `imrefl:"speed=0.1"`,
	colour:   Vec3 `imrefl:"colour"`,
	lumens:   f32 `imrefl:"min=0,max=100000,speed=10"`,
}

deletePointLight :: proc(light: ^PointLight) {
	delete(light.name)
}
