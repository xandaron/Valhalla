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

	globals.projectDir, _ = filepath.abs(os.args[1], context.allocator)
	os.set_working_directory(os.args[1])

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
	transformComp, _ := compileShader("./shaders/Transform.slang", "comp", .COMPUTE)
	defer delete(transformComp)
	lightVert, _ := compileShader("./shaders/Light.slang", "vert", .VERTEX)
	defer delete(lightVert)
	lightFrag, _ := compileShader("./shaders/Light.slang", "frag", .FRAGMENT)
	defer delete(lightFrag)
	sceneVert, _ := compileShader("./shaders/Scene.slang", "vert", .VERTEX)
	defer delete(sceneVert)
	sceneFrag, _ := compileShader("./shaders/Scene.slang", "frag", .FRAGMENT)
	defer delete(sceneFrag)
	postProcessComp, _ := compileShader("./shaders/PostProcess.slang", "comp", .COMPUTE)
	defer delete(postProcessComp)
	globals.graphicsData, err = initVkGraphics(
	InitGraphicsInfo {
		appVersion      = APP_VERSION,
		windowTitle     = APP_NAME,
		// TODO: Sort this out. I need to load shader descriptor files like the model and texture files
		transformComp   = transformComp,
		lightVert       = lightVert,
		lightFrag       = lightFrag,
		sceneVert       = sceneVert,
		sceneFrag       = sceneFrag,
		postProcessComp = postProcessComp,
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
	gameLoop: for updateWindow(&globals.graphicsData) {
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
			#partial errorCheck: switch e in err {
			case DrawError:
				#partial switch e {
				case .UpdateCommandBuffers:
					break errorCheck
				case:
					logf(.Error, "Failed to draw frame: %v", err)
					break gameLoop
				}
			case:
				logf(.Error, "Failed to draw frame: %v", err)
				break gameLoop
			}
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
		view(scene.cameras[scene.activeCamera]),
		projection(scene.cameras[scene.activeCamera]),
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

