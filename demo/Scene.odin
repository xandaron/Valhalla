package Demo

import valhalla "../src"
import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"


Scene :: struct {
	filePath:     string,
	name:         string,

	// Scene
	models:       [dynamic]^Model,
	objects:      [dynamic]^GameObject,
	pointLights:  [dynamic]^PointLight,
	cameras:      [dynamic]Camera,
	activeCamera: u32,

	// Assets
	modelPaths:   [dynamic]string,
	texturePaths: [dynamic]string,

	// Graphics Engine Data
	graphicsData: valhalla.SceneData,
}

Model :: struct {
	name:         string,
	position:     Vec3,
	rotation:     Quat,
	scale:        Vec3,
	animations:   []Animation,
	graphicsData: ^valhalla.Model,
}

GameObject :: struct {
	name:         string,
	modelIdx:     u32,
	animIdx:      u32,
	position:     Vec3,
	rotation:     Quat,
	scale:        Vec3,
	forward:      Vec3,
	selectable:   bool,
	tiled:        bool,
	action:       Action,

	// Graphics Engine Data
	graphicsData: ^valhalla.ModelInstance,
}

PointLight :: struct {
	name:         string,
	graphicsData: ^valhalla.PointLight,
}

Animation :: struct {
	name:         string,
	graphicsData: ^valhalla.Animation,
}

CameraMode :: enum {
	PERSPECTIVE,
	ORTHOGRAPHIC,
}

Camera :: struct {
	name:            string,
	eye, center, up: Vec3,
	near, far:       f32,
	fov:             f32,
	mode:            CameraMode,
}

// ATM we can't have a truly "empty" scene as we have to make buffers and images that must exist.
// It might be possible to make the buffers optional to solve this?
// I've heard of bindless buffers and images. Maybe that could be a solution?
createNewScene :: proc() {
	scene := &globals.scene

	scene.filePath = ""
	scene.name = strings.clone("New Scene")

	scene.modelPaths = make([dynamic]string, 2)
	scene.modelPaths[0] = strings.clone("./assets/Wizard.glb")
	scene.modelPaths[1] = strings.clone("./assets/cube.fbx")

	scene.texturePaths = make([dynamic]string, 3)
	scene.texturePaths[0] = strings.clone("./assets/albedo.png")
	scene.texturePaths[1] = strings.clone("./assets/white.jpg")
	scene.texturePaths[2] = strings.clone("./assets/normal.jpg")

	if valhalla.loadSceneAssets(
		   &globals.graphicsContext,
		   &scene.graphicsData,
		   scene.modelPaths[:],
		   scene.texturePaths[:],
	   ) !=
	   nil {
		panic("Failed to load scene assets")
	}

	scene.models[0].name = strings.clone("Wizard")
	scene.models[0].scale = {0.165, 0.165, 0.165}
	scene.models[0].rotation = quatFromEuler(radians(f32(90.0)), 0, 0, .XYZ)

	scene.models[1].name = strings.clone("Meter Cube")
	scene.models[1].scale = {0.5, 0.5, 0.5}

	scene.graphicsData.clearColour = {0.5, 0.5, 0.5, 1.0}
	scene.graphicsData.ambientLight = 0.25

	scene.objects = make([dynamic]^GameObject, 2)
	scene.objects[0] = new(GameObject)
	scene.objects[0]^ = {
		name         = strings.clone("Wizard"),
		modelIdx     = 0,
		position     = {0, 0, 0},
		rotation     = IQUAT,
		scale        = {1, 1, 1},
		forward      = {0, 0, -1},
		selectable   = true,
		graphicsData = new(valhalla.ModelInstance),
	}

	valhalla.addInstance(
		&scene.graphicsData,
		scene.models[0].graphicsData,
		scene.objects[0].graphicsData,
		&scene.objects[0].position,
		&scene.objects[0].rotation,
		&scene.objects[0].scale,
	)

	scene.objects[0].graphicsData.textureIdxs[0][valhalla.TextureIndex.ALBEDO] = 0
	scene.objects[0].graphicsData.textureIdxs[0][valhalla.TextureIndex.NORMAL_MAP] = 2

	scene.objects[1] = new(GameObject)
	scene.objects[1]^ = {
		name         = strings.clone("Floor"),
		modelIdx     = 1,
		position     = {0, -0.05, 0},
		rotation     = IQUAT,
		scale        = {10, 0.1, 10},
		tiled        = true,
		graphicsData = new(valhalla.ModelInstance),
	}

	valhalla.addInstance(
		&scene.graphicsData,
		scene.models[1].graphicsData,
		scene.objects[1].graphicsData,
		&scene.objects[1].position,
		&scene.objects[1].rotation,
		&scene.objects[1].scale,
	)

	scene.objects[1].graphicsData.textureIdxs[0][valhalla.TextureIndex.ALBEDO] = 1
	scene.objects[1].graphicsData.textureIdxs[0][valhalla.TextureIndex.NORMAL_MAP] = 2

	scene.pointLights = make([dynamic]^PointLight, 1)
	scene.pointLights[0] = new(PointLight)
	scene.pointLights[0]^ = {
		name         = strings.clone("light"),
		graphicsData = new(valhalla.PointLight),
	}
	scene.pointLights[0].graphicsData^ = {
		position   = {0, 1.5, -0.5},
		colour     = {1, 1, 1},
		brightness = 1,
		dropoff    = 5,
	}

	valhalla.addLight(&scene.graphicsData, scene.pointLights[0].graphicsData)

	scene.cameras = make([dynamic]Camera, 1)
	scene.cameras[0] = {
		name   = strings.clone("main"),
		eye    = {0.0, 2.0, -4.0},
		center = {0.0, 0.0, 0.0},
		up     = {0.0, 1.0, 0.0},
		fov    = 45.0,
		mode   = .PERSPECTIVE,
		near   = 0.1,
		far    = 100.0,
	}
	scene.activeCamera = 0
}

cleanupScene :: proc() {
	scene := &globals.scene
	valhalla.cleanupScene(&globals.graphicsContext, &scene.graphicsData)

	delete(scene.filePath)
	delete(scene.name)

	for &object in scene.objects {
		delete(object.name)
		free(object.graphicsData)
		free(object)
	}
	delete(scene.objects)

	for &model in scene.models {
		delete(model.name)
		delete(model.animations)
		free(model.graphicsData)
		free(model)
	}
	delete(scene.models)

	for &light in scene.pointLights {
		delete(light.name)
		free(light.graphicsData)
		free(light)
	}
	delete(scene.pointLights)

	for &camera in scene.cameras {
		delete(camera.name)
	}
	delete(scene.cameras)

	for &path in scene.modelPaths {
		delete(path)
	}
	delete(scene.modelPaths)

	for &path in scene.texturePaths {
		delete(path)
	}
	delete(scene.texturePaths)
}
