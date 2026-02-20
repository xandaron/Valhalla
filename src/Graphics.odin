#+feature using-stmt
package Valhalla

import "../imgui"
import imguiGLFW "../imgui/imgui_impl_glfw"
import imguiVulkan "../imgui/imgui_impl_vulkan"
import "core:mem"
import "vendor:glfw"
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


// ###################################################################
// #                         Data Structures                         #
// ###################################################################


Error :: union #shared_nil {
	InitError,
	CommandBufferError,
	ImageError,
	BufferError,
	DrawError,
}

vkDebugMessengerCreateInfo :: vk.DebugUtilsMessengerCreateInfoEXT

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

SceneResources :: struct {
	images:           [dynamic]Image,
	// TODO: Combine buffers into one buffer and use offsets
	vertexBuffer:     Buffer,
	indexBuffer:      Buffer,
	instanceBuffers:  [MAX_FRAMES_IN_FLIGHT]Buffer,
	boneBuffers:      [MAX_FRAMES_IN_FLIGHT]Buffer,
	lightBuffers:     [MAX_FRAMES_IN_FLIGHT]Buffer,
	transformBuffers: [MAX_FRAMES_IN_FLIGHT]Buffer,
	imageIndexBuffer: Buffer,
}

deleteSceneRecources :: proc(using graphicsData: ^GraphicsData, resources: ^SceneResources) {
	deleteBuffer(graphicsData, &resources.indexBuffer)
	deleteBuffer(graphicsData, &resources.vertexBuffer)
	deleteBuffer(graphicsData, &resources.imageIndexBuffer)

	for idx in 0 ..< MAX_FRAMES_IN_FLIGHT {
		deleteBuffer(graphicsData, &resources.instanceBuffers[idx])
		deleteBuffer(graphicsData, &resources.boneBuffers[idx])
		deleteBuffer(graphicsData, &resources.lightBuffers[idx])
		deleteBuffer(graphicsData, &resources.transformBuffers[idx])
	}

	for &image in resources.images {
		deleteImage(graphicsData, &image)
	}
}

@(private = "file")
DescriptorHeap :: struct {
	resourceBuffers: [MAX_FRAMES_IN_FLIGHT]Buffer,
	resourceReserve: u64,
	resourceStride:  u64,
	samplerBuffer:   Buffer,
	samplerReserve:  u64,
	samplerStride:   u64,
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
	descriptorHeap:      DescriptorHeap,
	pipelines:           [len(PipelineIndex)]Pipeline,

	// Frame Resources
	depthFormat:         vk.Format,
	inFlightFrames:      [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	semaphores:          [len(SemaphoreIndex)][MAX_FRAMES_IN_FLIGHT]vk.Semaphore,

	// Commands
	graphicsCommandPool: vk.CommandPool,
	computeCommandPool:  vk.CommandPool,
	commandBuffers:      [len(CmdBufferIndex)][MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

	// Buffer
	uniformBuffers:      [MAX_FRAMES_IN_FLIGHT]Buffer,

	// Util
	currentFrame:        u32,
	drawLights:          bool,
	reloadBuffers:       bool,
	updateResourceHeap:  bool,
	rerecordCommands:    bool,
}

@(private = "file")
Swapchain :: struct {
	handle:    vk.SwapchainKHR,
	transform: vk.SurfaceTransformFlagsKHR,
	format:    vk.SurfaceFormatKHR,
	mode:      vk.PresentModeKHR,
	extent:    vk.Extent2D,
	images:    []Image,
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
	handle:  vk.Buffer,
	address: vk.DeviceAddress,
	memory:  vk.DeviceMemory,
	mapped:  rawptr,
	size:    u64,
}

@(private = "file")
Image :: struct {
	handle:  vk.Image,
	memory:  vk.DeviceMemory,
	view:    vk.ImageView,
	format:  vk.Format,
	sampler: u32,
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

	createInstance(&graphicsData, initInfo.appVersion)

	if res := vk.CreateDebugUtilsMessengerEXT(
		instance,
		&VK_DEBUG_MESSENGER_CREATE_INFO,
		nil,
		&debugMessenger,
	); res != .SUCCESS {
		logf(.Error, "Failed to create vulkan debug callback! vkResult: %v", res)
	}

	initWindow(&graphicsData, initInfo.windowTitle)
	pickPhysicalDevice(&graphicsData)
	createLogicalDevice(&graphicsData)
	createSwapchain(&graphicsData)
	createCommandBuffers(&graphicsData)

	bufferSize: u64 = size_of(UniformBuffer)
	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if err := createBuffer(
			&graphicsData,
			&uniformBuffers[index],
			bufferSize,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
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

	createSyncObjects(&graphicsData)
	createSamplerDescriptorHeap(&graphicsData)

	createTransformPipeline(&graphicsData, initInfo.transformShader)

	pipelines[PipelineIndex.Light].images = make([]Image, 2)
	pipelines[PipelineIndex.Light].images[0].format = .R16G16B16A16_SFLOAT
	pipelines[PipelineIndex.Light].images[1].format = depthFormat
	createLightPipeline(&graphicsData, initInfo.lightShaders[:])

	pipelines[PipelineIndex.Scene].images = make([]Image, 2)
	pipelines[PipelineIndex.Scene].images[0].format = .R16G16B16A16_SFLOAT
	pipelines[PipelineIndex.Scene].images[1].format = depthFormat
	createScenePipelineImages(&graphicsData)
	createScenePipeline(&graphicsData, initInfo.sceneShaders[:])

	pipelines[PipelineIndex.PostProcess].images = make([]Image, 2)
	pipelines[PipelineIndex.PostProcess].images[0].format = .R16G16B16A16_SFLOAT
	pipelines[PipelineIndex.PostProcess].images[1].format = .R16G16B16A16_SFLOAT
	createPostProcessPipelineImages(&graphicsData)
	createPostProcessPipeline(&graphicsData, initInfo.postProcessShader)

	initImgui(&graphicsData)

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
		log(.Fatal, "Failed to wait for device idle!")
	}

	shutdownImgui(graphicsData)

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

	for &buffer in uniformBuffers {
		deleteBuffer(graphicsData, &buffer)
	}

	deleteSwapchain(graphicsData, swapchain)
	for &pipeline in pipelines {
		deletePipeline(graphicsData, &pipeline)
	}

	for &buffer in descriptorHeap.resourceBuffers {
		deleteBuffer(graphicsData, &buffer)
	}
	deleteBuffer(graphicsData, &descriptorHeap.samplerBuffer)

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

@(private = "file")
createInstance :: proc(using graphicsData: ^GraphicsData, version: u32) {
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
	}

	vk.load_proc_addresses(instance)
}

@(private = "file")
initWindow :: proc(using graphicsData: ^GraphicsData, windowTitle: cstring) {
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	if window = glfw.CreateWindow(1600, 800, windowTitle, nil, nil); window == nil {
		log(.Fatal, "Failed to create window.")
	}

	glfw.SetErrorCallback(glfwErrorCallback)
	glfw.SetKeyCallback(window, keyCallback)
	glfw.SetMouseButtonCallback(window, mouseButtonCallback)
	glfw.SetCursorPosCallback(window, cursorPosCallback)
	glfw.SetScrollCallback(window, scrollCallback)

	if res := glfw.CreateWindowSurface(instance, window, nil, &surface); res != .SUCCESS {
		logf(.Fatal, "Failed to create surface! vkResult: %v", res)
	}
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

@(private = "file")
pickPhysicalDevice :: proc(using graphicsData: ^GraphicsData) {
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
	}
}

@(private = "file")
createLogicalDevice :: proc(using graphicsData: ^GraphicsData) {
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

	descriptorHeapFeature: vk.PhysicalDeviceDescriptorHeapFeaturesEXT = {
		sType                       = .PHYSICAL_DEVICE_DESCRIPTOR_HEAP_FEATURES_EXT,
		pNext                       = nil,
		descriptorHeap              = true,
		descriptorHeapCaptureReplay = false,
	}

	maintenance7: vk.PhysicalDeviceMaintenance7FeaturesKHR = {
		sType        = .PHYSICAL_DEVICE_MAINTENANCE_7_FEATURES_KHR,
		pNext        = &descriptorHeapFeature,
		maintenance7 = true,
	}

	computeShaderDerivatives: vk.PhysicalDeviceComputeShaderDerivativesFeaturesKHR = {
		sType                        = .PHYSICAL_DEVICE_COMPUTE_SHADER_DERIVATIVES_FEATURES_KHR,
		pNext                        = &maintenance7,
		computeDerivativeGroupQuads  = true,
		computeDerivativeGroupLinear = false,
	}

	features14: vk.PhysicalDeviceVulkan14Features = {
		sType        = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
		pNext        = &computeShaderDerivatives,
		maintenance5 = true,
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
	}

	vk.load_proc_addresses(device)

	vk.GetDeviceQueue(device, queueFamilies.graphicsFamily, 0, &graphicsQueue)
	vk.GetDeviceQueue(device, queueFamilies.presentFamily, 0, &presentQueue)
	vk.GetDeviceQueue(device, queueFamilies.computeFamily, 0, &computeQueue)
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

	swapchain.images = make([]Image, swapchainImageCount)
	imageHandles := make([]vk.Image, swapchainImageCount, context.temp_allocator)
	vk.GetSwapchainImagesKHR(
		device,
		swapchain.handle,
		&swapchainImageCount,
		raw_data(imageHandles),
	)
	for idx in 0 ..< swapchainImageCount {
		swapchain.images[idx].handle = imageHandles[idx]
	}

	for idx in 0 ..< swapchainImageCount {
		err: ImageError
		err = createImageView(graphicsData, &swapchain.images[idx], .D2, {.COLOR}, 1)
		if err != .None {
			log(.Fatal, "Failed to create swapchain image view! vkResult: %v", err)
		}
	}
}

@(private = "file")
deleteSwapchain :: proc(graphicsData: ^GraphicsData, swapchain: Swapchain) {
	for &image in swapchain.images {
		vk.DestroyImageView(graphicsData.device, image.view, nil)
	}
	delete(swapchain.images)
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
	deleteSwapchain(graphicsData, oldSwapchain)

	for &image in pipelines[PipelineIndex.PostProcess].images {
		deleteImage(graphicsData, &image)
	}
	createPostProcessPipelineImages(graphicsData)

	shutdownImgui(graphicsData)
	initImgui(graphicsData)

	graphicsData.updateResourceHeap = true
	graphicsData.rerecordCommands = true
}

@(private = "file")
createCommandBuffers :: proc(using graphicsData: ^GraphicsData) {
	poolInfo: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		pNext            = nil,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queueFamilies.graphicsFamily,
	}
	if res := vk.CreateCommandPool(device, &poolInfo, nil, &graphicsCommandPool); res != .SUCCESS {
		log(.Fatal, "Failed to create command pool! vkResult: %v", res)
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
	}

	poolInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		pNext            = nil,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queueFamilies.computeFamily,
	}
	if res := vk.CreateCommandPool(device, &poolInfo, nil, &computeCommandPool); res != .SUCCESS {
		logf(.Fatal, "Failed to create command pool! vkResult: %v", res)
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
	}
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
beginSingleTimeCommands :: proc(
	using graphicsData: ^GraphicsData,
	commandPool: vk.CommandPool,
) -> (
	vk.CommandBuffer,
	CommandBufferError,
) {
	cmdBuffer: vk.CommandBuffer
	allocInfo: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = commandPool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if res := vk.AllocateCommandBuffers(device, &allocInfo, &cmdBuffer); res != .SUCCESS {
		logf(.Error, "Failed to allocate command buffer! vkResult: %v", res)
		return nil, .FailedToAllocateCommandBuffer
	}

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.ONE_TIME_SUBMIT},
		pInheritanceInfo = nil,
	}
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to begin command buffer! vkResult: %v", res)
		return nil, .FailedToBeginCommandBuffer
	}

	return cmdBuffer, .None
}

@(private = "file")
@(require_results)
endSingleTimeCommands :: proc(
	using graphicsData: ^GraphicsData,
	cmdBuffer: vk.CommandBuffer,
	commandPool: vk.CommandPool,
) -> CommandBufferError {
	cmdBuffer := cmdBuffer
	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
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
		pCommandBuffers      = &cmdBuffer,
		signalSemaphoreCount = 0,
		pSignalSemaphores    = nil,
	}

	fence: vk.Fence
	fenceCreateInfo: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		pNext = nil,
		flags = nil,
	}
	vk.CreateFence(device, &fenceCreateInfo, nil, &fence)

	vk.QueueSubmit(graphicsQueue, 1, &submitInfo, fence)
	vk.WaitForFences(device, 1, &fence, true, ~u64(0))

	vk.DestroyFence(device, fence, nil)
	vk.FreeCommandBuffers(device, commandPool, 1, &cmdBuffer)

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
	buffer: ^Buffer,
	size: u64,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> BufferError {
	bufferInfo: vk.BufferCreateInfo = {
		sType                 = .BUFFER_CREATE_INFO,
		pNext                 = nil,
		flags                 = nil,
		size                  = vk.DeviceSize(size),
		usage                 = usage,
		sharingMode           = .EXCLUSIVE,
		queueFamilyIndexCount = 0,
		pQueueFamilyIndices   = nil,
	}
	vkDevice := graphicsData.device
	if res := vk.CreateBuffer(vkDevice, &bufferInfo, nil, &buffer.handle); res != .SUCCESS {
		logf(.Error, "Failed to create buffer! vkResult: %d", res)
		return .FailedToCreateBuffer
	}

	memRequirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer.handle, &memRequirements)
	allocInfo: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = nil,
		allocationSize  = memRequirements.size,
		memoryTypeIndex = findMemoryType(graphicsData, memRequirements.memoryTypeBits, properties),
	}
	if res := vk.AllocateMemory(device, &allocInfo, nil, &buffer.memory); res != .SUCCESS {
		logf(.Error, "Failed to allocate buffer memory! vkResult: %d", res)
		return .FailedToAllocateBufferMemory
	}

	if res := vk.BindBufferMemory(device, buffer.handle, buffer.memory, 0); res != .SUCCESS {
		logf(.Error, "Failed to bind buffer memory! vkResult: %d", res)
		return .FailedToBindBufferMemory
	}

	buffer.address = vk.GetBufferDeviceAddress(
		device,
		&vk.BufferDeviceAddressInfo {
			sType = .BUFFER_DEVICE_ADDRESS_INFO,
			pNext = nil,
			buffer = buffer.handle,
		},
	)

	return .None
}

@(private = "file")
@(require_results)
loadBufferToGPU :: proc(
	using graphicsData: ^GraphicsData,
	bufferSize: u64,
	srcData: rawptr,
	dstBuffer: ^Buffer,
	bufferType: vk.BufferUsageFlag,
) -> BufferError {
	stagingBuffer: Buffer
	if err := createBuffer(
		graphicsData,
		&stagingBuffer,
		bufferSize,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	); err != nil {
		logf(.Error, "Failed to create staging buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}
	defer deleteBuffer(graphicsData, &stagingBuffer)

	data: rawptr
	vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(bufferSize), {}, &data)
	mem.copy(data, srcData, int(bufferSize))
	vk.UnmapMemory(device, stagingBuffer.memory)

	if err := createBuffer(
		graphicsData,
		dstBuffer,
		bufferSize,
		{.TRANSFER_DST, .STORAGE_BUFFER, bufferType},
		{.DEVICE_LOCAL},
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

	vk.CmdCopyBuffer(commandBuffer, stagingBuffer.handle, dstBuffer.handle, 1, &copyRegion)
	if err := endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool); err != nil {
		logf(.Error, "Failed to end single time command buffer! Error: %d", err)
		return .FailedToCreateBuffer
	}

	return nil
}

@(private = "file")
deleteBuffer :: proc(using graphicsData: ^GraphicsData, buffer: ^Buffer) {
	vk.DestroyBuffer(device, buffer.handle, nil)
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

	if res := vk.CreateImage(device, &imageInfo, nil, &image.handle); res != .SUCCESS {
		logf(.Error, "Failed to create texture! vkResult: %d", res)
		return .FailedToCreateImage
	}

	memRequirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image.handle, &memRequirements)
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

	if res := vk.BindImageMemory(device, image.handle, image.memory, 0); res != .SUCCESS {
		logf(.Error, "Failed to bind image memory! vkResult: %d", res)
		return .FailedToBindImageMemory
	}

	return .None
}

@(private = "file")
createImageView :: proc(
	using graphicsData: ^GraphicsData,
	image: ^Image,
	viewType: vk.ImageViewType,
	aspectFlags: vk.ImageAspectFlags,
	layerCount: u32,
) -> ImageError {
	viewInfo: vk.ImageViewCreateInfo = {
		sType = .IMAGE_VIEW_CREATE_INFO,
		pNext = nil,
		flags = nil,
		image = image.handle,
		viewType = viewType,
		format = image.format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = aspectFlags,
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = layerCount,
		},
	}
	if res := vk.CreateImageView(device, &viewInfo, nil, &image.view); res != .SUCCESS {
		logf(.Error, "Failed to create image view! vkResult: %d", res)
		return .FailedToCreateImageView
	}
	return .None
}

// @(private = "file")
// transitionImageLayout :: proc(
// 	using graphicsData: ^GraphicsData,
// 	commandBuffer: vk.CommandBuffer,
// 	image: vk.Image,
// 	oldLayout, newLayout: vk.ImageLayout,
// 	aspectMask: vk.ImageAspectFlags,
// 	layerCount: u32,
// ) -> ImageError {
// 	barrier: vk.ImageMemoryBarrier = {
// 		sType = .IMAGE_MEMORY_BARRIER,
// 		pNext = nil,
// 		srcAccessMask = {},
// 		dstAccessMask = {},
// 		oldLayout = oldLayout,
// 		newLayout = newLayout,
// 		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
// 		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
// 		image = image,
// 		subresourceRange = vk.ImageSubresourceRange {
// 			aspectMask = aspectMask,
// 			baseMipLevel = 0,
// 			levelCount = 1,
// 			baseArrayLayer = 0,
// 			layerCount = layerCount,
// 		},
// 	}

// 	sourceStage, destinationStage: vk.PipelineStageFlags
// 	#partial switch oldLayout {
// 	case .UNDEFINED:
// 		barrier.srcAccessMask = {}
// 		sourceStage = {.TOP_OF_PIPE}
// 	case .TRANSFER_SRC_OPTIMAL:
// 		barrier.srcAccessMask = {.TRANSFER_READ}
// 		sourceStage = {.TRANSFER}
// 	case .TRANSFER_DST_OPTIMAL:
// 		barrier.srcAccessMask = {.TRANSFER_WRITE}
// 		sourceStage = {.TRANSFER}
// 	case .SHADER_READ_ONLY_OPTIMAL:
// 		barrier.srcAccessMask = {.SHADER_READ}
// 		sourceStage = {.FRAGMENT_SHADER}
// 	case .GENERAL:
// 		barrier.srcAccessMask = {.SHADER_READ}
// 		sourceStage = {.COMPUTE_SHADER}
// 	case:
// 		log(.Error, "Unsupported image layout transition!")
// 		return .TransitionFailed
// 	}

// 	#partial switch newLayout {
// 	case .TRANSFER_SRC_OPTIMAL:
// 		barrier.dstAccessMask = {.TRANSFER_READ}
// 		destinationStage = {.TRANSFER}
// 	case .TRANSFER_DST_OPTIMAL:
// 		barrier.dstAccessMask = {.TRANSFER_WRITE}
// 		destinationStage = {.TRANSFER}
// 	case .SHADER_READ_ONLY_OPTIMAL:
// 		barrier.dstAccessMask = {.SHADER_READ}
// 		destinationStage = {.FRAGMENT_SHADER}
// 	case .GENERAL:
// 		if oldLayout == .TRANSFER_SRC_OPTIMAL {
// 			barrier.dstAccessMask = {.SHADER_WRITE}
// 		} else if oldLayout == .TRANSFER_DST_OPTIMAL {
// 			barrier.dstAccessMask = {.SHADER_READ}
// 		}
// 		destinationStage = {.COMPUTE_SHADER}
// 	case .PRESENT_SRC_KHR:
// 		barrier.dstAccessMask = {.SHADER_READ}
// 		destinationStage = {.COMPUTE_SHADER}
// 	case .COLOR_ATTACHMENT_OPTIMAL:
// 		barrier.dstAccessMask = {.SHADER_WRITE}
// 		destinationStage = {.VERTEX_SHADER}
// 	case:
// 		log(.Error, "Unsupported image layout transition!")
// 		return .TransitionFailed
// 	}

// 	vk.CmdPipelineBarrier(
// 		commandBuffer,
// 		sourceStage,
// 		destinationStage,
// 		{},
// 		0,
// 		nil,
// 		0,
// 		nil,
// 		1,
// 		&barrier,
// 	)

// 	return .None
// }

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

@(require_results)
addImage :: proc(
	using graphicsData: ^GraphicsData,
	scene: ^Scene,
	width, height: u32,
	format: vk.Format,
	data: []byte,
) -> Error {
	err: Error
	stagingBuffer: Buffer
	err = createBuffer(
		graphicsData,
		&stagingBuffer,
		u64(len(data)),
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	if err != nil {
		log(.Error, "Failed to create staging buffer!")
		return err
	}
	defer deleteBuffer(graphicsData, &stagingBuffer)

	vk.MapMemory(
		device,
		stagingBuffer.memory,
		0,
		vk.DeviceSize(len(data)),
		nil,
		&stagingBuffer.mapped,
	)
	mem.copy(stagingBuffer.mapped, raw_data(data), len(data))
	vk.UnmapMemory(device, stagingBuffer.memory)

	image: Image
	image.format = format
	err = createImage(
		graphicsData,
		&image,
		nil,
		.D2,
		width,
		height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != nil {
		logf(.Error, "Failed to create image for textures! Error: %v", err)
		return err
	}

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to begin single time commands! Error: %v", err)
		return err
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
				dstStageMask = {.COPY},
				dstAccessMask = {.TRANSFER_WRITE},
				oldLayout = .UNDEFINED,
				newLayout = .TRANSFER_DST_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = image.handle,
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

	vk.CmdCopyBufferToImage(
		cmdBuffer,
		stagingBuffer.handle,
		image.handle,
		.TRANSFER_DST_OPTIMAL,
		1,
		&vk.BufferImageCopy {
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
				srcStageMask = {.COPY},
				srcAccessMask = {.TRANSFER_WRITE},
				dstStageMask = nil,
				dstAccessMask = nil,
				oldLayout = .TRANSFER_DST_OPTIMAL,
				newLayout = .SHADER_READ_ONLY_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = image.handle,
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

	err = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
	if err != nil {
		logf(.Error, "Failed to end single time commands! Error: %v", err)
		return err
	}
	return nil
}

@(private = "file")
deleteImage :: proc(using graphicsData: ^GraphicsData, image: ^Image) {
	vk.DestroyImageView(device, image.view, nil)
	vk.DestroyImage(device, image.handle, nil)
	vk.FreeMemory(device, image.memory, nil)
}

updateSceneBuffers :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	err: Error

	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	err = loadBufferToGPU(
		graphicsData,
		size_of(Vertex) * u64(len(scene.vertices)),
		raw_data(scene.vertices),
		&scene.resources.vertexBuffer,
		.VERTEX_BUFFER,
	)
	if err != nil {
		logf(.Fatal, "Failed to load vertex buffer! Error: %v", err)
	}

	err = loadBufferToGPU(
		graphicsData,
		size_of(u32) * u64(len(scene.indices)),
		raw_data(scene.indices),
		&scene.resources.indexBuffer,
		.INDEX_BUFFER,
	)
	if err != nil {
		logf(.Fatal, "Failed to load index buffer! Error: %v", err)
	}

	instanceBufferSize: u64 = size_of(InstanceInfo) * u64(len(scene.objects))
	boneBufferSize: u64 = size_of(Mat4) * u64(scene.boneCount)
	lightBufferSize: u64 = size_of(LightData) * u64(len(scene.lights))
	transformBufferSize: u64 = size_of(Mat4) * u64(scene.vertexCount)

	textureIndexSize: u64 = 0
	for &model in scene.models {
		textureIndexSize += u64(len(model.instances)) * u64(len(model.meshes))
	}
	textureIndexSize *= len(TextureIndex) * size_of(u32)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		deleteBuffer(graphicsData, &scene.resources.instanceBuffers[i])
		err = createBuffer(
			graphicsData,
			&scene.resources.instanceBuffers[i],
			instanceBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		if err != nil {
			logf(.Fatal, "Failed to create instance buffer! Error: %v", err)
		}
		vk.MapMemory(
			graphicsData.device,
			scene.resources.instanceBuffers[i].memory,
			0,
			vk.DeviceSize(instanceBufferSize),
			nil,
			&scene.resources.instanceBuffers[i].mapped,
		)

		deleteBuffer(graphicsData, &scene.resources.boneBuffers[i])
		err = createBuffer(
			graphicsData,
			&scene.resources.boneBuffers[i],
			boneBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		if err != nil {
			logf(.Fatal, "Failed to create bone buffer! Error: %v", err)
		}
		vk.MapMemory(
			graphicsData.device,
			scene.resources.boneBuffers[i].memory,
			0,
			vk.DeviceSize(boneBufferSize),
			nil,
			&scene.resources.boneBuffers[i].mapped,
		)

		deleteBuffer(graphicsData, &scene.resources.lightBuffers[i])
		err = createBuffer(
			graphicsData,
			&scene.resources.lightBuffers[i],
			lightBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		if err != nil {
			logf(.Fatal, "Failed to create light buffer! Error: %v", err)
		}
		vk.MapMemory(
			graphicsData.device,
			scene.resources.lightBuffers[i].memory,
			0,
			vk.DeviceSize(lightBufferSize),
			nil,
			&scene.resources.lightBuffers[i].mapped,
		)

		deleteBuffer(graphicsData, &scene.resources.transformBuffers[i])
		err = createBuffer(
			graphicsData,
			&scene.resources.transformBuffers[i],
			transformBufferSize,
			{.STORAGE_BUFFER},
			{.DEVICE_LOCAL},
		)
		if err != nil {
			logf(.Fatal, "Failed to create transform buffer! Error: %v", err)
		}
	}

	deleteBuffer(graphicsData, &scene.resources.imageIndexBuffer)
	err = createBuffer(
		graphicsData,
		&scene.resources.imageIndexBuffer,
		textureIndexSize,
		{.STORAGE_BUFFER},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	if err != nil {
		logf(.Fatal, "Failed to create transform buffer! Error: %v", err)
	}
	vk.MapMemory(
		graphicsData.device,
		scene.resources.imageIndexBuffer.memory,
		0,
		vk.DeviceSize(textureIndexSize),
		nil,
		&scene.resources.imageIndexBuffer.mapped,
	)
	updateTextureIndexBuffer(graphicsData, scene)

	deleteImage(graphicsData, &pipelines[PipelineIndex.Light].images[0])
	deleteImage(graphicsData, &pipelines[PipelineIndex.Light].images[1])
	createLightPipelineImages(graphicsData, scene)

	for idx in 0 ..< MAX_FRAMES_IN_FLIGHT {
		deleteBuffer(graphicsData, &graphicsData.descriptorHeap.resourceBuffers[idx])
	}
	createResourceDescriptorHeap(graphicsData, scene)
	updateCommandBuffers(graphicsData, scene)
}

@(private = "file")
createResourceDescriptorHeap :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	bufferSize: u64 = descriptorHeap.resourceReserve
	bufferSize += descriptorHeap.resourceStride * u64(11 + len(scene.resources.images))

	err: Error
	stagingBuffer: Buffer
	err = createBuffer(graphicsData, &stagingBuffer, bufferSize, {.TRANSFER_SRC}, {.HOST_COHERENT})
	vk.MapMemory(
		graphicsData.device,
		stagingBuffer.memory,
		0,
		vk.DeviceSize(bufferSize),
		nil,
		&stagingBuffer.mapped,
	)
	defer deleteBuffer(graphicsData, &stagingBuffer)

	textureBufferLen := 0
	for &model in scene.models {
		textureBufferLen += len(model.instances) * len(model.meshes)
	}

	resourceInfo := make(
		[]vk.ResourceDescriptorInfoEXT,
		11 + len(scene.resources.images),
		context.temp_allocator,
	)

	// Vertex Buffer
	resourceInfo[0] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pAddressRange = &vk.DeviceAddressRangeEXT {
				address = vk.GetBufferDeviceAddress(
					device,
					&vk.BufferDeviceAddressInfo {
						sType = .BUFFER_DEVICE_ADDRESS_INFO,
						pNext = nil,
						buffer = scene.resources.vertexBuffer.handle,
					},
				),
				size = vk.DeviceSize(size_of(Vertex) * len(scene.vertices)),
			},
		},
	}

	// Image Index Buffer
	resourceInfo[1] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pAddressRange = &vk.DeviceAddressRangeEXT {
				address = vk.GetBufferDeviceAddress(
					device,
					&vk.BufferDeviceAddressInfo {
						sType = .BUFFER_DEVICE_ADDRESS_INFO,
						pNext = nil,
						buffer = scene.resources.imageIndexBuffer.handle,
					},
				),
				size = vk.DeviceSize(size_of(u32) * textureBufferLen * len(TextureIndex)),
			},
		},
	}

	// Uniform Buffer
	resourceInfo[2] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pAddressRange = &vk.DeviceAddressRangeEXT {
				size = vk.DeviceSize(size_of(UniformBuffer)),
			},
		},
	}

	// Instance Buffer
	resourceInfo[3] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pAddressRange = &vk.DeviceAddressRangeEXT {
				size = vk.DeviceSize(size_of(InstanceInfo) * len(scene.objects)),
			},
		},
	}

	// Bone Buffer
	resourceInfo[4] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pAddressRange = &vk.DeviceAddressRangeEXT {
				size = vk.DeviceSize(size_of(Mat4) * scene.boneCount),
			},
		},
	}

	// Light Buffer
	resourceInfo[5] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pAddressRange = &vk.DeviceAddressRangeEXT {
				size = vk.DeviceSize(size_of(LightData) * len(scene.lights)),
			},
		},
	}

	// Transform Buffer
	resourceInfo[6] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pAddressRange = &vk.DeviceAddressRangeEXT {
				size = vk.DeviceSize(size_of(Mat4) * scene.vertexCount),
			},
		},
	}

	// Shadow Map Cube Images
	resourceInfo[7] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pImage = &vk.ImageDescriptorInfoEXT {
				sType = .IMAGE_DESCRIPTOR_INFO_EXT,
				pNext = nil,
				pView = &vk.ImageViewCreateInfo {
					sType = .IMAGE_VIEW_CREATE_INFO,
					pNext = nil,
					flags = nil,
					image = pipelines[PipelineIndex.Light].images[0].handle,
					viewType = .CUBE_ARRAY,
					format = pipelines[PipelineIndex.Light].images[0].format,
					components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
					subresourceRange = vk.ImageSubresourceRange {
						aspectMask = {.COLOR},
						baseMipLevel = 0,
						levelCount = 1,
						baseArrayLayer = 0,
						layerCount = 1,
					},
				},
				layout = .SHADER_READ_ONLY_OPTIMAL,
			},
		},
	}

	// Scene Depth Image
	resourceInfo[8] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pImage = &vk.ImageDescriptorInfoEXT {
				sType = .IMAGE_DESCRIPTOR_INFO_EXT,
				pNext = nil,
				pView = &vk.ImageViewCreateInfo {
					sType = .IMAGE_VIEW_CREATE_INFO,
					pNext = nil,
					flags = nil,
					image = pipelines[PipelineIndex.Scene].images[1].handle,
					viewType = .D2,
					format = pipelines[PipelineIndex.Scene].images[1].format,
					components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
					subresourceRange = vk.ImageSubresourceRange {
						aspectMask = {.COLOR},
						baseMipLevel = 0,
						levelCount = 1,
						baseArrayLayer = 0,
						layerCount = 1,
					},
				},
				layout = .SHADER_READ_ONLY_OPTIMAL,
			},
		},
	}

	// Post-Process Input Image
	resourceInfo[9] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pImage = &vk.ImageDescriptorInfoEXT {
				sType = .IMAGE_DESCRIPTOR_INFO_EXT,
				pNext = nil,
				pView = &vk.ImageViewCreateInfo {
					sType = .IMAGE_VIEW_CREATE_INFO,
					pNext = nil,
					flags = nil,
					image = pipelines[PipelineIndex.PostProcess].images[0].handle,
					viewType = .D2,
					format = pipelines[PipelineIndex.PostProcess].images[0].format,
					components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
					subresourceRange = vk.ImageSubresourceRange {
						aspectMask = {.COLOR},
						baseMipLevel = 0,
						levelCount = 1,
						baseArrayLayer = 0,
						layerCount = 1,
					},
				},
				layout = .GENERAL,
			},
		},
	}

	// Post-Process Output Image
	resourceInfo[10] = {
		sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
		pNext = nil,
		type = nil,
		data = vk.ResourceDescriptorDataEXT {
			pImage = &vk.ImageDescriptorInfoEXT {
				sType = .IMAGE_DESCRIPTOR_INFO_EXT,
				pNext = nil,
				pView = &vk.ImageViewCreateInfo {
					sType = .IMAGE_VIEW_CREATE_INFO,
					pNext = nil,
					flags = nil,
					image = pipelines[PipelineIndex.PostProcess].images[1].handle,
					viewType = .D2,
					format = pipelines[PipelineIndex.PostProcess].images[1].format,
					components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
					subresourceRange = vk.ImageSubresourceRange {
						aspectMask = {.COLOR},
						baseMipLevel = 0,
						levelCount = 1,
						baseArrayLayer = 0,
						layerCount = 1,
					},
				},
				layout = .GENERAL,
			},
		},
	}

	// Mesh Images
	for &image, idx in scene.resources.images {
		resourceInfo[11 + idx] = vk.ResourceDescriptorInfoEXT {
			sType = .RESOURCE_DESCRIPTOR_INFO_EXT,
			pNext = nil,
			type = nil,
			data = vk.ResourceDescriptorDataEXT {
				pImage = &vk.ImageDescriptorInfoEXT {
					sType = .IMAGE_DESCRIPTOR_INFO_EXT,
					pNext = nil,
					pView = &vk.ImageViewCreateInfo {
						sType = .IMAGE_VIEW_CREATE_INFO,
						pNext = nil,
						flags = nil,
						image = image.handle,
						viewType = .D2,
						format = image.format,
						components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
						subresourceRange = vk.ImageSubresourceRange {
							aspectMask = {.COLOR},
							baseMipLevel = 0,
							levelCount = 1,
							baseArrayLayer = 0,
							layerCount = 1,
						},
					},
					layout = .SHADER_READ_ONLY_OPTIMAL,
				},
			},
		}
	}

	writeAddresses := make([]vk.HostAddressRangeEXT, len(resourceInfo), context.temp_allocator)
	for &address, idx in writeAddresses {
		offset := uintptr(descriptorHeap.resourceStride * u64(idx))
		address.address = rawptr(uintptr(stagingBuffer.mapped) + offset)
		address.size = int(descriptorHeap.resourceStride)
	}
	for idx in 0 ..< MAX_FRAMES_IN_FLIGHT {
		descriptorHeap.resourceBuffers[idx].size = bufferSize

		resourceInfo[2].data.pAddressRange.address = uniformBuffers[idx].address
		resourceInfo[3].data.pAddressRange.address = scene.resources.instanceBuffers[idx].address
		resourceInfo[4].data.pAddressRange.address = scene.resources.boneBuffers[idx].address
		resourceInfo[5].data.pAddressRange.address = scene.resources.lightBuffers[idx].address
		resourceInfo[6].data.pAddressRange.address = scene.resources.transformBuffers[idx].address

		if res := vk.WriteResourceDescriptorsEXT(
			device,
			u32(len(resourceInfo)),
			raw_data(resourceInfo),
			raw_data(writeAddresses),
		); res != .SUCCESS {
			logf(.Fatal, "Failed to write resource descriptors: %v", res)
		}

		err = createBuffer(
			graphicsData,
			&descriptorHeap.resourceBuffers[idx],
			bufferSize,
			{.DESCRIPTOR_HEAP_EXT, .SHADER_DEVICE_ADDRESS, .TRANSFER_DST},
			nil,
		)
		if err != nil {
			log(.Fatal, "Failed to create heap buffer!")
		}

		cmdBuffer: vk.CommandBuffer
		cmdBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
		if err != nil {
			log(.Fatal, "Failed to start single time commands!")
		}

		vk.CmdCopyBuffer2(
			cmdBuffer,
			&vk.CopyBufferInfo2 {
				sType = .COPY_BUFFER_INFO_2,
				pNext = nil,
				srcBuffer = stagingBuffer.handle,
				dstBuffer = descriptorHeap.resourceBuffers[idx].handle,
				regionCount = 1,
				pRegions = &vk.BufferCopy2 {
					sType = .BUFFER_COPY_2,
					pNext = nil,
					srcOffset = 0,
					dstOffset = 0,
					size = vk.DeviceSize(bufferSize),
				},
			},
		)

		err = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
		if err != nil {
			log(.Fatal, "Failed to submit single time commands!")
		}
	}
}

@(private = "file")
createSamplerDescriptorHeap :: proc(using graphicsData: ^GraphicsData) {
	heapProperties: vk.PhysicalDeviceDescriptorHeapPropertiesEXT
	heapProperties.sType = .PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT
	deviceProperties: vk.PhysicalDeviceProperties2
	deviceProperties.sType = .PHYSICAL_DEVICE_PROPERTIES_2
	deviceProperties.pNext = &heapProperties
	vk.GetPhysicalDeviceProperties2(physicalDevice, &deviceProperties)

	descriptorHeap.resourceReserve = u64(heapProperties.minResourceHeapReservedRange)
	descriptorHeap.resourceStride = u64(
		max(heapProperties.bufferDescriptorSize, heapProperties.imageDescriptorSize),
	)
	descriptorHeap.samplerReserve = u64(heapProperties.minSamplerHeapReservedRange)
	descriptorHeap.samplerStride = u64(heapProperties.samplerDescriptorSize)

	descriptorHeap.samplerBuffer.size =
		descriptorHeap.samplerReserve + descriptorHeap.samplerStride * 2

	err: Error
	stagingBuffer: Buffer

	err = createBuffer(
		graphicsData,
		&stagingBuffer,
		descriptorHeap.samplerBuffer.size,
		{.TRANSFER_SRC},
		{.HOST_COHERENT},
	)
	vk.MapMemory(
		graphicsData.device,
		stagingBuffer.memory,
		0,
		vk.DeviceSize(descriptorHeap.samplerBuffer.size),
		nil,
		&stagingBuffer.mapped,
	)
	defer deleteBuffer(graphicsData, &stagingBuffer)

	samplerInfo := [?]vk.SamplerCreateInfo {
		{
			sType = .SAMPLER_CREATE_INFO,
			pNext = nil,
			flags = nil,
			magFilter = .LINEAR,
			minFilter = .LINEAR,
			mipmapMode = .LINEAR,
			addressModeU = .CLAMP_TO_EDGE,
			addressModeV = .CLAMP_TO_EDGE,
			addressModeW = .CLAMP_TO_EDGE,
			mipLodBias = 0,
			anisotropyEnable = false,
			maxAnisotropy = 0.0,
			compareEnable = false,
			compareOp = .NEVER,
			minLod = 0,
			maxLod = vk.LOD_CLAMP_NONE,
			borderColor = .INT_OPAQUE_BLACK,
			unnormalizedCoordinates = false,
		},
		{
			sType = .SAMPLER_CREATE_INFO,
			pNext = nil,
			flags = nil,
			magFilter = .LINEAR,
			minFilter = .LINEAR,
			mipmapMode = .LINEAR,
			addressModeU = .CLAMP_TO_EDGE,
			addressModeV = .CLAMP_TO_EDGE,
			addressModeW = .CLAMP_TO_EDGE,
			mipLodBias = 0,
			anisotropyEnable = true,
			maxAnisotropy = deviceProperties.properties.limits.maxSamplerAnisotropy,
			compareEnable = false,
			compareOp = .NEVER,
			minLod = 0,
			maxLod = vk.LOD_CLAMP_NONE,
			borderColor = .INT_OPAQUE_BLACK,
			unnormalizedCoordinates = false,
		},
	}

	writeAddresses: [len(samplerInfo)]vk.HostAddressRangeEXT
	for &address, idx in writeAddresses {
		offset := uintptr(descriptorHeap.samplerStride * u64(idx))
		address.address = rawptr(uintptr(stagingBuffer.mapped) + offset)
		address.size = int(descriptorHeap.samplerStride)
	}

	if res := vk.WriteSamplerDescriptorsEXT(
		device,
		u32(len(samplerInfo)),
		&samplerInfo[0],
		&writeAddresses[0],
	); res != .SUCCESS {
		logf(.Fatal, "Failed to write resource descriptors: %v", res)
	}

	err = createBuffer(
		graphicsData,
		&descriptorHeap.samplerBuffer,
		descriptorHeap.samplerBuffer.size,
		{.DESCRIPTOR_HEAP_EXT, .SHADER_DEVICE_ADDRESS, .TRANSFER_DST},
		nil,
	)
	if err != nil {
		log(.Fatal, "Failed to create heap buffer!")
	}

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to start single time commands!")
	}

	vk.CmdCopyBuffer2(
		cmdBuffer,
		&vk.CopyBufferInfo2 {
			sType = .COPY_BUFFER_INFO_2,
			pNext = nil,
			srcBuffer = stagingBuffer.handle,
			dstBuffer = descriptorHeap.samplerBuffer.handle,
			regionCount = 1,
			pRegions = &vk.BufferCopy2 {
				sType = .BUFFER_COPY_2,
				pNext = nil,
				srcOffset = 0,
				dstOffset = 0,
				size = vk.DeviceSize(descriptorHeap.samplerBuffer.size),
			},
		},
	)

	err = endSingleTimeCommands(graphicsData, cmdBuffer, graphicsCommandPool)
	if err != nil {
		log(.Fatal, "Failed to submit single time commands!")
	}
}

@(private = "file")
createSyncObjects :: proc(using graphicsData: ^GraphicsData) {
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
		}

		for semaphoreIndex in SemaphoreIndex {
			if res := vk.CreateSemaphore(
				device,
				&semaphoreInfo,
				nil,
				&semaphores[semaphoreIndex][index],
			); res != .SUCCESS {
				logf(.Fatal, "Failed to create semaphore %v! vkResult: %v", semaphoreIndex, res)
			}
		}
	}
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
	handle: vk.Pipeline,
	images: []Image,
}

@(private = "file")
createTransformPipeline :: proc(
	using graphicsData: ^GraphicsData,
	shader: []byte,
	pipelineCache: vk.PipelineCache = 0,
) {
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
		pNext              = &vk.PipelineCreateFlags2CreateInfo {
			sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
			pNext = nil,
			// VK_PIPELINE_CREATE_2_DESCRIPTOR_HEAP_BIT_EXT = 0x1000000000ULL;
			flags = transmute(vk.PipelineCreateFlags2)u64(0x1000000000),
		},
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
		&pipelines[PipelineIndex.Transform].handle,
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
		log(.Fatal, "Failed to create shadow map colour image!")
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
		log(.Fatal, "Failed to create shadow map depth image!")
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
			image = pipelines[PipelineIndex.Light].images[0].handle,
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
			image = pipelines[PipelineIndex.Light].images[1].handle,
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
	pipelineCache: vk.PipelineCache = 0,
) {
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

	vertexBindingDescription := VERTEX_BINDING_DESCRIPTION
	pipelineInfo := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &vk.PipelineRenderingCreateInfo {
			sType                   = .PIPELINE_RENDERING_CREATE_INFO,
			pNext                   = &vk.PipelineCreateFlags2CreateInfo {
				sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
				pNext = nil,
				// VK_PIPELINE_CREATE_2_DESCRIPTOR_HEAP_BIT_EXT = 0x1000000000ULL;
				flags = transmute(vk.PipelineCreateFlags2)u64(0x1000000000),
			},
			viewMask                = 0,
			colorAttachmentCount    = 1,
			pColorAttachmentFormats = &pipelines[PipelineIndex.Light].images[0].format,
			depthAttachmentFormat   = pipelines[PipelineIndex.Light].images[1].format,
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
		&pipelines[PipelineIndex.Light].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! %v", res)
	}
}

@(private = "file")
createScenePipelineImages :: proc(using graphicsData: ^GraphicsData) {
	err: Error

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
	}

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
	}

	pipelines[PipelineIndex.Scene].images[1].sampler = 0

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
			image = pipelines[PipelineIndex.Scene].images[0].handle,
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
			image = pipelines[PipelineIndex.Scene].images[1].handle,
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
	pipelineCache: vk.PipelineCache = 0,
) {
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

	vertexBindingDescription := VERTEX_BINDING_DESCRIPTION
	pipelineInfo: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &vk.PipelineRenderingCreateInfo {
			sType                   = .PIPELINE_RENDERING_CREATE_INFO,
			pNext                   = &vk.PipelineCreateFlags2CreateInfo {
				sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
				pNext = nil,
				// VK_PIPELINE_CREATE_2_DESCRIPTOR_HEAP_BIT_EXT = 0x1000000000ULL;
				flags = transmute(vk.PipelineCreateFlags2)u64(0x1000000000),
			},
			viewMask                = 0,
			colorAttachmentCount    = 1,
			pColorAttachmentFormats = &pipelines[PipelineIndex.Scene].images[0].format,
			depthAttachmentFormat   = pipelines[PipelineIndex.Scene].images[1].format,
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
		&pipelines[PipelineIndex.Scene].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! %v", res)
	}
}

@(private = "file")
createPostProcessPipelineImages :: proc(using graphicsData: ^GraphicsData) {
	err: Error
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
		logf(.Fatal, "Failed to create image! Error: %v", err)
	}

	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.PostProcess].images[1],
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

	cmdBuffer: vk.CommandBuffer
	cmdBuffer, err = beginSingleTimeCommands(graphicsData, computeCommandPool)
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
			image = pipelines[PipelineIndex.PostProcess].images[0].handle,
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
			image = pipelines[PipelineIndex.PostProcess].images[1].handle,
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
	}
}

@(private = "file")
createPostProcessPipeline :: proc(
	using graphicsData: ^GraphicsData,
	shader: []byte,
	pipelineCache: vk.PipelineCache = 0,
) {
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
		pNext              = &vk.PipelineCreateFlags2CreateInfo {
			sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
			pNext = nil,
			// VK_PIPELINE_CREATE_2_DESCRIPTOR_HEAP_BIT_EXT = 0x1000000000ULL;
			flags = transmute(vk.PipelineCreateFlags2)u64(0x1000000000),
		},
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
		&pipelines[PipelineIndex.PostProcess].handle,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline! vkResult: %v", res)
	}
}

@(private = "file")
deletePipeline :: proc(using graphicsData: ^GraphicsData, pipeline: ^Pipeline) {
	vk.DestroyPipeline(device, pipeline.handle, nil)
	if pipeline.images != nil {
		for &image in pipeline.images {
			deleteImage(graphicsData, &image)
		}
		delete(pipeline.images)
	}
}

// It is the callers responsibility to ensure they pass the correct
// number of shaders to satisfy pipeline creation.
// You will crash if you don't.
updatePipelineShaders :: proc(
	using graphicsData: ^GraphicsData,
	pipelineIndex: PipelineIndex,
	shaders: [][]byte,
	pipelineCache: vk.PipelineCache = 0,
) {
	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		log(.Error, "Failed to wait device idle? %v", res)
	}

	deletePipeline(graphicsData, &pipelines[pipelineIndex])
	switch pipelineIndex {
	case .Transform:
		createTransformPipeline(graphicsData, shaders[0], pipelineCache)
	case .Light:
		createLightPipeline(graphicsData, shaders, pipelineCache)
	case .Scene:
		createScenePipeline(graphicsData, shaders, pipelineCache)
	case .PostProcess:
		createPostProcessPipeline(graphicsData, shaders[0], pipelineCache)
	}

	graphicsData.rerecordCommands = true
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
	}
}

@(private = "file")
shutdownImgui :: proc(using graphicsData: ^GraphicsData) {
	imguiVulkan.Shutdown()
	imguiGLFW.Shutdown()
	imgui.DestroyContext(imguiContext)
}

@(private = "file")
updateLightBuffer :: proc(using graphicsData: ^GraphicsData, scene: ^Scene, delta: f32) {
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
		scene.resources.lightBuffers[currentFrame].mapped,
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
		scene.resources.boneBuffers[graphicsData.currentFrame].mapped,
		raw_data(boneTransforms),
		scene.boneCount * size_of(Mat4),
	)
	mem.copy(
		scene.resources.instanceBuffers[graphicsData.currentFrame].mapped,
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
		scene.resources.imageIndexBuffer.mapped,
		raw_data(textureIndices),
		textureIndicesLength * size_of(u32),
	)
}

@(private = "file")
updateCommandBuffers :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		logf(.Error, "Failed to wait for device idle! vkResult: %v", res)
		panic("Idk why this would ever fail.")
	}

	for bufferIndex in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Transform][bufferIndex], nil)
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Light][bufferIndex], nil)
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Scene][bufferIndex], nil)
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Main][bufferIndex], nil)
		vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Transform][bufferIndex], nil)

		recordTransformCommands(graphicsData, bufferIndex, scene)
		recordLightCommands(graphicsData, bufferIndex, scene)
		recordSceneCommands(graphicsData, bufferIndex, scene)
		recordMainCommands(graphicsData, bufferIndex, scene)
		recordPostProcessCommands(graphicsData, bufferIndex)
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
	cmdBuffer := commandBuffers[CmdBufferIndex.Transform][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
	}

	vk.CmdBindResourceHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.resourceBuffers[index].address,
				size = vk.DeviceSize(descriptorHeap.resourceBuffers[index].size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.resourceReserve),
		},
	)
	vk.CmdBindSamplerHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.samplerBuffer.address,
				size = vk.DeviceSize(descriptorHeap.samplerBuffer.size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.samplerReserve),
		},
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

		vk.CmdPushDataEXT(
			cmdBuffer,
			&vk.PushDataInfoEXT {
				sType = .PUSH_DATA_INFO_EXT,
				pNext = nil,
				offset = 0,
				data = vk.HostAddressRangeConstEXT{address = &pushConstants, size = int(OFFSET)},
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
					data = vk.HostAddressRangeConstEXT {
						address = &pushConstants.instanceCount,
						size = size_of(Transform_PushConstants) - int(OFFSET),
					},
				},
			)
			vk.CmdDispatch(cmdBuffer, u32(ceil(f32(mesh.vertexCount) / 64.0)), 1, 1)
			pushConstants.transformOffset += mesh.vertexCount * u32(len(model.instances))
		}
		pushConstants.instance += u32(len(model.instances))
	}

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Fatal, "Failed to record command buffer! vkResult: %v", res)
	}
}

@(private = "file")
recordMainCommands :: proc(using graphicsData: ^GraphicsData, index: u32, scene: ^Scene) {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = nil,
		pInheritanceInfo = nil,
	}

	cmdBuffer := commandBuffers[CmdBufferIndex.Main][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
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
				image = pipelines[PipelineIndex.Light].images[0].handle,
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
			image = pipelines[PipelineIndex.Light].images[0].handle,
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
			image = pipelines[PipelineIndex.Scene].images[0].handle,
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
			image = pipelines[PipelineIndex.Scene].images[1].handle,
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
			image = pipelines[PipelineIndex.Scene].images[0].handle,
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
			image = pipelines[PipelineIndex.Scene].images[1].handle,
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
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
	}

	vk.CmdBindResourceHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.resourceBuffers[index].address,
				size = vk.DeviceSize(descriptorHeap.resourceBuffers[index].size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.resourceReserve),
		},
	)
	vk.CmdBindSamplerHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.samplerBuffer.address,
				size = vk.DeviceSize(descriptorHeap.samplerBuffer.size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.samplerReserve),
		},
	)
	vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[PipelineIndex.Light].handle)

	vk.CmdBindVertexBuffers(
		cmdBuffer,
		0,
		1,
		&scene.resources.vertexBuffer.handle,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer(cmdBuffer, scene.resources.indexBuffer.handle, 0, .UINT32)

	pushConstants: Light_PushConstants = {
		layerIndex   = 0,
		vertexOffset = 0,
		vertexCount  = 0,
	}
	for layerIndex: u32 = 0; layerIndex < lightImageCount; layerIndex += 1 {
		OFFSET :: u32(offset_of(Light_PushConstants, vertexOffset))
		pushConstants.layerIndex = layerIndex
		vk.CmdPushDataEXT(
			cmdBuffer,
			&vk.PushDataInfoEXT {
				sType = .PUSH_DATA_INFO_EXT,
				pNext = nil,
				offset = 0,
				data = vk.HostAddressRangeConstEXT{address = &pushConstants, size = int(OFFSET)},
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
						data = vk.HostAddressRangeConstEXT {
							address = &pushConstants.vertexOffset,
							size = size_of(Light_PushConstants) - int(OFFSET),
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
	}

	if res := vk.EndCommandBuffer(cmdBuffer); res != .SUCCESS {
		logf(.Fatal, "Failed to record command buffer! vkResult: %v", res)
	}
}

@(private = "file")
recordSceneCommands :: proc(using graphicsData: ^GraphicsData, index: u32, scene: ^Scene) {
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
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
	}

	vk.CmdBindResourceHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.resourceBuffers[index].address,
				size = vk.DeviceSize(descriptorHeap.resourceBuffers[index].size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.resourceReserve),
		},
	)
	vk.CmdBindSamplerHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.samplerBuffer.address,
				size = vk.DeviceSize(descriptorHeap.samplerBuffer.size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.samplerReserve),
		},
	)
	vk.CmdBindPipeline(cmdBuffer, .GRAPHICS, pipelines[PipelineIndex.Scene].handle)

	vk.CmdBindVertexBuffers(
		cmdBuffer,
		0,
		1,
		&scene.resources.vertexBuffer.handle,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer(cmdBuffer, scene.resources.indexBuffer.handle, 0, .UINT32)

	pushConstants: Scene_PushConstants = {
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
					data = vk.HostAddressRangeConstEXT {
						address = &pushConstants,
						size = size_of(Scene_PushConstants),
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
			pushConstants.instanceOffset += u32(len(model.instances))
		}
	}

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

	cmdBuffer := commandBuffers[CmdBufferIndex.PostProcess][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to start recording compute commands! vkResult: %v", res)
	}

	imageBarriers := [?]vk.ImageMemoryBarrier2 {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			pNext = nil,
			srcStageMask = nil,
			srcAccessMask = nil,
			dstStageMask = {.BLIT},
			dstAccessMask = {.TRANSFER_WRITE},
			oldLayout = .GENERAL,
			newLayout = .TRANSFER_DST_OPTIMAL,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = pipelines[PipelineIndex.PostProcess].images[0].handle,
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
			image = pipelines[PipelineIndex.PostProcess].images[1].handle,
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
			srcImage = pipelines[PipelineIndex.Scene].images[0].handle,
			srcImageLayout = .TRANSFER_SRC_OPTIMAL,
			dstImage = pipelines[PipelineIndex.PostProcess].images[0].handle,
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
					{x = i32(RENDER_SIZE.x), y = i32(RENDER_SIZE.y), z = 1},
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
			filter = .LINEAR,
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
				dstStageMask = {.COMPUTE_SHADER},
				dstAccessMask = {.SHADER_STORAGE_READ},
				oldLayout = .TRANSFER_DST_OPTIMAL,
				newLayout = .GENERAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = pipelines[PipelineIndex.PostProcess].images[0].handle,
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

	vk.CmdBindResourceHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.resourceBuffers[index].address,
				size = vk.DeviceSize(descriptorHeap.resourceBuffers[index].size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.resourceReserve),
		},
	)
	vk.CmdBindSamplerHeapEXT(
		cmdBuffer,
		&vk.BindHeapInfoEXT {
			sType = .BIND_HEAP_INFO_EXT,
			pNext = nil,
			heapRange = vk.DeviceAddressRangeEXT {
				address = descriptorHeap.samplerBuffer.address,
				size = vk.DeviceSize(descriptorHeap.samplerBuffer.size),
			},
			reservedRangeOffset = 0,
			reservedRangeSize = vk.DeviceSize(descriptorHeap.samplerReserve),
		},
	)
	vk.CmdBindPipeline(cmdBuffer, .COMPUTE, pipelines[PipelineIndex.PostProcess].handle)

	pushConstants: PostProcess_PushConstants = {
		contrast   = contrast,
		brightness = brightness,
		saturation = saturation,
		exposure   = pow(f32(2.0), exposure),
		tonemapper = tonemapper,
		gamma      = gamma,
		drawLights = b32(drawLights),
	}
	vk.CmdPushDataEXT(
		cmdBuffer,
		&vk.PushDataInfoEXT {
			sType = .PUSH_DATA_INFO_EXT,
			pNext = nil,
			offset = 0,
			data = vk.HostAddressRangeConstEXT {
				address = &pushConstants,
				size = size_of(PostProcess_PushConstants),
			},
		},
	)

	vk.CmdDispatch(
		cmdBuffer,
		u32(ceil(f32(swapchain.extent.width) / 32)),
		u32(ceil(f32(swapchain.extent.height) / 32)),
		1,
	)

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

	cmdBuffer := commandBuffers[CmdBufferIndex.Imgui][index]
	if res := vk.BeginCommandBuffer(cmdBuffer, &beginInfo); res != .SUCCESS {
		logf(.Fatal, "Failed to being recording command buffer! vkResult: %v", res)
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
				image = pipelines[PipelineIndex.PostProcess].images[1].handle,
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
			image = pipelines[PipelineIndex.PostProcess].images[1].handle,
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
			image = swapchain.images[imageIndex].handle,
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
			srcImage = pipelines[PipelineIndex.PostProcess].images[1].handle,
			srcImageLayout = .TRANSFER_SRC_OPTIMAL,
			dstImage = swapchain.images[imageIndex].handle,
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
				image = swapchain.images[imageIndex].handle,
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
		graphicsData.updateResourceHeap = false
		graphicsData.rerecordCommands = false
	} else {
		if graphicsData.updateResourceHeap {
			for idx in 0 ..< MAX_FRAMES_IN_FLIGHT {
				deleteBuffer(graphicsData, &graphicsData.descriptorHeap.resourceBuffers[idx])
			}

			createResourceDescriptorHeap(graphicsData, scene)
			graphicsData.updateResourceHeap = false
		}

		if graphicsData.rerecordCommands {
			updateCommandBuffers(graphicsData, scene)
			graphicsData.rerecordCommands = false
		}
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
		semaphores[SemaphoreIndex.Image][currentFrame],
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

	vk.ResetCommandBuffer(commandBuffers[CmdBufferIndex.Imgui][currentFrame], {})
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
		logf(.Fatal, "Failed to submit command buffer! vkResult: %v", res)
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
		logf(.Fatal, "Failed to submit command buffer! vkResult: %v", res)
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
		logf(.Fatal, "Failed to submit command buffer! vkResult: %v", res)
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
		logf(.Fatal, "Failed to submit command buffer! vkResult: %v", res)
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

