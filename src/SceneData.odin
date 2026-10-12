package Valhalla

import "base:intrinsics"

Object :: struct($Base: typeid) where intrinsics.type_is_struct(Base) {
	using _:     Base `imrefl:"flatten"`,
	position:    Vec3 `imrefl:"label=Position,speed=0.1"`,
	rotation:    Quat `imrefl:"label=Rotation,euler"`,
	scale:       Vec3 `imrefl:"label=Scale,speed=0.1"`,
	modelIdx:    u32 `imrefl:"ignore"`,
	instanceIdx: u32 `imrefl:"ignore"`,
	textureIdxs: [][TextureIndex]u32 `imrefl:"ignore"`,
	animation:   ObjectAnimation,
	attachment:  Attachment `imrefl:"ignore"`,
}

deleteGameObject :: proc(object: ^Object($B)) {
	delete(object.textureIdxs)
	deleteObjectAnimation(&object.animation)
}

Attachment :: struct {
	targetIdx:    i32,
	bindpointIdx: u32,
}

changeModel :: proc(scene: ^Scene($SB, $M, $T, $O, $L), objectIdx: u32, modelIdx: u32) {
	object := &scene.objects[objectIdx]
	model := &scene.models[object.modelIdx]

	removeInstance(scene, model, object.instanceIdx)

	object.modelIdx = modelIdx
	object.instanceIdx = addInstance(scene, &scene.models[modelIdx], objectIdx)
}

objectTransform :: proc(scene: ^Scene($SB, $M, $T, $O, $L), object: ^O) -> Mat4 {
	model := &scene.models[object.modelIdx]
	local := transform(
		object.position + model.position,
		object.rotation * model.rotation,
		object.scale * model.scale,
	)
	if object.attachment.targetIdx < 0 {
		return local
	}

	return objectParentTransform(scene, object) * local
}

objectParentTransform :: proc(scene: ^Scene($SB, $M, $T, $O, $L), object: ^O) -> Mat4 {
	if object.attachment.targetIdx < 0 {
		return IMAT4
	}

	target := &scene.objects[object.attachment.targetIdx]
	targetModel := &scene.models[target.modelIdx]
	targetTransform := transform(
		target.position + targetModel.position,
		target.rotation * targetModel.rotation,
		target.scale * targetModel.scale,
	)
	if int(object.attachment.bindpointIdx) >= len(targetModel.bindpoints) {
		return targetTransform
	}
	bindpoint := &targetModel.bindpoints[object.attachment.bindpointIdx]
	if int(bindpoint.boneIdx) >= len(target.animation.state) {
		return targetTransform
	}
	return targetTransform * target.animation.state[bindpoint.boneIdx]
}

Texture :: struct($Base: typeid) where intrinsics.type_is_struct(Base) {
	using _: Base `imrefl:"flatten"`,
}

Model :: struct($Base: typeid) where intrinsics.type_is_struct(Base) {
	using _:    Base `imrefl:"flatten"`,
	position:   Vec3 `imrefl:"label=Position,speed=0.1"`,
	rotation:   Quat `imrefl:"label=Rotation,euler"`,
	scale:      Vec3 `imrefl:"label=Scale,speed=0.1"`,
	meshes:     []Mesh `imrefl:"ignore"`,
	skeleton:   []Bone `imrefl:"ignore"`,
	animations: []Animation `imrefl:"read-only"`,
	bindpoints: [dynamic]Bindpoint,
	instances:  [dynamic]u32 `imrefl:"read-only"`,
}

deleteModel :: proc(model: ^Model($B)) {
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

addInstance :: proc(scene: ^Scene($SB, $M, $T, $O, $L), model: ^M, objectIdx: u32) -> u32 {
	append(&model.instances, objectIdx)

	scene.boneCount += len(model.skeleton)
	for &mesh in model.meshes {
		scene.vertexCount += mesh.vertexCount
	}
	return u32(len(model.instances) - 1)
}

removeInstance :: proc(scene: ^Scene($SB, $M, $T, $O, $L), model: ^M, instanceIdx: u32) {
	unordered_remove(&model.instances, instanceIdx)
	if u32(len(model.instances)) > instanceIdx {
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

PointLight :: struct($Base: typeid) where intrinsics.type_is_struct(Base) {
	using _:  Base `imrefl:"flatten"`,
	position: Vec3 `imrefl:"label=Position,speed=0.1"`,
	colour:   Vec3 `imrefl:"label=Colour,colour"`,
	lumens:   f32 `imrefl:"label=Lumens,min=0,max=100000,speed=10"`,
}
