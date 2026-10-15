package Offscreen

import "core:log"

import Valhalla "../../src"

OUTPUT :: "triangle.png"

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Offscreen failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	target := Valhalla.make_image(.R8G8B8A8_UNORM, {512, 512, 1}) or_return
	defer Valhalla.delete_image(&target)

	triangle, _ := Valhalla.make_shader(
		#load("Triangle.slang"),
		[]string{"vertex_main", "fragment_main"},
		{},
		{colour_formats = {0 = target.format}},
	) or_return
	defer Valhalla.delete_shader(&triangle)

	work := Valhalla.make_workload() or_return
	defer Valhalla.delete_workload(&work)

	cleared := Valhalla.clear_image(&work, target, {color = {float32 = {0, 0, 0, 1}}})
	drawn := Valhalla.bind_shader_colour(&triangle, cleared)
	Valhalla.draw(&triangle, 3, 1, 0, 0)
	Valhalla.bind_shader(&work, triangle) or_return
	picture := Valhalla.readback(&work, drawn) or_return
	Valhalla.finalize_workload(&work) or_return

	execution := Valhalla.execute_workload(&work) or_return
	Valhalla.wait_execution(execution) or_return
	Valhalla.write_readback_to_file(picture, OUTPUT) or_return
	log.infof("Wrote %v", OUTPUT)
	return nil
}
