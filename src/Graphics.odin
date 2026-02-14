#+feature using-stmt
package Valhalla

import "../imgui"
import imguiGLFW "../imgui/imgui_impl_glfw"
import imguiVulkan "../imgui/imgui_impl_vulkan"
import "core:mem"
import "core:strings"
import "vendor:glfw"
import img "vendor:stb/image"
import vk "vendor:vulkan"


// ###################################################################
// #                          Constants                              #
// ###################################################################


VERSION: u32 : (0 << 22) | (1 << 12) | (0)

HDR_ENABLED: bool : true

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


// ###################################################################
// #                        Callbacks                               #
// ###################################################################


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


// ###################################################################
// #                           Shader Data                           #
// ###################################################################


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
Post_PushConstants :: struct {
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


// ###################################################################
// #                         Data Structures                         #
// ###################################################################


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
	ImguiError,
	PipelineError,
	BufferError,
	RecordCommandBufferError,
	DrawError,
}

vkDebugMessengerCreateInfo :: vk.DebugUtilsMessengerCreateInfoEXT

@(private = "file")
PipelineIndex :: enum {
	Transform,
	Light,
	Scene,
	PostProcess,
}

@(private = "file")
SemaphoreIndex :: enum {
	Transform = 0,
	Main,
	PostProcess,
	Imgui,
	Image,
}

@(private = "file")
CmdBufferIndex :: enum {
	Transform = 0,
	Main,
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

	// Queues
	queueFamilies:       QueueFamilyIndices,
	graphicsQueue:       vk.Queue,
	presentQueue:        vk.Queue,
	computeQueue:        vk.Queue,

	// Swapchain
	swapchain:           Swapchain,

	// Pipelines
	descriptorSets:      [len(DescriptorSetIndex)]DescriptorSet,
	pipelines:           [len(PipelineIndex)]Pipeline,

	// Frame Resources
	depthFormat:         vk.Format,
	inFlightFrames:      [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	semaphores:          [len(SemaphoreIndex)][MAX_FRAMES_IN_FLIGHT]vk.Semaphore,

	// Commands
	graphicsCommandPool: vk.CommandPool,
	computeCommandPool:  vk.CommandPool,
	commandBuffers:      [len(CmdBufferIndex)][MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	samplers:            []vk.Sampler,

	// Buffer
	uniformBuffers:      [MAX_FRAMES_IN_FLIGHT]Buffer,

	// Util
	currentFrame:        u32,
	drawLights:          bool,
	reloadBuffers:       bool,
	rerecordCommands:    bool,
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
}

@(private = "file")
QueueFamilyIndices :: struct {
	graphicsFamily: u32,
	presentFamily:  u32,
	computeFamily:  u32,
}

Shader :: struct {
	file:       string,
	entryPoint: string,
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
Pipeline :: struct {
	handle:      vk.Pipeline,
	layout:      vk.PipelineLayout,
	images:      []Image,
	descriptor:  vk.DescriptorImageInfo,
	shaderCodes: [][]byte,
}

@(private = "file")
Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	mapped: rawptr,
}

@(private = "file")
Image :: struct {
	vkImage: vk.Image,
	memory:  vk.DeviceMemory,
	view:    vk.ImageView,
	format:  vk.Format,
	sampler: u32,
}

InitGraphicsInfo :: struct {
	appVersion:      u32,
	windowTitle:     cstring,

	// Shaders
	transformComp:   []byte,
	lightVert:       []byte,
	lightFrag:       []byte,
	sceneVert:       []byte,
	sceneFrag:       []byte,
	postProcessComp: []byte,
}

InitError :: enum {
	None = 0,
	InitError,
	GLFWError,
	DepthFormatError,
}

@(require_results)
initVkGraphics :: proc(initInfo: InitGraphicsInfo) -> (graphicsData: GraphicsData, err: Error) {
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
	createSwapchain(&graphicsData)
	createCommandBuffers(&graphicsData) or_return

	bufferSize := size_of(UniformBuffer)
	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if err := createBuffer(
			&graphicsData,
			bufferSize,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&uniformBuffers[index].buffer,
			&uniformBuffers[index].memory,
		); err != nil {
			log(.Fatal, "Failed to create uniform buffer!")
			return graphicsData, err
		}
		vk.MapMemory(
			device,
			uniformBuffers[index].memory,
			0,
			vk.DeviceSize(bufferSize),
			{},
			&uniformBuffers[index].mapped,
		)
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
	createBuffersDescriptorSets(&graphicsData) or_return
	createTexturesDescriptorSets(&graphicsData) or_return

	createSceneImages(&graphicsData) or_return
	pipelines[PipelineIndex.Light].shaderCodes = make([][]byte, 2)
	pipelines[PipelineIndex.Light].shaderCodes[0] = initInfo.lightVert
	pipelines[PipelineIndex.Light].shaderCodes[1] = initInfo.lightFrag
	pipelines[PipelineIndex.Scene].shaderCodes = make([][]byte, 2)
	pipelines[PipelineIndex.Scene].shaderCodes[0] = initInfo.sceneVert
	pipelines[PipelineIndex.Scene].shaderCodes[1] = initInfo.sceneFrag
	createGraphicsPipelines(&graphicsData) or_return

	pipelines[PipelineIndex.Transform].shaderCodes = make([][]byte, 1)
	pipelines[PipelineIndex.Transform].shaderCodes[0] = initInfo.transformComp
	pipelines[PipelineIndex.PostProcess].shaderCodes = make([][]byte, 1)
	pipelines[PipelineIndex.PostProcess].shaderCodes[0] = initInfo.postProcessComp
	createComputePipelines(&graphicsData) or_return

	initImgui(&graphicsData) or_return

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

cleanupVkGraphics :: proc(using graphicsData: ^GraphicsData) {
	if vk.DeviceWaitIdle(device) != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	cleanupImgui(graphicsData)

	vk.FreeCommandBuffers(
		device,
		computeCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[CmdBufferIndex.Transform][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[CmdBufferIndex.Main][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[CmdBufferIndex.Light][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[CmdBufferIndex.Scene][0],
	)
	vk.FreeCommandBuffers(
		device,
		computeCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[CmdBufferIndex.PostProcess][0],
	)
	vk.FreeCommandBuffers(
		device,
		graphicsCommandPool,
		MAX_FRAMES_IN_FLIGHT,
		&commandBuffers[CmdBufferIndex.Imgui][0],
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

	vk.DestroyDevice(device, nil)
	vk.DestroySurfaceKHR(instance, surface, nil)

	if debugMessenger != 0 {
		vk.DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
	}

	vk.DestroyInstance(instance, nil)

	glfw.DestroyWindow(window)
	glfw.Terminate()
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

	features := [?]vk.ValidationFeatureEnableEXT{.GPU_ASSISTED, .SYNCHRONIZATION_VALIDATION}
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
		deviceFeatures: vk.PhysicalDeviceFeatures2 = {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
		}

		vk.GetPhysicalDeviceProperties2(physicalDevice, &deviceProperties)
		vk.GetPhysicalDeviceFeatures2(physicalDevice, &deviceFeatures)

		indices, err := findQueueFamilies(physicalDevice, graphicsData)
		if err ||
		   !deviceFeatures.features.samplerAnisotropy ||
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

	getMaxUsableSampleCount :: proc(physicalDevice: vk.PhysicalDevice) -> vk.SampleCountFlags {
		deviceProperties: vk.PhysicalDeviceProperties2
		vk.GetPhysicalDeviceProperties2(physicalDevice, &deviceProperties)

		counts :=
			deviceProperties.properties.limits.framebufferColorSampleCounts &
			deviceProperties.properties.limits.framebufferDepthSampleCounts
		if ._64 in counts do return {._64}
		if ._32 in counts do return {._32}
		if ._16 in counts do return {._16}
		if ._8 in counts do return {._8}
		if ._4 in counts do return {._4}
		if ._2 in counts do return {._2}
		return {._1}
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

	maintenance7: vk.PhysicalDeviceMaintenance7FeaturesKHR = {
		sType        = .PHYSICAL_DEVICE_MAINTENANCE_7_FEATURES_KHR,
		pNext        = nil,
		maintenance7 = true,
	}

	maintenance5: vk.PhysicalDeviceMaintenance5Features = {
		sType        = .PHYSICAL_DEVICE_MAINTENANCE_5_FEATURES,
		pNext        = &maintenance7,
		maintenance5 = true,
	}

	computeShaderDerivatives: vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR = {
		sType                        = .PHYSICAL_DEVICE_COMPUTE_SHADER_DERIVATIVES_FEATURES_KHR,
		pNext                        = &maintenance5,
		computeDerivativeGroupQuads  = true,
		computeDerivativeGroupLinear = false,
	}

	features14: vk.PhysicalDeviceVulkan14Features = {
		sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
		pNext = &computeShaderDerivatives,
	}

	features13: vk.PhysicalDeviceVulkan13Features = {
		sType                          = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext                          = &features14,
		shaderDemoteToHelperInvocation = true,
		synchronization2               = true,
		dynamicRendering               = true,
	}

	features12: vk.PhysicalDeviceVulkan12Features = {
		sType                     = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext                     = &features13,
		shaderOutputViewportIndex = true,
		shaderOutputLayer         = true,
		timelineSemaphore         = true,
		bufferDeviceAddress       = true,
	}

	features11: vk.PhysicalDeviceVulkan11Features = {
		sType                = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext                = &features12,
		multiview            = true,
		shaderDrawParameters = true,
	}

	features: vk.PhysicalDeviceFeatures2 = {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &features11,
		features = {imageCubeArray = true, samplerAnisotropy = true},
	}

	requiredDeviceExtensions := DEVICE_EXTENSIONS
	createInfo: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features,
		flags                   = {},
		queueCreateInfoCount    = u32(len(queueCreateInfos)),
		pQueueCreateInfos       = raw_data(queueCreateInfos),
		enabledLayerCount       = u32(len(REQUESTED_LAYERS)),
		ppEnabledLayerNames     = raw_data(REQUESTED_LAYERS),
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
createSwapchain :: proc(using graphicsData: ^GraphicsData) {
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
		oldSwapchain          = graphicsData.swapchain.handle,
	}

	if res := vk.CreateSwapchainKHR(device, &createInfo, nil, &swapchain.handle); res != .SUCCESS {
		log(.Fatal, "Failed to create swapchain! vkResult: %v", res)
	}

	swapchain.images = make([]vk.Image, swapchainImageCount)
	vk.GetSwapchainImagesKHR(
		device,
		swapchain.handle,
		&swapchainImageCount,
		raw_data(swapchain.images),
	)

	swapchain.views = make([]vk.ImageView, swapchainImageCount)
	for index in 0 ..< swapchainImageCount {
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

	delete(swapchain.images)
	delete(swapchain.views)

	vk.DestroySwapchainKHR(graphicsData.device, swapchain.handle, nil)
}

@(private = "file")
@(require_results)
recreateSwapchain :: proc(using graphicsData: ^GraphicsData) -> (err: Error) {
	width, height := glfw.GetFramebufferSize(window)
	for width == 0 && height == 0 {
		glfw.WaitEvents()
		width, height = glfw.GetFramebufferSize(window)
	}

	vk.WaitForFences(device, len(inFlightFrames), &inFlightFrames[0], true, max(u64))
	vk.QueueWaitIdle(presentQueue)

	oldSwapchain := swapchain
	createSwapchain(graphicsData)
	cleanupSwapchain(graphicsData, oldSwapchain)

	deleteImage(graphicsData, &pipelines[PipelineIndex.PostProcess].images[0])
	deleteImage(graphicsData, &pipelines[PipelineIndex.PostProcess].images[1])
	createComputeImages(graphicsData) or_return

	updateComputeDescriptorSets(graphicsData)

	cleanupImgui(graphicsData)
	initImgui(graphicsData) or_return

	return nil
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
		&commandBuffers[CmdBufferIndex.Main][0],
	); res != .SUCCESS {
		log(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .SECONDARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[CmdBufferIndex.Light][0],
	); res != .SUCCESS {
		log(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .SECONDARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[CmdBufferIndex.Scene][0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .PRIMARY,
		commandBufferCount = 2,
	}
	if res := vk.AllocateCommandBuffers(
		device,
		&allocInfo,
		&commandBuffers[CmdBufferIndex.Imgui][0],
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
		&commandBuffers[CmdBufferIndex.Transform][0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
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
		&commandBuffers[CmdBufferIndex.PostProcess][0],
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

	submitInfo: vk.SubmitInfo = {
		sType                = .SUBMIT_INFO,
		pNext                = nil,
		waitSemaphoreCount   = 0,
		pWaitSemaphores      = nil,
		pWaitDstStageMask    = nil,
		commandBufferCount   = 1,
		pCommandBuffers      = &commandBuffer,
		signalSemaphoreCount = 0,
		pSignalSemaphores    = nil,
	}
	fence: vk.Fence
	fenceCreateInfo: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		pNext = nil,
		flags = {},
	}
	vk.CreateFence(device, &fenceCreateInfo, nil, &fence)
	vk.QueueSubmit(graphicsQueue, 1, &submitInfo, fence)
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
	buffer: ^vk.Buffer,
	bufferMemory: ^vk.DeviceMemory,
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
	vkDevice := graphicsData.device
	if res := vk.CreateBuffer(vkDevice, &bufferInfo, nil, buffer); res != .SUCCESS {
		logf(.Error, "Failed to create buffer! vkResult: %d", res)
		return .FailedToCreateBuffer
	}

	memRequirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer^, &memRequirements)
	allocInfo: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = nil,
		allocationSize  = memRequirements.size,
		memoryTypeIndex = findMemoryType(graphicsData, memRequirements.memoryTypeBits, properties),
	}
	if res := vk.AllocateMemory(device, &allocInfo, nil, bufferMemory); res != .SUCCESS {
		logf(.Error, "Failed to allocate buffer memory! vkResult: %d", res)
		return .FailedToAllocateBufferMemory
	}

	if res := vk.BindBufferMemory(device, buffer^, bufferMemory^, 0); res != .SUCCESS {
		logf(.Error, "Failed to bind buffer memory! vkResult: %d", res)
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
		&stagingBuffer.buffer,
		&stagingBuffer.memory,
	); err != nil {
		logf(.Error, "Failed to create staging buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}
	defer deleteBuffer(graphicsData, &stagingBuffer)

	data: rawptr
	vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(bufferSize), {}, &data)
	mem.copy(data, srcData, bufferSize)
	vk.UnmapMemory(device, stagingBuffer.memory)

	if err := createBuffer(
		graphicsData,
		bufferSize,
		{.TRANSFER_DST, .STORAGE_BUFFER, bufferType},
		{.DEVICE_LOCAL},
		&dstBuffer.buffer,
		&dstBuffer.memory,
	); err != nil {
		logf(.Error, "Failed to create destination buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}

	commandBuffer, err := beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to begin single time command buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}

	copyRegion: vk.BufferCopy = {
		srcOffset = 0,
		dstOffset = 0,
		size      = vk.DeviceSize(bufferSize),
	}

	vk.CmdCopyBuffer(commandBuffer, stagingBuffer.buffer, dstBuffer.buffer, 1, &copyRegion)
	if err := endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool); err != nil {
		logf(.Error, "Failed to end single time command buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}

	return nil
}

@(private = "file")
deleteBuffer :: proc(using graphicsData: ^GraphicsData, buffer: ^Buffer) {
	vk.DestroyBuffer(device, buffer.buffer, nil)
	vk.FreeMemory(device, buffer.memory, nil)
}

@(private = "file")
findMemoryType :: proc(
	using graphicsData: ^GraphicsData,
	typeFilter: u32,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	memProperties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties)
	for i in 0 ..< memProperties.memoryTypeCount {
		if typeFilter & (1 << i) != 0 &&
		   (memProperties.memoryTypes[i].propertyFlags & properties) == properties {
			return i
		}
	}
	log(.Error, "Failed to find suitable memory type!")
	return 0
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

	memRequirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image.vkImage, &memRequirements)
	allocInfo: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = nil,
		allocationSize  = memRequirements.size,
		memoryTypeIndex = findMemoryType(graphicsData, memRequirements.memoryTypeBits, properties),
	}
	if res := vk.AllocateMemory(device, &allocInfo, nil, &image.memory); res != .SUCCESS {
		logf(.Error, "Failed to allocate image memory! vkResult: %d", res)
		return .FailedToAllocateImageMemory
	}

	if res := vk.BindImageMemory(device, image.vkImage, image.memory, 0); res != .SUCCESS {
		logf(.Error, "Failed to bind image memory! vkResult: %d", res)
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
	barrier: vk.ImageMemoryBarrier = {
		sType = .IMAGE_MEMORY_BARRIER,
		pNext = nil,
		srcAccessMask = {},
		dstAccessMask = {},
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
	}

	sourceStage, destinationStage: vk.PipelineStageFlags
	#partial switch oldLayout {
	case .UNDEFINED:
		barrier.srcAccessMask = {}
		sourceStage = {.TOP_OF_PIPE}
	case .TRANSFER_SRC_OPTIMAL:
		barrier.srcAccessMask = {.TRANSFER_READ}
		sourceStage = {.TRANSFER}
	case .TRANSFER_DST_OPTIMAL:
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		sourceStage = {.TRANSFER}
	case .SHADER_READ_ONLY_OPTIMAL:
		barrier.srcAccessMask = {.SHADER_READ}
		sourceStage = {.FRAGMENT_SHADER}
	case .GENERAL:
		barrier.srcAccessMask = {.SHADER_READ}
		sourceStage = {.COMPUTE_SHADER}
	case:
		log(.Error, "Unsupported image layout transition!")
		return .TransitionFailed
	}

	#partial switch newLayout {
	case .TRANSFER_SRC_OPTIMAL:
		barrier.dstAccessMask = {.TRANSFER_READ}
		destinationStage = {.TRANSFER}
	case .TRANSFER_DST_OPTIMAL:
		barrier.dstAccessMask = {.TRANSFER_WRITE}
		destinationStage = {.TRANSFER}
	case .SHADER_READ_ONLY_OPTIMAL:
		barrier.dstAccessMask = {.SHADER_READ}
		destinationStage = {.FRAGMENT_SHADER}
	case .GENERAL:
		if oldLayout == .TRANSFER_SRC_OPTIMAL {
			barrier.dstAccessMask = {.SHADER_WRITE}
		} else if oldLayout == .TRANSFER_DST_OPTIMAL {
			barrier.dstAccessMask = {.SHADER_READ}
		}
		destinationStage = {.COMPUTE_SHADER}
	case .PRESENT_SRC_KHR:
		barrier.dstAccessMask = {.SHADER_READ}
		destinationStage = {.COMPUTE_SHADER}
	case .COLOR_ATTACHMENT_OPTIMAL:
		barrier.dstAccessMask = {.SHADER_WRITE}
		destinationStage = {.VERTEX_SHADER}
	case:
		log(.Error, "Unsupported image layout transition!")
		return .TransitionFailed
	}

	vk.CmdPipelineBarrier(
		commandBuffer,
		sourceStage,
		destinationStage,
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
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
	region: vk.BufferImageCopy = {
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
	vk.CmdCopyBufferToImage(commandBuffer, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)
}

@(private = "file")
copyBufferToTextureArray :: proc(
	using graphicsData: ^GraphicsData,
	commandBuffer: vk.CommandBuffer,
	buffer: vk.Buffer,
	image: vk.Image,
	width, height, textureCount: u32,
) {
	regions := make([]vk.BufferImageCopy, textureCount)
	defer delete(regions)
	imageSize := width * height * 4
	for &region, index in regions {
		index := u32(index)
		region = {
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
	vk.CmdCopyBufferToImage(
		commandBuffer,
		buffer,
		image,
		.TRANSFER_DST_OPTIMAL,
		u32(len(regions)),
		raw_data(regions),
	)
}

@(private = "file")
copyImage :: proc(
	commandBuffer: vk.CommandBuffer,
	extent: vk.Extent3D,
	srcImage, dstImage: vk.Image,
	srcLayout, dstLayout: vk.ImageLayout,
) {
	region: vk.ImageCopy = {
		srcSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		srcOffset = {x = 0, y = 0, z = 0},
		dstSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		dstOffset = {x = 0, y = 0, z = 0},
		extent = extent,
	}
	vk.CmdCopyImage(commandBuffer, srcImage, srcLayout, dstImage, dstLayout, 1, &region)
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
			&stagingBuffer.buffer,
			&stagingBuffer.memory,
		)
		if err != nil {
			logf(.Error, "Failed to create staging buffer! Error: %v", err)
			return err
		}
		defer {
			deleteBuffer(graphicsData, &stagingBuffer)
		}

		data: rawptr
		vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(textureSize), {}, &data)
		mem.copy(data, pixels, textureSize)
		vk.UnmapMemory(device, stagingBuffer.memory)

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
			vk.FreeMemory(device, stagingImage.memory, nil)
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

	copyInfo: vk.ImageCopy = {
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
	vk.CmdCopyImage(
		commandBuffer,
		image.vkImage,
		.TRANSFER_SRC_OPTIMAL,
		newImage.vkImage,
		.TRANSFER_DST_OPTIMAL,
		1,
		&copyInfo,
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
			&stagingBuffer.buffer,
			&stagingBuffer.memory,
		)
		if err != nil {
			logf(.Error, "Failed to create staging buffer! Error: %v", err)
			return err
		}
		defer {
			deleteBuffer(graphicsData, &stagingBuffer)
		}

		data: rawptr
		vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(textureSize), {}, &data)
		mem.copy(data, pixels, textureSize)
		vk.UnmapMemory(device, stagingBuffer.memory)

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
			vk.FreeMemory(device, stagingImage.memory, nil)
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
	vk.FreeMemory(device, image.memory, nil)
}

@(private = "file")
@(require_results)
updateLightPipelineImages :: proc(
	using graphicsData: ^GraphicsData,
	scene: ^Scene,
) -> (
	err: Error,
) {
	layerCount := u32(len(scene.lights)) * 6
	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.Light].images[0],
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
		log(.Error, "Failed to create shadow map colour image!")
		return err
	}

	pipelines[PipelineIndex.Light].images[0].view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.Light].images[0].vkImage,
		.CUBE_ARRAY,
		pipelines[PipelineIndex.Light].images[0].format,
		{.COLOR},
		layerCount,
	)
	if err != nil {
		log(.Error, "Failed to create shadow map colour image view!")
		return err
	}

	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.Light].images[1],
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
		log(.Error, "Failed to create shadow map depth image!")
		return err
	}

	pipelines[PipelineIndex.Light].images[1].view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.Light].images[1].vkImage,
		.CUBE_ARRAY,
		pipelines[PipelineIndex.Light].images[1].format,
		{.DEPTH},
		layerCount,
	)
	if err != nil {
		log(.Error, "Failed to create shadow map depth image view!")
		return err
	}

	cmdBuffer, cerr := beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if cerr != nil {
		log(.Error, "Failed to start commands! %v", cerr)
		return cerr
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
			image = pipelines[PipelineIndex.Light].images[0].vkImage,
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
			image = pipelines[PipelineIndex.Light].images[1].vkImage,
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

	cerr = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
	if cerr != nil {
		log(.Error, "Failed to submit commands! %v", cerr)
		return cerr
	}

	return
}

@(require_results)
updateSceneBuffers :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) -> Error {
	buffers := &scene.buffers
	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	if err := loadBufferToGPU(
		graphicsData,
		size_of(Vertex) * len(scene.vertices),
		raw_data(scene.vertices),
		&buffers.vertexBuffer,
		.VERTEX_BUFFER,
	); err != nil {
		logf(.Error, "Failed to load vertex buffer! Error: %v", err)
		return err
	}

	if err := loadBufferToGPU(
		graphicsData,
		size_of(u32) * len(scene.indices),
		raw_data(scene.indices),
		&buffers.indexBuffer,
		.INDEX_BUFFER,
	); err != nil {
		logf(.Error, "Failed to load index buffer! Error: %v", err)
		return err
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
		if err := createBuffer(
			graphicsData,
			instanceBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&buffers.instanceBuffers[i].buffer,
			&buffers.instanceBuffers[i].memory,
		); err != nil {
			logf(.Error, "Failed to create instance buffer! Error: %v", err)
			return err
		}
		vk.MapMemory(
			graphicsData.device,
			buffers.instanceBuffers[i].memory,
			0,
			vk.DeviceSize(instanceBufferSize),
			{},
			&buffers.instanceBuffers[i].mapped,
		)

		deleteBuffer(graphicsData, &buffers.boneBuffers[i])
		if err := createBuffer(
			graphicsData,
			boneBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&buffers.boneBuffers[i].buffer,
			&buffers.boneBuffers[i].memory,
		); err != nil {
			logf(.Error, "Failed to create bone buffer! Error: %v", err)
			return err
		}
		vk.MapMemory(
			graphicsData.device,
			buffers.boneBuffers[i].memory,
			0,
			vk.DeviceSize(boneBufferSize),
			{},
			&buffers.boneBuffers[i].mapped,
		)

		deleteBuffer(graphicsData, &buffers.lightBuffers[i])
		if err := createBuffer(
			graphicsData,
			lightBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&buffers.lightBuffers[i].buffer,
			&buffers.lightBuffers[i].memory,
		); err != nil {
			logf(.Error, "Failed to create light buffer! Error: %v", err)
			return err
		}
		vk.MapMemory(
			graphicsData.device,
			buffers.lightBuffers[i].memory,
			0,
			vk.DeviceSize(lightBufferSize),
			{},
			&buffers.lightBuffers[i].mapped,
		)

		deleteBuffer(graphicsData, &buffers.transformBuffers[i])
		if err := createBuffer(
			graphicsData,
			int(transformBufferSize),
			{.STORAGE_BUFFER},
			{.DEVICE_LOCAL},
			&buffers.transformBuffers[i].buffer,
			&buffers.transformBuffers[i].memory,
		); err != nil {
			logf(.Error, "Failed to create transform buffer! Error: %v", err)
			return err
		}
	}

	deleteBuffer(graphicsData, &buffers.textureIndexBuffer)
	if err := createBuffer(
		graphicsData,
		textureIndexSize,
		{.STORAGE_BUFFER},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&buffers.textureIndexBuffer.buffer,
		&buffers.textureIndexBuffer.memory,
	); err != nil {
		logf(.Error, "Failed to create transform buffer! Error: %v", err)
		return err
	}
	vk.MapMemory(
		graphicsData.device,
		buffers.textureIndexBuffer.memory,
		0,
		vk.DeviceSize(textureIndexSize),
		{},
		&buffers.textureIndexBuffer.mapped,
	)
	updateTextureIndexBuffer(graphicsData, scene)

	if err := updateLightPipelineImages(graphicsData, scene); err != nil {
		logf(.Error, "Failed to create shadow images! Error: %v", err)
		return err
	}

	if err := updateDescriptorSets(graphicsData, scene); err != nil {
		logf(.Error, "Failed to update descriptor sets! Error: %v", err)
		return err
	}

	if err := updateCommandBuffers(graphicsData, scene); err != nil {
		logf(.Error, "Failed to update command buffers! Error: %v", err)
		return err
	}

	return nil
}

DescriptorSetError :: enum {
	None = 0,
	FailedToCreateDescriptorPool,
	FailedToCreateDescriptorSetLayout,
	FailedToCreateDescriptorSet,
	FailedToAllocateDescriptorSets,
}

@(private = "file")
@(require_results)
createBuffersDescriptorSets :: proc(using graphicsData: ^GraphicsData) -> DescriptorSetError {
	layoutBindings: []vk.DescriptorSetLayoutBinding = {
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
		pBindings    = raw_data(layoutBindings),
	}

	if res := vk.CreateDescriptorSetLayout(
		device,
		&layoutInfo,
		nil,
		&descriptorSets[DescriptorSetIndex.Buffers].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor set layout! vkResult: %d", res)
		return .FailedToCreateDescriptorSetLayout
	}

	poolSizes: []vk.DescriptorPoolSize = {
		{type = .UNIFORM_BUFFER, descriptorCount = 1 * 2},
		{type = .STORAGE_BUFFER, descriptorCount = 7 * 2},
	}

	poolInfo: vk.DescriptorPoolCreateInfo = {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		pNext         = nil,
		flags         = {},
		maxSets       = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = raw_data(poolSizes),
	}

	if res := vk.CreateDescriptorPool(
		device,
		&poolInfo,
		nil,
		&descriptorSets[DescriptorSetIndex.Buffers].pool,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor pool! vkResult: %d", res)
		return .FailedToCreateDescriptorPool
	}

	layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT, context.temp_allocator)
	for &layout in layouts {
		layout = descriptorSets[DescriptorSetIndex.Buffers].layout
	}

	allocInfo: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = descriptorSets[DescriptorSetIndex.Buffers].pool,
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts),
	}

	if res := vk.AllocateDescriptorSets(
		device,
		&allocInfo,
		raw_data(descriptorSets[DescriptorSetIndex.Buffers].sets[:]),
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate descriptor sets! vkResult %v", res)
		return .FailedToAllocateDescriptorSets
	}

	return .None
}

@(private = "file")
@(require_results)
createTexturesDescriptorSets :: proc(using graphicsData: ^GraphicsData) -> DescriptorSetError {
	layoutBindings: []vk.DescriptorSetLayoutBinding = {
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
		pBindings    = raw_data(layoutBindings),
	}

	if res := vk.CreateDescriptorSetLayout(
		device,
		&layoutInfo,
		nil,
		&descriptorSets[DescriptorSetIndex.Textures].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor set layout! vkResult: %d", res)
		return .FailedToCreateDescriptorSetLayout
	}

	poolSizes: []vk.DescriptorPoolSize = {
		{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 3 * 2},
		{type = .STORAGE_IMAGE, descriptorCount = 2 * 2},
	}

	poolInfo: vk.DescriptorPoolCreateInfo = {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		pNext         = nil,
		flags         = {},
		maxSets       = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = raw_data(poolSizes),
	}

	if res := vk.CreateDescriptorPool(
		device,
		&poolInfo,
		nil,
		&descriptorSets[DescriptorSetIndex.Textures].pool,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor pool! vkResult: %d", res)
		return .FailedToCreateDescriptorPool
	}

	layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT, context.temp_allocator)
	for &layout in layouts {
		layout = descriptorSets[DescriptorSetIndex.Textures].layout
	}

	allocInfo: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = descriptorSets[DescriptorSetIndex.Textures].pool,
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts),
	}

	if res := vk.AllocateDescriptorSets(
		device,
		&allocInfo,
		raw_data(descriptorSets[DescriptorSetIndex.Textures].sets[:]),
	); res != .SUCCESS {
		logf(.Fatal, "Failed to allocate descriptor sets! vkResult: %d", res)
		return .FailedToAllocateDescriptorSets
	}

	return .None
}

@(private = "file")
@(require_results)
updateDescriptorSets :: proc(
	using graphicsData: ^GraphicsData,
	scene: ^Scene,
) -> (
	err: ImageError,
) {
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
		sampler     = samplers[pipelines[PipelineIndex.Light].images[0].sampler],
		imageView   = pipelines[PipelineIndex.Light].images[0].view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	sceneDepthInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[pipelines[PipelineIndex.Scene].images[1].sampler],
		imageView   = pipelines[PipelineIndex.Scene].images[1].view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	renderedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[PipelineIndex.PostProcess].images[0].view,
		imageLayout = .GENERAL,
	}

	processedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[PipelineIndex.PostProcess].images[1].view,
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Buffers].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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

	return .None
}

@(private = "file")
updateComputeDescriptorSets :: proc(using graphicsData: ^GraphicsData) {
	sceneDepthInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[pipelines[PipelineIndex.Scene].images[1].sampler],
		imageView   = pipelines[PipelineIndex.Scene].images[1].view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	renderedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[PipelineIndex.PostProcess].images[0].view,
		imageLayout = .GENERAL,
	}

	processedImageInfo: vk.DescriptorImageInfo = {
		imageView   = pipelines[PipelineIndex.PostProcess].images[1].view,
		imageLayout = .GENERAL,
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.Textures].sets[index],
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

PipelineError :: enum {
	None = 0,
	FailedToCreatePipelineLayout,
	FailedToCreateGraphicsPipeline,
	FailedToCreateComputePipeline,
	FailedToCreateShaderModule,
}

@(private = "file")
@(require_results)
createSceneImages :: proc(using graphicsData: ^GraphicsData) -> (err: Error) {
	pipelines[PipelineIndex.Scene].images = make([]Image, 2)
	pipelines[PipelineIndex.Scene].images[0].format = .R16G16B16A16_SFLOAT

	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.Scene].images[0],
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
		return
	}

	pipelines[PipelineIndex.Scene].images[0].view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.Scene].images[0].vkImage,
		.D2,
		pipelines[PipelineIndex.Scene].images[0].format,
		{.COLOR},
		1,
	)
	if err != nil {
		log(.Fatal, "Failed to create colour image view!")
		return
	}

	pipelines[PipelineIndex.Scene].images[1].format = depthFormat

	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.Scene].images[1],
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
		return
	}

	pipelines[PipelineIndex.Scene].images[1].view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.Scene].images[1].vkImage,
		.D2,
		pipelines[PipelineIndex.Scene].images[1].format,
		{.DEPTH},
		1,
	)
	if err != nil {
		log(.Fatal, "Failed to create depth image view!")
		return
	}

	pipelines[PipelineIndex.Scene].images[1].sampler = 0

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to start commands! %v", err)
		return
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
			image = pipelines[PipelineIndex.Scene].images[0].vkImage,
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
			image = pipelines[PipelineIndex.Scene].images[1].vkImage,
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
		return
	}

	return
}

@(private = "file")
@(require_results)
createGraphicsPipelines :: proc(
	using graphicsData: ^GraphicsData,
	pipelineCache: vk.PipelineCache = 0,
) -> Error {
	PIPELINE_COUNT: u32 : 2
	pipelineInfos: [PIPELINE_COUNT]vk.GraphicsPipelineCreateInfo

	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[DescriptorSetIndex.Buffers].layout,
		descriptorSets[DescriptorSetIndex.Textures].layout,
	}

	pipelines[PipelineIndex.Light].images = make([]Image, 2)
	pipelines[PipelineIndex.Light].images[0].format = .R16G16B16A16_SFLOAT
	pipelines[PipelineIndex.Light].images[1].format = depthFormat

	vertexBindingDescription := VERTEX_BINDING_DESCRIPTION

	// SHADOW PIPELINE
	shadowPushConstants: vk.PushConstantRange = {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = size_of(Light_PushConstants),
	}

	shadowPipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &shadowPushConstants,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&shadowPipelineLayoutInfo,
		nil,
		&pipelines[PipelineIndex.Light].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline layout! vkResult: %d", res)
		return .FailedToCreatePipelineLayout
	}

	shadowShaderStagesInfo: [2]vk.PipelineShaderStageCreateInfo = {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
				sType = .SHADER_MODULE_CREATE_INFO,
				pNext = nil,
				flags = nil,
				codeSize = len(pipelines[PipelineIndex.Light].shaderCodes[0]),
				pCode = transmute(^u32)raw_data(pipelines[PipelineIndex.Light].shaderCodes[0]),
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
				codeSize = len(pipelines[PipelineIndex.Light].shaderCodes[1]),
				pCode = transmute(^u32)raw_data(pipelines[PipelineIndex.Light].shaderCodes[1]),
			},
			flags = nil,
			stage = {.FRAGMENT},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
	}

	pipelineInfos[0] = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &vk.PipelineRenderingCreateInfo {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			pNext = nil,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &pipelines[PipelineIndex.Light].images[0].format,
			depthAttachmentFormat = pipelines[PipelineIndex.Light].images[1].format,
			stencilAttachmentFormat = .UNDEFINED,
		},
		flags               = nil,
		stageCount          = u32(len(shadowShaderStagesInfo)),
		pStages             = &shadowShaderStagesInfo[0],
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
		layout              = pipelines[PipelineIndex.Light].layout,
		renderPass          = 0,
		subpass             = 0,
		basePipelineHandle  = {},
		basePipelineIndex   = 0,
	}

	// MAIN PIPELINE
	mainPushConstant: vk.PushConstantRange = {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = size_of(Scene_PushConstants),
	}

	mainPipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &mainPushConstant,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&mainPipelineLayoutInfo,
		nil,
		&pipelines[PipelineIndex.Scene].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline layout! vkResult: %d", res)
		return .FailedToCreatePipelineLayout
	}

	mainShaderStagesInfo: [2]vk.PipelineShaderStageCreateInfo = {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &vk.ShaderModuleCreateInfo {
				sType = .SHADER_MODULE_CREATE_INFO,
				pNext = nil,
				flags = nil,
				codeSize = len(pipelines[PipelineIndex.Scene].shaderCodes[0]),
				pCode = transmute(^u32)raw_data(pipelines[PipelineIndex.Scene].shaderCodes[0]),
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
				codeSize = len(pipelines[PipelineIndex.Scene].shaderCodes[1]),
				pCode = transmute(^u32)raw_data(pipelines[PipelineIndex.Scene].shaderCodes[1]),
			},
			flags = nil,
			stage = {.FRAGMENT},
			module = 0,
			pName = "main",
			pSpecializationInfo = nil,
		},
	}

	pipelineInfos[1] = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &vk.PipelineRenderingCreateInfo {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			pNext = nil,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &pipelines[PipelineIndex.Scene].images[0].format,
			depthAttachmentFormat = pipelines[PipelineIndex.Scene].images[1].format,
			stencilAttachmentFormat = .UNDEFINED,
		},
		flags               = nil,
		stageCount          = u32(len(mainShaderStagesInfo)),
		pStages             = &mainShaderStagesInfo[0],
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
		layout              = pipelines[PipelineIndex.Scene].layout,
		renderPass          = 0,
		subpass             = 0,
		basePipelineHandle  = {},
		basePipelineIndex   = 0,
	}

	vkPipelines: [PIPELINE_COUNT]vk.Pipeline
	if res := vk.CreateGraphicsPipelines(
		device,
		pipelineCache,
		PIPELINE_COUNT,
		&pipelineInfos[0],
		nil,
		&vkPipelines[0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! %v", res)
		return .FailedToCreateGraphicsPipeline
	}

	pipelines[PipelineIndex.Light].handle = vkPipelines[0]
	pipelines[PipelineIndex.Scene].handle = vkPipelines[1]
	return nil
}

@(private = "file")
createComputeImages :: proc(using graphicsData: ^GraphicsData) -> (err: Error) {
	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.PostProcess].images[0],
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
		log(.Fatal, "Failed to create rendered image! %v", err)
		return err
	}

	pipelines[PipelineIndex.PostProcess].images[0].view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.PostProcess].images[0].vkImage,
		.D2,
		pipelines[PipelineIndex.PostProcess].images[0].format,
		{.COLOR},
		1,
	)
	if err != nil {
		log(.Fatal, "Failed to create rendered image view! %v", err)
		return err
	}

	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.PostProcess].images[1],
		{},
		.D2,
		swapchain.extent.width,
		swapchain.extent.height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_SRC, .STORAGE, .COLOR_ATTACHMENT},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		log(.Fatal, "Failed to create processed image! %v", err)
		return err
	}

	pipelines[PipelineIndex.PostProcess].images[1].view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.PostProcess].images[1].vkImage,
		.D2,
		pipelines[PipelineIndex.PostProcess].images[1].format,
		{.COLOR},
		1,
	)
	if err != nil {
		log(.Fatal, "Failed to create processed image view! %v", err)
		return err
	}

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, computeCommandPool)
	if err != nil {
		log(.Fatal, "Failed to start commands! %v", err)
		return err
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
			image = pipelines[PipelineIndex.PostProcess].images[0].vkImage,
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
			image = pipelines[PipelineIndex.PostProcess].images[1].vkImage,
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

	err = endSingleTimeCommands(graphicsData, cmdBuffer, computeCommandPool)
	if err != nil {
		log(.Fatal, "Failed to submit commands! %v", err)
		return err
	}

	return nil
}

@(private = "file")
@(require_results)
createComputePipelines :: proc(
	using graphicsData: ^GraphicsData,
	pipelineCache: vk.PipelineCache = 0,
) -> Error {
	PIPELINE_COUNT: u32 : 2
	pipelineInfos: [PIPELINE_COUNT]vk.ComputePipelineCreateInfo

	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[DescriptorSetIndex.Buffers].layout,
		descriptorSets[DescriptorSetIndex.Textures].layout,
	}

	// TRANSFORM COMPUTE
	transformPushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = size_of(Transform_PushConstants),
	}

	transformPipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &transformPushConstants,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&transformPipelineLayoutInfo,
		nil,
		&pipelines[PipelineIndex.Transform].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create precompute pipeline layout! vkResult: %d", res)
		return .FailedToCreatePipelineLayout
	}

	transformShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = &vk.ShaderModuleCreateInfo {
			sType = .SHADER_MODULE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			codeSize = len(pipelines[PipelineIndex.Transform].shaderCodes[0]),
			pCode = transmute(^u32)raw_data(pipelines[PipelineIndex.Transform].shaderCodes[0]),
		},
		flags               = nil,
		stage               = {.COMPUTE},
		module              = 0,
		pName               = "main",
		pSpecializationInfo = nil,
	}

	pipelineInfos[0] = {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = nil,
		flags              = {},
		stage              = transformShaderStageInfo,
		layout             = pipelines[PipelineIndex.Transform].layout,
		basePipelineHandle = {},
		basePipelineIndex  = 0,
	}

	// POSTPROCESS
	pipelines[PipelineIndex.PostProcess].images = make([]Image, 2)
	pipelines[PipelineIndex.PostProcess].images[0].format = .R16G16B16A16_SFLOAT
	ierr := createImage(
		graphicsData,
		&pipelines[PipelineIndex.PostProcess].images[0],
		{},
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
	if ierr != .None {
		logf(.Fatal, "Failed to create image! Error: %v", ierr)
		return ierr
	}

	pipelines[PipelineIndex.PostProcess].images[0].view, ierr = createImageView(
		graphicsData,
		pipelines[PipelineIndex.PostProcess].images[0].vkImage,
		.D2,
		pipelines[PipelineIndex.PostProcess].images[0].format,
		{.COLOR},
		1,
	)
	if ierr != .None {
		logf(.Fatal, "Failed to create image view for rendered image! Error: %v", ierr)
		return ierr
	}

	pipelines[PipelineIndex.PostProcess].images[1].format = .R16G16B16A16_SFLOAT
	ierr = createImage(
		graphicsData,
		&pipelines[PipelineIndex.PostProcess].images[1],
		{},
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
	if ierr != .None {
		logf(.Fatal, "Failed to create processed image! Error: %v", ierr)
		return ierr
	}

	pipelines[PipelineIndex.PostProcess].images[1].view, ierr = createImageView(
		graphicsData,
		pipelines[PipelineIndex.PostProcess].images[1].vkImage,
		.D2,
		pipelines[PipelineIndex.PostProcess].images[1].format,
		{.COLOR},
		1,
	)
	if ierr != .None {
		logf(.Fatal, "Failed to create image view for processed image! Error: %v", ierr)
		return ierr
	}

	cmdBuffer, cerr := beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if cerr != nil {
		log(.Error, "Failed to start commands! %v", cerr)
		return cerr
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
			image = pipelines[PipelineIndex.PostProcess].images[0].vkImage,
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
			image = pipelines[PipelineIndex.PostProcess].images[1].vkImage,
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

	cerr = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
	if cerr != nil {
		log(.Error, "Failed to submit commands! %v", cerr)
		return cerr
	}

	postPushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = size_of(Post_PushConstants),
	}

	postPipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &postPushConstants,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&postPipelineLayoutInfo,
		nil,
		&pipelines[PipelineIndex.PostProcess].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create postprocess pipeline layout! vkResult: %v", res)
		return .FailedToCreatePipelineLayout
	}

	postShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = &vk.ShaderModuleCreateInfo {
			sType = .SHADER_MODULE_CREATE_INFO,
			pNext = nil,
			flags = nil,
			codeSize = len(pipelines[PipelineIndex.PostProcess].shaderCodes[0]),
			pCode = transmute(^u32)raw_data(pipelines[PipelineIndex.PostProcess].shaderCodes[0]),
		},
		flags               = nil,
		stage               = {.COMPUTE},
		module              = 0,
		pName               = "main",
		pSpecializationInfo = nil,
	}
	defer vk.DestroyShaderModule(device, postShaderStageInfo.module, nil)

	pipelineInfos[1] = {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = nil,
		flags              = nil,
		stage              = postShaderStageInfo,
		layout             = pipelines[PipelineIndex.PostProcess].layout,
		basePipelineHandle = {},
		basePipelineIndex  = 0,
	}

	vkPipelines: [PIPELINE_COUNT]vk.Pipeline
	if res := vk.CreateComputePipelines(
		device,
		pipelineCache,
		PIPELINE_COUNT,
		&pipelineInfos[0],
		nil,
		&vkPipelines[0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! vkResult: %v", res)
		return .FailedToCreateGraphicsPipeline
	}

	pipelines[PipelineIndex.Transform].handle = vkPipelines[0]
	pipelines[PipelineIndex.PostProcess].handle = vkPipelines[1]
	return nil
}

@(private = "file")
cleanupPipeline :: proc(using graphicsData: ^GraphicsData, pipeline: ^Pipeline) {
	vk.DestroyPipeline(device, pipeline.handle, nil)
	vk.DestroyPipelineLayout(device, pipeline.layout, nil)
	delete(pipeline.shaderCodes)
}

changePipelineShader :: proc(
	using graphicsData: ^GraphicsData,
	pipeline: PipelineIndex,
	indices: u32,
) {
	// TODO: Implement shader reloading for individual pipelines
	// pipelines[pipeline].indices = indices
}

ImguiError :: enum {
	None = 0,
	Version,
	FailedToInitializeImgui,
}

@(private = "file")
@(require_results)
initImgui :: proc(using graphicsData: ^GraphicsData) -> Error {
	if !imgui.CHECKVERSION() {
		log(.Fatal, "Wrong imgui version!")
		return ImguiError.Version
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
		return .FailedToInitializeImgui
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
				pColorAttachmentFormats = &pipelines[PipelineIndex.PostProcess].images[1].format,
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
		return .FailedToInitializeImgui
	}

	return nil
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

RecordCommandBufferError :: enum {
	None = 0,
	FailedToRecordCommandBuffer,
}

@(require_results)
updateCommandBuffers :: proc(
	using graphicsData: ^GraphicsData,
	scene: ^Scene,
) -> RecordCommandBufferError {
	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		logf(.Error, "Failed to wait for device idle! vkResult: %v", res)
		panic("Idk why this would ever fail.")
	}

	for bufferIndex in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Transform][bufferIndex], {})
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Light][bufferIndex], {})
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Scene][bufferIndex], {})
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Main][bufferIndex], {})
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Transform][bufferIndex], {})

		recordTransformCommands(graphicsData, bufferIndex, scene) or_return
		recordLightCommands(graphicsData, bufferIndex, scene) or_return
		recordSceneCommands(graphicsData, bufferIndex, scene) or_return
		recordMainCommands(graphicsData, bufferIndex, scene) or_return
		recordPostProcessCommands(graphicsData, bufferIndex) or_return
	}

	return nil
}

@(private = "file")
@(require_results)
recordTransformCommands :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
	scene: ^Scene,
) -> RecordCommandBufferError {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}
	cmdBuffer := commandBuffers[CmdBufferIndex.Transform][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[DescriptorSetIndex.Buffers].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.Textures].sets[currentFrame],
	}
	vk.CmdBindDescriptorSets(
		cmdBuffer,
		.COMPUTE,
		pipelines[PipelineIndex.Transform].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)
	vk.CmdBindPipeline(cmdBuffer, .COMPUTE, pipelines[PipelineIndex.Transform].handle)

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
				layout = pipelines[PipelineIndex.Transform].layout,
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
					layout = pipelines[PipelineIndex.Transform].layout,
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

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	return .None
}

@(private = "file")
@(require_results)
recordMainCommands :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
	scene: ^Scene,
) -> RecordCommandBufferError {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = nil,
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[CmdBufferIndex.Main][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
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
				srcStageMask = nil,
				srcAccessMask = nil,
				dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
				dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
				oldLayout = .SHADER_READ_ONLY_OPTIMAL,
				newLayout = .COLOR_ATTACHMENT_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = pipelines[PipelineIndex.Light].images[0].vkImage,
				subresourceRange = vk.ImageSubresourceRange {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = u32(len(scene.lights)) * 6,
				},
			},
		},
	)

	vk.CmdBeginRendering(
		cmdBuffer,
		&vk.RenderingInfo {
			sType = .RENDERING_INFO,
			pNext = nil,
			flags = {.CONTENTS_SECONDARY_COMMAND_BUFFERS, .CONTENTS_INLINE_KHR},
			renderArea = vk.Rect2D {
				offset = {0, 0},
				extent = {SHADOW_RESOLUTION.x, SHADOW_RESOLUTION.y},
			},
			layerCount = u32(len(scene.lights)) * 6,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachments = &vk.RenderingAttachmentInfo {
				sType = .RENDERING_ATTACHMENT_INFO,
				pNext = nil,
				imageView = pipelines[PipelineIndex.Light].images[0].view,
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
				imageView = pipelines[PipelineIndex.Light].images[1].view,
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
	vk.CmdExecuteCommands(cmdBuffer, 1, &commandBuffers[CmdBufferIndex.Light][index])
	vk.CmdEndRendering(cmdBuffer)

	imageBarriers3 := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
			dstStageMask = {.FRAGMENT_SHADER},
			dstAccessMask = {.SHADER_READ},
			oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
			newLayout = .SHADER_READ_ONLY_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[PipelineIndex.Light].images[0].vkImage,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = u32(len(scene.lights)) * 6,
			},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
			oldLayout = .TRANSFER_SRC_OPTIMAL,
			newLayout = .COLOR_ATTACHMENT_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[PipelineIndex.Scene].images[0].vkImage,
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
			dstStageMask = {.EARLY_FRAGMENT_TESTS},
			dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
			oldLayout = .SHADER_READ_ONLY_OPTIMAL,
			newLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[PipelineIndex.Scene].images[1].vkImage,
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
			imageMemoryBarrierCount = len(imageBarriers3),
			pImageMemoryBarriers = &imageBarriers3[0],
		},
	)

	vk.CmdBeginRendering(
		cmdBuffer,
		&vk.RenderingInfo {
			sType = .RENDERING_INFO,
			pNext = nil,
			flags = {.CONTENTS_SECONDARY_COMMAND_BUFFERS, .CONTENTS_INLINE_KHR},
			renderArea = vk.Rect2D{offset = {0, 0}, extent = {RENDER_SIZE.x, RENDER_SIZE.y}},
			layerCount = 1,
			viewMask = 0,
			colorAttachmentCount = 1,
			pColorAttachments = &vk.RenderingAttachmentInfo {
				sType = .RENDERING_ATTACHMENT_INFO,
				pNext = nil,
				imageView = pipelines[PipelineIndex.Scene].images[0].view,
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
				imageView = pipelines[PipelineIndex.Scene].images[1].view,
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
	vk.CmdExecuteCommands(cmdBuffer, 1, &commandBuffers[CmdBufferIndex.Scene][index])
	vk.CmdEndRendering(cmdBuffer)

	imageBarriers2 := [?]vk.ImageMemoryBarrier2 {
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
			image = pipelines[PipelineIndex.Scene].images[0].vkImage,
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
			dstStageMask = {.FRAGMENT_SHADER},
			dstAccessMask = {.SHADER_READ},
			oldLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			newLayout = .SHADER_READ_ONLY_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[PipelineIndex.Scene].images[1].vkImage,
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
			imageMemoryBarrierCount = len(imageBarriers2),
			pImageMemoryBarriers = &imageBarriers2[0],
		},
	)

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordLightCommands :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
	scene: ^Scene,
) -> RecordCommandBufferError {
	lightCount := u32(len(scene.lights))
	lightImageCount := lightCount * 6

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.RENDER_PASS_CONTINUE},
		pInheritanceInfo = &vk.CommandBufferInheritanceInfo {
			sType = .COMMAND_BUFFER_INHERITANCE_INFO,
			pNext = &vk.CommandBufferInheritanceRenderingInfo {
				sType = .COMMAND_BUFFER_INHERITANCE_RENDERING_INFO,
				pNext = nil,
				flags = nil,
				viewMask = 0,
				colorAttachmentCount = 1,
				pColorAttachmentFormats = &pipelines[PipelineIndex.Light].images[0].format,
				depthAttachmentFormat = pipelines[PipelineIndex.Light].images[1].format,
				stencilAttachmentFormat = .UNDEFINED,
				rasterizationSamples = {._1},
			},
			renderPass = 0,
			subpass = 0,
			framebuffer = 0,
			occlusionQueryEnable = false,
			queryFlags = nil,
			pipelineStatistics = nil,
		},
	}

	cmdBuffer := commandBuffers[CmdBufferIndex.Light][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[PipelineIndex.Light].handle)

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[DescriptorSetIndex.Buffers].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.Textures].sets[currentFrame],
	}

	vk.CmdBindDescriptorSets(
		cmdBuffer,
		.GRAPHICS,
		pipelines[PipelineIndex.Light].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)

	vk.CmdBindVertexBuffers(
		cmdBuffer,
		0,
		1,
		&scene.buffers.vertexBuffer.buffer,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer(cmdBuffer, scene.buffers.indexBuffer.buffer, 0, .UINT32)

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
				layout = pipelines[PipelineIndex.Light].layout,
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
						layout = pipelines[PipelineIndex.Light].layout,
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

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordSceneCommands :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
	scene: ^Scene,
) -> RecordCommandBufferError {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.RENDER_PASS_CONTINUE},
		pInheritanceInfo = &vk.CommandBufferInheritanceInfo {
			sType = .COMMAND_BUFFER_INHERITANCE_INFO,
			pNext = &vk.CommandBufferInheritanceRenderingInfo {
				sType = .COMMAND_BUFFER_INHERITANCE_RENDERING_INFO,
				pNext = nil,
				flags = nil,
				viewMask = 0,
				colorAttachmentCount = 1,
				pColorAttachmentFormats = &pipelines[PipelineIndex.Scene].images[0].format,
				depthAttachmentFormat = pipelines[PipelineIndex.Scene].images[1].format,
				stencilAttachmentFormat = .UNDEFINED,
				rasterizationSamples = {._1},
			},
			renderPass = 0,
			subpass = 0,
			framebuffer = 0,
			occlusionQueryEnable = false,
			queryFlags = {},
			pipelineStatistics = {},
		},
	}

	cmdBuffer := commandBuffers[CmdBufferIndex.Scene][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[DescriptorSetIndex.Buffers].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.Textures].sets[currentFrame],
	}

	vk.CmdBindDescriptorSets(
		cmdBuffer,
		.GRAPHICS,
		pipelines[PipelineIndex.Scene].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)
	vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[PipelineIndex.Scene].handle)

	vk.CmdBindVertexBuffers(
		cmdBuffer,
		0,
		1,
		&scene.buffers.vertexBuffer.buffer,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer(cmdBuffer, scene.buffers.indexBuffer.buffer, 0, .UINT32)

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
					layout = pipelines[PipelineIndex.Scene].layout,
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

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordPostProcessCommands :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
) -> RecordCommandBufferError {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[CmdBufferIndex.PostProcess][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to start recording compute commands! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	imageBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = {.TOP_OF_PIPE},
			srcAccessMask = nil,
			dstStageMask = {.BLIT},
			dstAccessMask = {.TRANSFER_WRITE},
			oldLayout = .GENERAL,
			newLayout = .TRANSFER_DST_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[PipelineIndex.PostProcess].images[0].vkImage,
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
			dstStageMask = {.COMPUTE_SHADER},
			dstAccessMask = {.SHADER_STORAGE_WRITE},
			oldLayout = .TRANSFER_SRC_OPTIMAL,
			newLayout = .GENERAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[PipelineIndex.PostProcess].images[1].vkImage,
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
		pipelines[PipelineIndex.Scene].images[0].vkImage,
		pipelines[PipelineIndex.PostProcess].images[0].vkImage,
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
				image = pipelines[PipelineIndex.PostProcess].images[0].vkImage,
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
		descriptorSets[DescriptorSetIndex.Buffers].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.Textures].sets[currentFrame],
	}
	vk.CmdBindDescriptorSets(
		cmdBuffer,
		.COMPUTE,
		pipelines[PipelineIndex.PostProcess].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)

	pushConstants: Post_PushConstants = {
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
			layout = pipelines[PipelineIndex.PostProcess].layout,
			stageFlags = {.COMPUTE},
			offset = 0,
			size = size_of(Post_PushConstants),
			pValues = &pushConstants,
		},
	)

	vk.CmdBindPipeline(cmdBuffer, .COMPUTE, pipelines[PipelineIndex.PostProcess].handle)

	vk.CmdDispatch(
		cmdBuffer,
		u32(ceil(f32(swapchain.extent.width) / 32)),
		u32(ceil(f32(swapchain.extent.height) / 32)),
		1,
	)

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Error, "Failed to record compute command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordImguiCommands :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
	imageIndex: u32,
) -> RecordCommandBufferError {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = nil,
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[CmdBufferIndex.Imgui][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
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
				srcStageMask = {.TOP_OF_PIPE},
				srcAccessMask = nil,
				dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
				dstAccessMask = {.COLOR_ATTACHMENT_READ},
				oldLayout = .GENERAL,
				newLayout = .COLOR_ATTACHMENT_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = pipelines[PipelineIndex.PostProcess].images[1].vkImage,
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
			flags = {.CONTENTS_SECONDARY_COMMAND_BUFFERS, .CONTENTS_INLINE_KHR},
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
				imageView = pipelines[PipelineIndex.PostProcess].images[1].view,
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
			image = pipelines[PipelineIndex.PostProcess].images[1].vkImage,
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
			srcImage = pipelines[PipelineIndex.PostProcess].images[1].vkImage,
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
				dstStageMask = {.BOTTOM_OF_PIPE},
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

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Error, "Failed to record ui command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

windowSize :: proc(using graphicsData: ^GraphicsData) -> (width: i32, height: i32) {
	return glfw.GetWindowSize(window)
}

updateWindow :: proc(using graphicsData: ^GraphicsData) -> (ret: bool) {
	ret = !glfw.WindowShouldClose(window)
	glfw.PollEvents()
	return
}

@(require_results)
updateSceneData :: proc(
	graphicsData: ^GraphicsData,
	scene: ^Scene,
	view, projection: Mat4,
	delta: f32,
) -> Error {
	if graphicsData.reloadBuffers {
		if err := updateSceneBuffers(graphicsData, scene); err != nil {
			logf(.Error, "Failed to update scene buffers: %v", err)
			return err
		}
		graphicsData.reloadBuffers = false
		graphicsData.rerecordCommands = false
	} else if graphicsData.rerecordCommands {
		if err := updateCommandBuffers(graphicsData, scene); err != nil {
			logf(.Error, "Failed to update command buffers: %v", err)
			return err
		}
		graphicsData.rerecordCommands = false
	}

	updateUniformBuffer(graphicsData, scene, view, projection)
	updateLightBuffer(graphicsData, scene, delta)
	updateInstanceBuffer(graphicsData, scene, delta)

	return nil
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
drawFrame :: proc(using graphicsData: ^GraphicsData) -> (err: Error) {
	vk.WaitForFences(device, 1, &inFlightFrames[currentFrame], true, max(u64))

	imageIndex: u32
	if res := vk.AcquireNextImageKHR(
		device,
		swapchain.handle,
		max(u64),
		semaphores[SemaphoreIndex.Image][currentFrame],
		{},
		&imageIndex,
	); res == .ERROR_OUT_OF_DATE_KHR {
		if err = recreateSwapchain(graphicsData); err != nil {
			return err
		}
		graphicsData.rerecordCommands = true
		return DrawError.UpdateCommandBuffers
	} else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
		logf(.Error, "Failed to aquire swapchain image! vkResult: %v", res)
		return DrawError.FailedToAcquireSwapchainImage
	}
	vk.ResetFences(device, 1, &inFlightFrames[currentFrame])

	imguiVulkan.NewFrame()
	imguiGLFW.NewFrame()
	imgui.NewFrame()

	drawImgui(graphicsData)

	imgui.EndFrame()

	vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Imgui][currentFrame], {})
	if err := recordImguiCommands(graphicsData, currentFrame, imageIndex); err != nil {
		logf(.Error, "Failed to record ui command buffer! Error: %v", err)
		return err
	}

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
					commandBuffer = commandBuffers[CmdBufferIndex.Transform][currentFrame],
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
					semaphore = semaphores[SemaphoreIndex.Transform][currentFrame],
					value = 0,
					stageMask = {.BOTTOM_OF_PIPE},
					deviceIndex = 0,
				},
			},
		),
	}
	if res := vk.QueueSubmit2(computeQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Error, "Failed to submit command buffer! vkResult: %v", res)
		return .FailedToSubmitPreCommandBuffer
	}

	submitInfo = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		waitSemaphoreInfoCount   = 1,
		pWaitSemaphoreInfos      = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = semaphores[SemaphoreIndex.Transform][currentFrame],
					value = 0,
					stageMask = {.TOP_OF_PIPE},
					deviceIndex = 0,
				},
			},
		),
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = raw_data(
			[]vk.CommandBufferSubmitInfo {
				{
					sType = .COMMAND_BUFFER_SUBMIT_INFO,
					pNext = nil,
					commandBuffer = commandBuffers[CmdBufferIndex.Main][currentFrame],
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
					semaphore = semaphores[SemaphoreIndex.Main][currentFrame],
					value = 0,
					stageMask = {.BOTTOM_OF_PIPE},
					deviceIndex = 0,
				},
			},
		),
	}
	if res := vk.QueueSubmit2(graphicsQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Error, "Failed to submit command buffer! vkResult: %v", res)
		return .FailedToSubmitPreCommandBuffer
	}

	submitInfo = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		waitSemaphoreInfoCount   = 1,
		pWaitSemaphoreInfos      = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = semaphores[SemaphoreIndex.Main][currentFrame],
					value = 0,
					stageMask = {.TOP_OF_PIPE},
					deviceIndex = 0,
				},
			},
		),
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = raw_data(
			[]vk.CommandBufferSubmitInfo {
				{
					sType = .COMMAND_BUFFER_SUBMIT_INFO,
					pNext = nil,
					commandBuffer = commandBuffers[CmdBufferIndex.PostProcess][currentFrame],
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
					semaphore = semaphores[SemaphoreIndex.PostProcess][currentFrame],
					value = 0,
					stageMask = {.BOTTOM_OF_PIPE},
					deviceIndex = 0,
				},
			},
		),
	}
	if res := vk.QueueSubmit2(graphicsQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Error, "Failed to submit command buffer! vkResult: %v", res)
		return .FailedToSubmitPreCommandBuffer
	}

	submitInfo = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		waitSemaphoreInfoCount   = 2,
		pWaitSemaphoreInfos      = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = semaphores[SemaphoreIndex.PostProcess][currentFrame],
					value = 0,
					stageMask = {.TOP_OF_PIPE},
					deviceIndex = 0,
				},
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = semaphores[SemaphoreIndex.Image][currentFrame],
					value = 0,
					stageMask = {.BLIT},
					deviceIndex = 0,
				},
			},
		),
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = raw_data(
			[]vk.CommandBufferSubmitInfo {
				{
					sType = .COMMAND_BUFFER_SUBMIT_INFO,
					pNext = nil,
					commandBuffer = commandBuffers[CmdBufferIndex.Imgui][currentFrame],
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
					semaphore = semaphores[SemaphoreIndex.Imgui][currentFrame],
					value = 0,
					stageMask = {.BOTTOM_OF_PIPE},
					deviceIndex = 0,
				},
			},
		),
	}
	if res := vk.QueueSubmit2(graphicsQueue, 1, &submitInfo, inFlightFrames[currentFrame]);
	   res != .SUCCESS {
		logf(.Error, "Failed to submit command buffer! vkResult: %v", res)
		return .FailedToSubmitPreCommandBuffer
	}

	presentInfo: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		pNext              = nil,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &semaphores[SemaphoreIndex.Imgui][currentFrame],
		swapchainCount     = 1,
		pSwapchains        = &swapchain.handle,
		pImageIndices      = &imageIndex,
		pResults           = nil,
	}

	#partial switch res := vk.QueuePresentKHR(presentQueue, &presentInfo); res {
	case .SUCCESS:
		break
	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		err = recreateSwapchain(graphicsData)
		if err != nil {
			logf(.Error, "Failed to recreate swapchain! Error: %v", err)
			return err
		}
		graphicsData.rerecordCommands = true
		return DrawError.UpdateCommandBuffers
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

