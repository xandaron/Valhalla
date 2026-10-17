package Valhalla

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

VERSION: u32 : (0 << 22) | (1 << 12) | (0)

Error :: union #shared_nil {
	Device_Error,
	Window_Error,
	Input_Error,
	Surface_Error,
	Shader_Error,
	Workload_Error,
	Image_Error,
	Sampler_Error,
	Memory_Error,
	Staging_Error,
	Buffer_Error,
	Heap_Error,
}

Device_Error :: enum {
	None,
	GLFW_Init_Failed,
	Vulkan_Unavailable,
	Instance_Creation_Failed,
	Missing_Instance_Extension,
	No_Vulkan_Devices,
	No_Suitable_Device,
	Unsupported_Feature,
	Device_Creation_Failed,
}

Device_Features :: struct {
	core:     vk.PhysicalDeviceFeatures,
	vulkan11: vk.PhysicalDeviceVulkan11Features,
	vulkan12: vk.PhysicalDeviceVulkan12Features,
	vulkan13: vk.PhysicalDeviceVulkan13Features,
	vulkan14: vk.PhysicalDeviceVulkan14Features,
}

Validation :: enum {
	None,
	Standard,
	Synchronisation,
}

@(private = "file")
Device_Settings :: struct {
	app_name:            string,
	app_version:         u32,
	instance_extensions: []cstring,
	device_extensions:   []cstring,
	features:            Device_Features,
	feature_chain:       rawptr,
	validation:          Validation,
}

Queue_Families :: struct {
	graphics: u32,
	present:  u32,
	compute:  u32,
}

Optional_Features :: struct {
	multi_draw_indirect:   bool,
	draw_indirect_count:   bool,
	mesh_shader:           bool,
	task_shader:           bool,
	multiview_mesh_shader: bool,
	ray_query:             bool,
}

Device :: struct {
	instance:                 vk.Instance,
	debug_messenger:          vk.DebugUtilsMessengerEXT,
	physical_device:          vk.PhysicalDevice,
	handle:                   vk.Device,
	queue_families:           Queue_Families,
	graphics_queue:           vk.Queue,
	present_queue:            vk.Queue,
	compute_queue:            vk.Queue,
	properties:               vk.PhysicalDeviceProperties,
	memory_properties:        vk.PhysicalDeviceMemoryProperties,
	heap_properties:          vk.PhysicalDeviceDescriptorHeapPropertiesEXT,
	dynamic_state_properties: vk.PhysicalDeviceExtendedDynamicState3PropertiesEXT,
	optional:                 Optional_Features,
	debug_utils:              bool,
}

device: Device

@(private)
initialised: bool

@(private)
runtime_context: runtime.Context

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
	vk.EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME,
	vk.KHR_UNIFIED_IMAGE_LAYOUTS_EXTENSION_NAME,
}

@(private = "file")
Feature_Chain :: struct {
	features:              vk.PhysicalDeviceFeatures2,
	vulkan11:              vk.PhysicalDeviceVulkan11Features,
	vulkan12:              vk.PhysicalDeviceVulkan12Features,
	vulkan13:              vk.PhysicalDeviceVulkan13Features,
	vulkan14:              vk.PhysicalDeviceVulkan14Features,
	descriptor_heap:       vk.PhysicalDeviceDescriptorHeapFeaturesEXT,
	untyped_pointers:      vk.PhysicalDeviceShaderUntypedPointersFeaturesKHR,
	memory_priority:       vk.PhysicalDeviceMemoryPriorityFeaturesEXT,
	pageable_memory:       vk.PhysicalDevicePageableDeviceLocalMemoryFeaturesEXT,
	swapchain_maintenance: vk.PhysicalDeviceSwapchainMaintenance1FeaturesEXT,
	dynamic_state:         vk.PhysicalDeviceExtendedDynamicState3FeaturesEXT,
	unified_layouts:       vk.PhysicalDeviceUnifiedImageLayoutsFeaturesKHR,
}

@(private = "file")
FEATURE_BOOLS_OFFSET :: int(offset_of(vk.PhysicalDeviceVulkan11Features, storageBuffer16BitAccess))

@(require_results)
init :: proc(
	app_name := "",
	app_version: u32 = 0,
	instance_extensions: []cstring = nil,
	device_extensions: []cstring = nil,
	features := Device_Features{},
	feature_chain: rawptr = nil,
	validation := Validation.Synchronisation,
) -> (
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(!initialised, "Valhalla.init called twice")
	settings := Device_Settings {
		app_name            = app_name,
		app_version         = app_version,
		instance_extensions = instance_extensions,
		device_extensions   = device_extensions,
		features            = features,
		feature_chain       = feature_chain,
		validation          = validation,
	}
	runtime_context = context
	install_error_callback()
	if !glfw.Init() {
		return .GLFW_Init_Failed
	}
	initialised = true
	install_joystick_callback()
	install_monitor_callback()
	defer if err != nil {
		shutdown()
	}

	if !glfw.VulkanSupported() {
		return .Vulkan_Unavailable
	}
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	device.debug_utils = create_instance(settings) or_return
	if device.debug_utils {
		create_debug_messenger()
	}
	pick_physical_device(settings) or_return
	create_logical_device(settings) or_return
	open_descriptor_heap() or_return
	return nil
}

shutdown :: proc() {
	if !initialised {
		return
	}
	release_shader_compiler()
	if device.handle != nil {
		vk.DeviceWaitIdle(device.handle)
		release_workload_pool()
		close_descriptor_heap()
		close_staging()
		report_memory_leaks()
		destroy_memory_allocator()
		vk.DestroyDevice(device.handle, nil)
	}
	if device.debug_messenger != 0 {
		vk.DestroyDebugUtilsMessengerEXT(device.instance, device.debug_messenger, nil)
	}
	if device.instance != nil {
		vk.DestroyInstance(device.instance, nil)
	}
	device = {}
	glfw.Terminate()
	initialised = false
}

@(private)
name_object :: proc(type: vk.ObjectType, handle: u64, name: string) {
	if !device.debug_utils || name == "" || handle == 0 {
		return
	}
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	info: vk.DebugUtilsObjectNameInfoEXT = {
		sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
		objectType   = type,
		objectHandle = handle,
		pObjectName  = strings.clone_to_cstring(name, context.temp_allocator),
	}
	vk.SetDebugUtilsObjectNameEXT(device.handle, &info)
}

@(private)
begin_label :: proc(cmd: vk.CommandBuffer, name: string) {
	if !device.debug_utils {
		return
	}
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	label: vk.DebugUtilsLabelEXT = {
		sType      = .DEBUG_UTILS_LABEL_EXT,
		pLabelName = strings.clone_to_cstring(name, context.temp_allocator),
	}
	vk.CmdBeginDebugUtilsLabelEXT(cmd, &label)
}

@(private)
end_label :: proc(cmd: vk.CommandBuffer) {
	if device.debug_utils {
		vk.CmdEndDebugUtilsLabelEXT(cmd)
	}
}

@(private = "file")
vulkan_debug_callback :: proc "system" (
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	types: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = runtime_context
	level: log.Level = .Debug
	switch {
	case .ERROR in severity:
		level = .Error
	case .WARNING in severity:
		level = .Warning
	case .INFO in severity:
		level = .Info
	}
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	details := strings.builder_make(context.temp_allocator)
	for object in callback_data.pObjects[:callback_data.objectCount] {
		if object.pObjectName != nil {
			fmt.sbprintf(&details, "\n  %v \"%s\"", object.objectType, object.pObjectName)
		}
	}
	for index := int(callback_data.cmdBufLabelCount) - 1; index >= 0; index -= 1 {
		fmt.sbprintf(&details, "\n  in \"%s\"", callback_data.pCmdBufLabels[index].pLabelName)
	}
	log.logf(level, "[Vulkan %v]:\n%s%s", types, callback_data.pMessage, strings.to_string(details))
	return false
}

@(private = "file")
has_extension :: proc(available: []vk.ExtensionProperties, name: cstring) -> bool {
	for &extension in available {
		if name == cstring(&extension.extensionName[0]) {
			return true
		}
	}
	return false
}

@(private = "file")
@(require_results)
create_instance :: proc(settings: Device_Settings) -> (debug_utils: bool, err: Error) {
	app_info: vk.ApplicationInfo = {
		sType              = .APPLICATION_INFO,
		pApplicationName   = strings.clone_to_cstring(settings.app_name, context.temp_allocator),
		applicationVersion = settings.app_version,
		pEngineName        = "Valhalla",
		engineVersion      = VERSION,
		apiVersion         = vk.API_VERSION_1_4,
	}

	extension_count: u32
	vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
	available_extensions := make([]vk.ExtensionProperties, extension_count, context.temp_allocator)
	vk.EnumerateInstanceExtensionProperties(nil, &extension_count, raw_data(available_extensions))

	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	extensions := make(
		[dynamic]cstring,
		0,
		len(glfw_extensions) + len(INSTANCE_EXTENSIONS) + len(settings.instance_extensions),
		context.temp_allocator,
	)
	for name in glfw_extensions {
		if has_extension(available_extensions, name) {
			append(&extensions, name)
		} else {
			log.warnf("Couldn't find instance extension: %s", name)
		}
	}
	for name in INSTANCE_EXTENSIONS {
		if has_extension(available_extensions, name) {
			append(&extensions, name)
			if name == vk.EXT_DEBUG_UTILS_EXTENSION_NAME {
				debug_utils = true
			}
		} else {
			log.warnf("Couldn't find instance extension: %s", name)
		}
	}
	for name in settings.instance_extensions {
		if slice.contains(extensions[:], name) {
			continue
		}
		if !has_extension(available_extensions, name) {
			log.errorf("Requested instance extension is not available: %s", name)
			return false, .Missing_Instance_Extension
		}
		append(&extensions, name)
	}

	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	available_layers := make([]vk.LayerProperties, layer_count, context.temp_allocator)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	layers := make([dynamic]cstring, 0, len(REQUESTED_LAYERS), context.temp_allocator)
	layer_loop: for name in (REQUESTED_LAYERS if settings.validation != .None else nil) {
		for &layer in available_layers {
			if name == cstring(&layer.layerName[0]) {
				append(&layers, name)
				continue layer_loop
			}
		}
		log.warnf("Couldn't find layer: %s", name)
	}

	validation_enables := [?]vk.ValidationFeatureEnableEXT{.SYNCHRONIZATION_VALIDATION}
	validation_features: vk.ValidationFeaturesEXT = {
		sType                         = .VALIDATION_FEATURES_EXT,
		enabledValidationFeatureCount = u32(len(validation_enables)),
		pEnabledValidationFeatures    = &validation_enables[0],
	}

	instance_info: vk.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pNext                   = &validation_features if settings.validation == .Synchronisation else nil,
		pApplicationInfo        = &app_info,
		enabledLayerCount       = u32(len(layers)),
		ppEnabledLayerNames     = raw_data(layers),
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
	}

	if res := vk.CreateInstance(&instance_info, nil, &device.instance); res != .SUCCESS {
		log.errorf("Failed to create Vulkan instance: %v", res)
		return false, .Instance_Creation_Failed
	}
	vk.load_proc_addresses(device.instance)
	return
}

@(private = "file")
create_debug_messenger :: proc() {
	messenger_info: vk.DebugUtilsMessengerCreateInfoEXT = {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.ERROR, .WARNING, .INFO},
		messageType     = {.GENERAL, .PERFORMANCE, .VALIDATION},
		pfnUserCallback = vulkan_debug_callback,
	}
	if res := vk.CreateDebugUtilsMessengerEXT(device.instance, &messenger_info, nil, &device.debug_messenger);
	   res != .SUCCESS {
		log.errorf("Failed to create Vulkan debug messenger: %v", res)
	}
}

@(private = "file")
find_queue_families :: proc(physical_device: vk.PhysicalDevice) -> (families: Queue_Families, ok: bool) {
	family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, nil)
	properties := make([]vk.QueueFamilyProperties, family_count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, raw_data(properties))

	found_graphics, found_present, found_compute: bool
	for family, index in properties {
		if .GRAPHICS in family.queueFlags {
			families.graphics = u32(index)
			found_graphics = true
		}
		if .COMPUTE in family.queueFlags {
			families.compute = u32(index)
			found_compute = true
		}
		if glfw.GetPhysicalDevicePresentationSupport(device.instance, physical_device, u32(index)) {
			families.present = u32(index)
			found_present = true
		}
		if found_graphics && found_present && found_compute {
			return families, true
		}
	}
	return
}

@(private = "file")
link_feature_chain :: proc(chain: ^Feature_Chain) {
	chain.features.sType = .PHYSICAL_DEVICE_FEATURES_2
	chain.features.pNext = &chain.vulkan11
	chain.vulkan11.sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
	chain.vulkan11.pNext = &chain.vulkan12
	chain.vulkan12.sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	chain.vulkan12.pNext = &chain.vulkan13
	chain.vulkan13.sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES
	chain.vulkan13.pNext = &chain.vulkan14
	chain.vulkan14.sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES
	chain.vulkan14.pNext = &chain.descriptor_heap
	chain.descriptor_heap.sType = .PHYSICAL_DEVICE_DESCRIPTOR_HEAP_FEATURES_EXT
	chain.descriptor_heap.pNext = &chain.untyped_pointers
	chain.untyped_pointers.sType = .PHYSICAL_DEVICE_SHADER_UNTYPED_POINTERS_FEATURES_KHR
	chain.untyped_pointers.pNext = &chain.memory_priority
	chain.memory_priority.sType = .PHYSICAL_DEVICE_MEMORY_PRIORITY_FEATURES_EXT
	chain.memory_priority.pNext = &chain.pageable_memory
	chain.pageable_memory.sType = .PHYSICAL_DEVICE_PAGEABLE_DEVICE_LOCAL_MEMORY_FEATURES_EXT
	chain.pageable_memory.pNext = &chain.swapchain_maintenance
	chain.swapchain_maintenance.sType = .PHYSICAL_DEVICE_SWAPCHAIN_MAINTENANCE_1_FEATURES_EXT
	chain.swapchain_maintenance.pNext = &chain.dynamic_state
	chain.dynamic_state.sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT
	chain.dynamic_state.pNext = &chain.unified_layouts
	chain.unified_layouts.sType = .PHYSICAL_DEVICE_UNIFIED_IMAGE_LAYOUTS_FEATURES_KHR
	chain.unified_layouts.pNext = nil
}

@(private = "file")
merge_feature_bools :: proc(destination, source: rawptr, offset, size: int) {
	dst := ([^]b32)(uintptr(destination) + uintptr(offset))
	src := ([^]b32)(uintptr(source) + uintptr(offset))
	for i in 0 ..< (size - offset) / size_of(b32) {
		if src[i] {
			dst[i] = true
		}
	}
}

@(private = "file")
missing_feature_bools :: proc(request, support: rawptr, offset, size: int) -> bool {
	req := ([^]b32)(uintptr(request) + uintptr(offset))
	sup := ([^]b32)(uintptr(support) + uintptr(offset))
	for i in 0 ..< (size - offset) / size_of(b32) {
		if req[i] && !sup[i] {
			return true
		}
	}
	return false
}

@(private = "file")
request_features :: proc(chain: ^Feature_Chain, user: Device_Features) {
	link_feature_chain(chain)

	chain.features.features.imageCubeArray = true
	chain.features.features.samplerAnisotropy = true
	chain.features.features.fillModeNonSolid = true
	chain.features.features.depthClamp = true
	chain.features.features.depthBiasClamp = true
	chain.vulkan11.shaderDrawParameters = true
	chain.vulkan11.multiview = true
	chain.vulkan12.timelineSemaphore = true
	chain.vulkan12.bufferDeviceAddress = true
	chain.vulkan13.synchronization2 = true
	chain.vulkan13.dynamicRendering = true
	chain.vulkan14.maintenance5 = true
	chain.descriptor_heap.descriptorHeap = true
	chain.untyped_pointers.shaderUntypedPointers = true
	chain.memory_priority.memoryPriority = true
	chain.pageable_memory.pageableDeviceLocalMemory = true
	chain.swapchain_maintenance.swapchainMaintenance1 = true
	chain.dynamic_state.extendedDynamicState3PolygonMode = true
	chain.dynamic_state.extendedDynamicState3RasterizationSamples = true
	chain.dynamic_state.extendedDynamicState3SampleMask = true
	chain.dynamic_state.extendedDynamicState3AlphaToCoverageEnable = true
	chain.dynamic_state.extendedDynamicState3DepthClampEnable = true
	chain.dynamic_state.extendedDynamicState3ColorBlendEnable = true
	chain.dynamic_state.extendedDynamicState3ColorBlendEquation = true
	chain.dynamic_state.extendedDynamicState3ColorWriteMask = true
	chain.unified_layouts.unifiedImageLayouts = true

	user := user
	merge_feature_bools(&chain.features.features, &user.core, 0, size_of(vk.PhysicalDeviceFeatures))
	merge_feature_bools(&chain.vulkan11, &user.vulkan11, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan11Features))
	merge_feature_bools(&chain.vulkan12, &user.vulkan12, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan12Features))
	merge_feature_bools(&chain.vulkan13, &user.vulkan13, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan13Features))
	merge_feature_bools(&chain.vulkan14, &user.vulkan14, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan14Features))
}

@(private = "file")
query_supported_features :: proc(physical_device: vk.PhysicalDevice, support: ^Feature_Chain) {
	link_feature_chain(support)
	vk.GetPhysicalDeviceFeatures2(physical_device, &support.features)
}

@(private = "file")
supports_requested_features :: proc(physical_device: vk.PhysicalDevice, request: ^Feature_Chain) -> bool {
	support: Feature_Chain
	query_supported_features(physical_device, &support)

	return(
		!missing_feature_bools(&request.features.features, &support.features.features, 0, size_of(vk.PhysicalDeviceFeatures)) &&
		!missing_feature_bools(&request.vulkan11, &support.vulkan11, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan11Features)) &&
		!missing_feature_bools(&request.vulkan12, &support.vulkan12, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan12Features)) &&
		!missing_feature_bools(&request.vulkan13, &support.vulkan13, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan13Features)) &&
		!missing_feature_bools(&request.vulkan14, &support.vulkan14, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceVulkan14Features)) &&
		!missing_feature_bools(&request.descriptor_heap, &support.descriptor_heap, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceDescriptorHeapFeaturesEXT)) &&
		!missing_feature_bools(&request.untyped_pointers, &support.untyped_pointers, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceShaderUntypedPointersFeaturesKHR)) &&
		!missing_feature_bools(&request.memory_priority, &support.memory_priority, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceMemoryPriorityFeaturesEXT)) &&
		!missing_feature_bools(&request.pageable_memory, &support.pageable_memory, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDevicePageableDeviceLocalMemoryFeaturesEXT)) &&
		!missing_feature_bools(&request.swapchain_maintenance, &support.swapchain_maintenance, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceSwapchainMaintenance1FeaturesEXT)) &&
		!missing_feature_bools(&request.dynamic_state, &support.dynamic_state, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceExtendedDynamicState3FeaturesEXT)) &&
		!missing_feature_bools(&request.unified_layouts, &support.unified_layouts, FEATURE_BOOLS_OFFSET, size_of(vk.PhysicalDeviceUnifiedImageLayoutsFeaturesKHR)) \
	)
}

@(private = "file")
collect_device_extensions :: proc(settings: Device_Settings) -> []cstring {
	extensions := make([dynamic]cstring, 0, len(DEVICE_EXTENSIONS) + len(settings.device_extensions), context.temp_allocator)
	append(&extensions, ..DEVICE_EXTENSIONS)
	for name in settings.device_extensions {
		if !slice.contains(extensions[:], name) {
			append(&extensions, name)
		}
	}
	return extensions[:]
}

@(private = "file")
supports_extensions :: proc(physical_device: vk.PhysicalDevice, extensions: []cstring) -> bool {
	extension_count: u32
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &extension_count, nil)
	available := make([]vk.ExtensionProperties, extension_count, context.temp_allocator)
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &extension_count, raw_data(available))

	for name in extensions {
		if !has_extension(available, name) {
			return false
		}
	}
	return true
}

@(private = "file")
@(require_results)
pick_physical_device :: proc(settings: Device_Settings) -> Error {
	request: Feature_Chain
	request_features(&request, settings.features)
	extensions := collect_device_extensions(settings)

	score_physical_device :: proc(
		physical_device: vk.PhysicalDevice,
		request: ^Feature_Chain,
		extensions: []cstring,
	) -> (
		score: u32,
	) {
		families, found := find_queue_families(physical_device)
		if !found || !supports_requested_features(physical_device, request) || !supports_extensions(physical_device, extensions) {
			return
		}

		properties: vk.PhysicalDeviceProperties2 = {
			sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		}
		vk.GetPhysicalDeviceProperties2(physical_device, &properties)

		if properties.properties.deviceType == .DISCRETE_GPU {
			score += 1000
		}
		if families.graphics == families.present {
			score += 100
		}
		if families.graphics == families.compute {
			score += 100
		}
		score += properties.properties.limits.maxImageDimension2D
		return
	}

	device_count: u32
	vk.EnumeratePhysicalDevices(device.instance, &device_count, nil)
	if device_count == 0 {
		return .No_Vulkan_Devices
	}
	physical_devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(device.instance, &device_count, raw_data(physical_devices))

	best_score: u32
	for physical_device in physical_devices {
		if score := score_physical_device(physical_device, &request, extensions); score > best_score {
			device.physical_device = physical_device
			best_score = score
		}
	}
	if device.physical_device == nil {
		return .No_Suitable_Device
	}

	memory_properties: vk.PhysicalDeviceMemoryProperties2 = {
		sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2,
	}
	vk.GetPhysicalDeviceMemoryProperties2(device.physical_device, &memory_properties)
	device.memory_properties = memory_properties.memoryProperties

	device.dynamic_state_properties = {
		sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_PROPERTIES_EXT,
	}
	device.heap_properties = {
		sType = .PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT,
		pNext = &device.dynamic_state_properties,
	}
	properties: vk.PhysicalDeviceProperties2 = {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &device.heap_properties,
	}
	vk.GetPhysicalDeviceProperties2(device.physical_device, &properties)
	device.heap_properties.pNext = nil
	device.dynamic_state_properties.pNext = nil
	device.properties = properties.properties
	log.infof("Using GPU: %s", cstring(&device.properties.deviceName[0]))

	return nil
}

@(private = "file")
@(require_results)
create_logical_device :: proc(settings: Device_Settings) -> Error {
	device.queue_families, _ = find_queue_families(device.physical_device)
	families := device.queue_families

	priority: f32 = 1.0
	unique_families := unique_queue_families()
	queue_infos := make([]vk.DeviceQueueCreateInfo, len(unique_families), context.temp_allocator)
	for family, index in unique_families {
		queue_infos[index] = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = family,
			queueCount       = 1,
			pQueuePriorities = &priority,
		}
	}

	features: Feature_Chain
	request_features(&features, settings.features)
	features.unified_layouts.pNext = settings.feature_chain
	extensions := make([dynamic]cstring, context.temp_allocator)
	append(&extensions, ..collect_device_extensions(settings))

	support: Feature_Chain
	query_supported_features(device.physical_device, &support)
	features.features.features.multiDrawIndirect = features.features.features.multiDrawIndirect || support.features.features.multiDrawIndirect
	features.vulkan12.drawIndirectCount = features.vulkan12.drawIndirectCount || support.vulkan12.drawIndirectCount
	device.optional.multi_draw_indirect = bool(features.features.features.multiDrawIndirect)
	device.optional.draw_indirect_count = bool(features.vulkan12.drawIndirectCount)

	mesh_features: vk.PhysicalDeviceMeshShaderFeaturesEXT
	if !slice.contains(settings.device_extensions, vk.EXT_MESH_SHADER_EXTENSION_NAME) && supports_extensions(device.physical_device, {vk.EXT_MESH_SHADER_EXTENSION_NAME}) {
		mesh_support: vk.PhysicalDeviceMeshShaderFeaturesEXT = {
			sType = .PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
		}
		query: vk.PhysicalDeviceFeatures2 = {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			pNext = &mesh_support,
		}
		vk.GetPhysicalDeviceFeatures2(device.physical_device, &query)
		if mesh_support.meshShader {
			mesh_features = {
				sType               = .PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
				pNext               = settings.feature_chain,
				meshShader          = true,
				taskShader          = mesh_support.taskShader,
				multiviewMeshShader = mesh_support.multiviewMeshShader && features.vulkan11.multiview,
			}
			features.unified_layouts.pNext = &mesh_features
			append(&extensions, vk.EXT_MESH_SHADER_EXTENSION_NAME)
			device.optional.mesh_shader = true
			device.optional.task_shader = bool(mesh_features.taskShader)
			device.optional.multiview_mesh_shader = bool(mesh_features.multiviewMeshShader)
		}
	}

	ray_extensions := []cstring{vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, vk.KHR_RAY_QUERY_EXTENSION_NAME, vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME}
	acceleration_features: vk.PhysicalDeviceAccelerationStructureFeaturesKHR
	ray_query_features: vk.PhysicalDeviceRayQueryFeaturesKHR
	if supports_extensions(device.physical_device, ray_extensions) {
		acceleration_support: vk.PhysicalDeviceAccelerationStructureFeaturesKHR = {
			sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
		}
		ray_query_support: vk.PhysicalDeviceRayQueryFeaturesKHR = {
			sType = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
			pNext = &acceleration_support,
		}
		query: vk.PhysicalDeviceFeatures2 = {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			pNext = &ray_query_support,
		}
		vk.GetPhysicalDeviceFeatures2(device.physical_device, &query)
		if acceleration_support.accelerationStructure && ray_query_support.rayQuery {
			ray_query_features = {
				sType    = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
				pNext    = features.unified_layouts.pNext,
				rayQuery = true,
			}
			acceleration_features = {
				sType                 = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
				pNext                 = &ray_query_features,
				accelerationStructure = true,
			}
			features.unified_layouts.pNext = &acceleration_features
			for name in ray_extensions {
				if !slice.contains(extensions[:], name) {
					append(&extensions, name)
				}
			}
			device.optional.ray_query = true
		}
	}

	device_info: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features.features,
		queueCreateInfoCount    = u32(len(queue_infos)),
		pQueueCreateInfos       = raw_data(queue_infos),
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
	}
	if res := vk.CreateDevice(device.physical_device, &device_info, nil, &device.handle); res != .SUCCESS {
		log.errorf("Failed to create logical device: %v", res)
		return .Unsupported_Feature if res == .ERROR_FEATURE_NOT_PRESENT else .Device_Creation_Failed
	}
	vk.load_proc_addresses(device.handle)

	vk.GetDeviceQueue(device.handle, families.graphics, 0, &device.graphics_queue)
	vk.GetDeviceQueue(device.handle, families.present, 0, &device.present_queue)
	vk.GetDeviceQueue(device.handle, families.compute, 0, &device.compute_queue)
	return nil
}

@(private)
unique_queue_families :: proc() -> []u32 {
	families := device.queue_families
	unique := make([dynamic]u32, 0, 3, context.temp_allocator)
	for family in ([3]u32{families.graphics, families.present, families.compute}) {
		if !slice.contains(unique[:], family) {
			append(&unique, family)
		}
	}
	return unique[:]
}

// ===[ Command Buffers and Semaphores ]========================================

@(private)
@(require_results)
make_command_pool :: proc(flags: vk.CommandPoolCreateFlags, name := "") -> (pool: vk.CommandPool, err: Error) {
	info: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = flags,
		queueFamilyIndex = device.queue_families.graphics,
	}
	if res := vk.CreateCommandPool(device.handle, &info, nil, &pool); res != .SUCCESS {
		log.errorf("Failed to create a command pool: %v", res)
		return 0, .Command_Pool_Creation_Failed
	}
	name_object(.COMMAND_POOL, u64(pool), name)
	return
}

@(private)
@(require_results)
allocate_command_buffer :: proc(pool: vk.CommandPool, name := "") -> (cmd: vk.CommandBuffer, err: Error) {
	info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if res := vk.AllocateCommandBuffers(device.handle, &info, &cmd); res != .SUCCESS {
		log.errorf("Failed to allocate a command buffer: %v", res)
		return nil, .Command_Buffer_Allocation_Failed
	}
	name_object(.COMMAND_BUFFER, u64(uintptr(cmd)), name)
	return
}

@(private)
@(require_results)
begin_commands :: proc(cmd: vk.CommandBuffer, flags: vk.CommandBufferUsageFlags) -> Error {
	info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags,
	}
	if res := vk.BeginCommandBuffer(cmd, &info); res != .SUCCESS {
		log.errorf("Failed to begin a command buffer: %v", res)
		return .Recording_Failed
	}
	return nil
}

@(private)
@(require_results)
make_semaphore :: proc(timeline: bool, name := "") -> (semaphore: vk.Semaphore, err: Error) {
	type_info: vk.SemaphoreTypeCreateInfo = {
		sType         = .SEMAPHORE_TYPE_CREATE_INFO,
		semaphoreType = .TIMELINE,
	}
	info: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = &type_info if timeline else nil,
	}
	if res := vk.CreateSemaphore(device.handle, &info, nil, &semaphore); res != .SUCCESS {
		log.errorf("Failed to create a semaphore: %v", res)
		return 0, .Sync_Creation_Failed
	}
	name_object(.SEMAPHORE, u64(semaphore), name)
	return
}

@(private)
semaphore_value :: proc(semaphore: vk.Semaphore) -> (value: u64) {
	if semaphore != 0 {
		vk.GetSemaphoreCounterValue(device.handle, semaphore, &value)
	}
	return
}

@(private)
@(require_results)
wait_semaphore :: proc(semaphore: vk.Semaphore, value: u64) -> Error {
	semaphore, value := semaphore, value
	info: vk.SemaphoreWaitInfo = {
		sType          = .SEMAPHORE_WAIT_INFO,
		semaphoreCount = 1,
		pSemaphores    = &semaphore,
		pValues        = &value,
	}
	if res := vk.WaitSemaphores(device.handle, &info, max(u64)); res != .SUCCESS {
		log.errorf("Failed to wait on a semaphore: %v", res)
		return .Wait_Failed
	}
	return nil
}
