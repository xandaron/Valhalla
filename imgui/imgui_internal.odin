package imgui

import "core:c"

@(private="file") ARCH :: "x64" when ODIN_ARCH == .amd64 else "arm64"

when ODIN_OS == .Windows {
	foreign import lib { "imgui_windows_" + ARCH + ".lib" }
} else when ODIN_OS == .Linux {
	foreign import lib {
		"imgui_linux_" + ARCH + ".a",
		"system:c++",
	}
} else when ODIN_OS == .Darwin {
	foreign import lib {
		"imgui_darwin_" + ARCH + ".a",
		"system:c++",
	}
} else when ODIN_OS == .JS {
	foreign import lib "wasm/c_imgui_internal.o"
}

////////////////////////////////////////////////////////////
// DEFINES
////////////////////////////////////////////////////////////

DRAWLIST_ARCFAST_TABLE_SIZE :: 48 // Number of samples in lookup table.

////////////////////////////////////////////////////////////
// ENUMS
////////////////////////////////////////////////////////////

// Status flags for an already submitted item
// - output: stored in g.LastItemData.StatusFlags
ItemStatusFlags :: bit_set[ItemStatusFlag; c.int]
ItemStatusFlag :: enum c.int {
	HoveredRect      = 0,  // Mouse position is within item rectangle (does NOT mean that the window is in correct z-order and can be hovered!, this is only one part of the most-common IsItemHovered test)
	HasDisplayRect   = 1,  // g.LastItemData.DisplayRect is valid
	Edited           = 2,  // Value exposed by item was edited in the current frame (should match the bool return value of most widgets)
	ToggledSelection = 3,  // Set when Selectable(), TreeNode() reports toggling a selection. We can't report "Selected", only state changes, in order to easily handle clipping with less issues.
	ToggledOpen      = 4,  // Set when TreeNode() reports toggling their open state.
	HasDeactivated   = 5,  // Set if the widget/group is able to provide data for the ImGuiItemStatusFlags_Deactivated flag.
	Deactivated      = 6,  // Only valid if ImGuiItemStatusFlags_HasDeactivated is set.
	HoveredWindow    = 7,  // Override the HoveredWindow test to allow cross-window hover testing.
	Visible          = 8,  // [WIP] Set when item is overlapping the current clipping rectangle (Used internally. Please don't use yet: API/system will change as we refactor Itemadd()).
	HasClipRect      = 9,  // g.LastItemData.ClipRect is valid.
	HasShortcut      = 10, // g.LastItemData.Shortcut valid. Set by SetNextItemShortcut() -> ItemAdd().
}


// Extend ImGuiInputTextFlags_
InputTextFlagsPrivate :: enum c.int {
	// [Internal]
	ImGuiInputTextFlags_Multiline = 67108864,             // For internal use by InputTextMultiline()
	ImGuiInputTextFlags_MergedItem = 134217728,           // For internal use by TempInputText(), will skip calling ItemAdd(). Require bounding-box to strictly match.
	ImGuiInputTextFlags_LocalizeDecimalPoint = 268435456, // For internal use by InputScalar() and TempInputScalar()
}

// Extend ImGuiComboFlags_
ComboFlagsPrivate :: enum c.int {
	ImGuiComboFlags_CustomPreview = 1048576, // enable BeginComboPreview()
}

// Extend ImGuiSliderFlags_
SliderFlagsPrivate :: enum c.int {
	ImGuiSliderFlags_Vertical = 1048576, // Should this slider be orientated vertically?
	ImGuiSliderFlags_ReadOnly = 2097152, // Consider using g.NextItemData.ItemFlags |= ImGuiItemFlags_ReadOnly instead.
}

// Extend ImGuiSelectableFlags_
SelectableFlagsPrivate :: enum c.int {
	// NB: need to be in sync with last value of ImGuiSelectableFlags_
	ImGuiSelectableFlags_NoHoldingActiveID = 1048576,
	ImGuiSelectableFlags_SelectOnNav = 2097152,           // (WIP) Auto-select when moved into. This is not exposed in public API as to handle multi-select and modifiers we will need user to explicitly control focus scope. May be replaced with a BeginSelection() API.
	ImGuiSelectableFlags_SelectOnClick = 4194304,         // Override button behavior to react on Click (default is Click+Release)
	ImGuiSelectableFlags_SelectOnRelease = 8388608,       // Override button behavior to react on Release (default is Click+Release)
	ImGuiSelectableFlags_SpanAvailWidth = 16777216,       // Span all avail width even if we declared less for layout purpose. FIXME: We may be able to remove this (added in 6251d379, 2bcafc86 for menus)
	ImGuiSelectableFlags_SetNavIdOnHover = 33554432,      // Set Nav/Focus ID on mouse hover (used by MenuItem)
	ImGuiSelectableFlags_NoPadWithHalfSpacing = 67108864, // Disable padding each side with ItemSpacing * 0.5f
	ImGuiSelectableFlags_NoSetKeyOwner = 134217728,       // Don't set key/input owner on the initial click (note: mouse buttons are keys! often, the key in question will be ImGuiKey_MouseLeft!)
}

SeparatorFlags :: bit_set[SeparatorFlag; c.int]
SeparatorFlag :: enum c.int {
	Horizontal     = 0, // Axis default to current layout type, so generally Horizontal unless e.g. in a menu bar
	Vertical       = 1,
	SpanAllColumns = 2, // Make separator cover all columns of a legacy Columns() set.
}


// Flags for FocusWindow(). This is not called ImGuiFocusFlags to avoid confusion with public-facing ImGuiFocusedFlags.
// FIXME: Once we finishing replacing more uses of GetTopMostPopupModal()+IsWindowWithinBeginStackOf()
// and FindBlockingModal() with this, we may want to change the flag to be opt-out instead of opt-in.
FocusRequestFlags :: bit_set[FocusRequestFlag; c.int]
FocusRequestFlag :: enum c.int {
	RestoreFocusedChild = 0, // Find last focused child (if any) and focus it instead.
	UnlessBelowModal    = 1, // Do not set focus if the window is below a modal.
}


TextFlags :: bit_set[TextFlag; c.int]
TextFlag :: enum c.int {
	NoWidthForLargeClippedText = 0,
}


TooltipFlags :: bit_set[TooltipFlag; c.int]
TooltipFlag :: enum c.int {
	OverridePrevious = 1, // Clear/ignore previously submitted tooltip (defaults to append)
}


// FIXME: this is in development, not exposed/functional as a generic feature yet.
// Horizontal/Vertical enums are fixed to 0/1 so they may be used to index ImVec2
LayoutType :: enum c.int {
	Horizontal,
	Vertical,
}

// Flags for LogBegin() text capturing function
LogFlags :: bit_set[LogFlag; c.int]
LogFlag :: enum c.int {
	OutputTTY       = 0,
	OutputFile      = 1,
	OutputBuffer    = 2,
	OutputClipboard = 3,
}

LogFlags_OutputMask_ :: LogFlags{.OutputTTY,.OutputFile,.OutputBuffer,.OutputClipboard}

// X/Y enums are fixed to 0/1 so they may be used to index ImVec2
Axis :: enum c.int {
	None = -1,
	X,
	Y,
}

PlotType :: enum c.int {
	Lines,
	Histogram,
}

WindowRefreshFlags :: bit_set[WindowRefreshFlag; c.int]
WindowRefreshFlag :: enum c.int {
	TryToAvoidRefresh = 0, // [EXPERIMENTAL] Try to keep existing contents, USER MUST NOT HONOR BEGIN() RETURNING FALSE AND NOT APPEND.
	RefreshOnHover    = 1, // [EXPERIMENTAL] Always refresh on hover
	RefreshOnFocus    = 2, // [EXPERIMENTAL] Always refresh on focus
}


NextWindowDataFlags :: bit_set[NextWindowDataFlag; c.int]
NextWindowDataFlag :: enum c.int {
	HasPos            = 0,
	HasSize           = 1,
	HasContentSize    = 2,
	HasCollapsed      = 3,
	HasSizeConstraint = 4,
	HasFocus          = 5,
	HasBgAlpha        = 6,
	HasScroll         = 7,
	HasChildFlags     = 8,
	HasRefreshPolicy  = 9,
	HasViewport       = 10,
	HasDock           = 11,
	HasWindowClass    = 12,
}


NextItemDataFlags :: bit_set[NextItemDataFlag; c.int]
NextItemDataFlag :: enum c.int {
	HasWidth     = 0,
	HasOpen      = 1,
	HasShortcut  = 2,
	HasRefVal    = 3,
	HasStorageID = 4,
}


PopupPositionPolicy :: enum c.int {
	Default,
	ComboBox,
	Tooltip,
}

InputEventType :: enum c.int {
	None,
	MousePos,
	MouseWheel,
	MouseButton,
	MouseViewport,
	Key,
	Text,
	Focus,
	COUNT,
}

InputSource :: enum c.int {
	None,
	Mouse,    // Note: may be Mouse or TouchScreen or Pen. See io.MouseSource to distinguish them.
	Keyboard,
	Gamepad,
	COUNT,
}

ActivateFlags :: bit_set[ActivateFlag; c.int]
ActivateFlag :: enum c.int {
	PreferInput        = 0, // Favor activation that requires keyboard text input (e.g. for Slider/Drag). Default for Enter key.
	PreferTweak        = 1, // Favor activation for tweaking with arrows or gamepad (e.g. for Slider/Drag). Default for Space key and if keyboard is not used.
	TryToPreserveState = 2, // Request widget to preserve state if it can (e.g. InputText will try to preserve cursor/selection)
	FromTabbing        = 3, // Activation requested by a tabbing request
	FromShortcut       = 4, // Activation requested by an item shortcut via SetNextItemShortcut() function.
}


// Early work-in-progress API for ScrollToItem()
ScrollFlags :: bit_set[ScrollFlag; c.int]
ScrollFlag :: enum c.int {
	KeepVisibleEdgeX   = 0, // If item is not visible: scroll as little as possible on X axis to bring item back into view [default for X axis]
	KeepVisibleEdgeY   = 1, // If item is not visible: scroll as little as possible on Y axis to bring item back into view [default for Y axis for windows that are already visible]
	KeepVisibleCenterX = 2, // If item is not visible: scroll to make the item centered on X axis [rarely used]
	KeepVisibleCenterY = 3, // If item is not visible: scroll to make the item centered on Y axis
	AlwaysCenterX      = 4, // Always center the result item on X axis [rarely used]
	AlwaysCenterY      = 5, // Always center the result item on Y axis [default for Y axis for appearing window)
	NoScrollParent     = 6, // Disable forwarding scrolling to parent window if required to keep item/rect visible (only scroll window the function was applied to).
}

ScrollFlags_MaskX_ :: ScrollFlags{.KeepVisibleEdgeX,.KeepVisibleCenterX,.AlwaysCenterX}
ScrollFlags_MaskY_ :: ScrollFlags{.KeepVisibleEdgeY,.KeepVisibleCenterY,.AlwaysCenterY}

NavRenderCursorFlags :: bit_set[NavRenderCursorFlag; c.int]
NavRenderCursorFlag :: enum c.int {
	Compact    = 1, // Compact highlight, no padding/distance from focused item
	AlwaysDraw = 2, // Draw rectangular highlight if (g.NavId == id) even when g.NavCursorVisible == false, aka even when using the mouse.
	NoRounding = 3,
}


NavMoveFlags :: bit_set[NavMoveFlag; c.int]
NavMoveFlag :: enum c.int {
	LoopX                 = 0,  // On failed request, restart from opposite side
	LoopY                 = 1,
	WrapX                 = 2,  // On failed request, request from opposite side one line down (when NavDir==right) or one line up (when NavDir==left)
	WrapY                 = 3,  // This is not super useful but provided for completeness
	AllowCurrentNavId     = 4,  // Allow scoring and considering the current NavId as a move target candidate. This is used when the move source is offset (e.g. pressing PageDown actually needs to send a Up move request, if we are pressing PageDown from the bottom-most item we need to stay in place)
	AlsoScoreVisibleSet   = 5,  // Store alternate result in NavMoveResultLocalVisible that only comprise elements that are already fully visible (used by PageUp/PageDown)
	ScrollToEdgeY         = 6,  // Force scrolling to min/max (used by Home/End) // FIXME-NAV: Aim to remove or reword, probably unnecessary
	Forwarded             = 7,
	DebugNoResult         = 8,  // Dummy scoring for debug purpose, don't apply result
	FocusApi              = 9,  // Requests from focus API can land/focus/activate items even if they are marked with _NoTabStop (see NavProcessItemForTabbingRequest() for details)
	IsTabbing             = 10, // == Focus + Activate if item is Inputable + DontChangeNavHighlight
	IsPageMove            = 11, // Identify a PageDown/PageUp request.
	Activate              = 12, // Activate/select target item.
	NoSelect              = 13, // Don't trigger selection by not setting g.NavJustMovedTo
	NoSetNavCursorVisible = 14, // Do not alter the nav cursor visible state
	NoClearActiveId       = 15, // (Experimental) Do not clear active id when applying move result
}

NavMoveFlags_WrapMask_ :: NavMoveFlags{.LoopX,.LoopY,.WrapX,.WrapY}

NavLayer :: enum c.int {
	Main,  // Main scrolling layer
	Menu,  // Menu layer (access with Alt)
	COUNT,
}

// Flags for GetTypingSelectRequest()
TypingSelectFlags :: distinct c.int
TypingSelectFlags_None                :: TypingSelectFlags(0)
TypingSelectFlags_AllowBackspace      :: TypingSelectFlags(1<<0) // Backspace to delete character inputs. If using: ensure GetTypingSelectRequest() is not called more than once per frame (filter by e.g. focus state)
TypingSelectFlags_AllowSingleCharMode :: TypingSelectFlags(1<<1) // Allow "single char" search mode which is activated when pressing the same character multiple times.

// Flags for internal's BeginColumns(). This is an obsolete API. Prefer using BeginTable() nowadays!
OldColumnFlags :: bit_set[OldColumnFlag; c.int]
OldColumnFlag :: enum c.int {
	NoBorder               = 0, // Disable column dividers
	NoResize               = 1, // Disable resizing columns when clicking on the dividers
	NoPreserveWidths       = 2, // Disable column width preservation when adjusting columns
	NoForceWithinWindow    = 3, // Disable forcing columns to fit within window
	GrowParentContentsSize = 4, // Restore pre-1.51 behavior of extending the parent window contents size but _without affecting the columns width at all_. Will eventually remove.
}


// Store the source authority (dock node vs window) of a field
DataAuthority :: enum c.int {
	Auto,
	DockNode,
	Window,
}

DockNodeState :: enum c.int {
	Unknown,
	HostWindowHiddenBecauseSingleWindow,
	HostWindowHiddenBecauseWindowsAreResizing,
	HostWindowVisible,
}

// List of colors that are stored at the time of Begin() into Docked Windows.
// We currently store the packed colors in a simple array window->DockStyle.Colors[].
// A better solution may involve appending into a log of colors in ImGuiContext + store offsets into those arrays in ImGuiWindow,
// but it would be more complex as we'd need to double-buffer both as e.g. drop target may refer to window from last frame.
WindowDockStyleCol :: enum c.int {
	Text,
	TabHovered,
	TabFocused,
	TabSelected,
	TabSelectedOverline,
	TabDimmed,
	TabDimmedSelected,
	TabDimmedSelectedOverline,
	COUNT,
}

// This is experimental and not officially supported, it'll probably fall short of features, if/when it does we may backtrack.
LocKey :: enum c.int { // Forward declared enum type ImGuiLocKey
	VersionStr,
	TableSizeOne,
	TableSizeAllFit,
	TableSizeAllDefault,
	TableResetOrder,
	WindowingMainMenuBar,
	WindowingPopup,
	WindowingUntitled,
	OpenLink_s,
	CopyLink,
	DockingHideTabBar,
	DockingHoldShiftToDock,
	DockingDragToUndockOrMoveNode,
	COUNT,
}

// See IMGUI_DEBUG_LOG() and IMGUI_DEBUG_LOG_XXX() macros.
DebugLogFlags :: bit_set[DebugLogFlag; c.int]
DebugLogFlag :: enum c.int {
	EventError         = 0,  // Error submitted by IM_ASSERT_USER_ERROR()
	EventActiveId      = 1,
	EventFocus         = 2,
	EventPopup         = 3,
	EventNav           = 4,
	EventClipper       = 5,
	EventSelection     = 6,
	EventIO            = 7,
	EventFont          = 8,
	EventInputRouting  = 9,
	EventDocking       = 10,
	EventViewport      = 11,
	OutputToTTY        = 20, // Also send output to TTY
	OutputToTestEngine = 21, // Also send output to Test Engine
}

DebugLogFlags_EventMask_ :: DebugLogFlags{.EventError,.EventActiveId,.EventFocus,.EventPopup,.EventNav,.EventClipper,.EventSelection,.EventIO,.EventFont,.EventInputRouting,.EventDocking,.EventViewport}

ContextHookType :: enum c.int {
	NewFramePre,
	NewFramePost,
	EndFramePre,
	EndFramePost,
	RenderPre,
	RenderPost,
	Shutdown,
	PendingRemoval_,
}

// Extend ImGuiTabBarFlags_
TabBarFlagsPrivate :: enum c.int {
	ImGuiTabBarFlags_DockNode = 1048576,     // Part of a dock node [we don't use this in the master branch but it facilitate branch syncing to keep this around]
	ImGuiTabBarFlags_IsFocused = 2097152,
	ImGuiTabBarFlags_SaveSettings = 4194304, // FIXME: Settings are handled by the docking system, this only request the tab bar to mark settings dirty when reordering tabs
}


////////////////////////////////////////////////////////////
// STRUCTS
////////////////////////////////////////////////////////////

DockRequest :: struct { // Docking system dock/undock queued request
}

DockNodeSettings :: struct { // Storage for a dock node in .ini file (we preserve those even if the associated dock node isn't active during the session)
}

InputTextDeactivateData :: struct { // Short term storage to backup text of a deactivating InputText() while another is stealing active id
}

TableColumnsSettings :: struct { // Storage for a column .ini settings
}

Vec1 :: struct {
	x: f32,
}

// Helper: ImVec2ih (2D vector, half-size integer, for long-term packed storage)
Vec2ih :: struct {
	x: c.short,
	y: c.short,
}

// Helper: ImRect (2D axis aligned bounding-box)
// NB: we can't rely on ImVec2 math operators being available here!
Rect :: struct {
	Min: Vec2, // Upper-left
	Max: Vec2, // Lower-right
}

// Helper: ImBitVector
// Store 1-bit per value.
BitVector :: struct {
	Storage: Vector_U32,
}

// Instantiation of ImSpan<ImGuiTableColumn>
Span_ImGuiTableColumn :: struct {
	Data:    ^TableColumn,
	DataEnd: ^TableColumn,
}

// Instantiation of ImSpan<ImGuiTableColumnIdx>
Span_ImGuiTableColumnIdx :: struct {
	Data:    ^TableColumnIdx,
	DataEnd: ^TableColumnIdx,
}

// Instantiation of ImSpan<ImGuiTableCellData>
Span_ImGuiTableCellData :: struct {
	Data:    ^TableCellData,
	DataEnd: ^TableCellData,
}

// Data shared between all ImDrawList instances
// Conceptually this could have been called e.g. ImDrawListSharedContext
// Typically one ImGui context would create and maintain one of this.
// You may want to create your own instance of you try to ImDrawList completely without ImGui. In that case, watch out for future changes to this structure.
DrawListSharedData :: struct {
	TexUvWhitePixel:       Vec2,          // UV of white pixel in the atlas
	TexUvLines:            ^Vec4,         // UV of anti-aliased lines in the atlas
	Font_:                 ^Font,         // Current/default font (optional, for simplified AddText overload)
	FontSize:              f32,           // Current/default font size (optional, for simplified AddText overload)
	FontScale:             f32,           // Current/default font scale (== FontSize / Font->FontSize)
	CurveTessellationTol:  f32,           // Tessellation tolerance when using PathBezierCurveTo()
	CircleSegmentMaxError: f32,           // Number of circle segments to use per pixel of radius for AddCircle() etc
	ClipRectFullscreen:    Vec4,          // Value for PushClipRectFullscreen()
	InitialFlags:          DrawListFlags, // Initial flags at the beginning of the frame (it is possible to alter flags on a per-drawlist basis afterwards)
	TempBuffer:            Vector_Vec2,   // Temporary write buffer
	// Lookup tables
	ArcFastVtx:          [DRAWLIST_ARCFAST_TABLE_SIZE]Vec2, // Sample points on the quarter of the circle.
	ArcFastRadiusCutoff: f32,                               // Cutoff radius after which arc drawing will fallback to slower PathArcTo()
	CircleSegmentCounts: [64]u8,                            // Precomputed segment count for given radius before we calculate it dynamically (to avoid calculation overhead)
}

DrawDataBuilder :: struct {
	Layers:     [2]^Vector_DrawListPtr, // Pointers to global layers for: regular, tooltip. LayersP[0] is owned by DrawData.
	LayerData1: Vector_DrawListPtr,
}

DataVarInfo :: struct {
	Type:   DataType,
	Count:  u32,      // 1+
	Offset: u32,      // Offset in parent structure
}

DataTypeStorage :: struct {
	Data: [8]u8, // Opaque storage to fit any data up to ImGuiDataType_COUNT
}

// Type information associated to one ImGuiDataType. Retrieve with DataTypeGetInfo().
DataTypeInfo :: struct {
	Size:     c.size_t, // Size in bytes
	Name:     cstring,  // Short descriptive name for the type, for debugging
	PrintFmt: cstring,  // Default printf format for the type
	ScanFmt:  cstring,  // Default scanf format for the type
}

// Instantiation of ImChunkStream<ImGuiTableSettings>
ChunkStream_ImGuiTableSettings :: struct {
	Buf: Vector_char,
}

// Instantiation of ImChunkStream<ImGuiWindowSettings>
ChunkStream_ImGuiWindowSettings :: struct {
	Buf: Vector_char,
}

Vector_unsigned_char :: struct { // Instantiation of ImVector<unsigned char>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^c.uchar,
}

Vector_WindowStackData :: struct { // Instantiation of ImVector<ImGuiWindowStackData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^WindowStackData,
}

Vector_WindowPtr :: struct { // Instantiation of ImVector<ImGuiWindow*>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^^Window,
}

Vector_ViewportPPtr :: struct { // Instantiation of ImVector<ImGuiViewportP*>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^^ViewportP,
}

Vector_TreeNodeStackData :: struct { // Instantiation of ImVector<ImGuiTreeNodeStackData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TreeNodeStackData,
}

Vector_TableTempData :: struct { // Instantiation of ImVector<ImGuiTableTempData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TableTempData,
}

Vector_TableInstanceData :: struct { // Instantiation of ImVector<ImGuiTableInstanceData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TableInstanceData,
}

Vector_TableHeaderData :: struct { // Instantiation of ImVector<ImGuiTableHeaderData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TableHeaderData,
}

Vector_TableColumnSortSpecs :: struct { // Instantiation of ImVector<ImGuiTableColumnSortSpecs>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TableColumnSortSpecs,
}

Vector_Table :: struct { // Instantiation of ImVector<ImGuiTable>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^Table,
}

Vector_TabItem :: struct { // Instantiation of ImVector<ImGuiTabItem>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TabItem,
}

Vector_TabBar :: struct { // Instantiation of ImVector<ImGuiTabBar>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TabBar,
}

Vector_StyleMod :: struct { // Instantiation of ImVector<ImGuiStyleMod>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^StyleMod,
}

Vector_StackLevelInfo :: struct { // Instantiation of ImVector<ImGuiStackLevelInfo>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^StackLevelInfo,
}

Vector_ShrinkWidthItem :: struct { // Instantiation of ImVector<ImGuiShrinkWidthItem>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^ShrinkWidthItem,
}

Vector_SettingsHandler :: struct { // Instantiation of ImVector<ImGuiSettingsHandler>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^SettingsHandler,
}

Vector_PtrOrIndex :: struct { // Instantiation of ImVector<ImGuiPtrOrIndex>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^PtrOrIndex,
}

Vector_PopupData :: struct { // Instantiation of ImVector<ImGuiPopupData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^PopupData,
}

Vector_OldColumns :: struct { // Instantiation of ImVector<ImGuiOldColumns>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^OldColumns,
}

Vector_OldColumnData :: struct { // Instantiation of ImVector<ImGuiOldColumnData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^OldColumnData,
}

Vector_MultiSelectTempData :: struct { // Instantiation of ImVector<ImGuiMultiSelectTempData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^MultiSelectTempData,
}

Vector_MultiSelectState :: struct { // Instantiation of ImVector<ImGuiMultiSelectState>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^MultiSelectState,
}

Vector_ListClipperRange :: struct { // Instantiation of ImVector<ImGuiListClipperRange>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^ListClipperRange,
}

Vector_ListClipperData :: struct { // Instantiation of ImVector<ImGuiListClipperData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^ListClipperData,
}

Vector_KeyRoutingData :: struct { // Instantiation of ImVector<ImGuiKeyRoutingData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^KeyRoutingData,
}

Vector_ItemFlags :: struct { // Instantiation of ImVector<ImGuiItemFlags>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^ItemFlags,
}

Vector_InputEvent :: struct { // Instantiation of ImVector<ImGuiInputEvent>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^InputEvent,
}

Vector_ID :: struct { // Instantiation of ImVector<ImGuiID>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^ID,
}

Vector_GroupData :: struct { // Instantiation of ImVector<ImGuiGroupData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^GroupData,
}

Vector_FocusScopeData :: struct { // Instantiation of ImVector<ImGuiFocusScopeData>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^FocusScopeData,
}

Vector_DockRequest :: struct { // Instantiation of ImVector<ImGuiDockRequest>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^DockRequest,
}

Vector_DockNodeSettings :: struct { // Instantiation of ImVector<ImGuiDockNodeSettings>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^DockNodeSettings,
}

Vector_ContextHook :: struct { // Instantiation of ImVector<ImGuiContextHook>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^ContextHook,
}

Vector_ColorMod :: struct { // Instantiation of ImVector<ImGuiColorMod>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^ColorMod,
}

Vector_const_charPtr :: struct { // Instantiation of ImVector<const char*>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^cstring,
}

Vector_int :: struct { // Instantiation of ImVector<int>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^c.int,
}

// Instantiation of ImPool<ImGuiMultiSelectState>
Pool_ImGuiMultiSelectState :: struct {
	Buf:        Vector_MultiSelectState, // Contiguous data
	Map:        Storage,                 // ID->Index
	FreeIdx:    PoolIdx,                 // Next free idx to use
	AliveCount: PoolIdx,                 // Number of active/alive items (for display purpose)
}

// Instantiation of ImPool<ImGuiTabBar>
Pool_ImGuiTabBar :: struct {
	Buf:        Vector_TabBar, // Contiguous data
	Map:        Storage,       // ID->Index
	FreeIdx:    PoolIdx,       // Next free idx to use
	AliveCount: PoolIdx,       // Number of active/alive items (for display purpose)
}

// Instantiation of ImPool<ImGuiTable>
Pool_ImGuiTable :: struct {
	Buf:        Vector_Table, // Contiguous data
	Map:        Storage,      // ID->Index
	FreeIdx:    PoolIdx,      // Next free idx to use
	AliveCount: PoolIdx,      // Number of active/alive items (for display purpose)
}

// Helper: ImGuiTextIndex
// Maintain a line index for a text buffer. This is a strong candidate to be moved into the public API.
TextIndex :: struct {
	LineOffsets: Vector_int,
	EndOffset:   c.int,      // Because we don't own text buffer we need to maintain EndOffset (may bake in LineOffsets?)
}

// Stacked color modifier, backup of modified data so we can restore it
ColorMod :: struct {
	Col:         Col,
	BackupValue: Vec4,
}

// Stacked style modifier, backup of modified data so we can restore it. Data type inferred from the variable.
StyleMod :: struct {
	VarIdx:            StyleVar,
	__anonymous_type1: __anonymous_type1,
}

__anonymous_type1 :: struct {
	BackupInt:   [2]c.int,
	BackupFloat: [2]f32,
}

// Storage data for BeginComboPreview()/EndComboPreview()
ComboPreviewData :: struct {
	PreviewRect:                  Rect,
	BackupCursorPos:              Vec2,
	BackupCursorMaxPos:           Vec2,
	BackupCursorPosPrevLine:      Vec2,
	BackupPrevLineTextBaseOffset: f32,
	BackupLayout:                 LayoutType,
}

// Stacked storage data for BeginGroup()/EndGroup()
GroupData :: struct {
	WindowID:                     ID,
	BackupCursorPos:              Vec2,
	BackupCursorMaxPos:           Vec2,
	BackupCursorPosPrevLine:      Vec2,
	BackupIndent:                 Vec1,
	BackupGroupOffset:            Vec1,
	BackupCurrLineSize:           Vec2,
	BackupCurrLineTextBaseOffset: f32,
	BackupActiveIdIsAlive:        ID,
	BackupDeactivatedIdIsAlive:   bool,
	BackupHoveredIdIsAlive:       bool,
	BackupIsSameLine:             bool,
	EmitItem:                     bool,
}

// Simple column measurement, currently used for MenuItem() only.. This is very short-sighted/throw-away code and NOT a generic helper.
MenuColumns :: struct {
	TotalWidth:     u32,
	NextTotalWidth: u32,
	Spacing:        u16,
	OffsetIcon:     u16,    // Always zero for now
	OffsetLabel:    u16,    // Offsets are locked in Update()
	OffsetShortcut: u16,
	OffsetMark:     u16,
	Widths:         [4]u16, // Width of:   Icon, Label, Shortcut, Mark  (accumulators for current frame)
}

// Internal temporary state for deactivating InputText() instances.
InputTextDeactivatedState :: struct {
	ID_:   ID,          // widget id owning the text state (which just got deactivated)
	TextA: Vector_char, // text buffer
}

Stb_STB_TexteditState :: struct {
}

// Internal state of the currently focused/edited text input box
// For a given item ID, access with ImGui::GetInputTextState()
InputTextState :: struct {
	Ctx:                  ^Context,       // parent UI context (needs to be set explicitly by parent).
	Stb:                  rawptr,         // State for stb_textedit.h
	Flags:                InputTextFlags, // copy of InputText() flags. may be used to check if e.g. ImGuiInputTextFlags_Password is set.
	ID_:                  ID,             // widget id owning the text state
	TextLen:              c.int,          // UTF-8 length of the string in TextA (in bytes)
	TextSrc:              cstring,        // == TextA.Data unless read-only, in which case == buf passed to InputText(). Field only set and valid _inside_ the call InputText() call.
	TextA:                Vector_char,    // main UTF8 buffer. TextA.Size is a buffer size! Should always be >= buf_size passed by user (and of course >= CurLenA + 1).
	TextToRevertTo:       Vector_char,    // value to revert to when pressing Escape = backup of end-user buffer at the time of focus (in UTF-8, unaltered)
	CallbackTextBackup:   Vector_char,    // temporary storage for callback to support automatic reconcile of undo-stack
	BufCapacity:          c.int,          // end-user buffer capacity (include zero terminator)
	Scroll:               Vec2,           // horizontal offset (managed manually) + vertical scrolling (pulled from child window's own Scroll.y)
	CursorAnim:           f32,            // timer for cursor blink, reset on every user action so the cursor reappears immediately
	CursorFollow:         bool,           // set when we want scrolling to follow the current cursor position (not always!)
	SelectedAllMouseLock: bool,           // after a double-click to select all, we ignore further mouse drags to update selection
	Edited:               bool,           // edited this frame
	WantReloadUserBuf:    bool,           // force a reload of user buf so it may be modified externally. may be automatic in future version.
	ReloadSelectionStart: c.int,
	ReloadSelectionEnd:   c.int,
}

// Storage for SetNexWindow** functions
NextWindowData :: struct {
	Flags:                NextWindowDataFlags,
	PosCond:              Cond,
	SizeCond:             Cond,
	CollapsedCond:        Cond,
	DockCond:             Cond,
	PosVal:               Vec2,
	PosPivotVal:          Vec2,
	SizeVal:              Vec2,
	ContentSizeVal:       Vec2,
	ScrollVal:            Vec2,
	ChildFlags:           ChildFlags,
	PosUndock:            bool,
	CollapsedVal:         bool,
	SizeConstraintRect:   Rect,
	SizeCallback:         SizeCallback,
	SizeCallbackUserData: rawptr,
	BgAlphaVal:           f32,                 // Override background alpha
	ViewportId:           ID,
	DockId:               ID,
	WindowClass:          WindowClass,
	MenuBarOffsetMinVal:  Vec2,                // (Always on) This is not exposed publicly, so we don't clear it and it doesn't have a corresponding flag (could we? for consistency?)
	RefreshFlagsVal:      WindowRefreshFlags,
}

NextItemData :: struct {
	HasFlags:  NextItemDataFlags, // Called HasFlags instead of Flags to avoid mistaking this
	ItemFlags: ItemFlags,         // Currently only tested/used for ImGuiItemFlags_AllowOverlap and ImGuiItemFlags_HasSelectionUserData.
	// Non-flags members are NOT cleared by ItemAdd() meaning they are still valid during NavProcessItem()
	FocusScopeId:      ID,                // Set by SetNextItemSelectionUserData()
	SelectionUserData: SelectionUserData, // Set by SetNextItemSelectionUserData() (note that NULL/0 is a valid value, we use -1 == ImGuiSelectionUserData_Invalid to mark invalid values)
	Width:             f32,               // Set by SetNextItemWidth()
	Shortcut:          KeyChord,          // Set by SetNextItemShortcut()
	ShortcutFlags:     InputFlags,        // Set by SetNextItemShortcut()
	OpenVal:           bool,              // Set by SetNextItemOpen()
	OpenCond:          u8,                // Set by SetNextItemOpen()
	RefVal:            DataTypeStorage,   // Not exposed yet, for ImGuiInputTextFlags_ParseEmptyAsRefVal
	StorageId:         ID,                // Set by SetNextItemStorageID()
}

// Status storage for the last submitted item
LastItemData :: struct {
	ID_:         ID,
	ItemFlags:   ItemFlags,       // See ImGuiItemFlags_ (called 'InFlags' before v1.91.4).
	StatusFlags: ItemStatusFlags, // See ImGuiItemStatusFlags_
	Rect_:       Rect,            // Full rectangle
	NavRect:     Rect,            // Navigation scoring rectangle (not displayed)
	// Rarely used fields are not explicitly cleared, only valid when the corresponding ImGuiItemStatusFlags are set.
	DisplayRect: Rect,     // Display rectangle. ONLY VALID IF (StatusFlags & ImGuiItemStatusFlags_HasDisplayRect) is set.
	ClipRect:    Rect,     // Clip rectangle at the time of submitting item. ONLY VALID IF (StatusFlags & ImGuiItemStatusFlags_HasClipRect) is set..
	Shortcut:    KeyChord, // Shortcut at the time of submitting item. ONLY VALID IF (StatusFlags & ImGuiItemStatusFlags_HasShortcut) is set..
}

// Store data emitted by TreeNode() for usage by TreePop()
// - To implement ImGuiTreeNodeFlags_NavLeftJumpsBackHere: store the minimum amount of data
//   which we can't infer in TreePop(), to perform the equivalent of NavApplyItemToResult().
//   Only stored when the node is a potential candidate for landing on a Left arrow jump.
TreeNodeStackData :: struct {
	ID_:       ID,
	TreeFlags: TreeNodeFlags,
	ItemFlags: ItemFlags,     // Used for nav landing
	NavRect:   Rect,          // Used for nav landing
}

// sizeof() = 20
ErrorRecoveryState :: struct {
	SizeOfWindowStack:     c.short,
	SizeOfIDStack:         c.short,
	SizeOfTreeStack:       c.short,
	SizeOfColorStack:      c.short,
	SizeOfStyleVarStack:   c.short,
	SizeOfFontStack:       c.short,
	SizeOfFocusScopeStack: c.short,
	SizeOfGroupStack:      c.short,
	SizeOfItemFlagsStack:  c.short,
	SizeOfBeginPopupStack: c.short,
	SizeOfDisabledStack:   c.short,
}

// Data saved for each window pushed into the stack
WindowStackData :: struct {
	Window_:                  ^Window,
	ParentLastItemDataBackup: LastItemData,
	StackSizesInBegin:        ErrorRecoveryState, // Store size of various stacks for asserting
	DisabledOverrideReenable: bool,               // Non-child window override disabled flag
}

ShrinkWidthItem :: struct {
	Index:        c.int,
	Width:        f32,
	InitialWidth: f32,
}

PtrOrIndex :: struct {
	Ptr:   rawptr, // Either field can be set, not both. e.g. Dock node tab bars are loose while BeginTabBar() ones are in a pool.
	Index: c.int,  // Usually index in a main pool.
}

// Data used by IsItemDeactivated()/IsItemDeactivatedAfterEdit() functions
DeactivatedItemData :: struct {
	ID_:                 ID,
	ElapseFrame:         c.int,
	HasBeenEditedBefore: bool,
	IsAlive:             bool,
}

// Storage for popup stacks (g.OpenPopupStack and g.BeginPopupStack)
PopupData :: struct {
	PopupId:          ID,      // Set on OpenPopup()
	Window_:          ^Window, // Resolved on BeginPopup() - may stay unresolved if user never calls OpenPopup()
	RestoreNavWindow: ^Window, // Set on OpenPopup(), a NavWindow that will be restored on popup close
	ParentNavLayer:   c.int,   // Resolved on BeginPopup(). Actually a ImGuiNavLayer type (declared down below), initialized to -1 which is not part of an enum, but serves well-enough as "not any of layers" value
	OpenFrameCount:   c.int,   // Set on OpenPopup()
	OpenParentId:     ID,      // Set on OpenPopup(), we need this to differentiate multiple menu sets from each others (e.g. inside menu bar vs loose menu items)
	OpenPopupPos:     Vec2,    // Set on OpenPopup(), preferred popup position (typically == OpenMousePos when using mouse)
	OpenMousePos:     Vec2,    // Set on OpenPopup(), copy of mouse position at the time of opening popup
}

BitArrayForNamedKeys :: struct {
	__dummy: [20]c.char,
}

// FIXME: Structures in the union below need to be declared as anonymous unions appears to be an extension?
// Using ImVec2() would fail on Clang 'union member 'MousePos' has a non-trivial default constructor'
InputEventMousePos :: struct {
	PosX:        f32,
	PosY:        f32,
	MouseSource: MouseSource,
}

InputEventMouseWheel :: struct {
	WheelX:      f32,
	WheelY:      f32,
	MouseSource: MouseSource,
}

InputEventMouseButton :: struct {
	Button:      c.int,
	Down:        bool,
	MouseSource: MouseSource,
}

InputEventMouseViewport :: struct {
	HoveredViewportID: ID,
}

InputEventKey :: struct {
	Key:         Key,
	Down:        bool,
	AnalogValue: f32,
}

InputEventText :: struct {
	Char: c.uint,
}

InputEventAppFocused :: struct {
	Focused: bool,
}

InputEvent :: struct {
	Type:              InputEventType,
	Source:            InputSource,
	EventId:           u32,               // Unique, sequential increasing integer to identify an event (if you need to correlate them to other data).
	__anonymous_type2: __anonymous_type2,
	AddedByTestEngine: bool,
}

__anonymous_type2 :: struct {
	MousePos:      InputEventMousePos,      // if Type == ImGuiInputEventType_MousePos
	MouseWheel:    InputEventMouseWheel,    // if Type == ImGuiInputEventType_MouseWheel
	MouseButton:   InputEventMouseButton,   // if Type == ImGuiInputEventType_MouseButton
	MouseViewport: InputEventMouseViewport, // if Type == ImGuiInputEventType_MouseViewport
	Key:           InputEventKey,           // if Type == ImGuiInputEventType_Key
	Text:          InputEventText,          // if Type == ImGuiInputEventType_Text
	AppFocused:    InputEventAppFocused,    // if Type == ImGuiInputEventType_Focus
}

// Routing table entry (sizeof() == 16 bytes)
KeyRoutingData :: struct {
	NextEntryIndex:   KeyRoutingIndex,
	Mods:             u16,             // Technically we'd only need 4-bits but for simplify we store ImGuiMod_ values which need 16-bits.
	RoutingCurrScore: u8,              // [DEBUG] For debug display
	RoutingNextScore: u8,              // Lower is better (0: perfect score)
	RoutingCurr:      ID,
	RoutingNext:      ID,
}

// Routing table: maintain a desired owner for each possible key-chord (key + mods), and setup owner in NewFrame() when mods are matching.
// Stored in main context (1 instance)
KeyRoutingTable :: struct {
	Index:       [Key.NamedKey_COUNT]KeyRoutingIndex, // Index of first entry in Entries[]
	Entries:     Vector_KeyRoutingData,
	EntriesNext: Vector_KeyRoutingData,               // Double-buffer to avoid reallocation (could use a shared buffer)
}

// This extends ImGuiKeyData but only for named keys (legacy keys don't support the new features)
// Stored in main context (1 per named key). In the future it might be merged into ImGuiKeyData.
KeyOwnerData :: struct {
	OwnerCurr:        ID,
	OwnerNext:        ID,
	LockThisFrame:    bool, // Reading this key requires explicit owner id (until end of frame). Set by ImGuiInputFlags_LockThisFrame.
	LockUntilRelease: bool, // Reading this key requires explicit owner id (until key is released). Set by ImGuiInputFlags_LockUntilRelease. When this is true LockThisFrame is always true as well.
}

// Note that Max is exclusive, so perhaps should be using a Begin/End convention.
ListClipperRange :: struct {
	Min:                 c.int,
	Max:                 c.int,
	PosToIndexConvert:   bool,  // Begin/End are absolute position (will be converted to indices later)
	PosToIndexOffsetMin: i8,    // Add to Min after converting to indices
	PosToIndexOffsetMax: i8,    // Add to Min after converting to indices
}

// Temporary clipper data, buffers shared/reused between instances
ListClipperData :: struct {
	ListClipper:     ^ListClipper,
	LossynessOffset: f32,
	StepNo:          c.int,
	ItemsFrozen:     c.int,
	Ranges:          Vector_ListClipperRange,
}

// Storage for navigation query/results
NavItemData :: struct {
	Window_:           ^Window,           // Init,Move    // Best candidate window (result->ItemWindow->RootWindowForNav == request->Window)
	ID_:               ID,                // Init,Move    // Best candidate item ID
	FocusScopeId:      ID,                // Init,Move    // Best candidate focus scope ID
	RectRel:           Rect,              // Init,Move    // Best candidate bounding box in window relative space
	ItemFlags:         ItemFlags,         // ????,Move    // Best candidate item flags
	DistBox:           f32,               //      Move    // Best candidate box distance to current NavId
	DistCenter:        f32,               //      Move    // Best candidate center distance to current NavId
	DistAxial:         f32,               //      Move    // Best candidate axial distance to current NavId
	SelectionUserData: SelectionUserData, //I+Mov    // Best candidate SetNextItemSelectionUserData() value. Valid if (ItemFlags & ImGuiItemFlags_HasSelectionUserData)
}

// Storage for PushFocusScope(), g.FocusScopeStack[], g.NavFocusRoute[]
FocusScopeData :: struct {
	ID_:      ID,
	WindowID: ID,
}

// Returned by GetTypingSelectRequest(), designed to eventually be public.
TypingSelectRequest :: struct {
	Flags:           TypingSelectFlags, // Flags passed to GetTypingSelectRequest()
	SearchBufferLen: c.int,
	SearchBuffer:    cstring,           // Search buffer contents (use full string. unless SingleCharMode is set, in which case use SingleCharSize).
	SelectRequest:   bool,              // Set when buffer was modified this frame, requesting a selection.
	SingleCharMode:  bool,              // Notify when buffer contains same character repeated, to implement special mode. In this situation it preferred to not display any on-screen search indication.
	SingleCharSize:  i8,                // Length in bytes of first letter codepoint (1 for ascii, 2-4 for UTF-8). If (SearchBufferLen==RepeatCharSize) only 1 letter has been input.
}

// Storage for GetTypingSelectRequest()
TypingSelectState :: struct {
	Request:            TypingSelectRequest, // User-facing data
	SearchBuffer:       [64]c.char,          // Search buffer: no need to make dynamic as this search is very transient.
	FocusScope:         ID,
	LastRequestFrame:   c.int,
	LastRequestTime:    f32,
	SingleCharModeLock: bool,                // After a certain single char repeat count we lock into SingleCharMode. Two benefits: 1) buffer never fill, 2) we can provide an immediate SingleChar mode without timer elapsing.
}

OldColumnData :: struct {
	OffsetNorm:             f32,            // Column start offset, normalized 0.0 (far left) -> 1.0 (far right)
	OffsetNormBeforeResize: f32,
	Flags:                  OldColumnFlags, // Not exposed
	ClipRect:               Rect,
}

OldColumns :: struct {
	ID_:                      ID,
	Flags:                    OldColumnFlags,
	IsFirstFrame:             bool,
	IsBeingResized:           bool,
	Current:                  c.int,
	Count:                    c.int,
	OffMinX:                  f32,                  // Offsets from HostWorkRect.Min.x
	OffMaxX:                  f32,                  // Offsets from HostWorkRect.Min.x
	LineMinY:                 f32,
	LineMaxY:                 f32,
	HostCursorPosY:           f32,                  // Backup of CursorPos at the time of BeginColumns()
	HostCursorMaxPosX:        f32,                  // Backup of CursorMaxPos at the time of BeginColumns()
	HostInitialClipRect:      Rect,                 // Backup of ClipRect at the time of BeginColumns()
	HostBackupClipRect:       Rect,                 // Backup of ClipRect during PushColumnsBackground()/PopColumnsBackground()
	HostBackupParentWorkRect: Rect,                 //Backup of WorkRect at the time of BeginColumns()
	Columns:                  Vector_OldColumnData,
	Splitter:                 DrawListSplitter,
}

BoxSelectState :: struct {
	// Active box-selection data (persistent, 1 active at a time)
	ID_:                   ID,
	IsActive:              bool,
	IsStarting:            bool,
	IsStartedFromVoid:     bool,     // Starting click was not from an item.
	IsStartedSetNavIdOnce: bool,
	RequestClear:          bool,
	KeyMods:               KeyChord, // Latched key-mods for box-select logic.
	StartPosRel:           Vec2,     // Start position in window-contents relative space (to support scrolling)
	EndPosRel:             Vec2,     // End position in window-contents relative space
	ScrollAccum:           Vec2,     // Scrolling accumulator (to behave at high-frame spaces)
	Window_:               ^Window,
	// Temporary/Transient data
	UnclipMode:        bool, // (Temp/Transient, here in hot area). Set/cleared by the BeginMultiSelect()/EndMultiSelect() owning active box-select.
	UnclipRect:        Rect, // Rectangle where ItemAdd() clipping may be temporarily disabled. Need support by multi-select supporting widgets.
	BoxSelectRectPrev: Rect, // Selection rectangle in absolute coordinates (derived every frame from BoxSelectStartPosRel and MousePos)
	BoxSelectRectCurr: Rect,
}

// Temporary storage for multi-select
MultiSelectTempData :: struct {
	IO:                 MultiSelectIO,     // MUST BE FIRST FIELD. Requests are set and returned by BeginMultiSelect()/EndMultiSelect() + written to by user during the loop.
	Storage:            ^MultiSelectState,
	FocusScopeId:       ID,                // Copied from g.CurrentFocusScopeId (unless another selection scope was pushed manually)
	Flags:              MultiSelectFlags,
	ScopeRectMin:       Vec2,
	BackupCursorMaxPos: Vec2,
	LastSubmittedItem:  SelectionUserData, // Copy of last submitted item data, used to merge output ranges.
	BoxSelectId:        ID,
	KeyMods:            KeyChord,
	LoopRequestSetAll:  i8,                // -1: no operation, 0: clear all, 1: select all.
	IsEndIO:            bool,              // Set when switching IO from BeginMultiSelect() to EndMultiSelect() state.
	IsFocused:          bool,              // Set if currently focusing the selection scope (any item of the selection). May be used if you have custom shortcut associated to selection.
	IsKeyboardSetRange: bool,              // Set by BeginMultiSelect() when using Shift+Navigation. Because scrolling may be affected we can't afford a frame of lag with Shift+Navigation.
	NavIdPassedBy:      bool,
	RangeSrcPassedBy:   bool,              // Set by the item that matches RangeSrcItem.
	RangeDstPassedBy:   bool,              // Set by the item that matches NavJustMovedToId when IsSetRange is set.
}

// Persistent storage for multi-select (as long as selection is alive)
MultiSelectState :: struct {
	Window_:           ^Window,
	ID_:               ID,
	LastFrameActive:   c.int,             // Last used frame-count, for GC.
	LastSelectionSize: c.int,             // Set by BeginMultiSelect() based on optional info provided by user. May be -1 if unknown.
	RangeSelected:     i8,                // -1 (don't have) or true/false
	NavIdSelected:     i8,                // -1 (don't have) or true/false
	RangeSrcItem:      SelectionUserData, //
	NavIdItem:         SelectionUserData, // SetNextItemSelectionUserData() value for NavId (if part of submitted items)
}

// sizeof() 156~192
DockNode :: struct {
	ID_:                    ID,
	SharedFlags:            DockNodeFlags,    // (Write) Flags shared by all nodes of a same dockspace hierarchy (inherited from the root node)
	LocalFlags:             DockNodeFlags,    // (Write) Flags specific to this node
	LocalFlagsInWindows:    DockNodeFlags,    // (Write) Flags specific to this node, applied from windows
	MergedFlags:            DockNodeFlags,    // (Read)  Effective flags (== SharedFlags | LocalFlagsInNode | LocalFlagsInWindows)
	State:                  DockNodeState,
	ParentNode:             ^DockNode,
	ChildNodes:             [2]^DockNode,     // [Split node only] Child nodes (left/right or top/bottom). Consider switching to an array.
	Windows:                Vector_WindowPtr, // Note: unordered list! Iterate TabBar->Tabs for user-order.
	TabBar:                 ^TabBar,
	Pos:                    Vec2,             // Current position
	Size:                   Vec2,             // Current size
	SizeRef:                Vec2,             // [Split node only] Last explicitly written-to size (overridden when using a splitter affecting the node), used to calculate Size.
	SplitAxis:              Axis,             // [Split node only] Split axis (X or Y)
	WindowClass:            WindowClass,      // [Root node only]
	LastBgColor:            u32,
	HostWindow:             ^Window,
	VisibleWindow:          ^Window,          // Generally point to window which is ID is == SelectedTabID, but when CTRL+Tabbing this can be a different window.
	CentralNode:            ^DockNode,        // [Root node only] Pointer to central node.
	OnlyNodeWithWindows:    ^DockNode,        // [Root node only] Set when there is a single visible node within the hierarchy.
	CountNodeWithWindows:   c.int,            // [Root node only]
	LastFrameAlive:         c.int,            // Last frame number the node was updated or kept alive explicitly with DockSpace() + ImGuiDockNodeFlags_KeepAliveOnly
	LastFrameActive:        c.int,            // Last frame number the node was updated.
	LastFrameFocused:       c.int,            // Last frame number the node was focused.
	LastFocusedNodeId:      ID,               // [Root node only] Which of our child docking node (any ancestor in the hierarchy) was last focused.
	SelectedTabId:          ID,               // [Leaf node only] Which of our tab/window is selected.
	WantCloseTabId:         ID,               // [Leaf node only] Set when closing a specific tab/window.
	RefViewportId:          ID,               // Reference viewport ID from visible window when HostWindow == NULL.
	AuthorityForPos:        DataAuthority,
	AuthorityForSize:       DataAuthority,
	AuthorityForViewport:   DataAuthority,
	IsVisible:              bool,             // Set to false when the node is hidden (usually disabled as it has no active window)
	IsFocused:              bool,
	IsBgDrawnThisFrame:     bool,
	HasCloseButton:         bool,             // Provide space for a close button (if any of the docked window has one). Note that button may be hidden on window without one.
	HasWindowMenuButton:    bool,
	HasCentralNodeChild:    bool,
	WantCloseAll:           bool,             // Set when closing all tabs at once.
	WantLockSizeOnce:       bool,
	WantMouseMove:          bool,             // After a node extraction we need to transition toward moving the newly created host window
	WantHiddenTabBarUpdate: bool,
	WantHiddenTabBarToggle: bool,
}

// We don't store style.Alpha: dock_node->LastBgColor embeds it and otherwise it would only affect the docking tab, which intuitively I would say we don't want to.
WindowDockStyle :: struct {
	Colors: [WindowDockStyleCol.COUNT]u32,
}

DockContext :: struct {
	Nodes:           Storage,                 // Map ID -> ImGuiDockNode*: Active nodes
	Requests:        Vector_DockRequest,
	NodesSettings:   Vector_DockNodeSettings,
	WantFullRebuild: bool,
}

// ImGuiViewport Private/Internals fields (cardinal sin: we are using inheritance!)
// Every instance of ImGuiViewport is in fact a ImGuiViewportP.
ViewportP :: struct {
	// Appended from parent type ImGuiViewport
	ID_:              ID,            // Unique identifier for the viewport
	Flags:            ViewportFlags, // See ImGuiViewportFlags_
	Pos:              Vec2,          // Main Area: Position of the viewport (Dear ImGui coordinates are the same as OS desktop/native coordinates)
	Size:             Vec2,          // Main Area: Size of the viewport.
	WorkPos:          Vec2,          // Work Area: Position of the viewport minus task bars, menus bars, status bars (>= Pos)
	WorkSize:         Vec2,          // Work Area: Size of the viewport minus task bars, menu bars, status bars (<= Size)
	DpiScale:         f32,           // 1.0f = 96 DPI = No extra scale.
	ParentViewportId: ID,            // (Advanced) 0: no parent. Instruct the platform backend to setup a parent/child relationship between platform windows.
	DrawData_:        ^DrawData,     // The ImDrawData corresponding to this viewport. Valid after Render() and until the next call to NewFrame().
	// Platform/Backend Dependent Data
	// Our design separate the Renderer and Platform backends to facilitate combining default backends with each others.
	// When our create your own backend for a custom engine, it is possible that both Renderer and Platform will be handled
	// by the same system and you may not need to use all the UserData/Handle fields.
	// The library never uses those fields, they are merely storage to facilitate backend implementation.
	RendererUserData:        rawptr,          // void* to hold custom data structure for the renderer (e.g. swap chain, framebuffers etc.). generally set by your Renderer_CreateWindow function.
	PlatformUserData:        rawptr,          // void* to hold custom data structure for the OS / platform (e.g. windowing info, render context). generally set by your Platform_CreateWindow function.
	PlatformHandle:          rawptr,          // void* to hold higher-level, platform window handle (e.g. HWND, GLFWWindow*, SDL_Window*), for FindViewportByPlatformHandle().
	PlatformHandleRaw:       rawptr,          // void* to hold lower-level, platform-native window handle (under Win32 this is expected to be a HWND, unused for other platforms), when using an abstraction layer like GLFW or SDL (where PlatformHandle would be a SDL_Window*)
	PlatformWindowCreated:   bool,            // Platform window has been created (Platform_CreateWindow() has been called). This is false during the first frame where a viewport is being created.
	PlatformRequestMove:     bool,            // Platform window requested move (e.g. window was moved by the OS / host window manager, authoritative position will be OS window position)
	PlatformRequestResize:   bool,            // Platform window requested resize (e.g. window was resized by the OS / host window manager, authoritative size will be OS window size)
	PlatformRequestClose:    bool,            // Platform window requested closure (e.g. window was moved by the OS / host window manager, e.g. pressing ALT-F4)
	Window_:                 ^Window,         // Set when the viewport is owned by a window (and ImGuiViewportFlags_CanHostOtherWindows is NOT set)
	Idx:                     c.int,
	LastFrameActive:         c.int,           // Last frame number this viewport was activated by a window
	LastFocusedStampCount:   c.int,           // Last stamp number from when a window hosted by this viewport was focused (by comparing this value between two viewport we have an implicit viewport z-order we use as fallback)
	LastNameHash:            ID,
	LastPos:                 Vec2,
	LastSize:                Vec2,
	Alpha:                   f32,             // Window opacity (when dragging dockable windows/viewports we make them transparent)
	LastAlpha:               f32,
	LastFocusedHadNavWindow: bool,            // Instead of maintaining a LastFocusedWindow (which may harder to correctly maintain), we merely store weither NavWindow != NULL last time the viewport was focused.
	PlatformMonitor:         c.short,
	BgFgDrawListsLastFrame:  [2]c.int,        // Last frame number the background (0) and foreground (1) draw lists were used
	BgFgDrawLists:           [2]^DrawList,    // Convenience background (0) and foreground (1) draw lists. We use them to draw software mouser cursor when io.MouseDrawCursor is set and to draw most debug overlays.
	DrawDataP:               DrawData,
	DrawDataBuilder:         DrawDataBuilder, // Temporary data while building final ImDrawData
	LastPlatformPos:         Vec2,
	LastPlatformSize:        Vec2,
	LastRendererSize:        Vec2,
	// Per-viewport work area
	// - Insets are >= 0.0f values, distance from viewport corners to work area.
	// - BeginMainMenuBar() and DockspaceOverViewport() tend to use work area to avoid stepping over existing contents.
	// - Generally 'safeAreaInsets' in iOS land, 'DisplayCutout' in Android land.
	WorkInsetMin:      Vec2, // Work Area inset locked for the frame. GetWorkRect() always fits within GetMainRect().
	WorkInsetMax:      Vec2, // "
	BuildWorkInsetMin: Vec2, // Work Area inset accumulator for current frame, to become next frame's WorkInset
	BuildWorkInsetMax: Vec2, // "
}

// Windows data saved in imgui.ini file
// Because we never destroy or rename ImGuiWindowSettings, we can store the names in a separate buffer easily.
// (this is designed to be stored in a ImChunkStream buffer, with the variable-length Name following our structure)
WindowSettings :: struct {
	ID_:         ID,
	Pos:         Vec2ih,  // NB: Settings position are stored RELATIVE to the viewport! Whereas runtime ones are absolute positions.
	Size:        Vec2ih,
	ViewportPos: Vec2ih,
	ViewportId:  ID,
	DockId:      ID,      // ID of last known DockNode (even if the DockNode is invisible because it has only 1 active window), or 0 if none.
	ClassId:     ID,      // ID of window class if specified
	DockOrder:   c.short, // Order of the last time the window was visible within its DockNode. This is used to reorder windows that are reappearing on the same frame. Same value between windows that were active and windows that were none are possible.
	Collapsed:   bool,
	IsChild:     bool,
	WantApply:   bool,    // Set when loaded from .ini data (to enable merging/loading .ini data into an already running context)
	WantDelete:  bool,    // Set to invalidate/delete the settings entry
}

SettingsHandler :: struct {
	TypeName:   cstring,                                                                           // Short description stored in .ini file. Disallowed characters: '[' ']'
	TypeHash:   ID,                                                                                // == ImHashStr(TypeName)
	ClearAllFn: proc "c" (ctx: ^Context, handler: ^SettingsHandler),                               // Clear all settings data
	ReadInitFn: proc "c" (ctx: ^Context, handler: ^SettingsHandler),                               // Read: Called before reading (in registration order)
	ReadOpenFn: proc "c" (ctx: ^Context, handler: ^SettingsHandler, name: cstring) -> rawptr,      // Read: Called when entering into a new ini entry e.g. "[Window][Name]"
	ReadLineFn: proc "c" (ctx: ^Context, handler: ^SettingsHandler, entry: rawptr, line: cstring), // Read: Called for every line of text within an ini entry
	ApplyAllFn: proc "c" (ctx: ^Context, handler: ^SettingsHandler),                               // Read: Called after reading (in registration order)
	WriteAllFn: proc "c" (ctx: ^Context, handler: ^SettingsHandler, out_buf: ^TextBuffer),         // Write: Output every entries into 'out_buf'
	UserData:   rawptr,
}

LocEntry :: struct {
	Key:  LocKey,
	Text: cstring,
}

DebugAllocEntry :: struct {
	FrameCount: c.int,
	AllocCount: i16,
	FreeCount:  i16,
}

DebugAllocInfo :: struct {
	TotalAllocCount: c.int,              // Number of call to MemAlloc().
	TotalFreeCount:  c.int,
	LastEntriesIdx:  i16,                // Current index in buffer
	LastEntriesBuf:  [6]DebugAllocEntry, // Track last 6 frames that had allocations
}

MetricsConfig :: struct {
	ShowDebugLog:                 bool,
	ShowIDStackTool:              bool,
	ShowWindowsRects:             bool,
	ShowWindowsBeginOrder:        bool,
	ShowTablesRects:              bool,
	ShowDrawCmdMesh:              bool,
	ShowDrawCmdBoundingBoxes:     bool,
	ShowTextEncodingViewer:       bool,
	ShowAtlasTintedWithTextColor: bool,
	ShowDockingNodes:             bool,
	ShowWindowsRectsType:         c.int,
	ShowTablesRectsType:          c.int,
	HighlightMonitorIdx:          c.int,
	HighlightViewportID:          ID,
}

StackLevelInfo :: struct {
	ID_:             ID,
	QueryFrameCount: i8,         // >= 1: Query in progress
	QuerySuccess:    bool,       // Obtained result from DebugHookIdInfo()
	DataType:        DataType,
	Desc:            [57]c.char, // Arbitrarily sized buffer to hold a result (FIXME: could replace Results[] with a chunk stream?) FIXME: Now that we added CTRL+C this should be fixed.
}

// State for ID Stack tool queries
IDStackTool :: struct {
	LastActiveFrame:         c.int,
	StackLevel:              c.int,                 // -1: query stack and resize Results, >= 0: individual stack level
	QueryId:                 ID,                    // ID to query details for
	Results:                 Vector_StackLevelInfo,
	CopyToClipboardOnCtrlC:  bool,
	CopyToClipboardLastTime: f32,
}

ContextHook :: struct {
	HookId:   ID,                  // A unique ID assigned by AddContextHook()
	Type:     ContextHookType,
	Owner:    ID,
	Callback: ContextHookCallback,
	UserData: rawptr,
}

Context :: struct {
	Initialized:                        bool,
	FontAtlasOwnedByContext:            bool,               // IO.Fonts-> is owned by the ImGuiContext and will be destructed along with it.
	IO:                                 IO,
	PlatformIO:                         PlatformIO,
	Style:                              Style,
	ConfigFlagsCurrFrame:               ConfigFlags,        // = g.IO.ConfigFlags at the time of NewFrame()
	ConfigFlagsLastFrame:               ConfigFlags,
	Font_:                              ^Font,              // (Shortcut) == FontStack.empty() ? IO.Font : FontStack.back()
	FontSize:                           f32,                // (Shortcut) == FontBaseSize * g.CurrentWindow->FontWindowScale == window->FontSize(). Text height for current window.
	FontBaseSize:                       f32,                // (Shortcut) == IO.FontGlobalScale * Font->Scale * Font->FontSize. Base text height.
	FontScale:                          f32,                // == FontSize / Font->FontSize
	CurrentDpiScale:                    f32,                // Current window/viewport DpiScale == CurrentViewport->DpiScale
	DrawListSharedData:                 DrawListSharedData,
	Time:                               f64,
	FrameCount:                         c.int,
	FrameCountEnded:                    c.int,
	FrameCountPlatformEnded:            c.int,
	FrameCountRendered:                 c.int,
	WithinEndChildID:                   ID,                 // Set within EndChild()
	WithinFrameScope:                   bool,               // Set by NewFrame(), cleared by EndFrame()
	WithinFrameScopeWithImplicitWindow: bool,               // Set by NewFrame(), cleared by EndFrame() when the implicit debug window has been pushed
	GcCompactAll:                       bool,               // Request full GC
	TestEngineHookItems:                bool,               // Will call test engine hooks: ImGuiTestEngineHook_ItemAdd(), ImGuiTestEngineHook_ItemInfo(), ImGuiTestEngineHook_Log()
	TestEngine:                         rawptr,             // Test engine user data
	ContextName:                        [16]c.char,         // Storage for a context name (to facilitate debugging multi-context setups)
	// Inputs
	InputEventsQueue:           Vector_InputEvent, // Input events which will be trickled/written into IO structure.
	InputEventsTrail:           Vector_InputEvent, // Past input events processed in NewFrame(). This is to allow domain-specific application to access e.g mouse/pen trail.
	InputEventsNextMouseSource: MouseSource,
	InputEventsNextEventId:     u32,
	// Windows state
	Windows:                        Vector_WindowPtr,       // Windows, sorted in display order, back to front
	WindowsFocusOrder:              Vector_WindowPtr,       // Root windows, sorted in focus order, back to front.
	WindowsTempSortBuffer:          Vector_WindowPtr,       // Temporary buffer used in EndFrame() to reorder windows so parents are kept before their child
	CurrentWindowStack:             Vector_WindowStackData,
	WindowsById:                    Storage,                // Map window's ImGuiID to ImGuiWindow*
	WindowsActiveCount:             c.int,                  // Number of unique windows submitted by frame
	WindowsHoverPadding:            Vec2,                   // Padding around resizable windows for which hovering on counts as hovering the window == ImMax(style.TouchExtraPadding, WINDOWS_HOVER_PADDING).
	DebugBreakInWindow:             ID,                     // Set to break in Begin() call.
	CurrentWindow:                  ^Window,                // Window being drawn into
	HoveredWindow:                  ^Window,                // Window the mouse is hovering. Will typically catch mouse inputs.
	HoveredWindowUnderMovingWindow: ^Window,                // Hovered window ignoring MovingWindow. Only set if MovingWindow is set.
	HoveredWindowBeforeClear:       ^Window,                // Window the mouse is hovering. Filled even with _NoMouse. This is currently useful for multi-context compositors.
	MovingWindow:                   ^Window,                // Track the window we clicked on (in order to preserve focus). The actual window that is moved is generally MovingWindow->RootWindowDockTree.
	WheelingWindow:                 ^Window,                // Track the window we started mouse-wheeling on. Until a timer elapse or mouse has moved, generally keep scrolling the same window even if during the course of scrolling the mouse ends up hovering a child window.
	WheelingWindowRefMousePos:      Vec2,
	WheelingWindowStartFrame:       c.int,                  // This may be set one frame before WheelingWindow is != NULL
	WheelingWindowScrolledFrame:    c.int,
	WheelingWindowReleaseTimer:     f32,
	WheelingWindowWheelRemainder:   Vec2,
	WheelingAxisAvg:                Vec2,
	// Item/widgets state and tracking information
	DebugDrawIdConflicts:            ID,                  // Set when we detect multiple items with the same identifier
	DebugHookIdInfo:                 ID,                  // Will call core hooks: DebugHookIdInfo() from GetID functions, used by ID Stack Tool [next HoveredId/ActiveId to not pull in an extra cache-line]
	HoveredId:                       ID,                  // Hovered widget, filled during the frame
	HoveredIdPreviousFrame:          ID,
	HoveredIdPreviousFrameItemCount: c.int,               // Count numbers of items using the same ID as last frame's hovered id
	HoveredIdTimer:                  f32,                 // Measure contiguous hovering time
	HoveredIdNotActiveTimer:         f32,                 // Measure contiguous hovering time where the item has not been active
	HoveredIdAllowOverlap:           bool,
	HoveredIdIsDisabled:             bool,                // At least one widget passed the rect test, but has been discarded by disabled flag or popup inhibit. May be true even if HoveredId == 0.
	ItemUnclipByLog:                 bool,                // Disable ItemAdd() clipping, essentially a memory-locality friendly copy of LogEnabled
	ActiveId:                        ID,                  // Active widget
	ActiveIdIsAlive:                 ID,                  // Active widget has been seen this frame (we can't use a bool as the ActiveId may change within the frame)
	ActiveIdTimer:                   f32,
	ActiveIdIsJustActivated:         bool,                // Set at the time of activation for one frame
	ActiveIdAllowOverlap:            bool,                // Active widget allows another widget to steal active id (generally for overlapping widgets, but not always)
	ActiveIdNoClearOnFocusLoss:      bool,                // Disable losing active id if the active id window gets unfocused.
	ActiveIdHasBeenPressedBefore:    bool,                // Track whether the active id led to a press (this is to allow changing between PressOnClick and PressOnRelease without pressing twice). Used by range_select branch.
	ActiveIdHasBeenEditedBefore:     bool,                // Was the value associated to the widget Edited over the course of the Active state.
	ActiveIdHasBeenEditedThisFrame:  bool,
	ActiveIdFromShortcut:            bool,
	ActiveIdMouseButton:             c.int,
	ActiveIdClickOffset:             Vec2,                // Clicked offset from upper-left corner, if applicable (currently only set by ButtonBehavior)
	ActiveIdWindow:                  ^Window,
	ActiveIdSource:                  InputSource,         // Activating source: ImGuiInputSource_Mouse OR ImGuiInputSource_Keyboard OR ImGuiInputSource_Gamepad
	ActiveIdPreviousFrame:           ID,
	DeactivatedItemData:             DeactivatedItemData,
	ActiveIdValueOnActivation:       DataTypeStorage,     // Backup of initial value at the time of activation. ONLY SET BY SPECIFIC WIDGETS: DragXXX and SliderXXX.
	LastActiveId:                    ID,                  // Store the last non-zero ActiveId, useful for animation.
	LastActiveIdTimer:               f32,                 // Store the last non-zero ActiveId timer since the beginning of activation, useful for animation.
	// Key/Input Ownership + Shortcut Routing system
	// - The idea is that instead of "eating" a given key, we can link to an owner.
	// - Input query can then read input by specifying ImGuiKeyOwner_Any (== 0), ImGuiKeyOwner_NoOwner (== -1) or a custom ID.
	// - Routing is requested ahead of time for a given chord (Key + Mods) and granted in NewFrame().
	LastKeyModsChangeTime:         f64,                              // Record the last time key mods changed (affect repeat delay when using shortcut logic)
	LastKeyModsChangeFromNoneTime: f64,                              // Record the last time key mods changed away from being 0 (affect repeat delay when using shortcut logic)
	LastKeyboardKeyPressTime:      f64,                              // Record the last time a keyboard key (ignore mouse/gamepad ones) was pressed.
	KeysMayBeCharInput:            BitArrayForNamedKeys,             // Lookup to tell if a key can emit char input, see IsKeyChordPotentiallyCharInput(). sizeof() = 20 bytes
	KeysOwnerData:                 [Key.NamedKey_COUNT]KeyOwnerData,
	KeysRoutingTable:              KeyRoutingTable,
	ActiveIdUsingNavDirMask:       u32,                              // Active widget will want to read those nav move requests (e.g. can activate a button and move away from it)
	ActiveIdUsingAllKeyboardKeys:  bool,                             // Active widget will want to read all keyboard keys inputs. (this is a shortcut for not taking ownership of 100+ keys, frequently used by drag operations)
	DebugBreakInShortcutRouting:   KeyChord,                         // Set to break in SetShortcutRouting()/Shortcut() calls.
	// Next window/item data
	CurrentFocusScopeId: ID,             // Value for currently appending items == g.FocusScopeStack.back(). Not to be mistaken with g.NavFocusScopeId.
	CurrentItemFlags:    ItemFlags,      // Value for currently appending items == g.ItemFlagsStack.back()
	DebugLocateId:       ID,             // Storage for DebugLocateItemOnHover() feature: this is read by ItemAdd() so we keep it in a hot/cached location
	NextItemData:        NextItemData,   // Storage for SetNextItem** functions
	LastItemData:        LastItemData,   // Storage for last submitted item (setup by ItemAdd)
	NextWindowData:      NextWindowData, // Storage for SetNextWindow** functions
	DebugShowGroupRects: bool,
	// Shared stacks
	DebugFlashStyleColorIdx: Col,                      // (Keep close to ColorStack to share cache line)
	ColorStack:              Vector_ColorMod,          // Stack for PushStyleColor()/PopStyleColor() - inherited by Begin()
	StyleVarStack:           Vector_StyleMod,          // Stack for PushStyleVar()/PopStyleVar() - inherited by Begin()
	FontStack:               Vector_FontPtr,           // Stack for PushFont()/PopFont() - inherited by Begin()
	FocusScopeStack:         Vector_FocusScopeData,    // Stack for PushFocusScope()/PopFocusScope() - inherited by BeginChild(), pushed into by Begin()
	ItemFlagsStack:          Vector_ItemFlags,         // Stack for PushItemFlag()/PopItemFlag() - inherited by Begin()
	GroupStack:              Vector_GroupData,         // Stack for BeginGroup()/EndGroup() - not inherited by Begin()
	OpenPopupStack:          Vector_PopupData,         // Which popups are open (persistent)
	BeginPopupStack:         Vector_PopupData,         // Which level of BeginPopup() we are in (reset every frame)
	TreeNodeStack:           Vector_TreeNodeStackData, // Stack for TreeNode()
	// Viewports
	Viewports:                     Vector_ViewportPPtr, // Active viewports (always 1+, and generally 1 unless multi-viewports are enabled). Each viewports hold their copy of ImDrawData.
	CurrentViewport:               ^ViewportP,          // We track changes of viewport (happening in Begin) so we can call Platform_OnChangedViewport()
	MouseViewport:                 ^ViewportP,
	MouseLastHoveredViewport:      ^ViewportP,          // Last known viewport that was hovered by mouse (even if we are not hovering any viewport any more) + honoring the _NoInputs flag.
	PlatformLastFocusedViewportId: ID,
	FallbackMonitor:               PlatformMonitor,     // Virtual monitor used as fallback if backend doesn't provide monitor information.
	PlatformMonitorsFullWorkRect:  Rect,                // Bounding box of all platform monitors
	ViewportCreatedCount:          c.int,               // Unique sequential creation counter (mostly for testing/debugging)
	PlatformWindowsCreatedCount:   c.int,               // Unique sequential creation counter (mostly for testing/debugging)
	ViewportFocusedStampCount:     c.int,               // Every time the front-most window changes, we stamp its viewport with an incrementing counter
	// Keyboard/Gamepad Navigation
	NavCursorVisible:         bool, // Nav focus cursor/rectangle is visible? We hide it after a mouse click. We show it after a nav move.
	NavHighlightItemUnderNav: bool, // Disable mouse hovering highlight. Highlight navigation focused item instead of mouse hovered item.
	//bool                  NavDisableHighlight;                // Old name for !g.NavCursorVisible before 1.91.4 (2024/10/18). OPPOSITE VALUE (g.NavDisableHighlight == !g.NavCursorVisible)
	//bool                  NavDisableMouseHover;               // Old name for g.NavHighlightItemUnderNav before 1.91.1 (2024/10/18) this was called When user starts using keyboard/gamepad, we hide mouse hovering highlight until mouse is touched again.
	NavMousePosDirty:              bool,                  // When set we will update mouse position if io.ConfigNavMoveSetMousePos is set (not enabled by default)
	NavIdIsAlive:                  bool,                  // Nav widget has been seen this frame ~~ NavRectRel is valid
	NavId:                         ID,                    // Focused item for navigation
	NavWindow:                     ^Window,               // Focused window for navigation. Could be called 'FocusedWindow'
	NavFocusScopeId:               ID,                    // Focused focus scope (e.g. selection code often wants to "clear other items" when landing on an item of the same scope)
	NavLayer:                      NavLayer,              // Focused layer (main scrolling layer, or menu/title bar layer)
	NavActivateId:                 ID,                    // ~~ (g.ActiveId == 0) && (IsKeyPressed(ImGuiKey_Space) || IsKeyDown(ImGuiKey_Enter) || IsKeyPressed(ImGuiKey_NavGamepadActivate)) ? NavId : 0, also set when calling ActivateItem()
	NavActivateDownId:             ID,                    // ~~ IsKeyDown(ImGuiKey_Space) || IsKeyDown(ImGuiKey_Enter) || IsKeyDown(ImGuiKey_NavGamepadActivate) ? NavId : 0
	NavActivatePressedId:          ID,                    // ~~ IsKeyPressed(ImGuiKey_Space) || IsKeyPressed(ImGuiKey_Enter) || IsKeyPressed(ImGuiKey_NavGamepadActivate) ? NavId : 0 (no repeat)
	NavActivateFlags:              ActivateFlags,
	NavFocusRoute:                 Vector_FocusScopeData, // Reversed copy focus scope stack for NavId (should contains NavFocusScopeId). This essentially follow the window->ParentWindowForFocusRoute chain.
	NavHighlightActivatedId:       ID,
	NavHighlightActivatedTimer:    f32,
	NavNextActivateId:             ID,                    // Set by ActivateItem(), queued until next frame.
	NavNextActivateFlags:          ActivateFlags,
	NavInputSource:                InputSource,           // Keyboard or Gamepad mode? THIS CAN ONLY BE ImGuiInputSource_Keyboard or ImGuiInputSource_Mouse
	NavLastValidSelectionUserData: SelectionUserData,     // Last valid data passed to SetNextItemSelectionUser(), or -1. For current window. Not reset when focusing an item that doesn't have selection data.
	NavCursorHideFrames:           i8,
	// Navigation: Init & Move Requests
	NavAnyRequest:             bool,         // ~~ NavMoveRequest || NavInitRequest this is to perform early out in ItemAdd()
	NavInitRequest:            bool,         // Init request for appearing window to select first item
	NavInitRequestFromMove:    bool,
	NavInitResult:             NavItemData,  // Init request result (first item of the window, or one for which SetItemDefaultFocus() was called)
	NavMoveSubmitted:          bool,         // Move request submitted, will process result on next NewFrame()
	NavMoveScoringItems:       bool,         // Move request submitted, still scoring incoming items
	NavMoveForwardToNextFrame: bool,
	NavMoveFlags:              NavMoveFlags,
	NavMoveScrollFlags:        ScrollFlags,
	NavMoveKeyMods:            KeyChord,
	NavMoveDir:                Dir,          // Direction of the move request (left/right/up/down)
	NavMoveDirForDebug:        Dir,
	NavMoveClipDir:            Dir,          // FIXME-NAV: Describe the purpose of this better. Might want to rename?
	NavScoringRect:            Rect,         // Rectangle used for scoring, in screen space. Based of window->NavRectRel[], modified for directional navigation scoring.
	NavScoringNoClipRect:      Rect,         // Some nav operations (such as PageUp/PageDown) enforce a region which clipper will attempt to always keep submitted
	NavScoringDebugCount:      c.int,        // Metrics for debugging
	NavTabbingDir:             c.int,        // Generally -1 or +1, 0 when tabbing without a nav id
	NavTabbingCounter:         c.int,        // >0 when counting items for tabbing
	NavMoveResultLocal:        NavItemData,  // Best move request candidate within NavWindow
	NavMoveResultLocalVisible: NavItemData,  // Best move request candidate within NavWindow that are mostly visible (when using ImGuiNavMoveFlags_AlsoScoreVisibleSet flag)
	NavMoveResultOther:        NavItemData,  // Best move request candidate within NavWindow's flattened hierarchy (when using ImGuiWindowFlags_NavFlattened flag)
	NavTabbingResultFirst:     NavItemData,  // First tabbing request candidate within NavWindow and flattened hierarchy
	// Navigation: record of last move request
	NavJustMovedFromFocusScopeId:   ID,       // Just navigated from this focus scope id (result of a successfully MoveRequest).
	NavJustMovedToId:               ID,       // Just navigated to this id (result of a successfully MoveRequest).
	NavJustMovedToFocusScopeId:     ID,       // Just navigated to this focus scope id (result of a successfully MoveRequest).
	NavJustMovedToKeyMods:          KeyChord,
	NavJustMovedToIsTabbing:        bool,     // Copy of ImGuiNavMoveFlags_IsTabbing. Maybe we should store whole flags.
	NavJustMovedToHasSelectionData: bool,     // Copy of move result's ItemFlags & ImGuiItemFlags_HasSelectionUserData). Maybe we should just store ImGuiNavItemData.
	// Navigation: Windowing (CTRL+TAB for list, or Menu button + keys or directional pads to move/resize)
	ConfigNavWindowingKeyNext:  KeyChord, // = ImGuiMod_Ctrl | ImGuiKey_Tab (or ImGuiMod_Super | ImGuiKey_Tab on OS X). For reconfiguration (see #4828)
	ConfigNavWindowingKeyPrev:  KeyChord, // = ImGuiMod_Ctrl | ImGuiMod_Shift | ImGuiKey_Tab (or ImGuiMod_Super | ImGuiMod_Shift | ImGuiKey_Tab on OS X)
	NavWindowingTarget:         ^Window,  // Target window when doing CTRL+Tab (or Pad Menu + FocusPrev/Next), this window is temporarily displayed top-most!
	NavWindowingTargetAnim:     ^Window,  // Record of last valid NavWindowingTarget until DimBgRatio and NavWindowingHighlightAlpha becomes 0.0f, so the fade-out can stay on it.
	NavWindowingListWindow:     ^Window,  // Internal window actually listing the CTRL+Tab contents
	NavWindowingTimer:          f32,
	NavWindowingHighlightAlpha: f32,
	NavWindowingToggleLayer:    bool,
	NavWindowingToggleKey:      Key,
	NavWindowingAccumDeltaPos:  Vec2,
	NavWindowingAccumDeltaSize: Vec2,
	// Render
	DimBgRatio: f32, // 0.0..1.0 animation when fading in a dimming background (for modal window and CTRL+TAB list)
	// Drag and Drop
	DragDropActive:                  bool,
	DragDropWithinSource:            bool,                 // Set when within a BeginDragDropXXX/EndDragDropXXX block for a drag source.
	DragDropWithinTarget:            bool,                 // Set when within a BeginDragDropXXX/EndDragDropXXX block for a drag target.
	DragDropSourceFlags:             DragDropFlags,
	DragDropSourceFrameCount:        c.int,
	DragDropMouseButton:             c.int,
	DragDropPayload:                 Payload,
	DragDropTargetRect:              Rect,                 // Store rectangle of current target candidate (we favor small targets when overlapping)
	DragDropTargetClipRect:          Rect,                 // Store ClipRect at the time of item's drawing
	DragDropTargetId:                ID,
	DragDropAcceptFlags:             DragDropFlags,
	DragDropAcceptIdCurrRectSurface: f32,                  // Target item surface (we resolve overlapping targets by prioritizing the smaller surface)
	DragDropAcceptIdCurr:            ID,                   // Target item id (set at the time of accepting the payload)
	DragDropAcceptIdPrev:            ID,                   // Target item id from previous frame (we need to store this to allow for overlapping drag and drop targets)
	DragDropAcceptFrameCount:        c.int,                // Last time a target expressed a desire to accept the source
	DragDropHoldJustPressedId:       ID,                   // Set when holding a payload just made ButtonBehavior() return a press.
	DragDropPayloadBufHeap:          Vector_unsigned_char, // We don't expose the ImVector<> directly, ImGuiPayload only holds pointer+size
	DragDropPayloadBufLocal:         [16]c.uchar,          // Local buffer for small payloads
	// Clipper
	ClipperTempDataStacked: c.int,
	ClipperTempData:        Vector_ListClipperData,
	// Tables
	CurrentTable:                ^Table,
	DebugBreakInTable:           ID,                   // Set to break in BeginTable() call.
	TablesTempDataStacked:       c.int,                // Temporary table data size (because we leave previous instances undestructed, we generally don't use TablesTempData.Size)
	TablesTempData:              Vector_TableTempData, // Temporary table data (buffers reused/shared across instances, support nesting)
	Tables:                      Pool_ImGuiTable,      // Persistent table data
	TablesLastTimeActive:        Vector_float,         // Last used timestamp of each tables (SOA, for efficient GC)
	DrawChannelsTempMergeBuffer: Vector_DrawChannel,
	// Tab bars
	CurrentTabBar:      ^TabBar,
	TabBars:            Pool_ImGuiTabBar,
	CurrentTabBarStack: Vector_PtrOrIndex,
	ShrinkWidthBuffer:  Vector_ShrinkWidthItem,
	// Multi-Select state
	BoxSelectState:             BoxSelectState,
	CurrentMultiSelect:         ^MultiSelectTempData,
	MultiSelectTempDataStacked: c.int,                      // Temporary multi-select data size (because we leave previous instances undestructed, we generally don't use MultiSelectTempData.Size)
	MultiSelectTempData:        Vector_MultiSelectTempData,
	MultiSelectStorage:         Pool_ImGuiMultiSelectState,
	// Hover Delay system
	HoverItemDelayId:                ID,
	HoverItemDelayIdPreviousFrame:   ID,
	HoverItemDelayTimer:             f32, // Currently used by IsItemHovered()
	HoverItemDelayClearTimer:        f32, // Currently used by IsItemHovered(): grace time before g.TooltipHoverTimer gets cleared.
	HoverItemUnlockedStationaryId:   ID,  // Mouse has once been stationary on this item. Only reset after departing the item.
	HoverWindowUnlockedStationaryId: ID,  // Mouse has once been stationary on this window. Only reset after departing the window.
	// Mouse state
	MouseCursor:          MouseCursor,
	MouseStationaryTimer: f32,         // Time the mouse has been stationary (with some loose heuristic)
	MouseLastValidPos:    Vec2,
	// Widget state
	InputTextState:                  InputTextState,
	InputTextDeactivatedState:       InputTextDeactivatedState,
	InputTextPasswordFont:           Font,
	TempInputId:                     ID,                        // Temporary text input when CTRL+clicking on a slider, etc.
	DataTypeZeroValue:               DataTypeStorage,           // 0 for all data types
	BeginMenuDepth:                  c.int,
	BeginComboDepth:                 c.int,
	ColorEditOptions:                ColorEditFlags,            // Store user options for color edit widgets
	ColorEditCurrentID:              ID,                        // Set temporarily while inside of the parent-most ColorEdit4/ColorPicker4 (because they call each others).
	ColorEditSavedID:                ID,                        // ID we are saving/restoring HS for
	ColorEditSavedHue:               f32,                       // Backup of last Hue associated to LastColor, so we can restore Hue in lossy RGB<>HSV round trips
	ColorEditSavedSat:               f32,                       // Backup of last Saturation associated to LastColor, so we can restore Saturation in lossy RGB<>HSV round trips
	ColorEditSavedColor:             u32,                       // RGB value with alpha set to 0.
	ColorPickerRef:                  Vec4,                      // Initial/reference color at the time of opening the color picker.
	ComboPreviewData:                ComboPreviewData,
	WindowResizeBorderExpectedRect:  Rect,                      // Expected border rect, switch to relative edit if moving
	WindowResizeRelativeMode:        bool,
	ScrollbarSeekMode:               c.short,                   // 0: scroll to clicked location, -1/+1: prev/next page.
	ScrollbarClickDeltaToGrabCenter: f32,                       // When scrolling to mouse location: distance between mouse and center of grab box, normalized in parent space.
	SliderGrabClickOffset:           f32,
	SliderCurrentAccum:              f32,                       // Accumulated slider delta when using navigation controls.
	SliderCurrentAccumDirty:         bool,                      // Has the accumulated slider delta changed since last time we tried to apply it?
	DragCurrentAccumDirty:           bool,
	DragCurrentAccum:                f32,                       // Accumulator for dragging modification. Always high-precision, not rounded by end-user precision settings
	DragSpeedDefaultRatio:           f32,                       // If speed == 0.0f, uses (max-min) * DragSpeedDefaultRatio
	DisabledAlphaBackup:             f32,                       // Backup for style.Alpha for BeginDisabled()
	DisabledStackSize:               c.short,
	TooltipOverrideCount:            c.short,
	TooltipPreviousWindow:           ^Window,                   // Window of last tooltip submitted during the frame
	ClipboardHandlerData:            Vector_char,               // If no custom clipboard handler is defined
	MenusIdSubmittedThisFrame:       Vector_ID,                 // A list of menu IDs that were rendered at least once
	TypingSelectState:               TypingSelectState,         // State for GetTypingSelectRequest()
	// Platform support
	PlatformImeData_:    PlatformImeData, // Data updated by current frame
	PlatformImeDataPrev: PlatformImeData, // Previous frame data. When changed we call the platform_io.Platform_SetImeDataFn() handler.
	PlatformImeViewport: ID,
	// Extensions
	// FIXME: We could provide an API to register one slot in an array held in ImGuiContext?
	DockContext:               DockContext,
	DockNodeWindowMenuHandler: proc "c" (ctx: ^Context, node: ^DockNode, tab_bar: ^TabBar),
	// Settings
	SettingsLoaded:     bool,
	SettingsDirtyTimer: f32,                             // Save .ini Settings to memory when time reaches zero
	SettingsIniData:    TextBuffer,                      // In memory .ini settings
	SettingsHandlers:   Vector_SettingsHandler,          // List of .ini settings handlers
	SettingsWindows:    ChunkStream_ImGuiWindowSettings, // ImGuiWindow .ini settings entries
	SettingsTables:     ChunkStream_ImGuiTableSettings,  // ImGuiTable .ini settings entries
	Hooks:              Vector_ContextHook,              // Hooks for extensions (e.g. test engine)
	HookIdNext:         ID,                              // Next available HookId
	// Localization
	LocalizationTable: [LocKey.COUNT]cstring,
	// Capture/Logging
	LogEnabled:              bool,       // Currently capturing
	LogFlags:                LogFlags,   // Capture flags/type
	LogWindow:               ^Window,
	LogFile:                 FileHandle, // If != NULL log to stdout/ file
	LogBuffer:               TextBuffer, // Accumulation buffer when log to clipboard. This is pointer so our GImGui static constructor doesn't call heap allocators.
	LogNextPrefix:           cstring,
	LogNextSuffix:           cstring,
	LogLinePosY:             f32,
	LogLineFirstItem:        bool,
	LogDepthRef:             c.int,
	LogDepthToExpand:        c.int,
	LogDepthToExpandDefault: c.int,      // Default/stored value for LogDepthMaxExpand if not specified in the LogXXX function call.
	// Error Handling
	ErrorCallback:                     ErrorCallback,       // = NULL. May be exposed in public API eventually.
	ErrorCallbackUserData:             rawptr,              // = NULL
	ErrorTooltipLockedPos:             Vec2,
	ErrorFirst:                        bool,
	ErrorCountCurrentFrame:            c.int,               // [Internal] Number of errors submitted this frame.
	StackSizesInNewFrame:              ErrorRecoveryState,  // [Internal]
	StackSizesInBeginForCurrentWindow: ^ErrorRecoveryState, // [Internal]
	// Debug Tools
	// (some of the highly frequently used data are interleaved in other structures above: DebugBreakXXX fields, DebugHookIdInfo, DebugLocateId etc.)
	DebugDrawIdConflictsCount:      c.int,          // Locked count (preserved when holding CTRL)
	DebugLogFlags_:                 DebugLogFlags,
	DebugLogBuf:                    TextBuffer,
	DebugLogIndex:                  TextIndex,
	DebugLogSkippedErrors:          c.int,
	DebugLogAutoDisableFlags:       DebugLogFlags,
	DebugLogAutoDisableFrames:      u8,
	DebugLocateFrames:              u8,             // For DebugLocateItemOnHover(). This is used together with DebugLocateId which is in a hot/cached spot above.
	DebugBreakInLocateId:           bool,           // Debug break in ItemAdd() call for g.DebugLocateId.
	DebugBreakKeyChord:             KeyChord,       // = ImGuiKey_Pause
	DebugBeginReturnValueCullDepth: i8,             // Cycle between 0..9 then wrap around.
	DebugItemPickerActive:          bool,           // Item picker is active (started with DebugStartItemPicker())
	DebugItemPickerMouseButton:     u8,
	DebugItemPickerBreakId:         ID,             // Will call IM_DEBUG_BREAK() when encountering this ID
	DebugFlashStyleColorTime:       f32,
	DebugFlashStyleColorBackup:     Vec4,
	DebugMetricsConfig:             MetricsConfig,
	DebugIDStackTool:               IDStackTool,
	DebugAllocInfo:                 DebugAllocInfo,
	DebugHoveredDockNode:           ^DockNode,      // Hovered dock node.
	// Misc
	FramerateSecPerFrame:         [60]f32,     // Calculate estimate of framerate for user over the last 60 frames..
	FramerateSecPerFrameIdx:      c.int,
	FramerateSecPerFrameCount:    c.int,
	FramerateSecPerFrameAccum:    f32,
	WantCaptureMouseNextFrame:    c.int,       // Explicit capture override via SetNextFrameWantCaptureMouse()/SetNextFrameWantCaptureKeyboard(). Default to -1.
	WantCaptureKeyboardNextFrame: c.int,       // "
	WantTextInputNextFrame:       c.int,
	TempBuffer:                   Vector_char, // Temporary text buffer
	TempKeychordName:             [64]c.char,
}

// Transient per-window data, reset at the beginning of the frame. This used to be called ImGuiDrawContext, hence the DC variable name in ImGuiWindow.
// (That's theory, in practice the delimitation between ImGuiWindow and ImGuiWindowTempData is quite tenuous and could be reconsidered..)
// (This doesn't need a constructor because we zero-clear it as part of ImGuiWindow and all frame-temporary data are setup on Begin)
WindowTempData :: struct {
	// Layout
	CursorPos:               Vec2, // Current emitting position, in absolute coordinates.
	CursorPosPrevLine:       Vec2,
	CursorStartPos:          Vec2, // Initial position after Begin(), generally ~ window position + WindowPadding.
	CursorMaxPos:            Vec2, // Used to implicitly calculate ContentSize at the beginning of next frame, for scrolling range and auto-resize. Always growing during the frame.
	IdealMaxPos:             Vec2, // Used to implicitly calculate ContentSizeIdeal at the beginning of next frame, for auto-resize only. Always growing during the frame.
	CurrLineSize:            Vec2,
	PrevLineSize:            Vec2,
	CurrLineTextBaseOffset:  f32,  // Baseline offset (0.0f by default on a new line, generally == style.FramePadding.y when a framed item has been added).
	PrevLineTextBaseOffset:  f32,
	IsSameLine:              bool,
	IsSetPos:                bool,
	Indent:                  Vec1, // Indentation / start position from left of window (increased by TreePush/TreePop, etc.)
	ColumnsOffset:           Vec1, // Offset to the current column (if ColumnsCurrent > 0). FIXME: This and the above should be a stack to allow use cases like Tree->Column->Tree. Need revamp columns API.
	GroupOffset:             Vec1,
	CursorStartPosLossyness: Vec2, // Record the loss of precision of CursorStartPos due to really large scrolling amount. This is used by clipper to compensate and fix the most common use case of large scroll area.
	// Keyboard/Gamepad navigation
	NavLayerCurrent:          NavLayer, // Current layer, 0..31 (we currently only use 0..1)
	NavLayersActiveMask:      c.short,  // Which layers have been written to (result from previous frame)
	NavLayersActiveMaskNext:  c.short,  // Which layers have been written to (accumulator for current frame)
	NavIsScrollPushableX:     bool,     // Set when current work location may be scrolled horizontally when moving left / right. This is generally always true UNLESS within a column.
	NavHideHighlightOneFrame: bool,
	NavWindowHasScrollY:      bool,     // Set per window when scrolling can be used (== ScrollMax.y > 0.0f)
	// Miscellaneous
	MenuBarAppending:          bool,             // FIXME: Remove this
	MenuBarOffset:             Vec2,             // MenuBarOffset.x is sort of equivalent of a per-layer CursorPos.x, saved/restored as we switch to the menu bar. The only situation when MenuBarOffset.y is > 0 if when (SafeAreaPadding.y > FramePadding.y), often used on TVs.
	MenuColumns:               MenuColumns,      // Simplified columns storage for menu items measurement
	TreeDepth:                 c.int,            // Current tree depth.
	TreeHasStackDataDepthMask: u32,              // Store whether given depth has ImGuiTreeNodeStackData data. Could be turned into a ImU64 if necessary.
	ChildWindows:              Vector_WindowPtr,
	StateStorage:              ^Storage,         // Current persistent per-window storage (store e.g. tree node open/close state)
	CurrentColumns:            ^OldColumns,      // Current columns set
	CurrentTableIdx:           c.int,            // Current table index (into g.Tables)
	LayoutType_:               LayoutType,
	ParentLayoutType:          LayoutType,       // Layout type of parent window at the time of Begin()
	ModalDimBgColor:           u32,
	// Local parameters stacks
	// We store the current settings outside of the vectors to increase memory locality (reduce cache misses). The vectors are rarely modified. Also it allows us to not heap allocate for short-lived windows which are not using those settings.
	ItemWidth:        f32,          // Current item width (>0.0: width in pixels, <0.0: align xx pixels to the right of window).
	TextWrapPos:      f32,          // Current text wrap pos.
	ItemWidthStack:   Vector_float, // Store item widths to restore (attention: .back() is not == ItemWidth)
	TextWrapPosStack: Vector_float, // Store text wrap pos to restore (attention: .back() is not == TextWrapPos)
}

// Storage for one window
Window :: struct {
	Ctx:                                ^Context,       // Parent UI context (needs to be set explicitly by parent).
	Name:                               cstring,        // Window name, owned by the window.
	ID_:                                ID,             // == ImHashStr(Name)
	Flags:                              WindowFlags,    // See enum ImGuiWindowFlags_
	FlagsPreviousFrame:                 WindowFlags,    // See enum ImGuiWindowFlags_
	ChildFlags:                         ChildFlags,     // Set when window is a child window. See enum ImGuiChildFlags_
	WindowClass:                        WindowClass,    // Advanced users only. Set with SetNextWindowClass()
	Viewport:                           ^ViewportP,     // Always set in Begin(). Inactive windows may have a NULL value here if their viewport was discarded.
	ViewportId:                         ID,             // We backup the viewport id (since the viewport may disappear or never be created if the window is inactive)
	ViewportPos:                        Vec2,           // We backup the viewport position (since the viewport may disappear or never be created if the window is inactive)
	ViewportAllowPlatformMonitorExtend: c.int,          // Reset to -1 every frame (index is guaranteed to be valid between NewFrame..EndFrame), only used in the Appearing frame of a tooltip/popup to enforce clamping to a given monitor
	Pos:                                Vec2,           // Position (always rounded-up to nearest pixel)
	Size:                               Vec2,           // Current size (==SizeFull or collapsed title bar size)
	SizeFull:                           Vec2,           // Size when non collapsed
	ContentSize:                        Vec2,           // Size of contents/scrollable client area (calculated from the extents reach of the cursor) from previous frame. Does not include window decoration or window padding.
	ContentSizeIdeal:                   Vec2,
	ContentSizeExplicit:                Vec2,           // Size of contents/scrollable client area explicitly request by the user via SetNextWindowContentSize().
	WindowPadding:                      Vec2,           // Window padding at the time of Begin().
	WindowRounding:                     f32,            // Window rounding at the time of Begin(). May be clamped lower to avoid rendering artifacts with title bar, menu bar etc.
	WindowBorderSize:                   f32,            // Window border size at the time of Begin().
	TitleBarHeight:                     f32,            // Note that those used to be function before 2024/05/28. If you have old code calling TitleBarHeight() you can change it to TitleBarHeight.
	MenuBarHeight:                      f32,            // Note that those used to be function before 2024/05/28. If you have old code calling TitleBarHeight() you can change it to TitleBarHeight.
	DecoOuterSizeX1:                    f32,            // Left/Up offsets. Sum of non-scrolling outer decorations (X1 generally == 0.0f. Y1 generally = TitleBarHeight + MenuBarHeight). Locked during Begin().
	DecoOuterSizeY1:                    f32,            // Left/Up offsets. Sum of non-scrolling outer decorations (X1 generally == 0.0f. Y1 generally = TitleBarHeight + MenuBarHeight). Locked during Begin().
	DecoOuterSizeX2:                    f32,            // Right/Down offsets (X2 generally == ScrollbarSize.x, Y2 == ScrollbarSizes.y).
	DecoOuterSizeY2:                    f32,            // Right/Down offsets (X2 generally == ScrollbarSize.x, Y2 == ScrollbarSizes.y).
	DecoInnerSizeX1:                    f32,            // Applied AFTER/OVER InnerRect. Specialized for Tables as they use specialized form of clipping and frozen rows/columns are inside InnerRect (and not part of regular decoration sizes).
	DecoInnerSizeY1:                    f32,            // Applied AFTER/OVER InnerRect. Specialized for Tables as they use specialized form of clipping and frozen rows/columns are inside InnerRect (and not part of regular decoration sizes).
	NameBufLen:                         c.int,          // Size of buffer storing Name. May be larger than strlen(Name)!
	MoveId:                             ID,             // == window->GetID("#MOVE")
	TabId:                              ID,             // == window->GetID("#TAB")
	ChildId:                            ID,             // ID of corresponding item in parent window (for navigation to return from child window to parent window)
	PopupId:                            ID,             // ID in the popup stack when this window is used as a popup/menu (because we use generic Name/ID for recycling)
	Scroll:                             Vec2,
	ScrollMax:                          Vec2,
	ScrollTarget:                       Vec2,           // target scroll position. stored as cursor position with scrolling canceled out, so the highest point is always 0.0f. (FLT_MAX for no change)
	ScrollTargetCenterRatio:            Vec2,           // 0.0f = scroll so that target position is at top, 0.5f = scroll so that target position is centered
	ScrollTargetEdgeSnapDist:           Vec2,           // 0.0f = no snapping, >0.0f snapping threshold
	ScrollbarSizes:                     Vec2,           // Size taken by each scrollbars on their smaller axis. Pay attention! ScrollbarSizes.x == width of the vertical scrollbar, ScrollbarSizes.y = height of the horizontal scrollbar.
	ScrollbarX:                         bool,           // Are scrollbars visible?
	ScrollbarY:                         bool,           // Are scrollbars visible?
	ViewportOwned:                      bool,
	Active:                             bool,           // Set to true on Begin(), unless Collapsed
	WasActive:                          bool,
	WriteAccessed:                      bool,           // Set to true when any widget access the current window
	Collapsed:                          bool,           // Set when collapsing window to become only title-bar
	WantCollapseToggle:                 bool,
	SkipItems:                          bool,           // Set when items can safely be all clipped (e.g. window not visible or collapsed)
	SkipRefresh:                        bool,           // [EXPERIMENTAL] Reuse previous frame drawn contents, Begin() returns false.
	Appearing:                          bool,           // Set during the frame where the window is appearing (or re-appearing)
	Hidden:                             bool,           // Do not display (== HiddenFrames*** > 0)
	IsFallbackWindow:                   bool,           // Set on the "Debug##Default" window.
	IsExplicitChild:                    bool,           // Set when passed _ChildWindow, left to false by BeginDocked()
	HasCloseButton:                     bool,           // Set when the window has a close button (p_open != NULL)
	ResizeBorderHovered:                c.char,         // Current border being hovered for resize (-1: none, otherwise 0-3)
	ResizeBorderHeld:                   c.char,         // Current border being held for resize (-1: none, otherwise 0-3)
	BeginCount:                         c.short,        // Number of Begin() during the current frame (generally 0 or 1, 1+ if appending via multiple Begin/End pairs)
	BeginCountPreviousFrame:            c.short,        // Number of Begin() during the previous frame
	BeginOrderWithinParent:             c.short,        // Begin() order within immediate parent window, if we are a child window. Otherwise 0.
	BeginOrderWithinContext:            c.short,        // Begin() order within entire imgui context. This is mostly used for debugging submission order related issues.
	FocusOrder:                         c.short,        // Order within WindowsFocusOrder[], altered when windows are focused.
	AutoFitFramesX:                     i8,
	AutoFitFramesY:                     i8,
	AutoFitOnlyGrows:                   bool,
	AutoPosLastDirection:               Dir,
	HiddenFramesCanSkipItems:           i8,             // Hide the window for N frames
	HiddenFramesCannotSkipItems:        i8,             // Hide the window for N frames while allowing items to be submitted so we can measure their size
	HiddenFramesForRenderOnly:          i8,             // Hide the window until frame N at Render() time only
	DisableInputsFrames:                i8,             // Disable window interactions for N frames
	SetWindowPosAllowFlags:             Cond,           // store acceptable condition flags for SetNextWindowPos() use.
	SetWindowSizeAllowFlags:            Cond,           // store acceptable condition flags for SetNextWindowSize() use.
	SetWindowCollapsedAllowFlags:       Cond,           // store acceptable condition flags for SetNextWindowCollapsed() use.
	SetWindowDockAllowFlags:            Cond,           // store acceptable condition flags for SetNextWindowDock() use.
	SetWindowPosVal:                    Vec2,           // store window position when using a non-zero Pivot (position set needs to be processed when we know the window size)
	SetWindowPosPivot:                  Vec2,           // store window pivot for positioning. ImVec2(0, 0) when positioning from top-left corner; ImVec2(0.5f, 0.5f) for centering; ImVec2(1, 1) for bottom right.
	IDStack:                            Vector_ID,      // ID stack. ID are hashes seeded with the value at the top of the stack. (In theory this should be in the TempData structure)
	DC:                                 WindowTempData, // Temporary per-window data, reset at the beginning of the frame. This used to be called ImGuiDrawContext, hence the "DC" variable name.
	// The best way to understand what those rectangles are is to use the 'Metrics->Tools->Show Windows Rectangles' viewer.
	// The main 'OuterRect', omitted as a field, is window->Rect().
	OuterRectClipped:               Rect,                 // == Window->Rect() just after setup in Begin(). == window->Rect() for root window.
	InnerRect:                      Rect,                 // Inner rectangle (omit title bar, menu bar, scroll bar)
	InnerClipRect:                  Rect,                 // == InnerRect shrunk by WindowPadding*0.5f on each side, clipped within viewport or parent clip rect.
	WorkRect:                       Rect,                 // Initially covers the whole scrolling region. Reduced by containers e.g columns/tables when active. Shrunk by WindowPadding*1.0f on each side. This is meant to replace ContentRegionRect over time (from 1.71+ onward).
	ParentWorkRect:                 Rect,                 // Backup of WorkRect before entering a container such as columns/tables. Used by e.g. SpanAllColumns functions to easily access. Stacked containers are responsible for maintaining this. // FIXME-WORKRECT: Could be a stack?
	ClipRect:                       Rect,                 // Current clipping/scissoring rectangle, evolve as we are using PushClipRect(), etc. == DrawList->clip_rect_stack.back().
	ContentRegionRect:              Rect,                 // FIXME: This is currently confusing/misleading. It is essentially WorkRect but not handling of scrolling. We currently rely on it as right/bottom aligned sizing operation need some size to rely on.
	HitTestHoleSize:                Vec2ih,               // Define an optional rectangular hole where mouse will pass-through the window.
	HitTestHoleOffset:              Vec2ih,
	LastFrameActive:                c.int,                // Last frame number the window was Active.
	LastFrameJustFocused:           c.int,                // Last frame number the window was made Focused.
	LastTimeActive:                 f32,                  // Last timestamp the window was Active (using float as we don't need high precision there)
	ItemWidthDefault:               f32,
	StateStorage:                   Storage,
	ColumnsStorage:                 Vector_OldColumns,
	FontWindowScale:                f32,                  // User scale multiplier per-window, via SetWindowFontScale()
	FontDpiScale:                   f32,
	SettingsOffset:                 c.int,                // Offset into SettingsWindows[] (offsets are always valid as we only grow the array from the back)
	DrawList_:                      ^DrawList,            // == &DrawListInst (for backward compatibility reason with code using imgui_internal.h we keep this a pointer)
	DrawListInst:                   DrawList,
	ParentWindow:                   ^Window,              // If we are a child _or_ popup _or_ docked window, this is pointing to our parent. Otherwise NULL.
	ParentWindowInBeginStack:       ^Window,
	RootWindow:                     ^Window,              // Point to ourself or first ancestor that is not a child window. Doesn't cross through popups/dock nodes.
	RootWindowPopupTree:            ^Window,              // Point to ourself or first ancestor that is not a child window. Cross through popups parent<>child.
	RootWindowDockTree:             ^Window,              // Point to ourself or first ancestor that is not a child window. Cross through dock nodes.
	RootWindowForTitleBarHighlight: ^Window,              // Point to ourself or first ancestor which will display TitleBgActive color when this window is active.
	RootWindowForNav:               ^Window,              // Point to ourself or first ancestor which doesn't have the NavFlattened flag.
	ParentWindowForFocusRoute:      ^Window,              // Set to manual link a window to its logical parent so that Shortcut() chain are honoerd (e.g. Tool linked to Document)
	NavLastChildNavWindow:          ^Window,              // When going to the menu bar, we remember the child window we came from. (This could probably be made implicit if we kept g.Windows sorted by last focused including child window.)
	NavLastIds:                     [NavLayer.COUNT]ID,   // Last known NavId for this window, per layer (0/1)
	NavRectRel:                     [NavLayer.COUNT]Rect, // Reference rectangle, in window relative space
	NavPreferredScoringPosRel:      [NavLayer.COUNT]Vec2, // Preferred X/Y position updated when moving on a given axis, reset to FLT_MAX.
	NavRootFocusScopeId:            ID,                   // Focus Scope ID at the time of Begin()
	MemoryDrawListIdxCapacity:      c.int,                // Backup of last idx/vtx count, so when waking up the window we can preallocate and avoid iterative alloc/copy
	MemoryDrawListVtxCapacity:      c.int,
	MemoryCompacted:                bool,                 // Set when window extraneous data have been garbage collected
	// Docking
	DockIsActive:           bool,            // When docking artifacts are actually visible. When this is set, DockNode is guaranteed to be != NULL. ~~ (DockNode != NULL) && (DockNode->Windows.Size > 1).
	DockNodeIsVisible:      bool,
	DockTabIsVisible:       bool,            // Is our window visible this frame? ~~ is the corresponding tab selected?
	DockTabWantClose:       bool,
	DockOrder:              c.short,         // Order of the last time the window was visible within its DockNode. This is used to reorder windows that are reappearing on the same frame. Same value between windows that were active and windows that were none are possible.
	DockStyle:              WindowDockStyle,
	DockNode_:              ^DockNode,       // Which node are we docked into. Important: Prefer testing DockIsActive in many cases as this will still be set when the dock node is hidden.
	DockNodeAsHost:         ^DockNode,       // Which node are we owning (for parent windows)
	DockId:                 ID,              // Backup of last valid DockNode->ID, so single window remember their dock node id even when they are not bound any more
	DockTabItemStatusFlags: ItemStatusFlags,
	DockTabItemRect:        Rect,
}

// Storage for one active tab item (sizeof() 48 bytes)
TabItem :: struct {
	ID_:               ID,
	Flags:             TabItemFlags,
	Window_:           ^Window,      // When TabItem is part of a DockNode's TabBar, we hold on to a window.
	LastFrameVisible:  c.int,
	LastFrameSelected: c.int,        // This allows us to infer an ordered list of the last activated tabs with little maintenance
	Offset:            f32,          // Position relative to beginning of tab
	Width:             f32,          // Width currently displayed
	ContentWidth:      f32,          // Width of label, stored during BeginTabItem() call
	RequestedWidth:    f32,          // Width optionally requested by caller, -1.0f is unused
	NameOffset:        i32,          // When Window==NULL, offset to name within parent ImGuiTabBar::TabsNames
	BeginOrder:        i16,          // BeginTabItem() order, used to re-order tabs after toggling ImGuiTabBarFlags_Reorderable
	IndexDuringLayout: i16,          // Index only used during TabBarLayout(). Tabs gets reordered so 'Tabs[n].IndexDuringLayout == n' but may mismatch during additions.
	WantClose:         bool,         // Marked as closed by SetTabItemClosed()
}

// Storage for a tab bar (sizeof() 160 bytes)
TabBar :: struct {
	Window_:                         ^Window,
	Tabs:                            Vector_TabItem,
	Flags:                           TabBarFlags,
	ID_:                             ID,             // Zero for tab-bars used by docking
	SelectedTabId:                   ID,             // Selected tab/window
	NextSelectedTabId:               ID,             // Next selected tab/window. Will also trigger a scrolling animation
	VisibleTabId:                    ID,             // Can occasionally be != SelectedTabId (e.g. when previewing contents for CTRL+TAB preview)
	CurrFrameVisible:                c.int,
	PrevFrameVisible:                c.int,
	BarRect:                         Rect,
	CurrTabsContentsHeight:          f32,
	PrevTabsContentsHeight:          f32,            // Record the height of contents submitted below the tab bar
	WidthAllTabs:                    f32,            // Actual width of all tabs (locked during layout)
	WidthAllTabsIdeal:               f32,            // Ideal width if all tabs were visible and not clipped
	ScrollingAnim:                   f32,
	ScrollingTarget:                 f32,
	ScrollingTargetDistToVisibility: f32,
	ScrollingSpeed:                  f32,
	ScrollingRectMinX:               f32,
	ScrollingRectMaxX:               f32,
	SeparatorMinX:                   f32,
	SeparatorMaxX:                   f32,
	ReorderRequestTabId:             ID,
	ReorderRequestOffset:            i16,
	BeginCount:                      i8,
	WantLayout:                      bool,
	VisibleTabWasSubmitted:          bool,
	TabsAddedNew:                    bool,           // Set to true when a new tab item or button has been added to the tab bar during last frame
	TabsActiveCount:                 i16,            // Number of tabs submitted this frame.
	LastTabItemIdx:                  i16,            // Index of last BeginTabItem() tab for use by EndTabItem()
	ItemSpacingY:                    f32,
	FramePadding:                    Vec2,           // style.FramePadding locked at the time of BeginTabBar()
	BackupCursorPos:                 Vec2,
	TabsNames:                       TextBuffer,     // For non-docking tab bar we re-append names in a contiguous buffer.
}

// [Internal] sizeof() ~ 112
// We use the terminology "Enabled" to refer to a column that is not Hidden by user/api.
// We use the terminology "Clipped" to refer to a column that is out of sight because of scrolling/clipping.
// This is in contrast with some user-facing api such as IsItemVisible() / IsRectVisible() which use "Visible" to mean "not clipped".
TableColumn :: struct {
	Flags:                    TableColumnFlags,    // Flags after some patching (not directly same as provided by user). See ImGuiTableColumnFlags_
	WidthGiven:               f32,                 // Final/actual width visible == (MaxX - MinX), locked in TableUpdateLayout(). May be > WidthRequest to honor minimum width, may be < WidthRequest to honor shrinking columns down in tight space.
	MinX:                     f32,                 // Absolute positions
	MaxX:                     f32,
	WidthRequest:             f32,                 // Master width absolute value when !(Flags & _WidthStretch). When Stretch this is derived every frame from StretchWeight in TableUpdateLayout()
	WidthAuto:                f32,                 // Automatic width
	WidthMax:                 f32,                 // Maximum width (FIXME: overwritten by each instance)
	StretchWeight:            f32,                 // Master width weight when (Flags & _WidthStretch). Often around ~1.0f initially.
	InitStretchWeightOrWidth: f32,                 // Value passed to TableSetupColumn(). For Width it is a content width (_without padding_).
	ClipRect:                 Rect,                // Clipping rectangle for the column
	UserID:                   ID,                  // Optional, value passed to TableSetupColumn()
	WorkMinX:                 f32,                 // Contents region min ~(MinX + CellPaddingX + CellSpacingX1) == cursor start position when entering column
	WorkMaxX:                 f32,                 // Contents region max ~(MaxX - CellPaddingX - CellSpacingX2)
	ItemWidth:                f32,                 // Current item width for the column, preserved across rows
	ContentMaxXFrozen:        f32,                 // Contents maximum position for frozen rows (apart from headers), from which we can infer content width.
	ContentMaxXUnfrozen:      f32,
	ContentMaxXHeadersUsed:   f32,                 // Contents maximum position for headers rows (regardless of freezing). TableHeader() automatically softclip itself + report ideal desired size, to avoid creating extraneous draw calls
	ContentMaxXHeadersIdeal:  f32,
	NameOffset:               i16,                 // Offset into parent ColumnsNames[]
	DisplayOrder:             TableColumnIdx,      // Index within Table's IndexToDisplayOrder[] (column may be reordered by users)
	IndexWithinEnabledSet:    TableColumnIdx,      // Index within enabled/visible set (<= IndexToDisplayOrder)
	PrevEnabledColumn:        TableColumnIdx,      // Index of prev enabled/visible column within Columns[], -1 if first enabled/visible column
	NextEnabledColumn:        TableColumnIdx,      // Index of next enabled/visible column within Columns[], -1 if last enabled/visible column
	SortOrder:                TableColumnIdx,      // Index of this column within sort specs, -1 if not sorting on this column, 0 for single-sort, may be >0 on multi-sort
	DrawChannelCurrent:       TableDrawChannelIdx, // Index within DrawSplitter.Channels[]
	DrawChannelFrozen:        TableDrawChannelIdx, // Draw channels for frozen rows (often headers)
	DrawChannelUnfrozen:      TableDrawChannelIdx, // Draw channels for unfrozen rows
	IsEnabled:                bool,                // IsUserEnabled && (Flags & ImGuiTableColumnFlags_Disabled) == 0
	IsUserEnabled:            bool,                // Is the column not marked Hidden by the user? (unrelated to being off view, e.g. clipped by scrolling).
	IsUserEnabledNextFrame:   bool,
	IsVisibleX:               bool,                // Is actually in view (e.g. overlapping the host window clipping rectangle, not scrolled).
	IsVisibleY:               bool,
	IsRequestOutput:          bool,                // Return value for TableSetColumnIndex() / TableNextColumn(): whether we request user to output contents or not.
	IsSkipItems:              bool,                // Do we want item submissions to this column to be completely ignored (no layout will happen).
	IsPreserveWidthAuto:      bool,
	NavLayerCurrent:          i8,                  // ImGuiNavLayer in 1 byte
	AutoFitQueue:             u8,                  // Queue of 8 values for the next 8 frames to request auto-fit
	CannotSkipItemsQueue:     u8,                  // Queue of 8 values for the next 8 frames to disable Clipped/SkipItem
	SortDirection:            u8,                  // ImGuiSortDirection_Ascending or ImGuiSortDirection_Descending
	SortDirectionsAvailCount: u8,                  // Number of available sort directions (0 to 3)
	SortDirectionsAvailMask:  u8,                  // Mask of available sort directions (1-bit each)
	SortDirectionsAvailList:  u8,                  // Ordered list of available sort directions (2-bits each, total 8-bits)
}

// Transient cell data stored per row.
// sizeof() ~ 6 bytes
TableCellData :: struct {
	BgColor: u32,            // Actual color
	Column:  TableColumnIdx, // Column number
}

// Parameters for TableAngledHeadersRowEx()
// This may end up being refactored for more general purpose.
// sizeof() ~ 12 bytes
TableHeaderData :: struct {
	Index:     TableColumnIdx, // Column index
	TextColor: u32,
	BgColor0:  u32,
	BgColor1:  u32,
}

// Per-instance data that needs preserving across frames (seemingly most others do not need to be preserved aside from debug needs. Does that means they could be moved to ImGuiTableTempData?)
// sizeof() ~ 24 bytes
TableInstanceData :: struct {
	TableInstanceID:         ID,
	LastOuterHeight:         f32,   // Outer height from last frame
	LastTopHeadersRowHeight: f32,   // Height of first consecutive header rows from last frame (FIXME: this is used assuming consecutive headers are in same frozen set)
	LastFrozenHeight:        f32,   // Height of frozen section from last frame
	HoveredRowLast:          c.int, // Index of row which was hovered last frame.
	HoveredRowNext:          c.int, // Index of row hovered this frame, set after encountering it.
}

// sizeof() ~ 592 bytes + heap allocs described in TableBeginInitMemory()
Table :: struct {
	ID_:                        ID,
	Flags:                      TableFlags,
	RawData:                    rawptr,                      // Single allocation to hold Columns[], DisplayOrderToIndex[] and RowCellData[]
	TempData:                   ^TableTempData,              // Transient data while table is active. Point within g.CurrentTableStack[]
	Columns:                    Span_ImGuiTableColumn,       // Point within RawData[]
	DisplayOrderToIndex:        Span_ImGuiTableColumnIdx,    // Point within RawData[]. Store display order of columns (when not reordered, the values are 0...Count-1)
	RowCellData:                Span_ImGuiTableCellData,     // Point within RawData[]. Store cells background requests for current row.
	EnabledMaskByDisplayOrder:  BitArrayPtr,                 // Column DisplayOrder -> IsEnabled map
	EnabledMaskByIndex:         BitArrayPtr,                 // Column Index -> IsEnabled map (== not hidden by user/api) in a format adequate for iterating column without touching cold data
	VisibleMaskByIndex:         BitArrayPtr,                 // Column Index -> IsVisibleX|IsVisibleY map (== not hidden by user/api && not hidden by scrolling/cliprect)
	SettingsLoadedFlags:        TableFlags,                  // Which data were loaded from the .ini file (e.g. when order is not altered we won't save order)
	SettingsOffset:             c.int,                       // Offset in g.SettingsTables
	LastFrameActive:            c.int,
	ColumnsCount:               c.int,                       // Number of columns declared in BeginTable()
	CurrentRow:                 c.int,
	CurrentColumn:              c.int,
	InstanceCurrent:            i16,                         // Count of BeginTable() calls with same ID in the same frame (generally 0). This is a little bit similar to BeginCount for a window, but multiple table with same ID look are multiple tables, they are just synched.
	InstanceInteracted:         i16,                         // Mark which instance (generally 0) of the same ID is being interacted with
	RowPosY1:                   f32,
	RowPosY2:                   f32,
	RowMinHeight:               f32,                         // Height submitted to TableNextRow()
	RowCellPaddingY:            f32,                         // Top and bottom padding. Reloaded during row change.
	RowTextBaseline:            f32,
	RowIndentOffsetX:           f32,
	RowFlags:                   TableRowFlags,               // Current row flags, see ImGuiTableRowFlags_
	LastRowFlags:               TableRowFlags,
	RowBgColorCounter:          c.int,                       // Counter for alternating background colors (can be fast-forwarded by e.g clipper), not same as CurrentRow because header rows typically don't increase this.
	RowBgColor:                 [2]u32,                      // Background color override for current row.
	BorderColorStrong:          u32,
	BorderColorLight:           u32,
	BorderX1:                   f32,
	BorderX2:                   f32,
	HostIndentX:                f32,
	MinColumnWidth:             f32,
	OuterPaddingX:              f32,
	CellPaddingX:               f32,                         // Padding from each borders. Locked in BeginTable()/Layout.
	CellSpacingX1:              f32,                         // Spacing between non-bordered cells. Locked in BeginTable()/Layout.
	CellSpacingX2:              f32,
	InnerWidth:                 f32,                         // User value passed to BeginTable(), see comments at the top of BeginTable() for details.
	ColumnsGivenWidth:          f32,                         // Sum of current column width
	ColumnsAutoFitWidth:        f32,                         // Sum of ideal column width in order nothing to be clipped, used for auto-fitting and content width submission in outer window
	ColumnsStretchSumWeights:   f32,                         // Sum of weight of all enabled stretching columns
	ResizedColumnNextWidth:     f32,
	ResizeLockMinContentsX2:    f32,                         // Lock minimum contents width while resizing down in order to not create feedback loops. But we allow growing the table.
	RefScale:                   f32,                         // Reference scale to be able to rescale columns on font/dpi changes.
	AngledHeadersHeight:        f32,                         // Set by TableAngledHeadersRow(), used in TableUpdateLayout()
	AngledHeadersSlope:         f32,                         // Set by TableAngledHeadersRow(), used in TableUpdateLayout()
	OuterRect:                  Rect,                        // Note: for non-scrolling table, OuterRect.Max.y is often FLT_MAX until EndTable(), unless a height has been specified in BeginTable().
	InnerRect:                  Rect,                        // InnerRect but without decoration. As with OuterRect, for non-scrolling tables, InnerRect.Max.y is
	WorkRect:                   Rect,
	InnerClipRect:              Rect,
	BgClipRect:                 Rect,                        // We use this to cpu-clip cell background color fill, evolve during the frame as we cross frozen rows boundaries
	Bg0ClipRectForDrawCmd:      Rect,                        // Actual ImDrawCmd clip rect for BG0/1 channel. This tends to be == OuterWindow->ClipRect at BeginTable() because output in BG0/BG1 is cpu-clipped
	Bg2ClipRectForDrawCmd:      Rect,                        // Actual ImDrawCmd clip rect for BG2 channel. This tends to be a correct, tight-fit, because output to BG2 are done by widgets relying on regular ClipRect.
	HostClipRect:               Rect,                        // This is used to check if we can eventually merge our columns draw calls into the current draw call of the current window.
	HostBackupInnerClipRect:    Rect,                        // Backup of InnerWindow->ClipRect during PushTableBackground()/PopTableBackground()
	OuterWindow:                ^Window,                     // Parent window for the table
	InnerWindow:                ^Window,                     // Window holding the table data (== OuterWindow or a child window)
	ColumnsNames:               TextBuffer,                  // Contiguous buffer holding columns names
	DrawSplitter:               ^DrawListSplitter,           // Shortcut to TempData->DrawSplitter while in table. Isolate draw commands per columns to avoid switching clip rect constantly
	InstanceDataFirst:          TableInstanceData,
	InstanceDataExtra:          Vector_TableInstanceData,    // FIXME-OPT: Using a small-vector pattern would be good.
	SortSpecsSingle:            TableColumnSortSpecs,
	SortSpecsMulti:             Vector_TableColumnSortSpecs, // FIXME-OPT: Using a small-vector pattern would be good.
	SortSpecs:                  TableSortSpecs,              // Public facing sorts specs, this is what we return in TableGetSortSpecs()
	SortSpecsCount:             TableColumnIdx,
	ColumnsEnabledCount:        TableColumnIdx,              // Number of enabled columns (<= ColumnsCount)
	ColumnsEnabledFixedCount:   TableColumnIdx,              // Number of enabled columns using fixed width (<= ColumnsCount)
	DeclColumnsCount:           TableColumnIdx,              // Count calls to TableSetupColumn()
	AngledHeadersCount:         TableColumnIdx,              // Count columns with angled headers
	HoveredColumnBody:          TableColumnIdx,              // Index of column whose visible region is being hovered. Important: == ColumnsCount when hovering empty region after the right-most column!
	HoveredColumnBorder:        TableColumnIdx,              // Index of column whose right-border is being hovered (for resizing).
	HighlightColumnHeader:      TableColumnIdx,              // Index of column which should be highlighted.
	AutoFitSingleColumn:        TableColumnIdx,              // Index of single column requesting auto-fit.
	ResizedColumn:              TableColumnIdx,              // Index of column being resized. Reset when InstanceCurrent==0.
	LastResizedColumn:          TableColumnIdx,              // Index of column being resized from previous frame.
	HeldHeaderColumn:           TableColumnIdx,              // Index of column header being held.
	ReorderColumn:              TableColumnIdx,              // Index of column being reordered. (not cleared)
	ReorderColumnDir:           TableColumnIdx,              // -1 or +1
	LeftMostEnabledColumn:      TableColumnIdx,              // Index of left-most non-hidden column.
	RightMostEnabledColumn:     TableColumnIdx,              // Index of right-most non-hidden column.
	LeftMostStretchedColumn:    TableColumnIdx,              // Index of left-most stretched column.
	RightMostStretchedColumn:   TableColumnIdx,              // Index of right-most stretched column.
	ContextPopupColumn:         TableColumnIdx,              // Column right-clicked on, of -1 if opening context menu from a neutral/empty spot
	FreezeRowsRequest:          TableColumnIdx,              // Requested frozen rows count
	FreezeRowsCount:            TableColumnIdx,              // Actual frozen row count (== FreezeRowsRequest, or == 0 when no scrolling offset)
	FreezeColumnsRequest:       TableColumnIdx,              // Requested frozen columns count
	FreezeColumnsCount:         TableColumnIdx,              // Actual frozen columns count (== FreezeColumnsRequest, or == 0 when no scrolling offset)
	RowCellDataCurrent:         TableColumnIdx,              // Index of current RowCellData[] entry in current row
	DummyDrawChannel:           TableDrawChannelIdx,         // Redirect non-visible columns here.
	Bg2DrawChannelCurrent:      TableDrawChannelIdx,         // For Selectable() and other widgets drawing across columns after the freezing line. Index within DrawSplitter.Channels[]
	Bg2DrawChannelUnfrozen:     TableDrawChannelIdx,
	IsLayoutLocked:             bool,                        // Set by TableUpdateLayout() which is called when beginning the first row.
	IsInsideRow:                bool,                        // Set when inside TableBeginRow()/TableEndRow().
	IsInitializing:             bool,
	IsSortSpecsDirty:           bool,
	IsUsingHeaders:             bool,                        // Set when the first row had the ImGuiTableRowFlags_Headers flag.
	IsContextPopupOpen:         bool,                        // Set when default context menu is open (also see: ContextPopupColumn, InstanceInteracted).
	DisableDefaultContextMenu:  bool,                        // Disable default context menu contents. You may submit your own using TableBeginContextMenuPopup()/EndPopup()
	IsSettingsRequestLoad:      bool,
	IsSettingsDirty:            bool,                        // Set when table settings have changed and needs to be reported into ImGuiTableSetttings data.
	IsDefaultDisplayOrder:      bool,                        // Set when display order is unchanged from default (DisplayOrder contains 0...Count-1)
	IsResetAllRequest:          bool,
	IsResetDisplayOrderRequest: bool,
	IsUnfrozenRows:             bool,                        // Set when we got past the frozen row.
	IsDefaultSizingPolicy:      bool,                        // Set if user didn't explicitly set a sizing policy in BeginTable()
	IsActiveIdAliveBeforeTable: bool,
	IsActiveIdInTable:          bool,
	HasScrollbarYCurr:          bool,                        // Whether ANY instance of this table had a vertical scrollbar during the current frame.
	HasScrollbarYPrev:          bool,                        // Whether ANY instance of this table had a vertical scrollbar during the previous.
	MemoryCompacted:            bool,
	HostSkipItems:              bool,                        // Backup of InnerWindow->SkipItem at the end of BeginTable(), because we will overwrite InnerWindow->SkipItem on a per-column basis
}

// Transient data that are only needed between BeginTable() and EndTable(), those buffers are shared (1 per level of stacked table).
// - Accessing those requires chasing an extra pointer so for very frequently used data we leave them in the main table structure.
// - We also leave out of this structure data that tend to be particularly useful for debugging/metrics.
// FIXME-TABLE: more transient data could be stored in a stacked ImGuiTableTempData: e.g. SortSpecs.
// sizeof() ~ 136 bytes.
TableTempData :: struct {
	TableIndex:                   c.int,                  // Index in g.Tables.Buf[] pool
	LastTimeActive:               f32,                    // Last timestamp this structure was used
	AngledHeadersExtraWidth:      f32,                    // Used in EndTable()
	AngledHeadersRequests:        Vector_TableHeaderData, // Used in TableAngledHeadersRow()
	UserOuterSize:                Vec2,                   // outer_size.x passed to BeginTable()
	DrawSplitter:                 DrawListSplitter,
	HostBackupWorkRect:           Rect,                   // Backup of InnerWindow->WorkRect at the end of BeginTable()
	HostBackupParentWorkRect:     Rect,                   // Backup of InnerWindow->ParentWorkRect at the end of BeginTable()
	HostBackupPrevLineSize:       Vec2,                   // Backup of InnerWindow->DC.PrevLineSize at the end of BeginTable()
	HostBackupCurrLineSize:       Vec2,                   // Backup of InnerWindow->DC.CurrLineSize at the end of BeginTable()
	HostBackupCursorMaxPos:       Vec2,                   // Backup of InnerWindow->DC.CursorMaxPos at the end of BeginTable()
	HostBackupColumnsOffset:      Vec1,                   // Backup of OuterWindow->DC.ColumnsOffset at the end of BeginTable()
	HostBackupItemWidth:          f32,                    // Backup of OuterWindow->DC.ItemWidth at the end of BeginTable()
	HostBackupItemWidthStackSize: c.int,                  //Backup of OuterWindow->DC.ItemWidthStack.Size at the end of BeginTable()
}

// sizeof() ~ 12
TableColumnSettings :: struct {
	WidthOrWeight: f32,
	UserID:        ID,
	Index:         TableColumnIdx,
	DisplayOrder:  TableColumnIdx,
	SortOrder:     TableColumnIdx,
	SortDirection: u8,
	IsEnabled:     u8,             // "Visible" in ini file
	IsStretch:     u8,
}

// This is designed to be stored in a single ImChunkStream (1 header followed by N ImGuiTableColumnSettings, etc.)
TableSettings :: struct {
	ID_:             ID,             // Set to 0 to invalidate/delete the setting
	SaveFlags:       TableFlags,     // Indicate data we want to save using the Resizable/Reorderable/Sortable/Hideable flags (could be using its own flags..)
	RefScale:        f32,            // Reference scale to be able to rescale columns on font/dpi changes.
	ColumnsCount:    TableColumnIdx,
	ColumnsCountMax: TableColumnIdx, // Maximum number of columns this settings instance can store, we can recycle a settings instance with lower number of columns but not higher
	WantApply:       bool,           // Set when loaded from .ini data (to enable merging/loading .ini data into an already running context)
}

// This structure is likely to evolve as we add support for incremental atlas updates.
// Conceptually this could be in ImGuiPlatformIO, but we are far from ready to make this public.
FontBuilderIO :: struct {
	FontBuilder_Build: proc "c" (atlas: ^FontAtlas) -> bool,
}


////////////////////////////////////////////////////////////
// FUNCTIONS
////////////////////////////////////////////////////////////

@(default_calling_convention="c")
foreign lib {
	// Helpers: Hashing
	@(link_name="cImHashData") cImHashData :: proc(data: rawptr, data_size: c.size_t, seed: ID = {}) -> ID       ---
	@(link_name="cImHashStr")  cImHashStr  :: proc(data: cstring, data_size: c.size_t = {}, seed: ID = {}) -> ID ---
	// Helpers: Color Blending
	@(link_name="cImAlphaBlendColors") cImAlphaBlendColors :: proc(col_a: u32, col_b: u32) -> u32 ---
	// Helpers: Bit manipulation
	@(link_name="cImIsPowerOfTwo")      cImIsPowerOfTwo      :: proc(v: c.int) -> bool  ---
	@(link_name="cImIsPowerOfTwoImU64") cImIsPowerOfTwoImU64 :: proc(v: u64) -> bool    ---
	@(link_name="cImUpperPowerOfTwo")   cImUpperPowerOfTwo   :: proc(v: c.int) -> c.int ---
	// Helpers: String
	@(link_name="cImStricmp")       cImStricmp       :: proc(str1: cstring, str2: cstring) -> c.int                                                     --- // Case insensitive compare.
	@(link_name="cImStrnicmp")      cImStrnicmp      :: proc(str1: cstring, str2: cstring, count: c.size_t) -> c.int                                    --- // Case insensitive compare to a certain count.
	@(link_name="cImStrncpy")       cImStrncpy       :: proc(dst: cstring, src: cstring, count: c.size_t)                                               --- // Copy to a certain count and always zero terminate (strncpy doesn't).
	@(link_name="cImStrdup")        cImStrdup        :: proc(str: cstring) -> cstring                                                                   --- // Duplicate a string.
	@(link_name="cImStrdupcpy")     cImStrdupcpy     :: proc(dst: cstring, p_dst_size: ^c.size_t, str: cstring) -> cstring                              --- // Copy in provided buffer, recreate buffer if needed.
	@(link_name="cImStrchrRange")   cImStrchrRange   :: proc(str_begin: cstring, str_end: cstring, _c: c.char) -> cstring                               --- // Find first occurrence of 'c' in string range.
	@(link_name="cImStreolRange")   cImStreolRange   :: proc(str: cstring, str_end: cstring) -> cstring                                                 --- // End end-of-line
	@(link_name="cImStristr")       cImStristr       :: proc(haystack: cstring, haystack_end: cstring, needle: cstring, needle_end: cstring) -> cstring --- // Find a substring in a string range.
	@(link_name="cImStrTrimBlanks") cImStrTrimBlanks :: proc(str: cstring)                                                                              --- // Remove leading and trailing blanks from a buffer.
	@(link_name="cImStrSkipBlank")  cImStrSkipBlank  :: proc(str: cstring) -> cstring                                                                   --- // Find first non-blank character.
	@(link_name="cImStrlenW")       cImStrlenW       :: proc(str: ^Wchar) -> c.int                                                                      --- // Computer string length (ImWchar string)
	@(link_name="cImStrbol")        cImStrbol        :: proc(buf_mid_line: cstring, buf_begin: cstring) -> cstring                                      --- // Find beginning-of-line
	@(link_name="cImToUpper")       cImToUpper       :: proc(_c: c.char) -> c.char                                                                      ---
	@(link_name="cImCharIsBlankA")  cImCharIsBlankA  :: proc(_c: c.char) -> bool                                                                        ---
	@(link_name="cImCharIsBlankW")  cImCharIsBlankW  :: proc(_c: c.uint) -> bool                                                                        ---
	@(link_name="cImCharIsXdigitA") cImCharIsXdigitA :: proc(_c: c.char) -> bool                                                                        ---
	// Helpers: Formatting
	@(link_name="cImFormatString")                   cImFormatString                   :: proc(buf: cstring, buf_size: c.size_t, fmt: cstring, #c_vararg args: ..any) -> c.int ---
	@(link_name="cImFormatStringToTempBuffer")       cImFormatStringToTempBuffer       :: proc(out_buf: ^cstring, out_buf_end: ^cstring, fmt: cstring, #c_vararg args: ..any)  ---
	@(link_name="cImParseFormatFindStart")           cImParseFormatFindStart           :: proc(format: cstring) -> cstring                                                     ---
	@(link_name="cImParseFormatFindEnd")             cImParseFormatFindEnd             :: proc(format: cstring) -> cstring                                                     ---
	@(link_name="cImParseFormatTrimDecorations")     cImParseFormatTrimDecorations     :: proc(format: cstring, buf: cstring, buf_size: c.size_t) -> cstring                   ---
	@(link_name="cImParseFormatSanitizeForPrinting") cImParseFormatSanitizeForPrinting :: proc(fmt_in: cstring, fmt_out: cstring, fmt_out_size: c.size_t)                      ---
	@(link_name="cImParseFormatSanitizeForScanning") cImParseFormatSanitizeForScanning :: proc(fmt_in: cstring, fmt_out: cstring, fmt_out_size: c.size_t) -> cstring           ---
	@(link_name="cImParseFormatPrecision")           cImParseFormatPrecision           :: proc(format: cstring, default_value: c.int) -> c.int                                 ---
	// Helpers: UTF-8 <> wchar conversions
	@(link_name="cImTextCharToUtf8")                cImTextCharToUtf8                :: proc(out_buf: ^[5]c.char, _c: c.uint) -> cstring                                                                          --- // return out_buf
	@(link_name="cImTextStrToUtf8")                 cImTextStrToUtf8                 :: proc(out_buf: cstring, out_buf_size: c.int, in_text: ^Wchar, in_text_end: ^Wchar) -> c.int                                --- // return output UTF-8 bytes count
	@(link_name="cImTextCharFromUtf8")              cImTextCharFromUtf8              :: proc(out_char: ^c.uint, in_text: cstring, in_text_end: cstring) -> c.int                                                  --- // read one character. return input UTF-8 bytes count
	@(link_name="cImTextStrFromUtf8")               cImTextStrFromUtf8               :: proc(out_buf: ^Wchar, out_buf_size: c.int, in_text: cstring, in_text_end: cstring, in_remaining: ^cstring = nil) -> c.int --- // return input UTF-8 bytes count
	@(link_name="cImTextCountCharsFromUtf8")        cImTextCountCharsFromUtf8        :: proc(in_text: cstring, in_text_end: cstring) -> c.int                                                                     --- // return number of UTF-8 code-points (NOT bytes count)
	@(link_name="cImTextCountUtf8BytesFromChar")    cImTextCountUtf8BytesFromChar    :: proc(in_text: cstring, in_text_end: cstring) -> c.int                                                                     --- // return number of bytes to express one char in UTF-8
	@(link_name="cImTextCountUtf8BytesFromStr")     cImTextCountUtf8BytesFromStr     :: proc(in_text: ^Wchar, in_text_end: ^Wchar) -> c.int                                                                       --- // return number of bytes to express string in UTF-8
	@(link_name="cImTextFindPreviousUtf8Codepoint") cImTextFindPreviousUtf8Codepoint :: proc(in_text_start: cstring, in_text_curr: cstring) -> cstring                                                            --- // return previous UTF-8 code-point.
	@(link_name="cImTextCountLines")                cImTextCountLines                :: proc(in_text: cstring, in_text_end: cstring) -> c.int                                                                     --- // return number of lines taken by text. trailing carriage return doesn't count as an extra line.
	@(link_name="cImFileOpen")                      cImFileOpen                      :: proc(filename: cstring, mode: cstring) -> FileHandle                                                                      ---
	@(link_name="cImFileClose")                     cImFileClose                     :: proc(file: FileHandle) -> bool                                                                                            ---
	@(link_name="cImFileGetSize")                   cImFileGetSize                   :: proc(file: FileHandle) -> u64                                                                                             ---
	@(link_name="cImFileRead")                      cImFileRead                      :: proc(data: rawptr, size: u64, count: u64, file: FileHandle) -> u64                                                        ---
	@(link_name="cImFileWrite")                     cImFileWrite                     :: proc(data: rawptr, size: u64, count: u64, file: FileHandle) -> u64                                                        ---
	@(link_name="cImFileLoadToMemory")              cImFileLoadToMemory              :: proc(filename: cstring, mode: cstring, out_file_size: ^c.size_t = nil, padding_bytes: c.int = {}) -> rawptr               ---
	@(link_name="cImPow")                           cImPow                           :: proc(x: f32, y: f32) -> f32                                                                                               --- // DragBehaviorT/SliderBehaviorT uses ImPow with either float/double and need the precision
	@(link_name="cImPowDouble")                     cImPowDouble                     :: proc(x: f64, y: f64) -> f64                                                                                               ---
	@(link_name="cImLog")                           cImLog                           :: proc(x: f32) -> f32                                                                                                       --- // DragBehaviorT/SliderBehaviorT uses ImLog with either float/double and need the precision
	@(link_name="cImLogDouble")                     cImLogDouble                     :: proc(x: f64) -> f64                                                                                                       ---
	@(link_name="cImAbs")                           cImAbs                           :: proc(x: c.int) -> c.int                                                                                                   ---
	@(link_name="cImAbsFloat")                      cImAbsFloat                      :: proc(x: f32) -> f32                                                                                                       ---
	@(link_name="cImAbsDouble")                     cImAbsDouble                     :: proc(x: f64) -> f64                                                                                                       ---
	@(link_name="cImSign")                          cImSign                          :: proc(x: f32) -> f32                                                                                                       --- // Sign operator - returns -1, 0 or 1 based on sign of argument
	@(link_name="cImSignDouble")                    cImSignDouble                    :: proc(x: f64) -> f64                                                                                                       ---
	@(link_name="cImRsqrt")                         cImRsqrt                         :: proc(x: f32) -> f32                                                                                                       ---
	@(link_name="cImRsqrtDouble")                   cImRsqrtDouble                   :: proc(x: f64) -> f64                                                                                                       ---
	// - Misc maths helpers
	@(link_name="cImMin")                                    cImMin                                    :: proc(lhs: Vec2, rhs: Vec2) -> Vec2                      ---
	@(link_name="cImMax")                                    cImMax                                    :: proc(lhs: Vec2, rhs: Vec2) -> Vec2                      ---
	@(link_name="cImClamp")                                  cImClamp                                  :: proc(v: Vec2, mn: Vec2, mx: Vec2) -> Vec2               ---
	@(link_name="cImLerp")                                   cImLerp                                   :: proc(a: Vec2, b: Vec2, t: f32) -> Vec2                  ---
	@(link_name="cImLerpImVec2")                             cImLerpImVec2                             :: proc(a: Vec2, b: Vec2, t: Vec2) -> Vec2                 ---
	@(link_name="cImLerpImVec4")                             cImLerpImVec4                             :: proc(a: Vec4, b: Vec4, t: f32) -> Vec4                  ---
	@(link_name="cImSaturate")                               cImSaturate                               :: proc(f: f32) -> f32                                     ---
	@(link_name="cImLengthSqr")                              cImLengthSqr                              :: proc(lhs: Vec2) -> f32                                  ---
	@(link_name="cImLengthSqrImVec4")                        cImLengthSqrImVec4                        :: proc(lhs: Vec4) -> f32                                  ---
	@(link_name="cImInvLength")                              cImInvLength                              :: proc(lhs: Vec2, fail_value: f32) -> f32                 ---
	@(link_name="cImTrunc")                                  cImTrunc                                  :: proc(f: f32) -> f32                                     ---
	@(link_name="cImTruncImVec2")                            cImTruncImVec2                            :: proc(v: Vec2) -> Vec2                                   ---
	@(link_name="cImFloor")                                  cImFloor                                  :: proc(f: f32) -> f32                                     --- // Decent replacement for floorf()
	@(link_name="cImFloorImVec2")                            cImFloorImVec2                            :: proc(v: Vec2) -> Vec2                                   ---
	@(link_name="cImModPositive")                            cImModPositive                            :: proc(a: c.int, b: c.int) -> c.int                       ---
	@(link_name="cImDot")                                    cImDot                                    :: proc(a: Vec2, b: Vec2) -> f32                           ---
	@(link_name="cImRotate")                                 cImRotate                                 :: proc(v: Vec2, cos_a: f32, sin_a: f32) -> Vec2           ---
	@(link_name="cImLinearSweep")                            cImLinearSweep                            :: proc(current: f32, target: f32, speed: f32) -> f32      ---
	@(link_name="cImLinearRemapClamp")                       cImLinearRemapClamp                       :: proc(s0: f32, s1: f32, d0: f32, d1: f32, x: f32) -> f32 ---
	@(link_name="cImMul")                                    cImMul                                    :: proc(lhs: Vec2, rhs: Vec2) -> Vec2                      ---
	@(link_name="cImIsFloatAboveGuaranteedIntegerPrecision") cImIsFloatAboveGuaranteedIntegerPrecision :: proc(f: f32) -> bool                                    ---
	@(link_name="cImExponentialMovingAverage")               cImExponentialMovingAverage               :: proc(avg: f32, sample: f32, n: c.int) -> f32            ---
	// Helpers: Geometry
	@(link_name="cImBezierCubicCalc")                  cImBezierCubicCalc                  :: proc(p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, t: f32) -> Vec2                       ---
	@(link_name="cImBezierCubicClosestPoint")          cImBezierCubicClosestPoint          :: proc(p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, p: Vec2, num_segments: c.int) -> Vec2 --- // For curves with explicit number of segments
	@(link_name="cImBezierCubicClosestPointCasteljau") cImBezierCubicClosestPointCasteljau :: proc(p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, p: Vec2, tess_tol: f32) -> Vec2       --- // For auto-tessellated curves you can use tess_tol = style.CurveTessellationTol
	@(link_name="cImBezierQuadraticCalc")              cImBezierQuadraticCalc              :: proc(p1: Vec2, p2: Vec2, p3: Vec2, t: f32) -> Vec2                                 ---
	@(link_name="cImLineClosestPoint")                 cImLineClosestPoint                 :: proc(a: Vec2, b: Vec2, p: Vec2) -> Vec2                                            ---
	@(link_name="cImTriangleContainsPoint")            cImTriangleContainsPoint            :: proc(a: Vec2, b: Vec2, _c: Vec2, p: Vec2) -> bool                                  ---
	@(link_name="cImTriangleClosestPoint")             cImTriangleClosestPoint             :: proc(a: Vec2, b: Vec2, _c: Vec2, p: Vec2) -> Vec2                                  ---
	@(link_name="cImTriangleBarycentricCoords")        cImTriangleBarycentricCoords        :: proc(a: Vec2, b: Vec2, _c: Vec2, p: Vec2, out_u: ^f32, out_v: ^f32, out_w: ^f32)   ---
	@(link_name="cImTriangleArea")                     cImTriangleArea                     :: proc(a: Vec2, b: Vec2, _c: Vec2) -> f32                                            ---
	@(link_name="cImTriangleIsClockwise")              cImTriangleIsClockwise              :: proc(a: Vec2, b: Vec2, _c: Vec2) -> bool                                           ---
	@(link_name="ImRect_GetCenter")                    Rect_GetCenter                      :: proc(self: ^Rect) -> Vec2                                                          ---
	@(link_name="ImRect_GetSize")                      Rect_GetSize                        :: proc(self: ^Rect) -> Vec2                                                          ---
	@(link_name="ImRect_GetWidth")                     Rect_GetWidth                       :: proc(self: ^Rect) -> f32                                                           ---
	@(link_name="ImRect_GetHeight")                    Rect_GetHeight                      :: proc(self: ^Rect) -> f32                                                           ---
	@(link_name="ImRect_GetArea")                      Rect_GetArea                        :: proc(self: ^Rect) -> f32                                                           ---
	@(link_name="ImRect_GetTL")                        Rect_GetTL                          :: proc(self: ^Rect) -> Vec2                                                          --- // Top-left
	@(link_name="ImRect_GetTR")                        Rect_GetTR                          :: proc(self: ^Rect) -> Vec2                                                          --- // Top-right
	@(link_name="ImRect_GetBL")                        Rect_GetBL                          :: proc(self: ^Rect) -> Vec2                                                          --- // Bottom-left
	@(link_name="ImRect_GetBR")                        Rect_GetBR                          :: proc(self: ^Rect) -> Vec2                                                          --- // Bottom-right
	@(link_name="ImRect_Contains")                     Rect_Contains                       :: proc(self: ^Rect, p: Vec2) -> bool                                                 ---
	@(link_name="ImRect_ContainsImRect")               Rect_ContainsImRect                 :: proc(self: ^Rect, r: Rect) -> bool                                                 ---
	@(link_name="ImRect_ContainsWithPad")              Rect_ContainsWithPad                :: proc(self: ^Rect, p: Vec2, pad: Vec2) -> bool                                      ---
	@(link_name="ImRect_Overlaps")                     Rect_Overlaps                       :: proc(self: ^Rect, r: Rect) -> bool                                                 ---
	@(link_name="ImRect_Add")                          Rect_Add                            :: proc(self: ^Rect, p: Vec2)                                                         ---
	@(link_name="ImRect_AddImRect")                    Rect_AddImRect                      :: proc(self: ^Rect, r: Rect)                                                         ---
	@(link_name="ImRect_Expand")                       Rect_Expand                         :: proc(self: ^Rect, amount: f32)                                                     ---
	@(link_name="ImRect_ExpandImVec2")                 Rect_ExpandImVec2                   :: proc(self: ^Rect, amount: Vec2)                                                    ---
	@(link_name="ImRect_Translate")                    Rect_Translate                      :: proc(self: ^Rect, d: Vec2)                                                         ---
	@(link_name="ImRect_TranslateX")                   Rect_TranslateX                     :: proc(self: ^Rect, dx: f32)                                                         ---
	@(link_name="ImRect_TranslateY")                   Rect_TranslateY                     :: proc(self: ^Rect, dy: f32)                                                         ---
	@(link_name="ImRect_ClipWith")                     Rect_ClipWith                       :: proc(self: ^Rect, r: Rect)                                                         --- // Simple version, may lead to an inverted rectangle, which is fine for Contains/Overlaps test but not for display.
	@(link_name="ImRect_ClipWithFull")                 Rect_ClipWithFull                   :: proc(self: ^Rect, r: Rect)                                                         --- // Full version, ensure both points are fully clipped.
	@(link_name="ImRect_Floor")                        Rect_Floor                          :: proc(self: ^Rect)                                                                  ---
	@(link_name="ImRect_IsInverted")                   Rect_IsInverted                     :: proc(self: ^Rect) -> bool                                                          ---
	@(link_name="ImRect_ToVec4")                       Rect_ToVec4                         :: proc(self: ^Rect) -> Vec4                                                          ---
	@(link_name="cImBitArrayGetStorageSizeInBytes")    cImBitArrayGetStorageSizeInBytes    :: proc(bitcount: c.int) -> c.size_t                                                  ---
	@(link_name="cImBitArrayClearAllBits")             cImBitArrayClearAllBits             :: proc(arr: ^u32, bitcount: c.int)                                                   ---
	@(link_name="cImBitArrayTestBit")                  cImBitArrayTestBit                  :: proc(arr: ^u32, n: c.int) -> bool                                                  ---
	@(link_name="cImBitArrayClearBit")                 cImBitArrayClearBit                 :: proc(arr: ^u32, n: c.int)                                                          ---
	@(link_name="cImBitArraySetBit")                   cImBitArraySetBit                   :: proc(arr: ^u32, n: c.int)                                                          ---
	@(link_name="cImBitArraySetBitRange")              cImBitArraySetBitRange              :: proc(arr: ^u32, n: c.int, n2: c.int)                                               --- // Works on range [n..n2)
	@(link_name="ImBitVector_Create")                  BitVector_Create                    :: proc(self: ^BitVector, sz: c.int)                                                  ---
	@(link_name="ImBitVector_Clear")                   BitVector_Clear                     :: proc(self: ^BitVector)                                                             ---
	@(link_name="ImBitVector_TestBit")                 BitVector_TestBit                   :: proc(self: ^BitVector, n: c.int) -> bool                                           ---
	@(link_name="ImBitVector_SetBit")                  BitVector_SetBit                    :: proc(self: ^BitVector, n: c.int)                                                   ---
	@(link_name="ImBitVector_ClearBit")                BitVector_ClearBit                  :: proc(self: ^BitVector, n: c.int)                                                   ---
	@(link_name="ImGuiTextIndex_clear")                TextIndex_clear                     :: proc(self: ^TextIndex)                                                             ---
	@(link_name="ImGuiTextIndex_size")                 TextIndex_size                      :: proc(self: ^TextIndex) -> c.int                                                    ---
	@(link_name="ImGuiTextIndex_get_line_begin")       TextIndex_get_line_begin            :: proc(self: ^TextIndex, base: cstring, n: c.int) -> cstring                         ---
	@(link_name="ImGuiTextIndex_get_line_end")         TextIndex_get_line_end              :: proc(self: ^TextIndex, base: cstring, n: c.int) -> cstring                         ---
	@(link_name="ImGuiTextIndex_append")               TextIndex_append                    :: proc(self: ^TextIndex, base: cstring, old_size: c.int, new_size: c.int)            ---
	// Helper: ImGuiStorage
	@(link_name="cImLowerBound")                                      cImLowerBound                                    :: proc(in_begin: ^StoragePair, in_end: ^StoragePair, key: ID) -> ^StoragePair              ---
	@(link_name="ImDrawListSharedData_SetCircleTessellationMaxError") DrawListSharedData_SetCircleTessellationMaxError :: proc(self: ^DrawListSharedData, max_error: f32)                                          ---
	@(link_name="ImGuiDataVarInfo_GetVarPtr")                         DataVarInfo_GetVarPtr                            :: proc(self: ^DataVarInfo, parent: rawptr) -> rawptr                                       ---
	@(link_name="ImGuiMenuColumns_Update")                            MenuColumns_Update                               :: proc(self: ^MenuColumns, spacing: f32, window_reappearing: bool)                         ---
	@(link_name="ImGuiMenuColumns_DeclColumns")                       MenuColumns_DeclColumns                          :: proc(self: ^MenuColumns, w_icon: f32, w_label: f32, w_shortcut: f32, w_mark: f32) -> f32 ---
	@(link_name="ImGuiMenuColumns_CalcNextTotalWidth")                MenuColumns_CalcNextTotalWidth                   :: proc(self: ^MenuColumns, update_offsets: bool)                                           ---
	@(link_name="ImGuiInputTextDeactivatedState_ClearFreeMemory")     InputTextDeactivatedState_ClearFreeMemory        :: proc(self: ^InputTextDeactivatedState)                                                   ---
	@(link_name="ImGuiInputTextState_ClearText")                      InputTextState_ClearText                         :: proc(self: ^InputTextState)                                                              ---
	@(link_name="ImGuiInputTextState_ClearFreeMemory")                InputTextState_ClearFreeMemory                   :: proc(self: ^InputTextState)                                                              ---
	@(link_name="ImGuiInputTextState_OnKeyPressed")                   InputTextState_OnKeyPressed                      :: proc(self: ^InputTextState, key: c.int)                                                  --- // Cannot be inline because we call in code in stb_textedit.h implementation
	@(link_name="ImGuiInputTextState_OnCharPressed")                  InputTextState_OnCharPressed                     :: proc(self: ^InputTextState, _c: c.uint)                                                  ---
	// Cursor & Selection
	@(link_name="ImGuiInputTextState_CursorAnimReset")   InputTextState_CursorAnimReset   :: proc(self: ^InputTextState)          ---
	@(link_name="ImGuiInputTextState_CursorClamp")       InputTextState_CursorClamp       :: proc(self: ^InputTextState)          ---
	@(link_name="ImGuiInputTextState_HasSelection")      InputTextState_HasSelection      :: proc(self: ^InputTextState) -> bool  ---
	@(link_name="ImGuiInputTextState_ClearSelection")    InputTextState_ClearSelection    :: proc(self: ^InputTextState)          ---
	@(link_name="ImGuiInputTextState_GetCursorPos")      InputTextState_GetCursorPos      :: proc(self: ^InputTextState) -> c.int ---
	@(link_name="ImGuiInputTextState_GetSelectionStart") InputTextState_GetSelectionStart :: proc(self: ^InputTextState) -> c.int ---
	@(link_name="ImGuiInputTextState_GetSelectionEnd")   InputTextState_GetSelectionEnd   :: proc(self: ^InputTextState) -> c.int ---
	@(link_name="ImGuiInputTextState_SelectAll")         InputTextState_SelectAll         :: proc(self: ^InputTextState)          ---
	// Reload user buf (WIP #2890)
	// If you modify underlying user-passed const char* while active you need to call this (InputText V2 may lift this)
	//   strcpy(my_buf, "hello");
	//   if (ImGuiInputTextState* state = ImGui::GetInputTextState(id)) // id may be ImGui::GetItemID() is last item
	//       state->ReloadUserBufAndSelectAll();
	@(link_name="ImGuiInputTextState_ReloadUserBufAndSelectAll")     InputTextState_ReloadUserBufAndSelectAll     :: proc(self: ^InputTextState)                                                ---
	@(link_name="ImGuiInputTextState_ReloadUserBufAndKeepSelection") InputTextState_ReloadUserBufAndKeepSelection :: proc(self: ^InputTextState)                                                ---
	@(link_name="ImGuiInputTextState_ReloadUserBufAndMoveToEnd")     InputTextState_ReloadUserBufAndMoveToEnd     :: proc(self: ^InputTextState)                                                ---
	@(link_name="ImGuiNextWindowData_ClearFlags")                    NextWindowData_ClearFlags                    :: proc(self: ^NextWindowData)                                                ---
	@(link_name="ImGuiNextItemData_ClearFlags")                      NextItemData_ClearFlags                      :: proc(self: ^NextItemData)                                                  --- // Also cleared manually by ItemAdd()!
	@(link_name="ImGuiKeyRoutingTable_Clear")                        KeyRoutingTable_Clear                        :: proc(self: ^KeyRoutingTable)                                               ---
	@(link_name="ImGuiListClipperRange_FromIndices")                 ListClipperRange_FromIndices                 :: proc(min: c.int, max: c.int) -> ListClipperRange                           ---
	@(link_name="ImGuiListClipperRange_FromPositions")               ListClipperRange_FromPositions               :: proc(y1: f32, y2: f32, off_min: c.int, off_max: c.int) -> ListClipperRange ---
	@(link_name="ImGuiListClipperData_Reset")                        ListClipperData_Reset                        :: proc(self: ^ListClipperData, clipper: ^ListClipper)                        ---
	@(link_name="ImGuiNavItemData_Clear")                            NavItemData_Clear                            :: proc(self: ^NavItemData)                                                   ---
	@(link_name="ImGuiTypingSelectState_Clear")                      TypingSelectState_Clear                      :: proc(self: ^TypingSelectState)                                             --- // We preserve remaining data for easier debugging
	@(link_name="ImGuiMultiSelectTempData_Clear")                    MultiSelectTempData_Clear                    :: proc(self: ^MultiSelectTempData)                                           --- // Zero-clear except IO as we preserve IO.Requests[] buffer allocation.
	@(link_name="ImGuiMultiSelectTempData_ClearIO")                  MultiSelectTempData_ClearIO                  :: proc(self: ^MultiSelectTempData)                                           ---
	@(link_name="ImGuiDockNode_IsRootNode")                          DockNode_IsRootNode                          :: proc(self: ^DockNode) -> bool                                              ---
	@(link_name="ImGuiDockNode_IsDockSpace")                         DockNode_IsDockSpace                         :: proc(self: ^DockNode) -> bool                                              ---
	@(link_name="ImGuiDockNode_IsFloatingNode")                      DockNode_IsFloatingNode                      :: proc(self: ^DockNode) -> bool                                              ---
	@(link_name="ImGuiDockNode_IsCentralNode")                       DockNode_IsCentralNode                       :: proc(self: ^DockNode) -> bool                                              ---
	@(link_name="ImGuiDockNode_IsHiddenTabBar")                      DockNode_IsHiddenTabBar                      :: proc(self: ^DockNode) -> bool                                              --- // Hidden tab bar can be shown back by clicking the small triangle
	@(link_name="ImGuiDockNode_IsNoTabBar")                          DockNode_IsNoTabBar                          :: proc(self: ^DockNode) -> bool                                              --- // Never show a tab bar
	@(link_name="ImGuiDockNode_IsSplitNode")                         DockNode_IsSplitNode                         :: proc(self: ^DockNode) -> bool                                              ---
	@(link_name="ImGuiDockNode_IsLeafNode")                          DockNode_IsLeafNode                          :: proc(self: ^DockNode) -> bool                                              ---
	@(link_name="ImGuiDockNode_IsEmpty")                             DockNode_IsEmpty                             :: proc(self: ^DockNode) -> bool                                              ---
	@(link_name="ImGuiDockNode_Rect")                                DockNode_Rect                                :: proc(self: ^DockNode) -> Rect                                              ---
	@(link_name="ImGuiDockNode_SetLocalFlags")                       DockNode_SetLocalFlags                       :: proc(self: ^DockNode, flags: DockNodeFlags)                                ---
	@(link_name="ImGuiDockNode_UpdateMergedFlags")                   DockNode_UpdateMergedFlags                   :: proc(self: ^DockNode)                                                      ---
	@(link_name="ImGuiViewportP_ClearRequestFlags")                  ViewportP_ClearRequestFlags                  :: proc(self: ^ViewportP)                                                     ---
	// Calculate work rect pos/size given a set of offset (we have 1 pair of offset for rect locked from last frame data, and 1 pair for currently building rect)
	@(link_name="ImGuiViewportP_CalcWorkRectPos")  ViewportP_CalcWorkRectPos  :: proc(self: ^ViewportP, inset_min: Vec2) -> Vec2                  ---
	@(link_name="ImGuiViewportP_CalcWorkRectSize") ViewportP_CalcWorkRectSize :: proc(self: ^ViewportP, inset_min: Vec2, inset_max: Vec2) -> Vec2 ---
	@(link_name="ImGuiViewportP_UpdateWorkRect")   ViewportP_UpdateWorkRect   :: proc(self: ^ViewportP)                                           --- // Update public fields
	// Helpers to retrieve ImRect (we don't need to store BuildWorkRect as every access tend to change it, hence the code asymmetry)
	@(link_name="ImGuiViewportP_GetMainRect")      ViewportP_GetMainRect      :: proc(self: ^ViewportP) -> Rect                                  ---
	@(link_name="ImGuiViewportP_GetWorkRect")      ViewportP_GetWorkRect      :: proc(self: ^ViewportP) -> Rect                                  ---
	@(link_name="ImGuiViewportP_GetBuildWorkRect") ViewportP_GetBuildWorkRect :: proc(self: ^ViewportP) -> Rect                                  ---
	@(link_name="ImGuiWindowSettings_GetName")     WindowSettings_GetName     :: proc(self: ^WindowSettings) -> cstring                          ---
	@(link_name="ImGuiWindow_GetIDStr")            Window_GetIDStr            :: proc(self: ^Window, str: cstring, str_end: cstring = nil) -> ID ---
	@(link_name="ImGuiWindow_GetID")               Window_GetID               :: proc(self: ^Window, ptr: rawptr) -> ID                          ---
	@(link_name="ImGuiWindow_GetIDInt")            Window_GetIDInt            :: proc(self: ^Window, n: c.int) -> ID                             ---
	@(link_name="ImGuiWindow_GetIDFromPos")        Window_GetIDFromPos        :: proc(self: ^Window, p_abs: Vec2) -> ID                          ---
	@(link_name="ImGuiWindow_GetIDFromRectangle")  Window_GetIDFromRectangle  :: proc(self: ^Window, r_abs: Rect) -> ID                          ---
	// We don't use g.FontSize because the window may be != g.CurrentWindow.
	@(link_name="ImGuiWindow_Rect")                     Window_Rect                     :: proc(self: ^Window) -> Rect                        ---
	@(link_name="ImGuiWindow_CalcFontSize")             Window_CalcFontSize             :: proc(self: ^Window) -> f32                         ---
	@(link_name="ImGuiWindow_TitleBarRect")             Window_TitleBarRect             :: proc(self: ^Window) -> Rect                        ---
	@(link_name="ImGuiWindow_MenuBarRect")              Window_MenuBarRect              :: proc(self: ^Window) -> Rect                        ---
	@(link_name="ImGuiTableSettings_GetColumnSettings") TableSettings_GetColumnSettings :: proc(self: ^TableSettings) -> ^TableColumnSettings ---
	// Windows
	// We should always have a CurrentWindow in the stack (there is an implicit "Debug" window)
	// If this ever crashes because g.CurrentWindow is NULL, it means that either:
	// - ImGui::NewFrame() has never been called, which is illegal.
	// - You are calling ImGui functions after ImGui::EndFrame()/ImGui::Render() and before the next ImGui::NewFrame(), which is also illegal.
	@(link_name="ImGui_GetIOEx")                                    GetIOEx                                    :: proc(ctx: ^Context) -> ^IO                                                                            ---
	@(link_name="ImGui_GetPlatformIOEx")                            GetPlatformIOEx                            :: proc(ctx: ^Context) -> ^PlatformIO                                                                    ---
	@(link_name="ImGui_GetCurrentWindowRead")                       GetCurrentWindowRead                       :: proc() -> ^Window                                                                                     ---
	@(link_name="ImGui_GetCurrentWindow")                           GetCurrentWindow                           :: proc() -> ^Window                                                                                     ---
	@(link_name="ImGui_FindWindowByID")                             FindWindowByID                             :: proc(id: ID) -> ^Window                                                                               ---
	@(link_name="ImGui_FindWindowByName")                           FindWindowByName                           :: proc(name: cstring) -> ^Window                                                                        ---
	@(link_name="ImGui_UpdateWindowParentAndRootLinks")             UpdateWindowParentAndRootLinks             :: proc(window: ^Window, flags: WindowFlags, parent_window: ^Window)                                     ---
	@(link_name="ImGui_UpdateWindowSkipRefresh")                    UpdateWindowSkipRefresh                    :: proc(window: ^Window)                                                                                 ---
	@(link_name="ImGui_CalcWindowNextAutoFitSize")                  CalcWindowNextAutoFitSize                  :: proc(window: ^Window) -> Vec2                                                                         ---
	@(link_name="ImGui_IsWindowChildOf")                            IsWindowChildOf                            :: proc(window: ^Window, potential_parent: ^Window, popup_hierarchy: bool, dock_hierarchy: bool) -> bool ---
	@(link_name="ImGui_IsWindowWithinBeginStackOf")                 IsWindowWithinBeginStackOf                 :: proc(window: ^Window, potential_parent: ^Window) -> bool                                              ---
	@(link_name="ImGui_IsWindowAbove")                              IsWindowAbove                              :: proc(potential_above: ^Window, potential_below: ^Window) -> bool                                      ---
	@(link_name="ImGui_IsWindowNavFocusable")                       IsWindowNavFocusable                       :: proc(window: ^Window) -> bool                                                                         ---
	@(link_name="ImGui_SetWindowPosImGuiWindowPtr")                 SetWindowPosImGuiWindowPtr                 :: proc(window: ^Window, pos: Vec2, cond: Cond = {})                                                     ---
	@(link_name="ImGui_SetWindowSizeImGuiWindowPtr")                SetWindowSizeImGuiWindowPtr                :: proc(window: ^Window, size: Vec2, cond: Cond = {})                                                    ---
	@(link_name="ImGui_SetWindowCollapsedImGuiWindowPtr")           SetWindowCollapsedImGuiWindowPtr           :: proc(window: ^Window, collapsed: bool, cond: Cond = {})                                               ---
	@(link_name="ImGui_SetWindowHitTestHole")                       SetWindowHitTestHole                       :: proc(window: ^Window, pos: Vec2, size: Vec2)                                                          ---
	@(link_name="ImGui_SetWindowHiddenAndSkipItemsForCurrentFrame") SetWindowHiddenAndSkipItemsForCurrentFrame :: proc(window: ^Window)                                                                                 ---
	@(link_name="ImGui_SetWindowParentWindowForFocusRoute")         SetWindowParentWindowForFocusRoute         :: proc(window: ^Window, parent_window: ^Window)                                                         --- // You may also use SetNextWindowClass()'s FocusRouteParentWindowId field.
	@(link_name="ImGui_WindowRectAbsToRel")                         WindowRectAbsToRel                         :: proc(window: ^Window, r: Rect) -> Rect                                                                ---
	@(link_name="ImGui_WindowRectRelToAbs")                         WindowRectRelToAbs                         :: proc(window: ^Window, r: Rect) -> Rect                                                                ---
	@(link_name="ImGui_WindowPosAbsToRel")                          WindowPosAbsToRel                          :: proc(window: ^Window, p: Vec2) -> Vec2                                                                ---
	@(link_name="ImGui_WindowPosRelToAbs")                          WindowPosRelToAbs                          :: proc(window: ^Window, p: Vec2) -> Vec2                                                                ---
	// Windows: Display Order and Focus Order
	@(link_name="ImGui_FocusWindow")                                 FocusWindow                                 :: proc(window: ^Window, flags: FocusRequestFlags = {})                                                           ---
	@(link_name="ImGui_FocusTopMostWindowUnderOne")                  FocusTopMostWindowUnderOne                  :: proc(under_this_window: ^Window, ignore_window: ^Window, filter_viewport: ^Viewport, flags: FocusRequestFlags) ---
	@(link_name="ImGui_BringWindowToFocusFront")                     BringWindowToFocusFront                     :: proc(window: ^Window)                                                                                          ---
	@(link_name="ImGui_BringWindowToDisplayFront")                   BringWindowToDisplayFront                   :: proc(window: ^Window)                                                                                          ---
	@(link_name="ImGui_BringWindowToDisplayBack")                    BringWindowToDisplayBack                    :: proc(window: ^Window)                                                                                          ---
	@(link_name="ImGui_BringWindowToDisplayBehind")                  BringWindowToDisplayBehind                  :: proc(window: ^Window, above_window: ^Window)                                                                   ---
	@(link_name="ImGui_FindWindowDisplayIndex")                      FindWindowDisplayIndex                      :: proc(window: ^Window) -> c.int                                                                                 ---
	@(link_name="ImGui_FindBottomMostVisibleWindowWithinBeginStack") FindBottomMostVisibleWindowWithinBeginStack :: proc(window: ^Window) -> ^Window                                                                               ---
	// Windows: Idle, Refresh Policies [EXPERIMENTAL]
	@(link_name="ImGui_SetNextWindowRefreshPolicy") SetNextWindowRefreshPolicy :: proc(flags: WindowRefreshFlags) ---
	// Fonts, drawing
	@(link_name="ImGui_SetCurrentFont")                      SetCurrentFont                      :: proc(font: ^Font)                                                               ---
	@(link_name="ImGui_GetDefaultFont")                      GetDefaultFont                      :: proc() -> ^Font                                                                 ---
	@(link_name="ImGui_GetForegroundDrawListImGuiWindowPtr") GetForegroundDrawListImGuiWindowPtr :: proc(window: ^Window) -> ^DrawList                                              ---
	@(link_name="ImGui_AddDrawListToDrawDataEx")             AddDrawListToDrawDataEx             :: proc(draw_data: ^DrawData, out_list: ^Vector_DrawListPtr, draw_list: ^DrawList) ---
	// Init
	@(link_name="ImGui_Initialize") Initialize :: proc() ---
	@(link_name="ImGui_Shutdown")   Shutdown   :: proc() --- // Since 1.60 this is a _private_ function. You can call DestroyContext() to destroy the context created by CreateContext().
	// NewFrame
	@(link_name="ImGui_UpdateInputEvents")                  UpdateInputEvents                  :: proc(trickle_fast_inputs: bool)                                                                                                       ---
	@(link_name="ImGui_UpdateHoveredWindowAndCaptureFlags") UpdateHoveredWindowAndCaptureFlags :: proc()                                                                                                                                ---
	@(link_name="ImGui_FindHoveredWindowEx")                FindHoveredWindowEx                :: proc(pos: Vec2, find_first_and_in_any_viewport: bool, out_hovered_window: ^^Window, out_hovered_window_under_moving_window: ^^Window) ---
	@(link_name="ImGui_StartMouseMovingWindow")             StartMouseMovingWindow             :: proc(window: ^Window)                                                                                                                 ---
	@(link_name="ImGui_StartMouseMovingWindowOrNode")       StartMouseMovingWindowOrNode       :: proc(window: ^Window, node: ^DockNode, undock: bool)                                                                                  ---
	@(link_name="ImGui_UpdateMouseMovingWindowNewFrame")    UpdateMouseMovingWindowNewFrame    :: proc()                                                                                                                                ---
	@(link_name="ImGui_UpdateMouseMovingWindowEndFrame")    UpdateMouseMovingWindowEndFrame    :: proc()                                                                                                                                ---
	// Generic context hooks
	@(link_name="ImGui_AddContextHook")    AddContextHook    :: proc(_context: ^Context, hook: ^ContextHook) -> ID ---
	@(link_name="ImGui_RemoveContextHook") RemoveContextHook :: proc(_context: ^Context, hook_to_remove: ID)       ---
	@(link_name="ImGui_CallContextHooks")  CallContextHooks  :: proc(_context: ^Context, type: ContextHookType)    ---
	// Viewports
	@(link_name="ImGui_TranslateWindowsInViewport")                 TranslateWindowsInViewport                 :: proc(viewport: ^ViewportP, old_pos: Vec2, new_pos: Vec2, old_size: Vec2, new_size: Vec2) ---
	@(link_name="ImGui_ScaleWindowsInViewport")                     ScaleWindowsInViewport                     :: proc(viewport: ^ViewportP, scale: f32)                                                   ---
	@(link_name="ImGui_DestroyPlatformWindow")                      DestroyPlatformWindow                      :: proc(viewport: ^ViewportP)                                                               ---
	@(link_name="ImGui_SetWindowViewport")                          SetWindowViewport                          :: proc(window: ^Window, viewport: ^ViewportP)                                              ---
	@(link_name="ImGui_SetCurrentViewport")                         SetCurrentViewport                         :: proc(window: ^Window, viewport: ^ViewportP)                                              ---
	@(link_name="ImGui_GetViewportPlatformMonitor")                 GetViewportPlatformMonitor                 :: proc(viewport: ^Viewport) -> ^PlatformMonitor                                            ---
	@(link_name="ImGui_FindHoveredViewportFromPlatformWindowStack") FindHoveredViewportFromPlatformWindowStack :: proc(mouse_platform_pos: Vec2) -> ^ViewportP                                             ---
	// Settings
	@(link_name="ImGui_MarkIniSettingsDirty")               MarkIniSettingsDirty               :: proc()                                       ---
	@(link_name="ImGui_MarkIniSettingsDirtyImGuiWindowPtr") MarkIniSettingsDirtyImGuiWindowPtr :: proc(window: ^Window)                        ---
	@(link_name="ImGui_ClearIniSettings")                   ClearIniSettings                   :: proc()                                       ---
	@(link_name="ImGui_AddSettingsHandler")                 AddSettingsHandler                 :: proc(handler: ^SettingsHandler)              ---
	@(link_name="ImGui_RemoveSettingsHandler")              RemoveSettingsHandler              :: proc(type_name: cstring)                     ---
	@(link_name="ImGui_FindSettingsHandler")                FindSettingsHandler                :: proc(type_name: cstring) -> ^SettingsHandler ---
	// Settings - Windows
	@(link_name="ImGui_CreateNewWindowSettings")    CreateNewWindowSettings    :: proc(name: cstring) -> ^WindowSettings   ---
	@(link_name="ImGui_FindWindowSettingsByID")     FindWindowSettingsByID     :: proc(id: ID) -> ^WindowSettings          ---
	@(link_name="ImGui_FindWindowSettingsByWindow") FindWindowSettingsByWindow :: proc(window: ^Window) -> ^WindowSettings ---
	@(link_name="ImGui_ClearWindowSettings")        ClearWindowSettings        :: proc(name: cstring)                      ---
	// Localization
	@(link_name="ImGui_LocalizeRegisterEntries") LocalizeRegisterEntries :: proc(entries: ^LocEntry, count: c.int) ---
	@(link_name="ImGui_LocalizeGetMsg")          LocalizeGetMsg          :: proc(key: LocKey) -> cstring           ---
	// Scrolling
	@(link_name="ImGui_SetScrollXImGuiWindowPtr")        SetScrollXImGuiWindowPtr        :: proc(window: ^Window, scroll_x: f32)                     ---
	@(link_name="ImGui_SetScrollYImGuiWindowPtr")        SetScrollYImGuiWindowPtr        :: proc(window: ^Window, scroll_y: f32)                     ---
	@(link_name="ImGui_SetScrollFromPosXImGuiWindowPtr") SetScrollFromPosXImGuiWindowPtr :: proc(window: ^Window, local_x: f32, center_x_ratio: f32) ---
	@(link_name="ImGui_SetScrollFromPosYImGuiWindowPtr") SetScrollFromPosYImGuiWindowPtr :: proc(window: ^Window, local_y: f32, center_y_ratio: f32) ---
	// Early work-in-progress API (ScrollToItem() will become public)
	@(link_name="ImGui_ScrollToItem")   ScrollToItem   :: proc(flags: ScrollFlags = {})                                      ---
	@(link_name="ImGui_ScrollToRect")   ScrollToRect   :: proc(window: ^Window, rect: Rect, flags: ScrollFlags = {})         ---
	@(link_name="ImGui_ScrollToRectEx") ScrollToRectEx :: proc(window: ^Window, rect: Rect, flags: ScrollFlags = {}) -> Vec2 ---
	//#ifndef IMGUI_DISABLE_OBSOLETE_FUNCTIONS
	@(link_name="ImGui_ScrollToBringRectIntoView") ScrollToBringRectIntoView :: proc(window: ^Window, rect: Rect) ---
	// Basic Accessors
	@(link_name="ImGui_GetItemStatusFlags") GetItemStatusFlags :: proc() -> ItemStatusFlags                                        ---
	@(link_name="ImGui_GetItemFlags")       GetItemFlags       :: proc() -> ItemFlags                                              ---
	@(link_name="ImGui_GetActiveID")        GetActiveID        :: proc() -> ID                                                     ---
	@(link_name="ImGui_GetFocusID")         GetFocusID         :: proc() -> ID                                                     ---
	@(link_name="ImGui_SetActiveID")        SetActiveID        :: proc(id: ID, window: ^Window)                                    ---
	@(link_name="ImGui_SetFocusID")         SetFocusID         :: proc(id: ID, window: ^Window)                                    ---
	@(link_name="ImGui_ClearActiveID")      ClearActiveID      :: proc()                                                           ---
	@(link_name="ImGui_GetHoveredID")       GetHoveredID       :: proc() -> ID                                                     ---
	@(link_name="ImGui_SetHoveredID")       SetHoveredID       :: proc(id: ID)                                                     ---
	@(link_name="ImGui_KeepAliveID")        KeepAliveID        :: proc(id: ID)                                                     ---
	@(link_name="ImGui_MarkItemEdited")     MarkItemEdited     :: proc(id: ID)                                                     --- // Mark data associated to given item as "edited", used by IsItemDeactivatedAfterEdit() function.
	@(link_name="ImGui_PushOverrideID")     PushOverrideID     :: proc(id: ID)                                                     --- // Push given value as-is at the top of the ID stack (whereas PushID combines old and new hashes)
	@(link_name="ImGui_GetIDWithSeedStr")   GetIDWithSeedStr   :: proc(str_id_begin: cstring, str_id_end: cstring, seed: ID) -> ID ---
	@(link_name="ImGui_GetIDWithSeed")      GetIDWithSeed      :: proc(n: c.int, seed: ID) -> ID                                   ---
	// Basic Helpers for widget code
	@(link_name="ImGui_ItemSize")                 ItemSize                 :: proc(size: Vec2, text_baseline_y: f32 = -1.0)                                          ---
	@(link_name="ImGui_ItemSizeImRect")           ItemSizeImRect           :: proc(bb: Rect, text_baseline_y: f32 = -1.0)                                            --- // FIXME: This is a misleading API since we expect CursorPos to be bb.Min.
	@(link_name="ImGui_ItemAdd")                  ItemAdd                  :: proc(bb: Rect, id: ID, nav_bb: ^Rect = nil, extra_flags: ItemFlags = {}) -> bool       ---
	@(link_name="ImGui_ItemHoverable")            ItemHoverable            :: proc(bb: Rect, id: ID, item_flags: ItemFlags) -> bool                                  ---
	@(link_name="ImGui_IsWindowContentHoverable") IsWindowContentHoverable :: proc(window: ^Window, flags: HoveredFlags = {}) -> bool                                ---
	@(link_name="ImGui_IsClippedEx")              IsClippedEx              :: proc(bb: Rect, id: ID) -> bool                                                         ---
	@(link_name="ImGui_SetLastItemData")          SetLastItemData          :: proc(item_id: ID, in_flags: ItemFlags, status_flags: ItemStatusFlags, item_rect: Rect) ---
	@(link_name="ImGui_CalcItemSize")             CalcItemSize             :: proc(size: Vec2, default_w: f32, default_h: f32) -> Vec2                               ---
	@(link_name="ImGui_CalcWrapWidthForPos")      CalcWrapWidthForPos      :: proc(pos: Vec2, wrap_pos_x: f32) -> f32                                                ---
	@(link_name="ImGui_PushMultiItemsWidths")     PushMultiItemsWidths     :: proc(components: c.int, width_full: f32)                                               ---
	@(link_name="ImGui_ShrinkWidths")             ShrinkWidths             :: proc(items: ^ShrinkWidthItem, count: c.int, width_excess: f32)                         ---
	// Parameter stacks (shared)
	@(link_name="ImGui_GetStyleVarInfo")               GetStyleVarInfo               :: proc(idx: StyleVar) -> ^DataVarInfo ---
	@(link_name="ImGui_BeginDisabledOverrideReenable") BeginDisabledOverrideReenable :: proc()                              ---
	@(link_name="ImGui_EndDisabledOverrideReenable")   EndDisabledOverrideReenable   :: proc()                              ---
	// Logging/Capture
	@(link_name="ImGui_LogBegin")                 LogBegin                 :: proc(flags: LogFlags, auto_open_depth: c.int)                --- // -> BeginCapture() when we design v2 api, for now stay under the radar by using the old name.
	@(link_name="ImGui_LogToBuffer")              LogToBuffer              :: proc(auto_open_depth: c.int = -1)                            --- // Start logging/capturing to internal buffer
	@(link_name="ImGui_LogRenderedText")          LogRenderedText          :: proc(ref_pos: ^Vec2, text: cstring, text_end: cstring = nil) ---
	@(link_name="ImGui_LogSetNextTextDecoration") LogSetNextTextDecoration :: proc(prefix: cstring, suffix: cstring)                       ---
	// Childs
	@(link_name="ImGui_BeginChildEx") BeginChildEx :: proc(name: cstring, id: ID, size_arg: Vec2, child_flags: ChildFlags, window_flags: WindowFlags) -> bool ---
	// Popups, Modals
	@(link_name="ImGui_BeginPopupEx")                   BeginPopupEx                   :: proc(id: ID, extra_window_flags: WindowFlags) -> bool                                                              ---
	@(link_name="ImGui_OpenPopupEx")                    OpenPopupEx                    :: proc(id: ID, popup_flags: PopupFlags)                                                                              ---
	@(link_name="ImGui_ClosePopupToLevel")              ClosePopupToLevel              :: proc(remaining: c.int, restore_focus_to_window_under_popup: bool)                                                  ---
	@(link_name="ImGui_ClosePopupsOverWindow")          ClosePopupsOverWindow          :: proc(ref_window: ^Window, restore_focus_to_window_under_popup: bool)                                               ---
	@(link_name="ImGui_ClosePopupsExceptModals")        ClosePopupsExceptModals        :: proc()                                                                                                             ---
	@(link_name="ImGui_IsPopupOpenID")                  IsPopupOpenID                  :: proc(id: ID, popup_flags: PopupFlags) -> bool                                                                      ---
	@(link_name="ImGui_GetPopupAllowedExtentRect")      GetPopupAllowedExtentRect      :: proc(window: ^Window) -> Rect                                                                                      ---
	@(link_name="ImGui_GetTopMostPopupModal")           GetTopMostPopupModal           :: proc() -> ^Window                                                                                                  ---
	@(link_name="ImGui_GetTopMostAndVisiblePopupModal") GetTopMostAndVisiblePopupModal :: proc() -> ^Window                                                                                                  ---
	@(link_name="ImGui_FindBlockingModal")              FindBlockingModal              :: proc(window: ^Window) -> ^Window                                                                                   ---
	@(link_name="ImGui_FindBestWindowPosForPopup")      FindBestWindowPosForPopup      :: proc(window: ^Window) -> Vec2                                                                                      ---
	@(link_name="ImGui_FindBestWindowPosForPopupEx")    FindBestWindowPosForPopupEx    :: proc(ref_pos: Vec2, size: Vec2, last_dir: ^Dir, r_outer: Rect, r_avoid: Rect, policy: PopupPositionPolicy) -> Vec2 ---
	// Tooltips
	@(link_name="ImGui_BeginTooltipEx")     BeginTooltipEx     :: proc(tooltip_flags: TooltipFlags, extra_window_flags: WindowFlags) -> bool ---
	@(link_name="ImGui_BeginTooltipHidden") BeginTooltipHidden :: proc() -> bool                                                             ---
	// Menus
	@(link_name="ImGui_BeginViewportSideBar") BeginViewportSideBar :: proc(name: cstring, viewport: ^Viewport, dir: Dir, size: f32, window_flags: WindowFlags) -> bool                   ---
	@(link_name="ImGui_BeginMenuWithIcon")    BeginMenuWithIcon    :: proc(label: cstring, icon: cstring, enabled: bool = true) -> bool                                                  ---
	@(link_name="ImGui_MenuItemWithIcon")     MenuItemWithIcon     :: proc(label: cstring, icon: cstring, shortcut: cstring = nil, selected: bool = false, enabled: bool = true) -> bool ---
	// Combos
	@(link_name="ImGui_BeginComboPopup")   BeginComboPopup   :: proc(popup_id: ID, bb: Rect, flags: ComboFlags) -> bool ---
	@(link_name="ImGui_BeginComboPreview") BeginComboPreview :: proc() -> bool                                          ---
	@(link_name="ImGui_EndComboPreview")   EndComboPreview   :: proc()                                                  ---
	// Keyboard/Gamepad Navigation
	@(link_name="ImGui_NavInitWindow")                           NavInitWindow                           :: proc(window: ^Window, force_reinit: bool)                                               ---
	@(link_name="ImGui_NavInitRequestApplyResult")               NavInitRequestApplyResult               :: proc()                                                                                  ---
	@(link_name="ImGui_NavMoveRequestButNoResultYet")            NavMoveRequestButNoResultYet            :: proc() -> bool                                                                          ---
	@(link_name="ImGui_NavMoveRequestSubmit")                    NavMoveRequestSubmit                    :: proc(move_dir: Dir, clip_dir: Dir, move_flags: NavMoveFlags, scroll_flags: ScrollFlags) ---
	@(link_name="ImGui_NavMoveRequestForward")                   NavMoveRequestForward                   :: proc(move_dir: Dir, clip_dir: Dir, move_flags: NavMoveFlags, scroll_flags: ScrollFlags) ---
	@(link_name="ImGui_NavMoveRequestResolveWithLastItem")       NavMoveRequestResolveWithLastItem       :: proc(result: ^NavItemData)                                                              ---
	@(link_name="ImGui_NavMoveRequestResolveWithPastTreeNode")   NavMoveRequestResolveWithPastTreeNode   :: proc(result: ^NavItemData, tree_node_data: ^TreeNodeStackData)                          ---
	@(link_name="ImGui_NavMoveRequestCancel")                    NavMoveRequestCancel                    :: proc()                                                                                  ---
	@(link_name="ImGui_NavMoveRequestApplyResult")               NavMoveRequestApplyResult               :: proc()                                                                                  ---
	@(link_name="ImGui_NavMoveRequestTryWrapping")               NavMoveRequestTryWrapping               :: proc(window: ^Window, move_flags: NavMoveFlags)                                         ---
	@(link_name="ImGui_NavHighlightActivated")                   NavHighlightActivated                   :: proc(id: ID)                                                                            ---
	@(link_name="ImGui_NavClearPreferredPosForAxis")             NavClearPreferredPosForAxis             :: proc(axis: Axis)                                                                        ---
	@(link_name="ImGui_SetNavCursorVisibleAfterMove")            SetNavCursorVisibleAfterMove            :: proc()                                                                                  ---
	@(link_name="ImGui_NavUpdateCurrentWindowIsScrollPushableX") NavUpdateCurrentWindowIsScrollPushableX :: proc()                                                                                  ---
	@(link_name="ImGui_SetNavWindow")                            SetNavWindow                            :: proc(window: ^Window)                                                                   ---
	@(link_name="ImGui_SetNavID")                                SetNavID                                :: proc(id: ID, nav_layer: NavLayer, focus_scope_id: ID, rect_rel: Rect)                   ---
	@(link_name="ImGui_SetNavFocusScope")                        SetNavFocusScope                        :: proc(focus_scope_id: ID)                                                                ---
	// Focus/Activation
	// This should be part of a larger set of API: FocusItem(offset = -1), FocusItemByID(id), ActivateItem(offset = -1), ActivateItemByID(id) etc. which are
	// much harder to design and implement than expected. I have a couple of private branches on this matter but it's not simple. For now implementing the easy ones.
	@(link_name="ImGui_FocusItem")        FocusItem        :: proc()       --- // Focus last item (no selection/activation).
	@(link_name="ImGui_ActivateItemByID") ActivateItemByID :: proc(id: ID) --- // Activate an item by ID (button, checkbox, tree node etc.). Activation is queued and processed on the next frame when the item is encountered again.
	// Inputs
	// FIXME: Eventually we should aim to move e.g. IsActiveIdUsingKey() into IsKeyXXX functions.
	@(link_name="ImGui_IsNamedKey")                      IsNamedKey                      :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_IsNamedKeyOrMod")                 IsNamedKeyOrMod                 :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_IsLegacyKey")                     IsLegacyKey                     :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_IsKeyboardKey")                   IsKeyboardKey                   :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_IsGamepadKey")                    IsGamepadKey                    :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_IsMouseKey")                      IsMouseKey                      :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_IsAliasKey")                      IsAliasKey                      :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_IsLRModKey")                      IsLRModKey                      :: proc(key: Key) -> bool                                                  ---
	@(link_name="ImGui_FixupKeyChord")                   FixupKeyChord                   :: proc(key_chord: KeyChord) -> KeyChord                                   ---
	@(link_name="ImGui_ConvertSingleModFlagToKey")       ConvertSingleModFlagToKey       :: proc(key: Key) -> Key                                                   ---
	@(link_name="ImGui_GetKeyDataImGuiContextPtr")       GetKeyDataImGuiContextPtr       :: proc(ctx: ^Context, key: Key) -> ^KeyData                               ---
	@(link_name="ImGui_GetKeyData")                      GetKeyData                      :: proc(key: Key) -> ^KeyData                                              ---
	@(link_name="ImGui_GetKeyChordName")                 GetKeyChordName                 :: proc(key_chord: KeyChord) -> cstring                                    ---
	@(link_name="ImGui_MouseButtonToKey")                MouseButtonToKey                :: proc(button: MouseButton) -> Key                                        ---
	@(link_name="ImGui_IsMouseDragPastThreshold")        IsMouseDragPastThreshold        :: proc(button: MouseButton, lock_threshold: f32 = -1.0) -> bool           ---
	@(link_name="ImGui_GetKeyMagnitude2d")               GetKeyMagnitude2d               :: proc(key_left: Key, key_right: Key, key_up: Key, key_down: Key) -> Vec2 ---
	@(link_name="ImGui_GetNavTweakPressedAmount")        GetNavTweakPressedAmount        :: proc(axis: Axis) -> f32                                                 ---
	@(link_name="ImGui_CalcTypematicRepeatAmount")       CalcTypematicRepeatAmount       :: proc(t0: f32, t1: f32, repeat_delay: f32, repeat_rate: f32) -> c.int    ---
	@(link_name="ImGui_GetTypematicRepeatRate")          GetTypematicRepeatRate          :: proc(flags: InputFlags, repeat_delay: ^f32, repeat_rate: ^f32)          ---
	@(link_name="ImGui_TeleportMousePos")                TeleportMousePos                :: proc(pos: Vec2)                                                         ---
	@(link_name="ImGui_SetActiveIdUsingAllKeyboardKeys") SetActiveIdUsingAllKeyboardKeys :: proc()                                                                  ---
	@(link_name="ImGui_IsActiveIdUsingNavDir")           IsActiveIdUsingNavDir           :: proc(dir: Dir) -> bool                                                  ---
	// [EXPERIMENTAL] Low-Level: Key/Input Ownership
	// - The idea is that instead of "eating" a given input, we can link to an owner id.
	// - Ownership is most often claimed as a result of reacting to a press/down event (but occasionally may be claimed ahead).
	// - Input queries can then read input by specifying ImGuiKeyOwner_Any (== 0), ImGuiKeyOwner_NoOwner (== -1) or a custom ID.
	// - Legacy input queries (without specifying an owner or _Any or _None) are equivalent to using ImGuiKeyOwner_Any (== 0).
	// - Input ownership is automatically released on the frame after a key is released. Therefore:
	//   - for ownership registration happening as a result of a down/press event, the SetKeyOwner() call may be done once (common case).
	//   - for ownership registration happening ahead of a down/press event, the SetKeyOwner() call needs to be made every frame (happens if e.g. claiming ownership on hover).
	// - SetItemKeyOwner() is a shortcut for common simple case. A custom widget will probably want to call SetKeyOwner() multiple times directly based on its interaction state.
	// - This is marked experimental because not all widgets are fully honoring the Set/Test idioms. We will need to move forward step by step.
	//   Please open a GitHub Issue to submit your usage scenario or if there's a use case you need solved.
	@(link_name="ImGui_GetKeyOwner")                    GetKeyOwner                    :: proc(key: Key) -> ID                                      ---
	@(link_name="ImGui_SetKeyOwner")                    SetKeyOwner                    :: proc(key: Key, owner_id: ID, flags: InputFlags = {})      ---
	@(link_name="ImGui_SetKeyOwnersForKeyChord")        SetKeyOwnersForKeyChord        :: proc(key: KeyChord, owner_id: ID, flags: InputFlags = {}) ---
	@(link_name="ImGui_SetItemKeyOwnerImGuiInputFlags") SetItemKeyOwnerImGuiInputFlags :: proc(key: Key, flags: InputFlags)                         --- // Set key owner to last item if it is hovered or active. Equivalent to 'if (IsItemHovered() || IsItemActive()) { SetKeyOwner(key, GetItemID());'.
	@(link_name="ImGui_TestKeyOwner")                   TestKeyOwner                   :: proc(key: Key, owner_id: ID) -> bool                      --- // Test that key is either not owned, either owned by 'owner_id'
	@(link_name="ImGui_GetKeyOwnerData")                GetKeyOwnerData                :: proc(ctx: ^Context, key: Key) -> ^KeyOwnerData            ---
	// [EXPERIMENTAL] High-Level: Input Access functions w/ support for Key/Input Ownership
	// - Important: legacy IsKeyPressed(ImGuiKey, bool repeat=true) _DEFAULTS_ to repeat, new IsKeyPressed() requires _EXPLICIT_ ImGuiInputFlags_Repeat flag.
	// - Expected to be later promoted to public API, the prototypes are designed to replace existing ones (since owner_id can default to Any == 0)
	// - Specifying a value for 'ImGuiID owner' will test that EITHER the key is NOT owned (UNLESS locked), EITHER the key is owned by 'owner'.
	//   Legacy functions use ImGuiKeyOwner_Any meaning that they typically ignore ownership, unless a call to SetKeyOwner() explicitly used ImGuiInputFlags_LockThisFrame or ImGuiInputFlags_LockUntilRelease.
	// - Binding generators may want to ignore those for now, or suffix them with Ex() until we decide if this gets moved into public API.
	@(link_name="ImGui_IsKeyDownID")                      IsKeyDownID                      :: proc(key: Key, owner_id: ID) -> bool                                    ---
	@(link_name="ImGui_IsKeyPressedImGuiInputFlags")      IsKeyPressedImGuiInputFlags      :: proc(key: Key, flags: InputFlags, owner_id: ID = {}) -> bool            --- // Important: when transitioning from old to new IsKeyPressed(): old API has "bool repeat = true", so would default to repeat. New API requiress explicit ImGuiInputFlags_Repeat.
	@(link_name="ImGui_IsKeyReleasedID")                  IsKeyReleasedID                  :: proc(key: Key, owner_id: ID) -> bool                                    ---
	@(link_name="ImGui_IsKeyChordPressedImGuiInputFlags") IsKeyChordPressedImGuiInputFlags :: proc(key_chord: KeyChord, flags: InputFlags, owner_id: ID = {}) -> bool ---
	@(link_name="ImGui_IsMouseDownID")                    IsMouseDownID                    :: proc(button: MouseButton, owner_id: ID) -> bool                         ---
	@(link_name="ImGui_IsMouseClickedImGuiInputFlags")    IsMouseClickedImGuiInputFlags    :: proc(button: MouseButton, flags: InputFlags, owner_id: ID = {}) -> bool ---
	@(link_name="ImGui_IsMouseReleasedID")                IsMouseReleasedID                :: proc(button: MouseButton, owner_id: ID) -> bool                         ---
	@(link_name="ImGui_IsMouseDoubleClickedID")           IsMouseDoubleClickedID           :: proc(button: MouseButton, owner_id: ID) -> bool                         ---
	// Shortcut Testing & Routing
	// - Set Shortcut() and SetNextItemShortcut() in imgui.h
	// - When a policy (except for ImGuiInputFlags_RouteAlways *) is set, Shortcut() will register itself with SetShortcutRouting(),
	//   allowing the system to decide where to route the input among other route-aware calls.
	//   (* using ImGuiInputFlags_RouteAlways is roughly equivalent to calling IsKeyChordPressed(key) and bypassing route registration and check)
	// - When using one of the routing option:
	//   - The default route is ImGuiInputFlags_RouteFocused (accept inputs if window is in focus stack. Deep-most focused window takes inputs. ActiveId takes inputs over deep-most focused window.)
	//   - Routes are requested given a chord (key + modifiers) and a routing policy.
	//   - Routes are resolved during NewFrame(): if keyboard modifiers are matching current ones: SetKeyOwner() is called + route is granted for the frame.
	//   - Each route may be granted to a single owner. When multiple requests are made we have policies to select the winning route (e.g. deep most window).
	//   - Multiple read sites may use the same owner id can all access the granted route.
	//   - When owner_id is 0 we use the current Focus Scope ID as a owner ID in order to identify our location.
	// - You can chain two unrelated windows in the focus stack using SetWindowParentWindowForFocusRoute()
	//   e.g. if you have a tool window associated to a document, and you want document shortcuts to run when the tool is focused.
	@(link_name="ImGui_ShortcutID")             ShortcutID             :: proc(key_chord: KeyChord, flags: InputFlags, owner_id: ID) -> bool ---
	@(link_name="ImGui_SetShortcutRouting")     SetShortcutRouting     :: proc(key_chord: KeyChord, flags: InputFlags, owner_id: ID) -> bool --- // owner_id needs to be explicit and cannot be 0
	@(link_name="ImGui_TestShortcutRouting")    TestShortcutRouting    :: proc(key_chord: KeyChord, owner_id: ID) -> bool                    ---
	@(link_name="ImGui_GetShortcutRoutingData") GetShortcutRoutingData :: proc(key_chord: KeyChord) -> ^KeyRoutingData                       ---
	// Docking
	// (some functions are only declared in imgui.cpp, see Docking section)
	@(link_name="ImGui_DockContextInitialize")              DockContextInitialize              :: proc(ctx: ^Context)                                                                                                                                        ---
	@(link_name="ImGui_DockContextShutdown")                DockContextShutdown                :: proc(ctx: ^Context)                                                                                                                                        ---
	@(link_name="ImGui_DockContextClearNodes")              DockContextClearNodes              :: proc(ctx: ^Context, root_id: ID, clear_settings_refs: bool)                                                                                                --- // Use root_id==0 to clear all
	@(link_name="ImGui_DockContextRebuildNodes")            DockContextRebuildNodes            :: proc(ctx: ^Context)                                                                                                                                        ---
	@(link_name="ImGui_DockContextNewFrameUpdateUndocking") DockContextNewFrameUpdateUndocking :: proc(ctx: ^Context)                                                                                                                                        ---
	@(link_name="ImGui_DockContextNewFrameUpdateDocking")   DockContextNewFrameUpdateDocking   :: proc(ctx: ^Context)                                                                                                                                        ---
	@(link_name="ImGui_DockContextEndFrame")                DockContextEndFrame                :: proc(ctx: ^Context)                                                                                                                                        ---
	@(link_name="ImGui_DockContextGenNodeID")               DockContextGenNodeID               :: proc(ctx: ^Context) -> ID                                                                                                                                  ---
	@(link_name="ImGui_DockContextQueueDock")               DockContextQueueDock               :: proc(ctx: ^Context, target: ^Window, target_node: ^DockNode, payload: ^Window, split_dir: Dir, split_ratio: f32, split_outer: bool)                        ---
	@(link_name="ImGui_DockContextQueueUndockWindow")       DockContextQueueUndockWindow       :: proc(ctx: ^Context, window: ^Window)                                                                                                                       ---
	@(link_name="ImGui_DockContextQueueUndockNode")         DockContextQueueUndockNode         :: proc(ctx: ^Context, node: ^DockNode)                                                                                                                       ---
	@(link_name="ImGui_DockContextProcessUndockWindow")     DockContextProcessUndockWindow     :: proc(ctx: ^Context, window: ^Window, clear_persistent_docking_ref: bool = true)                                                                            ---
	@(link_name="ImGui_DockContextProcessUndockNode")       DockContextProcessUndockNode       :: proc(ctx: ^Context, node: ^DockNode)                                                                                                                       ---
	@(link_name="ImGui_DockContextCalcDropPosForDocking")   DockContextCalcDropPosForDocking   :: proc(target: ^Window, target_node: ^DockNode, payload_window: ^Window, payload_node: ^DockNode, split_dir: Dir, split_outer: bool, out_pos: ^Vec2) -> bool ---
	@(link_name="ImGui_DockContextFindNodeByID")            DockContextFindNodeByID            :: proc(ctx: ^Context, id: ID) -> ^DockNode                                                                                                                   ---
	@(link_name="ImGui_DockNodeWindowMenuHandler_Default")  DockNodeWindowMenuHandler_Default  :: proc(ctx: ^Context, node: ^DockNode, tab_bar: ^TabBar)                                                                                                     ---
	@(link_name="ImGui_DockNodeBeginAmendTabBar")           DockNodeBeginAmendTabBar           :: proc(node: ^DockNode) -> bool                                                                                                                              ---
	@(link_name="ImGui_DockNodeEndAmendTabBar")             DockNodeEndAmendTabBar             :: proc()                                                                                                                                                     ---
	@(link_name="ImGui_DockNodeGetRootNode")                DockNodeGetRootNode                :: proc(node: ^DockNode) -> ^DockNode                                                                                                                         ---
	@(link_name="ImGui_DockNodeIsInHierarchyOf")            DockNodeIsInHierarchyOf            :: proc(node: ^DockNode, parent: ^DockNode) -> bool                                                                                                           ---
	@(link_name="ImGui_DockNodeGetDepth")                   DockNodeGetDepth                   :: proc(node: ^DockNode) -> c.int                                                                                                                             ---
	@(link_name="ImGui_DockNodeGetWindowMenuButtonId")      DockNodeGetWindowMenuButtonId      :: proc(node: ^DockNode) -> ID                                                                                                                                ---
	@(link_name="ImGui_GetWindowDockNode")                  GetWindowDockNode                  :: proc() -> ^DockNode                                                                                                                                        ---
	@(link_name="ImGui_GetWindowAlwaysWantOwnTabBar")       GetWindowAlwaysWantOwnTabBar       :: proc(window: ^Window) -> bool                                                                                                                              ---
	@(link_name="ImGui_BeginDocked")                        BeginDocked                        :: proc(window: ^Window, p_open: ^bool)                                                                                                                       ---
	@(link_name="ImGui_BeginDockableDragDropSource")        BeginDockableDragDropSource        :: proc(window: ^Window)                                                                                                                                      ---
	@(link_name="ImGui_BeginDockableDragDropTarget")        BeginDockableDragDropTarget        :: proc(window: ^Window)                                                                                                                                      ---
	@(link_name="ImGui_SetWindowDock")                      SetWindowDock                      :: proc(window: ^Window, dock_id: ID, cond: Cond)                                                                                                             ---
	// Docking - Builder function needs to be generally called before the node is used/submitted.
	// - The DockBuilderXXX functions are designed to _eventually_ become a public API, but it is too early to expose it and guarantee stability.
	// - Do not hold on ImGuiDockNode* pointers! They may be invalidated by any split/merge/remove operation and every frame.
	// - To create a DockSpace() node, make sure to set the ImGuiDockNodeFlags_DockSpace flag when calling DockBuilderAddNode().
	//   You can create dockspace nodes (attached to a window) _or_ floating nodes (carry its own window) with this API.
	// - DockBuilderSplitNode() create 2 child nodes within 1 node. The initial node becomes a parent node.
	// - If you intend to split the node immediately after creation using DockBuilderSplitNode(), make sure
	//   to call DockBuilderSetNodeSize() beforehand. If you don't, the resulting split sizes may not be reliable.
	// - Call DockBuilderFinish() after you are done.
	@(link_name="ImGui_DockBuilderDockWindow")              DockBuilderDockWindow              :: proc(window_name: cstring, node_id: ID)                                                                                   ---
	@(link_name="ImGui_DockBuilderGetNode")                 DockBuilderGetNode                 :: proc(node_id: ID) -> ^DockNode                                                                                            ---
	@(link_name="ImGui_DockBuilderGetCentralNode")          DockBuilderGetCentralNode          :: proc(node_id: ID) -> ^DockNode                                                                                            ---
	@(link_name="ImGui_DockBuilderAddNode")                 DockBuilderAddNode                 :: proc(node_id: ID = {}, flags: DockNodeFlags = {}) -> ID                                                                   ---
	@(link_name="ImGui_DockBuilderRemoveNode")              DockBuilderRemoveNode              :: proc(node_id: ID)                                                                                                         --- // Remove node and all its child, undock all windows
	@(link_name="ImGui_DockBuilderRemoveNodeDockedWindows") DockBuilderRemoveNodeDockedWindows :: proc(node_id: ID, clear_settings_refs: bool = true)                                                                       ---
	@(link_name="ImGui_DockBuilderRemoveNodeChildNodes")    DockBuilderRemoveNodeChildNodes    :: proc(node_id: ID)                                                                                                         --- // Remove all split/hierarchy. All remaining docked windows will be re-docked to the remaining root node (node_id).
	@(link_name="ImGui_DockBuilderSetNodePos")              DockBuilderSetNodePos              :: proc(node_id: ID, pos: Vec2)                                                                                              ---
	@(link_name="ImGui_DockBuilderSetNodeSize")             DockBuilderSetNodeSize             :: proc(node_id: ID, size: Vec2)                                                                                             ---
	@(link_name="ImGui_DockBuilderSplitNode")               DockBuilderSplitNode               :: proc(node_id: ID, split_dir: Dir, size_ratio_for_node_at_dir: f32, out_id_at_dir: ^ID, out_id_at_opposite_dir: ^ID) -> ID --- // Create 2 child nodes in this parent node.
	@(link_name="ImGui_DockBuilderCopyDockSpace")           DockBuilderCopyDockSpace           :: proc(src_dockspace_id: ID, dst_dockspace_id: ID, in_window_remap_pairs: ^Vector_const_charPtr)                            ---
	@(link_name="ImGui_DockBuilderCopyNode")                DockBuilderCopyNode                :: proc(src_node_id: ID, dst_node_id: ID, out_node_remap_pairs: ^Vector_ID)                                                  ---
	@(link_name="ImGui_DockBuilderCopyWindowSettings")      DockBuilderCopyWindowSettings      :: proc(src_name: cstring, dst_name: cstring)                                                                                ---
	@(link_name="ImGui_DockBuilderFinish")                  DockBuilderFinish                  :: proc(node_id: ID)                                                                                                         ---
	// [EXPERIMENTAL] Focus Scope
	// This is generally used to identify a unique input location (for e.g. a selection set)
	// There is one per window (automatically set in Begin), but:
	// - Selection patterns generally need to react (e.g. clear a selection) when landing on one item of the set.
	//   So in order to identify a set multiple lists in same window may each need a focus scope.
	//   If you imagine an hypothetical BeginSelectionGroup()/EndSelectionGroup() api, it would likely call PushFocusScope()/EndFocusScope()
	// - Shortcut routing also use focus scope as a default location identifier if an owner is not provided.
	// We don't use the ID Stack for this as it is common to want them separate.
	@(link_name="ImGui_PushFocusScope")       PushFocusScope       :: proc(id: ID) ---
	@(link_name="ImGui_PopFocusScope")        PopFocusScope        :: proc()       ---
	@(link_name="ImGui_GetCurrentFocusScope") GetCurrentFocusScope :: proc() -> ID --- // Focus scope we are outputting into, set by PushFocusScope()
	// Drag and Drop
	@(link_name="ImGui_IsDragDropActive")               IsDragDropActive               :: proc() -> bool                       ---
	@(link_name="ImGui_BeginDragDropTargetCustom")      BeginDragDropTargetCustom      :: proc(bb: Rect, id: ID) -> bool       ---
	@(link_name="ImGui_ClearDragDrop")                  ClearDragDrop                  :: proc()                               ---
	@(link_name="ImGui_IsDragDropPayloadBeingAccepted") IsDragDropPayloadBeingAccepted :: proc() -> bool                       ---
	@(link_name="ImGui_RenderDragDropTargetRect")       RenderDragDropTargetRect       :: proc(bb: Rect, item_clip_rect: Rect) ---
	// Typing-Select API
	// (provide Windows Explorer style "select items by typing partial name" + "cycle through items by typing same letter" feature)
	// (this is currently not documented nor used by main library, but should work. See "widgets_typingselect" in imgui_test_suite for usage code. Please let us know if you use this!)
	@(link_name="ImGui_GetTypingSelectRequest")              GetTypingSelectRequest              :: proc(flags: TypingSelectFlags) -> ^TypingSelectRequest                                                                                                                      ---
	@(link_name="ImGui_TypingSelectFindMatch")               TypingSelectFindMatch               :: proc(req: ^TypingSelectRequest, items_count: c.int, get_item_name_func: proc "c" (arg_0: rawptr, arg_1: c.int) -> cstring, user_data: rawptr, nav_item_idx: c.int) -> c.int ---
	@(link_name="ImGui_TypingSelectFindNextSingleCharMatch") TypingSelectFindNextSingleCharMatch :: proc(req: ^TypingSelectRequest, items_count: c.int, get_item_name_func: proc "c" (arg_0: rawptr, arg_1: c.int) -> cstring, user_data: rawptr, nav_item_idx: c.int) -> c.int ---
	@(link_name="ImGui_TypingSelectFindBestLeadingMatch")    TypingSelectFindBestLeadingMatch    :: proc(req: ^TypingSelectRequest, items_count: c.int, get_item_name_func: proc "c" (arg_0: rawptr, arg_1: c.int) -> cstring, user_data: rawptr) -> c.int                      ---
	// Box-Select API
	@(link_name="ImGui_BeginBoxSelect") BeginBoxSelect :: proc(scope_rect: Rect, window: ^Window, box_select_id: ID, ms_flags: MultiSelectFlags) -> bool ---
	@(link_name="ImGui_EndBoxSelect")   EndBoxSelect   :: proc(scope_rect: Rect, ms_flags: MultiSelectFlags)                                             ---
	// Multi-Select API
	@(link_name="ImGui_MultiSelectItemHeader")  MultiSelectItemHeader  :: proc(id: ID, p_selected: ^bool, p_button_flags: ^ButtonFlags)                                                                 ---
	@(link_name="ImGui_MultiSelectItemFooter")  MultiSelectItemFooter  :: proc(id: ID, p_selected: ^bool, p_pressed: ^bool)                                                                             ---
	@(link_name="ImGui_MultiSelectAddSetAll")   MultiSelectAddSetAll   :: proc(ms: ^MultiSelectTempData, selected: bool)                                                                                ---
	@(link_name="ImGui_MultiSelectAddSetRange") MultiSelectAddSetRange :: proc(ms: ^MultiSelectTempData, selected: bool, range_dir: c.int, first_item: SelectionUserData, last_item: SelectionUserData) ---
	@(link_name="ImGui_GetBoxSelectState")      GetBoxSelectState      :: proc(id: ID) -> ^BoxSelectState                                                                                               ---
	@(link_name="ImGui_GetMultiSelectState")    GetMultiSelectState    :: proc(id: ID) -> ^MultiSelectState                                                                                             ---
	// Internal Columns API (this is not exposed because we will encourage transitioning to the Tables API)
	@(link_name="ImGui_SetWindowClipRectBeforeSetChannel") SetWindowClipRectBeforeSetChannel :: proc(window: ^Window, clip_rect: Rect)                          ---
	@(link_name="ImGui_BeginColumns")                      BeginColumns                      :: proc(str_id: cstring, count: c.int, flags: OldColumnFlags = {}) --- // setup number of columns. use an identifier to distinguish multiple column sets. close with EndColumns().
	@(link_name="ImGui_EndColumns")                        EndColumns                        :: proc()                                                          --- // close columns
	@(link_name="ImGui_PushColumnClipRect")                PushColumnClipRect                :: proc(column_index: c.int)                                       ---
	@(link_name="ImGui_PushColumnsBackground")             PushColumnsBackground             :: proc()                                                          ---
	@(link_name="ImGui_PopColumnsBackground")              PopColumnsBackground              :: proc()                                                          ---
	@(link_name="ImGui_GetColumnsID")                      GetColumnsID                      :: proc(str_id: cstring, count: c.int) -> ID                       ---
	@(link_name="ImGui_FindOrCreateColumns")               FindOrCreateColumns               :: proc(window: ^Window, id: ID) -> ^OldColumns                    ---
	@(link_name="ImGui_GetColumnOffsetFromNorm")           GetColumnOffsetFromNorm           :: proc(columns: ^OldColumns, offset_norm: f32) -> f32             ---
	@(link_name="ImGui_GetColumnNormFromOffset")           GetColumnNormFromOffset           :: proc(columns: ^OldColumns, offset: f32) -> f32                  ---
	// Tables: Candidates for public API
	@(link_name="ImGui_TableOpenContextMenu")              TableOpenContextMenu              :: proc(column_n: c.int = -1)                                                                    ---
	@(link_name="ImGui_TableSetColumnWidth")               TableSetColumnWidth               :: proc(column_n: c.int, width: f32)                                                             ---
	@(link_name="ImGui_TableSetColumnSortDirection")       TableSetColumnSortDirection       :: proc(column_n: c.int, sort_direction: SortDirection, append_to_sort_specs: bool)              ---
	@(link_name="ImGui_TableGetHoveredRow")                TableGetHoveredRow                :: proc() -> c.int                                                                               --- // Retrieve *PREVIOUS FRAME* hovered row. This difference with TableGetHoveredColumn() is the reason why this is not public yet.
	@(link_name="ImGui_TableGetHeaderRowHeight")           TableGetHeaderRowHeight           :: proc() -> f32                                                                                 ---
	@(link_name="ImGui_TableGetHeaderAngledMaxLabelWidth") TableGetHeaderAngledMaxLabelWidth :: proc() -> f32                                                                                 ---
	@(link_name="ImGui_TablePushBackgroundChannel")        TablePushBackgroundChannel        :: proc()                                                                                        ---
	@(link_name="ImGui_TablePopBackgroundChannel")         TablePopBackgroundChannel         :: proc()                                                                                        ---
	@(link_name="ImGui_TableAngledHeadersRowEx")           TableAngledHeadersRowEx           :: proc(row_id: ID, angle: f32, max_label_width: f32, data: ^TableHeaderData, data_count: c.int) ---
	// Tables: Internals
	@(link_name="ImGui_GetCurrentTable")                                     GetCurrentTable                                     :: proc() -> ^Table                                                                                                                     ---
	@(link_name="ImGui_TableFindByID")                                       TableFindByID                                       :: proc(id: ID) -> ^Table                                                                                                               ---
	@(link_name="ImGui_BeginTableWithID")                                    BeginTableWithID                                    :: proc(name: cstring, id: ID, columns_count: c.int, flags: TableFlags = {}, outer_size: Vec2 = {0, 0}, inner_width: f32 = 0.0) -> bool ---
	@(link_name="ImGui_TableBeginInitMemory")                                TableBeginInitMemory                                :: proc(table: ^Table, columns_count: c.int)                                                                                            ---
	@(link_name="ImGui_TableBeginApplyRequests")                             TableBeginApplyRequests                             :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableSetupDrawChannels")                              TableSetupDrawChannels                              :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableUpdateLayout")                                   TableUpdateLayout                                   :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableUpdateBorders")                                  TableUpdateBorders                                  :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableUpdateColumnsWeightFromWidth")                   TableUpdateColumnsWeightFromWidth                   :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableDrawBorders")                                    TableDrawBorders                                    :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableDrawDefaultContextMenu")                         TableDrawDefaultContextMenu                         :: proc(table: ^Table, flags_for_section_to_display: TableFlags)                                                                        ---
	@(link_name="ImGui_TableBeginContextMenuPopup")                          TableBeginContextMenuPopup                          :: proc(table: ^Table) -> bool                                                                                                          ---
	@(link_name="ImGui_TableMergeDrawChannels")                              TableMergeDrawChannels                              :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableGetInstanceData")                                TableGetInstanceData                                :: proc(table: ^Table, instance_no: c.int) -> ^TableInstanceData                                                                        ---
	@(link_name="ImGui_TableGetInstanceID")                                  TableGetInstanceID                                  :: proc(table: ^Table, instance_no: c.int) -> ID                                                                                        ---
	@(link_name="ImGui_TableSortSpecsSanitize")                              TableSortSpecsSanitize                              :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableSortSpecsBuild")                                 TableSortSpecsBuild                                 :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableGetColumnNextSortDirection")                     TableGetColumnNextSortDirection                     :: proc(column: ^TableColumn) -> SortDirection                                                                                          ---
	@(link_name="ImGui_TableFixColumnSortDirection")                         TableFixColumnSortDirection                         :: proc(table: ^Table, column: ^TableColumn)                                                                                            ---
	@(link_name="ImGui_TableGetColumnWidthAuto")                             TableGetColumnWidthAuto                             :: proc(table: ^Table, column: ^TableColumn) -> f32                                                                                     ---
	@(link_name="ImGui_TableBeginRow")                                       TableBeginRow                                       :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableEndRow")                                         TableEndRow                                         :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableBeginCell")                                      TableBeginCell                                      :: proc(table: ^Table, column_n: c.int)                                                                                                 ---
	@(link_name="ImGui_TableEndCell")                                        TableEndCell                                        :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableGetCellBgRect")                                  TableGetCellBgRect                                  :: proc(table: ^Table, column_n: c.int) -> Rect                                                                                         ---
	@(link_name="ImGui_TableGetColumnNameImGuiTablePtr")                     TableGetColumnNameImGuiTablePtr                     :: proc(table: ^Table, column_n: c.int) -> cstring                                                                                      ---
	@(link_name="ImGui_TableGetColumnResizeID")                              TableGetColumnResizeID                              :: proc(table: ^Table, column_n: c.int, instance_no: c.int = {}) -> ID                                                                  ---
	@(link_name="ImGui_TableCalcMaxColumnWidth")                             TableCalcMaxColumnWidth                             :: proc(table: ^Table, column_n: c.int) -> f32                                                                                          ---
	@(link_name="ImGui_TableSetColumnWidthAutoSingle")                       TableSetColumnWidthAutoSingle                       :: proc(table: ^Table, column_n: c.int)                                                                                                 ---
	@(link_name="ImGui_TableSetColumnWidthAutoAll")                          TableSetColumnWidthAutoAll                          :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableRemove")                                         TableRemove                                         :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableGcCompactTransientBuffers")                      TableGcCompactTransientBuffers                      :: proc(table: ^Table)                                                                                                                  ---
	@(link_name="ImGui_TableGcCompactTransientBuffersImGuiTableTempDataPtr") TableGcCompactTransientBuffersImGuiTableTempDataPtr :: proc(table: ^TableTempData)                                                                                                          ---
	@(link_name="ImGui_TableGcCompactSettings")                              TableGcCompactSettings                              :: proc()                                                                                                                               ---
	// Tables: Settings
	@(link_name="ImGui_TableLoadSettings")               TableLoadSettings               :: proc(table: ^Table)                                  ---
	@(link_name="ImGui_TableSaveSettings")               TableSaveSettings               :: proc(table: ^Table)                                  ---
	@(link_name="ImGui_TableResetSettings")              TableResetSettings              :: proc(table: ^Table)                                  ---
	@(link_name="ImGui_TableGetBoundSettings")           TableGetBoundSettings           :: proc(table: ^Table) -> ^TableSettings                ---
	@(link_name="ImGui_TableSettingsAddSettingsHandler") TableSettingsAddSettingsHandler :: proc()                                               ---
	@(link_name="ImGui_TableSettingsCreate")             TableSettingsCreate             :: proc(id: ID, columns_count: c.int) -> ^TableSettings ---
	@(link_name="ImGui_TableSettingsFindByID")           TableSettingsFindByID           :: proc(id: ID) -> ^TableSettings                       ---
	// Tab Bars
	@(link_name="ImGui_GetCurrentTabBar")                                 GetCurrentTabBar                                 :: proc() -> ^TabBar                                                                                                                                                                                           ---
	@(link_name="ImGui_BeginTabBarEx")                                    BeginTabBarEx                                    :: proc(tab_bar: ^TabBar, bb: Rect, flags: TabBarFlags) -> bool                                                                                                                                                ---
	@(link_name="ImGui_TabBarFindTabByID")                                TabBarFindTabByID                                :: proc(tab_bar: ^TabBar, tab_id: ID) -> ^TabItem                                                                                                                                                              ---
	@(link_name="ImGui_TabBarFindTabByOrder")                             TabBarFindTabByOrder                             :: proc(tab_bar: ^TabBar, order: c.int) -> ^TabItem                                                                                                                                                            ---
	@(link_name="ImGui_TabBarFindMostRecentlySelectedTabForActiveWindow") TabBarFindMostRecentlySelectedTabForActiveWindow :: proc(tab_bar: ^TabBar) -> ^TabItem                                                                                                                                                                          ---
	@(link_name="ImGui_TabBarGetCurrentTab")                              TabBarGetCurrentTab                              :: proc(tab_bar: ^TabBar) -> ^TabItem                                                                                                                                                                          ---
	@(link_name="ImGui_TabBarGetTabOrder")                                TabBarGetTabOrder                                :: proc(tab_bar: ^TabBar, tab: ^TabItem) -> c.int                                                                                                                                                              ---
	@(link_name="ImGui_TabBarGetTabName")                                 TabBarGetTabName                                 :: proc(tab_bar: ^TabBar, tab: ^TabItem) -> cstring                                                                                                                                                            ---
	@(link_name="ImGui_TabBarAddTab")                                     TabBarAddTab                                     :: proc(tab_bar: ^TabBar, tab_flags: TabItemFlags, window: ^Window)                                                                                                                                            ---
	@(link_name="ImGui_TabBarRemoveTab")                                  TabBarRemoveTab                                  :: proc(tab_bar: ^TabBar, tab_id: ID)                                                                                                                                                                          ---
	@(link_name="ImGui_TabBarCloseTab")                                   TabBarCloseTab                                   :: proc(tab_bar: ^TabBar, tab: ^TabItem)                                                                                                                                                                       ---
	@(link_name="ImGui_TabBarQueueFocus")                                 TabBarQueueFocus                                 :: proc(tab_bar: ^TabBar, tab: ^TabItem)                                                                                                                                                                       ---
	@(link_name="ImGui_TabBarQueueFocusStr")                              TabBarQueueFocusStr                              :: proc(tab_bar: ^TabBar, tab_name: cstring)                                                                                                                                                                   ---
	@(link_name="ImGui_TabBarQueueReorder")                               TabBarQueueReorder                               :: proc(tab_bar: ^TabBar, tab: ^TabItem, offset: c.int)                                                                                                                                                        ---
	@(link_name="ImGui_TabBarQueueReorderFromMousePos")                   TabBarQueueReorderFromMousePos                   :: proc(tab_bar: ^TabBar, tab: ^TabItem, mouse_pos: Vec2)                                                                                                                                                      ---
	@(link_name="ImGui_TabBarProcessReorder")                             TabBarProcessReorder                             :: proc(tab_bar: ^TabBar) -> bool                                                                                                                                                                              ---
	@(link_name="ImGui_TabItemEx")                                        TabItemEx                                        :: proc(tab_bar: ^TabBar, label: cstring, p_open: ^bool, flags: TabItemFlags, docked_window: ^Window) -> bool                                                                                                  ---
	@(link_name="ImGui_TabItemCalcSizeStr")                               TabItemCalcSizeStr                               :: proc(label: cstring, has_close_button_or_unsaved_marker: bool) -> Vec2                                                                                                                                      ---
	@(link_name="ImGui_TabItemCalcSize")                                  TabItemCalcSize                                  :: proc(window: ^Window) -> Vec2                                                                                                                                                                               ---
	@(link_name="ImGui_TabItemBackground")                                TabItemBackground                                :: proc(draw_list: ^DrawList, bb: Rect, flags: TabItemFlags, col: u32)                                                                                                                                         ---
	@(link_name="ImGui_TabItemLabelAndCloseButton")                       TabItemLabelAndCloseButton                       :: proc(draw_list: ^DrawList, bb: Rect, flags: TabItemFlags, frame_padding: Vec2, label: cstring, tab_id: ID, close_button_id: ID, is_contents_visible: bool, out_just_closed: ^bool, out_text_clipped: ^bool) ---
	// Render helpers
	// AVOID USING OUTSIDE OF IMGUI.CPP! NOT FOR PUBLIC CONSUMPTION. THOSE FUNCTIONS ARE A MESS. THEIR SIGNATURE AND BEHAVIOR WILL CHANGE, THEY NEED TO BE REFACTORED INTO SOMETHING DECENT.
	// NB: All position are in absolute pixels coordinates (we are never using window coordinates internally)
	@(link_name="ImGui_RenderText")                           RenderText                           :: proc(pos: Vec2, text: cstring, text_end: cstring = nil, hide_text_after_hash: bool = true)                                                                          ---
	@(link_name="ImGui_RenderTextWrapped")                    RenderTextWrapped                    :: proc(pos: Vec2, text: cstring, text_end: cstring, wrap_width: f32)                                                                                                  ---
	@(link_name="ImGui_RenderTextClipped")                    RenderTextClipped                    :: proc(pos_min: Vec2, pos_max: Vec2, text: cstring, text_end: cstring, text_size_if_known: ^Vec2, align: Vec2 = {0, 0}, clip_rect: ^Rect = nil)                       ---
	@(link_name="ImGui_RenderTextClippedWithDrawList")        RenderTextClippedWithDrawList        :: proc(draw_list: ^DrawList, pos_min: Vec2, pos_max: Vec2, text: cstring, text_end: cstring, text_size_if_known: ^Vec2, align: Vec2 = {0, 0}, clip_rect: ^Rect = nil) ---
	@(link_name="ImGui_RenderTextEllipsis")                   RenderTextEllipsis                   :: proc(draw_list: ^DrawList, pos_min: Vec2, pos_max: Vec2, clip_max_x: f32, ellipsis_max_x: f32, text: cstring, text_end: cstring, text_size_if_known: ^Vec2)         ---
	@(link_name="ImGui_RenderFrame")                          RenderFrame                          :: proc(p_min: Vec2, p_max: Vec2, fill_col: u32, borders: bool = true, rounding: f32 = 0.0)                                                                            ---
	@(link_name="ImGui_RenderFrameBorder")                    RenderFrameBorder                    :: proc(p_min: Vec2, p_max: Vec2, rounding: f32 = 0.0)                                                                                                                 ---
	@(link_name="ImGui_RenderColorRectWithAlphaCheckerboard") RenderColorRectWithAlphaCheckerboard :: proc(draw_list: ^DrawList, p_min: Vec2, p_max: Vec2, fill_col: u32, grid_step: f32, grid_off: Vec2, rounding: f32 = 0.0, flags: DrawFlags = {})                     ---
	@(link_name="ImGui_RenderNavCursor")                      RenderNavCursor                      :: proc(bb: Rect, id: ID, flags: NavRenderCursorFlags)                                                                                                                 --- // Navigation highlight
	@(link_name="ImGui_FindRenderedTextEnd")                  FindRenderedTextEnd                  :: proc(text: cstring, text_end: cstring = nil) -> cstring                                                                                                             --- // Find the optional ## from which we stop displaying text.
	@(link_name="ImGui_RenderMouseCursor")                    RenderMouseCursor                    :: proc(pos: Vec2, scale: f32, mouse_cursor: MouseCursor, col_fill: u32, col_border: u32, col_shadow: u32)                                                             ---
	// Render helpers (those functions don't access any ImGui state!)
	@(link_name="ImGui_RenderArrow")                    RenderArrow                    :: proc(draw_list: ^DrawList, pos: Vec2, col: u32, dir: Dir, scale: f32 = 1.0)                         ---
	@(link_name="ImGui_RenderBullet")                   RenderBullet                   :: proc(draw_list: ^DrawList, pos: Vec2, col: u32)                                                     ---
	@(link_name="ImGui_RenderCheckMark")                RenderCheckMark                :: proc(draw_list: ^DrawList, pos: Vec2, col: u32, sz: f32)                                            ---
	@(link_name="ImGui_RenderArrowPointingAt")          RenderArrowPointingAt          :: proc(draw_list: ^DrawList, pos: Vec2, half_sz: Vec2, direction: Dir, col: u32)                      ---
	@(link_name="ImGui_RenderArrowDockMenu")            RenderArrowDockMenu            :: proc(draw_list: ^DrawList, p_min: Vec2, sz: f32, col: u32)                                          ---
	@(link_name="ImGui_RenderRectFilledRangeH")         RenderRectFilledRangeH         :: proc(draw_list: ^DrawList, rect: Rect, col: u32, x_start_norm: f32, x_end_norm: f32, rounding: f32) ---
	@(link_name="ImGui_RenderRectFilledWithHole")       RenderRectFilledWithHole       :: proc(draw_list: ^DrawList, outer: Rect, inner: Rect, col: u32, rounding: f32)                       ---
	@(link_name="ImGui_CalcRoundingFlagsForRectInRect") CalcRoundingFlagsForRectInRect :: proc(r_in: Rect, r_outer: Rect, threshold: f32) -> DrawFlags                                        ---
	// Widgets
	@(link_name="ImGui_TextEx")                TextEx                :: proc(text: cstring, text_end: cstring = nil, flags: TextFlags = {})                                                                             ---
	@(link_name="ImGui_ButtonWithFlags")       ButtonWithFlags       :: proc(label: cstring, size_arg: Vec2 = {0, 0}, flags: ButtonFlags = {}) -> bool                                                                  ---
	@(link_name="ImGui_ArrowButtonEx")         ArrowButtonEx         :: proc(str_id: cstring, dir: Dir, size_arg: Vec2, flags: ButtonFlags = {}) -> bool                                                                ---
	@(link_name="ImGui_ImageButtonWithFlags")  ImageButtonWithFlags  :: proc(id: ID, user_texture_id: TextureID, image_size: Vec2, uv0: Vec2, uv1: Vec2, bg_col: Vec4, tint_col: Vec4, flags: ButtonFlags = {}) -> bool ---
	@(link_name="ImGui_SeparatorEx")           SeparatorEx           :: proc(flags: SeparatorFlags, thickness: f32 = 1.0)                                                                                               ---
	@(link_name="ImGui_SeparatorTextEx")       SeparatorTextEx       :: proc(id: ID, label: cstring, label_end: cstring, extra_width: f32)                                                                              ---
	@(link_name="ImGui_CheckboxFlagsImS64Ptr") CheckboxFlagsImS64Ptr :: proc(label: cstring, flags: ^i64, flags_value: i64) -> bool                                                                                     ---
	@(link_name="ImGui_CheckboxFlagsImU64Ptr") CheckboxFlagsImU64Ptr :: proc(label: cstring, flags: ^u64, flags_value: u64) -> bool                                                                                     ---
	// Widgets: Window Decorations
	@(link_name="ImGui_CloseButton")             CloseButton             :: proc(id: ID, pos: Vec2) -> bool                                                                                                  ---
	@(link_name="ImGui_CollapseButton")          CollapseButton          :: proc(id: ID, pos: Vec2, dock_node: ^DockNode) -> bool                                                                            ---
	@(link_name="ImGui_Scrollbar")               Scrollbar               :: proc(axis: Axis)                                                                                                                 ---
	@(link_name="ImGui_ScrollbarEx")             ScrollbarEx             :: proc(bb: Rect, id: ID, axis: Axis, p_scroll_v: ^i64, avail_v: i64, contents_v: i64, draw_rounding_flags: DrawFlags = {}) -> bool ---
	@(link_name="ImGui_GetWindowScrollbarRect")  GetWindowScrollbarRect  :: proc(window: ^Window, axis: Axis) -> Rect                                                                                        ---
	@(link_name="ImGui_GetWindowScrollbarID")    GetWindowScrollbarID    :: proc(window: ^Window, axis: Axis) -> ID                                                                                          ---
	@(link_name="ImGui_GetWindowResizeCornerID") GetWindowResizeCornerID :: proc(window: ^Window, n: c.int) -> ID                                                                                            --- // 0..3: corners
	@(link_name="ImGui_GetWindowResizeBorderID") GetWindowResizeBorderID :: proc(window: ^Window, dir: Dir) -> ID                                                                                            ---
	// Widgets low-level behaviors
	@(link_name="ImGui_ButtonBehavior")   ButtonBehavior   :: proc(bb: Rect, id: ID, out_hovered: ^bool, out_held: ^bool, flags: ButtonFlags = {}) -> bool                                                                                      ---
	@(link_name="ImGui_DragBehavior")     DragBehavior     :: proc(id: ID, data_type: DataType, p_v: rawptr, v_speed: f32, p_min: rawptr, p_max: rawptr, format: cstring, flags: SliderFlags) -> bool                                           ---
	@(link_name="ImGui_SliderBehavior")   SliderBehavior   :: proc(bb: Rect, id: ID, data_type: DataType, p_v: rawptr, p_min: rawptr, p_max: rawptr, format: cstring, flags: SliderFlags, out_grab_bb: ^Rect) -> bool                           ---
	@(link_name="ImGui_SplitterBehavior") SplitterBehavior :: proc(bb: Rect, id: ID, axis: Axis, size1: ^f32, size2: ^f32, min_size1: f32, min_size2: f32, hover_extend: f32 = 0.0, hover_visibility_delay: f32 = 0.0, bg_col: u32 = 0) -> bool ---
	// Widgets: Tree Nodes
	@(link_name="ImGui_TreeNodeBehavior")       TreeNodeBehavior       :: proc(id: ID, flags: TreeNodeFlags, label: cstring, label_end: cstring = nil) -> bool ---
	@(link_name="ImGui_TreePushOverrideID")     TreePushOverrideID     :: proc(id: ID)                                                                         ---
	@(link_name="ImGui_TreeNodeGetOpen")        TreeNodeGetOpen        :: proc(storage_id: ID) -> bool                                                         ---
	@(link_name="ImGui_TreeNodeSetOpen")        TreeNodeSetOpen        :: proc(storage_id: ID, open: bool)                                                     ---
	@(link_name="ImGui_TreeNodeUpdateNextOpen") TreeNodeUpdateNextOpen :: proc(storage_id: ID, flags: TreeNodeFlags) -> bool                                   --- // Return open state. Consume previous SetNextItemOpen() data, if any. May return true when logging.
	// Data type helpers
	@(link_name="ImGui_DataTypeGetInfo")       DataTypeGetInfo       :: proc(data_type: DataType) -> ^DataTypeInfo                                                                        ---
	@(link_name="ImGui_DataTypeFormatString")  DataTypeFormatString  :: proc(buf: cstring, buf_size: c.int, data_type: DataType, p_data: rawptr, format: cstring) -> c.int                ---
	@(link_name="ImGui_DataTypeApplyOp")       DataTypeApplyOp       :: proc(data_type: DataType, op: c.int, output: rawptr, arg_1: rawptr, arg_2: rawptr)                                ---
	@(link_name="ImGui_DataTypeApplyFromText") DataTypeApplyFromText :: proc(buf: cstring, data_type: DataType, p_data: rawptr, format: cstring, p_data_when_empty: rawptr = nil) -> bool ---
	@(link_name="ImGui_DataTypeCompare")       DataTypeCompare       :: proc(data_type: DataType, arg_1: rawptr, arg_2: rawptr) -> c.int                                                  ---
	@(link_name="ImGui_DataTypeClamp")         DataTypeClamp         :: proc(data_type: DataType, p_data: rawptr, p_min: rawptr, p_max: rawptr) -> bool                                   ---
	@(link_name="ImGui_DataTypeIsZero")        DataTypeIsZero        :: proc(data_type: DataType, p_data: rawptr) -> bool                                                                 ---
	// InputText
	@(link_name="ImGui_InputTextWithHintAndSize") InputTextWithHintAndSize :: proc(label: cstring, hint: cstring, buf: cstring, buf_size: c.int, size_arg: Vec2, flags: InputTextFlags, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool ---
	@(link_name="ImGui_InputTextDeactivateHook")  InputTextDeactivateHook  :: proc(id: ID)                                                                                                                                                                  ---
	@(link_name="ImGui_TempInputText")            TempInputText            :: proc(bb: Rect, id: ID, label: cstring, buf: cstring, buf_size: c.int, flags: InputTextFlags) -> bool                                                                          ---
	@(link_name="ImGui_TempInputScalar")          TempInputScalar          :: proc(bb: Rect, id: ID, label: cstring, data_type: DataType, p_data: rawptr, format: cstring, p_clamp_min: rawptr = nil, p_clamp_max: rawptr = nil) -> bool                    ---
	@(link_name="ImGui_TempInputIsActive")        TempInputIsActive        :: proc(id: ID) -> bool                                                                                                                                                          ---
	@(link_name="ImGui_SetNextItemRefVal")        SetNextItemRefVal        :: proc(data_type: DataType, p_data: rawptr)                                                                                                                                     ---
	// Color
	@(link_name="ImGui_ColorTooltip")            ColorTooltip            :: proc(text: cstring, col: ^f32, flags: ColorEditFlags) ---
	@(link_name="ImGui_ColorEditOptionsPopup")   ColorEditOptionsPopup   :: proc(col: ^f32, flags: ColorEditFlags)                ---
	@(link_name="ImGui_ColorPickerOptionsPopup") ColorPickerOptionsPopup :: proc(ref_col: ^f32, flags: ColorEditFlags)            ---
	// Plot
	@(link_name="ImGui_PlotEx") PlotEx :: proc(plot_type: PlotType, label: cstring, values_getter: proc "c" (data: rawptr, idx: c.int) -> f32, data: rawptr, values_count: c.int, values_offset: c.int, overlay_text: cstring, scale_min: f32, scale_max: f32, size_arg: Vec2) -> c.int ---
	// Shade functions (write over already created vertices)
	@(link_name="ImGui_ShadeVertsLinearColorGradientKeepAlpha") ShadeVertsLinearColorGradientKeepAlpha :: proc(draw_list: ^DrawList, vert_start_idx: c.int, vert_end_idx: c.int, gradient_p0: Vec2, gradient_p1: Vec2, col0: u32, col1: u32) ---
	@(link_name="ImGui_ShadeVertsLinearUV")                     ShadeVertsLinearUV                     :: proc(draw_list: ^DrawList, vert_start_idx: c.int, vert_end_idx: c.int, a: Vec2, b: Vec2, uv_a: Vec2, uv_b: Vec2, clamp: bool)      ---
	@(link_name="ImGui_ShadeVertsTransformPos")                 ShadeVertsTransformPos                 :: proc(draw_list: ^DrawList, vert_start_idx: c.int, vert_end_idx: c.int, pivot_in: Vec2, cos_a: f32, sin_a: f32, pivot_out: Vec2)    ---
	// Garbage collection
	@(link_name="ImGui_GcCompactTransientMiscBuffers")   GcCompactTransientMiscBuffers   :: proc()                ---
	@(link_name="ImGui_GcCompactTransientWindowBuffers") GcCompactTransientWindowBuffers :: proc(window: ^Window) ---
	@(link_name="ImGui_GcAwakeTransientWindowBuffers")   GcAwakeTransientWindowBuffers   :: proc(window: ^Window) ---
	// Error handling, State Recovery
	@(link_name="ImGui_ErrorLog")                                            ErrorLog                                            :: proc(msg: cstring) -> bool           ---
	@(link_name="ImGui_ErrorRecoveryStoreState")                             ErrorRecoveryStoreState                             :: proc(state_out: ^ErrorRecoveryState) ---
	@(link_name="ImGui_ErrorRecoveryTryToRecoverState")                      ErrorRecoveryTryToRecoverState                      :: proc(state_in: ^ErrorRecoveryState)  ---
	@(link_name="ImGui_ErrorRecoveryTryToRecoverWindowState")                ErrorRecoveryTryToRecoverWindowState                :: proc(state_in: ^ErrorRecoveryState)  ---
	@(link_name="ImGui_ErrorCheckUsingSetCursorPosToExtendParentBoundaries") ErrorCheckUsingSetCursorPosToExtendParentBoundaries :: proc()                               ---
	@(link_name="ImGui_ErrorCheckEndFrameFinalizeErrorTooltip")              ErrorCheckEndFrameFinalizeErrorTooltip              :: proc()                               ---
	@(link_name="ImGui_BeginErrorTooltip")                                   BeginErrorTooltip                                   :: proc() -> bool                       ---
	@(link_name="ImGui_EndErrorTooltip")                                     EndErrorTooltip                                     :: proc()                               ---
	// Debug Tools
	@(link_name="ImGui_DebugAllocHook")                         DebugAllocHook                             :: proc(info: ^DebugAllocInfo, frame_count: c.int, ptr: rawptr, size: c.size_t)                                                             --- // size >= 0 : alloc, size = -1 : free
	@(link_name="ImGui_DebugDrawCursorPos")                     DebugDrawCursorPos                         :: proc(col: u32 = u32(0xff0000ff))                                                                                                         ---
	@(link_name="ImGui_DebugDrawLineExtents")                   DebugDrawLineExtents                       :: proc(col: u32 = u32(0xff0000ff))                                                                                                         ---
	@(link_name="ImGui_DebugDrawItemRect")                      DebugDrawItemRect                          :: proc(col: u32 = u32(0xff0000ff))                                                                                                         ---
	@(link_name="ImGui_DebugTextUnformattedWithLocateItem")     DebugTextUnformattedWithLocateItem         :: proc(line_begin: cstring, line_end: cstring)                                                                                             ---
	@(link_name="ImGui_DebugLocateItem")                        DebugLocateItem                            :: proc(target_id: ID)                                                                                                                      --- // Call sparingly: only 1 at the same time!
	@(link_name="ImGui_DebugLocateItemOnHover")                 DebugLocateItemOnHover                     :: proc(target_id: ID)                                                                                                                      --- // Only call on reaction to a mouse Hover: because only 1 at the same time!
	@(link_name="ImGui_DebugLocateItemResolveWithLastItem")     DebugLocateItemResolveWithLastItem         :: proc()                                                                                                                                   ---
	@(link_name="ImGui_DebugBreakClearData")                    DebugBreakClearData                        :: proc()                                                                                                                                   ---
	@(link_name="ImGui_DebugBreakButton")                       DebugBreakButton                           :: proc(label: cstring, description_of_location: cstring) -> bool                                                                           ---
	@(link_name="ImGui_DebugBreakButtonTooltip")                DebugBreakButtonTooltip                    :: proc(keyboard_only: bool, description_of_location: cstring)                                                                              ---
	@(link_name="ImGui_ShowFontAtlas")                          ShowFontAtlas                              :: proc(atlas: ^FontAtlas)                                                                                                                  ---
	@(link_name="ImGui_DebugHookIdInfo")                        DebugHookIdInfo                            :: proc(id: ID, data_type: DataType, data_id: rawptr, data_id_end: rawptr)                                                                  ---
	@(link_name="ImGui_DebugNodeColumns")                       DebugNodeColumns                           :: proc(columns: ^OldColumns)                                                                                                               ---
	@(link_name="ImGui_DebugNodeDockNode")                      DebugNodeDockNode                          :: proc(node: ^DockNode, label: cstring)                                                                                                    ---
	@(link_name="ImGui_DebugNodeDrawList")                      DebugNodeDrawList                          :: proc(window: ^Window, viewport: ^ViewportP, draw_list: ^DrawList, label: cstring)                                                        ---
	@(link_name="ImGui_DebugNodeDrawCmdShowMeshAndBoundingBox") DebugNodeDrawCmdShowMeshAndBoundingBox     :: proc(out_draw_list: ^DrawList, draw_list: ^DrawList, draw_cmd: ^DrawCmd, show_mesh: bool, show_aabb: bool)                               ---
	@(link_name="ImGui_DebugNodeFont")                          DebugNodeFont                              :: proc(font: ^Font)                                                                                                                        ---
	@(link_name="ImGui_DebugNodeFontGlyph")                     DebugNodeFontGlyph                         :: proc(font: ^Font, glyph: ^FontGlyph)                                                                                                     ---
	@(link_name="ImGui_DebugNodeStorage")                       DebugNodeStorage                           :: proc(storage: ^Storage, label: cstring)                                                                                                  ---
	@(link_name="ImGui_DebugNodeTabBar")                        DebugNodeTabBar                            :: proc(tab_bar: ^TabBar, label: cstring)                                                                                                   ---
	@(link_name="ImGui_DebugNodeTable")                         DebugNodeTable                             :: proc(table: ^Table)                                                                                                                      ---
	@(link_name="ImGui_DebugNodeTableSettings")                 DebugNodeTableSettings                     :: proc(settings: ^TableSettings)                                                                                                           ---
	@(link_name="ImGui_DebugNodeTypingSelectState")             DebugNodeTypingSelectState                 :: proc(state: ^TypingSelectState)                                                                                                          ---
	@(link_name="ImGui_DebugNodeMultiSelectState")              DebugNodeMultiSelectState                  :: proc(state: ^MultiSelectState)                                                                                                           ---
	@(link_name="ImGui_DebugNodeWindow")                        DebugNodeWindow                            :: proc(window: ^Window, label: cstring)                                                                                                    ---
	@(link_name="ImGui_DebugNodeWindowSettings")                DebugNodeWindowSettings                    :: proc(settings: ^WindowSettings)                                                                                                          ---
	@(link_name="ImGui_DebugNodeWindowsList")                   DebugNodeWindowsList                       :: proc(windows: ^Vector_WindowPtr, label: cstring)                                                                                         ---
	@(link_name="ImGui_DebugNodeWindowsListByBeginStackParent") DebugNodeWindowsListByBeginStackParent     :: proc(windows: ^^Window, windows_size: c.int, parent_in_begin_stack: ^Window)                                                             ---
	@(link_name="ImGui_DebugNodeViewport")                      DebugNodeViewport                          :: proc(viewport: ^ViewportP)                                                                                                               ---
	@(link_name="ImGui_DebugNodePlatformMonitor")               DebugNodePlatformMonitor                   :: proc(monitor: ^PlatformMonitor, label: cstring, idx: c.int)                                                                              ---
	@(link_name="ImGui_DebugRenderKeyboardPreview")             DebugRenderKeyboardPreview                 :: proc(draw_list: ^DrawList)                                                                                                               ---
	@(link_name="ImGui_DebugRenderViewportThumbnail")           DebugRenderViewportThumbnail               :: proc(draw_list: ^DrawList, viewport: ^ViewportP, bb: Rect)                                                                               ---
	@(link_name="cImFontAtlasGetBuilderForStbTruetype")         cImFontAtlasGetBuilderForStbTruetype       :: proc() -> ^FontBuilderIO                                                                                                                 ---
	@(link_name="cImFontAtlasUpdateConfigDataPointers")         cImFontAtlasUpdateConfigDataPointers       :: proc(atlas: ^FontAtlas)                                                                                                                  ---
	@(link_name="cImFontAtlasBuildInit")                        cImFontAtlasBuildInit                      :: proc(atlas: ^FontAtlas)                                                                                                                  ---
	@(link_name="cImFontAtlasBuildSetupFont")                   cImFontAtlasBuildSetupFont                 :: proc(atlas: ^FontAtlas, font: ^Font, font_config: ^FontConfig, ascent: f32, descent: f32)                                                ---
	@(link_name="cImFontAtlasBuildPackCustomRects")             cImFontAtlasBuildPackCustomRects           :: proc(atlas: ^FontAtlas, stbrp_context_opaque: rawptr)                                                                                    ---
	@(link_name="cImFontAtlasBuildFinish")                      cImFontAtlasBuildFinish                    :: proc(atlas: ^FontAtlas)                                                                                                                  ---
	@(link_name="cImFontAtlasBuildRender8bppRectFromString")    cImFontAtlasBuildRender8bppRectFromString  :: proc(atlas: ^FontAtlas, x: c.int, y: c.int, w: c.int, h: c.int, in_str: cstring, in_marker_char: c.char, in_marker_pixel_value: c.uchar) ---
	@(link_name="cImFontAtlasBuildRender32bppRectFromString")   cImFontAtlasBuildRender32bppRectFromString :: proc(atlas: ^FontAtlas, x: c.int, y: c.int, w: c.int, h: c.int, in_str: cstring, in_marker_char: c.char, in_marker_pixel_value: c.uint)  ---
	@(link_name="cImFontAtlasBuildMultiplyCalcLookupTable")     cImFontAtlasBuildMultiplyCalcLookupTable   :: proc(out_table: ^[256]c.uchar, in_multiply_factor: f32)                                                                                  ---
	@(link_name="cImFontAtlasBuildMultiplyRectAlpha8")          cImFontAtlasBuildMultiplyRectAlpha8        :: proc(table: ^[256]c.uchar, pixels: ^c.uchar, x: c.int, y: c.int, w: c.int, h: c.int, stride: c.int)                                      ---
}

////////////////////////////////////////////////////////////
// TYPEDEFS
////////////////////////////////////////////////////////////

// Our current column maximum is 64 but we may raise that in the future.
TableColumnIdx :: i16
FileHandle     :: ^c.FILE
BitArrayPtr    :: ^u32    // Name for use in structs
// Helper: ImPool<>
// Basic keyed storage for contiguous instances, slow/amortized insertion, O(1) indexable, O(Log N) queries by ID over a dense/hot buffer,
// Honor constructor/destructor. Add/remove invalidate all pointers. Indexes have the same lifetime as the associated object.
PoolIdx         :: c.int
KeyRoutingIndex :: i16
// The error callback is currently not public, as it is expected that only advanced users will rely on it.
ErrorCallback       :: proc "c" (ctx: ^Context, user_data: rawptr, msg: cstring) // Function signature for g.ErrorCallback
ContextHookCallback :: proc "c" (ctx: ^Context, hook: ^ContextHook)
TableDrawChannelIdx :: u16
