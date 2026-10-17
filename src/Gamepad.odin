package Valhalla

import "base:runtime"
import "core:strings"
import "vendor:glfw"

MAX_JOYSTICKS :: glfw.JOYSTICK_LAST + 1

Connection_Event :: enum i32 {
	Connected    = glfw.CONNECTED,
	Disconnected = glfw.DISCONNECTED,
}

Hat_Direction :: enum {
	Up,
	Right,
	Down,
	Left,
}

Hat :: bit_set[Hat_Direction;u8]

#assert(1 << uint(Hat_Direction.Up) == glfw.HAT_UP)
#assert(1 << uint(Hat_Direction.Left) == glfw.HAT_LEFT)

Gamepad_Button :: enum i32 {
	A            = glfw.GAMEPAD_BUTTON_A,
	B            = glfw.GAMEPAD_BUTTON_B,
	X            = glfw.GAMEPAD_BUTTON_X,
	Y            = glfw.GAMEPAD_BUTTON_Y,
	Left_Bumper  = glfw.GAMEPAD_BUTTON_LEFT_BUMPER,
	Right_Bumper = glfw.GAMEPAD_BUTTON_RIGHT_BUMPER,
	Back         = glfw.GAMEPAD_BUTTON_BACK,
	Start        = glfw.GAMEPAD_BUTTON_START,
	Guide        = glfw.GAMEPAD_BUTTON_GUIDE,
	Left_Thumb   = glfw.GAMEPAD_BUTTON_LEFT_THUMB,
	Right_Thumb  = glfw.GAMEPAD_BUTTON_RIGHT_THUMB,
	Dpad_Up      = glfw.GAMEPAD_BUTTON_DPAD_UP,
	Dpad_Right   = glfw.GAMEPAD_BUTTON_DPAD_RIGHT,
	Dpad_Down    = glfw.GAMEPAD_BUTTON_DPAD_DOWN,
	Dpad_Left    = glfw.GAMEPAD_BUTTON_DPAD_LEFT,
}

Gamepad_Axis :: enum i32 {
	Left_X        = glfw.GAMEPAD_AXIS_LEFT_X,
	Left_Y        = glfw.GAMEPAD_AXIS_LEFT_Y,
	Right_X       = glfw.GAMEPAD_AXIS_RIGHT_X,
	Right_Y       = glfw.GAMEPAD_AXIS_RIGHT_Y,
	Left_Trigger  = glfw.GAMEPAD_AXIS_LEFT_TRIGGER,
	Right_Trigger = glfw.GAMEPAD_AXIS_RIGHT_TRIGGER,
}

Gamepad_State :: struct {
	buttons: [Gamepad_Button]Action,
	axes:    [Gamepad_Axis]f32,
}

#assert(size_of(Gamepad_State) == size_of(glfw.GamepadState))
#assert(offset_of(Gamepad_State, axes) == offset_of(glfw.GamepadState, axes))

@(private = "file")
joystick_id :: proc(joystick: int, loc := #caller_location) -> i32 {
	assert(joystick >= 0 && joystick < MAX_JOYSTICKS, "joystick out of range", loc)
	return i32(joystick)
}

joystick_present :: proc(joystick: int) -> bool {
	return bool(glfw.JoystickPresent(joystick_id(joystick)))
}

joystick_axes :: proc(joystick: int) -> []f32 {
	return glfw.GetJoystickAxes(joystick_id(joystick))
}

joystick_buttons :: proc(joystick: int) -> []Action {
	return transmute([]Action)glfw.GetJoystickButtons(joystick_id(joystick))
}

joystick_hats :: proc(joystick: int) -> []Hat {
	return transmute([]Hat)glfw.GetJoystickHats(joystick_id(joystick))
}

joystick_name :: proc(joystick: int) -> string {
	return glfw.GetJoystickName(joystick_id(joystick))
}

joystick_guid :: proc(joystick: int) -> string {
	return glfw.GetJoystickGUID(joystick_id(joystick))
}

set_joystick_user_pointer :: proc(joystick: int, pointer: rawptr) {
	glfw.SetJoystickUserPointer(joystick_id(joystick), pointer)
}

joystick_user_pointer :: proc(joystick: int) -> rawptr {
	return glfw.GetJoystickUserPointer(joystick_id(joystick))
}

joystick_is_gamepad :: proc(joystick: int) -> bool {
	return bool(glfw.JoystickIsGamepad(joystick_id(joystick)))
}

gamepad_name :: proc(joystick: int) -> string {
	return glfw.GetGamepadName(joystick_id(joystick))
}

gamepad_state :: proc(joystick: int) -> (state: Gamepad_State, ok: bool) {
	ok = bool(glfw.GetGamepadState(joystick_id(joystick), (^glfw.GamepadState)(&state)))
	return
}

@(require_results)
update_gamepad_mappings :: proc(mappings: string) -> Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if !glfw.UpdateGamepadMappings(strings.clone_to_cstring(mappings, context.temp_allocator)) {
		return .Gamepad_Mappings_Rejected
	}
	return nil
}

Joystick_Proc :: #type proc(joystick: int, event: Connection_Event)

set_joystick_callback :: proc(callback: Joystick_Proc) -> (previous: Joystick_Proc) {
	previous, joystick_callback = joystick_callback, callback
	return
}

@(private = "file")
joystick_callback: Joystick_Proc

@(private)
install_joystick_callback :: proc() {
	glfw.SetJoystickCallback(proc "c" (joystick, event: i32) {
		context = runtime_context
		if joystick_callback != nil {
			joystick_callback(int(joystick), Connection_Event(event))
		}
	})
}
