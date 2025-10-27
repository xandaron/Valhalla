package Valhalla

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:time"

APP_VERSION: u32 : (0 << 22) | (0 << 12) | (1)

LOG_TO_FILE :: false

frameCount: u32 = 0
fpsTimer := time.now()

delta: f64 = 0.0
lastFrameTime := time.now()

mouseMode := false
mousePos: Vec2 = {0, 0}
mouseDelta: Vec3 = {0, 0, 0}
mouseSensitivity: f32 = 1.0

cameraRotationSpeed: f32 = 1
cameraMoveSpeed: f32 = 1
cameraMove: Vec3 = {0, 0, 0}

MoveAction :: struct {
	destination: Vec3,
}

Action :: union {
	MoveAction,
}

globals: struct {
	runtimeContext:  runtime.Context,

	// Graphics Engine Data
	graphicsContext: GraphicsContext,
	selectedObject:  ^GameObject,

	// Scene Data
	scenes:          [dynamic]Scene,
	activeScene:     u32,

	// Debugging
	showDemo:        bool,
	showMetrics:     bool,
	baseDir:         string,
	fps:             f64,
	paused:          bool,
	inputLock:       bool,
}

@(private = "package")
main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)


	when ODIN_DEBUG {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		context.allocator = mem.tracking_allocator(&tracker)

		defer {
			if len(tracker.allocation_map) > 0 {
				logf(.Debug, "=== %v allocations not freed: ===", len(tracker.allocation_map))
				for _, entry in tracker.allocation_map {
					logf(.Debug, "- %v bytes @ %v", entry.size, entry.location)
				}
			}
			if len(tracker.bad_free_array) > 0 {
				logf(.Debug, "=== %v incorrect frees: ===", len(tracker.bad_free_array))
				for entry in tracker.bad_free_array {
					logf(.Debug, "- %p @ %v", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&tracker)
		}
	}
	free_all(context.temp_allocator)
	globals.runtimeContext = context

	os.set_current_directory(filepath.dir(filepath.dir(os.args[0], context.temp_allocator), context.temp_allocator))

	valhallaInitInfo := InitInfo {
		appVersion = 0,
		windowTitle = "Valhalla Demo",
		shaderFiles = {
			{file = "./shaders/Pre.slang", entryPoint = "comp"},
			{file = "./shaders/Shadow.slang", entryPoint = "vert"},
			{file = "./shaders/Shadow.slang", entryPoint = "frag"},
			{file = "./shaders/Main.slang", entryPoint = "vert"},
			{file = "./shaders/Main.slang", entryPoint = "frag"},
			{file = "./shaders/Post.slang", entryPoint = "comp"},
		},
		preComp = 0,
		lightVert = 1,
		lightFrag = 2,
		mainVert = 3,
		mainFrag = 4,
		postComp = 5,

		// Callbacks
		glfwCallbacks = {
			keyCallback = keyCallback,
			mouseButtonCallback = mouseButtonCallback,
			cursorPosCallback = cursorPosCallback,
			scrollCallback = scrollCallback,
		},

		// Vulkan debug messenger
		vkDebugMessengerCreateInfo = VK_DEBUG_MESSENGER_CREATE_INFO,
	}

	err: Error
	globals.graphicsContext, err = initVkGraphics(&valhallaInitInfo)
	defer cleanupVkGraphics(&globals.graphicsContext)

	append(&globals.scenes, createNewScene())
	defer delete(globals.scenes)
	defer deleteScene(&globals.scenes[0])

	if updateSceneBuffers(&globals.graphicsContext, &globals.scenes[0]) != nil {
		panic("Failed to update scene")
	}

	free_all(context.temp_allocator)
	for updateWindow(&globals.graphicsContext) {
		delta := f32(time.duration_seconds(time.since(lastFrameTime)))
		lastFrameTime = time.now()

		scene := &globals.scenes[globals.activeScene]
		camera := &scene.cameras[scene.activeCamera]

		forward := normalize(camera.center - camera.eye)
		up := camera.up
		right := cross(up, forward)

		movement :=
			delta *
			cameraMoveSpeed *
			cameraMove *
			Mat3{right.x, right.y, right.z, up.x, up.y, up.z, forward.x, forward.y, forward.z}
		camera.eye += movement
		camera.center += movement

		if mouseMode {
			if mouseDelta.xy != {0, 0} {
				mouseDelta.xy *= mouseSensitivity
				axis: Vec3 = mouseDelta.xy * matrix[2, 3]f32{
							up.x, up.y, up.z,
							right.x, right.y, right.z,
						}
				rotation := rotate3(radians(cameraRotationSpeed), axis)
				forward = rotation * forward
			}

			distance := length(camera.center - camera.eye) * (1 - mouseDelta.z * 0.1)

			// Clamp the pitch to prevent flipping
			MAX_Y :: 0.9396926208 // approximately sin(70 degrees)
			signY := sign(forward.y)
			absY := signY * forward.y
			if absY > MAX_Y {
				forward.xz *= sqrt((1 - (MAX_Y * MAX_Y)) / (1 - (absY * absY)))
				forward.y = signY * MAX_Y
			}
			camera.eye = camera.center - (forward * distance)

			mouseDelta = {0, 0, 0}
		}

		if globals.paused {
			delta = 0
		}

		// for &object in scene.objects {
		// 	switch &action in object.action {
		// 	case MoveAction:
		// 		facingDirection := quatMulVec3(object.rotation, object.forward)

		// 		direction := action.destination - object.position
		// 		dist := length(direction)

		// 		targetDirection := direction / dist
		// 		if distance(facingDirection, targetDirection) > 0.05 {
		// 			angleBetween := angle(object.forward, targetDirection)
		// 			targetRotation := quatFromAxisAngle(
		// 				angleBetween,
		// 				Vec3{0, direction.x < 0 ? 1 : -1, 0},
		// 			)

		// 			ROTATION_SPEED :: PI // 180 degrees per second
		// 			lerpTime := delta * ROTATION_SPEED / angle(facingDirection, targetDirection)
		// 			if lerpTime >= 1 {
		// 				object.rotation = targetRotation
		// 			} else {
		// 				object.rotation = slerp(object.rotation, targetRotation, lerpTime)
		// 			}
		// 		} else {
		// 			MOVE_SPEED :: 5
		// 			lerpTime := delta * MOVE_SPEED / dist
		// 			if lerpTime >= 1 {
		// 				object.position = action.destination
		// 				globals.inputLock = false
		// 				object.action = nil
		// 			} else {
		// 				object.position = lerp(object.position, action.destination, lerpTime)
		// 			}
		// 		}
		// 	}
		// }

		update(delta)
		if err = drawFrame(&globals.graphicsContext); err != nil {
			logf(.Error, "Failed to draw frame: {}", err)
			break
		}
		calcFrameRate()

		free_all(context.temp_allocator)
	}
}

update :: proc(delta: f32) {
	scene := &globals.scenes[globals.activeScene]
	updateAnimations(scene, delta)
	updateSceneData(
		&globals.graphicsContext,
		scene,
		viewProjection(scene.cameras[scene.activeCamera]),
		delta,
	)
}

calcFrameRate :: proc() {
	frameCount += 1
	if timeDelta := time.duration_seconds(time.since(fpsTimer)); timeDelta >= 1 {
		globals.fps = f64(frameCount) / timeDelta
		frameCount = 0
		fpsTimer = time.now()
	}
}

screenPositionToWorldRay :: proc(pos: Vec2) -> (origin: Vec3, direction: Vec3) {
	scene := &globals.scenes[globals.activeScene]
	camera := &scene.cameras[scene.activeCamera]

	width, height := windowSize(&globals.graphicsContext)

	vpPos := pos / Vec2{f32(width), f32(height)}
	vpPos = vpPos * 2 - 1

	proj := perspective(radians(camera.fov), f32(width) / f32(height), 0.1, 100)
	view := lookAt(camera.eye, camera.center, camera.up)
	ivp := inverse(proj * view)

	ndcNear := Vec4{vpPos.x, vpPos.y, 0, 1}
	ndcFar := Vec4{vpPos.x, vpPos.y, 1, 1}

	worldNear := ivp * ndcNear
	worldFar := ivp * ndcFar

	worldNear /= worldNear.w
	worldFar /= worldFar.w

	origin = worldNear.xyz
	direction = normalize(worldFar.xyz - worldNear.xyz)

	return
}

castRay :: proc(
	rayOrigin, rayDirection: Vec3,
	scene: ^Scene,
) -> (
	object: ^GameObject,
	distance: f32,
) {
	rayIntersects :: proc(
		rayOrigin, rayDirection: Vec3,
		boundingBox: ^AABB,
	) -> (
		hit: bool,
		distance: f32,
	) {
		t1 := (boundingBox.min - rayOrigin) / rayDirection
		t2 := (boundingBox.max - rayOrigin) / rayDirection

		tmin := minVec3(t1, t2)
		tmax := maxVec3(t1, t2)

		mint := max(tmin.x, max(tmin.y, tmin.z))
		maxt := min(tmax.x, min(tmax.y, tmax.z))

		return maxt >= mint, mint
	}

	object = nil

	distance = max(f32)
	for &obj in scene.objects {
		model := scene.models[obj.modelIdx]
		for &mesh in model.meshes {
			transform :=
				translate(obj.position + model.position) *
				quatToMat4(obj.rotation * model.rotation) *
				scale(obj.scale * model.scale)
			corners: [8]Vec3 = {
				mesh.boundingBox.min,
				{mesh.boundingBox.min.x, mesh.boundingBox.min.y, mesh.boundingBox.max.z},
				{mesh.boundingBox.min.x, mesh.boundingBox.max.y, mesh.boundingBox.min.z},
				{mesh.boundingBox.min.x, mesh.boundingBox.max.y, mesh.boundingBox.max.z},
				{mesh.boundingBox.max.x, mesh.boundingBox.min.y, mesh.boundingBox.min.z},
				{mesh.boundingBox.max.x, mesh.boundingBox.min.y, mesh.boundingBox.max.z},
				{mesh.boundingBox.max.x, mesh.boundingBox.max.y, mesh.boundingBox.min.z},
				mesh.boundingBox.max,
			}
			for i in 0 ..< 8 {
				corners[i] = (transform * Vec4{corners[i].x, corners[i].y, corners[i].z, 1}).xyz
			}
			newMin := corners[0]
			newMax := corners[0]
			for i in 1 ..< 8 {
				newMin = minVec3(newMin, corners[i])
				newMax = maxVec3(newMax, corners[i])
			}
			boundingBox := AABB {
				min = newMin,
				max = newMax,
			}
			intersects, dist := rayIntersects(rayOrigin, rayDirection, &boundingBox)
			// if intersects && dist < distance {
			// 	distance = dist
			// 	object = obj
			// }
		}
	}

	return
}
