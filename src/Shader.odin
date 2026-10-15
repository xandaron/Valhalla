package Valhalla

import "base:runtime"
import "base:intrinsics"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import vk "vendor:vulkan"
import slang "./slang"

Shader_Error :: enum {
	None,
	Compiler_Unavailable,
	Module_Load_Failed,
	Entry_Point_Not_Found,
	Link_Failed,
	Code_Generation_Failed,
	Invalid_SPIR_V,
	Invalid_Stage_Combination,
	Pipeline_Creation_Failed,
	Resource_Not_In_Heap,
	Too_Many_Bindings,
	Unsupported_Stage,
	Pipeline_Cache_Creation_Failed,
	Pipeline_Cache_File_Read_Failed,
	Pipeline_Cache_Incompatible,
	Pipeline_Cache_Write_Failed,
}

SHADER_BINDING_CAPACITY :: TABLE_CHUNK_SIZE / size_of(u32) - TABLE_HEADER_WORDS

MAX_COLOUR_ATTACHMENTS :: 8

Index_Type :: enum {
	U32,
	U16,
}

Shader_Stage :: enum {
	Vertex,
	Tessellation_Control,
	Tessellation_Evaluation,
	Geometry,
	Fragment,
	Compute,
	Task,
	Mesh,
}

Shader_Stages :: bit_set[Shader_Stage]

Shader_Define :: struct {
	name:  string,
	value: string,
}

Compiler_Settings :: struct {
	search_paths: []string,
	defines:      []Shader_Define,
}

Shader_Config :: struct {
	name:           string,
	pipeline_cache: Pipeline_Cache,
	push_type:      typeid,
	colour_formats: [MAX_COLOUR_ATTACHMENTS]vk.Format,
	depth_format:   vk.Format,
	stencil_format: vk.Format,
	view_mask:      u32,
}

Shader :: struct {
	handle:    vk.Pipeline,
	name:      string,
	push_size: int,
	push_type: typeid,
	push_plan: Push_Plan,
	pipeline_cache: Pipeline_Cache,
	variant:   union {
		Graphics_Shader,
		Compute_Shader,
	},
	recording: Shader_Recording,
}

Graphics_Shader :: struct {
	config: Shader_Config,
	mesh:   bool,
}

Compute_Shader :: struct {
	group_size: [3]u32,
}

@(private)
Push_Leaf_Kind :: enum u8 {
	Float,
	Signed,
	Unsigned,
	Bool,
	Pointer,
	Other,
	Image,
	Buffer,
	Sampler,
}

@(private = "file")
Push_Leaf :: struct {
	offset: int,
	width:  int,
	kind:   Push_Leaf_Kind,
	name:   string,
	group:  int,
}

@(private)
Push_Copy :: struct {
	from, to, size: int,
}

@(private)
Push_Slot :: struct {
	from, to, width: int,
	kind:            Push_Leaf_Kind,
	name:            string,
}

@(private)
Push_Plan :: struct {
	copies: []Push_Copy,
	slots:  []Push_Slot,
}

Shader_Resource :: union {
	Image,
	Buffer,
	Sampler,
}

Shader_Binding :: struct {
	resource: Shader_Resource,
	written:  bool,
}

Stencil_State :: struct {
	compare_op:    vk.CompareOp,
	pass_op:       vk.StencilOp,
	fail_op:       vk.StencilOp,
	depth_fail_op: vk.StencilOp,
	reference:     u32,
	compare_mask:  u32,
	write_mask:    u32,
}

Draw_State :: struct {
	viewport:          Maybe(vk.Viewport),
	scissor:           Maybe(vk.Rect2D),
	cull_mode:         vk.CullModeFlags,
	front_face:        vk.FrontFace,
	topology:          vk.PrimitiveTopology,
	primitive_restart: bool,
	polygon_mode:      vk.PolygonMode,
	depth_test:        bool,
	depth_compare:     vk.CompareOp,
	depth_write:       bool,
	depth_bias:        bool,
	depth_bias_values: [3]f32,
	depth_clamp:       bool,
	stencil_test:      bool,
	stencil_front:     Stencil_State,
	stencil_back:      Stencil_State,
	blend:             [MAX_COLOUR_ATTACHMENTS]Maybe(vk.ColorBlendEquationEXT),
	write_masks:       [MAX_COLOUR_ATTACHMENTS]vk.ColorComponentFlags,
	colour_state_set:  bit_set[0 ..< MAX_COLOUR_ATTACHMENTS],
	blend_constants:   [4]f32,
	alpha_to_coverage: bool,
}

Draw_Command :: struct {
	state:          int,
	draw_data:      u32,
	vertex_count:   u32,
	instances:      u32,
	first_vertex:   u32,
	first_instance: u32,
}

Draw_Indexed_Command :: struct {
	state:          int,
	draw_data:      u32,
	index_count:    u32,
	instances:      u32,
	first_index:    u32,
	vertex_offset:  i32,
	first_instance: u32,
}

Dispatch_Command :: struct {
	groups:    [3]u32,
	draw_data: u32,
}

Indirect_Kind :: enum u8 {
	Vertices,
	Indexed,
	Mesh_Tasks,
}

Draw_Indirect_Command :: struct {
	state:        int,
	draw_data:    u32,
	kind:         Indirect_Kind,
	buffer:       Buffer,
	offset:       vk.DeviceSize,
	count_buffer: Maybe(Buffer),
	count_offset: vk.DeviceSize,
	draws:        u32,
	stride:       u32,
}

Draw_Mesh_Command :: struct {
	state:     int,
	draw_data: u32,
	groups:    [3]u32,
}

Dispatch_Indirect_Command :: struct {
	draw_data: u32,
	buffer:    Buffer,
	offset:    vk.DeviceSize,
}

Shader_Command :: union {
	Draw_Command,
	Draw_Indexed_Command,
	Draw_Indirect_Command,
	Draw_Mesh_Command,
	Dispatch_Command,
	Dispatch_Indirect_Command,
}

Shader_Recording :: struct {
	id:                 u64,
	bindings:           [dynamic]Shader_Binding,
	colour_attachments: [dynamic]Image,
	depth_attachment:   Maybe(Image),
	index_buffer:       Maybe(Buffer),
	index_type:         Index_Type,
	state:              Draw_State,
	state_changed:      bool,
	states:             [dynamic]Draw_State,
	commands:           [dynamic]Shader_Command,
	push_data:          [dynamic]u8,
	push_source:        [dynamic]u8,
}

BLEND_ALPHA :: vk.ColorBlendEquationEXT {
	srcColorBlendFactor = .SRC_ALPHA,
	dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
	colorBlendOp        = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
	alphaBlendOp        = .ADD,
}

BLEND_PREMULTIPLIED :: vk.ColorBlendEquationEXT {
	srcColorBlendFactor = .ONE,
	dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
	colorBlendOp        = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
	alphaBlendOp        = .ADD,
}

BLEND_ADDITIVE :: vk.ColorBlendEquationEXT {
	srcColorBlendFactor = .ONE,
	dstColorBlendFactor = .ONE,
	colorBlendOp        = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ONE,
	alphaBlendOp        = .ADD,
}

@(private = "file")
next_recording_id: u64

@(private = "file")
compiler: intrinsics.type_proc_return_type(type_of(slang.create_global_session2), 0)

@(private = "file")
SPIRV_MAGIC :: 0x07230203

@(private = "file")
SPIRV_OP_ENTRY_POINT :: 15

@(private = "file")
SPIRV_OP_EXECUTION_MODE :: 16

@(private = "file")
SPIRV_EXECUTION_MODE_LOCAL_SIZE :: 17

@(private = "file")
Spirv_Op :: enum u32 {
	Type_Bool            = 20,
	Type_Int             = 21,
	Type_Float           = 22,
	Type_Vector          = 23,
	Type_Matrix          = 24,
	Type_Array           = 28,
	Type_Struct          = 30,
	Type_Pointer         = 32,
	Constant             = 43,
	Variable             = 59,
	Decorate             = 71,
	Member_Decorate      = 72,
	Member_Name          = 6,
	Type_Untyped_Pointer = 4417,
	Untyped_Variable     = 4418,
}

@(private = "file")
SPIRV_STORAGE_PUSH_CONSTANT :: 9

@(private = "file")
SPIRV_DECORATION_ROW_MAJOR :: 4

@(private = "file")
SPIRV_DECORATION_ARRAY_STRIDE :: 6

@(private = "file")
SPIRV_DECORATION_MATRIX_STRIDE :: 7

@(private = "file")
SPIRV_DECORATION_OFFSET :: 35

@(private = "file")
SPIRV_EXECUTION_MODELS := [Shader_Stage]u32 {
	.Vertex                  = 0,
	.Tessellation_Control    = 1,
	.Tessellation_Evaluation = 2,
	.Geometry                = 3,
	.Fragment                = 4,
	.Compute                 = 5,
	.Task                    = 5364,
	.Mesh                    = 5365,
}

@(private = "file")
STAGE_FLAGS := [Shader_Stage]vk.ShaderStageFlags {
	.Vertex                  = {.VERTEX},
	.Tessellation_Control    = {.TESSELLATION_CONTROL},
	.Tessellation_Evaluation = {.TESSELLATION_EVALUATION},
	.Geometry                = {.GEOMETRY},
	.Fragment                = {.FRAGMENT},
	.Compute                 = {.COMPUTE},
	.Task                    = {.TASK_EXT},
	.Mesh                    = {.MESH_EXT},
}

@(private = "file")
GRAPHICS_DYNAMIC_STATES := [?]vk.DynamicState {
	.VIEWPORT_WITH_COUNT,
	.SCISSOR_WITH_COUNT,
	.DEPTH_BIAS,
	.BLEND_CONSTANTS,
	.STENCIL_COMPARE_MASK,
	.STENCIL_WRITE_MASK,
	.STENCIL_REFERENCE,
	.CULL_MODE,
	.FRONT_FACE,
	.PRIMITIVE_TOPOLOGY,
	.DEPTH_TEST_ENABLE,
	.DEPTH_WRITE_ENABLE,
	.DEPTH_COMPARE_OP,
	.STENCIL_TEST_ENABLE,
	.STENCIL_OP,
	.DEPTH_BIAS_ENABLE,
	.PRIMITIVE_RESTART_ENABLE,
	.POLYGON_MODE_EXT,
	.RASTERIZATION_SAMPLES_EXT,
	.ALPHA_TO_COVERAGE_ENABLE_EXT,
	.DEPTH_CLAMP_ENABLE_EXT,
	.COLOR_BLEND_ENABLE_EXT,
	.COLOR_BLEND_EQUATION_EXT,
	.COLOR_WRITE_MASK_EXT,
}

@(private = "file")
Spirv_Entry_Point :: struct {
	name:       cstring,
	id:         u32,
	stage:      Shader_Stage,
	group_size: [3]u32,
	interface:  []u32,
	push_size:   int,
	push_type:   u32,
	push_leaves: []Push_Leaf,
}

@(require_results)
make_shader_from_file :: proc(
	path: string,
	entry_points: []string,
	settings: Compiler_Settings,
	config: Shader_Config,
	allocator := context.temp_allocator,
) -> (
	shader: Shader,
	diagnostics: string,
	err: Error,
) {
	text: string
	shader, text, err = compile_and_build(path, nil, entry_points, settings, config)
	return shader, take_diagnostics(text, allocator), err
}

@(require_results)
make_shader_from_code :: proc(
	code: []u8,
	entry_points: []string,
	settings: Compiler_Settings,
	config: Shader_Config,
	allocator := context.temp_allocator,
) -> (
	shader: Shader,
	diagnostics: string,
	err: Error,
) {
	text: string
	shader, text, err = compile_and_build("", code, entry_points, settings, config)
	return shader, take_diagnostics(text, allocator), err
}

@(private = "file")
compile_and_build :: proc(
	path: string,
	source: []u8,
	entry_points: []string,
	settings: Compiler_Settings,
	config: Shader_Config,
) -> (
	shader: Shader,
	text: string,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	code: []u32
	code, text, err = compile(path, source, entry_points, settings)
	if err != nil {
		return
	}
	shader, err = make_shader_from_compiled(code, entry_points, config)
	return
}

@(private = "file")
compile :: proc(path: string, source: []u8, entry_points: []string, settings: Compiler_Settings) -> (code: []u32, text: string, err: Error) {
	report := strings.builder_make()
	code, err = compile_slang(path, source, entry_points, settings, &report)
	return code, strings.to_string(report), err
}

@(private = "file")
take_diagnostics :: proc(text: string, allocator: runtime.Allocator) -> string {
	if text == "" {
		return ""
	}
	diagnostics := strings.clone(text, allocator)
	delete(text)
	return diagnostics
}

@(require_results)
make_shader_from_compiled :: proc(code: []u32, entry_points: []string, config: Shader_Config) -> (shader: Shader, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	shader = build_pipeline(code, entry_points, config) or_return
	reset_shader(&shader)
	return
}

make_shader :: proc {
	make_shader_from_file,
	make_shader_from_code,
	make_shader_from_compiled,
}

@(require_results)
make_shaders_from_file :: proc(
	path: string,
	entry_points: [][]string,
	settings: Compiler_Settings,
	configs: []Shader_Config,
	allocator := context.allocator,
	diagnostics_allocator := context.temp_allocator,
) -> (
	shaders: []Shader,
	diagnostics: string,
	err: Error,
) {
	text: string
	shaders, text, err = compile_and_build_all(path, nil, entry_points, settings, configs, allocator)
	return shaders, take_diagnostics(text, diagnostics_allocator), err
}

@(require_results)
make_shaders_from_code :: proc(
	code: []u8,
	entry_points: [][]string,
	settings: Compiler_Settings,
	configs: []Shader_Config,
	allocator := context.allocator,
	diagnostics_allocator := context.temp_allocator,
) -> (
	shaders: []Shader,
	diagnostics: string,
	err: Error,
) {
	text: string
	shaders, text, err = compile_and_build_all("", code, entry_points, settings, configs, allocator)
	return shaders, take_diagnostics(text, diagnostics_allocator), err
}

@(private = "file")
compile_and_build_all :: proc(
	path: string,
	source: []u8,
	entry_points: [][]string,
	settings: Compiler_Settings,
	configs: []Shader_Config,
	allocator: runtime.Allocator,
) -> (
	shaders: []Shader,
	text: string,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	code: []u32
	code, text, err = compile(path, source, slice.concatenate(entry_points, context.temp_allocator), settings)
	if err != nil {
		return
	}
	shaders, err = make_shaders_from_compiled(code, entry_points, configs, allocator)
	return
}

@(require_results)
make_shaders_from_compiled :: proc(
	code: []u32,
	entry_points: [][]string,
	configs: []Shader_Config,
	allocator := context.allocator,
) -> (
	shaders: []Shader,
	err: Error,
) {
	assert(len(entry_points) == len(configs), "make_shaders needs one config per shader")
	shaders = make([]Shader, len(configs), allocator)
	for &shader, index in shaders {
		shader, err = make_shader_from_compiled(code, entry_points[index], configs[index])
		if err != nil {
			delete_shaders(shaders[:index], allocator)
			return nil, err
		}
	}
	return
}

make_shaders :: proc {
	make_shaders_from_file,
	make_shaders_from_code,
	make_shaders_from_compiled,
}

delete_shader :: proc(shader: ^Shader) {
	if shader.handle != 0 {
		vk.DeviceWaitIdle(device.handle)
		vk.DestroyPipeline(device.handle, shader.handle, nil)
	}
	recording := &shader.recording
	delete(recording.bindings)
	delete(recording.colour_attachments)
	delete(recording.states)
	delete(recording.commands)
	delete(recording.push_data)
	delete(recording.push_source)
	delete_push_plan(&shader.push_plan)
	delete(shader.name)
	shader^ = {}
}

delete_shaders :: proc(shaders: []Shader, allocator := context.allocator) {
	for &shader in shaders {
		delete_shader(&shader)
	}
	delete(shaders, allocator)
}

@(require_results)
reload_shader_from_file :: proc(
	shader: ^Shader,
	path: string,
	entry_points: []string,
	settings: Compiler_Settings,
	allocator := context.temp_allocator,
) -> (
	diagnostics: string,
	err: Error,
) {
	text: string
	text, err = compile_and_reload(shader, path, nil, entry_points, settings)
	return take_diagnostics(text, allocator), err
}

@(require_results)
reload_shader_from_code :: proc(
	shader: ^Shader,
	code: []u8,
	entry_points: []string,
	settings: Compiler_Settings,
	allocator := context.temp_allocator,
) -> (
	diagnostics: string,
	err: Error,
) {
	text: string
	text, err = compile_and_reload(shader, "", code, entry_points, settings)
	return take_diagnostics(text, allocator), err
}

@(private = "file")
compile_and_reload :: proc(
	shader: ^Shader,
	path: string,
	source: []u8,
	entry_points: []string,
	settings: Compiler_Settings,
) -> (
	text: string,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	code: []u32
	code, text, err = compile(path, source, entry_points, settings)
	if err != nil {
		return
	}
	err = reload_shader_from_compiled(shader, code, entry_points)
	return
}

@(require_results)
reload_shader_from_compiled :: proc(shader: ^Shader, code: []u32, entry_points: []string) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	config: Shader_Config
	if graphics, is_graphics := shader.variant.(Graphics_Shader); is_graphics {
		config = graphics.config
	}
	config.push_type = shader.push_type
	config.pipeline_cache = shader.pipeline_cache
	config.name = shader.name
	rebuilt := build_pipeline(code, entry_points, config) or_return
	vk.DeviceWaitIdle(device.handle)
	vk.DestroyPipeline(device.handle, shader.handle, nil)
	rebuilt.recording = shader.recording
	delete_push_plan(&shader.push_plan)
	delete(rebuilt.name)
	rebuilt.name = shader.name
	shader^ = rebuilt
	if len(shader.recording.push_source) > 0 {
		resize(&shader.recording.push_data, shader.push_size)
	}
	return nil
}

reload_shader :: proc {
	reload_shader_from_file,
	reload_shader_from_code,
	reload_shader_from_compiled,
}

reset_shader :: proc(shader: ^Shader) {
	reset_shader_bindings(shader)
	recording := &shader.recording
	next_recording_id += 1
	recording.id = next_recording_id
	recording.index_type = .U32
	recording.state = default_draw_state()
	recording.state_changed = true
	clear(&recording.states)
	clear(&recording.commands)
	clear(&recording.push_data)
	clear(&recording.push_source)
}

reset_shader_bindings :: proc(shader: ^Shader) {
	recording := &shader.recording
	clear(&recording.bindings)
	clear(&recording.colour_attachments)
	recording.depth_attachment = nil
	recording.index_buffer = nil
}

@(require_results)
bind_shader_image_input :: proc(shader: ^Shader, image: Image) -> (index: u32, err: Error) {
	return add_binding(shader, {resource = image})
}

@(require_results)
bind_shader_buffer_input :: proc(shader: ^Shader, buffer: Buffer) -> (index: u32, err: Error) {
	return add_binding(shader, {resource = buffer})
}

@(require_results)
bind_shader_sampler_input :: proc(shader: ^Shader, sampler: Sampler) -> (index: u32, err: Error) {
	return add_binding(shader, {resource = sampler})
}

bind_shader_input :: proc {
	bind_shader_image_input,
	bind_shader_buffer_input,
	bind_shader_sampler_input,
}

@(require_results)
bind_shader_image_output :: proc(shader: ^Shader, image: Image) -> (written: Image, index: u32, err: Error) {
	assert(.STORAGE in image.usage, "bind_shader_output writes through a storage descriptor; render targets use bind_shader_colour or bind_shader_depth")
	index = add_binding(shader, {resource = image, written = true}) or_return
	return next_version(image), index, nil
}

@(require_results)
bind_shader_buffer_output :: proc(shader: ^Shader, buffer: Buffer) -> (written: Buffer, index: u32, err: Error) {
	index = add_binding(shader, {resource = buffer, written = true}) or_return
	return next_version(buffer), index, nil
}

bind_shader_output :: proc {
	bind_shader_image_output,
	bind_shader_buffer_output,
}

bind_shader_colour :: proc(shader: ^Shader, image: Image) -> Image {
	graphics, is_graphics := shader.variant.(Graphics_Shader)
	assert(is_graphics, "only graphics shaders have colour attachments")
	recording := &shader.recording
	slot := len(recording.colour_attachments)
	assert(slot < colour_format_count(graphics.config), "the shader was made with fewer colour formats than colour attachments bound")
	assert(image.format == graphics.config.colour_formats[slot], "a colour attachment's format must match the shader's colour format in that slot")
	assert(.COLOR_ATTACHMENT in image.usage, "the image cannot be a colour attachment")
	append(&recording.colour_attachments, image)
	return next_version(image)
}

bind_shader_depth :: proc(shader: ^Shader, image: Image) -> Image {
	graphics, is_graphics := shader.variant.(Graphics_Shader)
	assert(is_graphics, "only graphics shaders have a depth attachment")
	recording := &shader.recording
	_, has_depth := recording.depth_attachment.?
	assert(!has_depth, "a shader has one depth attachment")
	assert(
		image.format == graphics.config.depth_format || image.format == graphics.config.stencil_format,
		"the depth attachment's format must match the shader's depth or stencil format",
	)
	assert(.DEPTH_STENCIL_ATTACHMENT in image.usage, "the image cannot be a depth attachment")
	recording.depth_attachment = image
	return next_version(image)
}

bind_shader_index_buffer :: proc(shader: ^Shader, buffer: Buffer, index_type := Index_Type.U32) {
	_, is_graphics := shader.variant.(Graphics_Shader)
	assert(is_graphics, "only graphics shaders draw indexed")
	assert(.INDEX_BUFFER in buffer.usage, "the index buffer was not made with .Index usage")
	shader.recording.index_buffer = buffer
	shader.recording.index_type = index_type
}

set_push_data :: proc(shader: ^Shader, data: $T) {
	fmt.assertf(shader.push_type != nil, "set_push_data with %v, but the shader was made without Shader_Config.push_type", typeid_of(T))
	fmt.assertf(T == shader.push_type, "set_push_data with %v, but the shader was made for %v", typeid_of(T), shader.push_type)
	data := data
	recording := &shader.recording
	resize(&recording.push_source, size_of(T))
	copy(recording.push_source[:], mem.ptr_to_bytes(&data))
	resize(&recording.push_data, shader.push_size)
}

draw_vertices :: proc(shader: ^Shader, #any_int vertex_count, instances, first_vertex, first_instance: int, draw_data: u32 = 0) {
	assert(!is_mesh_shader(shader^), "a mesh shader draws with draw_mesh_tasks")
	append(
		&shader.recording.commands,
		Draw_Command {
			state = current_state(shader),
			draw_data = draw_data,
			vertex_count = u32(vertex_count),
			instances = u32(instances),
			first_vertex = u32(first_vertex),
			first_instance = u32(first_instance),
		},
	)
}

draw_indexed :: proc(
	shader: ^Shader,
	#any_int vertex_offset, first_index, index_count, first_instance, instances: int,
	draw_data: u32 = 0,
) {
	assert(!is_mesh_shader(shader^), "a mesh shader draws with draw_mesh_tasks")
	append(
		&shader.recording.commands,
		Draw_Indexed_Command {
			state = current_state(shader),
			draw_data = draw_data,
			index_count = u32(index_count),
			instances = u32(instances),
			first_index = u32(first_index),
			vertex_offset = i32(vertex_offset),
			first_instance = u32(first_instance),
		},
	)
}

draw :: proc {
	draw_vertices,
	draw_indexed,
}

draw_indirect :: proc(
	shader: ^Shader,
	buffer: Buffer,
	#any_int offset: int = 0,
	#any_int draws: int = 1,
	#any_int stride: int = size_of(vk.DrawIndirectCommand),
	draw_data: u32 = 0,
) {
	record_indirect(shader, .Vertices, buffer, offset, nil, 0, draws, stride, draw_data)
}

draw_indexed_indirect :: proc(
	shader: ^Shader,
	buffer: Buffer,
	#any_int offset: int = 0,
	#any_int draws: int = 1,
	#any_int stride: int = size_of(vk.DrawIndexedIndirectCommand),
	draw_data: u32 = 0,
) {
	record_indirect(shader, .Indexed, buffer, offset, nil, 0, draws, stride, draw_data)
}

draw_indirect_count :: proc(
	shader: ^Shader,
	buffer: Buffer,
	#any_int offset: int,
	count_buffer: Buffer,
	#any_int count_offset: int,
	#any_int max_draws: int,
	#any_int stride: int = size_of(vk.DrawIndirectCommand),
	draw_data: u32 = 0,
) {
	record_indirect(shader, .Vertices, buffer, offset, count_buffer, count_offset, max_draws, stride, draw_data)
}

draw_indexed_indirect_count :: proc(
	shader: ^Shader,
	buffer: Buffer,
	#any_int offset: int,
	count_buffer: Buffer,
	#any_int count_offset: int,
	#any_int max_draws: int,
	#any_int stride: int = size_of(vk.DrawIndexedIndirectCommand),
	draw_data: u32 = 0,
) {
	record_indirect(shader, .Indexed, buffer, offset, count_buffer, count_offset, max_draws, stride, draw_data)
}

draw_mesh_tasks :: proc(shader: ^Shader, groups: [3]u32, draw_data: u32 = 0) {
	assert(is_mesh_shader(shader^), "draw_mesh_tasks needs a shader made with a mesh entry point")
	append(&shader.recording.commands, Draw_Mesh_Command{state = current_state(shader), draw_data = draw_data, groups = groups})
}

draw_mesh_tasks_indirect :: proc(
	shader: ^Shader,
	buffer: Buffer,
	#any_int offset: int = 0,
	#any_int draws: int = 1,
	#any_int stride: int = size_of(vk.DrawMeshTasksIndirectCommandEXT),
	draw_data: u32 = 0,
) {
	record_indirect(shader, .Mesh_Tasks, buffer, offset, nil, 0, draws, stride, draw_data)
}

draw_mesh_tasks_indirect_count :: proc(
	shader: ^Shader,
	buffer: Buffer,
	#any_int offset: int,
	count_buffer: Buffer,
	#any_int count_offset: int,
	#any_int max_draws: int,
	#any_int stride: int = size_of(vk.DrawMeshTasksIndirectCommandEXT),
	draw_data: u32 = 0,
) {
	record_indirect(shader, .Mesh_Tasks, buffer, offset, count_buffer, count_offset, max_draws, stride, draw_data)
}

dispatch_indirect :: proc(shader: ^Shader, buffer: Buffer, #any_int offset: int = 0, draw_data: u32 = 0) {
	_, is_compute := shader.variant.(Compute_Shader)
	assert(is_compute, "dispatch_indirect needs a compute shader")
	assert(.INDIRECT_BUFFER in buffer.usage, "an indirect buffer needs .Indirect usage")
	assert(offset >= 0 && offset % 4 == 0, "an indirect offset must be a multiple of 4")
	assert(vk.DeviceSize(offset + size_of(vk.DispatchIndirectCommand)) <= buffer.size, "the dispatch reads past the end of the indirect buffer")
	append(&shader.recording.commands, Dispatch_Indirect_Command{draw_data = draw_data, buffer = buffer, offset = vk.DeviceSize(offset)})
}

@(private = "file")
record_indirect :: proc(
	shader: ^Shader,
	kind: Indirect_Kind,
	buffer: Buffer,
	offset: int,
	count_buffer: Maybe(Buffer),
	count_offset: int,
	draws: int,
	stride: int,
	draw_data: u32,
) {
	if kind == .Mesh_Tasks {
		assert(is_mesh_shader(shader^), "mesh task draws need a shader made with a mesh entry point")
	} else {
		assert(!is_mesh_shader(shader^), "a mesh shader draws with draw_mesh_tasks")
	}
	command_size := [Indirect_Kind]int {
		.Vertices   = size_of(vk.DrawIndirectCommand),
		.Indexed    = size_of(vk.DrawIndexedIndirectCommand),
		.Mesh_Tasks = size_of(vk.DrawMeshTasksIndirectCommandEXT),
	}
	_, has_count := count_buffer.?
	assert(.INDIRECT_BUFFER in buffer.usage, "an indirect buffer needs .Indirect usage")
	assert(offset >= 0 && offset % 4 == 0, "an indirect offset must be a multiple of 4")
	assert(draws >= 0, "the draw count cannot be negative")
	assert(draws <= 1 || stride % 4 == 0 && stride >= command_size[kind], "the stride must be a multiple of 4 and at least the size of one indirect command")
	assert(draws <= 1 || has_count || device.optional.multi_draw_indirect, "more than one indirect draw per command needs the multiDrawIndirect feature")
	assert(draws == 0 || vk.DeviceSize(offset + (draws - 1) * stride + command_size[kind]) <= buffer.size, "the draws read past the end of the indirect buffer")
	if count, ok := count_buffer.?; ok {
		assert(device.optional.draw_indirect_count, "indirect count draws need the drawIndirectCount feature")
		assert(.INDIRECT_BUFFER in count.usage, "a count buffer needs .Indirect usage")
		assert(count_offset >= 0 && count_offset % 4 == 0 && vk.DeviceSize(count_offset + 4) <= count.size, "the count offset must be a multiple of 4 inside the count buffer")
	}
	append(
		&shader.recording.commands,
		Draw_Indirect_Command {
			state = current_state(shader),
			draw_data = draw_data,
			kind = kind,
			buffer = buffer,
			offset = vk.DeviceSize(offset),
			count_buffer = count_buffer,
			count_offset = vk.DeviceSize(count_offset),
			draws = u32(draws),
			stride = u32(stride),
		},
	)
}

@(private)
is_mesh_shader :: proc(shader: Shader) -> bool {
	graphics, is_graphics := shader.variant.(Graphics_Shader)
	return is_graphics && graphics.mesh
}

dispatch :: proc(shader: ^Shader, groups: [3]u32, draw_data: u32 = 0) {
	_, is_compute := shader.variant.(Compute_Shader)
	assert(is_compute, "dispatch needs a compute shader")
	append(&shader.recording.commands, Dispatch_Command{groups = groups, draw_data = draw_data})
}

dispatch_threads :: proc(shader: ^Shader, threads: [3]u32, draw_data: u32 = 0) {
	compute, is_compute := shader.variant.(Compute_Shader)
	assert(is_compute, "dispatch_threads needs a compute shader")
	size := compute.group_size
	dispatch(shader, (threads + size - 1) / size, draw_data)
}

set_viewport :: proc(shader: ^Shader, position, size: [2]f32, depth_range := [2]f32{0, 1}) {
	state := graphics_state(shader)
	state.viewport = vk.Viewport {
		x        = position.x,
		y        = position.y,
		width    = size.x,
		height   = size.y,
		minDepth = depth_range[0],
		maxDepth = depth_range[1],
	}
}

set_scissor :: proc(shader: ^Shader, position: [2]i32, size: [2]u32) {
	assert(position.x >= 0 && position.y >= 0, "a scissor cannot start at a negative position")
	state := graphics_state(shader)
	state.scissor = vk.Rect2D {
		offset = {position.x, position.y},
		extent = {size.x, size.y},
	}
}

set_cull_mode :: proc(shader: ^Shader, cull_mode: vk.CullModeFlags) {
	graphics_state(shader).cull_mode = cull_mode
}

set_front_face :: proc(shader: ^Shader, front_face: vk.FrontFace) {
	graphics_state(shader).front_face = front_face
}

set_topology :: proc(shader: ^Shader, topology: vk.PrimitiveTopology) {
	assert(!is_mesh_shader(shader^), "mesh shaders choose their own primitives")
	#partial switch topology {
	case .TRIANGLE_LIST, .TRIANGLE_STRIP, .TRIANGLE_FAN, .TRIANGLE_LIST_WITH_ADJACENCY, .TRIANGLE_STRIP_WITH_ADJACENCY:
	case:
		assert(
			bool(device.dynamic_state_properties.dynamicPrimitiveTopologyUnrestricted),
			"this device can only switch between triangle topologies; shaders are built for triangles",
		)
	}
	graphics_state(shader).topology = topology
}

set_primitive_restart :: proc(shader: ^Shader, enabled: bool) {
	assert(!is_mesh_shader(shader^), "mesh shaders choose their own primitives")
	graphics_state(shader).primitive_restart = enabled
}

set_polygon_mode :: proc(shader: ^Shader, polygon_mode: vk.PolygonMode) {
	graphics_state(shader).polygon_mode = polygon_mode
}

set_depth_test :: proc(shader: ^Shader, enabled: bool, compare_op := vk.CompareOp.LESS_OR_EQUAL) {
	state := graphics_state(shader)
	state.depth_test = enabled
	state.depth_compare = compare_op
}

set_depth_write :: proc(shader: ^Shader, enabled: bool) {
	graphics_state(shader).depth_write = enabled
}

set_depth_bias :: proc(shader: ^Shader, enabled: bool, constant: f32 = 0, slope: f32 = 0, clamp: f32 = 0) {
	state := graphics_state(shader)
	state.depth_bias = enabled
	state.depth_bias_values = {constant, slope, clamp}
}

set_depth_clamp :: proc(shader: ^Shader, enabled: bool) {
	graphics_state(shader).depth_clamp = enabled
}

set_stencil_test :: proc(shader: ^Shader, enabled: bool) {
	graphics_state(shader).stencil_test = enabled
}

set_stencil :: proc(
	shader: ^Shader,
	compare_op := vk.CompareOp.ALWAYS,
	pass_op := vk.StencilOp.KEEP,
	fail_op := vk.StencilOp.KEEP,
	depth_fail_op := vk.StencilOp.KEEP,
	reference: u32 = 0,
	compare_mask: u32 = 0xff,
	write_mask: u32 = 0xff,
	faces := vk.StencilFaceFlags{.FRONT, .BACK},
) {
	state := graphics_state(shader)
	stencil := Stencil_State{compare_op, pass_op, fail_op, depth_fail_op, reference, compare_mask, write_mask}
	if .FRONT in faces {
		state.stencil_front = stencil
	}
	if .BACK in faces {
		state.stencil_back = stencil
	}
}

set_blend :: proc(shader: ^Shader, equation: Maybe(vk.ColorBlendEquationEXT), #any_int attachment: int = 0) {
	assert(attachment >= 0 && attachment < MAX_COLOUR_ATTACHMENTS, "set_blend names a colour attachment out of range")
	state := graphics_state(shader)
	state.blend[attachment] = equation
	state.colour_state_set += {attachment}
}

set_colour_write_mask :: proc(shader: ^Shader, mask: vk.ColorComponentFlags, #any_int attachment: int = 0) {
	assert(attachment >= 0 && attachment < MAX_COLOUR_ATTACHMENTS, "set_colour_write_mask names a colour attachment out of range")
	state := graphics_state(shader)
	state.write_masks[attachment] = mask
	state.colour_state_set += {attachment}
}

set_blend_constants :: proc(shader: ^Shader, constants: [4]f32) {
	graphics_state(shader).blend_constants = constants
}

set_alpha_to_coverage :: proc(shader: ^Shader, enabled: bool) {
	graphics_state(shader).alpha_to_coverage = enabled
}

@(private)
colour_format_count :: proc(config: Shader_Config) -> int {
	formats := config.colour_formats
	count := 0
	for format in formats {
		if format == .UNDEFINED {
			break
		}
		count += 1
	}
	for format in formats[count:] {
		assert(format == .UNDEFINED, "Shader_Config.colour_formats must list its formats first, with no gaps")
	}
	return count
}

@(private)
default_draw_state :: proc() -> (state: Draw_State) {
	state.front_face = .COUNTER_CLOCKWISE
	state.topology = .TRIANGLE_LIST
	state.polygon_mode = .FILL
	state.depth_compare = .LESS_OR_EQUAL
	stencil := Stencil_State {
		compare_op    = .ALWAYS,
		pass_op       = .KEEP,
		fail_op       = .KEEP,
		depth_fail_op = .KEEP,
		compare_mask  = 0xff,
		write_mask    = 0xff,
	}
	state.stencil_front = stencil
	state.stencil_back = stencil
	for &mask in state.write_masks {
		mask = {.R, .G, .B, .A}
	}
	return
}

@(private = "file")
@(require_results)
add_binding :: proc(shader: ^Shader, binding: Shader_Binding) -> (index: u32, err: Error) {
	switch resource in binding.resource {
	case Image:
		if resource.heap_index == 0 {
			log.error("The image has no descriptor: it must be sampled or storage capable, single-aspect, and made by Valhalla")
			return 0, .Resource_Not_In_Heap
		}
	case Buffer:
		if resource.heap_index == 0 {
			log.error("The buffer has no descriptor: it must be made by Valhalla with .Storage usage")
			return 0, .Resource_Not_In_Heap
		}
	case Sampler:
		if resource.heap_index == 0 {
			log.error("The sampler has no descriptor: it must be made by make_sampler")
			return 0, .Resource_Not_In_Heap
		}
	}
	recording := &shader.recording
	if len(recording.bindings) >= SHADER_BINDING_CAPACITY {
		log.errorf("A shader can bind at most %v resources", SHADER_BINDING_CAPACITY)
		return 0, .Too_Many_Bindings
	}
	index = u32(len(recording.bindings))
	append(&recording.bindings, binding)
	return
}

@(private = "file")
graphics_state :: proc(shader: ^Shader) -> ^Draw_State {
	_, is_graphics := shader.variant.(Graphics_Shader)
	assert(is_graphics, "draw state belongs to graphics shaders")
	shader.recording.state_changed = true
	return &shader.recording.state
}

@(private = "file")
current_state :: proc(shader: ^Shader) -> int {
	_, is_graphics := shader.variant.(Graphics_Shader)
	assert(is_graphics, "draws need a graphics shader")
	recording := &shader.recording
	if recording.state_changed || len(recording.states) == 0 {
		if len(recording.states) == 0 || recording.states[len(recording.states) - 1] != recording.state {
			append(&recording.states, recording.state)
		}
		recording.state_changed = false
	}
	return len(recording.states) - 1
}

@(private)
release_shader_compiler :: proc() {
	if compiler == nil {
		return
	}
	slang.release(compiler)
	compiler = nil
	slang.shutdown()
}

@(private = "file")
blob_text :: proc(blob: ^slang.Blob) -> string {
	if blob == nil || slang.get_buffer_size(blob) == 0 {
		return ""
	}
	return strings.string_from_ptr(([^]u8)(slang.get_buffer_pointer(blob)), int(slang.get_buffer_size(blob)))
}

@(private = "file")
@(require_results)
compile_slang :: proc(
	path: string,
	source: []u8,
	entry_points: []string,
	settings: Compiler_Settings,
	report: ^strings.Builder,
) -> (
	code: []u32,
	err: Error,
) {
	if compiler == nil {
		desc := slang.global_session_desc_default()
		ok: bool
		if compiler, ok = slang.create_global_session2(&desc); !ok {
			compiler = nil
			strings.write_string(report, "Slang's global session could not be created\n")
			return nil, .Compiler_Unavailable
		}
	}

	heap_capability := slang.find_capability(compiler, "spvDescriptorHeapEXT")
	if heap_capability == 0 {
		strings.write_string(report, "Slang does not know the spvDescriptorHeapEXT capability\n")
		return nil, .Compiler_Unavailable
	}
	target_options := []slang.Compiler_Option_Entry {
		{name = .Capability, value = {kind = .Int, intValue0 = i32(heap_capability)}},
		{name = .VulkanUseEntryPointName, value = {kind = .Int, intValue0 = 1}},
	}
	target := slang.target_desc_default()
	target.format = .SPIRV
	target.profile = slang.find_profile(compiler, "spirv_1_6")
	target.compilerOptionEntries = raw_data(target_options)
	target.compilerOptionEntryCount = u32(len(target_options))

	search_paths := make([]cstring, len(settings.search_paths), context.temp_allocator)
	for search_path, index in settings.search_paths {
		search_paths[index] = strings.clone_to_cstring(search_path, context.temp_allocator)
	}
	macros := make([]slang.Preprocessor_Macro_Desc, len(settings.defines), context.temp_allocator)
	for define, index in settings.defines {
		macros[index] = {
			name  = strings.clone_to_cstring(define.name, context.temp_allocator),
			value = strings.clone_to_cstring(define.value, context.temp_allocator),
		}
	}

	session_desc := slang.session_desc_default()
	session_desc.targets = &target
	session_desc.targetCount = 1
	session_desc.defaultMatrixLayoutMode = .COLUMN_MAJOR
	session_desc.searchPaths = raw_data(search_paths)
	session_desc.searchPathCount = slang.Int(len(search_paths))
	session_desc.preprocessorMacros = raw_data(macros)
	session_desc.preprocessorMacroCount = slang.Int(len(macros))

	session, session_ok := slang.create_session(compiler, &session_desc)
	if !session_ok {
		strings.write_string(report, "A Slang session could not be created\n")
		return nil, .Compiler_Unavailable
	}
	defer slang.release(session)

	module: intrinsics.type_proc_return_type(type_of(slang.load_module), 0)
	module_diagnostics: ^slang.Blob
	module_ok: bool
	if source != nil {
		module, module_diagnostics, module_ok = slang.load_module_from_source_string(
			session,
			"valhalla_shader",
			"valhalla_shader.slang",
			strings.clone_to_cstring(string(source), context.temp_allocator),
		)
	} else {
		module, module_diagnostics, module_ok = slang.load_module(session, strings.clone_to_cstring(path, context.temp_allocator))
	}
	defer slang.release(module_diagnostics)
	strings.write_string(report, blob_text(module_diagnostics))
	if !module_ok {
		return nil, .Module_Load_Failed
	}

	components := make([dynamic]^slang.Component_Type, 0, len(entry_points) + 1, context.temp_allocator)
	append(&components, module)
	entry_loop: for name, index in entry_points {
		for earlier in entry_points[:index] {
			if earlier == name {
				continue entry_loop
			}
		}
		entry_point, found := slang.find_entry_point_by_name(module, strings.clone_to_cstring(name, context.temp_allocator))
		if !found {
			fmt.sbprintf(report, "Shader entry point %v not found; it must carry a [shader(\"...\")] attribute\n", name)
			return nil, .Entry_Point_Not_Found
		}
		append(&components, entry_point)
	}
	defer for component in components[1:] {
		slang.release(component)
	}

	program, program_diagnostics, program_ok := slang.create_composite_component_type(session, components[:])
	defer slang.release(program_diagnostics)
	strings.write_string(report, blob_text(program_diagnostics))
	if !program_ok {
		return nil, .Link_Failed
	}
	defer slang.release(program)

	linked, link_diagnostics, link_ok := slang.link(program)
	defer slang.release(link_diagnostics)
	strings.write_string(report, blob_text(link_diagnostics))
	if !link_ok {
		return nil, .Link_Failed
	}
	defer slang.release(linked)

	blob, code_diagnostics, code_ok := slang.get_target_code(linked, 0)
	defer slang.release(code_diagnostics)
	strings.write_string(report, blob_text(code_diagnostics))
	if !code_ok {
		return nil, .Code_Generation_Failed
	}
	defer slang.release(blob)

	size := int(slang.get_buffer_size(blob))
	if size == 0 || size % size_of(u32) != 0 {
		strings.write_string(report, "Slang produced no SPIR-V\n")
		return nil, .Code_Generation_Failed
	}
	code = make([]u32, size / size_of(u32), context.temp_allocator)
	mem.copy(raw_data(code), slang.get_buffer_pointer(blob), size)
	return
}

@(private = "file")
parse_spirv :: proc(code: []u32) -> (entry_points: []Spirv_Entry_Point, ok: bool) {
	if len(code) < 5 || code[0] != SPIRV_MAGIC {
		return
	}
	found := make([dynamic]Spirv_Entry_Point, context.temp_allocator)
	layout := Spirv_Layout {
		types          = make(map[u32]Spirv_Type, context.temp_allocator),
		constants      = make(map[u32]u32, context.temp_allocator),
		array_strides  = make(map[u32]u32, context.temp_allocator),
		offsets        = make(map[Spirv_Member]u32, context.temp_allocator),
		matrix_strides = make(map[Spirv_Member]u32, context.temp_allocator),
		row_major      = make(map[Spirv_Member]bool, context.temp_allocator),
		member_names   = make(map[Spirv_Member]string, context.temp_allocator),
	}
	push_variables := make(map[u32]u32, context.temp_allocator)
	for i := 5; i < len(code); {
		word_count := int(code[i] >> 16)
		opcode := code[i] & 0xffff
		if word_count == 0 || i + word_count > len(code) {
			return
		}
		switch opcode {
		case SPIRV_OP_ENTRY_POINT:
			if word_count < 4 {
				return
			}
			for model, stage in SPIRV_EXECUTION_MODELS {
				if model == code[i + 1] {
					name := cstring(([^]u8)(raw_data(code[i + 3:])))
					first_interface := 3 + len(name) / 4 + 1
					interface := code[i + first_interface:i + word_count] if first_interface < word_count else nil
					append(&found, Spirv_Entry_Point{name = name, id = code[i + 2], stage = stage, interface = interface})
					break
				}
			}
		case SPIRV_OP_EXECUTION_MODE:
			if word_count >= 6 && code[i + 2] == SPIRV_EXECUTION_MODE_LOCAL_SIZE {
				for &entry_point in found {
					if entry_point.id == code[i + 1] {
						entry_point.group_size = {code[i + 3], code[i + 4], code[i + 5]}
					}
				}
			}
		case:
			collect_layout(&layout, &push_variables, Spirv_Op(opcode), code[i + 1:i + word_count])
		}
		i += word_count
	}
	push_sizes(&layout, push_variables, found[:])
	return found[:], true
}

@(private = "file")
Spirv_Type :: struct {
	op:       Spirv_Op,
	operands: []u32,
}

@(private = "file")
Spirv_Member :: struct {
	struct_id, member: u32,
}

@(private = "file")
Spirv_Layout :: struct {
	types:          map[u32]Spirv_Type,
	constants:      map[u32]u32,
	array_strides:  map[u32]u32,
	offsets:        map[Spirv_Member]u32,
	matrix_strides: map[Spirv_Member]u32,
	row_major:      map[Spirv_Member]bool,
	member_names:   map[Spirv_Member]string,
}

@(private = "file")
collect_layout :: proc(layout: ^Spirv_Layout, push_variables: ^map[u32]u32, op: Spirv_Op, operands: []u32) {
	#partial switch op {
	case .Type_Bool, .Type_Int, .Type_Float, .Type_Vector, .Type_Matrix, .Type_Array, .Type_Struct, .Type_Pointer, .Type_Untyped_Pointer:
		if len(operands) >= 1 {
			layout.types[operands[0]] = {op, operands[1:]}
		}
	case .Constant:
		if len(operands) >= 3 {
			layout.constants[operands[1]] = operands[2]
		}
	case .Decorate:
		if len(operands) >= 3 && operands[1] == SPIRV_DECORATION_ARRAY_STRIDE {
			layout.array_strides[operands[0]] = operands[2]
		}
	case .Member_Decorate:
		if len(operands) >= 3 {
			member := Spirv_Member{operands[0], operands[1]}
			switch operands[2] {
			case SPIRV_DECORATION_OFFSET:
				if len(operands) >= 4 {
					layout.offsets[member] = operands[3]
				}
			case SPIRV_DECORATION_MATRIX_STRIDE:
				if len(operands) >= 4 {
					layout.matrix_strides[member] = operands[3]
				}
			case SPIRV_DECORATION_ROW_MAJOR:
				layout.row_major[member] = true
			}
		}
	case .Member_Name:
		if len(operands) >= 3 {
			layout.member_names[{operands[0], operands[1]}] = string(cstring(([^]u8)(raw_data(operands[2:]))))
		}
	case .Variable:
		if len(operands) >= 3 && operands[2] == SPIRV_STORAGE_PUSH_CONSTANT {
			if pointer, known := layout.types[operands[0]]; known && pointer.op == .Type_Pointer && len(pointer.operands) >= 2 {
				push_variables[operands[1]] = pointer.operands[1]
			}
		}
	case .Untyped_Variable:
		if len(operands) >= 4 && operands[2] == SPIRV_STORAGE_PUSH_CONSTANT {
			push_variables[operands[1]] = operands[3]
		}
	}
}

@(private = "file")
push_sizes :: proc(layout: ^Spirv_Layout, push_variables: map[u32]u32, entry_points: []Spirv_Entry_Point) {
	for &entry_point in entry_points {
		for id in entry_point.interface {
			if pointee, is_push := push_variables[id]; is_push {
				size := type_size(layout, pointee)
				if size > entry_point.push_size {
					entry_point.push_size = size
					entry_point.push_type = pointee
				}
			}
		}
	}
	for &entry_point in entry_points {
		if entry_point.push_type == 0 {
			continue
		}
		leaves := make([dynamic]Push_Leaf, context.temp_allocator)
		flatten_spirv(layout, entry_point.push_type, 0, "", 0, false, &leaves)
		kept := make([dynamic]Push_Leaf, 0, len(leaves), context.temp_allocator)
		for leaf in leaves {
			if leaf.offset >= PUSH_HEADER_SIZE {
				append(&kept, leaf)
			}
		}
		entry_point.push_leaves = kept[:]
	}
}

@(private = "file")
field_name :: proc(parent, field: string) -> string {
	return field if parent == "" else fmt.tprintf("%v.%v", parent, field)
}

@(private = "file")
flatten_spirv :: proc(
	layout: ^Spirv_Layout,
	id: u32,
	offset: int,
	name: string,
	matrix_stride: u32,
	row_major: bool,
	leaves: ^[dynamic]Push_Leaf,
	group := -1,
) {
	group := group if group >= 0 else len(leaves)
	type, known := layout.types[id]
	if !known {
		append(leaves, Push_Leaf{offset = offset, kind = .Other, name = name, group = group})
		return
	}
	operands := type.operands
	#partial switch type.op {
	case .Type_Int:
		append(leaves, Push_Leaf{offset = offset, width = int(operands[0]) / 8, kind = .Signed if operands[1] == 1 else .Unsigned, name = name, group = group})
	case .Type_Float:
		append(leaves, Push_Leaf{offset = offset, width = int(operands[0]) / 8, kind = .Float, name = name, group = group})
	case .Type_Bool:
		append(leaves, Push_Leaf{offset = offset, width = 4, kind = .Bool, name = name, group = group})
	case .Type_Pointer, .Type_Untyped_Pointer:
		append(leaves, Push_Leaf{offset = offset, width = 8, kind = .Pointer, name = name, group = group})
	case .Type_Vector:
		size := type_size(layout, operands[0])
		for index in 0 ..< int(operands[1]) {
			flatten_spirv(layout, operands[0], offset + index * size, fmt.tprintf("%v[%v]", name, index), 0, false, leaves, group)
		}
	case .Type_Matrix:
		column := layout.types[operands[0]]
		columns, rows := int(operands[1]), int(column.operands[1])
		scalar := column.operands[0]
		element := type_size(layout, scalar)
		stride := int(matrix_stride) if matrix_stride != 0 else type_size(layout, operands[0])
		for c in 0 ..< columns {
			for r in 0 ..< rows {
				vector := r if row_major else c
				within := c if row_major else r
				flatten_spirv(layout, scalar, offset + vector * stride + within * element, fmt.tprintf("%v[%v][%v]", name, vector, within), 0, false, leaves)
			}
		}
	case .Type_Array:
		length := int(layout.constants[operands[1]])
		stride := int(layout.array_strides[id]) if id in layout.array_strides else type_size(layout, operands[0])
		for index in 0 ..< length {
			flatten_spirv(layout, operands[0], offset + index * stride, fmt.tprintf("%v[%v]", name, index), matrix_stride, row_major, leaves)
		}
	case .Type_Struct:
		for member_type, index in operands {
			member := Spirv_Member{id, u32(index)}
			member_name := layout.member_names[member] if member in layout.member_names else fmt.tprintf("member %v", index)
			flatten_spirv(
				layout,
				member_type,
				offset + int(layout.offsets[member]),
				field_name(name, member_name),
				layout.matrix_strides[member],
				layout.row_major[member],
				leaves,
			)
		}
	case:
		append(leaves, Push_Leaf{offset = offset, width = type_size(layout, id), kind = .Other, name = name, group = group})
	}
}

@(private = "file")
flatten_odin :: proc(info: ^runtime.Type_Info, offset: int, name: string, leaves: ^[dynamic]Push_Leaf) {
	switch info.id {
	case Image:
		append(leaves, Push_Leaf{offset = offset, kind = .Image, name = name})
		return
	case Buffer:
		append(leaves, Push_Leaf{offset = offset, kind = .Buffer, name = name})
		return
	case Sampler:
		append(leaves, Push_Leaf{offset = offset, kind = .Sampler, name = name})
		return
	}
	base := runtime.type_info_base(info)
	#partial switch variant in base.variant {
	case runtime.Type_Info_Integer:
		append(leaves, Push_Leaf{offset = offset, width = base.size, kind = .Signed if variant.signed else .Unsigned, name = name})
	case runtime.Type_Info_Rune:
		append(leaves, Push_Leaf{offset = offset, width = base.size, kind = .Signed, name = name})
	case runtime.Type_Info_Float:
		append(leaves, Push_Leaf{offset = offset, width = base.size, kind = .Float, name = name})
	case runtime.Type_Info_Boolean:
		append(leaves, Push_Leaf{offset = offset, width = base.size, kind = .Bool, name = name})
	case runtime.Type_Info_Pointer, runtime.Type_Info_Multi_Pointer:
		append(leaves, Push_Leaf{offset = offset, width = base.size, kind = .Pointer, name = name})
	case runtime.Type_Info_Enum:
		flatten_odin(variant.base, offset, name, leaves)
	case runtime.Type_Info_Bit_Set:
		if variant.underlying != nil {
			flatten_odin(variant.underlying, offset, name, leaves)
		} else {
			append(leaves, Push_Leaf{offset = offset, width = base.size, kind = .Unsigned, name = name})
		}
	case runtime.Type_Info_Array:
		flatten_odin_elements(variant.elem, variant.count, variant.elem_size, offset, name, leaves)
	case runtime.Type_Info_Enumerated_Array:
		flatten_odin_elements(variant.elem, variant.count, variant.elem_size, offset, name, leaves)
	case runtime.Type_Info_Simd_Vector:
		flatten_odin_elements(variant.elem, variant.count, variant.elem_size, offset, name, leaves)
	case runtime.Type_Info_Matrix:
		for c in 0 ..< variant.column_count {
			for r in 0 ..< variant.row_count {
				vector := c if variant.layout == .Column_Major else r
				within := r if variant.layout == .Column_Major else c
				flatten_odin(variant.elem, offset + (vector * variant.elem_stride + within) * variant.elem_size, fmt.tprintf("%v[%v][%v]", name, vector, within), leaves)
			}
		}
	case runtime.Type_Info_Struct:
		for index in 0 ..< int(variant.field_count) {
			flatten_odin(variant.types[index], offset + int(variant.offsets[index]), field_name(name, variant.names[index]), leaves)
		}
	case:
		append(leaves, Push_Leaf{offset = offset, width = base.size, kind = .Other, name = name})
	}
}

@(private = "file")
flatten_odin_elements :: proc(elem: ^runtime.Type_Info, count, elem_size, offset: int, name: string, leaves: ^[dynamic]Push_Leaf) {
	for index in 0 ..< count {
		flatten_odin(elem, offset + index * elem_size, fmt.tprintf("%v[%v]", name, index), leaves)
	}
}

@(private = "file")
leaf_type :: proc(leaf: Push_Leaf) -> string {
	switch leaf.kind {
	case .Float:
		return fmt.tprintf("f%v (float%v)", leaf.width * 8, "" if leaf.width == 4 else fmt.tprintf("%v_t", leaf.width * 8))
	case .Signed:
		return fmt.tprintf("i%v (int%v)", leaf.width * 8, "" if leaf.width == 4 else fmt.tprintf("%v_t", leaf.width * 8))
	case .Unsigned:
		return fmt.tprintf("u%v (uint%v)", leaf.width * 8, "" if leaf.width == 4 else fmt.tprintf("%v_t", leaf.width * 8))
	case .Bool:
		return fmt.tprintf("%v-byte bool", leaf.width)
	case .Pointer:
		return "8-byte pointer"
	case .Image, .Buffer, .Sampler:
		return fmt.tprintf("%v", leaf.kind)
	case .Other:
	}
	return fmt.tprintf("%v-byte value", leaf.width)
}

@(private = "file")
root_field :: proc(name: string) -> string {
	for character, index in name {
		if character == '.' || character == '[' {
			return name[:index]
		}
	}
	return name
}

@(private = "file")
leaves_match :: proc(shader_leaf, odin_leaf: Push_Leaf) -> bool {
	if shader_leaf.width != odin_leaf.width {
		return false
	}
	if root_field(shader_leaf.name) == root_field(odin_leaf.name) && shader_leaf.name != odin_leaf.name {
		return false
	}
	integral :: proc(kind: Push_Leaf_Kind) -> bool {
		return kind == .Signed || kind == .Unsigned || kind == .Bool || kind == .Pointer
	}
	if shader_leaf.kind == .Float || odin_leaf.kind == .Float {
		return shader_leaf.kind == odin_leaf.kind
	}
	return integral(shader_leaf.kind) && integral(odin_leaf.kind)
}

@(private = "file")
make_push_plan :: proc(push_type: typeid, push_size: int, shader_leaves: []Push_Leaf) -> (plan: Push_Plan) {
	user_size := max(push_size - PUSH_HEADER_SIZE, 0)
	if push_type == nil {
		fmt.assertf(
			user_size == 0,
			"The shader's push block holds %v bytes after Valhalla's %v-byte header; declare the Odin struct that mirrors it with Shader_Config.push_type",
			user_size,
			PUSH_HEADER_SIZE,
		)
		return
	}
	T := push_type
	fmt.assertf(user_size > 0, "Shader_Config.push_type is %v, but the shader declares no push data after Valhalla's header", T)
	fmt.assertf(
		push_size <= int(device.heap_properties.maxPushDataSize),
		"The shader's push block is %v bytes, more than the device's %v bytes of push data",
		push_size,
		device.heap_properties.maxPushDataSize,
	)
	odin_leaves := make([dynamic]Push_Leaf, context.temp_allocator)
	flatten_odin(type_info_of(T), 0, "", &odin_leaves)
	slice.sort_by(odin_leaves[:], proc(a, b: Push_Leaf) -> bool {return a.offset < b.offset})
	gpu_leaves := slice.clone(shader_leaves, context.temp_allocator)
	slice.sort_by(gpu_leaves, proc(a, b: Push_Leaf) -> bool {return a.offset < b.offset})

	mismatch :: proc(T: typeid, gpu: Maybe(Push_Leaf), odin: Maybe(Push_Leaf)) -> ! {
		shader_side := "nothing more"
		if leaf, ok := gpu.?; ok {
			shader_side = fmt.tprintf("%v `%v` at byte %v", leaf_type(leaf), leaf.name, leaf.offset - PUSH_HEADER_SIZE)
		}
		odin_side := "nothing more"
		if leaf, ok := odin.?; ok {
			odin_side = fmt.tprintf("%v `%v`", leaf_type(leaf), leaf.name)
		}
		fmt.panicf(
			"Push data mismatch between the shader's push struct and %v: the shader has %v where %v has %v. Declare the same fields in the same order; an Image, Buffer or Sampler field matches a DescriptorHandle (or uint) in the shader.",
			T,
			shader_side,
			T,
			odin_side,
		)
	}

	copies := make([dynamic]Push_Copy)
	slots := make([dynamic]Push_Slot)
	next := 0
	for odin_leaf in odin_leaves {
		if next >= len(gpu_leaves) {
			mismatch(T, nil, odin_leaf)
		}
		first := gpu_leaves[next]
		if odin_leaf.kind == .Image || odin_leaf.kind == .Buffer || odin_leaf.kind == .Sampler {
			count := 0
			for next < len(gpu_leaves) && gpu_leaves[next].group == first.group {
				leaf := gpu_leaves[next]
				if leaf.width != 4 || leaf.kind != .Unsigned && leaf.kind != .Signed || leaf.offset != first.offset + 4 * count {
					mismatch(T, leaf, odin_leaf)
				}
				count += 1
				next += 1
			}
			if count > 2 {
				mismatch(T, first, odin_leaf)
			}
			append(&slots, Push_Slot{from = odin_leaf.offset, to = first.offset, width = 4 * count, kind = odin_leaf.kind, name = strings.clone(odin_leaf.name)})
			continue
		}
		if !leaves_match(first, odin_leaf) {
			mismatch(T, first, odin_leaf)
		}
		next += 1
		if len(copies) > 0 {
			last := &copies[len(copies) - 1]
			if last.from + last.size == odin_leaf.offset && last.to + last.size == first.offset {
				last.size += odin_leaf.width
				continue
			}
		}
		append(&copies, Push_Copy{from = odin_leaf.offset, to = first.offset, size = odin_leaf.width})
	}
	if next < len(gpu_leaves) {
		mismatch(T, gpu_leaves[next], nil)
	}
	plan.copies = copies[:]
	plan.slots = slots[:]
	return
}

@(private)
delete_push_plan :: proc(plan: ^Push_Plan) {
	for slot in plan.slots {
		delete(slot.name)
	}
	delete(plan.copies)
	delete(plan.slots)
	plan^ = {}
}

@(private)
pack_push_data :: proc(shader: Shader, reads: ^[dynamic]Shader_Resource) {
	recording := shader.recording
	plan := shader.push_plan
	if len(recording.push_source) == 0 {
		return
	}
	assert(len(recording.push_data) == shader.push_size, "the push data no longer fits the shader; set it again after reload_shader changes the push block")
	source := recording.push_source[:]
	data := recording.push_data[:]
	for run in plan.copies {
		copy(data[run.to:][:run.size], source[run.from:][:run.size])
	}
	for slot in plan.slots {
		index: u32
		#partial switch slot.kind {
		case .Image:
			image := (^Image)(&source[slot.from])^
			if image.handle == 0 {
				index = null_image_index()
				break
			}
			fmt.assertf(image.heap_index != 0, "push field `%v`: the image has no descriptor; it must be sampled or storage capable, single-aspect, and made by Valhalla", slot.name)
			index = image.heap_index
			if written_binding(recording, image.heap_index, .Image) {
				index += 1
			} else {
				append(reads, image)
			}
		case .Buffer:
			buffer := (^Buffer)(&source[slot.from])^
			if buffer.handle == 0 {
				index = null_buffer_index()
				break
			}
			fmt.assertf(buffer.heap_index != 0, "push field `%v`: the buffer has no descriptor; it must be made by Valhalla with .Storage usage", slot.name)
			index = buffer.heap_index
			if !written_binding(recording, buffer.heap_index, .Buffer) {
				append(reads, buffer)
			}
		case .Sampler:
			sampler := (^Sampler)(&source[slot.from])^
			index = sampler.heap_index if sampler.heap_index != 0 else null_sampler_index()
		}
		(^u32)(&data[slot.to])^ = index
		if slot.width == 8 {
			(^u32)(&data[slot.to + 4])^ = 0
		}
	}
}

@(private = "file")
written_binding :: proc(recording: Shader_Recording, heap_index: u32, kind: Push_Leaf_Kind) -> bool {
	for binding in recording.bindings {
		if !binding.written {
			continue
		}
		#partial switch resource in binding.resource {
		case Image:
			if kind == .Image && resource.heap_index == heap_index {
				return true
			}
		case Buffer:
			if kind == .Buffer && resource.heap_index == heap_index {
				return true
			}
		}
	}
	return false
}

@(private = "file")
type_size :: proc(layout: ^Spirv_Layout, id: u32, matrix_stride: u32 = 0, row_major := false) -> int {
	type, known := layout.types[id]
	if !known {
		return 0
	}
	operands := type.operands
	#partial switch type.op {
	case .Type_Bool:
		return 4
	case .Type_Int, .Type_Float:
		return int(operands[0]) / 8
	case .Type_Pointer, .Type_Untyped_Pointer:
		return 8
	case .Type_Vector:
		return type_size(layout, operands[0]) * int(operands[1])
	case .Type_Matrix:
		columns := int(operands[1])
		if matrix_stride == 0 {
			return type_size(layout, operands[0]) * columns
		}
		rows := int(layout.types[operands[0]].operands[1])
		return int(matrix_stride) * (rows if row_major else columns)
	case .Type_Array:
		length := int(layout.constants[operands[1]])
		if stride, has_stride := layout.array_strides[id]; has_stride {
			return int(stride) * length
		}
		return type_size(layout, operands[0]) * length
	case .Type_Struct:
		extent := 0
		for member_type, index in operands {
			member := Spirv_Member{id, u32(index)}
			size := type_size(layout, member_type, layout.matrix_strides[member], layout.row_major[member])
			extent = max(extent, int(layout.offsets[member]) + size)
		}
		return extent
	}
	return 0
}

@(private = "file")
@(require_results)
build_pipeline :: proc(code: []u32, entry_points: []string, config: Shader_Config) -> (shader: Shader, err: Error) {
	available, parsed := parse_spirv(code)
	if !parsed {
		return {}, .Invalid_SPIR_V
	}

	shader_stages: Shader_Stages
	push_leaves: []Push_Leaf
	selected := make([dynamic]Spirv_Entry_Point, 0, len(entry_points), context.temp_allocator)
	for name in entry_points {
		matched := false
		for entry_point in available {
			if string(entry_point.name) == name {
				if entry_point.stage in shader_stages {
					log.errorf("Shader has more than one %v entry point", entry_point.stage)
					return {}, .Invalid_Stage_Combination
				}
				shader_stages += {entry_point.stage}
				append(&selected, entry_point)
				if entry_point.push_size > shader.push_size {
					shader.push_size = entry_point.push_size
					push_leaves = entry_point.push_leaves
				}
				matched = true
			}
		}
		if !matched {
			log.errorf("Shader entry point %v is not in the SPIR-V", name)
			return {}, .Entry_Point_Not_Found
		}
	}

	shader.push_plan = make_push_plan(config.push_type, shader.push_size, push_leaves)
	shader.push_type = config.push_type
	shader.pipeline_cache = config.pipeline_cache
	shader.name = strings.clone(config.name) if config.name != "" else strings.join(entry_points, "+")

	module_info: vk.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code) * size_of(u32),
		pCode    = raw_data(code),
	}
	stages := make([]vk.PipelineShaderStageCreateInfo, len(selected), context.temp_allocator)
	for entry_point, index in selected {
		stages[index] = {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pNext = &module_info,
			stage = STAGE_FLAGS[entry_point.stage],
			pName = entry_point.name,
		}
	}

	create_flags: vk.PipelineCreateFlags2CreateInfo = {
		sType = .PIPELINE_CREATE_FLAGS_2_CREATE_INFO,
		flags = {.DESCRIPTOR_HEAP_EXT},
	}

	if .Compute in shader_stages {
		if shader_stages != {.Compute} {
			log.error("A compute shader cannot be combined with other stages")
			return {}, .Invalid_Stage_Combination
		}
		shader.variant = Compute_Shader {
			group_size = selected[0].group_size,
		}
		pipeline_info: vk.ComputePipelineCreateInfo = {
			sType = .COMPUTE_PIPELINE_CREATE_INFO,
			pNext = &create_flags,
			stage = stages[0],
		}
		if res := vk.CreateComputePipelines(device.handle, config.pipeline_cache.handle, 1, &pipeline_info, nil, &shader.handle); res != .SUCCESS {
			log.errorf("Failed to create compute pipeline: %v", res)
			return {}, .Pipeline_Creation_Failed
		}
		name_object(.PIPELINE, u64(shader.handle), shader.name)
		return
	}

	if shader_stages & {.Vertex, .Mesh} == {} {
		log.error("A graphics shader needs a vertex or mesh entry point")
		return {}, .Invalid_Stage_Combination
	}
	mesh := .Mesh in shader_stages
	if mesh && shader_stages & {.Vertex, .Tessellation_Control, .Tessellation_Evaluation, .Geometry} != {} {
		log.error("A mesh shader replaces the vertex, tessellation and geometry stages")
		return {}, .Invalid_Stage_Combination
	}
	if .Task in shader_stages && !mesh {
		log.error("A task shader needs a mesh shader")
		return {}, .Invalid_Stage_Combination
	}
	if mesh && !device.optional.mesh_shader || .Task in shader_stages && !device.optional.task_shader {
		log.error("This device does not support mesh or task shaders (VK_EXT_mesh_shader)")
		return {}, .Unsupported_Stage
	}
	if mesh && config.view_mask != 0 && !device.optional.multiview_mesh_shader {
		log.error("This device does not support multiview with mesh shaders")
		return {}, .Unsupported_Stage
	}
	shader.variant = Graphics_Shader {
		config = config,
		mesh   = mesh,
	}
	dynamic_states := make([dynamic]vk.DynamicState, 0, len(GRAPHICS_DYNAMIC_STATES), context.temp_allocator)
	for state in GRAPHICS_DYNAMIC_STATES {
		if !mesh || state != .PRIMITIVE_TOPOLOGY && state != .PRIMITIVE_RESTART_ENABLE {
			append(&dynamic_states, state)
		}
	}

	colour_count := colour_format_count(config)
	colour_formats := config.colour_formats
	rendering_info: vk.PipelineRenderingCreateInfo = {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		viewMask                = config.view_mask,
		colorAttachmentCount    = u32(colour_count),
		pColorAttachmentFormats = &colour_formats[0],
		depthAttachmentFormat   = config.depth_format,
		stencilAttachmentFormat = config.stencil_format,
	}
	create_flags.pNext = &rendering_info

	blend_attachments := make([]vk.PipelineColorBlendAttachmentState, colour_count, context.temp_allocator)
	for &attachment in blend_attachments {
		attachment.colorWriteMask = {.R, .G, .B, .A}
	}

	pipeline_info: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &create_flags,
		stageCount          = u32(len(stages)),
		pStages             = raw_data(stages),
		pVertexInputState   = &{sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO},
		pInputAssemblyState = &{sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, topology = .TRIANGLE_LIST},
		pViewportState      = &{sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO},
		pRasterizationState = &{sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO, polygonMode = .FILL, lineWidth = 1},
		pMultisampleState   = &{sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, rasterizationSamples = {._1}},
		pDepthStencilState  = &{sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO, maxDepthBounds = 1},
		pColorBlendState    = &{
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			attachmentCount = u32(len(blend_attachments)),
			pAttachments = raw_data(blend_attachments),
		},
		pDynamicState       = &{
			sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = u32(len(dynamic_states)),
			pDynamicStates = raw_data(dynamic_states),
		},
	}
	if res := vk.CreateGraphicsPipelines(device.handle, config.pipeline_cache.handle, 1, &pipeline_info, nil, &shader.handle); res != .SUCCESS {
		log.errorf("Failed to create graphics pipeline: %v", res)
		return {}, .Pipeline_Creation_Failed
	}
	name_object(.PIPELINE, u64(shader.handle), shader.name)
	return
}

Pipeline_Cache :: struct {
	handle: vk.PipelineCache,
}

@(require_results)
make_empty_pipeline_cache :: proc() -> (cache: Pipeline_Cache, err: Error) {
	return create_pipeline_cache(nil)
}

@(require_results)
make_pipeline_cache_from_file :: proc(filename: string) -> (cache: Pipeline_Cache, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	data, read_err := os.read_entire_file(filename, context.temp_allocator)
	if read_err != nil {
		return {}, .Pipeline_Cache_File_Read_Failed
	}
	if !pipeline_cache_matches(data) {
		log.infof("%v is not a pipeline cache for this device and driver", filename)
		return {}, .Pipeline_Cache_Incompatible
	}
	return create_pipeline_cache(data)
}

make_pipeline_cache :: proc {
	make_empty_pipeline_cache,
	make_pipeline_cache_from_file,
}

@(require_results)
write_pipeline_cache_to_file :: proc(cache: Pipeline_Cache, filename: string) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	assert(cache.handle != 0, "write_pipeline_cache_to_file needs a pipeline cache")
	size: int
	if vk.GetPipelineCacheData(device.handle, cache.handle, &size, nil) != .SUCCESS {
		return .Pipeline_Cache_Write_Failed
	}
	data := make([]u8, size, context.temp_allocator)
	if size > 0 && vk.GetPipelineCacheData(device.handle, cache.handle, &size, raw_data(data)) != .SUCCESS {
		return .Pipeline_Cache_Write_Failed
	}
	temporary := strings.concatenate({filename, ".tmp"}, context.temp_allocator)
	if err := os.write_entire_file(temporary, data[:size]); err != nil {
		log.errorf("Could not write the pipeline cache to %v: %v", temporary, err)
		return .Pipeline_Cache_Write_Failed
	}
	if err := os.rename(temporary, filename); err != nil {
		log.errorf("Could not move the pipeline cache into %v: %v", filename, err)
		return .Pipeline_Cache_Write_Failed
	}
	return nil
}

delete_pipeline_cache :: proc(cache: ^Pipeline_Cache) {
	if cache.handle != 0 {
		vk.DestroyPipelineCache(device.handle, cache.handle, nil)
	}
	cache^ = {}
}

@(private = "file")
create_pipeline_cache :: proc(data: []u8) -> (cache: Pipeline_Cache, err: Error) {
	assert(initialised, "Valhalla.init must be called before make_pipeline_cache")
	info: vk.PipelineCacheCreateInfo = {
		sType           = .PIPELINE_CACHE_CREATE_INFO,
		initialDataSize = len(data),
		pInitialData    = raw_data(data),
	}
	if res := vk.CreatePipelineCache(device.handle, &info, nil, &cache.handle); res != .SUCCESS {
		log.errorf("Failed to create a pipeline cache: %v", res)
		return {}, .Pipeline_Cache_Creation_Failed
	}
	return
}

@(private = "file")
pipeline_cache_matches :: proc(data: []u8) -> bool {
	Header :: struct {
		length:  u32,
		version: vk.PipelineCacheHeaderVersion,
		vendor:  u32,
		device:  u32,
		uuid:    [vk.UUID_SIZE]u8,
	}
	if len(data) < size_of(Header) {
		return false
	}
	header := (^Header)(raw_data(data))^
	properties := device.properties
	return(
		int(header.length) >= size_of(Header) &&
		header.version == .ONE &&
		header.vendor == properties.vendorID &&
		header.device == properties.deviceID &&
		header.uuid == properties.pipelineCacheUUID \
	)
}
