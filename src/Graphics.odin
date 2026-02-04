#+feature using-stmt
package Valhalla

import "../imgui"
import imguiGLFW "../imgui/imgui_impl_glfw"
import imguiVulkan "../imgui/imgui_impl_vulkan"
import "../slang"
import "core:fmt"
import "core:mem"
import "core:strings"
import "vendor:glfw"
import img "vendor:stb/image"
import vk "vendor:vulkan"


// ###################################################################
// #                          Constants                              #
// ###################################################################


VERSION: u32 : (0 << 22) | (1 << 12) | (0)

IMGUI_ENABLED: bool : true

HDR_ENABLED: bool : true

@(private = "file")
REQUESTED_LAYERS: []cstring : {"VK_LAYER_KHRONOS_validation"}

@(private = "file")
DEVICE_EXTENSIONS: []cstring : {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME,
	vk.EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME,
	vk.KHR_MULTIVIEW_EXTENSION_NAME,
	vk.KHR_COMPUTE_SHADER_DERIVATIVES_EXTENSION_NAME,
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
	RenderPassError,
	DescriptorSetError,
	FrameBufferError,
	ImageError,
	ImguiError,
	PipelineError,
	BufferError,
	RecordCommandBufferError,
	DrawError,
}

vkDebugMessengerCreateInfo :: vk.DebugUtilsMessengerCreateInfoEXT

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
	viewProjection: Mat4,
	lightCount:     u32,
}

@(private = "file")
InstanceInfo :: struct #align (16) {
	modelTransform: Mat4,
	boneOffset:     u32,
}

@(private = "file")
PipelineIndex :: enum {
	PRECOMPUTE,
	LIGHT,
	MAIN,
	POSTPROCESS,
}

TextureIndex :: enum {
	ALBEDO,
	NORMAL_MAP,
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
	contrast:                  f32,
	brightness:                f32,
	saturation:                f32,
	exposure:                  f32,
	tonemapper:                enum i32 {
		None          = 0,
		NarkowiczACES = 1,
	},
	gamma:                     f32,

	// GLFW + IMGUI
	window:                    glfw.WindowHandle,
	imguiData:                 ImguiData,

	// Vulkan Data
	instance:                  vk.Instance,
	debugMessenger:            vk.DebugUtilsMessengerEXT,
	surface:                   vk.SurfaceKHR,
	physicalDevice:            vk.PhysicalDevice,
	device:                    vk.Device,

	// Queues
	queueFamilies:             QueueFamilyIndices,
	graphicsQueue:             vk.Queue,
	presentQueue:              vk.Queue,
	computeQueue:              vk.Queue,

	// Swapchain
	swapchainTransform:        vk.SurfaceTransformFlagsKHR,
	swapchain:                 vk.SwapchainKHR,
	swapchainFormat:           vk.SurfaceFormatKHR,
	swapchainMode:             vk.PresentModeKHR,
	swapchainExtent:           vk.Extent2D,
	swapchainImages:           []vk.Image,
	swapchainImageViews:       []vk.ImageView,

	// Pipelines
	shaderFiles:               [dynamic]Shader,
	descriptorSets:            [len(DescriptorSetIndex)]DescriptorSet,
	pipelines:                 [len(PipelineIndex)]Pipeline,

	// Frame Resources
	depthFormat:               vk.Format,
	inFlightFrames:            [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	preComputeFinished:        [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	rendersFinished:           [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	computeFinished:           [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	imguiFinished:             [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	imagesAvailable:           [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,

	// Commands
	graphicsCommandPool:       vk.CommandPool,
	computeCommandPool:        vk.CommandPool,
	preComputeCommandBuffers:  [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	mainCommandBuffers:        [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	shadowMapCommandBuffers:   [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	sceneCommandBuffers:       [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	postComputeCommandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	imguiCommandBuffers:       [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	samplers:                  []vk.Sampler,

	// Buffer
	uniformBuffers:            [MAX_FRAMES_IN_FLIGHT]Buffer,

	// Images for post processing
	renderedImage:             Image,
	processedImage:            Image,

	// Util
	currentFrame:              u32,
	drawLights:                bool,
	reloadBuffers:             bool,
	rerecordCommands:          bool,
}

@(private = "file")
ImguiData :: struct {
	imguiContext:   ^imgui.Context,
	frameBuffers:   []vk.Framebuffer,
	descriptorPool: vk.DescriptorPool,
	renderPass:     vk.RenderPass,
	colour:         Image,
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
	BUFFERS  = 0,
	TEXTURES = 1,
}

@(private = "file")
Pipeline :: struct {
	using _:    RenderPass,
	layout:     vk.PipelineLayout,
	pipeline:   vk.Pipeline,
	shaderIdxs: [2]u32,
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

InitInfo :: struct {
	appVersion:  u32,
	windowTitle: cstring,

	// Shaders
	shaderFiles: []Shader,
	preComp:     u32,
	lightVert:   u32,
	lightFrag:   u32,
	mainVert:    u32,
	mainFrag:    u32,
	postComp:    u32,
}

InitError :: enum {
	None = 0,
	InitError,
	GLFWError,
	DepthFormatError,
}

@(require_results)
initVkGraphics :: proc(initInfo: InitInfo) -> (graphicsData: GraphicsData, err: Error) {
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
		logf(.Warning, "Failed to create vulkan debug callback! vkResult: %v", res)
	}

	initWindow(&graphicsData, initInfo.windowTitle) or_return
	pickPhysicalDevice(&graphicsData) or_return
	createLogicalDevice(&graphicsData) or_return
	createSwapchain(&graphicsData) or_return
	createCommandBuffers(&graphicsData) or_return

	pipelines[PipelineIndex.LIGHT].frameBuffers = make([]vk.Framebuffer, len(swapchainImages))

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
	createRenderPass(&graphicsData) or_return
	createMainFrameBuffers(&graphicsData) or_return
	createBuffersDescriptorSets(&graphicsData) or_return
	createTexturesDescriptorSets(&graphicsData) or_return

	append(&shaderFiles, ..initInfo.shaderFiles)

	createGraphicsPipelines(
		&graphicsData,
		{initInfo.lightVert, initInfo.lightFrag},
		{initInfo.mainVert, initInfo.mainFrag},
	) or_return

	createComputePipelines(&graphicsData, initInfo.preComp, initInfo.postComp) or_return

	when IMGUI_ENABLED {
		initImgui(&graphicsData) or_return
		updateImgui(&graphicsData) or_return
	}

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

	when IMGUI_ENABLED {
		cleanupImgui(graphicsData)
		vk.DestroyDescriptorPool(device, imguiData.descriptorPool, nil)
	}

	vk.FreeCommandBuffers(device, computeCommandPool, 2, &preComputeCommandBuffers[0])
	vk.FreeCommandBuffers(device, graphicsCommandPool, 2, &mainCommandBuffers[0])
	vk.FreeCommandBuffers(device, graphicsCommandPool, 2, &shadowMapCommandBuffers[0])
	vk.FreeCommandBuffers(device, graphicsCommandPool, 2, &sceneCommandBuffers[0])
	when IMGUI_ENABLED {
		vk.FreeCommandBuffers(device, computeCommandPool, 2, &postComputeCommandBuffers[0])
		vk.FreeCommandBuffers(
			device,
			graphicsCommandPool,
			u32(len(swapchainImages)),
			&imguiCommandBuffers[0],
		)
	} else {
		vk.FreeCommandBuffers(
			device,
			computeCommandPool,
			u32(len(swapchainImages)),
			raw_data(postComputeCommandBuffers),
		)
	}

	vk.DestroyCommandPool(device, graphicsCommandPool, nil)
	vk.DestroyCommandPool(device, computeCommandPool, nil)

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroyFence(device, inFlightFrames[index], nil)
		vk.DestroySemaphore(device, preComputeFinished[index], nil)
		vk.DestroySemaphore(device, rendersFinished[index], nil)
		vk.DestroySemaphore(device, computeFinished[index], nil)
		vk.DestroySemaphore(device, imguiFinished[index], nil)
		vk.DestroySemaphore(device, imagesAvailable[index], nil)
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		deleteBuffer(graphicsData, &uniformBuffers[index])
	}

	for index in 0 ..< len(swapchainImages) {
		vk.DestroyFramebuffer(device, pipelines[PipelineIndex.MAIN].frameBuffers[index], nil)
		vk.DestroyFramebuffer(device, pipelines[PipelineIndex.LIGHT].frameBuffers[index], nil)
	}
	delete(pipelines[PipelineIndex.MAIN].frameBuffers)
	delete(pipelines[PipelineIndex.LIGHT].frameBuffers)

	delete(shaderFiles)

	cleanupSwapchain(graphicsData)
	cleanupPipelines(graphicsData)

	vk.DestroyRenderPass(device, pipelines[PipelineIndex.MAIN].renderPass, nil)
	vk.DestroyRenderPass(device, pipelines[PipelineIndex.LIGHT].renderPass, nil)

	deleteImage(graphicsData, &pipelines[PipelineIndex.MAIN].colour)
	deleteImage(graphicsData, &pipelines[PipelineIndex.MAIN].depth)
	deleteImage(graphicsData, &pipelines[PipelineIndex.LIGHT].colour)
	deleteImage(graphicsData, &pipelines[PipelineIndex.LIGHT].depth)

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

	slang.shutdown()

	glfw.DestroyWindow(window)
	glfw.Terminate()
}

setGLFWErrorCallback :: proc(errorCallback: GLFWErrorCallback) {
	glfw.SetErrorCallback(errorCallback)
}

setGLFWKeyCallback :: proc(window: glfw.WindowHandle, keyCallback: GLFWKeyCallback) {
	glfw.SetKeyCallback(window, keyCallback)
}

setGLFWMouseButtonCallback :: proc(
	window: glfw.WindowHandle,
	mouseButtonCallback: GLFWMouseButtonCallback,
) {
	glfw.SetMouseButtonCallback(window, mouseButtonCallback)
}

setGLFWCursorPosCallback :: proc(
	window: glfw.WindowHandle,
	cursorPosCallback: GLFWCursorPosCallback,
) {
	glfw.SetCursorPosCallback(window, cursorPosCallback)
}

setGLFWScrollCallback :: proc(window: glfw.WindowHandle, scrollCallback: GLFWScrollCallback) {
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

	instanceInfo: vk.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pNext                   = nil,
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
		physicalDeviceProperties: vk.PhysicalDeviceProperties
		physicalDeviceFeatures: vk.PhysicalDeviceFeatures

		vk.GetPhysicalDeviceProperties(physicalDevice, &physicalDeviceProperties)
		vk.GetPhysicalDeviceFeatures(physicalDevice, &physicalDeviceFeatures)

		indices, err := findQueueFamilies(physicalDevice, graphicsData)
		if err ||
		   !physicalDeviceFeatures.samplerAnisotropy ||
		   !checkDeviceExtensionSupport(physicalDevice) ||
		   !swapchainAdequate(physicalDevice, graphicsData) {
			return
		}

		if physicalDeviceProperties.deviceType == .DISCRETE_GPU {
			score += 1000
		}

		if indices.graphicsFamily == indices.presentFamily {
			score += 100
		}

		if indices.graphicsFamily == indices.computeFamily {
			score += 100
		}

		score += physicalDeviceProperties.limits.maxImageDimension2D
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
		physicalDeviceProperties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(physicalDevice, &physicalDeviceProperties)

		counts :=
			physicalDeviceProperties.limits.framebufferColorSampleCounts &
			physicalDeviceProperties.limits.framebufferDepthSampleCounts
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

	if queueFamilies.graphicsFamily != queueFamilies.computeFamily {
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

	deviceFeatures: vk.PhysicalDeviceFeatures = {
		robustBufferAccess                      = false,
		fullDrawIndexUint32                     = false,
		imageCubeArray                          = true,
		independentBlend                        = false,
		geometryShader                          = false,
		tessellationShader                      = false,
		sampleRateShading                       = false,
		dualSrcBlend                            = false,
		logicOp                                 = false,
		multiDrawIndirect                       = false,
		drawIndirectFirstInstance               = false,
		depthClamp                              = false,
		depthBiasClamp                          = false,
		fillModeNonSolid                        = false,
		depthBounds                             = false,
		wideLines                               = false,
		largePoints                             = false,
		alphaToOne                              = false,
		multiViewport                           = false,
		samplerAnisotropy                       = true,
		textureCompressionETC2                  = false,
		textureCompressionASTC_LDR              = false,
		textureCompressionBC                    = false,
		occlusionQueryPrecise                   = false,
		pipelineStatisticsQuery                 = false,
		vertexPipelineStoresAndAtomics          = false,
		fragmentStoresAndAtomics                = false,
		shaderTessellationAndGeometryPointSize  = false,
		shaderImageGatherExtended               = false,
		shaderStorageImageExtendedFormats       = false,
		shaderStorageImageMultisample           = false,
		shaderStorageImageReadWithoutFormat     = false,
		shaderStorageImageWriteWithoutFormat    = false,
		shaderUniformBufferArrayDynamicIndexing = false,
		shaderSampledImageArrayDynamicIndexing  = false,
		shaderStorageBufferArrayDynamicIndexing = false,
		shaderStorageImageArrayDynamicIndexing  = false,
		shaderClipDistance                      = false,
		shaderCullDistance                      = false,
		shaderFloat64                           = false,
		shaderInt64                             = false,
		shaderInt16                             = false,
		shaderResourceResidency                 = false,
		shaderResourceMinLod                    = false,
		sparseBinding                           = false,
		sparseResidencyBuffer                   = false,
		sparseResidencyImage2D                  = false,
		sparseResidencyImage3D                  = false,
		sparseResidency2Samples                 = false,
		sparseResidency4Samples                 = false,
		sparseResidency8Samples                 = false,
		sparseResidency16Samples                = false,
		sparseResidencyAliased                  = false,
		variableMultisampleRate                 = false,
		inheritedQueries                        = false,
	}

	multiview: vk.PhysicalDeviceMultiviewFeatures = {
		sType                       = .PHYSICAL_DEVICE_MULTIVIEW_FEATURES,
		pNext                       = nil,
		multiview                   = true,
		multiviewGeometryShader     = false,
		multiviewTessellationShader = false,
	}

	sync2: vk.PhysicalDeviceSynchronization2Features = {
		sType            = .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES,
		pNext            = &multiview,
		synchronization2 = true,
	}

	computeShaderDerivatives: vk.PhysicalDeviceComputeShaderDerivativesFeaturesNV = {
		sType                        = .PHYSICAL_DEVICE_COMPUTE_SHADER_DERIVATIVES_FEATURES_NV,
		pNext                        = &sync2,
		computeDerivativeGroupQuads  = true,
		computeDerivativeGroupLinear = false,
	}

	requiredDeviceExtensions := DEVICE_EXTENSIONS
	createInfo: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &computeShaderDerivatives,
		flags                   = {},
		queueCreateInfoCount    = u32(len(queueCreateInfos)),
		pQueueCreateInfos       = raw_data(queueCreateInfos),
		enabledLayerCount       = u32(len(REQUESTED_LAYERS)),
		ppEnabledLayerNames     = raw_data(REQUESTED_LAYERS),
		enabledExtensionCount   = u32(len(requiredDeviceExtensions)),
		ppEnabledExtensionNames = raw_data(requiredDeviceExtensions),
		pEnabledFeatures        = &deviceFeatures,
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

@(private = "file")
@(require_results)
createSwapchain :: proc(using graphicsData: ^GraphicsData) -> SwapchainError {
	chooseFormat :: proc(formats: []vk.SurfaceFormatKHR) -> (fmt: vk.SurfaceFormatKHR) {
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

	swapchainSupport := querySwapchainSupport(physicalDevice, graphicsData)

	max := swapchainSupport.capabilities.maxImageCount
	min := swapchainSupport.capabilities.minImageCount
	swapchainImageCount := max if max == 1 else (2 if 2 > min else min)
	swapchainTransform = swapchainSupport.capabilities.currentTransform

	swapchainFormat = chooseFormat(swapchainSupport.formats)
	swapchainMode = choosePresentMode(swapchainSupport.modes)
	swapchainExtent = chooseExtent(graphicsData, swapchainSupport.capabilities)

	oneQueueFamily :=
		queueFamilies.graphicsFamily == queueFamilies.presentFamily &&
		queueFamilies.graphicsFamily == queueFamilies.computeFamily
	createInfo: vk.SwapchainCreateInfoKHR = {
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		pNext                 = nil,
		flags                 = {},
		surface               = surface,
		minImageCount         = swapchainImageCount,
		imageFormat           = swapchainFormat.format,
		imageColorSpace       = swapchainFormat.colorSpace,
		imageExtent           = swapchainExtent,
		imageArrayLayers      = 1,
		imageUsage            = {.TRANSFER_DST, .COLOR_ATTACHMENT},
		imageSharingMode      = oneQueueFamily ? .EXCLUSIVE : .CONCURRENT,
		queueFamilyIndexCount = oneQueueFamily ? 0 : 3,
		pQueueFamilyIndices   = oneQueueFamily ? nil : raw_data([]u32{queueFamilies.graphicsFamily, queueFamilies.presentFamily, queueFamilies.computeFamily}),
		preTransform          = swapchainTransform,
		compositeAlpha        = {.OPAQUE},
		presentMode           = swapchainMode,
		clipped               = true,
		oldSwapchain          = {},
	}

	if res := vk.CreateSwapchainKHR(device, &createInfo, nil, &swapchain); res != .SUCCESS {
		log(.Fatal, "Failed to create swapchain! vkResult: %v", res)
		return .FailedToCreateSwapchain
	}

	swapchainImages = make([]vk.Image, swapchainImageCount)
	vk.GetSwapchainImagesKHR(device, swapchain, &swapchainImageCount, raw_data(swapchainImages))

	swapchainImageViews = make([]vk.ImageView, swapchainImageCount)
	for index in 0 ..< swapchainImageCount {
		err: ImageError
		swapchainImageViews[index], err = createImageView(
			graphicsData,
			swapchainImages[index],
			.D2,
			swapchainFormat.format,
			{.COLOR},
			1,
		)
		if err != .None {
			log(.Fatal, "Failed to create swapchain image view! vkResult: %v", err)
			return .FailedToCreateSwapchainImageView
		}
	}

	return .None
}

@(private = "file")
@(require_results)
recreateSwapchain :: proc(using graphicsData: ^GraphicsData) -> (err: Error) {
	width, height := glfw.GetFramebufferSize(window)
	for width == 0 && height == 0 {
		glfw.WaitEvents()
		width, height = glfw.GetFramebufferSize(window)
	}

	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		log(.Error, "Failed to wait for device idle! vkResult: %v", res)
		return .FailedToRecreateSwapchain
	}

	cleanupSwapchain(graphicsData)

	err = createSwapchain(graphicsData)
	if err != nil {
		log(.Error, "Failed to recreate swapchain!")
		return err
	}

	err = updateComputeDescriptorSets(graphicsData)
	if err != nil {
		log(.Error, "Failed to update compute descriptor sets!")
		return err
	}

	when IMGUI_ENABLED {
		cleanupImgui(graphicsData)
		err = updateImgui(graphicsData)
		if err != nil {
			log(.Fatal, "Failed to update Imgui!")
			return err
		}
	}

	return nil
}

@(private = "file")
cleanupSwapchain :: proc(using graphicsData: ^GraphicsData) {
	for imageView in swapchainImageViews {
		vk.DestroyImageView(device, imageView, nil)
	}
	delete(swapchainImages)
	delete(swapchainImageViews)

	vk.DestroySwapchainKHR(device, swapchain, nil)
	deleteImage(graphicsData, &renderedImage)
	deleteImage(graphicsData, &processedImage)
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
	if res := vk.AllocateCommandBuffers(device, &allocInfo, &mainCommandBuffers[0]);
	   res != .SUCCESS {
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
	if res := vk.AllocateCommandBuffers(device, &allocInfo, &shadowMapCommandBuffers[0]);
	   res != .SUCCESS {
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
	if res := vk.AllocateCommandBuffers(device, &allocInfo, &sceneCommandBuffers[0]);
	   res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	when IMGUI_ENABLED {
		allocInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			pNext              = nil,
			commandPool        = graphicsCommandPool,
			level              = .PRIMARY,
			commandBufferCount = u32(len(swapchainImages)),
		}
		if res := vk.AllocateCommandBuffers(device, &allocInfo, &imguiCommandBuffers[0]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
			return .FailedToAllocateCommandBuffer
		}
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
	if res := vk.AllocateCommandBuffers(device, &allocInfo, &preComputeCommandBuffers[0]);
	   res != .SUCCESS {
		logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
		return .FailedToAllocateCommandBuffer
	}

	when IMGUI_ENABLED {
		allocInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			pNext              = nil,
			commandPool        = computeCommandPool,
			level              = .PRIMARY,
			commandBufferCount = MAX_FRAMES_IN_FLIGHT,
		}
		if res := vk.AllocateCommandBuffers(device, &allocInfo, &postComputeCommandBuffers[0]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
			return .FailedToAllocateCommandBuffer
		}
	} else {
		allocInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			pNext              = nil,
			commandPool        = computeCommandPool,
			level              = .PRIMARY,
			commandBufferCount = u32(len(swapchainImages)),
		}
		if res := vk.AllocateCommandBuffers(device, &allocInfo, &postComputeCommandBuffers[0]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to allocate command buffer! vkResult: %v", res)
			return .FailedToAllocateCommandBuffer
		}
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
	blit: vk.ImageBlit = {
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

	vk.CmdBlitImage(
		commandBuffer,
		src,
		.TRANSFER_SRC_OPTIMAL,
		dst,
		.TRANSFER_DST_OPTIMAL,
		1,
		&blit,
		.LINEAR,
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

	updateShadowMapFrameBuffer(graphicsData, scene)

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
		&descriptorSets[DescriptorSetIndex.BUFFERS].layout,
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
		&descriptorSets[DescriptorSetIndex.BUFFERS].pool,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor pool! vkResult: %d", res)
		return .FailedToCreateDescriptorPool
	}

	layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT, context.temp_allocator)
	for &layout in layouts {
		layout = descriptorSets[DescriptorSetIndex.BUFFERS].layout
	}

	allocInfo: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = descriptorSets[DescriptorSetIndex.BUFFERS].pool,
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts),
	}

	if res := vk.AllocateDescriptorSets(
		device,
		&allocInfo,
		raw_data(descriptorSets[DescriptorSetIndex.BUFFERS].sets[:]),
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
		&descriptorSets[DescriptorSetIndex.TEXTURES].layout,
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
		&descriptorSets[DescriptorSetIndex.TEXTURES].pool,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create descriptor pool! vkResult: %d", res)
		return .FailedToCreateDescriptorPool
	}

	layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT, context.temp_allocator)
	for &layout in layouts {
		layout = descriptorSets[DescriptorSetIndex.TEXTURES].layout
	}

	allocInfo: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = descriptorSets[DescriptorSetIndex.TEXTURES].pool,
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts),
	}

	if res := vk.AllocateDescriptorSets(
		device,
		&allocInfo,
		raw_data(descriptorSets[DescriptorSetIndex.TEXTURES].sets[:]),
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
		sampler     = samplers[pipelines[PipelineIndex.LIGHT].colour.sampler],
		imageView   = pipelines[PipelineIndex.LIGHT].colour.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	sceneDepthInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[pipelines[PipelineIndex.MAIN].depth.sampler],
		imageView   = pipelines[PipelineIndex.MAIN].depth.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	if renderedImage.vkImage != 0 {
		deleteImage(graphicsData, &renderedImage)
		deleteImage(graphicsData, &processedImage)
	}

	renderedImage.format = .R16G16B16A16_SFLOAT
	err = createImage(
		graphicsData,
		&renderedImage,
		{},
		.D2,
		swapchainExtent.width,
		swapchainExtent.height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .STORAGE},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != .None {
		logf(.Fatal, "Failed to create rendered image! Error: %v", err)
		return err
	}

	renderedImage.view, err = createImageView(
		graphicsData,
		renderedImage.vkImage,
		.D2,
		renderedImage.format,
		{.COLOR},
		1,
	)
	if err != .None {
		logf(.Fatal, "Failed to create image view for rendered image! Error: %v", err)
		return err
	}

	processedImage.format = .R16G16B16A16_SFLOAT
	err = createImage(
		graphicsData,
		&processedImage,
		{},
		.D2,
		swapchainExtent.width,
		swapchainExtent.height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_SRC, .STORAGE},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != .None {
		logf(.Fatal, "Failed to create processed image! Error: %v", err)
		return err
	}

	processedImage.view, err = createImageView(
		graphicsData,
		processedImage.vkImage,
		.D2,
		processedImage.format,
		{.COLOR},
		1,
	)
	if err != .None {
		logf(.Fatal, "Failed to create image view for processed image! Error: %v", err)
		return err
	}

	renderedImageInfo: vk.DescriptorImageInfo = {
		imageView   = renderedImage.view,
		imageLayout = .GENERAL,
	}

	processedImageInfo: vk.DescriptorImageInfo = {
		imageView   = processedImage.view,
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.BUFFERS].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
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
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
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
@(require_results)
updateComputeDescriptorSets :: proc(using graphicsData: ^GraphicsData) -> ImageError {
	renderedImage.format = .R16G16B16A16_SFLOAT
	err := createImage(
		graphicsData,
		&renderedImage,
		{},
		.D2,
		swapchainExtent.width,
		swapchainExtent.height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .STORAGE},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != .None {
		log(.Fatal, "Failed to create rendered image!")
		return err
	}

	renderedImage.view, err = createImageView(
		graphicsData,
		renderedImage.vkImage,
		.D2,
		renderedImage.format,
		{.COLOR},
		1,
	)
	if err != .None {
		log(.Fatal, "Failed to create rendered image view!")
		return err
	}

	processedImage.format = .R16G16B16A16_SFLOAT
	err = createImage(
		graphicsData,
		&processedImage,
		{},
		.D2,
		swapchainExtent.width,
		swapchainExtent.height,
		1,
		{._1},
		.OPTIMAL,
		{.TRANSFER_SRC, .STORAGE},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)
	if err != .None {
		log(.Fatal, "Failed to create processed image!")
		return err
	}

	processedImage.view, err = createImageView(
		graphicsData,
		processedImage.vkImage,
		.D2,
		processedImage.format,
		{.COLOR},
		1,
	)
	if err != .None {
		log(.Fatal, "Failed to create processed image view!")
		return err
	}

	sceneDepthInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[pipelines[PipelineIndex.MAIN].depth.sampler],
		imageView   = pipelines[PipelineIndex.MAIN].depth.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	renderedImageInfo: vk.DescriptorImageInfo = {
		imageView   = renderedImage.view,
		imageLayout = .GENERAL,
	}

	processedImageInfo: vk.DescriptorImageInfo = {
		imageView   = processedImage.view,
		imageLayout = .GENERAL,
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
				dstBinding = 3,
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
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
				dstBinding = 4,
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
				dstSet = descriptorSets[DescriptorSetIndex.TEXTURES].sets[index],
				dstBinding = 5,
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

		if res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &preComputeFinished[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create semaphore! vkResult: %d", res)
			return .FailedToCreateSemaphore
		}

		if res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &rendersFinished[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create semaphore! vkResult: %d", res)
			return .FailedToCreateSemaphore
		}

		if res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &computeFinished[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create semaphore! vkResult: %d", res)
			return .FailedToCreateSemaphore
		}

		if res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &imguiFinished[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create semaphore! vkResult: %d", res)
			return .FailedToCreateSemaphore
		}

		if res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &imagesAvailable[index]);
		   res != .SUCCESS {
			logf(.Fatal, "Failed to create semaphore! vkResult: %d", res)
			return .FailedToCreateSemaphore
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

RenderPassError :: enum {
	None = 0,
	FailedToCreateRenderPass,
}

@(private = "file")
RenderPass :: struct {
	frameBuffers: []vk.Framebuffer,
	colour:       Image,
	depth:        Image,
	renderPass:   vk.RenderPass,
	descriptor:   vk.DescriptorImageInfo,
}

@(private = "file")
@(require_results)
createRenderPass :: proc(using graphicsData: ^GraphicsData) -> (err: Error) {
	// SHADOW
	{
		colourAttachment: vk.AttachmentDescription = {
			flags          = {},
			format         = .R32_SFLOAT,
			samples        = {._1},
			loadOp         = .CLEAR,
			storeOp        = .STORE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .SHADER_READ_ONLY_OPTIMAL,
			finalLayout    = .SHADER_READ_ONLY_OPTIMAL,
		}

		depthAttachment: vk.AttachmentDescription = {
			flags          = {},
			format         = depthFormat,
			samples        = {._1},
			loadOp         = .CLEAR,
			storeOp        = .DONT_CARE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .UNDEFINED,
			finalLayout    = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		}

		colourAttachmentRef: vk.AttachmentReference = {
			attachment = 0,
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}

		depthAttachmentRef: vk.AttachmentReference = {
			attachment = 1,
			layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		}

		subpass: vk.SubpassDescription = {
			flags                   = {},
			pipelineBindPoint       = .GRAPHICS,
			inputAttachmentCount    = 0,
			pInputAttachments       = nil,
			colorAttachmentCount    = 1,
			pColorAttachments       = &colourAttachmentRef,
			pResolveAttachments     = nil,
			pDepthStencilAttachment = &depthAttachmentRef,
			preserveAttachmentCount = 0,
			pPreserveAttachments    = nil,
		}

		renderPassInfo: vk.RenderPassCreateInfo = {
			sType           = .RENDER_PASS_CREATE_INFO,
			pNext           = nil,
			flags           = {},
			attachmentCount = 2,
			pAttachments    = raw_data(
				[]vk.AttachmentDescription{colourAttachment, depthAttachment},
			),
			subpassCount    = 1,
			pSubpasses      = &subpass,
			dependencyCount = 0,
			pDependencies   = nil,
		}

		if res := vk.CreateRenderPass(
			device,
			&renderPassInfo,
			nil,
			&pipelines[PipelineIndex.LIGHT].renderPass,
		); res != .SUCCESS {
			logf(.Fatal, "Unable to create render pass! vkResult: %d", res)
			return .FailedToCreateRenderPass
		}
	}

	// MAIN
	{
		pipelines[PipelineIndex.MAIN].colour.format = .R16G16B16A16_SFLOAT

		err = createImage(
			graphicsData,
			&pipelines[PipelineIndex.MAIN].colour,
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
			return err
		}

		pipelines[PipelineIndex.MAIN].colour.view, err = createImageView(
			graphicsData,
			pipelines[PipelineIndex.MAIN].colour.vkImage,
			.D2,
			pipelines[PipelineIndex.MAIN].colour.format,
			{.COLOR},
			1,
		)
		if err != nil {
			log(.Fatal, "Failed to create colour image view!")
			return err
		}

		pipelines[PipelineIndex.MAIN].depth.format = depthFormat

		err = createImage(
			graphicsData,
			&pipelines[PipelineIndex.MAIN].depth,
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
			return err
		}

		pipelines[PipelineIndex.MAIN].depth.view, err = createImageView(
			graphicsData,
			pipelines[PipelineIndex.MAIN].depth.vkImage,
			.D2,
			pipelines[PipelineIndex.MAIN].depth.format,
			{.DEPTH},
			1,
		)
		if err != nil {
			log(.Fatal, "Failed to create depth image view!")
			return err
		}

		pipelines[PipelineIndex.MAIN].depth.sampler = 0

		attachments: []vk.AttachmentDescription = {
			{
				flags = {},
				format = pipelines[PipelineIndex.MAIN].colour.format,
				samples = {._1},
				loadOp = .CLEAR,
				storeOp = .STORE,
				stencilLoadOp = .DONT_CARE,
				stencilStoreOp = .DONT_CARE,
				initialLayout = .UNDEFINED,
				finalLayout = .TRANSFER_SRC_OPTIMAL,
			},
			{
				flags = {},
				format = pipelines[PipelineIndex.MAIN].depth.format,
				samples = {._1},
				loadOp = .CLEAR,
				storeOp = .STORE,
				stencilLoadOp = .DONT_CARE,
				stencilStoreOp = .DONT_CARE,
				initialLayout = .UNDEFINED,
				finalLayout = .SHADER_READ_ONLY_OPTIMAL,
			},
		}

		colourAttachmentRef: vk.AttachmentReference = {
			attachment = 0,
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}

		depthAttachmentRef: vk.AttachmentReference = {
			attachment = 1,
			layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		}

		subpass: vk.SubpassDescription = {
			flags                   = {},
			pipelineBindPoint       = .GRAPHICS,
			inputAttachmentCount    = 0,
			pInputAttachments       = nil,
			colorAttachmentCount    = 1,
			pColorAttachments       = &colourAttachmentRef,
			pResolveAttachments     = nil,
			pDepthStencilAttachment = &depthAttachmentRef,
			preserveAttachmentCount = 0,
			pPreserveAttachments    = nil,
		}

		renderPassInfo: vk.RenderPassCreateInfo = {
			sType           = .RENDER_PASS_CREATE_INFO,
			pNext           = nil,
			flags           = {},
			attachmentCount = 2,
			pAttachments    = raw_data(attachments),
			subpassCount    = 1,
			pSubpasses      = &subpass,
			dependencyCount = 0,
			pDependencies   = nil,
		}

		if res := vk.CreateRenderPass(
			device,
			&renderPassInfo,
			nil,
			&pipelines[PipelineIndex.MAIN].renderPass,
		); res != .SUCCESS {
			logf(.Error, "Failed to create render pass! vkResult: %d", res)
			return .FailedToCreateRenderPass
		}
	}

	return nil
}

FrameBufferError :: enum {
	None = 0,
	FailedToCreateFrameBuffer,
}

@(private = "file")
@(require_results)
createMainFrameBuffers :: proc(using graphicsData: ^GraphicsData) -> FrameBufferError {
	frameBufferInfo: vk.FramebufferCreateInfo = {
		sType           = .FRAMEBUFFER_CREATE_INFO,
		pNext           = nil,
		flags           = {},
		renderPass      = pipelines[PipelineIndex.MAIN].renderPass,
		attachmentCount = 2,
		pAttachments    = raw_data(
			[]vk.ImageView {
				pipelines[PipelineIndex.MAIN].colour.view,
				pipelines[PipelineIndex.MAIN].depth.view,
			},
		),
		width           = RENDER_SIZE.x,
		height          = RENDER_SIZE.y,
		layers          = 1,
	}

	pipelines[PipelineIndex.MAIN].frameBuffers = make([]vk.Framebuffer, len(swapchainImages))
	for index in 0 ..< len(swapchainImages) {
		if res := vk.CreateFramebuffer(
			device,
			&frameBufferInfo,
			nil,
			&pipelines[PipelineIndex.MAIN].frameBuffers[index],
		); res != .SUCCESS {
			logf(.Fatal, "Failed to create frame buffer! vkResult: %d", res)
			return .FailedToCreateFrameBuffer
		}
	}

	return .None
}

@(private = "file")
createShadowMapFrameBuffer :: proc(
	using graphicsData: ^GraphicsData,
	scene: ^Scene,
) -> (
	err: Error,
) {
	pipelines[PipelineIndex.LIGHT].colour.format = .R32_SFLOAT

	layerCount := u32(len(scene.lights)) * 6
	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.LIGHT].colour,
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

	pipelines[PipelineIndex.LIGHT].colour.view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.LIGHT].colour.vkImage,
		.CUBE_ARRAY,
		pipelines[PipelineIndex.LIGHT].colour.format,
		{.COLOR},
		layerCount,
	)
	if err != nil {
		log(.Error, "Failed to create shadow map colour image view!")
		return err
	}

	commandBuffer: vk.CommandBuffer
	commandBuffer, err = beginSingleTimeCommands(graphicsData, graphicsCommandPool)
	if err != nil {
		log(.Error, "Failed to begin single time commands!")
		return err
	}

	transitionImageLayout(
		graphicsData,
		commandBuffer,
		pipelines[PipelineIndex.LIGHT].colour.vkImage,
		.UNDEFINED,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR},
		layerCount,
	)
	err = endSingleTimeCommands(graphicsData, commandBuffer, graphicsCommandPool)
	if err != nil {
		log(.Error, "Failed to end single time commands!")
		return err
	}

	pipelines[PipelineIndex.LIGHT].depth.format = depthFormat

	err = createImage(
		graphicsData,
		&pipelines[PipelineIndex.LIGHT].depth,
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

	pipelines[PipelineIndex.LIGHT].depth.view, err = createImageView(
		graphicsData,
		pipelines[PipelineIndex.LIGHT].depth.vkImage,
		.CUBE_ARRAY,
		pipelines[PipelineIndex.LIGHT].depth.format,
		{.DEPTH},
		layerCount,
	)
	if err != nil {
		log(.Error, "Failed to create shadow map depth image view!")
		return err
	}

	frameBufferInfo: vk.FramebufferCreateInfo = {
		sType           = .FRAMEBUFFER_CREATE_INFO,
		pNext           = nil,
		flags           = {},
		renderPass      = pipelines[PipelineIndex.LIGHT].renderPass,
		attachmentCount = 2,
		pAttachments    = raw_data(
			[]vk.ImageView {
				pipelines[PipelineIndex.LIGHT].colour.view,
				pipelines[PipelineIndex.LIGHT].depth.view,
			},
		),
		width           = SHADOW_RESOLUTION.x,
		height          = SHADOW_RESOLUTION.y,
		layers          = layerCount,
	}

	for index in 0 ..< len(swapchainImages) {
		if res := vk.CreateFramebuffer(
			device,
			&frameBufferInfo,
			nil,
			&pipelines[PipelineIndex.LIGHT].frameBuffers[index],
		); res != .SUCCESS {
			logf(.Error, "Failed to create frame buffer! vkResult: %d", res)
			return FrameBufferError.FailedToCreateFrameBuffer
		}
	}

	return nil
}

@(private = "file")
updateShadowMapFrameBuffer :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) {
	if pipelines[PipelineIndex.LIGHT].colour != {} {
		for index in 0 ..< len(swapchainImages) {
			vk.DestroyFramebuffer(device, pipelines[PipelineIndex.LIGHT].frameBuffers[index], nil)
		}
		deleteImage(graphicsData, &pipelines[PipelineIndex.LIGHT].colour)
		deleteImage(graphicsData, &pipelines[PipelineIndex.LIGHT].depth)
	}

	createShadowMapFrameBuffer(graphicsData, scene)
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
createShaderModules :: proc(
	using graphicsData: ^GraphicsData,
	shaderIdx: u32,
	stage: slang.Stage,
) -> (
	vk.ShaderModule,
	PipelineError,
) {
	blobToString :: proc(blob: ^slang.Blob) -> string {
		if blob == nil {
			return ""
		}
		size := slang.getBlobSize(blob)
		if size == 0 {
			return ""
		}
		return strings.clone_from_bytes(([^]u8)(slang.getBlobData(blob))[:size])
	}

	diagnosticsBlob: ^slang.Blob
	desc := slang.Global_Session_Desc {
		searchPaths     = nil,
		searchPathCount = 0,
	}
	globalSession := slang.createGlobalSessionWithDesc(&desc)
	if globalSession == nil {
		return 0, .FailedToCreateShaderModule
	}

	compileTargets := []slang.Compile_Target{.SPIRV}
	sessionDesc := slang.Session_Desc {
		targets                = raw_data(compileTargets),
		targetCount            = i32(len(compileTargets)),
		searchPaths            = nil,
		searchPathCount        = 0,
		preprocessorMacros     = nil,
		preprocessorMacroCount = 0,
		matrixLayoutMode       = .COLUMN_MAJOR,
	}
	session := slang.createSessionWithProfile(
		globalSession,
		slang.findProfile(globalSession, "spirv_1_6"),
		&sessionDesc,
	)
	if session == nil {
		return 0, .FailedToCreateShaderModule
	}

	module := slang.loadModule(
		session,
		strings.clone_to_cstring(shaderFiles[shaderIdx].file, context.temp_allocator),
		&diagnosticsBlob,
	)
	if module == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		return 0, .FailedToCreateShaderModule
	}

	components: [2]slang.Component_Type
	components[0] = {
		kind   = .MODULE,
		module = module,
	}

	entryPoint := slang.findEntryPoint(
		module,
		strings.clone_to_cstring(shaderFiles[shaderIdx].entryPoint, context.temp_allocator),
		stage,
		&diagnosticsBlob,
	)
	if entryPoint == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		return 0, .FailedToCreateShaderModule
	}
	components[1] = {
		kind       = .ENTRY_POINT,
		entryPoint = entryPoint,
	}

	program := slang.createCompositeComponentType(
		session,
		&components[0],
		i32(len(components)),
		&diagnosticsBlob,
	)
	if program == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		return 0, .FailedToCreateShaderModule
	}

	linkedProgram := slang.linkComponentType(program, &diagnosticsBlob)
	if linkedProgram == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		return 0, .FailedToCreateShaderModule
	}

	codeBlob := slang.getEntryPointCode(linkedProgram, 0, 0, &diagnosticsBlob)
	if codeBlob == nil {
		log(.Error, blobToString(diagnosticsBlob))
		slang.releaseBlob(diagnosticsBlob)
		return 0, .FailedToCreateShaderModule
	}

	createInfo: vk.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		pNext    = nil,
		flags    = {},
		codeSize = int(slang.getBlobSize(codeBlob)),
		pCode    = (^u32)(slang.getBlobData(codeBlob)),
	}
	shaderModule: vk.ShaderModule
	if res := vk.CreateShaderModule(device, &createInfo, nil, &shaderModule); res != .SUCCESS {
		log(.Error, fmt.tprintln("Failed to create shader module! vkResult: %d", res))
		return 0, .FailedToCreateShaderModule
	}

	slang.releaseBlob(codeBlob)

	slang.releaseComponentType(linkedProgram)
	slang.releaseComponentType(program)
	slang.releaseEntryPoint(components[1].entryPoint)
	slang.releaseModule(module)

	slang.releaseSession(session)
	slang.releaseGlobalSession(globalSession)

	return shaderModule, .None
}

@(private = "file")
@(require_results)
createGraphicsPipelines :: proc(
	using graphicsData: ^GraphicsData,
	shadowShaderIndices, mainShaderIndices: [2]u32,
	pipelineCache: vk.PipelineCache = 0,
) -> PipelineError {
	PIPELINE_COUNT: u32 : 2
	pipelineInfos: [PIPELINE_COUNT]vk.GraphicsPipelineCreateInfo

	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[DescriptorSetIndex.BUFFERS].layout,
		descriptorSets[DescriptorSetIndex.TEXTURES].layout,
	}

	vertexBindingDescription := VERTEX_BINDING_DESCRIPTION

	// SHADOW PIPELINE
	shadowPushConstants: vk.PushConstantRange = {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = 3 * size_of(u32),
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
		&pipelines[PipelineIndex.LIGHT].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline layout! vkResult: %d", res)
		return .FailedToCreatePipelineLayout
	}

	shadowShaderStagesInfo: [2]vk.PipelineShaderStageCreateInfo
	for &info, index in shadowShaderStagesInfo {
		module, err := createShaderModules(
			graphicsData,
			shadowShaderIndices[index],
			index == 0 ? .VERTEX : .FRAGMENT,
		)
		if err != nil {
			logf(.Fatal, "Failed to create shader module! vkResult: %d", err)
			return err
		}
		info = {
			sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext               = nil,
			flags               = {},
			stage               = {index == 0 ? .VERTEX : .FRAGMENT},
			module              = module,
			pName               = "main",
			pSpecializationInfo = nil,
		}
	}
	defer {
		for info in shadowShaderStagesInfo {
			vk.DestroyShaderModule(device, info.module, nil)
		}
	}

	pipelineInfos[0] = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
		stageCount          = u32(len(shadowShaderStagesInfo)),
		pStages             = &shadowShaderStagesInfo[0],
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
		pRasterizationState = &{
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
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
		pMultisampleState   = &{
			sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			rasterizationSamples = {._1},
			sampleShadingEnable = false,
			minSampleShading = 0.0,
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
		layout              = pipelines[PipelineIndex.LIGHT].layout,
		renderPass          = pipelines[PipelineIndex.LIGHT].renderPass,
		subpass             = 0,
		basePipelineHandle  = {},
		basePipelineIndex   = 0,
	}

	// MAIN PIPELINE
	mainPushConstant: vk.PushConstantRange = {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = size_of(f32) + 3 * size_of(u32),
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
		&pipelines[PipelineIndex.MAIN].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create pipeline layout! vkResult: %d", res)
		return .FailedToCreatePipelineLayout
	}

	mainShaderStagesInfo: [2]vk.PipelineShaderStageCreateInfo
	for &info, index in mainShaderStagesInfo {
		module, err := createShaderModules(
			graphicsData,
			mainShaderIndices[index],
			index == 0 ? .VERTEX : .FRAGMENT,
		)
		if err != nil {
			logf(.Fatal, "Failed to create shader module! vkResult: %d", err)
			return err
		}
		info = {
			sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext               = nil,
			flags               = {},
			stage               = {index == 0 ? .VERTEX : .FRAGMENT},
			module              = module,
			pName               = "main",
			pSpecializationInfo = nil,
		}
	}
	defer {
		for &info in mainShaderStagesInfo {
			vk.DestroyShaderModule(device, info.module, nil)
		}
	}

	pipelineInfos[1] = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
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
			pScissors = &vk.Rect2D {
				offset = {0, 0},
				extent = {RENDER_SIZE.x, RENDER_SIZE.y},
			},
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
		layout              = pipelines[PipelineIndex.MAIN].layout,
		renderPass          = pipelines[PipelineIndex.MAIN].renderPass,
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

	pipelines[PipelineIndex.LIGHT].pipeline = vkPipelines[0]
	pipelines[PipelineIndex.LIGHT].shaderIdxs = shadowShaderIndices

	pipelines[PipelineIndex.MAIN].pipeline = vkPipelines[1]
	pipelines[PipelineIndex.MAIN].shaderIdxs = mainShaderIndices

	return .None
}

@(private = "file")
@(require_results)
createComputePipelines :: proc(
	using graphicsData: ^GraphicsData,
	preShaderIndices, postShaderIndices: u32,
	pipelineCache: vk.PipelineCache = 0,
) -> PipelineError {
	PIPELINE_COUNT: u32 : 2
	pipelineInfos: [PIPELINE_COUNT]vk.ComputePipelineCreateInfo

	layouts: [len(DescriptorSetIndex)]vk.DescriptorSetLayout = {
		descriptorSets[DescriptorSetIndex.BUFFERS].layout,
		descriptorSets[DescriptorSetIndex.TEXTURES].layout,
	}

	// PRE COMPUTE
	preComputePushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = 5 * size_of(u32),
	}

	preComputePipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = len(layouts),
		pSetLayouts            = &layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &preComputePushConstants,
	}

	if res := vk.CreatePipelineLayout(
		device,
		&preComputePipelineLayoutInfo,
		nil,
		&pipelines[PipelineIndex.PRECOMPUTE].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create precompute pipeline layout! vkResult: %d", res)
		return .FailedToCreatePipelineLayout
	}

	shaderModule, err := createShaderModules(graphicsData, preShaderIndices, .COMPUTE)
	if err != nil {
		logf(.Fatal, "Failed to create precompute shader module! Error: %d", err)
		return err
	}
	preComputeShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
		stage               = {.COMPUTE},
		module              = shaderModule,
		pName               = "main",
		pSpecializationInfo = nil,
	}
	defer vk.DestroyShaderModule(device, preComputeShaderStageInfo.module, nil)

	pipelineInfos[0] = {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = nil,
		flags              = {},
		stage              = preComputeShaderStageInfo,
		layout             = pipelines[PipelineIndex.PRECOMPUTE].layout,
		basePipelineHandle = {},
		basePipelineIndex  = 0,
	}

	// POSTPROCESS PROCESSING
	postPushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = 7 * size_of(f32),
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
		&pipelines[PipelineIndex.POSTPROCESS].layout,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create postprocess pipeline layout! vkResult: %v", res)
		return .FailedToCreatePipelineLayout
	}

	shaderModule, err = createShaderModules(graphicsData, postShaderIndices, .COMPUTE)
	if err != nil {
		logf(.Fatal, "Failed to create precompute shader module! Error: %d", err)
		return err
	}

	postShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
		stage               = {.COMPUTE},
		module              = shaderModule,
		pName               = "main",
		pSpecializationInfo = nil,
	}
	defer vk.DestroyShaderModule(device, postShaderStageInfo.module, nil)

	pipelineInfos[1] = {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = nil,
		flags              = {},
		stage              = postShaderStageInfo,
		layout             = pipelines[PipelineIndex.POSTPROCESS].layout,
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

	pipelines[PipelineIndex.PRECOMPUTE].pipeline = vkPipelines[0]
	pipelines[PipelineIndex.PRECOMPUTE].shaderIdxs[0] = preShaderIndices

	pipelines[PipelineIndex.POSTPROCESS].pipeline = vkPipelines[1]
	pipelines[PipelineIndex.POSTPROCESS].shaderIdxs[0] = postShaderIndices

	return .None
}

@(private = "file")
cleanupPipelines :: proc(using graphicsData: ^GraphicsData) {
	vk.DestroyPipeline(device, pipelines[PipelineIndex.PRECOMPUTE].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.PRECOMPUTE].layout, nil)

	vk.DestroyPipeline(device, pipelines[PipelineIndex.LIGHT].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.LIGHT].layout, nil)

	vk.DestroyPipeline(device, pipelines[PipelineIndex.MAIN].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.MAIN].layout, nil)

	vk.DestroyPipeline(device, pipelines[PipelineIndex.POSTPROCESS].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.POSTPROCESS].layout, nil)
}

@(require_results)
reloadShaders :: proc(using graphicsData: ^GraphicsData, scene: ^Scene) -> (err: Error) {
	cleanupPipelines(graphicsData)
	createGraphicsPipelines(
		graphicsData,
		pipelines[PipelineIndex.LIGHT].shaderIdxs,
		pipelines[PipelineIndex.MAIN].shaderIdxs,
	) or_return

	createComputePipelines(
		graphicsData,
		pipelines[PipelineIndex.PRECOMPUTE].shaderIdxs[0],
		pipelines[PipelineIndex.POSTPROCESS].shaderIdxs[0],
	) or_return

	updateDescriptorSets(graphicsData, scene) or_return
	return nil
}

changePipelineShader :: proc(
	using graphicsData: ^GraphicsData,
	pipeline: PipelineIndex,
	indices: u32,
) {
	// TODO: Implement shader reloading for individual pipelines
	// pipelines[pipeline].indices = indices
}

@(private = "file")
@(require_results)
initImgui :: proc(using graphicsData: ^GraphicsData) -> DescriptorSetError {
	imgui.CHECKVERSION()

	poolSizes: []vk.DescriptorPoolSize = {
		{.SAMPLER, 1000},
		{.COMBINED_IMAGE_SAMPLER, 1000},
		{.SAMPLED_IMAGE, 1000},
		{.STORAGE_IMAGE, 1000},
		{.UNIFORM_TEXEL_BUFFER, 1000},
		{.STORAGE_TEXEL_BUFFER, 1000},
		{.UNIFORM_BUFFER, 1000},
		{.STORAGE_BUFFER, 1000},
		{.UNIFORM_BUFFER_DYNAMIC, 1000},
		{.STORAGE_BUFFER_DYNAMIC, 1000},
		{.INPUT_ATTACHMENT, 1000},
	}

	descriptorPoolCreateInfo: vk.DescriptorPoolCreateInfo = {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		pNext         = nil,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 1000,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = raw_data(poolSizes),
	}

	if res := vk.CreateDescriptorPool(
		device,
		&descriptorPoolCreateInfo,
		nil,
		&imguiData.descriptorPool,
	); res != .SUCCESS {
		logf(.Fatal, "Failed to create imgui descriptor pool! vkResult: %v", res)
		return .FailedToCreateDescriptorPool
	}

	return .None
}

ImguiError :: enum {
	None = 0,
	FailedToInitializeImgui,
}

@(private = "file")
@(require_results)
updateImgui :: proc(using graphicsData: ^GraphicsData) -> Error {
	imguiData.imguiContext = imgui.CreateContext()
	io := imgui.GetIO()
	imgui.StyleColorsClassic()

	imguiVulkan.LoadFunctions(
		proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr((vk.Instance)(user_data), function_name)
		},
		instance,
	)

	if !imguiGLFW.InitForVulkan(window, true) {
		log(.Fatal, "Failed to initialize imgui for vulkan.")
		return .FailedToInitializeImgui
	}

	// RenderPass
	{
		imguiData.colour.format = .R16G16B16A16_SFLOAT

		err := createImage(
			graphicsData,
			&imguiData.colour,
			{},
			.D2,
			u32(swapchainExtent.width),
			u32(swapchainExtent.height),
			1,
			{._1},
			.OPTIMAL,
			{.COLOR_ATTACHMENT, .TRANSFER_SRC, .TRANSFER_DST},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		)
		if err != .None {
			return err
		}

		imguiData.colour.view, err = createImageView(
			graphicsData,
			imguiData.colour.vkImage,
			.D2,
			imguiData.colour.format,
			{.COLOR},
			1,
		)
		if err != .None {
			log(.Fatal, "Failed to create imgui colour image view!")
			return err
		}

		attachment: vk.AttachmentDescription = {
			flags          = {},
			format         = imguiData.colour.format,
			samples        = {._1},
			loadOp         = .LOAD,
			storeOp        = .STORE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .TRANSFER_DST_OPTIMAL,
			finalLayout    = .TRANSFER_SRC_OPTIMAL,
		}

		colourAttachmentRef: vk.AttachmentReference = {
			attachment = 0,
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}

		subpass: vk.SubpassDescription = {
			flags                   = {},
			pipelineBindPoint       = .GRAPHICS,
			inputAttachmentCount    = 0,
			pInputAttachments       = nil,
			colorAttachmentCount    = 1,
			pColorAttachments       = &colourAttachmentRef,
			pResolveAttachments     = nil,
			pDepthStencilAttachment = nil,
			preserveAttachmentCount = 0,
			pPreserveAttachments    = nil,
		}

		renderPassInfo: vk.RenderPassCreateInfo = {
			sType           = .RENDER_PASS_CREATE_INFO,
			pNext           = nil,
			flags           = {},
			attachmentCount = 1,
			pAttachments    = &attachment,
			subpassCount    = 1,
			pSubpasses      = &subpass,
			dependencyCount = 0,
			pDependencies   = nil,
		}

		if res := vk.CreateRenderPass(device, &renderPassInfo, nil, &imguiData.renderPass);
		   res != .SUCCESS {
			logf(.Fatal, "Unable to create Imgui render pass! vkResult: %v", res)
			return RenderPassError.FailedToCreateRenderPass
		}
	}

	// FrameBuffer
	{
		frameBufferInfo: vk.FramebufferCreateInfo = {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			pNext           = nil,
			flags           = {},
			renderPass      = imguiData.renderPass,
			attachmentCount = 1,
			pAttachments    = &imguiData.colour.view,
			width           = u32(swapchainExtent.width),
			height          = u32(swapchainExtent.height),
			layers          = 1,
		}

		imguiData.frameBuffers = make([]vk.Framebuffer, len(swapchainImages))
		for index in 0 ..< len(swapchainImages) {
			if res := vk.CreateFramebuffer(
				device,
				&frameBufferInfo,
				nil,
				&imguiData.frameBuffers[index],
			); res != .SUCCESS {
				logf(.Fatal, "Failed to create Imgui frame buffer! vkResult: %v", res)
				return FrameBufferError.FailedToCreateFrameBuffer
			}
		}
	}

	implInitInfo: imguiVulkan.InitInfo = {
		Instance                    = instance,
		PhysicalDevice              = physicalDevice,
		Device                      = device,
		QueueFamily                 = queueFamilies.graphicsFamily,
		Queue                       = graphicsQueue,
		DescriptorPool              = imguiData.descriptorPool,
		RenderPass                  = imguiData.renderPass,
		MinImageCount               = 2,
		ImageCount                  = 2,
		MSAASamples                 = ._1,

		// (Optional)
		PipelineCache               = {},
		Subpass                     = 0,
		DescriptorPoolSize          = 0,

		// (Optional) Dynamic Rendering
		// Need to explicitly enable VK_KHR_dynamic_rendering extension to use this, even for Vulkan 1.3.
		UseDynamicRendering         = false,
		// NOTE: Odin-imgui: this field if #ifdef'd out in the Dear ImGui side if the struct is not defined.
		// Keeping the field is a pretty safe bet, but make sure to check this if you have issues!
		PipelineRenderingCreateInfo = {},

		// (Optional) Allocation, Debugging
		Allocator                   = nil,
		CheckVkResultFn             = imguiCheckVkResult,
		// Minimum allocation size. Set to 1024*1024 to satisfy zealous best practices validation layer and waste a little memory.
		MinAllocationSize           = 1024 * 1024,
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
	imgui.DestroyContext(imguiData.imguiContext)

	for &frameBuffer in imguiData.frameBuffers {
		vk.DestroyFramebuffer(device, frameBuffer, nil)
	}
	delete(imguiData.frameBuffers)

	deleteImage(graphicsData, &imguiData.colour)

	vk.DestroyRenderPass(device, imguiData.renderPass, nil)
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
	viewProjection: Mat4,
) {
	viewProjection: UniformBuffer = {
		viewProjection = viewProjection,
		lightCount     = u32(len(scene.lights)),
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
		vk.ResetCommandBuffer(preComputeCommandBuffers[bufferIndex], {})
		vk.ResetCommandBuffer(shadowMapCommandBuffers[bufferIndex], {})
		vk.ResetCommandBuffer(sceneCommandBuffers[bufferIndex], {})
		vk.ResetCommandBuffer(mainCommandBuffers[bufferIndex], {})

		recordPreComputeBuffer(graphicsData, bufferIndex, scene) or_return
		recordShadowMapBuffer(graphicsData, bufferIndex, scene) or_return
		recordSceneBuffers(graphicsData, bufferIndex, scene) or_return
		recordMainGraphicsBuffer(graphicsData, bufferIndex, scene) or_return

		when IMGUI_ENABLED {
			vk.ResetCommandBuffer(postComputeCommandBuffers[bufferIndex], {})
			recordPostComputeBuffer(graphicsData, bufferIndex) or_return
		}
	}

	when !IMGUI_ENABLED {
		for bufferIndex in 0 ..< u32(len(swapchainImages)) {
			vk.ResetCommandBuffer(postComputeCommandBuffers[bufferIndex], {})
			recordPostComputeBuffer(graphicsData, bufferIndex) or_return
		}
	}

	return nil
}

RecordCommandBufferError :: enum {
	None = 0,
	FailedToRecordCommandBuffer,
}

@(private = "file")
@(require_results)
recordPreComputeBuffer :: proc(
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

	if res := vk.BeginCommandBuffer(preComputeCommandBuffers[index], &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[DescriptorSetIndex.BUFFERS].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.TEXTURES].sets[currentFrame],
	}
	vk.CmdBindDescriptorSets(
		preComputeCommandBuffers[index],
		.COMPUTE,
		pipelines[PipelineIndex.PRECOMPUTE].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)
	vk.CmdBindPipeline(
		preComputeCommandBuffers[index],
		.COMPUTE,
		pipelines[PipelineIndex.PRECOMPUTE].pipeline,
	)

	offset: u32 = 0
	instanceIdx := 0
	for &model in scene.models {
		vk.CmdPushConstants(
			preComputeCommandBuffers[index],
			pipelines[PipelineIndex.PRECOMPUTE].layout,
			{.COMPUTE},
			0,
			1 * size_of(u32),
			&instanceIdx,
		)
		for &mesh in model.meshes {
			vk.CmdPushConstants(
				preComputeCommandBuffers[index],
				pipelines[PipelineIndex.PRECOMPUTE].layout,
				{.COMPUTE},
				1 * size_of(u32),
				4 * size_of(u32),
				raw_data(
					[]u32{u32(len(model.instances)), mesh.vertexCount, mesh.vertexOffset, offset},
				),
			)
			vk.CmdDispatch(
				preComputeCommandBuffers[index],
				u32(ceil(f32(mesh.vertexCount) / 64.0)),
				1,
				1,
			)
			offset += mesh.vertexCount * u32(len(model.instances))
		}
		instanceIdx += len(model.instances)
	}

	if res := vk.EndCommandBuffer(preComputeCommandBuffers[index]); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	return .None
}

@(private = "file")
@(require_results)
recordMainGraphicsBuffer :: proc(
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
	if res := vk.BeginCommandBuffer(mainCommandBuffers[index], &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	renderPassInfo: vk.RenderPassBeginInfo = {
		sType = .RENDER_PASS_BEGIN_INFO,
		pNext = nil,
		renderPass = pipelines[PipelineIndex.LIGHT].renderPass,
		framebuffer = pipelines[PipelineIndex.LIGHT].frameBuffers[index],
		renderArea = vk.Rect2D {
			offset = {0, 0},
			extent = {SHADOW_RESOLUTION.x, SHADOW_RESOLUTION.y},
		},
		clearValueCount = 2,
		pClearValues = raw_data(
			[]vk.ClearValue {
				{color = vk.ClearColorValue{float32 = {0, 0, 0, 0}}},
				{depthStencil = vk.ClearDepthStencilValue{depth = 1, stencil = 0}},
			},
		),
	}

	vk.CmdBeginRenderPass(mainCommandBuffers[index], &renderPassInfo, .SECONDARY_COMMAND_BUFFERS)
	vk.CmdExecuteCommands(mainCommandBuffers[index], 1, &shadowMapCommandBuffers[index])
	vk.CmdEndRenderPass(mainCommandBuffers[index])

	vk.CmdPipelineBarrier2(
		mainCommandBuffers[index],
		&vk.DependencyInfo {
			sType = .DEPENDENCY_INFO,
			pNext = nil,
			dependencyFlags = {},
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
				dstAccessMask = {.SHADER_READ},
				oldLayout = .SHADER_READ_ONLY_OPTIMAL,
				newLayout = .SHADER_READ_ONLY_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = pipelines[PipelineIndex.LIGHT].colour.vkImage,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = u32(len(scene.lights)) * 6,
				},
			},
		},
	)

	renderPassInfo = {
		sType = .RENDER_PASS_BEGIN_INFO,
		pNext = nil,
		renderPass = pipelines[PipelineIndex.MAIN].renderPass,
		framebuffer = pipelines[PipelineIndex.MAIN].frameBuffers[index],
		renderArea = vk.Rect2D{offset = {0, 0}, extent = {RENDER_SIZE.x, RENDER_SIZE.y}},
		clearValueCount = 2,
		pClearValues = raw_data(
			[]vk.ClearValue {
				{color = vk.ClearColorValue{float32 = scene.clearColour}},
				{depthStencil = vk.ClearDepthStencilValue{depth = 1, stencil = 0}},
			},
		),
	}
	vk.CmdBeginRenderPass(mainCommandBuffers[index], &renderPassInfo, .SECONDARY_COMMAND_BUFFERS)
	vk.CmdExecuteCommands(mainCommandBuffers[index], 1, &sceneCommandBuffers[index])
	vk.CmdEndRenderPass(mainCommandBuffers[index])

	if res := vk.EndCommandBuffer(mainCommandBuffers[index]); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordShadowMapBuffer :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
	scene: ^Scene,
) -> RecordCommandBufferError {
	lightCount := u32(len(scene.lights))
	shadowImageCount := lightCount * 6

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.RENDER_PASS_CONTINUE},
		pInheritanceInfo = &vk.CommandBufferInheritanceInfo {
			sType = .COMMAND_BUFFER_INHERITANCE_INFO,
			pNext = nil,
			renderPass = pipelines[PipelineIndex.LIGHT].renderPass,
			subpass = 0,
			framebuffer = pipelines[PipelineIndex.LIGHT].frameBuffers[index],
			occlusionQueryEnable = false,
			queryFlags = {},
			pipelineStatistics = {},
		},
	}
	if res := vk.BeginCommandBuffer(shadowMapCommandBuffers[index], &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	vk.CmdBindPipeline(
		shadowMapCommandBuffers[index],
		.GRAPHICS,
		pipelines[PipelineIndex.LIGHT].pipeline,
	)

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[DescriptorSetIndex.BUFFERS].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.TEXTURES].sets[currentFrame],
	}

	vk.CmdBindDescriptorSets(
		shadowMapCommandBuffers[index],
		.GRAPHICS,
		pipelines[PipelineIndex.LIGHT].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)

	vk.CmdBindVertexBuffers(
		shadowMapCommandBuffers[index],
		0,
		1,
		&scene.buffers.vertexBuffer.buffer,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer(
		shadowMapCommandBuffers[index],
		scene.buffers.indexBuffer.buffer,
		0,
		.UINT32,
	)

	for layerIndex: u32 = 0; layerIndex < shadowImageCount; layerIndex += 1 {
		vk.CmdPushConstants(
			shadowMapCommandBuffers[index],
			pipelines[PipelineIndex.LIGHT].layout,
			{.VERTEX},
			0,
			size_of(u32),
			&layerIndex,
		)

		offset: u32 = 0
		for &model in scene.models {
			for &mesh in model.meshes {
				vk.CmdPushConstants(
					shadowMapCommandBuffers[index],
					pipelines[PipelineIndex.LIGHT].layout,
					{.VERTEX},
					size_of(u32),
					2 * size_of(u32),
					raw_data([]u32{offset, mesh.vertexCount}),
				)

				vk.CmdDrawIndexed(
					shadowMapCommandBuffers[index],
					mesh.indexCount,
					u32(len(model.instances)),
					mesh.indexOffset,
					i32(mesh.vertexOffset),
					0,
				)
				offset += mesh.vertexCount * u32(len(model.instances))
			}
		}
	}

	if res := vk.EndCommandBuffer(shadowMapCommandBuffers[index]); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordSceneBuffers :: proc(
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
			pNext = nil,
			renderPass = pipelines[PipelineIndex.MAIN].renderPass,
			subpass = 0,
			framebuffer = pipelines[PipelineIndex.MAIN].frameBuffers[index],
			occlusionQueryEnable = false,
			queryFlags = {},
			pipelineStatistics = {},
		},
	}
	if res := vk.BeginCommandBuffer(sceneCommandBuffers[index], &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[DescriptorSetIndex.BUFFERS].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.TEXTURES].sets[currentFrame],
	}

	vk.CmdBindDescriptorSets(
		sceneCommandBuffers[index],
		.GRAPHICS,
		pipelines[PipelineIndex.MAIN].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)
	vk.CmdBindPipeline(
		sceneCommandBuffers[index],
		.GRAPHICS,
		pipelines[PipelineIndex.MAIN].pipeline,
	)

	vk.CmdPushConstants(
		sceneCommandBuffers[index],
		pipelines[PipelineIndex.MAIN].layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(f32),
		&scene.ambientLight,
	)

	vk.CmdBindVertexBuffers(
		sceneCommandBuffers[index],
		0,
		1,
		&scene.buffers.vertexBuffer.buffer,
		raw_data([]vk.DeviceSize{0}),
	)
	vk.CmdBindIndexBuffer(sceneCommandBuffers[index], scene.buffers.indexBuffer.buffer, 0, .UINT32)

	vertexOffset: u32 = 0
	instanceOffset: u32 = 0
	for &model in scene.models {
		for &mesh in model.meshes {
			vk.CmdPushConstants(
				sceneCommandBuffers[index],
				pipelines[PipelineIndex.MAIN].layout,
				{.VERTEX, .FRAGMENT},
				size_of(f32),
				3 * size_of(u32),
				raw_data([]u32{vertexOffset, mesh.vertexCount, instanceOffset}),
			)

			vk.CmdDrawIndexed(
				sceneCommandBuffers[index],
				mesh.indexCount,
				u32(len(model.instances)),
				mesh.indexOffset,
				i32(mesh.vertexOffset),
				0,
			)
			vertexOffset += mesh.vertexCount * u32(len(model.instances))
			instanceOffset += u32(len(model.instances))
		}
	}

	if res := vk.EndCommandBuffer(sceneCommandBuffers[index]); res != .SUCCESS {
		logf(.Error, "Failed to record command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordPostComputeBuffer :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
) -> RecordCommandBufferError {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}

	if res := vk.BeginCommandBuffer(postComputeCommandBuffers[index], &beginInfo);
	   res != .SUCCESS {
		logf(.Error, "Failed to start recording compute commands! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	transitionImageLayout(
		graphicsData,
		postComputeCommandBuffers[index],
		renderedImage.vkImage,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		1,
	)

	upscaleImage(
		postComputeCommandBuffers[index],
		pipelines[PipelineIndex.MAIN].colour.vkImage,
		renderedImage.vkImage,
		{RENDER_SIZE.x, RENDER_SIZE.y},
		{swapchainExtent.width, swapchainExtent.height},
		0,
		0,
	)

	transitionImageLayout(
		graphicsData,
		postComputeCommandBuffers[index],
		renderedImage.vkImage,
		.TRANSFER_DST_OPTIMAL,
		.GENERAL,
		{.COLOR},
		1,
	)

	transitionImageLayout(
		graphicsData,
		postComputeCommandBuffers[index],
		processedImage.vkImage,
		.UNDEFINED,
		.GENERAL,
		{.COLOR},
		1,
	)

	sets: [len(DescriptorSetIndex)]vk.DescriptorSet = {
		descriptorSets[DescriptorSetIndex.BUFFERS].sets[currentFrame],
		descriptorSets[DescriptorSetIndex.TEXTURES].sets[currentFrame],
	}
	vk.CmdBindDescriptorSets(
		postComputeCommandBuffers[index],
		.COMPUTE,
		pipelines[PipelineIndex.POSTPROCESS].layout,
		0,
		len(sets),
		&sets[0],
		0,
		nil,
	)

	vk.CmdPushConstants2(
		postComputeCommandBuffers[index],
		&vk.PushConstantsInfo {
			sType = .PUSH_CONSTANTS_INFO,
			pNext = nil,
			layout = pipelines[PipelineIndex.POSTPROCESS].layout,
			stageFlags = {.COMPUTE},
			offset = 0,
			size = 6 * size_of(f32),
			pValues = raw_data(
				[]f32 {
					contrast,
					brightness,
					saturation,
					pow(f32(2.0), exposure),
					transmute(f32)tonemapper,
					gamma,
				},
			),
		},
	)

	boolean := b32(drawLights)
	vk.CmdPushConstants2(
		postComputeCommandBuffers[index],
		&vk.PushConstantsInfo {
			sType = .PUSH_CONSTANTS_INFO,
			pNext = nil,
			layout = pipelines[PipelineIndex.POSTPROCESS].layout,
			stageFlags = {.COMPUTE},
			offset = 6 * size_of(f32),
			size = size_of(b32),
			pValues = &boolean,
		},
	)

	vk.CmdBindPipeline(
		postComputeCommandBuffers[index],
		.COMPUTE,
		pipelines[PipelineIndex.POSTPROCESS].pipeline,
	)

	vk.CmdDispatch(
		postComputeCommandBuffers[index],
		swapchainExtent.width / 32 + 1,
		swapchainExtent.height / 32 + 1,
		1,
	)

	transitionImageLayout(
		graphicsData,
		postComputeCommandBuffers[index],
		processedImage.vkImage,
		.UNDEFINED,
		.TRANSFER_SRC_OPTIMAL,
		{.COLOR},
		1,
	)

	when IMGUI_ENABLED {
		transitionImageLayout(
			graphicsData,
			postComputeCommandBuffers[index],
			imguiData.colour.vkImage,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		copyImage(
			postComputeCommandBuffers[index],
			vk.Extent3D{swapchainExtent.width, swapchainExtent.height, 1},
			processedImage.vkImage,
			imguiData.colour.vkImage,
			.TRANSFER_SRC_OPTIMAL,
			.TRANSFER_DST_OPTIMAL,
		)
	} else {
		transitionImageLayout(
			graphicsData,
			postComputeCommandBuffers[index],
			swapchainImages[index],
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		vk.CmdBlitImage(
			postComputeCommandBuffers[index],
			processedImage.vkImage,
			.TRANSFER_SRC_OPTIMAL,
			swapchainImages[index],
			.TRANSFER_DST_OPTIMAL,
			1,
			&vk.ImageBlit {
				srcSubresource = {
					aspectMask = {.COLOR},
					mipLevel = 0,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				srcOffsets = {
					{x = 0, y = 0, z = 0},
					{x = i32(swapchainExtent.width), y = i32(swapchainExtent.height), z = 1},
				},
				dstSubresource = {
					aspectMask = {.COLOR},
					mipLevel = 0,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				dstOffsets = {
					{x = 0, y = 0, z = 0},
					{x = i32(swapchainExtent.width), y = i32(swapchainExtent.height), z = 1},
				},
			},
			.NEAREST,
		)

		transitionImageLayout(
			graphicsData,
			postComputeCommandBuffers[index],
			swapchainImages[index],
			.TRANSFER_DST_OPTIMAL,
			.PRESENT_SRC_KHR,
			{.COLOR},
			1,
		)
	}

	if res := vk.EndCommandBuffer(postComputeCommandBuffers[index]); res != .SUCCESS {
		logf(.Error, "Failed to record compute command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}
	return .None
}

@(private = "file")
@(require_results)
recordImguiBuffer :: proc(
	using graphicsData: ^GraphicsData,
	index: u32,
) -> RecordCommandBufferError {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}
	if res := vk.BeginCommandBuffer(imguiCommandBuffers[index], &beginInfo); res != .SUCCESS {
		logf(.Error, "Failed to being recording command buffer! vkResult: %v", res)
		return .FailedToRecordCommandBuffer
	}

	renderPassInfo: vk.RenderPassBeginInfo = {
		sType = .RENDER_PASS_BEGIN_INFO,
		pNext = nil,
		renderPass = imguiData.renderPass,
		framebuffer = imguiData.frameBuffers[index],
		renderArea = vk.Rect2D{offset = {0, 0}, extent = swapchainExtent},
		clearValueCount = 0,
		pClearValues = nil,
	}
	vk.CmdBeginRenderPass(imguiCommandBuffers[index], &renderPassInfo, .INLINE)

	imgui.Render()
	imguiVulkan.RenderDrawData(imgui.GetDrawData(), imguiCommandBuffers[index])
	vk.CmdEndRenderPass(imguiCommandBuffers[index])

	transitionImageLayout(
		graphicsData,
		imguiCommandBuffers[index],
		swapchainImages[index],
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		1,
	)

	vk.CmdBlitImage(
		imguiCommandBuffers[index],
		imguiData.colour.vkImage,
		.TRANSFER_SRC_OPTIMAL,
		swapchainImages[index],
		.TRANSFER_DST_OPTIMAL,
		1,
		&vk.ImageBlit {
			srcSubresource = {
				aspectMask = {.COLOR},
				mipLevel = 0,
				baseArrayLayer = 0,
				layerCount = 1,
			},
			srcOffsets = {
				{x = 0, y = 0, z = 0},
				{x = i32(swapchainExtent.width), y = i32(swapchainExtent.height), z = 1},
			},
			dstSubresource = {
				aspectMask = {.COLOR},
				mipLevel = 0,
				baseArrayLayer = 0,
				layerCount = 1,
			},
			dstOffsets = {
				{x = 0, y = 0, z = 0},
				{x = i32(swapchainExtent.width), y = i32(swapchainExtent.height), z = 1},
			},
		},
		.NEAREST,
	)

	transitionImageLayout(
		graphicsData,
		imguiCommandBuffers[index],
		swapchainImages[index],
		.TRANSFER_DST_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR},
		1,
	)

	if res := vk.EndCommandBuffer(imguiCommandBuffers[index]); res != .SUCCESS {
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

updateSceneData :: proc(graphicsData: ^GraphicsData, scene: ^Scene, vp: Mat4, delta: f32) {
	updateUniformBuffer(graphicsData, scene, vp)
	updateLightBuffer(graphicsData, scene, delta)
	updateInstanceBuffer(graphicsData, scene, delta)

	if graphicsData.reloadBuffers {
		if err := updateSceneBuffers(graphicsData, scene); err != nil {
			logf(.Error, "Failed to update scene buffers: %v", err)
			panic("Failed to update scene buffers")
		}
		graphicsData.reloadBuffers = false
	}

	if graphicsData.rerecordCommands {
		if err := updateCommandBuffers(graphicsData, scene); err != nil {
			logf(.Error, "Failed to update command buffers: %v", err)
			panic("Failed to update command buffers")
		}
		graphicsData.rerecordCommands = false
	}
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
		swapchain,
		max(u64),
		imagesAvailable[currentFrame],
		{},
		&imageIndex,
	); res == .ERROR_OUT_OF_DATE_KHR {
		if err = recreateSwapchain(graphicsData); err != nil {
			return err
		}
		return DrawError.UpdateCommandBuffers
	} else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
		logf(.Error, "Failed to aquire swapchain image! vkResult: %v", res)
		return DrawError.FailedToAcquireSwapchainImage
	}
	vk.ResetFences(device, 1, &inFlightFrames[currentFrame])

	when IMGUI_ENABLED {
		imguiVulkan.NewFrame()
		imguiGLFW.NewFrame()
		imgui.NewFrame()

		drawImgui(graphicsData)

		imgui.EndFrame()

		vk.ResetCommandBuffer(imguiCommandBuffers[imageIndex], {})
		if err := recordImguiBuffer(graphicsData, imageIndex); err != nil {
			logf(.Error, "Failed to record ui command buffer! Error: %v", err)
			return err
		}
	}

	submitInfo := vk.SubmitInfo2 {
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
					commandBuffer = preComputeCommandBuffers[currentFrame],
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
					semaphore = preComputeFinished[currentFrame],
					value = 0,
					stageMask = {.COMPUTE_SHADER},
					deviceIndex = 0,
				},
			},
		),
	}

	if res := vk.QueueSubmit2(computeQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Error, "Failed to submit pre command buffer! vkResult: %v", res)
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
					semaphore = preComputeFinished[currentFrame],
					value = 1,
					stageMask = {.ALL_GRAPHICS},
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
					commandBuffer = mainCommandBuffers[currentFrame],
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
					semaphore = rendersFinished[currentFrame],
					value = 0,
					stageMask = {.ALL_GRAPHICS},
					deviceIndex = 0,
				},
			},
		),
	}

	if res := vk.QueueSubmit2(graphicsQueue, 1, &submitInfo, 0); res != .SUCCESS {
		logf(.Error, "Failed to submit main command buffer! vkResult: %v", res)
		return .FailedToSubmitMainCommandBuffer
	}

	submitInfo = {
		sType                    = .SUBMIT_INFO_2,
		pNext                    = nil,
		flags                    = {},
		commandBufferInfoCount   = 1,
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = computeFinished[currentFrame],
					value = 0,
					stageMask = {.COMPUTE_SHADER},
					deviceIndex = 0,
				},
			},
		),
	}

	fence: vk.Fence
	when IMGUI_ENABLED {
		submitInfo.pCommandBufferInfos = raw_data(
			[]vk.CommandBufferSubmitInfo {
				{
					sType = .COMMAND_BUFFER_SUBMIT_INFO,
					pNext = nil,
					commandBuffer = postComputeCommandBuffers[currentFrame],
					deviceMask = 0,
				},
			},
		)
		submitInfo.waitSemaphoreInfoCount = 1
		submitInfo.pWaitSemaphoreInfos = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = rendersFinished[currentFrame],
					value = 1,
					stageMask = {.COMPUTE_SHADER},
					deviceIndex = 0,
				},
			},
		)
	} else {
		submitInfo.pCommandBufferInfos = raw_data(
			[]vk.CommandBufferSubmitInfo {
				{
					sType = .COMMAND_BUFFER_SUBMIT_INFO,
					pNext = nil,
					commandBuffer = postComputeCommandBuffers[imageIndex],
					deviceMask = 0,
				},
			},
		)
		submitInfo.waitSemaphoreInfoCount = 2
		submitInfo.pWaitSemaphoreInfos = raw_data(
			[]vk.SemaphoreSubmitInfo {
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = rendersFinished[currentFrame],
					value = 1,
					stageMask = {.COMPUTE_SHADER},
					deviceIndex = 0,
				},
				{
					sType = .SEMAPHORE_SUBMIT_INFO,
					pNext = nil,
					semaphore = imagesAvailable[currentFrame],
					value = 1,
					stageMask = {.BOTTOM_OF_PIPE},
					deviceIndex = 0,
				},
			},
		)
		fence = inFlightFrames[currentFrame]
	}

	if res := vk.QueueSubmit2(computeQueue, 1, &submitInfo, fence); res != .SUCCESS {
		logf(.Error, "Failed to submit post command buffer! vkResult: %v", res)
		return DrawError.FailedToSubmitPostCommandBuffer
	}

	when IMGUI_ENABLED {
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
						semaphore = computeFinished[currentFrame],
						value = 1,
						stageMask = {.TOP_OF_PIPE},
						deviceIndex = 0,
					},
					{
						sType = .SEMAPHORE_SUBMIT_INFO,
						pNext = nil,
						semaphore = imagesAvailable[currentFrame],
						value = 1,
						stageMask = {.BOTTOM_OF_PIPE},
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
						commandBuffer = imguiCommandBuffers[imageIndex],
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
						semaphore = imguiFinished[currentFrame],
						value = 0,
						stageMask = {.ALL_GRAPHICS},
						deviceIndex = 0,
					},
				},
			),
		}

		if res := vk.QueueSubmit2(graphicsQueue, 1, &submitInfo, inFlightFrames[currentFrame]);
		   res != .SUCCESS {
			logf(.Error, "Failed to submit ui command buffer! vkResult: %v", res)
			return .FailedToSubmitUICommandBuffer
		}
	}

	presentInfo: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		pNext              = nil,
		waitSemaphoreCount = 1,
		swapchainCount     = 1,
		pSwapchains        = &swapchain,
		pImageIndices      = &imageIndex,
		pResults           = nil,
	}

	when IMGUI_ENABLED {
		presentInfo.pWaitSemaphores = &imguiFinished[currentFrame]
	} else {
		presentInfo.pWaitSemaphores = &computeFinished[currentFrame]
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

