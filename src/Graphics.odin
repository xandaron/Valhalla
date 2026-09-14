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

VERSION: u32 : (0 << 22) | (1 << 12) | (0)

HDR_ENABLED: bool : false

@(private = "file")
REQUESTED_LAYERS: []cstring : {"VK_LAYER_KHRONOS_validation"}

@(private = "file")
DEVICE_EXTENSIONS: []cstring : {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.KHR_COMPUTE_SHADER_DERIVATIVES_EXTENSION_NAME,
	vk.KHR_MAINTENANCE_7_EXTENSION_NAME,
}

when HDR_ENABLED {
	@(private = "file")
	INSTANCE_EXTENSIONS: []cstring : {
		vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
		vk.EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME,
	}
} else {
	@(private = "file")
	INSTANCE_EXTENSIONS: []cstring : {vk.EXT_DEBUG_UTILS_EXTENSION_NAME}
}

@(private = "file")
VERTEX_BINDING_DESCRIPTION: vk.VertexInputBindingDescription : {
	binding = 0,
	stride = size_of(Vertex),
	inputRate = .VERTEX,
}

@(private = "file")
VERTEX_ATTRIBUTE_DESCRIPTION: []vk.VertexInputAttributeDescription : {
	{
		location = 0,
		binding = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, position)),
	},
	{
		location = 1,
		binding = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, normal)),
	},
	{
		location = 2,
		binding = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, tangent)),
	},
	{
		location = 3,
		binding = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, bitangent)),
	},
	{location = 4, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, uv))},
	{
		location = 5,
		binding = 0,
		format = .R32G32B32A32_UINT,
		offset = u32(offset_of(Vertex, bones)),
	},
	{
		location = 6,
		binding = 0,
		format = .R32G32B32A32_SFLOAT,
		offset = u32(offset_of(Vertex, weights)),
	},
}

@(private = "file")
MAX_FRAMES_IN_FLIGHT: u32 : 2

RENDER_SIZE: [2]u32 : {1980, 1080}

@(private = "file")
SHADOW_RESOLUTION: [2]u32 : {512, 512}

@(private = "file")
IMAGES_RESOLUTION: [2]u32 : {2048, 2048}

@(private = "file")
DEPTH_BIAS_CONSTANT: f32 : 1.25

@(private = "file")
DEPTH_BIAS_SLOPE: f32 : 1.75

ErrorLevel :: enum {
	Warning,
	Error,
	Fatal,
}

WindowHandle :: glfw.WindowHandle
GLFWKeyCallback :: glfw.KeyProc
GLFWMouseButtonCallback :: glfw.MouseButtonProc
GLFWCursorPosCallback :: glfw.CursorPosProc
GLFWScrollCallback :: glfw.ScrollProc
GLFWErrorCallback :: glfw.ErrorProc

@(private = "file")
Transform_PushConstants :: struct {
	instance:        u32,
	instanceCount:   u32,
	vertexCount:     u32,
	vertexOffset:    u32,
	transformOffset: u32,
}

@(private = "file")
Light_PushConstants :: struct {
	layerIndex:   u32,
	vertexOffset: u32,
	vertexCount:  u32,
}

@(private = "file")
Scene_PushConstants :: struct {
	vertexOffset:   u32,
	vertexCount:    u32,
	instanceOffset: u32,
}

@(private = "file")
PostProcess_PushConstants :: struct {
	contrast:   f32,
	brightness: f32,
	saturation: f32,
	exposure:   f32,
	tonemapper: ToneMapper,
	gamma:      f32,
	drawLights: b32,
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
	colour:   Vec3,
	dropoff:  f32,
	near:     f32,
	far:      f32,
}

@(private = "file")
UniformBuffer :: struct #align (16) {
	projection:     Mat4,
	viewProjection: Mat4,
	lightCount:     u32,
	ambientLight:   f32,
}

@(private = "file")
InstanceInfo :: struct #align (16) {
	modelTransform: Mat4,
	boneOffset:     u32,
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
	DescriptorSetError,
	ImageError,
	BufferError,
	DrawError,
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
	textures:           Image,
	// TODO: Combine buffers into one buffer using offsets
	vertexBuffer:       Buffer,
	indexBuffer:        Buffer,
	instanceBuffers:    [MAX_FRAMES_IN_FLIGHT]Buffer,
	boneBuffers:        [MAX_FRAMES_IN_FLIGHT]Buffer,
	lightBuffers:       [MAX_FRAMES_IN_FLIGHT]Buffer,
	transformBuffers:   [MAX_FRAMES_IN_FLIGHT]Buffer,
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
	}
	deleteBuffer(graphicsData, &buffers.textureIndexBuffer)

	deleteImage(graphicsData, &buffers.textures)
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

	// Queues
	queueFamilies:       QueueFamilyIndices,
	graphicsQueue:       vk.Queue,
	presentQueue:        vk.Queue,
	computeQueue:        vk.Queue,

	// Swapchain
	swapchain:           Swapchain,

	// Pipelines
	descriptorSets:      [DescriptorSetIndex]DescriptorSet,
	pipelines:           [PipelineIndex]Pipeline,
	pipelineCache:       vk.PipelineCache,

	// Frame Resources
	depthFormat:         vk.Format,
	inFlightFrames:      [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	semaphores:          [SemaphoreIndex][MAX_FRAMES_IN_FLIGHT]vk.Semaphore,

	// Commands
	graphicsCommandPool: vk.CommandPool,
	computeCommandPool:  vk.CommandPool,
	commandBuffers:      [CmdBufferIndex][MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	samplers:            []vk.Sampler,

	// Buffer
	uniformBuffers:      [MAX_FRAMES_IN_FLIGHT]Buffer,

	// Util
	currentFrame:        u32,
	drawLights:          bool,
	reloadBuffers:       bool,
	dirtyCommands:       bit_set[CmdBufferIndex],
}

DIRTY_ALL: bit_set[CmdBufferIndex] : {.Transform, .Light, .Scene, .PostProcess}
DIRTY_GEOMETRY: bit_set[CmdBufferIndex] : {.Transform, .Light, .Scene}

markCommandsDirty :: proc(graphicsData: ^GraphicsData, passes: bit_set[CmdBufferIndex]) {
	graphicsData.dirtyCommands += passes
}

@(private = "file")
Swapchain :: struct {
	handle:    vk.SwapchainKHR,
	transform: vk.SurfaceTransformFlagsKHR,
	format:    vk.SurfaceFormatKHR,
	mode:      vk.PresentModeKHR,
	extent:    vk.Extent2D,
	images:    []vk.Image,
	views:     []vk.ImageView,
	presentReady: []vk.Semaphore,
}

@(private = "file")
QueueFamilyIndices :: struct {
	graphicsFamily: u32,
	presentFamily:  u32,
	computeFamily:  u32,
}

@(private = "file")
DescriptorSet :: struct {
	layout: vk.DescriptorSetLayout,
	pool:   vk.DescriptorPool,
	sets:   [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
}

@(private = "file")
DescriptorSetIndex :: enum {
	Buffers = 0,
	Textures,
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
	format:     vk.Format,
	sampler:    u32,
}

InitGraphicsInfo :: struct {
	appVersion:        u32,
	windowTitle:       cstring,

	// Shaders
	transformShader:   []byte,
	lightShaders:      [2][]byte,
	sceneShaders:      [2][]byte,
	postProcessShader: []byte,
}

InitError :: enum {
	None = 0,
	InitError,
	GLFWError,
	DepthFormatError,
}

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

	memoryAllocatorInit(&graphicsData.memoryAllocator, graphicsData.device, memoryProperties)

	createSwapchain(&graphicsData)
	createCommandBuffers(&graphicsData) or_return

	bufferSize := size_of(UniformBuffer)
	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if err := createBuffer(
			&graphicsData,
			bufferSize,
			{.UNIFORM_BUFFER},
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
	createBuffersDescriptorSets(&graphicsData)
	createTexturesDescriptorSets(&graphicsData)

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

	when HDR_ENABLED {
		tonemapper = .None
		gamma = 1.0
	} else {
		tonemapper = .NarkowiczACES
		gamma = 2.2
	}

	return graphicsData, nil
}

cleanupGraphics :: proc(using graphicsData: ^GraphicsData) {
	if vk.DeviceWaitIdle(device) != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	cleanupImgui(graphicsData)

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

	for &pipeline in pipelines {
		cleanupPipeline(graphicsData, &pipeline)

		for &image in pipeline.images {
			deleteImage(graphicsData, &image)
		}
		if len(pipeline.images) > 0 {
			delete(pipeline.images)
		}
	}

	for &descriptorSet in descriptorSets {
		vk.DestroyDescriptorPool(device, descriptorSet.pool, nil)
		vk.DestroyDescriptorSetLayout(device, descriptorSet.layout, nil)
	}

	cleanupSamplers(graphicsData)

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

updateWindow :: proc(using graphicsData: ^GraphicsData) -> (ret: bool) {
	ret = !glfw.WindowShouldClose(window)
	glfw.PollEvents()
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

InstanceError :: enum {
	None = 0,
	FailedToCreateInstance,
}

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

WindowError :: enum {
	None = 0,
	FailedToCreateWindow,
	FailedToCreateSurface,
}

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

	if res := glfw.CreateWindowSurface(instance, window, nil, &surface); res != .SUCCESS {
		logf(.Fatal, "Failed to create surface! vkResult: %v", res)
		return .FailedToCreateSurface
	}

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

DeviceError :: enum {
	None = 0,
	FailedToFindSuitableDevice,
	FailedToCreateDevice,
}

@(private = "file")
DeviceFeatures :: struct {
	features:           vk.PhysicalDeviceFeatures2,
	vulkan11:           vk.PhysicalDeviceVulkan11Features,
	vulkan12:           vk.PhysicalDeviceVulkan12Features,
	vulkan13:           vk.PhysicalDeviceVulkan13Features,
	vulkan14:           vk.PhysicalDeviceVulkan14Features,
	computeDerivatives: vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR,
	maintenance7:       vk.PhysicalDeviceMaintenance7FeaturesKHR,
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
			pNext = &chain.maintenance7,
		},
		maintenance7       = {sType = .PHYSICAL_DEVICE_MAINTENANCE_7_FEATURES_KHR, pNext = nil},
	}

	if !request {
		return
	}

	chain.features.features = {imageCubeArray = true, samplerAnisotropy = true}
	chain.vulkan11.multiview = true
	chain.vulkan11.shaderDrawParameters = true
	chain.vulkan12.shaderOutputViewportIndex = true
	chain.vulkan12.shaderOutputLayer = true
	chain.vulkan12.timelineSemaphore = true
	chain.vulkan12.bufferDeviceAddress = true
	chain.vulkan13.shaderDemoteToHelperInvocation = true
	chain.vulkan13.synchronization2 = true
	chain.vulkan13.dynamicRendering = true
	chain.vulkan14.maintenance5 = true
	chain.computeDerivatives.computeDerivativeGroupQuads = true
	chain.maintenance7.maintenance7 = true
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
		   &request.maintenance7,
		   &support.maintenance7,
		   size_of(vk.PhysicalDeviceMaintenance7FeaturesKHR),
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

SwapchainError :: enum {
	None = 0,
	FailedToCreateSwapchain,
	FailedToRecreateSwapchain,
	FailedToCreateSwapchainImageView,
}

getSwapcahainAspectRatio :: proc(using graphicsData: ^GraphicsData) -> f32 {
	return f32(swapchain.extent.width) / f32(swapchain.extent.height)
}

@(private = "file")
createSwapchain :: proc(using graphicsData: ^GraphicsData, oldSwapchain: vk.SwapchainKHR = 0) {
	chooseFormat :: proc(formats: []vk.SurfaceFormatKHR) -> (fmt: vk.SurfaceFormatKHR) {
		// TODO: improve this function
		fmt = formats[0]
		for format in formats {
			when HDR_ENABLED {
				if format.colorSpace == .HDR10_ST2084_EXT {
					return format
				} else if format.colorSpace == .SRGB_NONLINEAR && fmt.format != .R8G8B8A8_UNORM {
					if format.format == .R8G8B8A8_UNORM || format.format == .B8G8R8A8_UNORM {
						fmt = format
					}
				}
			} else {
				if (format.format == .B8G8R8A8_UNORM || format.format == .R8G8B8A8_UNORM) &&
				   format.colorSpace == .SRGB_NONLINEAR {
					fmt = format
				}
			}
		}
		return
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

	swapchain = {
		transform = swapchainSupport.capabilities.currentTransform,
		format    = chooseFormat(swapchainSupport.formats),
		mode      = choosePresentMode(swapchainSupport.modes),
		extent    = chooseExtent(graphicsData, swapchainSupport.capabilities),
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

	swapchain.presentReady = make([]vk.Semaphore, imageCount)
	semaphoreInfo: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = nil,
		flags = {},
	}
	for &semaphore in swapchain.presentReady {
		if res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &semaphore); res != .SUCCESS {
			logf(.Fatal, "Failed to create present semaphore! vkResult: %v", res)
		}
	}

	swapchain.views = make([]vk.ImageView, imageCount)
	for index in 0 ..< imageCount {
		err: ImageError
		swapchain.views[index], err = createImageView(
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

	for semaphore in swapchain.presentReady {
		vk.DestroySemaphore(graphicsData.device, semaphore, nil)
	}

	delete(swapchain.images)
	delete(swapchain.views)
	delete(swapchain.presentReady)

	vk.DestroySwapchainKHR(graphicsData.device, swapchain.handle, nil)
}

@(private = "file")
recreateSwapchain :: proc(using graphicsData: ^GraphicsData) {
	width, height := glfw.GetFramebufferSize(window)
	for width == 0 && height == 0 {
		glfw.WaitEvents()
		width, height = glfw.GetFramebufferSize(window)
	}

	vk.WaitForFences(device, len(inFlightFrames), &inFlightFrames[0], true, max(u64))
	vk.QueueWaitIdle(presentQueue)

	oldSwapchain := swapchain
	createSwapchain(graphicsData, oldSwapchain.handle)
	cleanupSwapchain(graphicsData, oldSwapchain)

	for &image in pipelines[.PostProcess].images {
		deleteImage(graphicsData, &image)
	}
	createPostProcessPipelineImages(graphicsData)

	updateComputeDescriptorSets(graphicsData)

	cleanupImgui(graphicsData)
	initImgui(graphicsData)
	markCommandsDirty(graphicsData, {.PostProcess})
}

CommandBufferError :: enum {
	None = 0,
	FailedToCreateCommandPool,
	FailedToAllocateCommandBuffer,
	FailedToBeginCommandBuffer,
	FailedToEndCommandBuffer,
}

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

BufferError :: enum {
	None = 0,
	FailedToCreateBuffer,
	FailedToAllocateBufferMemory,
	FailedToBindBufferMemory,
	FailedToLoadBufferToGPU,
}

@(private = "file")
@(require_results)
createBuffer :: proc(
	using graphicsData: ^GraphicsData,
	size: int,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^Buffer,
) -> BufferError {
	bufferInfo: vk.BufferCreateInfo = {
		sType                 = .BUFFER_CREATE_INFO,
		pNext                 = nil,
		flags                 = {},
		size                  = vk.DeviceSize(size),
		usage                 = usage,
		sharingMode           = .EXCLUSIVE,
		queueFamilyIndexCount = 0,
		pQueueFamilyIndices   = nil,
	}
	if res := vk.CreateBuffer(device, &bufferInfo, nil, &buffer.buffer); res != .SUCCESS {
		logf(.Error, "Failed to create buffer! vkResult: %v", res)
		return .FailedToCreateBuffer
	}

	dedicatedRequirements: vk.MemoryDedicatedRequirements = {
		sType = .MEMORY_DEDICATED_REQUIREMENTS,
		pNext = nil,
	}
	memoryRequirements: vk.MemoryRequirements2 = {
		sType = .MEMORY_REQUIREMENTS_2,
		pNext = &dedicatedRequirements,
	}
	vk.GetBufferMemoryRequirements2(
		device,
		&vk.BufferMemoryRequirementsInfo2 {
			sType = .BUFFER_MEMORY_REQUIREMENTS_INFO_2,
			pNext = nil,
			buffer = buffer.buffer,
		},
		&memoryRequirements,
	)

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

	if res := vk.BindBufferMemory(device, buffer.buffer, allocation.memory, allocation.offset);
	   res != .SUCCESS {
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
	stagingBuffer: Buffer
	if err := createBuffer(
		graphicsData,
		bufferSize,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&stagingBuffer,
	); err != nil {
		logf(.Error, "Failed to create staging buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}
	defer deleteBuffer(graphicsData, &stagingBuffer)

	mem.copy(stagingBuffer.mapped, srcData, bufferSize)

	if err := createBuffer(
		graphicsData,
		bufferSize,
		{.TRANSFER_DST, .STORAGE_BUFFER, bufferType},
		{.DEVICE_LOCAL},
		dstBuffer,
	); err != nil {
		logf(.Error, "Failed to create destination buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}

	commandBuffer, err := beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to begin single time command buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}

	copyRegion: vk.BufferCopy2 = {
		sType     = .BUFFER_COPY_2,
		pNext     = nil,
		srcOffset = 0,
		dstOffset = 0,
		size      = vk.DeviceSize(bufferSize),
	}

	vk.CmdCopyBuffer2(
		commandBuffer,
		&vk.CopyBufferInfo2 {
			sType = .COPY_BUFFER_INFO_2,
			pNext = nil,
			srcBuffer = stagingBuffer.buffer,
			dstBuffer = dstBuffer.buffer,
			regionCount = 1,
			pRegions = &copyRegion,
		},
	)
	if err := endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool); err != nil {
		logf(.Error, "Failed to end single time command buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}

	return nil
}

@(private = "file")
deleteBuffer :: proc(using graphicsData: ^GraphicsData, buffer: ^Buffer) {
	vk.DestroyBuffer(device, buffer.buffer, nil)
	memoryFree(&graphicsData.memoryAllocator, &buffer.allocation)
	buffer^ = {}
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

	if res := vk.BindImageMemory(device, image.vkImage, allocation.memory, allocation.offset);
	   res != .SUCCESS {
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
) -> (
	imageView: vk.ImageView,
	err: ImageError = .None,
) {
	viewInfo: vk.ImageViewCreateInfo = {
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
			baseArrayLayer = 0,
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
	image: vk.Image,
	width, height: u32,
) {
	region: vk.BufferImageCopy2 = {
		sType = .BUFFER_IMAGE_COPY_2,
		pNext = nil,
		bufferOffset = 0,
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
copyBufferToTextureArray :: proc(
	using graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	buffer: vk.Buffer,
	image: vk.Image,
	width, height, textureCount: u32,
) {
	regions := make([]vk.BufferImageCopy2, textureCount)
	defer delete(regions)
	imageSize := width * height * 4
	for &region, index in regions {
		index := u32(index)
		region = {
			sType = .BUFFER_IMAGE_COPY_2,
			pNext = nil,
			bufferOffset = vk.DeviceSize(imageSize * index),
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = vk.ImageSubresourceLayers {
				aspectMask = {.COLOR},
				mipLevel = 0,
				baseArrayLayer = u32(index),
				layerCount = 1,
			},
			imageOffset = vk.Offset3D{x = 0, y = 0, z = 0},
			imageExtent = vk.Extent3D{width = width, height = height, depth = 1},
		}
	}
	vk.CmdCopyBufferToImage2(
		commandBuffer,
		&vk.CopyBufferToImageInfo2 {
			sType = .COPY_BUFFER_TO_IMAGE_INFO_2,
			pNext = nil,
			srcBuffer = buffer,
			dstImage = image,
			dstImageLayout = .TRANSFER_DST_OPTIMAL,
			regionCount = u32(len(regions)),
			pRegions = raw_data(regions),
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
upscaleImage :: proc(
	commandBuffer: vk.CommandBuffer,
	src, dst: vk.Image,
	srcSize, dstSize: vk.Extent2D,
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
			{x = 0, y = 0, z = 0},
			{x = i32(dstSize.width), y = i32(dstSize.height), z = 1},
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

SamplerError :: enum {
	None = 0,
	FailedToCreateSampler,
}

@(private = "file")
@(require_results)
createSamplers :: proc(using graphicsData: ^GraphicsData) -> SamplerError {
	samplers = make([]vk.Sampler, 2)
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
	if res := vk.CreateSampler(device, &samplerInfo, nil, &samplers[0]); res != .SUCCESS {
		logf(.Fatal, "Failed to create texture sampler! vkResult: %d", res)
		return .FailedToCreateSampler
	}

	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physicalDevice, &properties)
	samplerInfo.anisotropyEnable = true
	samplerInfo.maxAnisotropy = properties.limits.maxSamplerAnisotropy
	if res := vk.CreateSampler(device, &samplerInfo, nil, &samplers[1]); res != .SUCCESS {
		logf(.Fatal, "Failed to create texture sampler! vkResult: %d", res)
		return .FailedToCreateSampler
	}

	return .None
}

@(private = "file")
cleanupSamplers :: proc(using graphicsData: ^GraphicsData) {
	for &sampler in samplers {
		vk.DestroySampler(device, sampler, nil)
	}
	delete(samplers)
}

LoaderError :: enum {
	None = 0,
	FailedToLoadFile,
	InvalidFileData,
}

@(require_results)
loadImages :: proc(
	using graphicsData: ^GraphicsData,
	scene: ^Scene,
	imagePaths: []string,
) -> (
	err: Error,
) {
	image := &scene.buffers.textures
	image.format = .R8G8B8A8_SRGB
	if err := createImage(
		graphicsData,
		image,
		{},
		.D2,
		IMAGES_RESOLUTION.x,
		IMAGES_RESOLUTION.y,
		u32(len(imagePaths)),
		{._1},
		.OPTIMAL,
		{.TRANSFER_DST, .TRANSFER_SRC, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	); err != nil {
		logf(.Error, "Failed to create image for textures! Error: %v", err)
		return err
	}

	commandBuffer: vk.CommandBuffer
	commandBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to begin single time commands! Error: %v", err)
		return err
	}

	transitionImageLayout(
		graphicsData,
		commandBuffer,
		image.vkImage,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		u32(len(imagePaths)),
	)

	if err := endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool); err != nil {
		logf(.Error, "Failed to end single time commands! Error: %v", err)
		return err
	}

	for path, index in imagePaths {
		width, height: i32
		pixels := img.load(
			strings.clone_to_cstring(path, allocator = context.temp_allocator),
			&width,
			&height,
			nil,
			4,
		)
		defer img.image_free(pixels)
		if pixels == nil {
			log(.Error, "Failed to load texture!")
			return ImageError.FailedToLoadImage
		}
		textureSize := int(width * height * 4)

		stagingBuffer: Buffer
		err = createBuffer(
			graphicsData,
			textureSize,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&stagingBuffer,
		)
		if err != nil {
			logf(.Error, "Failed to create staging buffer! Error: %v", err)
			return err
		}
		defer {
			deleteBuffer(graphicsData, &stagingBuffer)
		}

		mem.copy(stagingBuffer.mapped, pixels, textureSize)

		stagingImage: Image
		stagingImage.format = .R8G8B8A8_SRGB
		if err := createImage(
			graphicsData,
			&stagingImage,
			{},
			.D2,
			u32(width),
			u32(height),
			1,
			{._1},
			.OPTIMAL,
			{.TRANSFER_DST, .TRANSFER_SRC},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		); err != nil {
			logf(.Error, "Failed to create staging image! Error: %v", err)
			return err
		}

		defer {
			vk.DestroyImage(device, stagingImage.vkImage, nil)
			memoryFree(&graphicsData.memoryAllocator, &stagingImage.allocation)
		}

		commandBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
		if err != nil {
			logf(.Error, "Failed to begin single time commands! Error: %v", err)
			return err
		}
		transitionImageLayout(
			graphicsData,
			commandBuffer,
			stagingImage.vkImage,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		copyBufferToImage(
			graphicsData,
			commandBuffer,
			stagingBuffer.buffer,
			stagingImage.vkImage,
			u32(width),
			u32(height),
		)

		transitionImageLayout(
			graphicsData,
			commandBuffer,
			stagingImage.vkImage,
			.TRANSFER_DST_OPTIMAL,
			.TRANSFER_SRC_OPTIMAL,
			{.COLOR},
			1,
		)

		upscaleImage(
			commandBuffer,
			stagingImage.vkImage,
			image.vkImage,
			{u32(width), u32(height)},
			{IMAGES_RESOLUTION.x, IMAGES_RESOLUTION.y},
			0,
			u32(index),
		)
		err = endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool)
		if err != nil {
			logf(.Error, "Failed to end single time commands! Error: %v", err)
			return err
		}
	}

	commandBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to begin single time commands! Error: %v", err)
		return err
	}

	transitionImageLayout(
		graphicsData,
		commandBuffer,
		image.vkImage,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR},
		u32(len(imagePaths)),
	)

	err = endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to end single time commands! Error: %v", err)
		return err
	}

	image.view, err = createImageView(
		graphicsData,
		image.vkImage,
		.D2_ARRAY,
		image.format,
		{.COLOR},
		u32(len(imagePaths)),
	)
	if err != nil {
		logf(.Error, "Failed to create image view for textures! Error: %v", err)
		return err
	}

	image.sampler = 1
	return nil
}

@(require_results)
addImages :: proc(
	using graphicsData: ^GraphicsData,
	image: ^Image,
	imageLayers: u32,
	imagePaths: []string,
) -> (
	err: Error,
) {
	imageCount := u32(len(imagePaths))

	newImage: Image = {
		format  = image.format,
		sampler = image.sampler,
	}

	err = createImage(
		graphicsData,
		&newImage,
		{},
		.D2,
		IMAGES_RESOLUTION.x,
		IMAGES_RESOLUTION.y,
		imageLayers + imageCount,
		{._1},
		.OPTIMAL,
		{.TRANSFER_DST, .TRANSFER_SRC, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		logf(.Error, "Failed to create image for textures! Error: %v", err)
		return err
	}

	commandBuffer: vk.CommandBuffer
	commandBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to begin single time commands! Error: %v", err)
		return err
	}

	transitionImageLayout(
		graphicsData,
		commandBuffer,
		newImage.vkImage,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		imageLayers + imageCount,
	)

	transitionImageLayout(
		graphicsData,
		commandBuffer,
		image.vkImage,
		.SHADER_READ_ONLY_OPTIMAL,
		.TRANSFER_SRC_OPTIMAL,
		{.COLOR},
		imageLayers,
	)

	copyInfo: vk.ImageCopy2 = {
		sType = .IMAGE_COPY_2,
		pNext = nil,
		srcSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = imageLayers,
		},
		srcOffset = {0, 0, 0},
		dstSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = imageLayers,
		},
		dstOffset = {0, 0, 0},
		extent = {IMAGES_RESOLUTION.x, IMAGES_RESOLUTION.y, 1},
	}
	vk.CmdCopyImage2(
		commandBuffer,
		&vk.CopyImageInfo2 {
			sType = .COPY_IMAGE_INFO_2,
			pNext = nil,
			srcImage = image.vkImage,
			srcImageLayout = .TRANSFER_SRC_OPTIMAL,
			dstImage = newImage.vkImage,
			dstImageLayout = .TRANSFER_DST_OPTIMAL,
			regionCount = 1,
			pRegions = &copyInfo,
		},
	)
	err = endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to end single time commands! Error: %v", err)
		return err
	}

	// Crashing if error after this point
	deleteImage(graphicsData, image)
	image^ = newImage

	for path, pathIdx in imagePaths {
		width, height: i32
		pixels := img.load(
			strings.clone_to_cstring(path, allocator = context.temp_allocator),
			&width,
			&height,
			nil,
			4,
		)
		defer img.image_free(pixels)
		if pixels == nil {
			log(.Error, "Failed to load texture!")
			panic("Failed to load texture!")
		}
		textureSize := int(width * height * 4)

		stagingBuffer: Buffer
		err = createBuffer(
			graphicsData,
			textureSize,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&stagingBuffer,
		)
		if err != nil {
			logf(.Error, "Failed to create staging buffer! Error: %v", err)
			return err
		}
		defer {
			deleteBuffer(graphicsData, &stagingBuffer)
		}

		mem.copy(stagingBuffer.mapped, pixels, textureSize)

		stagingImage: Image
		stagingImage.format = .R8G8B8A8_SRGB
		err = createImage(
			graphicsData,
			&stagingImage,
			{},
			.D2,
			u32(width),
			u32(height),
			1,
			{._1},
			.OPTIMAL,
			{.TRANSFER_DST, .TRANSFER_SRC},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		)
		if err != nil {
			logf(.Error, "Failed to create staging image! Error: %v", err)
			return err
		}

		defer {
			vk.DestroyImage(device, stagingImage.vkImage, nil)
			memoryFree(&graphicsData.memoryAllocator, &stagingImage.allocation)
		}

		commandBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
		if err != nil {
			logf(.Error, "Failed to begin single time commands! Error: %v", err)
			return err
		}

		transitionImageLayout(
			graphicsData,
			commandBuffer,
			stagingImage.vkImage,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		copyBufferToImage(
			graphicsData,
			commandBuffer,
			stagingBuffer.buffer,
			stagingImage.vkImage,
			u32(width),
			u32(height),
		)

		transitionImageLayout(
			graphicsData,
			commandBuffer,
			stagingImage.vkImage,
			.TRANSFER_DST_OPTIMAL,
			.TRANSFER_SRC_OPTIMAL,
			{.COLOR},
			1,
		)

		upscaleImage(
			commandBuffer,
			stagingImage.vkImage,
			image.vkImage,
			{u32(width), u32(height)},
			{IMAGES_RESOLUTION.x, IMAGES_RESOLUTION.y},
			0,
			imageLayers,
		)

		err = endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool)
		if err != nil {
			logf(.Error, "Failed to end single time commands! Error: %v", err)
			return err
		}
	}

	commandBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to begin single time commands! Error: %v", err)
		return err
	}

	transitionImageLayout(
		graphicsData,
		commandBuffer,
		image.vkImage,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR},
		imageLayers,
	)
	err = endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to end single time commands! Error: %v", err)
		return err
	}

	image.view, err = createImageView(
		graphicsData,
		image.vkImage,
		.D2_ARRAY,
		image.format,
		{.COLOR},
		imageLayers,
	)
	if err != nil {
		logf(.Error, "Failed to create image view! Error: %v", err)
		return err
	}

	return nil
}

@(private = "file")
deleteImage :: proc(using graphicsData: ^GraphicsData, image: ^Image) {
	vk.DestroyImageView(device, image.view, nil)
	vk.DestroyImage(device, image.vkImage, nil)
	memoryFree(&graphicsData.memoryAllocator, &image.allocation)
	image.view = 0
	image.vkImage = 0
}

updateSceneBuffers :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	err: Error

	buffers := &scene.buffers
	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

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

	instanceBufferSize := size_of(InstanceInfo) * len(scene.objects)
	boneBufferSize := size_of(Mat4) * scene.boneCount
	lightBufferSize := size_of(LightData) * len(scene.lights)
	transformBufferSize := size_of(Mat4) * scene.vertexCount

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

	deleteImage(graphicsData, &pipelines[.Light].images[0])
	deleteImage(graphicsData, &pipelines[.Light].images[1])
	createLightPipelineImages(graphicsData, scene)

	updateDescriptorSets(graphicsData, scene)
	markCommandsDirty(graphicsData, DIRTY_ALL)
	updateCommandBuffers(graphicsData, scene)
}

DescriptorSetError :: enum {
	None = 0,
	FailedToCreateDescriptorPool,
	FailedToCreateDescriptorSetLayout,
	FailedToCreateDescriptorSet,
	FailedToAllocateDescriptorSets,
}

@(private = "file")
createBuffersDescriptorSets :: proc(using graphicsData: ^GraphicsData) {
	layoutBindings := [?]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 1,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 2,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 3,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 4,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
			pImmutableSamplers = nil,
		},
		{
			binding = 5,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 6,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 7,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
			pImmutableSamplers = nil,
		},
	}

	layoutInfo: vk.DescriptorSetLayoutCreateInfo = {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pNext        = nil,
		flags        = {},
		bindingCount = u32(len(layoutBindings)),
		pBindings    = &layoutBindings[0],
	}

	if res := vk.CreateDescriptorSetLayout(
		device,
		&layoutInfo,
		nil,
		&descriptorSets[.Buffers].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor set layout! vkResult: %d", res)
	}

	poolSizes := [?]vk.DescriptorPoolSize {
		{type = .UNIFORM_BUFFER, descriptorCount = 1 * 2},
		{type = .STORAGE_BUFFER, descriptorCount = 7 * 2},
	}

	poolInfo: vk.DescriptorPoolCreateInfo = {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		pNext         = nil,
		flags         = {},
		maxSets       = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = &poolSizes[0],
	}

	if res := vk.CreateDescriptorPool(
		device,
		&poolInfo,
		nil,
		&descriptorSets[.Buffers].pool,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor pool! vkResult: %d", res)
	}

	layouts: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
	for &layout in layouts {
		layout = descriptorSets[.Buffers].layout
	}

	allocInfo: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = descriptorSets[.Buffers].pool,
		descriptorSetCount = u32(len(layouts)),
		pSetLayouts        = &layouts[0],
	}

	if res := vk.AllocateDescriptorSets(
		device,
		&allocInfo,
		&descriptorSets[.Buffers].sets[0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate descriptor sets! vkResult %v", res)
	}
}

@(private = "file")
createTexturesDescriptorSets :: proc(using graphicsData: ^GraphicsData) {
	layoutBindings := [?]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
			pImmutableSamplers = nil,
		},
		{
			binding = 1,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
			pImmutableSamplers = nil,
		},
		{
			binding = 2,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 3,
			descriptorType = .STORAGE_IMAGE,
			descriptorCount = 1,
			stageFlags = {.COMPUTE},
			pImmutableSamplers = nil,
		},
		{
			binding = 4,
			descriptorType = .STORAGE_IMAGE,
			descriptorCount = 1,
			stageFlags = {.COMPUTE},
			pImmutableSamplers = nil,
		},
	}

	layoutInfo: vk.DescriptorSetLayoutCreateInfo = {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pNext        = nil,
		flags        = {},
		bindingCount = u32(len(layoutBindings)),
		pBindings    = &layoutBindings[0],
	}

	if res := vk.CreateDescriptorSetLayout(
		device,
		&layoutInfo,
		nil,
		&descriptorSets[.Textures].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor set layout! vkResult: %d", res)
	}

	poolSizes := [?]vk.DescriptorPoolSize {
		{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 3 * 2},
		{type = .STORAGE_IMAGE, descriptorCount = 2 * 2},
	}

	poolInfo: vk.DescriptorPoolCreateInfo = {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		pNext         = nil,
		flags         = {},
		maxSets       = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = &poolSizes[0],
	}

	if res := vk.CreateDescriptorPool(
		device,
		&poolInfo,
		nil,
		&descriptorSets[.Textures].pool,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor pool! vkResult: %d", res)
	}

	layouts: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
	for &layout in layouts {
		layout = descriptorSets[.Textures].layout
	}

	allocInfo: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = descriptorSets[.Textures].pool,
		descriptorSetCount = u32(len(layouts)),
		pSetLayouts        = &layouts[0],
	}

	if res := vk.AllocateDescriptorSets(
		device,
		&allocInfo,
		&descriptorSets[.Textures].sets[0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate descriptor sets! vkResult: %d", res)
	}
}

@(private = "file")
updateDescriptorSets :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	buffers := &scene.buffers
	vertexBufferInfo: vk.DescriptorBufferInfo = {
		buffer = buffers.vertexBuffer.buffer,
		offset = 0,
		range  = vk.DeviceSize(size_of(Vertex) * len(scene.vertices)),
	}

	uniformBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = size_of(UniformBuffer),
	}

	instanceBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(InstanceInfo) * len(scene.objects)),
	}

	boneBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(Mat4) * scene.boneCount),
	}

	lightsBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(LightData) * len(scene.lights)),
	}

	transformBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(Mat4) * scene.vertexCount),
	}

	textureBufferLen := 0
	for &model in scene.models {
		textureBufferLen += len(model.instances) * len(model.meshes)
	}
	textureIndexBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(u32) * textureBufferLen * len(TextureIndex)),
		buffer = buffers.textureIndexBuffer.buffer,
	}

	textureImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[buffers.textures.sampler],
		imageView   = buffers.textures.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	shadowImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[pipelines[.Light].images[0].sampler],
		imageView   = pipelines[.Light].images[0].view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	sceneDepthInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[pipelines[.Scene].images[1].sampler],
		imageView   = pipelines[.Scene].images[1].view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	renderedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[.PostProcess].images[0].view,
		imageLayout = .GENERAL,
	}

	processedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[.PostProcess].images[1].view,
		imageLayout = .GENERAL,
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		uniformBufferInfo.buffer = uniformBuffers[index].buffer
		instanceBufferInfo.buffer = buffers.instanceBuffers[index].buffer
		boneBufferInfo.buffer = buffers.boneBuffers[index].buffer
		lightsBufferInfo.buffer = buffers.lightBuffers[index].buffer
		transformBufferInfo.buffer = buffers.transformBuffers[index].buffer

		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 0,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &vertexBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 1,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .UNIFORM_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &uniformBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 2,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &instanceBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 3,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &boneBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 4,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &transformBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 5,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &transformBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 6,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &lightsBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Buffers].sets[index],
				dstBinding = 7,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &textureIndexBufferInfo,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 0,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &textureImageInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 1,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &shadowImageInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 2,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &sceneDepthInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 3,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_IMAGE,
				pImageInfo = &renderedImageInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 4,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_IMAGE,
				pImageInfo = &processedImageInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
		}

		vk.UpdateDescriptorSets(
			device,
			u32(len(descriptorWrites)),
			raw_data(descriptorWrites),
			0,
			nil,
		)
	}
}

@(private = "file")
updateComputeDescriptorSets :: proc(using graphicsData: ^GraphicsData) {
	sceneDepthInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[pipelines[.Scene].images[1].sampler],
		imageView   = pipelines[.Scene].images[1].view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	renderedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[.PostProcess].images[0].view,
		imageLayout = .GENERAL,
	}

	processedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[.PostProcess].images[1].view,
		imageLayout = .GENERAL,
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 2,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &sceneDepthInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 3,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_IMAGE,
				pImageInfo = &renderedImageInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[.Textures].sets[index],
				dstBinding = 4,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_IMAGE,
				pImageInfo = &processedImageInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
		}

		vk.UpdateDescriptorSets(
			device,
			u32(len(descriptorWrites)),
			raw_data(descriptorWrites),
			0,
			nil,
		)
	}
}

SyncError :: enum {
	None = 0,
	FailedToCreateFence,
	FailedToCreateSemaphore,
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

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if res := vk.CreateFence(device, &fenceInfo, nil, &inFlightFrames[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create fence! vkResult: %d", res)
			return .FailedToCreateFence
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

@(private = "file")
PipelineIndex :: enum {
	Transform,
	Light,
	Scene,
	PostProcess,
}

@(private = "file")
Pipeline :: struct {
	handle:     vk.Pipeline,
	layout:     vk.PipelineLayout,
	images:     []Image,
	descriptor: vk.DescriptorImageInfo,
}

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
		vkNameObject(
			device,
			.PIPELINE_LAYOUT,
			u64(pipelines[index].layout),
			fmt.tprintf("Pipeline Layout: %v", index),
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

	for index in DescriptorSetIndex {
		vkNameObject(
			device,
			.DESCRIPTOR_SET_LAYOUT,
			u64(descriptorSets[index].layout),
			fmt.tprintf("Descriptor Layout: %v", index),
		)
		for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
			vkNameObject(
				device,
				.DESCRIPTOR_SET,
				u64(descriptorSets[index].sets[frame]),
				fmt.tprintf("Descriptor Set: %v [frame %v]", index, frame),
			)
		}
	}
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
	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[.Buffers].layout,
		descriptorSets[.Textures].layout,
	}

	pushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = size_of(Transform_PushConstants),
	}

	pipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = nil,
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pushConstants,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&pipelineLayoutInfo,
		nil,
		&pipelines[.Transform].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create precompute pipeline layout! vkResult: %d", res)
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
		pNext              = nil,
		flags              = nil,
		stage              = shaderStageInfo,
		layout             = pipelines[.Transform].layout,
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

	pipelines[.Light].images[0].view, err = createImageView(
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

	pipelines[.Light].images[1].view, err = createImageView(
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
	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[.Buffers].layout,
		descriptorSets[.Textures].layout,
	}

	vertexBindingDescription := VERTEX_BINDING_DESCRIPTION

	pushConstants: vk.PushConstantRange = {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = size_of(Light_PushConstants),
	}

	pipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = nil,
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pushConstants,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&pipelineLayoutInfo,
		nil,
		&pipelines[.Light].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline layout! vkResult: %d", res)
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

	pipelineInfo := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &vk.PipelineRenderingCreateInfo {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			pNext = nil,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &pipelines[.Light].images[0].format,
			depthAttachmentFormat = pipelines[.Light].images[1].format,
			stencilAttachmentFormat = .UNDEFINED,
		},
		flags               = nil,
		stageCount          = u32(len(shaderStages)),
		pStages             = &shaderStages[0],
		pVertexInputState   = &vk.PipelineVertexInputStateCreateInfo {
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			vertexBindingDescriptionCount = 1,
			pVertexBindingDescriptions = &vertexBindingDescription,
			vertexAttributeDescriptionCount = u32(len(VERTEX_ATTRIBUTE_DESCRIPTION)),
			pVertexAttributeDescriptions = raw_data(VERTEX_ATTRIBUTE_DESCRIPTION),
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
			pViewports = &vk.Viewport {
				x = 0,
				y = 0,
				width = f32(SHADOW_RESOLUTION.x),
				height = f32(SHADOW_RESOLUTION.y),
				minDepth = 0,
				maxDepth = 1,
			},
			scissorCount = 1,
			pScissors = &vk.Rect2D {
				offset = {0, 0},
				extent = {SHADOW_RESOLUTION.x, SHADOW_RESOLUTION.y},
			},
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
		pDynamicState       = nil,
		layout              = pipelines[.Light].layout,
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
		RENDER_SIZE.x,
		RENDER_SIZE.y,
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

	pipelines[.Scene].images[0].view, err = createImageView(
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
		RENDER_SIZE.x,
		RENDER_SIZE.y,
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

	pipelines[.Scene].images[1].view, err = createImageView(
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
	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[.Buffers].layout,
		descriptorSets[.Textures].layout,
	}

	vertexBindingDescription := VERTEX_BINDING_DESCRIPTION

	pushConstant: vk.PushConstantRange = {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = size_of(Scene_PushConstants),
	}

	pipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = nil,
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pushConstant,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&pipelineLayoutInfo,
		nil,
		&pipelines[.Scene].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline layout! vkResult: %d", res)
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

	pipelineInfo: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &vk.PipelineRenderingCreateInfo {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			pNext = nil,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &pipelines[.Scene].images[0].format,
			depthAttachmentFormat = pipelines[.Scene].images[1].format,
			stencilAttachmentFormat = .UNDEFINED,
		},
		flags               = nil,
		stageCount          = u32(len(shaderStages)),
		pStages             = &shaderStages[0],
		pVertexInputState   = &{
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			vertexBindingDescriptionCount = 1,
			pVertexBindingDescriptions = &vertexBindingDescription,
			vertexAttributeDescriptionCount = u32(len(VERTEX_ATTRIBUTE_DESCRIPTION)),
			pVertexAttributeDescriptions = raw_data(VERTEX_ATTRIBUTE_DESCRIPTION),
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
			pViewports = &vk.Viewport {
				x = 0,
				y = 0,
				width = f32(RENDER_SIZE.x),
				height = f32(RENDER_SIZE.y),
				minDepth = 0,
				maxDepth = 1,
			},
			scissorCount = 1,
			pScissors = &vk.Rect2D{offset = {0, 0}, extent = {RENDER_SIZE.x, RENDER_SIZE.y}},
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
		pDynamicState       = nil,
		layout              = pipelines[.Scene].layout,
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

	pipelines[.PostProcess].images[0].view, err = createImageView(
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

	pipelines[.PostProcess].images[1].view, err = createImageView(
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
	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[.Buffers].layout,
		descriptorSets[.Textures].layout,
	}

	pushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = size_of(PostProcess_PushConstants),
	}

	pipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = nil,
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pushConstants,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&pipelineLayoutInfo,
		nil,
		&pipelines[.PostProcess].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create postprocess pipeline layout! vkResult: %v", res)
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
		pNext              = nil,
		flags              = nil,
		stage              = shaderStage,
		layout             = pipelines[.PostProcess].layout,
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
	vk.DestroyPipelineLayout(device, pipeline.layout, nil)
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
	case .PostProcess:
		createPostProcessPipeline(graphicsData, shaders[0])
		markCommandsDirty(graphicsData, {.PostProcess})
	}
}

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

@(private = "file")
updateLightBuffer :: proc(using graphicsData: ^GraphicsData, scene: ^Scene, delta: f32) {
	buffers := &scene.buffers
	lightData := make([]LightData, len(scene.lights), allocator = context.temp_allocator)
	for &light, i in scene.lights {
		colour := light.colour * light.brightness
		lightData[i] = {
			position = light.position,
			colour   = light.colour * light.brightness,
			dropoff  = light.dropoff,
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
					textureIndices[idx + int(val)] = object.textureIdxs[meshIdx][val]
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

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[.Buffers].sets[currentFrame],
		descriptorSets[.Textures].sets[currentFrame],
	}
	vk.CmdBindDescriptorSets2(
		cmdBuffer,
		&vk.BindDescriptorSetsInfo {
			sType = .BIND_DESCRIPTOR_SETS_INFO,
			pNext = nil,
			stageFlags = {.COMPUTE},
			layout = pipelines[.Transform].layout,
			firstSet = 0,
			descriptorSetCount = len(sets),
			pDescriptorSets = &sets[0],
			dynamicOffsetCount = 0,
			pDynamicOffsets = nil,
		},
	)
	vk.CmdBindPipeline(cmdBuffer, .COMPUTE, pipelines[.Transform].handle)

	pushConstants: Transform_PushConstants = {
		instance        = 0,
		instanceCount   = 0,
		vertexCount     = 0,
		vertexOffset    = 0,
		transformOffset = 0,
	}
	for &model in scene.models {
		OFFSET :: u32(offset_of(Transform_PushConstants, instanceCount))

		vk.CmdPushConstants2(
			cmdBuffer,
			&vk.PushConstantsInfo {
				sType = .PUSH_CONSTANTS_INFO,
				pNext = nil,
				layout = pipelines[.Transform].layout,
				stageFlags = {.COMPUTE},
				offset = 0,
				size = OFFSET,
				pValues = &pushConstants,
			},
		)
		for &mesh in model.meshes {
			pushConstants.instanceCount = u32(len(model.instances))
			pushConstants.vertexCount = mesh.vertexCount
			pushConstants.vertexOffset = mesh.vertexOffset

			vk.CmdPushConstants2(
				cmdBuffer,
				&vk.PushConstantsInfo {
					sType = .PUSH_CONSTANTS_INFO,
					pNext = nil,
					layout = pipelines[.Transform].layout,
					stageFlags = {.COMPUTE},
					offset = OFFSET,
					size = size_of(Transform_PushConstants) - OFFSET,
					pValues = &pushConstants.instanceCount,
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
	lightImageCount := lightCount * 6

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
			layerCount = lightImageCount,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachments = &vk.RenderingAttachmentInfo {
				sType = .RENDERING_ATTACHMENT_INFO,
				pNext = nil,
				imageView = pipelines[.Light].images[0].view,
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
				imageView = pipelines[.Light].images[1].view,
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

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[.Buffers].sets[currentFrame],
		descriptorSets[.Textures].sets[currentFrame],
	}

	vk.CmdBindDescriptorSets2(
		cmdBuffer,
		&vk.BindDescriptorSetsInfo {
			sType = .BIND_DESCRIPTOR_SETS_INFO,
			pNext = nil,
			stageFlags = {.VERTEX, .FRAGMENT},
			layout = pipelines[.Light].layout,
			firstSet = 0,
			descriptorSetCount = len(sets),
			pDescriptorSets = &sets[0],
			dynamicOffsetCount = 0,
			pDynamicOffsets = nil,
		},
	)

	vk.CmdBindVertexBuffers(
		cmdBuffer,
		0,
		1,
		&scene.buffers.vertexBuffer.buffer,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer2(
		cmdBuffer,
		scene.buffers.indexBuffer.buffer,
		0,
		vk.DeviceSize(vk.WHOLE_SIZE),
		.UINT32,
	)

	pushConstants: Light_PushConstants = {
		layerIndex   = 0,
		vertexOffset = 0,
		vertexCount  = 0,
	}
	for layerIndex: u32 = 0; layerIndex < lightImageCount; layerIndex += 1 {
		OFFSET :: u32(offset_of(Light_PushConstants, vertexOffset))
		pushConstants.layerIndex = layerIndex
		vk.CmdPushConstants2(
			cmdBuffer,
			&vk.PushConstantsInfo {
				sType = .PUSH_CONSTANTS_INFO,
				pNext = nil,
				layout = pipelines[.Light].layout,
				stageFlags = {.VERTEX},
				offset = 0,
				size = OFFSET,
				pValues = &pushConstants,
			},
		)

		pushConstants.vertexOffset = 0
		for &model in scene.models {
			for &mesh in model.meshes {
				pushConstants.vertexCount = mesh.vertexCount
				vk.CmdPushConstants2(
					cmdBuffer,
					&vk.PushConstantsInfo {
						sType = .PUSH_CONSTANTS_INFO,
						pNext = nil,
						layout = pipelines[.Light].layout,
						stageFlags = {.VERTEX},
						offset = OFFSET,
						size = size_of(Light_PushConstants) - OFFSET,
						pValues = &pushConstants.vertexOffset,
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
	}

	vk.CmdEndRendering(cmdBuffer)

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
			renderArea = vk.Rect2D{offset = {0, 0}, extent = {RENDER_SIZE.x, RENDER_SIZE.y}},
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

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[.Buffers].sets[currentFrame],
		descriptorSets[.Textures].sets[currentFrame],
	}

	vk.CmdBindDescriptorSets2(
		cmdBuffer,
		&vk.BindDescriptorSetsInfo {
			sType = .BIND_DESCRIPTOR_SETS_INFO,
			pNext = nil,
			stageFlags = {.VERTEX, .FRAGMENT},
			layout = pipelines[.Scene].layout,
			firstSet = 0,
			descriptorSetCount = len(sets),
			pDescriptorSets = &sets[0],
			dynamicOffsetCount = 0,
			pDynamicOffsets = nil,
		},
	)
	vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[.Scene].handle)

	vk.CmdBindVertexBuffers(
		cmdBuffer,
		0,
		1,
		&scene.buffers.vertexBuffer.buffer,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer2(
		cmdBuffer,
		scene.buffers.indexBuffer.buffer,
		0,
		vk.DeviceSize(vk.WHOLE_SIZE),
		.UINT32,
	)

	pushConstants: Scene_PushConstants = {
		vertexOffset   = 0,
		vertexCount    = 0,
		instanceOffset = 0,
	}
	for &model in scene.models {
		for &mesh in model.meshes {
			pushConstants.vertexCount = mesh.vertexCount
			vk.CmdPushConstants2(
				cmdBuffer,
				&vk.PushConstantsInfo {
					sType = .PUSH_CONSTANTS_INFO,
					pNext = nil,
					layout = pipelines[.Scene].layout,
					stageFlags = {.VERTEX, .FRAGMENT},
					offset = 0,
					size = size_of(Scene_PushConstants),
					pValues = &pushConstants,
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
		{RENDER_SIZE.x, RENDER_SIZE.y},
		{swapchain.extent.width, swapchain.extent.height},
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

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[.Buffers].sets[currentFrame],
		descriptorSets[.Textures].sets[currentFrame],
	}
	vk.CmdBindDescriptorSets2(
		cmdBuffer,
		&vk.BindDescriptorSetsInfo {
			sType = .BIND_DESCRIPTOR_SETS_INFO,
			pNext = nil,
			stageFlags = {.COMPUTE},
			layout = pipelines[.PostProcess].layout,
			firstSet = 0,
			descriptorSetCount = len(sets),
			pDescriptorSets = &sets[0],
			dynamicOffsetCount = 0,
			pDynamicOffsets = nil,
		},
	)

	pushConstants: PostProcess_PushConstants = {
		contrast   = contrast,
		brightness = brightness,
		saturation = saturation,
		exposure   = pow(f32(2.0), exposure),
		tonemapper = tonemapper,
		gamma      = gamma,
		drawLights = b32(drawLights),
	}
	vk.CmdPushConstants2(
		cmdBuffer,
		&vk.PushConstantsInfo {
			sType = .PUSH_CONSTANTS_INFO,
			pNext = nil,
			layout = pipelines[.PostProcess].layout,
			stageFlags = {.COMPUTE},
			offset = 0,
			size = size_of(PostProcess_PushConstants),
			pValues = &pushConstants,
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

@(require_results)
drawFrame :: proc(using graphicsData: ^GraphicsData) -> (err: DrawError) {
	vk.WaitForFences(device, 1, &inFlightFrames[currentFrame], true, max(u64))

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
					semaphore = swapchain.presentReady[imageIndex],
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

	presentInfo: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		pNext              = nil,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &swapchain.presentReady[imageIndex],
		swapchainCount     = 1,
		pSwapchains        = &swapchain.handle,
		pImageIndices      = &imageIndex,
		pResults           = nil,
	}

	#partial switch res := vk.QueuePresentKHR(presentQueue, &presentInfo); res {
	case .SUCCESS:
		break
	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		recreateSwapchain(graphicsData)
		return .UpdateCommandBuffers
	case:
		logf(.Error, "Failed to present swapchain image! vkResult: %v", res)
		return .FailedToPresentSwapchainImage
	}

	currentFrame = (currentFrame + 1) % 2
	return nil
}

@(require_results)
waitDeviceIdle :: proc(using graphicsData: ^GraphicsData) -> vk.Result {
	return vk.DeviceWaitIdle(device)
}
