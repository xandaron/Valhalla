package Two_Windows

import "core:log"
import "core:math"

import Valhalla "../../src"

WINDOW_SIZE :: [2]i32{520, 400}

DEFAULT_PICK :: [2]f32{0.1, 0.2}

DEFAULT_RADIUS :: 0.25

Shared :: struct {
	colour:  [4]f32,
	pick:    [2]f32,
	radius:  f32,
	padding: f32,
}

Push :: struct {
	size:   [2]f32,
	shared: Valhalla.Buffer,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Two windows failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	controller := Valhalla.make_window(title = "Controller: click to pick, scroll to resize", size = WINDOW_SIZE, position = [2]i32{120, 160}) or_return
	defer Valhalla.delete_window(&controller)
	viewer := Valhalla.make_window(title = "Viewer", size = WINDOW_SIZE, position = [2]i32{120 + WINDOW_SIZE.x + 16, 160}) or_return
	defer Valhalla.delete_window(&viewer)

	controller_surface := Valhalla.make_surface(controller) or_return
	defer Valhalla.delete_surface(&controller_surface)
	viewer_surface := Valhalla.make_surface(viewer) or_return
	defer Valhalla.delete_surface(&viewer_surface)

	palette := Valhalla.make_shader(
		#load("Windows.slang"),
		[]string{"fullscreen", "palette"},
		push_type = Push, colour_formats = {0 = controller_surface.format},
	) or_return
	defer Valhalla.delete_shader(&palette)
	disc := Valhalla.make_shader(#load("Windows.slang"), []string{"fullscreen", "disc"}, push_type = Push, colour_formats = {0 = viewer_surface.format}) or_return
	defer Valhalla.delete_shader(&disc)
	shared := Valhalla.make_buffer(size_of(Shared), {.Storage}, .Host_Visible) or_return
	defer Valhalla.delete_buffer(&shared)

	scene := Scene {
		controls = {pick = DEFAULT_PICK, radius = DEFAULT_RADIUS},
		controller_surface = &controller_surface,
		viewer_surface = &viewer_surface,
		palette = &palette,
		disc = &disc,
		shared = shared,
	}
	for surface, index in ([2]^Valhalla.Surface{&controller_surface, &viewer_surface}) {
		scene.targets[index] = Valhalla.make_image(surface.format, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, {.Attachment}, name = "target") or_return
	}
	defer Valhalla.delete_image(&scene.targets[0])
	defer Valhalla.delete_image(&scene.targets[1])
	scene.frame = Valhalla.make_workload() or_return
	defer Valhalla.delete_workload(&scene.frame)
	defer _ = Valhalla.wait_execution(scene.last)
	Valhalla.set_window_user_pointer(controller, rawptr(&scene.controls))
	Valhalla.set_mouse_button_callback(controller, on_mouse_button)
	Valhalla.set_cursor_position_callback(controller, on_cursor_pos)
	Valhalla.set_scroll_callback(controller, on_scroll)
	Valhalla.set_key_callback(controller, on_key)
	for !Valhalla.should_close(controller) && !Valhalla.should_close(viewer) {
		Valhalla.poll_events()
		draw_frame(&scene) or_return
		if controller_surface.minimised && viewer_surface.minimised {
			Valhalla.wait_events()
		}
	}
	return nil
}

Scene :: struct {
	controls:           Controls,
	controller_surface: ^Valhalla.Surface,
	viewer_surface:     ^Valhalla.Surface,
	palette:            ^Valhalla.Shader,
	disc:               ^Valhalla.Shader,
	shared:             Valhalla.Buffer,
	targets:            [2]Valhalla.Image,
	frame:              Valhalla.Workload,
	recorded:           bool,
	last:               Valhalla.Execution,
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	scene := (^Scene)(user_data)
	surfaces := [2]^Valhalla.Surface{scene.controller_surface, scene.viewer_surface}
	for surface, index in surfaces {
		if scene.targets[index].extent.xy != surface.extent {
			scene.recorded = false
		}
	}
	if !scene.recorded {
		record_frame(scene) or_return
	}

	Valhalla.wait_execution(scene.last) or_return
	shared := Shared {
		colour = hue_value(scene.controls.pick),
		pick   = scene.controls.pick,
		radius = scene.controls.radius,
	}
	Valhalla.load_to_buffer(shared, scene.shared) or_return

	scene.last = Valhalla.execute_workloads(&scene.frame) or_return
	return nil
}

record_frame :: proc(scene: ^Scene) -> Valhalla.Error {
	frame := &scene.frame
	Valhalla.reset_workload(frame) or_return
	record_window(scene, 0, scene.controller_surface, scene.palette) or_return
	record_window(scene, 1, scene.viewer_surface, scene.disc) or_return
	Valhalla.finalize_workload(frame) or_return
	scene.recorded = true
	return nil
}

record_window :: proc(scene: ^Scene, index: int, surface: ^Valhalla.Surface, shader: ^Valhalla.Shader) -> Valhalla.Error {
	_ = Valhalla.resize_image(&scene.targets[index], {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}) or_return
	image := scene.targets[index]

	Valhalla.reset_shader(shader)
	push := Push {
		size   = {f32(image.extent.x), f32(image.extent.y)},
		shared = scene.shared,
	}
	written := Valhalla.bind_shader_colour(shader, image)
	Valhalla.set_push_data(shader, push)
	Valhalla.draw(shader, 3)
	Valhalla.bind_shader(&scene.frame, shader^) or_return
	Valhalla.present(&scene.frame, written, surface)
	return nil
}

Controls :: struct {
	pick:     [2]f32,
	radius:   f32,
	dragging: bool,
}

on_mouse_button :: proc(window: Valhalla.Window, button: Valhalla.Mouse_Button, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	controls := (^Controls)(Valhalla.window_user_pointer(window))
	if button == .Left {
		controls.dragging = action == .Press
		if controls.dragging {
			controls.pick = to_pick(Valhalla.cursor_position(window), Valhalla.window_size(window))
		}
	}
}

on_cursor_pos :: proc(window: Valhalla.Window, position: [2]f64) {
	controls := (^Controls)(Valhalla.window_user_pointer(window))
	if controls.dragging {
		controls.pick = to_pick(position, Valhalla.window_size(window))
	}
}

on_scroll :: proc(window: Valhalla.Window, offset: [2]f64) {
	controls := (^Controls)(Valhalla.window_user_pointer(window))
	controls.radius = clamp(controls.radius + f32(offset.y) * 0.02, 0.05, 0.5)
}

on_key :: proc(window: Valhalla.Window, key: Valhalla.Key, scancode: i32, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	controls := (^Controls)(Valhalla.window_user_pointer(window))
	if action == .Release {
		return
	}
	#partial switch key {
	case .Left:
		controls.pick.x = clamp(controls.pick.x - 0.01, 0, 1)
	case .Right:
		controls.pick.x = clamp(controls.pick.x + 0.01, 0, 1)
	case .Up:
		controls.pick.y = clamp(controls.pick.y - 0.01, 0, 1)
	case .Down:
		controls.pick.y = clamp(controls.pick.y + 0.01, 0, 1)
	case .R:
		controls.pick, controls.radius = DEFAULT_PICK, DEFAULT_RADIUS
	case .Escape:
		Valhalla.request_close(window)
	}
}

to_pick :: proc(position: [2]f64, size: [2]i32) -> [2]f32 {
	return {clamp(f32(position.x) / f32(size.x), 0, 1), clamp(f32(position.y) / f32(size.y), 0, 1)}
}

hue_value :: proc(pick: [2]f32) -> (colour: [4]f32) {
	offsets := [3]f32{0, 4, 2}
	for offset, channel in offsets {
		colour[channel] = clamp(abs(math.mod(pick.x * 6 + offset, 6) - 3) - 1, 0, 1) * (1 - pick.y)
	}
	colour.a = 1
	return
}
