package Valhalla

Bone :: struct {
	parentIndex:  u32,
	offsetMatrix: Mat4,
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
	keyPositions: []KeyVec3,
	keyRotations: []KeyQuat,
	keyScales:    []KeyVec3,
}

deleteAnimationNode :: proc(node: ^AnimationNode) {
	delete(node.keyPositions)
	delete(node.keyRotations)
	delete(node.keyScales)
}

KeyVec3 :: struct {
	time:          f64,
	value:         Vec3,
	interpolation: InterpolationType,
}

KeyQuat :: struct {
	time:          f64,
	value:         Quat,
	interpolation: InterpolationType,
}

InterpolationType :: enum {
	Step,
	Linear,
	// CubicSpline,
}

ObjectAnimation :: struct {
	idx:     i32,
	timer:   f64,
	state:   []Mat4,
	cache:   []ObjectAnimationCache,
	playing: bool,
	end:     ObjectAnimationEnd,
}

deleteObjectAnimation :: proc(animation: ^ObjectAnimation) {
	delete(animation.state)
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

updateAnimations :: proc(scene: ^Scene, delta: f32) {
	for &object in scene.objects {
		animationData := object.animation
		if !animationData.playing || animationData.idx < 0 {
			continue
		}

		animation := scene.models[object.modelIdx].animations[animationData.idx]

		if animation.duration == 0 {
			animationData.timer = 0
		} else {
			animationData.timer += f64(delta)
		}
		for ; animationData.timer > animation.duration;
		    animationData.timer -= animation.duration {}

		for &node, nodeIdx in animation.nodes {
			animationData.state[nodeIdx] = IMAT4
			// (a *= b) == (a = a * b)
			// therefore I *= T *= R *= S == I * T * R * S
			if len(node.keyPositions) == 1 {
				animationData.state[nodeIdx] *= translate(node.keyPositions[0].value)
			} else if len(node.keyPositions) != 0 {
				id := animationData.cache[nodeIdx].positionIdx
				if id > u32(len(node.keyPositions)) {
					id = 0
				}
				for true {
					if node.keyPositions[id].time <= animationData.timer &&
					   animationData.timer <= node.keyPositions[id + 1].time {
						animationData.cache[nodeIdx].positionIdx = id
						break
					}
					id += 1
					if id == u32(len(node.keyPositions)) - 1 {
						id = 0
					}
				}

				positionIdx := animationData.cache[nodeIdx].positionIdx
				thisTime := node.keyPositions[positionIdx].time
				nextTime := node.keyPositions[positionIdx + 1].time
				dt := (animationData.timer - thisTime) / (nextTime - thisTime)
				animationData.state[nodeIdx] *= translate(
					lerp(
						node.keyPositions[positionIdx].value,
						node.keyPositions[positionIdx + 1].value,
						f32(dt),
					),
				)
			}

			if len(node.keyRotations) == 1 {
				animationData.state[nodeIdx] *= quatToMat4(node.keyRotations[0].value)
			} else if len(node.keyRotations) != 0 {
				id := animationData.cache[nodeIdx].rotationIdx
				if id > u32(len(node.keyRotations)) {
					id = 0
				}
				for true {
					if node.keyRotations[id].time <= animationData.timer &&
					   animationData.timer <= node.keyRotations[id + 1].time {
						animationData.cache[nodeIdx].rotationIdx = id
						break
					}
					id += 1
					if id == u32(len(node.keyRotations)) - 1 {
						id = 0
					}
				}

				rotationIdx := animationData.cache[nodeIdx].rotationIdx
				thisTime := node.keyRotations[rotationIdx].time
				nextTime := node.keyRotations[rotationIdx + 1].time
				timeDiff := f32((animationData.timer - thisTime) / (nextTime - thisTime))
				animationData.state[nodeIdx] *= quatToMat4(
					slerp(
						node.keyRotations[rotationIdx].value,
						node.keyRotations[rotationIdx + 1].value,
						f32(timeDiff),
					),
				)
			}

			if len(node.keyScales) == 1 {
				animationData.state[nodeIdx] *= scale(node.keyScales[0].value)
			} else if len(node.keyScales) != 0 {
				id := animationData.cache[nodeIdx].scaleIdx
				if id > u32(len(node.keyScales)) {
					id = 0
				}
				for true {
					if node.keyScales[id].time <= animationData.timer &&
					   animationData.timer <= node.keyScales[id + 1].time {
						animationData.cache[nodeIdx].scaleIdx = id
						break
					}
					id += 1
					if id == u32(len(node.keyScales)) - 1 {
						id = 0
					}
				}

				scaleIdx := animationData.cache[nodeIdx].scaleIdx
				thisTime := node.keyScales[scaleIdx].time
				nextTime := node.keyScales[scaleIdx + 1].time
				timeDiff := f32((animationData.timer - thisTime) / (nextTime - thisTime))
				value := lerp(
					node.keyScales[scaleIdx].value,
					node.keyScales[scaleIdx + 1].value,
					timeDiff,
				)
				animationData.state[nodeIdx] *= scale(value)
			}
		}
	}
}
