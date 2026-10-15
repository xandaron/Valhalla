package Hdr

import "core:fmt"
import "core:log"

import Valhalla "../../src"

Push :: struct {
	size:        [2]f32,
	scene:       Valhalla.Image,
	pq:          u32,
	paper_white: f32,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("HDR example failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "HDR") or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(&window, {prefer_hdr = true, manual_encoding = true}) or_return
	defer Valhalla.delete_surface(&surface)
	if !surface.hdr_available {
		log.info("This display offers no HDR format, so the example runs in SDR")
	}

	settings := Valhalla.Compiler_Settings {
		search_paths = {#directory + "/../../src/shaders"},
	}
	ramps, _ := Valhalla.make_shader(#load("Hdr.slang"), []string{"fullscreen", "ramps"}, settings, {push_type = Push, colour_formats = {0 = .R16G16B16A16_SFLOAT}}) or_return
	defer Valhalla.delete_shader(&ramps)

	scene := Scene {
		window   = &window,
		surface  = &surface,
		ramps    = &ramps,
		settings = settings,
		controls = {paper_white = 200},
	}
	defer Valhalla.delete_shader(&scene.encode)
	scene.lit = Valhalla.make_image(.R16G16B16A16_SFLOAT, {max(surface.extent.x, 1), max(surface.extent.y, 1), 1}) or_return
	defer Valhalla.delete_image(&scene.lit)
	scene.frame = Valhalla.make_workload() or_return
	defer Valhalla.delete_workload(&scene.frame)
	defer _ = Valhalla.wait_execution(scene.last)

	Valhalla.set_window_user_pointer(&window, rawptr(&scene.controls))
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

Title :: struct {
	hdr:         bool,
	paper_white: f32,
}

Scene :: struct {
	window:    ^Valhalla.Window,
	surface:   ^Valhalla.Surface,
	ramps:     ^Valhalla.Shader,
	settings:  Valhalla.Compiler_Settings,
	encode:    Valhalla.Shader,
	lit:       Valhalla.Image,
	controls:  Controls,
	shown:     Maybe(Title),
	minimised: bool,
	frame:     Valhalla.Workload,
	recorded:  bool,
	last:      Valhalla.Execution,
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	scene := (^Scene)(user_data)
	surface := scene.surface

	if scene.controls.toggle_hdr {
		scene.controls.toggle_hdr = false
		if surface.hdr_available {
			Valhalla.set_surface_hdr(surface, !surface.hdr) or_return
		}
	}

	title := Title{surface.hdr, scene.controls.paper_white if surface.hdr else 0}
	if shown, ok := scene.shown.?; !ok || shown != title {
		buffer: [128]u8
		if surface.hdr {
			Valhalla.set_window_title(scene.window, fmt.bprintf(buffer[:], "HDR: PQ, paper white %v nits (H for SDR, Up/Down for brightness)", title.paper_white))
		} else {
			Valhalla.set_window_title(scene.window, fmt.bprintf(buffer[:], "HDR example in SDR: clipped at paper white%v", " (H for HDR)" if surface.hdr_available else ""))
		}
		scene.shown = title
	}

	if scene.controls.changed {
		scene.controls.changed = false
		scene.recorded = false
	}
	if !scene.recorded {
		record_frame(scene) or_return
		if !scene.recorded {
			return nil
		}
	}
	execution, err := Valhalla.execute_workload(&scene.frame)
	if err == Valhalla.Workload_Error.Swapchain_Changed {
		scene.recorded = false
		return nil
	}
	scene.last = execution
	return err
}

record_frame :: proc(scene: ^Scene) -> Valhalla.Error {
	surface := scene.surface
	frame := &scene.frame
	Valhalla.reset_workload(frame) or_return

	image, acquire_err := Valhalla.acquire(frame, surface)
	scene.minimised = acquire_err == Valhalla.Surface_Error.Surface_Minimised
	if scene.minimised {
		return nil
	} else if acquire_err != nil {
		return acquire_err
	}

	if scene.encode.handle == 0 || scene.encode.variant.(Valhalla.Graphics_Shader).config.colour_formats[0] != image.format {
		Valhalla.delete_shader(&scene.encode)
		scene.encode, _ = Valhalla.make_shader(#load("Hdr.slang"), []string{"fullscreen", "encode"}, scene.settings, {push_type = Push, colour_formats = {0 = image.format}}) or_return
	}
	Valhalla.resize_image(&scene.lit, image.extent) or_return

	push := Push {
		size        = {f32(image.extent.x), f32(image.extent.y)},
		pq          = 1 if surface.hdr else 0,
		paper_white = scene.controls.paper_white,
	}

	Valhalla.reset_shader(scene.ramps)
	lit := Valhalla.bind_shader_colour(scene.ramps, scene.lit)
	Valhalla.set_push_data(scene.ramps, push)
	Valhalla.draw(scene.ramps, 3, 1, 0, 0)
	Valhalla.bind_shader(frame, scene.ramps^) or_return

	Valhalla.reset_shader(&scene.encode)
	push.scene = lit
	encoded := Valhalla.bind_shader_colour(&scene.encode, image)
	Valhalla.set_push_data(&scene.encode, push)
	Valhalla.draw(&scene.encode, 3, 1, 0, 0)
	Valhalla.bind_shader(frame, scene.encode) or_return

	Valhalla.present(frame, encoded)
	Valhalla.finalize_workload(frame) or_return
	scene.recorded = true
	return nil
}

Controls :: struct {
	paper_white: f32,
	toggle_hdr:  bool,
	changed:     bool,
}

on_key :: proc(window: ^Valhalla.Window, key: Valhalla.Key, scancode: i32, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	controls := (^Controls)(Valhalla.window_user_pointer(window))
	if action == .Release {
		return
	}
	#partial switch key {
	case .H:
		controls.toggle_hdr = true
	case .Up:
		controls.paper_white = min(controls.paper_white + 20, 480)
		controls.changed = true
	case .Down:
		controls.paper_white = max(controls.paper_white - 20, 80)
		controls.changed = true
	case .Escape:
		Valhalla.request_close(window)
	}
}
