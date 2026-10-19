package Textured_Cube

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:time"

import Valhalla "../../src"

Vertex :: struct {
	position: [4]f32,
	uv:       [2]f32,
	padding:  [2]f32,
}

Frame :: struct {
	transform: matrix[4, 4]f32,
}

Push :: struct {
	frame:          Valhalla.Buffer,
	vertices:       Valhalla.Buffer,
	albedo:         Valhalla.Image,
	linear_sampler: Valhalla.Sampler,
}

Face :: struct {
	normal, across, up: [3]f32,
}

FACES :: [6]Face {
	{normal = {1, 0, 0}, across = {0, 0, -1}, up = {0, 1, 0}},
	{normal = {-1, 0, 0}, across = {0, 0, 1}, up = {0, 1, 0}},
	{normal = {0, 1, 0}, across = {1, 0, 0}, up = {0, 0, -1}},
	{normal = {0, -1, 0}, across = {1, 0, 0}, up = {0, 0, 1}},
	{normal = {0, 0, 1}, across = {1, 0, 0}, up = {0, 1, 0}},
	{normal = {0, 0, -1}, across = {-1, 0, 0}, up = {0, 1, 0}},
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Textured cube failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "Textured Cube") or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(window) or_return
	defer Valhalla.delete_surface(&surface)

	cube_vertices, cube_indices := make_cube()
	vertices := Valhalla.make_buffer_from(cube_vertices, {.Storage}) or_return
	defer Valhalla.delete_buffer(&vertices)
	indices := Valhalla.make_buffer_from(cube_indices, {.Index}) or_return
	defer Valhalla.delete_buffer(&indices)

	texture := Valhalla.make_image_from_file(#directory + "/Cube.png") or_return
	defer Valhalla.delete_image(&texture)
	linear_sampler := Valhalla.make_sampler() or_return
	defer Valhalla.delete_sampler(&linear_sampler)
	frame_data := Valhalla.make_buffer(size_of(Frame), {.Storage}, .Host_Visible) or_return
	defer Valhalla.delete_buffer(&frame_data)

	cube := Valhalla.make_shader(
		#load("Cube.slang"),
		[]string{"vertex_main", "fragment_main"},
		push_type = Push, colour_formats = {0 = surface.format}, depth_format = .D32_SFLOAT,
	) or_return
	defer Valhalla.delete_shader(&cube)

	scene := Scene {
		surface        = &surface,
		cube           = &cube,
		frame_data     = frame_data,
		vertices       = vertices,
		indices        = indices,
		index_count    = len(cube_indices),
		texture        = texture,
		linear_sampler = linear_sampler,
		start          = time.now(),
	}
	scene.depth = Valhalla.make_image(.D32_SFLOAT, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, usage = {.Attachment}, name = "depth") or_return
	defer Valhalla.delete_image(&scene.depth)
	scene.target = Valhalla.make_image(surface.format, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, {.Attachment}, name = "target") or_return
	defer Valhalla.delete_image(&scene.target)
	scene.frame = Valhalla.make_workload("frame") or_return
	defer Valhalla.delete_workload(&scene.frame)
	defer _ = Valhalla.wait_execution(scene.last)

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
	surface:        ^Valhalla.Surface,
	cube:           ^Valhalla.Shader,
	frame:          Valhalla.Workload,
	recorded:       bool,
	last:           Valhalla.Execution,
	frame_data:     Valhalla.Buffer,
	vertices:       Valhalla.Buffer,
	indices:        Valhalla.Buffer,
	index_count:    int,
	texture:        Valhalla.Image,
	linear_sampler: Valhalla.Sampler,
	depth:          Valhalla.Image,
	start:          time.Time,
	target:      Valhalla.Image,
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	scene := (^Scene)(user_data)
	if scene.target.extent.xy != scene.surface.extent {
		scene.recorded = false
	}
	if !scene.recorded {
		record_frame(scene) or_return
	}

	Valhalla.wait_execution(scene.last) or_return
	seconds := f32(time.duration_seconds(time.since(scene.start)))
	frame := Frame {
		transform = view_projection(scene.depth.extent.xy) * linalg.matrix4_rotate_f32(seconds * 0.5, {0, 1, 0}),
	}
	Valhalla.load_to_buffer(frame, scene.frame_data) or_return

	scene.last = Valhalla.execute_workloads(&scene.frame) or_return
	return nil
}

record_frame :: proc(scene: ^Scene) -> Valhalla.Error {
	Valhalla.reset_workload(&scene.frame) or_return
	_ = Valhalla.resize_image(&scene.target, {max(scene.surface.extent.x, 1), max(scene.surface.extent.y, 1), 1}) or_return
	image := scene.target

	_ = Valhalla.resize_image(&scene.depth, image.extent) or_return

	cleared := Valhalla.clear_image(&scene.frame, image, {0.1, 0.1, 0.12, 1})
	depth_cleared := Valhalla.clear_depth(&scene.frame, scene.depth)

	cube := scene.cube
	Valhalla.reset_shader(cube)
	Valhalla.set_push_data(cube, Push{frame = scene.frame_data, vertices = scene.vertices, albedo = scene.texture, linear_sampler = scene.linear_sampler})
	Valhalla.bind_shader_index_buffer(cube, scene.indices, .U16)
	drawn := Valhalla.bind_shader_colour(cube, cleared)
	_ = Valhalla.bind_shader_depth(cube, depth_cleared)
	Valhalla.set_depth_test(cube, true)
	Valhalla.set_depth_write(cube, true)
	Valhalla.draw_indexed(cube, scene.index_count)
	Valhalla.bind_shader(&scene.frame, cube^) or_return

	Valhalla.workload_discards(&scene.frame, scene.depth)
	Valhalla.present(&scene.frame, drawn, scene.surface)
	Valhalla.finalize_workload(&scene.frame) or_return
	scene.recorded = true
	return nil
}

make_cube :: proc() -> (vertices: [24]Vertex, indices: [36]u16) {
	corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
	for face, face_index in FACES {
		cell := [2]f32{f32(face_index % 3), f32(face_index / 3)}
		for corner, corner_index in corners {
			position := face.normal + face.across * corner.x + face.up * corner.y
			vertices[face_index * 4 + corner_index] = {
				position = {position.x, position.y, position.z, 1},
				uv       = {(cell.x + (corner.x + 1) / 2) / 3, (cell.y + (1 - corner.y) / 2) / 2},
			}
		}
		first := u16(face_index * 4)
		copy(indices[face_index * 6:], []u16{first, first + 1, first + 2, first, first + 2, first + 3})
	}
	return
}

view_projection :: proc(size: [2]u32) -> matrix[4, 4]f32 {
	near, far := f32(0.1), f32(100)
	focal := 1 / math.tan(f32(math.PI) / 8)
	aspect := f32(size.x) / f32(size.y)
	projection := matrix[4, 4]f32{
		focal / aspect, 0, 0, 0,
		0, -focal, 0, 0,
		0, 0, near / (far - near), near * far / (far - near),
		0, 0, -1, 0,
	}
	view := linalg.matrix4_look_at_f32({4, 3.5, 5}, {0, 0, 0}, {0, 1, 0})
	return projection * view
}
