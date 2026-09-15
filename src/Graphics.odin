#+feature using-stmt
package Valhalla

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "vendor:glfw"
import img "vendor:stb/image"
import vk "vendor:vulkan"

import "../imgui"
import imguiGLFW "../imgui/imgui_impl_glfw"
import imguiVulkan "../imgui/imgui_impl_vulkan"


// ===[ Configuration ]========================================================

VERSION: u32 : (0 << 22) | (1 << 12) | (0)

HDR_DEFAULT: bool : true

PAPER_WHITE_NITS: f32 : 200.0

@(private = "file")
REQUESTED_LAYERS: []cstring : {"VK_LAYER_KHRONOS_validation"}

@(private = "file")
INSTANCE_EXTENSIONS: []cstring : {
	vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
	vk.EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME,
	vk.KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME,
	vk.EXT_SURFACE_MAINTENANCE_1_EXTENSION_NAME,
}

@(private = "file")
DEVICE_EXTENSIONS: []cstring : {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.EXT_MEMORY_BUDGET_EXTENSION_NAME,
	vk.EXT_DESCRIPTOR_HEAP_EXTENSION_NAME,
	vk.KHR_SHADER_UNTYPED_POINTERS_EXTENSION_NAME,
	vk.EXT_MEMORY_PRIORITY_EXTENSION_NAME,
	vk.EXT_PAGEABLE_DEVICE_LOCAL_MEMORY_EXTENSION_NAME,
	vk.EXT_SWAPCHAIN_MAINTENANCE_1_EXTENSION_NAME,
}



@(private = "file")
MAX_FRAMES_IN_FLIGHT: u32 : 2

RENDER_SIZE: [2]u32 : {1920, 1080}

@(private = "file")
SHADOW_RESOLUTION: [2]u32 : {512, 512}

@(private = "file")
SHADOW_CUBE_FACES :: 6

@(private = "file")
SHADOW_VIEW_MASK :: u32(1 << SHADOW_CUBE_FACES) - 1

@(private = "file")
DYNAMIC_VIEWPORT_STATES := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}

@(private = "file")
DEPTH_BIAS_CONSTANT: f32 : 1.25

@(private = "file")
DEPTH_BIAS_SLOPE: f32 : 1.75


// ===[ Errors ]===============================================================

ErrorLevel :: enum {
	Warning,
	Error,
	Fatal,
}

Error :: union #shared_nil {
	InitError,
	InstanceError,
	WindowError,
	DeviceError,
	SwapchainError,
	CommandBufferError,
	SyncError,
	SamplerError,
	LoaderError,
	ImageError,
	BufferError,
	StagingError,
	DescriptorHeapError,
	DrawError,
}

InitError :: enum {
	None = 0,
	InitError,
	GLFWError,
	DepthFormatError,
}

InstanceError :: enum {
	None = 0,
	FailedToCreateInstance,
}

WindowError :: enum {
	None = 0,
	FailedToCreateWindow,
	FailedToCreateSurface,
}

DeviceError :: enum {
	None = 0,
	FailedToFindSuitableDevice,
	FailedToCreateDevice,
}

SwapchainError :: enum {
	None = 0,
	FailedToCreateSwapchain,
	FailedToRecreateSwapchain,
	FailedToCreateSwapchainImageView,
}

CommandBufferError :: enum {
	None = 0,
	FailedToCreateCommandPool,
	FailedToAllocateCommandBuffer,
	FailedToBeginCommandBuffer,
	FailedToEndCommandBuffer,
}

BufferError :: enum {
	None = 0,
	FailedToCreateBuffer,
	FailedToAllocateBufferMemory,
	FailedToBindBufferMemory,
	FailedToLoadBufferToGPU,
}

ImageError :: enum {
	None = 0,
	FailedToCreateImage,
	FailedToAllocateImageMemory,
	FailedToBindImageMemory,
	FailedToCreateImageView,
	TransitionFailed,
	FailedToLoadImage,
}

SamplerError :: enum {
	None = 0,
	FailedToCreateSampler,
}

LoaderError :: enum {
	None = 0,
	FailedToLoadFile,
	InvalidFileData,
}

SyncError :: enum {
	None = 0,
	FailedToCreateFence,
	FailedToCreateSemaphore,
}

DrawError :: enum {
	None = 0,
	UpdateCommandBuffers,
	FailedToAcquireSwapchainImage,
	FailedToSubmitPreCommandBuffer,
	FailedToSubmitMainCommandBuffer,
	FailedToSubmitPostCommandBuffer,
	FailedToSubmitUICommandBuffer,
	FailedToPresentSwapchainImage,
}

@(private = "file")
MemoryError :: enum {
	None = 0,
	NoSuitableMemoryType,
	FailedToAllocate,
	FailedToMap,
	OutOfBudget,
}

StagingError :: enum {
	None = 0,
	FailedToCreateBuffer,
	FailedToCreateSemaphore,
	FailedToRecord,
	FailedToSubmit,
}

@(private = "file")
DescriptorHeapError :: enum {
	None = 0,
	FailedToCreateHeap,
	HeapTooSmall,
	OutOfTextureSlots,
}


// ===[ Shared Types ]=========================================================

WindowHandle :: glfw.WindowHandle

GLFWKeyCallback :: glfw.KeyProc

GLFWMouseButtonCallback :: glfw.MouseButtonProc

GLFWCursorPosCallback :: glfw.CursorPosProc

GLFWScrollCallback :: glfw.ScrollProc

GLFWErrorCallback :: glfw.ErrorProc

GLFWWindowRefreshCallback :: glfw.WindowRefreshProc

GLFWFramebufferSizeCallback :: glfw.FramebufferSizeProc

@(private = "file")
HeapIndices :: struct {
	vertexBuffer:       u32,
	uniformBuffer:      u32,
	instanceBuffer:     u32,
	boneBuffer:         u32,
	transformBuffer:    u32,
	positionBuffer:     u32,
	lightBuffer:        u32,
	textureIndexBuffer: u32,
	shadowMap:          u32,
	sceneDepth:         u32,
	renderedImage:      u32,
	processedImage:     u32,
	linearSampler:      u32,
	anisotropicSampler: u32,
}

Transform_PushConstants :: struct {
	resources:       HeapIndices,
	instance:        u32,
	instanceCount:   u32,
	vertexCount:     u32,
	vertexOffset:    u32,
	transformOffset: u32,
}

@(private = "file")
Light_PushConstants :: struct {
	resources:       HeapIndices,
	lightIndex:   u32,
	vertexOffset: u32,
	vertexCount:  u32,
}

@(private = "file")
Scene_PushConstants :: struct {
	resources:       HeapIndices,
	vertexOffset:   u32,
	vertexCount:    u32,
	instanceOffset: u32,
}

@(private = "file")
Gizmo_PushConstants :: struct {
	resources: HeapIndices,
	radius:    f32,
}

@(private = "file")
PostProcess_PushConstants :: struct {
	resources:       HeapIndices,
	contrast:   f32,
	brightness: f32,
	saturation: f32,
	exposure:   f32,
	tonemapper: ToneMapper,
	gamma:      f32,
	contentOffsetX: u32,
	contentOffsetY: u32,
	contentExtentX: u32,
	contentExtentY: u32,
	transferFunction: TransferFunction,
	paperWhiteNits: f32,
}

TransferFunction :: enum u32 {
	Gamma = 0,
	PQ    = 1,
}

ToneMapper :: enum u32 {
	None          = 0,
	NarkowiczACES = 1,
}

Vertex :: struct #align (16) {
	position:  Vec3,
	_:         u32,
	normal:    Vec3,
	_:         u32,
	tangent:   Vec3,
	_:         u32,
	bitangent: Vec3,
	_:         u32,
	uv:        Vec2,
	_:         u64,
	bones:     [4]u32,
	weights:   Vec4,
}

@(private = "file")
LightData :: struct #align (16) {
	position: Vec3,
	_:        u32,
	lumens:   Vec3,
	near:     f32,
	far:      f32,
}

@(private = "file")
UniformBuffer :: struct #align (16) {
	projection:     Mat4,
	viewProjection: Mat4,
	lightCount:     u32,
	ambientLight:   f32,
	_:              [2]u32,
	cameraPosition: Vec3,
	_:              u32,
}

@(private = "file")
InstanceInfo :: struct #align (16) {
	modelTransform: Mat4,
	boneOffset:     u32,
}

vkDebugMessengerCreateInfo :: vk.DebugUtilsMessengerCreateInfoEXT

@(private = "file")
SemaphoreIndex :: enum {
	Transform = 0,

	Image,
}

@(private = "file")
CmdBufferIndex :: enum {
	Transform = 0,
	Light,
	Scene,
	PostProcess,
	Imgui,
}

TextureIndex :: enum {
	Albedo,
	NormalMap,
	// MATERIAL,
	// ROUGHNESS,
}

GLFWCallbacks :: struct {
	errorCallback:       GLFWErrorCallback,
	keyCallback:         GLFWKeyCallback,
	mouseButtonCallback: GLFWMouseButtonCallback,
	cursorPosCallback:   GLFWCursorPosCallback,
	scrollCallback:      GLFWScrollCallback,
}

SceneBuffers :: struct {
	textures:           [dynamic]Image,
	// TODO: Combine buffers into one buffer using offsets
	vertexBuffer:       Buffer,
	indexBuffer:        Buffer,
	instanceBuffers:    [MAX_FRAMES_IN_FLIGHT]Buffer,
	boneBuffers:        [MAX_FRAMES_IN_FLIGHT]Buffer,
	lightBuffers:       [MAX_FRAMES_IN_FLIGHT]Buffer,
	transformBuffers:   [MAX_FRAMES_IN_FLIGHT]Buffer,
	positionBuffers:    [MAX_FRAMES_IN_FLIGHT]Buffer,
	textureIndexBuffer: Buffer,
}

deleteSceneBuffers :: proc(using graphicsData: ^GraphicsData, buffers: ^SceneBuffers) {
	deleteBuffer(graphicsData, &buffers.indexBuffer)
	deleteBuffer(graphicsData, &buffers.vertexBuffer)

	for idx in 0 ..< MAX_FRAMES_IN_FLIGHT {
		deleteBuffer(graphicsData, &buffers.instanceBuffers[idx])
		deleteBuffer(graphicsData, &buffers.boneBuffers[idx])
		deleteBuffer(graphicsData, &buffers.lightBuffers[idx])
		deleteBuffer(graphicsData, &buffers.transformBuffers[idx])
		deleteBuffer(graphicsData, &buffers.positionBuffers[idx])
	}
	deleteBuffer(graphicsData, &buffers.textureIndexBuffer)

	for &texture in buffers.textures {
		releaseTextureSlot(graphicsData, texture.heapSlot)
		deleteImage(graphicsData, &texture)
	}
	delete(buffers.textures)
}

GraphicsData :: struct {
	// Rendering push constants
	contrast:            f32,
	brightness:          f32,
	saturation:          f32,
	exposure:            f32,
	tonemapper:          ToneMapper,
	gamma:               f32,

	// GLFW + IMGUI
	window:              WindowHandle,
	imguiContext:        ^imgui.Context,

	// Vulkan Data
	instance:            vk.Instance,
	debugMessenger:      vk.DebugUtilsMessengerEXT,
	surface:             vk.SurfaceKHR,
	physicalDevice:      vk.PhysicalDevice,
	device:              vk.Device,
	memoryProperties:    vk.PhysicalDeviceMemoryProperties,
	memoryAllocator:     MemoryAllocator,
	staging:             StagingRing,
	heapProperties:      vk.PhysicalDeviceDescriptorHeapPropertiesEXT,
	multiviewProperties: vk.PhysicalDeviceMultiviewProperties,
	shadowColourViews:   []vk.ImageView,
	shadowDepthViews:    []vk.ImageView,
	heapIndices:         HeapIndices,
	heaps:               DescriptorHeaps,

	// Queues
	queueFamilies:       QueueFamilyIndices,
	graphicsQueue:       vk.Queue,
	presentQueue:        vk.Queue,
	computeQueue:        vk.Queue,

	// Swapchain
	swapchain:           Swapchain,

	// Pipelines
	pipelines:           [PipelineIndex]Pipeline,
	pipelineCache:       vk.PipelineCache,

	// Frame Resources
	depthFormat:         vk.Format,
	inFlightFrames:      [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	presentReady:        [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	presentFences:       [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	presentPending:      [MAX_FRAMES_IN_FLIGHT]bool,
	semaphores:          [SemaphoreIndex][MAX_FRAMES_IN_FLIGHT]vk.Semaphore,

	// Commands
	graphicsCommandPool: vk.CommandPool,
	computeCommandPool:  vk.CommandPool,
	commandBuffers:      [CmdBufferIndex][MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

	// Buffer
	uniformBuffers:      [MAX_FRAMES_IN_FLIGHT]Buffer,

	// Util
	hdrRequested:        bool,
	hdrSupported:        bool,
	showLightGizmos:     bool,
	lightGizmoRadius:    f32,
	swapchainDirty:      bool,
	paperWhiteNits:      f32,
	renderSize:          [2]u32,
	currentFrame:        u32,
	reloadBuffers:       bool,
	dirtyCommands:       bit_set[CmdBufferIndex],
}

@(private = "file")
QueueFamilyIndices :: struct {
	graphicsFamily: u32,
	presentFamily:  u32,
	computeFamily:  u32,
}

@(private = "file")
Buffer :: struct {
	buffer:     vk.Buffer,
	allocation: Allocation,
	mapped:     rawptr,
}

@(private = "file")
Image :: struct {
	vkImage:    vk.Image,
	allocation: Allocation,
	view:       vk.ImageView,
	viewInfo:   vk.ImageViewCreateInfo,
	format:     vk.Format,
	sampler:    u32,
	heapSlot:   u32,
}

InitGraphicsInfo :: struct {
	appVersion:        u32,
	windowTitle:       cstring,

	// Shaders
	transformShader:   []byte,
	lightShaders:      [2][]byte,
	sceneShaders:      [2][]byte,
	gizmoShaders:      [2][]byte,
	postProcessShader: []byte,
}


// ===[ Lifecycle ]============================================================

@(require_results)
initGraphics :: proc(initInfo: InitGraphicsInfo) -> (graphicsData: GraphicsData, err: Error) {
	initInfo := initInfo
	using graphicsData

	if !glfw.Init() {
		log(.Fatal, "Failed to initialize GLFW!")
		return graphicsData, .GLFWError
	}

	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	createInstance(&graphicsData, initInfo.appVersion) or_return

	if res := vk.CreateDebugUtilsMessengerEXT(
		instance,
		&VK_DEBUG_MESSENGER_CREATE_INFO,
		nil,
		&debugMessenger,
	); res != .SUCCESS {
		logf(.Error, "Failed to create vulkan debug callback! vkResult: %v", res)
	}

	initWindow(&graphicsData, initInfo.windowTitle) or_return
	pickPhysicalDevice(&graphicsData) or_return
	createLogicalDevice(&graphicsData) or_return

	memoryAllocatorInit(
		&graphicsData.memoryAllocator,
		graphicsData.device,
		graphicsData.physicalDevice,
		memoryProperties,
	)

	graphicsData.hdrRequested = HDR_DEFAULT
	createSwapchain(&graphicsData)
	if !graphicsData.hdrSupported {
		log(.Info, "Surface offers no HDR10 format; HDR is unavailable.")
	} else {
		logf(.Info, "HDR10 available, currently %v.", "on" if graphicsData.swapchain.hdr else "off")
	}
	createCommandBuffers(&graphicsData) or_return
	stagingInit(&graphicsData) or_return
	createDescriptorHeaps(&graphicsData) or_return

	bufferSize := size_of(UniformBuffer)
	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if err := createBuffer(
			&graphicsData,
			bufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&uniformBuffers[index],
		); err != nil {
			log(.Fatal, "Failed to create uniform buffer!")
			return graphicsData, err
		}
	}

	depthFormat = findSupportedDepthFormat(
		&graphicsData,
		{.D16_UNORM, .D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
	)
	if depthFormat == .UNDEFINED {
		log(.Fatal, "Failed to find a supported depth format!")
		return graphicsData, .DepthFormatError
	}

	createSyncObjects(&graphicsData) or_return
	createSamplers(&graphicsData) or_return

	graphicsData.renderSize = RENDER_SIZE

	createPipelineCache(&graphicsData)

	createTransformPipeline(&graphicsData, initInfo.transformShader)

	pipelines[.Light].images = make([]Image, 2)
	pipelines[.Light].images[0].format = .R16G16B16A16_SFLOAT
	pipelines[.Light].images[1].format = depthFormat
	createLightPipeline(&graphicsData, initInfo.lightShaders[:])

	pipelines[.Scene].images = make([]Image, 2)
	pipelines[.Scene].images[0].format = .R16G16B16A16_SFLOAT
	pipelines[.Scene].images[1].format = depthFormat
	createScenePipelineImages(&graphicsData)
	createScenePipeline(&graphicsData, initInfo.sceneShaders[:])
	createGizmoPipeline(&graphicsData, initInfo.gizmoShaders[:])

	pipelines[.PostProcess].images = make([]Image, 2)
	pipelines[.PostProcess].images[0].format = .R16G16B16A16_SFLOAT
	pipelines[.PostProcess].images[1].format = .R16G16B16A16_SFLOAT
	createPostProcessPipelineImages(&graphicsData)
	createPostProcessPipeline(&graphicsData, initInfo.postProcessShader)

	initImgui(&graphicsData)

	nameCoreObjects(&graphicsData)

	currentFrame = 0
	contrast = 1.0
	brightness = 0.0
	saturation = 1.0
	exposure = 0.0
	gamma = 2.2
	paperWhiteNits = PAPER_WHITE_NITS
	showLightGizmos = true
	lightGizmoRadius = 0.1
	applyHDRGrading(&graphicsData)

	return graphicsData, nil
}

cleanupGraphics :: proc(using graphicsData: ^GraphicsData) {
	if vk.DeviceWaitIdle(device) != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	cleanupImgui(graphicsData)

	stagingDestroy(graphicsData)
	cleanupDescriptorHeaps(graphicsData)

	vk.FreeCommandBuffers(
		device,
		computeCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[.Transform][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[.Light][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[.Scene][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[.PostProcess][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[.Imgui][0],
	)

	vk.DestroyCommandPool(device, graphicsCommandPool, nil)
	vk.DestroyCommandPool(device, computeCommandPool, nil)

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroyFence(device, inFlightFrames[index], nil)
		vk.DestroyFence(device, presentFences[index], nil)
		vk.DestroySemaphore(device, presentReady[index], nil)
		for semaphoreIndex in SemaphoreIndex {
			vk.DestroySemaphore(device, semaphores[semaphoreIndex][index], nil)
		}
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		deleteBuffer(graphicsData, &uniformBuffers[index])
	}

	cleanupSwapchain(graphicsData, swapchain)

	savePipelineCache(graphicsData)
	vk.DestroyPipelineCache(device, pipelineCache, nil)

	destroyShadowFaceViews(graphicsData)

	for &pipeline in pipelines {
		cleanupPipeline(graphicsData, &pipeline)

		for &image in pipeline.images {
			deleteImage(graphicsData, &image)
		}
		if len(pipeline.images) > 0 {
			delete(pipeline.images)
		}
	}

	memoryAllocatorReportLeaks(&graphicsData.memoryAllocator)
	memoryAllocatorDestroy(&graphicsData.memoryAllocator)

	vk.DestroyDevice(device, nil)
	vk.DestroySurfaceKHR(instance, surface, nil)

	if debugMessenger != 0 {
		vk.DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
	}

	vk.DestroyInstance(instance, nil)

	glfw.DestroyWindow(window)
	glfw.Terminate()
}

@(require_results)
waitDeviceIdle :: proc(using graphicsData: ^GraphicsData) -> vk.Result {
	return vk.DeviceWaitIdle(device)
}


// ===[ Window and Input ]=====================================================

updateWindow :: proc(using graphicsData: ^GraphicsData) -> (ret: bool) {
	ret = !glfw.WindowShouldClose(window)
	pollingEvents = true
	glfw.PollEvents()
	pollingEvents = false
	return
}

windowSize :: proc(using graphicsData: ^GraphicsData) -> (width: i32, height: i32) {
	return glfw.GetWindowSize(window)
}

setGLFWErrorCallback :: proc(errorCallback: GLFWErrorCallback) {
	glfw.SetErrorCallback(errorCallback)
}

setGLFWKeyCallback :: proc(window: WindowHandle, keyCallback: GLFWKeyCallback) {
	glfw.SetKeyCallback(window, keyCallback)
}

setGLFWMouseButtonCallback :: proc(
	window: WindowHandle,
	mouseButtonCallback: GLFWMouseButtonCallback,
) {
	glfw.SetMouseButtonCallback(window, mouseButtonCallback)
}

setGLFWCursorPosCallback :: proc(window: WindowHandle, cursorPosCallback: GLFWCursorPosCallback) {
	glfw.SetCursorPosCallback(window, cursorPosCallback)
}

setGLFWScrollCallback :: proc(window: WindowHandle, scrollCallback: GLFWScrollCallback) {
	glfw.SetScrollCallback(window, scrollCallback)
}

@(private)
pollingEvents: bool

@(private = "file")
@(require_results)
initWindow :: proc(using graphicsData: ^GraphicsData, windowTitle: cstring) -> WindowError {
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	if window = glfw.CreateWindow(1600, 800, windowTitle, nil, nil); window == nil {
		log(.Fatal, "Failed to create window.")
		return .FailedToCreateWindow
	}

	glfw.SetErrorCallback(glfwErrorCallback)
	glfw.SetKeyCallback(window, keyCallback)
	glfw.SetMouseButtonCallback(window, mouseButtonCallback)
	glfw.SetCursorPosCallback(window, cursorPosCallback)
	glfw.SetScrollCallback(window, scrollCallback)
	glfw.SetWindowRefreshCallback(window, windowRefreshCallback)
	glfw.SetFramebufferSizeCallback(window, framebufferSizeCallback)
	installModalLoopTimer(window)

	if res := glfw.CreateWindowSurface(instance, window, nil, &surface); res != .SUCCESS {
		logf(.Fatal, "Failed to create surface! vkResult: %v", res)
		return .FailedToCreateSurface
	}

	return .None
}


// ===[ Instance and Device ]==================================================

@(private = "file")
@(require_results)
createInstance :: proc(using graphicsData: ^GraphicsData, version: u32) -> InstanceError {
	appInfo: vk.ApplicationInfo = {
		sType              = .APPLICATION_INFO,
		pNext              = nil,
		pApplicationName   = "Valhalla",
		applicationVersion = version,
		pEngineName        = "Asgardian Graphics",
		engineVersion      = VERSION,
		apiVersion         = vk.API_VERSION_1_4,
	}

	glfwExtensions := glfw.GetRequiredInstanceExtensions()
	supportedExtensions := make([dynamic]cstring, allocator = context.temp_allocator)
	reserve(&supportedExtensions, len(glfwExtensions) + len(INSTANCE_EXTENSIONS))

	extensionCount: u32
	vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, nil)
	availableExtensions := make(
		[]vk.ExtensionProperties,
		extensionCount,
		allocator = context.temp_allocator,
	)

	vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, raw_data(availableExtensions))
	glfw_extension_outer_loop: for name in glfwExtensions {
		for &extension in availableExtensions {
			if name == cstring(&extension.extensionName[0]) {
				append(&supportedExtensions, name)
				continue glfw_extension_outer_loop
			}
		}
		logf(.Warning, "Couldn't find extension: %s", name)
	}

	instance_extension_outer_loop: for name in INSTANCE_EXTENSIONS {
		for &extension in availableExtensions {
			if (name == cstring(&extension.extensionName[0])) {
				append(&supportedExtensions, name)
				continue instance_extension_outer_loop
			}
		}
		logf(.Warning, "Couldn't find extension: %s", name)
	}

	supportedLayers := make([dynamic]cstring, allocator = context.temp_allocator)
	reserve(&supportedLayers, len(REQUESTED_LAYERS))

	layerCount: u32
	vk.EnumerateInstanceLayerProperties(&layerCount, nil)

	layers := make([]vk.LayerProperties, layerCount, allocator = context.temp_allocator)
	vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(layers))

	instance_layers_outer_loop: for name in REQUESTED_LAYERS {
		for &layer in layers {
			if name == cstring(&layer.layerName[0]) {
				append(&supportedLayers, name)
				continue instance_layers_outer_loop
			}
		}
		logf(.Warning, "Couldn't find layer: %s", name)
	}

	features := [?]vk.ValidationFeatureEnableEXT{.SYNCHRONIZATION_VALIDATION}
	validationFeatures: vk.ValidationFeaturesEXT = {
		sType                          = .VALIDATION_FEATURES_EXT,
		pNext                          = nil,
		enabledValidationFeatureCount  = u32(len(features)),
		pEnabledValidationFeatures     = &features[0],
		disabledValidationFeatureCount = 0,
		pDisabledValidationFeatures    = nil,
	}

	instanceInfo: vk.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pNext                   = &validationFeatures,
		flags                   = nil,
		pApplicationInfo        = &appInfo,
		enabledLayerCount       = u32(len(supportedLayers)),
		ppEnabledLayerNames     = raw_data(supportedLayers),
		enabledExtensionCount   = u32(len(supportedExtensions)),
		ppEnabledExtensionNames = raw_data(supportedExtensions),
	}

	if res := vk.CreateInstance(&instanceInfo, nil, &instance); res != .SUCCESS {
		logf(.Fatal, "Failed to create vulkan instance! vkResult: %v", res)
		return .FailedToCreateInstance
	}

	vk.load_proc_addresses(instance)
	return .None
}

@(private = "file")
findQueueFamilies :: proc(
	physicalDevice: vk.PhysicalDevice,
	graphicsData: ^GraphicsData,
) -> (
	indices: QueueFamilyIndices,
	err: b32 = false,
) {
	queueFamilyCount: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nil)
	queueFamilies := make([]vk.QueueFamilyProperties, queueFamilyCount)
	defer delete(queueFamilies)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physicalDevice,
		&queueFamilyCount,
		raw_data(queueFamilies),
	)

	foundPresentFamily := false
	foundGraphicsFamily := false
	foundComputeFamily := false
	for queueFamily, index in queueFamilies {
		if .GRAPHICS in queueFamily.queueFlags {
			indices.graphicsFamily = u32(index)
			foundGraphicsFamily = true
		}

		if .COMPUTE in queueFamily.queueFlags {
			indices.computeFamily = u32(index)
			foundComputeFamily = true
		}

		presentSupport: b32
		if vk.GetPhysicalDeviceSurfaceSupportKHR(
			   physicalDevice,
			   (u32)(index),
			   graphicsData.surface,
			   &presentSupport,
		   ); presentSupport {
			indices.presentFamily = u32(index)
			foundPresentFamily = true
		}

		if foundGraphicsFamily && foundPresentFamily && foundComputeFamily {
			return
		}
	}
	return indices, true
}

@(private = "file")
DeviceFeatures :: struct {
	features:           vk.PhysicalDeviceFeatures2,
	vulkan11:           vk.PhysicalDeviceVulkan11Features,
	vulkan12:           vk.PhysicalDeviceVulkan12Features,
	vulkan13:           vk.PhysicalDeviceVulkan13Features,
	vulkan14:           vk.PhysicalDeviceVulkan14Features,
	computeDerivatives: vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR,
	descriptorHeap:     vk.PhysicalDeviceDescriptorHeapFeaturesEXT,
	untypedPointers:    vk.PhysicalDeviceShaderUntypedPointersFeaturesKHR,
	memoryPriority:     vk.PhysicalDeviceMemoryPriorityFeaturesEXT,
	pageableMemory:     vk.PhysicalDevicePageableDeviceLocalMemoryFeaturesEXT,
	swapchainMaint1:    vk.PhysicalDeviceSwapchainMaintenance1FeaturesEXT,
}

@(private = "file")
buildDeviceFeatures :: proc(chain: ^DeviceFeatures, request: bool) {
	chain^ = {
		features           = {sType = .PHYSICAL_DEVICE_FEATURES_2, pNext = &chain.vulkan11},
		vulkan11           = {
			sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
			pNext = &chain.vulkan12,
		},
		vulkan12           = {
			sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
			pNext = &chain.vulkan13,
		},
		vulkan13           = {
			sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
			pNext = &chain.vulkan14,
		},
		vulkan14           = {
			sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
			pNext = &chain.computeDerivatives,
		},
		computeDerivatives = {
			sType = .PHYSICAL_DEVICE_COMPUTE_SHADER_DERIVATIVES_FEATURES_KHR,
			pNext = &chain.descriptorHeap,
		},
		descriptorHeap     = {
			sType = .PHYSICAL_DEVICE_DESCRIPTOR_HEAP_FEATURES_EXT,
			pNext = &chain.untypedPointers,
		},
		untypedPointers    = {
			sType = .PHYSICAL_DEVICE_SHADER_UNTYPED_POINTERS_FEATURES_KHR,
			pNext = &chain.memoryPriority,
		},
		memoryPriority     = {
			sType = .PHYSICAL_DEVICE_MEMORY_PRIORITY_FEATURES_EXT,
			pNext = &chain.pageableMemory,
		},
		pageableMemory     = {
			sType = .PHYSICAL_DEVICE_PAGEABLE_DEVICE_LOCAL_MEMORY_FEATURES_EXT,
			pNext = &chain.swapchainMaint1,
		},
		swapchainMaint1    = {
			sType = .PHYSICAL_DEVICE_SWAPCHAIN_MAINTENANCE_1_FEATURES_EXT,
			pNext = nil,
		},
	}

	if !request {
		return
	}

	chain.features.features = {imageCubeArray = true, samplerAnisotropy = true}
	chain.vulkan11.multiview = true
	chain.vulkan11.shaderDrawParameters = true
	chain.vulkan12.timelineSemaphore = true
	chain.vulkan12.bufferDeviceAddress = true
	chain.vulkan13.synchronization2 = true
	chain.vulkan13.dynamicRendering = true
	chain.vulkan14.maintenance5 = true
	chain.vulkan14.hostImageCopy = true
	chain.computeDerivatives.computeDerivativeGroupQuads = true
	chain.descriptorHeap.descriptorHeap = true
	chain.untypedPointers.shaderUntypedPointers = true
	chain.memoryPriority.memoryPriority = true
	chain.pageableMemory.pageableDeviceLocalMemory = true
	chain.swapchainMaint1.swapchainMaintenance1 = true
}

@(private = "file")
@(require_results)
supportsRequestedFeatures :: proc(physicalDevice: vk.PhysicalDevice) -> bool {
	missing :: proc(request, support: rawptr, size: int) -> bool {
		OFFSET :: offset_of(vk.PhysicalDeviceVulkan11Features, storageBuffer16BitAccess)
		req := ([^]b32)(uintptr(request) + OFFSET)
		sup := ([^]b32)(uintptr(support) + OFFSET)
		for i in 0 ..< (size - int(OFFSET)) / size_of(b32) {
			if req[i] && !sup[i] {
				return true
			}
		}
		return false
	}

	request, support: DeviceFeatures
	buildDeviceFeatures(&request, true)
	buildDeviceFeatures(&support, false)
	vk.GetPhysicalDeviceFeatures2(physicalDevice, &support.features)

	if missing(&request.features, &support.features, size_of(vk.PhysicalDeviceFeatures2)) ||
	   missing(&request.vulkan11, &support.vulkan11, size_of(vk.PhysicalDeviceVulkan11Features)) ||
	   missing(&request.vulkan12, &support.vulkan12, size_of(vk.PhysicalDeviceVulkan12Features)) ||
	   missing(&request.vulkan13, &support.vulkan13, size_of(vk.PhysicalDeviceVulkan13Features)) ||
	   missing(&request.vulkan14, &support.vulkan14, size_of(vk.PhysicalDeviceVulkan14Features)) ||
	   missing(
		   &request.computeDerivatives,
		   &support.computeDerivatives,
		   size_of(vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR),
	   ) ||
	   missing(
		   &request.descriptorHeap,
		   &support.descriptorHeap,
		   size_of(vk.PhysicalDeviceDescriptorHeapFeaturesEXT),
	   ) ||
	   missing(
		   &request.memoryPriority,
		   &support.memoryPriority,
		   size_of(vk.PhysicalDeviceMemoryPriorityFeaturesEXT),
	   ) ||
	   missing(
		   &request.pageableMemory,
		   &support.pageableMemory,
		   size_of(vk.PhysicalDevicePageableDeviceLocalMemoryFeaturesEXT),
	   ) ||
	   missing(
		   &request.swapchainMaint1,
		   &support.swapchainMaint1,
		   size_of(vk.PhysicalDeviceSwapchainMaintenance1FeaturesEXT),
	   ) ||
	   missing(
		   &request.untypedPointers,
		   &support.untypedPointers,
		   size_of(vk.PhysicalDeviceShaderUntypedPointersFeaturesKHR),
	   ) {
		return false
	}
	return true
}

@(private = "file")
@(require_results)
pickPhysicalDevice :: proc(using graphicsData: ^GraphicsData) -> DeviceError {
	scorePhysicalDevice :: proc(
		physicalDevice: vk.PhysicalDevice,
		graphicsData: ^GraphicsData,
	) -> (
		score: u32 = 0,
	) {
		deviceProperties: vk.PhysicalDeviceProperties2 = {
			sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		}

		vk.GetPhysicalDeviceProperties2(physicalDevice, &deviceProperties)

		indices, err := findQueueFamilies(physicalDevice, graphicsData)
		if err ||
		   !supportsRequestedFeatures(physicalDevice) ||
		   !checkDeviceExtensionSupport(physicalDevice) ||
		   !swapchainAdequate(physicalDevice, graphicsData) {
			return
		}

		if deviceProperties.properties.deviceType == .DISCRETE_GPU {
			score += 1000
		}

		if indices.graphicsFamily == indices.presentFamily {
			score += 100
		}

		if indices.graphicsFamily == indices.computeFamily {
			score += 100
		}

		score += deviceProperties.properties.limits.maxImageDimension2D
		return
	}

	checkDeviceExtensionSupport :: proc(physicalDevice: vk.PhysicalDevice) -> b32 {
		extensionCount: u32
		vk.EnumerateDeviceExtensionProperties(physicalDevice, nil, &extensionCount, nil)

		availableExtensions := make(
			[]vk.ExtensionProperties,
			extensionCount,
			context.temp_allocator,
		)
		vk.EnumerateDeviceExtensionProperties(
			physicalDevice,
			nil,
			&extensionCount,
			raw_data(availableExtensions),
		)

		outer_loop: for name in DEVICE_EXTENSIONS {
			for &extension in availableExtensions {
				if name == cstring(&extension.extensionName[0]) {
					continue outer_loop
				}
			}
			return false
		}
		return true
	}

	swapchainAdequate :: proc(
		physicalDevice: vk.PhysicalDevice,
		graphicsData: ^GraphicsData,
	) -> b32 {
		support := querySwapchainSupport(physicalDevice, graphicsData)
		return len(support.formats) != 0 && len(support.modes) != 0
	}

	deviceCount: u32
	vk.EnumeratePhysicalDevices(instance, &deviceCount, nil)

	if deviceCount == 0 {
		log(.Fatal, "No devices with Vulkan support!")
		return .FailedToFindSuitableDevice
	}

	physicalDevices := make([]vk.PhysicalDevice, deviceCount, allocator = context.temp_allocator)
	vk.EnumeratePhysicalDevices(instance, &deviceCount, raw_data(physicalDevices))

	physicalDeviceMap := make(map[vk.PhysicalDevice]u32, allocator = context.temp_allocator)
	for &physicalDevice in physicalDevices {
		physicalDeviceMap[physicalDevice] = scorePhysicalDevice(physicalDevice, graphicsData)
	}

	bestScore: u32
	for device, score in physicalDeviceMap {
		if (score > bestScore) {
			physicalDevice = (vk.PhysicalDevice)(device)
			bestScore = score
		}
	}

	if physicalDevice == nil {
		log(.Fatal, "No suitable physical device found!")
		return .FailedToFindSuitableDevice
	}

	properties: vk.PhysicalDeviceMemoryProperties2 = {
		sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2,
		pNext = nil,
	}
	vk.GetPhysicalDeviceMemoryProperties2(physicalDevice, &properties)
	memoryProperties = properties.memoryProperties

	multiviewProperties = {
		sType = .PHYSICAL_DEVICE_MULTIVIEW_PROPERTIES,
		pNext = nil,
	}
	heapProperties = {
		sType = .PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT,
		pNext = &multiviewProperties,
	}
	deviceProperties: vk.PhysicalDeviceProperties2 = {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &heapProperties,
	}
	vk.GetPhysicalDeviceProperties2(physicalDevice, &deviceProperties)

	return .None
}

@(private = "file")
@(require_results)
createLogicalDevice :: proc(using graphicsData: ^GraphicsData) -> DeviceError {
	queueFamilies, _ = findQueueFamilies(physicalDevice, graphicsData)

	queuePriority: f32 = 1.0
	queueCreateInfos := make([dynamic]vk.DeviceQueueCreateInfo, allocator = context.temp_allocator)
	reserve(&queueCreateInfos, 3)

	queueCreateInfo: vk.DeviceQueueCreateInfo = {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		pNext            = nil,
		flags            = {},
		queueFamilyIndex = queueFamilies.graphicsFamily,
		queueCount       = 1,
		pQueuePriorities = &queuePriority,
	}
	append(&queueCreateInfos, queueCreateInfo)

	if queueFamilies.graphicsFamily != queueFamilies.presentFamily {
		queueCreateInfo = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			pNext            = nil,
			flags            = {},
			queueFamilyIndex = queueFamilies.presentFamily,
			queueCount       = 1,
			pQueuePriorities = &queuePriority,
		}
		append(&queueCreateInfos, queueCreateInfo)
	}

	if queueFamilies.graphicsFamily != queueFamilies.computeFamily &&
	   queueFamilies.presentFamily != queueFamilies.computeFamily {
		queueCreateInfo = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			pNext            = nil,
			flags            = {},
			queueFamilyIndex = queueFamilies.computeFamily,
			queueCount       = 1,
			pQueuePriorities = &queuePriority,
		}
		append(&queueCreateInfos, queueCreateInfo)
	}

	features: DeviceFeatures
	buildDeviceFeatures(&features, true)

	requiredDeviceExtensions := DEVICE_EXTENSIONS
	createInfo: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features.features,
		flags                   = {},
		queueCreateInfoCount    = u32(len(queueCreateInfos)),
		pQueueCreateInfos       = raw_data(queueCreateInfos),
		enabledLayerCount       = 0,
		ppEnabledLayerNames     = nil,
		enabledExtensionCount   = u32(len(requiredDeviceExtensions)),
		ppEnabledExtensionNames = raw_data(requiredDeviceExtensions),
		pEnabledFeatures        = nil,
	}

	if res := vk.CreateDevice(physicalDevice, &createInfo, nil, &device); res != .SUCCESS {
		log(.Fatal, "Failed to create logical device! vkResult: %v", res)
		return .FailedToCreateDevice
	}

	vk.load_proc_addresses(device)

	vk.GetDeviceQueue(device, queueFamilies.graphicsFamily, 0, &graphicsQueue)
	vk.GetDeviceQueue(device, queueFamilies.presentFamily, 0, &presentQueue)
	vk.GetDeviceQueue(device, queueFamilies.computeFamily, 0, &computeQueue)

	return .None
}


// ===[ Swapchain ]============================================================

@(private = "file")
Swapchain :: struct {
	handle:    vk.SwapchainKHR,
	transform: vk.SurfaceTransformFlagsKHR,
	format:    vk.SurfaceFormatKHR,
	mode:      vk.PresentModeKHR,
	extent:    vk.Extent2D,
	images:    []vk.Image,
	views:     []vk.ImageView,
	hdr:       bool,
}

@(private = "file")
SwapchainSupportDetails :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	modes:        []vk.PresentModeKHR,
}

@(private = "file")
querySwapchainSupport :: proc(
	physicalDevice: vk.PhysicalDevice,
	graphicsData: ^GraphicsData,
) -> (
	swapchainSupport: SwapchainSupportDetails,
) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		physicalDevice,
		graphicsData.surface,
		&swapchainSupport.capabilities,
	)

	formatCount: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, graphicsData.surface, &formatCount, nil)
	if formatCount != 0 {
		swapchainSupport.formats = make(
			[]vk.SurfaceFormatKHR,
			formatCount,
			allocator = context.temp_allocator,
		)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			physicalDevice,
			graphicsData.surface,
			&formatCount,
			raw_data(swapchainSupport.formats),
		)
	}

	modeCount: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physicalDevice,
		graphicsData.surface,
		&modeCount,
		nil,
	)
	if modeCount != 0 {
		swapchainSupport.modes = make(
			[]vk.PresentModeKHR,
			modeCount,
			allocator = context.temp_allocator,
		)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			physicalDevice,
			graphicsData.surface,
			&modeCount,
			raw_data(swapchainSupport.modes),
		)
	}
	return
}

getSwapcahainAspectRatio :: proc(using graphicsData: ^GraphicsData) -> f32 {
	return f32(swapchain.extent.width) / f32(swapchain.extent.height)
}

getRenderAspectRatio :: proc(using graphicsData: ^GraphicsData) -> f32 {
	return f32(renderSize.x) / f32(renderSize.y)
}

// The render target has its own resolution and aspect, so fitting it to the swapchain leaves
// black bars on one axis whenever the two aspects differ.
@(private = "file")
@(require_results)
letterboxRect :: proc(
	renderSize: [2]u32,
	target: vk.Extent2D,
) -> (
	offset: vk.Offset2D,
	extent: vk.Extent2D,
) {
	scale := min(
		f32(target.width) / f32(renderSize.x),
		f32(target.height) / f32(renderSize.y),
	)
	extent = {
		width  = max(u32(f32(renderSize.x) * scale), 1),
		height = max(u32(f32(renderSize.y) * scale), 1),
	}
	offset = {
		x = i32((target.width - extent.width) / 2),
		y = i32((target.height - extent.height) / 2),
	}
	return
}

@(private = "file")
@(require_results)
isHDRSurfaceFormat :: proc(format: vk.SurfaceFormatKHR) -> bool {
	return(
		format.colorSpace == .HDR10_ST2084_EXT &&
		(format.format == .A2B10G10R10_UNORM_PACK32 ||
				format.format == .A2R10G10B10_UNORM_PACK32) 	)
}

@(private = "file")
createSwapchain :: proc(using graphicsData: ^GraphicsData, oldSwapchain: vk.SwapchainKHR = 0) {
	chooseFormat :: proc(
		formats: []vk.SurfaceFormatKHR,
		wantHDR: bool,
	) -> (
		fmt: vk.SurfaceFormatKHR,
		hdr: bool,
	) {
		fmt = formats[0]
		if wantHDR {
			for format in formats {
				if isHDRSurfaceFormat(format) {
					return format, true
				}
			}
		}

		for format in formats {
			if (format.format == .B8G8R8A8_UNORM || format.format == .R8G8B8A8_UNORM) &&
			   format.colorSpace == .SRGB_NONLINEAR {
				return format, false
			}
		}
		return fmt, false
	}

	choosePresentMode :: proc(modes: []vk.PresentModeKHR) -> (mode: vk.PresentModeKHR) {
		for mode in modes {
			if mode == .MAILBOX {
				return mode
			}
		}
		return .FIFO
	}

	chooseExtent :: proc(
		using graphicsData: ^GraphicsData,
		capabilities: vk.SurfaceCapabilitiesKHR,
	) -> (
		extent: vk.Extent2D,
	) {
		if capabilities.currentExtent.width != max(u32) {
			return capabilities.currentExtent
		}
		width, height := glfw.GetFramebufferSize(window)
		extent.width = clamp(
			u32(width),
			capabilities.minImageExtent.width,
			capabilities.maxImageExtent.width,
		)
		extent.height = clamp(
			u32(height),
			capabilities.minImageExtent.height,
			capabilities.maxImageExtent.height,
		)
		return
	}

	swapchainSupport := querySwapchainSupport(graphicsData.physicalDevice, graphicsData)

	max := swapchainSupport.capabilities.maxImageCount
	min := swapchainSupport.capabilities.minImageCount
	swapchainImageCount := max if max == 1 else (2 if 2 > min else min)

	hdrSupported = false
	for format in swapchainSupport.formats {
		if isHDRSurfaceFormat(format) {
			hdrSupported = true
			break
		}
	}

	surfaceFormat, hdrActive := chooseFormat(swapchainSupport.formats, hdrRequested && hdrSupported)
	swapchain = {
		transform = swapchainSupport.capabilities.currentTransform,
		format    = surfaceFormat,
		mode      = choosePresentMode(swapchainSupport.modes),
		extent    = chooseExtent(graphicsData, swapchainSupport.capabilities),
		hdr       = hdrActive,
	}

	queueFamiliesArray := make([dynamic]u32, context.temp_allocator)
	append(&queueFamiliesArray, queueFamilies.graphicsFamily)
	if queueFamilies.graphicsFamily != queueFamilies.presentFamily {
		append(&queueFamiliesArray, queueFamilies.presentFamily)
	}

	if queueFamilies.graphicsFamily != queueFamilies.computeFamily &&
	   queueFamilies.presentFamily != queueFamilies.computeFamily {
		append(&queueFamiliesArray, queueFamilies.computeFamily)
	}

	createInfo: vk.SwapchainCreateInfoKHR = {
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		pNext                 = nil,
		flags                 = {},
		surface               = graphicsData.surface,
		minImageCount         = swapchainImageCount,
		imageFormat           = swapchain.format.format,
		imageColorSpace       = swapchain.format.colorSpace,
		imageExtent           = swapchain.extent,
		imageArrayLayers      = 1,
		imageUsage            = {.TRANSFER_DST, .COLOR_ATTACHMENT},
		imageSharingMode      = len(queueFamiliesArray) == 1 ? .EXCLUSIVE : .CONCURRENT,
		queueFamilyIndexCount = u32(len(queueFamiliesArray)),
		pQueueFamilyIndices   = raw_data(queueFamiliesArray),
		preTransform          = swapchain.transform,
		compositeAlpha        = {.OPAQUE},
		presentMode           = swapchain.mode,
		clipped               = true,
		oldSwapchain          = oldSwapchain,
	}

	if res := vk.CreateSwapchainKHR(device, &createInfo, nil, &swapchain.handle); res != .SUCCESS {
		log(.Fatal, "Failed to create swapchain! vkResult: %v", res)
	}

	imageCount: u32
	vk.GetSwapchainImagesKHR(device, swapchain.handle, &imageCount, nil)

	swapchain.images = make([]vk.Image, imageCount)
	vk.GetSwapchainImagesKHR(device, swapchain.handle, &imageCount, raw_data(swapchain.images))

	swapchain.views = make([]vk.ImageView, imageCount)
	for index in 0 ..< imageCount {
		err: ImageError
		swapchain.views[index], _, err = createImageView(
			graphicsData,
			swapchain.images[index],
			.D2,
			swapchain.format.format,
			{.COLOR},
			1,
		)
		if err != .None {
			log(.Fatal, "Failed to create swapchain image view! vkResult: %v", err)
		}
	}
}

@(private = "file")
cleanupSwapchain :: proc(graphicsData: ^GraphicsData, swapchain: Swapchain) {
	for view in swapchain.views {
		vk.DestroyImageView(graphicsData.device, view, nil)
	}

	delete(swapchain.images)
	delete(swapchain.views)

	vk.DestroySwapchainKHR(graphicsData.device, swapchain.handle, nil)
}

@(private = "file")
applyHDRGrading :: proc(using graphicsData: ^GraphicsData) {
	tonemapper = .None if swapchain.hdr else .NarkowiczACES
}

setHDREnabled :: proc(using graphicsData: ^GraphicsData, enabled: bool) -> bool {
	if enabled && !hdrSupported {
		return false
	}
	if hdrRequested != enabled {
		hdrRequested = enabled
		swapchainDirty = true
	}
	return true
}

hdrEnabled :: proc(using graphicsData: ^GraphicsData) -> bool {
	return hdrRequested
}

hdrActive :: proc(using graphicsData: ^GraphicsData) -> bool {
	return swapchain.hdr
}

hdrAvailable :: proc(using graphicsData: ^GraphicsData) -> bool {
	return hdrSupported
}

@(private = "file")
waitForPresent :: proc(using graphicsData: ^GraphicsData, frame: u32) {
	if !presentPending[frame] {
		return
	}
	vk.WaitForFences(device, 1, &presentFences[frame], true, max(u64))
	presentPending[frame] = false
}

@(private = "file")
recreateSwapchain :: proc(using graphicsData: ^GraphicsData) {
	width, height := glfw.GetFramebufferSize(window)
	for width == 0 && height == 0 {
		glfw.WaitEvents()
		width, height = glfw.GetFramebufferSize(window)
	}

	vk.WaitForFences(device, len(inFlightFrames), &inFlightFrames[0], true, max(u64))
	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		waitForPresent(graphicsData, frame)
	}
	vk.QueueWaitIdle(presentQueue)

	oldSwapchain := swapchain
	createSwapchain(graphicsData, oldSwapchain.handle)
	cleanupSwapchain(graphicsData, oldSwapchain)

	for &image in pipelines[.PostProcess].images {
		deleteImage(graphicsData, &image)
	}
	createPostProcessPipelineImages(graphicsData)

	updateComputeDescriptorSets(graphicsData)

	markCommandsDirty(graphicsData, {.PostProcess})
}


// ===[ Device Memory ]========================================================

@(private = "file")
BLOCK_SIZE: vk.DeviceSize : 64 * 1024 * 1024

@(private = "file")
DEDICATED_THRESHOLD: vk.DeviceSize : BLOCK_SIZE / 4

@(private = "file")
MEMORY_PRIORITY_DEDICATED :: f32(1.0)

@(private = "file")
MEMORY_PRIORITY_BLOCK :: f32(0.5)

@(private = "file")
MemoryUsage :: enum {
	Linear,
	Optimal,
}

@(private = "file")
MemoryRange :: struct {
	offset: vk.DeviceSize,
	size:   vk.DeviceSize,
}

@(private = "file")
MemoryBlock :: struct {
	memory:          vk.DeviceMemory,
	size:            vk.DeviceSize,
	memoryTypeIndex: u32,
	usage:           MemoryUsage,
	mapped:          rawptr,
	free:            [dynamic]MemoryRange,
}

@(private = "file")
Allocation :: struct {
	memory: vk.DeviceMemory,
	offset: vk.DeviceSize,
	size:   vk.DeviceSize,
	mapped: rawptr,
	block:  ^MemoryBlock,
}

@(private = "file")
MemoryAllocator :: struct {
	device:         vk.Device,
	physicalDevice: vk.PhysicalDevice,
	properties:     vk.PhysicalDeviceMemoryProperties,
	blocks:         [dynamic]^MemoryBlock,
	dedicatedCount: u32,
	suballocCount:  u32,
	liveDedicated:  u32,
	liveSuballocs:  u32,
}

@(private = "file")
memoryAllocatorInit :: proc(
	allocator: ^MemoryAllocator,
	device: vk.Device,
	physicalDevice: vk.PhysicalDevice,
	properties: vk.PhysicalDeviceMemoryProperties,
) {
	allocator.device = device
	allocator.physicalDevice = physicalDevice
	allocator.properties = properties
	allocator.blocks = make([dynamic]^MemoryBlock)
}

@(private = "file")
@(require_results)
memoryHeapBudget :: proc(
	allocator: ^MemoryAllocator,
	heapIndex: u32,
) -> (
	budget, usage: vk.DeviceSize,
) {
	budgetProperties: vk.PhysicalDeviceMemoryBudgetPropertiesEXT = {
		sType = .PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT,
		pNext = nil,
	}
	properties: vk.PhysicalDeviceMemoryProperties2 = {
		sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2,
		pNext = &budgetProperties,
	}
	vk.GetPhysicalDeviceMemoryProperties2(allocator.physicalDevice, &properties)
	return budgetProperties.heapBudget[heapIndex], budgetProperties.heapUsage[heapIndex]
}

@(private = "file")
@(require_results)
memoryWithinBudget :: proc(
	allocator: ^MemoryAllocator,
	memoryTypeIndex: u32,
	size: vk.DeviceSize,
) -> bool {
	heapIndex := allocator.properties.memoryTypes[memoryTypeIndex].heapIndex
	budget, usage := memoryHeapBudget(allocator, heapIndex)
	if budget == 0 {
		return true
	}
	return usage + size <= budget
}

@(private = "file")
memoryAllocatorDestroy :: proc(allocator: ^MemoryAllocator) {
	for block in allocator.blocks {
		if block.mapped != nil {
			unmapInfo: vk.MemoryUnmapInfo = {
				sType  = .MEMORY_UNMAP_INFO,
				pNext  = nil,
				flags  = {},
				memory = block.memory,
			}
			vk.UnmapMemory2(allocator.device, &unmapInfo)
		}
		vk.FreeMemory(allocator.device, block.memory, nil)
		delete(block.free)
		free(block)
	}
	delete(allocator.blocks)
	allocator.blocks = nil
}

@(private = "file")
memoryAllocatorReportLeaks :: proc(allocator: ^MemoryAllocator) {
	logf(
		.Info,
		"Memory live: %v blocks + %v dedicated, serving %v suballocations.",
		len(allocator.blocks),
		allocator.liveDedicated,
		allocator.liveSuballocs,
	)
	logf(
		.Info,
		"Memory lifetime: %v vkAllocateMemory calls, %v suballocations.",
		u32(len(allocator.blocks)) + allocator.dedicatedCount,
		allocator.suballocCount,
	)

	for block, index in allocator.blocks {
		used := block.size
		for range in block.free {
			used -= range.size
		}
		if used != 0 {
			logf(
				.Warning,
				"Memory block %v (type %v) still has %v bytes allocated.",
				index,
				block.memoryTypeIndex,
				used,
			)
		}
	}
}

@(private = "file")
@(require_results)
memoryFindType :: proc(
	allocator: ^MemoryAllocator,
	typeFilter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	index: u32,
	ok: bool,
) {
	for i in 0 ..< allocator.properties.memoryTypeCount {
		if typeFilter & (1 << i) != 0 &&
		   (allocator.properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i, true
		}
	}
	return 0, false
}

@(private = "file")
@(require_results)
memoryAllocate :: proc(
	allocator: ^MemoryAllocator,
	requirements: vk.MemoryRequirements,
	properties: vk.MemoryPropertyFlags,
	usage: MemoryUsage,
	dedicatedInfo: ^vk.MemoryDedicatedAllocateInfo = nil,
) -> (
	allocation: Allocation,
	err: MemoryError,
) {
	memoryTypeIndex, found := memoryFindType(allocator, requirements.memoryTypeBits, properties)
	if !found {
		log(.Error, "Failed to find a suitable memory type!")
		return {}, .NoSuitableMemoryType
	}

	hostVisible := .HOST_VISIBLE in allocator.properties.memoryTypes[memoryTypeIndex].propertyFlags

	if dedicatedInfo != nil || requirements.size >= DEDICATED_THRESHOLD {
		if !memoryWithinBudget(allocator, memoryTypeIndex, requirements.size) {
			logf(
				.Error,
				"Heap for memory type %v cannot fit a %v byte dedicated allocation.",
				memoryTypeIndex,
				requirements.size,
			)
			return {}, .OutOfBudget
		}
		memory, mapped := memoryAllocateRaw(
			allocator,
			requirements.size,
			memoryTypeIndex,
			hostVisible,
			dedicatedInfo,
			MEMORY_PRIORITY_DEDICATED,
		) or_return
		allocator.dedicatedCount += 1
		allocator.liveDedicated += 1
		return {memory = memory, offset = 0, size = requirements.size, mapped = mapped}, .None
	}

	for block in allocator.blocks {
		if block.memoryTypeIndex != memoryTypeIndex || block.usage != usage {
			continue
		}
		if offset, ok := blockCarve(block, requirements.size, requirements.alignment); ok {
			allocator.suballocCount += 1
			allocator.liveSuballocs += 1
			return makeAllocation(block, offset, requirements.size), .None
		}
	}

	block := memoryAddBlock(
		allocator,
		memoryTypeIndex,
		usage,
		hostVisible,
		requirements.size + requirements.alignment,
	) or_return
	offset, ok := blockCarve(block, requirements.size, requirements.alignment)
	if !ok {
		log(.Error, "Allocation did not fit in a fresh memory block!")
		return {}, .FailedToAllocate
	}
	allocator.suballocCount += 1
	allocator.liveSuballocs += 1
	return makeAllocation(block, offset, requirements.size), .None
}

@(private = "file")
memoryFree :: proc(allocator: ^MemoryAllocator, allocation: ^Allocation) {
	if allocation.memory == 0 {
		return
	}

	if allocation.block == nil {
		if allocation.mapped != nil {
			unmapInfo: vk.MemoryUnmapInfo = {
				sType  = .MEMORY_UNMAP_INFO,
				pNext  = nil,
				flags  = {},
				memory = allocation.memory,
			}
			vk.UnmapMemory2(allocator.device, &unmapInfo)
		}
		vk.FreeMemory(allocator.device, allocation.memory, nil)
		allocator.liveDedicated -= 1
	} else {
		blockRelease(allocation.block, allocation.offset, allocation.size)
		allocator.liveSuballocs -= 1
	}

	allocation^ = {}
}

@(private = "file")
makeAllocation :: proc(
	block: ^MemoryBlock,
	offset, size: vk.DeviceSize,
) -> (
	allocation: Allocation,
) {
	allocation = {
		memory = block.memory,
		offset = offset,
		size   = size,
		block  = block,
	}
	if block.mapped != nil {
		allocation.mapped = rawptr(uintptr(block.mapped) + uintptr(offset))
	}
	return
}

@(private = "file")
@(require_results)
memoryAllocateRaw :: proc(
	allocator: ^MemoryAllocator,
	size: vk.DeviceSize,
	memoryTypeIndex: u32,
	hostVisible: bool,
	dedicatedInfo: ^vk.MemoryDedicatedAllocateInfo,
	priority: f32,
) -> (
	memory: vk.DeviceMemory,
	mapped: rawptr,
	err: MemoryError,
) {
	priorityInfo: vk.MemoryPriorityAllocateInfoEXT = {
		sType    = .MEMORY_PRIORITY_ALLOCATE_INFO_EXT,
		pNext    = dedicatedInfo,
		priority = priority,
	}

	flagsInfo: vk.MemoryAllocateFlagsInfo = {
		sType = .MEMORY_ALLOCATE_FLAGS_INFO,
		pNext = &priorityInfo,
		flags = {.DEVICE_ADDRESS},
		deviceMask = 0,
	}

	allocInfo: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = &flagsInfo,
		allocationSize  = size,
		memoryTypeIndex = memoryTypeIndex,
	}
	if res := vk.AllocateMemory(allocator.device, &allocInfo, nil, &memory); res != .SUCCESS {
		logf(.Error, "Failed to allocate device memory! vkResult: %v", res)
		return 0, nil, .FailedToAllocate
	}

	if hostVisible {
		mapInfo: vk.MemoryMapInfo = {
			sType  = .MEMORY_MAP_INFO,
			pNext  = nil,
			flags  = {},
			memory = memory,
			offset = 0,
			size   = size,
		}
		if res := vk.MapMemory2(allocator.device, &mapInfo, &mapped); res != .SUCCESS {
			logf(.Error, "Failed to map device memory! vkResult: %v", res)
			vk.FreeMemory(allocator.device, memory, nil)
			return 0, nil, .FailedToMap
		}
	}
	return memory, mapped, .None
}

@(private = "file")
@(require_results)
memoryAddBlock :: proc(
	allocator: ^MemoryAllocator,
	memoryTypeIndex: u32,
	usage: MemoryUsage,
	hostVisible: bool,
	minimumSize: vk.DeviceSize,
) -> (
	block: ^MemoryBlock,
	err: MemoryError,
) {
	blockSize := BLOCK_SIZE
	for !memoryWithinBudget(allocator, memoryTypeIndex, blockSize) {
		if blockSize <= minimumSize {
			logf(
				.Error,
				"Heap for memory type %v is out of budget (needed %v bytes).",
				memoryTypeIndex,
				minimumSize,
			)
			return nil, .OutOfBudget
		}
		blockSize /= 2
		if blockSize < minimumSize {
			blockSize = minimumSize
		}
	}

	memory, mapped := memoryAllocateRaw(
		allocator,
		blockSize,
		memoryTypeIndex,
		hostVisible,
		nil,
		MEMORY_PRIORITY_BLOCK,
	) or_return

	block = new(MemoryBlock)
	block^ = {
		memory          = memory,
		size            = blockSize,
		memoryTypeIndex = memoryTypeIndex,
		usage           = usage,
		mapped          = mapped,
		free            = make([dynamic]MemoryRange),
	}
	append(&block.free, MemoryRange{offset = 0, size = blockSize})
	append(&allocator.blocks, block)

	logf(
		.Info,
		"Allocated a %v MiB %v memory block (type %v).",
		blockSize / (1024 * 1024),
		usage,
		memoryTypeIndex,
	)
	return block, .None
}

@(private = "file")
memoryAlignUp :: proc(value, alignment: vk.DeviceSize) -> vk.DeviceSize {
	if alignment == 0 {
		return value
	}
	return (value + alignment - 1) & ~(alignment - 1)
}

@(private = "file")
blockCarve :: proc(
	block: ^MemoryBlock,
	size, alignment: vk.DeviceSize,
) -> (
	offset: vk.DeviceSize,
	ok: bool,
) {
	for &range, index in block.free {
		aligned := memoryAlignUp(range.offset, alignment)
		padding := aligned - range.offset
		if range.size < padding + size {
			continue
		}

		trailing := range.size - padding - size
		switch {
		case padding == 0 && trailing == 0:
			ordered_remove(&block.free, index)
		case padding == 0:
			range.offset = aligned + size
			range.size = trailing
		case trailing == 0:
			range.size = padding
		case:
			range.size = padding
			inject_at(&block.free, index + 1, MemoryRange{aligned + size, trailing})
		}
		return aligned, true
	}
	return 0, false
}

@(private = "file")
blockRelease :: proc(block: ^MemoryBlock, offset, size: vk.DeviceSize) {
	index := 0
	for index < len(block.free) && block.free[index].offset < offset {
		index += 1
	}
	inject_at(&block.free, index, MemoryRange{offset, size})

	if index + 1 < len(block.free) &&
	   block.free[index].offset + block.free[index].size == block.free[index + 1].offset {
		block.free[index].size += block.free[index + 1].size
		ordered_remove(&block.free, index + 1)
	}

	if index > 0 &&
	   block.free[index - 1].offset + block.free[index - 1].size == block.free[index].offset {
		block.free[index - 1].size += block.free[index].size
		ordered_remove(&block.free, index)
	}
}


// ===[ Staging Ring ]=========================================================

@(private = "file")
STAGING_SIZE: vk.DeviceSize : 64 * 1024 * 1024

@(private = "file")
StagingBatch :: struct {
	head:  u64,
	value: u64,
}

@(private = "file")
StagingRing :: struct {
	buffer:        vk.Buffer,
	allocation:    Allocation,
	mapped:        rawptr,

	size:          vk.DeviceSize,
	head:          u64,
	tail:          u64,

	timeline:      vk.Semaphore,
	submitted:     u64,
	pending:       [dynamic]StagingBatch,

	commandBuffer: vk.CommandBuffer,
	recording:     bool,

	oversized:     [dynamic]Buffer,
}

@(private = "file")
@(require_results)
stagingInit :: proc(graphicsData: ^GraphicsData) -> StagingError {
	ring := &graphicsData.staging
	ring.size = STAGING_SIZE
	ring.pending = make([dynamic]StagingBatch)
	ring.oversized = make([dynamic]Buffer)

	buffer: Buffer
	if err := createBuffer(
		graphicsData,
		int(STAGING_SIZE),
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&buffer,
	); err != nil {
		logf(.Error, "Failed to create staging ring! Error: %v", err)
		return .FailedToCreateBuffer
	}
	ring.buffer = buffer.buffer
	ring.allocation = buffer.allocation
	ring.mapped = buffer.mapped

	semaphoreTypeInfo: vk.SemaphoreTypeCreateInfo = {
		sType         = .SEMAPHORE_TYPE_CREATE_INFO,
		pNext         = nil,
		semaphoreType = .TIMELINE,
		initialValue  = 0,
	}
	semaphoreInfo: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = &semaphoreTypeInfo,
		flags = {},
	}
	if res := vk.CreateSemaphore(graphicsData.device, &semaphoreInfo, nil, &ring.timeline);
	   res != .SUCCESS {
		logf(.Error, "Failed to create staging timeline semaphore! vkResult: %v", res)
		return .FailedToCreateSemaphore
	}

	logf(.Info, "Staging ring: %v MiB.", STAGING_SIZE / (1024 * 1024))
	return .None
}

@(private = "file")
stagingDestroy :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging

	stagingWait(graphicsData)

	if ring.commandBuffer != nil {
		vk.FreeCommandBuffers(
			graphicsData.device,
			graphicsData.graphicsCommandPool,
			1,
			&ring.commandBuffer,
		)
	}
	vk.DestroySemaphore(graphicsData.device, ring.timeline, nil)
	vk.DestroyBuffer(graphicsData.device, ring.buffer, nil)
	memoryFree(&graphicsData.memoryAllocator, &ring.allocation)

	delete(ring.pending)
	delete(ring.oversized)
	ring^ = {}
}

@(private = "file")
@(require_results)
stagingCommands :: proc(graphicsData: ^GraphicsData) -> (vk.CommandBuffer, StagingError) {
	ring := &graphicsData.staging
	if ring.recording {
		return ring.commandBuffer, .None
	}

	if ring.commandBuffer == nil {
		allocInfo: vk.CommandBufferAllocateInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			pNext              = nil,
			commandPool        = graphicsData.graphicsCommandPool,
			level              = .PRIMARY,
			commandBufferCount = 1,
		}
		if res := vk.AllocateCommandBuffers(graphicsData.device, &allocInfo, &ring.commandBuffer);
		   res != .SUCCESS {
			logf(.Error, "Failed to allocate staging command buffer! vkResult: %v", res)
			return nil, .FailedToRecord
		}
		vkNameObject(
			graphicsData.device,
			.COMMAND_BUFFER,
			u64(uintptr(ring.commandBuffer)),
			"Cmd: Staging",
		)
	}

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.ONE_TIME_SUBMIT},
		pInheritanceInfo = nil,
	}
	if res := vk.BeginCommandBuffer(ring.commandBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to begin staging command buffer! vkResult: %v", res)
		return nil, .FailedToRecord
	}
	ring.recording = true
	return ring.commandBuffer, .None
}

@(private = "file")
@(require_results)
stagingReserve :: proc(
	graphicsData: ^GraphicsData,
	size: vk.DeviceSize,
	alignment: vk.DeviceSize = 16,
) -> (
	offset: vk.DeviceSize,
	ptr: rawptr,
	ok: bool,
) {
	ring := &graphicsData.staging
	if size > ring.size {
		return 0, nil, false
	}

	head := u64(memoryAlignUp(vk.DeviceSize(ring.head), alignment))

	if vk.DeviceSize(head % u64(ring.size)) + size > ring.size {
		head += u64(ring.size) - (head % u64(ring.size))
	}

	for head + u64(size) - ring.tail > u64(ring.size) {
		if len(ring.pending) == 0 {
			stagingFlush(graphicsData)
			if len(ring.pending) == 0 {
				break
			}
		}
		stagingWaitBatch(graphicsData)
	}

	ring.head = head + u64(size)
	offset = vk.DeviceSize(head % u64(ring.size))
	return offset, rawptr(uintptr(ring.mapped) + uintptr(offset)), true
}

@(private = "file")
@(require_results)
stagingOversized :: proc(
	graphicsData: ^GraphicsData,
	size: vk.DeviceSize,
) -> (
	buffer: vk.Buffer,
	ptr: rawptr,
	err: StagingError,
) {
	staging: Buffer
	if createErr := createBuffer(
		graphicsData,
		int(size),
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging,
	); createErr != nil {
		logf(.Error, "Failed to create oversized staging buffer! Error: %v", createErr)
		return 0, nil, .FailedToCreateBuffer
	}
	append(&graphicsData.staging.oversized, staging)
	return staging.buffer, staging.mapped, .None
}

@(private = "file")
stagingFlush :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging
	if !ring.recording {
		return
	}

	if res := vk.EndCommandBuffer(ring.commandBuffer); res != .SUCCESS {
		logf(.Error, "Failed to end staging command buffer! vkResult: %v", res)
		return
	}
	ring.recording = false
	ring.submitted += 1

	submitInfo: vk.SubmitInfo2 = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = &vk.CommandBufferSubmitInfo {
			sType = .COMMAND_BUFFER_SUBMIT_INFO,
			pNext = nil,
			commandBuffer = ring.commandBuffer,
			deviceMask = 0,
		},
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = &vk.SemaphoreSubmitInfo {
			sType = .SEMAPHORE_SUBMIT_INFO,
			pNext = nil,
			semaphore = ring.timeline,
			value = ring.submitted,
			stageMask = {.ALL_COMMANDS},
			deviceIndex = 0,
		},
	}
	if res := vk.QueueSubmit2(graphicsData.graphicsQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Error, "Failed to submit staging commands! vkResult: %v", res)
		return
	}

	append(&ring.pending, StagingBatch{head = ring.head, value = ring.submitted})
}

@(private = "file")
stagingWaitBatch :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging
	if len(ring.pending) == 0 {
		return
	}

	batch := ring.pending[0]
	value := batch.value
	waitInfo: vk.SemaphoreWaitInfo = {
		sType          = .SEMAPHORE_WAIT_INFO,
		pNext          = nil,
		flags          = {},
		semaphoreCount = 1,
		pSemaphores    = &ring.timeline,
		pValues        = &value,
	}
	if res := vk.WaitSemaphores(graphicsData.device, &waitInfo, max(u64)); res != .SUCCESS {
		logf(.Error, "Failed to wait on staging timeline! vkResult: %v", res)
	}

	ring.tail = batch.head
	ordered_remove(&ring.pending, 0)
}

@(private = "file")
stagingWait :: proc(graphicsData: ^GraphicsData) {
	ring := &graphicsData.staging

	stagingFlush(graphicsData)
	for len(ring.pending) > 0 {
		stagingWaitBatch(graphicsData)
	}

	for &buffer in ring.oversized {
		deleteBuffer(graphicsData, &buffer)
	}
	clear(&ring.oversized)
}

@(private = "file")
@(require_results)
stagingUploadBuffer :: proc(
	graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	dst: vk.Buffer,
	dstOffset: vk.DeviceSize,
	src: rawptr,
	size: vk.DeviceSize,
) -> StagingError {
	srcBuffer: vk.Buffer
	srcOffset: vk.DeviceSize
	ptr: rawptr

	if offset, mapped, ok := stagingReserve(graphicsData, size); ok {
		srcBuffer = graphicsData.staging.buffer
		srcOffset = offset
		ptr = mapped
	} else {
		buffer, mapped := stagingOversized(graphicsData, size) or_return
		srcBuffer = buffer
		srcOffset = 0
		ptr = mapped
	}

	mem.copy(ptr, src, int(size))

	copyRegion: vk.BufferCopy2 = {
		sType     = .BUFFER_COPY_2,
		pNext     = nil,
		srcOffset = srcOffset,
		dstOffset = dstOffset,
		size      = size,
	}
	vk.CmdCopyBuffer2(
		commandBuffer,
		&vk.CopyBufferInfo2 {
			sType = .COPY_BUFFER_INFO_2,
			pNext = nil,
			srcBuffer = srcBuffer,
			dstBuffer = dst,
			regionCount = 1,
			pRegions = &copyRegion,
		},
	)
	return .None
}


// ===[ Buffers ]==============================================================

@(require_results)
// `usage2` carries flags that only exist in the 64-bit usage enum (the descriptor heap bit, for
// instance). It is passed through a BufferUsageFlags2CreateInfo, which maintenance5 allows.
@(private = "file")
createBuffer :: proc(
	using graphicsData: ^GraphicsData,
	size: int,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^Buffer,
	usage2: vk.BufferUsageFlags2 = {},
) -> BufferError {
	usage2Info: vk.BufferUsageFlags2CreateInfo = {
		sType = .BUFFER_USAGE_FLAGS_2_CREATE_INFO,
		pNext = nil,
		usage = usage2,
	}

	// Descriptor heap writes describe a buffer by its device address, so every buffer that could
	// end up in the heap needs this. Adding it unconditionally is simpler than tracking which do.
	bufferInfo: vk.BufferCreateInfo = {
		sType                 = .BUFFER_CREATE_INFO,
		pNext                 = &usage2Info if usage2 != {} else nil,
		flags                 = {},
		size                  = vk.DeviceSize(size),
		usage                 = usage + {.SHADER_DEVICE_ADDRESS},
		sharingMode           = .EXCLUSIVE,
		queueFamilyIndexCount = 0,
		pQueueFamilyIndices   = nil,
	}
	dedicatedRequirements: vk.MemoryDedicatedRequirements = {
		sType = .MEMORY_DEDICATED_REQUIREMENTS,
		pNext = nil,
	}
	memoryRequirements: vk.MemoryRequirements2 = {
		sType = .MEMORY_REQUIREMENTS_2,
		pNext = &dedicatedRequirements,
	}
	vk.GetDeviceBufferMemoryRequirements(
		device,
		&vk.DeviceBufferMemoryRequirements {
			sType = .DEVICE_BUFFER_MEMORY_REQUIREMENTS,
			pNext = nil,
			pCreateInfo = &bufferInfo,
		},
		&memoryRequirements,
	)

	if _, found := memoryFindType(
		&graphicsData.memoryAllocator,
		memoryRequirements.memoryRequirements.memoryTypeBits,
		properties,
	); !found {
		logf(.Error, "No memory type supports a %v byte buffer with %v.", size, properties)
		return .FailedToAllocateBufferMemory
	}

	if res := vk.CreateBuffer(device, &bufferInfo, nil, &buffer.buffer); res != .SUCCESS {
		logf(.Error, "Failed to create buffer! vkResult: %v", res)
		return .FailedToCreateBuffer
	}

	dedicatedInfo: vk.MemoryDedicatedAllocateInfo = {
		sType  = .MEMORY_DEDICATED_ALLOCATE_INFO,
		pNext  = nil,
		image  = 0,
		buffer = buffer.buffer,
	}
	dedicated: ^vk.MemoryDedicatedAllocateInfo
	if dedicatedRequirements.prefersDedicatedAllocation ||
	   dedicatedRequirements.requiresDedicatedAllocation {
		dedicated = &dedicatedInfo
	}

	allocation, err := memoryAllocate(
		&graphicsData.memoryAllocator,
		memoryRequirements.memoryRequirements,
		properties,
		.Linear,
		dedicated,
	)
	if err != .None {
		vk.DestroyBuffer(device, buffer.buffer, nil)
		buffer.buffer = 0
		return .FailedToAllocateBufferMemory
	}
	buffer.allocation = allocation
	buffer.mapped = allocation.mapped

	bindInfo: vk.BindBufferMemoryInfo = {
		sType        = .BIND_BUFFER_MEMORY_INFO,
		pNext        = nil,
		buffer       = buffer.buffer,
		memory       = allocation.memory,
		memoryOffset = allocation.offset,
	}
	if res := vk.BindBufferMemory2(device, 1, &bindInfo); res != .SUCCESS {
		logf(.Error, "Failed to bind buffer memory! vkResult: %v", res)
		return .FailedToBindBufferMemory
	}

	return .None
}

@(private = "file")
@(require_results)
loadBufferToGPU :: proc(
	using graphicsData: ^GraphicsData,
	bufferSize: int,
	srcData: rawptr,
	dstBuffer: ^Buffer,
	bufferType: vk.BufferUsageFlag,
) -> Error {
	if err := createBuffer(
		graphicsData,
		bufferSize,
		{.TRANSFER_DST, .STORAGE_BUFFER, bufferType},
		{.DEVICE_LOCAL},
		dstBuffer,
	); err != nil {
		logf(.Error, "Failed to create destination buffer! Error: %v", err)
		return BufferError.FailedToCreateBuffer
	}

	commandBuffer, cmdErr := stagingCommands(graphicsData)
	if cmdErr != .None {
		return cmdErr
	}

	if err := stagingUploadBuffer(
		graphicsData,
		commandBuffer,
		dstBuffer.buffer,
		0,
		srcData,
		vk.DeviceSize(bufferSize),
	); err != .None {
		return err
	}

	return nil
}

@(private = "file")
deleteBuffer :: proc(using graphicsData: ^GraphicsData, buffer: ^Buffer) {
	vk.DestroyBuffer(device, buffer.buffer, nil)
	memoryFree(&graphicsData.memoryAllocator, &buffer.allocation)
	buffer^ = {}
}


// ===[ Images and Samplers ]==================================================

@(private = "file")
@(require_results)
createImage :: proc(
	using graphicsData: ^GraphicsData,
	image: ^Image,
	flags: vk.ImageCreateFlags,
	imageType: vk.ImageType,
	width, height, arrayLayers: u32,
	sampleCount: vk.SampleCountFlags,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	properties: vk.MemoryPropertyFlags,
	sharingMode: vk.SharingMode,
	queueFamilyIndexCount: u32,
	queueFamilyIndices: [^]u32,
) -> ImageError {
	imageInfo: vk.ImageCreateInfo = {
		sType                 = .IMAGE_CREATE_INFO,
		pNext                 = nil,
		flags                 = flags,
		imageType             = imageType,
		format                = image.format,
		extent                = {width, height, 1},
		mipLevels             = 1,
		arrayLayers           = arrayLayers,
		samples               = sampleCount,
		tiling                = tiling,
		usage                 = usage,
		sharingMode           = sharingMode,
		queueFamilyIndexCount = queueFamilyIndexCount,
		pQueueFamilyIndices   = queueFamilyIndices,
		initialLayout         = .UNDEFINED,
	}

	if res := vk.CreateImage(device, &imageInfo, nil, &image.vkImage); res != .SUCCESS {
		logf(.Error, "Failed to create texture! vkResult: %d", res)
		return .FailedToCreateImage
	}

	dedicatedRequirements: vk.MemoryDedicatedRequirements = {
		sType = .MEMORY_DEDICATED_REQUIREMENTS,
		pNext = nil,
	}
	memoryRequirements: vk.MemoryRequirements2 = {
		sType = .MEMORY_REQUIREMENTS_2,
		pNext = &dedicatedRequirements,
	}
	vk.GetImageMemoryRequirements2(
		device,
		&vk.ImageMemoryRequirementsInfo2 {
			sType = .IMAGE_MEMORY_REQUIREMENTS_INFO_2,
			pNext = nil,
			image = image.vkImage,
		},
		&memoryRequirements,
	)

	dedicatedInfo: vk.MemoryDedicatedAllocateInfo = {
		sType  = .MEMORY_DEDICATED_ALLOCATE_INFO,
		pNext  = nil,
		image  = image.vkImage,
		buffer = 0,
	}
	dedicated: ^vk.MemoryDedicatedAllocateInfo
	if dedicatedRequirements.prefersDedicatedAllocation ||
	   dedicatedRequirements.requiresDedicatedAllocation {
		dedicated = &dedicatedInfo
	}

	allocation, err := memoryAllocate(
		&graphicsData.memoryAllocator,
		memoryRequirements.memoryRequirements,
		properties,
		.Linear if tiling == .LINEAR else .Optimal,
		dedicated,
	)
	if err != .None {
		vk.DestroyImage(device, image.vkImage, nil)
		image.vkImage = 0
		return .FailedToAllocateImageMemory
	}
	image.allocation = allocation

	bindInfo: vk.BindImageMemoryInfo = {
		sType        = .BIND_IMAGE_MEMORY_INFO,
		pNext        = nil,
		image        = image.vkImage,
		memory       = allocation.memory,
		memoryOffset = allocation.offset,
	}
	if res := vk.BindImageMemory2(device, 1, &bindInfo); res != .SUCCESS {
		logf(.Error, "Failed to bind image memory! vkResult: %v", res)
		return .FailedToBindImageMemory
	}

	return .None
}

@(private = "file")
createImageView :: proc(
	using graphicsData: ^GraphicsData,
	image: vk.Image,
	viewType: vk.ImageViewType,
	format: vk.Format,
	aspectFlags: vk.ImageAspectFlags,
	layerCount: u32,
	baseArrayLayer: u32 = 0,
) -> (
	imageView: vk.ImageView,
	viewInfo: vk.ImageViewCreateInfo,
	err: ImageError = .None,
) {
	viewInfo = {
		sType = .IMAGE_VIEW_CREATE_INFO,
		pNext = nil,
		flags = {},
		image = image,
		viewType = viewType,
		format = format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = aspectFlags,
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = baseArrayLayer,
			layerCount = layerCount,
		},
	}
	if res := vk.CreateImageView(device, &viewInfo, nil, &imageView); res != .SUCCESS {
		logf(.Error, "Failed to create image view! vkResult: %d", res)
		err = .FailedToCreateImageView
		return
	}
	return
}

@(private = "file")
transitionImageLayout :: proc(
	using graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	image: vk.Image,
	oldLayout, newLayout: vk.ImageLayout,
	aspectMask: vk.ImageAspectFlags,
	layerCount: u32,
) -> ImageError {
	srcStage, dstStage: vk.PipelineStageFlags2
	srcAccess, dstAccess: vk.AccessFlags2

	#partial switch oldLayout {
	case .UNDEFINED:
		srcStage = {}
		srcAccess = {}
	case .TRANSFER_SRC_OPTIMAL:
		srcStage = {.COPY, .BLIT}
		srcAccess = {.TRANSFER_READ}
	case .TRANSFER_DST_OPTIMAL:
		srcStage = {.COPY, .BLIT}
		srcAccess = {.TRANSFER_WRITE}
	case .SHADER_READ_ONLY_OPTIMAL:
		srcStage = {.FRAGMENT_SHADER, .COMPUTE_SHADER}
		srcAccess = {.SHADER_SAMPLED_READ}
	case .GENERAL:
		srcStage = {.COMPUTE_SHADER}
		srcAccess = {.SHADER_STORAGE_READ, .SHADER_STORAGE_WRITE}
	case:
		log(.Error, "Unsupported image layout transition!")
		return .TransitionFailed
	}

	#partial switch newLayout {
	case .TRANSFER_SRC_OPTIMAL:
		dstStage = {.COPY, .BLIT}
		dstAccess = {.TRANSFER_READ}
	case .TRANSFER_DST_OPTIMAL:
		dstStage = {.COPY, .BLIT}
		dstAccess = {.TRANSFER_WRITE}
	case .SHADER_READ_ONLY_OPTIMAL:
		dstStage = {.FRAGMENT_SHADER, .COMPUTE_SHADER}
		dstAccess = {.SHADER_SAMPLED_READ}
	case .GENERAL:
		dstStage = {.COMPUTE_SHADER}
		dstAccess = {.SHADER_STORAGE_READ, .SHADER_STORAGE_WRITE}
	case .PRESENT_SRC_KHR:
		dstStage = {}
		dstAccess = {}
	case:
		log(.Error, "Unsupported image layout transition!")
		return .TransitionFailed
	}

	vk.CmdPipelineBarrier2(
		commandBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &vk.ImageMemoryBarrier2 {
				sType = .IMAGE_MEMORY_BARRIER_2,
				pNext = nil,
				srcStageMask = srcStage,
				srcAccessMask = srcAccess,
				dstStageMask = dstStage,
				dstAccessMask = dstAccess,
				oldLayout = oldLayout,
				newLayout = newLayout,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = image,
				subresourceRange = vk.ImageSubresourceRange {
					aspectMask = aspectMask,
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = layerCount,
				},
			},
		},
	)

	return .None
}

@(private = "file")
copyBufferToImage :: proc(
	using graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	buffer: vk.Buffer,
	bufferOffset: vk.DeviceSize,
	image: vk.Image,
	width, height: u32,
) {
	region: vk.BufferImageCopy2 = {
		sType = .BUFFER_IMAGE_COPY_2,
		pNext = nil,
		bufferOffset = bufferOffset,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = vk.ImageSubresourceLayers {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = vk.Offset3D{x = 0, y = 0, z = 0},
		imageExtent = vk.Extent3D{width = width, height = height, depth = 1},
	}
	vk.CmdCopyBufferToImage2(
		commandBuffer,
		&vk.CopyBufferToImageInfo2 {
			sType = .COPY_BUFFER_TO_IMAGE_INFO_2,
			pNext = nil,
			srcBuffer = buffer,
			dstImage = image,
			dstImageLayout = .TRANSFER_DST_OPTIMAL,
			regionCount = 1,
			pRegions = &region,
		},
	)
}


@(private = "file")
setViewportAndScissor :: proc(commandBuffer: vk.CommandBuffer, size: [2]u32) {
	vk.CmdSetViewport(
		commandBuffer,
		0,
		1,
		&vk.Viewport {
			x = 0,
			y = 0,
			width = f32(size.x),
			height = f32(size.y),
			minDepth = 0,
			maxDepth = 1,
		},
	)
	vk.CmdSetScissor(commandBuffer, 0, 1, &vk.Rect2D{offset = {0, 0}, extent = {size.x, size.y}})
}

@(private = "file")
upscaleImage :: proc(
	commandBuffer: vk.CommandBuffer,
	src, dst: vk.Image,
	srcSize, dstSize: vk.Extent2D,
	dstOffset: vk.Offset2D,
	srcLayer, dstLayer: u32,
) {
	blit: vk.ImageBlit2 = {
		sType = .IMAGE_BLIT_2,
		pNext = nil,
		srcSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = srcLayer,
			layerCount = 1,
		},
		srcOffsets = {
			{x = 0, y = 0, z = 0},
			{x = i32(srcSize.width), y = i32(srcSize.height), z = 1},
		},
		dstSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = dstLayer,
			layerCount = 1,
		},
		dstOffsets = {
			{x = dstOffset.x, y = dstOffset.y, z = 0},
			{x = dstOffset.x + i32(dstSize.width), y = dstOffset.y + i32(dstSize.height), z = 1},
		},
	}

	vk.CmdBlitImage2(
		commandBuffer,
		&vk.BlitImageInfo2 {
			sType = .BLIT_IMAGE_INFO_2,
			pNext = nil,
			srcImage = src,
			srcImageLayout = .TRANSFER_SRC_OPTIMAL,
			dstImage = dst,
			dstImageLayout = .TRANSFER_DST_OPTIMAL,
			regionCount = 1,
			pRegions = &blit,
			filter = .LINEAR,
		},
	)
}

@(private = "file")
copyImage :: proc(
	commandBuffer: vk.CommandBuffer,
	extent: vk.Extent3D,
	srcImage, dstImage: vk.Image,
	srcLayout, dstLayout: vk.ImageLayout,
) {
	region: vk.ImageCopy2 = {
		sType = .IMAGE_COPY_2,
		pNext = nil,
		srcSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		srcOffset = {x = 0, y = 0, z = 0},
		dstSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		dstOffset = {x = 0, y = 0, z = 0},
		extent = extent,
	}
	vk.CmdCopyImage2(
		commandBuffer,
		&vk.CopyImageInfo2 {
			sType = .COPY_IMAGE_INFO_2,
			pNext = nil,
			srcImage = srcImage,
			srcImageLayout = srcLayout,
			dstImage = dstImage,
			dstImageLayout = dstLayout,
			regionCount = 1,
			pRegions = &region,
		},
	)
}


@(private = "file")
@(require_results)
createSamplers :: proc(using graphicsData: ^GraphicsData) -> SamplerError {
	// No VkSampler objects: the descriptor heap takes sampler create infos directly and writes
	// the descriptor from them, so the sampler heap is the only place a sampler exists.
	samplerInfo: vk.SamplerCreateInfo = {
		sType                   = .SAMPLER_CREATE_INFO,
		pNext                   = nil,
		flags                   = {},
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipmapMode              = .LINEAR,
		addressModeU            = .CLAMP_TO_EDGE,
		addressModeV            = .CLAMP_TO_EDGE,
		addressModeW            = .CLAMP_TO_EDGE,
		mipLodBias              = 0,
		anisotropyEnable        = false,
		maxAnisotropy           = 0.0,
		compareEnable           = false,
		compareOp               = .NEVER,
		minLod                  = 0,
		maxLod                  = vk.LOD_CLAMP_NONE,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}
	writeSamplerDescriptor(graphicsData, .Nearest, &samplerInfo)

	properties: vk.PhysicalDeviceProperties2 = {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = nil,
	}
	vk.GetPhysicalDeviceProperties2(physicalDevice, &properties)
	samplerInfo.anisotropyEnable = true
	samplerInfo.maxAnisotropy = properties.properties.limits.maxSamplerAnisotropy
	writeSamplerDescriptor(graphicsData, .Anisotropic, &samplerInfo)

	return .None
}

@(private = "file")
deleteImage :: proc(using graphicsData: ^GraphicsData, image: ^Image) {
	vk.DestroyImageView(device, image.view, nil)
	vk.DestroyImage(device, image.vkImage, nil)
	memoryFree(&graphicsData.memoryAllocator, &image.allocation)
	image.view = 0
	image.vkImage = 0
}

@(private = "file")
findSupportedDepthFormat :: proc(
	using graphicsData: ^GraphicsData,
	candidates: []vk.Format,
	tiling: vk.ImageTiling,
	features: vk.FormatFeatureFlags,
) -> vk.Format {
	for format in candidates {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physicalDevice, format, &props)
		if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
			return format
		} else if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
			return format
		}
	}
	log(.Error, "Failed to find supported format!")
	return .UNDEFINED
}


// ===[ Texture Loading ]======================================================

@(require_results)
loadImages :: proc(using graphicsData: ^GraphicsData, scene: ^Scene, imagePaths: []string) -> Error {
	return addImages(graphicsData, scene, imagePaths)
}

@(require_results)
addImages :: proc(using graphicsData: ^GraphicsData, scene: ^Scene, imagePaths: []string) -> Error {
	buffers := &scene.buffers
	if buffers.textures == nil {
		buffers.textures = make([dynamic]Image)
	}

	defer stagingWait(graphicsData)

	for path in imagePaths {
		width, height: i32
		pixels := img.load(
			strings.clone_to_cstring(path, allocator = context.temp_allocator),
			&width,
			&height,
			nil,
			4,
		)
		if pixels == nil {
			logf(.Error, "Failed to load texture: %v", path)
			return ImageError.FailedToLoadImage
		}
		defer img.image_free(pixels)

		textureSize := vk.DeviceSize(width * height * 4)

		image: Image = {
			format  = .R8G8B8A8_SRGB,
			sampler = u32(SamplerSlot.Anisotropic),
		}
		if err := createImage(
			graphicsData,
			&image,
			{},
			.D2,
			u32(width),
			u32(height),
			1,
			{._1},
			.OPTIMAL,
			{.HOST_TRANSFER, .SAMPLED},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		); err != nil {
			logf(.Error, "Failed to create image for %v! Error: %v", path, err)
			return err
		}

		viewErr: ImageError
		image.view, image.viewInfo, viewErr = createImageView(
			graphicsData,
			image.vkImage,
			.D2,
			image.format,
			{.COLOR},
			1,
		)
		if viewErr != .None {
			logf(.Error, "Failed to create image view for %v! Error: %v", path, viewErr)
			return viewErr
		}

		slot, ok := acquireTextureSlot(graphicsData)
		if !ok {
			return DescriptorHeapError.OutOfTextureSlots
		}
		image.heapSlot = slot

		subresourceRange: vk.ImageSubresourceRange = {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		}
		transition: vk.HostImageLayoutTransitionInfo = {
			sType            = .HOST_IMAGE_LAYOUT_TRANSITION_INFO,
			pNext            = nil,
			image            = image.vkImage,
			oldLayout        = .UNDEFINED,
			newLayout        = .SHADER_READ_ONLY_OPTIMAL,
			subresourceRange = subresourceRange,
		}
		if res := vk.TransitionImageLayout(device, 1, &transition); res != .SUCCESS {
			logf(.Error, "Failed to transition %v for host copy! vkResult: %v", path, res)
			return ImageError.TransitionFailed
		}

		region: vk.MemoryToImageCopy = {
			sType = .MEMORY_TO_IMAGE_COPY,
			pNext = nil,
			pHostPointer = pixels,
			memoryRowLength = 0,
			memoryImageHeight = 0,
			imageSubresource = {
				aspectMask = {.COLOR},
				mipLevel = 0,
				baseArrayLayer = 0,
				layerCount = 1,
			},
			imageOffset = {0, 0, 0},
			imageExtent = {u32(width), u32(height), 1},
		}
		copyInfo: vk.CopyMemoryToImageInfo = {
			sType          = .COPY_MEMORY_TO_IMAGE_INFO,
			pNext          = nil,
			flags          = {},
			dstImage       = image.vkImage,
			dstImageLayout = .SHADER_READ_ONLY_OPTIMAL,
			regionCount    = 1,
			pRegions       = &region,
		}
		if res := vk.CopyMemoryToImage(device, &copyInfo); res != .SUCCESS {
			logf(.Error, "Failed to host copy texture %v! vkResult: %v", path, res)
			return ImageError.FailedToLoadImage
		}

		append(&buffers.textures, image)
	}

	return nil
}

// ===[ Descriptor Heaps ]=====================================================

@(private = "file")
// Writes every descriptor for both frames into the heap. Replaces the old descriptor pools,
// sets and set layouts entirely; see DescriptorHeap.odin.
updateDescriptorSets :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	buffers := &scene.buffers

	textureBufferLen := 0
	for &model in scene.models {
		textureBufferLen += len(model.instances) * len(model.meshes)
	}

	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		writeBufferDescriptor(
			graphicsData,
			frame,
			.Vertex,
			buffers.vertexBuffer.buffer,
			vk.DeviceSize(size_of(Vertex) * len(scene.vertices)),
			.STORAGE_BUFFER,
		)
		writeBufferDescriptor(
			graphicsData,
			frame,
			.Uniform,
			uniformBuffers[frame].buffer,
			size_of(UniformBuffer),
			.STORAGE_BUFFER,
		)
		writeBufferDescriptor(
			graphicsData,
			frame,
			.Instance,
			buffers.instanceBuffers[frame].buffer,
			vk.DeviceSize(size_of(InstanceInfo) * len(scene.objects)),
			.STORAGE_BUFFER,
		)
		writeBufferDescriptor(
			graphicsData,
			frame,
			.Bone,
			buffers.boneBuffers[frame].buffer,
			vk.DeviceSize(size_of(Mat4) * scene.boneCount),
			.STORAGE_BUFFER,
		)

		writeBufferDescriptor(
			graphicsData,
			frame,
			.Transform,
			buffers.transformBuffers[frame].buffer,
			vk.DeviceSize(size_of(Mat4) * scene.vertexCount),
			.STORAGE_BUFFER,
		)
		writeBufferDescriptor(
			graphicsData,
			frame,
			.Position,
			buffers.positionBuffers[frame].buffer,
			vk.DeviceSize(size_of(Vec4) * scene.vertexCount),
			.STORAGE_BUFFER,
		)

		writeBufferDescriptor(
			graphicsData,
			frame,
			.Light,
			buffers.lightBuffers[frame].buffer,
			vk.DeviceSize(size_of(LightData) * len(scene.lights)),
			.STORAGE_BUFFER,
		)
		writeBufferDescriptor(
			graphicsData,
			frame,
			.TextureIndex,
			buffers.textureIndexBuffer.buffer,
			vk.DeviceSize(size_of(u32) * textureBufferLen * len(TextureIndex)),
			.STORAGE_BUFFER,
		)

		for &texture in buffers.textures {
			writeTextureDescriptor(graphicsData, frame, texture.heapSlot, &texture.viewInfo)
		}
		writeImageDescriptor(
			graphicsData,
			frame,
			.ShadowMap,
			&pipelines[.Light].images[0].viewInfo,
			.SHADER_READ_ONLY_OPTIMAL,
			.SAMPLED_IMAGE,
		)
		writeImageDescriptor(
			graphicsData,
			frame,
			.SceneDepth,
			&pipelines[.Scene].images[1].viewInfo,
			.SHADER_READ_ONLY_OPTIMAL,
			.SAMPLED_IMAGE,
		)
		writeImageDescriptor(
			graphicsData,
			frame,
			.RenderedImage,
			&pipelines[.PostProcess].images[0].viewInfo,
			.GENERAL,
			.STORAGE_IMAGE,
		)
		writeImageDescriptor(
			graphicsData,
			frame,
			.ProcessedImage,
			&pipelines[.PostProcess].images[1].viewInfo,
			.GENERAL,
			.STORAGE_IMAGE,
		)
	}
}

// Rewrites only the descriptors whose images are recreated on a swapchain resize.
updateComputeDescriptorSets :: proc(using graphicsData: ^GraphicsData) {
	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		writeImageDescriptor(
			graphicsData,
			frame,
			.SceneDepth,
			&pipelines[.Scene].images[1].viewInfo,
			.SHADER_READ_ONLY_OPTIMAL,
			.SAMPLED_IMAGE,
		)
		writeImageDescriptor(
			graphicsData,
			frame,
			.RenderedImage,
			&pipelines[.PostProcess].images[0].viewInfo,
			.GENERAL,
			.STORAGE_IMAGE,
		)
		writeImageDescriptor(
			graphicsData,
			frame,
			.ProcessedImage,
			&pipelines[.PostProcess].images[1].viewInfo,
			.GENERAL,
			.STORAGE_IMAGE,
		)
	}
}

@(private = "file")
MAX_HEAP_TEXTURES :: 1024

BufferSlot :: enum u32 {
	Vertex       = 0,
	Uniform      = 1,
	Instance     = 2,
	Bone         = 3,
	Transform    = 4,
	Position     = 5,
	Light        = 6,
	TextureIndex = 7,
}

@(private = "file")
ImageSlot :: enum u32 {
	ShadowMap      = 0,
	SceneDepth     = 1,
	RenderedImage  = 2,
	ProcessedImage = 3,
}

@(private = "file")
SamplerSlot :: enum u32 {
	Nearest    = 0,
	Anisotropic = 1,
}

@(private = "file")
DescriptorHeaps :: struct {
	resource:        Buffer,
	resourceAddress: vk.DeviceAddress,
	frameStride:     vk.DeviceSize,
	bufferBase:      vk.DeviceSize,
	imageBase:       vk.DeviceSize,
	textureBase:     vk.DeviceSize,

	sampler:         Buffer,
	samplerAddress:  vk.DeviceAddress,
	samplerReserved: vk.DeviceSize,

	textureFree:     [dynamic]u32,
}

@(private = "file")
@(require_results)
bufferSlotOffset :: proc(graphicsData: ^GraphicsData, slot: BufferSlot) -> u32 {
	stride := graphicsData.heapProperties.bufferDescriptorSize
	return u32(graphicsData.heaps.bufferBase + vk.DeviceSize(slot) * stride)
}

bufferSlotIndex :: proc(graphicsData: ^GraphicsData, slot: BufferSlot) -> u32 {
	return bufferSlotOffset(graphicsData, slot) / u32(graphicsData.heapProperties.bufferDescriptorSize)
}

@(private = "file")
@(require_results)
imageSlotOffset :: proc(graphicsData: ^GraphicsData, slot: ImageSlot) -> u32 {
	properties := &graphicsData.heapProperties
	return u32(graphicsData.heaps.imageBase + vk.DeviceSize(slot) * properties.imageDescriptorSize)
}

imageSlotIndex :: proc(graphicsData: ^GraphicsData, slot: ImageSlot) -> u32 {
	return imageSlotOffset(graphicsData, slot) / u32(graphicsData.heapProperties.imageDescriptorSize)
}

textureSlotOffset :: proc(graphicsData: ^GraphicsData, slot: u32) -> u32 {
	properties := &graphicsData.heapProperties
	return u32(graphicsData.heaps.textureBase + vk.DeviceSize(slot) * properties.imageDescriptorSize)
}

textureSlotIndex :: proc(graphicsData: ^GraphicsData, slot: u32) -> u32 {
	return textureSlotOffset(graphicsData, slot) / u32(graphicsData.heapProperties.imageDescriptorSize)
}

acquireTextureSlot :: proc(graphicsData: ^GraphicsData) -> (slot: u32, ok: bool) {
	heaps := &graphicsData.heaps
	if len(heaps.textureFree) == 0 {
		logf(.Error, "Descriptor heap is out of texture slots (max %v).", MAX_HEAP_TEXTURES)
		return 0, false
	}
	slot = pop(&heaps.textureFree)
	return slot, true
}

releaseTextureSlot :: proc(graphicsData: ^GraphicsData, slot: u32) {
	append(&graphicsData.heaps.textureFree, slot)
}

@(private = "file")
@(require_results)
samplerSlotOffset :: proc(graphicsData: ^GraphicsData, slot: SamplerSlot) -> u32 {
	properties := &graphicsData.heapProperties
	return u32(
		graphicsData.heaps.samplerReserved + vk.DeviceSize(slot) * properties.samplerDescriptorSize,
	)
}

samplerSlotIndex :: proc(graphicsData: ^GraphicsData, slot: SamplerSlot) -> u32 {
	return samplerSlotOffset(graphicsData, slot) /
		u32(graphicsData.heapProperties.samplerDescriptorSize)
}

@(private = "file")
@(require_results)
createDescriptorHeaps :: proc(using graphicsData: ^GraphicsData) -> DescriptorHeapError {
	properties := &heapProperties

	heaps.bufferBase = memoryAlignUp(
		properties.minResourceHeapReservedRange,
		properties.bufferDescriptorSize,
	)
	heaps.imageBase = memoryAlignUp(
		heaps.bufferBase + vk.DeviceSize(len(BufferSlot)) * properties.bufferDescriptorSize,
		properties.imageDescriptorSize,
	)
	heaps.textureBase =
		heaps.imageBase + vk.DeviceSize(len(ImageSlot)) * properties.imageDescriptorSize

	texturesEnd :=
		heaps.textureBase + vk.DeviceSize(MAX_HEAP_TEXTURES) * properties.imageDescriptorSize

	heaps.frameStride = memoryAlignUp(texturesEnd, properties.resourceHeapAlignment)
	resourceSize := heaps.frameStride * vk.DeviceSize(MAX_FRAMES_IN_FLIGHT)

	heaps.textureFree = make([dynamic]u32, 0, MAX_HEAP_TEXTURES)
	for i := MAX_HEAP_TEXTURES - 1; i >= 0; i -= 1 {
		append(&heaps.textureFree, u32(i))
	}

	if resourceSize > properties.maxResourceHeapSize {
		logf(
			.Fatal,
			"Resource heap needs %v bytes but the device caps it at %v.",
			resourceSize,
			properties.maxResourceHeapSize,
		)
		return .HeapTooSmall
	}

	if err := createBuffer(
		graphicsData,
		int(resourceSize),
		{.SHADER_DEVICE_ADDRESS},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&heaps.resource,
		{.DESCRIPTOR_HEAP_EXT, .SHADER_DEVICE_ADDRESS},
	); err != nil {
		logf(.Fatal, "Failed to create resource heap! Error: %v", err)
		return .FailedToCreateHeap
	}

	heaps.samplerReserved = memoryAlignUp(
		properties.minSamplerHeapReservedRange,
		properties.samplerDescriptorAlignment,
	)
	samplerSize := memoryAlignUp(
		heaps.samplerReserved + vk.DeviceSize(len(SamplerSlot)) * properties.samplerDescriptorSize,
		properties.samplerHeapAlignment,
	)

	if samplerSize > properties.maxSamplerHeapSize {
		logf(
			.Fatal,
			"Sampler heap needs %v bytes but the device caps it at %v.",
			samplerSize,
			properties.maxSamplerHeapSize,
		)
		return .HeapTooSmall
	}

	if err := createBuffer(
		graphicsData,
		int(samplerSize),
		{.SHADER_DEVICE_ADDRESS},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&heaps.sampler,
		{.DESCRIPTOR_HEAP_EXT, .SHADER_DEVICE_ADDRESS},
	); err != nil {
		logf(.Fatal, "Failed to create sampler heap! Error: %v", err)
		return .FailedToCreateHeap
	}

	heaps.resourceAddress = vk.GetBufferDeviceAddress(
		device,
		&vk.BufferDeviceAddressInfo {
			sType = .BUFFER_DEVICE_ADDRESS_INFO,
			pNext = nil,
			buffer = heaps.resource.buffer,
		},
	)
	heaps.samplerAddress = vk.GetBufferDeviceAddress(
		device,
		&vk.BufferDeviceAddressInfo {
			sType = .BUFFER_DEVICE_ADDRESS_INFO,
			pNext = nil,
			buffer = heaps.sampler.buffer,
		},
	)

	heapIndices = {
		vertexBuffer       = bufferSlotIndex(graphicsData, .Vertex),
		uniformBuffer      = bufferSlotIndex(graphicsData, .Uniform),
		instanceBuffer     = bufferSlotIndex(graphicsData, .Instance),
		boneBuffer         = bufferSlotIndex(graphicsData, .Bone),
		transformBuffer    = bufferSlotIndex(graphicsData, .Transform),
		positionBuffer     = bufferSlotIndex(graphicsData, .Position),
		lightBuffer        = bufferSlotIndex(graphicsData, .Light),
		textureIndexBuffer = bufferSlotIndex(graphicsData, .TextureIndex),
		shadowMap          = imageSlotIndex(graphicsData, .ShadowMap),
		sceneDepth         = imageSlotIndex(graphicsData, .SceneDepth),
		renderedImage      = imageSlotIndex(graphicsData, .RenderedImage),
		processedImage     = imageSlotIndex(graphicsData, .ProcessedImage),
		linearSampler      = samplerSlotIndex(graphicsData, .Nearest),
		anisotropicSampler = samplerSlotIndex(graphicsData, .Anisotropic),
	}

	vkNameObject(device, .BUFFER, u64(heaps.resource.buffer), "Heap: Resource")
	vkNameObject(device, .BUFFER, u64(heaps.sampler.buffer), "Heap: Sampler")

	logf(
		.Info,
		"Descriptor heaps: resource %v bytes (%v per frame), sampler %v bytes.",
		resourceSize,
		heaps.frameStride,
		samplerSize,
	)
	return .None
}

@(private = "file")
cleanupDescriptorHeaps :: proc(using graphicsData: ^GraphicsData) {
	delete(heaps.textureFree)
	deleteBuffer(graphicsData, &heaps.resource)
	deleteBuffer(graphicsData, &heaps.sampler)
	heaps = {}
}

@(private = "file")
bindDescriptorHeaps :: proc(
	using graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	frame: u32,
) {
	vk.CmdBindResourceHeapEXT(
		commandBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = {
				address = heaps.resourceAddress + vk.DeviceAddress(heaps.frameStride * vk.DeviceSize(frame)),
				size = heaps.frameStride,
			},
			reservedRangeOffset = 0,
			reservedRangeSize = heapProperties.minResourceHeapReservedRange,
		},
	)

	vk.CmdBindSamplerHeapEXT(
		commandBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = {
				address = heaps.samplerAddress,
				size = vk.DeviceSize(heaps.sampler.allocation.size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = heapProperties.minSamplerHeapReservedRange,
		},
	)
}

@(private = "file")
@(require_results)
frameSlotAddress :: proc(using graphicsData: ^GraphicsData, frame: u32, offset: u32) -> rawptr {
	base := uintptr(heaps.resource.mapped)
	return rawptr(base + uintptr(heaps.frameStride * vk.DeviceSize(frame)) + uintptr(offset))
}

@(private = "file")
writeBufferDescriptor :: proc(
	using graphicsData: ^GraphicsData,
	frame: u32,
	slot: BufferSlot,
	buffer: vk.Buffer,
	size: vk.DeviceSize,
	type: vk.DescriptorType,
) {
	if buffer == 0 || size == 0 {
		return
	}

	address := vk.GetBufferDeviceAddress(
		device,
		&vk.BufferDeviceAddressInfo{sType = .BUFFER_DEVICE_ADDRESS_INFO, pNext = nil, buffer = buffer},
	)
	addressRange: vk.DeviceAddressRangeEXT = {
		address = address,
		size    = size,
	}

	info: vk.ResourceDescriptorInfoEXT = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = type,
		data = {pAddressRange = &addressRange},
	}
	destination: vk.HostAddressRangeEXT = {
		address = frameSlotAddress(graphicsData, frame, bufferSlotOffset(graphicsData, slot)),
		size    = int(heapProperties.bufferDescriptorSize),
	}

	if res := vk.WriteResourceDescriptorsEXT(device, 1, &info, &destination); res != .SUCCESS {
		logf(.Error, "Failed to write %v descriptor! vkResult: %v", slot, res)
	}
}

@(private = "file")
writeImageDescriptor :: proc(
	using graphicsData: ^GraphicsData,
	frame: u32,
	slot: ImageSlot,
	viewInfo: ^vk.ImageViewCreateInfo,
	layout: vk.ImageLayout,
	type: vk.DescriptorType,
) {
	if viewInfo.image == 0 {
		return
	}

	imageInfo: vk.ImageDescriptorInfoEXT = {
		sType  = .IMAGE_DESCRIPTOR_INFO_EXT,
		pNext  = nil,
		pView  = viewInfo,
		layout = layout,
	}
	info: vk.ResourceDescriptorInfoEXT = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = type,
		data = {pImage = &imageInfo},
	}
	destination: vk.HostAddressRangeEXT = {
		address = frameSlotAddress(graphicsData, frame, imageSlotOffset(graphicsData, slot)),
		size    = int(heapProperties.imageDescriptorSize),
	}

	if res := vk.WriteResourceDescriptorsEXT(device, 1, &info, &destination); res != .SUCCESS {
		logf(.Error, "Failed to write %v descriptor! vkResult: %v", slot, res)
	}
}

@(private = "file")
writeTextureDescriptor :: proc(
	using graphicsData: ^GraphicsData,
	frame: u32,
	slot: u32,
	viewInfo: ^vk.ImageViewCreateInfo,
) {
	if viewInfo.image == 0 {
		return
	}

	imageInfo: vk.ImageDescriptorInfoEXT = {
		sType  = .IMAGE_DESCRIPTOR_INFO_EXT,
		pNext  = nil,
		pView  = viewInfo,
		layout = .SHADER_READ_ONLY_OPTIMAL,
	}
	info: vk.ResourceDescriptorInfoEXT = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = .SAMPLED_IMAGE,
		data = {pImage = &imageInfo},
	}
	destination: vk.HostAddressRangeEXT = {
		address = frameSlotAddress(graphicsData, frame, textureSlotOffset(graphicsData, slot)),
		size    = int(heapProperties.imageDescriptorSize),
	}

	if res := vk.WriteResourceDescriptorsEXT(device, 1, &info, &destination); res != .SUCCESS {
		logf(.Error, "Failed to write texture descriptor %v! vkResult: %v", slot, res)
	}
}

writeSamplerDescriptor :: proc(
	using graphicsData: ^GraphicsData,
	slot: SamplerSlot,
	samplerInfo: ^vk.SamplerCreateInfo,
) {
	destination: vk.HostAddressRangeEXT = {
		address = rawptr(
			uintptr(heaps.sampler.mapped) + uintptr(samplerSlotOffset(graphicsData, slot)),
		),
		size = int(heapProperties.samplerDescriptorSize),
	}

	if res := vk.WriteSamplerDescriptorsEXT(device, 1, samplerInfo, &destination);
	   res != .SUCCESS {
		logf(.Error, "Failed to write %v sampler descriptor! vkResult: %v", slot, res)
	}
}

// ===[ Pipelines ]============================================================

@(private = "file")
PipelineIndex :: enum {
	Transform,
	Light,
	Scene,
	Gizmo,
	PostProcess,
}

@(private = "file")
Pipeline :: struct {
	handle:     vk.Pipeline,
	images:     []Image,
	descriptor: vk.DescriptorImageInfo,
}

@(private = "file")
PIPELINE_CACHE_PATH: string : "pipeline_cache.bin"

@(private = "file")
createPipelineCache :: proc(using graphicsData: ^GraphicsData) {
	initialData, readErr := os.read_entire_file(PIPELINE_CACHE_PATH, context.temp_allocator)
	if readErr != nil {
		logf(.Info, "No pipeline cache at %v, starting cold.", PIPELINE_CACHE_PATH)
		initialData = nil
	}

	cacheInfo: vk.PipelineCacheCreateInfo = {
		sType           = .PIPELINE_CACHE_CREATE_INFO,
		pNext           = nil,
		flags           = {},
		initialDataSize = len(initialData),
		pInitialData    = raw_data(initialData),
	}

	if res := vk.CreatePipelineCache(device, &cacheInfo, nil, &pipelineCache); res != .SUCCESS {
		logf(.Warning, "Failed to create pipeline cache! vkResult: %v", res)
		pipelineCache = 0
	}
}

@(private = "file")
savePipelineCache :: proc(using graphicsData: ^GraphicsData) {
	if pipelineCache == 0 {
		return
	}

	size: int
	if res := vk.GetPipelineCacheData(device, pipelineCache, &size, nil); res != .SUCCESS {
		logf(.Warning, "Failed to size pipeline cache! vkResult: %v", res)
		return
	}

	data := make([]byte, size, context.temp_allocator)
	if res := vk.GetPipelineCacheData(device, pipelineCache, &size, raw_data(data));
	   res != .SUCCESS {
		logf(.Warning, "Failed to read pipeline cache! vkResult: %v", res)
		return
	}

	if writeErr := os.write_entire_file(PIPELINE_CACHE_PATH, data); writeErr != nil {
		logf(
			.Warning,
			"Failed to write pipeline cache to %v! Error: %v",
			PIPELINE_CACHE_PATH,
			writeErr,
		)
		return
	}
	logf(.Info, "Wrote %v bytes of pipeline cache to %v.", size, PIPELINE_CACHE_PATH)
}

@(private = "file")
createTransformPipeline :: proc(
	using graphicsData: ^GraphicsData,
	shader: []byte,
) {
	createFlags: vk.PipelineCreateFlags2CreateInfo = {
		sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
		pNext = nil,
		flags = {.DESCRIPTOR_HEAP_EXT},
	}

	shaderStageInfo: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = &vk.ShaderModuleCreateInfo {
						sType = .SHADER_MODULE_CREATE_INFO,
						pNext = nil,
						flags = nil,
						codeSize = len(shader),
						pCode = transmute(^u32)raw_data(shader),
					},
		flags               = nil,
		stage               = {.COMPUTE},
		module              = 0,
		pName               = "main",
		pSpecializationInfo = nil,
	}

	pipelineInfo := vk.ComputePipelineCreateInfo {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = &createFlags,
		flags              = nil,
		stage              = shaderStageInfo,
		layout             = 0,
		basePipelineHandle = 0,
		basePipelineIndex  = 0,
	}

	if res := vk.CreateComputePipelines(
		device,
		pipelineCache,
		1,
		&pipelineInfo,
		nil,
		&pipelines[.Transform].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! vkResult: %v", res)
	}
}

@(private = "file")
destroyShadowFaceViews :: proc(using graphicsData: ^GraphicsData) {
	for view in shadowColourViews {
		vk.DestroyImageView(device, view, nil)
	}
	for view in shadowDepthViews {
		vk.DestroyImageView(device, view, nil)
	}
	delete(shadowColourViews)
	delete(shadowDepthViews)
	shadowColourViews = nil
	shadowDepthViews = nil
}

createLightPipelineImages :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	err: Error

	layerCount := u32(len(scene.lights)) * 6
	err = createImage(
		graphicsData,
		&pipelines[.Light].images[0],
		{.CUBE_COMPATIBLE},
		.D2,
		SHADOW_RESOLUTION.x,
		SHADOW_RESOLUTION.y,
		layerCount,
		{._1},
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		log(.Fatal, "Failed to create shadow map colour image!")
	}

	pipelines[.Light].images[0].view, pipelines[.Light].images[0].viewInfo, err = createImageView(
		graphicsData,
		pipelines[.Light].images[0].vkImage,
		.CUBE_ARRAY,
		pipelines[.Light].images[0].format,
		{.COLOR},
		layerCount,
	)
	if err != nil {
		log(.Fatal, "Failed to create shadow map colour image view!")
	}

	err = createImage(
		graphicsData,
		&pipelines[.Light].images[1],
		{.CUBE_COMPATIBLE},
		.D2,
		SHADOW_RESOLUTION.x,
		SHADOW_RESOLUTION.y,
		layerCount,
		{._1},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		log(.Fatal, "Failed to create shadow map depth image!")
	}

	pipelines[.Light].images[1].view, pipelines[.Light].images[1].viewInfo, err = createImageView(
		graphicsData,
		pipelines[.Light].images[1].vkImage,
		.CUBE_ARRAY,
		pipelines[.Light].images[1].format,
		{.DEPTH},
		layerCount,
	)
	if err != nil {
		log(.Fatal, "Failed to create shadow map depth image view!")
	}

	if multiviewProperties.maxMultiviewViewCount < SHADOW_CUBE_FACES {
		logf(
			.Fatal,
			"Shadow mapping needs %v multiview views, device supports %v.",
			SHADOW_CUBE_FACES,
			multiviewProperties.maxMultiviewViewCount,
		)
	}

	lightCount := len(scene.lights)
	shadowColourViews = make([]vk.ImageView, lightCount)
	shadowDepthViews = make([]vk.ImageView, lightCount)
	for light in 0 ..< lightCount {
		base := u32(light) * SHADOW_CUBE_FACES
		shadowColourViews[light], _, err = createImageView(
			graphicsData,
			pipelines[.Light].images[0].vkImage,
			.D2_ARRAY,
			pipelines[.Light].images[0].format,
			{.COLOR},
			SHADOW_CUBE_FACES,
			base,
		)
		if err != nil {
			log(.Fatal, "Failed to create shadow map colour face view!")
		}
		shadowDepthViews[light], _, err = createImageView(
			graphicsData,
			pipelines[.Light].images[1].vkImage,
			.D2_ARRAY,
			pipelines[.Light].images[1].format,
			{.DEPTH},
			SHADOW_CUBE_FACES,
			base,
		)
		if err != nil {
			log(.Fatal, "Failed to create shadow map depth face view!")
		}
	}

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to start commands! %v", err)
	}

	imageBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = nil,
			dstAccessMask = nil,
			oldLayout = .UNDEFINED,
			newLayout = .SHADER_READ_ONLY_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Light].images[0].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = layerCount,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = nil,
			dstAccessMask = nil,
			oldLayout = .UNDEFINED,
			newLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Light].images[1].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.DEPTH},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = layerCount,
			},
		},
	}
	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = len(imageBarriers),
			pImageMemoryBarriers = &imageBarriers[0],
		},
	)

	err = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to submit commands! %v", err)
	}
}

@(private = "file")
createLightPipeline :: proc(
	using graphicsData: ^GraphicsData,
	shaders: [][]byte,
) {
	createFlags: vk.PipelineCreateFlags2CreateInfo = {
		sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
		pNext = nil,
		flags = {.DESCRIPTOR_HEAP_EXT},
	}

	shaderStages := [?]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
							sType = .SHADER_MODULE_CREATE_INFO,
							pNext = nil,
							flags = nil,
							codeSize = len(shaders[0]),
							pCode = transmute(^u32)raw_data(shaders[0]),
						},
			flags = nil,
			stage = {.VERTEX},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
							sType = .SHADER_MODULE_CREATE_INFO,
							pNext = nil,
							flags = nil,
							codeSize = len(shaders[1]),
							pCode = transmute(^u32)raw_data(shaders[1]),
						},
			flags = nil,
			stage = {.FRAGMENT},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
	}

	renderingInfo: vk.PipelineRenderingCreateInfo = {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		pNext = nil,
		viewMask = SHADOW_VIEW_MASK,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &pipelines[.Light].images[0].format,
		depthAttachmentFormat = pipelines[.Light].images[1].format,
		stencilAttachmentFormat = .UNDEFINED,
	}
	createFlags.pNext = &renderingInfo

	pipelineInfo := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &createFlags,
		flags               = nil,
		stageCount          = u32(len(shaderStages)),
		pStages             = &shaderStages[0],
		pVertexInputState   = &vk.PipelineVertexInputStateCreateInfo {
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			vertexBindingDescriptionCount = 0,
			pVertexBindingDescriptions = nil,
			vertexAttributeDescriptionCount = 0,
			pVertexAttributeDescriptions = nil,
		},
		pInputAssemblyState = &vk.PipelineInputAssemblyStateCreateInfo {
			sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			topology = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		},
		pTessellationState  = nil,
		pViewportState      = &vk.PipelineViewportStateCreateInfo {
			sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			viewportCount = 1,
			pViewports = nil,
			scissorCount = 1,
			pScissors = nil,
		},
		pRasterizationState = &vk.PipelineRasterizationStateCreateInfo {
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			depthClampEnable = false,
			rasterizerDiscardEnable = false,
			polygonMode = .FILL,
			cullMode = {},
			frontFace = .COUNTER_CLOCKWISE,
			depthBiasEnable = true,
			depthBiasConstantFactor = DEPTH_BIAS_CONSTANT,
			depthBiasClamp = 0.0,
			depthBiasSlopeFactor = DEPTH_BIAS_SLOPE,
			lineWidth = 1.0,
		},
		pMultisampleState   = &vk.PipelineMultisampleStateCreateInfo {
			sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			rasterizationSamples = {._1},
			sampleShadingEnable = false,
			minSampleShading = 0.0,
			pSampleMask = nil,
			alphaToCoverageEnable = false,
			alphaToOneEnable = false,
		},
		pDepthStencilState  = &vk.PipelineDepthStencilStateCreateInfo {
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			depthTestEnable = true,
			depthWriteEnable = true,
			depthCompareOp = .LESS_OR_EQUAL,
			depthBoundsTestEnable = false,
			stencilTestEnable = false,
			front = {},
			back = {
					failOp = .KEEP,
					passOp = .KEEP,
					depthFailOp = .KEEP,
					compareOp = .ALWAYS,
					compareMask = 0,
					writeMask = 0,
					reference = 0,
			},
			minDepthBounds = 0,
			maxDepthBounds = 1,
		},
		pColorBlendState    = &vk.PipelineColorBlendStateCreateInfo {
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			logicOpEnable = false,
			logicOp = .COPY,
			attachmentCount = 1,
			pAttachments = &vk.PipelineColorBlendAttachmentState {
					blendEnable = false,
					srcColorBlendFactor = .ONE,
					dstColorBlendFactor = .ZERO,
					colorBlendOp = .ADD,
					srcAlphaBlendFactor = .ONE,
					dstAlphaBlendFactor = .ZERO,
					alphaBlendOp = .ADD,
					colorWriteMask = {.R, .G, .B, .A},
			},
			blendConstants = {0, 0, 0, 0},
		},
		pDynamicState       = &vk.PipelineDynamicStateCreateInfo {
			sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			dynamicStateCount = len(DYNAMIC_VIEWPORT_STATES),
			pDynamicStates = &DYNAMIC_VIEWPORT_STATES[0],
		},
		layout              = 0,
		renderPass          = 0,
		subpass             = 0,
		basePipelineHandle  = 0,
		basePipelineIndex   = 0,
	}

	if res := vk.CreateGraphicsPipelines(
		device,
		pipelineCache,
		1,
		&pipelineInfo,
		nil,
		&pipelines[.Light].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! %v", res)
	}
}

@(private = "file")
createScenePipelineImages :: proc(using graphicsData: ^GraphicsData) {
	err: Error

	err = createImage(
		graphicsData,
		&pipelines[.Scene].images[0],
		{},
		.D2,
		renderSize.x,
		renderSize.y,
		1,
		{._1},
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .TRANSFER_SRC},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		log(.Fatal, "Failed to create colour image!")
	}

	pipelines[.Scene].images[0].view, pipelines[.Scene].images[0].viewInfo, err = createImageView(
		graphicsData,
		pipelines[.Scene].images[0].vkImage,
		.D2,
		pipelines[.Scene].images[0].format,
		{.COLOR},
		1,
	)
	if err != nil {
		log(.Fatal, "Failed to create colour image view!")
	}

	err = createImage(
		graphicsData,
		&pipelines[.Scene].images[1],
		{},
		.D2,
		renderSize.x,
		renderSize.y,
		1,
		{._1},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		log(.Fatal, "Failed to create depth image!")
	}

	pipelines[.Scene].images[1].view, pipelines[.Scene].images[1].viewInfo, err = createImageView(
		graphicsData,
		pipelines[.Scene].images[1].vkImage,
		.D2,
		pipelines[.Scene].images[1].format,
		{.DEPTH},
		1,
	)
	if err != nil {
		log(.Fatal, "Failed to create depth image view!")
	}

	pipelines[.Scene].images[1].sampler = 0

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to start commands! %v", err)
	}

	imageBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = nil,
			dstAccessMask = nil,
			oldLayout = .UNDEFINED,
			newLayout = .TRANSFER_SRC_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Scene].images[0].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = nil,
			dstAccessMask = nil,
			oldLayout = .UNDEFINED,
			newLayout = .SHADER_READ_ONLY_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Scene].images[1].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.DEPTH},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
			},
		},
	}
	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = len(imageBarriers),
			pImageMemoryBarriers = &imageBarriers[0],
		},
	)

	err = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to submit commands! %v", err)
	}
}

@(private = "file")
createScenePipeline :: proc(
	using graphicsData: ^GraphicsData,
	shaders: [][]byte,
) {
	createFlags: vk.PipelineCreateFlags2CreateInfo = {
		sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
		pNext = nil,
		flags = {.DESCRIPTOR_HEAP_EXT},
	}

	shaderStages: [2]vk.PipelineShaderStageCreateInfo = {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
							sType = .SHADER_MODULE_CREATE_INFO,
							pNext = nil,
							flags = nil,
							codeSize = len(shaders[0]),
							pCode = transmute(^u32)raw_data(shaders[0]),
						},
			flags = nil,
			stage = {.VERTEX},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
							sType = .SHADER_MODULE_CREATE_INFO,
							pNext = nil,
							flags = nil,
							codeSize = len(shaders[1]),
							pCode = transmute(^u32)raw_data(shaders[1]),
						},
			flags = nil,
			stage = {.FRAGMENT},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
	}

	renderingInfo: vk.PipelineRenderingCreateInfo = {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		pNext = nil,
		viewMask = 0,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &pipelines[.Scene].images[0].format,
		depthAttachmentFormat = pipelines[.Scene].images[1].format,
		stencilAttachmentFormat = .UNDEFINED,
	}
	createFlags.pNext = &renderingInfo

	pipelineInfo: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &createFlags,
		flags               = nil,
		stageCount          = u32(len(shaderStages)),
		pStages             = &shaderStages[0],
		pVertexInputState   = &{
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			vertexBindingDescriptionCount = 0,
			pVertexBindingDescriptions = nil,
			vertexAttributeDescriptionCount = 0,
			pVertexAttributeDescriptions = nil,
		},
		pInputAssemblyState = &{
			sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			topology = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		},
		pTessellationState  = nil,
		pViewportState      = &{
			sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			viewportCount = 1,
			pViewports = nil,
			scissorCount = 1,
			pScissors = nil,
		},
		pRasterizationState = &{
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			depthClampEnable = false,
			rasterizerDiscardEnable = false,
			polygonMode = .FILL,
			cullMode = {.BACK},
			frontFace = .CLOCKWISE,
			depthBiasEnable = false,
			depthBiasConstantFactor = 0.0,
			depthBiasClamp = 0.0,
			depthBiasSlopeFactor = 0.0,
			lineWidth = 1.0,
		},
		pMultisampleState   = &{
			sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			rasterizationSamples = {._1},
			sampleShadingEnable = false,
			minSampleShading = 1.0,
			pSampleMask = nil,
			alphaToCoverageEnable = false,
			alphaToOneEnable = false,
		},
		pDepthStencilState  = &{
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			depthTestEnable = true,
			depthWriteEnable = true,
			depthCompareOp = .LESS,
			depthBoundsTestEnable = false,
			stencilTestEnable = false,
			front = {},
			back = {},
			minDepthBounds = 0,
			maxDepthBounds = 1,
		},
		pColorBlendState    = &{
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			logicOpEnable = false,
			logicOp = .COPY,
			attachmentCount = 1,
			pAttachments = &vk.PipelineColorBlendAttachmentState {
					blendEnable = false,
					srcColorBlendFactor = .ONE,
					dstColorBlendFactor = .ZERO,
					colorBlendOp = .ADD,
					srcAlphaBlendFactor = .ONE,
					dstAlphaBlendFactor = .ZERO,
					alphaBlendOp = .ADD,
					colorWriteMask = {.R, .G, .B, .A},
			},
			blendConstants = {0, 0, 0, 0},
		},
		pDynamicState       = &vk.PipelineDynamicStateCreateInfo {
			sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			dynamicStateCount = len(DYNAMIC_VIEWPORT_STATES),
			pDynamicStates = &DYNAMIC_VIEWPORT_STATES[0],
		},
		layout              = 0,
		renderPass          = 0,
		subpass             = 0,
		basePipelineHandle  = 0,
		basePipelineIndex   = 0,
	}

	if res := vk.CreateGraphicsPipelines(
		device,
		pipelineCache,
		1,
		&pipelineInfo,
		nil,
		&pipelines[.Scene].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! %v", res)
	}
}

@(private = "file")
createGizmoPipeline :: proc(
	using graphicsData: ^GraphicsData,
	shaders: [][]byte,
) {
	createFlags: vk.PipelineCreateFlags2CreateInfo = {
		sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
		pNext = nil,
		flags = {.DESCRIPTOR_HEAP_EXT},
	}

	shaderStages: [2]vk.PipelineShaderStageCreateInfo = {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
							sType = .SHADER_MODULE_CREATE_INFO,
							pNext = nil,
							flags = nil,
							codeSize = len(shaders[0]),
							pCode = transmute(^u32)raw_data(shaders[0]),
						},
			flags = nil,
			stage = {.VERTEX},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
							sType = .SHADER_MODULE_CREATE_INFO,
							pNext = nil,
							flags = nil,
							codeSize = len(shaders[1]),
							pCode = transmute(^u32)raw_data(shaders[1]),
						},
			flags = nil,
			stage = {.FRAGMENT},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
	}

	renderingInfo: vk.PipelineRenderingCreateInfo = {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		pNext = nil,
		viewMask = 0,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &pipelines[.Scene].images[0].format,
		depthAttachmentFormat = pipelines[.Scene].images[1].format,
		stencilAttachmentFormat = .UNDEFINED,
	}
	createFlags.pNext = &renderingInfo

	pipelineInfo: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &createFlags,
		flags               = nil,
		stageCount          = u32(len(shaderStages)),
		pStages             = &shaderStages[0],
		pVertexInputState   = &{
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			vertexBindingDescriptionCount = 0,
			pVertexBindingDescriptions = nil,
			vertexAttributeDescriptionCount = 0,
			pVertexAttributeDescriptions = nil,
		},
		pInputAssemblyState = &{
			sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			topology = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		},
		pTessellationState  = nil,
		pViewportState      = &{
			sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			viewportCount = 1,
			pViewports = nil,
			scissorCount = 1,
			pScissors = nil,
		},
		pRasterizationState = &{
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			depthClampEnable = false,
			rasterizerDiscardEnable = false,
			polygonMode = .FILL,
			cullMode = nil,
			frontFace = .CLOCKWISE,
			depthBiasEnable = false,
			depthBiasConstantFactor = 0.0,
			depthBiasClamp = 0.0,
			depthBiasSlopeFactor = 0.0,
			lineWidth = 1.0,
		},
		pMultisampleState   = &{
			sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			rasterizationSamples = {._1},
			sampleShadingEnable = false,
			minSampleShading = 1.0,
			pSampleMask = nil,
			alphaToCoverageEnable = false,
			alphaToOneEnable = false,
		},
		pDepthStencilState  = &{
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			depthTestEnable = true,
			depthWriteEnable = false,
			depthCompareOp = .LESS,
			depthBoundsTestEnable = false,
			stencilTestEnable = false,
			front = {},
			back = {},
			minDepthBounds = 0,
			maxDepthBounds = 1,
		},
		pColorBlendState    = &{
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			logicOpEnable = false,
			logicOp = .COPY,
			attachmentCount = 1,
			pAttachments = &vk.PipelineColorBlendAttachmentState {
					blendEnable = true,
					srcColorBlendFactor = .ONE,
					dstColorBlendFactor = .ONE,
					colorBlendOp = .ADD,
					srcAlphaBlendFactor = .ONE,
					dstAlphaBlendFactor = .ONE,
					alphaBlendOp = .ADD,
					colorWriteMask = {.R, .G, .B, .A},
			},
			blendConstants = {0, 0, 0, 0},
		},
		pDynamicState       = &vk.PipelineDynamicStateCreateInfo {
			sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			dynamicStateCount = len(DYNAMIC_VIEWPORT_STATES),
			pDynamicStates = &DYNAMIC_VIEWPORT_STATES[0],
		},
		layout              = 0,
		renderPass          = 0,
		subpass             = 0,
		basePipelineHandle  = 0,
		basePipelineIndex   = 0,
	}

	if res := vk.CreateGraphicsPipelines(
		device,
		pipelineCache,
		1,
		&pipelineInfo,
		nil,
		&pipelines[.Gizmo].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! %v", res)
	}
}

@(private = "file")
createPostProcessPipelineImages :: proc(using graphicsData: ^GraphicsData) {
	err: Error
	err = createImage(
		graphicsData,
		&pipelines[.PostProcess].images[0],
		nil,
		.D2,
		swapchain.extent.width,
		swapchain.extent.height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_DST, .STORAGE},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		logf(.Fatal, "Failed to create image! Error: %v", err)
	}

	pipelines[.PostProcess].images[0].view, pipelines[.PostProcess].images[0].viewInfo, err = createImageView(
		graphicsData,
		pipelines[.PostProcess].images[0].vkImage,
		.D2,
		pipelines[.PostProcess].images[0].format,
		{.COLOR},
		1,
	)
	if err != nil {
		logf(.Fatal, "Failed to create image view for rendered image! Error: %v", err)
	}

	err = createImage(
		graphicsData,
		&pipelines[.PostProcess].images[1],
		nil,
		.D2,
		swapchain.extent.width,
		swapchain.extent.height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_SRC, .COLOR_ATTACHMENT, .STORAGE},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		logf(.Fatal, "Failed to create processed image! Error: %v", err)
	}

	pipelines[.PostProcess].images[1].view, pipelines[.PostProcess].images[1].viewInfo, err = createImageView(
		graphicsData,
		pipelines[.PostProcess].images[1].vkImage,
		.D2,
		pipelines[.PostProcess].images[1].format,
		{.COLOR},
		1,
	)
	if err != nil {
		logf(.Fatal, "Failed to create image view for processed image! Error: %v", err)
	}

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to start commands! %v", err)
	}

	imageBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = nil,
			dstAccessMask = nil,
			oldLayout = .UNDEFINED,
			newLayout = .GENERAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.PostProcess].images[0].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = nil,
			dstAccessMask = nil,
			oldLayout = .UNDEFINED,
			newLayout = .TRANSFER_SRC_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.PostProcess].images[1].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
			},
		},
	}

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = len(imageBarriers),
			pImageMemoryBarriers = &imageBarriers[0],
		},
	)

	err = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to submit commands! %v", err)
	}
}

@(private = "file")
createPostProcessPipeline :: proc(
	using graphicsData: ^GraphicsData,
	shader: []byte,
) {
	err: Error
	createFlags: vk.PipelineCreateFlags2CreateInfo = {
		sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
		pNext = nil,
		flags = {.DESCRIPTOR_HEAP_EXT},
	}

	shaderStage: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = &vk.ShaderModuleCreateInfo {
						sType = .SHADER_MODULE_CREATE_INFO,
						pNext = nil,
						flags = nil,
						codeSize = len(shader),
						pCode = transmute(^u32)raw_data(shader),
				},
		flags               = nil,
		stage               = {.COMPUTE},
		module              = 0,
		pName               = "main",
		pSpecializationInfo = nil,
	}

	pipelineInfo := vk.ComputePipelineCreateInfo {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = &createFlags,
		flags              = nil,
		stage              = shaderStage,
		layout             = 0,
		basePipelineHandle = 0,
		basePipelineIndex  = 0,
	}

	if res := vk.CreateComputePipelines(
		device,
		pipelineCache,
		1,
		&pipelineInfo,
		nil,
		&pipelines[.PostProcess].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! vkResult: %v", res)
	}
}

@(private = "file")
cleanupPipeline :: proc(using graphicsData: ^GraphicsData, pipeline: ^Pipeline) {
	vk.DestroyPipeline(device, pipeline.handle, nil)
}

// It is the callers responsibility to ensure they pass the correct
// number of shaders to satisfy pipeline creation.
// You will crash if you don't.
updatePipelineShaders :: proc(
	using graphicsData: ^GraphicsData,
	pipelineIndex: PipelineIndex,
	shaders: [][]byte,
) {
	vk.DeviceWaitIdle(device)

	cleanupPipeline(graphicsData, &pipelines[pipelineIndex])
	switch pipelineIndex {
	case .Transform:
		createTransformPipeline(graphicsData, shaders[0])
		markCommandsDirty(graphicsData, {.Transform})
	case .Light:
		createLightPipeline(graphicsData, shaders)
		markCommandsDirty(graphicsData, {.Light})
	case .Scene:
		createScenePipeline(graphicsData, shaders)
		markCommandsDirty(graphicsData, {.Scene})
	case .Gizmo:
		createGizmoPipeline(graphicsData, shaders)
		markCommandsDirty(graphicsData, {.Scene})
	case .PostProcess:
		createPostProcessPipeline(graphicsData, shaders[0])
		markCommandsDirty(graphicsData, {.PostProcess})
	}
}


// ===[ Commands and Synchronisation ]=========================================

@(private = "file")
@(require_results)
createCommandBuffers :: proc(using graphicsData: ^GraphicsData) -> CommandBufferError {
	poolInfo: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		pNext            = nil,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queueFamilies.graphicsFamily,
	}
	if res := vk.CreateCommandPool(device, &poolInfo, nil, &graphicsCommandPool); res != .SUCCESS {
		log(.Fatal, "Failed to create command pool! vkResult: %v", res)
		return .FailedToCreateCommandPool
	}

	allocInfo: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[.Light][0],
	); res != .SUCCESS {
		log(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[.Scene][0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[.Imgui][0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	poolInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		pNext            = nil,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queueFamilies.computeFamily,
	}
	if res := vk.CreateCommandPool(device, &poolInfo, nil, &computeCommandPool); res != .SUCCESS {
		logf(.Fatal, "Failed to create command pool! vkResult: %v", res)
		return .FailedToCreateCommandPool
	}

	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = computeCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[.Transform][0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[.PostProcess][0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	return .None
}

@(private = "file")
beginSingleTimeCommands :: proc(
	using graphicsData: ^GraphicsData,
	commandPool: vk.CommandPool,
) -> (
	commandBuffer: vk.CommandBuffer,
	err: CommandBufferError = .None,
) {
	allocInfo: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = commandPool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if res := vk.AllocateCommandBuffers(device, &allocInfo, &commandBuffer); res != .SUCCESS {
		logf(.Error, "Failed to allocate command buffer! vkResult: %v", res)
		err = .FailedToAllocateCommandBuffer
		return
	}

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.ONE_TIME_SUBMIT},
		pInheritanceInfo = nil,
	}
	if res := vk.BeginCommandBuffer(commandBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to begin command buffer! vkResult: %v", res)
		err = .FailedToBeginCommandBuffer
		return
	}

	return
}

@(private = "file")
@(require_results)
endSingleTimeCommands :: proc(
	using graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	commandPool: vk.CommandPool,
) -> CommandBufferError {
	commandBuffer := commandBuffer
	if res := vk.EndCommandBuffer(commandBuffer); res != .SUCCESS {
		logf(.Error, "Failed to end command buffer! vkResult: %v", res)
		return .FailedToEndCommandBuffer
	}

	submitInfo: vk.SubmitInfo2 = {
		sType                  = .SUBMIT_INFO_2,
		pNext                  = nil,
		flags                  = {},
		waitSemaphoreInfoCount = 0,
		pWaitSemaphoreInfos    = nil,
		commandBufferInfoCount = 1,
		pCommandBufferInfos    = &vk.CommandBufferSubmitInfo {
			sType = .COMMAND_BUFFER_SUBMIT_INFO,
			pNext = nil,
			commandBuffer = commandBuffer,
			deviceMask = 0,
		},
		signalSemaphoreInfoCount = 0,
		pSignalSemaphoreInfos    = nil,
	}
	fence: vk.Fence
	fenceCreateInfo: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		pNext = nil,
		flags = {},
	}
	vk.CreateFence(device, &fenceCreateInfo, nil, &fence)

	// A command buffer can only be submitted to the family that owns its pool.
	queue := computeCommandPool == commandPool ? computeQueue : graphicsQueue
	vk.QueueSubmit2(queue, 1, &submitInfo, fence)
	vk.WaitForFences(device, 1, &fence, true, ~u64(0))
	vk.DestroyFence(device, fence, nil)
	vk.FreeCommandBuffers(device, commandPool, 1, &commandBuffer)

	return .None
}

@(private = "file")
@(require_results)
createSyncObjects :: proc(using graphicsData: ^GraphicsData) -> SyncError {
	fenceInfo: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		pNext = nil,
		flags = {.SIGNALED},
	}

	semaphoreInfo: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = nil,
		flags = {},
	}

	presentFenceInfo: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		pNext = nil,
		flags = {},
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if res := vk.CreateFence(device, &fenceInfo, nil, &inFlightFrames[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create fence! vkResult: %d", res)
			return .FailedToCreateFence
		}

		if res := vk.CreateFence(device, &presentFenceInfo, nil, &presentFences[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create present fence! vkResult: %d", res)
			return .FailedToCreateFence
		}

		if res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &presentReady[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create present semaphore! vkResult: %v", res)
			return .FailedToCreateSemaphore
		}

		for semaphoreIndex in SemaphoreIndex {
			if res := vk.CreateSemaphore(
					device,
					&semaphoreInfo,
					nil,
					&semaphores[semaphoreIndex][index],
			); res != .SUCCESS {
					logf(.Fatal, "Failed to create semaphore %v! vkResult: %v", semaphoreIndex, res)
					return .FailedToCreateSemaphore
			}
		}
	}

	return .None
}


// ===[ Scene and Frame Data ]=================================================

updateSceneBuffers :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	err: Error

	buffers := &scene.buffers
	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	deleteBuffer(graphicsData, &buffers.vertexBuffer)
	err = loadBufferToGPU(
		graphicsData,
		size_of(Vertex) * len(scene.vertices),
		raw_data(scene.vertices),
		&buffers.vertexBuffer,
		.VERTEX_BUFFER,
	)
	if err != nil {
		logf(.Fatal, "Failed to load vertex buffer! Error: %v", err)
	}

	deleteBuffer(graphicsData, &buffers.indexBuffer)
	err = loadBufferToGPU(
		graphicsData,
		size_of(u32) * len(scene.indices),
		raw_data(scene.indices),
		&buffers.indexBuffer,
		.INDEX_BUFFER,
	)
	if err != nil {
		logf(.Fatal, "Failed to load index buffer! Error: %v", err)
	}

	stagingWait(graphicsData)

	instanceBufferSize := size_of(InstanceInfo) * len(scene.objects)
	boneBufferSize := size_of(Mat4) * scene.boneCount
	lightBufferSize := size_of(LightData) * len(scene.lights)
	transformBufferSize := size_of(Mat4) * scene.vertexCount
	positionBufferSize := size_of(Vec4) * scene.vertexCount

	textureIndexSize := 0
	for &model in scene.models {
		textureIndexSize += len(model.instances) * len(model.meshes)
	}
	textureIndexSize *= len(TextureIndex) * size_of(u32)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		deleteBuffer(graphicsData, &buffers.instanceBuffers[i])
		err = createBuffer(
			graphicsData,
			instanceBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&buffers.instanceBuffers[i],
		)
		if err != nil {
			logf(.Fatal, "Failed to create instance buffer! Error: %v", err)
		}

		deleteBuffer(graphicsData, &buffers.boneBuffers[i])
		err = createBuffer(
			graphicsData,
			boneBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&buffers.boneBuffers[i],
		)
		if err != nil {
			logf(.Fatal, "Failed to create bone buffer! Error: %v", err)
		}

		deleteBuffer(graphicsData, &buffers.lightBuffers[i])
		err = createBuffer(
			graphicsData,
			lightBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&buffers.lightBuffers[i],
		)
		if err != nil {
			logf(.Fatal, "Failed to create light buffer! Error: %v", err)
		}

		deleteBuffer(graphicsData, &buffers.transformBuffers[i])
		err = createBuffer(
			graphicsData,
			int(transformBufferSize),
			{.STORAGE_BUFFER},
			{.DEVICE_LOCAL},
			&buffers.transformBuffers[i],
		)
		if err != nil {
			logf(.Fatal, "Failed to create transform buffer! Error: %v", err)
		}

		deleteBuffer(graphicsData, &buffers.positionBuffers[i])
		err = createBuffer(
			graphicsData,
			int(positionBufferSize),
			{.STORAGE_BUFFER},
			{.DEVICE_LOCAL},
			&buffers.positionBuffers[i],
		)
		if err != nil {
			logf(.Fatal, "Failed to create position buffer! Error: %v", err)
		}
	}

	deleteBuffer(graphicsData, &buffers.textureIndexBuffer)
	err = createBuffer(
		graphicsData,
		textureIndexSize,
		{.STORAGE_BUFFER},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&buffers.textureIndexBuffer,
	)
	if err != nil {
		logf(.Fatal, "Failed to create transform buffer! Error: %v", err)
	}
	updateTextureIndexBuffer(graphicsData, scene)

	destroyShadowFaceViews(graphicsData)
	deleteImage(graphicsData, &pipelines[.Light].images[0])
	deleteImage(graphicsData, &pipelines[.Light].images[1])
	createLightPipelineImages(graphicsData, scene)

	updateDescriptorSets(graphicsData, scene)
	markCommandsDirty(graphicsData, DIRTY_ALL)
	updateCommandBuffers(graphicsData, scene)
}

@(private = "file")
updateLightBuffer :: proc(using graphicsData: ^GraphicsData, scene: ^Scene, delta: f32) {
	buffers := &scene.buffers
	lightData := make([]LightData, len(scene.lights), allocator = context.temp_allocator)
	for &light, i in scene.lights {
		lightData[i] = {
			position = light.position,
			lumens   = light.colour * light.lumens,
			near     = 0.01,
			far      = 1000.0,
		}
	}

	mem.copy(
		buffers.lightBuffers[currentFrame].mapped,
		raw_data(lightData),
		size_of(LightData) * len(scene.lights),
	)
}

@(private = "file")
updateUniformBuffer :: proc(
	using graphicsData: ^GraphicsData,
	scene: ^Scene,
	view, projection: Mat4,
) {
	viewProjection: UniformBuffer = {
		projection     = projection,
		viewProjection = projection * view,
		lightCount     = u32(len(scene.lights)),
		ambientLight   = scene.ambientLight,
		cameraPosition = scene.cameras[scene.activeCamera].eye,
	}
	mem.copy(uniformBuffers[currentFrame].mapped, &viewProjection, size_of(UniformBuffer))
}

@(private = "file")
updateInstanceBuffer :: proc(graphicsData: ^GraphicsData, scene: ^Scene, delta: f32) {
	boneTransforms := make([]Mat4, scene.boneCount, allocator = context.temp_allocator)
	instanceData := make([]InstanceInfo, len(scene.objects), allocator = context.temp_allocator)

	boneTransforms[0] = IMAT4
	boneOffset: u32 = 1
	instanceIdx := 0
	for &model in scene.models {
		for &objectIdx in model.instances {
			defer instanceIdx += 1
			value := objectIdx
			object := &scene.objects[objectIdx]

			modelTransform: Mat4 = ---
			if object.attachment.targetIdx >= 0 {
					attachmentObject := &scene.objects[object.attachment.targetIdx]
					attachmentModel := &scene.models[attachmentObject.modelIdx]
					bindpoint := &attachmentModel.bindpoints[object.attachment.bindpointIdx]

					modelTransform =
						transform(
							attachmentObject.position + attachmentModel.position,
							attachmentObject.rotation * attachmentModel.rotation,
							attachmentObject.scale * attachmentModel.scale,
						) *
						attachmentObject.animation.state[bindpoint.boneIdx] *
						transform(
							object.position + model.position,
							object.rotation * model.rotation,
							object.scale * model.scale,
						)
			} else {
					modelTransform = transform(
						object.position + model.position,
						object.rotation * model.rotation,
						object.scale * model.scale,
					)
			}

			instanceData[instanceIdx] = {
					modelTransform = modelTransform,
					boneOffset     = boneOffset,
			}

			if len(model.skeleton) == 0 {
					instanceData[instanceIdx].boneOffset = 0
					continue
			}

			for &transform, idx in object.animation.state {
					boneTransforms[boneOffset + u32(idx)] =
						transform * model.skeleton[idx].offsetMatrix
			}
			boneOffset += u32(len(model.skeleton))
		}
	}

	mem.copy(
		scene.buffers.boneBuffers[graphicsData.currentFrame].mapped,
		raw_data(boneTransforms),
		scene.boneCount * size_of(Mat4),
	)
	mem.copy(
		scene.buffers.instanceBuffers[graphicsData.currentFrame].mapped,
		raw_data(instanceData),
		len(scene.objects) * size_of(InstanceInfo),
	)
}

@(private = "file")
updateTextureIndexBuffer :: proc(graphicsData: ^GraphicsData, scene: ^Scene) {
	textureIndicesLength := 0
	for &model in scene.models {
		textureIndicesLength += len(model.instances) * len(model.meshes)
	}
	textureIndicesLength *= len(TextureIndex)
	textureIndices := make([]u32, textureIndicesLength, allocator = context.temp_allocator)

	idx := 0
	for &model in scene.models {
		for &mesh, meshIdx in model.meshes {
			for &objectIdx in model.instances {
					object := &scene.objects[objectIdx]
					for val in TextureIndex {
						textureIdx := int(object.textureIdxs[meshIdx][val])
						if textureIdx < len(scene.buffers.textures) {
							textureIndices[idx + int(val)] = textureSlotIndex(
								graphicsData,
								scene.buffers.textures[textureIdx].heapSlot,
							)
						}
					}
					idx += len(TextureIndex)
			}
		}
	}

	mem.copy(
		scene.buffers.textureIndexBuffer.mapped,
		raw_data(textureIndices),
		textureIndicesLength * size_of(u32),
	)
}

updateSceneData :: proc(
	graphicsData: ^GraphicsData,
	scene: ^Scene,
	view, projection: Mat4,
	delta: f32,
) {
	if graphicsData.reloadBuffers {
		updateSceneBuffers(graphicsData, scene)
		graphicsData.reloadBuffers = false
	} else {
		updateCommandBuffers(graphicsData, scene)
	}

	updateUniformBuffer(graphicsData, scene, view, projection)
	updateLightBuffer(graphicsData, scene, delta)
	updateInstanceBuffer(graphicsData, scene, delta)
}


// ===[ Command Recording ]====================================================

DIRTY_ALL: bit_set[CmdBufferIndex] : {.Transform, .Light, .Scene, .PostProcess}

DIRTY_GEOMETRY: bit_set[CmdBufferIndex] : {.Transform, .Light, .Scene}

markCommandsDirty :: proc(graphicsData: ^GraphicsData, passes: bit_set[CmdBufferIndex]) {
	graphicsData.dirtyCommands += passes
}

@(private = "file")
updateCommandBuffers :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	if dirtyCommands == nil {
		return
	}
	defer dirtyCommands = nil

	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		logf(.Error, "Failed to wait for device idle! vkResult: %v", res)
		panic("Idk why this would ever fail.")
	}

	for bufferIndex in 0 ..< MAX_FRAMES_IN_FLIGHT {
		for pass in dirtyCommands {
			vk.ResetCommandBuffer(commandBuffers[pass][bufferIndex], nil)

			switch pass {
			case .Transform:
					recordTransformCommands(graphicsData, bufferIndex, scene)
			case .Light:
					recordLightCommands(graphicsData, bufferIndex, scene)
			case .Scene:
					recordSceneCommands(graphicsData, bufferIndex, scene)
			case .PostProcess:
					recordPostProcessCommands(graphicsData, bufferIndex)
			case .Imgui:
			}
		}
	}
}

@(private = "file")
recordTransformCommands :: proc(using graphicsData: ^GraphicsData, index: u32, scene: ^Scene) {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}
	cmdBuffer := commandBuffers[.Transform][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
	}

	vkBeginLabel(cmdBuffer, "Transform", {0.4, 0.8, 0.4, 1})

	bindDescriptorHeaps(graphicsData, cmdBuffer, index)
	vk.CmdBindPipeline(cmdBuffer, .COMPUTE, pipelines[.Transform].handle)

	pushConstants: Transform_PushConstants = {
		resources = heapIndices,
		instance        = 0,
		instanceCount   = 0,
		vertexCount     = 0,
		vertexOffset    = 0,
		transformOffset = 0,
	}
	for &model in scene.models {
		OFFSET :: u32(offset_of(Transform_PushConstants, instanceCount))

		vk.CmdPushDataEXT(
			cmdBuffer,
			&vk.PushDataInfoEXT {
					sType = .PUSH_DATA_INFO_EXT,
					pNext = nil,
					offset = 0,
					data = {address = &pushConstants, size = int(OFFSET)},
			},
			)
		for &mesh in model.meshes {
			pushConstants.instanceCount = u32(len(model.instances))
			pushConstants.vertexCount = mesh.vertexCount
			pushConstants.vertexOffset = mesh.vertexOffset

			vk.CmdPushDataEXT(
					cmdBuffer,
					&vk.PushDataInfoEXT {
						sType = .PUSH_DATA_INFO_EXT,
						pNext = nil,
						offset = OFFSET,
						data = {address = &pushConstants.instanceCount, size = int(size_of(Transform_PushConstants) - OFFSET)},
					},
					)
			vk.CmdDispatch(cmdBuffer, u32(ceil(f32(mesh.vertexCount) / 64.0)), 1, 1)
			pushConstants.transformOffset += mesh.vertexCount * u32(len(model.instances))
		}
		pushConstants.instance += u32(len(model.instances))
	}

	vkEndLabel(cmdBuffer)

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Fatal, "Failed to record command buffer! vkResult: %v", res)
	}
}

@(private = "file")
recordLightCommands :: proc(using graphicsData: ^GraphicsData, index: u32, scene: ^Scene) {
	lightCount := u32(len(scene.lights))
	lightImageCount := lightCount * SHADOW_CUBE_FACES

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = nil,
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[.Light][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
	}

	vkBeginLabel(cmdBuffer, "Shadow Maps", {0.9, 0.8, 0.3, 1})

	setViewportAndScissor(cmdBuffer, SHADOW_RESOLUTION)
	bindDescriptorHeaps(graphicsData, cmdBuffer, index)

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &vk.ImageMemoryBarrier2 {
					sType = .IMAGE_MEMORY_BARRIER_2,
					pNext = nil,
					srcStageMask = {.FRAGMENT_SHADER},
					srcAccessMask = {.SHADER_SAMPLED_READ},
					dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
					dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
					oldLayout = .SHADER_READ_ONLY_OPTIMAL,
					newLayout = .COLOR_ATTACHMENT_OPTIMAL,
					srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					image = pipelines[.Light].images[0].vkImage,
					subresourceRange = vk.ImageSubresourceRange {
						aspectMask = {.COLOR},
						baseMipLevel = 0,
						levelCount = 1,
						baseArrayLayer = 0,
						layerCount = lightImageCount,
					},
			},
		},
	)

	vk.CmdBindIndexBuffer2(
		cmdBuffer,
		scene.buffers.indexBuffer.buffer,
		0,
		vk.DeviceSize(vk.WHOLE_SIZE),
		.UINT32,
	)

	pushConstants: Light_PushConstants = {
		resources = heapIndices,
		lightIndex   = 0,
		vertexOffset = 0,
		vertexCount  = 0,
	}
	for lightIndex: u32 = 0; lightIndex < lightCount; lightIndex += 1 {
		OFFSET :: u32(offset_of(Light_PushConstants, vertexOffset))

		vk.CmdBeginRendering(
			cmdBuffer,
			&vk.RenderingInfo {
					sType = .RENDERING_INFO,
					pNext = nil,
					flags = nil,
					renderArea = vk.Rect2D {
						offset = {0, 0},
						extent = {SHADOW_RESOLUTION.x, SHADOW_RESOLUTION.y},
					},
					layerCount = 1,
					viewMask = SHADOW_VIEW_MASK,
					colorAttachmentCount = 1,
					pColorAttachments = &vk.RenderingAttachmentInfo {
						sType = .RENDERING_ATTACHMENT_INFO,
						pNext = nil,
						imageView = shadowColourViews[lightIndex],
						imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
						resolveMode = nil,
						resolveImageView = 0,
						resolveImageLayout = .UNDEFINED,
						loadOp = .CLEAR,
						storeOp = .STORE,
						clearValue = {color = {float32 = {0, 0, 0, 1}}},
					},
					pDepthAttachment = &vk.RenderingAttachmentInfo {
						sType = .RENDERING_ATTACHMENT_INFO,
						pNext = nil,
						imageView = shadowDepthViews[lightIndex],
						imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
						resolveMode = nil,
						resolveImageView = 0,
						resolveImageLayout = .UNDEFINED,
						loadOp = .CLEAR,
						storeOp = .STORE,
						clearValue = {depthStencil = {depth = 1, stencil = 0}},
					},
					pStencilAttachment = nil,
			},
		)

		vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[.Light].handle)

		pushConstants.lightIndex = lightIndex
		vk.CmdPushDataEXT(
			cmdBuffer,
			&vk.PushDataInfoEXT {
					sType = .PUSH_DATA_INFO_EXT,
					pNext = nil,
					offset = 0,
					data = {address = &pushConstants, size = int(OFFSET)},
			},
			)

		pushConstants.vertexOffset = 0
		for &model in scene.models {
			for &mesh in model.meshes {
					pushConstants.vertexCount = mesh.vertexCount
					vk.CmdPushDataEXT(
						cmdBuffer,
						&vk.PushDataInfoEXT {
							sType = .PUSH_DATA_INFO_EXT,
							pNext = nil,
							offset = OFFSET,
							data = {
								address = &pushConstants.vertexOffset,
								size = int(size_of(Light_PushConstants) - OFFSET),
							},
						},
					)

				vk.CmdDrawIndexed(
					cmdBuffer,
					mesh.indexCount,
					u32(len(model.instances)),
					mesh.indexOffset,
					i32(mesh.vertexOffset),
					0,
				)
				pushConstants.vertexOffset += mesh.vertexCount * u32(len(model.instances))
			}
		}

		vk.CmdEndRendering(cmdBuffer)
	}

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &vk.ImageMemoryBarrier2 {
				sType = .IMAGE_MEMORY_BARRIER_2,
				pNext = nil,
				srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
				srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
				dstStageMask = {.FRAGMENT_SHADER},
				dstAccessMask = {.SHADER_SAMPLED_READ},
				oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
				newLayout = .SHADER_READ_ONLY_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = pipelines[.Light].images[0].vkImage,
				subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = lightImageCount,
				},
			},
		},
	)

	vkEndLabel(cmdBuffer)

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Fatal, "Failed to record command buffer! vkResult: %v", res)
	}
}

@(private = "file")
recordSceneCommands :: proc(using graphicsData: ^GraphicsData, index: u32, scene: ^Scene) {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = nil,
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[.Scene][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
	}

	vkBeginLabel(cmdBuffer, "Scene", {0.4, 0.6, 0.9, 1})

	setViewportAndScissor(cmdBuffer, renderSize)

	entryBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.BLIT},
			srcAccessMask = {.TRANSFER_READ},
			dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
			oldLayout = .TRANSFER_SRC_OPTIMAL,
			newLayout = .COLOR_ATTACHMENT_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Scene].images[0].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			// Sampled as the depth source by the post-process pass last frame.
			srcStageMask = {.FRAGMENT_SHADER, .COMPUTE_SHADER},
			srcAccessMask = {.SHADER_SAMPLED_READ},
			dstStageMask = {.EARLY_FRAGMENT_TESTS},
			dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
			oldLayout = .SHADER_READ_ONLY_OPTIMAL,
			newLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Scene].images[1].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.DEPTH},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
	}

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = len(entryBarriers),
			pImageMemoryBarriers = &entryBarriers[0],
		},
	)

	vk.CmdBeginRendering(
		cmdBuffer,
		&vk.RenderingInfo {
			sType = .RENDERING_INFO,
			pNext = nil,
			flags = nil,
			renderArea = vk.Rect2D{offset = {0, 0}, extent = {renderSize.x, renderSize.y}},
			layerCount = 1,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachments = &vk.RenderingAttachmentInfo {
				sType = .RENDERING_ATTACHMENT_INFO,
				pNext = nil,
				imageView = pipelines[.Scene].images[0].view,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				resolveMode = nil,
				resolveImageView = 0,
				resolveImageLayout = .UNDEFINED,
				loadOp = .CLEAR,
				storeOp = .STORE,
				clearValue = {color = {float32 = scene.clearColour}},
			},
			pDepthAttachment = &vk.RenderingAttachmentInfo {
				sType = .RENDERING_ATTACHMENT_INFO,
				pNext = nil,
				imageView = pipelines[.Scene].images[1].view,
				imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				resolveMode = nil,
				resolveImageView = 0,
				resolveImageLayout = .UNDEFINED,
				loadOp = .CLEAR,
				storeOp = .STORE,
				clearValue = {depthStencil = {depth = 1, stencil = 0}},
			},
			pStencilAttachment = nil,
		},
	)

	bindDescriptorHeaps(graphicsData, cmdBuffer, index)
	vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[.Scene].handle)

	vk.CmdBindIndexBuffer2(
		cmdBuffer,
		scene.buffers.indexBuffer.buffer,
		0,
		vk.DeviceSize(vk.WHOLE_SIZE),
		.UINT32,
	)

	pushConstants: Scene_PushConstants = {
		resources = heapIndices,
		vertexOffset   = 0,
		vertexCount    = 0,
		instanceOffset = 0,
	}
	for &model in scene.models {
		for &mesh in model.meshes {
			pushConstants.vertexCount = mesh.vertexCount
			vk.CmdPushDataEXT(
				cmdBuffer,
				&vk.PushDataInfoEXT {
					sType = .PUSH_DATA_INFO_EXT,
					pNext = nil,
					offset = 0,
					data = {address = &pushConstants, size = int(size_of(Scene_PushConstants))},
				},
				)

			vk.CmdDrawIndexed(
				cmdBuffer,
				mesh.indexCount,
				u32(len(model.instances)),
				mesh.indexOffset,
				i32(mesh.vertexOffset),
				0,
			)
			pushConstants.vertexOffset += mesh.vertexCount * u32(len(model.instances))
			pushConstants.instanceOffset += u32(len(model.instances))
		}
	}

	if showLightGizmos && len(scene.lights) > 0 {
		vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[.Gizmo].handle)

		gizmoConstants: Gizmo_PushConstants = {
			resources = heapIndices,
			radius    = lightGizmoRadius,
		}
		vk.CmdPushDataEXT(
			cmdBuffer,
			&vk.PushDataInfoEXT {
				sType = .PUSH_DATA_INFO_EXT,
				pNext = nil,
				offset = 0,
				data = {address = &gizmoConstants, size = size_of(Gizmo_PushConstants)},
			},
		)

		vk.CmdDraw(cmdBuffer, 6, u32(len(scene.lights)), 0, 0)
	}

	vk.CmdEndRendering(cmdBuffer)

	exitBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
			dstStageMask = {.BLIT},
			dstAccessMask = {.TRANSFER_READ},
			oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
			newLayout = .TRANSFER_SRC_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Scene].images[0].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.LATE_FRAGMENT_TESTS},
			srcAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
			dstStageMask = {.FRAGMENT_SHADER, .COMPUTE_SHADER},
			dstAccessMask = {.SHADER_SAMPLED_READ},
			oldLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			newLayout = .SHADER_READ_ONLY_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.Scene].images[1].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.DEPTH},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
	}

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = len(exitBarriers),
			pImageMemoryBarriers = &exitBarriers[0],
		},
	)

	vkEndLabel(cmdBuffer)

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Fatal, "Failed to record command buffer! vkResult: %v", res)
	}
}

@(private = "file")
recordPostProcessCommands :: proc(using graphicsData: ^GraphicsData, index: u32) {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[.PostProcess][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to start recording compute commands! vkResult: %v", res)
	}

	vkBeginLabel(cmdBuffer, "Post Process", {0.8, 0.4, 0.8, 1})

	contentOffset, contentExtent := letterboxRect(renderSize, swapchain.extent)

	imageBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.COMPUTE_SHADER},
			srcAccessMask = {.SHADER_STORAGE_READ, .SHADER_SAMPLED_READ},
			dstStageMask = {.BLIT},
			dstAccessMask = {.TRANSFER_WRITE},
			oldLayout = .GENERAL,
			newLayout = .TRANSFER_DST_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.PostProcess].images[0].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.BLIT},
			srcAccessMask = {.TRANSFER_READ},
			dstStageMask = {.COMPUTE_SHADER},
			dstAccessMask = {.SHADER_STORAGE_WRITE},
			oldLayout = .TRANSFER_SRC_OPTIMAL,
			newLayout = .GENERAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.PostProcess].images[1].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
	}

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = len(imageBarriers),
			pImageMemoryBarriers = &imageBarriers[0],
		},
	)

	upscaleImage(
		cmdBuffer,
		pipelines[.Scene].images[0].vkImage,
		pipelines[.PostProcess].images[0].vkImage,
		{renderSize.x, renderSize.y},
		contentExtent,
		contentOffset,
		0,
		0,
	)

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &vk.ImageMemoryBarrier2 {
				sType = .IMAGE_MEMORY_BARRIER_2,
				pNext = nil,
				srcStageMask = {.BLIT},
				srcAccessMask = {.TRANSFER_WRITE},
				dstStageMask = {.COMPUTE_SHADER},
				dstAccessMask = {.SHADER_STORAGE_READ},
				oldLayout = .TRANSFER_DST_OPTIMAL,
				newLayout = .GENERAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = pipelines[.PostProcess].images[0].vkImage,
				subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
			},
		},
	)

	bindDescriptorHeaps(graphicsData, cmdBuffer, index)

	pushConstants: PostProcess_PushConstants = {
		resources = heapIndices,
		contrast   = contrast,
		brightness = brightness,
		saturation = saturation,
		exposure   = pow(f32(2.0), exposure),
		tonemapper = tonemapper,
		gamma      = gamma,
		contentOffsetX = u32(contentOffset.x),
		contentOffsetY = u32(contentOffset.y),
		contentExtentX = contentExtent.width,
		contentExtentY = contentExtent.height,
		transferFunction = .PQ if swapchain.hdr else .Gamma,
		paperWhiteNits = paperWhiteNits,
	}
	vk.CmdPushDataEXT(
		cmdBuffer,
		&vk.PushDataInfoEXT {
			sType = .PUSH_DATA_INFO_EXT,
			pNext = nil,
			offset = 0,
			data = {address = &pushConstants, size = int(size_of(PostProcess_PushConstants))},
		},
		)

	vk.CmdBindPipeline(cmdBuffer, .COMPUTE, pipelines[.PostProcess].handle)

	vk.CmdDispatch(
		cmdBuffer,
		u32(ceil(f32(swapchain.extent.width) / 32)),
		u32(ceil(f32(swapchain.extent.height) / 32)),
		1,
	)

	vkEndLabel(cmdBuffer)

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Fatal, "Failed to record compute command buffer! vkResult: %v", res)
	}
}

@(private = "file")
recordImguiCommands :: proc(using graphicsData: ^GraphicsData, index: u32, imageIndex: u32) {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = nil,
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[.Imgui][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
	}

	vkBeginLabel(cmdBuffer, "Imgui", {0.7, 0.7, 0.7, 1})

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &vk.ImageMemoryBarrier2 {
				sType = .IMAGE_MEMORY_BARRIER_2,
				pNext = nil,
				srcStageMask = {.COMPUTE_SHADER},
				srcAccessMask = {.SHADER_STORAGE_WRITE},
				dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
				dstAccessMask = {.COLOR_ATTACHMENT_READ},
				oldLayout = .GENERAL,
				newLayout = .COLOR_ATTACHMENT_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = pipelines[.PostProcess].images[1].vkImage,
				subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
			},
		},
	)

	vk.CmdBeginRendering(
		cmdBuffer,
		&vk.RenderingInfo {
			sType = .RENDERING_INFO,
			pNext = nil,
			flags = nil,
			renderArea = vk.Rect2D {
				offset = {0, 0},
				extent = {swapchain.extent.width, swapchain.extent.height},
			},
			layerCount = 1,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachments = &vk.RenderingAttachmentInfo {
				sType = .RENDERING_ATTACHMENT_INFO,
				pNext = nil,
				imageView = pipelines[.PostProcess].images[1].view,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				resolveMode = nil,
				resolveImageView = 0,
				resolveImageLayout = .UNDEFINED,
				loadOp = .LOAD,
				storeOp = .STORE,
				clearValue = {color = {float32 = {0, 0, 0, 1}}},
			},
			pDepthAttachment = nil,
			pStencilAttachment = nil,
		},
	)
	imgui.Render()
	imguiVulkan.RenderDrawData(imgui.GetDrawData(), cmdBuffer)
	vk.CmdEndRendering(cmdBuffer)

	imageBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
			dstStageMask = {.BLIT},
			dstAccessMask = {.TRANSFER_READ},
			oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
			newLayout = .TRANSFER_SRC_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[.PostProcess].images[1].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.BLIT},
			srcAccessMask = {.TRANSFER_READ},
			dstStageMask = {.BLIT},
			dstAccessMask = {.TRANSFER_WRITE},
			oldLayout = .UNDEFINED,
			newLayout = .TRANSFER_DST_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = swapchain.images[imageIndex],
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		},
	}

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = len(imageBarriers),
			pImageMemoryBarriers = &imageBarriers[0],
		},
	)

	vk.CmdBlitImage2(
		cmdBuffer,
		&vk.BlitImageInfo2 {
			sType = .BLIT_IMAGE_INFO_2,
			pNext = nil,
			srcImage = pipelines[.PostProcess].images[1].vkImage,
			srcImageLayout = .TRANSFER_SRC_OPTIMAL,
			dstImage = swapchain.images[imageIndex],
			dstImageLayout = .TRANSFER_DST_OPTIMAL,
			regionCount = 1,
			pRegions = &vk.ImageBlit2 {
				sType = .IMAGE_BLIT_2,
				pNext = nil,
				srcSubresource = {
					aspectMask = {.COLOR},
					mipLevel = 0,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				srcOffsets = {
					{x = 0, y = 0, z = 0},
					{x = i32(swapchain.extent.width), y = i32(swapchain.extent.height), z = 1},
				},
				dstSubresource = {
					aspectMask = {.COLOR},
					mipLevel = 0,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				dstOffsets = {
					{x = 0, y = 0, z = 0},
					{x = i32(swapchain.extent.width), y = i32(swapchain.extent.height), z = 1},
				},
			},
			filter = .NEAREST,
		},
	)

	vk.CmdPipelineBarrier2(
		cmdBuffer,
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = nil,
			memoryBarrierCount = 0,
			pMemoryBarriers = nil,
			bufferMemoryBarrierCount = 0,
			pBufferMemoryBarriers = nil,
			imageMemoryBarrierCount = 1,
			pImageMemoryBarriers = &vk.ImageMemoryBarrier2 {
				sType = .IMAGE_MEMORY_BARRIER_2,
				pNext = nil,
				srcStageMask = {.BLIT},
				srcAccessMask = {.TRANSFER_WRITE},
				dstStageMask = {},
				dstAccessMask = nil,
				oldLayout = .TRANSFER_DST_OPTIMAL,
				newLayout = .PRESENT_SRC_KHR,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = swapchain.images[imageIndex],
				subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
			},
		},
	)

	vkEndLabel(cmdBuffer)

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Fatal, "Failed to record ui command buffer! vkResult: %v", res)
	}
}


// ===[ Frame Submission ]=====================================================

@(require_results)
drawFrame :: proc(using graphicsData: ^GraphicsData) -> (err: DrawError) {
	if swapchainDirty {
		swapchainDirty = false
		recreateSwapchain(graphicsData)
		applyHDRGrading(graphicsData)
		return .UpdateCommandBuffers
	}

	vk.WaitForFences(device, 1, &inFlightFrames[currentFrame], true, max(u64))
	waitForPresent(graphicsData, currentFrame)

	imageIndex: u32
	if res := vk.AcquireNextImageKHR(
		device,
		swapchain.handle,
		max(u64),
		semaphores[.Image][currentFrame],
		{},
		&imageIndex,
	); res == .ERROR_OUT_OF_DATE_KHR {
		recreateSwapchain(graphicsData)
		return .UpdateCommandBuffers
	} else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
		logf(.Error, "Failed to aquire swapchain image! vkResult: %v", res)
		return .FailedToAcquireSwapchainImage
	}
	vk.ResetFences(device, 1, &inFlightFrames[currentFrame])

	imguiVulkan.NewFrame()
	imguiGLFW.NewFrame()
	imgui.NewFrame()

	drawImgui(graphicsData)

	imgui.EndFrame()

	vk.ResetCommandBuffer(commandBuffers[.Imgui][currentFrame], {})
	recordImguiCommands(graphicsData, currentFrame, imageIndex)

	submitInfo: vk.SubmitInfo2 = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		waitSemaphoreInfoCount   = 0,
		pWaitSemaphoreInfos      = nil,
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = raw_data(
			[]vk.CommandBufferSubmitInfo {
				{
					sType = .COMMAND_BUFFER_SUBMIT_INFO,
					pNext = nil,
					commandBuffer = commandBuffers[.Transform][currentFrame],
					deviceMask = 0,
				},
			},
		),
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = semaphores[.Transform][currentFrame],
					value = 0,
					stageMask = {.ALL_COMMANDS},
					deviceIndex = 0,
				},
			},
		),
	}
	if res := vk.QueueSubmit2(computeQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Fatal, "Failed to submit command buffer! vkResult: %v", res)
		return .FailedToSubmitPreCommandBuffer
	}

	graphicsCommandBuffers := [?]vk.CommandBufferSubmitInfo {
		{
			sType = .COMMAND_BUFFER_SUBMIT_INFO,
			pNext = nil,
			commandBuffer = commandBuffers[.Light][currentFrame],
			deviceMask = 0,
		},
		{
			sType = .COMMAND_BUFFER_SUBMIT_INFO,
			pNext = nil,
			commandBuffer = commandBuffers[.Scene][currentFrame],
			deviceMask = 0,
		},
		{
			sType = .COMMAND_BUFFER_SUBMIT_INFO,
			pNext = nil,
			commandBuffer = commandBuffers[.PostProcess][currentFrame],
			deviceMask = 0,
		},
		{
			sType = .COMMAND_BUFFER_SUBMIT_INFO,
			pNext = nil,
			commandBuffer = commandBuffers[.Imgui][currentFrame],
			deviceMask = 0,
		},
	}

	graphicsWaits := [?]vk.SemaphoreSubmitInfo {
		{
			sType = .SEMAPHORE_SUBMIT_INFO,
			pNext = nil,
			semaphore = semaphores[.Transform][currentFrame],
			value = 0,
			stageMask = {.ALL_COMMANDS},
			deviceIndex = 0,
		},
		{
			sType = .SEMAPHORE_SUBMIT_INFO,
			pNext = nil,
			semaphore = semaphores[.Image][currentFrame],
			value = 0,
			stageMask = {.BLIT},
			deviceIndex = 0,
		},
	}

	submitInfo = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		waitSemaphoreInfoCount   = len(graphicsWaits),
		pWaitSemaphoreInfos      = &graphicsWaits[0],
		commandBufferInfoCount   = len(graphicsCommandBuffers),
		pCommandBufferInfos      = &graphicsCommandBuffers[0],
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = presentReady[currentFrame],
					value = 0,
					stageMask = {.ALL_COMMANDS},
					deviceIndex = 0,
				},
			},
		),
	}
	if res := vk.QueueSubmit2(graphicsQueue, 1, &submitInfo, inFlightFrames[currentFrame]);
	   res != .SUCCESS {
		logf(.Fatal, "Failed to submit graphics command buffers! vkResult: %v", res)
		return .FailedToSubmitMainCommandBuffer
	}

	vk.ResetFences(device, 1, &presentFences[currentFrame])
	presentFenceInfo: vk.SwapchainPresentFenceInfoKHR = {
		sType          = .SWAPCHAIN_PRESENT_FENCE_INFO_KHR,
		pNext          = nil,
		swapchainCount = 1,
		pFences        = &presentFences[currentFrame],
	}
	presentInfo: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		pNext              = &presentFenceInfo,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &presentReady[currentFrame],
		swapchainCount     = 1,
		pSwapchains        = &swapchain.handle,
		pImageIndices      = &imageIndex,
		pResults           = nil,
	}

	presentResult := vk.QueuePresentKHR(presentQueue, &presentInfo)
	if presentResult == .SUCCESS || presentResult == .SUBOPTIMAL_KHR {
		presentPending[currentFrame] = true
	}

	#partial switch presentResult {
	case .SUCCESS:
		break
	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		recreateSwapchain(graphicsData)
		return .UpdateCommandBuffers
	case:
		logf(.Error, "Failed to present swapchain image! vkResult: %v", presentResult)
		return .FailedToPresentSwapchainImage
	}

	currentFrame = (currentFrame + 1) % 2
	return nil
}


// ===[ Dear ImGui ]===========================================================

@(private = "file")
initImgui :: proc(using graphicsData: ^GraphicsData) {
	if !imgui.CHECKVERSION() {
		log(.Fatal, "Wrong imgui version!")
	}

	imguiContext = imgui.CreateContext()
	io := imgui.GetIO()
	imgui.StyleColorsClassic()

	imguiVulkan.LoadFunctions(
		vk.API_VERSION_1_4,
		proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr(transmute(vk.Instance)user_data, function_name)
		},
		instance,
	)

	if !imguiGLFW.InitForVulkan(window, true) {
		log(.Fatal, "Failed to initialize imgui for vulkan.")
	}

	implInitInfo: imguiVulkan.InitInfo = {
		ApiVersion = vk.API_VERSION_1_4, // Fill with API version of Instance, e.g. VK_API_VERSION_1_3 or your value of VkApplicationInfo::apiVersion. May be lower than header version (VK_HEADER_VERSION_COMPLETE)
		Instance = instance,
		PhysicalDevice = physicalDevice,
		Device = device,
		QueueFamily = queueFamilies.graphicsFamily,
		Queue = graphicsQueue,
		DescriptorPool = 0,
		DescriptorPoolSize = 10,
		MinImageCount = 2,
		ImageCount = 2,
		PipelineCache = 0,

		// Pipeline
		PipelineInfoMain = {
			RenderPass = 0,
			Subpass = 0,
			MSAASamples = {._1},
			PipelineRenderingCreateInfo = {
				sType = .PIPELINE_RENDERING_CREATE_INFO,
				pNext = nil,
				viewMask = 0,
				colorAttachmentCount = 1,
				pColorAttachmentFormats = &pipelines[.PostProcess].images[1].format,
				depthAttachmentFormat = .UNDEFINED,
				stencilAttachmentFormat = .UNDEFINED,
			},
			SwapChainImageUsage = nil,
		},
		PipelineInfoForViewports = {
			RenderPass = 0,
			Subpass = 0,
			MSAASamples = {._1},
			PipelineRenderingCreateInfo = {},
			SwapChainImageUsage = nil,
		},
		UseDynamicRendering = true,

		// (Optional) Allocation, Debugging
		Allocator = {},
		CheckVkResultFn = imguiCheckVkResult,
		MinAllocationSize = 1024 * 1024,
		CustomShaderVertCreateInfo = {},
		CustomShaderFragCreateInfo = {},
	}

	if !imguiVulkan.Init(&implInitInfo) {
		log(.Fatal, "Failed to init imgui vulkan.")
	}
}

@(private = "file")
cleanupImgui :: proc(using graphicsData: ^GraphicsData) {
	imguiVulkan.Shutdown()
	imguiGLFW.Shutdown()
	imgui.DestroyContext(imguiContext)
}


// ===[ Debug Labelling ]======================================================

@(private = "file")
nameCoreObjects :: proc(using graphicsData: ^GraphicsData) {
	vkNameObject(device, .DEVICE, u64(uintptr(device)), "Device")
	vkNameObject(device, .QUEUE, u64(uintptr(graphicsQueue)), "Queue: Graphics")
	vkNameObject(device, .QUEUE, u64(uintptr(presentQueue)), "Queue: Present")
	vkNameObject(device, .QUEUE, u64(uintptr(computeQueue)), "Queue: Compute")
	vkNameObject(device, .SWAPCHAIN_KHR, u64(swapchain.handle), "Swapchain")

	vkNameObject(
		device,
		.COMMAND_POOL,
		u64(graphicsCommandPool),
		"Command Pool: Graphics",
	)
	vkNameObject(device, .COMMAND_POOL, u64(computeCommandPool), "Command Pool: Compute")
	vkNameObject(device, .PIPELINE_CACHE, u64(pipelineCache), "Pipeline Cache")

	for pass in CmdBufferIndex {
		for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
			vkNameObject(
				device,
				.COMMAND_BUFFER,
				u64(uintptr(commandBuffers[pass][frame])),
				fmt.tprintf("Cmd: %v [frame %v]", pass, frame),
			)
		}
	}

	for kind in SemaphoreIndex {
		for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
			vkNameObject(
				device,
				.SEMAPHORE,
				u64(semaphores[kind][frame]),
				fmt.tprintf("Semaphore: %v [frame %v]", kind, frame),
			)
		}
	}

	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vkNameObject(
			device,
			.FENCE,
			u64(inFlightFrames[frame]),
			fmt.tprintf("Fence: In Flight [frame %v]", frame),
		)
	}

	for index in PipelineIndex {
		vkNameObject(
			device,
			.PIPELINE,
			u64(pipelines[index].handle),
			fmt.tprintf("Pipeline: %v", index),
		)

		for &image, imageIndex in pipelines[index].images {
			vkNameObject(
				device,
				.IMAGE,
				u64(image.vkImage),
				fmt.tprintf("Image: %v [%v]", index, imageIndex),
			)
			vkNameObject(
				device,
				.IMAGE_VIEW,
				u64(image.view),
				fmt.tprintf("Image View: %v [%v]", index, imageIndex),
			)
		}
	}

}
