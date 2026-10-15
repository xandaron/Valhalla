package Valhalla_ImGui

import "base:runtime"
import "core:c"
import "core:log"
import "core:mem"
import vk "vendor:vulkan"

import imgui "../../deps/imgui"
import Valhalla "../"

// ===[ Platform ]==============================================================

GEOMETRY_SETS :: Valhalla.MAX_EXECUTIONS_IN_FLIGHT + 1

@(private = "file")
GEOMETRY_MIN_CAPACITY :: 4096

@(private = "file")
DECODED_TEXTURE :: u32(1) << 31

@(private = "file")
NEAREST_TEXTURE :: u32(1) << 30

@(private = "file")
NEAREST_TAG :: uintptr(1)

#assert(align_of(Valhalla.Image) > 1)

Filter :: enum {
	Linear,
	Nearest,
}

#assert(size_of(imgui.DrawVert) == 20)
#assert(size_of(imgui.DrawIdx) == 2)

@(private = "file")
Push :: struct {
	scale:       [2]f32,
	translate:   [2]f32,
	vertices:        Valhalla.Buffer,
	sampler:         Valhalla.Sampler,
	nearest_sampler: Valhalla.Sampler,
	srgb_target:     u32,
}

@(private = "file")
Backend :: struct {
	window:           Valhalla.Window,
	runtime_context:  runtime.Context,
	time:             f64,
	cursors:          [imgui.GuiMouseCursor]Valhalla.Cursor,
	shown_cursor:     imgui.GuiMouseCursor,
	last_mouse:       imgui.Vec2,
	mouse_in_window:  bool,
	previous_key:     Valhalla.Key_Proc,
	previous_char:    Valhalla.Text_Proc,
	previous_button:  Valhalla.Mouse_Button_Proc,
	previous_cursor:  Valhalla.Cursor_Position_Proc,
	previous_enter:   Valhalla.Cursor_Enter_Proc,
	previous_scroll:  Valhalla.Scroll_Proc,
	previous_focus:   Valhalla.Window_Focus_Proc,
	shader:           Valhalla.Shader,
	sampler:          Valhalla.Sampler,
	nearest_sampler:  Valhalla.Sampler,
	srgb_target:      bool,
	vertices:         [GEOMETRY_SETS]Valhalla.Buffer,
	indices:          [GEOMETRY_SETS]Valhalla.Buffer,
	geometry_set:     int,
	reported_format:  bool,
}

@(private = "file")
backend: Backend

init :: proc(window: ^Valhalla.Window, target_format: vk.Format, linear_output := false) -> (err: Valhalla.Error) {
	backend = {
		window          = window^,
		runtime_context = context,
		shown_cursor    = .COUNT,
		srgb_target     = Valhalla.is_srgb_format(target_format) || linear_output,
	}
	imgui.SetAllocatorFunctions(
		proc "c" (size: c.size_t, user_data: rawptr) -> rawptr {
			context = backend.runtime_context
			return mem.alloc(int(size)) or_else nil
		},
		proc "c" (pointer: rawptr, user_data: rawptr) {
			context = backend.runtime_context
			mem.free(pointer)
		},
	)
	assert(imgui.CHECKVERSION(), "the ImGui binding does not match the compiled library")
	imgui.CreateContext()
	imgui.StyleColorsDark()

	io := imgui.GetIO()
	io.ConfigFlags += {.DockingEnable, .NavEnableKeyboard, .NavEnableGamepad}
	io.BackendPlatformName = "Valhalla"
	io.BackendRendererName = "Valhalla"
	io.BackendFlags += {.HasMouseCursors, .HasSetMousePos, .RendererHasVtxOffset, .RendererHasTextures}

	platform_io := imgui.GetPlatformIO()
	platform_io.Platform_GetClipboardTextFn = proc "c" (ctx: ^imgui.GuiContext) -> cstring {
		context = backend.runtime_context
		text := Valhalla.clipboard_text()
		return cstring(raw_data(text)) if len(text) > 0 else nil
	}
	platform_io.Platform_SetClipboardTextFn = proc "c" (ctx: ^imgui.GuiContext, text: cstring) {
		context = backend.runtime_context
		Valhalla.set_clipboard_text(string(text))
	}

	for cursor in imgui.GuiMouseCursor {
		if shape, has_shape := cursor_shape(cursor); has_shape {
			backend.cursors[cursor] = Valhalla.make_standard_cursor(shape) or_continue
		}
	}

	backend.previous_key = Valhalla.set_key_callback(window, on_key)
	backend.previous_char = Valhalla.set_text_callback(window, on_char)
	backend.previous_button = Valhalla.set_mouse_button_callback(window, on_mouse_button)
	backend.previous_cursor = Valhalla.set_cursor_position_callback(window, on_cursor_pos)
	backend.previous_enter = Valhalla.set_cursor_enter_callback(window, on_cursor_enter)
	backend.previous_scroll = Valhalla.set_scroll_callback(window, on_scroll)
	backend.previous_focus = Valhalla.set_window_focus_callback(window, on_focus)

	backend.shader, _ = Valhalla.make_shader(
		#load("ImGui.slang"),
		[]string{"imgui_vertex", "imgui_fragment"},
		{search_paths = {#directory + "/../shaders"}},
		{push_type = Push, colour_formats = {0 = target_format}},
	) or_return
	backend.sampler = Valhalla.make_sampler(address_mode = .CLAMP_TO_EDGE) or_return
	backend.nearest_sampler = Valhalla.make_sampler(filter = .NEAREST, mipmap_mode = .NEAREST, address_mode = .CLAMP_TO_EDGE) or_return
	return nil
}

shutdown :: proc() {
	textures := &imgui.GetPlatformIO().Textures
	for texture in textures.Data[:textures.Size] {
		destroy_texture(texture)
	}
	for set in 0 ..< GEOMETRY_SETS {
		Valhalla.delete_buffer(&backend.vertices[set])
		Valhalla.delete_buffer(&backend.indices[set])
	}
	Valhalla.delete_shader(&backend.shader)
	Valhalla.delete_sampler(&backend.sampler)
	Valhalla.delete_sampler(&backend.nearest_sampler)
	for &cursor in backend.cursors {
		Valhalla.delete_cursor(&cursor)
	}

	window := &backend.window
	Valhalla.set_key_callback(window, backend.previous_key)
	Valhalla.set_text_callback(window, backend.previous_char)
	Valhalla.set_mouse_button_callback(window, backend.previous_button)
	Valhalla.set_cursor_position_callback(window, backend.previous_cursor)
	Valhalla.set_cursor_enter_callback(window, backend.previous_enter)
	Valhalla.set_scroll_callback(window, backend.previous_scroll)
	Valhalla.set_window_focus_callback(window, backend.previous_focus)

	imgui.DestroyContext()
	backend = {}
}

texture :: proc(image: ^Valhalla.Image, filter := Filter.Linear) -> imgui.TextureRef {
	return {_TexID = imgui.TextureID(uintptr(image) | (NEAREST_TAG if filter == .Nearest else 0))}
}

new_frame :: proc() {
	io := imgui.GetIO()
	window := &backend.window

	size := Valhalla.window_size(window)
	framebuffer := Valhalla.window_framebuffer_size(window)
	io.DisplaySize = {f32(size.x), f32(size.y)}
	if size.x > 0 && size.y > 0 {
		io.DisplayFramebufferScale = {f32(framebuffer.x) / f32(size.x), f32(framebuffer.y) / f32(size.y)}
	}

	now := Valhalla.time()
	if now <= backend.time {
		now = backend.time + 0.00001
	}
	io.DeltaTime = f32(now - backend.time) if backend.time > 0 else 1.0 / 60
	backend.time = now

	locked := Valhalla.cursor_mode(window) == .Disabled
	if locked {
		imgui.AddMousePosEvent(io, -max(f32), -max(f32))
	} else if Valhalla.window_focused(window) {
		if io.WantSetMousePos {
			Valhalla.set_cursor_position(window, {f64(io.MousePos.x), f64(io.MousePos.y)})
		} else if !backend.mouse_in_window {
			position := Valhalla.cursor_position(window)
			backend.last_mouse = {f32(position.x), f32(position.y)}
			imgui.AddMousePosEvent(io, backend.last_mouse.x, backend.last_mouse.y)
		}
	}

	if !locked && .NoMouseCursorChange not_in io.ConfigFlags {
		update_cursor(io)
	}
	update_gamepad(io)
}

@(private = "file")
update_cursor :: proc(io: ^imgui.GuiIO) {
	cursor := imgui.GetMouseCursor()
	if io.MouseDrawCursor {
		cursor = .None
	}
	if cursor == backend.shown_cursor {
		return
	}
	backend.shown_cursor = cursor
	if cursor == .None {
		Valhalla.set_cursor_mode(&backend.window, .Hidden)
		return
	}
	shown := backend.cursors[cursor]
	if shown.handle == nil {
		shown = backend.cursors[.Arrow]
	}
	Valhalla.set_cursor(&backend.window, shown)
	Valhalla.set_cursor_mode(&backend.window, .Normal)
}

@(private = "file")
update_gamepad :: proc(io: ^imgui.GuiIO) {
	if .NavEnableGamepad not_in io.ConfigFlags {
		return
	}
	io.BackendFlags -= {.HasGamepad}
	for joystick in 0 ..< Valhalla.MAX_JOYSTICKS {
		gamepad := Valhalla.gamepad_state(joystick) or_continue
		io.BackendFlags += {.HasGamepad}
		buttons := [?]struct {
			key:    imgui.GuiKey,
			button: Valhalla.Gamepad_Button,
		} {
			{.Key_GamepadStart, .Start},
			{.Key_GamepadBack, .Back},
			{.Key_GamepadFaceLeft, .X},
			{.Key_GamepadFaceRight, .B},
			{.Key_GamepadFaceUp, .Y},
			{.Key_GamepadFaceDown, .A},
			{.Key_GamepadDpadLeft, .Dpad_Left},
			{.Key_GamepadDpadRight, .Dpad_Right},
			{.Key_GamepadDpadUp, .Dpad_Up},
			{.Key_GamepadDpadDown, .Dpad_Down},
			{.Key_GamepadL1, .Left_Bumper},
			{.Key_GamepadR1, .Right_Bumper},
			{.Key_GamepadL3, .Left_Thumb},
			{.Key_GamepadR3, .Right_Thumb},
		}
		for entry in buttons {
			imgui.AddKeyEvent(io, entry.key, gamepad.buttons[entry.button] == .Press)
		}
		analog :: proc(io: ^imgui.GuiIO, key: imgui.GuiKey, value, low, high: f32) {
			amount := clamp((value - low) / (high - low), 0, 1)
			imgui.AddKeyAnalogEvent(io, key, amount > 0.1, amount)
		}
		axes := gamepad.axes
		analog(io, .Key_GamepadL2, axes[.Left_Trigger], -0.75, 1)
		analog(io, .Key_GamepadR2, axes[.Right_Trigger], -0.75, 1)
		analog(io, .Key_GamepadLStickLeft, axes[.Left_X], -0.25, -1)
		analog(io, .Key_GamepadLStickRight, axes[.Left_X], 0.25, 1)
		analog(io, .Key_GamepadLStickUp, axes[.Left_Y], -0.25, -1)
		analog(io, .Key_GamepadLStickDown, axes[.Left_Y], 0.25, 1)
		analog(io, .Key_GamepadRStickLeft, axes[.Right_X], -0.25, -1)
		analog(io, .Key_GamepadRStickRight, axes[.Right_X], 0.25, 1)
		analog(io, .Key_GamepadRStickUp, axes[.Right_Y], -0.25, -1)
		analog(io, .Key_GamepadRStickDown, axes[.Right_Y], 0.25, 1)
		return
	}
}

@(private = "file")
on_key :: proc(window: ^Valhalla.Window, key: Valhalla.Key, scancode: i32, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	if action != .Repeat {
		io := imgui.GetIO()
		update_modifiers(window, io, mods)
		imgui.AddKeyEvent(io, imgui_key(translate_key(key, scancode)), action == .Press)
	}
	if backend.previous_key != nil {
		backend.previous_key(window, key, scancode, action, mods)
	}
}

@(private = "file")
on_char :: proc(window: ^Valhalla.Window, codepoint: rune) {
	imgui.AddInputCharacter(imgui.GetIO(), u32(codepoint))
	if backend.previous_char != nil {
		backend.previous_char(window, codepoint)
	}
}

@(private = "file")
on_mouse_button :: proc(window: ^Valhalla.Window, button: Valhalla.Mouse_Button, action: Valhalla.Action, mods: Valhalla.Modifiers) {
	if i32(button) < i32(imgui.GuiMouseButton.COUNT) {
		io := imgui.GetIO()
		update_modifiers(window, io, mods)
		imgui.AddMouseButtonEvent(io, i32(button), action == .Press)
	}
	if backend.previous_button != nil {
		backend.previous_button(window, button, action, mods)
	}
}

@(private = "file")
on_cursor_pos :: proc(window: ^Valhalla.Window, position: [2]f64) {
	if Valhalla.cursor_mode(window) != .Disabled {
		backend.last_mouse = {f32(position.x), f32(position.y)}
		imgui.AddMousePosEvent(imgui.GetIO(), backend.last_mouse.x, backend.last_mouse.y)
	}
	if backend.previous_cursor != nil {
		backend.previous_cursor(window, position)
	}
}

@(private = "file")
on_cursor_enter :: proc(window: ^Valhalla.Window, entered: bool) {
	io := imgui.GetIO()
	if entered {
		backend.mouse_in_window = true
		imgui.AddMousePosEvent(io, backend.last_mouse.x, backend.last_mouse.y)
	} else {
		backend.last_mouse = io.MousePos
		backend.mouse_in_window = false
		imgui.AddMousePosEvent(io, -max(f32), -max(f32))
	}
	if backend.previous_enter != nil {
		backend.previous_enter(window, entered)
	}
}

@(private = "file")
on_scroll :: proc(window: ^Valhalla.Window, offset: [2]f64) {
	imgui.AddMouseWheelEvent(imgui.GetIO(), f32(offset.x), f32(offset.y))
	if backend.previous_scroll != nil {
		backend.previous_scroll(window, offset)
	}
}

@(private = "file")
on_focus :: proc(window: ^Valhalla.Window, focused: bool) {
	imgui.AddFocusEvent(imgui.GetIO(), focused)
	if backend.previous_focus != nil {
		backend.previous_focus(window, focused)
	}
}

@(private = "file")
update_modifiers :: proc(window: ^Valhalla.Window, io: ^imgui.GuiIO, mods: Valhalla.Modifiers) {
	held :: proc(window: ^Valhalla.Window, left, right: Valhalla.Key) -> bool {
		return Valhalla.key_down(window, left) || Valhalla.key_down(window, right)
	}
	imgui.AddKeyEvent(io, .Mod_Ctrl, .Control in mods || held(window, .Left_Control, .Right_Control))
	imgui.AddKeyEvent(io, .Mod_Shift, .Shift in mods || held(window, .Left_Shift, .Right_Shift))
	imgui.AddKeyEvent(io, .Mod_Alt, .Alt in mods || held(window, .Left_Alt, .Right_Alt))
	imgui.AddKeyEvent(io, .Mod_Super, .Super in mods || held(window, .Left_Super, .Right_Super))
}

@(private = "file")
translate_key :: proc(key: Valhalla.Key, scancode: i32) -> Valhalla.Key {
	if key < .Space || key > .World_2 {
		return key
	}
	name := Valhalla.key_name(key, scancode)
	if len(name) != 1 {
		return key
	}
	switch character := name[0]; character {
	case '0' ..= '9', '`', '-', '=', '[', ']', '\\', ',', ';', '\'', '.', '/', 'A' ..= 'Z':
		return Valhalla.Key(character)
	case 'a' ..= 'z':
		return Valhalla.Key(character - 'a' + 'A')
	}
	return key
}

@(private = "file")
imgui_key :: proc(key: Valhalla.Key) -> imgui.GuiKey {
	#partial switch key {
	case .Digit_0 ..= .Digit_9:
		return imgui.GuiKey(i32(imgui.GuiKey.Key_0) + i32(key) - i32(Valhalla.Key.Digit_0))
	case .A ..= .Z:
		return imgui.GuiKey(i32(imgui.GuiKey.Key_A) + i32(key) - i32(Valhalla.Key.A))
	case .F1 ..= .F24:
		return imgui.GuiKey(i32(imgui.GuiKey.Key_F1) + i32(key) - i32(Valhalla.Key.F1))
	case .Keypad_0 ..= .Keypad_9:
		return imgui.GuiKey(i32(imgui.GuiKey.Key_Keypad0) + i32(key) - i32(Valhalla.Key.Keypad_0))
	case .Tab:
		return .Key_Tab
	case .Left:
		return .Key_LeftArrow
	case .Right:
		return .Key_RightArrow
	case .Up:
		return .Key_UpArrow
	case .Down:
		return .Key_DownArrow
	case .Page_Up:
		return .Key_PageUp
	case .Page_Down:
		return .Key_PageDown
	case .Home:
		return .Key_Home
	case .End:
		return .Key_End
	case .Insert:
		return .Key_Insert
	case .Delete:
		return .Key_Delete
	case .Backspace:
		return .Key_Backspace
	case .Space:
		return .Key_Space
	case .Enter:
		return .Key_Enter
	case .Escape:
		return .Key_Escape
	case .Apostrophe:
		return .Key_Apostrophe
	case .Comma:
		return .Key_Comma
	case .Minus:
		return .Key_Minus
	case .Period:
		return .Key_Period
	case .Slash:
		return .Key_Slash
	case .Semicolon:
		return .Key_Semicolon
	case .Equal:
		return .Key_Equal
	case .Left_Bracket:
		return .Key_LeftBracket
	case .Backslash:
		return .Key_Backslash
	case .Right_Bracket:
		return .Key_RightBracket
	case .Grave_Accent:
		return .Key_GraveAccent
	case .World_1, .World_2:
		return .Key_Oem102
	case .Caps_Lock:
		return .Key_CapsLock
	case .Scroll_Lock:
		return .Key_ScrollLock
	case .Num_Lock:
		return .Key_NumLock
	case .Print_Screen:
		return .Key_PrintScreen
	case .Pause:
		return .Key_Pause
	case .Keypad_Decimal:
		return .Key_KeypadDecimal
	case .Keypad_Divide:
		return .Key_KeypadDivide
	case .Keypad_Multiply:
		return .Key_KeypadMultiply
	case .Keypad_Subtract:
		return .Key_KeypadSubtract
	case .Keypad_Add:
		return .Key_KeypadAdd
	case .Keypad_Enter:
		return .Key_KeypadEnter
	case .Keypad_Equal:
		return .Key_KeypadEqual
	case .Left_Shift:
		return .Key_LeftShift
	case .Left_Control:
		return .Key_LeftCtrl
	case .Left_Alt:
		return .Key_LeftAlt
	case .Left_Super:
		return .Key_LeftSuper
	case .Right_Shift:
		return .Key_RightShift
	case .Right_Control:
		return .Key_RightCtrl
	case .Right_Alt:
		return .Key_RightAlt
	case .Right_Super:
		return .Key_RightSuper
	case .Menu:
		return .Key_Menu
	}
	return .Key_None
}

@(private = "file")
cursor_shape :: proc(cursor: imgui.GuiMouseCursor) -> (Valhalla.Cursor_Shape, bool) {
	#partial switch cursor {
	case .Arrow, .Wait, .Progress:
		return .Arrow, true
	case .TextInput:
		return .IBeam, true
	case .ResizeAll:
		return .Resize_All, true
	case .ResizeNS:
		return .Resize_NS, true
	case .ResizeEW:
		return .Resize_EW, true
	case .ResizeNESW:
		return .Resize_NESW, true
	case .ResizeNWSE:
		return .Resize_NWSE, true
	case .Hand:
		return .Pointing_Hand, true
	case .NotAllowed:
		return .Not_Allowed, true
	}
	return {}, false
}

// ===[ Renderer ]==============================================================

render :: proc(workload: ^Valhalla.Workload, target: Valhalla.Image) -> (written: Valhalla.Image, err: Valhalla.Error) {
	written = target
	draw_data := imgui.GetDrawData()
	if draw_data.Textures != nil {
		for texture in draw_data.Textures.Data[:draw_data.Textures.Size] {
			if texture.Status != .OK {
				update_texture(texture) or_return
			}
		}
	}

	framebuffer := [2]f32{draw_data.DisplaySize.x * draw_data.FramebufferScale.x, draw_data.DisplaySize.y * draw_data.FramebufferScale.y}
	if framebuffer.x <= 0 || framebuffer.y <= 0 || draw_data.TotalVtxCount == 0 {
		return
	}
	extent := [2]f32{f32(target.extent.x), f32(target.extent.y)}

	set := backend.geometry_set
	backend.geometry_set = (set + 1) % GEOMETRY_SETS
	reserve_geometry(&backend.vertices[set], int(draw_data.TotalVtxCount) * size_of(imgui.DrawVert), {.Storage}) or_return
	reserve_geometry(&backend.indices[set], int(draw_data.TotalIdxCount) * size_of(imgui.DrawIdx), {.Index}) or_return
	vertex_bytes, index_bytes: int
	for list in draw_data.CmdLists.Data[:draw_data.CmdLists.Size] {
		vertices := ([^]u8)(list.VtxBuffer.Data)[:int(list.VtxBuffer.Size) * size_of(imgui.DrawVert)]
		indices := ([^]u8)(list.IdxBuffer.Data)[:int(list.IdxBuffer.Size) * size_of(imgui.DrawIdx)]
		Valhalla.load_memory_to_buffer(vertices, &backend.vertices[set], vertex_bytes) or_return
		Valhalla.load_memory_to_buffer(indices, &backend.indices[set], index_bytes) or_return
		vertex_bytes += len(vertices)
		index_bytes += len(indices)
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	shader := &backend.shader
	Valhalla.reset_shader(shader)
	scale := [2]f32{2 / draw_data.DisplaySize.x, 2 / draw_data.DisplaySize.y}
	push := Push {
		scale       = scale,
		translate   = {-1 - draw_data.DisplayPos.x * scale.x, -1 - draw_data.DisplayPos.y * scale.y},
		vertices        = backend.vertices[set],
		sampler         = backend.sampler,
		nearest_sampler = backend.nearest_sampler,
		srgb_target     = u32(backend.srgb_target),
	}
	Valhalla.set_push_data(shader, push)
	Valhalla.bind_shader_index_buffer(shader, backend.indices[set], .U16)
	written = Valhalla.bind_shader_colour(shader, target)
	Valhalla.set_blend(shader, Valhalla.BLEND_ALPHA)

	bound := make([dynamic]Bound_Texture, 0, 16, context.temp_allocator)
	clip: [2][2]f32
	clip_offset := draw_data.DisplayPos
	clip_scale := draw_data.FramebufferScale
	global_vertex, global_index: int
	for list in draw_data.CmdLists.Data[:draw_data.CmdLists.Size] {
		for &command in list.CmdBuffer.Data[:list.CmdBuffer.Size] {
			if command.UserCallback != nil {
				if transmute(uintptr)command.UserCallback != imgui.DrawCallback_ResetRenderState {
					command.UserCallback(list, &command)
				}
				continue
			}
			texture_id := imgui.DrawCmd_GetTexID(&command)
			if texture_id == imgui.TextureID_Invalid || command.ElemCount == 0 {
				continue
			}
			clip_min := [2]f32{max((command.ClipRect.x - clip_offset.x) * clip_scale.x, 0), max((command.ClipRect.y - clip_offset.y) * clip_scale.y, 0)}
			clip_max := [2]f32 {
				min((command.ClipRect.z - clip_offset.x) * clip_scale.x, framebuffer.x, extent.x),
				min((command.ClipRect.w - clip_offset.y) * clip_scale.y, framebuffer.y, extent.y),
			}
			if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y {
				continue
			}
			texture, already_bound := find_bound(bound[:], texture_id)
			if !already_bound {
				image := (^Valhalla.Image)(uintptr(texture_id) &~ NEAREST_TAG)^
				texture = Valhalla.bind_shader_input(shader, image) or_return
				if Valhalla.is_srgb_format(image.format) {
					texture |= DECODED_TEXTURE
				}
				if uintptr(texture_id) & NEAREST_TAG != 0 {
					texture |= NEAREST_TEXTURE
				}
				append(&bound, Bound_Texture{texture_id, texture})
			}
			if clip != {clip_min, clip_max} {
				clip = {clip_min, clip_max}
				Valhalla.set_scissor(shader, {i32(clip_min.x), i32(clip_min.y)}, {u32(clip_max.x - clip_min.x), u32(clip_max.y - clip_min.y)})
			}
			Valhalla.draw_indexed(
				shader,
				vertex_offset = global_vertex + int(command.VtxOffset),
				first_index = global_index + int(command.IdxOffset),
				index_count = command.ElemCount,
				first_instance = 0,
				instances = 1,
				draw_data = texture,
			)
		}
		global_vertex += int(list.VtxBuffer.Size)
		global_index += int(list.IdxBuffer.Size)
	}
	Valhalla.bind_shader(workload, shader^) or_return
	return
}

@(private = "file")
Bound_Texture :: struct {
	id:      imgui.TextureID,
	binding: u32,
}

@(private = "file")
find_bound :: proc(bound: []Bound_Texture, id: imgui.TextureID) -> (u32, bool) {
	for entry in bound {
		if entry.id == id {
			return entry.binding, true
		}
	}
	return 0, false
}

@(private = "file")
reserve_geometry :: proc(buffer: ^Valhalla.Buffer, size: int, usage: Valhalla.Buffer_Usages) -> Valhalla.Error {
	if buffer.handle != 0 && int(buffer.size) >= size {
		return nil
	}
	capacity := max(int(buffer.size), GEOMETRY_MIN_CAPACITY * size_of(imgui.DrawVert))
	for capacity < size {
		capacity *= 2
	}
	Valhalla.delete_buffer(buffer)
	buffer^ = Valhalla.make_buffer(capacity, Valhalla.Buffer_Settings{usage = usage, memory = .Host_Visible}) or_return
	return nil
}

@(private = "file")
update_texture :: proc(texture: ^imgui.TextureData) -> Valhalla.Error {
	switch texture.Status {
	case .OK, .Destroyed:
	case .WantDestroy:
		if texture.UnusedFrames >= GEOMETRY_SETS {
			destroy_texture(texture)
		}
	case .WantCreate:
		if texture.Format != .RGBA32 && texture.Format != .Alpha8 {
			if !backend.reported_format {
				backend.reported_format = true
				log.errorf("ImGui asked for texture format %v, which this backend does not create", texture.Format)
			}
			imgui.TextureData_SetStatus(texture, .Destroyed)
			return nil
		}
		image := new(Valhalla.Image)
		image^ = Valhalla.make_image(.R8G8B8A8_UNORM, {u32(texture.Width), u32(texture.Height), 1}) or_return
		texture.BackendUserData = image
		upload_texture_rect(texture, {0, 0, u16(texture.Width), u16(texture.Height)}) or_return
		imgui.TextureData_SetTexID(texture, imgui.TextureID(uintptr(image)))
		imgui.TextureData_SetStatus(texture, .OK)
	case .WantUpdates:
		for rect in texture.Updates.Data[:texture.Updates.Size] {
			upload_texture_rect(texture, rect) or_return
		}
		imgui.TextureData_SetStatus(texture, .OK)
	}
	return nil
}

@(private = "file")
upload_texture_rect :: proc(texture: ^imgui.TextureData, rect: imgui.TextureRect) -> Valhalla.Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	width, height := int(rect.w), int(rect.h)
	if width == 0 || height == 0 {
		return nil
	}
	pixels := make([]u8, width * height * 4, context.temp_allocator)
	for row in 0 ..< height {
		source := ([^]u8)(imgui.TextureData_GetPixelsAt(texture, i32(rect.x), i32(rect.y) + i32(row)))
		destination := pixels[row * width * 4:][:width * 4]
		if texture.Format == .RGBA32 {
			copy(destination, source[:width * 4])
		} else {
			for x in 0 ..< width {
				destination[x * 4 + 0] = 255
				destination[x * 4 + 1] = 255
				destination[x * 4 + 2] = 255
				destination[x * 4 + 3] = source[x]
			}
		}
	}
	image := (^Valhalla.Image)(texture.BackendUserData)
	return Valhalla.load_memory_to_image(pixels, image, 0, 0, {u32(rect.x), u32(rect.y), 0}, {u32(width), u32(height), 1})
}

@(private = "file")
destroy_texture :: proc(texture: ^imgui.TextureData) {
	image := (^Valhalla.Image)(texture.BackendUserData)
	if image != nil {
		Valhalla.delete_image(image)
		free(image)
		texture.BackendUserData = nil
	}
	imgui.TextureData_SetTexID(texture, imgui.TextureID_Invalid)
	imgui.TextureData_SetStatus(texture, .Destroyed)
}
