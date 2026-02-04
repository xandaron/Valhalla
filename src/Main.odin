package Valhalla

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:time"

APP_VERSION: u32 : (0 << 22) | (0 << 12) | (1)
APP_NAME :: "Valhalla Demo"

SCENE_PATH :: "./scenes/"
MODELS_PATH :: "./scene_components/models/"
TEXTURES_PATH :: "./scene_components/textures/"
SHADERS_PATH :: "./shaders/"
ASSETS_PATH :: "./assets/"

LOG_TO_FILE :: false

frameCount: u32 = 0
fpsTimer: time.Time

delta: f64 = 0
lastFrameTime: time.Time

mouseMode := false
mousePos: Vec2 = {0, 0}
mouseDelta: Vec3 = {0, 0, 0}
mouseSensitivity: f32 = 1

cameraRotationSpeed: f32 = 1
cameraMoveSpeed: f32 = 1
cameraMove: Vec3 = {0, 0, 0}

globals: struct {
	runtimeContext: runtime.Context,
	projectDir:     string,

	// Graphics Engine Data
	graphicsData:   GraphicsData,

	// Scene Data
	scenes:         [dynamic]Scene,
	activeScene:    u32,
	uiData:         UIData,

	// Debugging
	baseDir:        string,
	fps:            f64,
	paused:         bool,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if len(os.args) < 2 {
		logf(.Error, "Usage: %v <path_to_project_file>", os.args[0])
		os.exit(1)
	} else if !os.exists(os.args[1]) {
		logf(.Error, "%v: Dir not found!", os.args[1])
		os.exit(1)
	}

	globals.projectDir, _ = filepath.abs(os.args[1])
	os.set_current_directory(os.args[1])

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
	globals.runtimeContext = context

	err: Error
	globals.graphicsData, err = initVkGraphics(
		InitInfo {
			appVersion = APP_VERSION,
			windowTitle = APP_NAME,
			shaderFiles = {
				{file = "./shaders/Pre.slang", entryPoint = "comp"},
				{file = "./shaders/Shadow.slang", entryPoint = "vert"},
				{file = "./shaders/Shadow.slang", entryPoint = "frag"},
				{file = "./shaders/Scene.slang", entryPoint = "vert"},
				{file = "./shaders/Scene.slang", entryPoint = "frag"},
				{file = "./shaders/Post.slang", entryPoint = "comp"},
			},
			preComp = 0,
			lightVert = 1,
			lightFrag = 2,
			mainVert = 3,
			mainFrag = 4,
			postComp = 5,
		},
	)
	defer cleanupVkGraphics(&globals.graphicsData)

	append(&globals.scenes, Scene{path = "./scenes/knight.scene"})
	assert(loadScene(&globals.scenes[0]) == nil)
	defer {
		for &scene in globals.scenes {
			deleteScene(&scene)
		}
		delete(globals.scenes)
	}

	assert(updateSceneBuffers(&globals.graphicsData, &globals.scenes[0]) == nil)
	free_all(context.temp_allocator)

	fpsTimer = time.now()
	lastFrameTime = time.now()
	for updateWindow(&globals.graphicsData) {
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
			MAX_Y :: 0.9396926208 // approx sin(70 degrees)
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

		update(delta)
		if err = drawFrame(&globals.graphicsData); err != nil {
			logf(.Error, "Failed to draw frame: %v", err)
			break
		}
		calcFrameRate()

		free_all(context.temp_allocator)
	}
}

update :: proc(delta: f32) {
	scene := &globals.scenes[globals.activeScene]
	updateAnimations(scene, delta)
	if err := updateSceneData(
		&globals.graphicsData,
		scene,
		viewProjection(scene.cameras[scene.activeCamera]),
		delta,
	); err != nil {
		panic("Failed to update scene data!")
	}
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

	width, height := windowSize(&globals.graphicsData)

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

castRay :: proc(rayOrigin, rayDirection: Vec3, scene: ^Scene) -> (object: ^Object, distance: f32) {
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

