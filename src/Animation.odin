package Valhalla

Bone :: struct {
	name:         string,
	parentIdx:    u32,
	offsetMatrix: Mat4,
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
	idx:     i32,
	timer:   f64,
	playing: bool,
	state:   []Mat4,
	cache:   []ObjectAnimationCache,
	end:     ObjectAnimationEnd,
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

updateAnimations :: proc(scene: ^Scene, delta: f32) {
	interpolateNodes :: proc(values: []KeyValue($T), cachedIdx: ^u32, time: f64) -> T {
		assert(len(values) > 0, "No keyframes in animation node!")
		if len(values) == 1 {
			return values[0].value
		}

		for true {
			if values[cachedIdx^].time <= time && time <= values[cachedIdx^ + 1].time {
				break
			}
			cachedIdx^ += 1
			if cachedIdx^ == u32(len(values)) - 1 {
				cachedIdx^ = 0
			}
		}

		switch values[cachedIdx^].interpolation {
		case .CubicSpline:
			when T != Quat {
				// Catmull-Rom spline - calculates tangents automatically
				t1 := values[cachedIdx^].time
				t2 := values[cachedIdx^ + 1].time
				dt := f32((time - t1) / (t2 - t1))

				p0 := values[cachedIdx^].value
				p1 := values[cachedIdx^ + 1].value

				// Get neighboring points for tangent calculation
				p_prev :=
					cachedIdx^ > 0 ? values[cachedIdx^ - 1].value : values[len(values) - 1].value
				p_next :=
					cachedIdx^ + 2 < u32(len(values)) ? values[cachedIdx^ + 2].value : values[0].value

				// Catmull-Rom tangents (scaled by time differences for proper parameterization)
				m0 := 0.5 * (p1 - p_prev)
				m1 := 0.5 * (p_next - p0)

				// Hermite interpolation
				dt2 := dt * dt
				dt3 := dt2 * dt
				h00 := 2 * dt3 - 3 * dt2 + 1
				h10 := dt3 - 2 * dt2 + dt
				h01 := -2 * dt3 + 3 * dt2
				h11 := dt3 - dt2

				return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1
			} else {
				// Cubic spline interpolation is not typically used for quaternions
				// So we will fallback to spherical linear interpolation for quaternions
				fallthrough
			}
		case .SphericalLinear:
			when T == Quat {
				t1 := values[cachedIdx^].time
				t2 := values[cachedIdx^ + 1].time
				dt := (time - t1) / (t2 - t1)
				return slerp(values[cachedIdx^].value, values[cachedIdx^ + 1].value, f32(dt))
			} else {
				// Spherical linear interpolation is only valid for quaternions
				// So we will fallback to linear interpolation for other types
				fallthrough
			}
		case .Linear:
			t1 := values[cachedIdx^].time
			t2 := values[cachedIdx^ + 1].time
			return lerp(
				values[cachedIdx^].value,
				values[cachedIdx^ + 1].value,
				f32((time - t1) / (t2 - t1)),
			)
		case .Step:
			return values[cachedIdx^].value
		}
		panic("Unreachable!")
	}

	for &object in scene.objects {
		model := &scene.models[object.modelIdx]
		if len(scene.models[object.modelIdx].skeleton) == 0 {
			continue
		}

		objectAnimation := &object.animation
		if objectAnimation.idx >= 0 {
			animation := scene.models[object.modelIdx].animations[objectAnimation.idx]

			if animation.duration == 0 {
				objectAnimation.timer = 0
			} else {
				if objectAnimation.playing {
					objectAnimation.timer += f64(delta)
				}
				objectAnimation.timer -=
					floor(objectAnimation.timer / animation.duration) * animation.duration
			}

			objectAnimation.state[0] = IMAT4
			for &node, nodeIdx in animation.nodes {
				objectAnimation.state[nodeIdx] =
					objectAnimation.state[model.skeleton[nodeIdx].parentIdx] *
					translate(
						interpolateNodes(
							node.keyPositions,
							&objectAnimation.cache[nodeIdx].positionIdx,
							objectAnimation.timer,
						),
					) *
					quatToMat4(
						interpolateNodes(
							node.keyRotations,
							&objectAnimation.cache[nodeIdx].rotationIdx,
							objectAnimation.timer,
						),
					) *
					scale(
						interpolateNodes(
							node.keyScales,
							&objectAnimation.cache[nodeIdx].scaleIdx,
							objectAnimation.timer,
						),
					)
			}
		} else {
			for &node in objectAnimation.state {
				node = IMAT4
			}
		}
	}
}

