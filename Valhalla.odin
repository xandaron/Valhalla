#+private file

package Valhalla

import "base:runtime"
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

@(private = "package")
baseDir: string

frameCount: u16 = 0
fpsTimer := time.now()

@(private = "package")
paused := false
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

// Debug
@(private = "package")
showDemo := false
@(private = "package")
showMetrics := false

@(private = "package")
EngineState :: struct {
	graphicsContext: ^GraphicsContext,
}

@(private = "package")
engineState: EngineState

@(private = "package")
main :: proc() {
	// Sets the current dir to the folder above the dir of the exe file
	absExePath, _ := filepath.abs(os.args[0], context.temp_allocator)
	baseDir = filepath.dir(filepath.dir(absExePath, context.temp_allocator))
	if err := os.set_current_directory(baseDir); err != os.ERROR_NONE {
		fmt.printfln("Failed to set directory to '%s': %s", baseDir, err)
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

	graphicsContext: GraphicsContext
	engineState.graphicsContext = &graphicsContext

	glfwCallbacks := GLFWCallbacks {
		keyCallback         = keyCallback,
		mouseButtonCallback = mouseButtonCallback,
		cursorPosCallback   = cursorPosCallback,
		scrollCallback      = scrollCallback,
	}

	#partial switch initVkGraphics(
		&graphicsContext,
		"./assets/scenes/shambler_gltf.json",
		&glfwCallbacks,
	) {
	case .FailedToLoadSceneFile, .FailedToParseJson:
		log.log(.Warning, "Failed to load scene file")
	case .FailedToLoadModel:
		log.log(.Warning, "Failed to load model file")
	case .FailedToLoadTexture:
		log.log(.Warning, "Failed to load texture file")
	}
	defer cleanupVkGraphics(&graphicsContext)

	glfw.SetWindowUserPointer(graphicsContext.window, &engineState)

	for !glfw.WindowShouldClose(graphicsContext.window) {
		delta := f32(time.duration_seconds(time.since(lastFrameTime)))
		lastFrameTime = time.now()

		glfw.PollEvents()

		scene := &graphicsContext.scenes[graphicsContext.activeScene]
		camera := &scene.cameras[scene.activeCamera]

		forward := (camera.center - camera.eye) / camera.distance
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
			if mouseDelta != {0, 0, 0} {
				log.log(.Debug, "Test")
			}

			if mouseDelta.xy != {0, 0} {
				axis: Vec3 = mouseDelta.xy * matrix[2, 3]f32{
							up.x, up.y, up.z, 
							right.x, right.y, right.z, 
						}
				rotation := rotation3(radians(cameraRotationSpeed), axis)
				forward = rotation * forward
			}

			camera.distance *= 1 - mouseDelta.z * 0.1
			camera.eye = camera.center - (forward * camera.distance)

			mouseDelta = {0, 0, 0}
		}

		drawFrame(&graphicsContext, delta if !paused else 0)
		calcFrameRate(graphicsContext.window)

		free_all(context.temp_allocator)
	}
}

calcFrameRate :: proc(window: glfw.WindowHandle) {
	frameCount += 1
	if timeDelta := time.duration_seconds(time.since(fpsTimer)); timeDelta >= 1 {
		glfw.SetWindowTitle(
			window,
			strings.clone_to_cstring(
				fmt.tprintf("{:.2f}", (f64)(frameCount) / timeDelta),
				context.temp_allocator,
			),
		)
		frameCount = 0
		fpsTimer = time.now()
	}
}

keyCallback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtimeContext
	using engineState := (^EngineState)(glfw.GetWindowUserPointer(window))
	switch key {
	case glfw.KEY_ESCAPE:
		glfw.SetWindowShouldClose(window, glfw.TRUE)
	case glfw.KEY_P:
		if action == glfw.PRESS do paused = !paused
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
			scene := &graphicsContext.scenes[graphicsContext.activeScene]
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
			showDemo = !showDemo
		}
	case glfw.KEY_M:
		if action == glfw.PRESS {
			showMetrics = !showMetrics
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
	}
}

cursorPosCallback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	newPos: Vec2 = {f32(xpos), f32(ypos)} * mouseSensitivity
	mouseDelta.xy = newPos - mousePos
	mousePos = newPos
}

scrollCallback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	mouseDelta.z = f32(yoffset)
}
