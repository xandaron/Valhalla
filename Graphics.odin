package Valhalla

import ImFD "ImFileDialog"
import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "imgui"
import implGLFW "imgui/imgui_impl_glfw"
import implVulkan "imgui/imgui_impl_vulkan"
import "ufbx"
import "vendor:glfw"
import img "vendor:stb/image"
import vk "vendor:vulkan"


// ###################################################################
// #                          Constants                              #
// ###################################################################


@(private = "file")
UI_ENABLED: bool : true

@(private = "file")
HDR_ENABLED: bool : true

@(private = "file")
requestedLayers: []cstring : {"VK_LAYER_KHRONOS_validation"}

@(private = "file")
deviceExtensions: []cstring : {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME,
	vk.EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME,
	vk.KHR_MULTIVIEW_EXTENSION_NAME,
}

@(private = "file")
instanceExtensions: []cstring : {
	vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
	vk.EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME,
	vk.KHR_SYNCHRONIZATION_2_EXTENSION_NAME,
}

@(private = "file")
vertexBindingDescription: vk.VertexInputBindingDescription : {
	binding = 0,
	stride = size_of(Vertex),
	inputRate = .VERTEX,
}

@(private = "file")
vertexInputAttributeDescriptions: []vk.VertexInputAttributeDescription : {
	{
		location = 0,
		binding = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, position)),
	},
	{
		location = 1,
		binding = 0,
		format = .R32G32_SFLOAT,
		offset = u32(offset_of(Vertex, texCoord)),
	},
	{
		location = 2,
		binding = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, normal)),
	},
	{
		location = 3,
		binding = 0,
		format = .R32G32B32A32_UINT,
		offset = u32(offset_of(Vertex, bones)),
	},
	{
		location = 4,
		binding = 0,
		format = .R32G32B32A32_SFLOAT,
		offset = u32(offset_of(Vertex, weights)),
	},
}

@(private = "file")
ENGINE_VERSION: u32 : (0 << 22) | (0 << 12) | (1)

@(private = "file")
MAX_FRAMES_IN_FLIGHT: u32 : 2

@(private = "file")
RENDER_SIZE: Vec2 : {1980, 1080}

@(private = "file")
SHADOW_RESOLUTION: Vec2 : {2048, 2048}

@(private = "file")
IMAGES_RESOLUTION: Vec2 : {4096, 4096}

@(private = "file")
DEPTH_BIAS_CONSTANT: f32 : 1.25

@(private = "file")
DEPTH_BIAS_SLOPE: f32 : 1.75


// ###################################################################
// #                         Data Structures                         #
// ###################################################################


@(private = "file")
Vertex :: struct #min_field_align (16) {
	position: Vec3,
	texCoord: Vec2,
	normal:   Vec3,
	bones:    [4]u32,
	weights:  Vec4,
}

@(private = "file")
Bone :: struct {
	name:        cstring,
	isRoot:      bool,
	parentIndex: u32,
	inverseBind: Mat4,
}

@(private = "file")
Skeleton :: []Bone

@(private = "file")
KeyVector :: struct {
	time:  f64,
	value: Vec3,
}

@(private = "file")
KeyQuat :: struct {
	time:  f64,
	value: Quat,
}

@(private = "file")
AnimationNode :: struct {
	bone:            u32,
	keyPositions:    []KeyVector,
	keyRotations:    []KeyQuat,
	keyScales:       []KeyVector,
	numKeyPositions: u32,
	numKeyRotations: u32,
	numKeyScales:    u32,
}

@(private = "file")
Animation :: struct {
	name:     cstring,
	nodes:    []AnimationNode,
	duration: f64,
}

@(private = "file")
Model :: struct {
	name:         cstring,
	vertices:     []Vertex,
	vertexOffset: u32,
	indices:      []u32,
	indexOffset:  u32,
	skeleton:     Skeleton,
	animations:   []Animation,
}

@(private = "file")
Image :: struct {
	vkImage: vk.Image,
	memory:  vk.DeviceMemory,
	view:    vk.ImageView,
	format:  vk.Format,
	sampler: u32,
}

@(private = "file")
ImFDImageData :: struct {
	using image:   Image,
	descriptorSet: vk.DescriptorSet,
}

// Use Vec4 becuse of alignment issues when using Vec3
@(private = "file")
LightData :: struct #align (16) {
	position:        Vec4,
	colourIntensity: Vec4,
	near:            f32,
	far:             f32,
}

@(private = "file")
UniformBuffer :: struct #align (16) {
	view:           Mat4,
	projection:     Mat4,
	viewProjection: Mat4,
	lightCount:     u32,
}

@(private = "file")
InstanceInfo :: struct #align (16) {
	model:                Mat4,
	boneOffset:           u32,
	textureSamplerOffset: f32,
	normalsSamplerOffset: f32,
}

@(private = "file")
QueueFamilyIndices :: struct {
	graphicsFamily: u32,
	presentFamily:  u32,
	computeFamily:  u32,
}

@(private = "file")
SwapchainSupportDetails :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	modes:        []vk.PresentModeKHR,
}

@(private = "file")
Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	mapped: rawptr,
}

@(private = "file")
ImguiData :: struct {
	uiContext:      ^imgui.Context,
	frameBuffers:   []vk.Framebuffer,
	descriptorPool: vk.DescriptorPool,
	renderPass:     vk.RenderPass,
	colour:         Image,
	imfdImages:     [dynamic]ImFDImageData,
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
PipelineIndex :: enum {
	LIGHT      = 0,
	MAIN       = 1,
	PRECOMPUTE = 2,
	POST       = 3,
}

@(private = "file")
Pipeline :: struct {
	using renderPassData: RenderPass,
	descriptorPool:       vk.DescriptorPool,
	descriptorSets:       [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	pipeline:             vk.Pipeline,
	descriptorSetLayout:  vk.DescriptorSetLayout,
	layout:               vk.PipelineLayout,
}

@(private = "file")
PointLight :: struct {
	name:            cstring,
	position:        Vec3,
	colourIntensity: Vec3,
	rotationAngle:   f32,
	rotationAxis:    Vec3,
}

@(private = "file")
Instance :: struct {
	name:         cstring,
	modelID:      u32,
	animID:       u32,
	textureID:    u32,
	normalID:     u32,
	position:     Vec3,
	rotation:     Vec3,
	scale:        Vec3,
	positionKeys: []u32,
	rotationKeys: []u32,
	scaleKeys:    []u32,
	animTimer:    f64,
}

@(private = "file")
Scene :: struct {
	filePath:              string,
	name:                  cstring,
	clearColour:           [4]i32,
	ambientLight:          f32,

	// Scene
	instances:             [dynamic]Instance,
	instanceVerticesCount: int,
	pointLights:           [dynamic]PointLight,
	cameras:               [dynamic]Camera,
	activeCamera:          u32,

	// Assets
	modelPaths:            [dynamic]cstring,
	models:                [dynamic]Model,
	texturePaths:          [dynamic]cstring,
	textures:              Image,
	textureCount:          u32,
	normalPaths:           [dynamic]cstring,
	normals:               Image,
	normalCount:           u32,
	vertices:              [dynamic]Vertex,
	indices:               [dynamic]u32,
	boneCount:             int,
	shadowImages:          Image,

	// Buffers TODO: All buffers should be one buffer using offsets
	vertexBuffer:          Buffer,
	indexBuffer:           Buffer,
	instanceBuffers:       [MAX_FRAMES_IN_FLIGHT]Buffer,
	boneBuffers:           [MAX_FRAMES_IN_FLIGHT]Buffer,
	lightBuffers:          [MAX_FRAMES_IN_FLIGHT]Buffer,
	transformBuffers:      [MAX_FRAMES_IN_FLIGHT]Buffer,
}

CameraMode :: enum {
	PERSPECTIVE,
	ORTHOGRAPHIC,
}

Camera :: struct {
	name:            cstring,
	eye, center, up: Vec3,
	near, far:       f32,
	distance:        f32,
	fov:             f32,
	mode:            CameraMode,
}

GraphicsContext :: struct {
	// GLFW + IMGUI
	window:                   glfw.WindowHandle,
	imguiData:                ImguiData,

	// Vulkan Data
	instance:                 vk.Instance,
	debugMessenger:           vk.DebugUtilsMessengerEXT,
	surface:                  vk.SurfaceKHR,
	physicalDevice:           vk.PhysicalDevice,
	device:                   vk.Device,

	// Queues
	queueFamilies:            QueueFamilyIndices,
	graphicsQueue:            vk.Queue,
	presentQueue:             vk.Queue,
	computeQueue:             vk.Queue,

	// Swapchain
	swapchainImageCount:      u32,
	swapchainTransform:       vk.SurfaceTransformFlagsKHR,
	swapchain:                vk.SwapchainKHR,
	swapchainFormat:          vk.SurfaceFormatKHR,
	swapchainMode:            vk.PresentModeKHR,
	swapchainExtent:          vk.Extent2D,
	swapchainImages:          []vk.Image,
	swapchainImageViews:      []vk.ImageView,
	pipelines:                []Pipeline,

	// Frame Resources
	inImage:                  Image,
	outImage:                 Image,
	inFlightFrames:           []vk.Fence,
	precomputeFinished:       []vk.Semaphore,
	rendersFinished:          []vk.Semaphore,
	computeFinished:          []vk.Semaphore,
	uiFinished:               []vk.Semaphore,
	imagesAvailable:          []vk.Semaphore,

	// Commands
	graphicsCommandPool:      vk.CommandPool,
	mainCommandBuffers:       []vk.CommandBuffer,
	uiCommandBuffers:         []vk.CommandBuffer,
	computeCommandPool:       vk.CommandPool,
	precomputeCommandBuffers: []vk.CommandBuffer,
	computeCommandBuffers:    []vk.CommandBuffer,

	// Scene Data
	scenes:                   [dynamic]Scene,
	activeScene:              u32,
	samplers:                 []vk.Sampler,

	// Buffer
	uniformBuffers:           [MAX_FRAMES_IN_FLIGHT]Buffer,

	// Util
	currentFrame:             u32,
	framebufferResized:       b8,

	// Rendering push constants
	contrast:                 f32,
	brightness:               f32,
	saturation:               f32,
	exposure:                 f32,
	tonemapper:               f32,
	gamma:                    f32,
}


// ###################################################################
// #                               Init                              #
// ###################################################################


initVkGraphics :: proc(
	using graphicsContext: ^GraphicsContext,
	sceneFile: string = "",
) -> (
	err: LoadSceneError = .None,
) {
	when ODIN_DEBUG {
		glfw.SetErrorCallback(glfwErrorCallback)
	}

	if !glfw.Init() {
		log.log(.Fatal, "Failed to initalize GLFW!")
		panic("Failed to init GLFW!")
	}

	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	createInstance(graphicsContext)
	when ODIN_DEBUG {
		vkSetupDebugMessenger(graphicsContext)
	}
	initWindow(graphicsContext)
	pickPhysicalDevice(graphicsContext)
	createLogicalDevice(graphicsContext)
	createSwapchain(graphicsContext)
	createCommandBuffers(graphicsContext)

	bufferSize := size_of(UniformBuffer)
	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		createBuffer(
			graphicsContext,
			bufferSize,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&uniformBuffers[index].buffer,
			&uniformBuffers[index].memory,
		)
		vk.MapMemory(
			device,
			uniformBuffers[index].memory,
			0,
			vk.DeviceSize(bufferSize),
			{},
			&uniformBuffers[index].mapped,
		)
	}

	createSyncObjects(graphicsContext)
	createSamplers(graphicsContext)

	// TODO: Should add a preproces pipeline for vertex transforms (from bones) as I'm computing them lightCount * 6 + 1 times atm.
	pipelines = make([]Pipeline, len(PipelineIndex))

	createRenderPass(graphicsContext)
	createFramebuffers(graphicsContext)

	createGraphicsDescriptorSets(graphicsContext)
	createComputeDescriptorSets(graphicsContext)

	updateGraphicsDescriptorSets(graphicsContext)
	updateComputeDescriptorSets(graphicsContext)

	createGraphicsPipelines(graphicsContext)
	createComputePipelines(graphicsContext)

	when UI_ENABLED {
		initImgui(graphicsContext)
		updateImgui(graphicsContext)
	}

	framebufferResized = false
	currentFrame = 0
	contrast = 1.0
	brightness = 0.0
	saturation = 1.0
	exposure = 0.0
	tonemapper = 0.0 if !HDR_ENABLED else 1.0
	gamma = 1.0 if HDR_ENABLED else 2.2
	scenes = make([dynamic]Scene)

	if sceneFile == "" {
		createNewScene(graphicsContext)
	} else {
		_, err = loadScene(graphicsContext, sceneFile)
		if err == .FailedToLoadSceneFile || err == .FailedToParseJson {
			createNewScene(graphicsContext)
		}
	}

	setActiveScene(graphicsContext, 0)
	return
}

@(private = "file")
createInstance :: proc(using graphicsContext: ^GraphicsContext) {
	appInfo: vk.ApplicationInfo = {
		sType              = .APPLICATION_INFO,
		pNext              = nil,
		pApplicationName   = "Valhalla",
		applicationVersion = APP_VERSION,
		pEngineName        = "Asgardina Graphics",
		engineVersion      = ENGINE_VERSION,
		apiVersion         = vk.API_VERSION_1_4,
	}

	glfwExtensions := glfw.GetRequiredInstanceExtensions()
	supportedExtensions: [dynamic]cstring
	defer delete(supportedExtensions)

	extensionCount: u32
	vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, nil)
	availableExtensions := make([]vk.ExtensionProperties, extensionCount)
	defer delete(availableExtensions)
	vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, raw_data(availableExtensions))
	glfw_extension_outer_loop: for name in glfwExtensions {
		for &extension in availableExtensions {
			if name == cstring(&extension.extensionName[0]) {
				append(&supportedExtensions, name)
				continue glfw_extension_outer_loop
			}
		}
		log.logf(.Error, "Failed to find required extension: {}", name)
		panic("Failed to find required extension")
	}

	when ODIN_DEBUG {
		instance_extension_outer_loop: for name in instanceExtensions {
			for &extension in availableExtensions {
				if (name == cstring(&extension.extensionName[0])) {
					append(&supportedExtensions, name)
					continue instance_extension_outer_loop
				}
			}
			log.logf(.Warning, "Failed to find requested extension: {}", name)
		}
	}

	instanceInfo: vk.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pNext                   = nil,
		flags                   = nil,
		pApplicationInfo        = &appInfo,
		enabledLayerCount       = 0,
		ppEnabledLayerNames     = nil,
		enabledExtensionCount   = u32(len(supportedExtensions)),
		ppEnabledExtensionNames = raw_data(supportedExtensions),
	}

	when ODIN_DEBUG {
		debugMessengerCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
		supportedLayers: [dynamic]cstring
		defer delete(supportedLayers)
		layerCount: u32
		vk.EnumerateInstanceLayerProperties(&layerCount, nil)
		layers := make([]vk.LayerProperties, layerCount)
		defer delete(layers)
		vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(layers))
		instance_layers_outer_loop: for name in requestedLayers {
			for &layer in layers {
				if name == cstring(&layer.layerName[0]) {
					append(&supportedLayers, name)
					continue instance_layers_outer_loop
				}
			}
			log.logf(.Warning, "Failed to find requested layer: {}", name)
		}
		instanceInfo.enabledLayerCount = u32(len(supportedLayers))
		instanceInfo.ppEnabledLayerNames = raw_data(supportedLayers)

		debugMessengerCreateInfo = vkPopulateDebugMessengerCreateInfo()
		instanceInfo.pNext = &debugMessengerCreateInfo
	}

	if vk.CreateInstance(&instanceInfo, nil, &instance) != .SUCCESS {
		log.log(.Error, "Failed to create vulkan instance.")
		panic("Failed to create vulkan instance.")
	}

	// load_proc_addresses_instance :: proc(instance: Instance)
	vk.load_proc_addresses(instance)
}

@(private = "file")
initWindow :: proc(using graphicsContext: ^GraphicsContext) {
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	if window = glfw.CreateWindow(1600, 800, "Valhalla", nil, nil); window == nil {
		log.log(.Fatal, "Failed to create window, quitting application.")
		return
	}

	glfw.SetKeyCallback(window, glfwKeyCallback)
	glfw.SetMouseButtonCallback(window, glfwMouseButtonCallback)
	glfw.SetCursorPosCallback(window, glfwCursorPosCallback)
	glfw.SetScrollCallback(window, glfwScrollCallback)
	glfw.SetFramebufferSizeCallback(window, framebufferResizeCallback)
	if glfw.CreateWindowSurface(instance, window, nil, &surface) != .SUCCESS {
		log.log(.Fatal, "Failed to create surface!")
		panic("Failed to create surface!")
	}
}

cleanupVkGraphics :: proc(using graphicsContext: ^GraphicsContext) {
	graphicsContext := graphicsContext
	if vk.DeviceWaitIdle(device) != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	for index := len(scenes) - 1; index >= 0; index -= 1 {
		cleanupScene(graphicsContext, u32(index))
	}
	delete(scenes)

	when UI_ENABLED {
		cleanupImgui(graphicsContext)
		vk.DestroyDescriptorPool(device, imguiData.descriptorPool, nil)
	}

	vk.FreeCommandBuffers(device, computeCommandPool, 2, raw_data(precomputeCommandBuffers))
	vk.FreeCommandBuffers(device, graphicsCommandPool, 2, raw_data(mainCommandBuffers))
	vk.FreeCommandBuffers(device, computeCommandPool, 2, raw_data(computeCommandBuffers))
	vk.FreeCommandBuffers(device, graphicsCommandPool, 2, raw_data(uiCommandBuffers))

	vk.DestroyCommandPool(device, graphicsCommandPool, nil)
	vk.DestroyCommandPool(device, computeCommandPool, nil)
	delete(precomputeCommandBuffers)
	delete(mainCommandBuffers)
	delete(computeCommandBuffers)
	delete(uiCommandBuffers)

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroyFence(device, inFlightFrames[index], nil)
		vk.DestroySemaphore(device, precomputeFinished[index], nil)
		vk.DestroySemaphore(device, rendersFinished[index], nil)
		vk.DestroySemaphore(device, computeFinished[index], nil)
		vk.DestroySemaphore(device, uiFinished[index], nil)
		vk.DestroySemaphore(device, imagesAvailable[index], nil)
	}
	delete(inFlightFrames)
	delete(precomputeFinished)
	delete(rendersFinished)
	delete(computeFinished)
	delete(uiFinished)
	delete(imagesAvailable)

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		cleanupBuffer(graphicsContext, &uniformBuffers[index])
	}

	for index in 0 ..< swapchainImageCount {
		vk.DestroyFramebuffer(device, pipelines[PipelineIndex.MAIN].frameBuffers[index], nil)
		vk.DestroyFramebuffer(device, pipelines[PipelineIndex.LIGHT].frameBuffers[index], nil)
	}
	delete(pipelines[PipelineIndex.MAIN].frameBuffers)
	delete(pipelines[PipelineIndex.LIGHT].frameBuffers)

	cleanupSwapchain(graphicsContext)

	// PRECOMPUTE
	vk.DestroyDescriptorPool(device, pipelines[PipelineIndex.PRECOMPUTE].descriptorPool, nil)
	vk.DestroyDescriptorSetLayout(
		device,
		pipelines[PipelineIndex.PRECOMPUTE].descriptorSetLayout,
		nil,
	)

	vk.DestroyPipeline(device, pipelines[PipelineIndex.PRECOMPUTE].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.PRECOMPUTE].layout, nil)

	// LIGHT
	cleanupImage(graphicsContext, &pipelines[PipelineIndex.LIGHT].colour)
	cleanupImage(graphicsContext, &pipelines[PipelineIndex.LIGHT].depth)

	vk.DestroyDescriptorPool(device, pipelines[PipelineIndex.LIGHT].descriptorPool, nil)
	vk.DestroyDescriptorSetLayout(device, pipelines[PipelineIndex.LIGHT].descriptorSetLayout, nil)

	vk.DestroyPipeline(device, pipelines[PipelineIndex.LIGHT].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.LIGHT].layout, nil)
	vk.DestroyRenderPass(device, pipelines[PipelineIndex.LIGHT].renderPass, nil)

	// MAIN
	cleanupImage(graphicsContext, &pipelines[PipelineIndex.MAIN].colour)
	cleanupImage(graphicsContext, &pipelines[PipelineIndex.MAIN].depth)

	vk.DestroyDescriptorPool(device, pipelines[PipelineIndex.MAIN].descriptorPool, nil)
	vk.DestroyDescriptorSetLayout(device, pipelines[PipelineIndex.MAIN].descriptorSetLayout, nil)

	vk.DestroyPipeline(device, pipelines[PipelineIndex.MAIN].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.MAIN].layout, nil)
	vk.DestroyRenderPass(device, pipelines[PipelineIndex.MAIN].renderPass, nil)

	// POST
	vk.DestroyDescriptorPool(device, pipelines[PipelineIndex.POST].descriptorPool, nil)
	vk.DestroyDescriptorSetLayout(device, pipelines[PipelineIndex.POST].descriptorSetLayout, nil)

	vk.DestroyPipeline(device, pipelines[PipelineIndex.POST].pipeline, nil)
	vk.DestroyPipelineLayout(device, pipelines[PipelineIndex.POST].layout, nil)

	delete(pipelines)

	cleanupSamplers(graphicsContext)

	vk.DestroyDevice(device, nil)
	vk.DestroySurfaceKHR(instance, surface, nil)

	when ODIN_DEBUG {
		vk.DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
	}

	vk.DestroyInstance(instance, nil)

	glfw.DestroyWindow(window)
	glfw.Terminate()
}


// ###################################################################
// #                              Device                             #
// ###################################################################


@(private = "file")
findQueueFamilies :: proc(
	physicalDevice: vk.PhysicalDevice,
	graphicsContext: ^GraphicsContext,
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
			   graphicsContext.surface,
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
querySwapchainSupport :: proc(
	physicalDevice: vk.PhysicalDevice,
	graphicsContext: ^GraphicsContext,
) -> (
	swapchainSupport: SwapchainSupportDetails,
) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		physicalDevice,
		graphicsContext.surface,
		&swapchainSupport.capabilities,
	)

	formatCount: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physicalDevice,
		graphicsContext.surface,
		&formatCount,
		nil,
	)
	if formatCount != 0 {
		swapchainSupport.formats = make([]vk.SurfaceFormatKHR, formatCount)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			physicalDevice,
			graphicsContext.surface,
			&formatCount,
			raw_data(swapchainSupport.formats),
		)
	}

	modeCount: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physicalDevice,
		graphicsContext.surface,
		&modeCount,
		nil,
	)
	if modeCount != 0 {
		swapchainSupport.modes = make([]vk.PresentModeKHR, modeCount)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			physicalDevice,
			graphicsContext.surface,
			&modeCount,
			raw_data(swapchainSupport.modes),
		)
	}
	return
}

@(private = "file")
pickPhysicalDevice :: proc(graphicsContext: ^GraphicsContext) {
	scorePhysicalDevice :: proc(
		physicalDevice: vk.PhysicalDevice,
		graphicsContext: ^GraphicsContext,
	) -> (
		score: u32 = 0,
	) {
		physicalDeviceProperties: vk.PhysicalDeviceProperties
		physicalDeviceFeatures: vk.PhysicalDeviceFeatures

		vk.GetPhysicalDeviceProperties(physicalDevice, &physicalDeviceProperties)
		vk.GetPhysicalDeviceFeatures(physicalDevice, &physicalDeviceFeatures)

		indices, err := findQueueFamilies(physicalDevice, graphicsContext)
		if err ||
		   !physicalDeviceFeatures.geometryShader ||
		   !physicalDeviceFeatures.samplerAnisotropy ||
		   !checkDeviceExtensionSupport(physicalDevice) ||
		   !swapchainAdequate(physicalDevice, graphicsContext) {
			return
		}

		if physicalDeviceProperties.deviceType == .DISCRETE_GPU {
			score += 1000
		}

		if (indices.graphicsFamily == indices.presentFamily) {
			score += 100
		}

		score += physicalDeviceProperties.limits.maxImageDimension2D
		return
	}

	checkDeviceExtensionSupport :: proc(physicalDevice: vk.PhysicalDevice) -> b32 {
		extensionCount: u32
		vk.EnumerateDeviceExtensionProperties(physicalDevice, nil, &extensionCount, nil)
		availableExtensions := make([]vk.ExtensionProperties, extensionCount)
		defer delete(availableExtensions)
		vk.EnumerateDeviceExtensionProperties(
			physicalDevice,
			nil,
			&extensionCount,
			raw_data(availableExtensions),
		)

		outer_loop: for name in deviceExtensions {
			for &extension in availableExtensions {
				if (name == cstring(&extension.extensionName[0])) {
					continue outer_loop
				}
			}
			return false
		}
		return true
	}

	swapchainAdequate :: proc(
		physicalDevice: vk.PhysicalDevice,
		graphicsContext: ^GraphicsContext,
	) -> b32 {
		support := querySwapchainSupport(physicalDevice, graphicsContext)
		defer delete(support.formats)
		defer delete(support.modes)
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
	vk.EnumeratePhysicalDevices(graphicsContext.instance, &deviceCount, nil)

	if deviceCount == 0 {
		log.log(.Error, "No devices with Vulkan support!")
		panic("No devices with Vulkan support!")
	}

	physicalDevices := make([]vk.PhysicalDevice, deviceCount)
	defer delete(physicalDevices)
	vk.EnumeratePhysicalDevices(graphicsContext.instance, &deviceCount, raw_data(physicalDevices))

	{
		physicalDeviceMap: map[^vk.PhysicalDevice]u32
		defer delete(physicalDeviceMap)
		for &physicalDevice in physicalDevices {
			physicalDeviceMap[&physicalDevice] = scorePhysicalDevice(
				physicalDevice,
				graphicsContext,
			)
		}

		bestScore: u32
		for physicalDevice, score in physicalDeviceMap {
			if (score > bestScore) {
				graphicsContext.physicalDevice = (^vk.PhysicalDevice)(physicalDevice)^
				bestScore = score
			}
		}
	}

	if graphicsContext.physicalDevice == nil {
		log.log(.Error, "No suitable physical device found!")
		panic("No suitable physical device found!")
	}
}

@(private = "file")
createLogicalDevice :: proc(using graphicsContext: ^GraphicsContext) {
	queueFamilies, _ = findQueueFamilies(physicalDevice, graphicsContext)

	queuePriority: f32 = 1.0
	queueCreateInfos: [dynamic]vk.DeviceQueueCreateInfo
	defer delete(queueCreateInfos)
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
		multiViewport                           = true,
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

	requiredDeviceExtensions := deviceExtensions
	createInfo: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &sync2,
		flags                   = {},
		queueCreateInfoCount    = u32(len(queueCreateInfos)),
		pQueueCreateInfos       = raw_data(queueCreateInfos),
		enabledLayerCount       = 0,
		ppEnabledLayerNames     = nil,
		enabledExtensionCount   = u32(len(requiredDeviceExtensions)),
		ppEnabledExtensionNames = raw_data(requiredDeviceExtensions),
		pEnabledFeatures        = &deviceFeatures,
	}

	when ODIN_DEBUG {
		createInfo.enabledLayerCount = u32(len(requestedLayers))
		createInfo.ppEnabledLayerNames = raw_data(requestedLayers)
	}

	if vk.CreateDevice(physicalDevice, &createInfo, nil, &device) != .SUCCESS {
		log.log(.Error, "Failed to create logical device!")
		panic("Failed to create logical device!")
	}

	// load_proc_addresses_device :: proc(device: Device)
	vk.load_proc_addresses(device)

	vk.GetDeviceQueue(device, queueFamilies.graphicsFamily, 0, &graphicsQueue)
	vk.GetDeviceQueue(device, queueFamilies.presentFamily, 0, &presentQueue)
	vk.GetDeviceQueue(device, queueFamilies.computeFamily, 0, &computeQueue)
}


// ###################################################################
// #                            Swapchain                            #
// ###################################################################


@(private = "file")
createSwapchain :: proc(using graphicsContext: ^GraphicsContext) {
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
		capabilities: vk.SurfaceCapabilitiesKHR,
		using graphicsContext: ^GraphicsContext,
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

	swapchainSupport := querySwapchainSupport(physicalDevice, graphicsContext)

	max := swapchainSupport.capabilities.maxImageCount
	min := swapchainSupport.capabilities.minImageCount
	swapchainImageCount = max if max == 1 else (2 if 2 >= min else min)
	swapchainTransform = swapchainSupport.capabilities.currentTransform

	swapchainFormat = chooseFormat(swapchainSupport.formats)
	swapchainMode = choosePresentMode(swapchainSupport.modes)
	swapchainExtent = chooseExtent(swapchainSupport.capabilities, graphicsContext)
	delete(swapchainSupport.formats)
	delete(swapchainSupport.modes)

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

	if vk.CreateSwapchainKHR(device, &createInfo, nil, &swapchain) != .SUCCESS {
		log.log(.Error, "Failed to create swapchain!")
		panic("Failed to create swapchain!")
	}

	swapchainImages = make([]vk.Image, swapchainImageCount)
	vk.GetSwapchainImagesKHR(device, swapchain, &swapchainImageCount, raw_data(swapchainImages))

	swapchainImageViews = make([]vk.ImageView, swapchainImageCount)
	for index in 0 ..< swapchainImageCount {
		swapchainImageViews[index] = createImageView(
			graphicsContext,
			swapchainImages[index],
			.D2,
			swapchainFormat.format,
			{.COLOR},
			1,
		)
	}
}

@(private = "file")
recreateSwapchain :: proc(using graphicsContext: ^GraphicsContext) {
	width, height := glfw.GetFramebufferSize(window)
	for width == 0 && height == 0 {
		glfw.WaitEvents()
		width, height = glfw.GetFramebufferSize(window)
	}

	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		panic("Error waiting for device idle!")
	}

	cleanupSwapchain(graphicsContext)

	createSwapchain(graphicsContext)
	updateComputeDescriptorSets(graphicsContext)

	when UI_ENABLED {
		cleanupImgui(graphicsContext)
		updateImgui(graphicsContext)
	}
}

@(private = "file")
cleanupSwapchain :: proc(using graphicsContext: ^GraphicsContext) {
	for imageView in swapchainImageViews {
		vk.DestroyImageView(device, imageView, nil)
	}
	delete(swapchainImages)
	delete(swapchainImageViews)

	vk.DestroySwapchainKHR(device, swapchain, nil)
	cleanupImage(graphicsContext, &inImage)
	cleanupImage(graphicsContext, &outImage)
}


// ###################################################################
// #                             Commands                            #
// ###################################################################


@(private = "file")
createCommandBuffers :: proc(using graphicsContext: ^GraphicsContext) {
	poolInfo: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		pNext            = nil,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queueFamilies.graphicsFamily,
	}
	if vk.CreateCommandPool(device, &poolInfo, nil, &graphicsCommandPool) != .SUCCESS {
		log.log(.Error, "Failed to create command pool!")
		panic("Failed to create command pool!")
	}

	mainCommandBuffers = make([]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
	allocInfo: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if vk.AllocateCommandBuffers(device, &allocInfo, raw_data(mainCommandBuffers)) != .SUCCESS {
		log.log(.Error, "Failed to allocate command buffer!")
		panic("Failed to allocate command buffer!")
	}

	uiCommandBuffers = make([]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = graphicsCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if vk.AllocateCommandBuffers(device, &allocInfo, raw_data(uiCommandBuffers)) != .SUCCESS {
		log.log(.Error, "Failed to allocate command buffer!")
		panic("Failed to allocate command buffer!")
	}

	poolInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		pNext            = nil,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queueFamilies.computeFamily,
	}
	if vk.CreateCommandPool(device, &poolInfo, nil, &computeCommandPool) != .SUCCESS {
		log.log(.Error, "Failed to create command pool!")
		panic("Failed to create command pool!")
	}

	precomputeCommandBuffers = make([]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = computeCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if vk.AllocateCommandBuffers(device, &allocInfo, raw_data(precomputeCommandBuffers)) !=
	   .SUCCESS {
		log.log(.Error, "Failed to allocate command buffer!")
		panic("Failed to allocate command buffer!")
	}

	computeCommandBuffers = make([]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
	allocInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = computeCommandPool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if vk.AllocateCommandBuffers(device, &allocInfo, raw_data(computeCommandBuffers)) != .SUCCESS {
		log.log(.Error, "Failed to allocate command buffer!")
		panic("Failed to allocate command buffer!")
	}
}

@(private = "file")
beginSingleTimeCommands :: proc(
	using graphicsContext: ^GraphicsContext,
	commandPool: vk.CommandPool,
) -> (
	commandBuffer: vk.CommandBuffer,
) {
	allocInfo: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = commandPool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	vk.AllocateCommandBuffers(device, &allocInfo, &commandBuffer)
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {.ONE_TIME_SUBMIT},
		pInheritanceInfo = nil,
	}
	vk.BeginCommandBuffer(commandBuffer, &beginInfo)
	return
}

@(private = "file")
endSingleTimeCommands :: proc(
	using graphicsContext: ^GraphicsContext,
	commandBuffer: vk.CommandBuffer,
	commandPool: vk.CommandPool,
) {
	commandBuffer := commandBuffer
	vk.EndCommandBuffer(commandBuffer)
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
}


// ###################################################################
// #                             Buffers                             #
// ###################################################################


@(private = "file")
createBuffer :: proc(
	using graphicsContext: ^GraphicsContext,
	size: int,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^vk.Buffer,
	bufferMemory: ^vk.DeviceMemory,
) {
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
	vkDevice := graphicsContext.device
	if vk.CreateBuffer(vkDevice, &bufferInfo, nil, buffer) != .SUCCESS {
		log.log(.Error, "Failed to create buffer!")
		panic("Failed to create buffer!")
	}

	memRequirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer^, &memRequirements)
	allocInfo: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = nil,
		allocationSize  = memRequirements.size,
		memoryTypeIndex = findMemoryType(
			graphicsContext,
			memRequirements.memoryTypeBits,
			properties,
		),
	}
	if vk.AllocateMemory(device, &allocInfo, nil, bufferMemory) != .SUCCESS {
		log.log(.Error, "Failed to allocate buffer memory!")
		panic("Failed to allocate buffer memory!")
	}
	vk.BindBufferMemory(device, buffer^, bufferMemory^, 0)
}

@(private = "file")
loadBufferToGPU :: proc(
	using graphicsContext: ^GraphicsContext,
	bufferSize: int,
	srcData: rawptr,
	dstBuffer: ^Buffer,
	bufferType: vk.BufferUsageFlag,
) {
	stagingBuffer: Buffer
	createBuffer(
		graphicsContext,
		bufferSize,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&stagingBuffer.buffer,
		&stagingBuffer.memory,
	)

	data: rawptr
	vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(bufferSize), {}, &data)
	mem.copy(data, srcData, bufferSize)
	vk.UnmapMemory(device, stagingBuffer.memory)

	createBuffer(
		graphicsContext,
		bufferSize,
		{.TRANSFER_DST, .STORAGE_BUFFER, bufferType},
		{.DEVICE_LOCAL},
		&dstBuffer.buffer,
		&dstBuffer.memory,
	)

	commandBuffer: vk.CommandBuffer = beginSingleTimeCommands(graphicsContext, graphicsCommandPool)

	copyRegion: vk.BufferCopy = {
		srcOffset = 0,
		dstOffset = 0,
		size      = vk.DeviceSize(bufferSize),
	}

	vk.CmdCopyBuffer(commandBuffer, stagingBuffer.buffer, dstBuffer.buffer, 1, &copyRegion)

	endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)

	cleanupBuffer(graphicsContext, &stagingBuffer)
}

// Useful to have a function for this so I can update allocators easily in the future. 
@(private = "file")
cleanupBuffer :: proc(using graphicsContext: ^GraphicsContext, buffer: ^Buffer) {
	vk.DestroyBuffer(device, buffer.buffer, nil)
	vk.FreeMemory(device, buffer.memory, nil)
}


// ###################################################################
// #                              Images                             #
// ###################################################################


@(private = "file")
findMemoryType :: proc(
	using graphicsContext: ^GraphicsContext,
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
	log.log(.Error, "Failed to find suitable memory type!")
	panic("Failed to find suitable memory type!")
}

@(private = "file")
createImage :: proc(
	using graphicsContext: ^GraphicsContext,
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
) {
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

	if vk.CreateImage(device, &imageInfo, nil, &image.vkImage) != .SUCCESS {
		log.log(.Error, "Failed to create texture!")
		panic("Failed to create texture!")
	}

	memRequirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image.vkImage, &memRequirements)
	allocInfo: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		pNext           = nil,
		allocationSize  = memRequirements.size,
		memoryTypeIndex = findMemoryType(
			graphicsContext,
			memRequirements.memoryTypeBits,
			properties,
		),
	}
	if vk.AllocateMemory(device, &allocInfo, nil, &image.memory) != .SUCCESS {
		log.log(.Error, "Failed to allocate image memory!")
		panic("Failed to allocate image memory!")
	}
	if vk.BindImageMemory(device, image.vkImage, image.memory, 0) != .SUCCESS {
		log.log(.Error, "Failed to bind image memory!")
		panic("Failed to bind image memory!")
	}
}

@(private = "file")
createImageView :: proc(
	using graphicsContext: ^GraphicsContext,
	image: vk.Image,
	viewType: vk.ImageViewType,
	format: vk.Format,
	aspectFlags: vk.ImageAspectFlags,
	layerCount: u32,
) -> (
	imageView: vk.ImageView,
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
	if vk.CreateImageView(device, &viewInfo, nil, &imageView) != .SUCCESS {
		log.log(.Error, "Failed to create image view!")
		panic("Failed to create image view!")
	}
	return imageView
}

@(private = "file")
transitionImageLayout :: proc(
	using graphicsContext: ^GraphicsContext,
	commandBuffer: vk.CommandBuffer,
	image: vk.Image,
	oldLayout, newLayout: vk.ImageLayout,
	aspectMask: vk.ImageAspectFlags,
	layerCount: u32,
) {
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
		log.log(.Error, "Unsupported image layout transition!")
		panic("Unsupported image layout transition!")
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
		log.log(.Error, "Unsupported image layout transition!")
		panic("Unsupported image layout transition!")
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
}

@(private = "file")
copyBufferToImage :: proc(
	using graphicsContext: ^GraphicsContext,
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
	using graphicsContext: ^GraphicsContext,
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

@(private = "file")
createSamplers :: proc(using graphicsContext: ^GraphicsContext) {
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
	if vk.CreateSampler(device, &samplerInfo, nil, &samplers[0]) != .SUCCESS {
		log.log(.Error, "Failed to create texture sampler!")
		panic("Failed to create texture sampler!")
	}

	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physicalDevice, &properties)
	samplerInfo.anisotropyEnable = true
	samplerInfo.maxAnisotropy = properties.limits.maxSamplerAnisotropy
	if vk.CreateSampler(device, &samplerInfo, nil, &samplers[1]) != .SUCCESS {
		log.log(.Error, "Failed to create texture sampler!")
		panic("Failed to create texture sampler!")
	}
}

@(private = "file")
cleanupSamplers :: proc(using graphicsContext: ^GraphicsContext) {
	for &sampler in samplers {
		vk.DestroySampler(device, sampler, nil)
	}
	delete(samplers)
}


// ###################################################################
// #                              Assets                             #
// ###################################################################


@(private = "file")
loadModels :: proc(
	using graphicsContext: ^GraphicsContext,
	sceneIndex: u32,
	modelPaths: []cstring,
) {
	loadFBX :: proc(graphicsContext: ^GraphicsContext, model: ^Model, filename: cstring) {
		opts: ufbx.Load_Opts = {
			target_axes = ufbx.Coordinate_Axes {
				right = .POSITIVE_X,
				up = .POSITIVE_Y,
				front = .POSITIVE_Z,
			},
		}
		err: ufbx.Error
		scene := ufbx.load_file(filename, &opts, &err)
		if err.type != .NONE || scene == nil {
			log.logf(.Error, "Failed to load FBX file! Reason\n{}", err.description.data)
			panic("Failed to load FBX file!")
		}
		defer ufbx.free_scene(scene)

		model.skeleton = make([]Bone, scene.bones.count)
		boneIndex := 0
		for index in 0 ..< scene.nodes.count {
			node := scene.nodes.data[index]
			if node.attrib_type != .BONE {
				continue
			}

			parentIndex: u32 = 0
			if !node.parent.is_root {
				for bone, index in model.skeleton {
					if bone.name == node.parent.element.name.data {
						parentIndex = u32(index)
						break
					}
				}
			}
			model.skeleton[boneIndex] = {
				name        = node.bone.element.name.data,
				isRoot      = node.parent.is_root,
				parentIndex = parentIndex,
			}
			boneIndex += 1
		}

		vertexCount: uint = 0
		indexCount: uint = 0
		for index in 0 ..< scene.meshes.count {
			vertexCount += scene.meshes.data[index].num_indices
			indexCount += scene.meshes.data[index].num_triangles * 3
		}

		model.vertices = make([]Vertex, vertexCount)
		model.indices = make([]u32, indexCount)

		// TODO: Surely there is a way to copy a cstring better than this. Might have to copy the data?
		model.name = strings.clone_to_cstring(string(scene.meshes.data[0].element.name.data))

		vertexOffset, indexOffset, meshIndexOffset: u32 = 0, 0, 0
		for meshIndex in 0 ..< scene.meshes.count {
			mesh := scene.meshes.data[meshIndex]
			for faceIndex in 0 ..< mesh.faces.count {
				face := mesh.faces.data[faceIndex]
				triangulatedIndexCount := (face.num_indices - 2) * 3

				err: ufbx.Panic
				tris := ufbx.catch_triangulate_face(
					&err,
					raw_data(model.indices[indexOffset:indexOffset + triangulatedIndexCount]),
					uint(triangulatedIndexCount),
					mesh,
					face,
				)

				if err.did_panic {
					errMessage := transmute(string)err.message[0:err.message_length]
					log.log(.Error, errMessage)
					panic(errMessage)
				}

				for &index in model.indices[indexOffset:indexOffset + triangulatedIndexCount] {
					index += meshIndexOffset
				}
				indexOffset += triangulatedIndexCount
			}

			for indiceIndex in 0 ..< mesh.num_indices {
				indiceIndex := u32(indiceIndex)
				vertexIndex := mesh.vertex_position.indices.data[indiceIndex]
				pos := mesh.vertex_position.values.data[vertexIndex]

				uv := [2]f64{0, 0}
				if mesh.vertex_uv.values.count != 0 {
					uv = mesh.vertex_uv.values.data[mesh.vertex_uv.indices.data[indiceIndex]]
				}

				norm := [3]f64{0, 1, 0}
				if mesh.vertex_normal.values.count != 0 {
					norm =
						mesh.vertex_normal.values.data[mesh.vertex_normal.indices.data[indiceIndex]]
				}

				model.vertices[indiceIndex + vertexOffset] = {
					position = {f32(pos.x), f32(pos.y), f32(pos.z)},
					texCoord = {f32(uv.x), 1 - f32(uv.y)},
					normal   = {f32(norm.x), f32(norm.y), f32(norm.z)},
					weights  = {1.0, 0.0, 0.0, 0.0},
					bones    = {0, 0, 0, 0},
				}

				if mesh.skin_deformers.count != 0 {
					deformer := mesh.skin_deformers.data[0]
					numWeights :=
						deformer.vertices.data[vertexIndex].num_weights if deformer.vertices.data[vertexIndex].num_weights <= 4 else 4
					firstWeightIndex := deformer.vertices.data[vertexIndex].weight_begin

					for weightIndex in 0 ..< numWeights {
						skinWeight := deformer.weights.data[firstWeightIndex + weightIndex]
						boneName :=
							deformer.clusters.data[skinWeight.cluster_index].bone_node.element.name

						for &bone, boneIndex in model.skeleton {
							if bone.name == boneName.data {
								model.vertices[indiceIndex + vertexOffset].bones[weightIndex] =
									u32(boneIndex)
								break
							}
						}

						model.vertices[indiceIndex + vertexOffset].weights[weightIndex] = f32(
							skinWeight.weight,
						)
					}

					if numWeights != 0 {
						model.vertices[indiceIndex + vertexOffset].weights = normalize(
							model.vertices[indiceIndex + vertexOffset].weights,
						)
					}
				}
			}

			vertexOffset += u32(mesh.num_indices)
			meshIndexOffset = indexOffset
		}

		for clusterIndex in 0 ..< scene.skin_cluster.count {
			skinCluster := scene.skin_cluster.data[clusterIndex]^
			for &bone in model^.skeleton {
				if bone.name != skinCluster.bone_node.element.name.data {
					continue
				}

				m := skinCluster.geometry_to_bone.cols
				bone.inverseBind = {
					f32(m[0][0]),
					f32(m[1][0]),
					f32(m[2][0]),
					f32(m[3][0]),
					f32(m[0][1]),
					f32(m[1][1]),
					f32(m[2][1]),
					f32(m[3][1]),
					f32(m[0][2]),
					f32(m[1][2]),
					f32(m[2][2]),
					f32(m[3][2]),
					0,
					0,
					0,
					1,
				}
				break
			}
		}

		model.animations = make([]Animation, scene.anim_stacks.count)
		for animIndex in 0 ..< scene.anim_stacks.count {
			stack := scene.anim_stacks.data[animIndex]

			err: ufbx.Error
			bakedAnim := ufbx.bake_anim(scene, stack.anim, nil, &err)
			if err.type != .NONE {
				log.logf(.Error, "Error baking animation: {}", err.description.data)
				continue
			}
			defer ufbx.free_baked_anim(bakedAnim)

			animation := &model.animations[animIndex]
			// TODO: Surely there is a way to copy a cstring better than this. Might have to copy the data?
			animation.name = strings.clone_to_cstring(string(stack.element.name.data))
			animation.duration = bakedAnim.playback_duration
			animation.nodes = make([]AnimationNode, bakedAnim.nodes.count)

			for bakedIndex in 0 ..< bakedAnim.nodes.count {
				bakedNode := bakedAnim.nodes.data[bakedIndex]
				sceneNode := scene.nodes.data[bakedNode.typed_id]

				for bone, boneIndex in model.skeleton {
					if bone.name != sceneNode.element.name.data {
						continue
					}
					animNode := &animation.nodes[bakedIndex]
					animNode.bone = u32(boneIndex)
					animNode.keyPositions = make([]KeyVector, bakedNode.translation_keys.count)
					animNode.keyRotations = make([]KeyQuat, bakedNode.rotation_keys.count)
					animNode.keyScales = make([]KeyVector, bakedNode.scale_keys.count)
					animNode.numKeyPositions = bakedNode.translation_keys.count
					animNode.numKeyRotations = bakedNode.rotation_keys.count
					animNode.numKeyScales = bakedNode.scale_keys.count

					for index in 0 ..< bakedNode.translation_keys.count {
						data := bakedNode.translation_keys.data[index]
						animNode.keyPositions[index].time = data.time
						animNode.keyPositions[index].value.x = f32(data.value[0])
						animNode.keyPositions[index].value.y = f32(data.value[1])
						animNode.keyPositions[index].value.z = f32(data.value[2])
					}

					for index in 0 ..< bakedNode.rotation_keys.count {
						data := bakedNode.rotation_keys.data[index]
						animNode.keyRotations[index].time = data.time
						animNode.keyRotations[index].value.x = f32(data.value[0])
						animNode.keyRotations[index].value.y = f32(data.value[1])
						animNode.keyRotations[index].value.z = f32(data.value[2])
						animNode.keyRotations[index].value.w = f32(data.value[3])
					}

					for index in 0 ..< bakedNode.scale_keys.count {
						data := bakedNode.scale_keys.data[index]
						animNode.keyScales[index].time = data.time
						animNode.keyScales[index].value.x = f32(data.value[0])
						animNode.keyScales[index].value.y = f32(data.value[1])
						animNode.keyScales[index].value.z = f32(data.value[2])
					}
					break
				}
			}
		}
	}

	scene := &scenes[sceneIndex]

	modelOffset := len(scene.models)
	resize(&scene.models, len(scene.models) + len(modelPaths))

	for path, index in modelPaths {
		modelIndex := modelOffset + index

		scene.models[modelIndex].vertexOffset = u32(len(scene.vertices))
		scene.models[modelIndex].indexOffset = u32(len(scene.indices))

		loadFBX(graphicsContext, &scene.models[modelIndex], path)

		append(&scene.vertices, ..scene.models[modelIndex].vertices)
		append(&scene.indices, ..scene.models[modelIndex].indices)
	}
}

@(private = "file")
loadImages :: proc(using graphicsContext: ^GraphicsContext, image: ^Image, imagePaths: []cstring) {
	imageCount := u32(len(imagePaths))
	image.format = .R8G8B8A8_SRGB
	createImage(
		graphicsContext,
		image,
		{},
		.D2,
		u32(IMAGES_RESOLUTION.x),
		u32(IMAGES_RESOLUTION.y),
		imageCount,
		{._1},
		.OPTIMAL,
		{.TRANSFER_DST, .TRANSFER_SRC, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)

	commandBuffer := beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		image.vkImage,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		imageCount,
	)
	endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)

	for path, index in imagePaths {
		width, height: i32
		pixels := img.load(path, &width, &height, nil, 4)
		defer img.image_free(pixels)
		if pixels == nil {
			log.log(.Error, "Failed to load texture!")
			panic("Failed to load texture!")
		}
		textureSize := int(width * height * 4)

		stagingBuffer: Buffer
		createBuffer(
			graphicsContext,
			textureSize,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&stagingBuffer.buffer,
			&stagingBuffer.memory,
		)
		defer {
			cleanupBuffer(graphicsContext, &stagingBuffer)
		}

		data: rawptr
		vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(textureSize), {}, &data)
		mem.copy(data, pixels, textureSize)
		vk.UnmapMemory(device, stagingBuffer.memory)

		stagingImage: Image
		stagingImage.format = .R8G8B8A8_SRGB
		createImage(
			graphicsContext,
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
		defer {
			vk.DestroyImage(device, stagingImage.vkImage, nil)
			vk.FreeMemory(device, stagingImage.memory, nil)
		}

		commandBuffer = beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			stagingImage.vkImage,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		copyBufferToImage(
			graphicsContext,
			commandBuffer,
			stagingBuffer.buffer,
			stagingImage.vkImage,
			u32(width),
			u32(height),
		)

		transitionImageLayout(
			graphicsContext,
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
			{u32(IMAGES_RESOLUTION.x), u32(IMAGES_RESOLUTION.y)},
			0,
			u32(index),
		)
		endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)
	}

	commandBuffer = beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		image.vkImage,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR},
		imageCount,
	)
	endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)

	image.view = createImageView(
		graphicsContext,
		image.vkImage,
		.D2_ARRAY,
		image.format,
		{.COLOR},
		imageCount,
	)

	image.sampler = 1
}

addImages :: proc(
	using graphicsContext: ^GraphicsContext,
	image: ^Image,
	imageLayers: u32,
	imagePaths: []cstring,
) {
	imageCount := u32(len(imagePaths))

	newImage: Image = {
		format  = image.format,
		sampler = image.sampler,
	}

	createImage(
		graphicsContext,
		&newImage,
		{},
		.D2,
		u32(IMAGES_RESOLUTION.x),
		u32(IMAGES_RESOLUTION.y),
		imageLayers + imageCount,
		{._1},
		.OPTIMAL,
		{.TRANSFER_DST, .TRANSFER_SRC, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)

	commandBuffer := beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		newImage.vkImage,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		imageLayers + imageCount,
	)

	transitionImageLayout(
		graphicsContext,
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
		extent = {u32(IMAGES_RESOLUTION.x), u32(IMAGES_RESOLUTION.y), 1},
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
	endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)

	cleanupImage(graphicsContext, image)
	image^ = newImage

	imageLayers := imageLayers
	for path in imagePaths {
		width, height: i32
		pixels := img.load(path, &width, &height, nil, 4)
		defer img.image_free(pixels)
		if pixels == nil {
			log.log(.Error, "Failed to load texture!")
			panic("Failed to load texture!")
		}
		textureSize := int(width * height * 4)

		stagingBuffer: Buffer
		createBuffer(
			graphicsContext,
			textureSize,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&stagingBuffer.buffer,
			&stagingBuffer.memory,
		)
		defer {
			cleanupBuffer(graphicsContext, &stagingBuffer)
		}

		data: rawptr
		vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(textureSize), {}, &data)
		mem.copy(data, pixels, textureSize)
		vk.UnmapMemory(device, stagingBuffer.memory)

		stagingImage: Image
		stagingImage.format = .R8G8B8A8_SRGB
		createImage(
			graphicsContext,
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
		defer {
			vk.DestroyImage(device, stagingImage.vkImage, nil)
			vk.FreeMemory(device, stagingImage.memory, nil)
		}

		commandBuffer := beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			stagingImage.vkImage,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		copyBufferToImage(
			graphicsContext,
			commandBuffer,
			stagingBuffer.buffer,
			stagingImage.vkImage,
			u32(width),
			u32(height),
		)

		transitionImageLayout(
			graphicsContext,
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
			{u32(IMAGES_RESOLUTION.x), u32(IMAGES_RESOLUTION.y)},
			0,
			imageLayers,
		)
		endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)
		imageLayers += 1
	}

	commandBuffer = beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		image.vkImage,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR},
		imageLayers,
	)
	endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)

	image.view = createImageView(
		graphicsContext,
		image.vkImage,
		.D2_ARRAY,
		image.format,
		{.COLOR},
		imageLayers,
	)
}

@(private = "file")
createShadowImage :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scenes[sceneIndex].shadowImages.format = .R32_SFLOAT

	imageLayers := u32(len(scenes[sceneIndex].pointLights)) * 6
	createImage(
		graphicsContext,
		&scenes[sceneIndex].shadowImages,
		{.CUBE_COMPATIBLE},
		.D2,
		u32(SHADOW_RESOLUTION.x),
		u32(SHADOW_RESOLUTION.y),
		imageLayers,
		{._1},
		.OPTIMAL,
		{.TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
		.EXCLUSIVE,
		0,
		nil,
	)

	commandBuffer := beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		scenes[sceneIndex].shadowImages.vkImage,
		.UNDEFINED,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR},
		imageLayers,
	)
	endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)

	scenes[sceneIndex].shadowImages.view = createImageView(
		graphicsContext,
		scenes[sceneIndex].shadowImages.vkImage,
		.CUBE_ARRAY,
		scenes[sceneIndex].shadowImages.format,
		{.COLOR},
		imageLayers,
	)

	scenes[sceneIndex].shadowImages.sampler = 0
}

// Useful to have a function for this so I can update allocators easily in the future. 
@(private = "file")
cleanupImage :: proc(using graphicsContext: ^GraphicsContext, image: ^Image) {
	vk.DestroyImageView(device, image.view, nil)
	vk.DestroyImage(device, image.vkImage, nil)
	vk.FreeMemory(device, image.memory, nil)
}


// ###################################################################
// #                             Scenes                              #
// ###################################################################


LoadSceneError :: enum {
	None,
	FailedToLoadSceneFile,
	FailedToParseJson,
	FailedToLoadModel,
	FailedToLoadTexture,
}

@(private = "file")
loadSceneAssets :: proc(
	using graphicsContext: ^GraphicsContext,
	sceneIndex: u32,
) -> (
	err: LoadSceneError = .None,
) {
	scene := &scenes[sceneIndex]
	loadModels(graphicsContext, sceneIndex, scene.modelPaths[:])

	loadBufferToGPU(
		graphicsContext,
		size_of(Vertex) * len(scene.vertices),
		raw_data(scene.vertices),
		&scene.vertexBuffer,
		.VERTEX_BUFFER,
	)
	loadBufferToGPU(
		graphicsContext,
		size_of(u32) * len(scene.indices),
		raw_data(scene.indices),
		&scene.indexBuffer,
		.INDEX_BUFFER,
	)

	loadImages(graphicsContext, &scene.textures, scene.texturePaths[:])
	loadImages(graphicsContext, &scene.normals, scene.normalPaths[:])
	scene.textureCount = u32(len(scene.texturePaths))
	scene.normalCount = u32(len(scene.normalPaths))

	for &inst in scene.instances {
		skeletonLength := len(scene.models[inst.modelID].skeleton)
		scene.boneCount += skeletonLength
		inst.positionKeys = make([]u32, skeletonLength)
		inst.rotationKeys = make([]u32, skeletonLength)
		inst.scaleKeys = make([]u32, skeletonLength)
		inst.animTimer = 0.0
		scene.instanceVerticesCount += len(scene.models[inst.modelID].vertices)
	}
	scene.boneCount += 1

	instanceBufferSize := size_of(Instance) * len(scene.instances)
	boneBufferSize := size_of(Mat4) * scene.boneCount
	lightBufferSize := size_of(LightData) * len(scene.pointLights)
	transformBufferSize := size_of(Mat4) * scene.instanceVerticesCount

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		createBuffer(
			graphicsContext,
			instanceBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&scene.instanceBuffers[i].buffer,
			&scene.instanceBuffers[i].memory,
		)
		vk.MapMemory(
			device,
			scene.instanceBuffers[i].memory,
			0,
			vk.DeviceSize(instanceBufferSize),
			{},
			&scene.instanceBuffers[i].mapped,
		)

		createBuffer(
			graphicsContext,
			boneBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&scene.boneBuffers[i].buffer,
			&scene.boneBuffers[i].memory,
		)
		vk.MapMemory(
			device,
			scene.boneBuffers[i].memory,
			0,
			vk.DeviceSize(boneBufferSize),
			{},
			&scene.boneBuffers[i].mapped,
		)

		createBuffer(
			graphicsContext,
			lightBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&scene.lightBuffers[i].buffer,
			&scene.lightBuffers[i].memory,
		)
		vk.MapMemory(
			device,
			scene.lightBuffers[i].memory,
			0,
			vk.DeviceSize(lightBufferSize),
			{},
			&scene.lightBuffers[i].mapped,
		)

		createBuffer(
			graphicsContext,
			transformBufferSize,
			{.STORAGE_BUFFER},
			{.DEVICE_LOCAL},
			&scene.transformBuffers[i].buffer,
			&scene.transformBuffers[i].memory,
		)
	}
	createShadowImage(graphicsContext, sceneIndex)
	return
}

// ATM we cant have a truly "empty" scene as we have to make buffers and images that must exist.
// It might be possible to make the buffers optional to solve this?
@(private = "file")
createNewScene :: proc(using graphicsContext: ^GraphicsContext) {
	index := u32(len(scenes))

	scene: Scene

	scene.filePath = ""
	scene.name = strings.clone_to_cstring("New Scene")
	scene.clearColour = {150, 150, 150, 255}
	scene.ambientLight = 0.01

	scene.instances = make([dynamic]Instance, 1)
	scene.instances[0] = {
		name      = strings.clone_to_cstring("cube"),
		modelID   = 0,
		textureID = 0,
		normalID  = 0,
		position  = {0, 0, 0},
		rotation  = {0, 0, 0},
		scale     = {0.2, 0.2, 0.2},
	}

	scene.pointLights = make([dynamic]PointLight, 1)
	scene.pointLights[0] = {
		name            = strings.clone_to_cstring("white light"),
		position        = {0, 2, 0},
		colourIntensity = {0.4, 0.4, 0.4},
		rotationAngle   = 0,
		rotationAxis    = {0, 1, 0},
	}

	scene.cameras = make([dynamic]Camera, 1)
	scene.cameras[0] = {
		name     = strings.clone_to_cstring("main"),
		eye      = {0.0, 0.2, -0.4},
		center   = {0.0, 0.0, 0.0},
		up       = {0.0, 1.0, 0.0},
		distance = 1.0,
		fov      = 45.0,
		mode     = .PERSPECTIVE,
	}
	scene.activeCamera = 0

	scene.modelPaths = make([dynamic]cstring, 1)
	scene.modelPaths[0] = strings.clone_to_cstring("./assets/models/cube/cube.fbx")

	scene.models = make([dynamic]Model)

	scene.texturePaths = make([dynamic]cstring, 1)
	scene.texturePaths[0] = strings.clone_to_cstring("./assets/textures/missing_texture.jpg")
	scene.textureCount = 1

	scene.normalPaths = make([dynamic]cstring, 1)
	scene.normalPaths[0] = strings.clone_to_cstring("./assets/textures/normal.jpg")
	scene.normalCount = 1

	scene.vertices = make([dynamic]Vertex)
	scene.indices = make([dynamic]u32)

	append(&scenes, scene)

	loadSceneAssets(graphicsContext, index)
}

@(private = "file")
InstanceJSON :: struct {
	name:     cstring,
	model:    i32,
	texture:  i32,
	normal:   i32,
	position: Vec3,
	rotation: Vec3,
	scale:    Vec3,
}

@(private = "file")
SceneJSON :: struct {
	name:          cstring,
	clear_colour:  [4]i32,
	ambient_light: f32,
	cameras:       []Camera,
	lights:        []PointLight,
	models:        []cstring,
	textures:      []cstring,
	normals:       []cstring,
	instances:     []InstanceJSON,
}

@(private = "file")
saveScene :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[sceneIndex]

	sceneInfo: SceneJSON = {
		name          = scene.name,
		clear_colour  = scene.clearColour,
		ambient_light = scene.ambientLight,
		cameras       = scene.cameras[:],
		lights        = scene.pointLights[:],
		models        = scene.modelPaths[1:],
		textures      = scene.texturePaths[1:],
		normals       = scene.normalPaths[1:],
		instances     = make([]InstanceJSON, len(scene.instances)),
	}
	defer delete(sceneInfo.instances)

	for &instance, index in scene.instances {
		sceneInfo.instances[index] = {
			name     = instance.name,
			model    = i32(instance.modelID) - 1,
			texture  = i32(instance.textureID) - 1,
			normal   = i32(instance.normalID) - 1,
			position = instance.position,
			rotation = instance.rotation,
			scale    = instance.scale,
		}
	}

	json_data, err := json.marshal(sceneInfo, {pretty = true})
	if err != nil {
		panic("Couldn't marshal data")
	}
	defer delete(json_data)

	werr := os.write_entire_file_or_err(scene.filePath, json_data)
	if werr != nil {
		panic("Couldn't write file")
	}
}

loadScene :: proc(
	using graphicsContext: ^GraphicsContext,
	sceneFile: string,
) -> (
	index: u32,
	err: LoadSceneError = .None,
) {
	index = u32(len(scenes))

	data, rerr := os.read_entire_file_or_err(sceneFile)
	if rerr != nil {
		return 0, .FailedToLoadSceneFile
	}
	defer delete(data)

	sceneJson: SceneJSON
	merr := json.unmarshal(data, &sceneJson)
	if merr != nil {
		return 0, .FailedToParseJson
	}

	scene: Scene = {
		name         = sceneJson.name,
		filePath     = sceneFile,
		clearColour  = sceneJson.clear_colour,
		ambientLight = sceneJson.ambient_light,
		instances    = make([dynamic]Instance, len(sceneJson.instances)),
		pointLights  = make([dynamic]PointLight),
		cameras      = make([dynamic]Camera),
		modelPaths   = make([dynamic]cstring),
		models       = make([dynamic]Model),
		texturePaths = make([dynamic]cstring),
		normalPaths  = make([dynamic]cstring),
		vertices     = make([dynamic]Vertex),
		indices      = make([dynamic]u32),
	}

	for &instance, instanceIndex in sceneJson.instances {
		scene.instances[instanceIndex] = {
			name      = instance.name,
			modelID   = u32(instance.model + 1),
			textureID = u32(instance.texture + 1),
			normalID  = u32(instance.normal + 1),
			position  = instance.position,
			rotation  = instance.rotation,
			scale     = instance.scale,
		}
	}

	append(&scene.modelPaths, strings.clone_to_cstring("./assets/models/cube/cube.fbx"))
	append(&scene.texturePaths, strings.clone_to_cstring("./assets/textures/missing_texture.jpg"))
	append(&scene.normalPaths, strings.clone_to_cstring("./assets/textures/normal.jpg"))

	append(&scene.pointLights, ..sceneJson.lights)
	append(&scene.cameras, ..sceneJson.cameras)
	append(&scene.modelPaths, ..sceneJson.models)
	append(&scene.texturePaths, ..sceneJson.textures)
	append(&scene.normalPaths, ..sceneJson.normals)
	append(&scenes, scene)

	delete(sceneJson.lights)
	delete(sceneJson.cameras)
	delete(sceneJson.models)
	delete(sceneJson.textures)
	delete(sceneJson.normals)
	delete(sceneJson.instances)

	if err = loadSceneAssets(graphicsContext, index); err != .None {
		// TODO: This error should just be info not crashing. Should handle files not existing by using a replacement texture/model?
		panic("Load error")
	}
	return
}

closeScene :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	if vk.DeviceWaitIdle(device) != .SUCCESS {
		panic("Failed to wait for device idle?")
	}

	cleanupScene(graphicsContext, sceneIndex)
	if len(scenes) == 0 {
		createNewScene(graphicsContext)
	}
}

setActiveScene :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	paused = true

	if res := vk.DeviceWaitIdle(device); res != .SUCCESS {
		panic("Failed to wait for device idle!")
	}

	activeScene = sceneIndex
	updateSceneDescriptorSets(graphicsContext, sceneIndex)
}

@(private = "file")
cleanupScene :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := scenes[sceneIndex]

	cleanupBuffer(graphicsContext, &scene.indexBuffer)
	cleanupBuffer(graphicsContext, &scene.vertexBuffer)

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		cleanupBuffer(graphicsContext, &scene.instanceBuffers[index])
		cleanupBuffer(graphicsContext, &scene.boneBuffers[index])
		cleanupBuffer(graphicsContext, &scene.lightBuffers[index])
		cleanupBuffer(graphicsContext, &scene.transformBuffers[index])
	}

	cleanupImage(graphicsContext, &scene.textures)
	cleanupImage(graphicsContext, &scene.normals)
	cleanupImage(graphicsContext, &scene.shadowImages)

	for &texturePath in scene.texturePaths {
		delete(texturePath)
	}
	delete(scene.texturePaths)

	for &normalPath in scene.normalPaths {
		delete(normalPath)
	}
	delete(scene.normalPaths)

	for &model in scene.models {
		delete(model.name)
		delete(model.vertices)
		delete(model.indices)
		delete(model.skeleton)
		for &animation in model.animations {
			for &node in animation.nodes {
				delete(node.keyPositions)
				delete(node.keyRotations)
				delete(node.keyScales)
			}
			delete(animation.name)
			delete(animation.nodes)
		}
		delete(model.animations)
	}
	delete(scene.vertices)
	delete(scene.indices)
	delete(scene.models)

	for &modelPath in scene.modelPaths {
		delete(modelPath)
	}
	delete(scene.modelPaths)

	for &instance in scene.instances {
		delete(instance.name)
		delete(instance.scaleKeys)
		delete(instance.positionKeys)
		delete(instance.rotationKeys)
	}
	delete(scene.instances)

	for &light in scene.pointLights {
		delete(light.name)
	}
	delete(scene.pointLights)

	for &camera in scene.cameras {
		delete(camera.name)
	}
	delete(scene.cameras)
	delete(scene.name)

	unordered_remove(&scenes, sceneIndex)
}


// ###################################################################
// #                        Shader Descriptors                       #
// ###################################################################


@(private = "file")
createGraphicsDescriptorSets :: proc(using graphicsContext: ^GraphicsContext) {
	// SHADOW
	{
		layoutBindings: []vk.DescriptorSetLayoutBinding = {
			{
				binding = 0,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.VERTEX},
				pImmutableSamplers = nil,
			},
			{
				binding = 1,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.VERTEX},
				pImmutableSamplers = nil,
			},
			{
				binding = 2,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.VERTEX},
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

		if vk.CreateDescriptorSetLayout(
			   device,
			   &layoutInfo,
			   nil,
			   &pipelines[PipelineIndex.LIGHT].descriptorSetLayout,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create descriptor set layout!")
			panic("Failed to create descriptor set layout!")
		}

		poolSizes: []vk.DescriptorPoolSize = {{type = .STORAGE_BUFFER, descriptorCount = 4}}

		poolInfo: vk.DescriptorPoolCreateInfo = {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			pNext         = nil,
			flags         = {},
			maxSets       = MAX_FRAMES_IN_FLIGHT,
			poolSizeCount = u32(len(poolSizes)),
			pPoolSizes    = raw_data(poolSizes),
		}

		if vk.CreateDescriptorPool(
			   device,
			   &poolInfo,
			   nil,
			   &pipelines[PipelineIndex.LIGHT].descriptorPool,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create descriptor pool!")
			panic("Failed to create descriptor pool!")
		}

		layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
		defer delete(layouts)

		for &layout in layouts {
			layout = pipelines[PipelineIndex.LIGHT].descriptorSetLayout
		}

		allocInfo: vk.DescriptorSetAllocateInfo = {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pNext              = nil,
			descriptorPool     = pipelines[PipelineIndex.LIGHT].descriptorPool,
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
			pSetLayouts        = raw_data(layouts),
		}

		if vk.AllocateDescriptorSets(
			   device,
			   &allocInfo,
			   raw_data(pipelines[PipelineIndex.LIGHT].descriptorSets[:]),
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to allocate descriptor sets!")
			panic("Failed to allocate descriptor sets!")
		}
	}

	// MAIN
	{
		layoutBindings: []vk.DescriptorSetLayoutBinding = {
			{
				binding = 0,
				descriptorType = .UNIFORM_BUFFER,
				descriptorCount = 1,
				stageFlags = {.VERTEX, .FRAGMENT},
				pImmutableSamplers = nil,
			},
			{
				binding = 1,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.VERTEX},
				pImmutableSamplers = nil,
			},
			{
				binding = 2,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.FRAGMENT},
				pImmutableSamplers = nil,
			},
			{
				binding = 3,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.VERTEX},
				pImmutableSamplers = nil,
			},
			{
				binding = 4,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				stageFlags = {.FRAGMENT},
				pImmutableSamplers = nil,
			},
			{
				binding = 5,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				stageFlags = {.FRAGMENT},
				pImmutableSamplers = nil,
			},
			{
				binding = 6,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				stageFlags = {.FRAGMENT},
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

		if vk.CreateDescriptorSetLayout(
			   device,
			   &layoutInfo,
			   nil,
			   &pipelines[PipelineIndex.MAIN].descriptorSetLayout,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create descriptor set layout!")
			panic("Failed to create descriptor set layout!")
		}

		poolSizes: []vk.DescriptorPoolSize = {
			{type = .UNIFORM_BUFFER, descriptorCount = 1},
			{type = .STORAGE_BUFFER, descriptorCount = 3},
			{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 3},
		}

		poolInfo: vk.DescriptorPoolCreateInfo = {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			pNext         = nil,
			flags         = {},
			maxSets       = MAX_FRAMES_IN_FLIGHT,
			poolSizeCount = u32(len(poolSizes)),
			pPoolSizes    = raw_data(poolSizes),
		}

		if vk.CreateDescriptorPool(
			   device,
			   &poolInfo,
			   nil,
			   &pipelines[PipelineIndex.MAIN].descriptorPool,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create descriptor pool!")
			panic("Failed to create descriptor pool!")
		}

		layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
		defer delete(layouts)

		for &layout in layouts {
			layout = pipelines[PipelineIndex.MAIN].descriptorSetLayout
		}

		allocInfo: vk.DescriptorSetAllocateInfo = {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pNext              = nil,
			descriptorPool     = pipelines[PipelineIndex.MAIN].descriptorPool,
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
			pSetLayouts        = raw_data(layouts),
		}

		if vk.AllocateDescriptorSets(
			   device,
			   &allocInfo,
			   raw_data(pipelines[PipelineIndex.MAIN].descriptorSets[:]),
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to allocate descriptor sets!")
			panic("Failed to allocate descriptor sets!")
		}
	}
}

@(private = "file")
updateGraphicsDescriptorSets :: proc(using graphicsContext: ^GraphicsContext) {
	// MAIN
	{
		uniformBufferInfo: vk.DescriptorBufferInfo = {
			offset = 0,
			range  = size_of(UniformBuffer),
		}

		for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
			uniformBufferInfo.buffer = uniformBuffers[index].buffer

			descriptorWrite: vk.WriteDescriptorSet = {
				sType            = .WRITE_DESCRIPTOR_SET,
				pNext            = nil,
				dstSet           = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding       = 0,
				dstArrayElement  = 0,
				descriptorCount  = 1,
				descriptorType   = .UNIFORM_BUFFER,
				pImageInfo       = nil,
				pBufferInfo      = &uniformBufferInfo,
				pTexelBufferView = nil,
			}

			vk.UpdateDescriptorSets(device, 1, &descriptorWrite, 0, nil)
		}
	}
}

@(private = "file")
createComputeDescriptorSets :: proc(using graphicsContext: ^GraphicsContext) {
	// PRECOMPUTE
	{
		layoutBindings: []vk.DescriptorSetLayoutBinding = {
			{
				binding = 0,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.COMPUTE},
				pImmutableSamplers = nil,
			},
			{
				binding = 1,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.COMPUTE},
				pImmutableSamplers = nil,
			},
			{
				binding = 2,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.COMPUTE},
				pImmutableSamplers = nil,
			},
			{
				binding = 3,
				descriptorType = .STORAGE_BUFFER,
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

		if vk.CreateDescriptorSetLayout(
			   device,
			   &layoutInfo,
			   nil,
			   &pipelines[PipelineIndex.PRECOMPUTE].descriptorSetLayout,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create compute descriptor set layout!")
			panic("Failed to create compute descriptor set layout!")
		}

		poolSizes: []vk.DescriptorPoolSize = {{type = .STORAGE_BUFFER, descriptorCount = 5}}

		poolInfo: vk.DescriptorPoolCreateInfo = {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			pNext         = nil,
			flags         = {},
			maxSets       = MAX_FRAMES_IN_FLIGHT,
			poolSizeCount = u32(len(poolSizes)),
			pPoolSizes    = raw_data(poolSizes),
		}

		if vk.CreateDescriptorPool(
			   device,
			   &poolInfo,
			   nil,
			   &pipelines[PipelineIndex.PRECOMPUTE].descriptorPool,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create descriptor pool!")
			panic("Failed to create descriptor pool!")
		}

		layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
		defer delete(layouts)
		for &layout in layouts {
			layout = pipelines[PipelineIndex.PRECOMPUTE].descriptorSetLayout
		}

		allocInfo: vk.DescriptorSetAllocateInfo = {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pNext              = nil,
			descriptorPool     = pipelines[PipelineIndex.PRECOMPUTE].descriptorPool,
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
			pSetLayouts        = raw_data(layouts),
		}

		if vk.AllocateDescriptorSets(
			   device,
			   &allocInfo,
			   raw_data(pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[:]),
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to allocate compute descriptor sets!")
			panic("Failed to allocate compute descriptor sets!")
		}
	}

	// POST PROCESSING
	{
		layoutBindings: []vk.DescriptorSetLayoutBinding = {
			{
				binding = 0,
				descriptorType = .STORAGE_IMAGE,
				descriptorCount = 1,
				stageFlags = {.COMPUTE},
				pImmutableSamplers = nil,
			},
			{
				binding = 1,
				descriptorType = .STORAGE_IMAGE,
				descriptorCount = 1,
				stageFlags = {.COMPUTE},
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
				descriptorType = .UNIFORM_BUFFER,
				descriptorCount = 1,
				stageFlags = {.COMPUTE},
				pImmutableSamplers = nil,
			},
			{
				binding = 4,
				descriptorType = .STORAGE_BUFFER,
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

		if vk.CreateDescriptorSetLayout(
			   device,
			   &layoutInfo,
			   nil,
			   &pipelines[PipelineIndex.POST].descriptorSetLayout,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create compute descriptor set layout!")
			panic("Failed to create compute descriptor set layout!")
		}

		poolSizes: []vk.DescriptorPoolSize = {
			{type = .STORAGE_IMAGE, descriptorCount = 2},
			{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1},
			{type = .UNIFORM_BUFFER, descriptorCount = 1},
			{type = .STORAGE_BUFFER, descriptorCount = 1},
		}

		poolInfo: vk.DescriptorPoolCreateInfo = {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			pNext         = nil,
			flags         = {},
			maxSets       = MAX_FRAMES_IN_FLIGHT,
			poolSizeCount = u32(len(poolSizes)),
			pPoolSizes    = raw_data(poolSizes),
		}

		if vk.CreateDescriptorPool(
			   device,
			   &poolInfo,
			   nil,
			   &pipelines[PipelineIndex.POST].descriptorPool,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to create descriptor pool!")
			panic("Failed to create descriptor pool!")
		}

		layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
		defer delete(layouts)
		for &layout in layouts {
			layout = pipelines[PipelineIndex.POST].descriptorSetLayout
		}

		allocInfo: vk.DescriptorSetAllocateInfo = {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pNext              = nil,
			descriptorPool     = pipelines[PipelineIndex.POST].descriptorPool,
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
			pSetLayouts        = raw_data(layouts),
		}

		if vk.AllocateDescriptorSets(
			   device,
			   &allocInfo,
			   raw_data(pipelines[PipelineIndex.POST].descriptorSets[:]),
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Failed to allocate compute descriptor sets!")
			panic("Failed to allocate compute descriptor sets!")
		}

		sceneDepth: vk.DescriptorImageInfo = {
			sampler     = samplers[pipelines[PipelineIndex.MAIN].depth.sampler],
			imageView   = pipelines[PipelineIndex.MAIN].depth.view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}

		for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
			descriptorWrite: vk.WriteDescriptorSet = {
				sType            = .WRITE_DESCRIPTOR_SET,
				pNext            = nil,
				dstSet           = pipelines[PipelineIndex.POST].descriptorSets[index],
				dstBinding       = 2,
				dstArrayElement  = 0,
				descriptorCount  = 1,
				descriptorType   = .COMBINED_IMAGE_SAMPLER,
				pImageInfo       = &sceneDepth,
				pBufferInfo      = nil,
				pTexelBufferView = nil,
			}

			vk.UpdateDescriptorSets(device, 1, &descriptorWrite, 0, nil)
		}
	}
}

@(private = "file")
updateComputeDescriptorSets :: proc(using graphicsContext: ^GraphicsContext) {
	// POST PROCESSING
	{
		inImage.format = .R16G16B16A16_SFLOAT
		createImage(
			graphicsContext,
			&inImage,
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

		inImage.view = createImageView(
			graphicsContext,
			inImage.vkImage,
			.D2,
			inImage.format,
			{.COLOR},
			1,
		)

		outImage.format = .R16G16B16A16_SFLOAT
		createImage(
			graphicsContext,
			&outImage,
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

		outImage.view = createImageView(
			graphicsContext,
			outImage.vkImage,
			.D2,
			outImage.format,
			{.COLOR},
			1,
		)

		inImageInfo: vk.DescriptorImageInfo = {
			sampler     = samplers[inImage.sampler],
			imageView   = inImage.view,
			imageLayout = .GENERAL,
		}

		outImageInfo: vk.DescriptorImageInfo = {
			sampler     = samplers[outImage.sampler],
			imageView   = outImage.view,
			imageLayout = .GENERAL,
		}

		sceneDepth: vk.DescriptorImageInfo = {
			sampler     = samplers[pipelines[PipelineIndex.MAIN].depth.sampler],
			imageView   = pipelines[PipelineIndex.MAIN].depth.view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}

		uniformBufferInfo: vk.DescriptorBufferInfo = {
			offset = 0,
			range  = size_of(UniformBuffer),
		}

		for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
			uniformBufferInfo.buffer = uniformBuffers[index].buffer

			descriptorWrite: []vk.WriteDescriptorSet = {
				{
					sType = .WRITE_DESCRIPTOR_SET,
					pNext = nil,
					dstSet = pipelines[PipelineIndex.POST].descriptorSets[index],
					dstBinding = 0,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .STORAGE_IMAGE,
					pImageInfo = &inImageInfo,
					pBufferInfo = nil,
					pTexelBufferView = nil,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					pNext = nil,
					dstSet = pipelines[PipelineIndex.POST].descriptorSets[index],
					dstBinding = 1,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .STORAGE_IMAGE,
					pImageInfo = &outImageInfo,
					pBufferInfo = nil,
					pTexelBufferView = nil,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					pNext = nil,
					dstSet = pipelines[PipelineIndex.POST].descriptorSets[index],
					dstBinding = 2,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					pImageInfo = &sceneDepth,
					pBufferInfo = nil,
					pTexelBufferView = nil,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					pNext = nil,
					dstSet = pipelines[PipelineIndex.POST].descriptorSets[index],
					dstBinding = 3,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .UNIFORM_BUFFER,
					pImageInfo = nil,
					pBufferInfo = &uniformBufferInfo,
					pTexelBufferView = nil,
				},
			}

			vk.UpdateDescriptorSets(
				device,
				u32(len(descriptorWrite)),
				raw_data(descriptorWrite),
				0,
				nil,
			)
		}
	}
}

@(private = "file")
updateSceneDescriptorSets :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[activeScene]

	vertexBufferInfo: vk.DescriptorBufferInfo = {
		buffer = scene.vertexBuffer.buffer,
		offset = 0,
		range  = vk.DeviceSize(size_of(Vertex) * len(scene.vertices)),
	}

	instanceBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(InstanceInfo) * len(scene.instances)),
	}

	boneBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(Mat4) * scene.boneCount),
	}

	lightsBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(LightData) * len(scene.pointLights)),
	}

	transformBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(size_of(Mat4) * scene.instanceVerticesCount),
	}

	textureImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[scene.textures.sampler],
		imageView   = scene.textures.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	normalImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[scene.normals.sampler],
		imageView   = scene.normals.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	shadowImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[scene.shadowImages.sampler],
		imageView   = scene.shadowImages.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		instanceBufferInfo.buffer = scene.instanceBuffers[index].buffer
		boneBufferInfo.buffer = scene.boneBuffers[index].buffer
		lightsBufferInfo.buffer = scene.lightBuffers[index].buffer
		transformBufferInfo.buffer = scene.transformBuffers[index].buffer

		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.LIGHT].descriptorSets[index],
				dstBinding = 0,
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
				dstSet = pipelines[PipelineIndex.LIGHT].descriptorSets[index],
				dstBinding = 1,
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
				dstSet = pipelines[PipelineIndex.LIGHT].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 1,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 3,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 4,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 5,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &normalImageInfo,
				pBufferInfo = nil,
				pTexelBufferView = nil,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 6,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 1,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 3,
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
				dstSet = pipelines[PipelineIndex.POST].descriptorSets[index],
				dstBinding = 4,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &lightsBufferInfo,
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
updateSceneInstanceBuffer :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[sceneIndex]

	instanceBufferSize := size_of(Instance) * len(scene.instances)
	instanceBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(instanceBufferSize),
	}

	boneBufferSize := size_of(Mat4) * scene.boneCount
	boneBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(boneBufferSize),
	}

	transformBufferSize := size_of(Mat4) * scene.instanceVerticesCount
	transformBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(transformBufferSize),
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		cleanupBuffer(graphicsContext, &scene.instanceBuffers[index])
		cleanupBuffer(graphicsContext, &scene.boneBuffers[index])
		cleanupBuffer(graphicsContext, &scene.transformBuffers[index])

		createBuffer(
			graphicsContext,
			instanceBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&scene.instanceBuffers[index].buffer,
			&scene.instanceBuffers[index].memory,
		)
		vk.MapMemory(
			device,
			scene.instanceBuffers[index].memory,
			0,
			vk.DeviceSize(instanceBufferSize),
			{},
			&scene.instanceBuffers[index].mapped,
		)

		createBuffer(
			graphicsContext,
			boneBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&scene.boneBuffers[index].buffer,
			&scene.boneBuffers[index].memory,
		)
		vk.MapMemory(
			device,
			scene.boneBuffers[index].memory,
			0,
			vk.DeviceSize(boneBufferSize),
			{},
			&scene.boneBuffers[index].mapped,
		)

		createBuffer(
			graphicsContext,
			transformBufferSize,
			{.STORAGE_BUFFER},
			{.DEVICE_LOCAL},
			&scene.transformBuffers[index].buffer,
			&scene.transformBuffers[index].memory,
		)

		instanceBufferInfo.buffer = scene.instanceBuffers[index].buffer
		boneBufferInfo.buffer = scene.boneBuffers[index].buffer
		transformBufferInfo.buffer = scene.transformBuffers[index].buffer

		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.LIGHT].descriptorSets[index],
				dstBinding = 0,
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
				dstSet = pipelines[PipelineIndex.LIGHT].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 1,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 3,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 1,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 3,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &transformBufferInfo,
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
updateSceneInstanceModel :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[sceneIndex]

	boneBufferSize := size_of(Mat4) * scene.boneCount
	boneBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(boneBufferSize),
	}

	transformBufferSize := size_of(Mat4) * scene.instanceVerticesCount
	transformBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(transformBufferSize),
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		cleanupBuffer(graphicsContext, &scene.boneBuffers[index])
		cleanupBuffer(graphicsContext, &scene.transformBuffers[index])

		createBuffer(
			graphicsContext,
			boneBufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&scene.boneBuffers[index].buffer,
			&scene.boneBuffers[index].memory,
		)
		vk.MapMemory(
			device,
			scene.boneBuffers[index].memory,
			0,
			vk.DeviceSize(boneBufferSize),
			{},
			&scene.boneBuffers[index].mapped,
		)

		createBuffer(
			graphicsContext,
			transformBufferSize,
			{.STORAGE_BUFFER},
			{.DEVICE_LOCAL},
			&scene.transformBuffers[index].buffer,
			&scene.transformBuffers[index].memory,
		)

		boneBufferInfo.buffer = scene.boneBuffers[index].buffer
		transformBufferInfo.buffer = scene.transformBuffers[index].buffer
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.LIGHT].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 3,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 3,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &transformBufferInfo,
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
updateSceneModels :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[sceneIndex]

	cleanupBuffer(graphicsContext, &scene.vertexBuffer)
	cleanupBuffer(graphicsContext, &scene.indexBuffer)

	loadBufferToGPU(
		graphicsContext,
		size_of(Vertex) * len(scene.vertices),
		raw_data(scene.vertices),
		&scene.vertexBuffer,
		.VERTEX_BUFFER,
	)
	loadBufferToGPU(
		graphicsContext,
		size_of(u32) * len(scene.indices),
		raw_data(scene.indices),
		&scene.indexBuffer,
		.INDEX_BUFFER,
	)

	vertexBufferInfo: vk.DescriptorBufferInfo = {
		buffer = scene.vertexBuffer.buffer,
		offset = 0,
		range  = vk.DeviceSize(size_of(Vertex) * len(scene.vertices)),
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[index],
				dstBinding = 0,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &vertexBufferInfo,
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
updateSceneTextures :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[sceneIndex]

	textureImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[scene.textures.sampler],
		imageView   = scene.textures.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 4,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &textureImageInfo,
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
updateSceneNormals :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[sceneIndex]

	normalImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[scene.normals.sampler],
		imageView   = scene.normals.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 5,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &normalImageInfo,
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
updateSceneLights :: proc(using graphicsContext: ^GraphicsContext, sceneIndex: u32) {
	scene := &scenes[sceneIndex]
	cleanupImage(graphicsContext, &scene.shadowImages)
	createShadowImage(graphicsContext, sceneIndex)

	shadowImageInfo: vk.DescriptorImageInfo = {
		sampler     = samplers[scene.shadowImages.sampler],
		imageView   = scene.shadowImages.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	bufferSize := size_of(LightData) * len(scene.pointLights)
	lightsBufferInfo: vk.DescriptorBufferInfo = {
		offset = 0,
		range  = vk.DeviceSize(bufferSize),
	}

	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		cleanupBuffer(graphicsContext, &scene.lightBuffers[index])

		createBuffer(
			graphicsContext,
			bufferSize,
			{.STORAGE_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&scene.lightBuffers[index].buffer,
			&scene.lightBuffers[index].memory,
		)
		vk.MapMemory(
			device,
			scene.lightBuffers[index].memory,
			0,
			vk.DeviceSize(bufferSize),
			{},
			&scene.lightBuffers[index].mapped,
		)

		lightsBufferInfo.buffer = scene.lightBuffers[index].buffer
		descriptorWrites: []vk.WriteDescriptorSet = {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				pNext = nil,
				dstSet = pipelines[PipelineIndex.LIGHT].descriptorSets[index],
				dstBinding = 1,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 2,
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
				dstSet = pipelines[PipelineIndex.MAIN].descriptorSets[index],
				dstBinding = 6,
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
				dstSet = pipelines[PipelineIndex.POST].descriptorSets[index],
				dstBinding = 4,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pImageInfo = nil,
				pBufferInfo = &lightsBufferInfo,
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


// ###################################################################
// #                         Frame Resources                         #
// ###################################################################


@(private = "file")
createSyncObjects :: proc(using graphicsContext: ^GraphicsContext) {
	inFlightFrames = make([]vk.Fence, MAX_FRAMES_IN_FLIGHT)
	precomputeFinished = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	rendersFinished = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	computeFinished = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	uiFinished = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	imagesAvailable = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)

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
		result :=
			vk.CreateFence(device, &fenceInfo, nil, &inFlightFrames[index]) |
			vk.CreateSemaphore(device, &semaphoreInfo, nil, &precomputeFinished[index]) |
			vk.CreateSemaphore(device, &semaphoreInfo, nil, &rendersFinished[index]) |
			vk.CreateSemaphore(device, &semaphoreInfo, nil, &computeFinished[index]) |
			vk.CreateSemaphore(device, &semaphoreInfo, nil, &uiFinished[index]) |
			vk.CreateSemaphore(device, &semaphoreInfo, nil, &imagesAvailable[index])
		if result != .SUCCESS {
			log.log(.Error, "Failed to create sync objects!")
			panic("Failed to create sync objects!")
		}
	}
}


// ###################################################################
// #                             Pipeline                            #
// ###################################################################


@(private = "file")
findSupportedDepthFormat :: proc(
	using graphicsContext: ^GraphicsContext,
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
	log.log(.Error, "Failed to find supported format!")
	panic("Failed to find supported format!")
}

@(private = "file")
createRenderPass :: proc(using graphicsContext: ^GraphicsContext) {
	// SHADOW
	{
		pipelines[PipelineIndex.LIGHT].colour.format = .R32_SFLOAT

		createImage(
			graphicsContext,
			&pipelines[PipelineIndex.LIGHT].colour,
			{.CUBE_COMPATIBLE},
			.D2,
			u32(SHADOW_RESOLUTION.x),
			u32(SHADOW_RESOLUTION.y),
			6,
			{._1},
			.OPTIMAL,
			{.COLOR_ATTACHMENT, .TRANSFER_SRC},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		)

		pipelines[PipelineIndex.LIGHT].colour.view = createImageView(
			graphicsContext,
			pipelines[PipelineIndex.LIGHT].colour.vkImage,
			.D2_ARRAY,
			pipelines[PipelineIndex.LIGHT].colour.format,
			{.COLOR},
			6,
		)

		pipelines[PipelineIndex.LIGHT].depth.format = findSupportedDepthFormat(
			graphicsContext,
			{.D16_UNORM, .D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
			.OPTIMAL,
			{.DEPTH_STENCIL_ATTACHMENT},
		)

		createImage(
			graphicsContext,
			&pipelines[PipelineIndex.LIGHT].depth,
			{.CUBE_COMPATIBLE},
			.D2,
			u32(SHADOW_RESOLUTION.x),
			u32(SHADOW_RESOLUTION.y),
			6,
			{._1},
			.OPTIMAL,
			{.DEPTH_STENCIL_ATTACHMENT},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		)

		pipelines[PipelineIndex.LIGHT].depth.view = createImageView(
			graphicsContext,
			pipelines[PipelineIndex.LIGHT].depth.vkImage,
			.D2_ARRAY,
			pipelines[PipelineIndex.LIGHT].depth.format,
			{.DEPTH},
			6,
		)

		colourAttachment: vk.AttachmentDescription = {
			flags          = {},
			format         = pipelines[PipelineIndex.LIGHT].colour.format,
			samples        = {._1},
			loadOp         = .CLEAR,
			storeOp        = .STORE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .UNDEFINED,
			finalLayout    = .TRANSFER_SRC_OPTIMAL,
		}

		depthAttachment: vk.AttachmentDescription = {
			flags          = {},
			format         = pipelines[PipelineIndex.LIGHT].depth.format,
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

		dependencies: []vk.SubpassDependency = {
			{
				srcSubpass = vk.SUBPASS_EXTERNAL,
				dstSubpass = 0,
				srcStageMask = {.FRAGMENT_SHADER},
				dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
				srcAccessMask = {.SHADER_READ},
				dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
				dependencyFlags = {.BY_REGION},
			},
			{
				srcSubpass = 0,
				dstSubpass = vk.SUBPASS_EXTERNAL,
				srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
				dstStageMask = {.FRAGMENT_SHADER},
				srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
				dstAccessMask = {.SHADER_READ},
				dependencyFlags = {.BY_REGION},
			},
		}

		viewmask: u32 = 0b00111111
		multiview: vk.RenderPassMultiviewCreateInfo = {
			sType = .RENDER_PASS_MULTIVIEW_CREATE_INFO,
			pNext = nil,
			subpassCount = 1,
			pViewMasks = &viewmask,
			dependencyCount = 0,
			pViewOffsets = nil,
			correlationMaskCount = 1,
			pCorrelationMasks = &viewmask,
		}

		renderPassInfo: vk.RenderPassCreateInfo = {
			sType           = .RENDER_PASS_CREATE_INFO,
			pNext           = &multiview,
			flags           = {},
			attachmentCount = 2,
			pAttachments    = raw_data(
				[]vk.AttachmentDescription{colourAttachment, depthAttachment},
			),
			subpassCount    = 1,
			pSubpasses      = &subpass,
			dependencyCount = u32(len(dependencies)),
			pDependencies   = raw_data(dependencies),
		}

		if vk.CreateRenderPass(
			   device,
			   &renderPassInfo,
			   nil,
			   &pipelines[PipelineIndex.LIGHT].renderPass,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Unable to create render pass!")
			panic("Unable to create render pass!")
		}
	}

	// MAIN
	{
		pipelines[PipelineIndex.MAIN].colour.format = .R16G16B16A16_SFLOAT

		createImage(
			graphicsContext,
			&pipelines[PipelineIndex.MAIN].colour,
			{},
			.D2,
			u32(RENDER_SIZE.x),
			u32(RENDER_SIZE.y),
			1,
			{._1},
			.OPTIMAL,
			{.COLOR_ATTACHMENT, .TRANSFER_SRC},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		)

		pipelines[PipelineIndex.MAIN].colour.view = createImageView(
			graphicsContext,
			pipelines[PipelineIndex.MAIN].colour.vkImage,
			.D2,
			pipelines[PipelineIndex.MAIN].colour.format,
			{.COLOR},
			1,
		)

		pipelines[PipelineIndex.MAIN].depth.format = findSupportedDepthFormat(
			graphicsContext,
			{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
			.OPTIMAL,
			{.DEPTH_STENCIL_ATTACHMENT},
		)

		createImage(
			graphicsContext,
			&pipelines[PipelineIndex.MAIN].depth,
			{},
			.D2,
			u32(RENDER_SIZE.x),
			u32(RENDER_SIZE.y),
			1,
			{._1},
			.OPTIMAL,
			{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		)

		pipelines[PipelineIndex.MAIN].depth.view = createImageView(
			graphicsContext,
			pipelines[PipelineIndex.MAIN].depth.vkImage,
			.D2,
			pipelines[PipelineIndex.MAIN].depth.format,
			{.DEPTH},
			1,
		)

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

		if vk.CreateRenderPass(
			   device,
			   &renderPassInfo,
			   nil,
			   &pipelines[PipelineIndex.MAIN].renderPass,
		   ) !=
		   .SUCCESS {
			log.log(.Error, "Unable to create render pass!")
			panic("Unable to create render pass!")
		}
	}
}

@(private = "file")
createFramebuffers :: proc(using graphicsContext: ^GraphicsContext) {
	// SHADOW
	{
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
			width           = u32(SHADOW_RESOLUTION.x),
			height          = u32(SHADOW_RESOLUTION.y),
			layers          = 1,
		}

		pipelines[PipelineIndex.LIGHT].frameBuffers = make(
			[]vk.Framebuffer,
			len(swapchainImageViews),
		)

		for index in 0 ..< len(swapchainImageViews) {
			if vk.CreateFramebuffer(
				   device,
				   &frameBufferInfo,
				   nil,
				   &pipelines[PipelineIndex.LIGHT].frameBuffers[index],
			   ) !=
			   .SUCCESS {
				log.log(.Error, "Failed to create frame buffer!")
				panic("Failed to create frame buffer!")
			}
		}
	}

	// MAIN
	{
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
			width           = u32(RENDER_SIZE.x),
			height          = u32(RENDER_SIZE.y),
			layers          = 1,
		}

		pipelines[PipelineIndex.MAIN].frameBuffers = make(
			[]vk.Framebuffer,
			len(swapchainImageViews),
		)
		for index in 0 ..< len(swapchainImageViews) {
			if vk.CreateFramebuffer(
				   device,
				   &frameBufferInfo,
				   nil,
				   &pipelines[PipelineIndex.MAIN].frameBuffers[index],
			   ) !=
			   .SUCCESS {
				log.log(.Error, "Failed to create frame buffer!")
				panic("Failed to create frame buffer!")
			}
		}
	}
}

@(private = "file")
createShaderModule :: proc(
	using graphicsContext: ^GraphicsContext,
	filename: string,
) -> (
	shaderModule: vk.ShaderModule,
) {
	loadShaderFile :: proc(filepath: string) -> (data: []byte) {
		fileHandle, err := os.open(filepath, mode = (os.O_RDONLY | os.O_APPEND))
		if err != 0 {
			log.log(.Error, "Shader file couldn't be opened!")
			panic("Shader file couldn't be opened!")
		}
		defer os.close(fileHandle)
		success: bool
		if data, success = os.read_entire_file_from_handle(fileHandle); !success {
			log.log(.Error, "Shader file couldn't be read!")
			panic("Shader file couldn't be read!")
		}
		return
	}

	code := loadShaderFile(filename)
	createInfo: vk.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		pNext    = nil,
		flags    = {},
		codeSize = len(code),
		pCode    = (^u32)(raw_data(code)),
	}
	if vk.CreateShaderModule(device, &createInfo, nil, &shaderModule) != .SUCCESS {
		log.log(.Error, "Failed to create shader module")
		panic("Failed to create shader module")
	}
	delete(code)
	return
}

@(private = "file")
createGraphicsPipelines :: proc(
	using graphicsContext: ^GraphicsContext,
	pipelineCache: vk.PipelineCache = 0,
) {
	pipelineCount: u32 : 2
	pipelineInfos := make([]vk.GraphicsPipelineCreateInfo, pipelineCount)
	defer delete(pipelineInfos)

	vertexBindingDescription := vertexBindingDescription

	// SHADOW PIPELINE
	shadowPushConstants: vk.PushConstantRange = {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = 2 * size_of(u32),
	}

	shadowPipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = 1,
		pSetLayouts            = &pipelines[PipelineIndex.LIGHT].descriptorSetLayout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &shadowPushConstants,
	}

	if vk.CreatePipelineLayout(
		   device,
		   &shadowPipelineLayoutInfo,
		   nil,
		   &pipelines[PipelineIndex.LIGHT].layout,
	   ) !=
	   .SUCCESS {
		log.log(.Error, "Failed to create pipeline layout!")
		panic("Failed to create pipeline layout!")
	}

	shadowShaderStages := [?]vk.ShaderStageFlag{.VERTEX, .FRAGMENT}
	shadowShaderFiles := [?]string {
		"./assets/shaders/light.vert.spv",
		"./assets/shaders/light.frag.spv",
	}

	shadowShaderStagesInfo := make([]vk.PipelineShaderStageCreateInfo, len(shadowShaderFiles))
	for path, index in shadowShaderFiles {
		shadowShaderStagesInfo[index] = {
			sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext               = nil,
			flags               = {},
			stage               = {shadowShaderStages[index]},
			module              = createShaderModule(graphicsContext, path),
			pName               = "main",
			pSpecializationInfo = nil,
		}
	}
	defer {
		for stage in shadowShaderStagesInfo {
			vk.DestroyShaderModule(device, stage.module, nil)
		}
		delete(shadowShaderStagesInfo)
	}

	pipelineInfos[0] = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
		stageCount          = u32(len(shadowShaderStagesInfo)),
		pStages             = raw_data(shadowShaderStagesInfo),
		pVertexInputState   = &{
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			vertexBindingDescriptionCount = 1,
			pVertexBindingDescriptions = &vertexBindingDescription,
			vertexAttributeDescriptionCount = u32(len(vertexInputAttributeDescriptions)),
			pVertexAttributeDescriptions = raw_data(vertexInputAttributeDescriptions),
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
				width = SHADOW_RESOLUTION.x,
				height = SHADOW_RESOLUTION.y,
				minDepth = 0,
				maxDepth = 1,
			},
			scissorCount = 1,
			pScissors = &vk.Rect2D {
				offset = {0, 0},
				extent = {u32(SHADOW_RESOLUTION.x), u32(SHADOW_RESOLUTION.y)},
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
			frontFace = .CLOCKWISE,
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
		size       = size_of(u32) + size_of(f32),
	}

	mainPipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = 1,
		pSetLayouts            = &pipelines[PipelineIndex.MAIN].descriptorSetLayout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &mainPushConstant,
	}

	if vk.CreatePipelineLayout(
		   device,
		   &mainPipelineLayoutInfo,
		   nil,
		   &pipelines[PipelineIndex.MAIN].layout,
	   ) !=
	   .SUCCESS {
		log.log(.Error, "Failed to create pipeline layout!")
		panic("Failed to create pipeline layout!")
	}

	mainShaderStages := [?]vk.ShaderStageFlag{.VERTEX, .FRAGMENT}
	mainShaderFiles := [?]string {
		"./assets/shaders/main.vert.spv",
		"./assets/shaders/main.frag.spv",
	}

	mainShaderStagesInfo := make([]vk.PipelineShaderStageCreateInfo, len(mainShaderFiles))
	for path, index in mainShaderFiles {
		mainShaderStagesInfo[index] = {
			sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext               = nil,
			flags               = {},
			stage               = {mainShaderStages[index]},
			module              = createShaderModule(graphicsContext, path),
			pName               = "main",
			pSpecializationInfo = nil,
		}
	}
	defer {
		for stage in mainShaderStagesInfo {
			vk.DestroyShaderModule(device, stage.module, nil)
		}
		delete(mainShaderStagesInfo)
	}

	pipelineInfos[1] = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
		stageCount          = u32(len(mainShaderStagesInfo)),
		pStages             = raw_data(mainShaderStagesInfo),
		pVertexInputState   = &{
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			pNext = nil,
			flags = {},
			vertexBindingDescriptionCount = 1,
			pVertexBindingDescriptions = &vertexBindingDescription,
			vertexAttributeDescriptionCount = u32(len(vertexInputAttributeDescriptions)),
			pVertexAttributeDescriptions = raw_data(vertexInputAttributeDescriptions),
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
				width = RENDER_SIZE.x,
				height = RENDER_SIZE.y,
				minDepth = 0,
				maxDepth = 1,
			},
			scissorCount = 1,
			pScissors = &vk.Rect2D {
				offset = {0, 0},
				extent = {u32(RENDER_SIZE.x), u32(RENDER_SIZE.y)},
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

	vkPipelines := make([]vk.Pipeline, pipelineCount)
	defer delete(vkPipelines)
	if vk.CreateGraphicsPipelines(
		   device,
		   pipelineCache,
		   pipelineCount,
		   raw_data(pipelineInfos),
		   nil,
		   raw_data(vkPipelines),
	   ) !=
	   .SUCCESS {
		log.log(.Error, "Failed to create pipeline!")
		panic("Failed to create pipeline!")
	}

	for pipeline, i in vkPipelines {
		pipelines[i].pipeline = pipeline
	}
}

@(private = "file")
createComputePipelines :: proc(
	using graphicsContext: ^GraphicsContext,
	pipelineCache: vk.PipelineCache = 0,
) {
	pipelineCount: u32 : 2
	pipelineInfos := make([]vk.ComputePipelineCreateInfo, pipelineCount)
	defer delete(pipelineInfos)

	// PRE COMPUTE
	precomputePushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = 4 * size_of(u32),
	}

	precomputePipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = 1,
		pSetLayouts            = &pipelines[PipelineIndex.PRECOMPUTE].descriptorSetLayout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &precomputePushConstants,
	}

	if vk.CreatePipelineLayout(
		   device,
		   &precomputePipelineLayoutInfo,
		   nil,
		   &pipelines[PipelineIndex.PRECOMPUTE].layout,
	   ) !=
	   .SUCCESS {
		log.log(.Error, "Failed to create postprocess pipeline layout!")
		panic("Failed to create postprocess pipeline layout!")
	}

	precomputeShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
		stage               = {.COMPUTE},
		module              = createShaderModule(graphicsContext, "./assets/shaders/pre.comp.spv"),
		pName               = "main",
		pSpecializationInfo = nil,
	}
	defer vk.DestroyShaderModule(device, precomputeShaderStageInfo.module, nil)

	pipelineInfos[0] = {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = nil,
		flags              = {},
		stage              = precomputeShaderStageInfo,
		layout             = pipelines[PipelineIndex.PRECOMPUTE].layout,
		basePipelineHandle = {},
		basePipelineIndex  = 0,
	}

	// POST PROCESSING
	postPushConstants: vk.PushConstantRange = {
		stageFlags = {.COMPUTE},
		offset     = 0,
		size       = 6 * size_of(f32),
	}

	postPipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = 1,
		pSetLayouts            = &pipelines[PipelineIndex.POST].descriptorSetLayout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &postPushConstants,
	}

	if vk.CreatePipelineLayout(
		   device,
		   &postPipelineLayoutInfo,
		   nil,
		   &pipelines[PipelineIndex.POST].layout,
	   ) !=
	   .SUCCESS {
		log.log(.Error, "Failed to create postprocess pipeline layout!")
		panic("Failed to create postprocess pipeline layout!")
	}

	postShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		pNext               = nil,
		flags               = {},
		stage               = {.COMPUTE},
		module              = createShaderModule(
			graphicsContext,
			"./assets/shaders/post.comp.spv",
		),
		pName               = "main",
		pSpecializationInfo = nil,
	}
	defer vk.DestroyShaderModule(device, postShaderStageInfo.module, nil)

	pipelineInfos[1] = {
		sType              = .COMPUTE_PIPELINE_CREATE_INFO,
		pNext              = nil,
		flags              = {},
		stage              = postShaderStageInfo,
		layout             = pipelines[PipelineIndex.POST].layout,
		basePipelineHandle = {},
		basePipelineIndex  = 0,
	}

	vkPipelines := make([]vk.Pipeline, pipelineCount)
	defer delete(vkPipelines)
	if vk.CreateComputePipelines(
		   device,
		   pipelineCache,
		   pipelineCount,
		   raw_data(pipelineInfos),
		   nil,
		   raw_data(vkPipelines),
	   ) !=
	   .SUCCESS {
		log.log(.Error, "Failed to create pipeline!")
		panic("Failed to create pipeline!")
	}

	for pipeline, i in vkPipelines {
		pipelines[i + 2].pipeline = pipeline
	}
}


// ###################################################################
// #                              Imgui                              #
// ###################################################################


@(private = "file")
initImgui :: proc(using graphicsContext: ^GraphicsContext) {
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

	if vk.CreateDescriptorPool(
		   device,
		   &descriptorPoolCreateInfo,
		   nil,
		   &imguiData.descriptorPool,
	   ) !=
	   .SUCCESS {
		log.log(.Fatal, "Failed to create imgui descriptor pool!")
		panic("Failed to create imgui descriptor pool!")
	}
}

@(private = "file")
updateImgui :: proc(using graphicsContext: ^GraphicsContext) {
	ImFDCreateImage: ImFD.CreateTexture : proc "system" (
		data: ^c.uint8_t,
		width, height: c.int,
		format: c.char,
	) -> rawptr {
		context = runtime.default_context()
		using graphicsContext := engineState.graphicsContext

		imageData: ImFDImageData
		imageData.format = .B8G8R8A8_SRGB if format == 0 else .R8G8B8A8_SRGB
		createImage(
			graphicsContext,
			&imageData.image,
			{},
			.D2,
			u32(width),
			u32(height),
			1,
			{._1},
			.OPTIMAL,
			{.TRANSFER_DST, .SAMPLED},
			{.DEVICE_LOCAL},
			.EXCLUSIVE,
			0,
			nil,
		)

		imageData.view = createImageView(
			graphicsContext,
			imageData.vkImage,
			.D2,
			imageData.format,
			{.COLOR},
			1,
		)

		imageData.sampler = 0

		imageData.descriptorSet = implVulkan.AddTexture(
			samplers[imageData.image.sampler],
			imageData.image.view,
			.SHADER_READ_ONLY_OPTIMAL,
		)

		textureSize := int(width * height * 4)
		stagingBuffer: Buffer
		createBuffer(
			graphicsContext,
			textureSize,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&stagingBuffer.buffer,
			&stagingBuffer.memory,
		)
		defer {
			cleanupBuffer(graphicsContext, &stagingBuffer)
		}

		bufferData: rawptr
		vk.MapMemory(device, stagingBuffer.memory, 0, vk.DeviceSize(textureSize), {}, &bufferData)
		mem.copy(bufferData, data, textureSize)
		vk.UnmapMemory(device, stagingBuffer.memory)

		commandBuffer := beginSingleTimeCommands(graphicsContext, graphicsCommandPool)
		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			imageData.image.vkImage,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		copyBufferToImage(
			graphicsContext,
			commandBuffer,
			stagingBuffer.buffer,
			imageData.image.vkImage,
			u32(width),
			u32(height),
		)

		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			imageData.image.vkImage,
			.TRANSFER_DST_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			{.COLOR},
			1,
		)
		endSingleTimeCommands(graphicsContext, commandBuffer, graphicsCommandPool)

		append(&imguiData.imfdImages, imageData)

		return (rawptr)((uintptr)(imageData.descriptorSet))
	}

	ImFDDeleteImage: ImFD.DeleteTexture : proc "system" (descriptorPtr: rawptr) {}

	imguiData.uiContext = imgui.CreateContext()
	io := imgui.GetIO()
	when !ODIN_DEBUG {
		io.ConfigDebugHighlightIdConflicts = false
	}
	imgui.StyleColorsClassic()

	implVulkan.LoadFunctions(
		proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr((vk.Instance)(user_data), function_name)
		},
		instance,
	)

	if !implGLFW.InitForVulkan(window, true) {
		log.log(.Fatal, "Failed to initialize imgui for vulkan, quitting application.")
		return
	}

	// RenderPass
	{
		imguiData.colour.format = .R16G16B16A16_SFLOAT

		createImage(
			graphicsContext,
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

		imguiData.colour.view = createImageView(
			graphicsContext,
			imguiData.colour.vkImage,
			.D2,
			imguiData.colour.format,
			{.COLOR},
			1,
		)

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

		if vk.CreateRenderPass(device, &renderPassInfo, nil, &imguiData.renderPass) != .SUCCESS {
			log.log(.Error, "Unable to create render pass!")
			panic("Unable to create render pass!")
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

		imguiData.frameBuffers = make([]vk.Framebuffer, len(swapchainImageViews))
		for index in 0 ..< len(swapchainImageViews) {
			if vk.CreateFramebuffer(
				   device,
				   &frameBufferInfo,
				   nil,
				   &imguiData.frameBuffers[index],
			   ) !=
			   .SUCCESS {
				log.log(.Error, "Failed to create frame buffer!")
				panic("Failed to create frame buffer!")
			}
		}
	}

	implInitInfo: implVulkan.InitInfo = {
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
		MinAllocationSize           = 1024 * 1024, // Minimum allocation size. Set to 1024*1024 to satisfy zealous best practices validation layer and waste a little memory.
	}

	if !implVulkan.Init(&implInitInfo) {
		log.log(.Fatal, "Failed to init vulkan impl.")
		panic("Failed to init vulkan impl.")
	}

	ImFD.Init(ImFDCreateImage, ImFDDeleteImage)
	imguiData.imfdImages = make([dynamic]ImFDImageData)
}

@(private = "file")
cleanupImgui :: proc(using graphicsContext: ^GraphicsContext) {
	// This should probably be in ImFDDeleteImage but that causes issues so this is the best solution I have at the moment
	for &imageData, index in imguiData.imfdImages {
		cleanupImage(graphicsContext, &imageData.image)
		implVulkan.RemoveTexture(imageData.descriptorSet)
	}
	delete(imguiData.imfdImages)
	// ------------------------------------------------------------

	ImFD.Shutdown()
	implVulkan.Shutdown()
	implGLFW.Shutdown()
	imgui.DestroyContext(imguiData.uiContext)

	for &frameBuffer in imguiData.frameBuffers {
		vk.DestroyFramebuffer(device, frameBuffer, nil)
	}
	delete(imguiData.frameBuffers)

	cleanupImage(graphicsContext, &imguiData.colour)

	vk.DestroyRenderPass(device, imguiData.renderPass, nil)
}


// ###################################################################
// #                           Render Loop                           #
// ###################################################################


@(private = "file")
updateLightBuffer :: proc(using graphicsContext: ^GraphicsContext, delta: f32) {
	scene := &scenes[activeScene]

	lightData := make([]LightData, len(scene.pointLights))
	defer delete(lightData)
	for &light, i in scene.pointLights {
		direction: Vec3
		lookAtVector: Vec3

		if light.rotationAxis != {0, 0, 0} {
			light.position =
				rotation3(f32(radians(light.rotationAngle * delta)), light.rotationAxis) *
				light.position
		}

		direction = normalize(Vec3{0, 0, 0} - light.position)
		lookAtVector = Vec3{0, 0, 0}
		up: Vec3
		dot := dot(direction, Vec3{0, 1, 0})
		if abs(dot) < 0.0001 {
			up = cross(direction, Vec3{0, 1, 0})
		} else {
			up = cross(direction, Vec3{0, 0, 1})
		}
		lightData[i] = {
			position        = Vec4{light.position.x, light.position.y, light.position.z, 1},
			colourIntensity = Vec4 {
				light.colourIntensity.x,
				light.colourIntensity.y,
				light.colourIntensity.z,
				0,
			},
			near            = 0.01,
			far             = 5.0,
		}
	}
	mem.copy(
		scene.lightBuffers[currentFrame].mapped,
		raw_data(lightData),
		size_of(LightData) * len(scene.pointLights),
	)
}

@(private = "file")
updateUniformBuffer :: proc(using graphicsContext: ^GraphicsContext) {
	scene := &scenes[activeScene]

	camera := scene.cameras[scene.activeCamera]
	view := lookAt(camera.eye, camera.center, camera.up)
	projection: Mat4
	if camera.mode == .PERSPECTIVE {
		projection = perspective(
			radians(camera.fov),
			f32(swapchainExtent.width) / f32(swapchainExtent.height),
			0.1,
			100,
		)
	} else if camera.mode == .ORTHOGRAPHIC {
		projection = orthographic(
			radians(camera.fov),
			f32(swapchainExtent.width) / f32(swapchainExtent.height),
			0.1,
			100,
		)
	} else {
		log.log(.Error, "Undefined camera mode!")
		panic("Undefined camera mode!")
	}
	viewProjection: UniformBuffer = {
		view           = view,
		projection     = projection,
		viewProjection = projection * view,
		lightCount     = u32(len(scene.pointLights)),
	}
	mem.copy(uniformBuffers[currentFrame].mapped, &viewProjection, size_of(UniformBuffer))
}

@(private = "file")
updateInstanceBuffer :: proc(using graphicsContext: ^GraphicsContext, delta: f32) {
	scene := &scenes[activeScene]

	finalBoneTransforms := make([]Mat4, scene.boneCount)
	instanceData := make([]InstanceInfo, len(scene.instances))
	defer delete(finalBoneTransforms)
	defer delete(instanceData)
	finalBoneTransforms[0] = IMat4
	boneOffset: u32 = 1
	for &instance, instanceIndex in scene.instances {
		instanceData[instanceIndex] = {
			model                = translate(
				instance.position,
			) * quatToRotation(quatFromX(radians(instance.rotation.x)) * quatFromY(radians(instance.rotation.y)) * quatFromZ(radians(instance.rotation.x))) * scale(instance.scale),
			boneOffset           = boneOffset,
			textureSamplerOffset = f32(instance.textureID),
			normalsSamplerOffset = f32(instance.normalID),
		}

		model := &scene.models[instance.modelID]

		if len(model^.skeleton) == 0 {
			instanceData[instanceIndex].boneOffset = 0
			continue
		}

		skeleton := &model^.skeleton

		localBoneTransforms := make([]Mat4, len(skeleton))
		defer delete(localBoneTransforms)

		for index in 0 ..< len(skeleton) {
			localBoneTransforms[index] = IMat4
		}

		if len(model^.animations) != 0 {
			animation := model^.animations[instance.animID]
			instance.animTimer += f64(delta)
			instance.animTimer /= animation.duration
			instance.animTimer =
				(instance.animTimer - floor(instance.animTimer)) * animation.duration
			for &node, nodeIndex in animation.nodes {
				// a *= b == a = a * b
				// therefore I *= T *= R *= S == aT = I * T * R * S
				if node.numKeyPositions == 1 {
					localBoneTransforms[node.bone] *= translate(node.keyPositions[0].value)
				} else if node.numKeyPositions != 0 {
					id := instance.positionKeys[nodeIndex]
					for true {
						if node.keyPositions[id].time <= instance.animTimer &&
						   instance.animTimer <= node.keyPositions[id + 1].time {
							instance.positionKeys[nodeIndex] = id
							break
						}
						id += 1
						if id == node.numKeyPositions - 1 {
							id = 0
						}
					}
					valueDiff :=
						node.keyPositions[instance.positionKeys[nodeIndex] + 1].value -
						node.keyPositions[instance.positionKeys[nodeIndex]].value
					timeDiff :=
						(instance.animTimer -
							node.keyPositions[instance.positionKeys[nodeIndex]].time) /
						(node.keyPositions[instance.positionKeys[nodeIndex] + 1].time -
								node.keyPositions[instance.positionKeys[nodeIndex]].time)
					value :=
						f32(timeDiff) * valueDiff +
						node.keyPositions[instance.positionKeys[nodeIndex]].value
					localBoneTransforms[node.bone] *= translate(value)
				}

				if node.numKeyRotations == 1 {
					localBoneTransforms[node.bone] *= quatToRotation(node.keyRotations[0].value)
				} else if node.numKeyRotations != 0 {
					id := instance.rotationKeys[nodeIndex]
					for true {
						if node.keyRotations[id].time <= instance.animTimer &&
						   instance.animTimer <= node.keyRotations[id + 1].time {
							instance.rotationKeys[nodeIndex] = id
							break
						}
						id += 1
						if id == node.numKeyRotations - 1 {
							id = 0
						}
					}
					valueDiff :=
						node.keyRotations[instance.rotationKeys[nodeIndex] + 1].value -
						node.keyRotations[instance.rotationKeys[nodeIndex]].value
					timeDiff :=
						(instance.animTimer -
							node.keyRotations[instance.rotationKeys[nodeIndex]].time) /
						(node.keyRotations[instance.rotationKeys[nodeIndex] + 1].time -
								node.keyRotations[instance.rotationKeys[nodeIndex]].time)
					localBoneTransforms[node.bone] *= quatToRotation(
						quatLurp(
							node.keyRotations[instance.rotationKeys[nodeIndex]].value,
							node.keyRotations[instance.rotationKeys[nodeIndex] + 1].value,
							f32(timeDiff),
						),
					)
				}

				if node.numKeyScales == 1 {
					localBoneTransforms[node.bone] *= scale(node.keyScales[0].value)
				} else if node.numKeyScales != 0 {
					id := instance.scaleKeys[nodeIndex]
					for true {
						if node.keyScales[id].time <= instance.animTimer &&
						   instance.animTimer <= node.keyScales[id + 1].time {
							instance.scaleKeys[nodeIndex] = id
							break
						}
						id += 1
						if id == node.numKeyScales - 1 {
							id = 0
						}
					}
					valueDiff :=
						node.keyScales[instance.scaleKeys[nodeIndex] + 1].value -
						node.keyScales[instance.scaleKeys[nodeIndex]].value
					timeDiff :=
						(instance.animTimer - node.keyScales[instance.scaleKeys[nodeIndex]].time) /
						(node.keyScales[instance.scaleKeys[nodeIndex] + 1].time -
								node.keyScales[instance.scaleKeys[nodeIndex]].time)
					value :=
						f32(timeDiff) * valueDiff +
						node.keyScales[instance.scaleKeys[nodeIndex]].value
					localBoneTransforms[node.bone] *= scale(value)
				}
			}
		}

		finalBoneTransforms[boneOffset] = localBoneTransforms[0]
		if localBoneTransforms[0] != IMat4 {
			finalBoneTransforms[boneOffset] *= skeleton[0].inverseBind
		}
		for boneIndex in 1 ..< u32(len(skeleton)) {
			parentIndex := skeleton[boneIndex].parentIndex
			localBoneTransforms[boneIndex] =
				localBoneTransforms[parentIndex] * localBoneTransforms[boneIndex]
			finalBoneTransforms[boneOffset + boneIndex] = localBoneTransforms[boneIndex]
			if localBoneTransforms[boneIndex] != IMat4 {
				finalBoneTransforms[boneOffset + boneIndex] *= skeleton[boneIndex].inverseBind
			}
		}
		boneOffset += u32(len(skeleton))
	}

	mem.copy(
		scene.boneBuffers[currentFrame].mapped,
		raw_data(finalBoneTransforms),
		scene.boneCount * size_of(Mat4),
	)
	mem.copy(
		scene.instanceBuffers[currentFrame].mapped,
		raw_data(instanceData),
		len(scene.instances) * size_of(InstanceInfo),
	)
}

@(private = "file")
recordPrecomputeBuffer :: proc(
	using graphicsContext: ^GraphicsContext,
	commandBuffer: vk.CommandBuffer,
	imageIndex: u32,
) {
	scene := &scenes[activeScene]

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}

	if vk.BeginCommandBuffer(commandBuffer, &beginInfo) != .SUCCESS {
		log.log(.Error, "Failed to being recording command buffer!")
		panic("Failed to being recording command buffer!")
	}

	// PRECOMPUTE
	{
		vk.CmdBindDescriptorSets(
			commandBuffer,
			.COMPUTE,
			pipelines[PipelineIndex.PRECOMPUTE].layout,
			0,
			1,
			&pipelines[PipelineIndex.PRECOMPUTE].descriptorSets[currentFrame],
			0,
			nil,
		)
		vk.CmdBindPipeline(commandBuffer, .COMPUTE, pipelines[PipelineIndex.PRECOMPUTE].pipeline)

		offset: u32 = 0
		for &inst, index in scene.instances {
			vk.CmdPushConstants(
				commandBuffer,
				pipelines[PipelineIndex.PRECOMPUTE].layout,
				{.COMPUTE},
				0,
				4 * size_of(u32),
				raw_data(
					[]u32 {
						u32(index),
						u32(len(scene.models[inst.modelID].vertices)),
						scene.models[inst.modelID].vertexOffset,
						offset,
					},
				),
			)
			vk.CmdDispatch(
				commandBuffer,
				u32(len(scene.models[inst.modelID].vertices)) / 64 + 1,
				1,
				1,
			)
			offset += u32(len(scene.models[inst.modelID].vertices))
		}
	}

	if vk.EndCommandBuffer(commandBuffer) != .SUCCESS {
		log.log(.Error, "Failed to record command buffer!")
		panic("Failed to record command buffer!")
	}
}

@(private = "file")
recordGraphicsBuffer :: proc(
	using graphicsContext: ^GraphicsContext,
	commandBuffer: vk.CommandBuffer,
	imageIndex: u32,
) {
	scene := &scenes[activeScene]

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}
	if vk.BeginCommandBuffer(commandBuffer, &beginInfo) != .SUCCESS {
		log.log(.Error, "Failed to being recording command buffer!")
		panic("Failed to being recording command buffer!")
	}

	// SHADOW
	{
		lightCount := u32(len(scene.pointLights))
		shadowImageCount := lightCount * 6
		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			scene.shadowImages.vkImage,
			.SHADER_READ_ONLY_OPTIMAL,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			shadowImageCount,
		)
		for index: u32 = 0; index < u32(len(scene.pointLights)); index += 1 {
			renderPassInfo: vk.RenderPassBeginInfo = {
				sType = .RENDER_PASS_BEGIN_INFO,
				pNext = nil,
				renderPass = pipelines[PipelineIndex.LIGHT].renderPass,
				framebuffer = pipelines[PipelineIndex.LIGHT].frameBuffers[imageIndex],
				renderArea = vk.Rect2D {
					offset = {0, 0},
					extent = {u32(SHADOW_RESOLUTION.x), u32(SHADOW_RESOLUTION.y)},
				},
				clearValueCount = 2,
				pClearValues = raw_data(
					[]vk.ClearValue {
						{color = vk.ClearColorValue{float32 = {0, 0, 0, 0}}},
						{depthStencil = vk.ClearDepthStencilValue{depth = 1, stencil = 0}},
					},
				),
			}
			vk.CmdBeginRenderPass(commandBuffer, &renderPassInfo, .INLINE)

			vk.CmdBindPipeline(commandBuffer, .GRAPHICS, pipelines[PipelineIndex.LIGHT].pipeline)
			vk.CmdBindDescriptorSets(
				commandBuffer,
				.GRAPHICS,
				pipelines[PipelineIndex.LIGHT].layout,
				0,
				1,
				&pipelines[PipelineIndex.LIGHT].descriptorSets[currentFrame],
				0,
				nil,
			)

			vk.CmdBindVertexBuffers(
				commandBuffer,
				0,
				1,
				&scene.vertexBuffer.buffer,
				raw_data([]vk.DeviceSize{0}),
			)
			vk.CmdBindIndexBuffer(commandBuffer, scene.indexBuffer.buffer, 0, .UINT32)

			vk.CmdPushConstants(
				commandBuffer,
				pipelines[PipelineIndex.LIGHT].layout,
				{.VERTEX},
				size_of(u32),
				size_of(u32),
				&index,
			)

			offset: u32 = 0
			for &inst, j in scene.instances {
				vk.CmdPushConstants(
					commandBuffer,
					pipelines[PipelineIndex.LIGHT].layout,
					{.VERTEX},
					0,
					size_of(u32),
					&offset,
				)

				vk.CmdDrawIndexed(
					commandBuffer,
					u32(len(scene.models[inst.modelID].indices)),
					1,
					scene.models[inst.modelID].indexOffset,
					i32(scene.models[inst.modelID].vertexOffset),
					u32(j),
				)

				offset += u32(len(scene.models[inst.modelID].vertices))
			}

			vk.CmdEndRenderPass(commandBuffer)

			vk.CmdCopyImage(
				commandBuffer,
				pipelines[PipelineIndex.LIGHT].colour.vkImage,
				.TRANSFER_SRC_OPTIMAL,
				scene.shadowImages.vkImage,
				.TRANSFER_DST_OPTIMAL,
				1,
				&vk.ImageCopy {
					srcSubresource = vk.ImageSubresourceLayers {
						aspectMask = {.COLOR},
						mipLevel = 0,
						baseArrayLayer = 0,
						layerCount = 6,
					},
					srcOffset = {0, 0, 0},
					dstSubresource = vk.ImageSubresourceLayers {
						aspectMask = {.COLOR},
						mipLevel = 0,
						baseArrayLayer = index * 6,
						layerCount = 6,
					},
					dstOffset = {0, 0, 0},
					extent = vk.Extent3D {
						width = u32(SHADOW_RESOLUTION.x),
						height = u32(SHADOW_RESOLUTION.y),
						depth = 1,
					},
				},
			)
		}

		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			scene.shadowImages.vkImage,
			.TRANSFER_DST_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			{.COLOR},
			shadowImageCount,
		)
	}

	// MAIN
	{
		renderPassInfo: vk.RenderPassBeginInfo = {
			sType = .RENDER_PASS_BEGIN_INFO,
			pNext = nil,
			renderPass = pipelines[PipelineIndex.MAIN].renderPass,
			framebuffer = pipelines[PipelineIndex.MAIN].frameBuffers[imageIndex],
			renderArea = vk.Rect2D {
				offset = {0, 0},
				extent = {u32(RENDER_SIZE.x), u32(RENDER_SIZE.y)},
			},
			clearValueCount = 2,
			pClearValues = raw_data(
				[]vk.ClearValue {
					{
						color = vk.ClearColorValue {
							float32 = Vec4 {
								f32(scene.clearColour.x) / 255,
								f32(scene.clearColour.y) / 255,
								f32(scene.clearColour.z) / 255,
								f32(scene.clearColour.w) / 255,
							},
						},
					},
					{depthStencil = vk.ClearDepthStencilValue{depth = 1, stencil = 0}},
				},
			),
		}
		vk.CmdBeginRenderPass(commandBuffer, &renderPassInfo, .INLINE)

		vk.CmdBindDescriptorSets(
			commandBuffer,
			.GRAPHICS,
			pipelines[PipelineIndex.MAIN].layout,
			0,
			1,
			&pipelines[PipelineIndex.MAIN].descriptorSets[currentFrame],
			0,
			nil,
		)
		vk.CmdBindPipeline(commandBuffer, .GRAPHICS, pipelines[PipelineIndex.MAIN].pipeline)

		vk.CmdPushConstants(
			commandBuffer,
			pipelines[PipelineIndex.MAIN].layout,
			{.VERTEX, .FRAGMENT},
			size_of(u32),
			size_of(f32),
			&scene.ambientLight,
		)

		vk.CmdBindVertexBuffers(
			commandBuffer,
			0,
			1,
			&scene.vertexBuffer.buffer,
			raw_data([]vk.DeviceSize{0}),
		)
		vk.CmdBindIndexBuffer(commandBuffer, scene.indexBuffer.buffer, 0, .UINT32)

		offset: u32 = 0
		for &inst, index in scene.instances {
			vk.CmdPushConstants(
				commandBuffer,
				pipelines[PipelineIndex.MAIN].layout,
				{.VERTEX, .FRAGMENT},
				0,
				size_of(u32),
				&offset,
			)

			vk.CmdDrawIndexed(
				commandBuffer,
				u32(len(scene.models[inst.modelID].indices)),
				1,
				scene.models[inst.modelID].indexOffset,
				i32(scene.models[inst.modelID].vertexOffset),
				u32(index),
			)

			offset += u32(len(scene.models[inst.modelID].vertices))
		}

		vk.CmdEndRenderPass(commandBuffer)
	}

	if vk.EndCommandBuffer(commandBuffer) != .SUCCESS {
		log.log(.Error, "Failed to record command buffer!")
		panic("Failed to record command buffer!")
	}
}

@(private = "file")
recordComputeBuffer :: proc(
	using graphicsContext: ^GraphicsContext,
	commandBuffer: vk.CommandBuffer,
	imageIndex: u32,
) {
	scene := &scenes[activeScene]

	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}

	if vk.BeginCommandBuffer(commandBuffer, &beginInfo) != .SUCCESS {
		log.log(.Error, "Failed to start recording compute commands!")
		panic("Failed to start recording compute commands!")
	}

	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		inImage.vkImage,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		1,
	)

	upscaleImage(
		commandBuffer,
		pipelines[PipelineIndex.MAIN].colour.vkImage,
		inImage.vkImage,
		{u32(RENDER_SIZE.x), u32(RENDER_SIZE.y)},
		{swapchainExtent.width, swapchainExtent.height},
		0,
		0,
	)

	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		inImage.vkImage,
		.TRANSFER_DST_OPTIMAL,
		.GENERAL,
		{.COLOR},
		1,
	)

	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		outImage.vkImage,
		.UNDEFINED,
		.GENERAL,
		{.COLOR},
		1,
	)

	vk.CmdBindDescriptorSets(
		commandBuffer,
		.COMPUTE,
		pipelines[PipelineIndex.POST].layout,
		0,
		1,
		&pipelines[PipelineIndex.POST].descriptorSets[currentFrame],
		0,
		nil,
	)

	vk.CmdPushConstants(
		commandBuffer,
		pipelines[PipelineIndex.POST].layout,
		{.COMPUTE},
		0,
		6 * size_of(f32),
		raw_data(
			[]f32{contrast, brightness, saturation, pow(f32(2.0), exposure), tonemapper, gamma},
		),
	)

	vk.CmdBindPipeline(commandBuffer, .COMPUTE, pipelines[PipelineIndex.POST].pipeline)

	vk.CmdDispatch(
		commandBuffer,
		swapchainExtent.width / 32 + 1,
		swapchainExtent.height / 32 + 1,
		1,
	)

	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		outImage.vkImage,
		.UNDEFINED,
		.TRANSFER_SRC_OPTIMAL,
		{.COLOR},
		1,
	)

	when UI_ENABLED {
		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			imguiData.colour.vkImage,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		copyImage(
			commandBuffer,
			vk.Extent3D{swapchainExtent.width, swapchainExtent.height, 1},
			outImage.vkImage,
			imguiData.colour.vkImage,
			.TRANSFER_SRC_OPTIMAL,
			.TRANSFER_DST_OPTIMAL,
		)
	} else {
		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			swapchainImages[imageIndex],
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.COLOR},
			1,
		)

		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			scene.shadowMapImages.vkImage,
			.SHADER_READ_ONLY_OPTIMAL,
			.TRANSFER_SRC_OPTIMAL,
			{.DEPTH},
			6,
		)

		upscaleImage(
			commandBuffer,
			scene.shadowMapImages.vkImage,
			swapchainImages[imageIndex],
			{u32(SHADOW_RESOLUTION.x), u32(SHADOW_RESOLUTION.y)},
			{swapchainExtent.width, swapchainExtent.height},
			0,
			0,
		)

		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			scene.shadowMapImages.vkImage,
			.TRANSFER_SRC_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			{.DEPTH},
			6,
		)

		transitionImageLayout(
			graphicsContext,
			commandBuffer,
			swapchainImages[imageIndex],
			.TRANSFER_DST_OPTIMAL,
			.PRESENT_SRC_KHR,
			{.COLOR},
			1,
		)
	}

	if vk.EndCommandBuffer(commandBuffer) != .SUCCESS {
		log.log(.Error, "Failed to record compute command buffer!")
		panic("Failed to record compute command buffer!")
	}
}

@(private = "file")
recordUIBuffer :: proc(
	using graphicsContext: ^GraphicsContext,
	commandBuffer: vk.CommandBuffer,
	imageIndex: u32,
) {
	beginInfo: vk.CommandBufferBeginInfo = {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		pNext            = nil,
		flags            = {},
		pInheritanceInfo = nil,
	}
	if vk.BeginCommandBuffer(commandBuffer, &beginInfo) != .SUCCESS {
		log.log(.Error, "Failed to being recording command buffer!")
		panic("Failed to being recording command buffer!")
	}

	renderPassInfo: vk.RenderPassBeginInfo = {
		sType = .RENDER_PASS_BEGIN_INFO,
		pNext = nil,
		renderPass = imguiData.renderPass,
		framebuffer = imguiData.frameBuffers[imageIndex],
		renderArea = vk.Rect2D{offset = {0, 0}, extent = swapchainExtent},
		clearValueCount = 0,
		pClearValues = nil,
	}
	vk.CmdBeginRenderPass(commandBuffer, &renderPassInfo, .INLINE)

	imgui.Render()
	implVulkan.RenderDrawData(imgui.GetDrawData(), commandBuffer)

	vk.CmdEndRenderPass(commandBuffer)

	transitionImageLayout(
		graphicsContext,
		commandBuffer,
		swapchainImages[imageIndex],
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		1,
	)

	vk.CmdBlitImage(
		commandBuffer,
		imguiData.colour.vkImage,
		.TRANSFER_SRC_OPTIMAL,
		swapchainImages[imageIndex],
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
		graphicsContext,
		commandBuffer,
		swapchainImages[imageIndex],
		.TRANSFER_DST_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR},
		1,
	)

	if vk.EndCommandBuffer(commandBuffer) != .SUCCESS {
		log.log(.Error, "Failed to record ui command buffer!")
		panic("Failed to record ui command buffer!")
	}
}

@(private = "file")
drawUI :: proc(using graphicsContext: ^GraphicsContext) {
	constructMenuBar :: proc(using graphicsContext: ^GraphicsContext) {
		scene := &scenes[activeScene]

		if imgui.BeginMenu("File") {
			imgui.SeparatorText("Scene Files")
			if imgui.MenuItem("New") {
				createNewScene(graphicsContext)
				setActiveScene(graphicsContext, u32(len(scenes) - 1))
			}
			if imgui.MenuItem("Load") {
				ImFD.Open(
					"SceneOpenDialog",
					"Open a scene",
					"JSON file (*.json){.json},.*",
					true,
					"./assets/scenes/",
				)
				engineState.inMenu = true
			}
			if imgui.MenuItem("Save") {
				if scene.filePath == "" {
					ImFD.Save(
						"SceneSaveDialog",
						"Save Scene",
						"JSON file (*.json){.json},.*",
						"./assets/scenes/",
					)
					engineState.inMenu = true
				} else {
					saveScene(graphicsContext, activeScene)
				}
			}
			if imgui.MenuItem("Save AS...") {
				ImFD.Save(
					"SceneSaveDialog",
					"Save Scene",
					"JSON file (*.json){.json},.*",
					"./assets/scenes/",
				)
				engineState.inMenu = true
			}
			if imgui.MenuItem("Close") {
				closeScene(graphicsContext, activeScene)
				setActiveScene(graphicsContext, 0)
			}
			imgui.SeparatorText("Assets")
			if imgui.BeginMenu("Import") {
				if imgui.MenuItem("Model") {
					ImFD.Open(
						"LoadModelDialog",
						"Load Model",
						"FBX file (*.fbx){.fbx},OBJ file (*.obj){.obj},.*",
						true,
						"./assets/models/",
					)
					engineState.inMenu = true
				}
				if imgui.MenuItem("Texture") {
					ImFD.Open(
						"LoadTextureDialog",
						"Load Texture",
						"Image file (*.jpg, *.png){.jpg,.png},.*",
						true,
						"./assets/textures/",
					)
					engineState.inMenu = true
				}
				if imgui.MenuItem("Normal Map") {
					ImFD.Open(
						"LoadNormalDialog",
						"Load Normal Map",
						"Image file (*.jpg *.png){.jpg .png},.*",
						true,
						"./assets/textures/",
					)
					engineState.inMenu = true
				}
				imgui.EndMenu()
			}
			imgui.EndMenu()
		}
	}

	constructCamerasHeader :: proc(using graphicsContext: ^GraphicsContext) {
		scene := &scenes[activeScene]

		for index := len(scene.cameras) - 1; index >= 0; index -= 1 {
			camera := &scene.cameras[index]
			if !imgui.TreeNode(camera.name) {
				continue
			}
			active := u32(index) == scene.activeCamera
			imgui.Checkbox("Active", &active)
			if active {
				scene.activeCamera = u32(index)
			}
			imgui.DragFloat3("Eye", &camera.eye, 0.001)
			imgui.DragFloat3("Center", &camera.center, 0.001)
			imgui.DragFloat3("Up", &camera.up, 0.001)
			imgui.DragFloat("FOV", &camera.fov, 0.5)
			imgui.SeparatorText("Camera Mode")
			if imgui.RadioButton("Perspective", camera.mode == .PERSPECTIVE) {
				camera.mode = .PERSPECTIVE
			}
			if imgui.RadioButton("Orthographic", camera.mode == .ORTHOGRAPHIC) {
				camera.mode = .ORTHOGRAPHIC
			}
			imgui.BeginDisabled(len(scene.cameras) == 1)
			if imgui.Button("Delete") {
				delete(camera.name)
				unordered_remove(&scene.cameras, index)
				if active {
					scene.activeCamera = 0
				}
			}
			imgui.EndDisabled()
			imgui.TreePop()
		}
	}

	constructLightsHeader :: proc(using graphicsContext: ^GraphicsContext) {
		scene := &scenes[activeScene]

		for index := len(scene.pointLights) - 1; index >= 0; index -= 1 {
			light := &scene.pointLights[index]
			if !imgui.TreeNode(light.name) {
				continue
			}
			imgui.DragFloat3("Position", &light.position, 0.001)
			imgui.DragFloat3("Colour", &light.colourIntensity, 0.001, 0.0, 1.0)
			imgui.SeparatorText("Movement")
			imgui.DragFloat("Degrees", &light.rotationAngle, 0.001)
			imgui.DragFloat3("Axis", &light.rotationAxis, 0.001)
			imgui.BeginDisabled(len(scene.pointLights) == 1)
			if imgui.Button("Delete") {
				if vk.DeviceWaitIdle(device) != .SUCCESS {
					panic("Failed to wait for device?")
				}
				delete(light.name)
				unordered_remove(&scene.pointLights, index)
				updateSceneLights(graphicsContext, activeScene)
			}
			imgui.EndDisabled()
			imgui.TreePop()
		}
	}

	constructObjectsHeader :: proc(using graphicsContext: ^GraphicsContext) {
		scene := &scenes[activeScene]

		for index := len(scene.instances) - 1; index >= 0; index -= 1 {
			instance := &scene.instances[index]
			if !imgui.TreeNode(instance.name) {
				continue
			}
			imgui.DragFloat3("Position", &instance.position, 0.001)
			imgui.DragFloat3("Rotation", &instance.rotation, 0.001)
			imgui.DragFloat3("Scale", &instance.scale, 0.001)
			if imgui.BeginCombo("Model", scene.models[instance.modelID].name) {
				for &model, i in scene.models {
					if u32(i) != instance.modelID && imgui.Selectable(model.name) {
						scene.boneCount -= len(scene.models[instance.modelID].skeleton)
						scene.instanceVerticesCount -= len(scene.models[instance.modelID].vertices)

						delete(instance.positionKeys)
						delete(instance.rotationKeys)
						delete(instance.scaleKeys)

						instance.modelID = u32(i)
						skeletonLength := len(scene.models[instance.modelID].skeleton)
						scene.boneCount += skeletonLength
						scene.instanceVerticesCount += len(scene.models[instance.modelID].vertices)

						instance.positionKeys = make([]u32, skeletonLength)
						instance.rotationKeys = make([]u32, skeletonLength)
						instance.scaleKeys = make([]u32, skeletonLength)

						if vk.DeviceWaitIdle(device) != .SUCCESS {
							panic("Failed to wait for device idle?")
						}
						updateSceneInstanceModel(graphicsContext, activeScene)
					}
				}
				imgui.EndCombo()
			}
			if imgui.BeginCombo("Texture", scene.texturePaths[instance.textureID]) {
				for &texture, i in scene.texturePaths {
					if u32(i) != instance.textureID && imgui.Selectable(texture) {
						instance.textureID = u32(i)
					}
				}
				imgui.EndCombo()
			}
			if imgui.BeginCombo("Normal Map", scene.normalPaths[instance.normalID]) {
				for &normal, i in scene.normalPaths {
					if u32(i) != instance.normalID && imgui.Selectable(normal) {
						instance.normalID = u32(i)
					}
				}
				imgui.EndCombo()
			}
			animations := &scene.models[instance.modelID].animations
			if len(animations) > 0 {
				imgui.SeparatorText("Animations")
				if imgui.BeginCombo("Animation Selection", animations[instance.animID].name) {
					for &anim, i in animations {
						if instance.animID != u32(i) && imgui.Selectable(anim.name) {
							instance.animID = u32(i)
						}
					}
					imgui.EndCombo()
				}
				imgui.DragScalar("Animation Timer", .Double, &instance.animTimer, 0.01)
			}
			imgui.BeginDisabled(len(scene.instances) == 1)
			if imgui.Button("Delete") {
				delete(instance.name)
				delete(instance.positionKeys)
				delete(instance.rotationKeys)
				delete(instance.scaleKeys)
				scene.boneCount -= len(scene.models[instance.modelID].skeleton)
				scene.instanceVerticesCount -= len(scene.models[instance.modelID].vertices)
				unordered_remove(&scene.instances, index)

				if vk.DeviceWaitIdle(device) != .SUCCESS {
					panic("Failed to wait for device idle?")
				}
				updateSceneInstanceBuffer(graphicsContext, activeScene)
			}
			imgui.EndDisabled()
			imgui.TreePop()
		}
	}

	constructSceneEditor :: proc(using graphicsContext: ^GraphicsContext) {
		scene := &scenes[activeScene]

		if imgui.BeginMenuBar() {
			constructMenuBar(graphicsContext)
			imgui.EndMenuBar()
		}

		if imgui.Button("Toggle Time", {100, 20}) {
			paused = !paused
		}

		imgui.DragFloat("Contrast", &contrast, 0.01)
		imgui.DragFloat("Brightness", &brightness, 0.01)
		imgui.DragFloat("Saturation", &saturation, 0.01)
		imgui.DragFloat("Exposure", &exposure, 0.01)
		imgui.DragFloat("Gamma", &gamma, 0.01)

		if imgui.BeginCombo("Scene Selection", scene.name) {
			for &s, index in scenes {
				if activeScene != u32(index) && imgui.Selectable(s.name) {
					setActiveScene(graphicsContext, u32(index))
				}
			}
			imgui.EndCombo()
		}

		imgui.DragInt4("Clear Colour", &scene.clearColour)

		imgui.DragFloat("Ambient Light", &scene.ambientLight, 0.0001)

		if imgui.CollapsingHeader("Cameras") {
			constructCamerasHeader(graphicsContext)
			if imgui.Button("Add Camera") {
				count: u32 = 0
				for &camera in scene.cameras {
					if strings.compare(string(camera.name)[:len(camera.name) - 3], "Camera") == 0 {
						count += 1
					}
				}
				newCamera: Camera = {
					name     = fmt.caprintf("Camera{:3d}", count),
					eye      = {0.0, 0.2, -0.4},
					center   = {0.0, 0.0, 0.0},
					up       = {0.0, 1.0, 0.0},
					distance = 1.0,
					fov      = 45.0,
					mode     = .PERSPECTIVE,
				}
				append(&scene.cameras, newCamera)
			}
		}

		if imgui.CollapsingHeader("Lights") {
			constructLightsHeader(graphicsContext)
			if imgui.Button("Add Light") {
				count: u32 = 0
				for &light in scene.pointLights {
					if strings.compare(string(light.name)[:len(light.name) - 3], "Light") == 0 {
						count += 1
					}
				}
				if vk.DeviceWaitIdle(device) != .SUCCESS {
					panic("Failed to wait for device?")
				}
				newLight: PointLight = {
					name            = fmt.caprintf("Light{:3d}", count),
					position        = {0, 2, 0},
					colourIntensity = {1, 1, 1},
					rotationAngle   = 0,
					rotationAxis    = {0, 1, 0},
				}
				append(&scene.pointLights, newLight)
				updateSceneLights(graphicsContext, activeScene)
			}
		}

		if imgui.CollapsingHeader("Objects") {
			constructObjectsHeader(graphicsContext)
			if imgui.Button("Add Object") {
				count: u32 = 0
				for &instance in scene.instances {
					if strings.compare(string(instance.name)[:len(instance.name) - 3], "Object") ==
					   0 {
						count += 1
					}
				}
				newInstance: Instance = {
					name         = fmt.caprintf("Object{:3d}", count),
					modelID      = 0,
					animID       = 0,
					textureID    = 0,
					normalID     = 0,
					position     = {0, 0, 0},
					rotation     = {0, 0, 0},
					scale        = {0.2, 0.2, 0.2},
					positionKeys = make([]u32, len(scene.models[0].skeleton)),
					rotationKeys = make([]u32, len(scene.models[0].skeleton)),
					scaleKeys    = make([]u32, len(scene.models[0].skeleton)),
					animTimer    = 0.0,
				}
				scene.boneCount += len(scene.models[0].skeleton)
				scene.instanceVerticesCount += len(scene.models[0].vertices)
				append(&scene.instances, newInstance)
				if vk.DeviceWaitIdle(device) != .SUCCESS {
					panic("Failed to wait for device idle?")
				}
				updateSceneInstanceBuffer(graphicsContext, activeScene)
			}
		}
	}

	implVulkan.NewFrame()
	implGLFW.NewFrame()
	imgui.NewFrame()

	if showMetrics {
		imgui.ShowMetricsWindow()
	}

	if showDemo {
		imgui.ShowDemoWindow()
	}

	if imgui.Begin("Scene Editor", nil, {.MenuBar}) {
		constructSceneEditor(graphicsContext)
	}
	imgui.End()

	scene := &scenes[activeScene]

	if ImFD.IsDone("SceneOpenDialog") {
		if ImFD.HasResult() {
			file := ImFD.GetResult()
			index, err := loadScene(graphicsContext, string(file))
			setActiveScene(graphicsContext, index)
		}
		ImFD.Close()
		engineState.inMenu = false
	}
	if ImFD.IsDone("SceneSaveDialog") {
		if ImFD.HasResult() {
			file := ImFD.GetResult()
			scene.filePath = string(file)
			saveScene(graphicsContext, activeScene)
		}
		ImFD.Close()
		engineState.inMenu = false
	}
	if ImFD.IsDone("LoadModelDialog") {
		fileCount: c.int
		if ImFD.HasResult() {
			files := ImFD.GetResults(&fileCount)
			defer ImFD.FreeResults()
			newFilepaths := make([]cstring, fileCount)
			defer delete(newFilepaths)
			count := 0
			modelInner: for index in 0 ..< fileCount {
				file := files[index]
				for &loadedFile in scene.texturePaths {
					if file == loadedFile {
						continue modelInner
					}
				}
				stringLen := len(file) + 1
				// Is this the proper way to clone a cstring?
				memPtr, err := mem.alloc(stringLen)
				mem.copy(memPtr, (rawptr)(file), stringLen)
				newFilepaths[count] = (cstring)(memPtr)
				count += 1
			}
			if count != 0 {
				loadModels(graphicsContext, activeScene, newFilepaths[:count])
				if vk.DeviceWaitIdle(device) != .SUCCESS {
					panic("Failed to wait for device idle?")
				}
				updateSceneModels(graphicsContext, activeScene)
				append(&scene.modelPaths, ..newFilepaths[:count])
			}
		}
		ImFD.Close()
		engineState.inMenu = false
	}
	if ImFD.IsDone("LoadTextureDialog") {
		if ImFD.HasResult() {
			fileCount: c.int
			files := ImFD.GetResults(&fileCount)
			defer ImFD.FreeResults()
			newFilepaths := make([]cstring, fileCount)
			defer delete(newFilepaths)
			count: u32 = 0
			textureInner: for index in 0 ..< fileCount {
				file := files[index]
				for &loadedFile in scene.modelPaths {
					if file == loadedFile {
						continue textureInner
					}
				}
				stringLen := len(file) + 1
				// Is this the proper way to clone a cstring?
				memPtr, err := mem.alloc(stringLen)
				mem.copy(memPtr, (rawptr)(file), stringLen)
				newFilepaths[count] = (cstring)(memPtr)
				count += 1
			}
			if count != 0 {
				addImages(
					graphicsContext,
					&scene.textures,
					scene.textureCount,
					newFilepaths[:count],
				)
				updateSceneTextures(graphicsContext, activeScene)
				append(&scene.texturePaths, ..newFilepaths[:count])
				scene.textureCount += count
			}
		}
		ImFD.Close()
		engineState.inMenu = false
	}
	if ImFD.IsDone("LoadNormalDialog") {
		if ImFD.HasResult() {
			fileCount: c.int
			files := ImFD.GetResults(&fileCount)
			defer ImFD.FreeResults()
			newFilepaths := make([]cstring, fileCount)
			defer delete(newFilepaths)
			count: u32 = 0
			normalInner: for index in 0 ..< fileCount {
				file := files[index]
				foundMatch := false
				for &loadedFile in scene.normalPaths {
					if file == loadedFile {
						foundMatch = true
						continue normalInner
					}
				}
				stringLen := len(file) + 1
				// Is this the proper way to clone a cstring?
				memPtr, err := mem.alloc(stringLen)
				mem.copy(memPtr, (rawptr)(file), stringLen)
				newFilepaths[count] = (cstring)(memPtr)
				count += 1
			}
			if count != 0 {
				addImages(graphicsContext, &scene.normals, scene.normalCount, newFilepaths[:count])
				updateSceneNormals(graphicsContext, activeScene)
				append(&scene.normalPaths, ..newFilepaths[:count])
				scene.normalCount += count
			}
		}
		ImFD.Close()
		engineState.inMenu = false
	}
}

drawFrame :: proc(using graphicsContext: ^GraphicsContext, delta: f32) {
	vk.WaitForFences(device, 1, &inFlightFrames[currentFrame], true, max(u64))

	imageIndex: u32
	if result := vk.AcquireNextImageKHR(
		device,
		swapchain,
		max(u64),
		imagesAvailable[currentFrame],
		{},
		&imageIndex,
	); result == .ERROR_OUT_OF_DATE_KHR {
		recreateSwapchain(graphicsContext)
		return
	} else if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		log.log(.Error, "Failed to aquire swapchain image!")
		panic("Failed to aquire swapchain image!")
	}
	vk.ResetFences(device, 1, &inFlightFrames[currentFrame])

	vk.ResetCommandBuffer(precomputeCommandBuffers[currentFrame], {})
	vk.ResetCommandBuffer(mainCommandBuffers[currentFrame], {})
	vk.ResetCommandBuffer(computeCommandBuffers[currentFrame], {})
	when UI_ENABLED {
		vk.ResetCommandBuffer(uiCommandBuffers[currentFrame], {})
	}

	updateUniformBuffer(graphicsContext)
	updateLightBuffer(graphicsContext, delta)
	updateInstanceBuffer(graphicsContext, delta)
	when UI_ENABLED {
		drawUI(graphicsContext)
	}

	recordPrecomputeBuffer(graphicsContext, precomputeCommandBuffers[currentFrame], imageIndex)
	recordGraphicsBuffer(graphicsContext, mainCommandBuffers[currentFrame], imageIndex)
	recordComputeBuffer(graphicsContext, computeCommandBuffers[currentFrame], imageIndex)
	when UI_ENABLED {
		recordUIBuffer(graphicsContext, uiCommandBuffers[currentFrame], imageIndex)
	}

	submitInfo: vk.SubmitInfo = {
		sType                = .SUBMIT_INFO,
		pNext                = nil,
		waitSemaphoreCount   = 0,
		pWaitSemaphores      = nil,
		pWaitDstStageMask    = nil,
		commandBufferCount   = 1,
		pCommandBuffers      = &precomputeCommandBuffers[currentFrame],
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &precomputeFinished[currentFrame],
	}
	if res := vk.QueueSubmit(computeQueue, 1, &submitInfo, 0); res != .SUCCESS {
		log.log(.Error, "Failed to submit draw command buffer!")
		panic("Failed to submit draw command buffer!")
	}

	submitInfo = {
		sType                = .SUBMIT_INFO,
		pNext                = nil,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &precomputeFinished[currentFrame],
		pWaitDstStageMask    = &vk.PipelineStageFlags{.TOP_OF_PIPE},
		commandBufferCount   = 1,
		pCommandBuffers      = &mainCommandBuffers[currentFrame],
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &rendersFinished[currentFrame],
	}
	if res := vk.QueueSubmit(graphicsQueue, 1, &submitInfo, 0); res != .SUCCESS {
		log.log(.Error, "Failed to submit draw command buffer!")
		panic("Failed to submit draw command buffer!")
	}

	waitSemaphoresCount: u32
	waitSemaphores: []vk.Semaphore
	waitDstStageMasks: []vk.PipelineStageFlags
	when UI_ENABLED {
		waitSemaphoresCount = 1
		waitSemaphores = {rendersFinished[currentFrame]}
		waitDstStageMasks = {{.COMPUTE_SHADER}}
	} else {
		waitSemaphoresCount = 2
		waitSemaphores = {rendersFinished[currentFrame], imagesAvailable[currentFrame]}
		waitDstStageMasks = {{.COMPUTE_SHADER}, {.BOTTOM_OF_PIPE}}
	}

	submitInfo = {
		sType                = .SUBMIT_INFO,
		pNext                = nil,
		waitSemaphoreCount   = waitSemaphoresCount,
		pWaitSemaphores      = raw_data(waitSemaphores),
		pWaitDstStageMask    = raw_data(waitDstStageMasks),
		commandBufferCount   = 1,
		pCommandBuffers      = &computeCommandBuffers[currentFrame],
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &computeFinished[currentFrame],
	}
	fence: vk.Fence
	when !UI_ENABLED {
		fence = inFlightFrames[currentFrame]
	}

	if vk.QueueSubmit(computeQueue, 1, &submitInfo, fence) != .SUCCESS {
		log.log(.Error, "Failed to submit compute command buffer!")
		panic("Failed to submit compute command buffer!")
	}

	when UI_ENABLED {
		submitInfo = {
			sType                = .SUBMIT_INFO,
			pNext                = nil,
			waitSemaphoreCount   = 2,
			pWaitSemaphores      = raw_data(
				[]vk.Semaphore{computeFinished[currentFrame], imagesAvailable[currentFrame]},
			),
			pWaitDstStageMask    = raw_data(
				[]vk.PipelineStageFlags{{.TOP_OF_PIPE}, {.BOTTOM_OF_PIPE}},
			),
			commandBufferCount   = 1,
			pCommandBuffers      = &uiCommandBuffers[currentFrame],
			signalSemaphoreCount = 1,
			pSignalSemaphores    = &uiFinished[currentFrame],
		}
		if vk.QueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFrames[currentFrame]) !=
		   .SUCCESS {
			log.log(.Error, "Failed to submit ui command buffer!")
			panic("Failed to submit ui command buffer!")
		}
	}

	waitSemaphore: ^vk.Semaphore
	when UI_ENABLED {
		waitSemaphore = &uiFinished[currentFrame]
	} else {
		waitSemaphore = &computeFinished[currentFrame]
	}

	presentInfo: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		pNext              = nil,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = waitSemaphore,
		swapchainCount     = 1,
		pSwapchains        = &swapchain,
		pImageIndices      = &imageIndex,
		pResults           = nil,
	}

	if result := vk.QueuePresentKHR(presentQueue, &presentInfo);
	   result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR || framebufferResized {
		framebufferResized = false
		recreateSwapchain(graphicsContext)
	} else if result != .SUCCESS {
		log.log(.Error, "Failed to present swapchain image!")
		panic("Failed to present swapchain image!")
	}

	currentFrame = (currentFrame + 1) % 2
}
