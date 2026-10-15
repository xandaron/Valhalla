package ImGui_Example

import "core:log"
import "core:math"

import imgui "../../deps/imgui"
import Valhalla "../../src"
import valhalla_imgui "../../src/imgui"

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("ImGui example failed: %v", err)
	}
}

// ===[ Demo ]==================================================================

PATTERN_SIZE :: 256

FRAME_HISTORY :: 120

Pattern_Push :: struct {
	size:  [2]f32,
	time:  f32,
	speed: f32,
	tint:  [4]f32,
}

Demo :: struct {
	window:          ^Valhalla.Window,
	surface:         ^Valhalla.Surface,
	pattern_shader:  ^Valhalla.Shader,
	pattern:         Valhalla.Image,
	pattern_written: Valhalla.Image,
	pattern_shown:   bool,
	photo:           Valhalla.Image,
	clear_colour:    [4]f32,
	pattern_tint:    [3]f32,
	pattern_speed:   f32,
	show_demo:       bool,
	show_metrics:    bool,
	show_style:      bool,
	show_about:      bool,
	show_debug_log:  bool,
	show_id_stack:   bool,
	frame_times:     [FRAME_HISTORY]f32,
	frame_index:     int,
	minimised:       bool,
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "Dear ImGui on Valhalla", size = {1600, 900}) or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(&window, {}) or_return
	defer Valhalla.delete_surface(&surface)

	settings := Valhalla.Compiler_Settings {
		search_paths = {#directory + "/../../src/shaders"},
	}
	pattern_shader, _ := Valhalla.make_shader(
		#load("Pattern.slang"),
		[]string{"pattern_vertex", "pattern_fragment"},
		settings,
		{push_type = Pattern_Push, colour_formats = {0 = .R8G8B8A8_UNORM}},
	) or_return
	defer Valhalla.delete_shader(&pattern_shader)

	demo := Demo {
		window          = &window,
		surface         = &surface,
		pattern_shader  = &pattern_shader,
		pattern         = Valhalla.make_image(.R8G8B8A8_UNORM, {PATTERN_SIZE, PATTERN_SIZE, 1}, name = "pattern") or_return,
		photo           = Valhalla.make_image_from_file(#directory + "/../textured_cube/Cube.png") or_return,
		clear_colour    = {0.09, 0.1, 0.13, 1},
		pattern_tint    = {1, 1, 1},
		pattern_speed   = 1,
		show_demo       = true,
	}
	defer Valhalla.delete_image(&demo.pattern)
	defer Valhalla.delete_image(&demo.photo)
	demo.pattern_written = demo.pattern

	valhalla_imgui.init(&window, surface.format.format) or_return
	defer valhalla_imgui.shutdown()

	Valhalla.set_frame_callback(draw_frame, rawptr(&demo))
	defer Valhalla.set_frame_callback(nil)

	for !Valhalla.should_close(&window) {
		if demo.minimised {
			Valhalla.wait_events() or_return
		} else {
			Valhalla.poll_events() or_return
		}
		draw_frame(rawptr(&demo)) or_return
	}
	return nil
}

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	demo := (^Demo)(user_data)

	valhalla_imgui.new_frame()
	imgui.NewFrame()
	build_ui(demo)
	imgui.Render()

	frame := Valhalla.make_workload() or_return
	defer Valhalla.delete_workload(&frame)

	image, acquire_err := Valhalla.acquire(&frame, demo.surface)
	demo.minimised = acquire_err == Valhalla.Surface_Error.Surface_Minimised
	if demo.minimised {
		return nil
	} else if acquire_err != nil {
		return acquire_err
	}

	demo.pattern_written = demo.pattern
	if demo.pattern_shown {
		pattern := demo.pattern_shader
		Valhalla.reset_shader(pattern)
		demo.pattern_written = Valhalla.bind_shader_colour(pattern, demo.pattern)
		Valhalla.set_push_data(
			pattern,
			Pattern_Push {
				size = {PATTERN_SIZE, PATTERN_SIZE},
				time = f32(Valhalla.time()),
				speed = demo.pattern_speed,
				tint = {demo.pattern_tint.r, demo.pattern_tint.g, demo.pattern_tint.b, 1},
			},
		)
		Valhalla.draw(pattern, 3, 1, 0, 0)
		Valhalla.bind_shader(&frame, pattern^) or_return
	}

	colour := Valhalla.srgb_to_linear(demo.clear_colour) if demo.surface.encodes_srgb else demo.clear_colour
	cleared := Valhalla.clear_image(&frame, image, {color = {float32 = colour}})
	drawn := valhalla_imgui.render(&frame, cleared) or_return

	Valhalla.present(&frame, drawn)
	Valhalla.finalize_workload(&frame) or_return
	execution := Valhalla.execute_workload(&frame) or_return
	Valhalla.wait_execution(execution) or_return
	return nil
}

build_ui :: proc(demo: ^Demo) {
	io := imgui.GetIO()
	demo.pattern_shown = false
	demo.frame_times[demo.frame_index] = io.DeltaTime * 1000
	demo.frame_index = (demo.frame_index + 1) % FRAME_HISTORY

	imgui.DockSpaceOverViewport(0, nil, {.PassthruCentralNode})

	if imgui.BeginMainMenuBar() {
		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Quit", "Esc") {
				Valhalla.request_close(demo.window)
			}
			imgui.EndMenu()
		}
		if imgui.BeginMenu("Windows") {
			imgui.MenuItemBoolPtr("Dear ImGui demo", nil, &demo.show_demo)
			imgui.MenuItemBoolPtr("Metrics/Debugger", nil, &demo.show_metrics)
			imgui.MenuItemBoolPtr("Style editor", nil, &demo.show_style)
			imgui.MenuItemBoolPtr("Debug log", nil, &demo.show_debug_log)
			imgui.MenuItemBoolPtr("ID stack tool", nil, &demo.show_id_stack)
			imgui.MenuItemBoolPtr("About", nil, &demo.show_about)
			imgui.EndMenu()
		}
		imgui.EndMainMenuBar()
	}

	if imgui.IsKeyPressed(.Key_Escape) && !io.WantCaptureKeyboard {
		Valhalla.request_close(demo.window)
	}

	if demo.show_demo {
		imgui.ShowDemoWindow(&demo.show_demo)
	}
	if demo.show_metrics {
		imgui.ShowMetricsWindow(&demo.show_metrics)
	}
	if demo.show_debug_log {
		imgui.ShowDebugLogWindow(&demo.show_debug_log)
	}
	if demo.show_id_stack {
		imgui.ShowIDStackToolWindow(&demo.show_id_stack)
	}
	if demo.show_about {
		imgui.ShowAboutWindow(&demo.show_about)
	}
	if demo.show_style {
		if imgui.Begin("Style editor", &demo.show_style) {
			imgui.ShowStyleEditor()
		}
		imgui.End()
	}

	imgui.SetNextWindowPos({40, 60}, .FirstUseEver)
	imgui.SetNextWindowSize({440, 900}, .FirstUseEver)
	if imgui.Begin("Valhalla") {
		imgui.Text("%.1f FPS (%.2f ms)", io.Framerate, 1000 / max(io.Framerate, 0.001))
		imgui.PlotLines("Frame time (ms)", &demo.frame_times[0], FRAME_HISTORY, i32(demo.frame_index), nil, 0, 40, {0, 60})
		imgui.ColorEdit4("Clear colour", &demo.clear_colour)

		imgui.SeparatorText("Rendered by Valhalla this frame")
		imgui.Image(valhalla_imgui.texture(&demo.pattern_written), {PATTERN_SIZE, PATTERN_SIZE})
		demo.pattern_shown = imgui.IsItemVisible() && !imgui.IsWindowAppearing()
		if imgui.IsItemHovered() {
			imgui.SetTooltip("Drawn into an Valhalla image by another shader in the same workload")
		}
		imgui.SliderFloat("Speed", &demo.pattern_speed, 0, 5)
		imgui.ColorEdit3("Tint", &demo.pattern_tint)

		imgui.SeparatorText("Loaded from a file")
		width := min(imgui.GetContentRegionAvail().x, 384)
		imgui.Image(valhalla_imgui.texture(&demo.photo), {width, width * f32(demo.photo.extent.y) / f32(demo.photo.extent.x)})

		imgui.SeparatorText("Draw list primitives")
		draw_primitives()
	}
	imgui.End()
}

draw_primitives :: proc() {
	draw_list := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos()
	size := imgui.Vec2{min(imgui.GetContentRegionAvail().x, 384), 140}
	white := imgui.ColorConvertFloat4ToU32({1, 1, 1, 1})
	imgui.DrawList_AddRectFilledMultiColor(
		draw_list,
		origin,
		origin + size,
		imgui.ColorConvertFloat4ToU32({0.9, 0.2, 0.3, 1}),
		imgui.ColorConvertFloat4ToU32({0.2, 0.4, 0.9, 1}),
		imgui.ColorConvertFloat4ToU32({0.2, 0.9, 0.5, 1}),
		imgui.ColorConvertFloat4ToU32({0.9, 0.8, 0.2, 1}),
	)
	t := f32(imgui.GetTime())
	centre := origin + {size.x * 0.25, size.y * 0.5}
	imgui.DrawList_AddCircleFilled(draw_list, centre + {math.cos(t) * 12, math.sin(t) * 12}, 30, imgui.ColorConvertFloat4ToU32({0, 0, 0, 0.5}))
	imgui.DrawList_AddNgonFilled(draw_list, origin + {size.x * 0.5, size.y * 0.5}, 32, white, 6)
	imgui.DrawList_AddTriangleFilled(
		draw_list,
		origin + {size.x * 0.68, size.y * 0.8},
		origin + {size.x * 0.78, size.y * 0.2},
		origin + {size.x * 0.88, size.y * 0.8},
		imgui.ColorConvertFloat4ToU32({0.1, 0.1, 0.1, 0.8}),
	)
	imgui.DrawList_AddBezierCubic(
		draw_list,
		origin + {8, size.y - 8},
		origin + {size.x * 0.3, -size.y * 0.5},
		origin + {size.x * 0.7, size.y * 1.5},
		origin + {size.x - 8, 8},
		white,
		3,
	)
	imgui.DrawList_AddLine(draw_list, origin, origin + size, imgui.ColorConvertFloat4ToU32({1, 1, 1, 0.3}), 1)
	imgui.DrawList_AddText(draw_list, origin + {8, 8}, white, "ImDrawList")
	imgui.Dummy(size)
}
