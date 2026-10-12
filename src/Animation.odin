package Valhalla

Bone :: struct {
	name:         string,
	parentIdx:    u32,
	offsetMatrix: Mat4,
	bindTransform: Mat4,
}

deleteBone :: proc(bone: ^Bone) {
	delete(bone.name)
}

Animation :: struct {
	name:     string,
	duration: f64,
	nodes:    []AnimationNode,
}

deleteAnimation :: proc(animation: ^Animation) {
	delete(animation.name)
	for &node in animation.nodes {
		deleteAnimationNode(&node)
	}
	delete(animation.nodes)
}

AnimationNode :: struct {
	keyPositions: []KeyValue(Vec3),
	keyRotations: []KeyValue(Quat),
	keyScales:    []KeyValue(Vec3),
}

deleteAnimationNode :: proc(node: ^AnimationNode) {
	delete(node.keyPositions)
	delete(node.keyRotations)
	delete(node.keyScales)
}

KeyValue :: struct($valueType: typeid) {
	time:          f64,
	value:         valueType,
	interpolation: InterpolationType,
}

InterpolationType :: enum {
	Step,
	Linear,
	SphericalLinear,
	CubicSpline,
}

ObjectAnimation :: struct {
	idx:     i32 `imrefl:"ignore"`,
	timer:   f64 `imrefl:"label=Animation time,speed=0.01"`,
	playing: bool `imrefl:"label=Playing"`,
	state:   []Mat4 `imrefl:"ignore"`,
	cache:   []ObjectAnimationCache `imrefl:"ignore"`,
	end:     ObjectAnimationEnd `imrefl:"flatten"`,
}

deleteObjectAnimation :: proc(animation: ^ObjectAnimation) {
	delete(animation.state)
	delete(animation.cache)
}

ObjectAnimationCache :: struct {
	positionIdx, rotationIdx, scaleIdx: u32,
}

ObjectAnimationEnd :: struct {
	behavior:   AnimationBehavior,
	transition: AnimationTransition,
	nextIdx:    i32,
}

AnimationBehavior :: enum {
	Stop,
	Loop,
	Next,
}

AnimationTransition :: struct {
	timer:         f32,
	duration:      f32,
	interpolation: InterpolationType,
}
