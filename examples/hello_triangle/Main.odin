package Hello_Triangle

import "core:log"

import Valhalla "../../src"

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Hello triangle failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "Hello Triangle") or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(window) or_return
	defer Valhalla.delete_surface(&surface)

	triangle := Valhalla.make_shader(
		#load("Triangle.slang"),
		[]string{"vertex_main", "fragment_main"},
		push_type = nil, colour_formats = {0 = surface.format},
	) or_return
	defer Valhalla.delete_shader(&triangle)

	target := Valhalla.make_image(surface.format, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}, {.Attachment}, name = "target") or_return
	defer Valhalla.delete_image(&target)

	for !Valhalla.should_close(window) {
		Valhalla.poll_events()
		_ = Valhalla.resize_image(&target, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}) or_return

		frame := Valhalla.make_workload() or_return
		defer Valhalla.delete_workload(&frame)

		cleared := Valhalla.clear_image(&frame, target)
		Valhalla.reset_shader(&triangle)
		drawn := Valhalla.bind_shader_colour(&triangle, cleared)
		Valhalla.draw(&triangle, 3)
		Valhalla.bind_shader(&frame, triangle) or_return

		Valhalla.present(&frame, drawn, &surface)
		Valhalla.finalize_workload(&frame) or_return
		execution := Valhalla.execute_workloads(&frame) or_return
		Valhalla.wait_execution(execution) or_return
		if surface.minimised {
			Valhalla.wait_events()
		}
	}
	return nil
}
