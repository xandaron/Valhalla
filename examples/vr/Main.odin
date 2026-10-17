package Vr

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:time"
import vk "vendor:vulkan"

import Valhalla "../../src"

EYE_COUNT :: 2

EYE_FORMAT :: vk.Format.R16G16B16A16_SFLOAT

VERTICAL_FOV :: math.PI * 0.45

NEAR :: 0.05

FAR :: 200

IPD_DEFAULT :: 0.064

IPD_STEP :: 0.008

IPD_MAX :: 0.4

MOVE_SPEED :: 3

LOOK_SPEED :: 0.004

SKY :: [4]f32{0.42, 0.56, 0.78, 1}

Vertex :: struct {
	position: [4]f32,
	normal:   [4]f32,
}

Object :: struct {
	model:    matrix[4, 4]f32,
	colour:   [4]f32,
	material: [4]f32,
}

Eye :: struct {
	view_projection: matrix[4, 4]f32,
	position:        [4]f32,
}

View :: struct {
	sun:      [4]f32,
	settings: [4]f32,
}

Push :: struct {
	vertices:   Valhalla.Buffer,
	objects:    Valhalla.Buffer,
	eyes:       Valhalla.Buffer,
	view:       Valhalla.Buffer,
	eye_images: Valhalla.Image,
	sampler:    Valhalla.Sampler,
}

Mesh :: struct {
	first_index: int,
	index_count: int,
	base_vertex: int,
}

Spinner :: struct {
	object:   int,
	position: [3]f32,
	scale:    f32,
	speed:    f32,
	bob:      f32,
}

Head :: struct {
	position:   [3]f32,
	yaw, pitch: f32,
	ipd:        f32,
	lens:       bool,
	swap:       bool,
	forward:    bool,
	back:       bool,
	left:       bool,
	right:      bool,
	up:         bool,
	down:       bool,
	looking:    bool,
	last_mouse: [2]f64,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("VR failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(
		title = "VR: WASD to move, drag to look, [ ] eye separation, L lens preview, X swap eyes",
		size = {1600, 800},
	) or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(window) or_return
	defer Valhalla.delete_surface(&surface)

	vertices: [dynamic]Vertex
	defer delete(vertices)
	indices: [dynamic]u32
	defer delete(indices)
	plane := add_plane(&vertices, &indices)
	cube := add_cube(&vertices, &indices)
	sphere := add_sphere(&vertices, &indices, rings = 24, segments = 48)

	objects: [dynamic]Object
	defer delete(objects)
	meshes: [dynamic]Mesh
	defer delete(meshes)
	spinners: [dynamic]Spinner
	defer delete(spinners)
	add_object :: proc(objects: ^[dynamic]Object, meshes: ^[dynamic]Mesh, mesh: Mesh, model: matrix[4, 4]f32, colour: [3]f32, shininess, specular: f32, checker := false) -> int {
		append(objects, Object{model = model, colour = {colour.r, colour.g, colour.b, 1}, material = {shininess, specular, 1 if checker else 0, 0}})
		append(meshes, mesh)
		return len(objects) - 1
	}
	translate :: linalg.matrix4_translate_f32
	rotate :: linalg.matrix4_rotate_f32
	scale :: linalg.matrix4_scale_f32
	add_object(&objects, &meshes, plane, scale({60, 1, 60}), {0.7, 0.7, 0.72}, 8, 0.05, checker = true)
	for index in 0 ..< 12 {
		angle := f32(index) / 12 * 2 * math.PI
		hue := f32(index) / 12
		colour := [3]f32{0.5 + 0.45 * math.cos(hue * 6.283), 0.5 + 0.45 * math.cos(hue * 6.283 - 2.094), 0.5 + 0.45 * math.cos(hue * 6.283 + 2.094)}
		position := [3]f32{math.sin(angle) * 9, 1.5, -math.cos(angle) * 9}
		add_object(&objects, &meshes, cube, translate(position) * rotate(-angle, {0, 1, 0}) * scale({0.35, 1.5, 0.35}), colour, 24, 0.25)
	}
	spinner_defs := [?]struct {
		mesh:     Mesh,
		position: [3]f32,
		scale:    f32,
		colour:   [3]f32,
		speed:    f32,
	} {
		{cube, {0, 1.4, 1.6}, 0.25, {0.95, 0.15, 0.08}, 0.9},
		{sphere, {-0.9, 1.7, 0.6}, 0.22, {0.1, 0.55, 0.95}, 1.3},
		{cube, {1.1, 1.2, 0.2}, 0.3, {0.98, 0.7, 0.05}, -0.7},
		{sphere, {-2.2, 1.1, -1.5}, 0.5, {0.85, 0.85, 0.85}, 0.5},
		{cube, {2.6, 2.0, -3.0}, 0.6, {0.2, 0.8, 0.3}, 0.4},
		{sphere, {0.3, 2.6, -5.5}, 0.9, {0.75, 0.2, 0.85}, 0.3},
	}
	for def, index in spinner_defs {
		object := add_object(&objects, &meshes, def.mesh, translate(def.position) * scale(def.scale), def.colour, 64, 0.6)
		append(&spinners, Spinner{object = object, position = def.position, scale = def.scale, speed = def.speed, bob = f32(index)})
	}

	vertex_buffer := Valhalla.make_buffer_from_memory(raw_bytes(vertices[:]), {.Storage}) or_return
	defer Valhalla.delete_buffer(&vertex_buffer)
	index_buffer := Valhalla.make_buffer_from_memory(raw_bytes(indices[:]), {.Index}) or_return
	defer Valhalla.delete_buffer(&index_buffer)
	object_buffer := Valhalla.make_buffer(len(objects) * size_of(Object), {.Storage}, .Host_Visible) or_return
	defer Valhalla.delete_buffer(&object_buffer)
	eye_buffer := Valhalla.make_buffer(EYE_COUNT * size_of(Eye), {.Storage}, .Host_Visible) or_return
	defer Valhalla.delete_buffer(&eye_buffer)
	view_buffer := Valhalla.make_buffer(size_of(View), {.Storage}, .Host_Visible) or_return
	defer Valhalla.delete_buffer(&view_buffer)
	sampler := Valhalla.make_sampler(address_mode = .CLAMP_TO_EDGE) or_return
	defer Valhalla.delete_sampler(&sampler)

	stereo := Valhalla.make_shader(
		#load("Vr.slang"),
		[]string{"scene_vertex", "scene_fragment"},
		push_type = Push, colour_formats = {0 = EYE_FORMAT}, depth_format = .D32_SFLOAT, view_mask = 0b11,
	) or_return
	defer Valhalla.delete_shader(&stereo)
	composite := Valhalla.make_shader(
		#load("Vr.slang"),
		[]string{"composite_vertex", "composite_fragment"},
		push_type = Push, colour_formats = {0 = surface.format},
	) or_return
	defer Valhalla.delete_shader(&composite)

	scene := Scene {
		surface       = &surface,
		head          = {position = {0, 1.6, 4}, ipd = IPD_DEFAULT},
		objects       = objects[:],
		meshes        = meshes[:],
		spinners      = spinners[:],
		vertex_buffer = vertex_buffer,
		index_buffer  = index_buffer,
		object_buffer = &object_buffer,
		eye_buffer    = &eye_buffer,
		view_buffer   = &view_buffer,
		sampler       = sampler,
		stereo        = &stereo,
		composite     = &composite,
		sun           = linalg.normalize([3]f32{-0.5, -0.8, -0.35}),
		start         = time.now(),
		previous      = time.now(),
	}
	eye_size := eye_extent(surface.extent)
	scene.eyes = Valhalla.make_image(EYE_FORMAT, eye_size, usage = {.Attachment}, shape = .D2_Array, layers = EYE_COUNT, name = "eyes") or_return
	defer Valhalla.delete_image(&scene.eyes)
	scene.eye_depth = Valhalla.make_image(.D32_SFLOAT, eye_size, usage = {.Attachment}, shape = .D2_Array, layers = EYE_COUNT, name = "eye depth") or_return
	defer Valhalla.delete_image(&scene.eye_depth)
	scene.target = Valhalla.make_image(surface.format, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, {.Attachment}, name = "target") or_return
	defer Valhalla.delete_image(&scene.target)
	scene.frame = Valhalla.make_workload("frame") or_return
	defer Valhalla.delete_workload(&scene.frame)
	defer _ = Valhalla.wait_execution(scene.last)

	Valhalla.set_window_user_pointer(window, rawptr(&scene.head))
	Valhalla.set_mouse_button_callback(window, on_mouse_button)
	Valhalla.set_cursor_position_callback(window, on_cursor_pos)
	Valhalla.set_key_callback(window, on_key)
	for !Valhalla.should_close(window) {
		Valhalla.poll_events()
		draw_frame(&scene) or_return
		if scene.surface.minimised {
			Valhalla.wait_events()
		}
	}
	return nil
}

Scene :: struct {
	surface:       ^Valhalla.Surface,
	head:          Head,
	objects:       []Object,
	meshes:        []Mesh,
	spinners:      []Spinner,
	vertex_buffer: Valhalla.Buffer,
	index_buffer:  Valhalla.Buffer,
	object_buffer: ^Valhalla.Buffer,
	eye_buffer:    ^Valhalla.Buffer,
	view_buffer:   ^Valhalla.Buffer,
	sampler:       Valhalla.Sampler,
	stereo:        ^Valhalla.Shader,
	composite:     ^Valhalla.Shader,
	eyes:          Valhalla.Image,
	eye_depth:     Valhalla.Image,
	frame:         Valhalla.Workload,
	recorded:      bool,
	last:          Valhalla.Execution,
	sun:           [3]f32,
	start:         time.Time,
	previous:      time.Time,
	target:     Valhalla.Image,
}

eye_extent :: proc(extent: [2]u32) -> [3]u32 {
	return {max(extent.x / EYE_COUNT, 1), max(extent.y, 1), 1}
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	scene := (^Scene)(user_data)
	if scene.target.extent.xy != scene.surface.extent {
		scene.recorded = false
	}
	if !scene.recorded {
		record_frame(scene) or_return
	}

	now := time.now()
	delta := f32(time.duration_seconds(time.diff(scene.previous, now)))
	scene.previous = now
	seconds := f32(time.duration_seconds(time.diff(scene.start, now)))
	head := &scene.head
	move_head(head, min(delta, 0.1))

	Valhalla.wait_execution(scene.last) or_return
	for spinner in scene.spinners {
		position := spinner.position + {0, 0.15 * math.sin(seconds * 1.1 + spinner.bob), 0}
		spin := linalg.matrix4_rotate_f32(seconds * spinner.speed, linalg.normalize([3]f32{0.3, 1, 0.2}))
		scene.objects[spinner.object].model = linalg.matrix4_translate_f32(position) * spin * linalg.matrix4_scale_f32(spinner.scale)
	}

	forward := head_forward(head^)
	right := linalg.normalize(linalg.cross(forward, [3]f32{0, 1, 0}))
	extent := scene.eyes.extent
	eye_projection := projection(1 / math.tan(f32(VERTICAL_FOV) / 2), f32(extent.x) / f32(extent.y), NEAR, FAR)
	view := View {
		sun      = {scene.sun.x, scene.sun.y, scene.sun.z, 2.2},
		settings = {1 if head.lens else 0, 1 if head.swap else 0, 0, 0},
	}
	eyes: [EYE_COUNT]Eye
	for &eye, index in eyes {
		side: f32 = -0.5 if index == 0 else 0.5
		position := head.position + right * head.ipd * side
		eye = {
			view_projection = eye_projection * linalg.matrix4_look_at_f32(position, position + forward, {0, 1, 0}),
			position        = {position.x, position.y, position.z, 1},
		}
	}
	Valhalla.load_memory_to_buffer(raw_bytes(scene.objects), scene.object_buffer^) or_return
	Valhalla.load_memory_to_buffer(raw_bytes(eyes[:]), scene.eye_buffer^) or_return
	Valhalla.load_memory_to_buffer(mem.ptr_to_bytes(&view), scene.view_buffer^) or_return

	scene.last = Valhalla.execute_workloads(&scene.frame) or_return
	return nil
}

record_frame :: proc(scene: ^Scene) -> Valhalla.Error {
	stereo, composite := scene.stereo, scene.composite
	frame := &scene.frame
	Valhalla.reset_workload(frame) or_return

	_ = Valhalla.resize_image(&scene.target, {max(scene.surface.extent.x, 1), max(scene.surface.extent.y, 1), 1}) or_return
	image := scene.target
	eye_size := eye_extent(image.extent.xy)
	_ = Valhalla.resize_image(&scene.eyes, eye_size) or_return
	_ = Valhalla.resize_image(&scene.eye_depth, eye_size) or_return

	push := Push {
		vertices = scene.vertex_buffer,
		objects  = scene.object_buffer^,
		eyes     = scene.eye_buffer^,
		view     = scene.view_buffer^,
		sampler  = scene.sampler,
	}

	eyes_cleared := Valhalla.clear_image(frame, scene.eyes, SKY)
	depth_cleared := Valhalla.clear_depth(frame, scene.eye_depth)
	Valhalla.reset_shader(stereo)
	Valhalla.bind_shader_index_buffer(stereo, scene.index_buffer)
	eyes := Valhalla.bind_shader_colour(stereo, eyes_cleared)
	depth := Valhalla.bind_shader_depth(stereo, depth_cleared)
	Valhalla.set_depth_test(stereo, true)
	Valhalla.set_depth_write(stereo, true)
	Valhalla.set_push_data(stereo, push)
	for mesh, index in scene.meshes {
		Valhalla.draw_indexed(stereo, mesh.index_count, first_index = mesh.first_index, vertex_offset = mesh.base_vertex, draw_data = u32(index))
	}
	Valhalla.bind_shader(frame, stereo^) or_return
	Valhalla.workload_discards(frame, depth)

	cleared := Valhalla.clear_image(frame, image, {0, 0, 0, 1})
	Valhalla.reset_shader(composite)
	drawn := Valhalla.bind_shader_colour(composite, cleared)
	push.eye_images = eyes
	Valhalla.set_push_data(composite, push)
	Valhalla.draw(composite, 3)
	Valhalla.bind_shader(frame, composite^) or_return

	Valhalla.present(frame, drawn, scene.surface)
	Valhalla.finalize_workload(frame) or_return
	scene.recorded = true
	return nil
}

head_forward :: proc(head: Head) -> [3]f32 {
	return {math.sin(head.yaw) * math.cos(head.pitch), math.sin(head.pitch), -math.cos(head.yaw) * math.cos(head.pitch)}
}

move_head :: proc(head: ^Head, delta: f32) {
	forward := [3]f32{math.sin(head.yaw), 0, -math.cos(head.yaw)}
	right := [3]f32{math.cos(head.yaw), 0, math.sin(head.yaw)}
	motion: [3]f32
	if head.forward {
		motion += forward
	}
	if head.back {
		motion -= forward
	}
	if head.right {
		motion += right
	}
	if head.left {
		motion -= right
	}
	if head.up {
		motion.y += 1
	}
	if head.down {
		motion.y -= 1
	}
	if motion != 0 {
		head.position += linalg.normalize(motion) * MOVE_SPEED * delta
		head.position.y = max(head.position.y, 0.2)
	}
}

on_mouse_button :: proc(window: Valhalla.Window, button: Valhalla.Mouse_Button, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	head := (^Head)(Valhalla.window_user_pointer(window))
	if button == .Left {
		head.looking = action == .Press
	}
}

on_cursor_pos :: proc(window: Valhalla.Window, position: [2]f64) {
	head := (^Head)(Valhalla.window_user_pointer(window))
	if head.looking {
		delta := position - head.last_mouse
		head.yaw += f32(delta.x) * LOOK_SPEED
		head.pitch = clamp(head.pitch - f32(delta.y) * LOOK_SPEED, -1.4, 1.4)
	}
	head.last_mouse = position
}

on_key :: proc(window: Valhalla.Window, key: Valhalla.Key, scancode: i32, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	head := (^Head)(Valhalla.window_user_pointer(window))
	held := action != .Release
	pressed := action == .Press
	#partial switch key {
	case .Escape:
		if pressed {
			Valhalla.request_close(window)
		}
	case .W:
		head.forward = held
	case .S:
		head.back = held
	case .A:
		head.left = held
	case .D:
		head.right = held
	case .Space:
		head.up = held
	case .Left_Shift:
		head.down = held
	case .L:
		if pressed {
			head.lens = !head.lens
		}
	case .X:
		if pressed {
			head.swap = !head.swap
		}
	case .Left_Bracket, .Right_Bracket:
		if held {
			step: f32 = IPD_STEP if key == .Right_Bracket else -IPD_STEP
			head.ipd = clamp(head.ipd + step, 0, IPD_MAX)
			log.infof("Eye separation %.0f mm", head.ipd * 1000)
		}
	}
}

add_plane :: proc(vertices: ^[dynamic]Vertex, indices: ^[dynamic]u32) -> Mesh {
	mesh := Mesh{first_index = len(indices), index_count = 6, base_vertex = len(vertices)}
	for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
		append(vertices, Vertex{position = {corner.x, 0, corner.y, 1}, normal = {0, 1, 0, 0}})
	}
	append(indices, 0, 1, 2, 0, 2, 3)
	return mesh
}

add_cube :: proc(vertices: ^[dynamic]Vertex, indices: ^[dynamic]u32) -> Mesh {
	mesh := Mesh{first_index = len(indices), index_count = 36, base_vertex = len(vertices)}
	faces := [6][3][3]f32 {
		{{1, 0, 0}, {0, 0, -1}, {0, 1, 0}},
		{{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
		{{0, 1, 0}, {1, 0, 0}, {0, 0, -1}},
		{{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
		{{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
		{{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}},
	}
	for face, index in faces {
		normal, across, up := face[0], face[1], face[2]
		for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
			position := normal + across * corner.x + up * corner.y
			append(vertices, Vertex{position = {position.x, position.y, position.z, 1}, normal = {normal.x, normal.y, normal.z, 0}})
		}
		first := u32(index * 4)
		append(indices, first, first + 1, first + 2, first, first + 2, first + 3)
	}
	return mesh
}

add_sphere :: proc(vertices: ^[dynamic]Vertex, indices: ^[dynamic]u32, rings, segments: int) -> Mesh {
	mesh := Mesh{first_index = len(indices), index_count = rings * segments * 6, base_vertex = len(vertices)}
	for ring in 0 ..= rings {
		theta := f32(ring) / f32(rings) * math.PI
		for segment in 0 ..= segments {
			phi := f32(segment) / f32(segments) * 2 * math.PI
			point := [3]f32{math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi)}
			append(vertices, Vertex{position = {point.x, point.y, point.z, 1}, normal = {point.x, point.y, point.z, 0}})
		}
	}
	for ring in 0 ..< rings {
		for segment in 0 ..< segments {
			a := u32(ring * (segments + 1) + segment)
			b := a + u32(segments + 1)
			append(indices, a, b, a + 1, a + 1, b, b + 1)
		}
	}
	return mesh
}

projection :: proc(focal, aspect, near, far: f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		focal / aspect, 0, 0, 0,
		0, -focal, 0, 0,
		0, 0, far / (near - far), near * far / (near - far),
		0, 0, -1, 0,
	}
}

raw_bytes :: proc(data: []$T) -> []u8 {
	return ([^]u8)(raw_data(data))[:len(data) * size_of(T)]
}
