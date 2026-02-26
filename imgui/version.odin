package ImGui

CHECKVERSION :: proc() -> bool {
	return Gui_DebugCheckVersionAndDataLayout(
		IMGUI_VERSION,
		size_of(GuiIO),
		size_of(GuiStyle),
		size_of(Vec2),
		size_of(Vec4),
		size_of(DrawVert),
		size_of(DrawIdx)
	)
}