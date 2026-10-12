package Demo

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "vendor:glfw"

EXTERNAL_DEFAULT_PORT :: 47470

@(private = "file")
ExternalStepKind :: enum {
	Inject,
	Reply,
	AwaitScreenshot,
}

@(private = "file")
ExternalStep :: struct {
	kind:   ExternalStepKind,
	events: []InputEvent,
	reply:  string,
}

@(private = "file")
ExternalTab :: struct {
	kind:   string,
	index:  u32,
	name:   string,
	pinned: bool,
}

@(private = "file")
ExternalState :: struct {
	scene:         string,
	sceneIndex:    u32,
	scenes:        []string,
	uiHidden:      bool,
	flyMode:       bool,
	selectedKind:  string,
	selectedIndex: i64,
	tabs:          []ExternalTab,
	window:        [2]i32,
	fps:           f64,
}

@(private = "file")
external: struct {
	enabled:   bool,
	listener:  net.TCP_Socket,
	client:    net.TCP_Socket,
	connected: bool,
	received:  [dynamic]byte,
	steps:     [dynamic]ExternalStep,
	capture:   struct {
		prefix:    string,
		remaining: int,
		index:     int,
	},
}

externalInit :: proc(port: int) -> bool {
	listener, err := net.listen_tcp({address = net.IP4_Loopback, port = port}, 1)
	if err != nil {
		logf(.Error, "External API failed to listen on 127.0.0.1:%v: %v", port, err)
		return false
	}
	if blockErr := net.set_blocking(listener, false); blockErr != nil {
		logf(.Error, "External API failed to make its socket non-blocking: %v", blockErr)
		net.close(listener)
		return false
	}

	external.listener = listener
	external.enabled = true
	logf(.Info, "External API listening on 127.0.0.1:%v", port)
	return true
}

externalShutdown :: proc() {
	if !external.enabled {
		return
	}
	externalDisconnect()
	net.close(external.listener)
	delete(external.received)
	delete(external.steps)
	delete(external.capture.prefix)
	external = {}
}

externalTick :: proc() {
	if !external.enabled {
		return
	}

	if !external.connected {
		client, _, err := net.accept_tcp(external.listener)
		if err != nil {
			return
		}
		net.set_blocking(client, false)
		external.client = client
		external.connected = true
		handleInput(CursorEnterEvent{true})
	}

	if external.capture.remaining > 0 && !screenshotPending(&globals.graphicsData) {
		path := fmt.tprintf("%s_%03d.png", external.capture.prefix, external.capture.index)
		if requestScreenshot(&globals.graphicsData, path) {
			external.capture.index += 1
			external.capture.remaining -= 1
		}
	}

	buffer: [4096]byte
	for {
		count, err := net.recv_tcp(external.client, buffer[:])
		if err == .Would_Block {
			break
		}
		if err != nil || count == 0 {
			externalDisconnect()
			return
		}
		append(&external.received, ..buffer[:count])
	}

	for len(external.steps) == 0 {
		line, ok := externalNextLine()
		if !ok {
			return
		}
		externalParse(line)
	}

	step := external.steps[0]
	switch step.kind {
	case .Inject:
		for event in step.events {
			handleInput(event)
		}
	case .Reply:
		externalSend(step.reply)
	case .AwaitScreenshot:
		if screenshotPending(&globals.graphicsData) {
			return
		}
		if !screenshotSaved(&globals.graphicsData) {
			externalSend("err capture failed")
		} else if low, high, dump := screenshotRange(&globals.graphicsData); dump {
			externalSend(fmt.tprintf("ok min=%v max=%v", low, high))
		} else {
			externalSend("ok")
		}
	}
	externalFreeStep(step)
	ordered_remove(&external.steps, 0)
}

@(private = "file")
externalDisconnect :: proc() {
	if external.connected {
		net.close(external.client)
	}
	external.connected = false
	clear(&external.received)
	for step in external.steps {
		externalFreeStep(step)
	}
	clear(&external.steps)
}

@(private = "file")
externalFreeStep :: proc(step: ExternalStep) {
	delete(step.events)
	delete(step.reply)
}

@(private = "file")
externalNextLine :: proc() -> (line: string, ok: bool) {
	for b, i in external.received {
		if b == '\n' {
			line = strings.trim_space(strings.clone_from_bytes(external.received[:i], context.temp_allocator))
			remove_range(&external.received, 0, i + 1)
			return line, true
		}
	}
	return "", false
}

@(private = "file")
externalSend :: proc(reply: string) {
	if !external.connected {
		return
	}
	message := strings.concatenate({reply, "\n"}, context.temp_allocator)
	net.set_blocking(external.client, true)
	_, err := net.send_tcp(external.client, transmute([]byte)message)
	net.set_blocking(external.client, false)
	if err != nil {
		externalDisconnect()
	}
}

@(private = "file")
externalInject :: proc(events: ..InputEvent) {
	append(&external.steps, ExternalStep{kind = .Inject, events = make([]InputEvent, len(events))})
	copy(external.steps[len(external.steps) - 1].events, events)
}

@(private = "file")
externalReply :: proc(format: string, args: ..any) {
	append(&external.steps, ExternalStep{kind = .Reply, reply = fmt.aprintf(format, ..args)})
}

@(private = "file")
externalParse :: proc(line: string) {
	if line == "" {
		return
	}

	command, _, rest := strings.partition(line, " ")
	args := strings.fields(rest, context.temp_allocator)

	number :: proc(args: []string, i: int) -> (value: f64, ok: bool) {
		if i >= len(args) {
			return 0, false
		}
		return strconv.parse_f64(args[i])
	}

	switch command {
	case "ping":
		externalReply("ok pong")

	case "state":
		externalReply("ok %s", externalState())

	case "move":
		x, xOk := number(args, 0)
		y, yOk := number(args, 1)
		if !xOk || !yOk {
			externalReply("err usage: move X Y")
			return
		}
		externalInject(CursorPosEvent{x, y})
		externalReply("ok")

	case "click", "down", "up":
		x, xOk := number(args, 0)
		y, yOk := number(args, 1)
		if !xOk || !yOk {
			externalReply("err usage: %s X Y [left|right|middle] [ctrl] [shift] [alt]", command)
			return
		}
		button := i32(glfw.MOUSE_BUTTON_LEFT)
		mods: i32
		for arg in args[2:] {
			switch arg {
			case "left":
				button = glfw.MOUSE_BUTTON_LEFT
			case "right":
				button = glfw.MOUSE_BUTTON_RIGHT
			case "middle":
				button = glfw.MOUSE_BUTTON_MIDDLE
			case:
				mods |= externalModifier(arg)
			}
		}
		externalInject(CursorPosEvent{x, y})
		if command != "up" {
			externalModifiers(mods, glfw.PRESS)
			externalInject(MouseButtonEvent{button, glfw.PRESS, mods})
		}
		if command != "down" {
			externalInject(MouseButtonEvent{button, glfw.RELEASE, mods})
			externalModifiers(mods, glfw.RELEASE)
		}
		externalReply("ok")

	case "scroll":
		y, ok := number(args, 0)
		if !ok {
			externalReply("err usage: scroll DY")
			return
		}
		externalInject(ScrollEvent{0, y})
		externalReply("ok")

	case "key":
		if len(args) == 0 {
			externalReply("err usage: key NAME [ctrl] [shift] [alt]")
			return
		}
		key, known := externalKey(args[0])
		if !known {
			externalReply("err unknown key %q", args[0])
			return
		}
		mods: i32
		for arg in args[1:] {
			mods |= externalModifier(arg)
		}
		externalModifiers(mods, glfw.PRESS)
		externalInject(KeyEvent{key, 0, glfw.PRESS, mods})
		externalInject(KeyEvent{key, 0, glfw.RELEASE, mods})
		externalModifiers(mods, glfw.RELEASE)
		externalReply("ok")

	case "text":
		events := make([dynamic]InputEvent, context.temp_allocator)
		for codepoint in rest {
			append(&events, CharEvent{codepoint})
		}
		externalInject(..events[:])
		externalReply("ok")

	case "wait":
		frames, ok := number(args, 0)
		if !ok || frames < 0 {
			externalReply("err usage: wait FRAMES")
			return
		}
		for _ in 0 ..< int(frames) {
			externalInject()
		}
		externalReply("ok")

	case "screenshot":
		if rest == "" {
			externalReply("err usage: screenshot PATH")
			return
		}
		if !requestScreenshot(&globals.graphicsData, rest) {
			externalReply("err a screenshot is already pending")
			return
		}
		append(&external.steps, ExternalStep{kind = .AwaitScreenshot})

	case "images":
		listing := strings.builder_make(context.temp_allocator)
		strings.write_string(&listing, "ok")
		for kind in DebugImage {
			info := debugImageInfo(&globals.graphicsData, kind)
			fmt.sbprintf(
				&listing,
				" %s=%vx%vx%v",
				EXTERNAL_IMAGE_NAMES[kind],
				info.extent.width,
				info.extent.height,
				info.layers,
			)
		}
		externalReply("%s", strings.to_string(listing))

	case "dump":
		if len(args) < 2 {
			externalReply("err usage: dump IMAGE PATH [layer]")
			return
		}
		kind, known := externalImage(args[0])
		if !known {
			externalReply("err unknown image %q; see images", args[0])
			return
		}
		layer: u32
		if len(args) > 2 {
			value, ok := strconv.parse_uint(args[2])
			if !ok {
				externalReply("err bad layer %q", args[2])
				return
			}
			layer = u32(value)
		}
		if !requestDebugDump(&globals.graphicsData, kind, layer, args[1]) {
			externalReply("err cannot dump %s layer %v now", args[0], layer)
			return
		}
		append(&external.steps, ExternalStep{kind = .AwaitScreenshot})

	case "capture":
		frames, ok := number(args, 1)
		if len(args) < 2 || !ok || frames < 1 {
			externalReply("err usage: capture PREFIX FRAMES")
			return
		}
		delete(external.capture.prefix)
		external.capture.prefix = strings.clone(args[0])
		external.capture.remaining = int(frames)
		external.capture.index = 0
		externalReply("ok")

	case "quit":
		requestClose(&globals.graphicsData)
		externalReply("ok")

	case:
		externalReply("err unknown command %q", command)
	}
}

@(private = "file")
EXTERNAL_IMAGE_NAMES := [DebugImage]string {
	.SceneColour  = "scene-colour",
	.SceneDepth   = "scene-depth",
	.ShadowColour = "shadow-colour",
	.ShadowDepth  = "shadow-depth",
	.Output       = "output",
	.Interface    = "ui",
}

@(private = "file")
externalImage :: proc(name: string) -> (kind: DebugImage, ok: bool) {
	for candidate in DebugImage {
		if EXTERNAL_IMAGE_NAMES[candidate] == name {
			return candidate, true
		}
	}
	return {}, false
}

@(private = "file")
externalModifiers :: proc(mods: i32, action: i32) {
	MODIFIER_KEYS :: [?][2]i32 {
		{glfw.MOD_CONTROL, glfw.KEY_LEFT_CONTROL},
		{glfw.MOD_SHIFT, glfw.KEY_LEFT_SHIFT},
		{glfw.MOD_ALT, glfw.KEY_LEFT_ALT},
		{glfw.MOD_SUPER, glfw.KEY_LEFT_SUPER},
	}
	held := action == glfw.PRESS ? i32(0) : mods
	for pair in MODIFIER_KEYS {
		if mods & pair[0] == 0 {
			continue
		}
		if action == glfw.PRESS {
			held |= pair[0]
		} else {
			held &~= pair[0]
		}
		externalInject(KeyEvent{pair[1], 0, action, held})
	}
}

@(private = "file")
externalModifier :: proc(name: string) -> i32 {
	switch name {
	case "ctrl":
		return glfw.MOD_CONTROL
	case "shift":
		return glfw.MOD_SHIFT
	case "alt":
		return glfw.MOD_ALT
	case "super":
		return glfw.MOD_SUPER
	}
	return 0
}

@(private = "file")
externalKey :: proc(name: string) -> (key: i32, ok: bool) {
	upper := strings.to_upper(name, context.temp_allocator)
	if len(upper) == 1 {
		c := upper[0]
		if (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
			return i32(c), true
		}
	}
	if len(upper) >= 2 && upper[0] == 'F' {
		if n, parsed := strconv.parse_int(upper[1:]); parsed && n >= 1 && n <= 12 {
			return glfw.KEY_F1 + i32(n - 1), true
		}
	}
	switch upper {
	case "ENTER":
		return glfw.KEY_ENTER, true
	case "ESCAPE":
		return glfw.KEY_ESCAPE, true
	case "TAB":
		return glfw.KEY_TAB, true
	case "BACKSPACE":
		return glfw.KEY_BACKSPACE, true
	case "DELETE":
		return glfw.KEY_DELETE, true
	case "SPACE":
		return glfw.KEY_SPACE, true
	case "LEFT":
		return glfw.KEY_LEFT, true
	case "RIGHT":
		return glfw.KEY_RIGHT, true
	case "UP":
		return glfw.KEY_UP, true
	case "DOWN":
		return glfw.KEY_DOWN, true
	case "HOME":
		return glfw.KEY_HOME, true
	case "END":
		return glfw.KEY_END, true
	}
	return 0, false
}

@(private = "file")
externalState :: proc() -> string {
	scene := &globals.scenes[globals.activeScene]
	uiData := &globals.uiData

	scenes := make([]string, len(globals.scenes), context.temp_allocator)
	for &loaded, i in globals.scenes {
		scenes[i] = loaded.name
	}

	itemName :: proc(scene: ^Scene, item: InspectorItem) -> string {
		switch item.kind {
		case .Object:
			if int(item.index) < len(scene.objects) {
				return scene.objects[item.index].name
			}
		case .Light:
			if int(item.index) < len(scene.lights) {
				return scene.lights[item.index].name
			}
		}
		return ""
	}

	tabs := make([]ExternalTab, len(uiData.inspectorTabs), context.temp_allocator)
	for tab, i in uiData.inspectorTabs {
		tabs[i] = {
			kind   = fmt.tprint(tab.item.kind),
			index  = tab.item.index,
			name   = itemName(scene, tab.item),
			pinned = tab.pinned,
		}
	}

	state := ExternalState {
		scene         = scene.name,
		sceneIndex    = globals.activeScene,
		scenes        = scenes,
		uiHidden      = uiData.hidden,
		flyMode       = mouseMode,
		selectedIndex = -1,
		tabs          = tabs,
		fps           = globals.fps,
	}
	if selected, ok := uiData.selected.?; ok {
		state.selectedKind = fmt.tprint(selected.kind)
		state.selectedIndex = i64(selected.index)
	}
	state.window.x, state.window.y = windowSize(&globals.graphicsData)

	encoded, err := json.marshal(state, allocator = context.temp_allocator)
	if err != nil {
		return "{}"
	}
	return string(encoded)
}
