package Valhalla

import "../imgui"
import ImRefl "../imreflect"
import tinyfd "../tinyfiledialogs"
import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

UIData :: struct {
	createComponentInfo: CreateComponentData,
	hidden:              bool,
	hiddenBeforeFly:     bool,
	pendingPopup:        cstring,
	selected:            Maybe(InspectorItem),
	inspectorTabs:       [dynamic]InspectorTab,
	nextTabId:           u32,
	focusInspector:      bool,
	focusTab:            bool,
	selectionScene:      u32,
	sceneFiles:          [dynamic]string,
	sceneFilesScanned:   bool,
	objectFilter:        strings.Builder,
	editField:           TextField,
	debugImage:          DebugImage,
	debugLight:          int,
	debugFace:           int,
	debugRanges:         [DebugImage][2]f32,
	debugDockRequested:  bool,
	gizmo:               Gizmo,
	settingsDockId:      imgui.GuiID,
}

InspectorKind :: enum {
	Object,
	Light,
}

InspectorItem :: struct {
	kind:  InspectorKind,
	index: u32,
}

InspectorTab :: struct {
	item:   InspectorItem,
	id:     u32,
	pinned: bool,
}

GizmoHandle :: enum {
	None,
	AxisX,
	AxisY,
	AxisZ,
	PlaneYZ,
	PlaneXZ,
	PlaneXY,
}

Gizmo :: struct {
	hot:         bool,
	hovered:     GizmoHandle,
	active:      GizmoHandle,
	item:        InspectorItem,
	grab:        Vec3,
	startWorld:  Vec3,
	startLocal:  Vec3,
	toLocal:     Mat3,
}

TextField :: struct {
	builder:   strings.Builder,
	target:    rawptr,
	lastFrame: i32,
}

deleteUIData :: proc(uiData: ^UIData) {
	delete(uiData.inspectorTabs)
	for path in uiData.sceneFiles {
		delete(path)
	}
	delete(uiData.sceneFiles)
	strings.builder_destroy(&uiData.objectFilter)
	strings.builder_destroy(&uiData.editField.builder)
}

@(private = "file")
textFieldResize :: proc "c" (data: ^imgui.GuiInputTextCallbackData) -> i32 {
	if .CallbackResize in data.EventFlag {
		context = globals.runtimeContext
		builder := (^strings.Builder)(data.UserData)
		resize(&builder.buf, int(data.BufSize))
		data.Buf = cstring(raw_data(builder.buf))
	}
	return 0
}

@(private = "file")
inputBuilder :: proc(
	label: cstring,
	builder: ^strings.Builder,
	flags: imgui.GuiInputTextFlags = {},
) -> bool {
	text := strings.to_cstring(builder)
	changed := imgui.InputText(
		label,
		text,
		c.size_t(len(builder.buf) + 1),
		flags + {.CallbackResize},
		textFieldResize,
		builder,
	)
	resize(&builder.buf, len(cstring(raw_data(builder.buf))))
	return changed
}

@(private = "file")
stringField :: proc(
	label: cstring,
	field: ^TextField,
	value: string,
	target: rawptr,
) -> (
	text: string,
	committed: bool,
) {
	frame := imgui.GetFrameCount()
	if field.target == target && field.lastFrame >= frame - 1 {
		inputBuilder(label, &field.builder)
		field.lastFrame = frame
		if imgui.IsItemDeactivated() {
			field.target = nil
			return strings.to_string(field.builder), imgui.IsItemDeactivatedAfterEdit()
		}
		return
	}

	scratch := strings.builder_make(context.temp_allocator)
	strings.write_string(&scratch, value)
	inputBuilder(label, &scratch)
	if imgui.IsItemActive() {
		strings.builder_reset(&field.builder)
		strings.write_string(&field.builder, strings.to_string(scratch))
		field.target = target
		field.lastFrame = frame
	}
	return
}

@(private = "file")
nameField :: proc(label: cstring, field: ^TextField, name: ^string) -> bool {
	text, committed := stringField(label, field, name^, name)
	if !committed || text == "" || text == name^ {
		return false
	}
	delete(name^)
	name^ = strings.clone(text)
	return true
}

inspect :: proc(item: InspectorItem) {
	uiData := &globals.uiData
	uiData.selected = item
	uiData.focusInspector = true
	uiData.focusTab = true

	for tab in uiData.inspectorTabs {
		if tab.item == item {
			return
		}
	}
	for &tab in uiData.inspectorTabs {
		if !tab.pinned {
			tab.item = item
			closeOtherUnpinned(uiData, item)
			return
		}
	}
	append(&uiData.inspectorTabs, InspectorTab{item = item, id = uiData.nextTabId})
	uiData.nextTabId += 1
}

setFlyMode :: proc(enabled: bool) {
	uiData := &globals.uiData
	if enabled {
		uiData.hiddenBeforeFly = uiData.hidden
		uiData.hidden = true
	} else {
		uiData.hidden = uiData.hiddenBeforeFly
	}
}

@(private = "file")
clearSelection :: proc(uiData: ^UIData) {
	clear(&uiData.inspectorTabs)
	uiData.selected = nil
	uiData.focusTab = false
	uiData.selectionScene = globals.activeScene
}

@(private = "file")
switchScene :: proc(graphicsData: ^GraphicsData, sceneIdx: u32) {
	globals.activeScene = sceneIdx
	clearSelection(&globals.uiData)
	graphicsData.reloadBuffers = true
	markCommandsDirty(graphicsData, DIRTY_ALL)
}

@(private = "file")
isSelected :: proc(item: InspectorItem) -> bool {
	selected, ok := globals.uiData.selected.?
	return ok && selected == item
}

@(private = "file")
scanSceneFiles :: proc(uiData: ^UIData) {
	for path in uiData.sceneFiles {
		delete(path)
	}
	clear(&uiData.sceneFiles)
	uiData.sceneFilesScanned = true

	infos, err := os.read_all_directory_by_path(SCENE_PATH(), context.temp_allocator)
	if err != nil {
		logf(.Error, "Failed to read scene directory \"%v\": %v", SCENE_PATH(), err)
		return
	}
	for info in infos {
		if info.type == .Regular && filepath.ext(info.name) == ".scene" {
			append(&uiData.sceneFiles, strings.clone(projectPath(SCENE_PATH(), info.name)))
		}
	}
	slice.sort(uiData.sceneFiles[:])
}

@(private = "file")
loadedSceneIndex :: proc(path: string) -> int {
	target, _ := filepath.abs(path, context.temp_allocator)
	for &scene, sceneIdx in globals.scenes {
		if loaded, _ := filepath.abs(scene.path, context.temp_allocator); loaded == target {
			return sceneIdx
		}
	}
	return -1
}

@(private = "file")
openScene :: proc(graphicsData: ^GraphicsData, path: string) {
	if sceneIdx := loadedSceneIndex(path); sceneIdx >= 0 {
		if u32(sceneIdx) != globals.activeScene {
			switchScene(graphicsData, u32(sceneIdx))
		}
		return
	}

	append(&globals.scenes, Scene{path = strings.clone(path)})
	sceneIdx := len(globals.scenes) - 1
	if err := loadScene(&globals.scenes[sceneIdx]); err != .None {
		logf(.Error, "Failed to open scene \"%s\": %v", path, err)
		deleteScene(&globals.scenes[sceneIdx])
		unordered_remove(&globals.scenes, sceneIdx)
		return
	}
	switchScene(graphicsData, u32(sceneIdx))
}

CreateComponentData :: struct {
	name:      [100]byte,
	savePath:  [100]byte,
	assetPath: [100]byte,
}

overwriteBuffer :: proc(buffer: ^[100]byte, value: []byte) {
	i := 0
	for ; i < len(value); i += 1 {
		buffer[i] = value[i]
	}

	for ; i < len(buffer); i += 1 {
		if buffer[i] == 0 {
			break
		}
		buffer[i] = 0
	}
}

clearBuffer :: proc(buffer: ^[100]byte) {
	for i := 0; i < len(buffer); i += 1 {
		if buffer[i] == 0 {
			break
		}
		buffer[i] = 0
	}
}

bufferText :: proc(buffer: ^[100]byte) -> string {
	length := 0
	for length < len(buffer) && buffer[length] != 0 {
		length += 1
	}
	return string(buffer[:length])
}

clearComponentData :: proc(componentInfo: ^CreateComponentData) {
	clearBuffer(&componentInfo.name)
	clearBuffer(&componentInfo.savePath)
	clearBuffer(&componentInfo.assetPath)
}

saveAs :: proc(scene: ^Scene) {
	absPath, _ := filepath.abs(SCENE_PATH(), context.temp_allocator)
	str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
	if str != "" {
		relPath, err := filepath.rel(globals.projectDir, string(str), context.temp_allocator)
		if err != nil {
			logf(
				.Error,
				"Failed to get relative path: %v\nBase: %v\nPath: %v",
				err,
				globals.projectDir,
				string(str),
			)
			relPath = string(str)
		}
		newPath, oerr := os.replace_path_separators(relPath, '/', context.allocator)
		if oerr != nil {
			log(.Error, "Failed to replace path seperators!")
			return
		}
		delete(scene.path)
		scene.path = newPath
		saveScene(scene)
	}
}

@(private = "file")
sceneEdited :: proc(graphicsData: ^GraphicsData) {
	graphicsData.reloadBuffers = true
	markCommandsDirty(graphicsData, DIRTY_ALL)
}

@(private = "file")
toCstring :: #force_inline proc(str: string, allocator := context.temp_allocator) -> cstring {
	return strings.clone_to_cstring(str, allocator = allocator)
}

drawImgui :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	if globals.activeScene != uiData.selectionScene {
		clearSelection(uiData)
	}

	if uiData.hidden {
		return
	}

	drawMainMenu(graphicsData)
	drawDockSpace()
	drawTranslateGizmo(graphicsData)

	drawObjectCatalog(graphicsData)
	drawLightsPanel(graphicsData)
	drawScenesPanel(graphicsData)
	drawInspector(graphicsData)
	drawScenePanel(graphicsData)
	drawSettingsPanel(graphicsData)
	drawModelsPanel(graphicsData)
	drawTexturesPanel(graphicsData)
	drawDebugPanel(graphicsData)

	if uiData.pendingPopup != nil {
		imgui.OpenPopup(uiData.pendingPopup)
		uiData.pendingPopup = nil
	}
	drawPopups(graphicsData)
}

@(private = "file")
drawDockSpace :: proc() {
	dockSpace := imgui.GetID("EditorDockSpace")
	if imgui.DockBuilderGetNode(dockSpace) == nil {
		imgui.DockBuilderAddNode(
			dockSpace,
			transmute(imgui.GuiDockNodeFlags)imgui.GuiDockNodeFlagsPrivate{.DockSpace},
		)
		imgui.DockBuilderSetNodeSize(dockSpace, imgui.GetMainViewport().WorkSize)
		centre := dockSpace
		left := imgui.DockBuilderSplitNode(centre, .Left, 0.2, nil, &centre)
		right := imgui.DockBuilderSplitNode(centre, .Right, 0.3, nil, &centre)
		bottomRight := imgui.DockBuilderSplitNode(right, .Down, 0.45, nil, &right)
		imgui.DockBuilderDockWindow("Objects", left)
		imgui.DockBuilderDockWindow("Lights", left)
		imgui.DockBuilderDockWindow("Scenes", left)
		imgui.DockBuilderDockWindow("Inspector", right)
		imgui.DockBuilderDockWindow("Scene", bottomRight)
		imgui.DockBuilderDockWindow("Settings", bottomRight)
		imgui.DockBuilderDockWindow("Models", bottomRight)
		imgui.DockBuilderDockWindow("Textures", bottomRight)
		imgui.DockBuilderDockWindow("Debug", bottomRight)
		imgui.DockBuilderFinish(dockSpace)
	}
	uiData := &globals.uiData
	if !uiData.debugDockRequested &&
	   uiData.settingsDockId != 0 &&
	   imgui.FindWindowByName("Debug") == nil {
		imgui.DockBuilderDockWindow("Debug", uiData.settingsDockId)
		uiData.debugDockRequested = true
	}
	imgui.DockSpaceOverViewport(dockSpace, nil, {.PassthruCentralNode})
}

@(private = "file")
drawMainMenu :: proc(graphicsData: ^GraphicsData) {
	if !imgui.BeginMainMenuBar() {
		return
	}
	defer imgui.EndMainMenuBar()

	uiData := &globals.uiData
	scene := &globals.scenes[globals.activeScene]
	if imgui.BeginMenu("File") {
		if imgui.MenuItem("New Scene...") {
			uiData.pendingPopup = "New Scene"
		}

		if imgui.MenuItem("Open") {
			str := string(tinyfd.openFileDialog("Open Scene", projectPathC(SCENE_PATH()), 0, nil, nil, 0))
			if str != "" && os.exists(str) {
				relPath, err := filepath.rel(globals.projectDir, str, context.temp_allocator)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						str,
					)
					relPath = str
				}
				path, oerr := os.replace_path_separators(relPath, '/', context.temp_allocator)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}
				openScene(graphicsData, path)
				scene = &globals.scenes[globals.activeScene]
			}
		}

		if imgui.MenuItem("Save") {
			if scene.path != "" {
				saveScene(scene)
			} else {
				saveAs(scene)
			}
		}

		if imgui.MenuItem("Save As...") {
			saveAs(scene)
			uiData.sceneFilesScanned = false
		}

		if imgui.MenuItem("Close", enabled = len(globals.scenes) > 1) {
			saveScene(scene)
			deleteScene(scene)
			unordered_remove(&globals.scenes, globals.activeScene)
			switchScene(graphicsData, 0)
			scene = &globals.scenes[0]
		}

		imgui.SeparatorText("Assets")
		if imgui.BeginMenu("Import") {
			if imgui.MenuItem("Model") {
				path := tinyfd.openFileDialog("Open Model", projectPathC(RESOURCE_PATH()), 0, nil, nil, 0)
				if str := string(path);
				   str != "" && os.exists(str) && filepath.ext(string(str)) == ".model" {
					relPath, err := filepath.rel(globals.projectDir, str, context.temp_allocator)
					if err != nil {
						logf(
							.Error,
							"Failed to get relative path: %v\nBase: %v\nPath: %v",
							err,
							globals.projectDir,
							string(str),
						)
						relPath = string(str)
					}
					finalPath, oerr := os.replace_path_separators(relPath, '/', context.allocator)
					if oerr != nil {
						log(.Error, "Failed to replace path seperators!")
					}
					append(&scene.models, Model{path = finalPath})
					model := &scene.models[len(scene.models) - 1]
					if err := loadModelComponent(model); err != nil {
						logf(.Error, "Failed to load model component: %v", err)
					} else {
						if err := loadModel(scene, model); err != nil {
							logf(.Error, "Failed to load model: %v", err)
							delete(scene.models[len(scene.models) - 1].path)
							unordered_remove(&scene.models, len(scene.models) - 1)
						}
					}
				}
			}

			if imgui.MenuItem("Texture") {
				path := tinyfd.openFileDialog("Open Texture", projectPathC(RESOURCE_PATH()), 0, nil, nil, 0)
				if str := string(path);
				   str != "" && os.exists(str) && filepath.ext(string(str)) == ".texture" {
					relPath, err := filepath.rel(globals.projectDir, str, context.temp_allocator)
					if err != nil {
						logf(
							.Error,
							"Failed to get relative path: %v\nBase: %v\nPath: %v",
							err,
							globals.projectDir,
							string(str),
						)
						relPath = string(str)
					}
					path, oerr := os.replace_path_separators(relPath, '/', context.allocator)
					if oerr != nil {
						log(.Error, "Failed to replace path seperators!")
					}
					append(&scene.textures, Texture{path = path})
					texture := &scene.textures[len(scene.textures) - 1]
					if err := loadTextureComponent(texture); err != nil {
						logf(.Error, "Failed to load texture: %v", err)
						delete(texture.path)
						unordered_remove(&scene.textures, len(scene.textures) - 1)
					} else if err := addImages(graphicsData, scene, {texture.assetPath}); err != nil {
						logf(.Error, "Failed to add texture image \"%s\": %v", texture.assetPath, err)
						deleteTexture(texture)
						unordered_remove(&scene.textures, len(scene.textures) - 1)
					} else {
						graphicsData.reloadBuffers = true
						markCommandsDirty(graphicsData, DIRTY_ALL)
					}
				}
			}
			imgui.EndMenu()
		}
		imgui.EndMenu()
	}

	readout := fmt.ctprintf(
		"%.0f FPS  %.2f ms  (worst %.2f ms)",
		globals.fps,
		globals.frameTimeMs,
		globals.worstFrameMs,
	)
	imgui.SameLine(
		imgui.GetWindowWidth() - imgui.CalcTextSize(readout).x - imgui.GetStyle().ItemSpacing.x * 2,
	)
	imgui.Text(readout)
}

@(private = "file")
GIZMO_AXES := [3]Vec3{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}

@(private = "file")
GIZMO_COLOURS := [3]u32{0xFF3C3CDC, 0xFF3CC83C, 0xFFDC7832}

@(private = "file")
GIZMO_HOT_COLOUR :: 0xFF28DCF0

@(private = "file")
gizmoTarget :: proc(scene: ^Scene, item: InspectorItem) -> (world: Vec3, local: ^Vec3, toLocal: Mat3, ok: bool) {
	switch item.kind {
	case .Object:
		if int(item.index) >= len(scene.objects) {
			return
		}
		object := &scene.objects[item.index]
		world = (objectTransform(scene, object) * Vec4{0, 0, 0, 1}).xyz
		toLocal = Mat3(inverse(objectParentTransform(scene, object)))
		return world, &object.position, toLocal, true
	case .Light:
		if int(item.index) >= len(scene.lights) {
			return
		}
		light := &scene.lights[item.index]
		return light.position, &light.position, Mat3(1), true
	}
	return
}

@(private = "file")
gizmoGrab :: proc(handle: GizmoHandle, origin: Vec3, rayOrigin, rayDirection: Vec3) -> (point: Vec3, ok: bool) {
	switch handle {
	case .None:
		return
	case .AxisX, .AxisY, .AxisZ:
		axis := GIZMO_AXES[int(handle) - int(GizmoHandle.AxisX)]
		b := dot(axis, rayDirection)
		denominator := 1 - b * b
		if denominator < 1e-5 {
			return
		}
		offset := origin - rayOrigin
		t := (b * dot(rayDirection, offset) - dot(axis, offset)) / denominator
		return origin + axis * t, true
	case .PlaneYZ, .PlaneXZ, .PlaneXY:
		normal := GIZMO_AXES[int(handle) - int(GizmoHandle.PlaneYZ)]
		denominator := dot(normal, rayDirection)
		if abs(denominator) < 1e-5 {
			return
		}
		s := dot(normal, origin - rayOrigin) / denominator
		if s < 0 {
			return
		}
		return rayOrigin + rayDirection * s, true
	}
	return
}

@(private = "file")
drawTranslateGizmo :: proc(graphicsData: ^GraphicsData) {
	gizmo := &globals.uiData.gizmo
	gizmo.hot = false
	gizmo.hovered = .None

	selected, hasSelection := globals.uiData.selected.?
	if !hasSelection || mouseMode {
		gizmo.active = .None
		return
	}
	if gizmo.active != .None && gizmo.item != selected {
		gizmo.active = .None
	}

	scene := &globals.scenes[globals.activeScene]
	world, local, toLocal, ok := gizmoTarget(scene, selected)
	if !ok {
		gizmo.active = .None
		return
	}

	camera := scene.cameras[scene.activeCamera]
	viewProjection := projection(camera) * view(camera)
	project :: proc(graphicsData: ^GraphicsData, viewProjection: Mat4, point: Vec3) -> (screen: Vec2, visible: bool) {
		clip := viewProjection * Vec4{point.x, point.y, point.z, 1}
		if clip.w <= 1e-4 {
			return
		}
		return renderNDCToCursor(graphicsData, clip.xy / clip.w), true
	}

	origin := gizmo.active != .None ? gizmo.startWorld : world
	centre, visible := project(graphicsData, viewProjection, world)
	if !visible {
		gizmo.active = .None
		return
	}
	size := length(world - camera.eye) * 0.15

	axisEnds: [3]Vec2
	axisVisible: [3]bool
	for axis, i in GIZMO_AXES {
		axisEnds[i], axisVisible[i] = project(graphicsData, viewProjection, world + axis * size)
	}
	planeCorners: [3][4]Vec2
	planeVisible: [3]bool
	for normal in 0 ..< 3 {
		a := GIZMO_AXES[(normal + 1) % 3] * size
		b := GIZMO_AXES[(normal + 2) % 3] * size
		corners := [4]Vec3 {
			world + a * 0.2 + b * 0.2,
			world + a * 0.45 + b * 0.2,
			world + a * 0.45 + b * 0.45,
			world + a * 0.2 + b * 0.45,
		}
		planeVisible[normal] = true
		for corner, c in corners {
			screen, onScreen := project(graphicsData, viewProjection, corner)
			planeCorners[normal][c] = screen
			planeVisible[normal] &&= onScreen
		}
	}

	io := imgui.GetIO()
	mouse := Vec2{io.MousePos.x, io.MousePos.y}
	if gizmo.active == .None && !io.WantCaptureMouse {
		insideQuad :: proc(point: Vec2, quad: [4]Vec2) -> bool {
			sign: f32
			for i in 0 ..< 4 {
				edge := quad[(i + 1) % 4] - quad[i]
				side := edge.x * (point.y - quad[i].y) - edge.y * (point.x - quad[i].x)
				if sign == 0 {
					sign = side
				} else if side * sign < 0 {
					return false
				}
			}
			return true
		}
		segmentDistance :: proc(point, a, b: Vec2) -> f32 {
			ab := b - a
			t := clamp(dot(point - a, ab) / max(dot(ab, ab), 1e-6), 0, 1)
			return length(point - (a + ab * t))
		}

		for normal in 0 ..< 3 {
			if planeVisible[normal] && insideQuad(mouse, planeCorners[normal]) {
				gizmo.hovered = GizmoHandle(int(GizmoHandle.PlaneYZ) + normal)
			}
		}
		if gizmo.hovered == .None {
			for i in 0 ..< 3 {
				if axisVisible[i] && segmentDistance(mouse, centre, axisEnds[i]) < 7 {
					gizmo.hovered = GizmoHandle(int(GizmoHandle.AxisX) + i)
				}
			}
		}

		if gizmo.hovered != .None && imgui.IsMouseClicked(.Left) {
			if rayOrigin, rayDirection, rayOk := cursorRay(mouse); rayOk {
				if grab, grabOk := gizmoGrab(gizmo.hovered, world, rayOrigin, rayDirection); grabOk {
					gizmo.active = gizmo.hovered
					gizmo.item = selected
					gizmo.grab = grab
					gizmo.startWorld = world
					gizmo.startLocal = local^
					gizmo.toLocal = toLocal
				}
			}
		}
	}

	if gizmo.active != .None {
		if !imgui.IsMouseDown(.Left) {
			gizmo.active = .None
		} else if rayOrigin, rayDirection, rayOk := cursorRay(mouse); rayOk {
			if point, pointOk := gizmoGrab(gizmo.active, origin, rayOrigin, rayDirection); pointOk {
				local^ = gizmo.startLocal + gizmo.toLocal * (point - gizmo.grab)
			}
		}
	}
	gizmo.hot = gizmo.hovered != .None || gizmo.active != .None

	drawList := imgui.GetBackgroundDrawList()
	highlight := gizmo.active != .None ? gizmo.active : gizmo.hovered
	for normal in 0 ..< 3 {
		if !planeVisible[normal] {
			continue
		}
		handle := GizmoHandle(int(GizmoHandle.PlaneYZ) + normal)
		colour := handle == highlight ? u32(GIZMO_HOT_COLOUR) : GIZMO_COLOURS[normal]
		quad := planeCorners[normal]
		imgui.DrawList_AddQuadFilled(drawList, quad[0], quad[1], quad[2], quad[3], (colour & 0x00FFFFFF) | 0x60000000)
		imgui.DrawList_AddQuad(drawList, quad[0], quad[1], quad[2], quad[3], colour, 1.5)
	}
	for i in 0 ..< 3 {
		if !axisVisible[i] {
			continue
		}
		handle := GizmoHandle(int(GizmoHandle.AxisX) + i)
		colour := handle == highlight ? u32(GIZMO_HOT_COLOUR) : GIZMO_COLOURS[i]
		direction := axisEnds[i] - centre
		span := length(direction)
		if span < 1 {
			continue
		}
		direction /= span
		side := Vec2{-direction.y, direction.x}
		headBase := axisEnds[i] - direction * 12
		imgui.DrawList_AddLine(drawList, centre, headBase, colour, 3)
		imgui.DrawList_AddTriangleFilled(drawList, axisEnds[i], headBase + side * 6, headBase - side * 6, colour)
	}
	imgui.DrawList_AddCircleFilled(drawList, centre, 4, 0xFFFFFFFF)
}

@(private = "file")
drawObjectCatalog :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	defer imgui.End()
	if !imgui.Begin("Objects") {
		return
	}

	scene := &globals.scenes[globals.activeScene]
	if imgui.Button("New Object") {
		addObject(scene, 0)
		graphicsData.reloadBuffers = true
		markCommandsDirty(graphicsData, DIRTY_GEOMETRY)
		inspect({.Object, u32(len(scene.objects) - 1)})
	}
	imgui.SameLine()
	imgui.SetNextItemWidth(-1)
	inputBuilder("##filter", &uiData.objectFilter)
	imgui.SetItemTooltip("Filter by name")

	filter := strings.to_lower(strings.to_string(uiData.objectFilter), context.temp_allocator)
	for &object, objectIdx in scene.objects {
		if filter != "" && !strings.contains(strings.to_lower(object.name, context.temp_allocator), filter) {
			continue
		}
		item := InspectorItem{.Object, u32(objectIdx)}
		if imgui.Selectable(fmt.ctprintf("%s##object%v", object.name, objectIdx), isSelected(item)) {
			inspect(item)
		}
	}
}

@(private = "file")
drawLightsPanel :: proc(graphicsData: ^GraphicsData) {
	defer imgui.End()
	if !imgui.Begin("Lights") {
		return
	}

	scene := &globals.scenes[globals.activeScene]
	for &light, lightIdx in scene.lights {
		item := InspectorItem{.Light, u32(lightIdx)}
		if imgui.Selectable(fmt.ctprintf("%s##light%v", light.name, lightIdx), isSelected(item)) {
			inspect(item)
		}
	}
}

@(private = "file")
drawScenesPanel :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	defer imgui.End()
	if !imgui.Begin("Scenes") {
		return
	}

	if imgui.Button("New Scene") {
		uiData.pendingPopup = "New Scene"
	}
	imgui.SameLine()
	if imgui.Button("Refresh") || !uiData.sceneFilesScanned {
		scanSceneFiles(uiData)
	}

	for path in uiData.sceneFiles {
		sceneIdx := loadedSceneIndex(path)
		active := sceneIdx >= 0 && u32(sceneIdx) == globals.activeScene
		label: cstring
		if sceneIdx >= 0 {
			label = fmt.ctprintf("%s  (%s)##%s", globals.scenes[sceneIdx].name, filepath.base(path), path)
		} else {
			label = fmt.ctprintf("%s##%s", filepath.base(path), path)
		}
		if imgui.Selectable(label, active) && !active {
			openScene(graphicsData, path)
		}
	}
}

@(private = "file")
PIN_SPACE :: "   "

@(private = "file")
pinToggle :: proc(tab: ^InspectorTab) {
	low := imgui.GetItemRectMin()
	high := imgui.GetItemRectMax()
	iconLeft := low.x + imgui.GetStyle().FramePadding.x
	iconWidth := imgui.CalcTextSize(PIN_SPACE).x
	centre := imgui.Vec2{iconLeft + iconWidth * 0.5, (low.y + high.y) * 0.5}

	mouse := imgui.GetMousePos()
	overIcon :=
		imgui.IsItemHovered() && mouse.x >= iconLeft && mouse.x < iconLeft + iconWidth
	if overIcon && imgui.IsMouseClicked(.Left) {
		tab.pinned = !tab.pinned
		globals.uiData.selected = tab.item
		globals.uiData.focusTab = true
	}
	if overIcon {
		imgui.SetTooltip(tab.pinned ? "Unpin" : "Pin")
	}

	size := (high.y - low.y) * 0.32
	angle: f32 = tab.pinned ? 0 : 0.785398
	colour := imgui.GetColorU32(tab.pinned || overIcon ? .Text : .TextDisabled)
	point :: proc(centre: imgui.Vec2, size, angle, x, y: f32) -> imgui.Vec2 {
		return {
			centre.x + (x * cos(angle) - y * sin(angle)) * size,
			centre.y + (x * sin(angle) + y * cos(angle)) * size,
		}
	}
	quad :: proc(drawList: ^imgui.DrawList, centre: imgui.Vec2, size, angle, x0, y0, x1, y1: f32, colour: u32) {
		imgui.DrawList_AddQuadFilled(
			drawList,
			point(centre, size, angle, x0, y0),
			point(centre, size, angle, x1, y0),
			point(centre, size, angle, x1, y1),
			point(centre, size, angle, x0, y1),
			colour,
		)
	}

	drawList := imgui.GetWindowDrawList()
	quad(drawList, centre, size, angle, -0.4, -1.0, 0.4, -0.75, colour)
	quad(drawList, centre, size, angle, -0.22, -0.75, 0.22, -0.15, colour)
	quad(drawList, centre, size, angle, -0.6, -0.15, 0.6, 0.05, colour)
	imgui.DrawList_AddLine(
		drawList,
		point(centre, size, angle, 0, 0.05),
		point(centre, size, angle, 0, 1.0),
		colour,
		1.5,
	)
}

@(private = "file")
itemName :: proc(scene: ^Scene, item: InspectorItem) -> (name: ^string, ok: bool) {
	switch item.kind {
	case .Object:
		if int(item.index) < len(scene.objects) {
			return &scene.objects[item.index].name, true
		}
	case .Light:
		if int(item.index) < len(scene.lights) {
			return &scene.lights[item.index].name, true
		}
	}
	return nil, false
}

@(private = "file")
drawInspector :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	if uiData.focusInspector {
		imgui.SetNextWindowFocus()
		uiData.focusInspector = false
	}
	defer imgui.End()
	if !imgui.Begin("Inspector") {
		return
	}

	if len(uiData.inspectorTabs) == 0 {
		imgui.TextDisabled("Click an object or light gizmo in the viewport, or pick one from a list.")
		return
	}

	if !imgui.BeginTabBar("##inspector", {.FittingPolicyScroll}) {
		return
	}
	defer imgui.EndTabBar()

	scene := &globals.scenes[globals.activeScene]
	for i := 0; i < len(uiData.inspectorTabs); {
		item := uiData.inspectorTabs[i].item
		name, ok := itemName(scene, item)
		if !ok {
			ordered_remove(&uiData.inspectorTabs, i)
			continue
		}

		focusThis := uiData.focusTab && isSelected(item)
		open := true
		flags: imgui.GuiTabItemFlags
		if focusThis {
			flags = {.SetSelected}
		}
		label := fmt.ctprintf("%s%s###inspector%v", PIN_SPACE, name^, uiData.inspectorTabs[i].id)
		selected := imgui.BeginTabItem(label, &open, flags)
		pinToggle(&uiData.inspectorTabs[i])
		if selected {
			if focusThis {
				uiData.focusTab = false
			} else if !uiData.focusTab {
				uiData.selected = item
			}
			switch item.kind {
			case .Object:
				drawObjectInspector(graphicsData, scene, item.index)
			case .Light:
				drawLightInspector(graphicsData, scene, item.index)
			}
			imgui.EndTabItem()
		}

		if !open {
			ordered_remove(&uiData.inspectorTabs, i)
			if isSelected(item) {
				uiData.selected = nil
			}
			continue
		}
		i += 1
	}

	if selected, ok := uiData.selected.?; ok {
		for tab in uiData.inspectorTabs {
			if tab.item == selected && !tab.pinned {
				closeOtherUnpinned(uiData, selected)
				break
			}
		}
	}
}

@(private = "file")
closeOtherUnpinned :: proc(uiData: ^UIData, keep: InspectorItem) {
	for i := 0; i < len(uiData.inspectorTabs); {
		tab := uiData.inspectorTabs[i]
		if !tab.pinned && tab.item != keep {
			ordered_remove(&uiData.inspectorTabs, i)
			continue
		}
		i += 1
	}
}

@(private = "file")
drawLightInspector :: proc(graphicsData: ^GraphicsData, scene: ^Scene, lightIdx: u32) {
	light := &scene.lights[lightIdx]
	nameField(fmt.ctprintf("Name##light%v", lightIdx), &globals.uiData.editField, &light.name)
	if ImRefl.draw_value(light.name, light^, {flags = {.Flatten}}) {
		sceneEdited(graphicsData)
	}
}

@(private = "file")
drawObjectInspector :: proc(graphicsData: ^GraphicsData, scene: ^Scene, objectIdx: u32) {
	object := &scene.objects[objectIdx]
	suffix := fmt.tprintf("##object%v", objectIdx)

	nameField(fmt.ctprintf("Name%v", suffix), &globals.uiData.editField, &object.name)

	if ImRefl.draw_value(object.name, object^, {flags = {.Flatten}}) {
		sceneEdited(graphicsData)
	}

	imgui.SeparatorText("Model")
	if imgui.BeginCombo(fmt.ctprintf("Model%v", suffix), toCstring(scene.models[object.modelIdx].name)) {
		defer imgui.EndCombo()
		for modelIdx in 0 ..< len(scene.models) {
			if u32(modelIdx) == object.modelIdx {
				continue
			}

			model := &scene.models[modelIdx]
			if imgui.Selectable(toCstring(model.name)) {
				changeModel(scene, objectIdx, u32(modelIdx))
				textureIdxs := make([][TextureIndex]u32, len(model.meshes))
				for i in 0 ..< min(len(model.meshes), len(object.textureIdxs)) {
					textureIdxs[i] = object.textureIdxs[i]
				}
				delete(object.textureIdxs)
				object.textureIdxs = textureIdxs

				delete(object.animation.state)
				delete(object.animation.cache)
				object.animation.state = make([]Mat4, len(model.skeleton))
				object.animation.cache = make([]ObjectAnimationCache, len(model.skeleton))

				graphicsData.reloadBuffers = true
				markCommandsDirty(graphicsData, DIRTY_GEOMETRY)
			}
		}
	}

	animationData := &object.animation
	if len(scene.models[object.modelIdx].animations) > 0 {
		imgui.SeparatorText("Animation")
		animationName: string
		if animationData.idx >= 0 {
			animationName = scene.models[object.modelIdx].animations[animationData.idx].name
		} else {
			animationName = "None"
		}

		if imgui.BeginCombo(fmt.ctprintf("Animation Clip%v", suffix), toCstring(animationName)) {
			defer imgui.EndCombo()
			if animationData.idx >= 0 {
				if imgui.Selectable("None") {
					animationData.idx = -1
					animationData.timer = 0
				}
			}

			for &animation, animationIdx in scene.models[object.modelIdx].animations {
				if i32(animationIdx) == animationData.idx {
					continue
				}

				if imgui.Selectable(toCstring(animation.name)) {
					animationData.idx = i32(animationIdx)
					animationData.timer = 0
					for &node in animationData.cache {
						node.positionIdx = 0
						node.rotationIdx = 0
						node.scaleIdx = 0
					}
				}
			}
		}
	}

	imgui.SeparatorText("Textures")
	for mesh, meshIdx in scene.models[object.modelIdx].meshes {
		meshSuffix := fmt.ctprintf("%v##mesh%v", suffix, meshIdx)
		if imgui.TreeNode(fmt.ctprintf("%s%v", mesh.name, meshSuffix)) {
			defer imgui.TreePop()
			for slot in TextureIndex {
				current := &object.textureIdxs[meshIdx][slot]
				if imgui.BeginCombo(fmt.ctprintf("%v%v", slot, meshSuffix), toCstring(scene.textures[current^].name)) {
					defer imgui.EndCombo()
					for &texture, textureIdx in scene.textures {
						if current^ == u32(textureIdx) {
							continue
						}
						if imgui.Selectable(toCstring(texture.name)) {
							current^ = u32(textureIdx)
							graphicsData.reloadBuffers = true
						}
					}
				}
			}
		}
	}
}

@(private = "file")
drawScenePanel :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	defer imgui.End()
	if !imgui.Begin("Scene") {
		return
	}

	scene := &globals.scenes[globals.activeScene]
	nameField("Name##scene", &uiData.editField, &scene.name)
	if ImRefl.draw_value("Ambient light", scene.ambientLight) {
		graphicsData.reloadBuffers = true
	}
	if ImRefl.draw_value("Clear colour", scene.clearColour, {flags = {.Colour}}) {
		graphicsData.reloadBuffers = true
	}

	if imgui.CollapsingHeader("Cameras##header") {
		for &camera in scene.cameras {
			if ImRefl.draw_value(camera.name, camera) {
				sceneEdited(graphicsData)
			}
		}
	}
}

@(private = "file")
drawModelsPanel :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	defer imgui.End()
	if !imgui.Begin("Models") {
		return
	}

	if imgui.Button("Add New Model") {
		uiData.pendingPopup = "New Model"
	}

	scene := &globals.scenes[globals.activeScene]
	for &model, modelIdx in scene.models {
		if !imgui.TreeNode(fmt.ctprintf("%s###model%v", model.name, modelIdx)) {
			continue
		}
		defer imgui.TreePop()

		nameField(fmt.ctprintf("Name##model%v", modelIdx), &uiData.editField, &model.name)
		if asset, committed := stringField(
			fmt.ctprintf("Asset##model%v", modelIdx),
			&uiData.editField,
			model.assetPath,
			&model.assetPath,
		); committed && asset != "" && asset != model.assetPath {
			path := strings.clone(asset, context.temp_allocator)
			if err := changeModelAsset(scene, u32(modelIdx), path); err != .None {
				logf(.Error, "Failed to load model asset \"%s\": %v", path, err)
			} else {
				graphicsData.reloadBuffers = true
				markCommandsDirty(graphicsData, DIRTY_ALL)
			}
		}

		if ImRefl.draw_value(model.name, model, {flags = {.Flatten}}) {
			sceneEdited(graphicsData)
		}
	}
}

@(private = "file")
drawTexturesPanel :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	defer imgui.End()
	if !imgui.Begin("Textures") {
		return
	}

	if imgui.Button("Add New Texture") {
		uiData.pendingPopup = "New Texture"
	}

	scene := &globals.scenes[globals.activeScene]
	for &texture, textureIdx in scene.textures {
		if !imgui.TreeNode(fmt.ctprintf("%s###texture%v", texture.name, textureIdx)) {
			continue
		}
		defer imgui.TreePop()

		nameField(fmt.ctprintf("Name##texture%v", textureIdx), &uiData.editField, &texture.name)
		if asset, committed := stringField(
			fmt.ctprintf("Asset##texture%v", textureIdx),
			&uiData.editField,
			texture.assetPath,
			&texture.assetPath,
		); committed && asset != "" && asset != texture.assetPath {
			path := strings.clone(asset, context.temp_allocator)
			if err := changeTextureImage(graphicsData, scene, u32(textureIdx), path); err != nil {
				logf(.Error, "Failed to load texture asset \"%s\": %v", path, err)
			}
		}

		if id, size, ok := texturePreview(graphicsData, scene, u32(textureIdx)); ok && size.x > 0 {
			width := min(imgui.GetContentRegionAvail().x, 256)
			imgui.Image({_TexID = id}, {width, width * size.y / size.x})
		}
	}
}

@(private = "file")
drawSettingsPanel :: proc(graphicsData: ^GraphicsData) {
	defer imgui.End()
	visible := imgui.Begin("Settings")
	globals.uiData.settingsDockId = imgui.GetWindowDockID()
	if !visible {
		return
	}

	settings := &graphicsData.settings
	if ImRefl.draw_value("Render", settings^, {flags = {.Flatten}}) {
		settings.maxFrameLatency = clamp(settings.maxFrameLatency, 1, frameLatencyLimit())
		markCommandsDirty(graphicsData, {.Scene, .PostProcess})
	}

	if ImRefl.draw_value(
		"Gizmo radius",
		settings.lightGizmoRadius,
		{
			flags = {.Has_Min, .Has_Max, .Has_Speed} +
			(ImRefl.Draw_Flags{} if settings.showLightGizmos else {.Read_Only}),
			min = 0.01,
			max = 5,
			speed = 0.01,
		},
	) {
		markCommandsDirty(graphicsData, {.Scene})
	}

	if ImRefl.draw_value(
		"Gamma",
		settings.gamma,
		{
			flags = {.Has_Min, .Has_Speed} +
			(ImRefl.Draw_Flags{.Read_Only} if hdrActive(graphicsData) else {}),
			min = 0.1,
			speed = 0.01,
		},
	) {
		markCommandsDirty(graphicsData, {.PostProcess})
	}
	if hdrActive(graphicsData) {
		imgui.SetItemTooltip("Unused in HDR; the PQ transfer function replaces it.")
	}

	if ImRefl.draw_value(
		"Paper white (nits)",
		settings.paperWhiteNits,
		{
			flags = {.Has_Min, .Has_Max, .Has_Speed} +
			(ImRefl.Draw_Flags{} if hdrActive(graphicsData) else {.Read_Only}),
			min = 50,
			max = 1000,
			speed = 1,
		},
	) {
		markCommandsDirty(graphicsData, {.PostProcess})
	}

	available := hdrAvailable(graphicsData)
	hdr := hdrEnabled(graphicsData)
	imgui.BeginDisabled(!available)
	if imgui.Checkbox("HDR", &hdr) {
		setHDREnabled(graphicsData, hdr)
	}
	imgui.EndDisabled()
	if !available {
		imgui.SetItemTooltip("This surface offers no HDR10 format.")
	}
	imgui.SameLine()
	if !available {
		imgui.Text("(unavailable)")
	} else {
		imgui.Text(hdrActive(graphicsData) ? "(HDR10 PQ)" : "(sRGB)")
	}

	imgui.SeparatorText("Camera")
	ImRefl.draw_value("Camera", globals.settings.camera, {flags = {.Flatten}})
}

@(private = "file")
drawDebugPanel :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	if imgui.FindWindowByName("Debug") == nil && !uiData.debugDockRequested {
		return
	}
	defer imgui.End()
	if !imgui.Begin("Debug") {
		return
	}

	if imgui.BeginCombo("Image", toCstring(DEBUG_IMAGE_NAMES[uiData.debugImage])) {
		for kind in DebugImage {
			if !debugImageInfo(graphicsData, kind).previewable {
				continue
			}
			if imgui.Selectable(toCstring(DEBUG_IMAGE_NAMES[kind]), kind == uiData.debugImage) {
				uiData.debugImage = kind
			}
		}
		imgui.EndCombo()
	}

	info := debugImageInfo(graphicsData, uiData.debugImage)
	if info.layers == 0 {
		imgui.TextDisabled("This image does not exist right now.")
		return
	}

	layer: u32
	if uiData.debugImage == .ShadowColour || uiData.debugImage == .ShadowDepth {
		CUBE_FACE_NAMES :: [SHADOW_CUBE_FACES]cstring{"+X", "-X", "+Y", "-Y", "+Z", "-Z"}

		lights := globals.scenes[globals.activeScene].lights[:]
		lightCount := min(len(lights), int(info.layers) / SHADOW_CUBE_FACES)
		if lightCount == 0 {
			imgui.TextDisabled("The scene has no lights.")
			return
		}
		uiData.debugLight = clamp(uiData.debugLight, 0, lightCount - 1)
		uiData.debugFace = clamp(uiData.debugFace, 0, SHADOW_CUBE_FACES - 1)

		if imgui.BeginCombo("Light", fmt.ctprintf("%s##debuglight", lights[uiData.debugLight].name)) {
			for lightIdx in 0 ..< lightCount {
				label := fmt.ctprintf("%s##debuglight%v", lights[lightIdx].name, lightIdx)
				if imgui.Selectable(label, lightIdx == uiData.debugLight) {
					uiData.debugLight = lightIdx
				}
			}
			imgui.EndCombo()
		}

		faceNames := CUBE_FACE_NAMES
		if imgui.BeginCombo("Face", faceNames[uiData.debugFace]) {
			for face in 0 ..< SHADOW_CUBE_FACES {
				if imgui.Selectable(faceNames[face], face == uiData.debugFace) {
					uiData.debugFace = face
				}
			}
			imgui.EndCombo()
		}
		layer = u32(uiData.debugLight * SHADOW_CUBE_FACES + uiData.debugFace)
	}

	defaultRange := [2]f32{0, 1}
	if info.depth {
		defaultRange = {0.98, 1}
	} else if uiData.debugImage == .ShadowColour {
		defaultRange = {0, 30}
	}
	range := &uiData.debugRanges[uiData.debugImage]
	if range[0] == range[1] {
		range^ = defaultRange
	}
	imgui.DragFloatRange2("Range", &range[0], &range[1], 0.001)
	imgui.SameLine()
	if imgui.Button("Reset") {
		range^ = defaultRange
	}
	imgui.TextDisabled(fmt.ctprintf("%vx%v  %v", info.extent.width, info.extent.height, info.image.format))

	id, size, uvMax, ok := debugPreview(
		graphicsData,
		uiData.debugImage,
		layer,
		range[0],
		range[1],
	)
	if ok && size.x > 0 {
		width := imgui.GetContentRegionAvail().x
		imgui.Image({_TexID = id}, {width, width * size.y / size.x}, {0, 0}, uvMax)
	}
}

@(private = "file")
drawPopups :: proc(graphicsData: ^GraphicsData) {
	uiData := &globals.uiData
	if imgui.BeginPopupModal("New Scene") {
		createComponentInfo := &uiData.createComponentInfo
		imgui.Text("Name:")
		imgui.SameLine()
		imgui.InputText("##scenename", cstring(&createComponentInfo.name[0]), len(createComponentInfo.name))

		imgui.Text("Save Path:")
		imgui.SameLine()
		imgui.InputText("##savepath", cstring(&createComponentInfo.savePath[0]), len(createComponentInfo.savePath))
		imgui.SameLine()
		if imgui.Button("Browse##save") {
			absPath, _ := filepath.abs(SCENE_PATH(), context.temp_allocator)
			str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
			}
		}

		if imgui.Button("Create") {
			name := bufferText(&createComponentInfo.name)
			savePath := bufferText(&createComponentInfo.savePath)

			if name != "" && savePath != "" {
				path, oerr := os.replace_path_separators(
					savePath,
					'/',
					context.temp_allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				} else if newScene(name, path) {
					uiData.sceneFilesScanned = false
					clearComponentData(createComponentInfo)
					imgui.CloseCurrentPopup()
				}
			}
		}

		imgui.SameLine()
		if imgui.Button("Cancel") {
			imgui.CloseCurrentPopup()
			clearComponentData(createComponentInfo)
		}
		imgui.EndPopup()
	}

	if imgui.BeginPopupModal("New Model") {
		createComponentInfo := &uiData.createComponentInfo
		imgui.Text("Name:")
		imgui.SameLine()
		imgui.InputText("##texturename", cstring(&createComponentInfo.name[0]), 100)

		imgui.Text("Image Path:")
		imgui.SameLine()
		imgui.InputText("##texturepath", cstring(&createComponentInfo.assetPath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##texture") {
			absPath, _ := filepath.abs(ASSETS_PATH(), context.temp_allocator)
			str := tinyfd.openFileDialog(
				"Load Image",
				fmt.ctprintf("%s/", absPath),
				0,
				nil,
				nil,
				0,
			)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.assetPath, transmute([]byte)relPath)
			}
		}

		imgui.Text("Save Path:")
		imgui.SameLine()
		imgui.InputText("##savepath", cstring(&createComponentInfo.savePath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##save") {
			absPath, _ := filepath.abs(RESOURCE_PATH(), context.temp_allocator)
			str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
			}
		}

		if imgui.Button("Create") {
			scene := &globals.scenes[globals.activeScene]

			name, path, assetPath: string
			oerr: os.Error

			if createComponentInfo.name[0] != 0 &&
			   createComponentInfo.savePath[0] != 0 &&
			   createComponentInfo.assetPath[0] != 0 {
				name, oerr = os.replace_path_separators(
					string(createComponentInfo.name[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				path, oerr = os.replace_path_separators(
					string(createComponentInfo.savePath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				assetPath, oerr = os.replace_path_separators(
					string(createComponentInfo.assetPath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				append(&scene.models, Model{name = name, path = path, assetPath = assetPath})

				model := &scene.models[len(scene.models) - 1]
				model.rotation = IQUAT
				model.scale = {1, 1, 1}
				loadModel(scene, model)

				saveModelComponent(model)
				clearComponentData(createComponentInfo)
				imgui.CloseCurrentPopup()
			}
		}

		imgui.SameLine()
		if imgui.Button("Cancel") {
			imgui.CloseCurrentPopup()
			clearComponentData(createComponentInfo)
		}
		imgui.EndPopup()
	}

	if imgui.BeginPopupModal("New Texture") {
		createComponentInfo := &uiData.createComponentInfo
		imgui.Text("Name:")
		imgui.SameLine()
		imgui.InputText("##texturename", cstring(&createComponentInfo.name[0]), 100)

		imgui.Text("Image Path:")
		imgui.SameLine()
		imgui.InputText("##texturepath", cstring(&createComponentInfo.assetPath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##texture") {
			absPath, _ := filepath.abs(ASSETS_PATH(), context.temp_allocator)
			str := tinyfd.openFileDialog(
				"Load Image",
				fmt.ctprintf("%s/", absPath),
				0,
				nil,
				nil,
				0,
			)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.assetPath, transmute([]byte)relPath)
			}
		}

		imgui.Text("Save Path:")
		imgui.SameLine()
		imgui.InputText("##savepath", cstring(&createComponentInfo.savePath[0]), 100)
		imgui.SameLine()
		if imgui.Button("Browse##save") {
			absPath, _ := filepath.abs(RESOURCE_PATH(), context.temp_allocator)
			str := tinyfd.saveFileDialog("Save As", fmt.ctprintf("%s/", absPath), 0, nil, nil)
			if str != "" {
				relPath, err := filepath.rel(
					globals.projectDir,
					string(str),
					context.temp_allocator,
				)
				if err != nil {
					logf(
						.Error,
						"Failed to get relative path: %v\nBase: %v\nPath: %v",
						err,
						globals.projectDir,
						string(str),
					)
					relPath = string(str)
				}
				overwriteBuffer(&createComponentInfo.savePath, transmute([]byte)relPath)
			}
		}

		if imgui.Button("Create") {
			scene := &globals.scenes[globals.activeScene]

			name, path, assetPath: string
			oerr: os.Error

			if createComponentInfo.name[0] != 0 &&
			   createComponentInfo.savePath[0] != 0 &&
			   createComponentInfo.assetPath[0] != 0 {
				name, oerr = os.replace_path_separators(
					string(createComponentInfo.name[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				path, oerr = os.replace_path_separators(
					string(createComponentInfo.savePath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				assetPath, oerr = os.replace_path_separators(
					string(createComponentInfo.assetPath[:]),
					'/',
					context.allocator,
				)
				if oerr != nil {
					log(.Error, "Failed to replace path seperators!")
				}

				append(&scene.textures, Texture{name = name, path = path, assetPath = assetPath})

				texture := &scene.textures[len(scene.textures) - 1]

				saveTextureComponent(texture)
				clearComponentData(createComponentInfo)
				imgui.CloseCurrentPopup()
			}
		}

		imgui.SameLine()
		if imgui.Button("Cancel") {
			imgui.CloseCurrentPopup()
			clearComponentData(createComponentInfo)
		}
		imgui.EndPopup()
	}
}
