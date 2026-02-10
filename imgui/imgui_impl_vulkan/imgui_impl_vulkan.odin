package imgui_impl_vulkan

import imgui "../"
import vk "vendor:vulkan"

when      ODIN_OS == .Windows { foreign import lib "../imgui_windows_x64.lib" }
else when ODIN_OS == .Linux   { foreign import lib "../imgui_linux_x64.a" }
else when ODIN_OS == .Darwin  {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_vulkan.h
// Last checked `v1.91.7-docking` (d0d571e)

// Initialization data, for ImGui_ImplVulkan_Init()
// [Please zero-clear before use!]
// - About descriptor pool:
//   - A VkDescriptorPool should be created with VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
//     and must contain a pool size large enough to hold a small number of VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER descriptors.
//   - As an convenience, by setting DescriptorPoolSize > 0 the backend will create one for you.
//   - Current version of the backend use 1 descriptor for the font atlas + as many as additional calls done to ImGui_ImplVulkan_AddTexture().
//   - It is expected that as early as Q1 2025 the backend will use a few more descriptors, so aim at 10 + number of desierd calls to ImGui_ImplVulkan_AddTexture().
// - About dynamic rendering:
//   - When using dynamic rendering, set UseDynamicRendering=true and fill PipelineRenderingCreateInfo structure.
InitInfo :: struct {
	Instance:       vk.Instance,
	PhysicalDevice: vk.PhysicalDevice,
	Device:         vk.Device,
	QueueFamily:    u32,
	Queue:          vk.Queue,
	DescriptorPool: vk.DescriptorPool,  // See requirements in note above; ignored if using DescriptorPoolSize > 0
	RenderPass:     vk.RenderPass,      // Ignored if using dynamic rendering
	MinImageCount:  u32,                // >= 2
	ImageCount:     u32,                // >= MinImageCount
	MSAASamples:    vk.SampleCountFlag, // 0 defaults to VK_SAMPLE_COUNT_1_BIT

	// (Optional)
	PipelineCache: vk.PipelineCache,
	Subpass:       u32,

	// (Optional) Set to create internal descriptor pool instead of using DescriptorPool
	DescriptorPoolSize: u32,

	// (Optional) Dynamic Rendering
	// Need to explicitly enable VK_KHR_dynamic_rendering extension to use this, even for Vulkan 1.3.
	UseDynamicRendering:         bool,
	// NOTE: Odin-imgui: this field if #ifdef'd out in the Dear ImGui side if the struct is not defined.
	// Keeping the field is a pretty safe bet, but make sure to check this if you have issues!
	PipelineRenderingCreateInfo: vk.PipelineRenderingCreateInfo,

	// (Optional) Allocation, Debugging
	Allocator:         ^vk.AllocationCallbacks,
	CheckVkResultFn:   proc "c" (err: vk.Result),
	MinAllocationSize: vk.DeviceSize, // Minimum allocation size. Set to 1024*1024 to satisfy zealous best practices validation layer and waste a little memory.
}

@(link_prefix="ImGui_ImplVulkan_")
foreign lib {
	Init                :: proc(info: ^InitInfo) -> bool ---
	Shutdown            :: proc() ---
	NewFrame            :: proc() ---
	RenderDrawData      :: proc(draw_data: ^imgui.DrawData, command_buffer: vk.CommandBuffer, pipeline: vk.Pipeline = {}) ---
	CreateFontsTexture  :: proc() -> bool ---
	DestroyFontsTexture :: proc() ---
	SetMinImageCount    :: proc(min_image_count: u32) --- // To override MinImageCount after initialization (e.g. if swap chain is recreated)

	// Register a texture (VkDescriptorSet == ImTextureID)
	// FIXME: This is experimental in the sense that we are unsure how to best design/tackle this problem
	// Please post to https://github.com/ocornut/imgui/pull/914 if you have suggestions.
	AddTexture    :: proc(sampler: vk.Sampler, image_view: vk.ImageView, image_layout: vk.ImageLayout) -> vk.DescriptorSet ---
	RemoveTexture :: proc(descriptor_set: vk.DescriptorSet) ---

	// Optional: load Vulkan functions with a custom function loader
	// This is only useful with IMGUI_IMPL_VULKAN_NO_PROTOTYPES / VK_NO_PROTOTYPES
	LoadFunctions :: proc(loader_func: proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction, user_data: rawptr = nil) -> bool ---
}

// [BETA] Selected render state data shared with callbacks.
// This is temporarily stored in GetPlatformIO().Renderer_RenderState during the ImGui_ImplVulkan_RenderDrawData() call.
// (Please open an issue if you feel you need access to more data)
RenderState :: struct {
    CommandBuffer:  vk.CommandBuffer,
    Pipeline:       vk.Pipeline,
    PipelineLayout: vk.PipelineLayout,
}

// There are some more Vulkan functions/structs which are not bound. They are described like this:
// Internal / Miscellaneous Vulkan Helpers
// (Used by example's main.cpp. Used by multi-viewport features. PROBABLY NOT used by your own engine/app.)
