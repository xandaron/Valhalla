package Demo

import valhalla "../src"
import ai "assimp"
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
	entity:      ^GameObject,
}

Action :: union {
	MoveAction,
}

Globals :: struct {
	runtimeContext:  runtime.Context,

	// Graphics Engine Data
	graphicsContext: valhalla.GraphicsContext,
	action:          Action,
	selectedObject:  ^GameObject,

	// Scene Data
	scene:           Scene,
	activeScene:     u32,

	// Debugging
	showDemo:        bool,
	showMetrics:     bool,
	baseDir:         string,
	fps:             f64,
	paused:          bool,
	inputLock:       bool,
}

globals: Globals = {}

@(private = "package")
main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	// Sets the current dir to the folder above the dir of the exe file
	// All filepaths should be relative to this dir
	// This was mainly for NVIDIA Nsight to work properly
	absExePath, _ := filepath.abs(os.args[0], context.temp_allocator)
	globals.baseDir = filepath.dir(filepath.dir(absExePath, context.temp_allocator))
	if err := os.set_current_directory(globals.baseDir); err != os.ERROR_NONE {
		fmt.printfln("Failed to set directory to '%s': %s", globals.baseDir, err)
		panic("Failed to set directory!")
	}

	when ODIN_DEBUG {
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
	free_all(context.temp_allocator)
	globals.runtimeContext = context

	valhallaInitInfo := valhalla.InitInfo {
		appVersion = 0,
		windowTitle = "Valhalla Demo",

		// Callbacks
		glfwCallbacks = {
			keyCallback = keyCallback,
			mouseButtonCallback = mouseButtonCallback,
			cursorPosCallback = cursorPosCallback,
			scrollCallback = scrollCallback,
		},
		errorCallback = errorCallback,
		modelLoader = loadModel,
		imguiDraw = drawUI,

		// Vulkan debug messenger
		vkDebugMessengerCreateInfo = valhalla.VK_DEBUG_MESSENGER_CREATE_INFO,
	}

	err: valhalla.Error
	globals.graphicsContext, err = valhalla.initVkGraphics(&valhallaInitInfo)
	defer valhalla.cleanupVkGraphics(&globals.graphicsContext)

	createNewScene()
	defer cleanupScene()

	if valhalla.switchScene(&globals.graphicsContext, &globals.scene.graphicsData) != nil {
		panic("Failed to update scene")
	}

	for !glfw.WindowShouldClose(globals.graphicsContext.window) {
		delta := f32(time.duration_seconds(time.since(lastFrameTime)))
		lastFrameTime = time.now()

		glfw.PollEvents()

		scene := &globals.scene
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
			maxY :: 0.9396926208 // approximately sin(70 degrees)
			signY := sign(forward.y)
			absY := signY * forward.y
			if absY > maxY {
				forward.xz *= sqrt((1 - (maxY * maxY)) / (1 - (absY * absY)))
				forward.y = signY * maxY
			}
			camera.eye = camera.center - (forward * distance)

			mouseDelta = {0, 0, 0}
		}

		if globals.paused {
			delta = 0
		}

		switch &action in globals.action {
		case MoveAction:
			entity := action.entity

			facingDirection := quatMulVec3(entity.rotation, entity.forward)

			yOffset := entity.position.y
			entity.position.y = 0
			direction := action.destination - entity.position
			directionLength := length(direction)

			targetDirection := direction / directionLength
			if distance(facingDirection, targetDirection) > 0.01 {
				ROTATION_SPEED :: PI // 180 degrees per second
				timeToRotate := angle(facingDirection, targetDirection) / ROTATION_SPEED

				angleBetween := angle(entity.forward, targetDirection)
				targetRotation := quatFromAxisAngle(
					angleBetween,
					Vec3{0, direction.x < 0 ? 1 : -1, 0},
				)

				lerpTime := delta / timeToRotate

				newQuat: Quat
				if lerpTime >= 1 {
					entity.rotation = targetRotation
				} else {
					entity.rotation = slerp(entity.rotation, targetRotation, lerpTime)
				}
			} else {
				MOVE_SPEED :: 5
				timeToTravel := directionLength / MOVE_SPEED
				lerpTime := delta / timeToTravel
				if lerpTime >= 1 {
					entity.position = action.destination
					globals.inputLock = false
					globals.action = nil
				} else {
					entity.position = lerp(entity.position, action.destination, lerpTime)
					BOB_SPEED :: 4 * PI // 180 degrees per second
					lastPos := acos(yOffset / 0.3)
					entity.position.y = 0.3 * abs(cos(BOB_SPEED * delta + lastPos))
				}
			}
		}

		if valhalla.drawFrame(
			   &globals.graphicsContext,
			   viewProjection(scene.cameras[scene.activeCamera]),
			   delta,
		   ) !=
		   nil {
			log.logf(.Error, "Failed to draw frame: {}", err)
			break
		}
		calcFrameRate(globals.graphicsContext.window)

		free_all(context.temp_allocator)
	}
}

viewProjection :: proc(camera: Camera) -> Mat4 {
	if camera.mode == .PERSPECTIVE {
		return(
			valhalla.perspective(
				radians(camera.fov),
				valhalla.RENDER_SIZE.x / valhalla.RENDER_SIZE.y,
				camera.near,
				camera.far,
			) *
			valhalla.lookAt(camera.eye, camera.center, camera.up) \
		)
	} else {
		return(
			valhalla.orthographic(
				radians(camera.fov),
				valhalla.RENDER_SIZE.x / valhalla.RENDER_SIZE.y,
				camera.near,
				camera.far,
			) *
			valhalla.lookAt(camera.eye, camera.center, camera.up) \
		)
	}
	panic("")
}

calcFrameRate :: proc(window: glfw.WindowHandle) {
	frameCount += 1
	if timeDelta := time.duration_seconds(time.since(fpsTimer)); timeDelta >= 1 {
		globals.fps = f64(frameCount) / timeDelta
		frameCount = 0
		fpsTimer = time.now()
	}
}

keyCallback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = globals.runtimeContext

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

screenPositionToWorldRay :: proc(
	window: glfw.WindowHandle,
	pos: Vec2,
) -> (
	origin: Vec3,
	direction: Vec3,
) {
	scene := &globals.scene
	camera := &scene.cameras[scene.activeCamera]

	width, height := glfw.GetWindowSize(window)

	vpPos := pos / Vec2{f32(width), f32(height)}
	vpPos = vpPos * 2 - 1

	proj := valhalla.perspective(radians(camera.fov), f32(width) / f32(height), 0.1, 100)
	view := valhalla.lookAt(camera.eye, camera.center, camera.up)
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
		boundingBox: ^valhalla.AABB,
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

		for &mesh in model.graphicsData.meshes {
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
			boundingBox := valhalla.AABB {
				min = newMin,
				max = newMax,
			}
			intersects, dist := rayIntersects(rayOrigin, rayDirection, &boundingBox)
			if intersects && dist < distance {
				distance = dist
				object = obj
			}
		}
	}

	return
}

mouseButtonCallback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = globals.runtimeContext

	if globals.inputLock {
		return
	}

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
		object, _ := castRay(screenPositionToWorldRay(window, mousePos), &globals.scene)
		if object != nil && object.selectable {
			log.logf(.Debug, "Selected instance: {}", object.name)
			globals.selectedObject = object
		} else {
			globals.selectedObject = nil
		}
		return
	}
	if button == glfw.MOUSE_BUTTON_RIGHT && action == glfw.RELEASE {
		if globals.selectedObject == nil {
			return
		}

		origin, direction := screenPositionToWorldRay(window, mousePos)
		object, distance := castRay(origin, direction, &globals.scene)
		if object != nil && object.tiled {
			pos := (origin + direction * distance)
			globals.action = MoveAction {
				entity      = globals.selectedObject,
				destination = {round(pos.x), globals.selectedObject.position.y, round(pos.z)},
			}
			globals.inputLock = true
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


loadModel: valhalla.ModelLoader : proc(
	filename: cstring,
	vertexOffset, indiceOffset: u32,
) -> (
	^valhalla.Model,
	valhalla.LoaderError,
) {
	aiStringToCstring :: proc(aiStr: ^ai.String, allocator := context.allocator) -> string {
		return strings.clone_from_bytes(aiStr.data[:aiStr.length])
	}

	aiVectorToVec3 :: proc(aiVec: ^ai.Vector3D) -> Vec3 {
		return {aiVec.x, aiVec.y, aiVec.z}
	}

	aiQuaternionToQuat :: proc(aiQuat: ^ai.Quaternion) -> Quat {
		return transmute(Quat)Vec4{aiQuat.x, aiQuat.y, aiQuat.z, aiQuat.w}
	}

	aiMatrixToMat4 :: proc(aiMat: ^ai.Matrix4x4) -> Mat4 {
		return {
			aiMat.a1,
			aiMat.a2,
			aiMat.a3,
			aiMat.a4,
			aiMat.b1,
			aiMat.b2,
			aiMat.b3,
			aiMat.b4,
			aiMat.c1,
			aiMat.c2,
			aiMat.c3,
			aiMat.c4,
			aiMat.d1,
			aiMat.d2,
			aiMat.d3,
			aiMat.d4,
		}
	}
	scene := &globals.scene
	append(&scene.models, new(Model))
	model := scene.models[len(scene.models) - 1]

	model.graphicsData = new(valhalla.Model)
	model.graphicsData^ = {
		position  = &model.position,
		rotation  = &model.rotation,
		scale     = &model.scale,
		instances = make([dynamic]^valhalla.ModelInstance),
	}

	// I could make this persistent but I don't think I need to
	propertyStore := ai.CreatePropertyStore()

	// Stops Assimp from checking the area of faces preventing it from culling faces that are too small
	ai.SetImportPropertyInteger(propertyStore, ai.CONFIG_PP_FD_CHECKAREA, 0)

	// Maximum number of bones per vertex
	ai.SetImportPropertyInteger(propertyStore, ai.CONFIG_PP_LBW_MAX_WEIGHTS, 4)

	// Remove point and line primitives
	ai.SetImportPropertyInteger(
		propertyStore,
		ai.CONFIG_PP_SBP_REMOVE,
		i32(ai.Primitive_Type_Flags{.POINT, .LINE}),
	)

	// Remove scene components that I don't need
	ai.SetImportPropertyInteger(
		propertyStore,
		ai.CONFIG_PP_RVC_FLAGS,
		i32(ai.Component_Flags{.COLORS, .TEXTURES, .LIGHTS, .CAMERAS, .MATERIALS}),
	)

	defer ai.ReleasePropertyStore(propertyStore)

	IMPORT_FLAGS :: ai.Post_Process_Step_Flags {
		.CalcTangentSpace,
		.JoinIdenticalVertices,
		.MakeLeftHanded,
		.Triangulate,
		.RemoveComponent,
		.GenNormals,
		// This seems like a good idea.
		.SplitLargeMeshes,
		.LimitBoneWeights,
		// Maybe we should use this and add logging.
		// .ValidateDataStructure,
		// I don't think I need this right now. Maybe in the future.
		// .ImproveCacheLocality,
		.SortByPType,
		.FindDegenerates,
		.FindInvalidData,
		.GenUVCoords,
		// Not sure how necessary this is.
		.OptimizeMeshes,
		.OptimizeGraph,
		// Correct the UVs and winding order for Vulkan.
		.FlipUVs,
		.FlipWindingOrder,
		.GenBoundingBoxes,
	}

	aiScene := ai.ImportFileExWithProperties(filename, IMPORT_FLAGS, nil, propertyStore)
	if aiScene == nil {
		log.logf(.Error, "Failed to load file: %s", ai.GetErrorString())
		return model.graphicsData, .FailedToLoadFile
	}
	defer ai.FreeScene(aiScene)

	if aiScene.mNumMeshes == 0 {
		log.log(.Error, "Model has no meshes!")
		return model.graphicsData, .InvalidFileData
	}

	vertexOffset := vertexOffset
	indiceOffset := indiceOffset

	model.graphicsData.meshes = make([]valhalla.Mesh, aiScene.mNumMeshes)
	boneCount: u32 = 0
	for &mesh, meshIndex in model.graphicsData.meshes {
		sceneMesh := aiScene.mMeshes[meshIndex]

		if .TRIANGLE not_in sceneMesh.mPrimitiveTypes {
			continue
		}

		mesh = {
			vertices = make([]valhalla.Vertex, u32(sceneMesh.mNumVertices)),
			indices = make([]u32, u32(sceneMesh.mNumFaces * 3)),
			vertexOffset = vertexOffset,
			indiceOffset = indiceOffset,
			boundingBox = {
				min = aiVectorToVec3(&sceneMesh.mAABB.mMin),
				max = aiVectorToVec3(&sceneMesh.mAABB.mMax),
			},
		}

		vertexOffset += u32(len(mesh.vertices))
		indiceOffset += u32(len(mesh.indices))

		for vertexIndex in 0 ..< sceneMesh.mNumVertices {
			mesh.vertices[vertexIndex] = {
				position  = sceneMesh.mVertices[vertexIndex],
				normal    = sceneMesh.mNormals[vertexIndex],
				tangent   = sceneMesh.mTangents[vertexIndex],
				bitangent = sceneMesh.mBitangents[vertexIndex],
				uv        = {
					sceneMesh.mTextureCoords[0][vertexIndex].x,
					sceneMesh.mTextureCoords[0][vertexIndex].y,
				},
				weights   = {0.0, 0.0, 0.0, 0.0},
				bones     = {0, 0, 0, 0},
			}
		}

		for faceIndex in 0 ..< sceneMesh.mNumFaces {
			face := sceneMesh.mFaces[faceIndex]
			for indiceIndex in 0 ..< 3 {
				mesh.indices[faceIndex * 3 + u32(indiceIndex)] = u32(face.mIndices[indiceIndex])
			}
		}

		boneCount += sceneMesh.mNumBones
	}

	model.graphicsData.skeleton = make(valhalla.Skeleton, boneCount)
	boneMap := make(map[string]u32, boneCount)
	defer delete(boneMap)

	for &mesh, meshIndex in model.graphicsData.meshes {
		sceneMesh := aiScene.mMeshes[meshIndex]
		for &bone, boneIndex in model.graphicsData.skeleton {
			sceneBone := sceneMesh.mBones[boneIndex]

			bone.inverseBind = aiMatrixToMat4(&sceneBone.mOffsetMatrix)

			for weightIndex in 0 ..< sceneBone.mNumWeights {
				weight := &sceneBone.mWeights[weightIndex]
				vertexIndex := u32(weight.mVertexId)

				for index in 0 ..< 4 {
					if mesh.vertices[vertexIndex].weights[index] == 0.0 {
						mesh.vertices[vertexIndex].weights[index] = f32(weight.mWeight)
						mesh.vertices[vertexIndex].bones[index] = u32(boneIndex)
						break
					} else if index == 3 {
						// Assimp should limit the number of weights to 4.
						// If we reach here then something has gone wrong.
						log.logf(.Warning, "Vertex %v has more than 4 bone weights!", vertexIndex)
					}
				}
			}

			boneMap[aiStringToCstring(&sceneBone.mName, context.temp_allocator)] = u32(boneIndex)
		}
	}

	for &mesh in model.graphicsData.meshes {
		for &vertex, vertexIndex in mesh.vertices {
			if sum := vertex.weights.x + vertex.weights.y + vertex.weights.z + vertex.weights.w;
			   sum == 0.0 {
				vertex.weights = {1.0, 0.0, 0.0, 0.0}
				vertex.bones = {0, 0, 0, 0}
			} else if sum > 1.001 || sum < 0.999 {
				vertex.weights /= sum
			}
		}
	}

	if len(model.graphicsData.skeleton) > 0 {
		searchNodeTree :: proc(
			node: ^ai.Node,
			skeleton: ^valhalla.Skeleton,
			boneMap: ^map[string]u32,
		) {
			if node == nil {
				return
			}

			if boneIndex, isBone :=
				   boneMap[aiStringToCstring(&node.mName, context.temp_allocator)]; isBone {
				parent := node.mParent

				parentIndex: u32 = 0
				isParentBone := false
				for parentIndex, isParentBone =
					    boneMap[aiStringToCstring(&parent.mName, context.temp_allocator)];
				    !isParentBone;
				    parentIndex, isParentBone =
					    boneMap[aiStringToCstring(&parent.mName, context.temp_allocator)] {
					parent = parent.mParent
					if parent == nil {
						break
					}
				}
				skeleton[boneIndex].parentIndex = parentIndex
			}

			for childIndex in 0 ..< node.mNumChildren {
				searchNodeTree(node.mChildren[childIndex], skeleton, boneMap)
			}
		}

		searchNodeTree(aiScene.mRootNode, &model.graphicsData.skeleton, &boneMap)
		model.animations = make([]Animation, aiScene.mNumAnimations)
		for &animation, animationIndex in model.animations {
			sceneAnimation := aiScene.mAnimations[animationIndex]

			ticksToSecond :=
				1 / (sceneAnimation.mTicksPerSecond == 0.0 ? 1.0 : sceneAnimation.mTicksPerSecond)
			animation = {
				name         = aiStringToCstring(&sceneAnimation.mName),
				graphicsData = new(valhalla.Animation),
			}
			animation.graphicsData^ = {
				nodes    = make([]valhalla.AnimationNode, len(model.graphicsData.skeleton)),
				duration = sceneAnimation.mDuration * ticksToSecond,
			}

			for &node in animation.graphicsData.nodes {
				node = {
					keyPositions = {{time = animation.graphicsData.duration, value = {0, 0, 0}}},
					keyRotations = {
						{time = animation.graphicsData.duration, value = valhalla.IQUAT},
					},
					keyScales    = {{time = animation.graphicsData.duration, value = {1, 1, 1}}},
				}
			}

			for nodeIndex in 0 ..< sceneAnimation.mNumChannels {
				animationNode := sceneAnimation.mChannels[nodeIndex]

				boneIndex, exists :=
					boneMap[aiStringToCstring(&animationNode.mNodeName, context.temp_allocator)]
				if !exists {
					continue
				}

				node := &animation.graphicsData.nodes[boneIndex]

				offset: u32 = 0
				if animationNode.mPositionKeys[0].mTime != 0.0 {
					node.keyPositions = make(
						[]valhalla.KeyVec3,
						animationNode.mNumPositionKeys + 1,
					)
					node.keyPositions[0] = {
						time  = 0.0,
						value = animationNode.mPositionKeys[animationNode.mNumPositionKeys - 1].mValue,
					}
					offset = 1
				} else {
					node.keyPositions = make([]valhalla.KeyVec3, animationNode.mNumPositionKeys)
				}
				for keyIndex in 0 ..< animationNode.mNumPositionKeys {
					positionKey := &animationNode.mPositionKeys[keyIndex]
					node.keyPositions[keyIndex + offset] = {
						time  = positionKey.mTime * ticksToSecond,
						value = positionKey.mValue,
					}
				}

				offset = 0
				if animationNode.mRotationKeys[0].mTime != 0.0 {
					node.keyRotations = make(
						[]valhalla.KeyQuat,
						animationNode.mNumRotationKeys + 1,
					)
					node.keyRotations[0] = {
						time  = 0.0,
						value = aiQuaternionToQuat(
							&animationNode.mRotationKeys[animationNode.mNumRotationKeys - 1].mValue,
						),
					}
					offset = 1
				} else {
					node.keyRotations = make([]valhalla.KeyQuat, animationNode.mNumRotationKeys)
				}
				for keyIndex in 0 ..< animationNode.mNumRotationKeys {
					rotationKey := &animationNode.mRotationKeys[keyIndex]
					node.keyRotations[keyIndex + offset] = {
						time  = rotationKey.mTime * ticksToSecond,
						value = aiQuaternionToQuat(&rotationKey.mValue),
					}
				}

				offset = 0
				if animationNode.mScalingKeys[0].mTime != 0.0 {
					node.keyScales = make([]valhalla.KeyVec3, animationNode.mNumScalingKeys + 1)
					node.keyScales[0] = {
						time  = 0.0,
						value = animationNode.mScalingKeys[animationNode.mNumScalingKeys - 1].mValue,
					}
					offset = 1
				} else {
					node.keyScales = make([]valhalla.KeyVec3, animationNode.mNumScalingKeys)
				}
				for keyIndex in 0 ..< animationNode.mNumScalingKeys {
					scaleKey := &animationNode.mScalingKeys[keyIndex]
					node.keyScales[keyIndex + offset] = {
						time  = scaleKey.mTime * ticksToSecond,
						value = scaleKey.mValue,
					}
				}
			}
		}
	}

	return scene.models[len(scene.models) - 1].graphicsData, .None
}
