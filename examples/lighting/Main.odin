package Lighting

import "core:log"
import "core:math"
import "core:mem"
import "core:math/linalg"
import "core:time"

import Valhalla "../../src"

SHADOW_MAP_SIZE :: 2048

POINT_SHADOW_SIZE :: 512

POINT_NEAR :: 0.05

POINT_FAR :: 8

LIGHT_COUNT :: 4

Vertex :: struct {
	position: [4]f32,
	normal:   [4]f32,
}

Object :: struct {
	model:    matrix[4, 4]f32,
	colour:   [4]f32,
	material: [4]f32,
}

Light :: struct {
	position: [4]f32,
	colour:   [4]f32,
}

View :: struct {
	view_projection: matrix[4, 4]f32,
	camera:          [4]f32,
}

Push :: struct {
	light_view_projection: matrix[4, 4]f32,
	sun:                   [4]f32,
	vertices:              Valhalla.Buffer,
	objects:               Valhalla.Buffer,
	lights:                Valhalla.Buffer,
	light_count:           u32,
	shadow_map:            Valhalla.Image,
	shadow_sampler:        Valhalla.Sampler,
	faces:                 Valhalla.Buffer,
	point_shadow_maps:     [LIGHT_COUNT]Valhalla.Image,
	shadow_light:          u32,
	view:                  Valhalla.Buffer,
}

Mesh :: struct {
	first_index: int,
	index_count: int,
	base_vertex: int,
}

Orbit :: struct {
	yaw, pitch, distance: f32,
}

Camera :: struct {
	orbit:      Orbit,
	dragging:   bool,
	last_mouse: [2]f64,
}

LIGHT_COLOURS := [LIGHT_COUNT][3]f32{{1, 0.12, 0.05}, {0.1, 1, 0.2}, {0.15, 0.3, 1}, {1, 0.6, 0.1}}

CUBE_FACES := [6][2][3]f32 {
	{{1, 0, 0}, {0, -1, 0}},
	{{-1, 0, 0}, {0, -1, 0}},
	{{0, 1, 0}, {0, 0, 1}},
	{{0, -1, 0}, {0, 0, -1}},
	{{0, 0, 1}, {0, -1, 0}},
	{{0, 0, -1}, {0, -1, 0}},
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Lighting failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "Lighting: drag to orbit, scroll to zoom") or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(&window, {}) or_return
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
	add_object :: proc(objects: ^[dynamic]Object, meshes: ^[dynamic]Mesh, mesh: Mesh, model: matrix[4, 4]f32, colour: [3]f32, shininess, specular: f32) {
		append(objects, Object{model = model, colour = {colour.r, colour.g, colour.b, 1}, material = {shininess, specular, 0, 0}})
		append(meshes, mesh)
	}
	translate :: linalg.matrix4_translate_f32
	rotate :: linalg.matrix4_rotate_f32
	scale :: linalg.matrix4_scale_f32
	add_object(&objects, &meshes, plane, scale({8, 1, 8}), {0.3, 0.3, 0.32}, 16, 0.15)
	add_object(&objects, &meshes, cube, translate({-2, 0.75, -1}) * rotate(0.6, {0, 1, 0}) * scale(0.75), {0.9, 0.06, 0.04}, 32, 0.3)
	add_object(&objects, &meshes, cube, translate({1.8, 0.5, 1.6}) * rotate(-0.3, {0, 1, 0}) * scale(0.5), {0.03, 0.25, 0.95}, 32, 0.3)
	add_object(&objects, &meshes, cube, translate({2.4, 1.25, -2.2}) * rotate(0.9, {0, 1, 0}) * scale({0.4, 1.25, 0.4}), {0.95, 0.45, 0.02}, 16, 0.2)
	add_object(&objects, &meshes, sphere, translate({0, 1, 0.4}) * scale(1), {0.85, 0.85, 0.85}, 96, 0.8)
	add_object(&objects, &meshes, sphere, translate({-1.2, 0.45, 2.1}) * scale(0.45), {0.95, 0.75, 0.02}, 64, 0.6)
	add_object(&objects, &meshes, sphere, translate({0.6, 0.35, 2.7}) * scale(0.35), {0.6, 0.05, 0.85}, 64, 0.6)
	scene_count := len(objects)
	for colour in LIGHT_COLOURS {
		append(&objects, Object{colour = {colour.r, colour.g, colour.b, 1}, material = {1, 0, 2, 0}})
		append(&meshes, sphere)
	}

	vertex_buffer := Valhalla.make_buffer(raw_bytes(vertices[:]), Valhalla.Buffer_Settings{usage = {.Storage}}) or_return
	defer Valhalla.delete_buffer(&vertex_buffer)
	index_buffer := Valhalla.make_buffer(raw_bytes(indices[:]), Valhalla.Buffer_Settings{usage = {.Index}}) or_return
	defer Valhalla.delete_buffer(&index_buffer)
	object_buffer := Valhalla.make_buffer(len(objects) * size_of(Object), Valhalla.Buffer_Settings{usage = {.Storage}, memory = .Host_Visible}) or_return
	defer Valhalla.delete_buffer(&object_buffer)
	light_buffer := Valhalla.make_buffer(LIGHT_COUNT * size_of(Light), Valhalla.Buffer_Settings{usage = {.Storage}, memory = .Host_Visible}) or_return
	defer Valhalla.delete_buffer(&light_buffer)

	shadow_map := Valhalla.make_image(.D32_SFLOAT, {SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 1}, kind = .Depth) or_return
	defer Valhalla.delete_image(&shadow_map)
	faces_buffer := Valhalla.make_buffer(LIGHT_COUNT * 6 * size_of(matrix[4, 4]f32), Valhalla.Buffer_Settings{usage = {.Storage}, memory = .Host_Visible}) or_return
	defer Valhalla.delete_buffer(&faces_buffer)
	view_buffer := Valhalla.make_buffer(size_of(View), Valhalla.Buffer_Settings{usage = {.Uniform}, memory = .Host_Visible}) or_return
	defer Valhalla.delete_buffer(&view_buffer)
	point_shadow_maps: [LIGHT_COUNT]Valhalla.Image
	for &point_shadow_map in point_shadow_maps {
		point_shadow_map = Valhalla.make_image(.D32_SFLOAT, {POINT_SHADOW_SIZE, POINT_SHADOW_SIZE, 1}, kind = .Depth, shape = .Cube) or_return
	}
	defer for &point_shadow_map in point_shadow_maps {
		Valhalla.delete_image(&point_shadow_map)
	}
	shadow_sampler := Valhalla.make_sampler(address_mode = .CLAMP_TO_BORDER, compare_op = .LESS_OR_EQUAL, border_colour = .FLOAT_OPAQUE_WHITE) or_return
	defer Valhalla.delete_sampler(&shadow_sampler)

	settings := Valhalla.Compiler_Settings {
		search_paths = {#directory + "/../../src/shaders"},
	}
	shadow, _ := Valhalla.make_shader(#load("Lighting.slang"), []string{"shadow_vertex"}, settings, {push_type = Push, depth_format = .D32_SFLOAT}) or_return
	defer Valhalla.delete_shader(&shadow)
	point_shadow, _ := Valhalla.make_shader(
		#load("Lighting.slang"),
		[]string{"point_shadow_vertex"},
		settings,
		{push_type = Push, depth_format = .D32_SFLOAT, view_mask = 0b111111},
	) or_return
	defer Valhalla.delete_shader(&point_shadow)
	lit, _ := Valhalla.make_shader(
		#load("Lighting.slang"),
		[]string{"lit_vertex", "lit_fragment"},
		settings,
		{push_type = Push, colour_formats = {0 = surface.format.format}, depth_format = .D32_SFLOAT},
	) or_return
	defer Valhalla.delete_shader(&lit)

	sun := linalg.normalize([3]f32{-0.7, -0.55, -0.45})
	scene := Scene {
		surface               = &surface,
		camera                = {orbit = {yaw = 0.6, pitch = 0.45, distance = 11}},
		objects               = objects[:],
		meshes                = meshes[:],
		scene_count           = scene_count,
		vertex_buffer         = vertex_buffer,
		index_buffer          = index_buffer,
		object_buffer         = &object_buffer,
		light_buffer          = &light_buffer,
		faces_buffer          = &faces_buffer,
		view_buffer           = &view_buffer,
		shadow_map            = shadow_map,
		point_shadow_maps     = point_shadow_maps,
		shadow_sampler        = shadow_sampler,
		shadow                = &shadow,
		point_shadow          = &point_shadow,
		lit                   = &lit,
		sun                   = sun,
		light_view_projection = orthographic(10, 0.5, 30) * linalg.matrix4_look_at_f32(-sun * 14, {0, 0, 0}, {0, 0, 1}),
		start                 = time.now(),
	}
	scene.depth = Valhalla.make_image(.D32_SFLOAT, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, kind = .Depth, name = "depth") or_return
	defer Valhalla.delete_image(&scene.depth)
	scene.frame = Valhalla.make_workload("frame") or_return
	defer Valhalla.delete_workload(&scene.frame)
	defer _ = Valhalla.wait_execution(scene.last)

	Valhalla.set_window_user_pointer(&window, rawptr(&scene.camera))
	Valhalla.set_mouse_button_callback(&window, on_mouse_button)
	Valhalla.set_cursor_position_callback(&window, on_cursor_pos)
	Valhalla.set_scroll_callback(&window, on_scroll)
	Valhalla.set_key_callback(&window, on_key)
	Valhalla.set_frame_callback(draw_frame, rawptr(&scene))
	defer Valhalla.set_frame_callback(nil)

	for !Valhalla.should_close(&window) {
		if scene.minimised {
			Valhalla.wait_events() or_return
		} else {
			Valhalla.poll_events() or_return
		}
		draw_frame(&scene) or_return
	}
	return nil
}

Scene :: struct {
	surface:               ^Valhalla.Surface,
	camera:                Camera,
	objects:               []Object,
	meshes:                []Mesh,
	scene_count:           int,
	vertex_buffer:         Valhalla.Buffer,
	index_buffer:          Valhalla.Buffer,
	object_buffer:         ^Valhalla.Buffer,
	light_buffer:          ^Valhalla.Buffer,
	faces_buffer:          ^Valhalla.Buffer,
	view_buffer:           ^Valhalla.Buffer,
	frame:                 Valhalla.Workload,
	recorded:              bool,
	last:                  Valhalla.Execution,
	shadow_map:            Valhalla.Image,
	point_shadow_maps:     [LIGHT_COUNT]Valhalla.Image,
	shadow_sampler:        Valhalla.Sampler,
	shadow:                ^Valhalla.Shader,
	point_shadow:          ^Valhalla.Shader,
	lit:                   ^Valhalla.Shader,
	depth:                 Valhalla.Image,
	sun:                   [3]f32,
	light_view_projection: matrix[4, 4]f32,
	start:                 time.Time,
	minimised:             bool,
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	scene := (^Scene)(user_data)
	if !scene.recorded {
		record_frame(scene) or_return
		if !scene.recorded {
			return nil
		}
	}

	Valhalla.wait_execution(scene.last) or_return
	seconds := f32(time.duration_seconds(time.since(scene.start)))
	lights: [LIGHT_COUNT]Light
	faces: [LIGHT_COUNT * 6]matrix[4, 4]f32
	for &light, index in lights {
		angle := seconds * (0.4 + 0.15 * f32(index)) + f32(index) * math.PI / 2
		position := [3]f32{math.cos(angle) * 3.5, 1.2 + 0.6 * math.sin(seconds * 0.7 + f32(index)), math.sin(angle) * 3.5}
		colour := LIGHT_COLOURS[index]
		light = {position = {position.x, position.y, position.z, 6}, colour = {colour.r, colour.g, colour.b, 4}}
		scene.objects[scene.scene_count + index].model = linalg.matrix4_translate_f32(position) * linalg.matrix4_scale_f32(0.12)
		for face, face_index in CUBE_FACES {
			view := linalg.matrix4_look_at_f32(position, position + face[0], face[1])
			faces[index * 6 + face_index] = projection(1, 1, POINT_NEAR, POINT_FAR, flip_y = false) * view
		}
	}
	orbit := scene.camera.orbit
	eye := orbit.distance * [3]f32{math.cos(orbit.pitch) * math.sin(orbit.yaw), math.sin(orbit.pitch), math.cos(orbit.pitch) * math.cos(orbit.yaw)}
	extent := scene.depth.extent
	view := View {
		view_projection = projection(1 / math.tan(f32(math.PI) / 8), f32(extent.x) / f32(extent.y), 0.1, 100) * linalg.matrix4_look_at_f32(eye, {0, 0.5, 0}, {0, 1, 0}),
		camera          = {eye.x, eye.y, eye.z, 1},
	}
	Valhalla.load_memory_to_buffer(raw_bytes(faces[:]), scene.faces_buffer) or_return
	Valhalla.load_memory_to_buffer(raw_bytes(scene.objects), scene.object_buffer) or_return
	Valhalla.load_memory_to_buffer(raw_bytes(lights[:]), scene.light_buffer) or_return
	Valhalla.load_memory_to_buffer(mem.ptr_to_bytes(&view), scene.view_buffer) or_return

	execution, err := Valhalla.execute_workloads(&scene.frame)
	if err == Valhalla.Workload_Error.Swapchain_Changed {
		scene.recorded = false
		return nil
	}
	scene.last = execution
	return err
}

record_frame :: proc(scene: ^Scene) -> Valhalla.Error {
	shadow, point_shadow, lit := scene.shadow, scene.point_shadow, scene.lit
	frame := &scene.frame
	Valhalla.reset_workload(frame) or_return

	image, acquire_err := Valhalla.acquire(frame, scene.surface)
	scene.minimised = acquire_err == Valhalla.Surface_Error.Surface_Minimised
	if scene.minimised {
		return nil
	} else if acquire_err != nil {
		return acquire_err
	}
	Valhalla.resize_image(&scene.depth, image.extent) or_return

	sun := scene.sun
	push := Push {
		light_view_projection = scene.light_view_projection,
		sun                   = {sun.x, sun.y, sun.z, 0.9},
		light_count           = LIGHT_COUNT,
		vertices              = scene.vertex_buffer,
		objects               = scene.object_buffer^,
	}

	shadow_cleared := Valhalla.clear_image(frame, scene.shadow_map, {depthStencil = {depth = 1}})
	Valhalla.reset_shader(shadow)
	Valhalla.bind_shader_index_buffer(shadow, scene.index_buffer)
	shadowed := Valhalla.bind_shader_depth(shadow, shadow_cleared)
	Valhalla.set_depth_test(shadow, true)
	Valhalla.set_depth_write(shadow, true)
	Valhalla.set_depth_bias(shadow, true, constant = 1.5, slope = 2)
	Valhalla.set_push_data(shadow, push)
	for mesh, index in scene.meshes[:scene.scene_count] {
		Valhalla.draw_indexed(shadow, mesh.base_vertex, mesh.first_index, mesh.index_count, 0, 1, draw_data = u32(index))
	}
	Valhalla.bind_shader(frame, shadow^) or_return

	Valhalla.reset_shader(point_shadow)
	Valhalla.set_depth_test(point_shadow, true)
	Valhalla.set_depth_write(point_shadow, true)
	Valhalla.set_depth_bias(point_shadow, true, constant = 1.5, slope = 2)
	for mesh, index in scene.meshes[:scene.scene_count] {
		Valhalla.draw_indexed(point_shadow, mesh.base_vertex, mesh.first_index, mesh.index_count, 0, 1, draw_data = u32(index))
	}
	point_shadows: [LIGHT_COUNT]Valhalla.Image
	for point_shadow_map, light in scene.point_shadow_maps {
		cube_cleared := Valhalla.clear_image(frame, point_shadow_map, {depthStencil = {depth = 1}})
		Valhalla.reset_shader_bindings(point_shadow)
		point_push := push
		point_push.faces = scene.faces_buffer^
		point_push.shadow_light = u32(light)
		Valhalla.bind_shader_index_buffer(point_shadow, scene.index_buffer)
		point_shadows[light] = Valhalla.bind_shader_depth(point_shadow, cube_cleared)
		Valhalla.set_push_data(point_shadow, point_push)
		Valhalla.bind_shader(frame, point_shadow^) or_return
	}

	cleared := Valhalla.clear_image(frame, image, {color = {float32 = {0.1, 0.12, 0.18, 1}}})
	depth_cleared := Valhalla.clear_image(frame, scene.depth, {depthStencil = {depth = 1}})
	Valhalla.reset_shader(lit)
	push.lights = scene.light_buffer^
	push.view = scene.view_buffer^
	push.shadow_map = shadowed
	push.shadow_sampler = scene.shadow_sampler
	push.point_shadow_maps = point_shadows
	Valhalla.bind_shader_index_buffer(lit, scene.index_buffer)
	drawn := Valhalla.bind_shader_colour(lit, cleared)
	Valhalla.bind_shader_depth(lit, depth_cleared)
	Valhalla.set_depth_test(lit, true)
	Valhalla.set_depth_write(lit, true)
	Valhalla.set_push_data(lit, push)
	for mesh, index in scene.meshes {
		Valhalla.draw_indexed(lit, mesh.base_vertex, mesh.first_index, mesh.index_count, 0, 1, draw_data = u32(index))
	}
	Valhalla.bind_shader(frame, lit^) or_return

	Valhalla.workload_discards(frame, scene.depth)
	Valhalla.present(frame, drawn)
	Valhalla.finalize_workload(frame) or_return
	scene.recorded = true
	return nil
}

on_mouse_button :: proc(window: ^Valhalla.Window, button: Valhalla.Mouse_Button, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	camera := (^Camera)(Valhalla.window_user_pointer(window))
	if button == .Left {
		camera.dragging = action == .Press
		camera.last_mouse = Valhalla.cursor_position(window)
	}
}

on_cursor_pos :: proc(window: ^Valhalla.Window, position: [2]f64) {
	camera := (^Camera)(Valhalla.window_user_pointer(window))
	if camera.dragging {
		delta := position - camera.last_mouse
		camera.orbit.yaw -= f32(delta.x) * 0.01
		camera.orbit.pitch = clamp(camera.orbit.pitch + f32(delta.y) * 0.01, 0.05, 1.5)
		camera.last_mouse = position
	}
}

on_scroll :: proc(window: ^Valhalla.Window, offset: [2]f64) {
	camera := (^Camera)(Valhalla.window_user_pointer(window))
	camera.orbit.distance = clamp(camera.orbit.distance - f32(offset.y) * 0.75, 4, 25)
}

on_key :: proc(window: ^Valhalla.Window, key: Valhalla.Key, scancode: i32, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	if key == .Escape && action == .Press {
		Valhalla.request_close(window)
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

projection :: proc(focal, aspect, near, far: f32, flip_y := true) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		focal / aspect, 0, 0, 0,
		0, -focal if flip_y else focal, 0, 0,
		0, 0, far / (near - far), near * far / (near - far),
		0, 0, -1, 0,
	}
}

orthographic :: proc(half_size, near, far: f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		1 / half_size, 0, 0, 0,
		0, 1 / half_size, 0, 0,
		0, 0, -1 / (far - near), -near / (far - near),
		0, 0, 0, 1,
	}
}

raw_bytes :: proc(data: []$T) -> []u8 {
	return ([^]u8)(raw_data(data))[:len(data) * size_of(T)]
}
