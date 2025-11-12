package Valhalla

import ai "../assimp"
import "core:os/os2"
import "core:strings"

Scene :: struct {
	path:         string,
	name:         string,

	// Scene Settings
	ambientLight: f32,
	clearColour:  Vec4,

	// Assets
	models:       [dynamic]Model,
	textures:     [dynamic]Texture,
	objects:      [dynamic]Object,
	lights:       [dynamic]PointLight,
	cameras:      [dynamic]Camera,
	activeCamera: u32,
	vertexCount:  u32,
	vertices:     [dynamic]Vertex,
	indices:      [dynamic]u32,
	boneCount:    int,

	// Graphics Data
	buffers:      SceneBuffers,
}

deleteScene :: proc(scene: ^Scene) {
	delete(scene.name)

	for &model in scene.models {
		deleteModel(&model)
	}
	delete(scene.models)
	
	for &texture in scene.textures {
		deleteTexture(&texture)
	}
	delete(scene.textures)

	for &object in scene.objects {
		deleteGameObject(&object)
	}
	delete(scene.objects)

	for &light in scene.lights {
		deletePointLight(&light)
	}
	delete(scene.lights)

	for &camera in scene.cameras {
		deleteCamera(&camera)
	}
	delete(scene.cameras)

	delete(scene.vertices)
	delete(scene.indices)

	deleteSceneBuffers(&globals.graphicsContext, &scene.buffers)
}

Texture :: struct {
	path:      string,
	assetPath: string,
	name:      string,
	// I want to transition to having multiple vk.Images and binding them as opposed to how I do it right now.
	// vkImage: vk.Image,
	// memory:  vk.DeviceMemory,
	// view:    vk.ImageView,
	// format:  vk.Format,
	// sampler: u32,
}

deleteTexture :: proc(texture: ^Texture) {
	delete(texture.name)
	delete(texture.path)
	delete(texture.assetPath)
}

SceneData :: struct {
	nameLength:   u32,
	ambientLight: f32,
	clearColour:  Vec4,
	modelCount:   u32,
	textureCount: u32,
	objectCount:  u32,
	lightCount:   u32,
	cameraCount:  u32,
}

ObjectComponent :: struct {
	nameLength:    u32,
	position:      Vec3,
	rotation:      Quat,
	scale:         Vec3,
	modelIdx:      u32,
	texturesCount: u32,
	animation:     AnimationComponent,
	attachment:    Attachment,
}

AnimationComponent :: struct {
	idx:     i32,
	timer:   f64,
	playing: bool,
	end:     ObjectAnimationEnd,
}

LightComponent :: struct {
	nameLength: u32,
	position:   Vec3,
	colour:     Vec3,
	brightness: f32,
	dropoff:    f32,
}

CameraComponent :: struct {
	nameLength: u32,
	mode:       CameraMode,
	eye:        Vec3,
	center:     Vec3,
	up:         Vec3,
	fov:        f32,
	near:       f32,
	far:        f32,
}

SaveError :: enum {
	None,
	InvalidScene,
	InvalidSceneData,
	IO,
}

saveScene :: proc(scene: ^Scene) -> SaveError {
	if scene == nil {
		log(.Error, "Scene is nil")
		return .InvalidScene
	} else if scene.path == "" {
		log(.Error, "Scene path is empty")
		return .InvalidScene
	}

	for &model in scene.models {
		if saveModelComponent(&model) != .None {
			return .InvalidSceneData
		}
	}

	for &texture in scene.textures {
		if saveTextureComponent(&texture) != .None {
			return .InvalidSceneData
		}
	}

	file, err := os2.open(scene.path, {.Write, .Trunc, .Create})
	if err != nil {
		return .IO
	}
	defer os2.close(file)

	saveData := SceneData {
		nameLength   = u32(len(scene.name)),
		ambientLight = scene.ambientLight,
		clearColour  = scene.clearColour,
		modelCount   = u32(len(scene.models)),
		textureCount = u32(len(scene.textures)),
		objectCount  = u32(len(scene.objects)),
		lightCount   = u32(len(scene.lights)),
		cameraCount  = u32(len(scene.cameras)),
	}
	_, err = os2.write_ptr(file, &saveData, size_of(SceneData))
	if err != nil {
		return .IO
	}
	_, err = os2.write_string(file, scene.name)
	if err != nil {
		return .IO
	}

	for &model in scene.models {
		length := u32(len(model.path))
		os2.write_ptr(file, &length, size_of(u32))
		os2.write_string(file, model.path)
	}

	for &texture in scene.textures {
		length := u32(len(texture.path))
		os2.write_ptr(file, &length, size_of(u32))
		os2.write_string(file, texture.path)
	}

	for &object in scene.objects {
		objectData := ObjectComponent {
			nameLength = u32(len(object.name)),
			position = object.position,
			rotation = object.rotation,
			scale = object.scale,
			modelIdx = object.modelIdx,
			texturesCount = u32(len(object.textureIdxs)),
			animation = AnimationComponent {
				idx = object.animation.idx,
				timer = object.animation.timer,
				playing = object.animation.playing,
				end = object.animation.end,
			},
			attachment = object.attachment,
		}
		os2.write_ptr(file, &objectData, size_of(ObjectComponent))
		os2.write_string(file, object.name)
		os2.write_ptr(
			file,
			raw_data(object.textureIdxs),
			len(object.textureIdxs) * size_of([len(TextureIndex)]u32),
		)
	}

	for &light in scene.lights {
		lightData := LightComponent {
			nameLength = u32(len(light.name)),
			position   = light.position,
			colour     = light.colour,
			brightness = light.brightness,
			dropoff    = light.dropoff,
		}
		os2.write_ptr(file, &lightData, size_of(LightComponent))
		os2.write_string(file, light.name)
	}

	for &camera in scene.cameras {
		cameraData := CameraComponent {
			nameLength = u32(len(camera.name)),
			mode       = camera.mode,
			eye        = camera.eye,
			center     = camera.center,
			up         = camera.up,
			fov        = camera.fov,
			near       = camera.near,
			far        = camera.far,
		}
		os2.write_ptr(file, &cameraData, size_of(CameraComponent))
		os2.write_string(file, camera.name)
	}

	return .None
}

LoadError :: enum {
	None,
	InvalidArgument,
	IO,
	Asset,
}

loadScene :: proc(scene: ^Scene) -> LoadError {
	if scene == nil || scene.path == "" {
		return .InvalidArgument
	}

	file, err := os2.open(scene.path, {.Read})
	if err != nil {
		return .IO
	}
	defer os2.close(file)

	sceneData: SceneData
	os2.read_ptr(file, &sceneData, size_of(SceneData))

	scene.name         = string(make([]byte, sceneData.nameLength))
	scene.ambientLight = sceneData.ambientLight
	scene.clearColour  = sceneData.clearColour
	scene.models       = make([dynamic]Model, sceneData.modelCount)
	scene.textures     = make([dynamic]Texture, sceneData.textureCount)
	scene.objects      = make([dynamic]Object, sceneData.objectCount)
	scene.lights       = make([dynamic]PointLight, sceneData.lightCount)
	scene.cameras      = make([dynamic]Camera, sceneData.cameraCount)
	scene.boneCount    = 1

	os2.read(file, transmute([]byte)scene.name)

	for &model in scene.models {
		pathLength: u32
		os2.read_ptr(file, &pathLength, size_of(u32))
		modelPath := make([]byte, pathLength)
		os2.read(file, modelPath)

		model.path = string(modelPath)
		lerr := loadModelComponent(&model)
		if lerr != .None {
			logf(.Error, "Failed to load model \"%s\": %v", modelPath, lerr)
			return lerr
		}

		lerr = loadModel(scene, &model)
		if lerr != .None {
			logf(.Error, "Failed to load model data \"%s\": %v", modelPath, lerr)
			return .Asset
		}
	}

	texPaths := make([]string, sceneData.textureCount)
	defer delete(texPaths)
	for &texture, idx in scene.textures {
		pathLength: u32
		os2.read_ptr(file, &pathLength, size_of(u32))
		texturePath := make([]byte, pathLength)
		os2.read(file, texturePath)

		texture.path = string(texturePath)
		lerr := loadTextureComponent(&texture)
		if lerr != .None {
			logf(.Error, "Failed to load texture \"%s\": %v", texturePath, lerr)
			return lerr
		}

		texPaths[idx] = texture.assetPath
	}
	lerr := loadImages(&globals.graphicsContext, scene, texPaths)
	if lerr != nil {
		logf(.Error, "Failed to load images: %v", lerr)
		return .Asset
	}

	for &object, objectIdx in scene.objects {
		objectData: ObjectComponent
		os2.read_ptr(file, &objectData, size_of(ObjectComponent))
		object = {
			name = string(make([]byte, objectData.nameLength)),
			position = objectData.position,
			rotation = objectData.rotation,
			scale = objectData.scale,
			modelIdx = objectData.modelIdx,
			instanceIdx = addInstance(scene, &scene.models[objectData.modelIdx], u32(objectIdx)),
			textureIdxs = make([][len(TextureIndex)]u32, objectData.texturesCount),
			animation = ObjectAnimation {
				idx = objectData.animation.idx,
				timer = objectData.animation.timer,
				playing = objectData.animation.playing,
				state = make([]Mat4, len(scene.models[objectData.modelIdx].skeleton)),
				cache = make([]ObjectAnimationCache, len(scene.models[objectData.modelIdx].skeleton)),
				end = objectData.animation.end,
			},
			attachment = objectData.attachment,
		}
		os2.read(file, transmute([]byte)object.name)
		os2.read_ptr(
			file,
			raw_data(object.textureIdxs),
			int(objectData.texturesCount) * size_of([len(TextureIndex)]u32),
		)
	}

	for &light in scene.lights {
		lightData: LightComponent
		os2.read_ptr(file, &lightData, size_of(LightComponent))
		light = {
			name       = string(make([]byte, lightData.nameLength)),
			position   = lightData.position,
			colour     = lightData.colour,
			brightness = lightData.brightness,
			dropoff    = lightData.dropoff,
		}
		os2.read(file, transmute([]byte)light.name)
	}

	for &camera in scene.cameras {
		cameraData: CameraComponent
		os2.read_ptr(file, &cameraData, size_of(CameraComponent))
		camera = {
			name   = string(make([]byte, cameraData.nameLength)),
			eye    = cameraData.eye,
			center = cameraData.center,
			up     = cameraData.up,
			fov    = cameraData.fov,
			near   = cameraData.near,
			far    = cameraData.far,
		}
		os2.read(file, transmute([]byte)camera.name)
	}

	return .None
}

ModelComponent :: struct {
	nameLength:     u32,
	pathLength:     u32,
	position:       Vec3,
	rotation:       Quat,
	scale:          Vec3,
	bindpointCount: u32,
}

saveModelComponent :: proc(model: ^Model) -> SaveError {
	if model.path == "" {
		logf(.Error, "Model \"%s\" path is empty", model.name)
		return .InvalidSceneData
	}

	file, err := os2.open(model.path, {.Write, .Create, .Trunc})
	if err != nil {
		return .InvalidSceneData
	}
	defer os2.close(file)

	modelData := ModelComponent {
		nameLength     = u32(len(model.name)),
		pathLength     = u32(len(model.assetPath)),
		position       = model.position,
		rotation       = model.rotation,
		scale          = model.scale,
		bindpointCount = u32(len(model.bindpoints)),
	}
	os2.write_ptr(file, &modelData, size_of(ModelComponent))
	os2.write_string(file, model.name)
	os2.write_string(file, model.assetPath)
	os2.write_ptr(file, raw_data(model.bindpoints), len(model.bindpoints) * size_of(Bindpoint))

	return .None
}

loadModelComponent :: proc(model: ^Model) -> LoadError {
	if model.path == "" {
		return .InvalidArgument
	}

	file, err := os2.open(model.path, {.Read})
	if err != nil {
		return .IO
	}

	modelData: ModelComponent
	os2.read_ptr(file, &modelData, size_of(ModelComponent))

	model.assetPath = string(make([]byte, modelData.pathLength))
	model.name = string(make([]byte, modelData.nameLength))
	model.position = modelData.position
	model.rotation = modelData.rotation
	model.scale = modelData.scale
	model.bindpoints = make([dynamic]Bindpoint, modelData.bindpointCount)
	os2.read(file, transmute([]byte)model.name)
	os2.read(file, transmute([]byte)model.assetPath)
	os2.read_ptr(
		file,
		raw_data(model.bindpoints),
		int(modelData.bindpointCount * size_of(Bindpoint)),
	)

	return .None
}

loadModel :: proc(scene: ^Scene, model: ^Model) -> LoadError {
	aiStringToString :: proc(aiStr: ^ai.String, allocator := context.allocator) -> string {
		return strings.clone_from_bytes(
			transmute([]u8)aiStr.data[:aiStr.length],
			allocator = allocator,
		)
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
		// Maybe I should use this and add logging.
		// .ValidateDataStructure,
		.ImproveCacheLocality,
		.SortByPType,
		.FindDegenerates,
		.FindInvalidData,
		.GenUVCoords,
		.OptimizeMeshes,
		.OptimizeGraph,
		// Correct the UVs and winding order for Vulkan.
		.FlipUVs,
		.FlipWindingOrder,
		.GenBoundingBoxes,
	}

	aiScene := ai.ImportFileExWithProperties(
		strings.clone_to_cstring(model.assetPath, context.temp_allocator),
		IMPORT_FLAGS,
		nil,
		propertyStore,
	)
	if aiScene == nil {
		logf(.Error, "Failed to load file: %s", ai.GetErrorString())
		return .IO
	}
	defer ai.FreeScene(aiScene)

	if aiScene.mNumMeshes == 0 {
		log(.Error, "Model has no meshes!")
		return .InvalidArgument
	}

	// I'm finding meshes this way as the names of the meshes are rarely correct so I use the node name instead.
	findMeshes :: proc(
		aiScene: ^ai.Scene,
		node: ^ai.Node,
		meshes: ^[]Mesh,
		boneNames: ^map[string]struct{},
	) {
		if node.mNumMeshes == 1 {
			mesh := aiScene.mMeshes[node.mMeshes[0]]

			meshes[node.mMeshes[0]] = {
				name        = aiStringToString(&node.mName),
				vertexCount = mesh.mNumVertices,
				indexCount  = mesh.mNumFaces * 3,
				boundingBox = {mesh.mAABB.mMin, mesh.mAABB.mMax},
			}

			for &bone in mesh.mBones[:mesh.mNumBones] {
				if str := aiStringToString(&bone.mName, context.temp_allocator);
				   str not_in boneNames {
					boneNames[str] = {}
				}
			}
		}

		for &child in node.mChildren[:node.mNumChildren] {
			findMeshes(aiScene, child, meshes, boneNames)
		}
	}

	model.meshes = make([]Mesh, aiScene.mNumMeshes)
	boneNames := make(map[string]struct{})
	defer delete(boneNames)
	findMeshes(aiScene, aiScene.mRootNode, &model.meshes, &boneNames)

	findBones :: proc(node: ^ai.Node, boneNames: ^map[string]struct{}, boneMap: ^map[string]u32) {
		if str := aiStringToString(&node.mName, context.temp_allocator); str in boneNames {
			boneMap[str] = u32(len(boneMap))
		}
		for &child in node.mChildren[:node.mNumChildren] {
			findBones(child, boneNames, boneMap)
		}
	}

	boneMap := make(map[string]u32)
	defer delete(boneMap)

	findBones(aiScene.mRootNode, &boneNames, &boneMap)
	model.skeleton = make([]Bone, len(boneMap))

	vertexOffset := u32(len(scene.vertices))
	for &mesh, meshIndex in model.meshes {
		sceneMesh := aiScene.mMeshes[meshIndex]

		mesh.vertexOffset = u32(len(scene.vertices))
		mesh.indexOffset = u32(len(scene.indices))

		for vertexIndex in 0 ..< sceneMesh.mNumVertices {
			append(
				&scene.vertices,
				Vertex {
					position = sceneMesh.mVertices[vertexIndex],
					normal = sceneMesh.mNormals[vertexIndex],
					tangent = sceneMesh.mTangents[vertexIndex],
					bitangent = sceneMesh.mBitangents[vertexIndex],
					uv = {
						sceneMesh.mTextureCoords[0][vertexIndex].x,
						sceneMesh.mTextureCoords[0][vertexIndex].y,
					},
					weights = {0.0, 0.0, 0.0, 0.0},
					bones = {0, 0, 0, 0},
				},
			)
		}

		for faceIdx in 0 ..< sceneMesh.mNumFaces {
			face := &sceneMesh.mFaces[faceIdx]
			for indiceIdx in 0 ..< 3 {
				append(&scene.indices, u32(face.mIndices[indiceIdx]))
			}
		}

		for idx in 0 ..< sceneMesh.mNumBones {
			sceneBone := sceneMesh.mBones[idx]
			boneIdx := boneMap[aiStringToString(&sceneBone.mName, context.temp_allocator)]

			model.skeleton[boneIdx].offsetMatrix = aiMatrixToMat4(&sceneBone.mOffsetMatrix)

			for weightIdx in 0 ..< sceneBone.mNumWeights {
				weight := &sceneBone.mWeights[weightIdx]
				vertex := &scene.vertices[u32(weight.mVertexId) + mesh.vertexOffset]

				for n in 0 ..< 4 {
					if vertex.weights[n] == 0 {
						vertex.weights[n] = f32(weight.mWeight)
						vertex.bones[n] = u32(boneIdx)
						break
					} else if n == 3 {
						// Assimp should limit the number of weights to 4.
						// If we reach here then something has gone wrong.
						logf(.Warning, "Vertex has more than 4 bone weights!")
					}
				}
			}
		}
	}

	for &vertex in scene.vertices[vertexOffset:] {
		if sum := vertex.weights.x + vertex.weights.y + vertex.weights.z + vertex.weights.w;
		   sum == 0 {
			vertex.weights = {1, 0, 0, 0}
			vertex.bones = {0, 0, 0, 0}
		} else if sum != 1 {
			vertex.weights /= sum
		}
	}

	if len(model.skeleton) > 0 {
		searchNodeTree :: proc(node: ^ai.Node, skeleton: ^[]Bone, boneMap: ^map[string]u32) {
			if node == nil {
				return
			}

			if boneIdx, isBone := boneMap[aiStringToString(&node.mName, context.temp_allocator)];
			   isBone {
				parent := node.mParent

				parentIndex: u32 = 0
				isParentBone := false
				for parentIndex, isParentBone =
					    boneMap[aiStringToString(&parent.mName, context.temp_allocator)];
				    !isParentBone;
				    parentIndex, isParentBone =
					    boneMap[aiStringToString(&parent.mName, context.temp_allocator)] {
					parent = parent.mParent
					if parent == nil {
						break
					}
				}
				skeleton[boneIdx].name = aiStringToString(&node.mName)
				skeleton[boneIdx].parentIdx = parentIndex
			}

			for childIndex in 0 ..< node.mNumChildren {
				searchNodeTree(node.mChildren[childIndex], skeleton, boneMap)
			}
		}

		searchNodeTree(aiScene.mRootNode, &model.skeleton, &boneMap)
		model.animations = make([]Animation, aiScene.mNumAnimations)
		for &animation, animationIdx in model.animations {
			translateInterpolation :: proc(
				aiInterpolation: ai.Anim_Interpolation,
			) -> InterpolationType {
				switch aiInterpolation {
				case .Step:
					return .Step
				case .Linear:
					return .Linear
				case .Spherical_Linear:
					return .SphericalLinear
				case .Cubic_Spline:
					return .CubicSpline
				}
				panic("Unreachable!")
			}

			sceneAnimation := aiScene.mAnimations[animationIdx]

			ticksToSeconds :=
				1 / (sceneAnimation.mTicksPerSecond == 0.0 ? 1.0 : sceneAnimation.mTicksPerSecond)
			animation = {
				name     = aiStringToString(&sceneAnimation.mName),
				duration = sceneAnimation.mDuration * ticksToSeconds,
				nodes    = make([]AnimationNode, len(model.skeleton)),
			}

			for &node in animation.nodes {
				node = {
					keyPositions = {{time = animation.duration, value = {0, 0, 0}}},
					keyRotations = {{time = animation.duration, value = IQUAT}},
					keyScales    = {{time = animation.duration, value = {1, 1, 1}}},
				}
			}

			for nodeIdx in 0 ..< sceneAnimation.mNumChannels {
				animationNode := sceneAnimation.mChannels[nodeIdx]

				boneIdx, exists :=
					boneMap[aiStringToString(&animationNode.mNodeName, context.temp_allocator)]
				if !exists {
					continue
				}

				node := &animation.nodes[boneIdx]
				offset: u32 = 0
				if animationNode.mPositionKeys[0].mTime != 0.0 {
					node.keyPositions = make([]KeyValue(Vec3), animationNode.mNumPositionKeys + 1)
					node.keyPositions[0] = {
						time          = 0.0,
						value         = animationNode.mPositionKeys[animationNode.mNumPositionKeys - 1].mValue,
						interpolation = translateInterpolation(
							animationNode.mPositionKeys[animationNode.mNumPositionKeys - 1].mInterpolation,
						),
					}
					offset = 1
				} else {
					node.keyPositions = make([]KeyValue(Vec3), animationNode.mNumPositionKeys)
				}
				for keyIdx in 0 ..< animationNode.mNumPositionKeys {
					positionKey := &animationNode.mPositionKeys[keyIdx]
					node.keyPositions[keyIdx + offset] = {
						time          = positionKey.mTime * ticksToSeconds,
						value         = positionKey.mValue,
						interpolation = translateInterpolation(positionKey.mInterpolation),
					}
				}

				offset = 0
				if animationNode.mRotationKeys[0].mTime != 0.0 {
					node.keyRotations = make([]KeyValue(Quat), animationNode.mNumRotationKeys + 1)
					node.keyRotations[0] = {
						time          = 0.0,
						value         = aiQuaternionToQuat(
							&animationNode.mRotationKeys[animationNode.mNumRotationKeys - 1].mValue,
						),
						interpolation = translateInterpolation(
							animationNode.mRotationKeys[animationNode.mNumRotationKeys - 1].mInterpolation,
						),
					}
					if node.keyRotations[0].interpolation == .Linear {
						node.keyRotations[0].interpolation = .SphericalLinear
					}
					offset = 1
				} else {
					node.keyRotations = make([]KeyValue(Quat), animationNode.mNumRotationKeys)
				}
				for keyIdx in 0 ..< animationNode.mNumRotationKeys {
					rotationKey := &animationNode.mRotationKeys[keyIdx]
					key := &node.keyRotations[keyIdx + offset]
					key^ = {
						time          = rotationKey.mTime * ticksToSeconds,
						value         = aiQuaternionToQuat(&rotationKey.mValue),
						interpolation = translateInterpolation(rotationKey.mInterpolation),
					}
					if key.interpolation == .Linear {
						key.interpolation = .SphericalLinear
					}
				}

				offset = 0
				if animationNode.mScalingKeys[0].mTime != 0.0 {
					node.keyScales = make([]KeyValue(Vec3), animationNode.mNumScalingKeys + 1)
					node.keyScales[0] = {
						time          = 0.0,
						value         = animationNode.mScalingKeys[animationNode.mNumScalingKeys - 1].mValue,
						interpolation = translateInterpolation(
							animationNode.mScalingKeys[animationNode.mNumScalingKeys - 1].mInterpolation,
						),
					}
					offset = 1
				} else {
					node.keyScales = make([]KeyValue(Vec3), animationNode.mNumScalingKeys)
				}
				for keyIdx in 0 ..< animationNode.mNumScalingKeys {
					scaleKey := &animationNode.mScalingKeys[keyIdx]
					node.keyScales[keyIdx + offset] = {
						time          = scaleKey.mTime * ticksToSeconds,
						value         = scaleKey.mValue,
						interpolation = translateInterpolation(scaleKey.mInterpolation),
					}
				}
			}
		}
	}

	return .None
}

TextureComponent :: struct {
	nameLength: u32,
	pathLength: u32,
	// In the future I should generate bitmaps from the image at path
	// and save the bitmap in a file so I can load it later
	// width, height: u32,
	// miplevels: u32,
	// data: []byte,
}

saveTextureComponent :: proc(texture: ^Texture) -> SaveError {
	if texture.path == "" {
		logf(.Error, "Texture \"%s\" path is empty", texture.name)
		return .InvalidSceneData
	}

	file, err := os2.open(texture.path, {.Write, .Create, .Trunc})
	if err != nil {
		return .IO
	}
	defer os2.close(file)

	textureData := TextureComponent {
		nameLength = u32(len(texture.name)),
		pathLength = u32(len(texture.assetPath)),
	}
	os2.write_ptr(file, &textureData, size_of(TextureComponent))
	os2.write_string(file, texture.name)
	os2.write_string(file, texture.assetPath)

	return .None
}

loadTextureComponent :: proc(texture: ^Texture) -> LoadError {
	if texture.path == "" {
		return .InvalidArgument
	}

	file, err := os2.open(texture.path, {.Read})
	if err != nil {
		return .IO
	}
	defer os2.close(file)

	textureData: TextureComponent
	os2.read_ptr(file, &textureData, size_of(TextureComponent))

	texture.assetPath = string(make([]byte, textureData.pathLength))
	texture.name = string(make([]byte, textureData.nameLength))

	os2.read(file, transmute([]byte)texture.name)
	os2.read(file, transmute([]byte)texture.assetPath)

	return .None
}
