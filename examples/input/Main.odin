package Input

import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"

import Valhalla "../../src"

SPEED :: 400

STICK_DEAD_ZONE :: 0.15

COLOURS := [?][4]f32{{0.95, 0.55, 0.2, 1}, {0.3, 0.7, 1, 1}, {0.5, 0.9, 0.4, 1}, {0.9, 0.35, 0.7, 1}}

Disc :: struct {
	colour:   [4]f32,
	position: [2]f32,
	radius:   f32,
	locked:   u32,
}

Push :: struct {
	disc: Valhalla.Buffer,
}

State :: struct {
	position:   [2]f32,
	radius:     f32,
	colour:     int,
	locked:     bool,
	last_mouse: [2]f64,
	title:      string,
	window:     ^Valhalla.Window,
	surface:    ^Valhalla.Surface,
	shader:     ^Valhalla.Shader,
	disc:       Valhalla.Buffer,
	frame:      Valhalla.Workload,
	recorded:   bool,
	last:       Valhalla.Execution,
	last_time:  f64,
	minimised:  bool,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	if err := run(); err != nil {
		log.errorf("Input failed: %v", err)
	}
}

run :: proc() -> Valhalla.Error {
	Valhalla.init() or_return
	defer Valhalla.shutdown()

	window := Valhalla.make_window(title = "Input: WASD/stick move, Tab locks mouse, C/V clipboard, F11 fullscreen, drop files") or_return
	defer Valhalla.delete_window(&window)

	surface := Valhalla.make_surface(&window, {}) or_return
	defer Valhalla.delete_surface(&surface)

	settings := Valhalla.Compiler_Settings {
		search_paths = {#directory + "/../../src/shaders"},
	}
	shader, _ := Valhalla.make_shader(#load("Input.slang"), []string{"fullscreen", "scene"}, settings, {push_type = Push, colour_formats = {0 = surface.format.format}}) or_return
	defer Valhalla.delete_shader(&shader)

	crosshair := Valhalla.make_standard_cursor(.Crosshair) or_return
	defer Valhalla.delete_cursor(&crosshair)
	Valhalla.set_cursor(&window, crosshair)

	size := Valhalla.window_size(&window)
	state := State {
		position   = [2]f32{f32(size.x), f32(size.y)} * 0.5,
		radius     = 40,
		last_mouse = Valhalla.cursor_position(&window),
	}
	defer delete(state.title)

	Valhalla.set_window_user_pointer(&window, rawptr(&state))
	Valhalla.set_lock_key_modifiers(&window, true)
	Valhalla.set_key_callback(&window, on_key)
	Valhalla.set_mouse_button_callback(&window, on_mouse_button)
	Valhalla.set_cursor_position_callback(&window, on_cursor_pos)
	Valhalla.set_scroll_callback(&window, on_scroll)
	Valhalla.set_cursor_enter_callback(&window, on_cursor_enter)
	Valhalla.set_window_focus_callback(&window, on_focus)
	Valhalla.set_window_size_callback(&window, on_window_size)
	Valhalla.set_framebuffer_size_callback(&window, on_framebuffer_size)
	Valhalla.set_window_minimise_callback(&window, on_minimise)
	Valhalla.set_window_maximise_callback(&window, on_maximise)
	Valhalla.set_window_content_scale_callback(&window, on_content_scale)
	Valhalla.set_window_close_callback(&window, on_close)
	Valhalla.set_drop_callback(&window, on_drop)
	Valhalla.set_joystick_callback(on_joystick)

	for joystick in 0 ..< Valhalla.MAX_JOYSTICKS {
		if Valhalla.joystick_present(joystick) {
			log_joystick(joystick)
		}
	}

	state.window = &window
	state.surface = &surface
	state.shader = &shader
	state.disc = Valhalla.make_empty_buffer(size_of(Disc), Valhalla.Buffer_Settings{usage = {.Storage}, memory = .Host_Visible}) or_return
	defer Valhalla.delete_buffer(&state.disc)
	state.frame = Valhalla.make_workload() or_return
	defer Valhalla.delete_workload(&state.frame)
	defer _ = Valhalla.wait_execution(state.last)
	state.last_time = Valhalla.time()
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

draw_frame :: proc(user_data: rawptr) -> Valhalla.Error {
	state := (^State)(user_data)
	window := state.window
	now := Valhalla.time()
	delta := f32(now - state.last_time)
	state.last_time = now

	if state.title != "" {
		Valhalla.set_window_title(window, state.title)
		delete(state.title)
		state.title = ""
	}

	move: [2]f32
	if held(window, .A) || held(window, .Left) {
		move.x -= 1
	}
	if held(window, .D) || held(window, .Right) {
		move.x += 1
	}
	if held(window, .W) || held(window, .Up) {
		move.y -= 1
	}
	if held(window, .S) || held(window, .Down) {
		move.y += 1
	}
	for joystick in 0 ..< Valhalla.MAX_JOYSTICKS {
		gamepad := Valhalla.gamepad_state(joystick) or_continue
		stick := [2]f32{gamepad.axes[.Left_X], gamepad.axes[.Left_Y]}
		if abs(stick.x) > STICK_DEAD_ZONE || abs(stick.y) > STICK_DEAD_ZONE {
			move += stick
		}
		if gamepad.buttons[.A] == .Press {
			state.colour = 1
		}
	}
	state.position += move * SPEED * delta

	size := Valhalla.window_size(window)
	state.position = {clamp(state.position.x, 0, f32(size.x)), clamp(state.position.y, 0, f32(size.y))}

	if !state.recorded {
		record_frame(state) or_return
		if !state.recorded {
			return nil
		}
	}

	Valhalla.wait_execution(state.last) or_return
	framebuffer := Valhalla.window_framebuffer_size(window)
	scale := [2]f32{f32(framebuffer.x) / f32(max(size.x, 1)), f32(framebuffer.y) / f32(max(size.y, 1))}
	disc := Disc {
		colour   = Valhalla.srgb_to_linear(COLOURS[state.colour]) if state.surface.encodes_srgb else COLOURS[state.colour],
		position = state.position * scale,
		radius   = state.radius * scale.x,
		locked   = u32(state.locked),
	}
	Valhalla.load_memory_to_buffer(mem.ptr_to_bytes(&disc), &state.disc) or_return

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
	image, acquire_err := Valhalla.acquire(frame, state.surface)
	state.minimised = acquire_err == Valhalla.Surface_Error.Surface_Minimised
	if state.minimised {
		return nil
	} else if acquire_err != nil {
		return acquire_err
	}

	shader := state.shader
	Valhalla.reset_shader(shader)
	push := Push {
		disc = state.disc,
	}
	written := Valhalla.bind_shader_colour(shader, image)
	Valhalla.set_push_data(shader, push)
	Valhalla.draw(shader, 3, 1, 0, 0)
	Valhalla.bind_shader(frame, shader^) or_return
	Valhalla.present(frame, written)
	Valhalla.finalize_workload(frame) or_return
	state.recorded = true
	return nil
}

held :: proc(window: ^Valhalla.Window, key: Valhalla.Key) -> bool {
	return Valhalla.key_down(window, key)
}

state_of :: proc(window: ^Valhalla.Window) -> ^State {
	return (^State)(Valhalla.window_user_pointer(window))
}

set_title :: proc(state: ^State, title: string) {
	delete(state.title)
	state.title = strings.clone(title)
}

set_locked :: proc(window: ^Valhalla.Window, locked: bool) {
	state := state_of(window)
	state.locked = locked
	state.last_mouse = Valhalla.cursor_position(window)
	Valhalla.set_cursor_mode(window, locked ? .Disabled : .Normal)
	if Valhalla.raw_mouse_motion_supported() {
		_ = Valhalla.set_raw_mouse_motion(window, locked)
	}
}

on_key :: proc(window: ^Valhalla.Window, key: Valhalla.Key, scancode: i32, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	if action != .Press {
		return
	}
	state := state_of(window)
	log.infof("key %v (%q, scancode %v) %v", key, Valhalla.key_name(key, scancode), scancode, mods)
	#partial switch key {
	case .Escape:
		if state.locked {
			set_locked(window, false)
		} else if _, fullscreen := Valhalla.window_monitor(window); fullscreen {
			Valhalla.set_window_windowed(window)
		} else {
			Valhalla.request_close(window)
		}
	case .F11:
		if _, fullscreen := Valhalla.window_monitor(window); fullscreen {
			Valhalla.set_window_windowed(window)
		} else if monitor, found := Valhalla.nearest_monitor(window); found {
			mode := Valhalla.video_mode(monitor)
			log.infof("fullscreen on %v at %vx%v %v Hz", Valhalla.monitor_name(monitor), mode.size.x, mode.size.y, mode.refresh_rate)
			Valhalla.set_window_fullscreen(window, monitor)
		}
	case .Tab:
		set_locked(window, !state.locked)
	case .Space:
		state.colour = (state.colour + 1) % len(COLOURS)
	case .C:
		Valhalla.set_clipboard_text(fmt.tprintf("%.0f, %.0f", state.position.x, state.position.y))
		log.info("copied the disc position to the clipboard")
	case .V:
		text := Valhalla.clipboard_text()
		line, _, _ := strings.partition(text, "\n")
		log.infof("pasted %v bytes of clipboard text into the title", len(text))
		set_title(state, fmt.tprintf("Pasted: %s", line))
	}
}

on_mouse_button :: proc(window: ^Valhalla.Window, button: Valhalla.Mouse_Button, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	if action != .Press {
		return
	}
	state := state_of(window)
	position := Valhalla.cursor_position(window)
	log.infof("%v button at %v", button, position)
	if !state.locked && button == .Left {
		state.position = {f32(position.x), f32(position.y)}
	}
}

on_cursor_pos :: proc(window: ^Valhalla.Window, position: [2]f64) {
	state := state_of(window)
	if state.locked {
		delta := position - state.last_mouse
		state.position += {f32(delta.x), f32(delta.y)}
	}
	state.last_mouse = position
}

on_scroll :: proc(window: ^Valhalla.Window, offset: [2]f64) {
	state := state_of(window)
	state.radius = clamp(state.radius + f32(offset.y) * 4, 8, 200)
}

on_cursor_enter :: proc(window: ^Valhalla.Window, entered: bool) {
	log.infof("cursor %v", entered ? "entered" : "left")
}

on_focus :: proc(window: ^Valhalla.Window, focused: bool) {
	log.infof("window %v", focused ? "focused" : "unfocused")
	if !focused && state_of(window).locked {
		set_locked(window, false)
	}
}

on_window_size :: proc(window: ^Valhalla.Window, size: [2]i32) {
	log.infof("resized to %v", size)
}

on_framebuffer_size :: proc(window: ^Valhalla.Window, size: [2]i32) {
	log.infof("framebuffer resized to %v", size)
}

on_minimise :: proc(window: ^Valhalla.Window, minimised: bool) {
	log.infof("minimised: %v", minimised)
}

on_maximise :: proc(window: ^Valhalla.Window, maximised: bool) {
	log.infof("maximised: %v", maximised)
}

on_content_scale :: proc(window: ^Valhalla.Window, scale: [2]f32) {
	log.infof("content scale %v", scale)
}

on_close :: proc(window: ^Valhalla.Window) {
	log.info("close requested")
}

on_drop :: proc(window: ^Valhalla.Window, paths: []string) {
	for path in paths {
		log.infof("dropped %s", path)
	}
	set_title(state_of(window), fmt.tprintf("Dropped %v file(s)", len(paths)))
}

on_joystick :: proc(joystick: int, event: Valhalla.Connection_Event) {
	if event == .Connected {
		log_joystick(joystick)
	} else {
		log.infof("joystick %v disconnected", joystick)
	}
}

log_joystick :: proc(joystick: int) {
	if Valhalla.joystick_is_gamepad(joystick) {
		log.infof("gamepad %v connected: %s", joystick, Valhalla.gamepad_name(joystick))
	} else {
		log.infof(
			"joystick %v connected: %s (%v axes, %v buttons, %v hats)",
			joystick,
			Valhalla.joystick_name(joystick),
			len(Valhalla.joystick_axes(joystick)),
			len(Valhalla.joystick_buttons(joystick)),
			len(Valhalla.joystick_hats(joystick)),
		)
	}
}
