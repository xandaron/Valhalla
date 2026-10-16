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

	surface := Valhalla.make_surface(&window, {}) or_return
	defer Valhalla.delete_surface(&surface)

	triangle, _ := Valhalla.make_shader(
		#load("Triangle.slang"),
		[]string{"vertex_main", "fragment_main"},
		{},
		{colour_formats = {0 = surface.format.format}},
	) or_return
	defer Valhalla.delete_shader(&triangle)

	for !Valhalla.should_close(&window) {
		Valhalla.poll_events()

		frame := Valhalla.make_workload() or_return
		defer Valhalla.delete_workload(&frame)

		image, acquire_err := Valhalla.acquire(&frame, &surface)
		if acquire_err == Valhalla.Surface_Error.Surface_Minimised {
			Valhalla.wait_events()
			continue
		} else if acquire_err != nil {
			return acquire_err
		}

		cleared := Valhalla.clear_image(&frame, image, {})
		Valhalla.reset_shader(&triangle)
		drawn := Valhalla.bind_shader_colour(&triangle, cleared)
		Valhalla.draw(&triangle, 3, 1, 0, 0)
		Valhalla.bind_shader(&frame, triangle) or_return

		Valhalla.present(&frame, drawn)
		Valhalla.finalize_workload(&frame) or_return
		execution := Valhalla.execute_workloads(&frame) or_return
		Valhalla.wait_execution(execution) or_return
	}
	return nil
}
