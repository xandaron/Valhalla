package Valhalla

Object :: struct {
	name:        string,
	position:    Vec3,
	rotation:    Quat,
	scale:       Vec3,
	modelIdx:    u32,
	instanceIdx: u32,
	textureIdxs: [][len(TextureIndex)]u32,
	animation:   ObjectAnimation,
	attachment:  Attachment,
}

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

Model :: struct {
	path:       string,
	assetPath:  string,
	name:       string,
	position:   Vec3,
	rotation:   Quat,
	scale:      Vec3,
	meshes:     []Mesh,
	skeleton:   []Bone,
	animations: []Animation,
	bindpoints: [dynamic]Bindpoint,
	instances:  [dynamic]u32, // Index of game objects using this model
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
	eye:    Vec3,
	center: Vec3,
	up:     Vec3,
	fov:    f32,
	near:   f32,
	far:    f32,
}

deleteCamera :: proc(camera: ^Camera) {
	delete(camera.name)
}

CameraMode :: enum {
	PERSPECTIVE,
	ORTHOGRAPHIC,
}

viewProjection :: proc(camera: Camera) -> Mat4 {
	switch camera.mode {
	case .PERSPECTIVE:
		return(
			perspective(
				radians(camera.fov),
				RENDER_SIZE.x / RENDER_SIZE.y,
				camera.near,
				camera.far,
			) *
			lookAt(camera.eye, camera.center, camera.up) \
		)
	case .ORTHOGRAPHIC:
		return(
			orthographic(
				radians(camera.fov),
				RENDER_SIZE.x / RENDER_SIZE.y,
				camera.near,
				camera.far,
			) *
			lookAt(camera.eye, camera.center, camera.up) \
		)
	}
	panic("Unreachable!")
}

PointLight :: struct {
	name:       string,
	position:   Vec3,
	colour:     Vec3,
	brightness: f32,
	dropoff:    f32,
}

deletePointLight :: proc(light: ^PointLight) {
	delete(light.name)
}
