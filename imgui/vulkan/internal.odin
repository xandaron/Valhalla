#+private
package ImGui_ImplVulkan

import imgui ".."

import "base:runtime"
import "core:math"
import "core:mem"
import vk "vendor:vulkan"


internal_allocator: mem.Allocator

// Reusable buffers used for rendering 1 current in-flight frame, for ImGui_ImplVulkan_RenderDrawData()
FrameRenderBuffers :: struct {
	VertexBufferMemory: vk.DeviceMemory,
	IndexBufferMemory:  vk.DeviceMemory,
	VertexBufferSize:   vk.DeviceSize,
	IndexBufferSize:    vk.DeviceSize,
	VertexBuffer:       vk.Buffer,
	IndexBuffer:        vk.Buffer,
}

// Each viewport will hold 1 ImGui_ImplVulkanH_WindowRenderBuffers
WindowRenderBuffers :: struct {
	Index:              u32,
	Count:              u32,
	FrameRenderBuffers: imgui.Vector(FrameRenderBuffers),
}

Texture :: struct {
	Memory:        vk.DeviceMemory,
	Image:         vk.Image,
	ImageView:     vk.ImageView,
	DescriptorSet: vk.DescriptorSet,
}

// For multi-viewport support:
// Helper structure we store in the void* RendererUserData field of each ImGuiViewport to easily retrieve our backend data.
ViewportData :: struct {
	Window:               Window, // Used by secondary viewports only
	RenderBuffers:        WindowRenderBuffers, // Used by all viewports
	WindowOwned:          bool,
	SwapChainNeedRebuild: bool, // Flag when viewport swapchain resized in the middle of processing a frame
	SwapChainSuboptimal:  bool, // Flag when VK_SUBOPTIMAL_KHR was returned.
}

new_viewport_data :: proc() -> ^ViewportData {
	ptr := new(ViewportData, internal_allocator)
	ptr.Window = Default_Window
	return ptr
}

// Vulkan data
Data :: struct {
	VulkanInitInfo:                                    InitInfo,
	BufferMemoryAlignment:                             vk.DeviceSize,
	NonCoherentAtomSize:                               vk.DeviceSize,
	PipelineCreateFlags:                               vk.PipelineCreateFlags,
	DescriptorSetLayout:                               vk.DescriptorSetLayout,
	PipelineLayout:                                    vk.PipelineLayout,
	Pipeline:                                          vk.Pipeline, // pipeline for main render pass (created by app)
	PipelineForViewports:                              vk.Pipeline, // pipeline for secondary viewports (created by backend)
	ShaderModuleVert:                                  vk.ShaderModule,
	ShaderModuleFrag:                                  vk.ShaderModule,
	DescriptorPool:                                    vk.DescriptorPool,
	PipelineRenderingCreateInfoColorAttachmentFormats: imgui.Vector(vk.Format), // Deep copy of format array

	// Texture management
	TexSamplerLinear:                                  vk.Sampler,
	TexCommandPool:                                    vk.CommandPool,
	TexCommandBuffer:                                  vk.CommandBuffer,

	// Render buffers for main window
	MainWindowRenderBuffers:                           WindowRenderBuffers,
}

Default_Data: Data : {BufferMemoryAlignment = 256, NonCoherentAtomSize = 64}

new_data :: proc() -> ^Data {
	ptr := new(Data, internal_allocator)
	ptr^ = Default_Data
	return ptr
}

//-----------------------------------------------------------------------------
// SHADERS
//-----------------------------------------------------------------------------

// backends/vulkan/glsl_shader.vert, compiled with:
// # glslangValidator -V -x -o glsl_shader.vert.u32 glsl_shader.vert
/*
#version 450 core
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUV;
layout(location = 2) in vec4 aColor;
layout(push_constant) uniform uPushConstant { vec2 uScale; vec2 uTranslate; } pc;

out gl_PerVertex { vec4 gl_Position; };
layout(location = 0) out struct { vec4 Color; vec2 UV; } Out;

void main()
{
    Out.Color = aColor;
    Out.UV = aUV;
    gl_Position = vec4(aPos * pc.uScale + pc.uTranslate, 0, 1);
}
*/
__glsl_shader_vert_spv := [?]u32 {
	0x07230203,
	0x00010000,
	0x00080001,
	0x0000002e,
	0x00000000,
	0x00020011,
	0x00000001,
	0x0006000b,
	0x00000001,
	0x4c534c47,
	0x6474732e,
	0x3035342e,
	0x00000000,
	0x0003000e,
	0x00000000,
	0x00000001,
	0x000a000f,
	0x00000000,
	0x00000004,
	0x6e69616d,
	0x00000000,
	0x0000000b,
	0x0000000f,
	0x00000015,
	0x0000001b,
	0x0000001c,
	0x00030003,
	0x00000002,
	0x000001c2,
	0x00040005,
	0x00000004,
	0x6e69616d,
	0x00000000,
	0x00030005,
	0x00000009,
	0x00000000,
	0x00050006,
	0x00000009,
	0x00000000,
	0x6f6c6f43,
	0x00000072,
	0x00040006,
	0x00000009,
	0x00000001,
	0x00005655,
	0x00030005,
	0x0000000b,
	0x0074754f,
	0x00040005,
	0x0000000f,
	0x6c6f4361,
	0x0000726f,
	0x00030005,
	0x00000015,
	0x00565561,
	0x00060005,
	0x00000019,
	0x505f6c67,
	0x65567265,
	0x78657472,
	0x00000000,
	0x00060006,
	0x00000019,
	0x00000000,
	0x505f6c67,
	0x7469736f,
	0x006e6f69,
	0x00030005,
	0x0000001b,
	0x00000000,
	0x00040005,
	0x0000001c,
	0x736f5061,
	0x00000000,
	0x00060005,
	0x0000001e,
	0x73755075,
	0x6e6f4368,
	0x6e617473,
	0x00000074,
	0x00050006,
	0x0000001e,
	0x00000000,
	0x61635375,
	0x0000656c,
	0x00060006,
	0x0000001e,
	0x00000001,
	0x61725475,
	0x616c736e,
	0x00006574,
	0x00030005,
	0x00000020,
	0x00006370,
	0x00040047,
	0x0000000b,
	0x0000001e,
	0x00000000,
	0x00040047,
	0x0000000f,
	0x0000001e,
	0x00000002,
	0x00040047,
	0x00000015,
	0x0000001e,
	0x00000001,
	0x00050048,
	0x00000019,
	0x00000000,
	0x0000000b,
	0x00000000,
	0x00030047,
	0x00000019,
	0x00000002,
	0x00040047,
	0x0000001c,
	0x0000001e,
	0x00000000,
	0x00050048,
	0x0000001e,
	0x00000000,
	0x00000023,
	0x00000000,
	0x00050048,
	0x0000001e,
	0x00000001,
	0x00000023,
	0x00000008,
	0x00030047,
	0x0000001e,
	0x00000002,
	0x00020013,
	0x00000002,
	0x00030021,
	0x00000003,
	0x00000002,
	0x00030016,
	0x00000006,
	0x00000020,
	0x00040017,
	0x00000007,
	0x00000006,
	0x00000004,
	0x00040017,
	0x00000008,
	0x00000006,
	0x00000002,
	0x0004001e,
	0x00000009,
	0x00000007,
	0x00000008,
	0x00040020,
	0x0000000a,
	0x00000003,
	0x00000009,
	0x0004003b,
	0x0000000a,
	0x0000000b,
	0x00000003,
	0x00040015,
	0x0000000c,
	0x00000020,
	0x00000001,
	0x0004002b,
	0x0000000c,
	0x0000000d,
	0x00000000,
	0x00040020,
	0x0000000e,
	0x00000001,
	0x00000007,
	0x0004003b,
	0x0000000e,
	0x0000000f,
	0x00000001,
	0x00040020,
	0x00000011,
	0x00000003,
	0x00000007,
	0x0004002b,
	0x0000000c,
	0x00000013,
	0x00000001,
	0x00040020,
	0x00000014,
	0x00000001,
	0x00000008,
	0x0004003b,
	0x00000014,
	0x00000015,
	0x00000001,
	0x00040020,
	0x00000017,
	0x00000003,
	0x00000008,
	0x0003001e,
	0x00000019,
	0x00000007,
	0x00040020,
	0x0000001a,
	0x00000003,
	0x00000019,
	0x0004003b,
	0x0000001a,
	0x0000001b,
	0x00000003,
	0x0004003b,
	0x00000014,
	0x0000001c,
	0x00000001,
	0x0004001e,
	0x0000001e,
	0x00000008,
	0x00000008,
	0x00040020,
	0x0000001f,
	0x00000009,
	0x0000001e,
	0x0004003b,
	0x0000001f,
	0x00000020,
	0x00000009,
	0x00040020,
	0x00000021,
	0x00000009,
	0x00000008,
	0x0004002b,
	0x00000006,
	0x00000028,
	0x00000000,
	0x0004002b,
	0x00000006,
	0x00000029,
	0x3f800000,
	0x00050036,
	0x00000002,
	0x00000004,
	0x00000000,
	0x00000003,
	0x000200f8,
	0x00000005,
	0x0004003d,
	0x00000007,
	0x00000010,
	0x0000000f,
	0x00050041,
	0x00000011,
	0x00000012,
	0x0000000b,
	0x0000000d,
	0x0003003e,
	0x00000012,
	0x00000010,
	0x0004003d,
	0x00000008,
	0x00000016,
	0x00000015,
	0x00050041,
	0x00000017,
	0x00000018,
	0x0000000b,
	0x00000013,
	0x0003003e,
	0x00000018,
	0x00000016,
	0x0004003d,
	0x00000008,
	0x0000001d,
	0x0000001c,
	0x00050041,
	0x00000021,
	0x00000022,
	0x00000020,
	0x0000000d,
	0x0004003d,
	0x00000008,
	0x00000023,
	0x00000022,
	0x00050085,
	0x00000008,
	0x00000024,
	0x0000001d,
	0x00000023,
	0x00050041,
	0x00000021,
	0x00000025,
	0x00000020,
	0x00000013,
	0x0004003d,
	0x00000008,
	0x00000026,
	0x00000025,
	0x00050081,
	0x00000008,
	0x00000027,
	0x00000024,
	0x00000026,
	0x00050051,
	0x00000006,
	0x0000002a,
	0x00000027,
	0x00000000,
	0x00050051,
	0x00000006,
	0x0000002b,
	0x00000027,
	0x00000001,
	0x00070050,
	0x00000007,
	0x0000002c,
	0x0000002a,
	0x0000002b,
	0x00000028,
	0x00000029,
	0x00050041,
	0x00000011,
	0x0000002d,
	0x0000001b,
	0x0000000d,
	0x0003003e,
	0x0000002d,
	0x0000002c,
	0x000100fd,
	0x00010038,
}

// backends/vulkan/glsl_shader.frag, compiled with:
// # glslangValidator -V -x -o glsl_shader.frag.u32 glsl_shader.frag
/*
#version 450 core
layout(location = 0) out vec4 fColor;
layout(set=0, binding=0) uniform sampler2D sTexture;
layout(location = 0) in struct { vec4 Color; vec2 UV; } In;
void main()
{
    fColor = In.Color * texture(sTexture, In.UV.st);
}
*/
__glsl_shader_frag_spv := [?]u32 {
	0x07230203,
	0x00010000,
	0x00080001,
	0x0000001e,
	0x00000000,
	0x00020011,
	0x00000001,
	0x0006000b,
	0x00000001,
	0x4c534c47,
	0x6474732e,
	0x3035342e,
	0x00000000,
	0x0003000e,
	0x00000000,
	0x00000001,
	0x0007000f,
	0x00000004,
	0x00000004,
	0x6e69616d,
	0x00000000,
	0x00000009,
	0x0000000d,
	0x00030010,
	0x00000004,
	0x00000007,
	0x00030003,
	0x00000002,
	0x000001c2,
	0x00040005,
	0x00000004,
	0x6e69616d,
	0x00000000,
	0x00040005,
	0x00000009,
	0x6c6f4366,
	0x0000726f,
	0x00030005,
	0x0000000b,
	0x00000000,
	0x00050006,
	0x0000000b,
	0x00000000,
	0x6f6c6f43,
	0x00000072,
	0x00040006,
	0x0000000b,
	0x00000001,
	0x00005655,
	0x00030005,
	0x0000000d,
	0x00006e49,
	0x00050005,
	0x00000016,
	0x78655473,
	0x65727574,
	0x00000000,
	0x00040047,
	0x00000009,
	0x0000001e,
	0x00000000,
	0x00040047,
	0x0000000d,
	0x0000001e,
	0x00000000,
	0x00040047,
	0x00000016,
	0x00000022,
	0x00000000,
	0x00040047,
	0x00000016,
	0x00000021,
	0x00000000,
	0x00020013,
	0x00000002,
	0x00030021,
	0x00000003,
	0x00000002,
	0x00030016,
	0x00000006,
	0x00000020,
	0x00040017,
	0x00000007,
	0x00000006,
	0x00000004,
	0x00040020,
	0x00000008,
	0x00000003,
	0x00000007,
	0x0004003b,
	0x00000008,
	0x00000009,
	0x00000003,
	0x00040017,
	0x0000000a,
	0x00000006,
	0x00000002,
	0x0004001e,
	0x0000000b,
	0x00000007,
	0x0000000a,
	0x00040020,
	0x0000000c,
	0x00000001,
	0x0000000b,
	0x0004003b,
	0x0000000c,
	0x0000000d,
	0x00000001,
	0x00040015,
	0x0000000e,
	0x00000020,
	0x00000001,
	0x0004002b,
	0x0000000e,
	0x0000000f,
	0x00000000,
	0x00040020,
	0x00000010,
	0x00000001,
	0x00000007,
	0x00090019,
	0x00000013,
	0x00000006,
	0x00000001,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000001,
	0x00000000,
	0x0003001b,
	0x00000014,
	0x00000013,
	0x00040020,
	0x00000015,
	0x00000000,
	0x00000014,
	0x0004003b,
	0x00000015,
	0x00000016,
	0x00000000,
	0x0004002b,
	0x0000000e,
	0x00000018,
	0x00000001,
	0x00040020,
	0x00000019,
	0x00000001,
	0x0000000a,
	0x00050036,
	0x00000002,
	0x00000004,
	0x00000000,
	0x00000003,
	0x000200f8,
	0x00000005,
	0x00050041,
	0x00000010,
	0x00000011,
	0x0000000d,
	0x0000000f,
	0x0004003d,
	0x00000007,
	0x00000012,
	0x00000011,
	0x0004003d,
	0x00000014,
	0x00000017,
	0x00000016,
	0x00050041,
	0x00000019,
	0x0000001a,
	0x0000000d,
	0x00000018,
	0x0004003d,
	0x0000000a,
	0x0000001b,
	0x0000001a,
	0x00050057,
	0x00000007,
	0x0000001c,
	0x00000017,
	0x0000001b,
	0x00050085,
	0x00000007,
	0x0000001d,
	0x00000012,
	0x0000001c,
	0x0003003e,
	0x00000009,
	0x0000001d,
	0x000100fd,
	0x00010038,
}

//-----------------------------------------------------------------------------
// FUNCTIONS
//-----------------------------------------------------------------------------

// Backend data stored in io.BackendRendererUserData to allow support for multiple Dear ImGui contexts
// It is STRONGLY preferred that you use docking branch with multi-viewports (== single Dear ImGui context + multiple windows) instead of multiple Dear ImGui contexts.
// FIXME: multi-context support is not tested and probably dysfunctional in this backend.
GetBackendData :: proc() -> ^Data {
	return(
		imgui.Gui_GetCurrentContext() != nil ? (^Data)(imgui.Gui_GetIO().BackendRendererUserData) : nil \
	)
}

MemoryType :: proc(properties: vk.MemoryPropertyFlags, type_bits: u32) -> u32 {
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	prop: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(v.PhysicalDevice, &prop)
	for i: u32 = 0; i < prop.memoryTypeCount; i += 1 {
		if properties <= prop.memoryTypes[i].propertyFlags && (type_bits & (1 << i) != 0) {
			return i
		}
	}
	return 0xFFFFFFFF // Unable to find memoryType
}

check_vk_result :: proc(err: vk.Result) {
	bd := GetBackendData()
	if bd == nil {
		return
	}

	v := &bd.VulkanInitInfo
	if v.CheckVkResultFn != nil {
		v.CheckVkResultFn(err)
	}
}

// Same as IM_MEMALIGN(). 'alignment' must be a power of two.
AlignBufferSize :: #force_inline proc(size, alignment: vk.DeviceSize) -> vk.DeviceSize {
	return (size + alignment - 1) & ~(alignment - 1)
}

CreateOrResizeBuffer :: proc(
	buffer: ^vk.Buffer,
	buffer_memory: ^vk.DeviceMemory,
	buffer_size: ^vk.DeviceSize,
	new_size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
) {
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	err: vk.Result
	if buffer^ != 0 {
		vk.DestroyBuffer(v.Device, buffer^, v.Allocator)
	}
	if buffer_memory^ != 0 {
		vk.FreeMemory(v.Device, buffer_memory^, v.Allocator)
	}

	buffer_size_aligned := AlignBufferSize(
		math.max(v.MinAllocationSize, new_size),
		bd.BufferMemoryAlignment,
	)
	buffer_info: vk.BufferCreateInfo = {
		sType       = .BUFFER_CREATE_INFO,
		size        = buffer_size_aligned,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	err = vk.CreateBuffer(v.Device, &buffer_info, v.Allocator, buffer)
	check_vk_result(err)

	req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(v.Device, buffer^, &req)
	bd.BufferMemoryAlignment =
		(bd.BufferMemoryAlignment > req.alignment) ? bd.BufferMemoryAlignment : req.alignment
	alloc_info: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = MemoryType({.HOST_VISIBLE}, req.memoryTypeBits),
	}
	err = vk.AllocateMemory(v.Device, &alloc_info, v.Allocator, buffer_memory)
	check_vk_result(err)

	err = vk.BindBufferMemory(v.Device, buffer^, buffer_memory^, 0)
	check_vk_result(err)
	buffer_size^ = buffer_size_aligned
}

SetupRenderState :: proc(
	draw_data: ^imgui.DrawData,
	pipeline: vk.Pipeline,
	command_buffer: vk.CommandBuffer,
	rb: ^FrameRenderBuffers,
	fb_width, fb_height: i32,
) {
	bd := GetBackendData()

	// Bind pipeline:
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline)

	// Bind Vertex And Index Buffer:
	if draw_data.TotalVtxCount > 0 {
		vertex_buffers := [?]vk.Buffer{rb.VertexBuffer}
		vertex_offset := [?]vk.DeviceSize{0}
		vk.CmdBindVertexBuffers(
			command_buffer,
			0,
			len(vertex_buffers),
			&vertex_buffers[0],
			&vertex_offset[0],
		)
		vk.CmdBindIndexBuffer(
			command_buffer,
			rb.IndexBuffer,
			0,
			size_of(imgui.DrawIdx) == 2 ? .UINT16 : .UINT32,
		)
	}

	// Setup viewport:
	{
		viewport: vk.Viewport = {
			x        = 0,
			y        = 0,
			width    = f32(fb_width),
			height   = f32(fb_height),
			minDepth = 0,
			maxDepth = 1,
		}
		vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	}

	// Setup scale and translation:
	// Our visible imgui space lies from draw_data->DisplayPps (top left) to draw_data->DisplayPos+data_data->DisplaySize (bottom right). DisplayPos is (0,0) for single viewport apps.
	{
		scale := [?]f32{2 / draw_data.DisplaySize.x, 2 / draw_data.DisplaySize.y}
		translate := [?]f32 {
			-1 - draw_data.DisplayPos.x * scale[0],
			-1 - draw_data.DisplayPos.y * scale[1],
		}
		vk.CmdPushConstants(
			command_buffer,
			bd.PipelineLayout,
			{.VERTEX},
			size_of(f32) * 0,
			size_of(scale),
			&scale[0],
		)
		vk.CmdPushConstants(
			command_buffer,
			bd.PipelineLayout,
			{.VERTEX},
			size_of(scale),
			size_of(translate),
			&translate[0],
		)
	}
}

DestroyTexture :: proc(tex: ^imgui.TextureData) {
	if backend_tex := (^Texture)(tex.BackendUserData); backend_tex != nil {
		assert(backend_tex.DescriptorSet == (vk.DescriptorSet)(tex.TexID))
		bd := GetBackendData()
		v := &bd.VulkanInitInfo
		RemoveTexture(backend_tex.DescriptorSet)
		vk.DestroyImageView(v.Device, backend_tex.ImageView, v.Allocator)
		vk.DestroyImage(v.Device, backend_tex.Image, v.Allocator)
		vk.FreeMemory(v.Device, backend_tex.Memory, v.Allocator)
		free(backend_tex, internal_allocator)

		// Clear identifiers and mark as destroyed (in order to allow e.g. calling InvalidateDeviceObjects while running)
		imgui.TextureData_SetTexID(tex, imgui.TextureID_Invalid)
		tex.BackendUserData = nil
	}
	imgui.TextureData_SetStatus(tex, .Destroyed)
}

UpdateTexture :: proc(tex: ^imgui.TextureData) {
	if tex.Status == .OK {
		return
	}
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	err: vk.Result

	if tex.Status == .WantCreate {
		// Create and upload new texture to graphics system
		//IMGUI_DEBUG_LOG("UpdateTexture #%03d: WantCreate %dx%d\n", tex->UniqueID, tex->Width, tex->Height);
		assert(tex.TexID == imgui.TextureID_Invalid && tex.BackendUserData == nil)
		assert(tex.Format == .RGBA32)
		backend_tex := new(Texture, internal_allocator)

		// Create the Image:
		{
			info: vk.ImageCreateInfo = {
				sType = .IMAGE_CREATE_INFO,
				imageType = .D2,
				format = .R8G8B8A8_UNORM,
				extent = {width = u32(tex.Width), height = u32(tex.Height), depth = 1},
				mipLevels = 1,
				arrayLayers = 1,
				samples = {._1},
				tiling = .OPTIMAL,
				usage = {.SAMPLED, .TRANSFER_DST},
				sharingMode = .EXCLUSIVE,
				initialLayout = .UNDEFINED,
			}
			err = vk.CreateImage(v.Device, &info, v.Allocator, &backend_tex.Image)
			check_vk_result(err)
			req: vk.MemoryRequirements
			vk.GetImageMemoryRequirements(v.Device, backend_tex.Image, &req)
			alloc_info: vk.MemoryAllocateInfo = {
				sType           = .MEMORY_ALLOCATE_INFO,
				allocationSize  = max(v.MinAllocationSize, req.size),
				memoryTypeIndex = MemoryType({.DEVICE_LOCAL}, req.memoryTypeBits),
			}
			err = vk.AllocateMemory(v.Device, &alloc_info, v.Allocator, &backend_tex.Memory)
			check_vk_result(err)
			err = vk.BindImageMemory(v.Device, backend_tex.Image, backend_tex.Memory, 0)
			check_vk_result(err)
		}

		// Create the Image View:
		{
			info: vk.ImageViewCreateInfo = {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = backend_tex.Image,
				viewType = .D2,
				format = .R8G8B8A8_UNORM,
				subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
			}
			err = vk.CreateImageView(v.Device, &info, v.Allocator, &backend_tex.ImageView)
			check_vk_result(err)
		}

		// Create the Descriptor Set
		backend_tex.DescriptorSet = AddTexture(
			bd.TexSamplerLinear,
			backend_tex.ImageView,
			.SHADER_READ_ONLY_OPTIMAL,
		)

		// Store identifiers
		imgui.TextureData_SetTexID(tex, transmute(imgui.TextureID)backend_tex.DescriptorSet)
		tex.BackendUserData = backend_tex
	}

	if tex.Status == .WantCreate || tex.Status == .WantUpdates {
		backend_tex := transmute(^Texture)tex.BackendUserData

		// Update full texture or selected blocks. We only ever write to textures regions which have never been used before!
		// This backend choose to use tex->UpdateRect but you can use tex->Updates[] to upload individual regions.
		// We could use the smaller rect on _WantCreate but using the full rect allows us to clear the texture.
		upload_x := tex.Status == .WantCreate ? 0 : tex.UpdateRect.x
		upload_y := tex.Status == .WantCreate ? 0 : tex.UpdateRect.y
		upload_w := tex.Status == .WantCreate ? tex.Width : i32(tex.UpdateRect.w)
		upload_h := tex.Status == .WantCreate ? tex.Height : i32(tex.UpdateRect.h)

		// Create the Upload Buffer:
		upload_buffer_memory: vk.DeviceMemory

		upload_buffer: vk.Buffer
		upload_pitch := upload_w * tex.BytesPerPixel
		upload_size := AlignBufferSize(
			vk.DeviceSize(upload_h * upload_pitch),
			bd.NonCoherentAtomSize,
		)
		{
			buffer_info: vk.BufferCreateInfo = {
				sType       = .BUFFER_CREATE_INFO,
				size        = upload_size,
				usage       = {.TRANSFER_SRC},
				sharingMode = .EXCLUSIVE,
			}
			err = vk.CreateBuffer(v.Device, &buffer_info, v.Allocator, &upload_buffer)
			check_vk_result(err)
			req: vk.MemoryRequirements
			vk.GetBufferMemoryRequirements(v.Device, upload_buffer, &req)
			bd.BufferMemoryAlignment =
				bd.BufferMemoryAlignment > req.alignment ? bd.BufferMemoryAlignment : req.alignment
			alloc_info: vk.MemoryAllocateInfo = {
				sType           = .MEMORY_ALLOCATE_INFO,
				allocationSize  = math.max(v.MinAllocationSize, req.size),
				memoryTypeIndex = MemoryType({.HOST_VISIBLE}, req.memoryTypeBits),
			}
			err = vk.AllocateMemory(v.Device, &alloc_info, v.Allocator, &upload_buffer_memory)
			check_vk_result(err)
			err = vk.BindBufferMemory(v.Device, upload_buffer, upload_buffer_memory, 0)
			check_vk_result(err)
		}

		// Upload to Buffer:
		{
			map_: rawptr
			err = vk.MapMemory(v.Device, upload_buffer_memory, 0, upload_size, nil, &map_)
			check_vk_result(err)
			for y: i32 = 0; y < upload_h; y += 1 {
				mem.copy(
					rawptr(uintptr(map_) + uintptr(upload_pitch * y)),
					imgui.TextureData_GetPixelsAt(tex, i32(upload_x), i32(upload_y) + y),
					int(upload_pitch),
				)
			}
			range := [?]vk.MappedMemoryRange {
				{sType = .MAPPED_MEMORY_RANGE, memory = upload_buffer_memory, size = upload_size},
			}
			err = vk.FlushMappedMemoryRanges(v.Device, len(range), &range[0])
			check_vk_result(err)
			vk.UnmapMemory(v.Device, upload_buffer_memory)
		}

		// Start command buffer
		{
			err = vk.ResetCommandPool(v.Device, bd.TexCommandPool, nil)
			check_vk_result(err)
			begin_info: vk.CommandBufferBeginInfo = {
				sType = .COMMAND_BUFFER_BEGIN_INFO,
				flags = {.ONE_TIME_SUBMIT},
			}
			err = vk.BeginCommandBuffer(bd.TexCommandBuffer, &begin_info)
			check_vk_result(err)
		}

		// Copy to Image:
		{
			upload_barrier := [?]vk.BufferMemoryBarrier {
				{
					sType = .BUFFER_MEMORY_BARRIER,
					srcAccessMask = {.HOST_WRITE},
					dstAccessMask = {.TRANSFER_READ},
					srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					buffer = upload_buffer,
					offset = 0,
					size = upload_size,
				},
			}

			copy_barrier := [?]vk.ImageMemoryBarrier {
				{
					sType = .IMAGE_MEMORY_BARRIER,
					dstAccessMask = {.TRANSFER_WRITE},
					oldLayout = tex.Status == .WantCreate ? .UNDEFINED : .SHADER_READ_ONLY_OPTIMAL,
					newLayout = .TRANSFER_DST_OPTIMAL,
					srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					image = backend_tex.Image,
					subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
				},
			}
			vk.CmdPipelineBarrier(
				bd.TexCommandBuffer,
				{.FRAGMENT_SHADER, .HOST},
				{.TRANSFER},
				nil,
				0,
				nil,
				len(upload_barrier),
				&upload_barrier[0],
				len(copy_barrier),
				&copy_barrier[0],
			)

			region: vk.BufferImageCopy = {
				imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
				imageExtent = {width = u32(upload_w), height = u32(upload_h), depth = 1},
				imageOffset = {x = i32(upload_x), y = i32(upload_y)},
			}
			vk.CmdCopyBufferToImage(
				bd.TexCommandBuffer,
				upload_buffer,
				backend_tex.Image,
				.TRANSFER_DST_OPTIMAL,
				1,
				&region,
			)

			use_barrier := [?]vk.ImageMemoryBarrier {
				{
					sType = .IMAGE_MEMORY_BARRIER,
					srcAccessMask = {.TRANSFER_WRITE},
					dstAccessMask = {.SHADER_READ},
					oldLayout = .TRANSFER_DST_OPTIMAL,
					newLayout = .SHADER_READ_ONLY_OPTIMAL,
					srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
					image = backend_tex.Image,
					subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
				},
			}
			vk.CmdPipelineBarrier(
				bd.TexCommandBuffer,
				{.TRANSFER},
				{.FRAGMENT_SHADER},
				nil,
				0,
				nil,
				0,
				nil,
				len(use_barrier),
				&use_barrier[0],
			)
		}

		// End command buffer
		{
			end_info: vk.SubmitInfo = {
				sType              = .SUBMIT_INFO,
				commandBufferCount = 1,
				pCommandBuffers    = &bd.TexCommandBuffer,
			}
			err = vk.EndCommandBuffer(bd.TexCommandBuffer)
			check_vk_result(err)
			err = vk.QueueSubmit(v.Queue, 1, &end_info, 0)
			check_vk_result(err)
		}

		err = vk.QueueWaitIdle(v.Queue) // FIXME-OPT: Suboptimal!
		check_vk_result(err)
		vk.DestroyBuffer(v.Device, upload_buffer, v.Allocator)
		vk.FreeMemory(v.Device, upload_buffer_memory, v.Allocator)

		imgui.TextureData_SetStatus(tex, .OK)
	}

	if tex.Status == .WantDestroy && tex.UnusedFrames >= i32(bd.VulkanInitInfo.ImageCount) {
		DestroyTexture(tex)
	}
}

CreateShaderModules :: proc(device: vk.Device, allocator: ^vk.AllocationCallbacks) {
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	if bd.ShaderModuleVert == 0 {
		default_vert_info: vk.ShaderModuleCreateInfo = {
			sType    = .SHADER_MODULE_CREATE_INFO,
			codeSize = size_of(__glsl_shader_vert_spv),
			pCode    = &__glsl_shader_vert_spv[0],
		}
		p_vert_info :=
			v.CustomShaderVertCreateInfo.sType == .SHADER_MODULE_CREATE_INFO ? &v.CustomShaderVertCreateInfo : &default_vert_info
		err := vk.CreateShaderModule(device, p_vert_info, allocator, &bd.ShaderModuleVert)
		check_vk_result(err)
	}
	if bd.ShaderModuleFrag == 0 {
		default_frag_info: vk.ShaderModuleCreateInfo = {
			sType    = .SHADER_MODULE_CREATE_INFO,
			codeSize = size_of(__glsl_shader_frag_spv),
			pCode    = &__glsl_shader_frag_spv[0],
		}
		p_frag_info :=
			v.CustomShaderFragCreateInfo.sType == .SHADER_MODULE_CREATE_INFO ? &v.CustomShaderFragCreateInfo : &default_frag_info
		err := vk.CreateShaderModule(device, p_frag_info, allocator, &bd.ShaderModuleFrag)
		check_vk_result(err)
	}
}

CreatePipeline :: proc(
	device: vk.Device,
	allocator: ^vk.AllocationCallbacks,
	pipelineCache: vk.PipelineCache,
	info: ^PipelineInfo,
) -> vk.Pipeline {
	bd := GetBackendData()
	CreateShaderModules(device, allocator)

	stage := [?]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = bd.ShaderModuleVert,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = bd.ShaderModuleFrag,
			pName = "main",
		},
	}

	binding_desc := [?]vk.VertexInputBindingDescription {
		{stride = size_of(imgui.DrawVert), inputRate = .VERTEX},
	}

	attribute_desc := [?]vk.VertexInputAttributeDescription {
		{
			location = 0,
			binding = binding_desc[0].binding,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(imgui.DrawVert, pos)),
		},
		{
			location = 1,
			binding = binding_desc[0].binding,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(imgui.DrawVert, uv)),
		},
		{
			location = 2,
			binding = binding_desc[0].binding,
			format = .R8G8B8A8_UNORM,
			offset = u32(offset_of(imgui.DrawVert, col)),
		},
	}

	vertex_info: vk.PipelineVertexInputStateCreateInfo = {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = len(binding_desc),
		pVertexBindingDescriptions      = &binding_desc[0],
		vertexAttributeDescriptionCount = len(attribute_desc),
		pVertexAttributeDescriptions    = &attribute_desc[0],
	}

	ia_info: vk.PipelineInputAssemblyStateCreateInfo = {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	viewport_info: vk.PipelineViewportStateCreateInfo = {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	raster_info: vk.PipelineRasterizationStateCreateInfo = {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = nil,
		frontFace   = .COUNTER_CLOCKWISE,
		lineWidth   = 1,
	}

	ms_info: vk.PipelineMultisampleStateCreateInfo = {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = info.MSAASamples != nil ? info.MSAASamples : {._1},
	}

	color_attachment := [?]vk.PipelineColorBlendAttachmentState {
		{
			blendEnable = true,
			srcColorBlendFactor = .SRC_ALPHA,
			dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
			colorBlendOp = .ADD,
			srcAlphaBlendFactor = .ONE,
			dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
			alphaBlendOp = .ADD,
			colorWriteMask = {.R, .G, .B, .A},
		},
	}

	depth_info: vk.PipelineDepthStencilStateCreateInfo = {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
	}

	blend_info: vk.PipelineColorBlendStateCreateInfo = {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = len(color_attachment),
		pAttachments    = &color_attachment[0],
	}

	dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state: vk.PipelineDynamicStateCreateInfo = {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(dynamic_states),
		pDynamicStates    = &dynamic_states[0],
	}

	create_info: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		flags               = bd.PipelineCreateFlags,
		stageCount          = len(stage),
		pStages             = &stage[0],
		pVertexInputState   = &vertex_info,
		pInputAssemblyState = &ia_info,
		pViewportState      = &viewport_info,
		pRasterizationState = &raster_info,
		pMultisampleState   = &ms_info,
		pDepthStencilState  = &depth_info,
		pColorBlendState    = &blend_info,
		pDynamicState       = &dynamic_state,
		layout              = bd.PipelineLayout,
		renderPass          = info.RenderPass,
		subpass             = info.Subpass,
	}

	if bd.VulkanInitInfo.UseDynamicRendering {
		assert(
			info.PipelineRenderingCreateInfo.sType == .PIPELINE_RENDERING_CREATE_INFO_KHR,
			"PipelineRenderingCreateInfo::sType must be VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR",
		)
		assert(
			info.PipelineRenderingCreateInfo.pNext == nil,
			"PipelineRenderingCreateInfo::pNext must be nil",
		)
		create_info.pNext = &info.PipelineRenderingCreateInfo
		create_info.renderPass = 0 // Just make sure it's actually nil.
	}
	pipeline: vk.Pipeline
	err := vk.CreateGraphicsPipelines(device, pipelineCache, 1, &create_info, allocator, &pipeline)
	check_vk_result(err)
	return pipeline
}

CreateDeviceObjects :: proc() -> bool {
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	err: vk.Result

	if bd.TexSamplerLinear == 0 {
		// Bilinear sampling is required by default. Set 'io.Fonts->Flags |= ImFontAtlasFlags_NoBakedLines' or 'style.AntiAliasedLinesUseTex = false' to allow point/nearest sampling.
		info: vk.SamplerCreateInfo = {
			sType         = .SAMPLER_CREATE_INFO,
			magFilter     = .LINEAR,
			minFilter     = .LINEAR,
			mipmapMode    = .LINEAR,
			addressModeU  = .CLAMP_TO_EDGE,
			addressModeV  = .CLAMP_TO_EDGE,
			addressModeW  = .CLAMP_TO_EDGE,
			minLod        = -1000,
			maxLod        = 1000,
			maxAnisotropy = 1,
		}
		err = vk.CreateSampler(v.Device, &info, v.Allocator, &bd.TexSamplerLinear)
		check_vk_result(err)
	}

	if bd.DescriptorSetLayout == 0 {
		binding := [?]vk.DescriptorSetLayoutBinding {
			{
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				stageFlags = {.FRAGMENT},
			},
		}
		info: vk.DescriptorSetLayoutCreateInfo = {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = len(binding),
			pBindings    = &binding[0],
		}
		err = vk.CreateDescriptorSetLayout(v.Device, &info, v.Allocator, &bd.DescriptorSetLayout)
		check_vk_result(err)
	}

	if v.DescriptorPoolSize != 0 {
		assert(v.DescriptorPoolSize >= MINIMUM_IMAGE_SAMPLER_POOL_SIZE)
		pool_size: vk.DescriptorPoolSize = {.COMBINED_IMAGE_SAMPLER, v.DescriptorPoolSize}
		pool_info: vk.DescriptorPoolCreateInfo = {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			flags         = {.FREE_DESCRIPTOR_SET},
			maxSets       = v.DescriptorPoolSize,
			poolSizeCount = 1,
			pPoolSizes    = &pool_size,
		}

		err = vk.CreateDescriptorPool(v.Device, &pool_info, v.Allocator, &bd.DescriptorPool)
		check_vk_result(err)
	}

	if bd.PipelineLayout == 0 {
		// Constants: we are using 'vec2 offset' and 'vec2 scale' instead of a full 3d projection matrix
		push_constants := [?]vk.PushConstantRange {
			{stageFlags = {.VERTEX}, offset = size_of(f32) * 0, size = size_of(f32) * 4},
		}
		set_layout := [?]vk.DescriptorSetLayout{bd.DescriptorSetLayout}
		layout_info: vk.PipelineLayoutCreateInfo = {
			sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount         = len(set_layout),
			pSetLayouts            = &set_layout[0],
			pushConstantRangeCount = len(push_constants),
			pPushConstantRanges    = &push_constants[0],
		}
		err = vk.CreatePipelineLayout(v.Device, &layout_info, v.Allocator, &bd.PipelineLayout)
		check_vk_result(err)
	}

	// Create pipeline
	create_main_pipeline := v.PipelineInfoMain.RenderPass != 0
	create_main_pipeline |=
		v.UseDynamicRendering &&
		v.PipelineInfoMain.PipelineRenderingCreateInfo.sType == .PIPELINE_RENDERING_CREATE_INFO
	if create_main_pipeline {
		CreateMainPipeline(&v.PipelineInfoMain)
	}

	// Create command pool/buffer for texture upload
	if bd.TexCommandPool == 0 {
		info: vk.CommandPoolCreateInfo = {
			sType            = .COMMAND_POOL_CREATE_INFO,
			flags            = nil,
			queueFamilyIndex = v.QueueFamily,
		}
		err = vk.CreateCommandPool(v.Device, &info, v.Allocator, &bd.TexCommandPool)
		check_vk_result(err)
	}
	if bd.TexCommandBuffer == nil {
		info: vk.CommandBufferAllocateInfo = {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = bd.TexCommandPool,
			commandBufferCount = 1,
		}
		err = vk.AllocateCommandBuffers(v.Device, &info, &bd.TexCommandBuffer)
		check_vk_result(err)
	}

	return true
}

CreateMainPipeline :: proc(pipeline_info_in: ^PipelineInfo) {
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	if bd.Pipeline != 0 {
		vk.DestroyPipeline(v.Device, bd.Pipeline, v.Allocator)
		bd.Pipeline = 0
	}
	pipeline_info := &v.PipelineInfoMain
	if pipeline_info != pipeline_info_in {
		pipeline_info^ = pipeline_info_in^
	}

	pipeline_rendering_create_info := &pipeline_info.PipelineRenderingCreateInfo
	if v.UseDynamicRendering && pipeline_rendering_create_info.pColorAttachmentFormats != nil {
		// Deep copy buffer to reduce error-rate for end user (#8282)
		formats: imgui.Vector(vk.Format)
		defer imgui.VectorClear(&formats)

		imgui.VectorResize(&formats, int(pipeline_rendering_create_info.colorAttachmentCount))
		mem.copy(
			formats.Data,
			pipeline_rendering_create_info.pColorAttachmentFormats,
			imgui.VectorSizeInBytes(formats),
		)
		imgui.VectorSwap(&formats, &bd.PipelineRenderingCreateInfoColorAttachmentFormats)
		pipeline_rendering_create_info.pColorAttachmentFormats =
			bd.PipelineRenderingCreateInfoColorAttachmentFormats.Data
	}
	bd.Pipeline = CreatePipeline(v.Device, v.Allocator, v.PipelineCache, pipeline_info)
}

DestroyDeviceObjects :: proc() {
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	DestroyAllViewportsRenderBuffers(v.Device, v.Allocator)

	// Destroy all textures
	texs := &imgui.Gui_GetPlatformIO().Textures
	for &tex in texs.Data[:texs.Size] {
		if tex.RefCount == 1 {
			DestroyTexture(tex)
		}
	}

	if bd.TexCommandBuffer != nil {
		vk.FreeCommandBuffers(v.Device, bd.TexCommandPool, 1, &bd.TexCommandBuffer)
		bd.TexCommandBuffer = nil
	}
	if bd.TexCommandPool != 0 {
		vk.DestroyCommandPool(v.Device, bd.TexCommandPool, v.Allocator)
		bd.TexCommandPool = 0
	}
	if bd.TexSamplerLinear != 0 {
		vk.DestroySampler(v.Device, bd.TexSamplerLinear, v.Allocator)
		bd.TexSamplerLinear = 0
	}
	if bd.ShaderModuleVert != 0 {
		vk.DestroyShaderModule(v.Device, bd.ShaderModuleVert, v.Allocator)
		bd.ShaderModuleVert = 0
	}
	if bd.ShaderModuleFrag != 0 {
		vk.DestroyShaderModule(v.Device, bd.ShaderModuleFrag, v.Allocator)
		bd.ShaderModuleFrag = 0
	}
	if bd.DescriptorSetLayout != 0 {
		vk.DestroyDescriptorSetLayout(v.Device, bd.DescriptorSetLayout, v.Allocator)
		bd.DescriptorSetLayout = 0
	}
	if bd.PipelineLayout != 0 {
		vk.DestroyPipelineLayout(v.Device, bd.PipelineLayout, v.Allocator)
		bd.PipelineLayout = 0
	}
	if bd.Pipeline != 0 {
		vk.DestroyPipeline(v.Device, bd.Pipeline, v.Allocator)
		bd.Pipeline = 0
	}
	if bd.PipelineForViewports != 0 {
		vk.DestroyPipeline(v.Device, bd.PipelineForViewports, v.Allocator)
		bd.PipelineForViewports = 0
	}
	if bd.DescriptorPool != 0 {
		vk.DestroyDescriptorPool(v.Device, bd.DescriptorPool, v.Allocator)
		bd.DescriptorPool = 0
	}
}

// If unspecified by user, assume that ApiVersion == HeaderVersion
// We don't care about other versions than 1.3 for our checks, so don't need to make this exhaustive (e.g. with all #ifdef VK_VERSION_1_X checks)
GetDefaultApiVersion :: proc() -> u32 {
	return vk.API_VERSION_1_4
}

// Register a texture by creating a descriptor
// FIXME: This is experimental in the sense that we are unsure how to best design/tackle this problem, please post to https://github.com/ocornut/imgui/pull/914 if you have suggestions.
AddTexture :: proc(
	sampler: vk.Sampler,
	image_view: vk.ImageView,
	image_layout: vk.ImageLayout,
) -> vk.DescriptorSet {
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	pool := bd.DescriptorPool != 0 ? bd.DescriptorPool : v.DescriptorPool

	// Create Descriptor Set:
	descriptor_set: vk.DescriptorSet
	{
		alloc_info: vk.DescriptorSetAllocateInfo = {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = pool,
			descriptorSetCount = 1,
			pSetLayouts        = &bd.DescriptorSetLayout,
		}
		err := vk.AllocateDescriptorSets(v.Device, &alloc_info, &descriptor_set)
		check_vk_result(err)
	}

	// Update the Descriptor Set:
	{
		desc_image := [?]vk.DescriptorImageInfo {
			{sampler = sampler, imageView = image_view, imageLayout = image_layout},
		}
		write_desc := [?]vk.WriteDescriptorSet {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = descriptor_set,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = len(desc_image),
				pImageInfo = &desc_image[0],
			},
		}
		vk.UpdateDescriptorSets(v.Device, len(write_desc), &write_desc[0], 0, nil)
	}
	return descriptor_set
}

RemoveTexture :: proc(descriptor_set: vk.DescriptorSet) {
	descriptor_set := descriptor_set
	bd := GetBackendData()
	v := &bd.VulkanInitInfo
	pool := bd.DescriptorPool != 0 ? bd.DescriptorPool : v.DescriptorPool
	vk.FreeDescriptorSets(v.Device, pool, 1, &descriptor_set)
}

DestroyFrameRenderBuffers :: proc(
	device: vk.Device,
	buffers: ^FrameRenderBuffers,
	allocator: ^vk.AllocationCallbacks,
) {
	if buffers.VertexBuffer != 0 {
		vk.DestroyBuffer(device, buffers.VertexBuffer, allocator)
		buffers.VertexBuffer = 0
	}
	if buffers.VertexBufferMemory != 0 {
		vk.FreeMemory(device, buffers.VertexBufferMemory, allocator)
		buffers.VertexBufferMemory = 0
	}
	if buffers.IndexBuffer != 0 {
		vk.DestroyBuffer(device, buffers.IndexBuffer, allocator)
		buffers.IndexBuffer = 0
	}
	if buffers.IndexBufferMemory != 0 {
		vk.FreeMemory(device, buffers.IndexBufferMemory, allocator)
		buffers.IndexBufferMemory = 0
	}
	buffers.VertexBufferSize = 0
	buffers.IndexBufferSize = 0
}

DestroyWindowRenderBuffers :: proc(
	device: vk.Device,
	buffers: ^WindowRenderBuffers,
	allocator: ^vk.AllocationCallbacks,
) {
	for n: u32 = 0; n < buffers.Count; n += 1 {
		DestroyFrameRenderBuffers(device, &buffers.FrameRenderBuffers.Data[n], allocator)
	}
	imgui.VectorClear(&buffers.FrameRenderBuffers)
	buffers.Index = 0
	buffers.Count = 0
}

//-------------------------------------------------------------------------
// Internal / Miscellaneous Vulkan Helpers
// (Used by example's main.cpp. Used by multi-viewport features. PROBABLY NOT used by your own engine/app.)
//-------------------------------------------------------------------------
// You probably do NOT need to use or care about those functions.
// Those functions only exist because:
//   1) they facilitate the readability and maintenance of the multiple main.cpp examples files.
//   2) the upcoming multi-viewport feature will need them internally.
// Generally we avoid exposing any kind of superfluous high-level helpers in the backends,
// but it is too much code to duplicate everywhere so we exceptionally expose them.
//
// Your engine/app will likely _already_ have code to setup all that stuff (swap chain, render pass, frame buffers, etc.).
// You may read this code to learn about Vulkan, but it is recommended you use your own custom tailored code to do equivalent work.
// (The ImGui_ImplVulkanH_XXX functions do not interact with any of the state used by the regular ImGui_ImplVulkan_XXX functions)
//-------------------------------------------------------------------------

CreateWindowCommandBuffers :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	wd: ^Window,
	queue_family: u32,
	allocator: ^vk.AllocationCallbacks,
) {
	assert(physical_device != nil && device != nil)

	// Create Command Buffers
	err: vk.Result
	for i: u32 = 0; i < wd.ImageCount; i += 1 {
		fd := &wd.Frames.Data[i]
		{
			info: vk.CommandPoolCreateInfo = {
				sType            = .COMMAND_POOL_CREATE_INFO,
				flags            = nil,
				queueFamilyIndex = queue_family,
			}
			err = vk.CreateCommandPool(device, &info, allocator, &fd.CommandPool)
			check_vk_result(err)
		}
		{
			info: vk.CommandBufferAllocateInfo = {
				sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
				commandPool        = fd.CommandPool,
				level              = .PRIMARY,
				commandBufferCount = 1,
			}
			err = vk.AllocateCommandBuffers(device, &info, &fd.CommandBuffer)
			check_vk_result(err)
		}
		{
			info: vk.FenceCreateInfo = {
				sType = .FENCE_CREATE_INFO,
				flags = {.SIGNALED},
			}
			err = vk.CreateFence(device, &info, allocator, &fd.Fence)
			check_vk_result(err)
		}
	}

	for i: u32 = 0; i < wd.SemaphoreCount; i += 1 {
		fsd := &wd.FrameSemaphores.Data[i]
		{
			info: vk.SemaphoreCreateInfo = {
				sType = .SEMAPHORE_CREATE_INFO,
			}
			err = vk.CreateSemaphore(device, &info, allocator, &fsd.ImageAcquiredSemaphore)
			check_vk_result(err)
			err = vk.CreateSemaphore(device, &info, allocator, &fsd.RenderCompleteSemaphore)
			check_vk_result(err)
		}
	}
}

// Also destroy old swap chain and in-flight frames data, if any.
CreateWindowSwapChain :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	wd: ^Window,
	allocator: ^vk.AllocationCallbacks,
	w, h: i32,
	min_image_count: u32,
	image_usage: vk.ImageUsageFlags,
) {
	err: vk.Result
	old_swapchain := wd.Swapchain
	wd.Swapchain = 0
	err = vk.DeviceWaitIdle(device)
	check_vk_result(err)

	// We don't use ImGui_ImplVulkanH_DestroyWindow() because we want to preserve the old swapchain to create the new one.
	// Destroy old Framebuffer
	for i: u32 = 0; i < wd.ImageCount; i += 1 {
		DestroyFrame(device, &wd.Frames.Data[i], allocator)
	}
	for i: u32 = 0; i < wd.SemaphoreCount; i += 1 {
		DestroyFrameSemaphores(device, &wd.FrameSemaphores.Data[i], allocator)
	}
	imgui.VectorClear(&wd.Frames)
	imgui.VectorClear(&wd.FrameSemaphores)
	wd.ImageCount = 0
	if wd.RenderPass != 0 {
		vk.DestroyRenderPass(device, wd.RenderPass, allocator)
	}

	// If min image count was not specified, request different count of images dependent on selected present mode
	min_image_count := min_image_count
	if min_image_count == 0 {
		min_image_count = GetMinImageCountFromPresentMode(wd.PresentMode)
	}

	// Create Swapchain
	{
		cap: vk.SurfaceCapabilitiesKHR
		err = vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, wd.Surface, &cap)
		check_vk_result(err)

		info: vk.SwapchainCreateInfoKHR = {
			sType            = .SWAPCHAIN_CREATE_INFO_KHR,
			surface          = wd.Surface,
			minImageCount    = min_image_count,
			imageFormat      = wd.SurfaceFormat.format,
			imageColorSpace  = wd.SurfaceFormat.colorSpace,
			imageArrayLayers = 1,
			imageUsage       = ({.COLOR_ATTACHMENT} + image_usage),
			imageSharingMode = .EXCLUSIVE, // Assume that graphics family == present family
			preTransform     = .IDENTITY in cap.supportedTransforms ? {.IDENTITY} : cap.currentTransform,
		}
		if .OPAQUE in cap.supportedCompositeAlpha {
			info.compositeAlpha = {.OPAQUE}
		} else if .INHERIT in cap.supportedCompositeAlpha {
			info.compositeAlpha = {.INHERIT}
		} else {
			assert(false, "No supported composite alpha mode found!")
		}
		info.presentMode = wd.PresentMode
		info.clipped = true
		info.oldSwapchain = old_swapchain
		if info.minImageCount < cap.minImageCount {
			info.minImageCount = cap.minImageCount
		} else if cap.maxImageCount != 0 && info.minImageCount > cap.maxImageCount {
			info.minImageCount = cap.maxImageCount
		}

		if cap.currentExtent.width == 0xffffffff {
			info.imageExtent.width = u32(w)
			wd.Width = w
			info.imageExtent.height = u32(h)
			wd.Height = h
		} else {
			info.imageExtent.width = cap.currentExtent.width
			wd.Width = i32(cap.currentExtent.width)
			info.imageExtent.height = cap.currentExtent.height
			wd.Height = i32(cap.currentExtent.height)
		}
		err = vk.CreateSwapchainKHR(device, &info, allocator, &wd.Swapchain)
		check_vk_result(err)
		err = vk.GetSwapchainImagesKHR(device, wd.Swapchain, &wd.ImageCount, nil)
		check_vk_result(err)
		backbuffers: [16]vk.Image
		assert(wd.ImageCount >= min_image_count)
		assert(wd.ImageCount < len(backbuffers))
		err = vk.GetSwapchainImagesKHR(device, wd.Swapchain, &wd.ImageCount, &backbuffers[0])
		check_vk_result(err)

		wd.SemaphoreCount = wd.ImageCount + 1
		imgui.VectorResize(&wd.Frames, int(wd.ImageCount))
		imgui.VectorResize(&wd.FrameSemaphores, int(wd.SemaphoreCount))
		mem.zero(wd.Frames.Data, imgui.VectorSizeInBytes(wd.Frames))
		mem.zero(wd.FrameSemaphores.Data, imgui.VectorSizeInBytes(wd.FrameSemaphores))
		for i: u32 = 0; i < wd.ImageCount; i += 1 {
			wd.Frames.Data[i].Backbuffer = backbuffers[i]
		}
	}
	if old_swapchain != 0 {
		vk.DestroySwapchainKHR(device, old_swapchain, allocator)
	}

	// Create the Render Pass
	if !wd.UseDynamicRendering {
		attachment := wd.AttachmentDesc
		if attachment.format == .UNDEFINED {
			attachment.format = wd.SurfaceFormat.format
		}
		color_attachment: vk.AttachmentReference = {
			attachment = 0,
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}
		subpass: vk.SubpassDescription = {
			pipelineBindPoint    = .GRAPHICS,
			colorAttachmentCount = 1,
			pColorAttachments    = &color_attachment,
		}
		dependency: vk.SubpassDependency = {
			srcSubpass    = vk.SUBPASS_EXTERNAL,
			dstSubpass    = 0,
			srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = nil,
			dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		}
		info: vk.RenderPassCreateInfo = {
			sType           = .RENDER_PASS_CREATE_INFO,
			attachmentCount = 1,
			pAttachments    = &attachment,
			subpassCount    = 1,
			pSubpasses      = &subpass,
			dependencyCount = 1,
			pDependencies   = &dependency,
		}
		err = vk.CreateRenderPass(device, &info, allocator, &wd.RenderPass)
		check_vk_result(err)

		// We do not create a pipeline by default as this is also used by examples' main.cpp,
		// but secondary viewport in multi-viewport mode may want to create one with:
		//ImGui_ImplVulkan_CreatePipeline(device, allocator, VK_NULL_HANDLE, wd->RenderPass, VK_SAMPLE_COUNT_1_BIT, &wd->Pipeline, v->Subpass);
	}

	// Create The Image Views
	{
		info: vk.ImageViewCreateInfo = {
			sType = .IMAGE_VIEW_CREATE_INFO,
			viewType = .D2,
			format = wd.SurfaceFormat.format,
			components = {r = .R, g = .G, b = .B, a = .A},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		for i: u32 = 0; i < wd.ImageCount; i += 1 {
			fd := &wd.Frames.Data[i]
			info.image = fd.Backbuffer
			err = vk.CreateImageView(device, &info, allocator, &fd.BackbufferView)
			check_vk_result(err)
		}
	}

	// Create Framebuffer
	if !wd.UseDynamicRendering {
		attachment: [1]vk.ImageView
		info: vk.FramebufferCreateInfo = {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = wd.RenderPass,
			attachmentCount = 1,
			pAttachments    = &attachment[0],
			width           = u32(wd.Width),
			height          = u32(wd.Height),
			layers          = 1,
		}
		for i: u32 = 0; i < wd.ImageCount; i += 1 {
			fd := &wd.Frames.Data[i]
			attachment[0] = fd.BackbufferView
			err = vk.CreateFramebuffer(device, &info, allocator, &fd.Framebuffer)
			check_vk_result(err)
		}
	}
}

DestroyFrame :: proc(device: vk.Device, fd: ^Frame, allocator: ^vk.AllocationCallbacks) {
	vk.DestroyFence(device, fd.Fence, allocator)
	vk.FreeCommandBuffers(device, fd.CommandPool, 1, &fd.CommandBuffer)
	vk.DestroyCommandPool(device, fd.CommandPool, allocator)
	fd.Fence = 0
	fd.CommandBuffer = nil
	fd.CommandPool = 0

	vk.DestroyImageView(device, fd.BackbufferView, allocator)
	vk.DestroyFramebuffer(device, fd.Framebuffer, allocator)
}

DestroyFrameSemaphores :: proc(
	device: vk.Device,
	fsd: ^FrameSemaphores,
	allocator: ^vk.AllocationCallbacks,
) {
	vk.DestroySemaphore(device, fsd.ImageAcquiredSemaphore, allocator)
	vk.DestroySemaphore(device, fsd.RenderCompleteSemaphore, allocator)
	fsd.ImageAcquiredSemaphore = 0
	fsd.RenderCompleteSemaphore = 0
}

DestroyAllViewportsRenderBuffers :: proc(device: vk.Device, allocator: ^vk.AllocationCallbacks) {
	platform_io := imgui.Gui_GetPlatformIO()
	for n: i32 = 0; n < platform_io.Viewports.Size; n += 1 {
		if vd := (^ViewportData)(platform_io.Viewports.Data[n].RendererUserData); vd != nil {
			DestroyWindowRenderBuffers(device, &vd.RenderBuffers, allocator)
		}
	}
}

// //--------------------------------------------------------------------------------------------------------
// // MULTI-VIEWPORT / PLATFORM INTERFACE SUPPORT
// // This is an _advanced_ and _optional_ feature, allowing the backend to create and handle multiple viewports simultaneously.
// // If you are new to dear imgui or creating a new binding for dear imgui, it is recommended that you completely ignore this section first..
// //--------------------------------------------------------------------------------------------------------

CreateWindow :: proc "c" (viewport: ^imgui.GuiViewport) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := new_viewport_data()
	wd := &vd.Window
	v := &bd.VulkanInitInfo

	// Create surface
	platform_io := imgui.Gui_GetPlatformIO()
	err := (vk.Result)(
		platform_io.Platform_CreateVkSurface(
			viewport,
			transmute(u64)(v.Instance),
			v.Allocator,
			(^u64)(&wd.Surface),
		),
	)
	check_vk_result(err)

	// Check if surface creation failed
	if err != .SUCCESS || wd.Surface == 0 {
		free(vd, internal_allocator)
		return
	}

	// Check for WSI support
	res: b32
	vk.GetPhysicalDeviceSurfaceSupportKHR(v.PhysicalDevice, v.QueueFamily, wd.Surface, &res)
	if res != true {
		vk.DestroySurfaceKHR(v.Instance, wd.Surface, v.Allocator) // Error: no WSI support on physical device, clean up and return
		free(vd, internal_allocator)
		return
	}
	viewport.RendererUserData = vd

	// Select Surface Format
	pipeline_info := &v.PipelineInfoForViewports
	requestSurfaceImageFormats: imgui.Vector(vk.Format)
	defer imgui.VectorClear(&requestSurfaceImageFormats)
	for n: u32 = 0; n < pipeline_info.PipelineRenderingCreateInfo.colorAttachmentCount; n += 1 {
		imgui.VectorPushBack(
			&requestSurfaceImageFormats,
			pipeline_info.PipelineRenderingCreateInfo.pColorAttachmentFormats[n],
		)
	}

	defaultFormats :: [?]vk.Format{.B8G8R8A8_UNORM, .R8G8B8A8_UNORM, .B8G8R8_UNORM, .R8G8B8_UNORM}
	for format in defaultFormats {
		imgui.VectorPushBack(&requestSurfaceImageFormats, format)
	}

	requestSurfaceColorSpace := vk.ColorSpaceKHR.SRGB_NONLINEAR
	wd.SurfaceFormat = SelectSurfaceFormat(
		v.PhysicalDevice,
		wd.Surface,
		requestSurfaceImageFormats.Data,
		i32(requestSurfaceImageFormats.Size),
		requestSurfaceColorSpace,
	)

	// Select Present Mode
	// FIXME-VULKAN: Even thought mailbox seems to get us maximum framerate with a single window, it halves framerate with a second window etc. (w/ Nvidia and SDK 1.82.1)
	present_modes := [?]vk.PresentModeKHR{.MAILBOX, .IMMEDIATE, .FIFO}
	wd.PresentMode = SelectPresentMode(
		v.PhysicalDevice,
		wd.Surface,
		&present_modes[0],
		len(present_modes),
	)
	//printf("[vulkan] Secondary window selected PresentMode = %d\n", wd->PresentMode);

	// Create SwapChain, RenderPass, Framebuffer, etc.
	wd.UseDynamicRendering = v.UseDynamicRendering
	wd.AttachmentDesc.loadOp = .NoRendererClear in viewport.Flags ? .DONT_CARE : .CLEAR
	CreateOrResizeWindow(
		v.Instance,
		v.PhysicalDevice,
		v.Device,
		wd,
		v.QueueFamily,
		v.Allocator,
		i32(viewport.Size.x),
		i32(viewport.Size.y),
		v.MinImageCount,
		pipeline_info.SwapChainImageUsage,
	)
	vd.WindowOwned = true

	// Create pipeline (shared by all secondary viewports)
	if bd.PipelineForViewports == 0 {
		if wd.UseDynamicRendering {
			pipeline_info.PipelineRenderingCreateInfo.sType = .PIPELINE_RENDERING_CREATE_INFO
			pipeline_info.PipelineRenderingCreateInfo.colorAttachmentCount = 1
			pipeline_info.PipelineRenderingCreateInfo.pColorAttachmentFormats = &wd.SurfaceFormat.format
		} else {
			pipeline_info.RenderPass = wd.RenderPass
		}
		bd.PipelineForViewports = CreatePipeline(
			v.Device,
			v.Allocator,
			0,
			&v.PipelineInfoForViewports,
		)
	}
}

DestroyWindow_Internal :: proc "c" (viewport: ^imgui.GuiViewport) {
	context = runtime.default_context()
	// The main viewport (owned by the application) will always have RendererUserData == 0 since we didn't create the data for it.
	bd := GetBackendData()
	if vd := (^ViewportData)(viewport.RendererUserData); vd != nil {
		v := &bd.VulkanInitInfo
		if vd.WindowOwned {
			DestroyWindow(v.Instance, v.Device, &vd.Window, v.Allocator)
			vk.DestroySurfaceKHR(v.Instance, vd.Window.Surface, v.Allocator)
		}
		DestroyWindowRenderBuffers(v.Device, &vd.RenderBuffers, v.Allocator)
		free(vd, internal_allocator)
	}
	viewport.RendererUserData = nil
}

SetWindowSize :: proc "c" (viewport: ^imgui.GuiViewport, size: imgui.Vec2) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := (^ViewportData)(viewport.RendererUserData)
	if vd == nil { 	// This is nullptr for the main viewport (which is left to the user/app to handle)
		return
	}
	v := &bd.VulkanInitInfo
	wd := &vd.Window
	wd.AttachmentDesc.loadOp = .NoRendererClear in viewport.Flags ? .DONT_CARE : .CLEAR
	CreateOrResizeWindow(
		v.Instance,
		v.PhysicalDevice,
		v.Device,
		&vd.Window,
		v.QueueFamily,
		v.Allocator,
		i32(size.x),
		i32(size.y),
		v.MinImageCount,
		v.PipelineInfoForViewports.SwapChainImageUsage,
	)
}

RenderWindow :: proc "c" (viewport: ^imgui.GuiViewport, _: rawptr) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := (^ViewportData)(viewport.RendererUserData)
	if vd == nil {
		return
	}
	wd := &vd.Window
	v := &bd.VulkanInitInfo
	err: vk.Result

	if vd.SwapChainNeedRebuild || vd.SwapChainSuboptimal {
		CreateOrResizeWindow(
			v.Instance,
			v.PhysicalDevice,
			v.Device,
			wd,
			v.QueueFamily,
			v.Allocator,
			i32(viewport.Size.x),
			i32(viewport.Size.y),
			v.MinImageCount,
			v.PipelineInfoForViewports.SwapChainImageUsage,
		)
		vd.SwapChainNeedRebuild = false
		vd.SwapChainSuboptimal = false
	}

	fd: ^Frame
	fsd := &wd.FrameSemaphores.Data[wd.SemaphoreIndex]
	{
		{
			err = vk.AcquireNextImageKHR(
				v.Device,
				wd.Swapchain,
				max(u64),
				fsd.ImageAcquiredSemaphore,
				0,
				&wd.FrameIndex,
			)
			#partial switch err {
			case .ERROR_OUT_OF_DATE_KHR:
				vd.SwapChainNeedRebuild = true // Since we are not going to swap this frame anyway, it's ok that recreation happens on next frame.
				return
			case .SUBOPTIMAL_KHR:
				vd.SwapChainSuboptimal = true
			case:
				check_vk_result(err)
			}
			fd = &wd.Frames.Data[wd.FrameIndex]
		}
		for {
			err = vk.WaitForFences(v.Device, 1, &fd.Fence, true, 100)
			if err == .SUCCESS {break}
			if err == .TIMEOUT {continue}
			check_vk_result(err)
		}
		{
			err = vk.ResetCommandPool(v.Device, fd.CommandPool, nil)
			check_vk_result(err)
			info: vk.CommandBufferBeginInfo = {
				sType = .COMMAND_BUFFER_BEGIN_INFO,
				flags = {.ONE_TIME_SUBMIT},
			}
			err = vk.BeginCommandBuffer(fd.CommandBuffer, &info)
			check_vk_result(err)
		}
		{
			// clear_color := imgui.Vec4{0, 0, 0, 1}
			// mem.copy(&wd.ClearValue.color.float32[0], &clear_color, 4 * size_of(f32))
			wd.ClearValue.color.float32 = {0, 0, 0, 1}
		}
		if v.UseDynamicRendering {
			// Transition swapchain image to a layout suitable for drawing.
			barrier: vk.ImageMemoryBarrier = {
				sType = .IMAGE_MEMORY_BARRIER,
				dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
				oldLayout = .PRESENT_SRC_KHR,
				newLayout = .COLOR_ATTACHMENT_OPTIMAL,
				image = fd.Backbuffer,
				subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
			}
			vk.CmdPipelineBarrier(
				fd.CommandBuffer,
				{.COLOR_ATTACHMENT_OUTPUT},
				{.COLOR_ATTACHMENT_OUTPUT},
				nil,
				0,
				nil,
				0,
				nil,
				1,
				&barrier,
			)

			attachmentInfo: vk.RenderingAttachmentInfo = {
				sType       = .RENDERING_ATTACHMENT_INFO,
				imageView   = fd.BackbufferView,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				resolveMode = nil,
				loadOp      = .CLEAR,
				storeOp     = .STORE,
				clearValue  = wd.ClearValue,
			}

			renderingInfo: vk.RenderingInfo = {
				sType = .RENDERING_INFO_KHR,
				renderArea = {extent = {width = u32(wd.Width), height = u32(wd.Height)}},
				layerCount = 1,
				viewMask = 0,
				colorAttachmentCount = 1,
				pColorAttachments = &attachmentInfo,
			}

			vk.CmdBeginRendering(fd.CommandBuffer, &renderingInfo)
		} else {
			info: vk.RenderPassBeginInfo = {
				sType = .RENDER_PASS_BEGIN_INFO,
				renderPass = wd.RenderPass,
				framebuffer = fd.Framebuffer,
				renderArea = {extent = {width = u32(wd.Width), height = u32(wd.Height)}},
				clearValueCount = .NoRendererClear in viewport.Flags ? 0 : 1,
				pClearValues = .NoRendererClear in viewport.Flags ? nil : &wd.ClearValue,
			}
			vk.CmdBeginRenderPass(fd.CommandBuffer, &info, .INLINE)
		}
	}

	RenderDrawData(viewport.DrawData, fd.CommandBuffer, bd.PipelineForViewports)

	{
		if v.UseDynamicRendering {
			vk.CmdEndRenderingKHR(fd.CommandBuffer)

			// Transition image to a layout suitable for presentation
			barrier: vk.ImageMemoryBarrier = {
				sType = .IMAGE_MEMORY_BARRIER,
				srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
				oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
				newLayout = .PRESENT_SRC_KHR,
				image = fd.Backbuffer,
				subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
			}
			vk.CmdPipelineBarrier(
				fd.CommandBuffer,
				{.COLOR_ATTACHMENT_OUTPUT},
				{.BOTTOM_OF_PIPE},
				nil,
				0,
				nil,
				0,
				nil,
				1,
				&barrier,
			)
		} else {
			vk.CmdEndRenderPass(fd.CommandBuffer)
		}
		{
			wait_stage: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT}
			info: vk.SubmitInfo = {
				sType                = .SUBMIT_INFO,
				waitSemaphoreCount   = 1,
				pWaitSemaphores      = &fsd.ImageAcquiredSemaphore,
				pWaitDstStageMask    = &wait_stage,
				commandBufferCount   = 1,
				pCommandBuffers      = &fd.CommandBuffer,
				signalSemaphoreCount = 1,
				pSignalSemaphores    = &fsd.RenderCompleteSemaphore,
			}

			err = vk.EndCommandBuffer(fd.CommandBuffer)
			check_vk_result(err)
			err = vk.ResetFences(v.Device, 1, &fd.Fence)
			check_vk_result(err)
			err = vk.QueueSubmit(v.Queue, 1, &info, fd.Fence)
			check_vk_result(err)
		}
	}
}

SwapBuffers :: proc "c" (viewport: ^imgui.GuiViewport, _: rawptr) {
	context = runtime.default_context()
	bd := GetBackendData()
	vd := (^ViewportData)(viewport.RendererUserData)
	if vd == nil {
		return
	}
	wd := &vd.Window
	v := &bd.VulkanInitInfo

	if vd.SwapChainNeedRebuild { 	// Frame data became invalid in the middle of rendering
		return
	}

	err: vk.Result
	present_index := wd.FrameIndex

	fsd := &wd.FrameSemaphores.Data[wd.SemaphoreIndex]
	info: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &fsd.RenderCompleteSemaphore,
		swapchainCount     = 1,
		pSwapchains        = &wd.Swapchain,
		pImageIndices      = &present_index,
	}
	err = vk.QueuePresentKHR(v.Queue, &info)
	#partial switch err {
	case .ERROR_OUT_OF_DATE_KHR:
		vd.SwapChainNeedRebuild = true
		return
	case .SUBOPTIMAL_KHR:
		vd.SwapChainSuboptimal = true
	case:
		check_vk_result(err)
	}
	wd.SemaphoreIndex = (wd.SemaphoreIndex + 1) % wd.SemaphoreCount // Now we can use the next set of semaphores
}

InitMultiViewportSupport :: proc() {
	platform_io := imgui.Gui_GetPlatformIO()
	if .PlatformHasViewports in imgui.Gui_GetIO().BackendFlags {
		assert(
			platform_io.Platform_CreateVkSurface != nil,
			"Platform needs to setup the CreateVkSurface handler.",
		)
	}
	platform_io.Renderer_CreateWindow = CreateWindow
	platform_io.Renderer_DestroyWindow = DestroyWindow_Internal
	platform_io.Renderer_SetWindowSize = SetWindowSize
	platform_io.Renderer_RenderWindow = RenderWindow
	platform_io.Renderer_SwapBuffers = SwapBuffers
}

ShutdownMultiViewportSupport :: #force_inline proc() {
	imgui.Gui_DestroyPlatformWindows()
}

