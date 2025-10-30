package Valhalla

import ai "../assimp"
import "core:strings"

Scene :: struct {
	filePath:      string,
	name:          string,

	// Scene Settings
	ambientLight:  f32,
	clearColour:   Vec4,

	// Assets
	models:        [dynamic]Model,
	objects:       [dynamic]GameObject,
	lights:        [dynamic]PointLight,
	cameras:       [dynamic]Camera,
	activeCamera:  u32,
	vertexCount:   u32,
	textureCount:  u32,
	vertices:      [dynamic]Vertex,
	indices:       [dynamic]u32,
	instanceCount: int,
	boneCount:     int,

	// Graphics Data
	buffers:       SceneBuffers,
}

// ATM we can't have a truly "empty" scene as we have to make buffers and images that must exist.
// It might be possible to make the buffers optional to solve this?
createNewScene :: proc() -> (scene: Scene) {
	scene.filePath = ""
	scene.name = strings.clone("New Scene")
	scene.boneCount = 1

	if loadSceneAssets(
		   &scene,
		   {"./assets/cube/cube.fbx", "./assets/mage/Mage_Simplified.glb"},
		   {"./assets/cube/white.jpg", "./assets/blank_normal.jpg", "./assets/mage/texture.png"},
	   ) !=
	   nil {
		panic("Failed to load scene assets")
	}

	scene.models[0].name = strings.clone("Meter Cube")
	scene.models[0].scale = {0.5, 0.5, 0.5}

	scene.models[1].name = strings.clone("Knight Model")
	scene.models[1].scale = {0.165, 0.165, 0.165}
	scene.models[1].rotation = quatFromEuler(0, 0, 0, .XYZ)

	scene.clearColour = {0.5, 0.5, 0.5, 1.0}
	scene.ambientLight = 0.25

	append(
		&scene.objects,
		GameObject {
			name = strings.clone("Floor"),
			position = {0, -0.05, 0},
			rotation = IQUAT,
			scale = {10, 0.1, 10},
			modelIdx = 0,
			instanceIdx = addInstance(&scene, &scene.models[0], u32(len(scene.objects))),
			textureIdxs = make([][len(TextureIndex)]u32, len(scene.models[0].meshes)),
			animation = ObjectAnimation{idx = -1},
		},
	)

	for i in 0 ..< len(scene.models[scene.objects[0].modelIdx].meshes) {
		scene.objects[0].textureIdxs[i][TextureIndex.ALBEDO] = 0
		scene.objects[0].textureIdxs[i][TextureIndex.NORMAL_MAP] = 1
	}

	append(
		&scene.objects,
		GameObject {
			name = strings.clone("Knight"),
			position = {0, 0, 0},
			rotation = IQUAT,
			scale = {1, 1, 1},
			modelIdx = 1,
			instanceIdx = addInstance(&scene, &scene.models[1], u32(len(scene.objects))),
			textureIdxs = make([][len(TextureIndex)]u32, len(scene.models[1].meshes)),
			animation = ObjectAnimation {
				idx = 0,
				timer = 0,
				state = make([]Mat4, len(scene.models[1].skeleton)),
				cache = make([]ObjectAnimationCache, len(scene.models[1].skeleton)),
				playing = true,
				end = ObjectAnimationEnd{behavior = .Loop, transition = {}, nextIdx = -1},
			},
		},
	)

	for i in 0 ..< len(scene.models[scene.objects[1].modelIdx].meshes) {
		scene.objects[1].textureIdxs[i][TextureIndex.ALBEDO] = 2
		scene.objects[1].textureIdxs[i][TextureIndex.NORMAL_MAP] = 1
	}

	scene.lights = make([dynamic]PointLight, 1)
	scene.lights[0] = {
		name       = strings.clone("light"),
		position   = {0, 1.5, -0.5},
		colour     = {1, 1, 1},
		brightness = 1,
		dropoff    = 5,
	}

	scene.cameras = make([dynamic]Camera, 1)
	scene.cameras[0] = {
		name   = strings.clone("main"),
		mode   = .PERSPECTIVE,
		eye    = {0.0, 2.0, -4.0},
		center = {0.0, 0.0, 0.0},
		up     = {0.0, 1.0, 0.0},
		fov    = 45.0,
		near   = 0.1,
		far    = 100.0,
	}
	scene.activeCamera = 0

	return
}

deleteScene :: proc(scene: ^Scene) {
	delete(scene.filePath)
	delete(scene.name)

	for &model in scene.models {
		deleteModel(&model)
	}
	delete(scene.models)

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

loadSceneAssets :: proc(scene: ^Scene, modelPaths: []string, texturePaths: []string) -> Error {
	// Load Models
	for path in modelPaths {
		if err := loadModel(path, scene); err != nil {
			return err
		}
	}

	// Load Textures
	if err := loadImages(&globals.graphicsContext, scene, texturePaths); err != nil {
		return err
	}
	scene.textureCount = u32(len(texturePaths))

	return nil
}

loadModel :: proc(filename: string, scene: ^Scene) -> LoaderError {
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
		strings.clone_to_cstring(filename, context.temp_allocator),
		IMPORT_FLAGS,
		nil,
		propertyStore,
	)
	if aiScene == nil {
		logf(.Error, "Failed to load file: %s", ai.GetErrorString())
		return .FailedToLoadFile
	}
	defer ai.FreeScene(aiScene)

	if aiScene.mNumMeshes == 0 {
		log(.Error, "Model has no meshes!")
		return .InvalidFileData
	}

	model: Model
	model.meshes = make([]Mesh, aiScene.mNumMeshes)

	boneNames := make(map[string]struct{})
	defer delete(boneNames)

	vertexCount: u32 = 0
	indexCount: u32 = 0
	for &mesh, meshIndex in model.meshes {
		sceneMesh := aiScene.mMeshes[meshIndex]

		if .TRIANGLE not_in sceneMesh.mPrimitiveTypes {
			continue
		}

		mesh = {
			name = aiStringToString(&sceneMesh.mName),
			vertexOffset = u32(len(scene.vertices)) + vertexCount,
			vertexCount = sceneMesh.mNumVertices,
			indexOffset = u32(len(scene.indices)) + indexCount,
			indexCount = sceneMesh.mNumFaces * 3,
			boundingBox = {min = sceneMesh.mAABB.mMin, max = sceneMesh.mAABB.mMax},
		}
		vertexCount += mesh.vertexCount
		indexCount += mesh.indexCount
		
		for &bone in sceneMesh.mBones[:sceneMesh.mNumBones] {
		  if str := aiStringToString(&bone.mName, context.temp_allocator); str not_in boneNames {
		    boneNames[str] = {}
			}
		}
	}

	vertexOffset := u32(len(scene.vertices))
	reserve(&scene.vertices, u32(len(scene.vertices)) + vertexCount)
	reserve(&scene.indices, u32(len(scene.indices)) + indexCount)

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

	for &mesh, meshIndex in model.meshes {
		sceneMesh := aiScene.mMeshes[meshIndex]

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

	for idx in vertexOffset ..< u32(len(scene.vertices)) {
		vertex := &scene.vertices[idx]
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

			if boneIndex, isBone := boneMap[aiStringToString(&node.mName, context.temp_allocator)];
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
				skeleton[boneIndex].parentIndex = parentIndex
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
					offset = 1
				} else {
					node.keyRotations = make([]KeyValue(Quat), animationNode.mNumRotationKeys)
				}
				for keyIdx in 0 ..< animationNode.mNumRotationKeys {
					rotationKey := &animationNode.mRotationKeys[keyIdx]
					node.keyRotations[keyIdx + offset] = {
						time          = rotationKey.mTime * ticksToSeconds,
						value         = aiQuaternionToQuat(&rotationKey.mValue),
						interpolation = translateInterpolation(rotationKey.mInterpolation),
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

	append(&scene.models, model)
	return .None
}
