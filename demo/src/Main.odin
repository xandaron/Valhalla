package Demo

import "base:runtime"
import clog "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "vendor:glfw"

APP_VERSION: u32 : (0 << 22) | (0 << 12) | (1)
APP_NAME :: "Valhalla Demo"

LOG_TO_FILE :: false

frameCount: u32 = 0
fpsTimer: time.Time
frameTimeTotal: f64 = 0
frameTimeWorst: f64 = 0

delta: f64 = 0
lastFrameTime: time.Time

mouseMode := false
mousePos: Vec2 = {0, 0}
mouseDelta: Vec3 = {0, 0, 0}

Globals :: struct {
	runtimeContext: runtime.Context,
	projectDir:     string,
	projectFile:    string,
	project:        ProjectData,
	settings:       UserSettings,

	graphicsData:   GraphicsData,

	scenes:         [dynamic]Scene,
	activeScene:    u32,
	uiData:         UIData,

	baseDir:        string,
	fps:            f64,
	frameTimeMs:    f64,
	worstFrameMs:   f64,
	paused:         bool,
}

globals: Globals

PROJECT_FILE :: "demo.project"

main :: proc() {
	context.logger = clog.create_console_logger()
	defer clog.destroy_console_logger(context.logger)

	if !os.exists(PROJECT_FILE) {
		logf(.Error, "%v: project file not found! Run from the repository root.", PROJECT_FILE)
		os.exit(1)
	}

	globals.projectFile, _ = filepath.abs(PROJECT_FILE, context.allocator)
	globals.projectDir = filepath.dir(globals.projectFile)

	os.set_working_directory(globals.projectDir)

	projectErr: LoadError
	startupSceneOverride := ""
	externalPort := -1
	for arg in os.args[1:] {
		if strings.has_prefix(arg, "-external") {
			externalPort = EXTERNAL_DEFAULT_PORT
			if _, _, value := strings.partition(arg, ":"); value != "" {
				parsed, ok := strconv.parse_int(value)
				if !ok {
					logf(.Error, "Invalid external port \"%v\".", value)
					os.exit(1)
				}
				externalPort = parsed
			}
		} else {
			startupSceneOverride = arg
		}
	}

	globals.project, projectErr = loadProject(globals.projectFile)
	if projectErr != .None {
		logf(.Error, "Failed to load project \"%v\": %v", globals.projectFile, projectErr)
		os.exit(1)
	}
	if globals.project.root != "" && globals.project.root != "." {
		root := strings.concatenate(
			{globals.projectDir, "/", globals.project.root},
			context.temp_allocator,
		)
		if !os.is_dir(root) {
			logf(.Error, "Project root \"%v\" does not exist.", root)
			os.exit(1)
		}
		os.set_working_directory(root)
		delete(globals.projectDir)
		globals.projectDir, _ = filepath.abs(".", context.allocator)
	}

	logf(.Info, "Project \"%v\" loaded from %v", globals.project.name, globals.projectFile)
	defer deleteProject(&globals.project)

	if !os.is_dir(CONFIG_PATH()) {
		if err := os.make_directory_all(CONFIG_PATH()); err != nil {
			logf(.Error, "Failed to create config directory \"%v\": %v", CONFIG_PATH(), err)
			os.exit(1)
		}
	}
	settingsLoaded: bool
	globals.settings, settingsLoaded = loadUserSettings()

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
	transformComp, _ := compileShader(projectPath(SHADERS_PATH(), "Transform.slang"), "comp", .COMPUTE)
	lightVert, _ := compileShader(projectPath(SHADERS_PATH(), "Light.slang"), "vert", .VERTEX)
	lightFrag, _ := compileShader(projectPath(SHADERS_PATH(), "Light.slang"), "frag", .FRAGMENT)
	sceneVert, _ := compileShader(projectPath(SHADERS_PATH(), "Scene.slang"), "vert", .VERTEX)
	sceneFrag, _ := compileShader(projectPath(SHADERS_PATH(), "Scene.slang"), "frag", .FRAGMENT)
	gizmoVert, _ := compileShader(projectPath(SHADERS_PATH(), "Gizmo.slang"), "vert", .VERTEX)
	gizmoFrag, _ := compileShader(projectPath(SHADERS_PATH(), "Gizmo.slang"), "frag", .FRAGMENT)
	postProcessComp, _ := compileShader(projectPath(SHADERS_PATH(), "PostProcess.slang"), "comp", .COMPUTE)
	imguiVert, _ := compileShader(projectPath(SHADERS_PATH(), "Imgui.slang"), "vert", .VERTEX)
	imguiFrag, _ := compileShader(projectPath(SHADERS_PATH(), "Imgui.slang"), "frag", .FRAGMENT)
	defer delete(transformComp)
	defer delete(lightVert)
	defer delete(lightFrag)
	defer delete(sceneVert)
	defer delete(sceneFrag)
	defer delete(gizmoVert)
	defer delete(gizmoFrag)
	defer delete(postProcessComp)
	defer delete(imguiVert)
	defer delete(imguiFrag)

	err = initGraphics(
		&globals.graphicsData,
		InitGraphicsInfo {
			appVersion = APP_VERSION,
			windowTitle = APP_NAME,
			window = globals.settings.window,
			settings = globals.settings.render,
			gradeForOutput = !settingsLoaded,
			focusOnShow = externalPort < 0,
			configPath = CONFIG_PATH(),
			callbacks = {frame = frameCallback, input = onInput, ui = drawImgui},
			transformShader = transformComp,
			lightShaders = {lightVert, lightFrag},
			sceneShaders = {sceneVert, sceneFrag},
			gizmoShaders = {gizmoVert, gizmoFrag},
			postProcessShader = postProcessComp,
			imguiShaders = {imguiVert, imguiFrag},
		},
	)
	if err != nil {
		logf(.Error, "Failed to initialise graphics: %v", err)
		os.exit(1)
	}
	defer cleanupGraphics(&globals.graphicsData)
	defer {
		globals.settings.render = globals.graphicsData.settings
		globals.settings.window = windowGeometry(&globals.graphicsData, globals.settings.window)
		saveUserSettings(globals.settings)
	}

	if externalPort >= 0 {
		externalInit(externalPort)
	}
	defer externalShutdown()

	startupScene := startupSceneOverride != "" ? startupSceneOverride : globals.project.startupScene
	if startupScene == "" {
		logf(.Error, "Project declares no startup scene and none was given on the command line.")
		os.exit(1)
	}
	append(&globals.scenes, Scene{path = strings.clone(startupScene)})
	assert(loadScene(&globals.scenes[0]) == nil)
	defer {
		for &scene in globals.scenes {
			deleteScene(&globals.graphicsData, &scene)
		}
		delete(globals.scenes)
	}
	defer deleteUIData(&globals.uiData)

	updateSceneBuffers(&globals.graphicsData, &globals.scenes[0])
	free_all(context.temp_allocator)

	fpsTimer = time.now()
	lastFrameTime = time.now()
	gameLoop: for updateWindow(&globals.graphicsData) {
		if !tickFrame() {
			break gameLoop
		}
	}
}

@(private = "file")
ticking := false

frameCallback :: proc() {
	tickFrame()
}

tickFrame :: proc() -> bool {
	if ticking {
		return true
	}
	ticking = true
	defer ticking = false

	externalTick()

	frameSeconds := time.duration_seconds(time.since(lastFrameTime))
	delta := f32(frameSeconds)
	lastFrameTime = time.now()
	frameTimeTotal += frameSeconds
	frameTimeWorst = max(frameTimeWorst, frameSeconds)

	scene := &globals.scenes[globals.activeScene]
	camera := &scene.cameras[scene.activeCamera]

	forward := normalize(camera.center - camera.eye)
	up := camera.up
	right := cross(up, forward)

	cameraMove: Vec3
	if !imguiWantsKeyboard(&globals.graphicsData) {
		held :: proc(key: i32) -> f32 {
			return glfw.GetKey(globals.graphicsData.window, key) == glfw.PRESS ? 1 : 0
		}
		cameraMove = {
			held(glfw.KEY_D) - held(glfw.KEY_A),
			held(glfw.KEY_SPACE) - held(glfw.KEY_LEFT_SHIFT),
			held(glfw.KEY_W) - held(glfw.KEY_S),
		}
	}

	movement :=
		delta *
		globals.settings.camera.moveSpeed *
		cameraMove *
		Mat3{right.x, right.y, right.z, up.x, up.y, up.z, forward.x, forward.y, forward.z}
	camera.eye += movement
	camera.center += movement

	if mouseMode {
		if mouseDelta.xy != {0, 0} {
			mouseDelta.xy *= globals.settings.camera.mouseSensitivity
			axis: Vec3 = mouseDelta.xy * matrix[2, 3]f32{
						up.x, up.y, up.z,
						right.x, right.y, right.z,
					}
			rotation := rotate3(radians(globals.settings.camera.rotationSpeed), axis)
			forward = rotation * forward
		}

		distance := length(camera.center - camera.eye) * (1 - mouseDelta.z * 0.1)

		MAX_Y :: 0.9396926208
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
	if err := drawFrame(&globals.graphicsData); err != nil && err != .UpdateCommandBuffers {
		logf(.Error, "Failed to draw frame: %v", err)
		return false
	}
	calcFrameRate()

	free_all(context.temp_allocator)
	return true
}

update :: proc(delta: f32) {
	scene := &globals.scenes[globals.activeScene]
	updateAnimations(scene, delta)
	camera := scene.cameras[scene.activeCamera]
	updateSceneData(
		&globals.graphicsData,
		scene,
		viewProjection(camera, getRenderAspectRatio(&globals.graphicsData)),
		camera.eye,
		delta,
	)
}

calcFrameRate :: proc() {
	frameCount += 1
	if timeDelta := time.duration_seconds(time.since(fpsTimer)); timeDelta >= 1 {
		globals.fps = f64(frameCount) / timeDelta
		globals.frameTimeMs = 1000 * frameTimeTotal / f64(frameCount)
		globals.worstFrameMs = 1000 * frameTimeWorst
		frameCount = 0
		frameTimeTotal = 0
		frameTimeWorst = 0
		fpsTimer = time.now()
	}
}
