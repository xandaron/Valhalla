package Image_Editor

import "core:fmt"
import "core:log"
import "core:math/bits"
import "core:math/linalg"
import "core:path/filepath"
import "core:strings"
import vk "vendor:vulkan"

import imgui "../../deps/imgui"
import tinyfd "../../deps/tinyfiledialogs"
import Valhalla "../../src"
import valhalla_imgui "../../src/imgui"

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Image editor failed: %v", err)
	}
}

// ===[ Graph ]=================================================================

CODE_CAPACITY :: 16 * 1024

PREVIEW_WIDTH :: 160

PIPELINE_CACHE_FILE :: "image_editor.pipeline_cache"

CUSTOM_SIZE :: 1024

Pin_Kind :: enum {
	Image,
	Float,
}

Node_Kind :: enum {
	Image_File,
	Adjust,
	Blur,
	Sharpen,
	Mix,
	Custom,
	Value,
	Time,
	Output,
}

NODE_TITLES := [Node_Kind]cstring {
	.Image_File = "Image",
	.Adjust     = "Adjust",
	.Blur       = "Blur",
	.Sharpen    = "Sharpen",
	.Mix        = "Mix",
	.Custom     = "Custom shader",
	.Value      = "Value",
	.Time       = "Time",
	.Output     = "Output",
}

NODE_OUTPUTS := [Node_Kind]Maybe(Pin_Kind) {
	.Image_File = .Image,
	.Adjust     = .Image,
	.Blur       = .Image,
	.Sharpen    = .Image,
	.Mix        = .Image,
	.Custom     = .Image,
	.Value      = .Float,
	.Time       = .Float,
	.Output     = nil,
}

Input :: struct {
	name:    cstring,
	kind:    Pin_Kind,
	value:   f32,
	minimum: f32,
	maximum: f32,
	link:    ^Node,
	shown:   f32,
	pin:     [2]f32,
}

Node :: struct {
	id:              i32,
	kind:            Node_Kind,
	position:        [2]f32,
	size:            [2]f32,
	inputs:          [dynamic]Input,
	value:           f32,
	output_pin:      [2]f32,
	path:            string,
	source:          Valhalla.Image,
	load_error:      string,
	code:            [CODE_CAPACITY]u8,
	shader:          Valhalla.Shader,
	compile_log:     string,
	compile_failed:  bool,
	image:           Valhalla.Image,
	temp:            Valhalla.Image,
	preview:         Valhalla.Image,
	written:         Valhalla.Image,
	preview_shown:   Valhalla.Image,
	workload:        Valhalla.Workload,
	has_workload:    bool,
	recorded:        bool,
	stale:           bool,
	slot:            u32,
	valid:           bool,
	doomed:          bool,
}

DEFAULT_CODE :: `float4 effect(float2 uv, float4 p) {
	float2 shift = float2(p.x * 8 * texel_size().x, 0);
	float r = sample_a(uv + shift).r;
	float g = sample_a(uv).g;
	float b = sample_a(uv - shift).b;
	return float4(r, g, b, 1);
}
`

CUSTOM_PRELUDE :: `import Valhalla;

struct NodeParams {
	float4 p0;
	float4 p1;
};

struct NodePush {
	ValhallaHeader header;
	float2 texel;
	float2 direction;
	DescriptorHandle<Texture2D<float4>> a;
	DescriptorHandle<Texture2D<float4>> b;
	DescriptorHandle<SamplerState> sampler;
	DescriptorHandle<StructuredBuffer<NodeParams>> params;
};

[[vk::push_constant]]
ConstantBuffer<NodePush> push;

NodeParams params() {
	return push.params[push.header.draw_data];
}

struct Varyings {
	float4 position : SV_Position;
	float2 uv : TEXCOORD0;
};

[shader("vertex")]
Varyings custom_vertex(uint vertex_id : SV_VertexID) {
	float2 corner = float2((vertex_id << 1) & 2, vertex_id & 2);
	Varyings output;
	output.position = float4(corner * 2 - 1, 0, 1);
	output.uv = corner;
	return output;
}

float4 sample_a(float2 uv) {
	return push.a.Sample(push.sampler, uv);
}

float4 sample_b(float2 uv) {
	return push.b.Sample(push.sampler, uv);
}

float2 texel_size() {
	return push.texel;
}

#line 1 "effect"
`

CUSTOM_EPILOGUE :: `

[shader("fragment")]
float4 custom_fragment(Varyings input) : SV_Target {
	return effect(input.uv, params().p0);
}
`

Node_Push :: struct {
	texel:     [2]f32,
	direction: [2]f32,
	a:         Valhalla.Image,
	b:         Valhalla.Image,
	sampler:   Valhalla.Sampler,
	params:    Valhalla.Buffer,
}

Node_Params :: struct {
	p0: [4]f32,
	p1: [4]f32,
}

Link_Drag :: struct {
	active:       bool,
	source:       ^Node,
	target:       ^Node,
	target_input: int,
}

Editor :: struct {
	window:            Valhalla.Window,
	surface:           ^Valhalla.Surface,
	adjust:            Valhalla.Shader,
	blur:              Valhalla.Shader,
	sharpen:           Valhalla.Shader,
	mix:               Valhalla.Shader,
	encode:            Valhalla.Shader,
	present:           Valhalla.Shader,
	sampler:           Valhalla.Sampler,
	black:             Valhalla.Image,
	display:           Valhalla.Image,
	display_shown:     Valhalla.Image,
	display_valid:     bool,
	nodes:             [dynamic]^Node,
	next_id:           i32,
	scrolling:         [2]f32,
	selected:          ^Node,
	editing:           ^Node,
	drag:              Link_Drag,
	menu_node:         ^Node,
	add_position:      [2]f32,
	fit:               bool,
	zoom:              f32,
	save_path:         string,
	status:            string,
	show_viewer:       bool,
	show_graph:        bool,
	show_adjustments:  bool,
	show_shader:       bool,
	show_imgui_demo:   bool,
	target:         Valhalla.Image,
	pipeline_cache:    Valhalla.Pipeline_Cache,
	graph_signature:   u64,
	graph_recorded:    bool,
	graph_last:        Valhalla.Execution,
	params:            Valhalla.Buffer,
	param_values:      [dynamic]Node_Params,
	params_written:    bool,
	frames:            [Valhalla.MAX_EXECUTIONS_IN_FLIGHT]Valhalla.Workload,
	next_frame:        int,
	last:              Valhalla.Execution,
	open_node:         ^Node,
	open_path:         string,
}

make_node :: proc(editor: ^Editor, kind: Node_Kind, position: [2]f32) -> ^Node {
	node := new(Node)
	node.id = editor.next_id
	editor.next_id += 1
	node.kind = kind
	node.position = position
	image :: proc(node: ^Node, name: cstring) {
		append(&node.inputs, Input{name = name, kind = .Image})
	}
	number :: proc(node: ^Node, name: cstring, value, minimum, maximum: f32) {
		append(&node.inputs, Input{name = name, kind = .Float, value = value, minimum = minimum, maximum = maximum})
	}
	switch kind {
	case .Image_File, .Time:
	case .Adjust:
		image(node, "in")
		number(node, "exposure", 0, -5, 5)
		number(node, "contrast", 1, 0, 3)
		number(node, "saturation", 1, 0, 3)
		number(node, "gamma", 1, 0.1, 4)
		number(node, "temperature", 0, -5, 5)
	case .Blur:
		image(node, "in")
		number(node, "radius", 4, 0, 64)
	case .Sharpen:
		image(node, "in")
		number(node, "amount", 0.5, 0, 4)
	case .Mix:
		image(node, "a")
		image(node, "b")
		number(node, "factor", 0.5, 0, 1)
	case .Custom:
		image(node, "a")
		image(node, "b")
		number(node, "p.x", 0.5, 0, 1)
		number(node, "p.y", 0, 0, 1)
		number(node, "p.z", 0, 0, 1)
		number(node, "p.w", 0, 0, 1)
		copy(node.code[:], DEFAULT_CODE)
		compile_custom(editor, node)
	case .Value:
		node.value = 1
	case .Output:
		image(node, "in")
	}
	append(&editor.nodes, node)
	return node
}

free_node :: proc(node: ^Node) {
	Valhalla.delete_image(&node.source)
	Valhalla.delete_image(&node.image)
	Valhalla.delete_image(&node.temp)
	Valhalla.delete_image(&node.preview)
	Valhalla.delete_shader(&node.shader)
	Valhalla.delete_workload(&node.workload)
	delete(node.inputs)
	delete(node.path)
	delete(node.load_error)
	delete(node.compile_log)
	free(node)
}

delete_doomed_nodes :: proc(editor: ^Editor) -> Valhalla.Error {
	for node in editor.nodes {
		if node.doomed {
			Valhalla.wait_execution(editor.last) or_return
			break
		}
	}
	for index := len(editor.nodes) - 1; index >= 0; index -= 1 {
		node := editor.nodes[index]
		if !node.doomed {
			continue
		}
		for other in editor.nodes {
			for &input in other.inputs {
				if input.link == node {
					input.link = nil
				}
			}
		}
		if editor.selected == node {
			editor.selected = nil
		}
		if editor.editing == node {
			editor.editing = nil
		}
		if editor.open_node == node {
			editor.open_node = nil
		}
		ordered_remove(&editor.nodes, index)
		free_node(node)
	}
	return nil
}

default_graph :: proc(editor: ^Editor) {
	for node in editor.nodes {
		node.doomed = true
	}
	source := make_node(editor, .Image_File, {20, 30})
	adjust := make_node(editor, .Adjust, {270, 10})
	blur := make_node(editor, .Blur, {560, 30})
	output := make_node(editor, .Output, {810, 50})
	adjust.inputs[0].link = source
	blur.inputs[0].link = adjust
	blur.inputs[1].value = 0
	output.inputs[0].link = blur
	editor.scrolling = {}
}

first_node :: proc(editor: ^Editor, kind: Node_Kind) -> ^Node {
	for node in editor.nodes {
		if node.kind == kind && !node.doomed {
			return node
		}
	}
	return nil
}

depends_on :: proc(node, upstream: ^Node) -> bool {
	if node == upstream {
		return true
	}
	for input in node.inputs {
		if input.link != nil && depends_on(input.link, upstream) {
			return true
		}
	}
	return false
}

connect :: proc(editor: ^Editor, source, target: ^Node, input: int) {
	if depends_on(source, target) {
		editor.status = "That link would make a cycle"
		return
	}
	target.inputs[input].link = source
}

ordered_nodes :: proc(editor: ^Editor, allocator := context.temp_allocator) -> []^Node {
	order := make([dynamic]^Node, 0, len(editor.nodes), allocator)
	visited := make(map[^Node]bool, allocator = allocator)
	visit :: proc(node: ^Node, order: ^[dynamic]^Node, visited: ^map[^Node]bool) {
		if node in visited || node.doomed {
			return
		}
		visited[node] = true
		for input in node.inputs {
			if input.link != nil {
				visit(input.link, order, visited)
			}
		}
		append(order, node)
	}
	for node in editor.nodes {
		visit(node, &order, &visited)
	}
	return order[:]
}

input_value :: proc(input: Input) -> f32 {
	return input.link.value if input.link != nil else input.value
}

// ===[ Evaluation ]============================================================

ensure_image :: proc(image: ^Valhalla.Image, format: vk.Format, size: [2]u32) -> Valhalla.Error {
	if image.handle == 0 {
		image^ = Valhalla.make_image(format, {size.x, size.y, 1}, usage = {.Attachment}) or_return
		return nil
	}
	_ = Valhalla.resize_image(image, {size.x, size.y, 1}) or_return
	return nil
}

run_pass :: proc(
	editor: ^Editor,
	workload: ^Valhalla.Workload,
	shader: ^Valhalla.Shader,
	target: Valhalla.Image,
	a: Maybe(Valhalla.Image),
	b: Maybe(Valhalla.Image) = nil,
	slot: u32 = 0,
	direction: [2]f32 = {},
) -> (
	written: Valhalla.Image,
	err: Valhalla.Error,
) {
	Valhalla.reset_shader(shader)
	written = Valhalla.bind_shader_colour(shader, target)
	Valhalla.set_push_data(
		shader,
		Node_Push {
			texel = {1 / f32(target.extent.x), 1 / f32(target.extent.y)},
			direction = direction,
			a = a.? or_else editor.black,
			b = b.? or_else editor.black,
			sampler = editor.sampler,
			params = editor.params,
		},
	)
	Valhalla.draw(shader, 3, draw_data = slot)
	Valhalla.bind_shader(workload, shader^) or_return
	return
}

image_input :: proc(node: ^Node, index: int) -> Maybe(Valhalla.Image) {
	source := node.inputs[index].link
	if source == nil || !source.valid {
		return nil
	}
	return source.written
}

graph_signature :: proc(editor: ^Editor) -> u64 {
	hash: u64 = 14695981039346656037
	mix :: proc(hash: ^u64, value: u64) {
		hash^ = (hash^ ~ value) * 1099511628211
	}
	for node in editor.nodes {
		if node.doomed {
			continue
		}
		mix(&hash, u64(node.id))
		mix(&hash, u64(node.kind))
		mix(&hash, u64(node.source.handle))
		mix(&hash, u64(node.shader.handle))
		for input in node.inputs {
			mix(&hash, u64(input.link.id) + 1 if input.link != nil && !input.link.doomed else 0)
		}
	}
	return hash
}

ensure_display :: proc(editor: ^Editor, size: [2]u32) -> Valhalla.Error {
	if editor.display.handle != 0 && editor.display.extent.xy == size {
		return nil
	}
	Valhalla.delete_image(&editor.display)
	editor.display = Valhalla.make_image(.R8G8B8A8_SRGB, {size.x, size.y, 1}, usage = {.Attachment}, mip_levels = u32(bits.len(max(size.x, size.y)))) or_return
	return nil
}

record_graph :: proc(editor: ^Editor, order: []^Node) -> Valhalla.Error {
	Valhalla.wait_execution(editor.last) or_return
	if editor.params.size < vk.DeviceSize(max(len(order), 1) * size_of(Node_Params)) {
		Valhalla.delete_buffer(&editor.params)
		editor.params = Valhalla.make_buffer(max(len(order), 64) * size_of(Node_Params), {.Storage}, .Host_Visible) or_return
	}
	resize(&editor.param_values, len(order))
	editor.params_written = false
	editor.display_valid = false
	for node in editor.nodes {
		node.valid = false
		node.recorded = false
		node.preview_shown = editor.black
	}
	for node, index in order {
		node.slot = u32(index)
	}
	for node in order {
		if node_has_work(editor, node) {
			record_node(editor, node) or_return
		}
		node.stale = node.recorded
	}
	if !editor.display_valid {
		editor.display_shown = editor.black
	}
	return nil
}

node_has_work :: proc(editor: ^Editor, node: ^Node) -> bool {
	switch node.kind {
	case .Value, .Time:
		return false
	case .Image_File:
		return node.source.handle != 0
	case .Adjust, .Blur, .Sharpen:
		return image_input(node, 0) != nil
	case .Mix:
		return image_input(node, 0) != nil || image_input(node, 1) != nil
	case .Custom:
		return node.shader.handle != 0
	case .Output:
		return image_input(node, 0) != nil && node == first_node(editor, .Output)
	}
	return false
}

record_node :: proc(editor: ^Editor, node: ^Node) -> Valhalla.Error {
	if node.has_workload {
		Valhalla.reset_workload(&node.workload) or_return
	} else {
		node.workload = Valhalla.make_workload(fmt.tprintf("%v %v", NODE_TITLES[node.kind], node.id)) or_return
		node.has_workload = true
	}
	workload := &node.workload

	switch node.kind {
	case .Value, .Time:
	case .Image_File:
		node.written = node.source
	case .Adjust, .Blur, .Sharpen:
		a := image_input(node, 0).?
		ensure_image(&node.image, .R16G16B16A16_SFLOAT, a.extent.xy) or_return
		#partial switch node.kind {
		case .Adjust:
			node.written = run_pass(editor, workload, &editor.adjust, node.image, a, nil, node.slot) or_return
		case .Blur:
			ensure_image(&node.temp, .R16G16B16A16_SFLOAT, a.extent.xy) or_return
			across := run_pass(editor, workload, &editor.blur, node.temp, a, nil, node.slot, {1, 0}) or_return
			node.written = run_pass(editor, workload, &editor.blur, node.image, across, nil, node.slot, {0, 1}) or_return
		case .Sharpen:
			node.written = run_pass(editor, workload, &editor.sharpen, node.image, a, nil, node.slot) or_return
		}
	case .Mix:
		a, has_a := image_input(node, 0).?
		b, has_b := image_input(node, 1).?
		if !has_a {
			a = b
		} else if !has_b {
			b = a
		}
		ensure_image(&node.image, .R16G16B16A16_SFLOAT, a.extent.xy) or_return
		node.written = run_pass(editor, workload, &editor.mix, node.image, a, b, node.slot) or_return
	case .Custom:
		a := image_input(node, 0)
		b := image_input(node, 1)
		size := [2]u32{CUSTOM_SIZE, CUSTOM_SIZE}
		if image, has := a.?; has {
			size = image.extent.xy
		} else if image, has := b.?; has {
			size = image.extent.xy
		}
		ensure_image(&node.image, .R16G16B16A16_SFLOAT, size) or_return
		node.written = run_pass(editor, workload, &node.shader, node.image, a, b, node.slot) or_return
	case .Output:
		a := image_input(node, 0).?
		ensure_display(editor, a.extent.xy) or_return
		shown := run_pass(editor, workload, &editor.present, editor.display, a) or_return
		editor.display_shown = Valhalla.workload_produces(workload, Valhalla.generate_mips(workload, shown))
		editor.display_valid = true
	}

	if node.kind != .Output {
		extent := node.written.extent
		width := min(u32(PREVIEW_WIDTH), extent.x)
		height := max(u32(f32(extent.y) * f32(width) / f32(extent.x)), 1)
		ensure_image(&node.preview, .R8G8B8A8_UNORM, {width, height}) or_return
		preview := run_pass(editor, workload, &editor.encode, node.preview, node.written) or_return
		node.preview_shown = Valhalla.workload_produces(workload, preview)
		if node.kind != .Image_File {
			node.written = Valhalla.workload_produces(workload, node.written)
		}
		node.valid = true
	}
	Valhalla.finalize_workload(workload) or_return
	node.recorded = true
	return nil
}

update_params :: proc(editor: ^Editor, order: []^Node) -> Valhalla.Error {
	time := f32(Valhalla.time())
	for node in order {
		if node.kind == .Time {
			node.value = time
		}
	}
	changed := !editor.params_written
	for node in order {
		values: [8]f32
		count := 0
		for &input in node.inputs {
			input.shown = input_value(input)
			if input.kind == .Float {
				values[count] = input.shown
				count += 1
			}
		}
		params := Node_Params {
			p0 = {values[0], values[1], values[2], values[3]},
			p1 = {values[4], values[5], values[6], values[7]},
		}
		if node.valid && editor.param_values[node.slot] != params {
			editor.param_values[node.slot] = params
			node.stale = true
			changed = true
		}
	}
	if !changed {
		return nil
	}
	Valhalla.wait_execution(editor.graph_last) or_return
	Valhalla.load_memory_to_buffer(raw_bytes(editor.param_values[:]), editor.params) or_return
	editor.params_written = true
	return nil
}

raw_bytes :: proc(data: []$T) -> []u8 {
	return ([^]u8)(raw_data(data))[:len(data) * size_of(T)]
}

compile_custom :: proc(editor: ^Editor, node: ^Node) {
	source := strings.concatenate({CUSTOM_PRELUDE, string(cstring(&node.code[0])), CUSTOM_EPILOGUE}, context.temp_allocator)
	shader, err := Valhalla.make_shader(
		transmute([]u8)source,
		[]string{"custom_vertex", "custom_fragment"},
		pipeline_cache = editor.pipeline_cache, push_type = Node_Push, colour_formats = {0 = .R16G16B16A16_SFLOAT},
	)
	diagnostics := Valhalla.shader_diagnostics()
	delete(node.compile_log)
	if err != nil {
		node.compile_failed = true
		node.compile_log = fmt.aprintf("%v\n%s", err, diagnostics)
		return
	}
	Valhalla.delete_shader(&node.shader)
	node.shader = shader
	node.compile_failed = false
	node.compile_log = fmt.aprintf("Compiled\n%s", diagnostics) if diagnostics != "" else strings.clone("Compiled")
}

// ===[ Files ]=================================================================

IMAGE_FILTERS := [?]cstring{"*.png", "*.jpg", "*.jpeg", "*.bmp", "*.tga", "*.hdr", "*.psd", "*.gif"}

PNG_FILTERS := [?]cstring{"*.png"}

open_image :: proc(editor: ^Editor, node: ^Node) {
	picked := tinyfd.openFileDialog("Open image", nil, len(IMAGE_FILTERS), &IMAGE_FILTERS[0], "Images", 0)
	if picked == nil {
		return
	}
	delete(editor.open_path)
	editor.open_path = strings.clone(string(picked))
	editor.open_node = node
}

load_opened_image :: proc(editor: ^Editor) -> Valhalla.Error {
	node, path := editor.open_node, editor.open_path
	if node == nil {
		return nil
	}
	defer {
		delete(editor.open_path)
		editor.open_path = ""
		editor.open_node = nil
	}
	image, err := Valhalla.make_image_from_file(path)
	delete(node.load_error)
	node.load_error = ""
	if err != nil {
		node.load_error = fmt.aprintf("Could not load %v (%v)", filepath.base(path), err)
		return nil
	}
	Valhalla.wait_execution(editor.last) or_return
	Valhalla.delete_image(&node.source)
	node.source = image
	delete(node.path)
	node.path = strings.clone(path)
	Valhalla.set_window_title(editor.window, fmt.tprintf("Image editor: %v", filepath.base(path)))
	return nil
}

ask_save_path :: proc(editor: ^Editor) {
	picked := tinyfd.saveFileDialog("Save output", "output.png", len(PNG_FILTERS), &PNG_FILTERS[0], "PNG image")
	if picked == nil {
		return
	}
	path := string(picked)
	delete(editor.save_path)
	editor.save_path = strings.clone(path) if strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".png") else strings.concatenate({path, ".png"})
}

// ===[ Interface ]=============================================================

PIN_RADIUS :: 6

NODE_PADDING :: [2]f32{10, 8}

NODE_WIDGET_WIDTH :: 150

PIN_COLOURS := [Pin_Kind][4]f32 {
	.Image = {0.35, 0.8, 0.75, 1},
	.Float = {0.95, 0.65, 0.25, 1},
}

colour_u32 :: proc(colour: [4]f32) -> u32 {
	return imgui.ColorConvertFloat4ToU32(colour)
}

build_ui :: proc(editor: ^Editor) {
	imgui.DockSpaceOverViewport(0, nil, {.PassthruCentralNode})
	io := imgui.GetIO()

	if imgui.BeginMainMenuBar() {
		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Open image...", "Ctrl+O") {
				open_into_graph(editor)
			}
			if imgui.MenuItem("Save output as...", "Ctrl+S", false, editor.display_valid) {
				ask_save_path(editor)
			}
			imgui.Separator()
			if imgui.MenuItem("Quit") {
				Valhalla.request_close(editor.window)
			}
			imgui.EndMenu()
		}
		if imgui.BeginMenu("Graph") {
			add_node_items(editor, {80, 80} - editor.scrolling)
			imgui.Separator()
			if imgui.MenuItem("Reset to default") {
				default_graph(editor)
			}
			imgui.EndMenu()
		}
		if imgui.BeginMenu("Windows") {
			imgui.MenuItemBoolPtr("Viewer", nil, &editor.show_viewer)
			imgui.MenuItemBoolPtr("Shader graph", nil, &editor.show_graph)
			imgui.MenuItemBoolPtr("Adjustments", nil, &editor.show_adjustments)
			imgui.MenuItemBoolPtr("Shader editor", nil, &editor.show_shader)
			imgui.MenuItemBoolPtr("Dear ImGui demo", nil, &editor.show_imgui_demo)
			imgui.EndMenu()
		}
		if editor.status != "" {
			imgui.TextDisabled("  %s", strings.clone_to_cstring(editor.status, context.temp_allocator))
		}
		imgui.EndMainMenuBar()
	}

	if !io.WantTextInput && (imgui.IsKeyDown(.Key_LeftCtrl) || imgui.IsKeyDown(.Key_RightCtrl)) {
		if imgui.IsKeyPressed(.Key_O, false) {
			open_into_graph(editor)
		}
		if imgui.IsKeyPressed(.Key_S, false) && editor.display_valid {
			ask_save_path(editor)
		}
	}

	if editor.show_viewer {
		viewer_window(editor)
	}
	if editor.show_adjustments {
		adjustments_window(editor)
	}
	if editor.show_graph {
		graph_window(editor)
	}
	if editor.show_shader {
		shader_window(editor)
	}
	if editor.show_imgui_demo {
		imgui.ShowDemoWindow(&editor.show_imgui_demo)
	}
}

open_into_graph :: proc(editor: ^Editor) {
	node := first_node(editor, .Image_File)
	if node == nil {
		node = make_node(editor, .Image_File, {40, 120} - editor.scrolling)
	}
	open_image(editor, node)
}

add_node_items :: proc(editor: ^Editor, position: [2]f32) {
	for kind in Node_Kind {
		enabled := kind != .Output || first_node(editor, .Output) == nil
		if imgui.MenuItem(NODE_TITLES[kind], nil, false, enabled) {
			editor.selected = make_node(editor, kind, position)
		}
	}
}

viewer_window :: proc(editor: ^Editor) {
	imgui.SetNextWindowPos({20, 40}, .FirstUseEver)
	imgui.SetNextWindowSize({1000, 560}, .FirstUseEver)
	if imgui.Begin("Viewer", &editor.show_viewer) {
		if !editor.display_valid {
			if first_node(editor, .Image_File) == nil || first_node(editor, .Image_File).source.handle == 0 {
				if imgui.Button("Open an image...", {220, 40}) {
					open_into_graph(editor)
				}
			} else if first_node(editor, .Output) == nil {
				imgui.TextWrapped("Add an Output node to the graph and connect it to see the result here.")
			} else {
				imgui.TextWrapped("The Output node has nothing valid connected to it.")
			}
		} else {
			extent := [2]f32{f32(editor.display.extent.x), f32(editor.display.extent.y)}
			imgui.Checkbox("Fit", &editor.fit)
			imgui.SameLine()
			imgui.BeginDisabled(editor.fit)
			imgui.SetNextItemWidth(160)
			imgui.SliderFloat("Zoom", &editor.zoom, 0.05, 8, "%.2fx", {.Logarithmic})
			imgui.EndDisabled()
			imgui.SameLine()
			imgui.Text("%u x %u", editor.display.extent.x, editor.display.extent.y)
			if imgui.BeginChild("view", {0, 0}, {}, {.HorizontalScrollbar}) {
				available := imgui.GetContentRegionAvail()
				scale := editor.zoom
				if editor.fit {
					scale = max(min(available.x / extent.x, available.y / extent.y), 0.01)
				}
				size := extent * scale
				cursor := imgui.GetCursorScreenPos()
				imgui.SetCursorScreenPos(linalg.floor(cursor + linalg.max(available - size, 0) * 0.5))
				imgui.Image(valhalla_imgui.texture(editor.display_shown, .Nearest if scale >= 1 else .Linear), size)
				if imgui.IsItemHovered() && imgui.GetIO().MouseWheel != 0 && imgui.IsKeyDown(.Key_LeftCtrl) {
					editor.fit = false
					editor.zoom = clamp(editor.zoom * (1 + imgui.GetIO().MouseWheel * 0.1), 0.05, 8)
				}
			}
			imgui.EndChild()
		}
	}
	imgui.End()
}

adjustments_window :: proc(editor: ^Editor) {
	imgui.SetNextWindowPos({1040, 40}, .FirstUseEver)
	imgui.SetNextWindowSize({540, 560}, .FirstUseEver)
	if imgui.Begin("Adjustments", &editor.show_adjustments) {
		for node in ordered_nodes(editor) {
			if node.kind == .Output {
				continue
			}
			imgui.PushIDInt(node.id)
			label := fmt.ctprintf("%s##header", NODE_TITLES[node.kind])
			if imgui.CollapsingHeader(label, {.DefaultOpen}) {
				node_body(editor, node, false, 0)
			}
			imgui.PopID()
		}
	}
	imgui.End()
}

shader_window :: proc(editor: ^Editor) {
	imgui.SetNextWindowPos({1040, 620}, .FirstUseEver)
	imgui.SetNextWindowSize({540, 360}, .FirstUseEver)
	if imgui.Begin("Shader editor", &editor.show_shader) {
		node := editor.editing
		if node == nil || node.doomed {
			imgui.TextWrapped("Select a Custom shader node's \"Edit code\" button to edit it here.")
		} else {
			imgui.TextWrapped(
				"Write float4 effect(float2 uv, float4 p). p holds the node's p.x to p.w inputs. sample_a(uv) and sample_b(uv) read the image inputs (black when unconnected), and texel_size() is one pixel in uv. Colours are linear.",
			)
			ctrl := imgui.IsKeyDown(.Key_LeftCtrl) || imgui.IsKeyDown(.Key_RightCtrl)
			if imgui.Button("Compile (Ctrl+Enter)") || (ctrl && imgui.IsKeyPressed(.Key_Enter, false) && imgui.IsWindowFocused({.ChildWindows})) {
				compile_custom(editor, node)
			}
			imgui.SameLine()
			if imgui.Button("Reset to example") {
				node.code = {}
				copy(node.code[:], DEFAULT_CODE)
				compile_custom(editor, node)
			}
			log_height := imgui.GetFrameHeight() * 5
			imgui.InputTextMultiline("##code", cstring(&node.code[0]), CODE_CAPACITY, {-1, -log_height}, {.AllowTabInput})
			colour := [4]f32{1, 0.45, 0.4, 1} if node.compile_failed else [4]f32{0.5, 0.9, 0.5, 1}
			if imgui.BeginChild("log", {0, 0}, {.Borders}) {
				imgui.PushStyleColorImVec4(.Text, colour)
				imgui.TextWrapped("%s", strings.clone_to_cstring(node.compile_log, context.temp_allocator))
				imgui.PopStyleColor()
			}
			imgui.EndChild()
		}
	}
	imgui.End()
}

node_body :: proc(editor: ^Editor, node: ^Node, in_graph: bool, left: f32) {
	for &input, index in node.inputs {
		row := imgui.GetCursorScreenPos()
		if input.kind == .Image {
			name := input.link != nil ? NODE_TITLES[input.link.kind] : cstring("nothing")
			imgui.Text("%s: %s", input.name, name)
		} else if input.link != nil {
			imgui.Text("%s: %.3f (linked)", input.name, input.shown)
		} else {
			imgui.SetNextItemWidth(NODE_WIDGET_WIDTH if in_graph else -110)
			imgui.SliderFloat(input.name, &input.value, input.minimum, input.maximum)
		}
		if in_graph {
			input.pin = {left, row.y + imgui.GetFrameHeight() * 0.5}
		}
		_ = index
	}
	switch node.kind {
	case .Image_File:
		if imgui.Button("Open...") {
			open_image(editor, node)
		}
		if node.path != "" {
			imgui.SameLine()
			imgui.TextUnformatted(strings.clone_to_cstring(filepath.base(node.path), context.temp_allocator))
		}
		if node.load_error != "" {
			imgui.TextColored({1, 0.45, 0.4, 1}, "%s", strings.clone_to_cstring(node.load_error, context.temp_allocator))
		}
	case .Value:
		imgui.SetNextItemWidth(NODE_WIDGET_WIDTH if in_graph else -110)
		imgui.DragFloat("value", &node.value, 0.01)
	case .Time:
		imgui.Text("%.2f s", node.value)
	case .Custom:
		if imgui.Button("Edit code") {
			editor.editing = node
			editor.show_shader = true
			imgui.SetWindowFocusStr("Shader editor")
		}
		imgui.SameLine()
		if node.compile_failed {
			imgui.TextColored({1, 0.45, 0.4, 1}, "%s", cstring("compile failed"))
		} else {
			imgui.TextDisabled("compiled")
		}
	case .Output:
		imgui.TextDisabled("Shown in the Viewer")
	case .Adjust, .Blur, .Sharpen, .Mix:
	}
	if in_graph && node.kind != .Output && node.kind != .Value && node.kind != .Time {
		width := f32(PREVIEW_WIDTH)
		height := width * 0.6
		if node.preview_shown.handle != 0 && node.valid {
			height = width * f32(node.preview_shown.extent.y) / f32(node.preview_shown.extent.x)
		}
		imgui.Image(valhalla_imgui.texture(node.preview_shown), {width, height})
	}
}

graph_window :: proc(editor: ^Editor) {
	imgui.SetNextWindowPos({20, 620}, .FirstUseEver)
	imgui.SetNextWindowSize({1000, 360}, .FirstUseEver)
	if !imgui.Begin("Shader graph", &editor.show_graph) {
		imgui.End()
		return
	}
	imgui.TextDisabled("Drag from a pin to link. Right-click the canvas to add nodes, a node to delete it, a linked input pin to unlink it. Drag with the middle or right button to pan.")
	if imgui.BeginChild("canvas", {0, 0}, {.Borders}, {.NoScrollbar, .NoMove, .NoScrollWithMouse}) {
		draw_canvas(editor)
	}
	imgui.EndChild()
	imgui.End()
}

draw_canvas :: proc(editor: ^Editor) {
	io := imgui.GetIO()
	draw_list := imgui.GetWindowDrawList()
	canvas_min := imgui.GetCursorScreenPos()
	canvas_size := imgui.GetContentRegionAvail()
	canvas_max := canvas_min + canvas_size
	origin := canvas_min + editor.scrolling
	canvas_hovered := imgui.IsWindowHovered()
	mouse := imgui.GetMousePos()

	grid :: 32
	grid_colour := colour_u32({1, 1, 1, 0.06})
	for x := f32(int(editor.scrolling.x) % grid); x < canvas_size.x; x += grid {
		imgui.DrawList_AddLine(draw_list, {canvas_min.x + x, canvas_min.y}, {canvas_min.x + x, canvas_max.y}, grid_colour)
	}
	for y := f32(int(editor.scrolling.y) % grid); y < canvas_size.y; y += grid {
		imgui.DrawList_AddLine(draw_list, {canvas_min.x, canvas_min.y + y}, {canvas_max.x, canvas_min.y + y}, grid_colour)
	}

	imgui.DrawList_ChannelsSplit(draw_list, 3)
	hovered_node: ^Node
	for node in editor.nodes {
		if node.doomed {
			continue
		}
		draw_node(editor, node, origin, draw_list)
		rect_min := origin + node.position
		if mouse.x >= rect_min.x && mouse.y >= rect_min.y && mouse.x <= rect_min.x + node.size.x && mouse.y <= rect_min.y + node.size.y {
			hovered_node = node
		}
	}

	imgui.DrawList_ChannelsSetCurrent(draw_list, 0)
	for node in editor.nodes {
		if node.doomed {
			continue
		}
		for input in node.inputs {
			if input.link != nil && !input.link.doomed {
				draw_link(draw_list, input.link.output_pin, input.pin, PIN_COLOURS[input.kind])
			}
		}
	}

	drag := &editor.drag
	if drag.active {
		if drag.source != nil {
			draw_link(draw_list, drag.source.output_pin, mouse, PIN_COLOURS[NODE_OUTPUTS[drag.source.kind].?])
		} else if drag.target != nil {
			draw_link(draw_list, mouse, drag.target.inputs[drag.target_input].pin, PIN_COLOURS[drag.target.inputs[drag.target_input].kind])
		}
		if !imgui.IsMouseDown(.Left) {
			finish_drag(editor, mouse)
		}
	}
	imgui.DrawList_ChannelsMerge(draw_list)

	if canvas_hovered && !imgui.IsAnyItemActive() {
		if imgui.IsMouseDragging(.Middle, 0) || imgui.IsMouseDragging(.Right, 4) {
			editor.scrolling += io.MouseDelta
		}
	}
	if canvas_hovered && imgui.IsMouseReleased(.Right) && linalg.length(imgui.GetMouseDragDelta(.Right, 0)) < 4 {
		if hovered_node != nil {
			editor.menu_node = hovered_node
			imgui.OpenPopup("node menu")
		} else {
			editor.add_position = mouse - origin
			imgui.OpenPopup("add menu")
		}
	}
	if imgui.BeginPopup("add menu") {
		imgui.TextDisabled("Add node")
		imgui.Separator()
		add_node_items(editor, editor.add_position)
		imgui.EndPopup()
	}
	if imgui.BeginPopup("node menu") {
		node := editor.menu_node
		if node != nil {
			imgui.TextDisabled("%s", NODE_TITLES[node.kind])
			imgui.Separator()
			if node.kind == .Custom && imgui.MenuItem("Edit code") {
				editor.editing = node
				editor.show_shader = true
			}
			if imgui.MenuItem("Disconnect inputs") {
				for &input in node.inputs {
					input.link = nil
				}
			}
			if imgui.MenuItem("Delete", "Del") {
				node.doomed = true
			}
		}
		imgui.EndPopup()
	}
	if editor.selected != nil && imgui.IsWindowFocused() && !io.WantTextInput && imgui.IsKeyPressed(.Key_Delete, false) {
		editor.selected.doomed = true
	}
}

draw_link :: proc(draw_list: ^imgui.DrawList, from, to: [2]f32, colour: [4]f32) {
	reach := max(abs(to.x - from.x) * 0.5, 40)
	imgui.DrawList_AddBezierCubic(draw_list, from, from + {reach, 0}, to - {reach, 0}, to, colour_u32(colour), 3)
}

draw_node :: proc(editor: ^Editor, node: ^Node, origin: [2]f32, draw_list: ^imgui.DrawList) {
	io := imgui.GetIO()
	imgui.PushIDInt(node.id)
	defer imgui.PopID()

	rect_min := origin + node.position
	imgui.DrawList_ChannelsSetCurrent(draw_list, 2)
	imgui.SetCursorScreenPos(rect_min + NODE_PADDING)
	imgui.BeginGroup()
	imgui.TextUnformatted(NODE_TITLES[node.kind])
	imgui.Spacing()
	node_body(editor, node, true, rect_min.x)
	imgui.EndGroup()
	content := imgui.GetItemRectSize()
	node.size = {max(content.x, NODE_WIDGET_WIDTH + 60), content.y} + NODE_PADDING * 2
	rect_max := rect_min + node.size
	title_height := imgui.GetFrameHeight() + NODE_PADDING.y
	if output, has_output := NODE_OUTPUTS[node.kind].?; has_output {
		node.output_pin = {rect_max.x, rect_min.y + title_height * 0.5}
		imgui.SetCursorScreenPos(node.output_pin - PIN_RADIUS * 2)
		imgui.InvisibleButton("output", {PIN_RADIUS * 4, PIN_RADIUS * 4})
		if imgui.IsItemActivated() {
			editor.drag = {active = true, source = node}
		}
		draw_pin(draw_list, node.output_pin, PIN_COLOURS[output], true)
	}
	for &input, index in node.inputs {
		imgui.PushIDInt(i32(index))
		imgui.SetCursorScreenPos(input.pin - PIN_RADIUS * 2)
		imgui.InvisibleButton("input", {PIN_RADIUS * 4, PIN_RADIUS * 4})
		if imgui.IsItemActivated() {
			if input.link != nil {
				editor.drag = {active = true, source = input.link}
				input.link = nil
			} else {
				editor.drag = {active = true, target = node, target_input = index}
			}
		}
		if imgui.IsItemHovered() && imgui.IsMouseClicked(.Right) {
			input.link = nil
		}
		draw_pin(draw_list, input.pin, PIN_COLOURS[input.kind], input.link != nil)
		imgui.PopID()
	}

	imgui.DrawList_ChannelsSetCurrent(draw_list, 1)
	imgui.SetCursorScreenPos(rect_min)
	imgui.InvisibleButton("node", node.size)
	if imgui.IsItemActivated() {
		editor.selected = node
	}
	if imgui.IsItemActive() && imgui.IsMouseDragging(.Left) {
		node.position += io.MouseDelta
	}
	selected := editor.selected == node
	imgui.DrawList_AddRectFilled(draw_list, rect_min, rect_max, colour_u32({0.13, 0.14, 0.17, 0.97}), 6)
	imgui.DrawList_AddRectFilled(draw_list, rect_min, {rect_max.x, rect_min.y + title_height}, colour_u32({0.22, 0.27, 0.36, 1}), 6, {.RoundCornersTopLeft, .RoundCornersTopRight})
	border := [4]f32{1, 0.8, 0.3, 1} if selected else [4]f32{0.35, 0.37, 0.42, 1}
	imgui.DrawList_AddRect(draw_list, rect_min, rect_max, colour_u32(border), 6, {}, 2 if selected else 1)
}

draw_pin :: proc(draw_list: ^imgui.DrawList, position: [2]f32, colour: [4]f32, filled: bool) {
	if filled {
		imgui.DrawList_AddCircleFilled(draw_list, position, PIN_RADIUS, colour_u32(colour))
	} else {
		imgui.DrawList_AddCircleFilled(draw_list, position, PIN_RADIUS, colour_u32({0.1, 0.1, 0.12, 1}))
		imgui.DrawList_AddCircle(draw_list, position, PIN_RADIUS, colour_u32(colour), 0, 2)
	}
}

finish_drag :: proc(editor: ^Editor, mouse: [2]f32) {
	drag := editor.drag
	editor.drag = {}
	reach :: PIN_RADIUS * 3
	if drag.source != nil {
		kind := NODE_OUTPUTS[drag.source.kind].?
		for node in editor.nodes {
			if node.doomed || node == drag.source {
				continue
			}
			for input, index in node.inputs {
				if input.kind == kind && linalg.length(input.pin - mouse) <= reach {
					connect(editor, drag.source, node, index)
					return
				}
			}
		}
	} else if drag.target != nil {
		kind := drag.target.inputs[drag.target_input].kind
		for node in editor.nodes {
			output, has_output := NODE_OUTPUTS[node.kind].?
			if node.doomed || node == drag.target || !has_output || output != kind {
				continue
			}
			if linalg.length(node.output_pin - mouse) <= reach {
				connect(editor, node, drag.target, drag.target_input)
				return
			}
		}
	}
}

// ===[ Main ]==================================================================

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "Image editor", size = {1600, 1000}) or_return
	defer Valhalla.delete_window(&window)
	surface := Valhalla.make_surface(window) or_return
	defer Valhalla.delete_surface(&surface)

	editor := new(Editor)
	defer free(editor)
	editor.window = window
	editor.surface = &surface
	editor.target = Valhalla.make_image(surface.format, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, {.Attachment}, name = "target") or_return
	defer Valhalla.delete_image(&editor.target)
	editor.fit = true
	editor.zoom = 1
	editor.show_viewer = true
	editor.show_graph = true
	editor.show_adjustments = true

	cache, cache_err := Valhalla.make_pipeline_cache(PIPELINE_CACHE_FILE)
	if cache_err != nil {
		cache = Valhalla.make_pipeline_cache() or_return
	}
	editor.pipeline_cache = cache
	defer Valhalla.delete_pipeline_cache(&editor.pipeline_cache)
	defer if save_err := Valhalla.write_pipeline_cache_to_file(editor.pipeline_cache, PIPELINE_CACHE_FILE); save_err != nil {
		log.errorf("Could not save the pipeline cache: %v", save_err)
	}

	nodes_code := #load("Nodes.slang")
	editor.adjust = Valhalla.make_shader(nodes_code, []string{"fullscreen", "adjust"}, pipeline_cache = editor.pipeline_cache, push_type = Node_Push, colour_formats = {0 = .R16G16B16A16_SFLOAT}) or_return
	defer Valhalla.delete_shader(&editor.adjust)
	editor.blur = Valhalla.make_shader(nodes_code, []string{"fullscreen", "blur"}, pipeline_cache = editor.pipeline_cache, push_type = Node_Push, colour_formats = {0 = .R16G16B16A16_SFLOAT}) or_return
	defer Valhalla.delete_shader(&editor.blur)
	editor.sharpen = Valhalla.make_shader(nodes_code, []string{"fullscreen", "sharpen"}, pipeline_cache = editor.pipeline_cache, push_type = Node_Push, colour_formats = {0 = .R16G16B16A16_SFLOAT}) or_return
	defer Valhalla.delete_shader(&editor.sharpen)
	editor.mix = Valhalla.make_shader(nodes_code, []string{"fullscreen", "mix"}, pipeline_cache = editor.pipeline_cache, push_type = Node_Push, colour_formats = {0 = .R16G16B16A16_SFLOAT}) or_return
	defer Valhalla.delete_shader(&editor.mix)
	editor.encode = Valhalla.make_shader(nodes_code, []string{"fullscreen", "encode"}, pipeline_cache = editor.pipeline_cache, push_type = Node_Push, colour_formats = {0 = .R8G8B8A8_UNORM}) or_return
	defer Valhalla.delete_shader(&editor.present)
	editor.present = Valhalla.make_shader(nodes_code, []string{"fullscreen", "copy"}, pipeline_cache = editor.pipeline_cache, push_type = Node_Push, colour_formats = {0 = .R8G8B8A8_SRGB}) or_return
	defer Valhalla.delete_shader(&editor.encode)
	editor.sampler = Valhalla.make_sampler(address_mode = .CLAMP_TO_EDGE) or_return
	defer Valhalla.delete_sampler(&editor.sampler)
	editor.black = Valhalla.make_image(.R8G8B8A8_UNORM, {1, 1, 1}) or_return
	defer Valhalla.delete_image(&editor.black)
	Valhalla.load_memory_to_image([]u8{0, 0, 0, 255}, &editor.black) or_return
	editor.display_shown = editor.black
	defer Valhalla.delete_image(&editor.display)
	defer delete(editor.save_path)
	defer delete(editor.open_path)
	defer delete(editor.param_values)
	defer Valhalla.delete_buffer(&editor.params)

	default_graph(editor)
	defer {
		for node in editor.nodes {
			free_node(node)
		}
		delete(editor.nodes)
	}

	valhalla_imgui.init(window, surface.format) or_return
	defer valhalla_imgui.shutdown()

	for &frame in editor.frames {
		frame = Valhalla.make_workload("frame") or_return
	}
	defer for &frame in editor.frames {
		Valhalla.delete_workload(&frame)
	}
	defer _ = Valhalla.wait_execution(editor.last)

	for !Valhalla.should_close(window) {
		Valhalla.poll_events()
		draw_frame(editor) or_return
		if editor.surface.minimised {
			Valhalla.wait_events()
		}
	}
	return nil
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	editor := (^Editor)(user_data)

	valhalla_imgui.begin_frame()
	build_ui(editor)

	load_opened_image(editor) or_return
	order := ordered_nodes(editor)
	if signature := graph_signature(editor); !editor.graph_recorded || signature != editor.graph_signature {
		record_graph(editor, order) or_return
		editor.graph_signature = signature
		editor.graph_recorded = true
	}
	update_params(editor, order) or_return
	if editor.save_path != "" && editor.display_valid {
		save_output(editor) or_return
	}

	frame := &editor.frames[editor.next_frame]
	editor.next_frame = (editor.next_frame + 1) % len(editor.frames)
	Valhalla.reset_workload(frame) or_return
	size := [3]u32{max(editor.surface.extent.x, 1), max(editor.surface.extent.y, 1), 1}
	if editor.target.extent != size {
		Valhalla.wait_execution(editor.last) or_return
		_ = Valhalla.resize_image(&editor.target, size) or_return
	}
	image := editor.target

	background := [4]f32{0.07, 0.07, 0.09, 1}
	if editor.surface.encodes_srgb {
		background = Valhalla.srgb_to_linear(background)
	}
	cleared := Valhalla.clear_image(frame, image, background)
	drawn := valhalla_imgui.end_frame(frame, cleared) or_return
	Valhalla.present(frame, drawn, editor.surface)
	Valhalla.finalize_workload(frame) or_return
	_ = execute_after_graph(editor, frame) or_return
	return delete_doomed_nodes(editor)
}

execute_after_graph :: proc(editor: ^Editor, workload: ^Valhalla.Workload) -> (execution: Valhalla.Execution, err: Valhalla.Error) {
	order := ordered_nodes(editor)
	chain := make([dynamic]^Valhalla.Workload, 0, len(order) + 1, context.temp_allocator)
	for node in order {
		for input in node.inputs {
			if input.link != nil && input.link.stale {
				node.stale = true
			}
		}
		if node.stale && node.recorded {
			append(&chain, &node.workload)
		}
	}
	append(&chain, workload)
	execution = Valhalla.execute_workloads(..chain[:]) or_return
	editor.last = execution
	if len(chain) > 1 {
		editor.graph_last = execution
	}
	for node in order {
		node.stale = false
	}
	return
}

save_output :: proc(editor: ^Editor) -> Valhalla.Error {
	defer {
		delete(editor.save_path)
		editor.save_path = ""
	}
	save := Valhalla.make_workload("save") or_return
	defer Valhalla.delete_workload(&save)
	shot := Valhalla.readback(&save, editor.display_shown) or_return
	Valhalla.finalize_workload(&save) or_return
	execution := execute_after_graph(editor, &save) or_return
	Valhalla.wait_execution(execution) or_return
	if err := Valhalla.write_readback_to_file(shot, editor.save_path); err != nil {
		editor.status = "Saving failed"
	} else {
		editor.status = "Saved"
	}
	return nil
}
