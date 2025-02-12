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

APP_VERSION: u32 : (0 << 22) | (0 << 12) | (1)

frameCount: u16 = 0
fpsTimer := time.now()

paused := false
delta: f64 = 0.0
lastFrameTime := time.now()

mouseMode := false
mousePos, mouseDelta: f64Vec2 = {0, 0}, {0, 0}
mouseSensitivity: f64 = 1
scrollDelta: f64Vec2 = {0, 0}

cameraSpeed: f64 = 1
cameraMoveSpeed: f32 = 0.0003
cameraMove: Vec3 = {0, 0, 0}

// Debug
logger: runtime.Logger
showDemo := false
showMetrics := false

EngineState :: struct {
	graphicsContext: ^GraphicsContext,
	inMenu:          bool,
}

engineState: EngineState

main :: proc() {
	// Sets the current dir to the folder above the dir of the exe file
	{
		dashCount: u32 = 0
		filePath, _ := filepath.abs(os.args[0])
		for i := len(filePath) - 1; i >= 0; i -= 1 {
			if filepath.is_separator(filePath[i]) {
				dashCount += 1
				if dashCount == 2 {
					if err := os.set_current_directory(filePath[:i]); err != os.ERROR_NONE {
						fmt.printfln(
							"Failed to set current directory to '{}': {}",
							filePath[:i],
							err,
						)
					}
					break
				}
			}
		}
	}

	when ODIN_DEBUG {
		logPath := createLogPath()
		if logHandle, err := os.open(logPath, os.O_WRONLY | os.O_CREATE); err == 0 {
			logger = log.create_multi_logger(
				log.create_console_logger(),
				log.create_file_logger(logHandle),
			)
		} else {
			logger = log.create_multi_logger(log.create_console_logger())
			log.logf(.Warning, "Log file could not be created! Filename: {}", logPath)
		}
		context.logger = logger
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

	graphicsContext: GraphicsContext
	engineState.graphicsContext = &graphicsContext
	if err := initVkGraphics(&graphicsContext, "./assets/scenes/shambler.json"); err != .None {
		#partial switch err {
		case .FailedToLoadSceneFile, .FailedToParseJson:
			log.log(.Warning, "Failed to load scene file")
		case .FailedToLoadModel:
			log.log(.Warning, "Failed to load model file")
		case .FailedToLoadTexture:
			log.log(.Warning, "Failed to load texture file")
		}
	}
	defer cleanupVkGraphics(&graphicsContext)

	glfw.SetWindowUserPointer(graphicsContext.window, &engineState)

	setActiveScene(&graphicsContext, 0)

	for !glfw.WindowShouldClose(graphicsContext.window) {
		glfw.PollEvents()

		scene := &graphicsContext.scenes[graphicsContext.activeScene]
		camera := &scene.cameras[scene.activeCamera]
		if mouseMode {
			if mouseDelta != {0, 0} {
				axis: Vec3 = {0, 0, 0}
				forward := camera.center - camera.eye
				if mouseDelta.x < 0 {
					axis -= camera.up
				} else if mouseDelta.x > 0 {
					axis += camera.up
				}
				if mouseDelta.y > 0 {
					axis += cross(camera.up, forward)
				} else if mouseDelta.y < 0 {
					axis -= cross(camera.up, forward)
				}
				rotation := rotation3(f32(radians(cameraSpeed)), axis)
				camera.up = rotation * camera.up
				forward = rotation * forward
				camera.eye = camera.center - forward
				mouseDelta = {0, 0}
			}
			if scrollDelta.y != 0 {
				forward := (camera.center - camera.eye) / camera.distance
				camera.distance *= 1 + f32(-scrollDelta.y * 0.1)
				camera.eye = camera.center - forward * camera.distance
				scrollDelta = {0, 0}
			}
		}
		if cameraMove.x != 0 {
			right := normalize(cross(camera.up, (camera.center - camera.eye) / camera.distance))
			movement := cameraMoveSpeed * cameraMove.x * right
			camera.eye += movement
			camera.center += movement
		}
		if cameraMove.y != 0 {
			scene := &graphicsContext.scenes[graphicsContext.activeScene]
			movement := cameraMoveSpeed * cameraMove.y * camera.up
			camera.eye += movement
			camera.center += movement
		}
		if cameraMove.z != 0 {
			movement :=
				cameraMoveSpeed * cameraMove.z * (camera.center - camera.eye) / camera.distance
			camera.eye += movement
			camera.center += movement
		}

		delta := f32(time.duration_seconds(time.since(lastFrameTime)))
		lastFrameTime = time.now()
		drawFrame(&graphicsContext, delta if !paused else 0.0)
		calcFrameRate(graphicsContext.window)

		// I'm not using the temp allocatior so this shouldn't do anything
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

glfwKeyCallback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()
	context.logger = logger
	using engineState := (^EngineState)(glfw.GetWindowUserPointer(window))
	if inMenu do return
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

glfwMouseButtonCallback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	engineState := (^EngineState)(glfw.GetWindowUserPointer(window))
	if engineState.inMenu do return
	if button == glfw.MOUSE_BUTTON_MIDDLE && action == glfw.PRESS {
		if mouseMode {
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		} else {
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)
		}
		mouseMode = !mouseMode
	}
}

glfwCursorPosCallback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	engineState := (^EngineState)(glfw.GetWindowUserPointer(window))
	if engineState.inMenu do return
	newPos: f64Vec2 = {xpos, ypos} * mouseSensitivity
	vector1 := mousePos
	mouseDelta = newPos - vector1
	mousePos = newPos
}

glfwScrollCallback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	engineState := (^EngineState)(glfw.GetWindowUserPointer(window))
	if engineState.inMenu do return
	scrollDelta = {xoffset, yoffset}
}

framebufferResizeCallback :: proc "c" (window: glfw.WindowHandle, width: i32, height: i32) {
	engineState := (^EngineState)(glfw.GetWindowUserPointer(window))
	engineState.graphicsContext.framebufferResized = true
}
