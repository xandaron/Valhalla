#+private file

package Valhalla

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "vendor:glfw"

@(private = "package")
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

@(private = "package")
runtimeContext: runtime.Context

@(private = "package")
PointLight :: struct {
	name:      cstring,
	position:  Vec3,
	colour:    Vec3,
	intensity: f32,
	dropoff:   f32,
}

@(private = "package")
Instance :: struct {
	name:               cstring,
	position:           Vec3,
	rotation:           Vec3,
	scaleUniform:       bool,
	scale:              Vec3,

	// Graphics Engine Data
	using graphicsData: SceneInstanceData,
}

@(private = "package")
Scene :: struct {
	filePath:           string,
	name:               cstring,
	clearColour:        [4]i32,
	ambientLight:       f32,

	// Scene
	instances:          [dynamic]Instance,
	pointLights:        [dynamic]PointLight,
	cameras:            [dynamic]Camera,
	activeCamera:       u32,

	// Assets
	modelPaths:         [dynamic]cstring,
	texturePaths:       [dynamic]cstring,
	normalPaths:        [dynamic]cstring,

	// Graphics Engine Data
	using graphicsData: SceneGraphicalData,
}

@(private = "package")
CameraMode :: enum {
	PERSPECTIVE,
	ORTHOGRAPHIC,
}

@(private = "package")
Camera :: struct {
	name:            cstring,
	eye, center, up: Vec3,
	near, far:       f32,
	fov:             f32,
	mode:            CameraMode,
}

@(private = "package")
AABB :: struct {
	min, max: Vec3,
}

Globals :: struct {
	// Graphics Engine Data
	graphicsContext: GraphicsContext,

	// Scene Data
	scenes:          [dynamic]Scene,
	activeScene:     u32,

	// Debugging
	showDemo:        bool,
	showMetrics:     bool,
	baseDir:         string,
	fps:             f64,
	paused:          bool,
}

@(private = "package")
globals: Globals = {
	scenes      = make([dynamic]Scene),
	activeScene = 0,
	showDemo    = false,
	showMetrics = false,
	fps         = 0.0,
	paused      = false,
}

@(private = "package")
main :: proc() {
	// Sets the current dir to the folder above the dir of the exe file
	absExePath, _ := filepath.abs(os.args[0], context.temp_allocator)
	globals.baseDir = filepath.dir(filepath.dir(absExePath, context.temp_allocator))
	if err := os.set_current_directory(globals.baseDir); err != os.ERROR_NONE {
		fmt.printfln("Failed to set directory to '%s': %s", globals.baseDir, err)
		panic("Failed to set directory!")
	}

	when ODIN_DEBUG {
		when LOG_TO_FILE {
			logPath := createLogPath()
			if logHandle, err := os.open(logPath, os.O_WRONLY | os.O_CREATE); err == 0 {
				context.logger = log.create_multi_logger(
					log.create_console_logger(),
					log.create_file_logger(logHandle),
				)
			} else {
				context.logger = log.create_multi_logger(log.create_console_logger())
				log.logf(.Warning, "Log file could not be created! Filename: {}", logPath)
			}
		} else {
			context.logger = log.create_multi_logger(log.create_console_logger())
		}
		defer log.destroy_multi_logger(context.logger)

		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		context.allocator = mem.tracking_allocator(&tracker)

		defer {
			if len(tracker.allocation_map) > 0 {
				log.logf(.Debug, "=== %v allocations not freed: ===", len(tracker.allocation_map))
				for _, entry in tracker.allocation_map {
					log.logf(.Debug, "- %v bytes @ %v", entry.size, entry.location)
				}
			}
			if len(tracker.bad_free_array) > 0 {
				log.logf(.Debug, "=== %v incorrect frees: ===", len(tracker.bad_free_array))
				for entry in tracker.bad_free_array {
					log.logf(.Debug, "- %p @ %v", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&tracker)
		}
	}
	runtimeContext = context
	free_all(context.temp_allocator)

	glfwCallbacks := GLFWCallbacks {
		keyCallback         = keyCallback,
		mouseButtonCallback = mouseButtonCallback,
		cursorPosCallback   = cursorPosCallback,
		scrollCallback      = scrollCallback,
	}

	initVkGraphics(&globals.graphicsContext, &glfwCallbacks)
	defer cleanupVkGraphics(&globals.graphicsContext)
	#partial switch loadScene("./assets_game/scenes/Wizard.json") {
	case .FailedToLoadSceneFile, .FailedToParseJson:
		log.log(.Warning, "Failed to load scene file")
	case .FailedToLoadModel:
		log.log(.Warning, "Failed to load model file")
	case .FailedToLoadTexture:
		log.log(.Warning, "Failed to load texture file")
	}
	setActiveScene(&globals.graphicsContext, &globals.scenes[globals.activeScene])

	for !glfw.WindowShouldClose(globals.graphicsContext.window) {
		delta := f32(time.duration_seconds(time.since(lastFrameTime)))
		lastFrameTime = time.now()

		glfw.PollEvents()

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
				rotation := rotation3(radians(cameraRotationSpeed), axis)
				forward = rotation * forward
			}

			distance := length(camera.center - camera.eye) * (1 - mouseDelta.z * 0.1)

			minPitch: f32 : PI * -70.0 / 180.0
			maxPitch: f32 : PI * 70.0 / 180.0
			pitch := asin(forward.y)

			if pitch > maxPitch {
				pitch = maxPitch
			} else if pitch < minPitch {
				pitch = minPitch
			}

			// Project forward onto xz-plane
			xzDir := normalize(Vec3{forward.x, 0, forward.z})

			// Reconstruct forward with capped angle
			forward = normalize(
				xzDir * cos(pitch) +
				Vec3{0, 1, 0} * sin(pitch)
			)
			camera.eye = camera.center - (forward * distance)

			mouseDelta = {0, 0, 0}
		}

		drawFrame(&globals.graphicsContext, delta if !globals.paused else 0)
		calcFrameRate(globals.graphicsContext.window)

		free_all(context.temp_allocator)
	}

	for idx := len(globals.scenes) - 1; idx >= 0; idx -= 1 {
		closeScene(u32(idx))
	}
	delete(globals.scenes)
}

calcFrameRate :: proc(window: glfw.WindowHandle) {
	frameCount += 1
	if timeDelta := time.duration_seconds(time.since(fpsTimer)); timeDelta >= 1 {
		globals.fps = f64(frameCount) / timeDelta
		frameCount = 0
		fpsTimer = time.now()
	}
}

screenToWorldRay :: proc(window: glfw.WindowHandle, pos: Vec2) -> (origin: Vec3, direction: Vec3) {
	scene := &globals.scenes[globals.activeScene]
	camera := &scene.cameras[scene.activeCamera]

	width, height := glfw.GetWindowSize(window)

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

castRay :: proc(rayOrigin, rayDirection: Vec3, scene: ^Scene) -> (instance: ^Instance) {
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

	instance = nil

	distance := max(f32)
	for &inst in scene.instances {
		model := &scene.models[inst.modelIdx]

		for &mesh in model.meshes {
			transform :=
				translate(inst.position) *
				quatToRotation(
					eulerToQuat(
						radians(inst.rotation.x),
						radians(inst.rotation.y),
						radians(inst.rotation.z),
						.XYZ,
					),
				) *
				scale(inst.scale)
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
			transformed: [8]Vec3
			for i in 0 ..< 8 {
				transformed[i] =
					(transform * Vec4{corners[i].x, corners[i].y, corners[i].z, 1}).xyz
			}
			new_min := transformed[0]
			new_max := transformed[0]
			for i in 1 ..< 8 {
				new_min = minVec3(new_min, transformed[i])
				new_max = maxVec3(new_max, transformed[i])
			}
			boundingBox := AABB {
				min = new_min,
				max = new_max,
			}
			intersects, dist := rayIntersects(rayOrigin, rayDirection, &boundingBox)
			if intersects && dist < distance {
				distance = dist
				instance = &inst
			}
		}
	}

	return
}

keyCallback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtimeContext
	switch key {
	case glfw.KEY_ESCAPE:
		glfw.SetWindowShouldClose(window, glfw.TRUE)
	case glfw.KEY_P:
		if action == glfw.PRESS do globals.paused = !globals.paused
	case glfw.KEY_D:
		if action == glfw.PRESS {
			cameraMove.x += 1
		} else if action == glfw.RELEASE {
			cameraMove.x -= 1
		}
	case glfw.KEY_A:
		if action == glfw.PRESS {
			cameraMove.x -= 1
		} else if action == glfw.RELEASE {
			cameraMove.x += 1
		}
	case glfw.KEY_SPACE:
		if action == glfw.PRESS {
			cameraMove.y += 1
		} else if action == glfw.RELEASE {
			cameraMove.y -= 1
		}
	case glfw.KEY_LEFT_SHIFT:
		if action == glfw.PRESS {
			cameraMove.y -= 1
		} else if action == glfw.RELEASE {
			cameraMove.y += 1
		}
	case glfw.KEY_W:
		if action == glfw.PRESS {
			cameraMove.z += 1
		} else if action == glfw.RELEASE {
			cameraMove.z -= 1
		}
	case glfw.KEY_S:
		if action == glfw.PRESS {
			cameraMove.z -= 1
		} else if action == glfw.RELEASE {
			cameraMove.z += 1
		}
	case glfw.KEY_C:
		if action == glfw.PRESS {
			scene := &globals.scenes[globals.activeScene]
			camera := scene.cameras[scene.activeCamera]
			log.logf(
				.Debug,
				"eye: ({}, {}, {}), center: ({}, {}, {}), up: ({}, {}, {})",
				camera.eye.x,
				camera.eye.y,
				camera.eye.z,
				camera.center.x,
				camera.center.y,
				camera.center.z,
				camera.up.x,
				camera.up.y,
				camera.up.z,
			)
		}
	case glfw.KEY_H:
		if action == glfw.PRESS {
			globals.showDemo = !globals.showDemo
		}
	case glfw.KEY_M:
		if action == glfw.PRESS {
			globals.showMetrics = !globals.showMetrics
		}
	}
}

mouseButtonCallback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	if button == glfw.MOUSE_BUTTON_MIDDLE && action == glfw.PRESS {
		if mouseMode {
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL)
			mouseMode = false
		} else {
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)
			mouseMode = true
		}
		return
	}
	if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
		context = runtimeContext
		origin, direction := screenToWorldRay(window, mousePos)
		object := castRay(origin, direction, &globals.scenes[globals.activeScene])
		if object != nil {
			log.logf(.Debug, "Clicked on instance: {}", object.name)
		} else {
			log.log(.Debug, "Clicked on empty space")
		}
		return
	}
}

cursorPosCallback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	newPos: Vec2 = {f32(xpos), f32(ypos)}
	mouseDelta.xy = newPos - mousePos
	mousePos = newPos
}

scrollCallback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	mouseDelta.z = f32(yoffset)
}

InstanceJSON :: struct {
	name:         cstring `json:name`,
	model:        i32 `json:model`,
	textures:     []i32 `json:textures`,
	normals:      []i32 `json:normals`,
	position:     Vec3 `json:position`,
	rotation:     Vec3 `json:rotation`,
	scaleUniform: bool `json:scale_uniform`,
	scale:        Vec3 `json:scale`,
}

SceneJSON :: struct {
	name:          cstring `json:name`,
	clear_colour:  [4]i32 `json:clear_colour`,
	ambient_light: f32 `json:ambient_light`,
	cameras:       []Camera `json:cameras`,
	lights:        []PointLight `json:lights`,
	models:        []cstring `json:models`,
	textures:      []cstring `json:textures`,
	normals:       []cstring `json:normals`,
	instances:     []InstanceJSON `json:instances`,
}

// ATM we can't have a truly "empty" scene as we have to make buffers and images that must exist.
// It might be possible to make the buffers optional to solve this?
// I've heard of bindless buffers and images. Maybe that could be a solution?
@(private = "package")
createNewScene :: proc() {
	resize(&globals.scenes, len(globals.scenes) + 1)
	scene := &globals.scenes[len(globals.scenes) - 1]

	scene.filePath = ""
	scene.name = strings.clone_to_cstring("New Scene")
	scene.clearColour = {150, 150, 150, 255}
	scene.ambientLight = 0.01

	scene.instances = make([dynamic]Instance, 1)
	scene.instances[0] = {
		name        = strings.clone_to_cstring("cube"),
		modelIdx    = 0,
		textureIdxs = make([]u32, 1),
		normalIdxs  = make([]u32, 1),
		position    = {0, 0, 0},
		rotation    = {0, 0, 0},
		scale       = {1, 1, 1},
	}

	scene.pointLights = make([dynamic]PointLight, 1)
	scene.pointLights[0] = {
		name      = strings.clone_to_cstring("white light"),
		position  = {0, 2, 0},
		colour    = {1, 1, 1},
		intensity = 1,
	}

	scene.cameras = make([dynamic]Camera, 1)
	scene.cameras[0] = {
		name     = strings.clone_to_cstring("main"),
		eye      = {0.0, 0.2, -0.4},
		center   = {0.0, 0.0, 0.0},
		up       = {0.0, 1.0, 0.0},
		fov      = 45.0,
		mode     = .PERSPECTIVE,
	}
	scene.activeCamera = 0

	scene.modelPaths = make([dynamic]cstring, 1)
	scene.modelPaths[0] = strings.clone_to_cstring("./assets/models/cube/cube.fbx")

	scene.texturePaths = make([dynamic]cstring, 1)
	scene.texturePaths[0] = strings.clone_to_cstring("./assets/textures/missing_texture.jpg")
	scene.textureCount = 1

	scene.normalPaths = make([dynamic]cstring, 1)
	scene.normalPaths[0] = strings.clone_to_cstring("./assets/textures/normal.jpg")
	scene.normalCount = 1

	scene.indices = make([dynamic]u32)

	loadSceneAssets(&globals.graphicsContext, scene)
	switchScene(u32(len(globals.scenes) - 1))
}

LoadSceneError :: enum {
	None,
	FailedToLoadSceneFile,
	FailedToParseJson,
	FailedToLoadModel,
	FailedToLoadTexture,
}

@(private = "package")
loadScene :: proc(sceneFile: string) -> (err: LoadSceneError = .None) {
	data, rerr := os.read_entire_file_or_err(sceneFile)
	if rerr != nil {
		return .FailedToLoadSceneFile
	}
	defer delete(data)

	sceneJson: SceneJSON
	merr := json.unmarshal(data, &sceneJson)
	if merr != nil {
		return .FailedToParseJson
	}

	resize(&globals.scenes, len(globals.scenes) + 1)
	scene := &globals.scenes[len(globals.scenes) - 1]
	scene^ = {
		name         = sceneJson.name,
		clearColour  = sceneJson.clear_colour,
		ambientLight = sceneJson.ambient_light,
		instances    = make([dynamic]Instance, len(sceneJson.instances)),
		pointLights  = make([dynamic]PointLight),
		cameras      = make([dynamic]Camera),
		modelPaths   = make([dynamic]cstring),
		texturePaths = make([dynamic]cstring),
		normalPaths  = make([dynamic]cstring),
	}
	scene.filePath, _ = filepath.abs(sceneFile)

	for &instance, instanceIndex in sceneJson.instances {
		textureIdxs := make([]u32, len(instance.textures))
		normalIdxs := make([]u32, len(instance.normals))

		for index := 0; index < len(textureIdxs); index += 1 {
			textureIdxs[index] = u32(instance.textures[index] + 1)
			normalIdxs[index] = u32(instance.normals[index] + 1)
		}

		scene.instances[instanceIndex] = {
			name         = instance.name,
			modelIdx     = u32(instance.model + 1),
			textureIdxs  = textureIdxs[:],
			normalIdxs   = normalIdxs[:],
			position     = instance.position,
			rotation     = instance.rotation,
			scaleUniform = instance.scaleUniform,
			scale        = instance.scale,
		}
	}

	append(&scene.modelPaths, strings.clone_to_cstring("./assets/models/cube/cube.fbx"))
	append(&scene.texturePaths, strings.clone_to_cstring("./assets/textures/missing_texture.jpg"))
	append(&scene.normalPaths, strings.clone_to_cstring("./assets/textures/normal.jpg"))

	append(&scene.pointLights, ..sceneJson.lights)
	append(&scene.cameras, ..sceneJson.cameras)
	append(&scene.modelPaths, ..sceneJson.models)
	append(&scene.texturePaths, ..sceneJson.textures)
	append(&scene.normalPaths, ..sceneJson.normals)

	delete(sceneJson.lights)
	delete(sceneJson.cameras)
	delete(sceneJson.models)
	delete(sceneJson.textures)
	delete(sceneJson.normals)

	for &instance in sceneJson.instances {
		delete(instance.textures)
		delete(instance.normals)
	}
	delete(sceneJson.instances)

	if lerr := loadSceneAssets(&globals.graphicsContext, scene); lerr != .None {
		// TODO: This error should just be info not crashing. Should handle files not existing by using a replacement texture/model?
		panic("Load error")
	}

	return
}

@(private = "package")
saveScene :: proc(sceneIndex: u32) {
	scene := &globals.scenes[sceneIndex]

	sceneInfo: SceneJSON = {
		name          = scene.name,
		clear_colour  = scene.clearColour,
		ambient_light = scene.ambientLight,
		cameras       = scene.cameras[:],
		lights        = scene.pointLights[:],
		models        = scene.modelPaths[1:],
		textures      = scene.texturePaths[1:],
		normals       = scene.normalPaths[1:],
		instances     = make([]InstanceJSON, len(scene.instances)),
	}
	defer delete(sceneInfo.instances)

	for &instance, index in scene.instances {
		textureIdxs := make([]i32, len(instance.textureIdxs))
		normalIdxs := make([]i32, len(instance.normalIdxs))

		for index := 0; index < len(textureIdxs); index += 1 {
			textureIdxs[index] = i32(instance.textureIdxs[index]) - 1
			normalIdxs[index] = i32(instance.normalIdxs[index]) - 1
		}

		sceneInfo.instances[index] = {
			name         = instance.name,
			model        = i32(instance.modelIdx) - 1,
			textures     = textureIdxs,
			normals      = normalIdxs,
			position     = instance.position,
			rotation     = instance.rotation,
			scaleUniform = instance.scaleUniform,
			scale        = instance.scale,
		}
	}
	defer for &instance in sceneInfo.instances {
		delete(instance.textures)
		delete(instance.normals)
	}

	json_data, err := json.marshal(sceneInfo, {pretty = true})
	if err != nil {
		panic("Couldn't marshal data")
	}
	defer delete(json_data)

	werr := os.write_entire_file_or_err(scene.filePath, json_data)
	if werr != nil {
		panic("Couldn't write file")
	}
}

@(private = "package")
closeScene :: proc(idx: u32) {
	scene := &globals.scenes[idx]
	cleanupScene(&globals.graphicsContext, scene)

	for &texturePath in scene.texturePaths {
		delete(texturePath)
	}
	delete(scene.texturePaths)

	for &normalPath in scene.normalPaths {
		delete(normalPath)
	}
	delete(scene.normalPaths)

	for &modelPath in scene.modelPaths {
		delete(modelPath)
	}
	delete(scene.modelPaths)

	for &instance in scene.instances {
		delete(instance.name)
		delete(instance.textureIdxs)
		delete(instance.normalIdxs)
		delete(instance.scaleKeys)
		delete(instance.positionKeys)
		delete(instance.rotationKeys)
	}
	delete(scene.instances)

	for &light in scene.pointLights {
		delete(light.name)
	}
	delete(scene.pointLights)

	for &camera in scene.cameras {
		delete(camera.name)
	}
	delete(scene.cameras)
	delete(scene.name)
	delete(scene.filePath)

	unordered_remove(&globals.scenes, idx)
}

@(private = "package")
switchScene :: proc(sceneIndex: u32) {
	globals.activeScene = sceneIndex
	setActiveScene(&globals.graphicsContext, &globals.scenes[sceneIndex])
}
