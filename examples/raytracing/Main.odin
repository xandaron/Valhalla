package Raytracing

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:time"

import Valhalla "../../src"

Vertex :: struct {
	position: [4]f32,
	normal:   [4]f32,
}

Object :: struct {
	model:       matrix[4, 4]f32,
	colour:      [4]f32,
	material:    [4]f32,
	base_vertex: u32,
	first_index: u32,
	checker:     u32,
	pad:         u32,
}

Frame :: struct {
	inverse_view_projection: matrix[4, 4]f32,
	camera:                  [4]f32,
	sun:                     [4]f32,
}

Push :: struct {
	scene:    Valhalla.Acceleration_Structure,
	vertices: Valhalla.Buffer,
	indices:  Valhalla.Buffer,
	objects:  Valhalla.Buffer,
	frame:    Valhalla.Buffer,
	output:   Valhalla.Image,
	encode:   u32,
}

Mesh :: struct {
	first_index: int,
	index_count: int,
	base_vertex: int,
	vertex_count: int,
}

Orbit :: struct {
	yaw, pitch, distance: f32,
}

Camera :: struct {
	orbit:      Orbit,
	dragging:   bool,
	last_mouse: [2]f64,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Ray tracing failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()
	if !Valhalla.device.optional.ray_query {
		log.error("This GPU does not support ray queries (VK_KHR_ray_query and VK_KHR_acceleration_structure)")
		return nil
	}

	window := Valhalla.make_window(title = "Ray tracing: drag to orbit, scroll to zoom", size = {1280, 720}) or_return
	defer Valhalla.delete_window(&window)
	surface := Valhalla.make_surface(&window, {}) or_return
	defer Valhalla.delete_surface(&surface)

	vertices: [dynamic]Vertex
	defer delete(vertices)
	indices: [dynamic]u32
	defer delete(indices)
	plane := add_plane(&vertices, &indices)
	cube := add_cube(&vertices, &indices)
	sphere := add_sphere(&vertices, &indices, rings = 48, segments = 96)

	geometry := Valhalla.Buffer_Settings{usage = {.Storage, .Acceleration_Input}}
	geometry.name = "vertices"
	vertex_buffer := Valhalla.make_buffer(raw_bytes(vertices[:]), geometry) or_return
	defer Valhalla.delete_buffer(&vertex_buffer)
	geometry.name = "indices"
	index_buffer := Valhalla.make_buffer(raw_bytes(indices[:]), geometry) or_return
	defer Valhalla.delete_buffer(&index_buffer)

	meshes := [?]Mesh{plane, cube, sphere}
	bottoms: [len(meshes)]Valhalla.Acceleration_Structure
	for mesh, index in meshes {
		bottoms[index] = Valhalla.make_bottom_level(
			{
				{
					vertices = vertex_buffer,
					vertex_offset = mesh.base_vertex * size_of(Vertex),
					vertex_stride = size_of(Vertex),
					vertex_count = mesh.vertex_count,
					indices = index_buffer,
					index_offset = mesh.first_index * size_of(u32),
					triangle_count = mesh.index_count / 3,
				},
			},
			name = "mesh",
		) or_return
	}
	defer for &bottom in bottoms {
		Valhalla.delete_acceleration_structure(&bottom)
	}

	objects: [dynamic]Object
	defer delete(objects)
	instances: [dynamic]Valhalla.Acceleration_Instance
	defer delete(instances)
	add_object :: proc(
		objects: ^[dynamic]Object,
		instances: ^[dynamic]Valhalla.Acceleration_Instance,
		bottoms: []Valhalla.Acceleration_Structure,
		meshes: []Mesh,
		mesh: int,
		model: matrix[4, 4]f32,
		colour: [3]f32,
		reflectivity: f32,
		tint: f32 = 0,
		checker := false,
	) {
		append(
			objects,
			Object {
				model = model,
				colour = {colour.r, colour.g, colour.b, 1},
				material = {reflectivity, tint, 0, 0},
				base_vertex = u32(meshes[mesh].base_vertex),
				first_index = u32(meshes[mesh].first_index),
				checker = 1 if checker else 0,
			},
		)
		append(instances, Valhalla.Acceleration_Instance{structure = bottoms[mesh], transform = model, custom_index = u32(len(objects) - 1)})
	}
	translate :: linalg.matrix4_translate_f32
	rotate :: linalg.matrix4_rotate_f32
	scale :: linalg.matrix4_scale_f32
	PLANE, CUBE, SPHERE :: 0, 1, 2
	add_object(&objects, &instances, bottoms[:], meshes[:], PLANE, scale({20, 1, 20}), {0.9, 0.9, 0.9}, 0.15, checker = true)
	add_object(&objects, &instances, bottoms[:], meshes[:], SPHERE, translate({0, 1.2, 0}) * scale(1.2), {0.95, 0.95, 0.95}, 0.9)
	add_object(&objects, &instances, bottoms[:], meshes[:], SPHERE, translate({-2.6, 0.7, 1.4}) * scale(0.7), {0.95, 0.65, 0.2}, 0.6, tint = 1)
	add_object(&objects, &instances, bottoms[:], meshes[:], SPHERE, translate({2.3, 0.5, 2.0}) * scale(0.5), {0.2, 0.5, 0.95}, 0)
	add_object(&objects, &instances, bottoms[:], meshes[:], CUBE, translate({2.4, 0.8, -1.6}) * rotate(0.5, {0, 1, 0}) * scale(0.8), {0.9, 0.15, 0.1}, 0)
	add_object(&objects, &instances, bottoms[:], meshes[:], CUBE, translate({-2.0, 1.0, -2.4}) * rotate(-0.3, {0, 1, 0}) * scale({0.5, 1.0, 0.5}), {0.15, 0.8, 0.3}, 0.3)
	add_object(&objects, &instances, bottoms[:], meshes[:], CUBE, translate({0.4, 0.3, 2.8}) * rotate(0.9, {0, 1, 0}) * scale(0.3), {0.8, 0.3, 0.9}, 0)

	scene := Valhalla.make_top_level(instances[:], name = "scene") or_return
	defer Valhalla.delete_acceleration_structure(&scene)
	object_buffer := Valhalla.make_buffer(raw_bytes(objects[:]), Valhalla.Buffer_Settings{usage = {.Storage}, name = "objects"}) or_return
	defer Valhalla.delete_buffer(&object_buffer)
	frame_buffer := Valhalla.make_buffer(size_of(Frame), Valhalla.Buffer_Settings{usage = {.Storage}, memory = .Host_Visible, name = "frame"}) or_return
	defer Valhalla.delete_buffer(&frame_buffer)

	settings := Valhalla.Compiler_Settings {
		search_paths = {#directory + "/../../src/shaders"},
	}
	raytrace, _ := Valhalla.make_shader(#load("Raytracing.slang"), []string{"raytrace"}, settings, {push_type = Push}) or_return
	defer Valhalla.delete_shader(&raytrace)

	state := State {
		surface      = &surface,
		camera       = {orbit = {yaw = 0.5, pitch = 0.35, distance = 9}},
		raytrace     = &raytrace,
		push         = {scene = scene, vertices = vertex_buffer, indices = index_buffer, objects = object_buffer, frame = frame_buffer, encode = 0 if surface.encodes_srgb else 1},
		frame_buffer = &frame_buffer,
		start        = time.now(),
	}
	state.image = Valhalla.make_image(.R16G16B16A16_SFLOAT, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, kind = .Generic, name = "traced") or_return
	defer Valhalla.delete_image(&state.image)
	state.frame = Valhalla.make_workload("frame") or_return
	defer Valhalla.delete_workload(&state.frame)
	defer _ = Valhalla.wait_execution(state.last)

	Valhalla.set_window_user_pointer(&window, rawptr(&state.camera))
	Valhalla.set_mouse_button_callback(&window, on_mouse_button)
	Valhalla.set_cursor_position_callback(&window, on_cursor_pos)
	Valhalla.set_scroll_callback(&window, on_scroll)
	Valhalla.set_key_callback(&window, on_key)
	Valhalla.set_frame_callback(draw_frame, rawptr(&state))
	defer Valhalla.set_frame_callback(nil)

	for !Valhalla.should_close(&window) {
		if state.minimised {
			Valhalla.wait_events() or_return
		} else {
			Valhalla.poll_events() or_return
		}
		draw_frame(&state) or_return
	}
	return nil
}

State :: struct {
	surface:      ^Valhalla.Surface,
	camera:       Camera,
	raytrace:     ^Valhalla.Shader,
	push:         Push,
	frame_buffer: ^Valhalla.Buffer,
	image:        Valhalla.Image,
	frame:        Valhalla.Workload,
	recorded:     bool,
	last:         Valhalla.Execution,
	start:        time.Time,
	minimised:    bool,
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	state := (^State)(user_data)
	if !state.recorded {
		record_frame(state) or_return
		if !state.recorded {
			return nil
		}
	}

	seconds := f32(time.duration_seconds(time.since(state.start)))
	orbit := state.camera.orbit
	eye := orbit.distance * [3]f32{math.cos(orbit.pitch) * math.sin(orbit.yaw), math.sin(orbit.pitch), math.cos(orbit.pitch) * math.cos(orbit.yaw)}
	extent := state.image.extent
	view_projection := projection(1 / math.tan(f32(math.PI) / 6), f32(extent.x) / f32(extent.y), 0.1, 100) * linalg.matrix4_look_at_f32(eye, {0, 0.8, 0}, {0, 1, 0})
	angle := seconds * 0.3
	sun := linalg.normalize([3]f32{math.cos(angle), -0.9, math.sin(angle)})
	frame := Frame {
		inverse_view_projection = linalg.inverse(view_projection),
		camera                  = {eye.x, eye.y, eye.z, 1},
		sun                     = {sun.x, sun.y, sun.z, 1.6},
	}
	Valhalla.wait_execution(state.last) or_return
	Valhalla.load_memory_to_buffer(mem.ptr_to_bytes(&frame), state.frame_buffer) or_return

	execution, err := Valhalla.execute_workloads(&state.frame)
	if err == Valhalla.Workload_Error.Swapchain_Changed {
		state.recorded = false
		return nil
	}
	state.last = execution
	return err
}

record_frame :: proc(state: ^State) -> Valhalla.Error {
	frame := &state.frame
	Valhalla.reset_workload(frame) or_return
	target, acquire_err := Valhalla.acquire(frame, state.surface)
	state.minimised = acquire_err == Valhalla.Surface_Error.Surface_Minimised
	if state.minimised {
		return nil
	} else if acquire_err != nil {
		return acquire_err
	}
	Valhalla.resize_image(&state.image, target.extent) or_return

	raytrace := state.raytrace
	Valhalla.reset_shader(raytrace)
	traced, _ := Valhalla.bind_shader_output(raytrace, state.image) or_return
	push := state.push
	push.output = state.image
	Valhalla.set_push_data(raytrace, push)
	Valhalla.dispatch_threads(raytrace, {target.extent.x, target.extent.y, 1})
	Valhalla.bind_shader(frame, raytrace^) or_return

	shown := Valhalla.blit_image(frame, traced, target, filter = .NEAREST)
	Valhalla.present(frame, shown)
	Valhalla.finalize_workload(frame) or_return
	state.recorded = true
	return nil
}

on_mouse_button :: proc(window: ^Valhalla.Window, button: Valhalla.Mouse_Button, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	camera := (^Camera)(Valhalla.window_user_pointer(window))
	if button == .Left {
		camera.dragging = action == .Press
	}
}

on_cursor_pos :: proc(window: ^Valhalla.Window, position: [2]f64) {
	camera := (^Camera)(Valhalla.window_user_pointer(window))
	if camera.dragging {
		delta := position - camera.last_mouse
		camera.orbit.yaw -= f32(delta.x) * 0.01
		camera.orbit.pitch = clamp(camera.orbit.pitch + f32(delta.y) * 0.01, 0.05, 1.5)
	}
	camera.last_mouse = position
}

on_scroll :: proc(window: ^Valhalla.Window, offset: [2]f64) {
	camera := (^Camera)(Valhalla.window_user_pointer(window))
	camera.orbit.distance = clamp(camera.orbit.distance - f32(offset.y) * 0.75, 3, 25)
}

on_key :: proc(window: ^Valhalla.Window, key: Valhalla.Key, scancode: i32, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	if key == .Escape && action == .Press {
		Valhalla.request_close(window)
	}
}

add_plane :: proc(vertices: ^[dynamic]Vertex, indices: ^[dynamic]u32) -> Mesh {
	mesh := Mesh{first_index = len(indices), index_count = 6, base_vertex = len(vertices), vertex_count = 4}
	for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
		append(vertices, Vertex{position = {corner.x, 0, corner.y, 1}, normal = {0, 1, 0, 0}})
	}
	append(indices, 0, 1, 2, 0, 2, 3)
	return mesh
}

add_cube :: proc(vertices: ^[dynamic]Vertex, indices: ^[dynamic]u32) -> Mesh {
	mesh := Mesh{first_index = len(indices), index_count = 36, base_vertex = len(vertices), vertex_count = 24}
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
	mesh := Mesh{first_index = len(indices), index_count = rings * segments * 6, base_vertex = len(vertices), vertex_count = (rings + 1) * (segments + 1)}
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
